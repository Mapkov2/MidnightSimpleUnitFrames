"""Run real group-page resets against the current embedded factory export."""
from __future__ import annotations

import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

from factory_ui_scale_defaults_smoke import CBORReader


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, (bytes, str)):
        data = value.encode("utf-8") if isinstance(value, str) else value
        return '"' + "".join(chr(b) if 32 <= b < 127 and b not in (34, 92)
                             else f"\\{b:03d}" for b in data) + '"'
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua(k)}]={lua(v)}" for k, v in value.items()) + "}"
    raise TypeError(type(value))


def main():
    root, flavor = Path(sys.argv[1]).resolve(), sys.argv[2]
    executable = os.environ.get("MSUF_LUA") or shutil.which("lua")
    assert executable, "Lua 5.1 missing; use tools/run-classic-gate.ps1 or set MSUF_LUA"
    version = subprocess.run([executable, "-e", "io.write(_VERSION)"], capture_output=True, check=True)
    assert version.stdout == b"Lua 5.1", "group reset contract requires Lua 5.1"
    name = "ForeverFactory" if flavor == "Forever" else "Shell"
    source = root / f"MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_{name}.lua"
    compact = re.search(rb"MSUF3:[A-Za-z0-9+/=]+", source.read_bytes())
    assert compact, "factory export missing"
    reader = CBORReader(zlib.decompress(base64.b64decode(compact[0][6:], validate=True), -15))
    decoded = reader.read()
    assert reader.offset == len(reader.data), "trailing factory CBOR"
    with tempfile.TemporaryDirectory(prefix="msuf-group-reset-") as directory:
        fixture = Path(directory) / "factory.lua"
        fixture.write_text("return " + lua(compact[0]) + "," + lua(decoded) + "\n", encoding="utf-8")
        contract = root / "tools/tests/group_page_reset_cases.lua"
        subprocess.run([executable, str(contract), root.as_posix(), flavor, str(fixture)],
                       check=True, timeout=120)


if __name__ == "__main__":
    main()
