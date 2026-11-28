-- Replay the missing-health background through the normal single and group health drivers.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local restrictedHealth = flavor == "Mainline" or flavor == "Forever"
assert(restrictedHealth or flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists", "unsupported test flavor")
local absoluteOnly = arg[3] == "absolute"
assert(arg[3] == nil or (absoluteOnly and not restrictedHealth), "expected an optional Classic absolute mode")

local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local world = World.New(root, flavor, {
    beforeFile = function(_, env)
        if absoluteOnly then
            -- Exercise the public absolute fallback without native percent curves.
            env.UnitHealthPercent, env.CurveConstants = false, false
        end
    end,
})
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

local function ApplyProfiles()
    UF.Config.Refresh()
    local targetSpec = UF.Config.GetSpec("target")
    GF.InvalidateCompiledSpecs("raid")
    local groupSpec = GF.CompileSpec("raid", world.group, "raid1")
    assert(UF.ApplySpec(world.single, targetSpec, "MSUF_APPLY", true))
    assert(UF.ApplySpec(world.group, groupSpec, "MSUF_APPLY", true))
end
ApplyProfiles()

local function Near(actual, expected, description)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        description .. ": expected " .. expected .. ", got " .. tostring(actual))
end

local function Check(frame, unit)
    local bar, texture = frame.healthBackgroundBar, frame.hpBarBG
    local label = flavor .. " " .. unit
    assert(frame._msufHealthBackgroundFillMissing, label .. " did not use missing-health mode")
    assert(#texture.masks == 0, label .. " has the wrong number of backdrop masks")
    assert(bar:GetStatusBarTexture() == texture, label .. " draws a different backdrop than the one tinted")
    assert(bar:GetReverseFill() == true, label .. " has the wrong background orientation")

    world:Prime(frame, unit)
    for _, fraction in ipairs({ 1, 0.621, 0.823, 0.23, 1 }) do
        world.S.pct = fraction
        world:Fire(frame, unit, "UNIT_HEALTH")
        local _, foregroundMax = frame.hpBar:GetMinMaxValues()
        Near(foregroundMax, absoluteOnly and World.MAX_HEALTH or 100, label .. " foreground value route")
        Near(bar:GetValue(), 100 * (1 - fraction), label .. " missing-health value")
        local r, g, b, a = texture:GetVertexColor()
        Near(r, 0.32, label .. " red")
        Near(g, 0.32, label .. " green")
        Near(b, 0.32, label .. " blue")
        Near(a, 1, label .. " alpha")
        assert(#texture.masks == 0, label .. " changed mask attachments during a health update")
    end

    if restrictedHealth then
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

if restrictedHealth then
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

local function VisibleHealth(frame)
    local low, high = frame.hpBar:GetMinMaxValues()
    return (frame.hpBar:GetValue() - low) / (high - low)
end

-- The on-screen group preview is the default scene used in Edit Mode. With
-- animation stopped, its dummies still need the missing extent for fake HP.
local function CheckEditModeGroupPreview()
    world.env.MSUF_UnitEditModeActive = true
    assert(GF.ShowPreview("raid", 2, { immediate = true }), "Edit Mode raid preview did not show")
    local frames = GF.PreviewScenes.Default.raid:Frames()
    assert(#frames == 2, "Edit Mode raid preview has the wrong count")
    for _, frame in ipairs(frames) do
        Near(frame.healthBackgroundBar:GetValue(), 100 * (1 - VisibleHealth(frame)), "static Edit Mode group background")
    end
    GF.HidePreview("raid")
    world.env.MSUF_UnitEditModeActive = false
end

-- Match the native driver entry: paint a synthetic unit while Edit Mode owns
-- the animation, then stop it and return authority to the live health driver.
local function CheckEditModeUnitPreview()
    local frame = world.single
    local background = frame.healthBackgroundBar
    local animation = world.core.PreviewAnimation
    world.S.pct = 0.621
    world:Fire(frame, "target", "UNIT_HEALTH")
    Near(background:GetValue(), 37.9, "live background before Edit Mode animation")
    frame:Show()
    animation.enabled, animation.source, animation.elapsed = true, "edit_mode", 2.5
    assert(animation.ApplyUnitFrame(frame, 1, "target"), "Edit Mode target preview did not paint")
    assert(math.abs(VisibleHealth(frame) - world.S.pct) > 0.01, "Edit Mode target fixture did not change the sample")
    Near(background:GetValue(), 100 * (1 - VisibleHealth(frame)), "animated Edit Mode target background")
    if restrictedHealth then
        local fill = frame.hpBar
        assert(fill.observedInterpolation == nil and background.observedInterpolation == nil,
            "first Edit Mode paint did not snap the foreground and background together")
        animation.elapsed = 3.0
        assert(animation.ApplyUnitFrame(frame, 1, "target"), "second Edit Mode target sample did not paint")
        local interpolation = assert(fill._msufSmoothInterp, "Edit Mode fixture lost interpolation")
        assert(rawequal(fill.observedInterpolation, interpolation) and rawequal(background.observedInterpolation, interpolation),
            "ongoing Edit Mode animation did not interpolate the foreground and background together")
        Near(background:GetValue(), 100 * (1 - VisibleHealth(frame)), "ongoing Edit Mode target background")
    end
    assert(animation.SetEnabled(false), "Edit Mode target preview did not stop")
    Near(VisibleHealth(frame), world.S.pct, "live health restored after Edit Mode")
    Near(background:GetValue(), 37.9, "live background restored after Edit Mode")
    world.S.pct = 0.823
    world:Fire(frame, "target", "UNIT_HEALTH")
    Near(background:GetValue(), 17.7, "live background resumed after Edit Mode")
end

CheckEditModeUnitPreview()
CheckEditModeGroupPreview()


if restrictedHealth then
    local frame, animation = world.single, world.core.PreviewAnimation
    local background = frame.healthBackgroundBar
    world.S.secret = true
    world:Fire(frame, "target", "UNIT_HEALTH")
    assert(world.Secrets.IsSecret(background:GetValue()), "live restricted inverse was not delivered")
    animation.enabled, animation.source, animation.elapsed = true, "edit_mode", 3.5
    assert(animation.ApplyUnitFrame(frame, 1, "target"), "restricted target preview did not paint")
    assert(not world.Secrets.IsSecret(background:GetValue()), "restricted target preview did not use synthetic health")
    assert(animation.SetEnabled(false), "restricted target preview did not stop")
    assert(world.Secrets.IsSecret(background:GetValue()), "stopping preview left public health on a restricted backdrop")
    world.S.secret = false
end

general.barBgFillMode, raid.barBgFillMode = "full", "full"
ApplyProfiles()
world.S.pct = 0.621
for _, frame in ipairs({ world.single, world.group }) do
    world:Fire(frame, frame.MSUFUnitKey, "UNIT_HEALTH")
    Near(frame.healthBackgroundBar:GetValue(), 100, flavor .. " full background value")
    assert(not frame._msufHealthBackgroundNeedsValue, flavor .. " full background still follows health")
end

-- Healing and absorb overlays may be clipped at the health bounds. Clipping the
-- native health StatusBar itself can discard the first foreground pixel.
local function CheckPredictionClip(frame, spec)
    local cfg = spec.prediction
    local mode = UF.Shared.ABSORB_ANCHOR
    cfg.enabled, cfg.heal, cfg.absorb, cfg.healAbsorb = true, true, true, true
    cfg.healAnchorMode, cfg.healAbsorbAnchorMode = mode.FOLLOW_HP, mode.FOLLOW_HP
    cfg.absorbAnchorMode = mode.FOLLOW_HP_OVERFLOW
    assert(UF.ApplySpec(frame, spec, "MSUF_APPLY", { Health = true, Prediction = true }))
    local hp = frame.hpBar
    local bounded = assert(frame.incomingHealBar):GetParent()
    local overflow = assert(frame.absorbBar):GetParent()
    if restrictedHealth then
        assert(not hp:DoesClipChildren(), "prediction clipping cuts into the health foreground")
        assert(bounded ~= hp and bounded:GetParent() == hp and bounded:DoesClipChildren() and bounded.allPoints == hp,
            "bounded predictions must clip to the health rect")
    else
        assert(bounded == hp and hp:DoesClipChildren(), "Classic prediction clipping changed")
    end
    assert(frame.healAbsorbBar:GetParent() == bounded and overflow ~= bounded and overflow:DoesClipChildren(),
        "bounded and overflow predictions lost their separate clipping")
    assert(UF.ApplySpec(frame, spec, "MSUF_APPLY", { Prediction = true }))
    assert(frame.incomingHealBar:GetParent() == bounded and frame.absorbBar:GetParent() == overflow,
        "prediction reapply replaced the clipping parents")
end
CheckPredictionClip(world.single, world.single.MSUFSpec)
CheckPredictionClip(world.group, world.group.MSUFSpec)
local targetTarget = world.env.CreateFrame("Button", nil, world.env.UIParent)
targetTarget.MSUFUnitKey = "targettarget"
local targetSpec = UF.Config.RefreshUnit("targettarget")
local cfg, mode = targetSpec.prediction, UF.Shared.ABSORB_ANCHOR
cfg.enabled, cfg.heal, cfg.absorb, cfg.healAbsorb = true, true, true, true
cfg.healAnchorMode, cfg.absorbAnchorMode, cfg.healAbsorbAnchorMode = mode.LEFT, mode.RIGHT, mode.RIGHT
assert(UF.ApplySpec(targetTarget, targetSpec, "MSUF_APPLY", { Health = true, Prediction = true }))
assert(not targetTarget.hpBar:DoesClipChildren() and targetTarget.incomingHealBar:GetParent() == targetTarget.hpBar,
    "a fixed-position prediction acquired clipping")
CheckPredictionClip(targetTarget, targetSpec)

print(flavor .. (absoluteOnly and " absolute" or "") .. " single and group missing-health background render paths passed")
