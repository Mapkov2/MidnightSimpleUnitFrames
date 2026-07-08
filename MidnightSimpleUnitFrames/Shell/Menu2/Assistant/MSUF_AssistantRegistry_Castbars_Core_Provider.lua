-- Assistant Castbars player provider registry helper.
-- Loaded before MSUF_AssistantRegistry_Castbars_Core.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.BuildPlayerCastbarProviderRegistrar(ctx)
    if type(ctx) ~= "table" then return nil end

    local Registry = ctx.Registry
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GeneralDB = ctx.GeneralDB
    local CallGlobal = ctx.CallGlobal
    local ApplyCastbar = ctx.ApplyCastbar
    local CASTBAR_KEYS = ctx.CASTBAR_KEYS or {}
    local GetCastbarBackend = ctx.GetCastbarBackend
    local NormalizeCastbarBackend = ctx.NormalizeCastbarBackend
    local SetCastbarProvider = ctx.SetCastbarProvider

    if not (Registry and type(Registry.RegisterSetting) == "function") then return nil end
    if type(AddAliasesForUnit) ~= "function" or type(GeneralDB) ~= "function" then return nil end
    if type(CallGlobal) ~= "function" or type(ApplyCastbar) ~= "function" then return nil end
    if type(GetCastbarBackend) ~= "function" or type(NormalizeCastbarBackend) ~= "function" then return nil end
    if type(SetCastbarProvider) ~= "function" then return nil end

    return function()
        local unit = "player"
        local keys = CASTBAR_KEYS[unit]
        if type(keys) ~= "table" then return end

        local aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar provider")
        AddAliasesForUnit(aliases, unit, "cast bar provider")
        AddAliasesForUnit(aliases, unit, "castbar backend")
        AddAliasesForUnit(aliases, unit, "cast bar backend")
        AddAliasesForUnit(aliases, unit, "castbar source", "zauberleisten quelle")
        AddAliasesForUnit(aliases, unit, "castbar renderer", "zauberleisten renderer")
        AddAliasesForUnit(aliases, unit, "castbar owner", "zauberleisten besitzer")
        AddAliasesForUnit(aliases, unit, "blizzard castbar provider", "blizzard zauberleisten provider")
        AddAliasesForUnit(aliases, unit, "msuf castbar provider", "msuf zauberleisten provider")
        Registry:RegisterSetting({
            key = "general." .. keys.backend,
            label = "Player Cast Bar Provider",
            category = "Player / Cast Bar",
            unit = unit,
            frameType = "castbar",
            attribute = "provider",
            type = "enum",
            aliases = aliases,
            values = { "MSUF", "BLIZZARD" },
            valueAliases = {
                msuf = "MSUF",
                ["msuf castbar"] = "MSUF",
                ["msuf cast bar"] = "MSUF",
                ["msuf zauberleiste"] = "MSUF",
                ["eigene zauberleiste"] = "MSUF",
                ["eigene castbar"] = "MSUF",
                default = "MSUF",
                standard = "MSUF",
                blizzard = "BLIZZARD",
                ["blizzard castbar"] = "BLIZZARD",
                ["blizzard cast bar"] = "BLIZZARD",
                ["blizzard zauberleiste"] = "BLIZZARD",
                ["wow castbar"] = "BLIZZARD",
                ["wow zauberleiste"] = "BLIZZARD",
            },
            get = function()
                local backend = NormalizeCastbarBackend(unit, GetCastbarBackend(unit, GeneralDB()))
                if backend == "BLIZZARD" then return "BLIZZARD" end
                if backend == "MSUF" then return "MSUF" end
                local remembered = keys.memory and NormalizeCastbarBackend(unit, GeneralDB()[keys.memory]) or nil
                return remembered == "BLIZZARD" and "BLIZZARD" or "MSUF"
            end,
            set = function(value) SetCastbarProvider(unit, value) end,
            apply = function()
                ApplyCastbar("MSUF_ASSISTANT_CASTBAR_PROVIDER", unit)
                CallGlobal("MSUF_SuppressBlizzardPlayerCastbars")
            end,
            combatSafe = false,
        })
    end
end
