"""Report must preserve the real baseline check's exit status."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--luac", default=os.getenv("MSUF_LUAC"))
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="ratchet-report-") as directory:
    fixture = Path(directory)
    source = fixture / "MidnightSimpleUnitFrames/Test.lua"
    source.parent.mkdir()
    source.write_text("local value = 1\nreturn value\n", encoding="utf-8")
    (fixture / "tools").mkdir()
    command = [sys.executable, str(root / "tools/quality_ratchet.py"), "--root", str(fixture), "--profile", "classic", "--top", "0"]
    if args.luac:
        command += ["--luac", args.luac]
    def run(mode, success, detail=None):
        result = subprocess.run(command + [mode], text=True, capture_output=True)
        assert (result.returncode == 0) == success, mode + ": " + result.stdout + result.stderr
        if detail:
            assert detail in result.stdout, result.stdout
    run("--report", False, "no baseline")
    run("--update", True)
    run("--report", True)
    source.write_text("local value = _G.TestValue\nreturn value\n", encoding="utf-8")
    run("--check", False, "g_reads")
    run("--report", False, "g_reads")
    (fixture / "tools/quality_ratchet_baseline.json").write_text('{"metrics": [], "files": {}}', encoding="utf-8")
    run("--report", False, "baseline has no column")
print("PASS ratchet report: valid baseline accepted; missing, regressed and incomplete baselines rejected")
