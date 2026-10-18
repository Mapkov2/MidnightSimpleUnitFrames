-- Menu2 navigation rail: availability with a reason, hidden rows, foldable
-- group titles and a window title that is the rail breadcrumb.
--
-- The rail is built for real on a booted client world. Two Suite-shaped rows
-- are inserted the way the Suite does it (in place, by group id): one module
-- that is switched off (dimmed, "Off" badge, reason tooltip) and one whose
-- addon is not installed (hidden, its group title with it).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Boot(flavor, locale, preset)
    local world = World.New(root, flavor, { locale = locale })
    if preset then world.env.MSUF_DB = { general = { menuAppearancePreset = preset } } end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file)
        .. ": " .. tostring(failure and failure.message))
    -- The rail search box and list are an EditBox and a ScrollFrame; the shared
    -- stubs only carry the frame surface.
    local methods = world.widgets.Methods
    local function Add(name, fn) if methods[name] == nil then methods[name] = fn end end
    local noop = function() end
    for _, name in ipairs({ "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetGradientAlpha",
        "SetRoundLayoutToNearestPixel", "SetFocus", "ClearFocus", "HighlightText",
        "SetThickness", "SetStartPoint", "SetEndPoint" }) do
        Add(name, noop)
    end
    Add("HasFocus", function() return false end)
    Add("SetChecked", function(self, value) self.checked = value end)
    Add("GetChecked", function(self) return self.checked end)
    Add("SetScrollChild", function(self, child) self.scrollChild = child end)
    Add("GetScrollChild", function(self) return self.scrollChild end)
    Add("SetVerticalScroll", function(self, offset) self.verticalScroll = offset end)
    Add("GetVerticalScroll", function(self) return self.verticalScroll or 0 end)
    -- Native templates supply a font; the generic offline frame stubs do not.
    local createFontString = methods.CreateFontString
    methods.CreateFontString = function(self, ...)
        local label = createFontString(self, ...)
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        return label
    end
    local env = world.env
    local tip = { lines = {} }
    env.GameTooltip = {
        SetOwner = function() tip.title, tip.lines = nil, {} end,
        SetText = function(_, text) tip.title = text end,
        AddLine = function(_, text) tip.lines[#tip.lines + 1] = text end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
    }
    return world, env, assert(env.MSUF2, flavor .. ": Menu2 namespace missing"), tip
end

local function Last(frame, pointName)
    local found
    for _, point in ipairs(frame.points) do
        if point.point == pointName then found = point end
    end
    return found
end
local function Y(frame)
    local point = assert(Last(frame, "TOPLEFT"), "frame has no TOPLEFT point")
    return point.y
end
local function Hover(frame, tip)
    tip.title, tip.lines, tip.shown = nil, {}, false
    local enter = frame:GetScript("OnEnter")
    if enter then enter(frame) end
    local leave = frame:GetScript("OnLeave")
    if leave then leave(frame) end
    return tip.title, tip.lines[1]
end
local function InsertAfterTitle(items, groupId, row)
    for index, item in ipairs(items) do
        if item.title and item.id == groupId then
            table.insert(items, index + 1, row)
            return
        end
    end
    error("navigation group " .. groupId .. " missing")
end
local function TitleRow(M, id)
    local text = assert(M.navTitles[id], "no title for " .. id)
    local owner = assert(text:GetParent(), "title " .. id .. " has no row")
    return owner._msuf2ControlPartOf or owner
end

local function Fire(frame, name, ...)
    local handler = frame:GetScript(name)
    if handler then handler(frame, ...) end
end
local function Advance(driver, duration)
    for _ = 1, math.ceil(duration / 0.01) do
        Fire(driver, "OnUpdate", 0.01)
        -- WoW ticks each visible child driver on the same frame.
        for _, row in ipairs(driver.rows or {}) do
            local frame = row.button or row.frame
            local arrow = frame and frame._msuf2NavArrow
            if arrow and arrow._msuf2DisclosureMotion then Fire(arrow._msuf2DisclosureMotion, "OnUpdate", 0.01) end
        end
    end
end
local function Rect(frame, left, top)
    frame.left, frame.bottom = left, top - frame:GetHeight()
end
local function Selection(owner)
    return assert(owner._msuf2SelectionMotions and owner._msuf2SelectionMotions[1], "selector motion missing")
end
local function AssertSettled(driver)
    assert(not driver:GetScript("OnUpdate"), "motion retains an idle frame callback")
    for _, c in ipairs(driver.channels) do
        assert(c.value == c.target and c.velocity == 0, "motion did not settle exactly")
    end
end
local function NavigationMotion(world, M, row, title)
    local width, height, x, y = row:GetWidth(), row:GetHeight(), Last(row, "TOPLEFT").x, Y(row)
    local alpha = row:GetAlpha()
    assert(not row._msuf2ButtonMotion, "navigation eagerly allocated hover motion")
    Fire(row, "OnEnter")
    local driver = assert(row._msuf2ButtonMotion)
    assert(driver.duration == 0.12, "hover became slower than the approved 120ms")
    Advance(driver, 0.03)
    local c = driver.channels[1]
    local position, velocity = c.value, c.velocity
    assert(position > 0 and position < c.target and velocity > 0, "hover does not ease into its target")
    Fire(row, "OnMouseDown")
    assert(driver.duration == 0.14, "press became slower than the approved 140ms")
    assert(c.value == position and c.velocity == velocity, "press restarted current motion")
    Fire(row, "OnLeave")
    assert(c.value == position and c.velocity == velocity and c.target == 0, "leave snapped instead of retargeting")
    Advance(driver, 0.12)
    AssertSettled(driver)
    local selectPage, selected = M.SelectPage
    M.SelectPage = function(key) selected = key end
    local frameCount = #world.widgets.frames
    for _ = 1, 25 do
        Fire(row, "OnEnter")
        Fire(row, "OnMouseDown")
        Fire(row, "OnClick")
        Fire(row, "OnMouseUp")
        Advance(driver, 0.03)
        Fire(row, "OnLeave")
    end
    assert(selected, "animation swallowed navigation")
    assert(#world.widgets.frames == frameCount and row._msuf2ButtonMotion == driver, "warm hover allocated new frames")
    assert(row:GetAlpha() == alpha, "motion changed availability dimming")
    assert(row:GetWidth() == width and row:GetHeight() == height
        and Last(row, "TOPLEFT").x == x and Y(row) == y, "motion changed hitbox geometry")
    assert(not row:GetScript("OnUpdate"), "motion ticks the button itself")
    M.Theme.StopAllMenuAnimations()
    AssertSettled(driver)
    assert(c.value == 0, "quiescence retained hover feedback")
    Fire(row, "OnEnter")
    row:Hide()
    Fire(row, "OnHide") -- Generic widget stubs do not dispatch native visibility scripts.
    AssertSettled(driver)
    assert(not row._msuf2Hover, "hidden navigation retained hover state")
    row:Show()
    assert(not driver:GetScript("OnUpdate"), "reopening replayed stale motion")
    for _, key in ipairs({ "reduceMotion", "reducedMotion" }) do
        world.env.MSUF_DB.general[key] = true
        Fire(row, "OnEnter")
        Fire(row, "OnMouseDown")
        AssertSettled(driver)
        world.env.MSUF_DB.general[key] = nil
    end
    row:Disable()
    Fire(row, "OnDisable")
    Fire(row, "OnEnter")
    AssertSettled(driver)
    row:Enable()
    M.SelectPage = selectPage
    Fire(title, "OnEnter")
    assert(title._msuf2ButtonMotion:GetScript("OnUpdate"), "title hover missing")
    Fire(title, "OnClick")
    Fire(title, "OnClick")
    Fire(title, "OnHide")
    AssertSettled(title._msuf2ButtonMotion)
end
local function NavigationSelection(M, parent)
    local list = parent._msuf2NavList
    Rect(list, 0, 600)
    list.GetTop = function() return 600 end
    for _, button in pairs(M.navButtons) do
        button.GetLeft = function(self) return Last(self, "TOPLEFT").x end
        button.GetTop = function(self) return 600 + Y(self) end
    end
    local first, second = M.navButtons.home, M.navButtons.uf_player
    first:SetActive(true)
    local selection = Selection(list)
    local driver = assert(selection.driver)
    AssertSettled(driver)
    assert(#driver.channels == 4 and driver.channels[3].value == first:GetWidth()
        and driver.channels[4].value == first:GetHeight(), "selected surface is a stripe instead of the whole fill")
    assert(driver.art._msuf2Fill and driver.art._msuf2Edge, "moving surface bypasses the skin renderer")
    assert(first._msuf2Label:GetParent():GetFrameLevel() > driver.art:GetFrameLevel(), "moving fill covers the label")
    assert(driver.duration == 0.14, "selection became slower than the approved 140ms")
    local start = driver.channels[2].value
    first:SetActive(false)
    second:SetActive(true)
    assert(driver.channels[2].value == start, "selection jumped on click")
    Advance(driver, 0.06)
    assert(math.abs(driver.channels[2].value - driver.channels[2].target)
        < math.abs(start - driver.channels[2].target) * 0.05, "selection easing lost its snappy first 60ms")
    local c = driver.channels[2]
    local position, velocity = c.value, c.velocity
    assert(position ~= start and velocity ~= 0, "nav marker did not move")
    first:SetActive(true) -- Exercise both SetActive loop orders.
    second:SetActive(false)
    assert(c.value == position and c.velocity == velocity, "nav reversal reset position or velocity")
    Fire(first, "OnEnter")
    assert(not first._msuf2NavStripe or not first._msuf2NavStripe:IsShown(), "static nav stripe duplicates the moving marker")
    local skinCue = first._msuf2SkinnedSelectionCue
    assert(not skinCue or not skinCue.line:IsShown(), "skin stripe duplicates the moving marker")
    Advance(driver, 0.14)
    AssertSettled(driver)
    assert(c.value == start, "nav marker settled on the wrong row")
    second:SetActive(true)
    first:SetActive(false)
    Advance(driver, 0.02)
    parent:_msuf2NavReflow()
    AssertSettled(driver)
    assert(c.value == second:GetTop() - list:GetTop(), "nav reflow left marker at stale coordinates")
    second:Hide()
    Fire(second, "OnHide")
    assert(not driver.art:IsShown() and not driver:GetScript("OnUpdate"), "hidden selected row retained marker")
    second:Show()
    Fire(second, "OnShow")
    AssertSettled(driver)
    assert(driver.art:IsShown(), "reopened row lost its marker")
    second:SetActive(false)
    Advance(driver, 0.01)
    assert(not driver.art:IsShown(), "no active selection retained its marker")
end
local function TabScopeMotion(world, M, parent)
    local W, env = M.Widgets, world.env
    local section = env.CreateFrame("Frame", nil, parent)
    section:SetSize(300, 200)
    Rect(section, 100, 500)
    local values = { { value = "one", text = "One", width = 60 }, { value = "two", text = "Two", width = 60 },
        { value = "three", text = "Three", width = 60 } }
    local function Layout(control, wrap)
        Rect(control, 100, 500)
        for i, button in ipairs(control.buttons) do
            Rect(button, 100 + ((wrap and i == 3) and 0 or (i - 1) * 68), (wrap and i == 3) and 444 or 474)
        end
        Fire(control, "OnShow") -- Supply layout readiness that the generic stubs do not dispatch.
    end
    local segment = W.Segment(section, "Tabs", values, 240)
    Layout(segment)
    segment:SetValue("one")
    local driver = assert(Selection(segment).driver)
    AssertSettled(driver)
    assert(driver.duration == 0.16 and driver.rate == 65, "upper tabs lost their separate softer timing")
    segment:SetValue("two")
    Advance(driver, 0.06)
    local progress = driver.channels[1].value / driver.channels[1].target
    assert(progress > 0.89 and progress < 0.95, "upper tabs are no longer softer while staying responsive")
    local c, selectedWidth = driver.channels[1], driver.channels[3].target
    local position, velocity = c.value, c.velocity
    segment:SetValue("three")
    assert(c.value == position and c.velocity == velocity, "tab interruption is discontinuous")
    Advance(driver, 0.16)
    AssertSettled(driver)
    assert(driver.channels[3].value == selectedWidth, "tab marker changed hitbox width")
    local value, replacement = "one", nil
    local function BuildScope(setter)
        local bar = W.ScopeOverrideBar({}, section, { values = values, label = "Scope", width = 160, startX = 0, centerY = -38,
            getValue = function() return value end, setValue = setter })
        Layout(bar, true)
        bar:Refresh()
        return bar
    end
    local scope
    scope = BuildScope(function(nextValue)
        value = nextValue
        scope:Hide()
        Fire(scope, "OnHide")
        for _, button in ipairs(scope.buttons) do button:Hide(); Fire(button, "OnHide") end
        replacement = BuildScope(function(v) value = v end)
    end)
    local oldDriver = assert(Selection(scope).driver)
    local oldX, oldY = oldDriver.channels[1].value, oldDriver.channels[2].value
    Fire(scope.buttons[3], "OnClick") -- Real setter destroys/rebuilds the selector before Refresh.
    assert(replacement and value == "three", "scope click did not reach its model")
    local newDriver = assert(Selection(replacement).driver)
    assert(newDriver.channels[1].value == oldX and newDriver.channels[2].value == oldY
        and newDriver:GetScript("OnUpdate"), "rebuilt scope snapped instead of continuing motion")
    Advance(newDriver, 0.04)
    local cy = newDriver.channels[2]
    local py, vy = cy.value, cy.velocity
    replacement:SetValue("two")
    assert(cy.value == py and cy.velocity == vy, "wrapped scope reversal reset motion")
    Advance(newDriver, 0.16)
    AssertSettled(newDriver)
    assert(cy.value == -26, "wrapped scope marker settled on wrong line")
    for _, key in ipairs({ "reduceMotion", "reducedMotion" }) do
        env.MSUF_DB.general[key] = true
        replacement:SetValue("three")
        AssertSettled(newDriver)
        assert(cy.value == -56, "reduced-motion scope lost static selection")
        env.MSUF_DB.general[key] = nil
        replacement:SetValue("two")
    end
    M.Theme.StopAllMenuAnimations()
    AssertSettled(newDriver)
    -- A custom top-button painter must survive hide/disable, and multiple
    -- independent tab rows may share one owner (Aura controls do this).
    local a = W.TopButton(section, "A", 60, 24, { activeTextColor = { 0.2, 0.4, 0.6, 1 } })
    local b = W.TopButton(section, "B", 60, 24, {})
    a._msuf2Value, b._msuf2Value = "a", "b"
    Rect(a, 100, 474); Rect(b, 168, 474)
    local top = W.AttachSelectionMotion(section, { a, b }, false, "top")
    a:SetActive(true)
    Fire(a, "OnDisable")
    assert(a._msuf2Label.textColor[1] == 0.2 and a._msuf2Label.textColor[3] == 0.6,
        "motion replaced the custom active painter")
    Fire(a, "OnHide")
    Fire(a, "OnShow")
    assert(top.driver.art:IsShown(), "top-button reopen lost selected marker")
    b:SetActive(true)
    a:SetActive(false)
    Advance(top.driver, 0.16)
    AssertSettled(top.driver)
    local c = W.TopButton(section, "C", 60, 24, {})
    local d = W.TopButton(section, "D", 60, 24, {})
    c._msuf2Value, d._msuf2Value = "c", "d"
    Rect(c, 100, 444); Rect(d, 168, 444)
    local secondRow = W.AttachSelectionMotion(section, { c, d }, false, "second-row")
    c:SetActive(true)
    W.BeginSelectionMotion(d, "d")
    local replacementParent = env.CreateFrame("Frame", nil, parent)
    replacementParent:SetSize(300, 200)
    Rect(replacementParent, 100, 500)
    local c2 = W.TopButton(replacementParent, "C", 60, 24, {})
    local d2 = W.TopButton(replacementParent, "D", 60, 24, {})
    c2._msuf2Value, d2._msuf2Value = "c", "d"
    Rect(c2, 100, 444); Rect(d2, 168, 444)
    local secondReplacement = W.AttachSelectionMotion(replacementParent, { c2, d2 }, false, "second-row")
    d2:SetActive(true)
    assert(secondReplacement.driver.channels[1].value == secondRow.driver.channels[1].value
        and secondReplacement.driver.channels[1].value ~= top.driver.channels[1].value,
        "shared-owner handoff captured the wrong tab row")
    Fire(replacementParent, "OnShow")
    Fire(d2, "OnShow")
    assert(secondReplacement.driver:GetScript("OnUpdate"), "OnShow order cancelled replacement motion")
    Advance(secondReplacement.driver, 0.16)
    AssertSettled(secondReplacement.driver)
end

local function FoldMotion(world, M, parent)
    local list = parent._msuf2NavList
    M.UpdateNav("opt_fonts")
    local selection = Selection(list).driver
    Advance(selection, 0.14)
    for _, id in ipairs({ "frames", "combat", "interface", "style", "general" }) do
        M.SetNavGroupOpen(id, false)
        local arrowDriver = assert(TitleRow(M, id)._msuf2NavArrow._msuf2DisclosureMotion, "rail arrow motion missing")
        assert(arrowDriver:GetScript("OnUpdate") and arrowDriver.duration == 0.14, "rail arrow did not join fold timing")
        local driver = assert(list._msuf2NavFoldMotion)
        assert(driver:GetScript("OnUpdate") and driver.duration == 0.14, id .. ": missing snappy fold")
        Advance(driver, 0.04)
        local moving
        for _, c in ipairs(driver.channels) do if c.velocity ~= 0 then moving = c break end end
        assert(moving, id .. ": fold did not move")
        local value, velocity = moving.value, moving.velocity
        local angle, angularVelocity = arrowDriver.channels[1].value, arrowDriver.channels[1].velocity
        M.SetNavGroupOpen(id, true)
        assert(arrowDriver.channels[1].value == angle and arrowDriver.channels[1].velocity == angularVelocity,
            "rail arrow reversal lost current angular velocity")
        assert(moving.value == value and moving.velocity == velocity, id .. ": reversal snapped position/velocity")
        Advance(driver, 0.14)
        AssertSettled(driver)
        assert(not list._msuf2NavFolding, id .. ": fold retained its live-layout flag")
    end
    M.UpdateNav("opt_fonts")
    Advance(selection, 0.14)
    M.SetNavGroupOpen("style", false)
    Advance(list._msuf2NavFoldMotion, 0.14)
    Fire(M.navButtons.opt_fonts, "OnHide") -- Model native propagation through the real lifecycle hook.
    assert(not selection.art:IsShown(), "collapsed child kept its fill")
    M.SetNavGroupOpen("style", true)
    Advance(list._msuf2NavFoldMotion, 0.14)
    assert(selection.art:IsShown() and selection.channels[2].value == M.navButtons.opt_fonts:GetTop() - list:GetTop(),
        "reopened active group lost its fill")
    -- Selected rows below a fold follow their row without resetting selection velocity.
    M.UpdateNav("opt_fonts")
    Advance(selection, 0.14)
    M.SetNavGroupOpen("frames", false)
    Advance(list._msuf2NavFoldMotion, 0.04)
    assert(math.abs(selection.channels[2].value - (M.navButtons.opt_fonts:GetTop() - list:GetTop())) < 0.001,
        "selected fill detached from the folding layout")
    M.Theme.StopAllMenuAnimations()
    AssertSettled(list._msuf2NavFoldMotion)
    M.SetNavGroupOpen("frames", true)
    parent:_msuf2NavReflow() -- Unrelated layout changes settle rather than replaying a fold.
    AssertSettled(list._msuf2NavFoldMotion)
    for _, key in ipairs({ "reduceMotion", "reducedMotion" }) do
        M.SetNavGroupOpen("frames", false)
        Advance(list._msuf2NavFoldMotion, 0.14)
        world.env.MSUF_DB.general[key] = true
        M.SetNavGroupOpen("frames", false)
        assert(not M.navButtons.uf_player:IsShown(), "reduced motion retained a closing row")
        AssertSettled(list._msuf2NavFoldMotion)
        M.SetNavGroupOpen("frames", true)
        assert(M.navButtons.uf_player:IsMouseEnabled() and M.navButtons.uf_player:GetAlpha() == 1,
            "reduced-motion reopen retained disabled hit testing or faded alpha")
        world.env.MSUF_DB.general[key] = nil
    end
    M.UpdateNav("home")
end

local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted)
end
local function SelectionVisibility(owner, buttons, shown)
    -- Model native parent visibility propagation; shared stubs only store local visibility.
    owner:SetShown(shown)
    local selection = Selection(owner)
    for _, button in ipairs(buttons) do
        button:SetShown(shown)
        Fire(button, shown and "OnShow" or "OnHide")
    end
    if not shown and selection.driver then Fire(selection.driver, "OnHide") end
    Fire(owner, shown and "OnShow" or "OnHide")
end
local function SecondaryPageMotion(world, M, parent)
    local lookup = Upvalue(M.BuildSecondaryPageNav, "SECONDARY_NAV_BY_KEY")
    assert(next(lookup) == nil, "secondary navigation unexpectedly enabled in the product")
    local oldSelect, oldMetrics = M.SelectPage, M.GetContentMetrics
    M.GetContentMetrics = function() return 760, 560 end
    local group = { title = "Tabs", tabs = {
        { key = "motion_a", label = "Name", width = 72 }, { key = "motion_b", label = "HP Text", width = 96 } } }
    lookup.motion_a, lookup.motion_b = group, group
    for _, mode in ipairs({ "tabs", "rail", "narrow" }) do
        group.mode = mode == "tabs" and "tabs" or "rail"
        local cached, current = {}, nil
        local function Navigate(key)
            if current then SelectionVisibility(current, current.buttons, false) end
            local owner = cached[key]
            if not owner then
                local wrapper = world.env.CreateFrame("Frame", nil, parent)
                local width = mode == "narrow" and 500 or 720
                local ctx = { wrapper = wrapper, width = width, fullWidth = width }
                M.BuildSecondaryPageNav(ctx, key)
                owner = assert(ctx._msuf2SecondaryNav)
                Rect(owner, 100, 500)
                for _, button in ipairs(owner.buttons) do
                    local point = assert(Last(button, "TOPLEFT"))
                    Rect(button, 100 + point.x, 500 + point.y)
                end
                cached[key] = owner
            end
            current = owner
            SelectionVisibility(owner, owner.buttons, true)
        end
        M.SelectPage = Navigate
        Navigate("motion_a")
        local first = current
        local initial = assert(Selection(first).driver)
        AssertSettled(initial)
        local channel = mode == "rail" and 2 or 1
        local start = initial.channels[channel].value
        Fire(first.buttons[2], "OnClick")
        local destination = assert(Selection(current).driver)
        assert(current ~= first and destination.channels[channel].value == start
            and destination:GetScript("OnUpdate"), "secondary page rebuild lost moving selection")
        assert(destination.duration == (mode == "rail" and 0.14 or 0.16), "secondary mode timing mismatch")
        Advance(destination, 0.04)
        local c = destination.channels[channel]
        local position, velocity = c.value, c.velocity
        Fire(current.buttons[1], "OnClick")
        assert(current == first and initial.channels[channel].value == position
            and initial.channels[channel].velocity == velocity, "cached secondary page lost interruption state")
        Advance(initial, 0.16)
        AssertSettled(initial)
        assert(initial.channels[channel].value == start, "secondary selection settled at the wrong tab")
        assert(initial.art:GetWidth() == first.buttons[1]:GetWidth()
            and initial.art:GetHeight() == first.buttons[1]:GetHeight(), "secondary fill is not the whole button")
        SelectionVisibility(current, current.buttons, false)
    end
    lookup.motion_a, lookup.motion_b = nil, nil
    M.SelectPage, M.GetContentMetrics = oldSelect, oldMetrics
end
local function PaletteMotion(world, M, parent, surfaces)
    world.env.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    world.env.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage" }
    local picker = Upvalue(M.Widgets.OpenColorContextPicker, "Picker")
    local panel = world.env.CreateFrame("Frame", nil, parent)
    picker.BuildAdvancedCard(panel)
    picker.DefineLayout(panel)
    picker.DefinePaletteRefresh(panel)
    local card, buttons = panel.advancedCard, panel.paletteTabs
    Rect(card, 100, 500)
    for _, button in ipairs(buttons) do
        local point = assert(Last(button, "TOPLEFT"), "palette has no constructor anchor")
        Rect(button, 100 + point.x, 500 + point.y)
    end
    -- Test the real SetAdvanced lifecycle; only native layout/visibility is supplied here.
    panel.Layout = function(self) SelectionVisibility(card, buttons, self.advanced) end
    panel.SetContextListShown = function() end
    panel.Apply = function() error("changing palette applied a color") end
    local oldWindowControls = M.RefreshWindowControls
    M.RefreshWindowControls = function() end
    panel.paletteTab, panel._palettesDirty = "quick", true
    panel:SetAdvanced(true)
    local driver = assert(Selection(card).driver)
    AssertSettled(driver)
    assert(driver.duration == 0.16 and driver.rate == 65, "palette does not use the softer top-tab profile")
    assert(driver.art:GetWidth() == 78 and driver.art:GetHeight() == 20, "palette selection is only a stripe")
    local start = driver.channels[1].value
    Fire(buttons[4], "OnClick")
    assert(panel.paletteTab == "saved" and driver.channels[1].value == start, "palette click jumped or lost its model")
    Advance(driver, 0.04)
    local position, velocity = driver.channels[1].value, driver.channels[1].velocity
    Fire(buttons[2], "OnClick")
    assert(driver.channels[1].value == position and driver.channels[1].velocity == velocity,
        "palette reversal reset position or velocity")
    Advance(driver, 0.16)
    AssertSettled(driver)
    if surfaces then
        assert(surfaces[driver.art].active and not surfaces[buttons[2]].active,
            "Suite palette left selected fill on the stationary button")
        assert(surfaces[driver.art].spec.useControlShape, "Suite palette lost the configured control shape")
        assert(surfaces[driver.art].spec.activeRole == "buttonPrimary", "Suite palette selected fill uses idle material")
    end
    local frames = #world.widgets.frames
    for i = 1, 20 do Fire(buttons[i % 4 + 1], "OnClick"); Advance(driver, 0.02) end
    assert(#world.widgets.frames == frames, "warm palette clicks allocated frames")
    Fire(buttons[4], "OnClick")
    Advance(driver, 0.03)
    panel:SetAdvanced(false)
    AssertSettled(driver)
    -- Open() resets the picker model to Quick. Refresh it while the card is hidden,
    -- before the native OnShow seeds the visual, so no stale Saved-to-Quick slide plays.
    panel.paletteTab, panel._palettesDirty = "quick", true
    panel:SetAdvanced(true)
    AssertSettled(driver)
    assert(driver.channels[1].value == start and buttons[1]._msuf2MotionSelected,
        "reopened palette replayed the old session selection")
    Fire(buttons[3], "OnClick")
    Advance(driver, 0.16)
    panel:SetAdvanced(false)
    panel:SetAdvanced(true)
    AssertSettled(driver)
    assert(panel.paletteTab == "recent" and buttons[3]._msuf2MotionSelected,
        "Back/Advanced lost the current session palette")
    panel:SetAdvanced(false)
    M.RefreshWindowControls = oldWindowControls
end

local function RealScopePageMotion()
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local mw = MenuWorld.Open(root, "Mainline", { open = false })
    local M, W = mw.M, mw.M.Widgets
    -- Real InvalidatePage hides the wrapper. Model inherited visibility so the
    -- outgoing bar cannot consume the incoming page's carried selection.
    mw.world.widgets.Methods.IsVisible = function(self)
        local frame = self
        while frame do
            if not frame:IsShown() then return false end
            frame = frame:GetParent()
        end
        return true
    end
    local build, bars = W.ScopeOverrideBar, {}
    W.ScopeOverrideBar = function(ctx, section, opts)
        local bar = build(ctx, section, opts)
        Rect(bar, 100, 500)
        for _, button in ipairs(bar.buttons) do
            local point = assert(Last(button, "LEFT"))
            Rect(button, 100 + point.x, 500 + point.y + button:GetHeight() / 2)
        end
        if ctx.key == "opt_fonts" or ctx.key == "opt_bars" then bars[ctx.key] = bar end
        return bar
    end
    local function ShowBar(key)
        local bar = assert(bars[key], "real scope builder not reached: " .. key)
        for _, button in ipairs(bar.buttons) do Fire(button, "OnShow") end
        Fire(bar, "OnShow")
        return bar, assert(Selection(bar).driver)
    end
    local function Find(bar, value)
        for _, button in ipairs(bar.buttons) do if button._msuf2Value == value then return button end end
        error("missing real scope " .. value)
    end
    for _, key in ipairs({ "opt_fonts", "opt_bars" }) do
        assert(M.Open(key) ~= false, "scope page did not open")
        mw:RunTimers()
        local old, driver = ShowBar(key)
        local original = old:GetValue()
        local nextValue = original == "player" and "target" or "player"
        local start = {}
        for i, c in ipairs(driver.channels) do start[i] = c.value end
        Find(old, nextValue):Click()
        mw:RunTimers()
        local current, moved = ShowBar(key)
        assert((current ~= old) == (key == "opt_fonts") and current:GetValue() == nextValue,
            "scope lost its real rebuild/refresh behavior: " .. key)
        assert(moved:GetScript("OnUpdate"), "real scope rebuild snapped its selection: " .. key)
        for i, c in ipairs(moved.channels) do assert(c.value == start[i], "scope rebuild lost carried geometry: " .. key) end
        Advance(moved, 0.04)
        local positions, velocities = {}, {}
        for i, c in ipairs(moved.channels) do positions[i], velocities[i] = c.value, c.velocity end
        Find(current, original):Click()
        mw:RunTimers()
        local restored, returned = ShowBar(key)
        assert((restored ~= current) == (key == "opt_fonts") and restored:GetValue() == original,
            "scope reversal lost its page state")
        for i, c in ipairs(returned.channels) do
            assert(c.value == positions[i] and c.velocity == velocities[i], "real scope reversal reset motion: " .. key)
        end
        Advance(returned, 0.16)
        AssertSettled(returned)
        for i, c in ipairs(returned.channels) do assert(c.value == start[i], "real scope reversal ended at wrong position") end
    end
    W.ScopeOverrideBar = build
    M.frame:Hide()
end

local function RailFlavor(flavor)
    local world, env, M, tip = Boot(flavor)
    local suite = { dimOk = false, dimReason = "Disabled in Blizzard's AddOns list: MSUF_Suite_Nameplates", hide = true }
    InsertAfterTitle(M.navItems, "combat", { key = "smoke_dimmed", label = "Nameplates", group = "combat",
        availability = function() return suite.dimOk, suite.dimReason end })
    InsertAfterTitle(M.navItems, "interface", { key = "smoke_hidden", label = "Action Bars", group = "interface",
        availability = function() return false, "Install MSUF_Suite_ActionBars to use this module", suite.hide end })
    M.navPrimaryForKey.smoke_dimmed, M.navPrimaryForKey.smoke_hidden = "smoke_dimmed", "smoke_hidden"

    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(200, 600)
    M.BuildNavRail(parent)
    local buttons = M.navButtons

    NavigationMotion(world, M, buttons.smoke_dimmed, TitleRow(M, "frames"))
    NavigationSelection(M, parent)
    TabScopeMotion(world, M, parent)
    SecondaryPageMotion(world, M, parent)
    PaletteMotion(world, M, parent)
    suite.hide = false
    M.RefreshNavAvailability()
    FoldMotion(world, M, parent)
    suite.hide = true
    M.RefreshNavAvailability()

    -- Real root and child rows use the HD atlas with a readable label gap.
    for _, key in ipairs({ "home", "uf_player", "opt_fonts", "opt_colors", "classpower", "gameplay" }) do
        local button = assert(buttons[key])
        local icon, label = assert(button._msuf2NavIcon), button._msuf2Label
        assert(icon:GetTexture() == M.Theme.media.navIcons and not icon._msuf2GlyphParts,
            flavor .. ": " .. key .. " bypasses the shared HD artwork")
        assert(icon:GetWidth() == 20 and icon:GetHeight() == 20, "navigation icon size")
        assert(Last(label, "LEFT").x - Last(icon, "LEFT").x - icon:GetWidth() >= 8,
            flavor .. ": " .. key .. " text overlaps its icon")
        local _, size, flags = label:GetFont()
        assert(size == 14 and flags == "", flavor .. ": " .. key .. " navigation font: " .. tostring(size) .. "/" .. tostring(flags) .. "/" .. tostring(label._msuf2FontRole))
        assert(label.shadowColor[4] == 0 and label.shadowOffset[1] == 0 and label.shadowOffset[2] == 0,
            "navigation label has a blurred shadow")
        local count = #button.regions
        M.Theme.AttachNavIcon(button, key, button._msuf2NavIconIsChild, true)
        assert(#button.regions == count and button._msuf2NavIcon == icon, "refresh allocates another icon")
        M.Theme.SetNavIconVisible(button, false)
        assert(not icon:IsShown() and Last(label, "LEFT").x == 12, "hidden icons leave a blank column")
        M.Theme.SetNavIconVisible(button, true)
        assert(icon:IsShown() and Last(label, "LEFT").x == 38, "restored icons lost label spacing")
    end

    -- Dimmed: reason tooltip plus a non-color "Off" cue that the label stops short of.
    local dimmed = assert(buttons.smoke_dimmed, flavor .. ": dimmed row missing")
    assert(dimmed:IsShown() and dimmed:GetAlpha() == 0.4, flavor .. ": switched-off module is not dimmed")
    local badge = assert(dimmed._msuf2NavOffBadge, flavor .. ": dimmed row has no Off badge")
    assert(badge:IsShown() and badge:GetText() == M.Tr("Off"), flavor .. ": Off badge not shown")
    assert(Last(dimmed._msuf2Label, "RIGHT").x < -8, flavor .. ": label runs under the Off badge")
    M.RefreshNavIconVisibility()
    assert(Last(dimmed._msuf2Label, "RIGHT").x < -8, flavor .. ": icon relayout put the label under the Off badge")
    local tipTitle, tipBody = Hover(dimmed, tip)
    assert(tipTitle == "Nameplates" and tipBody == suite.dimReason,
        flavor .. ": dimmed row tooltip lost its reason: " .. tostring(tipTitle) .. " / " .. tostring(tipBody))
    suite.dimReason = nil
    M.RefreshNavAvailability()
    assert(select(2, Hover(dimmed, tip)) == "Unavailable", flavor .. ": reasonless off row has no tooltip body")
    suite.dimOk = true
    M.RefreshNavAvailability()
    assert(dimmed:GetAlpha() == 1 and not badge:IsShown(), flavor .. ": available module still dimmed")
    assert(Last(dimmed._msuf2Label, "RIGHT").x == -8, flavor .. ": label inset kept after the module came back")
    assert(Hover(dimmed, tip) == nil, flavor .. ": available row still explains itself")
    M.RefreshNavIconVisibility()
    assert(dimmed:GetAlpha() == 1, flavor .. ": icon refresh changed an available row")

    -- Changing Frame Basics (including undo/profile refresh) repaints the
    -- rail in the same refresh pass, without selecting another page.
    local refreshEntry = { refreshers = { function() suite.dimOk = false end } }
    M.RunEntryRefreshers(refreshEntry, { force = true })
    assert(dimmed:GetAlpha() == 0.4 and badge:IsShown(), flavor .. ": page refresh left the rail active")
    refreshEntry.refreshers[1] = function() suite.dimOk = true end
    M.RunEntryRefreshers(refreshEntry, { force = true })
    assert(dimmed:GetAlpha() == 1 and not badge:IsShown(), flavor .. ": page refresh left the rail grey")

    M.UpdateNav("smoke_dimmed")
    local selectedFill = assert(Selection(parent._msuf2NavList).driver).art
    suite.dimOk = false
    M.RefreshNavAvailability()
    assert(selectedFill:GetAlpha() == 0.4, "selected fill missed availability dimming")
    suite.dimOk = true
    M.RefreshNavAvailability()
    assert(selectedFill:GetAlpha() == 1, "selected fill stayed dim after enabling")
    M.UpdateNav("home")

    -- A clipped translated/custom-font label remains fully readable on hover.
    local oldTruncated = world.widgets.Methods.IsTruncated
    world.widgets.Methods.IsTruncated = function() return true end
    assert(Hover(buttons.home, tip) == "Dashboard", "clipped navigation label has no full title")
    world.widgets.Methods.IsTruncated = function() return false end
    assert(Hover(buttons.home, tip) == nil, "fitting label adds a redundant tooltip")
    world.widgets.Methods.IsTruncated = oldTruncated

    -- Hidden: out of the rail, its now-empty group title too, and the gap closes.
    local hidden = assert(buttons.smoke_hidden, flavor .. ": hidden row must stay in M.navButtons")
    local interfaceRow, styleRow = TitleRow(M, "interface"), TitleRow(M, "style")
    assert(not hidden:IsShown(), flavor .. ": row of a missing addon is shown")
    assert(not interfaceRow:IsShown(), flavor .. ": group title without visible pages is shown")
    local styleHiddenY = Y(styleRow)
    suite.hide = false
    assert(M.RefreshNavAvailability() == true, flavor .. ": unhiding a row did not relayout")
    assert(hidden:IsShown() and interfaceRow:IsShown(), flavor .. ": unhidden row or its title missing")
    assert(styleHiddenY - Y(styleRow) == 56, flavor .. ": hidden group left a gap of "
        .. tostring(56 - (styleHiddenY - Y(styleRow))))
    suite.hide = true
    M.RefreshNavAvailability()
    assert(Y(styleRow) == styleHiddenY and not interfaceRow:IsShown(), flavor .. ": re-hiding did not close the gap")

    -- Navigation into and titles for a hidden page still work.
    M.frame = { title = parent:CreateFontString() }
    M.UpdateNav("home")
    M.UpdateNav("smoke_hidden")
    M.SetTitle("smoke_hidden")
    local hiddenTitle = world.client.isForever and M.Tr("MSUF (Forever Version)") or "Interface > Action Bars"
    assert(M.frame.title:GetText() == hiddenTitle, flavor .. ": hidden page title: " .. tostring(M.frame.title:GetText()))
    assert(not hidden:IsShown(), flavor .. ": navigating to a hidden page showed its row")
    M.UpdateNav("home")

    -- Folding: title click, caret and tooltip cue, persisted per character.
    local framesRow, combatRow = TitleRow(M, "frames"), TitleRow(M, "combat")
    local combatOpenY = Y(combatRow)
    local listScroll = parent._msuf2NavListScroll
    local list = parent._msuf2NavList
    listScroll:SetHeight(100)
    parent:_msuf2NavReflow()
    local openHeight = list:GetHeight()
    assert(Hover(framesRow, tip) == "Collapse", flavor .. ": open group title tooltip")
    assert(framesRow._msuf2NavArrow.rotation == math.pi * 0.5, flavor .. ": open caret")
    assert(framesRow:GetScript("OnClick"), flavor .. ": group title is not clickable")(framesRow)
    assert(M.navHeaderState.frames == false, flavor .. ": title click did not fold the group")
    local fold = assert(list._msuf2NavFoldMotion, "fold driver missing")
    assert(fold.duration == 0.14 and fold:GetScript("OnUpdate"), "fold lost its short animated transition")
    assert(Y(combatRow) == combatOpenY and buttons.uf_player:IsShown(), "fold snapped at click time")
    Advance(fold, 0.14)
    AssertSettled(fold)
    local charKey = env.MSUF_GetCharKey()
    assert(env.MSUF_GlobalDB.char[charKey].menu2State.navHeaderState.frames == false,
        flavor .. ": folded group is not persisted")
    for _, key in ipairs({ "uf_player", "gf_layout", "opt_bars", "opt_castbar", "auras3_styling", "classpower" }) do
        assert(not buttons[key]:IsShown(), flavor .. ": " .. key .. " shown in a folded group")
    end
    assert(framesRow:IsShown(), flavor .. ": folded group lost its title")
    assert(framesRow._msuf2NavArrow.rotation == 0, flavor .. ": folded caret")
    assert(Hover(framesRow, tip) == "Expand", flavor .. ": folded group title tooltip")
    assert(combatOpenY - Y(combatRow) == -6 * 28, flavor .. ": folding did not pull the next group up")
    assert(list:GetHeight() == openHeight - 6 * 28, flavor .. ": rail height ignores the folded group")

    -- The Undo/Redo block stays right below the last visible row.
    local generalRow = TitleRow(M, "general")
    local history = M.historyControls
    M.SetNavGroupOpen("general", false)
    Advance(fold, 0.14)
    assert(history:IsShown() and Y(history) == Y(generalRow) - 22,
        flavor .. ": history block did not follow the folded General group")
    M.SetNavGroupOpen("general", true)
    Advance(fold, 0.14)
    assert(Y(history) == Y(buttons.profiles) - 30, flavor .. ": history block left profiles")

    -- Landing inside a folded group opens it; the lookup goes through the rail
    -- key, so a workspace tab (uf_target) opens Frames too.
    M.UpdateNav("uf_target")
    assert(M.navHeaderState.frames == true and buttons.uf_player:IsShown(),
        flavor .. ": navigation into a folded group did not reveal the active row")
    assert(buttons.uf_player._msuf2Active == true, flavor .. ": workspace tab did not mark its rail row")
    assert(buttons.uf_player:IsMouseEnabled() and buttons.uf_player:GetAlpha() == 1, "automatic unfold left an inert faded row")
    M.SetNavGroupOpen("frames", false)
    M.UpdateNav("uf_target")
    assert(M.navHeaderState.frames == false, flavor .. ": rebuilding the same page reopened a folded group")
    M.UpdateNav("opt_fonts")
    M.UpdateNav("opt_castbar")
    assert(M.navHeaderState.frames == true, flavor .. ": selecting a page in a folded group kept it folded")

    -- Window title: the breadcrumb the rail and search use.
    local expected = {
        opt_castbar = "Frames > Cast Bars",
        uf_target = "Frames > Unitframes > Target",
        gf_bars = "Frames > Party/Raid Frames > Dispel Overlay",
        auras3_styling = "Frames > Auras",
        opt_fonts = "Style > Fonts",
        home = "Dashboard",
    }
    local forever = M.Tr("MSUF (Forever Version)")
    for key, title in pairs(expected) do
        M.SetTitle(key)
        local want = world.client.isForever and forever or title
        assert(M.frame.title:GetText() == want,
            flavor .. ": " .. key .. " title " .. tostring(M.frame.title:GetText()) .. ", want " .. want)
    end
    M.SetTitle("opt_castbar")
    assert(world.client.isForever or M.frame.title:GetText():find(" > " .. buttons.opt_castbar:GetText(), 1, true),
        flavor .. ": title and rail label disagree")
    -- Minimizing copies the current title (MSUF_Menu2_Window.lua); a page change
    -- behind the bar has to carry over.
    M.minimizedBar = { title = parent:CreateFontString() }
    M.minimizedBar.title:SetText(M.frame.title:GetText())
    M.frame._msuf2Minimized = true
    M.SetTitle("gameplay")
    assert(M.minimizedBar.title:GetText() == M.frame.title:GetText()
        and (world.client.isForever or M.frame.title:GetText() == "General > Gameplay"),
        flavor .. ": minimized bar title did not follow the page")
    return world
end

local function LocalizedTitle()
    local world, env, M = Boot("Mainline", "deDE")
    -- The client runs this on ADDON_LOADED; the offline world never fires it.
    assert(world.core.FinalizeLocale() == "deDE", "deDE: language pack not selected")
    -- A theme font string translates on SetText; the joined title must not be
    -- looked up (and logged as missing) as a locale key of its own.
    M.frame = { title = M.Theme.Font(env.CreateFrame("Frame"), "GameFontDisableSmall", "MSUF") }
    M.SetTitle("uf_target")
    local want = M.Tr("Frames") .. " > " .. M.Tr("Unitframes") .. " > " .. M.Tr("Target")
    assert(M.Tr("Target") ~= "Target", "deDE: expected a translated Target label")
    assert(M.frame.title:GetText() == want, "deDE: breadcrumb title not translated per part: "
        .. tostring(M.frame.title:GetText()))
    assert(not (M.missingLocaleKeys or {})[want], "deDE: the joined title was translated as one locale key")
    InsertAfterTitle(M.navItems, "combat", { key = "smoke_dimmed", label = "Nameplates", group = "combat",
        availability = function() return false end })
    M.BuildNavRail(env.CreateFrame("Frame", nil, env.UIParent))
    local badge = assert(M.navButtons.smoke_dimmed._msuf2NavOffBadge, "deDE: dimmed row has no Off badge")
    assert(M.Tr("Off") ~= "Off" and badge:GetText() == M.Tr("Off"), "deDE: Off badge not translated: " .. tostring(badge:GetText()))
end

local function SkinnedSelection()
    local world, env, M = Boot("Mainline")
    local skin, enabled, surfaces = assert(world.core.MenuSkin), true, {}
    -- Exercise the real core bridge; this fake implements the Suite public API
    -- so selection semantics and provider repaint ownership are observable.
    local skinRed = 0.3
    local client = {}
    function client:SkinButton(button, spec)
        surfaces[button] = { active = spec.active, spec = spec }
        return true, "applied"
    end
    function client:SetActive(button, active) surfaces[button].active = active end
    function client:SkinFrame() return false end
    function client:ReleaseAll() for _, surface in pairs(surfaces) do surface.released = true end end
    local api = {
        RegisterAddon = function() return client end,
        IsEnabled = function() return enabled end,
        GetAppearanceSnapshot = function() return {} end,
        GetColor = function() return skinRed, 0.5, 0.8, 1 end,
        OnAppearanceChanged = function() end,
    }
    env.MapkoSkin = { GetAPI = function(major, minor) assert(major == 2 and minor == 1); return api end }
    local connected = false
    for _, frame in ipairs(world.widgets.frames) do
        local event = frame:GetScript("OnEvent")
        if event and debug.getinfo(event, "S").source:find("MSUF_MapkoSkin.lua", 1, true) then
            event(frame, "PLAYER_LOGIN")
            connected = true
            break
        end
    end
    assert(connected and skin.IsActive(), "Suite API bridge did not connect")
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(300, 200)
    Rect(parent, 100, 500)
    local segment = M.Widgets.Segment(parent, "Skin tabs", { { value = "name", text = "Name" },
        { value = "hp", text = "HP Text" } }, 280)
    Rect(segment, 100, 500)
    for i, button in ipairs(segment.buttons) do Rect(button, 100 + (i - 1) * 140, 474) end
    segment:SetValue("name")
    local driver = assert(Selection(segment).driver)
    local name, hp, surface = segment.buttons[1], segment.buttons[2], driver.art
    assert(name._msuf2Active and surfaces[name].active == false and surfaces[surface].active == true,
        "Suite selected fill is still painted on the stationary button")
    assert(surfaces[surface].spec.useControlShape and surfaces[surface].spec.ownedArt,
        "moving fill lost Suite shape ownership")
    assert(surfaces[surface].spec.activeRole == "buttonPrimary"
        and surfaces[surface].spec.role == "button" and surfaces[name].spec.role == "button",
        "Suite selected fill uses idle material")
    -- These explicit semantic roles retain their authored material; only the
    -- ordinary selected button adopts the provider's primary active material.
    for _, role in ipairs({ "danger", "success", "primary" }) do
        local action = M.Widgets.RoleButton(parent, role, role, 80, 22)
        action:SetActive(true)
        local spec = surfaces[action].spec
        assert(spec.role == "button" .. role:gsub("^%l", string.upper) and spec.activeRole == spec.role,
            "selection material changed a semantic action role")
    end
    local idle = M.Theme.Button(parent, "Action", 80, 22)
    assert(not surfaces[idle].active and surfaces[idle].spec.role == "button", "idle action adopted selected paint")
    local nav = M.Theme.Button(parent, "Navigation", 120, 24)
    nav._msuf2NavItem = true
    nav:SetActive(true)
    assert(surfaces[nav].spec.role == "navigation" and surfaces[nav].spec.activeRole == "button",
        "Suite sidebar lost its deliberate dark selected material")
    assert(not surface._msuf2SkinnedSelectionCue, "rectangular overlay masks the Suite shape")
    segment:SetValue("hp")
    Advance(driver, 0.04)
    local position, velocity = driver.channels[1].value, driver.channels[1].velocity
    skin.Refresh(nil, "appearance")
    assert(hp._msuf2Active and not surfaces[hp].active and surfaces[surface].active,
        "Suite repaint restored duplicate stationary selection")
    assert(driver.channels[1].value == position and driver.channels[1].velocity == velocity,
        "skin repaint restarted selection motion")
    PaletteMotion(world, M, parent, surfaces)
    local switch = M.Widgets.SwitchAt(parent, "Skin switch", 0, -80)
    switch:SetChecked(true)
    local switchDriver = assert(switch._msuf2SwitchMotion, "skinned switch motion missing")
    local layerOwner = { layerVisibility = {}, layerAvailable = {}, _msuf2SelectedPreviewLayerKey = nil }
    local helpers = M.PreviewHelpers
    local layerOpts = helpers.LayerChipButtonOpts(M.Tr, M.Theme.colors, helpers.PreviewChromePalette(M.Theme), {})
    local layer = helpers.CreateLayerButton(parent, layerOwner, { key = "a", label = "A", color = { 0.2, 0.6, 0.9 } }, 1, 160, layerOpts)
    layerOwner._msuf2SelectedPreviewLayerKey = "a"
    layer:Refresh()
    local layerDriver = assert(layer._msuf2LayerMotion, "skinned layer motion missing")
    Advance(switchDriver, 0.03)
    Advance(layerDriver, 0.03)
    local knob, knobVelocity = switchDriver.channels[1].value, switchDriver.channels[1].velocity
    local fill, fillVelocity = layerDriver.channels[1].value, layerDriver.channels[1].velocity
    skinRed = 0.7
    skin.Refresh(nil, "color")
    assert(switchDriver.channels[1].value == knob and switchDriver.channels[1].velocity == knobVelocity,
        "Suite repaint snapped switch geometry")
    assert(layerDriver.channels[1].value == fill and layerDriver.channels[1].velocity == fillVelocity,
        "Suite repaint snapped layer fill")
    assert(layerDriver.channels[1].target == M.Theme.colors.pillActive[1], "layer target ignores live Suite palette")
    Advance(switchDriver, 0.12)
    Advance(layerDriver, 0.10)
    skinRed = 0.4
    skin.Refresh(nil, "color")
    local settledSwitch = { switch._msuf2SwitchFill:GetVertexColor() }
    local settledLayer = { unpack(layer.bg.colorTexture) }
    M.Theme.StopAllMenuAnimations()
    for i = 1, 4 do
        assert(select(i, switch._msuf2SwitchFill:GetVertexColor()) == settledSwitch[i], "idle Suite switch repaint was undone by StopAll")
        assert(layer.bg.colorTexture[i] == settledLayer[i], "idle Suite layer repaint was undone by StopAll")
    end
    enabled = false
    skin.Refresh(nil, "appearance")
    assert(surfaces[surface].released and surface._msuf2Active, "skin opt-out lost moving native selection")
    Advance(driver, 0.16)
    AssertSettled(driver)
end
local function PresetSelection()
    for _, preset in ipairs({ "classicGlass", "midnight", "midnightDark" }) do
        local world, env, M = Boot("Mainline", nil, preset)
        assert(M.Theme.menuAppearancePreset == preset, "preset fixture did not select " .. preset)
        local parent = env.CreateFrame("Frame", nil, env.UIParent)
        parent:SetSize(300, 100)
        Rect(parent, 0, 100)
        local bar = M.Widgets.Segment(parent, "Skin", { { value = "name", text = "Name" },
            { value = "hp", text = "HP Text" } }, 280)
        Rect(bar, 0, 100)
        for i, button in ipairs(bar.buttons) do Rect(button, (i - 1) * 140, 74) end
        bar:SetValue("name")
        local driver = assert(Selection(bar).driver)
        assert(driver.art._msuf2Fill and driver.art:GetHeight() == bar.buttons[1]:GetHeight(),
            preset .. ": moving fill lost its full skin shape")
        bar:SetValue("hp")
        Advance(driver, 0.16)
        AssertSettled(driver)
        assert(driver.art:GetWidth() == bar.buttons[2]:GetWidth(), preset .. ": wrong selected fill width")
        SecondaryPageMotion(world, M, parent)
        PaletteMotion(world, M, parent)
    end
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do RailFlavor(flavor) end
LocalizedTitle()
RealScopePageMotion()
SkinnedSelection()
PresetSelection()
print("menu2_nav_rail_groups_smoke: ok (5 clients, eased motion lifecycle, off reason, hidden rows, folding, breadcrumb title, skinned selection, secondary/palette lifecycle)")
