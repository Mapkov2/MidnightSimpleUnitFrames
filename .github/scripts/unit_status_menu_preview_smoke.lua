local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local source = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua")

local sectionHeight = tonumber(source:match("local STATUS_SECTION_HEIGHT = (%d+)"))
local placementHeight = tonumber(source:match("local STATUS_PLACEMENT_CARD_HEIGHT = (%d+)"))
assert(sectionHeight and placementHeight, "status menu height contracts are missing")

-- The tab begins 64px below the section body. Placement starts after the
-- 38px card inset, 214px top row, and 12px gap. Keep a 12px bottom gutter.
local requiredSectionHeight = 64 + 38 + 214 + 12 + placementHeight + 12
assert(sectionHeight >= requiredSectionHeight,
    ("status section clips its Placement card: need %d, got %d"):format(requiredSectionHeight, sectionHeight))

-- The final slider title starts at -178; its 24px title gap and 24px control
-- require 226px, plus a real bottom gutter instead of touching the card edge.
assert(placementHeight >= 242,
    ("status Placement card clips the Layer slider: need 242, got %d"):format(placementHeight))

local symbolBinding = source:match('local symbol = BindStatusSpecDropdown%b()%s*local iconPack')
assert(symbolBinding, "status Symbol dropdown binding was not found")
assert(symbolBinding:find("RefreshStatusSectionState", 1, true),
    "status Symbol changes no longer refresh the icon preview strip")

print("unit status menu preview smoke: OK")
