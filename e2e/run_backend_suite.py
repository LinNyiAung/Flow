"""Run every backend E2E suite against the running stubbed server and summarise.

Suites either print [PASS]/[BUG]/[FAIL] lines or record rows in api_results.json
(section, name, status, detail); both are counted. A suite that exits non-zero
is reported as CRASH.
"""
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
SUITES = ["test_api", "test_jobs", "test_jobs2", "test_regressions_all", "test_regressions2", "test_regressions3",
          "test_round3", "test_backend_r4", "test_round5", "test_sweep", "test_load", "test_burst_pooled", "test_premium_expiry", "test_money_lock", "test_app_download"]

res_path = os.path.join(HERE, "api_results.json")
if os.path.exists(res_path):
    os.remove(res_path)

printed = Counter()
problems = []
crashes = []
timing = {}
for name in SUITES:
    t0 = time.time()
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    p = subprocess.run([PY, "-u", os.path.join(HERE, name + ".py")], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=env, cwd=HERE, timeout=1800)
    timing[name] = time.time() - t0
    out = p.stdout + p.stderr
    with open(os.path.join(HERE, "logs_" + name + ".txt"), "w", encoding="utf-8") as f:
        f.write(out)
    for line in out.splitlines():
        m = re.match(r"\s*\[(PASS|BUG|FAIL|INFO)\]\s*(.*)", line)
        if m:
            printed[(name, m.group(1))] += 1
            if m.group(1) in ("BUG", "FAIL"):
                problems.append(f"{name}: {line.strip()[:300]}")
    if p.returncode != 0:
        tail = "\n    ".join(out.strip().splitlines()[-6:])
        crashes.append(f"{name} exited {p.returncode}:\n    {tail}")
    print(f"--- {name}: exit {p.returncode} in {timing[name]:.0f}s", flush=True)

rows = json.load(open(res_path, encoding="utf-8"))["results"] if os.path.exists(res_path) else []
by_section = Counter((r[0], r[2]) for r in rows)
print("\n== api_results.json sections ==")
for (sec, st), n in sorted(by_section.items()):
    print(f"  {sec:36} {st:5} {n}")
print("\n== printed checks per suite ==")
for (suite, st), n in sorted(printed.items()):
    print(f"  {suite:24} {st:5} {n}")
# Suites that only print; the others also record every check in api_results.json,
# so counting their printed lines too would double-count.
PRINT_ONLY = {"test_jobs2", "test_regressions2", "test_regressions3", "test_backend_r4", "test_round5", "test_premium_expiry", "test_money_lock", "test_app_download"}
total = Counter(r[2] for r in rows)
for (suite, st), n in printed.items():
    if suite in PRINT_ONLY:
        total[st] += n
print("\nTOTAL:", dict(total))
problems = [p for p in problems if p.split(":", 1)[0] in PRINT_ONLY]
for r in rows:
    if r[2] not in ("PASS", "INFO"):
        problems.append(f"{r[0]}: {r[1]} -- {r[3][:250]}")
print(f"\n== problems ({len(problems)}) ==")
for x in problems:
    print("  " + x)
print(f"\n== crashes ({len(crashes)}) ==")
for x in crashes:
    print("  " + x)
