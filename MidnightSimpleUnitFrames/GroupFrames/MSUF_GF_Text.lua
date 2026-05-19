-- MSUF_GF_Text.lua
-- Group Frame text-slot compilation. Build-time only: creates per-slot C-side
-- text functions used by MSUF_GF_Effects.lua without adding runtime allocations.

local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
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

    local tl = c.tl or "NONE"
    local tc = c.tc or "NONE"
    local tr = c.tr or "NONE"

    c.tlFn = c.tlOn and _BuildTextFn(tl, abbrFn, delim, pctFmt) or nil
    c.tcFn = c.tcOn and _BuildTextFn(tc, abbrFn, delim, pctFmt) or nil
    c.trFn = c.trOn and _BuildTextFn(tr, abbrFn, delim, pctFmt) or nil
    -- Flag: any compiled text fn exists (fast skip in lean path)
    c.anyFastText = (c.tlFn or c.tcFn or c.trFn) and true or false
    -- Flag: any slot needs fallback (unknown mode)
    c.anySlowText = (c.tlOn and not c.tlFn) or (c.tcOn and not c.tcFn) or (c.trOn and not c.trFn) or false
end
GF.BuildTextSlotFns = _BuildSlotFns

------------------------------------------------------------------------
-- Runtime text dirty queue. Kept with text compilation so text scheduling,
-- fallback formatting, and retire cleanup share one owner.
------------------------------------------------------------------------
local C_Timer = _G.C_Timer
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax

local function _MSUF_ScheduleOnce(key, fn)
    local sched = _G.MSUF_ScheduleOnce
    if sched then return sched(key, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(0, fn) end
    if type(fn) == "function" then return fn() end
end

local function UpdateStatusText(f, unit)
    local fn = GF.UpdateStatusText or _G.MSUF_GF_UpdateStatus
    if type(fn) == "function" then return fn(f, unit) end
end
-- COALESCED TEXT FLUSH Ã¢â‚¬â€ batch all dirty GF frames via C_Timer.After(0)
-- Moves 3Ãƒâ€”FormatHealthText + 6Ãƒâ€”issecretvalue + UpdateStatusText (4 C-API
-- calls) OUT of the UNIT_HEALTH hot path into a single deferred flush.
-- In a 40-man raid at 50 UNIT_HEALTH/sec/unit = 2000 events/sec, this
-- eliminates ~20 Lua ops per event Ã¢â€ â€™ ~40 000 ops/sec saved.
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

function GF.RetireTextState(f)
    if not f then return end
    _gfTextDirtyFrames[f] = nil
    _gfTextQueued[f] = nil
    f._msufGFStatusDirty = nil
    f._msufGFNameCacheKey = nil
    f._msufGFNameStyleKey = nil
    f._msufGFNameText = nil
    f._msufGFNameClass = nil
    f._msufGFNameColorKey = nil
end
GF._TextQueued = _gfTextQueued
