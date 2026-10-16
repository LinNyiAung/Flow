"""Effect-based check: does the all-users weekly/monthly job generate insights for premium users with an expiry date?"""
import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, UTC
from types import SimpleNamespace as NS

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stubenv  # noqa: E402

os.chdir(stubenv.BACKEND)
import openai  # noqa: E402


class FakeCompletions:
    async def create(self, *a, **k):
        return NS(choices=[NS(message=NS(content="## Fake insight"), finish_reason="stop")],
                  usage=NS(prompt_tokens=1, completion_tokens=1, total_tokens=2))


class FakeAsyncOpenAI:
    def __init__(self, *a, **k):
        self.chat = NS(completions=FakeCompletions())


openai.AsyncOpenAI = FakeAsyncOpenAI

import insights_service as ins  # noqa: E402
I = __import__("pgcompat").async_collection("insights")  # insights live in PostgreSQL
U = __import__("pgcompat").async_collection("users")  # users live in PostgreSQL

stubenv.patch_loaded_modules()
HERE = os.path.dirname(os.path.abspath(__file__))
A = json.load(open(os.path.join(HERE, "api_results.json")))["state"]["A_id"]
RESULTS = []


def rec(name, status, detail=""):
    RESULTS.append(("Scheduler jobs", name, status, str(detail)[:500]))
    print(f"[{status}] {name}" + (f" -- {detail}" if detail else ""))


async def main():
    u = await U.find_one({"_id": A})
    print("A subscription:", u.get("subscription_type"), u.get("subscription_expires_at"))
    # control: same user but lifetime premium (no expiry)
    for label, expiry in (("trial user (has expiry)", u.get("subscription_expires_at") or datetime.now(UTC) + timedelta(days=20)),
                          ("lifetime premium (no expiry)", None)):
        await U.update_one({"_id": A}, {"$set": {"subscription_type": "premium", "subscription_expires_at": expiry}})
        await I.delete_many({"user_id": A})
        await ins.generate_weekly_insights_for_all_users()
        n = await I.count_documents({"user_id": A, "insight_type": "weekly"})
        rec(f"weekly all-users job generated insights for {label}", "PASS" if n else "BUG", f"{n} insight docs")
    await U.update_one({"_id": A}, {"$set": {"subscription_expires_at": datetime.now(UTC) + timedelta(days=20)}})


asyncio.run(main())
p = os.path.join(HERE, "api_results.json")
d = json.load(open(p))
d["results"] = [r for r in d["results"] if r[1] != "weekly insight job reached premium users"] + RESULTS
json.dump(d, open(p, "w"), indent=1, default=str)
