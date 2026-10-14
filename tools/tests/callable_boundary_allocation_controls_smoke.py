"""Verify that hook-free complete-operation heap controls detect real allocations."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
assert lua, "Lua 5.1 required (MSUF_LUA)"
source = (root / "tools/tests/callable_boundary_heap_smoke.lua").read_text(encoding="utf-8")
assert "debug.sethook" not in source, "heap process must remain hook-free"
needle = "for i = 1, case.iterations do case.run() end"
assert source.count(needle) == 1
source = source.replace("local errors = {}", "local errors = {}\nlocal sequence = 0")
controls = {
    "tables": "local temporary = {}; temporary.value = i",
    "closures": "local temporary = function() return i end; assert(temporary() == i)",
    "transient-strings": 'sequence = sequence + 1; local temporary = string.format("allocation/%d/%d", sequence, i)',
}
for name, allocation in {"production": "", **controls}.items():
    # The real setter still executes on every iteration. Collection is stopped;
    # no retained result table or diagnostic hook is needed to charge garbage.
    body = "for i = 1, case.iterations do case.run()"
    if allocation:
        body += '\n            if case.name == "text:resolver" then ' + allocation + " end"
    body += "\n        end"
    run = subprocess.run([lua, "-", str(root), "Mainline"],
                         input=source.replace(needle, body), text=True, capture_output=True)
    samples = re.findall(r"Mainline\s+text:resolver\s+100\s+heap\s+([\d.]+)\s+([\d.]+)", run.stdout)
    assert len(samples) == 1, (name, run.stdout, run.stderr)
    first, second = map(float, samples[0])
    if name == "production":
        assert run.returncode == 0 and first == second == 0, (name, run.stderr, samples)
    else:
        assert run.returncode != 0 and first > 0 and second > 0, (name, run.stderr, samples)
        assert "text:resolver:" in run.stderr and "heap regression" in run.stderr, run.stderr
    print(f"{name}: heap samples {first}/{second} KiB; native exit {run.returncode}", flush=True)
print("PASS callable heap controls: both samples detect tables, closures and transient strings")
