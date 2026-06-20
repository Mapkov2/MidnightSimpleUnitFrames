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

    local function AuraOverrideBool(scope, key)
        local pu = AuraPerUnit(scope, false)
        return type(pu) == "table" and pu[key] == true
    end

    local function SeedAuraTable(dst, src, keys)
        if type(dst) ~= "table" then return end
        src = type(src) == "table" and src or {}
        for i = 1, #keys do
            local key = keys[i]
            if dst[key] == nil then dst[key] = src[key] end
        end
    end

    local function SetAuraOverrideBool(scope, key, value)
        if scope == "shared" then return end
        local pu, _, auras = AuraPerUnit(scope, true)
        if type(pu) ~= "table" then return end
        if not value then
            pu[key] = false
            return
        end
        pu[key] = true
        local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
        if key == "overrideFilters" then
            if type(pu.filters) ~= "table" then
                pu.filters = {}
                if type(shared.filters) == "table" then
                    for k, v in pairs(shared.filters) do
                        if type(v) == "table" then
                            pu.filters[k] = {}
                            for kk, vv in pairs(v) do pu.filters[k][kk] = vv end
                        else
                            pu.filters[k] = v
                        end
                    end
                end
            end
            pu.filters.buffs = type(pu.filters.buffs) == "table" and pu.filters.buffs or {}
            pu.filters.debuffs = type(pu.filters.debuffs) == "table" and pu.filters.debuffs or {}
        elseif key == "overrideSharedLayout" then
            pu.layoutShared = type(pu.layoutShared) == "table" and pu.layoutShared or {}
            SeedAuraTable(pu.layoutShared, shared, {
                "maxBuffs", "maxDebuffs", "maxIcons", "perRow", "layoutMode", "growth",
                "buffGrowth", "debuffGrowth", "rowWrap", "buffRowWrap", "debuffRowWrap",
                "buffDebuffAnchor", "splitSpacing", "stackCountAnchor", "sortOrder",
            })
        elseif key == "overrideLayout" then
            pu.layout = type(pu.layout) == "table" and pu.layout or {}
            SeedAuraTable(pu.layout, shared, { "iconSize", "spacing", "cooldownTextSize", "stackTextSize", "reminderGrowth" })
        elseif key == "overrideIgnore" then
            pu.ignoreCats = type(pu.ignoreCats) == "table" and pu.ignoreCats or {}
            if type(shared.ignoreCats) == "table" then
                for k, v in pairs(shared.ignoreCats) do pu.ignoreCats[k] = v end
            end
        end
    end

    local function ResetAuraScope(scope)
        if scope == "shared" then return false end
        local _, unit, auras = AuraPerUnit(scope, false)
        if type(auras) ~= "table" or type(auras.perUnit) ~= "table" then return false end
        auras.perUnit[unit] = nil
        return true
    end

    local function ResetAllAuraOverrides()
        local auras = AuraRootDB()
        if type(auras) ~= "table" then return false end
        auras.perUnit = {}
        return true
    end

    return {
        AuraRootDB = AuraRootDB,
        AuraPerUnit = AuraPerUnit,
        AuraRootBool = AuraRootBool,
        SetAuraRootBool = SetAuraRootBool,
        AuraOverrideBool = AuraOverrideBool,
        SetAuraOverrideBool = SetAuraOverrideBool,
        ResetAuraScope = ResetAuraScope,
        ResetAllAuraOverrides = ResetAllAuraOverrides,
    }
end
