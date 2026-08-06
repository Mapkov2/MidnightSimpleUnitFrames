-- Assistant UnitFrames unit setting helper builder.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core_SettingsBase.lua; isolates generic unit setting registrars.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildSettingBaseUnitContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB
    local ClampNumber = ctx.ClampNumber
    local AllowedMap = ctx.AllowedMap
    local UnitApply = ctx.UnitApply

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(UnitDB) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(ClampNumber) ~= "function" or type(AllowedMap) ~= "function" then return nil end
    if type(UnitApply) ~= "function" then return nil end

    local function RegisterUnitBooleanSetting(unit, attr, dbKey, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = unit .. "." .. (opts.keySuffix or dbKey),
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
            unit = unit,
            frameType = opts.frameType or "unitframe",
            page = opts.page,
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            matchLabel = opts.matchLabel,
            get = function()
                if opts.get then return opts.get(unit) end
                local value = UnitDB(unit)[dbKey]
                if value == nil then return defaultValue and true or false end
                return value and true or false
            end,
            set = function(value)
                if opts.set then
                    opts.set(unit, value and true or false)
                    return
                end
                UnitDB(unit)[dbKey] = value and true or false
            end,
            apply = function()
                if opts.apply then
                    opts.apply(unit)
                else
                    UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey))
                end
            end,
            combatSafe = opts.combatSafe == true,
            applyWhenUnchanged = opts.applyWhenUnchanged == true,
            requiresReload = opts.requiresReload == true,
            description = opts.description,
        })
    end

    local function RegisterUnitNumberSetting(unit, attr, dbKey, label, defaultValue, minValue, maxValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = unit .. "." .. (opts.keySuffix or dbKey),
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
            unit = unit,
            frameType = opts.frameType or "unitframe",
            page = opts.page,
            attribute = attr,
            type = "number",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            min = minValue,
            max = maxValue,
            step = opts.step or 1,
            percent = opts.percent == true,
            moveAxis = opts.moveAxis,
            moveStep = opts.moveStep,
            moveAmount = opts.moveAmount,
            intentGuard = opts.intentGuard,
            get = function()
                if opts.get then return opts.get(unit) end
                local value = tonumber(UnitDB(unit)[dbKey])
                if value == nil and opts.fallbackGeneral then value = tonumber(GeneralDB()[dbKey]) end
                if value == nil then return defaultValue end
                return value
            end,
            set = function(value)
                value = ClampNumber(value, minValue, maxValue, opts.step or 1)
                if opts.set then
                    opts.set(unit, value)
                    return
                end
                UnitDB(unit)[dbKey] = value
            end,
            apply = function()
                if opts.apply then
                    opts.apply(unit)
                else
                    UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey))
                end
            end,
            combatSafe = opts.combatSafe == true,
            description = opts.description,
        })
    end

    local function RegisterUnitEnum(unit, attr, dbKey, label, defaultValue, values, aliases, opts)
        opts = opts or {}
        local allowed = AllowedMap(values)
        Registry:RegisterSetting({
            key = unit .. "." .. (opts.keySuffix or dbKey),
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
            unit = unit,
            frameType = opts.frameType or "unitframe",
            page = opts.page,
            attribute = attr,
            type = "enum",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            values = values,
            valueLabels = opts.valueLabels,
            valueAliases = opts.valueAliases,
            -- Some enum values are resolved by the setter rather than stored
            -- verbatim, so the value read back is legitimately not the value
            -- requested. Settings that do this must say so, or the transaction
            -- treats the difference as a failed write and rolls it back.
            normalizesValue = opts.normalizesValue == true,
            get = function()
                if opts.get then return opts.get(unit) end
                local value = UnitDB(unit)[dbKey]
                if allowed[value] then return value end
                if opts.fallbackGeneral then
                    value = GeneralDB()[dbKey]
                    if allowed[value] then return value end
                end
                return defaultValue
            end,
            set = function(value)
                if not allowed[value] then value = defaultValue end
                if opts.set then
                    opts.set(unit, value)
                    return
                end
                UnitDB(unit)[dbKey] = value
            end,
            apply = function() UnitApply(unit, opts, "MSUF_ASSISTANT_" .. tostring(dbKey)) end,
            combatSafe = opts.combatSafe == true,
            description = opts.description,
        })
    end

    local BuildSettingBaseUnitStringContext = A.UnitframesRegistry and A.UnitframesRegistry.BuildSettingBaseUnitStringContext
    local StringContext = type(BuildSettingBaseUnitStringContext) == "function" and BuildSettingBaseUnitStringContext({
        Registry = Registry,
        UNIT_LABELS = UNIT_LABELS,
        UnitDB = UnitDB,
        UnitApply = UnitApply,
    }) or nil
    if type(StringContext) ~= "table" or type(StringContext.RegisterUnitString) ~= "function" then return nil end
    local RegisterUnitString = StringContext.RegisterUnitString

    return {
        RegisterUnitBooleanSetting = RegisterUnitBooleanSetting,
        RegisterUnitNumberSetting = RegisterUnitNumberSetting,
        RegisterUnitEnum = RegisterUnitEnum,
        RegisterUnitString = RegisterUnitString,
    }
end
