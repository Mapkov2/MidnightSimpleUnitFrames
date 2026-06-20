#!/usr/bin/env python3
"""Minimal static checks for MidnightSimpleUnitFrames.

This intentionally stays small: Lua syntax, load-manifest reachability, and the
kernel/castbar refactor contracts that protect the shared scheduler/event bus
and de-minified castbar files.
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
SKIP_DIRS = {"scripts", "docs"}


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
    base = ADDON_ROOT if owner == TOC else owner.parent
    return (base / value).resolve()


def parse_load_refs() -> tuple[set[str], list[str]]:
    if not TOC.exists():
        raise CheckError(f"missing TOC: {TOC}")

    loaded_lua: set[str] = set()
    missing: list[str] = []
    xml_queue: list[Path] = []
    seen_xml: set[Path] = set()

    for line_no, line in enumerate(read(TOC).splitlines(), 1):
        item = line.strip()
        if not item or item.startswith("#") or item.startswith("##"):
            continue
        if not re.search(r"\.(lua|xml)$", item, re.IGNORECASE):
            continue
        path = resolve_ref(TOC, item)
        if not path.exists():
            missing.append(f"MidnightSimpleUnitFrames.toc:{line_no}: {normalize_ref(item)}")
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
    unreachable = sorted(production_lua - loaded_lua)
    if unreachable:
        raise CheckError("Lua files not reachable from TOC/XML:\n" + "\n".join(unreachable[:30]))


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise CheckError(f"{label}: missing `{needle}`")


def check_kernel_castbar_contracts() -> None:
    util = read(ADDON_ROOT / "Kernel" / "MSUF_Util.lua")
    scheduler = read(ADDON_ROOT / "Kernel" / "MSUF_Scheduler.lua")
    event_bus = read(ADDON_ROOT / "Kernel" / "MSUF_EventBus.lua")
    driver = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarDriver.lua")
    empower = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarEmpower.lua")
    player = read(ADDON_ROOT / "Castbars" / "MSUF_PlayerCastbarRuntime.lua")
    utils = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarUtils.lua")
    core = read(ADDON_ROOT / "Castbars" / "MSUF_Castbars_Core.lua")
    previews = read(ADDON_ROOT / "Castbars" / "MSUF_CastbarPreviews.lua")
    focus_kick = read(ADDON_ROOT / "Castbars" / "MSUF_FocusKickIcon.lua")
    manager = read(ADDON_ROOT / "Castbars" / "MSUF_Castbars.lua")

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
        (core, "MSUF_Castbars_Core.lua"),
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


def main() -> int:
    lua_files = all_lua_files()
    check_luac(lua_files)
    check_load_reachability(lua_files)
    check_kernel_castbar_contracts()
    print(f"MSUF static checks: ok ({len(lua_files)} Lua files)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as exc:
        print(f"MSUF static checks: failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
