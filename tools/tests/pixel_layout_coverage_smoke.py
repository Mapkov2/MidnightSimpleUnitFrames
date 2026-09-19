"""Guard every owned UI creation site, including future preview/widget additions.

Lua strings/comments (including secure snippets) are not executable constructors.
Explicit exceptions pin only nonvisual event drivers and measurement probes.
The native rendering contract is exercised separately by pixel_layout_profile_smoke.
"""
import collections
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
POLICY = ROOT / "tools/pixel-layout-exclusions.json"
CREATORS = {"CreateFrame", "CreateTexture", "CreateFontString", "CreateLine"}
SETTERS = {"SetBackdrop", "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture",
           "SetDisabledTexture", "SetThumbTexture"}


LONG_OPEN = re.compile(r"\[(=*)\[")
WORD = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")

def tokens(source):
    out = []
    pos = 0
    while pos < len(source):
        if source[pos].isspace():
            pos += 1
            continue
        comment = source.startswith("--", pos)
        start = pos + 2 if comment else pos
        long = LONG_OPEN.match(source, start)
        if long:
            end = source.find("]" + long[1] + "]", long.end())
            if end < 0:
                raise AssertionError("unterminated Lua long string/comment")
            end += len(long[1]) + 2
            if not comment:
                out.append(("string", source[pos:end], pos))
            pos = end
            continue
        if comment:
            end = source.find("\n", pos)
            pos = len(source) if end < 0 else end + 1
            continue
        if source[pos] in "\"'":
            quote, end = source[pos], pos + 1
            while end < len(source) and source[end] != quote:
                end += 2 if source[end] == "\\" else 1
            end += 1
            out.append(("string", source[pos:end], pos))
            pos = end
            continue
        word = WORD.match(source, pos)
        if word:
            out.append(("name", word[0], pos))
            pos += len(word[0])
        else:
            out.append(("punct", source[pos], pos))
            pos += 1
    return out


def scan():
    raw = collections.Counter()
    wrapped = 0
    paths = subprocess.check_output(["git", "ls-files", "*.lua"], cwd=ROOT, text=True).splitlines()
    for name in paths:
        if not name.startswith(("MidnightSimpleUnitFrames/", "MidnightSimpleUnitFrames_Options/")):
            continue
        if "/Locales/" in name or "/tools/" in name:
            continue
        if "/Libs/" in name and "/Libs/MSUFUnitFrames/" not in name:
            continue
        path = ROOT / name
        if not path.is_file():
            continue
        source = path.read_text(encoding="utf-8-sig")
        if not any(word in source for word in CREATORS | SETTERS):
            continue
        stream = tokens(source)
        stack = []
        for i, (kind, word, pos) in enumerate(stream):
            if word == "(" and kind == "punct":
                stack.append(stream[i - 1][1] if i else "")
            elif word == ")" and kind == "punct":
                stack.pop()
            if kind != "name" or word not in CREATORS | SETTERS:
                continue
            if i + 1 == len(stream) or stream[i + 1][1] != "(":
                continue
            if i and stream[i - 1][1] == "function":
                continue
            if word in SETTERS and (not i or stream[i - 1][1] != ":"):
                continue  # A similarly named local helper is not a native method.
            if "PixelLayoutRegion" in stack:
                wrapped += 1
                continue
            depth, end = 0, i + 1
            while end < len(stream):
                if stream[end][0] == "punct":
                    if stream[end][1] == "(":
                        depth += 1
                    elif stream[end][1] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                end += 1
            signature = " ".join(token[1] for token in stream[i:end + 1])
            if signature == "SetBackdrop ( nil )":
                continue  # Native ClearBackdrop cannot create or replace regions.
            raw[(name, signature)] += 1
    return raw, wrapped


actual, wrapped = scan()
expected = collections.Counter()
for row in json.loads(POLICY.read_text(encoding="utf-8-sig")):
    assert row["reason"].strip(), "missing nonvisual exception reason"
    expected[(row["path"], row["call"])] = row["count"]
assert actual == expected, "Pixel layout coverage drift: " + repr({
    "unreviewed": dict(actual - expected), "obsolete_exceptions": dict(expected - actual)})
assert wrapped > 1000, "owned creation coverage disappeared"
print(f"pixel_layout_coverage_smoke: ok ({wrapped} wrapped creation calls; "
      f"{sum(actual.values())} explicit nonvisual exceptions)")
