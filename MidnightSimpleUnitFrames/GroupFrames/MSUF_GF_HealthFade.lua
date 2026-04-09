--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) MSUF_GF_HealthFade.lua");
-- MSUF_GF_HealthFade.lua — Curve-based health threshold fade
-- Dims GF frames when HP is above a configurable threshold.
-- Healers see who needs healing: low HP = full alpha, high HP = dimmed.
--
-- Architecture: C_CurveUtil.CreateColorCurve() encodes the fade as a
-- step function in the alpha channel. UnitHealthPercent(unit, true, curve)
-- evaluates it C-side and returns a ColorMixin. The alpha goes directly
-- to frame:SetAlpha(). NO Lua-side comparison ever touches secret HP.
--
-- Cost: 1 C-API call per health update per frame (~2µs). Curve is cached.
-- Zero cost when disabled (early return at function entry).
--
-- Midnight 12.0 secret-safe. Zero combat overhead when disabled.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local UnitExists = _G.UnitExists
local issecretvalue = _G.issecretvalue
local CreateColor = _G.CreateColor
local UnitHealthPercent = _G.UnitHealthPercent
local C_CurveUtil = _G.C_CurveUtil

-- Gate: bail if CurveUtil API absent (pre-12.0)
if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
    GF.ApplyHealthFade = function() return false end
    return
end
if not UnitHealthPercent then
    GF.ApplyHealthFade = function() return false end
    return
end

------------------------------------------------------------------------
-- Curve cache: keyed by "threshold_belowAlpha_aboveAlpha".
-- Typically 1-2 unique curves active at any time.
------------------------------------------------------------------------
local _curveCache = {}

local function BuildCurve(threshold, belowAlpha, aboveAlpha)
    Perfy_Trace(Perfy_GetTime(), "Enter", "BuildCurve MSUF_GF_HealthFade.lua:44");
    local key = threshold .. "_" .. belowAlpha .. "_" .. aboveAlpha
    local cached = _curveCache[key]
    if cached then return cached end

    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)

    local pos = threshold / 100  -- 0-1 range
    local below = CreateColor(1, 1, 1, belowAlpha)
    local above = CreateColor(1, 1, 1, aboveAlpha)

    -- Step function: below threshold → belowAlpha, above → aboveAlpha
    curve:AddPoint(0, below)
    if pos > 0.001 then curve:AddPoint(pos - 0.001, below) end
    if pos < 0.999 then curve:AddPoint(pos + 0.001, above) end
    curve:AddPoint(1, above)

    _curveCache[key] = curve
    Perfy_Trace(Perfy_GetTime(), "Leave", "BuildCurve MSUF_GF_HealthFade.lua:44");
    return curve
end

--- Invalidate curve cache (call when options change).
function GF.InvalidateHealthFadeCurve()
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.InvalidateHealthFadeCurve MSUF_GF_HealthFade.lua:67");
    for k in pairs(_curveCache) do _curveCache[k] = nil end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.InvalidateHealthFadeCurve MSUF_GF_HealthFade.lua:67");
end

------------------------------------------------------------------------
-- Apply health fade alpha to a GF frame.
-- Called from dispatchHealth in GF_Effects on every UNIT_HEALTH.
-- Returns true if fade alpha was applied (caller should skip normal alpha).
------------------------------------------------------------------------
function GF.ApplyHealthFade(f, unit)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.ApplyHealthFade MSUF_GF_HealthFade.lua:76");
    if not f or not unit then return false end

    -- Early exit: check cached config flag (set by BuildFrameCache)
    local c = f._c
    if not c or not c.hfEn then return false end

    if not UnitExists(unit) then return false end

    -- Determine below-threshold alpha (full visibility for low HP)
    -- If out-of-range, combine with range fade alpha
    local belowAlpha = 1.0
    if f._msufGFLastRange == false then
        local conf = GF.GetConf(f._msufGFKind or "party")
        belowAlpha = conf and conf.rangeFadeAlpha or 0.4
    end

    local aboveAlpha = c.hfAlpha or 0.5
    local threshold  = c.hfThresh or 100

    -- Build/retrieve cached curve and evaluate via WoW engine
    local curve = BuildCurve(threshold, belowAlpha, aboveAlpha)
    local color = UnitHealthPercent(unit, true, curve)
    if not color then return false end

    -- Extract alpha — plain number, not secret
    local _, _, _, alpha = color:GetRGBA()
    if not alpha then return false end

    -- Apply directly — no diff-gate needed (SetAlpha is cheap, already gated internally)
    f:SetAlpha(alpha)
    f._msufGFHealthFadeActive = true
    Perfy_Trace(Perfy_GetTime(), "Leave", "GF.ApplyHealthFade MSUF_GF_HealthFade.lua:76");
    return true
end

------------------------------------------------------------------------
-- Clear health fade state (unit despawn / feature disabled).
------------------------------------------------------------------------
function GF.ClearHealthFade(f)
    Perfy_Trace(Perfy_GetTime(), "Enter", "GF.ClearHealthFade MSUF_GF_HealthFade.lua:114");
    if f and f._msufGFHealthFadeActive then
        f._msufGFHealthFadeActive = nil
        f:SetAlpha(1)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "GF.ClearHealthFade MSUF_GF_HealthFade.lua:114");
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) MSUF_GF_HealthFade.lua");