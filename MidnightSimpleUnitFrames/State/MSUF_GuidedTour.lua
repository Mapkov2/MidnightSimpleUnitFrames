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

local state = globalDB.global.guidedTour6
if type(state) ~= "table" or state.revision ~= REVISION then
    state = NewState()
    globalDB.global.guidedTour6 = state
else
    state.schema = 1
    if not VALID_STATUS[state.status] then state.status = "inactive" end
    if type(state.currentStageId) ~= "string" or state.currentStageId == "" then
        state.currentStageId = DEFAULT_STAGE
    end
    state.currentStageIndex = math.max(1, tonumber(state.currentStageIndex) or 1)
    state.cursors = type(state.cursors) == "table" and state.cursors or {}
    state.stageResults = type(state.stageResults) == "table" and state.stageResults or {}
    state.sectionResults = type(state.sectionResults) == "table" and state.sectionResults or {}
    state.sectionMetadata = type(state.sectionMetadata) == "table" and state.sectionMetadata or {}
    state.controlResults = type(state.controlResults) == "table" and state.controlResults or {}
    state.skippedControls = type(state.skippedControls) == "table" and state.skippedControls or {}
    state.preferences = type(state.preferences) == "table" and state.preferences or {}
end

local Tour = MSUF.GuidedTour6 or {}
MSUF.GuidedTour6 = Tour
_G.MSUF_GuidedTour6 = Tour

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
    return state
end

function Tour:IsActive()
    return state.status == "active"
end

function Tour:Start(profileName, firstStageId, restorePoint)
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
    return type(state.restorePoint) == "table" and state.restorePoint or nil
end

function Tour:MarkRestorePointUsed(used)
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
    if state.status ~= "active" then return false end
    state.resumedAt = Now()
    Touch()
    return true
end

function Tour:SetStage(stageId, stageIndex)
    if state.status ~= "active" or type(stageId) ~= "string" or stageId == "" then return false end
    state.currentStageId = stageId
    state.currentStageIndex = math.max(1, tonumber(stageIndex) or state.currentStageIndex or 1)
    Touch()
    return true
end

function Tour:GetPreference(key)
    key = type(key) == "string" and key or ""
    if key == "" then return nil end
    return state.preferences[key]
end

function Tour:SetPreference(key, value)
    if state.status ~= "active" or type(key) ~= "string" or key == "" then return false end
    local valueType = type(value)
    if value ~= nil and valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then return false end
    state.preferences[key] = value
    Touch()
    return true
end

function Tour:IsEditModePlacementComplete()
    return state.preferences[EDIT_MODE_MOVED_PREFERENCE] == true
end

function Tour:MarkEditModePlacementComplete(moverKey)
    if state.status ~= "active" or state.currentStageId ~= EDIT_MODE_STAGE then return false end
    local anchor = state.preferences[COOLDOWN_ANCHOR_PREFERENCE]
    if anchor ~= "cooldown" and anchor ~= "independent" then return false end
    local changed = state.preferences[EDIT_MODE_MOVED_PREFERENCE] ~= true
    state.preferences[EDIT_MODE_MOVED_PREFERENCE] = true
    state.preferences[EDIT_MODE_MOVED_KEY_PREFERENCE] = tostring(moverKey or "")
    Touch()
    return true, changed
end

function Tour:GetCursor(stageId)
    stageId = tostring(stageId or state.currentStageId or DEFAULT_STAGE)
    local cursor = state.cursors[stageId]
    return type(cursor) == "table" and cursor or nil
end

function Tour:SetCursor(stageId, cursor)
    if state.status ~= "active" then return false end
    stageId = tostring(stageId or state.currentStageId or DEFAULT_STAGE)
    if stageId == "" then return false end
    state.cursors[stageId] = CopyCursor(cursor)
    Touch()
    return true
end

function Tour:RecordControl(stageId, controlId, result, metadata)
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
    if state.status ~= "active" then return false end
    stageId = tostring(stageId or "")
    local code = ResultCode(result)
    if stageId == "" or not code then return false end
    state.stageResults[stageId] = code
    Touch()
    return true
end

function Tour:GetSummary()
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
    state.status = "completed"
    state.completedAt = Now()
    state.restorePoint = nil
    state.restorePointCreatedAt = nil
    state.restorePointUsedAt = nil
    Touch()
    return true
end

function Tour:Dismiss()
    state.status = "dismissed"
    state.dismissedAt = Now()
    Touch()
    return true
end

function Tour:Reset()
    state = NewState()
    globalDB.global.guidedTour6 = state
    return true
end
