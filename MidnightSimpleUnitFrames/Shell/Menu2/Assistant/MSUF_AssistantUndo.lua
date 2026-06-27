-- Assistant undo runtime: snapshots applied bundles and replays undo/redo safely.
-- Keep snapshot mutation centralized so parser modules remain pure plan producers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Assistant undo stack.
-- Undo stores snapshots of plain DB state before a plan is applied and then triggers broad
-- refreshers. It must not try to resurrect frame objects or transient runtime references.
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

local function CurrentApplyService()
    return (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
end

local function RequestBroadRuntime(reason)
    local opts = {
        preview = true,
        alpha = true,
        castbar = true,
        castbarTextures = true,
        fonts = true,
        bars = true,
        colors = true,
    }
    if M and type(M.RequestGeneralApply) == "function" then
        return M.RequestGeneralApply(reason, opts)
    end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneral(reason, opts)
    end
    return false
end

local function FlushApplyService()
    local apply = CurrentApplyService()
    if apply and type(apply.Flush) == "function" then return apply.Flush() end
end

local function ScheduleNextFrame(key, fn)
    if type(fn) ~= "function" then return false end
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce(tostring(key or "MSUF_ASSISTANT_BROAD_APPLY"), fn)
        return true
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
    return true
end

local function BroadApply(reason)
    -- Undo may touch several domains at once. Use broad scheduled refreshers rather than
    -- guessing which specific runtime owned each restored DB key.
    reason = reason or "MSUF_ASSISTANT_UNDO"
    RequestBroadRuntime(reason)
    FlushApplyService()
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RefreshAll) == "function" then
            MSUF.GF.RefreshAll()
        else
            if type(MSUF.GF.RebuildAll) == "function" then MSUF.GF.RebuildAll() end
            if type(MSUF.GF.RefreshVisuals) == "function" then MSUF.GF.RefreshVisuals() end
        end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
    end
    if MSUF and MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.RequestApply) == "function" then
        MSUF.MSUF_Auras3.RequestApply()
    end
    if M and type(M.MarkMenuDataDirty) == "function" then M.MarkMenuDataDirty(reason) end
    if M and M.frame and M.frame.IsShown and M.frame:IsShown() then
        if type(M.RequestRefresh) == "function" then M.RequestRefresh(nil, reason) elseif type(M.Refresh) == "function" then M.Refresh() end
    end
end

local function BroadApplySteps(reason)
    reason = reason or "MSUF_ASSISTANT_UNDO"
    return {
        function()
            RequestBroadRuntime(reason)
        end,
        function()
            FlushApplyService()
        end,
        function()
            if MSUF and MSUF.GF then
                if type(MSUF.GF.RefreshAll) == "function" then
                    MSUF.GF.RefreshAll()
                else
                    if type(MSUF.GF.RebuildAll) == "function" then MSUF.GF.RebuildAll() end
                    if type(MSUF.GF.RefreshVisuals) == "function" then MSUF.GF.RefreshVisuals() end
                end
                if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
            end
        end,
        function()
            if MSUF and MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.RequestApply) == "function" then
                MSUF.MSUF_Auras3.RequestApply()
            end
            if M and type(M.MarkMenuDataDirty) == "function" then M.MarkMenuDataDirty(reason) end
            if M and M.frame and M.frame.IsShown and M.frame:IsShown() then
                if type(M.RequestRefresh) == "function" then M.RequestRefresh(nil, reason) elseif type(M.Refresh) == "function" then M.Refresh() end
            end
        end,
    }
end

function A.RequestBroadApply(reason, opts, callback)
    if type(opts) == "function" and callback == nil then
        callback = opts
        opts = nil
    end
    opts = opts or {}
    A._broadApplyState = A._broadApplyState or { callbacks = {}, reasons = {} }
    local state = A._broadApplyState
    state.reason = tostring(reason or state.reason or "MSUF_ASSISTANT_APPLY")
    state.reasons[#state.reasons + 1] = state.reason
    if type(callback) == "function" then state.callbacks[#state.callbacks + 1] = callback end
    if state.running or state.scheduled then return true end

    state.scheduled = true
    ScheduleNextFrame("MSUF_ASSISTANT_BROAD_APPLY", function()
        state.scheduled = nil
        state.running = true
        local runReason = state.reason or "MSUF_ASSISTANT_APPLY"
        local callbacks = state.callbacks
        state.callbacks = {}
        state.reasons = {}
        state.reason = nil

        local function Finish(result)
            state.running = nil
            if type(result) == "table" and result.status == "failed" and type(A.AddHistory) == "function" then
                A.AddHistory("assistant", result.text or "Some affected MSUF views still need a refresh.", result.status)
            end
            for i = 1, #callbacks do callbacks[i](result) end
            if state.reason and not state.scheduled then
                A.RequestBroadApply(state.reason)
            end
        end

        if type(A.StartJob) == "function" then
            A.StartJob("assistant.broad_apply", BroadApplySteps(runReason), Finish)
        else
            BroadApply(runReason)
            Finish(true)
        end
    end)
    return true
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
            local value
            if useOld then
                value = change.oldValue
            else
                value = change.newValue
            end
            setting.set(value)
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
    if type(_G.MSUF_GlobalDB) ~= "table" then ExportPublic("MSUF_GlobalDB", {}) end
    if type(snapshot.globalDB) == "table" then
        DeepReplace(_G.MSUF_GlobalDB, snapshot.globalDB)
    end

    local gdb = _G.MSUF_GlobalDB
    if type(gdb.profiles) ~= "table" then gdb.profiles = {} end
    if type(gdb.char) ~= "table" then gdb.char = {} end

    if type(snapshot.profileStates) == "table" then
        for name, state in pairs(snapshot.profileStates) do
            if type(name) == "string" and name ~= "" then
                if type(state) == "table" and state.exists == true then
                    gdb.profiles[name] = DeepCopy(type(state.data) == "table" and state.data or {})
                else
                    gdb.profiles[name] = nil
                end
            end
        end
    elseif type(snapshot.profiles) == "table" then
        for name, profile in pairs(snapshot.profiles) do
            if type(name) == "string" and name ~= "" then
                gdb.profiles[name] = DeepCopy(type(profile) == "table" and profile or {})
            end
        end
    end

    local active = snapshot.activeProfile
    if type(active) ~= "string" or active == "" then active = "Default" end
    if type(gdb.profiles[active]) ~= "table" then
        gdb.profiles[active] = DeepCopy(type(snapshot.db) == "table" and snapshot.db or {})
    end

    ExportPublic("MSUF_ActiveProfile", active)
    ExportPublic("MSUF_DB", gdb.profiles[active])

    local charKey = snapshot.charKey
    if type(charKey) ~= "string" or charKey == "" then charKey = CurrentCharKey() end
    if type(charKey) == "string" and charKey ~= "" then
        if snapshot.charExists == false then
            gdb.char[charKey] = {}
        elseif type(snapshot.char) == "table" then
            gdb.char[charKey] = DeepCopy(snapshot.char)
        elseif type(gdb.char[charKey]) ~= "table" then
            gdb.char[charKey] = {}
        end
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
        return false, "I have no Assistant change to undo."
    end
    if type(bundle.beforeProfileSnapshot) == "table" then
        if RestoreProfileSnapshot(bundle.beforeProfileSnapshot) then
            A.RequestBroadApply("MSUF_ASSISTANT_PROFILE_UNDO")
        end
    elseif type(bundle.beforeSnapshot) == "table" then
        local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
        if type(db) == "table" then
            DeepReplace(db, bundle.beforeSnapshot)
            A.RequestBroadApply("MSUF_ASSISTANT_UNDO")
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
        return false, "I have no Assistant change to redo."
    end
    if type(bundle.afterProfileSnapshot) == "table" then
        if RestoreProfileSnapshot(bundle.afterProfileSnapshot) then
            A.RequestBroadApply("MSUF_ASSISTANT_PROFILE_REDO")
        end
    elseif type(bundle.afterSnapshot) == "table" then
        local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
        if type(db) == "table" then
            DeepReplace(db, bundle.afterSnapshot)
            A.RequestBroadApply("MSUF_ASSISTANT_REDO")
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

local function AddProfileName(names, name)
    name = type(name) == "string" and name or nil
    if not name or name == "" then return end
    if type(A.ResolveProfileName) == "function" then
        local resolved = A.ResolveProfileName(name)
        if type(resolved) == "string" and resolved ~= "" then name = resolved end
    end
    names[name] = true
end

local function ProfileNamesForAction(actionKey, args, active)
    local names = {}
    AddProfileName(names, active)
    args = type(args) == "table" and args or {}
    if actionKey == "switch_profile"
        or actionKey == "create_profile"
        or actionKey == "copy_profile"
        or actionKey == "delete_profile"
        or actionKey == "import_profile_string_new"
        or actionKey == "set_spec_profile"
        or actionKey == "clear_spec_profile"
    then
        AddProfileName(names, args.name)
    end
    if actionKey == "copy_profile" then
        AddProfileName(names, args.source)
        AddProfileName(names, args.from)
    end
    return names
end

function A.CaptureProfileSnapshot(actionKey, args)
    local active = _G.MSUF_ActiveProfile
    if type(active) ~= "string" or active == "" then active = "Default" end
    local charKey = CurrentCharKey()
    local gdb = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
    local profiles = type(gdb.profiles) == "table" and gdb.profiles or {}
    local profileStates = {}
    local names = ProfileNamesForAction(actionKey, args, active)
    for name in pairs(names) do
        local profile = profiles[name]
        profileStates[name] = {
            exists = type(profile) == "table",
            data = type(profile) == "table" and DeepCopy(profile) or nil,
        }
    end
    local char = type(gdb.char) == "table" and type(charKey) == "string" and gdb.char[charKey] or nil
    return {
        version = 2,
        profileStates = profileStates,
        db = DeepCopy(_G.MSUF_DB or {}),
        activeProfile = active,
        charKey = charKey,
        charExists = type(char) == "table",
        char = type(char) == "table" and DeepCopy(char) or nil,
    }
end

function A.ApplyBroad(reason)
    return A.RequestBroadApply(reason)
end
