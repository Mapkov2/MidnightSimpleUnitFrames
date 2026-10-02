"""Gate step: the quality ratchet over the real tree (tools/quality_ratchet.py --check).

Usage: python tools/tests/quality_ratchet_gate_smoke.py [repo root]

Prints the tool's one summary line; exits 1 on any regression, unlisted new-file violation or
malformed allowlist entry. After a merge the lead rebaselines with tools/quality_ratchet.py --update.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
run = subprocess.run([sys.executable, str(ROOT / "tools" / "quality_ratchet.py"), "--check", "--root", str(ROOT)],
                     capture_output=True, text=True, errors="replace")
lines = (run.stdout + run.stderr).strip().splitlines()
print("\n".join(lines[-40:] if run.returncode else lines[-1:]))
sys.exit(run.returncode)
