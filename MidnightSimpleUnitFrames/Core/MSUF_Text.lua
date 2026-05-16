-- Core/MSUF_Text.lua  Core text rendering (HP, power, name, level, separators)
-- Extracted from MidnightSimpleUnitFrames.lua (Phase 2 file split)
-- Loads AFTER MidnightSimpleUnitFrames.lua in the TOC.
local addonName, ns = ...
local F = ns.Cache and ns.Cache.F or {}
local type, tonumber, select = type, tonumber, select
local string_format = string.format

-- PERF: Direct upvalues for power text hot path (avoids F.* table indirection).
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitPowerPercent = UnitPowerPercent
local UnitHealthMissing = UnitHealthMissing

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
_G.MSUF_TEXTLAYOUT_VALID_KEYS = _G.MSUF_TEXTLAYOUT_VALID_KEYS or { player=true, target=true, focus=true, targettarget=true, pet=true, boss=true }
function _G.MSUF_NormalizeTextLayoutUnitKey(unitKey, fallbackKey)
    local k = unitKey
    if not k or k == "" then k = fallbackKey or "player" end
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
local function _MSUF_ClearHpPctField(self)
    if not self then return end
    local field = self.hpTextPct
    local token = field or false
    if self._msufHpPctCleared == token then return end
    ns.Text.ClearField(self, "hpTextPct")
    self._msufHpPctCleared = token
end
local function _MSUF_ClearTextField(self, field)
    if self and field then
        ns.Text.ClearField(self, field)
    end
end
local function _MSUF_ClearHpSlots(self)
    _MSUF_ClearTextField(self, "hpTextLeft")
    _MSUF_ClearTextField(self, "hpTextCenter")
    _MSUF_ClearTextField(self, "hpText")
    _MSUF_ClearHpPctField(self)
    if self then
        self._msufLastRenderPct = nil
        self._msufLastH = nil
        self._msufLastPctS = nil
    end
end
local function _MSUF_ClearPowerSlots(self)
    _MSUF_ClearTextField(self, "powerTextLeft")
    _MSUF_ClearTextField(self, "powerTextCenter")
    _MSUF_ClearTextField(self, "powerText")
    ns.Text.ClearField(self, "powerTextPct")
    self._msufPwrPctCleared = true
    self._msufRawPwrC, self._msufRawPwrM, self._msufRawPwrP = nil, nil, nil
    self._msufRawPwrMode, self._msufRawPwrSep = nil, nil
    self._msufLastPwrC, self._msufLastPwrM, self._msufLastPwrP = nil, nil, nil
    self._msufLastPwrMode, self._msufLastPwrSep = nil, nil
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
-- HP mode format dispatcher. Mirrors _MSUF_FormatPowerByMode pattern.
-- Returns mainText. hpPctStr may be nil (secret percent → caller handles).
local _MSUF_HP_REVERSE_MAP = {
    CURPERCENT    = "PERCENTCUR",
    PERCENTCUR    = "CURPERCENT",
    CURMAX        = "MAXCUR",
    MAXCUR        = "CURMAX",
    CURMAXPERCENT = "PERCENTMAXCUR",
    PERCENTMAXCUR = "CURMAXPERCENT",
    MAXPERCENT    = "PERCENTMAX",
    PERCENTMAX    = "MAXPERCENT",
    PERCENTCURMAX = "CURMAXPERCENT",
}

function ns.Text.NormalizeHpTextMode(mode)
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end
_G.MSUF_NormalizeHpTextMode = _G.MSUF_NormalizeHpTextMode or ns.Text.NormalizeHpTextMode

local function _MSUF_HpModeUsesPercent(mode)
    mode = ns.Text.NormalizeHpTextMode(mode)
    return mode == "PERCENT"
        or mode == "CURPERCENT"
        or mode == "PERCENTCUR"
        or mode == "CURMAXPERCENT"
        or mode == "PERCENTMAXCUR"
        or mode == "MAXPERCENT"
        or mode == "PERCENTMAX"
        or mode == "PERCENTCURMAX"
end

local function _MSUF_HpModeUsesCurrent(mode)
    mode = ns.Text.NormalizeHpTextMode(mode)
    return not (mode == "NONE"
        or mode == "PERCENT"
        or mode == "MAX"
        or mode == "DEFICIT"
        or mode == "MAXPERCENT"
        or mode == "PERCENTMAX")
end

local function _MSUF_HpModeUsesMax(mode)
    mode = ns.Text.NormalizeHpTextMode(mode)
    return mode == "MAX"
        or mode == "CURMAX"
        or mode == "MAXCUR"
        or mode == "CURMAXPERCENT"
        or mode == "PERCENTMAXCUR"
        or mode == "MAXPERCENT"
        or mode == "PERCENTMAX"
        or mode == "PERCENTCURMAX"
end

local function _MSUF_HpMissingText(self)
    if not (UnitHealthMissing and self and self.unit) then return nil end
    local missing = UnitHealthMissing(self.unit)
    if missing == nil then return nil end
    local isSecret = _MSUF_IsSecret(missing)
    if not isSecret then
        local n = tonumber(missing) or 0
        if n <= 0 then return "" end
    end
    local abbr = _G.ShortenNumber or _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers
    local txt = abbr and abbr(missing) or (not isSecret and tostring(missing) or nil)
    if txt == nil or txt == "" then return "" end
    return "-" .. txt
end

local function _MSUF_FormatHpByMode(mode, h, maxText, deficitText, hpPctStr, sep)
    if mode == "NONE" then return "" end
    if mode == "PERCENT" then return hpPctStr or "" end
    if mode == "CURRENT" then return h end
    if mode == "MAX" then return maxText or "" end
    if mode == "DEFICIT" then return deficitText or "" end
    if mode == "CURMAX" then return h .. sep .. (maxText or "") end
    if mode == "MAXCUR" then return (maxText or "") .. sep .. h end
    if not hpPctStr then return h end
    if mode == "CURPERCENT" then return h .. sep .. hpPctStr end
    if mode == "PERCENTCUR" then return hpPctStr .. sep .. h end
    if mode == "CURMAXPERCENT" then return h .. sep .. (maxText or "") .. sep .. hpPctStr end
    if mode == "PERCENTMAXCUR" then return hpPctStr .. sep .. (maxText or "") .. sep .. h end
    if mode == "MAXPERCENT" then return (maxText or "") .. sep .. hpPctStr end
    if mode == "PERCENTMAX" then return hpPctStr .. sep .. (maxText or "") end
    if mode == "PERCENTCURMAX" then return hpPctStr .. sep .. h .. sep .. (maxText or "") end
    return h .. sep .. hpPctStr
end
-- Absorb text suffix. Secret-safe: absorbText is from C-side TruncateWhenZero.
local function _MSUF_AppendAbsorb(text, absorbText, absorbStyle)
    if not absorbText then return text end
    if absorbStyle == "PAREN" then return text .. " (" .. absorbText .. ")" end
    return text .. " " .. absorbText
end
-- Secret-percent fallback (rare: <0.1% of calls). Uses C-side SetFormattedText.
local function _MSUF_SetHpSecret(fs, mode, h, hpPct, sep, absorbText, absorbStyle, maxText)
    mode = ns.Text.NormalizeHpTextMode(mode)
    maxText = maxText or ""
    if mode == "CURRENT" then
        ns.Text.Set(fs, _MSUF_AppendAbsorb(h, absorbText, absorbStyle), true)
    elseif mode == "PERCENT" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sfx, hpPct, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%", hpPct)
        end
    elseif mode == "PERCENTCUR" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sfx, hpPct, h, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s", hpPct, h)
        end
    elseif mode == "CURMAXPERCENT" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%s" .. sep .. "%.1f%%" .. sfx, h, maxText, hpPct, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%s" .. sep .. "%.1f%%", h, maxText, hpPct)
        end
    elseif mode == "PERCENTMAXCUR" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sep .. "%s" .. sfx, hpPct, maxText, h, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sep .. "%s", hpPct, maxText, h)
        end
    elseif mode == "MAXPERCENT" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%.1f%%" .. sfx, maxText, hpPct, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%s" .. sep .. "%.1f%%", maxText, hpPct)
        end
    elseif mode == "PERCENTMAX" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sfx, hpPct, maxText, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s", hpPct, maxText)
        end
    elseif mode == "PERCENTCURMAX" then
        if absorbText then
            local sfx = (absorbStyle == "PAREN") and " (%s)" or " %s"
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sep .. "%s" .. sfx, hpPct, h, maxText, absorbText)
        else
            ns.Text.SetFormatted(fs, true, "%.1f%%" .. sep .. "%s" .. sep .. "%s", hpPct, h, maxText)
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
function ns.Text.RenderHpMode(self, show, hpStr, hpPct, hasPct, conf, g, absorbText, absorbStyle, hpMaxStr, hpDeficitStr)
    if not self or not self.hpText then  return end
    if not show then
        _MSUF_ClearHpSlots(self)
        self._msufLastRenderPct = nil
        return
    end

    local spec = self._msufTextSpec or ns.Text.EnsureSpec(self)
    local hpLeftMode = spec.hpLeftMode or "NONE"
    local hpCenterMode = spec.hpCenterMode or "NONE"
    local hpRightMode = spec.hpRightMode or spec.hpMode or "CURPERCENT"
    if hpLeftMode == "NONE" and hpCenterMode == "NONE" and hpRightMode == "NONE" then
        _MSUF_ClearHpSlots(self)
        return
    end

    local sep = spec.hpSep
    local h = hpStr or ""
    local maxText = hpMaxStr or ""
    local hpPctStr = (hasPct and spec.hpNeedsPct) and _MSUF_PctToStr1D(hpPct) or nil
    local absorbField
    if absorbText then
        if hpRightMode ~= "NONE" then
            absorbField = "right"
        elseif hpCenterMode ~= "NONE" then
            absorbField = "center"
        elseif hpLeftMode ~= "NONE" then
            absorbField = "left"
        end
    end

    _MSUF_ClearHpPctField(self)
    self._msufLastH = nil
    self._msufLastPctS = hpPctStr

    local function RenderSlot(fs, mode, fieldKey)
        if not fs or mode == "NONE" then
            if fs then ns.Text.Set(fs, "", false) end
            return
        end
        local slotAbsorb = (absorbField == fieldKey) and absorbText or nil
        if not hasPct and _MSUF_HpModeUsesPercent(mode) then
            ns.Text.Set(fs, _MSUF_AppendAbsorb(h, slotAbsorb, absorbStyle), true)
            return
        end
        if _MSUF_HpModeUsesPercent(mode) and spec.hpNeedsPct and not hpPctStr then
            _MSUF_SetHpSecret(fs, mode, h, hpPct, sep, slotAbsorb, absorbStyle, maxText)
            return
        end
        local text
        local deficitText = (mode == "DEFICIT") and (_MSUF_HpMissingText(self) or hpDeficitStr) or nil
        text = _MSUF_FormatHpByMode(mode, h, maxText, deficitText, hpPctStr, sep)
        ns.Text.Set(fs, _MSUF_AppendAbsorb(text or "", slotAbsorb, absorbStyle), true)
    end

    RenderSlot(self.hpTextLeft, hpLeftMode, "left")
    RenderSlot(self.hpTextCenter, hpCenterMode, "center")
    RenderSlot(self.hpText, hpRightMode, "right")
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
    -- SECRET-SAFE: Check for secret values BEFORE type() — type() on secrets causes taint.
    -- Secret numbers pass through to C-side abbreviator (handles internally).
    if _MSUF_issecret and _MSUF_issecret(val) then
        local abbr = _MSUF_TextAbbrFn
        if abbr then
            local txt = abbr(val)
            if txt ~= nil then return txt end
        end
        return nil
    end
    -- Non-secret: safe to use type() and arithmetic.
    if type(val) == "number" then
        local abbr = _MSUF_TextAbbrFn
        if abbr then return abbr(val) end
        return tostring(val)
    end
    if type(val) == "string" then return val end
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

local function _MSUF_PowerModeNeeds(pMode)
    -- pMode is already normalized by EnsureSpec.
    if pMode == "NONE" then
        return false, false, false
    elseif pMode == "CURRENT" then
        return true, false, false
    elseif pMode == "MAX" then
        return false, true, false
    elseif pMode == "CURMAX" then
        return true, true, false
    elseif pMode == "PERCENT" then
        return false, false, true
    elseif pMode == "CURMAXPERCENT" then
        return true, true, true
    end
    return true, false, true
end

local function _MSUF_TextHasSlots(eff, g, leftKey, centerKey, rightKey)
    return (eff and (eff[leftKey] ~= nil or eff[centerKey] ~= nil or eff[rightKey] ~= nil))
        or (g and (g[leftKey] ~= nil or g[centerKey] ~= nil or g[rightKey] ~= nil))
end

local function _MSUF_TextReadSlotMode(eff, g, key, fallback, normalizer)
    local value = eff and eff[key]
    if value == nil and g then value = g[key] end
    if value == nil or value == "" then value = fallback or "NONE" end
    if normalizer then value = normalizer(value) end
    return value or fallback or "NONE"
end

local function _MSUF_TextReadLegacyMode(eff, g, key, fallback, normalizer)
    local value = (eff and eff[key]) or (g and g[key]) or fallback or "NONE"
    if normalizer then value = normalizer(value) end
    return value or fallback or "NONE"
end

local function _MSUF_TextReverseHp(mode)
    return _MSUF_HP_REVERSE_MAP[mode] or mode
end

local function _MSUF_PowerNeedsForSlots(leftMode, centerMode, rightMode)
    local c1, m1, p1 = _MSUF_PowerModeNeeds(leftMode)
    local c2, m2, p2 = _MSUF_PowerModeNeeds(centerMode)
    local c3, m3, p3 = _MSUF_PowerModeNeeds(rightMode)
    return c1 or c2 or c3, m1 or m2 or m3, p1 or p2 or p3
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
    local eff = (self.cachedConfig or udb) or nil
    -- HP
    local legacyHpMode = _MSUF_TextReadLegacyMode(eff, g, "hpTextMode", "CURPERCENT", ns.Text.NormalizeHpTextMode)
    local hpReverse = (eff and eff.hpTextReverse)
    if hpReverse == nil then hpReverse = g.hpTextReverse end
    local hpLeftMode, hpCenterMode, hpRightMode
    if _MSUF_TextHasSlots(eff, g, "textLeft", "textCenter", "textRight") then
        hpLeftMode = _MSUF_TextReadSlotMode(eff, g, "textLeft", "NONE", ns.Text.NormalizeHpTextMode)
        hpCenterMode = _MSUF_TextReadSlotMode(eff, g, "textCenter", "NONE", ns.Text.NormalizeHpTextMode)
        hpRightMode = _MSUF_TextReadSlotMode(eff, g, "textRight", "CURPERCENT", ns.Text.NormalizeHpTextMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", legacyHpMode
    end
    if hpReverse then
        hpLeftMode = _MSUF_TextReverseHp(hpLeftMode)
        hpCenterMode = _MSUF_TextReverseHp(hpCenterMode)
        hpRightMode = _MSUF_TextReverseHp(hpRightMode)
    end
    local hpSepRaw = (eff and eff.hpTextSeparator)
    if hpSepRaw == nil then hpSepRaw = g.hpTextSeparator end
    -- Power
    local legacyPMode = _MSUF_TextReadLegacyMode(eff, g, "powerTextMode", "CURPERCENT", ns.Text.NormalizePowerTextMode)
    local pLeftMode, pCenterMode, pRightMode
    if _MSUF_TextHasSlots(eff, g, "powerTextLeft", "powerTextCenter", "powerTextRight") then
        pLeftMode = _MSUF_TextReadSlotMode(eff, g, "powerTextLeft", "NONE", ns.Text.NormalizePowerTextMode)
        pCenterMode = _MSUF_TextReadSlotMode(eff, g, "powerTextCenter", "NONE", ns.Text.NormalizePowerTextMode)
        pRightMode = _MSUF_TextReadSlotMode(eff, g, "powerTextRight", "CURPERCENT", ns.Text.NormalizePowerTextMode)
    else
        pLeftMode, pCenterMode, pRightMode = "NONE", "NONE", legacyPMode
    end
    local rawPSep
    if eff then
        rawPSep = eff.powerTextSeparator
        if rawPSep == nil then rawPSep = eff.hpTextSeparator end
    end
    if rawPSep == nil then rawPSep = g.powerTextSeparator end
    local rawHpSep = (eff and eff.hpTextSeparator)
    if rawHpSep == nil then rawHpSep = g.hpTextSeparator end
    -- Aggregate needs across the three independent Power text slots.
    local pNeedsCur, pNeedsMax, pNeedsPct = _MSUF_PowerNeedsForSlots(pLeftMode, pCenterMode, pRightMode)
    -- PERF: HP split — precompute once per spec build to avoid calling
    -- _ShouldSplitHP on every RenderHpMode (10-50×/s per unit). Config changes
    -- invalidate the spec via _msufTextSpec = nil, so the cached value stays correct.
    local hpNeedsPct = _MSUF_HpModeUsesPercent(hpLeftMode) or _MSUF_HpModeUsesPercent(hpCenterMode) or _MSUF_HpModeUsesPercent(hpRightMode)
    local hpNeedsCurrent = _MSUF_HpModeUsesCurrent(hpLeftMode) or _MSUF_HpModeUsesCurrent(hpCenterMode) or _MSUF_HpModeUsesCurrent(hpRightMode)
    local hpNeedsMax = _MSUF_HpModeUsesMax(hpLeftMode) or _MSUF_HpModeUsesMax(hpCenterMode) or _MSUF_HpModeUsesMax(hpRightMode)
    local hpNeedsDeficit = (hpLeftMode == "DEFICIT" or hpCenterMode == "DEFICIT" or hpRightMode == "DEFICIT")
    -- Per-unit font override: resolve colorPowerTextByType per frame
    local _pColorByType = (g.colorPowerTextByType == true)
    if udb and udb.fontOverride and udb.colorPowerTextByType ~= nil then
        _pColorByType = (udb.colorPowerTextByType == true)
    end
    spec = {
        hpMode = hpRightMode,
        hpLeftMode = hpLeftMode,
        hpCenterMode = hpCenterMode,
        hpRightMode = hpRightMode,
        hpSep = ns.Text._SepToken(hpSepRaw, nil),
        hpNeedsPct = hpNeedsPct,
        hpNeedsCurrent = hpNeedsCurrent,
        hpNeedsMax = hpNeedsMax,
        hpNeedsDeficit = hpNeedsDeficit,
        pMode = pRightMode,
        pLeftMode = pLeftMode,
        pCenterMode = pCenterMode,
        pRightMode = pRightMode,
        pModesStamp = tostring(pLeftMode or "NONE") .. "|" .. tostring(pCenterMode or "NONE") .. "|" .. tostring(pRightMode or "NONE"),
        pSep = ns.Text._SepToken(rawPSep, rawHpSep),
        pNeedsCur = pNeedsCur,
        pNeedsMax = pNeedsMax,
        pNeedsPct = pNeedsPct,
        pColorByType = _pColorByType,
        useOverride = false,
        nameAnchor = (udb and udb.nameTextAnchor) or "LEFT",
    }
    self._msufTextSpec = spec
    return spec
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
        _MSUF_ClearPowerSlots(self)
        return
    end

    -- PERF: Inlined EnsureSpec fast path
    local spec = self._msufTextSpec or ns.Text.EnsureSpec(self)
    local pLeftMode = spec.pLeftMode or "NONE"
    local pCenterMode = spec.pCenterMode or "NONE"
    local pRightMode = spec.pRightMode or spec.pMode or "CURPERCENT"
    if pLeftMode == "NONE" and pCenterMode == "NONE" and pRightMode == "NONE" then
        _MSUF_ClearPowerSlots(self)
        return
    end
    local pModesStamp = spec.pModesStamp or (tostring(pLeftMode) .. "|" .. tostring(pCenterMode) .. "|" .. tostring(pRightMode))
    local powerSep = spec.pSep
    local colorByType = spec.pColorByType
    local needCur = spec.pNeedsCur
    local needMax = spec.pNeedsMax
    local needPct = spec.pNeedsPct
    if needCur == nil or needMax == nil or needPct == nil then
        needCur, needMax, needPct = _MSUF_PowerNeedsForSlots(pLeftMode, pCenterMode, pRightMode)
    end

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
        pType = UnitPowerType and UnitPowerType(unit)
    end
    -- Ele Shaman: class power shows Maelstrom → main bar + text show Mana
    if self._msufIsPlayer and _G.MSUF_EleMaelstromActive then pType = 0 end
    -- Aug Evoker: class power shows Ebon Might → main bar + text show Essence
    if self._msufIsPlayer and _G.MSUF_AugEvokerActive then pType = 19 end
    -- Shadow Priest: class power shows Insanity → main bar + text show Mana
    if self._msufIsPlayer and _G.MSUF_ShadowManaActive then pType = 0 end
    if pType ~= nil then
        if needCur and curValue == nil then
            curValue = UnitPower and UnitPower(unit, pType)
        end
        if needMax and maxValue == nil then
            maxValue = UnitPowerMax and UnitPowerMax(unit, pType)
        end
    else
        if needCur then curValue = UnitPower and UnitPower(unit) end
        if needMax then maxValue = UnitPowerMax and UnitPowerMax(unit) end
    end
    if not needCur then curValue = nil end
    if not needMax then maxValue = nil end
    -- Percent: pass-through UnitPowerPercent (more accurate than recomputing).
    -- Secret-safe: == nil is a reference check (never taints). type() on API returns is forbidden.
    if needPct and powerPct == nil then
        local fn = _MSUF_UnitPowerPercent
        if fn then
            local curve = _MSUF_PwrScaleTo100 or true
            powerPct = fn(unit, pType, false, curve)
            if powerPct == nil then powerPct = nil end  -- no-op, kept for clarity
        end
    end
    if not needPct then powerPct = nil end

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
           and pModesStamp == self._msufRawPwrMode
           and powerSep == self._msufRawPwrSep
        then
            return
        end
        self._msufRawPwrC = curValue
        self._msufRawPwrM = maxValue
        self._msufRawPwrP = powerPct
        self._msufRawPwrMode = pModesStamp
        self._msufRawPwrSep = powerSep
    else
        -- Secret value: invalidate raw cache; fall through to text-level guard.
        self._msufRawPwrC = nil
        self._msufRawPwrM = nil
        self._msufRawPwrP = nil
        self._msufRawPwrMode = nil
        self._msufRawPwrSep = nil
    end

    local curText = needCur and _MSUF_TextifyValue(curValue) or nil
    local maxText = needMax and _MSUF_TextifyValue(maxValue) or nil
    local pctText = needPct and _MSUF_TextifyPercent(powerPct) or nil

    -- PERF: Component-level diff guard. Skip string concat + SetText if all
    -- abbreviated components are unchanged. Saves 3-5 string allocations per call.
    -- Secret-safe: ShortenNumber on secret UnitPower returns secret strings.
    -- If ANY component is secret, skip caching entirely (fail-open to normal path).
    local _secretCur = _MSUF_IsSecret(curText)
    local _secretMax = _MSUF_IsSecret(maxText)
    local _secretPct = _MSUF_IsSecret(pctText)
    if not _secretCur and not _secretMax and not _secretPct then
        if curText == self._msufLastPwrC
           and maxText == self._msufLastPwrM
           and pctText == self._msufLastPwrP
           and pModesStamp == self._msufLastPwrMode
           and powerSep == self._msufLastPwrSep
        then
            return
        end
        self._msufLastPwrC = curText
        self._msufLastPwrM = maxText
        self._msufLastPwrP = pctText
        self._msufLastPwrMode = pModesStamp
        self._msufLastPwrSep = powerSep
    else
        -- Secret: invalidate cache so next non-secret call re-renders
        self._msufLastPwrC = nil
        self._msufLastPwrM = nil
        self._msufLastPwrP = nil
        self._msufLastPwrMode = nil
        self._msufLastPwrSep = nil
    end

    local function RenderPowerSlot(fs, mode)
        if not fs or mode == "NONE" then
            if fs then ns.Text.Set(fs, "", false) end
            return
        end
        local text = _MSUF_FormatPowerByMode(mode, curText, maxText, pctText, powerSep, powerSep, false)
        ns.Text.Set(fs, text or "", true)
    end

    RenderPowerSlot(self.powerTextLeft, pLeftMode)
    RenderPowerSlot(self.powerTextCenter, pCenterMode)
    RenderPowerSlot(self.powerText, pRightMode)
    if not self._msufPwrPctCleared then
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

 local TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"

 local function _ResolveToTInlineSeparator(conf)
    local token = conf and conf.totInlineSeparator
    if token == TOT_INLINE_CUSTOM_SEPARATOR then
        token = conf and conf.totInlineCustomSeparator
        if type(token) ~= "string" or token == "" then token = " " end
    elseif type(token) ~= "string" or token == "" then
        token = "|"
    end
    return token
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
    local sepToken = _ResolveToTInlineSeparator(totConf)
    sep:SetText(" " .. sepToken .. " ")
    -- Match target name font (no secret ops).
    local font, size, flags = targetFrame.nameText:GetFont()
    if font and sep.SetFont then
        sep:SetFont(font, size, flags)
        txt:SetFont(font, size, flags)
        local sr, sg, sb, sa = targetFrame.nameText:GetShadowColor()
        local sox, soy = targetFrame.nameText:GetShadowOffset()
        sep:SetShadowColor(sr or 0, sg or 0, sb or 0, sa or 0)
        sep:SetShadowOffset(sox or 0, soy or 0)
        txt:SetShadowColor(sr or 0, sg or 0, sb or 0, sa or 0)
        txt:SetShadowOffset(sox or 0, soy or 0)
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
        -- Per-unit font override (e.g. Target tab "Override shared settings")
        local tkey = targetFrame and targetFrame.msufConfigKey
        if tkey then
            local uconf = MSUF_DB and MSUF_DB[tkey]
            if uconf and uconf.fontOverride then
                local ov = uconf.nameClassColor
                if ov ~= nil then useClass = ov end
            end
        end
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
    if not enabled then  return end
    if not (self and self.powerText and UnitPowerType) then  return end
    local pType, pTok = UnitPowerType(unit)
    if pType == nil then  return end
    if self._msufIsPlayer and _G.MSUF_EleMaelstromActive then pType = 0; pTok = "MANA" end
    if self._msufIsPlayer and _G.MSUF_AugEvokerActive then pType = 19; pTok = "ESSENCE" end
    if self._msufIsPlayer and _G.MSUF_ShadowManaActive then pType = 0; pTok = "MANA" end
    local fn = _G.MSUF_GetResolvedPowerColor
    if not fn then  return end
    local pr, pg, pb = fn(pType, pTok)
    if not pr then  return end
    if self.powerTextLeft and self.powerTextLeft.SetTextColor then self.powerTextLeft:SetTextColor(pr, pg, pb, 1) end
    if self.powerTextCenter and self.powerTextCenter.SetTextColor then self.powerTextCenter:SetTextColor(pr, pg, pb, 1) end
    self.powerText:SetTextColor(pr, pg, pb, 1)
    if self.powerTextPct and self.powerTextPct.SetTextColor then self.powerTextPct:SetTextColor(pr, pg, pb, 1) end
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
    local idx
    if type(unit) == "string" then
        idx = unit:match("boss(%d+)")
    end
    local _bossPreviewNames = {
        "Archimonde the Defiler",
        "Yogg-Saron, Hope's End",
        "Kael'thas Sunstrider",
        "Illidan Stormrage",
        "Kel'Thuzad",
    }
    local ni = tonumber(idx) or 1
    if ni < 1 then ni = 1 end
    local txt = _bossPreviewNames[((ni - 1) % #_bossPreviewNames) + 1]
    ns.Text.ApplyName(frame, unit, txt)
 end
function ns.Text.ApplyBossTestLevel(frame, conf)
    if not frame or not frame.levelText then  return end
    local show = true
    if conf and conf.showLevelIndicator == false then
        show = false
    end
    ns.Text.Set(frame.levelText, show and "??" or "", show)
    if MSUF_ClampNameWidth then
        MSUF_ClampNameWidth(frame, conf)
    end
 end
