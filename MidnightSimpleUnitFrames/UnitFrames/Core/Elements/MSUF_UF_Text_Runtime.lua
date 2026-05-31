local _, MSUF = ...
local Text = MSUF and MSUF.UFText
local UF = MSUF and MSUF.UF
if not (Text and UF) then return end

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
local Secrets = MSUF.Secrets or {}
local IsSecret = Text.IsSecret or function(_) return false end
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local UpdateTextSlots = Text.UpdateTextSlots
local UpdateTextSlotsPlain = Text.UpdateTextSlotsPlain or UpdateTextSlots
local UpdateTextSlotsSecret = Text.UpdateTextSlotsSecret or UpdateTextSlots
local QueueHealthTextFlush = Text.QueueHealthTextFlush
local QueuePowerTextFlush = Text.QueuePowerTextFlush
local ResolveHealthTextModes = Text.ResolveHealthTextModes
local AnchorInlineToName = Text.AnchorInlineToName
local EMPTY_EVENTS = Text.EMPTY_EVENTS
local POWER_EVENTS = Text.POWER_EVENTS
local POWER_EVENTS_FREQUENT = Text.POWER_EVENTS_FREQUENT

local function RegionShown(region)
    if not region then
        return false
    end
    if region._msufShown ~= nil then
        return region._msufShown == true
    end
    return region.IsShown and region:IsShown() or false
end

local function ReadPowerValues(unit)
    local powerType
    if UnitPowerType then
        powerType = UnitPowerType(unit)
    end
    local power, maxPower
    if not IsSecret(powerType) and powerType ~= nil then
        power = UnitPower(unit, powerType)
        maxPower = UnitPowerMax(unit, powerType)
    else
        power = UnitPower(unit)
        maxPower = UnitPowerMax(unit)
    end
    if not IsSecret(power) and power == nil then power = 0 end
    if not IsSecret(maxPower) and maxPower == nil then maxPower = 1 end
    return power, maxPower
end

local function ReadPowerValuesPlain(frame, unit, event)
    local powerType = frame._msufTextPowerType
    if frame._msufTextPowerTypeKnown ~= true
        or event == "UNIT_DISPLAYPOWER"
        or event == "MSUF_APPLY"
        or event == "MSUF_FORCE_UPDATE" then
        local rawType = UnitPowerType and UnitPowerType(unit) or nil
        powerType = IsSecret(rawType) and nil or rawType
        frame._msufTextPowerType = powerType
        frame._msufTextPowerTypeKnown = true
    end

    local power
    if powerType ~= nil then
        power = UnitPower(unit, powerType)
    else
        power = UnitPower(unit)
    end

    local maxPower = frame._msufTextPowerMax
    if maxPower == nil
        or event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER"
        or event == "UNIT_POWER_BAR_SHOW"
        or event == "UNIT_POWER_BAR_HIDE"
        or event == "MSUF_APPLY"
        or event == "MSUF_FORCE_UPDATE" then
        if powerType ~= nil then
            maxPower = UnitPowerMax(unit, powerType)
        else
            maxPower = UnitPowerMax(unit)
        end
        frame._msufTextPowerMax = maxPower
    end

    return power, maxPower
end

function Text.UpdateNameColor(frame, event, unit)
    if RegionShown(frame and frame.nameText) then
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

    if UnitMissing(inlineUnit) then
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
    SetTextCached(frame.totInlineText, name)
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
        frame._msufNameStatusUnit = nil
        frame._msufNameStatusHidden = nil
        SetTextCached(frame.nameText, "")
        frame.nameText._msufShown = nil
        SetShownCached(frame.nameText, false)
        return
    end
    if rt and rt.hideNameOnDeadOffline == true then
        local connected = UnitIsConnected and UnitIsConnected(unit)
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
        local hidden = false
        if not IsSecret(connected) and connected == false then
            hidden = true
        elseif not IsSecret(dead) and dead == true then
            hidden = true
        end
        if event == "UNIT_HEALTH"
            and frame._msufNameStatusUnit == unit
            and frame._msufNameStatusHidden == hidden then
            return
        end
        frame._msufNameStatusUnit = unit
        frame._msufNameStatusHidden = hidden
        if hidden then
            SetTextCached(frame.nameText, "")
            frame.nameText._msufShown = nil
            SetShownCached(frame.nameText, false)
            return
        end
    else
        frame._msufNameStatusUnit = nil
        frame._msufNameStatusHidden = nil
    end
    frame.nameText._msufShown = nil
    SetShownCached(frame.nameText, true)
    -- UnitName can be a secret string for target/boss units. Do not cache,
    -- compare, shorten, or branch on it in Lua.
    SetTextCached(frame.nameText, UnitName(unit))
    Text.UpdateNameColor(frame, event, unit)
end

function Text.UpdateHealth(frame, event, unit, hp, hpMax)
    unit = unit or frame.unit
    local rt = frame._msufTextRuntime
    if not rt or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
        return
    end

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

    if rt.healthPlain == true then
        local hpSecret = IsSecret(hp)
        local hpMaxSecret = IsSecret(hpMax)
        if not hpSecret and hp == nil then
            hp = UnitHealth(unit)
            hpSecret = IsSecret(hp)
        end
        if not hpMaxSecret and hpMax == nil then
            hpMax = UnitHealthMax(unit)
            hpMaxSecret = IsSecret(hpMax)
        end

        if rt.healthNeedsMissing == true then
            local calc = frame and frame._msufHealthCalc
            rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
        else
            rt.healthMissing = nil
        end

        if not (hpSecret or hpMaxSecret or IsSecret(rt.healthMissing)) then
            hp = hp or 0
            hpMax = hpMax or 1
            if event == "UNIT_HEALTH"
                and rt._lastHealthTextHP == hp
                and rt._lastHealthTextMax == hpMax
                and rt._lastHealthTextMissing == rt.healthMissing then
                return
            end
            rt._lastHealthTextHP = hp
            rt._lastHealthTextMax = hpMax
            rt._lastHealthTextMissing = rt.healthMissing
            UpdateTextSlotsPlain(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
            return
        end

        rt._lastHealthTextHP = nil
        rt._lastHealthTextMax = nil
        rt._lastHealthTextMissing = nil
    end

    local hpSecret = IsSecret(hp)
    local hpMaxSecret = IsSecret(hpMax)
    if not hpSecret and hp == nil then
        hp = UnitHealth(unit)
        hpSecret = IsSecret(hp)
    end
    if not hpMaxSecret and hpMax == nil then
        hpMax = UnitHealthMax(unit)
        hpMaxSecret = IsSecret(hpMax)
    end

    -- Non-player units can return protected values. Do not probe them for
    -- equality; the secret sink below passes values straight to C.
    rt._lastHpRaw, rt._lastHpMaxRaw = hp, hpMax

    if rt.healthNeedsMissing == true then
        local calc = frame and frame._msufHealthCalc
        rt.healthMissing = calc and calc.GetMissingHealth and calc:GetMissingHealth() or nil
    else
        rt.healthMissing = nil
    end

    UpdateTextSlotsSecret(rt.healthSlots, rt.healthSlotCount, hp, hpMax, unit, HealthPercent, rt.healthNeedsPercent, rt)
end

function Text.MarkHealthDirty(frame, event, unit, hp, hpMax)
    unit = unit or frame.unit
    local rt = frame._msufTextRuntime
    if not rt or not rt.healthSlotCount or rt.healthSlotCount <= 0 then
        return
    end
    if event ~= "UNIT_HEALTH" or not GetTime or not QueueHealthTextFlush then
        return Text.UpdateHealth(frame, event, unit, hp, hpMax)
    end

    local throttle = rt.healthThrottle or 0
    if throttle <= 0 then
        return Text.UpdateHealth(frame, event, unit, hp, hpMax)
    end

    local now = GetTime()
    local nextTime = rt.nextHealthTextTime
    rt.pendingHP, rt.pendingHPMax = hp, hpMax
    rt.healthTextPending = true

    if not nextTime or now >= nextTime then
        rt.nextHealthTextTime = now + throttle
        QueueHealthTextFlush(frame, rt, 0)
    else
        QueueHealthTextFlush(frame, rt, nextTime - now)
    end
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

    local throttle = rt.powerThrottle or 0
    if throttle > 0
        and (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT")
        and GetTime then
        local now = GetTime()
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

    if rt.powerPlain == true then
        local powerSecret = IsSecret(power)
        local powerMaxSecret = IsSecret(powerMax)
        if not (powerSecret or powerMaxSecret) and (power == nil or powerMax == nil) then
            local currentPower, currentMax = ReadPowerValuesPlain(frame, unit, event)
            if power == nil then
                power = currentPower
                powerSecret = IsSecret(power)
            end
            if powerMax == nil then
                powerMax = currentMax
                powerMaxSecret = IsSecret(powerMax)
            end
        end
        rt.healthMissing = nil

        if not (powerSecret or powerMaxSecret) then
            power = power or 0
            powerMax = powerMax or 1
            if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT")
                and rt._lastPowerTextPower == power
                and rt._lastPowerTextMax == powerMax then
                return
            end
            rt._lastPowerTextPower = power
            rt._lastPowerTextMax = powerMax
            UpdateTextSlotsPlain(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt)
            return
        end

        rt._lastPowerTextPower = nil
        rt._lastPowerTextMax = nil
    end

    local powerSecret = IsSecret(power)
    local powerMaxSecret = IsSecret(powerMax)
    if not powerSecret and not powerMaxSecret and (power == nil or powerMax == nil) then
        local currentPower, currentMax = ReadPowerValues(unit)
        if power == nil then
            power = currentPower
            powerSecret = IsSecret(power)
        end
        if powerMax == nil then
            powerMax = currentMax
            powerMaxSecret = IsSecret(powerMax)
        end
    end
    rt.healthMissing = nil

    -- Secret-capable unit tokens are fail-open: no Lua equality probes.
    rt._lastPowerRaw, rt._lastPowerMaxRaw = power, powerMax

    UpdateTextSlotsSecret(rt.powerSlots, rt.powerSlotCount, power, powerMax, unit, PowerPercent, rt.powerNeedsPercent, rt)
end

local NAME_EVENTS = { "UNIT_NAME_UPDATE" }
local NAME_COLOR_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" }
local NAME_STATUS_EVENTS = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_HEALTH" }
local NAME_STATUS_COLD_EVENTS = NAME_COLOR_EVENTS
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
    NAME_STATUS_COLD_EVENTS = NAME_STATUS_COLD_EVENTS,
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

local TextStructure = {}
TextStructure.GetEvents = Text.GetEvents
TextStructure.GetUnitlessEvents = Text.GetUnitlessEvents
TextStructure.Create = Text.Create
TextStructure.Apply = Text.Apply
TextStructure.IsEnabled = Text.IsEnabled
UF.RegisterElement("Text", TextStructure)

local function NameTextNeedsHealthStatusEvent(frame, spec)
    if spec and spec.scope == "group" then
        return false
    end
    local unit = frame and frame.unit
    return unit ~= "player"
end

local NameText = {}

function NameText.IsEnabled(frame, spec)
    return spec and spec.showName ~= false
end

function NameText.GetEvents(frame, spec)
    if spec and spec.scope == "group" then
        return EMPTY_EVENTS
    end
    local text = spec and spec.text
    if text and text.hideNameOnDeadOffline == true then
        if not NameTextNeedsHealthStatusEvent(frame, spec) then
            return NAME_STATUS_COLD_EVENTS or NAME_COLOR_EVENTS
        end
        return NAME_STATUS_EVENTS
    end
    return text and text.nameNpcColor == true and NAME_COLOR_EVENTS or NAME_EVENTS
end

function NameText.Update(frame, event, unit)
    Text.UpdateName(frame, event, unit or frame.unit)
end

function NameText.Disable(frame)
    SetShownCached(frame and frame.nameText, false)
end

UF.RegisterElement("NameText", NameText)

local HealthText = {}

function HealthText.IsEnabled(frame, spec)
    return HealthTextEnabled(spec)
end

function HealthText.GetEvents()
    return HEALTH_TEXT_EVENTS
end

function HealthText.Update(frame, event, unit, hp, hpMax)
    if event == "UNIT_HEALTH" then
        return Text.MarkHealthDirty(frame, event, unit or frame.unit, hp, hpMax)
    end
    Text.UpdateHealth(frame, event, unit or frame.unit, hp, hpMax)
end

function HealthText.Disable(frame)
    SetShownCached(frame and frame.hpTextLeft, false)
    SetShownCached(frame and frame.hpTextCenter, false)
    SetShownCached(frame and frame.hpTextRight, false)
end

UF.RegisterElement("HealthText", HealthText)

local PowerText = {}

function PowerText.IsEnabled(frame, spec)
    return PowerTextEnabled(spec)
end

function PowerText.GetEvents(frame, spec)
    return spec and spec.power and spec.power.frequent == true and POWER_EVENTS_FREQUENT or POWER_EVENTS
end

function PowerText.Update(frame, event, unit, power, powerMax)
    Text.UpdatePower(frame, event, unit or frame.unit, power, powerMax)
end

function PowerText.Disable(frame)
    SetShownCached(frame and frame.powerTextLeft, false)
    SetShownCached(frame and frame.powerTextCenter, false)
    SetShownCached(frame and frame.powerTextRight, false)
end

UF.RegisterElement("PowerText", PowerText)

local InlineToT = {}

function InlineToT.IsEnabled(frame, spec)
    return InlineEnabled(frame, spec)
end

function InlineToT.GetEvents()
    return INLINE_TARGET_EVENTS
end

function InlineToT.GetUnitlessEvents(frame, spec)
    local inline = spec and spec.text and spec.text.inlineToT
    if not inline then
        return EMPTY_EVENTS
    end
    if (inline.colorMode and inline.colorMode ~= "DEFAULT")
        or inline.targetNameClassColor == true
        or inline.targetNameNpcColor == true
        or inline.totNameClassColor == true
        or inline.totNameNpcColor == true then
        return INLINE_COLOR_UNITLESS_EVENTS
    end
    return INLINE_NAME_UNITLESS_EVENTS
end

function InlineToT.Update(frame, event, unit)
    Text.UpdateInline(frame, event, unit)
end

function InlineToT.Disable(frame)
    SetShownCached(frame and frame.totInlineSep, false)
    SetShownCached(frame and frame.totInlineText, false)
    if frame then
        frame._msufInlineRaw, frame._msufInlineText, frame._msufInlineStamp = nil, nil, nil
    end
end

UF.RegisterElement("InlineToT", InlineToT)
