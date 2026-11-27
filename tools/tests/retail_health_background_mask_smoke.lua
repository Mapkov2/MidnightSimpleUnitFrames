-- Replay the missing-health background through the normal single and group health drivers.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
assert(flavor == "Mainline" or flavor == "Forever", "expected Mainline or Forever")

local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local world = World.New(root, flavor)
local UF, GF = world.UF, world.GF

-- The budget fixture supplies an artificial rounded decorator. Exercise the
-- square-frame lane in which an edge mask would otherwise be eligible.
local OwnsMask = UF.Surface.OwnsMask
UF.Surface.OwnsMask = function(frame, texture)
    if frame == world.single or frame == world.group then return false end
    return OwnsMask(frame, texture)
end

local db = UF.Config.GetDB()
local general, target, raid = db.general, db.target, GF.GetConf("raid")
general.barBgFillMode, general.barBgColorMode = "missing", "custom"
general.barTexture, general.barBackgroundTexture = "Solid", "Solid"
general.classBarBgR, general.classBarBgG, general.classBarBgB, general.classBarBgA = 0.32, 0.32, 0.32, 1
target.hpBgAlpha, target.showHP = 1, true
target.textLeft, target.textCenter, target.textRight = "NONE", "NONE", "CURPERCENT"
target.smoothFill, target.chunkedFill, target.reverseFillBars, target.verticalFillBars = false, false, false, false
raid.barBgFillMode, raid.barBgColorMode = "missing", "custom"
raid.hpBgAlpha, raid.barBgColorOverride = 1, true
raid.deadBgEnabled = false
raid.bgR, raid.bgG, raid.bgB = 0.32, 0.32, 0.32

UF.Config.Refresh()
local targetSpec = UF.Config.GetSpec("target")
GF.InvalidateCompiledSpecs("raid")
local groupSpec = GF.CompileSpec("raid", world.group, "raid1")
assert(UF.ApplySpec(world.single, targetSpec, "MSUF_APPLY", true))
assert(UF.ApplySpec(world.group, groupSpec, "MSUF_APPLY", true))

local function Near(actual, expected, description)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        description .. ": expected " .. expected .. ", got " .. tostring(actual))
end

local function Check(frame, unit)
    local bar, texture = frame.healthBackgroundBar, frame.hpBarBG
    local expectedMask = flavor == "Forever"
    local label = flavor .. " " .. unit
    assert(frame._msufHealthBackgroundFillMissing, label .. " did not use missing-health mode")
    assert(frame._msufHealthBackgroundMaskActive == expectedMask, label .. " used the wrong background render path")
    assert(#texture.masks == (expectedMask and 1 or 0), label .. " has the wrong number of backdrop masks")
    assert(bar:GetStatusBarTexture() == texture, label .. " draws a different backdrop than the one tinted")
    assert(bar:GetReverseFill() == true, label .. " has the wrong background orientation")

    world:Prime(frame, unit)
    for _, fraction in ipairs({ 1, 0.621, 0.823, 0.23, 1 }) do
        world.S.pct = fraction
        world:Fire(frame, unit, "UNIT_HEALTH")
        Near(bar:GetValue(), expectedMask and 100 or 100 * (1 - fraction), label .. " missing-health value")
        local r, g, b, a = texture:GetVertexColor()
        Near(r, 0.32, label .. " red")
        Near(g, 0.32, label .. " green")
        Near(b, 0.32, label .. " blue")
        Near(a, 1, label .. " alpha")
        assert(#texture.masks == (expectedMask and 1 or 0), label .. " changed mask attachments during a health update")
    end

    if not expectedMask then
        world.S.secret = true
        world:Fire(frame, unit, "UNIT_HEALTH")
        assert(world.Secrets.IsSecret(bar:GetValue()), label .. " did not deliver the restricted inverse value")
        world.S.secret, world.S.pct = false, 0.621
        world:Fire(frame, unit, "UNIT_HEALTH")
        Near(bar:GetValue(), 37.9, label .. " did not resume public inverse updates")
    end
end

Check(world.single, "target")
Check(world.group, "raid1")

if flavor == "Mainline" then
    -- Feed one synthetic sample through the same owner used by unit previews.
    local frame = world.single
    local fill, background = frame.hpBar, frame.healthBackgroundBar
    local interpolation = {}
    fill._msufSmoothInterp = interpolation
    for _, bar in ipairs({ fill, background }) do
        local SetValue = bar.SetValue
        function bar:SetValue(value, mode)
            self.observedInterpolation = mode
            SetValue(self, value, mode)
        end
    end

    local PaintSample = UF.Elements.Health.PaintSample
    assert(PaintSample(frame, "target", 823, 1000, true))
    assert(rawequal(fill.observedInterpolation, interpolation), "preview foreground snapped")
    assert(rawequal(background.observedInterpolation, interpolation), "preview background snapped")
    Near(background:GetValue(), 17.7, "animated preview missing-health value")
    assert(PaintSample(frame, "target", 621, 1000, false))
    assert(fill.observedInterpolation == nil and background.observedInterpolation == nil, "static preview interpolated")
    Near(background:GetValue(), 37.9, "static preview missing-health value")
end

print(flavor .. " single and group missing-health background render paths passed")
