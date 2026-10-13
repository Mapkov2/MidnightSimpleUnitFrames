"""Execute allocation mutants against the real roster sampler, including both collected repeats."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
assert lua, "Lua 5.1 required (MSUF_LUA)"
source = (root / "tools/tests/group_roster_budget_smoke.lua").read_text(encoding="utf-8")
source = source.replace("local results = {}", """local results = {}
local probeCase
local probeStrings = {}
for i = 1, 256 do probeStrings[i] = false end
local probeSequence = 0""")
source = source.replace("local function Measure(case, fn, repeatable)",
                        "local function Measure(case, fn, repeatable)\n    probeCase = case")
source = source.replace("    return ticks, kb", """    if probeCase == "raid_settle" then print("ALLOC_SAMPLE", kb) end
    return ticks, kb""")
controls = {
    "tables": 'for i = 1, 256 do probeStrings[i] = {} end',
    # The review's exact temporary-string control. Strings lose every reference
    # before the KB reading; collection before each sample must still charge them.
    "temporary-strings": '''for i = 1, 96 do probeStrings[i] = string.format("%03d:" .. string.rep("z", 96), i) end
        for i = 1, 96 do probeStrings[i] = false end''',
    "unique-strings": '''probeSequence = probeSequence + 1
        for i = 1, 96 do
            probeStrings[i] = string.format("unique/%d/%03d:%s", probeSequence, i, string.rep("u", 96))
        end
        for i = 1, 96 do probeStrings[i] = false end''',
    "repeated-strings": '''for i = 1, 96 do
            local temporary = string.format("repeated/%03d:%s", i, string.rep("r", 96))
            probeStrings[i] = temporary
            probeStrings[i] = false
        end''',
}
problems = []
for name, allocation in {"production": "", **controls}.items():
    mutant = source.replace('    kb = collectgarbage("count") - kb',
                            '    if probeCase == "raid_settle" then ' + allocation +
                            '\n    end\n    kb = collectgarbage("count") - kb')
    run = subprocess.run([lua, "-", str(root), "Mainline"], input=mutant,
                         text=True, capture_output=True)
    samples = [float(x) for x in re.findall(r"ALLOC_SAMPLE\s+([\d.]+)", run.stdout)]
    assert len(samples) == 2, (name, run.stdout, run.stderr)
    if name == "production":
        valid = run.returncode == 0 and all(x <= 8 for x in samples)
    else:
        valid = (run.returncode != 0 and "raid_settle:" in run.stderr
                 and "KB allocated, budget 8 KB" in run.stderr and all(x > 8 for x in samples))
    if not valid:
        problems.append((name, samples, run.returncode, run.stderr))
    print(f"{name}: cold/steady {samples}; exit {run.returncode}", flush=True)
assert not problems, problems
print("PASS roster allocation controls: unchanged 8 KB limit, both repeats detect tables and transient strings")
