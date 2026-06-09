local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function" and type(Registry.RegisterSetting) == "function") then return end

local function ProfileTable()
    local global = _G.MSUF_GlobalDB
    local profiles = type(global) == "table" and global.profiles or nil
    if type(profiles) == "table" then return profiles end
    return nil
end

local function ProfileExists(name)
    local profiles = ProfileTable()
    return type(name) == "string" and profiles and type(profiles[name]) == "table"
end

local function ResolveProfileName(name)
    name = tostring(name or "")
    if name == "" then return nil, "missing" end
    local profiles = ProfileTable()
    if type(profiles) ~= "table" then return name, "unknown" end
    if type(profiles[name]) == "table" then return name, "exact" end
    local wanted = name:lower()
    local compactWanted = wanted:gsub("[%s%-%_]+", "")
    local partial
    for profileName, profile in pairs(profiles) do
        if type(profile) == "table" then
            local lower = tostring(profileName):lower()
            local compactLower = lower:gsub("[%s%-%_]+", "")
            if lower == wanted then return profileName, "exact" end
            if compactLower == compactWanted then return profileName, "exact" end
            if lower:find(wanted, 1, true) or compactLower:find(compactWanted, 1, true) then
                if partial then return nil, "multiple" end
                partial = profileName
            end
        end
    end
    if partial then return partial, "partial" end
    return nil, "missing"
end

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

local function IsUUFImportString(value)
    local fn = _G.MSUF_IsUUFImportString
    if type(fn) == "function" then
        local ok, result = pcall(fn, value)
        if ok then return result == true end
    end
    return type(value) == "string" and value:match("^%s*!UUF_") ~= nil
end

local function RequireUUFBestEffortAccepted(value, args)
    if IsUUFImportString(value) and not (args and args.uufBestEffortAccepted == true) then
        return false, "UnhaltedUnitFrames imports need best-effort confirmation first."
    end
    return true
end

local Profile = {
    KindLabels = {
        all = "Full profile",
        unitframe = "Unitframes",
        castbar = "Castbars",
        colors = "Colors",
        gameplay = "Gameplay",
        groupframe = "Group Frames",
    },
}

function Profile.ExportKind(kind)
    kind = tostring(kind or "all"):lower()
    if kind == "full" or kind == "profile" then kind = "all" end
    if kind == "unitframes" or kind == "unit frame" or kind == "unit frames" then kind = "unitframe" end
    if kind == "castbars" or kind == "cast bar" or kind == "cast bars" then kind = "castbar" end
    if kind == "color" then kind = "colors" end
    if kind == "group" or kind == "groupframes" or kind == "group frame" or kind == "group frames" then kind = "groupframe" end
    if Profile.KindLabels[kind] then return kind end
    return "all"
end

function Profile.List()
    local out, seen = {}, {}
    local list = type(_G.MSUF_GetAllProfiles) == "function" and _G.MSUF_GetAllProfiles() or nil
    if type(list) == "table" then
        for i = 1, #list do
            local name = list[i]
            if type(name) == "string" and name ~= "" and not seen[name] then
                out[#out + 1] = name
                seen[name] = true
            end
        end
    end
    if #out == 0 then
        local profiles = ProfileTable()
        if type(profiles) == "table" then
            for name, profile in pairs(profiles) do
                if type(name) == "string" and type(profile) == "table" and not seen[name] then
                    out[#out + 1] = name
                    seen[name] = true
                end
            end
        end
    end
    if #out == 0 then out[1] = "Default" end
    table.sort(out, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return out
end

function Profile.Refresh()
    if M and M.frame and type(M.frame.RefreshStatus) == "function" then M.frame:RefreshStatus() end
    if M and type(M.Refresh) == "function" then M.Refresh() end
end

function Profile.CopyURL()
    return "h" .. "tt" .. "ps" .. "://wago.io/search/imports/wow/m" .. "suf"
end

function Profile.CharacterKey()
    if type(_G.MSUF_GetCharKey) == "function" then return _G.MSUF_GetCharKey() end
    local name = type(_G.UnitName) == "function" and _G.UnitName("player") or "Player"
    local realm = type(_G.GetRealmName) == "function" and _G.GetRealmName() or "Realm"
    return tostring(name or "Player") .. "-" .. tostring(realm or "Realm")
end

function Profile.CharMeta(create)
    local global = _G.MSUF_GlobalDB
    if type(global) ~= "table" then
        if not create then return nil end
        global = {}
        _G.MSUF_GlobalDB = global
    end
    if type(global.char) ~= "table" then
        if not create then return nil end
        global.char = {}
    end
    local key = Profile.CharacterKey()
    if type(global.char[key]) ~= "table" then
        if not create then return nil end
        global.char[key] = {}
    end
    local char = global.char[key]
    if create and type(char.specProfileMap) ~= "table" then char.specProfileMap = {} end
    return char
end

function Profile.SpecAutoSwitchEnabled()
    if type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" then return _G.MSUF_IsSpecAutoSwitchEnabled() == true end
    local char = Profile.CharMeta(false)
    return char and char.specAutoSwitch == true or false
end

function Profile.SetSpecAutoSwitch(enabled)
    enabled = enabled and true or false
    if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then
        _G.MSUF_SetSpecAutoSwitchEnabled(enabled)
        return true
    end
    local char = Profile.CharMeta(true)
    if not char then return false end
    char.specAutoSwitch = enabled
    return true
end

function Profile.SpecMeta()
    local out = {}
    local n = type(_G.GetNumSpecializations) == "function" and _G.GetNumSpecializations() or 0
    for i = 1, n do
        if type(_G.GetSpecializationInfo) == "function" then
            local specID, specName = _G.GetSpecializationInfo(i)
            if type(specID) == "number" and type(specName) == "string" and specName ~= "" then
                out[#out + 1] = { id = specID, name = specName }
            end
        end
    end
    return out
end

function Profile.CompactName(value)
    return tostring(value or ""):lower():gsub("[%s%-%_]+", "")
end

function Profile.ResolveSpecID(value)
    local n = tonumber(value)
    if n then return n, tostring(n) end
    local wanted = Profile.CompactName(value)
    if wanted == "" then return nil, nil end
    local partial
    local specs = Profile.SpecMeta()
    for i = 1, #specs do
        local spec = specs[i]
        local name = Profile.CompactName(spec.name)
        if name == wanted then return spec.id, spec.name end
        if name:find(wanted, 1, true) or wanted:find(name, 1, true) then
            if partial then return nil, "multiple" end
            partial = spec
        end
    end
    if partial then return partial.id, partial.name end
    return nil, nil
end

function Profile.SpecLabel(specID)
    local specs = Profile.SpecMeta()
    for i = 1, #specs do
        if specs[i].id == specID then return specs[i].name end
    end
    return "Spec " .. tostring(specID)
end

function Profile.GetSpecProfile(specID)
    if type(_G.MSUF_GetSpecProfile) == "function" then return _G.MSUF_GetSpecProfile(specID) end
    local char = Profile.CharMeta(false)
    local map = char and char.specProfileMap
    local value = type(map) == "table" and map[specID] or nil
    return type(value) == "string" and value ~= "" and value or nil
end

function Profile.SetSpecProfile(specID, profileName)
    if type(_G.MSUF_SetSpecProfile) == "function" then
        _G.MSUF_SetSpecProfile(specID, profileName)
        return true
    end
    local char = Profile.CharMeta(true)
    if not char then return false end
    if type(char.specProfileMap) ~= "table" then char.specProfileMap = {} end
    if type(profileName) == "string" and profileName ~= "" and profileName ~= "None" then
        char.specProfileMap[specID] = profileName
    else
        char.specProfileMap[specID] = nil
    end
    return true
end

function Profile.DeleteCreated(name)
    local profiles = ProfileTable()
    if type(profiles) == "table" then profiles[name] = nil end
end

function Profile.ShowReload(label)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
        _G.MSUF_ShowReloadRecommendedPopup(label or "Profile import")
    end
end

function Profile.SummaryText()
    local lines = {}
    lines[#lines + 1] = "Active profile: " .. ActiveProfileName()
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Profiles:"
    local profiles = Profile.List()
    for i = 1, #profiles do lines[#lines + 1] = "- " .. tostring(profiles[i]) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Spec auto-switch: " .. (Profile.SpecAutoSwitchEnabled() and "on" or "off")
    local specs = Profile.SpecMeta()
    if #specs > 0 then
        lines[#lines + 1] = "Spec mappings:"
        for i = 1, #specs do
            local spec = specs[i]
            lines[#lines + 1] = "- " .. spec.name .. ": " .. tostring(Profile.GetSpecProfile(spec.id) or "None")
        end
    else
        lines[#lines + 1] = "Spec mappings: specialization data is not available yet."
    end
    return table.concat(lines, "\n")
end

A.ProfileWorkflow = Profile
A.ResolveProfileName = ResolveProfileName
A.ProfileExists = ProfileExists
A.ActiveProfileName = ActiveProfileName

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
        return false, "Profile reset is not available right now."
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
    },
    get = function() return Profile.SpecAutoSwitchEnabled() end,
    set = function(value) Profile.SetSpecAutoSwitch(value and true or false) end,
    apply = function() Profile.Refresh() end,
    combatSafe = false,
})

Registry:RegisterAction({
    key = "profile_summary",
    label = "Show Profile Summary",
    type = "profile",
    kind = "flow",
    combatSafe = true,
    run = function()
        local text = Profile.SummaryText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Profiles",
                help = "Current profile, available profiles, and specialization profile mappings.",
                text = text,
                status = "Profile status only. No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "copy_wago_profiles_link",
    label = "Copy Wago Profiles Link",
    type = "profile",
    kind = "flow",
    combatSafe = true,
    run = function()
        local value = Profile.CopyURL()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago MSUF Profiles", value)
        elseif A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "export",
                title = "Wago MSUF Profiles",
                help = "Copy this link to browse community MSUF profiles.",
                text = value,
                status = "Press Select all, then Ctrl+C.",
            })
        elseif M and type(M.SelectPage) == "function" then
            M.SelectPage("profiles")
        end
        return true, "Done. The Wago MSUF profile link is ready to copy."
    end,
})

Registry:RegisterAction({
    key = "export_profile",
    label = "Export Current Profile",
    type = "profile",
    kind = "flow",
    combatSafe = true,
    run = function(args)
        local kind = Profile.ExportKind(args and args.kind or "all")
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) ~= "function" then return false, "Profile export is not available right now." end
        local value = fn(kind)
        if type(value) ~= "string" or value == "" then return false, "Profile export failed." end
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "export",
                title = "Current Profile Export: " .. tostring(Profile.KindLabels[kind] or kind),
                help = "Copy this MSUF profile string. It was generated through the existing MSUF profile export helper.",
                text = value,
                status = "Press Select all, then Ctrl+C.",
            })
        elseif type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("MSUF Profile Export", value)
        elseif M and type(M.SelectPage) == "function" then
            M.SelectPage("profiles")
        end
        return true, "Done. Copy your current profile below."
    end,
})

Registry:RegisterAction({
    key = "open_profile_import",
    label = "Open Profile Import",
    type = "profile",
    kind = "flow",
    combatSafe = true,
    run = function()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "import",
                title = "Import Profile",
                help = "Paste an MSUF profile string. The Assistant will ask for confirmation before importing into the active profile.",
                text = "",
                status = "No profile data imported yet.",
            })
            return true, "Paste your MSUF profile string below."
        end
        if M and type(M.SelectPage) == "function" then M.SelectPage("profiles") end
        return true, "Opened Profiles. Paste the import string in Profile string."
    end,
})

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
        if type(value) ~= "string" or value == "" then return false, "No profile string was provided." end
        local allowed, why = RequireUUFBestEffortAccepted(value, args)
        if not allowed then return false, why end
        local fn = _G.MSUF_ImportFromString
        if type(fn) ~= "function" then return false, "Profile import is not available right now." end
        if fn(value) == true then
            if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_IMPORT") end
            if A and type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
            if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
                _G.MSUF_ShowReloadRecommendedPopup("Profile import")
            end
            return true, "Done. Imported profile data into the active profile. Reload is recommended."
        end
        return false, "Profile import failed."
    end,
})

Registry:RegisterAction({
    key = "import_profile_string_new",
    label = "Import Profile String Into New Profile",
    type = "profile",
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function(args)
        local value = args and args.value
        local name = args and args.name
        if type(value) ~= "string" or value == "" then return false, "No profile string was provided." end
        local allowed, why = RequireUUFBestEffortAccepted(value, args)
        if not allowed then return false, why end
        if type(name) ~= "string" or name == "" then return false, "I need a new profile name for this import." end
        if ProfileExists(name) then return false, "Profile " .. tostring(name) .. " already exists." end
        if type(_G.MSUF_CreateProfile) ~= "function"
            or type(_G.MSUF_SwitchProfile) ~= "function"
            or type(_G.MSUF_ImportFromString) ~= "function"
        then
            return false, "Profile import into a new profile is not available right now."
        end

        local previous = ActiveProfileName()
        local previousExists = ProfileExists(previous)
        _G.MSUF_CreateProfile(name)
        if not ProfileExists(name) then
            return false, "Profile import failed because the new profile could not be created."
        end
        _G.MSUF_SwitchProfile(name)
        if ActiveProfileName() ~= name then
            if previousExists then _G.MSUF_SwitchProfile(previous) end
            Profile.DeleteCreated(name)
            return false, "Profile import failed because MSUF could not switch to the new profile."
        end
        if _G.MSUF_ImportFromString(value) ~= true then
            if previousExists then _G.MSUF_SwitchProfile(previous) end
            Profile.DeleteCreated(name)
            Profile.Refresh()
            return false, "Profile import failed."
        end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_IMPORT_NEW") end
        if A and type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
        Profile.ShowReload("Profile import")
        return true, "Done. Imported profile data into new profile " .. tostring(name) .. ". Reload is recommended."
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
        if type(value) ~= "string" or value == "" then return false, "No legacy profile string was provided." end
        local allowed, why = RequireUUFBestEffortAccepted(value, args)
        if not allowed then return false, why end
        local fn = _G.MSUF_ImportLegacyFromString
        if type(fn) ~= "function" then return false, "Legacy profile import is not available right now." end
        if fn(value) == false then return false, "Legacy profile import failed." end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_LEGACY_IMPORT") end
        if A and type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
        return true, "Done. Imported the legacy profile string."
    end,
})

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
        if type(name) ~= "string" or name == "" then return false, "I need a profile name to delete." end
        local requested = name
        local resolved, how = ResolveProfileName(name)
        if how == "multiple" then return false, "I found multiple matching profiles. Please use the exact profile name." end
        name = resolved
        if name == "Default" then return false, "The Default profile cannot be deleted. Reset it instead." end
        if not ProfileExists(name) then return false, "Profile " .. tostring(requested) .. " was not found." end
        if type(_G.MSUF_DeleteProfile) ~= "function" then return false, "Profile deletion is not available right now." end
        _G.MSUF_DeleteProfile(name)
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_DELETE") end
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
        if type(name) ~= "string" or name == "" then return false, "I need a profile name to switch to." end
        local requested = name
        local resolved, how = ResolveProfileName(name)
        if how == "multiple" then return false, "I found multiple matching profiles. Please use the exact profile name." end
        name = resolved
        if not ProfileExists(name) then return false, "Profile " .. tostring(requested) .. " was not found." end
        if type(_G.MSUF_SwitchProfile) ~= "function" then return false, "Profile switching is not available right now." end
        _G.MSUF_SwitchProfile(name)
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_SWITCH") end
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
        if type(name) ~= "string" or name == "" then return false, "I need a profile name to create." end
        if type(_G.MSUF_CreateProfile) ~= "function" then return false, "Profile creation is not available right now." end
        _G.MSUF_CreateProfile(name)
        if args and args.switch ~= false and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(name) end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_CREATE") end
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
        if type(name) ~= "string" or name == "" then return false, "I need a destination profile name." end
        if type(_G.MSUF_CopyProfile) ~= "function" then return false, "Profile copy is not available right now." end
        local copied = _G.MSUF_CopyProfile(_G.MSUF_ActiveProfile or "Default", name)
        if copied and type(_G.MSUF_SwitchProfile) == "function" then _G.MSUF_SwitchProfile(name) end
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_COPY") end
        return copied and true or false, copied and ("Done. Copied current profile to " .. tostring(name) .. ".") or "Profile copy failed."
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
        if specName == "multiple" then return false, "I found multiple matching specializations. Please use the exact specialization name or ID." end
        if not specID then return false, "I need a specialization name or ID." end
        if type(profileValue) ~= "string" or profileValue == "" then return false, "I need a profile name for " .. Profile.SpecLabel(specID) .. "." end
        local requested = profileValue
        local resolved, how = ResolveProfileName(profileValue)
        if how == "multiple" then return false, "I found multiple matching profiles. Please use the exact profile name." end
        if not ProfileExists(resolved) then return false, "Profile " .. tostring(requested) .. " was not found." end
        if not Profile.SetSpecProfile(specID, resolved) then return false, "Spec profile assignment is not available right now." end
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
        if specName == "multiple" then return false, "I found multiple matching specializations. Please use the exact specialization name or ID." end
        if not specID then return false, "I need a specialization name or ID." end
        if not Profile.SetSpecProfile(specID, nil) then return false, "Spec profile assignment is not available right now." end
        Profile.Refresh()
        return true, "Done. Cleared the profile assignment for " .. Profile.SpecLabel(specID) .. "."
    end,
})
