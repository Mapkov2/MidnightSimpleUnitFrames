-- The compact preview hides its layer rail behind a "Layers" button, so the rail
-- becomes a dropdown with a painted panel behind it. Chips must stay inside that
-- panel, and the panel must stay inside the preview. The trap: the render pass
-- re-flows the rail from the preview box width on every layer-availability
-- change -- entering combat view is one -- and the box is far wider and shorter
-- than the dropdown, so the flow has to be driven by the popover itself.
-- Geometry model only; real font metrics and texture bounds remain client checks.
local root = arg[1] or "."

local function Read(path)
    local file = assert(io.open(path, "rb"), "missing " .. path)
    local source = file:read("*a")
    file:close()
    return (source:gsub("\r\n", "\n"))
end

local HELPERS = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"
local UNIT = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua"
-- The unit compact/docked presentation switch lives in the View_Chrome sibling.
local UNIT_CHROME = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View_Chrome.lua"
local GROUP = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua"

-- Run the real helpers, not a copy of their arithmetic.
local helpers = Read(HELPERS)
local function Extract(marker)
    local first = assert(helpers:find(marker, 1, true), marker .. " missing")
    local last = assert(helpers:find("\nend\n", first, true), marker .. " unterminated")
    return helpers:sub(first, last + 4)
end
local H = {}
assert(loadstring("local H, min = ...\n" .. Extract("function H.FlowLayerChips")
    .. Extract("function H.FlowLayerPopover"), "flow"))(H, math.min)

local LABELS = {
    "Guides", "Name", "HP Text", "Pwr Text", "Portrait", "Texture", "Power", "Class",
    "Cast", "Buffs", "Debuffs", "Custom", "Dispel Overlay", "Dispel Symbol", "Status", "Bounds",
}
-- The unit page books a 180px preview section; the dropdown hangs below the
-- header inside it, and the docked box is 632 wide.
local POPOVER, BOX_W, BOX_H = 268, 632, 180
local BUDGET, CAP = BOX_H - 44, BOX_W - 24

local function Rail()
    local rail = { width = POPOVER, height = 0 }
    function rail:GetWidth() return self.width end
    function rail:SetWidth(value) self.width = value end
    function rail:SetHeight(value) self.height = value end
    return rail
end

local function Chips()
    local chips = {}
    for i = 1, #LABELS do
        -- CreateLayerButton sizes a chip as its text width plus 30.
        local chip = { label = LABELS[i], w = #LABELS[i] * 6.2 + 30 }
        function chip:GetWidth() return self.w end
        function chip:IsShown() return true end
        function chip:ClearAllPoints() self.x, self.y = nil, nil end
        function chip:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
        chips[i] = chip
    end
    return chips
end

local function Measure(rail, chips)
    local widest, rows = 0, 1
    for i = 1, #chips do
        local right = chips[i].x + chips[i].w
        assert(right <= rail.width,
            "chip left the panel: " .. chips[i].label .. " ends at " .. right .. " of " .. rail.width)
        if right > widest then widest = right end
        local row = math.floor(-chips[i].y / 24) + 1
        if row > rows then rows = row end
    end
    return widest, rows
end

-- Every chip inside the panel, and the panel inside the preview.
local rail, chips = Rail(), Chips()
local height = H.FlowLayerPopover(rail, chips, {
    width = POPOVER, maxWidth = CAP, maxHeight = BUDGET, rowHeight = 20 })
local widest, rows = Measure(rail, chips)
assert(rows > 1, "model did not wrap; widen the label set")
assert(height == rail.height and height > 0, "rail height not published")
assert(height <= BUDGET, "popover is " .. height .. "px tall, past the " .. BUDGET .. "px it has")
assert(rail.width <= CAP, "popover is wider than the preview it hangs in")
assert(rail.width >= widest, "panel " .. rail.width .. " is narrower than its widest row " .. widest)
print(string.format("popover: %d chips, %d rows, %dx%d panel (budget %dx%d), widest row ends at %d",
    #chips, rows, math.floor(rail.width + 0.5), height, CAP, BUDGET, math.floor(widest + 0.5)))

-- It widens rather than spilling: an impossible height budget pushes it to the
-- cap instead of running off the bottom edge.
local tight, tightChips = Rail(), Chips()
local tightH, tightW = H.FlowLayerPopover(tight, tightChips, {
    width = POPOVER, maxWidth = CAP, maxHeight = 30, rowHeight = 20 })
Measure(tight, tightChips)
assert(tightW == CAP, "a tight budget did not widen the popover to its cap")
assert(tightH < height, "widening did not reduce the row count")
print("tight budget: widened to the " .. CAP .. "px cap, " .. tightH .. "px tall")

-- Negative control: the render pass used to hand in the preview box width while
-- the panel stayed 268 wide.
local wide, wideChips = Rail(), Chips()
H.FlowLayerChips(wide, wideChips, { width = CAP, padX = 10, rowHeight = 20 })
local escaped = 0
for i = 1, #wideChips do
    if wideChips[i].x + wideChips[i].w > POPOVER then escaped = escaped + 1 end
end
assert(escaped > 0, "box-width flow no longer overflows; the negative control is dead")
print("negative control: box-width flow pushes " .. escaped .. " chips outside a " .. POPOVER .. "px panel")

-- Both preview surfaces must route the popover through the fitting flow, and
-- must hand the width back when the rail returns to the docked bottom strip.
local function CheckSurface(path, name, ownerField, presentationPath)
    local source = Read(path)
    local presentation = presentationPath and Read(presentationPath) or source
    local a = assert(source:find("LayoutLayerRail = function", 1, true), name .. ": no LayoutLayerRail")
    local b = assert(source:find("\n    end\n", a, true), name .. ": unterminated LayoutLayerRail")
    local body = source:sub(a, b)
    assert(body:find("local popover = self._msuf2LayerPopoverWidth", 1, true),
        name .. ": LayoutLayerRail does not read the popover width")
    assert(body:find("PreviewHelpers.FlowLayerPopover(" .. ownerField, 1, true),
        name .. ": popover does not use the fitting flow")
    assert(body:find("maxHeight =", 1, true), name .. ": popover has no height budget")
    assert(body:find("maxWidth =", 1, true), name .. ": popover has no width cap")
    assert(presentation:find("_msuf2LayerPopoverWidth = popoverWidth", 1, true),
        name .. ": compact presentation never claims the popover width")
    assert(presentation:find("_msuf2LayerPopoverWidth = nil", 1, true),
        name .. ": docked presentation never releases the popover width")
    assert(not source:find("LayoutLayerRail(popoverWidth + 24)", 1, true)
        and not presentation:find("LayoutLayerRail(popoverWidth + 24)", 1, true),
        name .. ": still flows 24px wider than the panel it paints")
end
CheckSurface(UNIT, "unit preview", "self.sidebar", UNIT_CHROME)
CheckSurface(GROUP, "group preview", "self._layers")
print("preview_layer_popover_smoke: the layer dropdown stays inside its preview on both surfaces")
