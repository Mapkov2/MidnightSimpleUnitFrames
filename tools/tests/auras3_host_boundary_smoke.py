"""Auras3 hosts use the public surface; private fields stay in the owning backends."""
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
paths = subprocess.check_output(["git", "ls-files", "*.lua"], cwd=root, text=True).splitlines()
violations = []
for rel in paths:
    # These are the two Auras3 implementations, rather than host consumers.
    if rel.startswith(("MidnightSimpleUnitFrames/Auras3/", "MidnightSimpleUnitFrames/Game/Classic/Auras/")):
        continue
    if not rel.startswith(("MidnightSimpleUnitFrames/", "MidnightSimpleUnitFrames_Options/")):
        continue
    source = (root / rel).read_text(encoding="utf-8-sig")
    source = re.sub(r"--\[\[.*?\]\]|--[^\n]*", "", source, flags=re.S)
    aliases = {"A3", "a3"}
    for alias in re.findall(r"local\s+(\w+)\s*=\s*[^\n]*?(?:MSUF_Auras3|UF\.Auras3)\b", source):
        aliases.add(alias)
    assignments = re.findall(r"\blocal\s+(\w+)\s*=\s*(\w+)\s*(?:\n|$)", source)
    changed = True
    while changed:
        changed = False
        for target, owner in assignments:
            if owner in aliases and target not in aliases:
                aliases.add(target)
                changed = True
    names = "|".join(re.escape(name) for name in sorted(aliases))
    # Any namespace spelling of the module table counts as a host handle, and the
    # Runtime record plus underscore fields are private to the owning backends.
    owner = rf"(?:{names}|(?:\w+\.)*MSUF_Auras3|UF\.Auras3)"
    private = r"(?:_\w+|Runtime)"
    pattern = rf"\b{owner}\s*(?:\.\s*({private})\b|\[\s*['\"]({private})['\"]\s*\])"
    for match in re.finditer(pattern, source):
        violations.append(f"{rel}: private host access {match.group(0)}")
if violations:
    raise SystemExit("\n".join(violations))
print("auras3_host_boundary_smoke: ok (all tracked addon hosts)")
