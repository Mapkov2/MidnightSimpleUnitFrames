-- Instance-local runtime kernel for the embedded MSUFUnitFrames framework.
local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local Metadata = UF.Metadata or {}
local Framework = MSUF.MSUFUnitFrames or MSUF.UFCore

local type = type
local pairs = pairs
local next = next
local tostring = tostring
local tonumber = tonumber
local table_remove = table.remove
local table_concat = table.concat
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitGUID = UnitGUID
local GetTime = GetTime or function() return 0 end
local issecretvalue = _G.issecretvalue or function(_) return false end

UF.version = "8.4-demand-runtime-plans"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
UF.pendingApply = UF.pendingApply or {}
UF.pendingElementRefreshes = UF.pendingElementRefreshes or {}
UF.visualRefreshCallbacks = UF.visualRefreshCallbacks or {}
UF.elementTraits = UF.elementTraits or {}
UF.initialized = UF.initialized or false

local HOST_VALUES = UF._hostValues or _G

UF.unitOrder = UF.unitOrder or {
  "player", "target", "focus", "targettarget", "focustarget", "pet",
  "boss1", "boss2", "boss3", "boss4", "boss5",
}

UF.unitLookup = UF.unitLookup or {}
for i = 1, #UF.unitOrder do
  UF.unitLookup[UF.unitOrder[i]] = true
end

UF.configKeyUnits = UF.configKeyUnits or {
  player = { "player" },
  target = { "target" },
  focus = { "focus" },
  targettarget = { "targettarget" },
  tot = { "targettarget" },
  targetoftarget = { "targettarget" },
  focustarget = { "focustarget" },
  pet = { "pet" },
  boss = { "boss1", "boss2", "boss3", "boss4", "boss5" },
}
UF.singleUnitLists = UF.singleUnitLists or {}

local BASIC_ELEMENTS = {
  LoadConditions = true,
  Health = true,
  Power = true,
  Text = true,
  NameText = true,
  HealthText = true,
  PowerText = true,
  InlineToT = true,
}
UF.basicElements = BASIC_ELEMENTS
local FORCE_UPDATE_ELEMENTS = UF.forceUpdateElements or {}
UF.forceUpdateElements = FORCE_UPDATE_ELEMENTS
for name in pairs(BASIC_ELEMENTS) do FORCE_UPDATE_ELEMENTS[name] = true end

local EVENT_ELEMENTS = {
  -- Native AuraContainer owns steady-state UNIT_AURA deltas, but party aura
  -- access can change without a catch-up delta on range/connection edges.
  -- Auras declares only those rare, unit-filtered recovery events.
  Auras = true,
  Portrait = true,
  TempMaxHealth = true,
  Prediction = true,
  -- These elements own live state that is not covered by the basic bar/text
  -- routes or by a separate shared driver. Keep them frame-routed so their
  -- option-gated GetEvents/GetUnitlessEvents declarations actually run.
  Borders = true,
  GroupCornerIndicators = true,
  GroupStatusRuntime = true,
  GroupVisuals = true,
  -- Group range events must stay unit-filtered per frame. A shared
  -- RegisterUnitEvent subscription is capped at four unit tokens and cannot
  -- safely dispatch a secret UNIT_IN_RANGE_UPDATE unit payload.
  GroupRangeFade = true,
}

-- Status regions are structural, but their child elements own the smallest
-- possible live event routes. Keep this explicit instead of widening the hot
-- event gate to every cold-path/apply element.
local STATUS_EVENT_ELEMENTS = {
  RaidMarkerIndicator = true,
  LeaderIndicator = true,
  LevelIndicator = true,
  RaidGroupIndicator = true,
  EliteIndicator = true,
  StatusTextIndicator = true,
  CombatIndicator = true,
  RestingIndicator = true,
  IncomingResIndicator = true,
  PVPIndicator = true,
  StanceIndicator = true,
}

local IDENTITY_ELEMENTS = {
  NameText = true,
  HealthText = true,
  PowerText = true,
  InlineToT = true,
  Portrait = true,
  TempMaxHealth = true,
  Prediction = true,
  Borders = true,
  -- These values belong to the bound unit and must be reseeded when target,
  -- focus, dependent, pet, or boss identity changes. Resting is player-only
  -- and owns PLAYER_UPDATE_RESTING/PLAYER_ENTERING_WORLD directly.
  RaidMarkerIndicator = true,
  LeaderIndicator = true,
  LevelIndicator = true,
  RaidGroupIndicator = true,
  EliteIndicator = true,
  StatusTextIndicator = true,
  CombatIndicator = true,
  IncomingResIndicator = true,
  PVPIndicator = true,
}
UF.identityElements = IDENTITY_ELEMENTS

local IDENTITY_BAR_ELEMENTS = {
  Health = true,
  Power = true,
}

local HEALTH_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_CONNECTION = true,
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}

local POWER_EVENTS = {
  UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true,
  UNIT_MAXPOWER = true,
  UNIT_DISPLAYPOWER = true,
}

local GROUP_LIFECYCLE_EVENTS = {
  PARTY_MEMBER_ENABLE = true,
  PARTY_MEMBER_DISABLE = true,
}

local GROUP_THREAT_EVENTS = {
  UNIT_THREAT_SITUATION_UPDATE = true,
  UNIT_THREAT_LIST_UPDATE = true,
}

local NONPREFIX_UNIT_EVENTS = {
  INCOMING_RESURRECT_CHANGED = true,
  -- Unit payload despite the PLAYER_ prefix (AFK/DND flag edges); without this
  -- entry a frame-routed subscription would fall back to an unfiltered
  -- RegisterEvent and fire for every unit's toggle.
  PLAYER_FLAGS_CHANGED = true,
}

local BOSS_UNITS = {
  boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

UF.dependentUnitParents = UF.dependentUnitParents or {
  targettarget = "target",
  focustarget = "focus",
}

function UF.ParentUnitForDependentUnit(unit)
  return UF.dependentUnitParents and UF.dependentUnitParents[unit]
end

function UF.IsDependentUnit(unit)
  return UF.ParentUnitForDependentUnit(unit) ~= nil
end

function UF.ConfigKeyForUnit(unit)
  if BOSS_UNITS[unit] then return "boss" end
  if unit == "targetoftarget" or unit == "tot" then return "targettarget" end
  return unit
end

function UF.IsManagedUnit(unit)
  return UF.unitLookup[unit] == true
end

local function IsUnitToken(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end
UF.IsUnitToken = IsUnitToken

local function UnitExistsSafe(unit)
  if not UnitExists then return true end
  local exists = UnitExists(unit)
  if issecretvalue(exists) == true then return true end
  return exists == true or exists == 1
end
UF.UnitExistsSafe = UnitExistsSafe

local function FreshUnitState(frame, unit)
  local state = frame and frame._msufUnitState
  if state
    and state.ready == true
    and state.unit == unit
    and frame._msufDispatchActive == true
    and state.dispatchToken == frame._msufDispatchToken then
    return state
  end
  return nil
end
UF.FreshUnitState = FreshUnitState

-- Identity consumers run back-to-back inside the same frame dispatch. Keep a
-- tiny dispatch-local read-through cache for the frame's bound unit so Core,
-- bars, backgrounds, status indicators, and text do not repeat protected unit
-- API calls. The dispatch token makes the cache impossible to survive an event
-- boundary; dependent/inline units deliberately bypass it.
local function IdentityDispatchState(frame, unit)
  if not (frame and frame._msufDispatchActive == true and IsUnitToken(unit)) then
    return nil
  end
  local boundUnit = frame.MSUFUnitKey or frame.unit
  if unit ~= boundUnit then return nil end

  local state = frame._msufUnitState
  if not state then
    state = {}
    frame._msufUnitState = state
  end
  local token = frame._msufDispatchToken
  if state.identityDispatchToken ~= token or state.identityUnit ~= unit then
    state.identityDispatchToken = token
    state.identityUnit = unit
    state.identityExistsRead = nil
    state.identityIsPlayerRead = nil
    state.identityClassRead = nil
    state.identityConnectedRead = nil
    state.identityDeadRead = nil
  end
  return state
end

local function ReadUnitExistsCached(frame, unit)
  local unitState = FreshUnitState(frame, unit)
  if unitState and unitState.existsKnown ~= nil then
    return unitState.exists == true, unitState.existsKnown == true
  end

  local state = IdentityDispatchState(frame, unit)
  if state and state.identityExistsRead == true then
    return state.exists == true, state.existsKnown == true
  end

  local exists, known
  if not UnitExists then
    exists, known = true, true
  else
    local raw = UnitExists(unit)
    if issecretvalue(raw) == true then
      exists, known = true, false
    else
      exists, known = raw == true or raw == 1, true
    end
  end
  if state then
    state.identityExistsRead = true
    state.exists = exists
    state.existsKnown = known
  end
  return exists, known
end
UF.ReadUnitExistsCached = ReadUnitExistsCached

local function ReadUnitIsPlayerCached(frame, unit)
  local unitState = FreshUnitState(frame, unit)
  if unitState then
    if unitState.isPlayerKnown == true then
      return unitState.isPlayer == true, true
    end
    if unitState.identityReady == true then
      return nil, false
    end
  end

  -- FreshUnitState already proved that this is the bound unit in the current
  -- dispatch. Reuse that table directly instead of re-running the guarded
  -- identity lookup for every status/text consumer in the same target swap.
  local state = unitState or IdentityDispatchState(frame, unit)
  if state and state.identityIsPlayerRead == true then
    return state.isPlayer, state.isPlayerKnown == true
  end

  local isPlayer, known
  if UnitIsPlayer then
    local raw = UnitIsPlayer(unit)
    if issecretvalue(raw) ~= true then
      isPlayer, known = raw == true or raw == 1, true
    end
  end
  if state then
    state.identityIsPlayerRead = true
    state.isPlayer = isPlayer
    state.isPlayerKnown = known == true
  end
  return isPlayer, known == true
end
UF.ReadUnitIsPlayerCached = ReadUnitIsPlayerCached

local function ReadUnitClassCached(frame, unit)
  local state = FreshUnitState(frame, unit) or IdentityDispatchState(frame, unit)
  if state and state.identityClassRead == true then
    return state.className, state.classToken
  end

  local className, classToken
  if UnitClass then
    className, classToken = UnitClass(unit)
  end
  if state then
    state.identityClassRead = true
    state.className = className
    state.classToken = classToken
  end
  return className, classToken
end
UF.ReadUnitClassCached = ReadUnitClassCached

local function ReadConnectedCached(frame, unit, state)
  state = state or FreshUnitState(frame, unit)
  if state and state.connectedKnown == true then
    return state.connected == true, true
  end

  local dispatchState = IdentityDispatchState(frame, unit)
  if dispatchState and dispatchState.identityConnectedRead == true then
    return dispatchState.connected == true, dispatchState.connectedKnown == true
  end

  local connected, known
  if not UnitIsConnected then
    connected, known = true, true
  else
    local raw = UnitIsConnected(unit)
    if issecretvalue(raw) == true or raw == nil then
      connected, known = true, false
    else
      connected, known = raw == true or raw == 1, true
    end
  end
  if dispatchState then
    dispatchState.identityConnectedRead = true
    dispatchState.connected = connected
    dispatchState.connectedKnown = known
  end
  return connected, known
end
UF.ReadConnectedCached = ReadConnectedCached

local function ReadDeadCached(frame, unit, state)
  state = state or FreshUnitState(frame, unit)
  if state and state.deadKnown == true then
    return state.dead == true, true
  end

  local dispatchState = IdentityDispatchState(frame, unit)
  if dispatchState and dispatchState.identityDeadRead == true then
    return dispatchState.dead == true, dispatchState.deadKnown == true
  end

  local dead, known
  if not (UnitIsDeadOrGhost or UnitIsDead) then
    dead, known = false, true
  else
    local raw = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or nil
    if (issecretvalue(raw) == true or raw == nil) and UnitIsDead then
      raw = UnitIsDead(unit)
    end
    if issecretvalue(raw) == true or raw == nil then
      dead, known = false, false
    else
      dead, known = raw == true or raw == 1, true
    end
  end
  if dispatchState then
    dispatchState.identityDeadRead = true
    dispatchState.dead = dead
    dispatchState.deadKnown = known
  end
  return dead, known
end
UF.ReadDeadCached = ReadDeadCached

local function Clamp01(value, fallback)
  value = tonumber(value)
  if value == nil then value = fallback end
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end
UF.Clamp01 = Clamp01

local function NumberWithFallback(value, fallback)
  value = tonumber(value)
  return value == nil and fallback or value
end
UF.NumberWithFallback = NumberWithFallback

local function NormalizeDispelDetectTrigger(value)
  value = tostring(value or ""):upper()
  if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then
    return "BY_RAID"
  end
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
    return "DISPEL_TYPE"
  elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
    return "DISPEL_TYPE"
  elseif value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then
    return "PLAYER_CAST"
  end
  return "BY_ME"
end
UF.NormalizeDispelDetectTrigger = NormalizeDispelDetectTrigger

local function NormalizeDispelOverlayTrigger(value)
  value = tostring(value or ""):upper()
  if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
  return NormalizeDispelDetectTrigger(value)
end
UF.NormalizeDispelOverlayTrigger = NormalizeDispelOverlayTrigger

local function NormalizeDispelOverlayStyle(value)
  if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
  return "FULL"
end
UF.NormalizeDispelOverlayStyle = NormalizeDispelOverlayStyle

local function NormalizeRangeFadeLayerMode(value)
  if value == "health" or value == "hp" or value == "hpbar" or value == "HP" or value == 2 then
    return "health"
  end
  return "frame"
end
UF.NormalizeRangeFadeLayerMode = NormalizeRangeFadeLayerMode

local function NormalizeAbsorbTestScope(scope)
  scope = tostring(scope or "shared"):lower():gsub("%s+", ""):gsub("%-", "_")
  if scope == "" or scope == "all" or scope == "global" then return "shared" end
  if scope == "gf_party" or scope == "group_party" or scope == "gfparty" then return "party" end
  if scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid"
    or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then return "raid" end
  if scope == "focus_target" then return "focustarget" end
  if scope == "targetoftarget" or scope == "tot" then return "targettarget" end
  return scope
end
UF.NormalizeAbsorbTestScope = NormalizeAbsorbTestScope

local PREDICTION_TEST_CATEGORIES = {
  heal = true,
  absorb = true,
  healAbsorb = true,
  tempMaxHealth = true,
}

local function NormalizePredictionTestCategory(category)
  if category == "heal" or category == "prediction" or category == "healPrediction" then return "heal" end
  if category == "healAbsorb" or category == "negative" or category == "negativeAbsorb" then return "healAbsorb" end
  if category == "absorb" or category == "positive" or category == "positiveAbsorb" then return "absorb" end
  if category == "tempMaxHealth" or category == "maxHealthLoss" or category == "reducedMaxHealth" then return "tempMaxHealth" end
  return nil
end
UF.NormalizePredictionTestCategory = NormalizePredictionTestCategory

local function PredictionTestBucketEnabled(bucket, category)
  if type(bucket) ~= "table" then return false end
  category = NormalizePredictionTestCategory(category)
  if category then return bucket[category] == true end
  return bucket.heal == true or bucket.absorb == true or bucket.healAbsorb == true
end

local function AbsorbTextureTestEnabledForScope(scope, category)
  local modes = HOST_VALUES.MSUF_PredictionTestModes
  if type(modes) == "table" then
    local normalized = NormalizeAbsorbTestScope(scope)
    if PredictionTestBucketEnabled(modes.shared, category) then return true end
    if normalized ~= "shared" and PredictionTestBucketEnabled(modes[normalized], category) then return true end
    return normalized == "shared" and PredictionTestBucketEnabled(modes.shared, category) or false
  end
  if HOST_VALUES.MSUF_AbsorbTextureTestMode ~= true then return false end
  local wanted = NormalizeAbsorbTestScope(HOST_VALUES.MSUF_AbsorbTextureTestScope)
  return wanted == "shared" or wanted == NormalizeAbsorbTestScope(scope)
end
UF.AbsorbTextureTestEnabledForScope = AbsorbTextureTestEnabledForScope
UF.PREDICTION_TEST_CATEGORIES = PREDICTION_TEST_CATEGORIES

local function ConfigScopedValue(conf, general, key, fallback)
  if conf and conf.hlOverride == true and conf[key] ~= nil then return conf[key] end
  if general and general[key] ~= nil then return general[key] end
  return fallback
end
UF.ConfigScopedValue = ConfigScopedValue

local BORDER_PRIORITY_DEFAULTS = { "dispel", "aggro", "purge", "bossTarget" }
local BORDER_PRIORITY_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
local BORDER_PRIORITY_ALIAS = {
  Dispel = "dispel", DISPEL = "dispel", Magic = "dispel", MAGIC = "dispel",
  Curse = "dispel", CURSE = "dispel", Disease = "dispel", DISEASE = "dispel",
  Poison = "dispel", POISON = "dispel", Bleed = "dispel", BLEED = "dispel",
  Aggro = "aggro", AGGRO = "aggro", Purge = "purge", PURGE = "purge",
  BossTarget = "bossTarget", Boss_Target = "bossTarget",
  ["Boss Target"] = "bossTarget", ["boss target"] = "bossTarget",
  boss_target = "bossTarget", bosstarget = "bossTarget", BOSS_TARGET = "bossTarget",
}

local function ScopedAliasValue(conf, general, key, legacyKey, fallback)
  if conf and conf.hlOverride == true then
    if conf[key] ~= nil then return conf[key] end
    if legacyKey and conf[legacyKey] ~= nil then return conf[legacyKey] end
  end
  if general then
    if general[key] ~= nil then return general[key] end
    if legacyKey and general[legacyKey] ~= nil then return general[legacyKey] end
  end
  return fallback
end

local function CompileBorderPriority(conf, general)
  local enabled = ScopedAliasValue(conf, general, "hlPrioEnabled", "highlightPrioEnabled", false)
  enabled = enabled == true or enabled == 1 or enabled == "1"
  local raw = ScopedAliasValue(conf, general, "hlPrioOrder", "highlightPrioOrder", nil)
  local order, used = {}, {}
  if type(raw) == "table" then
    for i = 1, #raw do
      local key = raw[i]
      if type(key) == "string" then key = BORDER_PRIORITY_ALIAS[key] or key end
      if BORDER_PRIORITY_ALLOWED[key] and not used[key] then
        used[key] = true
        order[#order + 1] = key
      end
    end
  end
  for i = 1, #BORDER_PRIORITY_DEFAULTS do
    local key = BORDER_PRIORITY_DEFAULTS[i]
    if not used[key] then
      used[key] = true
      order[#order + 1] = key
    end
  end
  return enabled, order
end
UF.CompileBorderPriority = CompileBorderPriority

local function GradientKeyActive(conf, key)
  if not (conf and conf.hlOverride == true and conf.gradientOverride == true) then return false end
  if conf.gradientOverrideVersion ~= 2 then return conf[key] ~= nil end
  return type(conf.gradientOverrideKeys) == "table" and conf.gradientOverrideKeys[key] == true
end

local function GradientScopedValue(conf, general, key, fallback, legacyKey)
  if GradientKeyActive(conf, key) and conf[key] ~= nil then return conf[key] end
  if legacyKey and GradientKeyActive(conf, legacyKey) and conf[legacyKey] ~= nil then return conf[legacyKey] end
  if general and general[key] ~= nil then return general[key] end
  if legacyKey and general and general[legacyKey] ~= nil then return general[legacyKey] end
  return fallback
end

local function ResolveBarGradient(conf, general, enabledKey)
  local power = enabledKey == "enablePowerGradient"
  local useLegacyDirections = false
  if power then
    local scopedPower = GradientKeyActive(conf, "powerGradientDirLeft") or GradientKeyActive(conf, "powerGradientDirRight")
      or GradientKeyActive(conf, "powerGradientDirUp") or GradientKeyActive(conf, "powerGradientDirDown")
    local scopedLegacy = GradientKeyActive(conf, "gradientDirLeft") or GradientKeyActive(conf, "gradientDirRight")
      or GradientKeyActive(conf, "gradientDirUp") or GradientKeyActive(conf, "gradientDirDown")
    local generalPower = general and (general.powerGradientDirLeft ~= nil or general.powerGradientDirRight ~= nil
      or general.powerGradientDirUp ~= nil or general.powerGradientDirDown ~= nil)
    useLegacyDirections = not scopedPower and (scopedLegacy or not generalPower)
  end
  local prefix = power and not useLegacyDirections and "powerGradientDir" or "gradientDir"
  local left = GradientScopedValue(conf, general, prefix .. "Left", false) == true
  local right = GradientScopedValue(conf, general, prefix .. "Right", false) == true
  local up = GradientScopedValue(conf, general, prefix .. "Up", false) == true
  local down = GradientScopedValue(conf, general, prefix .. "Down", false) == true
  if not (left or right or up or down) then
    local directionKey = power and not useLegacyDirections and "powerGradientDirection" or "gradientDirection"
    local legacy = GradientScopedValue(conf, general, directionKey, "RIGHT")
    left = legacy == "LEFT"
    up = legacy == "UP"
    down = legacy == "DOWN"
    right = not (left or up or down)
  end
  local strengthKey = power and "powerGradientStrength" or "gradientStrength"
  local colorPrefix = power and "powerBarGradientColor" or "healthBarGradientColor"
  return {
    enabled = GradientScopedValue(conf, general, enabledKey, false) == true,
    strength = Clamp01(GradientScopedValue(conf, general, strengthKey, 0.45,
      power and "gradientStrength" or nil), 0.45),
    r = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "R", 0), 0),
    g = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "G", 0), 0),
    b = Clamp01(GradientScopedValue(conf, general, colorPrefix .. "B", 0), 0),
    left = left, right = right, up = up, down = down,
  }
end
UF.ResolveBarGradient = ResolveBarGradient

function UF.FillPredictionColors(dst, general, conf, scopedValue, numberFn)
  scopedValue = scopedValue or ConfigScopedValue
  numberFn = numberFn or NumberWithFallback
  dst.healR = numberFn(general and general.healPredictionColorR, 0)
  dst.healG = numberFn(general and general.healPredictionColorG, 1)
  dst.healB = numberFn(general and general.healPredictionColorB, 0)
  dst.healA = Clamp01(scopedValue(conf, general, "healPredictionBarOpacity", general and general.healPredictionColorA), 0.45)
  dst.absorbR = numberFn(general and general.absorbBarColorR, 1)
  dst.absorbG = numberFn(general and general.absorbBarColorG, 1)
  dst.absorbB = numberFn(general and general.absorbBarColorB, 1)
  dst.absorbA = Clamp01(scopedValue(conf, general, "absorbBarOpacity", general and general.absorbBarColorA), 0.75)
  dst.healAbsorbR = numberFn(general and general.healAbsorbBarColorR, 0.7)
  dst.healAbsorbG = numberFn(general and general.healAbsorbBarColorG, 0)
  dst.healAbsorbB = numberFn(general and general.healAbsorbBarColorB, 0)
  dst.healAbsorbA = Clamp01(scopedValue(conf, general, "healAbsorbBarOpacity", general and general.healAbsorbBarColorA), 1)
end

function UF.UnitsForConfigKey(key)
  local units = UF.configKeyUnits[key]
  if units then return units end
  if UF.unitLookup[key] then
    units = UF.singleUnitLists[key]
    if not units then
      units = { key }
      UF.singleUnitLists[key] = units
    end
    return units
  end
  return nil
end

function UF.FrameName(unit)
  local prefix = UF.frameNamePrefix
    or (Framework and Framework.framePrefix)
    or "MSUF"
  return tostring(prefix) .. "_" .. tostring(unit or "unknown")
end

local UPDATE_KEYS = UF._updateKeys or setmetatable({}, {
  __index = function(t, name)
    if type(name) ~= "string" then return nil end
    local key = "_msufUpdate" .. name
    t[name] = key
    return key
  end,
})
UF._updateKeys = UPDATE_KEYS

local function GetUpdateKey(name)
  return UPDATE_KEYS[name]
end

function UF.BasicElementAllowed(name)
  return BASIC_ELEMENTS[name] == true
end

local function HotElementAllowed(name)
  return BASIC_ELEMENTS[name] == true
end
UF.CoreElementAllowed = HotElementAllowed

local function EventElementAllowed(name)
  local traits = UF.elementTraits[name]
  return (traits and traits.events == true)
    or HotElementAllowed(name) == true
    or EVENT_ELEMENTS[name] == true
    or STATUS_EVENT_ELEMENTS[name] == true
end

local function ApplyElementAllowed(name)
  local traits = UF.elementTraits[name]
  if traits and traits.apply == true then return true end
  if HotElementAllowed(name) == true then return true end
  if Metadata.runtimeUpdateOwners and Metadata.runtimeUpdateOwners[name] == true then return true end
  if Metadata.defaultApplyMask and Metadata.defaultApplyMask[name] == true then return true end
  return false
end
UF.ApplyElementAllowed = ApplyElementAllowed

function UF.ElementEnabled(element, frame, spec)
  return not element or type(element.IsEnabled) ~= "function" or element.IsEnabled(frame, spec) ~= false
end

function UF.RegisterElement(name, element, traits)
  if type(name) ~= "string" or type(element) ~= "table" then return false end
  if UF.elements[name] ~= nil and UF.elements[name] ~= element then return false end
  if not UF.elements[name] then
    UF.elementOrder[#UF.elementOrder + 1] = name
  end
  UF.elements[name] = element
  Elements[name] = element
  if type(traits) == "table" then
    UF.elementTraits[name] = traits
    if traits.defaultApply == true and type(Metadata.defaultApplyMask) == "table" then
      Metadata.defaultApplyMask[name] = true
    end
    if traits.forceUpdate == true then FORCE_UPDATE_ELEMENTS[name] = true end
    if traits.identity == true then IDENTITY_ELEMENTS[name] = true end
  end
  GetUpdateKey(name)
  return true
end

local function FrameVisibleForEvent(frame)
  if not frame then return false end
  local specEnabled = frame._msufCoreSpecEnabled
  if specEnabled == nil then
    local spec = frame.MSUFSpec
    specEnabled = not spec or spec.enabled ~= false
    frame._msufCoreSpecEnabled = specEnabled
  end
  if specEnabled == false then return false end

  local visible = frame._msufCoreVisible
  if visible == true then return true end
  if HOST_VALUES.MSUF_PreviewTestMode == true
    or HOST_VALUES.MSUF_BossTestMode == true
    or HOST_VALUES.MSUF2_BossUnitframePreviewActive == true then
    return true
  end
  if visible == false then return false end

  visible = not frame.IsVisible or frame:IsVisible()
  frame._msufCoreVisible = visible and true or false
  return visible
end
UF.FrameVisibleForEvent = FrameVisibleForEvent

local function IdentityUnitExists(frame, unit)
  if not IsUnitToken(unit) then return false end
  if HOST_VALUES.MSUF_PreviewTestMode == true
    or HOST_VALUES.MSUF_BossTestMode == true
    or HOST_VALUES.MSUF2_BossUnitframePreviewActive == true
    or HOST_VALUES.MSUF_UnitEditModeActive == true then
    return true
  end
  local exists = ReadUnitExistsCached(frame, unit)
  return exists == true
end

-- Only data-only events may carry stable identity across dispatches. Status
-- remains dispatch-local and is still refreshed by Health, while target,
-- roster, connection, flags, name, faction, and lifecycle events fall through
-- to the conservative identity invalidation below.
local IDENTITY_STABLE_DISPATCH_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
  UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
  UNIT_POWER_UPDATE = true,
  UNIT_POWER_FREQUENT = true,
  UNIT_MAXPOWER = true,
  UNIT_HEAL_PREDICTION = true,
  UNIT_ABSORB_AMOUNT_CHANGED = true,
  UNIT_HEAL_ABSORB_AMOUNT_CHANGED = true,
  UNIT_IN_RANGE_UPDATE = true,
  UNIT_DISTANCE_CHECK_UPDATE = true,
}

local function BeginFrameEvent(frame, event)
  frame._msufDispatchToken = (frame._msufDispatchToken or 0) + 1
  frame._msufDispatchActive = true
  -- Keep the per-frame state table allocated, but invalidate its contents for
  -- this dispatch. RefreshUnitState still performs the same full read on the
  -- first consumer, while later consumers in the same dispatch share it.
  local state = frame._msufUnitState
  if state then
    state.ready = false
    state.dispatchToken = nil
    if IDENTITY_STABLE_DISPATCH_EVENTS[event] ~= true then
      state.identityReady = nil
    end
  end
end

local function EndFrameEvent(frame)
  if frame._msufDeferDispatchEnd == true then return end
  frame._msufDispatchActive = nil
end

local function FrameOnEvent(frame, event, unit, ...)
  -- SetFrameSpec plus the visibility hooks keep both flags hot and exact for
  -- normal attached frames. Only fall back to the full preview-aware resolver
  -- for cold initialization, hidden frames, and disabled specs.
  if not (frame._msufCoreSpecEnabled == true and frame._msufCoreVisible == true)
    and not FrameVisibleForEvent(frame) then
    return
  end
  local path = frame[event]
  if path then return path(frame, event, unit, ...) end
end

-- Secure group children keep their visibility/spec state exact through the
-- adapter and the OnShow/OnHide hooks below. Their combat events therefore do
-- not need the generic preview-aware visibility resolver on every dispatch.
-- Retired/unbound children unregister all events; this one cheap guard only
-- covers the short hidden-header transition window.
local function GroupFrameOnEvent(frame, event, unit, ...)
  if frame._msufCoreSpecEnabled ~= true or frame._msufCoreVisible ~= true then
    return
  end
  local path = frame[event]
  if path then return path(frame, event, unit, ...) end
end

local groupLifecycleDriver
local CompileGroupLifecyclePlan
local SyncGroupLifecycleDriver

local function RunCompiledGroupLifecycle(frame, event, mode)
  if not (frame and frame._msufCoreScope == "group" and FrameVisibleForEvent(frame)) then
    return false
  end
  local plan = frame._msufGroupLifecyclePlan
  if not plan then plan = CompileGroupLifecyclePlan(frame) end
  local path = plan and (mode == "global" and plan.globalPath or plan.fullPath)
  if not path then return false end
  path(frame, event)
  return true
end

--- Refresh one secure group child from a coherent authoritative snapshot.
--- Preserve identity/roster/show reasons so stateful followers can choose their
--- full reseed branch while sharing the same compiled lifecycle path.
local function RefreshGroupFrameState(frame, reason)
  return RunCompiledGroupLifecycle(frame, reason or "PARTY_MEMBER_ENABLE", "full")
end
UF.RefreshGroupFrameState = RefreshGroupFrameState

local function BroadcastGroupLifecycle(event, mode, exceptFrame)
  local frames = UF.attachedFrameList
  for i = 1, #frames do
    local frame = frames[i]
    if frame ~= exceptFrame and frame._msufCoreScope == "group" then
      RunCompiledGroupLifecycle(frame, event, mode)
    end
  end
end

local function RunExactGroupLifecycleCopy(frame, _, event)
  if frame
    and frame._msufCoreScope == "group"
    and UF.attachedFrames[frame] == true then
    RunCompiledGroupLifecycle(frame, event, "full")
    return true
  end
  return false
end

local function BroadcastGroupLifecycleExceptUnit(event, mode, exceptUnit)
  local frames = UF.attachedFrameList
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.MSUFUnitKey ~= exceptUnit and frame._msufCoreScope == "group" then
      RunCompiledGroupLifecycle(frame, event, mode)
    end
  end
end

local RegisterFrameEvent
local RefreshHealthLifecycleSinkRoutes

local function HeaderLayoutRebindActive(frame)
  local GF = MSUF and MSUF.GF
  local isActive = GF and GF.IsHeaderLayoutRebindActive
  return type(isActive) == "function" and isActive(frame) == true
end

local function OnShowIdentityFollowupEvent(unit)
  if unit == "target" then return "PLAYER_TARGET_CHANGED" end
  if unit == "focus" then return "PLAYER_FOCUS_CHANGED" end
  if unit == "pet" then return "UNIT_PET" end
  if unit == "boss1" or unit == "boss2" or unit == "boss3"
    or unit == "boss4" or unit == "boss5" then
    return "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
  end
  return nil
end

local function MarkOnShowIdentityFollowup(frame)
  local unit = frame and frame.MSUFUnitKey
  local event = OnShowIdentityFollowupEvent(unit)
  if not (event and UnitGUID) then return end
  local guid = UnitGUID(unit)
  if guid == nil or issecretvalue(guid) == true then return end
  -- RegisterUnitWatch exposes target/focus/pet/boss frames before their matching
  -- lifecycle event reaches Lua. OnShow has already performed the complete
  -- identity reseed, so remember that exact same-frame GUID and let the event
  -- route skip only its redundant identity follower. Other event followers are
  -- untouched, and the timestamp/GUID guards make later changes authoritative.
  frame._msufCoreOnShowFollowupEvent = event
  frame._msufCoreOnShowFollowupGUID = guid
  frame._msufCoreOnShowFollowupTime = GetTime()
end

local function ConsumeOnShowIdentityFollowup(frame, event, unit)
  local expected = frame and frame._msufCoreOnShowFollowupEvent
  if not expected then return false end
  local expectedGUID = frame._msufCoreOnShowFollowupGUID
  local expectedTime = frame._msufCoreOnShowFollowupTime
  frame._msufCoreOnShowFollowupEvent = nil
  frame._msufCoreOnShowFollowupGUID = nil
  frame._msufCoreOnShowFollowupTime = nil
  if event ~= expected or GetTime() ~= expectedTime or not UnitGUID then return false end
  unit = unit or frame.MSUFUnitKey
  local guid = UnitGUID(unit)
  return guid ~= nil and issecretvalue(guid) ~= true and guid == expectedGUID
end

local function FrameOnShow(frame)
  frame._msufCoreVisible = true
  frame._msufCoreOnShowIdentityRefreshed = nil
  -- Restore the full event set suspended by the aggressive hidden-frame path.
  -- Re-registering from the recorded recipe reactivates every unit event; the
  -- identity/lifecycle refresh below then catches up on any state the frame
  -- missed while inert. Range is restored here too, so its dedicated branch is
  -- skipped when a full suspend was active.
  if frame._msufCoreEventsSuspended == true then
    frame._msufCoreEventsSuspended = nil
    local names = frame._msufEventNames
    local reg = frame._msufEventReg
    if names and reg and RegisterFrameEvent then
      for i = 1, #names do
        local e = names[i]
        RegisterFrameEvent(frame, e, reg[e] == true)
      end
    end
    frame._msufCoreRangeEventSuspended = nil
  elseif frame._msufCoreRangeEventConfigured == true
    and frame._msufCoreRangeEventSuspended == true
    and RegisterFrameEvent then
    RegisterFrameEvent(frame, "UNIT_IN_RANGE_UPDATE", frame._msufCoreRangeEventUnitless == true)
    frame._msufCoreRangeEventSuspended = nil
  end
  if frame._msufCoreScope == "group" then
    if HeaderLayoutRebindActive(frame) then
      frame._msufGFHeaderOnShowDeferred = true
    else
      frame._msufGFHeaderOnShowDeferred = nil
      RefreshGroupFrameState(frame, "MSUF_GF_ONSHOW")
    end
  elseif UF.RunLeanIdentity then
    -- Identity events can arrive while target/focus/dependent frames are
    -- hidden. Re-seed the existing lean plan once when the frame becomes
    -- visible so no status from the previous unit can bleed through.
    frame._msufCoreOnShowIdentityRefreshed =
      UF.RunLeanIdentity(frame, "MSUF_UF_ONSHOW") == true or nil
    if frame._msufCoreOnShowIdentityRefreshed == true then
      MarkOnShowIdentityFollowup(frame)
    end
  end
end

local function FrameOnHide(frame)
  frame._msufCoreVisible = false
  frame._msufCoreOnShowFollowupEvent = nil
  frame._msufCoreOnShowFollowupGUID = nil
  frame._msufCoreOnShowFollowupTime = nil
  if RefreshHealthLifecycleSinkRoutes and frame._msufHealthLifecycleSink then
    RefreshHealthLifecycleSinkRoutes(frame)
  end
  -- Zero-overhead-while-hidden: a hidden frame whose unit still exists keeps
  -- receiving every registered UNIT_* event and burns FrameOnEvent's early-
  -- return per event. Unregister them all while hidden so the frame is truly
  -- inert (FrameOnShow restores from the recorded recipe and reseeds). Default
  -- ON for GROUP frames only -- that is the case the user cares about, and a
  -- hidden group child can legitimately still own a live unit (priority views,
  -- the transient header-rebind window). Single frames are excluded: a hidden
  -- single frame's unit is gone (no target/pet/focus), so its unit events never
  -- fire anyway, and suspending them would only churn register/unregister on
  -- every target/focus swap. The diagnostic flag overrides both ways:
  --   MSUF_GF_SuspendHidden == false -> force OFF (A/B baseline via /msufgp)
  --   MSUF_GF_SuspendHidden == true  -> force ON for every scope (single too)
  local suspendFlag = HOST_VALUES.MSUF_GF_SuspendHidden
  if suspendFlag ~= false
    and (suspendFlag == true or frame._msufCoreScope == "group")
    and frame._msufCoreEventsSuspended ~= true
    and frame._msufEventNames
    and frame.UnregisterEvent then
    local names = frame._msufEventNames
    for i = 1, #names do
      frame:UnregisterEvent(names[i])
    end
    frame._msufCoreEventsSuspended = true
    if frame._msufCoreRangeEventConfigured == true then
      frame._msufCoreRangeEventSuspended = true
    end
    return
  end
  -- Blizzard's CompactUnitFrame explicitly unregisters this event while
  -- hidden because every registered unit makes the client perform additional
  -- native range work. Keep the compiled Lua route and restore registration
  -- on OnShow, but remove both C++ and Lua overhead for invisible frames.
  if frame._msufCoreRangeEventConfigured == true
    and frame._msufCoreRangeEventSuspended ~= true
    and frame.UnregisterEvent then
    frame:UnregisterEvent("UNIT_IN_RANGE_UPDATE")
    frame._msufCoreRangeEventSuspended = true
  end
end

local function EnsureGroupLifecycleDriver()
  if not groupLifecycleDriver and CreateFrame then
    groupLifecycleDriver = CreateFrame("Frame")
    groupLifecycleDriver:SetScript("OnEvent", function(_, event, unitTarget)
    -- PARTY_MEMBER_ENABLE/DISABLE expose a UnitTokenVariant, but Blizzard also
    -- uses the events as a group-wide alternate-power/presence invalidation.
    -- Keep that global semantic on a compiled minimal path while reserving the
    -- expensive health/prediction/portrait snapshot for the validated target.
    local GF = MSUF and MSUF.GF
    local resolve = GF and GF.ResolveLifecycleFrame
    if IsUnitToken(unitTarget) and type(resolve) == "function" then
      local targetFrame, exact = resolve(unitTarget)
      if exact == true
        and targetFrame
        and targetFrame._msufCoreScope == "group"
        and UF.attachedFrames[targetFrame] == true then
        local duplicateBucket = GF.priorityUnitFrames and GF.priorityUnitFrames[unitTarget]
        local forEach = GF.ForEachFrameForUnit
        if duplicateBucket and type(forEach) == "function" then
          if forEach(unitTarget, RunExactGroupLifecycleCopy, event) == true then
            BroadcastGroupLifecycleExceptUnit(event, "global", unitTarget)
            return
          end
          -- A stale duplicate registry must take the full authoritative path.
          BroadcastGroupLifecycle(event, "full")
          return
        end
        RunCompiledGroupLifecycle(targetFrame, event, "full")
        BroadcastGroupLifecycle(event, "global", targetFrame)
        return
      end
    end

    -- Secret/unusable tokens, aliases, secure rebind windows and index misses
    -- cannot be compared safely. Preserve the old authoritative full barrier.
    BroadcastGroupLifecycle(event, "full")
    end)
  end
  if groupLifecycleDriver then
    groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_ENABLE")
    groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_DISABLE")
  end
  return groupLifecycleDriver
end

SyncGroupLifecycleDriver = function()
  local wanted = false
  for i = 1, #UF.attachedFrameList do
    local frame = UF.attachedFrameList[i]
    if frame and frame._msufCoreScope == "group" and UF.attachedFrames[frame] == true then
      wanted = true
      break
    end
  end
  if wanted then
    EnsureGroupLifecycleDriver()
  elseif groupLifecycleDriver then
    groupLifecycleDriver:UnregisterAllEvents()
  end
  return wanted
end

local function IsUnitEvent(event)
  return type(event) == "string"
    and (event:sub(1, 5) == "UNIT_" or NONPREFIX_UNIT_EVENTS[event] == true)
end

local function DependentSource(frame, event)
  if event == "UNIT_TARGET" then
    return frame and UF.ParentUnitForDependentUnit(frame.MSUFUnitKey)
  end
  if event == "UNIT_PET" and frame and frame.MSUFUnitKey == "pet" then
    return "player"
  end
  return nil
end

local function ElementEvents(element, unitless, frame, spec)
  local getter
  if unitless then
    getter = element.GetUnitlessEvents
  else
    getter = element.GetEvents
  end
  if type(getter) == "function" then return getter(frame, spec) end
  if unitless then return element.unitlessEvents end
  return element.events
end

local function AddEventHandler(frame, event, update, unitless)
  if type(event) ~= "string" or event == "" or not update then return end
  local events = frame._msufEvents
  if not events then
    events = {}
    frame._msufEvents = events
  end
  local list = events[event]
  if not list then
    list = {}
    events[event] = list
    local names = frame._msufEventNames
    if not names then
      names = {}
      frame._msufEventNames = names
    end
    names[#names + 1] = event
  end
  list[#list + 1] = update
  list[#list + 1] = unitless == true
end

local SelectElementEventUpdate

-- Runtime route prototypes are immutable and receive the frame as their first
-- argument, so identical frame archetypes can share them safely. Only module
-- functions exported by registered elements enter the strong cache; a custom
-- per-frame closure still gets a private route and therefore cannot be retained
-- here after its frame is detached.
local NIL_ROUTE_KEY = {}
local staticElementFunctions = {}
local noDispatchElementFunctions = {}
local directHealthRouteCache = {}
local directGroupHealthRouteCache = {}
local directPowerRouteCache = {}
local directGroupThreatRouteCache = {}
local singleRouteCache = {}
local sharedFrameEventRoutes = {}

local function IsRegisteredElementFunction(fn)
  if type(fn) ~= "function" then return false end
  if staticElementFunctions[fn] == true then return true end
  for i = 1, #UF.elementOrder do
    local element = UF.elements[UF.elementOrder[i]]
    if type(element) == "table" then
      for _, candidate in pairs(element) do
        if candidate == fn then
          staticElementFunctions[fn] = true
          return true
        end
      end
    end
  end
  return false
end

local function IsNoDispatchElementFunction(fn)
  if noDispatchElementFunctions[fn] == true then return true end
  for i = 1, #UF.elementOrder do
    local element = UF.elements[UF.elementOrder[i]]
    local updates = type(element) == "table" and element.NoDispatchUpdates or nil
    if type(updates) == "table" and updates[fn] == true then
      noDispatchElementFunctions[fn] = true
      return true
    end
  end
  return false
end

local function RouteCacheLeaf(root, fn1, fn2, fn3, fn4, mode, target)
  local key1, key2, key3, key4 = fn1 or NIL_ROUTE_KEY, fn2 or NIL_ROUTE_KEY,
    fn3 or NIL_ROUTE_KEY, fn4 or NIL_ROUTE_KEY
  local node = root[key1]
  if not node then node = {}; root[key1] = node end
  local nextNode = node[key2]
  if not nextNode then nextNode = {}; node[key2] = nextNode end
  node = nextNode
  nextNode = node[key3]
  if not nextNode then nextNode = {}; node[key3] = nextNode end
  node = nextNode
  nextNode = node[key4]
  if not nextNode then nextNode = {}; node[key4] = nextNode end
  node = nextNode
  nextNode = node[mode]
  if not nextNode then nextNode = {}; node[mode] = nextNode end
  return nextNode, target or NIL_ROUTE_KEY
end

local function BuildHealthRoute(barFn, textFn, predictionFn, visualsFn, routeUnitless, target,
    predictionGated, textDirtyGated)
  -- UNIT_HEALTH can compile two followers whose common state is already known
  -- on the frame: the prediction owner publishes whether a health-dependent
  -- absorb visual exists, while the text coalescer publishes its pending bit.
  -- Keep those gates in this route so the overwhelmingly common no-op tick
  -- never crosses either follower function boundary.
  if predictionGated == true and textDirtyGated == true
    and predictionFn and textFn and not visualsFn then
    -- This exact UNIT_HEALTH archetype has no shared state consumer: Health
    -- owns the bar payload, Prediction is a frame-local gate/follower, and the
    -- deferred text marker retains no event payload. Group UNIT_HEALTH already
    -- uses the same dispatch-free contract; single frames can avoid the token
    -- churn too while connection/max/visual routes keep coherent dispatch.
    if target then
      return function(self, ev, _unit)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
      end
    end
    return function(self, ev, unit)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
    end
  end
  if predictionGated == true and textDirtyGated == true and predictionFn and textFn then
    if target then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end
  if predictionGated == true and predictionFn then
    if target then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if self._msufPredictionHealthVisualActive == true then
          if percentReady == true then
            predictionFn(self, ev, target)
          else
            predictionFn(self, ev, target, hp, hpMax)
          end
        end
        if textFn then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      if textFn then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end
  if textDirtyGated == true and textFn then
    if target then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if predictionFn then
          if percentReady == true then predictionFn(self, ev, target) else predictionFn(self, ev, target, hp, hpMax) end
        end
        local dirty = self._msufTextDirtyMask
        if dirty ~= 1 and dirty ~= 3 then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if predictionFn then
        if percentReady == true then predictionFn(self, ev, u) else predictionFn(self, ev, u, hp, hpMax) end
      end
      local dirty = self._msufTextDirtyMask
      if dirty ~= 1 and dirty ~= 3 then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end
  if target then
    if not predictionFn then
      return function(self, ev, _unit)
        BeginFrameEvent(self, ev)
        local hp, hpMax, percentReady
        if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
        if textFn then
          if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
        end
        if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
        EndFrameEvent(self)
      end
    end
    return function(self, ev, _unit)
      BeginFrameEvent(self, ev)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, target) end
      if percentReady == true then
        predictionFn(self, ev, target)
      else
        predictionFn(self, ev, target, hp, hpMax)
      end
      if textFn then
        if percentReady == true then textFn(self, ev, target) else textFn(self, ev, target, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, target, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end
  if not predictionFn then
    return function(self, ev, unit)
      BeginFrameEvent(self, ev)
      local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if textFn then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
      EndFrameEvent(self)
    end
  end
  return function(self, ev, unit)
    BeginFrameEvent(self, ev)
    local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
    local hp, hpMax, percentReady
    if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
    if percentReady == true then
      predictionFn(self, ev, u)
    else
      predictionFn(self, ev, u, hp, hpMax)
    end
    if textFn then
      if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
    end
    if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
    EndFrameEvent(self)
  end
end

-- Castbars can borrow an already-registered target/focus health route instead
-- of registering a second UNIT_HEALTH/UNIT_CONNECTION listener. The wrapper is
-- shared; mutable owner/sink state remains frame-local and exists only while a
-- non-player cast is active.
local function HealthLifecycleSinkRoute(self, ev, unit, ...)
  local base = ev == "UNIT_CONNECTION"
    and self._msufHealthLifecycleConnectionBase
    or self._msufHealthLifecycleHealthBase
  if base then base(self, ev, unit, ...) end
  local sink = self._msufHealthLifecycleSink
  if sink then sink(self._msufHealthLifecycleSinkOwner, self, ev, unit or self.MSUFUnitKey, ...) end
end

local function ClearHealthLifecycleSink(frame, notify)
  if not frame then return false end
  local sink = frame._msufHealthLifecycleSink
  local owner = frame._msufHealthLifecycleSinkOwner
  if not sink then return false end

  if frame.UNIT_HEALTH == HealthLifecycleSinkRoute then
    frame.UNIT_HEALTH = frame._msufHealthLifecycleHealthBase
  end
  if frame.UNIT_CONNECTION == HealthLifecycleSinkRoute then
    frame.UNIT_CONNECTION = frame._msufHealthLifecycleConnectionBase
  end
  frame._msufHealthLifecycleSink = nil
  frame._msufHealthLifecycleSinkOwner = nil
  frame._msufHealthLifecycleSinkUnit = nil
  frame._msufHealthLifecycleHealthBase = nil
  frame._msufHealthLifecycleConnectionBase = nil

  if notify == true then sink(owner, frame, "MSUF_UF_LIFECYCLE_DETACH", frame.MSUFUnitKey) end
  return true
end


RefreshHealthLifecycleSinkRoutes = function(frame)
  if not (frame and frame._msufHealthLifecycleSink) then return false end
  local health = frame.UNIT_HEALTH
  local connection = frame.UNIT_CONNECTION
  if health == HealthLifecycleSinkRoute then health = frame._msufHealthLifecycleHealthBase end
  if connection == HealthLifecycleSinkRoute then connection = frame._msufHealthLifecycleConnectionBase end

  local valid = UF.attachedFrames[frame] == true
    and frame._msufCoreSpecEnabled == true
    and frame._msufCoreVisible == true
    and frame._msufHealthLifecycleSinkUnit == frame.MSUFUnitKey
    and frame._msufActiveElements and frame._msufActiveElements.Health == true
    and type(health) == "function"
    and type(connection) == "function"
  if not valid then
    ClearHealthLifecycleSink(frame, true)
    return false
  end

  frame._msufHealthLifecycleHealthBase = health
  frame._msufHealthLifecycleConnectionBase = connection
  frame.UNIT_HEALTH = HealthLifecycleSinkRoute
  frame.UNIT_CONNECTION = HealthLifecycleSinkRoute
  return true
end

local function BuildPowerRoute(barFn, textFn, _unused, _unusedFollower, routeUnitless, target)
  if target then
    return function(self, ev, _unit, eventPowerToken)
      local power, powerMax, powerType, powerToken, metaChanged
      if barFn then power, powerMax, powerType, powerToken, metaChanged = barFn(self, ev, target, eventPowerToken) end
      if textFn then textFn(self, ev, target, power, powerMax, powerType, powerToken, metaChanged) end
    end
  end
  return function(self, ev, unit, eventPowerToken)
    local u = routeUnitless == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey)
    local power, powerMax, powerType, powerToken, metaChanged
    if barFn then power, powerMax, powerType, powerToken, metaChanged = barFn(self, ev, u, eventPowerToken) end
    if textFn then textFn(self, ev, u, power, powerMax, powerType, powerToken, metaChanged) end
  end
end

local function SharedDirectRoute(cache, builder, fn1, fn2, fn3, fn4, routeUnitless, target,
    predictionGated, textDirtyGated)
  if (fn1 and not IsRegisteredElementFunction(fn1))
    or (fn2 and not IsRegisteredElementFunction(fn2))
    or (fn3 and not IsRegisteredElementFunction(fn3))
    or (fn4 and not IsRegisteredElementFunction(fn4)) then
    return builder(fn1, fn2, fn3, fn4, routeUnitless, target,
      predictionGated, textDirtyGated)
  end
  local mode = target and "target" or (routeUnitless == true and "unitless" or "unit")
  if predictionGated == true then mode = mode .. ":prediction-gated" end
  if textDirtyGated == true then mode = mode .. ":text-dirty-gated" end
  local leaf, key = RouteCacheLeaf(cache, fn1, fn2, fn3, fn4, mode, target)
  local route = leaf[key]
  if not route then
    route = builder(fn1, fn2, fn3, fn4, routeUnitless, target,
      predictionGated, textDirtyGated)
    leaf[key] = route
  end
  sharedFrameEventRoutes[route] = true
  return route
end

-- UNIT_HEALTH is the dominant group-frame event. Health passes every value
-- needed by its text/prediction/visual followers, so the steady route has no
-- shared unit-state consumer and must not enter the generic dispatch protocol.
-- Rare connection/max-health/lifecycle paths retain BuildHealthRoute and its
-- coherent state snapshot.
local function BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn, predictionGated,
    textDirtyGated)
  -- Bar-only gated archetype (group percent bar, no text, no extra visuals):
  -- the steady no-absorb UNIT_HEALTH tick is exactly one updater call.
  if predictionGated == true and barFn and not textFn and not visualsFn then
    return function(self, ev, unit)
      local u = unit or self.MSUFUnitKey
      local hp, hpMax, percentReady = barFn(self, ev, u)
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
    end
  end
  if not predictionFn then
    return function(self, ev, unit)
      local u = unit or self.MSUFUnitKey
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      if textFn then
        local dirty = self._msufTextDirtyMask
        if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
          if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
        end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
    end
  end

  if predictionGated == true then
    return function(self, ev, unit)
      local u = unit or self.MSUFUnitKey
      local hp, hpMax, percentReady
      if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
      -- Absorb-data events own this plain gate. The common no-absorb member
      -- therefore pays no Prediction call at all on UNIT_HEALTH.
      if self._msufPredictionHealthVisualActive == true then
        if percentReady == true then
          predictionFn(self, ev, u)
        else
          predictionFn(self, ev, u, hp, hpMax)
        end
      end
      if textFn then
        local dirty = self._msufTextDirtyMask
        if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
          if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
        end
      end
      if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
    end
  end

  return function(self, ev, unit)
    local u = unit or self.MSUFUnitKey
    local hp, hpMax, percentReady
    if barFn then hp, hpMax, percentReady = barFn(self, ev, u) end
    if percentReady == true then
      predictionFn(self, ev, u)
    else
      predictionFn(self, ev, u, hp, hpMax)
    end
    if textFn then
      local dirty = self._msufTextDirtyMask
      if textDirtyGated ~= true or (dirty ~= 1 and dirty ~= 3) then
        if percentReady == true then textFn(self, ev, u) else textFn(self, ev, u, hp, hpMax) end
      end
    end
    if visualsFn then visualsFn(self, ev, u, hp, hpMax, percentReady) end
  end
end

local function SharedGroupHealthRoute(barFn, textFn, predictionFn, visualsFn, predictionGated,
    textDirtyGated)
  if (barFn and not IsRegisteredElementFunction(barFn))
    or (textFn and not IsRegisteredElementFunction(textFn))
    or (predictionFn and not IsRegisteredElementFunction(predictionFn))
    or (visualsFn and not IsRegisteredElementFunction(visualsFn)) then
    return BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn,
      predictionGated, textDirtyGated)
  end
  local mode = predictionGated == true and "prediction-gated" or "direct"
  if textDirtyGated == true then mode = mode .. ":text-dirty-gated" end
  local leaf, key = RouteCacheLeaf(directGroupHealthRouteCache,
    barFn, textFn, predictionFn, visualsFn, mode, nil)
  local route = leaf[key]
  if not route then
    route = BuildGroupHealthRoute(barFn, textFn, predictionFn, visualsFn,
      predictionGated, textDirtyGated)
    leaf[key] = route
  end
  sharedFrameEventRoutes[route] = true
  return route
end

local function BuildGroupThreatRoute(borderFn, cornerFn, resolvePair)
  return function(self, ev, unit)
    local u = unit or self.MSUFUnitKey
    local borderThreat, cornerThreat = resolvePair(
      self,
      u,
      borderFn and self._msufBorderRuntimeAggroMode or nil,
      cornerFn and self._msufGFCornerPreparedCfg
        and self._msufGFCornerPreparedCfg.runtimeAggroMode or nil)
    if borderFn then borderFn(self, ev, u, borderThreat) end
    if cornerFn then cornerFn(self, ev, u, cornerThreat) end
  end
end

local function SharedGroupThreatRoute(borderFn, cornerFn, resolvePair)
  local leaf, key = RouteCacheLeaf(directGroupThreatRouteCache,
    borderFn, cornerFn, resolvePair, nil, "unit", nil)
  local route = leaf[key]
  if not route then
    route = BuildGroupThreatRoute(borderFn, cornerFn, resolvePair)
    leaf[key] = route
  end
  sharedFrameEventRoutes[route] = true
  return route
end

local function BuildSingleRoute(update, unitless, target)
  local noDispatch = IsNoDispatchElementFunction(update)
  if unitless == true then
    if noDispatch then
      return function(self, ev, _unit, ...)
        update(self, ev, self.MSUFUnitKey, ...)
      end
    end
    return function(self, ev, _unit, ...)
      BeginFrameEvent(self, ev)
      update(self, ev, self.MSUFUnitKey, ...)
      EndFrameEvent(self)
    end
  elseif target then
    if noDispatch then
      return function(self, ev, _unit, ...)
        update(self, ev, target, ...)
      end
    end
    return function(self, ev, _unit, ...)
      BeginFrameEvent(self, ev)
      update(self, ev, target, ...)
      EndFrameEvent(self)
    end
  end
  if noDispatch then
    return function(self, ev, unit, ...)
      update(self, ev, unit or self.MSUFUnitKey, ...)
    end
  end
  return function(self, ev, unit, ...)
    BeginFrameEvent(self, ev)
    update(self, ev, unit or self.MSUFUnitKey, ...)
    EndFrameEvent(self)
  end
end

local function SharedSingleRoute(update, unitless, target)
  if not IsRegisteredElementFunction(update) then
    return BuildSingleRoute(update, unitless, target)
  end
  local node = singleRouteCache[update]
  if not node then node = {}; singleRouteCache[update] = node end
  local mode = target and "target" or (unitless == true and "unitless" or "unit")
  local leaf = node[mode]
  if not leaf then leaf = {}; node[mode] = leaf end
  local key = target or NIL_ROUTE_KEY
  local route = leaf[key]
  if not route then
    route = BuildSingleRoute(update, unitless, target)
    leaf[key] = route
  end
  sharedFrameEventRoutes[route] = true
  return route
end

local function CompileFrameEventPath(frame, event, list)
  local target = frame._msufFrameUnitEventTargets and frame._msufFrameUnitEventTargets[event]
  local count = #list
  if frame._msufCoreScope == "group" and GROUP_THREAT_EVENTS[event] == true then
    local borders = UF.elements.Borders
    local corners = UF.elements.GroupCornerIndicators
    local borderUpdate = borders and borders.UpdateGroupThreat
    local cornerUpdate = corners and corners.UpdateGroupThreat
    local visuals = MSUF.UFVisuals
    local resolvePair = visuals and visuals.ResolveGroupAggroPair
    local borderFn, cornerFn
    local direct = target == nil and type(resolvePair) == "function"
    for i = 1, count, 2 do
      local update = list[i]
      if list[i + 1] == true then
        direct = false
        break
      end
      if update == borderUpdate then
        borderFn = update
      elseif update == cornerUpdate then
        cornerFn = update
      else
        direct = false
        break
      end
    end
    if direct == true and (borderFn or cornerFn) then
      return SharedGroupThreatRoute(borderFn, cornerFn, resolvePair)
    end
  end
  local healthEvent = HEALTH_EVENTS[event] == true
  local powerEvent = POWER_EVENTS[event] == true
  if healthEvent or powerEvent then
    local barElement = healthEvent and UF.elements.Health or UF.elements.Power
    local barBase = healthEvent and frame[GetUpdateKey("Health")] or frame[GetUpdateKey("Power")]
    local barUpdate = healthEvent and barBase
      and SelectElementEventUpdate(barElement, frame, event, barBase) or barBase
    local textElement = healthEvent and UF.elements.HealthText or UF.elements.PowerText
    local textBase = healthEvent and frame[GetUpdateKey("HealthText")] or frame[GetUpdateKey("PowerText")]
    local textUpdate = textBase and SelectElementEventUpdate(textElement, frame, event, textBase) or nil
    local predictionUpdate
    local visualsUpdate
    if healthEvent then
      local predictionBase = frame[GetUpdateKey("Prediction")]
      if predictionBase then
        predictionUpdate = SelectElementEventUpdate(UF.elements.Prediction, frame, event, predictionBase)
      end
      local visualsBase = frame[GetUpdateKey("GroupVisuals")]
      if visualsBase then
        visualsUpdate = SelectElementEventUpdate(UF.elements.GroupVisuals, frame, event, visualsBase)
      end
    end
    local barFn, textFn, predictionFn, visualsFn
    local routeUnitless
    local direct = true
    for i = 1, count, 2 do
      local update = list[i]
      local unitless = list[i + 1] == true
      if routeUnitless == nil then
        routeUnitless = unitless
      elseif routeUnitless ~= unitless then
        direct = false
        break
      end
      if update == barUpdate then
        barFn = update
      elseif update == textUpdate then
        textFn = update
      elseif predictionUpdate and update == predictionUpdate then
        predictionFn = update
      elseif visualsUpdate and update == visualsUpdate then
        visualsFn = update
      else
        direct = false
        break
      end
    end
    if direct == true and (barFn or textFn or predictionFn or visualsFn) then
      if healthEvent then
        local prediction = event == "UNIT_HEALTH" and UF.elements.Prediction or nil
        local predictionGated = predictionFn and prediction
          and prediction.HealthVisualGateUpdates
          and prediction.HealthVisualGateUpdates[predictionFn] == true
        local healthText = event == "UNIT_HEALTH" and UF.elements.HealthText or nil
        local textDirtyGated = textFn and healthText
          and healthText.DirtyGateUpdates
          and healthText.DirtyGateUpdates[textFn] == true
        if frame._msufCoreScope == "group" and event == "UNIT_HEALTH"
          and target == nil and routeUnitless ~= true then
          return SharedGroupHealthRoute(
            barFn, textFn, predictionFn, visualsFn,
            predictionGated == true, textDirtyGated == true)
        end
        return SharedDirectRoute(directHealthRouteCache, BuildHealthRoute,
          barFn, textFn, predictionFn, visualsFn, routeUnitless, target,
          predictionGated == true, textDirtyGated == true)
      end
      return SharedDirectRoute(directPowerRouteCache, BuildPowerRoute,
        barFn, textFn, nil, nil, routeUnitless, target)
    end
  end
  if count == 2 then
    local update = list[1]
    return SharedSingleRoute(update, list[2] == true, target)
  end

  if target then
    return function(self, ev, unit, ...)
      BeginFrameEvent(self, ev)
      for i = 1, count, 2 do
        local update = list[i]
        update(self, ev, list[i + 1] == true and self.MSUFUnitKey or target, ...)
      end
      EndFrameEvent(self)
    end
  end

  return function(self, ev, unit, ...)
    BeginFrameEvent(self, ev)
    for i = 1, count, 2 do
      local update = list[i]
      update(self, ev, list[i + 1] == true and self.MSUFUnitKey or (unit or self.MSUFUnitKey), ...)
    end
    EndFrameEvent(self)
  end
end

local groupLifecyclePlanIntern = {}

local function LifecycleCachedHealth(frame, unit)
  local hpBar = frame.hpBar
  local hp = hpBar and hpBar._msufHealthValueUnit == unit and hpBar._msufHealthValue or nil
  local hpMax = hpBar and hpBar._msufHealthMaxUnit == unit and hpBar._msufHealthMax or nil
  if issecretvalue(hp) == true then hp = nil end
  if issecretvalue(hpMax) == true then hpMax = nil end
  return hp, hpMax
end

local function BuildLifecycleFullPath(healthPath, powerUpdate, powerTextUpdate,
    nameUpdate, portraitUpdate, statusUpdate, rangeUpdate, visualsUpdate,
    bordersUpdate, cornerUpdate)
  return function(frame, event)
    local unit = frame.MSUFUnitKey
    frame._msufGroupStateRefresh = true
    frame._msufDeferDispatchEnd = true
    if healthPath then healthPath(frame, event, nil) else BeginFrameEvent(frame, event) end

    local power, powerMax, powerType, powerToken, powerMetaChanged
    if powerUpdate then
      power, powerMax, powerType, powerToken, powerMetaChanged = powerUpdate(frame, event, unit)
    end
    if powerTextUpdate then
      powerTextUpdate(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    if nameUpdate then nameUpdate(frame, event, unit) end
    if portraitUpdate then portraitUpdate(frame, event, unit) end

    local hp, hpMax = LifecycleCachedHealth(frame, unit)
    if statusUpdate then statusUpdate(frame, event, unit, hp) end
    if rangeUpdate then rangeUpdate(frame, event, unit) end
    if visualsUpdate then visualsUpdate(frame, event, unit, hp, hpMax) end
    if bordersUpdate then bordersUpdate(frame, event, unit) end
    if cornerUpdate then cornerUpdate(frame, event, unit) end

    frame._msufDeferDispatchEnd = nil
    EndFrameEvent(frame)
    frame._msufGroupStateRefresh = nil
  end
end

local function BuildLifecycleGlobalPath(powerUpdate, powerTextUpdate,
    namePresenceUpdate, statusUpdate, rangeUpdate, visualsUpdate)
  return function(frame, event)
    local unit = frame.MSUFUnitKey
    BeginFrameEvent(frame, event)

    -- Blizzard treats PARTY_MEMBER_ENABLE/DISABLE as a group-wide alternate
    -- power and presence invalidation. These are the intentionally global
    -- followers; name/portrait and health stay target-only. If the lifecycle
    -- unit cannot be resolved safely, the driver selects fullPath for every
    -- frame instead of entering this minimal path.
    local power, powerMax, powerType, powerToken, powerMetaChanged
    if powerUpdate then
      power, powerMax, powerType, powerToken, powerMetaChanged = powerUpdate(frame, event, unit)
    end
    if powerTextUpdate then
      powerTextUpdate(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
    end
    if namePresenceUpdate then namePresenceUpdate(frame, event, unit) end

    local hp, hpMax = LifecycleCachedHealth(frame, unit)
    if statusUpdate then statusUpdate(frame, event, unit, hp) end
    if rangeUpdate then rangeUpdate(frame, event, unit) end
    if visualsUpdate then visualsUpdate(frame, event, unit, hp, hpMax) end

    EndFrameEvent(frame)
  end
end

local function NewGroupLifecyclePlan(healthPath, powerUpdate,
    powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
    rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
  return {
    fullPath = BuildLifecycleFullPath(healthPath, powerUpdate, powerTextUpdate,
      nameUpdate, portraitUpdate, statusUpdate, rangeUpdate, visualsUpdate,
      bordersUpdate, cornerUpdate),
    globalPath = BuildLifecycleGlobalPath(powerUpdate,
      powerTextUpdate, namePresenceUpdate, statusUpdate, rangeUpdate, visualsUpdate),
  }
end

local function InternLifecycleNode(node, value)
  local key = value or NIL_ROUTE_KEY
  local nextNode = node[key]
  if not nextNode then nextNode = {}; node[key] = nextNode end
  return nextNode
end

local function InternGroupLifecyclePlan(healthPath, powerUpdate,
    powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
    rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
  local shared = (not healthPath or sharedFrameEventRoutes[healthPath] == true)
  shared = shared
    and (not powerUpdate or IsRegisteredElementFunction(powerUpdate))
    and (not powerTextUpdate or IsRegisteredElementFunction(powerTextUpdate))
    and (not nameUpdate or IsRegisteredElementFunction(nameUpdate))
    and (not namePresenceUpdate or IsRegisteredElementFunction(namePresenceUpdate))
    and (not portraitUpdate or IsRegisteredElementFunction(portraitUpdate))
    and (not statusUpdate or IsRegisteredElementFunction(statusUpdate))
    and (not rangeUpdate or IsRegisteredElementFunction(rangeUpdate))
    and (not visualsUpdate or IsRegisteredElementFunction(visualsUpdate))
    and (not bordersUpdate or IsRegisteredElementFunction(bordersUpdate))
    and (not cornerUpdate or IsRegisteredElementFunction(cornerUpdate))
  if not shared then
    return NewGroupLifecyclePlan(healthPath, powerUpdate,
      powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
      rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
  end

  local node = InternLifecycleNode(groupLifecyclePlanIntern, healthPath)
  node = InternLifecycleNode(node, powerUpdate)
  node = InternLifecycleNode(node, powerTextUpdate)
  node = InternLifecycleNode(node, nameUpdate)
  node = InternLifecycleNode(node, namePresenceUpdate)
  node = InternLifecycleNode(node, portraitUpdate)
  node = InternLifecycleNode(node, statusUpdate)
  node = InternLifecycleNode(node, rangeUpdate)
  node = InternLifecycleNode(node, visualsUpdate)
  node = InternLifecycleNode(node, bordersUpdate)
  node = InternLifecycleNode(node, cornerUpdate)
  if not node.plan then
    node.plan = NewGroupLifecyclePlan(healthPath, powerUpdate,
      powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
      rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
  end
  return node.plan
end

local function ActiveLifecycleUpdate(frame, name)
  local active = frame and frame._msufActiveElements
  if not (active and active[name] == true) then return nil end
  local key = GetUpdateKey(name)
  return key and frame[key] or nil
end

CompileGroupLifecyclePlan = function(frame)
  if not (frame and frame._msufCoreScope == "group") then
    if frame then frame._msufGroupLifecyclePlan = nil end
    return nil
  end
  local healthPath = frame.PARTY_MEMBER_ENABLE
  local nameUpdate = ActiveLifecycleUpdate(frame, "NameText")
  local text = frame.MSUFSpec and frame.MSUFSpec.text
  local namePresenceUpdate = text and text.hideNameOnDeadOffline == true and nameUpdate or nil
  local plan = InternGroupLifecyclePlan(
    healthPath,
    ActiveLifecycleUpdate(frame, "Power"),
    ActiveLifecycleUpdate(frame, "PowerText"),
    nameUpdate,
    namePresenceUpdate,
    ActiveLifecycleUpdate(frame, "Portrait"),
    ActiveLifecycleUpdate(frame, "GroupStatusRuntime"),
    ActiveLifecycleUpdate(frame, "GroupRangeFade"),
    ActiveLifecycleUpdate(frame, "GroupVisuals"),
    ActiveLifecycleUpdate(frame, "Borders"),
    ActiveLifecycleUpdate(frame, "GroupCornerIndicators")
  )
  frame._msufGroupLifecyclePlan = plan
  return plan
end

RegisterFrameEvent = function(frame, event, unitless)
  if not (frame and frame.RegisterEvent) then return end
  if frame._msufCoreScope == "group"
    and GROUP_LIFECYCLE_EVENTS[event] == true
    and EnsureGroupLifecycleDriver() then
    return
  end
  -- Record the registration recipe so FrameOnHide can fully suspend a hidden
  -- frame's unit events and FrameOnShow can restore them. Default ON for group
  -- frames (see FrameOnHide). A hidden group child whose unit still exists would
  -- otherwise keep receiving every UNIT_* event and pay FrameOnEvent's early-
  -- return per event; suspending makes it truly inert, guaranteeing zero
  -- overhead while hidden.
  local reg = frame._msufEventReg
  if not reg then reg = {}; frame._msufEventReg = reg end
  reg[event] = unitless == true
  if unitless == true or not IsUnitEvent(event) or not frame.RegisterUnitEvent then
    frame:RegisterEvent(event)
    return
  end
  local source = DependentSource(frame, event) or frame.MSUFUnitKey
  if not IsUnitToken(source) then
    frame:RegisterEvent(event)
    return
  end
  frame:RegisterUnitEvent(event, source)
  if source ~= frame.MSUFUnitKey then
    frame._msufFrameUnitEvents = frame._msufFrameUnitEvents or {}
    frame._msufFrameUnitEventTargets = frame._msufFrameUnitEventTargets or {}
    frame._msufFrameUnitEvents[event] = source
    frame._msufFrameUnitEventTargets[event] = frame.MSUFUnitKey
  end
end

local function ClearFrameEvents(frame)
  if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
  if frame then
    local names = frame._msufEventNames
    if names then
      for i = 1, #names do
        frame[names[i]] = nil
      end
    end
    frame._msufEvents = nil
    frame._msufEventNames = nil
    frame._msufEventReg = nil
    frame._msufCoreEventsSuspended = nil
    frame._msufFrameUnitEvents = nil
    frame._msufFrameUnitEventTargets = nil
    frame._msufElementEventRoutes = nil
    frame._msufEventRouteUnit = nil
    frame._msufEventRouteNeedsIdentity = nil
    frame._msufCoreRangeEventConfigured = nil
    frame._msufCoreRangeEventUnitless = nil
    frame._msufCoreRangeEventSuspended = nil
  end
end

local function ElementUpdateFunction(frame, name)
  local key = UPDATE_KEYS[name]
  return key and frame[key] or nil
end

local function SelectElementUpdate(element, frame)
  local update = element and element.Update
  local selector = element and element.SelectUpdate
  if type(selector) == "function" then
    update = selector(frame, frame and frame.MSUFSpec) or update
  end
  return update
end

local function RefreshIdentityHealthBackground(frame)
  local active = frame and frame._msufActiveElements
  if not (active and active.Health == true) then return false end
  local health = UF.elements and UF.elements.Health
  local refresh = health and health.UpdateIdentityBackground
  if type(refresh) ~= "function" then return false end
  return refresh(frame) == true
end

SelectElementEventUpdate = function(element, frame, event, update)
  local selector = element and element.SelectEventUpdate
  if type(selector) == "function" then
    return selector(frame, frame and frame.MSUFSpec, event, update) or update
  end
  return update
end

local function IdentityEventUpdate(frame, event)
  if not frame then return end
  event = event or "MSUF_UNIT_IDENTITY"
  local unit = frame.MSUFUnitKey
  if ConsumeOnShowIdentityFollowup(frame, event, unit) then return end
  if not IdentityUnitExists(frame, unit) then
    RefreshIdentityHealthBackground(frame)
    return
  end
  local barPath = frame._msufIdentityBarPath
  local hp, hpMax, healthPercentReady
  local power, powerMax, powerType, powerToken, powerMetaChanged
  if barPath then
    hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged = barPath(frame, event, unit)
  end
  RefreshIdentityHealthBackground(frame)
  local path = frame._msufIdentityPath
  if path then
    return path(frame, event, unit,
      hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged)
  end
end

--- Dependent units can receive PLAYER_*_CHANGED and UNIT_TARGET in the same
--- event burst. Coalesce those notifications and move their identity work out
--- of the target-change tick; OnShow and normal unit events remain immediate.
local function FlushDependentIdentity(frame)
  if not frame then return end
  frame._msufDependentIdentityQueued = nil
  local event = frame._msufDependentIdentityEvent or "MSUF_DEPENDENT_IDENTITY"
  frame._msufDependentIdentityEvent = nil
  if UF.RunLeanIdentity then
    UF.RunLeanIdentity(frame, event)
  else
    IdentityEventUpdate(frame, event)
  end
end

local function QueueDependentIdentity(frame, event)
  if not frame then return end
  frame._msufDependentIdentityEvent = event or "MSUF_DEPENDENT_IDENTITY"
  if frame._msufDependentIdentityQueued == true then return end
  frame._msufDependentIdentityQueued = true

  local callback = frame._msufDependentIdentityCallback
  if not callback then
    callback = function() FlushDependentIdentity(frame) end
    frame._msufDependentIdentityCallback = callback
  end

  local scheduleOnce = UF.GetService and UF.GetService("ScheduleOnce")
    or HOST_VALUES.MSUF_ScheduleOnce
  if type(scheduleOnce) == "function" then
    scheduleOnce(callback, callback)
  elseif _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, callback)
  else
    callback()
  end
end

local function FrameNeedsIdentityLifecycle(frame)
  local active = frame and frame._msufActiveElements
  if not active then return false end
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if (IDENTITY_ELEMENTS[name] == true or IDENTITY_BAR_ELEMENTS[name] == true)
      and active[name] == true
      and ElementUpdateFunction(frame, name) then
      return true
    end
  end
  return false
end

local function IsBossUnit(unit)
  return unit == "boss1" or unit == "boss2" or unit == "boss3"
    or unit == "boss4" or unit == "boss5"
end

local function AddIdentityLifecycleHandlers(frame)
  if not FrameNeedsIdentityLifecycle(frame) then return end
  local unit = frame.MSUFUnitKey
  AddEventHandler(frame, "PLAYER_ENTERING_WORLD", IdentityEventUpdate, true)
  if unit == "target" then
    AddEventHandler(frame, "PLAYER_TARGET_CHANGED", IdentityEventUpdate, true)
  elseif unit == "focus" then
    AddEventHandler(frame, "PLAYER_FOCUS_CHANGED", IdentityEventUpdate, true)
  elseif unit == "pet" then
    AddEventHandler(frame, "UNIT_PET", IdentityEventUpdate, false)
  elseif unit == "targettarget" then
    AddEventHandler(frame, "PLAYER_TARGET_CHANGED", QueueDependentIdentity, true)
    AddEventHandler(frame, "UNIT_TARGET", QueueDependentIdentity, false)
  elseif unit == "focustarget" then
    AddEventHandler(frame, "PLAYER_FOCUS_CHANGED", QueueDependentIdentity, true)
    AddEventHandler(frame, "UNIT_TARGET", QueueDependentIdentity, false)
  elseif IsBossUnit(unit) then
    AddEventHandler(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", IdentityEventUpdate, true)
  end
end

local function CompileRuntimePath(list, count)
  if count == 1 then
    return list[1]
  end
  if count == 2 then
    local a, b = list[1], list[2]
    return function(frame, event, unit)
      a(frame, event, unit)
      return b(frame, event, unit)
    end
  end
  if count and count > 2 then
    return function(frame, event, unit)
      for i = 1, count do
        list[i](frame, event, unit)
      end
    end
  end
  return nil
end

local IDENTITY_STEP_NORMAL = 0
local IDENTITY_STEP_HEALTH_TEXT = 1
local IDENTITY_STEP_POWER_TEXT = 2
local IDENTITY_STEP_PREDICTION = 3

-- Identity bars run before the element sequence. Forward their ephemeral
-- values to the matching text elements so restricted/secret payloads do not
-- need a second native read. The values stay on the Lua stack and are never
-- retained on the frame. Every other element keeps its original three-arg
-- contract and the compiled elementOrder remains unchanged.
local function CompileIdentityRuntimePath(list, labels, count)
  if not count or count <= 0 then return nil end
  local kinds = {}
  local inlineToTScheduled = false
  for i = 1, count do
    local label = labels[i]
    if label == "HealthText" then
      kinds[i] = IDENTITY_STEP_HEALTH_TEXT
    elseif label == "PowerText" then
      kinds[i] = IDENTITY_STEP_POWER_TEXT
    elseif label == "Prediction" then
      kinds[i] = IDENTITY_STEP_PREDICTION
    else
      kinds[i] = IDENTITY_STEP_NORMAL
    end
    if label == "InlineToT" then
      inlineToTScheduled = true
    end
  end

  return function(frame, event, unit,
      hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged)
    -- NameText color updates normally keep InlineToT in sync. Identity plans
    -- already contain InlineToT as their own step, so mark the batch and let
    -- that one authoritative step do the work instead of updating it twice.
    if inlineToTScheduled then
      frame._msufIdentityInlineToTScheduled = true
    end
    for i = 1, count do
      local update = list[i]
      local kind = kinds[i]
      if kind == IDENTITY_STEP_HEALTH_TEXT then
        if healthPercentReady == true then
          -- Match BuildHealthRoute: the Health element already seeded the
          -- dispatch-percent slot consumed by HealthText.
          update(frame, event, unit, nil, nil)
        else
          update(frame, event, unit, hp, hpMax)
        end
      elseif kind == IDENTITY_STEP_POWER_TEXT then
        update(frame, event, unit,
          power, powerMax, powerType, powerToken, powerMetaChanged)
      elseif kind == IDENTITY_STEP_PREDICTION then
        if healthPercentReady == true then
          update(frame, event, unit)
        else
          update(frame, event, unit, hp, hpMax)
        end
      else
        update(frame, event, unit)
      end
    end
    if inlineToTScheduled then
      frame._msufIdentityInlineToTScheduled = nil
    end
  end
end

-- Identity and full-runtime paths are archetype data, not frame state. Intern
-- immutable function/label sequences so identical raid children retain only
-- references to one plan instead of four private arrays and two closures each.
-- A frame-owned selector closure deliberately falls back to a private plan.
local runtimeSequencePlanIntern = {}
local runtimeSequenceBuildFns = {}
local runtimeSequenceBuildLabels = {}
local EMPTY_RUNTIME_SEQUENCE_FNS = {}
local EMPTY_RUNTIME_SEQUENCE_LABELS = {}
local EMPTY_RUNTIME_SEQUENCE_PLAN = {
  functions = EMPTY_RUNTIME_SEQUENCE_FNS,
  labels = EMPTY_RUNTIME_SEQUENCE_LABELS,
  count = 0,
}

local function NewRuntimeSequencePlan(functions, labels, count, identity)
  local planFns, planLabels = {}, {}
  for i = 1, count do
    planFns[i] = functions[i]
    planLabels[i] = labels[i]
  end
  return {
    functions = planFns,
    labels = planLabels,
    count = count,
    path = identity == true
      and CompileIdentityRuntimePath(planFns, planLabels, count)
      or CompileRuntimePath(planFns, count),
  }
end

local function InternRuntimeSequencePlan(functions, labels, count, identity)
  if count <= 0 then return EMPTY_RUNTIME_SEQUENCE_PLAN end

  local node = runtimeSequencePlanIntern
  for i = 1, count do
    local update = functions[i]
    if not IsRegisteredElementFunction(update) then
      return NewRuntimeSequencePlan(functions, labels, count, identity)
    end
    local byLabel = node[update]
    if not byLabel then byLabel = {}; node[update] = byLabel end
    local label = labels[i]
    local nextNode = byLabel[label]
    if not nextNode then nextNode = {}; byLabel[label] = nextNode end
    node = nextNode
  end

  local planKey = identity == true and "identityPlan" or "plan"
  local plan = node[planKey]
  if plan then return plan end
  plan = NewRuntimeSequencePlan(functions, labels, count, identity)
  node[planKey] = plan
  return plan
end

local function BuildRuntimeSequencePlan(frame, include, identity)
  local functions = runtimeSequenceBuildFns
  local labels = runtimeSequenceBuildLabels
  local active = frame and frame._msufActiveElements
  local count = 0
  if active then
    for i = 1, #UF.elementOrder do
      local name = UF.elementOrder[i]
      if include[name] == true and active[name] == true then
        local update = ElementUpdateFunction(frame, name)
        if update then
          count = count + 1
          functions[count] = update
          labels[count] = name
        end
      end
    end
  end

  local plan = InternRuntimeSequencePlan(functions, labels, count, identity)
  for i = 1, count do
    functions[i] = nil
    labels[i] = nil
  end
  return plan
end

local function AssignRuntimeSequencePlan(frame, plan, listKey, countKey, labelKey, pathKey)
  frame[listKey] = plan.functions
  frame[labelKey] = plan.labels
  frame[countKey] = plan.count > 0 and plan.count or nil
  frame[pathKey] = plan.path
end

local identityBarPathIntern = {}
local function CompileIdentityBarPath(frame)
  local active = frame and frame._msufActiveElements
  if not active then return nil end
  local health = active.Health == true and ElementUpdateFunction(frame, "Health") or nil
  local power = active.Power == true and ElementUpdateFunction(frame, "Power") or nil
  if not (health or power) then return nil end

  local shared = (not health or IsRegisteredElementFunction(health))
    and (not power or IsRegisteredElementFunction(power))
  local byPower, key
  if shared then
    local healthKey = health or NIL_ROUTE_KEY
    byPower = identityBarPathIntern[healthKey]
    if not byPower then byPower = {}; identityBarPathIntern[healthKey] = byPower end
    key = power or NIL_ROUTE_KEY
    local path = byPower[key]
    if path then return path end
  end

  -- Always wrap, including health-only and power-only plans, so every
  -- archetype returns the same fixed tuple:
  -- hp, hpMax, healthPercentReady, power, powerMax, type, token, metaChanged.
  local path = function(self, event, unit)
    local hp, hpMax, healthPercentReady
    if health then
      hp, hpMax, healthPercentReady = health(self, event, unit)
    end
    local powerValue, powerMax, powerType, powerToken, powerMetaChanged
    if power then
      powerValue, powerMax, powerType, powerToken, powerMetaChanged = power(self, event, unit)
    end
    return hp, hpMax, healthPercentReady,
      powerValue, powerMax, powerType, powerToken, powerMetaChanged
  end
  if shared then byPower[key] = path end
  return path
end

function UF.RebuildRuntimeStatusState(frame)
  if not frame then return false end
  local identityPlan = BuildRuntimeSequencePlan(frame, IDENTITY_ELEMENTS, true)
  AssignRuntimeSequencePlan(frame, identityPlan,
    "_msufIdentityFns", "_msufIdentityCount", "_msufIdentityLabels", "_msufIdentityPath")
  local runtimePlan = BuildRuntimeSequencePlan(frame, FORCE_UPDATE_ELEMENTS)
  AssignRuntimeSequencePlan(frame, runtimePlan,
    "_msufRuntimeAllFns", "_msufRuntimeAllCount", "_msufRuntimeAllLabels", "_msufRuntimeAllPath")
  local runtimeLabels = frame._msufRuntimeAllLabels
  local onShowNeedsFull
  if runtimeLabels then
    for i = 1, #runtimeLabels do
      local name = runtimeLabels[i]
      if IDENTITY_ELEMENTS[name] ~= true and IDENTITY_BAR_ELEMENTS[name] ~= true then
        onShowNeedsFull = true
        break
      end
    end
  end
  frame._msufRuntimeOnShowNeedsFull = onShowNeedsFull
  frame._msufGroupIdentityFns = frame._msufIdentityFns
  frame._msufGroupIdentityCount = frame._msufIdentityCount
  frame._msufGroupIdentityLabels = frame._msufIdentityLabels
  frame._msufGroupIdentityPath = frame._msufIdentityPath
  frame._msufIdentityBarPath = CompileIdentityBarPath(frame)
  -- Prewarm the shared unit/read-through state while routes are compiled,
  -- never on the first target/combat event that consumes those routes.
  if (frame._msufIdentityPath or frame._msufIdentityBarPath)
    and not frame._msufUnitState then
    frame._msufUnitState = {}
  end
  if CompileGroupLifecyclePlan then CompileGroupLifecyclePlan(frame) end
  return true
end

-- Event providers mostly return module constants. Intern a defensive copy once
-- per distinct sequence so 40 identical raid frames do not retain the same
-- event-name arrays over and over. The interned arrays are immutable.
local eventListIntern = {}
local EMPTY_EVENT_LIST = {}
eventListIntern["0\030"] = EMPTY_EVENT_LIST

local function InternEventList(events)
  if type(events) ~= "table" then return nil end
  local count = #events
  local key = tostring(count) .. "\030" .. table_concat(events, "\031", 1, count)
  local interned = eventListIntern[key]
  if interned then return interned end
  interned = {}
  for i = 1, count do interned[i] = events[i] end
  eventListIntern[key] = interned
  return interned
end

local routeSnapshotIntern = {}
local sharedRouteSnapshots = {}
local runtimeRoutePlanIntern = {}

local function RuntimeRouteSnapshot(update, events, unitlessEvents)
  events = InternEventList(events)
  unitlessEvents = InternEventList(unitlessEvents)
  if not IsRegisteredElementFunction(update) then
    return { update = update, events = events, unitlessEvents = unitlessEvents }
  end
  local byEvents = routeSnapshotIntern[update]
  if not byEvents then byEvents = {}; routeSnapshotIntern[update] = byEvents end
  local eventKey = events or NIL_ROUTE_KEY
  local byUnitless = byEvents[eventKey]
  if not byUnitless then byUnitless = {}; byEvents[eventKey] = byUnitless end
  local unitlessKey = unitlessEvents or NIL_ROUTE_KEY
  local route = byUnitless[unitlessKey]
  if not route then
    route = { update = update, events = events, unitlessEvents = unitlessEvents }
    byUnitless[unitlessKey] = route
    sharedRouteSnapshots[route] = true
  end
  return route
end

local function InternRuntimeRoutePlan(routes)
  local node = runtimeRoutePlanIntern
  for i = 1, #UF.elementOrder do
    local route = routes[UF.elementOrder[i]]
    if route and sharedRouteSnapshots[route] ~= true then
      return routes
    end
    local key = route or NIL_ROUTE_KEY
    local nextNode = node[key]
    if not nextNode then nextNode = {}; node[key] = nextNode end
    node = nextNode
  end
  local plan = node.plan
  if plan then return plan end
  node.plan = routes
  return routes
end

local function RebuildFrameEvents(frame)
  if not frame then return false end
  ClearFrameEvents(frame)
  local routes = {}
  frame._msufElementEventRoutes = routes
  frame._msufEventRouteUnit = frame.MSUFUnitKey
  local active = frame._msufActiveElements
  if not active then
    frame._msufElementEventRoutes = InternRuntimeRoutePlan(routes)
    frame._msufEventRouteNeedsIdentity = false
    if RefreshHealthLifecycleSinkRoutes then RefreshHealthLifecycleSinkRoutes(frame) end
    UF.RebuildRuntimeStatusState(frame)
    if UF.SyncRuntimeDriver and UF._msufApplyingSpec ~= true then UF.SyncRuntimeDriver() end
    return true
  end
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if active[name] == true and EventElementAllowed(name) == true then
      local element = UF.elements[name]
      local update = ElementUpdateFunction(frame, name)
      if element and update then
        local events = ElementEvents(element, false, frame, frame.MSUFSpec)
        local unitlessEvents = ElementEvents(element, true, frame, frame.MSUFSpec)
        -- Providers may reuse or mutate their tables, so the runtime plan owns
        -- an immutable interned snapshot rather than the provider table.
        routes[name] = RuntimeRouteSnapshot(update, events, unitlessEvents)
        if type(events) == "table" then
          for j = 1, #events do
            local event = events[j]
            AddEventHandler(frame, event, SelectElementEventUpdate(element, frame, event, update), false)
          end
        end
        if type(unitlessEvents) == "table" then
          for j = 1, #unitlessEvents do
            local event = unitlessEvents[j]
            AddEventHandler(frame, event, SelectElementEventUpdate(element, frame, event, update), true)
          end
        end
      end
    end
  end
  frame._msufEventRouteNeedsIdentity = FrameNeedsIdentityLifecycle(frame)
  AddIdentityLifecycleHandlers(frame)
  local events = frame._msufEvents
  local names = frame._msufEventNames
  if events and names then
    names = InternEventList(names)
    frame._msufEventNames = names
    for n = 1, #names do
      local event = names[n]
      local list = events[event]
      local unitless = false
      for i = 2, #list, 2 do
        if list[i] == true then unitless = true break end
      end
      if event == "UNIT_IN_RANGE_UPDATE" then
        frame._msufCoreRangeEventConfigured = true
        frame._msufCoreRangeEventUnitless = unitless == true
        if frame._msufCoreVisible == false then
          frame._msufCoreRangeEventSuspended = true
        else
          RegisterFrameEvent(frame, event, unitless)
        end
      else
        RegisterFrameEvent(frame, event, unitless)
      end
      local path = CompileFrameEventPath(frame, event, list)
      frame[event] = path
    end
  end
  if RefreshHealthLifecycleSinkRoutes then RefreshHealthLifecycleSinkRoutes(frame) end
  -- Compiled routes either capture only the one generic list they need or use
  -- a shared prototype. The event->builder map itself has no runtime reader.
  frame._msufEvents = nil
  frame._msufElementEventRoutes = InternRuntimeRoutePlan(routes)
  UF.RebuildRuntimeStatusState(frame)
  if UF.SyncRuntimeDriver and UF._msufApplyingSpec ~= true then UF.SyncRuntimeDriver() end
  return true
end
UF.RefreshFrameUnitEventRouting = RebuildFrameEvents

local function EventListsMatch(a, b)
  if a == b then return true end
  if type(a) ~= "table" then a = nil end
  if type(b) ~= "table" then b = nil end
  local count = a and #a or 0
  if count ~= (b and #b or 0) then return false end
  for i = 1, count do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- Return true when the frame's currently registered event topology still
--- matches its active elements and current spec. This deliberately compares
--- dynamic GetEvents/GetUnitlessEvents results instead of trusting a visual
--- refresh label: health colours, text modes and prediction settings can all
--- change an element's event membership without changing its update function.
local function FrameEventRoutingMatches(frame)
  if not frame or frame._msufEventRouteUnit ~= frame.MSUFUnitKey then return false end
  local routes = frame._msufElementEventRoutes
  if type(routes) ~= "table" then return false end
  local active = frame._msufActiveElements
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if EventElementAllowed(name) == true then
      local route = routes[name]
      local element = active and active[name] == true and UF.elements[name] or nil
      local update = element and ElementUpdateFunction(frame, name) or nil
      if update then
        if not route or route.update ~= update then return false end
        if not EventListsMatch(route.events, ElementEvents(element, false, frame, frame.MSUFSpec)) then
          return false
        end
        if not EventListsMatch(route.unitlessEvents, ElementEvents(element, true, frame, frame.MSUFSpec)) then
          return false
        end
      elseif route then
        return false
      end
    end
  end
  return frame._msufEventRouteNeedsIdentity == FrameNeedsIdentityLifecycle(frame)
end
UF.FrameEventRoutingMatches = FrameEventRoutingMatches

local function RefreshFrameRoutingAfterElementApply(frame)
  if not frame then return false end
  UF.OptimizeFrameHotpaths(frame)
  if FrameEventRoutingMatches(frame) then
    -- Event registration can stay intact, but active/update functions may have
    -- changed for elements that are not frame-event owners.
    UF.RebuildRuntimeStatusState(frame)
    return false
  end
  return RebuildFrameEvents(frame) == true
end

function UF.RunLeanIdentity(frame, event)
  if not FrameVisibleForEvent(frame) then return false end
  local path = frame._msufIdentityPath
  local barPath = frame._msufIdentityBarPath
  if not (path or barPath) then return false end
  local unit = frame.MSUFUnitKey
  event = event or "MSUF_UNIT_IDENTITY"
  BeginFrameEvent(frame, event)
  if not IdentityUnitExists(frame, unit) then
    EndFrameEvent(frame)
    return false
  end
  local hp, hpMax, healthPercentReady
  local power, powerMax, powerType, powerToken, powerMetaChanged
  if barPath then
    hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged = barPath(frame, event, unit)
  end
  if path then
    path(frame, event, unit,
      hp, hpMax, healthPercentReady,
      power, powerMax, powerType, powerToken, powerMetaChanged)
  end
  EndFrameEvent(frame)
  return true
end

function UF.FrameRuntimeUpdate(frame, reason)
  if not FrameVisibleForEvent(frame) then return false end
  local path = frame._msufRuntimeAllPath
  if not path then return false end
  local unit = frame.MSUFUnitKey
  reason = reason or "MSUF_FORCE_UPDATE"
  BeginFrameEvent(frame, reason)
  path(frame, reason, unit)
  EndFrameEvent(frame)
  return true
end

function UF.FrameForceUpdate(frame, reason)
  return UF.FrameRuntimeUpdate(frame, reason or "MSUF_FORCE_UPDATE")
end

function UF.UpdateRuntime(unit, reason)
  if unit and issecretvalue(unit) == true then return false end
  if unit then
    local units = UF.UnitsForConfigKey(unit)
    if not units then return false end
    local didWork = false
    for i = 1, #units do didWork = UF.FrameRuntimeUpdate(UF.frames[units[i]], reason) or didWork end
    return didWork
  end
  local didWork = false
  UF.ForEachFrame(function(frame)
    didWork = UF.FrameRuntimeUpdate(frame, reason) or didWork
  end)
  return didWork
end

local function FrameIsElementEnabled(frame, name)
  return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end
UF.FrameIsElementEnabled = FrameIsElementEnabled

function UF.OptimizeFrameHotpaths(frame)
  if not frame then return false end
  local health = UF.elements and UF.elements.Health
  if health and type(health.SelectGroupHealthUpdater) == "function" then
    health.SelectGroupHealthUpdater(frame)
  end
  local power = UF.elements and UF.elements.Power
  if power and type(power.SelectGroupPowerUpdater) == "function" then
    power.SelectGroupPowerUpdater(frame)
  end
  return true
end

local function FrameDisableElement(frame, name, deferRouting)
  if not frame then return false end
  local element = UF.elements[name]
  local active = frame._msufActiveElements
  local wasActive = active and active[name] == true
  if active then active[name] = nil end
  frame[GetUpdateKey(name)] = nil
  if wasActive and element and element.Disable then element.Disable(frame) end
  if deferRouting ~= true then RefreshFrameRoutingAfterElementApply(frame) end
  return wasActive
end

local function FrameEnableElement(frame, name)
  local element = UF.elements[name]
  if not (frame and element and ApplyElementAllowed(name) == true) then return false end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, frame.MSUFSpec)
    frame._msufCreatedElements[name] = true
  end
  if element.Enable and element.Enable(frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    RefreshFrameRoutingAfterElementApply(frame)
    return false
  end
  frame[GetUpdateKey(name)] = SelectElementUpdate(element, frame)
  frame._msufActiveElements[name] = true
  RefreshFrameRoutingAfterElementApply(frame)
  return true
end

function UF.AttachFrameMethods(frame)
  if not frame then return frame end
  if frame._msufOufCoreMethods == true then
    local eventScript = frame._msufCoreScope == "group" and GroupFrameOnEvent or FrameOnEvent
    if frame.SetScript and frame._msufCoreEventScript ~= eventScript then
      frame:SetScript("OnEvent", eventScript)
      frame._msufCoreEventScript = eventScript
    end
    return frame
  end
  frame._msufOufCoreMethods = true
  frame._msufDispatchToken = frame._msufDispatchToken or 0
  -- Reserve the transient dispatch field while the frame is built, outside
  -- combat event delivery. Clear it immediately so the established contract
  -- remains exact: inactive dispatch state is nil, never false.
  if frame._msufDispatchActive == nil then
    frame._msufDispatchActive = false
    frame._msufDispatchActive = nil
  end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  frame.EnableElement = FrameEnableElement
  frame.DisableElement = FrameDisableElement
  frame.IsElementEnabled = FrameIsElementEnabled
  frame.ForceUpdate = function(self, reason) return UF.FrameForceUpdate(self, reason) end
  frame.UpdateAllElements = function(self, event) return UF.FrameRuntimeUpdate(self, event or "MSUF_FORCE_UPDATE") end
  local eventScript = frame._msufCoreScope == "group" and GroupFrameOnEvent or FrameOnEvent
  if frame.SetScript then
    frame:SetScript("OnEvent", eventScript)
    frame._msufCoreEventScript = eventScript
  end
  return frame
end

function UF.AttachFrame(frame, opts)
  if not frame then return nil end
  opts = type(opts) == "table" and opts or nil
  frame._msufCoreScope = opts and opts.scope or frame._msufCoreScope or "single"
  UF.AttachFrameMethods(frame)
  frame._msufVisualRoot = opts and opts.visualRoot or frame._msufVisualRoot or frame
  if frame.HookScript and frame._msufCoreVisibilityHooked ~= true then
    frame._msufCoreVisibilityHooked = true
    frame:HookScript("OnShow", FrameOnShow)
    frame:HookScript("OnHide", FrameOnHide)
    frame._msufCoreVisible = not frame.IsVisible or frame:IsVisible()
  end
  if frame._msufCoreVisible == nil then
    frame._msufCoreVisible = not frame.IsVisible or frame:IsVisible()
  end
  if UF.attachedFrames[frame] ~= true then
    UF.attachedFrames[frame] = true
    UF.attachedFrameList[#UF.attachedFrameList + 1] = frame
  end
  return frame
end

function UF.ForEachFrame(fn, a, b, c)
  if type(fn) ~= "function" then return end
  for i = 1, #UF.frameList do
    local frame = UF.frameList[i]
    if frame then fn(frame, nil, a, b, c) end
  end
end

function UF.ForEachAttachedFrame(fn, scope)
  if type(fn) ~= "function" then return end
  for i = 1, #UF.attachedFrameList do
    local frame = UF.attachedFrameList[i]
    if frame and (scope == nil or frame._msufCoreScope == scope) then fn(frame) end
  end
end

function UF.SetFrameSpec(frame, spec, unitFallback)
  if not (frame and spec) then return nil end
  local unit = spec.unit or unitFallback or frame.MSUFUnitKey
  frame.MSUFSpec = spec
  frame._msufCoreSpecEnabled = spec.enabled ~= false
  frame.MSUFUnitKey = unit
  frame.unitKey = unit
  frame.cachedConfig = spec
  frame.configKey = spec.key
  return frame
end

function UF.OnUnitChanged(frame, oldUnit, newUnit)
  if not frame then return false end
  if newUnit ~= nil then
    frame.MSUFUnitKey = newUnit
    frame.unitKey = newUnit
  end
  frame._msufUnitState = nil
  RebuildFrameEvents(frame)
  if frame._msufCoreScope == "group" then
    RefreshGroupFrameState(frame, "MSUF_GF_UNIT_IDENTITY")
    RefreshIdentityHealthBackground(frame)
  else
    UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  end
  local A3 = MSUF and MSUF.MSUF_Auras3
  local active = frame._msufActiveElements
  if active and active.Auras == true and A3 and type(A3.OnFrameUnitChanged) == "function" then
    A3.OnFrameUnitChanged(frame, oldUnit, newUnit)
  end
  return true
end

function UF.DetachFrame(frame)
  if not frame then return false end
  local wasApplying = UF._msufApplyingSpec
  UF._msufApplyingSpec = true
  if frame._msufActiveElements then
    for name in pairs(frame._msufActiveElements) do
      FrameDisableElement(frame, name, true)
    end
  end
  -- Element teardown makes this frame ineligible for immediate reattachment.
  -- Notify an active castbar lifecycle owner before erasing the wrapped event
  -- routes so it can promote itself to the minimal event fallback.
  if frame._msufHealthLifecycleSink then
    ClearHealthLifecycleSink(frame, true)
  end
  ClearFrameEvents(frame)
  frame._msufIdentityFns = nil
  frame._msufIdentityCount = nil
  frame._msufIdentityLabels = nil
  frame._msufIdentityPath = nil
  frame._msufIdentityBarPath = nil
  frame._msufRuntimeAllFns = nil
  frame._msufRuntimeAllCount = nil
  frame._msufRuntimeAllLabels = nil
  frame._msufRuntimeAllPath = nil
  frame._msufGroupIdentityFns = nil
  frame._msufGroupIdentityCount = nil
  frame._msufGroupIdentityLabels = nil
  frame._msufGroupIdentityPath = nil
  frame._msufGroupLifecyclePlan = nil
  frame._msufCoreScope = nil
  frame._msufVisualRoot = nil
  UF.attachedFrames[frame] = nil
  for i = #UF.attachedFrameList, 1, -1 do
    if UF.attachedFrameList[i] == frame then
      table_remove(UF.attachedFrameList, i)
      break
    end
  end
  if SyncGroupLifecycleDriver then SyncGroupLifecycleDriver() end
  UF._msufApplyingSpec = wasApplying
  if wasApplying ~= true and UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
  return true
end

function UF.GetFrame(unit)
  if unit and issecretvalue(unit) == true then return nil end
  return UF.frames[unit]
end

function UF.SetHealthLifecycleSink(unit, sink, owner)
  if type(sink) ~= "function" or owner == nil then return false end
  local frame = UF.GetFrame(unit)
  if not (frame
    and UF.attachedFrames[frame] == true
    and frame.MSUFUnitKey == unit
    and frame._msufCoreSpecEnabled == true
    and frame._msufCoreVisible == true
    and frame._msufActiveElements and frame._msufActiveElements.Health == true
    and type(frame.UNIT_HEALTH) == "function"
    and type(frame.UNIT_CONNECTION) == "function") then
    return false
  end
  if frame._msufHealthLifecycleSinkOwner ~= nil
    and frame._msufHealthLifecycleSinkOwner ~= owner then
    return false
  end

  frame._msufHealthLifecycleSink = sink
  frame._msufHealthLifecycleSinkOwner = owner
  frame._msufHealthLifecycleSinkUnit = unit
  return RefreshHealthLifecycleSinkRoutes(frame) == true, frame
end

function UF.ClearHealthLifecycleSink(frame, owner)
  if not frame or frame._msufHealthLifecycleSinkOwner ~= owner then return false end
  return ClearHealthLifecycleSink(frame, false)
end

function UF.Apply(unit, applyMask)
  local factory = UF.Factory
  if not (factory and factory.Apply) then return false end
  return factory.Apply(unit, applyMask)
end

function UF.ForceUpdate(unit)
  if InCombatLockdown and InCombatLockdown() then
    if UF.MarkDirty then UF.MarkDirty(unit) end
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then factory.EnsureDeferredDriver() end
    return false
  end
  if unit then
    if issecretvalue(unit) == true then return false end
    local units = UF.UnitsForConfigKey(unit)
    if not units then return false end
    for i = 1, #units do UF.FrameForceUpdate(UF.frames[units[i]], "MSUF_FORCE_UPDATE") end
    return true
  end
  UF.ForEachFrame(function(frame) UF.FrameForceUpdate(frame, "MSUF_FORCE_UPDATE") end)
  return true
end

function UF.ApplyElementToFrame(frame, name, spec, updateReason)
  local element = UF.elements[name]
  if not (frame and element) then return false end
  if spec then UF.SetFrameSpec(frame, spec) end
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  if ApplyElementAllowed(name) ~= true or UF.ElementEnabled(element, frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
    return true
  end
  if element.Create and not frame._msufCreatedElements[name] then
    element.Create(frame, frame.MSUFSpec)
    frame._msufCreatedElements[name] = true
  end
  if element.Apply then element.Apply(frame, frame.MSUFSpec) end
  if element.Enable and element.Enable(frame, frame.MSUFSpec) == false then
    FrameDisableElement(frame, name, true)
    if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
    return true
  end
  local update = SelectElementUpdate(element, frame)
  frame[GetUpdateKey(name)] = update
  frame._msufActiveElements[name] = true
  local immediateReason = updateReason
  if immediateReason == nil and element.UpdateOnApply == true then
    immediateReason = "MSUF_ELEMENT_APPLY"
  end
  if immediateReason and update then update(frame, immediateReason, frame.MSUFUnitKey) end
  if frame._msufElementApplyBatch ~= true then RefreshFrameRoutingAfterElementApply(frame) end
  return true
end

local function ApplyElementSelection(frame, selection, spec, updateReason, selectionIsMask)
  if not frame or (selection ~= true and type(selection) ~= "table") then return false end
  local wasApplying = UF._msufApplyingSpec
  local wasBatching = frame._msufElementApplyBatch
  UF._msufApplyingSpec = true
  frame._msufElementApplyBatch = true
  if spec then UF.SetFrameSpec(frame, spec) end

  if selectionIsMask == true then
    local full = selection == true
    for i = 1, #UF.elementOrder do
      local name = UF.elementOrder[i]
      if full or selection[name] == true then
        UF.ApplyElementToFrame(frame, name, nil, updateReason)
      end
    end
  else
    for i = 1, #selection do
      local name = selection[i]
      if ApplyElementAllowed(name) == true then
        UF.ApplyElementToFrame(frame, name, nil, updateReason)
      end
    end
  end

  frame._msufElementApplyBatch = wasBatching
  local rebuilt = false
  if wasBatching ~= true then rebuilt = RefreshFrameRoutingAfterElementApply(frame) end
  UF._msufApplyingSpec = wasApplying
  if rebuilt and wasApplying ~= true and UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
  -- Menu dispel-overlay preview. The stand-in tint is MSUF-drawn and therefore
  -- outside the element/dirty-mask system, so re-stamp it here: this is the one
  -- funnel both full spec applies (UF.ApplySpec) and targeted element refreshes
  -- (UF.ApplyElementsToFrame, which is how unit-frame aura settings apply) pass
  -- through. A single boolean read whenever no preview is active.
  if _G.MSUF_DispelOverlayPreviewMode == true
    and type(_G.MSUF_ApplyDispelOverlayPreviewToFrame) == "function" then
    _G.MSUF_ApplyDispelOverlayPreviewToFrame(frame)
  end
  if _G.MSUF_DispelSymbolPreviewMode == true
    and type(_G.MSUF_ApplyDispelSymbolPreviewToFrame) == "function" then
    _G.MSUF_ApplyDispelSymbolPreviewToFrame(frame)
  end
  return true
end

--- Apply an ordered element list as one frame transaction. Element layout and
--- updates still run in list order, while event routing is validated/rebuilt at
--- most once after the complete spec has landed.
function UF.ApplyElementsToFrame(frame, names, spec, updateReason)
  return ApplyElementSelection(frame, names, spec, updateReason, false)
end

local DEFAULT_APPLY_MASK = Metadata.defaultApplyMask or true

function UF.ApplySpec(frame, spec, reason, mask)
  if not (frame and spec) then return false end
  UF.AttachFrame(frame, { scope = spec.scope or frame._msufCoreScope or "single" })
  mask = mask or DEFAULT_APPLY_MASK
  ApplyElementSelection(frame, mask, spec, nil, true)
  if reason then UF.FrameRuntimeUpdate(frame, reason) end
  return true
end

function UF.BeginEventRegistrationBatch()
  UF._msufApplyingSpec = true
end

function UF.EndEventRegistrationBatch()
  UF._msufApplyingSpec = nil
  if UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
end

function UF.RebuildHotEventState()
  return true
end

function UF.RebindGroupHotEventHandlers()
  return true
end

function UF.DumpIdentityList(unit)
  local frame = unit and UF.frames[unit]
  local labels = frame and frame._msufIdentityLabels
  if not labels then return "" end
  local out = {}
  for i = 1, #labels do out[i] = tostring(labels[i]) end
  return table.concat(out, ",")
end

MSUF.UnitFrames = UF
