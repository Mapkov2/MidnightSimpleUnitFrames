-- Assistant UnitFrames general nested setting helper builder.
-- Loaded before MSUF_AssistantRegistry_Unitframes_Core_SettingsBase.lua; isolates non-unit generic registry glue.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildSettingBaseGeneralContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local GeneralDB = ctx.GeneralDB

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(GeneralDB) ~= "function" then return nil end

    local function RegisterGeneralNestedBoolean(rootKey, dbKey, attr, label, defaultValue, aliases, opts)
        opts = opts or {}
        Registry:RegisterSetting({
            key = "general." .. rootKey .. "." .. dbKey,
            label = label,
            category = opts.category or "Global",
            unit = opts.unit or "global",
            frameType = opts.frameType or "unitframe",
            attribute = attr,
            type = "boolean",
            aliases = aliases,
            get = function()
                local root = GeneralDB()[rootKey]
                if type(root) == "table" then
                    local value = root[dbKey]
                    if value ~= nil then return value and true or false end
                end
                return defaultValue and true or false
            end,
            set = function(value)
                local g = GeneralDB()
                g[rootKey] = type(g[rootKey]) == "table" and g[rootKey] or {}
                g[rootKey][dbKey] = value and true or false
            end,
            apply = function()
                if opts.apply then opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end
            end,
            combatSafe = opts.combatSafe == true,
            description = opts.description,
        })
    end

    return {
        RegisterGeneralNestedBoolean = RegisterGeneralNestedBoolean,
    }
end
