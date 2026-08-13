-- Assistant RegistryCore bars string setting helper.
-- Loaded after MSUF_AssistantRegistry_Core_Settings_Bars.lua to keep texture/string registration separate.
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
local ApplyBars = C.ApplyBars

if type(Registry) ~= "table" or type(BarsDB) ~= "function" then return end
if type(ApplyBars) ~= "function" then return end

local function ApplyRegistrySetting(opts, dbKey, fallback)
    local reason = opts.reason or ("MSUF_ASSISTANT_" .. dbKey)
    if opts.apply then
        opts.apply(reason)
    else
        fallback(reason)
    end
end

local function RegisterBarsString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Bars",
        unit = opts.unit or "global",
        frameType = opts.frameType or "globalBars",
        attribute = attr,
        type = "string",
        aliases = aliases,
        exactAliases = opts.exactAliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        mediaType = opts.mediaType,
        -- A texture key is stored canonically ("flat" -> "Flat"), so without
        -- this the transaction's verify step compares the request to the
        -- stored value, sees a difference and rolls the write back with
        -- "I could not safely apply that change".
        normalizesValue = opts.normalizeValue ~= nil,
        get = function()
            local value = BarsDB()[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            if opts.normalizeValue then value = opts.normalizeValue(value) end
            BarsDB()[dbKey] = tostring(value or "")
        end,
        apply = function() ApplyRegistrySetting(opts, dbKey, ApplyBars) end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

C.RegisterBarsString = RegisterBarsString
