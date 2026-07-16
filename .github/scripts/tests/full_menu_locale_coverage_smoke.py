#!/usr/bin/env python3
"""Full core MSUF menu localization coverage contract (Assistant excluded)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
ADDON = ROOT / "MidnightSimpleUnitFrames"
LOCALES = ADDON / "Locales"
LOCALE_NAMES = (
    "enUS", "enGB", "deDE", "esES", "esMX", "frFR",
    "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW",
)
ASSIGN_RE = re.compile(r'\["((?:\\.|[^"\\])*)"\]\s*=\s*"((?:\\.|[^"\\])*)"')
QUOTED = r'"((?:\\.|[^"\\])*)"'
FORMAT_RE = re.compile(r"%(?:%|(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?[sdif])")
SEARCH_PATTERN_KEY = re.compile(r"^MSUF2_SEARCH_[A-Z_]+_PATTERNS$")
TECHNICAL_ID_RE = re.compile(
    r"^(?:12\.1 PTR|AFK|DND|DIALOG|TOOLTIP|FULLSCREEN_DIALOG|STATUS|MSUF|"
    r"[a-zA-Z]+[A-Z_][A-Za-z0-9_]*|[a-z]+\d*_[a-z0-9_]+)$"
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def lua_unescape(value: str) -> str:
    def decimal_run(match: re.Match[str]) -> str:
        raw = bytes(int(number) for number in re.findall(r"\\(\d{1,3})", match.group(0)))
        return raw.decode("utf-8")

    value = re.sub(r"(?:\\\d{1,3})+", decimal_run, value)
    sentinel = "\ue100"
    value = value.replace("\\\\", sentinel)
    value = value.replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t")
    value = value.replace('\\"', '"').replace("\\'", "'")
    return value.replace(sentinel, "\\")


def assignments(locale: str) -> dict[str, str]:
    return {lua_unescape(key): lua_unescape(value) for key, value in ASSIGN_RE.findall(read(LOCALES / f"{locale}.lua"))}


def add_groups(target: set[str], pattern: str, source: str, group: int | None = None) -> None:
    for match in re.finditer(pattern, source, re.S):
        values = (match.group(group),) if group is not None else match.groups()
        for value in values:
            if value:
                target.add(lua_unescape(value))


def source_menu_keys() -> set[str]:
    roots = (
        ADDON / "Shell" / "Menu2",
        ADDON / "Shell" / "EditMode",
        ADDON / "Shell" / "UI" / "EditMode",
        ADDON / "Shell" / "UI" / "MSUF_EditPopupUI.lua",
    )
    files: list[Path] = []
    for root in roots:
        files.extend(root.rglob("*.lua") if root.is_dir() else (root,))
    files = [path for path in files if "assistant" not in str(path).lower()]
    keys: set[str] = set()
    for path in files:
        source = read(path)
        add_groups(keys, rf'(?<![A-Za-z0-9_])(?:M\.)?(?:Tr|Format|TrFormat)\(\s*{QUOTED}', source)
        add_groups(keys, rf'(?:W\.[A-Za-z0-9_]+|T\.Button)\(\s*[^,]+,\s*{QUOTED}', source)
        add_groups(keys, rf':CollapsibleSection\(\s*{QUOTED}\s*,\s*{QUOTED}', source, 2)
        add_groups(keys, rf'M\.AddTooltip\(\s*[^,]+,\s*{QUOTED}\s*,\s*{QUOTED}', source)
        add_groups(keys, rf'[:.]SetText\(\s*(?:Tr\()?\s*{QUOTED}', source)
        add_groups(keys, rf'RegisterPage\([^\n]+?title\s*=\s*{QUOTED}', source)
        add_groups(keys, rf'\b(?:text|label|title|subtitle|description|tooltip)\s*=\s*{QUOTED}', source)
        for match in re.finditer(r"M\.ValueTextList\((.*?)\)", source, re.S):
            values = re.findall(QUOTED, match.group(1))
            keys.update(lua_unescape(value) for value in values[1::2])
        for match in re.finditer(
            rf'\{{\s*{QUOTED}\s*,\s*{QUOTED}\s*,\s*"[a-z0-9_]+"\s*,\s*{QUOTED}', source
        ):
            keys.update(lua_unescape(value) for value in match.groups() if value)
    return {key for key in keys if key and "assistant" not in key.lower()}


def main() -> None:
    locale_data = {name: assignments(name) for name in LOCALE_NAMES}
    source_keys = source_menu_keys()
    master = {
        key: value for key, value in locale_data["enUS"].items()
        if "assistant" not in key.lower()
    }
    required = set(master) | source_keys
    assert len(source_keys) >= 1100, f"menu source inventory unexpectedly small: {len(source_keys)}"
    assert len(required) >= 1750, f"combined locale inventory unexpectedly small: {len(required)}"

    failures: list[str] = []
    for locale in LOCALE_NAMES:
        values = locale_data[locale]
        missing = sorted(required - set(values))
        if missing:
            failures.append(f"{locale}: {len(missing)} missing keys; first={missing[:5]!r}")
        leaked = sorted(
            key for key, value in values.items()
            if "ZXQ" in value or "###2468" in value or "###987654321###" in value
        )
        if leaked:
            failures.append(f"{locale}: leaked translation markers in {leaked[:5]!r}")
        for key in required & set(values):
            english_value = master.get(key, key)
            if not SEARCH_PATTERN_KEY.match(key) and FORMAT_RE.findall(english_value) != FORMAT_RE.findall(values[key]):
                failures.append(f"{locale}: format mismatch for {key!r}")
                break
        if locale not in {"enUS", "enGB"}:
            unchanged_prose = sorted(
                key for key in source_keys
                if values.get(key) == key
                and len(key.split()) >= 4
                and re.search(r"[A-Za-z]{3}", key)
                and not TECHNICAL_ID_RE.fullmatch(key)
                and not re.fullmatch(r"[A-Z0-9 %/_?.-]+", FORMAT_RE.sub("", key))
            )
            if unchanged_prose:
                failures.append(f"{locale}: unchanged English prose {unchanged_prose[:5]!r}")

    toc = read(ADDON / "MidnightSimpleUnitFrames.toc")
    if "Locales\\MSUF_PriorityFrames_FAQ.lua" not in toc:
        failures.append("main TOC does not load Priority Frames FAQ locales")
    if failures:
        raise AssertionError("\n".join(failures))
    print(
        f"PASS full menu locale coverage: {len(source_keys)} source keys, "
        f"{len(required)} combined non-Assistant keys, {len(LOCALE_NAMES)} locales"
    )


if __name__ == "__main__":
    main()
