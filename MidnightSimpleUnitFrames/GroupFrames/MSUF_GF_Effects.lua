-- MSUF_GF_Effects.lua â€” Group Frames Phase 2: Events + Effects
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

-- C-side gradient color curve (redâ†’yellowâ†’green) for GRADIENT health color mode.
-- Evaluated via calc:EvaluateCurrentHealthPercent(curve) â€” fully secret-safe,
-- zero Lua arithmetic. Replaces 6 Lua ops (UnitHealth, UnitHealthMax,
-- issecretvalueÃ—2, tonumberÃ—2, division, conditional) with 1 C-call.
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

------------------------------------------------------------------------
-- COMPILED FAST-TEXT: oUF-style pre-resolved text functions.
-- Each GF text slot gets a closure at BuildFrameCache time that calls
-- C-side APIs directly. Zero mode dispatch, zero FormatHealthText,
-- zero issecretvalue dedup (C-side SetText handles it internally).
-- Cost: ~0.3Î¼s/slot vs ~7.5Î¼s/slot with FormatHealthText.
------------------------------------------------------------------------
local _ftHpPct     = _G.UnitHealthPercent
local _ftHpMissing = _G.UnitHealthMissing
local _ftScale100  = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local _ftAbbrShort = _G.AbbreviateNumbers
local _ftAbbrLong  = _G.BreakUpLargeNumbers
local _ftAbbrFB    = _G.AbbreviateLargeNumbers or _G.ShortenNumber

-- Build a compiled text function for a given mode.
-- Returns fn(fontString, unit, hp, hpMax) or nil for NONE.
-- All string ops on secret values produce secret strings â†’ C-side SetText.
local function _BuildTextFn(mode, abbrFn, delim, pctFmt)
    if not mode or mode == "NONE" then return nil end

    if mode == "PERCENT" then
        if _ftHpPct then
            return function(fs, unit)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then fs:SetFormattedText(pctFmt, p) end
            end
        end
        return nil
    end

    if mode == "CURRENT" then
        return function(fs, _, hp) fs:SetText(abbrFn(hp)) end
    end

    if mode == "MAX" then
        return function(fs, _, _, hm) fs:SetText(abbrFn(hm)) end
    end

    if mode == "DEFICIT" then
        if _ftHpMissing then
            return function(fs, unit)
                local m = _ftHpMissing(unit)
                local iss = issecretvalue
                if iss and iss(m) then
                    fs:SetText("-" .. abbrFn(m))
                    return
                end
                if m and m > 0 then fs:SetText("-" .. abbrFn(m)) else fs:SetText("") end
            end
        end
        return nil
    end

    if mode == "CURMAX" then
        return function(fs, _, hp, hm) fs:SetText(abbrFn(hp) .. delim .. abbrFn(hm)) end
    end
    if mode == "MAXCUR" then
        return function(fs, _, hp, hm) fs:SetText(abbrFn(hm) .. delim .. abbrFn(hp)) end
    end

    -- Combined percent modes: use SetFormattedText to avoid Lua arithmetic on
    -- secret UnitHealthPercent return. C-side formatting handles secrets safely.
    if mode == "CURPERCENT" then
        if _ftHpPct then
            local fmt = "%s" .. delim .. pctFmt
            return function(fs, unit, hp)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, abbrFn(hp), p)
                else
                    fs:SetText(abbrFn(hp))
                end
            end
        end
        return function(fs, _, hp) fs:SetText(abbrFn(hp)) end
    end
    if mode == "PERCENTCUR" then
        if _ftHpPct then
            local fmt = pctFmt .. delim .. "%s"
            return function(fs, unit, hp)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, p, abbrFn(hp))
                else
                    fs:SetText(abbrFn(hp))
                end
            end
        end
        return function(fs, _, hp) fs:SetText(abbrFn(hp)) end
    end

    if mode == "CURMAXPERCENT" then
        if _ftHpPct then
            local fmt = "%s" .. delim .. "%s " .. pctFmt
            return function(fs, unit, hp, hm)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, abbrFn(hp), abbrFn(hm), p)
                else
                    fs:SetText(abbrFn(hp) .. delim .. abbrFn(hm))
                end
            end
        end
        return function(fs, _, hp, hm) fs:SetText(abbrFn(hp) .. delim .. abbrFn(hm)) end
    end
    if mode == "PERCENTMAXCUR" then
        if _ftHpPct then
            local fmt = pctFmt .. " %s" .. delim .. "%s"
            return function(fs, unit, hp, hm)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, p, abbrFn(hm), abbrFn(hp))
                else
                    fs:SetText(abbrFn(hm) .. delim .. abbrFn(hp))
                end
            end
        end
        return function(fs, _, hp, hm) fs:SetText(abbrFn(hm) .. delim .. abbrFn(hp)) end
    end

    if mode == "MAXPERCENT" then
        if _ftHpPct then
            local fmt = "%s" .. delim .. pctFmt
            return function(fs, unit, _, hm)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, abbrFn(hm), p)
                else
                    fs:SetText(abbrFn(hm))
                end
            end
        end
        return function(fs, _, _, hm) fs:SetText(abbrFn(hm)) end
    end
    if mode == "PERCENTMAX" then
        if _ftHpPct then
            local fmt = pctFmt .. delim .. "%s"
            return function(fs, unit, _, hm)
                local p = _ftHpPct(unit, true, _ftScale100)
                if p then
                    fs:SetFormattedText(fmt, p, abbrFn(hm))
                else
                    fs:SetText(abbrFn(hm))
                end
            end
        end
        return function(fs, _, _, hm) fs:SetText(abbrFn(hm)) end
    end

    -- Unknown mode: fallback to FormatHealthText via flush
    return nil
end

-- Reverse map (applied when hpTextReverse is true)
local _FT_REVERSE = {
    CURPERCENT="PERCENTCUR", PERCENTCUR="CURPERCENT",
    CURMAX="MAXCUR", MAXCUR="CURMAX",
    CURMAXPERCENT="PERCENTMAXCUR", PERCENTMAXCUR="CURMAXPERCENT",
    MAXPERCENT="PERCENTMAX", PERCENTMAX="MAXPERCENT",
    PERCENTCURMAX="CURMAXPERCENT",
}

-- Resolve abbreviator function (once per BuildFrameCache, not per text call)
local function _ResolveAbbrFn()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local useShort = not gen or gen.useShortNumbers ~= false
    if useShort then
        return _ftAbbrShort or _ftAbbrFB or tostring
    else
        return _ftAbbrLong or _ftAbbrShort or _ftAbbrFB or tostring
    end
end

-- Resolve percent format string
local function _ResolvePctFmt()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local hide = gen and gen.hidePercentSymbol
    return hide and "%d" or "%d%%"
end

-- Build all 3 text slot functions for a frame cache.
-- Called from BuildFrameCache. Stored as c.tlFn / c.tcFn / c.trFn.
local function _BuildSlotFns(c)
    local abbrFn = _ResolveAbbrFn()
    local pctFmt = _ResolvePctFmt()
    local delim  = c.delim or " / "
    local rev    = c.rev

    local tl = c.tl or "NONE"
    local tc = c.tc or "NONE"
    local tr = c.tr or "NONE"
    if rev then
        tl = _FT_REVERSE[tl] or tl
        tc = _FT_REVERSE[tc] or tc
        tr = _FT_REVERSE[tr] or tr
    end

    c.tlFn = c.tlOn and _BuildTextFn(tl, abbrFn, delim, pctFmt) or nil
    c.tcFn = c.tcOn and _BuildTextFn(tc, abbrFn, delim, pctFmt) or nil
    c.trFn = c.trOn and _BuildTextFn(tr, abbrFn, delim, pctFmt) or nil
    -- Flag: any compiled text fn exists (fast skip in lean path)
    c.anyFastText = (c.tlFn or c.tcFn or c.trFn) and true or false
    -- Flag: any slot needs fallback (unknown mode)
    c.anySlowText = (c.tlOn and not c.tlFn) or (c.tcOn and not c.tcFn) or (c.trOn and not c.trFn) or false
end
local IsAltKeyDown     = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local UnitInRaid       = _G.UnitInRaid
local UnitInRange      = _G.UnitInRange
local IsInGroup        = _G.IsInGroup
local IsInRaid         = _G.IsInRaid
local UnitIsGhost      = _G.UnitIsGhost
local _smoothInterp    = _G.Enum and _G.Enum.StatusBarInterpolation
                         and _G.Enum.StatusBarInterpolation.ExponentialEaseOut

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
local _GF_IsAbsorbEnabled

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

------------------------------------------------------------------------
-- Highlight value resolver: Bars hl* keys â†’ old GF conf key fallback
-- Bars system uses hlAggroEnabled/aggroOutlineMode, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- Single-pass resolution: conf.hlOverride â†’ general â†’ conf[fallback]
------------------------------------------------------------------------
local _HL_FALLBACK = {
    hlAggroEnabled  = "aggroEnabled",
    hlAggroColorR   = "aggroR",
    hlAggroColorG   = "aggroG",
    hlAggroColorB   = "aggroB",
    hlAggroMode     = "aggroMode",
    hlDispelEnabled = "dispelEnabled",
    hlTargetEnabled = "targetIndicator",
    hlTargetColorR  = "targetR",
    hlTargetColorG  = "targetG",
    hlTargetColorB  = "targetB",
}

local _HL_OUTLINE_MODE = {
    hlAggroEnabled  = "aggroOutlineMode",
    hlDispelEnabled = "dispelOutlineMode",
}

local function OutlineModeToEnabled(mode)
    if mode == nil then return nil end
    if mode == true or mode == false then return mode end
    local n = tonumber(mode)
    if n ~= nil then return n == 1 end
    return nil
end

local function HLVal(kind, key)
    local conf = GF.GetConf(kind)
    -- Priority 1: GF-local override
    local modeKey = _HL_OUTLINE_MODE[key]
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if modeKey then
        if conf.hlOverride then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
            if conf[key] ~= nil then
                enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
                return conf[key]
            end
        end
        if gen then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
            if gen[key] ~= nil then
                enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
                return gen[key]
            end
        end
    elseif conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
    end
    if not modeKey and gen then
        if gen[key] ~= nil then return gen[key] end
    end
    -- Priority 3: legacy GF conf fallback
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[fb])
            if enabled ~= nil then return enabled end
        end
        return conf[fb]
    end
    return nil
end

local function HLValCached(conf, gen, key)
    local modeKey = _HL_OUTLINE_MODE[key]
    if modeKey then
        if conf.hlOverride then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
            if conf[key] ~= nil then
                enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
                return conf[key]
            end
        end
        if gen then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
            if gen[key] ~= nil then
                enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
                return gen[key]
            end
        end
    elseif conf.hlOverride then
        if conf[key] ~= nil then return conf[key] end
    end
    if not modeKey and gen then
        if gen[key] ~= nil then return gen[key] end
    end
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[fb])
            if enabled ~= nil then return enabled end
        end
        return conf[fb]
    end
    return nil
end

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

local function GetDispelColor(dispelName)
    -- DB per-type color takes priority (Colors > Dispel panel)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and type(dispelName) == "string" then
        local r = gen["dispelType" .. dispelName .. "R"]
        if type(r) == "number" then
            return r, gen["dispelType" .. dispelName .. "G"], gen["dispelType" .. dispelName .. "B"]
        end
    end
    -- Hardcoded fallback
    local c = DISPEL_COLORS[dispelName]
    if c then return c[1], c[2], c[3] end
    -- Blizzard color objects
    local obj = _G["DEBUFF_TYPE_" .. (dispelName or ""):upper() .. "_COLOR"]
    if obj then
        if obj.GetRGB then return obj:GetRGB() end
        if obj.r then return obj.r, obj.g, obj.b end
    end
    return nil
end

local function GetReadableDispelTypeName(dispelName)
    if dispelName == nil then return nil end
    if issecretvalue and issecretvalue(dispelName) then return nil end
    if type(dispelName) ~= "string" or dispelName == "" or dispelName == "None" or dispelName == "DISPELLABLE" then
        return nil
    end
    return dispelName
end

local function ExtractColorRGB(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b
    end
    if colorObj.GetRGBA then
        local rr, gg, bb = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb end
    end
    return nil
end

local function ExtractColorRGBA(colorObj)
    if not colorObj then return nil end
    if colorObj.r ~= nil then
        return colorObj.r, colorObj.g, colorObj.b, colorObj.a or 1
    end
    if colorObj.GetRGBA then
        local rr, gg, bb, aa = colorObj:GetRGBA()
        if rr ~= nil then return rr, gg, bb, aa end
    end
    if colorObj.GetRGB then
        local rr, gg, bb = colorObj:GetRGB()
        if rr ~= nil then return rr, gg, bb, 1 end
    end
    return nil
end

------------------------------------------------------------------------
-- Secret-safe dispel color resolution.
--
-- SINGLE mode â†’ plain (r,g,b) triplet from the Colors panel.
-- TYPE mode   â†’ a *Color object* from C_UnitAuras.GetAuraDispelTypeColor.
--               The Color object carries secret-safe RGBA that can ONLY be
--               applied via texture:SetVertexColor(color:GetRGBA()). It
--               MUST NOT be unpacked into Lua locals and fed to
--               CreateColor / SetGradient / arithmetic â€” that taints the
--               values and breaks everything but flat fills (which is the
--               "only single-color works" bug in Beta 4/5).
--
-- Returns (colorObj, r, g, b):
--   colorObj ~= nil  â†’ TYPE mode resolved via curve. Apply via
--                      tex:SetVertexColor(colorObj:GetRGBA())
--   colorObj == nil  â†’ SINGLE/fallback. Use (r, g, b) directly.
------------------------------------------------------------------------
local function ResolveDispelColorObj(f, dispelName)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local mode = gen and gen.hlDispelColorMode or "SINGLE"
    local fallbackType = GetReadableDispelTypeName(dispelName)

    if mode ~= "TYPE" then
        local r, g, b
        if gen then
            r = gen.hlDispelColorR or gen.dispelBorderColorR
            g = gen.hlDispelColorG or gen.dispelBorderColorG
            b = gen.hlDispelColorB or gen.dispelBorderColorB
        end
        return nil, r or 0.25, g or 0.75, b or 1.00
    end

    -- TYPE mode: resolve Color object via shared dispel color curve.
    local CUA   = _G.C_UnitAuras
    local unit  = f and f.unit
    local curve = GF and GF._sharedDispelColorCurve

    if CUA and CUA.GetAuraDispelTypeColor and unit and curve then
        local cached = f and f._msufGFDispelColorObj
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        if cached and (f._msufGFDispelColorRev or 0) == colorRev then
            return cached
        end

        local aid = f and f._msufGFDispelAuraID
        if aid then
            local color = CUA.GetAuraDispelTypeColor(unit, aid, curve)
            if color then
                if f then
                    f._msufGFDispelColorObj = color
                    f._msufGFDispelColorRev = colorRev
                end
                return color
            end
        end

        -- Grid2 path: query the top dispellable aura directly via GetAuraDataByIndex.
        local aura = CUA.GetAuraDataByIndex and CUA.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if aura and aura.auraInstanceID then
            if f then f._msufGFDispelAuraID = aura.auraInstanceID end
            fallbackType = fallbackType or GetReadableDispelTypeName(aura.dispelName)
            local color = CUA.GetAuraDispelTypeColor(unit, aura.auraInstanceID, curve)
            if color then
                if f then
                    f._msufGFDispelColorObj = color
                    f._msufGFDispelColorRev = colorRev
                end
                return color
            end
        end

        -- Recovery fallback for clients where GetAuraDataByIndex on this filter misbehaves.
        if CUA.GetAuraSlots and CUA.GetAuraDataBySlot then
            local _, slot = CUA.GetAuraSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1)
            local auraBySlot = slot and CUA.GetAuraDataBySlot(unit, slot)
            if auraBySlot and auraBySlot.auraInstanceID then
                if f then f._msufGFDispelAuraID = auraBySlot.auraInstanceID end
                fallbackType = fallbackType or GetReadableDispelTypeName(auraBySlot.dispelName)
                local color = CUA.GetAuraDispelTypeColor(unit, auraBySlot.auraInstanceID, curve)
                if color then
                    if f then
                        f._msufGFDispelColorObj = color
                        f._msufGFDispelColorRev = colorRev
                    end
                    return color
                end
            end
        end
    end

    -- TYPE fallback: use the known dispel school if we have it, otherwise
    -- fall back to the neutral palette.
    if fallbackType then
        local fr, fg, fb = GetDispelColor(fallbackType)
        if fr then return nil, fr, fg, fb end
    end
    return nil, 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Legacy wrapper: keeps (r, g, b) shape for non-overlay callers (glow).
-- Glow APIs don't take a Color object, so we accept a *minor* loss of
-- secret-safety here â€” values feed into LCG's color table which is
-- only read by C-side SetVertexColor downstream, so it's still safe
-- in practice.
------------------------------------------------------------------------
local function ResolveDispelColor(dispelName, f)
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelName)
    if colorObj then
        local rr, gg, bb = ExtractColorRGB(colorObj)
        if rr ~= nil then return rr, gg, bb end
    end
    if r then return r, g, b end
    if type(dispelName) == "string" and dispelName ~= "DISPELLABLE" then
        local dr, dg, db = GetDispelColor(dispelName)
        if dr then return dr, dg, db end
    end
    return 0.25, 0.75, 1.00
end

------------------------------------------------------------------------
-- Dispel glow helpers (GF) â€” zero-alloc color table reuse
------------------------------------------------------------------------
local _gfGlowColor = { 0, 0, 0, 1 }

local function _GF_StartDispelGlow(f, r, g, b)
    local kind = f._msufGFKind or "party"
    local blizzardOwnsThisScope = false
    local blocksGlow = _G.MSUF_GroupBlizzardAuraRenderingBlocksDispelGlow
    if type(blocksGlow) == "function" then
        blizzardOwnsThisScope = blocksGlow(kind) == true
    end
    if not LCG or blizzardOwnsThisScope or not HLVal(kind, "hlDispelGlowEnabled") then
        f._msufGFDispelGlowActive = nil
        local offAnchor = f._msufGFDispelGlowAnchor
        f._msufGFDispelGlowAnchor = nil
        f._msufGFDispelGlowStyle = nil
        if LCG then
            if offAnchor then
                LCG.PixelGlow_Stop(offAnchor, "msufDispel")
                LCG.AutoCastGlow_Stop(offAnchor, "msufDispel")
                LCG.ProcGlow_Stop(offAnchor, "msufDispel")
            end
            local offBorder = f._msufGFHighlightBorder
            if offBorder and offBorder ~= offAnchor then
                LCG.PixelGlow_Stop(offBorder, "msufDispel")
                LCG.AutoCastGlow_Stop(offBorder, "msufDispel")
                LCG.ProcGlow_Stop(offBorder, "msufDispel")
            end
            if f ~= offAnchor and f ~= offBorder then
                LCG.PixelGlow_Stop(f, "msufDispel")
                LCG.AutoCastGlow_Stop(f, "msufDispel")
                LCG.ProcGlow_Stop(f, "msufDispel")
            end
        end
        return
    end
    local anchor = f._msufGFHighlightBorder or f
    local style = HLVal(kind, "hlDispelGlowStyle") or "PIXEL"
    local oldAnchor = f._msufGFDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or f._msufGFDispelGlowStyle ~= style) then
        LCG.PixelGlow_Stop(oldAnchor, "msufDispel")
        LCG.AutoCastGlow_Stop(oldAnchor, "msufDispel")
        LCG.ProcGlow_Stop(oldAnchor, "msufDispel")
    end
    if anchor ~= f then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
    _gfGlowColor[1], _gfGlowColor[2], _gfGlowColor[3] = r, g, b
    local lines = tonumber(HLVal(kind, "hlDispelGlowLines")) or 8
    local freq  = tonumber(HLVal(kind, "hlDispelGlowFrequency")) or 0.25
    local thick = tonumber(HLVal(kind, "hlDispelGlowThickness")) or 2
    if style == "AUTOCAST" then
        LCG.AutoCastGlow_Start(anchor, _gfGlowColor, lines, freq, nil, nil, nil, "msufDispel")
    elseif style == "PROC" then
        LCG.ProcGlow_Start(anchor, { color = _gfGlowColor, key = "msufDispel" })
    else
        LCG.PixelGlow_Start(anchor, _gfGlowColor, lines, freq, nil, thick, nil, nil, nil, "msufDispel")
    end
    f._msufGFDispelGlowActive = true
    f._msufGFDispelGlowAnchor = anchor
    f._msufGFDispelGlowStyle = style
end

local function _GF_StopDispelGlow(f)
    if not f then return end
    f._msufGFDispelGlowActive = nil
    local anchor = f._msufGFDispelGlowAnchor
    f._msufGFDispelGlowAnchor = nil
    f._msufGFDispelGlowStyle = nil
    if not LCG then return end
    if anchor then
        LCG.PixelGlow_Stop(anchor, "msufDispel")
        LCG.AutoCastGlow_Stop(anchor, "msufDispel")
        LCG.ProcGlow_Stop(anchor, "msufDispel")
    end

    local border = f._msufGFHighlightBorder
    if border and border ~= anchor then
        LCG.PixelGlow_Stop(border, "msufDispel")
        LCG.AutoCastGlow_Stop(border, "msufDispel")
        LCG.ProcGlow_Stop(border, "msufDispel")
    end
    if f ~= anchor and f ~= border then
        LCG.PixelGlow_Stop(f, "msufDispel")
        LCG.AutoCastGlow_Stop(f, "msufDispel")
        LCG.ProcGlow_Stop(f, "msufDispel")
    end
end

------------------------------------------------------------------------
-- Debuff stripe: presence callback (must be before dispatchAura)
------------------------------------------------------------------------
local _QUESTION_MARK_ICON = 136243
local _PADLOCK_ICON = 134400
local _dsPresenceResult = false
local _dsPresenceAF = nil
local _dsPresenceBLHash = nil
local _FrameHasStripeDebuff

local function _DecodeStripeAuraIconFileID(icon)
    if icon == nil then return 0 end
    if issecretvalue and issecretvalue(icon) == true then return 0 end
    return tonumber(icon) or 0
end

local function _dsPresenceCallback(aura)
    if not aura then return false end

    local af = _dsPresenceAF
    local blHash = _dsPresenceBLHash
    if blHash and af then
        local sid = af.DecodeSpellId(aura)
        if af.IsBlacklisted(sid, blHash, aura) then
            return false
        end
    end

    local iconFileID = _DecodeStripeAuraIconFileID(aura.icon)
    if iconFileID == _QUESTION_MARK_ICON or iconFileID == _PADLOCK_ICON then
        return false
    end

    _dsPresenceResult = true
    return true  -- stop iteration
end

------------------------------------------------------------------------
-- Forward declarations (defined later in file)
local _GF_RefreshBorder
local _GF_ApplyDispelOverlay
local _GF_ApplyDebuffStripe
local _GF_ClearNativeSuppressedDispel

------------------------------------------------------------------------
-- UNIT_AURA: per-frame dispatch with burst-dedup (A2 P2 pattern)
-- Fast-paths (update-only 16Âµs, remove-only-not-displayed) still fire
-- instantly. Full pipeline is gated: first event runs immediately,
-- subsequent same-frame events within 20ms are skipped.
-- Zero steady-state alloc: clear-callback allocated once per frame.
------------------------------------------------------------------------
-- Legacy _After0 removed from runtime hot paths; use central scheduler helpers above.

------------------------------------------------------------------------
-- PERF: Global per-frame budget for full aura scans.
-- AoE heal/damage â†’ 20 UNIT_AURA events in same frame â†’ 20 Ã— 138Âµs = 2.8ms spike.
-- Budget limits full scans to 8 per frame. Excess deferred to next frame via C_Timer.After(0).
-- Max spike capped to 8 Ã— 138Âµs â‰ˆ 1.1ms.
------------------------------------------------------------------------
local _GF_AURA_BUDGET_MAX = 8
local _gfAuraBudget = 0
local _gfAuraDirtyPending = false
local _gfAuraBudgetFrame = 0  -- GetTime of last budget reset
local _gfAuraDirtyQueue = {}
local _gfAuraDirtyQueued = {}
local _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0

local function _gfQueueAuraDirty(f)
    if not f then return end
    f._msufGFAuraDirty = true
    if not _gfAuraDirtyQueued[f] then
        _gfAuraDirtyQueued[f] = true
        _gfAuraDirtyTail = _gfAuraDirtyTail + 1
        _gfAuraDirtyQueue[_gfAuraDirtyTail] = f
    end
end

-- Forward-declared; assigned after dispatchAura is defined.
local _gfFlushDirtyAuras
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    if GF.SpellIndicatorsUnitAuraRelevant then
        return GF.SpellIndicatorsUnitAuraRelevant(f, f and f.unit, f and f._msufGFKind or "party", updateInfo)
    end

    local added = updateInfo.addedAuras
    if added and #added > 0 then
        return true
    end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function NativeAuraContainerReady(f, unit)
    local container = f and f._msufGFNativeAuras
    if not (container and container._msufNativeAuraAnchorID) then return false end
    local Native = ns and ns.MSUF_AuraNative
    local effectiveUnit = Native and Native.ResolveUnitToken and Native.ResolveUnitToken(unit) or unit
    return container._msufNativeAuraUnit == effectiveUnit
end

function GF.FinishAuraVisuals(f, unit, c, updateInfo)
    if not (f and c) then return end
    if c.nativeBlizzardDispels then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
    else
        local mergedDispel = f._msufGFMergedDispel
        local prevDispel = f._msufGFDispelType
        local dispelAid = f._msufGFDispelAuraID
        local prevAid = f._msufGFPrevDispelAuraID
        local colorRev = _G.MSUF_ColorStyleRevision or 0
        local prevColorRev = f._msufGFColorStyleRevision or 0
        if mergedDispel ~= prevDispel or dispelAid ~= prevAid or colorRev ~= prevColorRev then
            f._msufGFDispelType = mergedDispel
            f._msufGFPrevDispelAuraID = dispelAid
            f._msufGFColorStyleRevision = colorRev
            _GF_RefreshBorder(f, unit)
            _GF_ApplyDispelOverlay(f)
        end
    end

    if c.dsEn then
        local scanStripe = not updateInfo or updateInfo.isFullUpdate or f._msufGFHasAnyDebuff == nil
        if not scanStripe then
            local added = updateInfo.addedAuras
            if added and #added > 0 then
                scanStripe = true
            else
                local removed = updateInfo.removedAuraInstanceIDs
                scanStripe = removed and #removed > 0
            end
        end
        if scanStripe then
            local hadDebuff = f._msufGFHasAnyDebuff or false
            local hasDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
            f._msufGFHasAnyDebuff = hasDebuff
            if hasDebuff ~= hadDebuff then
                _GF_ApplyDebuffStripe(f)
            end
        end
    end

    if GF.UpdateCornerIndicators and c.ciAura then
        GF.UpdateCornerIndicators(f, unit)
    end
end

local function dispatchAura(f, unit, updateInfo)
    local c = f._c
    if not c then return end
    local kind = f._msufGFKind or "party"
    -- PERF: use pre-cached flags from BuildFrameCache (was GF.GetConf per event)
    local aurasOn = c.anyAuraGrp
    local siRefresh = c.siEn and SpellIndicatorsNeedRefresh(f, updateInfo) or false

    -- PERF: CornerIndicators only care about aura add/remove, not duration/stack
    -- updates. Skip CI when the event is a pure update (saves ~300ms/min in raids).
    local ciRelevant = not updateInfo or updateInfo.isFullUpdate
        or (updateInfo.addedAuras and #updateInfo.addedAuras > 0)
        or (updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0)

    if not aurasOn then
        local dispelChanged, dispelRelevant
        if c.dispelScan and GF._playerCanDispel then
            -- EQoL dirty-flag: only rescan when dispel state may have changed
            local needDispelScan = false
            if not updateInfo or updateInfo.isFullUpdate then
                needDispelScan = true
            else
                local added = updateInfo.addedAuras
                if added and #added > 0 then needDispelScan = true end
                if not needDispelScan then
                    local removed = updateInfo.removedAuraInstanceIDs
                    if removed and #removed > 0 then
                        local trackedAid = f._msufGFDispelAuraID
                        if not trackedAid then
                            -- No tracked dispel â€” new removals might reveal nothing, but
                            -- added check above covers new dispels. Skip.
                        else
                            -- Check if OUR tracked dispel aura was removed
                            for ri = 1, #removed do
                                if removed[ri] == trackedAid then
                                    needDispelScan = true; break
                                end
                            end
                        end
                    end
                end
            end
            if needDispelScan then
                if GF._UpdateDispelFromAuraDelta then
                    dispelChanged, dispelRelevant = GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
                else
                    GF._UpdateDispel(f, unit)
                    dispelChanged, dispelRelevant = true, true
                end
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateCornerIndicators and ((c.ciCustom and ciRelevant)
            or (c.ciDispel and ((not c.dispelScan and ciRelevant) or dispelChanged or dispelRelevant)))
        then
            GF.UpdateCornerIndicators(f, unit)
        end
        return
    end

    -- c.anyAuraGrp already includes sub-group enabled check, no need for second pass
    if c.nativeBlizzardAuraOnly and not c.ciAura and not c.dsEn then
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if not NativeAuraContainerReady(f, unit) and GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        end
        return
    end

    -- Full rescan required
    if not updateInfo or updateInfo.isFullUpdate then
        -- Throttle fullUpdate when out of combat (Blizzard fires these periodically)
        if updateInfo and updateInfo.isFullUpdate and not InCombatLockdown() then
            local now = GetTime()
            local last = f._msufGFLastFullAura
            if last and (now - last) < 0.5 then
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
            f._msufGFLastFullAura = now
        end
        -- fall through to full pipeline below
    else
        local added   = updateInfo.addedAuras
        local removed = updateInfo.removedAuraInstanceIDs
        local updated = updateInfo.updatedAuraInstanceIDs
        local hasAdd = added and #added > 0
        local hasRem = removed and #removed > 0
        local hasUpd = updated and #updated > 0

        -- Nothing relevant at all
        if not hasAdd and not hasRem and not hasUpd then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end

        local displayed = f._msufDisplayedAuraIDs

        -- Update-only: direct icon refresh (16Âµs vs 115Âµs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                local needsDeltaPipeline = false
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        if GF.RefreshAuraIcon(icon, unit, updated[ui]) == false then
                            needsDeltaPipeline = true
                            break
                        end
                    end
                end
                if not needsDeltaPipeline then
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add/remove: handled below by the cache-backed delta pipeline.
    end

    if updateInfo and not updateInfo.isFullUpdate then
        if c.siEn and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if GF.UpdateFrameAuras then
            GF.UpdateFrameAuras(f, unit, updateInfo)
        elseif GF._UpdateDispel then
            GF._UpdateDispel(f, unit)
        end
        GF.FinishAuraVisuals(f, unit, c, updateInfo)
        return
    end

    -- Out-of-combat rate limit: max 2 full rescans/s per frame (idle optimization)
    -- In combat: unlimited (instant debuff detection)
    if not InCombatLockdown() then
        local now = GetTime()
        if f._msufGFLastFullAura and (now - f._msufGFLastFullAura) < 0.5 then
            if siRefresh and GF.UpdateSpellIndicators then
                GF.UpdateSpellIndicators(f, unit)
            end
            return
        end
        f._msufGFLastFullAura = now
    end

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- P1: In-combat burst-dedup (A2 P2 pattern)
    -- First event runs the full pipeline immediately (zero latency).
    -- Subsequent events for the SAME frame within 20ms are skipped.
    -- Saves N-1 full pipeline runs per AoE burst (N=simultaneous aura
    -- changes per unit). Clear-callback allocated once per frame.
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    if f._msufGFFullPending then
        return
    end
    f._msufGFFullPending = true
    do
        local cb = f._msufGFPendClearCB
        if not cb then
            local frame = f
            cb = function() frame._msufGFFullPending = nil end
            f._msufGFPendClearCB = cb
        end
        local key = f._msufGFPendClearKey
        if not key then
            key = "GF_AURA_PEND_" .. tostring(f)
            f._msufGFPendClearKey = key
        end
        _MSUF_ScheduleDelayOnce(key, 0.02, cb)
    end

    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    -- P2: Global per-frame budget (AoE spike limiter)
    -- AoE events fire 20+ UNIT_AURA for different units in one frame.
    -- Each full scan costs ~138Âµs. 20 Ã— 138Âµs = 2.8ms spike.
    -- Budget caps to 8 scans/frame â†’ max ~1.1ms. Rest deferred.
    -- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    _gfAuraBudget = _gfAuraBudget + 1
    local now = GetTime()
    if now ~= _gfAuraBudgetFrame then
        _gfAuraBudgetFrame = now
        _gfAuraBudget = 1
    end
    if _gfAuraBudget > _GF_AURA_BUDGET_MAX then
        _gfQueueAuraDirty(f)
        if not _gfAuraDirtyPending then
            _gfAuraDirtyPending = true
            _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
        end
        return
    end

    -- Full aura processing (add/remove/fullUpdate)
    -- SI runs first: populates dedup IDs before buff scan
    if c.siEn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
    end
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit, updateInfo)
    else
        GF._UpdateDispel(f, unit)
    end
    GF.FinishAuraVisuals(f, unit, c, updateInfo)

end

------------------------------------------------------------------------
-- Deferred aura flush: processes frames that exceeded the per-frame budget.
-- Fires via C_Timer.After(0) â†’ runs at the start of the next frame.
------------------------------------------------------------------------
_gfFlushDirtyAuras = function()
    _gfAuraBudget = 0
    _gfAuraDirtyPending = false

    -- Process at most the same number of deferred full aura scans that the
    -- immediate path allows per frame. The previous loop walked the whole
    -- queue and relied on dispatchAura to re-queue overflow frames, which was
    -- correct but created extra Lua churn during large raid-wide aura bursts.
    local processed = 0
    local stopTail = _gfAuraDirtyTail
    while _gfAuraDirtyHead <= stopTail and processed < _GF_AURA_BUDGET_MAX do
        local f = _gfAuraDirtyQueue[_gfAuraDirtyHead]
        _gfAuraDirtyQueue[_gfAuraDirtyHead] = nil
        _gfAuraDirtyHead = _gfAuraDirtyHead + 1
        if f then
            _gfAuraDirtyQueued[f] = nil
            if f._msufGFAuraDirty then
                f._msufGFAuraDirty = nil
                local u = f.unit
                if u and UnitExists(u) then
                    -- This is the deferred full scan, so bypass the short
                    -- same-unit burst guard that scheduled the deferral.
                    f._msufGFFullPending = nil
                    dispatchAura(f, u, nil)
                end
            end
        end
        processed = processed + 1
    end
    if _gfAuraDirtyHead > _gfAuraDirtyTail then
        _gfAuraDirtyHead, _gfAuraDirtyTail = 1, 0
    elseif not _gfAuraDirtyPending then
        _gfAuraDirtyPending = true
        _MSUF_ScheduleOnce("GF_AURA_BUDGET_FLUSH", _gfFlushDirtyAuras)
    end
end
------------------------------------------------------------------------
-- Range fade (1:1 EQoL pattern)
-- Secret-safe: NEVER compare/type()/conditional on inRange.
-- Pass raw value to SetAlphaFromBoolean (C-side accepts secrets).
-- 1:1 EQoL GF:UpdateRange pattern â€” NO extra UnitPhaseReason/UnitIsVisible.
------------------------------------------------------------------------

-- EQoL UnsecretBool equivalent
local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function _NormalizeRangeFadeLayerMode(mode)
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "frame"
end

local function _GF_GetFrameAlpha(kind, conf)
    local fn = GF.GetEffectiveFrameAlpha
    if type(fn) == "function" then return fn(kind, conf) end
    return 1
end

local function _GF_ApplyFrameAlpha(f, kind, conf)
    local target = (f and f.barGroup) or f
    if target and target.SetAlpha then
        local c = f._c
        local a = c and c.frameAlpha
        if type(a) ~= "number" then
            a = _GF_GetFrameAlpha(kind, conf or GF.GetConf(kind))
        end
        target:SetAlpha(a)
    end
end

local function _ClearHealthRangeFade(f, kind)
    if not f then return end
    if f._msufGFHealthAlphaDynamic or f._msufGFHealthAlphaMul or type(f._msufGFHealthAlphaBool) ~= "nil" then
        f._msufGFHealthAlphaDynamic = nil
        f._msufGFHealthAlphaMul = nil
        f._msufGFHealthAlphaBool = nil
        f._msufGFHealthAlphaFalseMul = nil
        if GF.ApplyHealthBarAlpha then
            GF.ApplyHealthBarAlpha(f, kind or f._msufGFKind or "party")
        elseif f.health and f.health.SetAlpha then
            f.health:SetAlpha(1)
        end
    end
end

local function _ApplyHealthRangeFade(f, kind, boolValue, fadeMul, numericMul)
    if not f then return end
    local m = tonumber(fadeMul) or 1
    if m < 0 then m = 0 elseif m > 1 then m = 1 end

    f._msufGFHealthAlphaDynamic = true
    f._msufGFHealthAlphaFalseMul = m
    if type(boolValue) ~= "nil" then
        f._msufGFHealthAlphaBool = boolValue
        f._msufGFHealthAlphaMul = nil
    else
        local nm = tonumber(numericMul)
        if nm == nil then nm = m end
        if nm < 0 then nm = 0 elseif nm > 1 then nm = 1 end
        f._msufGFHealthAlphaBool = nil
        f._msufGFHealthAlphaMul = nm
    end

    _GF_ApplyFrameAlpha(f, kind or f._msufGFKind or "party")
    if GF.ApplyHealthBarAlpha then
        GF.ApplyHealthBarAlpha(f, kind or f._msufGFKind or "party")
    elseif f.health and f.health.SetAlpha and type(boolValue) == "nil" then
        f.health:SetAlpha(f._msufGFHealthAlphaMul or 1)
    end
end

local ApplyRangeFade
do
    ApplyRangeFade = function(f, unit, inRange)
        local c = f._c
        local kind = f._msufGFKind or "party"
        if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
        if f._msufGFRangeFadeUnit ~= unit then
            f._msufGFRangeFadeUnit = unit
        end
        local conf
        if not c then conf = GF.GetConf(kind) end
        local frameAlpha = (c and c.frameAlpha) or _GF_GetFrameAlpha(kind, conf)
        if (c and not c.rfEn) or (conf and conf.rangeFadeEnabled == false) then
            f._msufGFRangeFadeUnit = nil
            _ClearHealthRangeFade(f, kind)
            local target = (f and f.barGroup) or f
            if target and target.SetAlpha then target:SetAlpha(frameAlpha) end
            return
        end
        local fadeAlpha = (c and c.rfAlpha) or (conf and conf.rangeFadeAlpha) or 0.4
        local hpMode = ((c and c.rfLayerMode) or (conf and _NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode)) or "frame") == "health"

        if IsInGroup and IsInRaid then
            local inGroup = IsInGroup()
            local inRaid = IsInRaid()
            if not inGroup and not inRaid then
                f._msufGFRangeFadeUnit = nil
                _ClearHealthRangeFade(f, kind)
                local target = (f and f.barGroup) or f
                if target and target.SetAlpha then target:SetAlpha(frameAlpha) end
                return
            end
        end

        local connected = unit and UnitIsConnected and _UnsecretBool(UnitIsConnected(unit)) or nil
        if connected == false then
            f._msufGFRangeFadeUnit = nil
            local offA = (c and c.offAlpha) or (conf and conf.offlineAlpha) or fadeAlpha
            if hpMode then
                _ApplyHealthRangeFade(f, kind, nil, offA, offA)
            else
                _ClearHealthRangeFade(f, kind)
                local target = (f and f.barGroup) or f
                if target and target.SetAlpha then target:SetAlpha(frameAlpha * offA) end
            end
            return
        end

        if not hpMode then
            _ClearHealthRangeFade(f, kind)
        end
        if inRange == nil and unit and UnitInRange then inRange = UnitInRange(unit) end
        if type(inRange) ~= "nil" then
            if hpMode then
                _ApplyHealthRangeFade(f, kind, inRange, fadeAlpha)
            else
                local target = (f and f.barGroup) or f
                if target and target.SetAlphaFromBoolean then
                    target:SetAlphaFromBoolean(inRange, frameAlpha, frameAlpha * fadeAlpha)
                elseif target and target.SetAlpha then
                    local boolValue = _UnsecretBool(inRange)
                    if type(boolValue) ~= "nil" then
                        target:SetAlpha((boolValue and frameAlpha) or (frameAlpha * fadeAlpha))
                    end
                end
            end
        end
    end
end

function GF.RefreshGroupAlphas()
    local frames = GF.frames
    if frames then
        local list = GF.frameList
        if list then
            for i = 1, #list do
                local f = list[i]
                if f and _RuntimeEnabledForFrame(f) then
                    local kind = f._msufGFKind or "party"
                    if GF.BuildFrameCache then GF.BuildFrameCache(f) end
                    if GF.ApplyHealthBarAlpha then GF.ApplyHealthBarAlpha(f, kind) end
                    if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, kind) end
                    if GF.ApplyBackgroundAlpha then GF.ApplyBackgroundAlpha(f, kind) end
                    if f.unit and UnitExists(f.unit) then
                        ApplyRangeFade(f, f.unit)
                    else
                        _GF_ApplyFrameAlpha(f, kind)
                    end
                end
            end
        else
            for f in pairs(frames) do
                if f and _RuntimeEnabledForFrame(f) then
                    local kind = f._msufGFKind or "party"
                    if GF.BuildFrameCache then GF.BuildFrameCache(f) end
                    if GF.ApplyHealthBarAlpha then GF.ApplyHealthBarAlpha(f, kind) end
                    if GF.ApplyPowerBarAlpha then GF.ApplyPowerBarAlpha(f, kind) end
                    if GF.ApplyBackgroundAlpha then GF.ApplyBackgroundAlpha(f, kind) end
                    if f.unit and UnitExists(f.unit) then
                        ApplyRangeFade(f, f.unit)
                    else
                        _GF_ApplyFrameAlpha(f, kind)
                    end
                end
            end
        end
    end
    -- Runtime alpha transitions are already applied above. Do not dirty the
    -- visual pipeline here: in combat, MarkAllDirty promotes to a post-combat
    -- RefreshVisuals fan-out, turning alpha-only state changes into full
    -- frame/aura refreshes.
end

local function _GF_ShouldApplyRangeOrFrameAlpha(f, c, kind)
    if c and c.rfEn then return true end
    if f and f._msufGFHealthAlphaDynamic then return true end
    local cachedAlpha = c and c.frameAlpha
    if type(cachedAlpha) == "number" then return cachedAlpha < 0.999 end
    local fn = GF.GetEffectiveFrameAlpha
    if type(fn) ~= "function" then return false end
    kind = kind or (f and f._msufGFKind) or "party"
    local a = fn(kind, GF.GetConf(kind))
    return type(a) == "number" and a < 0.999
end

------------------------------------------------------------------------
-- Aggro border (secret-safe UnitThreatSituation)
------------------------------------------------------------------------
local _hlBdInsets = { left = 0, right = 0, top = 0, bottom = 0 }
local function _applyHighlightBorderStyle(border, conf, edgeSz, ofs, texKey, layer, r, g, b, a)
    edgeSz = math_max(1, edgeSz or 2)
    ofs = tonumber(ofs) or 0
    local edgeFile = GF.ResolveHighlightTexture(texKey)

    -- IMPORTANT:
    -- GF highlight live-apply must materialize a NEW backdrop description when
    -- edge texture/size changes. Reusing one shared table can leave existing
    -- Backdrop frames visually stale even though our Lua-side cache changed.
    -- UF does not have this issue because it creates a fresh literal table.
    if border._msufHLEdge ~= edgeFile or border._msufHLEdgeSz ~= edgeSz then
        border._msufHLEdge   = edgeFile
        border._msufHLEdgeSz = edgeSz
        border:SetBackdrop({ edgeFile = edgeFile, edgeSize = edgeSz, insets = _hlBdInsets })
        border:SetBackdropColor(0, 0, 0, 0)
    end
    border:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)

    -- Diff-gate anchor offset
    if border._msufHLOfs ~= ofs then
        border._msufHLOfs = ofs
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -ofs, ofs)
        border:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    end

    -- Layer: ABOVE_BORDER = higher FrameLevel
    local anchor = border:GetParent()
    if anchor then
        local baseLvl = anchor:GetFrameLevel()
        local wantLvl = (layer == "ABOVE_BORDER") and (baseLvl + 8) or (baseLvl + 3)
        if border._msufHLLvl ~= wantLvl then
            border._msufHLLvl = wantLvl
            border:SetFrameLevel(wantLvl)
        end
    end
end

------------------------------------------------------------------------
-- HLColor: read highlight COLORS always from MSUF_DB.general first
-- (same source as main UF â€” Colors panel writes there).
-- hlOverride only gates geometry (size/offset/layer) and enable flags,
-- NOT colors â€” prevents stale-seeded color copies in gf_party/gf_raid.
------------------------------------------------------------------------
local function HLColor(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

local function HLColorCached(gen, key, fallback)
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

------------------------------------------------------------------------
-- Per-frame settings cache (cold-path build, hot-path read)
-- Eliminates GF.GetConf + key reads from every UNIT_HEALTH/POWER event.
-- Rebuilt on ApplyVisuals (dirty flush) and RefreshVisuals.
------------------------------------------------------------------------
function GF.BuildFrameCache(f)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local c = f._c
    if not c then c = {}; f._c = c end
    f._msufGFStatusLayoutState = nil
    local fScale = conf._resolvedFrameScale or 1
    c.frameScale = fScale

    -- Smooth fill (pre-resolved interpolation enum)
    c.smooth    = conf.smoothFill ~= false and _smoothInterp or nil
    c.powSmooth = conf.powerSmoothFill and _smoothInterp or nil

    -- Health text slots. showHPText gates the whole HP text pipeline so
    -- disabled text builds no closures and does no event-time formatting.
    c.hpTextEnabled = conf.showHPText ~= false
    c.tl    = c.hpTextEnabled and (conf.textLeft    or "NONE") or "NONE"
    c.tc    = c.hpTextEnabled and (conf.textCenter  or "NONE") or "NONE"
    c.tr    = c.hpTextEnabled and (conf.textRight   or "NONE") or "NONE"
    c.tlOn  = c.tl ~= "NONE"
    c.tcOn  = c.tc ~= "NONE"
    c.trOn  = c.tr ~= "NONE"
    -- PERF: Aggregate flag â€” skip all 3 text blocks when no text enabled
    c.anyText = c.tlOn or c.tcOn or c.trOn
    c.delim = conf.textDelimiter or " / "
    c.rev   = conf.hpTextReverse
    -- Compile fast text functions (oUF-style: mode â†’ C-side closure)
    _BuildSlotFns(c)

    -- Cooldown swipe direction (Fix B): pre-cached so ApplyCooldownVisualStyle
    -- in RenderGroup hot path / RefreshAuraIcon doesn't need GF.GetConf.
    -- Live-apply via Options toggle: GF.RefreshVisuals â†’ ApplyVisuals â†’
    -- BuildFrameCache (this function) â†’ c.cdReverse refreshed.
    c.cdReverse = conf.cooldownSwipeDarkenOnLoss == true
    c.reverseFill = conf.reverseFill == true

    -- Health color mode (pre-resolve full chain)
    local gfMode = conf.gfBarMode
    local getCache = _G.MSUF_UFCore_GetSettingsCache
    local gc = type(getCache) == "function" and getCache() or nil
    if gfMode and gfMode ~= "GLOBAL" then
        c.hcMode = gfMode
    elseif gc and (gc.barMode == "dark" or gc.barMode == "unified") then
        c.hcMode = gc.barMode
    else
        c.hcMode = conf.healthColorMode or "CLASS"
    end
    c.darkR     = conf.gfDarkR or (gc and gc.darkBarR) or 0
    c.darkG     = conf.gfDarkG or (gc and gc.darkBarG) or 0
    c.darkB     = conf.gfDarkB or (gc and gc.darkBarB) or 0
    c.unifiedR  = conf.gfUnifiedR or (gc and gc.unifiedBarR) or 0.10
    c.unifiedG  = conf.gfUnifiedG or (gc and gc.unifiedBarG) or 0.60
    c.unifiedB  = conf.gfUnifiedB or (gc and gc.unifiedBarB) or 0.90
    c.customR   = conf.healthCustomR or 0.2
    c.customG   = conf.healthCustomG or 0.8
    c.customB   = conf.healthCustomB or 0.2
    c.classFn   = _G.MSUF_UFCore_GetClassBarColorFast
    -- PERF: Pre-resolve GRADIENT flag so lean path avoids string compare
    c.hcGradient = (c.hcMode == "GRADIENT")

    -- Power
    c.powH      = (GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind))
        or ((conf.powerHeight or 6) * fScale)
    c.showPow   = (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) or false
    c.ptl       = conf.powerTextLeft   or "NONE"
    c.ptc       = conf.powerTextCenter or "NONE"
    c.ptr       = conf.powerTextRight  or "NONE"
    c.ptlOn     = c.ptl ~= "NONE"
    c.ptcOn     = c.ptc ~= "NONE"
    c.ptrOn     = c.ptr ~= "NONE"
    c.pDelim    = conf.powerTextDelimiter or " / "
    c.anyPowerText = c.showPow and (c.ptlOn or c.ptcOn or c.ptrOn) or false
    -- Static config gate only. Runtime UnitEvent registration below also
    -- checks the current unit role so DPS frames with hidden power bars do
    -- not still wake up on UNIT_POWER_*.
    c.hasPowerElement = c.powH > 0 or c.anyPowerText
    -- UNIT_POWER_UPDATE is enough for group members. The player's own group
    -- button needs UNIT_POWER_FREQUENT for responsive resource text/smooth fill.
    c.powFrequent = c.hasPowerElement and (c.powSmooth or c.anyPowerText) or false
    c.powTank   = conf.powerShowTank   ~= false
    c.powHealer = conf.powerShowHealer ~= false
    c.powDPS    = conf.powerShowDamager ~= false

    -- Range fade
    c.rfEn    = conf.rangeFadeEnabled ~= false
    c.rfAlpha = conf.rangeFadeAlpha or 0.4
    c.offAlpha = conf.offlineAlpha or 0.5
    c.hideOfflineEn = conf.hideOfflineEnabled == true
    c.hideOfflineCombat = c.hideOfflineEn and conf.hideOfflineInCombat == true
    c.hideOfflineDelay = c.hideOfflineEn and (tonumber(conf.hideOfflineDelay) or 0) or 0
    if c.hideOfflineDelay < 0 then c.hideOfflineDelay = 0 end
    c.hideOfflineActive = c.hideOfflineEn and (c.hideOfflineCombat or not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))) or false
    f._msufGFOfflineConfigured = c.hideOfflineEn or nil
    f._msufGFOfflineCombatAllowed = c.hideOfflineCombat or nil
    f._msufGFOfflineActive = c.hideOfflineActive or nil
    if c.hideOfflineEn then
        GF._offlineHideAnyEnabled = true
    else
        if (f._msufGFOfflineHidden or f._msufGFOfflineHideTimer or f._msufGFOfflineKey or f._msufGFOfflineSince or f._msufGFOfflineHideDueAt)
            and GF.ResetOfflineHiddenFrame
        then
            GF.ResetOfflineHiddenFrame(f)
        end
        if GF._offlineHideAnyEnabled and GF.RefreshOfflineHideEnabledFlag and not GF._offlineHideFlagRefreshQueued then
            GF._offlineHideFlagRefreshQueued = true
            _MSUF_ScheduleOnce("GF_OFFLINE_HIDE_FLAG_REFRESH", function()
                GF._offlineHideFlagRefreshQueued = nil
                if GF.RefreshOfflineHideEnabledFlag then GF.RefreshOfflineHideEnabledFlag() end
            end)
        end
    end
    c.rfLayerMode = _NormalizeRangeFadeLayerMode(conf.rangeFadeLayerMode)
    c.hpBarAlpha = (GF.GetEffectiveHealthAlpha and GF.GetEffectiveHealthAlpha(kind, conf)) or tonumber(conf.hpBarAlpha) or 1
    if c.hpBarAlpha < 0 then c.hpBarAlpha = 0 elseif c.hpBarAlpha > 1 then c.hpBarAlpha = 1 end
    c.alphaPreserveHPColor = conf.alphaPreserveHPColor == true
    c.frameAlpha = (GF.GetEffectiveFrameAlpha and GF.GetEffectiveFrameAlpha(kind, conf)) or 1

    -- Health fade (curve-based HP threshold dimming)
    c.hfEn     = conf.healthFadeEnabled == true
    c.hfAlpha  = conf.healthFadeAlpha or 0.45
    c.hfThresh = conf.healthFadeThreshold or 95

    local auras = conf.auras
    c.aurasOn = auras and auras.enabled ~= false
    local auraMasterOn = c.aurasOn == true

    local pa = conf.privateAuras
    if GF.GetBlizzardAuraTypeFlags then
        local nativeBuffs, nativeDebuffs, nativeDispels, nativeExt, nativePrivate = GF.GetBlizzardAuraTypeFlags(conf)
        c.nativeBlizzardBuffs = nativeBuffs == true
        c.nativeBlizzardDebuffs = nativeDebuffs == true
        c.nativeBlizzardExt = nativeExt == true
        c.nativeBlizzardDispels = nativeDispels == true
        c.nativeBlizzardPrivate = nativePrivate == true and pa and pa.enabled ~= false
    else
        c.nativeBlizzardBuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "buffs") == true
        c.nativeBlizzardDebuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "debuffs") == true
        c.nativeBlizzardExt = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "externals") == true
        c.nativeBlizzardDispels = _GF_IsBlizzardDispelRendererActive(conf)
        c.nativeBlizzardPrivate = GF.IsBlizzardAuraTypeEnabled
            and GF.IsBlizzardAuraTypeEnabled(conf, "privateAuras") == true
            and pa and pa.enabled ~= false
    end

    -- Dispel overlay (color wash on health bar)
    c.doEn    = auraMasterOn and conf.dispelOverlayEnabled == true and not c.nativeBlizzardDispels
    c.doStyle = conf.dispelOverlayStyle or "FULL"
    c.doOnHP  = conf.dispelOverlayOnHealth ~= false
    c.doAlpha = conf.dispelOverlayAlpha or 0.35

    -- Debuff stripe (thin edge for any debuff). This is a custom aura-derived
    -- visual, so it must not keep UNIT_AURA/custom scans alive when Blizzard
    -- owns debuff rendering.
    c.dsEn    = auraMasterOn and conf.debuffStripeEnabled == true and not c.nativeBlizzardDebuffs
    c.dsEdge  = conf.debuffStripeEdge or "BOTTOM"
    c.dsH     = (GF.ScaleValue and GF.ScaleValue(conf.debuffStripeHeight or 3, fScale, 1))
        or (conf.debuffStripeHeight or 3)
    c.dsAlpha = conf.debuffStripeAlpha or 0.60
    c.dsR     = conf.debuffStripeColorR or 0.80
    c.dsG     = conf.debuffStripeColorG or 0.20
    c.dsB     = conf.debuffStripeColorB or 0.20

    -- Highlight border (pre-resolve HLVal)
    c.aggroEn   = HLValCached(conf, gen, "hlAggroEnabled") ~= false
    c.aggroMode = HLValCached(conf, gen, "hlAggroMode") or "ALL"
    c.dispelEn  = auraMasterOn and HLValCached(conf, gen, "hlDispelEnabled") ~= false and not c.nativeBlizzardDispels
    c.targetEn  = HLValCached(conf, gen, "hlTargetEnabled") ~= false
    c.focusEn   = conf.hlFocusEnabled ~= false
    c.aggroSize = HLValCached(conf, gen, "hlAggroSize") or 2
    c.aggroOfs = HLValCached(conf, gen, "hlAggroOffset") or 0
    c.aggroTex = HLValCached(conf, gen, "hlAggroTexture")
    c.aggroLayer = HLValCached(conf, gen, "hlAggroLayer") or "DEFAULT"
    c.aggroR = HLColorCached(gen, "hlAggroColorR", 1)
    c.aggroG = HLColorCached(gen, "hlAggroColorG", 0.55)
    c.aggroB = HLColorCached(gen, "hlAggroColorB", 0)

    -- Target color (pre-resolve HLColor)
    c.tgtSize = HLValCached(conf, gen, "hlTargetSize") or 2
    c.tgtOfs = HLValCached(conf, gen, "hlTargetOffset") or 0
    c.tgtTex = HLValCached(conf, gen, "hlTargetTexture")
    c.tgtLayer = HLValCached(conf, gen, "hlTargetLayer") or "DEFAULT"
    c.tgtR = HLColorCached(gen, "hlTargetColorR", 1)
    c.tgtG = HLColorCached(gen, "hlTargetColorG", 1)
    c.tgtB = HLColorCached(gen, "hlTargetColorB", 1)

    -- Focus color
    c.focSize = conf.hlFocusSize or 2
    c.focOfs = conf.hlFocusOffset or 0
    c.focTex = conf.hlFocusTexture
    c.focLayer = conf.hlFocusLayer or "DEFAULT"
    c.focR = conf.hlFocusColorR or 0.5
    c.focG = conf.hlFocusColorG or 0.5
    c.focB = conf.hlFocusColorB or 1.0

    -- Aura dispatch
    c.dispelScan = auraMasterOn and conf.dispelEnabled ~= false and not c.nativeBlizzardDispels
    local siRuntimeActive = false
    if auraMasterOn and conf.spellIndicators and conf.spellIndicators.enabled == true then
        local siActiveFn = GF.SpellIndicatorsRuntimeActive
        siRuntimeActive = type(siActiveFn) == "function"
            and siActiveFn(kind, conf.spellIndicators) == true
    end
    c.siEn       = siRuntimeActive
    c.healerBuffsEn = auraMasterOn and conf.healerBuffs and conf.healerBuffs.enabled == true and not c.siEn
    local customBuffs = auraMasterOn and auras.buff and auras.buff.enabled ~= false and not c.nativeBlizzardBuffs
    local customDebuffs = auraMasterOn and auras.debuff and auras.debuff.enabled ~= false and not c.nativeBlizzardDebuffs
    local customExt = auraMasterOn and auras.externals and auras.externals.enabled ~= false and not c.nativeBlizzardExt
    local customDispels = auraMasterOn and c.dispelScan and GF._playerCanDispel

    c.nativeBlizzardAuras = c.aurasOn and (
                   c.nativeBlizzardBuffs or c.nativeBlizzardDebuffs
                   or c.nativeBlizzardExt or c.nativeBlizzardDispels
                   or c.nativeBlizzardPrivate)
    c.customAuraGrp = customBuffs or customDebuffs or customExt or customDispels
    c.anyAuraGrp = c.nativeBlizzardAuras or c.customAuraGrp
    c.nativeBlizzardAuraOnly = c.nativeBlizzardAuras and not c.customAuraGrp
    c.auraCacheSig = nil
    -- PERF (4.22 Beta hotfix): clear cached resolved filter/max so next
    -- UpdateFrameAuras call re-reads from auras.X (settings may have changed).
    -- Paired with c.auraCacheSig invalidation -- both caches share lifetime.
    -- Re-allocation on next call is negligible (settings changes are rare).
    c.auraResolved = nil

    -- Corner indicators
    c.ciEn = conf.ciEnabled ~= false
    c.ciSize = tonumber(conf.ciSize) or 8
    if fScale ~= 1 then c.ciSize = math_max(4, math_floor(c.ciSize * fScale + 0.5)) end
    if c.ciSize < 4 then c.ciSize = 4 elseif c.ciSize > 24 then c.ciSize = 24 end
    c.ciAlpha = tonumber(conf.ciAlpha) or 1.0
    if c.ciAlpha < 0 then c.ciAlpha = 0 elseif c.ciAlpha > 1 then c.ciAlpha = 1 end
    -- PERF: Pre-compute slotâ†’category map (eliminates 63K SlotCat calls/session)
    c.ciSlotTL = (conf.ciSlotTL or "none")
    c.ciSlotTR = (conf.ciSlotTR or "none")
    c.ciSlotBL = (conf.ciSlotBL or "none")
    c.ciSlotBR = (conf.ciSlotBR or "none")
    c.ciSlotC  = (conf.ciSlotC  or "none")
    c.ciDispel = c.ciEn and auraMasterOn and (
        c.ciSlotTL == "dispel" or c.ciSlotTR == "dispel" or c.ciSlotBL == "dispel"
        or c.ciSlotBR == "dispel" or c.ciSlotC == "dispel")
    c.ciCustom = c.ciEn and auraMasterOn and (
        c.ciSlotTL == "custom" or c.ciSlotTR == "custom" or c.ciSlotBL == "custom"
        or c.ciSlotBR == "custom" or c.ciSlotC == "custom")
    c.ciAura = c.ciCustom or (c.ciDispel and not c.nativeBlizzardDispels)
    c.ciThreat = c.ciEn and (
        c.ciSlotTL == "aggro" or c.ciSlotTR == "aggro" or c.ciSlotBL == "aggro"
        or c.ciSlotBR == "aggro" or c.ciSlotC == "aggro")

    -- Private auras
    c.paEn = auraMasterOn and pa and pa.enabled ~= false and not c.nativeBlizzardPrivate

    -- Raid debuffs

    -- Heal prediction (Group Frame menu -> default off)
    c.healPredEn = (GF.IsHealPredictionEnabled and GF.IsHealPredictionEnabled(kind, conf)) or false

    -- Absorb: independently gated from heal prediction
    c.absorbEn = _GF_IsAbsorbEnabled(kind)
    c.healAbsorbEn = conf.healAbsorbEnabled ~= false
    c.healPredEventEn = c.healPredEn and f.incomingHealBar ~= nil
    c.absorbEventEn = c.absorbEn and f.absorbBar ~= nil and UnitGetTotalAbsorbs ~= nil
    c.healAbsorbEventEn = c.healAbsorbEn and f.healAbsorbBar ~= nil and UnitGetTotalHealAbsorbs ~= nil

    -- Name display
    c.nameEn = conf.showName ~= false
    c.nameMaxChars, c.nameNoEllipsis, c.nameClipSide = GF.ResolveNameTruncation(kind)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    c.nameStyleKey = tostring(c.nameEn) .. "\001"
        .. tostring(c.nameMaxChars) .. "\001"
        .. tostring(c.nameNoEllipsis) .. "\001"
        .. tostring(c.nameClipSide) .. "\001"
        .. tostring(conf.fontOverride) .. "\001"
        .. tostring(conf.useGlobalFontColor) .. "\001"
        .. tostring(conf.nameColorMode) .. "\001"
        .. tostring(conf.nameColorR) .. "\001"
        .. tostring(conf.nameColorG) .. "\001"
        .. tostring(conf.nameColorB) .. "\001"
        .. tostring(conf.fontR) .. "\001"
        .. tostring(conf.fontG) .. "\001"
        .. tostring(conf.fontB) .. "\001"
        .. tostring(gen and gen.nameClassColor)
    f._msufGFNameCacheKey = nil
    f._msufGFNameStyleKey = nil
    f._msufGFNameText = nil
    f._msufGFNameClass = nil
    f._msufGFNameColorKey = nil

    -- Status/icons: pre-resolve event/update consumers. Disabled features should
    -- not receive events and should not be called from shared dispatch paths.
    local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
    c.statusShowAFK = showAFK
    c.statusShowDND = showDND
    c.statusShowDead = showDead
    c.statusShowGhost = showGhost
    c.statusDeadTextEn = showDead and conf.statusText ~= false
    c.statusGhostTextEn = showGhost and conf.statusGhostText ~= false
    c.statusAwayTextEn = (showAFK or showDND) and conf.statusAFKText ~= false
    c.statusTextEn = c.statusDeadTextEn or c.statusGhostTextEn or c.statusAwayTextEn
    c.statusAwayEn = c.statusAwayTextEn
    c.roleIconEn   = conf.roleIcon ~= false
    c.powerRoleGated = c.hasPowerElement and ((not c.powTank) or (not c.powHealer) or (not c.powDPS))
    c.roleStateEn  = c.roleIconEn or c.powerRoleGated
    c.leaderEn     = conf.leaderIcon ~= false or conf.assistIcon ~= false
    c.raidMarkerEn = conf.raidMarker ~= false
    c.readyEn      = conf.readyCheckIcon ~= false
    c.summonEn     = conf.summonIcon ~= false
    c.resEn        = conf.resurrectIcon ~= false
    c.phaseEn      = conf.phaseIcon ~= false
    c.groupNumberEn = conf.showGroupNumber == true
    -- Status flags are driven by the global PLAYER_FLAGS_CHANGED path below;
    -- dead/offline states are covered by UNIT_HEALTH/UNIT_CONNECTION. Do not
    -- subscribe every raid button to UNIT_FLAGS: boss pulls and stealth/vanish
    -- transitions can flood it for the whole group.
    c.flagsEn      = false
    c.connectionEn = c.statusTextEn or c.rfEn or c.hideOfflineActive

    -- Composite: does anything need UNIT_AURA?
    c.needAura = c.customAuraGrp or c.ciAura
                 or (c.dispelScan and GF._playerCanDispel)
                 or c.dsEn
                 or c.siEn

    -- Composite: does anything need UNIT_THREAT?
    c.needThreat = c.aggroEn or c.ciThreat

    -- Event bitmask: drives diff-gated RegisterUnitEvents
    local evBits = 0
    if c.nameEn     then evBits = evBits + 1    end
    if c.hasPowerElement then evBits = evBits + 2    end
    if c.rfEn       then evBits = evBits + 4    end
    if c.needAura   then evBits = evBits + 8    end
    if c.needThreat then evBits = evBits + 16   end
    if c.summonEn   then evBits = evBits + 32   end
    if c.resEn      then evBits = evBits + 64   end
    if c.phaseEn    then evBits = evBits + 128  end
    if c.healPredEventEn then evBits = evBits + 256  end
    if c.absorbEventEn   then evBits = evBits + 512  end
    if c.healAbsorbEventEn then evBits = evBits + 1024 end
    if c.powFrequent then evBits = evBits + 2048 end
    if c.connectionEn then evBits = evBits + 4096 end
    if c.flagsEn then evBits = evBits + 8192 end
    local prevBits = c._evBits
    c._evBits = evBits
    if prevBits ~= nil and prevBits ~= evBits and f.unit and f._msufGFRegEv then
        GF.RegisterUnitEvents(f, f.unit)
    end
    if prevBits == nil or prevBits ~= evBits then
        if GF.RequestSyncGroupGlobalEvents then
            GF.RequestSyncGroupGlobalEvents()
        elseif GF.SyncGroupGlobalEvents then
            GF.SyncGroupGlobalEvents()
        end
    end

    -- Invalidate module-level text format cache (hidePercentSymbol, useShortNumbers)
    if GF.InvalidateTextFormatCache then GF.InvalidateTextFormatCache() end
end

------------------------------------------------------------------------
-- Lightweight border activation (NO SetBackdrop â€” color + show/hide only)
-- Called from PLAYER_TARGET_CHANGED / PLAYER_FOCUS_CHANGED
-- Full _GF_RefreshBorder is only needed when dispel/aggro state changes
-- or on config refresh (RefreshVisuals)
------------------------------------------------------------------------
local function _GF_QuickBorderUpdate(f)
    local border = f._msufGFHighlightBorder
    if not border then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    -- Dispel/Aggro are always higher priority than Target/Focus.
    -- If either is active, skip target/focus update (full _GF_RefreshBorder handles their order).
    if f._msufGFDispelType and c.dispelEn then return end
    if f._msufGFAggroLevel and f._msufGFAggroLevel >= 1 and c.aggroEn then return end

    -- Priority 3: Target
    if f._msufGFIsTarget and c.targetEn then
        if border._msufHLActivePrio ~= 3 then
            border._msufHLActivePrio = 3
            _applyHighlightBorderStyle(border, nil,
                c.tgtSize or 2,
                c.tgtOfs or 0,
                c.tgtTex,
                c.tgtLayer or "DEFAULT",
                c.tgtR, c.tgtG, c.tgtB, 1)
        else
            border:SetBackdropBorderColor(c.tgtR, c.tgtG, c.tgtB, 1)
        end
        if not border:IsShown() then border:Show() end
        return
    end

    -- Priority 4: Focus
    if f._msufGFIsFocus and c.focusEn then
        if border._msufHLActivePrio ~= 4 then
            border._msufHLActivePrio = 4
            _applyHighlightBorderStyle(border, nil,
                c.focSize or 2,
                c.focOfs or 0,
                c.focTex,
                c.focLayer or "DEFAULT",
                c.focR, c.focG, c.focB, 1)
        else
            border:SetBackdropBorderColor(c.focR, c.focG, c.focB, 1)
        end
        if not border:IsShown() then border:Show() end
        return
    end

    -- Nothing active
    border._msufHLActivePrio = nil
    if border:IsShown() then border:Hide() end
end

------------------------------------------------------------------------
-- Dispel overlay (color wash on health bar)
-- StatusBar-based: mirrors health value for "current health only" clip.
--
-- SECRET-SAFE COLOR APPLICATION (Midnight 12.0):
--   TYPE mode returns a Color object from C_UnitAuras.GetAuraDispelTypeColor.
--   Secret-tainted RGB values CAN pass through tex:SetVertexColor varargs
--   (C-side handles them) but CANNOT pass through CreateColor/SetGradient
--   (Lua-side taints). We therefore:
--     â€¢ use pre-baked gradient *textures* (Media/MSUF_Grad_*.tga) for the
--       TOP/BOTTOM/LEFT/RIGHT/EDGE styles â€” no SetGradient needed,
--     â€¢ apply the tint via tex:SetVertexColor(color:GetRGBA()) in a single
--       varargs passthrough â€” no Lua arithmetic on the tint values,
--     â€¢ use SetAlpha on the StatusBar frame for the user's doAlpha slider.
--
--   This replaces the Beta 5 path that called CreateColor(secret_r, ...)
--   in SetGradient branches â€” that was the "TYPE mode broken / only
--   SINGLE works" bug.
------------------------------------------------------------------------
local _MSUF_GRAD_PATH = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\"
local _GRAD_TEXTURES = {
    FULL   = "Interface\\Buttons\\WHITE8x8",
    TOP    = _MSUF_GRAD_PATH .. "MSUF_Grad_V",      -- solid top,    fades down
    BOTTOM = _MSUF_GRAD_PATH .. "MSUF_Grad_V_Rev",  -- solid bottom, fades up
    LEFT   = _MSUF_GRAD_PATH .. "MSUF_Grad_H",      -- solid left,   fades right
    RIGHT  = _MSUF_GRAD_PATH .. "MSUF_Grad_H_Rev",  -- solid right,  fades left
}

_GF_ApplyDispelOverlay = function(f)
    local dov = f._msufGFDispelOverlay
    if not dov then
        return
    end
    local c = f._c
    if not c then return end

    local dispelType = f._msufGFDispelType
    if not c.doEn or not dispelType then
        if dov:IsShown() then dov:Hide() end
        dov._msufDOSyncHP = nil
        return
    end

    -- Safety: anchor overlay to correct region based on style + doOnHP
    if f.health then
        local anchorTo = f.health
        if c.doStyle == "FULL" and not c.doOnHP and f.barGroup then
            anchorTo = f.barGroup
        end
        dov:ClearAllPoints()
        dov:SetAllPoints(anchorTo)
    end

    -- Pick gradient texture for the style (cheap diff-gate to avoid spamming
    -- SetStatusBarTexture â€” Blizzard reloads the atlas every call).
    local style = c.doStyle or "FULL"
    local texPath = _GRAD_TEXTURES[style] or _GRAD_TEXTURES.FULL
    if dov._msufDOStylePath ~= texPath then
        dov:SetStatusBarTexture(texPath)
        dov._msufDOStylePath = texPath
    end
    local tex = dov:GetStatusBarTexture()

    -- Fill value: mirror current health ("current health only") or full bar.
    local unit = f.unit
    if c.doOnHP and unit then
        local hm = f._msufGFCachedHpMax or UnitHealthMax(unit)
        dov:SetMinMaxValues(0, hm)
        dov:SetValue(UnitHealth(unit))
        dov._msufDOSyncHP = true
    else
        dov:SetMinMaxValues(0, 1)
        dov:SetValue(1)
        dov._msufDOSyncHP = nil
    end

    -- Resolve and apply tint (secret-safe path).
    local colorObj, r, g, b = ResolveDispelColorObj(f, dispelType)
    if tex then
        local rr, gg, bb, aa = ExtractColorRGBA(colorObj)
        tex:SetVertexColor(rr or r or 0.25, gg or g or 0.75, bb or b or 1.00, aa or 1)
    end
    -- User's alpha slider lives on the StatusBar frame, independent of tint.
    local userAlpha = c.doAlpha or 1
    if dov._msufDOAlphaCache ~= userAlpha then
        dov:SetAlpha(userAlpha)
        dov._msufDOAlphaCache = userAlpha
    end

    -- Reverse fill sync (match health bar direction)
    if dov.SetReverseFill then
        dov:SetReverseFill(c.reverseFill and true or false)
    end

    if not dov:IsShown() then dov:Show() end
end

------------------------------------------------------------------------
-- Debuff stripe (thin edge indicator for a configured debuff match).
-- Independent from dispel overlay â€” honors the Debuffs filter/list and
-- still works for non-dispellable debuffs when that filter allows them.
------------------------------------------------------------------------
_GF_ApplyDebuffStripe = function(f)
    local stripe = f._msufGFDebuffStripe
    if not stripe then return end
    local c = f._c
    if not c then return end

    if not c.dsEn or not f._msufGFHasAnyDebuff then
        if stripe:IsShown() then stripe:Hide() end
        return
    end

    -- Anchor based on edge setting
    local edge = c.dsEdge
    local h = math_max(1, c.dsH or 3)
    if stripe._msufDSEdge ~= edge or stripe._msufDSH ~= h then
        stripe._msufDSEdge = edge
        stripe._msufDSH = h
        stripe:ClearAllPoints()
        stripe:SetHeight(h)
        local anchor = f.health or f
        if edge == "TOP" then
            stripe:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
            stripe:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
        else -- BOTTOM (default)
            stripe:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
            stripe:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Color + alpha (diff-gated)
    local r, g, b, a = c.dsR, c.dsG, c.dsB, c.dsAlpha
    if stripe._msufDSR ~= r or stripe._msufDSG ~= g or stripe._msufDSB ~= b or stripe._msufDSA ~= a then
        stripe._msufDSR, stripe._msufDSG, stripe._msufDSB, stripe._msufDSA = r, g, b, a
        stripe:SetStatusBarColor(r, g, b, a)
    end

    -- Fill full width
    stripe:SetMinMaxValues(0, 1)
    stripe:SetValue(1)

    if not stripe:IsShown() then stripe:Show() end
end

_GF_RefreshBorder = function(f, unit)
    -- NOTE: Dispel overlay is fully decoupled from border highlight.
    -- Overlay lives in _GF_ApplyDispelOverlay and is called separately
    -- from dispel-change sites only â€” never from aggro/target/test paths.

    local border = f._msufGFHighlightBorder
    if not border then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    if not c then return end

    -- Resolve active states
    local dispelType = f._msufGFDispelType
    local hasDispel  = dispelType and c.dispelEn
    local aggroLevel = f._msufGFAggroLevel
    local hasAggro   = aggroLevel and aggroLevel >= 1 and c.aggroEn

    -- Shared geometry for dispel/aggro/purge (all use Aggro size keys)
    local sz  = c.aggroSize or 2
    local ofs = c.aggroOfs or 0
    local tex = c.aggroTex
    local lay = c.aggroLayer or "DEFAULT"
    local fScale = c.frameScale or 1
    if fScale ~= 1 and GF.ScaleValue then
        sz = GF.ScaleValue(sz, fScale, 1)
        ofs = GF.ScaleValue(ofs, fScale)
    end

    -- Configurable priority: read hlPrioOrder from Bars menu (general DB).
    -- Maps "dispel"/"magic"/"curse"/etc â†’ dispel, "aggro" â†’ aggro.
    -- Purge/bossTarget are UF-only, skip for GF.
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local prioEnabled = gen and gen.highlightPrioEnabled
    local prioOrder   = prioEnabled and gen.highlightPrioOrder

    if type(prioOrder) == "table" then
        for _, pk in ipairs(prioOrder) do
            if pk == "dispel" or pk == "magic" or pk == "curse"
            or pk == "disease" or pk == "poison" or pk == "bleed" then
                if hasDispel then
                    local r, g, b = ResolveDispelColor(dispelType, f)
                    if r then
                        _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay, r, g, b, 1)
                        border._msufHLActivePrio = 1; border:Show()
                        _GF_StartDispelGlow(f, r, g, b)
                        return
                    end
                end
            elseif pk == "aggro" then
                if hasAggro then
                    _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay,
                        c.aggroR or 1, c.aggroG or 0.55, c.aggroB or 0, 1)
                    border._msufHLActivePrio = 2; border:Show()
                    _GF_StopDispelGlow(f)
                    return
                end
            end
        end
    else
        -- Default: Dispel > Aggro
        if hasDispel then
            local r, g, b = ResolveDispelColor(dispelType, f)
            if r then
                _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay, r, g, b, 1)
                border._msufHLActivePrio = 1; border:Show()
                _GF_StartDispelGlow(f, r, g, b)
                return
            end
        end
        if hasAggro then
            _applyHighlightBorderStyle(border, nil, sz, ofs, tex, lay,
                c.aggroR or 1, c.aggroG or 0.55, c.aggroB or 0, 1)
            border._msufHLActivePrio = 2; border:Show()
            _GF_StopDispelGlow(f)
            return
        end
    end

    -- After configurable prio: Target (GF-specific, always after dispel/aggro)
    if f._msufGFIsTarget and c.targetEn then
        _applyHighlightBorderStyle(border, nil,
            c.tgtSize or 2,
            c.tgtOfs or 0,
            c.tgtTex,
            c.tgtLayer or "DEFAULT",
            c.tgtR or 1,
            c.tgtG or 1,
            c.tgtB or 1, 1)
        border._msufHLActivePrio = 3; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    -- Focus (GF-specific, lowest priority)
    if f._msufGFIsFocus and c.focusEn then
        _applyHighlightBorderStyle(border, nil,
            c.focSize or 2,
            c.focOfs or 0,
            c.focTex,
            c.focLayer or "DEFAULT",
            c.focR or 0.5,
            c.focG or 0.5,
            c.focB or 1.0, 1)
        border._msufHLActivePrio = 4; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    border._msufHLActivePrio = nil
    if border:IsShown() then border:Hide() end
    _GF_StopDispelGlow(f)
end

_GF_ClearNativeSuppressedDispel = function(f, unit)
    if not f then return end
    local hadDispel = f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
        or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive
    local border = f._msufGFHighlightBorder
    if border and border._msufHLActivePrio == 1 then hadDispel = true end

    f._msufGFMergedDispel = nil
    f._msufGFDispelType = nil
    f._msufGFDispelAuraID = nil
    f._msufGFPrevDispelAuraID = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    f._msufGFColorStyleRevision = nil

    local dov = f._msufGFDispelOverlay
    if dov then
        if dov:IsShown() then hadDispel = true; dov:Hide() end
        dov._msufDOSyncHP = nil
    end
    if GF.ApplyPrivateAuraContainerOverlay then
        GF.ApplyPrivateAuraContainerOverlay(f, unit or f.unit, { containerOverlay = { enabled = false } })
    elseif f._gfPrivOverlayFrame and f._gfPrivOverlayFrame:IsShown() then
        f._gfPrivOverlayFrame:Hide()
    end
    _GF_StopDispelGlow(f)
    if hadDispel and _GF_RefreshBorder then _GF_RefreshBorder(f, unit) end
end

function GF._RefreshAggroConsumers(f, unit, c)
    _GF_RefreshBorder(f, unit)
    if c and c.ciThreat and GF.UpdateCornerIndicators then
        f._msufCILastAt = nil
        GF.UpdateCornerIndicators(f, unit)
    end
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local prevLevel = f._msufGFAggroLevel
    -- PERF: pre-resolved flags on _c cache (populated in BuildFrameCache).
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end

    local testMode = (_G.MSUF_BorderTestModesActive == true) and _G.MSUF_AggroBorderTestMode
    -- Scope filtering
    if testMode then
        local testScope = _G.MSUF_AggroBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid"
                or (testScope == "mythicraid" or testScope == "gf_mythicraid") and "mythicraid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end
    local wantsAggroState = c and (c.aggroEn or c.ciThreat)
    if ((not wantsAggroState) or not unit) and not testMode then
        if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
        return
    end

    if not testMode then
        if not UnitExists(unit) then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        local aggroMode = (c and c.aggroMode) or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
                return
            end
            if aggroMode == "TANK_ONLY" and role ~= "TANK" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
                return
            end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then
            -- Secret: can't diff-gate, but only refresh if we had aggro before
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        local s = tonumber(status)
        if not s or s < 1 then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; GF._RefreshAggroConsumers(f, unit, c) end
            return
        end
        -- Diff-gate: only refresh border when threat level actually changes
        if s == prevLevel then return end
        f._msufGFAggroLevel = s
    else
        f._msufGFAggroLevel = 3
    end
    GF._RefreshAggroConsumers(f, unit, c)
end
GF._UpdateAggro = UpdateAggro

------------------------------------------------------------------------
-- Dispel border (zero-alloc direct C_UnitAuras slot scan)
-- Replaces AuraUtil.ForEachAura which allocates a table internally
-- every call ({C_UnitAuras.GetAuraSlots(...)}).
-- Module-level vararg scanner: zero closure, zero table per call.
------------------------------------------------------------------------
local _dispelScanUnit  -- module-level state for vararg scanner
local C_UnitAuras_GetAuraSlots    = C_UnitAuras and C_UnitAuras.GetAuraSlots
local C_UnitAuras_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local C_UnitAuras_GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local C_UnitAuras_IsAuraFilteredOut = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local _DISPEL_SCAN_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local _debuffStripeScanUnit

local function _DebuffStripeScanSlots(_, ...)
    local scanUnit = _debuffStripeScanUnit
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local aura = scanUnit and C_UnitAuras_GetAuraDataBySlot and C_UnitAuras_GetAuraDataBySlot(scanUnit, slot)
        if _dsPresenceCallback(aura) then
            return true
        end
    end
    return false
end

_FrameHasStripeDebuff = function(f, unit)
    if not unit or not UnitExists(unit) then return false end

    local kind = (f and f._msufGFKind) or "party"
    local conf = GF.GetConf(kind)
    local debCfg = conf and conf.auras and conf.auras.debuff or nil
    local af = GF.AuraFilter or _G.MSUF_GF_AuraFilter
    local filter = af and af.ResolveDebuffFilter(debCfg and debCfg.filterToken) or "HARMFUL"

    _dsPresenceResult = false
    _dsPresenceAF = af
    _dsPresenceBLHash = (debCfg and af and af.BuildBlacklistHash(debCfg)) or nil

    if C_UnitAuras_GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, index, filter)
            if not aura then break end
            if _dsPresenceCallback(aura) then break end
            index = index + 1
        end
    elseif C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
        _debuffStripeScanUnit = unit
        _DebuffStripeScanSlots(C_UnitAuras_GetAuraSlots(unit, filter))
        _debuffStripeScanUnit = nil
    elseif AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, filter, nil, _dsPresenceCallback, true)
    end

    _dsPresenceAF = nil
    _dsPresenceBLHash = nil
    return _dsPresenceResult
end

local function _DispelScanSlots(cont, ...)
    local GetData = C_UnitAuras_GetAuraDataBySlot
    local u = _dispelScanUnit
    local iss = issecretvalue
    -- C-side: use RAID_PLAYER_DISPELLABLE filter directly
    -- If we got slots from that filter, the first slot IS dispellable
    for i = 1, select("#", ...) do
        local slot = select(i, ...)
        local data = GetData(u, slot)
        if data and data.auraInstanceID then
            local dn = data.dispelName
            if not (iss and iss(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                return dn, data.auraInstanceID
            end
            return "DISPELLABLE", data.auraInstanceID
        end
    end
    return nil, nil
end

-- Legacy fallback (pre-C_UnitAuras clients)
local _scanTopDispel
local function _DispelScanCallback(auraData)
    if not auraData then return true end
    local dispelName = auraData.dispelName
    if issecretvalue and issecretvalue(dispelName) then return false end
    if dispelName and dispelName ~= "" then
        _scanTopDispel = dispelName
        return true
    end
    return false
end

function GF._UpdateDispel(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind)

    local testMode = (_G.MSUF_BorderTestModesActive == true) and _G.MSUF_DispelBorderTestMode
    -- Scope filtering: if test scope doesn't match this frame's kind, ignore test mode
    if testMode then
        local testScope = _G.MSUF_DispelBorderTestScope or "shared"
        if testScope ~= "shared" then
            local scopeKind = (testScope == "party" or testScope == "gf_party") and "party"
                or (testScope == "raid" or testScope == "gf_raid") and "raid"
                or (testScope == "mythicraid" or testScope == "gf_mythicraid") and "mythicraid" or nil
            if scopeKind ~= kind then testMode = false end
        end
    end

    local auras = conf and conf.auras
    if not testMode and (not auras or auras.enabled == false) then
        f._msufGFDispelKnown = true
        if _GF_ClearNativeSuppressedDispel then
            _GF_ClearNativeSuppressedDispel(f, unit)
        else
            f._msufGFMergedDispel = nil
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFPrevDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            f._msufGFColorStyleRevision = nil
        end
        return
    end

    if not testMode and _GF_IsBlizzardDispelRendererActive(conf) then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        f._msufGFDispelKnown = true
        return
    end

    if (HLVal(kind, "hlDispelEnabled") == false or not unit) and not testMode then
        f._msufGFDispelKnown = true
        if f._msufGFDispelType then
            f._msufGFDispelType = nil
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            _GF_RefreshBorder(f, unit)
            _GF_ApplyDispelOverlay(f)
        end
        return
    end

    local topDispel = nil
    local topAid = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    if not testMode then
        if not UnitExists(unit) then
            f._msufGFDispelKnown = true
            if f._msufGFDispelType then
                f._msufGFDispelType = nil
                f._msufGFDispelAuraID = nil
                f._msufGFDispelColorObj = nil
                f._msufGFDispelColorRev = nil
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
            end
            return
        end
        -- C-side: query dispellable debuffs directly (secret-safe)
        if C_UnitAuras_GetAuraDataByIndex then
            local aura = C_UnitAuras_GetAuraDataByIndex(unit, 1, _DISPEL_SCAN_FILTER)
            if aura and aura.auraInstanceID then
                local dn = aura.dispelName
                if not (issecretvalue and issecretvalue(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                    topDispel = dn
                else
                    topDispel = "DISPELLABLE"
                end
                topAid = aura.auraInstanceID
                if C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                    f._msufGFDispelColorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, topAid, GF._sharedDispelColorCurve)
                    f._msufGFDispelColorRev = _G.MSUF_ColorStyleRevision or 0
                else
                    f._msufGFDispelColorObj = nil
                    f._msufGFDispelColorRev = nil
                end
            end
        elseif C_UnitAuras_GetAuraSlots and C_UnitAuras_GetAuraDataBySlot then
            _dispelScanUnit = unit
            topDispel, topAid = _DispelScanSlots(C_UnitAuras_GetAuraSlots(unit, _DISPEL_SCAN_FILTER))
            _dispelScanUnit = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
        elseif AuraUtil and AuraUtil.ForEachAura then
            _scanTopDispel = nil
            AuraUtil.ForEachAura(unit, "HARMFUL|RAID", nil, _DispelScanCallback, true)
            topDispel = _scanTopDispel
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
        end
    else
        topDispel = _G.MSUF_DispelBorderTestType or "Magic"
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
    end

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFPrevDispelAuraID
    local colorRev = _G.MSUF_ColorStyleRevision or 0
    local prevColorRev = f._msufGFColorStyleRevision or 0
    f._msufGFDispelKnown = true
    f._msufGFDispelType = topDispel
    f._msufGFDispelAuraID = topAid
    f._msufGFPrevDispelAuraID = topAid

    if topDispel == prevDispel and topAid == prevAid and colorRev == prevColorRev and not testMode then return end

    f._msufGFColorStyleRevision = colorRev
    _GF_RefreshBorder(f, unit)
    -- Overlay only for real dispels â€” border test mode is border-only
    if not testMode then
        _GF_ApplyDispelOverlay(f)
    end
end

function GF._UpdateDispelFromAuraDelta(f, unit, updateInfo)
    if not (f and unit) then return false, false end

    local prevDispel = f._msufGFDispelType
    local prevAid = f._msufGFDispelAuraID
    local prevColorRev = f._msufGFColorStyleRevision or 0

    local function finishFull()
        GF._UpdateDispel(f, unit)
        return f._msufGFDispelType ~= prevDispel
            or f._msufGFDispelAuraID ~= prevAid
            or (f._msufGFColorStyleRevision or 0) ~= prevColorRev, true
    end

    if not updateInfo or updateInfo.isFullUpdate then
        return finishFull()
    end

    local trackedAid = f._msufGFDispelAuraID
    local removed = updateInfo.removedAuraInstanceIDs
    if removed and trackedAid then
        for i = 1, #removed do
            if removed[i] == trackedAid then
                return finishFull()
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated and trackedAid and C_UnitAuras_IsAuraFilteredOut then
        for i = 1, #updated do
            if updated[i] == trackedAid then
                if C_UnitAuras_IsAuraFilteredOut(unit, trackedAid, _DISPEL_SCAN_FILTER) ~= false then
                    return finishFull()
                end
                return false, true
            end
        end
    end

    if trackedAid then
        return false, false
    end

    local added = updateInfo.addedAuras
    if not added then
        return false, false
    end

    for i = 1, #added do
        local aura = added[i]
        local aid = aura and aura.auraInstanceID
        if aid then
            local dispellable
            if C_UnitAuras_IsAuraFilteredOut then
                dispellable = C_UnitAuras_IsAuraFilteredOut(unit, aid, _DISPEL_SCAN_FILTER) == false
            else
                local dn = aura.dispelName
                dispellable = not (issecretvalue and issecretvalue(dn))
                    and type(dn) == "string" and dn ~= "" and dn ~= "None"
            end
            if dispellable then
                local dn = aura.dispelName
                if not (issecretvalue and issecretvalue(dn)) and type(dn) == "string" and dn ~= "" and dn ~= "None" then
                    f._msufGFDispelType = dn
                else
                    f._msufGFDispelType = "DISPELLABLE"
                end
                f._msufGFDispelAuraID = aid
                f._msufGFPrevDispelAuraID = aid
                f._msufGFDispelKnown = true
                if C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and GF and GF._sharedDispelColorCurve then
                    f._msufGFDispelColorObj = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, GF._sharedDispelColorCurve)
                    f._msufGFDispelColorRev = _G.MSUF_ColorStyleRevision or 0
                else
                    f._msufGFDispelColorObj = nil
                    f._msufGFDispelColorRev = nil
                end
                local colorRev = _G.MSUF_ColorStyleRevision or 0
                f._msufGFColorStyleRevision = colorRev
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
                return true, true
            end
        end
    end

    return false, false
end

------------------------------------------------------------------------
-- Target indicator border
------------------------------------------------------------------------
local function UpdateTargetIndicator(f, unit)
    local border = f._msufGFTargetBorder
    if not border then return end
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end

    if not (c and c.targetEn) or not unit then
        border:Hide()
        return
    end

    local isTarget = UnitIsUnit and _UnsecretBool(UnitIsUnit(unit, "target")) == true
    if isTarget then
        _applyHighlightBorderStyle(border, nil,
            c.tgtSize or 2,
            c.tgtOfs or 0,
            c.tgtTex,
            c.tgtLayer or "DEFAULT",
            c.tgtR or 1,
            c.tgtG or 1,
            c.tgtB or 1, 1)
        border:Show()
    else
        border:Hide()
    end
end

------------------------------------------------------------------------
-- Status text helpers (module-level â€” zero closure allocation)
------------------------------------------------------------------------
local function _GF_HideHealthText(f)
    if f.textLeftFS then f.textLeftFS:SetText(""); f.textLeftFS:Hide() end
    if f.textCenterFS then f.textCenterFS:SetText(""); f.textCenterFS:Hide() end
    if f.textRightFS then f.textRightFS:SetText(""); f.textRightFS:Hide() end
    f._msufGFCachedTL, f._msufGFCachedTC, f._msufGFCachedTR = nil, nil, nil
    if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:Hide() end
    f._msufGFCachedPTL, f._msufGFCachedPTC, f._msufGFCachedPTR = nil, nil, nil
end

local function _GF_RestoreHealthText(f, conf)
    local hpTextOn = conf.showHPText ~= false
    local tl = hpTextOn and (conf.textLeft  or "NONE") or "NONE"
    local tc = hpTextOn and (conf.textCenter or "NONE") or "NONE"
    local tr = hpTextOn and (conf.textRight or "NONE") or "NONE"
    if f.textLeftFS  and tl ~= "NONE" then f.textLeftFS:Show() end
    if f.textCenterFS and tc ~= "NONE" then f.textCenterFS:Show() end
    if f.textRightFS and tr ~= "NONE" then f.textRightFS:Show() end
    if (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(f._msufGFKind or "party", conf)) then
        local ptl = conf.powerTextLeft   or "NONE"
        local ptc = conf.powerTextCenter  or "NONE"
        local ptr = conf.powerTextRight   or "NONE"
        if f.powerTextLeftFS  and ptl ~= "NONE" then f.powerTextLeftFS:Show() end
        if f.powerTextCenterFS and ptc ~= "NONE" then f.powerTextCenterFS:Show() end
        if f.powerTextRightFS and ptr ~= "NONE" then f.powerTextRightFS:Show() end
    end
end

------------------------------------------------------------------------
-- Status text: AFK / DND (red, GF-owned pipeline)
-- Status state encoding: 0=normal, 1=offline, 2=dead, 3=ghost, 4=afk, 5=dnd
------------------------------------------------------------------------
function GF.GetStatusIndicatorFlags()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local db = gen and gen.statusIndicators
    if type(db) ~= "table" then
        local getDB = _G.MSUF_GetStatusIndicatorDB
        db = (type(getDB) == "function") and getDB() or nil
    end
    if type(db) ~= "table" then
        return false, false, true, true
    end
    return db.showAFK == true, db.showDND == true, db.showDead == true, db.showGhost == true
end

local STATUS_TEXT_LAYOUTS = {
    [1] = { enKey = "statusText",      sizeKey = "statusTextSize",      anchorKey = "statusTextAnchor",      xKey = "statusOffsetX",      yKey = "statusOffsetY",      layerKey = "statusTextLayer",      defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [2] = { enKey = "statusText",      sizeKey = "statusTextSize",      anchorKey = "statusTextAnchor",      xKey = "statusOffsetX",      yKey = "statusOffsetY",      layerKey = "statusTextLayer",      defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [3] = { enKey = "statusGhostText", sizeKey = "statusGhostTextSize", anchorKey = "statusGhostTextAnchor", xKey = "statusGhostOffsetX", yKey = "statusGhostOffsetY", layerKey = "statusGhostTextLayer", defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [4] = { enKey = "statusAFKText",   sizeKey = "statusAFKTextSize",   anchorKey = "statusAFKTextAnchor",   xKey = "statusAFKOffsetX",   yKey = "statusAFKOffsetY",   layerKey = "statusAFKTextLayer",   defAnchor = "CENTER", defSize = 14, defLayer = 7 },
    [5] = { enKey = "statusAFKText",   sizeKey = "statusAFKTextSize",   anchorKey = "statusAFKTextAnchor",   xKey = "statusAFKOffsetX",   yKey = "statusAFKOffsetY",   layerKey = "statusAFKTextLayer",   defAnchor = "CENTER", defSize = 14, defLayer = 7 },
}

function GF.EnsureStatusTextLayer(f, conf, state)
    local s = STATUS_TEXT_LAYOUTS[state]
    local layer = tonumber(s and conf and conf[s.layerKey]) or (s and s.defLayer) or 7
    if layer < 0 then layer = 0 elseif layer > 30 then layer = 30 end

    local st = f and (f._msufGFStatusText or f.statusIndicatorText)
    if not st then return nil, layer end

    local parent = f.barGroup or f.health or f
    local layerFrame = f.statusTextLayer
    if not layerFrame and _G.CreateFrame and not (InCombatLockdown and InCombatLockdown()) then
        layerFrame = _G.CreateFrame("Frame", nil, parent)
        layerFrame:EnableMouse(false)
        if layerFrame.SetClipsChildren then layerFrame:SetClipsChildren(false) end
        f.statusTextLayer = layerFrame
    end

    if layerFrame then
        if layerFrame.GetParent and layerFrame:GetParent() ~= parent
            and layerFrame.SetParent and not (InCombatLockdown and InCombatLockdown())
        then
            layerFrame:SetParent(parent)
        end
        if layerFrame.ClearAllPoints then
            layerFrame:ClearAllPoints()
            layerFrame:SetAllPoints(parent)
        end
        if layerFrame.SetFrameLevel then
            if GF.SetFrameLayerLevel then
                GF.SetFrameLayerLevel(layerFrame, f, layer, 7)
            else
                local base = f.health or f.barGroup or f
                local baseLvl = base.GetFrameLevel and base:GetFrameLevel() or 0
                layerFrame:SetFrameLevel(baseLvl + layer)
            end
        end
        if st.SetParent and st.GetParent and st:GetParent() ~= layerFrame then
            st:SetParent(layerFrame)
        end
    end

    return layerFrame, layer
end

local function IsStatusTextStateEnabled(conf, state)
    local s = STATUS_TEXT_LAYOUTS[state]
    return s and conf and conf[s.enKey] ~= false
end

local function JustifyForStatusAnchor(anchor)
    if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" or anchor == "LEFT" then
        return "LEFT"
    end
    if anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "RIGHT" then
        return "RIGHT"
    end
    return "CENTER"
end

local function ApplyStatusTextStateLayout(f, conf, state)
    local st = f and (f._msufGFStatusText or f.statusIndicatorText)
    local s = STATUS_TEXT_LAYOUTS[state]
    if not (st and conf and s) then return end
    local _, frameLayer = GF.EnsureStatusTextLayer(f, conf, state)

    local kind = f._msufGFKind or "party"
    local fScale = conf._resolvedFrameScale or 1
    local size = tonumber(conf[s.sizeKey]) or s.defSize
    if fScale ~= 1 then
        size = math_max(6, math_floor(size * fScale + 0.5))
    else
        size = math_floor(size + 0.5)
    end
    local fontPath = GF.ResolveFontPath and GF.ResolveFontPath(kind)
    local fontFlags = GF.ResolveFontFlags and GF.ResolveFontFlags(kind)
    if fontPath and st.SetFont then
        local db = _G.MSUF_DB
        local fontKey = db and db.general and db.general.fontKey
        if type(_G.MSUF_SetFontSafe) == "function" then
            _G.MSUF_SetFontSafe(st, fontPath, size, fontFlags or "", fontKey)
        else
            st:SetFont(fontPath, size, fontFlags or "")
        end
    end

    local anchor = conf[s.anchorKey] or s.defAnchor
    local ox = tonumber(conf[s.xKey]) or 0
    local oy = tonumber(conf[s.yKey]) or 0
    if fScale ~= 1 and GF.ScaleValue then
        ox = GF.ScaleValue(ox, fScale)
        oy = GF.ScaleValue(oy, fScale)
    end

    local parent = f.health or f.barGroup or f
    st:ClearAllPoints()
    st:SetPoint(anchor, parent, anchor, ox, oy)
    if st.SetJustifyH then st:SetJustifyH(JustifyForStatusAnchor(anchor)) end
    if st.SetJustifyV then st:SetJustifyV("MIDDLE") end
    if st.SetDrawLayer then
        local sub = frameLayer or s.defLayer
        if sub < 0 then sub = 0 elseif sub > 7 then sub = 7 end
        st:SetDrawLayer("OVERLAY", sub)
    end
end
GF.ApplyStatusTextStateLayout = ApplyStatusTextStateLayout

local function UpdateStatusText(f, unit, forceAway)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local c = f._c
    if c and not c.statusTextEn then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            f._msufGFStatusLayoutState = nil
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            if f.nameText then f.nameText:Show() end
        end
        return
    end
    local showAFK, showDND, showDead, showGhost
    local deadTextEnabled, ghostTextEnabled, awayTextEnabled
    if c then
        showAFK, showDND = c.statusShowAFK, c.statusShowDND
        showDead, showGhost = c.statusShowDead, c.statusShowGhost
        deadTextEnabled = c.statusDeadTextEn
        ghostTextEnabled = c.statusGhostTextEn
        awayTextEnabled = c.statusAwayTextEn
    else
        showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
        deadTextEnabled = IsStatusTextStateEnabled(conf, 2)
        ghostTextEnabled = IsStatusTextStateEnabled(conf, 3)
        awayTextEnabled = IsStatusTextStateEnabled(conf, 4)
    end

    if not unit or not UnitExists(unit) then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
            f._msufGFStatusLayoutState = nil
            st:SetText("")
            st:Hide()
            _GF_RestoreHealthText(f, conf)
            if f.nameText then f.nameText:Show() end
        end
        return
    end

    -- Determine new status state
    local newState = 0
    local connected = UnitIsConnected(unit)
    if issecretvalue and issecretvalue(connected) then connected = true end

    if connected == false and showDead and deadTextEnabled then
        newState = 1
    else
        -- Secret-safe (12.0): UnitIsDeadOrGhost can return secret booleans for
        -- non-self units. Prefer the more specific APIs and use HP==0 as a
        -- final non-secret fallback so dead group members do not look alive
        -- after both players are dead and range data starts updating again.
        local ghost = false
        if UnitIsGhost then
            local g = UnitIsGhost(unit)
            if not (issecretvalue and issecretvalue(g)) and g then ghost = true end
        end

        local isDead = false
        local unitIsDead = _G.UnitIsDead
        if unitIsDead then
            local d = unitIsDead(unit)
            if not (issecretvalue and issecretvalue(d)) and d then isDead = true end
        end
        if not isDead and UnitIsDeadOrGhost then
            local dog = UnitIsDeadOrGhost(unit)
            if not (issecretvalue and issecretvalue(dog)) and dog then isDead = true end
        end
        if not isDead and UnitHealth then
            local hp = UnitHealth(unit)
            if not (issecretvalue and issecretvalue(hp)) and hp == 0 then isDead = true end
        end

        if ghost then
            if showGhost and ghostTextEnabled then
                newState = 3
            elseif not showGhost and showDead and deadTextEnabled then
                newState = 2
            end
        elseif isDead and showDead and deadTextEnabled then
            newState = 2
        else
            if awayTextEnabled and (showAFK or showDND) then
                local getAway = _G.MSUF_GetCachedAwayStatus
                if getAway then
                    local force = forceAway == true
                    local rev = ns and ns._msufAwayRevision or 0
                    local away
                    if not force
                        and f._msufGFAwayStatusUnit == unit
                        and f._msufGFAwayStatusRev == rev
                        and f._msufGFAwayStatusAFK == showAFK
                        and f._msufGFAwayStatusDND == showDND
                    then
                        away = f._msufGFAwayStatusFlags or 0
                    end
                    if away == nil then
                        away = getAway(unit, showAFK, showDND, force)
                        f._msufGFAwayStatusUnit = unit
                        f._msufGFAwayStatusRev = rev
                        f._msufGFAwayStatusAFK = showAFK
                        f._msufGFAwayStatusDND = showDND
                        f._msufGFAwayStatusFlags = away or 0
                    end
                    if showAFK and (away == 1 or away == 3) then
                        newState = 4
                    elseif showDND and (away == 2 or away == 3) then
                        newState = 5
                    end
                else
                    if showAFK and UnitIsAFK then
                        local afk = UnitIsAFK(unit)
                        if not (issecretvalue and issecretvalue(afk)) and afk == true then
                            newState = 4
                        end
                    end
                    if newState == 0 and showDND and UnitIsDND then
                        local dnd = UnitIsDND(unit)
                        if not (issecretvalue and issecretvalue(dnd)) and dnd == true then
                            newState = 5
                        end
                    end
                end
            end
        end
    end

    if newState ~= 0 and f._msufGFStatusLayoutState ~= newState then
        ApplyStatusTextStateLayout(f, conf, newState)
        f._msufGFStatusLayoutState = newState
    end

    -- Diff-gate: only update text/colors when state actually changes
    if newState == f._msufGFStatusState then return end
    f._msufGFStatusState = newState

    if newState == 0 then
        f._msufGFStatusLayoutState = nil
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("")
        st:Hide()
        _GF_RestoreHealthText(f, conf)
    elseif newState == 1 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 2 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 3 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(true) end
        st:SetText("GHOST")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 4 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 5 then
        if st.SetIgnoreParentAlpha then st:SetIgnoreParentAlpha(false) end
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    end
end

------------------------------------------------------------------------
-- Health color (GF-independent barMode, then global fallback)
-- Optional hp / hpMax parameters: when the caller (e.g. dispatchHealthFull)
-- already has fresh values, pass them to skip the GRADIENT-no-calc fallback's
-- duplicate UnitHealth/UnitHealthMax C-calls. nil/omitted â†’ fetch as before.
------------------------------------------------------------------------
local function ApplyHealthColor(f, kind, unit, hp, hpMax)
    if not f.health then return end
    if f._msufSIHealthColorR then
        f.health:SetStatusBarColor(f._msufSIHealthColorR, f._msufSIHealthColorG, f._msufSIHealthColorB, 1)
        f._msufGFHCStamp = nil
        return
    end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    local mode = c.hcMode

    if mode == "dark" then
        if f._msufGFHCStamp ~= "dark" then
            f._msufGFHCStamp = "dark"
            f.health:SetStatusBarColor(c.darkR, c.darkG, c.darkB, 1)
        end
        return
    end
    if mode == "unified" then
        if f._msufGFHCStamp ~= "unified" then
            f._msufGFHCStamp = "unified"
            f.health:SetStatusBarColor(c.unifiedR, c.unifiedG, c.unifiedB, 1)
        end
        return
    end
    if mode == "CLASS" and unit then
        local cls = f._msufGFClass
        if not cls then local _; _, cls = UnitClass(unit); f._msufGFClass = cls end
        if cls then
            if f._msufGFHCStamp == cls then return end
            f._msufGFHCStamp = cls
            local fn = c.classFn
            if type(fn) == "function" then
                local r, g, b = fn(cls)
                if r then f.health:SetStatusBarColor(r, g, b, 1); return end
            end
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if cc then f.health:SetStatusBarColor(cc.r, cc.g, cc.b, 1); return end
        end
    end
    if mode == "GRADIENT" and unit then
        -- C-side path: ColorCurve + calculator â†’ fully secret-safe, zero Lua math
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
                return
            end
        end
        -- Fallback: Lua-side (non-secret values only). Reuse caller-provided
        -- hp/hpMax if available â€” avoids redundant UnitHealth/UnitHealthMax
        -- calls when dispatchHealthFull already has fresh values.
        if hp == nil then hp = UnitHealth(unit) end
        if hpMax == nil then hpMax = UnitHealthMax(unit) end
        if issecretvalue and (issecretvalue(hp) or issecretvalue(hpMax)) then
            if f._msufGFHCStamp ~= "grad_secret" then
                f._msufGFHCStamp = "grad_secret"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            end
            return
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
            end
        else
            if f._msufGFHCStamp ~= "grad_default" then
                f._msufGFHCStamp = "grad_default"
                f.health:SetStatusBarColor(0.2, 0.8, 0.2, 1)
            end
        end
        return
    end
    if f._msufGFHCStamp ~= "custom" then
        f._msufGFHCStamp = "custom"
        f.health:SetStatusBarColor(c.customR, c.customG, c.customB, 1)
    end
end

local function ApplyHealthAlphaAfterColor(f, kind)
    if not f or not f.health or not GF.ApplyHealthBarAlpha then return end
    kind = kind or f._msufGFKind or "party"
    if f._msufGFHealthAlphaDynamic == true then
        GF.ApplyHealthBarAlpha(f, kind)
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
        GF.ApplyHealthBarAlpha(f, kind)
    end
end

local function ApplyHealthColorWithAlpha(f, kind, unit, hp, hpMax)
    ApplyHealthColor(f, kind, unit, hp, hpMax)
    ApplyHealthAlphaAfterColor(f, kind)
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

------------------------------------------------------------------------
-- Offline box hiding
-- hideOfflineEnabled gates the feature completely. When enabled, keep the
-- normal offline state visible for N seconds, then hide the visual box until
-- the unit reconnects. The secure click button remains owned by
-- SecureGroupHeader; only non-secure visual children are hidden.
------------------------------------------------------------------------
do
local function _GF_BumpOfflineToken(f)
    local token = (f._msufGFOfflineHideToken or 0) + 1
    f._msufGFOfflineHideToken = token
    return token
end

local function _GF_CancelOfflineHideTimer(f)
    local timer = f and f._msufGFOfflineHideTimer
    if timer and timer.Cancel then
        timer:Cancel()
    end
    if f then
        f._msufGFOfflineHideTimer = nil
        f._msufGFOfflineHideDueAt = nil
    end
end

local function _GF_SetOfflineHidden(f, hidden)
    if not f then return end
    hidden = hidden and true or false
    if f._msufGFOfflineHidden == hidden then return end
    f._msufGFOfflineHidden = hidden or nil

    if hidden then
        GF._offlineHideRuntimeActive = true
        if f.barGroup then f.barGroup:Hide() end
        if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
        if f._msufGFHighlightBorder then f._msufGFHighlightBorder:Hide() end
        if f._msufGFDispelOverlay then f._msufGFDispelOverlay:Hide() end
        if f._msufGFDebuffStripe then f._msufGFDebuffStripe:Hide() end
        if GF.HideFrameAuras then GF.HideFrameAuras(f) end
        if GF.HideSpellIndicators then GF.HideSpellIndicators(f) end
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
    else
        if f.barGroup then f.barGroup:Show() end
    end
end

local function _GF_ClearOfflineHiddenFrame(f)
    if not f then return end
    if not f._msufGFOfflineHidden and not f._msufGFOfflineKey
        and not f._msufGFOfflineSince and not f._msufGFOfflineHideDueAt
        and not f._msufGFOfflineHideTimer
    then
        return
    end
    _GF_CancelOfflineHideTimer(f)
    _GF_BumpOfflineToken(f)
    f._msufGFOfflineKey = nil
    f._msufGFOfflineSince = nil
    f._msufGFOfflineHideDueAt = nil
    _GF_SetOfflineHidden(f, false)
    if GF.RefreshOfflineHideRuntimeFlag then GF.RefreshOfflineHideRuntimeFlag() end
end

local function _GF_GetOfflineDelay(f, kind)
    local c = f and f._c
    local delay = c and c.hideOfflineDelay
    if delay == nil and GF.GetConf then
        local conf = GF.GetConf(kind or (f and f._msufGFKind) or "party")
        delay = (conf and conf.hideOfflineEnabled == true) and conf.hideOfflineDelay or 0
    end
    delay = tonumber(delay) or 0
    if delay < 0 then delay = 0 elseif delay > 120 then delay = 120 end
    return delay
end

local function _GF_CanRunOfflineHideNow(f, kind)
    if f and not _RuntimeEnabledForFrame(f) then return false end
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    local c = f and f._c
    if c then return c.hideOfflineCombat == true end
    if GF.GetConf then
        local conf = GF.GetConf(kind or (f and f._msufGFKind) or "party")
        return conf and conf.hideOfflineEnabled == true and conf.hideOfflineInCombat == true or false
    end
    return false
end

local function _GF_ScheduleOfflineHide(f, unit, dueAt, remaining)
    if not (f and dueAt) then return end
    if not _GF_CanRunOfflineHideNow(f) then return end
    if f._msufGFOfflineHideDueAt == dueAt then return end
    _GF_CancelOfflineHideTimer(f)
    local token = _GF_BumpOfflineToken(f)
    f._msufGFOfflineHideDueAt = dueAt
    remaining = tonumber(remaining) or 0
    if remaining < 0 then remaining = 0 end
    local function run()
        if not f or f._msufGFOfflineHideToken ~= token then return end
        f._msufGFOfflineHideTimer = nil
        if not _GF_CanRunOfflineHideNow(f) then return end
        if GF.UpdateOfflineHiddenFrame then GF.UpdateOfflineHiddenFrame(f, f.unit or unit, true) end
    end
    if C_Timer and C_Timer.NewTimer then
        GF._offlineHideRuntimeActive = true
        f._msufGFOfflineHideTimer = C_Timer.NewTimer(remaining, run)
    else
        GF._offlineHideRuntimeActive = true
        _MSUF_ScheduleDelayOnce("GF_OFFLINE_HIDE:" .. tostring(f) .. ":" .. tostring(token), remaining, run)
    end
end

function GF.UpdateOfflineHiddenFrame(f, unit, force)
    if not f then return false end
    if not _RuntimeEnabledForFrame(f) then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end
    local kind = f._msufGFKind or "party"
    if not _GF_CanRunOfflineHideNow(f, kind) then return false end
    if f._msufGFPreviewActive then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    unit = unit or f.unit
    local delay = _GF_GetOfflineDelay(f, kind)
    if delay <= 0 or not unit or not UnitExists(unit) then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    local connected = UnitIsConnected and UnitIsConnected(unit)
    if issecretvalue and connected ~= nil and issecretvalue(connected) then connected = true end
    if connected ~= false then
        _GF_ClearOfflineHiddenFrame(f)
        return false
    end

    local guidFn = _G.UnitGUID
    local key = unit
    if guidFn then
        local guid = guidFn(unit)
        if guid and not (issecretvalue and issecretvalue(guid)) then key = guid end
    end

    local now = (GetTime and GetTime()) or 0
    if f._msufGFOfflineKey ~= key then
        _GF_BumpOfflineToken(f)
        f._msufGFOfflineKey = key
        f._msufGFOfflineSince = now
        f._msufGFOfflineHideDueAt = nil
        _GF_SetOfflineHidden(f, false)
    elseif not f._msufGFOfflineSince then
        f._msufGFOfflineSince = now
    end

    local dueAt = (f._msufGFOfflineSince or now) + delay
    if force == true or now >= dueAt then
        f._msufGFOfflineHideDueAt = dueAt
        _GF_SetOfflineHidden(f, true)
        return true
    end

    _GF_SetOfflineHidden(f, false)
    _GF_ScheduleOfflineHide(f, unit, dueAt, dueAt - now)
    return false
end

GF.ResetOfflineHiddenFrame = _GF_ClearOfflineHiddenFrame

function GF.RefreshOfflineHideEnabledFlag()
    if not GF.GetConf then
        GF._offlineHideAnyEnabled = false
        return false
    end
    local party = GF.GetConf("party")
    local raid = GF.GetConf("raid")
    local mythic = GF.GetConf("mythicraid")
    local enabled = (party and party.enabled == true and party.hideOfflineEnabled == true)
        or (raid and raid.enabled == true and raid.hideOfflineEnabled == true)
        or (mythic and mythic.enabled == true and mythic.hideOfflineEnabled == true)
    GF._offlineHideCombatAnyEnabled = ((party and party.enabled == true and party.hideOfflineEnabled == true and party.hideOfflineInCombat == true)
        or (raid and raid.enabled == true and raid.hideOfflineEnabled == true and raid.hideOfflineInCombat == true)
        or (mythic and mythic.enabled == true and mythic.hideOfflineEnabled == true and mythic.hideOfflineInCombat == true)) or false
    GF._offlineHideAnyEnabled = enabled or false
    return GF._offlineHideAnyEnabled
end

local function _GF_ForEachOfflineFrame(fn)
    if type(fn) ~= "function" then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f and _RuntimeEnabledForFrame(f) then fn(f) end
        end
    elseif GF.frames then
        for f in pairs(GF.frames) do
            if _RuntimeEnabledForFrame(f) then fn(f) end
        end
    end
end

function GF.RefreshOfflineHideRuntimeFlag()
    local active = false
    _GF_ForEachOfflineFrame(function(f)
        if f and (f._msufGFOfflineHidden or f._msufGFOfflineHideTimer or f._msufGFOfflineHideDueAt) then
            active = true
        end
    end)
    GF._offlineHideRuntimeActive = active or nil
    return active
end

function GF.SuspendOfflineHideForCombat()
    if not GF._offlineHideRuntimeActive then return end
    _GF_ForEachOfflineFrame(function(f)
        if f and not f._msufGFOfflineCombatAllowed
            and (f._msufGFOfflineConfigured or f._msufGFOfflineHidden or f._msufGFOfflineHideTimer)
        then
            _GF_CancelOfflineHideTimer(f)
            _GF_BumpOfflineToken(f)
            _GF_SetOfflineHidden(f, false)
            f._msufGFOfflineActive = nil
        end
    end)
    if GF.RefreshOfflineHideRuntimeFlag then GF.RefreshOfflineHideRuntimeFlag() end
end

function GF.RefreshOfflineHiddenFrames()
    if InCombatLockdown and InCombatLockdown() then return end
    if not (GF.RefreshOfflineHideEnabledFlag and GF.RefreshOfflineHideEnabledFlag()) then return end
    _GF_ForEachOfflineFrame(function(f)
        if f and f.unit and UnitExists(f.unit) then
            if GF.BuildFrameCache then GF.BuildFrameCache(f) end
            if f._msufGFOfflineActive and GF.UpdateOfflineHiddenFrame then
                GF.UpdateOfflineHiddenFrame(f, f.unit)
            end
        end
    end)
end
end

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
        if c.nativeBlizzardDispels then
            if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        else
            local mergedDispel = f._msufGFMergedDispel
            local prevDispel = f._msufGFDispelType
            local dispelAid = f._msufGFDispelAuraID
            local prevAid = f._msufGFPrevDispelAuraID
            local colorRev = _G.MSUF_ColorStyleRevision or 0
            local prevColorRev = f._msufGFColorStyleRevision or 0
            if mergedDispel ~= prevDispel or dispelAid ~= prevAid or colorRev ~= prevColorRev then
                f._msufGFDispelType = mergedDispel
                f._msufGFPrevDispelAuraID = dispelAid
                f._msufGFColorStyleRevision = colorRev
                _GF_RefreshBorder(f, unit)
                _GF_ApplyDispelOverlay(f)
            end
        end
    else
        if GF.UpdateFrameAuras and not f._msufGFAurasHidden then GF.UpdateFrameAuras(f, unit) end
        if not c.aurasOn then
            if _GF_ClearNativeSuppressedDispel and (
                f._msufGFDispelType or f._msufGFMergedDispel or f._msufGFDispelAuraID
                or f._msufGFPrevDispelAuraID or f._msufGFDispelGlowActive or f._gfPrivContainerOverlayID
            ) then
                _GF_ClearNativeSuppressedDispel(f, unit)
            end
        elseif c.nativeBlizzardDispels then
            if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        elseif c.dispelScan and GF._playerCanDispel then GF._UpdateDispel(f, unit) end
    end
    -- Debuff stripe (UpdateAll always does full refresh)
    if c.dsEn then
        f._msufGFHasAnyDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
        _GF_ApplyDebuffStripe(f)
    else
        -- Feature disabled â€” clear cached presence and hide stripe so the
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

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- oUF-STYLE EVENT SPLIT: Each event only does what changed.
--
-- UNIT_HEALTH (10-50/s):      Bar + Text only. NO calculator, NO overlays.
-- UNIT_MAXHEALTH (~0.5/s):    Full chain (calc + bar + overlays + text).
-- UNIT_HEAL_PREDICTION:       Overlays only (incoming heals changed).
-- UNIT_ABSORB_AMOUNT_CHANGED: Overlays only (absorbs changed).
-- UNIT_HEAL_ABSORB_CHANGED:   Overlays only (heal absorbs changed).
--
-- This eliminates ~60% of Lua work per UNIT_HEALTH event.
-- Before: Calculator + SetMinMax + SetValue + Color + 3Ã—Text
--         + 3Ã—Overlay + HealthFade + StatusText = ~15 ops
-- After:  UnitHealth + SetValue + Text + StatusText = ~5 ops
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

------------------------------------------------------------------------
-- COALESCED TEXT FLUSH â€” batch all dirty GF frames via C_Timer.After(0)
-- Moves 3Ã—FormatHealthText + 6Ã—issecretvalue + UpdateStatusText (4 C-API
-- calls) OUT of the UNIT_HEALTH hot path into a single deferred flush.
-- In a 40-man raid at 50 UNIT_HEALTH/sec/unit = 2000 events/sec, this
-- eliminates ~20 Lua ops per event â†’ ~40 000 ops/sec saved.
------------------------------------------------------------------------
local _gfTextDirtyFrames = {}    -- sparse: f = true (kept for cleanup compatibility)
local _gfTextQueue = {}           -- dense queue avoids pairs() burst during flush
local _gfTextQueued = {}          -- [frame] = true while queued
local _gfTextHead, _gfTextTail = 1, 0
local _gfFlushDirtyText

local function _gfMarkTextDirty(f)
    if not f then return end
    _gfTextDirtyFrames[f] = true
    if not _gfTextQueued[f] then
        _gfTextQueued[f] = true
        _gfTextTail = _gfTextTail + 1
        _gfTextQueue[_gfTextTail] = f
    end
    if not _gfTextQueue.__flushQueued then
        _gfTextQueue.__flushQueued = true
        _MSUF_ScheduleOnce("GF_TEXT_FLUSH", _gfFlushDirtyText)
    end
end

function _gfFlushDirtyText()
    local queue = _gfTextQueue
    local head = _gfTextHead
    local stopTail = _gfTextTail

    while head <= stopTail do
        local f = queue[head]
        queue[head] = nil
        head = head + 1
        if f then
            _gfTextQueued[f] = nil
            _gfTextDirtyFrames[f] = nil
            local unit = f.unit
            if unit and f.health and f:IsVisible() then
                local c = f._c

                -- Health text fallback: only for uncompiled modes (anySlowText)
                if c and c.anySlowText then
                    local hp    = f._msufGFHealthTextValue
                    if hp == nil then hp = UnitHealth(unit) end
                    local hpMax = f._msufGFHealthTextMax or f._msufGFCachedHpMax or UnitHealthMax(unit)
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

                -- Power text (set dirty by dispatchPower lean path)
                if f._msufGFPwTextDirty then
                    f._msufGFPwTextDirty = nil
                    if c and c.anyPowerText then
                        local pw    = f._msufGFPwTextValue
                        if pw == nil then pw = UnitPower(unit) end
                        local pwMax = f._msufGFPwTextMax or f._msufGFCachedPwMax or UnitPowerMax(unit)
                        local iss2 = issecretvalue
                        if f.powerTextLeftFS and c.ptlOn then
                            local sval = GF.FormatPowerText(c.ptl, pw, pwMax, c.pDelim, unit)
                            local cv = f._msufGFCachedPTL
                            if (iss2 and (iss2(sval) or (cv ~= nil and iss2(cv)))) or cv ~= sval then
                                f._msufGFCachedPTL = (iss2 and iss2(sval)) and nil or sval
                                f.powerTextLeftFS:SetText(sval)
                            end
                        end
                        if f.powerTextCenterFS and c.ptcOn then
                            local sval = GF.FormatPowerText(c.ptc, pw, pwMax, c.pDelim, unit)
                            local cv = f._msufGFCachedPTC
                            if (iss2 and (iss2(sval) or (cv ~= nil and iss2(cv)))) or cv ~= sval then
                                f._msufGFCachedPTC = (iss2 and iss2(sval)) and nil or sval
                                f.powerTextCenterFS:SetText(sval)
                            end
                        end
                        if f.powerTextRightFS and c.ptrOn then
                            local sval = GF.FormatPowerText(c.ptr, pw, pwMax, c.pDelim, unit)
                            local cv = f._msufGFCachedPTR
                            if (iss2 and (iss2(sval) or (cv ~= nil and iss2(cv)))) or cv ~= sval then
                                f._msufGFCachedPTR = (iss2 and iss2(sval)) and nil or sval
                                f.powerTextRightFS:SetText(sval)
                            end
                        end
                    end
                end

                if f._msufGFStatusDirty then
                    f._msufGFStatusDirty = nil
                    UpdateStatusText(f, unit)
                end
            end
        end
    end

    -- Snapshot semantics: frames marked dirty by callbacks during this flush
    -- were appended after stopTail. Preserve them for the next frame instead
    -- of extending this flush or dropping them in the reset below.
    local liveTail = _gfTextTail
    if liveTail >= head then
        local writeIdx = 0
        for i = head, liveTail do
            local f = queue[i]
            queue[i] = nil
            if f then
                writeIdx = writeIdx + 1
                queue[writeIdx] = f
            end
        end
        _gfTextHead, _gfTextTail = 1, writeIdx
        if writeIdx > 0 then
            queue.__flushQueued = true
            _MSUF_ScheduleOnce("GF_TEXT_FLUSH", _gfFlushDirtyText)
        else
            queue.__flushQueued = nil
        end
    else
        _gfTextHead, _gfTextTail = 1, 0
        queue.__flushQueued = nil
    end
end
-- Expose for manual flush (Options live-preview, unit show, etc.)
GF._FlushDirtyText = _gfFlushDirtyText
GF._TextDirtyFrames = _gfTextDirtyFrames
GF._MarkTextDirty = _gfMarkTextDirty

------------------------------------------------------------------------
-- LEAN PATH: UNIT_HEALTH (hottest: 10-50/s per unit, Ã—40 in raids)
--
-- oUF-style: absolute minimum work per event.
--   1. UnitHealth(unit)             â€” 1 C-call (secret)
--   2. bar:SetValue(hp)             â€” 1 C-call (secret-safe)
--   3. Text/status refresh only when needed
--   4. Color (GRADIENT only)        â€” other modes stamp-gated elsewhere
--   5. Dirty flag for text+status   â€” coalesced flush next frame
--
-- REMOVED from hot path (vs. previous):
--   â€¢ UnitHealthMax()        â€” cached from UNIT_MAXHEALTH/init
--   â€¢ SetMinMaxValues()      â€” only on UNIT_MAXHEALTH
--   â€¢ 3Ã—FormatHealthText     â€” coalesced text flush
--   â€¢ 6Ã—issecretvalue        â€” coalesced text flush
--   â€¢ UpdateStatusText       â€” coalesced (AFK/DND cached; refreshed on flag events)
--   â€¢ Non-gradient health color â€” stamp-gated outside the lean path
------------------------------------------------------------------------
local function dispatchHealthLean(f, unit)
    local bar = f.health
    if not bar then return end
    local c = f._c

    -- 1 C-call â†’ secret value â†’ C-side SetValue
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

    -- Dispel overlay health sync ("current health only" â€” secret-safe SetValue)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then dov:SetValue(hp) end

    -- Compiled fast text: pre-resolved closures call C-side directly.
    -- ~0.3Î¼s/slot (vs 7.5Î¼s with FormatHealthText). Zero mode dispatch,
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
-- FULL PATH: UNIT_MAXHEALTH (rare â€” ~0.5/s)
-- Calculator â†’ bar + text + ALL overlays. Full refresh.
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

    -- Dispel overlay health sync ("current health only" â€” secret-safe)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then
        dov:SetMinMaxValues(0, hpMax)
        dov:SetValue(hp)
    end

    -- Color (full apply on maxHP change â€” handles unit-type transitions).
    -- Pass hp/hpMax through so the GRADIENT-no-calc fallback inside
    -- ApplyHealthColor doesn't re-fetch them.
    ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", unit, hp, hpMax)

    -- Text: prefer compiled closures (oUF-style C-side dispatch, ~0.3Âµs/slot)
    -- over FormatHealthText (~7.5Âµs/slot). Falls back to FormatHealthText only
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
    local ihBar = f.incomingHealBar
    if ihBar and c and c.healPredEn == false then
        ihBar:SetMinMaxValues(0, 1)
        ihBar:SetValue(0)
        if ihBar:IsShown() then ihBar:Hide() end
    end
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
            if c.healPredEn ~= false then
                local v = calc:GetIncomingHeals()
                if v ~= nil then ihBar:SetMinMaxValues(0, hpMax); ihBar:SetValue(v); if not ihBar:IsShown() then ihBar:Show() end
                else if ihBar:IsShown() then ihBar:Hide() end end
            else ihBar:SetMinMaxValues(0, 1); ihBar:SetValue(0); if ihBar:IsShown() then ihBar:Hide() end end
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
-- Calculator â†’ overlay bars ONLY. No HP bar, no text, no color.
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

    local ihBar = f.incomingHealBar
    local abBar = f.absorbBar
    local haBar = f.healAbsorbBar
    local ihEnabled = ihBar and c.healPredEn ~= false
    local abEnabled = abBar and c.absorbEn
    local haEnabled = haBar and c.healAbsorbEn ~= false
    if ihBar and not ihEnabled then GF._ClearOverlayBar(ihBar) end

    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if not (ihEnabled or abEnabled or haEnabled or absorbTestMode or f._msufGFAbsorbTestActive) then
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

    if absorbTestMode then return end

    if ihEnabled then
        GF._SetOverlayBarValue(ihBar, hpMax, calc:GetIncomingHeals())
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
-- Show/hide: issecretvalue(val) â†’ secret = Show (non-nil means has value).
-- Colors read from global MSUF_DB.general (same keys as main UF overlays).
--
-- Absorb enable: read from MSUF_DB.general (tied to Bars menu).
-- Heal prediction enable: read from GF conf (tied to GF Options menu).
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

------------------------------------------------------------------------
-- Absorb anchoring: apply SetReverseFill based on general.absorbAnchorMode
-- Mode 1: left anchor (fill Lâ†’R)   absorbReverse=false
-- Mode 2: right anchor (fill Râ†’L)  absorbReverse=true  (DEFAULT)
-- Mode 3: follow HP edge (clipped to bar)
-- Mode 4: follow HP edge + overflow (extends beyond bar)
-- Mode 5: reverse from max         absorbReverse=true (normal HP bar)
------------------------------------------------------------------------
local function _GF_ApplyAbsorbAnchor(f)
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
            if f._msufGFAbsorbAnchorStamp == mode and f._msufGFAbsorbFollowActive
               and f._msufGFAbsorbFollowRF == hpReverse and f._msufGFAbsorbFollowW == w then
                return
            end
            f._msufGFAbsorbAnchorStamp = mode
            f._msufGFAbsorbFollowActive = true
            f._msufGFAbsorbFollowRF = hpReverse
            f._msufGFAbsorbFollowW = w

            local isOverflow = (mode == 4)

            -- Clip frame (mode 3 only â€” prevents absorb extending beyond bar)
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
                    f.absorbBar:SetPoint("TOPRIGHT", hpTex, "TOPLEFT", 0, 0)
                    f.absorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMLEFT", 0, 0)
                    f.absorbBar:SetReverseFill(true)
                else
                    f.absorbBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
                    f.absorbBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
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
    if f.incomingHealBar and f.incomingHealBar.SetReverseFill then
        f.incomingHealBar:SetReverseFill(false)
    end
    f._msufGFAbsorbAnchorStamp = mode
    f._msufGFAbsorbFollowRF    = (mode == 5) and hpReverse or nil
    f._msufGFAbsorbFollowW     = nil
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

dispatchIncomingHeal = function(f, unit, calc, hp, hpMax)
    local bar = f.incomingHealBar
    if not bar then return end
    -- PERF: use pre-cached healPredEn from BuildFrameCache (was GF.GetConf + DB read per call)
    local c = f._c
    if c and c.healPredEn == false then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        if bar:IsShown() then bar:Hide() end
        return
    end
    -- Test mode: fixed values (same as main UF preview)
    local absorbTestMode = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
        and _GF_ShouldShowAbsorbTextureTestForFrame(f) or false
    if absorbTestMode then
        f._msufGFAbsorbTestActive = true
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(20)
        if not bar:IsShown() then bar:Show() end
        return
    end
    if not unit or not UnitExists(unit) then if bar:IsShown() then bar:Hide() end; return end
    if not hpMax then
        hpMax = (calc and calc.GetMaximumHealth) and calc:GetMaximumHealth() or UnitHealthMax(unit)
    end
    local val
    if calc and calc.GetIncomingHeals then
        val = calc:GetIncomingHeals()
    elseif UnitGetIncomingHeals then
        val = UnitGetIncomingHeals(unit)
    end
    if val == nil then if bar:IsShown() then bar:Hide() end; return end
    local valSecret = issecretvalue and issecretvalue(val)
    if not valSecret then
        local n = tonumber(val) or 0
        if n <= 0 then if bar:IsShown() then bar:Hide() end; return end
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
    if not bar:IsShown() then bar:Show() end
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
    dispatchIncomingHeal(f, unit, calc, hp, hpMax)
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

    -- Coalesced power text: dirty flag â†’ flush next frame
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
    -- name resolution (Unknown â†’ real). A full refresh is the only correct
    -- path; CTR/party-change events only refresh range fade.
    UNIT_PHASE                        = function(f, u)
        local c = f and f._c
        if c and c.phaseEn then UpdateAll(f, u) else ApplyRangeFade(f, u) end
    end,
    UNIT_CTR_OPTIONS                  = function(f, u) ApplyRangeFade(f, u) end,
    UNIT_OTHER_PARTY_CHANGED          = function(f, u) ApplyRangeFade(f, u) end,
}

------------------------------------------------------------------------
-- Per-frame OnEvent handler
-- oUF-STYLE: Each event dispatches ONLY to the handler that needs it.
-- UNIT_HEALTH â†’ lean path (bar + text only, NO calc/overlays)
-- UNIT_MAXHEALTH â†’ full path (calc + bar + overlays + text)
-- UNIT_HEAL_PREDICTION/ABSORB â†’ overlays only
------------------------------------------------------------------------
_RuntimeEnabledForFrame = function(f)
    if not f then return false end
    if f._msufGFPreviewActive then return true end
    if f.unit and UnitExists and UnitExists(f.unit) and f.IsVisible and f:IsVisible() then
        return true
    end
    local kind = f._msufGFKind or (GF.frames and GF.frames[f]) or "party"
    return not (GF.IsKindEnabled and not GF.IsKindEnabled(kind))
end

local function GF_OnEvent(self, event, unit, ...)
    local u = self and self.unit
    if not u then return end
    if unit ~= nil and unit ~= u then return end

    if self._msufGFEventActive ~= true and not _RuntimeEnabledForFrame(self) then
        if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(self) end
        return
    end
    -- PERF: unified hash-table dispatch. The prior hot-path if-elseif chain
    -- did 6-7 string compares (~1Âµs) before falling through to UNIT_DISPATCH.
    -- A direct table lookup is O(1) (~0.05Âµs). Net win: ~1Âµs per event.
    local fn = UNIT_DISPATCH[event]
    if fn then return fn(self, u, ...) end
end

------------------------------------------------------------------------
-- RegisterUnitEvents / UnregisterUnitEvents (replaces Phase 1 stubs)
------------------------------------------------------------------------
function GF._ShouldRegisterPowerEvents(f, unit, c)
    if not (f and unit and c and c.hasPowerElement) then return false end
    if c.anyPowerText then return true end
    return (GF._PowerBarActiveForUnit and GF._PowerBarActiveForUnit(f, unit, c)) or false
end

function GF.RegisterUnitEvents(f, unit)
    if not (f and unit) then return end
    f._msufGFFullPending = nil

    if not _RuntimeEnabledForFrame(f) then
        if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(f) end
        f._msufGFRegUnit = nil
        f._msufGFRegBits = nil
        f._msufGFEventActive = nil
        return
    end

    if not f._c then GF.BuildFrameCache(f) end
    local c = f._c
    local powerEvents = GF._ShouldRegisterPowerEvents(f, unit, c)

    -- Diff-gate: skip if same unit and same event bitmask
    local evBits = c._evBits or 0
    if not powerEvents then
        if c.hasPowerElement then evBits = evBits - 2 end
        if c.powFrequent then evBits = evBits - 2048 end
    end
    if f._msufGFRegUnit == unit and f._msufGFRegBits == evBits and f._msufGFRegEv then
        return
    end
    if f._msufGFRegUnit ~= unit then
        f._msufGFDispelKnown = nil
    end
    f._msufGFRegUnit = unit
    f._msufGFRegBits = evBits
    f._msufGFLastHealthValue = nil

    -- GUIDâ†’frame map (rebuilt on roster change, used for O(1) target/focus scan)
    local guid = _G.UnitGUID and _G.UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        local gmap = GF._guidMap
        if not gmap then gmap = {}; GF._guidMap = gmap end
        gmap[guid] = f
    end

    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
    end
    local regTbl = {}
    f._msufGFRegEv = regTbl

    f:RegisterUnitEvent("UNIT_HEALTH", unit);        regTbl["UNIT_HEALTH"] = true
    f:RegisterUnitEvent("UNIT_MAXHEALTH", unit);     regTbl["UNIT_MAXHEALTH"] = true
    if c.connectionEn then
        f:RegisterUnitEvent("UNIT_CONNECTION", unit); regTbl["UNIT_CONNECTION"] = true
    end
    if c.flagsEn then
        f:RegisterUnitEvent("UNIT_FLAGS", unit); regTbl["UNIT_FLAGS"] = true
    end

    if c.nameEn then
        f:RegisterUnitEvent("UNIT_NAME_UPDATE", unit); regTbl["UNIT_NAME_UPDATE"] = true
    end
    if powerEvents then
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit);  regTbl["UNIT_POWER_UPDATE"] = true
        if c.powFrequent and UnitIsUnit and _UnsecretBool(UnitIsUnit(unit, "player")) == true then
            f:RegisterUnitEvent("UNIT_POWER_FREQUENT", unit); regTbl["UNIT_POWER_FREQUENT"] = true
        end
        f:RegisterUnitEvent("UNIT_MAXPOWER", unit);      regTbl["UNIT_MAXPOWER"] = true
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit);  regTbl["UNIT_DISPLAYPOWER"] = true
    end
    if c.rfEn then
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit); regTbl["UNIT_IN_RANGE_UPDATE"] = true
        f:RegisterUnitEvent("UNIT_CTR_OPTIONS", unit); regTbl["UNIT_CTR_OPTIONS"] = true
        f:RegisterUnitEvent("UNIT_OTHER_PARTY_CHANGED", unit); regTbl["UNIT_OTHER_PARTY_CHANGED"] = true
    end
    if c.needAura then
        f:RegisterUnitEvent("UNIT_AURA", unit); regTbl["UNIT_AURA"] = true
    end
    if c.needThreat then
        f:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", unit); regTbl["UNIT_THREAT_SITUATION_UPDATE"] = true
        f:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", unit);      regTbl["UNIT_THREAT_LIST_UPDATE"] = true
    end
    if c.summonEn then
        f:RegisterUnitEvent("INCOMING_SUMMON_CHANGED", unit); regTbl["INCOMING_SUMMON_CHANGED"] = true
    end
    if c.resEn then
        f:RegisterUnitEvent("INCOMING_RESURRECT_CHANGED", unit); regTbl["INCOMING_RESURRECT_CHANGED"] = true
    end
    if c.phaseEn or c.rfEn then
        f:RegisterUnitEvent("UNIT_PHASE", unit); regTbl["UNIT_PHASE"] = true
    end
    if c.healPredEventEn then
        f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit); regTbl["UNIT_HEAL_PREDICTION"] = true
    end
    if c.absorbEventEn then
        f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_ABSORB_AMOUNT_CHANGED"] = true
    end
    if c.healAbsorbEventEn then
        f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = true
    end

    f:SetScript("OnEvent", GF_OnEvent)
    f._msufGFEventActive = true
end

function GF.UnregisterUnitEvents(f)
    if not f then return end
    if f._msufGFRegEv then
        for ev in pairs(f._msufGFRegEv) do
            if f.UnregisterEvent then f:UnregisterEvent(ev) end
        end
        f._msufGFRegEv = nil
    end
    f:SetScript("OnEvent", nil)
    f._msufGFEventActive = nil
    f._msufGFDispelKnown = nil
    if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
end

------------------------------------------------------------------------
-- Global events (not per-unit)
------------------------------------------------------------------------
local _globalFrame = CreateFrame("Frame")

-- Track current target frame for O(1) TARGET_CHANGED updates
local _gfTargetFrame = nil -- the frame whose unit was last "target"
local _gfFocusFrame  = nil -- the frame whose unit was last "focus"

-- PERF: Coalesced GROUP_ROSTER_UPDATE flush (one iteration per burst instead of N).
local _gfRosterPending = false
local function _gfRosterFlushFrame(f, gmap)
    if not f then return end
    if not _RuntimeEnabledForFrame(f) then return end

    local u = f.unit
    if not (u and UnitExists(u)) then
        f._msufGFRosterGUID = nil
        f._msufGFRosterUnit = nil
        f._msufGFRosterRole = nil
        f._msufGFRosterLeaderState = nil
        f._msufGFIsTarget = nil
        f._msufGFIsFocus = nil
        return
    end

    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end

    local UnitGUID = _G.UnitGUID
    local guid = UnitGUID and UnitGUID(u)
    local hasGUID = guid and not (issecretvalue and issecretvalue(guid))
    if hasGUID then gmap[guid] = f end

    local sameRosterUnit = hasGUID and f._msufGFRosterGUID == guid and f._msufGFRosterUnit == u
    f._msufGFRosterGUID = hasGUID and guid or nil
    f._msufGFRosterUnit = u

    local role
    local roleChanged = false
    if c and c.roleStateEn then
        role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        roleChanged = f._msufGFRosterRole ~= role
        f._msufGFRosterRole = role
    end

    local leaderState
    local leaderChanged = false
    if c and c.leaderEn then
        local isLeader = _G.UnitIsGroupLeader and _G.UnitIsGroupLeader(u)
        local isAssist = _G.UnitIsGroupAssistant and _G.UnitIsGroupAssistant(u)
        leaderState = (isLeader and 1 or 0) + (isAssist and 2 or 0)
        leaderChanged = f._msufGFRosterLeaderState ~= leaderState
        f._msufGFRosterLeaderState = leaderState
    end

    if sameRosterUnit then
        -- Same button/unit after a roster event: skip full visual refresh.
        -- Role, leader/assist and group-number metadata can still change.
        if roleChanged then GF.UpdateRoleIcon(f, u) end
        if leaderChanged then GF.UpdateLeaderIcon(f, u) end
        if (c and c.groupNumberEn)
            or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
            or (f.groupNumberText and f.groupNumberText:IsShown())
        then
            UpdateGroupNumber(f, u)
        end
    else
        dispatchName(f, u)
        ApplyHealthColorWithAlpha(f, f._msufGFKind or "party", u)
        ApplyPowerColor(f, u)
        if c and (c.statusTextEn or f._msufGFStatusState ~= 0) then UpdateStatusText(f, u) end
        if c and c.roleStateEn then GF.UpdateRoleIcon(f, u) end
        if c and c.raidMarkerEn then GF.UpdateRaidMarker(f, u) end
        if c and c.leaderEn then GF.UpdateLeaderIcon(f, u) end
        if (c and c.groupNumberEn)
            or (f._msufGroupNumberFS and f._msufGroupNumberFS:IsShown())
            or (f.groupNumberText and f.groupNumberText:IsShown())
        then
            UpdateGroupNumber(f, u)
        end
    end

    if not sameRosterUnit then
        UpdateTargetIndicator(f, u)
    end
end

local function _gfRosterFlush()
    -- PERF (4.22 Beta hotfix): _gfRosterPending stays TRUE during the entire
    -- flush body. Any GROUP_ROSTER_UPDATE that fires while we are running
    -- (or, paired with the Scheduler tail-snapshot, fires inside any callback
    -- on the same flush iteration) is dropped instead of re-enqueueing.
    -- The flag is cleared at the END of this function -- the next event after
    -- our work is done can schedule the next flush normally.
    local oldTarget = _gfTargetFrame
    local oldFocus  = _gfFocusFrame
    if oldTarget then oldTarget._msufGFIsTarget = nil end
    if oldFocus then oldFocus._msufGFIsFocus = nil end
    _gfTargetFrame = nil
    _gfFocusFrame  = nil

    -- Rebuild GUID->frame map. GUID changes identify the small subset of
    -- frames that need a full visual refresh after roster churn.
    local gmap = GF._guidMap
    if gmap then
        local wipeFn = _G.wipe
        if wipeFn then wipeFn(gmap) else for k in pairs(gmap) do gmap[k] = nil end end
    else
        gmap = {}
        GF._guidMap = gmap
    end

    local list = GF.frameList
    local count = list and #list or 0
    for i = 1, count do
        _gfRosterFlushFrame(list[i], gmap)
    end
    if not list then
        for f in pairs(GF.frames) do
            _gfRosterFlushFrame(f, gmap)
        end
    end

    local UnitGUID = _G.UnitGUID
    if UnitGUID then
        local tGUID = UnitExists("target") and UnitGUID("target")
        if tGUID and not (issecretvalue and issecretvalue(tGUID)) then
            local f = gmap[tGUID]
            if f and f.unit then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
            end
        end

        local fGUID = UnitExists("focus") and UnitGUID("focus")
        if fGUID and not (issecretvalue and issecretvalue(fGUID)) then
            local f = gmap[fGUID]
            if f and f.unit then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
            end
        end
    end

    if oldTarget ~= _gfTargetFrame then
        if oldTarget and oldTarget.unit then
            UpdateTargetIndicator(oldTarget, oldTarget.unit)
            _GF_QuickBorderUpdate(oldTarget)
        end
        if _gfTargetFrame and _gfTargetFrame.unit then
            UpdateTargetIndicator(_gfTargetFrame, _gfTargetFrame.unit)
            _GF_QuickBorderUpdate(_gfTargetFrame)
        end
    end

    if oldFocus ~= _gfFocusFrame then
        if oldFocus and oldFocus.unit then _GF_QuickBorderUpdate(oldFocus) end
        if _gfFocusFrame and _gfFocusFrame.unit then _GF_QuickBorderUpdate(_gfFocusFrame) end
    end

    -- Pending flag cleared at END (see header comment for rationale).
    _gfRosterPending = false
end

-- Exported for consolidated PLAYER_TARGET_CHANGED handler in UFCore
_G.MSUF_GF_OnTargetChanged = function()
    local oldTarget = _gfTargetFrame
    _gfTargetFrame = nil
    if oldTarget and oldTarget.unit then
        oldTarget._msufGFIsTarget = nil
        _GF_QuickBorderUpdate(oldTarget)
    end
    local tGUID = _G.UnitGUID and _G.UnitGUID("target")
    if tGUID and not (issecretvalue and issecretvalue(tGUID)) then
        local gmap = GF._guidMap
        local f = gmap and gmap[tGUID]
        if f and f.unit then
            f._msufGFIsTarget = true
            _gfTargetFrame = f
            _GF_QuickBorderUpdate(f)
        end
    end
end

-- READY_CHECK / READY_CHECK_FINISHED: update ready check icons
-- RAID_TARGET_UPDATE: update raid markers
function GF._AnyGroupConfFlag(key)
    if not key or not GF.GetConf then return false end
    local party = GF.GetConf("party")
    if party and party.enabled == true and party[key] ~= false then return true end
    local raidKind = (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
    local raid = GF.GetConf(raidKind)
    if raid and raid.enabled == true and raid[key] ~= false then return true end
    if raidKind ~= "raid" then
        raid = GF.GetConf("raid")
        if raid and raid.enabled == true and raid[key] ~= false then return true end
    end
    return false
end

do
    local _globalEventBits
    local _baseEventsActive
    local _globalEventSyncQueued = false
    local BASE_EVENTS = {
        "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "BARBER_SHOP_OPEN",
        "BARBER_SHOP_CLOSE",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
    }

    local function SetBaseEvents(active)
        active = active and true or false
        if active == _baseEventsActive then return end
        for i = 1, #BASE_EVENTS do
            local ev = BASE_EVENTS[i]
            if active then
                _globalFrame:RegisterEvent(ev)
            else
                _globalFrame:UnregisterEvent(ev)
            end
        end
        _baseEventsActive = active
    end

    local function _DoSyncGroupGlobalEvents()
        _globalEventSyncQueued = false
        if GF.SyncGroupGlobalEvents then GF.SyncGroupGlobalEvents() end
    end

    function GF.RequestSyncGroupGlobalEvents()
        if _globalEventSyncQueued then return end
        _globalEventSyncQueued = true
        _MSUF_ScheduleOnce("GF_GLOBAL_EVENTS_SYNC", _DoSyncGroupGlobalEvents)
    end

    function GF.SyncGroupGlobalEvents()
        if not _globalFrame then return end

        local anyEnabled = true
        if GF.UpdateAnyEnabledFlag then
            anyEnabled = GF.UpdateAnyEnabledFlag() and true or false
        elseif GF._anyEnabled == false then
            anyEnabled = false
        end

        SetBaseEvents(anyEnabled)

        local ready, raidMarker, leader, flags = false, false, false, false
        if anyEnabled then
            ready = GF._AnyGroupConfFlag("readyCheckIcon")
            raidMarker = GF._AnyGroupConfFlag("raidMarker")
            leader = GF._AnyGroupConfFlag("leaderIcon") or GF._AnyGroupConfFlag("assistIcon")
            local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
            flags = showAFK or showDND or showDead or showGhost
        end

        local bits = 0
        if ready then bits = bits + 1 end
        if raidMarker then bits = bits + 2 end
        if leader then bits = bits + 4 end
        if flags then bits = bits + 8 end
        if bits == _globalEventBits then return end

        local prevBits = _globalEventBits
        _globalEventBits = bits

        local function setEvent(ev, active, bit)
            local wasActive = prevBits and ((prevBits % (bit + bit)) >= bit)
            if wasActive == active then return end
            if active then
                _globalFrame:RegisterEvent(ev)
            else
                _globalFrame:UnregisterEvent(ev)
            end
        end

        setEvent("READY_CHECK", ready, 1)
        setEvent("READY_CHECK_CONFIRM", ready, 1)
        setEvent("READY_CHECK_FINISHED", ready, 1)
        setEvent("RAID_TARGET_UPDATE", raidMarker, 2)
        setEvent("PARTY_LEADER_CHANGED", leader, 4)
        setEvent("PLAYER_FLAGS_CHANGED", flags, 8)
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- OnGlobalEvent: dispatch table + shared frame-iteration helper.
-- (4.22 Beta hotfix.)
--
-- Replaces a long if/elseif chain (8+ string compares per dispatch) with a
-- single hash lookup. The per-event work itself is unchanged -- only the
-- dispatch shape and the duplicated `if list then for i=1,#list else for f
-- in pairs(GF.frames)` boilerplate (5+ identical copies) is consolidated.
--
-- All helpers, per-frame callbacks, and per-event handlers live inside
-- nested do/end blocks so each goes out of scope as soon as its handler
-- closure has captured it. This keeps simultaneously-active locals well
-- below the Lua 5.1 200-per-function limit. The dispatch table and the
-- final OnEvent function are stashed in GF (no new file-scope locals).
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
do
    -- Iterate either GF.frameList (preferred ordered list) or GF.frames
    -- (fallback hash). Forwards extra args to the callback. Mirrors the
    -- shape used 5+ times in the previous OnGlobalEvent body.
    local function _ForEachFrame(cb, ...)
        local list = GF.frameList
        if list then
            for i = 1, #list do
                local f = list[i]
                if _RuntimeEnabledForFrame(f) then cb(f, ...) end
            end
        else
            for f in pairs(GF.frames) do
                if _RuntimeEnabledForFrame(f) then cb(f, ...) end
            end
        end
    end

    local H = {}

    -- Events that don't need per-frame iteration: assign anonymous handlers
    -- directly into the dispatch table (no per-handler local).

    H.PLAYER_REGEN_DISABLED = function(_, event)
        _G.MSUF_InCombat = (event == "PLAYER_REGEN_DISABLED")
        local refreshOfflineAlpha = GF._offlineHideRuntimeActive or GF._offlineHideAnyEnabled
        if event == "PLAYER_REGEN_DISABLED" and GF._offlineHideRuntimeActive and GF.SuspendOfflineHideForCombat then
            GF.SuspendOfflineHideForCombat()
        end
        if refreshOfflineAlpha and GF.RefreshGroupAlphas then GF.RefreshGroupAlphas() end
        if event == "PLAYER_REGEN_ENABLED" and GF._offlineHideAnyEnabled and GF.RefreshOfflineHiddenFrames then
            GF.RefreshOfflineHiddenFrames()
        end
    end
    H.PLAYER_REGEN_ENABLED = H.PLAYER_REGEN_DISABLED

    H.PLAYER_FOCUS_CHANGED = function()
        local oldFocus = _gfFocusFrame
        _gfFocusFrame = nil
        if oldFocus and oldFocus.unit then
            oldFocus._msufGFIsFocus = nil
            _GF_QuickBorderUpdate(oldFocus)
        end
        local fGUID = _G.UnitGUID and UnitExists("focus") and _G.UnitGUID("focus")
        if fGUID and not (issecretvalue and issecretvalue(fGUID)) then
            local gmap = GF._guidMap
            local f = gmap and gmap[fGUID]
            if f and f.unit then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
                _GF_QuickBorderUpdate(f)
            end
        end
    end

    H.GROUP_ROSTER_UPDATE = function()
        -- PERF: Coalesce roster updates. At a world boss, GROUP_ROSTER_UPDATE
        -- fires 0.5/sec with 672Âµs P50 per call (iterates all 40 GF frames Ã— 10 functions).
        -- Multiple updates can fire in the same frame (join + promote + type change).
        -- Coalescing to next-frame eliminates burst spikes in the Blizzard profiler.
        if not _gfRosterPending then
            _gfRosterPending = true
            _gfTargetFrame = nil
            _gfFocusFrame  = nil
            _MSUF_ScheduleOnce("GF_ROSTER_FLUSH", _gfRosterFlush)
        end
    end

    -- READY_CHECK / READY_CHECK_CONFIRM / READY_CHECK_FINISHED share one
    -- handler. The per-frame CB calls GF.UpdateReadyCheck and is freed
    -- when this nested do/end ends.
    do
        local function CB(f, event)
            local c = f and f._c
            if c and c.readyEn and f.unit then GF.UpdateReadyCheck(f, f.unit, event) end
        end
        local h = function(_, event)
            if not GF._AnyGroupConfFlag("readyCheckIcon") then return end
            _ForEachFrame(CB, event)
        end
        H.READY_CHECK           = h
        H.READY_CHECK_CONFIRM   = h
        H.READY_CHECK_FINISHED  = h
    end

    do
        local function CB(f)
            local c = f and f._c
            if c and c.raidMarkerEn and f.unit and UnitExists(f.unit) then GF.UpdateRaidMarker(f, f.unit) end
        end
        H.RAID_TARGET_UPDATE = function()
            if not GF._AnyGroupConfFlag("raidMarker") then return end
            _ForEachFrame(CB)
        end
    end

    do
        local function CB(f)
            local c = f and f._c
            if c and c.leaderEn and f.unit and UnitExists(f.unit) then GF.UpdateLeaderIcon(f, f.unit) end
        end
        H.PARTY_LEADER_CHANGED = function()
            if not (GF._AnyGroupConfFlag("leaderIcon") or GF._AnyGroupConfFlag("assistIcon")) then return end
            _ForEachFrame(CB)
        end
    end

    -- BARBER_SHOP: hoisted constant `KINDS` was a fresh literal each call
    -- (`for _, k in ipairs({"party","raid"})`).
    do
        local KINDS = { "party", "raid" }
        H.BARBER_SHOP_OPEN = function()
            -- hideInClientScene: hide all GF headers when entering barber/dressing room
            for i = 1, #KINDS do
                local headerKind = KINDS[i]
                local confKind = (headerKind == "raid" and GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or headerKind
                local conf = GF.GetConf(confKind)
                if conf.hideInClientScene ~= false then
                    local header = GF.headers and GF.headers[headerKind]
                    if header and not InCombatLockdown() then
                        header._msufGF_clientSceneHidden = true
                        header:SetAlpha(0)
                    end
                end
            end
        end
        H.BARBER_SHOP_CLOSE = function()
            for i = 1, #KINDS do
                local scope = KINDS[i]
                local header = GF.headers and GF.headers[scope]
                if header and header._msufGF_clientSceneHidden then
                    header._msufGF_clientSceneHidden = nil
                    header:SetAlpha(1)
                end
            end
        end
    end

    do
        local function CB(f, changedUnit)
            local c = f and f._c
            if not (c and c.statusTextEn and f.unit and UnitExists(f.unit)) then return end
            local sameUnit = (f.unit == changedUnit)
            if not sameUnit and UnitIsUnit then
                sameUnit = _UnsecretBool(UnitIsUnit(f.unit, changedUnit)) == true
            end
            if sameUnit then
                UpdateStatusText(f, f.unit, true)
            end
        end
        H.PLAYER_FLAGS_CHANGED = function(_, _, changedUnit)
            local showAFK, showDND, showDead, showGhost = GF.GetStatusIndicatorFlags()
            if not (showAFK or showDND or showDead or showGhost) then return end
            if not changedUnit or changedUnit == "" then changedUnit = "player" end
            _ForEachFrame(CB, changedUnit)
        end
    end

    -- Stash dispatch entry on GF (avoids a new file-scope local).
    GF._OnGlobalEvent = function(self, event, ...)
        -- Fix 3: when GF is fully disabled, do nothing. Saves the per-event
        -- dispatch + empty-loop cost across PLAYER_FOCUS_CHANGED, READY_CHECK*,
        -- RAID_TARGET_UPDATE, PARTY_LEADER_CHANGED, GROUP_ROSTER_UPDATE,
        -- BARBER_SHOP_OPEN/CLOSE, PLAYER_FLAGS_CHANGED. Flag is maintained by
        -- RebuildAll and the PLAYER_REGEN_ENABLED retire-deferral path.
        if GF._anyEnabled == false then return end
        local h = H[event]
        if h then h(self, event, ...) end
    end
end

GF.SyncGroupGlobalEvents()
_globalFrame:SetScript("OnEvent", GF._OnGlobalEvent)

------------------------------------------------------------------------
-- Mouseover highlight
------------------------------------------------------------------------
local function _GF_GetHighlightColor()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        local c = gen.highlightColor
        if c and c[1] then return c[1], c[2] or 1, c[3] or 1 end
        if type(c) == "string" then
            local colors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
            if colors and colors[c] then
                local cc = colors[c]
                return cc[1], cc[2], cc[3]
            end
        end
    end
    return 1, 1, 1
end

local function _GF_IsHighlightEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen.highlightEnabled == false then return false end
    return true
end

local function _GF_EnsureHoverLine(hb, key)
    local lines = hb._msufGFHoverLines
    if not lines then
        lines = {}
        hb._msufGFHoverLines = lines
    end
    local t = lines[key]
    if not t and hb.CreateTexture then
        t = hb:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        lines[key] = t
    end
    return t
end

local function _GF_StyleMouseoverHighlight(f, hb)
    if not (f and hb) then return end
    local kind = f._msufGFKind or "party"
    local sz = math_max(1, tonumber(HLVal(kind, "hlHoverSize")) or 1)
    local ofs = tonumber(HLVal(kind, "hlHoverOffset")) or 0
    local r, g, b = _GF_GetHighlightColor()
    local anchor = f.barGroup or f

    if hb.SetBackdrop then hb:SetBackdrop(nil) end
    if hb.SetClipsChildren then hb:SetClipsChildren(false) end

    if hb._msufGFHoverOffset ~= ofs or hb._msufGFHoverSize ~= sz then
        hb._msufGFHoverOffset = ofs
        hb._msufGFHoverSize = sz
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
        hb:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    end

    local ext = ofs + sz
    local top = _GF_EnsureHoverLine(hb, "top")
    local bottom = _GF_EnsureHoverLine(hb, "bottom")
    local left = _GF_EnsureHoverLine(hb, "left")
    local right = _GF_EnsureHoverLine(hb, "right")
    if top then
        top:ClearAllPoints()
        top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -ext, ofs)
        top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", ext, ofs)
        top:SetHeight(sz)
        top:SetVertexColor(r, g, b, 0.7)
        top:Show()
    end
    if bottom then
        bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -ext, -ofs)
        bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", ext, -ofs)
        bottom:SetHeight(sz)
        bottom:SetVertexColor(r, g, b, 0.7)
        bottom:Show()
    end
    if left then
        left:ClearAllPoints()
        left:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -ofs, ext)
        left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -ofs, -ext)
        left:SetWidth(sz)
        left:SetVertexColor(r, g, b, 0.7)
        left:Show()
    end
    if right then
        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", ofs, ext)
        right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", ofs, -ext)
        right:SetWidth(sz)
        right:SetVertexColor(r, g, b, 0.7)
        right:Show()
    end

    if hb.SetFrameLevel and anchor.GetFrameLevel then
        local anchorLevel = anchor:GetFrameLevel() or 0
        local wantLevel = anchorLevel + 3
        local minTextLevel
        local layers = { f.nameTextLayer, f.healthTextLayer, f.powerTextLayer, f.statusTextLayer }
        for i = 1, #layers do
            local layer = layers[i]
            local level = layer and layer.GetFrameLevel and layer:GetFrameLevel()
            if level and (not minTextLevel or level < minTextLevel) then
                minTextLevel = level
            end
        end
        if minTextLevel and wantLevel >= minTextLevel then
            wantLevel = minTextLevel - 1
        end
        if wantLevel <= anchorLevel then
            wantLevel = anchorLevel + 1
        end
        if hb._msufGFHoverLevel ~= wantLevel then
            hb._msufGFHoverLevel = wantLevel
            hb:SetFrameLevel(wantLevel)
        end
    end
end
GF.StyleMouseoverHighlight = _GF_StyleMouseoverHighlight

local function EnsureMouseoverHighlight(f)
    if not _GF_IsHighlightEnabled() then return nil end
    local hb = f._msufGFHoverBorder
    if hb then
        _GF_StyleMouseoverHighlight(f, hb)
        return hb
    end
    local anchor = f.barGroup or f
    hb = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    hb:EnableMouse(false)
    _GF_StyleMouseoverHighlight(f, hb)
    hb:Hide()
    f._msufGFHoverBorder = hb
    return hb
end

------------------------------------------------------------------------
-- Tooltip + Highlight hooks
------------------------------------------------------------------------
local _tooltipPendingToken = 0 -- invalidates deferred tooltip callbacks
local _tooltipTarget  -- frame awaiting tooltip
local _Debug = ns and ns.Debug

local function DebugHover(message, ...)
    if _Debug and type(_Debug.PrintGFHover) == "function" then
        _Debug.PrintGFHover(message, ...)
    end
end

local function OnEnter(f)
    DebugHover("GF OnEnter frame=%s unit=%s kind=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"), tostring(f and f._msufGFKind or "party"))
    -- Mouseover highlight
    local hb = EnsureMouseoverHighlight(f)
    if hb then hb:Show() end
    -- Cancel any pending tooltip for a different frame
    _tooltipPendingToken = _tooltipPendingToken + 1
    _tooltipTarget = f
    -- Tooltip (throttled 150ms)
    if not f.unit or not UnitExists(f.unit) then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local mode = conf.tooltipMode or "ALWAYS"
    if mode == "NEVER" then
        DebugHover("GF tooltip blocked frame=%s reason=mode-never", tostring(f and f:GetName() or "<anon>"))
        return
    end
    if mode == "OOC" and InCombatLockdown() then
        DebugHover("GF tooltip blocked frame=%s reason=in-combat-ooc-mode", tostring(f and f:GetName() or "<anon>"))
        return
    end
    if mode == "MODIFIER" then
        local mod = conf.tooltipModifier or "ALT"
        if mod == "ALT"   and not IsAltKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=alt-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if mod == "CTRL"  and not IsControlKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=ctrl-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if mod == "SHIFT" and not IsShiftKeyDown() then
            DebugHover("GF tooltip blocked frame=%s reason=shift-not-held", tostring(f and f:GetName() or "<anon>"))
            return
        end
    end
    local token = _tooltipPendingToken
    C_Timer.After(0.15, function()
        if _tooltipPendingToken ~= token then
            DebugHover("GF tooltip canceled frame=%s reason=token-changed", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if _tooltipTarget ~= f then
            DebugHover("GF tooltip canceled frame=%s reason=target-changed", tostring(f and f:GetName() or "<anon>"))
            return
        end
        if not f.unit or not UnitExists(f.unit) then
            DebugHover("GF tooltip canceled frame=%s reason=unit-gone", tostring(f and f:GetName() or "<anon>"))
            return
        end
        DebugHover("GF tooltip firing frame=%s unit=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"))
        local tips = ns and ns.Tooltips
        if tips and type(tips.ShowUnit) == "function" then
            tips.ShowUnit(f, f.unit)
        elseif _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
            local gt = _G.GameTooltip
            gt:SetOwner(f, "ANCHOR_RIGHT")
            gt:SetUnit(f.unit)
            gt:Show()
        end
    end)
end

local function OnLeave(f)
    DebugHover("GF OnLeave frame=%s unit=%s kind=%s", tostring(f and f:GetName() or "<anon>"), tostring(f and f.unit or "nil"), tostring(f and f._msufGFKind or "party"))
    -- Cancel pending tooltip
    _tooltipPendingToken = _tooltipPendingToken + 1
    _tooltipTarget = nil
    -- Hide highlight
    if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
    -- Hide tooltip
    local tips = ns and ns.Tooltips
    if tips and type(tips.HideUnit) == "function" then
        tips.HideUnit(f)
    elseif _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
        _G.GameTooltip:Hide()
    end
end

-- Hook into GF_InitButton from Phase 1
local _origInit = _G.MSUF_GF_InitButton
if type(_origInit) == "function" then
    _G.MSUF_GF_InitButton = function(f, kind)
        _origInit(f, kind)
        -- Add tooltip scripts
        f:SetScript("OnEnter", OnEnter)
        f:SetScript("OnLeave", OnLeave)
        if GF.ClickCastEnabled then GF.RegisterClickCastFrame(f, true) end
        -- GF frames do NOT use the main Alpha module.
        -- Range fade is handled exclusively by ApplyRangeFade â†’ SetAlphaFromBoolean.
        -- The Alpha module (MSUF_ApplyUnitAlpha) would override SetAlphaFromBoolean
        -- with SetAlpha(1), killing the range fade.
    end
end

------------------------------------------------------------------------
-- Expose
------------------------------------------------------------------------
--- Combined highlight refresh (aggro + dispel + target) â€” called by
--- Borders.lua test mode buttons via _G.MSUF_GF_UpdateHighlight
local function UpdateHighlight(f, unit)
    unit = unit or f.unit
    if not unit then return end
    UpdateAggro(f, unit)
    local c = f._c
    if not c and GF.BuildFrameCache then GF.BuildFrameCache(f); c = f._c end
    local dispelTest = _G.MSUF_BorderTestModesActive == true and _G.MSUF_DispelBorderTestMode == true
    if c and c.nativeBlizzardDispels and not dispelTest then
        if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
    elseif dispelTest or (c and c.dispelScan and GF._playerCanDispel) then
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
        elseif c and c.nativeBlizzardDispels then
            if _GF_ClearNativeSuppressedDispel then _GF_ClearNativeSuppressedDispel(f, unit) end
        elseif c and c.dispelScan and GF._playerCanDispel then GF._UpdateDispel(f, unit) end
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
-- Memory-leak Fix 1: Frame-retire cleanup hook
-- Called from RetireHeader for every child being retired. Removes the
-- frame from every module-level table that strong-refs it, and cancels
-- any pending deferred callback that captures the frame as upvalue.
--
-- Without this, retired frames live up to ~6s longer than necessary
-- (ready-check fade timer) and module tables accumulate stale refs
-- between retire and next GROUP_ROSTER_UPDATE.
--
-- Defined as upvalue-closure so it sees:
--   _gfTargetFrame, _gfFocusFrame, _tooltipPendingToken, _tooltipTarget,
--   _gfTextDirtyFrames
-- which are file-scope locals.
------------------------------------------------------------------------
_G.MSUF_GF_OnFrameRetire = function(f)
    if not f then return end

    -- Cancel + clear pending ready-check fade timer (closure captures `f`)
    if GF.CancelReadyCheckTimer then GF.CancelReadyCheckTimer(f) end
    _GF_StopDispelGlow(f)
    if GF.ResetOfflineHiddenFrame then GF.ResetOfflineHiddenFrame(f) end
    if GF.HideFrameAuras then GF.HideFrameAuras(f) end
    if GF.RecycleFramePools then GF.RecycleFramePools(f) end
    if GF.UnregisterUnitEvents then GF.UnregisterUnitEvents(f) end

    -- Clear target / focus pointers if pointing at this frame
    if _gfTargetFrame == f then _gfTargetFrame = nil end
    if _gfFocusFrame  == f then _gfFocusFrame  = nil end

    -- Cancel pending tooltip if it targets this frame
    if _tooltipTarget == f then
        _tooltipPendingToken = _tooltipPendingToken + 1
        _tooltipTarget  = nil
    end

    -- Drop pending text-flush entry (avoids dangling key in dirty set)
    _gfTextDirtyFrames[f] = nil
    _gfTextQueued[f] = nil
    f._msufGFStatusDirty = nil
    f._msufGFAuraDirty = nil
    f._msufGFFullPending = nil
    f._msufGFNameCacheKey = nil
    f._msufGFNameStyleKey = nil
    f._msufGFNameText = nil
    f._msufGFNameClass = nil
    f._msufGFNameColorKey = nil
    _gfAuraDirtyQueued[f] = nil

    -- Remove from GUIDâ†’frame map (search by value â€” guid hash unknown here)
    local gmap = GF._guidMap
    if gmap then
        for guid, framef in pairs(gmap) do
            if framef == f then gmap[guid] = nil end
        end
    end

    -- Drop from render dirty queue (Render module owns _dirtyFrames; expose helper if missing)
    if GF._RetireFromDirty then GF._RetireFromDirty(f) end
end
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

-- Dispel overlay: refresh all frames (called from Options when settings change)
_G.MSUF_GF_RefreshDispelOverlay = function()
    if not GF.frames then return end
    _GF_ForEachLiveGroupFrame(function(f)
        GF.BuildFrameCache(f)
        _GF_ApplyDispelOverlay(f)
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
_G.MSUF_GF_GlobalEventFrame     = _globalFrame

--- Refresh overlay bars (absorb + heal absorb + incoming heal) on all GF frames.
--- Called from Bars options when test mode or absorb settings change.
_G.MSUF_GF_RefreshOverlays = function()
    if not GF.frames then return end
    local absorbTestMayRun = (_G.MSUF_AbsorbTextureTestMode == true)
        and _G.MSUF_InCombat ~= true
        and not (_G.InCombatLockdown and _G.InCombatLockdown())
    _GF_ForEachLiveGroupFrame(function(f)
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
GF._ApplyAbsorbAnchor     = _GF_ApplyAbsorbAnchor
GF._ReadOverlayColor      = _GF_ReadOverlayColor

-- Idle-diagnosis exports
_G.MSUF_GF_DispatchHealth  = dispatchHealthFull  -- Full refresh (for Options/manual use)
_G.MSUF_GF_DispatchPower   = dispatchPower
_G.MSUF_GF_DispatchAura    = dispatchAura
_G.MSUF_GF_DispatchOverlays = dispatchOverlays
_G.MSUF_GF_ApplyPowerColor = ApplyPowerColor
_G.MSUF_GF_OnEvent         = GF_OnEvent
-- Exported diagnostic helper. Do not wire this into health/power hotpaths
-- without profiling and visual regression validation.
_G.MSUF_GF_PixelSnap       = _GF_PixelSnappedSetValue
