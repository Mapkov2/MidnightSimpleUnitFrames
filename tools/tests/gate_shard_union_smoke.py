"""The push-tier shards together run every push-tier smoke invocation exactly once.

CI splits the push tier into n jobs with `-Shard k/n`. This smoke lists the plan the gate would run
for the whole push tier and for every shard (the gate stops after the listing, so no smoke runs and
no static check repeats), and proves that
- the shards' lists add up to the whole list, each invocation exactly once, for the n the workflow
  uses and for a second n;
- no shard is empty and none carries a lopsided share of the weight (a broken or stale
  tools/classic-gate-weights.tsv shows up here);
- the workflow's matrix names every shard 1..n once and agrees with the n in its -Shard argument,
  so a shard that CI never runs cannot go unnoticed.

Usage: python tools/tests/gate_shard_union_smoke.py <repository root>
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

root = Path(sys.argv[1]).resolve()
GATE = root / "tools" / "test-classic-prototype.ps1"
WORKFLOW = root / ".github" / "workflows" / "classic-gate.yml"
TIER_ARGS = ["-SkipTier", "nightly"]
failures = []


def check(condition, message):
    print("  %s  %s" % ("ok  " if condition else "FAIL", message))
    if not condition:
        failures.append(message)


shell = shutil.which("pwsh") or shutil.which("powershell")


def listing(extra):
    """Runs the gate in listing mode; returns (invocations, share in percent or None, error text)."""
    command = [shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(GATE),
               "-SelfContained", "-ListSmokes"] + TIER_ARGS + extra
    process = subprocess.run(command, cwd=str(root), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines = process.stdout.decode("utf-8", "replace").splitlines()
    invocations = [re.sub(r"^LISTSMOKE \d+ \| ", "", line) for line in lines if line.startswith("LISTSMOKE ")]
    share = None
    for line in lines:
        found = re.match(r"LISTSHARD \S+ \| \d+ invocations \| (\d+)% of the weight", line)
        if found:
            share = int(found.group(1))
    error = ""
    if process.returncode != 0 or not invocations:
        error = "exit %d: %s" % (process.returncode, process.stderr.decode("utf-8", "replace").strip()[:300])
    return invocations, share, error


print("Push-tier shards (test-classic-prototype.ps1 -Shard)")
workflow = WORKFLOW.read_text(encoding="utf-8") if WORKFLOW.is_file() else ""
matrix = re.search(r"shard:\s*\[([0-9,\s]+)\]", workflow)
argument = re.search(r'-Shard\s+"\$\{\{\s*matrix\.shard\s*\}\}/(\d+)"', workflow)
check(matrix is not None and argument is not None, "the push job is a matrix of shards: %s" % WORKFLOW.relative_to(root).as_posix())
count = int(argument.group(1)) if argument else 0
listed = [int(item) for item in re.split(r"[,\s]+", matrix.group(1).strip()) if item] if matrix else []
check(count > 1 and listed == list(range(1, count + 1)),
      "the matrix names every shard 1..%d once (%s)" % (count, ", ".join(str(item) for item in listed)))
check("-SkipTier nightly" in workflow, "the push job leaves the nightly tier to the nightly workflow")

if shell is None or count < 2:
    check(False, "PowerShell is on PATH and the workflow names the shard count")
else:
    counts = [count, 2] if count != 2 else [count, 3]
    jobs = [("whole", [])] + [("%d/%d" % (k, n), ["-Shard", "%d/%d" % (k, n)]) for n in counts for k in range(1, n + 1)]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = dict(zip([name for name, _ in jobs], pool.map(lambda job: listing(job[1]), jobs)))
    whole, _, error = results["whole"]
    check(not error and len(whole) > 0, "the push tier lists its invocations (%d) %s" % (len(whole), error))
    for n in counts:
        parts = [results["%d/%d" % (k, n)] for k in range(1, n + 1)]
        errors = [part[2] for part in parts if part[2]]
        check(not errors, "every one of the %d shards lists its invocations %s" % (n, "; ".join(errors)[:300]))
        merged = Counter()
        for invocations, _, _ in parts:
            merged.update(invocations)
        reference = Counter(whole)
        missing = sum((reference - merged).values())
        extra = sum((merged - reference).values())
        check(missing == 0 and extra == 0,
              "%d shards together hold every push-tier invocation exactly once (%d listed, %d missing, %d extra)" % (
                  n, sum(merged.values()), missing, extra))
        check(all(len(part[0]) > 0 for part in parts), "no shard of %d is empty (%s)" % (n, ", ".join(str(len(p[0])) for p in parts)))
        shares = [part[1] for part in parts]
        expected = 100.0 / n
        check(all(share is not None and 0.5 * expected <= share <= 1.5 * expected for share in shares),
              "the weight splits evenly across %d shards (%s%% each, about %.0f%%)" % (
                  n, ", ".join(str(share) for share in shares), expected))

print()
if failures:
    print("gate shard union smoke: %d FAILED" % len(failures))
    for message in failures:
        print("  - " + message)
    sys.exit(1)
print("gate shard union smoke: ok")
