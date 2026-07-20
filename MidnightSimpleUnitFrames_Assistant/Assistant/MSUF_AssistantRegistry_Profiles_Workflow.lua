-- Assistant Profiles workflow helpers shared by registry, diagnostics, and workflows.
-- Runtime profile operations remain delegated to the existing MSUF profile API.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

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

-- Existing profile names are stored with their user-facing casing.  Keep that
-- store as the canonical display source instead of reconstructing labels from
-- the parser's case-insensitive text.
local function DisplayProfileName(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return "" end
    local resolved = ResolveProfileName(name)
    return type(resolved) == "string" and resolved ~= "" and resolved or name
end

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

local Profile = {
    KindLabels = {
        all = "Full profile",
        unitframe = "Unit Frames",
        castbar = "Cast Bars",
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

local InstallCharacterProfileHelpers = A.ProfileWorkflowBuilders and A.ProfileWorkflowBuilders.InstallCharacterProfileHelpers
if type(InstallCharacterProfileHelpers) ~= "function" then return end
InstallCharacterProfileHelpers(Profile, ExportPublic)

local InstallSpecProfileHelpers = A.ProfileWorkflowBuilders and A.ProfileWorkflowBuilders.InstallSpecProfileHelpers
if type(InstallSpecProfileHelpers) ~= "function" then return end
InstallSpecProfileHelpers(Profile)

function Profile.DeleteCreated(name)
    local profiles = ProfileTable()
    if type(profiles) == "table" then profiles[name] = nil end
end

function Profile.ShowReload(label)
    if type(_G.MSUF_ShowReloadRecommendedPopup) == "function" then
        _G.MSUF_ShowReloadRecommendedPopup(label or "Profile import")
    end
end

Profile.ProfileExists = ProfileExists
Profile.ResolveProfileName = ResolveProfileName
Profile.DisplayProfileName = DisplayProfileName
Profile.ActiveProfileName = ActiveProfileName

A.ProfileWorkflow = Profile
A.ResolveProfileName = ResolveProfileName
A.DisplayProfileName = DisplayProfileName
A.ProfileExists = ProfileExists
A.ActiveProfileName = ActiveProfileName
