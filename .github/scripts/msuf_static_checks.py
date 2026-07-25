#!/usr/bin/env python3
"""Minimal static checks for MidnightSimpleUnitFrames.

This intentionally stays small: Lua syntax, load-manifest reachability, and the
runtime ownership contracts that protect the shared scheduler/event bus,
castbar refresh pipeline, and group-frame refresh pipeline.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ADDON_ROOT = REPO_ROOT / "MidnightSimpleUnitFrames"
TOC = ADDON_ROOT / "MidnightSimpleUnitFrames.toc"
LOCALE_TOC = REPO_ROOT / "MidnightSimpleUnitFrames_Locales" / "MidnightSimpleUnitFrames_Locales.toc"
ASSISTANT_TOC = REPO_ROOT / "MidnightSimpleUnitFrames_Assistant" / "MidnightSimpleUnitFrames_Assistant.toc"
ASSISTANT_ROOT = ASSISTANT_TOC.parent
ASSISTANT_MANIFEST = ASSISTANT_ROOT / "MSUF_AssistantRuntime.xml"
MENU_LOCALE_AUDIT = REPO_ROOT / ".github" / "scripts" / "tests" / "full_menu_locale_coverage_smoke.py"
ASSISTANT_SCRIPT_COUNT = 328
ASSISTANT_ORDER_SHA256 = "6D93B5BB79D3EDAFDF14D2838216E6ACEE814645ED37AFDEFB28863A9F232A39"
LUA_MAIN_CHUNK_LOCAL_BUDGETS = {
    # WoW Lua rejects a function at 200 locals. Keep enough structural reserve
    # that ordinary Auras3 work cannot drift back to the compiler cliff.
    "Auras3/MSUF_Auras3_UnitFrames.lua": 165,
}
SUPPORTED_LOCALES = {
    "enUS", "enGB", "deDE", "esES", "esMX", "frFR",
    "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW",
}
ENGLISH_LOCALES = {"enUS", "enGB"}
NON_ENGLISH_LOCALES = SUPPORTED_LOCALES - ENGLISH_LOCALES
SKIP_DIRS = {
    "scripts", "docs", "tools", "graphify-out", "__pycache__",
    ".codex-remote-attachments", ".codex_assistant_goal", "_local_workflows",
}
INTENTIONALLY_UNLOADED_LUA = {
    # Developer-only diagnostic tools. They are kept in source but excluded
    # from release loading so normal users pay no startup/runtime cost.
    "Features/Diagnostics/MSUF_Feature_DebugPosition.lua",
    "UnitFrames/Engine/MSUF_UF_PreviewDiagnostics.lua",
    # Superseded by the Borders/RoundedFrames highlight implementations.
    "UnitFrames/Engine/Elements/MSUF_UF_Highlight.lua",
}


class CheckError(RuntimeError):
    pass


def rel(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(ADDON_ROOT.resolve()).as_posix()
    except ValueError:
        try:
            companion_rel = resolved.relative_to(ASSISTANT_ROOT.resolve()).as_posix()
        except ValueError as exc:
            raise CheckError(f"runtime source is outside an addon root: {path}") from exc
        return f"../MidnightSimpleUnitFrames_Assistant/{companion_rel}"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def should_skip(path: Path) -> bool:
    try:
        relative = path.resolve().relative_to(ADDON_ROOT.resolve())
    except ValueError:
        try:
            relative = path.resolve().relative_to(ASSISTANT_ROOT.resolve())
        except ValueError:
            return True
        return any(part in SKIP_DIRS for part in relative.parts)
    if relative.parts[:3] == ("Shell", "Menu2", "Assistant"):
        return True  # forbidden core-owned V1 is reported by the ownership contract
    if relative.as_posix() in {
        "Shell/Menu2/MSUF_Menu2_AssistantDialogLocale.lua",
        "Shell/Menu2/MSUF_Menu2_AssistantDialogLocale_Data.lua",
    }:
        return True
    return any(part in SKIP_DIRS for part in relative.parts)


def all_lua_files() -> list[Path]:
    roots = (ADDON_ROOT, ASSISTANT_ROOT)
    return sorted(
        path
        for root in roots
        for path in root.rglob("*.lua")
        if not should_skip(path)
    )


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

    manifests = [TOC]
    if ASSISTANT_TOC.exists():
        manifests.append(ASSISTANT_TOC)
    for toc in manifests:
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


def check_locale_contracts() -> None:
    if LOCALE_TOC.exists():
        raise CheckError(f"legacy locale companion TOC must be removed: {LOCALE_TOC}")
    legacy_locale_addons = sorted(REPO_ROOT.glob("MidnightSimpleUnitFrames_Locale_*"))
    if legacy_locale_addons:
        names = ", ".join(path.name for path in legacy_locale_addons)
        raise CheckError(f"legacy per-locale addons must be removed: {names}")

    main_toc = read(TOC)
    locale_core = read(ADDON_ROOT / "Locales" / "MSUF_Localization.lua")
    if "LoadAddOn" in locale_core or "LocaleAddonName = localeAddon" in locale_core:
        raise CheckError("locale core must not load a retired locale companion addon")

    for locale in sorted(SUPPORTED_LOCALES):
        locale_ref = f"Locales\\{locale}.lua"
        locale_source = read(ADDON_ROOT / "Locales" / f"{locale}.lua")
        require(
            locale_source,
            f'if not MSUF or MSUF.LOCALE ~= "{locale}" then return end',
            f"{locale} active-pack guard",
        )
        require(main_toc, locale_ref, f"main TOC {locale} source")


def check_full_menu_locale_coverage() -> None:
    result = subprocess.run(
        [sys.executable, str(MENU_LOCALE_AUDIT), str(REPO_ROOT)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        raise CheckError("full Menu2 locale coverage failed" + (f":\n{detail}" if detail else ""))


def toc_field(text: str, name: str) -> str:
    match = re.search(rf"(?im)^##\s*{re.escape(name)}:\s*([^\r\n]+)", text)
    return match.group(1).strip() if match else ""


def check_assistant_runtime_contracts() -> None:
    if not ASSISTANT_TOC.exists():
        raise CheckError(f"missing load-on-demand Assistant V1 companion: {ASSISTANT_TOC}")
    if not ASSISTANT_MANIFEST.exists():
        raise CheckError(f"missing Assistant V1 runtime manifest: {ASSISTANT_MANIFEST}")

    menu2 = ADDON_ROOT / "Shell" / "Menu2"
    forbidden_core = (
        menu2 / "Assistant",
        menu2 / "MSUF_Menu2_AssistantRuntime.xml",
        menu2 / "MSUF_Menu2_AssistantDialogLocale.lua",
        menu2 / "MSUF_Menu2_AssistantDialogLocale_Data.lua",
    )
    present_core = [path for path in forbidden_core if path.exists()]
    if present_core:
        raise CheckError("Assistant V1 must be companion-owned; core artifacts found: " + ", ".join(map(str, present_core)))

    v2_artifacts = sorted(
        path
        for root in (ADDON_ROOT, ASSISTANT_ROOT)
        for path in root.rglob("*")
        if "assistantv2" in path.name.lower()
    )
    if v2_artifacts:
        raise CheckError("Assistant V2 runtime artifacts are forbidden: " + ", ".join(map(str, v2_artifacts)))

    main_toc = read(TOC)
    if "MSUF_Menu2_AssistantRuntime.xml" in main_toc or "AssistantV2" in main_toc:
        raise CheckError("main TOC must not eagerly load an Assistant runtime")
    companion = read(ASSISTANT_TOC)
    require(companion, "## LoadOnDemand: 1", "Assistant V1 LoD metadata")
    require(companion, "## Dependencies: MidnightSimpleUnitFrames", "Assistant V1 core dependency")
    if "..\\" in companion or "../" in companion:
        raise CheckError("Assistant companion TOC must not load runtime files from the core addon")
    toc_payload = [
        line.strip()
        for line in companion.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    if toc_payload != [ASSISTANT_MANIFEST.name]:
        raise CheckError(f"Assistant TOC must load exactly {ASSISTANT_MANIFEST.name}, got: {toc_payload}")

    scripts = [normalize_ref(value) for value in re.findall(r'<Script\s+file="([^"]+)"', read(ASSISTANT_MANIFEST))]
    if len(scripts) != ASSISTANT_SCRIPT_COUNT or len(set(scripts)) != len(scripts):
        raise CheckError(
            f"Assistant V1 manifest must contain exactly {ASSISTANT_SCRIPT_COUNT} unique scripts, got {len(scripts)}"
        )
    order_hash = hashlib.sha256("\n".join(scripts).encode("utf-8")).hexdigest().upper()
    if order_hash != ASSISTANT_ORDER_SHA256:
        raise CheckError(
            "Assistant V1 manifest inventory/load-order hash mismatch: "
            f"expected {ASSISTANT_ORDER_SHA256}, got {order_hash}"
        )
    assistant_root_resolved = ASSISTANT_ROOT.resolve()
    for script in scripts:
        parts = Path(script).parts
        if not script.lower().endswith(".lua") or ".." in parts or Path(script).is_absolute():
            raise CheckError(f"unsafe or non-Lua Assistant manifest reference: {script}")
        script_path = (ASSISTANT_ROOT / script).resolve()
        try:
            script_path.relative_to(assistant_root_resolved)
        except ValueError as exc:
            raise CheckError(f"Assistant manifest reference escapes companion: {script}") from exc
        if not script_path.is_file():
            raise CheckError(f"Assistant manifest references missing runtime file: {script}")

    actual_inventory = sorted(
        path.relative_to(ASSISTANT_ROOT).as_posix()
        for path in ASSISTANT_ROOT.rglob("*")
        if path.is_file()
    )
    expected_inventory = sorted([ASSISTANT_TOC.name, ASSISTANT_MANIFEST.name, *scripts])
    if actual_inventory != expected_inventory:
        unexpected = sorted(set(actual_inventory) - set(expected_inventory))
        missing = sorted(set(expected_inventory) - set(actual_inventory))
        raise CheckError(f"Assistant V1 companion inventory mismatch; unexpected={unexpected}, missing={missing}")

    bridge = read(menu2 / "MSUF_AssistantBridge.lua")
    bindings = read(menu2 / "MSUF_Menu2_Bindings.lua")
    catalog = read(menu2 / "MSUF_Menu2_ControlCatalog.lua")
    dashboard = read(menu2 / "MSUF_Menu2_Dashboard.lua")
    nav = read(menu2 / "MSUF_Menu2_NavRail.lua")
    widgets = read(menu2 / "MSUF_Menu2_Widgets.lua")
    window = read(menu2 / "MSUF_Menu2_Window.lua")
    routing = read(menu2 / "Search" / "MSUF_Menu2_Search_Routing.lua")
    search_index = read(menu2 / "Search" / "MSUF_Menu2_Search_IndexQuery.lua")
    group = read(menu2 / "Pages" / "MSUF_Menu2_Group.lua")
    ensure_start = bridge.find("function A.EnsureRuntimeLoaded(reason)")
    combat_gate = bridge.find('if InCombat() then return false, "combat" end', ensure_start)
    menu_gate = bridge.find('if not MenuShown() then return false, "menu_closed" end', ensure_start)
    loaded_fast_path = bridge.find("if A.IsRuntimeLoaded() then", ensure_start)
    if not (ensure_start >= 0 and ensure_start < combat_gate < loaded_fast_path
            and ensure_start < menu_gate < loaded_fast_path):
        raise CheckError("Assistant LoD bridge must gate combat and closed-menu calls before its loaded fast path")
    if any(marker in bridge for marker in ("RegisterEvent", "OnUpdate", "NewTicker")):
        raise CheckError("Assistant zero-idle bridge must not own events, OnUpdate, or tickers")
    require(bridge, "function A.ShowRuntimeDashboardCard()", "LoD dashboard-card promotion")

    require(catalog, "M.REQUIRED_SHELL_CONTRACT", "fail-closed raw-shell denominator")
    require(catalog, "minimumControls = 6", "required raw-shell control minimum")
    require(catalog, "minimumDispositions = 14", "required interaction disposition minimum")
    require(catalog, "function M.RegisterVirtualRuntimeControl", "frame-free conditional control contracts")
    require(catalog, "function M.MarkRuntimeControlComponent", "logical composite-control ownership")
    require(catalog, "RuntimeCapabilityIssue(record)", "runtime getter/provider capability validation")
    require(catalog, "ASSISTANT_REVIEW_DISPOSITIONS", "explicit Assistant disposition allowlist")
    require(catalog, "missing explicit settingKey/actionKey or reviewed Assistant disposition",
            "fail-closed persisted-control Assistant contract")
    require(catalog, "report.assistantContractComplete", "Assistant contract completeness signal")
    require(catalog, "report.assistantRegistryCrosswalkComplete", "Assistant registry crosswalk signal")
    require(catalog, "report.persistedControls", "persisted-control audit denominator")
    require(bindings, "Keep provider failures observable", "dynamic dropdown provider fail-closed behavior")
    require(bindings, "assistantDisposition = opts.assistantDisposition", "binding Assistant disposition propagation")
    require(search_index, "assistantDisposition = meta.assistantDisposition", "search Assistant disposition propagation")
    require(bindings, "SnapshotProfileRouting()", "profile/spec-routing undo coverage")

    for marker in (
        '"window.close"', '"window.minimize"', '"window.maximize"', '"window.restore"',
    ):
        require(window, marker, "window shell action registration")
    require(nav, '"search.clear"', "search-clear shell action registration")
    require(nav, 'controlId = "menu2.menu-chrome.search-intro-dismiss"',
            "frame-free search-intro action registration")
    for marker in (
        "M.MarkRuntimeControlComponent(labelHit, btn)",
        "M.MarkRuntimeControlComponent(edit, slider)",
        "M.MarkRuntimeControlComponent(btn, slider)",
        "M.MarkRuntimeControlComponent(btn, holder)",
        "M.MarkRuntimeControlComponent(btn, bar)",
    ):
        require(widgets, marker, "composite widget interaction ownership")

    require(dashboard, "RegisterDashboardDirectControls()", "frame-free Dashboard option contracts")
    require(routing, "SearchAuraStyleContainer(normalized)", "Aura Style selector routing")
    require(routing, 'SearchRouteSetState(route, "auraStyleContainer", container)',
            "Aura Style container route application")
    require(group, '{ value = "", text = "No supported specs", disabled = true }',
            "non-selectable empty spec placeholder")
    require(group, '{ value = "", text = "No spells for current spec", disabled = true }',
            "non-selectable empty spell placeholder")


def check_luac(lua_files: list[Path]) -> None:
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if not luac:
        raise CheckError("luac is not available")

    def compile_source(path: Path, *options: str) -> subprocess.CompletedProcess[bytes]:
        source = path.read_bytes()
        if source.startswith(b"\xef\xbb\xbf"):
            source = source[3:]
        return subprocess.run([luac, *options, "-"], input=source, capture_output=True)

    def compiler_output(proc: subprocess.CompletedProcess[bytes]) -> str:
        return (proc.stderr or proc.stdout).decode("utf-8", errors="replace").strip()

    failures: list[str] = []
    for path in lua_files:
        proc = compile_source(path, "-p")
        if proc.returncode != 0:
            failures.append(f"{rel(path)}: {compiler_output(proc)}")
    if failures:
        raise CheckError("luac failures:\n" + "\n".join(failures[:30]))

    for relative_path, budget in LUA_MAIN_CHUNK_LOCAL_BUDGETS.items():
        path = ADDON_ROOT / relative_path
        proc = compile_source(path, "-l", "-l")
        if proc.returncode != 0:
            raise CheckError(f"could not inspect Lua local budget for {relative_path}: "
                             f"{compiler_output(proc)}")
        listing = (proc.stdout or proc.stderr).decode("utf-8", errors="replace")
        match = re.search(r"(?m)^\s*locals\s*\((\d+)\)", listing)
        if not match:
            raise CheckError(f"could not parse main-chunk locals for {relative_path}")
        local_count = int(match.group(1))
        if local_count > budget:
            raise CheckError(f"{relative_path} main chunk uses {local_count} locals; budget is {budget}")


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
    require(event_bus, "local fn = h and h.fn", "EventBus cached handler")
    require(event_bus, "SafeCall(fn, event, ...)", "EventBus protected handler")

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

    require(runtime, "local function SyncCombatState", "group combat-state owner")
    require(
        runtime,
        '"PLAYER_REGEN_DISABLED",',
        "group combat-start event ownership",
    )
    require(
        runtime,
        '"PLAYER_REGEN_ENABLED",',
        "group combat-end event ownership",
    )
    for event, state in [
        ("PLAYER_REGEN_DISABLED", "true"),
        ("PLAYER_REGEN_ENABLED", "false"),
    ]:
        if not re.search(
            rf'(?:if|elseif)\s+event\s*==\s*["\']{event}["\']\s+then\s+'
            rf'SyncCombatState\s*\(\s*{state}\s*\)',
            runtime,
        ):
            raise CheckError(f"group combat-state owner must sync {state} on {event}")
    require(runtime, "local function SetRuntimeEventsEnabled", "dynamic group runtime event lifecycle")
    require(runtime, "if not AnyGroupFrameEnabled()", "disabled group runtime fast shutdown")
    if not re.search(
        r'(?:if|elseif)\s+event\s*==\s*["\']PLAYER_LOGIN["\']\s+or\s+'
        r'event\s*==\s*["\']PLAYER_ENTERING_WORLD["\']\s+then\s+'
        r'SyncCombatState\s*\(\s*\)',
        runtime,
    ):
        raise CheckError("group combat-state owner must resync from the live API on login/world entry")
    require(runtime, "local dirtyApplyMaskCache = {}", "group dirty-mask cache")
    require(runtime, "local function ApplyRefreshFrame", "stable group refresh callback")
    require(runtime, "function GF.RegisterRuntimeObserver", "group runtime observer API")
    require(runtime, "local function RefreshVisualsNow", "single internal group visual owner")
    require_count(runtime, "function GF.RefreshVisuals(", 1, "single public group visual owner")
    require_count(runtime, "function GF.RebuildAll(", 1, "single public group rebuild owner")
    if "GF.RefreshVisuals = function" in em2 or "GF.RebuildAll = function" in em2:
        raise CheckError("group Edit Mode must observe, not replace, group runtime functions")
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
        "and bar._msufPowerToken ~= eventPowerToken then return end",
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
    require(modes, "CP_SetPowerValue(bar, rawCur, smoothInterp)", "ClassPower secret-value C-side path keeps interpolation")
    require(alt_mana, "local SMOOTH_INTERP =", "Alternative Mana cached interpolation enum")
    require(alt_mana, "if maxSecret then AM._maxValue = nil", "Alternative Mana secret max cache guard")
    require(alt_mana, "if curSecret then AM._currentValue = nil", "Alternative Mana secret value cache guard")
    for key in ["classPowerSmoothFill", "altManaSmoothFill"]:
        require(defaults, key, f"ClassPower default {key}")
        require(page, key, f"ClassPower menu control {key}")
    require(page, '"powerSmoothFill"', "Class Resources managed Player power smoothing control")
    require(
        page,
        'local smooth = SwitchAt(self.ctx, layout, "Smooth fill"',
        "Visible managed Player power smoothing switch",
    )
    require(
        page,
        'Player, "powerSmoothFill", false, ApplyDetachedPlayerPowerSmoothing, '
        'Meta("detached_power.layout.smooth_fill")',
        "Managed Player power smoothing binding and catalog identity",
    )
    require(page, 'self:Add("detachedPlayer", smooth)',
            "Managed Player power smoothing enablement group")
    require(page, "powerSmoothFill = true", "ClassPower one-click Player smoothing")
    require(page, "realtimePowerText = true", "ClassPower one-click frequent Player power updates")
    require(global_page, 'M.RequestUnitApply("player", reason, { preview = true, power = true })',
            "Shared smooth power live Player apply")
    require(bars_page, 'M.RequestUnitApply("player", "MSUF2_BARS_REALTIME_POWER", {',
            "Realtime power text live Player apply")


def check_portrait_refresh_contracts() -> None:
    portrait = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Elements" / "MSUF_UF_Elements_Portrait.lua")
    visuals = read(ADDON_ROOT / "UnitFrames" / "Engine" / "Elements" / "MSUF_UF_Visuals_Common.lua")

    # The fallback and shared event maps may include additional lifecycle
    # events, but both must retain the vehicle and identity refresh triggers.
    for source, label in [
        (portrait, "Portrait fallback vehicle refresh events"),
        (visuals, "Portrait shared vehicle refresh events"),
    ]:
        for event in ["UNIT_ENTERED_VEHICLE = true", "UNIT_EXITED_VEHICLE = true", "MSUF_UNIT_IDENTITY_VISUAL = true"]:
            require(source, event, label)
    require(
        portrait,
        "if forceRefresh == true or UnitPortraitKeyChanged(texture, unit, frame, p) then",
        "Portrait forced-refresh cache bypass",
    )
    require(
        portrait,
        "ApplyUnitPortrait(texture, frame.MSUFUnitKey, frame, p, force or restorePortrait)",
        "Portrait force must reach the queued update path",
    )
    require(
        portrait,
        "ApplyUnitPortrait(texture, unit, frame, p, force)",
        "Portrait force must reach the direct update path",
    )


def check_edit_mode_mover_contracts() -> None:
    movers = read(ADDON_ROOT / "Shell" / "EditMode" / "MSUF_EditMode_Movers.lua")

    require(
        movers,
        "frame._msufPowerBarDetached == true",
        "Unit mover excludes a detached powerbar by frame ownership",
    )
    require(
        movers,
        "power._msufDetached == true",
        "Unit mover excludes a detached powerbar by applied layout state",
    )
    require(
        movers,
        "if not powerDetached and power and power.IsShown and power:IsShown() then",
        "Unit mover includes only attached visible powerbars in its visual bounds",
    )


def check_unit_preview_lifecycle_contracts() -> None:
    api = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_UnitPreview_API.lua")
    core = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_UnitPreview_Core.lua")
    auras = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_UnitPreview_Auras.lua")
    aura_edit_mode = read(ADDON_ROOT / "Auras3" / "MSUF_Auras3_EditMode.lua")
    sections = read(ADDON_ROOT / "Shell" / "Menu2" / "Pages" / "MSUF_Menu2_UnitSections.lua")
    group_preview = read(ADDON_ROOT / "Shell" / "Menu2" / "Pages" / "MSUF_Menu2_GroupPreview.lua")
    group_native = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_GroupPreview_Native.lua")
    group_render = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_GroupPreview_Render.lua")
    class_power = read(ADDON_ROOT / "Shell" / "Menu2" / "Preview" / "MSUF_Menu2_ClassPowerPreview.lua")
    window_priority = read(ADDON_ROOT / "Shell" / "Menu2" / "MSUF_Menu2_WindowPriority.lua")
    widgets = read(ADDON_ROOT / "Shell" / "Menu2" / "MSUF_Menu2_Widgets.lua")
    dropdowns = read(ADDON_ROOT / "Shell" / "Menu2" / "MSUF_Menu2_Dropdowns.lua")
    theme = read(ADDON_ROOT / "Shell" / "Menu2" / "MSUF_Menu2_Theme.lua")
    window = read(ADDON_ROOT / "Shell" / "Menu2" / "MSUF_Menu2_Window.lua")

    combat_gate = re.search(
        r'function\s+Core\.InCombat\s*\(\s*\)\s*'
        r'.*?local\s+(?P<lockdown>[A-Za-z_]\w*)\s*=\s*_G\.InCombatLockdown\s*'
        r'.*?if\s+type\s*\(\s*(?P=lockdown)\s*\)\s*==\s*["\']function["\']\s+then\s*'
        r'return\s+(?P=lockdown)\s*\(\s*\)\s*==\s*true\s*'
        r'end\s*return\s+_G\.MSUF_InCombat\s*==\s*true\s*end',
        core,
        re.DOTALL,
    )
    if not combat_gate:
        raise CheckError(
            "Unit preview combat gate must prefer live InCombatLockdown and use "
            "MSUF_InCombat only when that API is unavailable"
        )
    require_count(core, "_G.InCombatLockdown", 1, "Unit preview live combat authority")
    require_count(core, "_G.MSUF_InCombat", 1, "Unit preview cached combat fallback")

    if "ApplyCustomEffectPreview" in auras or "_msufCustomAuraPreviewTint" in auras:
        raise CheckError(
            "Generic Unit preview must not synthesize Custom Aura full-frame effects; "
            "those effects require an active aura and have a dedicated scoped preview"
        )
    # Since the runtime-metrics preview rewrite, Custom Aura footprints mirror
    # the live lane: runtime metrics own the bounds when available, and the
    # fallback sizes from full configured capacity (kept in sync with the
    # aura_growth_anchor smoke assertions).
    require(
        auras,
        "local cols, rows = GridShape(count, perRow, vertical)",
        "Custom Aura preview footprint mirrors runtime lane capacity",
    )
    if "PreviewLaneDimensions" in aura_edit_mode:
        raise CheckError(
            "Edit Mode Custom Aura mover must size from runtime metrics/capacity, "
            "not a sample-icon footprint (PreviewLaneDimensions was removed)"
        )
    require(
        aura_edit_mode,
        "local laneW = (metrics and metrics.width) or (fallback and fallback.width) or cfg.size",
        "Edit Mode Custom Aura mover sizes from runtime metrics",
    )

    for forbidden in [
        "if box.IsVisible and not box:IsVisible() then return end",
        "if wrapper and wrapper.IsVisible and not wrapper:IsVisible() then return true end",
        "box:IsShown() and (not box.IsVisible or box:IsVisible())",
    ]:
        if forbidden in api:
            raise CheckError("Unit preview refresh ownership must not depend on frame-lagged IsVisible state")
    require(api, 'if type(queuedRefresh) == "function" and box:IsShown() then',
            "Unit preview logically-owned queued render")
    require(sections, "local function PreviewHostShown()", "Unit preview page owner predicate")
    require(sections, "local function EnsurePreviewAttachment()",
            "Shared unit preview close/reopen ownership attachment")
    require_count(sections, "EnsurePreviewAttachment()", 3,
                  "Shared unit preview attachment definition and both ownership paths")
    require(widgets, "local function BodyOwned()", "Pinned preview logical ownership predicate")
    require(widgets, "if not BodyVisible() then\n            RefreshButton()",
            "Pinned preview transient visibility preservation")
    require_count(
        widgets,
        "if box._msuf2PinnedPreviewRecord ~= record then return end",
        2,
        "Stale pinned-preview callbacks require exact record ownership",
    )
    if "if box._msuf2PinnedPreviewRecord and box._msuf2PinnedPreviewRecord ~= record then return end" in widgets:
        raise CheckError("Released pinned-preview callbacks must not run after record ownership is cleared")
    require(widgets, "function M.SuspendPinnedPreviews(reason)",
            "Window hide suspends cached pinned-preview ownership")
    require(widgets, "record.restore(true)",
            "Pinned-preview ownership boundaries force an idempotent restore")
    require(widgets, 'box:CreateTexture(nil, "BACKGROUND", nil, -8)',
            "Pinned-preview background is owned by the preview render tree")
    if 'CreateFrame("Frame", nil, scrollParent or scroll, "BackdropTemplate")' in widgets:
        raise CheckError("Pinned-preview background must not be an independently levelled overlay frame")
    restore_start = widgets.find("local function Restore(force)")
    restore_cleanup = widgets.find("local scrim = (record and record.scrim) or box._msuf2PinnedPreviewScrim", restore_start)
    restore_early_return = widgets.find("if not force and not wasFloating then", restore_start)
    if not (restore_start >= 0 and restore_start < restore_cleanup < restore_early_return):
        raise CheckError("Pinned-preview restore must hide its background region before any logical-state early return")
    require(widgets, "function M.ResumePinnedPreviews(reason)",
            "Window show resumes cached pinned-preview geometry after ancestor visibility settles")
    require(widgets, "C_Timer.After(0.05, RefreshAfterShow)",
            "Pinned-preview resume has a settled-geometry refresh")
    require(window, 'M.CallIf(M.SuspendPinnedPreviews, "WINDOW_HIDE")',
            "Window hide preserves cached pinned-preview records without reattaching hooks")
    require(window, 'M.CallIf(M.ResumePinnedPreviews, "WINDOW_SHOW")',
            "Window show resumes cached pinned-preview records")
    require(group_preview, "function M.ResumeGFNativePreviews(reason, pageKey)",
            "Cached native Group preview has a symmetric window/page resume owner")
    if "if body and body.IsVisible and not body:IsVisible() then return false end" in group_preview:
        raise CheckError("Native Group preview ownership must not use frame-lagged IsVisible state")
    if "box:IsVisible()" in group_preview or "if self.IsVisible and not self:IsVisible() then return end" in group_native:
        raise CheckError("Native Group preview refresh must not discard work using frame-lagged IsVisible state")
    request_branch = group_preview.find("if box.RequestRefresh then")
    direct_refresh = group_preview.find("box:Refresh()", request_branch)
    if not (request_branch >= 0 and request_branch < direct_refresh):
        raise CheckError("Native Group preview must prefer queued refresh before its direct fallback")
    for boundary in ["WINDOW_SHOW", "SELECT_CACHED", "SELECT_PAGE"]:
        require(window, f'M.CallIf(M.ResumeGFNativePreviews, "{boundary}"',
                f"Native Group preview resumes at {boundary} ownership boundary")
    if "if box.IsVisible and not box:IsVisible() then return end" in class_power:
        raise CheckError("Class Resources preview refresh must not discard work using frame-lagged IsVisible state")
    require(class_power, "function box:_msufCPPreviewHostShown()",
            "Class Resources preview has a logical page/window owner predicate")
    require(class_power, 'RequestClassPowerPreviewRefresh(box, "CLASSPOWER_PREVIEW_SHOW")',
            "Class Resources preview repaints whenever its cached section is shown")
    require(class_power, "function M.ResumeClassPowerPreview(reason, pageKey)",
            "Cached Class Resources preview has an explicit lifecycle resume owner")
    for boundary in ["WINDOW_SHOW", "SELECT_CACHED", "SELECT_PAGE"]:
        require(window, f'M.CallIf(M.ResumeClassPowerPreview, "{boundary}"',
                f"Class Resources preview resumes at {boundary} ownership boundary")
    require(window, 'M.CallIf(M.ResumeClassPowerPreview, "EDIT_MODE_UI", M.activeKey)',
            "Class Resources preview resumes across Edit Mode state boundaries")
    require(group_render, "scene.selectedSpellEffect = scene.selectedSpellCfg and scene.selectedSpellCfg.frame",
            "Selected Group spell effect is owned independently of its transient render handle")
    require(group_render, 'selectedSpellEffectOwner = CreateFrame("Frame", nil, mock)',
            "Selected Group spell effect has a stable mock-owned render owner")
    require(group_render, "ApplySpellEffectPreview(selectedSpellEffectOwner, selectedSpellEffect)",
            "Selected Group spell effect is reconstructed on its stable owner")
    if "if effect then ApplySpellEffectPreview(handle, effect)" in group_render:
        raise CheckError("Full-frame Group spell effects must not be owned by transient icon handles")
    require(group_render, "HideSpellEffectPreview(spellHandle)",
            "Fallback Group spell effect is explicitly released when handle ownership changes")
    require(window_priority, 'local MENU_EDIT_FRAME_STRATA = "FULLSCREEN_DIALOG"',
            "Edit Mode menu priority uses strata instead of a numeric level jump")
    require(window_priority, "local MENU_EDIT_FRAME_LEVEL = MENU_NORMAL_FRAME_LEVEL",
            "Cached menu descendants retain a stable numeric frame-level root")
    require(window_priority, "local MENU_EDIT_POPUP_FRAME_LEVEL = MENU_NORMAL_POPUP_FRAME_LEVEL",
            "Cached popup descendants retain a stable numeric frame-level root")
    require(group_render, "local PREVIEW_LOCAL_BASE_OFFSET = 400",
            "Group preview reserves a bounded local level band for strata emulation")
    require(group_render, "local function SafePreviewFrameLevel(value)",
            "Group preview guards the WoW frame-level API range")
    if group_render.count(":SetFrameLevel(") != 1:
        raise CheckError("Group preview render must route every frame-level write through its bounded API helper")
    require(group_render, "SetPreviewFrameLevel(mock, previewRootLevel + PREVIEW_LOCAL_BASE_OFFSET)",
            "Cached Group preview rebases its mock before every render")
    selected_effect_level = group_render.find("SetPreviewFrameLevel(selectedEffectRoot, baseLevel")
    if selected_effect_level < 0:
        raise CheckError("Selected fallback spell frame effect is not assigned a deterministic level")
    require(group_render, 'ApplyHandleStrata(scene, selectedEffectRoot, "AUTO", liveStrata, hostStrata)',
            "Selected full-frame effect inherits menu host strata without live Edit Mode offsets")
    selected_effect_level_block = group_render[selected_effect_level:selected_effect_level + 240]
    require(selected_effect_level_block,
            "(S.Layers.SPELL_FRAME_EFFECT_BASE_OFFSET or 1) + (11 - priority)",
            "Selected full-frame effect uses the shared bounded health-effect priority band")
    require(theme, "function M.ResetFocusVeil(variant, opts)",
            "Menu modal focus veil has an explicit lifecycle reset")
    require(theme, "StopAlphaMotion(overlay)",
            "Menu focus veil reset cancels unfinished alpha motion")
    require(theme, "overlay:ClearAllPoints()",
            "Menu focus veil reset releases its cached page owner")
    require(dropdowns, 'HideDropdownFocus(not immediate)',
            "Immediate dropdown close synchronously releases its focus veil")
    require(dropdowns, "if T.StopMotion then T.StopMotion(dropdownFrame) end",
            "Immediate dropdown close cancels unfinished dropdown motion")
    require(dropdowns, "if dropdownOwner == self then CloseDropdown({ immediate = true }) end",
            "Hidden dropdown owner synchronously releases UIParent modal state")
    require(window, 'W.CloseDropdown({ immediate = true })',
            "Menu hide synchronously closes UIParent-owned dropdown state")
    require(window, "M.ResetFocusVeil(nil, { force = true })",
            "Menu hide enforces modal focus veil ownership cleanup")


def main() -> int:
    lua_files = all_lua_files()
    check_luac(lua_files)
    check_locale_contracts()
    check_full_menu_locale_coverage()
    check_assistant_runtime_contracts()
    check_load_reachability(lua_files)
    check_kernel_castbar_contracts()
    check_group_refresh_contracts()
    check_powerbar_contracts()
    check_classpower_smoothing_contracts()
    check_portrait_refresh_contracts()
    check_edit_mode_mover_contracts()
    check_unit_preview_lifecycle_contracts()
    print(f"MSUF static checks: ok ({len(lua_files)} Lua files)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as exc:
        print(f"MSUF static checks: failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
