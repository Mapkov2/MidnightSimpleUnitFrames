local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local world = dofile(root .. "/tools/tests/client_world.lua").New(root, flavor)
world:Boot()
assert(not world:FirstFailure(), "client boot failed")
local UF, env = world.core.UF, world.env
assert(type(UF.RegisterDecorator) == "function", "decorator registry missing")
local frame, texture = env.CreateFrame("Frame", nil, env.UIParent), {}
frame.MSUFUnitKey = "player"
local seen, owns = {}, true
assert(UF.RegisterDecorator("TestSurface", {
    Apply = function(f) seen.apply = f end,
    OnIdentity = function(f) seen.identity = f end,
    OnShow = function(f) seen.show = f end,
    OnVisualChanged = function(f, event, ...)
        seen.visual, seen.tail = event, select(9, ...)
        return f == frame
    end,
    OwnsMask = function(f, t) return owns and f == frame and t == texture end,
}))
UF.AttachFrame(frame)
UF.ApplySpec(frame, { unit = "player", enabled = true }, nil, {})
assert(seen.apply == nil, "element transaction added a decorator apply trigger")
frame:Hide()
frame:GetScript("OnHide")(frame)
frame:Show()
frame:GetScript("OnShow")(frame)
assert(seen.show == nil, "engine show added a decorator apply trigger")
UF.OnUnitChanged(frame, "player", "player")
assert(seen.identity == nil, "engine identity added a decorator apply trigger")
UF.Surface.Apply(frame)
UF.Surface.OnIdentity(frame)
UF.Surface.OnShow(frame)
assert(UF.Surface.OnVisualChanged(frame, "dispel"), "visual notification lost its result")
assert(seen.apply == frame and seen.identity == frame and seen.show == frame and seen.visual == "dispel")
UF.Surface.OnVisualChanged(frame, "edge", 1, 2, 3, 4, 5, 6, 7, 8, "blend")
assert(seen.tail == "blend", "visual callback lost its final argument")
assert(UF.Surface.OwnsMask(frame, texture), "mask ownership missing")
UF.SetDecoratorActive("TestSurface", false)
assert(UF.Surface.OwnsMask(frame, texture), "inactive decorator lost a retained mask")
owns = false
assert(not UF.Surface.OwnsMask(frame, texture), "released mask retained ownership")
seen.apply = nil
UF.Surface.Apply(frame)
assert(seen.apply == nil, "disabled decorator still applies")
assert(UF.Decorators.RoundedFrames and UF.Decorators.TextureLayer, "effect decorators missing")
-- Factory applies and explicit visual refreshes preserve their once-only
-- layout trigger. Targeted element transactions must add no surface work.
local tick = dofile(root .. "/tools/tests/health_tick_world.lua").New(root, flavor)
local runtime = tick.h.world.core
local layout = runtime.TextureLayer.ApplyToUnitFrame
tick.single._msufActivate = function(self) tick.env.RegisterUnitWatch(self); self:Show(); return true end
runtime.UF.Apply("target")
local function CountLayouts(run, expected)
    local count = 0
    debug.sethook(function()
        if debug.getinfo(2, "f").func == layout then count = count + 1 end
    end, "c")
    run()
    debug.sethook()
    assert(count == (expected or 1), "unexpected effect layouts in one transaction: " .. count)
end
CountLayouts(function() runtime.UF.Apply("target") end)
CountLayouts(function() runtime.UF.RefreshVisuals("target") end)
CountLayouts(function() runtime.UF.RefreshColors("target") end, 0)
CountLayouts(function() runtime.UF.ApplyElementsToFrame(tick.single, { "Borders" }) end, 0)
local eventFrame, eventName, eventUnit, identityCalls
identityCalls = 0
runtime.UF.RegisterDecorator("EventSurface", {
    OnEvent = function(driver, event, unit) eventFrame, eventName, eventUnit = driver, event, unit end,
    OnIdentity = function() identityCalls = identityCalls + 1 end,
})
runtime.UF.Surface.SetEvent("EventSurface", "native", "UNIT_TEST_SURFACE", true, "target")
tick.h:Event("UNIT_TEST_SURFACE", "target")
assert(runtime.UF.Surface.IsDecoratorActive("TextureLayer"), "decorator activity API missing")
assert(eventFrame and eventName == "UNIT_TEST_SURFACE" and eventUnit == "target", "native callback arguments lost")
assert(identityCalls == 0, "native event escaped into frame identity callback")
runtime.UF.SetDecoratorActive("EventSurface", false)
eventName = nil
tick.h:Event("UNIT_TEST_SURFACE", "target")
assert(eventName == nil, "inactive event decorator received a native callback")
runtime.UF.SetDecoratorActive("EventSurface", true)
tick.h:Event("UNIT_TEST_SURFACE", "target")
assert(eventName == "UNIT_TEST_SURFACE", "reactivated event decorator lost its callback")
print("uf_surface_decorators_smoke: ok (" .. flavor .. ")")
