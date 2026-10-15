"""Known native setter mutations must be rejected by the frozen per-preview oracle."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA") or os.environ.get("MSUF_LUA51") or shutil.which("lua")
if not LUA:
    raise SystemExit("Lua 5.1 is required")
CASES = [
    ("unit-player-default", "color"),
    ("unit-player-default", "position"),
    ("unit-player-default", "size"),
    ("unit-target-styled", "texcoord"),
    ("unit-player-default", "visibility"),
    ("unit-player-default", "font"),
    ("unit-player-default", "layer"),
    ("unit-player-default", "texture"),
    ("unit-target-styled", "mask"),
    ("unit-player-default", "value"),
    ("unit-player-native-portrait", "portrait"),
    ("unit-player-default", "text"),
    ("classpower-combo-circle", "alpha"),
    ("classpower-combo-circle", "size"),
    ("classpower-combo-circle", "visibility"),
    ("group-party-default", "extra"),
    ("group-party-default", "position"),
    ("group-party-default", "color"),
    ("castbar-target-channel", "texcoord"),
    ("castbar-player-normal", "font"),
]

validated = set()
for case, mutation in CASES:
    if case not in validated:
        baseline = subprocess.run([LUA, "tools/tests/preview_render_oracle_smoke.lua", str(ROOT), "Mainline", "--case", case],
                                  cwd=ROOT, capture_output=True, text=True)
        assert baseline.returncode == 0, "unmutated baseline already differs: " + baseline.stdout + baseline.stderr
        validated.add(case)
        print(f"BASELINE MATCH {case}", flush=True)
    command = [LUA, "tools/tests/preview_render_oracle_smoke.lua", str(ROOT), "Mainline",
               "--case", case, "--mutate", mutation]
    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    lines = run.stdout.splitlines()
    if run.returncode == 0 or not any(line.startswith("PREVIEW MISMATCH ") for line in lines):
        print(run.stdout + run.stderr)
        raise SystemExit(f"FAIL {case}/{mutation}: mutation escaped the comparator or never reached it")
    print(f"REJECTED {case}/{mutation} exit={run.returncode}", flush=True)
    for line in lines[:3]:
        print("  " + line, flush=True)
print(f"preview_oracle_mutation_smoke: ok ({len(CASES)} actual output mutations rejected)")
