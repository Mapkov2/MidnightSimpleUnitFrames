-- Exercise configured scene slots with the real native-animation glow renderer.
local root, flavor = assert(arg[1]):gsub("/$", ""), arg[2] or "Mainline"
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.MAX_BOSS_FRAMES = 5
    -- Native FlipBook geometry is absent from the shared widget emulator.
    local methods = world.widgets.Methods
    methods.SetFlipBookFrameWidth = function(self, width) self.flipBookFrameWidth = width end
    methods.SetFlipBookFrameHeight = function(self, height) self.flipBookFrameHeight = height end
end })
local GF, A3 = h.GF, h.core.MSUF_Auras3
GF.EnsureDB()
local host = h.env.CreateFrame("Frame", nil, h.env.UIParent)
host:SetSize(400, 300)
local scene = GF.NewPreviewScene(host)
scene:Activate()
local group = scene:Group("party", 1, { immediate = true })
h:RunTimers()
local frame = assert(group:Frames()[1])
local slot = { enabled = true, visual = "icon", iconEffect = "glow", size = 24,
    color = { 0.2, 0.4, 0.6, 0.8 }, icon = 134400 }
-- Supply resolved settings at the same boundary as the native config compiler.
A3.ResolveAuraPreviewConfig = function() return { spellIndicators = { enabled = true, slots = { slot } } } end
assert(GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec))
local visual = assert(frame._msufGFSpellIndicatorPreviews[1])
local classic = h.core.Client.IsClassic
local effect = classic and visual or assert(visual._msufA3PreviewIconEffectRoot, "configured slot did not use the live glow")
local glow = classic and assert(visual._msufA3ClassicIconGlow, "Classic configured slot lost its live glow")
    or assert(effect._msufA3AnimatedGlow, "configured slot has no halo/ants")
local function Playing()
    return classic and glow:IsShown() or (not classic and glow.animation:IsPlaying())
end
assert(Playing(), "configured glow is idle")
if not classic then
    assert(glow.halo:IsShown() and glow.ants:IsShown(), "native halo/ants are hidden")
    assert(glow.r == 0.2 and glow.a == 0.8, "configured glow lost its selected colour")
end
local frames, regions = #h.widgets.frames, #effect.regions
for _ = 1, 5 do assert(GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)) end
assert(#h.widgets.frames == frames and #effect.regions == regions, "repaint grew the retained glow")
slot.hiddenVisual = true
GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)
assert(not Playing(), "hidden configured icon kept animating")
slot.hiddenVisual = nil
GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)
slot.iconEffect = "none"
GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)
assert(not Playing() and (classic or not effect:IsShown()), "changing effect kept old glow alive")
slot.iconEffect = "glow"
GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)
GF.HideSpellIndicators(frame)
assert(not Playing(), "hiding configured slots kept native animation alive")
local sampleOwner = h.env.CreateFrame("Frame", nil, frame)
local bar = GF.PreviewSpellSample(frame, sampleOwner,
    { enabled = true, visual = "bar", size = 24, width = 100, color = { 0.2, 0.4, 0.6, 0.8 } })
assert(bar._durationBar:IsShown() and bar._durationBar:GetWidth() == 68, "bar sample lost its partial duration fill")
assert(not bar._msufA3ClassicIndicatorSwatch or not bar._msufA3ClassicIndicatorSwatch:IsShown(),
    "icon glow adapter covered the bar sample with a solid swatch")
GF.PreviewSpellIndicators(frame, "party", frame.MSUFSpec)
scene:Deactivate()
assert(not Playing(), "closing preview kept native animation alive")
print("group_preview_configured_glow_smoke " .. flavor .. ": configured halo/ants reuse and idle cleanup passed")
