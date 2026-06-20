-- Assistant RegistryCore gameplay setting helpers.
-- Extends RegistryCore after base DB/apply helpers are available.
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
local GameplayDB = C.GameplayDB
local ClampNumber = C.ClampNumber
local ApplyGameplay = C.ApplyGameplay

if not (Registry and type(Registry.RegisterSetting) == "function") then return end
if type(GameplayDB) ~= "function" or type(ClampNumber) ~= "function" or type(ApplyGameplay) ~= "function" then return end

local function RegisterGameplayBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            GameplayDB()[dbKey] = value and true or false
        end,
        apply = function() ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterGameplayNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        get = function()
            local value = tonumber(GameplayDB()[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            value = ClampNumber(value, minValue, maxValue, opts.step or 1)
            if dbKey == "nameplateMeleeSpellID" and M and type(M.SetGameplayMeleeSpellID) == "function" then
                M.SetGameplayMeleeSpellID(value)
                return
            end
            GameplayDB()[dbKey] = value
            if dbKey == "nameplateMeleeSpellID" then
                local g = GameplayDB()
                if g.meleeSpellPerSpec == true then
                    local specID = MSUF and type(MSUF.MSUF_GetPlayerSpecID) == "function" and MSUF.MSUF_GetPlayerSpecID() or nil
                    if specID then
                        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
                        g.nameplateMeleeSpellIDBySpec[specID] = value
                    end
                end
                if g.meleeSpellPerClass == true and UnitClass then
                    local _, class = UnitClass("player")
                    if class then
                        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
                        g.nameplateMeleeSpellIDByClass[class] = value
                    end
                end
            end
        end,
        apply = function() ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterGameplayEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if allowed[value] then return value end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            GameplayDB()[dbKey] = value
        end,
        apply = function() ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterGameplayString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            GameplayDB()[dbKey] = tostring(value or "")
        end,
        apply = function() ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function GameplayAliases(prefix, noun, ...)
    local aliases = {
        prefix .. " " .. noun,
        noun .. " " .. prefix,
    }
    for i = 1, select("#", ...) do aliases[#aliases + 1] = select(i, ...) end
    return aliases
end

C.RegisterGameplayBoolean = RegisterGameplayBoolean
C.RegisterGameplayNumber = RegisterGameplayNumber
C.RegisterGameplayEnum = RegisterGameplayEnum
C.RegisterGameplayString = RegisterGameplayString
C.GameplayAliases = GameplayAliases
