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

-- The engine loads before Group DB text. Keep inherited options on the existing
-- invalidation boundary; return-value formatting is explicitly the GROUP contract.
local TEXT_CONTEXT = "GroupFrames/MSUF_GroupFrames_DB_Text.lua"
local Text = MSUF.Require("MSUF_NS", TEXT_CONTEXT).UFText
if type(Text) ~= "table" then
    error("MSUF: missing required dependency 'UFText' required by " .. TEXT_CONTEXT, 2)
end
for _, name in ipairs({ "FormatValue", "FormatPercentValue", "FormatHealthString", "FormatPowerString", "TruncateName",
    "PercentFromValues", "MissingHealthFromValues" }) do
    -- Validate field readiness in the same resolve/type phase as MSUF.Require.
    local kind = type(Text[name])
    if kind ~= "function" then
        error("MSUF: missing required dependency 'UFText." .. name .. "' required by " .. TEXT_CONTEXT, 2)
    end
end

function GF.FormatHealthText(mode, hp, hpMax, delimiter, reverse, unit, hidePercentSymbol, shortNumbers,
    totalAbsorb, absorbIcon, percentDecimals)
    if not mode or mode == "NONE" then return "" end
    if reverse then mode = GF.ReverseHealthTextMode(mode) end
    if shortNumbers == nil then shortNumbers = _GF_GetUseShort() end
    return Text.FormatHealthString(mode, hp, hpMax, delimiter, unit, _GF_ResolveHidePct(hidePercentSymbol),
        shortNumbers == true, totalAbsorb, absorbIcon, percentDecimals, "GROUP")
end

function GF.TruncateName(name, maxChars, noEllipsis, clipSide)
    return Text.TruncateName(name, maxChars, not noEllipsis, clipSide)
end

function GF.FormatPowerText(mode, pw, pwMax, delimiter, unit, hidePercentSymbol)
    if not mode or mode == "NONE" then return "" end
    return Text.FormatPowerString(mode, pw, pwMax, delimiter, unit, _GF_ResolveHidePct(hidePercentSymbol),
        _GF_GetUseShort(), "GROUP")
end
