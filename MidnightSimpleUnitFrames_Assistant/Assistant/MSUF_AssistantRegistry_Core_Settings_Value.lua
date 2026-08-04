-- Assistant RegistryCore value setting helpers.
-- Loaded before MSUF_AssistantRegistry_Core_Settings.lua; isolates generic number/string/mapped enum registrars.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

function C.BuildGeneralValueSettingHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local ClampNumber = ctx.ClampNumber
    local ApplyGeneral = ctx.ApplyGeneral
    local ApplyRegistrySetting = ctx.ApplyRegistrySetting

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GeneralDB) ~= "function" or type(ClampNumber) ~= "function" then return nil end
    if type(ApplyGeneral) ~= "function" or type(ApplyRegistrySetting) ~= "function" then return nil end

    local function RegisterGeneralNumberSetting(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = label,
            category = opts.category or "Global",
            unit = opts.unit or "global",
            frameType = opts.frameType or "global",
            page = opts.page,
            attribute = attr,
            type = "number",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            min = minValue,
            max = maxValue,
            step = opts.step or 1,
            relativeStep = opts.relativeStep,
            percent = opts.percent == true,
            booleanOnValue = opts.booleanOnValue,
            booleanOffValue = opts.booleanOffValue,
            booleanAliases = opts.booleanAliases,
            moveAxis = opts.moveAxis,
            moveStep = opts.moveStep,
            moveAmount = opts.moveAmount,
            intentGuard = opts.intentGuard,
            get = function()
                local value = tonumber(GeneralDB()[dbKey])
                if value == nil then return defaultValue end
                return value
            end,
            set = function(value)
                GeneralDB()[dbKey] = ClampNumber(value, minValue, maxValue, opts.step or 1)
            end,
            apply = function() ApplyRegistrySetting(opts, dbKey, ApplyGeneral, { preview = true, applyAll = false }) end,
            combatSafe = opts.combatSafe == true,
            confirmRequired = opts.confirmRequired == true,
            requiresReload = opts.requiresReload == true,
            matchLabel = opts.matchLabel,
            description = opts.description,
        })
    end

    local function RegisterGeneralString(dbKey, attr, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = label,
            category = opts.category or "Global",
            unit = opts.unit or "global",
            frameType = opts.frameType or "global",
            attribute = attr,
            type = "string",
            aliases = aliases,
            valuePrefixes = opts.valuePrefixes or aliases,
            mediaType = opts.mediaType,
            normalizesValue = opts.normalizeValue ~= nil,
            get = function()
                local value = GeneralDB()[dbKey]
                if type(value) ~= "string" or value == "" then value = defaultValue or "" end
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                return value
            end,
            set = function(value)
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                GeneralDB()[dbKey] = tostring(value or "")
            end,
            apply = function() ApplyRegistrySetting(opts, dbKey, ApplyGeneral, { preview = true, applyAll = false }) end,
            combatSafe = opts.combatSafe == true,
            confirmRequired = opts.confirmRequired == true,
            description = opts.description,
        })
    end

    local function RegisterGeneralMappedEnum(dbKey, attr, label, defaultValue, values, storageByValue, aliases, opts)
        opts = opts or {}
        local allowed = {}
        local valueByStorage = {}
        for i = 1, #(values or {}) do
            local value = values[i]
            allowed[value] = true
            valueByStorage[storageByValue[value]] = value
        end
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = label,
            category = opts.category or "Global",
            unit = opts.unit or "global",
            frameType = opts.frameType or "global",
            attribute = attr,
            type = "enum",
            aliases = aliases,
            values = values,
            valueAliases = opts.valueAliases,
            get = function()
                local stored = GeneralDB()[dbKey]
                local value = valueByStorage[stored]
                if value then return value end
                return defaultValue
            end,
            set = function(value)
                if not allowed[value] then value = defaultValue end
                GeneralDB()[dbKey] = storageByValue[value]
                if opts.afterSet then opts.afterSet(value, storageByValue[value]) end
            end,
            apply = function() ApplyRegistrySetting(opts, dbKey, ApplyGeneral, { preview = true, applyAll = false }) end,
            combatSafe = opts.combatSafe == true,
            confirmRequired = opts.confirmRequired == true,
            description = opts.description,
        })
    end

    return {
        RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
        RegisterGeneralString = RegisterGeneralString,
        RegisterGeneralMappedEnum = RegisterGeneralMappedEnum,
    }
end
