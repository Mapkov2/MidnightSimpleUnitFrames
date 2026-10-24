-- Real client regions exercise material lifetime; counters bound cold writes.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local sourceOverride = arg[4]
local mw = World.Open(root, flavor, { page = "home", beforeCore = function(world)
  if sourceOverride then
    local load = world.LoadFile
    world.LoadFile = function(self, path, ...)
      if path:sub(-#"MSUF_UF_Elements_BarGloss.lua") == "MSUF_UF_Elements_BarGloss.lua" then path = sourceOverride end
      return load(self, path, ...)
    end
  end
  if arg[3] == "--separate-alpha" then return end
  -- Model the stricter native Texture contract in which both setters share
  -- one alpha lane. This conditional model is not a live renderer assertion.
  local methods = world.widgets.Methods
  local setAlpha, setVertex, getVertex = methods.SetAlpha, methods.SetVertexColor, methods.GetVertexColor
  function methods:SetAlpha(alpha)
    setAlpha(self, alpha)
    if self:GetObjectType() == "Texture" and self.vertexColor then self.vertexColor[4] = alpha end
  end
  function methods:SetVertexColor(r, g, b, alpha)
    setVertex(self, r, g, b, alpha)
    if self:GetObjectType() == "Texture" then self.alpha = alpha == nil and 1 or alpha end
  end
  function methods:GetVertexColor()
    local r, g, b, alpha = getVertex(self)
    if self:GetObjectType() == "Texture" then alpha = self.alpha end
    return r, g, b, alpha
  end
end })
local core, env = mw.core, mw.env
local UF, Common = core.UF, core.UFBarTextCommon
local checks = 0
local function Check(ok, label)
  checks = checks + 1
  assert(ok, flavor .. ": " .. label)
end
if arg[3] == "--without-gloss" then Common.ApplyBarGloss = function() end end
local function SharedAlphaLifecycle()
  for _, detached in ipairs({ false, true }) do
    local spec = UF.Config.GetSpec("target")
    spec.health.barGloss = { enabled = true, strength = 0.6 }
    spec.power.barGloss = { enabled = true, strength = 0.6 }
    spec.power.enabled, spec.power.detached, spec.power.alpha = true, detached, 0.35
    spec.power.detachedWidth, spec.power.detachedWidthExplicit, spec.power.detachedHeight = 147, 147, 8
    spec.alpha.active, spec.alpha.hpAlpha = true, 0.4
    local sample = env.CreateFrame("Button", nil, env.UIParent)
    sample:SetSize(275, 40)
    sample.MSUFSpec, sample.MSUFUnitKey, sample.unit = spec, "target", "target"
    UF.elements.Health.Create(sample, spec)
    UF.elements.Health.Apply(sample, spec)
    UF.elements.Power.Apply(sample, spec)
    UF.elements.Alpha.Apply(sample, spec)
    local hp, power = assert(sample.hpGloss), assert(sample.powerGloss)
    local function Dose(gloss, strength, opacity, label)
      for _, band in ipairs({ "upper", "lower" }) do
        local region = gloss[band]
        local r, g, b, vertexAlpha = region:GetVertexColor()
        local expected = strength * (band == "upper" and 0.65 or 0.08)
        local light = r * region:GetAlpha()
        if arg[3] == "--separate-alpha" then light = light * vertexAlpha end
        Check(math.abs(light - expected * opacity) < 0.000001,
          label .. " lost its material dose through the shared alpha lane")
        Check(r == g and g == b, label .. " reflected light is not neutral")
      end
    end
    Dose(power, 0.6, 0.35, "cold Power.Apply")
    Dose(hp, 0.6, 0.4, "cold Health/Alpha.Apply")
    spec.health.barGloss.strength, spec.power.barGloss.strength = 0.3, 0.2
    UF.elements.Health.Apply(sample, spec)
    UF.elements.Power.Apply(sample, spec)
    UF.elements.Alpha.Update(sample, "UNIT_HEALTH")
    Dose(power, 0.2, 0.35, "warm Power strength")
    Dose(hp, 0.3, 0.4, "warm Health strength with cached opacity")
    spec.power.alpha, spec.alpha.hpAlpha = 0, 0
    UF.elements.Power.Apply(sample, spec)
    UF.elements.Alpha.Apply(sample, spec)
    Dose(power, 0.2, 0, "zero Power opacity")
    Dose(hp, 0.3, 0, "zero Health opacity")
    spec.health.barGloss.strength, spec.power.barGloss.strength = 0.4, 0.5
    UF.elements.Health.Apply(sample, spec)
    UF.elements.Power.Apply(sample, spec)
    UF.elements.Alpha.Update(sample, "UNIT_HEALTH")
    Dose(power, 0.5, 0, "Power strength while transparent")
    Dose(hp, 0.4, 0, "Health strength while transparent")
    spec.power.alpha, spec.alpha.hpAlpha = 0.5, 0.5
    UF.elements.Power.Apply(sample, spec)
    UF.elements.Alpha.Apply(sample, spec)
    Dose(power, 0.5, 0.5, "restored Power opacity")
    Dose(hp, 0.4, 0.5, "restored Health opacity")
    local writes = 0
    for _, region in ipairs({ hp.upper, hp.lower, power.upper, power.lower }) do
      for _, name in ipairs({ "SetVertexColor", "SetAlpha", "SetPoint", "SetTexture", "SetTexCoord", "SetBlendMode" }) do
        local original = region[name]
        region[name] = function(self, ...) writes = writes + 1 return original(self, ...) end
      end
    end
    for pass = 1, 20 do
      Common.ApplyBarGloss(sample, sample.targetPowerBar, spec.power.barGloss, "powerGloss", 0.5)
    end
    Check(writes == 0, "unchanged Power material rewrote a native property")
    Check(sample.powerGloss == power and sample.hpGloss == hp, "alpha refresh replaced material regions")
    UF.Config.Refresh()
  end
end
SharedAlphaLifecycle()
local frame = env.CreateFrame("Button", nil, env.UIParent)
frame:SetSize(180, 40)
local bar = env.CreateFrame("StatusBar", nil, frame)
bar:SetSize(180, 40)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
local creations, targetReads = 0, 0
local getTarget = bar.GetStatusBarTexture
bar.GetStatusBarTexture = function(self, ...) targetReads = targetReads + 1 return getTarget(self, ...) end
local create = bar.CreateTexture
bar.CreateTexture = function(self, ...)
  creations = creations + 1
  return create(self, ...)
end
local off, on = { enabled = false, strength = 0.5 }, { enabled = true, strength = 0.6 }
Common.ApplyBarGloss(frame, bar, off, "hpGloss")
Check(frame.hpGloss == nil and creations == 0, "disabled material allocated")
Common.ApplyBarGloss(frame, bar, { enabled = true, strength = 0 }, "hpGloss")
Check(frame.hpGloss == nil and creations == 0, "zero strength allocated")
Check(targetReads == 0, "off or zero strength queried native fill")
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
local gloss = frame.hpGloss
Check(gloss and gloss.upper and gloss.lower and creations == 2, "enabled gloss did not create exactly two regions")
Check(math.abs(gloss.upper:GetVertexColor() - 0.6 * 0.65) < 0.000001, "gloss lost its neutral material intensity")
Check(gloss.target == bar:GetStatusBarTexture(), "gloss does not follow native fill")
local layer, sublevel = gloss.upper:GetDrawLayer()
Check(layer == "OVERLAY" and sublevel == 1, "gloss layer displaced text/prediction ownership")
local writes = 0
for _, texture in ipairs({ gloss.upper, gloss.lower }) do
  for _, name in ipairs({ "SetGradient", "SetGradientAlpha", "SetPoint", "ClearAllPoints", "SetAlpha", "Show", "Hide", "SetVertexColor",
      "SetTexture", "SetTexCoord", "SetBlendMode" }) do
    local original = texture[name]
    if original then texture[name] = function(self, ...) writes = writes + 1 return original(self, ...) end end
  end
end
for i = 1, 20 do Common.ApplyBarGloss(frame, bar, on, "hpGloss") end
Check(writes == 0 and creations == 2, "unchanged cold apply allocated or rewrote regions")
Common.ApplyBarGloss(frame, bar, off, "hpGloss")
Check(not gloss.upper:IsShown() and not gloss.lower:IsShown(), "disabled retained gloss is visible")
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
Check(frame.hpGloss == gloss and creations == 2, "reenable replaced gloss")
-- Existing native art provides detached ROUND/CRYSTAL/ORB alpha silhouettes.
bar._msufGlossMaskPath = "shape-a"
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
local mask = gloss.mask
Check(mask and gloss.maskAttached, "detached shape did not attach mask")
local adds = 0
for _, texture in ipairs({ gloss.upper, gloss.lower }) do
  local add = texture.AddMaskTexture
  texture.AddMaskTexture = function(self, ...) adds = adds + 1 return add(self, ...) end
end
bar._msufGlossMaskPath = "shape-b"
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
Check(gloss.mask == mask and adds == 0, "shape change duplicated mask attachment")
bar._msufGlossMaskPath = nil
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
Check(not gloss.maskAttached, "return to ordinary bar kept detached mask")
-- Combat never allocates or retargets a retained protected-layout region.
local other = env.CreateFrame("StatusBar", nil, frame)
other:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
local retainedTarget, retainedWrites = gloss.target, writes
mw.world.widgets:SetCombat(true)
Common.ApplyBarGloss(frame, other, on, "hpGloss")
Common.ApplyBarGloss(frame, other, on, "newGloss")
Check(gloss.target == retainedTarget and writes == retainedWrites, "combat retarget mutated retained regions")
Check(frame.newGloss == nil, "combat activation allocated regions")
mw.world.widgets:SetCombat(false)
Common.ApplyBarGloss(frame, other, on, "hpGloss")
Check(gloss.target == other:GetStatusBarTexture(), "retarget did not complete after combat")
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
-- Compilers preserve explicit false/zero and never materialize old defaults.
local shared = { healthGlossEnabled = true, healthGlossStrength = 0.8, powerGlossEnabled = true, powerGlossStrength = 0.2 }
local conf = { hlOverride = true, healthGlossEnabled = false, powerGlossStrength = 0 }
local hp, power = UF.ResolveBarGloss(conf, shared, "health"), UF.ResolveBarGloss(conf, shared, "power")
Check(hp.enabled == false and hp.strength == 0.8, "explicit false or absent strength inheritance failed")
Check(power.enabled == true and power.strength == 0, "explicit zero was replaced")
conf.hlOverride = false
Check(UF.ResolveBarGloss(conf, shared, "health").enabled, "disabled scope override did not inherit")
local empty = {}
local defaults = UF.ResolveBarGloss(empty, empty, "health")
Check(defaults.enabled == false and defaults.strength == 0.5 and next(empty) == nil, "resolver wrote defaults")
-- First activation after opacity was already cached must use Alpha's real sink.
frame.hpBar, frame.Health = bar, bar
frame.MSUFSpec = { alpha = { active = true, hpAlpha = 0 }, health = {} }
local Alpha = UF.elements.Alpha
Alpha.Apply(frame, frame.MSUFSpec)
Check(gloss.upper:GetAlpha() == 0 and gloss.lower:GetAlpha() == 0, "health opacity zero left gloss visible")
frame.hpGloss = nil
Alpha.Apply(frame, frame.MSUFSpec)
Common.ApplyBarGloss(frame, bar, on, "hpGloss")
Alpha.Update(frame, "UNIT_HEALTH")
Check(frame.hpGloss.upper:GetAlpha() == 0, "cached health alpha ignored first gloss activation")
-- Opaque range booleans pass unchanged to native alpha sinks.
local token, observed = {}, {}
frame._msufRangeBooleanActive, frame._msufRangeBooleanValue = true, token
frame._msufRangeBooleanOutAlpha, frame._msufAlphaRangeHealthLayer = 0.2, true
frame._msufAlphaRuntimeCfg.hpAlpha = 0.5
for _, texture in ipairs({ frame.hpGloss.upper, frame.hpGloss.lower }) do
  texture.SetAlphaFromBoolean = function(self, value, inside, outside)
    observed[#observed + 1] = { value, inside, outside }
  end
end
Alpha.Update(frame, "MSUF_ALPHA")
Check(#observed == 2 and observed[1][1] == token and observed[1][2] == 0.5 and observed[1][3] == 0.1,
  "native boolean range alpha did not include gloss")
frame._msufRangeBooleanActive = nil
-- Only cold material applies invoke the painter; ordinary health/power events do not.
local calls = 0
local original = Common.ApplyBarGloss
Common.ApplyBarGloss = function(...) calls = calls + 1 return original(...) end
local spec = UF.Config.GetSpec("player")
frame.MSUFSpec, frame.MSUFUnitKey, frame.unit = spec, "player", "player"
UF.elements.Health.Create(frame, spec)
UF.elements.Health.Apply(frame, spec)
UF.elements.Power.Apply(frame, spec)
local plain = env.CreateFrame("Button", nil, env.UIParent)
local plainSpec = UF.Config.GetSpec("target")
plain.MSUFSpec, plain.MSUFUnitKey, plain.unit = plainSpec, "target", "target"
UF.elements.Health.Create(plain, plainSpec)
calls = 0
UF.elements.Health.Apply(plain, plainSpec)
UF.elements.Power.Apply(plain, plainSpec)
Check(calls == 0 and plain.hpGloss == nil and plain.powerGloss == nil,
  "never-enabled frame entered the gloss material painter")
calls = 0
for i = 1, 20 do
  UF.elements.Health.Update(frame, "UNIT_HEALTH", "player")
  UF.elements.Power.Update(frame, "UNIT_POWER_UPDATE", "player", "MANA")
end
Check(calls == 0, "ordinary health/power event ran material painter")
Common.ApplyBarGloss = original
-- Real recompilation keeps only complete Gloss records; domains stay fresh.
local function CompilerGlossLifecycle()
  local config, copy = UF.Config, core.ProfileFields.CopySnapshot
  local originalDB = config.GetDB()
  local originalProfile = copy(originalDB)
  local function Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
  end
  local sparse = {}
  local first = UF.ResolveBarGloss(sparse, sparse, "health")
  local second = UF.ResolveBarGloss(sparse, sparse, "health")
  Check(first ~= second, "public three-argument resolver shared its result")
  first.strength = 1
  Check(second.enabled == false and second.strength == 0.5 and next(sparse) == nil,
    "public result mutation escaped or materialized defaults")
  local profile = copy(originalDB)
  local fields = { "healthGlossEnabled", "healthGlossStrength", "powerGlossEnabled", "powerGlossStrength" }
  for _, owner in ipairs({ "general", "player", "target" }) do
    for _, key in ipairs(fields) do profile[owner][key] = nil end
  end
  profile.player.hlOverride, profile.target.hlOverride = nil, nil
  env.MSUF_DB = profile
  config.Refresh()
  local records = {}
  for _, unit in ipairs({ "player", "target" }) do
    local compiled = config.GetSpec(unit)
    records[unit] = { spec = compiled, health = compiled.health, power = compiled.power, text = compiled.text,
      hpGloss = compiled.health.barGloss, powerGloss = compiled.power.barGloss }
  end
  Check(records.player.hpGloss ~= records.player.powerGloss and records.target.hpGloss ~= records.target.powerGloss,
    "health and power shared a compiled Gloss record")
  Check(records.player.hpGloss ~= records.target.hpGloss and records.player.powerGloss ~= records.target.powerGloss,
    "units shared compiled Gloss records")
  local function Recompile(label, expected)
    local saved = copy(profile)
    for _, previous in pairs(records) do
      previous.health.retiredKey, previous.power.retiredKey, previous.text.retiredKey = true, true, true
    end
    config.Refresh()
    for unit, previous in pairs(records) do
      local compiled, values = config.GetSpec(unit), expected[unit]
      Check(compiled == previous.spec, label .. ": root spec identity changed")
      Check(compiled.health ~= previous.health and compiled.power ~= previous.power and compiled.text ~= previous.text,
        label .. ": domain tables survived the root wipe")
      Check(compiled.health.retiredKey == nil and compiled.power.retiredKey == nil and compiled.text.retiredKey == nil,
        label .. ": stale domain key survived compilation")
      Check(compiled.health.barGloss == previous.hpGloss and compiled.power.barGloss == previous.powerGloss,
        label .. ": repeated compile allocated new Gloss records")
      Check(previous.hpGloss.enabled == values[1] and previous.hpGloss.strength == values[2], label .. ": health values stale")
      Check(previous.powerGloss.enabled == values[3] and previous.powerGloss.strength == values[4], label .. ": power values stale")
      for _, material in ipairs({ previous.hpGloss, previous.powerGloss }) do
        local count = 0
        for key in pairs(material) do
          Check(key == "enabled" or key == "strength", label .. ": compiled Gloss gained an unrelated field")
          count = count + 1
        end
        Check(count == 2, label .. ": compiled Gloss lost a field")
      end
      previous.health, previous.power, previous.text = compiled.health, compiled.power, compiled.text
    end
    Check(Equal(profile, saved), label .. ": compiler mutated the saved profile")
  end
  Recompile("sparse defaults", { player = { false, 0.5, false, 0.5 }, target = { false, 0.5, false, 0.5 } })
  profile.general.healthGlossEnabled, profile.general.healthGlossStrength = true, 0.8
  profile.general.powerGlossEnabled, profile.general.powerGlossStrength = true, 0.2
  profile.player.hlOverride, profile.player.healthGlossEnabled = false, false
  profile.target.hlOverride, profile.target.healthGlossEnabled, profile.target.powerGlossStrength = true, false, 0
  Recompile("false zero and inheritance", { player = { true, 0.8, true, 0.2 }, target = { false, 0.8, true, 0 } })
  profile.target.hlOverride = false
  profile.general.healthGlossEnabled, profile.general.healthGlossStrength = false, 0
  profile.general.powerGlossEnabled, profile.general.powerGlossStrength = false, 1
  Recompile("disabled override", { player = { false, 0, false, 1 }, target = { false, 0, false, 1 } })
  local oldProfile, oldSaved = profile, copy(profile)
  profile = copy(originalDB)
  profile.general.healthGlossEnabled, profile.general.healthGlossStrength = true, 0.35
  profile.general.powerGlossEnabled, profile.general.powerGlossStrength = true, 0.9
  profile.player.hlOverride = false
  profile.target.hlOverride, profile.target.healthGlossEnabled, profile.target.healthGlossStrength = true, true, 0.6
  profile.target.powerGlossEnabled, profile.target.powerGlossStrength = false, nil
  env.MSUF_DB = profile
  Recompile("profile replacement", { player = { true, 0.35, true, 0.9 }, target = { true, 0.6, false, 0.9 } })
  Check(Equal(oldProfile, oldSaved), "new profile compile mutated the previous profile")
  local preview, other = config.CompileSpec("target", {}), config.CompileSpec("target", {})
  local hp, power = preview.health.barGloss, preview.power.barGloss
  local health, powerDomain = preview.health, preview.power
  Check(hp ~= records.target.hpGloss and power ~= records.target.powerGloss,
    "preview shared the live spec's compiled material")
  Check(hp ~= other.health.barGloss and power ~= other.power.barGloss and hp ~= power,
    "independent previews shared compiled materials")
  profile.target.healthGlossStrength, profile.target.powerGlossEnabled, profile.target.powerGlossStrength = 0.17, true, 0.23
  local saved = copy(profile)
  preview.health.retiredKey, preview.power.retiredKey = true, true
  Check(config.CompileSpec("target", preview) == preview, "preview root was replaced")
  Check(preview.health ~= health and preview.power ~= powerDomain,
    "preview reused a domain table")
  Check(preview.health.retiredKey == nil and preview.power.retiredKey == nil, "preview kept a stale domain key")
  Check(preview.health.barGloss == hp and preview.power.barGloss == power, "preview lost its owned Gloss records")
  Check(hp.enabled == true and hp.strength == 0.17 and power.enabled == true and power.strength == 0.23,
    "preview retained old profile values")
  Check(records.target.hpGloss.strength == 0.6 and records.target.powerGloss.enabled == false,
    "preview compile mutated the live spec")
  Check(other.health.barGloss.strength == 0.6 and other.power.barGloss.enabled == false,
    "preview compile mutated a sibling preview")
  Check(Equal(profile, saved) and Equal(originalDB, originalProfile), "compiler changed a saved profile")
  env.MSUF_DB = originalDB
  config.Refresh()
end
CompilerGlossLifecycle()
print("bar gloss runtime smoke: " .. flavor .. " PASS (" .. checks .. " checks; no off-path regions or repeat writes)")
