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
-- The selection has one moving surface. A black skin accent must not make
-- its persistent cue disappear, and the stationary rows must not duplicate it.
do
    local theme, skin = M.Theme, mw.core.MenuSkin
    local originalSkin, originalReduced = skin.Button, theme.ReducedMotionEnabled
    local accent, title = theme.colors.accent, theme.colors.navTextActive
    local savedAccent, savedTitle = { unpack(accent) }, { unpack(title) }
    local function Cue(button)
        local cue = assert(button._msuf2SkinnedSelectionCue, "selected surface has no persistent cue")
        assert(cue.wash:IsShown() and cue.line:IsShown(), "selected surface cue is hidden")
        local wash, line = cue.wash.colorTexture, cue.line.colorTexture
        assert(wash[1] >= 0.8 and wash[2] >= 0.8 and wash[3] >= 0.8 and wash[4] >= 0.18,
            "black accent hid the selection wash")
        assert(line[1] >= 0.8 and line[2] >= 0.8 and line[3] >= 0.8 and line[4] >= 0.9,
            "black accent hid the selection stripe")
    end
    local expectCue = false
    local function OnlyMovingCue(key)
        local button = assert(M.navButtons[key])
        local selection = assert(button._msuf2SelectionMotion)
        assert(selection.selected == button and selection.driver.art:IsShown(), "moving selection lost its owner")
        if expectCue then Cue(selection.driver.art)
        else
            local nativeCue = selection.driver.art._msuf2SkinnedSelectionCue
            assert(not nativeCue or not nativeCue.wash:IsShown(), "native skin retained an extra wash")
            local stripe = assert(selection.driver.art._msuf2NavStripe, "native selection has no rail stripe")
            assert(stripe:IsShown() and stripe.width == 3, "native selection hid the rail stripe")
        end
        local cue = button._msuf2SkinnedSelectionCue
        assert(not cue or (not cue.wash:IsShown() and not cue.line:IsShown()), "stationary row duplicates moving cue")
        return selection
    end
    accent[1], accent[2], accent[3] = 0, 0, 0
    title[1], title[2], title[3] = 0.94, 0.96, 1
    for _, skinned in ipairs({ false, true, false, true }) do
        expectCue = skinned
        skin.Button = function() return skinned end
        for _, reduced in ipairs({ false, true }) do
            theme.ReducedMotionEnabled = function() return reduced end
            Click("home")
            local selection = OnlyMovingCue("home")
            MW.FireScript(M.navButtons.home, "OnEnter")
            OnlyMovingCue("home")
            local feedback = M.navButtons.home._msuf2ButtonMotion
            local hoverCue = feedback and feedback.art._msuf2SkinnedSelectionCue
            assert(not hoverCue or not hoverCue.wash:IsShown(), "hover duplicates the selection cue")
            MW.FireScript(M.navButtons.home, "OnMouseDown")
            local pressCue = feedback and feedback.art._msuf2SkinnedSelectionCue
            assert(not pressCue or not pressCue.line:IsShown(), "press duplicates the selection cue")
            MW.FireScript(M.navButtons.home, "OnMouseUp")
            MW.FireScript(M.navButtons.home, "OnLeave")
            Click("opt_misc")
            assert(OnlyMovingCue("opt_misc") == selection, "navigation replaced its reusable selection")
            M.HideSlashMenuAndMinibar(mw.win)
            Settle()
            assert(M.Open("opt_misc"))
            Settle()
            OnlyMovingCue("opt_misc")
        end
    end
    title[1], title[2], title[3] = 0.82, 0.84, 0.86
    local selected = M.navButtons.opt_misc._msuf2SelectionMotion
    M.Widgets.RefreshSelectionMotion(selected.owner, true)
    Cue(selected.driver.art)
    assert(selected.driver.art._msuf2SkinnedSelectionCue.line.colorTexture[1] == 0.82,
        "theme repaint retained the old selection color")
    local function Outline(button, shown)
        assert(not button._msuf2SkinnedSelectionCue and not button._msuf2TabOutline,
            "a tab created a second selection cue")
        local outline, fill = button._msuf2Edge, button._msuf2Fill
        local tint = shown and M.Theme.colors.navTextActive
        for _, key in ipairs({ "L", "M", "R" }) do
            local edge = outline[key]
            local layer, sublevel = edge:GetDrawLayer()
            assert(layer == "BACKGROUND" and sublevel == -1 and edge:GetTexture() == fill[key]:GetTexture(),
                "tab rim does not share the fill shape and sit behind it")
            if tint then
                assert(edge.vertexColor[1] == tint[1] and edge.vertexColor[4] >= 0.8, "tab rim lost its contrast")
            else
                assert(edge.vertexColor[1] < M.Theme.colors.navTextActive[1], "deselected tab kept its bright rim")
            end
        end
        return outline
    end
    skin.Button = function() return false end
    local owner = mw.env.CreateFrame("Frame", nil, mw.win)
    owner:SetPoint("TOPLEFT", mw.win, "TOPLEFT", 20, -20)
    owner:SetSize(200, 60)
    local static = theme.StyleTabButton(theme.Button(owner, "Choice", 90, 24))
    local regions = static:GetNumRegions()
    static:SetActive(true)
    local outline = Outline(static, true)
    static:SetSize(160, 26)
    MW.FireScript(static, "OnSizeChanged", 160, 26)
    assert(Outline(static, true) == outline and static:GetNumRegions() == regions, "resize recreated the native tab rim")
    static:SetEnabled(false)
    Outline(static, false)
    static:SetEnabled(true)
    Outline(static, true)
    static:SetActive(false)
    Outline(static, false)

    local tabs = M.Widgets.Segment(owner, "General settings",
        { { value = "general", text = "General settings" }, { value = "look", text = "Appearance" } }, 196)
    local choices = tabs.buttons
    tabs:SetValue("general")
    Settle()
    local selection = assert(choices[1]._msuf2SelectionMotion)
    local surface = assert(selection.driver.art)
    assert(surface:IsShown() and selection.selected == choices[1], "first tab lost its selection surface")
    local movingOutline = Outline(surface, true)
    Outline(choices[1], false)
    MW.FireScript(choices[1], "OnEnter")
    assert(Outline(surface, true) == movingOutline, "hover replaced the selected outline")
    local feedback = choices[1]._msuf2ButtonMotion
    if feedback then Outline(feedback.art, false) end
    MW.FireScript(choices[1], "OnLeave")
    tabs:SetValue("look")
    Settle()
    assert(selection.selected == choices[2] and Outline(surface, true) == movingOutline, "tab switch replaced the outline")
    Outline(choices[2], false)
    local menuScale, uiScale = mw.win:GetScale(), mw.env.UIParent:GetScale()
    mw.win:SetScale(0.57)
    mw.env.UIParent:SetScale(0.48)
    assert(Outline(surface, true) == movingOutline, "scaling replaced the selected outline")
    mw.env.UIParent:SetScale(uiScale)
    mw.win:SetScale(menuScale)
    skin.Button, theme.ReducedMotionEnabled = originalSkin, originalReduced
    for index = 1, 4 do accent[index], title[index] = savedAccent[index], savedTitle[index] end
    owner:Hide()
    Click("home")
end
-- A real section and its chevron sample the same native timing. Changing
-- direction seeds both from the current pose; reduced motion settles both.
do
    Click("opt_misc")
    local section
    for _, body in pairs(entry.sections) do
        local candidate = body._msuf2CollapsibleEntry
        if candidate and candidate.outer:IsVisible() then section = candidate break end
    end
    assert(section, "missing visible disclosure section")
    local reduced = M.Theme.ReducedMotionEnabled
    M.Theme.ReducedMotionEnabled = function() return false end
    section.SetOpenImmediate(false)
    section.SetOpenByUser(true)
    local height = assert(section._msuf2AccordionMotion)
    local arrow = assert(section.arrow._msuf2DisclosureMotion)
    local function Tick(driver, remaining)
        driver.foldClock.GetSmoothProgress = function() return remaining end
        driver:GetScript("OnUpdate")(driver, 0)
    end
    for _, driver in ipairs({ height, arrow }) do
        assert(driver.foldClock.duration == 0.150 and driver.foldClock.smoothing == "IN" and driver.foldGroup.reverse,
            "section and chevron must use the same native 150 ms disclosure")
        Tick(driver, 0.25)
    end
    local visibleHeight, angle = height.channels[1].value, arrow.channels[1].value
    section.contentHeight = section.contentHeight * 2
    section.builder:RelayoutCollapsibles()
    Tick(height, 0.25)
    assert(height.channels[1].value == visibleHeight, "a content resize jumped to the new endpoint")
    assert(visibleHeight > 0 and angle == 0.75, "native progress did not drive the fold")
    section.SetOpenByUser(false)
    assert(height.channels[1].start == visibleHeight and arrow.channels[1].start == angle,
        "rapid collapse must begin at the rendered position")
    Tick(height, 0.5)
    Tick(arrow, 0.5)
    assert(height.channels[1].value == visibleHeight * 0.5 and arrow.channels[1].value == angle * 0.5,
        "height and chevron progress diverged")
    M.Theme.ReducedMotionEnabled = function() return true end
    Tick(height, 0)
    assert(not height:GetScript("OnUpdate") and not arrow:GetScript("OnUpdate") and not section.body:IsShown(),
        "reduced motion must settle the geometry and arrow")
    M.Theme.ReducedMotionEnabled = reduced
end
print("menu_navigation_repaint_smoke: ok " .. flavor)
