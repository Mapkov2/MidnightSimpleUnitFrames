-- Assistant GroupFrames text setting registry.
-- Keeps group name/health/power text metadata out of the main settings file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterTextSettings(ctx, scope)
    if type(ctx) ~= "table" then return end
    scope = tostring(scope or "")
    if scope == "" then return end

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GeneralDB = ctx.GeneralDB
    local GroupDB = ctx.GroupDB
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber
    local RegisterGroupEnum = ctx.RegisterGroupEnum
    local RegisterGroupTextMode = ctx.RegisterGroupTextMode
    local RegisterGroupDelimiter = ctx.RegisterGroupDelimiter
    local GROUP_ANCHOR_VALUES = ctx.GROUP_ANCHOR_VALUES or {}
    local GROUP_ANCHOR_ALIASES = ctx.GROUP_ANCHOR_ALIASES or {}

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end
    if type(RegisterGroupEnum) ~= "function" or type(RegisterGroupTextMode) ~= "function" then return end
    if type(RegisterGroupDelimiter) ~= "function" then return end

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "hide name on dead offline")
    AddAliasesForUnit(aliases, scope, "hide name when dead")
    AddAliasesForUnit(aliases, scope, "hide name when offline")
    RegisterGroupBoolean(scope, "hideNameOnDeadOffline", "hideNameOnDeadOffline", "Hide Name on Dead or Offline", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name anchor")
    AddAliasesForUnit(aliases, scope, "name text anchor")
    RegisterGroupEnum(scope, "nameAnchor", "nameAnchor", "Name Anchor", "LEFT", GROUP_ANCHOR_VALUES, GROUP_ANCHOR_ALIASES, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name x")
    AddAliasesForUnit(aliases, scope, "name x offset")
    AddAliasesForUnit(aliases, scope, "name text x offset")
    RegisterGroupNumber(scope, "nameOffsetX", "nameOffsetX", "Name X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name y")
    AddAliasesForUnit(aliases, scope, "name y offset")
    AddAliasesForUnit(aliases, scope, "name text y offset")
    RegisterGroupNumber(scope, "nameOffsetY", "nameOffsetY", "Name Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "name layer")
    AddAliasesForUnit(aliases, scope, "name text layer")
    RegisterGroupNumber(scope, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5, 0, 30, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp left text")
    AddAliasesForUnit(aliases, scope, "health left text")
    AddAliasesForUnit(aliases, scope, "left hp text")
    RegisterGroupTextMode(scope, "healthTextLeft", "textLeft", "Left HP Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp right text")
    AddAliasesForUnit(aliases, scope, "health right text")
    AddAliasesForUnit(aliases, scope, "right hp text")
    RegisterGroupTextMode(scope, "healthTextRight", "textRight", "Right HP Text", "NONE", aliases)

    local function PercentSignVisible(scopeKey, dbKey)
        local conf = type(GroupDB) == "function" and GroupDB(scopeKey) or nil
        local value = type(conf) == "table" and conf[dbKey] or nil
        if value ~= nil then return value ~= true end
        local g = type(GeneralDB) == "function" and GeneralDB() or nil
        return not (type(g) == "table" and g.hidePercentSymbol == true)
    end
    local function SetPercentSignVisible(scopeKey, dbKey, visible)
        local conf = type(GroupDB) == "function" and GroupDB(scopeKey) or nil
        if type(conf) == "table" then
            conf[dbKey] = not (visible and true or false)
        end
    end
    local function RegisterHidePercent(attr, dbKey, label, ...)
        aliases = {}
        for i = 1, select("#", ...) do
            AddAliasesForUnit(aliases, scope, select(i, ...))
        end
        AddAliasesForUnit(aliases, scope, "hide percent sign")
        AddAliasesForUnit(aliases, scope, "hide percent symbol")
        AddAliasesForUnit(aliases, scope, "hide % sign")
        RegisterGroupBoolean(scope, attr, dbKey, label, false, "visual", aliases, { matchLabel = false })
    end
    local function RegisterPercentSign(attr, dbKey, label, ...)
        aliases = {}
        for i = 1, select("#", ...) do
            AddAliasesForUnit(aliases, scope, select(i, ...))
        end
        AddAliasesForUnit(aliases, scope, "percent sign")
        AddAliasesForUnit(aliases, scope, "percent symbol")
        AddAliasesForUnit(aliases, scope, "% sign")
        RegisterGroupBoolean(scope, attr, dbKey, label, true, "visual", aliases, {
            keySuffix = attr,
            get = function(scopeKey) return PercentSignVisible(scopeKey, dbKey) end,
            set = function(scopeKey, value) SetPercentSignVisible(scopeKey, dbKey, value) end,
        })
    end
    RegisterHidePercent("healthTextLeftHidePercentSymbol", "hpTextLeftHidePercentSymbol", "Left HP Hide % Sign", "hp left hide percent sign", "left hp hide percent sign", "health left hide percent sign", "left health hide percent sign", "hide hp left percent sign", "hide health left percent sign", "hide left hp percent sign")
    RegisterPercentSign("healthTextLeftPercentSymbol", "hpTextLeftHidePercentSymbol", "Left HP % Sign", "hp left percent sign", "health left percent sign", "left hp percent sign", "hp left % sign", "left hp % sign")
    RegisterHidePercent("healthTextCenterHidePercentSymbol", "hpTextCenterHidePercentSymbol", "Center HP Hide % Sign", "hp center hide percent sign", "center hp hide percent sign", "hp middle hide percent sign", "health center hide percent sign", "center health hide percent sign", "hide hp center percent sign", "hide health center percent sign", "hide center hp percent sign", "hide hp middle percent sign")
    RegisterPercentSign("healthTextCenterPercentSymbol", "hpTextCenterHidePercentSymbol", "Center HP % Sign", "hp center percent sign", "health center percent sign", "center hp percent sign", "hp middle percent sign", "middle hp percent sign", "hp center % sign")
    RegisterHidePercent("healthTextRightHidePercentSymbol", "hpTextRightHidePercentSymbol", "Right HP Hide % Sign", "hp right hide percent sign", "right hp hide percent sign", "health right hide percent sign", "right health hide percent sign", "hide hp right percent sign", "hide health right percent sign", "hide right hp percent sign")
    RegisterPercentSign("healthTextRightPercentSymbol", "hpTextRightHidePercentSymbol", "Right HP % Sign", "hp right percent sign", "health right percent sign", "right hp percent sign", "hp right % sign", "right hp % sign")

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text delimiter")
    AddAliasesForUnit(aliases, scope, "health text delimiter")
    AddAliasesForUnit(aliases, scope, "health delimiter")
    RegisterGroupDelimiter(scope, "healthTextDelimiter", "textDelimiter", "HP Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "reverse hp text")
    AddAliasesForUnit(aliases, scope, "reverse health text")
    AddAliasesForUnit(aliases, scope, "hp text reverse order")
    RegisterGroupBoolean(scope, "healthTextReverse", "hpTextReverse", "Reverse HP Text", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "health text decimals")
    AddAliasesForUnit(aliases, scope, "hp text decimals")
    AddAliasesForUnit(aliases, scope, "decimal percent")
    RegisterGroupBoolean(scope, "healthTextDecimals", "healthTextDecimals", "Health Text Decimals", false, "visual", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "abbreviate hp values")
    AddAliasesForUnit(aliases, scope, "abbreviate health values")
    AddAliasesForUnit(aliases, scope, "shorten hp values")
    AddAliasesForUnit(aliases, scope, "short hp numbers")
    AddAliasesForUnit(aliases, scope, "abbreviated hp numbers")
    AddAliasesForUnit(aliases, scope, "hp value abbreviation")
    RegisterGroupBoolean(scope, "hpFullValueShort", "hpFullValueShort", "Abbreviate HP Values", true, "font", aliases, {
        description = "Abbreviates numeric HP values with K/M. None and Percent-only HP slots are unaffected.",
    })

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text x")
    AddAliasesForUnit(aliases, scope, "hp text x offset")
    AddAliasesForUnit(aliases, scope, "health text x offset")
    RegisterGroupNumber(scope, "healthTextOffsetX", "hpOffsetX", "HP Text X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text y")
    AddAliasesForUnit(aliases, scope, "hp text y offset")
    AddAliasesForUnit(aliases, scope, "health text y offset")
    RegisterGroupNumber(scope, "healthTextOffsetY", "hpOffsetY", "HP Text Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "hp text layer")
    AddAliasesForUnit(aliases, scope, "health text layer")
    RegisterGroupNumber(scope, "healthTextLayer", "textLayer", "HP Text Layer", 5, 0, 30, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power left text")
    AddAliasesForUnit(aliases, scope, "left power text")
    RegisterGroupTextMode(scope, "powerTextLeft", "powerTextLeft", "Left Power Text", "NONE", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power center text")
    AddAliasesForUnit(aliases, scope, "power middle text")
    AddAliasesForUnit(aliases, scope, "center power text")
    RegisterGroupTextMode(scope, "powerTextCenter", "powerTextCenter", "Center Power Text", "PERCENT", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power right text")
    AddAliasesForUnit(aliases, scope, "right power text")
    RegisterGroupTextMode(scope, "powerTextRight", "powerTextRight", "Right Power Text", "NONE", aliases)

    RegisterHidePercent("powerTextLeftHidePercentSymbol", "powerTextLeftHidePercentSymbol", "Left Power Hide % Sign", "power left hide percent sign", "left power hide percent sign", "hide power left percent sign", "hide left power percent sign")
    RegisterPercentSign("powerTextLeftPercentSymbol", "powerTextLeftHidePercentSymbol", "Left Power % Sign", "power left percent sign", "left power percent sign", "power left % sign", "left power % sign")
    RegisterHidePercent("powerTextCenterHidePercentSymbol", "powerTextCenterHidePercentSymbol", "Center Power Hide % Sign", "power center hide percent sign", "center power hide percent sign", "power middle hide percent sign", "hide power center percent sign", "hide center power percent sign", "hide power middle percent sign")
    RegisterPercentSign("powerTextCenterPercentSymbol", "powerTextCenterHidePercentSymbol", "Center Power % Sign", "power center percent sign", "center power percent sign", "power middle percent sign", "middle power percent sign", "power center % sign")
    RegisterHidePercent("powerTextRightHidePercentSymbol", "powerTextRightHidePercentSymbol", "Right Power Hide % Sign", "power right hide percent sign", "right power hide percent sign", "hide power right percent sign", "hide right power percent sign")
    RegisterPercentSign("powerTextRightPercentSymbol", "powerTextRightHidePercentSymbol", "Right Power % Sign", "power right percent sign", "right power percent sign", "power right % sign", "right power % sign")

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text delimiter")
    AddAliasesForUnit(aliases, scope, "power delimiter")
    RegisterGroupDelimiter(scope, "powerTextDelimiter", "powerTextDelimiter", "Power Text Delimiter", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text x")
    AddAliasesForUnit(aliases, scope, "power text x offset")
    RegisterGroupNumber(scope, "powerTextOffsetX", "powerOffsetX", "Power Text X Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text y")
    AddAliasesForUnit(aliases, scope, "power text y offset")
    RegisterGroupNumber(scope, "powerTextOffsetY", "powerOffsetY", "Power Text Y Offset", 0, -100, 100, 1, "font", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power text layer")
    RegisterGroupNumber(scope, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2, 0, 30, 1, "font", aliases)

    for _, slotInfo in ipairs({
        { label = "HP Left Text", prefix = "hpTextLeft", words = { "hp left slot", "health left slot", "left hp slot" } },
        { label = "HP Center Text", prefix = "hpTextCenter", words = { "hp center slot", "health center slot", "center hp slot" } },
        { label = "HP Right Text", prefix = "hpTextRight", words = { "hp right slot", "health right slot", "right hp slot" } },
        { label = "Power Left Text", prefix = "powerTextLeft", words = { "power left slot", "left power slot" } },
        { label = "Power Center Text", prefix = "powerTextCenter", words = { "power center slot", "center power slot" } },
        { label = "Power Right Text", prefix = "powerTextRight", words = { "power right slot", "right power slot" } },
    }) do
        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " x offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetX", slotInfo.prefix .. "OffsetX", slotInfo.label .. " Slot X Offset", 0, -100, 100, 1, "font", aliases)

        aliases = {}
        for i = 1, #slotInfo.words do
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y")
            AddAliasesForUnit(aliases, scope, slotInfo.words[i] .. " y offset")
        end
        RegisterGroupNumber(scope, slotInfo.prefix .. "OffsetY", slotInfo.prefix .. "OffsetY", slotInfo.label .. " Slot Y Offset", 0, -100, 100, 1, "font", aliases)
    end
end
