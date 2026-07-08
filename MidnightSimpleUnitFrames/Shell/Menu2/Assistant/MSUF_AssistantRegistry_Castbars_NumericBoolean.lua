-- Assistant Castbars numeric-boolean setting registrar.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main castbar registry builds this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.BuildNumericBooleanRegistrar(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB
    local ApplyCastbar = ctx.ApplyCastbar
    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GeneralDB) ~= "function" or type(ApplyCastbar) ~= "function" then return nil end

    return function(dbKey, attr, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "general." .. dbKey,
            label = label,
            category = opts.category or "Appearance / Cast Bars",
            unit = opts.unit or "global",
            frameType = opts.frameType or "castbar",
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            get = function()
                local value = tonumber(GeneralDB()[dbKey])
                if value == nil then return defaultValue and true or false end
                return value ~= 0
            end,
            set = function(value)
                GeneralDB()[dbKey] = value and 1 or 0
            end,
            apply = function()
                local reason = opts.reason or ("MSUF_ASSISTANT_" .. dbKey)
                if opts.apply then opts.apply(reason) else ApplyCastbar(reason, opts.unit) end
            end,
            combatSafe = opts.combatSafe == true,
            description = opts.description,
        })
    end
end
