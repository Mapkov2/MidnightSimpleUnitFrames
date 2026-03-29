-- MSUF_GF_DB.lua — Group Frames DB defaults + config resolution
-- Phase 12: 3-slot health text, name color, name max chars, power per-role,
--           smooth fill toggle, hideInClientScene, target/aggro upgrades
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

ns.GF = ns.GF or {}
local GF = ns.GF

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor

------------------------------------------------------------------------
-- C-API references for secret-safe text formatting (WoW 12.0)
-- AbbreviateNumbers / BreakUpLargeNumbers accept secret values and
-- return secret strings that pass through to C-side SetText.
------------------------------------------------------------------------
local _GF_AbbrShort  = _G.AbbreviateNumbers         -- "1.2k"  (secret-safe)
local _GF_AbbrLong   = _G.BreakUpLargeNumbers       -- "1,234" (secret-safe)
local _GF_AbbrFallback = _G.AbbreviateLargeNumbers or _G.ShortenNumber
local _GF_UnitHealthPercent = _G.UnitHealthPercent   -- returns non-secret %
local _GF_UnitPowerPercent  = _G.UnitPowerPercent    -- returns non-secret %
local _GF_UnitPowerType     = _G.UnitPowerType
local _GF_UnitHealthMissing = _G.UnitHealthMissing   -- secret-safe deficit
local _GF_CSU_Round = _G.C_StringUtil and _G.C_StringUtil.RoundToNearestString
local _GF_ScaleTo100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100
local _GF_issecretvalue = _G.issecretvalue

------------------------------------------------------------------------
-- Health text modes (matches EQoL healthTextModeOptions)
------------------------------------------------------------------------
GF.HEALTH_TEXT_MODES = {
    { key = "NONE",           label = "None"                           },
    { key = "PERCENT",        label = "Percent"                        },
    { key = "CURRENT",        label = "Current"                        },
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

------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------
local PARTY_DEFAULTS = {
    enabled           = false,
    width             = 120,
    height            = 40,
    spacing           = 1,
    growth            = "DOWN",    -- DOWN / UP / RIGHT / LEFT
    showPlayer        = true,
    showSolo          = false,
    powerHeight       = 6,
    -- Position (CENTER-native, same as EM2 movers)
    point             = "CENTER",
    offsetX           = -400,
    offsetY           = 0,
    -- Health bar
    healthColorMode   = "CLASS",   -- CLASS / GRADIENT / CUSTOM
    healthCustomR     = 0.2,
    healthCustomG     = 0.8,
    healthCustomB     = 0.2,
    -- Bar textures (nil = inherit global)
    barTexture        = nil,
    barBgTexture      = nil,
    -- Background
    bgR               = 0.1,
    bgG               = 0.1,
    bgB               = 0.1,
    bgA               = 0.85,
    -- Border
    borderEnabled     = true,
    borderSize        = 1,
    borderR           = 0,
    borderG           = 0,
    borderB           = 0,
    borderA           = 1,
    -- Text: 3-slot system (replaces showHP boolean)
    showName          = true,
    showPower         = false,
    nameAnchor        = "LEFT",
    nameFontSize      = 12,
    hpFontSize        = 10,
    powerFontSize     = 9,
    textLeft          = "NONE",
    textCenter        = "PERCENT",
    textRight         = "NONE",
    textDelimiter     = " / ",
    -- Reverse order toggle (flips multi-part modes)
    hpTextReverse     = false,
    -- Name color
    nameColorMode     = "DEFAULT",  -- DEFAULT / CLASS / CUSTOM
    nameColorR        = 1,
    nameColorG        = 1,
    nameColorB        = 1,
    -- Name truncation
    nameMaxChars      = 0,     -- 0 = unlimited
    nameNoEllipsis    = false,
    -- Fonts (nil = inherit global)
    fontKey           = nil,
    fontOutline       = nil,
    useGlobalFontColor = true,
    fontR             = nil,
    fontG             = nil,
    fontB             = nil,
    -- Range fade
    rangeFadeEnabled  = true,
    rangeFadeAlpha    = 0.4,
    offlineAlpha      = 0.5,
    -- Aggro border
    aggroEnabled      = true,
    aggroR            = 1,
    aggroG            = 0,
    aggroB            = 0,
    aggroMode         = "ALL",  -- ALL / HEALER_ONLY / TANK_ONLY
    -- Dispel border
    dispelEnabled     = true,
    -- Target indicator
    targetIndicator   = true,
    targetR           = 1,
    targetG           = 1,
    targetB           = 1,
    -- Status icons
    iconStyle         = "BLIZZARD",  -- BLIZZARD / GLOSSY_ORBS / DARK_EMBOSS / etc.
    useMidnightIcons  = false,
    roleIcon          = true,
    roleIconSize      = 12,
    roleIconAnchor    = "TOPLEFT",
    roleIconX         = 0,
    roleIconY         = 0,
    raidMarker        = true,
    raidMarkerSize    = 14,
    raidMarkerAnchor  = "CENTER",
    raidMarkerX       = 0,
    raidMarkerY       = 0,
    leaderIcon        = true,
    leaderIconSize    = 12,
    leaderIconAnchor  = "TOPRIGHT",
    leaderIconX       = 0,
    leaderIconY       = 0,
    assistIcon        = true,
    assistIconSize    = 12,
    assistIconAnchor  = "TOPRIGHT",
    assistIconX       = 14,
    assistIconY       = 0,
    readyCheckIcon    = true,
    readyCheckSize    = 16,
    readyCheckAnchor  = "CENTER",
    readyCheckX       = 0,
    readyCheckY       = 0,
    summonIcon        = true,
    summonIconSize    = 16,
    summonAnchor      = "CENTER",
    summonX           = 0,
    summonY           = 0,
    resurrectIcon     = true,
    resurrectIconSize = 16,
    resurrectAnchor   = "CENTER",
    resurrectX        = 0,
    resurrectY        = 0,
    phaseIcon         = true,
    phaseIconSize     = 14,
    phaseAnchor       = "TOPLEFT",
    phaseX            = 0,
    phaseY            = 0,
    -- Text offsets
    nameOffsetX       = 0,
    nameOffsetY       = 0,
    hpOffsetX         = 0,
    hpOffsetY         = 0,
    powerOffsetX      = 0,
    powerOffsetY      = 0,
    statusOffsetX     = 0,
    statusOffsetY     = 0,
    -- Alpha pipeline (matches main UF alpha fields)
    alphaInCombat        = 1,
    alphaOutOfCombat     = 1,
    alphaFGInCombat      = 1,
    alphaFGOutOfCombat   = 1,
    alphaBGInCombat      = 1,
    alphaBGOutOfCombat   = 1,
    -- Health prediction overlays (colors from global Colors menu)
    absorbEnabled         = true,
    healAbsorbEnabled     = true,
    healPredEnabled       = true,
    -- Tooltip
    tooltipMode           = "ALWAYS",  -- ALWAYS / OOC / MODIFIER / NEVER
    tooltipModifier       = "ALT",     -- ALT / CTRL / SHIFT
    -- Group number (raid subgroup on frame)
    showGroupNumber       = false,
    groupNumberSize       = 10,
    groupNumberAnchor     = "BOTTOMRIGHT",
    groupNumberX          = -2,
    groupNumberY          = 2,
    -- Reverse fill
    reverseFill           = false,
    -- Smooth fill
    smoothFill            = true,
    -- Hide in client scene (barber/dressing room)
    hideInClientScene     = true,
    -- Power per-role visibility
    powerShowTank         = true,
    powerShowHealer       = true,
    powerShowDamager      = false,
    -- Power 3-slot text system
    powerTextLeft         = "NONE",
    powerTextCenter       = "PERCENT",
    powerTextRight        = "NONE",
    powerTextDelimiter    = " / ",
    -- Power smooth fill
    powerSmoothFill       = false,
    -- Auras (Phase 4, stubs)
    aurasEnabled      = false,
    auraMaxIcons      = 4,
    auraIconSize      = 20,
    -- Private Auras
    privateAurasEnabled    = true,
    privateAuraMax         = 4,
    privateAuraSize        = 20,
    privateAuraAnchor      = "TOPRIGHT",
    privateAuraX           = 0,
    privateAuraY           = 0,
    privateAuraCountdown   = true,
    -- Grid layout
    unitsPerColumn    = 5,
    maxColumns        = 1,
}

local RAID_DEFAULTS = {}
do
    for k, v in pairs(PARTY_DEFAULTS) do
        RAID_DEFAULTS[k] = v
    end
    RAID_DEFAULTS.width          = 80
    RAID_DEFAULTS.height         = 32
    RAID_DEFAULTS.spacing        = 1
    RAID_DEFAULTS.growth         = "DOWN"
    RAID_DEFAULTS.showPlayer     = true
    RAID_DEFAULTS.showSolo       = false
    RAID_DEFAULTS.powerHeight    = 4
    RAID_DEFAULTS.offsetX        = -500
    RAID_DEFAULTS.offsetY        = 0
    RAID_DEFAULTS.textLeft       = "NONE"
    RAID_DEFAULTS.textCenter     = "NONE"
    RAID_DEFAULTS.textRight      = "NONE"
    RAID_DEFAULTS.showPower      = false
    RAID_DEFAULTS.nameFontSize   = 10
    RAID_DEFAULTS.hpFontSize     = 9
    RAID_DEFAULTS.roleIconSize   = 10
    RAID_DEFAULTS.raidMarkerSize = 12
    RAID_DEFAULTS.auraMaxIcons   = 3
    RAID_DEFAULTS.auraIconSize   = 16
    RAID_DEFAULTS.unitsPerColumn = 5
    RAID_DEFAULTS.maxColumns     = 8
    RAID_DEFAULTS.showGroupNumber = true
    RAID_DEFAULTS.powerShowTank    = true
    RAID_DEFAULTS.powerShowHealer  = true
    RAID_DEFAULTS.powerShowDamager = false
end

GF.PARTY_DEFAULTS = PARTY_DEFAULTS
GF.RAID_DEFAULTS  = RAID_DEFAULTS

------------------------------------------------------------------------
-- Grid metrics (stored position = GRID CENTER)
------------------------------------------------------------------------
GF._measuredFirstCenterDelta = GF._measuredFirstCenterDelta or {}

function GF.GetHeaderOriginToFirstCenter(kind, w, h)
    local t = GF._measuredFirstCenterDelta and GF._measuredFirstCenterDelta[kind]
    if t and t.x ~= nil and t.y ~= nil then
        return t.x, t.y
    end
    return (w or 0) * 0.5, -(h or 0) * 0.5
end

function GF.GetGridMetrics(kind, count)
    local conf = GF.GetConf(kind)
    local w   = conf.width  or (kind == "raid" and 80 or 120)
    local h   = conf.height or (kind == "raid" and 32 or 40)
    local sp  = conf.spacing or 1
    local growth = conf.growth or "DOWN"
    local upc = conf.unitsPerColumn or 5

    count = tonumber(count) or 0
    if count < 1 then count = (kind == "raid" and 10 or 4) end

    local numCols = math_ceil(count / upc)
    if numCols < 1 then numCols = 1 end
    local major = math_min(count, upc)

    local totalW, totalH
    if growth == "DOWN" or growth == "UP" then
        totalW = numCols * w + math_max(0, numCols - 1) * sp
        totalH = major   * h + math_max(0, major   - 1) * sp
    else
        totalW = major   * w + math_max(0, major   - 1) * sp
        totalH = numCols * h + math_max(0, numCols - 1) * sp
    end

    local firstDX, firstDY = GF.GetHeaderOriginToFirstCenter(kind, w, h)
    local dx, dy = firstDX, firstDY
    if growth == "DOWN" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "UP" then
        dx = dx + (totalW - w) * 0.5
        dy = dy + (totalH - h) * 0.5
    elseif growth == "RIGHT" then
        dx = dx + (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    elseif growth == "LEFT" then
        dx = dx - (totalW - w) * 0.5
        dy = dy - (totalH - h) * 0.5
    end

    return dx, dy, totalW, totalH, w, h, sp, growth, upc, count, firstDX, firstDY
end

local function GetMigrationCount(kind, conf)
    if kind == "raid" then
        local isInRaid = _G.IsInRaid
        local getNum = _G.GetNumGroupMembers
        local n = (type(getNum) == "function") and (getNum() or 0) or 0
        if (type(isInRaid) == "function" and isInRaid()) and n > 0 then
            return n
        end
        return 10
    end

    local getSub = _G.GetNumSubgroupMembers
    local n = (type(getSub) == "function") and (getSub() or 0) or 0
    if n > 0 then
        if conf.showPlayer ~= false then n = n + 1 end
        return n
    end
    if conf.showSolo and conf.showPlayer ~= false then
        return 1
    end
    return 4
end

local function MigrateGroupPositionToGridCenter(conf, kind)
    if type(conf) ~= "table" then return end
    if conf.positionMode == "GRID_CENTER_V1" then return end
    local dx, dy = GF.GetGridMetrics(kind, GetMigrationCount(kind, conf))
    conf.offsetX = (conf.offsetX or (kind == "raid" and -500 or -400)) + dx
    conf.offsetY = (conf.offsetY or 0) + dy
    conf.positionMode = "GRID_CENTER_V1"
end

------------------------------------------------------------------------
-- Migration: showHP boolean → 3-slot text
------------------------------------------------------------------------
local function MigrateShowHPTo3Slot(conf)
    if type(conf) ~= "table" then return end
    -- Only migrate if old showHP exists and no 3-slot keys set yet
    if conf.showHP ~= nil and conf.textCenter == nil and conf.textLeft == nil and conf.textRight == nil then
        if conf.showHP then
            conf.textCenter = "PERCENT"
        else
            conf.textCenter = "NONE"
        end
        conf.textLeft  = "NONE"
        conf.textRight = "NONE"
    end
    -- Remove legacy key after migration
    conf.showHP = nil
end

------------------------------------------------------------------------
-- Migration: GF-local highlight keys → unified hl* with hlOverride
------------------------------------------------------------------------
local function MigrateHighlightToUnified(conf)
    if type(conf) ~= "table" then return end
    if conf._hlMigrated then return end
    -- Migrate old GF-local geometry keys to hlOverride scope
    local hadCustom = false
    local map = {
        aggroHighlightSize    = "hlAggroSize",
        aggroHighlightOffset  = "hlAggroOffset",
        aggroHighlightLayer   = "hlAggroLayer",
        targetBorderSize      = "hlTargetSize",
        targetHighlightOffset = "hlTargetOffset",
        targetHighlightLayer  = "hlTargetLayer",
        hoverHighlightSize    = "hlHoverSize",
        hoverHighlightOffset  = "hlHoverOffset",
    }
    for oldKey, newKey in pairs(map) do
        if conf[oldKey] ~= nil then
            conf[newKey] = conf[oldKey]
            hadCustom = true
        end
    end
    if hadCustom then conf.hlOverride = true end
    conf._hlMigrated = true
end

------------------------------------------------------------------------
-- DB init
------------------------------------------------------------------------
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

function GF.EnsureDB()
    local db = _G.MSUF_DB
    if not db then return end
    if type(db.gf_party) ~= "table" then db.gf_party = {} end
    if type(db.gf_raid)  ~= "table" then db.gf_raid  = {} end
    MigrateShowHPTo3Slot(db.gf_party)
    MigrateShowHPTo3Slot(db.gf_raid)
    MigrateHighlightToUnified(db.gf_party)
    MigrateHighlightToUnified(db.gf_raid)
    applyDefaults(db.gf_party, PARTY_DEFAULTS)
    applyDefaults(db.gf_raid,  RAID_DEFAULTS)
    MigrateGroupPositionToGridCenter(db.gf_party, "party")
    MigrateGroupPositionToGridCenter(db.gf_raid, "raid")
    -- Migrate flat aura/private-aura keys → nested tables
    if GF.MigrateAuraConfig then
        GF.MigrateAuraConfig(db.gf_party, false)
        GF.MigrateAuraConfig(db.gf_raid, true)
    end
end

------------------------------------------------------------------------
-- Config resolution
------------------------------------------------------------------------
function GF.GetConf(kind)
    local db = _G.MSUF_DB
    if not db then return kind == "raid" and RAID_DEFAULTS or PARTY_DEFAULTS end
    if kind == "raid" then
        return (type(db.gf_raid) == "table" and db.gf_raid) or RAID_DEFAULTS
    end
    return (type(db.gf_party) == "table" and db.gf_party) or PARTY_DEFAULTS
end

function GF.GetDefault(kind, key)
    if kind == "raid" then return RAID_DEFAULTS[key] end
    return PARTY_DEFAULTS[key]
end

--- Resolve a config value with fallback to default
function GF.Val(kind, key)
    local conf = GF.GetConf(kind)
    local v = conf[key]
    if v ~= nil then return v end
    if kind == "raid" then return RAID_DEFAULTS[key] end
    return PARTY_DEFAULTS[key]
end

--- Resolve a unified highlight value with scope override support.
--- GF-local (gf_party/gf_raid) can override general.hl* keys via hlOverride=true.
--- Falls through to MSUF_DB.general.hl* baseline.
function GF.GetHighlightVal(kind, key)
    local conf = GF.GetConf(kind)
    if conf.hlOverride and conf[key] ~= nil then return conf[key] end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return nil
end

--- Resolve bar texture path (falls through to global MSUF bar texture)
function GF.ResolveBarTexture(kind)
    local conf = GF.GetConf(kind)
    local key = conf.barTexture
    if key and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then return resolve(key) end
    end
    local fn = _G.MSUF_GetBarTexture
    if type(fn) == "function" then return fn() end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

--- Resolve bar background texture path
function GF.ResolveBarBgTexture(kind)
    local conf = GF.GetConf(kind)
    local key = conf.barBgTexture
    if key and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then return resolve(key) end
    end
    local fn = _G.MSUF_GetBarBackgroundTexture or _G.MSUF_GetBarTexture
    if type(fn) == "function" then return fn() end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

--- Resolve highlight border edge texture (LSM key → path, nil → WHITE8x8)
function GF.ResolveHighlightTexture(lsmKey)
    if not lsmKey or lsmKey == "" then return "Interface\\Buttons\\WHITE8x8" end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local p = LSM:Fetch("border", lsmKey, true)
        if p then return p end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

--- Resolve font path (falls through to global MSUF font)
function GF.ResolveFontPath(kind)
    local conf = GF.GetConf(kind)
    local key = conf.fontKey
    if key and key ~= "" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local p = LSM:Fetch("font", key, true)
            if p then return p end
        end
    end
    local fn = ns.Castbars and ns.Castbars._GetFontPath
    if type(fn) == "function" then return fn() end
    return "Fonts\\FRIZQT__.TTF"
end

--- Resolve font outline flags
function GF.ResolveFontFlags(kind)
    local conf = GF.GetConf(kind)
    local v = conf.fontOutline
    if v ~= nil then
        if v == "" or v == "NONE" then return "" end
        if v == "OUTLINE" or v == "THICKOUTLINE" then return v end
    end
    local fn = ns.Castbars and ns.Castbars._GetFontFlags
    if type(fn) == "function" then return fn() end
    return "OUTLINE"
end

--- Resolve font color (base color for non-name text)
function GF.ResolveFontColor(kind)
    local conf = GF.GetConf(kind)
    if conf.useGlobalFontColor ~= false then
        local fn = ns.MSUF_GetConfiguredFontColor
        if type(fn) == "function" then return fn() end
    end
    if conf.fontR then
        return conf.fontR, conf.fontG or 1, conf.fontB or 1
    end
    return 1, 1, 1
end

--- Resolve name text color (CLASS / CUSTOM / DEFAULT fallback to font color)
function GF.ResolveNameColor(kind, classToken)
    local conf = GF.GetConf(kind)
    local mode = conf.nameColorMode or "DEFAULT"

    if mode == "CLASS" and classToken then
        local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
        if type(fastClass) == "function" then
            local r, g, b = fastClass(nil, classToken)
            if r then return r, g, b end
        end
        local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
        if cc then return cc.r, cc.g, cc.b end
    end

    if mode == "CUSTOM" then
        return conf.nameColorR or 1, conf.nameColorG or 1, conf.nameColorB or 1
    end

    -- DEFAULT: use global font color
    return GF.ResolveFontColor(kind)
end

------------------------------------------------------------------------
-- Health text formatter — WoW 12.0 SECRET-SAFE (EQoL method)
--
-- In Midnight, UnitHealth/UnitPower return secret values for other
-- players. C-side abbreviators (AbbreviateNumbers, BreakUpLargeNumbers)
-- accept secret values and return secret strings. Secret strings can be
-- concatenated with ".." and passed to FontString:SetText (C-side).
-- Percent comes from UnitHealthPercent / UnitPowerPercent (non-secret).
--
-- Signature: FormatHealthText(mode, hp, hpMax, delimiter, reverse, unit)
-- The optional "unit" parameter enables the secret-safe path.
-- Preview mode (fake numeric values) omits unit → non-secret path runs.
------------------------------------------------------------------------
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
}

------------------------------------------------------------------------
-- Global text-formatting inheritance
------------------------------------------------------------------------
local function _GF_GetGlobalTextOpt(key, fallback)
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen and gen[key] ~= nil then return gen[key] end
    return fallback
end

------------------------------------------------------------------------
-- Unified abbreviator (handles secret + non-secret)
-- Secret:     AbbreviateNumbers → secret string (C-side, no Lua arith)
-- Non-secret: AbbreviateNumbers or BreakUpLargeNumbers per user pref
------------------------------------------------------------------------
local function _GF_Abbrev(val)
    if val == nil then return "0" end
    local iss = _GF_issecretvalue
    local isSecret = iss and iss(val)
    local useShort = _GF_GetGlobalTextOpt("useShortNumbers", true)
    if isSecret then
        -- Secret: must use C-side abbreviator; no type()/tonumber()/arithmetic
        local fn = useShort and (_GF_AbbrShort or _GF_AbbrFallback)
                            or  (_GF_AbbrLong  or _GF_AbbrShort or _GF_AbbrFallback)
        if fn then return fn(val) end
        return val   -- raw secret → SetText handles it C-side
    end
    -- Non-secret
    local n = tonumber(val) or 0
    local fn = useShort and (_GF_AbbrShort or _GF_AbbrFallback)
                        or  (_GF_AbbrLong  or _GF_AbbrShort or _GF_AbbrFallback)
    if fn then return fn(n) end
    return tostring(n)
end

--- Expose for callers that still reference GF._AbbrevNumber
GF._AbbrevNumber = _GF_Abbrev

------------------------------------------------------------------------
-- Percent helpers — UnitHealthPercent / UnitPowerPercent return normal
-- numbers (not secret) in 12.0.  Fallback: compute from values if both
-- are non-secret.
------------------------------------------------------------------------
local function _GF_HealthPercent(unit, hp, hpMax)
    if _GF_UnitHealthPercent and unit then
        -- EQoL method: UnitHealthPercent(unit, usePredicted, curve)
        -- ScaleTo100 curve → returns 0–100 (not 0–1)
        local pct = _GF_UnitHealthPercent(unit, true, _GF_ScaleTo100)
        if pct ~= nil then return pct end
    end
    -- Fallback (non-secret values only)
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
        -- EQoL method: UnitPowerPercent(unit, pType, unmodified, curve)
        -- ScaleTo100 curve → returns 0–100 (not 0–1)
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
        -- Secret percent (very rare): delegate to C-side
        if _GF_CSU_Round then
            return tostring(_GF_CSU_Round(pctVal)) .. pctSuffix
        end
        return nil
    end
    local p = tonumber(pctVal)
    if not p then return nil end
    return tostring(math_floor(p + 0.5)) .. pctSuffix
end

------------------------------------------------------------------------
-- Core mode formatter (shared by health + power)
-- All inputs may be secret strings (from _GF_Abbrev) or normal strings.
-- String concat ".." on secret strings produces a secret string.
------------------------------------------------------------------------
local function _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal)
    if mode == "PERCENT"  then return pctStr or "" end
    if mode == "CURRENT"  then return tostring(sCur) end
    if mode == "MAX"      then return tostring(sMax) end

    if mode == "DEFICIT" then
        if missingVal == nil then return "" end
        local iss = _GF_issecretvalue
        if iss and iss(missingVal) then
            -- Secret deficit → abbreviate, always show (can't test <= 0)
            return "-" .. tostring(_GF_Abbrev(missingVal))
        end
        local m = tonumber(missingVal) or 0
        if m <= 0 then return "" end
        return "-" .. tostring(_GF_Abbrev(m))
    end

    if mode == "CURMAX"   then return tostring(sCur) .. delim .. tostring(sMax) end
    if mode == "MAXCUR"   then return tostring(sMax) .. delim .. tostring(sCur) end

    -- All remaining modes need percent
    if not pctStr then
        -- Percent unavailable: degrade gracefully to current value
        return tostring(sCur)
    end
    if mode == "CURPERCENT"     then return tostring(sCur) .. delim .. pctStr end
    if mode == "CURMAXPERCENT"  then return tostring(sCur) .. delim .. tostring(sMax) .. delim .. pctStr end
    if mode == "PERCENTMAXCUR"  then return pctStr .. delim .. tostring(sMax) .. delim .. tostring(sCur) end
    if mode == "MAXPERCENT"     then return tostring(sMax) .. delim .. pctStr end
    if mode == "PERCENTCUR"     then return pctStr .. delim .. tostring(sCur) end
    if mode == "PERCENTMAX"     then return pctStr .. delim .. tostring(sMax) end
    if mode == "PERCENTCURMAX"  then return pctStr .. delim .. tostring(sCur) .. delim .. tostring(sMax) end

    return tostring(sCur)
end

------------------------------------------------------------------------
-- FormatHealthText(mode, hp, hpMax, delimiter, reverse [, unit])
--   mode      : "PERCENT", "CURMAX", "DEFICIT", etc. or "NONE"
--   hp, hpMax : raw UnitHealth / UnitHealthMax (possibly secret)
--   delimiter : " / " etc.
--   reverse   : swap mode before formatting
--   unit      : unitId for secret-safe percent (optional, nil in preview)
------------------------------------------------------------------------
function GF.FormatHealthText(mode, hp, hpMax, delimiter, reverse, unit)
    if not mode or mode == "NONE" then return "" end
    if reverse then mode = REVERSE_HP_MAP[mode] or mode end

    local delim = delimiter or " / "
    local hidePct = _GF_GetGlobalTextOpt("hidePercentSymbol", false)
    local pctSuffix = hidePct and "" or "%"

    -- Abbreviate cur/max (secret-safe: C-side abbreviators)
    local sCur = _GF_Abbrev(hp)
    local sMax = _GF_Abbrev(hpMax)

    -- Percent (non-secret via UnitHealthPercent API; fallback if non-secret values)
    local pctStr = nil
    if mode ~= "CURRENT" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = _GF_HealthPercent(unit, hp, hpMax)
        pctStr = _GF_FormatPct(pctVal, pctSuffix)
    end

    -- Deficit: try UnitHealthMissing API (secret-safe), else compute if non-secret
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

    return _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal)
end

--- Truncate name string (UTF-8 aware when possible)
function GF.TruncateName(name, maxChars, noEllipsis)
    if not name or maxChars == nil or maxChars <= 0 then return name end
    local len = string.len(name)
    if len <= maxChars then return name end
    local truncated = string.sub(name, 1, maxChars)
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

------------------------------------------------------------------------
-- FormatPowerText(mode, pw, pwMax, delimiter [, unit])
--   Same modes as health text. Secret-safe via C-side abbreviators.
------------------------------------------------------------------------
function GF.FormatPowerText(mode, pw, pwMax, delimiter, unit)
    if not mode or mode == "NONE" then return "" end

    local delim = delimiter or " / "
    local hidePct = _GF_GetGlobalTextOpt("hidePercentSymbol", false)
    local pctSuffix = hidePct and "" or "%"

    -- Abbreviate cur/max (secret-safe)
    local sCur = _GF_Abbrev(pw)
    local sMax = _GF_Abbrev(pwMax)

    -- Percent
    local pctStr = nil
    if mode ~= "CURRENT" and mode ~= "MAX" and mode ~= "CURMAX" and mode ~= "MAXCUR" and mode ~= "DEFICIT" then
        local pctVal = _GF_PowerPercent(unit, pw, pwMax)
        pctStr = _GF_FormatPct(pctVal, pctSuffix)
    end

    -- Deficit: compute from values if non-secret (no UnitPowerMissing API)
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
function GF.HasActivePowerTextSlot(kind)
    local conf = GF.GetConf(kind)
    if not conf.showPower then return false end
    local tl = conf.powerTextLeft   or "NONE"
    local tc = conf.powerTextCenter or "NONE"
    local tr = conf.powerTextRight  or "NONE"
    return tl ~= "NONE" or tc ~= "NONE" or tr ~= "NONE"
end

------------------------------------------------------------------------
-- Icon style resolver
------------------------------------------------------------------------
local MEDIA_PREFIX = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\"

local BLIZZARD_ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local BLIZZARD_ROLE_COORDS = {
    TANK    = { 0,    19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}
local BLIZZARD_LEADER_TEX = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local BLIZZARD_ASSIST_TEX = "Interface\\GroupFrame\\UI-Group-AssistantIcon"

local CUSTOM_STYLES = {
    GLOSSY_ORBS   = "GlossyOrbs",
    NEON_OUTLINE  = "NeonOutline",
    RING_SYMBOLS  = "RingSymbols",
    GLASS_PANELS  = "GlassPanels",
    DARK_EMBOSS   = "DarkEmboss",
    DOTS          = "Dots",
    SHAPES        = "Shapes",
    DIAMONDS      = "Diamonds",
    SQUARES       = "Squares",
}

local ROLE_MAP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

function GF.GetRoleTexture(kind, role)
    local conf = GF.GetConf(kind)
    local style = conf.iconStyle or "BLIZZARD"
    local folder = CUSTOM_STYLES[style]
    if folder then
        local file = ROLE_MAP[role] or "dps"
        if conf.useMidnightIcons then file = file .. "_midnight" end
        return MEDIA_PREFIX .. folder .. "\\" .. file, 0, 1, 0, 1
    end
    local c = BLIZZARD_ROLE_COORDS[role] or BLIZZARD_ROLE_COORDS.DAMAGER
    return BLIZZARD_ROLE_TEX, c[1], c[2], c[3], c[4]
end

function GF.GetLeaderTexture(kind)
    local conf = GF.GetConf(kind)
    local style = conf.iconStyle or "BLIZZARD"
    local folder = CUSTOM_STYLES[style]
    if folder then
        local file = "leader"
        if conf.useMidnightIcons then file = file .. "_midnight" end
        return MEDIA_PREFIX .. folder .. "\\" .. file, 0, 1, 0, 1
    end
    return BLIZZARD_LEADER_TEX, 0, 1, 0, 1
end

function GF.GetAssistTexture(kind)
    local conf = GF.GetConf(kind)
    local style = conf.iconStyle or "BLIZZARD"
    local folder = CUSTOM_STYLES[style]
    if folder then
        local file = "assist"
        if conf.useMidnightIcons then file = file .. "_midnight" end
        return MEDIA_PREFIX .. folder .. "\\" .. file, 0, 1, 0, 1
    end
    return BLIZZARD_ASSIST_TEX, 0, 1, 0, 1
end

GF.ICON_STYLE_ITEMS = {
    { key = "BLIZZARD",      label = "Blizzard (Default)" },
    { key = "GLOSSY_ORBS",   label = "Glossy Orbs"        },
    { key = "DARK_EMBOSS",   label = "Dark Emboss"        },
    { key = "GLASS_PANELS",  label = "Glass Panels"       },
    { key = "NEON_OUTLINE",  label = "Neon Outline"       },
    { key = "RING_SYMBOLS",  label = "Ring Symbols"       },
    { key = "DOTS",          label = "Dots"               },
    { key = "SHAPES",        label = "Shapes"             },
    { key = "DIAMONDS",      label = "Diamonds"           },
    { key = "SQUARES",       label = "Squares"            },
}

------------------------------------------------------------------------
-- Expose for other modules
------------------------------------------------------------------------
_G.MSUF_GF_EnsureDB   = GF.EnsureDB
_G.MSUF_GF_GetConf     = GF.GetConf
_G.MSUF_GF_Val         = GF.Val
_G.MSUF_GF_GetHighlightVal = GF.GetHighlightVal
