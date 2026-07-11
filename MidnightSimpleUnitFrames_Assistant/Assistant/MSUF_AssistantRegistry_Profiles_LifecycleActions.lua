-- Assistant Profiles lifecycle actions.
-- Loaded before MSUF_AssistantRegistry_Profiles.lua; the profile registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ProfileRegistry = A.ProfileRegistry or {}

function A.ProfileRegistry.RegisterLifecycleActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Profile = ctx.Profile
    local ResolveProfileName = ctx.ResolveProfileName
    local ProfileExists = ctx.ProfileExists
    local Assistant = ctx.Assistant or A

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(Profile) ~= "table" or type(ResolveProfileName) ~= "function" then return end
    if type(ProfileExists) ~= "function" then return end

    Registry:RegisterAction({
        key = "delete_profile",
        label = "Delete Profile",
        type = "profile",
        kind = "action",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local name = args and args.name
            if type(name) ~= "string" or name == "" then return false, "Which profile do you want me to delete?" end
            local requested = name
            local resolved, how = ResolveProfileName(name)
            if how == "multiple" then return false, "I found multiple matching profiles. Which full profile name do you want me to use?" end
            name = resolved
            if name == "Default" then return false, "The Default profile is protected. Reset it instead." end
            if not ProfileExists(name) then return false, "I don't see that profile: " .. tostring(requested) .. "." end
            if type(_G.MSUF_DeleteProfile) ~= "function" then return false, "Open Profiles first so I can delete that profile." end
            _G.MSUF_DeleteProfile(name)
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_DELETE") end
            return true, "Done. Deleted profile " .. tostring(name) .. "."
        end,
    })

    Registry:RegisterAction({
        key = "switch_profile",
        label = "Switch Profile",
        type = "profile",
        combatSafe = false,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local name = args and args.name
            if type(name) ~= "string" or name == "" then return false, "Which profile do you want me to switch to?" end
            local requested = name
            local resolved, how = ResolveProfileName(name)
            if how == "multiple" then return false, "I found multiple matching profiles. Which full profile name do you want me to use?" end
            name = resolved
            if not ProfileExists(name) then return false, "I don't see that profile: " .. tostring(requested) .. "." end
            if type(_G.MSUF_SwitchProfile) ~= "function" then return false, "Open Profiles first so I can switch profiles." end
            _G.MSUF_SwitchProfile(name)
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_SWITCH") end
            return true, "Done. Switched to profile " .. tostring(name) .. "."
        end,
    })

    Registry:RegisterAction({
        key = "create_profile",
        label = "Create Profile",
        type = "profile",
        combatSafe = false,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local name = args and args.name
            if type(name) ~= "string" or name == "" then return false, "What should the new profile be called?" end
            if type(_G.MSUF_CreateProfile) ~= "function" then return false, "Open Profiles first so I can create that profile." end
            _G.MSUF_CreateProfile(name)
            if args and args.switch ~= false and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(name) end
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_CREATE") end
            return true, "Done. Created profile " .. tostring(name) .. "."
        end,
    })

    Registry:RegisterAction({
        key = "copy_profile",
        label = "Copy Current Profile",
        type = "profile",
        combatSafe = false,
        confirmRequired = true,
        captureSnapshot = true,
        captureProfileSnapshot = true,
        run = function(args)
            local name = args and args.name
            if type(name) ~= "string" or name == "" then return false, "What should the destination profile be called?" end
            if type(_G.MSUF_CopyProfile) ~= "function" then return false, "Open Profiles first so I can copy that profile." end
            local copied = _G.MSUF_CopyProfile(_G.MSUF_ActiveProfile or "Default", name)
            if copied and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(name) end
            if Assistant and type(Assistant.ApplyBroad) == "function" then Assistant.ApplyBroad("MSUF_ASSISTANT_PROFILE_COPY") end
            return copied and true or false, copied and ("Done. Copied current profile to " .. tostring(name) .. ".") or "I kept the profile copy as it was."
        end,
    })
end
