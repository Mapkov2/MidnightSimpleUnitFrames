local _, MSUF = ...
local Surface = {}
local EMPTY_SAMPLE = {}
MSUF.UF.PreviewSurfaces.ClassPower = Surface
local function Noop() end
local function False() return false end
local function SceneFrame(kind, _, parent)
  local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "ClassPowerScene")
  return PixelLayoutRegion(CreateFrame(kind, nil, parent))
end

local function Sample(scene) return scene.opts.sample or EMPTY_SAMPLE end
local function Count(scene) return tonumber(Sample(scene).count) or 3 end

local function Resolve(scene, config)
  local sample = Sample(scene)
  local route = scene.route
  route.class = sample.class or "ROGUE"
  route.playerClass, route.spec = route.class, sample.spec or 1
  route.primaryPower = sample.primaryPower or (route.class == "DRUID" and route.spec == 2 and 3 or 0)
  route.formID, route.config = sample.formID, config
  local provider = MSUF.CPClient
  if provider and not provider.CreateSampleResolver then
    local _, power, mode, aura = provider.Resolve(route)
    return power, mode, aura
  end
  if scene.routeClass ~= route.class then
    scene.resolveSample = (provider or MSUF.ClassPowerConfig).CreateSampleResolver(route)
    scene.routeClass = route.class
  end
  return scene.resolveSample()
end

local function Build(scene, frame)
  local K = MSUF.CPConst or _G.MSUF_CP_CONST
  local builders = _G.MSUF_CP_CORE_BUILDERS
  local config = {}
  scene.compileConfig = MSUF.ClassPowerConfig.CreateCompiler(config)
  scene.compileConfig()
  local CP = { scene = true, bars = {}, ticks = {}, maxBars = 0, slotR = {}, slotG = {}, slotB = {},
    chargedMap = {}, filledAlpha = 1, emptyAlpha = 0.3, wlPredDelta = 0, runeMap = { 1, 2, 3, 4, 5, 6 } }
  local colors = builders.CONTROLLER_COLORS({ scene = true, _cpDB = config, POWER_TYPE_TOKENS = K.POWER_TYPE_TOKENS })
  local E = { CP = CP, _cpDB = config, CPConst = K, CPK = K.CPK, PT = K.PT, CreateFrame = SceneFrame,
    sample = true, C_SpellBook = scene.route.SpellBook, motionFrame = { Hide = Noop },
    CP_ResolveTexture = MSUF.ClassPowerConfig.ResolveTexture, NotSecret = MSUF.Secrets.NotSecret,
    CP_CheckAutoHide = function(cur, max)
      local b = config.bars
      local hide = (b.classPowerHideWhenFull and cur and max and max > 0 and cur >= max)
        or (b.classPowerHideWhenEmpty and cur and cur <= 0)
      CP.container:SetAlpha(hide and 0 or 1)
    end,
    ApplyRoundedSurface = function()
      if MSUF.RoundedSurface then MSUF.RoundedSurface.ApplyClassPower(CP) end
    end,
    GetProfileScopedCache = function() return scene.layoutCache end,
    CacheScreenPosition = Noop, ApplyCachedScreenPosition = False,
    GetCooldownFrame = function(name) return scene.cooldowns[name] end,
    UnitPower = function(_, _, raw) return Count(scene) * (raw and (Sample(scene).modifier or 1) or 1) end,
    UnitPowerMax = function() return scene.maximum end,
    UnitPowerDisplayMod = function() return Sample(scene).modifier or 1 end,
    UnitPartialPower = function() return (Sample(scene).partial or 0) * 1000 end,
    UnitStagger = function() return Count(scene) end,
    UnitHealthMax = function() return scene.maximum end,
    GetSpec = function() return Sample(scene).spec or 1 end,
    GetTime = function() return Sample(scene).time or 100 end,
    GetPowerRegenForPowerType = function() return 0.2 end,
    UnitHasVehicleUI = False,
    GetRuneCooldown = function(i)
      local rune = Sample(scene).runes and Sample(scene).runes[i]
      if rune then return rune.start, rune.duration, rune.ready end
      return 0, 10, i <= Count(scene)
    end,
    CP_ApplyRuneSortOrder = function(order)
      for i = 1, 6 do CP.runeMap[i] = order == "desc" and (7 - i) or i end
    end,
    GetTrackedPlayerAura = function(id)
      local sample = Sample(scene)
      if sample.auras then return sample.auras[id] end
      if id == K.CPK.SPELL.VOID_METAMORPHOSIS then return nil end
      scene.aura.applications = Count(scene)
      return scene.aura
    end,
    C_Spell = { GetSpellCastCount = function() return Count(scene) end,
      GetSpellMaxCumulativeAuraApplications = function() return scene.maximum end },
    C_DurationUtil = {}, C_StringUtil = {}, Enum = {}, STAGGER_CONST = K.STAGGER, TIP = K.TIP,
  }
  E.globals = setmetatable({ MSUF_player = false,
    MSUF_ClassPower_ApplyRoundedSurface = E.ApplyRoundedSurface }, { __index = _G })
  E.CoreUnitFrame = False
  local migration = {}
  E.AboveCooldownGap = function(anchor, container, bars, height)
    migration.classPowerOffsetY, migration.classPowerCooldownTopAnchor = bars.classPowerOffsetY, bars.classPowerCooldownTopAnchor
    return MSUF.CPFactoryShared.Core.CP_AboveCooldownGap(anchor, container, migration, height)
  end
  E.TrackedPlayerAuras = setmetatable({}, { __index = function(_, id) return E.GetTrackedPlayerAura(id) end })
  local runeColors = MSUF.CPClient and MSUF.CPClient.SampleRuneColors
  if runeColors then
    E.RuneTypes = { colors = runeColors, Get = function(i)
      local types = Sample(scene).runeTypes
      return types and types[i] or (i - 1) % 3 + 1
    end }
  end
  scene.textLevel = MSUF.ClassPowerConfig.CreatePowerTextLevel(CP)
  scene.compileVisual = MSUF.ClassPowerConfig.CreateVisualCompiler(CP, config, colors)
  local function Maximum() return scene.maximum end
  scene.resolveMax = MSUF.ClassPowerConfig.CreateMaxResolver(Maximum,
    { GetSpellMaxCumulativeAuraApplications = Maximum }, Maximum)
  for key, value in pairs(colors) do E[key] = value end
  local build = builders.BUILD(E)
  local layout = builders.LAYOUT(E)
  E.EnsureRuneText, E.EnsureMainText = build.CP_EnsureRuneText, build.CP_EnsureMainText
  local presentation = builders.PRESENTATION(E)
  E.ApplyFont = presentation.CP_ApplyFont
  CP.cdmScaledWidth = presentation.CDM_GetScaledWidth
  build.CP_Create(frame)
  CP._pf = frame
  scene.emptyCharged = CP.chargedMap
  scene.CP, scene.config, scene.colors = CP, config, colors
  scene.build, scene.layout, scene.presentation, scene.env = build, layout, presentation, E
end

function Surface.Create(scene)
  local frame = SceneFrame("Frame", nil, scene.root.parent)
  frame._msufPreviewScope, frame._msufPreviewScene = true, scene
  scene.layoutCache, scene.cooldowns, scene.aura = {}, {}, {}
  scene.route = {
    GetSpec = function() return Sample(scene).spec or 1 end,
    GetForm = function() return Sample(scene).formID end,
    PrimaryPower = function() return scene.route.primaryPower end,
    SpellBook = { IsSpellKnown = function(id)
      local known = Sample(scene).knownSpells
      return not known or known[id] == true
    end },
  }
  scene.route.isPlayerSpell = scene.route.SpellBook.IsSpellKnown
  for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }) do
    scene.cooldowns[name] = SceneFrame("Frame", nil, frame)
  end
  Build(scene, frame)
  return frame
end

local function NativeMode(scene)
  local buttons = {}
  local sensor = {}
  function sensor.CreateClassPowerAuraSensor(proxy, _, _, onSlot)
    local button = SceneFrame("Button", nil, proxy)
    function button:CanBeAccessedInContext() return true end
    function button:SetApplicationBar(bar, opts)
      self.sampleBar = bar
      bar:SetMinMaxValues(0, opts.maxApplications)
    end
    function button:SetApplicationCount(text, opts)
      self.sampleText, self.sampleFormat = text, opts.formatter.format
    end
    function button:ClearApplicationCount() self.sampleText = nil end
    buttons[#buttons + 1] = button
    onSlot(button)
    return { SetEnabled = Noop }
  end
  local function Formatter()
    return { SetBreakpoints = function(self, points) self.format = points[1].format end }
  end
  local native = MSUF.CPBuilders.NativeAuras({ CP = scene.CP, db = scene.config,
    globals = setmetatable({ MSUF_Auras3 = sensor }, { __index = _G }), C_Secrets = {},
    C_Spell = { GetSpellMaxCumulativeAuraApplications = function() return scene.maximum end },
    C_StringUtil = { CreateNumericRuleFormatter = Formatter },
    Texture = MSUF.ClassPowerConfig.ResolveTexture, TextLevel = scene.textLevel })
  return native, function()
    native.Sync()
    for _, button in ipairs(buttons) do
      if button.sampleBar then button.sampleBar:SetValue(Count(scene)) end
      if button.sampleText then button.sampleText:SetFormattedText(button.sampleFormat, Count(scene)) end
    end
    scene.env.CP_CheckAutoHide(nil, nil)
  end
end

local function Modes(scene, class)
  if scene.modeClass == class then return end
  if scene.ironfur then scene.ironfur.SetActive(false) end
  if scene.CP.nativeAuras then scene.CP.nativeAuras.Disable() end
  scene.modePools = scene.modePools or {}
  local cached = scene.modePools[class]
  if cached then
    scene.runners, scene.ironfur, scene.CP.nativeAuras = cached.runners, cached.ironfur, cached.native
    scene.modeClass = class
    return
  end
  scene.ironfur, scene.CP.nativeAuras = nil, nil
  local E, builders = scene.env, _G.MSUF_CP_MODE_BUILDERS
  E.PLAYER_CLASS = class
  local seg, frac, aura = builders.SEGMENTED(E), builders.FRACTIONAL(E), builders.AURA(E)
  local cont, rune, stagger = builders.CONTINUOUS(E), builders.RUNE(E), builders.STAGGER(E)
  scene.runners = { Segmented = seg.Update, Fractional = frac.Update, AuraSegmented = aura.UpdateSegmented,
    AuraSingle = aura.UpdateSingle, Continuous = cont.Update, SignedContinuous = cont.UpdateSigned,
    Rune = rune.Update, Stagger = stagger.Update }
  if class == "DRUID" and builders.IRONFUR then
    local ironfur = builders.IRONFUR(E)
    scene.ironfur = ironfur
    scene.runners.Ironfur = function() return ironfur.PaintSample(Sample(scene)) end
  end
  if class == "WARRIOR" and MSUF.CPBuilders and MSUF.CPBuilders.NativeAuras then
    scene.CP.nativeAuras, scene.runners.NativeAura = NativeMode(scene)
  end
  scene.modeClass = class
  scene.modePools[class] = { runners = scene.runners, ironfur = scene.ironfur, native = scene.CP.nativeAuras }
end

function Surface.Paint(scene)
  local frame, opts, CP = scene.frame, scene.opts, scene.CP
  local cfg, shared = scene.config, MSUF.ClassPowerConfig
  scene.compileConfig()
  local b, sample = cfg.bars, Sample(scene)
  frame:SetScale(opts.scale or 1)
  frame:SetSize(opts.playerWidth or (MSUF_DB.player and MSUF_DB.player.width) or 275, opts.playerHeight or 40)
  frame:ClearAllPoints()
  frame:SetPoint(opts.point or "CENTER", scene.root.parent, opts.point or "CENTER", opts.x or 0, opts.y or 0)
  for name, proxy in pairs(scene.cooldowns) do
    local geometry = opts.cooldowns and opts.cooldowns[name]
    if geometry then
      proxy:SetSize(geometry.width, geometry.height or 40)
      proxy:SetScale(geometry.scale or 1)
      proxy:ClearAllPoints()
      proxy:SetPoint("CENTER", frame, "CENTER", geometry.x or 0, geometry.y or -100)
      proxy:Show()
    else
      proxy:Hide()
      proxy:SetSize(0, 0)
    end
  end
  local power, mode = Resolve(scene, cfg)
  local K = _G.MSUF_CP_CONST
  if scene.ironfur and mode ~= K.CPK.MODE.IRONFUR then scene.ironfur.SetActive(false) end
  if not power or mode == K.CPK.MODE.NONE or b.showClassPower == false then
    CP.visible = false
    if CP.nativeAuras then CP.nativeAuras.Disable() end
    frame:Hide()
    return
  end
  if CP.nativeAuras and mode ~= K.CPK.MODE.NATIVE_AURA then CP.nativeAuras.Disable() end
  local descriptor = K.ModeDescriptors[mode]
  scene.maximum = tonumber(sample.maximum) or (descriptor.barCount and 100 or (power == K.PT.Runes and 6 or 5))
  local slots = scene.resolveMax(power, mode)
  CP.powerType, CP.renderMode, CP.currentMax, CP.modeDescriptor = power, mode, slots, descriptor
  CP.visible = true
  CP.filledAlpha, CP.emptyAlpha = b.classPowerFilledAlpha or 1, b.classPowerEmptyAlpha or 0.3
  CP.chargedMap, CP.chargedAny = sample.charged or scene.emptyCharged, sample.charged ~= nil
  CP.spStacks, CP.spExpires, CP.wlPredDelta = Count(scene), nil, sample.predicted or 0
  scene.build.CP_EnsureBars(frame, slots)
  if b.classPowerShowText == true then scene.build.CP_EnsureMainText() end
  Modes(scene, scene.route.class)
  scene.colors.InvalidateCaches()
  scene.compileVisual(power, mode, slots)
  scene.layout.CP_Layout(frame, slots, shared.ResolveHeight(b), power)
  scene.presentation.CP_RefreshTexture()
  scene.presentation.CP_ApplyFont()
  local paint = assert(scene.runners[descriptor.updateKey], "missing class resource sample painter")
  paint(power, slots)
  CP.container:Show()
  frame:Show()
end
