--- UnitFrames/Engine/MSUF_UF_UnitScene.lua
--- Static unit preview scenes: one plain Button per unit key, painted from a mock sample. The frame holds no unit while
--- it applies and is in no registry. Interface, sample fields, lifecycle: docs/PREVIEW_RUNTIME_RULES.md.
local _, MSUF = ...
MSUF.UF = MSUF.UF or {}
local UF = MSUF.UF
local FILE = "UnitFrames/Engine/MSUF_UF_UnitScene.lua"
local UnitScene = {}
UF.UnitScene = UnitScene

local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local type, pairs = type, pairs
local setmetatable = setmetatable
local floor, max, min = math.floor, math.max, math.min

local Scene = {}
Scene.__index = Scene
local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

-- Enum.PowerType ids of the sample power types.
local MANA, RAGE, FOCUS, ENERGY = 0, 1, 2, 3
-- UnitReaction values of the sample reactions (the portrait border colours by them).
local REACTION_VALUE = { friendly = 5, neutral = 4, enemy = 2 }

--- The static sample of each unit family (fields: docs/PREVIEW_RUNTIME_RULES.md). Data only; the elements never ask the client.
local SAMPLES = {
  player = { name = "Midnight", player = true, class = "ROGUE", race = "Night Elf", level = 80, hp = 0.72, power = 0.52,
    powerType = ENERGY, powerToken = "ENERGY", powerMax = 100, incoming = 0.14, absorb = 0.10, healAbsorb = 0.07, reducedMax = 0.1, leader = true,
    raidTarget = 8, raidGroup = 2, pvp = "Alliance", resting = true, combat = true,
    portrait = "Interface\\ICONS\\Ability_Stealth" },
  target = { name = "Astral Warden", class = "MAGE", race = "Construct", level = 82, hp = 0.41, power = 0.68,
    powerType = MANA, powerToken = "MANA", powerMax = 240000, incoming = 0.14, absorb = 0.10, healAbsorb = 0.07, reducedMax = 0.1, reaction = "neutral",
    npcKind = "npcCaster", classification = "elite", raidTarget = 1, inline = "Moonlit Tank",
    portrait = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
  focus = { name = "Voidcaller", class = "WARLOCK", race = "Orc", level = 81, hp = 0.63, power = 0.81, powerType = MANA,
    powerToken = "MANA", powerMax = 240000, incoming = 0.14, absorb = 0.10, healAbsorb = 0.07, reducedMax = 0.1, reaction = "enemy",
    classification = "rareelite", raidTarget = 5, portrait = "Interface\\ICONS\\Spell_Shadow_Metamorphosis" },
  targettarget = { name = "Moonlit Tank", player = true, class = "WARRIOR", race = "Human", level = 80, hp = 0.88,
    power = 0.36, powerType = RAGE, powerToken = "RAGE", powerMax = 100,
    portrait = "Interface\\ICONS\\Ability_Warrior_DefensiveStance" },
  focustarget = { name = "Marked Add", class = "WARRIOR", race = "Orc", level = 81, hp = 0.57, power = 0.24,
    powerType = RAGE, powerToken = "RAGE", powerMax = 100, reaction = "enemy", npcKind = "npcRegular",
    portrait = "Interface\\ICONS\\Ability_Warrior_Charge" },
  pet = { name = "Companion", class = "HUNTER", race = "Beast", level = 80, hp = 0.79, power = 0.44, powerType = FOCUS,
    powerToken = "FOCUS", powerMax = 100, reaction = "friendly", npcKind = "npcRegular",
    portrait = "Interface\\ICONS\\Ability_Hunter_BeastCall" },
  pettarget = { name = "Hunted Foe", class = "WARRIOR", race = "Orc", level = 81, hp = 0.57, power = 0.24,
    powerType = RAGE, powerToken = "RAGE", powerMax = 100, reaction = "enemy", npcKind = "npcRegular",
    portrait = "Interface\\ICONS\\Ability_Warrior_Charge" },
  boss = { name = "Boss Preview", class = "DEATHKNIGHT", race = "Undead", level = -1, hp = 0.55, power = 0.35,
    powerType = MANA, powerToken = "MANA", powerMax = 240000, incoming = 0.14, absorb = 0.10, healAbsorb = 0.07, reaction = "enemy", npcKind = "npcBoss",
    classification = "worldboss", raidTarget = 8, portrait = "Interface\\ICONS\\Achievement_Boss_LichKing" },
  arena = { name = "Arena Opponent", player = true, class = "MAGE", race = "Human", level = 80, hp = 0.65, power = 0.80,
    powerType = MANA, powerToken = "MANA", powerMax = 240000, reaction = "enemy", pvp = "Horde",
    portrait = "Interface\\ICONS\\Spell_Frost_FrostBolt02" },
}
UnitScene.SAMPLES = SAMPLES
UnitScene.HEALTH_MAX = 1000000

--- The family of a unit token: boss1..5 share the boss sample, arena1..N the arena sample.
local function FamilyOf(unit)
  if type(unit) ~= "string" then return nil end
  if SAMPLES[unit] then return unit end
  if unit:find("^boss%d+$") then return "boss" end
  if unit:find("^arena%d+$") then return "arena" end
  return nil
end

--- The unit token a scene of `unitKey` stands for; nil when this client has no such frame. "boss" and "arena" are slot 1.
function UnitScene.Normalize(unitKey)
  if unitKey == "boss" then unitKey = "boss1" elseif unitKey == "arena" then unitKey = "arena1" end
  if not (FamilyOf(unitKey) and UF.IsManagedUnit and UF.IsManagedUnit(unitKey)) then return nil end
  return unitKey
end

local function Translate(text)
  local translate = MSUF.Translate
  if type(translate) == "function" then return translate(text) end
  return text
end

local function Merge(base, override)
  local sample = {}
  for key, value in pairs(base) do sample[key] = value end
  if type(override) == "table" then
    for key, value in pairs(override) do sample[key] = value end
  end
  return sample
end

-- The unit elements a scene paints. Castbar and class power are the next scene package's; the auras are stand-ins.
local SCENE_ELEMENTS = {
  "Health", "TempMaxHealth", "Power", "Portrait", "Prediction", "StatusIndicators", "RaidMarkerIndicator",
  "LeaderIndicator", "LevelIndicator", "BossNumberIndicator", "RaidGroupIndicator", "EliteIndicator",
  "StatusTextIndicator", "CombatIndicator", "RestingIndicator", "IncomingResIndicator", "PVPIndicator",
  "StanceIndicator", "Borders", "Text", "NameText", "HealthText", "PowerText", "InlineToT", "Alpha",
  "PetHappinessIndicator", "PetXPBar", "ThreatIndicator",
}
local SCENE_MASK = {}
for i = 1, #SCENE_ELEMENTS do SCENE_MASK[SCENE_ELEMENTS[i]] = true end
UnitScene.ELEMENTS = SCENE_ELEMENTS
-- The elements with a sample mode of their own (status.testMode).
local TEST_MODE_ELEMENTS = { "ThreatIndicator", "PetHappinessIndicator", "PetXPBar" }

local function NewFrame(scene)
  local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
  local frame = PixelLayoutRegion(CreateFrame("Button", nil, scene.root.parent))
  frame:EnableMouse(false)
  frame._msufPreviewScope, frame._msufPreviewScene, frame._msufCoreVisible = true, scene, true
  -- Not a unit: the boss bar snap reads it (Factory IsBossFrame) to lay the bars out like its unit's.
  frame._msufSceneUnit = scene.unit
  frame:Hide()
  return frame
end

--- Open the paint window: the frame stands for its unit and its identity cache is the sample, so the engine's own
--- readers (class, player, NPC kind, dead, connected) answer from it without a client query.
local function OpenWindow(frame, unit, sample)
  local state = frame._msufUnitState
  if not state then
    state = {}
    frame._msufUnitState = state
  end
  local token = (frame._msufDispatchToken or 0) + 1
  frame._msufDispatchToken = token
  frame._msufDispatchActive = true
  frame.MSUFUnitKey, frame.unitKey = unit, unit
  state.unit, state.dispatchToken, state.ready = unit, token, true
  state.exists, state.existsKnown = true, true
  state.identityExistsRead = true
  state.dead, state.deadKnown = sample.dead == true, true
  state.identityDeadRead = true
  state.connected, state.connectedKnown = sample.offline ~= true, true
  state.identityConnectedRead = true
  local isPlayer = sample.player == true
  state.isPlayer, state.isPlayerKnown = isPlayer, true
  state.identityIsPlayerRead = true
  state.identityReady = true
  local names = LOCALIZED_CLASS_NAMES_MALE
  local className = sample.className or (sample.class and type(names) == "table" and names[sample.class])
  state.className = type(className) == "string" and className or sample.class
  state.classToken = sample.class
  sample.className = state.className
  state.identityClassRead = true
  local reaction = sample.reaction or "friendly"
  state.npcKind, state.npcKindKnown = nil, false
  -- A neutral NPC and a friendly boss keep their reaction colour (UnitNPCKind).
  local typeKind = sample.npcKind
  if reaction == "neutral" or (reaction == "friendly" and unit:find("^boss")) then typeKind = nil end
  state._npcKindTypeReady, state._npcKindType = true, typeKind or reaction
  state._npcKindReactionReady, state._npcKindReaction = true, reaction
  state._tapDeniedReady, state._tapDenied = true, false
  state._bossDispositionReady, state._bossDisposition = true, reaction == "friendly" and "friendly" or "hostile"
  state.npcClassRead = true
  state.npcClassEligible = (not isPlayer and reaction == "friendly" and sample.class) and true or nil
  state.npcClass = state.npcClassEligible and sample.class or nil
  state.npcClassSecret = nil
end

local function CloseWindow(frame)
  frame._msufDispatchActive = nil
  frame.MSUFUnitKey, frame.unitKey = nil, nil
end

-- The slot writers' percent source while a sample paints.
local samplePercent = 0
local function SamplePercent()
  return samplePercent
end

--- Health, power and absorb text of the sample, through the live slot writers and colours.
local function PaintTexts(frame, unit, sample, hp, hpMax, power, powerMax)
  local text = MSUF.UFText
  local rt = frame._msufTextRuntime
  if not (text and rt) then return end
  rt.healthMissing = max(0, hpMax - hp)
  rt.healthAbsorb = floor(hpMax * (sample.absorb or 0) + 0.5)
  samplePercent = hp * 100 / hpMax
  text.UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, SamplePercent, rt.healthNeedsPercent, rt)
  if (rt.healthAbsorbSlotCount or 0) > 0 then
    text.UpdateTextSlots(rt.healthAbsorbSlots, rt.healthAbsorbSlotCount, nil, nil, unit, nil, false, rt)
  end
  if rt.healthColorByClass == true then
    text.UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
  elseif rt.healthColorByHealth == true then
    text.SetSampleHealthTextColor(frame, rt, hp, hpMax)
  end
  samplePercent = power * 100 / powerMax
  text.UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, SamplePercent, rt.powerNeedsPercent, rt)
  if rt.powerColorByType == true then
    local r, g, b = text.PowerColor(frame, unit, sample.powerType, sample.powerToken, true)
    text.SetPowerTextColor(frame, r, g, b, rt.textColorA or 1)
  end
end

--- Threat percent, pet happiness and pet experience show their sample mode on the scene's private spec.
local function PaintTestModeElements(frame, unit)
  local status = frame.MSUFSpec and frame.MSUFSpec.status
  local active = frame._msufActiveElements
  if not (status and active) then return end
  local held = status.testMode
  status.testMode = true
  for i = 1, #TEST_MODE_ELEMENTS do
    local name = TEST_MODE_ELEMENTS[i]
    local element = active[name] == true and UF.elements[name]
    if element and element.Update then element.Update(frame, "MSUF_SAMPLE", unit) end
  end
  status.testMode = held
end

--- Paint the sample into one applied frame; the window is open.
local function PaintSample(frame, unit, sample, layout)
  local elements = UF.elements
  local active = frame._msufActiveElements or {}
  local hpMax = sample.hpMax or UnitScene.HEALTH_MAX
  local fraction = min(1, max(0, sample.hp or 1))
  local hp = sample.hpCur or floor(hpMax * fraction + 0.5)
  fraction = hp / hpMax
  local health = elements.Health
  if health and health.PaintSample then health.PaintSample(frame, unit, hp, hpMax) end
  local powerMax = sample.powerMax or 100
  local power = sample.powerCur or floor(powerMax * min(1, max(0, sample.power or 0)) + 0.5)
  local powerElement = elements.Power
  if powerElement and powerElement.PaintSample and frame.targetPowerBar then
    powerElement.PaintSample(frame, unit, power, powerMax, sample.powerType, sample.powerToken)
  end
  local prediction = elements.Prediction
  if prediction and active.Prediction == true and prediction.PaintSample then
    local paint = layout ~= false and prediction.PaintSample or prediction.PaintSampleData
    paint(frame, fraction * 100, (sample.incoming or 0) * 100, (sample.absorb or 0) * 100,
      (sample.healAbsorb or 0) * 100)
  end
  local tempMax = elements.TempMaxHealth
  if tempMax and active.TempMaxHealth == true then
    tempMax.Update(frame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", unit, sample.reducedMax or 0)
  end
  local text = MSUF.UFText
  if frame.nameText and frame.nameText:IsShown() then
    frame._msufPreviewNameText = Translate(sample.name)
    -- The name pass would refresh the inline text from the client: mark it owned, the sample paints it below.
    frame._msufIdentityInlineToTScheduled = true
    text.UpdateName(frame, "MSUF_SAMPLE", unit)
    frame._msufIdentityInlineToTScheduled = nil
  end
  if active.InlineToT == true then
    text.PaintSampleInline(frame, sample.inline and Translate(sample.inline) or nil)
  end
  PaintTexts(frame, unit, sample, hp, hpMax, power, powerMax)
  local status = frame.MSUFSpec and frame.MSUFSpec.status
  local runtime = MSUF.UFStatusRuntime
  if status and runtime then
    runtime.PaintSampleIdentityTexts(frame, status, sample)
    runtime.PaintSampleIndicators(frame, status, sample)
    runtime.UpdateBossNumber(frame, status)
    if sample.statusSelection then runtime.PaintSceneStatus(frame, status, sample.statusSelection, sample) end
  end
  local portrait = elements.Portrait
  if portrait and portrait.PaintSample and active.Portrait == true then portrait.PaintSample(frame, sample) end
  PaintTestModeElements(frame, unit)
  if sample.bossTargetPreview then elements.Borders.PaintScene(frame, unit) end


end

local LAYER_REGIONS = {
  health = { "hpBar", "healthBackgroundBar", "healthLossTrail" },
  border = { "border" },
  power = { "targetPowerBar", "powerBarBG", "powerLossTrail" },
  nameText = { "nameText", "totInlineSep", "totInlineText", "_msufNameDotsFS", "_msufInlineDotsFS" },
  hpText = { "hpTextLeft", "hpTextCenter", "hpText" }, powerText = { "powerTextLeft", "powerTextCenter", "powerText" },
  portrait = { "MSUFPortraitHolder" },
  dispelOverlay = { "_msufSceneDispelOverlay" }, dispelSymbol = { "_msufSceneDispelSymbol" },
  status = { "raidTargetIcon", "leaderIcon", "assistIcon", "eliteIcon", "levelText", "raceText", "classStatusText",
    "raidGroupNameText", "bossNumberText", "statusAFKTimerText", "combatStateIndicatorIcon",
    "restingIndicatorIcon", "incomingResIndicatorIcon", "pvpIndicatorIcon",
    "petHappinessIndicatorHolder", "petXPBar", "threatIndicatorHolder", "stanceIndicatorText", "_msufScene_statusText", "_msufScene_statusGhostText",
    "_msufScene_statusAFKText", "_msufScene_statusDNDText" },
}
function Scene:RestoreLayers()
  if self.hidden then
    for region in pairs(self.hidden) do
      region:Show()
      self.hidden[region] = nil
    end
  end
end
function Scene:FilterLayers()
  local frame, visible = self.frame, self.layerVisible
  if not (frame and visible) then return end
  local hidden = self.hidden or {}
  self.hidden = hidden
  local function Hide(region)
    if region and region:IsShown() then
      hidden[region] = true
      region:Hide()
    end
  end
  for layer, fields in pairs(LAYER_REGIONS) do
    if visible[layer] == false then for i = 1, #fields do Hide(frame[fields[i]]) end end
  end
  if visible.health == false then
    local trail = frame.healthLossTrail
    local pool = trail and trail._msufLossTrailPool
    for i = 1, pool and #pool or 0 do Hide(pool[i]) end
  end
  if visible.power == false then
    local bar = frame.targetPowerBar
    Hide(bar and bar.MSUFPowerBorderHost)
    local trail = frame.powerLossTrail
    local pool = trail and trail._msufLossTrailPool
    for i = 1, pool and #pool or 0 do Hide(pool[i]) end
  end
  for key, host in pairs(frame._msufGFFrameAuraPreviewHosts or {}) do
    if visible[key] == false or (key ~= "buff" and key ~= "debuff" and visible.auras == false) then Hide(host) end
  end
  local effectLayer = self.sample.frameEffectLayer
  if (effectLayer and visible[effectLayer] == false) or (not effectLayer and visible.auras == false) then Hide(frame._msufSceneEffectOwner) end
  if visible.auras == false then
    for _, region in pairs(frame._msufGFSpellIndicatorPreviews or {}) do
      Hide(region)
      Hide(region._frameEffectOwner)
    end
  end
  if visible.texLayer == false then
    for _, holder in pairs(frame._msufTexLayers or {}) do Hide(holder) end
  end
end
function Scene:SetLayerFilter(visible)
  self:RestoreLayers()
  self.layerVisible = visible
  self:FilterLayers()
end

function Scene:Frame()
  if not self.frame then self.frame = NewFrame(self) end
  return self.frame
end

function Scene:Unit() return self.unit end
function Scene:Sample() return self.sample end
function Scene:IsActive() return self.frame ~= nil and self.shown == true end

-- A warm menu repaint reuses its private spec. Capture the saved inputs (including nested profile tables), never
-- the live compiled spec: sliders can paint before the debounced live apply. No allocation on an unchanged read.
local function SettingsChanged(source, saved)
  local changed = false
  for key, value in pairs(source) do
    if type(value) == "table" then
      local child = saved[key]
      if type(child) ~= "table" then
        child = {}
        saved[key] = child
        changed = true
      end
      if SettingsChanged(value, child) then changed = true end
    elseif saved[key] ~= value then
      saved[key] = value
      changed = true
    end
  end
  for key in pairs(saved) do
    if source[key] == nil then
      saved[key] = nil
      changed = true
    end
  end
  return changed
end
function Scene:Compile()
  local db = UF.Config.GetDB()
  local inputs = self.inputs or {}
  self.inputs = inputs
  inputs.unit = UF.Config.GetUnitDB(self.unit)
  inputs.general, inputs.bars = db.general, db.bars
  inputs.classColors, inputs.powerColors = db.classColors, db.powerColors
  inputs.auras = db.auras3
  inputs.shortenNames = db.shortenNames
  inputs.inlineTarget = self.unit == "target" and db.targettarget or nil
  local saved = self.savedInputs or {}
  self.savedInputs = saved
  local changed = SettingsChanged(inputs, saved)
  if not self.spec or changed or self.serial ~= UF.Config.serial then
    self.serial = UF.Config.serial
    self.spec = UF.Config.CompileSpec(self.unit, self.spec)
    local p = self.spec and self.spec.portrait
    if p and p.blizzardCorner then
      if MSUF.Client.IsVanilla then self.cornerAvailable = false end
      if self.cornerAvailable == nil then
        local info = C_Texture and C_Texture.GetAtlasInfo
        self.cornerAvailable = MSUF.Client.IsForever == true
          or (info and info("UI-HUD-UnitFrame-Player-PortraitOn-CornerEmbellishment") ~= nil) or false
      end
      p.blizzardCornerAvailable = self.cornerAvailable
    end
  end
  return self.spec
end

--- Re-apply the spec (compiled now into this scene's own table) and paint the sample.
function Scene:Refresh()
  if InCombat() or self.shown ~= true then return false end
  local unit = self.unit
  local spec = self:Compile()
  if not spec then return false end
  self.spec = spec
  self:RestoreLayers()
  local frame = self:Frame()
  local sample = self.sample
  -- The health visual root cannot be built in combat; a refresh never runs there.
  UF.EnsureHealthVisualRoot(frame)
  frame.MSUFSpec = spec
  frame._msufCoreSpecEnabled = spec.enabled ~= false
  frame.configKey = spec.key
  frame._msufPortraitSampleClass = sample.class
  frame._msufSampleReaction = REACTION_VALUE[sample.reaction or "friendly"]
  frame._msufSamplePortraitArt = sample.portraitTexture or (sample.player ~= true and sample.portrait or nil)
  if frame._msufSceneWidth ~= spec.width or frame._msufSceneHeight ~= spec.height then
    frame._msufSceneWidth, frame._msufSceneHeight = spec.width, spec.height
    frame:SetSize(spec.width, spec.height)
  end
  if not frame._msufScenePlaced then
    frame._msufScenePlaced = true
    frame:SetPoint("CENTER", self.root.parent, "CENTER", 0, 0)
  end
  -- A paint that failed left its window open; the apply must not hold the unit.
  CloseWindow(frame)
  local layers = UF.Layers
  layers.SetLevelBias(self.level or 0)
  UF.ApplySceneSpec(frame, spec, SCENE_MASK, "single", unit)
  local rounded = UF.Decorators.RoundedFrames
  if rounded and rounded.active then
    OpenWindow(frame, unit, sample)
    rounded.Apply(frame)
    CloseWindow(frame)
  end
  layers.SetLevelBias(0)
  self:RefreshData(true)
  frame:Show()
  return true
end

--- Paint the sample again; no spec and no layout.
function Scene:RefreshData(layout)
  if InCombat() or self.shown ~= true or not self.frame then return false end
  self:RestoreLayers()
  local layers = UF.Layers
  layers.SetLevelBias(self.level or 0)
  local frame, unit, spec = self.frame, self.unit, self.frame.MSUFSpec
  local sample = self.sample
  if self.root.animating then
    local animated = self.animatedSample or {}
    self.animatedSample = animated
    for key in pairs(animated) do animated[key] = nil end
    for key, value in pairs(sample) do animated[key] = value end
    local state = MSUF.Require("MSUF_BuildPreviewAnimationFrameState", FILE)(frame, 1, unit, self.animationState or {}, self.root.elapsed)
    self.animationState = state
    animated.hp, animated.power = state.hpPct, state.powerPct
    animated.hpCur, animated.powerCur = nil, nil
    sample = animated
  end
  local auraEnabled = spec.auras and spec.auras.enabled == true or false
  if layout == true or (layout ~= false and self.auraEnabled ~= auraEnabled) then
    self.auraEnabled = auraEnabled
    local gf = MSUF.GF
    if gf and gf.PreviewUnitFrameAuras then gf.PreviewUnitFrameAuras(frame, unit, spec, 1) end
    local auras = MSUF.MSUF_Auras3
    if auras and auras.PaintSceneEffects then
      local cfg = auras.ResolveAuraPreviewConfig(frame, unit, spec)
      auras.PaintSceneEffects(frame, cfg and cfg.sensors)
    elseif auras and auras.ClassicVisuals then
      local cfg = auras.ResolveAuraPreviewConfig(frame, unit, spec)
      local visual, native = cfg and cfg.visual, auras.ClassicVisuals
      local present = self.dispelTypes
      if not present then
        present = {}
        self.dispelTypes = present
        for i = 1, #native.DispelTypes do present[native.DispelTypes[i]] = true end
      end
      native.UpdateDispelOverlay(frame, visual, visual and visual.overlayEnabled,
        visual and visual.r, visual and visual.g, visual and visual.b, 1)
      native.UpdateDispelSymbols(frame, visual, present)
      frame._msufSceneDispelOverlay = frame._msufA3ClassicDispelOverlayHost
      frame._msufSceneDispelSymbol = frame._msufA3ClassicDispelSymbolHost
    end
  end
  if layout ~= false then
    local auras = MSUF.MSUF_Auras3
    local effects = auras and auras.SpellIndicators
    local owner = frame._msufSceneEffectOwner
    if effects and sample.frameEffect then
      if not owner then
        local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
        owner = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        owner:EnableMouse(false)
        owner:SetAllPoints(frame)
        frame._msufSceneEffectOwner = owner
      end
      effects.ApplyPreviewFrameEffect(owner, sample.frameEffect, frame)
      owner:Show()
    elseif effects and owner then effects.HidePreviewFrameEffect(owner) end
  end
  OpenWindow(frame, unit, sample)
  PaintSample(frame, unit, sample, layout)
  local gf = MSUF.GF
  if gf and gf.AnimateUnitFrameAuras then gf.AnimateUnitFrameAuras(frame, self.root.animating and self.root.elapsed or nil) end
  CloseWindow(frame)
  if MSUF.TextureLayer and MSUF.TextureLayer.PaintSample then
    MSUF.TextureLayer.PaintSample(frame, unit, sample.hpCur or (sample.hp or 1) * (sample.hpMax or UnitScene.HEALTH_MAX),
      sample.hpMax or UnitScene.HEALTH_MAX, sample.class)
  end
  -- The paint can build regions the opacity pass has not seen (the threat text): settle it again, without the unit.
  local alpha = UF.elements.Alpha
  if alpha and frame._msufActiveElements and frame._msufActiveElements.Alpha == true then
    alpha.SceneApply(frame, frame.MSUFSpec)
  end
  self:FilterLayers()
  layers.SetLevelBias(0)
  return true
end

function Scene:Show()
  self.want = true
  if InCombat() or self.root.host.active ~= true then return false end
  self.shown = true
  return self:Refresh()
end

--- An explicit hide forgets the wanted state: only combat hides a scene without forgetting it.
function Scene:Hide()
  self.want = nil
  return self:Conceal()
end

function Scene:Conceal()
  self.shown = nil
  local frame = self.frame
  if frame then
    frame:Hide()
    local gf = MSUF.GF
    if gf then
      gf.HideFrameAuras(frame)
      gf.HideSpellIndicators(frame)
    end
    local auras = MSUF.MSUF_Auras3
    local effects = auras and auras.SpellIndicators
    if effects and frame._msufSceneEffectOwner then effects.HidePreviewFrameEffect(frame._msufSceneEffectOwner) end
  end
  return true
end

--- A new sample (merged over the unit's own; nil restores it).
function Scene:SetSample(sample, noRefresh)
  self.override = type(sample) == "table" and sample or nil
  self.sample = Merge(SAMPLES[FamilyOf(self.unit)], self.override)
  if noRefresh == true or self.shown ~= true then return false end
  return self:Refresh()
end

function Scene:SetParent(parent)
  if self.frame then
    self.frame:SetParent(parent)
    self.frame._msufScenePlaced = nil
  end
end

--- Forget the scene: its frame is hidden and stays with the scene's table, which the root drops.
function Scene:Release()
  self:Hide()
end

function UnitScene.New(root, unit, sample)
  local scene = setmetatable({ root = root, unit = unit }, Scene)
  scene.sample = Merge(SAMPLES[FamilyOf(unit)], sample)
  scene.override = sample
  return scene
end
