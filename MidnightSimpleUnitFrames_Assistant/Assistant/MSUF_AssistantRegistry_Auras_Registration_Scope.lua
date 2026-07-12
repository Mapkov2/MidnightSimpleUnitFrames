-- Assistant Auras scope registration helpers.
-- Loaded before MSUF_AssistantRegistry_Auras_Registration.lua; isolates scope-level setting registrars.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildScopeRegistrationHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local AuraScopeLabel = ctx.AuraScopeLabel
    local AuraSharedBool = ctx.AuraSharedBool
    local SetAuraSharedBool = ctx.SetAuraSharedBool
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local ApplyAuraScope = ctx.ApplyAuraScope

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AuraScopeLabel) ~= "function" or type(ApplyAuraScope) ~= "function" then return nil end
    if type(AuraSharedBool) ~= "function" or type(SetAuraSharedBool) ~= "function" then return nil end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return nil end

    local function RegisterAuraScopeLaneBoolean(scope, lane, attr, label, defaultValue, aliases, read, write, applyText)
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. lane .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
            category = AuraScopeLabel(scope) .. " / Aura Style",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
            type = "boolean",
            aliases = aliases,
            get = read,
            set = write,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    local function RegisterAuraScopeLaneNumber(scope, lane, attr, label, defaultValue, minValue, maxValue, aliases, read, write, applyText)
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. lane .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
            category = AuraScopeLabel(scope) .. " / Aura Style",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
            type = "number",
            aliases = aliases,
            min = minValue,
            max = maxValue,
            step = 1,
            get = read,
            set = write,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    local function RegisterAuraScopeLaneEnum(scope, lane, attr, label, values, valueAliases, aliases, read, write, applyText)
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. lane .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. (lane == "buff" and "Buff " or "Debuff ") .. label,
            category = AuraScopeLabel(scope) .. " / Aura Style",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. (lane == "buff" and "Buff" or "Debuff") .. attr,
            type = "enum",
            aliases = aliases,
            values = values,
            valueAliases = valueAliases,
            get = read,
            set = function(value) write(allowed[value] and value or values[1]) end,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    local function RegisterAuraScopeBoolean(scope, attr, label, defaultValue, aliases, read, write, applyText, exactAliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. label,
            category = AuraScopeLabel(scope) .. " / Auras",
            page = opts.page,
            description = opts.description,
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. attr,
            type = "boolean",
            aliases = aliases,
            exactAliases = exactAliases,
            get = read or function() return AuraSharedBool(attr, defaultValue) end,
            set = write or function(value) SetAuraSharedBool(attr, value) end,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    local function RegisterAuraScopeNumber(scope, attr, label, defaultValue, minValue, maxValue, aliases, read, write, applyText)
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. label,
            category = AuraScopeLabel(scope) .. " / Auras",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. attr,
            type = "number",
            aliases = aliases,
            min = minValue,
            max = maxValue,
            step = 1,
            get = read or function() return AuraReadNumber(scope, attr, defaultValue, minValue, maxValue) end,
            set = write or function(value) AuraWriteNumber(scope, attr, value, minValue, maxValue) end,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    local function RegisterAuraScopeEnum(scope, attr, label, values, valueAliases, aliases, read, write, applyText)
        local allowed = {}
        for i = 1, #values do allowed[values[i]] = true end
        Registry:RegisterSetting({
            key = "auras3." .. scope .. "." .. attr,
            label = AuraScopeLabel(scope) .. " " .. label,
            category = AuraScopeLabel(scope) .. " / Auras",
            unit = scope,
            frameType = "aura",
            attribute = "aura" .. attr,
            type = "enum",
            aliases = aliases,
            values = values,
            valueAliases = valueAliases,
            get = read,
            set = function(value) write(allowed[value] and value or values[1]) end,
            apply = function() ApplyAuraScope(scope, applyText) end,
            combatSafe = false,
        })
    end

    return {
        RegisterAuraScopeLaneBoolean = RegisterAuraScopeLaneBoolean,
        RegisterAuraScopeLaneNumber = RegisterAuraScopeLaneNumber,
        RegisterAuraScopeLaneEnum = RegisterAuraScopeLaneEnum,
        RegisterAuraScopeBoolean = RegisterAuraScopeBoolean,
        RegisterAuraScopeNumber = RegisterAuraScopeNumber,
        RegisterAuraScopeEnum = RegisterAuraScopeEnum,
    }
end
