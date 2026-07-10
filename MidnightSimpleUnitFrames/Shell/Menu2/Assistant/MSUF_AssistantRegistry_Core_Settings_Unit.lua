-- Assistant RegistryCore unit setting registration helpers.
-- Loaded before MSUF_AssistantRegistry_Core_Settings.lua; keeps per-unit helper specs isolated.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local UNIT_ALIASES = C.UNIT_ALIASES
local UnitDB = C.UnitDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyUnit = C.ApplyUnit
local MAX_SETTING_ALIASES = tonumber(C.MAX_SETTING_ALIASES) or 32

if type(Registry) ~= "table" or type(UnitDB) ~= "function" then return end
if type(ClampNumber) ~= "function" or type(ApplyUnit) ~= "function" then return end

local function AppendAlias(out, value)
    if #out >= MAX_SETTING_ALIASES then return false end
    out[#out + 1] = value
    return #out < MAX_SETTING_ALIASES
end

local function AddAliasesForUnit(out, unit, noun, nounDE)
    if #out >= MAX_SETTING_ALIASES then return false end
    local aliases = UNIT_ALIASES[unit] or { unit }
    for i = 1, #aliases do
        local u = aliases[i]
        if not AppendAlias(out, u .. " " .. noun) then return false end
        if not AppendAlias(out, noun .. " " .. u) then return false end
        if nounDE then
            if not AppendAlias(out, u .. " " .. nounDE) then return false end
            if not AppendAlias(out, nounDE .. " " .. u) then return false end
            if not AppendAlias(out, nounDE .. " vom " .. u) then return false end
        end
    end
    return true
end

local function RegisterUnitBoolean(unit, attr, dbKey, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. dbKey,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        get = function()
            local value = UnitDB(unit)[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            UnitDB(unit)[dbKey] = value and true or false
        end,
        apply = function()
            ApplyUnit(unit, opts.reason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or { preview = true, text = opts.text, power = opts.power, alpha = opts.alpha })
            if opts.refresh then CallGlobal(opts.refresh) end
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterUnitNumber(unit, attr, dbKey, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. dbKey,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "number",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        moveAxis = opts.moveAxis,
        moveStep = opts.moveStep,
        moveAmount = opts.moveAmount,
        intentGuard = opts.intentGuard,
        get = function()
            local value = tonumber(UnitDB(unit)[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            UnitDB(unit)[dbKey] = ClampNumber(value, minValue, maxValue, opts.step or 1)
        end,
        apply = function()
            ApplyUnit(unit, opts.reason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or { preview = true, text = opts.text, power = opts.power, alpha = opts.alpha })
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

C.AddAliasesForUnit = AddAliasesForUnit
C.RegisterUnitBoolean = RegisterUnitBoolean
C.RegisterUnitNumber = RegisterUnitNumber
