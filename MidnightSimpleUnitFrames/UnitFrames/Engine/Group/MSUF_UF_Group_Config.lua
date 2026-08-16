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
  if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
  if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
  if value == "ANY_DEBUFF" or value == "DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
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
local AbsorbTextureTestEnabledForScope = UF.AbsorbTextureTestEnabledForScope or function(scope, category)
  local modes = _G.MSUF_PredictionTestModes
  if type(modes) == "table" then
    local normalized = NormalizeAbsorbTestScope(scope)
    local function Enabled(bucket)
      if type(bucket) ~= "table" then return false end
      if category == "heal" or category == "absorb" or category == "healAbsorb"
        or category == "tempMaxHealth" then return bucket[category] == true end
      return bucket.heal == true or bucket.absorb == true or bucket.healAbsorb == true
    end
    return Enabled(modes.shared) or (normalized ~= "shared" and Enabled(modes[normalized]))
  end
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

local function GradientScopedValue(conf, general, key, fallback, legacyKey)
  if GradientKeyActive(conf, key) and conf[key] ~= nil then return conf[key] end
  if legacyKey and GradientKeyActive(conf, legacyKey) and conf[legacyKey] ~= nil then return conf[legacyKey] end
  if general and general[key] ~= nil then return general[key] end
  if legacyKey and general and general[legacyKey] ~= nil then return general[legacyKey] end
  return fallback
end

local function FallbackResolveBarGradient(conf, general, enabledKey)
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
    if not GRADIENT_DIR_KEYS[legacy] then legacy = "RIGHT" end
    left, right, up, down = legacy == "LEFT", legacy == "RIGHT", legacy == "UP", legacy == "DOWN"
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
    left = left,
    right = right,
    up = up,
    down = down,
  }
end

local function FallbackFillPredictionColors(dst, general, conf, scopedValue, numberFn)
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

-- These mirrors keep isolated compiler tests/load-order probes deterministic.
-- The live addon still uses the shared UF core helpers whenever they are loaded.
local ResolveBarGradient = UF.ResolveBarGradient or FallbackResolveBarGradient
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

local function NormalizeFrameOutlineStrata(value)
  local normalize = _G.MSUF_NormalizeFrameStrata
  if type(normalize) == "function" then return normalize(value, "AUTO") end
  if value == nil or value == "" then return "AUTO" end
  value = tostring(value):upper()
  local rank = _G.MSUF_FRAME_STRATA_RANK
  return rank and rank[value] and value or "AUTO"
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

local function AuraIconScale(value)
  value = tonumber(value) or 100
  if value < 20 then value = 20 elseif value > 300 then value = 300 end
  return value / 100
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

local function ResolveStatusbarTextureKey(key, fallback)
  if type(key) == "string" and key ~= "" then
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local texture = type(resolve) == "function" and resolve(key) or nil
    if type(texture) == "string" and texture ~= "" then
      return texture
    end
  end
  return fallback or WHITE
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

local function GlobalHealthMode(cache, general)
  local mode = NormalizeHealthMode(cache and cache.barMode) or NormalizeHealthMode(general and general.barMode)
  if mode == "gradient" then
    local enabled = cache and cache.healthGradientEnabled
    if enabled == nil then enabled = general and general.enableHealthGradient ~= false end
    if enabled == false then mode = "class" end
  end
  return mode
end

--- Resolve the effective health-color model once per compile. Runtime visual
--- code receives concrete mode/color fields instead of profile fallback logic.
local function ResolveHealthVisual(conf)
  conf = conf or {}
  local cache = SettingsCache()
  local general = GeneralDB()
  local mode = NormalizeHealthMode(conf.gfBarMode)
  if not mode then
    mode = GlobalHealthMode(cache, general) or NormalizeHealthMode(conf.healthColorMode) or "class"
  end

  local out = {
    mode = mode == "custom" and "unified" or mode,
    r = Num(conf.healthCustomR, 0.2),
    g = Num(conf.healthCustomG, 0.8),
    b = Num(conf.healthCustomB, 0.2),
    lossR = Clamp01(general and general.healthLossColorR, 1),
    lossG = Clamp01(general and general.healthLossColorG, 0.55),
    lossB = Clamp01(general and general.healthLossColorB, 0.08),
    backgroundMatchHealth = (cache and cache.barBgMatchHPColor == true) or (general and general.barBgMatchHPColor == true) or false,
    backgroundClassColor = (cache and cache.barBgClassColor == true) or (general and general.barBgClassColor == true) or false,
    npcClassColorBar = (cache and cache.npcClassColorBar == true) or (general and general.npcClassColorBar == true) or false,
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

local POWER_MODE_ALIASES = {
  TYPE = "type", type = "type",
  CLASS = "class", class = "class",
  STATIC = "static", static = "static",
  CUSTOM = "static", custom = "static",
  DARK = "dark", dark = "dark",
  UNIFIED = "unified", unified = "unified",
}

local function NormalizePowerMode(value)
  return value ~= nil and POWER_MODE_ALIASES[value] or nil
end

--- Resolve the effective power-colour model once per compile, mirroring
--- CompileUnitPower. `static`/`dark`/`unified` publish concrete r/g/b so the
--- element's SetColor takes its constant-colour branch and never samples the
--- unit's power type; `type`/`class` deliberately leave them nil so the dynamic
--- per-token lookup stays in charge. The mode itself is global/legacy-profile
--- driven - the group page mirrors the unit page, which configures bar art and
--- colour once on Bars rather than per scope.
local function ResolvePowerVisual(conf)
  conf = conf or {}
  local cache = SettingsCache()
  local general = GeneralDB()
  local mode = NormalizePowerMode(conf.powerColorMode) or "type"
  local out = {
    mode = mode,
    lossR = Clamp01(general and general.powerLossColorR, 0.70),
    lossG = Clamp01(general and general.powerLossColorG, 0.90),
    lossB = Clamp01(general and general.powerLossColorB, 1),
    -- No engine consumer reads this yet (the live behaviour comes from the
    -- global bar-background runtime); keep it truthful instead of hardcoded.
    backgroundMatchHealth = (general and general.powerBarBgMatchBarColor == true) or false,
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
  elseif mode == "static" then
    out.r = Num(general and general.powerBarColorR, 0.10)
    out.g = Num(general and general.powerBarColorG, 0.35)
    out.b = Num(general and general.powerBarColorB, 0.95)
  end
  return out
end

--- Per-token power colour overrides. Group frames read the same account-wide
--- tables the unit frames do, so the Color Painter stays a single source of
--- truth for every frame type.
local function CompilePowerColorOverrides(dst)
  dst = type(dst) == "table" and dst or {}
  wipe(dst)
  local general = GeneralDB()
  if not general then return dst end
  local function Absorb(src, onlyMissing)
    if type(src) ~= "table" then return end
    for token, color in pairs(src) do
      if (not onlyMissing or dst[token] == nil) and type(color) == "table" then
        local r = tonumber(color.r or color[1])
        local g = tonumber(color.g or color[2])
        local b = tonumber(color.b or color[3])
        if r and g and b then
          dst[token] = { r = r, g = g, b = b }
        end
      end
    end
  end
  Absorb(general.powerColorOverrides)
  Absorb(general.classPowerColorOverrides, true)
  return dst
end

--- Rectangular power-bar border. Thickness is clamped to the same 0..10 band
--- the unit compiler uses; the colour follows the shared bar outline colour so
--- the power edge matches the frame outline without a second colour picker.
local function CompilePowerBorder(power, conf, general)
  local thickness = Num(conf.powerBarBorderThickness, 1)
  if thickness < 0 then thickness = 0 elseif thickness > 10 then thickness = 10 end
  power.borderEnabled = conf.powerBarBorderEnabled == true and thickness > 0
  power.borderThickness = thickness
  power.borderR = Num(ScopedValue(conf, general, "barOutlineColorR", conf.borderR or general and general.barBorderR), 0)
  power.borderG = Num(ScopedValue(conf, general, "barOutlineColorG", conf.borderG or general and general.barBorderG), 0)
  power.borderB = Num(ScopedValue(conf, general, "barOutlineColorB", conf.borderB or general and general.barBorderB), 0)
  power.borderA = Num(ScopedValue(conf, general, "barOutlineColorA", conf.borderA or general and general.barBorderA), 1)
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
  elseif general and general.nameColorMode == "CUSTOM" then
    -- Shared Fonts scope custom name color. Mirrored here so one shared choice
    -- does not colour unit frames while leaving group names on the font color.
    text.nameColor = {
      r = Num(general.nameColorR, 1),
      g = Num(general.nameColorG, 1),
      b = Num(general.nameColorB, 1),
      a = 1,
    }
  else
    text.nameClassColor = general and general.nameClassColor == true
    text.nameNpcColor = general and general.npcNameRed == true
    text.nameNpcClassColor = general and general.nameNpcClassColor == true
  end
  local healthTextColorMode = general and general.colorHealthTextByHealth
  if conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then
    healthTextColorMode = conf.colorHealthTextByHealth
  end
  text.healthColorByHealth = healthTextColorMode == true or healthTextColorMode == "HEALTH"
  text.healthColorByClass = healthTextColorMode == "CLASS"

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
  -- Raw configured slots only. The engine's ResolveHealthTextModes applies the
  -- reverse-order mirror exactly once at apply time; routing through
  -- GF.ResolveHealthTextSlots pre-swapped the modes here, so the engine's own
  -- swap undid the reversal while the hide-%/absorb flags stayed mirrored.
  if conf and conf.showHPText == false then
    return "NONE", "NONE", "NONE"
  end
  return (conf and conf.textLeft) or "NONE", (conf and conf.textCenter) or "NONE", (conf and conf.textRight) or "NONE"
end

local function IsPowerTextEnabled(kind, conf)
  if GF.IsPowerTextEnabled then
    return GF.IsPowerTextEnabled(kind, conf)
  end
  return conf.showPowerText == true or conf.showPower == true
end

local function ResolvePowerTextColorByType(conf, general)
  local enabled = general and general.colorPowerTextByType == true
  if conf and conf.fontOverride == true then
    if conf.powerTextColorByType ~= nil then
      enabled = conf.powerTextColorByType == true
    elseif conf.colorPowerTextByType ~= nil then
      enabled = conf.colorPowerTextByType == true
    end
  end
  return enabled
end

local function ResolveTextSlotHidePercentSymbol(conf, general, key)
  if conf and conf[key] ~= nil then
    return conf[key] == true
  end
  return general and general.hidePercentSymbol == true
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

local function CompileStatusRuntimeEvents(leader, assist, readyCheck, summon, phase, raidMarker, raidGroup, statusTextFlags, statusTextPlayerFlags, incomingRes, pvp)
  local events, unitlessEvents
  if phase then
    events = AddEvent(events, "UNIT_PHASE")
    events = AddEvent(events, "UNIT_OTHER_PARTY_CHANGED")
  end
  if statusTextFlags then
    events = AddEvent(events, "UNIT_FLAGS")
  end
  -- Health forwards UNIT_CONNECTION directly, and Core's shared group
  -- lifecycle plan owns PARTY_MEMBER_ENABLE/DISABLE. Keeping them here would
  -- run the same status transition twice on the fused health/lifecycle paths.
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
  if leader or assist or raidGroup then
    unitlessEvents = AddEvent(unitlessEvents, "GROUP_ROSTER_UPDATE")
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
  statusAFKTimer = { "statusAFKTimerTextSize", 10, "statusAFKTimerTextAnchor", "CENTER", "statusAFKTimerOffsetX", 0, "statusAFKTimerOffsetY", -10, "statusAFKTimerTextLayer", 7 },
  statusDND = { "statusDNDTextSize", 14, "statusDNDTextAnchor", "CENTER", "statusDNDOffsetX", 0, "statusDNDOffsetY", 0, "statusDNDTextLayer", 7 },
  raidGroup = { "groupNumberSize", 10, "groupNumberAnchor", "BOTTOMRIGHT", "groupNumberX", -2, "groupNumberY", 2, "groupNumberLayer", 7 },
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
  local statusPlayerFlagTextEnabled = conf.statusAFKText == true or conf.statusDNDText == true
  local statusFlagTextEnabled = statusDeadGhostTextEnabled or statusPlayerFlagTextEnabled
  local statusTextEnabled = statusConnectionTextEnabled or statusFlagTextEnabled
  local raidGroupEnabled = conf.showGroupNumber == true
  local runtimeEvents, runtimeUnitlessEvents = CompileStatusRuntimeEvents(
    leaderEnabled, assistEnabled, readyCheckEnabled, summonEnabled, phaseEnabled,
    raidMarkerEnabled, raidGroupEnabled, statusFlagTextEnabled, statusPlayerFlagTextEnabled, incomingResEnabled, pvpEnabled
  )
  local runtimeEnabled = roleEnabled or leaderEnabled or assistEnabled
    or readyCheckEnabled or summonEnabled or phaseEnabled
    or raidMarkerEnabled or raidGroupEnabled or statusTextEnabled or incomingResEnabled or pvpEnabled

  local role = StatusRegionDef(conf, roleEnabled, "role")
  role.style = conf.roleIconStyle
  role.customIcon = conf.roleIconCustomIcon
  role.showTank = conf.roleIconShowTank ~= false
  role.showHealer = conf.roleIconShowHealer ~= false
  role.showDPS = conf.roleIconShowDPS ~= false
  local leader = StatusRegionDef(conf, leaderEnabled, "leader")
  leader.style = conf.leaderIconStyle
  leader.customIcon = conf.leaderIconCustomIcon
  local assist = StatusRegionDef(conf, assistEnabled, "assist")
  assist.style = conf.assistIconStyle
  assist.customIcon = conf.assistIconCustomIcon
  local statusText = StatusRegionDef(conf, statusTextEnabled, "statusText")
  statusText.showDead = conf.statusText == true
  statusText.showGhost = conf.statusGhostText == true
  statusText.showAFK = conf.statusAFKText == true
  statusText.showDND = conf.statusDNDText == true
  statusText.dead = StatusRegionDef(conf, conf.statusText == true, "statusText")
  statusText.ghost = StatusRegionDef(conf, conf.statusGhostText == true, "statusGhost")
  statusText.afk = StatusRegionDef(conf, conf.statusAFKText == true, "statusAFK")
  statusText.dnd = StatusRegionDef(conf, conf.statusDNDText == true, "statusDND")
  statusText.afkTimer = StatusRegionDef(conf, conf.statusAFKTimerText == true, "statusAFKTimer")
  local raidGroup = StatusRegionDef(conf, raidGroupEnabled, "raidGroup")
  raidGroup.style = conf.groupNumberStyle or "PAREN"
  --- Every icon carries its own style now, so the non-role indicators stop falling back to the
  --- retired scope-wide default. The value may carry the "@MIDNIGHT" suffix; the DB resolvers
  --- split it, so it is forwarded untouched.
  local raidMarker = StatusRegionDef(conf, raidMarkerEnabled, "raidMarker")
  raidMarker.style = conf.raidMarkerStyle
  raidMarker.customIcon = conf.raidMarkerCustomIcon
  local readyCheck = StatusRegionDef(conf, readyCheckEnabled, "readyCheck")
  readyCheck.style = conf.readyCheckIconStyle
  readyCheck.customIcon = conf.readyCheckIconCustomIcon
  local summon = StatusRegionDef(conf, summonEnabled, "summon")
  summon.style = conf.summonIconStyle
  summon.customIcon = conf.summonIconCustomIcon
  local incomingRes = StatusRegionDef(conf, incomingResEnabled, "incomingRes")
  incomingRes.style = conf.resurrectIconStyle
  incomingRes.customIcon = conf.resurrectIconCustomIcon
  local pvp = StatusRegionDef(conf, pvpEnabled, "pvp")
  pvp.style = conf.pvpIconStyle
  pvp.customIcon = conf.pvpIconCustomIcon
  local phase = StatusRegionDef(conf, phaseEnabled, "phase")
  phase.style = conf.phaseIconStyle
  phase.customIcon = conf.phaseIconCustomIcon

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
    iconStyle = conf.iconStyle or "BLIZZARD",
    useMidnight = conf.useMidnightIcons == true,
    role = role,
    raidMarker = raidMarker,
    leader = leader,
    assist = assist,
    readyCheck = readyCheck,
    summon = summon,
    incomingRes = incomingRes,
    pvp = pvp,
    phase = phase,
    statusText = statusText,
    raidGroup = raidGroup,
  }
end

local function CompilePrediction(kind, conf, texture)
  local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
  local absorbEnabled = ScopedValue(conf, general, "enableAbsorbBar", nil)
  if absorbEnabled == nil and conf and conf.hlOverride == true and conf.absorbEnabled ~= nil then
    absorbEnabled = conf.absorbEnabled
  end
  if absorbEnabled == nil then
    local absorbMode = Num(ScopedValue(conf, general, "absorbTextMode", nil), nil)
    absorbEnabled = absorbMode == nil or absorbMode == 2 or absorbMode == 3
  end
  local absorb = absorbEnabled ~= false
  local heal = GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf) or conf.healPredEnabled == true
  local healAbsorb = ScopedValue(conf, general, "healAbsorbEnabled", true) ~= false
  local healTest = AbsorbTextureTestEnabledForScope(kind, "heal")
  local absorbTest = AbsorbTextureTestEnabledForScope(kind, "absorb")
  local healAbsorbTest = AbsorbTextureTestEnabledForScope(kind, "healAbsorb")
  local test = healTest == true or absorbTest == true or healAbsorbTest == true
  if healTest == true then heal = true end
  if absorbTest == true then absorb = true end
  if healAbsorbTest == true then healAbsorb = true end
  local function Geometry(key, fallback, low, high)
    local value = Num(ScopedValue(conf, general, key, fallback), fallback)
    if value < low then return low end
    if value > high then return high end
    return value
  end
  local out = {
    enabled = heal == true or absorb == true or healAbsorb == true,
    heal = heal == true,
    absorb = absorb == true,
    healAbsorb = healAbsorb == true,
    test = test == true,
    healTest = healTest == true,
    absorbTest = absorbTest == true,
    healAbsorbTest = healAbsorbTest == true,
    healAnchorMode = Num(ScopedValue(conf, general, "healPredAnchorMode", 3), 3),
    absorbAnchorMode = Num(ScopedValue(conf, general, "absorbAnchorMode", 2), 2),
    healAbsorbAnchorMode = Num(ScopedValue(conf, general, "healAbsorbAnchorMode", 3), 3),
    healHeight = Geometry("healPredictionBarHeight", 0, 0, 100),
    healOffsetY = Geometry("healPredictionBarOffsetY", 0, -100, 100),
    absorbHeight = Geometry("absorbBarHeight", 0, 0, 100),
    absorbOffsetY = Geometry("absorbBarOffsetY", 0, -100, 100),
    healAbsorbHeight = Geometry("healAbsorbBarHeight", 0, 0, 100),
    healAbsorbOffsetY = Geometry("healAbsorbBarOffsetY", 0, -100, 100),
    overAbsorbOverlay = ScopedValue(conf, general, "overAbsorbOverlay", false) == true,
    fullHealthAbsorbStripe = ScopedValue(conf, general, "fullHealthAbsorbStripe", false) == true,
    texture = ScopedValue(conf, general, "healPredictionBarTexture", texture),
    absorbTexture = ScopedValue(conf, general, "absorbBarTexture", nil),
    healAbsorbTexture = ScopedValue(conf, general, "healAbsorbBarTexture", nil),
  }
  FillPredictionColors(out, general, conf, ScopedValue, Num)
  return out
end

local function ResolveTextSlotFontSize(conf, key, fallback)
  local value = Num(conf and conf[key], fallback)
  return value > 0 and value or fallback
end

local function CompileTempMaxHealth(kind, conf, texture)
  local general = _G.MSUF_DB and _G.MSUF_DB.general or {}
  local textureKey = ScopedValue(conf, general, "tempMaxHealthTexture", "")
  local resolvedTexture = texture
  if type(textureKey) == "string" and textureKey ~= "" then
    local resolve = _G.MSUF_ResolveStatusbarTextureKey
    local candidate = type(resolve) == "function" and resolve(textureKey) or textureKey
    if type(candidate) == "string" and candidate ~= "" then resolvedTexture = candidate end
  end
  local test = AbsorbTextureTestEnabledForScope(kind, "tempMaxHealth")
  return {
    enabled = ScopedValue(conf, general, "tempMaxHealthEnabled", false) == true or test == true,
    test = test == true,
    texture = resolvedTexture,
    r = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorR", 0.70), 0.70),
    g = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorG", 0.10), 0.10),
    b = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorB", 0.10), 0.10),
    a = Clamp01(ScopedValue(conf, general, "tempMaxHealthOpacity", 1), 1),
    backgroundAlpha = Clamp01(ScopedValue(conf, general, "tempMaxHealthBackgroundOpacity", 0.65), 0.65),
  }
end

local function CompileDispelVisual(kind, conf)
  local out = {
    r = 0.25,
    g = 0.75,
    b = 1,
    a = 1,
  }
  return out
end

--- Dispel-type symbol indicator. Auras3 normalizes/clamps every field, so this
--- only forwards the raw values; the shape must stay identical to the unit-frame
--- table in MSUF_UF_Config.lua so one compiler serves both scopes.
local function CompileDispelSymbol(conf)
  conf = conf or {}
  local out = {
    enabled = conf.dispelSymbolEnabled == true,
    style = conf.dispelSymbolStyle or "BLIZZARD",
    mode = conf.dispelSymbolMode or "ALL",
    trigger = conf.dispelSymbolTrigger or "BORDER",
    size = Num(conf.dispelSymbolSize, 12),
    spacing = Num(conf.dispelSymbolSpacing, 2),
    growth = conf.dispelSymbolGrowth or "RIGHT",
    anchor = conf.dispelSymbolAnchor or "TOPRIGHT",
    x = Num(conf.dispelSymbolX, 0),
    y = Num(conf.dispelSymbolY, 0),
    alpha = Clamp01(conf.dispelSymbolAlpha, 1),
    layer = Layer(conf.dispelSymbolLayer, 8),
    strata = NormalizeFrameOutlineStrata(conf.dispelSymbolStrata),
  }
  -- Auras3 caches its compiled group config against this. ReplaceTableContents
  -- keeps table identity across a visual-domain refresh, so identity alone
  -- cannot detect an edit -- and Auras3 resolves per frame per identity event,
  -- which is far too hot to rebuild a 13-part string on. Stamp it once here,
  -- where the settings are actually read.
  out.signature = table.concat({
    tostring(out.enabled), out.style, out.mode, out.trigger,
    tostring(out.size), tostring(out.spacing), out.growth, out.anchor,
    tostring(out.x), tostring(out.y), tostring(out.alpha),
    tostring(out.layer), tostring(out.strata),
  }, "\031")
  return out
end

local function CompileGroupVisuals(kind, conf)
  local general = _G.MSUF_DB and _G.MSUF_DB.general
  local hoverR, hoverG, hoverB = ResolveHighlightRGB()
  local hoverSize = general and general.highlightThickness
  if hoverSize == nil then
    hoverSize = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlHoverSize") or conf.hlHoverSize
  end
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
    offlineFadeEnabled = conf.offlineFadeEnabled == true,
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
    targetIndicator = conf.targetIndicator ~= false,
    targetR = Num(conf.targetR, 1),
    targetG = Num(conf.targetG, 1),
    targetB = Num(conf.targetB, 1),
    focusIndicator = conf.hlFocusEnabled ~= false,
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
    dispelOverlayLayer = Layer(conf.dispelOverlayLayer, 0),
    dispelOverlayStrata = NormalizeFrameOutlineStrata(conf.dispelOverlayStrata),
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
    IsBlizzardAuraTypeEnabled(conf, "externals")
end

local NATIVE_AURA_BLACKLIST_HASHES_ENABLED = true

local function AuraBlacklistHash(kind, groupKey, group)
  -- PTR 12.1 CustomAuraContainer candidateFilters can consume SpellID maps.
  -- Keep the expensive category expansion cached in the AuraFilter helper and
  -- pass only the resolved hash into the compiled spec.
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
  if groupKey == "buff" or groupKey == "trackedBuff" then
    return filter and filter.ResolveBuffFilter and filter.ResolveBuffFilter(token) or "HELPFUL"
  elseif groupKey == "externals" then
    -- Match Blizzard's 12.1 ExternalDefensivesFrame. EXTERNAL_DEFENSIVE already
    -- identifies defensives received from other players; !PLAYER only adds an
    -- avoidable caster-identity restriction for group units.
    return filter and filter.EXTERNALS_TOKEN or "HELPFUL|EXTERNAL_DEFENSIVE"
  end
  return filter and filter.ResolveDebuffFilter and filter.ResolveDebuffFilter(token) or "HARMFUL"
end

local function ExcludeAuraFilterToken(filterString, token)
  filterString = tostring(filterString or "")
  token = tostring(token or "")
  if token == "" then return filterString end
  local exclusion = "!" .. token
  if filterString:find(exclusion, 1, true) then return filterString end
  if filterString == "" then return exclusion end
  return filterString .. "|" .. exclusion
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
  trackedBuff = { "maxTrackedBuffs", 4, "TOPLEFT", 9, 8, 10, true, false },
  debuff = { "maxDebuffs", 3, "TOPLEFT", 6, 8, 10 },
  external = { "maxExternals", 3, "CENTER", 7, 10, 10, false, false },
}

local function ApplyAuraLane(out, prefix, groupKey, group, defaults, maxCount, iconSize, growthX, growthY, scale, kind)
  out[defaults[1]] = Num(group.max, maxCount)
  local iconScale = AuraIconScale(group.iconScale)
  out[prefix .. "IconScale"] = iconScale
  local iconZoom = group.iconZoom
  if iconZoom == nil and (prefix == "trackedBuff" or prefix == "external") then
    iconZoom = out.buffIconZoom
  end
  out[prefix .. "IconZoom"] = Num(iconZoom, Num(out.iconZoom, 100))
  local iconShape = group.iconShape
  if iconShape == nil and (prefix == "trackedBuff" or prefix == "external") then
    iconShape = out.buffIconShape
  end
  out[prefix .. "IconShape"] = type(iconShape) == "string" and iconShape or "RECTANGLE"
  out[prefix .. "IconSize"] = scale(Num(group.size, iconSize) * iconScale, iconSize, 1)
  out[prefix .. "Spacing"] = scale(group.spacing, 1, 0)
  out[prefix .. "PerRow"] = Num(group.perRow, defaults[2])
  out[prefix .. "GrowthX"] = growthX
  out[prefix .. "GrowthY"] = growthY
  out[prefix .. "Anchor"] = group.anchor or defaults[3]
  out[prefix .. "OffsetX"] = scale(group.x, 0)
  out[prefix .. "OffsetY"] = scale(group.y, 0)
  out[prefix .. "Layer"] = Layer(group.layer, defaults[4])
  out[prefix .. "Strata"] = NormalizeFrameOutlineStrata(group.strata)
  out[prefix .. "Alpha"] = group.behindBar == true and LaneAlpha(group) or 1
  out[prefix .. "Filter"] = AuraFilterString(groupKey, group)
  local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
  out[prefix .. "HidePermanent"] = group.hidePermanent == true or (blacklist and blacklist.hidePermanent == true) or false
  if prefix == "debuff" then
    out.debuffMaxDuration = Num(blacklist and blacklist.maxDuration, 0)
    local filter = GF.AuraFilter or _G.MSUF_GF_AuraFilter
    local nonPlayer = tostring(group.filterToken or ""):upper():gsub("[^A-Z0-9]", "") == "NONPLAYER"
    if filter and filter.IsNonPlayerDebuffFilter then
      nonPlayer = filter.IsNonPlayerDebuffFilter(group.filterToken) == true
    end
    out.debuffNonPlayer = nonPlayer
  end
  if group.showTooltip ~= nil then
    out[prefix .. "ShowTooltip"] = group.showTooltip == true
  end
  out[prefix .. "ShowCooldownSwipe"] = group.showCooldownSwipe ~= false
  out[prefix .. "CooldownSwipeReverse"] = group.cooldownSwipeReverse == true
  out[prefix .. "SortMethod"] = group.sortMethod or "DEFAULT"
  out[prefix .. "SortReverse"] = group.sortReverse == true
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
  out[prefix .. "CooldownDecimalSeconds"] = Num(group.cooldownDecimalSeconds, 3)
  out[prefix .. "StackSize"] = scale(group.stackSize, defaults[6], 6)
  out[prefix .. "StackAnchor"] = AuraTextAnchor(group.stackAnchor, "BOTTOMRIGHT")
  out[prefix .. "StackX"] = scale(group.stackX, 0)
  out[prefix .. "StackY"] = scale(group.stackY, 0)
  if defaults[8] ~= false then
    out[prefix .. "BlacklistHash"] = AuraBlacklistHash(kind, groupKey, group)
  end
end

local function SpellIndicatorModule()
  return GF.SpellIndicators or _G.MSUF_GF_SpellIndicators
end

local function AddSpellIDToHash(hash, spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0 end
  spellID = floor(spellID + 0.5)
  if spellID <= 0 or hash[spellID] == true then return 0 end
  hash[spellID] = true
  return 1
end

local function AddSpellIDAliasesToHash(hash, si, spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0 end
  spellID = floor(spellID + 0.5)
  local aliases = si and ((si.AuraSpellIDAliases and si.AuraSpellIDAliases[spellID])
    or (si.CustomAuraAliases and si.CustomAuraAliases[spellID]))
  if aliases == nil then return 0 end
  if type(aliases) ~= "table" then return AddSpellIDToHash(hash, aliases) end
  local count = 0
  for key, value in pairs(aliases) do
    if value == true then
      count = count + AddSpellIDToHash(hash, key)
    elseif value ~= false then
      count = count + AddSpellIDToHash(hash, value)
    end
  end
  return count
end

local function AddSpellIDToHashWithAliases(hash, si, spellID)
  local count = AddSpellIDToHash(hash, spellID)
  count = count + AddSpellIDAliasesToHash(hash, si, spellID)
  return count
end

local function AddSpellIDsForAura(hash, si, specKey, auraName, entry)
  if not (hash and si and specKey and auraName) then return 0 end
  local count = 0
  local includeAliases = type(entry) == "table" and entry.custom == true
  local function AddResolved(spellID)
    if includeAliases then return AddSpellIDToHashWithAliases(hash, si, spellID) end
    return AddSpellIDToHash(hash, spellID)
  end
  local id = tonumber(auraName)
  if id then count = count + AddResolved(id) end
  if type(entry) == "table" then
    count = count + AddResolved(entry.spellID or entry.spellId or entry.id)
    if includeAliases and type(entry.spells) == "string" then
      for token in entry.spells:gmatch("%d+") do
        count = count + AddResolved(token)
      end
    end
  end
  local ids = si.SpellIDs and si.SpellIDs[specKey]
  if ids then count = count + AddResolved(ids[auraName]) end
  local secretIDs = si.SecretSpellIDs and si.SecretSpellIDs[specKey]
  if secretIDs then count = count + AddResolved(secretIDs[auraName]) end
  local altIDs = si.AltSpellIDs and si.AltSpellIDs[specKey]
  if type(altIDs) == "table" then
    for spellID, mappedAuraName in pairs(altIDs) do
      if mappedAuraName == auraName then count = count + AddResolved(spellID) end
    end
  end
  local linked = si.LinkedAuraRules and si.LinkedAuraRules[specKey] and si.LinkedAuraRules[specKey][auraName]
  if type(linked) == "table" then
    count = count + AddResolved(linked.sourceSpellID)
    if type(linked.targetSpellIDs) == "table" then
      for i = 1, #linked.targetSpellIDs do
        count = count + AddResolved(linked.targetSpellIDs[i])
      end
    end
  end
  local trackable = si.TrackableAuras and si.TrackableAuras[specKey]
  if type(trackable) == "table" then
    for i = 1, #trackable do
      local info = trackable[i]
      if info and info.name == auraName then
        count = count + AddResolved(info.spellID or info.spellId or info.id)
        break
      end
    end
  end
  return count
end

local function CollectSpellIndicatorSpecs(siCfg, si)
  local out, seen = {}, {}
  local selected = siCfg and siCfg.spec or "auto"
  local function Add(specKey)
    if specKey and si and si.SpecInfo and si.SpecInfo[specKey] and not seen[specKey] then
      seen[specKey] = true
      out[#out + 1] = specKey
    end
  end
  if selected == "multi" then
    local allSpecsKey = si and si.ALL_SPECS_KEY
    local allSpecsConfig = allSpecsKey and type(siCfg and siCfg.specs) == "table" and siCfg.specs[allSpecsKey]
    if type(allSpecsConfig) == "table" and next(allSpecsConfig) ~= nil then
      Add(allSpecsKey)
    end
    local multi = type(siCfg and siCfg.multiSpecs) == "table" and siCfg.multiSpecs or nil
    if multi then
      for specKey, enabled in pairs(multi) do
        if enabled and specKey ~= allSpecsKey then Add(specKey) end
      end
    end
  elseif selected ~= "auto" then
    Add(selected)
  end
  if #out == 0 and si and type(si.GetPlayerSpec) == "function" then
    Add(si.GetPlayerSpec())
  end
  if #out == 0 and si and type(si.SpecInfo) == "table" then
    for specKey in pairs(si.SpecInfo) do
      Add(specKey)
      break
    end
  end
  return out
end

local function BuildSpellIndicatorAuraHashes(conf)
  local si = SpellIndicatorModule()
  local siCfg = type(conf and conf.spellIndicators) == "table" and conf.spellIndicators or nil
  if not (si and siCfg) then return nil, 0, nil end
  siCfg.specs = siCfg.specs or {}
  local specs = CollectSpellIndicatorSpecs(siCfg, si)
  local hash, count, autoBlacklistHash, autoBlacklistCount = {}, 0, nil, 0
  local autoBlacklistEnabled = siCfg.enabled == true
  local auraRoot = type(conf and conf.auras) == "table" and conf.auras or nil
  local externals = auraRoot and type(auraRoot.externals) == "table" and auraRoot.externals or {}
  local externalLaneActive = (auraRoot == nil or auraRoot.enabled ~= false)
    and externals.enabled ~= false and Num(externals.max, 2) > 0
  local externalAutoBlacklistActive = externalLaneActive
    and externals.autoBlacklistBuffs ~= false
  for i = 1, #specs do
    local specKey = specs[i]
    local specCfg = siCfg.specs and siCfg.specs[specKey]
    local defaults = si.SpecDefaults and si.SpecDefaults[specKey]
    if type(defaults) == "table" then
      for auraName, def in pairs(defaults) do
        local entry = type(specCfg) == "table" and specCfg[auraName] or nil
        if entry == nil then entry = def end
        if type(entry) == "table" and entry.enabled ~= false then
          count = count + AddSpellIDsForAura(hash, si, specKey, auraName, entry)
        end
      end
    end
    if type(specCfg) == "table" then
      for auraName, entry in pairs(specCfg) do
        if type(entry) == "table" and entry.enabled ~= false then
          if not (type(defaults) == "table" and defaults[auraName] ~= nil) then
            count = count + AddSpellIDsForAura(hash, si, specKey, auraName, entry)
          end
          local externalDefensive = type(si.IsExternalDefensiveAura) == "function"
            and si.IsExternalDefensiveAura(specKey, auraName, entry) == true
          -- The native !EXTERNAL_DEFENSIVE filter already owns this case and
          -- is both broader and cheaper than duplicating every external ID.
          -- Without the External lane, an own-cast-only Spell Icon must not
          -- blacklist the ID globally: that would also erase another player's
          -- Ironbark (or equivalent) from Buffs with nowhere else to show it.
          local safeToBlacklist = not externalDefensive
            or (not externalAutoBlacklistActive
              and (externalLaneActive or entry.onlyOwn == false))
          if autoBlacklistEnabled and entry.autoBlacklist == true and safeToBlacklist then
            autoBlacklistHash = autoBlacklistHash or {}
            autoBlacklistCount = autoBlacklistCount + AddSpellIDsForAura(autoBlacklistHash, si, specKey, auraName, entry)
          end
        end
      end
    end
  end
  if count <= 0 then hash = nil end
  if autoBlacklistCount <= 0 then autoBlacklistHash = nil end
  return hash, count, autoBlacklistHash
end

local function MergeSpellIDHashes(primary, extra)
  if type(extra) ~= "table" then return primary end
  if type(primary) == "table" then
    -- `extra` is a fresh compile-local hash. Merge the cached manual entries
    -- into it so the cached table stays immutable without allocating a third
    -- result table.
    for spellID, enabled in pairs(primary) do
      if enabled == true then extra[spellID] = true end
    end
  end
  return extra
end

local function CompileCoreAuras(kind, conf)
  local root = type(conf.auras) == "table" and conf.auras or nil
  local buff = root and type(root.buff) == "table" and root.buff or {}
  local debuff = root and type(root.debuff) == "table" and root.debuff or {}
  local externals = root and type(root.externals) == "table" and root.externals or {}
  local rootEnabled = root == nil or root.enabled ~= false
  local showBuffs = rootEnabled and buff.enabled ~= false
  local showDebuffs = rootEnabled and debuff.enabled ~= false
  local showExternals = rootEnabled and externals.enabled ~= false
  local trackedBuffIncludeHash, trackedBuffCount, spellIndicatorAutoBlacklistHash = BuildSpellIndicatorAuraHashes(conf)
  local trackedBuffMax = Num(buff.trackedMax, Num(conf.trackedBuffMax, trackedBuffCount > 0 and trackedBuffCount or 8))
  local trackedBuffsEnabled = false
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
  local trackedBuffGrowthX, trackedBuffGrowthY = SplitAuraGrowth(buff.trackedGrowth or buff.growth, "RIGHTDOWN")
  local debuffGrowthX, debuffGrowthY = SplitAuraGrowth(debuff.growth, "RIGHTDOWN")
  local externalGrowthX, externalGrowthY = SplitAuraGrowth(externals.growth, "RIGHTDOWN")
  local auraScale = DynamicAuraScale(root)
  local defaultBuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 22
  local defaultTrackedBuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 22
  local defaultDebuffSize = (kind == "raid" or kind == "mythicraid") and 16 or 20
  local defaultExternalSize = (kind == "raid" or kind == "mythicraid") and 22 or 28
  local function S(value, fallback, minValue)
    return ScaleAuraValue(Num(value, fallback), auraScale, minValue)
  end
  local out = {
    enabled = showBuffs == true or showDebuffs == true or showExternals == true
      or trackedBuffsEnabled == true
      or conf.dispelEnabled == true
      or conf.dispelOverlayEnabled == true
      or conf.dispelSymbolEnabled == true,
    group = true,
    kind = kind,
    renderer = "NATIVE_12_1",
    blizzard = {
      buffs = IsBlizzardAuraTypeEnabled(root or {}, "buffs"),
      debuffs = IsBlizzardAuraTypeEnabled(root or {}, "debuffs"),
      dispels = IsBlizzardAuraTypeEnabled(root or {}, "dispels"),
      externals = IsBlizzardAuraTypeEnabled(root or {}, "externals"),
      iconSize = Num(root and root.blizzardIconSize, 20),
      organizationType = root and root.blizzardOrganizationType or "default",
      strata = root and root.blizzardContainerStrata or "AUTO",
      frameLevelOffset = Layer(root and root.blizzardContainerFrameLevel, 1),
      showCooldownText = not (root and root.blizzardShowCooldownText == false),
      dispelBorder = root and root.blizzardDispelBorder == true,
    },
    showBuffs = showBuffs,
    showTrackedBuffs = trackedBuffsEnabled == true,
    showDebuffs = showDebuffs,
    showExternals = showExternals,
    showTooltip = root == nil or root.showTooltip ~= false,
    showSwipe = true,
    showStacks = true,
    stackAnchor = "BOTTOMRIGHT",
    dynamicScale = root and root.dynamicScale == true,
    dynamicScaleValue = auraScale,
    iconZoom = Num(root and root.iconZoom, 100),
    iconSize = S(conf.auraIconSize, 20, 1),
    spacing = 1,
    perRow = 4,
    growth = "RIGHT",
    rowWrap = "DOWN",
    debuffDispelBorderMode = debuffDispelBorderMode,
    debuffShowDispelBorder = debuffDispelBorderMode ~= "OFF",
    debuffShowDispelSymbol = debuffDispelBorderMode == "SYMBOL",
    showStealableBuffs = false,
  }
  ApplyAuraLane(out, "buff", "buff", buff, AURA_LANE_DEFAULTS.buff, Num(conf.auraMaxIcons, 4), defaultBuffSize, buffGrowthX, buffGrowthY, S, kind)
  -- 12.1 filter components are natively negatable. Keep external defensives
  -- out of the normal Buff lane only while their dedicated lane is actually
  -- active; disabling that lane immediately restores them to Buffs.
  if showExternals == true and Num(externals.max, 2) > 0 and externals.autoBlacklistBuffs ~= false then
    out.buffFilter = ExcludeAuraFilterToken(out.buffFilter, "EXTERNAL_DEFENSIVE")
  end
  out.buffBlacklistHash = MergeSpellIDHashes(out.buffBlacklistHash, spellIndicatorAutoBlacklistHash)
  local trackedBuff = {
    max = trackedBuffMax,
    size = Num(buff.trackedSize, Num(buff.size, defaultTrackedBuffSize)),
    iconScale = Num(buff.trackedIconScale, Num(buff.iconScale, 100)),
    spacing = Num(buff.trackedSpacing, Num(buff.spacing, 1)),
    perRow = Num(buff.trackedPerRow, Num(buff.perRow, 4)),
    growth = buff.trackedGrowth or buff.growth or "RIGHTDOWN",
    anchor = buff.trackedAnchor or "TOPLEFT",
    x = Num(buff.trackedX, 0),
    y = Num(buff.trackedY, 0),
    layer = Layer(buff.trackedLayer, Layer(conf.spellIndicators and conf.spellIndicators.layer, 9)),
    strata = buff.trackedStrata or buff.trackedFrameStrata or (conf.spellIndicators and conf.spellIndicators.strata),
    filterToken = buff.trackedOnlyOwn ~= false and "PLAYER" or "ALL",
    -- The tracked lane is a SpellID whitelist derived from the same Buff
    -- settings. A permanent-aura exclusion must win over that whitelist too.
    hidePermanent = buff.hidePermanent == true
      or (type(buff.blacklist) == "table" and buff.blacklist.hidePermanent == true),
    showTooltip = buff.trackedShowTooltip,
    showCooldownSwipe = buff.trackedShowCooldownSwipe,
    cooldownSwipeReverse = buff.trackedCooldownSwipeReverse,
    -- Tracked Buffs are their own native AuraGroup. Keep their ordering local
    -- instead of silently inheriting the normal Buff container's comparator.
    sortMethod = buff.trackedSortMethod,
    sortReverse = buff.trackedSortReverse == true,
    showDurationBar = buff.trackedShowDurationBar,
    durationBarHeight = buff.trackedDurationBarHeight,
    durationBarDisplay = buff.trackedDurationBarDisplay,
    durationBarPosition = buff.trackedDurationBarPosition,
    durationBarDirection = buff.trackedDurationBarDirection,
    showCooldown = buff.trackedShowCooldown,
    showStacks = buff.trackedShowStacks,
    cooldownSize = buff.trackedCooldownSize,
    cooldownAnchor = buff.trackedCooldownAnchor,
    cooldownX = buff.trackedCooldownX,
    cooldownY = buff.trackedCooldownY,
    cooldownDecimalSeconds = buff.trackedCooldownDecimalSeconds,
    stackSize = buff.trackedStackSize,
    stackAnchor = buff.trackedStackAnchor,
    stackX = buff.trackedStackX,
    stackY = buff.trackedStackY,
  }
  ApplyAuraLane(out, "trackedBuff", "trackedBuff", trackedBuff, AURA_LANE_DEFAULTS.trackedBuff, 8, defaultTrackedBuffSize, trackedBuffGrowthX, trackedBuffGrowthY, S, kind)
  out.trackedBuffIncludeHash = trackedBuffIncludeHash
  out.trackedBuffTrackedCount = trackedBuffCount or 0
  ApplyAuraLane(out, "debuff", "debuff", debuff, AURA_LANE_DEFAULTS.debuff, Num(conf.auraMaxIcons, 4), defaultDebuffSize, debuffGrowthX, debuffGrowthY, S, kind)
  ApplyAuraLane(out, "external", "externals", externals, AURA_LANE_DEFAULTS.external, 2, defaultExternalSize, externalGrowthX, externalGrowthY, S, kind)
  return out
end

local function CompileAlpha(conf)
  local hpAlpha = Clamp01(conf and conf.hpBarAlpha, 1)
  local oocAlpha = Clamp01(conf and conf.oocFadeAlpha, 0.5)
  return {
    active = hpAlpha < 1,
    hpAlpha = hpAlpha,
    excludeTextPortrait = conf and conf.alphaExcludeTextPortrait == true,
    -- Out-of-combat fade: composed by GroupRangeFade (CoreAlpha) rather than
    -- the shared Alpha element; externalOoc keeps the element's frame lane
    -- untouched so the group composer never reads a stale ooc value.
    oocFade = conf ~= nil and conf.oocFadeEnabled == true and oocAlpha < 1,
    oocAlpha = oocAlpha,
    externalOoc = true,
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

local PORTRAIT_SHAPES = { CIRCLE = true, ROUNDED = true, DIAMOND = true }
local PORTRAIT_BORDERS = { SOLID = true, CLASS_COLOR = true, REACTION = true, CUSTOM = true }
local PORTRAIT_PLACEMENTS = { ATTACHED = true, DETACHED = true, OVERLAY = true }
local PORTRAIT_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local PORTRAIT_OVERLAY_ALIGNMENTS = { LEFT = true, CENTER = true, RIGHT = true, FULL = true }
local PORTRAIT_BORDER_DIRECTIONS = { UP = true, RIGHT = true, DOWN = true, LEFT = true }

local function PortraitClassStyle(value)
  local normalize = _G.MSUF_NormalizePortraitClassStyleValue
  if type(normalize) == "function" then return normalize(value) end
  local media = MSUF and MSUF.PortraitMedia
  if media and type(media.NormalizeClassPack) == "function" then return media.NormalizeClassPack(value) end
  if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then return value end
  return "BLIZZARD"
end

local function PortraitLevel(value)
  value = floor(Num(value, 7) + 0.5)
  if value < 0 then return 0 end
  if value > 30 then return 30 end
  return value
end

local function PortraitPan(value)
  value = Num(value, 0)
  if value < -100 then return -100 end
  if value > 100 then return 100 end
  return value
end

local function CompilePortraitTexCoords(portrait, zoom, width, height, panX, panY)
  zoom = Num(zoom, 100)
  if zoom > 1 and zoom <= 2 then zoom = zoom * 100 end
  if zoom < 100 then zoom = 100 elseif zoom > 200 then zoom = 200 end
  local span = 0.84 * (100 / zoom)
  local spanX, spanY = span, span
  if width > 0 and height > 0 and width ~= height then
    if width > height then spanY = span * (height / width)
    else spanX = span * (width / height) end
  end
  local slackX, slackY = (1 - spanX) * 0.5, (1 - spanY) * 0.5
  local centerX = 0.5 + (PortraitPan(panX) / 100) * slackX
  local centerY = 0.5 - (PortraitPan(panY) / 100) * slackY
  portrait.zoom = zoom
  portrait.texL, portrait.texR = centerX - spanX * 0.5, centerX + spanX * 0.5
  portrait.texT, portrait.texB = centerY - spanY * 0.5, centerY + spanY * 0.5
end

--- Party is the only GroupFrames scope that owns portrait settings. Returning
--- an explicit disabled spec for every other kind keeps stale/imported keys
--- from allocating a Portrait holder on recycled raid buttons.
local function CompilePortrait(kind, conf, frameHeight)
  if kind ~= "party" then return { enabled = false } end
  conf = conf or {}
  local mode = conf.portraitMode
  if mode ~= "LEFT" and mode ~= "RIGHT" then mode = conf.showPortrait == true and "LEFT" or "OFF" end
  local override = Num(conf.portraitSizeOverride, Num(conf.portraitSize, 0))
  local autoSize = math.max(16, Num(frameHeight, 40) - 4)
  -- `0` deliberately means automatic sizing. Every positive slider value is
  -- an explicit override and must therefore reach the portrait layout intact.
  local size = override > 0 and math.max(1, override) or autoSize
  local width = Num(conf.portraitWidth, 0)
  local height = Num(conf.portraitHeight, 0)
  local sizeMode = conf.portraitSizeMode
  if sizeMode ~= "UNIFORM" and sizeMode ~= "SEPARATE" then
    -- Legacy Party portraits always let either positive axis override Size.
    sizeMode = (width > 0 or height > 0) and "SEPARATE" or "UNIFORM"
  end
  if sizeMode == "UNIFORM" then
    width, height = size, size
  else
    -- Retain Size as the zero-axis fallback so toggling to independent axes
    -- never changes the visible portrait before either axis is edited.
    width = width > 0 and math.max(8, width) or size
    height = height > 0 and math.max(8, height) or size
  end
  local shape = PORTRAIT_SHAPES[conf.portraitShape] and conf.portraitShape or "SQUARE"
  local borderStyle = PORTRAIT_BORDERS[conf.portraitBorderStyle] and conf.portraitBorderStyle or "NONE"
  local placement = PORTRAIT_PLACEMENTS[conf.portraitPlacement] and conf.portraitPlacement or "ATTACHED"
  local point = PORTRAIT_POINTS[conf.portraitDetachedPoint] and conf.portraitDetachedPoint or "RIGHT"
  local relPoint = PORTRAIT_POINTS[conf.portraitDetachedTo] and conf.portraitDetachedTo or "LEFT"
  local overlayAlign = PORTRAIT_OVERLAY_ALIGNMENTS[conf.portraitOverlayAlign] and conf.portraitOverlayAlign or "LEFT"
  local direction = PORTRAIT_BORDER_DIRECTIONS[conf.portraitBorderDirection] and conf.portraitBorderDirection or "UP"
  local edgeSoftnessLevel = floor((Num(conf.portraitEdgeSoftness, 0) / 2) + 0.5)
  if edgeSoftnessLevel < 0 then edgeSoftnessLevel = 0 elseif edgeSoftnessLevel > 15 then edgeSoftnessLevel = 15 end
  if shape == "BLIZZARD" or borderStyle ~= "NONE" then edgeSoftnessLevel = 0 end
  local portrait = {
    enabled = mode ~= "OFF",
    side = mode == "RIGHT" and "RIGHT" or "LEFT",
    render = conf.portraitRender == "CLASS" and "CLASS" or "2D",
    classStyle = PortraitClassStyle(conf.portraitClassStyle),
    castSpellIcon = conf.portraitCastSpellIcon == true,
    shape = shape,
    size = size,
    sizeMode = sizeMode,
    width = width,
    height = height,
    x = Num(conf.portraitOffsetX, 0),
    y = Num(conf.portraitOffsetY, 0),
    placement = placement,
    point = point,
    relPoint = relPoint,
    levelOffset = PortraitLevel(conf.portraitLevelOffset),
    overlayAlign = overlayAlign,
    alpha = Clamp01(Num(conf.portraitAlpha, 100) / 100, 1),
    edgeSoftnessLevel = edgeSoftnessLevel,
    border = {
      style = borderStyle,
      thickness = math.max(1, Num(conf.portraitBorderThickness, 2)),
      fill = conf.portraitFillBorder == true,
      art = conf.portraitBorderArt == "RELIEF" and "RELIEF" or "FLAT",
      direction = direction,
      r = Num(conf.portraitBorderColorR, 1),
      g = Num(conf.portraitBorderColorG, 1),
      b = Num(conf.portraitBorderColorB, 1),
      a = Num(conf.portraitBorderColorA, 1),
    },
    bg = {
      enabled = conf.portraitBgEnabled == true,
      r = Num(conf.portraitBgColorR, 0.05),
      g = Num(conf.portraitBgColorG, 0.05),
      b = Num(conf.portraitBgColorB, 0.05),
      a = Num(conf.portraitBgColorA, 0.85),
    },
  }
  CompilePortraitTexCoords(portrait, conf.portraitZoom, width, height, conf.portraitPanX, conf.portraitPanY)
  return portrait
end

--- Single writer for every colour-domain power field. CompileSpecUncached and
--- RefreshColorDomain both go through this, so the cheap in-place DIRTY_COLOR
--- lane can never leave a power field stale against a full recompile.
local function FillPowerVisualDomain(power, conf, general, texture, bgTexture)
  local visual = ResolvePowerVisual(conf)
  -- The Bars page owns shared power art. Resolve it once in the cached group
  -- spec; an empty/invalid key preserves the scope's effective Health texture.
  -- Runtime power events therefore only consume a finished path.
  local bars = _G.MSUF_DB and _G.MSUF_DB.bars
  power.texture = ResolveStatusbarTextureKey(bars and bars.powerBarTexture, texture)
  power.backgroundTexture = ResolveStatusbarTextureKey(bars and bars.powerBarBgTexture, bgTexture)
  power.background = CompileBarBackground(conf)
  power.backgroundMatchHealth = visual.backgroundMatchHealth
  power.mode = visual.mode
  power.r, power.g, power.b = visual.r, visual.g, visual.b
  power.lossR, power.lossG, power.lossB = visual.lossR, visual.lossG, visual.lossB
  power.colors = CompilePowerColorOverrides(power.colors)
  power.barGradient = ResolveBarGradient(conf, general, "enablePowerGradient")
  -- Mirrors CompileUnitPower: the power bar follows the health fill direction.
  power.reverse = conf.reverseFill == true
  CompilePowerBorder(power, conf, general)
  return power
end

--- Embed/detach geometry, mirroring the unit compiler. This is deliberately not
--- part of the colour domain: it changes layout, so it only recompiles on the
--- geometry path where the header can re-lay out outside combat.
local function FillPowerGeometry(power, conf, frameWidth)
  power.embed = conf.embedPowerBarIntoHealth ~= false
  power.detached = conf.powerBarDetached == true
  power.detachedX = Num(conf.detachedPowerBarOffsetX, 0)
  power.detachedY = Num(conf.detachedPowerBarOffsetY, -4)
  -- 0 is the group default for "never configured": fall back to the frame width
  -- and leave detachedWidthExplicit nil so nothing treats it as a chosen value.
  local width = Num(conf.detachedPowerBarWidth, 0)
  power.detachedWidthExplicit = width > 0 and width or nil
  power.detachedWidth = width > 0 and width or Num(frameWidth, 80)
  power.detachedHeight = Num(conf.detachedPowerBarHeight, 6)
  power.detachedAnchorMode = "CENTER"
  power.detachedLevel = Layer(conf.detachedPowerBarFrameLevelOffset, 6)
  power.textOnDetached = conf.detachedPowerBarTextOnBar == true
  -- Class Resource sync/anchor and the ROUND/CRYSTAL/ORB shapes are Player-only
  -- on the unit page; group members get the same plain bar every other unit does.
  power.shape = "BAR"
  power.detachedSyncClass = false
  power.detachedAnchorClass = false
  return power
end

local function ReplaceTableContents(dst, src)
  dst = type(dst) == "table" and dst or {}
  wipe(dst)
  if type(src) == "table" then
    for key, value in pairs(src) do
      dst[key] = value
    end
  end
  return dst
end

local function CompileTextSpec(kind, conf, general, baselineOffset, nameTextOptions)
  local healthLeft, healthCenter, healthRight = TextSlots(conf)
  local hpX = Num(conf.hpOffsetX, 0)
  local hpY = Num(conf.hpOffsetY, 0) + baselineOffset
  local powerX = Num(conf.powerOffsetX, 0)
  local powerY = Num(conf.powerOffsetY, 0) + baselineOffset
  local hpFontSize = Num(conf.hpFontSize, 10)
  local powerFontSize = Num(conf.powerFontSize, 9)
  return {
    anchorToBars = true,
    nameAnchorToFrame = conf._msufLegacyNameAnchorToFrame == true,
    nameLegacyTruncation = conf._msufLegacyNameAnchorToFrame == true,
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
    healthColorByClass = nameTextOptions.healthColorByClass == true,
    healthLeft = healthLeft,
    healthCenter = healthCenter,
    healthRight = healthRight,
    healthLeftFontSize = ResolveTextSlotFontSize(conf, "hpTextLeftFontSize", hpFontSize),
    healthCenterFontSize = ResolveTextSlotFontSize(conf, "hpTextCenterFontSize", hpFontSize),
    healthRightFontSize = ResolveTextSlotFontSize(conf, "hpTextRightFontSize", hpFontSize),
    healthLeftHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextLeftHidePercentSymbol"),
    healthCenterHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextCenterHidePercentSymbol"),
    healthRightHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextRightHidePercentSymbol"),
    healthDelimiter = conf.textDelimiter or " / ",
    healthPercentDecimals = (conf.healthTextDecimals == true or conf.hpTextDecimals == true) and 1 or 0,
    healthShortNumbers = conf.hpFullValueShort ~= false,
    healthAbsorbIcon = conf.hpAbsorbIcon == true,
    healthLeftAbsorbIcon = conf.hpTextLeftAbsorbIcon == nil and conf.hpAbsorbIcon == true or conf.hpTextLeftAbsorbIcon == true,
    healthCenterAbsorbIcon = conf.hpTextCenterAbsorbIcon == nil and conf.hpAbsorbIcon == true or conf.hpTextCenterAbsorbIcon == true,
    healthRightAbsorbIcon = conf.hpTextRightAbsorbIcon == nil and conf.hpAbsorbIcon == true or conf.hpTextRightAbsorbIcon == true,
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
    powerLeftFontSize = ResolveTextSlotFontSize(conf, "powerTextLeftFontSize", powerFontSize),
    powerCenterFontSize = ResolveTextSlotFontSize(conf, "powerTextCenterFontSize", powerFontSize),
    powerRightFontSize = ResolveTextSlotFontSize(conf, "powerTextRightFontSize", powerFontSize),
    powerLeftHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextLeftHidePercentSymbol"),
    powerCenterHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextCenterHidePercentSymbol"),
    powerRightHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextRightHidePercentSymbol"),
    powerDelimiter = conf.powerTextDelimiter or " / ",
    powerLayer = Layer(conf.powerTextLayer, 2),
    powerLeftX = powerX + Num(conf.powerTextLeftOffsetX, 0),
    powerLeftY = powerY + Num(conf.powerTextLeftOffsetY, 0),
    powerCenterX = powerX + Num(conf.powerTextCenterOffsetX, 0),
    powerCenterY = powerY + Num(conf.powerTextCenterOffsetY, 0),
    powerRightX = powerX + Num(conf.powerTextRightOffsetX, 0),
    powerRightY = powerY + Num(conf.powerTextRightOffsetY, 0),
    powerColorByType = ResolvePowerTextColorByType(conf, general),
    shortNumbers = true,
  }
end

local function CompileBorderSpec(kind, conf, general)
  local dispelBorderEnabled = GF.GetHighlightVal and GF.GetHighlightVal(kind, "hlDispelEnabled")
  if dispelBorderEnabled == nil then
    dispelBorderEnabled = conf.dispelEnabled == true
  end
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
  local borderThickness = GF.GetBarOutlineThickness and GF.GetBarOutlineThickness(kind) or Num(conf.borderSize, 1)
  local bars = _G.MSUF_DB and _G.MSUF_DB.bars or nil
  local borderStrata = NormalizeFrameOutlineStrata(conf.hlOverride == true and conf.barOutlineStrata ~= nil and conf.barOutlineStrata or (bars and bars.barOutlineStrata))
  local borderLayer = Layer(conf.hlOverride == true and conf.barOutlineLayer ~= nil and conf.barOutlineLayer or (bars and bars.barOutlineLayer), 0)
  -- Optional typed outline media, same scope rails as thickness/layer. True
  -- borders use edgeFile geometry; textures use the historic stretched edges.
  local borderTextureMode, borderTextureKeyResolved, borderTexture
  local borderTextureKey = conf.hlOverride == true and conf.barOutlineTexture ~= nil and conf.barOutlineTexture or (bars and bars.barOutlineTexture)
  local styles = MSUF.BorderStyles or _G.MSUF_BorderStyles
  if type(borderTextureKey) == "string" and borderTextureKey ~= ""
    and styles and type(styles.ResolveFrame) == "function" then
    borderTextureMode, borderTextureKeyResolved, borderTexture = styles.ResolveFrame(borderTextureKey)
  end
  return {
    enabled = conf.borderEnabled ~= false,
    thickness = borderThickness,
    textureKey = borderTextureKeyResolved,
    texture = borderTexture,
    textureMode = borderTextureMode,
    layer = borderLayer,
    strata = borderStrata,
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
GF._compiledSpecRevision = GF._compiledSpecRevision or 1
local compiledSpecRevisionByKind = GF._compiledSpecRevisionByKind or {}
GF._compiledSpecRevisionByKind = compiledSpecRevisionByKind
local specDomainSerials = GF._compiledSpecDomainSerials or {}
GF._compiledSpecDomainSerials = specDomainSerials

local function NextSpecDomainRevision(key)
  local revision = (tonumber(specDomainSerials[key]) or 0) + 1
  specDomainSerials[key] = revision
  return revision
end

local function BumpCompiledSpecRevision(kind)
  GF._compiledSpecRevision = (GF._compiledSpecRevision or 1) + 1
  if kind then
    compiledSpecRevisionByKind[kind] = (compiledSpecRevisionByKind[kind] or 1) + 1
  end
end

local function CompileSpecUncached(kind, frame, unit, conf)
  kind = kind or "party"
  if not conf then
    if GF.EnsureDB then
      GF.EnsureDB()
    end
    conf = GF.GetConf and GF.GetConf(kind) or {}
  end
  unit = unit or (frame and frame.MSUFUnitKey)

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

  local general = GeneralDB() or {}
  local healthVisual = ResolveHealthVisual(conf)
  local nameTextOptions = ResolveNameTextOptions(kind, conf)
  if type(nameTextOptions.nameColor) == "table" then
    nameTextOptions.nameColor.a = textAlpha
  end
  local textSpec = CompileTextSpec(kind, conf, general, baselineOffset, nameTextOptions)
  local status = CompileStatus(kind, conf)
  local group = CompileGroupVisuals(kind, conf)
  local alpha = CompileAlpha(conf)
  local portrait = CompilePortrait(kind, conf, h)
  local nameFontSize = Num(conf.nameFontSize, 12)

  return {
    _msufGFCompileSerial = GF._compiledSpecSerial or 1,
    _msufTextLayoutRevision = NextSpecDomainRevision("_msufTextLayoutRevision"),
    _msufTextColorRevision = NextSpecDomainRevision("_msufTextColorRevision"),
    _msufPowerVisualRevision = NextSpecDomainRevision("_msufPowerVisualRevision"),
    _msufBorderVisualRevision = NextSpecDomainRevision("_msufBorderVisualRevision"),
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
      lossR = healthVisual.lossR,
      lossG = healthVisual.lossG,
      lossB = healthVisual.lossB,
      texture = texture,
      backgroundTexture = bgTexture,
      background = CompileBarBackground(conf),
      backgroundMatchHealth = healthVisual.backgroundMatchHealth == true,
      backgroundClassColor = healthVisual.backgroundClassColor == true,
      npcClassColorBar = healthVisual.npcClassColorBar == true,
      barGradient = ResolveBarGradient(conf, general, "enableGradient"),
      reverse = conf.reverseFill == true,
      chunked = conf.chunkedFill == true,
      smooth = conf.smoothFill == true and conf.chunkedFill ~= true,
    },
    power = FillPowerGeometry(FillPowerVisualDomain({
      enabled = powerHeight > 0,
      height = powerHeight,
      chunked = conf.powerChunkedFill == true,
      smooth = conf.powerSmoothFill == true and conf.powerChunkedFill ~= true,
    }, conf, general, texture, bgTexture), conf, w),
    text = textSpec,
    tempMaxHealth = CompileTempMaxHealth(kind, conf, texture),
    prediction = CompilePrediction(kind, conf, texture),
    dispel = CompileDispelVisual(kind, conf),
    status = status,
    border = CompileBorderSpec(kind, conf, general),
    alpha = alpha,
    portrait = portrait,
    auras = CompileCoreAuras(kind, conf),
    group = group,
    groupLayout = {
      clickCastEnabled = conf.clickCastEnabled ~= false,
      hideInClientScene = conf.hideInClientScene ~= false,
      hideInHousing = conf.hideInHousing == true,
    },
    cornerIndicators = GF.CompileCornerIndicators and GF.CompileCornerIndicators(conf) or { enabled = false },
    dispelSymbol = CompileDispelSymbol(conf),
    spellIndicators = GF.CompileSpellIndicators and GF.CompileSpellIndicators(conf) or { enabled = false, items = {} },
  }
end

local function BumpSpecDomain(base, key)
  base[key] = NextSpecDomainRevision(key)
  return base[key]
end

local function RefreshFontDomain(kind, base, conf)
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
  local general = GeneralDB() or {}
  local nameTextOptions = ResolveNameTextOptions(kind, conf)
  if type(nameTextOptions.nameColor) == "table" then
    nameTextOptions.nameColor.a = textAlpha
  end

  local nameFontSize = Num(conf.nameFontSize, 12)
  base.font = font
  base.fontFlags = fontFlags
  base.fontSize = nameFontSize
  base.nameFontSize = nameFontSize
  base.healthFontSize = Num(conf.hpFontSize, 10)
  base.powerFontSize = Num(conf.powerFontSize, 9)
  base.fontShadow = fontShadow == true
  base.fontShadowAlpha = fontShadowAlpha
  base.fontShadowX = fontShadowX
  base.fontShadowY = fontShadowY
  base.textColor = ReplaceTableContents(base.textColor, { r = tr or 1, g = tg or 1, b = tb or 1, a = textAlpha })
  base.showName = conf.showName ~= false
  base.showHealthText = conf.showHPText ~= false
  base.showPowerText = IsPowerTextEnabled(kind, conf)
  base.text = ReplaceTableContents(base.text, CompileTextSpec(kind, conf, general, baselineOffset, nameTextOptions))
  -- RaidGroupIndicator is part of the font apply mask, but its font size lives
  -- below status instead of the regular text domain. Keep the shared compiled
  -- table in place so existing frame specs and the menu preview see the new
  -- value without invalidating/recompiling the full group spec on slider drag.
  local raidGroup = base.status and base.status.raidGroup
  if raidGroup then raidGroup.size = Num(conf.groupNumberSize, 10) end
  BumpSpecDomain(base, "_msufTextLayoutRevision")
  BumpSpecDomain(base, "_msufTextColorRevision")
end

local GROUP_COLOR_KEYS = {
  "deadBgEnabled", "deadBgOffline", "hoverHighlightEnabled",
  "deadBgR", "deadBgG", "deadBgB", "deadBgA", "hpBarAlpha", "hpBgAlpha",
  "hoverHighlightR", "hoverHighlightG", "hoverHighlightB",
  "targetR", "targetG", "targetB", "focusR", "focusG", "focusB",
  "dispelOverlayAlpha", "debuffStripeAlpha", "debuffStripeColorR", "debuffStripeColorG", "debuffStripeColorB",
}

local function RefreshColorDomain(kind, base, conf)
  local general = GeneralDB() or {}
  local texture = ResolveTexture(GF.ResolveBarTexture, kind)
  local backgroundTexture = ResolveTexture(GF.ResolveBarBgTexture, kind)
  base.texture = texture
  base.backgroundTexture = backgroundTexture
  base.backgroundAlpha = Num(conf.hpBgAlpha, 0.85)
  local healthVisual = ResolveHealthVisual(conf)
  local health = base.health or {}
  base.health = health
  health.texture = texture
  health.backgroundTexture = backgroundTexture
  health.mode = healthVisual.mode
  health.r, health.g, health.b = healthVisual.r, healthVisual.g, healthVisual.b
  health.lossR, health.lossG, health.lossB = healthVisual.lossR, healthVisual.lossG, healthVisual.lossB
  health.gradientLowR, health.gradientLowG, health.gradientLowB = healthVisual.gradientLowR, healthVisual.gradientLowG, healthVisual.gradientLowB
  health.gradientMidR, health.gradientMidG, health.gradientMidB = healthVisual.gradientMidR, healthVisual.gradientMidG, healthVisual.gradientMidB
  health.gradientHighR, health.gradientHighG, health.gradientHighB = healthVisual.gradientHighR, healthVisual.gradientHighG, healthVisual.gradientHighB
  health.background = CompileBarBackground(conf)
  health.backgroundMatchHealth = healthVisual.backgroundMatchHealth == true
  health.backgroundClassColor = healthVisual.backgroundClassColor == true
  health.npcClassColorBar = healthVisual.npcClassColorBar == true
  health.barGradient = ResolveBarGradient(conf, general, "enableGradient")

  local power = base.power or {}
  base.power = power
  FillPowerVisualDomain(power, conf, general, texture, backgroundTexture)

  local tr, tg, tb = 1, 1, 1
  if GF.ResolveFontColor then
    tr, tg, tb = GF.ResolveFontColor(kind)
  end
  local textAlpha = GF.ResolveFontTextAlpha and GF.ResolveFontTextAlpha(kind) or 1
  base.textColor = ReplaceTableContents(base.textColor, { r = tr or 1, g = tg or 1, b = tb or 1, a = textAlpha })
  local text = base.text or {}
  base.text = text
  local oldHealthColorByHealth = text.healthColorByHealth == true
  local oldHealthColorByClass = text.healthColorByClass == true
  local oldPowerColorByType = text.powerColorByType == true
  local nameTextOptions = ResolveNameTextOptions(kind, conf)
  if type(nameTextOptions.nameColor) == "table" then
    nameTextOptions.nameColor.a = textAlpha
  end
  text.nameClassColor = nameTextOptions.nameClassColor == true
  text.nameNpcColor = nameTextOptions.nameNpcColor == true
  text.nameNpcClassColor = nameTextOptions.nameNpcClassColor == true
  text.nameColor = nameTextOptions.nameColor
  text.healthColorByHealth = nameTextOptions.healthColorByHealth == true
  text.healthColorByClass = nameTextOptions.healthColorByClass == true
  text.powerColorByType = ResolvePowerTextColorByType(conf, general)
  if oldHealthColorByHealth ~= (text.healthColorByHealth == true)
    or oldHealthColorByClass ~= (text.healthColorByClass == true)
    or oldPowerColorByType ~= (text.powerColorByType == true) then
    BumpSpecDomain(base, "_msufTextLayoutRevision")
  end

  base.tempMaxHealth = ReplaceTableContents(base.tempMaxHealth, CompileTempMaxHealth(kind, conf, texture))
  base.prediction = ReplaceTableContents(base.prediction, CompilePrediction(kind, conf, texture))
  base.dispel = ReplaceTableContents(base.dispel, CompileDispelVisual(kind, conf))
  base.border = ReplaceTableContents(base.border, CompileBorderSpec(kind, conf, general))
  base.alpha = ReplaceTableContents(base.alpha, CompileAlpha(conf))

  local nextGroup = CompileGroupVisuals(kind, conf)
  local group = base.group or {}
  base.group = group
  for i = 1, #GROUP_COLOR_KEYS do
    local key = GROUP_COLOR_KEYS[i]
    group[key] = nextGroup[key]
  end

  if GF.CompileCornerIndicators then
    base.cornerIndicators = ReplaceTableContents(base.cornerIndicators, GF.CompileCornerIndicators(conf))
  end
  base.dispelSymbol = ReplaceTableContents(base.dispelSymbol, CompileDispelSymbol(conf))
  BumpSpecDomain(base, "_msufTextColorRevision")
  BumpSpecDomain(base, "_msufPowerVisualRevision")
  BumpSpecDomain(base, "_msufBorderVisualRevision")
end

local function RefreshBorderDomain(kind, base, conf)
  base.border = ReplaceTableContents(base.border, CompileBorderSpec(kind, conf, GeneralDB() or {}))
  BumpSpecDomain(base, "_msufBorderVisualRevision")
end

local function DomainMaskHas(mask, flag)
  mask = tonumber(mask) or 0
  flag = tonumber(flag) or 0
  return flag > 0 and mask % (flag * 2) >= flag
end

--- Refresh color/font/border values in-place. These domains do not change the
--- structural element/event contract, so callers can keep the compiled base and
--- per-frame specs instead of dropping the cache and rebuilding all routing.
function GF.RefreshCompiledSpecDomains(kind, mask)
  if type(mask) ~= "number" then return false end
  local font = DomainMaskHas(mask, GF.DIRTY_FONT)
  local color = DomainMaskHas(mask, GF.DIRTY_COLOR)
  local border = DomainMaskHas(mask, GF.DIRTY_BORDER)
  if not (font or color or border) then return false end

  local remainder = mask
  if font then remainder = remainder - GF.DIRTY_FONT end
  if color then remainder = remainder - GF.DIRTY_COLOR end
  if border then remainder = remainder - GF.DIRTY_BORDER end
  if remainder ~= 0 then return false end

  local function RefreshOne(refreshKind, base)
    if not base then return end
    local conf = base._msufGFConf or (GF.GetConf and GF.GetConf(refreshKind)) or {}
    base._msufGFConf = conf
    if font then RefreshFontDomain(refreshKind, base, conf) end
    if color then
      RefreshColorDomain(refreshKind, base, conf)
    elseif border then
      RefreshBorderDomain(refreshKind, base, conf)
    end
  end

  if kind then
    RefreshOne(kind, compiledSpecCache[kind])
  else
    for refreshKind, base in pairs(compiledSpecCache) do
      RefreshOne(refreshKind, base)
    end
  end
  return true
end

function GF.InvalidateCompiledSpecs(kind)
  BumpCompiledSpecRevision(kind)
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

function GF.GetCompiledSpecRevision(kind)
  kind = kind or "party"
  local base = compiledSpecCache[kind]
  return tostring(GF._compiledSpecRevision or 1)
    .. ":" .. tostring(compiledSpecRevisionByKind[kind] or 1)
    .. ":" .. tostring(GF._compiledSpecSerial or 1)
    .. ":" .. tostring(compiledSpecSerialByKind[kind] or 1)
    .. ":" .. tostring(base and base._msufTextLayoutRevision or 0)
    .. ":" .. tostring(base and base._msufTextColorRevision or 0)
    .. ":" .. tostring(base and base._msufPowerVisualRevision or 0)
    .. ":" .. tostring(base and base._msufBorderVisualRevision or 0)
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

local TEXT_SPEC_ROOT_KEYS = {
  "font", "fontFlags", "fontSize", "nameFontSize", "healthFontSize", "powerFontSize",
  "fontShadow", "fontShadowAlpha", "fontShadowX", "fontShadowY",
  "showName", "showHealthText", "showPowerText", "text",
}

local function PatchFrameSpec(base, kind, frame, unit, conf)
  local spec = frame._msufGFSpec
  if not spec then
    spec = {}
    frame._msufGFSpec = spec
  end
  if frame._msufGFSpecBase ~= base then
    CopyShallow(spec, base)
    frame._msufGFSpecBase = base
    frame._msufGFTextLayoutRevision = base._msufTextLayoutRevision
    frame._msufGFTextColorRevision = base._msufTextColorRevision
    frame._msufGFPowerVisualRevision = base._msufPowerVisualRevision
    frame._msufGFBorderVisualRevision = base._msufBorderVisualRevision
  else
    if frame._msufGFTextLayoutRevision ~= base._msufTextLayoutRevision then
      for i = 1, #TEXT_SPEC_ROOT_KEYS do
        local key = TEXT_SPEC_ROOT_KEYS[i]
        spec[key] = base[key]
      end
      spec._msufTextLayoutRevision = base._msufTextLayoutRevision
      frame._msufGFTextLayoutRevision = base._msufTextLayoutRevision
    end
    if frame._msufGFTextColorRevision ~= base._msufTextColorRevision then
      spec.textColor = base.textColor
      spec.texture = base.texture
      spec.backgroundTexture = base.backgroundTexture
      spec.backgroundAlpha = base.backgroundAlpha
      spec._msufTextColorRevision = base._msufTextColorRevision
      frame._msufGFTextColorRevision = base._msufTextColorRevision
    end
    if frame._msufGFBorderVisualRevision ~= base._msufBorderVisualRevision then
      spec.border = base.border
      spec._msufBorderVisualRevision = base._msufBorderVisualRevision
      frame._msufGFBorderVisualRevision = base._msufBorderVisualRevision
    end
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
  if frame._msufGFPowerSpecBase ~= base.power
    or frame._msufGFPowerVisualRevision ~= base._msufPowerVisualRevision then
    CopyShallow(power, base.power)
    frame._msufGFPowerSpecBase = base.power
    frame._msufGFPowerVisualRevision = base._msufPowerVisualRevision
  end
  power.enabled = powerHeight > 0
  power.height = powerHeight
  spec.power = power
  -- Power text is part of the same role-gated runtime ownership as the bar.
  -- A DPS frame with its power bar disabled must not retain PowerText events.
  spec.showPowerText = powerHeight > 0 and base.showPowerText == true

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
  unit = unit or (frame and frame.MSUFUnitKey)
  if frame then
    return PatchFrameSpec(base, kind, frame, unit, conf)
  end
  return base
end

function GF.GetCompiledSpec(kind, frame, unit)
  return GF.CompileSpec(kind, frame, unit)
end
