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
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyHealthStatusColor = C.ApplyHealthStatusColor
local ApplyBackgrounds = C.ApplyBackgrounds
local RefreshUnitState = C.RefreshUnitState
local ApplyBarGradient = C.ApplyBarGradient
local issecretvalue = _G.issecretvalue or function(_) return false end
local floor = C.floor or math.floor
local GetTime = C.GetTime or _G.GetTime
local type = type

-- In combat the boss/raid health values are secret, so the integer percent
-- bucket below can't be computed (it would require comparing secret values) and
-- the gradient recolor would otherwise run on every UNIT_HEALTH tick. Cap the
-- gradient recolor rate per bar instead: at this interval the color step is
-- imperceptible, and the next tick within the window carries the update.
local GRADIENT_SECRET_THROTTLE = 0.1
local Health = {
    events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION" },
}
local GROUP_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" }

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
    frame._msufIsGroupFrame = spec and spec.scope == "group"
    frame._msufHealthColorByHealth = spec and spec.health and spec.health.mode == "gradient"
    frame._msufHealthBgDynamic = spec and spec.health and spec.health.backgroundMatchHealth == true
    frame._msufPowerBgDynamic = spec and spec.power and spec.power.backgroundMatchHealth == true
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
end

function Health.GetEvents(frame, spec)
    if frame._msufIsGroupFrame then
        return GROUP_HEALTH_EVENTS
    end
    return Health.events
end

function Health.Update(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.hpBar
    if not bar then
        return
    end
    local spec = frame.MSUFSpec
    local coldColor = frame._msufHealthColdColor == true
    if RefreshUnitState and not (coldColor and event == "UNIT_HEALTH") then
        RefreshUnitState(frame, unit, spec, event)
    end

    if event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
        local hp, maxHP = bar._msufHealthValue, bar._msufHealthMax
        local rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP)
        if not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
            ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
        end
        return hp, maxHP
    end

    local hp = UnitHealth(unit)
    if issecretvalue(hp) ~= true and hp == nil then hp = 0 end
    bar._msufHealthValue = hp

    local animate = event == "UNIT_HEALTH"
    local maxReady = bar._msufHealthMaxReady == true and bar._msufHealthMaxUnit == unit
    local maxHP
    if animate and maxReady then
        maxHP = bar._msufHealthMax
    else
        maxHP = UnitHealthMax(unit)
        if issecretvalue(maxHP) ~= true and maxHP == nil then maxHP = 1 end
        bar._msufHealthMax = maxHP
        bar._msufHealthMaxUnit = unit
        bar._msufHealthMaxReady = true
    end

    -- Max health only changes on UNIT_MAXHEALTH (and forced applies); skip the
    -- SetMinMaxValues C call on the high-frequency UNIT_HEALTH tick. Gated on the
    -- plain event string, so the (possibly secret) max is never compared.
    if not animate or bar._msufMinMaxInit ~= true then
        SetBarMinMax(bar, maxHP, true)
        bar._msufMinMaxInit = true
    end
    local interp = animate and bar._msufSmoothInterp or nil
    if interp then
        bar:SetValue(hp, interp)
        bar._msufInterpolating = true
    else
        bar:SetValue(hp)
    end
    bar._msufValue = nil
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
        local hpSecret = issecretvalue(hp) == true
        local maxSecret = issecretvalue(maxHP) == true
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
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP)
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
