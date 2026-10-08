--- MidnightSimpleUnitFrames 6.0 first-load lifecycle.
---
--- This file loads before any code that normalizes the SavedVariables and settles
--- on the addon's ADDON_LOADED, the first moment they exist. Raw SavedVariable
--- presence is the only reliable way to distinguish a clean install from an
--- upgrade without touching the active profile.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type, tostring, pairs = type, tostring, pairs
local time = time

local REVISION = 1
local CURRENT_PROFILE_SCHEMA = 600
local ProfilePolicy = MSUF.ProfilePolicy or {}
MSUF.ProfilePolicy = ProfilePolicy
ProfilePolicy.CurrentSchema = CURRENT_PROFILE_SCHEMA

function ProfilePolicy.AcceptsProfile(profile)
    return type(profile) == "table"
        and tonumber(profile._msufProfileSchema) == CURRENT_PROFILE_SCHEMA
end

local function HasCurrentSnapshotData(snapshot)
    return type(snapshot) == "table"
        and tonumber(snapshot.schema) == CURRENT_PROFILE_SCHEMA
        and type(snapshot.kind) == "string"
        and type(snapshot.payload) == "table"
end

function ProfilePolicy.AcceptsSnapshot(snapshot)
    return HasCurrentSnapshotData(snapshot)
        and snapshot.addon == "MSUF"
        and tonumber(snapshot.fmt) == 2
end

function ProfilePolicy.SelectSupportedDecodedProfile(decoded)
    if ProfilePolicy.AcceptsProfile(decoded) or ProfilePolicy.AcceptsSnapshot(decoded) then
        return decoded
    end
    -- Wago's portable schema-1 envelope was introduced during the 6.x line.
    -- Prefer its lossless schema-600 snapshot when present, while retaining
    -- portable-only 6.x exports. An invalid embedded snapshot fails closed.
    if type(decoded) == "table"
        and decoded.addon == "MSUF"
        and tonumber(decoded.fmt) == 2
        and tonumber(decoded.schema) == 1
        and type(decoded.kind) == "string"
        and type(decoded.payload) == "table" then
        local full = decoded.msuf6
        if full == nil then return decoded end
        if HasCurrentSnapshotData(full) then
            return {
                addon = "MSUF",
                fmt = 2,
                schema = full.schema,
                kind = full.kind,
                profile = type(full.profile) == "string" and full.profile or decoded.profile,
                payload = full.payload,
            }
        end
    end
    return nil
end
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

-- The client loads SavedVariables after every Lua file of the addon ran and
-- right before it fires ADDON_LOADED for the addon, so MSUF_DB and
-- MSUF_GlobalDB are nil here even on an upgrade. The install evidence, the
-- pre-6 archive and the lifecycle state settle on ADDON_LOADED, before any
-- PLAYER_LOGIN work creates or normalizes a profile. MSUF 5.71 and older use
-- the same MSUF_DB/MSUF_GlobalDB names as 6.0, so their untouched shape is the
-- authoritative upgrade/profile signal.
--
-- Until then the early State files share one MSUF_GlobalDB root. A clean
-- install keeps it; on an upgrade the client replaces it with the saved one.
local globalDB = rawget(_G, "MSUF_GlobalDB")
-- What already existed when this file ran. In game that is nothing; a test
-- harness that seeds the SavedVariables first counts as saved data.
local preloadGlobalDB, preloadProfileDB = globalDB, rawget(_G, "MSUF_DB")
local placeholderGlobalDB
if type(globalDB) ~= "table" then
    globalDB = {}
    placeholderGlobalDB = globalDB
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then
    globalDB.global = {}
end

local rawProfileDB, rawGlobalDB, hadSavedState
-- MSUF_DB as State/MSUF_Defaults.lua created it while the addon loaded (a
-- file read a setting before the SavedVariables existed). On a clean install
-- the client leaves it in place, so it is no evidence of saved data.
local sessionProfileDB

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
    --- Character bindings live in MSUF_GlobalDB.char (State/MSUF_Profiles.lua).
    local chars = type(rawGlobalDB) == "table" and rawGlobalDB.char or nil
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

local installEvidence, state
ProfilePolicy.ArchivedThisLoad = 0
local settled, savedVariablesLoaded = false, false

function ProfilePolicy.NoteSessionProfileDB(profile)
    if not savedVariablesLoaded then sessionProfileDB = profile end
end

-- Schema 600 is the profile contract for every MSUF 6.x release. Archive old
-- or unversioned profiles before Defaults/Profiles can normalize them.
local function EnsurePre6Archive()
    if type(globalDB.ignoredPre6Profiles) ~= "table" then
        globalDB.ignoredPre6Profiles = {}
    end
    return globalDB.ignoredPre6Profiles
end

local function StoreArchivedProfile(name, profile)
    local archive = EnsurePre6Archive()
    local key, suffix = name, 1
    while archive[key] ~= nil and archive[key] ~= profile do
        suffix = suffix + 1
        key = name .. " (" .. suffix .. ")"
    end
    archive[key] = profile
end

local function ArchivePre6Profiles()
    local retiredNames
    local archivedCount = 0
    if type(globalDB.profiles) == "table" then
        for name, profile in pairs(globalDB.profiles) do
            if not ProfilePolicy.AcceptsProfile(profile) then
                StoreArchivedProfile(name, profile)
                globalDB.profiles[name] = nil
                retiredNames = retiredNames or {}
                retiredNames[name] = true
                archivedCount = archivedCount + 1
            end
        end
    end
    if rawProfileDB ~= nil and not ProfilePolicy.AcceptsProfile(rawProfileDB) then
        StoreArchivedProfile("__standalone", rawProfileDB)
        _G.MSUF_DB = nil
        archivedCount = archivedCount + 1
    end
    if retiredNames then
        if type(globalDB.char) == "table" then
            for _, binding in pairs(globalDB.char) do
                if type(binding) == "table" then
                    if retiredNames[binding.activeProfile] then binding.activeProfile = nil end
                    if type(binding.specProfileMap) == "table" then
                        for specID, profileName in pairs(binding.specProfileMap) do
                            if retiredNames[profileName] then binding.specProfileMap[specID] = nil end
                        end
                    end
                end
            end
        end
        if retiredNames[globalDB.global.defaultProfileForNewChars] then
            globalDB.global.defaultProfileForNewChars = nil
        end
        -- An archived profile is no sync member any more; a stale name would
        -- later claim a module a new profile of that name joins.
        local syncGroups = globalDB.global.profileSyncGroups
        if type(syncGroups) == "table" then
            for _, group in pairs(syncGroups) do
                if type(group) == "table" and type(group.members) == "table" then
                    for name in pairs(retiredNames) do group.members[name] = nil end
                end
            end
        end
    end
    ProfilePolicy.ArchivedThisLoad = archivedCount
end

local function Now()
    return type(time) == "function" and time() or 0
end

--- One shared accessor, MSUF.GetAddonVersion from Game/Shared/Initialize.lua:
--- the version is resolved once from the TOC this client loaded, so no consumer
--- asks a TOC again.
local function AddonVersion()
    local getVersion = MSUF.GetAddonVersion
    local version = type(getVersion) == "function" and getVersion() or nil
    if type(version) == "string" and version ~= "" then return version end
    return "6.0"
end

local function SettleLifecycleState()
    state = globalDB.global.firstLoad6
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
end

-- Settles on the addon's ADDON_LOADED in game (loadedNow). A caller that asks
-- for the lifecycle before that event (a harness without it) gets a lifecycle
-- from what existed when this file ran; the event, when it comes, settles again
-- from the SavedVariables.
local function SettleSavedVariables(loadedNow)
    if loadedNow then
        if savedVariablesLoaded then return end
        savedVariablesLoaded = true
        rawProfileDB = rawget(_G, "MSUF_DB")
        rawGlobalDB = rawget(_G, "MSUF_GlobalDB")
        -- Still the load-time tables: the client found nothing to load.
        if rawProfileDB == sessionProfileDB then rawProfileDB = nil end
        if rawGlobalDB == placeholderGlobalDB then rawGlobalDB = nil end
        sessionProfileDB = nil
    else
        if settled then return end
        rawProfileDB, rawGlobalDB = preloadProfileDB, preloadGlobalDB
    end
    settled = true
    hadSavedState = rawProfileDB ~= nil or rawGlobalDB ~= nil
    installEvidence = DetectInstallEvidence()
    local live = rawget(_G, "MSUF_GlobalDB")
    if type(live) ~= "table" then
        live = globalDB
        _G.MSUF_GlobalDB = live
    end
    globalDB = live
    if type(globalDB.global) ~= "table" then
        globalDB.global = {}
    end
    ArchivePre6Profiles()
    SettleLifecycleState()
end

if type(_G.CreateFrame) == "function" then
    local loader = _G.CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, loaded)
        if loaded ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        SettleSavedVariables(true)
    end)
end

local FirstLoad = MSUF.FirstLoad6 or {}
MSUF.FirstLoad6 = FirstLoad

-- Session-only guard on top of the persisted status. It keeps the scene hidden
-- for the rest of this session even if the persisted status is restored to
-- "pending" (for example by undo of a first-load action).
FirstLoad.deferredThisSession = false

-- Some profile/bootstrap paths can repair or replace the SavedVariables root
-- after this early module has loaded. Always follow the currently exported
-- root before reading or mutating onboarding state, otherwise the menu can
-- render a stale `pending` table even though the saved state is completed.
local function SyncLiveState()
    if not settled then SettleSavedVariables() end
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

-- Clients that lose their SavedVariables between sessions (the WoW Forever
-- beta) start every login as a clean install, so this one-time scene would
-- never retire there. `/msuf firstload` is the only path that writes a debug
-- install reason, and it keeps the preview available on those clients.
local function ClientShowsOnboarding()
    local client = MSUF.Client
    return type(client) ~= "table" or client.SupportsOnboardingScenes ~= false
end

function FirstLoad:ShouldShowDashboard()
    SyncLiveState()
    if self.deferredThisSession then
        return false
    end
    if not ClientShowsOnboarding()
        and state.installReason ~= "debug_forced_fresh"
        and state.installReason ~= "debug_forced_upgrade" then
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

-- MSUF's own first run still owns the screen: the one-time welcome would show,
-- or the Quick Setup it started is still running (it resumes after a reload).
-- Unlike ShouldShowDashboard this never writes, because Transition asks it in
-- the middle of a change. Clients without onboarding scenes never report it.
local function FirstRunPending()
    if FirstLoad.deferredThisSession then return false end
    if not ClientShowsOnboarding()
        and state.installReason ~= "debug_forced_fresh"
        and state.installReason ~= "debug_forced_upgrade" then
        return false
    end
    return state.status == "pending" or (state.status == "active" and state.step == "guided_tour")
end

--- The optional MSUF Suite reads this at login and holds its own installer
--- while it is true; SettleSuiteHandOff below calls the installer afterwards.
function FirstLoad:IsFirstRunPending()
    SyncLiveState()
    return FirstRunPending() or self.suiteHandOffOwed == true
end

local function ShowSuiteInstaller()
    MSUF.SuiteLink.MaybeShowInstaller()
end

-- Leaving the pending first run (completed, dismissed, later) hands off to the
-- Suite installer once per session, one frame later so a Suite error cannot
-- abort the MSUF action that got here. Another active step, the profile import
-- route, keeps the hand-off owed until that route completes.
local function SettleSuiteHandOff()
    if FirstRunPending() or state.status == "active" or state.status == "pending" then
        FirstLoad.suiteHandOffOwed = true
        return
    end
    FirstLoad.suiteHandOffOwed = nil
    if FirstLoad.suiteHandedOff then return end
    FirstLoad.suiteHandedOff = true
    local timer = _G.C_Timer
    local after = type(timer) == "table" and timer.After or nil
    if type(after) == "function" then after(0, ShowSuiteInstaller) else ShowSuiteInstaller() end
end

local function Transition(status, step)
    SyncLiveState()
    if not VALID_STATUS[status] then
        return false
    end
    local suiteWaits = FirstLoad.suiteHandOffOwed == true or FirstRunPending()
    state.status = status
    if type(step) == "string" and step ~= "" then
        state.step = step
    end
    state.updatedAt = Now()
    if suiteWaits then SettleSuiteHandOff() end
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
    self.suiteHandOffOwed, self.suiteHandedOff = nil, nil
    return true
end
