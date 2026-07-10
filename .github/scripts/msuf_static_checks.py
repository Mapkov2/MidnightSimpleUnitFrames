#!/usr/bin/env python3
"""Minimal static checks for MidnightSimpleUnitFrames.

This intentionally stays small: Lua syntax, load-manifest reachability, and the
runtime ownership contracts that protect the shared scheduler/event bus,
castbar refresh pipeline, and group-frame refresh pipeline.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ADDON_ROOT = REPO_ROOT / "MidnightSimpleUnitFrames"
TOC = ADDON_ROOT / "MidnightSimpleUnitFrames.toc"
LOCALE_ADDON_ROOT = REPO_ROOT / "MidnightSimpleUnitFrames_Locales"
LOCALE_TOC = LOCALE_ADDON_ROOT / "MidnightSimpleUnitFrames_Locales.toc"
SUPPORTED_LOCALES = {
    "enUS", "enGB", "deDE", "esES", "esMX", "frFR",
    "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW",
}
ENGLISH_LOCALES = {"enUS", "enGB"}
NON_ENGLISH_LOCALES = SUPPORTED_LOCALES - ENGLISH_LOCALES
SKIP_DIRS = {"scripts", "docs"}
INTENTIONALLY_UNLOADED_LUA = {
    # Developer-only diagnostic tools. They are kept in source but excluded
    # from release loading so normal users pay no startup/runtime cost.
    "Features/Diagnostics/MSUF_ClickCoreProfiler.lua",
    "Features/Diagnostics/MSUF_Feature_ClickProbe.lua",
    "Features/Diagnostics/MSUF_Feature_DebugPosition.lua",
    "UnitFrames/Engine/Group/MSUF_UF_Group_Profiler.lua",
    "UnitFrames/Engine/MSUF_UF_PreviewDiagnostics.lua",
    # Superseded by the Borders/RoundedFrames highlight implementations.
    "UnitFrames/Engine/Elements/MSUF_UF_Highlight.lua",
}


class CheckError(RuntimeError):
    pass


def rel(path: Path) -> str:
    return path.resolve().relative_to(ADDON_ROOT.resolve()).as_posix()


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def should_skip(path: Path) -> bool:
    try:
        relative = path.resolve().relative_to(ADDON_ROOT.resolve())
    except ValueError:
        return True
    return any(part in SKIP_DIRS for part in relative.parts)


def all_lua_files() -> list[Path]:
    return sorted(path for path in ADDON_ROOT.rglob("*.lua") if not should_skip(path))


def normalize_ref(value: str) -> str:
    return value.strip().replace("\\", "/")


def resolve_ref(owner: Path, value: str) -> Path:
    value = normalize_ref(value)
    return (owner.parent / value).resolve()


def parse_load_refs() -> tuple[set[str], list[str]]:
    if not TOC.exists():
        raise CheckError(f"missing TOC: {TOC}")

    loaded_lua: set[str] = set()
    missing: list[str] = []
    xml_queue: list[Path] = []
    seen_xml: set[Path] = set()

    for toc in [TOC, LOCALE_TOC]:
        for line_no, line in enumerate(read(toc).splitlines(), 1):
            item = line.strip()
            if not item or item.startswith("#") or item.startswith("##"):
                continue
            if not re.search(r"\.(lua|xml)$", item, re.IGNORECASE):
                continue
            path = resolve_ref(toc, item)
            if not path.exists():
                missing.append(f"{toc.name}:{line_no}: {normalize_ref(item)}")
                continue
            if path.suffix.lower() == ".lua":
                loaded_lua.add(rel(path))
            elif path.suffix.lower() == ".xml":
                xml_queue.append(path)

    file_attr = re.compile(r'\bfile\s*=\s*"([^"]+\.(?:lua|xml))"', re.IGNORECASE)
    while xml_queue:
        xml = xml_queue.pop(0).resolve()
        if xml in seen_xml:
            continue
        seen_xml.add(xml)
        for line_no, line in enumerate(read(xml).splitlines(), 1):
            for match in file_attr.finditer(line):
                child = resolve_ref(xml, match.group(1))
                if not child.exists():
                    missing.append(f"{rel(xml)}:{line_no}: {normalize_ref(match.group(1))}")
                    continue
                if child.suffix.lower() == ".lua":
                    loaded_lua.add(rel(child))
                elif child.suffix.lower() == ".xml":
                    xml_queue.append(child)

    return loaded_lua, missing


def check_locale_addon_contracts() -> None:
    if not LOCALE_TOC.exists():
        raise CheckError(f"missing locale TOC: {LOCALE_TOC}")
    legacy_locale_addons = sorted(REPO_ROOT.glob("MidnightSimpleUnitFrames_Locale_*"))
    if legacy_locale_addons:
        names = ", ".join(path.name for path in legacy_locale_addons)
        raise CheckError(f"legacy per-locale addons must be removed: {names}")

    main_toc = read(TOC)
    companion_toc = read(LOCALE_TOC)
    locale_core = read(ADDON_ROOT / "Locales" / "MSUF_Localization.lua")
    require(
        locale_core,
        'local localeAddon = "MidnightSimpleUnitFrames_Locales"',
        "consolidated locale addon name",
    )
    require(
        locale_core,
        'if MSUF.LOCALE ~= "enUS" and MSUF.LOCALE ~= "enGB" then',
        "non-English LoadOnDemand condition",
    )
    require(locale_core, "loadAddOn(localeAddon)", "non-English locale LoadAddOn")
    require(companion_toc, "## LoadOnDemand: 1", "locale companion LoadOnDemand")
    require(companion_toc, "## X-MSUF-Locales:", "locale companion metadata")

    for locale in sorted(SUPPORTED_LOCALES):
        locale_ref = f"Locales\\{locale}.lua"
        locale_source = read(ADDON_ROOT / "Locales" / f"{locale}.lua")
        require(
            locale_source,
            f'if not MSUF or MSUF.LOCALE ~= "{locale}" then return end',
            f"{locale} active-pack guard",
        )
        if locale in ENGLISH_LOCALES:
            require(main_toc, locale_ref, f"main TOC {locale} source")
            if locale_ref in companion_toc:
                raise CheckError(f"English locale must not load from companion: {locale}")
        else:
            companion_ref = f"..\\MidnightSimpleUnitFrames\\{locale_ref}"
            require(companion_toc, companion_ref, f"locale companion {locale} source")
            if locale_ref in main_toc:
                raise CheckError(f"main TOC must not eagerly load locale pack {locale}")

    companion_refs = set(re.findall(r"Locales\\([A-Za-z]{4})\.lua", companion_toc))
    if companion_refs != NON_ENGLISH_LOCALES:
        missing = sorted(NON_ENGLISH_LOCALES - companion_refs)
        extra = sorted(companion_refs - NON_ENGLISH_LOCALES)
        raise CheckError(f"locale companion mismatch; missing={missing}, extra={extra}")


def check_luac(lua_files: list[Path]) -> None:
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if not luac:
        raise CheckError("luac is not available")

    failures: list[str] = []
    for path in lua_files:
        proc = subprocess.run([luac, "-p", str(path)], capture_output=True, text=True)
        if proc.returncode != 0:
            failures.append(f"{rel(path)}: {(proc.stderr or proc.stdout).strip()}")
    if failures:
        raise CheckError("luac failures:\n" + "\n".join(failures[:30]))


def check_load_reachability(lua_files: list[Path]) -> None:
    loaded_lua, missing = parse_load_refs()
    if missing:
        raise CheckError("missing load references:\n" + "\n".join(missing[:30]))

    production_lua = {rel(path) for path in lua_files}
    stale_allowlist = sorted(INTENTIONALLY_UNLOADED_LUA - production_lua)
    if stale_allowlist:
        raise CheckError("stale intentionally-unloaded Lua entries:\n" + "\n".join(stale_allowlist))

    unreachable = sorted(production_lua - loaded_lua - INTENTIONALLY_UNLOADED_LUA)
    if unreachable:
        raise CheckError("Lua files not reachable from TOC/XML:\n" + "\n".join(unreachable[:30]))


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise CheckError(f"{label}: missing `{needle}`")


def require_count(text: str, needle: str, expected: int, label: str) -> None:
    actual = text.count(needle)
    if actual != expected:
        raise CheckError(f"{label}: expected {expected} `{needle}`, found {actual}")


def check_kernel_castbar_contracts() -> None:
    util = read(ADDON_ROOT / "Kernel" / "MSUF_Util.lua")
    scheduler = read(ADDON_ROOT / "Kernel" / "MSUF_Scheduler.lua")
    event_bus = read(ADDON_ROOT / "Kernel" / "MSUF_EventBus.lua")
    driver = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarDriver.lua")
    empower = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarEmpower.lua")
    player = read(ADDON_ROOT / "Castbars" / "MSUF_PlayerCastbarRuntime.lua")
    utils = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarUtils.lua")
    style = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarStyle.lua")
    core = read(ADDON_ROOT / "Castbars" / "MSUF_Castbars_Core.lua")
    visuals = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarVisuals.lua")
    previews = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarPreviews.lua")
    focus_kick = read(ADDON_ROOT / "Castbars" / "MSUF_FocusKickIcon.lua")
    manager = read(ADDON_ROOT / "Castbars" / "MSUF_Castbars.lua")
    font_runtime = read(ADDON_ROOT / "Runtime" / "MSUF_FontRuntime.lua")

    require(util, 'ExportPublic("MSUF_SafeCall"', "SafeCall export")
    require(scheduler, "SafeCall(cb)", "Scheduler protected callback")
    require(event_bus, "SafeCall(h.fn, event, ...)", "EventBus protected handler")

    compact = re.sub(
        r"\s+",
        "",
        driver
        + "\n" + empower
        + "\n" + player
        + "\n" + utils
        + "\n" + core
        + "\n" + visuals
        + "\n" + previews
        + "\n" + focus_kick
        + "\n" + manager,
    )
    for marker in ["Legacy/minified", "locale,e=", "localn=GetTime", "function(e,n,t"]:
        if marker in compact:
            raise CheckError(f"Castbar refactor target still contains minified marker `{marker}`")

    for text, filename in [
        (driver, "MSUF_CastbarDriver.lua"),
        (empower, "MSUF_CastbarEmpower.lua"),
        (player, "MSUF_PlayerCastbarRuntime.lua"),
        (utils, "MSUF_CastbarUtils.lua"),
        (style, "MSUF_CastbarStyle.lua"),
        (core, "MSUF_Castbars_Core.lua"),
        (visuals, "MSUF_CastbarVisuals.lua"),
        (previews, "MSUF_CastbarPreviews.lua"),
        (focus_kick, "MSUF_FocusKickIcon.lua"),
        (manager, "MSUF_Castbars.lua"),
    ]:
        long_lines = [f"{filename}:{i}: {len(line)}" for i, line in enumerate(text.splitlines(), 1) if len(line) > 180]
        if long_lines:
            raise CheckError("overlong castbar refactor lines:\n" + "\n".join(long_lines[:20]))

    for needle in [
        "local function ScheduleStopConfirmation",
        "local function HandleDriverEvent",
        "local function CreateCastBar",
        'ExportPublic("MSUF_CreateCastBar"',
    ]:
        require(driver, needle, "Castbar driver readable contract")

    for needle in [
        "local function BuildEmpowerTimeline",
        "local function LayoutEmpowerStageSegments",
        "local function PlayerCastbarEmpowerStart",
        'ExportPublic("MSUF_PlayerCastbar_EmpowerStart"',
    ]:
        require(empower, needle, "Castbar empower readable contract")

    for needle in [
        "local function ApplyActiveCast",
        "local function UnhaltedUpdate",
        "local function PlayerCastbarOnEvent",
        'ExportPublic("MSUF_PlayerCastbar_OnEvent"',
    ]:
        require(player, needle, "Player castbar runtime readable contract")

    for needle in [
        "local function ApplyNonInterruptibleTint",
        "local function ApplyCastbarGlowFade",
        "local function ShortenCastbarSpellName",
        'ExportPublic("MSUF_Castbar_ApplyNonInterruptibleTint"',
    ]:
        require(utils, needle, "Castbar utils readable contract")

    for needle in [
        "local function GetGlobalFontSettings",
        "local function ResolveStatusbarTextureKey",
        "local function RefreshCastbarStyleCache",
        "local function UpdateCastbarVisuals",
        'ExportPublic("MSUF_UpdateCastbarVisuals"',
        'ExportPublic("MSUF_GetCastbarTexture"',
    ]:
        require(core, needle, "Castbar core readable contract")

    for needle in [
        "local function CreatePreview",
        "local function UpdatePlayerCastbarPreview",
        "local function SetBossCastbarTestMode",
        'ExportPublic("MSUF_UpdatePlayerCastbarPreview"',
        'ExportPublic("MSUF_HideAllCastbarPreviews"',
    ]:
        require(previews, needle, "Castbar previews readable contract")

    for needle in [
        "local function EnsureIconFrame",
        "local function ApplyCastState",
        "local function SetPreviewEnabled",
        'ExportPublic("MSUF_FocusKick_ApplyCastState"',
        'ExportPublic("MSUF_FocusKick_SetPreviewEnabled"',
    ]:
        require(focus_kick, needle, "Focus kick icon readable contract")

    for needle in [
        "local function CreatePlayerCastbarFrame",
        "RegisterCastbar = function",
        "UpdateCastbarFrame = function",
        'ExportPublic("MSUF_RegisterCastbar"',
        'ExportPublic("MSUF_UpdateCastbarFrame"',
    ]:
        require(manager, needle, "Castbar manager readable contract")

    castbar_refresh_sources = "\n".join([core, visuals, manager, font_runtime])
    for export_name in [
        "MSUF_UpdateCastbarVisuals",
        "MSUF_UpdateCastbarVisuals_Immediate",
        "MSUF_UpdateCastbarTextures",
        "MSUF_UpdateCastbarTextures_Immediate",
    ]:
        require_count(
            castbar_refresh_sources,
            f'ExportPublic("{export_name}",',
            1,
            f"single castbar refresh owner for {export_name}",
        )
    require(core, 'ExportPublic("MSUF_ApplyAllCastbarsAndSync"', "bulk castbar apply owner")
    require_count(
        "\n".join([core, style]),
        'ExportPublic("MSUF_UpdateCastbarFillDirection",',
        1,
        "single castbar fill-direction owner",
    )
    require(style, 'ExportPublic("MSUF_UpdateCastbarFillDirection",', "castbar fill-direction owner")
    require_count(
        "\n".join([core, utils]),
        'ExportPublic("MSUF_GetCastbarReverseFillForFrame",',
        1,
        "single castbar reverse-fill owner",
    )
    require(utils, 'ExportPublic("MSUF_GetCastbarReverseFillForFrame",', "castbar reverse-fill owner")


def check_group_refresh_contracts() -> None:
    runtime = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Group" / "MSUF_UF_Group_Runtime.lua")
    em2 = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Group" / "MSUF_UF_Group_EM2.lua")
    targeted = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Group" / "MSUF_UF_Group_TargetedSpells.lua")

    require(runtime, "local dirtyApplyMaskCache = {}", "group dirty-mask cache")
    require(runtime, "local function ApplyRefreshFrame", "stable group refresh callback")
    require(runtime, "function GF.RegisterRuntimeObserver", "group runtime observer API")
    require(runtime, "local function RefreshVisualsNow", "single internal group visual owner")
    require_count(runtime, "function GF.RefreshVisuals(", 1, "single public group visual owner")
    require_count(runtime, "function GF.RebuildAll(", 1, "single public group rebuild owner")
    for source, label in [(em2, "group Edit Mode"), (targeted, "targeted spells")]:
        if "GF.RefreshVisuals = function" in source or "GF.RebuildAll = function" in source:
            raise CheckError(f"{label} must observe, not replace, group runtime functions")
        require(source, "RegisterRuntimeObserver", f"{label} observer registration")


def check_powerbar_contracts() -> None:
    power = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Elements" / "MSUF_UF_Elements_Power.lua")
    metadata = read(ADDON_ROOT / "UnitFrames" / "Engine" / "MSUF_UF_Metadata.lua")
    textures = read(ADDON_ROOT / "Runtime" / "MSUF_TextureRuntime.lua")
    backgrounds = read(ADDON_ROOT / "Runtime" / "MSUF_BarBackgroundRuntime.lua")

    for needle in [
        "bar:SetValue(value, interp)",
        "bar.MSUFPowerBorderHost",
        "ApplyPowerBorder(bar, power)",
        "frame._msufPowerBarDetached = power.detached == true and true or nil",
        "return POWER_EVENTS_FAST",
        "PowerEventMatchesToken(bar, event, eventPowerToken)",
    ]:
        require(power, needle, "Powerbar native runtime contract")
    for reason in ["MSUF2_POWER_DETACHED_SHAPE", "MSUF2_POWER_DETACHED_ORB_SIZE"]:
        require(metadata, reason, "Powerbar targeted refresh reason")
    require(textures, "_msufPowerShapeActive == true", "Power shape foreground ownership")
    require(backgrounds, "local shapedPower =", "Power shape background ownership")
    require(backgrounds, "_MSUF_ApplyBgColor(frame, frame.powerBarBG", "Power shape tint-only refresh")


def check_classpower_smoothing_contracts() -> None:
    controller = read(ADDON_ROOT / "ClassPower" / "MSUF_CP_Controller.lua")
    modes = read(ADDON_ROOT / "ClassPower" / "MSUF_CP_Modes.lua")
    alt_mana = read(ADDON_ROOT / "ClassPower" / "MSUF_CP_AltMana.lua")
    defaults = read(ADDON_ROOT / "State" / "MSUF_Defaults.lua")
    page = read(ADDON_ROOT / "Shell" / "Menu2" / "Pages" / "MSUF_Menu2_AdvancedClassPower.lua")
    global_page = read(ADDON_ROOT / "Shell" / "Menu2" / "Pages" / "MSUF_Menu2_Global.lua")
    bars_page = read(ADDON_ROOT / "Shell" / "Menu2" / "Pages" / "MSUF_Menu2_GlobalBars.lua")

    for needle in [
        "visual.smoothInterp = _cpDB.classSmooth and SMOOTH_INTERP or nil",
        'CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", wantPower and not wantFrequentPower, "player")',
        'CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", wantFrequentPower, "player")',
    ]:
        require(controller, needle, "ClassPower native smoothing/event contract")
    require(modes, "bar:SetValue(value, smoothInterp)", "ClassPower C-side interpolation")
    require(modes, "CP_SetPowerValue(bar, rawCur, smoothInterp)", "ClassPower secret-value C-side path")
    require(alt_mana, "local SMOOTH_INTERP =", "Alternative Mana cached interpolation enum")
    require(alt_mana, "if maxSecret then AM._maxValue = nil", "Alternative Mana secret max cache guard")
    require(alt_mana, "if curSecret then AM._currentValue = nil", "Alternative Mana secret value cache guard")
    for key in ["classPowerSmoothFill", "altManaSmoothFill"]:
        require(defaults, key, f"ClassPower default {key}")
        require(page, key, f"ClassPower menu control {key}")
    require(page, '"powerSmoothFill"', "Class Resources managed Player power smoothing control")
    require(page, 'local dpbSmooth = SwitchAt(', "Visible managed Player power smoothing switch")
    require(page, "powerSmoothFill = true", "ClassPower one-click Player smoothing")
    require(page, "realtimePowerText = true", "ClassPower one-click frequent Player power updates")
    require(global_page, 'M.RequestUnitApply("player", reason, { preview = true, power = true })',
            "Shared smooth power live Player apply")
    require(bars_page, 'M.RequestUnitApply("player", "MSUF2_BARS_REALTIME_POWER", {',
            "Realtime power text live Player apply")


def check_portrait_refresh_contracts() -> None:
    portrait = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Elements" / "MSUF_UF_Elements_Portrait.lua")

    require(
        portrait,
        "UNIT_ENTERED_VEHICLE = true,\n  UNIT_EXITED_VEHICLE = true,\n  MSUF_UNIT_IDENTITY_VISUAL = true",
        "Portrait vehicle events must use the forced-refresh path",
    )
    require(
        portrait,
        "if forceRefresh == true or UnitPortraitKeyChanged(texture, unit, frame, p) then",
        "Portrait forced-refresh cache bypass",
    )
    require_count(
        portrait,
        "ApplyUnitPortrait(texture, unit, frame, p, force)",
        2,
        "Portrait force must reach both queued and direct update paths",
    )


def main() -> int:
    lua_files = all_lua_files()
    check_luac(lua_files)
    check_locale_addon_contracts()
    check_load_reachability(lua_files)
    check_kernel_castbar_contracts()
    check_group_refresh_contracts()
    check_powerbar_contracts()
    check_classpower_smoothing_contracts()
    check_portrait_refresh_contracts()
    print(f"MSUF static checks: ok ({len(lua_files)} Lua files)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as exc:
        print(f"MSUF static checks: failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
