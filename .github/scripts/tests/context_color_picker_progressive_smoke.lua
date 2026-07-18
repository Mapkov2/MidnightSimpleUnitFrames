local path = "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_ContextColorPicker.lua"
local handle = assert(io.open(path, "rb"))
local source = handle:read("*a")
handle:close()

local function Has(needle, message)
    assert(source:find(needle, 1, true), message)
end

Has("local SIMPLE_WIDTH, SIMPLE_HEIGHT = 420, 424", "compact picker dimensions missing")
Has("local ADVANCED_WIDTH, ADVANCED_HEIGHT = 680, 548", "advanced picker dimensions missing")
Has("self.advancedCard:SetShown(advanced)", "advanced tools are not gated as one progressive section")
Has('self.more:SetText(Tr(advanced and "Back to controls" or "Advanced"))',
    "advanced disclosure button does not communicate both states")
Has("self.advanced = false", "picker must always open in the simple state")

Has('Font(advancedCard, "GameFontNormalSmall", "Quick colors"', "quick colors must live in Advanced")
Has('Input(advancedCard, 58, true)', "RGB precision fields must live in Advanced")
Has('Input(advancedCard, 112, false)', "HEX precision field must live in Advanced")
Has('Swatch(advancedCard, 23', "recent and saved palettes must live in Advanced")
Has('Font(wheelCard, "GameFontNormalSmall", "Class colors"', "class colors must stay grouped with color tools")

local openStart = assert(source:find("function panel:Open", 1, true))
local openEnd = assert(source:find("panel:SetScript(\"OnKeyDown\"", openStart, true))
local openSource = source:sub(openStart, openEnd - 1)
assert(openSource:find("self.advanced = false", 1, true), "Open must reset Advanced before layout")

print("context color picker progressive disclosure smoke: ok")
