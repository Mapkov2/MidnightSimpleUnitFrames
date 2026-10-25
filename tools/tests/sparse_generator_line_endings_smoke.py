"""Run both real sparse checks on LF/CRLF input copies; reject content drift.

Usage: python tools/tests/sparse_generator_line_endings_smoke.py <root> <lua51>
The caller owns the shared Lua slot. Subprocesses run strictly sequentially.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root, lua = Path(sys.argv[1]).resolve(), sys.argv[2]
data = "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_StorageData.lua"
inputs = (data, "tools/fixtures/defaults/schema.lua", "tools/profile_corpus_golden.lua",
          "tools/tests/profile_state_harness.lua")
original = {name: (root / name).read_bytes() for name in inputs}
scratch = Path("C:/tmp/m7")
with tempfile.TemporaryDirectory(prefix="sparse-eol-", dir=scratch if scratch.is_dir() else None) as directory:
    checkout = Path(directory)
    for newline in (b"\n", b"\r\n"):
        for name, raw in original.items():
            target = checkout / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw.replace(b"\r\n", b"\n").replace(b"\n", newline))
        target = checkout / data
        before = target.read_bytes()
        for version, marker in ((2, b"FROZEN SPARSE V2 DATA"), (3, b"SPARSE V3 INHERITED DEFAULTS")):
            command = [lua, str(root / "tools/defaults_schema_generate.lua"), str(checkout),
                       "--check", "--sparse-v" + str(version)]
            result = subprocess.run(command, capture_output=True, text=True)
            assert result.returncode == 0, (newline, version, result.stdout, result.stderr)
            assert target.read_bytes() == before, "check rewrote its input"
            # Only a comment changes: the V3 wire parser still loads, but exact
            # generated content must fail independently of newline normalization.
            changed = before.replace(b"-- BEGIN " + marker + newline,
                                     b"-- BEGIN " + marker + newline + b"-- stale" + newline, 1)
            assert changed != before
            target.write_bytes(changed)
            result = subprocess.run(command, capture_output=True, text=True)
            assert result.returncode != 0 and "differ" in result.stderr, (version, result.stdout, result.stderr)
            assert target.read_bytes() == changed, "failed check rewrote its input"
            target.write_bytes(before)
        print("PASS sparse V2/V3 checks and content rejection:", repr(newline))
assert all((root / name).read_bytes() == raw for name, raw in original.items()), "source inputs changed"
