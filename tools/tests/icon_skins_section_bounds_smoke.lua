-- The real Icon Skins page must contain its positioned controls at every width.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M = mw.M

local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end

local function CheckBounds(width)
    local body = assert(M.cache.icon_skins.sections.icon_skins_default)
    local sliders, toggles, tiles, family = 0, 0, 0
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame:GetParent() == body then
            local point, relative, relativePoint, _, y = frame:GetPoint()
            if point == "TOPLEFT" and relative == body and relativePoint == "TOPLEFT" then
                local bottom = -y + frame:GetHeight()
                assert(bottom + 14 <= body:GetHeight(), string.format(
                    "%s width %d: %s bottom %.0f needs 14px padding inside section height %.0f",
                    flavor, width, frame._msuf2ControlKind or "tile", bottom, body:GetHeight()))
                if frame._msuf2ControlKind == "slider" then sliders = sliders + 1 end
                if frame._msuf2ControlKind == "toggle" then toggles = toggles + 1 end
                if frame._msuf2ControlKind == "segment" then family = frame end
                if frame.skinId then tiles = tiles + 1 end
            end
        end
    end
    assert(sliders == 2 and toggles == 1 and tiles > 40, "real look controls and complete skin gallery required")
    assert(body._msuf2CollapsibleEntry.contentHeight == body:GetHeight(), "accordion height must match body")
    local outer = body._msuf2CollapsibleEntry.outer
    local nextOuter = M.cache.icon_skins.sections.icon_skins_areas._msuf2CollapsibleEntry.outer
    local _, _, _, _, y = outer:GetPoint()
    local _, _, _, _, nextY = nextOuter:GetPoint()
    assert(nextY <= y - outer:GetHeight() - 8, "following section must start below the complete default section")
    return body, assert(family, "family selector required")
end

for _, width in ipairs({ 1500, 720, 1000 }) do
    M.GetContentMetrics = function() return width, 700 end
    M.InvalidatePage("icon_skins")
    assert(M.SelectPage("icon_skins"))
    Settle()
    local body, family = CheckBounds(width)
    local height = body:GetHeight()
    for _, value in ipairs({ "Shadow", "ALL" }) do
        local button
        for _, choice in ipairs(family.buttons) do
            if choice._msuf2Value == value then button = choice end
        end
        assert(button, "real family button required"):Click()
        Settle()
        assert(CheckBounds(width):GetHeight() == height, "filtering must preserve room for look controls")
    end
    body._msuf2CollapsibleEntry.SetOpenImmediate(false)
    Settle()
    body._msuf2CollapsibleEntry.SetOpenImmediate(true)
    Settle()
    assert(CheckBounds(width):GetHeight() == height, "reopen must preserve the measured height")
    assert(M.SelectPage("home"))
    assert(M.SelectPage("icon_skins"))
    Settle()
    assert(CheckBounds(width) == body, "cached page must retain its correctly sized section")
end
print("icon_skins_section_bounds_smoke " .. flavor .. ": narrow, normal, wide, fold/reopen and cached return pass")
