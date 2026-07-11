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
local tonumber = Text.tonumber
local type = Text.type or luaType
local format = Text.format
local floor = Text.floor
local max = Text.max
local SCALE_100 = Text.SCALE_100
local REVERSE_HEALTH_MODE = Text.REVERSE_HEALTH_MODE
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
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
  CURRENT = 1, MAX = 2, CURMAX = 3, MAXCUR = 3,
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
        return AbbreviateSecretNumber(value)
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
    return AbbreviateShortNumber(value)
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
  local text = SmallIntegerText(value) or format("%d", value or 0)
  if hideSymbol then
    return text
  end
  if type(value) == "number" and value >= 0 and value <= 100 then
    local n = floor(value)
    if n == value then
      return PERCENT_TEXT_0_100[n]
    end
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
  SetTextCached(slot.fs, AddSuffix(text, slot.suffix))
end

local function SlotTextPlain(slot, text)
  SetTextPlainCached(slot.fs, AddSuffix(text, slot.suffix))
end

local function SlotFormatted(slot, pattern, ...)
  local fs = slot and slot.fs
  if not fs then
    return
  end
  fs._aText = nil
  fs._aTextPlain = nil
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
    return AbbreviateShortNumber(value or 0)
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
  if not slot.hidePercentSymbol and type(pct) == "number" and pct >= 0 and pct <= 100 then
    local n = floor(pct)
    if n == pct then
      return PERCENT_TEXT_0_100[n]
    end
  end
  local text = SmallIntegerText(pct) or format("%d", pct or 0)
  return slot.hidePercentSymbol and text or (text .. "%")
end

local function SlotFormattedValue(slot, value)
  if issecretvalue(value) == true then
    if slot.short and AbbreviateSecretNumber then
      return AbbreviateSecretNumber(value), "%s"
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

local MODE_WRITERS = {
  CURRENT = WriteCurrent,
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

local MODE_PLAIN_WRITERS = {
  CURRENT = PlainWriteCurrent,
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
}

local SECRET_MODE_CODES = {
  CURRENT = 1,
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

local function SecretWrite(slot, cur, maxValue, pct)
  local fs = slot.fs
  if not fs then return end
  local fn = slot.secretValueFn
  local needsCur = slot.secretNeedsCur
  local needsMax = slot.secretNeedsMax
  local needsPct = slot.secretNeedsPct
  if fn then
    if needsCur then
      cur = issecretvalue(cur) == true and fn(cur) or fn(FiniteNumberOr(cur, 0))
    end
    if needsMax then
      maxValue = issecretvalue(maxValue) == true and fn(maxValue) or fn(FiniteNumberOr(maxValue, 0))
    end
  else
    if needsCur and issecretvalue(cur) ~= true then
      cur = FiniteNumberOr(cur, 0)
    end
    if needsMax and issecretvalue(maxValue) ~= true then
      maxValue = FiniteNumberOr(maxValue, 0)
    end
  end
  if needsPct and issecretvalue(pct) ~= true then
    pct = FiniteNumberOr(pct, 0)
  end
  fs._aText = nil
  fs._aTextPlain = nil
  slot.secretSetter(fs, slot.secretPattern, cur, maxValue, pct, slot.delimiter)
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
  local fallbackHide = text.hidePercentSymbol == true
  local hideLeft = text.healthLeftHidePercentSymbol ~= nil and text.healthLeftHidePercentSymbol == true or fallbackHide
  local hideCenter = text.healthCenterHidePercentSymbol ~= nil and text.healthCenterHidePercentSymbol == true or fallbackHide
  local hideRight = text.healthRightHidePercentSymbol ~= nil and text.healthRightHidePercentSymbol == true or fallbackHide
  if text.healthReverse == true then
    healthLeft, healthRight = healthRight, healthLeft
    hideLeft, hideRight = hideRight, hideLeft
    healthLeft = REVERSE_HEALTH_MODE[healthLeft] or healthLeft
    healthCenter = REVERSE_HEALTH_MODE[healthCenter] or healthCenter
    healthRight = REVERSE_HEALTH_MODE[healthRight] or healthRight
  end
  return healthLeft, healthCenter, healthRight, hideLeft, hideCenter, hideRight
end

local function BuildSecretPattern(mode, vf, pf)
  if mode == "CURRENT" or mode == "MAX" then
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

local function AddTextSlot(slots, index, fs, mode, delimiter, short, hidePercentSymbol, percentDecimals)
  if not (fs and mode and mode ~= "NONE") then
    return index, false, false
  end
  if not MODE_WRITERS[mode] then
    mode = "CURMAX"
  end
  local needsPercent = ModeNeedsPercent(mode)
  local slot = slots[index]
  if not slot then
    slot = {}
    slots[index] = slot
  end
  slot.fs = fs
  slot.mode = mode
  slot.writer = MODE_WRITERS[mode] or WriteCurMax
  slot.plainWriter = MODE_PLAIN_WRITERS[mode] or PlainWriteCurMax
  local secretCode = SECRET_MODE_CODES[mode]
  slot.secretWriter = secretCode and SecretWrite or nil
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
  else
    slot.secretValueFn = nil
    slot.secretPattern = nil
  end
  slot.suffix = nil
  slot.canSecret = nil
  return index + 1, needsPercent, mode == "DEFICIT", ModeNeedsCurrent(mode), ModeNeedsMax(mode)
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
        local hidePercentSymbol = i == 1 and hidePercentSymbol1 or (i == 2 and hidePercentSymbol2 or hidePercentSymbol3)
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

local function CompileTextRuntime(frame, spec, text)
  local rt = frame._msufTextRuntime
  if not rt then
    rt = {}
    frame._msufTextRuntime = rt
  end
  text = text or {}
  rt.showName = spec and spec.showName ~= false and frame.nameText ~= nil or false
  rt.hideNameOnDeadOffline = text.hideNameOnDeadOffline == true
  rt.nameShortenMax = text.nameShorten == true and (tonumber(text.nameShortenMax) or 6) or 0
  if rt.nameShortenMax > 0 then
    rt.nameShortenMax = floor(max(4, rt.nameShortenMax) + 0.5)
    if rt.nameShortenMax > 40 then
      rt.nameShortenMax = 40
    end
  end
  rt.nameShortenSide = text.nameShortenSide == "RIGHT" and "RIGHT" or "LEFT"
  rt.nameShortenDots = text.nameShortenDots ~= false and (text.nameAnchor or "LEFT") == "LEFT"
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
    inlineRt.nameShortenDots = inline.nameShortenDots ~= false and (text.nameAnchor or "LEFT") == "LEFT"
    inlineRt.stamp = inlineRt.unit .. ":" .. inlineRt.separator .. ":" .. inlineRt.colorMode .. ":" .. (inlineRt.nameShortenMax or 0) .. ":" .. inlineRt.nameShortenSide .. ":" .. (inlineRt.nameShortenDots and "1" or "0")
  else
    rt.inlineToT = nil
  end
  rt.healthSlots = rt.healthSlots or {}
  rt.powerSlots = rt.powerSlots or {}
  local showHealth = spec and spec.showHealthText ~= false
  local healthLeft, healthCenter, healthRight, healthHideLeft, healthHideCenter, healthHideRight = ResolveHealthTextModes(text)
  rt.healthPercentDecimals = NormalizePercentDecimals(text.healthPercentDecimals)

  local needsPercent, needsMissing, needsCurrent, needsMax
  rt.healthSlotCount, needsPercent, needsMissing, needsCurrent, needsMax = CompileThreeTextSlots(
    rt.healthSlots, frame, showHealth, HEALTH_SLOT_FIELDS,
    healthLeft, healthCenter, healthRight,
    text.healthDelimiter, text.shortNumbers,
    healthHideLeft, healthHideCenter, healthHideRight, rt.healthPercentDecimals)
  rt.healthNeedsPercent = needsPercent
  rt.healthNeedsMissing = needsMissing
  rt.healthNeedsCurrent = needsCurrent
  rt.healthNeedsMax = needsMax
  rt.healthColorByHealth = text.healthColorByHealth == true
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
  rt.healthPlain = nativeSecrets ~= true and frame.unit == "player"
  rt._lastHealthTextHP = nil
  rt._lastHealthTextMax = nil
  rt._lastHealthTextMissing = nil
  rt._dispatchHealthTextHP = nil
  rt._dispatchHealthTextMax = nil
  rt._dispatchHealthTextMissing = nil
  rt._dispatchHealthMissing = nil
  rt._dispatchHealthMissingReady = nil

  local showPower = spec and spec.showPowerText ~= false
  local powerUnused
  rt.powerSlotCount, needsPercent, powerUnused, needsCurrent, needsMax = CompileThreeTextSlots(
    rt.powerSlots, frame, showPower, POWER_SLOT_FIELDS,
    text.powerLeft, text.powerCenter, text.powerRight,
    text.powerDelimiter, text.shortNumbers,
    text.powerLeftHidePercentSymbol ~= nil and text.powerLeftHidePercentSymbol == true or text.hidePercentSymbol == true,
    text.powerCenterHidePercentSymbol ~= nil and text.powerCenterHidePercentSymbol == true or text.hidePercentSymbol == true,
    text.powerRightHidePercentSymbol ~= nil and text.powerRightHidePercentSymbol == true or text.hidePercentSymbol == true)
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
  rt.powerPlain = nativeSecrets ~= true and frame.unit == "player"
  rt.plainTextTrusted = nativeSecrets ~= true and frame.unit == "player"
  rt._lastPowerTextPower = nil
  rt._lastPowerTextMax = nil
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
    if rt.healthSlotCount > 0 then
      rt.healthHot = hot.healthHot
      rt.healthHotFromPercent = hot.healthFromPercent and hot.healthFromPercent(frame, rt) or nil
    else
      rt.healthHot = nil
      rt.healthHotFromPercent = nil
    end
    if rt.powerSlotCount > 0 then
      rt.powerHot = hot.powerHot
      rt.powerHotFromPercent = hot.powerFromPercent and hot.powerFromPercent(frame, rt) or nil
    else
      rt.powerHot = nil
      rt.powerHotFromPercent = nil
    end
  else
    rt.healthHot = nil
    rt.healthHotFromPercent = nil
    rt.powerHot = nil
    rt.powerHotFromPercent = nil
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
  for i = 1, count do
    local slot = slots[i]
    if slot then
      local writer = slot.secretWriter
      if writer then
        writer(slot, cur, max, pct, true, rt)
      else
        writer = slot.writer
        if writer then
          writer(slot, cur, max, pct, false, rt)
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
