#!/usr/bin/env python3
"""Build a UI-control to Assistant-registry coverage matrix.

This is intentionally conservative: it records every control-like call site it
can statically identify and marks uncertain rows as unmapped/partial instead of
silently treating them as covered.
"""

from __future__ import annotations

import csv
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "MidnightSimpleUnitFrames"
ASSISTANT = ADDON / "Shell" / "Menu2" / "Assistant"
PAGES = ADDON / "Shell" / "Menu2" / "Pages"
DOCS = ADDON / "docs"
OUT = DOCS / "ASSISTANT_REGISTRY_MATRIX.tsv"


REGISTRY_FILES = [
    "MSUF_AssistantRegistry.lua",
    "MSUF_AssistantRegistry_Core.lua",
    "MSUF_AssistantRegistry_Unitframes.lua",
    "MSUF_AssistantRegistry_Castbars.lua",
    "MSUF_AssistantRegistry_Auras.lua",
    "MSUF_AssistantRegistry_GroupFrames.lua",
    "MSUF_AssistantRegistry_Boss.lua",
    "MSUF_AssistantRegistry_ClassPower.lua",
    "MSUF_AssistantRegistry_Gameplay.lua",
    "MSUF_AssistantRegistry_Global.lua",
    "MSUF_AssistantRegistry_Dashboard.lua",
    "MSUF_AssistantRegistry_Profiles.lua",
    "MSUF_AssistantRegistry_EditMode.lua",
    "MSUF_AssistantRegistry_Diagnostics.lua",
]


CONTROL_PATTERNS = [
    ("toggle", re.compile(r"\bW\.(?:Toggle|ToggleAt|SwitchAt)\s*\((.*)")),
    ("slider", re.compile(r"\bW\.Slider\s*\((.*)")),
    ("dropdown", re.compile(r"\bW\.Dropdown\s*\((.*)")),
    ("color", re.compile(r"\bW\.Color\s*\((.*)")),
    ("textinput", re.compile(r"\bW\.TextInput\s*\((.*)")),
    ("segment", re.compile(r"\bW\.Segment\s*\((.*)")),
    ("button", re.compile(r"\bW\.Button\s*\((.*)")),
    ("button", re.compile(r"\bT\.Button\s*\((.*)")),
    ("button", re.compile(r"\bT\.CloseButton\s*\((.*)")),
]

HELPER_PATTERNS = [
    ("toggle", re.compile(r"\bBind\w*Toggle\s*\((.*)")),
    ("slider", re.compile(r"\bBind\w*Slider\s*\((.*)")),
    ("dropdown", re.compile(r"\bBind\w*Dropdown\s*\((.*)")),
    ("color", re.compile(r"\bBind\w*Color\s*\((.*)")),
    ("textinput", re.compile(r"\bBind\w*Text\w*\s*\((.*)")),
]

HELPER_CALL_SPECS = [
    # name, control_type, label_idx, key_idx, values_idx, min_idx, max_idx, step_idx
    ("ToggleAt", "toggle", 2, 6, None, None, None, None),
    ("SwitchAt", "toggle", 2, 6, None, None, None, None),
    ("ValueToggleAt", "toggle", 2, None, None, None, None, None),
    ("ValueSwitchAt", "toggle", 2, None, None, None, None, None),
    ("SliderAt", "slider", 2, 10, None, 5, 6, 7),
    ("ValueSliderAt", "slider", 2, None, None, 5, 6, 7),
    ("DropdownAt", "dropdown", 2, 8, 5, None, None, None),
    ("ValueDropdownAt", "dropdown", 2, None, 5, None, None, None),
    ("BindTableToggle", "toggle", 2, 4, None, None, None, None),
    ("BindTableSlider", "slider", 2, 8, None, 3, 4, 5),
    ("BindTableDropdown", "dropdown", 2, 6, 3, None, None, None),
    ("BindBarsAlphaPercent", "slider", 2, 3, None, None, None, 6),
    ("ColorValueAt", "color", 2, None, None, None, None, None),
    ("CH.ApiColorAt", "color", 2, None, None, None, None, None),
    ("CH.GeneralColorAt", "color", 2, 6, None, None, None, None),
    ("CH.TableColorAt", "color", 2, 6, None, None, None, None),
    ("ButtonAt", "button", 1, None, None, None, None, None),
    ("CH.ButtonAt", "button", 1, None, None, None, None, None),
    ("CreateWindowControlButton", "button", 2, 1, None, None, None, None),
    ("DashboardDisclosure", "toggle", 1, 3, None, None, None, None),
    ("BuildDashboardChangelog", "toggle", 2, None, None, None, None, None),
    ("BindCastToggle", "toggle", 1, 5, None, None, None, None),
    ("BindCastSlider", "slider", 1, 8, None, 5, 6, 7),
    ("BindCastDropdown", "dropdown", 1, None, 5, None, None, None),
]

FACTORY_FUNCTIONS_BY_FILE = {
    "MSUF_Menu2_Advanced.lua": {
        "BindTableToggle", "BindTableSwitchAt", "BindTableSlider", "BindTableDropdown",
        "BindValueDropdown", "BindTableColor", "BindValueToggle", "BindValueSwitchAt",
        "BindValueSlider", "ToggleAt", "SwitchAt", "ValueToggleAt", "ValueSwitchAt",
        "SliderAt", "ValueSliderAt", "DropdownAt", "ValueDropdownAt", "ColorAt",
        "ScopedToggleAt", "ScopedSliderAt", "ScopedDropdownAt", "TogglePillAt",
    },
    "MSUF_Menu2_AdvancedColors.lua": {
        "ApiColorAt", "GeneralColorAt", "TableColorAt", "ButtonAt",
    },
    "MSUF_Menu2_GlobalBars.lua": {
        "BindUFOverlayToggle",
    },
    "MSUF_Menu2_UnitSectionShared.lua": {
        "IsNameRelativeAnchor",
    },
    "MSUF_Menu2_UnitText.lua": {
        "SwitchOrToggle",
    },
    "MSUF_Menu2_Dashboard.lua": {
        "Button",
    },
}

KEYISH = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
RESERVED_KEY_STRINGS = {
    "function",
    "true",
    "false",
    "nil",
    "player",
    "target",
    "focus",
    "boss",
    "party",
    "raid",
    "shared",
    "left",
    "right",
    "top",
    "bottom",
    "center",
    "TOPLEFT",
    "TOPRIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
    "CENTER",
    "LEFT",
    "RIGHT",
    "TOP",
    "BOTTOM",
    "RTL",
    "LTR",
    "Blizzard",
    "border",
    "box",
}

PAGE_UNITS = {
    "uf_player": "player",
    "uf_target": "target",
    "uf_focus": "focus",
    "uf_targettarget": "targettarget",
    "uf_focustarget": "focustarget",
    "uf_pet": "pet",
    "uf_boss": "boss",
}

UNIT_LABELS = {
    "player": "Player",
    "target": "Target",
    "focus": "Focus",
    "targettarget": "Target of Target",
    "focustarget": "Focus Target",
    "pet": "Pet",
    "boss": "Boss",
}


@dataclass
class RegistryRow:
    kind: str
    key: str
    label: str
    category: str
    frame_type: str
    unit: str
    attribute: str
    control_type: str
    values: str
    min_value: str
    max_value: str
    step: str
    aliases: str


@dataclass
class UiRow:
    ui_file: str
    line: int
    function: str
    page: str
    label: str
    section: str
    control_type: str
    db_key_or_helper: str
    values_min_max_step: str
    apply_helper: str
    registry_key: str
    status: str
    reason: str


def clean(value: object) -> str:
    return str(value if value is not None else "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def normalize(text: str) -> str:
    text = clean(text).lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def compact(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", clean(text).lower())


def split_args(arg_text: str) -> list[str]:
    args: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escape = False
    depth = 0
    for ch in arg_text:
        if quote:
            current.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            current.append(ch)
            continue
        if ch in "({[":
            depth += 1
        elif ch in ")}]" and depth > 0:
            depth -= 1
        if ch == "," and depth == 0:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        args.append("".join(current).strip())
    return args


def call_arg_text(match: re.Match[str]) -> str:
    text = match.group(1).strip()
    if text.endswith(")"):
        text = text[:-1].rstrip()
    return text


def full_call_text(lines: list[str], index: int, max_lines: int = 40) -> str:
    out: list[str] = []
    quote: str | None = None
    escape = False
    depth = 0
    started = False
    for i in range(index, min(len(lines), index + max_lines)):
        line = lines[i]
        out.append(line)
        for ch in line:
            if quote:
                if escape:
                    escape = False
                elif ch == "\\":
                    escape = True
                elif ch == quote:
                    quote = None
                continue
            if ch in ("'", '"'):
                quote = ch
                continue
            if ch == "(":
                depth += 1
                started = True
            elif ch == ")" and depth > 0:
                depth -= 1
        if started and depth <= 0:
            break
    return "\n".join(out)


def helper_call_args(statement: str, name: str) -> list[str] | None:
    pattern = re.compile(r"\b" + re.escape(name) + r"\s*\((.*)", re.S)
    match = pattern.search(statement)
    if not match:
        return None
    return split_args(call_arg_text(match))


def unquote(value: str) -> str | None:
    value = value.strip()
    if len(value) >= 2 and value[0] in ("'", '"') and value[-1] == value[0]:
        return value[1:-1]
    return None


def quoted_strings(text: str) -> list[str]:
    out: list[str] = []
    for match in re.finditer(r'"((?:\\.|[^"\\])*)"|\'((?:\\.|[^\'\\])*)\'', text):
        out.append(match.group(1) if match.group(1) is not None else match.group(2))
    return out


def extract_label(control_type: str, args: list[str]) -> str:
    if not args:
        return ""
    if control_type in {"toggle", "slider", "dropdown", "color", "textinput", "segment", "button"}:
        for arg in args[1:4]:
            q = unquote(arg)
            if q and not KEYISH.match(q):
                return q
        for arg in args:
            q = unquote(arg)
            if q:
                return q
    return ""


def explicit_empty_label(args: list[str]) -> bool:
    for arg in args[1:4]:
        if arg.strip() in {'""', "''"}:
            return True
    return False


def extract_helper_label(strings: list[str]) -> str:
    for value in strings:
        if value.startswith("MSUF"):
            continue
        if KEYISH.match(value):
            continue
        return value
    return strings[0] if strings else ""


def extract_key(strings: list[str], label: str) -> str:
    normalized_label = normalize(label)
    candidates: list[str] = []
    for value in strings:
        if not value or value.startswith("MSUF"):
            continue
        if normalize(value) == normalized_label:
            continue
        if value in RESERVED_KEY_STRINGS:
            continue
        if KEYISH.match(value) and len(value) > 2:
            candidates.append(value)
    for value in candidates:
        if re.search(r"[a-z][A-Z]|[A-Z][a-z]", value):
            return value
    return candidates[-1] if candidates else ""


def extract_key_from_args(args: list[str], label: str) -> str:
    strings = [q for arg in args for q in ([unquote(arg)] if unquote(arg) is not None else [])]
    return extract_key(strings, label)


def source_files() -> list[Path]:
    files = sorted(PAGES.glob("*.lua"))
    files += [
        ADDON / "Shell" / "Menu2" / "MSUF_Menu2_Dashboard.lua",
        ADDON / "Shell" / "Menu2" / "MSUF_Menu2_Navigation.lua",
        ADDON / "Shell" / "Menu2" / "MSUF_Menu2_NavRail.lua",
        ADDON / "Shell" / "Menu2" / "MSUF_Menu2_Window.lua",
    ]
    return [f for f in files if f.exists()]


def factory_functions_for_file(path: Path) -> set[str]:
    return FACTORY_FUNCTIONS_BY_FILE.get(path.name, set())


def page_keys_for_file(text: str) -> str:
    keys = re.findall(r'M\.RegisterPage\s*\(\s*"([^"]+)"', text)
    if keys:
        return ",".join(dict.fromkeys(keys))
    if "UNIT_PAGES" in text or "UnitPage" in text:
        return "uf_player,uf_target,uf_focus,uf_pet,uf_targettarget,uf_focustarget,uf_boss"
    return ""


def infer_section(line: str, current_function: str) -> str:
    section_match = re.search(r'(?:b:CollapsibleSection|b:Section)\s*\(\s*"[^"]+"\s*,\s*"([^"]+)"', line)
    if section_match:
        return section_match.group(1)
    return current_function


def window_text(lines: list[str], index: int, radius: int = 8) -> str:
    lo = max(0, index - radius)
    hi = min(len(lines), index + radius + 1)
    return "\n".join(lines[lo:hi])


def forward_text(lines: list[str], index: int, radius: int = 14) -> str:
    hi = min(len(lines), index + radius + 1)
    return "\n".join(lines[index:hi])


def binding_text(lines: list[str], index: int, radius: int = 14) -> str:
    out = [lines[index]]
    hi = min(len(lines), index + radius + 1)
    for i in range(index + 1, hi):
        line = lines[i]
        starts_next_control = any(pattern.search(line) for _, pattern in CONTROL_PATTERNS)
        if starts_next_control:
            break
        out.append(line)
    return "\n".join(out)


def extract_db_from_window(text: str) -> str:
    patterns = [
        r'SetPortraitValue\s*\([^,\)]*,\s*"([^"]+)"',
        r'SetString\s*\([^,\)]*,\s*"([^"]+)"',
        r'SetText\s*\([^,\)]*,\s*"([^"]+)"',
        r'SetNumber\s*\([^,\)]*,\s*"([^"]+)"',
        r'SetBool\s*\([^,\)]*,\s*"([^"]+)"',
        r'(?:ReadG|SetG|ReadGBool|SetGBool)\s*\(\s*"([^"]+)"',
        r'(?:ReadBool|SetBool|ReadNumber|SetNumber|SetText|GetText)\s*\([^,\)]*,\s*"([^"]+)"',
        r'\[\s*"([^"]+)"\s*\]',
    ]
    for pattern in patterns:
        match = re.search(pattern, text)
        if match:
            value = match.group(1)
            if KEYISH.match(value):
                return value
    return ""


def row_units(row: UiRow) -> set[str]:
    units: set[str] = set()
    for page in clean(row.page).split(","):
        unit = PAGE_UNITS.get(page)
        if unit:
            units.add(unit)
    return units


def control_type_matches(row_type: str, registry_type: str) -> bool:
    if row_type == registry_type:
        return True
    if row_type == "slider" and registry_type == "number":
        return True
    if row_type in {"segment", "dropdown"} and registry_type == "enum":
        return True
    if row_type == "dropdown" and registry_type == "string":
        return True
    if row_type in {"toggle", "button"} and registry_type == "boolean":
        return True
    if row_type == "toggle" and registry_type == "enum":
        return True
    return False


def filter_candidates_by_row_scope(row: UiRow, candidates: list[RegistryRow]) -> list[RegistryRow]:
    units = row_units(row)
    if not units:
        return candidates
    scoped = [c for c in candidates if c.unit in units]
    return scoped or candidates


def synthetic_candidates(row: UiRow, settings: list[RegistryRow]) -> list[RegistryRow]:
    label = normalize(row.label)
    ui_file = row.ui_file.replace("\\", "/")
    wanted_attr = ""
    wanted_frame = ""
    if "MSUF_Menu2_UnitAlpha.lua" in ui_file:
        if label == "in combat":
            wanted_attr, wanted_frame = "alphaInCombat", "unitframe"
        elif label == "out of combat":
            wanted_attr, wanted_frame = "alphaOutOfCombat", "unitframe"
        elif row.db_key_or_helper == "alphaExcludeTextPortrait":
            wanted_attr, wanted_frame = "alphaLayerMode", "unitframe"
    elif "MSUF_Menu2_UnitFrameVisuals.lua" in ui_file and ("castbar" in normalize(row.section) or "castbar" in normalize(row.function)):
        if label == "enable castbar":
            wanted_attr, wanted_frame = "enabled", "castbar"
        elif label == "castbar provider":
            wanted_attr, wanted_frame = "provider", "castbar"
        elif label in {"<dynamic timelabel>", "dynamic timelabel"}:
            wanted_attr, wanted_frame = "time", "castbar"
        elif label == "icon":
            wanted_attr, wanted_frame = "icon", "castbar"
        elif label == "text":
            wanted_attr, wanted_frame = "text", "castbar"
    if not wanted_attr:
        return []
    units = row_units(row)
    out = [
        s for s in settings
        if s.attribute == wanted_attr and s.frame_type == wanted_frame and (not units or s.unit in units)
    ]
    return out


def settings_with_suffix(settings: list[RegistryRow], suffixes: set[str], frame_type: str | None = None) -> list[RegistryRow]:
    return [
        setting for setting in settings
        if setting.key.split(".")[-1] in suffixes and (frame_type is None or setting.frame_type == frame_type)
    ]


def settings_with_keys(settings: list[RegistryRow], keys: set[str]) -> list[RegistryRow]:
    return [setting for setting in settings if setting.key in keys]


def settings_with_attribute(settings: list[RegistryRow], attrs: set[str], frame_type: str | None = None) -> list[RegistryRow]:
    return [
        setting for setting in settings
        if setting.attribute in attrs and (frame_type is None or setting.frame_type == frame_type)
    ]


def unique_registry_rows(rows: list[RegistryRow]) -> list[RegistryRow]:
    out: list[RegistryRow] = []
    seen: set[str] = set()
    for row in rows:
        if row.key in seen:
            continue
        seen.add(row.key)
        out.append(row)
    return out


def action_with_key(actions: list[RegistryRow], key: str) -> list[RegistryRow]:
    return [action for action in actions if action.key == key]


def mark_registry_family(row: UiRow, candidates: list[RegistryRow], reason: str) -> bool:
    candidates = unique_registry_rows(candidates)
    if not candidates:
        return False
    row.registry_key = "|".join(candidate.key for candidate in candidates[:12])
    row.status = "registered"
    row.reason = reason
    return True


def mark_known_gap(row: UiRow, reason: str, status: str = "unmapped", registry_key: str = "") -> bool:
    row.registry_key = registry_key
    row.status = status
    row.reason = reason
    return True


def apply_synthetic_mapping(row: UiRow, settings: list[RegistryRow], actions: list[RegistryRow]) -> bool:
    label = normalize(row.label)
    ui_file = row.ui_file.replace("\\", "/")

    if "MSUF_Menu2_Dashboard.lua" in ui_file:
        if row.function == "Button" and label.startswith("dynamic"):
            return mark_known_gap(row, "Dashboard local Button() factory; concrete Dashboard panel/actions are audited at their call sites or through Dashboard Assistant actions.", "todo")
        if row.function == "BuildCommandCenter":
            return mark_known_gap(row, "Dashboard command-center result buttons are transient parser-result choices; Assistant executes the selected parsed action directly.", "todo")
        if row.function == "BuildSimpleScaleColumn":
            return mark_registry_family(row, settings_with_keys(settings, {"general.msufUiScale", "general.slashMenuScale"}), "Matched Dashboard simple scale sliders to MSUF frame/menu scale settings.")
        if row.db_key_or_helper in {"dashboardRecoveryOpen", "dashboardScalingOpen", "dashboardChangelogOpen", "BuildDashboardChangelog"}:
            return mark_registry_family(row, action_with_key(actions, "set_dashboard_panel"), "Matched Dashboard disclosure header to the shared Dashboard panel state action.")

    if "MSUF_Menu2_NavRail.lua" in ui_file:
        if row.function == "CreateNavButton":
            return mark_registry_family(row, action_with_key(actions, "open_page"), "Matched NavRail page button factory to Assistant open-page navigation action.")
        if row.function == "StyleHistoryButton":
            return mark_registry_family(row, action_with_key(actions, "assistant.action.history.undo") + action_with_key(actions, "assistant.action.history.redo"), "Matched NavRail Undo/Redo buttons to Assistant history actions.")
        if row.function == "ShowSearchIntro":
            return mark_known_gap(row, "NavRail section/search intro buttons are UI-only expand/help state; Assistant opens concrete pages and search targets directly.", "todo")

    if "MSUF_Menu2_Window.lua" in ui_file:
        if row.function == "CreateMinimizedBar" and label == "restore":
            return mark_registry_family(row, action_with_key(actions, "menu_window_restore"), "Matched minimized-bar restore button to the shared Menu2 restore action.")
        if row.function == "CreateMinimizedBar" and label != "restore":
            return mark_registry_family(row, action_with_key(actions, "menu_window_close"), "Matched minimized-bar close button to the shared Menu2 close action.")
        if row.function == "BuildWindow" and label.startswith("dynamic"):
            return mark_registry_family(row, action_with_key(actions, "menu_window_close"), "Matched menu window close button to the shared Menu2 close action.")
        if row.function == "BuildWindow" and label == "maximize":
            return mark_registry_family(row, action_with_key(actions, "menu_window_maximize"), "Matched menu window maximize/restore button to the shared Menu2 maximize action.")
        if row.function == "BuildWindow" and label == "minimize":
            return mark_registry_family(row, action_with_key(actions, "menu_window_minimize"), "Matched menu window minimize button to the shared Menu2 minimize action.")

    if "MSUF_Menu2_Advanced.lua" in ui_file:
        return mark_known_gap(row, "Aura setup control on the Advanced/Aura page; aura feature work is intentionally out of scope for this non-aura parity pass.", "todo")

    if "MSUF_Menu2_AdvancedClassPower.lua" in ui_file:
        if label == "class color":
            return mark_registry_family(row, action_with_key(actions, "open_page"), "Matched Class Color shortcut to Assistant open-page navigation action for Colors.")
        if label == "msuf edit mode":
            return mark_registry_family(row, action_with_key(actions, "assistant.action.editMode.enter"), "Matched MSUF Edit Mode button to Assistant edit-mode enter action.")
        if label == "width mode":
            return mark_registry_family(row, settings_with_keys(settings, {"bars.detachedPowerBarWidthMode"}), "Matched Detached Power Bar width mode dropdown to registered setting.")

    if "MSUF_Menu2_AdvancedColors.lua" in ui_file:
        section = normalize(row.section)
        if row.function in {"ApiColorAt", "GeneralColorAt", "TableColorAt"}:
            return mark_known_gap(row, "Colors helper forwarding function; concrete color call sites are audited separately.", "todo")
        if row.function == "SetHighlightRGB" or label == "mouseover highlight color":
            return mark_registry_family(row, settings_with_keys(settings, {"general.highlightColor"}), "Matched mouseover highlight color swatch to registered color setting.")
        if row.function == "ButtonAt":
            return mark_known_gap(row, "Colors ButtonAt() factory helper; concrete reset buttons are covered by registered color reset actions where shared helpers exist.", "todo")
        if section == "power bar colors":
            if label == "power type":
                return mark_known_gap(row, "Runtime selected power-token dropdown; Assistant targets concrete registered power-token color settings directly.", "todo")
            if label == "color":
                return mark_registry_family(row, settings_with_attribute(settings, {"powerColor"}, "colors"), "Matched selected power-token color swatch to registered power-color token settings.")
            if label == "reset":
                return mark_registry_family(row, action_with_key(actions, "reset_power_color_token"), "Matched selected power-token reset button to Assistant token reset action.")
        if section == "class power colors":
            if label == "resource type":
                return mark_known_gap(row, "Runtime selected class-resource token dropdown; Assistant targets concrete registered class-resource token color settings directly.", "todo")
            if label == "color":
                return mark_registry_family(row, settings_with_attribute(settings, {"classPowerColor"}, "colors"), "Matched selected class-resource color swatch to registered class-resource token color settings.")
            if label == "background":
                return mark_registry_family(row, settings_with_attribute(settings, {"classPowerBackgroundColor"}, "colors"), "Matched selected class-resource background swatch to registered class-resource background color settings.")
            if label in {"reset color", "reset bg"}:
                return mark_registry_family(row, action_with_key(actions, "reset_class_power_color_token"), "Matched selected class-resource color reset button to registered token reset action.")
            if label == "combo point slot mode":
                return mark_registry_family(row, settings_with_keys(settings, {"bars.classPowerComboPointColorMode"}), "Matched combo point slot mode dropdown to registered class-resource setting.")
            if label.startswith("dynamic tostring"):
                return mark_registry_family(row, settings_with_attribute(settings, {"comboPointSlotColor"}, "colors"), "Matched combo point slot color swatches to registered slot color settings.")
            if label == "reset slots":
                return mark_registry_family(row, action_with_key(actions, "reset_class_power_combo_slot_colors"), "Matched combo point slot reset button to registered reset action.")
        if section == "auras":
            return mark_known_gap(row, "Aura color control; aura feature work is intentionally out of scope for this non-aura parity pass.", "todo")
        if section == "portrait colors":
            if label == "border custom color":
                return mark_registry_family(row, settings_with_keys(settings, {"general.portraitBorderColor"}), "Matched portrait border color swatch to registered portrait color setting.")
            if label == "background color":
                return mark_registry_family(row, settings_with_keys(settings, {"general.portraitBgColor"}), "Matched portrait background color swatch to registered portrait color setting.")
        if section == "global font color" and label == "use font palette":
            return mark_registry_family(row, action_with_key(actions, "reset_global_font_color"), "Matched Use font palette button to registered global font color reset action.")
        if section == "class bar colors":
            if label.startswith("dynamic"):
                return mark_registry_family(row, settings_with_attribute(settings, {"classColor"}, "colors"), "Matched dynamic class color swatches to registered class bar color settings.")
            if label == "reset all class colors":
                return mark_registry_family(row, action_with_key(actions, "reset_class_colors"), "Matched class color reset button to registered reset action.")
        if section == "bar background tint" and label == "reset to black":
            return mark_registry_family(row, action_with_key(actions, "reset_bar_background_color"), "Matched bar background tint reset button to registered reset action.")
        if section == "unitframe colors" and label.startswith("dynamic"):
            return mark_registry_family(row, settings_with_attribute(settings, {"npcColor"}, "colors"), "Matched dynamic NPC reaction color swatches to registered unitframe color settings.")
        if section == "npc type colors":
            if label == "color hp bar class color mode only":
                return mark_registry_family(row, settings_with_keys(settings, {"general.npcTypeColorBar"}), "Matched NPC Type HP-bar toggle to registered setting.")
            if label == "color name text":
                return mark_registry_family(row, settings_with_keys(settings, {"general.npcTypeColorText"}), "Matched NPC Type name-text toggle to registered setting.")
            if label.startswith("dynamic info"):
                return mark_registry_family(row, settings_with_attribute(settings, {"npcTypeTarget", "npcTypeFocus", "npcTypeBoss", "npcTypeToT"}, "colors"), "Matched dynamic NPC Type apply-to toggles to registered per-unit settings.")
            if label.startswith("dynamic row"):
                return mark_registry_family(row, settings_with_attribute(settings, {"npcTypeColor"}, "colors"), "Matched dynamic NPC Type color swatches to registered type-color settings.")
        if section == "dispel":
            if label == "color mode":
                return mark_registry_family(row, settings_with_keys(settings, {"general.hlDispelColorMode"}), "Matched Dispel color mode dropdown to registered setting.")
            if label == "dispel color all types":
                return mark_registry_family(row, settings_with_keys(settings, {"general.hlDispelColor"}), "Matched shared Dispel color swatch to registered color setting.")
            if label.startswith("dynamic def"):
                return mark_registry_family(row, settings_with_attribute(settings, {"dispelTypeColor"}, "colors"), "Matched per-type Dispel color swatches to registered type color settings.")
        if section == "castbar colors":
            if label == "interrupt color all castbars":
                return mark_registry_family(row, settings_with_keys(settings, {"general.castbarInterruptFeedbackColor"}), "Matched interrupt feedback color swatch to registered castbar color setting.")
            if label == "custom color":
                return mark_registry_family(row, settings_with_keys(settings, {"general.playerCastbarOverrideColor"}), "Matched player castbar override color swatch to registered setting.")
            if label == "mode":
                return mark_registry_family(row, settings_with_keys(settings, {"general.playerCastbarOverrideMode"}), "Matched player castbar override mode dropdown to registered setting.")
            if label == "player override":
                return mark_registry_family(row, settings_with_keys(settings, {"general.playerCastbarOverrideEnabled"}), "Matched player castbar override toggle to registered setting.")

    if "MSUF_Menu2_Global.lua" in ui_file:
        if row.function == "BuildScopeOverrideSection" and row.control_type == "toggle":
            return mark_registry_family(row, settings_with_suffix(settings, {"override"}), "Matched global scope override toggle to scoped Bars/Fonts override settings.")
        if row.function == "BuildScopeOverrideSection" and row.control_type == "button":
            return mark_registry_family(row, action_with_key(actions, "reset_all_scoped_global_bars_overrides") + action_with_key(actions, "reset_all_scoped_global_font_overrides"), "Matched shared-scope reset button to registered scoped override reset actions.")

    if "MSUF_Menu2_GlobalCastbars.lua" in ui_file:
        if row.function == "CastbarShowTime" and label in {"dynamic spec text", "interrupt"}:
            return mark_registry_family(row, action_with_key(actions, "preview_castbar"), "Matched Global Castbars preview selector/shake buttons to the shared castbar preview action.")
        if label == "reset position":
            return mark_registry_family(row, action_with_key(actions, "reset_focus_kick_position"), "Matched Focus Kick reset position button to registered reset action.")

    if "MSUF_Menu2_GlobalMisc.lua" in ui_file:
        if label == "show unitframe tooltips":
            return mark_registry_family(row, settings_with_keys(settings, {"general.unitTooltipMode"}), "Matched tooltip behavior dropdown to registered setting.")
        if label == "modifier key":
            return mark_registry_family(row, settings_with_keys(settings, {"general.unitTooltipModifier"}), "Matched tooltip modifier dropdown to registered setting.")

    if "MSUF_Menu2_Group.lua" in ui_file:
        if row.function == "RunCopy":
            return mark_known_gap(row, "Runtime group copy category checkbox in the copy popup; Assistant passes category scopes directly to copy_group.", "partial", "copy_group")

    if "MSUF_Menu2_UnitSectionShared.lua" in ui_file:
        if row.function == "IsNameRelativeAnchor":
            return mark_known_gap(row, "Shared section notice button factory; concrete notice buttons are audited where the section creates them.", "todo")

    if "MSUF_Menu2_UnitText.lua" in ui_file:
        if label == "text area":
            return mark_known_gap(row, "Runtime unit text-area tab selector; Assistant targets concrete name, HP, power, and advanced text settings directly.", "todo")
        if row.function == "SwitchOrToggle":
            return mark_known_gap(row, "Unit text toggle factory for HP reverse-order and move-together UI state; concrete persistent text settings are mapped separately.", "todo")
        if label == "hidden" and row.function == "BuildValueTextTab":
            return mark_registry_family(row, settings_with_suffix(settings, {"showHP", "showPower"}, "unitframe"), "Matched dynamic HP/power text visibility switches to registered unit text settings.")
        if row.function == "SlotControl" and label.startswith("dynamic"):
            return mark_registry_family(row, settings_with_suffix(settings, {
                "hpTextLeft", "hpTextCenter", "hpTextRight",
                "powerTextLeft", "powerTextCenter", "powerTextRight",
            }, "unitframe"), "Matched dynamic HP/power text slot dropdowns to registered left/center/right slot settings.")
        if row.function == "SlotControl" and label == "delimiter":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpTextSeparator", "powerTextSeparator"}, "unitframe"), "Matched HP/power delimiter dropdowns to registered text separator settings.")
        if row.function == "SlotControl" and label == "":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpTextReverse"}, "unitframe"), "Matched HP reverse-order toggle to registered setting.")
        if row.function == "SlotControl" and label == "slot":
            return mark_known_gap(row, "Runtime selected HP/power text slot selector; Assistant targets concrete left/center/right slot settings directly.", "todo")
        if row.function == "SlotControl" and label == "slot x":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "hpTextLeftOffsetX", "hpTextCenterOffsetX", "hpTextRightOffsetX",
                "powerTextLeftOffsetX", "powerTextCenterOffsetX", "powerTextRightOffsetX",
            }, "unitframe"), "Matched selected-slot X slider to concrete registered slot X offset settings.")
        if row.function == "SlotControl" and label == "slot y":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "hpTextLeftOffsetY", "hpTextCenterOffsetY", "hpTextRightOffsetY",
                "powerTextLeftOffsetY", "powerTextCenterOffsetY", "powerTextRightOffsetY",
            }, "unitframe"), "Matched selected-slot Y slider to concrete registered slot Y offset settings.")
        if row.function == "SlotControl" and label == "size":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpFontSize", "powerFontSize"}, "unitframe"), "Matched HP/power text size sliders to registered font-size settings.")

    if "MSUF_Menu2_AdvancedGameplay.lua" in ui_file:
        if label == "msuf edit mode":
            return mark_registry_family(row, action_with_key(actions, "assistant.action.editMode.enter"), "Matched MSUF Edit Mode button to Assistant edit-mode enter action.")
        if label == "enter text":
            return mark_registry_family(row, settings_with_keys(settings, {"gameplay.combatStateEnterText"}), "Matched combat enter text input to gameplay string setting.")
        if label == "leave text":
            return mark_registry_family(row, settings_with_keys(settings, {"gameplay.combatStateLeaveText"}), "Matched combat leave text input to gameplay string setting.")
        if label == "preview":
            return mark_registry_family(row, action_with_key(actions, "preview_player_totems"), "Matched TotemFrame preview button to Assistant preview action.")
        if label == "reset totemframe layout":
            return mark_registry_family(row, action_with_key(actions, "reset_player_totems_layout"), "Matched TotemFrame reset button to Assistant reset action.")
        if label == "choose spell id or name":
            return mark_registry_family(row, action_with_key(actions, "set_crosshair_melee_spell") + settings_with_keys(settings, {"gameplay.nameplateMeleeSpellID"}), "Matched crosshair spell input to Assistant spell action and backing setting.")

    if "MSUF_Menu2_GlobalFonts.lua" in ui_file:
        def font_scope_settings(suffixes: set[str]) -> list[RegistryRow]:
            return [
                setting for setting in settings
                if setting.key.split(".")[-1] in suffixes
                and setting.frame_type == "fonts"
            ]

        if label == "font sharedmedia":
            return mark_registry_family(row, settings_with_keys(settings, {"general.fontKey"}), "Matched shared font picker to global font setting.")
        if label == "outline":
            return mark_registry_family(row, font_scope_settings({"outline"}), "Matched font outline segment to scoped font outline settings.")
        if label == "player name color":
            return mark_registry_family(row, font_scope_settings({"nameColorMode"}), "Matched name color dropdown to scoped font name-color settings.")
        if label == "npc boss name color":
            return mark_registry_family(row, font_scope_settings({"npcNameRed"}), "Matched NPC/Boss name color dropdown to scoped font NPC-name settings.")
        if label == "shorten group names":
            return mark_registry_family(row, settings_with_suffix(settings, {"nameShortenEnabled"}, "group"), "Matched group-frame name shortening toggle.")
        if label == "truncation style" and row.line < 600:
            return mark_registry_family(row, settings_with_suffix(settings, {"nameClipSide"}, "group"), "Matched group-frame name truncation style setting.")
        if label == "max name length" and row.line < 600:
            return mark_registry_family(row, settings_with_suffix(settings, {"nameMaxChars"}, "group"), "Matched group-frame max name length setting.")
        if label == "no ellipsis truncate without" and row.line < 600:
            return mark_registry_family(row, settings_with_suffix(settings, {"nameNoEllipsis"}, "group"), "Matched group-frame no-ellipsis setting.")
        if label.startswith("dynamic namescope shared and shorten names"):
            return mark_registry_family(row, font_scope_settings({"shortenNames"}), "Matched scoped unit/shared name shortening toggle.")
        if label == "truncation style":
            return mark_registry_family(row, font_scope_settings({"shortenNameClipSide"}), "Matched scoped unit/shared name truncation style setting.")
        if label == "max name length":
            return mark_registry_family(row, font_scope_settings({"shortenNameMaxChars"}), "Matched scoped unit/shared max name length setting.")
        if label == "no ellipsis truncate without" and row.line >= 600:
            return mark_registry_family(row, font_scope_settings({"shortenNameNoEllipsis"}), "Matched scoped unit/shared no-ellipsis setting.")

    if "MSUF_Menu2_AdvancedProfiles.lua" in ui_file:
        if label == "active profile":
            return mark_registry_family(row, action_with_key(actions, "switch_profile"), "Matched active-profile dropdown to profile switch action.")
        if label == "profile name for create copy":
            return mark_known_gap(row, "Profile-name staging input; Assistant passes the name directly to create_profile or copy_profile.", "partial", "create_profile|copy_profile")
        if label == "copy current to name":
            return mark_registry_family(row, action_with_key(actions, "copy_profile"), "Matched profile copy action.")
        if label == "reset current profile":
            return mark_registry_family(row, action_with_key(actions, "reset_profile"), "Matched active-profile reset action.")
        if label == "delete current profile":
            return mark_registry_family(row, action_with_key(actions, "delete_profile"), "Matched profile delete action.")
        if label == "auto switch profile by specialization":
            return mark_registry_family(row, settings_with_keys(settings, {"profiles.specAutoSwitch"}), "Matched profile spec auto-switch setting.")
        if label.startswith("dynamic s name"):
            return mark_registry_family(row, action_with_key(actions, "set_spec_profile") + action_with_key(actions, "clear_spec_profile"), "Matched dynamic specialization profile assignment actions.")
        if label == "export kind":
            return mark_known_gap(row, "Profile export-kind staging dropdown; Assistant passes the requested kind directly to export_profile.", "partial", "export_profile")
        if label == "profile string":
            return mark_known_gap(row, "Profile-string staging input/output; Assistant export/import actions provide or consume the string directly.", "partial", "export_profile|import_profile_string|import_profile_string_new|import_legacy_profile_string")
        if label == "export":
            return mark_registry_family(row, action_with_key(actions, "export_profile"), "Matched profile export action.")
        if label == "import to current profile":
            return mark_registry_family(row, action_with_key(actions, "import_profile_string"), "Matched active-profile import action.")
        if label == "import and create new profile":
            return mark_known_gap(row, "New-profile import mode toggle; Assistant uses import_profile_string_new with the target name directly.", "partial", "import_profile_string_new")
        if label == "new profile name":
            return mark_known_gap(row, "New-profile import name staging input; Assistant passes the target profile name directly to import_profile_string_new.", "partial", "import_profile_string_new")
        if label == "import legacy":
            return mark_registry_family(row, action_with_key(actions, "import_legacy_profile_string"), "Matched legacy profile import action.")
        if label == "browse wago profiles":
            return mark_registry_family(row, action_with_key(actions, "copy_wago_profiles_link"), "Matched Wago profile link action.")
        if label == "dropdown style":
            return mark_registry_family(row, settings_with_keys(settings, {"general.dropdownStyleMode"}), "Matched dropdown style setting.")

    if "MSUF_Menu2_GlobalBars.lua" in ui_file:
        def global_bar_settings(suffixes: set[str]) -> list[RegistryRow]:
            return [
                setting for setting in settings
                if setting.key.split(".")[-1] in suffixes
                and setting.frame_type in {"globalBars", "bars", "colors"}
                and not setting.key.startswith("gf_")
            ]

        suffix_by_label = {
            "bar textures sharedmedia": "barTexture",
            "background texture": "barBackgroundTexture",
            "hp bar gradient": "enableGradient",
            "power bar gradient": "enablePowerGradient",
            "display mode": "absorbTextMode",
            "outline color": "barOutlineColor",
            "highlight border thickness": "highlightBorderThickness",
            "dispel border detects": "dispelBorderTrigger",
            "boss target border": "bossTargetOutlineMode",
            "unitframe dispel overlay": "unitDispelOverlayEnabled",
            "custom highlight priority": "hlPrioEnabled",
            "smooth power bar": "smoothPowerBar",
            "realtime power text": "realtimePowerText",
        }
        suffix = suffix_by_label.get(label)
        if suffix:
            return mark_registry_family(row, global_bar_settings({suffix}), "Matched Global Bars control to global/scoped Assistant setting.")
        if label.startswith("dynamic text") and row.function == "PadButton":
            return mark_registry_family(row, global_bar_settings({"gradientDirection"}), "Matched gradient direction pad buttons to global/scoped gradient-direction settings.")
        if label == "test prediction bars":
            return mark_registry_family(row, action_with_key(actions, "toggle_absorb_bar_test"), "Matched absorb prediction-bar test action.")
        if label in {"test aggro border", "test dispel border", "test purge border", "test boss target border"}:
            return mark_registry_family(row, action_with_key(actions, "toggle_highlight_border_test"), "Matched highlight-border test action.")
        if label == "dispel test type":
            return mark_registry_family(row, action_with_key(actions, "set_dispel_border_test_type"), "Matched transient dispel-border test type action.")
        if row.function == "BindBorderTestToggle" and label.startswith("dynamic"):
            return mark_registry_family(row, action_with_key(actions, "toggle_highlight_border_test"), "Matched highlight-border test toggle factory to Assistant highlight-border test action.")
        if row.function == "BindUFOverlayToggle" and label.startswith("dynamic"):
            return mark_known_gap(row, "UnitFrame Dispel Overlay toggle factory helper; concrete overlay settings are audited through their call sites.", "todo")

    if "MSUF_Menu2_GlobalCastbars.lua" in ui_file:
        if row.function == "ApplyAndRefresh" and label.startswith("dynamic spec"):
            return mark_registry_family(row, settings_with_keys(settings, {
                "general.castbarShowGlow", "general.castbarShowLatency",
                "general.castbarShowSpark", "general.castbarSparkOverflow",
            }), "Matched castbar texture/outline loop toggles to registered castbar appearance settings.")

    if "MSUF_Menu2_GroupIndicators.lua" in ui_file:
        group_scopes = ("party", "raid", "mythicraid")
        corner_slots = ("TL", "TR", "BL", "BR", "C")

        def group_keys(suffix: str) -> set[str]:
            return {f"gf_{scope}.{suffix}" for scope in group_scopes}

        def corner_custom_keys(suffix: str) -> set[str]:
            return {f"gf_{scope}.ciCustom{slot}.{suffix}" for scope in group_scopes for slot in corner_slots}

        suffix_by_label = {
            "group number": "showGroupNumber",
            "focus highlight": "hlFocusEnabled",
            "focus glow color": "hlFocusColor",
            "group border": "groupBorderEnabled",
            "padding": "groupBorderPadding",
            "group border color": "groupBorderColor",
            "icon style": "iconStyle",
            "use midnight style": "useMidnightIcons",
            "tank": "roleIconShowTank",
            "healer": "roleIconShowHealer",
            "dps": "roleIconShowDPS",
            "corner indicators": "ciEnabled",
            "icon size": "ciSize",
            "alpha": "ciAlpha",
        }
        suffix = suffix_by_label.get(label)
        if label == "size" and row.line == 73:
            suffix = "groupNumberSize"
        elif label == "anchor" and row.line == 74:
            suffix = "groupNumberAnchor"
        elif label == "x offset" and row.line == 75:
            suffix = "groupNumberX"
        elif label == "y offset" and row.line == 76:
            suffix = "groupNumberY"
        if suffix:
            return mark_registry_family(row, settings_with_suffix(settings, {suffix}, "group"), "Matched Group Indicators control to scoped group-frame setting.")

        if label == "status icon controls":
            return mark_known_gap(row, "Runtime Basic/Advanced status-icon tab selector; Assistant changes the concrete status-icon fields directly.", "todo")
        if label == "indicator":
            return mark_known_gap(row, "Runtime selected-status-icon dropdown; Assistant targets concrete group status icons by phrase.", "todo")
        if label == "enabled" and row.function == "BindStatusSlider":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "roleIcon", "leaderIcon", "assistIcon", "raidMarker", "readyCheckIcon", "summonIcon",
                "resurrectIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText",
            }, "group"), "Matched dynamic selected group status-icon enabled settings.")
        if label == "icon pack":
            return mark_registry_family(row, settings_with_suffix(settings, {"roleIconStyle", "leaderIconStyle", "assistIconStyle"}, "group"), "Matched dynamic selected group status-icon icon-pack settings.")
        if label in {"preview current", "show all"}:
            return mark_registry_family(row, action_with_key(actions, "preview_group_status_icon"), "Matched group status-icon preview action.")
        if label == "reset selected":
            return mark_registry_family(row, action_with_key(actions, "reset_group_status_icon"), "Matched group status-icon reset action.")
        if label in {"size", "anchor", "x offset", "y offset", "x offset extended", "y offset extended", "layer"} and row.line < 430:
            suffixes_by_label = {
                "size": {"roleIconSize", "leaderIconSize", "assistIconSize", "raidMarkerSize", "readyCheckSize", "summonIconSize", "resurrectIconSize", "phaseIconSize", "statusTextSize", "statusGhostTextSize", "statusAFKTextSize"},
                "anchor": {"roleIconAnchor", "leaderIconAnchor", "assistIconAnchor", "raidMarkerAnchor", "readyCheckAnchor", "summonAnchor", "resurrectAnchor", "phaseAnchor", "statusTextAnchor", "statusGhostTextAnchor", "statusAFKTextAnchor"},
                "x offset": {"roleIconX", "leaderIconX", "assistIconX", "raidMarkerX", "readyCheckX", "summonX", "resurrectX", "phaseX", "statusOffsetX", "statusGhostOffsetX", "statusAFKOffsetX"},
                "x offset extended": {"roleIconX", "leaderIconX", "assistIconX", "raidMarkerX", "readyCheckX", "summonX", "resurrectX", "phaseX", "statusOffsetX", "statusGhostOffsetX", "statusAFKOffsetX"},
                "y offset": {"roleIconY", "leaderIconY", "assistIconY", "raidMarkerY", "readyCheckY", "summonY", "resurrectY", "phaseY", "statusOffsetY", "statusGhostOffsetY", "statusAFKOffsetY"},
                "y offset extended": {"roleIconY", "leaderIconY", "assistIconY", "raidMarkerY", "readyCheckY", "summonY", "resurrectY", "phaseY", "statusOffsetY", "statusGhostOffsetY", "statusAFKOffsetY"},
                "layer": {"roleIconLayer", "leaderIconLayer", "assistIconLayer", "raidMarkerLayer", "readyCheckLayer", "summonLayer", "resurrectLayer", "phaseLayer", "statusTextLayer", "statusGhostTextLayer", "statusAFKTextLayer"},
            }
            return mark_registry_family(row, settings_with_suffix(settings, suffixes_by_label[label], "group"), "Matched dynamic selected group status-icon placement settings.")

        if label.startswith("dynamic tr spell indicators"):
            return mark_registry_family(row, settings_with_keys(settings, group_keys("spellIndicators.enabled")), "Matched spell-indicator root enabled setting.")
        if label == "layer" and row.line == 547:
            return mark_registry_family(row, settings_with_keys(settings, group_keys("spellIndicators.layer")), "Matched spell-indicator layer setting.")
        if label.startswith("dynamic tr spec"):
            return mark_registry_family(row, settings_with_keys(settings, group_keys("spellIndicators.spec")), "Matched spell-indicator spec setting.")
        if label.startswith("dynamic tr multi spec entry"):
            return mark_known_gap(row, "Runtime selected multi-spec dropdown; Assistant toggles a concrete multi-spec entry by spec name.", "todo")
        if label.startswith("dynamic tr track selected multi spec"):
            return mark_registry_family(row, action_with_key(actions, "set_group_spell_indicator_multi_spec"), "Matched spell-indicator multi-spec tracking action.")
        if label.startswith("dynamic tr spell"):
            return mark_known_gap(row, "Runtime selected-spell dropdown; Assistant targets concrete spell-indicator auras by name or spell ID.", "todo")
        if label.startswith("dynamic tr enabled") or label.startswith("dynamic tr only my cast"):
            return mark_registry_family(row, action_with_key(actions, "set_group_spell_indicator_aura"), "Matched dynamic selected spell-indicator aura action.")
        if (
            row.function in {"BindPlacedDropdown", "BindPlacedSlider", "BindPlacedToggle", "BindFrameSlider", "ToggleSpellIndicator"}
            or label in {"indicator type", "anchor", "size", "x offset", "y offset", "bar width", "growth", "frame effect", "color", "priority", "tint alpha", "border glow thickness", "show when missing", "cooldown text size"}
        ) and 830 <= row.line <= 1040:
            return mark_registry_family(row, action_with_key(actions, "set_group_spell_indicator_aura"), "Matched dynamic selected spell-indicator aura field action.")

        if label.startswith("dynamic slotinfo text or slotkey indicator"):
            return mark_registry_family(row, settings_with_suffix(settings, {"ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC"}, "group"), "Matched corner-indicator slot assignment settings.")
        if label == "editor slot":
            return mark_known_gap(row, "Runtime selected corner-editor slot; Assistant targets concrete corner slots by phrase.", "todo")
        if label == "selected slot indicator":
            return mark_registry_family(row, settings_with_suffix(settings, {"ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC"}, "group"), "Matched selected corner-indicator slot assignment settings.")
        if label == "spell ids comma separated":
            return mark_registry_family(row, settings_with_keys(settings, corner_custom_keys("spells")), "Matched corner-indicator custom spell-ID settings.")
        if label == "when":
            return mark_registry_family(row, settings_with_keys(settings, corner_custom_keys("mode")), "Matched corner-indicator custom mode settings.")
        if label == "filter":
            return mark_registry_family(row, settings_with_keys(settings, corner_custom_keys("filter")), "Matched corner-indicator custom filter settings.")
        if label == "custom color":
            return mark_registry_family(row, settings_with_keys(settings, corner_custom_keys("color")), "Matched corner-indicator custom color settings.")

    if "MSUF_Menu2_GroupBars.lua" in ui_file:
        suffix_by_label = {
            "dispel overlay": "dispelOverlayEnabled",
            "overlay detects": "dispelOverlayTrigger",
            "overlay style": "dispelOverlayStyle",
            "show on current health only": "dispelOverlayOnHealth",
            "overlay opacity": "dispelOverlayAlpha",
            "bar color mode": "gfBarMode",
            "health bar": "healthBarColor",
            "foreground texture": "barTexture",
            "background texture": "barBgTexture",
            "health color mode": "healthColorMode",
            "show power bar": "powerBarEnabled",
            "power height": "powerHeight",
            "smooth fill": "powerSmoothFill",
            "tank": "powerShowTank",
            "healer": "powerShowHealer",
            "dps": "powerShowDamager",
            "show name": "showName",
            "hide name on dead offline": "hideNameOnDeadOffline",
            "name layer": "nameTextLayer",
            "hp layer": "textLayer",
            "power layer": "powerTextLayer",
            "debuff stripe": "debuffStripeEnabled",
            "stripe edge": "debuffStripeEdge",
            "stripe height": "debuffStripeHeight",
            "stripe opacity": "debuffStripeAlpha",
            "range fade": "rangeFadeEnabled",
            "affects": "rangeFadeLayerMode",
            "rangefadealpha": "rangeFadeAlpha",
            "offlinealpha": "offlineAlpha",
        }
        suffix = suffix_by_label.get(label)
        if label == "anchor" and row.function == "SetPowerTextEnabled":
            suffix = "nameAnchor"
        elif label == "x offset" and row.function == "SetPowerTextEnabled":
            suffix = "nameOffsetX"
        elif label == "y offset" and row.function == "SetPowerTextEnabled":
            suffix = "nameOffsetY"
        elif label == "size" and row.function == "SetPowerTextEnabled":
            suffix = "nameFontSize"
        if suffix:
            return mark_registry_family(row, settings_with_suffix(settings, {suffix}, "group"), "Matched Group Bars control to scoped group-frame setting.")
        if label == "text area":
            return mark_known_gap(row, "Runtime Text area tab selector; Assistant targets the concrete group text settings directly.", "todo")
        if label in {"hidden", "font"} and row.function == "BuildValueTextTab":
            return mark_registry_family(row, settings_with_suffix(settings, {"showHPText", "showPowerText"}, "group"), "Matched dynamic HP/power text visibility controls.")
        if label == "visual" and row.function == "SlotControl":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "textLeft", "textCenter", "textRight",
                "powerTextLeft", "powerTextCenter", "powerTextRight",
            }, "group"), "Matched dynamic HP/power text slot-mode controls.")
        if label == "delimiter":
            return mark_registry_family(row, settings_with_suffix(settings, {"textDelimiter", "powerTextDelimiter"}, "group"), "Matched dynamic HP/power text delimiter controls.")
        if label == "reverse order":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpTextReverse"}, "group"), "Matched HP text reverse-order setting.")
        if label == "x offset" and row.function == "SlotControl":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpOffsetX", "powerOffsetX"}, "group"), "Matched dynamic HP/power group text X offset controls.")
        if label == "y offset" and row.function == "SlotControl":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpOffsetY", "powerOffsetY"}, "group"), "Matched dynamic HP/power group text Y offset controls.")
        if label == "move text as one group":
            return mark_known_gap(row, "Runtime editor toggle only; Assistant sets whole-text offsets and per-slot offsets directly.", "todo")
        if label == "slot":
            return mark_known_gap(row, "Runtime selected-slot selector only; Assistant targets concrete left/center/right slot offset settings directly.", "todo")
        if label.startswith("dynamic slot") or row.function == "SlotAxis":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "hpTextLeftOffsetX", "hpTextCenterOffsetX", "hpTextRightOffsetX",
                "powerTextLeftOffsetX", "powerTextCenterOffsetX", "powerTextRightOffsetX",
                "hpTextLeftOffsetY", "hpTextCenterOffsetY", "hpTextRightOffsetY",
                "powerTextLeftOffsetY", "powerTextCenterOffsetY", "powerTextRightOffsetY",
            }, "group"), "Matched dynamic selected-slot offset controls.")
        if label == "size" and row.function == "SlotAxis":
            return mark_registry_family(row, settings_with_suffix(settings, {"hpFontSize", "powerFontSize"}, "group"), "Matched dynamic HP/power text font-size controls.")

    if "MSUF_Menu2_GroupLayout.lua" in ui_file:
        suffix_by_label = {
            "use msuf group frames": "enabled",
            "show player": "showPlayer",
            "show while solo": "showSolo",
            "smooth health fill": "smoothFill",
            "reverse fill direction": "reverseFill",
            "hide during client scene": "hideInClientScene",
            "click casting clique": "clickCastEnabled",
            "if this switch is off": "blizzardFallbackMode",
            "blizzardfallbackmode": "blizzardFallbackMode",
            "offline members": "hideOfflineEnabled",
            "hide offline in combat": "hideOfflineInCombat",
            "hide offline after": "hideOfflineDelay",
            "width": "width",
            "height": "height",
            "spacing": "spacing",
            "units per column": "unitsPerColumn",
            "max columns": "maxColumns",
            "preserve raid groups": "preserveRaidGroups",
            "sort mode": "sortMode",
            "sort by role": "sortByRole",
            "player first in role": "playerFirstInRole",
            "frame scaling": "frameScaleEnabled",
            "scale mode": "frameScaleMode",
            "framescalemanual": "frameScaleManual",
            "scaleat10": "scaleAt10",
            "scaleat20": "scaleAt20",
            "scaleat25": "scaleAt25",
            "scaleover25": "scaleOver25",
            "in combat": "alphaCurrentInCombat",
            "out of combat": "alphaCurrentOutOfCombat",
            "sync both": "alphaSync",
            "affects": "opacityMode",
            "background color": "bgColor",
            "bga": "bgA",
            "hpbaralpha": "hpBarAlpha",
            "preserve hp color": "alphaPreserveHPColor",
            "text ignores hp opacity": "hpTextIgnoreAlpha",
            "anchor to": "anchorToFrame",
            "anchor point": "anchorPoint",
            "anchorpoint": "anchorPoint",
        }
        suffix = suffix_by_label.get(label)
        if not suffix and label == "" and row.function == "BindTransparencySlider":
            suffix = "hpBgAlpha"
        if suffix:
            return mark_registry_family(row, settings_with_suffix(settings, {suffix}, "group"), "Matched Group Layout control to scoped group-frame setting.")
        if label == "pick":
            return mark_known_gap(row, "Interactive group anchor picker overlay; Assistant supports the resulting custom anchor frame name via group customAnchorFrame.", "partial", "gf_party.customAnchorFrame|gf_raid.customAnchorFrame|gf_mythicraid.customAnchorFrame")
        if label == "clear":
            return mark_registry_family(row, action_with_key(actions, "clear_group_custom_anchor"), "Matched Assistant action that clears the group custom anchor frame.")

    if "MSUF_Menu2_UnitStatusSection.lua" in ui_file:
        if label == "status icon controls":
            return mark_known_gap(row, "Runtime Basic/Advanced tab selector; Assistant changes the concrete status fields directly.", "todo")
        if label == "indicator":
            return mark_known_gap(row, "Runtime selected-indicator dropdown; Assistant targets concrete indicators by phrase.", "todo")
        if label == "use midnight style":
            return mark_registry_family(row, settings_with_keys(settings, {"general.statusIconsUseMidnightStyle"}), "Matched global status-icon style setting.")
        if label == "enabled":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "showLeaderIcon", "showRaidMarker", "showLevelIndicator", "showRaidGroupInName", "showEliteIcon",
                "statusTextEnabled", "showCombatStateIndicator", "showRestingIndicator", "showIncomingResIndicator",
            }, "unitframe"), "Matched dynamic selected status-indicator enabled settings.")
        if label == "symbol":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "combatStateIndicatorSymbol", "restedStateIndicatorSymbol", "incomingResIndicatorSymbol",
            }, "unitframe"), "Matched dynamic selected status-indicator symbol settings.")
        if label == "icon pack":
            return mark_registry_family(row, settings_with_suffix(settings, {"leaderIconStyle"}, "unitframe"), "Matched dynamic selected status-indicator icon-pack settings.")
        if label.startswith("dynamic info text"):
            return mark_registry_family(row, settings_with_keys(settings, {
                "general.statusIndicators.showDead", "general.statusIndicators.showGhost",
                "general.statusIndicators.showAFK", "general.statusIndicators.showDND",
            }), "Matched dynamic dead-text state toggles.")
        if label == "size":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "leaderIconSize", "raidMarkerSize", "levelIndicatorSize", "nameFontSize", "eliteIconSize",
                "statusTextSize", "combatStateIndicatorSize", "restedStateIndicatorSize", "incomingResIndicatorSize",
            }, "unitframe"), "Matched dynamic selected status-indicator size settings.")
        if label == "anchor":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "leaderIconAnchor", "raidMarkerAnchor", "levelIndicatorAnchor", "raidGroupNameAnchor", "eliteIconAnchor",
                "statusTextAnchor", "combatStateIndicatorAnchor", "restedStateIndicatorAnchor", "incomingResIndicatorAnchor",
            }, "unitframe"), "Matched dynamic selected status-indicator anchor settings.")
        if "x offset" in label:
            return mark_registry_family(row, settings_with_suffix(settings, {
                "leaderIconOffsetX", "raidMarkerOffsetX", "levelIndicatorOffsetX", "raidGroupNameOffsetX", "eliteIconOffsetX",
                "statusTextOffsetX", "combatStateIndicatorOffsetX", "restedStateIndicatorOffsetX", "incomingResIndicatorOffsetX",
            }, "unitframe"), "Matched dynamic selected status-indicator X offset settings.")
        if "y offset" in label:
            return mark_registry_family(row, settings_with_suffix(settings, {
                "leaderIconOffsetY", "raidMarkerOffsetY", "levelIndicatorOffsetY", "raidGroupNameOffsetY", "eliteIconOffsetY",
                "statusTextOffsetY", "combatStateIndicatorOffsetY", "restedStateIndicatorOffsetY", "incomingResIndicatorOffsetY",
            }, "unitframe"), "Matched dynamic selected status-indicator Y offset settings.")
        if label == "layer":
            return mark_registry_family(row, settings_with_suffix(settings, {
                "leaderIconLayer", "raidMarkerLayer", "levelIndicatorLayer", "nameTextLayer", "eliteIconLayer",
                "statusTextLayer", "combatStateIndicatorLayer", "restedStateIndicatorLayer", "incomingResIndicatorLayer",
            }, "unitframe"), "Matched dynamic selected status-indicator layer settings.")
        if label == "reset selected":
            return mark_registry_family(row, action_with_key(actions, "reset_unit_status_indicator"), "Matched Assistant reset action for the selected status-indicator family.")
        if label == "preview current":
            return mark_registry_family(row, action_with_key(actions, "preview_unit_status_indicator"), "Matched Assistant status-preview action in current mode.")
        if label == "show all":
            return mark_registry_family(row, action_with_key(actions, "preview_unit_status_indicator"), "Matched Assistant status-preview action in all-indicators mode.")

    if "MSUF_Menu2_UnitSections.lua" in ui_file:
        if row.function == "ShowCopyPopup" and label.startswith("dynamic cat label"):
            return mark_registry_family(row, action_with_key(actions, "copy_unit"), "Matched unit-copy action with category scope arguments.")
        if row.function == "BuildBasics" and label == "enable" and row.control_type == "button":
            return mark_registry_family(row, settings_with_suffix(settings, {"enabled"}, "unitframe"), "Matched frame-enabled setting used by the enable-now button.")
        if row.function in {"CommitCustomAnchor", "PickCustomAnchor"} and label == "pick":
            return mark_known_gap(row, "Interactive picker overlay; Assistant supports the resulting custom anchor frame name via unit.anchorFrameName.", "partial", "player.anchorFrameName|target.anchorFrameName|focus.anchorFrameName")
        if row.function in {"CommitCustomAnchor", "PickCustomAnchor"} and label == "clear":
            return mark_registry_family(row, action_with_key(actions, "clear_unit_custom_anchor"), "Matched Assistant action that clears the custom anchor frame.")
        if row.function == "BuildInlineText" and label == "custom separator":
            return mark_registry_family(row, settings_with_keys(settings, {"targettarget.totInlineCustomSeparator"}), "Matched Target of Target inline custom separator setting.")
        if row.function == "BuildLoadConditions" and label.startswith("dynamic"):
            return mark_registry_family(row, settings_with_suffix(settings, {
                "loadCondHideMounted", "loadCondHideOutOfCombat", "loadCondHideSolo", "loadCondHideInVehicle",
                "loadCondHideInGroup", "loadCondHideInInstance", "loadCondHideResting", "loadCondHideInCombat",
                "loadCondHideStealthed",
            }, "unitframe"), "Matched dynamic load-condition toggle settings.")

    return False


def extract_apply_from_window(text: str) -> str:
    names = [
        "ApplyCastbars",
        "ApplyCastbarTextures",
        "ApplyBars",
        "ApplyFonts",
        "ApplyGameplay",
        "ApplyGroup",
        "ApplyAura",
        "ApplyUnit",
        "RequestGeneralApply",
        "RequestUnitApply",
        "QueueGF",
        "Refresh",
    ]
    found = [name for name in names if name in text]
    return "|".join(dict.fromkeys(found))


def values_for_control(control_type: str, args: list[str]) -> str:
    if control_type == "slider":
        nums = []
        for arg in args[2:5]:
            nums.append(clean(arg))
        return "min={};max={};step={}".format(*(nums + ["", "", ""])[:3])
    if control_type in {"dropdown", "segment"}:
        return clean(args[2]) if len(args) > 2 else ""
    if control_type == "color":
        return "rgb 0..1"
    return ""


def helper_values_for_control(control_type: str, args: list[str], min_idx: int | None, max_idx: int | None, step_idx: int | None, values_idx: int | None) -> str:
    if control_type == "slider":
        if min_idx is None and max_idx is None and step_idx is not None:
            return f"min=0;max=100;step={clean(args[step_idx]) if len(args) > step_idx else ''}"
        nums = [
            clean(args[min_idx]) if min_idx is not None and len(args) > min_idx else "",
            clean(args[max_idx]) if max_idx is not None and len(args) > max_idx else "",
            clean(args[step_idx]) if step_idx is not None and len(args) > step_idx else "",
        ]
        return "min={};max={};step={}".format(*nums)
    if control_type in {"dropdown", "segment"} and values_idx is not None and len(args) > values_idx:
        return clean(args[values_idx])
    if control_type == "color":
        return "rgb 0..1"
    return ""


def helper_label(args: list[str], label_idx: int | None) -> str:
    if label_idx is None or len(args) <= label_idx:
        return ""
    value = unquote(args[label_idx])
    if value is not None:
        return value
    return f"<dynamic:{clean(args[label_idx]) or 'label'}>"


def helper_key(args: list[str], key_idx: int | None, label: str) -> str:
    if key_idx is not None and len(args) > key_idx:
        value = unquote(args[key_idx])
        if value and KEYISH.match(value):
            return value
    strings = [q for arg in args for q in ([unquote(arg)] if unquote(arg) is not None else [])]
    return extract_key(strings, label)


def load_registry() -> tuple[list[RegistryRow], list[RegistryRow]]:
    lua_files = "\n".join(f'  "{(ASSISTANT / name).as_posix()}",' for name in REGISTRY_FILES)
    script = f"""
_G = _G or _ENV
_G.MSUF_NS = {{ MSUF2 = {{}} }}
local MSUF = _G.MSUF_NS
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {{ general = {{}}, bars = {{}}, gameplay = {{}} }}
local files = {{
{lua_files}
}}
local function esc(v)
  v = tostring(v or "")
  v = v:gsub("\\t", " "):gsub("\\r", " "):gsub("\\n", " ")
  return v
end
local function join(tbl)
  if type(tbl) ~= "table" then return "" end
  local out = {{}}
  for k, v in pairs(tbl) do
    if type(k) == "number" then out[#out + 1] = tostring(v) else out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  table.sort(out)
  return table.concat(out, "|")
end
for _, path in ipairs(files) do
  local chunk, err = loadfile(path)
  assert(chunk, err)
  chunk("MidnightSimpleUnitFrames", MSUF)
end
local R = MSUF.Assistant.Registry
for _, s in ipairs(R.settings or {{}}) do
  print(table.concat({{
    "SETTING", esc(s.key), esc(s.label), esc(s.category), esc(s.frameType), esc(s.unit), esc(s.attribute), esc(s.type),
    join(s.values), esc(s.min), esc(s.max), esc(s.step), join(s.aliases)
  }}, "\\t"))
end
for _, a in ipairs(R.actions or {{}}) do
  print(table.concat({{
    "ACTION", esc(a.key), esc(a.label), esc(a.category), esc(a.type), esc(a.unit), "", "action",
    "", "", "", "", join(a.aliases)
  }}, "\\t"))
end
"""
    proc = subprocess.run(["lua", "-"], input=script, text=True, capture_output=True, cwd=ROOT, check=True)
    settings: list[RegistryRow] = []
    actions: list[RegistryRow] = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 13:
            continue
        row = RegistryRow(
            kind=parts[0],
            key=parts[1],
            label=parts[2],
            category=parts[3],
            frame_type=parts[4],
            unit=parts[5],
            attribute=parts[6],
            control_type=parts[7],
            values=parts[8],
            min_value=parts[9],
            max_value=parts[10],
            step=parts[11],
            aliases=parts[12],
        )
        if row.kind == "SETTING":
            settings.append(row)
        else:
            actions.append(row)
    return settings, actions


def scan_ui() -> list[UiRow]:
    rows: list[UiRow] = []
    seen: set[tuple[str, int, str, str]] = set()
    for path in source_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        page = page_keys_for_file(text)
        lines = text.splitlines()
        factory_functions = factory_functions_for_file(path)
        current_function = ""
        current_section = ""
        for idx, line in enumerate(lines):
            line_no = idx + 1
            fn = re.match(r"\s*local function\s+([A-Za-z_][A-Za-z0-9_]*)", line)
            if fn:
                current_function = fn.group(1)
            sec = infer_section(line, current_function)
            if sec and sec != current_function:
                current_section = sec

            if current_function in factory_functions:
                continue

            matched = False
            for control_type, pattern in CONTROL_PATTERNS:
                match = pattern.search(line)
                if not match:
                    continue
                args = split_args(call_arg_text(match))
                label = extract_label(control_type, args)
                label_arg = args[1].strip() if len(args) > 1 else ""
                if not label and not explicit_empty_label(args):
                    if current_function.lower().startswith(("bind", "create")) and label_arg == "label":
                        continue
                    label = f"<dynamic:{label_arg or 'label'}>"
                win = binding_text(lines, idx)
                db_key = extract_db_from_window(win)
                key = (str(path.relative_to(ROOT)), line_no, control_type, label)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(UiRow(
                    ui_file=str(path.relative_to(ROOT)).replace("\\", "/"),
                    line=line_no,
                    function=current_function,
                    page=page,
                    label=label,
                    section=current_section or current_function,
                    control_type=control_type,
                    db_key_or_helper=db_key,
                    values_min_max_step=values_for_control(control_type, args),
                    apply_helper=extract_apply_from_window(win),
                    registry_key="",
                    status="unmapped",
                    reason="No Assistant registry key was matched by exact DB key or label.",
                ))
                matched = True
                break
            if matched:
                continue

            for name, control_type, label_idx, key_idx, values_idx, min_idx, max_idx, step_idx in HELPER_CALL_SPECS:
                if re.match(r"\s*(?:local\s+)?function\s+", line):
                    continue
                if name not in line:
                    continue
                statement = full_call_text(lines, idx)
                args = helper_call_args(statement, name)
                if not args:
                    continue
                label = helper_label(args, label_idx)
                if name == "BuildDashboardChangelog":
                    title_match = re.search(r'\btitle\s*=\s*"([^"]+)"', statement)
                    label = title_match.group(1) if title_match else "Changelog"
                if not label:
                    continue
                win = statement + "\n" + binding_text(lines, idx)
                db_key = "dashboardChangelogOpen" if name == "BuildDashboardChangelog" else (helper_key(args, key_idx, label) or extract_db_from_window(win))
                key = (str(path.relative_to(ROOT)), line_no, control_type, label)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(UiRow(
                    ui_file=str(path.relative_to(ROOT)).replace("\\", "/"),
                    line=line_no,
                    function=current_function,
                    page=page,
                    label=label,
                    section=current_section or current_function,
                    control_type=control_type,
                    db_key_or_helper=db_key or name,
                    values_min_max_step=helper_values_for_control(control_type, args, min_idx, max_idx, step_idx, values_idx),
                    apply_helper=extract_apply_from_window(win),
                    registry_key="",
                    status="unmapped",
                    reason="Helper callsite control; static audit could not prove registry mapping.",
                ))
                matched = True
                break
            if matched:
                continue

            for control_type, pattern in HELPER_PATTERNS:
                if re.match(r"\s*local function\s+", line):
                    continue
                match = pattern.search(line)
                if not match:
                    continue
                args = split_args(call_arg_text(match))
                strings = quoted_strings(line)
                if not strings:
                    continue
                label = extract_label(control_type, args) or extract_helper_label(strings)
                win = binding_text(lines, idx)
                db_key = extract_key_from_args(args, label) or extract_db_from_window(win) or extract_key(strings, label)
                key = (str(path.relative_to(ROOT)), line_no, control_type, label)
                if key in seen:
                    continue
                seen.add(key)
                rows.append(UiRow(
                    ui_file=str(path.relative_to(ROOT)).replace("\\", "/"),
                    line=line_no,
                    function=current_function,
                    page=page,
                    label=label,
                    section=current_section or current_function,
                    control_type=control_type,
                    db_key_or_helper=db_key or pattern.pattern.split("\\")[1],
                    values_min_max_step="",
                    apply_helper=extract_apply_from_window(win),
                    registry_key="",
                    status="unmapped",
                    reason="Helper-created control; static audit could not prove registry mapping.",
                ))
                break
    return rows


def apply_registry_mapping(rows: list[UiRow], settings: list[RegistryRow], actions: list[RegistryRow]) -> None:
    settings_by_suffix: dict[str, list[RegistryRow]] = {}
    settings_by_label: dict[str, list[RegistryRow]] = {}
    actions_by_label: dict[str, list[RegistryRow]] = {}
    for setting in settings:
        suffix = setting.key.split(".")[-1]
        settings_by_suffix.setdefault(suffix.lower(), []).append(setting)
        settings_by_label.setdefault(normalize(setting.label), []).append(setting)
        for alias in setting.aliases.split("|"):
            if alias:
                settings_by_label.setdefault(normalize(alias), []).append(setting)
    for action in actions:
        actions_by_label.setdefault(normalize(action.label), []).append(action)
        for alias in action.aliases.split("|"):
            if alias:
                actions_by_label.setdefault(normalize(alias), []).append(action)

    for row in rows:
        candidates: list[RegistryRow] = []
        if apply_synthetic_mapping(row, settings, actions):
            continue
        db = row.db_key_or_helper.lower()
        if row.control_type == "button":
            action_candidates = actions_by_label.get(normalize(row.label), [])
            if action_candidates:
                row.registry_key = "|".join(a.key for a in action_candidates[:3])
                row.status = "registered"
                row.reason = "Matched Assistant action by label/alias."
            continue
        if db:
            candidates = settings_by_suffix.get(db, [])
        if not candidates and row.label:
            candidates = settings_by_label.get(normalize(row.label), [])
            if not candidates:
                units = row_units(row)
                scoped_labels = []
                for unit in sorted(units):
                    unit_label = UNIT_LABELS.get(unit, unit)
                    scoped_labels.append(f"{unit_label} {row.label}")
                    scoped_labels.append(f"{unit} {row.label}")
                for scoped_label in scoped_labels:
                    candidates.extend(settings_by_label.get(normalize(scoped_label), []))
        if not candidates:
            candidates = synthetic_candidates(row, settings)
        candidates = filter_candidates_by_row_scope(row, candidates)
        candidates = unique_registry_rows(candidates)
        if len(candidates) == 1:
            row.registry_key = candidates[0].key
            row.status = "registered"
            row.reason = "Matched Assistant setting by DB key or label/alias."
        elif len(candidates) > 1:
            exact_type = [c for c in candidates if control_type_matches(row.control_type, c.control_type)]
            if len(exact_type) == 1:
                row.registry_key = exact_type[0].key
                row.status = "registered"
                row.reason = "Matched Assistant setting by DB key/label and control type."
            elif exact_type and db and all(c.key.split(".")[-1].lower() == db for c in exact_type):
                row.registry_key = "|".join(c.key for c in exact_type[:8])
                row.status = "registered"
                row.reason = "Matched page-scoped Assistant settings by DB key and control type."
            elif exact_type and len(exact_type) == len(candidates) and row_units(row):
                row.registry_key = "|".join(c.key for c in exact_type[:8])
                row.status = "registered"
                row.reason = "Matched page-scoped Assistant settings for this reused UI control."
            else:
                row.registry_key = "|".join(c.key for c in candidates[:5])
                row.status = "partial"
                row.reason = "Multiple Assistant settings match; needs explicit one-to-one mapping."


def write_matrix(rows: list[UiRow], settings: list[RegistryRow], actions: list[RegistryRow]) -> None:
    DOCS.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "ui_file",
        "line",
        "function",
        "page",
        "visible_label",
        "section",
        "control_type",
        "db_key_or_helper",
        "values_min_max_step",
        "apply_helper",
        "registry_key",
        "status",
        "reason",
    ]
    with OUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({
                "ui_file": row.ui_file,
                "line": row.line,
                "function": row.function,
                "page": row.page,
                "visible_label": row.label,
                "section": row.section,
                "control_type": row.control_type,
                "db_key_or_helper": row.db_key_or_helper,
                "values_min_max_step": row.values_min_max_step,
                "apply_helper": row.apply_helper,
                "registry_key": row.registry_key,
                "status": row.status,
                "reason": row.reason,
            })

    counts: dict[str, int] = {}
    for row in rows:
        counts[row.status] = counts.get(row.status, 0) + 1
    print(f"wrote {OUT.relative_to(ROOT)}")
    print(f"ui_rows {len(rows)}")
    print(f"registered_settings {len(settings)}")
    print(f"registered_actions {len(actions)}")
    for key in sorted(counts):
        print(f"{key} {counts[key]}")


def main() -> int:
    settings, actions = load_registry()
    rows = scan_ui()
    apply_registry_mapping(rows, settings, actions)
    write_matrix(rows, settings, actions)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
