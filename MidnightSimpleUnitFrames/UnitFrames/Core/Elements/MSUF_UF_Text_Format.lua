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
local function ValueArg(value, canSecret)
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
    -- Intentionally NO dedupe/compare: `text` may be a WoW secret value
    -- (health/power/name-derived strings). Passing a secret to SetText is fine,
    -- but comparing one with == raises a hard error. Always set directly, like
    -- the status SetText helper's `raw` path. Upstream throttling already caps
    -- how often this runs.
    fs:SetText(text or "")
end

local function AddSuffix(text, suffix)
    if suffix then
        return (text or "") .. suffix
    end
    return text
end

local function SetReadableModeText(fs, mode, cur, max, pct, delimiter, short, hidePercentSymbol, suffix, canSecret)
    local c = FormatValue(cur, short, canSecret)
    local m = FormatValue(max, short, canSecret)
    local p = FormatPercentValue(pct, hidePercentSymbol, canSecret)
    if not (c and m) then
        return false
    end
    local needsPct = ModeNeedsPercent(mode)
    if needsPct and not p then
        return false
    end
    if mode == "CURRENT" then
        SetTextCached(fs, AddSuffix(c, suffix))
    elseif mode == "MAX" then
        SetTextCached(fs, AddSuffix(m, suffix))
    elseif mode == "CURMAX" then
        SetTextCached(fs, AddSuffix(c .. delimiter .. m, suffix))
    elseif mode == "MAXCUR" then
        SetTextCached(fs, AddSuffix(m .. delimiter .. c, suffix))
    elseif mode == "PERCENT" then
        SetTextCached(fs, AddSuffix(p, suffix))
    elseif mode == "CURPERCENT" then
        SetTextCached(fs, AddSuffix(c .. delimiter .. p, suffix))
    elseif mode == "PERCENTCUR" then
        SetTextCached(fs, AddSuffix(p .. delimiter .. c, suffix))
    elseif mode == "CURMAXPERCENT" then
        SetTextCached(fs, AddSuffix(c .. delimiter .. m .. delimiter .. p, suffix))
    elseif mode == "PERCENTMAXCUR" then
        SetTextCached(fs, AddSuffix(p .. delimiter .. m .. delimiter .. c, suffix))
    elseif mode == "MAXPERCENT" then
        SetTextCached(fs, AddSuffix(m .. delimiter .. p, suffix))
    elseif mode == "PERCENTMAX" then
        SetTextCached(fs, AddSuffix(p .. delimiter .. m, suffix))
    elseif mode == "PERCENTCURMAX" then
        SetTextCached(fs, AddSuffix(p .. delimiter .. c .. delimiter .. m, suffix))
    elseif mode == "DEFICIT" then
        SetTextCached(fs, "")
    else
        SetTextCached(fs, AddSuffix(c .. delimiter .. m, suffix))
    end
    return true
end

local function SetShortModeText(fs, mode, curArg, maxArg, pctArg, pctKnown, delimiter, hidePercentSymbol)
    local abbreviate = AbbreviateNumbers or AbbreviateLargeNumbers
    if not abbreviate then
        return false
    end
    local c = abbreviate(curArg)
    local m = abbreviate(maxArg)
    local pctFormat = hidePercentSymbol and "%d" or "%d%%"
    if mode == "CURRENT" then
        fs:SetText(c)
    elseif mode == "MAX" then
        fs:SetText(m)
    elseif mode == "CURMAX" then
        fs:SetText(c .. delimiter .. m)
    elseif mode == "MAXCUR" then
        fs:SetText(m .. delimiter .. c)
    elseif mode == "PERCENT" then
        if pctKnown then
            fs:SetFormattedText(pctFormat, pctArg)
        else
            fs:SetText("")
        end
    elseif mode == "CURPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%s%s" .. pctFormat, c, delimiter, pctArg)
        else
            fs:SetText(c)
        end
    elseif mode == "PERCENTCUR" then
        if pctKnown then
            fs:SetFormattedText(pctFormat .. "%s%s", pctArg, delimiter, c)
        else
            fs:SetText(c)
        end
    elseif mode == "CURMAXPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%s%s%s%s" .. pctFormat, c, delimiter, m, delimiter, pctArg)
        else
            fs:SetText(c .. delimiter .. m)
        end
    elseif mode == "PERCENTMAXCUR" then
        if pctKnown then
            fs:SetFormattedText(pctFormat .. "%s%s%s%s", pctArg, delimiter, m, delimiter, c)
        else
            fs:SetText(m .. delimiter .. c)
        end
    elseif mode == "MAXPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%s%s" .. pctFormat, m, delimiter, pctArg)
        else
            fs:SetText(m)
        end
    elseif mode == "PERCENTMAX" then
        if pctKnown then
            fs:SetFormattedText(pctFormat .. "%s%s", pctArg, delimiter, m)
        else
            fs:SetText(m)
        end
    elseif mode == "PERCENTCURMAX" then
        if pctKnown then
            fs:SetFormattedText(pctFormat .. "%s%s%s%s", pctArg, delimiter, c, delimiter, m)
        else
            fs:SetText(c .. delimiter .. m)
        end
    else
        return false
    end
    return true
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
    delimiter = delimiter or " - "
    local curArg = ValueArg(cur, canSecret)
    local maxArg = ValueArg(max, canSecret)
    local pct
    local pctKnown = false
    local pctArg
    if ModeNeedsPercent(mode) then
        if pctOverrideSet then
            pct = pctOverride
        else
            pct = percentFn and percentFn(unit)
        end
        pctKnown = pct ~= nil
        pctArg = pctKnown and ValueArg(pct, canSecret) or nil
    end

    if SetReadableModeText(fs, mode, cur, max, pct, delimiter, short, hidePercentSymbol, suffix, canSecret) then
        return
    end

    fs._msufLastSetText = nil
    if short and SetShortModeText(fs, mode, curArg, maxArg, pctArg, pctKnown, delimiter, hidePercentSymbol) then
        return
    end

    if mode == "CURRENT" then
        fs:SetFormattedText("%d", curArg)
    elseif mode == "MAX" then
        fs:SetFormattedText("%d", maxArg)
    elseif mode == "CURMAX" then
        fs:SetFormattedText("%d%s%d", curArg, delimiter, maxArg)
    elseif mode == "MAXCUR" then
        fs:SetFormattedText("%d%s%d", maxArg, delimiter, curArg)
    elseif mode == "PERCENT" then
        if pctKnown then
            fs:SetFormattedText("%d%%", pctArg)
        else
            fs:SetText("")
        end
    elseif mode == "CURPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%d%s%d%%", curArg, delimiter, pctArg)
        else
            fs:SetFormattedText("%d", curArg)
        end
    elseif mode == "PERCENTCUR" then
        if pctKnown then
            fs:SetFormattedText("%d%%%s%d", pctArg, delimiter, curArg)
        else
            fs:SetFormattedText("%d", curArg)
        end
    elseif mode == "CURMAXPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%d%s%d%s%d%%", curArg, delimiter, maxArg, delimiter, pctArg)
        else
            fs:SetFormattedText("%d%s%d", curArg, delimiter, maxArg)
        end
    elseif mode == "PERCENTMAXCUR" then
        if pctKnown then
            fs:SetFormattedText("%d%%%s%d%s%d", pctArg, delimiter, maxArg, delimiter, curArg)
        else
            fs:SetFormattedText("%d%s%d", maxArg, delimiter, curArg)
        end
    elseif mode == "MAXPERCENT" then
        if pctKnown then
            fs:SetFormattedText("%d%s%d%%", maxArg, delimiter, pctArg)
        else
            fs:SetFormattedText("%d", maxArg)
        end
    elseif mode == "PERCENTMAX" then
        if pctKnown then
            fs:SetFormattedText("%d%%%s%d", pctArg, delimiter, maxArg)
        else
            fs:SetFormattedText("%d", maxArg)
        end
    elseif mode == "PERCENTCURMAX" then
        if pctKnown then
            fs:SetFormattedText("%d%%%s%d%s%d", pctArg, delimiter, curArg, delimiter, maxArg)
        else
            fs:SetFormattedText("%d%s%d", curArg, delimiter, maxArg)
        end
    elseif mode == "DEFICIT" then
        fs:SetText("")
    else
        fs:SetFormattedText("%d%s%d", curArg, delimiter, maxArg)
    end
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
    local slot = slots[index]
    if not slot then
        slot = {}
        slots[index] = slot
    end
    slot.fs = fs
    slot.mode = mode
    slot.delimiter = delimiter
    slot.short = short == true
    slot.hidePercentSymbol = hidePercentSymbol == true
    return index + 1, ModeNeedsPercent(mode)
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
        pctKnown = pct ~= nil
    end
    for i = 1, count do
        local slot = slots[i]
        if slot then
            if slot.mode == "DEFICIT" and rt and rt.healthMissing ~= nil then
                SetTextCached(slot.fs, "-" .. (FormatValue(rt.healthMissing, slot.short, rt.canHaveSecretValues) or "0"))
            else
                SetModeText(slot.fs, slot.mode, cur, max, slot.delimiter, unit, nil, slot.short, slot.hidePercentSymbol, pct, pctKnown, nil, rt and rt.canHaveSecretValues)
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
local healthTextQueue = {}
local powerTextQueue = {}

local function TextThrottleOnUpdate(self)
    local now = GetTime and GetTime() or 0
    local active = false

    for frame, when in pairs(healthTextQueue) do
        if now >= when then
            healthTextQueue[frame] = nil
            FlushPendingHealthText(frame)
        else
            active = true
        end
    end

    for frame, when in pairs(powerTextQueue) do
        if now >= when then
            powerTextQueue[frame] = nil
            FlushPendingPowerText(frame)
        else
            active = true
        end
    end

    if not active then
        self:Hide()
    end
end

local function QueueTextThrottle(queue, frame, remaining)
    if not textThrottleFrame then
        textThrottleFrame = CreateFrame("Frame")
        textThrottleFrame:SetScript("OnUpdate", TextThrottleOnUpdate)
        textThrottleFrame:Hide()
    end
    queue[frame] = (GetTime and GetTime() or 0) + (remaining > 0 and remaining or 0.01)
    textThrottleFrame:Show()
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
