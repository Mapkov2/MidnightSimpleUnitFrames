local path = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local layout = assert(source:match(
    "local function LayoutStatusControls%b()%s*(.-)%s*local function ShowControl"
), "status indicator layout helper missing")

assert(layout:find("Shared.PlaceSlider(placementCard, size, placeLeftX, -54, placeLeftW)", 1, true),
    "status indicator size is not in the first left row")
assert(layout:find("Shared.PlaceSlider(placementCard, x, placeRightX, -54, placeRightW)", 1, true),
    "status indicator X offset is not in the first right row")
assert(layout:find("Shared.PlaceDropdown(placementCard, anchor, placeLeftX, -116, placeLeftW)", 1, true)
    and layout:find("Shared.PlaceSlider(placementCard, y, placeRightX, -116, placeRightW)", 1, true),
    "status indicator anchor/Y controls do not share the second row")
assert(layout:find("Shared.PlaceSlider(placementCard, layer, placeLeftX, -178, placeLeftW)", 1, true)
    and layout:find("PlaceButton(reset, placementCard, placeRightX, -178, 150)", 1, true),
    "status indicator layer/reset controls do not share the third row")
assert(not layout:find("placeLeftX, -212", 1, true),
    "status indicator layer still uses the clipped fourth-row position")

io.write("unit_status_indicator_layout_smoke: ok\n")
