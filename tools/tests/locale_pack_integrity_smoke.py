"""Every locale pack shows one translation per key, keeps the placeholders of the English text
and never ships a label made only of question marks.

A key assigned twice with different values is silently decided by load order (the last
assignment wins), so one copy is dead text that a translator may have fixed in vain. A
placeholder that the English value does not have, or one that is missing, makes
string.format raise or print a value in the wrong place. A value of only question marks is
an encoding accident that ships as a visible label.

Usage: python tools/tests/locale_pack_integrity_smoke.py <repo root>
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
LOCALES = ROOT / "MidnightSimpleUnitFrames" / "Locales"
ENTRY = re.compile(r'^\s*(?:L)?\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*(?:--.*)?$')
ANY = re.compile(r'(?:^|[\s;,{(])(?:L)?\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?[sdifgxXcq]|%%')


SYMBOLIC = re.compile(r"^[A-Z0-9_]+$")


def placeholder_mismatch(key, reference, value):
    """True when value's format specifiers differ from the English reference.
    Symbolic keys without an English value are skipped (the code owns their arguments).
    Alternation patterns ('a %s|b %s') compare the set of per-alternative counts."""
    if reference == key and SYMBOLIC.match(key):
        return False
    if "|" in reference and SYMBOLIC.match(key):
        ref = {len(PLACEHOLDER.findall(part)) for part in reference.split("|")}
        got = {len(PLACEHOLDER.findall(part)) for part in value.split("|")}
        return ref != got
    return sorted(PLACEHOLDER.findall(reference)) != sorted(PLACEHOLDER.findall(value))


def entries(path):
    text = path.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), 1):
        for match in ANY.finditer(line):
            yield number, match.group(1), match.group(2)


def placeholders(text):
    return sorted(PLACEHOLDER.findall(text))


english = {}
for _, key, value in entries(LOCALES / "enUS.lua"):
    english[key] = value  # the runtime keeps the last assignment

failures = []
packs = sorted(p for p in LOCALES.glob("*.lua") if re.fullmatch(r"[a-z]{2}[A-Z]{2}\.lua", p.name))
if len(packs) != 12:
    failures.append(f"expected 12 locale packs, found {len(packs)}: {[p.name for p in packs]}")
for pack in packs:
    seen = {}
    for number, key, value in entries(pack):
        seen.setdefault(key, []).append((number, value))
        reference = english.get(key, key)
        if placeholder_mismatch(key, reference, value):
            failures.append(f"{pack.name}:{number}: placeholders of {key!r} differ from enUS {reference!r}: {value!r}")
        if value.strip() and set(value.strip()) <= {"?", " "} and not set(key.strip()) <= {"?", " "}:
            failures.append(f"{pack.name}:{number}: {key!r} is only question marks")
    for key, rows in seen.items():
        if len({value for _, value in rows}) > 1:
            where = ", ".join(f"line {number}: {value!r}" for number, value in rows)
            failures.append(f"{pack.name}: {key!r} has conflicting translations ({where})")

if failures:
    for line in failures[:60]:
        print("FAIL " + line)
    if len(failures) > 60:
        print(f"... and {len(failures) - 60} more")
    sys.exit(f"locale pack integrity failed: {len(failures)} problems")
print(f"locale pack integrity: {len(packs)} packs, one translation per key, placeholders match enUS, no '?' labels")
