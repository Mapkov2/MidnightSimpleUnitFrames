-- Assistant profile diagnostics.
-- Loaded before MSUF_AssistantRegistry_Diagnostics.lua; the main diagnostics registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DiagnosticsRegistry = A.DiagnosticsRegistry or {}

function A.DiagnosticsRegistry.BuildProfileDiagnostic(ctx)
    if type(ctx) ~= "table" then return nil end

    local Menu = ctx.M or M
    local ActiveProfileName = ctx.ActiveProfileName
    local AddActionChoice = ctx.AddActionChoice
    local AppendFixChoices = ctx.AppendFixChoices

    if type(ActiveProfileName) ~= "function" then return nil end
    if type(AddActionChoice) ~= "function" or type(AppendFixChoices) ~= "function" then return nil end

    local function CountKeys(tbl)
        local count = 0
        if type(tbl) ~= "table" then return 0 end
        for _ in pairs(tbl) do count = count + 1 end
        return count
    end

    local function FirstExistingProfile(profiles, preferred)
        if type(profiles) ~= "table" then return nil end
        if type(preferred) == "string" and type(profiles[preferred]) == "table" then return preferred end
        if type(profiles.Default) == "table" then return "Default" end
        local names = {}
        for name, profile in pairs(profiles) do
            if type(name) == "string" and type(profile) == "table" then names[#names + 1] = name end
        end
        table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
        return names[1]
    end

    local function CharProfileState()
        local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
        local chars = global and type(global.char) == "table" and global.char or nil
        local key
        if type(_G.MSUF_GetCharKey) == "function" then
            key = _G.MSUF_GetCharKey()
        elseif type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
            key = tostring(_G.UnitName("player") or "Player") .. "-" .. tostring(_G.GetRealmName() or "Realm")
        end
        local char = key and chars and chars[key] or nil
        return key, type(char) == "table" and char or nil
    end

    local function ClearBrokenSpecProfileMappings()
        local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
        local profiles = global and type(global.profiles) == "table" and global.profiles or nil
        local _, char = CharProfileState()
        local map = char and type(char.specProfileMap) == "table" and char.specProfileMap or nil
        if type(profiles) ~= "table" or type(map) ~= "table" then return 0 end
        local broken = {}
        for specID, profileName in pairs(map) do
            if type(profileName) == "string" and type(profiles[profileName]) ~= "table" then broken[#broken + 1] = specID end
        end
        table.sort(broken, function(a, b) return tostring(a) < tostring(b) end)
        for i = 1, #broken do
            local specID = broken[i]
            if type(_G.MSUF_SetSpecProfile) == "function" then
                _G.MSUF_SetSpecProfile(specID, nil)
            else
                map[specID] = nil
            end
        end
        return #broken
    end

    local function ProfileDiagnosticText()
        local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
        local profiles = global and type(global.profiles) == "table" and global.profiles or nil
        local active = ActiveProfileName()
        local activeTable = profiles and profiles[active] or nil
        local charKey, char = CharProfileState()
        local map = char and type(char.specProfileMap) == "table" and char.specProfileMap or nil
        local brokenSpecs = 0
        if map and profiles then
            for _, profileName in pairs(map) do
                if type(profileName) == "string" and type(profiles[profileName]) ~= "table" then brokenSpecs = brokenSpecs + 1 end
            end
        end

        local lines = {
            "Profile check:",
            "Active profile: " .. tostring(active),
            "Saved profiles: " .. tostring(CountKeys(profiles)),
            "Active profile data: " .. (type(activeTable) == "table" and "ready" or "open Profiles first"),
            "Active profile in use: " .. ((type(activeTable) == "table" and _G.MSUF_DB == activeTable) and "yes" or "refresh needed"),
            "Character profile record: " .. tostring(charKey or "not saved yet"),
            "Specialization auto-switch: " .. ((char and char.specAutoSwitch == true) and "on" or "off"),
            "Specialization profile links: " .. tostring(CountKeys(map)),
        }
        if brokenSpecs > 0 then
            lines[#lines + 1] = "Broken specialization links: " .. tostring(brokenSpecs) .. " point to profiles that no longer exist."
        end
        lines[#lines + 1] = "Prepared profile changes:"
        lines[#lines + 1] = "- New or copied profile name: " .. tostring((Menu and Menu.profileCreateCopyName ~= "" and Menu.profileCreateCopyName) or "empty")
        lines[#lines + 1] = "- Export selection: " .. tostring((Menu and Menu.profileExportKind) or "all")
        lines[#lines + 1] = "- Import text: " .. (((Menu and type(Menu.profileImportString) == "string" and Menu.profileImportString ~= "") and "present") or "empty")
        lines[#lines + 1] = "- Import as new profile: " .. ((Menu and Menu.profileImportCreateNew == true) and "on" or "off")
        local lifecycleTasks = {}
        if type(_G.MSUF_CreateProfile) == "function" then lifecycleTasks[#lifecycleTasks + 1] = "create" end
        if type(_G.MSUF_SwitchProfile) == "function" then lifecycleTasks[#lifecycleTasks + 1] = "switch" end
        if type(_G.MSUF_CopyProfile) == "function" then lifecycleTasks[#lifecycleTasks + 1] = "copy" end
        if type(_G.MSUF_DeleteProfile) == "function" then lifecycleTasks[#lifecycleTasks + 1] = "delete" end
        if type(_G.MSUF_RenameProfile) == "function" then lifecycleTasks[#lifecycleTasks + 1] = "rename" end
        local transferTasks = {}
        if type(_G.MSUF_ImportFromString) == "function" then transferTasks[#transferTasks + 1] = "import" end
        if type(_G.MSUF_ExportSelectionToString) == "function" then transferTasks[#transferTasks + 1] = "export" end
        lines[#lines + 1] = "Available profile tasks:"
        lines[#lines + 1] = "- Lifecycle: " .. (#lifecycleTasks > 0 and table.concat(lifecycleTasks, ", ") or "open Profiles to create, switch, copy, delete, or rename profiles")
        lines[#lines + 1] = "- Import/export: " .. (#transferTasks > 0 and table.concat(transferTasks, ", ") or "open Profiles to import or export profile strings")
        if type(activeTable) ~= "table" then
            lines[#lines + 1] = "Next step: switch to an existing profile or create/copy a new profile before importing."
        elseif brokenSpecs > 0 then
            lines[#lines + 1] = "Next step: clear or reassign the broken specialization profile links."
        else
            lines[#lines + 1] = "Profile storage looks OK."
        end
        local choices = {}
        if type(activeTable) ~= "table" then
            local fallback = FirstExistingProfile(profiles)
            if fallback then
                AddActionChoice(choices, "switch_profile", { name = fallback }, "Switch to existing profile " .. tostring(fallback), "Uses an existing profile after the active profile could not be found.", nil, true)
            end
        elseif _G.MSUF_DB ~= activeTable then
            AddActionChoice(choices, "switch_profile", { name = active }, "Refresh active profile " .. tostring(active), "Switches to the current active profile again so MSUF refreshes it.", nil, true)
        end
        if brokenSpecs > 0 then
            AddActionChoice(choices, "clear_broken_spec_profile_mappings", {}, "Clear broken spec profile links", "Removes spec profile links that point to profiles that no longer exist.", nil, true)
        end
        AddActionChoice(choices, "open_page", { page = "profiles", label = "Profiles" }, "Open Profiles page", "Opens the Profiles page for review.")
        return AppendFixChoices(table.concat(lines, "\n"), choices)
    end

    return {
        ClearBrokenSpecProfileMappings = ClearBrokenSpecProfileMappings,
        ProfileDiagnosticText = ProfileDiagnosticText,
    }
end
