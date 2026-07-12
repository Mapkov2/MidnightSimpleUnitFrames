-- Standalone regression for the per-unit HP abbreviation toggle.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function NewFontString()
    return {
        shown = true,
        IsShown = function(self) return self.shown end,
        SetText = function(self, value) self.text = value end,
        SetFormattedText = function(self, pattern, ...) self.text = string.format(pattern, ...) end,
    }
end

_G.AbbreviateNumbers = function(value) return "SHORT:" .. tostring(value) end
_G.AbbreviateLargeNumbers = _G.AbbreviateNumbers
_G.BreakUpLargeNumbers = function(value) return "FULL:" .. tostring(value) end

local Text = {
    UnitPowerType = function() return 0 end,
    AbbreviateNumbers = _G.AbbreviateNumbers,
    AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers,
    BreakUpLargeNumbers = _G.BreakUpLargeNumbers,
    tonumber = tonumber,
    type = type,
    format = string.format,
    floor = math.floor,
    max = math.max,
    REVERSE_HEALTH_MODE = {},
}
local addon = { UFText = Text, Apply = {} }
local source = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua"
assert(loadfile(source))("MidnightSimpleUnitFrames", addon)

local modes = {
    "CURRENT", "MAX", "DEFICIT", "CURMAX", "CURPERCENT", "CURMAXPERCENT", "FULLVALUE",
}
for _, shortNumbers in ipairs({ false, true }) do
    for _, mode in ipairs(modes) do
        local fontString = NewFontString()
        local frame = { unit = "player", hpTextRight = fontString }
        local spec = {
            key = "player",
            showName = false,
            showHealthText = true,
            showPowerText = false,
        }
        local text = {
            healthLeft = "NONE",
            healthCenter = "NONE",
            healthRight = mode,
            healthDelimiter = " / ",
            healthShortNumbers = shortNumbers,
            powerLeft = "NONE",
            powerCenter = "NONE",
            powerRight = "NONE",
        }
        local runtime = Text.CompileTextRuntime(frame, spec, text)
        local slot = runtime.healthSlots[1]
        Check(runtime.healthSlotCount == 1, mode .. ": missing health slot")
        Check(slot.short == shortNumbers, mode .. ": toggle did not reach compiled slot")
        slot.plainWriter(slot, 717080, 1000000, 72, true, { healthMissing = 282920 })
        local marker = shortNumbers and "SHORT:" or "FULL:"
        Check(fontString.text and fontString.text:find(marker, 1, true),
            mode .. ": wrong formatter: " .. tostring(fontString.text))
    end
end

print("HP text abbreviation smoke passed (14 mode/toggle cases)")
