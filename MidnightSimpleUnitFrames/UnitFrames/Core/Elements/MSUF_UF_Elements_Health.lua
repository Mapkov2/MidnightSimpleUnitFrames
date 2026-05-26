local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local C = MSUF.UFBarTextCommon
if not C then return end

local UF = C.UF
local CreateFrame = C.CreateFrame
local UnitClass = C.UnitClass
local UnitExists = C.UnitExists
local UnitHealth = C.UnitHealth
local UnitHealthMax = C.UnitHealthMax
local UnitGetTotalAbsorbs = C.UnitGetTotalAbsorbs
local UnitPower = C.UnitPower
local UnitPowerMax = C.UnitPowerMax
local UnitPowerType = C.UnitPowerType
local UnitHealthPercent = C.UnitHealthPercent
local UnitPowerPercent = C.UnitPowerPercent
local AbbreviateNumbers = C.AbbreviateNumbers
local AbbreviateLargeNumbers = C.AbbreviateLargeNumbers
local InCombatLockdown = C.InCombatLockdown
local UnitName = C.UnitName
local UnitIsPlayer = C.UnitIsPlayer
local UnitIsDeadOrGhost = C.UnitIsDeadOrGhost
local UnitIsConnected = C.UnitIsConnected
local UnitReaction = C.UnitReaction
local UnitSelectionColor = C.UnitSelectionColor
local GetUnitClassification = C.GetUnitClassification
local PowerBarColor = C.PowerBarColor
local RAID_CLASS_COLORS = C.RAID_CLASS_COLORS
local type = C.type
local tonumber = C.tonumber
local format = C.format
local byte = C.byte
local sub = C.sub
local abs = C.abs
local floor = C.floor
local max = C.max
local GetTime = C.GetTime
local C_Timer = C.C_Timer
local StatusBarInterpolation = C.StatusBarInterpolation
local SMOOTH_INTERP = C.SMOOTH_INTERP
local WHITE = C.WHITE
local SCALE_100 = C.SCALE_100
local REVERSE_HEALTH_MODE = C.REVERSE_HEALTH_MODE
local EMPTY_EVENTS = C.EMPTY_EVENTS
local POWER_EVENTS = C.POWER_EVENTS
local POWER_EVENTS_FREQUENT = C.POWER_EVENTS_FREQUENT
local TEXT_EVENT_SETS = C.TEXT_EVENT_SETS
local TEXT_EVENT_SETS_ABSORB = C.TEXT_EVENT_SETS_ABSORB
local ClampFrameLayer = C.ClampFrameLayer
local DrawSubLayer = C.DrawSubLayer
local GetLayerBaseLevel = C.GetLayerBaseLevel
local SetStatusTexture = C.SetStatusTexture
local ApplyStatusColor = C.ApplyStatusColor
local SetBarMinMax = C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local ApplyTextureColor = C.ApplyTextureColor
local SetShownCached = C.SetShownCached
local SetFrameLevelCached = C.SetFrameLevelCached
local ExternalFrameWidth = C.ExternalFrameWidth
local ClassColor = C.ClassColor
local UnitNPCKind = C.UnitNPCKind
local NPCColor = C.NPCColor
local GradientColor = C.GradientColor
local HealthColor = C.HealthColor
local ApplyHealthStatusColor = C.ApplyHealthStatusColor
local ApplyBackgrounds = C.ApplyBackgrounds
local PowerColor = C.PowerColor
local RefreshUnitState = C.RefreshUnitState
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local Health = {
    events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION" },
}
local GROUP_HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }

local calcUnsupported
local function EnsureHealthCalc(frame)
    if calcUnsupported then
        return nil
    end
    local calc = frame._msufHealthCalc
    if calc then
        return calc
    end
    if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
        calcUnsupported = true
        return nil
    end
    calc = CreateUnitHealPredictionCalculator()
    if not calc then
        calcUnsupported = true
        return nil
    end
    if calc.SetIncomingHealOverflowPercent then
        calc:SetIncomingHealOverflowPercent(1)
    end
    frame._msufHealthCalc = calc
    return calc
end

local function ReadHealthValues(frame, unit)
    local calc = EnsureHealthCalc(frame)
    if calc then
        UnitGetDetailedHealPrediction(unit, "player", calc)
        return calc:GetCurrentHealth(), calc:GetMaximumHealth(), calc
    end
    return UnitHealth(unit), UnitHealthMax(unit), nil
end

local function ReadDirectHealthValues(unit)
    local hp = UnitHealth(unit)
    local maxHP = UnitHealthMax(unit)
    return hp or 0, maxHP or 1, nil
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

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
    frame.hpBar = bar
    frame.Health = bar
end

function Health.Apply(frame, spec)
    if not frame.hpBar then
        Health.Create(frame, spec)
    end
    frame._msufHealthColorByHealth = spec and spec.health and spec.health.mode == "gradient"
    frame._msufHealthBgDynamic = spec and spec.health and spec.health.backgroundMatchHealth == true
    frame._msufPowerBgDynamic = spec and spec.power and spec.power.backgroundMatchHealth == true
    frame._msufHealthColdColor = spec and spec.scope == "group"
        and frame._msufHealthColorByHealth ~= true
        or nil
    if spec and spec.scope == "group" then
        frame._msufHealthCalc = nil
    end
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
end

function Health.GetEvents(frame, spec)
    if spec and spec.scope == "group" then
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

    local hp, maxHP, calc
    if spec and spec.scope == "group" then
        hp, maxHP, calc = ReadDirectHealthValues(unit)
    else
        hp, maxHP, calc = ReadHealthValues(frame, unit)
    end
    local animate = event == "UNIT_HEALTH"

    SetBarMinMax(bar, maxHP, true)
    SetBarValue(bar, hp, true, animate)
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

    local rawHealthColor
    if updateColor then
        rawHealthColor = ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, calc)
    end
    if updateColor and not rawHealthColor and (frame._msufHealthBgDynamic == true or frame._msufPowerBgDynamic == true) then
        ApplyBackgrounds(frame, frame._msufHealthBgDynamic == true, frame._msufPowerBgDynamic == true)
    end
    return hp, maxHP
end

UF.RegisterElement("Health", Health)
