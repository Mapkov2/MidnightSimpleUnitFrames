local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local UNDO_LIMIT = 20

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return copy
end
A.DeepCopy = A.DeepCopy or DeepCopy

local function DeepReplace(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for key in pairs(dst) do
        if src[key] == nil then dst[key] = nil end
    end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            DeepReplace(dst[key], value)
        else
            dst[key] = value
        end
    end
end
A.DeepReplace = A.DeepReplace or DeepReplace

local function CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then fn(...) end
end

local function BroadApply(reason)
    reason = reason or "MSUF_ASSISTANT_UNDO"
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply(reason, { preview = true, alpha = true, castbar = true })
    end
    CallGlobal("MSUF_UpdateAllFonts_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_UpdateCastbarVisuals")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_RefreshAllUnitAlphas")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason)
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RebuildAll) == "function" then MSUF.GF.RebuildAll() end
        if type(MSUF.GF.RefreshVisuals) == "function" then MSUF.GF.RefreshVisuals() end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
    end
    if MSUF and MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.RequestApply) == "function" then
        MSUF.MSUF_Auras3.RequestApply()
    end
    if M and type(M.MarkMenuDataDirty) == "function" then M.MarkMenuDataDirty(reason) end
    if M and M.frame and M.frame.IsShown and M.frame:IsShown() and type(M.Refresh) == "function" then M.Refresh() end
end

function A.PushUndo(bundle)
    if type(bundle) ~= "table" then return false end
    if (type(bundle.changes) ~= "table" or #bundle.changes == 0)
        and type(bundle.beforeSnapshot) ~= "table"
        and type(bundle.beforeProfileSnapshot) ~= "table"
    then
        return false
    end
    A.undoStack = A.undoStack or {}
    A.redoStack = A.redoStack or {}
    A.undoStack[#A.undoStack + 1] = bundle
    while #A.undoStack > UNDO_LIMIT do table.remove(A.undoStack, 1) end
    for key in pairs(A.redoStack) do A.redoStack[key] = nil end
    return true
end

local function ApplyChangeList(changes, useOld)
    local registry = A.Registry
    if not registry or type(changes) ~= "table" then return false end
    local applied = {}
    local changed = false
    for i = #changes, 1, -1 do
        local change = changes[i]
        local setting = registry:GetSetting(change.key)
        if setting and type(setting.set) == "function" then
            setting.set(useOld and change.oldValue or change.newValue)
            changed = true
            if type(setting.apply) == "function" then
                applied[#applied + 1] = setting
            end
        end
    end
    for i = 1, #applied do
        applied[i].apply()
    end
    return changed
end

local function CurrentCharKey()
    local fn = _G.MSUF_GetCharKey
    if type(fn) == "function" then return fn() end
    return nil
end

local function RestoreProfileSnapshot(snapshot)
    if type(snapshot) ~= "table" then return false end
    if type(_G.MSUF_GlobalDB) ~= "table" then _G.MSUF_GlobalDB = {} end
    DeepReplace(_G.MSUF_GlobalDB, type(snapshot.globalDB) == "table" and snapshot.globalDB or {})

    local gdb = _G.MSUF_GlobalDB
    if type(gdb.profiles) ~= "table" then gdb.profiles = {} end
    if type(gdb.char) ~= "table" then gdb.char = {} end

    local active = snapshot.activeProfile
    if type(active) ~= "string" or active == "" then active = "Default" end
    if type(gdb.profiles[active]) ~= "table" then
        gdb.profiles[active] = DeepCopy(type(snapshot.db) == "table" and snapshot.db or {})
    end

    _G.MSUF_ActiveProfile = active
    _G.MSUF_DB = gdb.profiles[active]

    local charKey = snapshot.charKey
    if type(charKey) ~= "string" or charKey == "" then charKey = CurrentCharKey() end
    if type(charKey) == "string" and charKey ~= "" then
        if type(gdb.char[charKey]) ~= "table" then gdb.char[charKey] = {} end
        gdb.char[charKey].activeProfile = active
    end
    return true
end
A.RestoreProfileSnapshot = A.RestoreProfileSnapshot or RestoreProfileSnapshot

function A.UndoLast()
    A.undoStack = A.undoStack or {}
    A.redoStack = A.redoStack or {}
    local bundle = table.remove(A.undoStack)
    if not bundle then
        return false, "There is no Assistant change to undo."
    end
    if type(bundle.beforeProfileSnapshot) == "table" then
        if RestoreProfileSnapshot(bundle.beforeProfileSnapshot) then
            BroadApply("MSUF_ASSISTANT_PROFILE_UNDO")
        end
    elseif type(bundle.beforeSnapshot) == "table" then
        local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
        if type(db) == "table" then
            DeepReplace(db, bundle.beforeSnapshot)
            BroadApply("MSUF_ASSISTANT_UNDO")
        end
    else
        ApplyChangeList(bundle.changes, true)
    end
    A.redoStack[#A.redoStack + 1] = bundle
    return true, "Done. Reverted the last Assistant change."
end

function A.RedoLast()
    A.undoStack = A.undoStack or {}
    A.redoStack = A.redoStack or {}
    local bundle = table.remove(A.redoStack)
    if not bundle then
        return false, "There is no Assistant change to redo."
    end
    if type(bundle.afterProfileSnapshot) == "table" then
        if RestoreProfileSnapshot(bundle.afterProfileSnapshot) then
            BroadApply("MSUF_ASSISTANT_PROFILE_REDO")
        end
    elseif type(bundle.afterSnapshot) == "table" then
        local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
        if type(db) == "table" then
            DeepReplace(db, bundle.afterSnapshot)
            BroadApply("MSUF_ASSISTANT_REDO")
        end
    else
        ApplyChangeList(bundle.changes, false)
    end
    A.undoStack[#A.undoStack + 1] = bundle
    return true, "Done. Reapplied the Assistant change."
end

function A.CaptureSnapshot()
    local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    return DeepCopy(db or {})
end

function A.CaptureProfileSnapshot()
    return {
        globalDB = DeepCopy(_G.MSUF_GlobalDB or {}),
        db = DeepCopy(_G.MSUF_DB or {}),
        activeProfile = _G.MSUF_ActiveProfile,
        charKey = CurrentCharKey(),
    }
end

function A.ApplyBroad(reason)
    BroadApply(reason)
end
