--- GroupFrames/MSUF_GroupFrames_DB_Text.lua
--- Group-frame text: font, colour and name truncation resolvers, and the
--- secret-safe health and power text formatters.
--- Split by cohesion from MSUF_GroupFrames_DB.lua (2026-10-01). Loads right
--- after it (UFCore_Group.xml and the Classic GroupFrames.xml manifests) and
--- shares the one MSUF.GF table; see that file for the module's API surface.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

MSUF.GF = MSUF.GF or {}
local GF = MSUF.GF
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type

local ComposeFontFlags = _G.MSUF_ComposeFontFlags

local function ClampTextAlpha(value)
    value = tonumber(value) or 1
    if value < 0.7 then return 0.7 end
    if value > 1 then return 1 end
    return value
end

local function ClampBaselineOffset(value)
    value = tonumber(value) or 0
    if value < -4 then return -4 end
    if value > 4 then return 4 end
    return value
end

local ShadowMetrics = _G.MSUF_ResolveFontShadowMetrics

---
--- C-API references for secret-safe text formatting (WoW 12.0)
--- AbbreviateNumbers / BreakUpLargeNumbers accept secret values and
--- return secret strings that pass through to C-side SetText.
---
local _GF_AbbrShort  = _G.AbbreviateNumbers         --- "1.2k" (secret-safe)
local _GF_AbbrLong   = _G.BreakUpLargeNumbers       --- "1,234" (secret-safe)
local _GF_AbbrFallback = _G.AbbreviateLargeNumbers or _G.ShortenNumber
local _GF_UnitHealthPercent = _G.UnitHealthPercent   --- returns non-secret %
local _GF_UnitPowerPercent  = _G.UnitPowerPercent    --- returns non-secret %
local _GF_UnitPowerType     = _G.UnitPowerType
local _GF_UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local _GF_UnitHealthMissing = _G.UnitHealthMissing   --- secret-safe deficit
local _GF_CSU_Round = _G.C_StringUtil and _G.C_StringUtil.RoundToNearestString
local _GF_CSU_TruncateZero = _G.C_StringUtil and _G.C_StringUtil.TruncateWhenZero
local _GF_CSU_WrapString = _G.C_StringUtil and _G.C_StringUtil.WrapString
local _GF_ScaleTo100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local _GF_issecretvalue = _G.issecretvalue
--- Global abbreviation style, pushed on the cold path by
--- Runtime/MSUF_NumberFormat.lua. nil keeps the client's locale-dependent
--- output; a table switches the C abbreviator to MSUF's locale-independent
--- breakpoints. Only the short form takes it - BreakUpLargeNumbers does not.
local _GF_NUM_OPTS = nil
do
    local NumberFormat = MSUF.NumberFormat
    if NumberFormat and NumberFormat.Register then
        NumberFormat.Register(function(options) _GF_NUM_OPTS = options end)
    end
end
local _GF_ABSORB_ICON_MARKUP = "|TInterface\\Icons\\INV_Shield_06:0|t"
local _GF_ABSORB_MODE_BASE = {
    CURRENTABSORB = "CURRENT",
    FULLVALUEABSORB = "FULLVALUE",
    MAXABSORB = "MAX",
    DEFICITABSORB = "DEFICIT",
    CURMAXABSORB = "CURMAX",
    PERCENTABSORB = "PERCENT",
    CURPERCENTABSORB = "CURPERCENT",
    CURMAXPERCENTABSORB = "CURMAXPERCENT",
    MAXPERCENTABSORB = "MAXPERCENT",
    PERCENTCURABSORB = "PERCENTCUR",
    PERCENTMAXABSORB = "PERCENTMAX",
    PERCENTCURMAXABSORB = "PERCENTCURMAX",
    MAXCURABSORB = "MAXCUR",
    PERCENTMAXCURABSORB = "PERCENTMAXCUR",
}

---
--- Health text modes (matches EQoL healthTextModeOptions)
---
GF.HEALTH_TEXT_MODES = {
    { key = "NONE",           label = "None"                           },
    { key = "ABSORB",         label = "Absorb"                         },
    { key = "CURRENTABSORB",  label = "Current + Absorb"               },
    { key = "FULLVALUEABSORB", label = "Full Value + Absorb"           },
    { key = "MAXABSORB",      label = "Max + Absorb"                   },
    { key = "DEFICITABSORB",  label = "Deficit + Absorb"               },
    { key = "CURMAXABSORB",   label = "Current / Max + Absorb"         },
    { key = "PERCENTABSORB",  label = "Percent + Absorb"               },
    { key = "CURPERCENTABSORB", label = "Current / Percent + Absorb"   },
    { key = "CURMAXPERCENTABSORB", label = "Current / Max / Percent + Absorb" },
    { key = "MAXPERCENTABSORB", label = "Max / Percent + Absorb"       },
    { key = "PERCENTCURABSORB", label = "Percent / Current + Absorb"   },
    { key = "PERCENTMAXABSORB", label = "Percent / Max + Absorb"       },
    { key = "PERCENTCURMAXABSORB", label = "Percent / Current / Max + Absorb" },
    { key = "PERCENT",        label = "Percent"                        },
    { key = "CURRENT",        label = "Current"                        },
    { key = "FULLVALUE",      label = "Full Value"                     },
    { key = "MAX",            label = "Max"                            },
    { key = "DEFICIT",        label = "Deficit"                        },
    { key = "CURMAX",         label = "Current / Max"                  },
    { key = "CURPERCENT",     label = "Current / Percent"              },
    { key = "CURMAXPERCENT",  label = "Current / Max / Percent"        },
    { key = "MAXPERCENT",     label = "Max / Percent"                  },
    { key = "PERCENTCUR",     label = "Percent / Current"              },
    { key = "PERCENTMAX",     label = "Percent / Max"                  },
    { key = "PERCENTCURMAX",  label = "Percent / Current / Max"        },
}

GF.DELIMITER_OPTIONS = {
    { key = " ",    label = "Space"        },
    { key = "  ",   label = "Double Space"  },
    { key = " / ",  label = "/"            },
    { key = " - ",  label = "-"            },
    { key = " : ",  label = ":"            },
    { key = " | ",  label = "|"            },
}


--- Resolve font path (global MSUF font family)
--- Check if GF scope has font override active
function GF.HasFontOverride(kind)
    local conf = GF.GetConf(kind)
    return conf.fontOverride == true
end

function GF.ResolveFontPath(kind)
    return _G.MSUF_GetFontPath()
end

--- Resolve font outline flags
function GF.ResolveFontFlags(kind)
    local conf = GF.GetConf(kind)
    local db = _G.MSUF_DB
    local gen = db and db.general
    local monochrome = gen and gen.fontMonochrome == true
    local slug = gen and gen.fontSlug == true
    --- When override active: use GF-local fontOutline
    if conf.fontOverride then
        local v = conf.fontOutline
        if conf.fontMonochrome ~= nil then monochrome = conf.fontMonochrome == true end
        if conf.fontSlug ~= nil then slug = conf.fontSlug == true end
        if slug then monochrome = false end
        if v ~= nil then
            if v == "" then v = "NONE" end
            if v == "NONE" or v == "OUTLINE" or v == "THICKOUTLINE" then return ComposeFontFlags(v, monochrome, slug) end
        end
    end
    --- Fallback: derive from global boldText / noOutline
    local outline = "OUTLINE"
    if gen then
        if gen.boldText then outline = "THICKOUTLINE"
        elseif gen.noOutline then outline = "NONE" end
    end
    local fn = MSUF.Castbars and MSUF.Castbars._GetFontFlags
    if type(fn) == "function" and not (gen and (gen.boldText or gen.noOutline or gen.fontMonochrome or gen.fontSlug)) then return fn() end
    if slug then monochrome = false end
    return ComposeFontFlags(outline, monochrome, slug)
end

function GF.ResolveFontTextAlpha(kind)
    local conf = GF.GetConf(kind)
    if conf.fontOverride and conf.fontTextAlpha ~= nil then
        return ClampTextAlpha(conf.fontTextAlpha)
    end
    local db = _G.MSUF_DB
    local gen = db and db.general
    return ClampTextAlpha(gen and gen.fontTextAlpha)
end

function GF.ResolveFontBaselineOffset(kind)
    local conf = GF.GetConf(kind)
    if conf.fontOverride and conf.fontBaselineOffset ~= nil then
        return ClampBaselineOffset(conf.fontBaselineOffset)
    end
    local db = _G.MSUF_DB
    local gen = db and db.general
    return ClampBaselineOffset(gen and gen.fontBaselineOffset)
end

function GF.ResolveFontShadow(kind)
    local conf = GF.GetConf(kind)
    local db = _G.MSUF_DB
    local gen = db and db.general
    local enabled = not (gen and gen.textBackdrop == false)
    local alpha, x, y = ShadowMetrics(gen and gen.fontShadowOpacity, gen and gen.fontShadowDistance,
        gen and gen.fontShadowStrength)
    if conf.fontOverride then
        if conf.textBackdrop ~= nil then enabled = conf.textBackdrop == true end
        if conf.fontShadowOpacity ~= nil or conf.fontShadowDistance ~= nil or conf.fontShadowStrength ~= nil then
            alpha, x, y = ShadowMetrics(conf.fontShadowOpacity, conf.fontShadowDistance,
                conf.fontShadowStrength, alpha, x)
        end
    end
    if tostring(GF.ResolveFontFlags(kind) or ""):upper():find("SLUG", 1, true) then enabled = false end
    return enabled, alpha, x, y
end

--- Resolve font color (base color for non-name text)
function GF.ResolveFontColor(kind)
    local conf = GF.GetConf(kind)
    --- Override with local color only when override + useGlobalFontColor=false
    if conf.fontOverride and conf.useGlobalFontColor == false then
        if conf.fontR then
            return conf.fontR, conf.fontG or 1, conf.fontB or 1
        end
    end
    --- Fallback: global font color (shared with UF)
    local fn = MSUF.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then return fn() end
    return 1, 1, 1
end

--- UF_Config's class colour export (it loads before the group DB), resolved once
--- on first use so a fixture that never colours a name need not stub it.
local GetClassBarColorFast

local function ClassNameColor(classToken)
    GetClassBarColorFast = GetClassBarColorFast
        or MSUF.Require("MSUF_UFCore_GetClassBarColorFast", "GroupFrames/MSUF_GroupFrames_DB_Text.lua")
    local r, g, b = GetClassBarColorFast(classToken)
    if r then return r, g, b end
    local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
    if cc then return cc.r, cc.g, cc.b end
    return nil
end

--- Resolve name text color (CLASS / CUSTOM / DEFAULT fallback to font color)
function GF.ResolveNameColor(kind, classToken)
    local conf = GF.GetConf(kind)

    --- When override active: use GF-local nameColorMode
    if conf.fontOverride then
        local mode = conf.nameColorMode or "DEFAULT"
        if mode == "CLASS" and classToken then
            local r, g, b = ClassNameColor(classToken)
            if r then return r, g, b end
        end
        if mode == "CUSTOM" then
            return conf.nameColorR or 1, conf.nameColorG or 1, conf.nameColorB or 1
        end
        return GF.ResolveFontColor(kind)
    end

    --- No override: use global nameClassColor boolean (shared with UF)
    local db = _G.MSUF_DB
    local gen = db and db.general
    if gen and gen.nameClassColor and classToken then
        local r, g, b = ClassNameColor(classToken)
        if r then return r, g, b end
    end

    --- DEFAULT: use global font color
    return GF.ResolveFontColor(kind)
end

--- Resolve name truncation
--- Returns maxChars, noEllipsis, clipSide
function GF.ResolveNameTruncation(kind)
    local conf = GF.GetConf(kind)
    local localMax = tonumber(conf.nameMaxChars) or 0

    if conf.fontOverride == true then
        local enabled = conf.nameShortenEnabled
        if enabled == nil then enabled = localMax > 0 end
        if enabled ~= true then
            return 0, conf.nameNoEllipsis or false, conf.nameClipSide or "RIGHT"
        end
        if localMax <= 0 then localMax = 6 end
        local side = conf.nameClipSide or "RIGHT"
        if side ~= "LEFT" and side ~= "RIGHT" then side = "RIGHT" end
        return localMax, conf.nameNoEllipsis or false, side
    end

    local db = _G.MSUF_DB
    local gen = db and db.general
    if db and db.shortenNames == true then
        local maxChars = tonumber(gen and gen.shortenNameMaxChars) or 6
        local side = (gen and gen.shortenNameClipSide) or "LEFT"
        if side ~= "LEFT" and side ~= "RIGHT" then side = "LEFT" end
        return maxChars, (gen and gen.shortenNameShowDots == false) or false, side
    end

    return 0, false, "RIGHT"
end

---
--- Health text formatter - WoW 12.0 SECRET-SAFE (EQoL method)
---
--- In Midnight, UnitHealth/UnitPower return secret values for other
--- players. C-side abbreviators (AbbreviateNumbers, BreakUpLargeNumbers)
--- accept secret values and return secret strings. Secret strings can be
--- concatenated with ".." and passed to FontString:SetText (C-side).
--- Percent comes from UnitHealthPercent / UnitPowerPercent (non-secret).
---
--- Signature: FormatHealthText(mode, hp, hpMax, delimiter, reverse, unit, hidePercentSymbol, shortNumbers, totalAbsorb, absorbIcon)
--- The optional "unit" parameter enables the secret-safe path.
--- Preview mode (fake numeric values) omits unit - non-secret path runs.
---
--- Mode-swap table for reverse
local REVERSE_HP_MAP = {
    CURPERCENT     = "PERCENTCUR",
    PERCENTCUR     = "CURPERCENT",
    CURMAX         = "MAXCUR",
    MAXCUR         = "CURMAX",
    CURMAXPERCENT  = "PERCENTMAXCUR",
    PERCENTMAXCUR  = "CURMAXPERCENT",
    MAXPERCENT     = "PERCENTMAX",
    PERCENTMAX     = "MAXPERCENT",
    PERCENTCURMAX  = "CURMAXPERCENT",
    CURPERCENTABSORB = "PERCENTCURABSORB",
    PERCENTCURABSORB = "CURPERCENTABSORB",
    CURMAXABSORB = "MAXCURABSORB",
    MAXCURABSORB = "CURMAXABSORB",
    CURMAXPERCENTABSORB = "PERCENTMAXCURABSORB",
    PERCENTMAXCURABSORB = "CURMAXPERCENTABSORB",
    MAXPERCENTABSORB = "PERCENTMAXABSORB",
    PERCENTMAXABSORB = "MAXPERCENTABSORB",
    PERCENTCURMAXABSORB = "CURMAXPERCENTABSORB",
}

function GF.ReverseHealthTextMode(mode)
    return REVERSE_HP_MAP[mode] or mode
end

function GF.ResolveHealthTextSlots(conf)
    local hpTextOn = not conf or conf.showHPText ~= false
    local tl = hpTextOn and (conf and conf.textLeft or "NONE") or "NONE"
    local tc = hpTextOn and (conf and conf.textCenter or "NONE") or "NONE"
    local tr = hpTextOn and (conf and conf.textRight or "NONE") or "NONE"
    if conf and conf.hpTextReverse == true then
        tl, tr = tr, tl
        tl = GF.ReverseHealthTextMode(tl)
        tc = GF.ReverseHealthTextMode(tc)
        tr = GF.ReverseHealthTextMode(tr)
    end
    return tl, tc, tr
end

---
--- Global text-formatting inheritance
---
local function _GF_GetGlobalTextOpt(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

--- Module-level cache for hot-path text formatting options
--- Avoids 3 table lookups per _GF_GetGlobalTextOpt call (9+ calls per UNIT_HEALTH)
local _cachedHidePct
local _cachedUseShort
local function _GF_GetHidePct()
    if _cachedHidePct == nil then _cachedHidePct = _GF_GetGlobalTextOpt("hidePercentSymbol", false) and true or false end
    return _cachedHidePct
end
local function _GF_ResolveHidePct(hidePercentSymbol)
    if hidePercentSymbol ~= nil then return hidePercentSymbol == true end
    return _GF_GetHidePct()
end
local function _GF_GetUseShort()
    if _cachedUseShort == nil then _cachedUseShort = _GF_GetGlobalTextOpt("useShortNumbers", true) and true or false end
    return _cachedUseShort
end
function GF.InvalidateTextFormatCache()
    _cachedHidePct = nil
    _cachedUseShort = nil
end

local _GF_SPACED_DELIMITERS = {
    [""] = " ",
    ["-"] = " - ",
    ["/"] = " / ",
    ["\\"] = " \\ ",
    ["|"] = " | ",
    ["<"] = " < ",
    [">"] = " > ",
    ["~"] = " ~ ",
    [":"] = " : ",
}

local function _GF_NormalizeTextDelimiter(delimiter, fallback)
    if delimiter == nil then
        return fallback or " / "
    end
    return _GF_SPACED_DELIMITERS[delimiter] or delimiter
end

---
--- Unified abbreviator (handles secret + non-secret)
--- Secret: AbbreviateNumbers - secret string (C-side, no Lua arith)
--- Non-secret: AbbreviateNumbers or BreakUpLargeNumbers per user pref
---
local function _GF_Abbrev(val, shortNumbers)
    if val == nil then return "0" end
    local iss = _GF_issecretvalue
    local isSecret = iss and iss(val)
    local useShort = shortNumbers == nil and _GF_GetUseShort() or shortNumbers == true
    if isSecret then
        --- Secret: must use C-side abbreviator; no type()/tonumber()/arithmetic
        local fn = useShort and (_GF_AbbrShort or _GF_AbbrFallback)
                            or  (_GF_AbbrLong  or _GF_AbbrShort or _GF_AbbrFallback)
        if fn then return fn(val, useShort and _GF_NUM_OPTS or nil) end
        return val   --- raw secret ? SetText handles it C-side
    end
    --- Non-secret
    local n = tonumber(val) or 0
    local fn = useShort and (_GF_AbbrShort or _GF_AbbrFallback)
                        or  (_GF_AbbrLong  or _GF_AbbrShort or _GF_AbbrFallback)
    if fn then return fn(n, useShort and _GF_NUM_OPTS or nil) end
    return tostring(n)
end

--- Expose for callers that still reference GF._AbbrevNumber
GF._AbbrevNumber = _GF_Abbrev

---
--- Percent helpers - UnitHealthPercent / UnitPowerPercent return normal
--- numbers (not secret) in 12.0. Fallback: compute from values if both
--- are non-secret.
---
local function _GF_HealthPercent(unit, hp, hpMax)
    if _GF_UnitHealthPercent and unit then
        --- EQoL method: UnitHealthPercent(unit, usePredicted, curve)
        --- ScaleTo100 curve - returns 0- (not 0-)
        local pct = _GF_UnitHealthPercent(unit, true, _GF_ScaleTo100)
        if pct ~= nil then return pct end
    end
    --- Fallback (non-secret values only)
    local iss = _GF_issecretvalue
    if iss and (iss(hp) or iss(hpMax)) then return nil end
    local mx = tonumber(hpMax) or 0
    if mx > 0 then return (tonumber(hp) or 0) / mx * 100 end
    return nil
end

local function _GF_PowerPercent(unit, pw, pwMax)
    if _GF_UnitPowerPercent and unit then
        local ptFn = _GF_UnitPowerType
        local pType = ptFn and ptFn(unit)
        --- EQoL method: UnitPowerPercent(unit, pType, unmodified, curve)
        --- ScaleTo100 curve - returns 0- (not 0-)
        local pct
        if _GF_ScaleTo100 then
            pct = _GF_UnitPowerPercent(unit, pType, false, _GF_ScaleTo100)
        else
            pct = _GF_UnitPowerPercent(unit, pType, false, true)
        end
        if pct ~= nil then return pct end
    end
    local iss = _GF_issecretvalue
    if iss and (iss(pw) or iss(pwMax)) then return nil end
    local mx = tonumber(pwMax) or 0
    if mx > 0 then return (tonumber(pw) or 0) / mx * 100 end
    return nil
end

--- Format a percent value into "42%" or "42" (respects hidePercentSymbol).
--- Handles secret percent (rare) via C_StringUtil.RoundToNearestString.
local function _GF_FormatPct(pctVal, pctSuffix)
    if pctVal == nil then return nil end
    local iss = _GF_issecretvalue
    if iss and iss(pctVal) then
        if _GF_CSU_Round then
            return _GF_CSU_Round(pctVal) .. pctSuffix
        end
        return nil
    end
    local p = tonumber(pctVal)
    if not p then return nil end
    return math_floor(p + 0.5) .. pctSuffix
end

---
--- Core mode formatter (shared by health + power)
--- All inputs may be secret strings (from _GF_Abbrev) or normal strings.
--- String concat ".." on secret strings produces a secret string.
---
local function _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal, shortNumbers)
    if mode == "PERCENT"  then return pctStr or "" end
    if mode == "CURRENT"  then return sCur end
    if mode == "FULLVALUE" then return sCur end
    if mode == "MAX"      then return sMax end

    if mode == "DEFICIT" then
        if missingVal == nil then return "" end
        local iss = _GF_issecretvalue
        if iss and iss(missingVal) then
            return "-" .. _GF_Abbrev(missingVal, shortNumbers)
        end
        local m = tonumber(missingVal) or 0
        if m <= 0 then return "" end
        return "-" .. _GF_Abbrev(m, shortNumbers)
    end

    if mode == "CURMAX"   then return sCur .. delim .. sMax end
    if mode == "MAXCUR"   then return sMax .. delim .. sCur end

    --- All remaining modes need percent
    if not pctStr then return sCur end
    if mode == "CURPERCENT"     then return sCur .. delim .. pctStr end
    if mode == "CURMAXPERCENT"  then return sCur .. delim .. sMax .. delim .. pctStr end
    if mode == "PERCENTMAXCUR"  then return pctStr .. delim .. sMax .. delim .. sCur end
    if mode == "MAXPERCENT"     then return sMax .. delim .. pctStr end
    if mode == "PERCENTCUR"     then return pctStr .. delim .. sCur end
    if mode == "PERCENTMAX"     then return pctStr .. delim .. sMax end
    if mode == "PERCENTCURMAX"  then return pctStr .. delim .. sCur .. delim .. sMax end

    return sCur
end

---
local function _GF_FormatAbsorbText(value, shortNumbers, absorbIcon, combined)
    local iss = _GF_issecretvalue
    local secret = iss and iss(value)
    if not secret and value == nil then return "" end
    local prefix
    if combined then
        prefix = absorbIcon and (" + " .. _GF_ABSORB_ICON_MARKUP .. " ") or " + "
    elseif absorbIcon then
        prefix = _GF_ABSORB_ICON_MARKUP .. " "
    end
    if secret then
        if _GF_CSU_TruncateZero then
            local text = _GF_CSU_TruncateZero(value)
            if prefix and _GF_CSU_WrapString then return _GF_CSU_WrapString(text, prefix, "") end
            return text
        end
        return _GF_Abbrev(value, shortNumbers)
    end
    value = tonumber(value) or 0
    if value <= 0 then return "" end
    local text = _GF_Abbrev(value, shortNumbers)
    return prefix and (prefix .. text) or text
end

--- FormatHealthText(mode, hp, hpMax, delimiter, reverse [, unit [, hidePercentSymbol [, shortNumbers [, totalAbsorb [, absorbIcon]]]]])
--- mode : "PERCENT", "CURMAX", "DEFICIT", etc. or "NONE"
--- hp, hpMax : raw UnitHealth / UnitHealthMax (possibly secret)
--- delimiter : " / " etc.
--- reverse : swap mode before formatting
--- unit : unitId for secret-safe percent (optional, nil in preview)
---
function GF.FormatHealthText(mode, hp, hpMax, delimiter, reverse, unit, hidePercentSymbol, shortNumbers, totalAbsorb, absorbIcon)
    if not mode or mode == "NONE" then return "" end
    if reverse then mode = REVERSE_HP_MAP[mode] or mode end

    local absorbBaseMode = _GF_ABSORB_MODE_BASE[mode]
    local absorbText = ""
    if mode == "ABSORB" or absorbBaseMode then
        local value = totalAbsorb
        local valueIsSecret = _GF_issecretvalue and _GF_issecretvalue(value)
        if not valueIsSecret and value == nil and unit and _GF_UnitGetTotalAbsorbs then
            value = _GF_UnitGetTotalAbsorbs(unit)
        end
        absorbText = _GF_FormatAbsorbText(value, shortNumbers, absorbIcon == true, absorbBaseMode ~= nil)
        if mode == "ABSORB" then return absorbText end
        mode = absorbBaseMode
    end

    local delim = _GF_NormalizeTextDelimiter(delimiter, " / ")
    local hidePct = _GF_ResolveHidePct(hidePercentSymbol)
    local pctSuffix = hidePct and "" or "%"

    --- Abbreviate cur/max (secret-safe: C-side abbreviators)
    local sCur = _GF_Abbrev(hp, shortNumbers)
    local sMax = _GF_Abbrev(hpMax, shortNumbers)

    --- Percent (non-secret via UnitHealthPercent API; fallback if non-secret values)
    local pctStr = nil
    if mode ~= "CURRENT" and mode ~= "FULLVALUE" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = _GF_HealthPercent(unit, hp, hpMax)
        pctStr = _GF_FormatPct(pctVal, pctSuffix)
    end

    --- Deficit: try UnitHealthMissing API (secret-safe), else compute if non-secret
    local missingVal = nil
    if mode == "DEFICIT" then
        if _GF_UnitHealthMissing and unit then
            missingVal = _GF_UnitHealthMissing(unit)
        end
        if missingVal == nil then
            local iss = _GF_issecretvalue
            if not (iss and (iss(hp) or iss(hpMax))) then
                local cur = tonumber(hp) or 0
                local mx  = tonumber(hpMax) or 0
                missingVal = mx - cur
            end
        end
    end

    return _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal, shortNumbers) .. absorbText
end

--- Truncate name string (UTF-8 aware when possible)
function GF.TruncateName(name, maxChars, noEllipsis, clipSide)
    maxChars = math_floor((tonumber(maxChars) or 0) + 0.5)
    if not name or maxChars <= 0 then return name end
    if _GF_issecretvalue and _GF_issecretvalue(name) then return name end
    clipSide = (clipSide == "LEFT") and "LEFT" or "RIGHT"

    local function NextByte(pos)
        local b = string.byte(name, pos)
        if not b then return pos + 1 end
        if b < 128 then return pos + 1 end
        if b < 224 then return pos + 2 end
        if b < 240 then return pos + 3 end
        return pos + 4
    end

    local charCount = 0
    local bytePos = 1
    local nameLen = #name
    while bytePos <= nameLen do
        charCount = charCount + 1
        bytePos = NextByte(bytePos)
    end

    if charCount <= maxChars then return name end

    if clipSide == "LEFT" then
        local skip = charCount - maxChars
        bytePos = 1
        for _ = 1, skip do
            bytePos = NextByte(bytePos)
        end
        local truncated = string.sub(name, bytePos)
        if noEllipsis then return truncated end
        return ".." .. truncated
    end

    charCount = 0
    bytePos = 1
    while bytePos <= nameLen and charCount < maxChars do
        charCount = charCount + 1
        bytePos = NextByte(bytePos)
    end
    local truncated = string.sub(name, 1, bytePos - 1)
    if noEllipsis then return truncated end
    return truncated .. ".."
end

--- Check if any text slot is active (not NONE)
function GF.HasActiveTextSlot(kind)
    local conf = GF.GetConf(kind)
    local tl = conf.textLeft  or "NONE"
    local tc = conf.textCenter or "NONE"
    local tr = conf.textRight or "NONE"
    return tl ~= "NONE" or tc ~= "NONE" or tr ~= "NONE"
end

---
--- FormatPowerText(mode, pw, pwMax, delimiter [, unit [, hidePercentSymbol]])
--- Same modes as health text. Secret-safe via C-side abbreviators.
---
function GF.FormatPowerText(mode, pw, pwMax, delimiter, unit, hidePercentSymbol)
    if not mode or mode == "NONE" then return "" end

    local delim = _GF_NormalizeTextDelimiter(delimiter, " / ")
    local hidePct = _GF_ResolveHidePct(hidePercentSymbol)
    local pctSuffix = hidePct and "" or "%"

    --- Abbreviate cur/max (secret-safe)
    local sCur = _GF_Abbrev(pw)
    local sMax = _GF_Abbrev(pwMax)

    --- Percent
    local pctStr = nil
    if mode ~= "CURRENT" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = _GF_PowerPercent(unit, pw, pwMax)
        pctStr = _GF_FormatPct(pctVal, pctSuffix)
    end

    --- Deficit: compute from values if non-secret (no UnitPowerMissing API)
    local missingVal = nil
    if mode == "DEFICIT" then
        local iss = _GF_issecretvalue
        if not (iss and (iss(pw) or iss(pwMax))) then
            local cur = tonumber(pw) or 0
            local mx  = tonumber(pwMax) or 0
            missingVal = mx - cur
        end
    end

    return _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal)
end

--- Check if any power text slot is active
function GF.HasActivePowerTextSlot(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) then return false end
    local tl = conf.powerTextLeft   or "NONE"
    local tc = conf.powerTextCenter or "NONE"
    local tr = conf.powerTextRight  or "NONE"
    return tl ~= "NONE" or tc ~= "NONE" or tr ~= "NONE"
end
