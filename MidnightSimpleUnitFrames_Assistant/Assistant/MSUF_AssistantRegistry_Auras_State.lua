-- Assistant Auras saved-state helper registry.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main auras registry passes runtime helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildStateHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local AuraRuntimeUnit = ctx.AuraRuntimeUnit

    if type(AuraModel) ~= "function" then return nil end

    local function AuraRootDB()
        local Model = AuraModel()
        if Model and type(Model.EnsureDB) == "function" then
            local auras = Model.EnsureDB()
            if type(auras) == "table" then return auras end
        end
        local auras = type(EnsureAuraFallbackDB) == "function" and EnsureAuraFallbackDB() or nil
        if type(auras) == "table" then return auras end
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
        return _G.MSUF_DB.auras3
    end

    local function AuraPerUnit(scope, create)
        local auras = AuraRootDB()
        if type(auras) ~= "table" then return nil end
        auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
        local unit = AuraRuntimeUnit and AuraRuntimeUnit(scope) or tostring(scope or "player")
        local pu = auras.perUnit[unit]
        if create and type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        return pu, unit, auras
    end

    local function AuraRootBool(key, defaultValue)
        local auras = AuraRootDB()
        if type(auras) ~= "table" then return defaultValue and true or false end
        if auras[key] == nil then return defaultValue and true or false end
        return auras[key] == true
    end

    local function SetAuraRootBool(key, value)
        local auras = AuraRootDB()
        if type(auras) == "table" then auras[key] = value and true or false end
    end

    return {
        AuraRootDB = AuraRootDB,
        AuraPerUnit = AuraPerUnit,
        AuraRootBool = AuraRootBool,
        SetAuraRootBool = SetAuraRootBool,
    }
end
