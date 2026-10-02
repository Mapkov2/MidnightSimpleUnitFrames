"""Gate step: the feature inventory over the real tree (tools/feature_inventory.py).

Usage: python tools/tests/feature_inventory_gate_smoke.py [repo root]

Fails when a setting, label, slash command, binding, locale key or export of the frozen baseline is
missing from the tree and has no entry in tools/feature_inventory_allowlist.json. Also proves the
frozen snapshot still equals a fresh extraction of its commit when that commit is in the clone
(a shallow CI clone uses the snapshot as frozen). Prints one summary line.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
TOOL = str(ROOT / "tools" / "feature_inventory.py")


def run(*arguments):
    done = subprocess.run([sys.executable, TOOL, "--root", str(ROOT)] + list(arguments), capture_output=True,
                          text=True, errors="replace")
    return done.returncode, (done.stdout + done.stderr).strip().splitlines()


code, lines = run()
if code:
    print("\n".join(lines[-60:]))
    sys.exit(code)
verify_code, verify_lines = run("--verify-baseline")
if verify_code:
    print("\n".join(verify_lines))
    sys.exit(verify_code)
print(lines[-1])
