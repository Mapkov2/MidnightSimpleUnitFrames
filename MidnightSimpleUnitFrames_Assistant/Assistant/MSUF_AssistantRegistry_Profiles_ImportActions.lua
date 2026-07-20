-- Assistant profile import actions.
-- Loaded before MSUF_AssistantRegistry_Profiles_ImportExport.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ProfileRegistry = A.ProfileRegistry or {}

function A.ProfileRegistry.RegisterProfileImportActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Profile = ctx.Profile
    local ProfileExists = ctx.ProfileExists
    local ActiveProfileName = ctx.ActiveProfileName
    local Assistant = ctx.Assistant or A
    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(Profile) ~= "table" then return end
    if type(ProfileExists) ~= "function" or type(ActiveProfileName) ~= "function" then return end

    Registry:RegisterAction({
        key = "import_profile_string",
        label = "Import Profile String",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Add the profile string you want to import." end
            local fn = _G.MSUF_ImportFromString
            if type(fn) ~= "function" then return false, "Open Profiles first, then send the profile import text." end
            if fn(value) == true then
                if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_IMPORT") end
                if Assistant and type(Assistant.CloseLargeTextPanel) == "function" then Assistant.CloseLargeTextPanel() end
                if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                    _G.MSUF_ShowReloadRecommendedPopup("Profile import")
                end
                return true, "Done. Imported profile data into the active profile. A reload is recommended."
            end
            return false, "I kept the profile as it was. Add the corrected import text when ready."
        end,
    })

    Registry:RegisterAction({
        key = "import_profile_string_new",
        label = "Import Profile String into New Profile",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local value = args and args.value
            local name = args and args.name
            if type(value) ~= "string" or value == "" then return false, "Add the profile string you want to import." end
            if type(name) ~= "string" or name == "" then return false, "What should the new profile be called for this import?" end
            if ProfileExists(name) then return false, "Profile " .. tostring(name) .. " already exists." end
            if type(_G.MSUF_CreateProfile) ~= "function"
                or type(_G.MSUF_SwitchProfile) ~= "function"
                or type(_G.MSUF_ImportFromString) ~= "function"
            then
                return false, "Open Profiles first, then send the profile import text."
            end

            local previous = ActiveProfileName()
            local previousExists = ProfileExists(previous)
            _G.MSUF_CreateProfile(name)
            if not ProfileExists(name) then
                return false, "The profile import did not create the new profile."
            end
            _G.MSUF_SwitchProfile(name)
            if ActiveProfileName() ~= name then
                if previousExists then _G.MSUF_SwitchProfile(previous) end
                Profile.DeleteCreated(name)
                return false, "The profile import did not switch to the new profile."
            end
            if _G.MSUF_ImportFromString(value) ~= true then
                if previousExists then _G.MSUF_SwitchProfile(previous) end
                Profile.DeleteCreated(name)
                Profile.Refresh()
                return false, "I kept the profile as it was. Add the corrected import text when ready."
            end
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_IMPORT_NEW") end
            if Assistant and type(Assistant.CloseLargeTextPanel) == "function" then Assistant.CloseLargeTextPanel() end
            Profile.ShowReload("Profile import")
            return true, "Done. Imported profile data into the new profile " .. tostring(name) .. ". A reload is recommended."
        end,
    })

    Registry:RegisterAction({
        key = "import_legacy_profile_string",
        label = "Import Legacy Profile String",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local value = args and args.value
            if type(value) ~= "string" or value == "" then return false, "Add the legacy profile string you want to import." end
            local fn = _G.MSUF_ImportLegacyFromString
            if type(fn) ~= "function" then return false, "Open Profiles first, then send the legacy import text." end
            if fn(value) == false then return false, "I kept the profile as it was. Add the corrected legacy import text when ready." end
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_LEGACY_IMPORT") end
            if Assistant and type(Assistant.CloseLargeTextPanel) == "function" then Assistant.CloseLargeTextPanel() end
            return true, "Done. Imported the legacy profile string."
        end,
    })
end
