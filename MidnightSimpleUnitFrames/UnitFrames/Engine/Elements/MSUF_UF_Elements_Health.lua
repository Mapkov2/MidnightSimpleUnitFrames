local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local C = MSUF.UFBarTextCommon
if not C then return end

local UF = C.UF
local CreateFrame = C.CreateFrame
local UnitHealth = C.UnitHealth
local UnitHealthMax = C.UnitHealthMax
local WHITE = C.WHITE
local SetStatusTexture = C.SetStatusTexture
local SetBarMinMax = C.SetBarMinMax
local SetBarMinMaxKnown = C.SetBarMinMaxKnown
local SetBarMinMaxPlain = C.SetBarMinMaxPlain or C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SetBarValueKnown = C.SetBarValueKnown
local SetBarValuePlain = C.SetBarValuePlain or C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyHealthStatusColor = C.ApplyHealthStatusColor
local ApplyBackgrounds = C.ApplyBackgrounds
local ApplyBarGradient = C.ApplyBarGradient
local RefreshUnitState = C.RefreshUnitState
local issecretvalue = _G.issecretvalue or function(_) return false end
local floor = C.floor or math.floor
local GetTime = C.GetTime or _G.GetTime
local type = type

if not SetBarMinMaxKnown then
    SetBarMinMaxKnown = function(bar, maxValue)
        return SetBarMinMax(bar, maxValue, true)
    end
end

if not SetBarValueKnown then
    SetBarValueKnown = function(bar, value, _, animate)
        return SetBarValue(bar, value, true, animate)
    end
end

-- In combat the boss/raid health values are secret, so the integer percent
-- bucket below can't be computed (it would require comparing secret values) and
-- the gradient recolor would otherwise run on every UNIT_HEALTH tick. Cap the
-- gradient recolor rate per bar instead: at this interval the color step is
-- imperceptible, and the next tick within the window carries the update.
local GRADIENT_SECRET_THROTTLE = 0.1
local Health = {
    events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION" },
}
local HEALTH_EVENTS_NO_FACTION = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS" }
local HEALTH_EVENTS_PLAYER = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_FLAGS" }
local GROUP_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }

local function StoreHealthValue(bar, unit, hp, hpSecret)
    if not bar then return end
    if hpSecret == nil then hpSecret = issecretvalue(hp) == true end
    if hpSecret then
        bar._msufHealthValue = nil
        bar._msufHealthValueUnit = nil
        return
    end
    bar._msufHealthValue = hp
    bar._msufHealthValueUnit = unit
end

local function StoreHealthMax(bar, unit, maxHP, maxSecret)
    if not bar then return end
    if maxSecret == nil then maxSecret = issecretvalue(maxHP) == true end
    if maxSecret then
        bar._msufHealthMax = nil
        bar._msufHealthMaxUnit = nil
        bar._msufHealthMaxSecret = nil
        bar._msufHealthMaxReady = nil
        return
    end
    bar._msufHealthMax = maxHP
    bar._msufHealthMaxUnit = unit
    bar._msufHealthMaxSecret = nil
    bar._msufHealthMaxReady = true
end

local function ConnectionStatusKey(frame, unit, event)
    if not RefreshUnitState then
        return nil
    end
    local state = RefreshUnitState(frame, unit, frame and frame.MSUFSpec, event or "UNIT_CONNECTION")
    if not state then
        return nil
    end
    if state.existsKnown == true and state.exists == false then
        return 1
    end
    if state.deadKnown == true and state.dead == true then
        return 2
    end
    if state.connectedKnown == true and state.connected == false then
        return 3
    end
    if state.existsKnown == true and state.deadKnown == true and state.connectedKnown == true then
        return 0
    end
    return nil
end

function Health.Create(frame, spec)
    if frame.hpBar then
        return
    end
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.02, 0.02, 0.025, spec and spec.backgroundAlpha or 0.72)
    frame.bg = bg
    frame.hpBarBG = bg
    frame.healthBg = bg

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
    frame.hpBar = bar
    frame.Health = bar
    frame.health = bar
end

function Health.Apply(frame, spec)
    if not frame.hpBar then
        Health.Create(frame, spec)
    end
    frame.Health = frame.hpBar
    frame.health = frame.hpBar
    frame.healthBg = frame.hpBarBG or frame.bg
    -- Drop any cached gradient percent bucket: the spec (mode/curve) and/or the
    -- frame's unit may have changed, so the next tick must recolor from scratch.
    frame.hpBar._msufGradientPct = nil
    frame._msufGradStashAt = nil
    frame._msufIsGroupFrame = spec and spec.scope == "group"
    frame._msufHealthColorByHealth = spec and spec.health and spec.health.mode == "gradient"
    frame._msufHealthBgDynamic = spec and spec.health and spec.health.backgroundMatchHealth == true
    frame._msufPowerBgDynamic = spec and spec.power and spec.power.backgroundMatchHealth == true
    frame._msufHealthConnectionColorKey = nil
    frame._msufHealthColdColor = frame._msufIsGroupFrame
        and frame._msufHealthColorByHealth ~= true
        or nil
    SetStatusTexture(frame.hpBar, spec and spec.health and spec.health.texture or spec and spec.texture or WHITE)
    if frame.hpBar.SetReverseFill then
        local reverse = spec and spec.health and spec.health.reverse == true
        if frame.hpBar._msufReverseFill ~= reverse then
            frame.hpBar:SetReverseFill(reverse)
            frame.hpBar._msufReverseFill = reverse
        end
    end
    SetBarSmoothing(frame.hpBar, spec and spec.health and spec.health.smooth == true)
    ApplyBackgrounds(frame)
    if ApplyBarGradient then
        ApplyBarGradient(frame, frame.hpBar, spec and spec.health and spec.health.barGradient, "hpGradients")
    end
    frame._msufUpdateHealthValue = frame.unit == "player" and Health.UpdateValuePlain or Health.UpdateValue
    frame._msufUpdateHealthMaxValue = frame.unit == "player" and Health.UpdateMaxValuePlain or Health.UpdateMaxValue
    frame._msufUpdateHealthConnection = Health.UpdateConnectionState
end

function Health.GetEvents(frame, spec)
    if frame._msufIsGroupFrame or (spec and spec.scope == "group") then
        return GROUP_HEALTH_EVENTS
    end
    local health = spec and spec.health
    local unit = frame and frame.unit
    if unit == "player" or (spec and spec.key == "player") then
        return HEALTH_EVENTS_PLAYER
    end
    if (health and health.mode) ~= "class" then
        return HEALTH_EVENTS_NO_FACTION
    end
    return Health.events
end

function Health.UpdateValuePlain(frame, event, unit)
    unit = unit or frame.unit
    if issecretvalue(unit) == true or unit ~= "player" then
        return Health.UpdateValue(frame, event, unit)
    end
    local bar = frame.hpBar
    if not bar then
        return
    end

    local hp = UnitHealth(unit)
    if issecretvalue(hp) == true then
        return Health.UpdateValue(frame, event, unit)
    end
    if hp == nil then hp = 0 end
    StoreHealthValue(bar, unit, hp, false)

    local maxUnit = bar._msufHealthMaxUnit
    local maxReady = bar._msufHealthMaxReady == true and maxUnit == unit
    local maxHP
    if maxReady then
        maxHP = bar._msufHealthMax
    else
        maxHP = UnitHealthMax(unit)
        if issecretvalue(maxHP) == true then
            return Health.UpdateValue(frame, event, unit)
        end
        if maxHP == nil then maxHP = 1 end
        StoreHealthMax(bar, unit, maxHP, false)
    end

    if bar._msufMinMaxInit ~= true then
        SetBarMinMaxPlain(bar, maxHP)
        bar._msufMinMaxInit = true
    end
    SetBarValuePlain(bar, hp, true)

    local coldColor = frame._msufHealthColdColor == true
    local updateColor
    if coldColor then
        updateColor = bar._msufStatusR == nil
    else
        updateColor = frame._msufHealthColorByHealth == true or bar._msufStatusR == nil
    end

    local gradientBucket
    if frame._msufHealthColorByHealth == true and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
        gradientBucket = floor((hp / maxHP) * 100 + 0.5)
        if bar._msufGradientPct == gradientBucket then
            updateColor = false
        end
    end

    local rawHealthColor
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
        if gradientBucket ~= nil then
            bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
        end
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

function Health.UpdateValue(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.hpBar
    if not bar then
        return
    end

    local hp = UnitHealth(unit)
    local hpSecret = issecretvalue(hp) == true
    if not hpSecret and hp == nil then hp = 0 end
    local cacheUnit = unit
    StoreHealthValue(bar, cacheUnit, hp, hpSecret)

    local maxUnit = bar._msufHealthMaxUnit
    local maxReady = bar._msufHealthMaxReady == true
        and cacheUnit ~= nil
        and maxUnit == cacheUnit
    local maxHP, maxSecret
    if maxReady then
        maxHP = bar._msufHealthMax
        maxSecret = bar._msufHealthMaxSecret == true
    else
        maxHP = UnitHealthMax(unit)
        maxSecret = issecretvalue(maxHP) == true
        if not maxSecret and maxHP == nil then maxHP = 1 end
        StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
    end

    if bar._msufMinMaxInit ~= true then
        SetBarMinMaxKnown(bar, maxHP, maxSecret)
        bar._msufMinMaxInit = true
    end
    SetBarValueKnown(bar, hp, hpSecret, true)

    local coldColor = frame._msufHealthColdColor == true
    local updateColor
    if coldColor then
        updateColor = bar._msufStatusR == nil
    else
        updateColor = frame._msufHealthColorByHealth == true or bar._msufStatusR == nil
    end

    local gradientBucket
    if frame._msufHealthColorByHealth == true then
        if not (hpSecret or maxSecret)
            and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
            gradientBucket = floor((hp / maxHP) * 100 + 0.5)
            if bar._msufGradientPct == gradientBucket then
                updateColor = false
            end
        elseif GetTime then
            bar._msufGradientPct = nil
            local now = GetTime()
            local nextAt = bar._msufGradientThrottleAt
            if nextAt and now < nextAt then
                updateColor = false
            else
                bar._msufGradientThrottleAt = now + GRADIENT_SECRET_THROTTLE
            end
        end
    end

    local rawHealthColor
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_HEALTH")
        if gradientBucket ~= nil then
            bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
        end
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

function Health.UpdateMaxValuePlain(frame, event, unit)
    unit = unit or frame.unit
    if issecretvalue(unit) == true or unit ~= "player" then
        return Health.UpdateMaxValue(frame, event, unit)
    end
    local bar = frame.hpBar
    if not bar then
        return
    end

    local hp = UnitHealth(unit)
    if issecretvalue(hp) == true then
        return Health.UpdateMaxValue(frame, event, unit)
    end
    if hp == nil then hp = 0 end
    local maxHP = UnitHealthMax(unit)
    if issecretvalue(maxHP) == true then
        return Health.UpdateMaxValue(frame, event, unit)
    end
    if maxHP == nil then maxHP = 1 end
    StoreHealthValue(bar, unit, hp, false)
    StoreHealthMax(bar, unit, maxHP, false)

    SetBarMinMaxPlain(bar, maxHP)
    bar._msufMinMaxInit = true
    SetBarValuePlain(bar, hp, false)
    SnapBarInterpolation(bar)

    local rawHealthColor
    local updateColor = frame._msufHealthColorByHealth == true or frame._msufHealthColdColor ~= true or bar._msufStatusR == nil
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
        bar._msufGradientPct = nil
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

function Health.UpdateMaxValue(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.hpBar
    if not bar then
        return
    end

    local hp = UnitHealth(unit)
    local hpSecret = issecretvalue(hp) == true
    if not hpSecret and hp == nil then hp = 0 end
    local maxHP = UnitHealthMax(unit)
    local maxSecret = issecretvalue(maxHP) == true
    if not maxSecret and maxHP == nil then maxHP = 1 end
    local cacheUnit = unit
    StoreHealthValue(bar, cacheUnit, hp, hpSecret)
    StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)

    SetBarMinMaxKnown(bar, maxHP, maxSecret)
    bar._msufMinMaxInit = true
    SetBarValueKnown(bar, hp, hpSecret, false)
    SnapBarInterpolation(bar)

    local rawHealthColor
    local updateColor = frame._msufHealthColorByHealth == true or frame._msufHealthColdColor ~= true or bar._msufStatusR == nil
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_MAXHEALTH")
        bar._msufGradientPct = nil
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

function Health.UpdateConnectionState(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.hpBar
    if not bar then
        return
    end

    local cacheUnit = unit
    local valueUnit = bar._msufHealthValueUnit
    local hp = cacheUnit ~= nil and valueUnit == cacheUnit and bar._msufHealthValue or nil
    local hpSecret = issecretvalue(hp) == true
    if not hpSecret and hp == nil then
        hp = UnitHealth(unit)
        hpSecret = issecretvalue(hp) == true
        if not hpSecret and hp == nil then hp = 0 end
        StoreHealthValue(bar, cacheUnit, hp, hpSecret)
    end

    local maxUnit = bar._msufHealthMaxUnit
    local maxReady = bar._msufHealthMaxReady == true
        and cacheUnit ~= nil
        and maxUnit == cacheUnit
    local maxHP, maxSecret
    if maxReady then
        maxHP = bar._msufHealthMax
        maxSecret = bar._msufHealthMaxSecret == true
    else
        maxHP = UnitHealthMax(unit)
        maxSecret = issecretvalue(maxHP) == true
        if not maxSecret and maxHP == nil then maxHP = 1 end
        StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
    end

    local wroteBar
    if bar._msufMinMaxInit ~= true then
        wroteBar = SetBarMinMaxKnown(bar, maxHP, maxSecret) or wroteBar
        bar._msufMinMaxInit = true
    end
    wroteBar = SetBarValueKnown(bar, hp, hpSecret, false) or wroteBar
    if wroteBar or bar._msufInterpolating == true then
        SnapBarInterpolation(bar)
    end

    local colorKey = ConnectionStatusKey(frame, unit, event)
    if colorKey == nil or frame._msufHealthConnectionColorKey ~= colorKey then
        local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event or "UNIT_CONNECTION")
        frame._msufHealthConnectionColorKey = colorKey
        if rawHealthColor ~= true then
            bar._msufGradientPct = nil
        end
        if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
            ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
        end
    end
    return hp, maxHP
end

function Health.Update(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.hpBar
    if not bar then
        return
    end
    local coldColor = frame._msufHealthColdColor == true

    if event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
        local cacheUnit = unit
        local hpUnit = bar._msufHealthValueUnit
        local maxUnit = bar._msufHealthMaxUnit
        local hp = cacheUnit ~= nil and hpUnit == cacheUnit and bar._msufHealthValue or nil
        local maxHP = cacheUnit ~= nil and maxUnit == cacheUnit and bar._msufHealthMax or nil
        local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event)
        if rawHealthColor ~= true then
            bar._msufGradientPct = nil
        end
        if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
            ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
        end
        return hp, maxHP
    end

    local hp = UnitHealth(unit)
    local hpSecret = issecretvalue(hp) == true
    if not hpSecret and hp == nil then hp = 0 end
    local cacheUnit = unit
    StoreHealthValue(bar, cacheUnit, hp, hpSecret)

    local animate = event == "UNIT_HEALTH"
    local maxUnit = bar._msufHealthMaxUnit
    local maxReady = bar._msufHealthMaxReady == true
        and cacheUnit ~= nil
        and maxUnit == cacheUnit
    local maxHP, maxSecret
    if animate and maxReady then
        maxHP = bar._msufHealthMax
        maxSecret = bar._msufHealthMaxSecret == true
    else
        maxHP = UnitHealthMax(unit)
        maxSecret = issecretvalue(maxHP) == true
        if not maxSecret and maxHP == nil then maxHP = 1 end
        StoreHealthMax(bar, cacheUnit, maxHP, maxSecret)
    end

    -- Max health only changes on UNIT_MAXHEALTH (and forced applies); skip the
    -- SetMinMaxValues C call on the high-frequency UNIT_HEALTH tick. Gated on the
    -- plain event string, so the (possibly secret) max is never compared.
    if not animate or bar._msufMinMaxInit ~= true then
        SetBarMinMaxKnown(bar, maxHP, maxSecret)
        bar._msufMinMaxInit = true
    end
    SetBarValueKnown(bar, hp, hpSecret, animate)
    if not animate then
        SnapBarInterpolation(bar)
    end

    local updateColor
    if coldColor then
        updateColor = bar._msufStatusR == nil or (event ~= "UNIT_HEALTH" and event ~= "UNIT_MAXHEALTH")
    else
        updateColor = frame._msufHealthColorByHealth == true
            or event ~= "UNIT_HEALTH"
            or bar._msufStatusR == nil
    end

    -- Gradient color is a pure function of the health percent (the cached
    -- alive/dead state only refreshes on non-health events). On a UNIT_HEALTH
    -- tick, recomputing the color curve + writing SetStatusBarColor is wasted
    -- work unless the integer percent bucket actually changed. Cache the bucket
    -- per bar and skip the recolor when it is unchanged. _msufGradientPct is only
    -- trusted while it holds a live-gradient bucket; the recolor below resets it
    -- to nil whenever the dead/offline (grey) path runs, so a later tick at the
    -- same percent still recolors back to the gradient.
    local gradientBucket
    if event == "UNIT_HEALTH" and frame._msufHealthColorByHealth == true then
        if not (hpSecret or maxSecret)
            and type(hp) == "number" and type(maxHP) == "number" and maxHP > 0 then
            gradientBucket = floor((hp / maxHP) * 100 + 0.5)
            if bar._msufGradientPct == gradientBucket then
                updateColor = false
            end
        elseif GetTime then
            -- Secret health (combat): the bucket above can't be computed, so the
            -- value-based skip is unavailable. Throttle the gradient recolor by
            -- time instead -- recolor at most once per window, letting the next
            -- in-window tick carry the change. The first recolor (no timestamp
            -- yet) is never suppressed. A stale per-percent bucket left from the
            -- plain path is cleared so the next plain tick recomputes from scratch.
            bar._msufGradientPct = nil
            local now = GetTime()
            local nextAt = bar._msufGradientThrottleAt
            if nextAt and now < nextAt then
                updateColor = false
            else
                bar._msufGradientThrottleAt = now + GRADIENT_SECRET_THROTTLE
            end
        end
    end

    local rawHealthColor
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, nil, event)
        if gradientBucket ~= nil then
            bar._msufGradientPct = rawHealthColor == true and gradientBucket or nil
        end
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

UF.RegisterElement("Health", Health)
