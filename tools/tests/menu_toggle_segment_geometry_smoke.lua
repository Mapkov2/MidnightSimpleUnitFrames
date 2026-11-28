-- Real Menu2 controls: idle hover art, native restyle and retained tab geometry.
local root, flavor = assert(arg[1]):gsub("\\", "/"), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    for _,name in ipairs({"SetWidth", "SetSize"}) do
        local set = world.widgets.Methods[name]
        world.widgets.Methods[name] = function(self, ...)
            local width = self:GetWidth()
            set(self, ...)
            if width ~= self:GetWidth() and (self._msuf2ControlKind == "segment" or self.testTabParent) then
                World.FireScript(self, "OnSizeChanged", self:GetWidth(), self:GetHeight())
            end
        end
    end
end })
local M, W, T, env = mw.M, mw.M.Widgets, mw.M.Theme, mw.env
T.ReducedMotionEnabled = function() return true end
assert(T.FontSize("control") == 14 and T.FontSize(T.SETTING_CARD_ROLE or "card") == 14, "settings typography is not 14 units")
local section = env.CreateFrame("Frame", nil, env.UIParent)
section:SetSize(1020, 400)
section._msuf2Width, section.testTabParent = 1020, true
local button = W.ToggleAt(section, "Toggle", 16, -20, 280)
local hover, fill, hit = button._msuf2ToggleRowHover, button._msuf2ToggleHoverFill, button._msuf2LabelHit
assert(not hover:IsShown() and not fill:IsShown(), "idle toggle has visible hover artwork")
World.FireScript(hit, "OnEnter")
assert(hover:IsShown() and fill:IsShown(), "hover feedback missing")
local edge = T.colors.checkActiveEdge
local old = edge[1]
edge[1] = .9123
T.StyleCheckmark(button)
assert(hover:GetVertexColor() == .9123, "same-state restyle retained old hover palette")
edge[1] = old
World.FireScript(hit, "OnLeave")
assert(not hover:IsShown() and not fill:IsShown(), "leave retained hover art")
button:SetChecked(true)
W.SetControlEnabled(button, false)
T.StyleCheckmark(button)
assert(button:GetCheckedTexture():GetAlpha() == .42, "same-state restyle lost disabled check alpha")
W.SetControlShown(button, false)
W.SetControlShown(button, true)
assert(not hover:IsShown(), "visibility gate exposed idle hover art")
World.FireScript(button, "OnShow")
assert(button:GetCheckedTexture():GetAlpha() == .42, "reopen lost disabled check alpha")
W.SetControlEnabled(button, true)
World.FireScript(hit, "OnEnter")
World.FireScript(button, "OnHide")
assert(not hover:IsShown(), "hide retained hover art")
-- Settings controls in the real Menu2 widget graph.
local dropdown = W.Dropdown(section, "Long dropdown field label", {
    { value = "one", text = "A translated selection", icon = 134400 },
    { value = "two", text = "Second selection", color = { .5, .6, .7 } },
}, 180)
W.MoveWidget(dropdown, section, 16, -158, 180, "CENTER")
dropdown:SetValue("one")
local title = dropdown._msuf2Title
local value = dropdown._msuf2Label
assert(dropdown:GetHeight() >= 26, "settings dropdown kept the compact action button height")
assert(value._msuf2FontRole == button._msuf2Label._msuf2FontRole, "dropdown value uses a different font role than its checkbox")
assert(title:GetJustifyH() == "LEFT", "dropdown title did not align left")
local _, parent, _, x, y = dropdown:GetPoint(1)
local _, titleParent, _, titleX, titleY = title:GetPoint(1)
assert(parent == titleParent and x == titleX and y <= titleY - 20,
    "dropdown title and value do not share a left edge with room between them")
local _, _, _, leftPad = value:GetPoint(1)
local _, _, _, rightPad = value:GetPoint(2)
local _, _, _, arrowRight = dropdown._msuf2Chevron:GetPoint(1)
assert(leftPad >= 12 and rightPad < arrowRight - dropdown._msuf2Chevron:GetWidth(),
    "dropdown label crosses the arrow")
assert(y - dropdown:GetHeight() >= -210, "taller dropdown no longer fits the reserved row")
-- Restrict the popup to a small owner window. The body should scroll
-- when only one full choice fits and the preferred width is too wide.
dropdown._msuf2DropdownClampFrame = {
    GetLeft = function() return 0 end, GetRight = function() return 220 end,
    GetBottom = function() return 0 end, GetTop = function() return 120 end,
}
dropdown._msuf2DropdownPreferredWidth = 400
dropdown.GetLeft, dropdown.GetRight = function() return 16 end, function() return 196 end
dropdown.GetBottom, dropdown.GetTop = function() return 55 end, function() return 81 end
dropdown:Click()
local function named(name)
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame:GetName() == name then return frame end
    end
end
local popup = assert(named("MSUF2NativeDropdownList"), "settings dropdown did not open")
assert(popup:IsShown(), "settings dropdown popup not visible")
assert(popup:GetWidth() <= 204 and popup:GetHeight() <= 45,
    "dropdown exceeded the space available inside its owner window")
local scroll = assert(named("MSUF2NativeDropdownScroll"))
local firstChoice = select(1, scroll:GetScrollChild():GetChildren())
assert(firstChoice:GetHeight() >= 26 and firstChoice._msuf2Text._msuf2FontRole == button._msuf2Label._msuf2FontRole,
    "dropdown popup selection uses a different font role or row height")
local _, _, _, choiceStart = firstChoice._msuf2Text:GetPoint(1)
local _, _, _, iconStart = firstChoice._msuf2Icon:GetPoint(1)
assert(choiceStart > iconStart + firstChoice._msuf2Icon:GetWidth(), "popup choice text overlaps its icon")
W.CloseDropdown({ immediate = true })
-- At smaller widths the existing compact slider arrangement keeps the edit
-- within the row and restores both steppers when the layout has space.
local numeric = W.Slider(section, "Höhe der Ressourcenleiste", -1000, 1000, 0.25, 260)
local numberBox, minus, plus = numeric.editBox, numeric.minusButton, numeric.plusButton
assert(numberBox._msuf2FontRole == button._msuf2Label._msuf2FontRole,
    "numeric value uses a different font role than checkbox text")
assert(numberBox:GetHeight() == dropdown:GetHeight() and minus:GetHeight() == dropdown:GetHeight()
    and plus:GetHeight() == dropdown:GetHeight(), "slider numeric controls do not match the settings dropdown")
assert(numberBox:GetWidth() >= 64, "default number field is too narrow for signed decimals")
for _, width in ipairs({ 260, 204, 156, 96, 260 }) do
    W.MoveWidget(numeric, section, 16, -16, width)
    local stepsShown = width >= 204
    assert(minus:IsShown() == stepsShown and plus:IsShown() == stepsShown, "slider lost its compact stepper layout")
    assert(numberBox:IsShown() == (width ~= 96), "numeric field does not match the compact layout")
    local _, _, _, _, trackY = numeric:GetPoint()
    local _, _, _, _, labelY = numeric._msuf2Title:GetPoint()
    assert(trackY - numeric:GetHeight() >= labelY - 48, "numeric row exceeds its space in a settings grid")
    if numberBox:IsShown() then
        local _, _, _, editGap = numberBox:GetPoint()
        local valueRight = numeric:GetWidth() + editGap + numberBox:GetWidth()
        if stepsShown then
            local _, _, _, minusGap = minus:GetPoint()
            local _, _, _, plusGap = plus:GetPoint()
            valueRight = valueRight + minusGap + minus:GetWidth() + plusGap + plus:GetWidth()
        end
        assert(valueRight <= width + 0.5, "number field or stepper exceeds narrow column width")
    end
end
local previousShift, previousControl = env.IsShiftKeyDown, env.IsControlKeyDown
local function NoModifier() return false end
env.IsShiftKeyDown, env.IsControlKeyDown = NoModifier, NoModifier
numeric:SetValue(-12.25)
plus:Click()
assert(numeric:GetValue() == -12, "plus lost the declared fractional step")
minus:Click()
assert(numeric:GetValue() == -12.25, "minus lost the declared fractional step")
env.IsShiftKeyDown, env.IsControlKeyDown = previousShift, previousControl
local values = {{value="a",text="A"},{value="b",text="B"},{value="c",text="C"},{value="d",text="D"}}
local ctx = {key="test",refreshers={}}
local settingsScale = 1.15
local grid = W.SettingsRows(ctx, section, { width = 560, columns = 2, rows = {
    { kind = "toggle", id = "first", label = "Wide label", get = function() return false end, set = function() end },
    { kind = "toggle", id = "second", label = "Second", get = function() return false end, set = function() end },
} })
local firstToggle, secondToggle = grid.controls.first, grid.controls.second
local _, _, _, firstX = firstToggle:GetPoint()
local _, _, _, secondX = secondToggle:GetPoint()
local labelEnd = firstX + firstToggle:GetWidth() + 8 + firstToggle._msuf2Label:GetWidth()
local hitEnd = firstX - 4 + firstToggle._msuf2LabelHit:GetWidth()
assert(labelEnd * settingsScale < secondX * settingsScale and hitEnd * settingsScale < secondX * settingsScale,
    "settings row toggle overlaps the next column at 115 percent")
-- A translated setting can span both columns and start a separate group.
local aligned = W.SettingsRows(ctx, section, { width = 560, y = -10, columns = 2, rows = {
    { kind = "toggle", id = "firstGroup", label = "First group", get = function() return false end, set = function() end },
    { kind = "toggle", id = "secondColumn", label = "Second column", get = function() return false end, set = function() end },
    { kind = "toggle", id = "wide", label = string.rep("Wide label ", 5), startsGroup = true,
        get = function() return false end, set = function() end },
} })
local wide = aligned.controls.wide
local _, _, _, firstGroupX, firstGroupY = aligned.controls.firstGroup:GetPoint()
local _, _, _, wideX, wideY = wide:GetPoint()
assert(wideX == firstGroupX and firstGroupY - wideY == 40, "group boundary did not add room after the preceding row")
assert(wide._msuf2Label:GetWidth() >= 520, "long setting caption did not make the row full-width")
local choiceGrid = W.SettingsRows(ctx, section, { width = 560, columns = 2, rows = {
    { kind = "dropdown", id = "choice", label = "Position",
        values = { { value = 1, text = "Short value" }, { value = 2, text = string.rep("Long choice ", 5) } },
        get = function() return 1 end, set = function() end },
} })
assert(choiceGrid.controls.choice:GetWidth() >= 550, "dropdown width ignores longer translated choices")
local wrappedCaption = string.rep("Wrapped setting caption ", 3)
local stubMethods = mw.world.widgets.Methods
local originalHeight = stubMethods.GetStringHeight
stubMethods.GetStringHeight = function(self)
    if self:GetText() == wrappedCaption then return 38 end
    return originalHeight(self)
end
local wrappedGrid = W.SettingsRows(ctx, section, { width = 240, y = -10, columns = 1, rows = {
    { kind = "slider", id = "wrappedCaption", label = wrappedCaption, min = 1, max = 30, default = 10,
        get = function() return 10 end, set = function() end },
} })
stubMethods.GetStringHeight = originalHeight
local wrappedField = wrappedGrid.controls.wrappedCaption
local _, _, _, _, titleY = wrappedField._msuf2Title:GetPoint()
local _, _, _, _, fieldY = wrappedField:GetPoint()
assert(titleY - fieldY == 44, "wrapped field title overlaps the numeric controls")
assert(wrappedGrid.bottomY == -84, "the next settings row did not move below the wrapped title")
local tabs = W.SegmentTabs(ctx, section, {label="",values=values,width=988,x=16,y=12,defaultTab="a"})
local buttons = tabs.buttons
for _,width in ipairs({600,900,500,1020}) do
    section._msuf2Width=width
    section:SetWidth(width)
    W.MoveWidget(tabs,section,16,12,988)
    assert(tabs:GetWidth()<=width-32, "tabs exceed their parent")
    for i,choice in ipairs(buttons) do
        local _,relative,_,x=choice:GetPoint()
        assert(relative==tabs and x+choice:GetWidth()<=tabs:GetWidth(),"choice exceeds resized tabs")
    end
    assert(tabs.buttons==buttons and tabs:GetValue()=="a", "resize replaced choices or changed selection")
end
-- A caller's preferred width is a minimum. A translated caption and its
-- padding must fit inside the selected outline, even when the choices wrap.
local long = "Cleanse Color Overlay"
local captions = { { value = "a", text = "Layout", width = 64 },
    { value = "b", text = long, width = 106 }, { value = "c", text = "Blizzard player auras", width = 94 } }
local scopeOptions = { values = captions, width = 318, label = "", labelWidth = 0, startX = 14, centerY = -80 }
local scope = W.ScopeOverrideBar(ctx, section, scopeOptions)
local metrics = W.MeasureScopeOverrideBar(captions, scopeOptions)
assert(metrics.rows == 2 and scope:GetLayoutMetrics().bottomY == metrics.bottomY, "scope measurement and layout disagree")
local function CheckLabel(choice)
    local label = choice._msuf2Label
    assert(label._msuf2FontRole == "control" and label:GetJustifyH() == "CENTER", "tab still uses the small action font")
    local left, owner, _, x = label:GetPoint(1)
    local right, other, _, edge = label:GetPoint(2)
    assert(left == "LEFT" and right == "RIGHT" and owner == choice and other == choice and x == 10 and edge == -10,
        "tab label is not bounded by its button")
    assert(choice:GetWidth() >= label:GetStringWidth() + 20, "tab has no room for its caption")
end
for _, choice in ipairs(scope.buttons) do CheckLabel(choice) end
local strip = W.SegmentTabs(ctx, section, { label = "", values = captions, width = 440, compact = true, defaultTab = "a" })
for _, choice in ipairs(strip.buttons) do CheckLabel(choice) end
assert(strip.buttons[2]:GetWidth() > strip.buttons[1]:GetWidth(), "unequal captions still use equal-width tabs")
local _, _, _, lastX = strip.buttons[3]:GetPoint()
assert(lastX + strip.buttons[3]:GetWidth() < strip:GetWidth() - 30, "short captions stretched to fill the strip")
local resize = {}
ctx.AddResizeCallback = function(_, callback) resize[#resize + 1] = callback end
local stacked = env.CreateFrame("Frame", nil, env.UIParent)
stacked:SetSize(660, 280)
local first = W.ScopeOverrideBar(ctx, stacked, { values = captions, width = 660, labelWidth = 0, startX = 14, centerY = -28 })
local second = W.ScopeOverrideBar(ctx, stacked, { values = { captions[1] }, width = 660, labelWidth = 0, startX = 14, centerY = -64 })
for _, width in ipairs({ 318, 660, 318 }) do
    first:SetWidth(width)
    second:SetWidth(width)
    for _, callback in ipairs(resize) do callback() end
    local _, _, _, _, center = second.buttons[1]:GetPoint()
    assert(center == second:GetLayoutMetrics().centerY and center + 13 < first:GetLayoutMetrics().bottomY,
        "wrapping the upper bar overlaps the lower selector")
end
local before = strip.buttons[2]:GetWidth()
local glyphWidth = mw.world.widgets.Methods.GetStringWidth
mw.world.widgets.Methods.GetStringWidth = function(self) return glyphWidth(self) * 1.2 end
T.RefreshMenuFonts()
assert(strip.buttons[2]:GetWidth() > before, "retained tab did not remeasure after a font change")
mw.world.widgets.Methods.GetStringWidth = glyphWidth
T.RefreshMenuFonts()
assert(strip.buttons[2]:GetWidth() == before, "restoring the menu font kept the wider tab")

-- The text shown in the scaled menu can measure wider than the same caption
-- in the shared UIParent probe. Use the rendered label for segment geometry.
local unbounded = mw.world.widgets.Methods.GetUnboundedStringWidth
local menuTextScale = 1.20
mw.world.widgets.Methods.GetUnboundedStringWidth = function(self)
    local _, owner = self:GetPoint(1)
    local width = self:GetStringWidth()
    return owner and owner._msuf2SegmentChoice == true and width * menuTextScale or width
end
local reminderTabs = W.SegmentTabs(ctx, section, { label = "", compact = true, wrap = true, width = 650,
    values = {
        { value = "reminders", text = "What to remind" },
        { value = "visibility", text = "When to show" },
        { value = "appearance", text = "Appearance", width = 145 },
    }, defaultTab = "reminders" })
local function CheckReminderCaptions()
    for _, choice in ipairs(reminderTabs.buttons) do
        local label = choice._msuf2Label
        assert(label:GetUnboundedStringWidth() == label:GetStringWidth() * menuTextScale, "fixture did not scale the tab font")
        assert(choice:GetWidth() >= label:GetUnboundedStringWidth() + 20, "scaled reminder caption is clipped: " .. label:GetText())
    end
    assert(reminderTabs:GetHeight() == 26, "reminder tabs wrapped despite available space")
    assert(reminderTabs:GetValue() == "reminders", "remeasuring reminder tabs changed selection")
    assert(reminderTabs.buttons[3]:GetWidth() >= 145, "remeasurement ignored the caller's minimum width")
end
CheckReminderCaptions()
menuTextScale = 1.4
World.FireScript(reminderTabs, "OnShow")
CheckReminderCaptions()
local general = M.GetGeneralDB()
local originalZoom = general.slashMenuScale
local unrelated = env.CreateFrame("Frame", nil, mw.win)
local unrelatedRefreshes = 0
T.TrackTabLayout(unrelated, function() unrelatedRefreshes = unrelatedRefreshes + 1 end)
general.slashMenuScale = 0.80
M.ApplyMenuFrameScale(mw.win)
local zoomedWidth = reminderTabs.buttons[1]:GetWidth()
menuTextScale = 1.55
general.slashMenuScale = 0.92
M.ApplyMenuFrameScale(mw.win)
CheckReminderCaptions()
assert(reminderTabs.buttons[1]:GetWidth() > zoomedWidth, "menu zoom did not resize the retained tabs")
assert(unrelatedRefreshes == 0, "menu zoom ran an unrelated tab layout")
menuTextScale = 1
general.slashMenuScale = originalZoom
M.ApplyMenuFrameScale(mw.win)
CheckReminderCaptions()
mw.world.widgets.Methods.GetUnboundedStringWidth = unbounded
print("menu_toggle_segment_geometry_smoke " .. flavor .. ": pass")
