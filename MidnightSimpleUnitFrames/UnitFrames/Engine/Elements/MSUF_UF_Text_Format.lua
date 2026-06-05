local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

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
local IsSecret = Text.IsSecret or function(_) return false end
local IsNil = Text.IsNil or function(value) return value == nil end
local ApplyText = Apply.Text or function(fs, text)
    if not fs then return end
    if IsSecret(text) then
        fs._aText = nil
        fs:SetText(text)
        return
    end
    text = text or ""
    if fs._aText ~= text then
        fs:SetText(text)
        fs._aText = text
    end
end
local ValueOrDefault = Text.ValueOrDefault or function(value, fallback)
    if value == nil then return fallback end
    return value
end
local pairs = pairs

local INT_TEXT_0_100 = {}
local PERCENT_TEXT_0_100 = {}
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
    if IsSecret(value) then
        return value
    end
    return ValueOrDefault(value, 0)
end

local function HealthPercent(unit)
    if not UnitHealthPercent then
        return nil
    end
    if SCALE_100 then
        return UnitHealthPercent(unit, true, SCALE_100)
    end
    return UnitHealthPercent(unit, true)
end

local function PowerPercent(unit)
    if not UnitPowerPercent then
        return nil
    end
    return UnitPowerPercent(unit)
end

local function ModeNeedsPercent(mode)
    return mode == "PERCENT"
        or mode == "CURPERCENT"
        or mode == "PERCENTCUR"
        or mode == "CURMAXPERCENT"
        or mode == "PERCENTMAXCUR"
        or mode == "MAXPERCENT"
        or mode == "PERCENTMAX"
        or mode == "PERCENTCURMAX"
end

local function ModeNeedsCurrent(mode)
    return mode == "CURRENT"
        or mode == "CURMAX"
        or mode == "MAXCUR"
        or mode == "CURPERCENT"
        or mode == "PERCENTCUR"
        or mode == "CURMAXPERCENT"
        or mode == "PERCENTMAXCUR"
        or mode == "PERCENTCURMAX"
end

local function ModeNeedsMax(mode)
    return mode == "MAX"
        or mode == "CURMAX"
        or mode == "MAXCUR"
        or mode == "CURMAXPERCENT"
        or mode == "PERCENTMAXCUR"
        or mode == "MAXPERCENT"
        or mode == "PERCENTMAX"
        or mode == "PERCENTCURMAX"
end

local function FormatValue(value, short, canSecret)
    if IsSecret(value) then
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
    if IsSecret(value) then
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
    text = text or ""
    if fs._aText ~= text then
        fs:SetText(text)
        fs._aText = text
    end
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
    if IsSecret(value) then
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
    if IsSecret(pct) then
        return ValueArg(pct, slot.canSecret), slot.hidePercentSymbol and "%d" or "%d%%"
    end
    return SlotPercent(slot, pct), "%s"
end

local function WriteCurrent(slot, cur)
    if IsSecret(cur) then
        local c, cf = SlotFormattedValue(slot, cur)
        SlotFormatted(slot, cf, c)
        return
    end
    SlotText(slot, SlotValue(slot, cur))
end

local function WriteMax(slot, cur, maxValue)
    if IsSecret(maxValue) then
        local m, mf = SlotFormattedValue(slot, maxValue)
        SlotFormatted(slot, mf, m)
        return
    end
    SlotText(slot, SlotValue(slot, maxValue))
end

local function WriteCurMax(slot, cur, maxValue)
    if IsSecret(cur) or IsSecret(maxValue) then
        local c, cf = SlotFormattedValue(slot, cur)
        local m, mf = SlotFormattedValue(slot, maxValue)
        SlotFormatted(slot, cf .. "%s" .. mf, c, slot.delimiter, m)
        return
    end
    SlotText(slot, SlotValue(slot, cur) .. slot.delimiter .. SlotValue(slot, maxValue))
end

local function WriteMaxCur(slot, cur, maxValue)
    if IsSecret(cur) or IsSecret(maxValue) then
        local c, cf = SlotFormattedValue(slot, cur)
        local m, mf = SlotFormattedValue(slot, maxValue)
        SlotFormatted(slot, mf .. "%s" .. cf, m, slot.delimiter, c)
        return
    end
    SlotText(slot, SlotValue(slot, maxValue) .. slot.delimiter .. SlotValue(slot, cur))
end

local function WritePercent(slot, cur, maxValue, pct, pctKnown)
    if pctKnown and IsSecret(pct) then
        local p, pf = SlotFormattedPercent(slot, pct)
        SlotFormatted(slot, pf, p)
        return
    end
    local p = pctKnown and SlotPercent(slot, pct) or nil
    SlotText(slot, p or "")
end

local function WriteCurPercent(slot, cur, maxValue, pct, pctKnown)
    if IsSecret(cur) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(cur) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(cur) or IsSecret(maxValue) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(cur) or IsSecret(maxValue) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(maxValue) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(maxValue) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(cur) or IsSecret(maxValue) or (pctKnown and IsSecret(pct)) then
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
    if IsSecret(missing) then
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

local function SecretSlotValue(slot, value)
    if slot.short and AbbreviateSecretNumber then
        return AbbreviateSecretNumber(value), "%s"
    elseif (not slot.short) and BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value), "%s"
    end
    return value, "%d"
end

local function SecretSlotPercent(slot, pct)
    return pct, slot.hidePercentSymbol and "%d" or "%d%%"
end

local function SecretWriteCurrent(slot, cur)
    local c, cf = SecretSlotValue(slot, cur)
    SlotFormatted(slot, cf, c)
end

local function SecretWriteMax(slot, cur, maxValue)
    local m, mf = SecretSlotValue(slot, maxValue)
    SlotFormatted(slot, mf, m)
end

local function SecretWriteCurMax(slot, cur, maxValue)
    local c, cf = SecretSlotValue(slot, cur)
    local m, mf = SecretSlotValue(slot, maxValue)
    SlotFormatted(slot, cf .. "%s" .. mf, c, slot.delimiter, m)
end

local function SecretWriteMaxCur(slot, cur, maxValue)
    local c, cf = SecretSlotValue(slot, cur)
    local m, mf = SecretSlotValue(slot, maxValue)
    SlotFormatted(slot, mf .. "%s" .. cf, m, slot.delimiter, c)
end

local function SecretWritePercent(slot, cur, maxValue, pct)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, pf, p)
end

local function SecretWriteCurPercent(slot, cur, maxValue, pct)
    local c, cf = SecretSlotValue(slot, cur)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, cf .. "%s" .. pf, c, slot.delimiter, p)
end

local function SecretWritePercentCur(slot, cur, maxValue, pct)
    local c, cf = SecretSlotValue(slot, cur)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, pf .. "%s" .. cf, p, slot.delimiter, c)
end

local function SecretWriteCurMaxPercent(slot, cur, maxValue, pct)
    local c, cf = SecretSlotValue(slot, cur)
    local m, mf = SecretSlotValue(slot, maxValue)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, cf .. "%s" .. mf .. "%s" .. pf, c, slot.delimiter, m, slot.delimiter, p)
end

local function SecretWritePercentMaxCur(slot, cur, maxValue, pct)
    local c, cf = SecretSlotValue(slot, cur)
    local m, mf = SecretSlotValue(slot, maxValue)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, pf .. "%s" .. mf .. "%s" .. cf, p, slot.delimiter, m, slot.delimiter, c)
end

local function SecretWriteMaxPercent(slot, cur, maxValue, pct)
    local m, mf = SecretSlotValue(slot, maxValue)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, mf .. "%s" .. pf, m, slot.delimiter, p)
end

local function SecretWritePercentMax(slot, cur, maxValue, pct)
    local m, mf = SecretSlotValue(slot, maxValue)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, pf .. "%s" .. mf, p, slot.delimiter, m)
end

local function SecretWritePercentCurMax(slot, cur, maxValue, pct)
    local c, cf = SecretSlotValue(slot, cur)
    local m, mf = SecretSlotValue(slot, maxValue)
    local p, pf = SecretSlotPercent(slot, pct)
    SlotFormatted(slot, pf .. "%s" .. cf .. "%s" .. mf, p, slot.delimiter, c, slot.delimiter, m)
end

local MODE_SECRET_WRITERS = {
    CURRENT = SecretWriteCurrent,
    MAX = SecretWriteMax,
    CURMAX = SecretWriteCurMax,
    MAXCUR = SecretWriteMaxCur,
    PERCENT = SecretWritePercent,
    CURPERCENT = SecretWriteCurPercent,
    PERCENTCUR = SecretWritePercentCur,
    CURMAXPERCENT = SecretWriteCurMaxPercent,
    PERCENTMAXCUR = SecretWritePercentMaxCur,
    MAXPERCENT = SecretWriteMaxPercent,
    PERCENTMAX = SecretWritePercentMax,
    PERCENTCURMAX = SecretWritePercentCurMax,
}

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
        pctKnown = not IsNil(pct)
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
    slot.secretWriter = MODE_SECRET_WRITERS[mode]
    slot.needsPercent = needsPercent
    slot.delimiter = NormalizeTextDelimiter(delimiter)
    slot.short = short == true
    slot.hidePercentSymbol = hidePercentSymbol == true
    slot.suffix = nil
    slot.canSecret = nil
    return index + 1, needsPercent, mode == "DEFICIT", ModeNeedsCurrent(mode), ModeNeedsMax(mode)
end

local function TrimTextSlots(slots, firstDead)
    for i = firstDead, #slots do
        slots[i] = nil
    end
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

    local nextIndex = 1
    local needsPercent = false
    local needsMissing = false
    local slotNeeds
    local slotMissing
    if showHealth and frame.hpTextLeft and frame.hpTextLeft:IsShown() then
        nextIndex, slotNeeds, slotMissing = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextLeft, healthLeft, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
    end
    if showHealth and frame.hpTextCenter and frame.hpTextCenter:IsShown() then
        nextIndex, slotNeeds, slotMissing = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextCenter, healthCenter, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
    end
    if showHealth and frame.hpTextRight and frame.hpTextRight:IsShown() then
        nextIndex, slotNeeds, slotMissing = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextRight, healthRight, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsMissing = needsMissing or slotMissing
    end
    rt.healthSlotCount = nextIndex - 1
    rt.healthNeedsPercent = needsPercent
    rt.healthNeedsMissing = needsMissing
    rt.healthColorByHealth = text.healthColorByHealth == true
    rt.healthPlain = frame.unit == "player"
    rt._lastHealthTextHP = nil
    rt._lastHealthTextMax = nil
    TrimTextSlots(rt.healthSlots, nextIndex)

    local showPower = spec and spec.showPowerText ~= false and spec.power and spec.power.enabled == true
    nextIndex = 1
    needsPercent = false
    local needsCurrent = false
    local needsMax = false
    local slotCurrent, slotMax, slotUnused
    if showPower and frame.powerTextLeft and frame.powerTextLeft:IsShown() then
        nextIndex, slotNeeds, slotUnused, slotCurrent, slotMax = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextLeft, text.powerLeft, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
    end
    if showPower and frame.powerTextCenter and frame.powerTextCenter:IsShown() then
        nextIndex, slotNeeds, slotUnused, slotCurrent, slotMax = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextCenter, text.powerCenter, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
    end
    if showPower and frame.powerTextRight and frame.powerTextRight:IsShown() then
        nextIndex, slotNeeds, slotUnused, slotCurrent, slotMax = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextRight, text.powerRight, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
        needsCurrent = needsCurrent or slotCurrent
        needsMax = needsMax or slotMax
    end
    rt.powerSlotCount = nextIndex - 1
    rt.powerNeedsPercent = needsPercent
    rt.powerNeedsCurrent = needsCurrent
    rt.powerNeedsMax = needsMax
    rt.powerColorByType = text.powerColorByType == true
    rt.powerPlain = frame.unit == "player"
    rt._lastPowerTextPower = nil
    rt._lastPowerTextMax = nil
    frame._msufTextPowerType = nil
    frame._msufTextPowerTypeKnown = nil
    frame._msufTextPowerMax = nil
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
    TrimTextSlots(rt.powerSlots, nextIndex)

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
        pctKnown = not IsNil(pct)
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

local function UpdateTextSlotsPlain(slots, count, cur, max, unit, percentFn, needsPercent, rt)
    if not slots or not count or count <= 0 then
        return
    end
    if IsSecret(cur) or IsSecret(max) or (rt and IsSecret(rt.healthMissing)) then
        return UpdateTextSlotsSecret(slots, count, cur, max, unit, percentFn, needsPercent, rt)
    end
    local pct
    local pctKnown = false
    if needsPercent == true and percentFn then
        pct = percentFn(unit)
        if IsSecret(pct) then
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
        if IsNil(hp) and UnitHealth then
            hp = UnitHealth(unit)
        end
        if IsNil(hpMax) then
            local bar = frame.hpBar or frame.Health
            if bar and bar._msufHealthMaxReady == true and bar._msufHealthMaxUnit == unit then
                hpMax = bar._msufHealthMax
            elseif UnitHealthMax then
                hpMax = UnitHealthMax(unit)
            end
        end
    end
    if rt.healthNeedsMissing == true then
        local calc = frame and frame._msufHealthCalc
        rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
    else
        rt.healthMissing = nil
    end
    return hp, hpMax
end

local function ResolvePendingPower(frame, rt, power, powerMax)
    local unit = frame and frame.unit
    if unit and (IsNil(power) or IsNil(powerMax)) then
        local powerType = frame._msufTextPowerType
        if frame._msufTextPowerTypeKnown ~= true and UnitPowerType then
            local rawType = UnitPowerType(unit)
            if not IsSecret(rawType) then
                powerType = rawType
                frame._msufTextPowerType = powerType
            end
            frame._msufTextPowerTypeKnown = true
        end

        if IsNil(power) and UnitPower then
            if powerType ~= nil then
                power = UnitPower(unit, powerType)
            else
                power = UnitPower(unit)
            end
        end
        if IsNil(powerMax) and UnitPowerMax then
            if powerType ~= nil then
                powerMax = UnitPowerMax(unit, powerType)
            else
                powerMax = UnitPowerMax(unit)
            end
        end
    end
    rt.healthMissing = nil
    return power, powerMax
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
    if UpdateHealthTextColor then
        UpdateHealthTextColor(frame, rt, frame.unit, hp, hpMax)
    end
    if rt.healthPlain == true then
        UpdateTextSlotsPlain(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, HealthPercent, rt.healthNeedsPercent, rt)
    else
        UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, HealthPercent, rt.healthNeedsPercent, rt)
    end
end

local textThrottleFrame
local textThrottleTimerActive
local textThrottleTimerAt
local textThrottleToken = 0
local healthTextQueue = {}
local powerTextQueue = {}
local TEXT_FLUSH_PER_TICK = 10
local TEXT_MIN_DELAY = 0.01

local function FlushTextQueues(now)
    local active = false
    local nextAt
    local flushed = 0

    for frame, when in pairs(healthTextQueue) do
        if now >= when then
            healthTextQueue[frame] = nil
            FlushPendingHealthText(frame)
            flushed = flushed + 1
            if flushed >= TEXT_FLUSH_PER_TICK then
                active = true
                nextAt = now + TEXT_MIN_DELAY
                break
            end
        else
            active = true
            if not nextAt or when < nextAt then nextAt = when end
        end
    end

    flushed = 0
    for frame, when in pairs(powerTextQueue) do
        if now >= when then
            powerTextQueue[frame] = nil
            FlushPendingPowerText(frame)
            flushed = flushed + 1
            if flushed >= TEXT_FLUSH_PER_TICK then
                active = true
                nextAt = now + TEXT_MIN_DELAY
                break
            end
        else
            active = true
            if not nextAt or when < nextAt then nextAt = when end
        end
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

ScheduleTextThrottleTimer = function(delay, when)
    delay = delay and delay > 0 and delay or TEXT_MIN_DELAY
    when = when or ((GetTime and GetTime() or 0) + delay)

    if textThrottleTimerActive and textThrottleTimerAt and textThrottleTimerAt <= when then
        return
    end

    textThrottleTimerActive = true
    textThrottleTimerAt = when
    if C_Timer and C_Timer.After then
        textThrottleToken = textThrottleToken + 1
        local token = textThrottleToken
        C_Timer.After(delay, function()
            if token ~= textThrottleToken then
                return
            end
            RunTextThrottle()
        end)
        return
    end

    if not textThrottleFrame then
        textThrottleFrame = CreateFrame("Frame")
        textThrottleFrame:SetScript("OnUpdate", TextThrottleOnUpdate)
        textThrottleFrame:Hide()
    end
    textThrottleFrame:Show()
end

local function QueueTextThrottle(queue, frame, remaining)
    local now = GetTime and GetTime() or 0
    local delay = remaining > 0 and remaining or TEXT_MIN_DELAY
    local when = now + delay
    queue[frame] = when
    ScheduleTextThrottleTimer(delay, when)
end

local function QueueHealthTextFlush(frame, rt, remaining)
    if rt.healthTimerActive == true then
        return
    end
    rt.healthTimerActive = true
    QueueTextThrottle(healthTextQueue, frame, remaining)
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
        UpdateTextSlotsPlain(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PowerPercent, rt.powerNeedsPercent, rt)
    else
        UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PowerPercent, rt.powerNeedsPercent, rt)
    end
end

local function QueuePowerTextFlush(frame, rt, remaining)
    if rt.powerTimerActive == true then
        return
    end
    rt.powerTimerActive = true
    QueueTextThrottle(powerTextQueue, frame, remaining)
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
