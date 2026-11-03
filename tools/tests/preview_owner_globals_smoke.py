"""Reject accidental global fallbacks in the composed preview owners (Lua 5.1 bytecode)."""
import re
import subprocess
import sys
from pathlib import Path

root, compiler = Path(sys.argv[1]), sys.argv[2]
base = root / "MidnightSimpleUnitFrames_Options/Shell/Menu2"
standard = set("assert ipairs math next pairs select string tonumber tostring type unpack".split())
owners = {
    "Preview/MSUF_Menu2_GroupPreview_Model.lua": {'GetSpellInfo', 'C_Spell', 'UnitLevel', 'wipe'},
    "Preview/MSUF_Menu2_GroupPreview_Chrome.lua": {'InCombatLockdown', 'CreateFrame'},
    "Preview/MSUF_Menu2_GroupPreview_Selection.lua": {'GetTime'},
    "Preview/MSUF_Menu2_GroupPreview_Layers.lua": {'IsShiftKeyDown', 'CreateFrame', 'GameTooltip'},
    "Preview/MSUF_Menu2_GroupPreview_View.lua": {'CreateFrame'},
    "Preview/MSUF_Menu2_GroupPreview_Native.lua": {'CreateFrame', 'C_Timer'},
    "Preview/MSUF_Menu2_GroupPreview_HandleStorage.lua": {'InCombatLockdown'},
    "Preview/MSUF_Menu2_GroupPreview_HandleDrag.lua": {'IsControlKeyDown', 'GetCursorPosition', 'UIParent', 'IsMouseButtonDown'},
    "Preview/MSUF_Menu2_GroupPreview_HandleView.lua": {'CreateFrame', 'UIParent', 'GameTooltip', 'GetCursorPosition'},

    "MSUF_Menu2_PreviewContracts.lua": set(),
    "Preview/MSUF_Menu2_UnitPreview_Layout.lua": set(),
    "Preview/MSUF_Menu2_UnitPreview_Presentation.lua": set(),
    "Preview/MSUF_Menu2_UnitPreview_Selection.lua": {"GetCurrentKeyBoardFocus", "MSUF_UFPreview_ActiveNudgeBox"},
    "Preview/MSUF_Menu2_UnitPreview_Input.lua": {
        "CreateFrame", "GameTooltip", "GetCursorPosition", "IsControlKeyDown", "IsMouseButtonDown", "IsShiftKeyDown", "UIParent"},
    "Preview/MSUF_Menu2_UnitPreview_View.lua": {"CreateFrame", "GameTooltip", "STANDARD_TEXT_FONT"},
    "Preview/MSUF_Menu2_UnitPreview_Render.lua": {"SetPortraitTexture", "issecretvalue"},
    "Preview/MSUF_Menu2_GroupPreview_Plan.lua": set(),
    "Preview/MSUF_Menu2_GroupPreview_Presentation.lua": set(),
    "Preview/MSUF_Menu2_GroupPreview_Render.lua": {
        "CreateFrame", "GetCurrentKeyBoardFocus", "InCombatLockdown", "IsShiftKeyDown", "MSUF_InCombat", "issecretvalue", "wipe"},
}
for name, native in owners.items():
    process = subprocess.run([compiler, "-l", "-p", str(base / name)], capture_output=True, text=True)
    if process.returncode:
        raise SystemExit(process.stderr)
    reads = set(re.findall(r"\bGETGLOBAL\b[^\n]*; ([^\r\n]+)", process.stdout))
    writes = set(re.findall(r"\bSETGLOBAL\b[^\n]*; ([^\r\n]+)", process.stdout))
    unexpected = reads - standard - native
    if unexpected or writes:
        raise SystemExit(name + ": unintended global reads " + repr(sorted(unexpected)) + "; writes " + repr(sorted(writes)))
print("PASS preview owner bindings: " + str(len(owners)) + " bytecode trees; no accidental global helpers or global writes")
