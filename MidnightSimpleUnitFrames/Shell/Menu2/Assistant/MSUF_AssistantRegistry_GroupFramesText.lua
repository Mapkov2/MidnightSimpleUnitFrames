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
    RegisterGroupNumber(scope, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5, 1, 15, 1, "font", aliases)

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
    RegisterGroupNumber(scope, "healthTextLayer", "textLayer", "HP Text Layer", 5, 1, 15, 1, "font", aliases)

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
    RegisterGroupNumber(scope, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2, 1, 15, 1, "font", aliases)

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
