"""The full-downgrade entry point must enforce source bytes before loading Lua."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("historical", root / "tools/tests/historical_6503_source.py")
historical = importlib.util.module_from_spec(spec)
spec.loader.exec_module(historical)
source = Path(os.environ.get("MSUF_HISTORICAL_6503_DIR", str(historical.CACHE)))
assert historical.verify(source) == historical.TREE
parser = argparse.ArgumentParser()
parser.add_argument("--lua", default=os.environ.get("MSUF_LUA", "lua5.1"))
lua = parser.parse_args().lua
def preflight(path, success, message):
    env = dict(os.environ, MSUF_PYTHON=sys.executable, MSUF_HISTORICAL_6503_DIR=str(path))
    run = subprocess.run([lua, str(root / "tools/tests/profile_rollback_full_graph_smoke.lua"),
                          str(root), "Mainline", "--verify-source"], env=env, capture_output=True, text=True)
    assert (run.returncode == 0) == success, run.stdout + run.stderr
    assert message in run.stdout + run.stderr, run.stdout + run.stderr
preflight(source, True, historical.TREE)
with tempfile.TemporaryDirectory(prefix="historical-pin-") as directory:
    missing = Path(directory) / "missing"
    preflight(missing, False, "historical 6.503 source missing")
    missing.mkdir()
    (missing / "VERSION").write_bytes(b"6.503\n")
    preflight(missing, False, "historical 6.503 tree mismatch")
    # Independently compare the portable tree builder with Git on file/dir names
    # whose ordering differs when a directory separator is mishandled.
    fixture = Path(directory) / "tree"
    fixture.mkdir()
    for name in ("a.txt", "a/file", "Z", "a0"):
        path = fixture / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(name.encode())
    subprocess.run(["git", "init", "-q", str(fixture)], check=True)
    subprocess.run(["git", "-C", str(fixture), "-c", "core.autocrlf=false", "add", "."], check=True)
    expected = subprocess.check_output(["git", "-C", str(fixture), "write-tree"], text=True).strip()
    assert historical.tree_id(fixture) == expected, "tree builder differs from Git"
    (fixture / "a/file").write_bytes(b"tampered")
    assert historical.tree_id(fixture) != expected, "file tampering did not change tree"
print("PASS historical pin: full Lua preflight accepts exact tree and rejects missing/mismatched sources")
