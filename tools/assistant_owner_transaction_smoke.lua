_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local suppliedAddonRoot = select(1, ...)
local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local assistantRoot = RuntimeManifest.ResolveCompanionRoot(suppliedAddonRoot) .. "/Assistant/"

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

local function equal(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do if not equal(value, b[key], seen) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.GetTime = function() return os.clock() end
_G.GetServerTime = function() return 123456 end
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.MSUF_GetCharKey = function() return "Realm-Player" end
_G.MSUF_ScheduleOnce = function(_, fn) if type(fn) == "function" then fn() end end
_G.C_Timer = { After = function(_, fn) if type(fn) == "function" then fn() end end }
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(kind, fn) if kind == "OnEvent" then self.onEvent = fn end end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end

local M = MSUF.MSUF2
M.EnsureDB = function() return _G.MSUF_DB end
M.RequestGeneralApply = function() return true end
M.ApplyService = { Flush = function() end }
M.InvalidatePage = function() end

local function loadAssistant(name)
    local chunk, err = loadfile(assistantRoot .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadAssistant("MSUF_AssistantHistory.lua")
loadAssistant("MSUF_AssistantUndo.lua")
loadAssistant("MSUF_AssistantRegistry_ActionInputs.lua")
loadAssistant("MSUF_Assistant.lua")

local A = assert(MSUF.Assistant, "Assistant missing")
local originalRemember = A.RememberAppliedBundle
local originalPushUndo = A.PushUndo
local genericSnapshotCalls = 0
A.CaptureSnapshot = function() genericSnapshotCalls = genericSnapshotCalls + 1; return {} end
A.CaptureProfileSnapshot = function() genericSnapshotCalls = genericSnapshotCalls + 1; return {} end

local function status(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

local function resetStacks()
    A.undoStack = {}
    A.redoStack = {}
    A.RememberAppliedBundle = originalRemember
    A.PushUndo = originalPushUndo
    A._preserveNilSavedVariablesUntilReload = nil
    genericSnapshotCalls = 0
end

local function actionPlan(key, adapter, run, args)
    local inputContract = assert(A.ActionInputs.GetContract(key), "missing test action input contract for " .. tostring(key))
    return {
        kind = "action",
        summary = key,
        args = args or {},
        action = {
            key = key,
            label = key,
            mutability = "savedState",
            mutatesState = true,
            rollbackStrategy = "transactionAdapter",
            transactionAdapter = adapter,
            transactionAdapterMode = "capturedOwnerState",
            transactionAdapterReady = true,
            assistantInputExplicit = true,
            assistantInput = inputContract,
            -- Stale generic flags must never cause a second capture when an
            -- owner adapter is declared.
            captureSnapshot = true,
            captureProfileSnapshot = true,
            run = run,
        },
    }
end

local function execute(plan)
    local result = A.ExecutePlan(plan)
    local tx = A.lastAssistantTransactionError
    assert(status(result) == "applied", tostring(plan.action.key) .. " did not apply: " .. tostring(result and result.text)
        .. " [" .. tostring(tx and tx.phase) .. ": " .. tostring(tx and tx.error) .. "]")
    assert(genericSnapshotCalls == 0, tostring(plan.action.key) .. " used a generic snapshot in addition to its owner adapter")
    return result
end

-- No-match owner: exact fields and the in-memory last pointer are reversible.
resetStacks()
_G.MSUF_DB = { general = {} }
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GlobalDB = {
    global = { assistantNoMatch = {
        total = 7,
        recent = { { text = "one" } },
        counts = { one = { count = 7 } },
        untouched = "keep",
    } },
}
A._lastNoMatch = { text = "one", nested = { 1, 2 } }
local noMatchBefore = copy(_G.MSUF_GlobalDB.global.assistantNoMatch)
local lastBefore = copy(A._lastNoMatch)
local noMatchPlan = actionPlan("assistant_nomatch_clear", "globalAssistantNoMatch", function()
    local store = _G.MSUF_GlobalDB.global.assistantNoMatch
    store.total, store.recent, store.counts = 0, {}, {}
    A._lastNoMatch = nil
    return true, "cleared"
end)
execute(noMatchPlan)
assert(A.UndoLast() == true, "no-match undo failed")
assert(equal(_G.MSUF_GlobalDB.global.assistantNoMatch, noMatchBefore), "no-match undo was not exact")
assert(equal(A._lastNoMatch, lastBefore), "last-no-match pointer was not restored")
assert(A.RedoLast() == true, "no-match redo failed")
assert(_G.MSUF_GlobalDB.global.assistantNoMatch.total == 0 and A._lastNoMatch == nil)
assert(_G.MSUF_GlobalDB.global.assistantNoMatch.untouched == "keep")

-- Profile copy: source/destination, the current character binding, active
-- profile and MSUF_DB alias all round-trip.
resetStacks()
_G.MSUF_GlobalDB = {
    profiles = {
        Default = { value = 1 },
        Other = { value = 2 },
    },
    char = {
        ["Realm-Player"] = { activeProfile = "Other", specProfileMap = { [1] = "Default" }, marker = "mine" },
        ["Realm-Other"] = { activeProfile = "Default", marker = "other" },
    },
    global = { untouched = true },
}
_G.MSUF_ActiveProfile = "Other"
_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Other
local copyOtherCharBefore = copy(_G.MSUF_GlobalDB.char["Realm-Other"])
local copyPlan = actionPlan("copy_profile_from_to", "profileCopyFromTo", function(args)
    _G.MSUF_GlobalDB.profiles[args.name] = copy(_G.MSUF_GlobalDB.profiles[args.source])
    _G.MSUF_GlobalDB.profiles[args.name].translated = true
    _G.MSUF_GlobalDB.char["Realm-Player"].activeProfile = args.name
    _G.MSUF_ActiveProfile = args.name
    _G.MSUF_DB = _G.MSUF_GlobalDB.profiles[args.name]
    return true, "copied"
end, { source = "Default", name = "Raid" })
execute(copyPlan)
assert(_G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Raid, "copy did not end with a DB alias")
assert(A.UndoLast() == true, "copy undo failed")
assert(_G.MSUF_GlobalDB.profiles.Raid == nil, "copy undo kept a newly-created destination")
assert(_G.MSUF_ActiveProfile == "Other" and _G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Other)
assert(_G.MSUF_GlobalDB.char["Realm-Player"].activeProfile == "Other")
assert(equal(_G.MSUF_GlobalDB.char["Realm-Other"], copyOtherCharBefore), "copy touched another character")
assert(A.RedoLast() == true, "copy redo failed")
assert(_G.MSUF_GlobalDB.profiles.Raid.translated == true)
assert(_G.MSUF_ActiveProfile == "Raid" and _G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Raid)

-- Rename captures the whole character binding owner so every active/spec link
-- referencing the old name is restored exactly.
resetStacks()
_G.MSUF_GlobalDB = {
    profiles = { Default = { value = 0 }, Old = { value = 5 } },
    char = {
        A = { activeProfile = "Old", specProfileMap = { [1] = "Old", [2] = "Default" }, nested = { x = 1 } },
        B = { activeProfile = "Default", specProfileMap = { [3] = "Old" }, nested = { y = 2 } },
    },
    global = { untouched = "global" },
}
_G.MSUF_ActiveProfile = "Old"
_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Old
local renameCharsBefore = copy(_G.MSUF_GlobalDB.char)
local renamePlan = actionPlan("rename_profile", "profileRename", function(args)
    local profiles = _G.MSUF_GlobalDB.profiles
    profiles[args.name], profiles[args.source] = profiles[args.source], nil
    profiles[args.name].translated = "rename"
    for _, char in pairs(_G.MSUF_GlobalDB.char) do
        if char.activeProfile == args.source then char.activeProfile = args.name end
        for specID, profileName in pairs(char.specProfileMap or {}) do
            if profileName == args.source then char.specProfileMap[specID] = args.name end
        end
    end
    _G.MSUF_ActiveProfile = args.name
    _G.MSUF_DB = profiles[args.name]
    return true, "renamed"
end, { source = "Old", name = "New" })
execute(renamePlan)
assert(A.UndoLast() == true, "rename undo failed")
assert(_G.MSUF_GlobalDB.profiles.New == nil and _G.MSUF_GlobalDB.profiles.Old.value == 5)
assert(equal(_G.MSUF_GlobalDB.char, renameCharsBefore), "rename undo missed a character/spec binding")
assert(_G.MSUF_ActiveProfile == "Old" and _G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Old)
assert(A.RedoLast() == true, "rename redo failed")
assert(_G.MSUF_GlobalDB.profiles.Old == nil and _G.MSUF_GlobalDB.profiles.New.translated == "rename")
assert(_G.MSUF_GlobalDB.char.A.activeProfile == "New")
assert(_G.MSUF_GlobalDB.char.A.specProfileMap[1] == "New" and _G.MSUF_GlobalDB.char.B.specProfileMap[3] == "New")

-- Factory reset must leave all three SavedVariables globals nil. Undo restores
-- the complete graph and the MSUF_DB/profile alias; redo stages nil again.
resetStacks()
_G.MSUF_GlobalDB = {
    profiles = { Default = { value = 42, nested = { true } } },
    char = { ["Realm-Player"] = { activeProfile = "Default", specProfileMap = { [7] = "Default" } } },
    global = { dashboard = { marker = true } },
}
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Default
local factoryBefore = copy(_G.MSUF_GlobalDB)
local factoryPlan = actionPlan("factory_reset_all", "factoryResetAll", function()
    _G.MSUF_DB, _G.MSUF_GlobalDB, _G.MSUF_ActiveProfile = nil, nil, nil
    return true, "reset staged"
end)
local factoryResult = execute(factoryPlan)
assert(factoryResult.preserveNilSavedVariables == true, "factory reset did not expose its nil-SV contract")
assert(_G.MSUF_DB == nil and _G.MSUF_GlobalDB == nil and _G.MSUF_ActiveProfile == nil, "factory reset recreated SavedVariables")
assert(A.UndoLast() == true, "factory undo failed")
assert(equal(_G.MSUF_GlobalDB, factoryBefore), "factory undo did not restore the complete global graph")
assert(_G.MSUF_ActiveProfile == "Default" and _G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Default)
assert(A._preserveNilSavedVariablesUntilReload == nil)
assert(A.RedoLast() == true, "factory redo failed")
assert(_G.MSUF_DB == nil and _G.MSUF_GlobalDB == nil and _G.MSUF_ActiveProfile == nil, "factory redo did not restore nil globals")
assert(A._preserveNilSavedVariablesUntilReload == true)

local function historyActionPlan(key, run)
    local inputContract = assert(A.ActionInputs.GetContract(key), "missing history action input contract")
    return {
        kind = "action",
        action = {
            key = key,
            label = key,
            mutability = "savedState",
            transactionAdapter = "assistantHistoryBundle",
            transactionAdapterMode = "selfManaged",
            transactionAdapterReady = true,
            rollbackStrategy = "transactionAdapter",
            assistantInputExplicit = true,
            assistantInput = inputContract,
            run = run,
        },
    }
end
local wrappedUndo = A.ExecutePlan(historyActionPlan("assistant.action.history.undo", function() return A.UndoLast() end))
assert(status(wrappedUndo) == "applied" and _G.MSUF_GlobalDB ~= nil,
    "Assistant history undo did not restore factory-reset state")
local wrappedRedo = A.ExecutePlan(historyActionPlan("assistant.action.history.redo", function() return A.RedoLast() end))
assert(status(wrappedRedo) == "applied" and wrappedRedo.preserveNilSavedVariables == true,
    "Assistant history redo did not preserve the factory-reset nil contract")
assert(_G.MSUF_DB == nil and _G.MSUF_GlobalDB == nil and _G.MSUF_ActiveProfile == nil,
    "wrapped factory redo recreated SavedVariables")

-- A run failure restores the owner, while a context-commit failure restores
-- both owner state and the pre-existing history stacks.
resetStacks()
_G.MSUF_DB = { general = {} }
_G.MSUF_ActiveProfile = "Default"
_G.MSUF_GlobalDB = { global = { assistantNoMatch = { total = 1, recent = {}, counts = {} } } }
local failedRun = actionPlan("assistant_nomatch_clear", "globalAssistantNoMatch", function()
    _G.MSUF_GlobalDB.global.assistantNoMatch.total = 9
    error("run failure")
end)
assert(status(A.ExecutePlan(failedRun)) == "failed")
assert(_G.MSUF_GlobalDB.global.assistantNoMatch.total == 1, "run failure left owner mutation")
assert(#A.undoStack == 0)

A.undoStack = { { changes = { { key = "existing" } } } }
A.redoStack = { { changes = { { key = "redo" } } } }
A.RememberAppliedBundle = function() error("context commit failure") end
local failedCommit = actionPlan("assistant_nomatch_clear", "globalAssistantNoMatch", function()
    _G.MSUF_GlobalDB.global.assistantNoMatch.total = 9
    return true, "cleared"
end)
assert(status(A.ExecutePlan(failedCommit)) == "failed")
assert(_G.MSUF_GlobalDB.global.assistantNoMatch.total == 1, "commit failure left owner mutation")
assert(#A.undoStack == 1 and #A.redoStack == 1, "commit failure changed undo/redo history")

-- Unknown, mismatched and not-ready adapters all fail before action.run.
resetStacks()
_G.MSUF_DB = { general = {} }
_G.MSUF_GlobalDB = { global = {} }
_G.MSUF_ActiveProfile = "Default"
local ran = false
local unknown = actionPlan("assistant_nomatch_clear", "doesNotExist", function() ran = true; return true end)
assert(status(A.ExecutePlan(unknown)) == "failed" and ran == false, "unknown adapter did not fail closed")
local mismatched = actionPlan("rename_profile", "globalAssistantNoMatch", function() ran = true; return true end, { source = "A", name = "B" })
assert(status(A.ExecutePlan(mismatched)) == "failed" and ran == false, "mismatched adapter did not fail closed")
local notReady = actionPlan("assistant_nomatch_clear", "globalAssistantNoMatch", function() ran = true; return true end)
notReady.action.transactionAdapterReady = false
assert(status(A.ExecutePlan(notReady)) == "failed" and ran == false, "not-ready adapter did not fail closed")

print("assistant_owner_transaction_smoke: ok")
