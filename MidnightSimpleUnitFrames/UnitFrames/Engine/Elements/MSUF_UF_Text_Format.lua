--- UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua
--- Allocation-light formatting helpers for unitframe text strings.
---
--- Called from frequent UNIT_* events, so number formatting, fallback strings,
--- and secret-safe branches stay local and avoid per-refresh table churn.

local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

local Apply = MSUF.Apply or {}
local luaType = type
local UnitPowerType = Text.UnitPowerType
local UnitHealthPercent = Text.UnitHealthPercent
local UnitPowerPercent = Text.UnitPowerPercent
local AbbreviateShortNumber = Text.AbbreviateNumbers or _G.AbbreviateNumbers
local BreakUpLargeNumbers = Text.BreakUpLargeNumbers or _G.BreakUpLargeNumbers
local AbbreviateLargeNumber = Text.AbbreviateLargeNumbers or _G.AbbreviateLargeNumbers or _G.ShortenNumber
local AbbreviateSecretNumber = AbbreviateShortNumber or AbbreviateLargeNumber
--- Global abbreviation style: nil lets the client decide (locale-dependent),
--- a table switches the C abbreviator to MSUF's locale-independent breakpoints.
--- Runtime/MSUF_NumberFormat.lua pushes it on the cold path, so every call site
--- below stays one direct C call with a constant second argument. Only the
--- short/abbreviating calls take it - BreakUpLargeNumbers never does.
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
local REVERSE_HEALTH_MODE = Text.REVERSE_HEALTH_MODE
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local TruncateWhenZero = _G.C_StringUtil and _G.C_StringUtil.TruncateWhenZero
local WrapString = _G.C_StringUtil and _G.C_StringUtil.WrapString
local ABSORB_ICON_MARKUP = "|TInterface\\Icons\\INV_Shield_06:0|t"
local ApplyText = Apply.Text or function(fs, text)
  if not fs then return end
  if issecretvalue(text) == true then
    fs._aText = nil
    fs._aTextPlain = nil
    fs:SetText(text)
    return
  end
  text = text or ""
  if fs._aTextPlain == true and fs._aText == text then
    return
  end
  fs:SetText(text)
  fs._aText = text
  fs._aTextPlain = true
end
local function IsFiniteNumber(value)
  return type(value) == "number" and value == value and (value - value) == 0
end

local function FiniteNumberOr(value, fallback)
  if type(value) == "number" then
    return IsFiniteNumber(value) and value or fallback
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
  local powerType = UnitPowerType and UnitPowerType(unit) or nil
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

local function SetTextPlainCached(fs, text)
  if not fs then
    return
  end
  if issecretvalue(text) == true then
    fs._aText = nil
    fs._aTextPlain = nil
    fs:SetText(text)
    return
  end
  text = text or ""
  if fs._aTextPlain == true and fs._aText == text then
    return
  end
  fs:SetText(text)
  fs._aText = text
  fs._aTextPlain = true
end

local function AddSuffix(text, suffix)
  if suffix then
    return (text or "") .. suffix
  end
  return text
end

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

--- Absorbs come back secret on every 12.x client, and a secret number can be
--- neither compared to zero nor formatted in Lua. TruncateWhenZero is the only
--- tainted-callable API that collapses a zero to an empty string, but it always
--- writes the raw integer - which is why the absorb value ignored "Short
--- numbers" while every other health slot honored it.
---
--- Parking that raw integer in the data section of a hyperlink keeps the zero
--- test (WrapString still drops prefix and suffix for an empty infix) while the
--- client renders the link body only, and the body carries the value formatted
--- exactly like the health slots next to it. The inner WrapString is a plain
--- secret-safe join: a formatted number is never the empty string.
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

local function CompileSecretWriter(slot)
  local fs = slot.fs
  local fn = slot.secretValueFn
  -- Only the short slot abbreviates; the long slot runs BreakUpLargeNumbers,
  -- which takes no abbreviation options. Reading NUM_OPTS inside the closure
  -- (instead of binding it here) keeps compiled slots correct after a style
  -- change without a recompile pass.
  local abbreviates = slot.short == true
  local code = slot.secretCode
  local needsCur = slot.secretNeedsCur
  local needsMax = slot.secretNeedsMax
  local needsPct = slot.secretNeedsPct
  local pattern = slot.secretPattern
  local delimiter = slot.delimiter

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
    if code == 1 then
      fs:SetFormattedText(pattern, cur)
    elseif code == 2 then
      fs:SetFormattedText(pattern, maxValue)
    elseif code == 3 then
      fs:SetFormattedText(pattern, cur, delimiter, maxValue)
    elseif code == 4 then
      fs:SetFormattedText(pattern, maxValue, delimiter, cur)
    elseif code == 5 then
      fs:SetFormattedText(pattern, pct)
    elseif code == 6 then
      fs:SetFormattedText(pattern, cur, delimiter, pct)
    elseif code == 7 then
      fs:SetFormattedText(pattern, pct, delimiter, cur)
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

local function BuildSecretPattern(mode, vf, pf)
  if mode == "CURRENT" or mode == "FULLVALUE" or mode == "MAX" then
    return vf
  elseif mode == "PERCENT" then
    return pf
  elseif mode == "CURMAX" or mode == "MAXCUR" then
    return vf .. "%s" .. vf
  elseif mode == "CURPERCENT" or mode == "MAXPERCENT" then
    return vf .. "%s" .. pf
  elseif mode == "PERCENTCUR" or mode == "PERCENTMAX" then
    return pf .. "%s" .. vf
  elseif mode == "CURMAXPERCENT" then
    return vf .. "%s" .. vf .. "%s" .. pf
  elseif mode == "PERCENTMAXCUR" or mode == "PERCENTCURMAX" then
    return pf .. "%s" .. vf .. "%s" .. vf
  end
  return nil
end

local function SecretPercentFormat(slot)
  if NormalizePercentDecimals(slot and slot.percentDecimals) >= 1 then
    return slot.hidePercentSymbol and "%.1f" or "%.1f%%"
  end
  return slot.hidePercentSymbol and "%d" or "%d%%"
end

local function AddTextSlot(slots, index, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals, absorbIcon)
  if not (fs and mode and mode ~= "NONE") then
    return index, false, false, false, false, false, false
  end
  local absorbBaseMode = ABSORB_HEALTH_MODE_BASE[mode]
  local compiledMode = absorbBaseMode or mode
  if not MODE_WRITERS[compiledMode] then
    mode = "CURMAX"
    compiledMode = mode
    absorbBaseMode = nil
  end
  local needsPercent = ModeNeedsPercent(compiledMode)
  local slot = slots[index]
  if not slot then
    slot = {}
    slots[index] = slot
  end
  slot.fs = fs
  slot.mode = mode
  slot.absorbIcon = absorbIcon == true
  slot.absorbBaseWriter = absorbBaseMode and MODE_WRITERS[compiledMode] or nil
  slot.absorbBasePlainWriter = absorbBaseMode and MODE_PLAIN_WRITERS[compiledMode] or nil
  slot.writer = absorbBaseMode and WriteAbsorbCombined or (MODE_WRITERS[compiledMode] or WriteCurMax)
  slot.plainWriter = absorbBaseMode and PlainWriteAbsorbCombined or (MODE_PLAIN_WRITERS[compiledMode] or PlainWriteCurMax)
  local secretCode
  if not absorbBaseMode then secretCode = SECRET_MODE_CODES[compiledMode] end
  slot.secretWriter = nil
  slot.secretCode = secretCode
  slot.secretSetter = secretCode and SECRET_SETTERS[secretCode] or nil
  slot.secretNeedsCur = SECRET_NEEDS_CUR[secretCode]
  slot.secretNeedsMax = SECRET_NEEDS_MAX[secretCode]
  slot.secretNeedsPct = SECRET_NEEDS_PCT[secretCode]
  slot.needsPercent = needsPercent
  slot.delimiter = NormalizeTextDelimiter(delimiter)
  slot.short = short == true
  slot.hidePercentSymbol = hidePercentSymbol == true
  slot.percentDecimals = NormalizePercentDecimals(percentDecimals)
  if secretCode then
    local secretValueFn = slot.short and AbbreviateSecretNumber or BreakUpLargeNumbers
    slot.secretValueFn = secretValueFn
    slot.secretPattern = BuildSecretPattern(mode,
      secretValueFn and "%s" or "%d",
      SecretPercentFormat(slot))
    slot.secretWriter = CompileSecretWriter(slot)
  else
    slot.secretValueFn = nil
    slot.secretPattern = nil
  end
  slot.suffix = nil
  slot.appendSuffix = false
  slot.canSecret = nil
  local usesAbsorb = mode == "ABSORB" or absorbBaseMode ~= nil
  return index + 1, needsPercent, compiledMode == "DEFICIT", ModeNeedsCurrent(compiledMode), ModeNeedsMax(compiledMode), usesAbsorb, mode == "ABSORB"
end

local function TrimTextSlots(slots, firstDead)
  for i = firstDead, #slots do
    slots[i] = nil
  end
end

local HEALTH_SLOT_FIELDS = { "hpTextLeft", "hpTextCenter", "hpTextRight" }
local POWER_SLOT_FIELDS = { "powerTextLeft", "powerTextCenter", "powerTextRight" }

local function CompileThreeTextSlots(slots, frame, show, fields, mode1, mode2, mode3, delimiter, short, hidePercentSymbol1, hidePercentSymbol2, hidePercentSymbol3, percentDecimals)
  local nextIndex = 1
  local needsPercent, needsMissing, needsCurrent, needsMax = false, false, false, false
  if show then
    for i = 1, #fields do
      local fs = frame[fields[i]]
      if fs and fs:IsShown() then
        local mode = i == 1 and mode1 or (i == 2 and mode2 or mode3)
        -- Branch-selected for the same reason as the health slots: a false flag
        -- would otherwise fall through to the Right slot's flag.
        local hidePercentSymbol
        if i == 1 then hidePercentSymbol = hidePercentSymbol1
        elseif i == 2 then hidePercentSymbol = hidePercentSymbol2
        else hidePercentSymbol = hidePercentSymbol3 end
        local slotNeeds, slotMissing, slotCurrent, slotMax
        nextIndex, slotNeeds, slotMissing, slotCurrent, slotMax = AddTextSlot(slots, nextIndex, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals)
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
      end
    end
  end
  TrimTextSlots(slots, nextIndex)
  return nextIndex - 1, needsPercent, needsMissing, needsCurrent, needsMax
end

local function CompileHealthTextSlots(valueSlots, absorbSlots, frame, show, mode1, mode2, mode3, delimiter, short, hidePercentSymbol1, hidePercentSymbol2, hidePercentSymbol3, percentDecimals, absorbIcon1, absorbIcon2, absorbIcon3)
  local valueIndex, absorbIndex = 1, 1
  local combinedAbsorbCount = 0
  local needsPercent, needsMissing, needsCurrent, needsMax = false, false, false, false
  if show then
    for i = 1, #HEALTH_SLOT_FIELDS do
      local fs = frame[HEALTH_SLOT_FIELDS[i]]
      if fs and fs:IsShown() then
        local mode = i == 1 and mode1 or (i == 2 and mode2 or mode3)
        -- Booleans must be selected by branch, never by and/or: a slot whose
        -- flag is false makes `i == n and flagN` yield false and fall through
        -- to the Right slot's flag, so a Left/Center slot silently inherited
        -- Right's "Hide % sign" and absorb icon.
        local hidePercentSymbol, absorbIcon
        if i == 1 then
          hidePercentSymbol, absorbIcon = hidePercentSymbol1, absorbIcon1
        elseif i == 2 then
          hidePercentSymbol, absorbIcon = hidePercentSymbol2, absorbIcon2
        else
          hidePercentSymbol, absorbIcon = hidePercentSymbol3, absorbIcon3
        end
        local absorbOnly = mode == "ABSORB"
        local slots = absorbOnly and absorbSlots or valueSlots
        local index = absorbOnly and absorbIndex or valueIndex
        local slotNeeds, slotMissing, slotCurrent, slotMax, slotAbsorb, slotAbsorbOnly
        index, slotNeeds, slotMissing, slotCurrent, slotMax, slotAbsorb, slotAbsorbOnly = AddTextSlot(
          slots, index, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals, absorbIcon)
        if slotAbsorbOnly then
          absorbIndex = index
        else
          valueIndex = index
          if slotAbsorb then combinedAbsorbCount = combinedAbsorbCount + 1 end
        end
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
      end
    end
  end
  TrimTextSlots(valueSlots, valueIndex)
  TrimTextSlots(absorbSlots, absorbIndex)
  local valueCount, absorbCount = valueIndex - 1, absorbIndex - 1
  return valueCount + absorbCount, valueCount, absorbCount, combinedAbsorbCount, needsPercent, needsMissing, needsCurrent, needsMax
end

local function CompileTextRuntime(frame, spec, text)
  local rt = frame._msufTextRuntime
  if not rt then
    rt = {}
    frame._msufTextRuntime = rt
  end
  text = text or {}
  rt.showName = spec and spec.showName ~= false and frame.nameText ~= nil or false
  rt.hideNameOnDeadOffline = text.hideNameOnDeadOffline == true
  local configuredNameShortenMax = text.nameShorten == true and (tonumber(text.nameShortenMax) or 6) or 0
  rt.nameShortenMax = configuredNameShortenMax
  if rt.nameShortenMax > 0 then
    rt.nameShortenMax = floor(max(4, rt.nameShortenMax) + 0.5)
    if rt.nameShortenMax > 40 then
      rt.nameShortenMax = 40
    end
  end
  rt.nameShortenSide = text.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
  local nameAnchor = text.nameAnchor or "LEFT"
  rt.nameShortenDots = text.nameShortenDots ~= false
    and (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "FRAMELEFT")
  rt.nameLegacyTruncation = text.nameLegacyTruncation == true
  rt.nameLegacyShortenMax = rt.nameLegacyTruncation and configuredNameShortenMax or 0
  rt.nameLegacyShortenDots = text.nameShortenDots ~= false
  rt.nameShortenStamp = rt.nameShortenMax > 0 and (rt.nameShortenMax .. ":" .. rt.nameShortenSide .. ":" .. (rt.nameShortenDots and "1" or "0")) or false
  local inline = text.inlineToT
  if inline and inline.enabled == true and spec and spec.key == "target" then
    local inlineRt = rt.inlineToT
    if not inlineRt then
      inlineRt = {}
      rt.inlineToT = inlineRt
    end
    inlineRt.unit = inline.unit or "targettarget"
    inlineRt.separator = inline.separator or " | "
    inlineRt.colorMode = inline.colorMode or "AUTO"
    inlineRt.targetNameClassColor = inline.targetNameClassColor == true
    inlineRt.targetNameNpcColor = inline.targetNameNpcColor == true
    inlineRt.targetNameNpcClassColor = inline.targetNameNpcClassColor == true
    inlineRt.totNameClassColor = inline.totNameClassColor == true
    inlineRt.totNameNpcColor = inline.totNameNpcColor == true
    inlineRt.totNameNpcClassColor = inline.totNameNpcClassColor == true
    inlineRt.nameShortenMax = inline.nameShorten == true and (tonumber(inline.nameShortenMax) or 6) or 0
    if inlineRt.nameShortenMax > 0 then
      inlineRt.nameShortenMax = floor(max(4, inlineRt.nameShortenMax) + 0.5)
      if inlineRt.nameShortenMax > 40 then
        inlineRt.nameShortenMax = 40
      end
    end
    inlineRt.nameShortenSide = inline.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
    inlineRt.nameShortenDots = inline.nameShortenDots ~= false
      and (nameAnchor == "LEFT" or nameAnchor == "TOPLEFT" or nameAnchor == "FRAMELEFT")
    inlineRt.stamp = inlineRt.unit .. ":" .. inlineRt.separator .. ":" .. inlineRt.colorMode .. ":" .. (inlineRt.nameShortenMax or 0) .. ":" .. inlineRt.nameShortenSide .. ":" .. (inlineRt.nameShortenDots and "1" or "0")
  else
    rt.inlineToT = nil
  end
  rt.healthSlots = rt.healthSlots or {}
  rt.healthAbsorbSlots = rt.healthAbsorbSlots or {}
  rt.powerSlots = rt.powerSlots or {}
  local showHealth = spec and spec.showHealthText ~= false
  local healthLeft, healthCenter, healthRight, healthHideLeft, healthHideCenter, healthHideRight,
    healthIconLeft, healthIconCenter, healthIconRight = ResolveHealthTextModes(text)
  rt.healthPercentDecimals = NormalizePercentDecimals(text.healthPercentDecimals)

  local needsPercent, needsMissing, needsCurrent, needsMax
  rt.healthSlotCount, rt.healthValueSlotCount, rt.healthAbsorbSlotCount, rt.healthCombinedAbsorbSlotCount,
    needsPercent, needsMissing, needsCurrent, needsMax = CompileHealthTextSlots(
    rt.healthSlots, rt.healthAbsorbSlots, frame, showHealth,
    healthLeft, healthCenter, healthRight,
    text.healthDelimiter, text.healthShortNumbers,
    healthHideLeft, healthHideCenter, healthHideRight, rt.healthPercentDecimals,
    healthIconLeft, healthIconCenter, healthIconRight)
  rt.healthUsesAbsorb = (rt.healthAbsorbSlotCount or 0) + (rt.healthCombinedAbsorbSlotCount or 0) > 0
  rt.healthNeedsPercent = needsPercent
  rt.healthNeedsMissing = needsMissing
  rt.healthNeedsCurrent = needsCurrent
  rt.healthNeedsMax = needsMax
  rt.healthColorByHealth = text.healthColorByHealth == true
  rt.healthColorByClass = text.healthColorByClass == true
  if (needsPercent == true or rt.healthColorByHealth == true) and needsCurrent ~= true then
    rt.healthDispatchKeyMode = needsMax == true and 5 or 4
  elseif needsCurrent == true and needsMax == true then
    rt.healthDispatchKeyMode = 3
  elseif needsMax == true then
    rt.healthDispatchKeyMode = 2
  elseif needsCurrent == true then
    rt.healthDispatchKeyMode = 1
  else
    rt.healthDispatchKeyMode = 0
  end
  local baseTextColor = spec and spec.textColor
  rt.textColorR = baseTextColor and baseTextColor.r or 1
  rt.textColorG = baseTextColor and baseTextColor.g or 1
  rt.textColorB = baseTextColor and baseTextColor.b or 1
  rt.textColorA = baseTextColor and baseTextColor.a or 1
  rt.healthTextAlpha = rt.textColorA
  rt._textGradientPct = nil
  rt.healthPlain = nativeSecrets ~= true and frame.MSUFUnitKey == "player"
  rt._lastHealthTextHP = nil
  rt._lastHealthTextMax = nil
  rt._lastHealthTextMissing = nil
  rt._lastAbsorbTextValue = nil
  rt.healthAbsorb = nil
  rt._dispatchHealthTextHP = nil
  rt._dispatchHealthTextMax = nil
  rt._dispatchHealthTextMissing = nil
  rt._dispatchHealthMissing = nil
  rt._dispatchHealthMissingReady = nil
  frame._msufTextHealthMax = nil
  frame._msufTextHealthMaxUnit = nil
  frame._msufTextHealthMaxReady = nil

  local showPower = spec and spec.showPowerText ~= false
  local powerUnused
  -- Per-slot override wins whenever it is set, including an explicit false.
  local powerFallbackHide = text.hidePercentSymbol == true
  local powerHideLeft, powerHideCenter, powerHideRight =
    text.powerLeftHidePercentSymbol, text.powerCenterHidePercentSymbol, text.powerRightHidePercentSymbol
  if powerHideLeft == nil then powerHideLeft = powerFallbackHide else powerHideLeft = powerHideLeft == true end
  if powerHideCenter == nil then powerHideCenter = powerFallbackHide else powerHideCenter = powerHideCenter == true end
  if powerHideRight == nil then powerHideRight = powerFallbackHide else powerHideRight = powerHideRight == true end
  rt.powerSlotCount, needsPercent, powerUnused, needsCurrent, needsMax = CompileThreeTextSlots(
    rt.powerSlots, frame, showPower, POWER_SLOT_FIELDS,
    text.powerLeft, text.powerCenter, text.powerRight,
    text.powerDelimiter, text.shortNumbers,
    powerHideLeft, powerHideCenter, powerHideRight)
  rt.powerNeedsPercent = needsPercent
  rt.powerNeedsCurrent = needsCurrent
  rt.powerNeedsMax = needsMax
  if needsPercent == true and needsCurrent ~= true then
    rt.powerDispatchKeyMode = needsMax == true and 5 or 4
  elseif needsCurrent == true and needsMax == true then
    rt.powerDispatchKeyMode = 3
  elseif needsMax == true then
    rt.powerDispatchKeyMode = 2
  elseif needsCurrent == true then
    rt.powerDispatchKeyMode = 1
  else
    rt.powerDispatchKeyMode = 0
  end
  if text.directLayout == true and text.powerColorByType ~= true then
    rt.powerColorByType = "STATIC"
  else
    rt.powerColorByType = text.powerColorByType == true
  end
  local powerSpec = spec and spec.power
  rt.powerRefreshTypeOnTick = rt.powerColorByType == true
    and (not powerSpec or powerSpec.mode == nil or powerSpec.mode == "power")
  frame._msufTextPowerNeedsType = rt.powerSlotCount > 0
    and (rt.powerColorByType == true or needsMax == true or needsPercent == true)
    and true
    or nil
  rt.powerPlain = nativeSecrets ~= true and frame.MSUFUnitKey == "player"
  rt.plainTextTrusted = nativeSecrets ~= true and frame.MSUFUnitKey == "player"
  rt._lastPowerTextPower = nil
  rt._lastPowerTextMax = nil
  rt._dispatchHealthPercent = nil
  rt._dispatchHealthPercentReady = nil
  rt._dispatchHealthMissing = nil
  rt._dispatchHealthMissingReady = nil
  rt._dispatchPowerTextPower = nil
  rt._dispatchPowerTextMax = nil
  frame._msufTextPowerType = nil
  frame._msufTextPowerToken = nil
  frame._msufTextPowerTypeKnown = nil
  frame._msufTextPowerTypeUnit = nil
  frame._msufTextPowerMax = nil
  frame._msufTextPowerMaxUnit = nil
  local hot = Text.RuntimeHotFunctions
  if hot then
    local groupScope = spec and spec.scope == "group"
    if rt.healthValueSlotCount > 0 then
      local fromValues
      if groupScope and (rt.healthNeedsCurrent == true
        or rt.healthNeedsMax == true
        or rt.healthNeedsMissing == true) then
        fromValues = hot.healthFromValues and hot.healthFromValues(frame, rt) or nil
      end
      rt.healthHot = fromValues or hot.healthHot
      rt.healthHotFromPercent = hot.healthFromPercent and hot.healthFromPercent(frame, rt) or nil
      rt.healthDirty = groupScope and hot.groupHealthDirty or hot.healthDirty
      rt.healthDefersUnitHealthText = not (groupScope and rt.healthHotFromPercent
        and rt.healthUsesAbsorb ~= true) and true or nil
    else
      rt.healthHot = nil
      rt.healthHotFromPercent = nil
      rt.healthDirty = nil
      rt.healthDefersUnitHealthText = nil
    end
    if rt.powerSlotCount > 0 then
      local fromValues
      if groupScope and (rt.powerNeedsCurrent == true or rt.powerNeedsMax == true) then
        fromValues = hot.powerFromValues and hot.powerFromValues(frame, rt) or nil
      end
      rt.powerHot = fromValues or hot.powerHot
      rt.powerHotFromPercent = hot.powerFromPercent and hot.powerFromPercent(frame, rt) or nil
      rt.powerDirty = hot.powerDirty
    else
      rt.powerHot = nil
      rt.powerHotFromPercent = nil
      rt.powerDirty = nil
    end
  else
    rt.healthHot = nil
    rt.healthHotFromPercent = nil
    rt.healthDirty = nil
    rt.healthDefersUnitHealthText = nil
    rt.powerHot = nil
    rt.powerHotFromPercent = nil
    rt.powerDirty = nil
  end
  return rt
end

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

UpdateTextSlotsSecret = function(slots, count, cur, max, unit, percentFn, needsPercent, rt, pctOverride, pctOverrideSet)
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
  local curSecret = issecretvalue(cur) == true
  local maxSecret = issecretvalue(max) == true
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
Text.FormatValue = FormatValue
Text.FormatPercentValue = FormatPercentValue
Text.SetTextCached = SetTextCached
Text.AddSuffix = AddSuffix
Text.SetModeText = SetModeText
Text.ResolveHealthTextModes = ResolveHealthTextModes
Text.AddTextSlot = AddTextSlot
Text.TrimTextSlots = TrimTextSlots
Text.CompileTextRuntime = CompileTextRuntime
Text.UpdateTextSlots = UpdateTextSlots
Text.UpdateTextSlotsPlain = UpdateTextSlotsPlain
Text.UpdateTextSlotsSecret = UpdateTextSlotsSecret
