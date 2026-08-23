-- Assistant Castbars detail setting registry.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main castbar registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

local DetailData = A.CastbarsRegistry.DetailData or {}
local CASTBAR_ICON_POSITION_VALUES = DetailData.CASTBAR_ICON_POSITION_VALUES
local CASTBAR_TEXT_POSITION_VALUES = DetailData.CASTBAR_TEXT_POSITION_VALUES
local CASTBAR_TEXT_ALIGN_VALUES = DetailData.CASTBAR_TEXT_ALIGN_VALUES
local CASTBAR_TRUNCATE_VALUES = DetailData.CASTBAR_TRUNCATE_VALUES
local CASTBAR_ICON_BORDER_VALUES = DetailData.CASTBAR_ICON_BORDER_VALUES
local CASTBAR_TIME_FORMAT_VALUES = DetailData.CASTBAR_TIME_FORMAT_VALUES
local CASTBAR_ICON_POSITION_ALIASES = DetailData.CASTBAR_ICON_POSITION_ALIASES
local CASTBAR_TEXT_POSITION_ALIASES = DetailData.CASTBAR_TEXT_POSITION_ALIASES
local CASTBAR_TEXT_ALIGN_ALIASES = DetailData.CASTBAR_TEXT_ALIGN_ALIASES
local CASTBAR_TRUNCATE_ALIASES = DetailData.CASTBAR_TRUNCATE_ALIASES
local CASTBAR_ICON_BORDER_ALIASES = DetailData.CASTBAR_ICON_BORDER_ALIASES
local CASTBAR_TIME_FORMAT_ALIASES = DetailData.CASTBAR_TIME_FORMAT_ALIASES

function A.CastbarsRegistry.RegisterDetailSettings(ctx)
    if type(ctx) ~= "table" then return end

    local CASTBAR_DETAIL_FIELDS = ctx.CASTBAR_DETAIL_FIELDS or {}
    local CastbarAliases = ctx.CastbarAliases
    local UnitCastbarAliases = ctx.UnitCastbarAliases
    local RegisterCastbarNumber = ctx.RegisterCastbarNumber
    local RegisterGeneralNumber = ctx.RegisterGeneralNumber
    local RegisterGeneralEnumSetting = ctx.RegisterGeneralEnumSetting
    local ApplyCastbarTextures = ctx.ApplyCastbarTextures
    local ApplyCastbar = ctx.ApplyCastbar

    if type(CastbarAliases) ~= "function" or type(UnitCastbarAliases) ~= "function" then return end
    if type(RegisterCastbarNumber) ~= "function" or type(RegisterGeneralNumber) ~= "function" then return end
    if type(RegisterGeneralEnumSetting) ~= "function" or type(ApplyCastbarTextures) ~= "function" then return end
    if type(CASTBAR_ICON_POSITION_VALUES) ~= "table" or type(CASTBAR_TEXT_POSITION_VALUES) ~= "table" then return end
    if type(CASTBAR_TEXT_ALIGN_VALUES) ~= "table" or type(CASTBAR_TRUNCATE_VALUES) ~= "table" then return end
    if type(CASTBAR_ICON_BORDER_VALUES) ~= "table" or type(CASTBAR_TIME_FORMAT_VALUES) ~= "table" then return end
    if type(CASTBAR_ICON_POSITION_ALIASES) ~= "table" or type(CASTBAR_TEXT_POSITION_ALIASES) ~= "table" then return end
    if type(CASTBAR_TEXT_ALIGN_ALIASES) ~= "table" or type(CASTBAR_TRUNCATE_ALIASES) ~= "table" then return end
    if type(CASTBAR_ICON_BORDER_ALIASES) ~= "table" or type(CASTBAR_TIME_FORMAT_ALIASES) ~= "table" then return end

    RegisterCastbarNumber("castbarIconSize", "iconSize", "Castbar Icon Size", 0, 0, 128, CastbarAliases("icon size", "castbar icon size", "spell icon size"), {
        reason = "MSUF2_CASTBAR_ICON_SIZE",
        apply = ApplyCastbarTextures,
        description = "Global cast bar icon size override. 0 follows the cast bar height.",
    })
    RegisterCastbarNumber("castbarIconOffsetX", "iconOffsetX", "Castbar Icon X Offset", 0, -300, 300, CastbarAliases("icon x", "icon x offset", "castbar icon x", "castbar icon x offset"), {
        reason = "MSUF2_CASTBAR_ICON_X",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarNumber("castbarIconOffsetY", "iconOffsetY", "Castbar Icon Y Offset", 0, -300, 300, CastbarAliases("icon y", "icon y offset", "castbar icon y", "castbar icon y offset"), {
        reason = "MSUF2_CASTBAR_ICON_Y",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarNumber("castbarSpellNameFontSize", "spellNameFontSize", "Castbar Spell Name Font Size", 0, 0, 48, CastbarAliases("spell name font size", "castbar text font size", "castbar spell text font size", "spell text size"), {
        reason = "MSUF2_CASTBAR_SPELL_FONT_SIZE",
        apply = ApplyCastbar,
        description = "Global cast bar spell-name font override. 0 follows the global font size.",
    })
    RegisterCastbarNumber("castbarTimeFontSize", "timeFontSize", "Castbar Time Font Size", 0, 0, 48, CastbarAliases("time font size", "castbar time font size", "castbar timer font size", "castbar time text size"), {
        reason = "MSUF2_CASTBAR_TIME_FONT_SIZE",
        apply = ApplyCastbar,
        description = "Global cast bar time font override. 0 follows the spell-name or global font size.",
    })

    local detail = {
        player = { prefix = "castbarPlayer", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        target = { prefix = "castbarTarget", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        focus = { prefix = "castbarFocus", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        boss = { prefix = "bossCast", iconDefault = 0, textX = 0, textY = 0, timeX = 0, timeY = 0 },
    }
    for unit, spec in pairs(detail) do
        local aliases
        aliases = UnitCastbarAliases(unit, "castbar icon size", "castbar spell icon size")
        RegisterGeneralNumber(spec.prefix .. "IconSize", unit, "castbar", "iconSize", "Castbar Icon Size", spec.iconDefault, 0, 128, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon zoom", "castbar spell icon zoom")
        RegisterGeneralNumber(spec.prefix .. "IconZoom", unit, "castbar", "iconZoom", "Castbar Icon Zoom", 100, 100, 200, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon position", "castbar spell icon position")
        RegisterGeneralEnumSetting(spec.prefix .. "IconPosition", unit, "castbar", "iconPosition", "Castbar Icon Position", "LEFT", CASTBAR_ICON_POSITION_VALUES, aliases, CASTBAR_ICON_POSITION_ALIASES)
        aliases = UnitCastbarAliases(unit, "castbar icon x", "castbar icon x offset")
        RegisterGeneralNumber(spec.prefix .. "IconOffsetX", unit, "castbar", "iconOffsetX", "Castbar Icon X Offset", 0, -300, 300, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon y", "castbar icon y offset")
        RegisterGeneralNumber(spec.prefix .. "IconOffsetY", unit, "castbar", "iconOffsetY", "Castbar Icon Y Offset", 0, -300, 300, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon spacing", "castbar spell icon spacing")
        RegisterGeneralNumber(spec.prefix .. "IconSpacing", unit, "castbar", "iconSpacing", "Castbar Icon Spacing", 1, 0, 40, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon border thickness", "castbar icon border size", "castbar spell icon border thickness")
        RegisterGeneralNumber(spec.prefix .. "IconBorderThickness", unit, "castbar", "iconBorderThickness", "Castbar Icon Border Thickness", 0, 0, 8, aliases)
        aliases = UnitCastbarAliases(unit, "castbar icon border", "castbar icon border style")
        RegisterGeneralEnumSetting(spec.prefix .. "IconBorderStyle", unit, "castbar", "iconBorderStyle", "Castbar Icon Border Style", "DARK", CASTBAR_ICON_BORDER_VALUES, aliases, CASTBAR_ICON_BORDER_ALIASES)
        aliases = UnitCastbarAliases(unit, "castbar icon layer", "castbar icon frame level", "castbar icon level")
        RegisterGeneralNumber(spec.prefix .. "IconFrameLevelOffset", unit, "castbar", "iconFrameLevelOffset", "Castbar Icon Layer", 0, 0, 30, aliases)
        aliases = UnitCastbarAliases(unit, "castbar layer", "castbar frame layer", "castbar frame level")
        RegisterGeneralNumber(spec.prefix .. "FrameLevelOffset", unit, "castbar", "frameLevelOffset", "Castbar Frame Layer", 6, 0, 30, aliases)

        aliases = UnitCastbarAliases(unit, "castbar spell name position", "castbar spell text position", "castbar text position")
        RegisterGeneralEnumSetting(spec.prefix .. "SpellNamePosition", unit, "castbar", "spellNamePosition", "Castbar Spell Name Position", "LEFT", CASTBAR_TEXT_POSITION_VALUES, aliases, CASTBAR_TEXT_POSITION_ALIASES)
        aliases = UnitCastbarAliases(unit, "castbar text x", "castbar spell name x", "castbar spell text x", "castbar text x offset")
        RegisterGeneralNumber(spec.prefix .. "TextOffsetX", unit, "castbar", "textOffsetX", "Castbar Spell Text X Offset", spec.textX, -300, 300, aliases)
        aliases = UnitCastbarAliases(unit, "castbar text y", "castbar spell name y", "castbar spell text y", "castbar text y offset")
        RegisterGeneralNumber(spec.prefix .. "TextOffsetY", unit, "castbar", "textOffsetY", "Castbar Spell Text Y Offset", spec.textY, -300, 300, aliases)
        -- SpellNameAlign is retained in old profiles only. SpellNamePosition
        -- now owns both the visible anchor and its natural justification.
        aliases = UnitCastbarAliases(unit, "castbar spell name font size", "castbar text font size", "castbar spell text size")
        RegisterGeneralNumber(spec.prefix .. "SpellNameFontSize", unit, "castbar", "spellNameFontSize", "Castbar Spell Name Font Size", 0, 0, 48, aliases)
        aliases = UnitCastbarAliases(unit,
            "castbar spell name manual width", "castbar spell text manual width", "castbar text manual width",
            "castbar spell name max width", "castbar spell text max width", "castbar text max width")
        RegisterGeneralNumber(spec.prefix .. "SpellNameMaxWidth", unit, "castbar", "spellNameMaxWidth", "Castbar Spell Name Manual Width", 0, 0, 500, aliases)
        aliases = UnitCastbarAliases(unit,
            "castbar spell name width behavior", "castbar spell text width behavior", "castbar text width behavior",
            "castbar spell name truncate", "castbar spell text truncate", "castbar text truncate")
        RegisterGeneralEnumSetting(spec.prefix .. "SpellNameTruncate", unit, "castbar", "spellNameTruncate", "Castbar Spell Name Width Behavior", "AUTO", CASTBAR_TRUNCATE_VALUES, aliases, CASTBAR_TRUNCATE_ALIASES)

        aliases = UnitCastbarAliases(unit, "castbar time format", "cast time format", "castbar timer format")
        RegisterGeneralEnumSetting(CASTBAR_DETAIL_FIELDS[unit].timeFormat, unit, "castbar", "timeFormat", "Castbar Time Format", "CURRENT", CASTBAR_TIME_FORMAT_VALUES, aliases, CASTBAR_TIME_FORMAT_ALIASES)
        aliases = UnitCastbarAliases(unit, "castbar time position", "castbar time text position", "castbar timer position")
        RegisterGeneralEnumSetting(spec.prefix .. "TimePosition", unit, "castbar", "timePosition", "Castbar Time Position", "RIGHT", CASTBAR_TEXT_POSITION_VALUES, aliases, CASTBAR_TEXT_POSITION_ALIASES)
        aliases = UnitCastbarAliases(unit, "castbar time x", "castbar time text x", "castbar timer x", "castbar time x offset")
        RegisterGeneralNumber(spec.prefix .. "TimeOffsetX", unit, "castbar", "timeOffsetX", "Castbar Time Text X Offset", spec.timeX, -300, 300, aliases)
        aliases = UnitCastbarAliases(unit, "castbar time y", "castbar time text y", "castbar timer y", "castbar time y offset")
        RegisterGeneralNumber(spec.prefix .. "TimeOffsetY", unit, "castbar", "timeOffsetY", "Castbar Time Text Y Offset", spec.timeY, -300, 300, aliases)
        aliases = UnitCastbarAliases(unit, "castbar time font size", "castbar timer font size", "castbar time text size")
        RegisterGeneralNumber(spec.prefix .. "TimeFontSize", unit, "castbar", "timeFontSize", "Castbar Time Font Size", 0, 0, 48, aliases)

        if unit ~= "player" then
            aliases = UnitCastbarAliases(unit, "castbar destination name position",
                "castbar target name position", "cast target name position")
            RegisterGeneralEnumSetting(spec.prefix .. "TargetNamePosition", unit, "castbar", "targetNamePosition",
                "Castbar Target Name Position", "BELOW", CASTBAR_TEXT_POSITION_VALUES, aliases, CASTBAR_TEXT_POSITION_ALIASES)
            aliases = UnitCastbarAliases(unit, "castbar destination name font size",
                "castbar target name font size", "cast target name size")
            RegisterGeneralNumber(spec.prefix .. "TargetNameFontSize", unit, "castbar", "targetNameFontSize",
                "Castbar Target Name Font Size", unit == "target" and 12 or 10, 6, 48, aliases)
            aliases = UnitCastbarAliases(unit, "castbar destination name alignment",
                "castbar target name alignment", "cast target name alignment")
            RegisterGeneralEnumSetting(spec.prefix .. "TargetNameAlign", unit, "castbar", "targetNameAlign",
                "Castbar Target Name Alignment", "RIGHT", CASTBAR_TEXT_ALIGN_VALUES, aliases, CASTBAR_TEXT_ALIGN_ALIASES)
            aliases = UnitCastbarAliases(unit, "castbar destination name x offset",
                "castbar target name x", "castbar target name x offset")
            RegisterGeneralNumber(spec.prefix .. "TargetNameOffsetX", unit, "castbar", "targetNameOffsetX",
                "Castbar Target Name X Offset", unit == "target" and 2 or 0, -300, 300, aliases)
            aliases = UnitCastbarAliases(unit, "castbar destination name y offset",
                "castbar target name y", "castbar target name y offset")
            RegisterGeneralNumber(spec.prefix .. "TargetNameOffsetY", unit, "castbar", "targetNameOffsetY",
                "Castbar Target Name Y Offset", 1, -300, 300, aliases)
        end
    end
end
