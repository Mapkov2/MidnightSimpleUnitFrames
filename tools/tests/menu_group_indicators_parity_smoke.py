"""Replay whole-page observations captured from the original GroupIndicators builders."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

root, flavor = Path(sys.argv[1]), sys.argv[2]
lua = os.environ.get("MSUF_LUA") or shutil.which("lua")
assert lua, "Lua 5.1 executable missing"
expected = json.loads((root / "tools/fixtures/menu-group-indicators/parity.json").read_text())
assert expected["baseline"] == "76eb2c69ba22d15201df07eb863241666ed69b63"

total = 0
for width in (720, 1040):
    for state in ("default", "general", "edge"):
        key = f"{flavor}-{width}-{state}"
        with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
            run = subprocess.run(
                [lua, str(root / "tools/tests/menu_group_indicators_parity_world.lua"),
                 str(root), flavor, str(width), state],
                cwd=root, stdout=output, stderr=errors, check=False,
            )
            errors.seek(max(0, errors.tell() - 4096))
            assert run.returncode == 0, errors.read().decode(errors="replace")
            output.seek(0)
            digest, rows = hashlib.sha256(), 0
            for line in output:
                line = line.replace(b"\r\n", b"\n")
                digest.update(line)
                rows += line.count(b"\n")
        actual = {"sha256": digest.hexdigest(), "rows": rows}
        assert actual == expected["cases"][key], f"{key}: full-page observations differ: {actual}"
        total += actual["rows"]
print(f"menu_group_indicators_parity_smoke {flavor}: six exact full-page receipts, {total} rows")
