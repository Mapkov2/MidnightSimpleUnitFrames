"""Decode the shipped factory exports: global UI scaling must start disabled.

The Lua factory tests stub the CBOR decoder, so they cannot catch an enabled
scale saved inside the real Forever export. This test reads both exports and
their portable/native sections without third-party Python dependencies.
"""
from __future__ import annotations

import base64
import re
import struct
import sys
import zlib
from pathlib import Path


class CBORReader:
    """Read the definite-length CBOR values used by the factory exports."""

    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, size: int) -> bytes:
        end = self.offset + size
        assert end <= len(self.data), "truncated factory CBOR"
        value = self.data[self.offset:end]
        self.offset = end
        return value

    def read(self):
        head = self.take(1)[0]
        major, extra = head >> 5, head & 31
        if major == 7:
            if extra in (20, 21):
                return extra == 21
            if extra in (22, 23):
                return None
            if extra in (25, 26, 27):
                fmt = {25: ">e", 26: ">f", 27: ">d"}[extra]
                return struct.unpack(fmt, self.take(struct.calcsize(fmt)))[0]
            raise AssertionError(f"unsupported CBOR simple value: {extra}")
        assert extra < 28, "indefinite factory CBOR is unsupported"
        size = extra if extra < 24 else int.from_bytes(self.take(1 << (extra - 24)), "big")
        if major == 0:
            return size
        if major == 1:
            return -1 - size
        if major == 2:
            return self.take(size)
        if major == 3:
            return self.take(size).decode("utf-8")
        if major == 4:
            return [self.read() for _ in range(size)]
        if major == 5:
            result = {}
            for _ in range(size):
                key = self.read()
                assert key not in result, "duplicate factory CBOR key"
                result[key] = self.read()
            return result
        raise AssertionError(f"unsupported factory CBOR major type: {major}")

def check_export(path: Path):
    match = re.search(rb"\[\[MSUF3:([A-Za-z0-9+/=]+)\]\]", path.read_bytes())
    assert match, f"{path.name}: factory export missing"
    reader = CBORReader(zlib.decompress(base64.b64decode(match[1], validate=True), -15))
    export = reader.read()
    assert reader.offset == len(reader.data), f"{path.name}: trailing factory CBOR"
    assert export[b"addon"] == b"MSUF" and export[b"fmt"] == 2, "unexpected factory export"
    for section, payload in (("portable", export[b"payload"]), ("native", export[b"msuf6"][b"payload"])):
        general = payload[b"general"]
        scale = general[b"UIScale"]
        label = f"{path.name} {section}"
        assert scale[b"Enabled"] is False, f"{label}: global UI scaling is enabled by default"
        assert scale[b"Scale"] == 1, f"{label}: disabled scale must start at 1"
        assert general[b"globalUiScalePreset"] == b"auto", f"{label}: global scale preset must be off"
        assert general.get(b"globalUiScaleValue") is None, f"{label}: global scale value must be absent"
        assert general[b"msufUiScale"] == 1, f"{label}: local frame scale must start at 1"
        print(f"PASS {label}: global UI scaling off")


if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve()
    defaults = root / "MidnightSimpleUnitFrames" / "State" / "Defaults"
    for filename in ("MSUF_Defaults_Shell.lua", "MSUF_Defaults_ForeverFactory.lua"):
        check_export(defaults / filename)
