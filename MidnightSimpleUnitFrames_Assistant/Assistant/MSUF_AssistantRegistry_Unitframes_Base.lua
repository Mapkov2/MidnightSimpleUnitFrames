-- Assistant UnitFrame registry base settings.
-- Registers the simple per-unit frame controls before the extended UnitFrame domain.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local AddAliasesForUnit = C.AddAliasesForUnit
local RegisterUnitBoolean = C.RegisterUnitBoolean
local RegisterUnitNumber = C.RegisterUnitNumber
local UnitDefaultPower = C.UnitDefaultPower
if type(AddAliasesForUnit) ~= "function" or type(RegisterUnitBoolean) ~= "function" or type(RegisterUnitNumber) ~= "function" or type(UnitDefaultPower) ~= "function" then return end

local UNIT_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local RANGE_FADE_UNITS = { target = true, targettarget = true, focus = true, focustarget = true, pet = true, boss = true }

for i = 1, #UNIT_KEYS do
    local unit = UNIT_KEYS[i]
    local aliases

    aliases = {}
    AddAliasesForUnit(aliases, unit, "frame", "frame")
    RegisterUnitBoolean(unit, "enabled", "enabled", "Frame Enabled", true, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_FRAME_ENABLED" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "name", "name")
    AddAliasesForUnit(aliases, unit, "name text", "namen")
    RegisterUnitBoolean(unit, "name", "showName", "Name", true, aliases, { category = "Text", reason = "MSUF_ASSISTANT_NAME", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "hp text", "hp text")
    AddAliasesForUnit(aliases, unit, "health text", "leben text")
    RegisterUnitBoolean(unit, "hpText", "showHP", "HP Text", true, aliases, { category = "Text", reason = "MSUF_ASSISTANT_HP_TEXT", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "power text", "power text")
    AddAliasesForUnit(aliases, unit, "mana text", "mana text")
    RegisterUnitBoolean(unit, "powerText", "showPowerText", "Power Text", UnitDefaultPower(unit), aliases, { category = "Text", reason = "MSUF_ASSISTANT_POWER_TEXT", text = true })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "width", "breite")
    AddAliasesForUnit(aliases, unit, "frame width", "frame breite")
    RegisterUnitNumber(unit, "width", "width", "Width",
        unit == "boss" and 180 or (unit == "focus" and 180 or 275),
        40, 900, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_WIDTH" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "height", "hoehe")
    AddAliasesForUnit(aliases, unit, "frame height", "frame hoehe")
    RegisterUnitNumber(unit, "height", "height", "Height",
        unit == "boss" and 30 or (unit == "focus" and 30 or 40),
        10, 180, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_HEIGHT" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "x position", "x position")
    AddAliasesForUnit(aliases, unit, "x offset", "x versatz")
    RegisterUnitNumber(unit, "offsetX", "offsetX", "X Position", 0, -4096, 4096, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_X" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "y position", "y position")
    AddAliasesForUnit(aliases, unit, "y offset", "y versatz")
    RegisterUnitNumber(unit, "offsetY", "offsetY", "Y Position", 0, -4096, 4096, aliases, { category = "Frame", reason = "MSUF_ASSISTANT_Y" })

    aliases = {}
    AddAliasesForUnit(aliases, unit, "raid marker", "raid marker")
    AddAliasesForUnit(aliases, unit, "raid marker icon", "schlachtzug marker")
    AddAliasesForUnit(aliases, unit, "raid indicator", "raid symbol")
    RegisterUnitBoolean(unit, "raidMarker", "showRaidMarker", "Raid Marker", true, aliases, {
        category = "Status",
        reason = "MSUF_ASSISTANT_RAID_MARKER",
        text = true,
        refresh = "MSUF_RefreshRaidMarkerFrames",
    })

    if RANGE_FADE_UNITS[unit] then
        aliases = {}
        AddAliasesForUnit(aliases, unit, "range fade", "range fade")
        AddAliasesForUnit(aliases, unit, "range fading", "reichweite fade")
        RegisterUnitBoolean(unit, "rangeFade", "rangeFadeEnabled", "Range Fade", true, aliases, { category = "Range", reason = "MSUF_ASSISTANT_RANGE_FADE", alpha = true })
    end
end
