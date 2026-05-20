-- MSUF_GF_Effects.lua Ã¢â‚¬â€ Group Frames Phase 2: Events + Effects
-- Per-frame RegisterUnitEvent, range fade (Grid2 pattern), aggro/dispel/target
-- borders, AFK/DND text, UNIT_AURA coalescing
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local _RuntimeEnabledForFrame

local issecretvalue = _G.issecretvalue
local InCombatLockdown = _G.InCombatLockdown
local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected

-- LibCustomGlow for dispel glow
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDND = _G.UnitIsDND
local UnitIsUnit = _G.UnitIsUnit
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitPowerType = _G.UnitPowerType
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitThreatSituation = _G.UnitThreatSituation
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime

local function UpdateGroupNumber(f)
    local fn = GF.UpdateGroupNumberFrame
    if fn then return fn(f) end
end

local function _GF_IsBlizzardDispelRendererActive(conf)
    if not conf or conf.dispelEnabled == false then return false end
    local auras = conf.auras
    if not auras or auras.enabled == false then return false end
    if GF.IsBlizzardAuraTypeEnabled then
        return GF.IsBlizzardAuraTypeEnabled(conf, "dispels") == true
    end
    local Native = ns and ns.MSUF_AuraNative
    if not Native then return false end
    if Native.Supported and not Native.Supported() then return false end
    if Native.IsBlizzardRenderer and not Native.IsBlizzardRenderer(auras.renderer) then return false end
    local types = auras.blizzardTypes
    if Native.TypeEnabled then return Native.TypeEnabled(types, "dispels", true) == true end
    return type(types) ~= "table" or types.dispels ~= false
end
GF.IsBlizzardDispelRendererActive = GF.IsBlizzardDispelRendererActive or _GF_IsBlizzardDispelRendererActive

-- Central scheduler bridge (Foundation/MSUF_Scheduler.lua).
-- Keeps hot-path deferrals keyed/deduped; falls back to C_Timer if a standalone
-- file is loaded without the foundation module.
local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function _MSUF_ScheduleDelayOnce(key, delay, fn)
    local sched = _G.MSUF_ScheduleDelayOnce
    if sched then return sched(key, delay, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(delay or 0, fn) end
    if type(fn) == "function" then return fn() end
end
local AuraUtil = _G.AuraUtil
local CreateFrame = _G.CreateFrame
local PowerBarColor = _G.PowerBarColor
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local UnitGetTotalAbsorbs     = _G.UnitGetTotalAbsorbs
local UnitGetIncomingHeals    = _G.UnitGetIncomingHeals
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction      = _G.UnitGetDetailedHealPrediction

-- C-side gradient color curve (redÃ¢â€ â€™yellowÃ¢â€ â€™green) for GRADIENT health color mode.
-- Evaluated via calc:EvaluateCurrentHealthPercent(curve) Ã¢â‚¬â€ fully secret-safe,
-- zero Lua arithmetic. Replaces 6 Lua ops (UnitHealth, UnitHealthMax,
-- issecretvalueÃƒâ€”2, tonumberÃƒâ€”2, division, conditional) with 1 C-call.
local _gfGradientCurve
do
    local CCU = _G.C_CurveUtil
    local CC  = _G.CreateColor
    if CCU and CCU.CreateColorCurve and CC then
        _gfGradientCurve = CCU.CreateColorCurve()
        _gfGradientCurve:AddPoint(0,   CC(1, 0, 0))   -- red at 0%
        _gfGradientCurve:AddPoint(0.5, CC(1, 1, 0))   -- yellow at 50%
        _gfGradientCurve:AddPoint(1,   CC(0, 1, 0))   -- green at 100%
    end
end
local math_floor = math.floor
local math_max   = math.max

-- Compiled GF text-slot functions moved to GroupFrames\\MSUF_GF_Text.lua.

local function ResolvePowerBarColor(powerToken)
    local resolver = _G.MSUF_GetResolvedPowerColor
    if type(resolver) == "function" then
        local r, g, b = resolver(nil, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    if powerToken and PowerBarColor and PowerBarColor[powerToken] then
        local c = PowerBarColor[powerToken]
        local r = c.r or c[1] or 0.5
        local g = c.g or c[2] or 0.5
        local b = c.b or c[3] or 0.8
        return r, g, b
    end

    return 0.5, 0.5, 0.8
end

-- Forward declarations (defined later in file)
local _GF_IsAbsorbEnabled, _GF_ResolveHealPredAnchorMode, _GF_ApplyHealPredAnchor, _GF_ApplyAbsorbAnchor

------------------------------------------------------------------------
-- HealPredictionCalculator: 1 API call replaces separate
-- UnitHealth + UnitHealthMax + UnitGetIncomingHeals + UnitGetTotalAbsorbs
-- + UnitGetTotalHealAbsorbs.  Per-frame, lazily created.
------------------------------------------------------------------------
local _calcUnsupported
local function _GF_EnsureCalc(f)
    if _calcUnsupported then return nil end
    if f._msufHPCalc then return f._msufHPCalc end
    if not (CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction) then
        _calcUnsupported = true
        return nil
    end
    local calc = CreateUnitHealPredictionCalculator()
    if not calc then _calcUnsupported = true; return nil end
    if calc.SetIncomingHealOverflowPercent then calc:SetIncomingHealOverflowPercent(1) end
    f._msufHPCalc = calc
    return calc
end

------------------------------------------------------------------------
-- Pixel-snapped SetValue: skip SetValue when the filled pixel count
-- hasn't changed.  Avoids redundant C-API calls in 40-man raids where
-- small HP ticks don't move a pixel boundary.
------------------------------------------------------------------------
local function _GF_PixelSnappedSetValue(bar, value, smooth, forceImmediate)
    if not (bar and bar.SetValue) or value == nil then return end
    if issecretvalue and issecretvalue(value) then
        bar._msufSnapPx = nil
        if smooth and not forceImmediate then
            bar:SetValue(value, _smoothInterp or nil)
        else
            bar:SetValue(value)
        end
        return
    end
    local minV, maxV = 0, 1
    if bar.GetMinMaxValues then
        minV, maxV = bar:GetMinMaxValues()
    end
    if issecretvalue and (issecretvalue(minV) or issecretvalue(maxV)) then
        bar._msufSnapPx = nil
        bar:SetValue(value)
        return
    end
    minV = tonumber(minV) or 0
    maxV = tonumber(maxV) or minV
    local range = maxV - minV
    if range <= 0 then
        bar:SetValue(value)
        return
    end
    -- PERF: cache axisPx per bar (only changes on resize/reparent)
    -- Eliminates GetOrientation + GetWidth/GetHeight + GetEffectiveScale per call
    local axisPx = bar._msufCachedAxisPx
    if not axisPx then
        local orient = bar.GetOrientation and bar:GetOrientation()
        local axisLen = (orient == "VERTICAL")
            and (bar.GetHeight and bar:GetHeight() or 0)
            or  (bar.GetWidth  and bar:GetWidth()  or 0)
        if issecretvalue and issecretvalue(axisLen) then
            bar._msufSnapPx = nil
            bar:SetValue(value)
            return
        end
        axisLen = tonumber(axisLen) or 0
        if axisLen <= 0 then bar:SetValue(value); return end
        local scale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        axisPx = math_floor(axisLen * scale + 0.5)
        bar._msufCachedAxisPx = axisPx
        -- Hook OnSizeChanged to invalidate cache
        if not bar._msufSnapHooked then
            bar._msufSnapHooked = true
            bar:HookScript("OnSizeChanged", function(self)
                self._msufCachedAxisPx = nil
                self._msufSnapPx = nil
            end)
        end
    end
    if axisPx <= 0 then bar:SetValue(value); return end
    local v = tonumber(value) or 0
    if v < minV then v = minV end
    if v > maxV then v = maxV end
    local norm = (v - minV) / range
    local filledPx = math_floor(norm * axisPx + 0.5)
    if filledPx < 0 then filledPx = 0 end
    if filledPx > axisPx then filledPx = axisPx end
    if not forceImmediate and bar._msufSnapPx == filledPx and bar._msufSnapAxis == axisPx then
        return
    end
    bar._msufSnapPx   = filledPx
    bar._msufSnapAxis = axisPx
    local snapped = minV + (filledPx / axisPx) * range
    if smooth and not forceImmediate and _smoothInterp then
        bar:SetValue(snapped, _smoothInterp)
    else
        bar:SetValue(snapped)
    end
end

-- Highlight value/config helpers live in GroupFrames\\MSUF_GF_Highlight.lua.
------------------------------------------------------------------------
-- Range fade uses the same UnitInRange-only path as EQoL group frames.
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Dispel type colors (fallback for pre-Midnight clients)
------------------------------------------------------------------------
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Bleed   = { 0.80, 0.10, 0.10 },
}

------------------------------------------------------------------------
-- Aura-effects runtime loads before Effects so UNIT_AURA and border paths bind
-- direct function upvalues instead of per-event compatibility lookups.
------------------------------------------------------------------------
local _GF_RefreshBorder = GF.RefreshBorder or _G.MSUF_GF_RefreshBorder or function() end
local _GF_StopDispelGlow = GF.StopDispelGlow or _G.MSUF_GF_StopDispelGlow or function() end
local _GF_ApplyDispelOverlay = GF.ApplyDispelOverlay or _G.MSUF_GF_ApplyDispelOverlay or function() end
local _GF_ApplyDebuffStripe = GF.ApplyDebuffStripe or _G.MSUF_GF_ApplyDebuffStripe or function() end
local _GF_ClearNativeSuppressedDispel = GF.ClearNativeSuppressedDispel or function() end
local _FrameHasStripeDebuff = GF.FrameHasStripeDebuff or function() return false end
local dispatchAura = GF.DispatchAura or _G.MSUF_GF_DispatchAura or function() end

if type(GF.FinishAuraVisuals) ~= "function" then
    function GF.FinishAuraVisuals(f, unit, c, updateInfo)
        local fn = GF.FinishAuraVisualsImpl
        if type(fn) == "function" then return fn(f, unit, c, updateInfo) end
    end
end

if type(GF._UpdateDispel) ~= "function" then
    function GF._UpdateDispel(f, unit)
        local fn = GF.UpdateDispel
        if type(fn) == "function" then return fn(f, unit) end
    end
end

if type(GF._UpdateDispelFromAuraDelta) ~= "function" then
    function GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
        local fn = GF.UpdateDispelFromAuraDelta
        if type(fn) == "function" then return fn(f, unit, updateInfo) end
        return false, false
    end
end

local function GetDispelColor(dispelName)
    local fn = GF.GetDispelColor
    if type(fn) == "function" and fn ~= GetDispelColor then return fn(dispelName) end
    return 0.25, 0.75, 1.00
end

local function ResolveDispelColor(dispelName, f)
    local fn = GF.ResolveDispelColor
    if type(fn) == "function" and fn ~= ResolveDispelColor then return fn(dispelName, f) end
    return GetDispelColor(dispelName)
end

------------------------------------------------------------------------
-- Range/threat runtime loads before Effects for direct hot-path bindings.
------------------------------------------------------------------------
local ApplyRangeFade = GF.ApplyRangeFade or function() end
local _GF_ShouldApplyRangeOrFrameAlpha = GF.ShouldApplyRangeOrFrameAlpha or function() return false end

if type(GF.RefreshGroupAlphas) ~= "function" then
    function GF.RefreshGroupAlphas()
        local fn = GF.RefreshGroupAlphasImpl
        if type(fn) == "function" then return fn() end
    end
end

local function _NormalizeRangeFadeLayerMode(mode)
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "frame"
end

-- Highlight and status modules load before Effects so hot paths bind direct
-- function upvalues instead of per-event compatibility lookups.
local _applyHighlightBorderStyle = GF.ApplyHighlightBorderStyle or _G.MSUF_GF_ApplyHLBorderStyle or function() end
local _GF_QuickBorderUpdate = GF.QuickBorderUpdate or _G.MSUF_GF_QuickBorderUpdate or function() end
local UpdateTargetIndicator = GF.UpdateTargetIndicator or _G.MSUF_GF_UpdateTarget or function() end
local UpdateStatusText = GF.UpdateStatusText or _G.MSUF_GF_UpdateStatus or function() end
local UpdateAggro = GF.UpdateAggro or GF._UpdateAggro or _G.MSUF_GF_UpdateAggro or function() end

-- Per-frame settings cache lives in GroupFrames\MSUF_GF_FrameCache.lua.
local function _GF_BuildFrameCachePending(f)
    local fn = GF.BuildFrameCacheImpl
    if type(fn) == "function" then return fn(f) end
end
GF.BuildFrameCache = GF.BuildFrameCache or _GF_BuildFrameCachePending

------------------------------------------------------------------------
-- Dispel overlay, debuff stripe, native-dispel cleanup, and full border refresh live in GroupFrames\\MSUF_GF_AuraEffects.lua.

------------------------------------------------------------------------
-- Dispel scan lives in GroupFrames\\MSUF_GF_AuraEffects.lua.

------------------------------------------------------------------------
-- Health color (GF-independent barMode, then global fallback)
-- Optional hp / hpMax parameters: when the caller (e.g. dispatchHealthFull)
-- already has fresh values, pass them to skip the GRADIENT-no-calc fallback's
-- duplicate UnitHealth/UnitHealthMax C-calls. nil/omitted Ã¢â€ â€™ fetch as before.
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit, hp, hpMax)
    if not f.health then return false end
    if f._msufSIHealthColorR then
        f.health:SetStatusBarColor(f._msufSIHealthColorR, f._msufSIHealthColorG, f._msufSIHealthColorB, 1)
        f._msufGFHCStamp = nil
        return true
    end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    local mode = c.hcMode

    if mode == "dark" then
        if f._msufGFHCStamp ~= "dark" then
            f._msufGFHCStamp = "dark"
            f.health:SetStatusBarColor(c.darkR, c.darkG, c.darkB, 1)
            return true
        end
        return false
    end
    if mode == "unified" then
        if f._msufGFHCStamp ~= "unified" then
            f._msufGFHCStamp = "unified"
            f.health:SetStatusBarColor(c.unifiedR, c.unifiedG, c.unifiedB, 1)
            return true
        end
        return false
    end
    if mode == "CLASS" and unit then
        local cls = f._msufGFClass
        if not cls then local _; _, cls = UnitClass(unit); f._msufGFClass = cls end
        if cls then
            if f._msufGFHCStamp == cls then return false end
            f._msufGFHCStamp = cls
            local fn = c.classFn
            if type(fn) == "function" then
                local r, g, b = fn(cls)
                if r then f.health:SetStatusBarColor(r, g, b, 1); return true end
            end
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1); return true end
        end
    end
    if mode == "GRADIENT" and unit then
        -- C-side path: ColorCurve + calculator Ã¢â€ â€™ fully secret-safe, zero Lua math
        local calc = f._msufHPCalc
        if calc and _gfGradientCurve then
            local color = calc:EvaluateCurrentHealthPercent(_gfGradientCurve)
            if color then
                local r, g, b = color:GetRGB()
                -- Secret-safe path: the curve result can carry secret values.
                -- Feed them straight into the C-side setter; do not quantize or
                -- otherwise touch them in Lua.
                f._msufGFGradRQ = nil
                f._msufGFGradGQ = nil
                f.health:SetStatusBarColor(r, g, b, 1)
                f._msufGFHCStamp = "gradient"
                return true
            end
        end
        -- Fallback: Lua-side (non-secret values only). Reuse caller-provided
        -- hp/hpMax if available Ã¢â‚¬â€ avoids redundant UnitHealth/UnitHealthMax
        -- calls when dispatchHealthFull already has fresh values.
        if hp == nil then hp = UnitHealth(unit) end
        if hpMax == nil then hpMax = UnitHealthMax(unit) end
        if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then
            if f._msufGFHCStamp ~= "grad_secret" then
                f._msufGFHCStamp = "grad_secret"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
                return true
            end
            return false
        end
        local hpN, hpMaxN = tonumber(hp), tonumber(hpMax)
        if hpN and hpMaxN and hpMaxN > 0 then
            local pct = hpN / hpMaxN
            local r = pct > 0.5 and (1 - (pct - 0.5) * 2) or 1
            local g = pct > 0.5 and 1 or (pct * 2)
            local rQ = math_floor(r * 255 + 0.5)
            local gQ = math_floor(g * 255 + 0.5)
            if f._msufGFGradRQ ~= rQ or f._msufGFGradGQ ~= gQ then
                f._msufGFGradRQ = rQ
                f._msufGFGradGQ = gQ
                f.health:SetStatusBarColor(r, g, 0, 1)
                return true
            end
        else
            if f._msufGFHCStamp ~= "grad_default" then
                f._msufGFHCStamp = "grad_default"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
                return true
            end
        end
        return false
    end
    if f._msufGFHCStamp ~= "custom" then
        f._msufGFHCStamp = "custom"
        f.health:SetStatusBarColor(c.customR, c.customG, c.customB, 1)
        return true
    end
    return false
end

local function ApplyHealthAlphaAfterColor(f, kind, colorChanged)
    if not f or not f.health or not GF.ApplyHealthBarAlpha then return end
    kind = kind or f._msufGFKind or "party"
    if f._msufGFHealthAlphaDynamic == true then
        GF.ApplyHealthBarAlpha(f, kind)
        f._msufGFHealthAlphaLast = nil
        f._msufGFHealthAlphaPreserveLast = nil
        return
    end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    local alpha = c and c.hpBarAlpha
    local preserve = c and c.alphaPreserveHPColor
    local conf
    if type(alpha) ~= "number" then
        conf = GF.GetConf(kind)
        alpha = (GF.GetEffectiveHealthAlpha and GF.GetEffectiveHealthAlpha(kind, conf)) or tonumber(conf and conf.hpBarAlpha) or 1
        preserve = conf and conf.alphaPreserveHPColor == true
    elseif preserve == nil then
        conf = GF.GetConf(kind)
        preserve = conf and conf.alphaPreserveHPColor == true
    end
    if alpha < 0.999 or preserve then
        if not colorChanged and f._msufGFHealthAlphaLast == alpha and f._msufGFHealthAlphaPreserveLast == preserve then
            return
        end
        GF.ApplyHealthBarAlpha(f, kind)
        f._msufGFHealthAlphaLast = alpha
        f._msufGFHealthAlphaPreserveLast = preserve
    else
        f._msufGFHealthAlphaLast = nil
        f._msufGFHealthAlphaPreserveLast = nil
    end
end

local function ApplyHealthColorWithAlpha(f, kind, unit, hp, hpMax)
    local colorChanged = ApplyHealthColor(f, kind, unit, hp, hpMax)
    ApplyHealthAlphaAfterColor(f, kind, colorChanged)
end

------------------------------------------------------------------------
-- Power color (secret-safe pToken)
------------------------------------------------------------------------
function GF._PowerBarActiveForUnit(f, unit, c)
    if not (f and f.power and unit and c and c.hasPowerElement and (c.powH or 0) > 0) then return false end
    local hidden = f._msufGFPowRoleHidden
    if (hidden == nil or f._msufGFPowRoleUnit ~= unit) and GF.GetEffectivePowerHeight then
        hidden = GF.GetEffectivePowerHeight(f._msufGFKind or "party", unit, nil) <= 0
        f._msufGFPowRoleHidden = hidden
        f._msufGFPowRoleUnit = unit
    end
    return not hidden
end

local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    if not (GF._PowerBarActiveForUnit and GF._PowerBarActiveForUnit(f, unit, c)) then
        if f.power:IsShown() then f.power:Hide() end
        return
    end
    local _, pToken = UnitPowerType(unit)
    -- Secret-safe: pToken may be secret in 12.0
    if issecretvalue and pToken and issecretvalue(pToken) then
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
        if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, f._msufGFKind or "party") end
        return
    end
    local r, g, b = ResolvePowerBarColor(pToken)
    f.power:SetStatusBarColor(r, g, b, 1)
    if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, f._msufGFKind or "party") end
end

-- Offline-hide lifecycle lives in GroupFrames\\MSUF_GF_StatusOffline.lua.
------------------------------------------------------------------------
-- Full update for a single frame (called on unit assignment + events)
------------------------------------------------------------------------
local dispatchOverlays, dispatchIncomingHeal, dispatchAbsorb, dispatchHealAbsorb
local _GF_DispatchOverlaysFromCalc

local function _GF_ShouldShowAbsorbTextureTestForFrame(f)
    if not _G.MSUF_AbsorbTextureTestMode then return false end
    if _G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown()) then return false end
    local testFn = _G.MSUF_ShouldShowAbsorbTextureTest
    if type(testFn) == "function" then
        return testFn(f, f and f._msufGFKind) and true or false
    end
    return true
end

local function UpdateAll(f, unit)
    if not f or not unit then return end
    if not _RuntimeEnabledForFrame(f) then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if f._msufGFOfflineActive and (_G.MSUF_InCombat ~= true or f._msufGFOfflineCombatAllowed)
        and GF.UpdateOfflineHiddenFrame and GF.UpdateOfflineHiddenFrame(f, unit)
    then
        return
    end
    GF.UpdateButton(f, unit)
    if _GF_ShouldApplyRangeOrFrameAlpha(f, c, f._msufGFKind or "party") then ApplyRangeFade(f, unit) end
    if c.needThreat then UpdateAggro(f, unit) end

    local _siOn = c.siEn
    if GF.UpdateSpellIndicators then
        if _siOn then GF.UpdateSpellIndicators(f, unit) else GF.HideSpellIndicators(f) end
    end

    if c.anyAuraGrp and GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
        GF.FinishAuraVisuals(f, unit, c)
    else
        if GF.UpdateFrameAuras and not f._msufGFAurasHidden then GF.UpdateFrameAuras(f, unit) end
        if not c.aurasOn then
            if _GF_ClearNativeSuppressedDispel and (
                f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
                or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive or f._gfPrivContainerOverlayID
            ) then
                _GF_ClearNativeSuppressedDispel(f, unit)
            end
        elseif c.nativeBlizzardDispelsSuppressCustom and not GF.DispelScanActive(c) then
            if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        elseif GF.DispelScanActive(c) then GF._UpdateDispel(f, unit) end
    end
    -- Debuff stripe (UpdateAll always does full refresh)
    if c.dsEn then
        f._msufGFHasAnyDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
        _GF_ApplyDebuffStripe(f)
    else
        -- Feature disabled Ã¢â‚¬â€ clear cached presence and hide stripe so the
        -- option toggle takes effect live (without it the visual lingers
        -- until the next aura event re-evaluates).
        f._msufGFHasAnyDebuff = false
        local stripe = f._msufGFDebuffStripe
        if stripe and stripe:IsShown() then stripe:Hide() end
    end
    UpdateTargetIndicator(f, unit)
    if c.statusTextEn or f._msufGFStatusState ~= 0 then UpdateStatusText(f, unit) end
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    local wasAbsorbTestMode = f._msufGFAbsorbTestActive
    if c.healPredEn or absorbTestMode or wasAbsorbTestMode then
        dispatchOverlays(f, unit)
        if wasAbsorbTestMode and not absorbTestMode then f._msufGFAbsorbTestActive = nil end
    end
    if c.roleStateEn or (f.roleIcon and f.roleIcon:IsShown()) then GF.UpdateRoleIcon(f, unit) end
    if c.raidMarkerEn or (f.raidIcon and f.raidIcon:IsShown()) then GF.UpdateRaidMarker(f, unit) end
    if c.leaderEn
        or (f.leaderIcon and f.leaderIcon:IsShown())
        or (f.assistIcon and f.assistIcon:IsShown())
    then
        GF.UpdateLeaderIcon(f, unit)
    end
    if c.summonEn or (f.summonIcon and f.summonIcon:IsShown()) then GF.UpdateSummonIcon(f, unit) end
    if c.resEn or (f.resurrectIcon and f.resurrectIcon:IsShown()) then GF.UpdateResurrectIcon(f, unit) end
    if c.phaseEn or (f.phaseIcon and f.phaseIcon:IsShown()) then GF.UpdatePhaseIcon(f, unit) end
    if c.groupNumberEn
        or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
        or (f.groupNumberText and f.groupNumberText:IsShown())
    then
        UpdateGroupNumber(f, unit)
    end
    if c.ciEn and GF.UpdateCornerIndicators and (c.ciAura or c.ciThreat or f._msufCIHasVisible) then
        if not c.ciAura then f._msufCILastAt = nil end
        GF.UpdateCornerIndicators(f, unit)
    end
    if c.paEn and GF.ApplyPrivateAuras then
        GF.ApplyPrivateAuras(f, unit)
    elseif GF.ClearPrivateAuras and (f._gfPrivAnchorIDs or f._gfPrivUnit or f._gfPrivContainerOverlayID) then
        GF.ClearPrivateAuras(f)
    end
    if f._gfPrivContainerOverlayID and GF.ApplyPrivateAuraContainerOverlay then
        GF.ApplyPrivateAuraContainerOverlay(f, unit, { containerOverlay = { enabled = false } })
    end
end

------------------------------------------------------------------------
-- Per-frame event dispatch table
------------------------------------------------------------------------

-- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
-- oUF-STYLE EVENT SPLIT: Each event only does what changed.
--
-- UNIT_HEALTH (10-50/s):      Bar + Text only. NO calculator, NO overlays.
-- UNIT_MAXHEALTH (~0.5/s):    Full chain (calc + bar + overlays + text).
-- UNIT_HEAL_PREDICTION:       Overlays only (incoming heals changed).
-- UNIT_ABSORB_AMOUNT_CHANGED: Overlays only (absorbs changed).
-- UNIT_HEAL_ABSORB_CHANGED:   Overlays only (heal absorbs changed).
--
-- This eliminates ~60% of Lua work per UNIT_HEALTH event.
-- Before: Calculator + SetMinMax + SetValue + Color + 3Ãƒâ€”Text
--         + 3Ãƒâ€”Overlay + HealthFade + StatusText = ~15 ops
-- After:  UnitHealth + SetValue + Text + StatusText = ~5 ops
-- Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Text dirty queue bridge. Runtime text queue lives in GroupFrames\\MSUF_GF_Text.lua.
------------------------------------------------------------------------
local function _gfMarkTextDirty(f)
    local fn = GF._MarkTextDirty or GF.MarkTextDirty
    if type(fn) == "function" and fn ~= _gfMarkTextDirty then return fn(f) end
end
GF._MarkTextDirty = GF._MarkTextDirty or _gfMarkTextDirty
GF._FlushDirtyText = GF._FlushDirtyText or function()
    local fn = GF.FlushDirtyText
    if type(fn) == "function" then return fn() end
end

-- LEAN PATH: UNIT_HEALTH (hottest: 10-50/s per unit, Ãƒâ€”40 in raids)
--
-- oUF-style: absolute minimum work per event.
--   1. UnitHealth(unit)             Ã¢â‚¬â€ 1 C-call (secret)
--   2. bar:SetValue(hp)             Ã¢â‚¬â€ 1 C-call (secret-safe)
--   3. Text/status refresh only when needed
--   4. Color (GRADIENT only)        Ã¢â‚¬â€ other modes stamp-gated elsewhere
--   5. Dirty flag for text+status   Ã¢â‚¬â€ coalesced flush next frame
--
-- REMOVED from hot path (vs. previous):
--   Ã¢â‚¬Â¢ UnitHealthMax()        Ã¢â‚¬â€ cached from UNIT_MAXHEALTH/init
--   Ã¢â‚¬Â¢ SetMinMaxValues()      Ã¢â‚¬â€ only on UNIT_MAXHEALTH
--   Ã¢â‚¬Â¢ 3Ãƒâ€”FormatHealthText     Ã¢â‚¬â€ coalesced text flush
--   Ã¢â‚¬Â¢ 6Ãƒâ€”issecretvalue        Ã¢â‚¬â€ coalesced text flush
--   Ã¢â‚¬Â¢ UpdateStatusText       Ã¢â‚¬â€ coalesced (AFK/DND cached; refreshed on flag events)
--   Ã¢â‚¬Â¢ Non-gradient health color Ã¢â‚¬â€ stamp-gated outside the lean path
------------------------------------------------------------------------
local function dispatchHealthLean(f, unit)
    local bar = f.health
    if not bar then return end
    local c = f._c

    -- 1 C-call Ã¢â€ â€™ secret value Ã¢â€ â€™ C-side SetValue
    local hp = UnitHealth(unit)
    local iss = issecretvalue
    local secretHP = iss and iss(hp)
    if not secretHP then
        if f._msufGFLastHealthValue == hp then
            if c and c.statusTextEn and hp == 0 then
                local state = f._msufGFStatusState or 0
                if not (state == 1 or state == 2 or state == 3) then
                    f._msufGFStatusDirty = true
                    _gfMarkTextDirty(f)
                end
            end
            return
        end
        f._msufGFLastHealthValue = hp
    else
        f._msufGFLastHealthValue = nil
    end

    if c then
        local sm = c.smooth
        if sm then bar:SetValue(hp, sm) else bar:SetValue(hp) end
    else
        bar:SetValue(hp)
    end
    if c and (c.alphaPreserveHPColor or f._msufGFMissingHPBg or f._msufGFPreserveAlphaState == true) and GF.SyncPreserveMissingHP then
        GF.SyncPreserveMissingHP(f, f._msufGFKind or "party", hp, f._msufGFCachedHpMax)
    end

    -- Dispel overlay health sync ("current health only" Ã¢â‚¬â€ secret-safe SetValue)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then dov:SetValue(hp) end

    -- Compiled fast text: pre-resolved closures call C-side directly.
    -- ~0.3ÃŽÂ¼s/slot (vs 7.5ÃŽÂ¼s with FormatHealthText). Zero mode dispatch,
    -- zero issecretvalue, zero string compare dedup.
    if c and c.anyFastText then
        local hm = f._msufGFCachedHpMax
        local fn = c.tlFn; if fn then fn(f.textLeftFS, unit, hp, hm) end
        fn = c.tcFn; if fn then fn(f.textCenterFS, unit, hp, hm) end
        fn = c.trFn; if fn then fn(f.textRightFS, unit, hp, hm) end
    end
    if c and (c.anySlowText or c.statusTextEn) then
        local slowTextDirty = false
        local nowT
        if c.anySlowText then
            local hpMax = f._msufGFCachedHpMax
            f._msufGFHealthTextValue = hp
            f._msufGFHealthTextMax = hpMax

            local comparable = not (secretHP or (iss and hpMax ~= nil and iss(hpMax)))
            if comparable then
                if f._msufGFHealthTextCmpValue ~= hp or f._msufGFHealthTextCmpMax ~= hpMax then
                    f._msufGFHealthTextCmpValue = hp
                    f._msufGFHealthTextCmpMax = hpMax
                    slowTextDirty = true
                end
            else
                f._msufGFHealthTextCmpValue = nil
                f._msufGFHealthTextCmpMax = nil
                nowT = nowT or GetTime()
                local nextAt = f._msufGFSecretTextNextAt or 0
                if nowT >= nextAt then
                    f._msufGFSecretTextNextAt = nowT + 0.05
                    slowTextDirty = true
                end
            end
        end

        local statusDirty = false
        if c.statusTextEn then
            local state = f._msufGFStatusState or 0
            if secretHP then
                nowT = nowT or GetTime()
                local nextAt = f._msufGFSecretStatusNextAt or 0
                if nowT >= nextAt then
                    f._msufGFSecretStatusNextAt = nowT + 0.20
                    statusDirty = true
                end
            elseif hp == 0 then
                -- Only enter the expensive status resolver when we are not
                -- already showing a dead/offline/ghost state. Repeated
                -- UNIT_HEALTH on dead raid members is otherwise pure churn.
                statusDirty = not (state == 1 or state == 2 or state == 3)
            else
                -- Health is back above zero: clear existing death states.
                statusDirty = (state == 1 or state == 2 or state == 3)
            end
            if statusDirty then f._msufGFStatusDirty = true end
        end
        if slowTextDirty or statusDirty then
            _gfMarkTextDirty(f)
        end
    elseif not c then
        f._msufGFStatusDirty = true
        _gfMarkTextDirty(f)
    end

    -- GRADIENT color only (all other modes stamp-gated elsewhere)
    if c and (c.hcGradient or f._msufSIHealthColorR) then
        if c.hcGradient then
            local calc = f._msufHPCalc
            if not calc and not _calcUnsupported then calc = _GF_EnsureCalc(f) end
            if calc then
                -- Keep the calculator in sync with the lean UNIT_HEALTH path so
                -- the gradient reflects the current bar value instead of a stale
                -- snapshot from the last full refresh.
                UnitGetDetailedHealPrediction(unit, "player", calc)
            end
        end
        ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", unit)
    end
end

------------------------------------------------------------------------
-- FULL PATH: UNIT_MAXHEALTH (rare Ã¢â‚¬â€ ~0.5/s)
-- Calculator Ã¢â€ â€™ bar + text + ALL overlays. Full refresh.
------------------------------------------------------------------------
local function dispatchHealthFull(f, unit)
    if not f.health then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    local calc = f._msufHPCalc
    if not calc and not _calcUnsupported then calc = _GF_EnsureCalc(f) end
    local hp, hpMax
    if calc then
        UnitGetDetailedHealPrediction(unit, "player", calc)
        hp    = calc:GetCurrentHealth()
        hpMax = calc:GetMaximumHealth()
    else
        hp    = UnitHealth(unit)
        hpMax = UnitHealthMax(unit)
    end

    f.health:SetMinMaxValues(0, hpMax)
    if c.smooth then f.health:SetValue(hp, c.smooth) else f.health:SetValue(hp) end
    f._msufGFCachedHpMax = hpMax
    if not (issecretvalue and issecretvalue(hp)) then
        f._msufGFLastHealthValue = hp
    else
        f._msufGFLastHealthValue = nil
    end
    f._msufGFHealthTextValue = hp
    f._msufGFHealthTextMax = hpMax
    if c and c.anySlowText then
        local iss = issecretvalue
        if not (iss and (iss(hp) or iss(hpMax))) then
            f._msufGFHealthTextCmpValue = hp
            f._msufGFHealthTextCmpMax = hpMax
        else
            f._msufGFHealthTextCmpValue = nil
            f._msufGFHealthTextCmpMax = nil
        end
    end
    if GF.SyncPreserveMissingHP then
        GF.SyncPreserveMissingHP(f, f._msufGFKind or "party", hp, hpMax)
    end

    -- Dispel overlay health sync ("current health only" Ã¢â‚¬â€ secret-safe)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then
        dov:SetMinMaxValues(0, hpMax)
        dov:SetValue(hp)
    end

    -- Color (full apply on maxHP change Ã¢â‚¬â€ handles unit-type transitions).
    -- Pass hp/hpMax through so the GRADIENT-no-calc fallback inside
    -- ApplyHealthColor doesn't re-fetch them.
    ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", unit, hp, hpMax)

    -- Text: prefer compiled closures (oUF-style C-side dispatch, ~0.3Ã‚Âµs/slot)
    -- over FormatHealthText (~7.5Ã‚Âµs/slot). Falls back to FormatHealthText only
    -- for unknown/uncompiled modes (c.anySlowText). Closures handle secret
    -- values C-side via SetText / SetFormattedText.
    if c.anyText then
        if c.anyFastText then
            local fn = c.tlFn; if fn and f.textLeftFS   then fn(f.textLeftFS,   unit, hp, hpMax) end
            fn      = c.tcFn; if fn and f.textCenterFS then fn(f.textCenterFS, unit, hp, hpMax) end
            fn      = c.trFn; if fn and f.textRightFS  then fn(f.textRightFS,  unit, hp, hpMax) end
        end
        if c.anySlowText then
            local iss = issecretvalue
            if f.textLeftFS and c.tlOn and not c.tlFn then
                local sval = GF.FormatHealthText(c.tl, hp, hpMax, c.delim, c.rev, unit)
                local cv = f._msufGFCachedTL
                if (iss and (iss(sval) or (cv ~= nil and iss(cv)))) or cv ~= sval then
                    f._msufGFCachedTL = (iss and iss(sval)) and nil or sval
                    f.textLeftFS:SetText(sval)
                end
            end
            if f.textCenterFS and c.tcOn and not c.tcFn then
                local sval = GF.FormatHealthText(c.tc, hp, hpMax, c.delim, c.rev, unit)
                local cv = f._msufGFCachedTC
                if (iss and (iss(sval) or (cv ~= nil and iss(cv)))) or cv ~= sval then
                    f._msufGFCachedTC = (iss and iss(sval)) and nil or sval
                    f.textCenterFS:SetText(sval)
                end
            end
            if f.textRightFS and c.trOn and not c.trFn then
                local sval = GF.FormatHealthText(c.tr, hp, hpMax, c.delim, c.rev, unit)
                local cv = f._msufGFCachedTR
                if (iss and (iss(sval) or (cv ~= nil and iss(cv)))) or cv ~= sval then
                    f._msufGFCachedTR = (iss and iss(sval)) and nil or sval
                    f.textRightFS:SetText(sval)
                end
            end
        end
    end
    UpdateStatusText(f, unit)

    -- Overlays from calculator
    local ihBar = (c and c.healPredEn == true) and f.incomingHealBar or nil
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    local wasAbsorbTestMode = f._msufGFAbsorbTestActive
    if absorbTestMode or wasAbsorbTestMode then
        _GF_DispatchOverlaysFromCalc(f, unit, calc, hp, hpMax)
        if wasAbsorbTestMode and not absorbTestMode then f._msufGFAbsorbTestActive = nil end
    elseif calc then
        if ihBar then
            if _GF_ApplyHealPredAnchor then _GF_ApplyHealPredAnchor(f) end
            local wasShown = ihBar.IsShown and ihBar:IsShown()
            local v = calc:GetIncomingHeals()
            if v ~= nil then ihBar:SetMinMaxValues(0, hpMax); ihBar:SetValue(v); if not ihBar:IsShown() then ihBar:Show() end
            else if ihBar:IsShown() then ihBar:Hide() end end
            if (wasShown and not ihBar:IsShown()) or ((not wasShown) and ihBar:IsShown()) then
                _GF_ApplyAbsorbAnchor(f)
            end
        end
        local abBar = f.absorbBar
        if abBar then
            if c.absorbEn then
                local v = calc:GetTotalDamageAbsorbs()
                if v ~= nil then abBar:SetMinMaxValues(0, hpMax); abBar:SetValue(v); if not abBar:IsShown() then abBar:Show() end
                else if abBar:IsShown() then abBar:Hide() end end
            else if abBar:IsShown() then abBar:Hide() end end
        end
        local haBar = f.healAbsorbBar
        if haBar then
            if c.healAbsorbEn ~= false then
                local v = calc:GetTotalHealAbsorbs()
                if v ~= nil then haBar:SetMinMaxValues(0, hpMax); haBar:SetValue(v); if not haBar:IsShown() then haBar:Show() end
                else if haBar:IsShown() then haBar:Hide() end end
            else if haBar:IsShown() then haBar:Hide() end end
        end
    else
        _GF_DispatchOverlaysFromCalc(f, unit, nil, hp, hpMax)
    end

    if c.hfEn and GF.ApplyHealthFade then
        GF.ApplyHealthFade(f, unit)
    end
end

------------------------------------------------------------------------
-- OVERLAY-ONLY PATH: UNIT_HEAL_PREDICTION / UNIT_ABSORB / UNIT_HEAL_ABSORB
-- Calculator Ã¢â€ â€™ overlay bars ONLY. No HP bar, no text, no color.
------------------------------------------------------------------------
function GF._ClearOverlayBar(bar)
    if not bar then return end
    if bar._msufGFOverlayMax ~= 1 then
        bar:SetMinMaxValues(0, 1)
        bar._msufGFOverlayMax = 1
    end
    if bar._msufGFOverlayValue ~= 0 then
        bar:SetValue(0)
        bar._msufGFOverlayValue = 0
    end
    if bar:IsShown() then bar:Hide() end
end

function GF._SetOverlayBarValue(bar, hpMax, value)
    if not bar then return end
    if value == nil then
        GF._ClearOverlayBar(bar)
        return
    end

    local iss = issecretvalue
    local maxValue = hpMax or 1
    if not (iss and iss(value)) then
        local n = tonumber(value) or 0
        if n <= 0 then
            GF._ClearOverlayBar(bar)
            return
        end
    end

    if iss and iss(maxValue) then
        bar:SetMinMaxValues(0, maxValue)
        bar._msufGFOverlayMax = nil
    elseif bar._msufGFOverlayMax ~= maxValue then
        bar:SetMinMaxValues(0, maxValue)
        bar._msufGFOverlayMax = maxValue
    end

    if iss and iss(value) then
        bar:SetValue(value)
        bar._msufGFOverlayValue = nil
    elseif bar._msufGFOverlayValue ~= value then
        bar:SetValue(value)
        bar._msufGFOverlayValue = value
    end
    if not bar:IsShown() then bar:Show() end
end

local function dispatchOverlaysOnly(f, unit)
    if not f.health then return end

    local c = f._c
    if not c then return end

    local ihBar = (c.healPredEn == true) and f.incomingHealBar or nil
    local abBar = f.absorbBar
    local haBar = f.healAbsorbBar
    local ihEnabled = ihBar ~= nil
    local abEnabled = abBar and c.absorbEn
    local haEnabled = haBar and c.healAbsorbEn ~= false
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if not (ihEnabled or abEnabled or haEnabled or absorbTestMode or f._msufGFAbsorbTestActive) then
        return
    end

    if absorbTestMode then
        _GF_DispatchOverlaysFromCalc(f, unit, nil)
        return
    end

    -- PERF: Same-frame dedup. UNIT_HEAL_PREDICTION + UNIT_ABSORB_AMOUNT_CHANGED
    -- + UNIT_HEAL_ABSORB_AMOUNT_CHANGED frequently fire in the same WoW frame
    -- (e.g. heal lands with absorb bubble). This function reads calc and
    -- renders ALL THREE overlay bars regardless of which event triggered it,
    -- so back-to-back calls in the same frame re-do identical work.
    -- GetTime() is frame-stable (constant within a frame, advances between).
    local nowT = GetTime()
    if f._msufGFOverlayT == nowT then return end
    f._msufGFOverlayT = nowT

    local calc = f._msufHPCalc
    if not calc and not _calcUnsupported then calc = _GF_EnsureCalc(f) end
    if not calc then
        -- No calculator: fall back to legacy per-overlay dispatch
        _GF_DispatchOverlaysFromCalc(f, unit, nil)
        return
    end

    UnitGetDetailedHealPrediction(unit, "player", calc)
    local hpMax = f._msufGFCachedHpMax or calc:GetMaximumHealth()

    if ihEnabled then
        if _GF_ApplyHealPredAnchor then _GF_ApplyHealPredAnchor(f) end
        local wasShown = ihBar.IsShown and ihBar:IsShown()
        GF._SetOverlayBarValue(ihBar, hpMax, calc:GetIncomingHeals())
        if (wasShown and not ihBar:IsShown()) or ((not wasShown) and ihBar:IsShown()) then
            _GF_ApplyAbsorbAnchor(f)
        end
    end
    if abEnabled then
        GF._SetOverlayBarValue(abBar, hpMax, calc:GetTotalDamageAbsorbs())
    end
    if haEnabled then
        GF._SetOverlayBarValue(haBar, hpMax, calc:GetTotalHealAbsorbs())
    end
end

------------------------------------------------------------------------
-- Health prediction overlays (absorb + incoming heal + heal absorb)
-- All 12.0 secret-safe: raw API values passed to C-side SetValue/SetMinMaxValues.
-- Show/hide: issecretvalue(val) Ã¢â€ â€™ secret = Show (non-nil means has value).
-- Colors read from global MSUF_DB.general (same keys as main UF overlays).
--
-- Absorb enable: read from MSUF_DB.general (tied to Bars menu).
-- Heal prediction enable: read from GF config resolver; local values are
-- honored only when the Bars scope override is active.
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Absorb settings resolver: reads from gf_party/gf_raid (if hlOverride),
-- falls through to MSUF_DB.general (tied to Bars menu).
------------------------------------------------------------------------
local function _GF_GetAbsorbSetting(kind, key)
    local dbKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
    local db = _G.MSUF_DB and _G.MSUF_DB[dbKey]
    if db and db.hlOverride and db[key] ~= nil then return db[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return nil
end

_GF_IsAbsorbEnabled = function(kind)
    -- All absorb settings resolve through _GF_GetAbsorbSetting which respects hlOverride.
    -- Without hlOverride, GF falls through to general (Bars menu shared scope).
    local mode = _GF_GetAbsorbSetting(kind, "absorbTextMode")
    if mode then
        mode = tonumber(mode)
        if mode then return (mode == 2 or mode == 3) end
    end
    local v = _GF_GetAbsorbSetting(kind, "enableAbsorbBar")
    if v ~= nil then return (v ~= false) end
    return true
end

local function _GF_NormalizeAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback
    if mode < 1 or mode > 5 then mode = fallback end
    return mode
end

_GF_ResolveHealPredAnchorMode = function(kind, conf)
    if conf and conf.hlOverride == true and conf.healPredAnchorMode ~= nil then
        return _GF_NormalizeAnchorMode(conf.healPredAnchorMode, 3)
    end
    return _GF_NormalizeAnchorMode(_GF_GetAbsorbSetting(kind, "healPredAnchorMode"), 3)
end

local function _GF_AnchorModeFollowsHP(mode)
    return mode == 3 or mode == 4
end

local function _GF_GetOrCreateHealPredClip(f, hpBar)
    local clip = f and f._msufGFHealPredFollowClip
    if not clip then
        clip = CreateFrame("Frame", nil, hpBar)
        clip:SetAllPoints(hpBar)
        if clip.SetClipsChildren then clip:SetClipsChildren(true) end
        f._msufGFHealPredFollowClip = clip
    else
        if clip.GetParent and clip:GetParent() ~= hpBar then clip:SetParent(hpBar) end
        clip:ClearAllPoints()
        clip:SetAllPoints(hpBar)
    end
    if clip.SetFrameLevel and hpBar.GetFrameLevel then
        clip:SetFrameLevel(hpBar:GetFrameLevel() + 1)
    end
    return clip
end

_GF_ApplyHealPredAnchor = function(f)
    local bar = f and f.incomingHealBar
    local hpBar = f and f.health
    if not (bar and hpBar) then return end
    local c = f._c
    local kind = f._msufGFKind or "party"
    local mode = (c and c.healPredAnchorMode) or _GF_ResolveHealPredAnchorMode(kind, GF.GetConf and GF.GetConf(kind))
    local hpReverse = hpBar.GetReverseFill and hpBar:GetReverseFill() and true or false

    if not _GF_AnchorModeFollowsHP(mode) then
        local reverse
        if mode == 1 then
            reverse = false
        elseif mode == 5 then
            reverse = not hpReverse
        else
            reverse = true
        end

        if bar._msufGFHealPredAnchorStamp == mode
            and bar._msufGFHealPredFollowActive ~= true
            and (mode ~= 5 or bar._msufGFHealPredRF == hpReverse)
        then
            return
        end

        bar._msufGFHealPredAnchorStamp = mode
        bar._msufGFHealPredFollowActive = nil
        bar._msufGFHealPredRF = (mode == 5) and hpReverse or nil
        bar._msufGFHealPredTex = nil
        bar._msufGFHealPredW = nil

        if f._msufGFHealPredFollowClip then f._msufGFHealPredFollowClip:Hide() end
        if bar.GetParent and bar:GetParent() ~= hpBar then bar:SetParent(hpBar) end
        bar:ClearAllPoints()
        bar:SetAllPoints(hpBar)
        if bar.SetReverseFill then bar:SetReverseFill(reverse and true or false) end
        if bar.SetFrameLevel and hpBar.GetFrameLevel then bar:SetFrameLevel(hpBar:GetFrameLevel() + 1) end
        return
    end

    if not hpBar.GetStatusBarTexture then return end
    local hpTex = hpBar:GetStatusBarTexture()
    if not hpTex then return end
    local w = hpBar.GetWidth and hpBar:GetWidth() or nil
    local isOverflow = (mode == 4)
    local clip = _GF_GetOrCreateHealPredClip(f, hpBar)
    local parent = isOverflow and (f.barGroup or f) or clip
    if isOverflow then clip:Hide() else clip:Show() end

    if bar._msufGFHealPredAnchorStamp == mode
        and bar._msufGFHealPredFollowActive == true
        and bar._msufGFHealPredRF == hpReverse
        and bar._msufGFHealPredTex == hpTex
        and bar._msufGFHealPredW == w
        and (not bar.GetParent or bar:GetParent() == parent)
    then
        return
    end

    bar._msufGFHealPredAnchorStamp = mode
    bar._msufGFHealPredFollowActive = true
    bar._msufGFHealPredRF = hpReverse
    bar._msufGFHealPredTex = hpTex
    bar._msufGFHealPredW = w

    if parent and bar.GetParent and bar:GetParent() ~= parent then bar:SetParent(parent) end
    bar:ClearAllPoints()
    if hpReverse then
        bar:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
        if bar.SetReverseFill then bar:SetReverseFill(true) end
    else
        bar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
        if bar.SetReverseFill then bar:SetReverseFill(false) end
    end
    if w and w > 0 then bar:SetWidth(w) end
    if bar.SetFrameLevel and hpBar.GetFrameLevel then bar:SetFrameLevel(hpBar:GetFrameLevel() + 1) end
end

------------------------------------------------------------------------
-- Absorb anchoring: apply SetReverseFill based on general.absorbAnchorMode
-- Mode 1: left anchor (fill LÃ¢â€ â€™R)   absorbReverse=false
-- Mode 2: right anchor (fill RÃ¢â€ â€™L)  absorbReverse=true  (DEFAULT)
-- Mode 3: follow HP edge (clipped to bar)
-- Mode 4: follow HP edge + overflow (extends beyond bar)
-- Mode 5: reverse from max         absorbReverse=true (normal HP bar)
------------------------------------------------------------------------
_GF_ApplyAbsorbAnchor = function(f)
    if not f or not f.health then return end
    local kind = f._msufGFKind or "party"
    local mode = tonumber(_GF_GetAbsorbSetting(kind, "absorbAnchorMode")) or 2

    local hpBar = f.health
    local hpReverse = hpBar.GetReverseFill and hpBar:GetReverseFill() and true or false

    -- Mode 3/4: follow current HP edge
    if mode == 3 or mode == 4 then
        local hpTex = hpBar:GetStatusBarTexture()
        if not hpTex then mode = 2 -- fallback
        else
            local w = hpBar:GetWidth()
            local absorbAnchorTex = hpTex
            local absorbChained = nil
            local ihBar = f.incomingHealBar
            if ihBar and ihBar.IsShown and ihBar:IsShown() and f._c and f._c.healPredEn == true then
                local healMode = (f._c and f._c.healPredAnchorMode)
                    or _GF_ResolveHealPredAnchorMode(kind, GF.GetConf and GF.GetConf(kind))
                if _GF_AnchorModeFollowsHP(healMode) then
                    local ihTex = ihBar.GetStatusBarTexture and ihBar:GetStatusBarTexture()
                    if ihTex then
                        absorbAnchorTex = ihTex
                        absorbChained = true
                    end
                end
            end
            if f._msufGFAbsorbAnchorStamp == mode and f._msufGFAbsorbFollowActive
               and f._msufGFAbsorbFollowRF == hpReverse
               and f._msufGFAbsorbFollowW == w
               and f._msufGFAbsorbFollowAnchorTex == absorbAnchorTex
               and f._msufGFAbsorbFollowChained == absorbChained then
                return
            end
            f._msufGFAbsorbAnchorStamp = mode
            f._msufGFAbsorbFollowActive = true
            f._msufGFAbsorbFollowRF = hpReverse
            f._msufGFAbsorbFollowW = w
            f._msufGFAbsorbFollowAnchorTex = absorbAnchorTex
            f._msufGFAbsorbFollowChained = absorbChained

            local isOverflow = (mode == 4)

            -- Clip frame (mode 3 only Ã¢â‚¬â€ prevents absorb extending beyond bar)
            local clip = f._msufAbsorbFollowClip
            if not clip then
                clip = CreateFrame("Frame", nil, hpBar)
                clip:SetAllPoints(hpBar)
                if clip.SetClipsChildren then clip:SetClipsChildren(true) end
                f._msufAbsorbFollowClip = clip
            else
                clip:ClearAllPoints()
                clip:SetAllPoints(hpBar)
            end
            clip:SetFrameLevel(hpBar:GetFrameLevel() + 2)
            clip:Show()

            -- Absorb: outward from HP edge (same direction as HP fill)
            if f.absorbBar then
                local absorbParent = isOverflow and (f.barGroup or f) or clip
                if f.absorbBar:GetParent() ~= absorbParent then
                    f.absorbBar:SetParent(absorbParent)
                end
                f.absorbBar:ClearAllPoints()
                if hpReverse then
                    f.absorbBar:SetPoint("TOPRIGHT", absorbAnchorTex, "TOPLEFT", 0, 0)
                    f.absorbBar:SetPoint("BOTTOMRIGHT", absorbAnchorTex, "BOTTOMLEFT", 0, 0)
                    f.absorbBar:SetReverseFill(true)
                else
                    f.absorbBar:SetPoint("TOPLEFT", absorbAnchorTex, "TOPRIGHT", 0, 0)
                    f.absorbBar:SetPoint("BOTTOMLEFT", absorbAnchorTex, "BOTTOMRIGHT", 0, 0)
                    f.absorbBar:SetReverseFill(false)
                end
                if w and w > 0 then f.absorbBar:SetWidth(w) end
                f.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
            end

            -- HealAbsorb: inward from HP edge (opposite direction)
            if f.healAbsorbBar then
                if f.healAbsorbBar:GetParent() ~= clip then
                    f.healAbsorbBar:SetParent(clip)
                end
                f.healAbsorbBar:ClearAllPoints()
                if hpReverse then
                    f.healAbsorbBar:SetPoint("TOPLEFT", hpTex, "TOPLEFT", 0, 0)
                    f.healAbsorbBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMLEFT", 0, 0)
                    f.healAbsorbBar:SetReverseFill(false)
                else
                    f.healAbsorbBar:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
                    f.healAbsorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
                    f.healAbsorbBar:SetReverseFill(true)
                end
                if w and w > 0 then f.healAbsorbBar:SetWidth(w) end
                f.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
            end
            return
        end
    end

    -- Mode 1/2/5: full overlay (restore from mode 3/4 if needed)
    -- Diff-gate: when no follow-restore is needed, skip work if (mode, hpReverse)
    -- match the cached stamp. Mirrors main UF MSUF_ApplyAbsorbAnchorMode parity.
    -- hpReverse only matters for mode 5 (it picks the fill direction); for mode
    -- 1 and 2 the reverse flags are constants, so the stamp alone suffices.
    local needRestore = f._msufGFAbsorbFollowActive and true or false
    if not needRestore
        and f._msufGFAbsorbAnchorStamp == mode
        and (mode ~= 5 or f._msufGFAbsorbFollowRF == hpReverse) then
        return
    end

    if needRestore then
        f._msufGFAbsorbFollowActive = nil
        if f._msufAbsorbFollowClip then f._msufAbsorbFollowClip:Hide() end
        -- Re-parent absorb bars back to health
        if f.absorbBar then
            f.absorbBar:SetParent(hpBar)
            f.absorbBar:ClearAllPoints()
            f.absorbBar:SetAllPoints(hpBar)
            f.absorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 2)
        end
        if f.healAbsorbBar then
            f.healAbsorbBar:SetParent(hpBar)
            f.healAbsorbBar:ClearAllPoints()
            f.healAbsorbBar:SetAllPoints(hpBar)
            f.healAbsorbBar:SetFrameLevel(hpBar:GetFrameLevel() + 3)
        end
    end

    local absorbReverse, healReverse
    if mode == 1 then
        absorbReverse = false
        healReverse   = true
    elseif mode == 5 then
        absorbReverse = not hpReverse
        healReverse   = hpReverse and true or false
    else
        -- Mode 2: right anchor (default)
        absorbReverse = true
        healReverse   = false
    end

    if f.absorbBar and f.absorbBar.SetReverseFill then
        f.absorbBar:SetReverseFill(absorbReverse and true or false)
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetReverseFill then
        f.healAbsorbBar:SetReverseFill(healReverse and true or false)
    end
    f._msufGFAbsorbAnchorStamp = mode
    f._msufGFAbsorbFollowRF    = (mode == 5) and hpReverse or nil
    f._msufGFAbsorbFollowW     = nil
    f._msufGFAbsorbFollowAnchorTex = nil
    f._msufGFAbsorbFollowChained = nil
end
------------------------------------------------------------------------
local function _GF_ReadOverlayColor(keyR, keyG, keyB, defR, defG, defB, defA)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local r, g, b = gen[keyR], gen[keyG], gen[keyB]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, defA
        end
    end
    return defR, defG, defB, defA
end

local function _GF_HideIncomingHealBar(f, bar)
    if not bar then return end
    local wasShown = bar:IsShown()
    bar:Hide()
    if wasShown then _GF_ApplyAbsorbAnchor(f) end
end

local function _GF_ShowIncomingHealBar(f, bar)
    if not bar then return end
    if not bar:IsShown() then
        bar:Show()
        _GF_ApplyAbsorbAnchor(f)
    end
end

dispatchIncomingHeal = function(f, unit, calc, hp, hpMax)
    local bar = f.incomingHealBar
    if not bar then return end
    -- PERF: use pre-cached healPredEn from BuildFrameCache (was GF.GetConf + DB read per call)
    local c = f._c
    if not (c and c.healPredEn == true) then
        if bar:IsShown() then
            GF._ClearOverlayBar(bar)
            _GF_ApplyAbsorbAnchor(f)
        end
        return
    end
    if _GF_ApplyHealPredAnchor then _GF_ApplyHealPredAnchor(f) end
    -- Test mode: fixed values (same as main UF preview)
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if absorbTestMode then
        f._msufGFAbsorbTestActive = true
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(20)
        _GF_ShowIncomingHealBar(f, bar)
        return
    end
    if not unit or not UnitExists(unit) then _GF_HideIncomingHealBar(f, bar); return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetIncomingHeals then
        val = calc:GetIncomingHeals()
    elseif UnitGetIncomingHeals then
        val = UnitGetIncomingHeals(unit)
    end
    if val == nil then _GF_HideIncomingHealBar(f, bar); return end
    local valSecret = issecretvalue and issecretvalue(val)
    if not valSecret then
        local n = tonumber(val) or 0
        if n <= 0 then _GF_HideIncomingHealBar(f, bar); return end
        local hpMaxSecret = issecretvalue and issecretvalue(hpMax)
        if not hpMaxSecret then
            if not hp then
                hp = (calc and calc.GetCurrentHealth) and calc:GetCurrentHealth() or UnitHealth(unit)
            end
            local hpSecret = issecretvalue and issecretvalue(hp)
            if not hpSecret then
                local missing = (tonumber(hpMax) or 0) - (tonumber(hp) or 0)
                if missing < 0 then missing = 0 end
                if n > missing then val = missing end
            end
        end
    end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    _GF_ShowIncomingHealBar(f, bar)
end

dispatchAbsorb = function(f, unit, calc, hpMax)
    local bar = f.absorbBar
    if not bar then return end
    -- Test mode: fixed values, no unit/secret dependency (same as main UF)
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if absorbTestMode then
        f._msufGFAbsorbTestActive = true
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(25)
        if not bar:IsShown() then bar:Show() end
        return
    end
    -- PERF: use pre-cached absorbEn from BuildFrameCache (was _GF_IsAbsorbEnabled per call)
    local c = f._c
    if not (c and c.absorbEn) then
        bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end
        return
    end
    if not unit or not UnitExists(unit) then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetTotalDamageAbsorbs then
        val = calc:GetTotalDamageAbsorbs()
    elseif UnitGetTotalAbsorbs then
        val = UnitGetTotalAbsorbs(unit)
    end
    if val == nil then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    if issecretvalue and issecretvalue(val) then
        if not bar:IsShown() then bar:Show() end
    else
        local want = (tonumber(val) or 0) > 0
        if want and not bar:IsShown() then bar:Show()
        elseif not want and bar:IsShown() then bar:Hide() end
    end
end

dispatchHealAbsorb = function(f, unit, calc, hpMax)
    local bar = f.healAbsorbBar
    if not bar then return end
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if absorbTestMode then
        f._msufGFAbsorbTestActive = true
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(15)
        if not bar:IsShown() then bar:Show() end
        return
    end
    -- PERF: use pre-cached healAbsorbEn from BuildFrameCache (was GF.GetConf per call)
    local c = f._c
    if c and c.healAbsorbEn == false then
        bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end
        return
    end
    if not unit or not UnitExists(unit) then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetTotalHealAbsorbs then
        val = calc:GetTotalHealAbsorbs()
    elseif UnitGetTotalHealAbsorbs then
        val = UnitGetTotalHealAbsorbs(unit)
    end
    if val == nil then bar:SetMinMaxValues(0, 1); bar:SetValue(0); if bar:IsShown() then bar:Hide() end; return end
    bar:SetMinMaxValues(0, hpMax)
    bar:SetValue(val)
    if issecretvalue and issecretvalue(val) then
        if not bar:IsShown() then bar:Show() end
    else
        local want = (tonumber(val) or 0) > 0
        if want and not bar:IsShown() then bar:Show()
        elseif not want and bar:IsShown() then bar:Hide() end
    end
end

_GF_DispatchOverlaysFromCalc = function(f, unit, calc, hp, hpMax)
    local c = f and f._c
    local ihBar = f and f.incomingHealBar
    if ihBar and ((c and c.healPredEn == true) or (ihBar.IsShown and ihBar:IsShown())) then
        dispatchIncomingHeal(f, unit, calc, hp, hpMax)
    end
    dispatchAbsorb(f, unit, calc, hpMax)
    dispatchHealAbsorb(f, unit, calc, hpMax)
end

dispatchOverlays = function(f, unit)
    local calc = _GF_EnsureCalc(f)
    if calc and unit and UnitExists(unit) then
        UnitGetDetailedHealPrediction(unit, "player", calc)
    end
    _GF_DispatchOverlaysFromCalc(f, unit, calc)
end

local function dispatchPower(f, unit)
    if not f.power then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if not c.hasPowerElement then return end
    local barActive = GF._PowerBarActiveForUnit and GF._PowerBarActiveForUnit(f, unit, c)
    if not barActive and f.power:IsShown() then
        f.power:Hide()
    end
    if not barActive and not c.anyPowerText then
        if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
        if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
        if f.powerTextRightFS then f.powerTextRightFS:Hide() end
        return
    end

    local pw = UnitPower(unit)
    if barActive then
        if c.powSmooth then f.power:SetValue(pw, c.powSmooth) else f.power:SetValue(pw) end
        if not f.power:IsShown() then f.power:Show() end
    elseif f.power:IsShown() then
        f.power:Hide()
    end

    -- Coalesced power text: dirty flag Ã¢â€ â€™ flush next frame
    if c.anyPowerText then
        local pwMax = f._msufGFCachedPwMax
        if pwMax == nil then
            pwMax = UnitPowerMax(unit)
            f._msufGFCachedPwMax = pwMax
        end
        f._msufGFPwTextValue = pw
        f._msufGFPwTextMax = pwMax

        local iss = issecretvalue
        local comparable = not (iss and (iss(pw) or iss(pwMax)))
        if comparable then
            if not f._msufGFPwTextDirty
                and f._msufGFPwTextCmpValue == pw
                and f._msufGFPwTextCmpMax == pwMax
            then
                return
            end
            f._msufGFPwTextCmpValue = pw
            f._msufGFPwTextCmpMax = pwMax
        else
            f._msufGFPwTextCmpValue = nil
            f._msufGFPwTextCmpMax = nil
        end

        if f._msufGFPwTextDirty then return end
        f._msufGFPwTextDirty = true
        _gfMarkTextDirty(f)
    end
end

-- UNIT_MAXPOWER: full power path (SetMinMaxValues + inline text)
local function dispatchPowerFull(f, unit)
    if not f.power then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if not c.hasPowerElement then return end
    local barActive = GF._PowerBarActiveForUnit and GF._PowerBarActiveForUnit(f, unit, c)
    if not barActive and f.power:IsShown() then
        f.power:Hide()
    end
    if not barActive and not c.anyPowerText then
        if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
        if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
        if f.powerTextRightFS then f.powerTextRightFS:Hide() end
        return
    end

    local pw    = UnitPower(unit)
    local pwMax = UnitPowerMax(unit)
    if barActive then
        f.power:SetMinMaxValues(0, pwMax)
        if c.powSmooth then f.power:SetValue(pw, c.powSmooth) else f.power:SetValue(pw) end
    end
    f._msufGFCachedPwMax = pwMax
    f._msufGFPwTextValue = pw
    f._msufGFPwTextMax = pwMax
    if barActive then
        if not f.power:IsShown() then f.power:Show() end
    elseif f.power:IsShown() then
        f.power:Hide()
    end

    -- Inline text on full path (rare event ~0.5/s)
    if c.anyPowerText then
        local iss = issecretvalue
        if not (iss and (iss(pw) or iss(pwMax))) then
            f._msufGFPwTextCmpValue = pw
            f._msufGFPwTextCmpMax = pwMax
        else
            f._msufGFPwTextCmpValue = nil
            f._msufGFPwTextCmpMax = nil
        end
        f._msufGFPwTextDirty = nil
        if f.powerTextLeftFS and c.ptlOn then
            local s = GF.FormatPowerText(c.ptl, pw, pwMax, c.pDelim, unit)
            f._msufGFCachedPTL = (iss and iss(s)) and nil or s
            f.powerTextLeftFS:SetText(s)
        end
        if f.powerTextCenterFS and c.ptcOn then
            local s = GF.FormatPowerText(c.ptc, pw, pwMax, c.pDelim, unit)
            f._msufGFCachedPTC = (iss and iss(s)) and nil or s
            f.powerTextCenterFS:SetText(s)
        end
        if f.powerTextRightFS and c.ptrOn then
            local s = GF.FormatPowerText(c.ptr, pw, pwMax, c.pDelim, unit)
            f._msufGFCachedPTR = (iss and iss(s)) and nil or s
            f.powerTextRightFS:SetText(s)
        end
    end
end

local function dispatchDisplayPower(f, unit)
    ApplyPowerColor(f, unit)
    dispatchPowerFull(f, unit)
end

local function dispatchName(f, unit)
    if not f.nameText then return end

    local kind = f._msufGFKind or "party"
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    if c and not c.nameEn then
        f._msufGFNameCacheKey = nil
        f._msufGFNameStyleKey = nil
        return
    end

    local guidFn = _G.UnitGUID
    local guid = guidFn and guidFn(unit)
    if guid and issecretvalue and issecretvalue(guid) then guid = nil end
    local cacheKey = guid or unit or ""
    local styleKey = (c and c.nameStyleKey) or kind
    local cachedName = f._msufGFNameText

    if f._msufGFNameCacheKey == cacheKey
        and f._msufGFNameStyleKey == styleKey
        and cachedName ~= nil
        and cachedName ~= ""
        and cachedName ~= _G.UNKNOWN
        and cachedName ~= _G.UNKNOWNOBJECT
    then
        return
    end

    local name = UnitName(unit) or ""
    local maxC = (c and c.nameMaxChars) or 0
    if maxC > 0 then
        name = GF.TruncateName(name, maxC, c and c.nameNoEllipsis, c and c.nameClipSide)
    end

    if f._msufGFNameText ~= name then
        f.nameText:SetText(name)
    end

    -- Cache class token (avoids C API call in ApplyHealthColor hot path)
    local _, classToken = UnitClass(unit)
    f._msufGFClass = classToken
    local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
    local colorKey = tostring(nr) .. "\001" .. tostring(ng) .. "\001" .. tostring(nb)
    if f._msufGFNameColorKey ~= colorKey then
        f.nameText:SetTextColor(nr, ng, nb, 1)
    end

    f._msufGFNameCacheKey = cacheKey
    f._msufGFNameStyleKey = styleKey
    f._msufGFNameText = name
    f._msufGFNameClass = classToken
    f._msufGFNameColorKey = colorKey
end

local UNIT_DISPATCH = {
    -- oUF-STYLE SPLIT: Each event does only what changed.
    UNIT_HEALTH                       = dispatchHealthLean,   -- Bar + Text ONLY (hottest: 10-50/s)
    UNIT_MAXHEALTH                    = dispatchHealthFull,   -- Full chain (rare: ~0.5/s)
    UNIT_HEAL_PREDICTION              = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_ABSORB_AMOUNT_CHANGED        = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED   = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_POWER_UPDATE                 = dispatchPower,
    UNIT_POWER_FREQUENT               = dispatchPower,
    UNIT_MAXPOWER                     = dispatchPowerFull,
    UNIT_DISPLAYPOWER                 = dispatchDisplayPower,
    UNIT_NAME_UPDATE                  = dispatchName,
    UNIT_CONNECTION                   = function(f, u)
        local wasOfflineHidden = f and f._msufGFOfflineHidden == true
        if f and f._msufGFOfflineActive and (_G.MSUF_InCombat ~= true or f._msufGFOfflineCombatAllowed)
            and GF.UpdateOfflineHiddenFrame and GF.UpdateOfflineHiddenFrame(f, u)
        then
            return
        end
        if wasOfflineHidden then
            UpdateAll(f, u)
            return
        end
        local c = f._c
        if c and c.statusTextEn then UpdateStatusText(f, u) end
        if c and _GF_ShouldApplyRangeOrFrameAlpha(f, c, f._msufGFKind or "party") then ApplyRangeFade(f, u) end
    end,
    UNIT_FLAGS                        = function(f, u)
        local c = f._c
        if c and c.statusTextEn and (c.statusAwayEn or (f._msufGFStatusState or 0) ~= 0) then
            UpdateStatusText(f, u, true)
        end
    end,
    UNIT_IN_RANGE_UPDATE              = function(f, u, inRange)
        local c = f._c
        if c and c.statusTextEn then
            local state = f._msufGFStatusState or 0
            if state ~= 0 then
                UpdateStatusText(f, u)
            elseif UnitHealth then
                local hp = UnitHealth(u)
                if not (issecretvalue and issecretvalue(hp)) and hp == 0 then
                    UpdateStatusText(f, u)
                end
            end
        end
        ApplyRangeFade(f, u, inRange)
    end,
    UNIT_AURA                         = function(f, u, updateInfo)
        dispatchAura(f, u, updateInfo)
    end,
    UNIT_THREAT_SITUATION_UPDATE      = function(f, u) UpdateAggro(f, u) end,
    UNIT_THREAT_LIST_UPDATE           = function(f, u) UpdateAggro(f, u) end,
    INCOMING_SUMMON_CHANGED           = function(f, u) GF.UpdateSummonIcon(f, u); GF.UpdateResurrectIcon(f, u) end,
    INCOMING_RESURRECT_CHANGED        = function(f, u) GF.UpdateResurrectIcon(f, u) end,
    -- UNIT_PHASE still does a full refresh for phase icon and
    -- name resolution (Unknown Ã¢â€ â€™ real). A full refresh is the only correct
    -- path; CTR/party-change events only refresh range fade.
    UNIT_PHASE                        = function(f, u)
        local c = f and f._c
        if c and c.phaseEn then UpdateAll(f, u) else ApplyRangeFade(f, u) end
    end,
    UNIT_CTR_OPTIONS                  = function(f, u) ApplyRangeFade(f, u) end,
    UNIT_OTHER_PARTY_CHANGED          = function(f, u) ApplyRangeFade(f, u) end,
}

_RuntimeEnabledForFrame = function(f)
    if not f then return false end
    if f._msufGFPreviewActive then return true end
    if f.unit and UnitExists and UnitExists(f.unit) and f.IsVisible and f:IsVisible() then
        return true
    end
    local kind = f._msufGFKind or (GF.frames and GF.frames[f]) or "party"
    return not (GF.IsKindEnabled and not GF.IsKindEnabled(kind))
end
GF._RuntimeEnabledForFrame = _RuntimeEnabledForFrame
GF._UnitDispatch = UNIT_DISPATCH

-- Group-frame unit/global event registration lives in GroupFrames\MSUF_GF_Events.lua.
-- Effects exports GF._UnitDispatch and GF._RuntimeEnabledForFrame for that module.
-- Mouseover highlight and tooltip runtime lives in GroupFrames\\MSUF_GF_TooltipMouseover.lua.
------------------------------------------------------------------------
-- Expose
------------------------------------------------------------------------
--- Combined highlight refresh (aggro + dispel + target) Ã¢â‚¬â€ called by
--- Borders.lua test mode buttons via _G.MSUF_GF_UpdateHighlight
local function UpdateHighlight(f, unit)
    unit = unit or f.unit
    if not unit then return end
    UpdateAggro(f, unit)
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    local dispelTest = _G.MSUF_BorderTestModesActive == true and _G.MSUF_DispelBorderTestMode == true
    if c and c.nativeBlizzardDispelsSuppressCustom and not GF.DispelScanActive(c) and not dispelTest then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
    elseif dispelTest or GF.DispelScanActive(c) then
        GF._UpdateDispel(f, unit)
    elseif _GF_ClearNativeSuppressedDispel then
        _GF_ClearNativeSuppressedDispel(f, unit)
    end
    UpdateTargetIndicator(f, unit)
end

_G.MSUF_GF_UpdateAll     = UpdateAll
_G.MSUF_GF_UpdateAggro   = UpdateAggro
_G.MSUF_GF_UpdateDispel   = GF._UpdateDispel
_G.MSUF_GF_UpdateHighlight = UpdateHighlight
_G.MSUF_GF_UpdateVisualDirty = function(f, unit, bits)
    if not f or not unit then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if f._msufGFOfflineActive and (_G.MSUF_InCombat ~= true or f._msufGFOfflineCombatAllowed)
        and GF.UpdateOfflineHiddenFrame and GF.UpdateOfflineHiddenFrame(f, unit)
    then
        return
    end

    -- Visual settings changed; avoid the legacy full UpdateAll unless the change
    -- actually needs max-health/power/layout-dependent recomputation. This keeps
    -- Options live-apply / preview refreshes from invoking aura scans for every
    -- frame on color/font/texture-only changes.
    local band = bit and bit.band or bit32 and bit32.band
    if not band or not bits or bits == 0x3F then
        return UpdateAll(f, unit)
    end

    if band(bits, 0x01) ~= 0 then -- DIRTY_GEOMETRY
        dispatchHealthFull(f, unit)
        dispatchPowerFull(f, unit)
        if c and c.healPredEn then dispatchOverlaysOnly(f, unit) end
    end

    if band(bits, 0x08) ~= 0 then -- DIRTY_COLOR
        ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", unit)
        ApplyPowerColor(f, unit)
        if c and _GF_ShouldApplyRangeOrFrameAlpha(f, c, f._msufGFKind or "party") then ApplyRangeFade(f, unit) end
    end

    if band(bits, 0x10) ~= 0 then -- DIRTY_BORDER
        if c and c.needThreat then UpdateAggro(f, unit) end
        if c and not c.aurasOn then
            if _GF_ClearNativeSuppressedDispel and (
                f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
                or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive or f._gfPrivContainerOverlayID
            ) then
                _GF_ClearNativeSuppressedDispel(f, unit)
            end
        elseif c and c.nativeBlizzardDispelsSuppressCustom and not GF.DispelScanActive(c) then
            if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        elseif GF.DispelScanActive(c) then GF._UpdateDispel(f, unit) end
        UpdateTargetIndicator(f, unit)
    end

    if band(bits, 0x04) ~= 0 or band(bits, 0x20) ~= 0 then -- FONT/LAYOUT
        -- Font/layout options can affect name truncation and name color.
        -- The v2 visual-dirty split avoided the legacy full UpdateAll path here,
        -- so explicitly refresh the name text to preserve live-apply for
        -- Group Frame Fonts > Name Shortening without reintroducing aura scans.
        dispatchName(f, unit)
        if c and (c.statusTextEn or f._msufGFStatusState ~= 0) then UpdateStatusText(f, unit) end
        if c and (c.roleStateEn or (f.roleIcon and f.roleIcon:IsShown())) then GF.UpdateRoleIcon(f, unit) end
        if c and (c.raidMarkerEn or (f.raidIcon and f.raidIcon:IsShown())) then GF.UpdateRaidMarker(f, unit) end
        if c and (
            c.leaderEn
            or (f.leaderIcon and f.leaderIcon:IsShown())
            or (f.assistIcon and f.assistIcon:IsShown())
        ) then
            GF.UpdateLeaderIcon(f, unit)
        end
        if (c and c.groupNumberEn)
            or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
            or (f.groupNumberText and f.groupNumberText:IsShown())
        then
            UpdateGroupNumber(f, unit)
        end
        if c and c.ciEn and GF.UpdateCornerIndicators and (c.ciAura or c.ciThreat or f._msufCIHasVisible) then
            if not c.ciAura then f._msufCILastAt = nil end
            GF.UpdateCornerIndicators(f, unit)
        end
        if c and c.paEn and GF.ApplyPrivateAuras then
            GF.ApplyPrivateAuras(f, unit)
        elseif GF.ClearPrivateAuras and (f._gfPrivAnchorIDs or f._gfPrivUnit or f._gfPrivContainerOverlayID) then
            GF.ClearPrivateAuras(f)
        end
    end
end
_G.MSUF_GF_UpdateTarget   = UpdateTargetIndicator
_G.MSUF_GF_UpdateStatus   = UpdateStatusText
_G.MSUF_GF_UpdateGroupNum = UpdateGroupNumber
_G.MSUF_GF_StopDispelGlow = _GF_StopDispelGlow

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Frame-retire cleanup lives in GroupFrames\\MSUF_GF_Cleanup.lua.
------------------------------------------------------------------------
GF.GetDispelColor     = GetDispelColor
GF.ResolveDispelColor = ResolveDispelColor

local function _GF_ForEachLiveGroupFrame(fn)
    if type(fn) ~= "function" then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f and f._msufIsGroupFrame and _RuntimeEnabledForFrame(f) then fn(f) end
        end
    elseif GF.frames then
        for f in pairs(GF.frames) do
            if f and f._msufIsGroupFrame and _RuntimeEnabledForFrame(f) then fn(f) end
        end
    end
end
GF.ForEachLiveGroupFrame = _GF_ForEachLiveGroupFrame

-- Dispel overlay: refresh all frames (called from Options when settings change)
_G.MSUF_GF_RefreshDispelOverlay = function()
    if not GF.frames then return end
    _GF_ForEachLiveGroupFrame(function(f)
        GF.BuildFrameCache(f)
        local c = f and f._c
        if f and f.unit and c and GF.DispelScanActive and GF.DispelScanActive(c) and GF._UpdateDispel then
            GF._UpdateDispel(f, f.unit)
        else
            _GF_ApplyDispelOverlay(f)
        end
    end)
end
-- Single-frame overlay apply (for Borders.lua test-mode cleanup)
_G.MSUF_GF_ApplyDispelOverlay = _GF_ApplyDispelOverlay

-- Debuff stripe: refresh all frames (called from Options when settings change)
_G.MSUF_GF_RefreshDebuffStripe = function()
    if not GF.frames then return end
    _GF_ForEachLiveGroupFrame(function(f)
        GF.BuildFrameCache(f)
        _GF_ApplyDebuffStripe(f)
    end)
end
_G.MSUF_GF_ApplyDebuffStripe = _GF_ApplyDebuffStripe

-- Diagnostic exports (target-click spike diagnosis)
_G.MSUF_GF_QuickBorderUpdate   = _GF_QuickBorderUpdate
_G.MSUF_GF_RefreshBorder        = _GF_RefreshBorder
_G.MSUF_GF_ApplyHLBorderStyle   = _applyHighlightBorderStyle
_G.MSUF_GF_BuildFrameCache      = GF.BuildFrameCache
_G.MSUF_GF_GlobalEventFrame     = GF._globalFrame

--- Refresh overlay bars (absorb + heal absorb + incoming heal) on all GF frames.
--- Called from Bars options when test mode or absorb settings change.
_G.MSUF_GF_RefreshOverlays = function()
    if not GF.frames then return end
    local absorbTestMayRun = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
    _GF_ForEachLiveGroupFrame(function(f)
        local c = f and f._c
        if c and c.healPredEn == true and _GF_ApplyHealPredAnchor then _GF_ApplyHealPredAnchor(f) end
        _GF_ApplyAbsorbAnchor(f)
        local u = f.unit
        if u then
            local wasAbsorbTestMode = f._msufGFAbsorbTestActive
            dispatchOverlays(f, u)
            if wasAbsorbTestMode and not (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(f)) then f._msufGFAbsorbTestActive = nil end
        elseif (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(f)) or f._msufGFAbsorbTestActive then
            dispatchIncomingHeal(f, nil)
            dispatchAbsorb(f, nil)
            dispatchHealAbsorb(f, nil)
            if not (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(f)) then f._msufGFAbsorbTestActive = nil end
        end
    end)
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local pf = list[i]
                if pf then
                    local c = pf._c
                    if c and c.healPredEn == true and _GF_ApplyHealPredAnchor then _GF_ApplyHealPredAnchor(pf) end
                    _GF_ApplyAbsorbAnchor(pf)
                    local u = pf.unit or pf._msufGFPreviewUnit
                    if u then
                        local wasAbsorbTestMode = pf._msufGFAbsorbTestActive
                        dispatchOverlays(pf, u)
                        if wasAbsorbTestMode and not (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(pf)) then pf._msufGFAbsorbTestActive = nil end
                    elseif (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(pf)) or pf._msufGFAbsorbTestActive then
                        dispatchIncomingHeal(pf, nil)
                        dispatchAbsorb(pf, nil)
                        dispatchHealAbsorb(pf, nil)
                        if not (absorbTestMayRun and _GF_ShouldShowAbsorbTextureTestForFrame(pf)) then pf._msufGFAbsorbTestActive = nil end
                    end
                end
            end
        end
    end
end
GF._ApplyHealthColor      = ApplyHealthColorWithAlpha
GF._ApplyHealPredAnchor   = _GF_ApplyHealPredAnchor
GF._ApplyAbsorbAnchor     = _GF_ApplyAbsorbAnchor
GF._IsAbsorbEnabled       = _GF_IsAbsorbEnabled
GF._ResolveHealPredAnchorMode = _GF_ResolveHealPredAnchorMode
GF._ReadOverlayColor      = _GF_ReadOverlayColor

-- Idle-diagnosis exports
_G.MSUF_GF_DispatchHealth  = dispatchHealthFull  -- Full refresh (for Options/manual use)
_G.MSUF_GF_DispatchPower   = dispatchPower
_G.MSUF_GF_DispatchAura    = dispatchAura
_G.MSUF_GF_DispatchName    = dispatchName
_G.MSUF_GF_DispatchOverlays = dispatchOverlays
_G.MSUF_GF_ApplyPowerColor = ApplyPowerColor
_G.MSUF_GF_OnEvent         = GF._OnUnitEvent
-- Exported diagnostic helper. Do not wire this into health/power hotpaths
-- without profiling and visual regression validation.
_G.MSUF_GF_PixelSnap       = _GF_PixelSnappedSetValue
