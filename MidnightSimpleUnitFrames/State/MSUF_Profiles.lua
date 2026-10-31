-- Profile storage lifecycle, named-profile operations and specialization switching.
--- State/MSUF_Profiles.lua
--- Profile storage, import/export, and active-profile state.
---
--- This file is the cold boundary between SavedVariables and the live addon.
--- It is allowed to copy tables, normalize old schemas, and fan out profile
--- changes to runtime modules, but gameplay event handlers should never call
--- into the expensive import/export paths directly.
---
--- Mental model:
--- * MSUF_GlobalDB.profiles stores named profile tables.
--- * MSUF_GlobalDB.char[charKey] stores the active profile and spec bindings.
--- * MSUF_DB always points at the active profile table for legacy callers.
--- Keep the MSUF_DB table reference stable during imports where possible:
--- several modules cache table references and only invalidate on the explicit
--- post-profile apply hook below.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF
MSUF.Public = MSUF.Public or {}

local Parts = {}
MSUF.ProfilesParts = Parts
local ExportPublic = MSUF.ExportPublic
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "State/MSUF_Profiles.lua")
local GetCharKey, GetPlayerSpecID, IsSpecAutoSwitchEnabled, GetSpecProfile, ApplySpecProfileIfEnabled, InitProfiles

--- Shared coldpath field helpers (State/MSUF_StateHelpers.lua) and the import
--- parser plus compact transport codecs (State/MSUF_ProfileCodec.lua) load
--- before this file. Both are hard dependencies of the normalization and
--- import/export paths below.
local StateHelpers = MSUF.StateHelpers
if type(StateHelpers) ~= "table" then
    error("State/MSUF_StateHelpers.lua must load before State/MSUF_Profiles.lua")
end
local MSUF_PROFILE_IMPORT_LIMITS = MSUF.ProfileIOImportLimits
if type(MSUF_PROFILE_IMPORT_LIMITS) ~= "table" then
    error("State/MSUF_ProfileCodec.lua must load before State/MSUF_Profiles.lua")
end

--- Profile storage owns DB mutation; ProfileRuntime owns the ordered fanout.
--- REQUIRED, in the same spirit as the two errors above: State/MSUF_Defaults.lua
--- is listed unconditionally in the TOC three entries ahead of this file and is
--- the single top-level writer of MSUF_EnsureDB. Every profile create, switch,
--- reset and import below routes its schema repair through it, so a missing
--- export must not degrade into profiles that silently skip normalization.
local MSUF_ENSURE_DB = MSUF.Require("MSUF_EnsureDB", "State/MSUF_Profiles.lua")
local function MSUF_ProfileIO_RunEnsureDB(force, allowPersistedFastPath)
    MSUF_ENSURE_DB(force == true, allowPersistedFastPath == true)
    return true
end

-- Profile imports can enter through Menu2, legacy globals, or the external
-- Wago API. Complete first-load at the shared mutation boundary so every
-- successful path records the same durable lifecycle result.
function MSUF.ProfileIOCompleteFirstLoadImport()
    local firstLoad = MSUF and MSUF.FirstLoad6
    if type(firstLoad) ~= "table" or type(firstLoad.CompleteProfileImport) ~= "function" then
        return false
    end
    local completed = firstLoad.CompleteProfileImport(firstLoad, "import")

    if completed == true then
        local menu = MSUF and MSUF.MSUF2
        if type(menu) == "table" and type(menu.InvalidatePage) == "function" then
            menu.InvalidatePage("home")
        end
    end
    return completed == true
end
local ApplyProfileRuntime = MSUF.ProfileRuntime.Apply
--- Chat lines of the profile commands. The sentence is translated first and
--- formatted after, so a language places the names where it needs them; the
--- coloured "MSUF:" tag is not part of the sentence. Locales/MSUF_Localization.lua
--- loads ahead of State/ in every core TOC; the selected pack fills its table
--- at ADDON_LOADED, before any of these lines can print.
local Translate = MSUF.Translate
local PROFILE_CHAT_TAG = { error = "|cffff0000MSUF:|r ", ok = "|cff00ff00MSUF:|r ", note = "|cffffd700MSUF:|r " }
local function ProfileChatLine(tone, text, ...)
    return PROFILE_CHAT_TAG[tone] .. string.format(Translate(text), ...)
end
local function ProfileChat(tone, text, ...)
    print(ProfileChatLine(tone, text, ...))
end
--- The one profile name rule of MSUF, the Suite and its skin: at most 80
--- bytes (MAX_PROFILE_NAME_BYTES, MSUF_Suite/Core/Database.lua). The Suite
--- cannot follow a longer name, so every entry point that names a new
--- profile refuses it before anything changes. quiet: the caller reports.
local function ProfileNameTooLong(name, quiet)
    if type(name) ~= "string" or #name <= 80 then return false end
    if not quiet then ProfileChat("error", "Profile names can be at most %d bytes long.", 80) end
    return true
end
local Variants, ProfileSync = MSUF.ProfileVariants, MSUF.ProfileSync
local function PrepareProfileMutation(rebindOnly)
    local beforeMutation = MSUF.ProfileRuntime.BeforeMutation
    if beforeMutation and not rebindOnly then beforeMutation() end
    if Variants then Variants.Restore() end
end
local function BeforeProfileSwitch()
    --- Sync rides on top of a profile change: a flush that cannot run is
    --- reported and the change goes ahead. The profile itself is never at
    --- risk; only the propagation to the other members is skipped.
    if ProfileSync then
        local ok,why=ProfileSync.Flush()
        if not ok then ProfileSync.Report("Profile sync skipped (%s).", why) end
    end
    PrepareProfileMutation()
    if Variants then Variants.SetManual(nil) end
    return true
end
--- Profile lifecycle API. These globals are used by Menu2, menu actions,
--- slash handlers, and legacy callers, so the public surface stays global even
--- though the implementation is isolated in this State module.
function MSUF.PublicGlobals.MSUF_GetCharKey()
    -- A client without realms may report no realm name. Coerce it to "" so the
    -- key stays stable and profile bootstrap never concatenates nil.
    local realm = GetRealmName()
    if type(realm) ~= "string" then realm = "" end
    return UnitName("player") .. "-" .. realm
end
ExportPublic("MSUF_GetCharKey", MSUF.PublicGlobals.MSUF_GetCharKey)
local function MSUF_ProfileIO_EnsureProfileRoots()
    if type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.profiles) ~= "table" then
        MSUF_GlobalDB.profiles = {}
    end
    if type(MSUF_GlobalDB.char) ~= "table" then
        MSUF_GlobalDB.char = {}
    end
    return MSUF_GlobalDB.profiles, MSUF_GlobalDB.char
end
--- Account-wide preferences that must survive a profile switch live beside the
--- other `MSUF_GlobalDB.global` state (first-load, guided tour). Keeping this
--- out of the profile tables is deliberate: switching, resetting, or importing
--- a profile must never rewrite which profile future characters start on.
local function MSUF_ProfileIO_EnsureGlobalMeta()
    if type(MSUF_GlobalDB) ~= "table" then
        MSUF_GlobalDB = {}
    end
    if type(MSUF_GlobalDB.global) ~= "table" then
        MSUF_GlobalDB.global = {}
    end
    return MSUF_GlobalDB.global
end
--- Starting profile for characters that have never picked one. `nil` keeps the
--- historical behaviour (new characters land on "Default").
function MSUF_GetDefaultProfileForNewCharacters()
    local name = MSUF_ProfileIO_EnsureGlobalMeta().defaultProfileForNewChars
    if type(name) ~= "string" or name == "" then return nil end
    return name
end
function MSUF_SetDefaultProfileForNewCharacters(name)
    --- Ensure the profile roots first: both helpers rebuild `MSUF_GlobalDB`
    --- when it is missing, and capturing `meta` before that could hand back a
    --- table that is about to be replaced.
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local meta = MSUF_ProfileIO_EnsureGlobalMeta()
    --- "None" is the shared dropdown sentinel for "no selection" (same contract
    --- as MSUF_SetSpecProfile), so it clears unless a real profile owns the name.
    if type(name) ~= "string" or name == ""
        or (name == "None" and type(profiles["None"]) ~= "table") then
        meta.defaultProfileForNewChars = nil
        return true
    end
    if type(profiles[name]) ~= "table" then
        ProfileChat("error", "Unknown profile: %s", tostring(name))
        return false, "unknown profile"
    end
    meta.defaultProfileForNewChars = name
    return true
end
--- One profile's shape is owned by State/MSUF_ProfileNormalize.lua (loaded
--- right before this file): menu defaults, the bounded deep copy and the
--- translator to the current schema.
local Normalize = MSUF.ProfileNormalize
if type(Normalize) ~= "table" then
    error("State/MSUF_ProfileNormalize.lua must load before State/MSUF_Profiles.lua")
end
local MSUF_ProfileIO_EnsureProfileMenuDefaults = Normalize.EnsureProfileMenuDefaults
local MSUF_ProfileIO_TranslateProfileToCurrent = Normalize.TranslateProfileToCurrent
local MSUF_ProfileIO_TranslateProfilesToCurrent = Normalize.TranslateProfilesToCurrent
local MSUF_ProfileIO_NotifySuiteProfileChanged
function MSUF.PublicGlobals.MSUF_InitProfiles(startup)
    if Variants and Variants.IsRecording() then return end
    -- A rebind to a different profile passes BeforeProfileSwitch below.
    PrepareProfileMutation(true)
    local previousActive = type(MSUF_ActiveProfile) == "string" and MSUF_ActiveProfile or nil
    local previousDB = type(MSUF_DB) == "table" and MSUF_DB or nil
    local legacyDB = startup and startup.legacyDB or MSUF_DB
    local hadEstablishedOwner = previousActive ~= nil and previousActive ~= "" and previousDB ~= nil
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    GetCharKey = GetCharKey or MSUF.Require("MSUF_GetCharKey", "State/MSUF_Profiles.lua")
    local charKey = GetCharKey()
    local char = type(chars[charKey]) == "table" and chars[charKey] or {}
    chars[charKey] = char
    local active = char.activeProfile
    -- Suite starts after MSUF has bound this character. Preserve whether this
    -- login began without a choice so Suite can apply its installed profile.
    if _G.MSUF_ProfileWasUnboundAtLogin == nil then
        _G.MSUF_ProfileWasUnboundAtLogin = type(active) ~= "string" or active == ""
    end
    if type(active) ~= "string" or active == "" then
        active = nil
    end
    if not next(profiles) then
        local base = legacyDB or {}
        profiles["Default"] = CopyTable(type(base) == "table" and base or {})
        if not active then
            active = "Default"
        end
    end
    --- Older builds stored the pickers' unassigned row as the name "None".
    --- MSUF_SetSpecProfile never stored "None" there, so each character's
    --- spec map clears it once (specProfileMapVersion 1); an assignment to a
    --- real "None" profile made after that stays. The new-character choice
    --- could name a real "None" profile: it is cleared only without one.
    for _, entry in pairs(chars) do
        if type(entry) == "table" and entry.specProfileMapVersion ~= 1 then
            local map = entry.specProfileMap
            if type(map) == "table" then
                for slot, mapped in pairs(map) do
                    if mapped == "None" then map[slot] = nil end
                end
            end
            entry.specProfileMapVersion = 1
        end
    end
    local meta = MSUF_ProfileIO_EnsureGlobalMeta()
    if meta.defaultProfileForNewChars == "None" and type(profiles.None) ~= "table" then
        meta.defaultProfileForNewChars = nil
    end
    local startupName, startupSource = MSUF.ResolveStartupProfile(MSUF_GlobalDB, legacyDB, charKey)
    active = startupName
    if startup and startup.profile then
        profiles[active] = startup.profile
    elseif type(profiles[active]) ~= "table" then
        profiles[active] = CopyTable(startupSource or {})
    end
    if hadEstablishedOwner and (previousActive~=active or previousDB~=profiles[active]) then
        local ok,why=BeforeProfileSwitch()
        if not ok then return false,why end
    end
    if MSUF_ProfileIO_TranslateProfilesToCurrent then
        MSUF_ProfileIO_TranslateProfilesToCurrent(profiles, "init")
    end
    local boundProfile = profiles[active]
    if MSUF.ProfileMigrations then
        MSUF.ProfileMigrations.ApplyStoredProfiles(profiles)
        boundProfile = MSUF.ProfileMigrations.PrepareBinding(boundProfile)
    end
    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = boundProfile
    if MSUF.Castbars then MSUF.Castbars.Config.Invalidate() end
    MSUF.PublicGlobals.MSUF_GF_InvalidateConfCache()
    --- After DB swap: seed missing defaults so per-unit conf tables exist.
    --- Without this, CreateSimpleUnitFrame sees conf=nil/{} for pet/targettarget
    --- when the profile was saved from an older version missing those keys,
    --- and UpdateSimpleUnitFrame defaults showPowerText=true since conf.showPower is nil.
    --- The Defaults module persists its completed repair revision on the
    --- profile. A non-forced ensure still repairs a new/legacy profile, while
    --- avoiding a second complete pass when this exact profile was already
    --- repaired earlier in the startup chain.
    MSUF_ProfileIO_RunEnsureDB(false, true)
    MSUF.DefaultsSchema.CaptureRollbackBackup(MSUF_GlobalDB)
    MSUF.NumberFormat.Refresh()
    if MSUF.MinimapButton then MSUF.MinimapButton.RefreshProfileBinding() end
    if not startup then
        if MSUF.MenuSkin then MSUF.MenuSkin.Refresh() end
        if Variants then Variants.ResolveCurrent() end
        if ProfileSync then ProfileSync.Activate()
            ProfileSync.RefreshEvents() end
    end
    if hadEstablishedOwner and (previousActive ~= active or previousDB ~= MSUF_DB) then
        ApplyProfileRuntime("PROFILE_INIT_REBIND", false)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_INIT_REBIND", active)
    end
 end
ExportPublic("MSUF_InitProfiles", MSUF.PublicGlobals.MSUF_InitProfiles)
function MSUF.RestorePre70ProfileBackup()
    if Variants and not Variants.CanMutateProfile() then return false end
    BeforeProfileSwitch()
    local ok, legacy = MSUF.DefaultsSchema.RestoreRollbackBackup(MSUF_GlobalDB)
    if not ok then return false end
    MSUF_DB, MSUF_ActiveProfile = nil, nil
    MSUF.PublicGlobals.MSUF_InitProfiles({ legacyDB = legacy })
    if Variants then Variants.ResolveCurrent() end
    if ProfileSync then ProfileSync.Activate()
        ProfileSync.RefreshEvents() end
    ApplyProfileRuntime("PROFILE_BACKUP_RESTORE", false)
    MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_BACKUP_RESTORE", MSUF_ActiveProfile)
    return true
end
local function MSUF_ProfileIO_NotifySuiteLifecycle(kind, source, target)
    return MSUF.SuiteLink.NotifyProfileLifecycle(kind, source, target)
end
function MSUF_CreateProfile(name)
    if type(name) ~= "string" or not name:find("%S") or name:find("[%z\1-\31]") then
        return false, "invalid profile name"
    end
    if ProfileNameTooLong(name) then return false, "profile name too long" end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if profiles[name] then
        ProfileChat("error", "Profile '%s' already exists.", name)
        return false, "profile already exists"
    end
    local createFactoryProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
        or MSUF.PublicGlobals.MSUF_CreateFactoryDefaultProfile
    local profile = createFactoryProfile()
    if type(profile) ~= "table" then
        ProfileChat("error", "Factory defaults are not available; profile was not created.")
        return false, "factory defaults unavailable"
    end
    profiles[name] = profile
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[name], {
            source = "profile_create",
            trustNormalizationMarker = true,
        })
    end
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profiles[name])
    local accepted, refusal = MSUF_ProfileIO_NotifySuiteLifecycle("create", name)
    if accepted == false then
        profiles[name] = nil
        return false, refusal
    end
    ProfileChat("ok", "Created new profile '%s'.", name)
    return true
 end
-- Profile mutations may cross combat for the core's existing deferred
-- runtime-apply path. Suite lifecycle notifications remain out of combat: one
-- raised in combat is kept (the latest wins, it names the profile active now)
-- and delivered when combat ends instead of being dropped.
MSUF_ProfileIO_NotifySuiteProfileChanged = (function()
    local pendingReason, pendingName, Notify
    local function FlushPending()
        local reason, name = pendingReason, pendingName
        if reason == nil then return end
        pendingReason, pendingName = nil, nil
        Notify(reason, name)
    end
    Notify = function(reason, name)
        if MSUF.Util.InCombat() then
            pendingReason, pendingName = reason, name
            MSUF.EventBus:Register("PLAYER_REGEN_ENABLED", "MSUF_PROFILES_SUITE_NOTIFY", FlushPending, nil, true)
            return false
        end
        MSUF.SuiteLink.NotifyProfileChanged(name, reason)
        return true
    end
    return Notify
end)()
function MSUF_SwitchProfile(name)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or type(profiles[name]) ~= "table" then
        ProfileChat("error", "Unknown profile: %s", tostring(name))
        return false, "unknown profile"
    end
    local prepared,why=BeforeProfileSwitch()
    if not prepared then return false,why end
    GetCharKey = GetCharKey or MSUF.Require("MSUF_GetCharKey", "State/MSUF_Profiles.lua")
    local charKey = GetCharKey()
    local char = type(chars[charKey]) == "table" and chars[charKey] or {}
    chars[charKey] = char
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[name], {
            source = "profile_switch",
            trustNormalizationMarker = true,
        })
    end
    local boundProfile = profiles[name]
    if MSUF.ProfileMigrations then boundProfile = MSUF.ProfileMigrations.PrepareBinding(boundProfile) end
    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = boundProfile
    if MSUF.Castbars then MSUF.Castbars.Config.Invalidate() end
    MSUF.PublicGlobals.MSUF_GF_InvalidateConfCache()
    --- Compiled unit-frame configs are rebuilt by the runtime apply below
    --- (MSUF_UFCore_NotifyConfigChanged in State/MSUF_ProfileRuntime.lua).
    --- Stored profiles carry the Defaults completion revision. Imports and
    --- resets clear/bypass it, so a valid profile can switch without paying a
    --- second broad default-fill pass while stale/malformed tables still repair.
    MSUF_ProfileIO_RunEnsureDB(false, true)
    ApplyProfileRuntime("PROFILE_SWITCH", false)
    MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_SWITCH", name)
    ProfileChat("ok", "Switched to profile '%s'.", name)
    return true
 end
local function MSUF_ResetProfile(name)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    name = name or MSUF_ActiveProfile
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or not profiles[name] then return false, "unknown profile" end
    if name == MSUF_ActiveProfile then local ok,why=BeforeProfileSwitch()
        if not ok then return false,why end end
    if name == MSUF_ActiveProfile and MSUF.ProfileWorkbench then
        local ok, why = MSUF.ProfileWorkbench.Checkpoint("Before resetting settings", true)
        if not ok then return false, why end
    end
    if name ~= MSUF_ActiveProfile then
        --- A stored profile needs its schema stamp (an unstamped table is
        --- archived as pre-6.0 at the next login), so it is seeded the way
        --- MSUF_CreateProfile seeds one; the active one is seeded by EnsureDB.
        local createFactoryProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
            or MSUF.PublicGlobals.MSUF_CreateFactoryDefaultProfile
        local profile = type(createFactoryProfile) == "function" and createFactoryProfile() or nil
        if type(profile) ~= "table" then
            ProfileChat("error", "Factory defaults are not available; profile was not reset.")
            return false, "factory defaults unavailable"
        end
        profiles[name] = profile
        MSUF_ProfileIO_TranslateProfileToCurrent(profile, { source = "profile_reset", trustNormalizationMarker = true })
        MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    else
        profiles[name] = {}
    end
    if name == MSUF_ActiveProfile then
        MSUF_DB = profiles[name]
        if MSUF.Castbars then MSUF.Castbars.Config.Invalidate() end
        MSUF.PublicGlobals.MSUF_GF_InvalidateConfCache()
        MSUF_ProfileIO_RunEnsureDB(true)
        --- The reset belongs to this profile only: sync members keep their
        --- settings and receive just the edits made after it.
        if ProfileSync then ProfileSync.Rebase() end
        ApplyProfileRuntime("PROFILE_RESET", false)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_RESET", name)
    end
    MSUF_ProfileIO_NotifySuiteLifecycle("reset", name)
    ProfileChat("note", "Profile '%s' reset to defaults.", name)
    return true
 end
--- quiet: the caller reports (MSUF_DeleteProfiles prints one summary line).
local function DeleteProfile(name, quiet)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    name = name or MSUF_ActiveProfile
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or not profiles[name] then return false, "unknown profile" end
    if name == "Default" then
        ProfileChat("error", "You cannot delete the 'Default' profile. Use Reset instead.")
        return false, "default profile is protected"
    end
    --- The survivor every affected character moves to must not depend on
    --- `pairs()` order: "Default" when it exists, else the alphabetically first
    --- string-keyed profile, the same rule MSUF_ProfileIO_FallbackProfileTable
    --- applies to repairs.
    local fallbackName
    if type(profiles["Default"]) == "table" then
        fallbackName = "Default"
    else
        for profileName, tbl in pairs(profiles) do
            if profileName ~= name and type(profileName) == "string" and profileName ~= ""
                and type(tbl) == "table"
                and (fallbackName == nil or profileName < fallbackName) then
                fallbackName = profileName
            end
        end
    end
    if not fallbackName then
        ProfileChat("error", "Cannot delete the last remaining profile.")
        return false, "cannot delete last profile"
    end
    if MSUF_ActiveProfile == name then local ok,why=BeforeProfileSwitch()
        if not ok then return false,why end end
    if chars then
        for _, char in pairs(chars) do
            if type(char) == "table" then
                if char.activeProfile == name then char.activeProfile = fallbackName end
                if type(char.specProfileMap) == "table" then
                    for specID, profileName in pairs(char.specProfileMap) do
                        if profileName == name then char.specProfileMap[specID] = nil end
                    end
                end
            end
        end
    end
    --- Clear rather than retarget: the account chose this specific profile as
    --- the starting point for new characters, and silently pointing that at an
    --- arbitrary survivor would change what the setting means. New characters
    --- fall back to "Default" until the account picks a replacement.
    local globalMeta = MSUF_ProfileIO_EnsureGlobalMeta()
    if globalMeta.defaultProfileForNewChars == name then
        globalMeta.defaultProfileForNewChars = nil
    end
    if ProfileSync then ProfileSync.RenameOrDelete(name) end
    profiles[name] = nil
    MSUF.DefaultsSchema.RenameProfileRecovery(name)
    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end
    MSUF_ProfileIO_NotifySuiteLifecycle("delete", name)
    if not quiet then ProfileChat("note", "Profile '%s' deleted.", name) end
    return true
 end
function MSUF_DeleteProfile(name)
    return DeleteProfile(name, false)
end
--- The Profiles page cleanup list deletes several profiles at once. Every name
--- takes the MSUF_DeleteProfile path above (character bindings, spec maps, the
--- new-character default, sync groups, the Suite); one chat line reports the
--- count. Returns how many profiles were deleted.
local function MSUF_DeleteProfiles(names)
    local deleted = 0
    for i = 1, type(names) == "table" and #names or 0 do
        -- A profile/spec switch may have changed the active profile while the
        -- cleanup confirmation was open. Its dedicated delete stays separate.
        local name = names[i]
        if type(name) == "string" and name ~= MSUF_ActiveProfile and DeleteProfile(name, true) == true then
            deleted = deleted + 1
        end
    end
    if deleted > 0 then ProfileChat("note", "Profiles deleted: %d", deleted) end
    return deleted
end
local function ProfileCopySource(profiles, sourceName, destName)
    local src = profiles[sourceName]
    if type(src) ~= "table" then
        ProfileChat("error", "Source profile '%s' not found.", sourceName)
        return nil
    end
    if profiles[destName] then
        ProfileChat("error", "Profile '%s' already exists.", destName)
        return nil
    end
    return src
end

local function MSUF_CopyProfile(sourceName, destName)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    if not sourceName or sourceName == "" then
        ProfileChat("error", "No source profile specified.")
        return false
    end
    if type(destName) ~= "string" or not destName:find("%S") or destName:find("[%z\1-\31]") then
        ProfileChat("error", "No destination name specified.")
        return false
    end
    if ProfileNameTooLong(destName) then return false, "profile name too long" end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local src = ProfileCopySource(profiles, sourceName, destName)
    if not src then return false end
    local copy,why
    if Variants then copy,why=Variants.BaseSnapshot(src,true) else copy=CopyTable(src) end
    if not copy then return false,why end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(copy) end
    copy.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    profiles[destName] = copy
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[destName], {
            source = "profile_copy",
            trustNormalizationMarker = true,
        })
    end
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profiles[destName])
    if MSUF.ProfileMigrations then MSUF.ProfileMigrations.Apply(profiles[destName]) end
    local ok,reason=MSUF_ProfileIO_NotifySuiteLifecycle("copy", sourceName, destName)
    if ok==false then profiles[destName]=nil
        return false,reason end
    ProfileChat("ok", "Copied '%s' -> '%s'.", sourceName, destName)
    return true
end
local function MSUF_RenameProfile(sourceName, destName)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    if not sourceName or sourceName == "" then
        ProfileChat("error", "No source profile specified.")
        return false
    end
    if type(destName) ~= "string" or not destName:find("%S") then
        ProfileChat("error", "No destination name specified.")
        return false
    end
    if destName:find("[%z\1-\31]") then
        ProfileChat("error", "Profile names need a visible character and cannot contain control characters.")
        return false, "invalid-profile-name"
    end
    if sourceName == destName then
        ProfileChat("note", "Profile is already named '%s'.", sourceName)
        return true
    end
    if ProfileNameTooLong(destName) then return false, "profile name too long" end
    if sourceName == "Default" then
        ProfileChat("error", "You cannot rename the 'Default' profile. Copy it instead.")
        return false
    end

    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local src = ProfileCopySource(profiles, sourceName, destName)
    if not src then return false end
    --- The Suite renames its own and its skin's profile first. It refuses,
    --- with nothing changed, a name one of them already holds, a name it
    --- cannot store, and any rename in combat. Out of combat the variant
    --- overlay is lifted before it is asked, so it moves the base settings; a
    --- refusal lays the overlay again.
    local active = MSUF_ActiveProfile == sourceName
    local overlay = active and Variants and not InCombatLockdown()
    if overlay then Variants.Restore() end
    local accepted, refusal = MSUF_ProfileIO_NotifySuiteLifecycle("rename", sourceName, destName)
    if accepted == false then
        if overlay then Variants.ResolveCurrent() end
        if refusal == "profile-exists" then
            ProfileChat("error", "Profile '%s' already exists.", destName)
        elseif InCombatLockdown() then
            print(Translate("|cffff0000MSUF:|r Cannot change profiles while in combat."))
        elseif refusal == "invalid-profile-name" then
            --- Too long was refused above; the Suite's rule also wants a
            --- visible character and no control characters.
            ProfileChat("error", "Profile names need a visible character and cannot contain control characters.")
        else
            ProfileChat("error", "Profile names can be at most %d bytes long.", 80)
        end
        return false, refusal
    end

    if ProfileSync then ProfileSync.RenameOrDelete(sourceName,destName) end
    profiles[destName] = src
    profiles[sourceName] = nil
    MSUF.DefaultsSchema.RenameProfileRecovery(sourceName, destName)
    MSUF.GuidedTour6:RenameProfile(sourceName, destName)
    if chars then
        for _, char in pairs(chars) do
            if type(char) == "table" then
                if char.activeProfile == sourceName then
                    char.activeProfile = destName
                end
                local map = char.specProfileMap
                if type(map) == "table" then
                    for specID, profileName in pairs(map) do
                        if profileName == sourceName then
                            map[specID] = destName
                        end
                    end
                end
            end
        end
    end
    --- The profile itself survives a rename, so the new-character preference
    --- follows it instead of being cleared.
    local globalMeta = MSUF_ProfileIO_EnsureGlobalMeta()
    if globalMeta.defaultProfileForNewChars == sourceName then
        globalMeta.defaultProfileForNewChars = destName
    end
    --- The switch prepares (sync flush, variant restore) under the new name:
    --- the old one is gone from every store, and resolving it would make the
    --- Suite create a stray profile under it.
    if active then
        MSUF_ActiveProfile = destName
        MSUF_SwitchProfile(destName)
    end
    ProfileChat("ok", "Renamed '%s' -> '%s'.", sourceName, destName)
    return true
end
local function MSUF_GetAllProfiles()
    local list = {}
    if MSUF_GlobalDB and type(MSUF_GlobalDB.profiles) == "table" then
        for name, tbl in pairs(MSUF_GlobalDB.profiles) do
            if type(name) == "string" and type(tbl) == "table" then
                table.insert(list, name)
            end
        end
        table.sort(list)
    end
     return list
end
---
--- Spec-based profile auto-switch (per-character)
--- Stored in:
--- MSUF_GlobalDB.char[charKey].specAutoSwitch (boolean)
--- MSUF_GlobalDB.char[charKey].specProfileMap (table: specID -> profileName)
--- This is intentionally not profile-local: a profile switch must not rewrite
--- the player's "which spec should load which profile" preference.
--- Design goals:
--- - Very small, fully optional (off by default).
--- - Combat-safe: if spec changes in combat, we defer the switch.
--- - Works with existing global profiles (no DB migration needed).
---
--- WoW Forever: every class has a single specialization, and players switch
--- between Blizzard's two talent groups instead (the Camelot talent frame's
--- DUAL_SPEC_PRIMARY/DUAL_SPEC_SECONDARY tabs, driven by
--- C_SpecializationInfo.GetActiveSpecGroup). Blizzard_DeprecatedSpecialization,
--- the only source of the global GetSpecialization/GetSpecializationInfo, does
--- not load there. On Forever the specProfileMap key is therefore the active
--- talent group index (1 primary, 2 secondary); every other client keeps specID.
local IS_FOREVER = MSUF.Client.IsForever == true
local function MSUF_GetCharMeta()
    local _, chars = MSUF_ProfileIO_EnsureProfileRoots()
    GetCharKey = GetCharKey or MSUF.Require("MSUF_GetCharKey", "State/MSUF_Profiles.lua")
    local charKey = GetCharKey()
    local char = chars[charKey]
    if type(char) ~= "table" then
        char = {}
        chars[charKey] = char
    end
    if char.specAutoSwitch == nil then
        char.specAutoSwitch = false
    end
    if type(char.specProfileMap) ~= "table" then
        char.specProfileMap = {}
    end
     return char
end
function MSUF.PublicGlobals.MSUF_IsSpecAutoSwitchEnabled()
    local char = MSUF_GetCharMeta()
    return (char.specAutoSwitch == true)
end
ExportPublic("MSUF_IsSpecAutoSwitchEnabled", MSUF.PublicGlobals.MSUF_IsSpecAutoSwitchEnabled)
function MSUF.PublicGlobals.MSUF_SetSpecAutoSwitchEnabled(enabled)
    local char = MSUF_GetCharMeta()
    char.specAutoSwitch = (enabled == true)
    if char.specAutoSwitch then
        if MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled then
            MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled("TOGGLE_ON")
        end
    end
 end
ExportPublic("MSUF_SetSpecAutoSwitchEnabled", MSUF.PublicGlobals.MSUF_SetSpecAutoSwitchEnabled)
function MSUF.PublicGlobals.MSUF_GetSpecProfile(specID)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return nil end
    local v = char.specProfileMap[specID]
    if type(v) ~= "string" or v == "" then
         return nil
    end
     return v
end
ExportPublic("MSUF_GetSpecProfile", MSUF.PublicGlobals.MSUF_GetSpecProfile)
function MSUF.PublicGlobals.MSUF_SetSpecProfile(specID, profileName)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return end
    --- "None" clears unless a real profile owns the name (the contract of
    --- MSUF_SetDefaultProfileForNewCharacters).
    if type(profileName) ~= "string" or profileName == ""
        or (profileName == "None" and type(MSUF_GlobalDB.profiles.None) ~= "table") then
        char.specProfileMap[specID] = nil
    else
        char.specProfileMap[specID] = profileName
    end
    if char.specAutoSwitch == true then
        local cur = MSUF.PublicGlobals.MSUF_GetPlayerSpecID and MSUF.PublicGlobals.MSUF_GetPlayerSpecID() or nil
        if cur == specID then
            if MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled then
                MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled("MAP_CHANGED")
            end
        end
    end
 end
ExportPublic("MSUF_SetSpecProfile", MSUF.PublicGlobals.MSUF_SetSpecProfile)
function MSUF.PublicGlobals.MSUF_GetPlayerSpecID()
    if IS_FOREVER then
        local specInfo = _G.C_SpecializationInfo
        local getActiveGroup = type(specInfo) == "table" and specInfo.GetActiveSpecGroup or nil
        if type(getActiveGroup) ~= "function" then  return nil end
        local group = getActiveGroup()
        if type(group) ~= "number" or group < 1 then  return nil end
        return group
    end
    local api = MSUF.Specialization
    if not api.GetSpecialization or not api.GetSpecializationInfo then return nil end
    local idx = api.GetSpecialization()
    if not idx then return nil end
    local specID = api.GetSpecializationInfo(idx)
    if type(specID) ~= "number" then
         return nil
    end
     return specID
end
ExportPublic("MSUF_GetPlayerSpecID", MSUF.PublicGlobals.MSUF_GetPlayerSpecID)
--- Combat-safe deferrer (shared)
local function MSUF_RunAfterCombat_SpecProfile(fn)
    if type(fn) ~= "function" then  return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        ExportPublic("MSUF_PendingSpecProfileSwitch", fn)
        local f = MSUF.PublicGlobals.MSUF_SpecProfileDeferFrame
        if not f and type(_G.CreateFrame) == "function" then
            f = _G.CreateFrame("Frame")
            ExportPublic("MSUF_SpecProfileDeferFrame", f)
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                local pending = MSUF.PublicGlobals.MSUF_PendingSpecProfileSwitch
                if pending then
                    ExportPublic("MSUF_PendingSpecProfileSwitch", nil)
                    pending()
                end
             end)
        end
         return
    end
    fn()
 end
function MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled(reason)
    local char = MSUF_GetCharMeta()
    if char.specAutoSwitch ~= true then  return end
    GetPlayerSpecID = GetPlayerSpecID or MSUF.Require("MSUF_GetPlayerSpecID", "State/MSUF_Profiles.lua")
    local specID = GetPlayerSpecID()
    if type(specID) ~= "number" then  return end
    local profileName = char.specProfileMap[specID]
    if type(profileName) ~= "string" or profileName == "" then  return end
    --- Only switch to existing profiles.
    if not (type(_G.MSUF_GlobalDB) == "table"
        and type(_G.MSUF_GlobalDB.profiles) == "table"
        and type(_G.MSUF_GlobalDB.profiles[profileName]) == "table") then return end
    if _G.MSUF_ActiveProfile == profileName then
         return
    end
    MSUF_RunAfterCombat_SpecProfile(function()
        --- Re-check after combat (spec could have changed again).
        IsSpecAutoSwitchEnabled = IsSpecAutoSwitchEnabled or MSUF.Require("MSUF_IsSpecAutoSwitchEnabled", "State/MSUF_Profiles.lua")
        if not IsSpecAutoSwitchEnabled() then  return end
        GetPlayerSpecID = GetPlayerSpecID or MSUF.Require("MSUF_GetPlayerSpecID", "State/MSUF_Profiles.lua")
        local cur = GetPlayerSpecID()
        if cur ~= specID then  return end
        GetSpecProfile = GetSpecProfile or MSUF.Require("MSUF_GetSpecProfile", "State/MSUF_Profiles.lua")
        local mapped = GetSpecProfile(specID)
        if mapped ~= profileName then  return end
        if _G.MSUF_ActiveProfile == profileName then  return end
        if _G.MSUF_SwitchProfile then
            _G.MSUF_SwitchProfile(profileName)
        end
     end)
 end
ExportPublic("MSUF_ApplySpecProfileIfEnabled", MSUF.PublicGlobals.MSUF_ApplySpecProfileIfEnabled)
--- Event driver (very small; only does work when enabled)
do
    local f
    local function EnsureFrame()
        if f then  return end
        if type(_G.CreateFrame) ~= "function" then  return end
        f = _G.CreateFrame("Frame")
        ExportPublic("MSUF_SpecProfileEventFrame", f)
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
                 return
            end
            IsSpecAutoSwitchEnabled = IsSpecAutoSwitchEnabled or MSUF.Require("MSUF_IsSpecAutoSwitchEnabled", "State/MSUF_Profiles.lua")
            if not MSUF_ActiveProfile or not IsSpecAutoSwitchEnabled() then return end
            ApplySpecProfileIfEnabled = ApplySpecProfileIfEnabled or MSUF.Require("MSUF_ApplySpecProfileIfEnabled", "State/MSUF_Profiles.lua")
            ApplySpecProfileIfEnabled(event)
         end)
     end
    EnsureFrame()
end
---
--- Profile Export / Import (selection-based)
--- New snapshot format (Lua table):
--- return {
--- addon = "MSUF",
--- fmt = 2,
--- schema = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
--- kind = "unitframe" | "castbar" | "colors" | "gameplay" | "groupframe" | "all",
--- profile = "<active profile name>",
--- payload = { ...selected settings... },
--- }
--- Import behavior:
--- - If the snapshot matches the format above: apply only the selected category into the
--- CURRENT ACTIVE profile (keeps everything else unchanged).
--- - Text snapshots emitted by the serializer remain supported when they carry
---   the same schema-600 contract.
---

Parts.ApplyProfileRuntime = ApplyProfileRuntime
Parts.ExportPublic = ExportPublic
Parts.InitProfiles = InitProfiles
Parts.MSUF_CopyProfile = MSUF_CopyProfile
Parts.MSUF_DeleteProfiles = MSUF_DeleteProfiles
Parts.MSUF_GetAllProfiles = MSUF_GetAllProfiles
Parts.MSUF_PROFILE_IMPORT_LIMITS = MSUF_PROFILE_IMPORT_LIMITS
Parts.MSUF_ProfileIO_EnsureProfileMenuDefaults = MSUF_ProfileIO_EnsureProfileMenuDefaults
Parts.MSUF_ProfileIO_EnsureProfileRoots = MSUF_ProfileIO_EnsureProfileRoots
Parts.MSUF_ProfileIO_NotifySuiteLifecycle = MSUF_ProfileIO_NotifySuiteLifecycle
Parts.MSUF_ProfileIO_NotifySuiteProfileChanged = MSUF_ProfileIO_NotifySuiteProfileChanged
Parts.MSUF_ProfileIO_RunEnsureDB = MSUF_ProfileIO_RunEnsureDB
Parts.MSUF_ProfileIO_TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent
Parts.MSUF_ProfileIO_TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent
Parts.MSUF_RenameProfile = MSUF_RenameProfile
Parts.MSUF_ResetProfile = MSUF_ResetProfile
Parts.Normalize = Normalize
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.PrepareProfileMutation = PrepareProfileMutation
Parts.ProfileChat = ProfileChat
Parts.ProfileChatLine = ProfileChatLine
Parts.ProfileNameTooLong = ProfileNameTooLong
Parts.ProfileSync = ProfileSync
Parts.StateHelpers = StateHelpers
Parts.Translate = Translate
Parts.Variants = Variants
