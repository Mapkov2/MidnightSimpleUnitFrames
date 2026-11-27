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
local values = {{value="a",text="A"},{value="b",text="B"},{value="c",text="C"},{value="d",text="D"}}
local ctx = {key="test",refreshers={}}
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
