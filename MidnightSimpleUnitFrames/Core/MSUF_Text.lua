-- Core/MSUF_Text.lua  Core text rendering (HP, power, name, level, separators)
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, select = type, tonumber, select
local string_format = string.format

-- PERF: Resolve issecretvalue once at load. Must be before any function that
-- uses it (ns.Text.Set, RenderHpMode, RenderPowerText).
local _MSUF_issecret = _G.issecretvalue
local _MSUF_IsSecret
if type(_MSUF_issecret) == "function" then
    _MSUF_IsSecret = function(v) return _MSUF_issecret(v) and true or false end
else
    _MSUF_IsSecret = function() return false end
end

ns.Text._msufPatchD = ns.Text._msufPatchD or { version = "D1" }
function ns.Text.Set(fs, text, show)
    -- Secret-safe: do NOT compare secret strings.
    if not fs then  return end
    if not show then
        if fs.Hide then fs:Hide() end
        if fs._msufLastSetT then fs._msufLastSetT = nil end
        if fs.SetText then fs:SetText("") end
         return
    end
    if text == nil then text = "" end
    -- PERF: Skip SetText if text unchanged. Saves C-side string copy + layout
    -- invalidation + GC of the old internal string.
    -- Secret-safe: issecretvalue guards the comparison. Secret strings
    -- (from ShortenNumber on secret UnitPower values) fall through to SetText.
    -- P0: Use file-scope upvalue (_MSUF_issecret) instead of _G lookup per call.
    if not _MSUF_issecret or not _MSUF_issecret(text) then
        if text == fs._msufLastSetT then
            if fs.Show then fs:Show() end
            return
        end
        fs._msufLastSetT = text
    else
        fs._msufLastSetT = nil
    end
    if fs.SetText then fs:SetText(text) end
    if fs.Show then fs:Show() end
 end
ns.Text._msufPatchE = ns.Text._msufPatchE or { version = "E1" }
-- Secret-safe: numeric clamps only; no text comparisons.
ns.Text._msufPatchG = ns.Text._msufPatchG or { version = "G1" }
function ns.Text.ClampSpacerValue(value, maxValue, enabled)
    if not enabled then  return 0 end
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    local m = tonumber(maxValue) or 0
    if m < 0 then m = 0 end
    if v > m then v = m end
     return v
end
_G.MSUF_TEXTLAYOUT_VALID_KEYS = _G.MSUF_TEXTLAYOUT_VALID_KEYS or { player=true, target=true, focus=true, targettarget=true, pet=true, boss=true }
function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, fallbackKey)
    local k = unitKey
    if not k or k == "" then local _g = MSUF_DB and MSUF_DB.general; k = fallbackKey or (_g and _g.hpSpacerSelectedUnitKey) or "player" end
    if k == "tot" then k = "targettarget" end
    -- Perf: avoid pattern matching in hot layout paths.
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(k) then k = "boss" end
    if not _G.MSUF_TEXTLAYOUT_VALID_KEYS[k] then k = "player" end
     return k
end
function ns.Text.SetFormatted(fs, show, fmt, ...)
    -- Secret-safe: do NOT compare results. Pass-through to FontString API.
    if not fs then  return end
    if not show then
        if fs.Hide then fs:Hide() end
        if fs._msufLastSetT then fs._msufLastSetT = nil end
        if fs.SetText then fs:SetText("") end
         return
    end
    -- Invalidate diff cache (SetFormattedText changes text through C side)
    fs._msufLastSetT = nil
    if fs.SetFormattedText then
        fs:SetFormattedText(fmt, ...)
    else
        -- Fallback: avoid string.format on potentially secret args; just clear.
        if fs.SetText then fs:SetText("") end
    end
    if fs.Show then fs:Show() end
 end
function ns.Text.Clear(fs, hide)
    -- Secret-safe: do NOT compare strings.
    if not fs then  return end
    if fs._msufLastSetT then fs._msufLastSetT = nil end
    if fs.SetText then fs:SetText("") end
    if hide and fs.Hide then fs:Hide() end
 end
function ns.Text.ClearField(self, field)
    if not self then  return end
    local fs = self[field]
    if not fs then  return end
    ns.Text.Clear(fs, true)
 end
-- Patch O: central text renderers (HP/Power/Pct/ToT inline) - secret-safe (no string compares)
function ns.Text._SepToken(raw, fallback)
    -- Accept legacy/malformed values (e.g. false) safely.
    local sep = raw
    if sep == nil or sep == false then sep = fallback end
    if sep == nil or sep == false then sep = "" end
    if type(sep) ~= "string" then
        -- Treat non-string separators as "none" (prevents concat errors).
        sep = ""
    end
    if sep == "" then
         return " "
    end
    return " " .. sep .. " "
end
function ns.Text._ShouldSplitHP(self, conf, g, hpMode)
    if not self or not self.hpTextPct then  return false end
    if hpMode ~= "FULL_PLUS_PERCENT" and hpMode ~= "PERCENT_PLUS_FULL" then  return false end
    local on = (conf and conf.hpTextSpacerEnabled == true) or (not conf and g and g.hpTextSpacerEnabled == true)
    if not on then  return false end
    local x = (conf and tonumber(conf.hpTextSpacerX)) or (g and tonumber(g.hpTextSpacerX)) or 0
    x = tonumber(x) or 0
    return (x > 0)
end
-- HP mode format dispatcher. Mirrors _MSUF_FormatPowerByMode pattern.
-- Returns mainText. hpPctStr may be nil (secret percent → caller handles).
local function _MSUF_FormatHpByMode(mode, h, hpPctStr, sep)
    if mode == "FULL_ONLY" then
        return h
    elseif mode == "PERCENT_ONLY" then
        return hpPctStr or h
    elseif mode == "PERCENT_PLUS_FULL" then
        if hpPctStr then return hpPctStr .. sep .. h end
        return h
    end
    -- FULL_PLUS_PERCENT (default)
    if hpPctStr then return h .. sep .. hpPctStr end
    return h
end
-- Absorb text suffix. Secret-safe: absorbText is from C-side TruncateWhenZero.
local function _MSUF_AppendAbsorb(text, absorbText, absorbStyle)
    if not absorbText then return text end
    if absorbStyle == "PAREN" then return text .. " (" .. absorbText .. ")" end
    return text .. " " .. absorbText
end
-- Secret-percent fallback (rare: <0.1% of calls). Uses C-side SetFormattedText.
local function _MSUF_SetHpSecret(fs, mode, h, hpPct, sep, absorbText, absorbStyle)
    if mode == "FULL_ONLY" then
        ns.Text.Set(fs, _MSUF_AppendAbsorb(h, absorbText, absorbStyle), true)
    elseif mode == "PERCENT_ONLY" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sfx, hpPct, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%", hpPct)
        end
    elseif mode == "PERCENT_PLUS_FULL" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sfx, hpPct, h, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s", hpPct, h)
        end
    else
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%.1f%%" .. sfx, h, hpPct, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%.1f%%", h, hpPct)
        end
    end
end
-- Pre-build common percent strings (0%-100% integer AND 0.0%-100.0% with one decimal)
-- to avoid per-frame string allocations. Integer cache for power text, decimal cache for HP text.
local _MSUF_PCT_CACHE = {}
for _pci = 0, 100 do _MSUF_PCT_CACHE[_pci] = tostring(_pci) .. "%" end
-- Decimal cache: keyed by 10x value (e.g. 753 = "75.3%"). Covers 0.0 to 100.0.
local _MSUF_PCT_CACHE_1D = {}
for _pci10 = 0, 1000 do
    local whole = math.floor(_pci10 / 10)
    local frac = _pci10 - (whole * 10)
    _MSUF_PCT_CACHE_1D[_pci10] = tostring(whole) .. "." .. tostring(frac) .. "%"
end
-- PERF: Fast percent-to-string using pre-built cache. Eliminates C-side format calls.
-- Returns cached "75.3%" string for values 0.0-100.0; falls back to format for out-of-range.
-- SECRET-SAFE: Must bail on secret numbers before any arithmetic.
local _string_format = string.format
local _pct1d_issecret = _G.issecretvalue  -- resolve once; nil if API absent
local function _MSUF_PctToStr1D(pct)
    if pct == nil then return nil end
    if _pct1d_issecret and _pct1d_issecret(pct) then return nil end
    if type(pct) ~= "number" then return nil end
    local key = math.floor(pct * 10 + 0.5)
    if key >= 0 and key <= 1000 then
        return _MSUF_PCT_CACHE_1D[key]
    end
    return _string_format("%.1f%%", pct)
end
function ns.Text.RenderHpMode(self, show, hpStr, hpPct, hasPct, conf, g, absorbText, absorbStyle)
    if not self or not self.hpText then  return end
    if not show then
        ns.Text.Set(self.hpText, "", false)
        ns.Text.ClearField(self, "hpTextPct")
        return
    end

    local spec = ns.Text.EnsureSpec(self)
    local hpMode = spec.hpMode
    local sep = spec.hpSep
    local hpText = self.hpText
    local h = hpStr or ""

    -- Pre-compute percent string (nil for secret values → SetFormattedText fallback)
    local hpPctStr = hasPct and _MSUF_PctToStr1D(hpPct) or nil

    -- Split path: HP in main FontString, percent in side FontString
    local split = hasPct and ns.Text._ShouldSplitHP(self, spec.hpSpacerConf, spec.hpSpacerG, hpMode) or false
    if split then
        local mainText = _MSUF_AppendAbsorb(h, absorbText, absorbStyle)
        if not absorbText and not _MSUF_IsSecret(h) and h == self._msufLastH and hpPctStr == self._msufLastPctS then return end
        if _MSUF_IsSecret(h) or absorbText then self._msufLastH = nil else self._msufLastH = h end
        self._msufLastPctS = hpPctStr
        ns.Text.Set(hpText, mainText, true)
        if hpPctStr then
            ns.Text.Set(self.hpTextPct, hpPctStr, true)
        else
            ns.Text.SetFormatted(self.hpTextPct, true, "%.1f%%", hpPct)
        end
        return
    end

    -- Single FontString path
    ns.Text.ClearField(self, "hpTextPct")

    -- No percent available: just HP value (+ optional absorb)
    if not hasPct then
        ns.Text.Set(hpText, _MSUF_AppendAbsorb(h, absorbText, absorbStyle), true)
        return
    end

    -- Secret percent fallback (rare: UnitHealthPercent returned secret)
    if not hpPctStr then
        self._msufLastH = nil
        _MSUF_SetHpSecret(hpText, hpMode, h, hpPct, sep, absorbText, absorbStyle)
        return
    end

    -- Fast path: diff guard → format → absorb → Set
    if not absorbText and not _MSUF_IsSecret(h) and h == self._msufLastH and hpPctStr == self._msufLastPctS then return end
    if _MSUF_IsSecret(h) or absorbText then self._msufLastH = nil else self._msufLastH = h end
    self._msufLastPctS = hpPctStr

    local mainText = _MSUF_FormatHpByMode(hpMode, h, hpPctStr, sep)
    ns.Text.Set(hpText, _MSUF_AppendAbsorb(mainText, absorbText, absorbStyle), true)
 end
-- PERF: Cache function refs + constants at file scope (called 50-200x/sec in combat).
local _MSUF_UnitPowerPercent = (type(UnitPowerPercent) == "function") and UnitPowerPercent or nil
local _MSUF_UnitPowerTypeFn = (type(UnitPowerType) == "function") and UnitPowerType or nil
local _MSUF_PwrScaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) or nil
function ns.Text.GetUnitPowerPercent(unit)
    local fn = _MSUF_UnitPowerPercent
    if not fn then return nil end
    local pType
    local ptFn = _MSUF_UnitPowerTypeFn
    if ptFn then pType = ptFn(unit) end
    if _MSUF_PwrScaleTo100 then
        return fn(unit, pType, false, _MSUF_PwrScaleTo100)
    end
    return fn(unit, pType, false, true)
end
_G.MSUF_GetUnitPowerPercent = _G.MSUF_GetUnitPowerPercent or ns.Text.GetUnitPowerPercent
-- EQoL-style power text modes:
-- CURRENT, MAX, CURMAX, PERCENT, CURPERCENT, CURMAXPERCENT

-- (_MSUF_IsSecret is declared at file top, before ns.Text.Set)

function ns.Text.NormalizePowerTextMode(mode)
    if mode == nil then return "CURPERCENT" end
    -- Legacy MSUF values (pre-EQoL modes)
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end
_G.MSUF_NormalizePowerTextMode = _G.MSUF_NormalizePowerTextMode or ns.Text.NormalizePowerTextMode

-- PERF: Cache abbreviation function at file scope (called 100-400x/sec across all units).
local _MSUF_TextAbbrFn = _G.AbbreviateLargeNumbers or _G.ShortenNumber or _G.AbbreviateNumbers

local function _MSUF_TextifyValue(val)
    if val == nil then return nil end
    -- Fast path: plain numbers (99%+ of calls) bypass secret handling entirely.
    if type(val) == "number" then
        local abbr = _MSUF_TextAbbrFn
        if abbr then return abbr(val) end
        return tostring(val)
    end
    if type(val) == "string" then return val end
    -- Secret / unknown type: pass to C-side abbreviator (secret-safe, no Lua arithmetic).
    local abbr = _MSUF_TextAbbrFn
    if abbr then
        local txt = abbr(val)
        if txt ~= nil then return txt end
    end
    return nil
end

local function _MSUF_TextifyPercent(percentValue)
    if percentValue == nil then return nil end
    -- Secret value path: delegate to C-side formatting (no Lua arithmetic).
    if _MSUF_IsSecret(percentValue) then
        local CSU = _G.C_StringUtil
        if CSU and CSU.RoundToNearestString then
            local txt = CSU.RoundToNearestString(percentValue, 0.01)
            if txt ~= nil then return tostring(txt) .. "%" end
        end
        return nil
    end
    -- Normal number fast path: use cached strings for 0-100%.
    local pv = tonumber(percentValue)
    if not pv then return nil end
    local pctInt = math.floor(pv + 0.5)
    return _MSUF_PCT_CACHE[pctInt] or (tostring(pctInt) .. "%")
end

local function _MSUF_PowerModeAllowsSplit(mode)
    mode = ns.Text.NormalizePowerTextMode(mode)
    return (mode == "CURPERCENT" or mode == "CURMAXPERCENT")
end

-- Unified per-frame text config spec. Built once, cached on frame._msufTextSpec.
-- Replaces separate _msufHpTextConf (htc) and _msufPwrTextConf (ptc) caches.
-- Invalidated: set frame._msufTextSpec = nil on config change / profile switch.
function ns.Text.EnsureSpec(self)
    local spec = self._msufTextSpec
    if spec then return spec end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local key = self.msufConfigKey or self._msufConfigKey or self._msufUnitKey or self.unitKey
    local udb = (key and MSUF_DB and MSUF_DB[key]) or nil
    local useOverride = (udb and udb.hpPowerTextOverride == true)
    local eff = useOverride and (self.cachedConfig or udb) or nil
    -- HP
    local hpMode = (useOverride and eff and eff.hpTextMode) or g.hpTextMode or "FULL_PLUS_PERCENT"
    local hpSepRaw = (useOverride and eff and eff.hpTextSeparator) or g.hpTextSeparator
    -- Power
    local rawPMode = (useOverride and eff and eff.powerTextMode) or g.powerTextMode
    local pMode = ns.Text.NormalizePowerTextMode(rawPMode)
    local rawPSep
    if useOverride and eff then
        rawPSep = eff.powerTextSeparator
        if rawPSep == nil then rawPSep = eff.hpTextSeparator end
    else
        rawPSep = g.powerTextSeparator
    end
    local rawHpSep = (useOverride and eff and eff.hpTextSeparator) or g.hpTextSeparator
    -- Power split
    local pSplitEnabled = false
    if self.powerTextPct and _MSUF_PowerModeAllowsSplit(pMode) then
        local splitOn = (useOverride and eff and eff.powerTextSpacerEnabled == true)
            or ((not useOverride) and g.powerTextSpacerEnabled == true)
        if splitOn then
            local splitX = (useOverride and eff and tonumber(eff.powerTextSpacerX))
                or tonumber(g.powerTextSpacerX) or 0
            splitX = tonumber(splitX) or 0
            if splitX > 0 and key and type(_G.MSUF_GetPowerSpacerMaxForUnitKey) == "function" then
                local maxP = tonumber(_G.MSUF_GetPowerSpacerMaxForUnitKey(key)) or 0
                if splitX > maxP then splitX = maxP end
            end
            pSplitEnabled = (splitX > 0)
        end
    end
    spec = {
        hpMode = hpMode,
        hpSep = ns.Text._SepToken(hpSepRaw, nil),
        hpSpacerConf = (useOverride and eff) or nil,
        hpSpacerG = g,
        pMode = pMode,
        pSep = ns.Text._SepToken(rawPSep, rawHpSep),
        pColorByType = (g.colorPowerTextByType == true),
        pSplitEnabled = pSplitEnabled,
        useOverride = useOverride,
        hpAnchor = (udb and udb.hpTextAnchor) or g.hpTextAnchor or "RIGHT",
        powerAnchor = (udb and udb.powerTextAnchor) or g.powerTextAnchor or "RIGHT",
        nameAnchor = (udb and udb.nameTextAnchor) or "LEFT",
    }
    self._msufTextSpec = spec
    return spec
end

function ns.Text._ShouldSplitPower(self, pMode, hasPct)
    if not self or not hasPct or not self.powerTextPct then  return false end
    if not _MSUF_PowerModeAllowsSplit(pMode) then  return false end
    if not MSUF_DB then
        if type(EnsureDB) == "function" then EnsureDB() end
    end
    local key = self.msufConfigKey
    local udb = (key and MSUF_DB and MSUF_DB[key]) or nil
    local gen = (MSUF_DB and MSUF_DB.general) or nil
    -- Spacers inherit Shared unless per-unit override is enabled.
    local useOverride = (udb and udb.hpPowerTextOverride == true)
    local on = (useOverride and udb and udb.powerTextSpacerEnabled == true) or ((not useOverride) and gen and gen.powerTextSpacerEnabled == true)
    if not on then  return false end
    local x = (useOverride and udb and tonumber(udb.powerTextSpacerX)) or ((gen and tonumber(gen.powerTextSpacerX)) or 0)
    x = tonumber(x) or 0
    if x <= 0 then  return false end
    if key and type(_G.MSUF_GetPowerSpacerMaxForUnitKey) == "function" then
        local maxP = tonumber(_G.MSUF_GetPowerSpacerMaxForUnitKey(key)) or 0
        if x < 0 then x = 0 end
        if x > maxP then x = maxP end
    end
    return (x > 0)
end

local function _MSUF_FormatPowerByMode(mode, curText, maxText, pctText, joinPrimary, joinSecondary, splitAllowed)
    joinPrimary = joinPrimary or " "
    joinSecondary = joinSecondary or joinPrimary

    if mode == "CURRENT" then
        return curText or "", nil
    elseif mode == "MAX" then
        return maxText or "", nil
    elseif mode == "CURMAX" then
        if curText and maxText then
            return curText .. joinSecondary .. maxText, nil
        end
        return curText or maxText or "", nil
    elseif mode == "PERCENT" then
        return pctText or "", nil
    elseif mode == "CURPERCENT" then
        if splitAllowed and pctText then
            return curText or "", pctText
        end
        if curText and pctText then
            return curText .. joinPrimary .. pctText, nil
        end
        return curText or pctText or "", nil
    elseif mode == "CURMAXPERCENT" then
        local main
        if curText and maxText then
            main = curText .. joinSecondary .. maxText
        else
            main = curText or maxText
        end
        if splitAllowed and pctText then
            return main or "", pctText
        end
        if main and pctText then
            return main .. joinPrimary .. pctText, nil
        end
        return main or pctText or "", nil
    end

    -- Unknown mode: default to CURPERCENT behavior.
    if splitAllowed and pctText then
        return curText or "", pctText
    end
    if curText and pctText then
        return curText .. joinPrimary .. pctText, nil
    end
    return curText or pctText or "", nil
end

function ns.Text.RenderPowerText(self)
    if not self or not self.unit or not self.powerText then  return end

    local unit = self.unit
    local showPower = self.showPowerText
    if showPower == nil then showPower = true end
    if not showPower then
        ns.Text.Set(self.powerText, "", false)
        ns.Text.ClearField(self, "powerTextPct")
        return
    end

    local spec = ns.Text.EnsureSpec(self)
    local pMode = spec.pMode
    local powerSep = spec.pSep
    local colorByType = spec.pColorByType

    -- PERF: Reuse pType/cur/max/pct from DIRECT_APPLY handler if same frame.
    -- This keeps the text 1:1 in sync with the bar fast-path.
    -- pPct is pre-cached by DIRECT_APPLY → skips 1× UnitPowerPercent C-API call.
    -- NOTE: In WoW 12.0, cached values CAN be secret (UnitPower returns secret
    -- numbers where type() == "number" but issecretvalue() == true, and ~= nil
    -- is also true). Must still run IsSecret before any string compares.
    local pType, curValue, maxValue, powerPct
    local frameSerial = _G._MSUF_FrameSerial
    local cachedSerial = self._msufCachedPSerial
    if cachedSerial and frameSerial and cachedSerial == frameSerial then
        pType = self._msufCachedPType
        curValue = self._msufCachedPCur
        maxValue = self._msufCachedPMax
        powerPct = self._msufCachedPPct
    end
    -- Fallback: fetch from C-API if no valid cache.
    -- 2 args only — matches MidnightRogueBars secret-safe pattern.
    if pType == nil then
        pType = (F.UnitPowerType and F.UnitPowerType(unit)) or (UnitPowerType and UnitPowerType(unit))
    end
    -- Ele Shaman: class power shows Maelstrom → main bar + text show Mana
    if self._msufIsPlayer and _G.MSUF_EleMaelstromActive then pType = 0 end
    if pType ~= nil then
        if curValue == nil then
            curValue = (F.UnitPower and F.UnitPower(unit, pType)) or (UnitPower and UnitPower(unit, pType)) or nil
        end
        if maxValue == nil then
            maxValue = (F.UnitPowerMax and F.UnitPowerMax(unit, pType)) or (UnitPowerMax and UnitPowerMax(unit, pType)) or nil
        end
    else
        curValue = (F.UnitPower and F.UnitPower(unit)) or (UnitPower and UnitPower(unit)) or nil
        maxValue = (F.UnitPowerMax and F.UnitPowerMax(unit)) or (UnitPowerMax and UnitPowerMax(unit)) or nil
    end
    -- Percent: pass-through UnitPowerPercent (more accurate than recomputing).
    if powerPct == nil then
        local fn = _MSUF_UnitPowerPercent
        if fn then
            local curve = _MSUF_PwrScaleTo100 or true
            powerPct = fn(unit, pType, false, curve)
            if type(powerPct) ~= "number" then powerPct = nil end
        end
    end


    -- PERF P0: Raw-value diff guard. Skip ALL textification + string work when
    -- raw power values are unchanged (most frequent case: energy/mana hasn't
    -- ticked between events). Saves 3× AbbreviateLargeNumbers + 1× FormatPercent
    -- + downstream concat per skipped call (~790 B/call allocation eliminated).
    -- Secret-safe: bail before any comparison if values could be secret.
    if not _MSUF_issecret
       or (not _MSUF_issecret(curValue) and not _MSUF_issecret(maxValue)
           and (powerPct == nil or not _MSUF_issecret(powerPct)))
    then
        if curValue == self._msufRawPwrC
           and maxValue == self._msufRawPwrM
           and powerPct == self._msufRawPwrP
        then
            return
        end
        self._msufRawPwrC = curValue
        self._msufRawPwrM = maxValue
        self._msufRawPwrP = powerPct
    else
        -- Secret value: invalidate raw cache; fall through to text-level guard.
        self._msufRawPwrC = nil
        self._msufRawPwrM = nil
        self._msufRawPwrP = nil
    end

    local curText = _MSUF_TextifyValue(curValue)
    local maxText = _MSUF_TextifyValue(maxValue)
    local pctText = _MSUF_TextifyPercent(powerPct)

    -- PERF: Component-level diff guard. Skip string concat + SetText if all
    -- abbreviated components are unchanged. Saves 3-5 string allocations per call.
    -- Secret-safe: ShortenNumber on secret UnitPower returns secret strings.
    -- If ANY component is secret, skip caching entirely (fail-open to normal path).
    local _secretCur = _MSUF_IsSecret(curText)
    local _secretMax = _MSUF_IsSecret(maxText)
    local _secretPct = _MSUF_IsSecret(pctText)
    if not _secretCur and not _secretMax and not _secretPct then
        if curText == self._msufLastPwrC and maxText == self._msufLastPwrM and pctText == self._msufLastPwrP then
            return
        end
        self._msufLastPwrC = curText
        self._msufLastPwrM = maxText
        self._msufLastPwrP = pctText
    else
        -- Secret: invalidate cache so next non-secret call re-renders
        self._msufLastPwrC = nil
        self._msufLastPwrM = nil
        self._msufLastPwrP = nil
    end

    local hasPct = (pctText ~= nil)
    local splitAllowed = (self.powerTextPct ~= nil) and hasPct and spec.pSplitEnabled or false

    local mainText, sideText = _MSUF_FormatPowerByMode(pMode, curText, maxText, pctText, powerSep, powerSep, splitAllowed)

    ns.Text.Set(self.powerText, mainText or "", true)
    if sideText ~= nil and self.powerTextPct then
        ns.Text.Set(self.powerTextPct, sideText, true)
        self._msufPwrPctCleared = nil
    elseif not self._msufPwrPctCleared then
        -- PERF: Gate ClearField — skip if already cleared (saves ~1.6ms/trace).
        ns.Text.ClearField(self, "powerTextPct")
        self._msufPwrPctCleared = true
    end

    -- PERF: Skip SetTextColor when power type hasn't changed since last apply.
    -- UnitPowerType only changes on UNIT_DISPLAYPOWER (very rare).
    if colorByType then
        if self._msufPTColorType ~= pType or not self._msufPTColorByPower then
            ns.Text.ApplyPowerTextColorByType(self, unit, true)
        end
    end
end
-- Resolve helper color lookups used by ToT inline.
 -- These are global functions defined in MidnightSimpleUnitFrames.lua (loaded before this file).
 local MSUF_GetNPCReactionColor = _G.MSUF_GetNPCReactionColor or function(kind) return 1, 1, 1 end
 local MSUF_GetClassBarColor    = _G.MSUF_GetClassBarColor    or function(tok)  return 1, 1, 1 end

 -- PERF: Cache FastNPC function ref at file scope (called 4× per RenderToTInline).
 -- Resolved lazily; avoids 4 separate _G lookups + type() checks per target swap.
 local _RenderToTInline_FastNPC = nil
 local _RenderToTInline_FastNPCChecked = false

 local function _GetToTFastNPC()
     if _RenderToTInline_FastNPCChecked then return _RenderToTInline_FastNPC end
     local fn = _G.MSUF_UFCore_GetNPCReactionColorFast
     _RenderToTInline_FastNPC = (type(fn) == "function") and fn or nil
     _RenderToTInline_FastNPCChecked = true
     return _RenderToTInline_FastNPC
 end

 -- PERF: Unified NPC color resolver. Uses fast UFCore path if available, falls back to legacy.
 local function _ToTInlineNPCColor(kind)
     local fn = _GetToTFastNPC()
     if fn then return fn(kind) end
     return MSUF_GetNPCReactionColor(kind)
 end

 function ns.Text.RenderToTInline(targetFrame, totConf)
    if not targetFrame or not targetFrame.nameText then  return end
    local sep = targetFrame._msufToTInlineSep
    local txt = targetFrame._msufToTInlineText
    if not sep or not txt then  return end
    local enabled = (totConf and totConf.showToTInTargetName) and true or false
    if not enabled or not (F.UnitExists and F.UnitExists("target")) or not (F.UnitExists and F.UnitExists("targettarget")) then
        ns.Util.SetShown(sep, false)
        ns.Util.SetShown(txt, false)
         return
    end
    local sepToken = (totConf and totConf.totInlineSeparator) or "|"
    if type(sepToken) ~= "string" or sepToken == "" then sepToken = "|" end
    sep:SetText(" " .. sepToken .. " ")
    -- Match target name font (no secret ops).
    local font, size, flags = targetFrame.nameText:GetFont()
    if font and sep.SetFont then
        sep:SetFont(font, size, flags)
        txt:SetFont(font, size, flags)
    end
    -- Clamp ToT inline width (secret-safe, no string width math).
    local frameWidth = (targetFrame.GetWidth and targetFrame:GetWidth()) or 0
    local maxW = 120
    if frameWidth and frameWidth > 0 then
        maxW = math.floor(frameWidth * 0.32)
        if maxW < 80 then maxW = 80 end
        if maxW > 180 then maxW = 180 end
    end
    txt:SetWidth(maxW)
    local r, gCol, b = 1, 1, 1
    if F.UnitIsPlayer and F.UnitIsPlayer("targettarget") then
        local useClass = false
        local g = MSUF_DB and MSUF_DB.general
        if g and g.nameClassColor then useClass = true end
        if useClass then
            local _, classToken = F.UnitClass("targettarget")
            r, gCol, b = MSUF_GetClassBarColor(classToken)
        else
            r, gCol, b = 1, 1, 1
    end
    else
        if F.UnitIsDeadOrGhost and F.UnitIsDeadOrGhost("targettarget") then
            r, gCol, b = _ToTInlineNPCColor("dead")
        else
            local reaction = F.UnitReaction and F.UnitReaction("player", "targettarget")
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = _ToTInlineNPCColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = _ToTInlineNPCColor("neutral")
                else
                    r, gCol, b = _ToTInlineNPCColor("enemy")
                end
            else
                r, gCol, b = _ToTInlineNPCColor("enemy")
            end
    end
    end
    sep:SetTextColor(0.7, 0.7, 0.7)
    txt:SetTextColor(r, gCol, b)
    local totName = F.UnitName and F.UnitName("targettarget")
    txt:SetText(totName or "")
    ns.Util.SetShown(sep, true)
    ns.Util.SetShown(txt, true)
 end
function ns.Text.ApplyPowerTextColorByType(self, unit, enabled)
    -- Secret-safe & pass-through: avoid extra comparisons/caching; just apply resolved color.
    if not enabled then  return end
    if not (self and self.powerText and UnitPowerType) then  return end
    -- UnitPowerType existence is guarded above. Direct call (no FastCall overhead).
    local pType, pTok = UnitPowerType(unit)
    if pType == nil then  return end
    -- Ele Shaman: class power shows Maelstrom → text color matches Mana
    if self._msufIsPlayer and _G.MSUF_EleMaelstromActive then pType = 0; pTok = "MANA" end
    if type(MSUF_GetResolvedPowerColor) ~= "function" then  return end
    local pr, pg, pb = MSUF_GetResolvedPowerColor(pType, pTok)
    if not pr then  return end
    self.powerText:SetTextColor(pr, pg, pb, 1)
    self._msufPTColorByPower = true
    self._msufPTColorType = pType
    self._msufPTColorTok = pTok
 end
function ns.Text.ApplyName(frame, unit, overrideText)
    -- Secret-safe: do NOT compare name strings. Use API pass-through only.
    if not frame or not frame.nameText then  return end
    local show = (frame.showName ~= false)
    local txt = overrideText
    if txt == nil and show and unit and F.UnitName then
        txt = F.UnitName(unit)
    end
    if txt == nil then
        show = false
        txt = ""
    end
    ns.Text.Set(frame.nameText, txt, show)
 end
function ns.Text.ApplyLevel(frame, unit, conf, overrideText, forceShow)
    -- Secret-safe: do NOT compare strings for emptiness.
    if not frame or not frame.levelText then  return end
    local showLevel = true
    if conf and conf.showLevelIndicator == false then
        showLevel = false
    end
    if forceShow ~= nil then
        showLevel = (forceShow == true)
    end
    local txt = ""
    if overrideText ~= nil then
        txt = overrideText
    elseif showLevel and unit and F.UnitExists and F.UnitExists(unit) then
        txt = (MSUF_GetUnitLevelText and MSUF_GetUnitLevelText(unit)) or ""
    end
    ns.Text.Set(frame.levelText, txt, showLevel)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
 end
function ns.Text.ApplyBossTestName(frame, unit)
    if not frame then  return end
    local txt = "Test Boss"
    local idx
    if type(unit) == "string" then
        idx = unit:match("boss(%d+)")
    end
    if idx then
        txt = "Test Boss " .. idx
    end
    ns.Text.ApplyName(frame, unit, txt)
 end
function ns.Text.ApplyBossTestLevel(frame, conf)
    if not frame or not frame.levelText then  return end
    local show = (frame.showName ~= false)
    ns.Text.Set(frame.levelText, "??", show)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
 end
