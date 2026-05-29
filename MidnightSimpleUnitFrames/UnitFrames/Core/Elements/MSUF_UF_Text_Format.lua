local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

local CreateFrame = Text.CreateFrame
local UnitHealthPercent = Text.UnitHealthPercent
local UnitPowerPercent = Text.UnitPowerPercent
local AbbreviateNumbers = Text.AbbreviateNumbers
local AbbreviateLargeNumbers = Text.AbbreviateLargeNumbers
local tonumber = Text.tonumber
local format = Text.format
local floor = Text.floor
local max = Text.max
local GetTime = Text.GetTime
local SCALE_100 = Text.SCALE_100
local REVERSE_HEALTH_MODE = Text.REVERSE_HEALTH_MODE
local issecretvalue = _G.issecretvalue
local C_Timer = _G.C_Timer
local pairs = pairs

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) == true
end

local function IsNil(value)
    if IsSecret(value) then
        return false
    end
    return value == nil
end

local function ValueArg(value, canSecret)
    if IsSecret(value) then
        return value
    end
    return value or 0
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

local function FormatValue(value, short, canSecret)
    if IsSecret(value) then
        if short then
            local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
            if abbreviate then
                return abbreviate(value)
            end
        end
        return value
    end
    if not short then
        return format("%d", value or 0)
    end
    local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
    if abbreviate then
        return abbreviate(value or 0)
    end
    return format("%d", value or 0)
end

local function FormatPercentValue(value, hideSymbol, canSecret)
    if IsSecret(value) then
        return value
    end
    if value == nil then
        return nil
    end
    local text = format("%d", value or 0)
    if hideSymbol then
        return text
    end
    return text .. "%"
end

local function SetTextCached(fs, text)
    if not fs then
        return
    end
    if IsSecret(text) then
        fs._msufTextLastPlain = nil
        fs:SetText(text)
        return
    end
    text = text or ""
    if fs._msufTextLastPlain == text then
        return
    end
    fs._msufTextLastPlain = text
    fs:SetText(text)
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

local function SlotFormatted(slot, pattern, ...)
    local fs = slot and slot.fs
    if not fs then
        return
    end
    fs._msufTextLastPlain = nil
    fs:SetFormattedText(pattern, ...)
end

local function SlotValue(slot, value)
    return FormatValue(value, slot.short, slot.canSecret)
end

local function SlotPercent(slot, pct)
    return FormatPercentValue(pct, slot.hidePercentSymbol, slot.canSecret)
end

local function SlotFormattedValue(slot, value)
    if IsSecret(value) then
        if slot.short then
            local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
            if abbreviate then
                return abbreviate(value), "%s"
            end
        end
        return ValueArg(value, slot.canSecret), "%d"
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

local function SetModeText(fs, mode, cur, max, delimiter, unit, percentFn, short, hidePercentSymbol, pctOverride, pctOverrideSet, suffix, canSecret)
    if not fs then
        return
    end
    mode = mode or "NONE"
    if mode == "NONE" then
        SetTextCached(fs, "")
        return
    end
    delimiter = delimiter or " - "
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
        return index, false
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
    slot.needsPercent = needsPercent
    slot.delimiter = delimiter or " - "
    slot.short = short == true
    slot.hidePercentSymbol = hidePercentSymbol == true
    slot.suffix = nil
    slot.canSecret = nil
    return index + 1, needsPercent
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
    rt.canHaveSecretValues = false
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
    local slotNeeds
    if showHealth and frame.hpTextLeft and frame.hpTextLeft:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextLeft, healthLeft, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    if showHealth and frame.hpTextCenter and frame.hpTextCenter:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextCenter, healthCenter, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    if showHealth and frame.hpTextRight and frame.hpTextRight:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.healthSlots, nextIndex, frame.hpTextRight, healthRight, text.healthDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    rt.healthSlotCount = nextIndex - 1
    rt.healthNeedsPercent = needsPercent
    TrimTextSlots(rt.healthSlots, nextIndex)

    local showPower = spec and spec.showPowerText ~= false and spec.power and spec.power.enabled == true
    nextIndex = 1
    needsPercent = false
    if showPower and frame.powerTextLeft and frame.powerTextLeft:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextLeft, text.powerLeft, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    if showPower and frame.powerTextCenter and frame.powerTextCenter:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextCenter, text.powerCenter, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    if showPower and frame.powerTextRight and frame.powerTextRight:IsShown() then
        nextIndex, slotNeeds = AddTextSlot(rt.powerSlots, nextIndex, frame.powerTextRight, text.powerRight, text.powerDelimiter, text.shortNumbers, text.hidePercentSymbol)
        needsPercent = needsPercent or slotNeeds
    end
    rt.powerSlotCount = nextIndex - 1
    rt.powerNeedsPercent = needsPercent
    rt.powerColorByType = text.powerColorByType == true
    rt.powerThrottle = tonumber(text.powerThrottle) or 0.1
    if rt.powerSlotCount <= 0 or spec and spec.key == "player" then
        rt.powerThrottle = 0
    end
    rt.healthThrottle = tonumber(text.healthThrottle) or 0.1
    if rt.healthSlotCount <= 0 or spec and spec.key == "player" then
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
            slot.canSecret = rt and rt.canHaveSecretValues
            local writer = slot.writer
            if writer then
                writer(slot, cur, max, pct, pctKnown, rt)
            end
        end
    end
end

local FlushPendingPowerText

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
    UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, frame.unit, HealthPercent, rt.healthNeedsPercent, rt)
end

local textThrottleFrame
local textThrottleTimerActive
local textThrottleTimerAt
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

local function TextThrottleTimerTick()
    textThrottleTimerActive = nil
    textThrottleTimerAt = nil

    local now = GetTime and GetTime() or 0
    local active, nextAt = FlushTextQueues(now)
    if active then
        local delay = nextAt and nextAt > now and (nextAt - now) or TEXT_MIN_DELAY
        ScheduleTextThrottleTimer(delay, now + delay)
    end
end

local function TextThrottleOnUpdate(self)
    local now = GetTime and GetTime() or 0
    local active = FlushTextQueues(now)
    if not active then
        self:Hide()
    end
end

ScheduleTextThrottleTimer = function(delay, when)
    delay = delay and delay > 0 and delay or TEXT_MIN_DELAY
    when = when or ((GetTime and GetTime() or 0) + delay)

    local after = C_Timer and C_Timer.After
    if after then
        if textThrottleTimerActive and textThrottleTimerAt and textThrottleTimerAt <= when then
            return
        end
        textThrottleTimerActive = true
        textThrottleTimerAt = when
        after(delay, TextThrottleTimerTick)
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
    rt.healthMissing = nil
    UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, frame.unit, PowerPercent, rt.powerNeedsPercent, rt)
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
Text.QueueHealthTextFlush = QueueHealthTextFlush
Text.QueuePowerTextFlush = QueuePowerTextFlush
