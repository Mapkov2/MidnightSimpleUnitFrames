-- Test the real bridge with a native-panel lifecycle double.
local marker, shown, fail, showCalls, hideCalls = {}, false, nil, 0, 0
local combat = false
local ns = { EditMode = {}, ExportPublic = function(name, value) _G[name] = value end }
ns.Require = function(name) return assert(_G[name]) end
_G.MSUF_EnsureDB = function() end
_G.MSUF_DB = { general = {} }
_G.InCombatLockdown = function() return combat end
_G.EditModeManagerFrame = { IsShown = function() return shown end }
_G.ShowUIPanel = function(frame)
    assert(frame == EditModeManagerFrame)
    showCalls = showCalls + 1
    if fail == "show" then error(marker) end
    shown = true
end
_G.HideUIPanel = function(frame)
    assert(frame == EditModeManagerFrame)
    hideCalls = hideCalls + 1
    if fail == "hide" then error(marker) end
    shown = false
end
assert(loadfile("MidnightSimpleUnitFrames/Runtime/MSUF_BlizzEditModeBridge.lua"))("MSUF", ns)
local set = ns.EditMode.SetBlizzardEditMode
set(false)
assert(hideCalls == 0, "bridge closed a panel it did not own")
fail = "show"
local ok, err = pcall(set, true)
assert(not ok and err == marker and not MSUF_BlizzEditModeStartedByMSUF,
    "open failure was hidden or falsely committed")
fail = nil
set(true)
assert(shown and MSUF_BlizzEditModeStartedByMSUF)
fail = "hide"
ok, err = pcall(set, false)
assert(not ok and err == marker and MSUF_BlizzEditModeStartedByMSUF,
    "close failure lost ownership or the original exception")
fail = nil
set(false)
assert(not shown and not MSUF_BlizzEditModeStartedByMSUF)
local before = showCalls
combat = true
set(true)
combat = false
MSUF_DB.general.linkEditModes = false
set(true)
assert(showCalls == before, "combat/disabled linking reached native panel mutation")
print("PASS Blizzard bridge: direct exceptions, ownership commit, native panel lifecycle")
