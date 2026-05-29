local _, MSUF = ...
local Text = MSUF and MSUF.UFText
if not Text then return end

local UnitExists = Text.UnitExists
local UnitHealth = Text.UnitHealth
local UnitHealthMax = Text.UnitHealthMax
local UnitPower = Text.UnitPower
local UnitPowerMax = Text.UnitPowerMax
local UnitPowerType = Text.UnitPowerType
local InCombatLockdown = Text.InCombatLockdown
local UnitName = Text.UnitName
local UnitIsDeadOrGhost = Text.UnitIsDeadOrGhost
local UnitIsConnected = Text.UnitIsConnected
local GetTime = Text.GetTime
local PowerColor = Text.PowerColor
local SetShownCached = Text.SetShownCached
local SetTextCached = Text.SetTextCached
local SetNameTextColor = Text.SetNameTextColor
local NameTextColor = Text.NameTextColor
local SetInlineTextColor = Text.SetInlineTextColor
local InlineTextColor = Text.InlineTextColor
local SetPowerTextColor = Text.SetPowerTextColor
local HealthPercent = Text.HealthPercent
local PowerPercent = Text.PowerPercent
local issecretvalue = _G.issecretvalue
local UpdateTextSlots = Text.UpdateTextSlots
local QueueHealthTextFlush = Text.QueueHealthTextFlush
local QueuePowerTextFlush = Text.QueuePowerTextFlush
local ResolveHealthTextModes = Text.ResolveHealthTextModes
local AnchorInlineToName = Text.AnchorInlineToName
local EMPTY_EVENTS = Text.EMPTY_EVENTS
local POWER_EVENTS = Text.POWER_EVENTS
local POWER_EVENTS_FREQUENT = Text.POWER_EVENTS_FREQUENT

local function ReadPowerValues(unit)
    local powerType = UnitPowerType and UnitPowerType(unit) or nil
    local power, maxPower
    if powerType ~= nil then
        power = UnitPower(unit, powerType)
        maxPower = UnitPowerMax(unit, powerType)
    else
        power = UnitPower(unit)
        maxPower = UnitPowerMax(unit)
    end
    if power == nil then power = 0 end
    if maxPower == nil then maxPower = 1 end
    return power, maxPower
end

function Text.UpdateNameColor(frame, event, unit)
    if frame.nameText and frame.nameText:IsShown() then
        SetNameTextColor(frame, NameTextColor(frame, unit or frame.unit))
        Text.UpdateInline(frame, event, unit)
    end
end

function Text.UpdateInline(frame, event, unit)
    local rt = frame and frame._msufTextRuntime
    local inline = rt and rt.inlineToT
    if not inline then
        if frame and (frame.totInlineSep or frame.totInlineText) then
            SetShownCached(frame.totInlineSep, false)
            SetShownCached(frame.totInlineText, false)
            SetShownCached(frame._msufInlineDotsFS, false)
        end
        return
    end

    local inlineUnit = inline.unit or "targettarget"
    if (event == "UNIT_NAME_UPDATE" or event == "UNIT_CLASSIFICATION_CHANGED") and unit and unit ~= inlineUnit then
        return
    end
    if not (frame.totInlineSep and frame.totInlineText) then
        return
    end

    local exists = UnitExists(inlineUnit)
    if not exists then
        SetShownCached(frame.totInlineSep, false)
        SetShownCached(frame.totInlineText, false)
        SetShownCached(frame._msufInlineDotsFS, false)
        frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
        return
    end

    local stamp = inline.stamp
    if frame._msufInlineStamp ~= stamp then
        SetTextCached(frame.totInlineSep, inline.separator)
        frame._msufInlineStamp = stamp
    end
    -- UnitName can be a secret string for target-derived units. Like oUF,
    -- pass it straight to C-side FontString code and never compare or slice it.
    local name = UnitName(inlineUnit)
    frame.totInlineText:SetText(name)
    if AnchorInlineToName then
        AnchorInlineToName(frame)
    end
    SetShownCached(frame.totInlineSep, true)
    SetShownCached(frame.totInlineText, true)
    SetInlineTextColor(frame, InlineTextColor(frame, inlineUnit, inline))
end

function Text.UpdateName(frame, event, unit)
    unit = unit or frame.unit
    if unit ~= frame.unit then
        Text.UpdateInline(frame, event, unit)
        return
    end
    local rt = frame._msufTextRuntime
    if not frame.nameText then
        return
    end
    if rt and rt.showName == false then
        frame.nameText:SetText("")
        frame.nameText._msufShown = nil
        SetShownCached(frame.nameText, false)
        return
    end
    if rt and rt.hideNameOnDeadOffline == true then
        local connected = UnitIsConnected and UnitIsConnected(unit)
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
        if connected == false or dead == true then
            frame.nameText:SetText("")
            frame.nameText._msufShown = nil
            SetShownCached(frame.nameText, false)
            return
        end
    end
    frame.nameText._msufShown = nil
    SetShownCached(frame.nameText, true)
    -- UnitName can be a secret string for target/boss units. Do not cache,
    -- compare, shorten, or branch on it in Lua.
    frame.nameText:SetText(UnitName(unit))
    Text.UpdateNameColor(frame, event, unit)
end

function Text.UpdateHealth(frame, event, unit, hp, hpMax)
    unit = unit or frame.unit
    local rt = frame._msufTextRuntime
    if not rt or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
        return
    end
    if hp == nil then
        hp = UnitHealth(unit)
    end
    if hpMax == nil then
        hpMax = UnitHealthMax(unit)
    end

    -- Raw-value short-circuit (5.54 _HealthValueFast pattern). On the frequent
    -- UNIT_HEALTH tick, if the raw HP and max are unchanged the formatted text
    -- cannot differ, so skip the whole slot-format pass. issecretvalue is checked
    -- FIRST so a secret value never reaches the == compare; if any side is secret
    -- we fall through and render (the downstream FontString diff stays ~free).
    if event == "UNIT_HEALTH" then
        local lastHp, lastMax = rt._lastHpRaw, rt._lastHpMaxRaw
        local isv = issecretvalue
        if not (isv and (isv(hp) or isv(hpMax)
            or (lastHp ~= nil and isv(lastHp)) or (lastMax ~= nil and isv(lastMax)))) then
            if hp == lastHp and hpMax == lastMax then
                return
            end
        end
        rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax
    else
        rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax
    end

    local calc = frame and frame._msufHealthCalc
    rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil

    local throttle = rt.healthThrottle or 0
    if throttle > 0 and event == "UNIT_HEALTH" and GetTime then
        local now = GetTime()
        local nextTime = rt.nextHealthTextTime
        if nextTime and now < nextTime then
            rt.pendingHP, rt.pendingHPMax = hp, hpMax
            rt.healthTextPending = true
            QueueHealthTextFlush(frame, rt, nextTime - now)
            return
        end
        rt.nextHealthTextTime = now + throttle
    else
        rt.pendingHP, rt.pendingHPMax = nil, nil
        rt.healthTextPending = nil
        rt.nextHealthTextTime = nil
    end
    UpdateTextSlots(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
end

function Text.UpdatePower(frame, event, unit, power, powerMax)
    unit = unit or frame.unit
    local rt = frame._msufTextRuntime
    if not rt or not rt.powerSlotCount or rt.powerSlotCount <= 0 then
        return
    end
    if rt.powerColorByType == true
        and (event == "UNIT_DISPLAYPOWER" or event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" or event == "MSUF_POWER_LAYOUT" or event == "MSUF_POWER_TEXT_COLORS" or frame._msufPowerTextColorInitialized ~= true) then
        local r, g, b = PowerColor(frame, unit)
        SetPowerTextColor(frame, r, g, b, 1)
        frame._msufPowerTextColorInitialized = true
    end
    if power == nil or powerMax == nil then
        local currentPower, currentMax = ReadPowerValues(unit)
        if power == nil then
            power = currentPower
        end
        if powerMax == nil then
            powerMax = currentMax
        end
    end
    rt.healthMissing = nil

    -- Raw-value short-circuit for the frequent power ticks (5.54 _PowerFrequent
    -- pattern); same secret-safe ordering as the health path.
    if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        local lastP, lastMax = rt._lastPowerRaw, rt._lastPowerMaxRaw
        local isv = issecretvalue
        if not (isv and (isv(power) or isv(powerMax)
            or (lastP ~= nil and isv(lastP)) or (lastMax ~= nil and isv(lastMax)))) then
            if power == lastP and powerMax == lastMax then
                return
            end
        end
    end
    rt._lastPowerRaw, rt._lastPowerMaxRaw = power, powerMax

    local throttle = rt.powerThrottle or 0
    if throttle > 0
        and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") then
        local now = GetTime and GetTime() or 0
        local nextTime = rt.nextPowerTextTime
        if nextTime and now < nextTime then
            rt.pendingPower, rt.pendingPowerMax = power, powerMax
            rt.powerTextPending = true
            QueuePowerTextFlush(frame, rt, nextTime - now)
            return
        end
        rt.nextPowerTextTime = now + throttle
    else
        rt.pendingPower, rt.pendingPowerMax = nil, nil
        rt.powerTextPending = nil
        rt.nextPowerTextTime = nil
    end
    UpdateTextSlots(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt)
end

local NAME_EVENTS = { "UNIT_NAME_UPDATE" }
local NAME_COLOR_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" }
local NAME_STATUS_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_HEALTH" }
local HEALTH_TEXT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }
local INLINE_TARGET_EVENTS = { "UNIT_TARGET" }
local INLINE_NAME_UNITLESS_EVENTS = { "UNIT_NAME_UPDATE" }
local INLINE_COLOR_UNITLESS_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" }

local function ModeEnabled(mode)
    return mode ~= nil and mode ~= "NONE"
end

local function HealthTextEnabled(spec)
    if not (spec and spec.showHealthText ~= false) then
        return false
    end
    local left, center, right = ResolveHealthTextModes(spec.text)
    return ModeEnabled(left) or ModeEnabled(center) or ModeEnabled(right)
end

local function PowerTextEnabled(spec)
    if not (spec and spec.showPowerText ~= false and spec.power and spec.power.enabled == true) then
        return false
    end
    local text = spec.text or {}
    return ModeEnabled(text.powerLeft) or ModeEnabled(text.powerCenter) or ModeEnabled(text.powerRight)
end

local function InlineEnabled(frame, spec)
    local text = spec and spec.text
    local inline = text and text.inlineToT
    return frame and frame.unit == "target" and spec and spec.showName ~= false and inline and inline.enabled == true
end

function Text.IsEnabled(frame, spec)
    return (spec and spec.showName ~= false)
        or HealthTextEnabled(spec)
        or PowerTextEnabled(spec)
        or InlineEnabled(frame, spec)
end
local Runtime = {
    EMPTY_EVENTS = EMPTY_EVENTS,
    NAME_EVENTS = NAME_EVENTS,
    NAME_COLOR_EVENTS = NAME_COLOR_EVENTS,
    NAME_STATUS_EVENTS = NAME_STATUS_EVENTS,
    HEALTH_TEXT_EVENTS = HEALTH_TEXT_EVENTS,
    INLINE_TARGET_EVENTS = INLINE_TARGET_EVENTS,
    INLINE_NAME_UNITLESS_EVENTS = INLINE_NAME_UNITLESS_EVENTS,
    INLINE_COLOR_UNITLESS_EVENTS = INLINE_COLOR_UNITLESS_EVENTS,
    POWER_EVENTS = POWER_EVENTS,
    POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT,
    HealthTextEnabled = HealthTextEnabled,
    PowerTextEnabled = PowerTextEnabled,
    InlineEnabled = InlineEnabled,
    SetShownCached = SetShownCached,
    UpdateName = Text.UpdateName,
    UpdateHealth = Text.UpdateHealth,
    UpdatePower = Text.UpdatePower,
    UpdateInline = Text.UpdateInline,
}
MSUF.UFTextRuntime = Runtime
