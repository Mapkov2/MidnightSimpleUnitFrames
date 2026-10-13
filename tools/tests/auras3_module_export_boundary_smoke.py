"""Runtime helpers export through named owners, rather than the A3 private bus."""
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
revision = sys.argv[2] if len(sys.argv) > 2 else None
prefix = "MidnightSimpleUnitFrames/Auras3/Runtime/"
command = ["git", "ls-tree", "-r", "--name-only", revision, prefix] if revision else ["git", "ls-files", prefix]
paths = subprocess.check_output(command, cwd=root, text=True).splitlines()
failures = []
for rel in paths:
    if not rel.endswith(".lua"):
        continue
    source = subprocess.check_output(["git", "show", f"{revision}:{rel}"], cwd=root, text=True) if revision else (
        root / rel).read_text(encoding="utf-8-sig")
    source = re.sub(r"--[^\n]*", "", source)
    pattern = r"(?:function\s+A3\._\w+\s*\(|A3\._[A-Z]\w*\s*=|A3\._\w+\s*=\s*function)"
    for match in re.finditer(pattern, source):
        failures.append(f"{rel}: private helper export {match.group(0)}")
if failures:
    raise SystemExit("\n".join(failures[:8]) + f"\nPrivate exports: {len(failures)}")
print("auras3_module_export_boundary_smoke: ok (named runtime owners)")
