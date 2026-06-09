local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local V = MSUF.UFVisuals or {}
local UF = V.UF or MSUF.UF
local tonumber = V.tonumber or tonumber
local EMPTY_EVENTS = V.EMPTY_EVENTS or {}
local Clamp01 = V.Clamp01
local SetFrameAlpha = V.SetFrameAlpha
local SetAlphaCached = V.SetAlphaCached

-- Unified, coldpath alpha element.
--
-- One value drives everything: spec.alpha.hpAlpha (the HP-fill transparency slider).
-- When spec.alpha.excludeTextPortrait is false, the same value also dims the frame
-- texts and the portrait so the whole foreground fades together. When true, texts +
-- portrait stay fully opaque and only the bar textures dim.
--
-- Background opacity is NOT handled here -- it is baked into the bar background
-- colour (out.health.background.a, from hpBgAlpha) by the config compiler.
--
-- Range fade is a pure multiplier on top: MSUF_UF_RangeFade stores frame._msufRangeMul
-- and calls UF.ApplyRangeModifier, which re-applies hpAlpha * mul (or dims the whole
-- frame, depending on the range layer mode). The element stays disabled while hpAlpha
-- == 1, but ApplyRangeModifier is self-sufficient so range still works in that case.

local Alpha = {}

local function CastbarForUnit(unit)
    if not unit then
        return nil
    end
    if unit == "target" then
        return _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar or _G.TargetCastBar
    elseif unit == "focus" then
        return _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar or _G.FocusCastBar
    end

    local bossIndex = tostring(unit):match("^boss(%d+)$")
    if bossIndex then
        local index = tonumber(bossIndex)
        local bossCastbars = _G.MSUF_BossCastbars
        return (bossCastbars and bossCastbars[index])
            or _G["MSUF_BossCastbar" .. bossIndex]
            or _G["MSUF_boss" .. bossIndex .. "CastBar"]
            or _G["MSUF_Boss" .. bossIndex .. "CastBar"]
    end

    return nil
end

local function CastbarRangeAlpha(frame, mul)
    if not frame then
        return 1
    end
    local spec = frame.MSUFSpec
    local range = spec and spec.range
    if not (range and range.active == true) or range.layerMode == "health" then
        return 1
    end
    return Clamp01(mul, 1)
end

local function ApplyCastbarRangeAlpha(frame, mul, force)
    local unit = frame and frame.unit
    local castbar = CastbarForUnit(unit)
    if not (castbar and castbar.SetAlpha) then
        return false
    end
    if castbar._msufFocusKickSuppressed == true then
        return false
    end

    local alpha = CastbarRangeAlpha(frame, mul)
    SetAlphaCached(castbar, alpha, "_msufRangeCastbarAlpha", force)
    return true
end

local TEXT_ALPHA_FIELDS = {
    "nameText",
    "levelText",
    "hpTextLeft",
    "hpTextCenter",
    "hpTextRight",
    "powerTextLeft",
    "powerTextCenter",
    "powerTextRight",
    "totInlineSep",
    "totInlineText",
    "raidGroupNameText",
    "statusIndicatorText",
}

local function StatusBarTexture(bar)
    if not (bar and bar.GetStatusBarTexture) then
        return nil
    end
    local texture = bar._msufAlphaStatusTextureObject
    if not texture then
        texture = bar:GetStatusBarTexture()
        bar._msufAlphaStatusTextureObject = texture
    end
    return texture
end

-- Dim only the fill texture of a StatusBar, never the bar object itself. The bar
-- object's alpha is owned by other systems (group health-fade, group range fade), so
-- touching only the fill texture lets those multiply cleanly with our configured alpha.
local function SetStatusBarFillAlpha(bar, alpha, field, force)
    if not bar then
        return
    end
    SetAlphaCached(StatusBarTexture(bar), alpha, field or "_msufAlphaStatusTexture", force)
end

local function SetTextLayerAlpha(frame, alpha, force)
    for i = 1, #TEXT_ALPHA_FIELDS do
        SetAlphaCached(frame and frame[TEXT_ALPHA_FIELDS[i]], alpha, "_msufAlphaText", force)
    end
end

local function SetPortraitLayerAlpha(frame, alpha, force)
    SetAlphaCached(frame and frame.MSUFPortraitHolder, alpha, "_msufAlphaPortraitHolder", force)
    SetAlphaCached(frame and frame.portrait, 1, "_msufAlphaPortraitTexture", force)
end

-- Apply the HP-fill alpha to the health bar and any prediction bars that sit on top
-- of it, so absorbs/heal-prediction fade with the health fill.
local function ApplyHealthFillAlpha(frame, alpha, force)
    SetStatusBarFillAlpha(frame.hpBar or frame.Health, alpha, "_msufAlphaHealth", force)
    SetStatusBarFillAlpha(frame.incomingHealBar, alpha, "_msufAlphaPrediction", force)
    SetStatusBarFillAlpha(frame.absorbBar, alpha, "_msufAlphaPrediction", force)
    SetStatusBarFillAlpha(frame.healAbsorbBar, alpha, "_msufAlphaPrediction", force)
end

local function RangeMul(frame)
    local mul = tonumber(frame and frame._msufRangeMul)
    if mul == nil then
        return 1
    elseif mul < 0 then
        return 0
    elseif mul > 1 then
        return 1
    end
    return mul
end

-- "health" range fade dims only the HP fill; anything else dims the whole frame.
local function RangeFadesWholeFrame(frame)
    local spec = frame and frame.MSUFSpec
    local range = spec and spec.range
    return not (range and range.layerMode == "health")
end

-- Resolve the configured HP-fill alpha (independent of range), clamped, with the
-- edit-mode floor so bars never fully vanish while the user is positioning frames.
local function ConfiguredHPAlpha(cfg)
    local hp = Clamp01(cfg and cfg.hpAlpha, 1)
    if _G.MSUF_UnitEditModeActive == true and hp < 0.35 then
        hp = 0.35
    end
    return hp
end

local function ResetFrameLayers(frame, force)
    if not frame then
        return
    end
    SetFrameAlpha(frame, 1)
    ApplyCastbarRangeAlpha(frame, 1, force)
    ApplyHealthFillAlpha(frame, 1, force)
    SetTextLayerAlpha(frame, 1, force)
    SetPortraitLayerAlpha(frame, 1, force)
    frame._msufAlphaActive = nil
end

-- The single apply path. `force` re-writes even when the cached values match.
local function ApplyAlpha(frame, cfg, force)
    if not frame then
        return
    end

    local mul = RangeMul(frame)
    local wholeFrame = RangeFadesWholeFrame(frame)

    -- No configured alpha and no range fade -> make sure everything is restored,
    -- then leave the frame alone.
    if not (cfg and cfg.active == true) and mul == 1 then
        if frame._msufAlphaActive == true then
            ResetFrameLayers(frame, force)
        end
        return
    end

    local hp = ConfiguredHPAlpha(cfg)
    local excludeTextPortrait = cfg and cfg.excludeTextPortrait == true

    -- Configured foreground opacity (texts + portrait), before range. The toggle keeps
    -- it fully opaque while the bars dim.
    local foregroundAlpha = excludeTextPortrait and 1 or hp

    -- Range either fades the whole frame (frame alpha, which cascades to texts/portrait)
    -- or only the HP fill texture. Text/portrait are never multiplied by range directly:
    -- in whole-frame mode the frame alpha already covers them; in health mode range is
    -- meant to touch the bar only.
    local frameAlpha = wholeFrame and mul or 1
    local hpAlpha = hp * (wholeFrame and 1 or mul)

    if not force
        and frame._msufAlphaLastFrame == frameAlpha
        and frame._msufAlphaLastHP == hpAlpha
        and frame._msufAlphaLastFG == foregroundAlpha then
        return
    end

    SetFrameAlpha(frame, frameAlpha)
    ApplyCastbarRangeAlpha(frame, mul, force)
    ApplyHealthFillAlpha(frame, hpAlpha, force)
    SetTextLayerAlpha(frame, foregroundAlpha, force)
    SetPortraitLayerAlpha(frame, foregroundAlpha, force)

    frame._msufAlphaActive = true
    frame._msufAlphaLastFrame = frameAlpha
    frame._msufAlphaLastHP = hpAlpha
    frame._msufAlphaLastFG = foregroundAlpha
end

function Alpha.IsEnabled(frame, spec)
    return spec and spec.alpha and spec.alpha.active == true
end

function Alpha.GetEvents(frame, spec)
    return EMPTY_EVENTS
end

function Alpha.GetUnitlessEvents(frame, spec)
    return EMPTY_EVENTS
end

function Alpha.Apply(frame, spec)
    ApplyAlpha(frame, spec and spec.alpha, true)
end

function Alpha.Update(frame, event)
    local force = event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE"
        or event == "MSUF_VISUALS" or event == "MSUF_ALPHA" or event == "MSUF_RANGE_FORCE"
    ApplyAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, force)
end

function Alpha.Disable(frame)
    if not frame then
        return
    end
    frame._msufAlphaLastFrame = nil
    frame._msufAlphaLastHP = nil
    frame._msufAlphaLastFG = nil
    -- Range fade may still want the frame dimmed even though configured alpha is 1.
    if RangeMul(frame) ~= 1 then
        ApplyAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, true)
        return
    end
    ResetFrameLayers(frame, true)
end

-- Range fade entry point. Stores the multiplier and re-applies. Stays self-sufficient
-- (does not depend on the element being enabled), because the dispatcher disables the
-- Alpha element whenever hpAlpha == 1 -- but range still needs to dim such frames.
UF.ApplyRangeModifier = function(frame, mul, force)
    if not frame then
        return false
    end
    mul = Clamp01(mul, 1)
    if force ~= true and frame._msufRangeMul == mul then
        return true
    end
    frame._msufRangeMul = mul
    local cfg = frame.MSUFSpec and frame.MSUFSpec.alpha
    if cfg or mul ~= 1 then
        ApplyAlpha(frame, cfg, force == true)
    else
        SetFrameAlpha(frame, mul)
        ApplyCastbarRangeAlpha(frame, mul, force == true)
    end
    return true
end
_G.MSUF_UF_ApplyRangeModifier = UF.ApplyRangeModifier

_G.MSUF_UF_ApplyCastbarRangeAlpha = function(castbarOrUnit, mul, force)
    local unit = type(castbarOrUnit) == "string" and castbarOrUnit
        or castbarOrUnit and castbarOrUnit.unit
    if not unit then
        return false
    end
    local frame = UF.frames and UF.frames[unit]
    if not frame and tostring(unit):match("^boss%d+$") then
        frame = UF.frames and UF.frames.boss
    end
    if not frame then
        return false
    end
    return ApplyCastbarRangeAlpha(frame, mul or RangeMul(frame), force == true)
end

UF.ApplyAlphaFrame = function(frame, event)
    if not frame then
        return false
    end
    Alpha.Update(frame, event or "MSUF_ALPHA")
    return true
end

UF.RegisterElement("Alpha", Alpha)

-- Coalesced refresh of every managed unit frame's alpha. Combat-state alpha no longer
-- exists, so both "all" and the legacy "combat" request resolve to the same refresh.
do
    local pending

    local function Flush()
        pending = nil
        if _G.MSUF_RefreshAllUnitAlphas then
            return _G.MSUF_RefreshAllUnitAlphas()
        end
    end

    function Alpha.RequestRefresh()
        if pending then
            return true
        end
        pending = true
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("UF_ALPHA_FLUSH", Flush)
        elseif _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, Flush)
        else
            Flush()
        end
        return true
    end
end

_G.MSUF_RequestAlphaRefresh = function()
    return Alpha.RequestRefresh()
end

-- Retained for callers (preview API, key bindings). No combat alpha anymore -> refresh
-- everything.
_G.MSUF_RefreshCombatUnitAlphas = function()
    if _G.MSUF_RefreshAllUnitAlphas then
        return _G.MSUF_RefreshAllUnitAlphas()
    end
    return false
end

-- Returns the configured HP-fill alpha for a unit key (preview helper).
_G.MSUF_GetDesiredUnitAlpha = function(key)
    local unit = key == "boss" and "boss1" or key
    if unit == "tot" or unit == "targetoftarget" then
        unit = "targettarget"
    end
    local spec = unit and UF.Config and UF.Config.GetSpec and UF.Config.GetSpec(unit)
    local cfg = spec and spec.alpha
    if not cfg then
        return 1
    end
    return Clamp01(cfg.hpAlpha, 1)
end

_G.MSUF_ApplyUnitAlpha = function(frame, key)
    if not frame then
        return false
    end
    Alpha.Update(frame, "MSUF_ALPHA")
    return true
end

-- preserveHPColor was removed with the layered model; kept as a no-op so the bar
-- colour pipeline (MSUF_Colors / BarsCommon) can call it unconditionally.
_G.MSUF_Alpha_UpdatePreserveMissingHP = function()
end
