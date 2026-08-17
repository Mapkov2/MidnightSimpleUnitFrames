local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

--- UnitFrames/Engine/MSUF_UF_Config.lua
---
--- Cold config compiler for unit frames. It reads MSUF_DB, resolves legacy
--- aliases/defaults, and produces per-unit specs consumed by Factory, Core, and
--- hot Dispatch code. Keep DB walking and schema interpretation here; runtime
--- event handlers should read compiled frame.MSUFSpec fields instead.

local UF = MSUF.UF
UF.Config = UF.Config or {}
local Config = UF.Config

local type = type
local tonumber = tonumber
local tostring = tostring
local pairs = pairs
local byte, sub = string.byte, string.sub
local max, min, abs, floor = math.max, math.min, math.abs, math.floor
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local IsInInstance = _G.IsInInstance
local GetInstanceInfo = _G.GetInstanceInfo
local wipe = _G.wipe or table.wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
local Clamp01 = UF.Clamp01
local Number = UF.NumberWithFallback
local NormalizeDispelDetectTrigger = UF.NormalizeDispelDetectTrigger
local NormalizeDispelOverlayTrigger = UF.NormalizeDispelOverlayTrigger
local NormalizeDispelOverlayStyle = UF.NormalizeDispelOverlayStyle
local NormalizeRangeFadeLayerMode = UF.NormalizeRangeFadeLayerMode
local NormalizeAbsorbTestScope = UF.NormalizeAbsorbTestScope
local AbsorbTextureTestEnabledForScope = UF.AbsorbTextureTestEnabledForScope
local ScopedValue = UF.ConfigScopedValue
local CompileBorderPriority = UF.CompileBorderPriority
local ResolveBarGradient = UF.ResolveBarGradient
local FillPredictionColors = UF.FillPredictionColors

local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CDM_WIDTH_FRAMES = {
  cooldown = "EssentialCooldownViewer",
  utility = "UtilityCooldownViewer",
  tracked_buffs = "BuffIconCooldownViewer",
}
local COOLDOWN_VIEWER_FRAMES = {
  EssentialCooldownViewer = true,
  UtilityCooldownViewer = true,
  BuffIconCooldownViewer = true,
}
local LEGACY_UNIT_NAME_ANCHORS = {
  LEFT = "TOPLEFT",
  CENTER = "TOP",
  RIGHT = "TOPRIGHT",
}
local function NormalizeUnitNameAnchor(value)
  value = tostring(value or "TOPLEFT"):upper()
  return LEGACY_UNIT_NAME_ANCHORS[value] or value
end
local ECV_ANCHORS = {
  player = { "RIGHT", "LEFT", -20, 0 },
  target = { "LEFT", "RIGHT", 20, 0 },
  focus = { "TOP", "LEFT", 0, 0 },
  targettarget = { "TOP", "RIGHT", 0, -40 },
  focustarget = { "TOP", "RIGHT", 0, 40 },
}

local DEFAULTS = {
  player = { width = 275, height = 40, x = -256, y = -180, showName = false, showPower = true },
  target = { width = 275, height = 40, x = 320, y = -180, showName = true, showPower = true },
  focus = { width = 180, height = 30, x = -260, y = -300, showName = true, showPower = false },
  targettarget = { width = 180, height = 30, x = 220, y = -300, showName = false, showPower = false },
  focustarget = { width = 180, height = 30, x = 260, y = 180, showName = true, showPower = false },
  pet = { width = 220, height = 30, x = -275, y = -250, showName = true, showPower = true },
  boss = { width = 180, height = 30, x = 500, y = 180, showName = true, showPower = false },
}

local POWER_KEYS = {
  player = "showPlayerPowerBar",
  target = "showTargetPowerBar",
  focus = "showFocusPowerBar",
  boss = "showBossPowerBar",
}

local function IsCooldownViewerFrameName(frameName)
  return COOLDOWN_VIEWER_FRAMES[frameName] == true
end

local CASTBAR_KEYS = {
  player = "enablePlayerCastbar",
  target = "enableTargetCastbar",
  focus = "enableFocusCastbar",
  boss = "enableBossCastbar",
}

local RANGE_KEYS = {
  target = true,
  targettarget = true,
  focus = true,
  focustarget = true,
  pet = true,
  boss = true,
}

local CLASS_TOKENS = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
  "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local playerClassToken
local function PlayerClassToken()
  if playerClassToken == nil and type(_G.UnitClass) == "function" then
    local _, token = _G.UnitClass("player")
    if type(token) == "string" and token ~= "" then playerClassToken = token end
  end
  return playerClassToken
end

local function ResolveClassColor(db, token)
  local classColors = type(db.classColors) == "table" and db.classColors or nil
  local src = classColors and token and classColors[token]
  if type(src) == "table" and tonumber(src.r or src[1]) and tonumber(src.g or src[2]) and tonumber(src.b or src[3]) then
    return Number(src.r or src[1], 1), Number(src.g or src[2], 1), Number(src.b or src[3], 1)
  end
  local palette = MSUF.MSUF_FONT_COLORS or _G.MSUF_FONT_COLORS
  if type(src) == "string" and palette and palette[src] then
    local color = palette[src]
    return Number(color.r or color[1], 1), Number(color.g or color[2], 1), Number(color.b or color[3], 1)
  end
  local color = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
  if color then return color.r or 0.12, color.g or 0.62, color.b or 0.95 end
  return 0.12, 0.62, 0.95
end

local NPC_COLOR_DEFAULTS = {
  friendly = { 0, 1, 0 },
  neutral = { 1, 1, 0 },
  enemy = { 0.85, 0.10, 0.10 },
  dead = { 0.4, 0.4, 0.4 },
  npcBoss = { 0.74, 0.11, 0 },
  npcMiniboss = { 0.56, 0, 0.74 },
  npcCaster = { 0, 0.45, 0.74 },
  npcMelee = { 0.99, 0.99, 0.99 },
  npcRegular = { 0.70, 0.56, 0.33 },
}

local dbInitialized = false

--- Config can be asked for specs before every module has finished loading.
--- EnsureDB centralizes that bootstrap without making the hot dispatch layer
--- know about profile initialization.
local function EnsureDB()
  if not dbInitialized or type(_G.MSUF_DB) ~= "table" then
    if type(_G.MSUF_InitProfiles) == "function" then
      _G.MSUF_InitProfiles()
    end
    if type(_G.MSUF_EnsureDB) == "function" then
      _G.MSUF_EnsureDB()
    end
    dbInitialized = true
  end
  if type(_G.MSUF_DB) ~= "table" then
    ExportPublic("MSUF_DB", {})
  end
  return _G.MSUF_DB
end

local function Bool(value, fallback)
    if value == nil then
        return fallback
    end
    return value == true
end

local function OutlineModeEnabled(value, fallback)
  if value == nil then value = fallback end
  if value == true or value == false then return value end
  value = tonumber(value)
  if value == nil then return fallback == true end
  return value == 1
end

local function NormalizeFrameOutlineStrata(value)
  local normalize = _G.MSUF_NormalizeFrameStrata
  if type(normalize) == "function" then return normalize(value, "AUTO") end
  if value == nil or value == "" then return "AUTO" end
  value = tostring(value):upper()
  local rank = _G.MSUF_FRAME_STRATA_RANK
  return rank and rank[value] and value or "AUTO"
end

local function CopyColor(dst, r, g, b, a)
  dst.r = Number(r, dst.r or 1)
  dst.g = Number(g, dst.g or 1)
  dst.b = Number(b, dst.b or 1)
  dst.a = Number(a, dst.a or 1)
end

local function CopyConfigColor(src)
  if type(src) ~= "table" then
    return nil
  end
  local r = tonumber(src.r or src[1])
  local g = tonumber(src.g or src[2])
  local b = tonumber(src.b or src[3])
  local a = src.a
  if a == nil then a = src[4] end
  a = tonumber(a)
  if r == nil or g == nil or b == nil then
    return nil
  end
  return { r = r, g = g, b = b, a = a or 1 }
end

local function ApplyNpcTypeFlags(dst, general, colorKey)
  dst.npcColorMode = general.npcColorMode == "type" and "type" or "reaction"
  dst[colorKey] = general[colorKey] ~= false
  dst.npcTypeTarget = general.npcTypeTarget ~= false
  dst.npcTypeFocus = general.npcTypeFocus ~= false
  dst.npcTypeBoss = general.npcTypeBoss ~= false
  dst.npcTypeToT = general.npcTypeToT ~= false
end

local function NPCTypeTextColorEnabled(text)
  return text and text.npcColorMode == "type" and text.npcTypeColorText ~= false
end

local function CopyPowerColorOverrides(dst, src, onlyMissing)
  if type(src) ~= "table" then
    return
  end
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

local DIRECT_TEXT_LAYOUTS = {
  "Name", "HealthLeft", "HealthCenter", "HealthRight",
  "PowerLeft", "PowerCenter", "PowerRight",
}

local function CopyDirectTextLayout(text, conf)
  for i = 1, #DIRECT_TEXT_LAYOUTS do
    local suffix = DIRECT_TEXT_LAYOUTS[i]
    local key = "direct" .. suffix
    text[key .. "Point"] = conf[key .. "Point"]
    text[key .. "RelativePoint"] = conf[key .. "RelativePoint"]
    text[key .. "X"] = Number(conf[key .. "OffsetX"], 0)
    text[key .. "Y"] = Number(conf[key .. "OffsetY"], 0)
    text[key .. "Color"] = CopyConfigColor(conf[key .. "Color"])
  end
end

local function ClearDirectTextLayout(text)
  for i = 1, #DIRECT_TEXT_LAYOUTS do
    local key = "direct" .. DIRECT_TEXT_LAYOUTS[i]
    text[key .. "Point"] = nil
    text[key .. "RelativePoint"] = nil
    text[key .. "X"] = nil
    text[key .. "Y"] = nil
    text[key .. "Color"] = nil
  end
end

local TEXT_SIDES = { "Left", "Center", "Right" }

local function ApplySideTextOffsets(text, outPrefix, confPrefix, legacyPrefix, baseX, baseY, conf, general)
  for i = 1, #TEXT_SIDES do
    local side = TEXT_SIDES[i]
    local outKey = outPrefix .. side
    text[outKey .. "X"] = baseX + Number(conf[confPrefix .. side .. "OffsetX"] or conf[legacyPrefix .. side .. "OffsetX"]
      or general[confPrefix .. side .. "OffsetX"] or general[legacyPrefix .. side .. "OffsetX"], 0)
    text[outKey .. "Y"] = baseY + Number(conf[confPrefix .. side .. "OffsetY"] or conf[legacyPrefix .. side .. "OffsetY"]
      or general[confPrefix .. side .. "OffsetY"] or general[legacyPrefix .. side .. "OffsetY"], 0)
  end
end

local function ResolveTextSlotFontSize(conf, general, key, fallback)
  local value = Number((conf and conf[key]) or (general and general[key]), fallback)
  if value <= 0 then return fallback end
  return value
end

local function ResolveBarMode(general)
  local mode = general and general.barMode
  if type(mode) == "string" then
    mode = mode:lower()
  end
  if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
    if general and general.useClassColors == true then
      mode = "class"
    elseif general and general.darkMode == true then
      mode = "dark"
    else
      mode = "dark"
    end
  end
  if mode == "gradient" and general and general.enableHealthGradient == false then
    mode = "class"
  end
  return mode
end

local HEALTH_MODE_ALIASES = {
  CLASS = "class", class = "class",
  GRADIENT = "gradient", gradient = "gradient",
  DARK = "dark", dark = "dark",
  UNIFIED = "unified", unified = "unified",
}

local function ResolveUnitBarMode(conf, general)
  local mode = conf and conf.healthColorMode
  if type(mode) == "string" then
    mode = HEALTH_MODE_ALIASES[mode] or HEALTH_MODE_ALIASES[mode:lower()]
  end
  return mode or ResolveBarMode(general)
end

local function ResolvePowerMode(general)
  local mode = general and (general.powerColorMode or general.powerBarColorMode)
  if type(mode) == "string" then
    mode = mode:lower()
  end
  if mode == "class" or mode == "static" or mode == "unified" or mode == "dark" then
    return mode
  end
  return "power"
end

local function ResolveDarkColor(general, dst)
  local gray = Number(general and (general.darkBarGray or general.darkBgBrightness), 0.07)
  if gray > 1 then
    gray = gray / 100
  end
  CopyColor(dst, general and general.darkBarR or gray, general and general.darkBarG or gray, general and general.darkBarB or gray, 1)
end

local function ResolveTextColor(general, dst)
  dst = dst or {}
  local getColor = _G.MSUF_GetConfiguredFontColor or MSUF.MSUF_GetConfiguredFontColor
  if type(getColor) == "function" then
    local r, g, b = getColor()
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      CopyColor(dst, r, g, b, 1)
      return dst
    end
  end
  if general and general.useCustomFontColor == true
    and type(general.fontColorCustomR) == "number"
    and type(general.fontColorCustomG) == "number"
    and type(general.fontColorCustomB) == "number" then
    CopyColor(dst, general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB, 1)
    return dst
  end
  local palette = MSUF.MSUF_FONT_COLORS or _G.MSUF_FONT_COLORS
  local key = general and general.fontColor
  if type(key) == "string" and palette then
    local c = palette[key:lower()]
    if c then
      CopyColor(dst, c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4] or 1)
      return dst
    end
  end
  CopyColor(dst, 1, 1, 1, 1)
  return dst
end

local function ResolveBgAlpha(general, bars, conf)
  local perUnit = conf and conf.hpBgAlpha
  if type(perUnit) == "number" then
    return Clamp01(perUnit, 0.85)
  end
  local alpha = bars and bars.barBackgroundAlpha
  if type(alpha) == "number" then
    return Clamp01(alpha / 100, 0.9)
  end
  return Clamp01(general and general.barBackgroundAlpha, 0.9)
end

local function ResolvePowerBgAlpha(general, bars, conf)
  local perUnit = conf and conf.powerBarBgAlpha
  if type(perUnit) == "number" then
    return Clamp01(perUnit, 0.85)
  end
  return ResolveBgAlpha(general, bars, conf)
end

local function DarkTint(general, r, g, b)
  if general and general.darkMode == true and general.darkBgCustomColor ~= true then
    local brightness = Clamp01(general.darkBgBrightness, 0.25)
    return (r or 0) * brightness, (g or 0) * brightness, (b or 0) * brightness
  end
  return r or 0, g or 0, b or 0
end

local function ResolveHealthBackground(general, bars, health, dst, conf)
  dst = dst or {}
  local r, g, b, tintAlpha
  local getBg = _G.MSUF_GetBarBackgroundTintRGBA
  if type(getBg) == "function" then
    r, g, b, tintAlpha = getBg()
  else
    r, g, b = DarkTint(general, Number(general and general.classBarBgR, 0), Number(general and general.classBarBgG, 0), Number(general and general.classBarBgB, 0))
    tintAlpha = Number(general and general.classBarBgA, 1)
  end
  if general and general.barBgMatchHPColor == true and health then
    r, g, b = DarkTint(general, health.r, health.g, health.b)
  end
  -- Color opacity is an explicit user-controlled multiplier whose neutral
  -- default is 1.0. This replaces the old hidden 0.9 tint alpha, so setting
  -- both the tint and per-unit Background controls to 100% is truly opaque.
  CopyColor(dst, r, g, b, ResolveBgAlpha(general, bars, conf) * Clamp01(tintAlpha, 1))
  return dst
end

local function ResolvePowerBackground(general, bars, health, dst, conf)
  dst = dst or {}
  local r, g, b, tintAlpha
  local getBg = _G.MSUF_GetPowerBarBackgroundTintRGBA
  if type(getBg) == "function" then
    r, g, b, tintAlpha = getBg()
  else
    r, g, b = DarkTint(general, Number(general and general.powerBarBgColorR, Number(general and general.classBarBgR, 0)), Number(general and general.powerBarBgColorG, Number(general and general.classBarBgG, 0)), Number(general and general.powerBarBgColorB, Number(general and general.classBarBgB, 0)))
    tintAlpha = Number(general and general.powerBarBgColorA, Number(general and general.classBarBgA, 1))
  end
  if (general and general.powerBarBgMatchBarColor == true) or (bars and bars.powerBarBgMatchBarColor == true) then
    r, g, b = DarkTint(general, health and health.r or r, health and health.g or g, health and health.b or b)
  end
  CopyColor(dst, r, g, b, ResolvePowerBgAlpha(general, bars, conf) * Clamp01(tintAlpha, 1))
  return dst
end

local NormalizePredictionTestCategory = UF.NormalizePredictionTestCategory or function(category) return category end
local function PredictionTestModesAny(modes)
  if type(modes) ~= "table" then return false end
  for _, bucket in pairs(modes) do
    if type(bucket) == "table" and (bucket.heal == true or bucket.absorb == true
      or bucket.healAbsorb == true or bucket.tempMaxHealth == true) then
      return true
    end
  end
  return false
end

local SetAbsorbTextureTestMode = _G.MSUF_SetAbsorbTextureTestMode or function(enabled, scope, category)
  local normalizedScope = NormalizeAbsorbTestScope(scope)
  local normalizedCategory = NormalizePredictionTestCategory(category)
  local modes = _G.MSUF_PredictionTestModes
  if type(modes) ~= "table" then modes = {} end
  local bucket = modes[normalizedScope]
  if type(bucket) ~= "table" then bucket = {}; modes[normalizedScope] = bucket end
  if normalizedCategory then
    bucket[normalizedCategory] = enabled == true or nil
  else
    bucket.heal = enabled == true or nil
    bucket.absorb = enabled == true or nil
    bucket.healAbsorb = enabled == true or nil
  end
  if not (bucket.heal or bucket.absorb or bucket.healAbsorb or bucket.tempMaxHealth) then modes[normalizedScope] = nil end
  local anyEnabled = PredictionTestModesAny(modes)
  ExportPublic("MSUF_PredictionTestModes", anyEnabled and modes or nil)
  ExportPublic("MSUF_AbsorbTextureTestMode", anyEnabled)
  ExportPublic("MSUF_AbsorbTextureTestScope", enabled and normalizedScope or nil)
end
ExportPublic("MSUF_SetAbsorbTextureTestMode", SetAbsorbTextureTestMode)

local ClearAbsorbTextureTestMode = _G.MSUF_ClearAbsorbTextureTestMode or function()
  ExportPublic("MSUF_PredictionTestModes", nil)
  ExportPublic("MSUF_AbsorbTextureTestMode", false)
  ExportPublic("MSUF_AbsorbTextureTestScope", nil)
end
ExportPublic("MSUF_ClearAbsorbTextureTestMode", ClearAbsorbTextureTestMode)

local ShouldShowAbsorbTextureTest = _G.MSUF_ShouldShowAbsorbTextureTest or function(frame, scope, category)
  local key = scope
    or frame and (frame.configKey or frame.MSUFUnitKey or frame._msufGFKind or frame.unitKey)
    or nil
  return AbsorbTextureTestEnabledForScope(key, category)
end
ExportPublic("MSUF_ShouldShowAbsorbTextureTest", ShouldShowAbsorbTextureTest)

local HEALTH_TEXT_MODE_ALIASES = {
  FULL_ONLY = "CURRENT",
  PERCENT_ONLY = "PERCENT",
  FULL_SLASH_MAX = "CURMAX",
  FULL_PLUS_PERCENT = "CURPERCENT",
  PERCENT_PLUS_FULL = "PERCENTCUR",
}
local POWER_TEXT_MODE_ALIASES = {
  FULL_ONLY = "CURRENT",
  PERCENT_ONLY = "PERCENT",
  FULL_SLASH_MAX = "CURMAX",
  FULL_PLUS_PERCENT = "CURPERCENT",
  PERCENT_PLUS_FULL = "CURPERCENT",
}

local function NormalizeHealthTextMode(mode, fallback)
  return mode == nil and fallback or HEALTH_TEXT_MODE_ALIASES[mode] or mode
end

local function NormalizePowerTextMode(mode, fallback)
  return mode == nil and fallback or POWER_TEXT_MODE_ALIASES[mode] or mode
end

local function PowerTextModeNeedsValueTicks(mode)
  return mode ~= nil and mode ~= "NONE" and mode ~= "MAX"
end

local function ResolveTextSlotHidePercentSymbol(conf, general, key)
  if conf and conf[key] ~= nil then
    return conf[key] == true
  end
  return general and general.hidePercentSymbol == true
end

local function ResolveNameShortening(db, general, conf, unit, text)
  local shorten = db and db.shortenNames == true
  local maxChars = Number(general and general.shortenNameMaxChars, 6)
  local side = tostring(general and general.shortenNameClipSide or "LEFT"):upper()
  local maskPx = Number(general and general.shortenNameFrontMaskPx, 0)
  local dots = general and general.shortenNameShowDots
  dots = dots == nil or dots == true

  if conf and conf.fontOverride == true then
    if conf.shortenNames ~= nil then
      shorten = conf.shortenNames == true
    elseif conf.nameShortenEnabled ~= nil then
      shorten = conf.nameShortenEnabled == true
    end
    maxChars = Number(conf.shortenNameMaxChars or conf.nameMaxChars, maxChars)
    side = tostring(conf.shortenNameClipSide or conf.nameClipSide or side):upper()
    maskPx = Number(conf.shortenNameFrontMaskPx, maskPx)
    if conf.shortenNameShowDots ~= nil then
      dots = conf.shortenNameShowDots == true
    elseif conf.nameNoEllipsis ~= nil then
      dots = conf.nameNoEllipsis ~= true
    end
  end

  if side ~= "RIGHT" then
    side = "LEFT"
  end

  maxChars = floor((tonumber(maxChars) or 6) + 0.5)
  if maxChars < 4 then
    maxChars = 4
  elseif maxChars > 40 then
    maxChars = 40
  end
  maskPx = floor((tonumber(maskPx) or 0) + 0.5)
  if maskPx < 0 then
    maskPx = 0
  elseif maskPx > 80 then
    maskPx = 80
  end

  text.nameShorten = shorten == true
  text.nameShortenMax = maxChars
  text.nameShortenSide = side
  text.nameShortenDots = dots == true
  text.nameShortenMaskPx = maskPx
end

local function ResolveNameColorFlags(general, conf)
  local classColor = general and general.nameClassColor == true
  local npcColor = general and general.npcNameRed == true
  local npcClassColor = general and general.nameNpcClassColor == true
  if conf and conf.fontOverride == true then
    -- A CUSTOM name color is a full replacement, resolved exactly as group
    -- frames resolve theirs: the runtime's nameColor override short-circuits
    -- every class/NPC rule, so no flag may survive next to it. Components are
    -- returned loose; the caller owns the reusable color table.
    if conf.nameColorMode == "CUSTOM" then
      return false, false, false,
        Clamp01(conf.nameColorR, 1), Clamp01(conf.nameColorG, 1), Clamp01(conf.nameColorB, 1)
    end
    if conf.nameClassColor ~= nil then
      classColor = conf.nameClassColor == true
    end
    if conf.npcNameRed ~= nil then
      npcColor = conf.npcNameRed == true
    end
    if conf.nameNpcClassColor ~= nil then
      npcClassColor = conf.nameNpcClassColor == true
    end
  elseif general and general.nameColorMode == "CUSTOM" then
    -- The shared Fonts scope stores its mode on general. A frame with its own
    -- font override never reaches here, so an explicit per-frame DEFAULT still
    -- beats a shared CUSTOM instead of being overridden by it.
    return false, false, false,
      Clamp01(general.nameColorR, 1), Clamp01(general.nameColorG, 1), Clamp01(general.nameColorB, 1)
  end
  return classColor, npcColor, npcClassColor
end

local function ResolveHealthTextColorMode(general, conf)
  local value = general and general.colorHealthTextByHealth
  if conf and conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then
    value = conf.colorHealthTextByHealth
  end
  if value == "CLASS" then return "CLASS" end
  if value == true or value == "HEALTH" then return "HEALTH" end
  return "DEFAULT"
end

local function ResolvePowerTextColorByType(general, conf)
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

local function Utf8Prefix(value, maxChars)
  value = tostring(value or "")
  maxChars = tonumber(maxChars) or 0
  if value == "" or maxChars <= 0 then
    return ""
  end
  local pos, len, chars = 1, #value, 0
  while pos <= len and chars < maxChars do
    local b = byte(value, pos)
    if not b then
      break
    elseif b < 128 then
      pos = pos + 1
    elseif b < 224 then
      pos = pos + 2
    elseif b < 240 then
      pos = pos + 3
    else
      pos = pos + 4
    end
    chars = chars + 1
  end
  return sub(value, 1, pos - 1)
end

local function ResolveToTInlineSeparator(conf)
  local token = conf and conf.totInlineSeparator
  if token == "__CUSTOM__" then
    token = tostring(conf and conf.totInlineCustomSeparator or ""):gsub("[%c]", " ")
    token = Utf8Prefix(token, 5)
    if token == "" then
      token = " "
    end
  elseif token == nil then
    token = "|"
  else
    token = tostring(token)
  end
  if token == "" then
    token = " "
  end
  return " " .. token .. " "
end

local function ResolveToTInlineColorMode(value)
  value = tostring(value or "AUTO"):upper()
  if value == "TOT_NAME" or value == "TARGET_NAME" or value == "NPC" or value == "DEFAULT" then
    return value
  end
  return "AUTO"
end

local function ResolveToTInline(db, general, unit, targetText)
  if unit ~= "target" then
    targetText.inlineToT = nil
    return
  end

  local tot = type(db and db.targettarget) == "table" and db.targettarget or type(db and db.tot) == "table" and db.tot or nil
  if not (tot and tot.showToTInTargetName == true) then
    targetText.inlineToT = nil
    return
  end

  local inline = targetText.inlineToT
  if type(inline) ~= "table" then
    inline = {}
    targetText.inlineToT = inline
  end
  ResolveNameShortening(db, general, tot, "targettarget", inline)
  inline.enabled = true
  inline.unit = "targettarget"
  inline.separator = ResolveToTInlineSeparator(tot)
  inline.colorMode = ResolveToTInlineColorMode(tot.totInlineColorMode)
  local targetNpcTypeColor = NPCTypeTextColorEnabled(targetText)
  inline.targetNameClassColor = targetText.nameClassColor == true
  inline.targetNameNpcColor = targetText.nameNpcColor == true or targetNpcTypeColor
  inline.targetNameNpcClassColor = targetText.nameNpcClassColor == true
  inline.totNameClassColor, inline.totNameNpcColor, inline.totNameNpcClassColor = ResolveNameColorFlags(general, tot)
  inline.totNameNpcColor = inline.totNameNpcColor == true or targetNpcTypeColor
end

local function NormalizePortraitMode(conf)
  local mode = conf and conf.portraitMode
  if mode == "LEFT" or mode == "RIGHT" then
    return mode
  end
  if conf and conf.showPortrait == true then
    return "LEFT"
  end
  return "OFF"
end

local function NormalizePortraitRender(mode)
  return mode == "CLASS" and "CLASS" or "2D"
end

local function NormalizePortraitClassStyle(value)
  local fn = _G.MSUF_NormalizePortraitClassStyleValue
  if type(fn) == "function" then
    return fn(value)
  end
  local PM = MSUF and MSUF.PortraitMedia
  if PM and type(PM.NormalizeClassPack) == "function" then
    return PM.NormalizeClassPack(value)
  end
  if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then
    return value
  end
  return "BLIZZARD"
end

--- BLIZZARD is the stock player-frame dressing: the client's own circular
--- portrait mask plus the untinted gold ring cut from Blizzard's frame atlas.
local function NormalizePortraitShape(shape)
  if shape == "CIRCLE" or shape == "ROUNDED" or shape == "DIAMOND" or shape == "BLIZZARD" then
    return shape
  end
  return "SQUARE"
end

local function NormalizePortraitBorder(style)
  if style == "SOLID" or style == "CLASS_COLOR" or style == "REACTION" or style == "CUSTOM" then
    return style
  end
  return "NONE"
end

--- Border renderer: FLAT is the geometric edge/ring pair, RELIEF swaps in the
--- beveled ring art. The art is greyscale, so the border colour still tints it.
local function NormalizePortraitBorderArt(value)
  return value == "RELIEF" and "RELIEF" or "FLAT"
end

local PORTRAIT_BORDER_DIRECTIONS = { UP = true, RIGHT = true, DOWN = true, LEFT = true }
local function NormalizePortraitBorderDirection(value)
  return PORTRAIT_BORDER_DIRECTIONS[value] == true and value or "UP"
end

local function NormalizePortraitZoom(value)
  value = Number(value, 100)
  if value > 1 and value <= 2 then
    value = value * 100
  end
  if value < 100 then
    return 100
  elseif value > 200 then
    return 200
  end
  return value
end

local PORTRAIT_PLACEMENTS = { ATTACHED = true, DETACHED = true, OVERLAY = true }
local PORTRAIT_ANCHOR_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true,
  LEFT = true, CENTER = true, RIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local PORTRAIT_OVERLAY_ALIGNMENTS = { LEFT = true, CENTER = true, RIGHT = true, FULL = true }

local function NormalizePortraitPlacement(value)
  return PORTRAIT_PLACEMENTS[value] == true and value or "ATTACHED"
end

local function NormalizePortraitAnchorPoint(value, fallback)
  return PORTRAIT_ANCHOR_POINTS[value] == true and value or fallback
end

local function NormalizePortraitOverlayAlign(value)
  return PORTRAIT_OVERLAY_ALIGNMENTS[value] == true and value or "LEFT"
end

--- Portrait layer rides the shared 0..30 unit-frame scale, measured from the
--- frame itself. The health bar sits at frame+1, so layer 0 parks an overlay
--- portrait behind the bars while the default 7 reproduces the pre-6.0 stacking.
local function NormalizePortraitLevelOffset(value, fallback)
  value = math.floor(Number(value, fallback or 7) + 0.5)
  if value < 0 then
    return 0
  elseif value > 30 then
    return 30
  end
  return value
end

local function NormalizePortraitPan(value)
  value = Number(value, 0)
  if value < -100 then
    return -100
  elseif value > 100 then
    return 100
  end
  return value
end

--- 2D portrait art is square. Baking zoom, the holder aspect ratio and the pan
--- offset into the tex coords here keeps the whole thing free at event time --
--- the element only ever replays four numbers it never has to recompute.
--- A square holder at zoom 100 with no pan reproduces the classic 0.08..0.92.
--- The BLIZZARD shape starts from the full texture instead: the stock player
--- frame renders its circular portrait without any crop, so zoom 100 must be
--- pixel-identical to Blizzard before the zoom/pan sliders take over.
local function CompilePortraitTexCoords(p, zoom, width, height, panX, panY)
  local baseSpan = p.shape == "BLIZZARD" and 1 or 0.84
  local span = baseSpan * (100 / zoom)
  local spanX, spanY = span, span
  width = Number(width, 0)
  height = Number(height, 0)
  if width > 0 and height > 0 and width ~= height then
    if width > height then
      spanY = span * (height / width)
    else
      spanX = span * (width / height)
    end
  end
  local slackX = (1 - spanX) * 0.5
  local slackY = (1 - spanY) * 0.5
  local centerX = 0.5 + (Number(panX, 0) / 100) * slackX
  local centerY = 0.5 - (Number(panY, 0) / 100) * slackY
  p.zoom = zoom
  p.texL = centerX - spanX * 0.5
  p.texR = centerX + spanX * 0.5
  p.texT = centerY - spanY * 0.5
  p.texB = centerY + spanY * 0.5
end

local function CompileRange(out, conf, general, key)
  local range = out.range or {}
  out.range = range
  local supported = RANGE_KEYS[key] == true
  range.enabled = supported and conf.rangeFadeEnabled ~= false
  range.active = out.enabled ~= false and range.enabled == true
  range.alpha = Clamp01(conf.rangeFadeAlpha or general.rangeFadeAlpha, 0.4)
  range.layerMode = NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode or general.rangeFadeLayerMode)
end

local function CompileAlpha(out, conf, general, key)
  local alpha = out.alpha or {}
  out.alpha = alpha

  local hpAlpha = Clamp01(conf.hpBarAlpha, 1)
  alpha.hpAlpha = hpAlpha
  alpha.excludeTextPortrait = conf.alphaExcludeTextPortrait == true
  alpha.active = hpAlpha < 1

  -- Out-of-combat fade: whole-frame multiplier applied only while out of
  -- combat; min-composed with the range fade in the alpha element so the
  -- strongest single fade wins. oocFade with an alpha of 1 is inert.
  local oocAlpha = Clamp01(conf.oocFadeAlpha, 0.5)
  alpha.oocFade = conf.oocFadeEnabled == true and oocAlpha < 1
  alpha.oocAlpha = oocAlpha
end

local function ClampStatusLayer(value, fallback)
  value = Number(value, fallback or 7)
  value = math.floor(value + 0.5)
  if value < 0 then
    return 0
  elseif value > 30 then
    return 30
  end
  return value
end

local function StatusBool(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if value == nil and legacyKey then
    value = conf and conf[legacyKey]
  end
  if value == nil then
    value = general and general[key]
    if value == nil and legacyKey then
      value = general and general[legacyKey]
    end
  end
  return Bool(value, fallback)
end

local Secrets = MSUF.Secrets or {}
local PlainTrue = Secrets.PlainTrue or function(value) return value == true or value == 1 end

local function APIBool(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return PlainTrue(fn(...)) == true
end

local function CurrentInstanceType()
  if IsInInstance then
    local _, instanceType = IsInInstance()
    if type(instanceType) == "string" and instanceType ~= "" then
      return instanceType
    end
  end
  if GetInstanceInfo then
    local _, instanceType = GetInstanceInfo()
    if type(instanceType) == "string" and instanceType ~= "" then
      return instanceType
    end
  end
  return nil
end

local _pvpContextKnown, _pvpContextActive = false, false

local function UnitFramePVPContextualDisabled()
  local gameRules = _G.C_GameRules
  local enum = _G.Enum
  local rule = enum and enum.GameRule and enum.GameRule.UnitFramePvPContextualDisabled
  return gameRules and type(gameRules.IsGameRuleActive) == "function" and rule ~= nil
    and APIBool(gameRules.IsGameRuleActive, rule)
end

local function ComputePVPIndicatorContextActive(warModeOverride)
  if UnitFramePVPContextualDisabled() then return false end
  local instanceType = CurrentInstanceType()
  if instanceType == "pvp" or instanceType == "arena" then
    return true
  elseif instanceType == "party" or instanceType == "raid" then
    return false
  end

  -- WAR_MODE_STATUS_UPDATE carries the new desired state. Treat it as the
  -- authoritative boundary so a still-active deactivation timer cannot keep
  -- the compiled UF/GF PvP paths warm after War Mode was switched off.
  if warModeOverride ~= nil then
    return warModeOverride == true
  end

  local cpvp = _G.C_PvP
  if not cpvp then return false end
  -- This indicator is intentionally a PvP-mode feature, not a general
  -- UnitIsPVP flag display. Outside War Mode, arenas and battlegrounds its
  -- complete UF/GF runtime stays uncompiled even when the profile enables it.
  if type(cpvp.IsWarModeDesired) == "function" then
    return APIBool(cpvp.IsWarModeDesired)
  end
  return APIBool(cpvp.IsWarModeActive)
end

function UF.InvalidatePVPIndicatorContext()
  _pvpContextKnown = false
end

function UF.PVPIndicatorContextActive()
  if not _pvpContextKnown then
    _pvpContextActive = ComputePVPIndicatorContextActive() == true
    _pvpContextKnown = true
  end
  return _pvpContextActive == true
end

local PVP_CONTEXT_REFRESH_ELEMENTS = { "StatusIndicators", "PVPIndicator", "GroupStatusRuntime" }
local PVP_CONTEXT_FORCE_EVENTS = {
  ACTIVE_GAME_MODE_UPDATED = true,
  PLAYER_ENTERING_WORLD = true,
  WAR_MODE_STATUS_UPDATE = true,
}

function UF.RefreshPVPIndicatorContext(reason, force, warModeOverride)
  local oldKnown, oldActive = _pvpContextKnown, _pvpContextActive
  local active
  if warModeOverride ~= nil then
    active = ComputePVPIndicatorContextActive(warModeOverride == true) == true
    _pvpContextActive = active
    _pvpContextKnown = true
  else
    UF.InvalidatePVPIndicatorContext()
    active = UF.PVPIndicatorContextActive()
  end
  if force ~= true and oldKnown and oldActive == active then
    return false
  end
  if UF.RefreshElements then
    UF.RefreshElements(nil, PVP_CONTEXT_REFRESH_ELEMENTS, reason or "MSUF_PVP_CONTEXT")
  end
  local gf = MSUF.GF
  if gf then
    if gf.RefreshVisuals then
      gf.RefreshVisuals(nil, gf.DIRTY_VISUAL)
    elseif gf.RefreshAll then
      gf.RefreshAll()
    end
  end
  return true
end

local function RegisterPVPContextEvent(frame, event)
  frame:RegisterEvent(event)
end

if not UF.pvpIndicatorContextDriver then
  local pvpDriver = CreateFrame("Frame")
  pvpDriver:SetScript("OnEvent", function(_, event, arg1)
    -- This driver owns cold recompilation only. PvP textures already have their
    -- native per-frame event routing, so never query context or rebuild UF/GF
    -- specs in combat.
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    local force = PVP_CONTEXT_FORCE_EVENTS[event] == true
    local warModeOverride
    if event == "WAR_MODE_STATUS_UPDATE" then
      warModeOverride = PlainTrue(arg1) == true
    end
    -- This is a compile boundary, not just a repaint: false disables the
    -- cached UF status path and the GF runtime/event path before both refresh.
    UF.RefreshPVPIndicatorContext(
      "MSUF_PVP_CONTEXT_" .. tostring(event),
      force,
      warModeOverride
    )
  end)
  RegisterPVPContextEvent(pvpDriver, "ACTIVE_GAME_MODE_UPDATED")
  RegisterPVPContextEvent(pvpDriver, "PLAYER_ENTERING_WORLD")
  RegisterPVPContextEvent(pvpDriver, "ZONE_CHANGED_NEW_AREA")
  RegisterPVPContextEvent(pvpDriver, "WAR_MODE_STATUS_UPDATE")
  UF.pvpIndicatorContextDriver = pvpDriver
end

local function StatusNumber(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if value == nil and legacyKey then
    value = conf and conf[legacyKey]
  end
  if value == nil then
    value = general and general[key]
    if value == nil and legacyKey then
      value = general and general[legacyKey]
    end
  end
  return Number(value, fallback)
end

local function StatusString(conf, general, key, fallback, legacyKey)
  local value = conf and conf[key]
  if (type(value) ~= "string" or value == "") and legacyKey then
    value = conf and conf[legacyKey]
  end
  if type(value) ~= "string" or value == "" then
    value = general and general[key]
    if (type(value) ~= "string" or value == "") and legacyKey then
      value = general and general[legacyKey]
    end
  end
  if type(value) ~= "string" or value == "" then
    value = fallback
  end
  return value or ""
end

local function StatusAllowed(key, id)
  if id == "leader" or id == "assist" or id == "combat" or id == "incomingRes" then
    return key == "player" or key == "target"
  elseif id == "pvp" then
    return key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "focustarget"
  elseif id == "resting" or id == "stance" then
    return key == "player"
  elseif id == "raidGroup" then
    return key == "player" or key == "target" or key == "targettarget" or key == "focustarget" or key == "focus"
  elseif id == "elite" then
    return key == "target" or key == "focus" or key == "targettarget" or key == "focustarget" or key == "boss"
  end
  return true
end

local function ResetList(list)
  list = list or {}
  wipe(list)
  return list
end

local function AddEvent(list, event)
  list[#list + 1] = event
end

local function CompileStatusEntry(status, id, conf, general, key, showKey, fallbackShow, sizeKey, fallbackSize, anchorKey, fallbackAnchor, xKey, fallbackX, yKey, fallbackY, layerKey, fallbackLayer, legacyLayerKey)
  local entry = status[id] or {}
  status[id] = entry
  entry.enabled = StatusAllowed(key, id) and StatusBool(conf, general, showKey, fallbackShow) or false
  entry.size = StatusNumber(conf, general, sizeKey, fallbackSize)
  entry.anchor = StatusString(conf, general, anchorKey, fallbackAnchor)
  entry.x = StatusNumber(conf, general, xKey, fallbackX)
  entry.y = StatusNumber(conf, general, yKey, fallbackY)
  entry.layer = ClampStatusLayer(StatusNumber(conf, general, layerKey, fallbackLayer, legacyLayerKey), fallbackLayer)
  return entry
end

--- Indicator text colors are stored as a complete R/G/B triple or not at all.
--- Unlike StatusNumber this read is nil-preserving on purpose: an unset triple
--- has to keep inheriting the frame's resolved font color, so profiles that
--- never picked a color are not silently pinned to white.
local function ApplyStatusColor(entry, conf, general, colorPrefix)
  local r, g, b
  if colorPrefix then
    r = conf and conf[colorPrefix .. "ColorR"]
    if r == nil then r = general and general[colorPrefix .. "ColorR"] end
    g = conf and conf[colorPrefix .. "ColorG"]
    if g == nil then g = general and general[colorPrefix .. "ColorG"] end
    b = conf and conf[colorPrefix .. "ColorB"]
    if b == nil then b = general and general[colorPrefix .. "ColorB"] end
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
  end
  if r and g and b then
    entry.colorR, entry.colorG, entry.colorB = Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1)
  else
    entry.colorR, entry.colorG, entry.colorB = nil, nil, nil
  end
  return entry
end

local function StatusEntryDef(id, showKey, showDefault, sizeKey, sizeDefault, anchorKey, anchorDefault, xKey, xDefault, yKey, yDefault, layerKey, layerDefault, style, symbol, customIcon, legacyLayerKey, colorPrefix)
  return { id, showKey, showDefault, sizeKey, sizeDefault, anchorKey, anchorDefault, xKey, xDefault, yKey, yDefault, layerKey, layerDefault, style = style, symbol = symbol, customIcon = customIcon, legacyLayerKey = legacyLayerKey, colorPrefix = colorPrefix }
end

local function PrefixedStatusDef(id, showKey, showDefault, prefix, sizeDefault, anchorDefault, xDefault, yDefault, layerDefault, style, symbol, customIcon)
  return StatusEntryDef(id, showKey, showDefault,
    prefix .. "Size", sizeDefault, prefix .. "Anchor", anchorDefault,
    prefix .. "OffsetX", xDefault, prefix .. "OffsetY", yDefault,
    prefix .. "Layer", layerDefault, style, symbol, customIcon, nil, prefix)
end

local UNIT_STATUS_ENTRY_DEFS = {
  PrefixedStatusDef("leader", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", 0, 3, 7, { "leaderIconStyle", "BLIZZARD" }, nil, { "leaderIconCustomIcon", "" }),
  PrefixedStatusDef("assist", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", 0, 3, 7, { "assistIconStyle", "BLIZZARD", "leaderIconStyle" }, nil, { "assistIconCustomIcon", "" }),
  PrefixedStatusDef("raidMarker", "showRaidMarker", true, "raidMarker", 18, "TOPLEFT", 16, 3, 7, nil, nil, { "raidMarkerCustomIcon", "" }),
  PrefixedStatusDef("level", "showLevelIndicator", true, "levelIndicator", 14, "NAMERIGHT", 0, 0, 7),
  PrefixedStatusDef("bossNumber", "showBossNumberIndicator", false, "bossNumberIndicator", 14, "TOPLEFT", 4, -4, 7),
  PrefixedStatusDef("race", "showRaceIndicator", false, "raceIndicator", 14, "NAMERIGHT", 0, 0, 7),
  PrefixedStatusDef("classText", "showClassTextIndicator", false, "classTextIndicator", 14, "NAMERIGHT", 0, 0, 7),
  StatusEntryDef("raidGroup", "showRaidGroupInName", false, "nameFontSize", 12, "raidGroupNameAnchor", "NAMERIGHT", "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "raidGroupNameLayer", 5, { "raidGroupNameStyle", "PAREN" }, nil, nil, "nameTextLayer", "raidGroupName"),
  PrefixedStatusDef("elite", "showEliteIcon", true, "eliteIcon", 20, "TOPRIGHT", 2, 2, 7, nil, nil, { "eliteIconCustomIcon", "" }),
  PrefixedStatusDef("combat", "showCombatStateIndicator", true, "combatStateIndicator", 18, "TOPLEFT", 0, 0, 7, nil, { "combatStateIndicatorSymbol", "DEFAULT" }, { "combatStateIndicatorCustomIcon", "" }),
  PrefixedStatusDef("resting", "showRestingIndicator", true, "restedStateIndicator", 39, "TOPLEFT", -40, 50, 25, { "restedStateIndicatorIconStyle", "BLIZZARD" }, { "restedStateIndicatorSymbol", "rested_blizzard_animated", "restingStateIndicatorSymbol" }, { "restedStateIndicatorCustomIcon", "" }),
  PrefixedStatusDef("incomingRes", "showIncomingResIndicator", true, "incomingResIndicator", 18, "TOPRIGHT", 0, 0, 7, nil, { "incomingResIndicatorSymbol", "DEFAULT" }, { "incomingResIndicatorCustomIcon", "" }),
  PrefixedStatusDef("pvp", "showPvpIndicator", true, "pvpIndicator", 18, "TOPRIGHT", 0, 0, 7, nil, nil, { "pvpIndicatorCustomIcon", "" }),
  PrefixedStatusDef("stance", "showStanceIndicator", false, "stanceIndicator", 12, "TOP", 0, -2, 7),
}

local UNIT_STATUS_TEXT_STATE_DEFS = {
  { "statusDeadText", "statusDeadTextEnabled", "showDead", true, "statusText" },
  { "statusGhostText", "statusGhostTextEnabled", "showGhost", true, "statusGhostText" },
  { "statusAFKText", "statusAFKTextEnabled", "showAFK", false, "statusAFKText" },
  { "statusDNDText", "statusDNDTextEnabled", "showDND", false, "statusDNDText" },
}

local function CompileUnitStatusTextState(status, conf, general, def, fallbackSize)
  local id, showKey, legacyStateKey, defaultShow, prefix = def[1], def[2], def[3], def[4], def[5]
  local entry = status[id] or {}
  status[id] = entry
  local explicit = conf and conf[showKey]
  if explicit == nil then explicit = general and general[showKey] end
  if explicit == nil then
    local states = general and type(general.statusIndicators) == "table" and general.statusIndicators or nil
    local legacyState = states and states[legacyStateKey]
    if legacyState == nil then legacyState = defaultShow end
    entry.enabled = StatusBool(conf, general, "statusTextEnabled", true) and legacyState == true
  else
    entry.enabled = Bool(explicit, defaultShow)
  end
  local legacyPrefix = prefix ~= "statusText" and "statusText" or nil
  entry.size = StatusNumber(conf, general, prefix .. "Size", fallbackSize, legacyPrefix and (legacyPrefix .. "Size"))
  entry.anchor = StatusString(conf, general, prefix .. "Anchor", "CENTER", legacyPrefix and (legacyPrefix .. "Anchor"))
  entry.x = StatusNumber(conf, general, prefix .. "OffsetX", 0, legacyPrefix and (legacyPrefix .. "OffsetX"))
  entry.y = StatusNumber(conf, general, prefix .. "OffsetY", 0, legacyPrefix and (legacyPrefix .. "OffsetY"))
  entry.layer = ClampStatusLayer(StatusNumber(conf, general, prefix .. "Layer", 7, legacyPrefix and (legacyPrefix .. "Layer")), 7)
  ApplyStatusColor(entry, conf, general, prefix)
  return entry
end

local function CompileStatusEntryDef(status, conf, general, key, def, fallbackSize)
  local entry = CompileStatusEntry(status, def[1], conf, general, key,
    def[2], def[3], def[4], fallbackSize or def[5], def[6], def[7],
    def[8], def[9], def[10], def[11], def[12], def[13], def.legacyLayerKey)
  local style = def.style
  if style then
    entry.style = StatusString(conf, general, style[1], style[2])
  end
  local symbol = def.symbol
  if symbol then
    entry.symbol = StatusString(conf, general, symbol[1], symbol[2], symbol[3])
  end
  local customIcon = def.customIcon
  if customIcon then
    entry.customIcon = StatusString(conf, general, customIcon[1], customIcon[2])
  end
  ApplyStatusColor(entry, conf, general, def.colorPrefix)
  return entry
end

local LOAD_CONDITION_KEYS = {
  { "hideInHousing", "HideInHousing" },
  { "hideInCombat", "HideInCombat" },
  { "hideInGroup", "HideInGroup" },
  { "hideInInstance", "HideInInstance" },
  { "hideInVehicle", "HideInVehicle" },
  { "hideMounted", "HideMounted" },
  { "hideNoTarget", "HideNoTarget" },
  { "hideOutOfCombat", "HideOutOfCombat" },
  { "hideOutOfCombatNoTarget", "HideOutOfCombatNoTarget" },
  { "hideResting", "HideResting" },
  { "hideSolo", "HideSolo" },
  { "hideStealthed", "HideStealthed" },
}

local function CompileLoadConditions(out, conf)
  local load = out.load or {}
  out.load = load
  local active = false
  for i = 1, #LOAD_CONDITION_KEYS do
    local def = LOAD_CONDITION_KEYS[i]
    local enabled = Bool(conf["loadCond" .. def[2]], false)
    load[def[1]] = enabled
    active = active or enabled
  end
  load.active = active

  load.unitlessEvents = ResetList(load.unitlessEvents)
  if load.active then
    AddEvent(load.unitlessEvents, "PLAYER_REGEN_ENABLED")
  end
  if load.hideInInstance == true or load.hideInHousing == true then
    AddEvent(load.unitlessEvents, "PLAYER_ENTERING_WORLD")
    AddEvent(load.unitlessEvents, "ZONE_CHANGED_NEW_AREA")
  end
end

local function TextureFromGlobal()
  local fn = _G.MSUF_GetBarTexture
  if type(fn) == "function" then
    return fn() or WHITE
  end
  return WHITE
end

local function BackgroundTextureFromGlobal()
  local fn = _G.MSUF_GetBarBackgroundTexture
  if type(fn) == "function" then
    return fn() or WHITE
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

local function TextureFromScope(conf, general)
  -- Unit-frame textures are shared-only. Party/Raid texture overrides are
  -- resolved by the GroupFrames compiler path.
  local key = general and general.barTexture
  if key ~= nil then
    return ResolveStatusbarTextureKey(key, TextureFromGlobal())
  end
  return TextureFromGlobal()
end

local function BackgroundTextureFromScope(conf, general, foregroundTexture)
  local key
  if general then
    key = general.barBackgroundTexture
    if key == nil then key = general.barBgTexture end
  end
  if key ~= nil then
    if key == "" then
      return foregroundTexture or TextureFromScope(conf, general)
    end
    return ResolveStatusbarTextureKey(key, foregroundTexture or WHITE)
  end
  return BackgroundTextureFromGlobal()
end

-- Power bars may carry their own art instead of inheriting the unit's shared
-- bar texture. Resolution is scope-aware and happens once here in the compile
-- (cold) path, so the runtime only ever reads the finished spec value:
--   global bars.powerBarTexture -> per-unit conf.powerBarTexture
-- The same two layers cover the detached Player bar; there is no separate
-- Class Resources texture anymore, so the unit page owns the bar's appearance
-- whether it is detached or not. An empty value at every level keeps the
-- historical behavior (power follows the unit bar texture).
local function PowerTextureFromScope(conf, bars, fallback)
  local key = conf and conf.powerBarTexture
  if type(key) ~= "string" or key == "" then
    key = bars and bars.powerBarTexture
  end
  if type(key) == "string" and key ~= "" then
    return ResolveStatusbarTextureKey(key, fallback or TextureFromGlobal())
  end
  return fallback
end

local function PowerBackgroundTextureFromScope(conf, bars, fallback)
  local key = conf and conf.powerBarBgTexture
  if type(key) ~= "string" or key == "" then
    key = bars and bars.powerBarBgTexture
  end
  if type(key) == "string" and key ~= "" then
    return ResolveStatusbarTextureKey(key, fallback or WHITE)
  end
  return fallback
end

local function ClassPowerFallbackWidth(out, bars)
  local widthMode = bars and bars.classPowerWidthMode or "player"
  if widthMode == "auto_pips" then
    local shape = tostring((bars and bars.classPowerShape) or "BAR"):upper()
    if shape == "CIRCLE" or shape == "DIAMOND" or shape == "HEX" then
      local container = _G.MSUF_ClassPowerContainer
      local liveW = container and container.GetWidth and container:GetWidth() or nil
      if liveW and liveW >= 20 then
        return liveW
      end
    end
  end
  if widthMode == "custom" then
    local custom = Number(bars and bars.classPowerWidth, 0)
    if custom >= 30 then
      return custom
    end
  end
  return max(1, Number(out and out.width, 275) - 4)
end

local function CooldownWidthFrameName(mode)
  return CDM_WIDTH_FRAMES[mode]
end

local function NormalizeClassPowerShape(value)
  value = tostring(value or "BAR"):upper()
  if value == "CIRCLE" or value == "DIAMOND" or value == "HEX" then return value end
  return "BAR"
end

local function ResolveDetachedPowerShape(conf, bars)
  local value = tostring((conf and conf.detachedPowerBarShape) or "BAR"):upper()
  if value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
  --- Compatibility for an unmigrated legacy FOLLOW_CLASS value only. New
  --- profiles always store a direct, independent Powerbar shape.
  local classShape = NormalizeClassPowerShape(bars and bars.classPowerShape)
  if classShape == "CIRCLE" then return "ROUND" end
  if classShape == "DIAMOND" or classShape == "HEX" then return "CRYSTAL" end
  return "BAR"
end

local function FontFromGlobal()
  local fn = _G.MSUF_GetFontPath
  if type(fn) == "function" then
    return fn() or DEFAULT_FONT
  end
  return DEFAULT_FONT
end

local function FontFlagsFromGlobal()
  local fn = _G.MSUF_GetFontFlags
  if type(fn) == "function" then
    return fn() or "OUTLINE"
  end
  return "OUTLINE"
end

local function ComposeFontFlags(outline, monochrome, slug)
  local flags = ""
  outline = tostring(outline or "OUTLINE"):upper()
  if slug == true then
    return (outline == "NONE" or outline == "") and "SLUG" or "OUTLINE,SLUG"
  end
  if outline == "THICKOUTLINE" then
    flags = "THICKOUTLINE"
  elseif outline ~= "NONE" and outline ~= "" then
    flags = "OUTLINE"
  end
  if monochrome == true then
    flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
  end
  return flags
end

local function ResolveFontFlags(general, conf)
  local outline = "OUTLINE"
  local monochrome = general and general.fontMonochrome == true
  local slug = general and general.fontSlug == true
  if general and general.noOutline then
    outline = "NONE"
  elseif general and general.boldText then
    outline = "THICKOUTLINE"
  end
  if conf and conf.fontOverride == true then
    if conf.noOutline ~= nil or conf.boldText ~= nil then
      if conf.noOutline then outline = "NONE"
      elseif conf.boldText then outline = "THICKOUTLINE"
      else outline = "OUTLINE" end
    end
    if conf.fontMonochrome ~= nil then
      monochrome = conf.fontMonochrome == true
    end
    if conf.fontSlug ~= nil then
      slug = conf.fontSlug == true
    end
  end
  if not (conf and conf.fontOverride == true)
    and not (general and (general.noOutline or general.boldText or general.fontMonochrome or general.fontSlug)) then
    return FontFlagsFromGlobal()
  end
  if slug then monochrome = false end
  return ComposeFontFlags(outline, monochrome, slug)
end

local function ResolveFontTextAlpha(general, conf)
  local value = general and general.fontTextAlpha
  if conf and conf.fontOverride == true and conf.fontTextAlpha ~= nil then
    value = conf.fontTextAlpha
  end
  value = tonumber(value) or 1
  if value < 0.7 then return 0.7 end
  if value > 1 then return 1 end
  return value
end

local function ResolveFontBaselineOffset(general, conf)
  local value = general and general.fontBaselineOffset
  if conf and conf.fontOverride == true and conf.fontBaselineOffset ~= nil then
    value = conf.fontBaselineOffset
  end
  value = tonumber(value) or 0
  if value < -4 then return -4 end
  if value > 4 then return 4 end
  return value
end

local ResolveFontShadowMetrics = _G.MSUF_ResolveFontShadowMetrics or function(opacity, distance, legacyStrength, fallbackOpacity, fallbackDistance)
  if legacyStrength ~= nil then
    legacyStrength = tostring(legacyStrength):upper()
    opacity = legacyStrength == "SOFT" and 0.55 or 1
    distance = legacyStrength == "DEEP" and 2 or 1
  else
    opacity = tonumber(opacity) or tonumber(fallbackOpacity) or 1
    distance = tonumber(distance) or tonumber(fallbackDistance) or 1
  end
  if opacity < 0.20 then opacity = 0.20 elseif opacity > 1 then opacity = 1 end
  distance = math.floor(distance + 0.5)
  distance = distance <= 1 and 1 or 2
  return opacity, distance, -distance
end

local function ResolveFontShadow(general, conf, flags)
  local enabled = not (general and general.textBackdrop == false)
  local alpha, x, y = ResolveFontShadowMetrics(general and general.fontShadowOpacity,
    general and general.fontShadowDistance, general and general.fontShadowStrength)
  if conf and conf.fontOverride == true then
    if conf.textBackdrop ~= nil then enabled = conf.textBackdrop == true end
    if conf.fontShadowOpacity ~= nil or conf.fontShadowDistance ~= nil or conf.fontShadowStrength ~= nil then
      alpha, x, y = ResolveFontShadowMetrics(conf.fontShadowOpacity, conf.fontShadowDistance,
        conf.fontShadowStrength, alpha, x)
    end
  end
  if tostring(flags or ""):upper():find("SLUG", 1, true) then enabled = false end
  return enabled, alpha, x, y
end

local function BossLayoutDelta(conf, index, def)
  conf = conf or {}
  def = def or DEFAULTS.boss
  index = Number(index, 1)
  local step = index - 1
  if step <= 0 then
    return 0, 0
  end
  local spacing = Number(conf.spacing, -42)
  local mode = conf.bossLayoutMode or "VERTICAL_DOWN"
  if mode == "VERTICAL_UP" then
    return 0, step * -spacing
  elseif mode == "HORIZONTAL_RIGHT" or mode == "HORIZONTAL_LEFT" then
    local width = Number(conf.width or conf.frameWidth, def.width)
    local height = Number(conf.height or conf.frameHeight, def.height)
    local visualGap = abs(spacing) - height
    local delta = step * (width + max(0, visualGap))
    if mode == "HORIZONTAL_LEFT" then
      delta = -delta
    end
    return delta, 0
  end
  return 0, step * spacing
end

local function BossOffset(conf, index, def)
  local x = Number(conf.offsetX or conf.x, def.x)
  local y = Number(conf.offsetY or conf.y, def.y)
  local dx, dy = BossLayoutDelta(conf, index, def)
  return x + dx, y + dy
end

local function PowerEnabled(unit, key, conf, bars)
  if conf.showPowerBar ~= nil then
    return conf.showPowerBar ~= false
  end
  local powerKey = POWER_KEYS[key]
  if powerKey and bars and bars[powerKey] ~= nil then
    return bars[powerKey] ~= false
  end
  if conf.showPowerText == nil and conf.showPower ~= nil then
    return conf.showPower ~= false
  end
  return DEFAULTS[key] and DEFAULTS[key].showPower ~= false
end

local function CastbarEnabled(unit, key, general)
  local shouldUseGlobal = _G.MSUF_ShouldUseMSUFCastbar
  if type(shouldUseGlobal) == "function" then
    return shouldUseGlobal(unit, general) == true
  end
  local shouldUse = UF.ShouldUseMSUFCastbar
  if type(shouldUse) == "function" then
    return shouldUse(unit) == true
  end
  local castbarKey = CASTBAR_KEYS[key]
  if not castbarKey then
    return false
  end
  return not (general and general[castbarKey] == false)
end

local function IsGlobalCooldownAnchorEnabled(general)
  local isEnabled = _G.MSUF_IsCooldownAnchorEnabled
  if type(isEnabled) == "function" then return isEnabled(general) == true end
  return general and general.anchorToCooldown == true or false
end

local function ResolveAnchorSettings(conf, general)
  local anchorFrameName = conf and conf.anchorFrameName
  if anchorFrameName == "UI_Parent" then anchorFrameName = "UIParent" end
  if type(anchorFrameName) == "string" and anchorFrameName ~= "" then
    return anchorFrameName, conf.anchorToUnitframe, IsCooldownViewerFrameName(anchorFrameName)
  end

  local anchorToUnitframe = conf and conf.anchorToUnitframe
  if type(anchorToUnitframe) == "string"
    and anchorToUnitframe ~= ""
    and anchorToUnitframe ~= "GLOBAL"
    and anchorToUnitframe ~= "global"
    and anchorToUnitframe ~= "FREE" then
    if IsCooldownViewerFrameName(anchorToUnitframe) then
      return anchorToUnitframe, "GLOBAL", true
    end
    return nil, anchorToUnitframe, false
  end

  if IsGlobalCooldownAnchorEnabled(general) then
    return "EssentialCooldownViewer", "GLOBAL", true
  end

  local globalAnchor = general and general.anchorName
  if globalAnchor == "UI_Parent" then globalAnchor = "UIParent" end
  if IsCooldownViewerFrameName(globalAnchor) then
    return globalAnchor, "GLOBAL", true
  end
  if type(globalAnchor) == "string"
    and globalAnchor ~= ""
    and globalAnchor ~= "UIParent"
    and globalAnchor ~= "WorldFrame"
    and globalAnchor ~= "EssentialCooldownViewer" then
    return globalAnchor, "GLOBAL", false
  end

  return nil, anchorToUnitframe, false
end

local function CompileUnitPortrait(out, conf, general)
  out.portrait = out.portrait or {}
  local portraitMode = NormalizePortraitMode(conf)
  local portraitOverride = Number(conf.portraitSizeOverride, Number(conf.portraitSize, 0))
  local portraitAutoSize = max(16, Number(out.height, 30) - 4)
  local portraitSize = portraitOverride > 0 and max(1, portraitOverride) or portraitAutoSize
  local portraitSizeMode = conf.portraitSizeMode
  if portraitSizeMode ~= "UNIFORM" and portraitSizeMode ~= "SEPARATE" then
    -- Legacy UnitFrames gave a positive uniform override priority. With Auto
    -- size, positive axis values were the only signal for non-square geometry.
    portraitSizeMode = portraitOverride > 0 and "UNIFORM"
      or ((Number(conf.portraitWidth, 0) > 0 or Number(conf.portraitHeight, 0) > 0) and "SEPARATE" or "UNIFORM")
  end
  out.portrait.enabled = portraitMode ~= "OFF"
  out.portrait.side = portraitMode == "RIGHT" and "RIGHT" or "LEFT"
  out.portrait.render = NormalizePortraitRender(conf.portraitRender)
  out.portrait.classStyle = NormalizePortraitClassStyle(conf.portraitClassStyle)
  out.portrait.castSpellIcon = conf.portraitCastSpellIcon == true
  out.portrait.shape = NormalizePortraitShape(conf.portraitShape)
  out.portrait.size = portraitSize
  out.portrait.sizeMode = portraitSizeMode
  out.portrait.x = Number(conf.portraitOffsetX, 0)
  out.portrait.y = Number(conf.portraitOffsetY, 0)
  --- The explicit mode keeps both value sets intact while making their
  --- precedence unambiguous. This also lets users return to their previous
  --- uniform or non-square geometry without destructive slider resets.
  local portraitWidth = Number(conf.portraitWidth, 0)
  local portraitHeight = Number(conf.portraitHeight, 0)
  if portraitSizeMode == "UNIFORM" then
    out.portrait.width = portraitSize
    out.portrait.height = portraitSize
  else
    -- A zero axis inherits the retained uniform value. Switching modes is
    -- therefore visually stable, while Size = 0 still resolves to Auto.
    out.portrait.width = portraitWidth > 0 and max(8, portraitWidth) or portraitSize
    out.portrait.height = portraitHeight > 0 and max(8, portraitHeight) or portraitSize
  end
  out.portrait.placement = NormalizePortraitPlacement(conf.portraitPlacement)
  out.portrait.point = NormalizePortraitAnchorPoint(conf.portraitDetachedPoint, "RIGHT")
  out.portrait.relPoint = NormalizePortraitAnchorPoint(conf.portraitDetachedTo, "LEFT")
  out.portrait.levelOffset = NormalizePortraitLevelOffset(conf.portraitLevelOffset, 7)
  out.portrait.overlayAlign = NormalizePortraitOverlayAlign(conf.portraitOverlayAlign)
  out.portrait.alpha = Clamp01(Number(conf.portraitAlpha, 100) / 100, 1)
  CompilePortraitTexCoords(
    out.portrait,
    NormalizePortraitZoom(conf.portraitZoom),
    out.portrait.width,
    out.portrait.height,
    NormalizePortraitPan(conf.portraitPanX),
    NormalizePortraitPan(conf.portraitPanY))
  out.portrait.border = out.portrait.border or {}
  out.portrait.border.style = NormalizePortraitBorder(conf.portraitBorderStyle)
  out.portrait.border.thickness = max(1, Number(conf.portraitBorderThickness, 2))
  out.portrait.border.fill = conf.portraitFillBorder == true
  out.portrait.border.art = NormalizePortraitBorderArt(conf.portraitBorderArt)
  out.portrait.border.direction = NormalizePortraitBorderDirection(conf.portraitBorderDirection)
  out.portrait.border.r = Number(general.portraitBorderColorR, 1)
  out.portrait.border.g = Number(general.portraitBorderColorG, 1)
  out.portrait.border.b = Number(general.portraitBorderColorB, 1)
  out.portrait.border.a = Number(general.portraitBorderColorA, 1)
  local portraitEdgeSoftnessLevel = min(15, max(0,
    floor((Number(conf.portraitEdgeSoftness, 0) / 2) + 0.5)))
  if out.portrait.shape == "BLIZZARD" or out.portrait.border.style ~= "NONE" then
    portraitEdgeSoftnessLevel = 0
  end
  out.portrait.edgeSoftnessLevel = portraitEdgeSoftnessLevel
  out.portrait.bg = out.portrait.bg or {}
  out.portrait.bg.enabled = conf.portraitBgEnabled == true
  out.portrait.bg.r = Number(general.portraitBgColorR, 0.05)
  out.portrait.bg.g = Number(general.portraitBgColorG, 0.05)
  out.portrait.bg.b = Number(general.portraitBgColorB, 0.05)
  out.portrait.bg.a = Number(general.portraitBgColorA, 0.85)
end

local function CompileUnitStatus(out, conf, general, key)
  out.status = out.status or {}
  local status = out.status
  status.key = key
  local statusAlpha = StatusNumber(conf, general, "stateIconsAlpha", 1, "statusIconsAlpha")
  if statusAlpha > 1 then
    statusAlpha = statusAlpha / 100
  end
  status.alpha = Clamp01(statusAlpha, 1)
  status.testMode = StatusBool(conf, general, "stateIconsTestMode", false, "statusIconsTestMode")
  status.useMidnight = StatusBool(conf, general, "statusIconsUseMidnightStyle", false)

  local levelSize = Number(conf.nameFontSize or general.nameFontSize, out.nameFontSize)
  local raidGroupSize = out.nameFontSize
  local statusTextSize = out.nameFontSize + 2
  for i = 1, #UNIT_STATUS_ENTRY_DEFS do
    local def = UNIT_STATUS_ENTRY_DEFS[i]
    local id = def[1]
    local fallbackSize = statusTextSize
    if id == "level" or id == "bossNumber" or id == "race" or id == "classText" or id == "stance" then
      fallbackSize = levelSize
    elseif id == "raidGroup" then
      fallbackSize = raidGroupSize
    end
    CompileStatusEntryDef(status, conf, general, key, def, fallbackSize)
  end

  local statusTextStates = {}
  for i = 1, #UNIT_STATUS_TEXT_STATE_DEFS do
    statusTextStates[i] = CompileUnitStatusTextState(status, conf, general, UNIT_STATUS_TEXT_STATE_DEFS[i], statusTextSize)
  end
  local deadText, ghostText, afkText, dndText = statusTextStates[1], statusTextStates[2], statusTextStates[3], statusTextStates[4]
  local baseText = deadText.enabled and deadText or ghostText.enabled and ghostText
    or afkText.enabled and afkText or dndText.enabled and dndText or deadText
  local statusText = status.statusText or {}
  status.statusText = statusText
  statusText.enabled = deadText.enabled or ghostText.enabled or afkText.enabled or dndText.enabled
  statusText.size, statusText.anchor = baseText.size, baseText.anchor
  statusText.x, statusText.y, statusText.layer = baseText.x, baseText.y, baseText.layer
  statusText.colorR, statusText.colorG, statusText.colorB = baseText.colorR, baseText.colorG, baseText.colorB
  statusText.showDead, statusText.showGhost = deadText.enabled, ghostText.enabled
  statusText.showAFK, statusText.showDND = afkText.enabled, dndText.enabled
  statusText.dead, statusText.ghost, statusText.afk, statusText.dnd = deadText, ghostText, afkText, dndText

  -- AFK timer companion region: independent placement, but it only renders
  -- while the AFK state text is active, so it needs no own show-state keys.
  local afkTimer = statusText.afkTimer or {}
  statusText.afkTimer = afkTimer
  local afkTimerShow = conf and conf.statusAFKTimerEnabled
  if afkTimerShow == nil then afkTimerShow = general and general.statusAFKTimerEnabled end
  afkTimer.enabled = afkTimerShow == true
  afkTimer.size = StatusNumber(conf, general, "statusAFKTimerSize", 12)
  afkTimer.anchor = StatusString(conf, general, "statusAFKTimerAnchor", "CENTER")
  afkTimer.x = StatusNumber(conf, general, "statusAFKTimerOffsetX", 0)
  afkTimer.y = StatusNumber(conf, general, "statusAFKTimerOffsetY", -14)
  afkTimer.layer = ClampStatusLayer(StatusNumber(conf, general, "statusAFKTimerLayer", 7), 7)
  ApplyStatusColor(afkTimer, conf, general, "statusAFKTimer")
  if afkTimer.colorR == nil then
    afkTimer.colorR, afkTimer.colorG, afkTimer.colorB = afkText.colorR, afkText.colorG, afkText.colorB
  end

  local pvp = status.pvp
  if pvp.enabled and UF.PVPIndicatorContextActive and not UF.PVPIndicatorContextActive() then
    pvp.enabled = false
    pvp.contextDisabled = true
  end

  local statusEnabled = false
  for i = 1, #UNIT_STATUS_ENTRY_DEFS do
    local entry = status[UNIT_STATUS_ENTRY_DEFS[i][1]]
    statusEnabled = statusEnabled or (entry and entry.enabled == true)
  end
  statusEnabled = statusEnabled or statusText.enabled
  status.enabled = statusEnabled
end

local function ResolveUnitContext(db, unit)
  local key = UF.ConfigKeyForUnit(unit)
  local def = DEFAULTS[key] or DEFAULTS.player
  local conf = type(db[key]) == "table" and db[key] or {}
  if key == "targettarget" and type(db.targettarget) ~= "table" and type(db.tot) == "table" then
    conf = db.tot
  end
  local general = type(db.general) == "table" and db.general or {}
  local bars = type(db.bars) == "table" and db.bars or {}
  local bossIndex = unit and unit:match("^boss(%d+)$")
  return key, def, conf, general, bars, bossIndex
end

--- Unit frames canonically store HP-text visibility in showHP. Older imports
--- may only carry showHPText, so use that alias strictly when the canonical
--- field is absent. Never let a stale alias override an explicit current value.
local function UnitHealthTextEnabled(conf)
  local enabled = conf.showHP
  if enabled == nil then enabled = conf.showHPText end
  return enabled ~= false
end

local function CompileUnitBase(out, unit, key, def, conf, general, bars, bossIndex)
  out.unit = unit
  out.key = key
  out.enabled = conf.enabled ~= false
  out.width = Number(conf.width or conf.frameWidth, def.width)
  out.height = Number(conf.height or conf.frameHeight, def.height)
  local cooldownViewerAnchor
  out.anchorFrameName, out.anchorToUnitframe, cooldownViewerAnchor = ResolveAnchorSettings(conf, general)
  -- 5.77 stored Utility/Buff viewer positions as CENTER-to-CENTER offsets.
  -- Only EssentialCooldownViewer owns the specialized edge-anchor rules.
  -- Keep this distinction in the cold config compile so legacy coordinates
  -- retain their exact screen geometry without adding runtime event work.
  local essentialCooldownAnchor = cooldownViewerAnchor
    and out.anchorFrameName == "EssentialCooldownViewer"
  local ecvRule = essentialCooldownAnchor and ECV_ANCHORS[key] or nil
  if ecvRule then
    out.point = ecvRule[1]
    out.relativePoint = ecvRule[2]
  else
    out.point = conf.point or "CENTER"
    out.relativePoint = conf.relativePoint or out.point
  end
  local x, y
  if bossIndex then
    x, y = BossOffset(conf, tonumber(bossIndex) or 1, def)
  else
    x = Number(conf.offsetX or conf.x, def.x)
    y = Number(conf.offsetY or conf.y, def.y)
  end
  if ecvRule then
    x = x + Number(ecvRule[3], 0)
    y = y + Number(ecvRule[4], 0)
  end
  out.x, out.y = x, y

  out.texture = TextureFromScope(conf, general)
  out.backgroundTexture = BackgroundTextureFromScope(conf, general, out.texture)
  out.backgroundAlpha = ResolveBgAlpha(general, bars, conf)
  if conf.showName ~= nil then
    out.showName = conf.showName == true
  else
    out.showName = def.showName ~= false
  end
  out.showHealthText = UnitHealthTextEnabled(conf)
  if conf.showPowerText ~= nil then
    out.showPowerText = conf.showPowerText ~= false
  elseif conf.showPower ~= nil then
    out.showPowerText = conf.showPower ~= false
  else
    out.showPowerText = true
  end
  out.font = FontFromGlobal()
  out.fontFlags = ResolveFontFlags(general, conf)
  out.fontSize = Number(conf.fontSize or general.fontSize, 12)
  out.nameFontSize = Number(conf.nameFontSize or general.nameFontSize, out.fontSize)
  out.healthFontSize = Number(conf.hpFontSize or general.hpFontSize, out.fontSize)
  out.powerFontSize = Number(conf.powerFontSize or general.powerFontSize, out.fontSize)
  out.textColor = out.textColor or {}
  ResolveTextColor(general, out.textColor)
  out.textColor.a = ResolveFontTextAlpha(general, conf)
  do
    local shadowEnabled, shadowAlpha, shadowX, shadowY = ResolveFontShadow(general, conf, out.fontFlags)
    out.fontShadow = shadowEnabled
    out.fontShadowAlpha = shadowAlpha
    out.fontShadowX = shadowX
    out.fontShadowY = shadowY
  end
end

local function CompileUnitText(out, db, unit, key, conf, general, bars)
  local text = out.text or {}
  out.text = text
  text.healthLeft = NormalizeHealthTextMode(conf.textLeft, "NONE")
  text.healthCenter = NormalizeHealthTextMode(conf.textCenter, "NONE")
  text.healthRight = NormalizeHealthTextMode(conf.textRight or conf.hpTextMode or general.hpTextMode, "CURPERCENT")
  text.healthLeftHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextLeftHidePercentSymbol")
  text.healthCenterHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextCenterHidePercentSymbol")
  text.healthRightHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "hpTextRightHidePercentSymbol")
  text.healthLeftFontSize = ResolveTextSlotFontSize(conf, general, "hpTextLeftFontSize", out.healthFontSize)
  text.healthCenterFontSize = ResolveTextSlotFontSize(conf, general, "hpTextCenterFontSize", out.healthFontSize)
  text.healthRightFontSize = ResolveTextSlotFontSize(conf, general, "hpTextRightFontSize", out.healthFontSize)
  if conf.hpTextReverse ~= nil then
    text.healthReverse = conf.hpTextReverse == true
  else
    text.healthReverse = general.hpTextReverse == true
  end
  text.healthDelimiter = conf.hpTextSeparator or general.hpTextSeparator or " - "
  text.healthPercentDecimals = (conf.healthTextDecimals == true or conf.hpTextDecimals == true) and 1 or 0
  text.healthAbsorbIcon = conf.hpAbsorbIcon == true
  text.healthLeftAbsorbIcon = conf.hpTextLeftAbsorbIcon == nil and text.healthAbsorbIcon or conf.hpTextLeftAbsorbIcon == true
  text.healthCenterAbsorbIcon = conf.hpTextCenterAbsorbIcon == nil and text.healthAbsorbIcon or conf.hpTextCenterAbsorbIcon == true
  text.healthRightAbsorbIcon = conf.hpTextRightAbsorbIcon == nil and text.healthAbsorbIcon or conf.hpTextRightAbsorbIcon == true
  if conf.hpFullValueShort ~= nil then
    text.healthShortNumbers = conf.hpFullValueShort == true
  else
    text.healthShortNumbers = general.useShortNumbers ~= false
  end
  text.nameAnchor = NormalizeUnitNameAnchor(conf.nameTextAnchor or conf.nameAnchor or general.nameTextAnchor or general.nameAnchor)
  text.nameX = Number(conf.nameOffsetX or conf.nameTextOffsetX or general.nameOffsetX or general.nameTextOffsetX, 4)
  local fontBaselineOffset = ResolveFontBaselineOffset(general, conf)
  text.nameY = Number(conf.nameOffsetY or conf.nameTextOffsetY or general.nameOffsetY or general.nameTextOffsetY, -4) + fontBaselineOffset
  text.healthX = Number(conf.hpOffsetX or conf.hpTextOffsetX or general.hpOffsetX or general.hpTextOffsetX, -4)
  text.healthY = Number(conf.hpOffsetY or conf.hpTextOffsetY or general.hpOffsetY or general.hpTextOffsetY, -4) + fontBaselineOffset
  ApplySideTextOffsets(text, "health", "hpText", "hp", text.healthX, text.healthY, conf, general)
  text.powerLeft = NormalizePowerTextMode(conf.powerTextLeft, "NONE")
  text.powerCenter = NormalizePowerTextMode(conf.powerTextCenter, "NONE")
  text.powerRight = NormalizePowerTextMode(conf.powerTextRight or conf.powerTextMode or general.powerTextMode, "CURPERCENT")
  text.powerLeftHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextLeftHidePercentSymbol")
  text.powerCenterHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextCenterHidePercentSymbol")
  text.powerRightHidePercentSymbol = ResolveTextSlotHidePercentSymbol(conf, general, "powerTextRightHidePercentSymbol")
  text.powerLeftFontSize = ResolveTextSlotFontSize(conf, general, "powerTextLeftFontSize", out.powerFontSize)
  text.powerCenterFontSize = ResolveTextSlotFontSize(conf, general, "powerTextCenterFontSize", out.powerFontSize)
  text.powerRightFontSize = ResolveTextSlotFontSize(conf, general, "powerTextRightFontSize", out.powerFontSize)
  text.powerDelimiter = conf.powerTextSeparator or general.powerTextSeparator or text.healthDelimiter
  text.powerX = Number(conf.powerOffsetX or conf.powerTextOffsetX or general.powerOffsetX or general.powerTextOffsetX, -4)
  text.powerY = Number(conf.powerOffsetY or conf.powerTextOffsetY or general.powerOffsetY or general.powerTextOffsetY, 4) + fontBaselineOffset
  ApplySideTextOffsets(text, "power", "powerText", "power", text.powerX, text.powerY, conf, general)
  text.nameLayer = ClampStatusLayer(conf.nameTextLayer or general.nameTextLayer, 5)
  text.healthLayer = ClampStatusLayer(conf.hpTextLayer or conf.textLayer or general.hpTextLayer or general.textLayer, 5)
  text.powerLayer = ClampStatusLayer(conf.powerTextLayer or general.powerTextLayer, 2)
  ResolveNameShortening(db, general, conf, unit, text)
  local customR, customG, customB
  text.nameClassColor, text.nameNpcColor, text.nameNpcClassColor, customR, customG, customB =
    ResolveNameColorFlags(general, conf)
  ApplyNpcTypeFlags(text, general, "npcTypeColorText")
  local nameCustomColor
  if customR then
    -- The table is reused across compiles so a config apply allocates nothing.
    nameCustomColor = text.nameCustomColor
    if not nameCustomColor then
      nameCustomColor = {}
      text.nameCustomColor = nameCustomColor
    end
    nameCustomColor.r, nameCustomColor.g, nameCustomColor.b, nameCustomColor.a = customR, customG, customB, 1
    -- An explicit per-frame color has to beat the global NPC-type name rule,
    -- which NameTextColor checks before it honors the override. Only this
    -- frame's text flag is cleared; the global setting stays untouched.
    text.npcTypeColorText = false
  end
  ResolveToTInline(db, general, unit, text)
  local healthTextColorMode = ResolveHealthTextColorMode(general, conf)
  text.healthColorByHealth = healthTextColorMode == "HEALTH"
  text.healthColorByClass = healthTextColorMode == "CLASS"
  text.powerColorByType = ResolvePowerTextColorByType(general, conf)
  text.directLayout = conf.directTextLayout == true
  if text.directLayout == true then
    CopyDirectTextLayout(text, conf)
    local npcTypeNameColor = NPCTypeTextColorEnabled(text)
    if text.nameClassColor ~= true and text.nameNpcColor ~= true and text.nameNpcClassColor ~= true and not npcTypeNameColor then
      text.nameColor = nameCustomColor or text.directNameColor
    else
      text.nameColor = nil
    end
  else
    text.nameColor = nameCustomColor
    ClearDirectTextLayout(text)
  end
  text.shortNumbers = general.useShortNumbers ~= false
  text.hidePercentSymbol = general.hidePercentSymbol == true
end

local function PetFrameColorEnabled(general)
  -- The color picker has no separate enable toggle. As in the legacy runtime,
  -- a complete stored RGB tuple is the opt-in signal for the pet override.
  return type(general.petFrameColorR) == "number"
    and type(general.petFrameColorG) == "number"
    and type(general.petFrameColorB) == "number"
end

local function CompileUnitHealth(out, db, conf, general, bars)
  local health = out.health or {}
  out.health = health
  health.texture = out.texture
  health.backgroundTexture = out.backgroundTexture
  health.reverse = conf.reverseFillBars == true
  health.vertical = conf.verticalFillBars == true
  health.chunked = conf.chunkedFill == true
  health.smooth = conf.smoothFill == true and health.chunked ~= true
  health.lossR = Clamp01(general.healthLossColorR, 1)
  health.lossG = Clamp01(general.healthLossColorG, 0.55)
  health.lossB = Clamp01(general.healthLossColorB, 0.08)
  health.mode = ResolveUnitBarMode(conf, general)
  health.gradient = general.enableHealthGradient ~= false
  health.gradientLowR = Number(general.healthGradientLowR, 1)
  health.gradientLowG = Number(general.healthGradientLowG, 0)
  health.gradientLowB = Number(general.healthGradientLowB, 0)
  health.gradientMidR = Number(general.healthGradientMidR, 1)
  health.gradientMidG = Number(general.healthGradientMidG, 1)
  health.gradientMidB = Number(general.healthGradientMidB, 0)
  health.gradientHighR = Number(general.healthGradientHighR, 0)
  health.gradientHighG = Number(general.healthGradientHighG, 1)
  health.gradientHighB = Number(general.healthGradientHighB, 0)
  health.barGradient = ResolveBarGradient(conf, general, "enableGradient")
  ApplyNpcTypeFlags(health, general, "npcTypeColorBar")
  -- Boss frames keep reaction coloring (hostile red / friendly green). The
  -- optional NPC class-color override only applies to non-boss NPC frames.
  health.npcClassColorBar = general.npcClassColorBar == true and out.key ~= "boss"
  health.petColorEnabled = PetFrameColorEnabled(general)
  health.petR = Number(general.petFrameColorR, 0)
  health.petG = Number(general.petFrameColorG, 0.8)
  health.petB = Number(general.petFrameColorB, 0)
  health.petUsePlayerClassColor = out.key == "pet" and general.petFrameUsePlayerClassColor == true or false
  if health.petUsePlayerClassColor then
    health.petPlayerClassR, health.petPlayerClassG, health.petPlayerClassB = ResolveClassColor(db, PlayerClassToken())
  else
    health.petPlayerClassR, health.petPlayerClassG, health.petPlayerClassB = nil, nil, nil
  end
  if health.mode == "unified" then
    CopyColor(health, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
  elseif health.mode == "dark" then
    ResolveDarkColor(general, health)
  else
    CopyColor(health, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
  end
  health.background = ResolveHealthBackground(general, bars, health, health.background or {}, conf)
  health.backgroundMatchHealth = general.barBgMatchHPColor == true
  health.backgroundClassColor = general.barBgClassColor == true
  return health
end

local function CompileUnitTempMaxHealth(out, conf, general, key)
  local cfg = out.tempMaxHealth or {}
  out.tempMaxHealth = cfg
  local test = AbsorbTextureTestEnabledForScope(key, "tempMaxHealth")
  cfg.test = test == true
  cfg.enabled = ScopedValue(conf, general, "tempMaxHealthEnabled", false) == true or cfg.test
  cfg.texture = ResolveStatusbarTextureKey(
    ScopedValue(conf, general, "tempMaxHealthTexture", ""), out.texture)
  cfg.r = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorR", 0.70), 0.70)
  cfg.g = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorG", 0.10), 0.10)
  cfg.b = Clamp01(ScopedValue(conf, general, "tempMaxHealthColorB", 0.10), 0.10)
  cfg.a = Clamp01(ScopedValue(conf, general, "tempMaxHealthOpacity", 1), 1)
  cfg.backgroundAlpha = Clamp01(ScopedValue(conf, general, "tempMaxHealthBackgroundOpacity", 0.65), 0.65)
end

local function CompileUnitPower(out, unit, key, conf, general, bars, health)
  local power = out.power or {}
  out.power = power
  power.enabled = PowerEnabled(unit, key, conf, bars)
  power.height = Number(conf.powerBarHeight or bars.powerBarHeight, 3)
  power.texture = PowerTextureFromScope(conf, bars, out.texture)
  power.backgroundTexture = PowerBackgroundTextureFromScope(conf, bars, out.backgroundTexture)
  local text = out.text
  power.frequent = unit == "player"
    and out.enabled ~= false
    and out.showPowerText == true
    and bars.realtimePowerText == true
    and text ~= nil
    and (PowerTextModeNeedsValueTicks(text.powerLeft)
      or PowerTextModeNeedsValueTicks(text.powerCenter)
      or PowerTextModeNeedsValueTicks(text.powerRight))
    or false
  power.alpha = Clamp01(conf.powerBarAlpha, 1)
  power.mode = ResolvePowerMode(general)
  power.colors = power.colors or {}
  wipe(power.colors)
  CopyPowerColorOverrides(power.colors, general.powerColorOverrides)
  CopyPowerColorOverrides(power.colors, general.classPowerColorOverrides, true)
  if conf.embedPowerBarIntoHealth ~= nil then
    power.embed = conf.embedPowerBarIntoHealth == true
  elseif bars.embedPowerBarIntoHealth ~= nil then
    power.embed = bars.embedPowerBarIntoHealth == true
  else
    power.embed = true
  end
  power.detached = conf.powerBarDetached == true
  power.detachedWidth = Number(conf.detachedPowerBarWidth, out.width)
  -- Same value without the frame-width fallback: nil means the Detached width
  -- was never configured. Class Resource width sync consults it so a width the
  -- user actually set stays authoritative when no Class Resource bar exists.
  power.detachedWidthExplicit = Number(conf.detachedPowerBarWidth, nil)
  power.detachedHeight = Number(conf.detachedPowerBarHeight, power.height)
  power.orbSize = Number(conf.detachedPowerOrbSize, 54)
  if power.orbSize < 20 then
    power.orbSize = 20
  elseif power.orbSize > 160 then
    power.orbSize = 160
  end
  power.detachedX = Number(conf.detachedPowerBarOffsetX, 0)
  power.detachedY = Number(conf.detachedPowerBarOffsetY, -4)
  power.detachedAnchorMode = tostring(conf.detachedPowerBarAnchorMode or "CENTER"):upper()
  power.detachedLevel = ClampStatusLayer(conf.detachedPowerBarFrameLevelOffset, 6)
  power.textOnDetached = conf.detachedPowerBarTextOnBar == true
  power.detachedSyncClass = key == "player" and conf.detachedPowerBarSyncClassPower ~= false
  power.detachedAnchorClass = key == "player" and conf.detachedPowerBarAnchorToClassPower == true
  power.detachedClassWidth = ClassPowerFallbackWidth(out, bars)
  power.detachedClassWidthFrameName = CooldownWidthFrameName(bars.classPowerWidthMode)
  power.detachedWidthFrameName = CooldownWidthFrameName(bars.detachedPowerBarWidthMode)
  power.shape = (key == "player" and power.detached == true) and ResolveDetachedPowerShape(conf, bars) or "BAR"
  power.borderEnabled = Bool(conf.powerBarBorderEnabled, bars.powerBarBorderEnabled == true)
  power.borderThickness = Number(conf.powerBarBorderThickness or bars.powerBarBorderThickness or bars.powerBarBorderSize, 1)
  if power.borderThickness < 0 then
    power.borderThickness = 0
  elseif power.borderThickness > 10 then
    power.borderThickness = 10
  end
  -- Class Resources owns the outline of every detached Player power shape,
  -- including BAR. Other units keep their per-unit power border controls.
  power.detachedOutline = key == "player"
    and Number(bars.detachedPowerBarOutline, power.borderThickness)
    or nil
  if power.detachedOutline ~= nil then
    if power.detachedOutline < 0 then
      power.detachedOutline = 0
    elseif power.detachedOutline > 8 then
      power.detachedOutline = 8
    end
  end
  power.borderR = Number(ScopedValue(conf, general, "barOutlineColorR", general.barBorderR), 0)
  power.borderG = Number(ScopedValue(conf, general, "barOutlineColorG", general.barBorderG), 0)
  power.borderB = Number(ScopedValue(conf, general, "barOutlineColorB", general.barBorderB), 0)
  power.borderA = Number(ScopedValue(conf, general, "barOutlineColorA", general.barBorderA), 1)
  if power.mode == "unified" then
    CopyColor(power, general.unifiedBarR or 0.1, general.unifiedBarG or 0.6, general.unifiedBarB or 0.9, 1)
  elseif power.mode == "dark" then
    ResolveDarkColor(general, power)
  elseif power.mode == "static" then
    CopyColor(power, general.powerBarColorR or 0.1, general.powerBarColorG or 0.35, general.powerBarColorB or 0.95, 1)
  else
    CopyColor(power, 0.1, 0.35, 0.95, 1)
  end
  power.background = ResolvePowerBackground(general, bars, health, power.background or {}, conf)
  power.backgroundMatchHealth = general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true
  power.barGradient = ResolveBarGradient(conf, general, "enablePowerGradient")
  power.reverse = health.reverse == true
  power.vertical = health.vertical == true
  power.lossR = Clamp01(general.powerLossColorR, 0.70)
  power.lossG = Clamp01(general.powerLossColorG, 0.90)
  power.lossB = Clamp01(general.powerLossColorB, 1)
  if conf.powerChunkedFill ~= nil then
    power.chunked = conf.powerChunkedFill == true
  else
    power.chunked = unit == "player" and bars.chunkedPowerBar == true or false
  end
  if conf.powerSmoothFill ~= nil then
    power.smooth = conf.powerSmoothFill == true and power.chunked ~= true
  else
    power.smooth = unit == "player" and bars.smoothPowerBar == true and power.chunked ~= true or false
  end
end

local function CompileUnitPrediction(out, conf, general, key)
  local pred = out.prediction or {}
  out.prediction = pred
  local absorbEnabled = ScopedValue(conf, general, "enableAbsorbBar", nil)
  if absorbEnabled == nil then
    local absorbMode = Number(ScopedValue(conf, general, "absorbTextMode", nil), nil)
    absorbEnabled = absorbMode == nil or absorbMode == 2 or absorbMode == 3
  end
  pred.absorb = absorbEnabled ~= false
  local legacyHealEnabled = general.showSelfHealPrediction == true or general.enableHealPrediction == true
  pred.heal = ScopedValue(conf, general, "healPredEnabled", legacyHealEnabled) == true
  pred.healAbsorb = ScopedValue(conf, general, "healAbsorbEnabled", true) ~= false
  pred.healTest = AbsorbTextureTestEnabledForScope(key, "heal")
  pred.absorbTest = AbsorbTextureTestEnabledForScope(key, "absorb")
  pred.healAbsorbTest = AbsorbTextureTestEnabledForScope(key, "healAbsorb")
  pred.test = pred.healTest == true or pred.absorbTest == true or pred.healAbsorbTest == true
  if pred.healTest == true then pred.heal = true end
  if pred.absorbTest == true then pred.absorb = true end
  if pred.healAbsorbTest == true then pred.healAbsorb = true end
  pred.enabled = pred.heal == true or pred.absorb == true or pred.healAbsorb == true
  pred.texture = out.texture
  pred.healAnchorMode = Number(ScopedValue(conf, general, "healPredAnchorMode", 3), 3)
  pred.absorbAnchorMode = Number(ScopedValue(conf, general, "absorbAnchorMode", 2), 2)
  pred.healAbsorbAnchorMode = Number(ScopedValue(conf, general, "healAbsorbAnchorMode", 3), 3)
  pred.healHeight = max(0, min(100, Number(ScopedValue(conf, general, "healPredictionBarHeight", 0), 0)))
  pred.healOffsetY = max(-100, min(100, Number(ScopedValue(conf, general, "healPredictionBarOffsetY", 0), 0)))
  pred.absorbHeight = max(0, min(100, Number(ScopedValue(conf, general, "absorbBarHeight", 0), 0)))
  pred.absorbOffsetY = max(-100, min(100, Number(ScopedValue(conf, general, "absorbBarOffsetY", 0), 0)))
  pred.healAbsorbHeight = max(0, min(100, Number(ScopedValue(conf, general, "healAbsorbBarHeight", 0), 0)))
  pred.healAbsorbOffsetY = max(-100, min(100, Number(ScopedValue(conf, general, "healAbsorbBarOffsetY", 0), 0)))
  pred.overAbsorbOverlay = ScopedValue(conf, general, "overAbsorbOverlay", false) == true
  pred.fullHealthAbsorbStripe = ScopedValue(conf, general, "fullHealthAbsorbStripe", false) == true
  pred.texture = ScopedValue(conf, general, "healPredictionBarTexture", out.texture)
  pred.absorbTexture = ScopedValue(conf, general, "absorbBarTexture", nil)
  pred.healAbsorbTexture = ScopedValue(conf, general, "healAbsorbBarTexture", nil)
  FillPredictionColors(pred, general, conf, ScopedValue, Number)
end

local function CompileUnitDispel(out, conf, general)
  -- These controls live on the individual Player/Target/Focus/Boss pages and
  -- are independent of the Bars override gate.  general.* is retained only as
  -- a compatibility fallback for profiles predating per-unit ownership.
  local function UnitDispelValue(key, fallback)
    if conf and conf[key] ~= nil then return conf[key] end
    if general and general[key] ~= nil then return general[key] end
    return fallback
  end
  local dispel = out.dispel or {}
  out.dispel = dispel
  dispel.r = 0.25
  dispel.g = 0.75
  dispel.b = 1
  dispel.a = 1
  local overlay = out.dispelOverlay or {}
  out.dispelOverlay = overlay
  overlay.enabled = UnitDispelValue("unitDispelOverlayEnabled", false) == true
  overlay.trigger = NormalizeDispelOverlayTrigger(UnitDispelValue("unitDispelOverlayTrigger", "BORDER"))
  overlay.style = NormalizeDispelOverlayStyle(UnitDispelValue("unitDispelOverlayStyle", "FULL"))
  overlay.onHealth = UnitDispelValue("unitDispelOverlayOnHealth", true) ~= false
  overlay.alpha = Clamp01(UnitDispelValue("unitDispelOverlayAlpha", 0.35), 0.35)
  -- Dispel-type symbol indicator. Auras3 normalizes/clamps every field, so this
  -- only has to forward the raw scoped values.
  local symbol = out.dispelSymbol or {}
  out.dispelSymbol = symbol
  symbol.enabled = UnitDispelValue("unitDispelSymbolEnabled", false) == true
  symbol.style = UnitDispelValue("unitDispelSymbolStyle", "BLIZZARD")
  symbol.mode = UnitDispelValue("unitDispelSymbolMode", "ALL")
  symbol.trigger = UnitDispelValue("unitDispelSymbolTrigger", "BORDER")
  symbol.size = UnitDispelValue("unitDispelSymbolSize", 14)
  symbol.spacing = UnitDispelValue("unitDispelSymbolSpacing", 2)
  symbol.growth = UnitDispelValue("unitDispelSymbolGrowth", "RIGHT")
  symbol.anchor = UnitDispelValue("unitDispelSymbolAnchor", "TOPRIGHT")
  symbol.x = UnitDispelValue("unitDispelSymbolX", 0)
  symbol.y = UnitDispelValue("unitDispelSymbolY", 0)
  symbol.alpha = Clamp01(UnitDispelValue("unitDispelSymbolAlpha", 1), 1)
  symbol.layer = UnitDispelValue("unitDispelSymbolLayer", 8)
  symbol.strata = UnitDispelValue("unitDispelSymbolStrata", "AUTO")
end

local function CompileUnitBorder(out, conf, general, bars)
  local border = out.border or {}
  out.border = border
  local outlineThickness = conf.hlOverride == true and conf.barOutlineThickness ~= nil and conf.barOutlineThickness or bars.barOutlineThickness
  if outlineThickness == nil then
    outlineThickness = general.useBarBorder == false and 0 or 1
  end
  border.thickness = Number(outlineThickness, 1)
  border.enabled = bars.showBarBorder ~= false and border.thickness > 0
  local outlineLayer = conf.hlOverride == true and conf.barOutlineLayer ~= nil and conf.barOutlineLayer or bars.barOutlineLayer
  border.layer = max(0, min(30, floor((tonumber(outlineLayer) or 0) + 0.5)))
  border.strata = NormalizeFrameOutlineStrata(conf.hlOverride == true and conf.barOutlineStrata ~= nil and conf.barOutlineStrata or bars.barOutlineStrata)
  -- Optional typed outline media. True borders use eight-piece edgeFile
  -- geometry; statusbar textures keep the historic four stretched edges.
  -- Rounded Frames ignores both and keeps its tinted rounded edge.
  border.textureMode, border.textureKey, border.texture = nil, nil, nil
  local outlineTextureKey = conf.hlOverride == true and conf.barOutlineTexture ~= nil and conf.barOutlineTexture or bars.barOutlineTexture
  local styles = MSUF.BorderStyles or _G.MSUF_BorderStyles
  if type(outlineTextureKey) == "string" and outlineTextureKey ~= ""
    and styles and type(styles.ResolveFrame) == "function" then
    border.textureMode, border.textureKey, border.texture = styles.ResolveFrame(outlineTextureKey)
  end
  border.r = Number(ScopedValue(conf, general, "barOutlineColorR", general.barBorderR), 0)
  border.g = Number(ScopedValue(conf, general, "barOutlineColorG", general.barBorderG), 0)
  border.b = Number(ScopedValue(conf, general, "barOutlineColorB", general.barBorderB), 0)
  border.a = Number(ScopedValue(conf, general, "barOutlineColorA", general.barBorderA), 1)
  border.highlightThickness = Number(ScopedValue(conf, general, "highlightBorderThickness", bars.highlightBorderThickness or general.highlightBorderThickness), border.thickness)
  border.aggroR = Number(general.hlAggroColorR or general.aggroBorderColorR or general.aggroBorderR, 1.00)
  border.aggroG = Number(general.hlAggroColorG or general.aggroBorderColorG or general.aggroBorderG, 0.55)
  border.aggroB = Number(general.hlAggroColorB or general.aggroBorderColorB or general.aggroBorderB, 0.00)
  border.purgeR = Number(general.hlPurgeColorR or general.purgeBorderColorR, 1.00)
  border.purgeG = Number(general.hlPurgeColorG or general.purgeBorderColorG, 0.85)
  border.purgeB = Number(general.hlPurgeColorB or general.purgeBorderColorB, 0.00)
  local bossColor = general.bossTargetHighlightColor
  border.bossTargetR = Number(type(bossColor) == "table" and bossColor[1], 1.00)
  border.bossTargetG = Number(type(bossColor) == "table" and bossColor[2], 0.82)
  border.bossTargetB = Number(type(bossColor) == "table" and bossColor[3], 0.00)
  border.prioEnabled, border.prioOrder = CompileBorderPriority(conf, general)
  local legacyDispelBorder = general.dispelBorderEnabled == true or general.hlDispelBorderEnabled == true
  if general.dispelBorderEnabled == nil and general.hlDispelBorderEnabled == nil then
    legacyDispelBorder = true
  end
  border.aggro = OutlineModeEnabled(ScopedValue(conf, general, "aggroOutlineMode", nil),
    general.aggroIndicatorMode == "border" or general.enableAggroHighlight == true)
  border.dispel = OutlineModeEnabled(ScopedValue(conf, general, "dispelOutlineMode", nil),
    legacyDispelBorder)
  border.dispelTrigger = NormalizeDispelDetectTrigger(ScopedValue(conf, general, "dispelBorderTrigger", "DISPEL_TYPE"))
  border.purge = OutlineModeEnabled(ScopedValue(conf, general, "purgeOutlineMode", nil),
    general.purgeBorderEnabled == true or general.hlPurgeBorderEnabled == true)
  border.bossTarget = OutlineModeEnabled(ScopedValue(conf, general, "bossTargetOutlineMode", nil),
    general.bossTargetHighlightEnabled ~= false)
end

local function CompileUnitTail(out, unit, key, conf, general, bars)
  CompileUnitPortrait(out, conf, general)
  CompileUnitStatus(out, conf, general, key)

  out.auras = out.auras or {}
  local A3 = MSUF.MSUF_Auras3
  out.auras.enabled = (A3 and A3.UnitFrameAuraEnabled and A3.UnitFrameAuraEnabled(unit) == true)
    or (out.border and out.border.dispel == true)
    or (out.border and out.border.purge == true and (unit == "target" or unit == "focus"))
    or (out.dispelOverlay and out.dispelOverlay.enabled == true)
    or (out.dispelSymbol and out.dispelSymbol.enabled == true)
    or false

  out.castbar = out.castbar or {}
  out.castbar.enabled = CastbarEnabled(unit, key, general)

  out.classPower = out.classPower or {}
  out.classPower.enabled = key == "player" and bars.showClassPower ~= false or false
end

--- ResolveUnit is the main DB-to-runtime-spec compiler for one unit token.
--- Keep it deterministic and side-effect-light: frame creation, region updates,
--- and event registration happen in Factory/Core after this spec exists.
local function ResolveUnit(db, unit, out)
  out = out or {}
  wipe(out)

  local key, def, conf, general, bars, bossIndex = ResolveUnitContext(db, unit)
  CompileUnitBase(out, unit, key, def, conf, general, bars, bossIndex)
  CompileUnitText(out, db, unit, key, conf, general, bars)
  local health = CompileUnitHealth(out, db, conf, general, bars)
  CompileUnitTempMaxHealth(out, conf, general, key)
  CompileUnitPower(out, unit, key, conf, general, bars, health)
  CompileUnitPrediction(out, conf, general, key)

  CompileAlpha(out, conf, general, key)
  CompileRange(out, conf, general, key)

  CompileLoadConditions(out, conf)
  CompileUnitDispel(out, conf, general)
  CompileUnitBorder(out, conf, general, bars)
  CompileUnitTail(out, unit, key, conf, general, bars)

  return out
end

Config.specs = Config.specs or {}

local function ConfigInCombat()
  return InCombatLockdown and InCombatLockdown()
end

function Config.BossLayoutDelta(conf, index)
  return BossLayoutDelta(conf, index, DEFAULTS.boss)
end

function Config.BossLayoutOffset(conf, index)
  return BossOffset(conf, index, DEFAULTS.boss)
end

--- Full refresh recompiles every managed unit spec. This is a cold/warm
--- operation for profile changes, option edits, and explicit rebuild requests;
--- do not call it from UNIT_HEALTH/POWER/AURA style gameplay events.
function Config.Refresh()
  if ConfigInCombat() then
    Config.dirty = true
    return Config.specs
  end
  local db = EnsureDB()
  for i = 1, #UF.unitOrder do
    local unit = UF.unitOrder[i]
    Config.specs[unit] = ResolveUnit(db, unit, Config.specs[unit])
  end
  Config.serial = (Config.serial or 0) + 1
  Config.dirty = nil
  return Config.specs
end

local function MSUF_GetBossLayoutDelta(index, conf)
  local db = EnsureDB()
  conf = conf or (db and db.boss) or {}
  return BossLayoutDelta(conf, index, DEFAULTS.boss)
end
ExportPublic("MSUF_GetBossLayoutDelta", MSUF_GetBossLayoutDelta)

function Config.RefreshUnit(unit)
  if not (unit and UF.IsManagedUnit and UF.IsManagedUnit(unit)) then
    return nil
  end
  if ConfigInCombat() then
    Config.dirty = true
    return Config.specs[unit]
  end
  local db = EnsureDB()
  Config.specs[unit] = ResolveUnit(db, unit, Config.specs[unit])
  Config.serial = (Config.serial or 0) + 1
  return Config.specs[unit]
end

function Config.GetSpec(unit)
  if Config.dirty == true and not ConfigInCombat() then
    Config.Refresh()
  end
  if not Config.specs[unit] then
    Config.Refresh()
  end
  return Config.specs[unit]
end

function Config.GetDB()
  return EnsureDB()
end

function Config.GetUnitDB(unit)
  local db = EnsureDB()
  return db[UF.ConfigKeyForUnit(unit)]
end

Config.settingsCache = Config.settingsCache or {}

--- Small read-mostly cache for runtime color/font decisions that are shared by
--- many frames. Hot code reads this cache instead of walking MSUF_DB.general.
local function BuildSettingsCache(db)
  local cache = Config.settingsCache
  local general = type(db.general) == "table" and db.general or {}
  local bars = type(db.bars) == "table" and db.bars or {}
  local dr, dg, dbb
  local dark = {}
  ResolveDarkColor(general, dark)
  dr, dg, dbb = dark.r, dark.g, dark.b
  local healthBg = ResolveHealthBackground(general, bars, nil, cache._healthBg or {})
  cache._healthBg = healthBg
  local powerBg = ResolvePowerBackground(general, bars, nil, cache._powerBg or {})
  cache._powerBg = powerBg

  cache.dbRef = db
  cache.generalRef = general
  cache.barsRef = bars
  cache.settingsSerial = Config.serial or 0
  cache.barMode = ResolveBarMode(general)
  cache.darkMode = general.darkMode == true
  cache.darkBgBrightness = Clamp01(general.darkBgBrightness, 0.25)
  cache.darkBarR, cache.darkBarG, cache.darkBarB = dr, dg, dbb
  cache.unifiedBarR = Number(general.unifiedBarR, 0.1)
  cache.unifiedBarG = Number(general.unifiedBarG, 0.6)
  cache.unifiedBarB = Number(general.unifiedBarB, 0.9)
  cache.healthGradientEnabled = general.enableHealthGradient ~= false
  cache.healthGradientLowR = Number(general.healthGradientLowR, 1)
  cache.healthGradientLowG = Number(general.healthGradientLowG, 0)
  cache.healthGradientLowB = Number(general.healthGradientLowB, 0)
  cache.healthGradientMidR = Number(general.healthGradientMidR, 1)
  cache.healthGradientMidG = Number(general.healthGradientMidG, 1)
  cache.healthGradientMidB = Number(general.healthGradientMidB, 0)
  cache.healthGradientHighR = Number(general.healthGradientHighR, 0)
  cache.healthGradientHighG = Number(general.healthGradientHighG, 1)
  cache.healthGradientHighB = Number(general.healthGradientHighB, 0)
  cache.barBackgroundAlpha = ResolveBgAlpha(general, bars)
  cache.barBgTintR, cache.barBgTintG, cache.barBgTintB, cache.barBgTintA = healthBg.r, healthBg.g, healthBg.b, healthBg.a
  cache.powerBgTintR, cache.powerBgTintG, cache.powerBgTintB, cache.powerBgTintA = powerBg.r, powerBg.g, powerBg.b, powerBg.a
  cache.barBgClassColor = general.barBgClassColor == true
  cache.barBgMatchHPColor = general.barBgMatchHPColor == true
  cache.powerBarBgMatchHPColor = general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true
  cache.petFrameColorEnabled = PetFrameColorEnabled(general)
  cache.petFrameColorR = Number(general.petFrameColorR, 0)
  cache.petFrameColorG = Number(general.petFrameColorG, 0.8)
  cache.petFrameColorB = Number(general.petFrameColorB, 0)
  cache.petFrameUsePlayerClassColor = general.petFrameUsePlayerClassColor == true
  ApplyNpcTypeFlags(cache, general, "npcTypeColorBar")
  ApplyNpcTypeFlags(cache, general, "npcTypeColorText")
  cache.npcClassColorBar = general.npcClassColorBar == true
  cache.classColors = cache.classColors or {}
  local classColors = type(db.classColors) == "table" and db.classColors or nil
  local palette = MSUF.MSUF_FONT_COLORS or _G.MSUF_FONT_COLORS
  for i = 1, #CLASS_TOKENS do
    local token = CLASS_TOKENS[i]
    local dst = cache.classColors[token] or {}
    cache.classColors[token] = dst
    local src = classColors and classColors[token]
    if type(src) == "table" and tonumber(src.r or src[1]) and tonumber(src.g or src[2]) and tonumber(src.b or src[3]) then
      dst.r, dst.g, dst.b = Number(src.r or src[1], 1), Number(src.g or src[2], 1), Number(src.b or src[3], 1)
    elseif type(src) == "string" and palette and palette[src] then
      local c = palette[src]
      dst.r, dst.g, dst.b = Number(c.r or c[1], 1), Number(c.g or c[2], 1), Number(c.b or c[3], 1)
    else
      local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
      dst.r, dst.g, dst.b = c and c.r or 0.12, c and c.g or 0.62, c and c.b or 0.95
    end
  end
  if cache.petFrameUsePlayerClassColor then
    cache.playerClassToken = PlayerClassToken()
    local color = cache.playerClassToken and cache.classColors[cache.playerClassToken]
    cache.petPlayerClassR = color and color.r or 0.12
    cache.petPlayerClassG = color and color.g or 0.62
    cache.petPlayerClassB = color and color.b or 0.95
  else
    cache.playerClassToken = nil
    cache.petPlayerClassR, cache.petPlayerClassG, cache.petPlayerClassB = nil, nil, nil
  end
  cache.npcColors = cache.npcColors or {}
  local npcColors = type(db.npcColors) == "table" and db.npcColors or nil
  for kind, fallback in pairs(NPC_COLOR_DEFAULTS) do
    local dst = cache.npcColors[kind] or {}
    cache.npcColors[kind] = dst
    local src = npcColors and npcColors[kind]
    if type(src) == "table" then
      dst.r = Number(src.r or src[1], fallback[1])
      dst.g = Number(src.g or src[2], fallback[2])
      dst.b = Number(src.b or src[3], fallback[3])
    else
      dst.r, dst.g, dst.b = fallback[1], fallback[2], fallback[3]
    end
  end
  Config.settingsCacheDirty = nil
  return cache
end

function Config.GetSettingsCache()
  local db = EnsureDB()
  local cache = Config.settingsCache
  if Config.dirty == true and ConfigInCombat() and cache.dbRef ~= nil then
    return cache
  end
  if Config.settingsCacheDirty == true then
    return BuildSettingsCache(db)
  end
  if cache.dbRef == db and cache.settingsSerial == (Config.serial or 0) then
    return cache
  end
  return BuildSettingsCache(db)
end

ExportPublic("MSUF_UFCore_GetSettingsCache", Config.GetSettingsCache)

function Config.RefreshSettingsCache()
  Config.settingsCacheDirty = true
  if ConfigInCombat() then
    Config.dirty = true
    return Config.settingsCache
  end
  return Config.GetSettingsCache()
end

ExportPublic("MSUF_UFCore_RefreshSettingsCache", Config.RefreshSettingsCache)

local function MSUF_UFCore_GetClassBarColorFast(classToken)
  local cache = Config.GetSettingsCache()
  local c = cache and cache.classColors and cache.classColors[classToken]
  if c then
    return c.r, c.g, c.b
  end
  c = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
  if c then
    return c.r, c.g, c.b
  end
  return 0.12, 0.62, 0.95
end
ExportPublic("MSUF_UFCore_GetClassBarColorFast", MSUF_UFCore_GetClassBarColorFast)

local function MSUF_UFCore_GetNPCReactionColorFast(kind)
  local cache = Config.GetSettingsCache()
  local c = cache and cache.npcColors and cache.npcColors[kind]
  if c then
    return c.r, c.g, c.b
  end
  local fallback = NPC_COLOR_DEFAULTS[kind] or NPC_COLOR_DEFAULTS.enemy
  return fallback[1], fallback[2], fallback[3]
end
ExportPublic("MSUF_UFCore_GetNPCReactionColorFast", MSUF_UFCore_GetNPCReactionColorFast)
