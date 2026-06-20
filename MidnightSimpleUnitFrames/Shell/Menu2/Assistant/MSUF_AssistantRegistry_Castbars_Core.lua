-- Assistant Castbars shared registry helpers and backend fallback logic.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main registry wires the returned context into split modules.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

local CASTBAR_KEYS = A.CastbarsRegistry.CASTBAR_KEYS
local CASTBAR_DETAIL_FIELDS = A.CastbarsRegistry.CASTBAR_DETAIL_FIELDS

function A.CastbarsRegistry.BuildCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end
    if type(CASTBAR_KEYS) ~= "table" or type(CASTBAR_DETAIL_FIELDS) ~= "table" then return nil end

    local Registry = ctx.Registry
    local RegistryCore = ctx.RegistryCore
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GeneralDB = ctx.GeneralDB
    local ClampNumber = ctx.ClampNumber
    local CallGlobal = ctx.CallGlobal
    local ApplyCastbar = ctx.ApplyCastbar
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(ClampNumber) ~= "function" or type(ApplyCastbar) ~= "function" then return nil end
    if type(RegisterGeneralEnum) ~= "function" then return nil end
    if type(CallGlobal) ~= "function" then
        CallGlobal = function(name, ...)
            local fn = _G[name]
            if type(fn) == "function" then return fn(...) end
            return nil
        end
    end

    local BuildBackendContext = A.CastbarsRegistry and A.CastbarsRegistry.BuildBackendContext
    local Backend = type(BuildBackendContext) == "function" and BuildBackendContext({
        GeneralDB = GeneralDB,
        CASTBAR_KEYS = CASTBAR_KEYS,
    }) or nil
    if type(Backend) ~= "table" then return nil end
    local GetCastbarBackend = Backend.GetCastbarBackend
    local SetCastbarBackend = Backend.SetCastbarBackend
    local NormalizeCastbarBackend = Backend.NormalizeCastbarBackend
    local SetCastbarProvider = Backend.SetCastbarProvider
    if type(GetCastbarBackend) ~= "function" or type(SetCastbarBackend) ~= "function" then return nil end
    if type(NormalizeCastbarBackend) ~= "function" or type(SetCastbarProvider) ~= "function" then return nil end

    local function RegisterUnitCastbarBoolean(unit)
        local aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar", "castbar")
        AddAliasesForUnit(aliases, unit, "cast bar", "zauberleiste")
        Registry:RegisterSetting({
            key = "general." .. CASTBAR_KEYS[unit].enable,
            label = UNIT_LABELS[unit] .. " Cast Bar",
            category = UNIT_LABELS[unit] .. " / Cast Bar",
            unit = unit,
            frameType = "castbar",
            attribute = "enabled",
            type = "boolean",
            aliases = aliases,
            get = function() return GetCastbarBackend(unit, GeneralDB()) ~= "HIDE" end,
            set = function(value) SetCastbarBackend(unit, value and true or false) end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_ENABLE") end,
            combatSafe = false,
        })
    end

    local function RegisterGeneralNumber(key, unit, frameType, attr, label, defaultValue, minValue, maxValue, aliases)
        Registry:RegisterSetting({
            key = "general." .. key,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = frameType,
            attribute = attr,
            type = "number",
            aliases = aliases,
            min = minValue,
            max = maxValue,
            step = 1,
            get = function()
                local value = tonumber(GeneralDB()[key])
                if value == nil then return defaultValue end
                return value
            end,
            set = function(value)
                GeneralDB()[key] = ClampNumber(value, minValue, maxValue, 1)
            end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_GEOMETRY") end,
            combatSafe = false,
        })
    end

    local function RegisterGeneralEnumSetting(key, unit, frameType, attr, label, defaultValue, values, aliases, valueAliases)
        RegisterGeneralEnum(key, attr, UNIT_LABELS[unit] .. " " .. label, defaultValue, values, aliases, {
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = frameType,
            valueAliases = valueAliases,
            reason = "MSUF_ASSISTANT_CASTBAR_DETAIL",
            apply = ApplyCastbar,
        })
    end

    local function RegisterCastbarUnitGeneralBoolean(unit, dbKey, attr, label, defaultValue, aliases)
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Castbar",
            unit = unit,
            frameType = "castbar",
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            get = function()
                local value = GeneralDB()[dbKey]
                if value == nil then return defaultValue and true or false end
                return value and true or false
            end,
            set = function(value)
                GeneralDB()[dbKey] = value and true or false
            end,
            apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_DETAIL") end,
            combatSafe = false,
        })
    end

    local BuildPlayerCastbarProviderRegistrar = A.CastbarsRegistry and A.CastbarsRegistry.BuildPlayerCastbarProviderRegistrar
    local RegisterPlayerCastbarProvider = type(BuildPlayerCastbarProviderRegistrar) == "function" and BuildPlayerCastbarProviderRegistrar({
        Registry = Registry,
        AddAliasesForUnit = AddAliasesForUnit,
        GeneralDB = GeneralDB,
        CallGlobal = CallGlobal,
        ApplyCastbar = ApplyCastbar,
        CASTBAR_KEYS = CASTBAR_KEYS,
        GetCastbarBackend = GetCastbarBackend,
        NormalizeCastbarBackend = NormalizeCastbarBackend,
        SetCastbarProvider = SetCastbarProvider,
    }) or nil
    if type(RegisterPlayerCastbarProvider) ~= "function" then return nil end

    if type(RegistryCore) == "table" then
        RegistryCore.CASTBAR_KEYS = CASTBAR_KEYS
        RegistryCore.GetCastbarBackend = GetCastbarBackend
    end

    return {
        CASTBAR_KEYS = CASTBAR_KEYS,
        CASTBAR_DETAIL_FIELDS = CASTBAR_DETAIL_FIELDS,
        GetCastbarBackend = GetCastbarBackend,
        RegisterUnitCastbarBoolean = RegisterUnitCastbarBoolean,
        RegisterGeneralNumber = RegisterGeneralNumber,
        RegisterGeneralEnumSetting = RegisterGeneralEnumSetting,
        RegisterCastbarUnitGeneralBoolean = RegisterCastbarUnitGeneralBoolean,
        RegisterPlayerCastbarProvider = RegisterPlayerCastbarProvider,
    }
end
