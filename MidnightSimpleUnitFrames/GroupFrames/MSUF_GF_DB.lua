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
    -- Pet frames are not shipped yet; keep default disabled until backend exists.
    showPets          = false,
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
    -- Status icon layers (draw order: higher = on top)
    roleIconLayer     = 1,
    leaderIconLayer   = 2,
    assistIconLayer   = 2,
    raidMarkerLayer   = 3,
    readyCheckLayer   = 4,
    summonLayer       = 4,
    resurrectLayer    = 4,
    phaseLayer        = 3,
    -- Text offsets
    nameOffsetX       = 0,
    nameOffsetY       = 0,
    hpOffsetX         = 0,
    hpOffsetY         = 0,
    powerOffsetX      = 0,
    powerOffsetY      = 0,
    statusOffsetX     = 0,
    statusOffsetY     = 0,
    -- Text layer (frame level relative to bar)
    textLayer         = 5,
    powerTextLayer    = 2,
    -- Alpha pipeline (matches main UF alpha fields)
    alphaInCombat        = 1,
    alphaOutOfCombat     = 1,
    alphaFGInCombat      = 1,
    alphaFGOutOfCombat   = 1,
    alphaBGInCombat      = 1,
    alphaBGOutOfCombat   = 1,
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
    -- Cutaway health (red fadeout showing health loss)
    cutawayEnabled        = true,
    cutawayFadeTime       = 0.4,   -- seconds before cutaway fades
    cutawayColorR         = 0.70,
    cutawayColorG         = 0.10,
    cutawayColorB         = 0.10,
    cutawayColorA         = 0.75,
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
    ciSlotTR          = "boss",
    ciSlotBL          = "none",
    ciSlotBR          = "none",
    ciSlotC           = "none",
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
    if count < 1 then count = (kind == "raid" and 10 or 5) end

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
    return 5
end

local function MigrateGroupPositionToGridCenter(conf, kind)
    if not conf then return end
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
    local _partyFresh = type(db.gf_party) ~= "table"
    local _raidFresh  = type(db.gf_raid)  ~= "table"
    if _partyFresh then db.gf_party = {} end
    if _raidFresh  then db.gf_raid  = {} end
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
    -- Ensure spell filter fields exist on each aura sub-group
    for _, conf in pairs({db.gf_party, db.gf_raid}) do
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
    for _, conf in pairs({db.gf_party, db.gf_raid}) do
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
    -- Schedule default preset apply on first-ever setup
    if (_partyFresh or _raidFresh) and not db._gfDefaultPresetApplied then
        GF._pendingDefaultPreset = true
    end
    -- Update cached conf references
    GF.InvalidateConfCache()
end

------------------------------------------------------------------------
-- Config resolution (cached — eliminates _G.MSUF_DB + type() per call)
------------------------------------------------------------------------
local _confParty, _confRaid

function GF.GetConf(kind)
    if kind == "raid" then return _confRaid or RAID_DEFAULTS end
    return _confParty or PARTY_DEFAULTS
end

--- Call after any DB mutation (EnsureDB, profile swap, options apply)
function GF.InvalidateConfCache()
    local db = _G.MSUF_DB
    if not db then
        _confParty, _confRaid = nil, nil
        return
    end
    _confParty = (type(db.gf_party) == "table" and db.gf_party) or nil
    _confRaid  = (type(db.gf_raid)  == "table" and db.gf_raid)  or nil
end

function GF.GetDefault(kind, key)
    if kind == "raid" then return RAID_DEFAULTS[key] end
    return PARTY_DEFAULTS[key]
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

function GF.ResetAllToDefaults()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return false end

    db.gf_party = db.gf_party or {}
    db.gf_raid  = db.gf_raid or {}

    ResetConfToDefaults(db.gf_party, PARTY_DEFAULTS)
    ResetConfToDefaults(db.gf_raid, RAID_DEFAULTS)

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
function GF.SwitchRaidLayout(situationKey)
    local conf = GF.GetConf("raid")
    if not conf then return end
    local prev = conf._activeRaidLayout
    if prev and prev ~= situationKey then
        GF.SaveRaidLayout(conf, prev)
    end
    conf._activeRaidLayout = situationKey
    GF.LoadRaidLayout(conf, situationKey)
    GF.InvalidateConfCache()
    if GF.RebuildAll then GF.RebuildAll() end
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
function GF.AutoSwitchRaidLayout()
    local conf = GF.GetConf("raid")
    if not conf then return end
    local mode = conf.raidLayoutMode or "manual"
    if mode ~= "auto" then return end
    local situation = GF.DetectRaidSituation()
    if situation ~= conf._activeRaidLayout then
        GF.SwitchRaidLayout(situation)
    end
end

------------------------------------------------------------------------
-- Group Frame Scaling
-- Scales entire frame (geometry + fonts + icons) based on group size.
-- Mode: "off" / "auto" / "manual"
-- Auto thresholds: 1-15 = 100%, 16-25 = 85%, 26-40 = 70%
-- Manual: user-defined 50-150%
-- Stored as conf._resolvedFrameScale (set during SetupHeader, read by Render)
------------------------------------------------------------------------
local SCALE_AUTO_DEFAULTS = {
    { max = 10, scale = 100 },  -- 1-10 players
    { max = 20, scale = 85  },  -- 11-20 players
    { max = 25, scale = 80  },  -- 21-25 players
    -- 26+ uses scaleOver25
}
local SCALE_OVER25_DEFAULT = 70

function GF.ResolveFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return 1 end
    local mode = conf.frameScaleMode or "off"
    if mode == "off" then return 1 end
    if mode == "manual" then
        return (conf.frameScaleManual or 100) / 100
    end
    -- Auto: configurable breakpoints
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local s10  = conf.scaleAt10  or SCALE_AUTO_DEFAULTS[1].scale
    local s20  = conf.scaleAt20  or SCALE_AUTO_DEFAULTS[2].scale
    local s25  = conf.scaleAt25  or SCALE_AUTO_DEFAULTS[3].scale
    local s26  = conf.scaleOver25 or SCALE_OVER25_DEFAULT
    if n <= 10 then return s10 / 100 end
    if n <= 20 then return s20 / 100 end
    if n <= 25 then return s25 / 100 end
    return s26 / 100
end

--- Apply resolved scale to conf cache (called before header setup)
function GF.ApplyFrameScale(kind)
    local conf = GF.GetConf(kind)
    if not conf then return end
    conf._resolvedFrameScale = GF.ResolveFrameScale(kind)
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
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local p = LSM:Fetch("font", key, true)
                if p then return p end
            end
        end
    end
    -- Fallback: global font (shared with UF)
    local db = _G.MSUF_DB
    local gKey = db and db.general and db.general.fontKey
    if gKey and gKey ~= "" then
        local fn = _G.MSUF_GetFontPath or (ns and ns.MSUF_GetFontPath)
        if type(fn) == "function" then return fn() end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local p = LSM:Fetch("font", gKey, true)
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
_G.MSUF_GF_InvalidateConfCache = GF.InvalidateConfCache
_G.MSUF_GF_ResetAllToDefaults = GF.ResetAllToDefaults

------------------------------------------------------------------------
-- Role Presets: cutting-edge configs per role/healer spec.
-- Applied via GF.ApplyPreset(kind, presetKey).
-- Each preset is a partial config overlay — unset keys keep current value.
------------------------------------------------------------------------
GF.PRESETS = {}

-- Deep copy utility (exported for presets + copy system)
function GF._DeepCopyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = GF._DeepCopyTable(v) end
    return dst
end

local function _MergePreset(base, override)
    local merged = {}
    for k, v in pairs(base) do
        merged[k] = (type(v) == "table") and GF._DeepCopyTable(v) or v
    end
    for k, v in pairs(override) do
        if type(v) == "table" and type(merged[k]) == "table" then
            for sk, sv in pairs(v) do merged[k][sk] = (type(sv) == "table") and GF._DeepCopyTable(sv) or sv end
        else
            merged[k] = (type(v) == "table") and GF._DeepCopyTable(v) or v
        end
    end
    return merged
end

-- ══════════════════════════════════════════════════════════════════════
-- DPS: Minimal, zero clutter. Debuffs, private auras, social icons.
-- ══════════════════════════════════════════════════════════════════════
GF.PRESETS.DPS = {
    label = "|cffff4444DPS|r",
    desc  = "Compact: debuffs, private auras, social icons. No HP text, no power bar.",
    conf  = {
        width = 80, height = 28, spacing = 1,
        showName = true, nameFontSize = 9, nameAnchor = "LEFT",
        nameOffsetX = 2, nameOffsetY = 2,
        nameMaxChars = 7, nameNoEllipsis = true,
        textLeft = "NONE", textCenter = "NONE", textRight = "NONE",
        hpFontSize = 10,
        showPower = false, powerHeight = 0,
        healthFadeEnabled = false,
        debuffStripeEnabled = false,
        rangeFadeEnabled = true, rangeFadeAlpha = 0.35,
        aggroEnabled = true, dispelEnabled = true, targetIndicator = true,
        roleIcon = true, roleIconSize = 8,
        roleIconAnchor = "BOTTOMLEFT", roleIconX = 0, roleIconY = 0,
        raidMarker = true, raidMarkerSize = 12,
        raidMarkerAnchor = "TOPLEFT", raidMarkerX = 0, raidMarkerY = 0,
        leaderIcon = true, leaderIconSize = 10,
        leaderIconAnchor = "TOPRIGHT", leaderIconX = 0, leaderIconY = 0,
        assistIcon = true, assistIconSize = 10,
        assistIconAnchor = "TOPRIGHT", assistIconX = 12, assistIconY = 0,
        readyCheckIcon = true, readyCheckSize = 20,
        readyCheckAnchor = "CENTER", readyCheckX = 0, readyCheckY = 0,
        resurrectIcon = true, resurrectIconSize = 18,
        resurrectAnchor = "CENTER", resurrectX = 0, resurrectY = 0,
        summonIcon = true, summonIconSize = 18,
        summonAnchor = "CENTER", summonX = 0, summonY = 0,
        phaseIcon = true, phaseIconSize = 12,
        phaseAnchor = "TOPLEFT", phaseX = 0, phaseY = -14,
        ciEnabled = true, ciAlpha = 0.9,
        ciSlotTL = "dispel", ciSlotTR = "boss", ciSlotBL = "none", ciSlotBR = "none", ciSlotC = "none",
        auras = {
            enabled = true,
            buff = { enabled = false },
            debuff = {
                enabled = true, maxIcons = 3, iconSize = 13, spacing = 1,
                anchor = "RIGHT", x = 2, y = 0, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = {
                    SATED = true, DESERTER = true, SKYRIDING = true,
                    COOLDOWNS = true, ROGUE_POISONS = true,
                    SHAMAN_IMBUE = true, SELF_BUFFS = true,
                },
            },
            externals = { enabled = false },
        },
        -- Private auras (bottom-right inside frame, max 2, growing left)
        privateAuras = {
            enabled = true, max = 2, size = 13,
            anchor = "BOTTOMRIGHT", direction = "LEFT",
            x = 0, y = 0,
            showCountdown = true, showNumbers = false,
            layer = 8,
                    -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
            -- Replaces the old DF-drawn frame-border overlay.
            containerOverlay = {
                enabled = false,
                showIcons = true,
                dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
                gradientDir = "default",         -- sweep direction
            },
},
        spellIndicators = { enabled = false },
    },
}
GF.PRESETS.DPS.party = {
    width = 110, height = 36, spacing = 2,
    nameFontSize = 12, nameMaxChars = 10,
    raidMarkerSize = 14, readyCheckSize = 22,
    auras = {
        enabled = true,
        buff = { enabled = false },
        debuff = {
            enabled = true, maxIcons = 3, iconSize = 14, spacing = 1,
            anchor = "RIGHT", x = 2, y = 0, growth = "RIGHT",
            showCooldown = true, showStacks = true,
            filterToken = "ALL",
            blacklistCats = {
                SATED = true, DESERTER = true, SKYRIDING = true,
                COOLDOWNS = true, ROGUE_POISONS = true,
                SHAMAN_IMBUE = true, SELF_BUFFS = true,
            },
        },
        externals = { enabled = false },
    },
    privateAuras = {
        enabled = true, max = 2, size = 15,
        anchor = "BOTTOMRIGHT", direction = "LEFT",
        x = 0, y = 0, showCountdown = true, showNumbers = false, layer = 8,
            -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
        -- Replaces the old DF-drawn frame-border overlay.
        containerOverlay = {
            enabled = false,
            showIcons = true,
            dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
            gradientDir = "default",         -- sweep direction
        },
},
}

-- ══════════════════════════════════════════════════════════════════════
-- TANK: Full situational awareness. Deficit HP, power bar, debuffs,
-- externals (survival CDs from others), private defensives.
-- healthFade OFF — tanks always need full visibility of all frames.
-- ══════════════════════════════════════════════════════════════════════
GF.PRESETS.TANK = {
    label = "|cff5599ffTank|r",
    desc  = "Deficit HP, power bar, 4 debuffs, 3 externals, private auras. Full aggro awareness.",
    conf  = {
        width = 110, height = 40, spacing = 2,
        showName = true, nameFontSize = 10, nameAnchor = "LEFT",
        nameOffsetX = 2, nameOffsetY = 4,
        nameMaxChars = 8, nameNoEllipsis = true,
        textLeft = "NONE", textCenter = "DEFICIT", textRight = "NONE",
        hpFontSize = 10,
        showPower = true, powerHeight = 4,
        rangeFadeEnabled = true, rangeFadeAlpha = 0.30,
        aggroEnabled = true, dispelEnabled = true, targetIndicator = true,
        healthFadeEnabled = false,
        debuffStripeEnabled = true, debuffStripeHeight = 3, debuffStripeEdge = "BOTTOM",
        debuffStripeAlpha = 0.70, debuffStripeColorR = 0.90, debuffStripeColorG = 0.20, debuffStripeColorB = 0.20,
        roleIcon = true, roleIconSize = 10,
        roleIconAnchor = "BOTTOMLEFT", roleIconX = 0, roleIconY = 0,
        raidMarker = true, raidMarkerSize = 14,
        raidMarkerAnchor = "TOPLEFT", raidMarkerX = 0, raidMarkerY = 0,
        leaderIcon = true, leaderIconSize = 10,
        leaderIconAnchor = "TOPRIGHT", leaderIconX = 0, leaderIconY = 0,
        assistIcon = true, assistIconSize = 10,
        assistIconAnchor = "TOPRIGHT", assistIconX = 12, assistIconY = 0,
        readyCheckIcon = true, readyCheckSize = 20,
        readyCheckAnchor = "CENTER", readyCheckX = 0, readyCheckY = 0,
        resurrectIcon = true, resurrectIconSize = 18,
        resurrectAnchor = "CENTER", resurrectX = 0, resurrectY = 0,
        summonIcon = true, summonIconSize = 18,
        summonAnchor = "CENTER", summonX = 0, summonY = 0,
        phaseIcon = true, phaseIconSize = 12,
        phaseAnchor = "TOPLEFT", phaseX = 0, phaseY = -14,
        ciEnabled = true, ciAlpha = 0.9,
        ciSlotTL = "dispel", ciSlotTR = "boss", ciSlotBL = "none", ciSlotBR = "none", ciSlotC = "none",
        auras = {
            enabled = true,
            buff = { enabled = false },
            debuff = {
                enabled = true, maxIcons = 4, iconSize = 18, spacing = 1,
                anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
            },
            externals = {
                enabled = true, maxIcons = 3, iconSize = 20, spacing = 1,
                anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
            },
        },
        privateAuras = {
            enabled = true, max = 3, size = 14,
            anchor = "BOTTOMRIGHT", direction = "LEFT",
            x = 0, y = 0, showCountdown = true, showNumbers = true, layer = 8,
                    -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
            -- Replaces the old DF-drawn frame-border overlay.
            containerOverlay = {
                enabled = false,
                showIcons = true,
                dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
                gradientDir = "default",         -- sweep direction
            },
},
        spellIndicators = { enabled = false },
    },
}
GF.PRESETS.TANK.party = {
    width = 140, height = 48, spacing = 3,
    nameFontSize = 12, nameMaxChars = 10, nameOffsetY = 5,
    hpFontSize = 11, powerHeight = 5,
    auras = {
        enabled = true,
        buff = { enabled = false },
        debuff = {
            enabled = true, maxIcons = 4, iconSize = 20, spacing = 1,
            anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
            showCooldown = true, showStacks = true,
            filterToken = "ALL",
            blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
        },
        externals = {
            enabled = true, maxIcons = 3, iconSize = 22, spacing = 1,
            anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
        },
    },
    privateAuras = {
        enabled = true, max = 3, size = 16,
        anchor = "BOTTOMRIGHT", direction = "LEFT",
        x = 0, y = 0, showCountdown = true, showNumbers = true, layer = 8,
            -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
        -- Replaces the old DF-drawn frame-border overlay.
        containerOverlay = {
            enabled = false,
            showIcons = true,
            dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
            gradientDir = "default",         -- sweep direction
        },
},
}

-- ══════════════════════════════════════════════════════════════════════
-- HEALER BASE: Foundation for all healer presets.
-- • healthFade dims full-HP targets (≥90%) → low HP frames pop visually
-- • debuffStripe: thin red bottom line for any active debuff
-- • Deficit HP text: triage at a glance
-- • Power bar on: mana/resource awareness is critical
-- • Debuffs outside top-right, externals outside top-left (no clipping)
-- • Private auras: personal defensive tracking bottom-right
-- • SI icons (per spec defaults): HoTs/shields placed on each frame
-- ══════════════════════════════════════════════════════════════════════
local _HEALER_BASE = {
    width = 120, height = 44, spacing = 2,
    showName = true, nameFontSize = 11, nameAnchor = "LEFT",
    nameOffsetX = 2, nameOffsetY = 2,
    nameMaxChars = 8, nameNoEllipsis = true,
    textLeft = "NONE", textCenter = "DEFICIT", textRight = "NONE",
    hpFontSize = 11,
    showPower = true, powerHeight = 4,
    rangeFadeEnabled = true, rangeFadeAlpha = 0.30,
    aggroEnabled = true, dispelEnabled = true, targetIndicator = true,
    healthFadeEnabled = true, healthFadeThreshold = 90, healthFadeAlpha = 0.35,
    debuffStripeEnabled = true, debuffStripeHeight = 3, debuffStripeEdge = "BOTTOM",
    debuffStripeAlpha = 0.70, debuffStripeColorR = 0.90, debuffStripeColorG = 0.20, debuffStripeColorB = 0.20,
    roleIcon = true, roleIconSize = 10,
    roleIconAnchor = "BOTTOMLEFT", roleIconX = 0, roleIconY = 0,
    raidMarker = true, raidMarkerSize = 14,
    raidMarkerAnchor = "TOPLEFT", raidMarkerX = 0, raidMarkerY = 0,
    leaderIcon = true, leaderIconSize = 10,
    leaderIconAnchor = "TOPRIGHT", leaderIconX = 0, leaderIconY = 0,
    assistIcon = true, assistIconSize = 10,
    assistIconAnchor = "TOPRIGHT", assistIconX = 12, assistIconY = 0,
    readyCheckIcon = true, readyCheckSize = 20,
    readyCheckAnchor = "CENTER", readyCheckX = 0, readyCheckY = 0,
    resurrectIcon = true, resurrectIconSize = 18,
    resurrectAnchor = "CENTER", resurrectX = 0, resurrectY = 0,
    summonIcon = true, summonIconSize = 18,
    summonAnchor = "CENTER", summonX = 0, summonY = 0,
    phaseIcon = true, phaseIconSize = 12,
    phaseAnchor = "TOPLEFT", phaseX = 0, phaseY = -14,
    ciEnabled = true, ciAlpha = 0.9,
    ciSlotTL = "dispel", ciSlotTR = "boss", ciSlotBL = "none", ciSlotBR = "none", ciSlotC = "none",
    auras = {
        enabled = true,
        buff = { enabled = false },
        debuff = {
            enabled = true, maxIcons = 3, iconSize = 18, spacing = 1,
            anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
            showCooldown = true, showStacks = true,
            filterToken = "ALL",
            blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
        },
        externals = {
            enabled = true, maxIcons = 2, iconSize = 20, spacing = 1,
            anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
        },
    },
    privateAuras = {
        enabled = true, max = 2, size = 14,
        anchor = "BOTTOMRIGHT", direction = "LEFT",
        x = 0, y = 0, showCountdown = true, showNumbers = true, layer = 8,
            -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
        -- Replaces the old DF-drawn frame-border overlay.
        containerOverlay = {
            enabled = false,
            showIcons = true,
            dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
            gradientDir = "default",         -- sweep direction
        },
},
}

-- Party override builder — scales healer frames for 5-player content.
-- auraExtra can override any aura sub-key (buff/debuff/externals).
local function _MakeHealerParty(auraExtra)
    local auras = {
        enabled = true,
        buff = { enabled = false },
        debuff = {
            enabled = true, maxIcons = 3, iconSize = 20, spacing = 1,
            anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
            showCooldown = true, showStacks = true,
            filterToken = "ALL",
            blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
        },
        externals = {
            enabled = true, maxIcons = 2, iconSize = 22, spacing = 1,
            anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
        },
    }
    if auraExtra then
        for k, v in pairs(auraExtra) do auras[k] = v end
    end
    return {
        width = 150, height = 52, spacing = 3,
        nameFontSize = 13, nameMaxChars = 12, hpFontSize = 12,
        powerHeight = 5,
        auras = auras,
        privateAuras = {
            enabled = true, max = 2, size = 16,
            anchor = "BOTTOMRIGHT", direction = "LEFT",
            x = 0, y = 0, showCountdown = true, showNumbers = true, layer = 8,
                    -- Private Aura Dispel Overlay (12.0.5+ Blizzard-rendered).
            -- Replaces the old DF-drawn frame-border overlay.
            containerOverlay = {
                enabled = false,
                showIcons = true,
                dispelMode = "dispellableByMe",  -- "dispellableByMe" | "allDispellable"
                gradientDir = "default",         -- sweep direction
            },
},
    }
end

-- ── Holy Priest ──────────────────────────────────────────────────────
-- Renew (TL icon) + PoM (TR icon) + Guardian Spirit (border glow) via SI.
-- Magic + Disease dispel corner.
GF.PRESETS.HOLY_PRIEST = {
    label = "|cffffffffHoly Priest|r",
    desc  = "Renew+PoM SI icons, Guardian Spirit glow. Health fade. Magic/Disease dispel.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
    }),
}
GF.PRESETS.HOLY_PRIEST.party = _MakeHealerParty()

-- ── Discipline Priest ────────────────────────────────────────────────
-- Atonement (TL square tint) + PW:S (TR icon) + PoM (BL icon) via SI.
-- Pain Suppression border glow. Buff group shows 1 own-cast absorb.
-- Magic + Disease dispel corner.
GF.PRESETS.DISC_PRIEST = {
    label = "|cffffffffDisc Priest|r",
    desc  = "Atonement tint, PW:S+PoM SI icons, Pain Suppression glow. Magic/Disease dispel.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
        auras = {
            enabled = true,
            buff = {
                enabled = true, maxIcons = 1, iconSize = 14, spacing = 1,
                anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
                showCooldown = false, showStacks = false,
                filterToken = "PLAYER", blacklistCats = {},
            },
            debuff = {
                enabled = true, maxIcons = 3, iconSize = 18, spacing = 1,
                anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
            },
            externals = {
                enabled = true, maxIcons = 2, iconSize = 20, spacing = 1,
                anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
            },
        },
    }),
}
GF.PRESETS.DISC_PRIEST.party = _MakeHealerParty({
    buff = {
        enabled = true, maxIcons = 1, iconSize = 16, spacing = 1,
        anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
        showCooldown = false, showStacks = false,
        filterToken = "PLAYER", blacklistCats = {},
    },
})

-- ── Restoration Druid ────────────────────────────────────────────────
-- Rejuv (TL) + Regrowth (TR) + Lifebloom (BL) + WG square + Germination
-- square + Ironbark border glow — all via SI. Buff row for HoT tracking.
-- Nature/Poison dispel corner (no Curse in DF+).
GF.PRESETS.RESTO_DRUID = {
    label = "|cffff7d0aResto Druid|r",
    desc  = "All 5 HoT SI icons + Ironbark glow. Buff row for HoT tracking. Dispel corner.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
        auras = {
            enabled = true,
            buff = {
                enabled = true, maxIcons = 3, iconSize = 14, spacing = 1,
                anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = false,
                filterToken = "PLAYER", blacklistCats = {},
            },
            debuff = {
                enabled = true, maxIcons = 3, iconSize = 18, spacing = 1,
                anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
            },
            externals = {
                enabled = true, maxIcons = 2, iconSize = 20, spacing = 1,
                anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
            },
        },
    }),
}
GF.PRESETS.RESTO_DRUID.party = _MakeHealerParty({
    buff = {
        enabled = true, maxIcons = 3, iconSize = 14, spacing = 1,
        anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
        showCooldown = true, showStacks = false,
        filterToken = "PLAYER", blacklistCats = {},
    },
})

-- ── Restoration Shaman ───────────────────────────────────────────────
-- Riptide (TL icon) + Earth Shield (TR icon) + EarthlivingWeapon (BL
-- square) via SI. Magic + Curse dispel corner.
GF.PRESETS.RESTO_SHAMAN = {
    label = "|cff0070deResto Shaman|r",
    desc  = "Riptide+Earth Shield+Earthliving SI icons. Magic/Curse dispel corner.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
    }),
}
GF.PRESETS.RESTO_SHAMAN.party = _MakeHealerParty()

-- ── Holy Paladin ─────────────────────────────────────────────────────
-- Beacon of Light (TL) + Beacon of Faith/Eternal Flame (TR) + Dawnlight
-- (bottom square) + BoP/BoSac border glows via SI. 3 external slots for
-- BoP/BoSac tracking. Magic+Disease+Poison dispel corner.
GF.PRESETS.HOLY_PALADIN = {
    label = "|cfff58cbaHoly Paladin|r",
    desc  = "Beacon SI icons, BoP/BoSac glows, 3 external slots. Magic/Disease/Poison dispel.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
        auras = {
            enabled = true,
            buff = { enabled = false },
            debuff = {
                enabled = true, maxIcons = 3, iconSize = 18, spacing = 1,
                anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
            },
            externals = {
                enabled = true, maxIcons = 3, iconSize = 20, spacing = 1,
                anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
            },
        },
    }),
}
GF.PRESETS.HOLY_PALADIN.party = _MakeHealerParty({
    externals = {
        enabled = true, maxIcons = 3, iconSize = 22, spacing = 1,
        anchor = "TOPLEFT", x = -2, y = 2, growth = "LEFT",
    },
})

-- ── Mistweaver Monk ──────────────────────────────────────────────────
-- Renewing Mist (TL) + Enveloping Mist (TR) + Soothing Mist (BL) +
-- Life Cocoon border glow via SI. Magic + Disease dispel corner.
GF.PRESETS.MISTWEAVER = {
    label = "|cff00ff96Mistweaver|r",
    desc  = "RenewingMist+EnvelopingMist+LifeCocoon glow SI icons. Magic/Disease dispel.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
    }),
}
GF.PRESETS.MISTWEAVER.party = _MakeHealerParty()

-- ── Preservation Evoker ──────────────────────────────────────────────
-- Echo (TL + namecolor tint) + Reversion (TR) + Dream Breath (BL) +
-- Lifebind (center square) via SI. Magic + Poison dispel corner.
GF.PRESETS.PRES_EVOKER = {
    label = "|cff33937fPres Evoker|r",
    desc  = "Echo namecolor tint + Reversion/DreamBreath/Lifebind SI icons. Magic/Poison dispel.",
    conf  = _MergePreset(_HEALER_BASE, {
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
    }),
}
GF.PRESETS.PRES_EVOKER.party = _MakeHealerParty()

-- ── Augmentation Evoker ──────────────────────────────────────────────
-- Ebon Might (TL healthtint) + Prescience (TR namecolor) + Blistering
-- Scales (BR square) via SI. Percent HP (not deficit — Aug isn't healing).
-- Less aggressive fade threshold. Buff row shows own-cast buffs.
-- No externals (Aug doesn't track survival CDs).
GF.PRESETS.AUG_EVOKER = {
    label = "|cff33937fAug Evoker|r",
    desc  = "EbonMight+Prescience SI icons+tints. Percent HP. Buff row. No externals.",
    conf  = _MergePreset(_HEALER_BASE, {
        textCenter = "PERCENT",
        healthFadeEnabled = true, healthFadeThreshold = 80, healthFadeAlpha = 0.40,
        spellIndicators = { enabled = true, spec = "auto", specs = {} },
        auras = {
            enabled = true,
            buff = {
                enabled = true, maxIcons = 2, iconSize = 14, spacing = 1,
                anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = false,
                filterToken = "PLAYER", blacklistCats = {},
            },
            debuff = {
                enabled = true, maxIcons = 2, iconSize = 16, spacing = 1,
                anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
                showCooldown = true, showStacks = true,
                filterToken = "ALL",
                blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
            },
            externals = { enabled = false },
        },
    }),
}
GF.PRESETS.AUG_EVOKER.party = _MakeHealerParty({
    buff = {
        enabled = true, maxIcons = 2, iconSize = 14, spacing = 1,
        anchor = "BOTTOMLEFT", x = 0, y = 2, growth = "RIGHT",
        showCooldown = true, showStacks = false,
        filterToken = "PLAYER", blacklistCats = {},
    },
    debuff = {
        enabled = true, maxIcons = 2, iconSize = 18, spacing = 1,
        anchor = "TOPRIGHT", x = 2, y = 2, growth = "RIGHT",
        showCooldown = true, showStacks = true,
        filterToken = "ALL",
        blacklistCats = { SATED = true, SKYRIDING = true, COOLDOWNS = true, DESERTER = true },
    },
    externals = { enabled = false },
})

-- Ordered preset list for UI
GF.PRESET_ORDER = {
    "DPS", "TANK",
    "HOLY_PRIEST", "DISC_PRIEST",
    "RESTO_DRUID", "RESTO_SHAMAN",
    "HOLY_PALADIN", "MISTWEAVER",
    "PRES_EVOKER", "AUG_EVOKER",
}

------------------------------------------------------------------------
-- Apply preset to a scope (party/raid).
-- Base conf applied first, then scope-specific override (party = larger).
------------------------------------------------------------------------
function GF.ApplyPreset(kind, presetKey)
    local preset = GF.PRESETS[presetKey]
    if not preset or not preset.conf then return false end
    local conf = GF.GetConf(kind)
    if not conf then return false end

    local px, py, pp = conf.offsetX, conf.offsetY, conf.point

    for k, v in pairs(preset.conf) do
        conf[k] = (type(v) == "table") and GF._DeepCopyTable(v) or v
    end

    local scopeOvr = (kind == "raid") and preset.raid or preset.party
    if scopeOvr then
        for k, v in pairs(scopeOvr) do
            conf[k] = (type(v) == "table") and GF._DeepCopyTable(v) or v
        end
    end

    conf.offsetX, conf.offsetY, conf.point = px, py, pp

    if GF.RebuildAll then GF.RebuildAll() end
    GF.RefreshVisuals()
    return true
end

------------------------------------------------------------------------
-- Class/Spec → Preset: auto-applied on first addon setup.
-- Healers and tanks get specialized presets; everything else gets DPS.
------------------------------------------------------------------------
local _CLASS_PRESET_MAP = {
    DRUID_4       = "RESTO_DRUID",
    SHAMAN_3      = "RESTO_SHAMAN",
    PRIEST_1      = "DISC_PRIEST",
    PRIEST_2      = "HOLY_PRIEST",
    PALADIN_1     = "HOLY_PALADIN",
    EVOKER_2      = "PRES_EVOKER",
    EVOKER_3      = "AUG_EVOKER",
    MONK_2        = "MISTWEAVER",
    WARRIOR_3     = "TANK",
    PALADIN_2     = "TANK",
    MONK_1        = "TANK",
    DRUID_3       = "TANK",
    DEMONHUNTER_2 = "TANK",
    DEATHKNIGHT_1 = "TANK",
}

function GF.MaybeApplyDefaultPreset()
    if not GF._pendingDefaultPreset then return end
    GF._pendingDefaultPreset = nil
    local db = _G.MSUF_DB
    if not db then return end

    local _, classToken
    if UnitClass then _, classToken = UnitClass("player") end
    local specIdx = GetSpecialization and GetSpecialization() or nil
    if not (classToken and specIdx) then return end

    local key = classToken .. "_" .. specIdx
    local presetKey = _CLASS_PRESET_MAP[key] or "DPS"

    db._gfDefaultPresetApplied = true
    GF.ApplyPreset("party", presetKey)
    GF.ApplyPreset("raid",  presetKey)
    print("|cff00ff00MSUF:|r Default group frame preset applied: " .. (GF.PRESETS[presetKey] and GF.PRESETS[presetKey].label or presetKey))
end

-- Register PLAYER_ENTERING_WORLD to fire MaybeApplyDefaultPreset once.
do
    local _f = CreateFrame("Frame")
    _f:RegisterEvent("PLAYER_ENTERING_WORLD")
    _f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            _f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            GF.MaybeApplyDefaultPreset()
        end
    end)
end
