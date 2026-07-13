-- Assistant UnitFrames unit string setting helper builder.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_Unit.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildSettingBaseUnitStringContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local UnitDB = ctx.UnitDB
    local UnitApply = ctx.UnitApply

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(UnitDB) ~= "function" or type(UnitApply) ~= "function" then return nil end

    local function RegisterUnitString(unit, attr, dbKey, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = unit .. "." .. (opts.keySuffix or dbKey),
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
            unit = unit,
            frameType = opts.frameType or "unitframe",
            page = opts.page,
            attribute = attr,
            type = "string",
            aliases = aliases,
            valuePrefixes = opts.valuePrefixes or aliases,
            mediaType = opts.mediaType,
            values = opts.values,
            valueAliases = opts.valueAliases,
            valueLabels = opts.valueLabels,
            closedValues = opts.closedValues,
            refreshValues = opts.refreshValues,
            normalizesValue = opts.normalizeValue ~= nil,
            get = function()
                local value = UnitDB(unit)[dbKey]
                if type(value) ~= "string" or value == "" then value = defaultValue or "" end
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                return value
            end,
            set = function(value)
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                if opts.set then
                    opts.set(unit, value)
                    return
                end
                UnitDB(unit)[dbKey] = tostring(value or "")
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

    return {
        RegisterUnitString = RegisterUnitString,
    }
end
