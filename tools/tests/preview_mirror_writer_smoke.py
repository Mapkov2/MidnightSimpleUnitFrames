"""Compatibility flag publication belongs exclusively to the request provider."""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
owner = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Preview.lua"
names = ["MSUF_UnitEditModeActive", "MSUF_PreviewTestMode", "MSUF_BossTestMode", "MSUF_ArenaTestMode",
         "MSUF2_BossUnitframePreviewActive", "MSUF2_ArenaUnitframePreviewActive", "MSUF_UnitPreviewActive"]
failures = []
for addon in ["MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options"]:
    for path in (root / addon).rglob("*.lua"):
        relative = path.relative_to(root).as_posix()
        if relative == owner:
            continue
        source = path.read_text(encoding="utf-8-sig")
        if relative == "MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua":
            # The Kernel's keep policy lists every exported name with `true` (also a global) or `false`
            # (namespace-only). A policy row publishes nothing; line numbers stay intact.
            source = re.sub(r"local GlobalExports = \{.*?\n\}\n", lambda m: "\n" * m.group(0).count("\n"),
                            source, count=1, flags=re.S)
        for name in names:
            patterns = [rf'\b{re.escape(name)}\s*=(?!=)',
                        rf'\[\s*["\']{re.escape(name)}["\']\s*\]\s*=(?!=)',
                        rf'\b(?:ExportPublic|PublishCompat|Export|Publish)\(\s*["\']{re.escape(name)}["\']\s*,']
            for pattern in patterns:
                for match in re.finditer(pattern, source):
                    line = source.count("\n", 0, match.start()) + 1
                    failures.append(f"{relative}:{line}: independent {name} writer")
provider_path = root / owner
if not provider_path.exists():
    failures.append("missing canonical request provider")
provider = provider_path.read_text() if provider_path.exists() else ""
for name in names:
    if f'ExportPublic("{name}", value)' not in provider:
        failures.append(f"missing canonical publication for {name}")
for forbidden in ["rawget(", "setmetatable(", "_G."]:
    if forbidden in provider:
        failures.append(f"request provider has forbidden global-input/interception surface: {forbidden}")
if failures:
    raise SystemExit("\n".join(failures))
print("PASS seven preview mirrors have one publisher; bare names and publication aliases checked")
