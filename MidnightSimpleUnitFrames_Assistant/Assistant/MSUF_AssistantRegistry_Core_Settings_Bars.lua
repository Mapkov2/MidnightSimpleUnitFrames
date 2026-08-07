-- Assistant RegistryCore bars/class-power setting registration helpers.
-- Loaded after MSUF_AssistantRegistry_Core_Settings.lua; keeps bar helper specs isolated.
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
local BarsDB = C.BarsDB
local ClampNumber = C.ClampNumber
local ApplyClassPower = C.ApplyClassPower

if type(Registry) ~= "table" or type(BarsDB) ~= "function" then return end
if type(ClampNumber) ~= "function" then return end

local function ApplyRegistrySetting(opts, dbKey, fallback)
    local reason = opts.reason or ("MSUF_ASSISTANT_" .. dbKey)
    if opts.apply then
        opts.apply(reason)
    else
        fallback(reason)
    end
end

local function RegisterBarsBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. (opts.keySuffix or dbKey),
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        valueAliases = opts.valueAliases,
        companionChanges = opts.companionChanges,
        get = function()
            if opts.get then return opts.get() end
            local value = BarsDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            if opts.set then
                opts.set(value and true or false)
                return
            end
            BarsDB()[dbKey] = value and true or false
        end,
        apply = function() ApplyRegistrySetting(opts, dbKey, ApplyClassPower) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterBarsNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
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
            if opts.get then return opts.get() end
            local value = tonumber(BarsDB()[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            value = ClampNumber(value, minValue, maxValue, opts.step or 1)
            if opts.set then
                opts.set(value)
                return
            end
            BarsDB()[dbKey] = value
        end,
        apply = function() ApplyRegistrySetting(opts, dbKey, ApplyClassPower) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local function RegisterBarsEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local value = BarsDB()[dbKey]
            if value == nil and opts.nilValue then return opts.nilValue end
            if allowed[value] then return value end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            if opts.nilValue and value == opts.nilValue then
                BarsDB()[dbKey] = nil
            else
                BarsDB()[dbKey] = value
            end
        end,
        apply = function() ApplyRegistrySetting(opts, dbKey, ApplyClassPower) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local function ClassPowerAliases(noun, ...)
    local aliases = {}
    local prefixes = { "class power", "class resource", "class resources", "class bar", "resource bar" }
    for i = 1, #prefixes do aliases[#aliases + 1] = prefixes[i] .. " " .. noun end
    for i = 1, select("#", ...) do aliases[#aliases + 1] = select(i, ...) end
    return aliases
end

C.RegisterBarsBoolean = RegisterBarsBoolean
C.RegisterBarsNumber = RegisterBarsNumber
C.RegisterBarsEnum = RegisterBarsEnum
C.ClassPowerAliases = ClassPowerAliases
