--- UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua
--- Allocation-light formatting helpers for unitframe text strings.

local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

local Apply = MSUF.Apply or {}

-- Bind mandatory factories once; report both the consumer and received shape.
local function RequireFactory(key)
  local factories = MSUF.UFModuleFactories
  assert(type(factories) == "table", "Elements/MSUF_UF_Text_Format.lua: required UF factory registry for " .. key)
  local factory = factories[key]
  local kind = type(factory)
  assert(kind == "function", "Elements/MSUF_UF_Text_Format.lua: required UF provider " .. key .. " (expected function, got " .. kind .. ")")
  return factory
end
local luaType = type
-- SlotFormatted counts its varargs on every formatted text write.
local select = select
local UnitPowerType = Text.UnitPowerType
local ResolveDisplayedPowerIdentity = Text.ResolveDisplayedPowerIdentity
local UnitHealthPercent = Text.UnitHealthPercent
local UnitPowerPercent = Text.UnitPowerPercent
local AbbreviateShortNumber = Text.AbbreviateNumbers or _G.AbbreviateNumbers
local BreakUpLargeNumbers = Text.BreakUpLargeNumbers or _G.BreakUpLargeNumbers
local AbbreviateLargeNumber = Text.AbbreviateLargeNumbers or _G.AbbreviateLargeNumbers or _G.ShortenNumber
local AbbreviateSecretNumber = AbbreviateShortNumber or AbbreviateLargeNumber
--- Global abbreviation style: nil lets the client decide (locale-dependent),
--- a table switches the C abbreviator to MSUF's locale-independent breakpoints.
local NUM_OPTS = nil
do
  local NumberFormat = MSUF.NumberFormat
  if NumberFormat and NumberFormat.Register then
    NumberFormat.Register(function(options) NUM_OPTS = options end)
  end
end
local tonumber = Text.tonumber
local type = Text.type or luaType
local format = Text.format
local floor = Text.floor
local max = Text.max
local SCALE_100 = Text.SCALE_100
local ABSORB_HEALTH_MODE_BASE = Text.ABSORB_HEALTH_MODE_BASE or {}
--- What a text writer's change check keys on (rt.healthDispatchKeyMode and
--- rt.powerDispatchKeyMode): compiled here from the slots' modes, read on every
--- value update by Text_Runtime and the class power health text.
local DISPATCH_KEY = { NONE = 0, CURRENT = 1, MAX = 2, CURRENT_MAX = 3, PERCENT = 4, PERCENT_MAX = 5 }
Text.DISPATCH_KEY = DISPATCH_KEY
local REVERSE_HEALTH_MODE = Text.REVERSE_HEALTH_MODE
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue
local StringUtil = _G.C_StringUtil
local TruncateWhenZero = StringUtil and StringUtil.TruncateWhenZero
local WrapString = StringUtil and StringUtil.WrapString
local ABSORB_ICON_MARKUP = "|TInterface\\Icons\\INV_Shield_06:0|t"
local ApplyText = Apply.Text
local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

local function FiniteNumberOr(value, fallback)
  if type(value) == "number" then
    -- The type is already known. Avoid a second type query/helper call for
    -- every public health, power and percent value sent to a native formatter.
    return value == value and (value - value) == 0 and value or fallback
  end
  if value == nil then
    return fallback
  end
  local number = tonumber and tonumber(value) or nil
  return IsFiniteNumber(number) and number or fallback
end

local function FiniteNumberOrNil(value)
  return FiniteNumberOr(value, nil)
end

local INT_TEXT_0_100 = {}
local PERCENT_TEXT_0_100 = {}
local DECIMAL_TEXT_0_1000 = {}
local DECIMAL_PERCENT_TEXT_0_1000 = {}
-- Precompute the common 0..100 strings used by percent displays; this avoids rebuilding
-- identical strings during health/power updates across many frames.
for i = 0, 100 do
  local text = format("%d", i)
  INT_TEXT_0_100[i] = text
  PERCENT_TEXT_0_100[i] = text .. "%"
end

-- Decimal percentages are optional. Building 2,002 strings at login penalizes
-- every user even when no text slot enables decimal percentages. Cache each
-- representation on first use instead; the hot path still becomes a table read
-- after that value has appeared once.
local function DecimalPercentText(key, hideSymbol)
  local cache = hideSymbol and DECIMAL_TEXT_0_1000 or DECIMAL_PERCENT_TEXT_0_1000
  local text = cache[key]
  if text == nil then
    text = format("%.1f", key / 10)
    if not hideSymbol then text = text .. "%" end
    cache[key] = text
  end
  return text
end

local function SmallIntegerText(value)
  if type(value) == "number" and value >= 0 and value <= 100 then
    local n = floor(value)
    if n == value then
      return INT_TEXT_0_100[n]
    end
  end
  return nil
end

local function TruncateInteger(value)
  return value >= 0 and floor(value) or -floor(-value)
end

local function CompactNumber(value)
  if type(value) ~= "number" then
    value = tonumber(value) or 0
  end
  local sign = ""
  if value < 0 then
    sign = "-"
    value = -value
  end
  if value >= 1000000000 then
    local n = floor((value / 100000000) + 0.5) / 10
    if n >= 10 or n == floor(n) then
      return sign .. format("%dB", floor(n + 0.5))
    end
    return sign .. format("%.1fB", n)
  elseif value >= 1000000 then
    local n = floor((value / 100000) + 0.5) / 10
    if n >= 10 or n == floor(n) then
      return sign .. format("%dM", floor(n + 0.5))
    end
    return sign .. format("%.1fM", n)
  elseif value >= 1000 then
    local n = floor((value / 100) + 0.5) / 10
    if n >= 10 or n == floor(n) then
      return sign .. format("%dK", floor(n + 0.5))
    end
    return sign .. format("%.1fK", n)
  end
  return SmallIntegerText(value) or format("%d", value or 0)
end

local SPACED_DELIMITERS = {
  [""] = " ",
  ["-"] = " - ",
  ["/"] = " / ",
  ["\\"] = " \\ ",
  ["|"] = " | ",
  ["<"] = " < ",
  [">"] = " > ",
  ["~"] = " ~ ",
  [":"] = " : ",
}

local function NormalizeTextDelimiter(delimiter)
  if delimiter == nil then
    return " - "
  end
  return SPACED_DELIMITERS[delimiter] or delimiter
end

local function ValueArg(value, canSecret)
  if issecretvalue(value) == true then
    return value
  end
  return FiniteNumberOr(value, 0)
end

local function HealthPercent(unit)
  if not UnitHealthPercent or not SCALE_100 or type(unit) ~= "string" or unit == "" then
    return nil
  end
  local pct = UnitHealthPercent(unit, true, SCALE_100)
  if issecretvalue(pct) == true then
    return pct
  end
  return FiniteNumberOrNil(pct)
end

local function PowerPercent(unit)
  if not UnitPowerPercent or not SCALE_100 or type(unit) ~= "string" or unit == "" then
    return nil
  end
  local powerType, _, displayMana
  if unit == "player" and ResolveDisplayedPowerIdentity then
    powerType, _, displayMana = ResolveDisplayedPowerIdentity(unit)
  end
  if displayMana ~= true then
    powerType = UnitPowerType and UnitPowerType(unit) or nil
  end
  if issecretvalue(powerType) == true then powerType = nil end
  local pct = UnitPowerPercent(unit, powerType, false, SCALE_100)
  if issecretvalue(pct) == true then
    return pct
  end
  return FiniteNumberOrNil(pct)
end

local function NormalizePercentDecimals(decimals)
  decimals = tonumber(decimals) or 0
  return decimals >= 1 and 1 or 0
end

local MODE_NEEDS = {
  CURRENT = 1, FULLVALUE = 1, MAX = 2, CURMAX = 3, MAXCUR = 3,
  PERCENT = 4, CURPERCENT = 5, PERCENTCUR = 5,
  MAXPERCENT = 6, PERCENTMAX = 6,
  CURMAXPERCENT = 7, PERCENTMAXCUR = 7, PERCENTCURMAX = 7,
}

local function ModeNeedsPercent(mode)
  return (MODE_NEEDS[mode] or 0) >= 4
end

local function ModeNeedsCurrent(mode)
  return (MODE_NEEDS[mode] or 0) % 2 == 1
end

local function ModeNeedsMax(mode)
  return (MODE_NEEDS[mode] or 0) % 4 >= 2
end

local function FormatValue(value, short, canSecret)
  if issecretvalue(value) == true then
    if short then
      if AbbreviateSecretNumber then
        return AbbreviateSecretNumber(value, NUM_OPTS)
      end
    elseif BreakUpLargeNumbers then
      return BreakUpLargeNumbers(value)
    end
    return value
  end
  value = FiniteNumberOr(value, 0)
  if not short then
    if BreakUpLargeNumbers then
      return BreakUpLargeNumbers(value)
    end
    return SmallIntegerText(value) or format("%d", value or 0)
  end
  if AbbreviateShortNumber then
    return AbbreviateShortNumber(value, NUM_OPTS)
  end
  return CompactNumber(value)
end

local function FormatPercentValue(value, hideSymbol, canSecret, decimals)
  if issecretvalue(value) == true then
    return value
  end
  if value == nil then
    return nil
  end
  value = FiniteNumberOrNil(value)
  if value == nil then
    return nil
  end
  decimals = NormalizePercentDecimals(decimals)
  if decimals >= 1 and type(value) == "number" then
    local key = floor(value * 10 + 0.5)
    if key >= 0 and key <= 1000 then
      return DecimalPercentText(key, hideSymbol)
    end
    local text = format("%.1f", key / 10)
    return hideSymbol and text or (text .. "%")
  end
  local integer = TruncateInteger(value)
  local text = SmallIntegerText(integer) or format("%d", integer)
  if hideSymbol then
    return text
  end
  if integer >= 0 and integer <= 100 then
    return PERCENT_TEXT_0_100[integer]
  end
  return text .. "%"
end

local function SetTextCached(fs, text)
  ApplyText(fs, text)
end

local SetTextPlainCached = ApplyText

local function SlotText(slot, text)
  if slot.appendSuffix == true then
    SetTextCached(slot.fs, text .. slot.suffix)
  else
    SetTextCached(slot.fs, text)
  end
end

local function SlotTextPlain(slot, text)
  if slot.appendSuffix == true then
    SetTextPlainCached(slot.fs, text .. slot.suffix)
  else
    SetTextPlainCached(slot.fs, text)
  end
end

local function SlotFormatted(slot, pattern, ...)
  local fs = slot and slot.fs
  if not fs then
    return
  end
  fs._aText = nil
  fs._aTextPlain = nil
  if slot.appendSuffix == true then
    local suffix = slot.suffix
    local argc = select("#", ...)
    local a, b, c, d, e = ...
    pattern = pattern .. "%s"
    if argc >= 5 then
      fs:SetFormattedText(pattern, a, b, c, d, e, suffix)
    elseif argc == 4 then
      fs:SetFormattedText(pattern, a, b, c, d, suffix)
    elseif argc == 3 then
      fs:SetFormattedText(pattern, a, b, c, suffix)
    elseif argc == 2 then
      fs:SetFormattedText(pattern, a, b, suffix)
    elseif argc == 1 then
      fs:SetFormattedText(pattern, a, suffix)
    else
      fs:SetFormattedText(pattern, suffix)
    end
    return
  end
  fs:SetFormattedText(pattern, ...)
end

local function SlotValue(slot, value)
  return FormatValue(value, slot.short, slot.canSecret)
end

local function SlotPercent(slot, pct)
  return FormatPercentValue(pct, slot.hidePercentSymbol, slot.canSecret, slot.percentDecimals)
end

local function SlotValuePlain(slot, value)
  value = FiniteNumberOr(value, 0)
  if not slot.short then
    if BreakUpLargeNumbers then
      return BreakUpLargeNumbers(value or 0)
    end
    return SmallIntegerText(value) or format("%d", value or 0)
  end
  if AbbreviateShortNumber then
    return AbbreviateShortNumber(value or 0, NUM_OPTS)
  end
  return CompactNumber(value)
end

local function SlotPercentPlain(slot, pct)
  if pct == nil then
    return nil
  end
  pct = FiniteNumberOrNil(pct)
  if pct == nil then
    return nil
  end
  if NormalizePercentDecimals(slot.percentDecimals) >= 1 and type(pct) == "number" then
    local key = floor(pct * 10 + 0.5)
    if key >= 0 and key <= 1000 then
      return DecimalPercentText(key, slot.hidePercentSymbol)
    end
    local text = format("%.1f", key / 10)
    return slot.hidePercentSymbol and text or (text .. "%")
  end
  local integer = TruncateInteger(pct)
  if not slot.hidePercentSymbol and integer >= 0 and integer <= 100 then
    return PERCENT_TEXT_0_100[integer]
  end
  local text = SmallIntegerText(integer) or format("%d", integer)
  return slot.hidePercentSymbol and text or (text .. "%")
end

local function SlotFormattedValue(slot, value)
  if issecretvalue(value) == true then
    if slot.short and AbbreviateSecretNumber then
      return AbbreviateSecretNumber(value, NUM_OPTS), "%s"
    elseif (not slot.short) and BreakUpLargeNumbers then
      return BreakUpLargeNumbers(value), "%s"
    end
    return value, "%d"
  end
  return SlotValue(slot, value), "%s"
end

local function SlotFormattedPercent(slot, pct)
  if issecretvalue(pct) == true then
    if NormalizePercentDecimals(slot.percentDecimals) >= 1 then
      return ValueArg(pct, slot.canSecret), slot.hidePercentSymbol and "%.1f" or "%.1f%%"
    end
    return ValueArg(pct, slot.canSecret), slot.hidePercentSymbol and "%d" or "%d%%"
  end
  return SlotPercent(slot, pct), "%s"
end

local function WriteCurrent(slot, cur)
  if issecretvalue(cur) == true then
    local c, cf = SlotFormattedValue(slot, cur)
    SlotFormatted(slot, cf, c)
    return
  end
  SlotText(slot, SlotValue(slot, cur))
end

local function WriteMax(slot, cur, maxValue)
  if issecretvalue(maxValue) == true then
    local m, mf = SlotFormattedValue(slot, maxValue)
    SlotFormatted(slot, mf, m)
    return
  end
  SlotText(slot, SlotValue(slot, maxValue))
end

local function WriteCurMax(slot, cur, maxValue)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true then
    local c, cf = SlotFormattedValue(slot, cur)
    local m, mf = SlotFormattedValue(slot, maxValue)
    SlotFormatted(slot, cf .. "%s" .. mf, c, slot.delimiter, m)
    return
  end
  SlotText(slot, SlotValue(slot, cur) .. slot.delimiter .. SlotValue(slot, maxValue))
end

local function WriteMaxCur(slot, cur, maxValue)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true then
    local c, cf = SlotFormattedValue(slot, cur)
    local m, mf = SlotFormattedValue(slot, maxValue)
    SlotFormatted(slot, mf .. "%s" .. cf, m, slot.delimiter, c)
    return
  end
  SlotText(slot, SlotValue(slot, maxValue) .. slot.delimiter .. SlotValue(slot, cur))
end

local function WritePercent(slot, cur, maxValue, pct, pctKnown)
  if pctKnown and issecretvalue(pct) == true then
    local p, pf = SlotFormattedPercent(slot, pct)
    SlotFormatted(slot, pf, p)
    return
  end
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p or "")
end

local function WriteCurPercent(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(cur) == true or (pctKnown and issecretvalue(pct) == true) then
    local c, cf = SlotFormattedValue(slot, cur)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, cf .. "%s" .. pf, c, slot.delimiter, p)
    else
      SlotFormatted(slot, cf, c)
    end
    return
  end
  local c = SlotValue(slot, cur)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (c .. slot.delimiter .. p) or c)
end

local function WritePercentCur(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(cur) == true or (pctKnown and issecretvalue(pct) == true) then
    local c, cf = SlotFormattedValue(slot, cur)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, pf .. "%s" .. cf, p, slot.delimiter, c)
    else
      SlotFormatted(slot, cf, c)
    end
    return
  end
  local c = SlotValue(slot, cur)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (p .. slot.delimiter .. c) or c)
end

local function WriteCurMaxPercent(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true or (pctKnown and issecretvalue(pct) == true) then
    local c, cf = SlotFormattedValue(slot, cur)
    local m, mf = SlotFormattedValue(slot, maxValue)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, cf .. "%s" .. mf .. "%s" .. pf, c, slot.delimiter, m, slot.delimiter, p)
    else
      SlotFormatted(slot, cf .. "%s" .. mf, c, slot.delimiter, m)
    end
    return
  end
  local c = SlotValue(slot, cur)
  local m = SlotValue(slot, maxValue)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (c .. slot.delimiter .. m .. slot.delimiter .. p) or (c .. slot.delimiter .. m))
end

local function WritePercentMaxCur(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true or (pctKnown and issecretvalue(pct) == true) then
    local c, cf = SlotFormattedValue(slot, cur)
    local m, mf = SlotFormattedValue(slot, maxValue)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, pf .. "%s" .. mf .. "%s" .. cf, p, slot.delimiter, m, slot.delimiter, c)
    else
      SlotFormatted(slot, mf .. "%s" .. cf, m, slot.delimiter, c)
    end
    return
  end
  local c = SlotValue(slot, cur)
  local m = SlotValue(slot, maxValue)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (p .. slot.delimiter .. m .. slot.delimiter .. c) or (m .. slot.delimiter .. c))
end

local function WriteMaxPercent(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(maxValue) == true or (pctKnown and issecretvalue(pct) == true) then
    local m, mf = SlotFormattedValue(slot, maxValue)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, mf .. "%s" .. pf, m, slot.delimiter, p)
    else
      SlotFormatted(slot, mf, m)
    end
    return
  end
  local m = SlotValue(slot, maxValue)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (m .. slot.delimiter .. p) or m)
end

local function WritePercentMax(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(maxValue) == true or (pctKnown and issecretvalue(pct) == true) then
    local m, mf = SlotFormattedValue(slot, maxValue)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, pf .. "%s" .. mf, p, slot.delimiter, m)
    else
      SlotFormatted(slot, mf, m)
    end
    return
  end
  local m = SlotValue(slot, maxValue)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (p .. slot.delimiter .. m) or m)
end

local function WritePercentCurMax(slot, cur, maxValue, pct, pctKnown)
  if issecretvalue(cur) == true or issecretvalue(maxValue) == true or (pctKnown and issecretvalue(pct) == true) then
    local c, cf = SlotFormattedValue(slot, cur)
    local m, mf = SlotFormattedValue(slot, maxValue)
    if pctKnown then
      local p, pf = SlotFormattedPercent(slot, pct)
      SlotFormatted(slot, pf .. "%s" .. cf .. "%s" .. mf, p, slot.delimiter, c, slot.delimiter, m)
    else
      SlotFormatted(slot, cf .. "%s" .. mf, c, slot.delimiter, m)
    end
    return
  end
  local c = SlotValue(slot, cur)
  local m = SlotValue(slot, maxValue)
  local p = pctKnown and SlotPercent(slot, pct) or nil
  SlotText(slot, p and (p .. slot.delimiter .. c .. slot.delimiter .. m) or (c .. slot.delimiter .. m))
end

local function WriteDeficit(slot, cur, maxValue, pct, pctKnown, rt)
  local missing = rt and rt.healthMissing
  if issecretvalue(missing) == true then
    local value, valueFormat = SlotFormattedValue(slot, missing)
    SlotFormatted(slot, "-" .. valueFormat, value)
    return
  end
  if missing ~= nil then
    SlotText(slot, "-" .. (FormatValue(missing, slot.short, slot.canSecret) or "0"))
    return
  end
  SlotText(slot, "")
end

-- WriteDeficit rationale: docs/uf-responsibility-notes.md.
local ABSORB_SECRET_LINK = "|Hmsufabsorb:"

local function SecretAbsorbText(slot, absorb, prefix)
  local body = WrapString(FormatValue(absorb, slot.short, slot.canSecret),
    prefix and ("|h" .. prefix) or "|h", "|h")
  return WrapString(TruncateWhenZero(absorb), ABSORB_SECRET_LINK, body)
end

local function AbsorbDisplayText(slot, absorb, combined, plain)
  local secret = issecretvalue(absorb) == true
  if not secret and absorb == nil then return "" end
  local prefix
  if combined then
    prefix = slot.absorbIcon and (" + " .. ABSORB_ICON_MARKUP .. " ") or " + "
  elseif slot.absorbIcon then
    prefix = ABSORB_ICON_MARKUP .. " "
  end
  if secret then
    -- Mirrors FormatValue's own secret branch: without the matching C formatter
    -- it hands back the raw secret number, which cannot ride in the link body.
    local secretFormatter = AbbreviateSecretNumber
    if not slot.short then secretFormatter = BreakUpLargeNumbers end
    if secretFormatter and TruncateWhenZero and WrapString then
      return SecretAbsorbText(slot, absorb, prefix)
    end
    if TruncateWhenZero then
      local text = TruncateWhenZero(absorb)
      if prefix and WrapString then return WrapString(text, prefix, "") end
      return text
    end
    return FormatValue(absorb, slot.short, slot.canSecret)
  end
  absorb = FiniteNumberOr(absorb, 0)
  if absorb <= 0 then return "" end
  local text = plain and SlotValuePlain(slot, absorb) or (FormatValue(absorb, slot.short, slot.canSecret) or "")
  return prefix and (prefix .. text) or text
end

local function WriteAbsorb(slot, cur, maxValue, pct, pctKnown, rt)
  SlotText(slot, AbsorbDisplayText(slot, rt and rt.healthAbsorb, false, false))
end

local function WriteAbsorbCombined(slot, cur, maxValue, pct, pctKnown, rt)
  slot.suffix = AbsorbDisplayText(slot, rt and rt.healthAbsorb, true, false)
  slot.appendSuffix = true
  slot.absorbBaseWriter(slot, cur, maxValue, pct, pctKnown, rt)
  slot.appendSuffix = false
  slot.suffix = nil
end

local MODE_WRITERS = {
  CURRENT = WriteCurrent,
  FULLVALUE = WriteCurrent,
  MAX = WriteMax,
  CURMAX = WriteCurMax,
  MAXCUR = WriteMaxCur,
  PERCENT = WritePercent,
  CURPERCENT = WriteCurPercent,
  PERCENTCUR = WritePercentCur,
  CURMAXPERCENT = WriteCurMaxPercent,
  PERCENTMAXCUR = WritePercentMaxCur,
  MAXPERCENT = WriteMaxPercent,
  PERCENTMAX = WritePercentMax,
  PERCENTCURMAX = WritePercentCurMax,
  DEFICIT = WriteDeficit,
  ABSORB = WriteAbsorb,
}

local function PlainWriteCurrent(slot, cur)
  SlotTextPlain(slot, SlotValuePlain(slot, cur))
end

local function PlainWriteMax(slot, cur, maxValue)
  SlotTextPlain(slot, SlotValuePlain(slot, maxValue))
end

local function PlainWriteCurMax(slot, cur, maxValue)
  SlotTextPlain(slot, SlotValuePlain(slot, cur) .. slot.delimiter .. SlotValuePlain(slot, maxValue))
end

local function PlainWriteMaxCur(slot, cur, maxValue)
  SlotTextPlain(slot, SlotValuePlain(slot, maxValue) .. slot.delimiter .. SlotValuePlain(slot, cur))
end

local function PlainWritePercent(slot, cur, maxValue, pct, pctKnown)
  SlotTextPlain(slot, pctKnown and SlotPercentPlain(slot, pct) or "")
end

local function PlainWriteCurPercent(slot, cur, maxValue, pct, pctKnown)
  local c = SlotValuePlain(slot, cur)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (c .. slot.delimiter .. p) or c)
end

local function PlainWritePercentCur(slot, cur, maxValue, pct, pctKnown)
  local c = SlotValuePlain(slot, cur)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (p .. slot.delimiter .. c) or c)
end

local function PlainWriteCurMaxPercent(slot, cur, maxValue, pct, pctKnown)
  local c = SlotValuePlain(slot, cur)
  local m = SlotValuePlain(slot, maxValue)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (c .. slot.delimiter .. m .. slot.delimiter .. p) or (c .. slot.delimiter .. m))
end

local function PlainWritePercentMaxCur(slot, cur, maxValue, pct, pctKnown)
  local c = SlotValuePlain(slot, cur)
  local m = SlotValuePlain(slot, maxValue)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (p .. slot.delimiter .. m .. slot.delimiter .. c) or (m .. slot.delimiter .. c))
end

local function PlainWriteMaxPercent(slot, cur, maxValue, pct, pctKnown)
  local m = SlotValuePlain(slot, maxValue)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (m .. slot.delimiter .. p) or m)
end

local function PlainWritePercentMax(slot, cur, maxValue, pct, pctKnown)
  local m = SlotValuePlain(slot, maxValue)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (p .. slot.delimiter .. m) or m)
end

local function PlainWritePercentCurMax(slot, cur, maxValue, pct, pctKnown)
  local c = SlotValuePlain(slot, cur)
  local m = SlotValuePlain(slot, maxValue)
  local p = pctKnown and SlotPercentPlain(slot, pct) or nil
  SlotTextPlain(slot, p and (p .. slot.delimiter .. c .. slot.delimiter .. m) or (c .. slot.delimiter .. m))
end

local function PlainWriteDeficit(slot, cur, maxValue, pct, pctKnown, rt)
  local missing = rt and rt.healthMissing
  if missing ~= nil then
    SlotTextPlain(slot, "-" .. (SlotValuePlain(slot, missing) or "0"))
    return
  end
  SlotTextPlain(slot, "")
end

local function PlainWriteAbsorb(slot, cur, maxValue, pct, pctKnown, rt)
  SlotTextPlain(slot, AbsorbDisplayText(slot, rt and rt.healthAbsorb, false, true))
end

local function PlainWriteAbsorbCombined(slot, cur, maxValue, pct, pctKnown, rt)
  slot.suffix = AbsorbDisplayText(slot, rt and rt.healthAbsorb, true, true)
  slot.appendSuffix = true
  slot.absorbBasePlainWriter(slot, cur, maxValue, pct, pctKnown, rt)
  slot.appendSuffix = false
  slot.suffix = nil
end

local MODE_PLAIN_WRITERS = {
  CURRENT = PlainWriteCurrent,
  FULLVALUE = PlainWriteCurrent,
  MAX = PlainWriteMax,
  CURMAX = PlainWriteCurMax,
  MAXCUR = PlainWriteMaxCur,
  PERCENT = PlainWritePercent,
  CURPERCENT = PlainWriteCurPercent,
  PERCENTCUR = PlainWritePercentCur,
  CURMAXPERCENT = PlainWriteCurMaxPercent,
  PERCENTMAXCUR = PlainWritePercentMaxCur,
  MAXPERCENT = PlainWriteMaxPercent,
  PERCENTMAX = PlainWritePercentMax,
  PERCENTCURMAX = PlainWritePercentCurMax,
  DEFICIT = PlainWriteDeficit,
  ABSORB = PlainWriteAbsorb,
}

local SECRET_MODE_CODES = {
  CURRENT = 1,
  FULLVALUE = 1,
  MAX = 2,
  CURMAX = 3,
  MAXCUR = 4,
  PERCENT = 5,
  CURPERCENT = 6,
  PERCENTCUR = 7,
  CURMAXPERCENT = 8,
  PERCENTMAXCUR = 9,
  MAXPERCENT = 10,
  PERCENTMAX = 11,
  PERCENTCURMAX = 12,
}

local SECRET_NEEDS_CUR = { [1] = true, [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true, [12] = true }
local SECRET_NEEDS_MAX = { [2] = true, [3] = true, [4] = true, [8] = true, [9] = true, [10] = true, [11] = true, [12] = true }
local SECRET_NEEDS_PCT = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true, [12] = true }
-- Retain the compiled setter contract for cold-path consumers and smoke tests.
-- The hot secret writer below emits the native call directly.
local SECRET_SETTERS = {
  function(fs, pattern, cur) fs:SetFormattedText(pattern, cur) end,
  function(fs, pattern, _, maxValue) fs:SetFormattedText(pattern, maxValue) end,
  function(fs, pattern, cur, maxValue, _, delimiter) fs:SetFormattedText(pattern, cur, delimiter, maxValue) end,
  function(fs, pattern, cur, maxValue, _, delimiter) fs:SetFormattedText(pattern, maxValue, delimiter, cur) end,
  function(fs, pattern, _, _, pct) fs:SetFormattedText(pattern, pct) end,
  function(fs, pattern, cur, _, pct, delimiter) fs:SetFormattedText(pattern, cur, delimiter, pct) end,
  function(fs, pattern, cur, _, pct, delimiter) fs:SetFormattedText(pattern, pct, delimiter, cur) end,
  function(fs, pattern, cur, maxValue, pct, delimiter) fs:SetFormattedText(pattern, cur, delimiter, maxValue, delimiter, pct) end,
  function(fs, pattern, cur, maxValue, pct, delimiter) fs:SetFormattedText(pattern, pct, delimiter, maxValue, delimiter, cur) end,
  function(fs, pattern, _, maxValue, pct, delimiter) fs:SetFormattedText(pattern, maxValue, delimiter, pct) end,
  function(fs, pattern, _, maxValue, pct, delimiter) fs:SetFormattedText(pattern, pct, delimiter, maxValue) end,
  function(fs, pattern, cur, maxValue, pct, delimiter) fs:SetFormattedText(pattern, pct, delimiter, cur, delimiter, maxValue) end,
}

local function CompileCurrentPercentWriter(slot)
  local fs = slot.fs
  local fn = slot.secretValueFn
  local abbreviates = slot.short == true
  local code = slot.secretCode
  local pattern = slot.secretPattern
  local delimiter = slot.delimiter
    if fn and abbreviates then
      -- Bind the two frequent native formats without adding a dispatch/helper
      -- call per write. Only values and the live number style vary at runtime.
      if code == 6 then
        return function(_, cur, _, pct, _, _, curSecret, _, pctSecret)
          if curSecret == nil then curSecret = issecretvalue(cur) == true end
          if pctSecret == nil then pctSecret = issecretvalue(pct) == true end
          cur = curSecret == true and fn(cur, NUM_OPTS) or fn(FiniteNumberOr(cur, 0), NUM_OPTS)
          if pctSecret ~= true then pct = FiniteNumberOr(pct, 0) end
          fs._aText, fs._aTextPlain = nil, nil
          fs:SetFormattedText(pattern, cur, delimiter, pct)
        end
      end
      return function(_, cur, _, pct, _, _, curSecret, _, pctSecret)
        if curSecret == nil then curSecret = issecretvalue(cur) == true end
        if pctSecret == nil then pctSecret = issecretvalue(pct) == true end
        cur = curSecret == true and fn(cur, NUM_OPTS) or fn(FiniteNumberOr(cur, 0), NUM_OPTS)
        if pctSecret ~= true then pct = FiniteNumberOr(pct, 0) end
        fs._aText, fs._aTextPlain = nil, nil
        fs:SetFormattedText(pattern, pct, delimiter, cur)
      end
    end
    -- Current + percent is a common two-value slot. Its maximum is unused, so
    -- compile that fact instead of walking the general three-value dispatcher.
    -- Number-style options stay live, as in the single-value writers above.
    local currentFirst = code == 6
    return function(_, cur, _, pct, _, _, curSecret, _, pctSecret)
      if curSecret == nil then curSecret = issecretvalue(cur) == true end
      if pctSecret == nil then pctSecret = issecretvalue(pct) == true end
      if fn then
        local opts = abbreviates and NUM_OPTS or nil
        cur = curSecret == true and fn(cur, opts) or fn(FiniteNumberOr(cur, 0), opts)
      elseif curSecret ~= true then
        cur = FiniteNumberOr(cur, 0)
      end
      if pctSecret ~= true then pct = FiniteNumberOr(pct, 0) end
      fs._aText, fs._aTextPlain = nil, nil
      if currentFirst then fs:SetFormattedText(pattern, cur, delimiter, pct)
      else fs:SetFormattedText(pattern, pct, delimiter, cur) end
    end
end

local function CompileSecretWriter(slot)
  local code = slot.secretCode
  if code == 6 or code == 7 then return CompileCurrentPercentWriter(slot) end
  local fs = slot.fs
  local fn = slot.secretValueFn
  -- Only the short slot abbreviates; the long slot runs BreakUpLargeNumbers,
  -- which takes no abbreviation options. Reading NUM_OPTS inside the closure
  -- (instead of binding it here) keeps compiled slots correct after a style
  -- change without a recompile pass.
  local abbreviates = slot.short == true
  local pattern = slot.secretPattern
  local delimiter = slot.delimiter

  -- A single-value slot has no runtime format dispatch or unused value needs.
  if code == 1 then
    -- Native number formatters already return a string. For an exact "%s"
    -- slot, SetText accepts that same opaque result without formatting it again.
    -- Select this at compile time; numeric fallbacks keep their original writer.
    if fn and pattern == "%s" then
      if abbreviates then
        -- This is the common CURRENT slot. Keep style options live while
        -- selecting the short-number contract only when the slot is compiled.
        return function(_, cur, _, _, _, _, curSecret)
          if curSecret == nil then curSecret = issecretvalue(cur) == true end
          cur = curSecret == true and fn(cur, NUM_OPTS) or fn(FiniteNumberOr(cur, 0), NUM_OPTS)
          fs._aText, fs._aTextPlain = nil, nil
          fs:SetText(cur)
        end
      end
      return function(_, cur, _, _, _, _, curSecret)
        if curSecret == nil then curSecret = issecretvalue(cur) == true end
        cur = curSecret == true and fn(cur, nil) or fn(FiniteNumberOr(cur, 0), nil)
        fs._aText, fs._aTextPlain = nil, nil
        fs:SetText(cur)
      end
    end
    return function(_, cur, _, _, _, _, curSecret)
      if curSecret == nil then curSecret = issecretvalue(cur) == true end
      if fn then
        local opts = abbreviates and NUM_OPTS or nil
        cur = curSecret == true and fn(cur, opts) or fn(FiniteNumberOr(cur, 0), opts)
      elseif curSecret ~= true then
        cur = FiniteNumberOr(cur, 0)
      end
      fs._aText, fs._aTextPlain = nil, nil
      fs:SetFormattedText(pattern, cur)
    end
  elseif code == 2 then
    if fn and pattern == "%s" then
      if abbreviates then
        return function(_, _, maxValue, _, _, _, _, maxSecret)
          if maxSecret == nil then maxSecret = issecretvalue(maxValue) == true end
          maxValue = maxSecret == true and fn(maxValue, NUM_OPTS) or fn(FiniteNumberOr(maxValue, 0), NUM_OPTS)
          fs._aText, fs._aTextPlain = nil, nil
          fs:SetText(maxValue)
        end
      end
      return function(_, _, maxValue, _, _, _, _, maxSecret)
        if maxSecret == nil then maxSecret = issecretvalue(maxValue) == true end
        maxValue = maxSecret == true and fn(maxValue, nil) or fn(FiniteNumberOr(maxValue, 0), nil)
        fs._aText, fs._aTextPlain = nil, nil
        fs:SetText(maxValue)
      end
    end
    return function(_, _, maxValue, _, _, _, _, maxSecret)
      if maxSecret == nil then maxSecret = issecretvalue(maxValue) == true end
      if fn then
        local opts = abbreviates and NUM_OPTS or nil
        maxValue = maxSecret == true and fn(maxValue, opts) or fn(FiniteNumberOr(maxValue, 0), opts)
      elseif maxSecret ~= true then
        maxValue = FiniteNumberOr(maxValue, 0)
      end
      fs._aText, fs._aTextPlain = nil, nil
      fs:SetFormattedText(pattern, maxValue)
    end
  elseif code == 5 then
    return function(_, _, _, pct, _, _, _, _, pctSecret)
      if pctSecret == nil then pctSecret = issecretvalue(pct) == true end
      if pctSecret ~= true then pct = FiniteNumberOr(pct, 0) end
      fs._aText, fs._aTextPlain = nil, nil
      fs:SetFormattedText(pattern, pct)
    end
  end

  local needsCur = slot.secretNeedsCur
  local needsMax = slot.secretNeedsMax
  local needsPct = slot.secretNeedsPct
  return function(_, cur, maxValue, pct, _, _, curSecret, maxSecret, pctSecret)
    if needsCur and curSecret == nil then curSecret = issecretvalue(cur) == true end
    if needsMax and maxSecret == nil then maxSecret = issecretvalue(maxValue) == true end
    if needsPct and pctSecret == nil then pctSecret = issecretvalue(pct) == true end
    if fn then
      local opts = abbreviates and NUM_OPTS or nil
      if needsCur then
        cur = curSecret == true and fn(cur, opts) or fn(FiniteNumberOr(cur, 0), opts)
      end
      if needsMax then
        maxValue = maxSecret == true and fn(maxValue, opts) or fn(FiniteNumberOr(maxValue, 0), opts)
      end
    else
      if needsCur and curSecret ~= true then cur = FiniteNumberOr(cur, 0) end
      if needsMax and maxSecret ~= true then maxValue = FiniteNumberOr(maxValue, 0) end
    end
    if needsPct and pctSecret ~= true then pct = FiniteNumberOr(pct, 0) end
    fs._aText = nil
    fs._aTextPlain = nil
    -- The format mode is fixed when the slot is compiled. Dispatching the
    -- native call here avoids a second Lua function call for every secret text
    -- write while retaining one shared normalization path for all modes.
    if code == 3 then
      fs:SetFormattedText(pattern, cur, delimiter, maxValue)
    elseif code == 4 then
      fs:SetFormattedText(pattern, maxValue, delimiter, cur)
    elseif code == 8 then
      fs:SetFormattedText(pattern, cur, delimiter, maxValue, delimiter, pct)
    elseif code == 9 then
      fs:SetFormattedText(pattern, pct, delimiter, maxValue, delimiter, cur)
    elseif code == 10 then
      fs:SetFormattedText(pattern, maxValue, delimiter, pct)
    elseif code == 11 then
      fs:SetFormattedText(pattern, pct, delimiter, maxValue)
    else
      fs:SetFormattedText(pattern, pct, delimiter, cur, delimiter, maxValue)
    end
  end
end

local function SetModeText(fs, mode, cur, max, delimiter, unit, percentFn, short, hidePercentSymbol, pctOverride, pctOverrideSet, suffix, canSecret, percentDecimals)
  if not fs then
    return
  end
  mode = mode or "NONE"
  if mode == "NONE" then
    SetTextCached(fs, "")
    return
  end
  delimiter = NormalizeTextDelimiter(delimiter)
  local pct
  local pctKnown = false
  if ModeNeedsPercent(mode) then
    if pctOverrideSet then
      pct = pctOverride
    else
      pct = percentFn and percentFn(unit)
    end
    pctKnown = issecretvalue(pct) == true or pct ~= nil
  end

  local slot = Text._modeTextSlot
  if not slot then
    slot = {}
    Text._modeTextSlot = slot
  end
  slot.fs = fs
  slot.delimiter = delimiter
  slot.short = short == true
  slot.hidePercentSymbol = hidePercentSymbol == true
  slot.percentDecimals = NormalizePercentDecimals(percentDecimals)
  slot.suffix = suffix
  slot.appendSuffix = suffix ~= nil
  slot.canSecret = canSecret
  local writer = MODE_WRITERS[mode] or WriteCurMax
  writer(slot, cur, max, pct, pctKnown, nil)
  slot.fs = nil
end

local function ResolveHealthTextModes(text)
  text = text or {}
  local healthLeft = text.healthLeft
  local healthCenter = text.healthCenter
  local healthRight = text.healthRight
  -- Same nil/false distinction the absorb icons below already make: a per-slot
  -- false is an explicit "show the % sign" and must win over the global flag,
  -- which `slot ~= nil and slot == true or fallback` collapsed back to hidden.
  local fallbackHide = text.hidePercentSymbol == true
  local hideLeft, hideCenter, hideRight =
    text.healthLeftHidePercentSymbol, text.healthCenterHidePercentSymbol, text.healthRightHidePercentSymbol
  if hideLeft == nil then hideLeft = fallbackHide else hideLeft = hideLeft == true end
  if hideCenter == nil then hideCenter = fallbackHide else hideCenter = hideCenter == true end
  if hideRight == nil then hideRight = fallbackHide else hideRight = hideRight == true end
  local iconLeft, iconCenter, iconRight = text.healthLeftAbsorbIcon, text.healthCenterAbsorbIcon, text.healthRightAbsorbIcon
  if iconLeft == nil then iconLeft = text.healthAbsorbIcon == true else iconLeft = iconLeft == true end
  if iconCenter == nil then iconCenter = text.healthAbsorbIcon == true else iconCenter = iconCenter == true end
  if iconRight == nil then iconRight = text.healthAbsorbIcon == true else iconRight = iconRight == true end
  if text.healthReverse == true then
    healthLeft, healthRight = healthRight, healthLeft
    hideLeft, hideRight = hideRight, hideLeft
    iconLeft, iconRight = iconRight, iconLeft
    healthLeft = REVERSE_HEALTH_MODE[healthLeft] or healthLeft
    healthCenter = REVERSE_HEALTH_MODE[healthCenter] or healthCenter
    healthRight = REVERSE_HEALTH_MODE[healthRight] or healthRight
  end
  return healthLeft, healthCenter, healthRight, hideLeft, hideCenter, hideRight, iconLeft, iconCenter, iconRight
end

local AddTextSlot, CompileTextRuntime, TrimTextSlots
AddTextSlot, CompileTextRuntime, TrimTextSlots = RequireFactory("TextSlotCompile")(
  ABSORB_HEALTH_MODE_BASE, AbbreviateSecretNumber, BreakUpLargeNumbers, CompileSecretWriter, DISPATCH_KEY, MODE_PLAIN_WRITERS,
    MODE_WRITERS, ModeNeedsCurrent, ModeNeedsMax, ModeNeedsPercent, NormalizePercentDecimals, NormalizeTextDelimiter,
    PlainWriteAbsorbCombined, PlainWriteCurMax, ResolveHealthTextModes, SECRET_MODE_CODES, SECRET_NEEDS_CUR, SECRET_NEEDS_MAX,
    SECRET_NEEDS_PCT, SECRET_SETTERS, Text, WriteAbsorbCombined, WriteCurMax, floor, max, nativeSecrets, tonumber
)

local function UpdateTextSlots(slots, count, cur, max, unit, percentFn, needsPercent, rt)
  if not slots or not count or count <= 0 then
    return
  end
  local pct
  local pctKnown = false
  if needsPercent == true then
    pct = percentFn and percentFn(unit)
    pctKnown = issecretvalue(pct) == true or pct ~= nil
  end
  for i = 1, count do
    local slot = slots[i]
    if slot then
      local writer = slot.writer
      if writer then
        writer(slot, cur, max, pct, pctKnown, rt)
      end
    end
  end
end

local UpdateTextSlotsSecret

local function UpdateTextSlotsPlain(slots, count, cur, max, unit, percentFn, needsPercent, rt, pctOverride, pctOverrideSet)
  if not slots or not count or count <= 0 then
    return
  end
  if nativeSecrets and (issecretvalue(cur) == true
    or issecretvalue(max) == true
    or (rt and issecretvalue(rt.healthMissing) == true)) then
    return UpdateTextSlotsSecret(slots, count, cur, max, unit, percentFn, needsPercent, rt, pctOverride, pctOverrideSet)
  end
  local pct
  local pctKnown = false
  if needsPercent == true and percentFn then
    if pctOverrideSet == true then
      pct = pctOverride
    else
      pct = percentFn(unit)
    end
    if issecretvalue(pct) == true then
      return UpdateTextSlotsSecret(slots, count, cur, max, unit, percentFn, needsPercent, rt, pct, true)
    end
    pctKnown = pct ~= nil
  end
  for i = 1, count do
    local slot = slots[i]
    if slot then
      local writer = slot.plainWriter
      if writer then
        writer(slot, cur, max, pct, pctKnown, rt)
      end
    end
  end
end

UpdateTextSlotsSecret = function(slots, count, cur, max, unit, percentFn, needsPercent, rt, pctOverride, pctOverrideSet, curSecret, maxSecret)
  if not slots or not count or count <= 0 then
    return
  end
  local pct
  if needsPercent == true and percentFn then
    if pctOverrideSet == true then
      pct = pctOverride
    else
      pct = percentFn(unit)
    end
  end
  -- Runtime readers can pass the classification of these exact values. It is
  -- local to this synchronous write, never retained across events or rereads.
  -- Standalone slot callers still classify their own inputs once here.
  if curSecret == nil then curSecret = issecretvalue(cur) == true end
  if maxSecret == nil then maxSecret = issecretvalue(max) == true end
  local pctSecret = needsPercent == true and issecretvalue(pct) == true or false
  local pctKnown = needsPercent == true and (pctSecret or pct ~= nil)
  for i = 1, count do
    local slot = slots[i]
    if slot then
      local writer = slot.secretWriter
      if writer then
        writer(slot, cur, max, pct, true, rt, curSecret, maxSecret, pctSecret)
      else
        writer = slot.writer
        if writer then
          writer(slot, cur, max, pct, pctKnown, rt)
        end
      end
    end
  end
end

Text.HealthPercent = HealthPercent
Text.PowerPercent = PowerPercent
Text.ModeNeedsPercent = ModeNeedsPercent
Text.SetTextCached = SetTextCached
Text.SetModeText = SetModeText
Text.ResolveHealthTextModes = ResolveHealthTextModes
Text.AddTextSlot = AddTextSlot
Text.TrimTextSlots = TrimTextSlots
Text.CompileTextRuntime = CompileTextRuntime
Text.UpdateTextSlots = UpdateTextSlots
Text.UpdateTextSlotsPlain = UpdateTextSlotsPlain
Text.UpdateTextSlotsSecret = UpdateTextSlotsSecret

-- Return-value callers cannot use the native FontString writer. GROUP explicitly
-- preserves its public preview contract (aliases stay unknown, missing percent
-- falls back to current, FULLVALUE follows short, and secrets stay opaque).
function Text.FormatValue(value, short, canSecret, compatibility)
    if compatibility ~= "GROUP" then return FormatValue(value, short, canSecret) end
    local secret = issecretvalue(value) == true
    if not secret and value == nil then return "0" end
    local fn = short and (AbbreviateShortNumber or AbbreviateLargeNumber)
        or (BreakUpLargeNumbers or AbbreviateShortNumber or AbbreviateLargeNumber)
    if secret then
        if fn then return fn(value, short and NUM_OPTS or nil) end
        return value
    end
    value = tonumber(value) or 0
    -- GF's native fallback order and unbounded public numeric inputs differ.
    if not fn then return tostring(value) end
    if (short and not AbbreviateShortNumber) or (not short and not BreakUpLargeNumbers)
        or not IsFiniteNumber(value) then
        return fn(value, short and NUM_OPTS or nil)
    end
    return FormatValue(value, short, canSecret)
end

local RoundToNearestString = StringUtil and StringUtil.RoundToNearestString
local UnitHealthMissing = _G.UnitHealthMissing
local UnitGetTotalAbsorbs = Text.UnitGetTotalAbsorbs
function Text.FormatPercentValue(value, hideSymbol, canSecret, decimals, compatibility)
    if compatibility ~= "GROUP" then return FormatPercentValue(value, hideSymbol, canSecret, decimals) end
    if issecretvalue(value) == true then
        if RoundToNearestString then return RoundToNearestString(value) .. (hideSymbol and "" or "%"), true end
        return nil, false
    end
    value = tonumber(value)
    if value == nil then return nil, false end
    if decimals ~= 1 then value, decimals = floor(value + 0.5), 0 end
    -- GROUP used number concatenation, not %d's signed native integer range.
    -- Keep unbounded public previews intact while normal values share the cache.
    if decimals == 0 and (not IsFiniteNumber(value) or value < -2147483648 or value > 2147483647) then
        return value .. (hideSymbol and "" or "%"), true
    end
    if decimals == 1 and not IsFiniteNumber(value) then
        return format("%.1f", value) .. (hideSymbol and "" or "%"), true
    end
    return FormatPercentValue(value, hideSymbol, canSecret, decimals), true
end

local function GroupDelimiter(delimiter, fallback)
    if delimiter == nil then
        return fallback or " / "
    end
    return SPACED_DELIMITERS[delimiter] or delimiter
end

---
--- Unified abbreviator (handles secret + non-secret)
--- Secret: AbbreviateNumbers - secret string (C-side, no Lua arith)
--- Non-secret: AbbreviateNumbers or BreakUpLargeNumbers per user pref
---
local function GroupValue(value, short)
    return Text.FormatValue(value, short, true, "GROUP")
end

---
--- Percent helpers. UnitHealthPercent is SecretReturns and UnitPowerPercent
--- SecretWhenUnitPowerRestricted (UnitDocumentation.lua): a secret percent goes
--- to the C formatter untouched, only a plain one may be compared. Fallback:
--- compute from values if both are non-secret.
---
local function GroupPercentValue(unit, current, maximum, power)
    local pct
    if unit then
        if power and UnitPowerPercent then
            local powerType = UnitPowerType and UnitPowerType(unit)
            if SCALE_100 then pct = UnitPowerPercent(unit, powerType, false, SCALE_100)
            else pct = UnitPowerPercent(unit, powerType, false, true) end
        elseif not power and UnitHealthPercent then
            pct = UnitHealthPercent(unit, true, SCALE_100)
        end
        if issecretvalue(pct) or pct ~= nil then return pct end
    end
    if issecretvalue(current) or issecretvalue(maximum) then return nil end
    -- Runtime supplies the shared arithmetic owner after this file loads.
    return Text.PercentFromValues(tonumber(current) or 0, tonumber(maximum) or 0, "GROUP")
end

local function GroupMissingValue(current, maximum, unit, health)
    local missingVal
    if health and unit and UnitHealthMissing then missingVal = UnitHealthMissing(unit) end
    if issecretvalue(missingVal) or missingVal ~= nil then return missingVal end
    if issecretvalue(current) or issecretvalue(maximum) then return nil end
    return Text.MissingHealthFromValues(tonumber(current) or 0, tonumber(maximum) or 0, "GROUP")
end

--- Format a percent value into "42%" or "42" (respects hidePercentSymbol).
local function GroupPercent(value, suffix, decimals)
    return Text.FormatPercentValue(value, suffix == "", true, decimals, "GROUP")
end

---
--- Core mode formatter (shared by health + power)
--- All inputs may be secret strings (from GroupValue) or normal strings.
--- String concat ".." on secret strings produces a secret string.
---
local function FormatModeString(mode, sCur, sMax, delim, pctStr, hasPct, missingVal, shortNumbers)
    if mode == "PERCENT"  then
        if not hasPct then return "" end
        return pctStr
    end
    if mode == "CURRENT"  then return sCur end
    if mode == "FULLVALUE" then return sCur end
    if mode == "MAX"      then return sMax end

    if mode == "DEFICIT" then
        local iss = issecretvalue
        if iss and iss(missingVal) then
            return "-" .. GroupValue(missingVal, shortNumbers)
        end
        if missingVal == nil then return "" end
        local m = tonumber(missingVal) or 0
        if m <= 0 then return "" end
        return "-" .. GroupValue(m, shortNumbers)
    end

    if mode == "CURMAX"   then return sCur .. delim .. sMax end
    if mode == "MAXCUR"   then return sMax .. delim .. sCur end

    --- All remaining modes need percent
    if not hasPct then return sCur end
    if mode == "CURPERCENT"     then return sCur .. delim .. pctStr end
    if mode == "CURMAXPERCENT"  then return sCur .. delim .. sMax .. delim .. pctStr end
    if mode == "PERCENTMAXCUR"  then return pctStr .. delim .. sMax .. delim .. sCur end
    if mode == "MAXPERCENT"     then return sMax .. delim .. pctStr end
    if mode == "PERCENTCUR"     then return pctStr .. delim .. sCur end
    if mode == "PERCENTMAX"     then return pctStr .. delim .. sMax end
    if mode == "PERCENTCURMAX"  then return pctStr .. delim .. sCur .. delim .. sMax end

    return sCur
end

---
local function GroupAbsorbText(value, shortNumbers, absorbIcon, combined)
    local iss = issecretvalue
    local secret = iss and iss(value)
    if not secret and value == nil then return "" end
    local prefix
    if combined then
        prefix = absorbIcon and (" + " .. ABSORB_ICON_MARKUP .. " ") or " + "
    elseif absorbIcon then
        prefix = ABSORB_ICON_MARKUP .. " "
    end
    if secret then
        if TruncateWhenZero then
            local text = TruncateWhenZero(value)
            if prefix and WrapString then return WrapString(text, prefix, "") end
            return text
        end
        return GroupValue(value, shortNumbers)
    end
    value = tonumber(value) or 0
    if value <= 0 then return "" end
    local text = GroupValue(value, shortNumbers)
    return prefix and (prefix .. text) or text
end

-- GROUP strings retain the legacy mode/fallback contract; live slots continue
-- to use compiled native writers above. A secret result is never inspected here.
function Text.FormatHealthString(mode, hp, hpMax, delimiter, unit, hidePercentSymbol, shortNumbers,
     totalAbsorb, absorbIcon, percentDecimals, compatibility)
    if not mode or mode == "NONE" then return "" end
    assert(compatibility == "GROUP", "health string compatibility required")

    local absorbBaseMode = ABSORB_HEALTH_MODE_BASE[mode]
    local absorbText = ""
    if mode == "ABSORB" or absorbBaseMode then
        local value = totalAbsorb
        local valueIsSecret = issecretvalue and issecretvalue(value)
        if not valueIsSecret and value == nil and unit and UnitGetTotalAbsorbs then
            value = UnitGetTotalAbsorbs(unit)
        end
        absorbText = GroupAbsorbText(value, shortNumbers, absorbIcon == true, absorbBaseMode ~= nil)
        if mode == "ABSORB" then return absorbText end
        mode = absorbBaseMode
    end

    local delim = GroupDelimiter(delimiter, " / ")
    local hidePct = hidePercentSymbol == true
    local pctSuffix = hidePct and "" or "%"

    --- Abbreviate cur/max (secret-safe: C-side abbreviators)
    local sCur = GroupValue(hp, shortNumbers)
    local sMax = GroupValue(hpMax, shortNumbers)

    --- Percent via the native API, or plain-value fallback.
    local pctStr, hasPct = nil, false
    if mode ~= "CURRENT" and mode ~= "FULLVALUE" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = GroupPercentValue(unit, hp, hpMax, false)
        pctStr, hasPct = GroupPercent(pctVal, pctSuffix, percentDecimals)
    end

    local missingVal
    if mode == "DEFICIT" then missingVal = GroupMissingValue(hp, hpMax, unit, true) end

    return FormatModeString(mode, sCur, sMax, delim, pctStr, hasPct, missingVal, shortNumbers) .. absorbText
end

---
--- FormatPowerText(mode, pw, pwMax, delimiter [, unit [, hidePercentSymbol]])
--- Same modes as health text. Secret-safe via C-side abbreviators.
---
function Text.FormatPowerString(mode, pw, pwMax, delimiter, unit, hidePercentSymbol, shortNumbers, compatibility)
    assert(compatibility == "GROUP", "power string compatibility required")
    if not mode or mode == "NONE" then return "" end

    local delim = GroupDelimiter(delimiter, " / ")
    local hidePct = hidePercentSymbol == true
    local pctSuffix = hidePct and "" or "%"

    --- Abbreviate cur/max (secret-safe)
    local sCur = GroupValue(pw, shortNumbers)
    local sMax = GroupValue(pwMax, shortNumbers)

    --- Percent
    local pctStr, hasPct = nil, false
    if mode ~= "CURRENT" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = GroupPercentValue(unit, pw, pwMax, true)
        pctStr, hasPct = GroupPercent(pctVal, pctSuffix)
    end

    local missingVal
    if mode == "DEFICIT" then missingVal = GroupMissingValue(pw, pwMax, unit, false) end

    return FormatModeString(mode, sCur, sMax, delim, pctStr, hasPct, missingVal, shortNumbers)
end
