local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitTextureLayer.lua")
local sectionHeight = tonumber(source:match("local TEXLAYER_SECTION_H = (%d+)"))
local cardY = tonumber(source:match("local TEXLAYER_CARD_Y = (%-%d+)"))
local cardHeight = tonumber(source:match("local TEXLAYER_CARD_H = (%d+)"))
local sourceColorY = tonumber(source:match(
    'BindLayerDropdown%(setupCard, "Source color", 16, (%-%d+),'
))

assert(sectionHeight and cardY and cardHeight and sourceColorY,
    "Texture Layer menu geometry was not found")

-- Dropdown controls sit 24px below their labels and are 22px tall. Preserve
-- another 16px for the soft edge and visual footer.
local requiredCardHeight = math.abs(sourceColorY) + 24 + 22 + 16
assert(cardHeight >= requiredCardHeight,
    ("Texture Layer Setup card clips Source color: need %d, got %d"):format(requiredCardHeight, cardHeight))

-- Keep the card itself away from the following Anchoring accordion.
local requiredSectionHeight = math.abs(cardY) + cardHeight + 32
assert(sectionHeight >= requiredSectionHeight,
    ("Texture Layer section clips its card: need %d, got %d"):format(requiredSectionHeight, sectionHeight))

print("texture layer menu clipping smoke: OK")
