"""Require real, TOC-loaded providers for explicit MSUF service doubles."""
import re
from pathlib import Path
from load_order import ROOT, ordered
from error_paths import tokens


def declarations(source):
    # Preserve code and string literals; erase comments using lexical offsets.
    found = set()
    alias_ranges = [match.span() for match in re.finditer(
        r"local (?:GF_PUBLIC_ALIASES|STATUS_REFRESH_ALIASES)\s*=\s*\{.*?\n\}", source, re.S)]
    for token, offset in tokens(source):
        if not token.startswith("MSUF_") or not re.fullmatch(r"MSUF_\w+", token):
            continue
        before, after = source[max(0, offset - 90):offset], source[offset + len(token):]
        # Global function declarations and assignments, including the G alias.
        declaration = re.search(r"\b(?:(local)\s+)?function\s+(?:(?:_G|G)\.)?$", before)
        if declaration and not declaration[1]:
            found.add(token)
        elif re.search(r"(?:_G|G)\.$", before) and re.match(r"\s*=(?!=)", after):
            found.add(token)
        # Direct export literals, including local Export = MSUF.ExportPublic.
        elif re.search(r"(?:ExportPublic|Export)\(\s*$", before):
            found.add(token)
        # Explicit exported alias/name tables (the following export loop uses it).
        elif source[offset:offset + 1] in "\"'" and any(start <= offset < end for start, end in alias_ranges):
            found.add(token)
    return found


assert declarations("-- function MSUF_Fake() end\nlocal function MSUF_Private() end") == set()
assert declarations('ExportPublic("MSUF_Real", impl)') == {"MSUF_Real"}


providers = {}
for path in ordered:
    for name in declarations(path.read_text(encoding="utf-8-sig")):
        providers.setdefault(name, []).append(path)

assert "MSUF_UpdateCastbarVisuals_Immediate" in providers
assert "MSUF_ScheduleDelayOnce" not in providers
assert "MSUF_SetStatusIconStyleUseMidnight" not in providers

requests = set()
for path in (path for folder in (".github/quality", ".github/scripts", "tools") for path in (ROOT / folder).rglob("*.lua")):
    source = path.read_text(encoding="utf-8-sig")
    if "service_ports.lua" not in source and path.name != "service_ports.lua":
        continue
    for match in re.finditer(r"\b\w+\.Install\(\s*(?:\[\[(.*?)\]\]|\"([^\"]*)\")", source, re.S):
        requests.update((match[1] or match[2]).split())
missing = sorted(requests - providers.keys())
assert not missing, "Invented MSUF test service(s), load the real provider: " + ", ".join(missing)

core_contract = ROOT / "MidnightSimpleUnitFrames/Kernel/MSUF_RuntimeContracts.lua"
source = core_contract.read_text(encoding="utf-8-sig")
required = re.findall(r'"(MSUF_\w+)"', source)
for name in required:
    assert name in providers, "Required runtime export has no loaded provider: " + name
    assert any(ordered.index(owner) < ordered.index(core_contract) for owner in providers[name]), name
assert ordered.index(core_contract) < next(i for i, path in enumerate(ordered) if "MidnightSimpleUnitFrames_Options" in path.parts)
print(f"PASS export ownership: {len(requests)} explicit test services and {len(required)} late core dependencies")
