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

local function SetFont(fs, spec, size)
    if not fs then
        return
    end
    local font = (spec and spec.font) or (_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    local fontSize = tonumber(size) or 12
    local flags = spec and spec.fontFlags or "OUTLINE"
    if fs._msufFont ~= font or fs._msufFontSize ~= fontSize or fs._msufFontFlags ~= flags then
        fs:SetFont(font, fontSize, flags)
        fs._msufFont = font
        fs._msufFontSize = fontSize
        fs._msufFontFlags = flags
    end
    local color = spec and spec.textColor
    local r, g, b, a = color and color.r or 1, color and color.g or 1, color and color.b or 1, color and color.a or 1
    if fs._msufTextR ~= r or fs._msufTextG ~= g or fs._msufTextB ~= b or fs._msufTextA ~= a then
        fs:SetTextColor(r, g, b, a)
        fs._msufTextR, fs._msufTextG, fs._msufTextB, fs._msufTextA = r, g, b, a
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
    if frame.powerTextLeft then frame.powerTextLeft:SetTextColor(r, g, b, a) end
    if frame.powerTextCenter then frame.powerTextCenter:SetTextColor(r, g, b, a) end
    if frame.powerTextRight then frame.powerTextRight:SetTextColor(r, g, b, a) end
    frame._msufPowerTextR, frame._msufPowerTextG, frame._msufPowerTextB, frame._msufPowerTextA = r, g, b, a
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
            return r, g, b, 1
        end
    elseif npcNames then
        local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, keyOverride))
        return r, g, b, 1
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
            return r, g, b, 1
        end
        return fr, fg, fb, fa
    end
    if isPlayer then
        if inline and inline.targetNameClassColor == true then
            local r, g, b = ClassColor(unit)
            return r, g, b, 1
        end
    elseif inline and inline.targetNameNpcColor == true then
        local r, g, b = NPCColor(UnitNPCKind(frame, unit, spec, true, "targettarget"))
        return r, g, b, 1
    end
    return fr, fg, fb, fa
end
Text.C = C
Text.UF = UF
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
Text.SetNameTextColor = SetNameTextColor
Text.NameTextColorFor = NameTextColorFor
Text.NameTextColor = NameTextColor
Text.SetInlineTextColor = SetInlineTextColor
Text.InlineTextColor = InlineTextColor
