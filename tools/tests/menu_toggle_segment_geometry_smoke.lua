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
print("menu_toggle_segment_geometry_smoke " .. flavor .. ": pass")
