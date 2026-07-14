-- Assistant Castbar per-unit setting registry.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main castbar registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.RegisterUnitSettings(ctx)
    if type(ctx) ~= "table" then return end

    local CASTBAR_KEYS = ctx.CASTBAR_KEYS or {}
    local CASTBAR_DETAIL_FIELDS = ctx.CASTBAR_DETAIL_FIELDS or {}
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterUnitCastbarBoolean = ctx.RegisterUnitCastbarBoolean
    local RegisterGeneralNumber = ctx.RegisterGeneralNumber
    local RegisterGeneralEnumSetting = ctx.RegisterGeneralEnumSetting
    local RegisterCastbarUnitGeneralBoolean = ctx.RegisterCastbarUnitGeneralBoolean
    local RegisterPlayerCastbarProvider = ctx.RegisterPlayerCastbarProvider
    local RegisterBossCastbarDetachSetting = ctx.RegisterBossCastbarDetachSetting

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(RegisterUnitCastbarBoolean) ~= "function" or type(RegisterGeneralNumber) ~= "function" then return end
    if type(RegisterGeneralEnumSetting) ~= "function" or type(RegisterCastbarUnitGeneralBoolean) ~= "function" then return end

    local WIDTH_SOURCE_VALUES = { "manual", "unitframe", "essential", "utility" }
    local WIDTH_SOURCE_ALIASES = {
        manual = "manual",
        ["manual width"] = "manual",
        custom = "manual",
        fixed = "manual",
        own = "unitframe",
        unit = "unitframe",
        unitframe = "unitframe",
        ["unit frame"] = "unitframe",
        ["auto unit frame"] = "unitframe",
        ["follow unit frame"] = "unitframe",
        cdm = "essential",
        cooldown = "essential",
        cooldowns = "essential",
        essential = "essential",
        ["essential cooldown"] = "essential",
        ["essential cooldowns"] = "essential",
        utility = "utility",
        ["utility cooldown"] = "utility",
        ["utility cooldowns"] = "utility",
    }

    for unit, keys in pairs(CASTBAR_KEYS) do
        RegisterUnitCastbarBoolean(unit)
        local aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar width", "castbar breite")
        AddAliasesForUnit(aliases, unit, "cast bar width", "zauberleiste breite")
        RegisterGeneralNumber(keys.w, unit, "castbar", "width", "Castbar Width", unit == "boss" and 176 or (unit == "focus" and 175 or 272), 40, 900, aliases)

        if keys.match then
            aliases = {}
            AddAliasesForUnit(aliases, unit, "castbar width mode")
            AddAliasesForUnit(aliases, unit, "castbar width behavior")
            AddAliasesForUnit(aliases, unit, "castbar width source")
            AddAliasesForUnit(aliases, unit, "castbar match width")
            AddAliasesForUnit(aliases, unit, "castbar auto width")
            AddAliasesForUnit(aliases, unit, "cast bar width mode")
            RegisterGeneralEnumSetting(keys.match, unit, "castbar", "widthSource", "Castbar Width Mode", "manual", WIDTH_SOURCE_VALUES, aliases, WIDTH_SOURCE_ALIASES)
        end

        aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar height", "castbar hoehe")
        AddAliasesForUnit(aliases, unit, "cast bar height", "zauberleiste hoehe")
        RegisterGeneralNumber(keys.h, unit, "castbar", "height", "Castbar Height", unit == "boss" and 12 or 18, 6, 80, aliases)

        aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar x", "castbar x")
        AddAliasesForUnit(aliases, unit, "castbar x offset", "castbar x versatz")
        RegisterGeneralNumber(keys.x, unit, "castbar", "offsetX", "Castbar X", 0, -1000, 1000, aliases)

        aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar y", "castbar y")
        AddAliasesForUnit(aliases, unit, "castbar y offset", "castbar y versatz")
        RegisterGeneralNumber(keys.y, unit, "castbar", "offsetY", "Castbar Y", 0, -1000, 1000, aliases)
    end

    if type(RegisterBossCastbarDetachSetting) == "function" then
        RegisterBossCastbarDetachSetting()
    end

    if type(RegisterPlayerCastbarProvider) == "function" then
        RegisterPlayerCastbarProvider()
    end

    for unit, fields in pairs(CASTBAR_DETAIL_FIELDS) do
        local aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar time")
        AddAliasesForUnit(aliases, unit, "cast time")
        AddAliasesForUnit(aliases, unit, "show cast time")
        RegisterCastbarUnitGeneralBoolean(unit, fields.time, "time", "Cast Time Text", true, aliases)

        aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar icon")
        AddAliasesForUnit(aliases, unit, "cast icon")
        AddAliasesForUnit(aliases, unit, "spell icon")
        RegisterCastbarUnitGeneralBoolean(unit, fields.icon, "icon", "Castbar Icon", true, aliases)

        aliases = {}
        AddAliasesForUnit(aliases, unit, "castbar text")
        AddAliasesForUnit(aliases, unit, "castbar name")
        AddAliasesForUnit(aliases, unit, "castbar spell name")
        AddAliasesForUnit(aliases, unit, "castbar spell text")
        AddAliasesForUnit(aliases, unit, "spell name")
        AddAliasesForUnit(aliases, unit, "spell name text")
        RegisterCastbarUnitGeneralBoolean(unit, fields.text, "text", "Castbar Spell Text", true, aliases)
    end
end
