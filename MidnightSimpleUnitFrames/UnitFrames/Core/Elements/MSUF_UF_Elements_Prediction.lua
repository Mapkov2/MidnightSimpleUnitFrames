local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetIncomingHeals = _G.UnitGetIncomingHeals
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction = _G.UnitGetDetailedHealPrediction
local tonumber = tonumber
local type = type
local issecretvalue = _G.issecretvalue
local Enum = _G.Enum

local WHITE = "Interface\\Buttons\\WHITE8x8"
local UnitIncomingHealClampMode = Enum and Enum.UnitIncomingHealClampMode
local UnitDamageAbsorbClampMode = Enum and Enum.UnitDamageAbsorbClampMode
local UnitHealAbsorbClampMode = Enum and Enum.UnitHealAbsorbClampMode
local UnitHealAbsorbMode = Enum and Enum.UnitHealAbsorbMode
local INCOMING_MISSING = UnitIncomingHealClampMode and UnitIncomingHealClampMode.MissingHealth or 0
local INCOMING_MAX = UnitIncomingHealClampMode and UnitIncomingHealClampMode.MaximumHealth or 1
local ABSORB_MISSING = UnitDamageAbsorbClampMode and UnitDamageAbsorbClampMode.MissingHealthWithoutIncomingHeals or 1
local ABSORB_MAX = UnitDamageAbsorbClampMode and UnitDamageAbsorbClampMode.MaximumHealth or 2
local HEAL_ABSORB_CURRENT = UnitHealAbsorbClampMode and UnitHealAbsorbClampMode.CurrentHealth or 0
local HEAL_ABSORB_TOTAL = UnitHealAbsorbMode and UnitHealAbsorbMode.Total or 1
local TEST_MAX = 100
local TEST_INCOMING = 20
local TEST_ABSORB = 25
local TEST_HEAL_ABSORB = 15
local EMPTY_EVENTS = {}
local DERIVED_PREDICTION_UNITS = {
    targettarget = true,
    focustarget = true,
}
local PREDICTION_EVENTS = {
    [1] = { "UNIT_HEAL_PREDICTION", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [2] = { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [3] = { "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [4] = { "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [5] = { "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [6] = { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [7] = { "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
}
local PREDICTION_HEALTH_EVENTS = {
    [1] = { "UNIT_HEALTH", "UNIT_HEAL_PREDICTION", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [2] = { "UNIT_HEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [3] = { "UNIT_HEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [4] = { "UNIT_HEALTH", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [5] = { "UNIT_HEALTH", "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [6] = { "UNIT_HEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
    [7] = { "UNIT_HEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH", "UNIT_CONNECTION" },
}

local calcUnsupported

local function SetShownCached(obj, show)
    if obj and obj._msufShown ~= show then
        obj:SetShown(show)
        obj._msufShown = show
    end
end

local function SetTextureCached(bar, texture)
    texture = texture or WHITE
    if bar and (bar._msufTexture ~= texture or bar.MSUF_cachedStatusbarTexture ~= texture) then
        bar:SetStatusBarTexture(texture)
        bar._msufTexture = texture
        bar.MSUF_cachedStatusbarTexture = texture
    end
end

local function SetColorCached(bar, r, g, b, a)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if bar and (bar._msufR ~= r or bar._msufG ~= g or bar._msufB ~= b or bar._msufA ~= a) then
        bar:SetStatusBarColor(r, g, b, a)
        bar._msufR, bar._msufG, bar._msufB, bar._msufA = r, g, b, a
    end
end

local function NormalizeAnchorMode(mode, fallback)
    mode = tonumber(mode) or fallback or 2
    if mode < 1 or mode > 5 then
        return fallback or 2
    end
    return mode
end

local function AnchorModeReverse(mode, hpReverse)
    if mode == 1 then
        return false
    elseif mode == 5 then
        return hpReverse ~= true
    end
    return true
end

local function FollowModeReverse(hpReverse)
    return hpReverse == true
end

local function ReverseForMode(mode, hpReverse)
    if mode == 3 or mode == 4 then
        return FollowModeReverse(hpReverse)
    end
    return AnchorModeReverse(mode, hpReverse)
end

local function ClampModeForAnchor(mode)
    if mode == 4 or mode == 1 or mode == 2 or mode == 5 then
        return ABSORB_MAX
    end
    return ABSORB_MISSING
end

local function IncomingClampModeForAnchor(mode)
    if mode == 1 or mode == 2 or mode == 4 or mode == 5 then
        return INCOMING_MAX
    end
    return INCOMING_MISSING
end

local function CacheableValue(value)
    return not (issecretvalue and issecretvalue(value))
end

local function SetMinMaxCached(bar, maxValue)
    if not bar or type(maxValue) == "nil" then
        return false
    end
    local cacheable = CacheableValue(maxValue)
    if cacheable and bar._msufMax == maxValue then
        return false
    end
    bar:SetMinMaxValues(0, maxValue)
    bar._msufMax = cacheable and maxValue or nil
    return true
end

local function SetValueCached(bar, value)
    if not bar or type(value) == "nil" then
        return
    end
    local cacheable = CacheableValue(value)
    if cacheable and bar._msufValue == value then
        return
    end
    bar:SetValue(value)
    bar._msufValue = cacheable and value or nil
end

local function HideBar(bar)
    if not bar then
        return
    end
    if SetMinMaxCached(bar, 1) then
        bar._msufValue = nil
    end
    SetValueCached(bar, 0)
    SetShownCached(bar, false)
end

local function IsPositiveOverlayAmount(value)
    local valueType = type(value)
    if valueType == "nil" then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return true
    end
    if valueType == "number" then
        return value > 0
    end
    return (tonumber(value) or 0) > 0
end

local function ShowValue(bar, maxValue, value)
    if not IsPositiveOverlayAmount(value) then
        HideBar(bar)
        return
    end
    if type(maxValue) == "nil" then
        maxValue = 1
    end
    if SetMinMaxCached(bar, maxValue) then
        bar._msufValue = nil
    end
    SetValueCached(bar, value)
    SetShownCached(bar, true)
end

local function CanShareHealthCalc(frame)
    return not (frame and frame.MSUFSpec and frame.MSUFSpec.scope == "group")
end

local function EnsureCalc(frame)
    if calcUnsupported then
        return nil
    end
    local shareHealthCalc = CanShareHealthCalc(frame)
    local calc = frame._msufPredictionCalc or (shareHealthCalc and frame._msufHealthCalc) or nil
    if calc then
        frame._msufPredictionCalc = calc
        if shareHealthCalc and not frame._msufHealthCalc then
            frame._msufHealthCalc = calc
        end
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
    frame._msufPredictionCalc = calc
    if shareHealthCalc then
        frame._msufHealthCalc = calc
    end
    return calc
end

local function ConfigureCalc(calc, cfg)
    if not calc then
        return
    end
    local healMode = NormalizeAnchorMode(cfg and cfg.healAnchorMode, 3)
    local absorbMode = NormalizeAnchorMode(cfg and cfg.absorbAnchorMode, 2)
    local incomingClamp = IncomingClampModeForAnchor(healMode)
    local damageClamp = ClampModeForAnchor(absorbMode)

    if calc.SetIncomingHealClampMode and calc._msufIncomingClamp ~= incomingClamp then
        calc:SetIncomingHealClampMode(incomingClamp)
        calc._msufIncomingClamp = incomingClamp
    end
    if calc.SetDamageAbsorbClampMode and calc._msufDamageClamp ~= damageClamp then
        calc:SetDamageAbsorbClampMode(damageClamp)
        calc._msufDamageClamp = damageClamp
    end
    if calc.SetHealAbsorbClampMode and calc._msufHealAbsorbClamp ~= HEAL_ABSORB_CURRENT then
        calc:SetHealAbsorbClampMode(HEAL_ABSORB_CURRENT)
        calc._msufHealAbsorbClamp = HEAL_ABSORB_CURRENT
    end
    if calc.SetHealAbsorbMode and calc._msufHealAbsorbMode ~= HEAL_ABSORB_TOTAL then
        calc:SetHealAbsorbMode(HEAL_ABSORB_TOTAL)
        calc._msufHealAbsorbMode = HEAL_ABSORB_TOTAL
    end
end

local function CalcIncomingHeals(calc, unit)
    if calc and calc.GetIncomingHeals then
        local value = calc:GetIncomingHeals()
        if type(value) ~= "nil" then
            return value
        end
    end
    if calc and calc.GetTotalIncomingHeals then
        local value = calc:GetTotalIncomingHeals()
        if type(value) ~= "nil" then
            return value
        end
    end
    return UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or nil
end

local function CalcDamageAbsorbs(calc, unit)
    if calc then
        if calc.GetDamageAbsorbs then
            local value = calc:GetDamageAbsorbs()
            if type(value) ~= "nil" then return value end
        end
        if calc.GetTotalDamageAbsorbs then
            local value = calc:GetTotalDamageAbsorbs()
            if type(value) ~= "nil" then return value end
        end
    end
    return UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit) or nil
end

local function CalcHealAbsorbs(calc, unit)
    if calc then
        if calc.GetHealAbsorbs then
            local value = calc:GetHealAbsorbs()
            if type(value) ~= "nil" then return value end
        end
        if calc.GetTotalHealAbsorbs then
            local value = calc:GetTotalHealAbsorbs()
            if type(value) ~= "nil" then return value end
        end
    end
    return UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit) or nil
end

local function ClampIncomingToMissing(value, hp, maxHP)
    if type(value) ~= "number" or type(hp) ~= "number" or type(maxHP) ~= "number" then
        return value
    end
    local missing = maxHP - hp
    if missing <= 0 then
        return 0
    end
    if value > missing then
        return missing
    end
    return value
end

local function ResolveTexture(key, fallback)
    if type(key) == "string" and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            return resolve(key) or fallback
        end
        return key
    end
    return fallback
end

local function EnsureBar(frame, key, levelOffset)
    local bar = frame[key]
    local hpBar = frame.hpBar or frame.Health
    if bar then
        return bar
    end
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(WHITE)
    bar:SetAllPoints(hpBar or frame)
    if bar.SetFrameLevel and hpBar and hpBar.GetFrameLevel then
        local level = (hpBar:GetFrameLevel() or frame:GetFrameLevel() or 1) + levelOffset
        bar:SetFrameLevel(level)
        bar._msufFrameLevel = level
    end
    bar:Hide()
    frame[key] = bar
    return bar
end

local function SyncBarLayer(frame, hpBar, bar, levelOffset)
    if not (frame and hpBar and bar) then
        return
    end
    if bar.SetFrameStrata and frame.GetFrameStrata then
        local strata = frame:GetFrameStrata()
        if strata and bar._msufFrameStrata ~= strata then
            bar:SetFrameStrata(strata)
            bar._msufFrameStrata = strata
        end
    end
    if bar.SetFrameLevel and hpBar.GetFrameLevel then
        local level = (hpBar:GetFrameLevel() or frame:GetFrameLevel() or 1) + levelOffset
        if bar._msufFrameLevel ~= level then
            bar:SetFrameLevel(level)
            bar._msufFrameLevel = level
        end
    end
end

local function StatusTexture(bar)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
end

local function VisibleFollowBar(cfg, bar)
    return cfg and cfg.heal == true and bar and bar._msufShown == true and bar or nil
end

local function SetParentCached(bar, parent)
    if not (bar and parent and bar.GetParent) then
        return false
    end
    if bar:GetParent() == parent then
        return false
    end
    bar:SetParent(parent)
    return true
end

local function LayoutBar(frame, bar, levelOffset, mode, reverse, followBar)
    local hpBar = frame.hpBar or frame.Health
    if not (bar and hpBar) then
        return
    end
    mode = NormalizeAnchorMode(mode, 2)
    SyncBarLayer(frame, hpBar, bar, levelOffset)
    local follow = (mode == 3 or mode == 4) and (StatusTexture(followBar) or StatusTexture(hpBar)) or nil
    local width = (hpBar.GetWidth and hpBar:GetWidth()) or tonumber(frame.MSUFSpec and frame.MSUFSpec.width) or 1
    if not width or width <= 0 then
        width = tonumber(frame.MSUFSpec and frame.MSUFSpec.width) or 1
    end
    local anchorTarget = follow or hpBar
    local parent = (mode == 4) and frame or hpBar
    local parentChanged = SetParentCached(bar, parent)
    if hpBar.SetClipsChildren and mode == 3 and hpBar._msufPredictionClipsChildren ~= true then
        hpBar:SetClipsChildren(true)
        hpBar._msufPredictionClipsChildren = true
    end
    if bar._msufPredictionMode ~= mode
        or bar._msufPredictionReverse ~= reverse
        or bar._msufPredictionAnchorTarget ~= anchorTarget
        or bar._msufPredictionWidth ~= width
        or bar._msufPredictionParent ~= parent
        or parentChanged then
        bar:ClearAllPoints()
        if follow then
            bar:SetWidth(width)
            if reverse then
                bar:SetPoint("TOPRIGHT", follow, "TOPLEFT", 0, 0)
                bar:SetPoint("BOTTOMRIGHT", follow, "BOTTOMLEFT", 0, 0)
            else
                bar:SetPoint("TOPLEFT", follow, "TOPRIGHT", 0, 0)
                bar:SetPoint("BOTTOMLEFT", follow, "BOTTOMRIGHT", 0, 0)
            end
        else
            bar:SetAllPoints(hpBar)
        end
        bar._msufPredictionMode = mode
        bar._msufPredictionReverse = reverse
        bar._msufPredictionAnchorTarget = anchorTarget
        bar._msufPredictionWidth = width
        bar._msufPredictionParent = parent
    end
    if bar.SetReverseFill and bar._msufReverseFill ~= reverse then
        bar:SetReverseFill(reverse)
        bar._msufReverseFill = reverse
    end
end

local function NeedsHealthEvent(cfg)
    if not cfg then
        return false
    end
    if cfg.healAbsorb == true then
        return true
    end
    if cfg.heal == true and NormalizeAnchorMode(cfg.healAnchorMode, 3) == 3 then
        return true
    end
    return cfg.absorb == true and NormalizeAnchorMode(cfg.absorbAnchorMode, 2) == 3
end

local Prediction = {}

function Prediction.IsEnabled(frame, spec)
    return spec and spec.prediction and spec.prediction.enabled == true
end

local function PredictionEventsForConfig(cfg, healthAware)
    if not (cfg and cfg.enabled == true) then
        return EMPTY_EVENTS
    end
    if cfg.test == true then
        return EMPTY_EVENTS
    end
    local mask = (cfg.heal == true and 1 or 0)
        + (cfg.absorb == true and 2 or 0)
        + (cfg.healAbsorb == true and 4 or 0)
    local eventTable = healthAware ~= false and NeedsHealthEvent(cfg) and PREDICTION_HEALTH_EVENTS or PREDICTION_EVENTS
    return eventTable[mask] or EMPTY_EVENTS
end

function Prediction.GetEvents(frame, spec)
    return PredictionEventsForConfig(spec and spec.prediction, true)
end

function Prediction.GetUnitlessEvents(frame, spec)
    if not (frame and DERIVED_PREDICTION_UNITS[frame.unit] == true) then
        return EMPTY_EVENTS
    end
    return PredictionEventsForConfig(spec and spec.prediction, false)
end

function Prediction.Create(frame, spec)
    local cfg = spec and spec.prediction or {}
    if cfg.heal == true then
        frame.incomingHealBar = EnsureBar(frame, "incomingHealBar", 1)
        frame.healPredictionBar = frame.incomingHealBar
    end
    if cfg.absorb == true then
        frame.absorbBar = EnsureBar(frame, "absorbBar", 2)
    end
    if cfg.healAbsorb == true then
        frame.healAbsorbBar = EnsureBar(frame, "healAbsorbBar", 3)
    end
end

function Prediction.Apply(frame, spec)
    local cfg = spec and spec.prediction or {}
    Prediction.Create(frame, spec)
    ConfigureCalc(EnsureCalc(frame), cfg)
    local hpReverse = spec and spec.health and spec.health.reverse == true
    local healMode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
    local absorbMode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)

    if frame.incomingHealBar then
        LayoutBar(frame, frame.incomingHealBar, 1, healMode, ReverseForMode(healMode, hpReverse))
        SetTextureCached(frame.incomingHealBar, ResolveTexture(cfg.texture, spec and spec.texture or WHITE))
        SetColorCached(frame.incomingHealBar, cfg.healR, cfg.healG, cfg.healB, cfg.healA)
        if cfg.heal ~= true then HideBar(frame.incomingHealBar) end
    end
    if frame.absorbBar then
        local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
        LayoutBar(frame, frame.absorbBar, 2, absorbMode, ReverseForMode(absorbMode, hpReverse), follow)
        SetTextureCached(frame.absorbBar, ResolveTexture(cfg.absorbTexture, spec and spec.texture or WHITE))
        SetColorCached(frame.absorbBar, cfg.absorbR, cfg.absorbG, cfg.absorbB, cfg.absorbA)
        if cfg.absorb ~= true then HideBar(frame.absorbBar) end
    end
    if frame.healAbsorbBar then
        local healAbsorbReverse = not hpReverse
        LayoutBar(frame, frame.healAbsorbBar, 3, 5, healAbsorbReverse)
        SetTextureCached(frame.healAbsorbBar, ResolveTexture(cfg.healAbsorbTexture, spec and spec.texture or WHITE))
        SetColorCached(frame.healAbsorbBar, cfg.healAbsorbR, cfg.healAbsorbG, cfg.healAbsorbB, cfg.healAbsorbA)
        if cfg.healAbsorb ~= true then HideBar(frame.healAbsorbBar) end
    end
end

function Prediction.Disable(frame)
    HideBar(frame and frame.incomingHealBar)
    HideBar(frame and frame.absorbBar)
    HideBar(frame and frame.healAbsorbBar)
end

function Prediction.Update(frame, event, unit, seedHP, seedMaxHP, seedCalc)
    if unit and frame and unit ~= frame.unit then
        unit = frame.unit
        seedHP, seedMaxHP, seedCalc = nil, nil, nil
    else
        unit = unit or frame.unit
    end
    local cfg = frame.MSUFSpec and frame.MSUFSpec.prediction
    if not (cfg and cfg.enabled == true) then
        Prediction.Disable(frame)
        return
    end

    local exists = UnitExists and UnitExists(unit)
    if not exists then
        Prediction.Disable(frame)
        return
    end

    local hpReverse = frame.MSUFSpec and frame.MSUFSpec.health and frame.MSUFSpec.health.reverse == true
    if cfg.test == true then
        if cfg.heal == true and frame.incomingHealBar then
            local mode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
            LayoutBar(frame, frame.incomingHealBar, 1, mode, ReverseForMode(mode, hpReverse))
            ShowValue(frame.incomingHealBar, TEST_MAX, TEST_INCOMING)
        elseif frame.incomingHealBar then
            HideBar(frame.incomingHealBar)
        end
        if cfg.absorb == true and frame.absorbBar then
            local mode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
            local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
            LayoutBar(frame, frame.absorbBar, 2, mode, ReverseForMode(mode, hpReverse), follow)
            ShowValue(frame.absorbBar, TEST_MAX, TEST_ABSORB)
        elseif frame.absorbBar then
            HideBar(frame.absorbBar)
        end
        if cfg.healAbsorb == true and frame.healAbsorbBar then
            ShowValue(frame.healAbsorbBar, TEST_MAX, TEST_HEAL_ABSORB)
        elseif frame.healAbsorbBar then
            HideBar(frame.healAbsorbBar)
        end
        return
    end

    local calc = EnsureCalc(frame)
    ConfigureCalc(calc, cfg)
    local hp, maxHP
    local canUseSeed = calc and seedCalc == calc and type(seedHP) ~= "nil" and type(seedMaxHP) ~= "nil"
    if canUseSeed then
        hp, maxHP = seedHP, seedMaxHP
    elseif calc and UnitGetDetailedHealPrediction then
        UnitGetDetailedHealPrediction(unit, "player", calc)
        hp = calc.GetCurrentHealth and calc:GetCurrentHealth() or nil
        maxHP = calc.GetMaximumHealth and calc:GetMaximumHealth() or nil
    end
    if type(hp) == "nil" and UnitHealth then hp = UnitHealth(unit) end
    if type(maxHP) == "nil" and UnitHealthMax then maxHP = UnitHealthMax(unit) end
    if cfg.heal == true and frame.incomingHealBar then
        local mode = NormalizeAnchorMode(cfg.healAnchorMode, 3)
        local incoming = CalcIncomingHeals(calc, unit)
        if not calc and mode == 3 then
            incoming = ClampIncomingToMissing(incoming, hp, maxHP)
        end
        ShowValue(frame.incomingHealBar, maxHP, incoming)
    elseif frame.incomingHealBar then
        HideBar(frame.incomingHealBar)
    end

    if cfg.absorb == true and frame.absorbBar then
        local mode = NormalizeAnchorMode(cfg.absorbAnchorMode, 2)
        local follow = VisibleFollowBar(cfg, frame.incomingHealBar)
        LayoutBar(frame, frame.absorbBar, 2, mode, ReverseForMode(mode, hpReverse), follow)
        ShowValue(frame.absorbBar, maxHP, CalcDamageAbsorbs(calc, unit))
    elseif frame.absorbBar then
        HideBar(frame.absorbBar)
    end

    if cfg.healAbsorb == true and frame.healAbsorbBar then
        ShowValue(frame.healAbsorbBar, maxHP, CalcHealAbsorbs(calc, unit))
    elseif frame.healAbsorbBar then
        HideBar(frame.healAbsorbBar)
    end
end

UF.RegisterElement("Prediction", Prediction)
