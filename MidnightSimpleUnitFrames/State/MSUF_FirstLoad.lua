--- MidnightSimpleUnitFrames 6.0 first-load lifecycle.
---
--- This file intentionally loads before any code that normalizes the SavedVariables.
--- Raw SavedVariable presence is the only reliable way to distinguish a clean install
--- from an upgrade without touching the active profile.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type, tostring = type, tostring
local time = time

local REVISION = 1
local CURRENT_PROFILE_SCHEMA = 600
local VALID_STATUS = {
    pending = true,
    active = true,
    later = true,
    completed = true,
    dismissed = true,
}
local TERMINAL_STATUS = {
    completed = true,
    dismissed = true,
}

-- SavedVariables are available before the first addon Lua file runs. Capture
-- their untouched shape before Defaults/Profiles create or migrate anything.
-- MSUF 5.71 and older use the same MSUF_DB/MSUF_GlobalDB names as 6.0, so this
-- is the authoritative upgrade/profile signal.
local rawProfileDB = rawget(_G, "MSUF_DB")
local rawGlobalDB = rawget(_G, "MSUF_GlobalDB")
local hadSavedState = rawProfileDB ~= nil or rawGlobalDB ~= nil

local function TableHasEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

local function FirstProfile(profiles)
    if type(profiles) ~= "table" then return nil end
    for _, profile in pairs(profiles) do
        if type(profile) == "table" then return profile end
    end
end

local function DetectInstallEvidence()
    local profiles = type(rawGlobalDB) == "table" and rawGlobalDB.profiles or nil
    local chars = type(rawGlobalDB) == "table" and rawGlobalDB.chars or nil
    local profile = TableHasEntries(rawProfileDB) and rawProfileDB or FirstProfile(profiles)
    local schema = tonumber(type(profile) == "table" and profile._msufProfileSchema)
    local hasProfile = type(profile) == "table"
    local reason
    if TableHasEntries(profiles) then
        reason = schema and "saved_profiles_schema" or "legacy_saved_profiles"
    elseif TableHasEntries(rawProfileDB) then
        reason = schema and "saved_profile_schema" or "legacy_saved_profile"
    elseif TableHasEntries(chars) then
        reason = "saved_profile_bindings"
    elseif hadSavedState then
        reason = "saved_variables_present"
    else
        reason = "no_saved_variables"
    end
    return {
        reason = reason,
        hadSavedState = hadSavedState,
        hasProfile = hasProfile,
        profileSchema = schema,
        legacyProfile = hasProfile and (schema == nil or schema < CURRENT_PROFILE_SCHEMA) or false,
        rawDB = rawProfileDB ~= nil,
        rawProfiles = TableHasEntries(profiles),
    }
end

local installEvidence = DetectInstallEvidence()

local globalDB = rawget(_G, "MSUF_GlobalDB")
if type(globalDB) ~= "table" then
    globalDB = {}
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then
    globalDB.global = {}
end

local function Now()
    return type(time) == "function" and time() or 0
end

local function AddonVersion()
    local api = _G.C_AddOns
    local value
    if type(api) == "table" and type(api.GetAddOnMetadata) == "function" then
        value = api.GetAddOnMetadata(addonName, "Version")
    elseif type(_G.GetAddOnMetadata) == "function" then
        value = _G.GetAddOnMetadata(addonName, "Version")
    end
    return tostring(value or "6.0")
end

local state = globalDB.global.firstLoad6
if type(state) ~= "table" or state.revision ~= REVISION then
    state = {
        schema = 1,
        revision = REVISION,
        installKind = hadSavedState and "upgrade" or "fresh",
        status = "pending",
        step = "welcome",
        firstSeenVersion = AddonVersion(),
        firstSeenAt = Now(),
        installReason = installEvidence.reason,
        existingProfileDetected = installEvidence.hasProfile,
        legacyProfileDetected = installEvidence.legacyProfile,
        detectedProfileSchema = installEvidence.profileSchema,
    }
    globalDB.global.firstLoad6 = state
else
    state.schema = 1
    state.installKind = state.installKind == "fresh" and "fresh" or "upgrade"
    if not VALID_STATUS[state.status] then
        state.status = "pending"
    end
    -- A stale beta/debug lifecycle must not overrule untouched 5.71-or-older
    -- profile data. Current 6.0 profiles carry schema 600, so this correction
    -- is narrow and cannot turn a real new 6.0 default profile into an upgrade.
    if state.status == "pending" and state.installKind == "fresh" and installEvidence.legacyProfile then
        state.installKind = "upgrade"
        state.installReason = "reclassified_" .. tostring(installEvidence.reason)
        state.existingProfileDetected = true
        state.legacyProfileDetected = true
        state.detectedProfileSchema = installEvidence.profileSchema
    end
    if type(state.step) ~= "string" or state.step == "" then
        state.step = "welcome"
    end
    if type(state.firstSeenVersion) ~= "string" or state.firstSeenVersion == "" then
        state.firstSeenVersion = AddonVersion()
    end
    if type(state.installReason) ~= "string" or state.installReason == "" then
        state.installReason = state.installKind == "upgrade" and installEvidence.reason or "persisted_fresh_install"
    end
    if state.existingProfileDetected == nil and state.installKind == "upgrade" then
        state.existingProfileDetected = installEvidence.hasProfile
    end
    if state.legacyProfileDetected == nil and state.installKind == "upgrade" then
        state.legacyProfileDetected = installEvidence.legacyProfile
    end
    if state.detectedProfileSchema == nil and state.installKind == "upgrade" then
        state.detectedProfileSchema = installEvidence.profileSchema
    end
end

local FirstLoad = MSUF.FirstLoad6 or {}
MSUF.FirstLoad6 = FirstLoad

-- Session-only guard on top of the persisted status. It keeps the scene hidden
-- for the rest of this session even if the persisted status is restored to
-- "pending" (for example by an Assistant undo of a first-load action).
FirstLoad.deferredThisSession = false

-- Some profile/bootstrap paths can repair or replace the SavedVariables root
-- after this early module has loaded. Always follow the currently exported
-- root before reading or mutating onboarding state, otherwise the menu can
-- render a stale `pending` table even though the saved state is completed.
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
    local liveState = globalDB.global.firstLoad6
    if liveState ~= state then
        if type(liveState) == "table" and liveState.revision == REVISION and VALID_STATUS[liveState.status] then
            state = liveState
        else
            globalDB.global.firstLoad6 = state
        end
    end
    return state
end

function FirstLoad:GetState()
    return SyncLiveState()
end

function FirstLoad:GetInstallKind()
    SyncLiveState()
    return state.installKind
end

function FirstLoad:GetDetection()
    SyncLiveState()
    return {
        installKind = state.installKind,
        reason = state.installReason,
        existingProfile = state.existingProfileDetected == true,
        legacyProfile = state.legacyProfileDetected == true,
        profileSchema = state.detectedProfileSchema,
        rawDB = installEvidence.rawDB,
        rawProfiles = installEvidence.rawProfiles,
    }
end

function FirstLoad:IsTerminal()
    SyncLiveState()
    return TERMINAL_STATUS[state.status] == true
end

function FirstLoad:ShouldShowDashboard()
    SyncLiveState()
    if self.deferredThisSession then
        return false
    end
    -- Successful imports persist an independent receipt so the welcome cannot
    -- reappear if an older/stale lifecycle table survived the profile switch.
    -- Fresh installs that already have a named active profile predate that
    -- receipt; treat that explicit setup choice as completed as well. An
    -- explicit debug reset must bypass this recovery, otherwise
    -- `/msuf firstload fresh` immediately completes itself again for the very
    -- imported profile it is supposed to preview.
    local activeProfile = rawget(_G, "MSUF_ActiveProfile")
    local importReceipt = globalDB.global.firstLoad6ProfileImported == true
    local recoveredNamedProfile = state.status == "pending"
        and state.installKind == "fresh"
        and state.installReason ~= "debug_forced_fresh"
        and type(activeProfile) == "string"
        and activeProfile ~= ""
        and activeProfile ~= "Default"
    if importReceipt or recoveredNamedProfile then
        self:CompleteProfileImport(recoveredNamedProfile and "import_recovered" or "import")
    end
    -- Any explicit route choice (guided tour, import, defaults, changelog,
    -- "not now", full settings) moves the status away from "pending" and
    -- retires this one-time welcome scene for good. The normal Dashboard keeps
    -- its own Guided Setup entry point, so nothing is lost permanently.
    return state.status == "pending"
end

-- Fresh players who close the one-time welcome with the default setup still
-- benefit from a clear next step on the normal Dashboard. Keep that cue until
-- they either import a profile or finish Guided Setup; neither path is allowed
-- to revive the welcome scene itself.
function FirstLoad:ShouldHighlightGuidedSetup()
    SyncLiveState()
    if state.installKind ~= "fresh" or state.status ~= "completed" or state.step ~= "defaults" then
        return false
    end
    if globalDB.global.firstLoad6ProfileImported == true then
        return false
    end
    local tour = MSUF and MSUF.GuidedTour6
    local tourState = type(tour) == "table" and type(tour.GetState) == "function" and tour:GetState() or nil
    return not (type(tourState) == "table" and tourState.status == "completed")
end

local function Transition(status, step)
    SyncLiveState()
    if not VALID_STATUS[status] then
        return false
    end
    state.status = status
    if type(step) == "string" and step ~= "" then
        state.step = step
    end
    state.updatedAt = Now()
    return true
end

function FirstLoad:Start(step)
    -- Completion/dismissal closes only the one-time onboarding lifecycle. The
    -- independent Guided Setup controller may still start again from the
    -- normal Dashboard without reviving this welcome scene.
    if self:IsTerminal() then return false, state.status end
    self.deferredThisSession = false
    return Transition("active", step or "personalize")
end

function FirstLoad:DeferForSession(step)
    if self:IsTerminal() then return false, state.status end
    local changed = Transition("later", step or "welcome")
    self.deferredThisSession = true
    return changed
end

function FirstLoad:Complete(step)
    SyncLiveState()
    self.deferredThisSession = false
    state.completedAt = Now()
    return Transition("completed", step or "defaults")
end

-- A player can import from the Profiles page without first choosing the import
-- card on the welcome scene. Treat that successful direct import as the same
-- explicit setup choice, but do not interrupt an unrelated active guided tour.
function FirstLoad:CompleteProfileImport(step)
    SyncLiveState()
    globalDB.global.firstLoad6ProfileImported = true
    if self:IsTerminal() then return false, state.status end
    if state.status ~= "pending" and not (state.status == "active" and state.step == "import") then
        return false, state.status
    end
    return self:Complete(step or "import")
end

function FirstLoad:Dismiss(step)
    SyncLiveState()
    self.deferredThisSession = false
    state.dismissedAt = Now()
    return Transition("dismissed", step or "full_settings")
end

--- Testing/preview helper (`/msuf firstload`): re-arms the one-time welcome
--- scene as if the addon had just been installed, optionally forcing the
--- fresh or upgrade variant. Deliberately bypasses the terminal-status guard.
function FirstLoad:Reset(installKind)
    SyncLiveState()
    if installKind ~= "fresh" and installKind ~= "upgrade" then
        installKind = state.installKind
    end
    state = {
        schema = 1,
        revision = REVISION,
        installKind = installKind == "fresh" and "fresh" or "upgrade",
        status = "pending",
        step = "welcome",
        firstSeenVersion = AddonVersion(),
        firstSeenAt = Now(),
        installReason = installKind == "upgrade" and "debug_forced_upgrade" or "debug_forced_fresh",
        existingProfileDetected = installKind == "upgrade" and installEvidence.hasProfile or false,
        legacyProfileDetected = installKind == "upgrade" and installEvidence.legacyProfile or false,
        detectedProfileSchema = installKind == "upgrade" and installEvidence.profileSchema or nil,
    }
    globalDB.global.firstLoad6 = state
    globalDB.global.firstLoad6ProfileImported = nil
    self.deferredThisSession = false
    return true
end
