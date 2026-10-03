local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
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

local ExportPublic = MSUF.ExportPublic

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
function MSUF_GetCharKey()
    -- A client without realms may report no realm name. Coerce it to "" so the
    -- key stays stable and profile bootstrap never concatenates nil.
    local realm = GetRealmName()
    if type(realm) ~= "string" then realm = "" end
    return UnitName("player") .. "-" .. realm
end
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
--- A stale configured name must fall through to "Default" instead of being
--- honoured: the init path clones a donor into any missing profile name, so an
--- unvalidated value here would resurrect a deleted profile as a ghost copy.
--- Reads the stored field directly rather than through the public getter, so a
--- third party replacing that global cannot steer login profile selection.
local function MSUF_ProfileIO_NewCharacterProfile(profiles)
    local configured = MSUF_ProfileIO_EnsureGlobalMeta().defaultProfileForNewChars
    if type(configured) ~= "string" or configured == "" then return nil end
    if type(profiles) == "table" and type(profiles[configured]) == "table" then
        return configured
    end
    return nil
end
--- Pick the donor profile for a repair without depending on `pairs()` order.
--- Two characters hitting this same path must clone the same source, otherwise
--- an account silently grows divergent copies of an arbitrary profile. Only
--- string keys are eligible because `MSUF_GetAllProfiles` never lists any other
--- kind, so a numeric-keyed leftover must not become somebody's live settings.
local function MSUF_ProfileIO_FallbackProfileTable(profiles)
    if type(profiles) ~= "table" then return nil, nil end
    if type(profiles["Default"]) == "table" then
        return profiles["Default"], "Default"
    end
    local names
    for name, tbl in pairs(profiles) do
        if type(name) == "string" and name ~= "" and type(tbl) == "table" then
            names = names or {}
            names[#names + 1] = name
        end
    end
    if not names then return nil, nil end
    table.sort(names)
    return profiles[names[1]], names[1]
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
function MSUF_InitProfiles()
    if Variants and Variants.IsRecording() then return end
    -- A rebind to a different profile passes BeforeProfileSwitch below.
    PrepareProfileMutation(true)
    local previousActive = type(MSUF_ActiveProfile) == "string" and MSUF_ActiveProfile or nil
    local previousDB = type(MSUF_DB) == "table" and MSUF_DB or nil
    local hadEstablishedOwner = previousActive ~= nil and previousActive ~= "" and previousDB ~= nil
    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local charKey = MSUF_GetCharKey()
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
        local base = MSUF_DB or {}
        profiles["Default"] = CopyTable(type(base) == "table" and base or {})
        if not active then
            active = "Default"
        end
    end
    if not active then
        --- A character that has never chosen a profile follows the account-wide
        --- preference when it still names a live profile. Everything else keeps
        --- landing on "Default" exactly as before, and a character that already
        --- has `activeProfile` set never reaches this branch at all.
        active = MSUF_ProfileIO_NewCharacterProfile(profiles) or "Default"
    end
    if type(profiles[active]) ~= "table" then
        local fallback = MSUF_ProfileIO_FallbackProfileTable(profiles)
        profiles[active] = CopyTable(fallback or {})
    end
    if hadEstablishedOwner and (previousActive~=active or previousDB~=profiles[active]) then
        local ok,why=BeforeProfileSwitch()
        if not ok then return false,why end
    end
    if MSUF_ProfileIO_TranslateProfilesToCurrent then
        MSUF_ProfileIO_TranslateProfilesToCurrent(profiles, "init")
    end
    char.activeProfile = active
    MSUF_ActiveProfile = active
    MSUF_DB = profiles[active]
    _G.MSUF_GF_InvalidateConfCache()
    --- After DB swap: seed missing defaults so per-unit conf tables exist.
    --- Without this, CreateSimpleUnitFrame sees conf=nil/{} for pet/targettarget
    --- when the profile was saved from an older version missing those keys,
    --- and UpdateSimpleUnitFrame defaults showPowerText=true since conf.showPower is nil.
    --- The Defaults module persists its completed repair revision on the
    --- profile. A non-forced ensure still repairs a new/legacy profile, while
    --- avoiding a second complete pass when this exact profile was already
    --- repaired earlier in the startup chain.
    MSUF_ProfileIO_RunEnsureDB(false, true)
    if Variants then Variants.ResolveCurrent() end
    if ProfileSync then ProfileSync.Activate(); ProfileSync.RefreshEvents() end
    if hadEstablishedOwner and (previousActive ~= active or previousDB ~= MSUF_DB) then
        ApplyProfileRuntime("PROFILE_INIT_REBIND", false)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_INIT_REBIND", active)
    end
 end
local function MSUF_ProfileIO_NotifySuiteLifecycle(kind, source, target)
    local suite = rawget(_G, "MSUFSuite")
    if type(suite) == "table" and type(suite.OnMSUFProfileLifecycle) == "function" then
        return suite.OnMSUFProfileLifecycle(kind, source, target)
    end
    return true
end
function MSUF_CreateProfile(name)
    if type(name) ~= "string" or name == "" then return false, "invalid profile name" end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if profiles[name] then
        ProfileChat("error", "Profile '%s' already exists.", name)
        return false, "profile already exists"
    end
    local createFactoryProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
        or _G.MSUF_CreateFactoryDefaultProfile
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
    MSUF_ProfileIO_NotifySuiteLifecycle("create", name)
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
        if rawget(_G, "MSUF_InCombat") == true
            or (type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true)
            or (type(_G.UnitAffectingCombat) == "function" and _G.UnitAffectingCombat("player") == true)
        then
            pendingReason, pendingName = reason, name
            MSUF.EventBus:Register("PLAYER_REGEN_ENABLED", "MSUF_PROFILES_SUITE_NOTIFY", FlushPending, nil, true)
            return false
        end
        local suite = rawget(_G, "MSUFSuite")
        if type(suite) == "table" and type(suite.OnMSUFProfileChanged) == "function" then
            suite.OnMSUFProfileChanged(name, reason)
        end
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
    local charKey = MSUF_GetCharKey()
    local char = type(chars[charKey]) == "table" and chars[charKey] or {}
    chars[charKey] = char
    if MSUF_ProfileIO_TranslateProfileToCurrent then
        MSUF_ProfileIO_TranslateProfileToCurrent(profiles[name], {
            source = "profile_switch",
            trustNormalizationMarker = true,
        })
    end
    char.activeProfile = name
    MSUF_ActiveProfile = name
    MSUF_DB = profiles[name]
    _G.MSUF_GF_InvalidateConfCache()
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
function MSUF_ResetProfile(name)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    name = name or MSUF_ActiveProfile
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    if not name or not profiles[name] then return false, "unknown profile" end
    if name == MSUF_ActiveProfile then local ok,why=BeforeProfileSwitch(); if not ok then return false,why end end
    if name ~= MSUF_ActiveProfile then
        --- A stored profile needs its schema stamp (an unstamped table is
        --- archived as pre-6.0 at the next login), so it is seeded the way
        --- MSUF_CreateProfile seeds one; the active one is seeded by EnsureDB.
        local createFactoryProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
            or _G.MSUF_CreateFactoryDefaultProfile
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
        _G.MSUF_GF_InvalidateConfCache()
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
function MSUF_DeleteProfile(name)
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
    if MSUF_ActiveProfile == name then local ok,why=BeforeProfileSwitch(); if not ok then return false,why end end
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
    if MSUF_ActiveProfile == name then
        MSUF_SwitchProfile(fallbackName)
    end
    MSUF_ProfileIO_NotifySuiteLifecycle("delete", name)
    ProfileChat("note", "Profile '%s' deleted.", name)
    return true
 end
function MSUF_CopyProfile(sourceName, destName)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    if not sourceName or sourceName == "" then
        ProfileChat("error", "No source profile specified.")
        return false
    end
    if not destName or destName == "" then
        ProfileChat("error", "No destination name specified.")
        return false
    end
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local src = profiles[sourceName]
    if type(src) ~= "table" then
        ProfileChat("error", "Source profile '%s' not found.", sourceName)
        return false
    end
    if profiles[destName] then
        ProfileChat("error", "Profile '%s' already exists.", destName)
        return false
    end
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
    local ok,reason=MSUF_ProfileIO_NotifySuiteLifecycle("copy", sourceName, destName)
    if ok==false then profiles[destName]=nil; return false,reason end
    ProfileChat("ok", "Copied '%s' -> '%s'.", sourceName, destName)
    return true
end
function MSUF_RenameProfile(sourceName, destName)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    if not sourceName or sourceName == "" then
        ProfileChat("error", "No source profile specified.")
        return false
    end
    if not destName or destName == "" then
        ProfileChat("error", "No destination name specified.")
        return false
    end
    if sourceName == destName then
        ProfileChat("note", "Profile is already named '%s'.", sourceName)
        return true
    end
    if sourceName == "Default" then
        ProfileChat("error", "You cannot rename the 'Default' profile. Copy it instead.")
        return false
    end

    local profiles, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local src = profiles[sourceName]
    if type(src) ~= "table" then
        ProfileChat("error", "Source profile '%s' not found.", sourceName)
        return false
    end
    if profiles[destName] then
        ProfileChat("error", "Profile '%s' already exists.", destName)
        return false
    end

    if MSUF_ActiveProfile == sourceName then local ok,why=BeforeProfileSwitch(); if not ok then return false,why end end
    if ProfileSync then ProfileSync.RenameOrDelete(sourceName,destName) end
    profiles[destName] = src
    profiles[sourceName] = nil
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
    MSUF_ProfileIO_NotifySuiteLifecycle("rename", sourceName, destName)
    if MSUF_ActiveProfile == sourceName then
        MSUF_SwitchProfile(destName)
    end
    ProfileChat("ok", "Renamed '%s' -> '%s'.", sourceName, destName)
    return true
end
function MSUF_GetAllProfiles()
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
local IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true
local function MSUF_GetCharMeta()
    local _, chars = MSUF_ProfileIO_EnsureProfileRoots()
    local charKey = MSUF_GetCharKey()
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
function MSUF_IsSpecAutoSwitchEnabled()
    local char = MSUF_GetCharMeta()
    return (char.specAutoSwitch == true)
end
function MSUF_SetSpecAutoSwitchEnabled(enabled)
    local char = MSUF_GetCharMeta()
    char.specAutoSwitch = (enabled == true)
    if char.specAutoSwitch then
        if _G.MSUF_ApplySpecProfileIfEnabled then
            _G.MSUF_ApplySpecProfileIfEnabled("TOGGLE_ON")
        end
    end
 end
function MSUF_GetSpecProfile(specID)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return nil end
    local v = char.specProfileMap[specID]
    if type(v) ~= "string" or v == "" then
         return nil
    end
     return v
end
function MSUF_SetSpecProfile(specID, profileName)
    local char = MSUF_GetCharMeta()
    if type(specID) ~= "number" then  return end
    if type(profileName) ~= "string" or profileName == "" or profileName == "None" then
        char.specProfileMap[specID] = nil
    else
        char.specProfileMap[specID] = profileName
    end
    if char.specAutoSwitch == true then
        local cur = _G.MSUF_GetPlayerSpecID and _G.MSUF_GetPlayerSpecID() or nil
        if cur == specID then
            if _G.MSUF_ApplySpecProfileIfEnabled then
                _G.MSUF_ApplySpecProfileIfEnabled("MAP_CHANGED")
            end
        end
    end
 end
function MSUF_GetPlayerSpecID()
    if IS_FOREVER then
        local specInfo = _G.C_SpecializationInfo
        local getActiveGroup = type(specInfo) == "table" and specInfo.GetActiveSpecGroup or nil
        if type(getActiveGroup) ~= "function" then  return nil end
        local group = getActiveGroup()
        if type(group) ~= "number" or group < 1 then  return nil end
        return group
    end
    if type(_G.GetSpecialization) ~= "function" or type(_G.GetSpecializationInfo) ~= "function" then
         return nil
    end
    local idx = _G.GetSpecialization()
    if not idx then  return nil end
    local specID = _G.GetSpecializationInfo(idx)
    if type(specID) ~= "number" then
         return nil
    end
     return specID
end
--- Combat-safe deferrer (shared)
local function MSUF_RunAfterCombat_SpecProfile(fn)
    if type(fn) ~= "function" then  return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        ExportPublic("MSUF_PendingSpecProfileSwitch", fn)
        local f = _G.MSUF_SpecProfileDeferFrame
        if not f and type(_G.CreateFrame) == "function" then
            f = _G.CreateFrame("Frame")
            ExportPublic("MSUF_SpecProfileDeferFrame", f)
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                local pending = _G.MSUF_PendingSpecProfileSwitch
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
function MSUF_ApplySpecProfileIfEnabled(reason)
    local char = MSUF_GetCharMeta()
    if char.specAutoSwitch ~= true then  return end
    local specID = MSUF_GetPlayerSpecID()
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
        if not MSUF_IsSpecAutoSwitchEnabled() then  return end
        local cur = MSUF_GetPlayerSpecID()
        if cur ~= specID then  return end
        local mapped = MSUF_GetSpecProfile(specID)
        if mapped ~= profileName then  return end
        if _G.MSUF_ActiveProfile == profileName then  return end
        if _G.MSUF_SwitchProfile then
            _G.MSUF_SwitchProfile(profileName)
        end
     end)
 end
--- Event driver (very small; only does work when enabled)
do
    local f
    local function EnsureFrame()
        if f then  return end
        if type(_G.CreateFrame) ~= "function" then  return end
        f = _G.CreateFrame("Frame")
        ExportPublic("MSUF_SpecProfileEventFrame", f)
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_LOGIN")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
                 return
            end
            if not MSUF_IsSpecAutoSwitchEnabled() then return end
            MSUF_ApplySpecProfileIfEnabled(event)
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
local function MSUF_WipeTable(t)
    if not t then  return end
    for k in pairs(t) do
        t[k] = nil
    end
 end
local MSUF_DeepCopy = Normalize.DeepCopy

MSUF.ProfileIOValidateImportValue = function(root)
    local seen, nodes, stringBytes = {}, 0, 0
    local function Walk(value, depth)
        nodes = nodes + 1
        if nodes > MSUF_PROFILE_IMPORT_LIMITS.nodes then return false, "profile has too many values" end
        local valueType = type(value)
        if valueType == "string" then
            stringBytes = stringBytes + #value
            if stringBytes > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return false, "profile strings are too large" end
            return true
        end
        if valueType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then return false, "profile contains an invalid number" end
            return true
        end
        if valueType == "nil" or valueType == "boolean" then return true end
        -- The template and the type name ride along, so the chat line translates the sentence first.
        if valueType ~= "table" then return false, "profile contains unsupported " .. valueType, "profile contains unsupported %s", valueType end
        if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then return false, "profile is too deep" end
        if seen[value] then return false, "profile contains a cyclic or shared table" end
        seen[value] = true
        for key, child in pairs(value) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then return false, "profile contains an unsupported table key" end
            local ok, why, template, inserted = Walk(key, depth + 1)
            if not ok then return false, why, template, inserted end
            ok, why, template, inserted = Walk(child, depth + 1)
            if not ok then return false, why, template, inserted end
        end
        return true
    end
    if type(root) ~= "table" then return false, "profile is not a table" end
    return Walk(root, 1)
end

local MSUF_ProfileIO_ImportWarningMap = {}
local MSUF_ProfileIO_ImportWarnings = {}

local function MSUF_ProfileIO_ResetImportWarnings()
    for key in pairs(MSUF_ProfileIO_ImportWarningMap) do
        MSUF_ProfileIO_ImportWarningMap[key] = nil
    end
    for i = #MSUF_ProfileIO_ImportWarnings, 1, -1 do
        MSUF_ProfileIO_ImportWarnings[i] = nil
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
end

local function MSUF_ProfileIO_AddImportWarning(kind, label, value)
    if type(value) ~= "string" or value == "" then return end
    kind = tostring(kind or "media")
    label = tostring(label or "profile")
    local id = kind .. "\001" .. label .. "\001" .. value
    if MSUF_ProfileIO_ImportWarningMap[id] then return end
    MSUF_ProfileIO_ImportWarningMap[id] = true
    MSUF_ProfileIO_ImportWarnings[#MSUF_ProfileIO_ImportWarnings + 1] = {
        kind = kind,
        label = label,
        value = value,
    }
end

local function MSUF_ProfileIO_PublishImportWarnings()
    if #MSUF_ProfileIO_ImportWarnings == 0 then
        ExportPublic("MSUF_ProfileIO_LastImportWarnings", nil)
        return nil
    end
    local copy = {}
    for i = 1, #MSUF_ProfileIO_ImportWarnings do
        copy[i] = MSUF_DeepCopy(MSUF_ProfileIO_ImportWarnings[i])
    end
    ExportPublic("MSUF_ProfileIO_LastImportWarnings", copy)
    return copy
end

local function MSUF_ProfileIO_ReportImportWarnings()
    local warnings = MSUF_ProfileIO_PublishImportWarnings()
    if not warnings then return end
    local count = #warnings
    local maxLines = count > 5 and 5 or count
    for i = 1, maxLines do
        local w = warnings[i]
        local text = (w.kind == "font") and "Import warning: missing font '%s' in %s. Using fallback font."
            or "Import warning: missing texture '%s' in %s. Using fallback texture."
        ProfileChat("note", text, tostring(w.value), tostring(w.label))
    end
    if count > maxLines then
        ProfileChat("note", "Import warning: %d more missing media item(s).", count - maxLines)
    end
end

local function MSUF_ProfileIO_GetLSM()
    return (MSUF and MSUF.LSM) or _G.MSUF_LSM or (_G.LibStub and _G.LibStub("LibSharedMedia-3.0", true))
end

local function MSUF_ProfileIO_LooksLikeMediaPath(value)
    if type(value) ~= "string" or value == "" then return false end
    local lower = value:lower()
    return value:find("\\", 1, true) ~= nil
        or value:find("/", 1, true) ~= nil
        or lower:match("%.ttf$") ~= nil
        or lower:match("%.otf$") ~= nil
        or lower:match("%.tga$") ~= nil
        or lower:match("%.blp$") ~= nil
        or lower:match("%.png$") ~= nil
end

local function MSUF_ProfileIO_FontPathAvailable(path)
    if type(path) ~= "string" or path == "" then return false end
    --- Runtime/MSUF_FontRegistry.lua answers availability from registry
    --- metadata (MSUF_IsAvailableFontPath); the SetFont probe it replaced,
    --- MSUF_FontPathIsLoadable, no longer exists.
    local isAvailable = _G.MSUF_IsAvailableFontPath
    if type(isAvailable) == "function" then
        return isAvailable(path) == true
    end
    local isKnown = _G.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then return false end
    return true
end

local function MSUF_ProfileIO_FontKeyAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    local normalize = _G.MSUF_NormalizeFontKey
    local normalized = normalize(key)
    local internal = _G.MSUF_GetInternalFontPathByKey
    if type(internal) == "function" then
        local path = internal(normalized) or internal(key)
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then
        return MSUF_ProfileIO_FontPathAvailable(key)
    end
    local lsm = MSUF_ProfileIO_GetLSM()
    if lsm and type(lsm.HashTable) == "function" then
        local fonts = lsm:HashTable("font")
        local path = fonts and (fonts[normalized] or fonts[key])
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    if lsm and type(lsm.Fetch) == "function" then
        local path = lsm:Fetch("font", normalized, true)
        if (not path) and normalized ~= key then path = lsm:Fetch("font", key, true) end
        if MSUF_ProfileIO_FontPathAvailable(path) then return true end
    end
    return false
end

local MSUF_ProfileIO_TextureProbeHost
local MSUF_ProfileIO_TextureProbe
local MSUF_ProfileIO_TextureProbeReliable
local MSUF_ProfileIO_TexturePathCache = {}

local function MSUF_ProfileIO_NormalizeTexturePath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("/", "\\")
    return path ~= "" and path or nil
end

local function MSUF_ProfileIO_TextureProbeRaw(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path or type(_G.CreateFrame) ~= "function" then return nil end
    if not MSUF_ProfileIO_TextureProbe then
        MSUF_ProfileIO_TextureProbeHost = _G.CreateFrame("Frame")
        if MSUF_ProfileIO_TextureProbeHost.Hide then MSUF_ProfileIO_TextureProbeHost:Hide() end
        MSUF_ProfileIO_TextureProbe = PixelLayoutRegion(MSUF_ProfileIO_TextureProbeHost:CreateTexture(nil, "ARTWORK"), true)
    end
    local probe = MSUF_ProfileIO_TextureProbe
    if not (probe and type(probe.SetTexture) == "function") then return nil end
    probe:SetTexture(nil)
    -- SetTexture reports an unloadable path via its documented success return.
    local applied = probe:SetTexture(path)
    if applied == false then
        probe:SetTexture(nil)
        return false
    end
    if type(probe.GetTexture) == "function" then
        local tex = probe:GetTexture()
        probe:SetTexture(nil)
        return tex ~= nil and tex ~= ""
    end
    probe:SetTexture(nil)
    return true
end

local function MSUF_ProfileIO_TextureProbeIsReliable()
    if MSUF_ProfileIO_TextureProbeReliable ~= nil then return MSUF_ProfileIO_TextureProbeReliable end
    local result = MSUF_ProfileIO_TextureProbeRaw("Interface\\AddOns\\MidnightSimpleUnitFrames\\__msuf_missing_texture_probe__")
    MSUF_ProfileIO_TextureProbeReliable = (result == false)
    return MSUF_ProfileIO_TextureProbeReliable
end

local function MSUF_ProfileIO_TexturePathLoadable(path)
    path = MSUF_ProfileIO_NormalizeTexturePath(path)
    if not path then return false end
    local cached = MSUF_ProfileIO_TexturePathCache[path]
    if cached ~= nil then return cached end
    local isKnown = _G.MSUF_IsKnownFileAsset
    if type(isKnown) == "function" and isKnown(path) == false then
        MSUF_ProfileIO_TexturePathCache[path] = false
        return false
    end
    if not MSUF_ProfileIO_TextureProbeIsReliable() then
        MSUF_ProfileIO_TexturePathCache[path] = true
        return true
    end
    local lower = path:lower()
    local exists = MSUF_ProfileIO_TextureProbeRaw(path) == true
    if not exists and not (lower:match("%.tga$") or lower:match("%.blp$") or lower:match("%.png$")) then
        exists = MSUF_ProfileIO_TextureProbeRaw(path .. ".tga") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".blp") == true
            or MSUF_ProfileIO_TextureProbeRaw(path .. ".png") == true
    end
    MSUF_ProfileIO_TexturePathCache[path] = exists and true or false
    return MSUF_ProfileIO_TexturePathCache[path]
end

local function MSUF_ProfileIO_StatusbarTextureAvailable(key)
    if type(key) ~= "string" or key == "" then return true end
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" and MSUF_ProfileIO_TexturePathLoadable(builtins[key]) then
        return true
    end
    if key == "Solid" or key == "Blizzard" or key == "Flat" or key == "RaidHP" or key == "RaidPower" then
        return true
    end
    if MSUF_ProfileIO_LooksLikeMediaPath(key) then
        return MSUF_ProfileIO_TexturePathLoadable(key)
    end
    local lsm = MSUF_ProfileIO_GetLSM()
    if lsm and type(lsm.HashTable) == "function" then
        local bars = lsm:HashTable("statusbar")
        local path = bars and bars[key]
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    if lsm and type(lsm.Fetch) == "function" then
        local path = lsm:Fetch("statusbar", key, true)
        if MSUF_ProfileIO_TexturePathLoadable(path) then return true end
    end
    return false
end

local function MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, labelPrefix, keys)
    if type(scope) ~= "table" then return end
    for _, key in ipairs(keys) do
        local value = scope[key]
        if type(value) == "string" and value ~= "" and not MSUF_ProfileIO_StatusbarTextureAvailable(value) then
            MSUF_ProfileIO_AddImportWarning("texture", labelPrefix .. "." .. key, value)
        end
    end
end

local MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "castbarTexture",
    "castbarBackgroundTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS = {
    "classPowerTexture",
    "classPowerBgTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "playerHPBarTexture",
    "playerHPBarBgTexture",
}

local MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "powerBarTexture",
    "powerBarBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS = {
    "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
}

local MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS = {
    "barTexture",
    "barBackgroundTexture",
    "barBgTexture",
    "absorbBarTexture",
    "healAbsorbBarTexture",
}

local function MSUF_ProfileIO_CollectProfileMediaWarnings(profile)
    if type(profile) ~= "table" then return end
    local g = profile.general
    if type(g) == "table" then
        if type(g.fontKey) == "string" and g.fontKey ~= "" and not MSUF_ProfileIO_FontKeyAvailable(g.fontKey) then
            MSUF_ProfileIO_AddImportWarning("font", "general.fontKey", g.fontKey)
        end
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(g, "general", MSUF_PROFILEIO_GENERAL_TEXTURE_WARNING_KEYS)
    end
    local bars = profile.bars
    if type(bars) == "table" then
        MSUF_ProfileIO_CollectStatusbarTextureWarnings(bars, "bars", MSUF_PROFILEIO_BARS_TEXTURE_WARNING_KEYS)
    end
    for _, scopeKey in ipairs(MSUF_PROFILEIO_MEDIA_UNIT_SCOPE_KEYS) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_UNIT_TEXTURE_WARNING_KEYS)
        end
    end
    for _, scopeKey in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local scope = profile[scopeKey]
        if type(scope) == "table" then
            MSUF_ProfileIO_CollectStatusbarTextureWarnings(scope, scopeKey, MSUF_PROFILEIO_GROUP_TEXTURE_WARNING_KEYS)
        end
    end
end

ExportPublic("MSUF_ProfileIO_GetLastImportWarnings", function()
    return MSUF_ProfileIO_PublishImportWarnings()
end)

local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = Normalize.CURRENT_PROFILE_SCHEMA
local MSUF_PROFILEIO_UNIT_KEYS = Normalize.UNIT_KEYS
local MSUF_ProfileIO_NormalizeImportedFontSizes = Normalize.NormalizeImportedFontSizes
local MSUF_ProfileIO_NormalizeGFAuraFilterToken = Normalize.NormalizeGFAuraFilterToken

--- Deterministic-ish Lua serializer (good enough for UI copy/paste strings).

--- Key ownership for general settings lives in one registry
--- (State/MSUF_ProfileFields.lua, F.GeneralOwner): partial exports and imports
--- carry exactly the keys their kind owns, and profile sync asks the same owner.
local function MSUF_GeneralKeysOfKind(kind)
    local fields = MSUF.ProfileFields
    return function(key) return fields.GeneralKeyInKind(key, kind) end
end
--- Aura colour keys in general (owner auraColors in the registry); an import
--- that carries one refreshes every aura scope.
local MSUF_AURA_GENERAL_KEYS = {
aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}
-- Unified, coldpath alpha keys: HP fill opacity, power fill opacity, background
-- opacity, and opt-in exclusions for informational elements. They are unit
-- frame settings, not colours (the registry declares them unitframes).
local MSUF_UNITFRAME_ALPHA_KEYS = {
    hpBarAlpha = true,
    powerBarAlpha = true,
    hpBgAlpha = true,
    powerBarBgAlpha = true,
    alphaExcludeTextPortrait = true,
    alphaExcludePredictionBars = true,
}
local MSUF_UNITFRAME_ALPHA_DEFAULTS = {
    hpBarAlpha = 1,
    powerBarAlpha = 1,
    hpBgAlpha = 0.85,
    powerBarBgAlpha = 0.85,
    alphaExcludeTextPortrait = false,
    alphaExcludePredictionBars = false,
}
local MSUF_UNITFRAME_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local function MSUF_CopyGeneralSubset(filterFn, profile)
    local out = {}
    local g = ((profile or MSUF_DB) and (profile or MSUF_DB).general) or {}
    for k, v in pairs(g) do
        if filterFn(k, v) then
            out[k] = MSUF_DeepCopy(v)
        end
    end
     return out
end
--- db is the profile table an import stages into (never nil).
local function MSUF_WipeGeneralSubset(filterFn, db)
    if type(db.general) ~= "table" then
        db.general = {}
    end
    local g = db.general
    for k in pairs(g) do
        if filterFn(k, g[k]) then
            g[k] = nil
        end
    end
 end
--- Only the keys the import kind owns land: a payload that carries more (an
--- export from a build that guessed ownership by name) cannot overwrite keys
--- another kind or the receiving profile owns.
local function MSUF_ApplyGeneralSubset(tbl, db, filterFn)
    if not tbl then  return end
    if type(db.general) ~= "table" then
        db.general = {}
    end
    local g = db.general
    for k, v in pairs(tbl) do
        if filterFn(k, v) then
            g[k] = MSUF_DeepCopy(v)
        end
    end
 end
--- Legacy combat/layered alpha keys retired by the unified alpha rewrite. Imported
--- profiles may still carry them; strip them so they never resurrect the old model.
local MSUF_UNITFRAME_LEGACY_ALPHA_KEYS = {
    "alphaInCombat", "alphaOutOfCombat", "alphaSync", "alphaSyncBoth", "alphaLayerMode",
    "alphaFGInCombat", "alphaFGOutOfCombat", "alphaBGInCombat", "alphaBGOutOfCombat",
    "alphaHPInCombat", "alphaHPOutOfCombat", "alphaPreserveHPColor", "bgA", "hpTextIgnoreAlpha",
}
local function MSUF_ProfileIO_EnsureUnitframeAlphaDB(profile)
    profile = profile or _G.MSUF_DB
    if type(profile) ~= "table" then  return end
    local function ensureAlpha(conf)
        if type(conf) ~= "table" then  return end
        for i = 1, #MSUF_UNITFRAME_LEGACY_ALPHA_KEYS do
            conf[MSUF_UNITFRAME_LEGACY_ALPHA_KEYS[i]] = nil
        end
        for k, v in pairs(MSUF_UNITFRAME_ALPHA_DEFAULTS) do
            if conf[k] == nil then
                conf[k] = v
            end
        end
    end
    for _, unitKey in ipairs(MSUF_UNITFRAME_UNIT_KEYS) do
        if type(profile[unitKey]) ~= "table" then
            profile[unitKey] = {}
        end
        ensureAlpha(profile[unitKey])
    end
 end
local function MSUF_ProfileIO_EnsureGroupFramesDB()
    local ensureGF = _G.MSUF_GF_EnsureDB
    if type(ensureGF) == "function" then
        ensureGF()
        return
    end
    local gf = _G.MSUF_NS and _G.MSUF_NS.GF
    if gf and type(gf.EnsureDB) == "function" then
        gf.EnsureDB()
    end
end
local function MSUF_ProfileIO_EnsureCompleteProfileDB()
    MSUF_ProfileIO_RunEnsureDB()
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_EnsureGroupFramesDB()
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras then
        if type(auras.EnsureDB) == "function" then
            auras.EnsureDB()
        end
        local aurasDB = auras.DB
        if aurasDB and type(aurasDB.Ensure) == "function" then
            aurasDB.Ensure()
        end
    end
end
--- Variant recording takes its base only after this complete pass.
MSUF.ProfileIOEnsureCompleteProfileDB = MSUF_ProfileIO_EnsureCompleteProfileDB

--- Export normalization does not try to make the live DB pretty. It creates a
--- clean payload copy, translates old aliases, and strips runtime/cache-only
--- state so copied profile strings stay portable across characters and clients.
local MSUF_GF_BLIZZARD_TYPE_DEFAULTS = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
}

local function MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)
    if type(auras) ~= "table" then return end
    if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
    if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
    if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
end


local function MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end

    if group.filterToken == nil then
        local fm = group.filterMode
        if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
            group.filterToken = "ALL"
        elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
            group.filterToken = fm
        elseif fm == "NOT_PLAYER" then
            group.filterToken = "ALL"
        else
            group.filterToken = defaultToken
        end
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)

    -- No default categories: MSUF_GF_AuraFilter.DEFAULT_BLACKLIST_BUFF/DEBUFF,
    -- which this used to copy, are gone since 6.0 alpha 1 and read as nil.
    if type(group.blacklistCats) ~= "table" then
        group.blacklistCats = {}
    end
    if group.strata == nil then group.strata = "AUTO" end
    if groupKey == "buff" and group.trackedStrata == nil then group.trackedStrata = "AUTO" end
    if group.cooldownSwipeReverse == nil then group.cooldownSwipeReverse = false end
    if type(group.blacklist) ~= "table" then group.blacklist = {} end
    if type(group.blacklist.spells) ~= "table" then group.blacklist.spells = {} end
end

local function MSUF_ProfileIO_NormalizeGroupFrameForExport(conf)
    if type(conf) ~= "table" then return end
    if type(conf.auras) ~= "table" then return end

    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "NATIVE_12_1" then
        auras.renderer = "NATIVE_12_1"
    end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    for key, value in pairs(MSUF_GF_BLIZZARD_TYPE_DEFAULTS) do
        if auras.blizzardTypes[key] == nil then
            auras.blizzardTypes[key] = value
        end
    end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
    MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)

    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "buff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    if type(payload) ~= "table" then return payload end
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    return payload
end

local MSUF_PROFILEIO_WAGO_SCHEMA = 1
local MSUF_PROFILEIO_WAGO_FULL_KEY = "msuf6"
local MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS = {
    -- The dispel data-format stamps: without them an import of the portable
    -- payload runs both dispel migrations again (TOP -> ALL, By me -> Dispel type).
    _msufDispelPriorityMigration = true,
    _msufNativeDispelTriggerMigration = true,
    arena = true,
    profileVariants = true,
    auras2 = true,
    bars = true,
    boss = true,
    classColors = true,
    classPowerPerSpec = true,
    classPowerPresets = true,
    focus = true,
    gameplay = true,
    general = true,
    gf_mythicraid = true,
    gf_party = true,
    gf_priority = true,
    gf_raid = true,
    group = true,
    groupFrames = true,
    groupframes = true,
    npcColors = true,
    party = true,
    pet = true,
    pettarget = true,
    player = true,
    shortenNames = true,
    target = true,
    targettarget = true,
    tot = true,
}
local MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS = {
    buffGroupOffsetX = true,
    buffGroupOffsetY = true,
    debuffGroupOffsetX = true,
    debuffGroupOffsetY = true,
    buffGroupIconSize = true,
    debuffGroupIconSize = true,
    buffGrowthX = true,
    buffGrowthY = true,
    debuffGrowthX = true,
    debuffGrowthY = true,
    showCooldownText = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarHeight = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextAnchor = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    buffAnchor = true,
    debuffAnchor = true,
    -- buffLayer/debuffLayer intentionally remain portable. Some external tools
    -- keep only this compatibility payload and omit the embedded msuf6 table.
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
}

local function MSUF_ProfileIO_CopyIfMissingValue(tbl, toKey, ...)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil then return end
    for i = 1, select("#", ...) do
        local fromKey = select(i, ...)
        if tbl[fromKey] ~= nil then
            tbl[toKey] = MSUF_DeepCopy(tbl[fromKey])
            return
        end
    end
end

local function MSUF_ProfileIO_CopyMissingFrom(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if tbl[key] == nil then
            tbl[key] = MSUF_DeepCopy(value)
        end
    end
end

local function MSUF_ProfileIO_StripPrivateMSUFKeys(tbl, seen)
    if type(tbl) ~= "table" then return end
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true
    for key, value in pairs(tbl) do
        if type(key) == "string" and key:match("^_msuf") then
            tbl[key] = nil
        elseif type(value) == "table" then
            MSUF_ProfileIO_StripPrivateMSUFKeys(value, seen)
        end
    end
end

local function MSUF_ProfileIO_NormalizeAuraFilterForWago(filter)
    if type(filter) ~= "table" then return end
    filter.onlyImportantAuras = nil
    local function normalizeGroup(group)
        if type(group) ~= "table" then return end
        group.includeNameplateOnly = nil
        group.cancelable = nil
        group.notCancelable = nil
        group.externalDefensive = nil
        group.bigDefensive = nil
        group.exclusive = nil
        group.crowdControl = nil
        if group.filterToken == nil then
            group.filterToken = "ALL"
        end
    end
    normalizeGroup(filter.buffs)
    normalizeGroup(filter.debuffs)
end

local function MSUF_ProfileIO_NormalizeAuraLayoutForWago(layout, layoutShared)
    if type(layout) ~= "table" then return end
    MSUF_ProfileIO_CopyMissingFrom(layout, layoutShared)
    MSUF_ProfileIO_CopyIfMissingValue(layout, "iconSize", "buffGroupIconSize", "debuffGroupIconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffIconSize", "buffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffIconSize", "debuffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetX", "buffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetY", "buffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetX", "debuffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetY", "debuffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetX", "buffGroupOffsetX", "debuffGroupOffsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetY", "debuffGroupOffsetY", "buffGroupOffsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "growth", "buffGrowthX", "debuffGrowthX")
    if layout.layoutMode == "SEPARATE" then
        layout.layoutMode = "SINGLE"
    end
    for key in pairs(MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS) do
        layout[key] = nil
    end
end

local function MSUF_ProfileIO_NormalizeAurasForWago(auras)
    if type(auras) ~= "table" then return end
    MSUF_ProfileIO_StripPrivateMSUFKeys(auras)
    MSUF_ProfileIO_NormalizeAuraLayoutForWago(auras.shared)
    MSUF_ProfileIO_NormalizeAuraFilterForWago(auras.shared and auras.shared.filters)
    if type(auras.perUnit) == "table" then
        for _, unit in pairs(auras.perUnit) do
            if type(unit) == "table" then
                MSUF_ProfileIO_NormalizeAuraLayoutForWago(unit.layout, unit.layoutShared)
                unit.layoutShared = nil
                unit.overrideSharedLayout = nil
                MSUF_ProfileIO_NormalizeAuraFilterForWago(unit.filters)
            end
        end
    end
end

local function MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end
    if group.filterToken == nil then
        group.filterToken = defaultToken
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)
    if type(group.blacklist) == "table" then
        group.blacklist.spells = nil
    end
    group.cooldownSwipeReverse = nil
end

local function MSUF_ProfileIO_NormalizeGroupFrameForWago(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "BLIZZARD" then
        auras.renderer = "BLIZZARD"
    end
    if auras.renderer == nil then auras.renderer = "BLIZZARD" end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    for key, value in pairs(MSUF_GF_BLIZZARD_TYPE_DEFAULTS) do
        if auras.blizzardTypes[key] == nil then
            auras.blizzardTypes[key] = value
        end
    end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
    auras.blizzardContainerAnchor = "FRAME"
    auras.blizzardContainerX = 0
    auras.blizzardContainerY = 0
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "buff", "RAID")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_MakeWagoPayload(payload)
    if type(payload) ~= "table" then return {} end
    local out = {}
    for key, value in pairs(payload) do
        if MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS[key] then
            out[key] = MSUF_DeepCopy(value)
        end
    end
    if type(payload.auras3) == "table" then
        out.auras2 = MSUF_DeepCopy(payload.auras3)
    end
    out.auras3 = nil
    out.auras = nil
    out._msufProfileSchema = nil
    out._msufLegacyProfileSchema = nil
    MSUF_ProfileIO_NormalizeAurasForWago(out.auras2)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_mythicraid)
    return out
end

local function MSUF_ProfileIO_MakeWagoSnapshot(snapshot)
    if type(snapshot) ~= "table" or snapshot.kind ~= "all" or type(snapshot.payload) ~= "table" then
        return snapshot, false
    end
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_WAGO_SCHEMA,
        kind    = "all",
        profile = snapshot.profile,
        payload = MSUF_ProfileIO_MakeWagoPayload(snapshot.payload),
        [MSUF_PROFILEIO_WAGO_FULL_KEY] = {
            schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
            kind    = "all",
            profile = snapshot.profile,
            payload = MSUF_DeepCopy(snapshot.payload),
        },
    }, true
end

local function MSUF_ProfileIO_SelectWagoFullSnapshot(snapshot)
    if type(snapshot) ~= "table" then return snapshot end
    local full = snapshot[MSUF_PROFILEIO_WAGO_FULL_KEY]
    if type(full) == "table"
        and tonumber(full.schema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and type(full.payload) == "table" then
        return {
            addon   = "MSUF",
            fmt     = 2,
            schema  = full.schema,
            kind    = type(full.kind) == "string" and full.kind or snapshot.kind,
            profile = type(full.profile) == "string" and full.profile or snapshot.profile,
            payload = full.payload,
        }
    end
    return snapshot
end

local function MSUF_ProfileIO_SelectSupportedProfile(decoded)
    local policy = type(MSUF) == "table" and MSUF.ProfilePolicy or nil
    local selectSupported = type(policy) == "table" and policy.SelectSupportedDecodedProfile or nil
    if type(selectSupported) == "function" then
        return selectSupported(decoded)
    end
    if type(decoded) == "table"
        and tonumber(decoded._msufProfileSchema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
        return decoded
    end
    if type(decoded) == "table"
        and decoded.addon == "MSUF"
        and tonumber(decoded.fmt) == 2
        and tonumber(decoded.schema) == MSUF_PROFILEIO_WAGO_SCHEMA
        and type(decoded.kind) == "string"
        and type(decoded.payload) == "table"
        and decoded[MSUF_PROFILEIO_WAGO_FULL_KEY] == nil then
        return decoded
    end
    local snapshot = MSUF_ProfileIO_SelectWagoFullSnapshot(decoded)
    if type(snapshot) == "table"
        and snapshot.addon == "MSUF"
        and tonumber(snapshot.fmt) == 2
        and tonumber(snapshot.schema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and type(snapshot.kind) == "string"
        and type(snapshot.payload) == "table" then
        return snapshot
    end
    return nil
end

local function MSUF_CopyGroupFramePayload(profile)
    local MSUF_DB = profile or _G.MSUF_DB
    local payload = {}
    if type(MSUF_DB) ~= "table" then
        return payload
    end
    if type(MSUF_DB.gf_party) == "table" then
        payload.gf_party = MSUF_DeepCopy(MSUF_DB.gf_party)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    end
    if type(MSUF_DB.gf_raid) == "table" then
        payload.gf_raid = MSUF_DeepCopy(MSUF_DB.gf_raid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    end
    if type(MSUF_DB.gf_mythicraid) == "table" then
        payload.gf_mythicraid = MSUF_DeepCopy(MSUF_DB.gf_mythicraid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    end
    if type(MSUF_DB.gf_priority) == "table" then
        payload.gf_priority = MSUF_DeepCopy(MSUF_DB.gf_priority)
    end
    return payload
end
--- Blizzard Edit Mode data in profile strings is strictly opt-in, per
--- direction: exports never carry general.blizzardEditModeSnapshot and
--- imports never apply it unless the profiles-page switch is on. Both flags
--- are session-transient by design — the user decides per session.
local MSUF_ProfileIO_ExportBlizzardEM = false
local MSUF_ProfileIO_ImportBlizzardEM = false
local MSUF_ProfileIO_ExportVariants, MSUF_ProfileIO_ImportVariants = true, true
ExportPublic("MSUF_Profiles_SetExportVariants", function(value) MSUF_ProfileIO_ExportVariants=value==true end)
ExportPublic("MSUF_Profiles_SetImportVariants", function(value) MSUF_ProfileIO_ImportVariants=value==true end)
ExportPublic("MSUF_Profiles_SetExportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ExportBlizzardEM = value == true
end)
ExportPublic("MSUF_Profiles_SetImportBlizzardEditMode", function(value)
    MSUF_ProfileIO_ImportBlizzardEM = value == true
end)

-- Add a coordinate reference to export copies only. Older imports without the
-- explicit mode retain their saved offsets instead of being silently moved.
local function MSUF_ProfileIO_StampScreenReference(payload)
    local height = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(height) == true then return end
    if type(height) ~= "number" or height < 400 or height > 10000 then return end
    local function Stamp(conf)
        if type(conf) ~= "table" or (conf.offsetX == nil and conf.offsetY == nil
            and conf.x == nil and conf.y == nil) then return end
        if conf.screenPositionMode ~= nil and conf.screenPositionMode ~= "relativeHeight" then return end
        conf.screenPositionHeight = height
        conf.screenPositionMode = "relativeHeight"
    end
    for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
        Stamp(payload[MSUF_PROFILEIO_UNIT_KEYS[i]])
    end
    for i = 1, 5 do Stamp(payload["boss" .. i]) end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do Stamp(payload[key]) end
end

-- Selected-frame snapshots have a separate kind so older importers reject them
-- instead of treating them as the broad Unitframes category (which resets globals).
-- Only explicitly owned settings cross this boundary; shared appearance stays local.
local UnitSelection = {
    units = { player = true, target = true, targettarget = true, focustarget = true,
        focus = true, pet = true, boss = true, arena = true },
    auraFlags = { showPlayer = "player", showPet = "pet", showTarget = "target", showFocus = "focus",
        showBoss = "boss", showArena = "arena" },
    barKeys = { showPlayerPowerBar = "player", showTargetPowerBar = "target",
        showFocusPowerBar = "focus", showBossPowerBar = "boss", showArenaPowerBar = "arena" },
}
function UnitSelection.Supported(unit)
    return UnitSelection.units[unit] == true
        and (not MSUF.Client or not MSUF.Client.SupportsUnit or MSUF.Client.SupportsUnit(unit))
end
function UnitSelection.GeneralOwner(key)
    if type(key) ~= "string" then return nil end
    for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local title = unit:sub(1, 1):upper() .. unit:sub(2)
        if key:sub(1, #unit + 7) == "castbar" .. title
            or key:sub(1, #unit + 7) == unit .. "Castbar"
            or key:sub(1, #unit + 8) == "show" .. title .. "Cast"
            or key == "enable" .. title .. "Castbar"
            or ((unit == "boss" or unit == "arena") and key:sub(1, #unit + 4) == unit .. "Cast") then
            return unit
        end
    end
    if key == "castbarOpositeDirectionTarget" then return "target" end
    if key == "_msufBossCastbarPhysicalEdgeAnchor_v1" then return "boss" end
end
function UnitSelection.AuraOwner(key)
    if key == "player" or key == "pet" or key == "target" or key == "focus" then return key end
    if type(key) == "string" then
        if key:match("^boss[1-5]$") then return "boss" end
        if key:match("^arena[1-5]$") then return "arena" end
    end
end
function UnitSelection.ReplaceTable(parent, key, source)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    MSUF_WipeTable(parent[key])
    for k, v in pairs(source) do parent[key][k] = MSUF_DeepCopy(v) end
end
function UnitSelection.Copy(profile, selected)
    local payload = {}
    for unit in pairs(UnitSelection.units) do
        if selected[unit] == true then
            payload[unit] = MSUF_DeepCopy(profile[unit] or {})
        end
    end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        local out = {}
        for key, value in pairs(profile[spec[1]] or {}) do
            local owner = spec[2](key)
            if owner and selected[owner] then out[key] = MSUF_DeepCopy(value) end
        end
        payload[spec[1]] = out
    end
    local auras = profile.auras3 or {}
    local out = { perUnit = {} }
    for flag, unit in pairs(UnitSelection.auraFlags) do
        if selected[unit] then
            out[flag] = auras[flag] == true or (flag == "showPet" and auras[flag] == nil)
            local count = (unit == "boss" or unit == "arena") and 5 or 1
            for i = 1, count do
                local key = count == 1 and unit or unit .. i
                out.perUnit[key] = MSUF_DeepCopy(auras.perUnit and auras.perUnit[key] or {})
            end
        end
    end
    if next(out.perUnit) then payload.auras3 = out end
    return payload
end
--- A rejection returns the English reason plus its template and the inserted
--- key, so the import chat line can translate the whole sentence first.
function UnitSelection.Reject(template, key)
    key = tostring(key)
    return nil, template:format(key), template, key
end
function UnitSelection.Validate(payload)
    local selected = {}
    for key, value in pairs(payload) do
        if UnitSelection.units[key] then
            if not UnitSelection.Supported(key) then return UnitSelection.Reject("unsupported unitframe: %s", key) end
            if type(value) ~= "table" then return UnitSelection.Reject("invalid unitframe: %s", key) end
            selected[key] = true
        elseif key ~= "general" and key ~= "bars" and key ~= "auras3" then
            return UnitSelection.Reject("unexpected selected-frame setting: %s", key)
        elseif type(value) ~= "table" then
            return UnitSelection.Reject("invalid selected-frame settings: %s", key)
        end
    end
    if not next(selected) then return nil, "select at least one unitframe" end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        for key in pairs(payload[spec[1]] or {}) do
            local owner = spec[2](key)
            if not owner or not selected[owner] then
                return UnitSelection.Reject("setting outside selected unitframes: %s", key)
            end
        end
    end
    for key, value in pairs(payload.auras3 or {}) do
        if key == "perUnit" and type(value) == "table" then
            for unit, conf in pairs(value) do
                local owner = UnitSelection.AuraOwner(unit)
                if not owner or not selected[owner] or type(conf) ~= "table" then
                    return UnitSelection.Reject("aura settings outside selected unitframes: %s", unit)
                end
            end
        elseif not UnitSelection.auraFlags[key] or not selected[UnitSelection.auraFlags[key]]
            or type(value) ~= "boolean" then
            return UnitSelection.Reject("unexpected selected-frame aura setting: %s", key)
        end
    end
    return selected
end
function UnitSelection.Commit(payload, selected, db)
    for unit in pairs(selected) do UnitSelection.ReplaceTable(db, unit, payload[unit]) end
    for _, spec in ipairs({ { "general", UnitSelection.GeneralOwner },
        { "bars", function(key) return UnitSelection.barKeys[key] end } }) do
        local root = spec[1]
        if type(db[root]) ~= "table" then db[root] = {} end
        for key in pairs(db[root]) do
            local owner = spec[2](key)
            if owner and selected[owner] then db[root][key] = nil end
        end
        for key, value in pairs(payload[root] or {}) do db[root][key] = MSUF_DeepCopy(value) end
    end
    if payload.auras3 then
        if type(db.auras3) ~= "table" then db.auras3 = {} end
        local auras = db.auras3
        if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
        for key, value in pairs(payload.auras3) do
            if key == "perUnit" then
                for unit, conf in pairs(value) do UnitSelection.ReplaceTable(auras.perUnit, unit, conf) end
            else
                auras[key] = value
            end
        end
    end
end

local function MSUF_SnapshotForKind(kind, selectedUnits)
    if Variants and Variants.IsRecording() then return nil end
    MSUF_ProfileIO_EnsureCompleteProfileDB()
    local MSUF_DB
    if Variants then MSUF_DB=Variants.BaseSnapshot(_G.MSUF_DB,true) else MSUF_DB=_G.MSUF_DB end
    if type(MSUF_DB)~="table" then return nil end
    local payload = {}
    if kind == "unitselection" then
        if type(selectedUnits) ~= "table" then return nil end
        local selected = {}
        for unit, enabled in pairs(selectedUnits) do
            if enabled == true then
                if not UnitSelection.Supported(unit) then return nil end
                selected[unit] = true
            end
        end
        if not next(selected) then return nil end
        payload = UnitSelection.Copy(MSUF_DB, selected)
    elseif kind == "unitframe" then
        --- Everything EXCEPT: gameplay, colors, castbars
        for k, v in pairs(MSUF_DB or {}) do
            if k == "general" then
                payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("unitframe"), MSUF_DB)
            elseif k == "classColors" or k == "npcColors" or k == "gameplay" then
                --- exclude
            else
                payload[k] = MSUF_DeepCopy(v)
            end
        end
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    elseif kind == "castbar" then
        payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("castbar"), MSUF_DB)
    elseif kind == "colors" then
        payload.general = MSUF_CopyGeneralSubset(MSUF_GeneralKeysOfKind("colors"), MSUF_DB)
        payload.classColors = MSUF_DeepCopy((MSUF_DB and MSUF_DB.classColors) or {})
        payload.npcColors   = MSUF_DeepCopy((MSUF_DB and MSUF_DB.npcColors) or {})
    elseif kind == "gameplay" then
        payload.gameplay = MSUF_DeepCopy((MSUF_DB and MSUF_DB.gameplay) or {})
    elseif kind == "groupframe" or kind == "groupframes" then
        payload = MSUF_CopyGroupFramePayload(MSUF_DB)
    elseif kind == "all" then
        payload = MSUF_DeepCopy(MSUF_DB or {})
        MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    else
         return nil
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    if kind~="all" or not MSUF_ProfileIO_ExportVariants then payload.profileVariants=nil end
    if type(payload.general) == "table" then
        payload.general.blizzardEditModeSnapshot = nil
    end
    if kind == "all" and MSUF_ProfileIO_ExportBlizzardEM then
        local blizzSnapshot = type(MSUF_DB) == "table" and type(MSUF_DB.general) == "table"
            and MSUF_DB.general.blizzardEditModeSnapshot or nil
        if type(blizzSnapshot) == "table" then
            if type(payload.general) ~= "table" then payload.general = {} end
            payload.general.blizzardEditModeSnapshot = MSUF_DeepCopy(blizzSnapshot)
        end
    end
    if kind == "unitselection" or kind == "unitframe" or kind == "groupframe"
        or kind == "groupframes" or kind == "all" then
        MSUF_ProfileIO_StampScreenReference(payload)
    end
    return {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = kind,
        profile = MSUF_ActiveProfile or "Default",
        payload = payload,
    }
end

local function MSUF_ProfileIO_AuraImportScopes(payload)
    if type(payload) ~= "table" then
        return nil, false
    end

    local g = payload.general
    if type(g) == "table" then
        for k in pairs(MSUF_AURA_GENERAL_KEYS) do
            if g[k] ~= nil then
                return nil, true
            end
        end
    end

    local auras = payload.auras3
    if type(auras) ~= "table" then
        return nil, false
    end

    local scopes, seen = {}, {}
    local function AddScope(scope)
        scope = tostring(scope or "")
        if scope ~= "" and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end

    for key, value in pairs(auras) do
        if key == "perUnit" and type(value) == "table" then
            for unit, conf in pairs(value) do
                if type(conf) == "table" then
                    AddScope(unit)
                end
            end
        else
            return nil, true
        end
    end

    if #scopes > 0 then
        return scopes, false
    end
    return nil, true
end
--- After a profile import we must explicitly refresh Auras/Auras3 so the live UI matches without /reload.
--- Keep this scoped (Auras only) to avoid unintended regressions in other modules.
local function MSUF_ProfileIO_PostImportApply_Auras(kind, payload)
    if not payload then  return end
    local scopes, full = MSUF_ProfileIO_AuraImportScopes(payload)
    if not full and not scopes then  return end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if not full and scopes then
        local called = false
        for i = 1, #scopes do
            local scope = scopes[i]
            if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
                a3.ApplyFontsFromGlobal(scope, "MSUF_PROFILE_IMPORT_AURAS")
                called = true
            elseif a3 and type(a3.RequestScope) == "function" then
                a3.RequestScope(scope, "MSUF_PROFILE_IMPORT_AURAS")
                called = true
            elseif a3 and type(a3.RefreshUnit) == "function" then
                a3.RefreshUnit(scope)
                called = true
            else
                full = true
                break
            end
        end
        if called and not full then
            return
        end
    end
    if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
        a3.ApplyFontsFromGlobal(nil, "MSUF_PROFILE_IMPORT_AURAS")
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end
end
local function MSUF_ProfileIO_PostImportApply_GroupFrames(kind, payload)
    if type(payload) ~= "table" then  return end
    local touchedKinds, seenKinds = {}, {}
    local function AddKind(groupKind)
        if groupKind and not seenKinds[groupKind] then
            seenKinds[groupKind] = true
            touchedKinds[#touchedKinds + 1] = groupKind
        end
    end
    if type(payload.gf_party) == "table" then AddKind("party") end
    if type(payload.gf_raid) == "table" then AddKind("raid") end
    if type(payload.gf_mythicraid) == "table" then AddKind("mythicraid") end
    if type(payload.gf_priority) == "table" then AddKind("priority") end
    local touched = (kind == "groupframe") or (kind == "groupframes")
    if not touched then
        touched = (#touchedKinds > 0)
    end
    if not touched then  return end
    if #touchedKinds == 0 then
        AddKind("party")
        AddKind("raid")
        AddKind("mythicraid")
        AddKind("priority")
    end
    MSUF_ProfileIO_EnsureGroupFramesDB()
    -- No blacklist hash flush: MSUF_GF_AuraFilter.BuildBlacklistHash re-checks
    -- each group's blacklist signature on every call (and
    -- InvalidateAllBlacklistHashes, called here before, exists nowhere).
    -- Group frames load after this file; Kernel/MSUF_RuntimeContracts.lua
    -- requires this provider once the core TOC has loaded.
    MSUF.Require("MSUF_GF_InvalidateConfCache", "State/MSUF_Profiles.lua")()
    local gf = (type(MSUF) == "table" and MSUF.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF)
    if gf and type(gf.Rebuild) == "function" then
        local rebuilt = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            gf.Rebuild(groupKind)
            rebuilt = true
        end
        if rebuilt then return end
    elseif gf and type(gf.RefreshGeometry) == "function" then
        local refreshed = false
        for i = 1, #touchedKinds do
            local groupKind = touchedKinds[i]
            gf.RefreshGeometry(groupKind)
            refreshed = true
            if type(gf.RefreshUnitBindings) == "function" then
                gf.RefreshUnitBindings(groupKind)
            end
            if type(gf.RefreshVisuals) == "function" then
                gf.RefreshVisuals(groupKind, gf.DIRTY_ALL or gf.DIRTY_CONFIG or gf.DIRTY_VISUAL)
            end
        end
        if refreshed then return end
    elseif gf and type(gf.RequestAuraRefresh) == "function" then
        gf.RequestAuraRefresh()
    elseif gf and type(gf.MarkAllDirty) == "function" then
        gf.MarkAllDirty(gf.DIRTY_AURAS or gf.DIRTY_ALL or 0x3F)
    end
end
local function MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
    if type(payload) ~= "table" then  return end
    local full = (kind == "all")
    local touchedUnits, seenUnits = {}, {}
    local function AddUnit(unitKey)
        unitKey = tostring(unitKey or "")
        if unitKey == "tot" then unitKey = "targettarget" end
        if unitKey ~= "" and not seenUnits[unitKey] then
            seenUnits[unitKey] = true
            touchedUnits[#touchedUnits + 1] = unitKey
        end
    end
    for _, unitKey in ipairs(MSUF_UNITFRAME_UNIT_KEYS) do
        local conf = payload[unitKey]
        if type(conf) == "table" then
            for alphaKey in pairs(MSUF_UNITFRAME_ALPHA_KEYS) do
                if conf[alphaKey] ~= nil then
                    AddUnit(unitKey)
                    break
                end
            end
        end
    end
    if type(payload.tot) == "table" then
        for alphaKey in pairs(MSUF_UNITFRAME_ALPHA_KEYS) do
            if payload.tot[alphaKey] ~= nil then
                AddUnit("targettarget")
                break
            end
        end
    end
    if not full and #touchedUnits == 0 then  return end
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    local refresh = _G.MSUF_RefreshAllUnitAlphas or _G.MSUF_RequestAlphaRefresh
    if type(refresh) == "function" then
        if full then
            refresh()
        else
            for i = 1, #touchedUnits do refresh(touchedUnits[i]) end
        end
    end
end
--- Import failure chat lines. Every fixed reason the import path prints has a
--- full-sentence key in the language packs: the sentence is translated whole,
--- a frame key or value type goes in after, and the chat tag goes in front.
--- Callers keep receiving the English reason. Any other reason keeps the
--- translated-reason route: the profile variant reasons have their own keys,
--- and the parser's byte-position errors are built at runtime and stay English.
local IMPORT_FAILED_SENTENCES = {}
for _, sentence in ipairs({
    "Import failed: could not decode compact profile string (%s).",
    -- the table-literal parser (State/MSUF_ProfileCodec.lua)
    "Import failed: profile import is too large",
    "Import failed: unterminated comment",
    "Import failed: profile table has too many values",
    "Import failed: unterminated string",
    "Import failed: unterminated escape",
    "Import failed: invalid decimal escape",
    "Import failed: unsupported string escape",
    "Import failed: invalid number",
    "Import failed: profile table is too deep",
    "Import failed: unterminated table",
    "Import failed: unsupported table key",
    "Import failed: unsupported value",
    "Import failed: profile import must contain a table",
    -- the schema stamp and the snapshot kind
    "Import failed: MSUF 6.x profile required (schema 600).",
    "Import failed: unknown kind",
    -- the value validator: snapshot, then full profile
    "Import failed: profile has too many values",
    "Profile import failed: profile has too many values",
    "Import failed: profile strings are too large",
    "Profile import failed: profile strings are too large",
    "Import failed: profile contains an invalid number",
    "Profile import failed: profile contains an invalid number",
    "Import failed: profile contains unsupported %s",
    "Profile import failed: profile contains unsupported %s",
    "Import failed: profile is too deep",
    "Profile import failed: profile is too deep",
    "Import failed: profile contains a cyclic or shared table",
    "Profile import failed: profile contains a cyclic or shared table",
    "Import failed: profile contains an unsupported table key",
    "Profile import failed: profile contains an unsupported table key",
    -- UnitSelection.Validate
    "Import failed: unsupported unitframe: %s.",
    "Import failed: invalid unitframe: %s.",
    "Import failed: unexpected selected-frame setting: %s.",
    "Import failed: invalid selected-frame settings: %s.",
    "Import failed: select at least one unitframe.",
    "Import failed: setting outside selected unitframes: %s.",
    "Import failed: aura settings outside selected unitframes: %s.",
    "Import failed: unexpected selected-frame aura setting: %s.",
    -- the live profile's base snapshot (Variants.BaseSnapshot)
    "Import failed: profile contains a value that cannot be saved",
    "Import failed: profile contains a table that refers to itself",
    "Import failed: profile exceeds snapshot limits",
    "Import failed: an add-on part of the profile could not be copied",
}) do IMPORT_FAILED_SENTENCES[sentence] = true end
local function ImportFailedLine(text, reason, template, inserted)
    local sentence = text:format(tostring(template or reason))
    if IMPORT_FAILED_SENTENCES[sentence] then
        return ProfileChatLine("error", sentence, inserted ~= nil and tostring(inserted) or nil)
    end
    return ProfileChatLine("error", text, Translate(tostring(reason)))
end
--- Import transaction, step 1 of 3: decode, select, validate and stage.
--- Runs before anything is written. It performs no SavedVariables writes, no
--- ExportPublic and no prints, so every rejection (including a truncated
--- string pasted into new-profile import) leaves the stored profiles
--- untouched. The codec returns nil for bytes the native decoders reject
--- (native CBOR raises into the Kernel boundary), so a garbled string is an
--- ordinary rejection here. mode is "active" (current or new profile) or
--- "external" (MSUF_ImportExternal). Returns a plan table, or nil plus reason
--- plus (active mode) the exact chat line the pre-transaction entry points
--- printed for that rejection. External reasons keep their old strings too.
local function MSUF_ProfileIO_PrepareImport(str, mode)
    local external = (mode == "external")
    if type(str) ~= "string" or not str:match("%S") then
        return nil, "empty string", ProfileChatLine("error", "Import failed (empty string).")
    end
    local decoded, why
    local tryDec = _G.MSUF_TryDecodeCompactString
    if type(tryDec) == "function" then
        decoded = tryDec(str)
    end
    if type(decoded) ~= "table" then
        --- A compact MSUF2/MSUF3/MSUF4 string that failed to decode is NEVER
        --- retried as a table literal.
        local prefix = str:match("^%s*(MSUF%d+):")
        if prefix == "MSUF2" or prefix == "MSUF3" or prefix == "MSUF4" then
            why = "could not decode compact profile string (" .. prefix .. ")"
            return nil, why, ImportFailedLine("Import failed: %s.", why, "could not decode compact profile string (%s)", prefix)
        end
        decoded, why = MSUF.ProfileIOParseTableLiteral(str)
        if type(decoded) ~= "table" then
            if external then return nil, "invalid lua table string" end
            -- Byte-position parse errors ("expected = at byte 12") are built at runtime and stay English.
            return nil, tostring(why), ImportFailedLine("Import failed: %s", why)
        end
    end
    --- Source-client stamp: `decoded` is still the raw decoded envelope here.
    --- A reader of the exporting client's stamp belongs at this point, before
    --- SelectSupportedProfile rebuilds or drops the envelope.
    local selected = MSUF_ProfileIO_SelectSupportedProfile(decoded)
    local schemaWhy = "MSUF 6.x profile required (schema 600)"
    if type(selected) ~= "table" then
        return nil, schemaWhy, ImportFailedLine("Import failed: %s.", schemaWhy)
    end
    local isSnapshot = selected.addon == "MSUF" and tonumber(selected.fmt) == 2
        and type(selected.payload) == "table" and type(selected.kind) == "string"
    --- Rejection order follows the pre-transaction entry points: external
    --- import rejects any snapshot that is not kind "all" before validating,
    --- and an active full profile checks its schema stamp before validating.
    if isSnapshot and external and selected.kind ~= "all" then
        return nil, "external import requires a full profile snapshot"
    end
    if not isSnapshot and not external
        and tonumber(selected._msufProfileSchema) ~= MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
        return nil, schemaWhy, ImportFailedLine("Import failed: %s.", schemaWhy)
    end
    local valid, validationError, validationTemplate, validationType = MSUF.ProfileIOValidateImportValue(selected)
    if not valid then
        return nil, validationError, ImportFailedLine(isSnapshot and "Import failed: %s" or "Profile import failed: %s",
            validationError, validationTemplate, validationType)
    end
    local staged = MSUF_DeepCopy(selected)
    local plan = {
        isSnapshot = isSnapshot,
        schema = staged.schema,
    }
    local kind
    if plan.isSnapshot then
        kind = staged.kind
        if kind == "groupframes" then
            kind = "groupframe"
        end
        if kind ~= "unitselection" and kind ~= "unitframe" and kind ~= "groupframe" and kind ~= "castbar"
            and kind ~= "colors" and kind ~= "gameplay" and kind ~= "all" then
            return nil, "unknown kind", ImportFailedLine("Import failed: %s", "unknown kind")
        end
        plan.snapshotKind, plan.payload = staged.kind, staged.payload
    else
        kind = "all"
        plan.payload = staged
    end
    plan.kind = kind
    local payload = plan.payload
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    --- Variants that will not be imported are dropped before validation, so
    --- a string is never rejected for data the import leaves behind.
    if kind~="all" or not MSUF_ProfileIO_ImportVariants then payload.profileVariants=nil end
    if payload.profileVariants~=nil and Variants then
        local clean,variantError=Variants.ValidateForProfile(payload,payload.profileVariants)
        if not clean then
            return nil, variantError, ImportFailedLine("Import failed: %s", variantError)
        end
        payload.profileVariants=clean
    end
    if kind == "unitselection" then
        local selectedUnits, selectionError, selectionTemplate, selectionKey = UnitSelection.Validate(payload)
        if not selectedUnits then
            return nil, selectionError, ImportFailedLine("Import failed: %s.", selectionError, selectionTemplate, selectionKey)
        end
        -- Normalize untrusted frame data, then project it back onto its explicit
        -- owners. Normalizers may seed shared defaults; those must never travel.
        -- A selected aura scope is already the current per-unit model. It has no
        -- global model marker, so never feed it to the full-profile aura resetter.
        local selectedAuras = payload.auras3
        payload.auras3 = nil
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "unitselection_import", markProfile = false, createGeneral = false,
        })
        payload.auras3 = selectedAuras
        for _, conf in pairs(selectedAuras and selectedAuras.perUnit or {}) do
            StateHelpers.NormalizeAuraLayoutTable(conf.layout, StateHelpers.ProfileIOSpec)
            StateHelpers.NormalizeAuraLayoutTable(conf.layoutShared, StateHelpers.ProfileIOSpec)
        end
        plan.payload = UnitSelection.Copy(payload, selectedUnits)
        plan.selectedUnits = selectedUnits
        MSUF_ProfileIO_CollectProfileMediaWarnings(plan.payload)
        return plan
    end
    if mode == "external" then
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "external_import",
            markProfile = true,
        })
        -- State/MSUF_Defaults.lua also owns the portrait render and dispel
        -- priority migrations an external import runs after the translator.
        MSUF.Require("MSUF_NormalizePortraitRenderDB", "State/MSUF_Profiles.lua")(payload)
        MSUF.Require("MSUF_MigrateDispelPriorityProfile", "State/MSUF_Profiles.lua")(payload, true)
    elseif not plan.isSnapshot then
        MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
            source = "profile_import",
            markProfile = true,
        })
        if not MSUF_ProfileIO_ImportBlizzardEM and type(payload.general) == "table" then
            payload.general.blizzardEditModeSnapshot = nil
        end
    else
        --- Opt-in gate for imported Blizzard Edit Mode data: stripped before the
        --- merge unless the profiles-page switch is on, so a foreign string can
        --- never silently rearrange the local Blizzard HUD.
        if not MSUF_ProfileIO_ImportBlizzardEM and type(payload.general) == "table" then
            payload.general.blizzardEditModeSnapshot = nil
        end
        if kind == "unitframe" or kind == "groupframe" or kind == "all" then
            MSUF_ProfileIO_TranslateProfileToCurrent(payload, {
                source = "snapshot_import",
                schema = plan.schema,
                markProfile = (kind == "all"),
                createGeneral = (kind == "all") or type(payload.general) == "table",
                normalizePositions = (kind == "unitframe" or kind == "all"),
            })
        else
            MSUF_ProfileIO_NormalizeImportedFontSizes(payload)
        end
    end
    MSUF_ProfileIO_CollectProfileMediaWarnings(payload)
    return plan
end
--- Import transaction, step 2 of 3: stage the complete profile the commit
--- will install and run every normalizer over it: the forced defaults pass,
--- the unit alpha keys, the group-frame repair and the aura model. Nothing
--- live is written here. A payload a normalizer cannot digest raises while
--- every stored profile is still untouched, so a malformed string can never
--- leave a half-written profile behind that fails again at every login.
--- base is the target profile's current content: the active profile's base
--- snapshot, a new profile's factory table, or the stored external target.
--- Partial kinds merge into a private copy of it; full kinds only take its
--- local variants while variant import is off.
local ImportTx = {}
function ImportTx.Merge(kind, payload, db)
    if kind == "unitframe" then
        --- Wipe & replace the same general-key set that Unitframes export.
        local owned = MSUF_GeneralKeysOfKind("unitframe")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
        for k, v in pairs(payload) do
            if k ~= "general" then
                if type(v) == "table" then
                    if type(db[k]) ~= "table" then
                        db[k] = {}
                    end
                    MSUF_WipeTable(db[k])
                    for kk, vv in pairs(v) do
                        db[k][kk] = MSUF_DeepCopy(vv)
                    end
                else
                    db[k] = v
                end
            end
        end
    elseif kind == "groupframe" then
        for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }) do
            local value = payload[key]
            if type(value) == "table" then
                if type(db[key]) ~= "table" then
                    db[key] = {}
                end
                MSUF_WipeTable(db[key])
                for kk, vv in pairs(value) do
                    db[key][kk] = MSUF_DeepCopy(vv)
                end
            elseif value ~= nil then
                db[key] = MSUF_DeepCopy(value)
            end
        end
    elseif kind == "castbar" then
        local owned = MSUF_GeneralKeysOfKind("castbar")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
    elseif kind == "colors" then
        local owned = MSUF_GeneralKeysOfKind("colors")
        MSUF_WipeGeneralSubset(owned, db)
        if type(payload.general) == "table" then
            MSUF_ApplyGeneralSubset(payload.general, db, owned)
        end
        if type(db.classColors) ~= "table" then db.classColors = {} end
        if type(db.npcColors) ~= "table" then db.npcColors = {} end
        MSUF_WipeTable(db.classColors)
        MSUF_WipeTable(db.npcColors)
        if type(payload.classColors) == "table" then
            for kk, vv in pairs(payload.classColors) do
                db.classColors[kk] = MSUF_DeepCopy(vv)
            end
        end
        if type(payload.npcColors) == "table" then
            for kk, vv in pairs(payload.npcColors) do
                db.npcColors[kk] = MSUF_DeepCopy(vv)
            end
        end
    elseif kind == "gameplay" then
        if type(db.gameplay) ~= "table" then db.gameplay = {} end
        MSUF_WipeTable(db.gameplay)
        if type(payload.gameplay) == "table" then
            for kk, vv in pairs(payload.gameplay) do
                db.gameplay[kk] = MSUF_DeepCopy(vv)
            end
        end
    end
end
function ImportTx.Stage(plan, base)
    local kind, payload = plan.kind, plan.payload
    local candidate
    if kind == "unitselection" then
        --- Defaults can migrate unrelated categories. Repair a private
        --- candidate; the commit copies only the selected owners back.
        candidate = MSUF_DeepCopy(base)
        UnitSelection.Commit(payload, plan.selectedUnits, candidate)
        _G.MSUF_NormalizeProfileDefaults(candidate, true)
        MSUF_ProfileIO_EnsureUnitframeAlphaDB(candidate)
        plan.selection = UnitSelection.Copy(candidate, plan.selectedUnits)
        return candidate
    end
    if kind == "all" then
        candidate = MSUF_DeepCopy(payload)
        if not MSUF_ProfileIO_ImportVariants then
            candidate.profileVariants = MSUF_DeepCopy(base.profileVariants)
        end
    else
        candidate = MSUF_DeepCopy(base)
        ImportTx.Merge(kind, payload, candidate)
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(candidate) end
    _G.MSUF_NormalizeProfileDefaults(candidate, true)
    MSUF_ProfileIO_EnsureUnitframeAlphaDB(candidate)
    --- The group-frame and aura modules load after this file; the import
    --- refreshes below treat them as optional the same way.
    local gf, auras = MSUF.GF, MSUF.MSUF_Auras3
    if type(gf) == "table" and type(gf.RepairGroupDB) == "function" then gf.RepairGroupDB(candidate) end
    if type(auras) == "table" and type(auras.NormalizeProfileDB) == "function" then auras.NormalizeProfileDB(candidate) end
    --- Local variants kept across a full import are checked against the new
    --- settings they will overlay. They stay stored either way (they are the
    --- user's data); a mismatch is reported once after the commit.
    if kind == "all" and not MSUF_ProfileIO_ImportVariants and candidate.profileVariants ~= nil and Variants then
        local clean, why = Variants.ValidateForProfile(candidate, candidate.profileVariants)
        if clean then candidate.profileVariants = clean else plan.keptVariantsProblem = why end
    end
    plan.candidate = candidate
    return candidate
end
--- Base content of the active profile for staging: the base snapshot (never
--- a live variant overlay). A full import with variant import on needs none.
function ImportTx.LiveBase(plan)
    MSUF_ProfileIO_RunEnsureDB()
    if plan.kind == "all" and MSUF_ProfileIO_ImportVariants then return {} end
    if type(MSUF_DB) ~= "table" then return {} end
    if Variants then return Variants.BaseSnapshot(MSUF_DB, true) end
    return MSUF_DeepCopy(MSUF_DB)
end
--- A new profile starts from the same factory table MSUF_CreateProfile
--- builds, repaired the way the following profile switch repairs it.
function ImportTx.FactoryBase()
    local create = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile)
        or _G.MSUF_CreateFactoryDefaultProfile
    local profile = type(create) == "function" and create() or nil
    if type(profile) ~= "table" then return nil end
    MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
        source = "profile_create",
        trustNormalizationMarker = true,
    })
    MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    _G.MSUF_NormalizeProfileDefaults(profile, false, true)
    return profile
end
function ImportTx.ReportKeptVariants(plan)
    if not plan.keptVariantsProblem then return end
    ProfileChat("note", "Your profile variants were kept, but they do not match the imported settings and stay inactive (%s).",
        Translate(tostring(plan.keptVariantsProblem)))
end
--- Import transaction, step 3 of 3: swap the staged candidate into the active
--- profile. Everything that can reject a string or raise already ran on the
--- private candidate, so this step has no failure return.
local function MSUF_ProfileIO_CommitImportToActiveProfile(plan)
    --- Pending edits reach the other sync members first; the imported
    --- settings themselves stay in this profile (re-based below).
    if ProfileSync then ProfileSync.Flush() end
    PrepareProfileMutation()
    local kind, payload = plan.kind, plan.payload
    --- Always keep the profile-table reference stable (important!).
    --- Do not replace MSUF_DB with a new table here. Runtime modules keep
    --- references into the active profile and are invalidated by the apply hook.
    if type(MSUF_DB) ~= "table" then
        MSUF_DB = {}
    end
    if kind == "unitselection" then
        UnitSelection.Commit(plan.selection, plan.selectedUnits, MSUF_DB)
    else
        --- The staged candidate is private and fully normalized: move its
        --- values over without another copy.
        MSUF_WipeTable(MSUF_DB)
        for k, v in pairs(plan.candidate) do
            MSUF_DB[k] = v
        end
    end
    --- Ensure the active profile table in GlobalDB points to MSUF_DB.
    if type(MSUF_GlobalDB) == "table" and type(MSUF_GlobalDB.profiles) == "table" and MSUF_ActiveProfile then
        MSUF_GlobalDB.profiles[MSUF_ActiveProfile] = MSUF_DB
    end
    if kind ~= "unitselection" then
        MSUF_ProfileIO_RunEnsureDB(true)
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    end
    if ProfileSync then ProfileSync.Rebase() end
    if not plan.isSnapshot then
        MSUF.ProfileIOCompleteFirstLoadImport()
        MSUF_ProfileIO_PostImportApply_Auras("all", payload)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", payload)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", payload)
        if MSUF.Client and MSUF.Client.SupportsBlizzardEditMode and type(payload.general) == "table"
            and type(payload.general.blizzardEditModeSnapshot) == "table" then
            _G.MSUF_BlizzardEditMode_ApplyProfileSnapshot()
        end
        ApplyProfileRuntime("PROFILE_IMPORT", true)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_IMPORT", MSUF_ActiveProfile)
        ImportTx.ReportKeptVariants(plan)
        return true
    end
    MSUF_ProfileIO_PostImportApply_Auras(plan.snapshotKind, payload)
    MSUF_ProfileIO_PostImportApply_GroupFrames(plan.snapshotKind, payload)
    MSUF_ProfileIO_PostImportApply_UnitAlphas(kind, payload)
    if MSUF.Client and MSUF.Client.SupportsBlizzardEditMode and type(payload.general) == "table"
        and type(payload.general.blizzardEditModeSnapshot) == "table" then
        _G.MSUF_BlizzardEditMode_ApplyProfileSnapshot()
    end
    ApplyProfileRuntime("PROFILE_IMPORT", true)
    MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_IMPORT", MSUF_ActiveProfile)
    MSUF.ProfileIOCompleteFirstLoadImport()
    ImportTx.ReportKeptVariants(plan)
    return true
end
function MSUF_ExportSelectionToString(kind, selectedUnits)
    local snap = MSUF_SnapshotForKind(kind, selectedUnits)
    if not snap then return nil end
    local exportSnap, wagoExport = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    if wagoExport then
        return _G.MSUF_EncodeCompactTableMSUF3(exportSnap)
    end
    return _G.MSUF_EncodeCompactTable(snap)
end

--- Imports schema-600 MSUF2/MSUF3/MSUF4 strings or safe text snapshots into
--- the active profile. Returns true, or false plus the rejection reason.
function MSUF_ImportFromString(str)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    MSUF_ProfileIO_ResetImportWarnings()
    local plan, why, chatLine = MSUF_ProfileIO_PrepareImport(str, "active")
    if not plan then
        print(chatLine)
        return false, why
    end
    local base, baseWhy = ImportTx.LiveBase(plan)
    if not base then
        chatLine = ImportFailedLine("Import failed: %s", baseWhy)
        print(chatLine)
        return false, baseWhy
    end
    ImportTx.Stage(plan, base)
    MSUF_ProfileIO_CommitImportToActiveProfile(plan)
    if plan.isSnapshot then
        ProfileChat("ok", "Imported %s settings into the active profile.", tostring(plan.snapshotKind))
    else
        ProfileChat("ok", "Profile imported into the active profile.")
    end
    MSUF_ProfileIO_ReportImportWarnings()
    return true
end
--- Imports a string into a new profile and switches to it. The string is
--- decoded, validated, staged and normalized BEFORE the profile is created or
--- switched, so a rejected string creates nothing, switches nothing and
--- leaves SavedVariables untouched. A failed create stops there; a failed
--- switch switches back and removes the created profile, from Suite too.
--- Returns true, or false plus reason plus stage ("name", "exists", "decode",
--- "create" or "switch").
function MSUF_ImportIntoNewProfile(name, str)
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    MSUF_ProfileIO_ResetImportWarnings()
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return false, "enter a new profile name", "name"
    end
    --- Read-only existence check: the profile roots are not created before
    --- the string has been accepted.
    local profiles = type(MSUF_GlobalDB) == "table" and MSUF_GlobalDB.profiles or nil
    if type(profiles) == "table" and profiles[name] ~= nil then
        return false, "profile already exists", "exists"
    end
    local plan, why, chatLine = MSUF_ProfileIO_PrepareImport(str, "active")
    if not plan then
        print(chatLine)
        return false, why, "decode"
    end
    local base = {}
    if plan.kind ~= "all" then
        base = ImportTx.FactoryBase()
        if not base then
            ProfileChat("error", "Factory defaults are not available; profile was not created.")
            return false, "factory defaults unavailable", "create"
        end
    end
    ImportTx.Stage(plan, base)
    local previous = MSUF_ActiveProfile or "Default"
    local created = MSUF_CreateProfile(name)
    profiles = type(MSUF_GlobalDB) == "table" and MSUF_GlobalDB.profiles or nil
    if created ~= true or type(profiles) ~= "table" or type(profiles[name]) ~= "table" then
        return false, "could not create profile", "create"
    end
    local previousExists = type(profiles[previous]) == "table"
    MSUF_SwitchProfile(name)
    if MSUF_ActiveProfile ~= name then
        if previousExists then MSUF_SwitchProfile(previous) end
        profiles[name] = nil
        MSUF_ProfileIO_NotifySuiteLifecycle("delete", name)
        return false, "could not switch profile", "switch"
    end
    MSUF_ProfileIO_CommitImportToActiveProfile(plan)
    if plan.isSnapshot then
        ProfileChat("ok", "Imported %s settings into the active profile.", tostring(plan.snapshotKind))
    else
        ProfileChat("ok", "Profile imported into the active profile.")
    end
    MSUF_ProfileIO_ReportImportWarnings()
    return true
end
---
--- External Wago UI Packs API (stateless by profileKey)
--- Goals:
--- - Allow tools to export/import a SPECIFIC profile by key without switching MSUF_ActiveProfile.
--- - Keep DB table references stable (important for runtime caches) when overwriting the ACTIVE profile.
--- - Zero regression: existing import/export code paths remain unchanged.
--- API:
--- ok, strOrErr = MSUF_ExportExternal(profileKey)
--- ok, errOrNil = MSUF_ImportExternal(profileString, profileKey)
---

local function MSUF_ProfileIO_EnsureProfileSystemInitialized()
    MSUF_ProfileIO_RunEnsureDB()
    local profiles = MSUF_ProfileIO_EnsureProfileRoots()
    local active = MSUF_ActiveProfile
    local needsInit = type(active) ~= "string"
        or active == ""
        or type(MSUF_DB) ~= "table"
        or type(profiles[active]) ~= "table"
    if needsInit then
        MSUF_InitProfiles()
    end
end
local function MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileKey) ~= "string" or profileKey == "" then
         return nil
    end
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    return MSUF_GlobalDB.profiles[profileKey]
end

local function MSUF_ProfileIO_MaterializeProfileCopyForExport(profile, profileKey)
    if type(profile) ~= "table" then return nil, "not a table" end
    MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
        source = "external_export", markProfile = true, trustNormalizationMarker = true,
    })
    _G.MSUF_NormalizePortraitRenderDB(profile)
    _G.MSUF_NormalizeProfileDefaults(profile, false, true)
    MSUF_ProfileIO_EnsureUnitframeAlphaDB(profile)
    MSUF.GF.RepairGroupDB(profile)
    MSUF.MSUF_Auras3.NormalizeProfileDB(profile)
    return profile
end
local function MSUF_ProfileIO_OverwriteProfile(profileKey, plan)
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    if type(plan) ~= "table" or type(plan.payload) ~= "table" then
         return false, "not a table"
    end
    --- plan is an accepted MSUF_ProfileIO_PrepareImport plan: its payload is
    --- already validated, translated and media-checked. The stored or active
    --- table only changes after the staged candidate survived every normalizer,
    --- so a stored profile is always the normalized one.
    MSUF_ProfileIO_EnsureProfileSystemInitialized()
    if Variants and not Variants.CanMutateProfile() then return false,"finish editing the variant first" end
    local existing = MSUF_GlobalDB.profiles[profileKey]
    local isActive = (profileKey == MSUF_ActiveProfile)
    local base = {}
    if not MSUF_ProfileIO_ImportVariants and type(existing) == "table" then
        base = existing
        if isActive and Variants and type(MSUF_DB) == "table" then
            local why
            base, why = Variants.BaseSnapshot(MSUF_DB, true)
            if not base then return false, why end
        end
    end
    local newTable = ImportTx.Stage(plan, base)
    if isActive then
        --- As for any import into the active profile: pending edits reach
        --- the sync members first, the imported settings stay local.
        if ProfileSync then ProfileSync.Flush() end
        PrepareProfileMutation()
    end
    if isActive and type(MSUF_DB) ~= "table" and type(existing) == "table" then
        MSUF_DB = existing
    end
    --- Keep references stable for ACTIVE profile (and if someone holds a ref to the existing table).
    if isActive and type(MSUF_DB) == "table" then
        --- Prefer wiping the active table ref (MSUF_DB) to avoid cache/reference drift.
        local target = MSUF_DB
        MSUF_WipeTable(target)
        for k, v in pairs(newTable) do
            target[k] = v
        end
        MSUF_GlobalDB.profiles[profileKey] = target
        MSUF_ProfileIO_RunEnsureDB(true)
        if ProfileSync then ProfileSync.Rebase() end
        MSUF.ProfileIOCompleteFirstLoadImport()
        MSUF_ProfileIO_EnsureUnitframeAlphaDB()
        MSUF_ProfileIO_PostImportApply_Auras("all", target)
        MSUF_ProfileIO_PostImportApply_GroupFrames("all", target)
        MSUF_ProfileIO_PostImportApply_UnitAlphas("all", target)
        ApplyProfileRuntime("PROFILE_EXTERNAL_IMPORT", true)
        MSUF_ProfileIO_NotifySuiteProfileChanged("PROFILE_EXTERNAL_IMPORT", profileKey)
        MSUF_ProfileIO_ReportImportWarnings()
        ImportTx.ReportKeptVariants(plan)
        return true
    end
    if type(existing) == "table" then
        --- For non-active profiles we can still preserve reference stability if something else points at it.
        MSUF_WipeTable(existing)
        for k, v in pairs(newTable) do
            existing[k] = v
        end
        MSUF_GlobalDB.profiles[profileKey] = existing
        MSUF_ProfileIO_ReportImportWarnings()
        ImportTx.ReportKeptVariants(plan)
        MSUF.ProfileIOCompleteFirstLoadImport()
        return true
    end
    MSUF_GlobalDB.profiles[profileKey] = newTable
    MSUF_ProfileIO_ReportImportWarnings()
    MSUF.ProfileIOCompleteFirstLoadImport()
    return true
end
function MSUF_ExportExternal(profileKey)
    if Variants and Variants.IsRecording() then return false,"finish editing the variant first" end
    local profileTbl = MSUF_ProfileIO_GetProfileTable(profileKey)
    if type(profileTbl) ~= "table" then
         return false, "unknown profileKey"
    end
    local payload
    if profileKey == MSUF_ActiveProfile then
        MSUF_ProfileIO_EnsureCompleteProfileDB()
        profileTbl = MSUF_DB
        local snapshotWhy
        if Variants then payload,snapshotWhy=Variants.BaseSnapshot(profileTbl,true) else payload=MSUF_DeepCopy(profileTbl) end
        if not payload then return false,snapshotWhy or "profile exceeds snapshot limits" end
    else
        payload = MSUF_DeepCopy(profileTbl)
        local materialized, why = MSUF_ProfileIO_MaterializeProfileCopyForExport(payload, profileKey)
        if type(materialized) ~= "table" then
            return false, tostring(why or "profile materialization failed")
        end
        payload = materialized
    end
    if MSUF.ProfileFields and MSUF.ProfileFields.StripExternal then MSUF.ProfileFields.StripExternal(payload) end
    payload.assistant = nil -- retired Assistant history (State/MSUF_RetiredData.lua)
    if not MSUF_ProfileIO_ExportVariants then payload.profileVariants=nil end
    local snap = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
        kind    = "all",
        profile = profileKey,
        payload = MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload),
    }
    if profileKey == MSUF_ActiveProfile then
        MSUF_ProfileIO_StampScreenReference(snap.payload)
    end
    local exportSnap = MSUF_ProfileIO_MakeWagoSnapshot(snap)
    return true, _G.MSUF_EncodeCompactTableMSUF3(exportSnap)
end
function MSUF_ImportExternal(profileString, profileKey)
    MSUF_ProfileIO_ResetImportWarnings()
    if type(profileString) ~= "string" or not profileString:match("%S") then
         return false, "empty profileString"
    end
    if type(profileKey) ~= "string" or profileKey == "" then
         return false, "invalid profileKey"
    end
    local plan, why = MSUF_ProfileIO_PrepareImport(profileString, "external")
    if not plan then
        return false, why
    end
    return MSUF_ProfileIO_OverwriteProfile(profileKey, plan)
end
--- Deprecated compatibility aliases (MSUF_Profiles_*) of the profile string API,
--- once used by load-order proxies; MSUF itself calls the canonical names.
ExportPublic("MSUF_Profiles_ExportExternal", MSUF_ExportExternal)
ExportPublic("MSUF_Profiles_ImportExternal", MSUF_ImportExternal)
--- Globals for the Options module.
ExportPublic("MSUF_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_ImportFromString", MSUF_ImportFromString)
--- Always expose the real implementations under stable, explicit names.
--- This lets other modules (or load-order proxies) call the correct logic even if _G.MSUF_ImportFromString was set earlier.
ExportPublic("MSUF_Profiles_ExportSelectionToString", MSUF_ExportSelectionToString)
ExportPublic("MSUF_Profiles_ImportFromString", MSUF_ImportFromString)
ExportPublic("MSUF_ImportIntoNewProfile", MSUF_ImportIntoNewProfile)
ExportPublic("MSUF_Profiles_ImportIntoNewProfile", MSUF_ImportIntoNewProfile)
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ExportExternal = "MSUF_ExportExternal"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportExternal = "MSUF_ImportExternal"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ExportSelectionToString = "MSUF_ExportSelectionToString"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportFromString = "MSUF_ImportFromString"
MSUF.Compat.DeprecatedAliases.MSUF_Profiles_ImportIntoNewProfile = "MSUF_ImportIntoNewProfile"
ExportPublic("MSUF_ProfileIO_TranslateProfileToCurrent", MSUF_ProfileIO_TranslateProfileToCurrent)
ExportPublic("MSUF_ProfileIO_TranslateProfilesToCurrent", MSUF_ProfileIO_TranslateProfilesToCurrent)
ExportPublic("MSUF_CreateProfile", MSUF_CreateProfile)
ExportPublic("MSUF_SwitchProfile", MSUF_SwitchProfile)
ExportPublic("MSUF_ResetProfile", MSUF_ResetProfile)
ExportPublic("MSUF_DeleteProfile", MSUF_DeleteProfile)
ExportPublic("MSUF_CopyProfile", MSUF_CopyProfile)
ExportPublic("MSUF_RenameProfile", MSUF_RenameProfile)
ExportPublic("MSUF_GetAllProfiles", MSUF_GetAllProfiles)
if type(MSUF) == "table" then
    MSUF.MSUF_ExportSelectionToString = MSUF_ExportSelectionToString
    MSUF.MSUF_ImportFromString        = MSUF_ImportFromString
    MSUF.MSUF_ImportIntoNewProfile    = MSUF_ImportIntoNewProfile
    MSUF.MSUF_ProfileIO_TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent
    MSUF.MSUF_ProfileIO_TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent
end
