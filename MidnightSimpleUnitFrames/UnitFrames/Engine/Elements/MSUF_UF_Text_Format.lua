local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

-- Text formatting helpers for unitframe name/health/power strings.
-- Runtime modules call into this file on frequent UNIT_* events, so formatting tables,
-- short-number helpers, and secret-safe fallbacks are kept local and allocation-light.
local Apply = MSUF.Apply or {}
local luaType = type
local CreateFrame = Text.CreateFrame
local UnitHealth = Text.UnitHealth
local UnitHealthMax = Text.UnitHealthMax
local UnitPower = Text.UnitPower
local UnitPowerMax = Text.UnitPowerMax
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
local GetTime = Text.GetTime
local C_Timer = _G.C_Timer
local UpdateHealthTextColor = Text.UpdateHealthTextColor
local SCALE_100 = Text.SCALE_100
local REVERSE_HEALTH_MODE = Text.REVERSE_HEALTH_MODE
local nativeSecrets = _G.issecretvalue ~= nil
local issecretvalue = _G.issecretvalue or function(_) return false end
local wipe = _G.wipe or function(t)
  for k in pairs(t) do
    t[k] = nil
  end
  return t
end
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
local ValueOrDefault = Text.ValueOrDefault or function(value, fallback)
  if value == nil then return fallback end
  return value
end
local pairs = pairs

local INT_TEXT_0_100 = {}
local PERCENT_TEXT_0_100 = {}
-- Precompute the common 0..100 strings used by percent displays; this avoids rebuilding
-- identical strings during health/power updates across many frames.
for i = 0, 100 do
  local text = format("%d", i)
  INT_TEXT_0_100[i] = text
  PERCENT_TEXT_0_100[i] = text .. "%"
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
  return ValueOrDefault(value, 0)
end

local function HealthPercent(unit)
  if not UnitHealthPercent or type(unit) ~= "string" or unit == "" then
    return nil
  end
  if SCALE_100 then
    return UnitHealthPercent(unit, true, SCALE_100)
  end
  return UnitHealthPercent(unit, true)
end

local function PowerPercent(unit)
  if not UnitPowerPercent or type(unit) ~= "string" or unit == "" then
    return nil
  end
  local powerType = UnitPowerType and UnitPowerType(unit) or nil
  if issecretvalue(powerType) == true then powerType = nil end
  if SCALE_100 then
    return UnitPowerPercent(unit, powerType, false, SCALE_100)
  end
  return UnitPowerPercent(unit, powerType, false, true)
end

local function PercentFromPlainValues(cur, maxValue)
  if nativeSecrets and (issecretvalue(cur) == true or issecretvalue(maxValue) == true) then
    return nil
  end
  if type(cur) ~= "number" or type(maxValue) ~= "number" or maxValue <= 0 then
    return nil
  end
  return floor((cur / maxValue) * 100 + 0.5)
end

local function MissingHealthFromValues(cur, maxValue)
  if nativeSecrets and (issecretvalue(cur) == true or issecretvalue(maxValue) == true) then
    return nil
  end
  if type(cur) ~= "number" or type(maxValue) ~= "number" then
    return nil
  end
  local missing = maxValue - cur
  return missing > 0 and missing or 0
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
  if not short then
    if BreakUpLargeNumbers then
      return BreakUpLargeNumbers(ValueOrDefault(value, 0))
    end
    return SmallIntegerText(value) or format("%d", value or 0)
  end
  if AbbreviateShortNumber then
    return AbbreviateShortNumber(ValueOrDefault(value, 0))
  end
  return CompactNumber(value)
end

local function FormatPercentValue(value, hideSymbol, canSecret)
  if issecretvalue(value) == true then
    return value
  end
  if value == nil then
    return nil
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
  return FormatPercentValue(pct, slot.hidePercentSymbol, slot.canSecret)
end

local function SlotValuePlain(slot, value)
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

local function SecretWrite(slot, cur, maxValue, pct)
  local fs = slot.fs
  if not fs then return end
  local code = slot.secretCode
  local fn = slot.secretValueFn
  if fn then
    if code == 1 or code == 3 or code == 4 or code == 6 or code == 7 or code == 8 or code == 9 or code == 12 then
      cur = fn(cur)
    end
    if code == 2 or code == 3 or code == 4 or code == 8 or code == 9 or code == 10 or code == 11 or code == 12 then
      maxValue = fn(maxValue)
    end
  end
  fs._aText = nil
  fs._aTextPlain = nil
  if code == 1 then
    fs:SetFormattedText(slot.secretPattern, cur)
  elseif code == 2 then
    fs:SetFormattedText(slot.secretPattern, maxValue)
  elseif code == 3 then
    fs:SetFormattedText(slot.secretPattern, cur, slot.delimiter, maxValue)
  elseif code == 4 then
    fs:SetFormattedText(slot.secretPattern, maxValue, slot.delimiter, cur)
  elseif code == 5 then
    fs:SetFormattedText(slot.secretPattern, pct)
  elseif code == 6 then
    fs:SetFormattedText(slot.secretPattern, cur, slot.delimiter, pct)
  elseif code == 7 then
    fs:SetFormattedText(slot.secretPattern, pct, slot.delimiter, cur)
  elseif code == 8 then
    fs:SetFormattedText(slot.secretPattern, cur, slot.delimiter, maxValue, slot.delimiter, pct)
  elseif code == 9 then
    fs:SetFormattedText(slot.secretPattern, pct, slot.delimiter, maxValue, slot.delimiter, cur)
  elseif code == 10 then
    fs:SetFormattedText(slot.secretPattern, maxValue, slot.delimiter, pct)
  elseif code == 11 then
    fs:SetFormattedText(slot.secretPattern, pct, slot.delimiter, maxValue)
  elseif code == 12 then
    fs:SetFormattedText(slot.secretPattern, pct, slot.delimiter, cur, slot.delimiter, maxValue)
  end
end

local function SetModeText(fs, mode, cur, max, delimiter, unit, percentFn, short, hidePercentSymbol, pctOverride, pctOverrideSet, suffix, canSecret)
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
  if text.healthReverse == true then
    healthLeft, healthRight = healthRight, healthLeft
    healthLeft = REVERSE_HEALTH_MODE[healthLeft] or healthLeft
    healthCenter = REVERSE_HEALTH_MODE[healthCenter] or healthCenter
    healthRight = REVERSE_HEALTH_MODE[healthRight] or healthRight
  end
  return healthLeft, healthCenter, healthRight
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

local function AddTextSlot(slots, index, fs, mode, delimiter, short, hidePercentSymbol)
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
  slot.secretCode = secretCode
  slot.secretWriter = secretCode and SecretWrite or nil
  slot.needsPercent = needsPercent
  slot.delimiter = NormalizeTextDelimiter(delimiter)
  slot.short = short == true
  slot.hidePercentSymbol = hidePercentSymbol == true
  if secretCode then
    local secretValueFn = slot.short and AbbreviateSecretNumber or BreakUpLargeNumbers
    slot.secretValueFn = secretValueFn
    slot.secretPattern = BuildSecretPattern(mode,
      secretValueFn and "%s" or "%d",
      slot.hidePercentSymbol and "%d" or "%d%%")
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

local function CompileThreeTextSlots(slots, frame, show, fields, mode1, mode2, mode3, delimiter, short, hidePercentSymbol)
  local nextIndex = 1
  local needsPercent, needsMissing, needsCurrent, needsMax = false, false, false, false
  if show then
    for i = 1, #fields do
      local fs = frame[fields[i]]
      if fs and fs:IsShown() then
        local mode = i == 1 and mode1 or (i == 2 and mode2 or mode3)
        local slotNeeds, slotMissing, slotCurrent, slotMax
        nextIndex, slotNeeds, slotMissing, slotCurrent, slotMax = AddTextSlot(slots, nextIndex, fs, mode, delimiter, short, hidePercentSymbol)
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
    inlineRt.totNameClassColor = inline.totNameClassColor == true
    inlineRt.totNameNpcColor = inline.totNameNpcColor == true
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
  local healthLeft, healthCenter, healthRight = ResolveHealthTextModes(text)

  local needsPercent, needsMissing, needsCurrent, needsMax
  rt.healthSlotCount, needsPercent, needsMissing, needsCurrent, needsMax = CompileThreeTextSlots(
    rt.healthSlots, frame, showHealth, HEALTH_SLOT_FIELDS,
    healthLeft, healthCenter, healthRight,
    text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
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
    text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
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
  rt.powerThrottle = tonumber(text.powerThrottle) or 0.1
  if rt.powerSlotCount <= 0 then
    rt.powerThrottle = 0
  end
  rt.healthThrottle = tonumber(text.healthThrottle) or 0.1
  if rt.healthSlotCount <= 0 then
    rt.healthThrottle = 0
  end
  rt.healthTextPending = nil
  rt.healthTimerActive = nil
  rt.pendingHP = nil
  rt.pendingHPMax = nil
  rt.nextHealthTextTime = nil
  rt.powerTextPending = nil
  rt.powerTimerActive = nil
  rt.pendingPower = nil
  rt.pendingPowerMax = nil
  rt.nextPowerTextTime = nil

  local hot = Text.RuntimeHotFunctions
  if hot then
    if rt.healthSlotCount > 0 then
      rt.healthHot = hot.healthHot
      rt.healthDirty = rt.healthThrottle > 0 and hot.healthDirty or nil
      rt.healthFlush = hot.healthFlush
    else
      rt.healthHot = nil
      rt.healthDirty = nil
      rt.healthFlush = nil
    end
    if rt.powerSlotCount > 0 then
      rt.powerHot = hot.powerHot
      rt.powerDirty = rt.powerThrottle > 0 and hot.powerDirty or nil
      rt.powerFlush = hot.powerFlush
    else
      rt.powerHot = nil
      rt.powerDirty = nil
      rt.powerFlush = nil
    end
  else
    rt.healthHot = nil
    rt.healthDirty = nil
    rt.healthFlush = nil
    rt.powerHot = nil
    rt.powerDirty = nil
    rt.powerFlush = nil
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
    return UpdateTextSlotsSecret(slots, count, cur, max, unit, percentFn, needsPercent, rt)
  end
  local pct
  local pctKnown = false
  if needsPercent == true and percentFn then
    if pctOverrideSet == true then
      pct = pctOverride
    else
      pct = PercentFromPlainValues(cur, max)
    end
    if pct == nil and pctOverrideSet ~= true then
      pct = percentFn(unit)
    end
    if issecretvalue(pct) == true then
      return UpdateTextSlotsSecret(slots, count, cur, max, unit, percentFn, needsPercent, rt)
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

UpdateTextSlotsSecret = function(slots, count, cur, max, unit, percentFn, needsPercent, rt)
  if not slots or not count or count <= 0 then
    return
  end
  local pct
  if needsPercent == true and percentFn then
    pct = percentFn(unit)
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

local FlushPendingPowerText

local function ResolvePendingHealth(frame, rt, hp, hpMax)
  local unit = frame and frame.unit
  if unit then
    local percentNeedsValues = rt.healthNeedsPercent == true and UnitHealthPercent == nil
    local missingNeedsValues = rt.healthNeedsMissing == true
    local needsCurrent = rt.healthNeedsCurrent == true or rt.healthColorByHealth == true or percentNeedsValues or missingNeedsValues
    local needsMax = rt.healthNeedsMax == true or rt.healthColorByHealth == true or percentNeedsValues or missingNeedsValues
    local needHP = needsCurrent and issecretvalue(hp) ~= true and hp == nil
    local needMax = needsMax and issecretvalue(hpMax) ~= true and hpMax == nil
    if needHP or needMax then
      local bar = frame.hpBar or frame.Health
      if bar then
        local hpUnit = bar._msufHealthValueUnit
        local maxUnit = bar._msufHealthMaxUnit
        if needHP and hpUnit == unit then
          hp = bar._msufHealthValue
          needHP = issecretvalue(hp) ~= true and hp == nil
        end
        if needMax and bar._msufHealthMaxReady == true and maxUnit == unit then
          hpMax = bar._msufHealthMax
          needMax = issecretvalue(hpMax) ~= true and hpMax == nil
        end
      end
    end
    if needHP and UnitHealth then
      hp = UnitHealth(unit)
    end
    if needMax and UnitHealthMax then
      hpMax = UnitHealthMax(unit)
    end
  end
  if rt.healthNeedsMissing == true then
    if rt._dispatchHealthMissingReady == true then
      rt.healthMissing = rt._dispatchHealthMissing
      rt._dispatchHealthMissingReady = nil
      rt._dispatchHealthMissing = nil
    else
      rt.healthMissing = MissingHealthFromValues(hp, hpMax)
      if rt.healthMissing == nil then
        local calc = frame and frame._msufHealthCalc
        rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
      end
    end
  else
    rt._dispatchHealthMissingReady = nil
    rt._dispatchHealthMissing = nil
    rt.healthMissing = nil
  end
  return hp, hpMax
end

local function ResolvePendingPower(frame, rt, power, powerMax)
  local unit = frame and frame.unit
  local percentNeedsValues = rt.powerNeedsPercent == true and UnitPowerPercent == nil
  local needsPower = rt.powerNeedsCurrent == true or percentNeedsValues
  local needsMax = rt.powerNeedsMax == true or percentNeedsValues
  local needPower = needsPower and issecretvalue(power) ~= true and power == nil
  local needPowerMax = needsMax and issecretvalue(powerMax) ~= true and powerMax == nil
  if unit and (needPower or needPowerMax) then
    local powerType
    if frame._msufTextPowerNeedsType == true then
      powerType = frame._msufTextPowerType
    end
    if frame._msufTextPowerNeedsType == true and UnitPowerType then
      local typeUnit = frame._msufTextPowerTypeUnit
      local typeUnitMatches = typeUnit == unit
      if frame._msufTextPowerTypeKnown ~= true or not typeUnitMatches then
        local rawType, rawToken = UnitPowerType(unit)
        if issecretvalue(rawType) == true then rawType = nil end
        if issecretvalue(rawToken) == true then rawToken = nil end
        powerType = rawType
        frame._msufTextPowerType = rawType
        frame._msufTextPowerToken = rawToken
        frame._msufTextPowerTypeKnown = true
        frame._msufTextPowerTypeUnit = unit
      end
    end

    if needPower and UnitPower then
      if powerType ~= nil then
        power = UnitPower(unit, powerType)
      else
        power = UnitPower(unit)
      end
    end
    if needPowerMax and UnitPowerMax then
      local maxUnit = frame._msufTextPowerMaxUnit
      local maxUnitMatches = maxUnit == unit
      if maxUnitMatches and frame._msufTextPowerMax ~= nil then
        powerMax = frame._msufTextPowerMax
      elseif powerType ~= nil then
        powerMax = UnitPowerMax(unit, powerType)
      else
        powerMax = UnitPowerMax(unit)
      end
      if issecretvalue(powerMax) ~= true and powerMax == nil then powerMax = 1 end
      frame._msufTextPowerMax = powerMax
      frame._msufTextPowerMaxUnit = unit
    end
  end
  rt.healthMissing = nil
  return power, powerMax
end

local function PlainHealthTextKey(rt, hp, hpMax, pctOverride, pctOverrideSet)
  if nativeSecrets and (issecretvalue(hp) == true
    or issecretvalue(hpMax) == true
    or (pctOverrideSet == true and issecretvalue(pctOverride) == true)) then
    return false
  end
  local mode = rt.healthDispatchKeyMode or 0
  local keyHP, keyMax = false, false
  if mode == 1 then
    keyHP = hp
  elseif mode == 2 then
    keyMax = hpMax
  elseif mode == 3 then
    keyHP, keyMax = hp, hpMax
  elseif mode == 4 or mode == 5 then
    if pctOverrideSet == true and issecretvalue(pctOverride) ~= true then
      keyHP = pctOverride or false
    elseif type(hp) == "number" and type(hpMax) == "number" and hpMax > 0 then
      keyHP = floor((hp / hpMax) * 100 + 0.5)
    else
      return false
    end
    keyMax = mode == 5 and hpMax or false
  end
  return true, keyHP, keyMax
end

local function PlainPowerTextKey(rt, power, powerMax, pctOverride, pctOverrideSet)
  if nativeSecrets and (issecretvalue(power) == true
    or issecretvalue(powerMax) == true
    or (pctOverrideSet == true and issecretvalue(pctOverride) == true)) then
    return false
  end
  local mode = rt.powerDispatchKeyMode or 0
  local keyPower, keyMax = false, false
  if mode == 1 then
    keyPower = power
  elseif mode == 2 then
    keyMax = powerMax
  elseif mode == 3 then
    keyPower, keyMax = power, powerMax
  elseif mode == 4 or mode == 5 then
    if pctOverrideSet == true and issecretvalue(pctOverride) ~= true then
      keyPower = pctOverride or false
    elseif type(power) == "number" and type(powerMax) == "number" and powerMax > 0 then
      keyPower = floor((power / powerMax) * 100 + 0.5)
    else
      return false
    end
    keyMax = mode == 5 and powerMax or false
  end
  return true, keyPower, keyMax
end

local function FlushPendingHealthText(frame)
  local rt = frame and frame._msufTextRuntime
  if not rt or not rt.healthTextPending or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
    if rt then
      rt.healthTimerActive = nil
    end
    return
  end

  local hp, hpMax = rt.pendingHP, rt.pendingHPMax
  rt.pendingHP, rt.pendingHPMax = nil, nil
  rt.healthTextPending = nil
  rt.healthTimerActive = nil

  local now = GetTime and GetTime() or 0
  local throttle = rt.healthThrottle or 0
  rt.nextHealthTextTime = throttle > 0 and (now + throttle) or nil
  hp, hpMax = ResolvePendingHealth(frame, rt, hp, hpMax)
  if rt.healthPlain == true then
    local pctOverride, pctOverrideSet
    if rt.healthNeedsPercent == true then
      pctOverride = PercentFromPlainValues(hp, hpMax)
      if pctOverride ~= nil then
        pctOverrideSet = true
      elseif UnitHealthPercent then
        pctOverride = HealthPercent(frame.unit)
        pctOverrideSet = true
      end
    end
    local comparable, keyHP, keyMax = PlainHealthTextKey(rt, hp, hpMax, pctOverride, pctOverrideSet)
    if comparable == true
      and rt._lastHealthTextHP == keyHP
      and rt._lastHealthTextMax == keyMax
      and rt._lastHealthTextMissing == rt.healthMissing then
      return
    end
    if comparable == true then
      rt._lastHealthTextHP = keyHP
      rt._lastHealthTextMax = keyMax
      rt._lastHealthTextMissing = rt.healthMissing
    else
      rt._lastHealthTextHP = nil
      rt._lastHealthTextMax = nil
      rt._lastHealthTextMissing = nil
    end
    if rt.healthColorByHealth == true and UpdateHealthTextColor then
      UpdateHealthTextColor(frame, rt, frame.unit, hp, hpMax)
    end
    UpdateTextSlotsPlain(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, HealthPercent, rt.healthNeedsPercent, rt, pctOverride, pctOverrideSet)
  else
    if rt.healthColorByHealth == true and UpdateHealthTextColor then
      UpdateHealthTextColor(frame, rt, frame.unit, hp, hpMax)
    end
    UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, HealthPercent, rt.healthNeedsPercent, rt)
  end
end

local textThrottleFrame
local textThrottleTimerActive
local textThrottleTimerAt
local healthTextQueue = {}
local healthTextQueueList = {}
local healthTextQueueHead = 1
local healthTextQueueTail = 0
local powerTextQueue = {}
local powerTextQueueList = {}
local powerTextQueueHead = 1
local powerTextQueueTail = 0
local TEXT_FLUSH_PER_TICK = 10
local TEXT_MIN_DELAY = 0.01

local function CompactTextQueue(list, head, tail)
  if head <= 1 then
    return head, tail
  end
  if head > tail then
    wipe(list)
    return 1, 0
  end
  local out = 1
  for i = head, tail do
    list[out] = list[i]
    out = out + 1
  end
  for i = out, tail do
    list[i] = nil
  end
  return 1, out - 1
end

local function RemoveQueuedTextFrame(queue, list, head, tail, frame)
  if queue[frame] == nil then
    return head, tail
  end
  queue[frame] = nil
  for i = head, tail do
    if list[i] == frame then
      for j = i, tail - 1 do
        list[j] = list[j + 1]
      end
      list[tail] = nil
      tail = tail - 1
      break
    end
  end
  if head > tail then
    wipe(list)
    return 1, 0
  end
  return head, tail
end

local function QueueTextFrame(queue, list, head, tail, frame, when)
  if head > 32 then
    head, tail = CompactTextQueue(list, head, tail)
  end
  head, tail = RemoveQueuedTextFrame(queue, list, head, tail, frame)

  local pos = tail + 1
  while pos > head do
    local prevFrame = list[pos - 1]
    local prevWhen = prevFrame and queue[prevFrame]
    if not prevWhen or prevWhen <= when then
      break
    end
    list[pos] = prevFrame
    pos = pos - 1
  end
  list[pos] = frame
  queue[frame] = when
  return head, tail + 1
end

local function QueueHasPending(head, tail)
  return head <= tail
end

local function EarliestAt(a, b)
  if not b then return a end
  if not a or b < a then return b end
  return a
end

local function FlushQueuedText(queue, list, head, tail, now, flushFn, budget)
  local flushed = 0
  local active = false
  local nextAt
  local i = head
  local last = tail

  while i <= last do
    if flushed >= budget then
      active = true
      nextAt = now + TEXT_MIN_DELAY
      break
    end

    local frame = list[i]
    local when = frame and queue[frame]
    if not when then
      list[i] = nil
      i = i + 1
    elseif now >= when then
      queue[frame] = nil
      list[i] = nil
      i = i + 1
      flushFn(frame)
      flushed = flushed + 1
    else
      active = true
      nextAt = when
      break
    end
  end

  head = i
  if head > tail then
    wipe(list)
    head = 1
    tail = 0
  elseif head > 32 then
    head, tail = CompactTextQueue(list, head, tail)
  end
  return head, tail, active, nextAt, flushed
end

local function FlushTextQueues(now)
  local active = false
  local nextAt
  local budget = TEXT_FLUSH_PER_TICK
  local flushed

  healthTextQueueHead, healthTextQueueTail, active, nextAt, flushed = FlushQueuedText(
    healthTextQueue, healthTextQueueList, healthTextQueueHead, healthTextQueueTail, now, FlushPendingHealthText, budget
  )
  budget = budget - flushed

  if budget > 0 then
    local powerActive, powerNext
    powerTextQueueHead, powerTextQueueTail, powerActive, powerNext, flushed = FlushQueuedText(
      powerTextQueue, powerTextQueueList, powerTextQueueHead, powerTextQueueTail, now, FlushPendingPowerText, budget
    )
    active = active or powerActive
    nextAt = EarliestAt(nextAt, powerNext)
  elseif QueueHasPending(powerTextQueueHead, powerTextQueueTail) then
    active = true
    nextAt = EarliestAt(nextAt, now + TEXT_MIN_DELAY)
  end

  return active, nextAt
end

local ScheduleTextThrottleTimer

local function RunTextThrottle(now)
  now = now or (GetTime and GetTime() or 0)
  textThrottleTimerActive = nil
  textThrottleTimerAt = nil

  local active, nextAt = FlushTextQueues(now)
  if not active then
    return false
  end

  local delay = nextAt and nextAt > now and (nextAt - now) or TEXT_MIN_DELAY
  ScheduleTextThrottleTimer(delay, now + delay)
  return true
end

local function TextThrottleOnUpdate(self)
  local now = GetTime and GetTime() or 0
  if textThrottleTimerAt and now < textThrottleTimerAt then
    return
  end
  if not RunTextThrottle(now) then
    self:Hide()
  end
end

local function TextThrottleTimerCallback()
  -- MUST ALWAYS run RunTextThrottle -- never gate on textThrottleTimerAt.
  RunTextThrottle()
end

ScheduleTextThrottleTimer = function(delay, when)
  delay = delay and delay > 0 and delay or TEXT_MIN_DELAY
  when = when or ((GetTime and GetTime() or 0) + delay)

  if textThrottleTimerActive and textThrottleTimerAt and textThrottleTimerAt <= when then
    return
  end

  textThrottleTimerActive = true
  textThrottleTimerAt = when
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, TextThrottleTimerCallback)
    return
  end

  if not textThrottleFrame then
    textThrottleFrame = CreateFrame("Frame")
    textThrottleFrame:SetScript("OnUpdate", TextThrottleOnUpdate)
    textThrottleFrame:Hide()
  end
  textThrottleFrame:Show()
end

local function QueueHealthTextFlush(frame, rt, remaining)
  if rt.healthTimerActive == true then
    return
  end
  rt.healthTimerActive = true
  local delay = remaining > 0 and remaining or TEXT_MIN_DELAY
  local when = (GetTime and GetTime() or 0) + delay
  healthTextQueueHead, healthTextQueueTail = QueueTextFrame(
    healthTextQueue, healthTextQueueList, healthTextQueueHead, healthTextQueueTail, frame, when
  )
  ScheduleTextThrottleTimer(delay, when)
end

FlushPendingPowerText = function(frame)
  local rt = frame and frame._msufTextRuntime
  if not rt or not rt.powerTextPending or not rt.powerSlotCount or rt.powerSlotCount <= 0 then
    if rt then
      rt.powerTimerActive = nil
    end
    return
  end

  local power, powerMax = rt.pendingPower, rt.pendingPowerMax
  rt.pendingPower, rt.pendingPowerMax = nil, nil
  rt.powerTextPending = nil
  rt.powerTimerActive = nil

  local now = GetTime and GetTime() or 0
  local throttle = rt.powerThrottle or 0
  rt.nextPowerTextTime = throttle > 0 and (now + throttle) or nil
  power, powerMax = ResolvePendingPower(frame, rt, power, powerMax)
  if rt.powerPlain == true then
    local pctOverride, pctOverrideSet
    if rt.powerNeedsPercent == true then
      pctOverride = PercentFromPlainValues(power, powerMax)
      if pctOverride ~= nil then
        pctOverrideSet = true
      elseif UnitPowerPercent then
        pctOverride = PowerPercent(frame.unit)
        pctOverrideSet = true
      end
    end
    local comparable, keyPower, keyMax = PlainPowerTextKey(rt, power, powerMax, pctOverride, pctOverrideSet)
    if comparable == true
      and rt._lastPowerTextPower == keyPower
      and rt._lastPowerTextMax == keyMax then
      return
    end
    if comparable == true then
      rt._lastPowerTextPower = keyPower
      rt._lastPowerTextMax = keyMax
    else
      rt._lastPowerTextPower = nil
      rt._lastPowerTextMax = nil
    end
    UpdateTextSlotsPlain(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PowerPercent, rt.powerNeedsPercent, rt, pctOverride, pctOverrideSet)
  else
    UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PowerPercent, rt.powerNeedsPercent, rt)
  end
end

local function QueuePowerTextFlush(frame, rt, remaining)
  if rt.powerTimerActive == true then
    return
  end
  rt.powerTimerActive = true
  local delay = remaining > 0 and remaining or TEXT_MIN_DELAY
  local when = (GetTime and GetTime() or 0) + delay
  powerTextQueueHead, powerTextQueueTail = QueueTextFrame(
    powerTextQueue, powerTextQueueList, powerTextQueueHead, powerTextQueueTail, frame, when
  )
  ScheduleTextThrottleTimer(delay, when)
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
Text.FlushPendingHealthText = FlushPendingHealthText
Text.FlushPendingPowerText = FlushPendingPowerText
Text.QueueHealthTextFlush = QueueHealthTextFlush
Text.QueuePowerTextFlush = QueuePowerTextFlush
