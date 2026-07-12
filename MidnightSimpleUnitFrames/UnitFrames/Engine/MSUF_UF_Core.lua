local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
MSUF.UF = MSUF.UF or {}
MSUF.UF.Elements = MSUF.UF.Elements or {}

local UF = MSUF.UF
local Elements = UF.Elements
local Metadata = UF.Metadata or {}

local type = type
local pairs = pairs
local next = next
local tostring = tostring
local tonumber = tonumber
local table_remove = table.remove
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local issecretvalue = _G.issecretvalue or function(_) return false end

UF.version = "8.2-ouf-coalesced-dependent-identity"
UF.frames = UF.frames or {}
UF.frameList = UF.frameList or {}
UF.attachedFrames = UF.attachedFrames or {}
UF.attachedFrameList = UF.attachedFrameList or {}
UF.elements = UF.elements or {}
UF.elementOrder = UF.elementOrder or {}
UF.pendingApply = UF.pendingApply or {}
UF.pendingElementRefreshes = UF.pendingElementRefreshes or {}
UF.visualRefreshCallbacks = UF.visualRefreshCallbacks or {}
UF.initialized = UF.initialized or false

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

local EVENT_ELEMENTS = {
  Portrait = true,
  Prediction = true,
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
}

local IDENTITY_ELEMENTS = {
  NameText = true,
  HealthText = true,
  PowerText = true,
  InlineToT = true,
  Portrait = true,
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

local IDENTITY_BAR_ELEMENTS = {
  Health = true,
  Power = true,
}

local HEALTH_EVENTS = {
  UNIT_HEALTH = true,
  UNIT_MAXHEALTH = true,
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

local NONPREFIX_UNIT_EVENTS = {
  INCOMING_RESURRECT_CHANGED = true,
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

local function ReadConnectedCached(frame, unit, state)
  state = state or FreshUnitState(frame, unit)
  if state and state.connectedKnown == true then
    return state.connected == true, true
  end
  if not UnitIsConnected then return true, true end
  local connected = UnitIsConnected(unit)
  if issecretvalue(connected) == true or connected == nil then return true, false end
  return connected == true or connected == 1, true
end
UF.ReadConnectedCached = ReadConnectedCached

local function ReadDeadCached(frame, unit, state)
  state = state or FreshUnitState(frame, unit)
  if state and state.deadKnown == true then
    return state.dead == true, true
  end
  if not (UnitIsDeadOrGhost or UnitIsDead) then return false, true end
  local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) or nil
  if (issecretvalue(dead) == true or dead == nil) and UnitIsDead then
    dead = UnitIsDead(unit)
  end
  if issecretvalue(dead) == true or dead == nil then return false, false end
  return dead == true or dead == 1, true
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
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then
    return "DISPEL_TYPE"
  elseif value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then
    return "ANY_DEBUFF"
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

local function AbsorbTextureTestEnabledForScope(scope)
  if _G.MSUF_AbsorbTextureTestMode ~= true then return false end
  local wanted = NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
  return wanted == "shared" or wanted == NormalizeAbsorbTestScope(scope)
end
UF.AbsorbTextureTestEnabledForScope = AbsorbTextureTestEnabledForScope

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

local function GradientScopedValue(conf, general, key, fallback)
  if conf and conf.hlOverride == true and conf.gradientOverride == true and conf[key] ~= nil then
    return conf[key]
  end
  if general and general[key] ~= nil then return general[key] end
  return fallback
end

local function ResolveBarGradient(conf, general, enabledKey)
  local left = GradientScopedValue(conf, general, "gradientDirLeft", false) == true
  local right = GradientScopedValue(conf, general, "gradientDirRight", false) == true
  local up = GradientScopedValue(conf, general, "gradientDirUp", false) == true
  local down = GradientScopedValue(conf, general, "gradientDirDown", false) == true
  if not (left or right or up or down) then
    local legacy = GradientScopedValue(conf, general, "gradientDirection", "RIGHT")
    left = legacy == "LEFT"
    up = legacy == "UP"
    down = legacy == "DOWN"
    right = not (left or up or down)
  end
  return {
    enabled = GradientScopedValue(conf, general, enabledKey, false) == true,
    strength = Clamp01(GradientScopedValue(conf, general, "gradientStrength", 0.45), 0.45),
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
  dst.healA = Clamp01(general and general.healPredictionColorA, 0.45)
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
  return "MSUF_" .. tostring(unit or "unknown")
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
  return HotElementAllowed(name) == true
    or EVENT_ELEMENTS[name] == true
    or STATUS_EVENT_ELEMENTS[name] == true
end

local function ApplyElementAllowed(name)
  if HotElementAllowed(name) == true then return true end
  if Metadata.runtimeUpdateOwners and Metadata.runtimeUpdateOwners[name] == true then return true end
  if Metadata.defaultApplyMask and Metadata.defaultApplyMask[name] == true then return true end
  return false
end
UF.ApplyElementAllowed = ApplyElementAllowed

function UF.ElementEnabled(element, frame, spec)
  return not element or type(element.IsEnabled) ~= "function" or element.IsEnabled(frame, spec) ~= false
end

function UF.RegisterElement(name, element)
  if type(name) ~= "string" or type(element) ~= "table" then return false end
  if not UF.elements[name] then
    UF.elementOrder[#UF.elementOrder + 1] = name
  end
  UF.elements[name] = element
  Elements[name] = element
  GetUpdateKey(name)
  return true
end

local function FrameVisibleForEvent(frame)
  if not frame then return false end
  local spec = frame.MSUFSpec
  if spec and spec.enabled == false then return false end
  if frame.IsVisible and not frame:IsVisible()
    and _G.MSUF_PreviewTestMode ~= true
    and _G.MSUF_BossTestMode ~= true
    and _G.MSUF2_BossUnitframePreviewActive ~= true then
    return false
  end
  return true
end

local function IdentityUnitExists(frame, unit)
  if not IsUnitToken(unit) then return false end
  if _G.MSUF_PreviewTestMode == true
    or _G.MSUF_BossTestMode == true
    or _G.MSUF2_BossUnitframePreviewActive == true
    or _G.MSUF_UnitEditModeActive == true then
    return true
  end
  return UnitExistsSafe(unit)
end

local function BeginFrameEvent(frame)
  frame._msufDispatchToken = (frame._msufDispatchToken or 0) + 1
  frame._msufDispatchActive = true
  -- Keep the per-frame state table allocated, but invalidate its contents for
  -- this dispatch. RefreshUnitState still performs the same full read on the
  -- first consumer, while later consumers in the same dispatch share it.
  local state = frame._msufUnitState
  if state then
    state.ready = false
    state.dispatchToken = nil
    state.identityReady = nil
  end
end

local function EndFrameEvent(frame)
  if frame._msufDeferDispatchEnd == true then return end
  frame._msufDispatchActive = nil
end

local function FrameOnEvent(frame, event, unit, ...)
  if not FrameVisibleForEvent(frame) then return end
  local path = frame[event]
  if path then return path(frame, event, unit, ...) end
end

local groupLifecycleDriver

local function LifecycleUpdate(frame, name)
  local active = frame and frame._msufActiveElements
  if not (active and active[name] == true) then return nil end
  local key = GetUpdateKey(name)
  return key and frame[key] or nil
end

local function RunGroupLifecycleFollowers(frame, event)
  local unit = frame.unit

  local power, powerMax, powerType, powerToken, powerMetaChanged
  local update = LifecycleUpdate(frame, "Power")
  if update then
    power, powerMax, powerType, powerToken, powerMetaChanged = update(frame, event, unit)
  end
  update = LifecycleUpdate(frame, "PowerText")
  if update then
    update(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
  end

  update = LifecycleUpdate(frame, "NameText")
  if update then update(frame, event, unit) end

  update = LifecycleUpdate(frame, "Portrait")
  if update then update(frame, event, unit) end

  local hpBar = frame.hpBar
  local hp = hpBar and hpBar._msufHealthValueUnit == unit and hpBar._msufHealthValue or nil
  local hpMax = hpBar and hpBar._msufHealthMaxUnit == unit and hpBar._msufHealthMax or nil
  if issecretvalue(hp) == true then hp = nil end
  if issecretvalue(hpMax) == true then hpMax = nil end

  update = LifecycleUpdate(frame, "GroupStatusRuntime")
  if update then update(frame, event, unit, hp) end
  update = LifecycleUpdate(frame, "GroupRangeFade")
  if update then update(frame, event, unit) end
  update = LifecycleUpdate(frame, "GroupVisuals")
  if update then update(frame, event, unit, hp, hpMax) end
end

--- Refresh one secure group child from a coherent authoritative snapshot.
--- The caller's reason is diagnostic only: canonical lifecycle semantics keep
--- Health/Prediction/Text and all group followers on the same narrow path.
local function RefreshGroupFrameState(frame, _reason)
  if not (frame and frame._msufCoreScope == "group" and FrameVisibleForEvent(frame)) then
    return false
  end
  local event = "PARTY_MEMBER_ENABLE"
  frame._msufGroupStateRefresh = true
  frame._msufDeferDispatchEnd = true
  if frame[event] then
    FrameOnEvent(frame, event, nil)
  else
    BeginFrameEvent(frame)
  end
  RunGroupLifecycleFollowers(frame, event)
  frame._msufDeferDispatchEnd = nil
  EndFrameEvent(frame)
  frame._msufGroupStateRefresh = nil
  return true
end
UF.RefreshGroupFrameState = RefreshGroupFrameState

local function GroupFrameOnShow(frame)
  RefreshGroupFrameState(frame, "MSUF_GF_ONSHOW")
end

local function EnsureGroupLifecycleDriver()
  if groupLifecycleDriver or not CreateFrame then return groupLifecycleDriver end
  groupLifecycleDriver = CreateFrame("Frame")
  groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_ENABLE")
  groupLifecycleDriver:RegisterEvent("PARTY_MEMBER_DISABLE")
  groupLifecycleDriver:SetScript("OnEvent", function(_, event)
    local frames = UF.attachedFrameList
    for i = 1, #frames do
      local frame = frames[i]
      if frame and frame._msufCoreScope == "group" and FrameVisibleForEvent(frame) then
        -- These events are a group invalidation barrier. Ignore unitTarget so
        -- AI/follower transitions refresh every frame with its own bound unit.
        RefreshGroupFrameState(frame, event)
      end
    end
  end)
  return groupLifecycleDriver
end

local function IsUnitEvent(event)
  return type(event) == "string"
    and (event:sub(1, 5) == "UNIT_" or NONPREFIX_UNIT_EVENTS[event] == true)
end

local function DependentSource(frame, event)
  if event == "UNIT_TARGET" then
    return frame and UF.ParentUnitForDependentUnit(frame.unit)
  end
  if event == "UNIT_PET" and frame and frame.unit == "pet" then
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

local function CompileFrameEventPath(frame, event, list)
  local target = frame._msufFrameUnitEventTargets and frame._msufFrameUnitEventTargets[event]
  local count = #list
  local healthEvent = HEALTH_EVENTS[event] == true
  local powerEvent = POWER_EVENTS[event] == true
  if healthEvent or powerEvent then
    local barUpdate = healthEvent and frame[GetUpdateKey("Health")] or frame[GetUpdateKey("Power")]
    local textUpdate = healthEvent and frame[GetUpdateKey("HealthText")] or frame[GetUpdateKey("PowerText")]
    local predictionUpdate = healthEvent and frame[GetUpdateKey("Prediction")] or nil
    local barFn, textFn, predictionFn
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
      else
        direct = false
        break
      end
    end
    if direct == true and (barFn or textFn or predictionFn) then
      if healthEvent then
        if target then
          return function(self, ev, _unit, ...)
            BeginFrameEvent(self)
            local hp, hpMax, percentReady
            if barFn then hp, hpMax, percentReady = barFn(self, ev, target, ...) end
            if predictionFn then
              if percentReady == true then predictionFn(self, ev, target, nil, nil, ...) else predictionFn(self, ev, target, hp, hpMax, ...) end
            end
            if textFn then
              if percentReady == true then textFn(self, ev, target, nil, nil, ...) else textFn(self, ev, target, hp, hpMax, ...) end
            end
            EndFrameEvent(self)
          end
        end
        return function(self, ev, unit, ...)
          BeginFrameEvent(self)
          local u = routeUnitless == true and self.unit or (unit or self.unit)
          local hp, hpMax, percentReady
          if barFn then hp, hpMax, percentReady = barFn(self, ev, u, ...) end
          if predictionFn then
            if percentReady == true then predictionFn(self, ev, u, nil, nil, ...) else predictionFn(self, ev, u, hp, hpMax, ...) end
          end
          if textFn then
            if percentReady == true then textFn(self, ev, u, nil, nil, ...) else textFn(self, ev, u, hp, hpMax, ...) end
          end
          EndFrameEvent(self)
        end
      end
      if target then
        return function(self, ev, _unit, ...)
          BeginFrameEvent(self)
          local power, powerMax, powerType, powerToken, metaChanged
          if barFn then power, powerMax, powerType, powerToken, metaChanged = barFn(self, ev, target, ...) end
          if textFn then textFn(self, ev, target, powerMax == nil and nil or power, powerMax, powerType, powerToken, metaChanged, ...) end
          EndFrameEvent(self)
        end
      end
      return function(self, ev, unit, ...)
        BeginFrameEvent(self)
        local u = routeUnitless == true and self.unit or (unit or self.unit)
        local power, powerMax, powerType, powerToken, metaChanged
        if barFn then power, powerMax, powerType, powerToken, metaChanged = barFn(self, ev, u, ...) end
        if textFn then textFn(self, ev, u, powerMax == nil and nil or power, powerMax, powerType, powerToken, metaChanged, ...) end
        EndFrameEvent(self)
      end
    end
  end
  if count == 2 then
    local update = list[1]
    if list[2] == true then
      return function(self, ev, _unit, ...)
        BeginFrameEvent(self)
        update(self, ev, self.unit, ...)
        EndFrameEvent(self)
      end
    elseif target then
      return function(self, ev, _unit, ...)
        BeginFrameEvent(self)
        update(self, ev, target, ...)
        EndFrameEvent(self)
      end
    end
    return function(self, ev, unit, ...)
      BeginFrameEvent(self)
      update(self, ev, unit or self.unit, ...)
      EndFrameEvent(self)
    end
  end

  if target then
    return function(self, ev, unit, ...)
      BeginFrameEvent(self)
      for i = 1, count, 2 do
        local update = list[i]
        update(self, ev, list[i + 1] == true and self.unit or target, ...)
      end
      EndFrameEvent(self)
    end
  end

  return function(self, ev, unit, ...)
    BeginFrameEvent(self)
    for i = 1, count, 2 do
      local update = list[i]
      update(self, ev, list[i + 1] == true and self.unit or (unit or self.unit), ...)
    end
    EndFrameEvent(self)
  end
end

local function RegisterFrameEvent(frame, event, unitless)
  if not (frame and frame.RegisterEvent) then return end
  if frame._msufCoreScope == "group"
    and GROUP_LIFECYCLE_EVENTS[event] == true
    and EnsureGroupLifecycleDriver() then
    return
  end
  if unitless == true or not IsUnitEvent(event) or not frame.RegisterUnitEvent then
    frame:RegisterEvent(event)
    return
  end
  local source = DependentSource(frame, event) or frame.unit
  if not IsUnitToken(source) then
    frame:RegisterEvent(event)
    return
  end
  frame:RegisterUnitEvent(event, source)
  if source ~= frame.unit then
    frame._msufFrameUnitEvents = frame._msufFrameUnitEvents or {}
    frame._msufFrameUnitEventTargets = frame._msufFrameUnitEventTargets or {}
    frame._msufFrameUnitEvents[event] = source
    frame._msufFrameUnitEventTargets[event] = frame.unit
  end
end

local function ClearFrameEvents(frame)
  if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
  if frame then
    local names = frame._msufEventNames
    if names then
      for i = 1, #names do
        frame[names[i]] = nil
        names[i] = nil
      end
    end
    frame._msufEvents = nil
    frame._msufEventNames = nil
    frame._msufFrameUnitEvents = nil
    frame._msufFrameUnitEventTargets = nil
    frame._msufElementEventRoutes = nil
    frame._msufEventRouteUnit = nil
    frame._msufEventRouteNeedsIdentity = nil
  end
end

local function ElementUpdateFunction(frame, name)
  local key = UPDATE_KEYS[name]
  return key and frame[key] or nil
end

local function FrameHasActiveElement(frame, name)
  return frame and frame._msufActiveElements and frame._msufActiveElements[name] == true
end

local function IdentityEventUpdate(frame, event)
  if not frame then return end
  event = event or "MSUF_UNIT_IDENTITY"
  local unit = frame.unit
  if not IdentityUnitExists(frame, unit) then return end
  local barPath = frame._msufIdentityBarPath
  if barPath then barPath(frame, event, unit) end
  local path = frame._msufIdentityPath
  if path then return path(frame, event, unit) end
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

  local scheduleOnce = _G.MSUF_ScheduleOnce
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
  if type(unit) ~= "string" or unit:sub(1, 4) ~= "boss" then return false end
  local index = tonumber(unit:sub(5))
  return index and index >= 1 and index <= 5
end

local function AddIdentityLifecycleHandlers(frame)
  if not FrameNeedsIdentityLifecycle(frame) then return end
  local unit = frame.unit
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
    local fn = list[1]
    return function(frame, event, unit)
      return fn(frame, event, unit)
    end
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

local function BuildRuntimeList(frame, include, listKey, countKey, labelKey, pathKey)
  local list = frame[listKey] or {}
  local labels = frame[labelKey] or {}
  frame[listKey], frame[labelKey] = list, labels
  local n = 0
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if include(frame, name) == true then
      local update = ElementUpdateFunction(frame, name)
      if update then
        n = n + 1
        list[n] = update
        labels[n] = name
      end
    end
  end
  for i = n + 1, #list do list[i] = nil end
  for i = n + 1, #labels do labels[i] = nil end
  frame[countKey] = n > 0 and n or nil
  if pathKey then
    frame[pathKey] = CompileRuntimePath(list, n)
  end
end

local function CompileIdentityBarPath(frame)
  local active = frame and frame._msufActiveElements
  if not active then return nil end
  local health = active.Health == true and ElementUpdateFunction(frame, "Health") or nil
  local power = active.Power == true and ElementUpdateFunction(frame, "Power") or nil
  if health and power then
    return function(self, event, unit)
      health(self, event, unit)
      power(self, event, unit)
    end
  end
  if health then
    return function(self, event, unit)
      health(self, event, unit)
    end
  end
  if power then
    return function(self, event, unit)
      power(self, event, unit)
    end
  end
  return nil
end

function UF.RebuildRuntimeStatusState(frame)
  if not frame then return false end
  BuildRuntimeList(frame, function(_, name)
    return IDENTITY_ELEMENTS[name] == true and FrameHasActiveElement(frame, name)
  end, "_msufIdentityFns", "_msufIdentityCount", "_msufIdentityLabels", "_msufIdentityPath")
  BuildRuntimeList(frame, function(_, name)
    return HotElementAllowed(name) == true and FrameHasActiveElement(frame, name)
  end, "_msufRuntimeAllFns", "_msufRuntimeAllCount", "_msufRuntimeAllLabels", "_msufRuntimeAllPath")
  frame._msufGroupIdentityFns = frame._msufIdentityFns
  frame._msufGroupIdentityCount = frame._msufIdentityCount
  frame._msufGroupIdentityLabels = frame._msufIdentityLabels
  frame._msufGroupIdentityPath = frame._msufIdentityPath
  frame._msufIdentityBarPath = CompileIdentityBarPath(frame)
  return true
end

local function SnapshotEventList(events)
  if type(events) ~= "table" then return nil end
  local snapshot = {}
  for i = 1, #events do snapshot[i] = events[i] end
  return snapshot
end

local function RebuildFrameEvents(frame)
  if not frame then return false end
  ClearFrameEvents(frame)
  local routes = {}
  frame._msufElementEventRoutes = routes
  frame._msufEventRouteUnit = frame.unit
  local active = frame._msufActiveElements
  if not active then
    frame._msufEventRouteNeedsIdentity = false
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
        routes[name] = {
          update = update,
          -- Providers normally return immutable constants, but snapshot the
          -- lists so a future provider that reuses/mutates a table cannot make
          -- the routing comparator accept stale registrations.
          events = SnapshotEventList(events),
          unitlessEvents = SnapshotEventList(unitlessEvents),
        }
        if type(events) == "table" then
          for j = 1, #events do AddEventHandler(frame, events[j], update, false) end
        end
        if type(unitlessEvents) == "table" then
          for j = 1, #unitlessEvents do AddEventHandler(frame, unitlessEvents[j], update, true) end
        end
      end
    end
  end
  frame._msufEventRouteNeedsIdentity = FrameNeedsIdentityLifecycle(frame)
  AddIdentityLifecycleHandlers(frame)
  local events = frame._msufEvents
  local names = frame._msufEventNames
  if events and names then
    for n = 1, #names do
      local event = names[n]
      local list = events[event]
      local unitless = false
      for i = 2, #list, 2 do
        if list[i] == true then unitless = true break end
      end
      RegisterFrameEvent(frame, event, unitless)
      frame[event] = CompileFrameEventPath(frame, event, list)
    end
  end
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
  if not frame or frame._msufEventRouteUnit ~= frame.unit then return false end
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
  local unit = frame.unit
  if not IdentityUnitExists(frame, unit) then return false end
  BeginFrameEvent(frame)
  event = event or "MSUF_UNIT_IDENTITY"
  if barPath then barPath(frame, event, unit) end
  if path then path(frame, event, unit) end
  EndFrameEvent(frame)
  return true
end

function UF.FrameRuntimeUpdate(frame, reason)
  if not FrameVisibleForEvent(frame) then return false end
  local path = frame._msufRuntimeAllPath
  if not path then return false end
  BeginFrameEvent(frame)
  local unit = frame.unit
  reason = reason or "MSUF_FORCE_UPDATE"
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
  frame[GetUpdateKey(name)] = element.Update
  frame._msufActiveElements[name] = true
  RefreshFrameRoutingAfterElementApply(frame)
  return true
end

function UF.AttachFrameMethods(frame)
  if not frame then return frame end
  if frame._msufOufCoreMethods == true then return frame end
  frame._msufOufCoreMethods = true
  frame._msufDispatchToken = frame._msufDispatchToken or 0
  frame._msufCreatedElements = frame._msufCreatedElements or {}
  frame._msufActiveElements = frame._msufActiveElements or {}
  frame.EnableElement = FrameEnableElement
  frame.DisableElement = FrameDisableElement
  frame.IsElementEnabled = FrameIsElementEnabled
  frame.ForceUpdate = function(self, reason) return UF.FrameForceUpdate(self, reason) end
  frame.UpdateAllElements = function(self, event) return UF.FrameRuntimeUpdate(self, event or "MSUF_FORCE_UPDATE") end
  if frame.SetScript then frame:SetScript("OnEvent", FrameOnEvent) end
  return frame
end

function UF.AttachFrame(frame, opts)
  if not frame then return nil end
  opts = type(opts) == "table" and opts or nil
  UF.AttachFrameMethods(frame)
  frame._msufCoreScope = opts and opts.scope or frame._msufCoreScope or "single"
  frame._msufVisualRoot = opts and opts.visualRoot or frame._msufVisualRoot or frame
  if frame._msufCoreScope == "group"
    and frame.HookScript
    and frame._msufGroupOnShowHooked ~= true then
    frame._msufGroupOnShowHooked = true
    frame:HookScript("OnShow", GroupFrameOnShow)
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
  local unit = spec.unit or unitFallback or frame.unit
  frame.MSUFSpec = spec
  frame.MSUFUnitKey = unit
  frame.unit = unit
  frame.unitKey = unit
  frame.cachedConfig = spec
  frame.configKey = spec.key
  return frame
end

function UF.OnUnitChanged(frame, oldUnit, newUnit)
  if not frame then return false end
  if newUnit ~= nil then
    frame.unit = newUnit
    frame.unitKey = newUnit
  end
  frame._msufUnitState = nil
  RebuildFrameEvents(frame)
  if frame._msufCoreScope == "group" then
    RefreshGroupFrameState(frame, "MSUF_GF_UNIT_IDENTITY")
  else
    UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY")
  end
  local A3 = MSUF and MSUF.MSUF_Auras3
  if A3 and type(A3.OnFrameUnitChanged) == "function" then
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
  frame._msufGroupIdentityPath = nil
  frame._msufCoreScope = nil
  frame._msufVisualRoot = nil
  UF.attachedFrames[frame] = nil
  for i = #UF.attachedFrameList, 1, -1 do
    if UF.attachedFrameList[i] == frame then
      table_remove(UF.attachedFrameList, i)
      break
    end
  end
  UF._msufApplyingSpec = wasApplying
  if wasApplying ~= true and UF.SyncRuntimeDriver then UF.SyncRuntimeDriver() end
  return true
end

function UF.GetFrame(unit)
  if unit and issecretvalue(unit) == true then return nil end
  return UF.frames[unit]
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
  frame[GetUpdateKey(name)] = element.Update
  frame._msufActiveElements[name] = true
  local immediateReason = updateReason
  if immediateReason == nil and element.UpdateOnApply == true then
    immediateReason = "MSUF_ELEMENT_APPLY"
  end
  if immediateReason and element.Update then element.Update(frame, immediateReason, frame.unit) end
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
