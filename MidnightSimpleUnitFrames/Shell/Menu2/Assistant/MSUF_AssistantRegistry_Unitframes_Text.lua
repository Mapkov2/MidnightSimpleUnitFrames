-- Assistant UnitFrame text registry.
-- Keeps per-unit name, health, and power text metadata outside the main
-- UnitFrame registry loop while preserving the same cold registration behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local function AppendAliases(aliases, ...)
    if type(aliases) ~= "table" then return aliases end
    for i = 1, select("#", ...) do
        local alias = select(i, ...)
        if type(alias) == "string" and alias ~= "" then
            aliases[#aliases + 1] = alias
        end
    end
    return aliases
end

function A.UnitframesRegistry.RegisterTextSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitTextNumber = ctx.RegisterUnitTextNumber
    local TextValue = ctx.TextValue

    if type(MakeAliases) ~= "function" or type(RegisterUnitBooleanSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitTextNumber) ~= "function" then return end
    if type(TextValue) ~= "function" then return end

    local TEXT_ANCHOR_VALUES = ctx.TEXT_ANCHOR_VALUES or {}
    local HP_MODE_VALUES = ctx.HP_MODE_VALUES or {}
    local HP_MODE_ALIASES = ctx.HP_MODE_ALIASES
    local POWER_MODE_VALUES = ctx.POWER_MODE_VALUES or {}
    local POWER_MODE_ALIASES = ctx.POWER_MODE_ALIASES
    local SEPARATOR_VALUES = ctx.SEPARATOR_VALUES or {}
    local SEPARATOR_ALIASES = ctx.SEPARATOR_ALIASES

    RegisterUnitEnum(unit, "nameTextAnchor", "nameTextAnchor", "Name Text Anchor", "LEFT", TEXT_ANCHOR_VALUES, MakeAliases(unit, "name anchor", "name text anchor"), {
        category = "Text",
        text = true,
        valueAliases = { left = "LEFT", center = "CENTER", middle = "CENTER", right = "RIGHT" },
        get = function(unitKey) return TextValue(unitKey, "nameTextAnchor", "LEFT") end,
    })
    RegisterUnitTextNumber(unit, "nameOffsetX", "nameOffsetX", "Name X Offset", 4,
        MakeAliases(unit, "name x", "name x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameOffsetY", "nameOffsetY", "Name Y Offset", -4,
        MakeAliases(unit, "name y", "name y offset"), { min = -300, max = 300 })
    local nameFontAliases = MakeAliases(unit, "name size", "name font size")
    AppendAliases(nameFontAliases, "unit name text size", "unit frame name text size", "unit name font size")
    RegisterUnitTextNumber(unit, "nameFontSize", "nameFontSize", "Name Font Size", 14,
        nameFontAliases, { min = 6, max = 48, fonts = true, generalKey = "nameFontSize" })

    local hpLeftAliases = MakeAliases(unit, "hp left slot", "health left slot", "left hp text")
    AppendAliases(hpLeftAliases, "unit text slot", "unit text left slot", "unit hp left slot", "unit health left slot", "unit health text left slot")
    RegisterUnitEnum(unit, "hpTextLeft", "textLeft", "HP Left Slot", "NONE", HP_MODE_VALUES,
        hpLeftAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textLeft", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    local hpCenterAliases = MakeAliases(unit, "hp center slot", "health center slot", "center hp text")
    AppendAliases(hpCenterAliases, "unit text slot", "unit text center slot", "unit text middle slot", "unit hp center slot", "unit health center slot", "unit health text center slot")
    RegisterUnitEnum(unit, "hpTextCenter", "textCenter", "HP Center Slot", "NONE", HP_MODE_VALUES,
        hpCenterAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textCenter", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    local hpRightAliases = MakeAliases(unit, "hp right slot", "health right slot", "right hp text")
    AppendAliases(hpRightAliases, "unit text slot", "unit text right slot", "unit hp right slot", "unit health right slot", "unit health text right slot")
    RegisterUnitEnum(unit, "hpTextRight", "textRight", "HP Right Slot", "CURPERCENT", HP_MODE_VALUES,
        hpRightAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textRight", TextValue(unitKey, "hpTextMode", "CURPERCENT")) end,
        })
    RegisterUnitEnum(unit, "hpTextSeparator", "hpTextSeparator", "HP Text Delimiter", "", SEPARATOR_VALUES,
        MakeAliases(unit, "hp text delimiter", "hp text separator", "health text delimiter"),
        { category = "Text", text = true, valueAliases = SEPARATOR_ALIASES, get = function(unitKey) return TextValue(unitKey, "hpTextSeparator", "") end })
    RegisterUnitBooleanSetting(unit, "hpTextReverse", "hpTextReverse", "Reverse HP Text Order", false,
        MakeAliases(unit, "reverse hp text", "hp text reverse order"), { category = "Text", text = true })
    RegisterUnitBooleanSetting(unit, "healthTextDecimals", "healthTextDecimals", "Health Text Decimals", false,
        MakeAliases(unit, "health text decimals", "hp text decimals", "decimal percent"), { category = "Text", text = true })
    RegisterUnitTextNumber(unit, "hpOffsetX", "hpOffsetX", "HP Text X Offset", -4,
        MakeAliases(unit, "hp text x", "health text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpOffsetY", "hpOffsetY", "HP Text Y Offset", -4,
        MakeAliases(unit, "hp text y", "health text y offset"), { min = -300, max = 300 })
    local hpFontAliases = MakeAliases(unit, "hp text size", "hp font size", "health text size")
    AppendAliases(hpFontAliases, "unit text size", "unit frame text size", "unit hp text size", "unit health text size", "unit health font size")
    RegisterUnitTextNumber(unit, "hpFontSize", "hpFontSize", "HP Font Size", 14,
        hpFontAliases, { min = 6, max = 48, fonts = true, generalKey = "hpFontSize" })

    local powerLeftAliases = MakeAliases(unit, "power left slot", "mana left slot", "left power text")
    AppendAliases(powerLeftAliases, "unit text slot", "unit text left slot", "unit power left slot", "unit mana left slot", "unit power text left slot")
    RegisterUnitEnum(unit, "powerTextLeft", "powerTextLeft", "Power Left Slot", "NONE", POWER_MODE_VALUES,
        powerLeftAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextLeft", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    local powerCenterAliases = MakeAliases(unit, "power center slot", "mana center slot", "center power text")
    AppendAliases(powerCenterAliases, "unit text slot", "unit text center slot", "unit text middle slot", "unit power center slot", "unit mana center slot", "unit power text center slot")
    RegisterUnitEnum(unit, "powerTextCenter", "powerTextCenter", "Power Center Slot", "NONE", POWER_MODE_VALUES,
        powerCenterAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextCenter", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    local powerRightAliases = MakeAliases(unit, "power right slot", "mana right slot", "right power text")
    AppendAliases(powerRightAliases, "unit text slot", "unit text right slot", "unit power right slot", "unit mana right slot", "unit power text right slot")
    RegisterUnitEnum(unit, "powerTextRight", "powerTextRight", "Power Right Slot", "CURPERCENT", POWER_MODE_VALUES,
        powerRightAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextRight", TextValue(unitKey, "powerTextMode", "CURPERCENT")) end,
        })
    RegisterUnitEnum(unit, "powerTextSeparator", "powerTextSeparator", "Power Text Delimiter", "", SEPARATOR_VALUES,
        MakeAliases(unit, "power text delimiter", "power text separator", "mana text delimiter"),
        {
            category = "Text",
            text = true,
            valueAliases = SEPARATOR_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextSeparator", TextValue(unitKey, "hpTextSeparator", "")) end,
        })
    RegisterUnitTextNumber(unit, "powerOffsetX", "powerOffsetX", "Power Text X Offset", -4,
        MakeAliases(unit, "power text x", "mana text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "powerOffsetY", "powerOffsetY", "Power Text Y Offset", 4,
        MakeAliases(unit, "power text y", "mana text y offset"), { min = -300, max = 300 })
    local powerFontAliases = MakeAliases(unit, "power text size", "power font size", "mana text size")
    AppendAliases(powerFontAliases, "unit text size", "unit frame text size", "unit power text size", "unit mana text size", "unit power font size")
    RegisterUnitTextNumber(unit, "powerFontSize", "powerFontSize", "Power Font Size", 14,
        powerFontAliases, { min = 6, max = 48, fonts = true, generalKey = "powerFontSize" })

    local hpSlots = {
        { suffix = "Left", label = "HP Left Slot", keyPrefix = "hpTextLeft", alias = "hp left slot" },
        { suffix = "Center", label = "HP Center Slot", keyPrefix = "hpTextCenter", alias = "hp center slot" },
        { suffix = "Right", label = "HP Right Slot", keyPrefix = "hpTextRight", alias = "hp right slot" },
    }
    for s = 1, #hpSlots do
        local slot = hpSlots[s]
        local slotLower = tostring(slot.suffix or ""):lower()
        if slotLower == "center" then slotLower = "center" end
        local slotXAliases = MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset")
        AppendAliases(slotXAliases,
            "unit text slot x", "unit text slot x offset",
            "unit text " .. slotLower .. " slot x", "unit text " .. slotLower .. " slot x offset",
            "unit hp " .. slotLower .. " slot x", "unit hp " .. slotLower .. " slot x offset",
            "unit health " .. slotLower .. " slot x", "unit health " .. slotLower .. " slot x offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            slotXAliases, { min = -300, max = 300 })
        local slotYAliases = MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset")
        AppendAliases(slotYAliases,
            "unit text slot y", "unit text slot y offset",
            "unit text " .. slotLower .. " slot y", "unit text " .. slotLower .. " slot y offset",
            "unit hp " .. slotLower .. " slot y", "unit hp " .. slotLower .. " slot y offset",
            "unit health " .. slotLower .. " slot y", "unit health " .. slotLower .. " slot y offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            slotYAliases, { min = -300, max = 300 })
    end
    local powerSlots = {
        { label = "Power Left Slot", keyPrefix = "powerTextLeft", alias = "power left slot" },
        { label = "Power Center Slot", keyPrefix = "powerTextCenter", alias = "power center slot" },
        { label = "Power Right Slot", keyPrefix = "powerTextRight", alias = "power right slot" },
    }
    for s = 1, #powerSlots do
        local slot = powerSlots[s]
        local slotLower = tostring(slot.label or ""):match("Power%s+(%S+)%s+Slot")
        slotLower = tostring(slotLower or ""):lower()
        local slotXAliases = MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset")
        AppendAliases(slotXAliases,
            "unit text slot x", "unit text slot x offset",
            "unit text " .. slotLower .. " slot x", "unit text " .. slotLower .. " slot x offset",
            "unit power " .. slotLower .. " slot x", "unit power " .. slotLower .. " slot x offset",
            "unit mana " .. slotLower .. " slot x", "unit mana " .. slotLower .. " slot x offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            slotXAliases, { min = -300, max = 300 })
        local slotYAliases = MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset")
        AppendAliases(slotYAliases,
            "unit text slot y", "unit text slot y offset",
            "unit text " .. slotLower .. " slot y", "unit text " .. slotLower .. " slot y offset",
            "unit power " .. slotLower .. " slot y", "unit power " .. slotLower .. " slot y offset",
            "unit mana " .. slotLower .. " slot y", "unit mana " .. slotLower .. " slot y offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            slotYAliases, { min = -300, max = 300 })
    end

    RegisterUnitTextNumber(unit, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5,
        MakeAliases(unit, "name text layer", "name layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "hpTextLayer", "hpTextLayer", "HP Text Layer", 5,
        MakeAliases(unit, "hp text layer", "health text layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2,
        MakeAliases(unit, "power text layer", "mana text layer"), { min = 0, max = 30, fonts = true })
end
