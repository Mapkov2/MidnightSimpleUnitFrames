-- Executable shared-history regression for Menu2 and Edit Mode.
-- It covers surface lifetime, cross-surface undo/redo, prepared changes,
-- drag transactions, targeted apply, preview notification, and cancel markers.

_G = _G or _ENV

local deepCopyCalls = 0
local function DeepCopy(value, seen)
    deepCopyCalls = deepCopyCalls + 1
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}; seen[value] = copy
    for key, item in pairs(value) do copy[DeepCopy(key, seen)] = DeepCopy(item, seen) end
    return copy
end
local function KeySet(...)
    local out = {}; for i = 1, select("#", ...) do out[select(i, ...)] = true end; return out
end
local function Words(text, asSet)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do
        if asSet then out[word] = true else out[#out + 1] = word end
    end
    return out
end

local profile = {
    general = { marker = 1 },
    player = { offsetX = 0, offsetY = 0, width = 220 },
    gf_party = { offsetX = -400, offsetY = 0 },
    auras3 = { shared = { spacing = 2 } },
}
_G.MSUF_DB = profile
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GlobalDB = {
    profiles = { Default = profile },
    char = { ["Tester-Realm"] = { specAutoSwitch = false, specProfileMap = { [1] = "Default" } } },
}
_G.MSUF_GetCharKey = function() return "Tester-Realm" end
_G.C_Timer = { After = function(_, fn) if type(fn) == "function" then fn() end end }

local counters = { unit = 0, group = 0, aura = 0, flush = 0, editRefresh = 0 }
_G.MSUF_EM_RefreshAfterHistoryRestore = function()
    counters.editRefresh = counters.editRefresh + 1
end

local namespace = { MSUF2 = {} }
namespace.ExportPublic = function(name, value) _G[name] = value; return value end
local M = namespace.MSUF2
M.KeySet = KeySet
M.KeySetFromWords = function(text) return Words(text, true) end
M.WordList = function(text) return Words(text, false) end
M.DeepCopy = DeepCopy
local combatLocked = false
M.IsConfigCombatLocked = function() return combatLocked end
M.CallIf = function(fn, ...) if type(fn) == "function" then return fn(...) end end
M.ApplyService = {
    SafeInvoke = function(fn, ...)
        local ok, a, b, c = pcall(fn, ...)
        return ok, a, b, c
    end,
    CallGlobal = function() return false end,
    NormalizeUnit = function(unit) return unit end,
    RequestUnit = function(unit)
        assert(unit == "player", "unit history restore was not scoped to Player")
        counters.unit = counters.unit + 1
        return true
    end,
    RequestGroup = function(scope)
        assert(scope == "party", "group history restore lost its scope")
        counters.group = counters.group + 1
        return true
    end,
    RequestAuras = function(scope)
        assert(scope == "player", "aura history restore lost its unit scope")
        counters.aura = counters.aura + 1
        return true
    end,
    Flush = function() counters.flush = counters.flush + 1 end,
}

assert(loadfile("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua"))(
    "MidnightSimpleUnitFrames", namespace)

assert(M.StartHistorySession("edit_mode") == true, "Edit Mode history surface did not start")
assert(M.CaptureHistory("Move Unit frame: player", "edit_mode:unit:player", function()
    profile.player.offsetX = 25
    return true
end) == true, "Edit Mode change was not captured")
assert(M.GetHistoryState().undoCount == 1, "Edit Mode change did not create one history step")

assert(M.StartHistorySession("menu") == true, "Menu history surface did not join")
assert(M.GetHistoryState().undoCount == 1, "opening Menu2 cleared Edit Mode history")
assert(M.Undo() == true and profile.player.offsetX == 0, "Menu2 could not undo an Edit Mode change")
assert(counters.unit == 1 and counters.flush >= 1, "unit undo did not use the targeted immediate apply path")
assert(M.Redo() == true and profile.player.offsetX == 25, "Menu2 could not redo an Edit Mode change")

assert(M.CaptureHistory("Player width", "uf_player:slider:Player width", function()
    profile.player.width = 260
    return true
end) == true, "Menu2 unit change was not captured")
assert(M.EndHistorySession("menu") == true, "Menu history surface did not end")
assert(M.GetHistoryState().activeSurfaces == 1, "ending Menu2 also ended Edit Mode history")
assert(M.Undo() == true and profile.player.width == 220, "Edit Mode could not undo a Menu2 change")

local beforeDragCount = M.GetHistoryState().undoCount
assert(M.BeginHistoryTransaction("Move Unit frame: player", "edit_mode:unit:player") == true, "drag transaction did not start")
for x = 30, 90, 15 do profile.player.offsetX = x end
assert(M.CommitHistoryTransaction() == true, "drag transaction did not commit")
assert(M.GetHistoryState().undoCount == beforeDragCount + 1, "a drag created more than one history step")
assert(M.Undo() == true and profile.player.offsetX == 25, "drag undo did not restore its exact start")
assert(M.Redo() == true and profile.player.offsetX == 90, "drag redo did not restore its exact final position")

local prepared = assert(M.PrepareHistoryChange("Aura spacing", "edit_mode:aura:player"))
profile.auras3.shared.spacing = 7
assert(M.CommitPreparedHistory(prepared) == true, "prepared Edit Mode change did not commit")
assert(M.Undo() == true and profile.auras3.shared.spacing == 2, "prepared aura undo failed")
assert(counters.aura == 1, "aura undo did not use the scoped aura apply path")

assert(M.CaptureHistory("Party position", "group:party:offsetX", function()
    profile.gf_party.offsetX = -350
    return true
end) == true, "group change was not captured")
assert(M.Undo() == true and profile.gf_party.offsetX == -400, "group undo failed")
assert(counters.group == 1, "group undo did not use the scoped group apply path")

profile.general.marker = 9
assert(M.CheckpointHistory("Marker", "general:marker") == true, "post-marker change was not captured")
assert(M.BeginHistoryTransaction("Pending drag", "edit_mode:unit:player") == true, "pending cancel transaction did not start")
profile.player.offsetY = 45
_G.MSUF_GlobalDB.char["Tester-Realm"].specAutoSwitch = true
_G.MSUF_GlobalDB.char["Tester-Realm"].specProfileMap[1] = "Raid"
assert(M.CancelHistorySurface("edit_mode", true) == true, "Edit Mode cancel marker was not restored")
assert(profile.general.marker == 1 and profile.player.offsetX == 0 and profile.player.offsetY == 0,
    "Edit Mode cancel did not restore the complete active profile")
assert(_G.MSUF_GlobalDB.char["Tester-Realm"].specAutoSwitch == false
    and _G.MSUF_GlobalDB.char["Tester-Realm"].specProfileMap[1] == "Default",
    "Edit Mode cancel did not restore spec-profile routing")
assert(M.GetHistoryState().undoCount == 0, "Edit Mode cancel left its session entries in shared history")
assert(M.CommitHistoryTransaction() == false, "Edit Mode cancel left a pending transaction alive")

assert(M.EndHistorySession("edit_mode") == true, "Edit Mode history surface did not end")
assert(M.GetHistoryState().activeSurfaces == 0, "shared history still reports an active surface")
assert(M.StartHistorySession("menu") == true, "Menu history surface did not reopen")
assert(M.CaptureHistory("Menu marker", "general:marker", function()
    profile.general.marker = 2
    return true
end) == true, "Menu history did not restart after Edit Mode cancel")
local beforeNestedEdit = DeepCopy(profile)
assert(M.StartHistorySession("edit_mode") == true, "nested Edit Mode surface did not start")
assert(M.CaptureHistory("Nested Edit move", "edit_mode:unit:player", function()
    profile.player.offsetX = 50
    return true
end) == true, "nested Edit Mode change was not captured")
assert(M.CancelHistorySurface("edit_mode", true) == true, "nested Edit Mode cancel failed")
assert(profile.player.offsetX == beforeNestedEdit.player.offsetX, "nested Edit Mode cancel did not restore its entry state")
assert(M.GetHistoryState().undoCount == 1, "nested Edit Mode cancel removed earlier Menu2 history")
assert(M.EndHistorySession("edit_mode") == true, "nested Edit Mode surface did not end")
assert(M.EndHistorySession("menu") == true, "Menu surface did not end")
assert(M.StartHistorySession("menu") == true, "Menu history surface did not reopen a second time")
assert(M.GetHistoryState().undoCount == 1, "reopening Menu2 cleared shared history")
assert(counters.editRefresh >= 5, "undo/redo did not notify Edit Mode preview synchronization")

-- Combat may begin between the first and final snapshot of a drag. That edge
-- must do no DB copy, apply, preview refresh, or history-stack mutation while
-- combat is active. The interrupted step is finalized on the next config use.
local combatUndoBase = M.GetHistoryState().undoCount
local combatStartX = profile.player.offsetX
assert(M.BeginHistoryTransaction("Combat-interrupted drag", "edit_mode:unit:player") == true,
    "combat-interrupted drag transaction did not start")
profile.player.offsetX = 73
local copiesBeforeCombatCommit = deepCopyCalls
local combatFanoutBefore = {
    unit = counters.unit,
    group = counters.group,
    aura = counters.aura,
    flush = counters.flush,
    editRefresh = counters.editRefresh,
}
combatLocked = true
assert(M.CommitHistoryTransaction() == false, "combat transaction unexpectedly committed in combat")
assert(deepCopyCalls == copiesBeforeCombatCommit, "combat transaction copied the profile")
assert(M.GetHistoryState().undoCount == combatUndoBase, "combat transaction mutated the undo stack")
assert(counters.unit == combatFanoutBefore.unit and counters.group == combatFanoutBefore.group
    and counters.aura == combatFanoutBefore.aura and counters.flush == combatFanoutBefore.flush
    and counters.editRefresh == combatFanoutBefore.editRefresh,
    "combat transaction triggered apply or preview fanout")
local copiesBeforeBlockedUndo = deepCopyCalls
assert(M.Undo() == false, "undo was allowed in combat")
assert(deepCopyCalls == copiesBeforeBlockedUndo, "blocked combat undo copied history state")
assert(M.GetHistoryState().undoCount == combatUndoBase, "blocked combat undo popped the stack")
assert(M.EndHistorySession("menu") == true, "combat history surface did not close cheaply")
assert(M.GetHistoryState().activeSurfaces == 0, "combat history close left an active surface")
assert(deepCopyCalls == copiesBeforeBlockedUndo, "combat history close copied the profile")
assert(counters.unit == combatFanoutBefore.unit and counters.group == combatFanoutBefore.group
    and counters.aura == combatFanoutBefore.aura and counters.flush == combatFanoutBefore.flush
    and counters.editRefresh == combatFanoutBefore.editRefresh,
    "combat history close triggered apply or preview fanout")
combatLocked = false
assert(M.StartHistorySession("menu") == true, "history did not reopen after combat")
assert(M.GetHistoryState().undoCount == combatUndoBase + 1,
    "combat-interrupted drag was not finalized after combat")
assert(M.Undo() == true and profile.player.offsetX == combatStartX,
    "deferred combat drag did not restore its exact start")

local combatPreparedBase = M.GetHistoryState().undoCount
local preparedCombat = assert(M.PrepareHistoryChange("Combat prepared width", "edit_mode:unit:player"))
local combatStartWidth = profile.player.width
profile.player.width = 281
local copiesBeforePreparedCommit = deepCopyCalls
combatLocked = true
assert(M.CommitPreparedHistory(preparedCombat) == false, "prepared history committed in combat")
assert(deepCopyCalls == copiesBeforePreparedCommit, "prepared combat history copied the profile")
assert(M.GetHistoryState().undoCount == combatPreparedBase, "prepared combat history mutated the undo stack")
combatLocked = false
assert(M.FlushDeferredHistory() == true, "prepared combat history did not finalize after combat")
assert(M.Undo() == true and profile.player.width == combatStartWidth,
    "deferred prepared history did not restore its exact start")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end
local function Contains(source, needle, message)
    assert(source:find(needle, 1, true), message or ("missing contract: " .. needle))
end
local core = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua")
local movers = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua")
local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
local castbars = Read("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarPreviewEdit.lua")
local groups = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua")
local window = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Window.lua")
Contains(core, 'history.StartHistorySession("edit_mode")', "Edit Mode does not join shared history")
Contains(core, 'history.CancelHistorySurface("edit_mode", true)', "Cancel All does not rewind the Edit Mode history marker")
Contains(core, 'history.EndHistorySession("edit_mode")', "Edit Mode does not leave shared history")
Contains(core, 'ExportPublic("MSUF_EM_RefreshAfterHistoryRestore"', "Edit Mode restore preview bridge is missing")
Contains(core, 'if combatLocked and EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end',
    "combat exit does not cancel history timers before hiding movers")
Contains(core, 'C_Timer.NewTimer(DEBOUNCE_SEC, CommitAfterDebounce)',
    "Edit Mode debounce history does not use a cancellable timer")
Contains(core, 'if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end',
    "Edit Mode debounce history timer is not cancelled")
Contains(core, 'pending.timer = C_Timer.NewTimer(0, CommitPreparedAfterFrame)',
    "prepared Edit Mode history does not use a cancellable timer")
assert(not core:find("SNAPSHOT_KEYS", 1, true), "Cancel All still snapshots only a partial profile")
for name, source in pairs({ movers = movers, auras = auras, castbars = castbars, groups = groups }) do
    Contains(source, "MSUF_EM_UndoBeginChange", name .. " drag does not begin a shared transaction")
    Contains(source, "MSUF_EM_UndoCommitChange", name .. " drag does not commit a shared transaction")
end
Contains(window, 'M.CallIf(M.StartHistorySession, "menu")', "Menu2 does not identify its shared history surface")
Contains(window, 'M.CallIf(M.EndHistorySession, "menu")', "Menu2 does not release its shared history surface")
local bindings = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua")
Contains(bindings, 'if IsConfigCombatLocked() then', "shared history has no combat commit guard")
Contains(bindings, 'DeferHistoryCommit(tx.label, tx.source, tx.before)',
    "combat-interrupted history is not deferred without a snapshot")
Contains(bindings, 'refreshTimer = C_Timer.NewTimer(MENU_REFRESH_DELAY, Run)',
    "history menu refresh does not use a cancellable timer")
assert(not bindings:find('SetScript("OnUpdate"', 1, true), "shared history introduced an OnUpdate hotpath")

print(string.format(
    "unified_history_surface_smoke: ok undo=%d unit=%d group=%d aura=%d editRefresh=%d",
    M.GetHistoryState().undoCount, counters.unit, counters.group, counters.aura, counters.editRefresh
))
