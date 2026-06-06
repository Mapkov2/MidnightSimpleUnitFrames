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
local UnitPower = C.UnitPower
local UnitPowerMax = C.UnitPowerMax
local UnitPowerType = C.UnitPowerType
local UnitHealthPercent = C.UnitHealthPercent
local UnitPowerPercent = C.UnitPowerPercent
local AbbreviateNumbers = C.AbbreviateNumbers
local BreakUpLargeNumbers = C.BreakUpLargeNumbers
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
local abs = C.abs
local floor = C.floor
local max = C.max
local GetTime = C.GetTime
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
local ApplyBackgrounds = C.ApplyBackgrounds
local PowerColor = C.PowerColor
local Text = MSUF.UFText or {}
MSUF.UFText = Text
local Secrets = MSUF.Secrets or {}
local IsSecret = C.IsSecret or Secrets.IsSecret or function(_) return false end

local STANDARD_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- Returns true if the FontString's actually-applied font matches what we asked
-- for. On a failed SetFont the engine keeps the previous font, so GetFont() will
-- not match -> we treat that as "not applied" and retry on the next layout pass.
local function FontApplied(fs, requested)
    if type(fs.GetFont) ~= "function" then return true end
    local actual = fs:GetFont()
    if not actual then return false end
    return tostring(actual):gsub("/", "\\"):lower() == tostring(requested or ""):gsub("/", "\\"):lower()
end

local function ApplyFontChecked(fs, requested, size, flags)
    if not (fs and type(fs.SetFont) == "function") then return false end
    local safeSet = _G.MSUF_SetFontSafe
    if type(safeSet) == "function" then
        return safeSet(fs, requested, size, flags) == true and FontApplied(fs, requested)
    end
    local ok, applied = pcall(fs.SetFont, fs, requested, size, flags)
    return ok and applied ~= false and FontApplied(fs, requested)
end

local function SetFont(fs, spec, size)
    if not fs then
        return
    end
    local font = (spec and spec.font) or STANDARD_FONT
    local fontSize = tonumber(size) or 12
    local flags = spec and spec.fontFlags or "OUTLINE"
    if fs._msufFont ~= font or fs._msufFontSize ~= fontSize or fs._msufFontFlags ~= flags then
        if ApplyFontChecked(fs, font, fontSize, flags) then
            fs._msufFont = font
            fs._msufFontSize = fontSize
            fs._msufFontFlags = flags
        else
            -- Cold-start race: the requested font isn't loadable yet. Apply a
            -- guaranteed-present fallback so the text is visible and measurable,
            -- but DO NOT cache the requested font -- leave the memo cleared so the
            -- next layout pass retries it once the real font has loaded. (Without
            -- this the memo records the intended font and the fallback face/metrics
            -- stick until a /reload.)
            ApplyFontChecked(fs, STANDARD_FONT, fontSize, flags)
            fs._msufFont = nil
            fs._msufFontSize = nil
            fs._msufFontFlags = nil
        end
    end
    local color = spec and spec.textColor
    local r, g, b, a = color and color.r or 1, color and color.g or 1, color and color.b or 1, color and color.a or 1
    if fs._msufTextR ~= r or fs._msufTextG ~= g or fs._msufTextB ~= b or fs._msufTextA ~= a then
        fs:SetTextColor(r, g, b, a)
        fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
    end
    if fs.SetShadowOffset then
        local shadowOn = spec and spec.fontShadow == true
        local sx = shadowOn and (tonumber(spec and spec.fontShadowX) or 1) or 0
        local sy = shadowOn and (tonumber(spec and spec.fontShadowY) or -1) or 0
        local sa = shadowOn and (tonumber(spec and spec.fontShadowAlpha) or 1) or 0
        if fs._msufShadowX ~= sx or fs._msufShadowY ~= sy or fs._msufShadowA ~= sa then
            if shadowOn and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, sa) end
            fs:SetShadowOffset(sx, sy)
            fs._msufShadowX, fs._msufShadowY, fs._msufShadowA = sx, sy, sa
        end
    end
end

local function SetPowerTextColor(frame, r, g, b, a)
    a = a or 1
    if frame._msufPowerTextR == r
        and frame._msufPowerTextG == g
        and frame._msufPowerTextB == b
        and frame._msufPowerTextA == a then
        return
    end
    -- Keep the per-fontstring color cache (fs._msufText*) in sync with the actual
    -- color we apply here. SetFont() short-circuits on that same cache, so if we
    -- skip it the stale type color survives when power-color-by-type is toggled off.
    local left, center, right = frame.powerTextLeft, frame.powerTextCenter, frame.powerTextRight
    if left then
        left:SetTextColor(r, g, b, a)
        left._msufTextR, left._msufTextG, left._msufTextB, left._msufTextA = r, g, b, a
    end
    if center then
        center:SetTextColor(r, g, b, a)
        center._msufTextR, center._msufTextG, center._msufTextB, center._msufTextA = r, g, b, a
    end
    if right then
        right:SetTextColor(r, g, b, a)
        right._msufTextR, right._msufTextG, right._msufTextB, right._msufTextA = r, g, b, a
    end
    frame._msufPowerTextR, frame._msufPowerTextG, frame._msufPowerTextB, frame._msufPowerTextA = r, g, b, a
end

local function SetHealthTextSlotColor(fs, r, g, b, a)
    if not fs then
        return
    end
    fs:SetTextColor(r, g, b, a)
    fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
end

local function SetHealthTextSlotColorSecret(fs, r, g, b, a)
    if not fs then
        return
    end
    fs:SetTextColor(r, g, b, a)
    fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = nil, nil, nil, nil
end

local function SetHealthTextSlotsColor(slots, count, setter, r, g, b, a)
    if not (slots and count and count > 0) then
        return false
    end
    for i = 1, count do
        local slot = slots[i]
        setter(slot and slot.fs, r, g, b, a)
    end
    return true
end

local function SetHealthTextColor(frame, rt, r, g, b, a)
    a = a or 1
    if IsSecret(r) or IsSecret(g) or IsSecret(b) or IsSecret(a) then
        if not SetHealthTextSlotsColor(rt and rt.healthSlots, rt and rt.healthSlotCount, SetHealthTextSlotColorSecret, r, g, b, a) then
            SetHealthTextSlotColorSecret(frame.hpTextLeft, r, g, b, a)
            SetHealthTextSlotColorSecret(frame.hpTextCenter, r, g, b, a)
            SetHealthTextSlotColorSecret(frame.hpTextRight, r, g, b, a)
        end
        frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = nil, nil, nil, nil
        return
    end
    if frame._msufHealthTextR == r
        and frame._msufHealthTextG == g
        and frame._msufHealthTextB == b
        and frame._msufHealthTextA == a then
        return
    end
    if not SetHealthTextSlotsColor(rt and rt.healthSlots, rt and rt.healthSlotCount, SetHealthTextSlotColor, r, g, b, a) then
        SetHealthTextSlotColor(frame.hpTextLeft, r, g, b, a)
        SetHealthTextSlotColor(frame.hpTextCenter, r, g, b, a)
        SetHealthTextSlotColor(frame.hpTextRight, r, g, b, a)
    end
    frame._msufHealthTextR, frame._msufHealthTextG, frame._msufHealthTextB, frame._msufHealthTextA = r, g, b, a
end

local function BaseTextColor(frame)
    local spec = frame and frame.MSUFSpec
    local color = spec and spec.textColor
    return color and color.r or 1, color and color.g or 1, color and color.b or 1, color and color.a or 1
end

local function HealthGradientFromValues(hp, hpMax)
    if IsSecret(hp) or IsSecret(hpMax) then
        return nil
    end
    hp = tonumber(hp)
    hpMax = tonumber(hpMax)
    if not hp or not hpMax or hpMax <= 0 then
        return nil
    end
    local pct = hp / hpMax
    if pct < 0 then
        pct = 0
    elseif pct > 1 then
        pct = 1
    end
    if pct <= 0.5 then
        return 1, pct * 2, 0, 1
    end
    return (1 - pct) * 2, 1, 0, 1
end

local function HealthTextColor(frame, unit, hp, hpMax)
    local calc = frame and frame._msufHealthCalc
    local r, g, b, raw = GradientColor(unit, calc)
    if raw == true then
        local _, _, _, a = BaseTextColor(frame)
        return r, g, b, a
    end
    r, g, b = HealthGradientFromValues(hp, hpMax)
    if r then
        local _, _, _, a = BaseTextColor(frame)
        return r, g, b, a
    end
    return BaseTextColor(frame)
end

local function UpdateHealthTextColor(frame, rt, unit, hp, hpMax)
    if not (rt and rt.healthColorByHealth == true and frame) then
        return
    end
    SetHealthTextColor(frame, rt, HealthTextColor(frame, unit or frame.unit, hp, hpMax))
end

local function SetNameTextColor(frame, r, g, b, a)
    a = a or 1
    if frame._msufNameTextR == r
        and frame._msufNameTextG == g
        and frame._msufNameTextB == b
        and frame._msufNameTextA == a then
        return
    end
    if frame.nameText then
        frame.nameText:SetTextColor(r, g, b, a)
    end
    if frame._msufNameDotsFS then
        frame._msufNameDotsFS:SetTextColor(r, g, b, a)
    end
    frame._msufNameTextR, frame._msufNameTextG, frame._msufNameTextB, frame._msufNameTextA = r, g, b, a
end

local function NameTextColorFor(frame, unit, classNames, npcNames, keyOverride)
    local spec = frame and frame.MSUFSpec
    local fallback = spec and spec.textColor
    local fr, fg, fb, fa = fallback and fallback.r or 1, fallback and fallback.g or 1, fallback and fallback.b or 1, fallback and fallback.a or 1
    if not classNames and not npcNames then
        return fr, fg, fb, fa
    end
    local isPlayer = UnitIsPlayer(unit)
    if isPlayer then
        if classNames then
            local r, g, b = ClassColor(unit)
            return r, g, b, fa
        end
    elseif npcNames then
        local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, keyOverride))
        return r, g, b, fa
    end
    return fr, fg, fb, fa
end

local function NameTextColor(frame, unit)
    local spec = frame and frame.MSUFSpec
    local text = spec and spec.text or {}
    local override = text.nameColor
    if type(override) == "table" then
        return override.r or 1, override.g or 1, override.b or 1, override.a or 1
    end
    return NameTextColorFor(frame, unit, text.nameClassColor == true, text.nameNpcColor == true)
end

local function SetInlineTextColor(frame, r, g, b, a)
    a = a or 1
    if frame._msufInlineTextR == r
        and frame._msufInlineTextG == g
        and frame._msufInlineTextB == b
        and frame._msufInlineTextA == a then
        return
    end
    if frame.totInlineText then
        frame.totInlineText:SetTextColor(r, g, b, a)
    end
    if frame._msufInlineDotsFS then
        frame._msufInlineDotsFS:SetTextColor(r, g, b, a)
    end
    frame._msufInlineTextR, frame._msufInlineTextG, frame._msufInlineTextB, frame._msufInlineTextA = r, g, b, a
end

local function InlineTextColor(frame, unit, inline)
    local spec = frame and frame.MSUFSpec
    local fallback = spec and spec.textColor
    local fr, fg, fb, fa = fallback and fallback.r or 1, fallback and fallback.g or 1, fallback and fallback.b or 1, fallback and fallback.a or 1
    local mode = inline and inline.colorMode or "AUTO"
    if mode == "DEFAULT" then
        return fr, fg, fb, fa
    elseif mode == "TARGET_NAME" then
        return NameTextColorFor(frame, frame.unit, inline.targetNameClassColor == true, inline.targetNameNpcColor == true)
    elseif mode == "TOT_NAME" then
        return NameTextColorFor(frame, unit, inline.totNameClassColor == true, inline.totNameNpcColor == true, "targettarget")
    end

    local isPlayer = UnitIsPlayer(unit)
    if mode == "NPC" then
        if not isPlayer then
            local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, "targettarget"))
            return r, g, b, fa
        end
        return fr, fg, fb, fa
    end
    if isPlayer then
        if inline and inline.targetNameClassColor == true then
            local r, g, b = ClassColor(unit)
            return r, g, b, fa
        end
    elseif inline and inline.targetNameNpcColor == true then
        local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, "targettarget"))
        return r, g, b, fa
    end
    return fr, fg, fb, fa
end
Text.C = C
Text.UF = UF
Text.Secrets = Secrets
Text.IsSecret = Secrets.IsSecret or function(_) return false end
Text.IsNil = Secrets.IsNil or function(value) return value == nil end
Text.ValueOrDefault = Secrets.ValueOrDefault or function(value, fallback)
    if value == nil then return fallback end
    return value
end
Text.CreateFrame = CreateFrame
Text.UnitClass = UnitClass
Text.UnitExists = UnitExists
Text.UnitHealth = UnitHealth
Text.UnitHealthMax = UnitHealthMax
Text.UnitPower = UnitPower
Text.UnitPowerMax = UnitPowerMax
Text.UnitPowerType = UnitPowerType
Text.UnitHealthPercent = UnitHealthPercent
Text.UnitPowerPercent = UnitPowerPercent
Text.AbbreviateNumbers = AbbreviateNumbers
Text.BreakUpLargeNumbers = BreakUpLargeNumbers
Text.AbbreviateLargeNumbers = AbbreviateLargeNumbers
Text.InCombatLockdown = InCombatLockdown
Text.UnitName = UnitName
Text.UnitIsPlayer = UnitIsPlayer
Text.UnitIsDeadOrGhost = UnitIsDeadOrGhost
Text.UnitIsConnected = UnitIsConnected
Text.UnitReaction = UnitReaction
Text.UnitSelectionColor = UnitSelectionColor
Text.GetUnitClassification = GetUnitClassification
Text.PowerBarColor = PowerBarColor
Text.RAID_CLASS_COLORS = RAID_CLASS_COLORS
Text.type = type
Text.tonumber = tonumber
Text.format = format
Text.abs = abs
Text.floor = floor
Text.max = max
Text.GetTime = GetTime
Text.StatusBarInterpolation = StatusBarInterpolation
Text.SMOOTH_INTERP = SMOOTH_INTERP
Text.WHITE = WHITE
Text.SCALE_100 = SCALE_100
Text.REVERSE_HEALTH_MODE = REVERSE_HEALTH_MODE
Text.EMPTY_EVENTS = EMPTY_EVENTS
Text.POWER_EVENTS = POWER_EVENTS
Text.POWER_EVENTS_FREQUENT = POWER_EVENTS_FREQUENT
Text.TEXT_EVENT_SETS = TEXT_EVENT_SETS
Text.TEXT_EVENT_SETS_ABSORB = TEXT_EVENT_SETS_ABSORB
Text.ClampFrameLayer = ClampFrameLayer
Text.DrawSubLayer = DrawSubLayer
Text.GetLayerBaseLevel = GetLayerBaseLevel
Text.SetStatusTexture = SetStatusTexture
Text.ApplyStatusColor = ApplyStatusColor
Text.SetBarMinMax = SetBarMinMax
Text.SetBarValue = SetBarValue
Text.SnapBarInterpolation = SnapBarInterpolation
Text.SetBarSmoothing = SetBarSmoothing
Text.ApplyTextureColor = ApplyTextureColor
Text.SetShownCached = SetShownCached
Text.SetFrameLevelCached = SetFrameLevelCached
Text.ExternalFrameWidth = ExternalFrameWidth
Text.ClassColor = ClassColor
Text.UnitNPCKind = UnitNPCKind
Text.NPCColor = NPCColor
Text.GradientColor = GradientColor
Text.HealthColor = HealthColor
Text.ApplyBackgrounds = ApplyBackgrounds
Text.PowerColor = PowerColor
Text.SetFont = SetFont
Text.SetPowerTextColor = SetPowerTextColor
Text.SetHealthTextColor = SetHealthTextColor
Text.HealthTextColor = HealthTextColor
Text.UpdateHealthTextColor = UpdateHealthTextColor
Text.SetNameTextColor = SetNameTextColor
Text.NameTextColorFor = NameTextColorFor
Text.NameTextColor = NameTextColor
Text.SetInlineTextColor = SetInlineTextColor
Text.InlineTextColor = InlineTextColor
