"""Replay whole-page observations from the original GroupIndicators builders.

Widget creation ordinals can shift when unrelated previews create fewer frames.
Canonicalise only widget:<digits> identities by first appearance within each case;
retain every row, field and repeated identity when comparing the full structure.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

def observation_receipt(output):
    identities = {}

    def canonical_widget(match):
        token = match.group()
        if token not in identities:
            identities[token] = f"widget:{len(identities) + 1}".encode("ascii")
        return identities[token]

    digest, rows = hashlib.sha256(), 0
    for line in output:
        line = line.replace(b"\r\n", b"\n")
        line = re.sub(rb"widget:[0-9]+", canonical_widget, line)
        digest.update(line)
        rows += line.count(b"\n")
    return {"sha256": digest.hexdigest(), "rows": rows}


def main():
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
                actual = observation_receipt(output)
            assert actual == expected["cases"][key], f"{key}: full-page observations differ: {actual}"
            total += actual["rows"]
    print(f"menu_group_indicators_parity_smoke {flavor}: six exact full-page receipts, {total} rows")


if __name__ == "__main__":
    main()
