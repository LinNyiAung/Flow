"""Per-book money lock in PostgreSQL (a row lock on the books row): serializes across processes, and each block is
all-or-nothing."""
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
from sql import books as books_db  # noqa: E402
from sql import transactions as transactions_db  # noqa: E402
from sql import users as users_db  # noqa: E402
from sql.db import dispose_engine  # noqa: E402
from utils import get_book_balance, get_book_money_lock, get_books_money_locks  # noqa: E402

HOLD_SECONDS = 1.5


def tx(book_id, amount, type_="inflow"):
    now = datetime.now(UTC)
    return {"_id": str(uuid.uuid4()), "book_id": book_id, "type": type_, "main_category": "Employment Income",
            "sub_category": "Salary", "amount": amount, "currency": "usd", "date": now, "description": "lock test",
            "created_at": now, "updated_at": now, "recurrence": None}


async def hold(book_id):
    """Child process: take the lock, say so, keep it for HOLD_SECONDS."""
    async with books_db.money_lock(book_id):
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
    book = await books_db.create_personal_book(uid)

    # 1. Another process holding the book's lock blocks this one until it releases.
    child = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "--hold", book],
                             stdout=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    wait_until_locked(child)
    t0 = time.monotonic()
    async with get_book_money_lock(book):
        waited = time.monotonic() - t0
    child.wait(timeout=30)
    check(waited >= HOLD_SECONDS * 0.6, "a second process waits for the book's money lock", f"waited {waited:.2f}s")

    # ...but other books are not blocked by it.
    other = str(uuid.uuid4())
    await users_db.insert_user({"_id": other, "name": "Other", "email": f"lock-{other[:8]}@example.com", "password": "x",
                                "is_verified": True, "created_at": datetime.now(UTC)})
    other_book = await books_db.create_personal_book(other)
    child = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "--hold", book],
                             stdout=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    wait_until_locked(child)
    t0 = time.monotonic()
    async with get_book_money_lock(other_book):
        waited = time.monotonic() - t0
    child.wait(timeout=30)
    check(waited < 0.5, "another book's lock is independent", f"waited {waited:.2f}s")

    # 2. The block sees its own writes (balance check after a write in the same block).
    seen = None
    try:
        async with get_book_money_lock(book):
            await transactions_db.insert_transaction(tx(book, 50))
            seen = (await get_book_balance(book, "usd"))["balance"]
            raise Boom()
    except Boom:
        pass
    check(seen == 50, "inside the lock, the balance includes the block's own write", f"saw {seen}")

    # 3. An error in the block rolls back everything it wrote (incl. a nested transaction()).
    after = (await get_book_balance(book, "usd"))["balance"]
    check(after == 0, "an exception inside the lock rolls back its writes", f"balance after rollback {after}")
    try:
        async with get_book_money_lock(book):
            await transactions_db.insert_many([tx(book, 5), tx(book, 7)])
            raise Boom()
    except Boom:
        pass
    check(await transactions_db.count_transactions(book) == 0, "a nested batch insert rolls back with the block")

    # 4. A clean block commits.
    async with get_book_money_lock(book):
        await transactions_db.insert_transaction(tx(book, 20))
    check((await get_book_balance(book, "usd"))["balance"] == 20, "a block that finishes commits its writes")

    # 5. Two concurrent overdrafts against 20 available: exactly one goal contribution-style
    #    spend fits (check-then-write under the lock), from two different processes' worth of locks.
    async def spend(amount):
        async with books_db.money_lock(book):  # the DB lock alone, as two server processes would hold it
            available = (await get_book_balance(book, "usd"))["available_balance"]
            await asyncio.sleep(0.3)  # widen the race window
            if amount <= available:
                await transactions_db.insert_transaction(tx(book, amount, "outflow"))
                return True
            return False

    outcomes = await asyncio.gather(spend(15), spend(15))
    final = (await get_book_balance(book, "usd"))["balance"]
    check(sorted(outcomes) == [False, True] and final == 5, "two concurrent 15 spends from 20: exactly one succeeds",
          f"outcomes={outcomes}, final balance={final}")

    # 6. Two books' locks taken in opposite orders (a transfer and its undo) never deadlock: get_books_money_locks
    #    sorts the ids, so the second block simply waits for the first.
    async def both(ids):
        async with get_books_money_locks(ids):
            await asyncio.sleep(0.3)
        return True

    t0 = time.monotonic()
    try:
        done = await asyncio.wait_for(asyncio.gather(both((book, other_book)), both((other_book, book))), timeout=15)
    except asyncio.TimeoutError:
        done = None
    took = time.monotonic() - t0
    check(done == [True, True] and took >= 0.55, "two books' locks in opposite orders: both blocks finish, one after the other",
          f"done={done}, took {took:.2f}s")

    # 7. A person's id is not a book: locking it holds no book's row (the book's lock is still free).
    child = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "--hold", uid],
                             stdout=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    wait_until_locked(child)
    t0 = time.monotonic()
    async with get_book_money_lock(book):
        waited = time.monotonic() - t0
    child.wait(timeout=30)
    check(waited < 0.5, "a lock on the person's id doesn't hold their book's lock", f"waited {waited:.2f}s")

    await users_db.delete_user(uid)  # the personal books and their entries cascade
    await users_db.delete_user(other)
    await dispose_engine()

asyncio.run(main())
print(f"{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
