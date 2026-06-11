local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local C = MSUF.UFBarTextCommon
if not C then return end

local UF = C.UF
local CreateFrame = C.CreateFrame
local UnitPower = C.UnitPower
local UnitPowerMax = C.UnitPowerMax
local UnitPowerType = C.UnitPowerType
local tonumber = C.tonumber
local floor = C.floor
local WHITE = C.WHITE
local POWER_EVENTS = C.POWER_EVENTS
local POWER_EVENTS_FREQUENT = C.POWER_EVENTS_FREQUENT
local SetStatusTexture = C.SetStatusTexture
local ApplyStatusColor = C.ApplyStatusColor
local SetBarMinMax = C.SetBarMinMax
local SetBarMinMaxKnown = C.SetBarMinMaxKnown
local SetBarMinMaxPlain = C.SetBarMinMaxPlain or C.SetBarMinMax
local SetBarValue = C.SetBarValue
local SetBarValueKnown = C.SetBarValueKnown
local SetBarValuePlain = C.SetBarValuePlain or C.SetBarValue
local SnapBarInterpolation = C.SnapBarInterpolation
local SetBarSmoothing = C.SetBarSmoothing
local SetShownCached = C.SetShownCached
local SetFrameLevelCached = C.SetFrameLevelCached
local ExternalFrameWidth = C.ExternalFrameWidth
local ApplyBackgrounds = C.ApplyBackgrounds
local ApplyBarGradient = C.ApplyBarGradient
local HideBarGradient = C.HideBarGradient
local PowerColor = C.PowerColor
local issecretvalue = _G.issecretvalue or function(_) return false end
local Power = {}

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

local function ReadPowerType(unit)
    if not UnitPowerType then
        return nil, nil
    end
    local powerType, powerToken = UnitPowerType(unit)
    if issecretvalue(powerType) == true then powerType = nil end
    if issecretvalue(powerToken) == true then powerToken = nil end
    return powerType, powerToken
end

local function ReadPowerMeta(frame, bar, unit, force)
    if not force and bar._msufPowerMaxReady == true and bar._msufPowerMaxUnit == unit then
        return bar._msufPowerType, bar._msufPowerMax, bar._msufPowerToken, false, bar._msufPowerMaxSecret == true
    end

    local needsType = frame and frame._msufPowerBarNeedsType == true
    local powerType, powerToken
    if needsType then
        powerType, powerToken = ReadPowerType(unit)
    end
    local maxPower
    -- powerType is already secret-sanitised to nil by ReadPowerType, so a plain
    -- nil test is sufficient here -- no second issecretvalue C call needed.
    if powerType == nil then
        maxPower = UnitPowerMax(unit)
    else
        maxPower = UnitPowerMax(unit, powerType)
    end
    local maxSecret = issecretvalue(maxPower) == true
    if not maxSecret and maxPower == nil then maxPower = 1 end

    local powerMetaChanged = powerType ~= bar._msufPowerType or powerToken ~= bar._msufPowerToken
    bar._msufPowerType = powerType
    bar._msufPowerToken = powerToken
    bar._msufPowerMax = maxPower
    bar._msufPowerMaxSecret = maxSecret or nil
    bar._msufPowerMaxUnit = unit
    bar._msufPowerMaxReady = true
    if needsType then
        frame._msufTextPowerType = powerType
        frame._msufTextPowerToken = powerToken
        frame._msufTextPowerTypeKnown = true
        frame._msufTextPowerTypeUnit = unit
    end
    frame._msufTextPowerMax = maxPower
    frame._msufTextPowerMaxUnit = unit
    return powerType, maxPower, powerToken, powerMetaChanged, maxSecret
end

local function ReadPowerValues(frame, bar, unit, event, animate)
    local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
    if animate and bar._msufPowerMaxReady == true and bar._msufPowerMaxUnit == unit then
        powerType = bar._msufPowerType
        maxPower = bar._msufPowerMax
        powerToken = bar._msufPowerToken
        powerMetaChanged = false
        maxSecret = bar._msufPowerMaxSecret == true
    else
        local forceMeta = bar._msufPowerMaxReady ~= true
            or bar._msufPowerMaxUnit ~= unit
        if not forceMeta and not animate then
            forceMeta = event == "UNIT_MAXPOWER"
                or event == "UNIT_DISPLAYPOWER"
                or event == "UNIT_POWER_BAR_SHOW"
                or event == "UNIT_POWER_BAR_HIDE"
                or event == "MSUF_APPLY"
                or event == "MSUF_FORCE_UPDATE"
                or event == "MSUF_POWER_LAYOUT"
        end
        powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, forceMeta)
    end
    -- Value ticks only read the value. Power type/max are refreshed by the
    -- registered meta events above; probing UnitPowerType on every frequent tick
    -- costs more than the rare one-frame stale cache it prevents.
    local power
    -- powerType originates from ReadPowerType (secret-sanitised to nil), so a
    -- plain nil test avoids a redundant issecretvalue C call on every read.
    if powerType ~= nil then
        power = UnitPower(unit, powerType)
    else
        power = UnitPower(unit)
    end
    local powerSecret = issecretvalue(power) == true
    if not powerSecret and power == nil then power = 0 end
    return power, maxPower, powerType, powerToken, powerMetaChanged, powerSecret, maxSecret
end

local function EnsurePowerBackground(frame, bar, spec)
    local bg = frame and frame.powerBarBG
    if bg and bg.GetParent and bg:GetParent() == bar then
        return bg
    end
    if bg then
        bg:Hide()
    end
    bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetColorTexture(0, 0, 0, spec and spec.backgroundAlpha or 0.72)
    frame.powerBarBG = bg
    frame.powerBg = bg
    return bg
end

local function HidePowerBorder(bar)
    local edges = bar and bar.MSUFPowerBorderEdges
    if not edges then
        return
    end
    for i = 1, 4 do
        SetShownCached(edges[i], false)
    end
end

local function EnsurePowerBorder(bar)
    local edges = bar.MSUFPowerBorderEdges
    if edges then
        return edges
    end
    edges = {}
    for i = 1, 4 do
        local edge = bar:CreateTexture(nil, "OVERLAY", nil, 6)
        edge:SetColorTexture(0, 0, 0, 1)
        edges[i] = edge
    end
    bar.MSUFPowerBorderEdges = edges
    return edges
end

local function ApplyPowerBorder(bar, power)
    local thickness = floor((tonumber(power and power.borderThickness) or 0) + 0.5)
    if not (power and power.borderEnabled == true) or thickness <= 0 then
        HidePowerBorder(bar)
        return
    end
    if thickness > 10 then
        thickness = 10
    end
    local r, g, b, a = power.borderR or 0, power.borderG or 0, power.borderB or 0, power.borderA or 1
    local edges = EnsurePowerBorder(bar)
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    if bar._msufPowerBorderThickness ~= thickness then
        top:ClearAllPoints()
        top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -thickness, 0)
        top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", thickness, 0)
        top:SetHeight(thickness)

        bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -thickness, 0)
        bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", thickness, 0)
        bottom:SetHeight(thickness)

        left:ClearAllPoints()
        left:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, thickness)
        left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, -thickness)
        left:SetWidth(thickness)

        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, thickness)
        right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, -thickness)
        right:SetWidth(thickness)
        bar._msufPowerBorderThickness = thickness
    end
    if bar._msufPowerBorderR ~= r or bar._msufPowerBorderG ~= g or bar._msufPowerBorderB ~= b or bar._msufPowerBorderA ~= a then
        for i = 1, 4 do
            edges[i]:SetColorTexture(r, g, b, a)
        end
        bar._msufPowerBorderR, bar._msufPowerBorderG, bar._msufPowerBorderB, bar._msufPowerBorderA = r, g, b, a
    end
    for i = 1, 4 do
        SetShownCached(edges[i], true)
    end
end

function Power.IsEnabled(frame, spec)
    return spec and spec.power and spec.power.enabled == true
end

function Power.GetEvents(frame, spec)
    return spec and spec.power and spec.power.frequent == true and POWER_EVENTS_FREQUENT or POWER_EVENTS
end

function Power.Disable(frame)
    if frame.targetPowerBar then
        SetShownCached(frame.targetPowerBar, false)
    end
    if frame.powerBarBG then
        SetShownCached(frame.powerBarBG, false)
    end
    if HideBarGradient then
        HideBarGradient(frame.powerGradients)
    end
    HidePowerBorder(frame.targetPowerBar)
end

function Power.Create(frame, spec)
    if frame.targetPowerBar then
        return
    end
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture((spec and spec.texture) or WHITE)
    frame.targetPowerBar = bar
    frame.powerBar = bar
    frame.Power = bar
    frame.power = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetColorTexture(0, 0, 0, spec and spec.backgroundAlpha or 0.72)
    frame.powerBarBG = bg
    frame.powerBg = bg
end

function Power.Apply(frame, spec)
    if not frame.targetPowerBar then
        Power.Create(frame, spec)
    end
    local bar = frame.targetPowerBar
    frame.Power = bar
    frame.powerBar = bar
    frame.power = bar
    local bg = EnsurePowerBackground(frame, bar, spec)
    local power = spec and spec.power or {}
    local needsType = power.mode == nil or power.mode == "power"
    if frame._msufPowerBarNeedsType ~= (needsType and true or nil) then
        frame._msufPowerBarNeedsType = needsType and true or nil
        bar._msufPowerType = nil
        bar._msufPowerToken = nil
        bar._msufPowerMaxReady = nil
        bar._msufPowerMaxUnit = nil
    end
    local h = tonumber(power.height) or 3
    local layout = power.detached == true and "DETACHED" or (power.embed == false and "OUTSIDE" or "EMBED")
    local classAnchor = power.detached == true and power.detachedAnchorClass == true and _G.MSUF_ClassPowerContainer or nil
    if classAnchor and classAnchor.IsShown and not classAnchor:IsShown() then
        classAnchor = nil
    end
    local width = tonumber(power.detachedWidth) or tonumber(spec and spec.width) or frame:GetWidth()
    if power.detached == true then
        if power.detachedSyncClass == true then
            local classWidth = classAnchor and classAnchor.GetWidth and classAnchor:GetWidth() or nil
            if classWidth and classWidth < 20 then
                classWidth = nil
            end
            width = classWidth
                or ExternalFrameWidth(power.detachedClassWidthFrameName, bar)
                or tonumber(power.detachedClassWidth)
                or width
        else
            width = ExternalFrameWidth(power.detachedWidthFrameName, bar) or width
        end
    end
    width = tonumber(width) or tonumber(spec and spec.width) or frame:GetWidth()
    if width < 20 then
        width = tonumber(spec and spec.width) or 20
    end
    local detachedH = tonumber(power.detachedHeight) or h
    local detachedX = tonumber(power.detachedX) or 0
    local detachedY = tonumber(power.detachedY) or -4
    local detachedLevel = tonumber(power.detachedLevel) or 6
    local frameLevel = frame.GetFrameLevel and (frame:GetFrameLevel() or 1) or 1
    local targetLevel = frameLevel + detachedLevel
    local layoutChanged = bar._msufPowerLayout ~= layout
        or bar._msufPowerHeight ~= h
        or bar._msufPowerWidth ~= width
        or bar._msufPowerDetachedHeight ~= detachedH
        or bar._msufPowerDetachedX ~= detachedX
        or bar._msufPowerDetachedY ~= detachedY
        or bar._msufPowerDetachedLevel ~= detachedLevel
        or bar._msufPowerFrameLevel ~= frameLevel
        or bar._msufPowerAnchorFrame ~= classAnchor
    if layoutChanged then
        bar:ClearAllPoints()
        bg:ClearAllPoints()
    end
    if power.detached == true then
        frame._msufPowerBarDetached = true
        if layoutChanged then
            if classAnchor then
                bar:SetPoint("TOP", classAnchor, "BOTTOM", detachedX, detachedY)
            else
                bar:SetPoint("TOP", frame, "BOTTOM", detachedX, detachedY)
            end
            bar:SetSize(width, detachedH)
            SetFrameLevelCached(bar, targetLevel)
        end
    elseif power.embed == false then
        frame._msufPowerBarDetached = nil
        if layoutChanged then
            bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -1)
            bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -1)
            bar:SetHeight(h)
            SetFrameLevelCached(bar, frameLevel + 1)
        end
    else
        frame._msufPowerBarDetached = nil
        if layoutChanged then
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            bar:SetHeight(h)
            SetFrameLevelCached(bar, frameLevel + 1)
        end
    end
    if layoutChanged then
        bg:SetAllPoints(bar)
        bar._msufPowerLayout = layout
        bar._msufPowerHeight = h
        bar._msufPowerWidth = width
        bar._msufPowerDetachedHeight = detachedH
        bar._msufPowerDetachedX = detachedX
        bar._msufPowerDetachedY = detachedY
        bar._msufPowerDetachedLevel = detachedLevel
        bar._msufPowerFrameLevel = frameLevel
        bar._msufPowerAnchorFrame = classAnchor
    end
    if bar.SetReverseFill then
        local reverse = power.reverse == true
        if bar._msufReverseFill ~= reverse then
            bar:SetReverseFill(reverse)
            bar._msufReverseFill = reverse
        end
    end
    SetBarSmoothing(bar, power.smooth == true)
    SetStatusTexture(bar, power.texture or WHITE)
    ApplyStatusColor(bar, PowerColor(frame, frame.unit))
    ApplyBackgrounds(frame)
    if ApplyBarGradient then
        ApplyBarGradient(frame, bar, power.barGradient, "powerGradients")
    end
    frame._msufUpdatePowerValue = frame.unit == "player" and Power.UpdateValuePlain or Power.UpdateValue
    if power.enabled == true then
        SetShownCached(bar, true)
        SetShownCached(bg, true)
        ApplyPowerBorder(bar, power)
    else
        SetShownCached(bar, false)
        SetShownCached(bg, false)
        HidePowerBorder(bar)
    end
end

function Power.UpdateValuePlain(frame, event, unit)
    unit = unit or frame.unit
    if unit ~= "player" then
        return Power.UpdateValue(frame, event, unit)
    end
    local bar = frame.targetPowerBar
    if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
        return
    end

    local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
    if bar._msufPowerMaxReady == true and bar._msufPowerMaxUnit == unit then
        powerType = bar._msufPowerType
        maxPower = bar._msufPowerMax
        powerToken = bar._msufPowerToken
        maxSecret = bar._msufPowerMaxSecret == true
        powerMetaChanged = false
    else
        powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, true)
    end

    local power
    if powerType ~= nil then
        power = UnitPower(unit, powerType)
    else
        power = UnitPower(unit)
    end
    power = power or 0

    if powerMetaChanged or bar._msufMinMaxInit ~= true then
        SetBarMinMaxPlain(bar, maxPower)
        bar._msufMinMaxInit = true
    end
    SetBarValuePlain(bar, power, true)

    if bar._msufStatusR == nil or powerMetaChanged then
        ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
    end
    return power, maxPower
end

function Power.UpdateValue(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.targetPowerBar
    if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
        return
    end

    local powerType, maxPower, powerToken, powerMetaChanged, maxSecret
    if bar._msufPowerMaxReady == true and bar._msufPowerMaxUnit == unit then
        powerType = bar._msufPowerType
        maxPower = bar._msufPowerMax
        powerToken = bar._msufPowerToken
        maxSecret = bar._msufPowerMaxSecret == true
        powerMetaChanged = false
    else
        powerType, maxPower, powerToken, powerMetaChanged, maxSecret = ReadPowerMeta(frame, bar, unit, true)
    end

    local power
    if powerType ~= nil then
        power = UnitPower(unit, powerType)
    else
        power = UnitPower(unit)
    end
    local powerSecret = issecretvalue(power) == true
    if not powerSecret and power == nil then power = 0 end

    if powerMetaChanged or bar._msufMinMaxInit ~= true then
        SetBarMinMaxKnown(bar, maxPower, maxSecret)
        bar._msufMinMaxInit = true
    end
    SetBarValueKnown(bar, power, powerSecret, true)

    if bar._msufStatusR == nil or powerMetaChanged then
        ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
    end
    return power, maxPower
end

function Power.Update(frame, event, unit)
    unit = unit or frame.unit
    local bar = frame.targetPowerBar
    if not bar or bar._msufShown == false or (bar._msufShown == nil and bar.IsShown and not bar:IsShown()) then
        return
    end

    local animate = event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
    local power, maxPower, powerType, powerToken, powerMetaChanged, powerSecret, maxSecret = ReadPowerValues(frame, bar, unit, event, animate)

    -- Max power only changes on UNIT_MAXPOWER / UNIT_DISPLAYPOWER (and forced
    -- applies); skip the SetMinMaxValues C call on the frequent value ticks.
    -- Gated on the plain event string -- the (possibly secret) max is never
    -- compared.
    if not animate or powerMetaChanged or bar._msufMinMaxInit ~= true then
        SetBarMinMaxKnown(bar, maxPower, maxSecret)
        bar._msufMinMaxInit = true
    end
    SetBarValueKnown(bar, power, powerSecret, animate)
    if not animate then
        SnapBarInterpolation(bar)
    end

    if bar._msufStatusR == nil
        or powerMetaChanged
        or (not animate and (event == "UNIT_DISPLAYPOWER" or event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" or event == "MSUF_POWER_LAYOUT")) then
        ApplyStatusColor(bar, PowerColor(frame, unit, powerType, powerToken, true))
    end
    return power, maxPower
end

UF.RegisterElement("Power", Power)
