-- menu_scope_bar_resize_smoke.lua <repoRoot> <flavor>
--
-- A retained page only reflows when the menu window is resized
-- (Shell/Menu2/MSUF_Menu2_Window_PageEntry.lua). The Editing scope bar
-- (MSUF_Menu2_Widgets_Controls.lua) wraps its buttons again on that reflow, so
-- a Bars page built wide and shown narrow no longer keeps one long row of
-- scope buttons past the window edge. On the client's real menu:
--   * the narrowed page is the same retained entry, every scope button ends
--     inside its bar, and the section's controls below the buttons moved down
--     with the extra rows, inside the section's new height;
--   * widening again restores the original rows and every original position.
-- Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home" })
local M = mw.M

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local _, height = M.GetContentMetrics()
local function SetContentWidth(width)
    M.GetContentMetrics = function() return width, height end
end

-- The scope bars in a page's frame tree.
local function CollectBars(frame, bars)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child._msuf2Rows and child.buttons then bars[#bars + 1] = child end
        CollectBars(child, bars)
    end
    return bars
end

-- Top-edge offsets of everything a scope bar's section places, except the bar.
local function SectionLayout(bar)
    local section, skip, layout = bar:GetParent(), { [bar] = true, [bar.label] = true }, {}
    for _, button in ipairs(bar.buttons) do skip[button] = true end
    local objects = { section:GetChildren() }
    for _, region in ipairs({ section:GetRegions() }) do objects[#objects + 1] = region end
    for _, object in ipairs(objects) do
        if not skip[object] then
            local _, relative, relativePoint, _, y = object:GetPoint(1)
            if relative == section and type(relativePoint) == "string" and relativePoint:find("^TOP") then
                layout[object] = y or 0
            end
        end
    end
    return section, layout
end

-- Every scope button ends inside its bar; nothing in the section overlaps the
-- button rows, and the section is tall enough for what it places.
local function CheckBars(label)
    local entry = Check(M.cache.opt_bars, label .. ": the Bars page did not build")
    local bars = CollectBars(entry.wrapper, {})
    Check(#bars > 0, label .. ": the Bars page has no scope bar")
    local rows, layouts = 0, {}
    for _, bar in ipairs(bars) do
        local barWidth = bar:GetWidth()
        for _, button in ipairs(bar.buttons) do
            local _, _, _, x = button:GetPoint(1)
            Check(x + button:GetWidth() <= barWidth, ("%s: scope button %s ends at %d, past the bar width %d")
                :format(label, tostring(button._msuf2Value), x + button:GetWidth(), barWidth))
        end
        local section, layout = SectionLayout(bar)
        local lowest = bar._msuf2BottomY
        for _, y in pairs(layout) do
            Check(y >= bar._msuf2LastRowCenterY + 12 or y <= bar._msuf2BottomY,
                ("%s: a control at y %d overlaps the scope rows down to %d"):format(label, y, bar._msuf2BottomY))
            if y < lowest then lowest = y end
        end
        Check(section:GetHeight() > -lowest, ("%s: the section height %d ends above its control at y %d")
            :format(label, section:GetHeight(), lowest))
        rows = math.max(rows, bar._msuf2Rows)
        layouts[bar] = layout
    end
    return entry, rows, layouts
end

SetContentWidth(1180)
Check(mw:Select("opt_bars"), "the Bars page did not open")
local wide, wideRows, wideLayouts = CheckBars("built wide")

-- Another page, a narrower window, then back: the retained entry reflows.
Check(mw:Select("home"), "the Dashboard did not open")
SetContentWidth(620)
Check(mw:Select("opt_bars"), "the Bars page did not reopen")
local narrow, narrowRows = CheckBars("reopened narrow")
Check(narrow == wide, "narrowing rebuilt the Bars page instead of reflowing it")
Check(narrowRows > wideRows, "the narrow Bars page kept the wide scope rows")

-- The active page's resize path (Window.lua RebuildActivePageForResize).
SetContentWidth(1180)
M.activeKey = nil
Check(mw:Select("opt_bars"), "the active Bars page did not reselect after widening")
local widened, widenedRows, widenedLayouts = CheckBars("widened in place")
Check(widened == wide and widenedRows == wideRows, "widening left the scope buttons on " .. widenedRows .. " rows")
for bar, layout in pairs(wideLayouts) do
    for object, y in pairs(layout) do
        Check(widenedLayouts[bar][object] == y, ("widening left a control at y %s instead of %d")
            :format(tostring(widenedLayouts[bar][object]), y))
    end
end

print(("menu_scope_bar_resize_smoke: ok (%s, %d rows wide, %d narrow)"):format(flavor, wideRows, narrowRows))
