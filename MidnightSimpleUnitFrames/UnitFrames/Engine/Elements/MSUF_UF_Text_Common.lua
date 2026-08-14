local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local C = MSUF.UFBarTextCommon
if not C then return end

-- UF text common export shim.
-- Pulls the shared bar/text helper bundle into local symbols for legacy split modules. Keep
-- behavioral changes in MSUF_UF_Elements_BarsCommon.lua so the text runtime stays consistent.
local UF = C.UF
local FreshUnitState = UF.FreshUnitState
local ReadUnitIsPlayerCached = UF.ReadUnitIsPlayerCached
local ReadUnitClassCached = UF.ReadUnitClassCached
local CreateFrame = C.CreateFrame
local UnitClass = C.UnitClass
local UnitExists = C.UnitExists
local UnitHealth = C.UnitHealth
local UnitHealthMax = C.UnitHealthMax
local UnitGetTotalAbsorbs = C.UnitGetTotalAbsorbs
local UnitPower = C.UnitPower
local UnitPowerMax = C.UnitPowerMax
local UnitPowerType = C.UnitPowerType
local UnitHealthPercent = C.UnitHealthPercent
local UnitPowerPercent = C.UnitPowerPercent
local AbbreviateNumbers = C.AbbreviateNumbers
local BreakUpLargeNumbers = C.BreakUpLargeNumbers
local AbbreviateLargeNumbers = C.AbbreviateLargeNumbers
local InCombatLockdown = C.InCombatLockdown
local UnitName = C.UnitName
local UnitIsPlayer = C.UnitIsPlayer
local UnitIsDeadOrGhost = C.UnitIsDeadOrGhost
local UnitIsConnected = C.UnitIsConnected
local UnitReaction = C.UnitReaction
local UnitSelectionColor = C.UnitSelectionColor
local PowerBarColor = C.PowerBarColor
local RAID_CLASS_COLORS = C.RAID_CLASS_COLORS
local C_ClassColor_GetClassColor = _G.C_ClassColor and _G.C_ClassColor.GetClassColor
local type = C.type
local tonumber = C.tonumber
local format = C.format
local abs = C.abs
local floor = C.floor
local max = C.max
local GetTime = C.GetTime
local StatusBarInterpolation = C.StatusBarInterpolation
local SMOOTH_INTERP = C.SMOOTH_INTERP
local WHITE = C.WHITE
local SCALE_100 = C.SCALE_100
local ABSORB_HEALTH_MODE_BASE = C.ABSORB_HEALTH_MODE_BASE
local REVERSE_HEALTH_MODE = C.REVERSE_HEALTH_MODE
local EMPTY_EVENTS = C.EMPTY_EVENTS
local POWER_EVENTS = C.POWER_EVENTS
local POWER_EVENTS_FREQUENT = C.POWER_EVENTS_FREQUENT
local TEXT_EVENT_SETS = C.TEXT_EVENT_SETS
local TEXT_EVENT_SETS_ABSORB = C.TEXT_EVENT_SETS_ABSORB
local ClampFrameLayer = C.ClampFrameLayer
local DrawSubLayer = C.DrawSubLayer
local GetLayerBaseLevel = C.GetLayerBaseLevel
local SetStatusTexture = C.SetStatusTexture
local ApplyStatusColor = C.ApplyStatusColor
local SetBarMinMax = C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyTextureColor = C.ApplyTextureColor
local SetShownCached = C.SetShownCached
local SetFrameLevelCached = C.SetFrameLevelCached
local ExternalFrameWidth = C.ExternalFrameWidth
local ClassColorForToken = C.ClassColorForToken
local ClassColor = C.ClassColor
local UnitNPCKind = C.UnitNPCKind
local NPCColor = C.NPCColor
local GradientColor = C.GradientColor
local HealthColor = C.HealthColor
local ApplyBackgrounds = C.ApplyBackgrounds
local PowerColor = C.PowerColor
local Text = MSUF.UFText or {}
MSUF.UFText = Text
local Secrets = MSUF.Secrets or {}
local IsSecret = C.IsSecret or Secrets.IsSecret or function(_) return false end
-- Retail secret values can flow through health/color APIs during restricted
-- states. Cache normal numbers, but never persist secret-backed color tuples.
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local SECRET_DEPENDENT_CLASS_COLOR = 2

local STANDARD_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local EXPRESSWAY_REGULAR = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf"
local EXPRESSWAY_SEMIBOLD = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"

local function ResolveRoleFont(font, role, size)
  if type(font) ~= "string" or font == "" then return font end
  local normalized = font:gsub("/", "\\"):lower()
  local regular = EXPRESSWAY_REGULAR:lower()
  if normalized ~= regular and not normalized:match("\\expressway regular%.ttf$") then return font end
  if role == "name" or ((role == "health" or role == "power") and (tonumber(size) or 12) <= 10) then
    return EXPRESSWAY_SEMIBOLD
  end
  return font
end

local function FontApplied(fs, requested, requestedSize)
  local matches = _G.MSUF_FontApplicationMatches
  if type(matches) == "function" then
    return matches(fs, requested, requestedSize) == true
  end
  if type(fs.GetFont) ~= "function" then return true end
  local actual, actualSize = fs:GetFont()
  if not actual then return false end
  local pathMatches = tostring(actual):gsub("/", "\\"):lower() == tostring(requested or ""):gsub("/", "\\"):lower()
  actualSize, requestedSize = tonumber(actualSize), tonumber(requestedSize)
  return pathMatches and actualSize ~= nil and requestedSize ~= nil and math.abs(actualSize - requestedSize) <= 0.01
end

local function ApplyFontChecked(fs, requested, size, flags)
  if not (fs and type(fs.SetFont) == "function") then return false end
  size = tonumber(size) or 12
  if size <= 0 then size = 12 end
  if size < 6 then size = 6 elseif size > 128 then size = 128 end
  local ok, applied = pcall(fs.SetFont, fs, requested, size, flags)
  return ok and applied ~= false and FontApplied(fs, requested, size)
end

local function SetFont(fs, spec, size, role)
  if not fs then
    return true
  end
  local fontSize = tonumber(size) or 12
  if fontSize <= 0 then fontSize = 12 end
  if fontSize < 6 then fontSize = 6 elseif fontSize > 128 then fontSize = 128 end
  local font = ResolveRoleFont((spec and spec.font) or STANDARD_FONT, role, fontSize)
  local flags = spec and spec.fontFlags or "OUTLINE"
  local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
  local fontReady = fs._msufFontPending ~= true
  if fs._msufFontAttemptEpoch ~= fontEpoch
    or fs._msufFont ~= font
    or fs._msufFontSize ~= fontSize
    or fs._msufFontFlags ~= flags
  then
    if ApplyFontChecked(fs, font, fontSize, flags) then
      fs._msufFont = font
      fs._msufFontSize = fontSize
      fs._msufFontFlags = flags
      fs._msufFontEpoch = fontEpoch
      fs._msufFontAttemptEpoch = fontEpoch
      fs._msufFontPending = nil
      fontReady = true
    else
      if font ~= STANDARD_FONT then ApplyFontChecked(fs, STANDARD_FONT, fontSize, flags) end
      local clear = _G.MSUF_ClearFontStringApplyCaches
      if type(clear) == "function" then clear(fs) end
      -- Remember this epoch's bounded fallback attempt so ordinary unit events
      -- do not retry SetFont. The coordinator's next epoch is the retry owner.
      fs._msufFont, fs._msufFontSize, fs._msufFontFlags = font, fontSize, flags
      fs._msufFontEpoch = nil
      fs._msufFontAttemptEpoch = fontEpoch
      fs._msufFontPending = true
      local markFailed = _G.MSUF_MarkFontApplyFailed
      if type(markFailed) == "function" then markFailed() end
      fontReady = false
    end
  end
  local color = spec and spec.textColor
  local r, g, b, a = color and color.r or 1, color and color.g or 1, color and color.b or 1, color and color.a or 1
  if fs._msufTextR ~= r or fs._msufTextG ~= g or fs._msufTextB ~= b or fs._msufTextA ~= a then
    fs:SetTextColor(r, g, b, a)
    fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
  end
  if fs.SetShadowOffset then
    local shadowOn = spec and spec.fontShadow == true
    local sx = shadowOn and (tonumber(spec and spec.fontShadowX) or 1) or 0
    local sy = shadowOn and (tonumber(spec and spec.fontShadowY) or -1) or 0
    local sa = shadowOn and (tonumber(spec and spec.fontShadowAlpha) or 1) or 0
    if fs._msufShadowX ~= sx or fs._msufShadowY ~= sy or fs._msufShadowA ~= sa then
      if shadowOn and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, sa) end
      fs:SetShadowOffset(sx, sy)
      fs._msufShadowX, fs._msufShadowY, fs._msufShadowA = sx, sy, sa
    end
  end
  return fontReady
end

local function SetPowerTextColor(frame, r, g, b, a)
  a = a or 1
  if frame._msufPowerTextR == r
    and frame._msufPowerTextG == g
    and frame._msufPowerTextB == b
    and frame._msufPowerTextA == a then
    return
  end
  local left, center, right = frame.powerTextLeft, frame.powerTextCenter, frame.powerTextRight
  if left then
    left:SetTextColor(r, g, b, a)
    left._msufTextR, left._msufTextG, left._msufTextB, left._msufTextA = r, g, b, a
  end
  if center then
    center:SetTextColor(r, g, b, a)
    center._msufTextR, center._msufTextG, center._msufTextB, center._msufTextA = r, g, b, a
  end
  if right then
    right:SetTextColor(r, g, b, a)
    right._msufTextR, right._msufTextG, right._msufTextB, right._msufTextA = r, g, b, a
  end
  frame._msufPowerTextR, frame._msufPowerTextG, frame._msufPowerTextB, frame._msufPowerTextA = r, g, b, a
end

local function SetHealthTextSlotColor(fs, r, g, b, a)
  if not fs then
    return
  end
  fs:SetTextColor(r, g, b, a)
  fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
end

local function SetHealthTextSlotColorSecret(fs, r, g, b, a)
  if not fs then
    return
  end
  fs:SetTextColor(r, g, b, a)
  -- Do not memoize secret colors. Equality checks on later plain numbers would
  -- otherwise incorrectly skip SetTextColor after the secure value resolves.
  fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = nil, nil, nil, nil
end

local function SetHealthTextSlotsColor(slots, count, setter, r, g, b, a)
  if not (slots and count and count > 0) then
    return false
  end
  for i = 1, count do
    local slot = slots[i]
    setter(slot and slot.fs, r, g, b, a)
  end
  return true
end

local function SetHealthTextColor(frame, rt, r, g, b, a)
  a = a or 1
  -- issecretvalue is authoritative for each component: a false result means the
  -- value is a plain Lua number and may be compared/memoized safely. Any secret
  -- component routes through the secret setter, which also clears the memo so a
  -- later plain tuple can never be skipped against a stale secret write.
  if issecretvalue(r) == true or issecretvalue(g) == true
    or issecretvalue(b) == true or issecretvalue(a) == true then
    if not SetHealthTextSlotsColor(rt and rt.healthSlots, rt and rt.healthSlotCount, SetHealthTextSlotColorSecret, r, g, b, a) then
      SetHealthTextSlotColorSecret(frame.hpTextLeft, r, g, b, a)
      SetHealthTextSlotColorSecret(frame.hpTextCenter, r, g, b, a)
      SetHealthTextSlotColorSecret(frame.hpTextRight, r, g, b, a)
    end
    frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = nil, nil, nil, nil
    return
  end
  if frame._msufHealthTextR == r
    and frame._msufHealthTextG == g
    and frame._msufHealthTextB == b
    and frame._msufHealthTextA == a then
    return
  end
  if not SetHealthTextSlotsColor(rt and rt.healthSlots, rt and rt.healthSlotCount, SetHealthTextSlotColor, r, g, b, a) then
    SetHealthTextSlotColor(frame.hpTextLeft, r, g, b, a)
    SetHealthTextSlotColor(frame.hpTextCenter, r, g, b, a)
    SetHealthTextSlotColor(frame.hpTextRight, r, g, b, a)
  end
  frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = r, g, b, a
end

local function BaseTextColor(frame)
  local spec = frame and frame.MSUFSpec
  local color = spec and spec.textColor
  return color and color.r or 1, color and color.g or 1, color and color.b or 1, color and color.a or 1
end

local function HealthGradientFromValues(frame, hp, hpMax)
  if nativeSecrets and (issecretvalue(hp) == true or issecretvalue(hpMax) == true) then
    -- Secret health values cannot be normalized safely. Fall back to the runtime
    -- color provider or the configured base text color.
    return nil
  end
  hp = tonumber(hp)
  hpMax = tonumber(hpMax)
  if not hp or not hpMax or hpMax <= 0 then
    return nil
  end
  local pct = hp / hpMax
  if pct < 0 then
    pct = 0
  elseif pct > 1 then
    pct = 1
  end
  local spec = frame and frame.MSUFSpec
  local health = spec and spec.health or nil
  local lr, lg, lb = health and health.gradientLowR or 1, health and health.gradientLowG or 0, health and health.gradientLowB or 0
  local mr, mg, mb = health and health.gradientMidR or 1, health and health.gradientMidG or 1, health and health.gradientMidB or 0
  local hr, hg, hb = health and health.gradientHighR or 0, health and health.gradientHighG or 1, health and health.gradientHighB or 0
  if pct <= 0.5 then
    local t = pct * 2
    return lr + (mr - lr) * t, lg + (mg - lg) * t, lb + (mb - lb) * t, 1
  end
  local t = (pct - 0.5) * 2
  return mr + (hr - mr) * t, mg + (hg - mg) * t, mb + (hb - mb) * t, 1
end

local function HealthTextColor(frame, unit, hp, hpMax, rt)
  local a = rt and rt.healthTextAlpha
  if frame and frame._msufHealthColorByHealth == true then
    local at = frame._msufGradStashAt
    if at and ((GetTime and GetTime() or 0) - at) < 0.2 then
      if a == nil then
        local _
        _, _, _, a = BaseTextColor(frame)
      end
      return frame._msufGradStashR, frame._msufGradStashG, frame._msufGradStashB, a
    end
  end
  local r, g, b, raw = GradientColor(unit, nil, frame)
  if raw == true then
    if a == nil then
      local _
      _, _, _, a = BaseTextColor(frame)
    end
    return r, g, b, a
  end
  if nativeSecrets ~= true then
    local gr, gg, gb = HealthGradientFromValues(frame, hp, hpMax)
    if gr then
      r, g, b = gr, gg, gb
    else
      r = nil
    end
  else
    r = nil
  end
  if r then
    if a == nil then
      local _
      _, _, _, a = BaseTextColor(frame)
    end
    return r, g, b, a
  end
  return BaseTextColor(frame)
end

local function UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
  if not (rt and frame) then
    return
  end
  if rt.healthColorByClass == true then
    local r, g, b = ClassColor(unit or frame.MSUFUnitKey)
    local a = rt.healthTextAlpha
    if a == nil then
      local _
      _, _, _, a = BaseTextColor(frame)
    end
    SetHealthTextColor(frame, rt, r, g, b, a)
    rt._textGradientPct = nil
    return
  end
  if rt.healthColorByHealth ~= true then return end
  -- Bucket non-secret health percentages to avoid text-color churn on every
  -- health tick while preserving exact updates for secret/runtime-only values.
  -- With native secrets present, plain values are detected via issecretvalue so
  -- fully-readable units keep the bucket fast path; secret values always take
  -- the exact update below.
  if (issecretvalue(hp) ~= true and issecretvalue(hpMax) ~= true)
    and type(hp) == "number" and type(hpMax) == "number" and hpMax > 0 then
    local bucket = floor((hp / hpMax) * 100 + 0.5)
    if rt._textGradientPct == bucket then
      return
    end
    SetHealthTextColor(frame, rt, HealthTextColor(frame, unit or frame.MSUFUnitKey, hp, hpMax, rt))
    rt._textGradientPct = bucket
    return
  end
  rt._textGradientPct = nil
  SetHealthTextColor(frame, rt, HealthTextColor(frame, unit or frame.MSUFUnitKey, hp, hpMax, rt))
end

local function SetNameTextColor(frame, r, g, b, a)
  a = a or 1
  if frame._msufNameTextR == r
    and frame._msufNameTextG == g
    and frame._msufNameTextB == b
    and frame._msufNameTextA == a then
    return
  end
  if frame.nameText then
    frame.nameText:SetTextColor(r, g, b, a)
  end
  if frame._msufNameDotsFS then
    frame._msufNameDotsFS:SetTextColor(r, g, b, a)
  end
  frame._msufNameTextR, frame._msufNameTextG, frame._msufNameTextB, frame._msufNameTextA = r, g, b, a
end

local function PlainUnitIsPlayer(frame, unit)
  if issecretvalue(unit) == true then
    return nil
  end
  local unitState = FreshUnitState and FreshUnitState(frame, unit)
  if unitState and unitState.isPlayerKnown == true then
    return unitState.isPlayer == true
  end
  local isPlayer, known = ReadUnitIsPlayerCached(frame, unit)
  if known == true then return isPlayer == true end
  return nil
end

local function DispatchClassColor(frame, unit, allowSecretPassThrough)
  local _, class = ReadUnitClassCached(frame, unit)
  if allowSecretPassThrough == true and issecretvalue(class) == true then
    return class, nil, nil, SECRET_DEPENDENT_CLASS_COLOR
  end
  local r, g, b = ClassColorForToken(class)
  if r ~= nil then return r, g, b end
  return 0.12, 0.62, 0.95
end

local function DispatchClassToken(frame, unit)
  local _, class = ReadUnitClassCached(frame, unit)
  return class
end

local function TextWantsNPCTypeColor(text)
  return text and text.npcColorMode == "type" and text.npcTypeColorText ~= false
end

local function NameTextColorFor(frame, unit, classNames, npcNames, keyOverride, npcClassNames)
  local spec = frame and frame.MSUFSpec
  local fallback = spec and spec.textColor
  local fr, fg, fb, fa = fallback and fallback.r or 1, fallback and fallback.g or 1, fallback and fallback.b or 1, fallback and fallback.a or 1
  if not classNames and not npcNames and not npcClassNames then
    return fr, fg, fb, fa
  end
  local isPlayer = PlainUnitIsPlayer(frame, unit)
  if isPlayer == nil then
    return fr, fg, fb, fa
  end
  if isPlayer then
    if classNames then
      local r, g, b, secretClass = DispatchClassColor(
        frame, unit, unit == "targettarget" or unit == "focustarget")
      return r, g, b, fa, secretClass
    end
  else
    if npcClassNames then
      local class = DispatchClassToken(frame, unit)
      if issecretvalue(class) ~= true and class then
        local r, g, b
        if ClassColorForToken then
          r, g, b = ClassColorForToken(class)
        end
        if r == nil then
          r, g, b = DispatchClassColor(frame, unit)
        end
        return r, g, b, fa
      end
    end
    if npcNames or npcClassNames then
      local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, keyOverride))
      return r, g, b, fa
    end
  end
  return fr, fg, fb, fa
end

local function NameTextColor(frame, unit)
  local spec = frame and frame.MSUFSpec
  local text = spec and spec.text or {}
  local override = text.nameColor
  local npcTypeColor = TextWantsNPCTypeColor(text)
  if type(override) == "table" and not npcTypeColor then
    return override.r or 1, override.g or 1, override.b or 1, override.a or 1
  end
  return NameTextColorFor(frame, unit, text.nameClassColor == true, text.nameNpcColor == true or npcTypeColor, nil, text.nameNpcClassColor == true)
end

local function SetInlineTextColor(frame, r, g, b, a)
  a = a or 1
  if frame._msufInlineTextR == r
    and frame._msufInlineTextG == g
    and frame._msufInlineTextB == b
    and frame._msufInlineTextA == a then
    return
  end
  if frame.totInlineText then
    frame.totInlineText:SetTextColor(r, g, b, a)
  end
  if frame._msufInlineDotsFS then
    frame._msufInlineDotsFS:SetTextColor(r, g, b, a)
  end
  frame._msufInlineTextR, frame._msufInlineTextG, frame._msufInlineTextB, frame._msufInlineTextA = r, g, b, a
end

local function InlineTextColor(frame, unit, inline)
  local spec = frame and frame.MSUFSpec
  local fallback = spec and spec.textColor
  local fr, fg, fb, fa = fallback and fallback.r or 1, fallback and fallback.g or 1, fallback and fallback.b or 1, fallback and fallback.a or 1
  local mode = inline and inline.colorMode or "AUTO"
  if mode == "DEFAULT" then
    return fr, fg, fb, fa
  elseif mode == "TARGET_NAME" then
    return NameTextColorFor(frame, frame.MSUFUnitKey, inline.targetNameClassColor == true, inline.targetNameNpcColor == true, nil, inline.targetNameNpcClassColor == true)
  elseif mode == "TOT_NAME" then
    return NameTextColorFor(frame, unit, inline.totNameClassColor == true, inline.totNameNpcColor == true, "targettarget", inline.totNameNpcClassColor == true)
  end

  local isPlayer = PlainUnitIsPlayer(frame, unit)
  if isPlayer == nil then
    return fr, fg, fb, fa
  end
  if mode == "NPC" then
    if not isPlayer then
      local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, "targettarget"))
      return r, g, b, fa
    end
    return fr, fg, fb, fa
  end
  if isPlayer then
    if inline and inline.targetNameClassColor == true then
      local r, g, b, secretClass = DispatchClassColor(
        frame, unit, unit == "targettarget" or unit == "focustarget")
      return r, g, b, fa, secretClass
    end
  else
    if inline and inline.targetNameNpcClassColor == true then
      local class = DispatchClassToken(frame, unit)
      if issecretvalue(class) ~= true and class then
        local r, g, b = DispatchClassColor(frame, unit)
        return r, g, b, fa
      end
    end
    if inline and (inline.targetNameNpcColor == true or inline.targetNameNpcClassColor == true) then
      local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, "targettarget"))
      return r, g, b, fa
    end
  end
  return fr, fg, fb, fa
end

local function ApplySecretClassTextColor(primary, secondary, class, alpha)
  local classColor = C_ClassColor_GetClassColor and C_ClassColor_GetClassColor(class)
  if not classColor then return false end
  -- Keep the secret RGB tuple only on this stack frame so both text regions
  -- share one native lookup. Do not inspect it or persist it in Lua caches.
  local r, g, b = classColor:GetRGB()
  if primary then primary:SetTextColor(r, g, b, alpha) end
  if secondary then secondary:SetTextColor(r, g, b, alpha) end
  return true
end

local function ApplyNameTextColor(frame, unit)
  local r, g, b, a, secretClass = NameTextColor(frame, unit)
  if secretClass == SECRET_DEPENDENT_CLASS_COLOR then
    if ApplySecretClassTextColor(frame and frame.nameText, frame and frame._msufNameDotsFS, r, a) then
      frame._msufNameTextR, frame._msufNameTextG, frame._msufNameTextB, frame._msufNameTextA = nil, nil, nil, nil
      return
    end
    r, g, b = 0.12, 0.62, 0.95
  end
  SetNameTextColor(frame, r, g, b, a)
end

local function ApplyInlineTextColor(frame, unit, inline)
  local r, g, b, a, secretClass = InlineTextColor(frame, unit, inline)
  if secretClass == SECRET_DEPENDENT_CLASS_COLOR then
    if ApplySecretClassTextColor(frame and frame.totInlineText, frame and frame._msufInlineDotsFS, r, a) then
      frame._msufInlineTextR, frame._msufInlineTextG, frame._msufInlineTextB, frame._msufInlineTextA = nil, nil, nil, nil
      return
    end
    r, g, b = 0.12, 0.62, 0.95
  end
  SetInlineTextColor(frame, r, g, b, a)
end
Text.C = C
Text.UF = UF
Text.Secrets = Secrets
Text.IsSecret = Secrets.IsSecret or function(_) return false end
Text.IsNil = Secrets.IsNil or function(value) return value == nil end
Text.ValueOrDefault = Secrets.ValueOrDefault or function(value, fallback)
  if value == nil then return fallback end
  return value
end
Text.CreateFrame = CreateFrame
Text.UnitClass = UnitClass
Text.UnitExists = UnitExists
Text.UnitHealth = UnitHealth
Text.UnitHealthMax = UnitHealthMax
Text.UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
Text.UnitPower = UnitPower
Text.UnitPowerMax = UnitPowerMax
Text.UnitPowerType = UnitPowerType
Text.UnitHealthPercent = UnitHealthPercent
Text.UnitPowerPercent = UnitPowerPercent
Text.AbbreviateNumbers = AbbreviateNumbers
Text.BreakUpLargeNumbers = BreakUpLargeNumbers
Text.AbbreviateLargeNumbers = AbbreviateLargeNumbers
Text.InCombatLockdown = InCombatLockdown
Text.UnitName = UnitName
Text.UnitIsPlayer = UnitIsPlayer
Text.UnitIsDeadOrGhost = UnitIsDeadOrGhost
Text.UnitIsConnected = UnitIsConnected
Text.UnitReaction = UnitReaction
Text.UnitSelectionColor = UnitSelectionColor
Text.PowerBarColor = PowerBarColor
Text.RAID_CLASS_COLORS = RAID_CLASS_COLORS
Text.type = type
Text.tonumber = tonumber
Text.format = format
Text.abs = abs
Text.floor = floor
Text.max = max
Text.GetTime = GetTime
Text.StatusBarInterpolation = StatusBarInterpolation
Text.SMOOTH_INTERP = SMOOTH_INTERP
Text.WHITE = WHITE
Text.SCALE_100 = SCALE_100
Text.ABSORB_HEALTH_MODE_BASE = ABSORB_HEALTH_MODE_BASE
Text.REVERSE_HEALTH_MODE = REVERSE_HEALTH_MODE
Text.EMPTY_EVENTS = EMPTY_EVENTS
Text.POWER_EVENTS = POWER_EVENTS
Text.POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT
Text.TEXT_EVENT_SETS = TEXT_EVENT_SETS
Text.TEXT_EVENT_SETS_ABSORB = TEXT_EVENT_SETS_ABSORB
Text.ClampFrameLayer = ClampFrameLayer
Text.DrawSubLayer = DrawSubLayer
Text.GetLayerBaseLevel = GetLayerBaseLevel
Text.SetStatusTexture = SetStatusTexture
Text.ApplyStatusColor = ApplyStatusColor
Text.SetBarMinMax = SetBarMinMax
Text.SetBarValue = SetBarValue
Text.SnapBarInterpolation = SnapBarInterpolation
Text.SetBarSmoothing = SetBarSmoothing
Text.ApplyTextureColor = ApplyTextureColor
Text.SetShownCached = SetShownCached
Text.SetFrameLevelCached = SetFrameLevelCached
Text.ExternalFrameWidth = ExternalFrameWidth
Text.ClassColor = ClassColor
Text.UnitNPCKind = UnitNPCKind
Text.NPCColor = NPCColor
Text.GradientColor = GradientColor
Text.HealthColor = HealthColor
Text.ApplyBackgrounds = ApplyBackgrounds
Text.PowerColor = PowerColor
Text.SetFont = SetFont
Text.ResolveRoleFont = ResolveRoleFont
Text.SetPowerTextColor = SetPowerTextColor
Text.SetHealthTextColor = SetHealthTextColor
Text.HealthTextColor = HealthTextColor
Text.UpdateHealthTextColor = UpdateHealthTextColor
Text.SetNameTextColor = SetNameTextColor
Text.NameTextColorFor = NameTextColorFor
Text.NameTextColor = NameTextColor
Text.ApplyNameTextColor = ApplyNameTextColor
Text.NPCTypeTextColorEnabled = TextWantsNPCTypeColor
Text.SetInlineTextColor = SetInlineTextColor
Text.InlineTextColor = InlineTextColor
Text.ApplyInlineTextColor = ApplyInlineTextColor
