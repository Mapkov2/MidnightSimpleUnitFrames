local path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
source = source:gsub("\r\n", "\n")

assert(source:find('CollapsibleSection("status_icons", "Status icons", 618, false)', 1, true),
    "status section height does not match the compact basic-tab layout")
assert(source:find("local topCardY, topCardH, cardRowGap = -38, 214, 12", 1, true),
    "status top-card geometry is not defined on the shared spacing grid")
assert(source:find('leftX - 2, topCardY, leftW + 16, topCardH)', 1, true)
    and source:find('rightX - 2, topCardY, rightW + 16, topCardH)', 1, true),
    "selected-indicator and preview cards are not vertically symmetric")
assert(source:find("local placementCardY = topCardY - topCardH - cardRowGap", 1, true),
    "placement card is not derived from the symmetric top-card row")
assert(source:find('T.ApplyButtonRole(control, enabled and "success" or "danger")', 1, true),
    "current-status preview button does not expose the selected indicator state")
assert(source:find("SetPreviewCurrentVisual(current, isEnabled)", 1, true)
    and source:find("SetPreviewCurrentVisual(advanced.current, isEnabled)", 1, true),
    "basic and advanced current-status preview buttons do not share the same state visual")
assert(source:find('RefreshStatusRuntime(unit, spec)\n            if RefreshStatusSectionState then RefreshStatusSectionState() end', 1, true),
    "status enable toggle still rebuilds the full page instead of refreshing in place")

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

local unitPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"
local unitFile = assert(io.open(unitPath, "rb"))
local unitSource = unitFile:read("*a")
unitFile:close()
for _, statusRow in ipairs({
    'StatusControl("statusText", "Dead / Offline Text"',
    'StatusControl("statusGhostText", "Ghost Text"',
    'StatusControl("statusAFKText", "AFK Text"',
    'StatusControl("statusDNDText", "DND Text"',
}) do
    assert(unitSource:find(statusRow, 1, true),
        "split unit status text is missing from the indicator selector: " .. statusRow)
end
assert(unitSource:find('StatusControl("level", "Level Text"', 1, true),
    "level text is not exposed in Status Icons")
assert(unitSource:find('StatusControl("raceText", "Race Text"', 1, true),
    "race text is not exposed in Status Icons")
assert(unitSource:find('StatusControl("classText", "Class Text"', 1, true),
    "class text is not exposed in Status Icons")
assert(not unitSource:find('StatusControl("unitInfoText"', 1, true),
    "combined identity text still exists instead of three separate Status Icon controls")

local previewPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua"
local previewFile = assert(io.open(previewPath, "rb"))
local previewSource = previewFile:read("*a")
previewFile:close()
for _, previewId in ipairs({ "level", "raceText", "classText", "statusText", "statusGhostText", "statusAFKText", "statusDNDText" }) do
    assert(previewSource:find("\n" .. previewId .. "|", 1, true),
        previewId .. " does not have an independent status preview spec")
end
assert(not previewSource:find("\nunitInfoText|", 1, true),
    "combined identity preview still exists instead of three separate previews")

local viewPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"
local viewFile = assert(io.open(viewPath, "rb"))
local viewSource = viewFile:read("*a")
viewFile:close()
assert(viewSource:find('fn(key, moveReason)', 1, true),
    "status preview movement does not refresh the affected unit")

local renderPath = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"
local renderFile = assert(io.open(renderPath, "rb"))
local renderSource = renderFile:read("*a")
renderFile:close()
assert(renderSource:find("tonumber(conf[spec.x]) or tonumber(statusCfg and statusCfg.x)", 1, true)
    and renderSource:find("tonumber(conf[spec.y]) or tonumber(statusCfg and statusCfg.y)", 1, true),
    "status preview drag offsets do not override the stale compiled preview snapshot")

io.write("unit_status_indicator_layout_smoke: ok\n")
