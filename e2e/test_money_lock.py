"""Per-user money lock in PostgreSQL: serializes across processes, and each block is all-or-nothing."""
import asyncio
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime, UTC

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
from sql import transactions as transactions_db  # noqa: E402
from sql import users as users_db  # noqa: E402
from sql.db import dispose_engine  # noqa: E402
from utils import get_user_balance, get_user_money_lock  # noqa: E402

HOLD_SECONDS = 1.5


def tx(user_id, amount, type_="inflow"):
    now = datetime.now(UTC)
    return {"_id": str(uuid.uuid4()), "user_id": user_id, "type": type_, "main_category": "Employment Income",
            "sub_category": "Salary", "amount": amount, "currency": "usd", "date": now, "description": "lock test",
            "created_at": now, "updated_at": now, "recurrence": None}


async def hold(user_id):
    """Child process: take the lock, say so, keep it for HOLD_SECONDS."""
    async with users_db.money_lock(user_id):
        print("LOCKED", flush=True)
        await asyncio.sleep(HOLD_SECONDS)
    await dispose_engine()


if len(sys.argv) == 3 and sys.argv[1] == "--hold":
    asyncio.run(hold(sys.argv[2]))
    sys.exit(0)

results = []


def wait_until_locked(child):
    """Skip the backend's import-time banner lines until the child reports it holds the lock."""
    for line in child.stdout:
        if line.strip() == "LOCKED":
            return
    raise RuntimeError("lock holder exited without taking the lock")


def check(ok, name, detail=""):
    results.append(ok)
    print(("[PASS] " if ok else "[BUG] ") + name + (f" -- {detail}" if detail and not ok else ""), flush=True)


class Boom(Exception):
    pass


async def main():
    uid = str(uuid.uuid4())
    await users_db.insert_user({"_id": uid, "name": "Lock", "email": f"lock-{uid[:8]}@example.com", "password": "x",
                                "is_verified": True, "created_at": datetime.now(UTC)})

    # 1. Another process holding the user's lock blocks this one until it releases.
    child = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "--hold", uid],
                             stdout=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    wait_until_locked(child)
    t0 = time.monotonic()
    async with get_user_money_lock(uid):
        waited = time.monotonic() - t0
    child.wait(timeout=30)
    check(waited >= HOLD_SECONDS * 0.6, "a second process waits for the user's money lock", f"waited {waited:.2f}s")

    # ...but other users are not blocked by it.
    other = str(uuid.uuid4())
    await users_db.insert_user({"_id": other, "name": "Other", "email": f"lock-{other[:8]}@example.com", "password": "x",
                                "is_verified": True, "created_at": datetime.now(UTC)})
    child = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "--hold", uid],
                             stdout=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    wait_until_locked(child)
    t0 = time.monotonic()
    async with get_user_money_lock(other):
        waited = time.monotonic() - t0
    child.wait(timeout=30)
    check(waited < 0.5, "another user's lock is independent", f"waited {waited:.2f}s")

    # 2. The block sees its own writes (balance check after a write in the same block).
    seen = None
    try:
        async with get_user_money_lock(uid):
            await transactions_db.insert_transaction(tx(uid, 50))
            seen = (await get_user_balance(uid, "usd"))["balance"]
            raise Boom()
    except Boom:
        pass
    check(seen == 50, "inside the lock, the balance includes the block's own write", f"saw {seen}")

    # 3. An error in the block rolls back everything it wrote (incl. a nested transaction()).
    after = (await get_user_balance(uid, "usd"))["balance"]
    check(after == 0, "an exception inside the lock rolls back its writes", f"balance after rollback {after}")
    try:
        async with get_user_money_lock(uid):
            await transactions_db.insert_many([tx(uid, 5), tx(uid, 7)])
            raise Boom()
    except Boom:
        pass
    check(await transactions_db.count_transactions(uid) == 0, "a nested batch insert rolls back with the block")

    # 4. A clean block commits.
    async with get_user_money_lock(uid):
        await transactions_db.insert_transaction(tx(uid, 20))
    check((await get_user_balance(uid, "usd"))["balance"] == 20, "a block that finishes commits its writes")

    # 5. Two concurrent overdrafts against 20 available: exactly one goal contribution-style
    #    spend fits (check-then-write under the lock), from two different processes' worth of locks.
    async def spend(amount):
        async with users_db.money_lock(uid):  # the DB lock alone, as two server processes would hold it
            available = (await get_user_balance(uid, "usd"))["available_balance"]
            await asyncio.sleep(0.3)  # widen the race window
            if amount <= available:
                await transactions_db.insert_transaction(tx(uid, amount, "outflow"))
                return True
            return False

    outcomes = await asyncio.gather(spend(15), spend(15))
    final = (await get_user_balance(uid, "usd"))["balance"]
    check(sorted(outcomes) == [False, True] and final == 5, "two concurrent 15 spends from 20: exactly one succeeds",
          f"outcomes={outcomes}, final balance={final}")

    await users_db.delete_user(uid)
    await users_db.delete_user(other)
    await dispose_engine()


asyncio.run(main())
print(f"{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
