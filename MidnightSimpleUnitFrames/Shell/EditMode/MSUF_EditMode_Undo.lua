--- EditMode/MSUF_EditMode_Undo.lua - Edit Mode undo and redo
--- Captures DB snapshots before changes, restores on undo.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_Undo.lua"
local ExportPublic = MSUF.ExportPublic
local EM2 = _G.MSUF_EM2
local Util = EM2.Util

local ApplyAllSettingsSafe = Util.ApplyAllSettingsSafe
local ApplySettingsForKeySafe = Util.ApplySettingsForKeySafe
local ProfileIdentity, IsCurrentProfile = Util.ProfileIdentity, Util.IsCurrentProfile
local SharedHistoryService = Util.SharedHistoryService
local RequestGroupGeometryApply = _G.MSUF_RequestGroupGeometryApply

local Undo = {}
EM2.Undo = Undo

local undoStack = {}
local redoStack = {}
local MAX_UNDO = 30
local debounceKey = nil
local debounceTime = 0
local DEBOUNCE_SEC = 0.5
local sharedDebounceKey
local sharedDebounceGeneration = 0
local sharedDebounceTimer
local pendingPreparedTimers = {}
local activeFallbackPrepared
local activeChangeUsesShared = false

local HISTORY_CATEGORY_LABELS = {
    unit = "Unit frame",
    castbar = "Castbar",
    general = "General layout",
    classpower = "Class Resources",
    power = "Detached power bar",
    aura = "Aura layout",
    gf = "Group frame",
    external = "External frame",
}

--- Menu2's undo surfaces show the label as given, so it is built from
--- translated pieces through translated format strings ("Move Unit frame:
--- player"). The key is a profile identifier and stays as it is.
local function HistoryChangeLabel(category, key, action)
    local tr = Util.Tr or tostring
    local label = tr(HISTORY_CATEGORY_LABELS[tostring(category or "")] or "Edit Mode")
    action = tr(tostring(action or "Change"))
    key = tostring(key or "")
    if key ~= "" then return string.format(tr("%s %s: %s"), action, label, key) end
    return string.format(tr("%s %s"), action, label)
end

local function HistoryChangeSource(category, key)
    return "edit_mode:" .. tostring(category or "change") .. ":" .. tostring(key or "")
end

local function CommitSharedDebounce()
    if not sharedDebounceKey then return false end
    sharedDebounceKey = nil
    sharedDebounceGeneration = sharedDebounceGeneration + 1
    if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
    sharedDebounceTimer = nil
    local history = SharedHistoryService()
    return history and type(history.CommitHistoryTransaction) == "function"
        and history.CommitHistoryTransaction() or false
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

local function DeepRestore(dst, src)
    for k in pairs(dst) do
        if src[k] == nil then dst[k] = nil end
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepRestore(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function ResolveGFDBKey(key)
    if key == "party" then return "gf_party" end
    if key == "raid" then return "gf_raid" end
    if key == "mythicraid" then return "gf_mythicraid" end
    if key == "priority" then return "gf_priority" end
    if key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority" then return key end
    return nil
end

local function ResolveGFKind(key)
    if key == "gf_party" then return "party" end
    if key == "gf_raid" then return "raid" end
    if key == "gf_mythicraid" then return "mythicraid" end
    if key == "gf_priority" then return "priority" end
    if key == "party" or key == "raid" or key == "mythicraid" or key == "priority" then return key end
    return nil
end

local function NormalizeCastbarUndoUnit(unit)
    unit = tostring(unit or "")
    if unit:match("^boss%d+$") then return "boss" end
    if unit:match("^arena%d+$") then return "arena" end
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" or unit == "arena" then return unit end
    return nil
end

local function ApplyCastbarUndo(unit)
    unit = NormalizeCastbarUndoUnit(unit)
    if unit then
        MSUF.Require("MSUF_ApplyCastbarUnitAndSync", CALLER)(unit)
        return true
    end
    MSUF.Require("MSUF_UpdateCastbarVisuals", CALLER)(unit)
    return true
end

local function ApplyAuraUndo(unit)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not a3 then return false end
    unit = tostring(unit or "")
    if unit ~= "" and unit ~= "shared" and unit ~= "global" and unit ~= "*" then
        if type(a3.RequestScope) == "function" then return a3.RequestScope(unit, "EM2_AURA_UNDO") end
        if type(a3.RefreshUnit) == "function" then return a3.RefreshUnit(unit) end
    end
    if type(a3.RefreshAll) == "function" then return a3.RefreshAll() end
    return false
end

local function ApplyGFUndo(key, dbKey)
    local gf = MSUF and MSUF.GF
    local kind = ResolveGFKind(key) or ResolveGFKind(dbKey)
    if RequestGroupGeometryApply(kind, "EM2_UNDO_GROUP_GEOMETRY") then
        return true
    end
    if gf and type(gf.RefreshGeometry) == "function" then
        gf.RefreshGeometry(kind)
        if type(gf.RefreshUnitBindings) == "function" then
            gf.RefreshUnitBindings(kind)
        end
        if type(gf.RefreshVisuals) == "function" then
            gf.RefreshVisuals(kind, gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)
        end
        return true
    end
    if gf and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)
        return true
    end
    return false
end

local function CaptureState(category, key)
    if category == "external" then
        local external = EM2.ExternalElements
        return external and type(external.CaptureHistoryState) == "function"
            and external.CaptureHistoryState(key) or nil
    end
    local db = _G.MSUF_DB
    if not db then return nil end
    local snap = { category = category, key = key, profile = ProfileIdentity() }
    if category == "unit" then
        snap.data = DeepCopy(db[key] or {})
    elseif category == "castbar" then
        snap.data = DeepCopy(db.general or {})
    elseif category == "general" then
        -- Edit Mode also owns a small number of global layout tools (for
        -- example the external anchor picker).  Keep them in the Edit Mode
        -- undo domain without pretending they are castbar changes.
        snap.data = DeepCopy(db.general or {})
    elseif category == "classpower" then
        snap.data = DeepCopy(db.bars or {})
    elseif category == "power" then
        snap.data = { unit = DeepCopy(db[key] or {}), bars = DeepCopy(db.bars or {}) }
    elseif category == "aura" then
        snap.data = DeepCopy(db.auras3 or {})
    elseif category == "gf" then
        local dbKey = ResolveGFDBKey(key)
        if not dbKey then return nil end
        snap.dbKey = dbKey
        snap.data = DeepCopy(db[dbKey] or {})
    end
    return snap
end

local function RestoreState(snap)
    if not snap then return end
    ExportPublic("MSUF__UndoRestoring", true)
    if snap.category == "external" then
        local external = EM2.ExternalElements
        if external and type(external.RestoreHistoryState) == "function" then
            external.RestoreHistoryState(snap)
        end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(snap.key, true)
        end
        ExportPublic("MSUF__UndoRestoring", false)
        return
    end
    local db = _G.MSUF_DB
    if not db then
        ExportPublic("MSUF__UndoRestoring", false)
        return
    end

    if snap.category == "unit" then
        db[snap.key] = db[snap.key] or {}
        DeepRestore(db[snap.key], snap.data)
        ApplySettingsForKeySafe(snap.key)
    elseif snap.category == "castbar" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        ApplyCastbarUndo(snap.key)
    elseif snap.category == "general" then
        db.general = db.general or {}
        DeepRestore(db.general, snap.data)
        ApplyAllSettingsSafe()
    elseif snap.category == "classpower" then
        db.bars = db.bars or {}
        DeepRestore(db.bars, snap.data)
        MSUF.Require("MSUF_ClassPower_RefreshLayout", CALLER)()
        MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", CALLER)("player", true)
    elseif snap.category == "power" then
        db[snap.key] = db[snap.key] or {}
        db.bars = db.bars or {}
        DeepRestore(db[snap.key], snap.data.unit)
        DeepRestore(db.bars, snap.data.bars)
        ApplySettingsForKeySafe(snap.key)
        MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", CALLER)(snap.key, true)
    elseif snap.category == "aura" then
        db.auras3 = db.auras3 or {}
        DeepRestore(db.auras3, snap.data)
        ApplyAuraUndo(snap.key)
    elseif snap.category == "gf" then
        local dbKey = snap.dbKey or ResolveGFDBKey(snap.key)
        if dbKey then
            db[dbKey] = db[dbKey] or {}
            DeepRestore(db[dbKey], snap.data)
            ApplyGFUndo(snap.key, dbKey)
            MSUF.Require("MSUF_EM2_SyncGFPopups", CALLER)()
        end
    end

    if snap.category == "unit" then MSUF.Require("MSUF_ForceTextLayoutForUnitKey", CALLER)(snap.key) end

    --- Sync popups
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    if EM2.ResourcePopup and EM2.ResourcePopup.Sync then EM2.ResourcePopup.Sync() end
    Util.SyncMovers()

    ExportPublic("MSUF__UndoRestoring", false)
end

-- Two-phase snapshots are used by fail-closed callers which can only know
-- whether an external apply succeeded after the DB write.  Failed applies do
-- not consume undo capacity or destroy the redo stack.
function Undo.PrepareChange(category, key)
    if _G.MSUF__UndoRestoring then return nil end
    --- A debounced unit nudge keeps the shared transaction open for half a
    --- second. A castbar or resource nudge inside that window is a gesture of
    --- its own: close the unit entry first, or this change folds into it.
    CommitSharedDebounce()
    local history = SharedHistoryService()
    if history and type(history.PrepareHistoryChange) == "function" then
        local prepared = history.PrepareHistoryChange(
            HistoryChangeLabel(category, key),
            HistoryChangeSource(category, key)
        )
        if prepared then
            return { category = category, key = key, shared = prepared }
        end
    end
    return CaptureState(category, key)
end

function Undo.CommitPrepared(snap)
    if _G.MSUF__UndoRestoring or type(snap) ~= "table" or type(snap.category) ~= "string" then return false end
    if snap.shared then
        local history = SharedHistoryService()
        return history and type(history.CommitPreparedHistory) == "function"
            and history.CommitPreparedHistory(snap.shared) or false
    end
    undoStack[#undoStack + 1] = snap
    if #undoStack > MAX_UNDO then table.remove(undoStack, 1) end
    for i = 1, #redoStack do redoStack[i] = nil end
    return true
end

function Undo.BeforeChange(category, key, debounce)
    if _G.MSUF__UndoRestoring then return end
    local history = SharedHistoryService()
    if history and type(history.BeginHistoryTransaction) == "function" then
        local dk = tostring(category or "") .. ":" .. tostring(key or "")
        if debounce then
            if sharedDebounceKey and sharedDebounceKey ~= dk then CommitSharedDebounce() end
            if not sharedDebounceKey then
                if not history.BeginHistoryTransaction(
                    HistoryChangeLabel(category, key),
                    HistoryChangeSource(category, key)
                ) then return false end
                sharedDebounceKey = dk
            end
            sharedDebounceGeneration = sharedDebounceGeneration + 1
            local generation = sharedDebounceGeneration
            if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
            sharedDebounceTimer = nil
            local function CommitAfterDebounce()
                sharedDebounceTimer = nil
                if (InCombatLockdown and InCombatLockdown()) then return end
                if sharedDebounceKey == dk and sharedDebounceGeneration == generation then CommitSharedDebounce() end
            end
            if C_Timer and C_Timer.NewTimer then
                sharedDebounceTimer = C_Timer.NewTimer(DEBOUNCE_SEC, CommitAfterDebounce)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(DEBOUNCE_SEC, function()
                    if (InCombatLockdown and InCombatLockdown()) then return end
                    if sharedDebounceKey == dk and sharedDebounceGeneration == generation then CommitSharedDebounce() end
                end)
            end
            return true
        end
        CommitSharedDebounce()
        local snap = Undo.PrepareChange(category, key)
        if not snap then return false end
        if snap.shared and C_Timer and (C_Timer.NewTimer or C_Timer.After) then
            local pending = { snap = snap, active = true }
            pendingPreparedTimers[pending] = true
            local function CommitPreparedAfterFrame()
                if not pending.active then return end
                pending.active = false
                pendingPreparedTimers[pending] = nil
                Undo.CommitPrepared(snap)
            end
            if C_Timer.NewTimer then
                pending.timer = C_Timer.NewTimer(0, CommitPreparedAfterFrame)
            else
                C_Timer.After(0, CommitPreparedAfterFrame)
            end
            return true
        end
        return Undo.CommitPrepared(snap)
    end
    if debounce then
        local now = GetTime()
        local dk = (category or "") .. ":" .. (key or "")
        if dk == debounceKey and (now - debounceTime) < DEBOUNCE_SEC then return end
        debounceKey = dk
        debounceTime = now
    end
    local snap = Undo.PrepareChange(category, key)
    if not snap then return end
    return Undo.CommitPrepared(snap)
end

function Undo.BeginChange(category, key, action)
    if _G.MSUF__UndoRestoring then return false end
    CommitSharedDebounce()
    local history = SharedHistoryService()
    if history and type(history.BeginHistoryTransaction) == "function" then
        activeChangeUsesShared = history.BeginHistoryTransaction(
            HistoryChangeLabel(category, key, action or "Move"),
            HistoryChangeSource(category, key)
        ) == true
        activeFallbackPrepared = nil
        return activeChangeUsesShared
    end
    activeFallbackPrepared = CaptureState(category, key)
    activeChangeUsesShared = false
    return activeFallbackPrepared ~= nil
end

function Undo.CommitChange()
    if activeChangeUsesShared then
        activeChangeUsesShared = false
        local history = SharedHistoryService()
        return history and type(history.CommitHistoryTransaction) == "function"
            and history.CommitHistoryTransaction() or false
    end
    local snap = activeFallbackPrepared
    activeFallbackPrepared = nil
    if not snap then return false end
    return Undo.CommitPrepared(snap)
end

function Undo.CancelChange(combatStarting)
    --- combatStarting: called from PLAYER_REGEN_DISABLED, before lockdown.
    local combatLocked = combatStarting == true or ((InCombatLockdown and InCombatLockdown()) and true or false)
    local history = SharedHistoryService()
    if sharedDebounceTimer and sharedDebounceTimer.Cancel then sharedDebounceTimer:Cancel() end
    sharedDebounceTimer = nil
    for pending in pairs(pendingPreparedTimers) do
        pending.active = false
        if pending.timer and pending.timer.Cancel then pending.timer:Cancel() end
        if combatLocked and pending.snap and pending.snap.shared
            and history and type(history.DeferPreparedHistory) == "function" then
            history.DeferPreparedHistory(pending.snap.shared)
        end
        pendingPreparedTimers[pending] = nil
    end
    local hadSharedChange = activeChangeUsesShared or sharedDebounceKey ~= nil
    activeChangeUsesShared = false
    activeFallbackPrepared = nil
    sharedDebounceKey = nil
    sharedDebounceGeneration = sharedDebounceGeneration + 1
    if combatLocked and hadSharedChange and history and type(history.CommitHistoryTransaction) == "function" then
        return history.CommitHistoryTransaction()
    end
    return history and type(history.CancelHistoryTransaction) == "function"
        and history.CancelHistoryTransaction() or false
end

local function ClearLocalHistory()
    for i = 1, #undoStack do undoStack[i] = nil end
    for i = 1, #redoStack do redoStack[i] = nil end
end

local function IsForeignProfileSnap(snap)
    return snap.category ~= "external" and not IsCurrentProfile(snap.profile)
end

function Undo.DoUndo()
    CommitSharedDebounce()
    if activeChangeUsesShared or activeFallbackPrepared then Undo.CommitChange() end
    local history = SharedHistoryService()
    if history and type(history.Undo) == "function" then return history.Undo() end
    if #undoStack == 0 then return end
    local snap = undoStack[#undoStack]
    undoStack[#undoStack] = nil
    if IsForeignProfileSnap(snap) then
        ClearLocalHistory()
        return
    end
    local current = CaptureState(snap.category, snap.key)
    if current then redoStack[#redoStack + 1] = current end
    RestoreState(snap)
end

function Undo.DoRedo()
    CommitSharedDebounce()
    if activeChangeUsesShared or activeFallbackPrepared then Undo.CommitChange() end
    local history = SharedHistoryService()
    if history and type(history.Redo) == "function" then return history.Redo() end
    if #redoStack == 0 then return end
    local snap = redoStack[#redoStack]
    redoStack[#redoStack] = nil
    if IsForeignProfileSnap(snap) then
        ClearLocalHistory()
        return
    end
    local current = CaptureState(snap.category, snap.key)
    if current then undoStack[#undoStack + 1] = current end
    RestoreState(snap)
end

function Undo.Clear()
    CommitSharedDebounce()
    activeFallbackPrepared = nil
    activeChangeUsesShared = false
    for i = 1, #undoStack do undoStack[i] = nil end
    for i = 1, #redoStack do redoStack[i] = nil end
    debounceKey = nil
    local history = SharedHistoryService()
    if history and type(history.ClearHistory) == "function" then history.ClearHistory() end
end

function Undo.CanUndo()
    local history = SharedHistoryService()
    if history and type(history.GetHistoryState) == "function" then
        local state = history.GetHistoryState()
        return state and state.canUndo == true
    end
    return #undoStack > 0
end
function Undo.CanRedo()
    local history = SharedHistoryService()
    if history and type(history.GetHistoryState) == "function" then
        local state = history.GetHistoryState()
        return state and state.canRedo == true
    end
    return #redoStack > 0
end

function Undo.RefreshControls()
    if EM2.HUD and EM2.HUD.RefreshControls then EM2.HUD.RefreshControls() end
    if EM2.UnitPopup and EM2.UnitPopup.RefreshHistory then EM2.UnitPopup.RefreshHistory() end
    if EM2.CastPopup and EM2.CastPopup.RefreshHistory then EM2.CastPopup.RefreshHistory() end
    if EM2.AuraPopup and EM2.AuraPopup.RefreshHistory then EM2.AuraPopup.RefreshHistory() end
    if EM2.ResourcePopup and EM2.ResourcePopup.RefreshHistory then EM2.ResourcePopup.RefreshHistory() end
    if EM2.ExternalPopup and EM2.ExternalPopup.RefreshHistory then EM2.ExternalPopup.RefreshHistory() end
    MSUF.Require("MSUF_EM2_RefreshGFHistoryControls", CALLER)()
end

function EM2.RefreshAfterHistoryRestore(reason)
    Undo.RefreshControls()
    if not (EM2.State and EM2.State.IsActive and EM2.State.IsActive()) then return end
    if Util.IsConfigCombatLocked and Util.IsConfigCombatLocked() then return end

    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    --- An open popup that keeps the undone values in its boxes writes them
    --- back with the next edit (ApplyResource re-reads all four boxes).
    if EM2.ResourcePopup and EM2.ResourcePopup.Sync then EM2.ResourcePopup.Sync() end
    local external = EM2.ExternalPopup
    if external and external.Sync and external.IsOpen and external.IsOpen() then external.Sync() end
    MSUF.Require("MSUF_EM2_SyncGFPopups", CALLER)()
    Util.SyncMovers()
    Util.RefreshUFPreview(reason or "EM2_HISTORY_RESTORE")

    -- This is a cold, user-triggered restore path. The async preview pipeline
    -- coalesces all UnitFrame preview work without adding an idle/combat loop.
    MSUF.Require("MSUF_SyncAllUnitPreviewsAsync", CALLER)()
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout() end
end

--- Legacy globals
local function MSUF_EM_UndoBeforeChange(category, key, debounce) Undo.BeforeChange(category, key, debounce) end
local function MSUF_EM_UndoBeginChange(category, key, action) return Undo.BeginChange(category, key, action) end
local function MSUF_EM_UndoCommitChange() return Undo.CommitChange() end
local function MSUF_EM_UndoClear() Undo.Clear() end
local function MSUF_EM_UndoUndo() Undo.DoUndo() end
local function MSUF_EM_UndoRedo() Undo.DoRedo() end
local function MSUF_EM_RefreshHistoryControls() Undo.RefreshControls() end
local function MSUF_EM_RefreshAfterHistoryRestore(reason, source) return EM2.RefreshAfterHistoryRestore(reason, source) end

ExportPublic("MSUF_EM_UndoBeforeChange", MSUF_EM_UndoBeforeChange)
ExportPublic("MSUF_EM_UndoBeginChange", MSUF_EM_UndoBeginChange)
ExportPublic("MSUF_EM_UndoCommitChange", MSUF_EM_UndoCommitChange)
ExportPublic("MSUF_EM_UndoClear", MSUF_EM_UndoClear)
ExportPublic("MSUF_EM_UndoUndo", MSUF_EM_UndoUndo)
ExportPublic("MSUF_EM_UndoRedo", MSUF_EM_UndoRedo)
ExportPublic("MSUF_EM_RefreshHistoryControls", MSUF_EM_RefreshHistoryControls)
ExportPublic("MSUF_EM_RefreshAfterHistoryRestore", MSUF_EM_RefreshAfterHistoryRestore)
