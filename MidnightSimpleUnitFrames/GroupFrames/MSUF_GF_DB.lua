-- MSUF_GF_DB.lua — Group Frames DB defaults + config resolution
-- Phase 12: 3-slot health text, name color, name max chars, power per-role,
--           smooth fill toggle, hideInClientScene, target/aggro upgrades
-- Midnight 12.0 secret-safe, zero combat overhead
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

ns.GF = ns.GF or {}
local GF = ns.GF

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ResolveFontPathSafe = _G.MSUF_ResolveFontPath or function(path) return path end

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
local _GF_UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
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
    -- Masque skin for aura icons (requires Masque addon)
    masqueEnabled     = false,
    -- Group-frame aura/spell-indicator cooldowns default to the standard
    -- Blizzard-style remaining-time swipe. Enabling the layout option flips
    -- them into the elapsed-time "darkens on loss" style.
    cooldownSwipeDarkenOnLoss = false,
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
    hpBarAlpha        = 1,
    hpTextIgnoreAlpha = true,
    -- Border
    borderEnabled     = true,
    borderSize        = 1,
    borderR           = 0,
    borderG           = 0,
    borderB           = 0,
    borderA           = 1,
    -- Text: 3-slot system (replaces showHP boolean)
    showName          = true,
    showHPText        = true,
    -- Legacy key `showPower` is kept for saved profiles; new code treats
    -- it as the Group Frame power-text toggle, not as power-bar visibility.
    showPower         = false,
    showPowerText     = false,
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
    rangeFadeLayerMode = "frame", -- frame / health
    offlineAlpha      = 0.5,
    hideOfflineDelay  = 0,
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
    statusText        = true,
    statusTextSize    = 14,
    statusTextAnchor  = "CENTER",
    statusGhostText        = true,
    statusGhostTextSize    = 14,
    statusGhostTextAnchor  = "CENTER",
    statusAFKText          = true,
    statusAFKTextSize      = 14,
    statusAFKTextAnchor    = "CENTER",
    -- Status icon/text layers (frame level order: higher = on top)
    roleIconLayer     = 1,
    leaderIconLayer   = 2,
    assistIconLayer   = 2,
    raidMarkerLayer   = 3,
    readyCheckLayer   = 4,
    summonLayer       = 4,
    resurrectLayer    = 4,
    phaseLayer        = 3,
    statusTextLayer   = 7,
    statusGhostTextLayer = 7,
    statusAFKTextLayer   = 7,
    -- Text offsets
    nameOffsetX       = 0,
    nameOffsetY       = 0,
    hpOffsetX         = 0,
    hpOffsetY         = 0,
    powerOffsetX      = 0,
    powerOffsetY      = 0,
    statusOffsetX     = 0,
    statusOffsetY     = 0,
    statusGhostOffsetX = 0,
    statusGhostOffsetY = 0,
    statusAFKOffsetX   = 0,
    statusAFKOffsetY   = 0,
    -- Text layer (frame level relative to bar)
    nameTextLayer     = 5,
    textLayer         = 5,
    powerTextLayer    = 2,
    -- Alpha pipeline (matches main UF alpha fields)
    alphaSync            = false,
    alphaExcludeTextPortrait = false,
    alphaLayerMode       = 0,
    alphaInCombat        = 1,
    alphaOutOfCombat     = 1,
    alphaFGInCombat      = 1,
    alphaFGOutOfCombat   = 1,
    alphaBGInCombat      = 1,
    alphaBGOutOfCombat   = 1,
    alphaHPInCombat      = 1,
    alphaHPOutOfCombat   = 1,
    alphaPreserveHPColor = false,
    -- Health prediction overlays: NO defaults here — falls through to global Bars settings
    -- (absorbEnabled, healAbsorbEnabled, healPredEnabled are resolved at runtime)
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
    -- Dispel overlay (color wash on health bar when dispellable debuff active)
    dispelOverlayEnabled  = false,
    dispelOverlayStyle    = "FULL",   -- FULL / BOTTOM / TOP / LEFT / RIGHT
    dispelOverlayOnHealth = true,     -- true = clip to current health fill
    dispelOverlayAlpha    = 0.35,

    -- Debuff stripe (thin edge indicator for any debuff)
    debuffStripeEnabled   = false,
    debuffStripeEdge      = "BOTTOM", -- BOTTOM / TOP
    debuffStripeHeight    = 3,        -- pixels
    debuffStripeAlpha     = 0.60,
    debuffStripeColorR    = 0.80,
    debuffStripeColorG    = 0.20,
    debuffStripeColorB    = 0.20,
    -- Health fade (dim frames above HP threshold — healer focus)
    healthFadeEnabled     = false,
    healthFadeThreshold   = 95,    -- % HP above which frame is dimmed
    healthFadeAlpha       = 0.45,  -- alpha when above threshold
    -- Focus highlight (separate glow when unit is focus)
    hlFocusEnabled        = true,
    hlFocusColorR         = 0.50,
    hlFocusColorG         = 0.50,
    hlFocusColorB         = 1.00,
    hlFocusSize           = 2,
    hlFocusOffset         = 0,
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
    aurasEnabled      = true,
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
    -- Corner Indicators
    ciEnabled         = true,
    ciSize            = 8,
    ciAlpha           = 1.0,
    ciSlotTL          = "dispel",
    ciSlotTR          = "aggro",
    ciSlotBL          = "none",
    ciSlotBR          = "none",
    ciSlotC           = "none",
    -- Aggro slot color (matches highlight aggro border default = orange)
    ciAggroColorR     = 1.00,
    ciAggroColorG     = 0.55,
    ciAggroColorB     = 0.00,
    -- Custom-slot configs (per-slot table; nil = unset).
    -- Each: { spells = "1234,5678", mode = "present"|"missing",
    --         filter = "HELPFUL|PLAYER", r = 0.4, g = 1, b = 0.4 }
    ciCustomTL        = nil,
    ciCustomTR        = nil,
    ciCustomBL        = nil,
    ciCustomBR        = nil,
    ciCustomC         = nil,
    -- Grid layout
    unitsPerColumn    = 5,
    maxColumns        = 1,
    -- Role sort
    sortByRole        = false,
    roleOrder         = "TANK,HEALER,DAMAGER",
    separateMeleeRanged = false,
    playerFirstInRole   = false,
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
    RAID_DEFAULTS.showPowerText  = false
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

local MYTHIC_RAID_DEFAULTS = {}
do
    for k, v in pairs(RAID_DEFAULTS) do
        MYTHIC_RAID_DEFAULTS[k] = v
    end
end

GF.PARTY_DEFAULTS = PARTY_DEFAULTS
GF.RAID_DEFAULTS  = RAID_DEFAULTS
GF.MYTHIC_RAID_DEFAULTS = MYTHIC_RAID_DEFAULTS

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

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local function IsDefaultsConf(kind, conf)
    if kind == "raid" then return conf == RAID_DEFAULTS end
    if kind == "mythicraid" then return conf == MYTHIC_RAID_DEFAULTS end
    return conf == PARTY_DEFAULTS
end

------------------------------------------------------------------------
-- Group Frame Scaling
-- Scales the physical frame geometry first; render modules then use the
-- cached scale for fonts and icons. Keeping the math here prevents the
-- header, preview, mover, and child-scan paths from drifting apart.
------------------------------------------------------------------------
local SCALE_AUTO_DEFAULTS = {
    { max = 10, scale = 100 },  -- 1-10 players
    { max = 20, scale = 85  },  -- 11-20 players
    { max = 25, scale = 80  },  -- 21-25 players
    -- 26+ uses scaleOver25
}
local SCALE_OVER25_DEFAULT = 70

local function ClampScalePct(v, fallback)
    v = tonumber(v) or fallback or 100
    if v < 50 then v = 50 elseif v > 150 then v = 150 end
    return v
end

local function RoundScaled(v, scale)
    v = (tonumber(v) or 0) * (tonumber(scale) or 1)
    if v >= 0 then return math_floor(v + 0.5) end
    return -math_floor((-v) + 0.5)
end

function GF.ResolveFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return 1 end
    local mode = conf.frameScaleMode or "off"
    if mode == "off" then return 1 end
    if mode == "manual" then
        return ClampScalePct(conf.frameScaleManual, 100) / 100
    end

    local getNum = _G.GetNumGroupMembers
    local n = getNum and getNum() or 0
    local s10 = ClampScalePct(conf.scaleAt10,  SCALE_AUTO_DEFAULTS[1].scale)
    local s20 = ClampScalePct(conf.scaleAt20,  SCALE_AUTO_DEFAULTS[2].scale)
    local s25 = ClampScalePct(conf.scaleAt25,  SCALE_AUTO_DEFAULTS[3].scale)
    local s26 = ClampScalePct(conf.scaleOver25, SCALE_OVER25_DEFAULT)
    if n <= 10 then return s10 / 100 end
    if n <= 20 then return s20 / 100 end
    if n <= 25 then return s25 / 100 end
    return s26 / 100
end

function GF.ApplyFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return 1 end
    local s = GF.ResolveFrameScale(kind)
    if not IsDefaultsConf(kind, conf) then
        conf._resolvedFrameScale = s
    end
    return s
end

function GF.GetFrameScale(kind)
    return GF.ApplyFrameScale(kind)
end

function GF.ScaleValue(value, scale, minValue)
    local v = RoundScaled(value, scale)
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

function GF.ScaleFrameValue(kind, value, minValue)
    local conf = GF.GetConf(kind)
    local scale = (conf and conf._resolvedFrameScale) or GF.ApplyFrameScale(kind) or 1
    return GF.ScaleValue(value, scale, minValue)
end

function GF.GetScaledFrameMetrics(kind)
    local conf = GF.GetConf(kind)
    local isRaidLike = IsRaidLikeKind(kind)
    if not conf then
        return isRaidLike and 80 or 120, isRaidLike and 32 or 40, 1, 1
    end
    local scale = GF.ApplyFrameScale(kind)
    local w = GF.ScaleValue(tonumber(conf.width) or (isRaidLike and 80 or 120), scale, 1)
    local h = GF.ScaleValue(tonumber(conf.height) or (isRaidLike and 32 or 40), scale, 1)
    local sp = GF.ScaleValue(tonumber(conf.spacing) or 1, scale, 0)
    return w, h, sp, scale
end

function GF.GetScaledPowerHeight(kind)
    local conf = GF.GetConf(kind)
    local raw = tonumber(conf and conf.powerHeight) or (IsRaidLikeKind(kind) and 4 or 6)
    if raw <= 0 then return 0 end
    if not conf then return raw end
    local scale = conf._resolvedFrameScale or GF.ApplyFrameScale(kind) or 1
    return GF.ScaleValue(raw, scale, 1)
end

function GF.NormalizeGroupRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return "DAMAGER"
end

function GF.GetUnitGroupRole(unit)
    local role = unit and _GF_UnitGroupRolesAssigned and _GF_UnitGroupRolesAssigned(unit)
    return GF.NormalizeGroupRole(role)
end

function GF.ShouldShowPowerBarForRole(kind, role, conf)
    conf = conf or GF.GetConf(kind)
    if not conf then return false end
    local raw = tonumber(conf.powerHeight) or (IsRaidLikeKind(kind) and 4 or 6)
    if raw <= 0 then return false end

    role = GF.NormalizeGroupRole(role)
    if role == "TANK" then
        return conf.powerShowTank ~= false
    elseif role == "HEALER" then
        return conf.powerShowHealer ~= false
    end
    return conf.powerShowDamager ~= false
end

function GF.ShouldShowPowerBarForUnit(kind, unit, conf)
    return GF.ShouldShowPowerBarForRole(kind, GF.GetUnitGroupRole(unit), conf)
end

function GF.GetEffectivePowerHeight(kind, unit, role, conf)
    conf = conf or GF.GetConf(kind)
    if not GF.ShouldShowPowerBarForRole(kind, role or GF.GetUnitGroupRole(unit), conf) then
        return 0
    end
    return (GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (tonumber(conf and conf.powerHeight) or 0)
end

function GF.GetGridMetrics(kind, count)
    local conf = GF.GetConf(kind)
    local w, h, sp = GF.GetScaledFrameMetrics(kind)
    local growth = conf.growth or "DOWN"
    local upc = conf.unitsPerColumn or 5

    count = tonumber(count) or 0
    if count < 1 then count = (IsRaidLikeKind(kind) and 10 or 5) end

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
    if IsRaidLikeKind(kind) then
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
    return 5
end

local function MigrateGroupPositionToGridCenter(conf, kind)
    if not conf then return end
    if conf.positionMode == "GRID_CENTER_V1" then return end
    local dx, dy = GF.GetGridMetrics(kind, GetMigrationCount(kind, conf))
    conf.offsetX = (conf.offsetX or (IsRaidLikeKind(kind) and -500 or -400)) + dx
    conf.offsetY = (conf.offsetY or 0) + dy
    conf.positionMode = "GRID_CENTER_V1"
end

------------------------------------------------------------------------
-- Migration: showHP boolean → 3-slot text
------------------------------------------------------------------------
local function MigrateShowHPTo3Slot(conf)
    if not conf then return end
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
    if not conf then return end
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

-- Corner Indicators: migrate dropped categories ("boss", "missing") → "none".
-- These categories no longer work in 12.0 due to secret-tagged isRaid/spellId
-- on debuffs/buffs cast by other players. Replaced with "aggro" + "custom".
-- One-shot migration (idempotent via _ciMigratedV2 stamp).
local CI_DROPPED_CATEGORIES = { boss = true, missing = true }
local CI_CUSTOM_KEYS = { "ciCustomTL", "ciCustomTR", "ciCustomBL", "ciCustomBR", "ciCustomC" }

-- Always-run defensive sweep: ensure ciCustom* slots are either a table or nil.
-- A previous build may have stamped a non-table value (e.g. number, string)
-- into one of these keys; the new option UI indexes them as tables and would
-- crash on a number/string. Cheap to run every login.
local function CleanupCornerCustomTypes(conf)
    if not conf then return end
    for _, k in ipairs(CI_CUSTOM_KEYS) do
        local v = conf[k]
        if v ~= nil and type(v) ~= "table" then conf[k] = nil end
    end
end

local function MigrateCornerIndicators(conf)
    if not conf then return end
    if conf._ciMigratedV2 then return end
    local slotKeys = { "ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC" }
    for _, k in ipairs(slotKeys) do
        if CI_DROPPED_CATEGORIES[conf[k]] then conf[k] = "none" end
    end
    -- Drop legacy boss color keys (replaced by aggro color in CI v2 schema)
    conf.ciBossColorR = nil
    conf.ciBossColorG = nil
    conf.ciBossColorB = nil
    conf.ciMissingColorR = nil
    conf.ciMissingColorG = nil
    conf.ciMissingColorB = nil
    conf._ciMigratedV2 = true
end

local function RemoveGroupPetFrameConfig(conf)
    if type(conf) ~= "table" then return end
    conf.showPets = nil
    if conf.anchorToFrame == "pet" then
        conf.anchorToFrame = nil
    end
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

local GF_FONT_KEY_ALIASES = {
    ["Friz Quadrata TT"]        = "FRIZQT",
    ["Arial Narrow"]            = "ARIALN",
    ["Morpheus"]                = "MORPHEUS",
    ["Skurri"]                  = "SKURRI",
    ["Friz Quadrata (default)"] = "FRIZQT",
    ["Arial (default)"]         = "ARIALN",
    ["Morpheus (default)"]      = "MORPHEUS",
    ["Skurri (default)"]        = "SKURRI",
}

local function NormalizeFontField(conf)
    if type(conf) ~= "table" then return end
    local key = conf.fontKey
    if type(key) ~= "string" or key == "" then return end
    local normalize = _G.MSUF_NormalizeFontKey or function(k) return GF_FONT_KEY_ALIASES[k] or k end
    local normalized = normalize(key)
    if normalized ~= key then
        conf.fontKey = normalized
    end
end

function GF.EnsureDB()
    local db = _G.MSUF_DB
    if not db then return end
    local _partyFresh = type(db.gf_party) ~= "table"
    local _raidFresh  = type(db.gf_raid)  ~= "table"
    local _mythicFresh = type(db.gf_mythicraid) ~= "table"
    if _partyFresh then db.gf_party = {} end
    if _raidFresh  then db.gf_raid  = {} end
    if _mythicFresh then db.gf_mythicraid = {} end
    NormalizeFontField(db.gf_party)
    NormalizeFontField(db.gf_raid)
    NormalizeFontField(db.gf_mythicraid)
    MigrateShowHPTo3Slot(db.gf_party)
    MigrateShowHPTo3Slot(db.gf_raid)
    MigrateShowHPTo3Slot(db.gf_mythicraid)
    MigrateHighlightToUnified(db.gf_party)
    MigrateHighlightToUnified(db.gf_raid)
    MigrateHighlightToUnified(db.gf_mythicraid)
    -- Defensive: type-guard ciCustom* fields BEFORE the one-shot CI migration
    -- (which may already be stamped done from a previous build).
    CleanupCornerCustomTypes(db.gf_party)
    CleanupCornerCustomTypes(db.gf_raid)
    CleanupCornerCustomTypes(db.gf_mythicraid)
    MigrateCornerIndicators(db.gf_party)
    MigrateCornerIndicators(db.gf_raid)
    MigrateCornerIndicators(db.gf_mythicraid)
    RemoveGroupPetFrameConfig(db.gf_party)
    RemoveGroupPetFrameConfig(db.gf_raid)
    RemoveGroupPetFrameConfig(db.gf_mythicraid)
    applyDefaults(db.gf_party, PARTY_DEFAULTS)
    applyDefaults(db.gf_raid,  RAID_DEFAULTS)
    applyDefaults(db.gf_mythicraid, MYTHIC_RAID_DEFAULTS)
    MigrateGroupPositionToGridCenter(db.gf_party, "party")
    MigrateGroupPositionToGridCenter(db.gf_raid, "raid")
    MigrateGroupPositionToGridCenter(db.gf_mythicraid, "mythicraid")
    -- Migrate flat aura/private-aura keys → nested tables
    if GF.MigrateAuraConfig then
        GF.MigrateAuraConfig(db.gf_party, false)
        GF.MigrateAuraConfig(db.gf_raid, true)
        GF.MigrateAuraConfig(db.gf_mythicraid, true)
    end
    -- Ensure spell filter fields exist on each aura sub-group
    for _, conf in pairs({db.gf_party, db.gf_raid, db.gf_mythicraid}) do
        -- Migrate: remove legacy absorb/heal defaults that blocked global override
        if conf.absorbEnabled == true and not conf._absorbMigrated then
            conf.absorbEnabled = nil
            conf._absorbMigrated = true
        end
        if conf.healAbsorbEnabled == true and not conf._absorbMigrated then
            conf.healAbsorbEnabled = nil
        end
        if conf.healPredEnabled == true and not conf._healPredMigrated then
            conf.healPredEnabled = nil
            conf._healPredMigrated = true
        end
        -- Remove absorb keys that shadow general when hlOverride is off
        if not conf.hlOverride then
            conf.absorbEnabled = nil
            conf.absorbTextMode = nil
            conf.enableAbsorbBar = nil
        end
        if type(conf.auras) == "table" then
            for _, gk in pairs({"buff", "debuff", "externals"}) do
                local g = conf.auras[gk]
                if type(g) == "table" then
                    -- Migrate v3: old spellFilter/spellList → new filterToken/blacklistCats
                    if not g._filterMigV3 then
                        g._filterMigV3 = true
                        -- Convert old filterMode → new filterToken
                        if g.filterMode and not g.filterToken then
                            local fm = g.filterMode
                            if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
                                g.filterToken = (gk == "debuff") and "ALL" or "RAID"
                            elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
                                g.filterToken = fm
                            elseif fm == "NOT_PLAYER" then
                                g.filterToken = "ALL"
                            end
                        end
                        -- Convert old spellFilter+spellList → blacklistCats
                        if g.spellFilter == "BLACKLIST" and type(g.spellList) == "table" then
                            if not g.blacklistCats then g.blacklistCats = {} end
                            -- Check if old spellList contained Sated spells
                            if g.spellList[57723] or g.spellList[57724] or g.spellList[80354] then
                                g.blacklistCats.SATED = true
                            end
                            if g.spellList[26013] or g.spellList[71041] then
                                g.blacklistCats.DESERTER = true
                            end
                        end
                        -- Clean up legacy keys
                        g.spellFilter = nil
                        g.spellList   = nil
                        g.filterMode  = nil
                    end
                    -- Ensure new keys exist with defaults
                    if g.filterToken == nil then
                        g.filterToken = (gk == "debuff") and "ALL" or "RAID"
                    end
                    if type(g.blacklistCats) ~= "table" then
                        -- Apply sensible defaults from AuraFilter module
                        local AF = GF.AuraFilter or _G.MSUF_GF_AuraFilter
                        if AF then
                            local defs = (gk == "buff") and AF.DEFAULT_BLACKLIST_BUFF
                                      or (gk == "debuff") and AF.DEFAULT_BLACKLIST_DEBUFF
                                      or nil
                            if defs then
                                g.blacklistCats = {}
                                for k, v in pairs(defs) do g.blacklistCats[k] = v end
                            else
                                g.blacklistCats = {}
                            end
                        else
                            g.blacklistCats = {}
                        end
                    end
                end
            end
        end
    end
    -- Migration v2: force-enable auras + defensives (showstopper fix)
    for _, conf in pairs({db.gf_party, db.gf_raid, db.gf_mythicraid}) do
        if type(conf.auras) == "table" and not conf._auraMigV2 then
            conf._auraMigV2 = true
            if conf.auras.enabled == false or conf.auras.enabled == nil then
                conf.auras.enabled = true
            end
            local ext = conf.auras.externals
            if type(ext) == "table" and not ext.enabled then
                ext.enabled = true
            end
        end
    end
    -- Update cached conf references
    GF.InvalidateConfCache()

    -- Obsolete role-layout bootstrap flags from older builds.
    db._gfDefaultPresetApplied = nil
    GF._pendingDefaultPreset = nil

    if GF.SeedCurrentSpecSpellIndicatorDefaults then
        GF.SeedCurrentSpecSpellIndicatorDefaults()
    end
end

------------------------------------------------------------------------
-- Config resolution (cached — eliminates _G.MSUF_DB + type() per call)
------------------------------------------------------------------------
local _confParty, _confRaid, _confMythicRaid

function GF.IsMythicRaidContext()
    local inGroup = (IsInGroup and IsInGroup()) or false
    local inRaid = (IsInRaid and IsInRaid()) or false
    if not inGroup and not inRaid then return false end

    local raidDifficultyID = GetRaidDifficultyID and GetRaidDifficultyID() or nil
    if raidDifficultyID == 16 then return true end

    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" and difficultyID == 16 then
        return true
    end

    return false
end

function GF.GetLiveRaidKind()
    if GF.IsMythicRaidContext and GF.IsMythicRaidContext() then
        return "mythicraid"
    end
    return "raid"
end

function GF.GetConfigDBKey(kind)
    if kind == "raid" then return "gf_raid" end
    if kind == "mythicraid" then return "gf_mythicraid" end
    return "gf_party"
end

local function GetDefaultsTable(kind)
    if kind == "raid" then return RAID_DEFAULTS end
    if kind == "mythicraid" then return MYTHIC_RAID_DEFAULTS end
    return PARTY_DEFAULTS
end

function GF.GetConf(kind)
    local dbKey = GF.GetConfigDBKey(kind)
    if dbKey == "gf_mythicraid" then return _confMythicRaid or MYTHIC_RAID_DEFAULTS end
    if dbKey == "gf_raid" then return _confRaid or RAID_DEFAULTS end
    return _confParty or PARTY_DEFAULTS
end

--- Call after any DB mutation (EnsureDB, profile swap, options apply)
function GF.InvalidateConfCache()
    local db = _G.MSUF_DB
    if not db then
        _confParty, _confRaid, _confMythicRaid = nil, nil, nil
        return
    end
    _confParty = (type(db.gf_party) == "table" and db.gf_party) or nil
    _confRaid  = (type(db.gf_raid)  == "table" and db.gf_raid)  or nil
    _confMythicRaid = (type(db.gf_mythicraid) == "table" and db.gf_mythicraid) or nil
end

function GF.GetDefault(kind, key)
    return GetDefaultsTable(kind)[key]
end

local function ResetConfToDefaults(conf, defaults)
    if type(conf) ~= "table" or type(defaults) ~= "table" then return end
    for k in pairs(conf) do
        conf[k] = nil
    end
    for k, v in pairs(defaults) do
        conf[k] = (type(v) == "table" and GF._DeepCopyTable) and GF._DeepCopyTable(v) or v
    end
end

local function GetFactoryGroupFrameDefaults()
    local createProfile = (type(ns) == "table" and ns.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
    if type(createProfile) ~= "function" then return nil end

    local profile = createProfile()
    if type(profile) ~= "table" then return nil end

    local party = type(profile.gf_party) == "table" and profile.gf_party or nil
    local raid = type(profile.gf_raid) == "table" and profile.gf_raid or nil
    local mythicraid = type(profile.gf_mythicraid) == "table" and profile.gf_mythicraid or nil
    if party and raid and mythicraid then
        return party, raid, mythicraid
    end
    return nil
end

function GF.ResetAllToDefaults()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end

    db.gf_party = db.gf_party or {}
    db.gf_raid  = db.gf_raid or {}
    db.gf_mythicraid = db.gf_mythicraid or {}

    local partyDefaults, raidDefaults, mythicRaidDefaults = GetFactoryGroupFrameDefaults()
    ResetConfToDefaults(db.gf_party, partyDefaults or PARTY_DEFAULTS)
    ResetConfToDefaults(db.gf_raid, raidDefaults or RAID_DEFAULTS)
    ResetConfToDefaults(db.gf_mythicraid, mythicRaidDefaults or MYTHIC_RAID_DEFAULTS)

    GF.EnsureDB()

    if GF.RebuildAll then GF.RebuildAll() end
    if GF.RefreshVisuals then GF.RefreshVisuals() end

    return true
end

------------------------------------------------------------------------
-- Raid Layout Situations
-- Stores per-situation geometry overrides (Mythic / Normal-HC / Open World).
-- On situation change: save current → load target → RebuildAll.
-- Auto-detect via difficultyID on PLAYER_ENTERING_WORLD.
------------------------------------------------------------------------
local LAYOUT_GEO_KEYS = {
    "width", "height", "spacing", "growth",
    "unitsPerColumn", "maxColumns",
    "point", "anchorPoint", "offsetX", "offsetY",
}

local RAID_LAYOUT_SITUATIONS = {
    { key = "manual",    label = "Manual (no auto-switch)" },
    { key = "mythic",    label = "Mythic Raid / M+" },
    { key = "normal",    label = "Normal / Heroic Raid" },
    { key = "openworld", label = "Open World / Party" },
}
GF.RAID_LAYOUT_SITUATIONS = RAID_LAYOUT_SITUATIONS

--- Save current geometry to a situation slot
function GF.SaveRaidLayout(conf, situationKey)
    if not conf then return end
    if type(conf.raidLayouts) ~= "table" then conf.raidLayouts = {} end
    local slot = conf.raidLayouts[situationKey]
    if not slot then slot = {}; conf.raidLayouts[situationKey] = slot end
    for _, k in ipairs(LAYOUT_GEO_KEYS) do
        slot[k] = conf[k]
    end
end

--- Load geometry from a situation slot onto the main conf
function GF.LoadRaidLayout(conf, situationKey)
    if not conf then return end
    local layouts = conf.raidLayouts
    if type(layouts) ~= "table" then return end
    local slot = layouts[situationKey]
    if type(slot) ~= "table" then return end
    for _, k in ipairs(LAYOUT_GEO_KEYS) do
        if slot[k] ~= nil then conf[k] = slot[k] end
    end
end

--- Switch active situation: save current → load new → rebuild
function GF.SwitchRaidLayout(situationKey, kind)
    kind = kind or (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
    local conf = GF.GetConf(kind)
    if not conf then return false end
    local prev = conf._activeRaidLayout
    if prev == situationKey then return false end
    if prev and prev ~= situationKey then
        GF.SaveRaidLayout(conf, prev)
    end
    conf._activeRaidLayout = situationKey
    GF.LoadRaidLayout(conf, situationKey)
    GF.InvalidateConfCache()
    if GF.RebuildAll then GF.RebuildAll() end
    return true
end

--- Detect situation from instance difficulty
function GF.DetectRaidSituation()
    local _, _, difficultyID = GetInstanceInfo()
    if not difficultyID or difficultyID == 0 then return "openworld" end
    -- Mythic Raid = 16, Mythic+ = 8, Mythic Dungeon = 23
    if difficultyID == 16 or difficultyID == 8 or difficultyID == 23 then
        return "mythic"
    end
    -- Normal Raid = 14, Heroic Raid = 15, LFR = 17
    if difficultyID == 14 or difficultyID == 15 or difficultyID == 17 then
        return "normal"
    end
    -- Normal Dungeon = 1, Heroic Dungeon = 2, Timewalking = 24/33
    if difficultyID == 1 or difficultyID == 2 or difficultyID == 24 or difficultyID == 33 then
        return "normal"
    end
    return "openworld"
end

--- Auto-switch handler (called on PLAYER_ENTERING_WORLD)
function GF.AutoSwitchRaidLayout(kind)
    kind = kind or (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
    local conf = GF.GetConf(kind)
    if not conf then return false end
    local mode = conf.raidLayoutMode or "manual"
    if mode ~= "auto" then return false end
    local situation = GF.DetectRaidSituation()
    if situation ~= conf._activeRaidLayout then
        return GF.SwitchRaidLayout(situation, kind) == true
    end
    return false
end

--- Resolve a config value with fallback to default
function GF.Val(kind, key)
    local conf = GF.GetConf(kind)
    local v = conf[key]
    if v ~= nil then return v end
    return GetDefaultsTable(kind)[key]
end

function GF.IsHealPredictionEnabled(kind, conf)
    conf = conf or GF.GetConf(kind)
    if conf and conf.healPredEnabled ~= nil then
        return conf.healPredEnabled == true
    end
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
        if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    end
    return false
end

------------------------------------------------------------------------
-- Alpha resolution (GF-local equivalent of Core/MSUF_Alpha.lua)
------------------------------------------------------------------------
local function Clamp01(v, fallback)
    v = tonumber(v)
    if v == nil then v = fallback or 1 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

function GF.NormalizeAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" then
        return "background"
    end
    if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

function GF.GetAlphaKeys(conf, mode)
    mode = GF.NormalizeAlphaLayerMode(mode)
    if conf and conf.alphaExcludeTextPortrait == true then
        if mode == "background" then return "alphaBGInCombat", "alphaBGOutOfCombat" end
        if mode == "health" then return "alphaHPInCombat", "alphaHPOutOfCombat" end
        return "alphaFGInCombat", "alphaFGOutOfCombat"
    end
    return "alphaInCombat", "alphaOutOfCombat"
end

function GF.GetAlphaPair(conf, mode)
    if not conf then return 1, 1 end
    mode = GF.NormalizeAlphaLayerMode(mode or conf.alphaLayerMode)

    local aIn = Clamp01(conf.alphaInCombat, 1)
    local aOut = Clamp01(conf.alphaOutOfCombat, 1)
    if conf.alphaExcludeTextPortrait == true then
        if mode == "background" then
            aIn = Clamp01(conf.alphaBGInCombat, aIn)
            aOut = Clamp01(conf.alphaBGOutOfCombat, aOut)
        elseif mode == "health" then
            aIn = Clamp01(conf.alphaHPInCombat, Clamp01(conf.alphaFGInCombat, aIn))
            aOut = Clamp01(conf.alphaHPOutOfCombat, Clamp01(conf.alphaFGOutOfCombat, aOut))
        else
            aIn = Clamp01(conf.alphaFGInCombat, aIn)
            aOut = Clamp01(conf.alphaFGOutOfCombat, aOut)
        end
    end

    local sync = conf.alphaSyncBoth
    if sync == nil then sync = conf.alphaSync end
    if sync then aOut = aIn end
    return aIn, aOut
end

function GF.GetCurrentAlpha(conf, mode)
    local aIn, aOut = GF.GetAlphaPair(conf, mode)
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil and _G.InCombatLockdown then inCombat = _G.InCombatLockdown() end
    return (inCombat == true) and aIn or aOut
end

function GF.GetEffectiveFrameAlpha(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf then return 1 end
    if conf.alphaExcludeTextPortrait == true then return 1 end
    return GF.GetCurrentAlpha(conf, "foreground")
end

function GF.GetEffectiveHealthAlpha(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf then return 1 end
    if conf.alphaExcludeTextPortrait == true then
        local mode = GF.NormalizeAlphaLayerMode(conf.alphaLayerMode)
        if mode == "background" then
            local aIn = Clamp01(conf.alphaFGInCombat, Clamp01(conf.alphaInCombat, 1))
            local aOut = Clamp01(conf.alphaFGOutOfCombat, Clamp01(conf.alphaOutOfCombat, 1))
            local sync = conf.alphaSyncBoth
            if sync == nil then sync = conf.alphaSync end
            if sync then aOut = aIn end
            local inCombat = _G.MSUF_InCombat
            if inCombat == nil and _G.InCombatLockdown then inCombat = _G.InCombatLockdown() end
            return (inCombat == true) and aIn or aOut
        end
        return GF.GetCurrentAlpha(conf, mode)
    end
    return Clamp01(conf.hpBarAlpha, 1)
end

function GF.GetEffectivePowerAlpha(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf or conf.alphaExcludeTextPortrait ~= true then return 1 end
    local mode = GF.NormalizeAlphaLayerMode(conf.alphaLayerMode)
    if mode == "health" or mode == "background" then return 1 end
    return GF.GetCurrentAlpha(conf, "foreground")
end

function GF.GetEffectiveBackgroundAlpha(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf or conf.alphaExcludeTextPortrait ~= true then return 1 end
    return GF.GetCurrentAlpha(conf, "background")
end

--- Group Frame power text toggle with legacy-profile compatibility.
--- `showPower` was historically used by GF as the power-text toggle; keep
--- reading it when the explicit `showPowerText` key does not exist yet.
function GF.IsPowerTextEnabled(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf then return false end
    -- OR keeps old profiles/presets working even if only one of the two
    -- mirror keys exists or was written by older code. The setter below writes
    -- both keys, so explicit user toggles remain deterministic.
    return conf.showPowerText == true or conf.showPower == true
end

function GF.SetPowerTextEnabled(kind, enabled)
    local conf = GF.GetConf(kind)
    if not conf then return end
    local v = enabled and true or false
    conf.showPowerText = v
    conf.showPower = v -- legacy mirror so Edit Mode / old profiles stay in sync
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

--- Resolve outline thickness with scope override support.
--- GF-local (gf_party/gf_raid) can override bars.barOutlineThickness via hlOverride=true.
function GF.GetBarOutlineThickness(kind)
    local conf = GF.GetConf(kind)
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    local raw = nil
    if conf and conf.hlOverride and conf.barOutlineThickness ~= nil then
        raw = conf.barOutlineThickness
    elseif bars then
        raw = bars.barOutlineThickness
    end
    local t = tonumber(raw)
    if type(t) ~= "number" then t = 2 end
    t = math_floor(t + 0.5)
    if t < 0 then t = 0 elseif t > 6 then t = 6 end
    return t
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
--- Check if GF scope has font override active
function GF.HasFontOverride(kind)
    local conf = GF.GetConf(kind)
    return conf.fontOverride == true
end

function GF.ResolveFontPath(kind)
    local conf = GF.GetConf(kind)
    -- When override active: use GF-local fontKey
    if conf.fontOverride then
        local key = conf.fontKey
        if key and key ~= "" then
            local fn = _G.MSUF_GetFontPathForKey or (ns and ns.MSUF_GetFontPathForKey)
            if type(fn) == "function" then
                local p = fn(key)
                if p then return ResolveFontPathSafe(p, conf.nameFontSize or 12, GF.ResolveFontFlags and GF.ResolveFontFlags(kind) or "") end
            end
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local raw = _G.MSUF_GetRawLSMFontPath
                local p = type(raw) == "function" and raw(LSM, key) or nil
                if not p and type(LSM.HashTable) == "function" then
                    local fonts = LSM:HashTable("font")
                    p = fonts and fonts[key]
                end
                if p then return ResolveFontPathSafe(p, conf.nameFontSize or 12, GF.ResolveFontFlags and GF.ResolveFontFlags(kind) or "") end
            end
        end
    end
    -- Fallback: global font (shared with UF)
    local db = _G.MSUF_DB
    local gKey = db and db.general and db.general.fontKey
    if gKey and gKey ~= "" then
        local pathForKey = _G.MSUF_GetFontPathForKey or (ns and ns.MSUF_GetFontPathForKey)
        if type(pathForKey) == "function" then return ResolveFontPathSafe(pathForKey(gKey), 12, "") end
        local fn = _G.MSUF_GetFontPath or (ns and ns.MSUF_GetFontPath)
        if type(fn) == "function" then return ResolveFontPathSafe(fn(), 12, "") end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local raw = _G.MSUF_GetRawLSMFontPath
            local p = type(raw) == "function" and raw(LSM, gKey) or nil
            if not p and type(LSM.HashTable) == "function" then
                local fonts = LSM:HashTable("font")
                p = fonts and fonts[gKey]
            end
            if p then return ResolveFontPathSafe(p, 12, "") end
        end
    end
    local fn = ns.Castbars and ns.Castbars._GetFontPath
    if type(fn) == "function" then return ResolveFontPathSafe(fn(), 12, "") end
    return ResolveFontPathSafe("Fonts\\FRIZQT__.TTF", 12, "")
end

--- Resolve font outline flags
function GF.ResolveFontFlags(kind)
    local conf = GF.GetConf(kind)
    -- When override active: use GF-local fontOutline
    if conf.fontOverride then
        local v = conf.fontOutline
        if v ~= nil then
            if v == "" or v == "NONE" then return "" end
            if v == "OUTLINE" or v == "THICKOUTLINE" then return v end
        end
    end
    -- Fallback: derive from global boldText / noOutline
    local db = _G.MSUF_DB
    local gen = db and db.general
    if gen then
        if gen.boldText then return "THICKOUTLINE" end
        if gen.noOutline then return "" end
    end
    local fn = ns.Castbars and ns.Castbars._GetFontFlags
    if type(fn) == "function" then return fn() end
    return "OUTLINE"
end

--- Resolve font color (base color for non-name text)
function GF.ResolveFontColor(kind)
    local conf = GF.GetConf(kind)
    -- Override with local color only when override + useGlobalFontColor=false
    if conf.fontOverride and conf.useGlobalFontColor == false then
        if conf.fontR then
            return conf.fontR, conf.fontG or 1, conf.fontB or 1
        end
    end
    -- Fallback: global font color (shared with UF)
    local fn = ns.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then return fn() end
    return 1, 1, 1
end

--- Resolve name text color (CLASS / CUSTOM / DEFAULT fallback to font color)
function GF.ResolveNameColor(kind, classToken)
    local conf = GF.GetConf(kind)

    -- When override active: use GF-local nameColorMode
    if conf.fontOverride then
        local mode = conf.nameColorMode or "DEFAULT"
        if mode == "CLASS" and classToken then
            local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
            if type(fastClass) == "function" then
                local r, g, b = fastClass(classToken)
                if r then return r, g, b end
            end
            local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
            if cc then return cc.r, cc.g, cc.b end
        end
        if mode == "CUSTOM" then
            return conf.nameColorR or 1, conf.nameColorG or 1, conf.nameColorB or 1
        end
        return GF.ResolveFontColor(kind)
    end

    -- No override: use global nameClassColor boolean (shared with UF)
    local db = _G.MSUF_DB
    local gen = db and db.general
    if gen and gen.nameClassColor and classToken then
        local fastClass = _G.MSUF_UFCore_GetClassBarColorFast
        if type(fastClass) == "function" then
            local r, g, b = fastClass(classToken)
            if r then return r, g, b end
        end
        local cc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
        if cc then return cc.r, cc.g, cc.b end
    end

    -- DEFAULT: use global font color
    return GF.ResolveFontColor(kind)
end

--- Resolve name truncation (respects fontOverride)
--- Returns maxChars, noEllipsis
function GF.ResolveNameTruncation(kind)
    local conf = GF.GetConf(kind)
    if conf.fontOverride then
        return conf.nameMaxChars or 0, conf.nameNoEllipsis or false
    end
    -- No override: use defaults (unlimited)
    return 0, false
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

-- Module-level cache for hot-path text formatting options
-- Avoids 3 table lookups per _GF_GetGlobalTextOpt call (9+ calls per UNIT_HEALTH)
local _cachedHidePct
local _cachedUseShort
local function _GF_GetHidePct()
    if _cachedHidePct == nil then _cachedHidePct = _GF_GetGlobalTextOpt("hidePercentSymbol", false) and true or false end
    return _cachedHidePct
end
local function _GF_GetUseShort()
    if _cachedUseShort == nil then _cachedUseShort = _GF_GetGlobalTextOpt("useShortNumbers", true) and true or false end
    return _cachedUseShort
end
function GF.InvalidateTextFormatCache()
    _cachedHidePct = nil
    _cachedUseShort = nil
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
    local useShort = _GF_GetUseShort()
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
        if _GF_CSU_Round then
            return _GF_CSU_Round(pctVal) .. pctSuffix
        end
        return nil
    end
    local p = tonumber(pctVal)
    if not p then return nil end
    return math_floor(p + 0.5) .. pctSuffix
end

------------------------------------------------------------------------
-- Core mode formatter (shared by health + power)
-- All inputs may be secret strings (from _GF_Abbrev) or normal strings.
-- String concat ".." on secret strings produces a secret string.
------------------------------------------------------------------------
local function _GF_FormatByMode(mode, sCur, sMax, delim, pctStr, missingVal)
    if mode == "PERCENT"  then return pctStr or "" end
    if mode == "CURRENT"  then return sCur end
    if mode == "MAX"      then return sMax end

    if mode == "DEFICIT" then
        if missingVal == nil then return "" end
        local iss = _GF_issecretvalue
        if iss and iss(missingVal) then
            return "-" .. _GF_Abbrev(missingVal)
        end
        local m = tonumber(missingVal) or 0
        if m <= 0 then return "" end
        return "-" .. _GF_Abbrev(m)
    end

    if mode == "CURMAX"   then return sCur .. delim .. sMax end
    if mode == "MAXCUR"   then return sMax .. delim .. sCur end

    -- All remaining modes need percent
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
    local hidePct = _GF_GetHidePct()
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
    -- UTF-8 safe: count characters, not bytes
    -- Each UTF-8 char starts with a byte that's NOT a continuation byte (10xxxxxx)
    local charCount = 0
    local bytePos = 1
    local nameLen = #name
    while bytePos <= nameLen and charCount < maxChars do
        charCount = charCount + 1
        local b = string.byte(name, bytePos)
        if b < 128 then
            bytePos = bytePos + 1       -- ASCII: 1 byte
        elseif b < 224 then
            bytePos = bytePos + 2       -- 2-byte (Cyrillic, Latin Extended)
        elseif b < 240 then
            bytePos = bytePos + 3       -- 3-byte (CJK, etc.)
        else
            bytePos = bytePos + 4       -- 4-byte (Emoji, rare)
        end
    end
    if bytePos > nameLen then return name end  -- name fits
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

------------------------------------------------------------------------
-- FormatPowerText(mode, pw, pwMax, delimiter [, unit])
--   Same modes as health text. Secret-safe via C-side abbreviators.
------------------------------------------------------------------------
function GF.FormatPowerText(mode, pw, pwMax, delimiter, unit)
    if not mode or mode == "NONE" then return "" end

    local delim = delimiter or " / "
    local hidePct = _GF_GetHidePct()
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
function GF.HasActivePowerTextSlot(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not (GF.IsPowerTextEnabled and GF.IsPowerTextEnabled(kind, conf)) then return false end
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
_G.MSUF_GF_InvalidateConfCache = GF.InvalidateConfCache
_G.MSUF_GF_ResetAllToDefaults = GF.ResetAllToDefaults

------------------------------------------------------------------------
-- Shared table helpers
------------------------------------------------------------------------
function GF._DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = GF._DeepCopyTable(v)
    end
    return dst
end

------------------------------------------------------------------------
-- Spell Indicator first-load defaults
--
-- Older builds seeded healer Spell Indicators as a side effect of applying a
-- full role layout. Keep that behavior focused:
-- the first time a profile sees a supported player spec, copy that spec's
-- Spell Indicator defaults into SavedVariables and enable SI for that scope.
-- From then on the saved config is the source of truth.
------------------------------------------------------------------------
local GF_SI_KINDS = { "party", "raid", "mythicraid" }
local GF_SI_SEED_VERSION = 1

local function NormalizeSpellIndicatorConfig(conf)
    if type(conf) ~= "table" then return nil, false end
    local changed = false
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, _autoSeededSpecs = {} }
        return conf.spellIndicators, true
    end

    local si = conf.spellIndicators
    if si.spec == nil or si.spec == "" then
        si.spec = "auto"
        changed = true
    end
    if type(si.specs) ~= "table" then
        si.specs = {}
        changed = true
    end
    if si.layer == nil then
        si.layer = 9
        changed = true
    end
    if type(si._autoSeededSpecs) ~= "table" then
        si._autoSeededSpecs = {}
        changed = true
    end
    return si, changed
end

local function GetSpellIndicatorModule()
    return GF.SpellIndicators or _G.MSUF_GF_SpellIndicators
end

local function GetCurrentSpellIndicatorSpecKey()
    local SI = GetSpellIndicatorModule()
    if SI and type(SI.GetPlayerSpec) == "function" then
        local specKey = SI.GetPlayerSpec()
        if specKey then return specKey end
    end

    local _, classToken
    if UnitClass then _, classToken = UnitClass("player") end
    local specIdx = GetSpecialization and GetSpecialization() or nil
    if not (SI and SI.SpecMap and classToken and specIdx) then return nil end
    return SI.SpecMap[classToken .. "_" .. specIdx]
end

local function CopyMissingSpecDefaults(siCfg, specKey)
    local SI = GetSpellIndicatorModule()
    local defaults = SI and SI.SpecDefaults and SI.SpecDefaults[specKey]
    if not (siCfg and specKey and defaults) then return false end

    if type(SI.EnsureSpecConfig) == "function" then
        SI.EnsureSpecConfig(siCfg, specKey)
        return true
    end

    siCfg.specs = siCfg.specs or {}
    local specCfg = siCfg.specs[specKey]
    if type(specCfg) ~= "table" then
        specCfg = {}
        siCfg.specs[specKey] = specCfg
    end

    for auraName, def in pairs(defaults) do
        local entry = specCfg[auraName]
        if type(entry) ~= "table" then
            entry = GF._DeepCopyTable(def)
            if entry.onlyOwn == nil then entry.onlyOwn = true end
            specCfg[auraName] = entry
        else
            if entry.placed == nil and def.placed ~= nil then
                entry.placed = GF._DeepCopyTable(def.placed)
            end
            if entry.frame == nil and def.frame ~= nil then
                entry.frame = GF._DeepCopyTable(def.frame)
            end
            if entry.onlyOwn == nil then
                entry.onlyOwn = (def.onlyOwn ~= false)
            end
        end
    end
    return true
end

function GF.SeedSpellIndicatorDefaultsForSpec(specKey)
    local SI = GetSpellIndicatorModule()
    if not (SI and SI.SpecDefaults and SI.SpecDefaults[specKey]) then return false end

    local changed = false
    for i = 1, #GF_SI_KINDS do
        local kind = GF_SI_KINDS[i]
        local conf = GF.GetConf and GF.GetConf(kind) or nil
        if type(conf) == "table" and not IsDefaultsConf(kind, conf) then
            local si, normalized = NormalizeSpellIndicatorConfig(conf)
            changed = normalized or changed
            if si then
                local stamps = si._autoSeededSpecs
                if not stamps[specKey] then
                    CopyMissingSpecDefaults(si, specKey)

                    if si.enabled ~= true then
                        si.enabled = true
                    end
                    if si.spec == nil or si.spec == "" then
                        si.spec = "auto"
                    elseif si.spec == "multi" then
                        if type(si.multiSpecs) ~= "table" then si.multiSpecs = {} end
                        if not next(si.multiSpecs) then si.multiSpecs[specKey] = true end
                    end

                    stamps[specKey] = GF_SI_SEED_VERSION
                    si._autoSeedVersion = GF_SI_SEED_VERSION
                    changed = true
                end
            end
        end
    end

    if changed then
        if GF.MarkAllDirty then GF.MarkAllDirty(GF.DIRTY_AURAS or GF.DIRTY_ALL or 0x3F) end
        if GF.RefreshVisuals and not (InCombatLockdown and InCombatLockdown()) then GF.RefreshVisuals() end
        if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
        if GF._RequestOptionsResync then GF._RequestOptionsResync() end
    end
    return changed
end

function GF.SeedCurrentSpecSpellIndicatorDefaults()
    local specKey = GetCurrentSpellIndicatorSpecKey()
    if not specKey then return false end
    return GF.SeedSpellIndicatorDefaultsForSpec(specKey)
end

_G.MSUF_GF_SeedSpellIndicatorDefaultsForSpec = GF.SeedSpellIndicatorDefaultsForSpec
_G.MSUF_GF_SeedCurrentSpecSpellIndicatorDefaults = GF.SeedCurrentSpecSpellIndicatorDefaults

-- Keep first-load SI defaults in sync with the player's actual spec. This is
-- intentionally independent from group-frame size, alpha, aura, and role layout
-- defaults so those can evolve without maintaining role layout snapshots.
do
    local seedFrame = CreateFrame("Frame")
    local queued = false
    local function QueueSeed()
        if queued then return end
        queued = true
        local function Run()
            queued = false
            if GF.EnsureDB then GF.EnsureDB() end
            if GF.SeedCurrentSpecSpellIndicatorDefaults then
                GF.SeedCurrentSpecSpellIndicatorDefaults()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
    end

    seedFrame:RegisterEvent("PLAYER_LOGIN")
    seedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    seedFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    seedFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    seedFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    seedFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    seedFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
        QueueSeed()
    end)
end
