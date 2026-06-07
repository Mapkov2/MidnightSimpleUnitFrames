local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
local CreateFrame = CreateFrame
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent = _G.UnitHealthPercent
local UnitPowerPercent = _G.UnitPowerPercent
local AbbreviateNumbers = _G.AbbreviateNumbers
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers
local AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers or _G.ShortenNumber
local InCombatLockdown = _G.InCombatLockdown
local UnitName = UnitName
local UnitIsPlayer = UnitIsPlayer
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitReaction = UnitReaction
local UnitSelectionColor = UnitSelectionColor
local GetUnitClassification = GetUnitClassification
local PowerBarColor = PowerBarColor
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local type = type
local tonumber = tonumber
local format = string.format
local byte, sub = string.byte, string.sub
local abs, floor, max = math.abs, math.floor, math.max
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local StatusBarInterpolation = _G.Enum and _G.Enum.StatusBarInterpolation
local SMOOTH_INTERP = StatusBarInterpolation and StatusBarInterpolation.ExponentialEaseOut or nil
local C_CurveUtil = _G.C_CurveUtil
local CreateColor = _G.CreateColor
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local SCALE_100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local REVERSE_HEALTH_MODE = {
    CURPERCENT = "PERCENTCUR",
    PERCENTCUR = "CURPERCENT",
    CURMAX = "MAXCUR",
    MAXCUR = "CURMAX",
    CURMAXPERCENT = "PERCENTMAXCUR",
    PERCENTMAXCUR = "CURMAXPERCENT",
    MAXPERCENT = "PERCENTMAX",
    PERCENTMAX = "MAXPERCENT",
    PERCENTCURMAX = "CURMAXPERCENT",
}
local EMPTY_EVENTS = {}
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UNIT_CONNECTION" }
local POWER_EVENTS_FREQUENT = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UNIT_CONNECTION" }
local TEXT_EVENT_SETS = {
    [0] = EMPTY_EVENTS,
    [1] = { "UNIT_NAME_UPDATE" },
    [2] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED" },
    [3] = { "UNIT_NAME_UPDATE", "UNIT_TARGET" },
    [4] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_TARGET" },
}
local TEXT_EVENT_SETS_ABSORB = {
    [0] = { "UNIT_ABSORB_AMOUNT_CHANGED" },
    [1] = { "UNIT_NAME_UPDATE", "UNIT_ABSORB_AMOUNT_CHANGED" },
    [2] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_ABSORB_AMOUNT_CHANGED" },
    [3] = { "UNIT_NAME_UPDATE", "UNIT_TARGET", "UNIT_ABSORB_AMOUNT_CHANGED" },
    [4] = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_TARGET", "UNIT_ABSORB_AMOUNT_CHANGED" },
}

local function ClampFrameLayer(layer, fallback)
    layer = floor((tonumber(layer) or fallback or 5) + 0.5)
    if layer < 0 then
        return 0
    elseif layer > 30 then
        return 30
    end
    return layer
end

local function DrawSubLayer(layer, fallback)
    layer = ClampFrameLayer(layer, fallback)
    if layer > 7 then
        return 7
    end
    return layer
end

local function GetLayerBaseLevel(frame)
    local base = frame and (frame.Health or frame.hpBar or frame)
    return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function SetStatusTexture(bar, texture)
    if bar and texture and bar.MSUFTexture ~= texture then
        bar:SetStatusBarTexture(texture)
        bar.MSUFTexture = texture
    end
end

local function ApplyStatusColor(bar, r, g, b, a)
    if bar then
        r, g, b, a = r or 1, g or 1, b or 1, a or 1
        if bar._msufStatusR ~= r or bar._msufStatusG ~= g or bar._msufStatusB ~= b or bar._msufStatusA ~= a then
            bar:SetStatusBarColor(r, g, b, a)
            bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = r, g, b, a
        end
    end
end

local function SetBarMinMax(bar, maxValue, directValue)
    if directValue then
        bar:SetMinMaxValues(0, maxValue)
        bar._msufMaxValue = nil
        return true
    elseif bar._msufMaxValue ~= maxValue then
        bar:SetMinMaxValues(0, maxValue)
        bar._msufMaxValue = maxValue
        return true
    end
    return false
end

local function SetBarValue(bar, value, directValue, animate)
    local interp = animate and bar._msufSmoothInterp or nil
    if directValue then
        if interp then
            bar:SetValue(value, interp)
            bar._msufInterpolating = true
        else
            bar:SetValue(value)
        end
        bar._msufValue = nil
        return true
    end
    value = tonumber(value) or 0
    if bar._msufValue ~= value then
        if interp then
            bar:SetValue(value, interp)
            bar._msufInterpolating = true
        else
            bar:SetValue(value)
        end
        bar._msufValue = value
        return true
    end
    return false
end

local function SnapBarInterpolation(bar)
    if not (bar and bar._msufInterpolating == true) then
        return false
    end
    if bar.SetToTargetValue then
        bar:SetToTargetValue()
    end
    bar._msufInterpolating = nil
    return true
end

local function SetBarSmoothing(bar, enabled)
    if not bar then
        return
    end
    local interp = enabled == true and SMOOTH_INTERP or nil
    if bar._msufSmoothInterp ~= interp then
        SnapBarInterpolation(bar)
        bar._msufSmoothInterp = interp
    end
end

local function ApplyTextureColor(region, texture, r, g, b, a)
    if not region then
        return
    end
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    if texture then
        if region._msufBgTexture ~= texture or region._msufBgColorTexture == true then
            region:SetTexture(texture)
            region._msufBgTexture = texture
            region._msufBgColorTexture = nil
        end
        if region._msufBgR ~= r or region._msufBgG ~= g or region._msufBgB ~= b or region._msufBgA ~= a then
            region:SetVertexColor(r, g, b, a)
            region._msufBgR, region._msufBgG, region._msufBgB, region._msufBgA = r, g, b, a
        end
    elseif region._msufBgColorTexture ~= true or region._msufBgR ~= r or region._msufBgG ~= g or region._msufBgB ~= b or region._msufBgA ~= a then
        region:SetColorTexture(r, g, b, a)
        region._msufBgColorTexture = true
        region._msufBgTexture = nil
        region._msufBgR, region._msufBgG, region._msufBgB, region._msufBgA = r, g, b, a
    end
end

local function SetShownCached(obj, show)
    if obj and obj._msufShown ~= show then
        obj:SetShown(show)
        obj._msufShown = show
    end
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback or 1
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local GRADIENT_DIRS = { "left", "right", "up", "down" }

local function GradientActive(spec)
    if not (spec and spec.enabled == true) then
        return false
    end
    if (tonumber(spec.strength) or 0) <= 0 then
        return false
    end
    return spec.left == true or spec.right == true or spec.up == true or spec.down == true
end

local function HideBarGradient(grads)
    if type(grads) ~= "table" then
        return
    end
    for i = 1, #GRADIENT_DIRS do
        SetShownCached(grads[GRADIENT_DIRS[i]], false)
    end
end

local function GradientTarget(bar)
    if bar and bar.GetStatusBarTexture then
        local fill = bar:GetStatusBarTexture()
        if fill then
            return fill
        end
    end
    return bar
end

local function AnchorGradientTexture(tex, target)
    if not (tex and target) or tex._msufGradientTarget == target then
        return
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    tex._msufGradientTarget = target
end

local function ConfigureGradientTexture(tex, direction, alpha)
    if not tex then
        return
    end
    alpha = Clamp01(alpha, 0.45)
    local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
    local minA, maxA
    if direction == "left" or direction == "down" then
        minA, maxA = alpha, 0
    else
        minA, maxA = 0, alpha
    end
    if tex._msufGradientDirection == direction
        and tex._msufGradientAlpha == alpha
        and tex._msufGradientReady == true then
        return
    end
    tex:SetTexture(WHITE)
    if tex.SetBlendMode then
        tex:SetBlendMode("BLEND")
    end
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(0, 0, 0, minA), CreateColor(0, 0, 0, maxA))
        if ok then
            tex._msufGradientReady = true
            tex._msufGradientDirection = direction
            tex._msufGradientAlpha = alpha
            return
        end
    end
    if tex.SetGradientAlpha then
        local ok = pcall(tex.SetGradientAlpha, tex, orientation, 0, 0, 0, minA, 0, 0, 0, maxA)
        if ok then
            tex._msufGradientReady = true
            tex._msufGradientDirection = direction
            tex._msufGradientAlpha = alpha
            return
        end
    end
    tex:SetColorTexture(0, 0, 0, alpha)
    tex._msufGradientReady = true
    tex._msufGradientDirection = direction
    tex._msufGradientAlpha = alpha
end

local function EnsureGradientTexture(bar, grads, direction)
    local tex = grads and grads[direction]
    if tex then
        return tex
    end
    if not (bar and bar.CreateTexture) then
        return nil
    end
    tex = bar:CreateTexture(nil, "OVERLAY", nil, 0)
    tex:SetTexture(WHITE)
    tex:SetBlendMode("BLEND")
    grads[direction] = tex
    return tex
end

local function ApplyBarGradient(frame, bar, spec, storeKey)
    if not (frame and bar) then
        return nil
    end
    local grads = frame[storeKey]
    if not grads then
        grads = {}
        frame[storeKey] = grads
    end
    if frame._msufIsGroupFrame == true then
        bar._msufGFGrads = grads
    end
    if not GradientActive(spec) then
        HideBarGradient(grads)
        return grads
    end
    local target = GradientTarget(bar)
    local alpha = Clamp01(spec.strength, 0.45)
    for i = 1, #GRADIENT_DIRS do
        local direction = GRADIENT_DIRS[i]
        local tex = grads[direction]
        if spec[direction] == true then
            tex = EnsureGradientTexture(bar, grads, direction)
            AnchorGradientTexture(tex, target)
            ConfigureGradientTexture(tex, direction, alpha)
            SetShownCached(tex, true)
        else
            SetShownCached(tex, false)
        end
    end
    return grads
end

local BAR_GRADIENT_ELEMENTS = { "Health", "Power" }

local function UpdateAllBarGradients(unit)
    local refreshed = false
    if UF and type(UF.RefreshElements) == "function" then
        refreshed = UF.RefreshElements(unit, BAR_GRADIENT_ELEMENTS, "MSUF2_GRADIENT") or refreshed
    end
    local GF = MSUF and MSUF.GF
    if GF and type(GF.RefreshVisuals) == "function" then
        refreshed = GF.RefreshVisuals(nil, GF.DIRTY_VISUAL) or refreshed
    end
    if _G.MSUF_RoundedUF_Active == true and type(_G.MSUF_RoundedUF_OnApplyAll) == "function" then
        _G.MSUF_RoundedUF_OnApplyAll()
    end
    return refreshed
end

_G.MSUF_UpdateAllBarGradients = _G.MSUF_UpdateAllBarGradients or UpdateAllBarGradients
MSUF.MSUF_UpdateAllBarGradients = MSUF.MSUF_UpdateAllBarGradients or UpdateAllBarGradients

local function SetFrameLevelCached(frame, level)
    if frame and frame.SetFrameLevel and frame._msufFrameLevel ~= level then
        frame:SetFrameLevel(level)
        frame._msufFrameLevel = level
    end
end

local function ExternalFrameWidth(frameName, relativeTo)
    if not frameName then
        return nil
    end
    local frame = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(frameName)) or _G[frameName]
    if not (frame and frame.GetWidth) or (frame.IsShown and not frame:IsShown()) then
        return nil
    end
    local widthFn = _G.MSUF_CDM_GetScaledWidth
    local width = type(widthFn) == "function" and widthFn(frame, relativeTo) or frame:GetWidth()
    width = tonumber(width)
    if width and width >= 20 then
        return width
    end
    return nil
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    local fast = _G.MSUF_UFCore_GetClassBarColorFast
    if type(fast) == "function" and class then
        local r, g, b = fast(class)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        return c.r, c.g, c.b
    end
    return 0.12, 0.62, 0.95
end

local function UnitNPCKind(frame, unit, spec, forText, keyOverride)
    local health = spec and spec.health or {}
    local text = spec and spec.text or {}
    local typeColorEnabled = forText and text.npcTypeColorText or health.npcTypeColorBar
    local colorMode = (forText and text.npcColorMode) or health.npcColorMode
    if colorMode == "type" and typeColorEnabled ~= false then
        local key = keyOverride or spec and spec.key or frame.configKey
        local allowed = true
        if key == "target" then
            if forText then allowed = text.npcTypeTarget ~= false else allowed = health.npcTypeTarget ~= false end
        elseif key == "focus" then
            if forText then allowed = text.npcTypeFocus ~= false else allowed = health.npcTypeFocus ~= false end
        elseif key == "boss" then
            if forText then allowed = text.npcTypeBoss ~= false else allowed = health.npcTypeBoss ~= false end
        elseif key == "targettarget" or key == "focustarget" then
            if forText then allowed = text.npcTypeToT ~= false else allowed = health.npcTypeToT ~= false end
        end
        if allowed and GetUnitClassification then
            local classification = GetUnitClassification(unit)
            if classification == "worldboss" or classification == "rareelite" then
                return "npcBoss"
            elseif classification == "elite" then
                return "npcMiniboss"
            elseif classification == "rare" then
                return "npcCaster"
            elseif classification == "minus" then
                return "npcMelee"
            elseif classification == "normal" then
                return "npcRegular"
            end
        end
    end

    local dead = UnitIsDeadOrGhost(unit)
    if dead then
        return "dead"
    end

    if UnitReaction then
        local reaction = UnitReaction(unit, "player")
        reaction = tonumber(reaction)
        if reaction and reaction >= 5 then
            return "friendly"
        elseif reaction and reaction == 4 then
            return "neutral"
        end
    end
    return "enemy"
end

local function ReadUnitBool(api, unit, defaultValue)
    if not api then
        return defaultValue, false
    end
    local value = api(unit)
    if IsSecret(value) or value == nil then
        return defaultValue, false
    end
    return value == true or value == 1, true
end

local function RefreshUnitState(frame, unit, spec, event)
    if not frame then
        return nil
    end
    unit = unit or frame.unit
    local state = frame._msufUnitState
    if not state then
        state = {}
        frame._msufUnitState = state
    elseif state.unit == unit and state.ready == true then
        local dispatchToken = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
        if dispatchToken and state.dispatchToken == dispatchToken then
            return state
        end
        if event ~= "UNIT_HEALTH"
            and event ~= "UNIT_POWER_FREQUENT"
            and event ~= "UNIT_POWER_UPDATE" then
            -- Full recompute below: lower-frequency events may change identity,
            -- connection or NPC-kind state.
        else
            -- High-frequency value ticks cannot change unit identity, existence,
            -- death, connection or NPC-kind; those arrive on their own events and
            -- refresh the cache then. Reusing the cached state drops several C
            -- calls per health/power tick on the player frame.
            return state
        end
    end

    local dispatchToken = frame._msufDispatchActive == true and frame._msufDispatchToken or nil
    state.unit = unit
    state.dispatchToken = dispatchToken
    state.ready = true
    state.exists, state.existsKnown = ReadUnitBool(UnitExists, unit, true)
    state.dead, state.deadKnown = ReadUnitBool(UnitIsDeadOrGhost, unit, false)
    state.connected, state.connectedKnown = ReadUnitBool(UnitIsConnected, unit, true)
    state.isPlayer, state.isPlayerKnown = ReadUnitBool(UnitIsPlayer, unit, false)
    state.npcKind = nil
    state.npcKindKnown = false
    if state.isPlayerKnown and not state.isPlayer then
        state.npcKind = UnitNPCKind(frame, unit, spec)
        state.npcKindKnown = state.npcKind ~= nil
    end
    return state
end

local function NPCColor(kind)
    local fast = _G.MSUF_UFCore_GetNPCReactionColorFast
    if type(fast) == "function" then
        local r, g, b = fast(kind)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if kind == "friendly" then return 0, 1, 0 end
    if kind == "neutral" then return 1, 1, 0 end
    if kind == "dead" then return 0.4, 0.4, 0.4 end
    if kind == "npcBoss" then return 0.74, 0.11, 0 end
    if kind == "npcMiniboss" then return 0.56, 0, 0.74 end
    if kind == "npcCaster" then return 0, 0.45, 0.74 end
    if kind == "npcMelee" then return 0.99, 0.99, 0.99 end
    if kind == "npcRegular" then return 0.70, 0.56, 0.33 end
    return 0.85, 0.10, 0.10
end

local healthGradientCurve
local function HealthGradientCurve()
    if healthGradientCurve ~= nil then
        return healthGradientCurve
    end
    if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
        local curve = C_CurveUtil.CreateColorCurve()
        curve:AddPoint(0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(0.5, CreateColor(1, 1, 0, 1))
        curve:AddPoint(1, CreateColor(0, 1, 0, 1))
        healthGradientCurve = curve
    else
        healthGradientCurve = false
    end
    return healthGradientCurve
end

local function GradientColor(unit, calc)
    local curve = HealthGradientCurve()
    if calc and curve and calc.EvaluateCurrentHealthPercent then
        local color = calc:EvaluateCurrentHealthPercent(curve)
        if color and color.GetRGB then
            local r, g, b = color:GetRGB()
            return r, g, b, true
        end
    end
    if UnitHealthPercent and curve then
        local color = UnitHealthPercent(unit, true, curve)
        if color and color.GetRGB then
            local r, g, b = color:GetRGB()
            return r, g, b, true
        end
    end
    return 0.2, 0.8, 0.2, false
end

local function HealthColor(frame, unit, hp, maxHP, calc)
    local spec = frame and frame.MSUFSpec
    local health = spec and spec.health or {}
    local state = RefreshUnitState(frame, unit, spec, "UNIT_HEALTH")
    if state and state.existsKnown and state.exists == false then
        return 0.28, 0.28, 0.28
    end
    if state and ((state.deadKnown and state.dead == true) or (state.connectedKnown and state.connected == false)) then
        return 0.35, 0.35, 0.35
    end

    if health.mode == "dark" or health.mode == "unified" then
        return health.r or 1, health.g or 1, health.b or 1
    elseif health.mode == "gradient" then
        return GradientColor(unit, calc)
    end

    if spec and spec.key == "pet" and health.petColorEnabled == true then
        return health.petR or 0, health.petG or 0.8, health.petB or 0
    end

    if state and state.isPlayerKnown and state.isPlayer then
        return ClassColor(unit)
    end

    local kind = state and state.npcKindKnown and state.npcKind or UnitNPCKind(frame, unit, spec)
    if kind then
        return NPCColor(kind)
    elseif UnitSelectionColor then
        local r, g, b = UnitSelectionColor(unit)
        if r ~= nil then
            return r, g, b
        end
    end
    return health.r or 0.1, health.g or 0.6, health.b or 0.9
end

local function ApplyHealthStatusColor(bar, frame, unit, hp, maxHP, calc)
    local spec = frame and frame.MSUFSpec
    local health = spec and spec.health or {}
    local r, g, b, raw = HealthColor(frame, unit, hp, maxHP, calc)
    if health.mode == "gradient" and raw == true then
        bar:SetStatusBarColor(r, g, b, 1)
        bar._msufStatusR, bar._msufStatusG, bar._msufStatusB, bar._msufStatusA = nil, nil, nil, nil
        return true
    end
    ApplyStatusColor(bar, r, g, b)
    return false
end

local function ApplyBackgrounds(frame, health, power)
    local spec = frame and frame.MSUFSpec
    if not spec then
        return
    end
    if health == nil then health = true end
    if power == nil then power = true end
    local hb = spec.health and spec.health.background
    if health and frame.bg and hb then
        local r, g, b = hb.r, hb.g, hb.b
        if frame._msufHealthBgDynamic == true and frame.hpBar and frame.hpBar.GetStatusBarColor then
            local cr, cg, cb = frame.hpBar:GetStatusBarColor()
            if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                r, g, b = cr, cg, cb
            end
        end
        ApplyTextureColor(frame.bg, spec.health.backgroundTexture, r, g, b, hb.a or spec.backgroundAlpha or 0.9)
        frame._msufHPBgTex = spec.health.backgroundTexture
    end
    local pb = spec.power and spec.power.background
    if power and frame.powerBarBG and pb then
        local r, g, b = pb.r, pb.g, pb.b
        if frame._msufPowerBgDynamic == true and frame.hpBar and frame.hpBar.GetStatusBarColor then
            local cr, cg, cb = frame.hpBar:GetStatusBarColor()
            if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                r, g, b = cr, cg, cb
            end
        end
        ApplyTextureColor(frame.powerBarBG, spec.power.backgroundTexture, r, g, b, pb.a or spec.backgroundAlpha or 0.9)
        frame._msufPowerBgTex = spec.power.backgroundTexture
    end
end

local function PowerColor(frame, unit)
    local spec = frame and frame.MSUFSpec
    local powerSpec = spec and spec.power or {}
    if powerSpec.mode == "dark" or powerSpec.mode == "unified" or powerSpec.mode == "static" then
        return powerSpec.r or 0.1, powerSpec.g or 0.35, powerSpec.b or 0.95
    elseif powerSpec.mode == "class" then
        return ClassColor(unit)
    end

    local powerType, token = UnitPowerType(unit)
    local tokenKey = not IsSecret(token) and token or nil
    local powerTypeKey = not IsSecret(powerType) and powerType or nil
    local resolved = _G.MSUF_GetResolvedPowerColor
    if type(resolved) == "function" then
        local r, g, b = resolved(powerTypeKey, tokenKey)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local override = powerSpec.colors and tokenKey ~= nil and powerSpec.colors[tokenKey] or nil
    if override then
        return override.r, override.g, override.b
    end
    local c = tokenKey ~= nil and PowerBarColor and PowerBarColor[tokenKey]
    if not c and powerTypeKey ~= nil then
        c = PowerBarColor and PowerBarColor[powerTypeKey]
    end
    if not c then
        c = PowerBarColor and PowerBarColor["MANA"]
    end
    return c and c.r or 0.2, c and c.g or 0.45, c and c.b or 1
end

MSUF.UFBarTextCommon = {
    UF = UF,
    CreateFrame = CreateFrame,
    UnitClass = UnitClass,
    UnitExists = UnitExists,
    UnitHealth = UnitHealth,
    UnitHealthMax = UnitHealthMax,
    UnitGetTotalAbsorbs = UnitGetTotalAbsorbs,
    UnitPower = UnitPower,
    UnitPowerMax = UnitPowerMax,
    UnitPowerType = UnitPowerType,
    UnitHealthPercent = UnitHealthPercent,
    UnitPowerPercent = UnitPowerPercent,
    AbbreviateNumbers = AbbreviateNumbers,
    BreakUpLargeNumbers = BreakUpLargeNumbers,
    AbbreviateLargeNumbers = AbbreviateLargeNumbers,
    InCombatLockdown = InCombatLockdown,
    UnitName = UnitName,
    UnitIsPlayer = UnitIsPlayer,
    UnitIsDeadOrGhost = UnitIsDeadOrGhost,
    UnitIsConnected = UnitIsConnected,
    UnitReaction = UnitReaction,
    UnitSelectionColor = UnitSelectionColor,
    GetUnitClassification = GetUnitClassification,
    PowerBarColor = PowerBarColor,
    RAID_CLASS_COLORS = RAID_CLASS_COLORS,
    type = type,
    tonumber = tonumber,
    format = format,
    byte = byte,
    sub = sub,
    abs = abs,
    floor = floor,
    max = max,
    GetTime = GetTime,
    C_Timer = C_Timer,
    StatusBarInterpolation = StatusBarInterpolation,
    SMOOTH_INTERP = SMOOTH_INTERP,
    WHITE = WHITE,
    SCALE_100 = SCALE_100,
    REVERSE_HEALTH_MODE = REVERSE_HEALTH_MODE,
    EMPTY_EVENTS = EMPTY_EVENTS,
    POWER_EVENTS = POWER_EVENTS,
    POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT,
    TEXT_EVENT_SETS = TEXT_EVENT_SETS,
    TEXT_EVENT_SETS_ABSORB = TEXT_EVENT_SETS_ABSORB,
    ClampFrameLayer = ClampFrameLayer,
    DrawSubLayer = DrawSubLayer,
    GetLayerBaseLevel = GetLayerBaseLevel,
    IsSecret = IsSecret,
    IsNil = IsNil,
    RefreshUnitState = RefreshUnitState,
    SetStatusTexture = SetStatusTexture,
    ApplyStatusColor = ApplyStatusColor,
    SetBarMinMax = SetBarMinMax,
    SetBarValue = SetBarValue,
    SnapBarInterpolation = SnapBarInterpolation,
    SetBarSmoothing = SetBarSmoothing,
    ApplyTextureColor = ApplyTextureColor,
    SetShownCached = SetShownCached,
    ApplyBarGradient = ApplyBarGradient,
    HideBarGradient = HideBarGradient,
    UpdateAllBarGradients = UpdateAllBarGradients,
    SetFrameLevelCached = SetFrameLevelCached,
    ExternalFrameWidth = ExternalFrameWidth,
    ClassColor = ClassColor,
    UnitNPCKind = UnitNPCKind,
    NPCColor = NPCColor,
    GradientColor = GradientColor,
    HealthColor = HealthColor,
    ApplyHealthStatusColor = ApplyHealthStatusColor,
    ApplyBackgrounds = ApplyBackgrounds,
    PowerColor = PowerColor,
}
