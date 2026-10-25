-- Warm navigation must retain layout work and paint-target bindings until their inputs change.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M = mw.M
-- Unspecified global input APIs are opaque truthy stubs in client_world.
-- A regular left click must not be mistaken for the Ctrl+drag pan gesture.
mw.env.IsControlKeyDown = function() return false end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function Click(key)
    M.navLastPageForPrimary[key] = key
    assert(M.navButtons[key], "missing real navigation button"):Click()
    Settle()
    assert(M.activeKey == key, "navigation reached another page")
end
for key in pairs(M.cache) do assert(key == "home", "opening built a hidden page: " .. key) end
Click("opt_misc")
Click("home")
Click("opt_misc")
local entry = M.cache.opt_misc
local layouts, refreshes = 0, 0
for _, body in pairs(entry.sections) do
    local section = body._msuf2CollapsibleEntry
    if section and section._msuf2RefreshLayout then
        local refresh = section._msuf2RefreshLayout
        section._msuf2RefreshLayout = function(...) layouts = layouts + 1; return refresh(...) end
    end
end
entry.refreshers[#entry.refreshers + 1] = function() refreshes = refreshes + 1 end
local frames = mw:Frames()
for _ = 1, 4 do Click("home"); Click("opt_misc") end
assert(mw:Frames() == frames, "warm navigation created frames")
assert(refreshes == 0, "unchanged data ran refreshers")
assert(layouts == 0, "unchanged cached page repeated section layout: " .. layouts)
M.MarkMenuDataDirty("navigation-regression")
Click("home"); Click("opt_misc")
assert(refreshes == 1 and layouts > 0, "changed data did not refresh and settle")
layouts = 0
M.QueueVisiblePageLayoutSettle("opt_misc", entry)
Settle()
assert(layouts == 0, "settled geometry queued again")
-- The opening revision remains necessary: a hidden-window external change is observable.
M.HideSlashMenuAndMinibar(mw.win)
Settle()
assert(M.Open("opt_misc"))
Settle()
assert(refreshes == 2, "reopen reused stale data")
local metrics = M.GetContentMetrics
local width, height = metrics()
M.GetContentMetrics = function() return width + 64, height end
layouts = 0
Click("home"); Click("opt_misc")
assert(layouts > 0 and entry.layoutWidth == width + 64, "resized page skipped layout")
M.GetContentMetrics = metrics
Click("home"); Click("opt_misc")
assert(entry.layoutWidth == width, "restored width was not applied")
Click("opt_colors")
Click("home")
Click("opt_colors")
local tooltips, addTooltip = 0, M.AddTooltip
M.AddTooltip = function(...) tooltips = tooltips + 1; return addTooltip(...) end
frames = mw:Frames()
Click("home"); Click("opt_colors")
assert(mw:Frames() == frames, "cached Colors created frames")
assert(tooltips == 0, "unchanged paint targets rewired tooltips: " .. tooltips)
M.AddTooltip = addTooltip
local inherit
for i = 1, 60 do
    local name, value = debug.getupvalue(M.RuntimeControlCatalog.Register, i)
    if name == "InheritTabPreparation" then inherit = value; break end
end
assert(inherit, "missing actual exact-tab inheritance owner")
local prepared
for _, widget in ipairs(M.cache.opt_colors.searchWidgets) do
    if widget._msuf2InheritedTabPrepare then prepared = widget; break end
end
assert(prepared, "Colors did not build an exact-tab control")
collectgarbage("collect"); collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 50 do inherit(prepared, prepared._msuf2RuntimeControlRecord) end
local allocated = collectgarbage("count") - before
collectgarbage("restart")
assert(allocated < 0.1, "unchanged exact-tab registration allocated " .. allocated .. " KB")
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
end
local state = Upvalue(M.ColorsSetPainterCategory, "state")
local focus, pick = M.Widgets.FocusCollapsibleSection, M.Widgets.OpenColorContextPicker
local focused, picked
M.Widgets.FocusCollapsibleSection = function(section) focused = section; return true end
M.Widgets.OpenColorContextPicker = function(label, owners) picked = label; assert(#owners > 0); return true end
-- Reuse the same target pool across categories; its callbacks must follow the new anchors.
for _, category in ipairs({ "unit", "cast", "group", "resources", "unit" }) do
    M.ColorsSetPainterCategory(category)
    Settle()
    for _, target in ipairs(state.clickTargets) do
        local handler = target:GetScript("OnClick")
        local right = Upvalue(handler, "onRightClick")
        local spec = Upvalue(right, "spec")
        assert(target.allPoints == spec.anchor, "paint target kept another category's anchor")
        focused, picked = nil, nil
        target:Click("RightButton")
        assert(focused == M.cache.opt_colors.sections[spec.sectionId], "paint target opened another section")
        if category == "unit" and spec.sectionId == "colors_appearance" then
            focused, picked = nil, nil
            target:Click("LeftButton")
            assert(picked == spec.label or focused == M.cache.opt_colors.sections[spec.sectionId],
                "paint target opened another color picker/section")
        end
    end
end
M.Widgets.FocusCollapsibleSection, M.Widgets.OpenColorContextPicker = focus, pick
print("menu_navigation_repaint_smoke: ok " .. flavor)
