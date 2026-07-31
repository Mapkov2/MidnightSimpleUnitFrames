--- MidnightSimpleUnitFrames 6.0 guided setup lifecycle.
---
--- The menu owns presentation and page routing. This early state module only
--- persists progress so a long, optional tour can survive reloads without
--- changing the active profile or any configuration value by itself.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local type, tostring, pairs = type, tostring, pairs
local time = time

local REVISION = 1
local DEFAULT_STAGE = "menu_basics"
local EDIT_MODE_STAGE = "edit_mode"
local GROUP_EDIT_MODE_STAGE = "group_edit_mode"
local EDIT_MODE_MOVED_PREFERENCE = "editModeMoved"
local EDIT_MODE_MOVED_KEY_PREFERENCE = "editModeMovedKey"
local COOLDOWN_ANCHOR_PREFERENCE = "unitframeCooldownAnchor"
local VALID_STATUS = {
    inactive = true,
    active = true,
    completed = true,
    dismissed = true,
}
local VALID_RESULT = {
    reviewed = "r",
    kept = "k",
    skipped = "s",
}

local function Now()
    return type(time) == "function" and time() or 0
end

local globalDB = rawget(_G, "MSUF_GlobalDB")
if type(globalDB) ~= "table" then
    globalDB = {}
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then globalDB.global = {} end

local function NewState()
    return {
        schema = 1,
        revision = REVISION,
        status = "inactive",
        currentStageId = DEFAULT_STAGE,
        currentStageIndex = 1,
        cursors = {},
        stageResults = {},
        sectionResults = {},
        sectionMetadata = {},
        controlResults = {},
        skippedControls = {},
        preferences = {},
    }
end

local function Normalize(target)
    target.schema = 1
    if not VALID_STATUS[target.status] then target.status = "inactive" end
    if type(target.currentStageId) ~= "string" or target.currentStageId == "" then
        target.currentStageId = DEFAULT_STAGE
    end
    target.currentStageIndex = math.max(1, tonumber(target.currentStageIndex) or 1)
    target.cursors = type(target.cursors) == "table" and target.cursors or {}
    target.stageResults = type(target.stageResults) == "table" and target.stageResults or {}
    target.sectionResults = type(target.sectionResults) == "table" and target.sectionResults or {}
    target.sectionMetadata = type(target.sectionMetadata) == "table" and target.sectionMetadata or {}
    target.controlResults = type(target.controlResults) == "table" and target.controlResults or {}
    target.skippedControls = type(target.skippedControls) == "table" and target.skippedControls or {}
    target.preferences = type(target.preferences) == "table" and target.preferences or {}
    return target
end

local state = globalDB.global.guidedTour6
if type(state) ~= "table" or state.revision ~= REVISION then
    state = NewState()
    globalDB.global.guidedTour6 = state
else
    Normalize(state)
end

local Tour = MSUF.GuidedTour6 or {}
MSUF.GuidedTour6 = Tour
_G.MSUF_GuidedTour6 = Tour

-- This module loads before `MSUF_GlobalDB` is guaranteed to exist, and profile
-- repair or a full reset can replace the root afterwards. Without re-resolving
-- it, a completed or dismissed tour is recorded in an orphaned table while the
-- menu keeps reading "inactive" from that same orphan, so the tour offers
-- itself again on every visit. Mirrors MSUF_FirstLoad.lua's SyncLiveState.
local function SyncLiveState()
    local liveDB = rawget(_G, "MSUF_GlobalDB")
    if type(liveDB) ~= "table" then
        _G.MSUF_GlobalDB = globalDB
        return state
    end
    if type(liveDB.global) ~= "table" then
        liveDB.global = {}
    end
    globalDB = liveDB
    local liveState = globalDB.global.guidedTour6
    if liveState ~= state then
        if type(liveState) == "table" and liveState.revision == REVISION then
            state = Normalize(liveState)
        else
            globalDB.global.guidedTour6 = state
        end
    end
    return state
end

-- Every public entry point below reads or writes `state`, so each one calls
-- SyncLiveState first. Wrapping them in a loop would be shorter, but an
-- explicit call is what MSUF_FirstLoad does and it stays obvious to the next
-- reader adding a method.

local function Touch()
    state.updatedAt = Now()
end

local function CopyCursor(cursor)
    cursor = type(cursor) == "table" and cursor or {}
    return {
        overview = cursor.overview ~= false,
        sectionId = type(cursor.sectionId) == "string" and cursor.sectionId or nil,
        sectionIndex = math.max(0, tonumber(cursor.sectionIndex) or 0),
        controlId = type(cursor.controlId) == "string" and cursor.controlId or nil,
        controlIndex = math.max(0, tonumber(cursor.controlIndex) or 0),
        controlTotal = math.max(0, tonumber(cursor.controlTotal) or 0),
    }
end

local function ResultCode(result)
    return VALID_RESULT[result] or (result == "r" or result == "k" or result == "s") and result or nil
end

function Tour:GetState()
    return SyncLiveState()
end

function Tour:SyncSavedVariables()
    return SyncLiveState()
end

function Tour:IsActive()
    SyncLiveState()
    return state.status == "active"
end

function Tour:Start(profileName, firstStageId, restorePoint)
    SyncLiveState()
    local fresh = NewState()
    fresh.status = "active"
    fresh.currentStageId = type(firstStageId) == "string" and firstStageId ~= "" and firstStageId or DEFAULT_STAGE
    fresh.profileName = tostring(profileName or _G.MSUF_ActiveProfile or "Default")
    if type(restorePoint) == "table" then
        fresh.restorePoint = restorePoint
        fresh.restorePointCreatedAt = Now()
    end
    fresh.startedAt = Now()
    state = fresh
    globalDB.global.guidedTour6 = state
    return true
end

function Tour:GetRestorePoint()
    SyncLiveState()
    return type(state.restorePoint) == "table" and state.restorePoint or nil
end

function Tour:MarkRestorePointUsed(used)
    SyncLiveState()
    if state.status ~= "active" or type(state.restorePoint) ~= "table" then return false end
    if used == false then
        state.restorePointUsedAt = nil
    else
        state.restorePointUsedAt = Now()
    end
    Touch()
    return true
end

function Tour:Resume()
    SyncLiveState()
    if state.status ~= "active" then return false end
    state.resumedAt = Now()
    Touch()
    return true
end

function Tour:SetStage(stageId, stageIndex)
    SyncLiveState()
    if state.status ~= "active" or type(stageId) ~= "string" or stageId == "" then return false end
    state.currentStageId = stageId
    state.currentStageIndex = math.max(1, tonumber(stageIndex) or state.currentStageIndex or 1)
    Touch()
    return true
end

function Tour:GetPreference(key)
    SyncLiveState()
    key = type(key) == "string" and key or ""
    if key == "" then return nil end
    return state.preferences[key]
end

function Tour:SetPreference(key, value)
    SyncLiveState()
    if state.status ~= "active" or type(key) ~= "string" or key == "" then return false end
    local valueType = type(value)
    if value ~= nil and valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then return false end
    state.preferences[key] = value
    Touch()
    return true
end

function Tour:IsEditModePlacementComplete()
    SyncLiveState()
    return state.preferences[EDIT_MODE_MOVED_PREFERENCE] == true
        and state.preferences.editModePopupOpened == true
end

function Tour:IsGroupEditModePlacementComplete()
    SyncLiveState()
    return state.preferences.groupEditModeMoved == true
        and state.preferences.groupEditModePopupOpened == true
end

function Tour:MarkEditModePopupOpened(moverKey)
    SyncLiveState()
    if state.status ~= "active" then return false end
    moverKey = tostring(moverKey or "")
    if state.currentStageId == GROUP_EDIT_MODE_STAGE then
        if moverKey ~= "gf_party" and moverKey ~= "party" then return false end
        local changed = state.preferences.groupEditModePopupOpened ~= true
        state.preferences.groupEditModePopupOpened = true
        state.preferences.groupEditModePopupOpenedKey = moverKey
        Touch()
        return true, changed
    end
    if state.currentStageId ~= EDIT_MODE_STAGE or moverKey ~= "player" then return false end
    local changed = state.preferences.editModePopupOpened ~= true
    state.preferences.editModePopupOpened = true
    state.preferences.editModePopupOpenedKey = moverKey
    Touch()
    return true, changed
end

function Tour:MarkEditModePlacementComplete(moverKey)
    SyncLiveState()
    if state.status ~= "active" then return false end
    moverKey = tostring(moverKey or "")
    if state.currentStageId == GROUP_EDIT_MODE_STAGE then
        if moverKey ~= "gf_party" and moverKey ~= "party" then return false end
        local changed = state.preferences.groupEditModeMoved ~= true
        state.preferences.groupEditModeMoved = true
        state.preferences.groupEditModeMovedKey = moverKey
        Touch()
        return true, changed
    end
    if state.currentStageId ~= EDIT_MODE_STAGE then return false end
    if moverKey ~= "player" then return false end
    local anchor = state.preferences[COOLDOWN_ANCHOR_PREFERENCE]
    if anchor ~= "cooldown" and anchor ~= "independent" then return false end
    local changed = state.preferences[EDIT_MODE_MOVED_PREFERENCE] ~= true
    state.preferences[EDIT_MODE_MOVED_PREFERENCE] = true
    state.preferences[EDIT_MODE_MOVED_KEY_PREFERENCE] = moverKey
    Touch()
    return true, changed
end

function Tour:GetCursor(stageId)
    SyncLiveState()
    stageId = tostring(stageId or state.currentStageId or DEFAULT_STAGE)
    local cursor = state.cursors[stageId]
    return type(cursor) == "table" and cursor or nil
end

function Tour:SetCursor(stageId, cursor)
    SyncLiveState()
    if state.status ~= "active" then return false end
    stageId = tostring(stageId or state.currentStageId or DEFAULT_STAGE)
    if stageId == "" then return false end
    state.cursors[stageId] = CopyCursor(cursor)
    Touch()
    return true
end

function Tour:RecordControl(stageId, controlId, result, metadata)
    SyncLiveState()
    if state.status ~= "active" then return false end
    stageId, controlId = tostring(stageId or ""), tostring(controlId or "")
    local code = ResultCode(result)
    if stageId == "" or controlId == "" or not code then return false end
    local results = state.controlResults[stageId]
    if type(results) ~= "table" then
        results = {}
        state.controlResults[stageId] = results
    end
    results[controlId] = code
    if code == "s" then
        metadata = type(metadata) == "table" and metadata or {}
        state.skippedControls[controlId] = {
            stageId = stageId,
            pageKey = type(metadata.pageKey) == "string" and metadata.pageKey or nil,
            sectionId = type(metadata.sectionId) == "string" and metadata.sectionId or nil,
            label = tostring(metadata.label or controlId),
            help = tostring(metadata.help or ""),
        }
    else
        state.skippedControls[controlId] = nil
    end
    Touch()
    return true
end

function Tour:RecordSection(stageId, sectionId, result, metadata)
    SyncLiveState()
    if state.status ~= "active" then return false end
    stageId, sectionId = tostring(stageId or ""), tostring(sectionId or "")
    local code = ResultCode(result)
    if stageId == "" or sectionId == "" or not code then return false end
    local key = stageId .. "\031" .. sectionId
    state.sectionResults[key] = code
    metadata = type(metadata) == "table" and metadata or {}
    state.sectionMetadata[key] = {
        stageId = stageId,
        sectionId = sectionId,
        pageKey = type(metadata.pageKey) == "string" and metadata.pageKey or nil,
        label = tostring(metadata.label or sectionId),
    }
    Touch()
    return true
end

function Tour:RecordStage(stageId, result)
    SyncLiveState()
    if state.status ~= "active" then return false end
    stageId = tostring(stageId or "")
    local code = ResultCode(result)
    if stageId == "" or not code then return false end
    state.stageResults[stageId] = code
    Touch()
    return true
end

function Tour:GetSummary()
    SyncLiveState()
    local summary = {
        reviewedStages = 0,
        keptStages = 0,
        skippedStages = 0,
        reviewedSections = 0,
        keptSections = 0,
        skippedSections = 0,
        reviewedControls = 0,
        keptControls = 0,
        skippedControls = 0,
    }
    local function Count(code, reviewedKey, keptKey, skippedKey)
        if code == "r" then summary[reviewedKey] = summary[reviewedKey] + 1
        elseif code == "k" then summary[keptKey] = summary[keptKey] + 1
        elseif code == "s" then summary[skippedKey] = summary[skippedKey] + 1 end
    end
    for _, code in pairs(state.stageResults) do Count(code, "reviewedStages", "keptStages", "skippedStages") end
    for _, code in pairs(state.sectionResults) do Count(code, "reviewedSections", "keptSections", "skippedSections") end
    for _, controls in pairs(state.controlResults) do
        if type(controls) == "table" then
            for _, code in pairs(controls) do Count(code, "reviewedControls", "keptControls", "skippedControls") end
        end
    end
    return summary
end

function Tour:Complete()
    SyncLiveState()
    state.status = "completed"
    state.completedAt = Now()
    state.restorePoint = nil
    state.restorePointCreatedAt = nil
    state.restorePointUsedAt = nil
    Touch()
    return true
end

function Tour:Dismiss()
    SyncLiveState()
    state.status = "dismissed"
    state.dismissedAt = Now()
    Touch()
    return true
end

function Tour:Reset()
    SyncLiveState()
    state = NewState()
    globalDB.global.guidedTour6 = state
    return true
end
