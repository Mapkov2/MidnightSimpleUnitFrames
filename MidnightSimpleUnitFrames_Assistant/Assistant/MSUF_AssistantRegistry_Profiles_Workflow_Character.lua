-- Assistant profile character metadata helpers.
-- Loaded before MSUF_AssistantRegistry_Profiles_Workflow.lua; keeps character DB plumbing isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ProfileWorkflowBuilders = A.ProfileWorkflowBuilders or {}

function A.ProfileWorkflowBuilders.InstallCharacterProfileHelpers(Profile, ExportPublic)
    if type(Profile) ~= "table" then return false end
    ExportPublic = ExportPublic or MSUF.ExportPublic or function(name, value) _G[name] = value; return value end

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
            ExportPublic("MSUF_GlobalDB", global)
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

    return true
end
