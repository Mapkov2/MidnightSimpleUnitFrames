--- UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua
--- Compiles group-frame SavedVariables into unit-frame specs.
---
--- The compiled spec is the contract consumed by UF.ApplySpec. Keep expensive
--- DB/default/media decisions here so Adapter/Runtime/Visual elements can run
--- from cached spec data during roster and unit events.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local floor = math.floor
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetTime = _G.GetTime
local wipe = _G.wipe or table.wipe
local Clamp01 = UF.Clamp01 or function(value, fallback)
  value = tonumber(value)
  if value == nil then value = fallback end
  value = value or 0
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end
local Num = UF.NumberWithFallback or function(value, fallback)
  -- Perf smoke can load group config without the full UF core helper table.
  -- Keep the compiled-spec path deterministic instead of depending on load-order side effects.
  local number = tonumber(value)
  if number ~= nil then return number end
  return fallback
end
local NormalizeDispelDetectTrigger = UF.NormalizeDispelDetectTrigger or function(value)
  value = tostring(value or ""):upper()
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
  if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
  if value == "PLAYER_CAST" or value == "CAST_BY_ME" or value == "MY_DEBUFF" then return "PLAYER_CAST" end
  return "BY_ME"
end
local NormalizeDispelOverlayTrigger = UF.NormalizeDispelOverlayTrigger or function(value)
  value = tostring(value or ""):upper()
  if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
  return NormalizeDispelDetectTrigger(value)
end
local NormalizeDispelOverlayStyle = UF.NormalizeDispelOverlayStyle or function(value)
  if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
  return "FULL"
end
local DISPEL_OVERLAY_121_PTR_DISABLED = false
local NormalizeRangeFadeLayerMode = UF.NormalizeRangeFadeLayerMode or function(value)
  if value == "health" or value == "hp" or value == "hpbar" or value == "HP" or value == 2 then return "health" end
  return "frame"
end
local NormalizeAbsorbTestScope = UF.NormalizeAbsorbTestScope or function(scope)
  scope = tostring(scope or "shared"):lower()
  scope = scope:gsub("%s+", "")
  scope = scope:gsub("%-", "_")
  if scope == "" or scope == "all" or scope == "global" then return "shared" end
  if scope == "gf_party" or scope == "group_party" or scope == "gfparty" then return "party" end
  if scope == "gf_raid" or scope == "gf_mythicraid" or scope == "group_raid" or scope == "gfraid" or scope == "mythic" or scope == "mythicraid" then return "raid" end
  if scope == "focus_target" then return "focustarget" end
  if scope == "targetoftarget" or scope == "tot" then return "targettarget" end
  return scope
end
local AbsorbTextureTestEnabledForScope = UF.AbsorbTextureTestEnabledForScope or function(scope)
  if _G.MSUF_AbsorbTextureTestMode ~= true then return false end
  local wanted = NormalizeAbsorbTestScope(_G.MSUF_AbsorbTextureTestScope)
  return wanted == "shared" or wanted == NormalizeAbsorbTestScope(scope)
end
local ScopedValue = UF.ConfigScopedValue or function(conf, general, key, fallback)
  if conf and conf.hlOverride == true and conf[key] ~= nil then return conf[key] end
  if general and general[key] ~= nil then return general[key] end
  return fallback
end
local CompileBorderPriority = UF.CompileBorderPriority or function(conf, general)
  local function Read(key, legacyKey, fallback)
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
  local aliases = {
    Dispel = "dispel", DISPEL = "dispel", Magic = "dispel", MAGIC = "dispel", Curse = "dispel", CURSE = "dispel",
    Disease = "dispel", DISEASE = "dispel", Poison = "dispel", POISON = "dispel", Bleed = "dispel", BLEED = "dispel",
    Aggro = "aggro", AGGRO = "aggro", Purge = "purge", PURGE = "purge", BossTarget = "bossTarget",
    Boss_Target = "bossTarget", ["Boss Target"] = "bossTarget", ["boss target"] = "bossTarget",
    boss_target = "bossTarget", bosstarget = "bossTarget", BOSS_TARGET = "bossTarget",
  }
  local allowed, defaults, order, used = { dispel = true, aggro = true, purge = true, bossTarget = true }, { "dispel", "aggro", "purge", "bossTarget" }, {}, {}
  local raw = Read("hlPrioOrder", "highlightPrioOrder", nil)
  if type(raw) == "table" then
    for i = 1, #raw do
      local key = raw[i]
      if type(key) == "string" then key = aliases[key] or key end
      if allowed[key] and not used[key] then order[#order + 1], used[key] = key, true end
    end
  end
  for i = 1, #defaults do if not used[defaults[i]] then order[#order + 1], used[defaults[i]] = defaults[i], true end end
  local enabled = Read("hlPrioEnabled", "highlightPrioEnabled", false)
  return enabled == true or enabled == 1 or enabled == "1", order
end
local GRADIENT_DIR_KEYS = { LEFT = true, RIGHT = true, UP = true, DOWN = true }
local function GradientKeyActive(conf, key)
  if not (conf and conf.hlOverride == true and conf.gradientOverride == true) then return false end
  if conf.gradientOverrideVersion ~= 2 then return conf[key] ~= nil end
  return type(conf.gradientOverrideKeys) == "table" and conf.gradientOverrideKeys[key] == true
end

local function GradientScopedValue(conf, general, key, fallback)
  if GradientKeyActive(conf, key) and conf[key] ~= nil then return conf[key] end
  if general and general[key] ~= nil then return general[key] end
  return fallback
end

local function FallbackResolveBarGradient(conf, general, enabledKey)
  local left = GradientScopedValue(conf, general, "gradientDirLeft", false) == true
  local right = GradientScopedValue(conf, general, "gradientDirRight", false) == true
  local up = GradientScopedValue(conf, general, "gradientDirUp", false) == true
  local down = GradientScopedValue(conf, general, "gradientDirDown", false) == true
  if not (left or right or up or down) then
    local legacy = GradientScopedValue(conf, general, "gradientDirection", "RIGHT")
    if not GRADIENT_DIR_KEYS[legacy] then legacy = "RIGHT" end
    left, right, up, down = legacy == "LEFT", legacy == "RIGHT", legacy == "UP", legacy == "DOWN"
  end
  return {
    enabled = GradientScopedValue(conf, general, enabledKey, false) == true,
    strength = Clamp01(GradientScopedValue(conf, general, "gradientStrength", 0.45), 0.45),
    left = left,
    right = right,
    up = up,
    down = down,
  }
end

local DISPEL_TYPE_COLORS = {
  { "Magic", 0.20, 0.60, 1.00 },
  { "Curse", 0.60, 0.00, 1.00 },
  { "Disease", 0.60, 0.40, 0.00 },
  { "Poison", 0.00, 0.60, 0.00 },
  { "Bleed", 0.80, 0.10, 0.10 },
}

local function FallbackFillDispelTypeColors(dst, general, numberFn)
  for i = 1, #DISPEL_TYPE_COLORS do
    local color = DISPEL_TYPE_COLORS[i]
    local key = "type" .. color[1]
    dst[key .. "R"] = numberFn(general and general["dispelType" .. color[1] .. "R"], color[2])
    dst[key .. "G"] = numberFn(general and general["dispelType" .. color[1] .. "G"], color[3])
    dst[key .. "B"] = numberFn(general and general["dispelType" .. color[1] .. "B"], color[4])
  end
end

local function FallbackFillPredictionColors(dst, general, conf, scopedValue, numberFn)
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

-- These mirrors keep isolated compiler tests/load-order probes deterministic.
-- The live addon still uses the shared UF core helpers whenever they are loaded.
local ResolveBarGradient = UF.ResolveBarGradient or FallbackResolveBarGradient
local FillDispelTypeColors = UF.FillDispelTypeColors or FallbackFillDispelTypeColors
local FillPredictionColors = UF.FillPredictionColors or FallbackFillPredictionColors

local WHITE = "Interface\\Buttons\\WHITE8x8"
local EMPTY_EVENTS = {}

local function PVPIndicatorContextActive()
  return UF and type(UF.PVPIndicatorContextActive) == "function" and UF.PVPIndicatorContextActive() == true
end

local function Layer(value, fallback)
  value = floor((tonumber(value) or fallback or 5) + 0.5)
  if value < 0 then return 0 end
  if value > 30 then return 30 end
  return value
end

local _groupSizeCacheAt, _groupSizeCacheValue = 0, 0
--- Group-size reads are used for dynamic aura scaling. Cache briefly so one
--- refresh pass does not call into roster APIs for every compiled frame.
local function CachedGroupSize()
  local now = GetTime and GetTime() or 0
  if now - _groupSizeCacheAt < 1 then return _groupSizeCacheValue end
  _groupSizeCacheAt = now
  _groupSizeCacheValue = GetNumGroupMembers and GetNumGroupMembers() or 0
  return _groupSizeCacheValue
end

function GF.InvalidateGroupSizeCache()
  _groupSizeCacheAt = 0
end

local function DynamicAuraScale(root)
  if not (root and root.dynamicScale == true) then return 1 end
  local n = CachedGroupSize()
  if n <= 15 then return 1 end
  if n <= 25 then return 0.85 end
  return 0.70
end

local function ScaleAuraValue(value, scale, minValue)
  value = tonumber(value) or 0
  if scale ~= 1 then
    value = value * scale
  end
  if value >= 0 then
    value = floor(value + 0.5)
  else
    value = -floor((-value) + 0.5)
  end
  if minValue ~= nil and value < minValue then value = minValue end
  return value
end

local function ResolveTexture(resolver, kind)
  if type(resolver) == "function" then
    local texture = resolver(kind)
    if type(texture) == "string" and texture ~= "" then
      return texture
    end
  end
  return WHITE
end

local function ResolveHighlightRGB()
  local general = _G.MSUF_DB and _G.MSUF_DB.general
  local color = general and general.highlightColor
  if type(color) == "table" then
    return Num(color[1], 1), Num(color[2], 1), Num(color[3], 1)
  end
  local key = type(color) == "string" and color:lower() or "white"
  local colors = _G.MSUF_FONT_COLORS
  local c = type(colors) == "table" and (colors[key] or colors.white)
  if type(c) == "table" then
    return Num(c[1], 1), Num(c[2], 1), Num(c[3], 1)
  end
  return 1, 1, 1
end

local function SettingsCache()
  local getter = _G.MSUF_UFCore_GetSettingsCache
  if type(getter) == "function" then
    local cache = getter()
    if type(cache) == "table" then
      return cache
    end
  end
  return nil
end

local function GeneralDB()
  local db = _G.MSUF_DB
  return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local HEALTH_MODE_ALIASES = {
  GRADIENT = "gradient", gradient = "gradient",
  CUSTOM = "custom", custom = "custom",
  DARK = "dark", dark = "dark",
  UNIFIED = "unified", unified = "unified",
  CLASS = "class", class = "class",
}

local function NormalizeHealthMode(value)
  return value ~= "GLOBAL" and HEALTH_MODE_ALIASES[value] or nil
end

--- Resolve the effective health-color model once per compile. Runtime visual
--- code receives concrete mode/color fields instead of profile fallback logic.
local function ResolveHealthVisual(conf)
  conf = conf or {}
  local cache = SettingsCache()
  local general = GeneralDB()
  local mode = NormalizeHealthMode(conf.gfBarMode)
  if not mode then
    local globalMode = cache and cache.barMode or general and general.barMode
    if globalMode == "dark" or globalMode == "unified" then
      mode = globalMode
    else
      mode = NormalizeHealthMode(conf.healthColorMode) or "class"
    end
  end

  local out = {
    mode = mode == "custom" and "unified" or mode,
    r = Num(conf.healthCustomR, 0.2),
    g = Num(conf.healthCustomG, 0.8),
    b = Num(conf.healthCustomB, 0.2),
    backgroundMatchHealth = (cache and cache.barBgMatchHPColor == true) or (general and general.barBgMatchHPColor == true) or false,
    gradientLowR = Num(cache and cache.healthGradientLowR or general and general.healthGradientLowR, 1),
    gradientLowG = Num(cache and cache.healthGradientLowG or general and general.healthGradientLowG, 0),
    gradientLowB = Num(cache and cache.healthGradientLowB or general and general.healthGradientLowB, 0),
    gradientMidR = Num(cache and cache.healthGradientMidR or general and general.healthGradientMidR, 1),
    gradientMidG = Num(cache and cache.healthGradientMidG or general and general.healthGradientMidG, 1),
    gradientMidB = Num(cache and cache.healthGradientMidB or general and general.healthGradientMidB, 0),
    gradientHighR = Num(cache and cache.healthGradientHighR or general and general.healthGradientHighR, 0),
    gradientHighG = Num(cache and cache.healthGradientHighG or general and general.healthGradientHighG, 1),
    gradientHighB = Num(cache and cache.healthGradientHighB or general and general.healthGradientHighB, 0),
  }
  if mode == "dark" then
    local gray = Num(general and (general.darkBarGray or general.darkBgBrightness), 0.07)
    out.r = Num(conf.gfDarkR, cache and cache.darkBarR or general and general.darkBarR or gray)
    out.g = Num(conf.gfDarkG, cache and cache.darkBarG or general and general.darkBarG or gray)
    out.b = Num(conf.gfDarkB, cache and cache.darkBarB or general and general.darkBarB or gray)
  elseif mode == "unified" then
    out.r = Num(conf.gfUnifiedR, cache and cache.unifiedBarR or general and general.unifiedBarR or 0.10)
    out.g = Num(conf.gfUnifiedG, cache and cache.unifiedBarG or general and general.unifiedBarG or 0.60)
    out.b = Num(conf.gfUnifiedB, cache and cache.unifiedBarB or general and general.unifiedBarB or 0.90)
  elseif mode == "gradient" or mode == "class" then
    out.r = Num(cache and cache.unifiedBarR or general and general.unifiedBarR, out.r)
    out.g = Num(cache and cache.unifiedBarG or general and general.unifiedBarG, out.g)
    out.b = Num(cache and cache.unifiedBarB or general and general.unifiedBarB, out.b)
  end
  return out
end

local function ResolveNameTextOptions(kind, conf)
  conf = conf or {}
  local text = {}
  local general = GeneralDB()
  if conf.fontOverride == true then
    local mode = conf.nameColorMode or "DEFAULT"
    if mode == "CLASS" then
      text.nameClassColor = true
    elseif mode == "CUSTOM" then
      text.nameColor = {
        r = Num(conf.nameColorR, 1),
        g = Num(conf.nameColorG, 1),
        b = Num(conf.nameColorB, 1),
        a = 1,
      }
    end
  else
    text.nameClassColor = general and general.nameClassColor == true
    text.nameNpcColor = general and general.npcNameRed == true
    text.nameNpcClassColor = general and general.nameNpcClassColor == true
  end
  text.healthColorByHealth = general and general.colorHealthTextByHealth == true
  if conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then
    text.healthColorByHealth = conf.colorHealthTextByHealth == true
  end

  local maxChars, noEllipsis, side
  if GF.ResolveNameTruncation then
    maxChars, noEllipsis, side = GF.ResolveNameTruncation(kind)
  else
    maxChars, noEllipsis, side = Num(conf.nameMaxChars, 0), conf.nameNoEllipsis == true, conf.nameClipSide or "RIGHT"
  end
  maxChars = floor((tonumber(maxChars) or 0) + 0.5)
  if maxChars < 0 then maxChars = 0 end
  text.nameShorten = maxChars > 0
  text.nameShortenMax = maxChars
  text.nameShortenSide = side == "LEFT" and "LEFT" or "RIGHT"
  text.nameShortenDots = noEllipsis ~= true
  text.hideNameOnDeadOffline = conf.hideNameOnDeadOffline == true
  return text
end

local function TextSlots(conf)
  if GF.ResolveHealthTextSlots then
    local left, center, right = GF.ResolveHealthTextSlots(conf)
    return left or "NONE", center or "NONE", right or "NONE"
  end
  return conf.textLeft or "NONE", conf.textCenter or "NONE", conf.textRight or "NONE"
end

local function IsPowerTextEnabled(kind, conf)
  if GF.IsPowerTextEnabled then
    return GF.IsPowerTextEnabled(kind, conf)
  end
  return conf.showPowerText == true or conf.showPower == true
end

local function GetRole(unit)
  if GF.GetUnitGroupRole then
    return GF.GetUnitGroupRole(unit)
  end
  local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or nil
  if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
    return role
  end
  return "DAMAGER"
end

local function EffectivePowerHeight(kind, unit, role, conf)
  if conf.powerBarEnabled == false then
    return 0
  end
  if GF.GetEffectivePowerHeight then
    return GF.GetEffectivePowerHeight(kind, unit, role, conf)
  end
  return Num(conf.powerHeight, 4)
end

local function AddEvent(list, event)
  if not list then
    list = {}
  end
  list[#list + 1] = event
  return list
end

local function CompileStatusRuntimeEvents(leader, assist, readyCheck, summon, phase, raidMarker, raidGroup, statusTextConnection, statusTextFlags, statusTextPlayerFlags, incomingRes, pvp)
  local events, unitlessEvents
  if phase then
    events = AddEvent(events, "UNIT_PHASE")
    events = AddEvent(events, "UNIT_OTHER_PARTY_CHANGED")
  end
  if statusTextConnection then
    events = AddEvent(events, "UNIT_CONNECTION")
  end
  if statusTextFlags then
    events = AddEvent(events, "UNIT_FLAGS")
  end
  if statusTextPlayerFlags then
    unitlessEvents = AddEvent(unitlessEvents, "PLAYER_FLAGS_CHANGED")
  end
  if incomingRes then
    events = AddEvent(events, "INCOMING_RESURRECT_CHANGED")
  end
  if pvp then
    events = AddEvent(events, "UNIT_FACTION")
  end
  if raidMarker then
    unitlessEvents = AddEvent(unitlessEvents, "RAID_TARGET_UPDATE")
  end
  if leader or assist then
    unitlessEvents = AddEvent(unitlessEvents, "PARTY_LEADER_CHANGED")
  end
  if readyCheck then
    unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK")
    unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK_CONFIRM")
    unitlessEvents = AddEvent(unitlessEvents, "READY_CHECK_FINISHED")
  end
  if summon then
    unitlessEvents = AddEvent(unitlessEvents, "INCOMING_SUMMON_CHANGED")
  end
  return events or EMPTY_EVENTS, unitlessEvents or EMPTY_EVENTS
end

local function StatusRegion(conf, enabled, sizeKey, sizeFallback, anchorKey, anchorFallback, xKey, xFallback, yKey, yFallback, layerKey, layerFallback)
  return {
    enabled = enabled,
    size = Num(conf[sizeKey], sizeFallback),
    anchor = conf[anchorKey] or anchorFallback,
    x = Num(conf[xKey], xFallback),
    y = Num(conf[yKey], yFallback),
    layer = Layer(conf[layerKey], layerFallback),
  }
end

local GROUP_STATUS_REGIONS = {
  role = { "roleIconSize", 12, "roleIconAnchor", "TOPLEFT", "roleIconX", 0, "roleIconY", 0, "roleIconLayer", 1 },
  raidMarker = { "raidMarkerSize", 14, "raidMarkerAnchor", "CENTER", "raidMarkerX", 0, "raidMarkerY", 0, "raidMarkerLayer", 3 },
  leader = { "leaderIconSize", 12, "leaderIconAnchor", "TOPRIGHT", "leaderIconX", 0, "leaderIconY", 0, "leaderIconLayer", 2 },
  assist = { "assistIconSize", 12, "assistIconAnchor", "TOPRIGHT", "assistIconX", 14, "assistIconY", 0, "assistIconLayer", 2 },
  readyCheck = { "readyCheckSize", 16, "readyCheckAnchor", "CENTER", "readyCheckX", 0, "readyCheckY", 0, "readyCheckLayer", 4 },
  summon = { "summonIconSize", 16, "summonAnchor", "CENTER", "summonX", 0, "summonY", 0, "summonLayer", 4 },
  incomingRes = { "resurrectIconSize", 16, "resurrectAnchor", "CENTER", "resurrectX", 0, "resurrectY", 0, "resurrectLayer", 4 },
  pvp = { "pvpIconSize", 14, "pvpIconAnchor", "TOPLEFT", "pvpIconX", 14, "pvpIconY", 0, "pvpIconLayer", 3 },
  phase = { "phaseIconSize", 14, "phaseAnchor", "TOPLEFT", "phaseX", 0, "phaseY", 0, "phaseLayer", 3 },
  statusText = { "statusTextSize", 14, "statusTextAnchor", "CENTER", "statusOffsetX", 0, "statusOffsetY", 0, "statusTextLayer", 7 },
  statusGhost = { "statusGhostTextSize", 14, "statusGhostTextAnchor", "CENTER", "statusGhostOffsetX", 0, "statusGhostOffsetY", 0, "statusGhostTextLayer", 7 },
  statusAFK = { "statusAFKTextSize", 14, "statusAFKTextAnchor", "CENTER", "statusAFKOffsetX", 0, "statusAFKOffsetY", 0, "statusAFKTextLayer", 7 },
  raidGroup = { "groupNumberSize", 10, "groupNumberAnchor", "BOTTOMRIGHT", "groupNumberX", -2, "groupNumberY", 2, "statusTextLayer", 7 },
}

local function StatusRegionDef(conf, enabled, key)
  local d = GROUP_STATUS_REGIONS[key]
  return StatusRegion(conf, enabled, d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10])
end

local function CompileStatus(kind, conf)
  local roleEnabled = conf.roleIcon == true
  local raidMarkerEnabled = conf.raidMarker == true
  local leaderEnabled = conf.leaderIcon == true
  local assistEnabled = conf.assistIcon == true
  local readyCheckEnabled = conf.readyCheckIcon == true
  local summonEnabled = conf.summonIcon == true
  local incomingResEnabled = conf.resurrectIcon == true
  local pvpEnabled = conf.pvpIcon == true and PVPIndicatorContextActive()
  local phaseEnabled = conf.phaseIcon == true
  local statusDeadGhostTextEnabled = conf.statusText == true or conf.statusGhostText == true
  local statusConnectionTextEnabled = conf.statusText == true
  local statusPlayerFlagTextEnabled = conf.statusAFKText == true
  local statusFlagTextEnabled = statusDeadGhostTextEnabled or statusPlayerFlagTextEnabled
  local statusTextEnabled = statusConnectionTextEnabled or statusFlagTextEnabled
  local raidGroupEnabled = conf.showGroupNumber == true
  local runtimeEvents, runtimeUnitlessEvents = CompileStatusRuntimeEvents(
    leaderEnabled, assistEnabled, readyCheckEnabled, summonEnabled, phaseEnabled,
    raidMarkerEnabled, raidGroupEnabled, statusConnectionTextEnabled, statusFlagTextEnabled, statusPlayerFlagTextEnabled, incomingResEnabled, pvpEnabled
  )
  local runtimeEnabled = roleEnabled or leaderEnabled or assistEnabled
    or readyCheckEnabled or summonEnabled or phaseEnabled
    or raidMarkerEnabled or raidGroupEnabled or statusTextEnabled or incomingResEnabled or pvpEnabled

  local role = StatusRegionDef(conf, roleEnabled, "role")
  role.style = conf.roleIconStyle
  role.showTank = conf.roleIconShowTank ~= false
  role.showHealer = conf.roleIconShowHealer ~= false
  role.showDPS = conf.roleIconShowDPS ~= false
  local leader = StatusRegionDef(conf, leaderEnabled, "leader")
  leader.style = conf.leaderIconStyle
  local assist = StatusRegionDef(conf, assistEnabled, "assist")
  assist.style = conf.assistIconStyle
  local statusText = StatusRegionDef(conf, statusTextEnabled, "statusText")
  statusText.showDead = conf.statusText == true
  statusText.showGhost = conf.statusGhostText == true
  statusText.showAFK = conf.statusAFKText == true
  statusText.showDND = conf.statusAFKText == true
  statusText.dead = StatusRegionDef(conf, conf.statusText == true, "statusText")
  statusText.ghost = StatusRegionDef(conf, conf.statusGhostText == true, "statusGhost")
  statusText.afk = StatusRegionDef(conf, conf.statusAFKText == true, "statusAFK")
  local raidGroup = StatusRegionDef(conf, raidGroupEnabled, "raidGroup")
  raidGroup.style = conf.groupNumberStyle or "PAREN"

  return {
    enabled = roleEnabled or raidMarkerEnabled or leaderEnabled or assistEnabled
      or readyCheckEnabled or summonEnabled or incomingResEnabled
      or pvpEnabled or phaseEnabled or statusTextEnabled or raidGroupEnabled,
    group = true,
    groupRuntimeEnabled = runtimeEnabled,
    groupRuntimeEvents = runtimeEvents,
    groupRuntimeUnitlessEvents = runtimeUnitlessEvents,
    runtimeLeaderPair = leaderEnabled or assistEnabled,
    runtimeReadyCheck = readyCheckEnabled,
    runtimeSummon = summonEnabled,
    runtimePhase = phaseEnabled,
    runtimeRaidMarker = raidMarkerEnabled,
    runtimeRaidGroup = raidGroupEnabled,
    runtimeStatusText = statusTextEnabled,
    runtimeIncomingRes = incomingResEnabled,
    runtimePVP = pvpEnabled,
    kind = kind,
    alpha = 1,
    useMidnight = conf.useMidnightIcons == true,
    role = role,
    raidMarker = StatusRegionDef(conf, raidMarkerEnabled, "raidMarker"),
    leader = leader,
    assist = assist,
    readyCheck = StatusRegionDef(conf, readyCheckEnabled, "readyCheck"),
    summon = StatusRegionDef(conf, summonEnabled, "summon"),
    incomingRes = StatusRegionDef(conf, incomingResEnabled, "incomingRes"),
    pvp = StatusRegionDef(conf, pvpEnabled, "pvp"),
    phase = StatusRegionDef(conf, phaseEnabled, "phase"),
    statusText = statusText,
    raidGroup = raidGroup,
  }
end

local function CompilePrediction(kind, conf, texture)
  local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
  local absorbMode = Num(ScopedValue(conf, general, "absorbTextMode", nil), nil)
  local absorb
  if absorbMode then
    absorb = absorbMode == 2 or absorbMode == 3
  else
    local absorbEnabled = ScopedValue(conf, general, "enableAbsorbBar", nil)
    if absorbEnabled == nil and conf and conf.hlOverride == true and conf.absorbEnabled ~= nil then
      absorbEnabled = conf.absorbEnabled
    end
    if absorbEnabled == nil then absorbEnabled = true end
    absorb = absorbEnabled ~= false
  end
  local heal = GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf) or conf.healPredEnabled == true
  local healAbsorb = absorb == true and ScopedValue(conf, general, "healAbsorbEnabled", true) ~= false
  local test = AbsorbTextureTestEnabledForScope(kind)
  if test == true then
    heal = true
    absorb = true
    healAbsorb = true
  end
  local out = {
    enabled = heal == true or absorb == true or healAbsorb == true,
    heal = heal == true,
    absorb = absorb == true,
    healAbsorb = healAbsorb == true,
    test = test == true,
    healAnchorMode = Num(ScopedValue(conf, general, "healPredAnchorMode", 3), 3),
    absorbAnchorMode = Num(ScopedValue(conf, general, "absorbAnchorMode", 2), 2),
    texture = texture,
    absorbTexture = ScopedValue(conf, general, "absorbBarTexture", nil),
    healAbsorbTexture = ScopedValue(conf, general, "healAbsorbBarTexture", nil),
  }
  FillPredictionColors(out, general, conf, ScopedValue, Num)
  return out
end

local function CompileDispelVisual(kind, conf)
  local general = GeneralDB() or {}
  local mode = general.hlDispelColorMode or "SINGLE"
  local out = {
    colorMode = mode == "TYPE" and "TYPE" or "SINGLE",
    r = Num(general.hlDispelColorR or general.dispelBorderColorR, 0.25),
    g = Num(general.hlDispelColorG or general.dispelBorderColorG, 0.75),
    b = Num(general.hlDispelColorB or general.dispelBorderColorB, 1),
    a = 1,
  }
  FillDispelTypeColors(out, general, Num)
  return out
end

local function CompileGroupVisuals(kind, conf)
  local general = _G.MSUF_DB and _G.MSUF_DB.general
  local hoverR, hoverG, hoverB = ResolveHighlightRGB()
  local hoverSize = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlHoverSize") or conf.hlHoverSize
  local frameHighlightEnabled = not (general and general.highlightEnabled == false)
  if general and general.highlightEnabled == nil and general.enableHighlightOnHover ~= nil then
    frameHighlightEnabled = general.enableHighlightOnHover == true
  end
  return {
    kind = kind,
    rangeFadeEnabled = conf.rangeFadeEnabled == true,
    rangeFadeAlpha = Clamp01(conf.rangeFadeAlpha, 0.4),
    rangeFadeLayerMode = NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode),
    offlineAlpha = Clamp01(conf.offlineAlpha, 0.5),
    hideOfflineEnabled = conf.hideOfflineEnabled == true,
    hideOfflineInCombat = conf.hideOfflineInCombat == true,
    hideOfflineDelay = Num(conf.hideOfflineDelay, 0),
    healthFadeEnabled = conf.healthFadeEnabled == true,
    healthFadeThreshold = Num(conf.healthFadeThreshold, 95),
    healthFadeAlpha = Clamp01(conf.healthFadeAlpha, 0.45),
    deadBgEnabled = conf.deadBgEnabled == true,
    deadBgOffline = conf.deadBgOffline ~= false,
    deadBgR = Num(conf.deadBgR, 0.60),
    deadBgG = Num(conf.deadBgG, 0.05),
    deadBgB = Num(conf.deadBgB, 0.05),
    deadBgA = Clamp01(conf.deadBgA, 0.90),
    hpBarAlpha = Clamp01(conf.hpBarAlpha, 1),
    hpBgAlpha = Clamp01(conf.hpBgAlpha, 0.85),
    hoverHighlightEnabled = frameHighlightEnabled,
    hoverHighlightSize = Num(hoverSize, 1),
    hoverHighlightR = hoverR,
    hoverHighlightG = hoverG,
    hoverHighlightB = hoverB,
    targetIndicator = frameHighlightEnabled and conf.targetIndicator ~= false,
    targetR = Num(conf.targetR, 1),
    targetG = Num(conf.targetG, 1),
    targetB = Num(conf.targetB, 1),
    focusIndicator = frameHighlightEnabled and conf.hlFocusEnabled ~= false,
    focusR = Num(conf.hlFocusColorR, 0.5),
    focusG = Num(conf.hlFocusColorG, 0.5),
    focusB = Num(conf.hlFocusColorB, 1),
    focusSize = Num(conf.hlFocusSize, 2),
    focusOffset = Num(conf.hlFocusOffset, 0),
    dispelOverlayEnabled = (not DISPEL_OVERLAY_121_PTR_DISABLED) and conf.dispelOverlayEnabled == true,
    dispelOverlayStyle = NormalizeDispelOverlayStyle(conf.dispelOverlayStyle),
    dispelOverlayAlpha = Clamp01(conf.dispelOverlayAlpha, 0.35),
    dispelOverlayTrigger = NormalizeDispelOverlayTrigger(conf.dispelOverlayTrigger),
    dispelOverlayOnHealth = conf.dispelOverlayOnHealth ~= false,
    debuffStripeEnabled = conf.debuffStripeEnabled == true,
    debuffStripeEdge = conf.debuffStripeEdge or "BOTTOM",
    debuffStripeHeight = Num(conf.debuffStripeHeight, 3),
    debuffStripeAlpha = Clamp01(conf.debuffStripeAlpha, 0.6),
    debuffStripeColorR = Num(conf.debuffStripeColorR, 0.8),
    debuffStripeColorG = Num(conf.debuffStripeColorG, 0.2),
    debuffStripeColorB = Num(conf.debuffStripeColorB, 0.2),
  }
end

local function SplitAuraGrowth(value, fallback)
  value = value or fallback or "RIGHTDOWN"
  if value == "LEFTUP" then
    return "LEFT", "UP"
  elseif value == "LEFTDOWN" then
    return "LEFT", "DOWN"
  elseif value == "RIGHTUP" then
    return "RIGHT", "UP"
  elseif value == "UP" then
    return "UP", "UP"
  elseif value == "DOWN" then
    return "DOWN", "DOWN"
  end
  return "RIGHT", "DOWN"
end

local function IsBlizzardAuraTypeEnabled(confOrRoot, nativeKey)
  local root = type(confOrRoot) == "table" and (confOrRoot.auras or confOrRoot) or nil
  if not root or root.enabled == false then return false end
  local types = type(root.blizzardTypes) == "table" and root.blizzardTypes or nil
  local value = types and types[nativeKey]
  if value ~= nil then return value == true end
  return true
end

function GF.GetBlizzardAuraTypeFlags(conf)
  return IsBlizzardAuraTypeEnabled(conf, "buffs"),
    IsBlizzardAuraTypeEnabled(conf, "debuffs"),
    IsBlizzardAuraTypeEnabled(conf, "dispels"),
    IsBlizzardAuraTypeEnabled(conf, "externals"),
    IsBlizzardAuraTypeEnabled(conf, "privateAuras")
end

local NATIVE_AURA_BLACKLIST_HASHES_ENABLED = false

local function AuraBlacklistHash(kind, groupKey, group)
  -- 12.1 native AuraContainers cannot consume addon SpellID/category
  -- blacklist hashes. Keep saved legacy data out of compiled group specs.
  if not NATIVE_AURA_BLACKLIST_HASHES_ENABLED then return nil end

  local filter = GF.AuraFilter or _G.MSUF_GF_AuraFilter
  if filter and filter.GetBlacklistHashForGroup then
    return filter.GetBlacklistHashForGroup(kind, groupKey)
  end
  if filter and filter.BuildBlacklistHash and type(group) == "table" then
    return filter.BuildBlacklistHash(group)
  end
  return nil
end

local function AuraFilterString(groupKey, group)
  local filter = GF.AuraFilter or _G.MSUF_GF_AuraFilter
  local token = group and group.filterToken
  if groupKey == "buff" then
    return filter and filter.ResolveBuffFilter and filter.ResolveBuffFilter(token) or "HELPFUL"
  elseif groupKey == "externals" then
    return filter and filter.EXTERNALS_TOKEN or "HELPFUL|BIG_DEFENSIVE"
  end
  return filter and filter.ResolveDebuffFilter and filter.ResolveDebuffFilter(token) or "HARMFUL"
end

local function AuraTextAnchor(value, fallback)
  if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
    or value == "LEFT" or value == "CENTER" or value == "RIGHT"
    or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
    return value
  end
  return fallback or "CENTER"
end

local function AuraDurationBarPosition(value)
  value = tostring(value or "BOTTOM"):upper()
  if value == "TOP" then return "TOP" end
  return "BOTTOM"
end

local function AuraDurationBarDirection(value)
  value = tostring(value or "REMAINING"):upper()
  if value == "ELAPSED" or value == "ELAPSED_TIME" then return "ELAPSED" end
  return "REMAINING"
end

local function AuraDurationBarDisplay(value)
  value = tostring(value or "BAR_ONLY"):upper()
  if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" or value == "OVERLAY" then return "OVERLAY" end
  return "BAR_ONLY"
end

local function LaneAlpha(group)
  return Clamp01(Num(group and group.behindBarAlpha, 85) / 100, 0.85)
end

local AURA_LANE_DEFAULTS = {
  buff = { "maxBuffs", 4, "BOTTOMRIGHT", 5, 8, 10 },
  debuff = { "maxDebuffs", 3, "TOPLEFT", 6, 8, 10 },
  external = { "maxExternals", 3, "CENTER", 7, 10, 10, false, false },
}

local function ApplyAuraLane(out, prefix, groupKey, group, defaults, maxCount, iconSize, growthX, growthY, scale, kind)
  out[defaults[1]] = Num(group.max, maxCount)
  out[prefix .. "IconSize"] = scale(group.size, iconSize, 1)
  out[prefix .. "Spacing"] = scale(group.spacing, 1, 0)
  out[prefix .. "PerRow"] = Num(group.perRow, defaults[2])
  out[prefix .. "GrowthX"] = growthX
  out[prefix .. "GrowthY"] = growthY
  out[prefix .. "Anchor"] = group.anchor or defaults[3]
  out[prefix .. "OffsetX"] = scale(group.x, 0)
  out[prefix .. "OffsetY"] = scale(group.y, 0)
  out[prefix .. "Layer"] = Layer(group.layer, defaults[4])
  out[prefix .. "Alpha"] = group.behindBar == true and LaneAlpha(group) or 1
  out[prefix .. "Filter"] = AuraFilterString(groupKey, group)
  out[prefix .. "ShowCooldownSwipe"] = group.showCooldownSwipe ~= false
  out[prefix .. "CooldownSwipeReverse"] = group.cooldownSwipeReverse == true
  out[prefix .. "ShowDurationBar"] = group.showDurationBar == true
  out[prefix .. "DurationBarHeight"] = scale(group.durationBarHeight, 2, 1)
  out[prefix .. "DurationBarDisplay"] = AuraDurationBarDisplay(group.durationBarDisplay)
  out[prefix .. "DurationBarPosition"] = AuraDurationBarPosition(group.durationBarPosition)
  out[prefix .. "DurationBarDirection"] = AuraDurationBarDirection(group.durationBarDirection)
  out[prefix .. "ShowCooldown"] = group.showCooldown ~= false
  out[prefix .. "ShowStacks"] = defaults[7] ~= false and group.showStacks ~= false or group.showStacks == true
  out[prefix .. "CooldownSize"] = scale(group.cooldownSize, defaults[5], 6)
  out[prefix .. "CooldownAnchor"] = AuraTextAnchor(group.cooldownAnchor, "CENTER")
  out[prefix .. "CooldownX"] = scale(group.cooldownX, 0)
  out[prefix .. "CooldownY"] = scale(group.cooldownY, 0)
  out[prefix .. "StackSize"] = scale(group.stackSize, defaults[6], 6)
  out[prefix .. "StackAnchor"] = AuraTextAnchor(group.stackAnchor, "BOTTOMRIGHT")
  out[prefix .. "StackX"] = scale(group.stackX, 0)
  out[prefix .. "StackY"] = scale(group.stackY, 0)
  if defaults[8] ~= false then
    out[prefix .. "BlacklistHash"] = AuraBlacklistHash(kind, groupKey, group)
  end
end

local function CompileCoreAuras(kind, conf)
  local root = type(conf.auras) == "table" and conf.auras or nil
  local buff = root and type(root.buff) == "table" and root.buff or {}
  local debuff = root and type(root.debuff) == "table" and root.debuff or {}
  local externals = root and type(root.externals) == "table" and root.externals or {}
  local private = type(conf.privateAuras) == "table" and conf.privateAuras or {}
  local rootEnabled = root == nil or root.enabled ~= false
  local showBuffs = rootEnabled and buff.enabled ~= false
  local showDebuffs = rootEnabled and debuff.enabled ~= false
  local showExternals = rootEnabled and externals.enabled ~= false
  local privateEnabled = private.enabled
  if privateEnabled == nil then privateEnabled = conf.privateAurasEnabled ~= false end
  local showPrivate = rootEnabled and privateEnabled ~= false
  local function NormalizeDispelBorderMode(value, legacyEnabled)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
      or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
      return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return legacyEnabled == true and "SYMBOL" or "OFF" end
    return legacyEnabled == true and "SYMBOL" or "OFF"
  end
  local debuffDispelBorderMode = NormalizeDispelBorderMode(debuff.dispelBorderMode, debuff.showDispelBorder == true)
  local buffGrowthX, buffGrowthY = SplitAuraGrowth(buff.growth, "LEFTUP")
  local debuffGrowthX, debuffGrowthY = SplitAuraGrowth(debuff.growth, "RIGHTDOWN")
  local externalGrowthX, externalGrowthY = SplitAuraGrowth(externals.growth, "RIGHTDOWN")
  local auraScale = DynamicAuraScale(root)
  local defaultBuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 22
  local defaultDebuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 20
  local defaultExternalSize = (kind == "raid" or kind == "mythicraid") and 22 or 28
  local function S(value, fallback, minValue)
    return ScaleAuraValue(Num(value, fallback), auraScale, minValue)
  end
  local out = {
    enabled = showBuffs == true or showDebuffs == true or showExternals == true
      or conf.dispelEnabled == true
      or conf.dispelOverlayEnabled == true,
    group = true,
    kind = kind,
    renderer = "NATIVE_12_1",
    blizzard = {
      buffs = IsBlizzardAuraTypeEnabled(root or {}, "buffs"),
      debuffs = IsBlizzardAuraTypeEnabled(root or {}, "debuffs"),
      dispels = IsBlizzardAuraTypeEnabled(root or {}, "dispels"),
      externals = IsBlizzardAuraTypeEnabled(root or {}, "externals"),
      privateAuras = IsBlizzardAuraTypeEnabled(root or {}, "privateAuras"),
      iconSize = Num(root and root.blizzardIconSize, 20),
      organizationType = root and root.blizzardOrganizationType or "default",
      strata = root and root.blizzardContainerStrata or "AUTO",
      frameLevelOffset = Layer(root and root.blizzardContainerFrameLevel, 1),
      showCooldownText = not (root and root.blizzardShowCooldownText == false),
      dispelBorder = root and root.blizzardDispelBorder == true,
      privateLayerFix = root == nil or root.blizzardPrivateLayerFix ~= false,
    },
    showBuffs = showBuffs,
    showDebuffs = showDebuffs,
    showExternals = showExternals,
    showTooltip = root == nil or root.showTooltip ~= false,
    clickThrough = false,
    showSwipe = true,
    showStacks = true,
    stackAnchor = "BOTTOMRIGHT",
    sortByDuration = root and root.sortByDuration == true,
    preferPlayer = root and root.preferPlayer == true,
    dynamicScale = root and root.dynamicScale == true,
    dynamicScaleValue = auraScale,
    cooldownSwipeDarkenOnLoss = conf.cooldownSwipeDarkenOnLoss == true,
    iconSize = S(conf.auraIconSize, 20, 1),
    spacing = 1,
    perRow = 4,
    growth = "RIGHT",
    rowWrap = "DOWN",
    debuffDispelBorderMode = debuffDispelBorderMode,
    debuffShowDispelBorder = debuffDispelBorderMode ~= "OFF",
    debuffShowDispelSymbol = debuffDispelBorderMode == "SYMBOL",
    showStealableBuffs = false,
    private = {
      enabled = showPrivate,
      num = Num(private.max, Num(conf.privateAuraMax, 4)),
      size = S(private.size, Num(conf.privateAuraSize, 20), 1),
      spacing = S(private.spacing, 1, 0),
      anchor = private.anchor or conf.privateAuraAnchor or "TOPRIGHT",
      growth = private.growth or "RIGHT",
      x = S(private.x, Num(conf.privateAuraX, 0)),
      y = S(private.y, Num(conf.privateAuraY, 0)),
      showCountdown = private.showCountdown ~= false and conf.privateAuraCountdown ~= false,
      showNumbers = private.showNumbers == true,
    },
  }
  ApplyAuraLane(out, "buff", "buff", buff, AURA_LANE_DEFAULTS.buff, Num(conf.auraMaxIcons, 4), defaultBuffSize, buffGrowthX, buffGrowthY, S, kind)
  ApplyAuraLane(out, "debuff", "debuff", debuff, AURA_LANE_DEFAULTS.debuff, Num(conf.auraMaxIcons, 4), defaultDebuffSize, debuffGrowthX, debuffGrowthY, S, kind)
  ApplyAuraLane(out, "external", "externals", externals, AURA_LANE_DEFAULTS.external, 2, defaultExternalSize, externalGrowthX, externalGrowthY, S, kind)
  return out
end

local function CompileAlpha(conf)
  local hpAlpha = Clamp01(conf and conf.hpBarAlpha, 1)
  return {
    active = hpAlpha < 1,
    hpAlpha = hpAlpha,
    excludeTextPortrait = conf and conf.alphaExcludeTextPortrait == true,
  }
end

local function CompileBarBackground(conf)
  return {
    r = Num(conf.bgR, 0.1),
    g = Num(conf.bgG, 0.1),
    b = Num(conf.bgB, 0.1),
    a = Num(conf.hpBgAlpha, 0.85),
  }
end

local compiledSpecCache = GF._compiledSpec or {}
GF._compiledSpec = compiledSpecCache
GF._compiledSpecSerial = GF._compiledSpecSerial or 1
local compiledSpecKey = GF._compiledSpecKey or {}
GF._compiledSpecKey = compiledSpecKey
local compiledSpecSerialByKind = GF._compiledSpecSerialByKind or {}
GF._compiledSpecSerialByKind = compiledSpecSerialByKind
local compiledSpecSettingsGenByKind = GF._compiledSpecSettingsGenByKind or {}
GF._compiledSpecSettingsGenByKind = compiledSpecSettingsGenByKind
local compiledSpecSettingsGenAll = GF._compiledSpecSettingsGenAll or 1
GF._compiledSpecSettingsGenAll = compiledSpecSettingsGenAll

local function CompileSpecUncached(kind, frame, unit, conf)
  kind = kind or "party"
  if not conf then
    if GF.EnsureDB then
      GF.EnsureDB()
    end
    conf = GF.GetConf and GF.GetConf(kind) or {}
  end
  unit = unit or (frame and frame.unit)

  local w, h = 80, 32
  if GF.GetScaledFrameMetrics then
    w, h = GF.GetScaledFrameMetrics(kind)
  else
    w, h = Num(conf.width, w), Num(conf.height, h)
  end

  local role = GetRole(unit)
  local powerHeight = EffectivePowerHeight(kind, unit, role, conf)
  local texture = ResolveTexture(GF.ResolveBarTexture, kind)
  local bgTexture = ResolveTexture(GF.ResolveBarBgTexture, kind)
  local font = GF.ResolveFontPath and GF.ResolveFontPath(kind) or "Fonts\\FRIZQT__.TTF"
  local fontFlags = GF.ResolveFontFlags and GF.ResolveFontFlags(kind) or "OUTLINE"
  local tr, tg, tb = 1, 1, 1
  if GF.ResolveFontColor then
    tr, tg, tb = GF.ResolveFontColor(kind)
  end
  local textAlpha = GF.ResolveFontTextAlpha and GF.ResolveFontTextAlpha(kind) or 1
  local baselineOffset = GF.ResolveFontBaselineOffset and GF.ResolveFontBaselineOffset(kind) or 0
  local fontShadow, fontShadowAlpha, fontShadowX, fontShadowY = true, 1, 1, -1
  if GF.ResolveFontShadow then
    fontShadow, fontShadowAlpha, fontShadowX, fontShadowY = GF.ResolveFontShadow(kind)
  end

  local healthLeft, healthCenter, healthRight = TextSlots(conf)
  local healthVisual = ResolveHealthVisual(conf)
  local nameTextOptions = ResolveNameTextOptions(kind, conf)
  if type(nameTextOptions.nameColor) == "table" then
    nameTextOptions.nameColor.a = textAlpha
  end
  local hpX, hpY = Num(conf.hpOffsetX, 0), Num(conf.hpOffsetY, 0) + baselineOffset
  local powerX, powerY = Num(conf.powerOffsetX, 0), Num(conf.powerOffsetY, 0) + baselineOffset
  local status = CompileStatus(kind, conf)
  local group = CompileGroupVisuals(kind, conf)
  local alpha = CompileAlpha(conf)
  local dispelBorderEnabled = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlDispelEnabled")
  if dispelBorderEnabled == nil then
    dispelBorderEnabled = conf.dispelEnabled == true
  end
  local general = GeneralDB() or {}
  local aggroBorderMode = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlAggroEnabled")
  if aggroBorderMode == nil and GF.GetHighlightVal then
    aggroBorderMode = GF.GetHighlightVal(kind, "aggroOutlineMode")
  end
  if aggroBorderMode == nil then
    aggroBorderMode = ScopedValue(conf, general, "aggroOutlineMode", nil)
  end
  local aggroBorderEnabled
  if aggroBorderMode == nil then
    aggroBorderEnabled = conf.aggroEnabled == true
  else
    aggroBorderEnabled = tonumber(aggroBorderMode) == 1 or aggroBorderMode == true
  end
  local highlightThickness = GF.GetHighlightVal and GF.GetHighlightVal(kind, "highlightBorderThickness")
  if highlightThickness == nil and GF.GetHighlightVal then
    highlightThickness = GF.GetHighlightVal(kind, "hlAggroSize")
  end
  if highlightThickness == nil then
    highlightThickness = ScopedValue(conf, general, "highlightBorderThickness", nil)
      or ScopedValue(conf, general, "hlAggroSize", nil)
  end
  local dispelBorderTrigger = ScopedValue(conf, general, "dispelBorderTrigger", "DISPEL_TYPE")
  local prioEnabled, prioOrder = CompileBorderPriority(conf, general)
  local nameFontSize = Num(conf.nameFontSize, 12)
  local borderThickness = GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind) or Num(conf.borderSize, 1)

  return {
    _msufGFCompileSerial = GF._compiledSpecSerial or 1,
    scope = "group",
    key = "gf_" .. kind,
    unit = unit,
    groupKind = kind,
    width = w,
    height = h,
    texture = texture,
    backgroundTexture = bgTexture,
    backgroundAlpha = Num(conf.hpBgAlpha, 0.85),
    font = font,
    fontFlags = fontFlags,
    fontSize = nameFontSize,
    nameFontSize = nameFontSize,
    healthFontSize = Num(conf.hpFontSize, 10),
    powerFontSize = Num(conf.powerFontSize, 9),
    fontShadow = fontShadow == true,
    fontShadowAlpha = fontShadowAlpha,
    fontShadowX = fontShadowX,
    fontShadowY = fontShadowY,
    textColor = { r = tr or 1, g = tg or 1, b = tb or 1, a = textAlpha },
    showName = conf.showName ~= false,
    showHealthText = conf.showHPText ~= false,
    showPowerText = IsPowerTextEnabled(kind, conf),
    health = {
      mode = healthVisual.mode,
      r = healthVisual.r,
      g = healthVisual.g,
      b = healthVisual.b,
      gradientLowR = healthVisual.gradientLowR,
      gradientLowG = healthVisual.gradientLowG,
      gradientLowB = healthVisual.gradientLowB,
      gradientMidR = healthVisual.gradientMidR,
      gradientMidG = healthVisual.gradientMidG,
      gradientMidB = healthVisual.gradientMidB,
      gradientHighR = healthVisual.gradientHighR,
      gradientHighG = healthVisual.gradientHighG,
      gradientHighB = healthVisual.gradientHighB,
      texture = texture,
      backgroundTexture = bgTexture,
      background = CompileBarBackground(conf),
      backgroundMatchHealth = healthVisual.backgroundMatchHealth == true,
      barGradient = ResolveBarGradient(conf, general, "enableGradient"),
      reverse = conf.reverseFill == true,
      smooth = conf.smoothFill ~= false,
    },
    power = {
      enabled = powerHeight > 0,
      height = powerHeight,
      texture = texture,
      backgroundTexture = bgTexture,
      background = CompileBarBackground(conf),
      backgroundMatchHealth = false,
      embed = true,
      detached = false,
      mode = conf.powerColorMode or "type",
      barGradient = ResolveBarGradient(conf, general, "enablePowerGradient"),
      smooth = conf.powerSmoothFill == true,
    },
    text = {
      anchorToBars = true,
      nameClassColor = nameTextOptions.nameClassColor == true,
      nameNpcColor = nameTextOptions.nameNpcColor == true,
      nameNpcClassColor = nameTextOptions.nameNpcClassColor == true,
      nameColor = nameTextOptions.nameColor,
      nameAnchor = conf.nameAnchor or "LEFT",
      nameX = Num(conf.nameOffsetX, 0),
      nameY = Num(conf.nameOffsetY, 0) + baselineOffset,
      nameLayer = Layer(conf.nameTextLayer, 5),
      nameShorten = nameTextOptions.nameShorten == true,
      nameShortenMax = nameTextOptions.nameShortenMax,
      nameShortenSide = nameTextOptions.nameShortenSide,
      nameShortenDots = nameTextOptions.nameShortenDots,
      hideNameOnDeadOffline = nameTextOptions.hideNameOnDeadOffline == true,
      healthColorByHealth = nameTextOptions.healthColorByHealth == true,
      healthLeft = healthLeft,
      healthCenter = healthCenter,
      healthRight = healthRight,
      healthDelimiter = conf.textDelimiter or " / ",
      healthPercentDecimals = (conf.healthTextDecimals == true or conf.hpTextDecimals == true) and 1 or 0,
      healthReverse = conf.hpTextReverse == true,
      healthLayer = Layer(conf.textLayer, 5),
      healthX = hpX,
      healthY = hpY,
      healthLeftX = hpX + Num(conf.hpTextLeftOffsetX, 0),
      healthLeftY = hpY + Num(conf.hpTextLeftOffsetY, 0),
      healthCenterX = hpX + Num(conf.hpTextCenterOffsetX, 0),
      healthCenterY = hpY + Num(conf.hpTextCenterOffsetY, 0),
      healthRightX = hpX + Num(conf.hpTextRightOffsetX, 0),
      healthRightY = hpY + Num(conf.hpTextRightOffsetY, 0),
      powerLeft = conf.powerTextLeft or "NONE",
      powerCenter = conf.powerTextCenter or "NONE",
      powerRight = conf.powerTextRight or "NONE",
      powerDelimiter = conf.powerTextDelimiter or " / ",
      powerLayer = Layer(conf.powerTextLayer, 2),
      powerLeftX = powerX + Num(conf.powerTextLeftOffsetX, 0),
      powerLeftY = powerY + Num(conf.powerTextLeftOffsetY, 0),
      powerCenterX = powerX + Num(conf.powerTextCenterOffsetX, 0),
      powerCenterY = powerY + Num(conf.powerTextCenterOffsetY, 0),
      powerRightX = powerX + Num(conf.powerTextRightOffsetX, 0),
      powerRightY = powerY + Num(conf.powerTextRightOffsetY, 0),
      shortNumbers = true,
    },
    prediction = CompilePrediction(kind, conf, texture),
    dispel = CompileDispelVisual(kind, conf),
    status = status,
    border = {
      enabled = conf.borderEnabled ~= false,
      thickness = borderThickness,
      r = Num(ScopedValue(conf, general, "barOutlineColorR", conf.borderR or general and general.barBorderR), 0),
      g = Num(ScopedValue(conf, general, "barOutlineColorG", conf.borderG or general and general.barBorderG), 0),
      b = Num(ScopedValue(conf, general, "barOutlineColorB", conf.borderB or general and general.barBorderB), 0),
      a = Num(ScopedValue(conf, general, "barOutlineColorA", conf.borderA or general and general.barBorderA), 1),
      highlightThickness = Num(highlightThickness, borderThickness),
      aggro = aggroBorderEnabled == true,
      aggroMode = conf.aggroMode or general.aggroMode or "ALL",
      aggroR = Num(general.hlAggroColorR or general.aggroBorderColorR or general.aggroBorderR, 1.00),
      aggroG = Num(general.hlAggroColorG or general.aggroBorderColorG or general.aggroBorderG, 0.55),
      aggroB = Num(general.hlAggroColorB or general.aggroBorderColorB or general.aggroBorderB, 0.00),
      purgeR = Num(general.hlPurgeColorR or general.purgeBorderColorR, 1.00),
      purgeG = Num(general.hlPurgeColorG or general.purgeBorderColorG, 0.85),
      purgeB = Num(general.hlPurgeColorB or general.purgeBorderColorB, 0.00),
      dispel = dispelBorderEnabled == true,
      dispelTrigger = NormalizeDispelDetectTrigger(dispelBorderTrigger),
      prioEnabled = prioEnabled,
      prioOrder = prioOrder,
    },
    alpha = alpha,
    auras = CompileCoreAuras(kind, conf),
    group = group,
    groupLayout = {
      clickCastEnabled = conf.clickCastEnabled ~= false,
      hideInClientScene = conf.hideInClientScene ~= false,
      hideInHousing = conf.hideInHousing == true,
    },
    cornerIndicators = GF.CompileCornerIndicators and GF.CompileCornerIndicators(conf) or { enabled = false },
    spellIndicators = GF.CompileSpellIndicators and GF.CompileSpellIndicators(conf) or { enabled = false, items = {} },
  }
end

function GF.InvalidateCompiledSpecs(kind)
  if kind then
    compiledSpecSettingsGenByKind[kind] = (compiledSpecSettingsGenByKind[kind] or 1) + 1
  else
    compiledSpecSettingsGenAll = compiledSpecSettingsGenAll + 1
    GF._compiledSpecSettingsGenAll = compiledSpecSettingsGenAll
  end
  if kind then
    compiledSpecCache[kind] = nil
  else
    wipe(compiledSpecCache)
  end
end

function GF.DropCompiledSpecs(kind)
  if kind then
    compiledSpecCache[kind] = nil
  else
    wipe(compiledSpecCache)
  end
end

local function CompiledSpecSettingsToken(kind)
  return tostring(compiledSpecSettingsGenAll) .. ":" .. tostring(compiledSpecSettingsGenByKind[kind] or 1)
end

local function CompiledSpecContentKey(kind, base)
  local auras = base and base.auras
  local status = base and base.status
  return table.concat({
    tostring(kind or ""),
    tostring(base and base.width or ""),
    tostring(base and base.height or ""),
    tostring(auras and auras.dynamicScaleValue or 1),
    tostring(status and status.runtimePVP == true and 1 or 0),
    CompiledSpecSettingsToken(kind),
  }, "|")
end

local function StampCompiledSpec(kind, base)
  if not (kind and base) then
    return
  end
  local key = CompiledSpecContentKey(kind, base)
  if compiledSpecKey[kind] ~= key then
    compiledSpecKey[kind] = key
    GF._compiledSpecSerial = (GF._compiledSpecSerial or 1) + 1
    compiledSpecSerialByKind[kind] = GF._compiledSpecSerial
  end
  base._msufGFCompileSerial = compiledSpecSerialByKind[kind] or GF._compiledSpecSerial or 1
end

local function CopyShallow(dst, src)
  wipe(dst)
  for k, v in pairs(src) do
    dst[k] = v
  end
  return dst
end

local function PatchFrameSpec(base, kind, frame, unit, conf)
  local spec = frame._msufGFSpec
  if not spec then
    spec = {}
    frame._msufGFSpec = spec
  end
  if frame._msufGFSpecBase ~= base then
    CopyShallow(spec, base)
    frame._msufGFSpecBase = base
  end
  spec.unit = unit
  spec.key = "gf_" .. kind
  spec.groupKind = kind

  local role = GetRole(unit)
  local powerHeight = EffectivePowerHeight(kind, unit, role, conf)
  local power = frame._msufGFPowerSpec
  if not power then
    power = {}
    frame._msufGFPowerSpec = power
  end
  if frame._msufGFPowerSpecBase ~= base.power then
    CopyShallow(power, base.power)
    frame._msufGFPowerSpecBase = base.power
  end
  power.enabled = powerHeight > 0
  power.height = powerHeight
  spec.power = power

  local status = frame._msufGFStatusSpec
  if not status then
    status = {}
    frame._msufGFStatusSpec = status
  end
  if frame._msufGFStatusSpecBase ~= base.status then
    CopyShallow(status, base.status)
    frame._msufGFStatusSpecBase = base.status
  end
  status.roleValue = role
  spec.status = status
  return spec
end

--- Main compile entry. It turns the current GF config plus frame/unit context
--- into a generic unit-frame spec for the shared UF engine.
function GF.CompileSpec(kind, frame, unit)
  kind = kind or "party"
  local base = compiledSpecCache[kind]
  local conf = base and base._msufGFConf
  if not base then
    if GF.EnsureDB then
      GF.EnsureDB()
    end
    conf = GF.GetConf and GF.GetConf(kind) or {}
    base = CompileSpecUncached(kind, nil, nil, conf)
    StampCompiledSpec(kind, base)
    base._msufGFConf = conf
    compiledSpecCache[kind] = base
  elseif not conf then
    if GF.EnsureDB then
      GF.EnsureDB()
    end
    conf = GF.GetConf and GF.GetConf(kind) or {}
    base._msufGFConf = conf
  end
  unit = unit or (frame and frame.unit)
  if frame then
    return PatchFrameSpec(base, kind, frame, unit, conf)
  end
  return base
end

function GF.GetCompiledSpec(kind, frame, unit)
  return GF.CompileSpec(kind, frame, unit)
end
