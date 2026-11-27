-- The real Icon Skins page must contain its positioned controls at every width.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M = mw.M

-- Mirror the extra samples the Suite registers. Model fixed-width wrapped font
-- metrics because the shared stub reports a single line at every width.
for i = 1, 5 do
    assert(M.IconSkinsPage.RegisterArea({
        key = "test_suite_icon_" .. i,
        group = "Suite",
        label = i == 1 and "Additional defensive cooldown icons" or "Suite icons",
        icon = "Interface/Icons/Spell_Holy_PowerWordShield",
        read = function() return "DEFAULT" end,
        write = function() end,
    }))
end
local methods = mw.world.widgets.Methods
local originalStringHeight = methods.GetStringHeight
local lineHeight = 13
function methods:GetStringHeight()
    if not self.parent or self.parent._msuf2SectionId ~= "icon_skins_strip" then
        return originalStringHeight(self)
    end
    local width = self:GetWidth()
    local lines, used = 1, 0
    for word in (self:GetText() or ""):gmatch("%S+") do
        local pixels = #word * 7
        if used > 0 and used + 7 + pixels > width then
            lines, used = lines + 1, 0
        end
        used = used == 0 and pixels or used + 7 + pixels
    end
    return lines * lineHeight
end

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

local function StripOffset(region, body)
    local point, parent, anchor, x, y = region:GetPoint()
    assert(point == "TOPLEFT", "sample must have a top-left anchor")
    if parent == body then return x, y end
    local parentX, parentY = StripOffset(parent, body)
    if anchor == "BOTTOMLEFT" then
        parentY = parentY - (parent:GetObjectType() == "FontString" and parent:GetStringHeight() or parent:GetHeight())
    end
    return parentX + x, parentY + y
end

local function CheckStrip()
    local page = M.cache.icon_skins
    local body = page.sections.icon_skins_strip
    local entry = body._msuf2CollapsibleEntry
    local rowY, rowBottom
    local count, rows = 0, 0
    for _, icon in ipairs({ body:GetChildren() }) do
        if icon.label and icon.skin then
            count = count + 1
            local _, y = StripOffset(icon, body)
            if rowY ~= y then
                assert(not rowBottom or y <= rowBottom - 6, "next icon row overlaps wrapped skin captions")
                rowY, rowBottom, rows = y, y, rows + 1
            end
            local labelX, labelY = StripOffset(icon.label, body)
            local skinX, skinY = StripOffset(icon.skin, body)
            assert(labelY <= y - icon:GetHeight(), "icon overlaps title")
            assert(skinY <= labelY - icon.label:GetStringHeight() - 2, "wrapped title overlaps skin caption")
            assert(labelX + icon.label:GetWidth() <= body:GetWidth() - 8, "title exceeds the section width")
            assert(skinX + icon.skin:GetWidth() <= body:GetWidth() - 8, "skin caption exceeds the section width")
            rowBottom = math.min(rowBottom, skinY - icon.skin:GetStringHeight())
        end
    end
    assert(count >= 9 and rows >= 2, "multi-row Suite icon strip required")
    assert(-rowBottom + 12 <= body:GetHeight(), "last icon row exceeds the section height")
    assert(entry.contentHeight == body:GetHeight(), "icons accordion must use the measured body height")
    local nextOuter = page.sections.icon_skins_default._msuf2CollapsibleEntry.outer
    local _, _, _, _, top = entry.outer:GetPoint()
    local _, _, _, _, nextY = nextOuter:GetPoint()
    assert(nextY <= top - entry.outer:GetHeight() - 8, "Default Skin starts inside the icons accordion")
    return body, rows
end

local homeHeight = M.scrollChild:GetHeight()
local hidden = assert(M.BuildPageEntry("icon_skins", true))
assert(hidden.hiddenBuild and hidden.sections.icon_skins_strip, "hidden search build must construct the icon strip")
assert(M.scrollChild:GetHeight() == homeHeight, "hidden search build must preserve the current page's height")

for _, width in ipairs({ 1000, 1500, 720 }) do
    M.GetContentMetrics = function() return width, 700 end
    M.InvalidatePage("icon_skins")
    assert(M.SelectPage("icon_skins"))
    Settle()
    local strip, stripRows = CheckStrip()
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
    assert(CheckStrip() == strip, "cached icon strip required")
    if width == 1000 then
        local height = strip:GetHeight()
        lineHeight = 19
        M.Refresh()
        Settle()
        CheckStrip()
        assert(strip:GetHeight() > height, "taller captions must grow the open section")
        lineHeight = 13
        M.Refresh()
        Settle()
        assert(strip:GetHeight() == height, "shorter captions must shrink the open section")

        M.GetContentMetrics = function() return 630, 700 end
        assert(M.SelectPage("icon_skins"))
        Settle()
        local resized, rows = CheckStrip()
        assert(resized == strip and rows > stripRows, "retained icon strip must reflow at narrower width")
        MenuWorld.FireVisibilityScripts(M.cache.icon_skins.wrapper)
        assert(M.SelectPage("home"))
        M.GetContentMetrics = function() return width, 700 end
        assert(M.SelectPage("icon_skins"))
        local restored, restoredRows = CheckStrip()
        assert(restored == strip and restoredRows == stripRows, "retained strip must reflow as soon as it is shown")
        Settle()

        local entry = strip._msuf2CollapsibleEntry
        entry.SetOpenImmediate(false)
        Settle()
        assert(not strip:IsShown(), "icon strip should hide while folded")
        entry.SetOpenImmediate(true)
        Settle()
        assert(CheckStrip():GetHeight() == height, "reopening the strip must restore its measured height")

        assert(M.SelectPage("home"))
        Settle()
        local scrollHeight = M.scrollChild:GetHeight()
        M.IconSkinsPage.SelectDefault("BORDERLESS")
        Settle()
        assert(M.scrollChild:GetHeight() == scrollHeight, "hidden icon strip changed another page's scroll height")
        assert(M.SelectPage("icon_skins"))
        Settle()
        assert(CheckStrip():GetHeight() < height, "shorter skin captions must shrink the strip on return")
        M.IconSkinsPage.SelectDefault("CUSTOM")
        Settle()
        assert(CheckStrip():GetHeight() == height, "restoring the long skin captions must regrow the strip")
    end
end
print("icon_skins_section_bounds_smoke " .. flavor .. ": strip and gallery bounds, wrapped text, resize and cached return pass")
