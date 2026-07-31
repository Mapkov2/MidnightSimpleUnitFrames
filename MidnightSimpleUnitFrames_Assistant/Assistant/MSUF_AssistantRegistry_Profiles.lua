-- Assistant Profiles registry: exposes profile lifecycle, staging, import/export, and diagnostics.
-- Destructive or copy actions must remain snapshot-backed and confirmation-gated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function" and type(Registry.RegisterSetting) == "function") then return end

-- Profile assistant registry.
-- Actions here stage or invoke profile operations, but parsing must preserve user-provided
-- profile names exactly enough for import/export/copy flows to resolve them safely.
local Profile = A.ProfileWorkflow
local ResolveProfileName = A.ResolveProfileName
local ProfileExists = A.ProfileExists
local ActiveProfileName = A.ActiveProfileName
local RegisterImportExportActions = A.ProfileRegistry and A.ProfileRegistry.RegisterImportExportActions
local RegisterLifecycleActions = A.ProfileRegistry and A.ProfileRegistry.RegisterLifecycleActions
if type(Profile) ~= "table"
    or type(ResolveProfileName) ~= "function"
    or type(ProfileExists) ~= "function"
    or type(ActiveProfileName) ~= "function"
then
    return
end

Registry:RegisterAction({
    key = "reset_profile",
    label = "Reset Active Profile",
    type = "profile",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function()
        if M and type(M.ResetPageToDefaults) == "function" and M.ResetPageToDefaults("profiles") then
            return true, "Done. Reset the active profile."
        end
        return false, "Open Profiles first so I can reset the profile."
    end,
})

Registry:RegisterSetting({
    key = "profiles.specAutoSwitch",
    label = "Auto-switch Profile by Specialization",
    category = "Profiles / Spec Profiles",
    unit = "global",
    frameType = "profiles",
    attribute = "specAutoSwitch",
    type = "boolean",
    aliases = {
        "auto switch profile by specialization", "auto switch profile by spec",
        "profile auto switch", "spec profile switching", "specialization profile switching",
        "profile by specialization", "profile by spec",
        "profil automatisch wechseln", "profil auto switch", "profil nach spec",
        "profil nach spezialisierung", "spec profil wechsel", "spezialisierungs profil wechsel",
    },
    get = function() return Profile.SpecAutoSwitchEnabled() end,
    set = function(value) Profile.SetSpecAutoSwitch(value and true or false) end,
    apply = function() Profile.Refresh() end,
    combatSafe = false,
})

if type(RegisterImportExportActions) == "function" then
    RegisterImportExportActions({
        Registry = Registry,
        Profile = Profile,
        ProfileExists = ProfileExists,
        ActiveProfileName = ActiveProfileName,
        Assistant = A,
        Menu = M,
    })
end

if type(RegisterLifecycleActions) == "function" then
    RegisterLifecycleActions({
        Registry = Registry,
        Profile = Profile,
        ResolveProfileName = ResolveProfileName,
        ProfileExists = ProfileExists,
        Assistant = A,
    })
end

-- The Profiles page dropdown "New character profile" picks what a character
-- that has never run MSUF starts on. It is modelled as an action rather than a
-- setting for the same reason "Active profile" is: the valid values are the
-- live profile pool, which no static enum can describe. "None" clears it and
-- restores the historical "new characters land on Default" behaviour.
Registry:RegisterAction({
    key = "set_new_character_profile",
    label = "Set New Character Default Profile",
    type = "profile",
    -- No alias may contain "default profile": that phrase is already owned by
    -- "reset profile to default", and these aliases resolved there instead --
    -- offering to reset the active profile when the player asked which profile
    -- new characters start on.
    aliases = {
        "set new character profile", "new character profile",
        "profile for new characters", "set profile for new characters",
        "new characters profile",
        "profil fuer neue charaktere", "neues charakter profil",
        "profil neuer charaktere",
    },
    -- The profile name is free-form (the live profile pool), so it is read off
    -- the value tail rather than matched against a list. Returning an empty
    -- table for the bare alias is deliberate: `run` then asks which profile to
    -- use instead of guessing one.
    parseAliasArgs = function(text, raw)
        local source = tostring(raw or text or "")
        local normalized = source:lower()
        if not (normalized:find("new character", 1, true)
            or normalized:find("new characters", 1, true)
            or normalized:find("neue charaktere", 1, true)
            or normalized:find("neuer charaktere", 1, true)
            or normalized:find("charakter profil", 1, true))
        then
            return false
        end
        local name = source:match("%f[%a][Tt][Oo]%f[%A]%s+(.+)$")
            or source:match("%f[%a][Aa][Uu][Ff]%f[%A]%s+(.+)$")
        if name then
            name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[\"']", ""):gsub("[\"']$", "")
            name = name:gsub("%s*%.$", "")
        end
        if name and name ~= "" then return { name = name } end
        return {}
    end,
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function(args)
        local requested = args and args.name
        if type(requested) ~= "string" or requested == "" then
            return false, "Which profile do you want new characters to start on? Say a profile name, or None to clear it."
        end
        if type(Profile.SetNewCharacterProfile) ~= "function" then
            return false, "Open Profiles first so I can set the profile for new characters."
        end
        -- Clearing is a real outcome, so it must not be routed through the
        -- name resolver -- "None" is a sentinel, never a profile to look up.
        if requested == "None" or requested:lower() == "none" then
            if not Profile.SetNewCharacterProfile(nil) then
                return false, "Open Profiles first so I can set the profile for new characters."
            end
            Profile.Refresh()
            return true, "Done. New characters now start on Default."
        end
        local resolved, how = ResolveProfileName(requested)
        if how == "multiple" then return false, "I found multiple matching profiles. Which full profile name do you want me to use?" end
        if not ProfileExists(resolved) then return false, "I don't see that profile: " .. tostring(requested) .. "." end
        if not Profile.SetNewCharacterProfile(resolved) then
            return false, "Open Profiles first so I can set the profile for new characters."
        end
        Profile.Refresh()
        return true, "Done. New characters now start on profile " .. tostring(resolved) .. "."
    end,
})

Registry:RegisterAction({
    key = "set_spec_profile",
    label = "Set Spec Profile",
    type = "profile",
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function(args)
        local specValue = args and args.spec
        local profileValue = args and args.name
        local specID, specName = Profile.ResolveSpecID(specValue)
        if specName == "multiple" then return false, "I found multiple matching specializations. Which full specialization name or ID do you want me to use?" end
        if not specID then return false, "Which specialization do you want me to use? A name or ID is enough." end
        if type(profileValue) ~= "string" or profileValue == "" then return false, "Which profile do you want me to use for " .. Profile.SpecLabel(specID) .. "?" end
        local requested = profileValue
        local resolved, how = ResolveProfileName(profileValue)
        if how == "multiple" then return false, "I found multiple matching profiles. Which full profile name do you want me to use?" end
        if not ProfileExists(resolved) then return false, "I don't see that profile: " .. tostring(requested) .. "." end
        if not Profile.SetSpecProfile(specID, resolved) then return false, "Open Profiles first so I can assign the specialization profile." end
        Profile.Refresh()
        return true, "Done. " .. Profile.SpecLabel(specID) .. " now uses profile " .. tostring(resolved) .. "."
    end,
})

Registry:RegisterAction({
    key = "clear_spec_profile",
    label = "Clear Spec Profile",
    type = "profile",
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function(args)
        local specValue = args and args.spec
        local specID, specName = Profile.ResolveSpecID(specValue)
        if specName == "multiple" then return false, "I found multiple matching specializations. Which full specialization name or ID do you want me to use?" end
        if not specID then return false, "Which specialization do you want me to use? A name or ID is enough." end
        if not Profile.SetSpecProfile(specID, nil) then return false, "Open Profiles first so I can clear the specialization profile." end
        Profile.Refresh()
        return true, "Done. Cleared the profile assignment for " .. Profile.SpecLabel(specID) .. "."
    end,
})
