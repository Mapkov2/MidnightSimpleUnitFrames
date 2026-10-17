local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
do
local isolated = setmetatable({}, { __index = _G })
isolated._G = isolated
local ns = { Client = { IsClassic = flavor ~= "Mainline" and flavor ~= "Forever" } }
for _, path in ipairs({ "Kernel/MSUF_Bootstrap.lua", "ClassPower/MSUF_CP_Constants.lua",
    "ClassPower/MSUF_CP_Controller_Colors.lua" }) do
    setfenv(assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path)), isolated)("MidnightSimpleUnitFrames", ns)
end
local shared = assert(ns.ClassPowerColors, "colour API must exist before controller build")
local fields = { OverrideRGB = "function", ResolveSlotColorMode = "function", ResolveSlotColor = "function",
    ResolveFullColor = "function", COMBO_POINT_SLOT_TOKENS = "table", COMBO_POINT_RAMP_R = "table",
    COMBO_POINT_RAMP_G = "table", COMBO_POINT_RAMP_B = "table" }
local count = 0
for key, value in pairs(shared) do
    assert(type(value) == fields[key], "load-time API field changed: " .. key)
    count = count + 1
end
assert(count == 8, "load-time API lost a field")
assert(shared.ResolveSlotColorMode("COMBO_POINTS", { comboPointColorMode = "ramp" }) == "ramp")
local config = { general = {}, comboPointColorMode = "ramp", colorOverrides = { COMBO_POINTS = { .2, .3, .4 } } }
local build = isolated.MSUF_CP_CORE_BUILDERS.CONTROLLER_COLORS
local live = build({ _cpDB = config, POWER_TYPE_TOKENS = {} })
assert(ns.ClassPowerColors == shared, "controller build replaced the load-time API")
assert(live.ResolveSlotColor == shared.ResolveSlotColor, "live resolver identity changed")
assert(shared.ResolveSlotColorMode("COMBO_POINTS") == "ramp", "live default config was not bound")
assert(live.ResolveClassPowerColor("COMBO_POINTS") == .2)
config.colorOverrides.COMBO_POINTS = { .7, .8, .9 }
local sample = { general = {}, comboPointColorMode = "custom", colorOverrides = { COMBO_POINTS = { .1, .2, .3 } } }
local scene = build({ scene = true, _cpDB = sample, POWER_TYPE_TOKENS = {} })
assert(ns.ClassPowerColors == shared and scene.ResolveSlotColor ~= shared.ResolveSlotColor)
assert(scene.ResolveSlotColorMode("COMBO_POINTS") == "custom")
assert(shared.ResolveSlotColorMode("COMBO_POINTS") == "ramp", "scene rebound live config")
assert(scene.ResolveClassPowerColor("COMBO_POINTS") == .1)
scene.InvalidateCaches()
assert(live.ResolveClassPowerColor("COMBO_POINTS") == .2, "scene invalidated live cache")
live.InvalidateCaches()
assert(live.ResolveClassPowerColor("COMBO_POINTS") == .7)
assert(scene.ResolveClassPowerColor("COMBO_POINTS") == .1, "live invalidated scene config")
end
local W = dofile(root .. "/tools/tests/preview_surface_world.lua")
local classes = { "ROGUE" }
local cases = 0
for _, class in ipairs(classes) do
  local sample = { class = class, spec = 1, count = 3, maximum = 5, primaryPower = 3, time = 100 }
  local h = W.Open(root, flavor, sample)
  local env, ns = h.env, h.core
  local owner = h:Host()
  local pf = env.CreateFrame("Frame", nil, owner)
  pf:SetSize(275, 40); pf:SetPoint("CENTER", owner, "CENTER", 0, 0)
  ns.UF.frames.player, env.MSUF_player = pf, pf
  local live = assert(W.Upvalue(env.MSUF_ClassPower_IsRuntimeActive, "CP"))
  local bars, general = env.MSUF_DB.bars, env.MSUF_DB.general
  bars.showClassPower, bars.showAltMana, bars.playerHPBarEnabled = true, false, false
  bars.classPowerAnchorToCooldown, bars.classPowerWidthMode = false, "player"
  bars.classPowerShowText, bars.classPowerHeight = true, 11
  bars.classPowerFilledAlpha, bars.classPowerEmptyAlpha = 0.83, 0.27
  bars.classPowerGap, bars.classPowerOutline = 3, 2
  bars.classPowerOffsetX, bars.classPowerOffsetY = 9, -7
  local r = h.GF.NewPreviewScene(owner)
  local scene = h:SceneCall(r.ClassPower, r, { sample = sample, playerWidth = 275 })
  assert(not scene:Frame(), "frame built while closed")
  env.MSUF_ClassPower_Refresh()
  local before = W.CPSnapshot(h, live, pf)
  h:SceneCall(r.Activate, r)
  assert(scene.CP.container:GetWidth() == 275, "P1 player width must be 275, with no 4px inset")
  W.Equal(h, before, W.CPSnapshot(h, scene.CP, scene:Frame()), "live/scene " .. class)
  W.Equal(h, before, W.CPSnapshot(h, live, pf), "scene changed live controller")
  for _, shape in ipairs({ "CIRCLE", "DIAMOND", "HEX", "BAR" }) do
    for _, mode in ipairs({ "default", "ramp", "custom" }) do
      bars.classPowerShape, bars.classPowerComboPointColorMode = shape, mode
      general.classPowerColorOverrides = { COMBO_POINTS = { .12, .32, .52 }, COMBO_POINTS_1 = { .77, .21, .48 },
        COMBO_POINTS_FULL = { .38, .74, .18 }, RESOURCE_TEXT = { .61, .23, .72 } }
      bars.classPowerFullColorEnabled = { COMBO_POINTS = true }
      sample.count = mode == "custom" and 5 or 3
      env.MSUF_ClassPower_Refresh()
      h:SceneCall(scene.SetOptions, scene, { sample = sample, playerWidth = 275 })
      if mode == "custom" then
        assert(scene.CP.visual.slotR[1] == .77 and scene.CP.visual.slotG[1] == .21
          and scene.CP.visual.slotB[1] == .48, "slot colour resolver dropped")
        assert(scene.CP.visual.useFullColor and scene.CP.visual.fullR == .38
          and scene.CP.visual.fullG == .74 and scene.CP.visual.fullB == .18, "full colour resolver dropped")
      end
      W.Equal(h, W.CPSnapshot(h, live, pf), W.CPSnapshot(h, scene.CP, scene:Frame()),
        flavor .. "/" .. class .. "/" .. shape .. "/" .. mode)
      cases = cases + 1
    end
  end
  local cooldowns = {}
  for i, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }) do
    local geometry = { width = 210 + i * 23, height = 37, scale = .8 + i * .2, x = 14, y = -107 }
    cooldowns[name] = geometry
    local cd = env.CreateFrame("Frame", nil, pf)
    cd:SetSize(geometry.width, geometry.height); cd:SetScale(geometry.scale)
    cd:SetPoint("CENTER", pf, "CENTER", geometry.x, geometry.y); cd:Show()
    env[name] = cd
  end
  for _, shape in ipairs({ "BAR", "CIRCLE" }) do
    bars.classPowerShape = shape
    for _, mode in ipairs({ "player", "custom", "auto_pips", "cooldown", "utility", "tracked_buffs" }) do
      bars.classPowerWidthMode, bars.classPowerWidth = mode, 319
      for _, anchored in ipairs({ false, true }) do
        bars.classPowerAnchorToCooldown = anchored
        env.MSUF_ClassPower_Refresh()
        h:SceneCall(scene.SetOptions, scene, { sample = sample, playerWidth = 275, cooldowns = cooldowns })
        W.Equal(h, W.CPSnapshot(h, live, pf), W.CPSnapshot(h, scene.CP, scene:Frame()),
          "width " .. shape .. "/" .. mode .. "/" .. tostring(anchored))
        if mode == "player" then assert(scene.CP.container:GetWidth() == 275, "4px width drift") end
        if mode == "custom" then assert(scene.CP.container:GetWidth() == 319, "custom width ignored") end
        cases = cases + 1
      end
    end
  end
  bars.classPowerAnchorToCooldown = false
  bars.classPowerWidthMode = "player"
  for _, count in ipairs({ 0, 3, 5 }) do
    sample.count = count
    bars.classPowerHideWhenEmpty, bars.classPowerHideWhenFull = true, true
    env.MSUF_ClassPower_Refresh()
    h:SceneCall(scene.SetOptions, scene, { sample = sample, playerWidth = 275 })
    W.Equal(h, W.CPSnapshot(h, live, pf), W.CPSnapshot(h, scene.CP, scene:Frame()), "full/empty visibility")
  end
  bars.classPowerHideWhenEmpty, bars.classPowerHideWhenFull, bars.classPowerHideOOC = false, false, true
  h:SceneCall(scene.Refresh, scene)
  assert(scene.CP.container:GetAlpha() == 1, "preview kept out-of-combat auto-hide")
  bars.classPowerHideOOC = false
  W.InputAndIsolation(h, r, scene)
  local poolSize
  for pass = 1, 2 do
    for _, resource in ipairs({ { class = "DRUID", spec = 2, primaryPower = 3 },
      { class = "WARRIOR", spec = 2 }, { class = "ROGUE", spec = 1 } }) do
      resource.count, resource.maximum = 3, 5
      h:SceneCall(scene.SetOptions, scene, { sample = resource, playerWidth = 275, cooldowns = cooldowns })
    end
    if poolSize then assert(#h.widgets.frames == poolSize, "class switch rebuilt pooled surfaces") end
    poolSize = #h.widgets.frames
  end
  W.Lifecycle(h, r, scene)
end
local allClasses = { "DRUID", "PALADIN", "WARLOCK", "MAGE", "SHAMAN", "PRIEST", "HUNTER", "WARRIOR" }
if flavor == "Mainline" or flavor == "Mists" then
  allClasses[#allClasses + 1], allClasses[#allClasses + 2] = "DEATHKNIGHT", "MONK"
end
if flavor == "Mainline" then
  allClasses[#allClasses + 1], allClasses[#allClasses + 2] = "EVOKER", "DEMONHUNTER"
end
for _, class in ipairs(allClasses) do
  local sample = { class = class, spec = 1, count = 3, maximum = 5, primaryPower = 0, time = 100 }
  local h = W.Open(root, flavor, sample)
  local env, ns, owner = h.env, h.core, h:Host()
  local pf = env.CreateFrame("Frame", nil, owner)
  pf:SetSize(275, 40); pf:SetPoint("CENTER", owner, "CENTER", 0, 0)
  ns.UF.frames.player, env.MSUF_player = pf, pf
  local live = assert(W.Upvalue(env.MSUF_ClassPower_IsRuntimeActive, "CP"))
  local b = env.MSUF_DB.bars
  b.showClassPower, b.showAltMana, b.playerHPBarEnabled, b.showEbonMight = true, false, false, false
  b.classPowerWidthMode, b.classPowerAnchorToCooldown, b.classPowerShape = "player", false, "BAR"
  b.classPowerShowText, b.classPowerHeight = true, 12
  b.showShadowMana, b.showEleMaelstrom, b.showGuardianIronfur, b.showSweepingStrikes = true, true, true, true
  local r = h.GF.NewPreviewScene(owner)
  local scene = h:SceneCall(r.ClassPower, r, { sample = sample, playerWidth = 275 })
  local specs = class == "DRUID" and { 1, 2, 3, 4, 2, 1, 3 } or { 1, 2, 3, 2, 1 }
  for _, spec in ipairs(specs) do
    sample.spec = spec
    sample.primaryPower = class == "DRUID" and (spec == 2 and 3 or spec == 3 and 1 or 0) or 0
    sample.maximum = class == "DEATHKNIGHT" and 6 or class == "EVOKER" and 6 or 5
    sample.modifier = flavor == "Mists" and class == "WARLOCK" and spec == 3 and 10 or 1
    sample.runes = class == "DEATHKNIGHT" and { { ready=true }, { ready=true }, { ready=true },
      { start=95,duration=10 }, { start=96,duration=10 }, { start=97,duration=10 } } or nil
    env.MSUF_ClassPower_Refresh()
    if class == "HUNTER" and live.powerType == "TIP_OF_THE_SPEAR" then
      live.spStacks = sample.count
      live.updateFn(live.powerType, live.currentMax)
    end
    if class == "DRUID" and live.powerType == "IRONFUR" then
      live.ironfur.PaintSample(sample)
    end
    h:SceneCall(scene.SetOptions, scene, { sample = sample, playerWidth = 275 })
    if not r:IsActive() then h:SceneCall(r.Activate, r) end
    if live.visible then
      assert(scene:Frame():IsShown(), "supported sample hidden " .. class .. spec)
      W.Equal(h, W.CPSnapshot(h, live, pf), W.CPSnapshot(h, scene.CP, scene:Frame()),
        flavor .. "/" .. class .. "/spec" .. spec)
    else
      assert(not scene:Frame():IsShown(), "invented class resource " .. class .. spec)
    end
    cases = cases + 1
  end
  h:SceneCall(r.Release, r)
end
print("classpower_preview_scene_smoke: " .. flavor .. " " .. cases .. " twin paints, geometry, API isolation and lifecycle")
