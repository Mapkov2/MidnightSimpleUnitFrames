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

local function DeepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not DeepEqual(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function CaptureField(container, key)
    local value
    if type(container) == "table" then value = rawget(container, key) end
    return { exists = value ~= nil, value = DeepCopy(value) }
end

local function RestoreField(container, key, state)
    if type(container) ~= "table" or type(state) ~= "table" then return false end
    if state.exists == true then
        container[key] = DeepCopy(state.value)
    else
        container[key] = nil
    end
    return true
end

local function CapturePublicValue(name)
    local value = rawget(_G, name)
    return { exists = value ~= nil, value = DeepCopy(value) }
end

local function RestorePublicValue(name, state)
    if type(state) ~= "table" then return false end
    if state.exists == true then
        ExportPublic(name, DeepCopy(state.value))
    else
        ExportPublic(name, nil)
    end
    return true
end

local function ActionCharKey()
    local fn = _G.MSUF_GetCharKey
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn)
    if not ok or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function TrimActionText(value)
    value = tostring(value or "")
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ActiveProfileValue()
    local value = tostring(_G.MSUF_ActiveProfile or "Default")
    if value == "" then return "Default" end
    return value
end

local function ProfileAliasName(globalDB, db)
    local profiles = type(globalDB) == "table" and globalDB.profiles or nil
    if type(profiles) ~= "table" or type(db) ~= "table" then return nil end
    for name, profile in pairs(profiles) do
        if profile == db and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

local function CaptureProfileDBReference(globalDB)
    local db = rawget(_G, "MSUF_DB")
    if db == nil then return { exists = false }, nil end
    local alias = ProfileAliasName(globalDB, db)
    if alias then return { exists = true, aliased = true }, alias end
    return { exists = true, value = DeepCopy(db) }, nil
end

local function ResolveProfileOwnerIdentity(actionKey, args, prior)
    if type(prior) == "table"
        and prior.kind == "assistantActionTransaction"
        and prior.actionKey == actionKey
        and type(prior.identity) == "table"
    then
        return DeepCopy(prior.identity)
    end

    args = type(args) == "table" and args or {}
    local source = TrimActionText(args.source)
    local destination = TrimActionText(args.name or args.destination)
    if actionKey == "rename_profile" and source == "" then source = ActiveProfileValue() end
    if source == "" then return nil, "profile source is required" end
    if destination == "" then return nil, "profile destination is required" end

    if type(A.ResolveProfileName) == "function" then
        local ok, resolved, how = pcall(A.ResolveProfileName, source)
        if not ok then return nil, "profile-name resolver failed: " .. tostring(resolved) end
        if how == "multiple" then return nil, "profile source is ambiguous" end
        if type(resolved) == "string" and resolved ~= "" then source = resolved end
    end

    local identity = { source = source, destination = destination }
    if actionKey == "copy_profile_from_to" then
        identity.charKey = ActionCharKey()
        if not identity.charKey then return nil, "current character binding is unavailable" end
    end
    return identity
end

local function CaptureProfileOwnerState(identity, captureAllCharacters)
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" or type(globalDB.profiles) ~= "table" then
        return nil, "profile store is unavailable"
    end
    local entries = {}
    entries[identity.source] = CaptureField(globalDB.profiles, identity.source)
    entries[identity.destination] = CaptureField(globalDB.profiles, identity.destination)

    local characterState
    if captureAllCharacters then
        characterState = { mode = "all", root = CaptureField(globalDB, "char") }
    elseif type(globalDB.char) == "table" then
        characterState = {
            mode = "one",
            rootWasTable = true,
            charKey = identity.charKey,
            entry = CaptureField(globalDB.char, identity.charKey),
        }
    else
        characterState = {
            mode = "one",
            rootWasTable = false,
            root = CaptureField(globalDB, "char"),
            charKey = identity.charKey,
        }
    end

    local dbState, dbAlias = CaptureProfileDBReference(globalDB)
    return {
        profileEntries = entries,
        characters = characterState,
        activeProfile = CapturePublicValue("MSUF_ActiveProfile"),
        db = dbState,
        dbAliasProfile = dbAlias,
    }
end

local function RestoreProfileOwnerState(state)
    if type(state) ~= "table" or type(state.profileEntries) ~= "table" then
        return false, "invalid profile-owner snapshot"
    end
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" then
        globalDB = {}
        ExportPublic("MSUF_GlobalDB", globalDB)
    else
        ExportPublic("MSUF_GlobalDB", globalDB)
    end
    if type(globalDB.profiles) ~= "table" then globalDB.profiles = {} end
    for name, entry in pairs(state.profileEntries) do
        if type(name) ~= "string" or name == "" or not RestoreField(globalDB.profiles, name, entry) then
            return false, "invalid profile entry in owner snapshot"
        end
    end

    local characters = state.characters
    if type(characters) ~= "table" then return false, "missing character binding snapshot" end
    if characters.mode == "all" then
        if not RestoreField(globalDB, "char", characters.root) then return false, "could not restore character bindings" end
    elseif characters.mode == "one" and characters.rootWasTable == true then
        if type(characters.charKey) ~= "string" or characters.charKey == "" then return false, "missing character key" end
        if type(globalDB.char) ~= "table" then globalDB.char = {} end
        if not RestoreField(globalDB.char, characters.charKey, characters.entry) then return false, "could not restore character binding" end
    elseif characters.mode == "one" then
        if not RestoreField(globalDB, "char", characters.root) then return false, "could not restore character root" end
    else
        return false, "unsupported character binding snapshot"
    end

    if not RestorePublicValue("MSUF_ActiveProfile", state.activeProfile) then return false, "could not restore active profile" end
    if type(state.db) ~= "table" then return false, "missing profile DB snapshot" end
    if state.db.exists == true then
        local alias = state.dbAliasProfile
        if type(alias) == "string" and type(globalDB.profiles[alias]) == "table" then
            ExportPublic("MSUF_DB", globalDB.profiles[alias])
        else
            ExportPublic("MSUF_DB", DeepCopy(state.db.value))
        end
    else
        ExportPublic("MSUF_DB", nil)
    end
    return true
end

local function CaptureWagoBackupState(profileName)
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" then
        return { level = "root", root = CapturePublicValue("MSUF_GlobalDB") }
    end
    if type(globalDB.global) ~= "table" then
        return { level = "global", value = CaptureField(globalDB, "global") }
    end
    if type(globalDB.global.dashboard) ~= "table" then
        return { level = "dashboard", value = CaptureField(globalDB.global, "dashboard") }
    end
    local dashboard = globalDB.global.dashboard
    if type(dashboard.wagoProfileBackupConfirmed) ~= "table" then
        return { level = "map", value = CaptureField(dashboard, "wagoProfileBackupConfirmed") }
    end
    return {
        level = "entry",
        entry = CaptureField(dashboard.wagoProfileBackupConfirmed, profileName),
    }
end

local function RestoreWagoBackupState(state, profileName)
    if type(state) ~= "table" then return false, "invalid Wago backup snapshot" end
    if state.level == "root" then return RestorePublicValue("MSUF_GlobalDB", state.root) end
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" then globalDB = {}; ExportPublic("MSUF_GlobalDB", globalDB) end
    if state.level == "global" then return RestoreField(globalDB, "global", state.value) end
    if type(globalDB.global) ~= "table" then globalDB.global = {} end
    if state.level == "dashboard" then return RestoreField(globalDB.global, "dashboard", state.value) end
    if type(globalDB.global.dashboard) ~= "table" then globalDB.global.dashboard = {} end
    local dashboard = globalDB.global.dashboard
    if state.level == "map" then return RestoreField(dashboard, "wagoProfileBackupConfirmed", state.value) end
    if state.level ~= "entry" or type(profileName) ~= "string" or profileName == "" then
        return false, "unsupported Wago backup snapshot"
    end
    if type(dashboard.wagoProfileBackupConfirmed) ~= "table" then dashboard.wagoProfileBackupConfirmed = {} end
    return RestoreField(dashboard.wagoProfileBackupConfirmed, profileName, state.entry)
end

local function CaptureNoMatchState()
    local state = { lastNoMatch = CaptureField(A, "_lastNoMatch") }
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" then
        state.level, state.root = "root", CapturePublicValue("MSUF_GlobalDB")
        return state
    end
    if type(globalDB.global) ~= "table" then
        state.level, state.value = "global", CaptureField(globalDB, "global")
        return state
    end
    if type(globalDB.global.assistantNoMatch) ~= "table" then
        state.level, state.value = "store", CaptureField(globalDB.global, "assistantNoMatch")
        return state
    end
    local store = globalDB.global.assistantNoMatch
    state.level = "fields"
    state.total = CaptureField(store, "total")
    state.recent = CaptureField(store, "recent")
    state.counts = CaptureField(store, "counts")
    return state
end

local function RestoreNoMatchState(state)
    if type(state) ~= "table" or type(state.lastNoMatch) ~= "table" then return false, "invalid no-match snapshot" end
    if not RestoreField(A, "_lastNoMatch", state.lastNoMatch) then return false, "could not restore no-match pointer" end
    if state.level == "root" then return RestorePublicValue("MSUF_GlobalDB", state.root) end
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    if type(globalDB) ~= "table" then globalDB = {}; ExportPublic("MSUF_GlobalDB", globalDB) end
    if state.level == "global" then return RestoreField(globalDB, "global", state.value) end
    if type(globalDB.global) ~= "table" then globalDB.global = {} end
    if state.level == "store" then return RestoreField(globalDB.global, "assistantNoMatch", state.value) end
    if state.level ~= "fields" then return false, "unsupported no-match snapshot" end
    if type(globalDB.global.assistantNoMatch) ~= "table" then globalDB.global.assistantNoMatch = {} end
    local store = globalDB.global.assistantNoMatch
    return RestoreField(store, "total", state.total)
        and RestoreField(store, "recent", state.recent)
        and RestoreField(store, "counts", state.counts)
end

local function CaptureFactoryResetState()
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    local dbState, dbAlias = CaptureProfileDBReference(globalDB)
    return {
        globalDB = CapturePublicValue("MSUF_GlobalDB"),
        activeProfile = CapturePublicValue("MSUF_ActiveProfile"),
        db = dbState,
        dbAliasProfile = dbAlias,
    }
end

local function RestoreFactoryResetState(state)
    if type(state) ~= "table" or type(state.globalDB) ~= "table"
        or type(state.activeProfile) ~= "table" or type(state.db) ~= "table"
    then
        return false, "invalid factory-reset snapshot"
    end
    if not RestorePublicValue("MSUF_GlobalDB", state.globalDB) then return false, "could not restore global DB" end
    if not RestorePublicValue("MSUF_ActiveProfile", state.activeProfile) then return false, "could not restore active profile" end
    if state.db.exists == true then
        local globalDB = rawget(_G, "MSUF_GlobalDB")
        local alias = state.dbAliasProfile
        if type(alias) == "string" and type(globalDB) == "table"
            and type(globalDB.profiles) == "table" and type(globalDB.profiles[alias]) == "table"
        then
            ExportPublic("MSUF_DB", globalDB.profiles[alias])
        else
            ExportPublic("MSUF_DB", DeepCopy(state.db.value))
        end
    else
        ExportPublic("MSUF_DB", nil)
    end
    return true
end

local ACTION_TRANSACTION_ADAPTERS = {
    profileCopyFromTo = { actionKey = "copy_profile_from_to", mode = "capturedOwnerState" },
    profileRename = { actionKey = "rename_profile", mode = "capturedOwnerState" },
    factoryResetAll = { actionKey = "factory_reset_all", mode = "capturedOwnerState" },
    globalDashboardWagoBackup = { actionKey = "confirm_wago_backup", mode = "capturedOwnerState" },
    globalAssistantNoMatch = { actionKey = "assistant_nomatch_clear", mode = "capturedOwnerState" },
    managedHistory = {
        mode = "selfManaged",
        actionKeys = {
            ["assistant.action.editMode.cancel"] = true,
            ["assistant.action.editMode.redo"] = true,
            ["assistant.action.editMode.undo"] = true,
            menu_history_redo = true,
            menu_history_undo = true,
        },
    },
    assistantHistoryBundle = {
        mode = "selfManaged",
        actionKeys = { ["assistant.action.history.redo"] = true, ["assistant.action.history.undo"] = true },
    },
    userConfirmedAnchorPicker = {
        mode = "deferredUserInput",
        actionKeys = {
            ["assistant.action.editMode.anchorPicker"] = true,
            start_group_custom_anchor_picker = true,
            start_unit_custom_anchor_picker = true,
        },
    },
}

local function AdapterAllowsAction(adapter, actionKey)
    if type(adapter) ~= "table" or type(actionKey) ~= "string" or actionKey == "" then return false end
    if adapter.actionKey then return adapter.actionKey == actionKey end
    return type(adapter.actionKeys) == "table" and adapter.actionKeys[actionKey] == true
end

function A.GetActionTransactionAdapterMode(adapterName, actionKey)
    local adapter = ACTION_TRANSACTION_ADAPTERS[tostring(adapterName or "")]
    if not AdapterAllowsAction(adapter, actionKey) then return nil end
    return adapter.mode
end

function A.CaptureActionTransaction(actionKey, args, adapterName, prior)
    local adapter = ACTION_TRANSACTION_ADAPTERS[tostring(adapterName or "")]
    if not AdapterAllowsAction(adapter, actionKey) or adapter.mode ~= "capturedOwnerState" then
        return nil, "unknown or unsupported action transaction adapter"
    end

    local identity
    local state
    local err
    if adapterName == "profileCopyFromTo" or adapterName == "profileRename" then
        identity, err = ResolveProfileOwnerIdentity(actionKey, args, prior)
        if not identity then return nil, err end
        state, err = CaptureProfileOwnerState(identity, adapterName == "profileRename")
    elseif adapterName == "factoryResetAll" then
        state = CaptureFactoryResetState()
    elseif adapterName == "globalDashboardWagoBackup" then
        identity = type(prior) == "table" and prior.identity and DeepCopy(prior.identity)
            or { profileName = ActiveProfileValue() }
        state = CaptureWagoBackupState(identity.profileName)
    elseif adapterName == "globalAssistantNoMatch" then
        state = CaptureNoMatchState()
    end
    if type(state) ~= "table" then return nil, err or "action owner state could not be captured" end
    return {
        kind = "assistantActionTransaction",
        version = 1,
        adapter = adapterName,
        actionKey = actionKey,
        args = DeepCopy(type(args) == "table" and args or {}),
        identity = DeepCopy(identity),
        state = state,
    }
end

function A.RestoreActionTransaction(snapshot, reason)
    if type(snapshot) ~= "table" or snapshot.kind ~= "assistantActionTransaction" or snapshot.version ~= 1 then
        return false, "invalid action transaction snapshot"
    end
    local adapter = ACTION_TRANSACTION_ADAPTERS[tostring(snapshot.adapter or "")]
    if not AdapterAllowsAction(adapter, snapshot.actionKey) or adapter.mode ~= "capturedOwnerState" then
        return false, "unknown or unsupported action transaction adapter"
    end

    local restored
    local err
    if snapshot.adapter == "profileCopyFromTo" or snapshot.adapter == "profileRename" then
        restored, err = RestoreProfileOwnerState(snapshot.state)
    elseif snapshot.adapter == "factoryResetAll" then
        restored, err = RestoreFactoryResetState(snapshot.state)
    elseif snapshot.adapter == "globalDashboardWagoBackup" then
        restored, err = RestoreWagoBackupState(snapshot.state, snapshot.identity and snapshot.identity.profileName)
    elseif snapshot.adapter == "globalAssistantNoMatch" then
        restored, err = RestoreNoMatchState(snapshot.state)
    end
    if restored ~= true then return false, err or "action owner state could not be restored" end

    local verify
    if snapshot.adapter == "profileCopyFromTo" or snapshot.adapter == "profileRename" then
        verify, err = CaptureProfileOwnerState(snapshot.identity, snapshot.adapter == "profileRename")
    elseif snapshot.adapter == "factoryResetAll" then
        verify = CaptureFactoryResetState()
    elseif snapshot.adapter == "globalDashboardWagoBackup" then
        verify = CaptureWagoBackupState(snapshot.identity and snapshot.identity.profileName)
    elseif snapshot.adapter == "globalAssistantNoMatch" then
        verify = CaptureNoMatchState()
    end
    if type(verify) ~= "table" or not DeepEqual(verify, snapshot.state) then
        return false, err or "restored action owner state did not verify"
    end

    if snapshot.adapter == "factoryResetAll" then
        local stagedNil = snapshot.state.globalDB and snapshot.state.globalDB.exists ~= true
            and snapshot.state.db and snapshot.state.db.exists ~= true
            and snapshot.state.activeProfile and snapshot.state.activeProfile.exists ~= true
        A._preserveNilSavedVariablesUntilReload = stagedNil and true or nil
    end

    if snapshot.adapter == "profileCopyFromTo" or snapshot.adapter == "profileRename"
        or (snapshot.adapter == "factoryResetAll" and snapshot.state.db and snapshot.state.db.exists == true)
    then
        if type(_G.MSUF_UFCore_InvalidateSettingsCache) == "function" then pcall(_G.MSUF_UFCore_InvalidateSettingsCache) end
        local core = MSUF and MSUF.MSUF_UnitframeCore
        if core and type(core.InvalidateAllFrameConfigs) == "function" then pcall(core.InvalidateAllFrameConfigs) end
        if reason and type(A.RequestBroadApply) == "function" then pcall(A.RequestBroadApply, reason) end
    elseif snapshot.adapter == "globalDashboardWagoBackup" then
        if M and type(M.InvalidatePage) == "function" then pcall(M.InvalidatePage, "home") end
    end
    return true
end

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

local function RequestAurasRuntime(reason)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestAuraFonts) == "function" then
        return apply.RequestAuraFonts("shared", reason or "MSUF_ASSISTANT_UNDO_AURAS")
    end
    if apply and type(apply.RequestAuras) == "function" then
        return apply.RequestAuras("shared", reason or "MSUF_ASSISTANT_UNDO_AURAS")
    end
    if MSUF and MSUF.MSUF_Auras3 and type(MSUF.MSUF_Auras3.RequestApply) == "function" then
        MSUF.MSUF_Auras3.RequestApply()
        return true
    end
    return false
end

local function RequestGroupRuntime(reason)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGroupReset) == "function" then
        return apply.RequestGroupReset(reason or "MSUF_ASSISTANT_UNDO_GROUP")
    end
    if apply and type(apply.RequestGroup) == "function" then
        return apply.RequestGroup("group", "reset", reason or "MSUF_ASSISTANT_UNDO_GROUP")
    end
    local GP = M and M.GroupPage
    if GP and type(GP.QueueGF) == "function" then
        GP.QueueGF("party", "rebuild")
        GP.QueueGF("raid", "rebuild")
        GP.QueueGF("mythicraid", "rebuild")
        return true
    end
    if MSUF and MSUF.GF then
        if type(MSUF.GF.RefreshAll) == "function" then
            MSUF.GF.RefreshAll()
        elseif type(MSUF.GF.RefreshVisuals) == "function" then
            MSUF.GF.RefreshVisuals()
        end
        if type(MSUF.GF.RefreshPreviewLayout) == "function" then MSUF.GF.RefreshPreviewLayout() end
        return true
    end
    return false
end

local function ScheduleNextFrame(key, fn)
    if type(fn) ~= "function" then return false end
    if (type(A.IsCombatLocked) == "function" and A.IsCombatLocked()) or A._menuRuntimeActive == false then return false end
    A.undoNextFramePending = A.undoNextFramePending or {}
    A.undoNextFrameOrder = A.undoNextFrameOrder or {}
    local nextFramePending = A.undoNextFramePending
    local nextFrameOrder = A.undoNextFrameOrder
    key = tostring(key or "MSUF_ASSISTANT_BROAD_APPLY")
    if nextFramePending[key] == nil then
        nextFrameOrder[#nextFrameOrder + 1] = key
    end
    nextFramePending[key] = fn
    if A.undoNextFrameQueued then return true end
    A.undoNextFrameQueued = true
    local timer
    local function Run()
        if type(A.UntrackMenuRuntimeTimer) == "function" then A.UntrackMenuRuntimeTimer("assistant.undo.next_frame", timer) end
        A.undoNextFrameQueued = false
        if (type(A.IsCombatLocked) == "function" and A.IsCombatLocked()) or A._menuRuntimeActive == false then return end
        local pending = A.undoNextFramePending or {}
        local order = A.undoNextFrameOrder or {}
        A.undoNextFramePending = {}
        A.undoNextFrameOrder = {}
        for i = 1, #order do
            local cb = pending[order[i]]
            if type(cb) == "function" then cb() end
        end
    end
    if _G.C_Timer and type(_G.C_Timer.NewTimer) == "function" then
        timer = _G.C_Timer.NewTimer(0, Run)
        if type(A.TrackMenuRuntimeTimer) == "function" then A.TrackMenuRuntimeTimer("assistant.undo.next_frame", timer) end
    else
        Run()
    end
    return true
end

local function BroadApply(reason)
    -- Undo may touch several domains at once. Use broad scheduled refreshers rather than
    -- guessing which specific runtime owned each restored DB key.
    reason = reason or "MSUF_ASSISTANT_UNDO"
    RequestBroadRuntime(reason)
    FlushApplyService()
    RequestGroupRuntime(reason)
    FlushApplyService()
    RequestAurasRuntime(reason)
    FlushApplyService()
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
            RequestGroupRuntime(reason)
            FlushApplyService()
        end,
        function()
            RequestAurasRuntime(reason)
            FlushApplyService()
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
        and type(bundle.beforeActionTransaction) ~= "table"
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
    if not registry or type(changes) ~= "table" then return false, "Assistant registry is unavailable." end
    local prepared = {}
    for i = #changes, 1, -1 do
        local change = changes[i]
        local setting = registry:GetSetting(change.key)
        if not (setting and type(setting.get) == "function" and type(setting.set) == "function") then
            return false, "Assistant setting is unavailable: " .. tostring(change.key or i)
        end
        local readOk, current = pcall(setting.get)
        if not readOk then return false, "Could not read " .. tostring(change.key or i) .. ": " .. tostring(current) end
        prepared[#prepared + 1] = {
            setting = setting,
            before = DeepCopy(current),
            target = DeepCopy(useOld and change.oldValue or change.newValue),
        }
    end

    local written = {}
    local applySettings = {}
    local function RunApplies()
        local seen = {}
        for i = 1, #applySettings do
            local setting = applySettings[i]
            local key = setting.key or setting
            if not seen[key] and type(setting.apply) == "function" then
                seen[key] = true
                local ok, err = pcall(setting.apply)
                if not ok then return false, err end
            end
        end
        local service = CurrentApplyService()
        if service and type(service.Flush) == "function" then
            local ok, err = pcall(service.Flush)
            if not ok then return false, err end
        end
        return true
    end
    local function Rollback()
        for i = #written, 1, -1 do
            local item = written[i]
            pcall(item.setting.set, DeepCopy(item.before))
        end
        RunApplies()
    end

    for i = 1, #prepared do
        local item = prepared[i]
        local ok, err = pcall(item.setting.set, DeepCopy(item.target))
        if not ok then
            Rollback()
            return false, "Could not restore " .. tostring(item.setting.key or i) .. ": " .. tostring(err)
        end
        written[#written + 1] = item
        applySettings[#applySettings + 1] = item.setting
        local readOk, actual = pcall(item.setting.get)
        if not readOk then
            Rollback()
            return false, "Could not verify " .. tostring(item.setting.key or i) .. ": " .. tostring(actual)
        end
        local same
        if type(item.setting.sameValue) == "function" then
            local compareOk, value = pcall(item.setting.sameValue, actual, item.target)
            same = compareOk and value == true
        elseif item.setting.type == "number" and tonumber(actual) and tonumber(item.target) then
            same = math.abs(tonumber(actual) - tonumber(item.target)) < 0.0001
        else
            same = actual == item.target
        end
        if not same then
            Rollback()
            return false, "Stored value differs while restoring " .. tostring(item.setting.key or i)
        end
    end
    local applied, applyErr = RunApplies()
    if not applied then
        Rollback()
        return false, "Could not refresh restored settings: " .. tostring(applyErr)
    end
    return #written > 0
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

function A.RestoreSnapshot(snapshot, reason)
    if type(snapshot) ~= "table" then return false end
    local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return false end
    DeepReplace(db, snapshot)
    if reason and type(A.RequestBroadApply) == "function" then
        pcall(A.RequestBroadApply, reason)
    end
    return true
end

function A.UndoLast()
    A.undoStack = A.undoStack or {}
    A.redoStack = A.redoStack or {}
    local bundle = A.undoStack[#A.undoStack]
    if not bundle then
        return false, "I have no Assistant change to undo."
    end
    local restored = false
    local restoreError
    if type(bundle.beforeActionTransaction) == "table" then
        local ok, value, detail = pcall(A.RestoreActionTransaction, bundle.beforeActionTransaction, "MSUF_ASSISTANT_ACTION_UNDO")
        restored = ok and value == true
        if not restored then restoreError = detail or value end
    elseif type(bundle.beforeProfileSnapshot) == "table" then
        local ok, value = pcall(RestoreProfileSnapshot, bundle.beforeProfileSnapshot)
        restored = ok and value == true
        if restored then
            if type(A.RequestBroadApply) == "function" then pcall(A.RequestBroadApply, "MSUF_ASSISTANT_PROFILE_UNDO") end
        else
            restoreError = value
        end
    elseif type(bundle.beforeSnapshot) == "table" then
        local ok, value = pcall(A.RestoreSnapshot, bundle.beforeSnapshot, "MSUF_ASSISTANT_UNDO")
        restored = ok and value == true
        if not restored then restoreError = value end
    else
        restored, restoreError = ApplyChangeList(bundle.changes, true)
    end
    if not restored then
        return false, "I could not safely undo that Assistant change, so I kept it on the undo stack. " .. tostring(restoreError or "")
    end
    table.remove(A.undoStack)
    A.redoStack[#A.redoStack + 1] = bundle
    return true, "Done. Reverted the last Assistant change."
end

function A.RedoLast()
    A.undoStack = A.undoStack or {}
    A.redoStack = A.redoStack or {}
    local bundle = A.redoStack[#A.redoStack]
    if not bundle then
        return false, "I have no Assistant change to redo."
    end
    local restored = false
    local restoreError
    if type(bundle.afterActionTransaction) == "table" then
        local ok, value, detail = pcall(A.RestoreActionTransaction, bundle.afterActionTransaction, "MSUF_ASSISTANT_ACTION_REDO")
        restored = ok and value == true
        if not restored then restoreError = detail or value end
    elseif type(bundle.afterProfileSnapshot) == "table" then
        local ok, value = pcall(RestoreProfileSnapshot, bundle.afterProfileSnapshot)
        restored = ok and value == true
        if restored then
            if type(A.RequestBroadApply) == "function" then pcall(A.RequestBroadApply, "MSUF_ASSISTANT_PROFILE_REDO") end
        else
            restoreError = value
        end
    elseif type(bundle.afterSnapshot) == "table" then
        local ok, value = pcall(A.RestoreSnapshot, bundle.afterSnapshot, "MSUF_ASSISTANT_REDO")
        restored = ok and value == true
        if not restored then restoreError = value end
    else
        restored, restoreError = ApplyChangeList(bundle.changes, false)
    end
    if not restored then
        return false, "I could not safely redo that Assistant change, so I kept it on the redo stack. " .. tostring(restoreError or "")
    end
    table.remove(A.redoStack)
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
