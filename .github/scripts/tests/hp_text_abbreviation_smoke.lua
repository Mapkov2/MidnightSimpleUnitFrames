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
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

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

-- Group frames compile the scope setting into the same shared health slots.
_G.MSUF_DB = {
    general = {},
    gf_party = {
        showHPText = true,
        textLeft = "NONE",
        textCenter = "MAX",
        textRight = "NONE",
        hpFullValueShort = false,
    },
}
local groupAddon = { UF = {} }
local groupDBChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))
groupDBChunk("MidnightSimpleUnitFrames", groupAddon)
local groupMetadataChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))
groupMetadataChunk("MidnightSimpleUnitFrames", groupAddon)
local groupConfigChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))
groupConfigChunk("MidnightSimpleUnitFrames", groupAddon)

Check(groupAddon.GF.PARTY_DEFAULTS.hpFullValueShort == true, "group abbreviation default must stay enabled")
local groupSpec = groupAddon.GF.CompileSpec("party", nil, "party1")
Check(groupSpec.text.healthShortNumbers == false, "group full-value setting did not compile")
local groupFontString = NewFontString()
local groupFrame = {
    unit = "party1",
    hpTextCenter = groupFontString,
    _msufTextHealthMax = 1000000,
    _msufTextHealthMaxUnit = "party1",
}
local groupRuntime = Text.CompileTextRuntime(groupFrame, groupSpec, groupSpec.text)
Check(groupRuntime.healthSlots[1].short == false, "group full-value slot did not compile")
groupRuntime._lastHealthTextMax = 1000000

_G.MSUF_DB.gf_party.hpFullValueShort = true
Check(groupAddon.GF.RefreshCompiledSpecDomains("party", groupAddon.GF.DIRTY_FONT) == true,
    "group font-domain refresh did not recompile text")
groupSpec = groupAddon.GF.CompileSpec("party", nil, "party1")
Check(groupSpec.text.healthShortNumbers == true, "group abbreviated setting did not recompile")
groupRuntime = Text.CompileTextRuntime(groupFrame, groupSpec, groupSpec.text)
Check(groupRuntime.healthSlots[1].short == true, "group abbreviated slot did not recompile")
Check(groupRuntime._lastHealthTextMax == nil and groupFrame._msufTextHealthMax == nil,
    "group static max caches were not cleared")

for _, shortNumbers in ipairs({ false, true }) do
    for _, mode in ipairs(modes) do
        local formatted = groupAddon.GF.FormatHealthText(
            mode, 717080, 1000000, " / ", false, nil, false, shortNumbers)
        local marker = shortNumbers and "SHORT:" or "FULL:"
        Check(formatted and formatted:find(marker, 1, true),
            "group preview " .. mode .. ": wrong formatter: " .. tostring(formatted))
    end
end

print("HP text abbreviation smoke passed (28 mode/toggle cases + group config recompile)")
