-- Assistant Auras unit-lane registration helpers.
-- Loaded before MSUF_AssistantRegistry_Auras_Registration.lua; consumed by the registration helper factory.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildUnitLaneRegistrationHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local ApplyAura = ctx.ApplyAura
    local AuraLaneShown = ctx.AuraLaneShown
    local SetAuraLaneShown = ctx.SetAuraLaneShown

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(ApplyAura) ~= "function" then return nil end
    if type(AuraLaneShown) ~= "function" or type(SetAuraLaneShown) ~= "function" then return nil end

    local function AuraLaneAttribute(lane, attr)
        return "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr
    end

    local function RegisterAuraUnitLaneBoolean(unit, lane, attr, label, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "auras3." .. unit .. "." .. lane .. "." .. attr,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Auras",
            page = opts.page,
            description = opts.description,
            unit = unit,
            frameType = "aura",
            attribute = AuraLaneAttribute(lane, attr),
            type = "boolean",
            aliases = aliases,
            exactAliases = opts.exactAliases,
            get = function() return AuraLaneShown(unit, lane) end,
            set = function(value) SetAuraLaneShown(unit, lane, value) end,
            apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_VISIBILITY") end,
            combatSafe = false,
        })
    end

    local function RegisterAuraUnitLaneNumber(unit, lane, attr, label, defaultValue, minValue, maxValue, step, aliases, read, write, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "auras3." .. unit .. "." .. lane .. "." .. attr,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Auras",
            unit = unit,
            frameType = "aura",
            attribute = AuraLaneAttribute(lane, attr),
            type = "number",
            aliases = aliases,
            exactAliases = opts.exactAliases or aliases,
            min = minValue,
            max = maxValue,
            step = step or 1,
            moveAxis = opts.moveAxis,
            moveStep = opts.moveStep,
            moveAmount = opts.moveAmount,
            get = read,
            set = write,
            apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_LAYOUT") end,
            combatSafe = false,
        })
    end

    local function RegisterAuraUnitLaneEnum(unit, lane, attr, label, values, valueAliases, aliases, read, write, opts)
        opts = opts or {}
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "auras3." .. unit .. "." .. lane .. "." .. attr,
            label = UNIT_LABELS[unit] .. " " .. label,
            category = UNIT_LABELS[unit] .. " / Auras",
            unit = unit,
            frameType = "aura",
            attribute = AuraLaneAttribute(lane, attr),
            type = "enum",
            aliases = aliases,
            exactAliases = opts.exactAliases or aliases,
            values = values,
            valueAliases = valueAliases,
            get = read,
            set = function(value) write(allowed[value] and value or values[1]) end,
            apply = function() ApplyAura(unit, "MSUF_ASSISTANT_AURA_LAYOUT") end,
            combatSafe = false,
        })
    end

    return {
        RegisterAuraUnitLaneBoolean = RegisterAuraUnitLaneBoolean,
        RegisterAuraUnitLaneNumber = RegisterAuraUnitLaneNumber,
        RegisterAuraUnitLaneEnum = RegisterAuraUnitLaneEnum,
    }
end
