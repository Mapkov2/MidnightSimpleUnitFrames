-- MSUF_GF_Effects.lua — Group Frames Phase 2: Events + Effects
-- Per-frame RegisterUnitEvent, range fade (Grid2 pattern), aggro/dispel/target
-- borders, status icons, AFK/DND text, UNIT_AURA coalescing
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

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
local UnitIsPlayer = _G.UnitIsPlayer
local UnitClass = _G.UnitClass
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitPowerType = _G.UnitPowerType
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local UnitIsGroupAssistant = _G.UnitIsGroupAssistant
local UnitThreatSituation = _G.UnitThreatSituation
local UnitPhaseReason = _G.UnitPhaseReason
local UnitHasIncomingResurrection = _G.UnitHasIncomingResurrection
local GetRaidTargetIndex = _G.GetRaidTargetIndex
local GetReadyCheckStatus = _G.GetReadyCheckStatus
local C_IncomingSummon = _G.C_IncomingSummon
local C_Timer = _G.C_Timer
local GetTime = _G.GetTime
local AuraUtil = _G.AuraUtil
local CreateFrame = _G.CreateFrame
local IsSpellInRange = _G.C_Spell and _G.C_Spell.IsSpellInRange
local CheckInteractDistance = _G.CheckInteractDistance
local IsPlayerSpell = _G.IsPlayerSpell
local PowerBarColor = _G.PowerBarColor
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local SetRaidTargetIconTexture = _G.SetRaidTargetIconTexture
local UnitGetTotalAbsorbs     = _G.UnitGetTotalAbsorbs
local UnitGetIncomingHeals    = _G.UnitGetIncomingHeals
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local CreateUnitHealPredictionCalculator = _G.CreateUnitHealPredictionCalculator
local UnitGetDetailedHealPrediction      = _G.UnitGetDetailedHealPrediction

-- C-side gradient color curve (red→yellow→green) for GRADIENT health color mode.
-- Evaluated via calc:EvaluateCurrentHealthPercent(curve) — fully secret-safe,
-- zero Lua arithmetic. Replaces 6 Lua ops (UnitHealth, UnitHealthMax,
-- issecretvalue×2, tonumber×2, division, conditional) with 1 C-call.
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
-- Cost: ~0.3μs/slot vs ~7.5μs/slot with FormatHealthText.
------------------------------------------------------------------------
local _ftHpPct     = _G.UnitHealthPercent
local _ftHpMissing = _G.UnitHealthMissing
local _ftScale100  = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local _ftAbbrShort = _G.AbbreviateNumbers
local _ftAbbrLong  = _G.BreakUpLargeNumbers
local _ftAbbrFB    = _G.AbbreviateLargeNumbers or _G.ShortenNumber

-- Build a compiled text function for a given mode.
-- Returns fn(fontString, unit, hp, hpMax) or nil for NONE.
-- All string ops on secret values produce secret strings → C-side SetText.
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
                if m then fs:SetText("-" .. abbrFn(m)) else fs:SetText("") end
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
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local IsAltKeyDown     = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local UnitInRaid       = _G.UnitInRaid
local UnitInRange      = _G.UnitInRange
local IsInGroup        = _G.IsInGroup
local IsInRaid         = _G.IsInRaid
local UnitIsGhost      = _G.UnitIsGhost
local GetRaidRosterInfo = _G.GetRaidRosterInfo
local strmatch         = string.match
local _smoothInterp    = _G.Enum and _G.Enum.StatusBarInterpolation
                         and _G.Enum.StatusBarInterpolation.ExponentialEaseOut

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
-- Highlight value resolver: Bars hl* keys → old GF conf key fallback
-- Bars system uses hlAggroEnabled, hlAggroColorR, etc.
-- Old GF DB uses aggroEnabled, aggroR, etc.
-- Single-pass resolution: conf.hlOverride → general → conf[fallback]
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

local function HLVal(kind, key)
    local conf = GF.GetConf(kind)
    -- Priority 1: GF-local override
    if conf.hlOverride and conf[key] ~= nil then return conf[key] end
    -- Priority 2: global general (always fresh — 2 table lookups)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    -- Priority 3: legacy GF conf fallback
    local fb = _HL_FALLBACK[key]
    if fb and conf[fb] ~= nil then return conf[fb] end
    return nil
end

------------------------------------------------------------------------
-- Range check spells (Grid2 pattern — IsSpellInRange, NOT secret)
------------------------------------------------------------------------
local _playerClass = select(2, UnitClass("player"))
local _rangeFriendlySpell
local _rangeNeedsTicker = false

do
    local function IVS(id) return IsPlayerSpell and IsPlayerSpell(id) and id end
    local spells = {
        DRUID       = function() return 8936 end,       -- Regrowth
        PRIEST      = function() return 2061 end,       -- Flash Heal
        SHAMAN      = function() return 8004 end,       -- Healing Surge
        PALADIN     = function() return 19750 end,      -- Flash of Light
        MONK        = function() return 116670 end,     -- Vivify
        EVOKER      = function() return 355913 end,     -- Emerald Blossom
        WARLOCK     = function() return 20707 end,      -- Soulstone
        MAGE        = function() return 1459 end,       -- Arcane Intellect
        HUNTER      = function() return nil end,
        ROGUE       = function() return IVS(36554) or IVS(57934) end, -- Shadowstep / Tricks
        DEATHKNIGHT = function() return IVS(47541) end, -- Death Coil
        WARRIOR     = function() return nil end,
        DEMONHUNTER = function() return nil end,
    }
    local _spellGetter = spells[_playerClass]

    -- Exported: re-resolve on SPELLS_CHANGED, spec change, instance entry.
    -- Called from recovery ticker OnEvent + PLAYER_LOGIN.
    function GF._RebuildRangeSpell()
        local old = _rangeFriendlySpell
        _rangeFriendlySpell = _spellGetter and _spellGetter() or nil
        _rangeNeedsTicker = (_rangeFriendlySpell == nil)
    end
    GF._RebuildRangeSpell()  -- initial resolve at file load
end

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
-- SINGLE mode → plain (r,g,b) triplet from the Colors panel.
-- TYPE mode   → a *Color object* from C_UnitAuras.GetAuraDispelTypeColor.
--               The Color object carries secret-safe RGBA that can ONLY be
--               applied via texture:SetVertexColor(color:GetRGBA()). It
--               MUST NOT be unpacked into Lua locals and fed to
--               CreateColor / SetGradient / arithmetic — that taints the
--               values and breaks everything but flat fills (which is the
--               "only single-color works" bug in Beta 4/5).
--
-- Returns (colorObj, r, g, b):
--   colorObj ~= nil  → TYPE mode resolved via curve. Apply via
--                      tex:SetVertexColor(colorObj:GetRGBA())
--   colorObj == nil  → SINGLE/fallback. Use (r, g, b) directly.
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
            local slots = { CUA.GetAuraSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE") }
            for i = 2, #slots do
                local slot = slots[i]
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
                    break
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
-- secret-safety here — values feed into LCG's color table which is
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
-- Dispel glow helpers (GF) — zero-alloc color table reuse
------------------------------------------------------------------------
local _gfGlowColor = { 0, 0, 0, 1 }

local function _GF_StartDispelGlow(f, r, g, b)
    if not LCG then return end
    local kind = f._msufGFKind or "party"
    if not HLVal(kind, "hlDispelGlowEnabled") then return end
    local anchor = f._msufGFHighlightBorder or f
    _gfGlowColor[1], _gfGlowColor[2], _gfGlowColor[3] = r, g, b
    local style = HLVal(kind, "hlDispelGlowStyle") or "PIXEL"
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
end

local function _GF_StopDispelGlow(f)
    if not f._msufGFDispelGlowActive then return end
    f._msufGFDispelGlowActive = nil
    if not LCG then return end
    local anchor = f._msufGFHighlightBorder or f
    LCG.PixelGlow_Stop(anchor, "msufDispel")
    LCG.AutoCastGlow_Stop(anchor, "msufDispel")
    LCG.ProcGlow_Stop(anchor, "msufDispel")
end

------------------------------------------------------------------------
-- Status icon textures
------------------------------------------------------------------------
local ICON_TEX = {
    ready      = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notReady   = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting    = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    resurrect  = "Interface\\RaidFrame\\Raid-Icon-Rez",
    phase      = "Interface\\TargetingFrame\\UI-PhasingIcon",
}
local SUMMON_PENDING  = 1
local SUMMON_ACCEPTED = 2
local SUMMON_DECLINED = 3
local SUMMON_TEX = {
    [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}

------------------------------------------------------------------------
-- Role icon coords
------------------------------------------------------------------------
local ROLE_TEXTURES = {
    TANK    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER  = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DAMAGER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}
local ROLE_COORDS = {
    TANK    = { 0,     19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

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

------------------------------------------------------------------------
-- UNIT_AURA: per-frame dispatch with burst-dedup (A2 P2 pattern)
-- Fast-paths (update-only 16µs, remove-only-not-displayed) still fire
-- instantly. Full pipeline is gated: first event runs immediately,
-- subsequent same-frame events within 20ms are skipped.
-- Zero steady-state alloc: clear-callback allocated once per frame.
------------------------------------------------------------------------
local _After0 = C_Timer and C_Timer.After

------------------------------------------------------------------------
-- PERF: Global per-frame budget for full aura scans.
-- AoE heal/damage → 20 UNIT_AURA events in same frame → 20 × 138µs = 2.8ms spike.
-- Budget limits full scans to 8 per frame. Excess deferred to next frame via C_Timer.After(0).
-- Max spike capped to 8 × 138µs ≈ 1.1ms.
------------------------------------------------------------------------
local _GF_AURA_BUDGET_MAX = 8
local _gfAuraBudget = 0
local _gfAuraDirtyPending = false
local _gfAuraBudgetFrame = 0  -- GetTime of last budget reset

-- Forward-declared; assigned after dispatchAura is defined.
local _gfFlushDirtyAuras
local function SpellIndicatorsNeedRefresh(f, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    local added = updateInfo.addedAuras
    if added and #added > 0 then return true end

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
                            -- No tracked dispel — new removals might reveal nothing, but
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
                GF._UpdateDispel(f, unit)
            end
        end
        if siRefresh and GF.UpdateSpellIndicators then
            GF.UpdateSpellIndicators(f, unit)
        end
        if ciRelevant and GF.UpdateCornerIndicators and c.ciEn then
            GF.UpdateCornerIndicators(f, unit)
        end
        return
    end

    -- c.anyAuraGrp already includes sub-group enabled check, no need for second pass

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

        -- Update-only: direct icon refresh (16µs vs 115µs)
        if not hasAdd and not hasRem and hasUpd then
            if displayed and GF.RefreshAuraIcon then
                for ui = 1, #updated do
                    local icon = displayed[updated[ui]]
                    if icon then
                        GF.RefreshAuraIcon(icon, unit, updated[ui])
                    end
                end
                if siRefresh and GF.UpdateSpellIndicators then
                    GF.UpdateSpellIndicators(f, unit)
                end
                return
            end
        end

        -- Remove-only: skip if none of the removed auras were displayed
        if hasRem and not hasAdd then
            if displayed then
                local anyDisplayed = false
                for ri = 1, #removed do
                    if displayed[removed[ri]] then anyDisplayed = true; break end
                end
                if not anyDisplayed then
                    -- Removed auras weren't visible — also handle updates if present
                    if hasUpd and GF.RefreshAuraIcon then
                        for ui = 1, #updated do
                            local icon = displayed[updated[ui]]
                            if icon then GF.RefreshAuraIcon(icon, unit, updated[ui]) end
                        end
                    end
                    if siRefresh and GF.UpdateSpellIndicators then
                        GF.UpdateSpellIndicators(f, unit)
                    end
                    -- Corner Indicators: removal may clear a dispel/boss dot
                    if GF.UpdateCornerIndicators and c.ciEn then
                        GF.UpdateCornerIndicators(f, unit)
                    end
                    return
                end
            end
        end

        -- Add or displayed-remove: fall through to full pipeline
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

    -- ════════════════════════════════════════════════════════════════
    -- P1: In-combat burst-dedup (A2 P2 pattern)
    -- First event runs the full pipeline immediately (zero latency).
    -- Subsequent events for the SAME frame within 20ms are skipped.
    -- Saves N-1 full pipeline runs per AoE burst (N=simultaneous aura
    -- changes per unit). Clear-callback allocated once per frame.
    -- ════════════════════════════════════════════════════════════════
    if f._msufGFFullPending then return end
    f._msufGFFullPending = true
    if _After0 then
        local cb = f._msufGFPendClearCB
        if not cb then
            local frame = f
            cb = function() frame._msufGFFullPending = nil end
            f._msufGFPendClearCB = cb
        end
        _After0(0.02, cb)
    else
        f._msufGFFullPending = nil   -- fallback: no timer → no dedup
    end

    -- ════════════════════════════════════════════════════════════════
    -- P2: Global per-frame budget (AoE spike limiter)
    -- AoE events fire 20+ UNIT_AURA for different units in one frame.
    -- Each full scan costs ~138µs. 20 × 138µs = 2.8ms spike.
    -- Budget caps to 8 scans/frame → max ~1.1ms. Rest deferred.
    -- ════════════════════════════════════════════════════════════════
    _gfAuraBudget = _gfAuraBudget + 1
    local now = GetTime()
    if now ~= _gfAuraBudgetFrame then
        _gfAuraBudgetFrame = now
        _gfAuraBudget = 1
    end
    if _gfAuraBudget > _GF_AURA_BUDGET_MAX then
        f._msufGFAuraDirty = true
        if not _gfAuraDirtyPending and _After0 then
            _gfAuraDirtyPending = true
            _After0(0, _gfFlushDirtyAuras)
        end
        return
    end

    -- Full aura processing (add/remove/fullUpdate)
    -- SI runs first: populates dedup IDs before buff scan
    if c.siEn and GF.UpdateSpellIndicators then
        GF.UpdateSpellIndicators(f, unit)
    end
    if GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
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
    else
        GF._UpdateDispel(f, unit)
    end

    -- Debuff stripe: detect a debuff that passes the Debuffs filter/list.
    if c.dsEn then
        local hadDebuff = f._msufGFHasAnyDebuff or false
        local hasDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
        f._msufGFHasAnyDebuff = hasDebuff
        if hasDebuff ~= hadDebuff then
            _GF_ApplyDebuffStripe(f)
        end
    end

    -- Corner Indicators (only when enabled)
    if GF.UpdateCornerIndicators and c.ciEn then
        GF.UpdateCornerIndicators(f, unit)
    end

end

------------------------------------------------------------------------
-- Deferred aura flush: processes frames that exceeded the per-frame budget.
-- Fires via C_Timer.After(0) → runs at the start of the next frame.
------------------------------------------------------------------------
_gfFlushDirtyAuras = function()
    _gfAuraBudget = 0
    _gfAuraDirtyPending = false
    for f in pairs(GF.frames) do
        if f._msufGFAuraDirty then
            f._msufGFAuraDirty = nil
            local u = f.unit
            if u and UnitExists(u) then
                dispatchAura(f, u, nil)
            end
        end
    end
end
------------------------------------------------------------------------
-- Range fade (1:1 EQoL pattern)
-- Secret-safe: NEVER compare/type()/conditional on inRange.
-- Pass raw value to SetAlphaFromBoolean (C-side accepts secrets).
-- 1:1 EQoL GF:UpdateRange pattern — NO extra UnitPhaseReason/UnitIsVisible.
------------------------------------------------------------------------

-- EQoL UnsecretBool equivalent
local function _UnsecretBool(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function ApplyRangeFade(f, unit, inRange)
    local c = f._c
    if c and not c.rfEn then
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local fadeAlpha = conf.rangeFadeAlpha or 0.4

    -- Disabled → full alpha
    if conf.rangeFadeEnabled == false then
        if f.SetAlpha then f:SetAlpha(1) end
        return
    end

    -- Solo guard (EQoL: IsInGroup + IsInRaid)
    if IsInGroup and IsInRaid then
        if not IsInGroup() and not IsInRaid() then
            if f.SetAlpha then f:SetAlpha(1) end
            return
        end
    end

    -- Offline (EQoL: UnsecretBool on UnitIsConnected)
    local connected = unit and UnitIsConnected and _UnsecretBool(UnitIsConnected(unit)) or nil
    if connected == false then
        local offA = conf.offlineAlpha or fadeAlpha
        if f.SetAlpha then f:SetAlpha(offA) end
        return
    end

    -- EQoL exact pattern (line 8424)
    if inRange == nil and unit and UnitInRange then inRange = UnitInRange(unit) end

    if type(inRange) ~= "nil" then
        if f.SetAlphaFromBoolean then
            f:SetAlphaFromBoolean(inRange, 1, fadeAlpha)
        end
    end
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
-- (same source as main UF — Colors panel writes there).
-- hlOverride only gates geometry (size/offset/layer) and enable flags,
-- NOT colors — prevents stale-seeded color copies in gf_party/gf_raid.
------------------------------------------------------------------------
local function HLColor(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
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
    local c = f._c
    if not c then c = {}; f._c = c end

    -- Smooth fill (pre-resolved interpolation enum)
    c.smooth    = conf.smoothFill ~= false and _smoothInterp or nil
    c.powSmooth = conf.powerSmoothFill and _smoothInterp or nil

    -- Health text slots
    c.tl    = conf.textLeft    or "NONE"
    c.tc    = conf.textCenter  or "NONE"
    c.tr    = conf.textRight   or "NONE"
    c.tlOn  = c.tl ~= "NONE"
    c.tcOn  = c.tc ~= "NONE"
    c.trOn  = c.tr ~= "NONE"
    -- PERF: Aggregate flag — skip all 3 text blocks when no text enabled
    c.anyText = c.tlOn or c.tcOn or c.trOn
    c.delim = conf.textDelimiter or " / "
    c.rev   = conf.hpTextReverse
    -- Compile fast text functions (oUF-style: mode → C-side closure)
    _BuildSlotFns(c)

    -- Cutaway
    c.cwEn   = conf.cutawayEnabled ~= false
    c.cwFade = conf.cutawayFadeTime or 0.4
    c.cwR    = conf.cutawayColorR or 0.70
    c.cwG    = conf.cutawayColorG or 0.10
    c.cwB    = conf.cutawayColorB or 0.10
    c.cwA    = conf.cutawayColorA or 0.75

    -- Cooldown swipe direction (Fix B): pre-cached so ApplyCooldownVisualStyle
    -- in RenderGroup hot path / RefreshAuraIcon doesn't need GF.GetConf.
    -- Live-apply via Options toggle: GF.RefreshVisuals → ApplyVisuals →
    -- BuildFrameCache (this function) → c.cdReverse refreshed.
    c.cdReverse = conf.cooldownSwipeDarkenOnLoss == true

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
    c.powH      = conf.powerHeight or 6
    c.showPow   = conf.showPower
    c.ptl       = conf.powerTextLeft   or "NONE"
    c.ptc       = conf.powerTextCenter or "NONE"
    c.ptr       = conf.powerTextRight  or "NONE"
    c.ptlOn     = c.ptl ~= "NONE"
    c.ptcOn     = c.ptc ~= "NONE"
    c.ptrOn     = c.ptr ~= "NONE"
    c.pDelim    = conf.powerTextDelimiter or " / "
    c.powTank   = conf.powerShowTank   ~= false
    c.powHealer = conf.powerShowHealer ~= false
    c.powDPS    = conf.powerShowDamager ~= false

    -- Range fade
    c.rfEn    = conf.rangeFadeEnabled ~= false
    c.rfAlpha = conf.rangeFadeAlpha or 0.4
    c.offAlpha = conf.offlineAlpha or 0.5

    -- Health fade (curve-based HP threshold dimming)
    c.hfEn     = conf.healthFadeEnabled == true
    c.hfAlpha  = conf.healthFadeAlpha or 0.45
    c.hfThresh = conf.healthFadeThreshold or 95

    -- Dispel overlay (color wash on health bar)
    c.doEn    = conf.dispelOverlayEnabled == true
    c.doStyle = conf.dispelOverlayStyle or "FULL"
    c.doOnHP  = conf.dispelOverlayOnHealth ~= false
    c.doAlpha = conf.dispelOverlayAlpha or 0.35

    -- Debuff stripe (thin edge for any debuff)
    c.dsEn    = conf.debuffStripeEnabled == true
    c.dsEdge  = conf.debuffStripeEdge or "BOTTOM"
    c.dsH     = conf.debuffStripeHeight or 3
    c.dsAlpha = conf.debuffStripeAlpha or 0.60
    c.dsR     = conf.debuffStripeColorR or 0.80
    c.dsG     = conf.debuffStripeColorG or 0.20
    c.dsB     = conf.debuffStripeColorB or 0.20

    -- Highlight border (pre-resolve HLVal)
    c.aggroEn   = HLVal(kind, "hlAggroEnabled") ~= false
    c.aggroMode = HLVal(kind, "hlAggroMode") or "ALL"
    c.dispelEn  = HLVal(kind, "hlDispelEnabled") ~= false
    c.targetEn  = HLVal(kind, "hlTargetEnabled") ~= false
    c.focusEn   = conf.hlFocusEnabled ~= false

    -- Target color (pre-resolve HLColor)
    c.tgtR = HLColor("hlTargetColorR", 1)
    c.tgtG = HLColor("hlTargetColorG", 1)
    c.tgtB = HLColor("hlTargetColorB", 1)

    -- Focus color
    c.focR = conf.hlFocusColorR or 0.5
    c.focG = conf.hlFocusColorG or 0.5
    c.focB = conf.hlFocusColorB or 1.0

    -- Aura dispatch
    c.dispelScan = conf.dispelEnabled ~= false
    c.siEn       = conf.spellIndicators and conf.spellIndicators.enabled == true
    local auras  = conf.auras
    c.aurasOn    = auras and auras.enabled ~= false
    c.anyAuraGrp = c.aurasOn and (
                   (auras.debuff and auras.debuff.enabled ~= false) or
                   (auras.buff and auras.buff.enabled ~= false) or
                   (auras.externals and auras.externals.enabled))

    -- Corner indicators
    c.ciEn = conf.ciEnabled ~= false
    -- PERF: Pre-compute slot→category map (eliminates 63K SlotCat calls/session)
    c.ciSlotTL = (conf.ciSlotTL or "none")
    c.ciSlotTR = (conf.ciSlotTR or "none")
    c.ciSlotBL = (conf.ciSlotBL or "none")
    c.ciSlotBR = (conf.ciSlotBR or "none")
    c.ciSlotC  = (conf.ciSlotC  or "none")

    -- Raid debuffs

    -- Heal prediction (resolve full fallthrough: conf → general → default true)
    local hpEn = conf.healPredEnabled
    if hpEn == nil then
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        hpEn = not gen or gen.enableHealPrediction ~= false
    end
    c.healPredEn = hpEn

    -- Absorb: independently gated from heal prediction
    c.absorbEn = _GF_IsAbsorbEnabled(kind)
    c.healAbsorbEn = conf.healAbsorbEnabled ~= false

    -- Name display
    c.nameEn = conf.showName ~= false

    -- Status icons (gate event registration)
    c.summonEn = conf.summonIcon ~= false
    c.resEn    = conf.resurrectIcon ~= false
    c.phaseEn  = conf.phaseIcon ~= false

    -- Composite: does anything need UNIT_AURA?
    c.needAura = c.anyAuraGrp or c.ciEn
                 or (c.dispelScan and GF._playerCanDispel)
                 or c.siEn

    -- Composite: does anything need UNIT_THREAT?
    c.needThreat = c.aggroEn

    -- Private auras
    local pa = conf.privateAuras
    c.paEn = pa and pa.enabled ~= false

    -- Event bitmask: drives diff-gated RegisterUnitEvents
    local evBits = 0
    if c.nameEn     then evBits = evBits + 1    end
    if c.powH > 0   then evBits = evBits + 2    end
    if c.rfEn       then evBits = evBits + 4    end
    if c.needAura   then evBits = evBits + 8    end
    if c.needThreat then evBits = evBits + 16   end
    if c.summonEn   then evBits = evBits + 32   end
    if c.resEn      then evBits = evBits + 64   end
    if c.phaseEn    then evBits = evBits + 128  end
    if c.healPredEn then evBits = evBits + 256  end
    if c.absorbEn   then evBits = evBits + 512  end
    if c.healAbsorbEn and not c.absorbEn then evBits = evBits + 1024 end
    local prevBits = c._evBits
    c._evBits = evBits
    if prevBits ~= nil and prevBits ~= evBits and f.unit and f._msufGFRegEv then
        GF.RegisterUnitEvents(f, f.unit)
    end

    -- Invalidate module-level text format cache (hidePercentSymbol, useShortNumbers)
    if GF.InvalidateTextFormatCache then GF.InvalidateTextFormatCache() end
end

------------------------------------------------------------------------
-- Lightweight border activation (NO SetBackdrop — color + show/hide only)
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
            local kind = f._msufGFKind or "party"
            local conf = GF.GetConf(kind)
            _applyHighlightBorderStyle(border, conf,
                HLVal(kind, "hlTargetSize") or 2,
                HLVal(kind, "hlTargetOffset") or 0,
                HLVal(kind, "hlTargetTexture"),
                HLVal(kind, "hlTargetLayer") or "DEFAULT",
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
            local kind = f._msufGFKind or "party"
            local conf = GF.GetConf(kind)
            _applyHighlightBorderStyle(border, conf,
                conf.hlFocusSize or 2,
                conf.hlFocusOffset or 0,
                conf.hlFocusTexture,
                conf.hlFocusLayer or "DEFAULT",
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
--     • use pre-baked gradient *textures* (Media/MSUF_Grad_*.tga) for the
--       TOP/BOTTOM/LEFT/RIGHT/EDGE styles — no SetGradient needed,
--     • apply the tint via tex:SetVertexColor(color:GetRGBA()) in a single
--       varargs passthrough — no Lua arithmetic on the tint values,
--     • use SetAlpha on the StatusBar frame for the user's doAlpha slider.
--
--   This replaces the Beta 5 path that called CreateColor(secret_r, ...)
--   in SetGradient branches — that was the "TYPE mode broken / only
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
    if not dov then return end
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
    -- SetStatusBarTexture — Blizzard reloads the atlas every call).
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
        local kind = f._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        dov:SetReverseFill(conf.reverseFill and true or false)
    end

    if not dov:IsShown() then dov:Show() end
end

------------------------------------------------------------------------
-- Debuff stripe (thin edge indicator for a configured debuff match).
-- Independent from dispel overlay — honors the Debuffs filter/list and
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
    -- from dispel-change sites only — never from aggro/target/test paths.

    local border = f._msufGFHighlightBorder
    if not border then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    -- Resolve active states
    local dispelType = f._msufGFDispelType
    local hasDispel  = dispelType and HLVal(kind, "hlDispelEnabled") ~= false
    local aggroLevel = f._msufGFAggroLevel
    local hasAggro   = aggroLevel and aggroLevel >= 1 and HLVal(kind, "hlAggroEnabled") ~= false

    -- Shared geometry for dispel/aggro/purge (all use Aggro size keys)
    local sz  = HLVal(kind, "hlAggroSize") or 2
    local ofs = HLVal(kind, "hlAggroOffset") or 0
    local tex = HLVal(kind, "hlAggroTexture")
    local lay = HLVal(kind, "hlAggroLayer") or "DEFAULT"

    -- Configurable priority: read hlPrioOrder from Bars menu (general DB).
    -- Maps "dispel"/"magic"/"curse"/etc → dispel, "aggro" → aggro.
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
                        _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
                        border._msufHLActivePrio = 1; border:Show()
                        _GF_StartDispelGlow(f, r, g, b)
                        return
                    end
                end
            elseif pk == "aggro" then
                if hasAggro then
                    _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay,
                        HLColor("hlAggroColorR", 1), HLColor("hlAggroColorG", 0.55), HLColor("hlAggroColorB", 0), 1)
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
                _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay, r, g, b, 1)
                border._msufHLActivePrio = 1; border:Show()
                _GF_StartDispelGlow(f, r, g, b)
                return
            end
        end
        if hasAggro then
            _applyHighlightBorderStyle(border, conf, sz, ofs, tex, lay,
                HLColor("hlAggroColorR", 1), HLColor("hlAggroColorG", 0.55), HLColor("hlAggroColorB", 0), 1)
            border._msufHLActivePrio = 2; border:Show()
            _GF_StopDispelGlow(f)
            return
        end
    end

    -- After configurable prio: Target (GF-specific, always after dispel/aggro)
    if f._msufGFIsTarget and HLVal(kind, "hlTargetEnabled") ~= false then
        _applyHighlightBorderStyle(border, conf,
            HLVal(kind, "hlTargetSize") or 2,
            HLVal(kind, "hlTargetOffset") or 0,
            HLVal(kind, "hlTargetTexture"),
            HLVal(kind, "hlTargetLayer") or "DEFAULT",
            HLColor("hlTargetColorR", 1),
            HLColor("hlTargetColorG", 1),
            HLColor("hlTargetColorB", 1), 1)
        border._msufHLActivePrio = 3; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    -- Focus (GF-specific, lowest priority)
    if f._msufGFIsFocus and conf.hlFocusEnabled ~= false then
        _applyHighlightBorderStyle(border, conf,
            conf.hlFocusSize or 2,
            conf.hlFocusOffset or 0,
            conf.hlFocusTexture,
            conf.hlFocusLayer or "DEFAULT",
            conf.hlFocusColorR or 0.5,
            conf.hlFocusColorG or 0.5,
            conf.hlFocusColorB or 1.0, 1)
        border._msufHLActivePrio = 4; border:Show()
        _GF_StopDispelGlow(f)
        return
    end

    border._msufHLActivePrio = nil
    if border:IsShown() then border:Hide() end
    _GF_StopDispelGlow(f)
end

local function UpdateAggro(f, unit)
    local kind = f._msufGFKind or "party"
    local prevLevel = f._msufGFAggroLevel
    -- PERF: pre-resolved flags on _c cache (populated in BuildFrameCache).
    local c = f._c

    local testMode = _G.MSUF_AggroBorderTestMode
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
    if (((c and c.aggroEn) == false) or not unit) and not testMode then
        if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
        return
    end

    if not testMode then
        if not UnitExists(unit) then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local aggroMode = (c and c.aggroMode) or "ALL"
        if aggroMode ~= "ALL" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if aggroMode == "HEALER_ONLY" and role ~= "HEALER" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
            if aggroMode == "TANK_ONLY" and role ~= "TANK" then
                if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
                return
            end
        end
        local status = UnitThreatSituation and UnitThreatSituation(unit)
        if issecretvalue and issecretvalue(status) then
            -- Secret: can't diff-gate, but only refresh if we had aggro before
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        local s = tonumber(status)
        if not s or s < 1 then
            if prevLevel ~= nil then f._msufGFAggroLevel = nil; _GF_RefreshBorder(f, unit) end
            return
        end
        -- Diff-gate: only refresh border when threat level actually changes
        if s == prevLevel then return end
        f._msufGFAggroLevel = s
    else
        f._msufGFAggroLevel = 3
    end
    _GF_RefreshBorder(f, unit)
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

    local testMode = _G.MSUF_DispelBorderTestMode
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

    if (HLVal(kind, "hlDispelEnabled") == false or not unit) and not testMode then
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
    f._msufGFDispelType = topDispel
    f._msufGFDispelAuraID = topAid
    f._msufGFPrevDispelAuraID = topAid

    if topDispel == prevDispel and topAid == prevAid and colorRev == prevColorRev and not testMode then return end

    f._msufGFColorStyleRevision = colorRev
    _GF_RefreshBorder(f, unit)
    -- Overlay only for real dispels — border test mode is border-only
    if not testMode then
        _GF_ApplyDispelOverlay(f)
    end
end

------------------------------------------------------------------------
-- Target indicator border
------------------------------------------------------------------------
local function UpdateTargetIndicator(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local border = f._msufGFTargetBorder
    if not border then return end

    if HLVal(kind, "hlTargetEnabled") == false or not unit then
        border:Hide()
        return
    end

    local isTarget = UnitIsUnit and UnitIsUnit(unit, "target")
    if isTarget then
        local edgeSz = HLVal(kind, "hlTargetSize") or 2
        local ofs    = HLVal(kind, "hlTargetOffset") or 0
        local tex    = HLVal(kind, "hlTargetTexture")
        local lay    = HLVal(kind, "hlTargetLayer") or "DEFAULT"
        _applyHighlightBorderStyle(border, conf, edgeSz, ofs, tex, lay,
            HLVal(kind, "hlTargetColorR") or 1,
            HLVal(kind, "hlTargetColorG") or 1,
            HLVal(kind, "hlTargetColorB") or 1, 1)
        border:Show()
    else
        border:Hide()
    end
end

------------------------------------------------------------------------
-- Status text helpers (module-level — zero closure allocation)
------------------------------------------------------------------------
local function _GF_HideHealthText(f)
    if f.textLeftFS then f.textLeftFS:Hide() end
    if f.textCenterFS then f.textCenterFS:Hide() end
    if f.textRightFS then f.textRightFS:Hide() end
    if f.powerTextLeftFS then f.powerTextLeftFS:Hide() end
    if f.powerTextCenterFS then f.powerTextCenterFS:Hide() end
    if f.powerTextRightFS then f.powerTextRightFS:Hide() end
end

local function _GF_RestoreHealthText(f, conf)
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    if f.textLeftFS  and tl ~= "NONE" then f.textLeftFS:Show() end
    if f.textCenterFS and tc ~= "NONE" then f.textCenterFS:Show() end
    if f.textRightFS and tr ~= "NONE" then f.textRightFS:Show() end
    if conf.showPower and (conf.powerHeight or 6) > 0 then
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
local function UpdateStatusText(f, unit)
    local st = f._msufGFStatusText or f.statusIndicatorText
    if not st then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)

    if not unit or not UnitExists(unit) then
        if f._msufGFStatusState ~= 0 then
            f._msufGFStatusState = 0
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

    if connected == false then
        newState = 1
    else
        -- Secret-safe (12.0): UnitIsDeadOrGhost may return secret booleans for
        -- non-self units. Guard via issecretvalue; treat secret as "alive" so
        -- we fall through to AFK/DND check.
        local dog = UnitIsDeadOrGhost(unit)
        if issecretvalue and issecretvalue(dog) then dog = false end
        if dog then
            local ghost = UnitIsGhost and UnitIsGhost(unit)
            if issecretvalue and ghost and issecretvalue(ghost) then ghost = false end
            newState = ghost and 3 or 2
        else
            if UnitIsAFK then
                local afk = UnitIsAFK(unit)
                if not (issecretvalue and issecretvalue(afk)) and afk == true then
                    newState = 4
                end
            end
            if newState == 0 and UnitIsDND then
                local dnd = UnitIsDND(unit)
                if not (issecretvalue and issecretvalue(dnd)) and dnd == true then
                    newState = 5
                end
            end
        end
    end

    -- Diff-gate: only update visuals when state actually changes
    if newState == f._msufGFStatusState then return end
    f._msufGFStatusState = newState

    if newState == 0 then
        st:SetText("")
        st:Hide()
        _GF_RestoreHealthText(f, conf)
    elseif newState == 1 then
        st:SetText("OFFLINE")
        st:SetTextColor(0.6, 0.6, 0.6, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 2 then
        st:SetText("DEAD")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 3 then
        st:SetText("GHOST")
        st:SetTextColor(1, 1, 1, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 4 then
        st:SetText("AFK")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    elseif newState == 5 then
        st:SetText("DND")
        st:SetTextColor(1, 0.6, 0, 1)
        st:Show()
        _GF_HideHealthText(f)
    end
end

------------------------------------------------------------------------
-- Role icon update
------------------------------------------------------------------------
local function UpdateRoleIcon(f, unit)
    if not f.roleIcon then
        -- Still update power role cache even without role icon widget
        if f.power then
            local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit)
            local c = f._c
            if c and role then
                f._msufGFPowRoleHidden = (role == "TANK" and not c.powTank)
                    or (role == "HEALER" and not c.powHealer)
                    or (role == "DAMAGER" and not c.powDPS) or false
            else
                f._msufGFPowRoleHidden = false
            end
        end
        return
    end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.roleIcon == false or not unit or not UnitExists(unit) then
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        f._msufGFPowRoleHidden = false
        return
    end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)

    -- Cache power-per-role visibility (read by dispatchPower lean path)
    local c = f._c
    if c and role then
        f._msufGFPowRoleHidden = (role == "TANK" and not c.powTank)
            or (role == "HEALER" and not c.powHealer)
            or (role == "DAMAGER" and not c.powDPS) or false
    else
        f._msufGFPowRoleHidden = false
    end

    if role and role ~= "NONE" then
        local tex, l, r, t, b = GF.GetRoleTexture(kind, role)
        if tex then
            f.roleIcon:SetTexture(tex)
            f.roleIcon:SetTexCoord(l, r, t, b)
            if not f.roleIcon:IsShown() then f.roleIcon:Show() end
        else
            if f.roleIcon:IsShown() then f.roleIcon:Hide() end
        end
    else
        if f.roleIcon:IsShown() then f.roleIcon:Hide() end
    end
end

------------------------------------------------------------------------
-- Raid target marker update
------------------------------------------------------------------------
local function UpdateRaidMarker(f, unit)
    if not f.raidIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.raidMarker == false or not unit or not UnitExists(unit) then
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
        return
    end
    local idx = GetRaidTargetIndex(unit)
    if idx then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        if not f.raidIcon:IsShown() then f.raidIcon:Show() end
    else
        if f.raidIcon:IsShown() then f.raidIcon:Hide() end
    end
end

------------------------------------------------------------------------
-- Leader / Assistant icon update
------------------------------------------------------------------------
local function UpdateLeaderIcon(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    -- Leader icon
    if f.leaderIcon then
        if conf.leaderIcon == false or not unit or not UnitExists(unit) then
            if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
        else
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isLeader then
                local tex, l, r, t, b = GF.GetLeaderTexture(kind)
                f.leaderIcon:SetTexture(tex)
                f.leaderIcon:SetTexCoord(l, r, t, b)
                if not f.leaderIcon:IsShown() then f.leaderIcon:Show() end
            else
                if f.leaderIcon:IsShown() then f.leaderIcon:Hide() end
            end
        end
    end
    -- Assist icon (separate from leader)
    if f.assistIcon then
        if conf.assistIcon == false or not unit or not UnitExists(unit) then
            if f.assistIcon:IsShown() then f.assistIcon:Hide() end
        else
            local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
            -- Only show assist if not also leader (avoid double-icon)
            local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
            if isAssist and not isLeader then
                local tex, l, r, t, b = GF.GetAssistTexture(kind)
                f.assistIcon:SetTexture(tex)
                f.assistIcon:SetTexCoord(l, r, t, b)
                if not f.assistIcon:IsShown() then f.assistIcon:Show() end
            else
                if f.assistIcon:IsShown() then f.assistIcon:Hide() end
            end
        end
    end
end

------------------------------------------------------------------------
-- Ready check icon
------------------------------------------------------------------------
local _readyCheckTimers = {} -- [frame] = timer handle

local function UpdateReadyCheck(f, unit, event)
    if not f.readyCheckIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.readyCheckIcon == false or not unit then
        f.readyCheckIcon:Hide()
        if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel(); _readyCheckTimers[f] = nil end
        return
    end

    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.ready)
        f.readyCheckIcon:Show()
    elseif status == "notready" then
        f.readyCheckIcon:SetTexture(ICON_TEX.notReady)
        f.readyCheckIcon:Show()
    elseif status == "waiting" then
        f.readyCheckIcon:SetTexture(ICON_TEX.waiting)
        f.readyCheckIcon:Show()
    else
        if event == "READY_CHECK_FINISHED" and f.readyCheckIcon:IsShown() then
            -- Fade out after 6 seconds
            if _readyCheckTimers[f] then _readyCheckTimers[f]:Cancel() end
            _readyCheckTimers[f] = C_Timer.NewTimer(6, function()
                _readyCheckTimers[f] = nil
                f.readyCheckIcon:Hide()
            end)
        else
            f.readyCheckIcon:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Summon icon
------------------------------------------------------------------------
local function UpdateSummonIcon(f, unit)
    if not f.summonIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.summonIcon == false or not unit then
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
        return
    end
    local status
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        status = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local tex = status and SUMMON_TEX[status]
    if tex then
        f.summonIcon:SetTexture(tex)
        f.summonIcon:Show()
        f._msufGFSummonActive = true
    else
        f.summonIcon:Hide()
        f._msufGFSummonActive = false
    end
end

------------------------------------------------------------------------
-- Resurrect icon
------------------------------------------------------------------------
local function UpdateResurrectIcon(f, unit)
    if not f.resurrectIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.resurrectIcon == false or not unit then
        f.resurrectIcon:Hide()
        return
    end
    -- Suppress if summon is active
    if f._msufGFSummonActive then
        f.resurrectIcon:Hide()
        return
    end
    local show = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if show then
        f.resurrectIcon:SetTexture(ICON_TEX.resurrect)
        f.resurrectIcon:Show()
    else
        f.resurrectIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Phase icon
------------------------------------------------------------------------
local function UpdatePhaseIcon(f, unit)
    if not f.phaseIcon then return end
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    if conf.phaseIcon == false or not unit then
        f.phaseIcon:Hide()
        return
    end
    local reason
    if UnitIsPlayer and UnitIsPlayer(unit) and UnitPhaseReason then
        local conn = UnitIsConnected(unit)
        if issecretvalue and issecretvalue(conn) then conn = true end
        if conn then reason = UnitPhaseReason(unit) end
    end
    if reason then
        f.phaseIcon:SetTexture(ICON_TEX.phase)
        f.phaseIcon:Show()
    else
        f.phaseIcon:Hide()
    end
end

------------------------------------------------------------------------
-- Health color (GF-independent barMode, then global fallback)
-- Optional hp / hpMax parameters: when the caller (e.g. dispatchHealthFull)
-- already has fresh values, pass them to skip the GRADIENT-no-calc fallback's
-- duplicate UnitHealth/UnitHealthMax C-calls. nil/omitted → fetch as before.
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
        -- C-side path: ColorCurve + calculator → fully secret-safe, zero Lua math
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
        -- hp/hpMax if available — avoids redundant UnitHealth/UnitHealthMax
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

------------------------------------------------------------------------
-- Power color (secret-safe pToken)
------------------------------------------------------------------------
local function ApplyPowerColor(f, unit)
    if not (f.power and unit) then return end
    if not UnitExists(unit) then return end
    local _, pToken = UnitPowerType(unit)
    -- Secret-safe: pToken may be secret in 12.0
    if issecretvalue and pToken and issecretvalue(pToken) then
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
        return
    end
    if pToken and PowerBarColor and PowerBarColor[pToken] then
        local c = PowerBarColor[pToken]
        f.power:SetStatusBarColor(c.r or 0.5, c.g or 0.5, c.b or 0.5, 1)
    else
        f.power:SetStatusBarColor(0.5, 0.5, 0.8, 1)
    end
end

------------------------------------------------------------------------
-- Group number (raid subgroup) — secret-safe
------------------------------------------------------------------------
local function UpdateGroupNumber(f, unit)
    if not f.groupNumberText then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    if not conf.showGroupNumber then f.groupNumberText:Hide(); return end
    if not unit or not GetRaidRosterInfo then f.groupNumberText:Hide(); return end
    local idx = strmatch(unit, "^raid(%d+)$")
    if not idx then f.groupNumberText:Hide(); return end
    local raidIdx = tonumber(idx)
    if not raidIdx then f.groupNumberText:Hide(); return end
    local _, _, subgroup = GetRaidRosterInfo(raidIdx)
    if issecretvalue and issecretvalue(subgroup) then
        f.groupNumberText:SetText("")
        f.groupNumberText:Hide()
        return
    end
    local sg = tonumber(subgroup)
    if sg and sg >= 1 and sg <= 8 then
        f.groupNumberText:SetText(tostring(sg))
        f.groupNumberText:Show()
    else
        f.groupNumberText:Hide()
    end
end

------------------------------------------------------------------------
-- Full update for a single frame (called on unit assignment + events)
------------------------------------------------------------------------
local dispatchOverlays, dispatchIncomingHeal, dispatchAbsorb, dispatchHealAbsorb
local _GF_DispatchOverlaysFromCalc
local function UpdateAll(f, unit)
    if not f or not unit then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    GF.UpdateButton(f, unit)
    if c.rfEn then ApplyRangeFade(f, unit) end
    if c.needThreat then UpdateAggro(f, unit) end

    local _siOn = c.siEn
    if GF.UpdateSpellIndicators then
        if _siOn then GF.UpdateSpellIndicators(f, unit) else GF.HideSpellIndicators(f) end
    end

    if c.anyAuraGrp and GF.UpdateFrameAuras then
        GF.UpdateFrameAuras(f, unit)
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
    else
        if GF.UpdateFrameAuras then GF.UpdateFrameAuras(f, unit) end
        if c.dispelScan and GF._playerCanDispel then GF._UpdateDispel(f, unit) end
    end
    -- Debuff stripe (UpdateAll always does full refresh)
    if c.dsEn then
        f._msufGFHasAnyDebuff = (_FrameHasStripeDebuff and _FrameHasStripeDebuff(f, unit)) or false
        _GF_ApplyDebuffStripe(f)
    end
    UpdateTargetIndicator(f, unit)
    UpdateStatusText(f, unit)
    if c.healPredEn then dispatchOverlays(f, unit) end
    UpdateRoleIcon(f, unit)
    UpdateRaidMarker(f, unit)
    UpdateLeaderIcon(f, unit)
    if c.summonEn then UpdateSummonIcon(f, unit) end
    if c.resEn then UpdateResurrectIcon(f, unit) end
    if c.phaseEn then UpdatePhaseIcon(f, unit) end
    UpdateGroupNumber(f, unit)
    if c.ciEn and GF.UpdateCornerIndicators then GF.UpdateCornerIndicators(f, unit) end
    if c.paEn and GF.ApplyPrivateAuras then GF.ApplyPrivateAuras(f, unit) end
end

------------------------------------------------------------------------
-- Per-frame event dispatch table
------------------------------------------------------------------------

-- ════════════════════════════════════════════════════════════════════════
-- oUF-STYLE EVENT SPLIT: Each event only does what changed.
--
-- UNIT_HEALTH (10-50/s):      Bar + Text only. NO calculator, NO overlays.
-- UNIT_MAXHEALTH (~0.5/s):    Full chain (calc + bar + overlays + text).
-- UNIT_HEAL_PREDICTION:       Overlays only (incoming heals changed).
-- UNIT_ABSORB_AMOUNT_CHANGED: Overlays only (absorbs changed).
-- UNIT_HEAL_ABSORB_CHANGED:   Overlays only (heal absorbs changed).
--
-- This eliminates ~60% of Lua work per UNIT_HEALTH event.
-- Before: Calculator + SetMinMax + SetValue + Cutaway + Color + 3×Text
--         + 3×Overlay + HealthFade + StatusText = ~15 ops
-- After:  UnitHealth + SetValue + Cutaway + Text + StatusText = ~5 ops
-- ════════════════════════════════════════════════════════════════════════

------------------------------------------------------------------------
-- COALESCED TEXT FLUSH — batch all dirty GF frames via C_Timer.After(0)
-- Moves 3×FormatHealthText + 6×issecretvalue + UpdateStatusText (4 C-API
-- calls) OUT of the UNIT_HEALTH hot path into a single deferred flush.
-- In a 40-man raid at 50 UNIT_HEALTH/sec/unit = 2000 events/sec, this
-- eliminates ~20 Lua ops per event → ~40 000 ops/sec saved.
------------------------------------------------------------------------
local _gfTextDirtyFrames = {}    -- sparse: f = true
local _gfTextFlushQueued = false

local function _gfFlushDirtyText()
    _gfTextFlushQueued = false
    for f in pairs(_gfTextDirtyFrames) do
        _gfTextDirtyFrames[f] = nil
        local unit = f.unit
        if unit and f.health and f:IsVisible() then
            local c = f._c

            -- Health text fallback: only for uncompiled modes (anySlowText)
            if c and c.anySlowText then
                local hp    = UnitHealth(unit)
                local hpMax = f._msufGFCachedHpMax or UnitHealthMax(unit)
                local iss = issecretvalue
                if f.textLeftFS and c.tlOn and not c.tlFn then
                    local s = GF.FormatHealthText(c.tl, hp, hpMax, c.delim, c.rev, unit)
                    f.textLeftFS:SetText(s)
                end
                if f.textCenterFS and c.tcOn and not c.tcFn then
                    local s = GF.FormatHealthText(c.tc, hp, hpMax, c.delim, c.rev, unit)
                    f.textCenterFS:SetText(s)
                end
                if f.textRightFS and c.trOn and not c.trFn then
                    local s = GF.FormatHealthText(c.tr, hp, hpMax, c.delim, c.rev, unit)
                    f.textRightFS:SetText(s)
                end
            end

            -- Power text (set dirty by dispatchPower lean path)
            if f._msufGFPwTextDirty then
                f._msufGFPwTextDirty = nil
                if c and c.showPow then
                    local pw    = UnitPower(unit)
                    local pwMax = f._msufGFCachedPwMax or UnitPowerMax(unit)
                    local iss2 = issecretvalue
                    if f.powerTextLeftFS and c.ptlOn then
                        local s = GF.FormatPowerText(c.ptl, pw, pwMax, c.pDelim, unit)
                        local cv = f._msufGFCachedPTL
                        if (iss2 and (iss2(s) or (cv ~= nil and iss2(cv)))) or cv ~= s then
                            f._msufGFCachedPTL = (iss2 and iss2(s)) and nil or s
                            f.powerTextLeftFS:SetText(s)
                        end
                    end
                    if f.powerTextCenterFS and c.ptcOn then
                        local s = GF.FormatPowerText(c.ptc, pw, pwMax, c.pDelim, unit)
                        local cv = f._msufGFCachedPTC
                        if (iss2 and (iss2(s) or (cv ~= nil and iss2(cv)))) or cv ~= s then
                            f._msufGFCachedPTC = (iss2 and iss2(s)) and nil or s
                            f.powerTextCenterFS:SetText(s)
                        end
                    end
                    if f.powerTextRightFS and c.ptrOn then
                        local s = GF.FormatPowerText(c.ptr, pw, pwMax, c.pDelim, unit)
                        local cv = f._msufGFCachedPTR
                        if (iss2 and (iss2(s) or (cv ~= nil and iss2(cv)))) or cv ~= s then
                            f._msufGFCachedPTR = (iss2 and iss2(s)) and nil or s
                            f.powerTextRightFS:SetText(s)
                        end
                    end
                end
            end
        end
    end
end
-- Expose for manual flush (Options live-preview, unit show, etc.)
GF._FlushDirtyText = _gfFlushDirtyText
GF._TextDirtyFrames = _gfTextDirtyFrames

------------------------------------------------------------------------
-- LEAN PATH: UNIT_HEALTH (hottest: 10-50/s per unit, ×40 in raids)
--
-- oUF-style: absolute minimum work per event.
--   1. UnitHealth(unit)             — 1 C-call (secret)
--   2. bar:SetValue(hp)             — 1 C-call (secret-safe)
--   3. Cutaway timer (if enabled)   — reuse cached hpMax, no SetMinMax
--   4. Color (GRADIENT only)        — other modes stamp-gated elsewhere
--   5. Dirty flag for text+status   — coalesced flush next frame
--
-- REMOVED from hot path (vs. previous):
--   • UnitHealthMax()        — cached from UNIT_MAXHEALTH/init
--   • SetMinMaxValues()      — only on UNIT_MAXHEALTH
--   • 3×FormatHealthText     — coalesced text flush
--   • 6×issecretvalue        — coalesced text flush
--   • UpdateStatusText       — coalesced (4 C-API calls: Connected/Dead/AFK/DND)
--   • Cutaway SetMinMaxValues — uses cached hpMax
--   • Cutaway color stamp    — set once at config change / UNIT_MAXHEALTH
------------------------------------------------------------------------
local function dispatchHealthLean(f, unit)
    local bar = f.health
    if not bar then return end
    local c = f._c

    -- 1 C-call → secret value → C-side SetValue
    local hp = UnitHealth(unit)
    if c then
        local sm = c.smooth
        if sm then bar:SetValue(hp, sm) else bar:SetValue(hp) end
    else
        bar:SetValue(hp)
    end

    -- Dispel overlay health sync ("current health only" — secret-safe SetValue)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then dov:SetValue(hp) end

    -- Compiled fast text: pre-resolved closures call C-side directly.
    -- ~0.3μs/slot (vs 7.5μs with FormatHealthText). Zero mode dispatch,
    -- zero issecretvalue, zero string compare dedup.
    if c and c.anyFastText then
        local hm = f._msufGFCachedHpMax
        local fn = c.tlFn; if fn then fn(f.textLeftFS, unit, hp, hm) end
        fn = c.tcFn; if fn then fn(f.textCenterFS, unit, hp, hm) end
        fn = c.trFn; if fn then fn(f.textRightFS, unit, hp, hm) end
    end

    -- Cutaway: stamp-based (no Timer:Cancel per event).
    -- Just record when to snap. Callback checks stamp.
    local cw = f._msufCutaway
    if cw and c and c.cwEn then
        f._msufCwSnapAt = GetTime() + c.cwFade
        if not f._msufCwTicking then
            f._msufCwTicking = true
            if not f._msufCwTickFn then
                local frame = f
                f._msufCwTickFn = function()
                    frame._msufCwTicking = false
                    local cw2 = frame._msufCutaway
                    local snapAt = frame._msufCwSnapAt
                    if cw2 and snapAt and GetTime() >= snapAt then
                        if frame.unit and UnitExists(frame.unit) then
                            cw2:SetValue(UnitHealth(frame.unit))
                        end
                    elseif cw2 and snapAt then
                        -- Not yet: re-schedule for remaining time
                        frame._msufCwTicking = true
                        C_Timer.After(snapAt - GetTime(), frame._msufCwTickFn)
                    end
                end
            end
            C_Timer.After(c.cwFade, f._msufCwTickFn)
        end
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
        ApplyHealthColor(f, f._msufGFKind or "party", unit)
    end
end

------------------------------------------------------------------------
-- FULL PATH: UNIT_MAXHEALTH (rare — ~0.5/s)
-- Calculator → bar + text + ALL overlays. Full refresh.
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

    -- Dispel overlay health sync ("current health only" — secret-safe)
    local dov = f._msufGFDispelOverlay
    if dov and dov._msufDOSyncHP then
        dov:SetMinMaxValues(0, hpMax)
        dov:SetValue(hp)
    end

    -- Cutaway
    local cw = f._msufCutaway
    if cw and c.cwEn then
        cw:SetMinMaxValues(0, hpMax)
        -- Apply cutaway color (stamp-gated — only changes on config)
        if cw._cwStampR ~= c.cwR or cw._cwStampG ~= c.cwG or cw._cwStampB ~= c.cwB then
            cw._cwStampR, cw._cwStampG, cw._cwStampB = c.cwR, c.cwG, c.cwB
            cw:SetStatusBarColor(c.cwR, c.cwG, c.cwB, c.cwA)
        end
        if not cw:IsShown() then cw:Show() end
    end

    -- Color (full apply on maxHP change — handles unit-type transitions).
    -- Pass hp/hpMax through so the GRADIENT-no-calc fallback inside
    -- ApplyHealthColor doesn't re-fetch them.
    ApplyHealthColor(f, f._msufGFKind or "party", unit, hp, hpMax)

    -- Text: prefer compiled closures (oUF-style C-side dispatch, ~0.3µs/slot)
    -- over FormatHealthText (~7.5µs/slot). Falls back to FormatHealthText only
    -- for unknown/uncompiled modes (c.anySlowText). Closures handle secret
    -- values C-side via SetText / SetFormattedText.
    if c.anyText then
        if c.anyFastText then
            local fn = c.tlFn; if fn and f.textLeftFS   then fn(f.textLeftFS,   unit, hp, hpMax) end
            fn      = c.tcFn; if fn and f.textCenterFS then fn(f.textCenterFS, unit, hp, hpMax) end
            fn      = c.trFn; if fn and f.textRightFS  then fn(f.textRightFS,  unit, hp, hpMax) end
        end
        if c.anySlowText then
            if f.textLeftFS and c.tlOn and not c.tlFn then
                f.textLeftFS:SetText(GF.FormatHealthText(c.tl, hp, hpMax, c.delim, c.rev, unit))
            end
            if f.textCenterFS and c.tcOn and not c.tcFn then
                f.textCenterFS:SetText(GF.FormatHealthText(c.tc, hp, hpMax, c.delim, c.rev, unit))
            end
            if f.textRightFS and c.trOn and not c.trFn then
                f.textRightFS:SetText(GF.FormatHealthText(c.tr, hp, hpMax, c.delim, c.rev, unit))
            end
        end
    end
    UpdateStatusText(f, unit)

    -- Overlays from calculator
    if calc and not _G.MSUF_AbsorbTextureTestMode then
        local ihBar = f.incomingHealBar
        if ihBar then
            if c.healPredEn ~= false then
                local v = calc:GetIncomingHeals()
                if v ~= nil then ihBar:SetMinMaxValues(0, hpMax); ihBar:SetValue(v); if not ihBar:IsShown() then ihBar:Show() end
                else if ihBar:IsShown() then ihBar:Hide() end end
            else if ihBar:IsShown() then ihBar:Hide() end end
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
    elseif not calc then
        _GF_DispatchOverlaysFromCalc(f, unit, nil, hp, hpMax)
    end

    if c.hfEn and GF.ApplyHealthFade then
        GF.ApplyHealthFade(f, unit)
    end
end

------------------------------------------------------------------------
-- OVERLAY-ONLY PATH: UNIT_HEAL_PREDICTION / UNIT_ABSORB / UNIT_HEAL_ABSORB
-- Calculator → overlay bars ONLY. No HP bar, no text, no color.
------------------------------------------------------------------------
local function dispatchOverlaysOnly(f, unit)
    if not f.health then return end

    -- PERF: Same-frame dedup. UNIT_HEAL_PREDICTION + UNIT_ABSORB_AMOUNT_CHANGED
    -- + UNIT_HEAL_ABSORB_AMOUNT_CHANGED frequently fire in the same WoW frame
    -- (e.g. heal lands with absorb bubble). This function reads calc and
    -- renders ALL THREE overlay bars regardless of which event triggered it,
    -- so back-to-back calls in the same frame re-do identical work.
    -- GetTime() is frame-stable (constant within a frame, advances between).
    local nowT = GetTime()
    if f._msufGFOverlayT == nowT then return end
    f._msufGFOverlayT = nowT

    local c = f._c
    if not c then return end

    local calc = f._msufHPCalc
    if not calc and not _calcUnsupported then calc = _GF_EnsureCalc(f) end
    if not calc then
        -- No calculator: fall back to legacy per-overlay dispatch
        _GF_DispatchOverlaysFromCalc(f, unit, nil)
        return
    end

    UnitGetDetailedHealPrediction(unit, "player", calc)
    local hpMax = f._msufGFCachedHpMax or calc:GetMaximumHealth()

    if _G.MSUF_AbsorbTextureTestMode then return end

    local ihBar = f.incomingHealBar
    if ihBar and c.healPredEn ~= false then
        local v = calc:GetIncomingHeals()
        if v ~= nil then ihBar:SetMinMaxValues(0, hpMax); ihBar:SetValue(v); if not ihBar:IsShown() then ihBar:Show() end
        else if ihBar:IsShown() then ihBar:Hide() end end
    end
    local abBar = f.absorbBar
    if abBar and c.absorbEn then
        local v = calc:GetTotalDamageAbsorbs()
        if v ~= nil then abBar:SetMinMaxValues(0, hpMax); abBar:SetValue(v); if not abBar:IsShown() then abBar:Show() end
        else if abBar:IsShown() then abBar:Hide() end end
    end
    local haBar = f.healAbsorbBar
    if haBar and c.healAbsorbEn ~= false then
        local v = calc:GetTotalHealAbsorbs()
        if v ~= nil then haBar:SetMinMaxValues(0, hpMax); haBar:SetValue(v); if not haBar:IsShown() then haBar:Show() end
        else if haBar:IsShown() then haBar:Hide() end end
    end
end

------------------------------------------------------------------------
-- Health prediction overlays (absorb + incoming heal + heal absorb)
-- All 12.0 secret-safe: raw API values passed to C-side SetValue/SetMinMaxValues.
-- Show/hide: issecretvalue(val) → secret = Show (non-nil means has value).
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
-- Mode 1: left anchor (fill L→R)   absorbReverse=false
-- Mode 2: right anchor (fill R→L)  absorbReverse=true  (DEFAULT)
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

            -- Clip frame (mode 3 only — prevents absorb extending beyond bar)
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
    if f._msufGFAbsorbFollowActive then
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
    -- Test mode: fixed values (same as main UF preview)
    if _G.MSUF_AbsorbTextureTestMode then
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(20)
        if not bar:IsShown() then bar:Show() end
        return
    end
    -- PERF: use pre-cached healPredEn from BuildFrameCache (was GF.GetConf + DB read per call)
    local c = f._c
    if c and c.healPredEn == false then if bar:IsShown() then bar:Hide() end; return end
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
    if _G.MSUF_AbsorbTextureTestMode then
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
    if _G.MSUF_AbsorbTextureTestMode then
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
    if c.powH <= 0 then return end
    -- Role visibility: cached per-frame, only re-evaluated on GROUP_ROSTER_UPDATE
    local roleHidden = f._msufGFPowRoleHidden
    if roleHidden then if f.power:IsShown() then f.power:Hide() end; return end

    local pw = UnitPower(unit)
    if c.powSmooth then f.power:SetValue(pw, c.powSmooth) else f.power:SetValue(pw) end
    if not f.power:IsShown() then f.power:Show() end

    -- Coalesced power text: dirty flag → flush next frame
    if c.showPow and (c.ptlOn or c.ptcOn or c.ptrOn) then
        _gfTextDirtyFrames[f] = true
        f._msufGFPwTextDirty = true
        if not _gfTextFlushQueued then
            _gfTextFlushQueued = true
            C_Timer.After(0, _gfFlushDirtyText)
        end
    end
end

-- UNIT_MAXPOWER: full power path (SetMinMaxValues + inline text)
local function dispatchPowerFull(f, unit)
    if not f.power then return end
    local c = f._c
    if not c then GF.BuildFrameCache(f); c = f._c end
    if c.powH <= 0 then return end
    local roleHidden = f._msufGFPowRoleHidden
    if roleHidden then if f.power:IsShown() then f.power:Hide() end; return end

    local pw    = UnitPower(unit)
    local pwMax = UnitPowerMax(unit)
    f.power:SetMinMaxValues(0, pwMax)
    if c.powSmooth then f.power:SetValue(pw, c.powSmooth) else f.power:SetValue(pw) end
    f._msufGFCachedPwMax = pwMax
    if not f.power:IsShown() then f.power:Show() end

    -- Inline text on full path (rare event ~0.5/s)
    if c.showPow then
        local iss = issecretvalue
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
    if f.nameText then
        local kind = f._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        if conf.showName ~= false then
            local name = UnitName(unit) or ""
            local maxC = conf.nameMaxChars or 0
            if maxC > 0 then
                name = GF.TruncateName(name, maxC, conf.nameNoEllipsis)
            end
            f.nameText:SetText(name)
            -- Cache class token (avoids C API call in ApplyHealthColor hot path)
            local _, classToken = UnitClass(unit)
            f._msufGFClass = classToken
            local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
            f.nameText:SetTextColor(nr, ng, nb, 1)
        end
    end
end

local UNIT_DISPATCH = {
    -- oUF-STYLE SPLIT: Each event does only what changed.
    UNIT_HEALTH                       = dispatchHealthLean,   -- Bar + Text ONLY (hottest: 10-50/s)
    UNIT_MAXHEALTH                    = dispatchHealthFull,   -- Full chain (rare: ~0.5/s)
    UNIT_HEAL_PREDICTION              = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_ABSORB_AMOUNT_CHANGED        = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED   = dispatchOverlaysOnly, -- Overlays ONLY
    UNIT_POWER_UPDATE                 = dispatchPower,
    UNIT_MAXPOWER                     = dispatchPowerFull,
    UNIT_DISPLAYPOWER                 = dispatchDisplayPower,
    UNIT_NAME_UPDATE                  = dispatchName,
    UNIT_CONNECTION                   = function(f, u) UpdateStatusText(f, u); ApplyRangeFade(f, u) end,
    UNIT_FLAGS                        = function(f, u) UpdateStatusText(f, u); UpdateRoleIcon(f, u); UpdateLeaderIcon(f, u) end,
    UNIT_IN_RANGE_UPDATE              = function(f, u, inRange) ApplyRangeFade(f, u, inRange) end,
    UNIT_AURA                         = function(f, u, updateInfo)
        dispatchAura(f, u, updateInfo)
    end,
    UNIT_THREAT_SITUATION_UPDATE      = function(f, u) UpdateAggro(f, u) end,
    UNIT_THREAT_LIST_UPDATE           = function(f, u) UpdateAggro(f, u) end,
    INCOMING_SUMMON_CHANGED           = function(f, u) UpdateSummonIcon(f, u); UpdateResurrectIcon(f, u) end,
    INCOMING_RESURRECT_CHANGED        = function(f, u) UpdateResurrectIcon(f, u) end,
    UNIT_PHASE                        = function(f, u) UpdatePhaseIcon(f, u) end,
}

------------------------------------------------------------------------
-- Per-frame OnEvent handler
-- oUF-STYLE: Each event dispatches ONLY to the handler that needs it.
-- UNIT_HEALTH → lean path (bar + text only, NO calc/overlays)
-- UNIT_MAXHEALTH → full path (calc + bar + overlays + text)
-- UNIT_HEAL_PREDICTION/ABSORB → overlays only
------------------------------------------------------------------------
local function GF_OnEvent(self, event, unit, ...)
    local u = self.unit
    if not u then return end
    -- PERF: unified hash-table dispatch. The prior hot-path if-elseif chain
    -- did 6-7 string compares (~1µs) before falling through to UNIT_DISPATCH.
    -- A direct table lookup is O(1) (~0.05µs). Net win: ~1µs per event.
    local fn = UNIT_DISPATCH[event]
    if fn then return fn(self, u, ...) end
end

------------------------------------------------------------------------
-- RegisterUnitEvents / UnregisterUnitEvents (replaces Phase 1 stubs)
------------------------------------------------------------------------
function GF.RegisterUnitEvents(f, unit)
    if not (f and unit) then return end
    f._msufGFFullPending = nil

    if not f._c then GF.BuildFrameCache(f) end
    local c = f._c

    -- Diff-gate: skip if same unit and same event bitmask
    local evBits = c._evBits or 0
    if f._msufGFRegUnit == unit and f._msufGFRegBits == evBits and f._msufGFRegEv then
        return
    end
    f._msufGFRegUnit = unit
    f._msufGFRegBits = evBits

    -- GUID→frame map (rebuilt on roster change, used for O(1) target/focus scan)
    local guid = UnitGUID and UnitGUID(unit)
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
    f:RegisterUnitEvent("UNIT_CONNECTION", unit);     regTbl["UNIT_CONNECTION"] = true
    f:RegisterUnitEvent("UNIT_FLAGS", unit);          regTbl["UNIT_FLAGS"] = true

    if c.nameEn then
        f:RegisterUnitEvent("UNIT_NAME_UPDATE", unit); regTbl["UNIT_NAME_UPDATE"] = true
    end
    if c.powH > 0 then
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", unit);  regTbl["UNIT_POWER_UPDATE"] = true
        f:RegisterUnitEvent("UNIT_MAXPOWER", unit);      regTbl["UNIT_MAXPOWER"] = true
        f:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit);  regTbl["UNIT_DISPLAYPOWER"] = true
    end
    if c.rfEn then
        f:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit); regTbl["UNIT_IN_RANGE_UPDATE"] = true
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
    if c.phaseEn then
        f:RegisterUnitEvent("UNIT_PHASE", unit); regTbl["UNIT_PHASE"] = true
    end
    if c.healPredEn then
        f:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit); regTbl["UNIT_HEAL_PREDICTION"] = true
    end
    if c.absorbEn then
        if UnitGetTotalAbsorbs then
            f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_ABSORB_AMOUNT_CHANGED"] = true
        end
        if UnitGetTotalHealAbsorbs then
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = true
        end
    elseif c.healAbsorbEn then
        -- Heal absorb enabled independently of shield absorb bar
        if UnitGetTotalHealAbsorbs then
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit); regTbl["UNIT_HEAL_ABSORB_AMOUNT_CHANGED"] = true
        end
    end

    f:SetScript("OnEvent", GF_OnEvent)

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
local function _gfRosterFlush()
    _gfRosterPending = false
    _gfTargetFrame = nil
    _gfFocusFrame  = nil
    -- Rebuild GUID→frame map (GUIDs change on roster change)
    local gmap = GF._guidMap
    if gmap then wipe(gmap) else gmap = {}; GF._guidMap = gmap end
    for f in pairs(GF.frames) do
        local u = f.unit
        if u and UnitExists(u) then
            local guid = UnitGUID and UnitGUID(u)
            if guid and not (issecretvalue and issecretvalue(guid)) then
                gmap[guid] = f
            end
            dispatchName(f, u)
            ApplyHealthColor(f, f._msufGFKind or "party", u)
            ApplyPowerColor(f, u)
            UpdateStatusText(f, u)
            UpdateRoleIcon(f, u)
            UpdateRaidMarker(f, u)
            UpdateLeaderIcon(f, u)
            UpdateGroupNumber(f, u)
            if UnitIsUnit(u, "target") then
                f._msufGFIsTarget = true
                _gfTargetFrame = f
            end
            if UnitExists("focus") and UnitIsUnit(u, "focus") then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
            end
            UpdateTargetIndicator(f, u)
        end
    end
end

-- Exported for consolidated PLAYER_TARGET_CHANGED handler in UFCore
_G.MSUF_GF_OnTargetChanged = function()
    local oldTarget = _gfTargetFrame
    _gfTargetFrame = nil
    if oldTarget and oldTarget.unit then
        oldTarget._msufGFIsTarget = nil
        _GF_QuickBorderUpdate(oldTarget)
    end
    local tGUID = UnitGUID and UnitGUID("target")
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
local function OnGlobalEvent(self, event, ...)
    -- Fix 3: when GF is fully disabled, do nothing. Saves the per-event
    -- dispatch + empty-loop cost across PLAYER_FOCUS_CHANGED, READY_CHECK*,
    -- RAID_TARGET_UPDATE, PARTY_LEADER_CHANGED, GROUP_ROSTER_UPDATE,
    -- BARBER_SHOP_OPEN/CLOSE, PLAYER_FLAGS_CHANGED. Flag is maintained by
    -- RebuildAll and the PLAYER_REGEN_ENABLED retire-deferral path.
    if not GF._anyEnabled then return end

    if event == "PLAYER_FOCUS_CHANGED" then
        local oldFocus = _gfFocusFrame
        _gfFocusFrame = nil
        if oldFocus and oldFocus.unit then
            oldFocus._msufGFIsFocus = nil
            _GF_QuickBorderUpdate(oldFocus)
        end
        local fGUID = UnitGUID and UnitExists("focus") and UnitGUID("focus")
        if fGUID and not (issecretvalue and issecretvalue(fGUID)) then
            local gmap = GF._guidMap
            local f = gmap and gmap[fGUID]
            if f and f.unit then
                f._msufGFIsFocus = true
                _gfFocusFrame = f
                _GF_QuickBorderUpdate(f)
            end
        end

    elseif event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, event) end
        end

    elseif event == "READY_CHECK_FINISHED" then
        for f in pairs(GF.frames) do
            if f.unit then UpdateReadyCheck(f, f.unit, "READY_CHECK_FINISHED") end
        end

    elseif event == "RAID_TARGET_UPDATE" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateRaidMarker(f, f.unit) end
        end

    elseif event == "PARTY_LEADER_CHANGED" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then UpdateLeaderIcon(f, f.unit) end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- PERF: Coalesce roster updates. At a world boss, GROUP_ROSTER_UPDATE
        -- fires 0.5/sec with 672µs P50 per call (iterates all 40 GF frames × 10 functions).
        -- Multiple updates can fire in the same frame (join + promote + type change).
        -- Coalescing to next-frame eliminates burst spikes in the Blizzard profiler.
        if not _gfRosterPending then
            _gfRosterPending = true
            _gfTargetFrame = nil
            _gfFocusFrame  = nil
            if _After0 then
                _After0(0, _gfRosterFlush)
            else
                _gfRosterFlush()
            end
        end
    elseif event == "BARBER_SHOP_OPEN" then
        -- hideInClientScene: hide all GF headers when entering barber/dressing room
        for _, headerKind in ipairs({"party", "raid"}) do
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
    elseif event == "BARBER_SHOP_CLOSE" then
        for _, scope in ipairs({"party", "raid"}) do
            local header = GF.headers and GF.headers[scope]
            if header and header._msufGF_clientSceneHidden then
                header._msufGF_clientSceneHidden = nil
                header:SetAlpha(1)
            end
        end

    elseif event == "PLAYER_FLAGS_CHANGED" then
        for f in pairs(GF.frames) do
            if f.unit and UnitExists(f.unit) then
                UpdateStatusText(f, f.unit)
            end
        end
    end
end

_globalFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
_globalFrame:RegisterEvent("READY_CHECK")
_globalFrame:RegisterEvent("READY_CHECK_CONFIRM")
_globalFrame:RegisterEvent("READY_CHECK_FINISHED")
_globalFrame:RegisterEvent("RAID_TARGET_UPDATE")
_globalFrame:RegisterEvent("PARTY_LEADER_CHANGED")
_globalFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_globalFrame:RegisterEvent("BARBER_SHOP_OPEN")
_globalFrame:RegisterEvent("BARBER_SHOP_CLOSE")
_globalFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
_globalFrame:SetScript("OnEvent", OnGlobalEvent)

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

local _hoverBdCache = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local function EnsureMouseoverHighlight(f)
    if not _GF_IsHighlightEnabled() then return nil end
    local hb = f._msufGFHoverBorder
    if hb then
        -- Already exists: just return it. Style is set at creation + config change.
        return hb
    end
    local kind = f._msufGFKind or "party"
    local sz = math_max(1, tonumber(HLVal(kind, "hlHoverSize")) or 1)
    local ofs = tonumber(HLVal(kind, "hlHoverOffset")) or 0
    local r, g, b = _GF_GetHighlightColor()
    local anchor = f.barGroup or f
    hb = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    hb:SetPoint("TOPLEFT", -ofs, ofs)
    hb:SetPoint("BOTTOMRIGHT", ofs, -ofs)
    hb:SetFrameLevel(anchor:GetFrameLevel() + 6)
    hb:EnableMouse(false)
    _hoverBdCache.edgeSize = sz
    hb:SetBackdrop(_hoverBdCache)
    hb:SetBackdropBorderColor(r, g, b, 0.7)
    hb:SetBackdropColor(0, 0, 0, 0)
    hb:Hide()
    f._msufGFHoverBorder = hb
    return hb
end

------------------------------------------------------------------------
-- Tooltip + Highlight hooks
------------------------------------------------------------------------
local _tooltipPending -- C_Timer handle for deferred tooltip
local _tooltipTarget  -- frame awaiting tooltip

local function OnEnter(f)
    -- Mouseover highlight
    local hb = EnsureMouseoverHighlight(f)
    if hb then hb:Show() end
    -- Cancel any pending tooltip for a different frame
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = f
    -- Tooltip (throttled 150ms)
    if not f.unit or not UnitExists(f.unit) then return end
    local conf = GF.GetConf(f._msufGFKind or "party")
    local mode = conf.tooltipMode or "ALWAYS"
    if mode == "NEVER" then return end
    if mode == "OOC" and InCombatLockdown() then return end
    if mode == "MODIFIER" then
        local mod = conf.tooltipModifier or "ALT"
        if mod == "ALT"   and not IsAltKeyDown()     then return end
        if mod == "CTRL"  and not IsControlKeyDown()  then return end
        if mod == "SHIFT" and not IsShiftKeyDown()    then return end
    end
    _tooltipPending = C_Timer.NewTimer(0.15, function()
        _tooltipPending = nil
        if _tooltipTarget ~= f then return end
        if not f.unit or not UnitExists(f.unit) then return end
        if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
            _G.GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            _G.GameTooltip:SetUnit(f.unit)
            _G.GameTooltip:Show()
        end
    end)
end

local function OnLeave(f)
    -- Cancel pending tooltip
    if _tooltipPending then _tooltipPending:Cancel(); _tooltipPending = nil end
    _tooltipTarget = nil
    -- Hide highlight
    if f._msufGFHoverBorder then f._msufGFHoverBorder:Hide() end
    -- Hide tooltip
    if _G.GameTooltip and not _G.GameTooltip:IsForbidden() then
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
        -- GF frames do NOT use the main Alpha module.
        -- Range fade is handled exclusively by ApplyRangeFade → SetAlphaFromBoolean.
        -- The Alpha module (MSUF_ApplyUnitAlpha) would override SetAlphaFromBoolean
        -- with SetAlpha(1), killing the range fade.
    end
end

------------------------------------------------------------------------
-- Expose
------------------------------------------------------------------------
--- Combined highlight refresh (aggro + dispel + target) — called by
--- Borders.lua test mode buttons via _G.MSUF_GF_UpdateHighlight
local function UpdateHighlight(f, unit)
    unit = unit or f.unit
    if not unit then return end
    UpdateAggro(f, unit)
    GF._UpdateDispel(f, unit)
    UpdateTargetIndicator(f, unit)
end

_G.MSUF_GF_UpdateAll     = UpdateAll
_G.MSUF_GF_UpdateAggro   = UpdateAggro
_G.MSUF_GF_UpdateDispel   = GF._UpdateDispel
_G.MSUF_GF_UpdateHighlight = UpdateHighlight
_G.MSUF_GF_UpdateRange    = ApplyRangeFade
_G.MSUF_GF_UpdateTarget   = UpdateTargetIndicator
_G.MSUF_GF_UpdateStatus   = UpdateStatusText
_G.MSUF_GF_UpdateGroupNum = UpdateGroupNumber

------------------------------------------------------------------------
-- Memory-leak Fix 1: Frame-retire cleanup hook
-- Called from RetireHeader for every child being retired. Removes the
-- frame from every module-level table that strong-refs it, and cancels
-- any pending Closure-Timer that captures the frame as upvalue.
--
-- Without this, retired frames live up to ~6s longer than necessary
-- (ready-check fade timer) and module tables accumulate stale refs
-- between retire and next GROUP_ROSTER_UPDATE.
--
-- Defined as upvalue-closure so it sees:
--   _readyCheckTimers, _gfTargetFrame, _gfFocusFrame, _tooltipPending,
--   _tooltipTarget, _gfTextDirtyFrames
-- which are file-scope locals.
------------------------------------------------------------------------
local function _GF_OnFrameRetire(f)
    if not f then return end

    -- Cancel + clear pending ready-check fade timer (closure captures `f`)
    local rcTimer = _readyCheckTimers[f]
    if rcTimer then
        if type(rcTimer.Cancel) == "function" then rcTimer:Cancel() end
        _readyCheckTimers[f] = nil
    end

    -- Stop cutaway re-schedule loop (closure self-cancels when _msufCwTicking false)
    f._msufCwTicking = false
    f._msufCwSnapAt  = nil

    -- Clear target / focus pointers if pointing at this frame
    if _gfTargetFrame == f then _gfTargetFrame = nil end
    if _gfFocusFrame  == f then _gfFocusFrame  = nil end

    -- Cancel pending tooltip if it targets this frame
    if _tooltipTarget == f then
        if _tooltipPending and type(_tooltipPending.Cancel) == "function" then
            _tooltipPending:Cancel()
        end
        _tooltipPending = nil
        _tooltipTarget  = nil
    end

    -- Drop pending text-flush entry (avoids dangling key in dirty set)
    _gfTextDirtyFrames[f] = nil

    -- Remove from GUID→frame map (search by value — guid hash unknown here)
    local gmap = GF._guidMap
    if gmap then
        for guid, framef in pairs(gmap) do
            if framef == f then gmap[guid] = nil end
        end
    end

    -- Drop from render dirty queue (Render module owns _dirtyFrames; expose helper if missing)
    if GF._RetireFromDirty then GF._RetireFromDirty(f) end
end
_G.MSUF_GF_OnFrameRetire = _GF_OnFrameRetire
GF.GetDispelColor     = GetDispelColor
GF.ResolveDispelColor = ResolveDispelColor

-- Dispel overlay: refresh all frames (called from Options when settings change)
_G.MSUF_GF_RefreshDispelOverlay = function()
    if not GF.frames then return end
    for f in pairs(GF.frames) do
        if f._msufIsGroupFrame then
            GF.BuildFrameCache(f)
            _GF_ApplyDispelOverlay(f)
        end
    end
end
-- Single-frame overlay apply (for Borders.lua test-mode cleanup)
_G.MSUF_GF_ApplyDispelOverlay = _GF_ApplyDispelOverlay

-- Debuff stripe: refresh all frames (called from Options when settings change)
_G.MSUF_GF_RefreshDebuffStripe = function()
    if not GF.frames then return end
    for f in pairs(GF.frames) do
        if f._msufIsGroupFrame then
            GF.BuildFrameCache(f)
            _GF_ApplyDebuffStripe(f)
        end
    end
end
_G.MSUF_GF_ApplyDebuffStripe = _GF_ApplyDebuffStripe

-- Exports for Perfy profiling (target-click spike diagnosis)
_G.MSUF_GF_QuickBorderUpdate   = _GF_QuickBorderUpdate
_G.MSUF_GF_RefreshBorder        = _GF_RefreshBorder
_G.MSUF_GF_ApplyHLBorderStyle   = _applyHighlightBorderStyle
_G.MSUF_GF_BuildFrameCache      = GF.BuildFrameCache
_G.MSUF_GF_GlobalEventFrame     = _globalFrame

--- Refresh overlay bars (absorb + heal absorb + incoming heal) on all GF frames.
--- Called from Bars options when test mode or absorb settings change.
_G.MSUF_GF_RefreshOverlays = function()
    if not GF.frames then return end
    local testMode = _G.MSUF_AbsorbTextureTestMode
    for f in pairs(GF.frames) do
        if f._msufIsGroupFrame then
            _GF_ApplyAbsorbAnchor(f)
            local u = f.unit
            if u then
                dispatchOverlays(f, u)
            elseif testMode then
                dispatchIncomingHeal(f, nil)
                dispatchAbsorb(f, nil)
                dispatchHealAbsorb(f, nil)
            end
        end
    end
    if GF._previewFrames then
        for _, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local pf = list[i]
                if pf then
                    _GF_ApplyAbsorbAnchor(pf)
                    local u = pf.unit or pf._msufGFPreviewUnit
                    if u then
                        dispatchOverlays(pf, u)
                    elseif testMode then
                        dispatchIncomingHeal(pf, nil)
                        dispatchAbsorb(pf, nil)
                        dispatchHealAbsorb(pf, nil)
                    end
                end
            end
        end
    end
end
GF._ApplyHealthColor      = ApplyHealthColor
GF._ApplyAbsorbAnchor     = _GF_ApplyAbsorbAnchor
GF._ReadOverlayColor      = _GF_ReadOverlayColor

-- Perfy idle-diagnosis exports (zero cost when Perfy absent)
_G.MSUF_GF_DispatchHealth  = dispatchHealthFull  -- Full refresh (for Options/manual use)
_G.MSUF_GF_DispatchPower   = dispatchPower
_G.MSUF_GF_DispatchAura    = dispatchAura
_G.MSUF_GF_DispatchOverlays = dispatchOverlays
_G.MSUF_GF_ApplyPowerColor = ApplyPowerColor
_G.MSUF_GF_OnEvent         = GF_OnEvent
_G.MSUF_GF_PixelSnap       = _GF_PixelSnappedSetValue
