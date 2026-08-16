--- GroupFrames/MSUF_GroupFrames_DB.lua - group-frame defaults, DB normalization, and config access
--- Phase 12: 3-slot health text, name color, name max chars, power per-role,
--- smooth fill toggle, hideInClientScene, target/aggro upgrades
--- Midnight 12.0 secret-safe, zero combat overhead
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

MSUF.GF = MSUF.GF or {}
local GF = MSUF.GF
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

--==========================================================================--
-- GroupFrames API surface (MSUF.GF / _G.MSUF_*)
--==========================================================================--
-- This is the contract for the GroupFrames module. The module is split across
-- GroupFrames/*.lua and UnitFrames/Engine/Group/*.lua but shares ONE table
-- (MSUF.GF, aliased `GF` in every file). Keep the surface minimal:
--
--   * Public / external bridges  -> global _G.MSUF_* wrappers (see lists below).
--       Options, EditMode, the Assistant, slash/debug, LoadOnDemand modules and
--       third-party addons call these by GLOBAL NAME. Treat them as a stable
--       ABI: do not rename or delete; if one becomes unused keep it as a thin
--       wrapper (deprecated) rather than removing it.
--
--   * Cross-file internal API    -> GF.* functions used by >1 GroupFrames file
--       (e.g. GF.GetConf, GF.GetGridMetrics, GF.ApplyButton, GF.CompileSpec,
--        GF.GetConfigDBKey, GF.GetLiveRaidKind, GF.GetLiveGroupKind,
--        GF.ForEachFrame, GF.MarkDirty,
--        the GF.DIRTY_* mask constants, GF.RefreshAll/RefreshVisuals/RebuildAll).
--       Keep these on GF.*; they are the module's internal contract.
--
--   * File-local helpers         -> plain `local function`. If a helper is only
--       used inside one file it MUST NOT live on GF.*; declare it local instead.
--
-- _G.MSUF_* bridge groups (definition file in parentheses):
--   Refresh/runtime (Runtime):  MSUF_GF_RebuildAll, _RefreshAll, _Refresh,
--       _RefreshVisuals, _RefreshGeometry, _RefreshOverlays, _RefreshBorder,
--       _RefreshOutlineGeometry, _RefreshColors, _RefreshFonts,
--       _UpdateGroupVisibility, _EM2_SetActivePreviewKind, _EM2_NudgePreview,
--       _InvalidateCooldownTextCurve, _ForceCooldownTextRecolor,
--       _ForceAuraTextColorRefresh   (EM2 re-wraps _RefreshVisuals/_RebuildAll
--       in-place to add edit-mode preview sync -- that re-assignment is
--       intentional, not a duplicate definition).
--   Preview (Preview):  MSUF_GF_ShowPreview, _HidePreview, _SetPreviewAnchor,
--       _RefreshPreviewLayout, _RefreshPreviewBox.  NOTE: Preview.lua loads
--       after Runtime.lua and OWNS the real preview implementation -- Runtime
--       deliberately does NOT define these to avoid an overwritten duplicate.
--   DB config (this file):  MSUF_GF_EnsureDB, _GetConf, _Val, _GetHighlightVal,
--       _InvalidateConfCache, _ResetAllToDefaults.
--   Status icon packs (this file):  MSUF_RegisterStatusIconPack /
--       MSUF_RefreshStatusIconPacks are a PUBLIC extension point for other
--       addons (no internal callers by design -- keep them). Plus
--       MSUF_GetStatusIconPackValues / MSUF_GetStatusIconTexture /
--       MSUF_Get{Role,Leader,Assist}StatusIconTexture.
--   Spell indicators (DB_SpellIndicators): MSUF_GF_Seed{,Current}SpellIndicator*.
--   EditMode popups (EM2): MSUF_EM2_*GFPopup*, MSUF_GF_EM2_*.
--   Blizzard frames (Blizzard): MSUF_GF_DisableBlizzard.
--==========================================================================--

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs
local ResolveFontPathSafe = _G.MSUF_ResolveFontPath or function(path) return path end

local function ComposeFontFlags(outline, monochrome, slug)
    local flags = ""
    outline = tostring(outline or "OUTLINE"):upper()
    if slug == true then
        return (outline == "NONE" or outline == "") and "SLUG" or "OUTLINE,SLUG"
    end
    if outline == "THICKOUTLINE" then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" and outline ~= "" then
        flags = "OUTLINE"
    end
    if monochrome == true then
        flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
    end
    return flags
end

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

local ShadowMetrics = _G.MSUF_ResolveFontShadowMetrics or function(opacity, distance, legacyStrength, fallbackOpacity, fallbackDistance)
    if legacyStrength ~= nil then
        legacyStrength = tostring(legacyStrength):upper()
        opacity = legacyStrength == "SOFT" and 0.55 or 1
        distance = legacyStrength == "DEEP" and 2 or 1
    else
        opacity = tonumber(opacity) or tonumber(fallbackOpacity) or 1
        distance = tonumber(distance) or tonumber(fallbackDistance) or 1
    end
    if opacity < 0.20 then opacity = 0.20 elseif opacity > 1 then opacity = 1 end
    distance = math.floor(distance + 0.5)
    distance = distance <= 1 and 1 or 2
    return opacity, distance, -distance
end

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
local _GF_UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
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

---
--- Defaults
---
local PARTY_DEFAULTS = {
    enabled           = false,
    blizzardFallbackMode = "AUTO", --- AUTO / SHOW / NONE when this MSUF scope is disabled
    --- AUTO / SHOW / MOUSEOVER / HIDDEN for Blizzard's Raid Manager tab. One shared
    --- frame, so Party, Raid and Mythic Raid always hold the same value (Menu2 writes all
    --- three). AUTO keeps the historical behavior: gone while MSUF owns the group frames.
    raidManagerMode   = "AUTO",
    width             = 120,
    height            = 40,
    spacing           = 1,
    growth            = "DOWN",    --- DOWN / UP / RIGHT / LEFT
    showPlayer        = true,
    showSolo          = false,
    clickCastEnabled  = true,
    powerBarEnabled   = true,
    powerHeight       = 6,
    --- Position (CENTER-native, same as EM2 movers)
    point             = "CENTER",
    offsetX           = -400,
    offsetY           = 0,
    --- Health bar
    healthColorMode   = "CLASS",   --- CLASS / GRADIENT / CUSTOM
    healthCustomR     = 0.2,
    healthCustomG     = 0.8,
    healthCustomB     = 0.2,
    --- Bar textures (nil = inherit global)
    barTexture        = nil,
    barBgTexture      = nil,
    --- Background (RGB colour; opacity is the unified hpBgAlpha)
    bgR               = 0.1,
    bgG               = 0.1,
    bgB               = 0.1,
    --- Unified alpha: HP fill opacity, background opacity, keep-text/portrait toggle
    hpBarAlpha        = 1,
    hpBgAlpha         = 0.85,
    --- Out-of-combat fade: whole-member-frame alpha while out of combat.
    --- Composed min() with range/offline fade in GroupRangeFade; off by default.
    oocFadeEnabled    = false,
    oocFadeAlpha      = 0.5,
    --- Border
    borderEnabled     = true,
    borderSize        = 1,
    borderR           = 0,
    borderG           = 0,
    borderB           = 0,
    borderA           = 1,
    --- Optional visual border around the whole group block.
    groupBorderEnabled = false,
    groupBorderSize    = 1,
    groupBorderPadding = 2,
    groupBorderR       = 0.38,
    groupBorderG       = 0.68,
    groupBorderB       = 1.00,
    groupBorderA       = 0.95,
    --- Text: 3-slot system (replaces showHP boolean)
    showName          = true,
    showHPText        = true,
    --- Legacy key `showPower` is kept for saved profiles; new code treats
    --- it as the Group Frame power-text toggle, not as power-bar visibility.
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
    healthTextDecimals = false,
    hpFullValueShort  = true,
    hpAbsorbIcon      = false,
    --- Reverse order toggle (flips multi-part modes)
    hpTextReverse     = false,
    --- Name color
    nameColorMode     = "DEFAULT",  --- DEFAULT / CLASS / CUSTOM
    nameColorR        = 1,
    nameColorG        = 1,
    nameColorB        = 1,
    --- Name truncation
    nameMaxChars      = 0,     --- 0 = unlimited
    nameNoEllipsis    = false,
    hideNameOnDeadOffline = false,
    --- Font style/color (font family is global)
    fontOutline       = nil,
    fontMonochrome    = nil,
    fontSlug          = nil,
    textBackdrop      = nil,
    fontShadowStrength = nil,
    fontShadowOpacity = nil,
    fontShadowDistance = nil,
    fontTextAlpha     = nil,
    fontBaselineOffset = nil,
    useGlobalFontColor = true,
    fontR             = nil,
    fontG             = nil,
    fontB             = nil,
    --- Range fade
    rangeFadeEnabled  = true,
    rangeFadeAlpha    = 0.4,
    rangeFadeLayerMode = "frame", --- frame / health
    offlineAlpha      = 0.5,
    offlineFadeEnabled = false,
    hideOfflineEnabled = false,
    hideOfflineInCombat = false,
    hideOfflineDelay  = 0,
    --- Aggro border
    aggroEnabled      = true,
    aggroR            = 1,
    aggroG            = 0,
    aggroB            = 0,
    aggroMode         = "ALL",  --- ALL / NON_TANK / HEALER / TANK
    --- Dispel border
    dispelEnabled     = true,
    --- Target indicator
    targetIndicator   = true,
    targetR           = 1,
    targetG           = 1,
    targetB           = 1,
    --- Status icons
    iconStyle         = "MSUF_ROLES", --- MSUF role glyphs; unsupported status types fall back to Blizzard
    useMidnightIcons  = false,
    roleIcon          = true,
    roleIconStyle     = "DEFAULT",
    roleIconCustomIcon = "",
    roleIconShowTank   = true,
    roleIconShowHealer = true,
    roleIconShowDPS    = true,
    roleIconSize      = 16,
    roleIconAnchor    = "LEFT",
    roleIconX         = 4,
    roleIconY         = 0,
    raidMarker        = true,
    raidMarkerStyle   = "DEFAULT",
    raidMarkerCustomIcon = "",
    raidMarkerSize    = 14,
    raidMarkerAnchor  = "CENTER",
    raidMarkerX       = 0,
    raidMarkerY       = 0,
    leaderIcon        = true,
    leaderIconStyle   = "DEFAULT",
    leaderIconCustomIcon = "",
    leaderIconSize    = 12,
    leaderIconAnchor  = "TOPRIGHT",
    leaderIconX       = 0,
    leaderIconY       = 0,
    assistIcon        = true,
    assistIconStyle   = "DEFAULT",
    assistIconCustomIcon = "",
    assistIconSize    = 12,
    assistIconAnchor  = "TOPRIGHT",
    assistIconX       = 14,
    assistIconY       = 0,
    readyCheckIcon    = true,
    readyCheckIconStyle = "DEFAULT",
    readyCheckIconCustomIcon = "",
    readyCheckSize    = 16,
    readyCheckAnchor  = "CENTER",
    readyCheckX       = 0,
    readyCheckY       = 0,
    summonIcon        = true,
    summonIconStyle   = "DEFAULT",
    summonIconCustomIcon = "",
    summonIconSize    = 16,
    summonAnchor      = "CENTER",
    summonX           = 0,
    summonY           = 0,
    resurrectIcon     = true,
    resurrectIconStyle = "DEFAULT",
    resurrectIconCustomIcon = "",
    resurrectIconSize = 16,
    resurrectAnchor   = "CENTER",
    resurrectX        = 0,
    resurrectY        = 0,
    pvpIcon           = true,
    pvpIconStyle      = "DEFAULT",
    pvpIconCustomIcon = "",
    pvpIconSize       = 14,
    pvpIconAnchor     = "TOPLEFT",
    pvpIconX          = 14,
    pvpIconY          = 0,
    phaseIcon         = true,
    phaseIconStyle    = "DEFAULT",
    phaseIconCustomIcon = "",
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
    statusAFKTimerText       = false,
    statusAFKTimerTextSize   = 10,
    statusAFKTimerTextAnchor = "CENTER",
    statusDNDText          = true,
    statusDNDTextSize      = 14,
    statusDNDTextAnchor    = "CENTER",
    --- Status icon/text layers (frame level order: higher = on top)
    roleIconLayer     = 1,
    leaderIconLayer   = 2,
    assistIconLayer   = 2,
    raidMarkerLayer   = 3,
    readyCheckLayer   = 4,
    summonLayer       = 4,
    resurrectLayer    = 4,
    pvpIconLayer      = 3,
    phaseLayer        = 3,
    statusTextLayer   = 7,
    statusGhostTextLayer = 7,
    statusAFKTextLayer   = 7,
    statusAFKTimerTextLayer = 7,
    statusDNDTextLayer   = 7,
    --- Text offsets
    nameOffsetX       = 28, -- clears the complete left status-icon lane
    nameOffsetY       = 0,
    hpOffsetX         = 0,
    hpOffsetY         = 0,
    hpTextLeftOffsetX = 0,
    hpTextLeftOffsetY = 0,
    hpTextCenterOffsetX = 0,
    hpTextCenterOffsetY = 0,
    hpTextRightOffsetX = 0,
    hpTextRightOffsetY = 0,
    powerOffsetX      = 0,
    powerOffsetY      = 0,
    powerTextLeftOffsetX = 0,
    powerTextLeftOffsetY = 0,
    powerTextCenterOffsetX = 0,
    powerTextCenterOffsetY = 0,
    powerTextRightOffsetX = 0,
    powerTextRightOffsetY = 0,
    statusOffsetX     = 0,
    statusOffsetY     = 0,
    statusGhostOffsetX = 0,
    statusGhostOffsetY = 0,
    statusAFKOffsetX   = 0,
    statusAFKOffsetY   = 0,
    statusAFKTimerOffsetX = 0,
    statusAFKTimerOffsetY = -10,
    statusDNDOffsetX   = 0,
    statusDNDOffsetY   = 0,
    --- Text layer (frame level relative to bar)
    nameTextLayer     = 5,
    textLayer         = 5,
    powerTextLayer    = 2,
    --- Unified alpha: keep text + portrait opaque while bars dim (HP/background
    --- opacity live in hpBarAlpha / hpBgAlpha above).
    alphaExcludeTextPortrait = false,
    --- Group Frame heal prediction is edited in Global Style > Bars using the
    --- Party/Raid bar scopes. hlOverride gates local values; otherwise the
    --- shared UnitFrame heal-prediction toggle is the fallback.
    healPredEnabled      = true,
    tempMaxHealthEnabled = false,
    tempMaxHealthTexture = "Solid",
    tempMaxHealthColorR  = 0.70,
    tempMaxHealthColorG  = 0.10,
    tempMaxHealthColorB  = 0.10,
    tempMaxHealthOpacity = 1,
    tempMaxHealthBackgroundOpacity = 0.65,
    healPredAnchorMode   = 3,
    healPredictionBarHeight = 0,
    healPredictionBarOffsetY = 0,
    healPredictionBarOpacity = 0.45,
    healPredictionBarTexture = "",
    enableAbsorbBar      = true,
    healAbsorbEnabled    = true,
    absorbTextMode       = 2,
    absorbAnchorMode     = 5,
    absorbBarHeight      = 0,
    absorbBarOffsetY     = 0,
    absorbBarOpacity     = 1,
    absorbBarTexture     = "MSUF Smooth v2",
    healAbsorbAnchorMode = 3,
    healAbsorbBarHeight  = 0,
    healAbsorbBarOffsetY = 0,
    healAbsorbBarOpacity = 1,
    healAbsorbBarTexture = "Solid",
    overAbsorbOverlay    = true,
    --- Group number (raid subgroup on frame)
    showGroupNumber       = false,
    groupNumberStyle      = "PAREN",
    groupNumberSize       = 10,
    groupNumberAnchor     = "BOTTOMRIGHT",
    groupNumberX          = -2,
    groupNumberY          = 2,
    groupNumberLayer      = 7,
    --- Reverse fill
    reverseFill           = false,
    --- Smooth fill
    smoothFill            = false,
    --- Instant fill with a delayed recent-loss trail.
    chunkedFill           = false,
    --- Dispel overlay (color wash on health bar when dispellable debuff active)
    dispelOverlayEnabled  = false,
    dispelOverlayStyle    = "FULL",   --- FULL / BOTTOM / TOP / LEFT / RIGHT
    dispelOverlayOnHealth = true,     --- true = clip to current health fill
    dispelOverlayAlpha    = 0.35,
    dispelOverlayTrigger  = "BORDER", --- BORDER / BY_ME(dispellable by player) / DISPEL_TYPE / ANY_DEBUFF
    dispelOverlayLayer    = 0,        --- additive 0..30 local FrameLevel offset
    dispelOverlayStrata   = "AUTO",

    --- Dispel-type symbol (placed icon that names WHICH debuff type is up)
    dispelSymbolEnabled   = false,
    dispelSymbolStyle     = "BLIZZARD", --- BLIZZARD / BLIZZARD_RING / BLIZZARD_BORDER / MSUF_LETTERS / MSUF_SHAPES / MSUF_GLYPHS / MSUF_MINIMAL
    dispelSymbolMode      = "ALL",      --- ALL = one symbol per type, TOP = highest priority only
    dispelSymbolTrigger   = "BORDER",   --- BORDER / BY_ME / BY_RAID / DISPEL_TYPE / PLAYER_CAST
    dispelSymbolSize      = 12,
    dispelSymbolSpacing   = 2,          --- gap between ALL-mode symbols
    dispelSymbolGrowth    = "RIGHT",    --- RIGHT / LEFT / UP / DOWN
    dispelSymbolAnchor    = "TOPRIGHT",
    dispelSymbolX         = 0,
    dispelSymbolY         = 0,
    dispelSymbolAlpha     = 1,
    dispelSymbolLayer     = 8,          --- additive 0..30 local FrameLevel offset
    dispelSymbolStrata    = "AUTO",

    --- Debuff stripe (thin edge indicator for any debuff)
    debuffStripeEnabled   = false,
    debuffStripeEdge      = "BOTTOM", --- BOTTOM / TOP
    debuffStripeHeight    = 3,        --- pixels
    debuffStripeAlpha     = 0.60,
    debuffStripeColorR    = 0.80,
    debuffStripeColorG    = 0.20,
    debuffStripeColorB    = 0.20,
    --- Health fade (dim frames above HP threshold - healer focus)
    healthFadeEnabled     = false,
    healthFadeThreshold   = 95,    --- % HP above which frame is dimmed
    healthFadeAlpha       = 0.45,  --- alpha when above threshold
    --- Dead/offline background tint (event-driven; recolors the HP background
    --- when a member is dead, a ghost, or offline)
    deadBgEnabled         = false,
    deadBgOffline         = true,  --- also tint disconnected members
    deadBgR               = 0.60,
    deadBgG               = 0.05,
    deadBgB               = 0.05,
    deadBgA               = 0.90,
    --- Focus highlight (separate glow when unit is focus)
    hlFocusEnabled        = true,
    hlFocusColorR         = 0.50,
    hlFocusColorG         = 0.50,
    hlFocusColorB         = 1.00,
    hlFocusSize           = 2,
    hlFocusOffset         = 0,
    --- Hide in client scene (barber/dressing room)
    hideInClientScene     = true,
    hideInHousing         = false,
    --- Power per-role visibility
    powerShowTank         = true,
    powerShowHealer       = true,
    powerShowDamager      = false,
    --- Power 3-slot text system
    powerTextLeft         = "NONE",
    powerTextCenter       = "PERCENT",
    powerTextRight        = "NONE",
    powerTextDelimiter    = " / ",
    --- Power smooth fill
    powerSmoothFill       = false,
    powerChunkedFill      = false,
    --- Power bar parity with the unit-frame Resource Bar section. Bar art and
    --- colour stay global (same as the unit page, which configures them once on
    --- Bars); these are the per-scope keys that page actually exposes.
    powerBarBorderEnabled = false,
    powerBarBorderThickness = 1,
    embedPowerBarIntoHealth = true,
    powerBarDetached      = false,
    detachedPowerBarTextOnBar = false,
    detachedPowerBarOffsetX = 0,
    detachedPowerBarOffsetY = -4,
    detachedPowerBarWidth = 0,
    detachedPowerBarHeight = 6,
    detachedPowerBarFrameLevelOffset = 6,
    --- Auras (Phase 4, stubs)
    aurasEnabled      = true,
    auraMaxIcons      = 4,
    auraIconSize      = 20,
    --- Corner Indicators
    ciEnabled         = true,
    ciSize            = 8,
    ciAlpha           = 1.0,
    ciLayer           = 7,
    ciStrata          = "AUTO",
    ciSlotTL          = "dispel",
    ciSlotTR          = "aggro",
    ciSlotBL          = "none",
    ciSlotBR          = "none",
    ciSlotC           = "none",
    --- Aggro slot color (matches highlight aggro border default = orange)
    ciAggroColorR     = 1.00,
    ciAggroColorG     = 0.55,
    ciAggroColorB     = 0.00,
    --- Custom-slot configs (per-slot table; nil = unset).
    --- Each: { spells = "1234,5678", mode = "present"|"missing",
    --- filter = "HELPFUL|PLAYER", r = 0.4, g = 1, b = 0.4 }
    ciCustomTL        = nil,
    ciCustomTR        = nil,
    ciCustomBL        = nil,
    ciCustomBR        = nil,
    ciCustomC         = nil,
    --- Grid layout
    unitsPerColumn    = 5,
    maxColumns        = 1,
    preserveRaidGroups = false,
    --- Role sort
    sortByRole        = false,
    roleOrder         = "TANK,HEALER,DAMAGER",
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
    RAID_DEFAULTS.powerBarEnabled = true
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
    RAID_DEFAULTS.roleIconSize   = 14
    RAID_DEFAULTS.raidMarkerSize = 12
    RAID_DEFAULTS.pvpIconSize    = 12
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

--- Party-only portrait defaults. Keep these assignments after the Raid/Mythic
--- clone blocks above: those scopes intentionally do not own portrait config.
PARTY_DEFAULTS.portraitMode = "OFF"
PARTY_DEFAULTS.portraitRender = "2D"
PARTY_DEFAULTS.portraitClassStyle = "BLIZZARD"
PARTY_DEFAULTS.portraitShape = "SQUARE"
PARTY_DEFAULTS.portraitSizeMode = "UNIFORM"
PARTY_DEFAULTS.portraitSizeOverride = 0
PARTY_DEFAULTS.portraitWidth = 0
PARTY_DEFAULTS.portraitHeight = 0
PARTY_DEFAULTS.portraitOffsetX = 0
PARTY_DEFAULTS.portraitOffsetY = 0
PARTY_DEFAULTS.portraitZoom = 100
PARTY_DEFAULTS.portraitPanX = 0
PARTY_DEFAULTS.portraitPanY = 0
PARTY_DEFAULTS.portraitPlacement = "ATTACHED"
PARTY_DEFAULTS.portraitDetachedPoint = "RIGHT"
PARTY_DEFAULTS.portraitDetachedTo = "LEFT"
PARTY_DEFAULTS.portraitOverlayAlign = "LEFT"
PARTY_DEFAULTS.portraitLevelOffset = 7
PARTY_DEFAULTS.portraitAlpha = 100
PARTY_DEFAULTS.portraitCastSpellIcon = false
PARTY_DEFAULTS.portraitBorderStyle = "NONE"
PARTY_DEFAULTS.portraitEdgeSoftness = 0
PARTY_DEFAULTS.portraitBorderThickness = 2
PARTY_DEFAULTS.portraitFillBorder = false
PARTY_DEFAULTS.portraitBorderArt = "FLAT"
PARTY_DEFAULTS.portraitBorderDirection = "UP"
PARTY_DEFAULTS.portraitBorderColorR = 1
PARTY_DEFAULTS.portraitBorderColorG = 1
PARTY_DEFAULTS.portraitBorderColorB = 1
PARTY_DEFAULTS.portraitBorderColorA = 1
PARTY_DEFAULTS.portraitBgEnabled = false
PARTY_DEFAULTS.portraitBgColorR = 0.05
PARTY_DEFAULTS.portraitBgColorG = 0.05
PARTY_DEFAULTS.portraitBgColorB = 0.05
PARTY_DEFAULTS.portraitBgColorA = 0.85

--- Priority Frames are a small secure duplicate strip for important raid
--- members. Visuals intentionally inherit the active raid/mythic-raid spec;
--- this table owns only activation, selection policy, and container geometry.
local PRIORITY_DEFAULTS = {
    enabled       = false,
    autoTanks     = true,
    maxFrames     = 5,
    growth        = "DOWN",
    spacing       = 2,
    anchorMode    = "RAID_RIGHT", --- RAID_RIGHT / RAID_LEFT / RAID_TOP / RAID_BOTTOM / FREE
    attachGap     = 8,
    attachOffset  = 0,
    point         = "CENTER",
    relativePoint = "CENTER",
    offsetX       = -120,
    offsetY       = 0,
}

GF.PARTY_DEFAULTS = PARTY_DEFAULTS
GF.RAID_DEFAULTS  = RAID_DEFAULTS
GF.MYTHIC_RAID_DEFAULTS = MYTHIC_RAID_DEFAULTS
GF.PRIORITY_DEFAULTS = PRIORITY_DEFAULTS

function GF.ShouldShowNameText(frame, conf)
    return conf and conf.showName ~= false and not (frame and frame._msufGFNameHiddenForStatus == true)
end

---
--- Grid metrics (V2 stores the selected anchor point of the complete grid bounds)
---
GF._measuredFirstCenterDelta = GF._measuredFirstCenterDelta or {}

local LEGACY_GRID_POSITION_MODE = "GRID_CENTER_V1"
local STABLE_GRID_POSITION_MODE = "GRID_BOUNDS_V2"

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

---
--- Anchor point
--- Party, Raid and Mythic Raid expose exactly ONE anchor control ("Anchor
--- Point"): it pins the chosen corner of the block to the identical corner of
--- the anchor frame. `point` is only its legacy projection, and `relativePoint`
--- has no control at all - but profiles still carry both, and the placement code
--- used to let a stale `relativePoint` win over the visible setting. A scope
--- whose leftover said CENTER anchored to the middle of the anchor frame while a
--- scope without one anchored to its corner, so two scopes showing the same
--- Anchor Point and the same X/Y landed half an anchor frame apart (GitHub #67).
--- Retire the leftovers on the first placement - folding them into the saved
--- offsets keeps the block exactly where it is - and let the visible setting own
--- both sides from then on. Priority Frames are excluded on purpose: point and
--- relativePoint are real, settable options there (GF.SetPriorityOption).
---
local ANCHOR_POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}

local function AnchorPointFraction(point)
    local fx, fy = 0.5, 0.5
    if point == "LEFT" or point == "TOPLEFT" or point == "BOTTOMLEFT" then
        fx = 0
    elseif point == "RIGHT" or point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
        fx = 1
    end
    if point == "BOTTOM" or point == "BOTTOMLEFT" or point == "BOTTOMRIGHT" then
        fy = 0
    elseif point == "TOP" or point == "TOPLEFT" or point == "TOPRIGHT" then
        fy = 1
    end
    return fx, fy
end

function GF.GetAnchorPoint(conf)
    local point = conf and (conf.anchorPoint or conf.point) or "CENTER"
    if not ANCHOR_POINTS[point] then point = "CENTER" end
    return point
end

--- Clamp the configured anchor point, not the complete group footprint.
--- Party and Raid can have very different grid sizes. Full-frame clamping
--- silently adds a size-dependent delta after SetPoint, so identical
--- Anchor To / Anchor Point / X / Y values no longer identify the same screen
--- point. Blizzard's clamp rect supports an exact point-sized selection (the
--- same mechanism Edit Mode uses for selection bounds), preserving recovery at
--- the screen edge without changing the saved coordinate contract.
function GF.ConfigureAnchorPointScreenClamp(frame, point, width, height)
    if not (frame and frame.SetClampedToScreen) then return false end
    point = ANCHOR_POINTS[point] and point or "CENTER"
    local w = tonumber(width) or (frame.GetWidth and tonumber(frame:GetWidth()))
    local h = tonumber(height) or (frame.GetHeight and tonumber(frame:GetHeight()))
    if not (frame.SetClampRectInsets and w and h and w >= 0 and h >= 0) then
        --- A full-frame fallback would reintroduce the Party/Raid divergence.
        frame:SetClampedToScreen(false)
        frame._msufScreenClampEnabled = nil
        frame._msufGFAnchorPointClampKey = nil
        return false
    end

    local fx, fy = AnchorPointFraction(point)
    local half = 0.5
    local left, right = w * fx - half, -w * (1 - fx) + half
    local top, bottom = -h * (1 - fy) + half, h * fy - half
    local key = point .. "\030" .. tostring(w) .. "\030" .. tostring(h)
    if frame._msufGFAnchorPointClampKey ~= key then
        frame:SetClampRectInsets(left, right, top, bottom)
        frame._msufGFAnchorPointClampKey = key
    end
    if frame._msufScreenClampEnabled ~= true then
        frame:SetClampedToScreen(true)
        frame._msufScreenClampEnabled = true
    end
    return true
end

--- Convert a legacy relativePoint into the saved offsets. Returns false while
--- the anchor frame has no measurable size so the next placement can retry;
--- until then the old pair stays live and the block does not jump.
local function RetireLegacyRelativePoint(conf, point, parent)
    local legacy = conf.relativePoint
    if not ANCHOR_POINTS[legacy] or legacy == point then
        conf.relativePoint = nil
        return true
    end
    local w = parent and parent.GetWidth and tonumber(parent:GetWidth())
    local h = parent and parent.GetHeight and tonumber(parent:GetHeight())
    if not (w and h and w > 0 and h > 0) then return false end
    local fx, fy = AnchorPointFraction(point)
    local rfx, rfy = AnchorPointFraction(legacy)
    conf.offsetX = math_floor(((tonumber(conf.offsetX) or 0) + w * (rfx - fx)) + 0.5)
    conf.offsetY = math_floor(((tonumber(conf.offsetY) or 0) + h * (rfy - fy)) + 0.5)
    conf.relativePoint = nil
    return true
end

--- Anchor points for one group block, ready to feed a SetPoint call. `parent` is
--- the already resolved anchor frame; it is only read to retire the legacy pair.
--- Callers must read conf.offsetX/offsetY AFTER this, since retiring rewrites
--- them. Cold path only (header setup, preview build, Edit Mode sync).
function GF.ResolveAnchorPoint(kind, conf, parent)
    local point = GF.GetAnchorPoint(conf)
    if kind == "priority" then
        local relativePoint = conf and conf.relativePoint
        return point, ANCHOR_POINTS[relativePoint] and relativePoint or point
    end
    --- Callers reach this with a header key ("raid" also carries the Mythic Raid
    --- conf), so reject every defaults table instead of the one for `kind`:
    --- a shared defaults table must never collect a scope's position.
    if type(conf) ~= "table"
        or conf == PARTY_DEFAULTS or conf == RAID_DEFAULTS
        or conf == MYTHIC_RAID_DEFAULTS or conf == PRIORITY_DEFAULTS then
        return point, point
    end
    if conf.relativePoint ~= nil and not RetireLegacyRelativePoint(conf, point, parent) then
        return point, conf.relativePoint
    end
    --- Keep the legacy projection in step so exports, imports and the Assistant
    --- never read a point the menu no longer shows.
    if conf.point ~= point then conf.point = point end
    return point, point
end

---
--- Group Frame Scaling
--- Scales the physical frame geometry first; render modules then use the
--- cached scale for fonts and icons. Keeping the math here prevents the
--- header, preview, mover, and child-scan paths from drifting apart.
---
local SCALE_AUTO_DEFAULTS = {
    { max = 10, scale = 100 },  --- 1-10 players
    { max = 20, scale = 85  },  --- 11-20 players
    { max = 25, scale = 80  },  --- 21-25 players
    --- 26+ uses scaleOver25
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
    if conf and conf.powerBarEnabled == false then return 0 end
    local raw = tonumber(conf and conf.powerHeight) or (IsRaidLikeKind(kind) and 4 or 6)
    if raw <= 0 then return 0 end
    if not conf then return raw end
    local scale = conf._resolvedFrameScale or GF.ApplyFrameScale(kind) or 1
    return GF.ScaleValue(raw, scale, 1)
end

function GF.NormalizeGroupRole(role)
    if _GF_issecretvalue then
        if _GF_issecretvalue(role) == true then return "DAMAGER" end
    end
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
    if conf.powerBarEnabled == false then return false end
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

local function GetRaidGroupLayoutParts(conf, count)
    local upc = math_floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end
    local primary = math_min(upc, 5)
    local groups = math_floor((tonumber(conf and conf.maxColumns) or 8) + 0.5)
    if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    if type(GF.GetPreservedRaidGroupCount) == "function" then
        groups = tonumber(GF.GetPreservedRaidGroupCount(conf)) or groups
        if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
    end
    local blockColumns = math_ceil(5 / primary)
    if blockColumns < 1 then blockColumns = 1 end
    return upc, primary, groups, blockColumns
end

function GF.GetVisibleLayoutCount(kind, count, conf)
    count = math_floor((tonumber(count) or 0) + 0.5)
    if count < 1 then return count end
    if not IsRaidLikeKind(kind) then return count end

    conf = conf or (GF.GetConf and GF.GetConf(kind)) or {}
    if conf and conf.preserveRaidGroups == true then
        local groups = math_floor((tonumber(conf.maxColumns) or 8) + 0.5)
        if groups < 1 then groups = 1 elseif groups > 8 then groups = 8 end
        return math_min(count, groups * 5)
    end

    local upc = math_floor((tonumber(conf and conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end
    local columns = math_floor((tonumber(conf and conf.maxColumns) or 8) + 0.5)
    if columns < 1 then columns = 1 elseif columns > 40 then columns = 40 end
    return math_min(count, upc * columns)
end

function GF.GetPreservedRaidGridMetrics(kind, count)
    local conf = GF.GetConf(kind)
    local w, h, sp = GF.GetScaledFrameMetrics(kind)
    local growth = conf.growth or "DOWN"

    count = tonumber(count) or 0
    local upc, primary, maxGroups, blockColumns = GetRaidGroupLayoutParts(conf, count)
    local groups = (count > 0) and math_ceil(count / 5) or maxGroups
    if groups < 1 then groups = 1 end
    groups = math_min(maxGroups, groups)

    local blockW, blockH
    if growth == "DOWN" or growth == "UP" then
        blockW = blockColumns * w + math_max(0, blockColumns - 1) * sp
        blockH = primary      * h + math_max(0, primary - 1) * sp
    else
        blockW = primary      * w + math_max(0, primary - 1) * sp
        blockH = blockColumns * h + math_max(0, blockColumns - 1) * sp
    end

    local totalW, totalH
    if growth == "DOWN" or growth == "UP" then
        totalW = groups * blockW + math_max(0, groups - 1) * sp
        totalH = blockH
    else
        totalW = blockW
        totalH = groups * blockH + math_max(0, groups - 1) * sp
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

    return dx, dy, totalW, totalH, w, h, sp, growth, upc, count, firstDX, firstDY, primary, groups, blockColumns, blockW, blockH
end

function GF.GetGridMetrics(kind, count)
    local conf = GF.GetConf(kind)
    if IsRaidLikeKind(kind) and conf.preserveRaidGroups == true and GF.GetPreservedRaidGridMetrics then
        return GF.GetPreservedRaidGridMetrics(kind, count)
    end

    local w, h, sp = GF.GetScaledFrameMetrics(kind)
    local growth = conf.growth or "DOWN"
    local upc = math_floor((tonumber(conf.unitsPerColumn) or 5) + 0.5)
    if upc < 1 then upc = 1 elseif upc > 40 then upc = 40 end

    count = tonumber(count) or 0
    if count < 1 then count = (IsRaidLikeKind(kind) and 10 or 5) end

    local numCols = math_ceil(count / upc)
    if numCols < 1 then numCols = 1 end
    -- Non-preserve raid columns use maxColumns as a real display cap. The wider
    -- column cap preserves imported/manual values above the menu slider range.
    local columnCap = IsRaidLikeKind(kind) and 40 or 8
    local maxDefault = IsRaidLikeKind(kind) and 8 or numCols
    local maxColumns = math_floor((tonumber(conf.maxColumns) or maxDefault) + 0.5)
    if maxColumns < 1 then maxColumns = 1 elseif maxColumns > columnCap then maxColumns = columnCap end
    if numCols > maxColumns then numCols = maxColumns end
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

--- GRID_CENTER_V1 was rendered by shifting an already full-size header by the
--- origin-to-center delta. That made the stored point a count-dependent corner
--- in practice. Convert only when a group is actually about to be displayed so
--- the current live/preview count preserves the exact legacy on-screen bounds.
function GF.EnsureStableGridPosition(kind, count, conf)
    conf = conf or (GF.GetConf and GF.GetConf(kind))
    if type(conf) ~= "table" then return false end
    if conf.positionMode == STABLE_GRID_POSITION_MODE then return false end
    if conf.positionMode ~= LEGACY_GRID_POSITION_MODE then return false end

    local dx, dy = GF.GetGridMetrics(kind, count)
    local fallbackX = IsRaidLikeKind(kind) and -500 or -400
    conf.offsetX = (tonumber(conf.offsetX) or fallbackX) - (tonumber(dx) or 0)
    conf.offsetY = (tonumber(conf.offsetY) or 0) - (tonumber(dy) or 0)
    conf.positionMode = STABLE_GRID_POSITION_MODE
    return true
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
    if conf.positionMode == LEGACY_GRID_POSITION_MODE or conf.positionMode == STABLE_GRID_POSITION_MODE then return end
    local dx, dy = GF.GetGridMetrics(kind, GetMigrationCount(kind, conf))
    conf.offsetX = (conf.offsetX or (IsRaidLikeKind(kind) and -500 or -400)) + dx
    conf.offsetY = (conf.offsetY or 0) + dy
    conf.positionMode = LEGACY_GRID_POSITION_MODE
end

---
--- Migration: showHP boolean - 3-slot text
---
local function MigrateShowHPTo3Slot(conf)
    if not conf then return end
    --- Only migrate if old showHP exists and no 3-slot keys set yet
    if conf.showHP ~= nil and conf.textCenter == nil and conf.textLeft == nil and conf.textRight == nil then
        if conf.showHP then
            conf.textCenter = "PERCENT"
        else
            conf.textCenter = "NONE"
        end
        conf.textLeft  = "NONE"
        conf.textRight = "NONE"
    end
    --- Remove legacy key after migration
    conf.showHP = nil
end

---
--- Migration: GF-local highlight keys - unified hl* with hlOverride
---
local HIGHLIGHT_MIGRATION_KEYS = {
    aggroHighlightSize    = "hlAggroSize",
    aggroHighlightOffset  = "hlAggroOffset",
    aggroHighlightLayer   = "hlAggroLayer",
    targetBorderSize      = "hlTargetSize",
    targetHighlightOffset = "hlTargetOffset",
    targetHighlightLayer  = "hlTargetLayer",
    hoverHighlightSize    = "hlHoverSize",
    hoverHighlightOffset  = "hlHoverOffset",
}

local function MigrateHighlightToUnified(conf)
    if not conf then return end
    if conf._hlMigrated then return end
    --- Migrate old GF-local geometry keys to hlOverride scope
    local hadCustom = false
    for oldKey, newKey in pairs(HIGHLIGHT_MIGRATION_KEYS) do
        if conf[oldKey] ~= nil then
            conf[newKey] = conf[oldKey]
            hadCustom = true
        end
    end
    if hadCustom then conf.hlOverride = true end
    conf._hlMigrated = true
end

--- Corner Indicators: migrate dropped categories ("boss", "missing") - "none".
--- These categories no longer work in 12.0 due to secret-tagged isRaid/spellId
--- on debuffs/buffs cast by other players. Replaced with "aggro" + "custom".
--- One-shot migration (idempotent via _ciMigratedV2 stamp).
local CI_DROPPED_CATEGORIES = { boss = true, missing = true }
local CI_CUSTOM_KEYS = { "ciCustomTL", "ciCustomTR", "ciCustomBL", "ciCustomBR", "ciCustomC" }
local CI_SLOT_KEYS = { "ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC" }

--- Always-run defensive sweep: ensure ciCustom* slots are either a table or nil.
--- A previous build may have stamped a non-table value (e.g. number, string)
--- into one of these keys; the new option UI indexes them as tables and would
--- crash on a number/string. Cheap to run every login.
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
    for _, k in ipairs(CI_SLOT_KEYS) do
        if CI_DROPPED_CATEGORIES[conf[k]] then conf[k] = "none" end
    end
    --- Drop legacy boss color keys (replaced by aggro color in CI v2 schema)
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

local function RemoveLayoutPresetState(conf)
    if type(conf) ~= "table" then return end
    conf.layoutIntentPreset = nil
end

local function ResolveLegacyHealPredictionEnabled()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if type(gen) ~= "table" then return false end
    if gen.healPredEnabled ~= nil then return gen.healPredEnabled == true end
    if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
    if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    return false
end

local function NormalizeHealPredictionAnchorMode(value, fallback)
    local mode = tonumber(value) or fallback or 3
    if mode < 1 or mode > 5 then mode = fallback or 3 end
    return mode
end

local function ResolveSharedHealPredictionAnchorMode()
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    return NormalizeHealPredictionAnchorMode(gen and gen.healPredAnchorMode, 3)
end

local function MigrateHealPredictionOwnership(conf)
    if type(conf) ~= "table" then return end
    if conf.healPredEnabled == nil and conf.healPrediction ~= nil then
        conf.healPredEnabled = conf.healPrediction == true
    end
    if conf.healPredEnabled == nil then
        conf.healPredEnabled = ResolveLegacyHealPredictionEnabled()
    end
    conf.healPredAnchorMode = NormalizeHealPredictionAnchorMode(conf.healPredAnchorMode, 3)
    if conf._healPredBarsScopeMigrated ~= true then
        local sharedEnabled = ResolveLegacyHealPredictionEnabled()
        local localEnabled = conf.healPredEnabled == true
        local sharedAnchor = ResolveSharedHealPredictionAnchorMode()
        local localAnchor = NormalizeHealPredictionAnchorMode(conf.healPredAnchorMode, 3)
        if localEnabled ~= sharedEnabled or (localEnabled and localAnchor ~= sharedAnchor) then
            conf.hlOverride = true
        end
        conf._healPredBarsScopeMigrated = true
    end
    conf.healPrediction = nil
end

local function MigrateTextureOverrideOwnership(conf)
    if type(conf) ~= "table" or conf._barTextureOverrideMigrated == true then return end
    if (type(conf.barTexture) == "string" and conf.barTexture ~= "")
        or (type(conf.barBackgroundTexture) == "string" and conf.barBackgroundTexture ~= "")
        or (type(conf.barBgTexture) == "string" and conf.barBgTexture ~= "") then
        conf.hlOverride = true
    end
    conf._barTextureOverrideMigrated = true
end

---
--- DB init
---
local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        end
    end
end

local function NormalizeFontField(conf)
    if type(conf) ~= "table" then return end
    conf.fontKey = nil
    conf.nameShortenOverride = nil
    conf._msufGFNameTruncationOverride = nil
end

local GF_NATIVE_AURA_RENDERER = "NATIVE_12_1"
local GF_CUSTOM_AURA_RENDERER = "CUSTOM"
local GF_AURA_PROFILE_MODEL_REVISION = 1
local GF_RETIRED_AURA_ROOT_KEYS = {
    "aurasEnabled", "auraMaxIcons", "auraIconSize", "auraAnchor",
    "auraGrowthX", "auraGrowthY", "auraSpacing", "auraPerRow",
    "privateAurasEnabled", "privateAuraMax", "privateAuraSize",
    "privateAuraAnchor", "privateAuraX", "privateAuraY", "privateAuraCountdown",
}
local function ClearRetiredAuraRootFields(conf)
    if type(conf) ~= "table" then return false end
    local changed = false
    for i = 1, #GF_RETIRED_AURA_ROOT_KEYS do
        local key = GF_RETIRED_AURA_ROOT_KEYS[i]
        if conf[key] ~= nil then
            conf[key] = nil
            changed = true
        end
    end
    if conf._auraMigV2 ~= nil then
        conf._auraMigV2 = nil
        changed = true
    end
    return changed
end
local GF_BLIZZARD_AURA_TYPE_DEFAULTS = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
}
local GF_AURA_GROUP_KEYS = { "buff", "debuff", "externals" }
local RepairAuraFilters, RepairAuraV2

local function NormalizeAuraRenderer(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    local auras = conf.auras
    if auras.renderer ~= GF_CUSTOM_AURA_RENDERER and auras.renderer ~= GF_NATIVE_AURA_RENDERER then
        auras.renderer = GF_NATIVE_AURA_RENDERER
    end
    if auras.renderer == GF_NATIVE_AURA_RENDERER then
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        for key, value in pairs(GF_BLIZZARD_AURA_TYPE_DEFAULTS) do
            if auras.blizzardTypes[key] == nil then
                auras.blizzardTypes[key] = value
            end
        end
        if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
        if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
        if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
        if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
        if auras.blizzardDispelBorder == nil then auras.blizzardDispelBorder = false end
        if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
        if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
        if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
    end
end

--- PERF: Group runtime has several defensive DB boundaries. A completed repair
--- remains valid across frames until an actual DB mutation invalidates it; table
--- identity checks still catch profile/root replacements without a scan.
local ensureDBReady = false
local ensureDBRoot, ensureDBParty, ensureDBRaid, ensureDBMythic, ensureDBPriority

local function MigrateSplitDNDStatusText(conf)
    if type(conf) ~= "table" or conf.statusDNDText ~= nil or conf.statusAFKText == nil then return end
    conf.statusDNDText = conf.statusAFKText
    conf.statusDNDTextSize = conf.statusAFKTextSize
    conf.statusDNDTextAnchor = conf.statusAFKTextAnchor
    conf.statusDNDTextLayer = conf.statusAFKTextLayer
    conf.statusDNDOffsetX = conf.statusAFKOffsetX
    conf.statusDNDOffsetY = conf.statusAFKOffsetY
end

-- RC1-RC8 briefly exported the Group page's option tables through one
-- positional key list. One missing key shifted every following dropdown onto
-- the next domain. Keep repair here, at the existing cold DB boundary, so bad
-- selections from those builds cannot leak into runtime specs or reappear
-- after a profile import. Stable EnsureDB calls still return before any scan.
local GROUP_MENU_DOMAIN_REPAIR = {
    revision = 1,
    nameAnchors = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
    },
    framePoints = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    },
    sortModes = { INDEX = true, NAME = true, ROLE = true, GROUP = true, GROUP_ROLE = true },
    powerTextModes = {
        NONE = true, PERCENT = true, CURRENT = true, FULLVALUE = true, MAX = true, DEFICIT = true,
        CURMAX = true, CURPERCENT = true, CURMAXPERCENT = true, MAXPERCENT = true,
        PERCENTCUR = true, PERCENTMAX = true, PERCENTCURMAX = true,
    },
    dispelOverlayStyles = { FULL = true, BOTTOM = true, TOP = true, LEFT = true, RIGHT = true },
    debuffStripeEdges = { BOTTOM = true, TOP = true },
    placedIndicatorTypes = { icon = true, square = true, bar = true, number = true },
    frameEffectTypes = { healthtint = true, border = true, glow = true, pulse = true, namecolor = true },
    -- Timed full-frame effects cannot be driven reliably from secret 12.1
    -- group auras. Retained profile values fall back to the active-aura path.
    frameEffectTimings = { always = true },
    iconEffectTypes = { none = true, glow = true },
    spellGrowth = { RIGHTDOWN = true, LEFTDOWN = true, RIGHTUP = true, LEFTUP = true },
    shiftedNameAnchors = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true },
    shiftedAnchorTargets = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    },
    shiftedDelimiters = { LEFT = true, CENTER = true, RIGHT = true },
    statusAnchorFields = {
        "roleIconAnchor", "leaderIconAnchor", "assistIconAnchor", "raidMarkerAnchor",
        "readyCheckAnchor", "summonAnchor", "resurrectAnchor", "pvpIconAnchor", "phaseAnchor",
        "statusTextAnchor", "statusGhostTextAnchor", "statusAFKTextAnchor", "statusAFKTimerTextAnchor", "statusDNDTextAnchor",
        "groupNumberAnchor", "dispelSymbolAnchor",
    },
    auraDefaults = {
        buff = { anchor = "BOTTOMRIGHT", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
        debuff = { anchor = "TOPLEFT", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
        externals = { anchor = "CENTER", cooldownAnchor = "CENTER", stackAnchor = "BOTTOMRIGHT" },
    },
}

function GROUP_MENU_DOMAIN_REPAIR.EnumField(owner, key, allowed, fallback)
    local value = owner and owner[key]
    if value ~= nil and not allowed[value] then owner[key] = fallback end
end

function GROUP_MENU_DOMAIN_REPAIR.SpellIndicators(conf)
    local si = conf and conf.spellIndicators
    local specs = type(si) == "table" and si.specs or nil
    if type(specs) ~= "table" then return end
    for _, spec in pairs(specs) do
        if type(spec) == "table" then
            for _, entry in pairs(spec) do
                if type(entry) == "table" then
                    local placed = entry.placed
                    if type(placed) == "table" then
                        if not GROUP_MENU_DOMAIN_REPAIR.placedIndicatorTypes[placed.type] then
                            entry.placed = false
                        else
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "anchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, "TOPLEFT")
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "growth", GROUP_MENU_DOMAIN_REPAIR.spellGrowth, "RIGHTDOWN")
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(placed, "iconEffect", GROUP_MENU_DOMAIN_REPAIR.iconEffectTypes, "none")
                        end
                    end
                    local frame = entry.frame
                    if type(frame) == "table" then
                        if not GROUP_MENU_DOMAIN_REPAIR.frameEffectTypes[frame.type] then
                            entry.frame = false
                        else
                            GROUP_MENU_DOMAIN_REPAIR.EnumField(frame, "timing", GROUP_MENU_DOMAIN_REPAIR.frameEffectTimings, "always")
                        end
                    end
                end
            end
        end
    end
end

function GROUP_MENU_DOMAIN_REPAIR.Conf(conf, defaults, isRaid)
    if type(conf) ~= "table" then return end
    defaults = defaults or PARTY_DEFAULTS

    -- TOP*/BOTTOM* were the four aura-corner choices accidentally shown for
    -- Name. Before the fix every one rendered through the LEFT fallback, so a
    -- one-time reset to LEFT preserves the user's actual on-screen geometry.
    if conf._menuSpecDomainRepair ~= GROUP_MENU_DOMAIN_REPAIR.revision then
        if GROUP_MENU_DOMAIN_REPAIR.shiftedNameAnchors[conf.nameAnchor] then conf.nameAnchor = defaults.nameAnchor or "LEFT" end
        if GROUP_MENU_DOMAIN_REPAIR.shiftedAnchorTargets[conf.anchorToFrame] then conf.anchorToFrame = nil end
        conf._menuSpecDomainRepair = GROUP_MENU_DOMAIN_REPAIR.revision
    end

    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "nameAnchor", GROUP_MENU_DOMAIN_REPAIR.nameAnchors, defaults.nameAnchor or "LEFT")
    if not GROUP_MENU_DOMAIN_REPAIR.sortModes[conf.sortMode] then
        if isRaid == true and conf.preserveRaidGroups == true then
            conf.sortMode = "GROUP"
        elseif conf.sortByRole == true then
            conf.sortMode = "ROLE"
        elseif conf.sortByName == true then
            conf.sortMode = "NAME"
        else
            conf.sortMode = "INDEX"
        end
    end
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextLeft", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextLeft or "NONE")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextCenter", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextCenter or "PERCENT")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "powerTextRight", GROUP_MENU_DOMAIN_REPAIR.powerTextModes, defaults.powerTextRight or "NONE")
    if GROUP_MENU_DOMAIN_REPAIR.shiftedDelimiters[conf.textDelimiter] then conf.textDelimiter = defaults.textDelimiter or " / " end
    if GROUP_MENU_DOMAIN_REPAIR.shiftedDelimiters[conf.powerTextDelimiter] then conf.powerTextDelimiter = defaults.powerTextDelimiter or " / " end
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "dispelOverlayStyle", GROUP_MENU_DOMAIN_REPAIR.dispelOverlayStyles, defaults.dispelOverlayStyle or "FULL")
    GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, "debuffStripeEdge", GROUP_MENU_DOMAIN_REPAIR.debuffStripeEdges, defaults.debuffStripeEdge or "BOTTOM")

    for i = 1, #GROUP_MENU_DOMAIN_REPAIR.statusAnchorFields do
        local key = GROUP_MENU_DOMAIN_REPAIR.statusAnchorFields[i]
        GROUP_MENU_DOMAIN_REPAIR.EnumField(conf, key, GROUP_MENU_DOMAIN_REPAIR.framePoints, defaults[key] or "CENTER")
    end
    local auras = conf.auras
    if type(auras) == "table" then
        for lane, laneDefaults in pairs(GROUP_MENU_DOMAIN_REPAIR.auraDefaults) do
            local group = auras[lane]
            if type(group) == "table" then
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "anchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.anchor)
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "cooldownAnchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.cooldownAnchor)
                GROUP_MENU_DOMAIN_REPAIR.EnumField(group, "stackAnchor", GROUP_MENU_DOMAIN_REPAIR.framePoints, laneDefaults.stackAnchor)
            end
        end
    end
    GROUP_MENU_DOMAIN_REPAIR.SpellIndicators(conf)
end

local function MigratePortraitSizeMode(conf)
    if type(conf) ~= "table" then return end
    if conf.portraitSizeMode == "UNIFORM" or conf.portraitSizeMode == "SEPARATE" then return end
    -- Party's legacy compiler let either positive axis win even when the
    -- uniform Size field was also populated. Preserve that visible geometry.
    if (tonumber(conf.portraitWidth) or 0) > 0 or (tonumber(conf.portraitHeight) or 0) > 0 then
        conf.portraitSizeMode = "SEPARATE"
    else
        conf.portraitSizeMode = "UNIFORM"
    end
end

function GF.EnsureDB()
    local db = _G.MSUF_DB
    if not db then return end
    if ensureDBRoot == db
        and ensureDBParty == db.gf_party
        and ensureDBRaid == db.gf_raid
        and ensureDBMythic == db.gf_mythicraid
        and ensureDBPriority == db.gf_priority
    then
        if ensureDBReady then return end
        --- In-place menu/profile mutations are already visible through the
        --- stable tables. Defer structural repair until the first OOC boundary.
        if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    end
    local _partyFresh = type(db.gf_party) ~= "table"
    local _raidFresh  = type(db.gf_raid)  ~= "table"
    local _mythicFresh = type(db.gf_mythicraid) ~= "table"
    local _priorityFresh = type(db.gf_priority) ~= "table"
    if _partyFresh then db.gf_party = {} end
    if _raidFresh  then db.gf_raid  = {} end
    if _mythicFresh then db.gf_mythicraid = {} end
    if _priorityFresh then db.gf_priority = {} end
    --- MSUF 6.0 no longer registers aura buttons with Masque. Clear only our
    --- retired profile flag; Masque itself and its other addon groups remain
    --- completely untouched.
    db.gf_party.masqueEnabled = nil
    db.gf_raid.masqueEnabled = nil
    db.gf_mythicraid.masqueEnabled = nil
    NormalizeFontField(db.gf_party)
    NormalizeFontField(db.gf_raid)
    NormalizeFontField(db.gf_mythicraid)
    MigrateShowHPTo3Slot(db.gf_party)
    MigrateShowHPTo3Slot(db.gf_raid)
    MigrateShowHPTo3Slot(db.gf_mythicraid)
    MigrateHighlightToUnified(db.gf_party)
    MigrateHighlightToUnified(db.gf_raid)
    MigrateHighlightToUnified(db.gf_mythicraid)
    --- Defensive: type-guard ciCustom* fields BEFORE the one-shot CI migration
    --- (which may already be stamped done from a previous build).
    CleanupCornerCustomTypes(db.gf_party)
    CleanupCornerCustomTypes(db.gf_raid)
    CleanupCornerCustomTypes(db.gf_mythicraid)
    MigrateCornerIndicators(db.gf_party)
    MigrateCornerIndicators(db.gf_raid)
    MigrateCornerIndicators(db.gf_mythicraid)
    RemoveGroupPetFrameConfig(db.gf_party)
    RemoveGroupPetFrameConfig(db.gf_raid)
    RemoveGroupPetFrameConfig(db.gf_mythicraid)
    RemoveLayoutPresetState(db.gf_party)
    RemoveLayoutPresetState(db.gf_raid)
    RemoveLayoutPresetState(db.gf_mythicraid)
    MigrateHealPredictionOwnership(db.gf_party)
    MigrateHealPredictionOwnership(db.gf_raid)
    MigrateHealPredictionOwnership(db.gf_mythicraid)
    MigrateTextureOverrideOwnership(db.gf_party)
    MigrateTextureOverrideOwnership(db.gf_raid)
    MigrateTextureOverrideOwnership(db.gf_mythicraid)
    MigrateSplitDNDStatusText(db.gf_party)
    MigrateSplitDNDStatusText(db.gf_raid)
    MigrateSplitDNDStatusText(db.gf_mythicraid)
    MigratePortraitSizeMode(db.gf_party)
    applyDefaults(db.gf_party, PARTY_DEFAULTS)
    applyDefaults(db.gf_raid,  RAID_DEFAULTS)
    applyDefaults(db.gf_mythicraid, MYTHIC_RAID_DEFAULTS)
    applyDefaults(db.gf_priority, PRIORITY_DEFAULTS)
    MigrateGroupPositionToGridCenter(db.gf_party, "party")
    MigrateGroupPositionToGridCenter(db.gf_raid, "raid")
    MigrateGroupPositionToGridCenter(db.gf_mythicraid, "mythicraid")
    --- Migrate flat aura keys to nested tables
    if GF.MigrateAuraConfig then
        GF.MigrateAuraConfig(db.gf_party, false)
        GF.MigrateAuraConfig(db.gf_raid, true)
        GF.MigrateAuraConfig(db.gf_mythicraid, true)
    end
    GROUP_MENU_DOMAIN_REPAIR.Conf(db.gf_party, PARTY_DEFAULTS, false)
    GROUP_MENU_DOMAIN_REPAIR.Conf(db.gf_raid, RAID_DEFAULTS, true)
    GROUP_MENU_DOMAIN_REPAIR.Conf(db.gf_mythicraid, MYTHIC_RAID_DEFAULTS, true)
    NormalizeAuraRenderer(db.gf_party)
    NormalizeAuraRenderer(db.gf_raid)
    NormalizeAuraRenderer(db.gf_mythicraid)
    --- Ensure spell filter fields exist on each aura sub-group.
    RepairAuraFilters = RepairAuraFilters or function(conf)
        --- Migrate: remove legacy absorb/heal defaults that blocked global override
        if conf.absorbEnabled == true and not conf._absorbMigrated then
            conf.absorbEnabled = nil
            conf._absorbMigrated = true
        end
        if conf.healAbsorbEnabled == true and not conf._absorbMigrated then
            conf.healAbsorbEnabled = nil
        end
        --- Remove absorb keys that shadow general when hlOverride is off
        if not conf.hlOverride then
            conf.absorbEnabled = nil
            conf.absorbTextMode = nil
            conf.enableAbsorbBar = nil
        end
        if type(conf.auras) == "table" then
            for _, gk in ipairs(GF_AURA_GROUP_KEYS) do
                local g = conf.auras[gk]
                if type(g) == "table" then
                    --- Migrate v3: old spellFilter/spellList - new filterToken/blacklistCats
                    if not g._filterMigV3 then
                        g._filterMigV3 = true
                        --- Convert old filterMode - new filterToken
                        if g.filterMode and not g.filterToken then
                            local fm = g.filterMode
                            if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
                                g.filterToken = "ALL"
                            elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
                                g.filterToken = fm
                            elseif fm == "NOT_PLAYER" then
                                g.filterToken = "ALL"
                            end
                        end
                        --- Convert old spellFilter+spellList - blacklistCats
                        if g.spellFilter == "BLACKLIST" and type(g.spellList) == "table" then
                            if type(g.blacklist) ~= "table" then g.blacklist = {} end
                            if type(g.blacklist.spells) ~= "table" then g.blacklist.spells = {} end
                            for spellID, enabled in pairs(g.spellList) do
                                if enabled == true then
                                    local id = tonumber(spellID)
                                    if id then g.blacklist.spells[tostring(math.floor(id + 0.5))] = true end
                                end
                            end
                            if not g.blacklistCats then g.blacklistCats = {} end
                            --- Check if old spellList contained Sated spells
                            if g.spellList[57723] or g.spellList[57724] or g.spellList[80354] then
                                g.blacklistCats.SATED = true
                            end
                            if g.spellList[26013] or g.spellList[71041] then
                                g.blacklistCats.DESERTER = true
                            end
                        end
                        --- Clean up legacy keys
                        g.spellFilter = nil
                        g.spellList   = nil
                        g.filterMode  = nil
                    end
                    --- Ensure new keys exist with defaults
                    if g.filterToken == nil then
                        g.filterToken = (gk == "externals") and "RAID" or "ALL"
                    end
                    --- This runs only during the cold EnsureDB repair pass.
                    --- Retired/unknown native filters must not remain active
                    --- invisibly after their controls were removed from Menu2.
                    if gk == "buff" or gk == "debuff" then
                        local AF = GF.AuraFilter or _G.MSUF_GF_AuraFilter
                        local normalize = AF and AF.NormalizeFilterToken
                        if type(normalize) == "function" then
                            g.filterToken = normalize(gk, g.filterToken)
                        end
                    end
                    if type(g.blacklistCats) ~= "table" then
                        --- Apply sensible defaults from AuraFilter module
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
                    if type(g.blacklist) ~= "table" then g.blacklist = {} end
                    if type(g.blacklist.spells) ~= "table" then g.blacklist.spells = {} end
                    if g.showDurationBar == nil then g.showDurationBar = false end
                    if g.durationBarHeight == nil then g.durationBarHeight = 2 end
                    if g.durationBarDisplay ~= "OVERLAY" then g.durationBarDisplay = "BAR_ONLY" end
                    if g.durationBarPosition ~= "TOP" then g.durationBarPosition = "BOTTOM" end
                    if g.durationBarDirection ~= "ELAPSED" then g.durationBarDirection = "REMAINING" end
                end
            end
        end
    end
    RepairAuraFilters(db.gf_party)
    RepairAuraFilters(db.gf_raid)
    RepairAuraFilters(db.gf_mythicraid)
    --- Migration v2: force-enable auras + defensives (showstopper fix)
    RepairAuraV2 = RepairAuraV2 or function(conf)
        if type(conf.auras) == "table"
            and tonumber(conf.auras.profileModelRevision) ~= GF_AURA_PROFILE_MODEL_REVISION
            and not conf._auraMigV2 then
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
    RepairAuraV2(db.gf_party)
    RepairAuraV2(db.gf_raid)
    RepairAuraV2(db.gf_mythicraid)
    --- Update cached conf references
    GF.InvalidateConfCache(true)

    --- Obsolete role-layout bootstrap flags from older builds.
    db._gfDefaultPresetApplied = nil
    GF._pendingDefaultPreset = nil

    if GF.SeedCurrentSpecSpellIndicatorDefaults and not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects then
        GF.SeedCurrentSpecSpellIndicatorDefaults()
    end

    ensureDBRoot = db
    ensureDBParty, ensureDBRaid, ensureDBMythic, ensureDBPriority = db.gf_party, db.gf_raid, db.gf_mythicraid, db.gf_priority
    ensureDBReady = true
end

---
--- Config resolution (cached - eliminates _G.MSUF_DB + type() per call)
---
local _confParty, _confRaid, _confMythicRaid, _confPriority

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

--- Blizzard treats a live Arena as Party scope even when the roster APIs also
--- report Raid. Keep that precedence in one shared cold-path helper so runtime,
--- Edit Mode, previews, Priority Frames, borders, and native-frame ownership all
--- select the same saved configuration. Brawls deliberately retain their normal
--- roster scope, matching Blizzard_GroupFrameVisibility.
function GF.IsArenaPartyContext()
    local isActiveArena = _G.IsActiveBattlefieldArena
    if type(isActiveArena) ~= "function" or isActiveArena() ~= true then
        return false
    end
    local pvp = _G.C_PvP
    local isInBrawl = type(pvp) == "table" and pvp.IsInBrawl or nil
    return type(isInBrawl) ~= "function" or isInBrawl() ~= true
end

function GF.GetLiveGroupKind()
    if GF.IsArenaPartyContext and GF.IsArenaPartyContext() then
        return "party"
    end
    if _G.IsInRaid and _G.IsInRaid() then
        return GF.GetLiveRaidKind and GF.GetLiveRaidKind() or "raid"
    end
    if _G.IsInGroup and _G.IsInGroup() then
        return "party"
    end
    return nil
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

--- MSUF <= 5.57 stored early Group Frame aura settings as flat fields. The
--- 5.57 runtime migrated them through GF.MigrateAuraConfig, but that owner no
--- longer exists in 6.0. Keep the migration in the DB layer so it runs for
--- SavedVariables startup, profile switches, full imports, and group-only
--- snapshot imports before the compiled Group Frame spec consumes the data.
local function LegacyAuraGrowth(conf, fallback)
    local x = tostring(conf and conf.auraGrowthX or ""):upper()
    local y = tostring(conf and conf.auraGrowthY or ""):upper()
    if x == "UP" or x == "DOWN" then return x end
    if x ~= "LEFT" and x ~= "RIGHT" then return fallback end
    if y ~= "UP" and y ~= "DOWN" then return x .. (fallback:find("UP", 1, true) and "UP" or "DOWN") end
    return x .. y
end

local LEGACY_BUFF_DEFAULTS = {
    enabled = true, anchor = "BOTTOMRIGHT", growth = "LEFTUP",
    x = 0, y = 0, size = 22, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 4, max = 6, spacing = 1,
    layer = 5, filterMode = "RAID_PLAYER",
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
    showStacks = true, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local LEGACY_DEBUFF_DEFAULTS = {
    enabled = true, anchor = "TOPLEFT", growth = "RIGHTDOWN",
    x = 0, y = 0, size = 20, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 3, max = 6, spacing = 1,
    layer = 6, showDispelBorder = true,
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
    showStacks = true, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local LEGACY_EXTERNAL_DEFAULTS = {
    enabled = true, anchor = "CENTER", growth = "RIGHTDOWN",
    x = 0, y = 0, size = 28, iconScale = 100, iconZoom = 100, iconShape = "RECTANGLE", perRow = 3, max = 2, spacing = 1,
    layer = 7, autoBlacklistBuffs = true,
    showCooldownSwipe = true, showCooldown = true, cooldownAnchor = "CENTER",
    cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 10, cooldownOutline = "OUTLINE",
    showStacks = false, stackAnchor = "BOTTOMRIGHT",
    stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
}

local function CopyAuraDefaults(defaults)
    local copy = {}
    for key, value in pairs(defaults) do copy[key] = value end
    return copy
end

local function FillMissingAuraModel(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end
    local changed = false
    for key, value in pairs(src) do
        if dst[key] == nil then
            if type(value) == "table" then
                local copy = {}
                FillMissingAuraModel(copy, value)
                dst[key] = copy
            else
                dst[key] = value
            end
            changed = true
        elseif type(dst[key]) == "table" and type(value) == "table" then
            changed = FillMissingAuraModel(dst[key], value) or changed
        end
    end
    return changed
end

local function LegacyBuffDefaults()
    return CopyAuraDefaults(LEGACY_BUFF_DEFAULTS)
end

local function LegacyDebuffDefaults()
    return CopyAuraDefaults(LEGACY_DEBUFF_DEFAULTS)
end

local function LegacyExternalDefaults()
    return CopyAuraDefaults(LEGACY_EXTERNAL_DEFAULTS)
end

local function LegacyPrivateAuraDefaults()
    return {
        enabled = true, max = 4, size = 20, anchor = "TOPRIGHT",
        direction = "LEFT", spacing = 1, x = 0, y = 0, layer = 8,
        showCountdown = true, showNumbers = false,
        showDispelType = false, showDuration = false,
        durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
    }
end

local function FillMissingAuraFields(group, defaults)
    if type(group) ~= "table" then return end
    for key, value in pairs(defaults) do
        if group[key] == nil then group[key] = value end
    end
end

local function SpellIndicatorStyleDefaults(conf)
    local auras = type(conf) == "table" and conf.auras or nil
    local buff = type(auras) == "table" and type(auras.buff) == "table" and auras.buff or LEGACY_BUFF_DEFAULTS
    local rootTooltip = type(auras) == "table" and auras.showTooltip
    local showTooltip
    if buff.showTooltip ~= nil then
        showTooltip = buff.showTooltip ~= false
    else
        showTooltip = rootTooltip ~= false
    end
    return {
        alpha = tonumber(buff.alpha) or 1,
        showTooltip = showTooltip,
        showCooldownText = buff.showCooldown ~= false,
        showCooldownSwipe = buff.showCooldownSwipe ~= false,
        cooldownSwipeReverse = buff.cooldownSwipeReverse == true,
        cooldownSize = tonumber(buff.cooldownSize) or 8,
        cooldownAnchor = buff.cooldownAnchor or "CENTER",
        cooldownX = tonumber(buff.cooldownX or buff.cooldownOffsetX) or 0,
        cooldownY = tonumber(buff.cooldownY or buff.cooldownOffsetY) or 0,
        cooldownDecimalSeconds = tonumber(buff.cooldownDecimalSeconds) or 3,
        showDurationBar = buff.showDurationBar == true,
        durationBarHeight = tonumber(buff.durationBarHeight) or 2,
        durationBarDisplay = buff.durationBarDisplay or "BAR_ONLY",
        durationBarPosition = buff.durationBarPosition or "BOTTOM",
        durationBarDirection = buff.durationBarDirection or "REMAINING",
        showStacks = buff.showStacks ~= false,
        stackSize = tonumber(buff.stackSize) or 10,
        stackAnchor = buff.stackAnchor or "BOTTOMRIGHT",
        stackX = tonumber(buff.stackX or buff.stackOffsetX) or 0,
        stackY = tonumber(buff.stackY or buff.stackOffsetY) or 0,
    }
end

--- Ensures the per-scope Spell Icon deep-Style block exists. Shape, border and
--- shadow always come from shared Buff Appearance and are intentionally absent.
function GF.EnsureSpellIndicatorStyle(conf)
    if type(conf) ~= "table" then return nil, false end
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, iconZoom = 100, iconScale = 100 }
    end
    local si = conf.spellIndicators
    local defaults = SpellIndicatorStyleDefaults(conf)
    local changed = false
    if type(si.style) ~= "table" then
        si.style = defaults
        changed = true
    else
        if si.style.iconShape ~= nil then
            si.style.iconShape = nil
            changed = true
        end
        for key, value in pairs(defaults) do
            if si.style[key] == nil then
                si.style[key] = value
                changed = true
            end
        end
    end
    return si.style, changed
end

function GF.MigrateAuraConfig(conf, isRaid)
    if type(conf) ~= "table" then return false end
    local changed = false
    if type(conf.auras) == "table"
        and tonumber(conf.auras.profileModelRevision) == GF_AURA_PROFILE_MODEL_REVISION then
        -- applyDefaults still carries the pre-Auras3 compatibility keys for
        -- genuinely legacy profiles. Never let those aliases become persisted
        -- state again once the canonical native model owns this scope.
        changed = ClearRetiredAuraRootFields(conf) or changed
        -- Native 6.0 profiles are completed only from the native factory
        -- model. Never run the legacy flat/Aura2 default fillers over them.
        local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalGroupAuraState)
            or _G.MSUF_CreateCanonicalGroupAuraState
        if type(createCanonical) == "function" then
            local state = createCanonical()
            state = type(state) == "table" and state[isRaid and "gf_raid" or "gf_party"] or nil
            if type(state) == "table" then
                changed = FillMissingAuraModel(conf.auras, state.auras) or changed
                if type(conf.privateAuras) ~= "table" and type(state.privateAuras) == "table" then
                    conf.privateAuras = {}
                    FillMissingAuraModel(conf.privateAuras, state.privateAuras)
                    changed = true
                end
                if type(conf.spellIndicators) ~= "table" and type(state.spellIndicators) == "table" then
                    conf.spellIndicators = {}
                    FillMissingAuraModel(conf.spellIndicators, state.spellIndicators)
                    changed = true
                end
            end
        end
        if type(GF.EnsureSpellIndicatorStyle) == "function" then
            local _, styleChanged = GF.EnsureSpellIndicatorStyle(conf)
            changed = styleChanged or changed
        end
        return changed
    end
    local hadFlatAuras = conf.aurasEnabled ~= nil and type(conf.auras) ~= "table"
    if hadFlatAuras then
        local buff = LegacyBuffDefaults()
        local debuff = LegacyDebuffDefaults()
        local enabled = conf.aurasEnabled ~= false
        local iconSize = tonumber(conf.auraIconSize) or 20
        local maxIcons = tonumber(conf.auraMaxIcons) or 4
        local perRow = tonumber(conf.auraPerRow) or maxIcons
        local spacing = tonumber(conf.auraSpacing) or 1
        buff.enabled = enabled
        buff.anchor = conf.auraAnchor or "BOTTOMLEFT"
        buff.growth = LegacyAuraGrowth(conf, buff.growth)
        buff.size, buff.max, buff.perRow, buff.spacing = iconSize, maxIcons, perRow, spacing
        debuff.size, debuff.max, debuff.spacing = iconSize, maxIcons, spacing
        conf.auras = {
            enabled = enabled,
            buff = buff,
            debuff = debuff,
            externals = LegacyExternalDefaults(),
        }
        -- This was an explicit user setting, not the old broken default that
        -- _auraMigV2 was designed to force on. Preserve an intentional false.
        conf._auraMigV2 = true
        conf.aurasEnabled = nil
        conf.auraMaxIcons = nil
        conf.auraIconSize = nil
        conf.auraAnchor = nil
        conf.auraGrowthX = nil
        conf.auraGrowthY = nil
        conf.auraSpacing = nil
        conf.auraPerRow = nil
        changed = true
    end
    if type(conf.auras) ~= "table" then
        local buff, debuff, externals = LegacyBuffDefaults(), LegacyDebuffDefaults(), LegacyExternalDefaults()
        if isRaid == true then
            buff.size, buff.max, buff.perRow = 16, 3, 3
            debuff.size, debuff.max, debuff.perRow = 14, 3, 3
            externals.size, externals.max, externals.perRow = 24, 2, 2
        end
        conf.auras = { enabled = true, buff = buff, debuff = debuff, externals = externals }
        changed = true
    end
    if conf.privateAurasEnabled ~= nil and type(conf.privateAuras) ~= "table" then
        local private = LegacyPrivateAuraDefaults()
        private.enabled = conf.privateAurasEnabled ~= false
        private.max = tonumber(conf.privateAuraMax) or 4
        private.size = tonumber(conf.privateAuraSize) or 20
        private.anchor = conf.privateAuraAnchor or "TOPRIGHT"
        private.x = tonumber(conf.privateAuraX) or 0
        private.y = tonumber(conf.privateAuraY) or 0
        private.showCountdown = conf.privateAuraCountdown ~= false
        conf.privateAuras = private
        conf.privateAurasEnabled = nil
        conf.privateAuraMax = nil
        conf.privateAuraSize = nil
        conf.privateAuraAnchor = nil
        conf.privateAuraX = nil
        conf.privateAuraY = nil
        conf.privateAuraCountdown = nil
        changed = true
    elseif type(conf.privateAuras) ~= "table" then
        conf.privateAuras = LegacyPrivateAuraDefaults()
        changed = true
    end
    if type(conf.auras.buff) ~= "table" then conf.auras.buff = LegacyBuffDefaults(); changed = true end
    if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = LegacyDebuffDefaults(); changed = true end
    if type(conf.auras.externals) ~= "table" then conf.auras.externals = LegacyExternalDefaults(); changed = true end
    if conf.auras.iconZoom == nil then conf.auras.iconZoom = 100; changed = true end
    local legacyIconZoom = tonumber(conf.auras.iconZoom) or 100
    if conf.auras.buff.iconZoom == nil then conf.auras.buff.iconZoom = legacyIconZoom; changed = true end
    if conf.auras.debuff.iconZoom == nil then conf.auras.debuff.iconZoom = legacyIconZoom; changed = true end
    FillMissingAuraFields(conf.auras.buff, LEGACY_BUFF_DEFAULTS)
    FillMissingAuraFields(conf.auras.debuff, LEGACY_DEBUFF_DEFAULTS)
    FillMissingAuraFields(conf.auras.externals, LEGACY_EXTERNAL_DEFAULTS)
    if type(conf.spellIndicators) ~= "table" then
        conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9, iconZoom = 100, iconScale = 100 }
        changed = true
    end
    if conf.spellIndicators.iconZoom == nil then conf.spellIndicators.iconZoom = 100; changed = true end
    if conf.spellIndicators.iconScale == nil then conf.spellIndicators.iconScale = 100; changed = true end
    local _, spellStyleChanged = GF.EnsureSpellIndicatorStyle(conf)
    changed = spellStyleChanged or changed
    return changed
end

function GF.GetPriorityConf()
    return _confPriority or PRIORITY_DEFAULTS
end

--- Call after any DB mutation (EnsureDB, profile swap, options apply). Internal
--- cache refreshes may preserve the completed DB repair with keepDBReady=true.
function GF.InvalidateConfCache(keepDBReady)
    if keepDBReady ~= true then
        ensureDBReady = false
    end
    local db = _G.MSUF_DB
    if not db then
        _confParty, _confRaid, _confMythicRaid, _confPriority = nil, nil, nil, nil
        return
    end
    _confParty = (type(db.gf_party) == "table" and db.gf_party) or nil
    _confRaid  = (type(db.gf_raid)  == "table" and db.gf_raid)  or nil
    _confMythicRaid = (type(db.gf_mythicraid) == "table" and db.gf_mythicraid) or nil
    _confPriority = (type(db.gf_priority) == "table" and db.gf_priority) or nil
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
    local createProfile = (type(MSUF) == "table" and MSUF.MSUF_CreateFactoryDefaultProfile) or _G.MSUF_CreateFactoryDefaultProfile
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
    db.gf_priority = db.gf_priority or {}

    local partyDefaults, raidDefaults, mythicRaidDefaults = GetFactoryGroupFrameDefaults()
    ResetConfToDefaults(db.gf_party, partyDefaults or PARTY_DEFAULTS)
    ResetConfToDefaults(db.gf_raid, raidDefaults or RAID_DEFAULTS)
    ResetConfToDefaults(db.gf_mythicraid, mythicRaidDefaults or MYTHIC_RAID_DEFAULTS)
    ResetConfToDefaults(db.gf_priority, PRIORITY_DEFAULTS)

    GF.InvalidateConfCache()
    GF.EnsureDB()

    if GF.RefreshAll then GF.RefreshAll() end

    return true
end

---
--- Raid Layout Situations
--- Stores per-situation geometry overrides (Mythic / Normal-HC / Open World).
--- On situation change: save current - load target - refresh geometry.
--- Auto-detect via difficultyID on PLAYER_ENTERING_WORLD.
---
local LAYOUT_GEO_KEYS = {
    "width", "height", "spacing", "growth", "groupGrowth",
    "unitsPerColumn", "maxColumns", "preserveRaidGroups",
    "point", "anchorPoint", "relativePoint", "offsetX", "offsetY", "positionMode",
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
    --- Situation slots created before GRID_BOUNDS_V2 did not persist a mode.
    --- Mark those offsets as legacy so the next real layout can preserve their
    --- visible position while converting with the correct live roster count.
    if slot.positionMode == nil then
        conf.positionMode = LEGACY_GRID_POSITION_MODE
    end
end

local function RefreshRaidLayoutKind(kind)
    if GF.RefreshGeometry then
        return GF.RefreshGeometry(kind)
    end
    local did = false
    if GF.RefreshHeaderLayout then
        did = GF.RefreshHeaderLayout(kind) or did
    end
    if GF.RefreshUnitBindings then
        did = GF.RefreshUnitBindings(kind) or did
    end
    if GF.RefreshVisuals then
        local dirty = GF.DIRTY_GEOMETRY or GF.DIRTY_LAYOUT or GF.DIRTY_VISUAL
        did = GF.RefreshVisuals(kind, dirty) or did
    end
    if did then
        return true
    end
    if GF.RefreshAll then
        return GF.RefreshAll()
    end
    return false
end

--- Switch active situation: save current - load new - rebuild
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
    RefreshRaidLayoutKind(kind)
    return true
end

--- Detect situation from instance difficulty
function GF.DetectRaidSituation()
    local _, _, difficultyID = GetInstanceInfo()
    if not difficultyID or difficultyID == 0 then return "openworld" end
    --- Mythic Raid = 16, Mythic+ = 8, Mythic Dungeon = 23
    if difficultyID == 16 or difficultyID == 8 or difficultyID == 23 then
        return "mythic"
    end
    --- Normal Raid = 14, Heroic Raid = 15, LFR = 17
    if difficultyID == 14 or difficultyID == 15 or difficultyID == 17 then
        return "normal"
    end
    --- Normal Dungeon = 1, Heroic Dungeon = 2, Timewalking = 24/33
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
    if conf and conf.hlOverride == true and conf.healPredEnabled ~= nil then
        return conf.healPredEnabled == true
    end
    return ResolveLegacyHealPredictionEnabled()
end

--- Alpha is now unified and coldpath: per-frame `hpBarAlpha` (HP fill) and
--- `hpBgAlpha` (background texture, baked into the bar background colour), plus the
--- `alphaExcludeTextPortrait` toggle. No combat-state alpha, no layer modes -- the
--- old GF.GetAlphaPair / GF.GetEffective*Alpha / GF.HasCombatAlpha helpers were
--- removed. HP-fill opacity is applied in MSUF_UF_Group_Visuals.UpdateHealthFade.

--- Group Frame power text toggle with legacy-profile compatibility.
--- `showPower` was historically used by GF as the power-text toggle; keep
--- reading it when the explicit `showPowerText` key does not exist yet.
function GF.IsPowerTextEnabled(kind, conf)
    conf = conf or GF.GetConf(kind)
    if not conf then return false end
    --- OR keeps old profiles/presets working even if only one of the two
    --- mirror keys exists or was written by older code. The setter below writes
    --- both keys, so explicit user toggles remain deterministic.
    return conf.showPowerText == true or conf.showPower == true
end

function GF.SetPowerTextEnabled(kind, enabled)
    local conf = GF.GetConf(kind)
    if not conf then return end
    local v = enabled and true or false
    conf.showPowerText = v
    conf.showPower = v --- legacy mirror so Edit Mode / old profiles stay in sync
end

--- Resolve a unified highlight value with scope override support.
--- GF-local (gf_party/gf_raid) can override general.hl* keys via hlOverride=true.
--- Falls through to MSUF_DB.general.hl* baseline.
local _HL_OUTLINE_MODE_KEYS = {
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

function GF.GetHighlightVal(kind, key)
    local conf = GF.GetConf(kind)
    local modeKey = _HL_OUTLINE_MODE_KEYS[key]
    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if conf.hlOverride then
        if modeKey then
            local enabled = OutlineModeToEnabled(conf[modeKey])
            if enabled ~= nil then return enabled end
        end
        if conf[key] ~= nil then
            if modeKey then
                local enabled = OutlineModeToEnabled(conf[key])
                if enabled ~= nil then return enabled end
            end
            return conf[key]
        end
    end
    if gen then
        if modeKey then
            local enabled = OutlineModeToEnabled(gen[modeKey])
            if enabled ~= nil then return enabled end
        end
        if gen[key] ~= nil then
            if modeKey then
                local enabled = OutlineModeToEnabled(gen[key])
                if enabled ~= nil then return enabled end
            end
            return gen[key]
        end
    end
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
    if t < 0 then t = 0 elseif t > 8 then t = 8 end
    return t
end

--- Resolve bar texture path (falls through to global MSUF bar texture)
function GF.ResolveBarTexture(kind)
    local conf = GF.GetConf(kind)
    local key = conf and conf.hlOverride == true and conf.barTexture or nil
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
    local key
    if conf and conf.hlOverride == true then
        key = conf.barBackgroundTexture
        if key == nil then key = conf.barBgTexture end
    end
    if key ~= nil then
        if key == "" then return GF.ResolveBarTexture(kind) end
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then return resolve(key) end
    end
    local fn = _G.MSUF_GetBarBackgroundTexture or _G.MSUF_GetBarTexture
    if type(fn) == "function" then return fn() end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

--- Resolve highlight border edge texture (LSM key - path, nil - WHITE8x8)
function GF.ResolveHighlightTexture(lsmKey)
    if not lsmKey or lsmKey == "" then return "Interface\\Buttons\\WHITE8x8" end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local p = LSM:Fetch("border", lsmKey, true)
        if p then return p end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

--- Resolve font path (global MSUF font family)
--- Check if GF scope has font override active
function GF.HasFontOverride(kind)
    local conf = GF.GetConf(kind)
    return conf.fontOverride == true
end

function GF.ResolveFontPath(kind)
    --- Font family is intentionally global. GF scopes may override style/color,
    --- but never the font face.
    local db = _G.MSUF_DB
    local gKey = db and db.general and db.general.fontKey
    if gKey and gKey ~= "" then
        local pathForKey = _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
        if type(pathForKey) == "function" then return ResolveFontPathSafe(pathForKey(gKey), 12, "") end
        local fn = _G.MSUF_GetFontPath or (MSUF and MSUF.MSUF_GetFontPath)
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
    local fn = MSUF.Castbars and MSUF.Castbars._GetFontPath
    if type(fn) == "function" then return ResolveFontPathSafe(fn(), 12, "") end
    return ResolveFontPathSafe("Fonts\\FRIZQT__.TTF", 12, "")
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

--- Resolve name text color (CLASS / CUSTOM / DEFAULT fallback to font color)
function GF.ResolveNameColor(kind, classToken)
    local conf = GF.GetConf(kind)

    --- When override active: use GF-local nameColorMode
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

    --- No override: use global nameClassColor boolean (shared with UF)
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

---
--- Icon style resolver
---
local MEDIA_PREFIX = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Icons\\"

local BLIZZARD_ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local BLIZZARD_ROLE_COORDS = {
    TANK    = { 0,    19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64,  20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}
local BLIZZARD_LEADER_TEX = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local BLIZZARD_ASSIST_TEX = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local BLIZZARD_RAID_MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local BLIZZARD_READY_TEXTURES = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local BLIZZARD_SUMMON_TEXTURES = {
    pending = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    accepted = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    declined = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}
local BLIZZARD_REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
local BLIZZARD_PHASE_TEXTURE = "Interface\\TargetingFrame\\UI-PhasingIcon"
local BLIZZARD_STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local BLIZZARD_PVP_TEXTURES = {
    Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
    FFA = "Interface\\TargetingFrame\\UI-PVP-Alliance",
}

local CUSTOM_STYLES = {
    CLASSIC       = "Classic",
    MIDNIGHT      = "Midnight",
    MSUF_ROLES    = "MSUFRoles",
    UXPRO         = "UXPro",
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

local CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX = {
    CLASSIC    = true,
    MIDNIGHT   = true,
    MSUF_ROLES = true,
}

local ROLE_ONLY_CUSTOM_STYLES = {
    MSUF_ROLES = true,
}

local ROLE_ONLY_ICON_FILES = {
    tank = true,
    healer = true,
    dps = true,
}

local STANDALONE_STATUS_ICON_FOLDERS = {
    { label = "Custom Glyphs", folder = "CustomGlyphs" },
    { label = "Custom Badges", folder = "CustomBadges" },
}

local ROLE_MAP = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local RAID_MARKER_FILES = {
    [1] = "raid_star",
    [2] = "raid_circle",
    [3] = "raid_diamond",
    [4] = "raid_triangle",
    [5] = "raid_moon",
    [6] = "raid_square",
    [7] = "raid_cross",
    [8] = "raid_skull",
}
local READY_FILES = {
    ready = "ready_ready",
    notready = "ready_notready",
    waiting = "ready_waiting",
}
local SUMMON_FILES = {
    [1] = "summon_pending",
    [2] = "summon_accepted",
    [3] = "summon_declined",
    pending = "summon_pending",
    accepted = "summon_accepted",
    declined = "summon_declined",
}
local PVP_FILES = {
    Alliance = "pvp_alliance",
    Horde = "pvp_horde",
    FFA = "pvp_ffa",
    alliance = "pvp_alliance",
    horde = "pvp_horde",
    ffa = "pvp_ffa",
}
local SIMPLE_STATUS_ICON_FILES = {
    incomingRes = "resurrect",
    resurrect = "resurrect",
    pvp = "pvp_alliance",
    phase = "phase",
    combat = "combat",
    resting = "resting",
    elite = "elite_elite",
    rare = "elite_rare",
    boss = "elite_boss",
}
local ADDON_ICON_STYLE_PREFIX = "ADDON:"
local REGISTERED_ICON_STYLE_PREFIX = "REGISTERED:"
local LSM_ICON_STYLE_PREFIX = "LSM:"
local ROLE_ICON_FILES = { "tank", "healer", "dps", "leader", "assist" }
local NON_ROLE_ICON_FILES = {
    "raid_star", "raid_circle", "raid_diamond", "raid_triangle",
    "raid_moon", "raid_square", "raid_cross", "raid_skull",
    "ready_ready", "ready_notready", "ready_waiting",
    "summon_pending", "summon_accepted", "summon_declined",
    "resurrect", "pvp_alliance", "pvp_horde", "pvp_ffa", "phase",
    "combat", "resting", "elite_elite", "elite_rare", "elite_boss",
}
local _externalIconPacks
local _externalIconPackOrder
local _registeredIconPacks = {}
local _statusIconAssetItemsCache = {}
local _textureProbeHost
local _textureProbe
local _textureProbeReliable
local _texturePathExistsCache = {}

local function NormalizeIconFolderPath(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = path:gsub("/", "\\"):gsub("\\+$", "")
    return path ~= "" and path or nil
end

local function TextureProbeRaw(path)
    if type(path) ~= "string" or path == "" or type(CreateFrame) ~= "function" then return false end
    if not _textureProbe then
        _textureProbeHost = CreateFrame("Frame")
        if _textureProbeHost.Hide then _textureProbeHost:Hide() end
        _textureProbe = _textureProbeHost:CreateTexture(nil, "ARTWORK")
    end
    if not (_textureProbe and _textureProbe.SetTexture) then return false end
    _textureProbe:SetTexture(nil)
    local applied = _textureProbe:SetTexture(path)
    if applied == false then
        _textureProbe:SetTexture(nil)
        return false
    end
    if _textureProbe.GetTexture then
        local tex = _textureProbe:GetTexture()
        _textureProbe:SetTexture(nil)
        return tex ~= nil and tex ~= ""
    end
    _textureProbe:SetTexture(nil)
    return applied == true
end

local function TextureProbeReliable()
    if _textureProbeReliable ~= nil then return _textureProbeReliable end
    _textureProbeReliable = TextureProbeRaw("Interface\\AddOns\\MidnightSimpleUnitFrames\\__msuf_missing_texture_probe__") == false
    return _textureProbeReliable
end

local function TexturePathExists(path)
    path = NormalizeIconFolderPath(path)
    if not path then return false end
    if _texturePathExistsCache[path] ~= nil then return _texturePathExistsCache[path] end
    local exists = TextureProbeReliable() and (TextureProbeRaw(path) or TextureProbeRaw(path .. ".tga") or TextureProbeRaw(path .. ".blp"))
    _texturePathExistsCache[path] = exists and true or false
    return _texturePathExistsCache[path]
end

local function IconFolderLooksComplete(folder)
    folder = NormalizeIconFolderPath(folder)
    if not folder then return false end
    local roleComplete = true
    for _, file in ipairs(ROLE_ICON_FILES) do
        if not TexturePathExists(folder .. "\\" .. file) then
            roleComplete = false
            break
        end
    end
    if roleComplete then return true end
    local statusComplete = true
    for _, file in ipairs(NON_ROLE_ICON_FILES) do
        if not TexturePathExists(folder .. "\\" .. file) then
            statusComplete = false
            break
        end
    end
    return statusComplete
end

local function AddExternalIconPack(key, label, folder, noMidnightSuffix, hasMidnightSuffix, files)
    folder = NormalizeIconFolderPath(folder)
    local hasFiles = type(files) == "table" and next(files) ~= nil
    if type(key) ~= "string" or key == "" or (not folder and not hasFiles) then return end
    if _externalIconPacks[key] then return end
    local pack = {
        key = key,
        label = (type(label) == "string" and label ~= "" and label) or key,
        folder = folder,
        files = files,
        noMidnightSuffix = noMidnightSuffix == true,
        hasMidnightSuffix = hasMidnightSuffix == true,
    }
    _externalIconPacks[key] = pack
    _externalIconPackOrder[#_externalIconPackOrder + 1] = pack
end

local function NormalizeStatusIconFileKey(file)
    if type(file) ~= "string" or file == "" then return nil end
    file = file:gsub("\\", "/"):match("([^/]+)$") or file
    file = file:gsub("%.[%a%d]+$", "")
    file = file:gsub("%s+", "_"):gsub("[^%w_%-]", "_"):lower()
    return file ~= "" and file or nil
end

local function LSM()
    local lsm = (MSUF and MSUF.LSM) or _G.MSUF_LSM
    if not lsm and type(_G.LibStub) == "function" then
        lsm = _G.LibStub("LibSharedMedia-3.0", true)
    end
    return lsm
end

local function ParseLSMStatusIconName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local a, b = name:match("^MSUF%s+Status%s+Icon%s+Pack:%s*(.-)%s*:%s*([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    a, b = name:match("^MSUF%s+StatusIcon:%s*(.-)%s*:%s*([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    a, b = name:match("^MSUF:StatusIcon:(.-):([%w_%-%.%s]+)%s*$")
    if a and b then return a, NormalizeStatusIconFileKey(b) end
    return nil
end

local function AddSharedMediaIconPacks()
    local lsm = LSM()
    if not (lsm and type(lsm.HashTable) == "function") then return end
    local packs, labels = {}, {}
    for _, mediaType in ipairs({ "msuf_statusicon", "background", "statusbar" }) do
        local hash = lsm:HashTable(mediaType)
        if type(hash) == "table" then
            for name, path in pairs(hash) do
                local label, file = ParseLSMStatusIconName(name)
                if label and file and type(path) == "string" and path ~= "" then
                    local key = label:gsub("%s+", "_"):gsub("[^%w_%-]", "_")
                    if key ~= "" then
                        packs[key] = packs[key] or {}
                        packs[key][file] = path
                        labels[key] = label
                    end
                end
            end
        end
    end
    local keys = {}
    for key in pairs(packs) do keys[#keys + 1] = key end
    table.sort(keys)
    for i = 1, #keys do
        local key = keys[i]
        local files = packs[key]
        AddExternalIconPack(LSM_ICON_STYLE_PREFIX .. key, labels[key], nil, false, true, files)
    end
end

local function GetAddonInfoName(index)
    local c = _G.C_AddOns
    if c and type(c.GetAddOnInfo) == "function" then
        local name, title = c.GetAddOnInfo(index)
        return name, title
    end
    if type(_G.GetAddOnInfo) == "function" then
        local name, title = _G.GetAddOnInfo(index)
        return name, title
    end
end

local function GetAddonCount()
    local c = _G.C_AddOns
    if c and type(c.GetNumAddOns) == "function" then return tonumber(c.GetNumAddOns()) or 0 end
    if type(_G.GetNumAddOns) == "function" then return tonumber(_G.GetNumAddOns()) or 0 end
    return 0
end

local function GetAddonMetadata(addonName, field)
    local c = _G.C_AddOns
    if c and type(c.GetAddOnMetadata) == "function" then
        return c.GetAddOnMetadata(addonName, field)
    end
    if type(_G.GetAddOnMetadata) == "function" then return _G.GetAddOnMetadata(addonName, field) end
end

local function IsTruthyMetadata(value)
    if value == true then return true end
    if type(value) ~= "string" then return false end
    value = value:lower()
    return value == "1" or value == "true" or value == "yes" or value == "y"
end

local function ExternalIconPackByKey(style)
    if type(style) ~= "string" or style == "" then return nil end
    GF.RefreshExternalStatusIconPacks()
    return _externalIconPacks and _externalIconPacks[style]
end

function GF.RefreshExternalStatusIconPacks(force)
    if _externalIconPacks and not force then return _externalIconPacks end
    _externalIconPacks = {}
    _externalIconPackOrder = {}
    _statusIconAssetItemsCache = {}

    for key, pack in pairs(_registeredIconPacks) do
        AddExternalIconPack(key, pack.label, pack.folder, pack.noMidnightSuffix, pack.hasMidnightSuffix)
    end

    AddSharedMediaIconPacks()

    local count = GetAddonCount()
    for i = 1, count do
        local addonName, title = GetAddonInfoName(i)
        if type(addonName) == "string" and addonName ~= "" then
            local marked = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-StatusIconPack"))
                or IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-IconPack"))
            local metadataFolder = NormalizeIconFolderPath(GetAddonMetadata(addonName, "X-MSUF-IconFolder"))
            local label = GetAddonMetadata(addonName, "X-MSUF-IconPack-Name") or title or addonName
            local noMidnight = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-NoMidnightSuffix"))
            local hasMidnight = IsTruthyMetadata(GetAddonMetadata(addonName, "X-MSUF-HasMidnightSuffix"))
            local iconFolders = metadataFolder and { metadataFolder } or { "Media\\Icons", "Icons" }
            local fallbackFolder
            for _, iconFolder in ipairs(iconFolders) do
                local folder = "Interface\\AddOns\\" .. addonName .. "\\" .. iconFolder
                if not fallbackFolder then fallbackFolder = folder end
                if IconFolderLooksComplete(folder) then
                    AddExternalIconPack(ADDON_ICON_STYLE_PREFIX .. addonName, label, folder, noMidnight, hasMidnight)
                    fallbackFolder = nil
                    break
                end
            end
            if marked and fallbackFolder then
                AddExternalIconPack(ADDON_ICON_STYLE_PREFIX .. addonName, label, fallbackFolder, noMidnight, hasMidnight)
            end
        end
    end

    return _externalIconPacks
end

function GF.RegisterStatusIconPack(key, label, folder, opts)
    key = (type(key) == "string" and key ~= "" and key) or nil
    folder = NormalizeIconFolderPath(folder)
    if not (key and folder) then return nil end
    if key:sub(1, #ADDON_ICON_STYLE_PREFIX) ~= ADDON_ICON_STYLE_PREFIX
        and key:sub(1, #REGISTERED_ICON_STYLE_PREFIX) ~= REGISTERED_ICON_STYLE_PREFIX
    then
        key = REGISTERED_ICON_STYLE_PREFIX .. key
    end
    _registeredIconPacks[key] = {
        label = label,
        folder = folder,
        noMidnightSuffix = type(opts) == "table" and opts.noMidnightSuffix == true,
        hasMidnightSuffix = type(opts) == "table" and opts.hasMidnightSuffix == true,
    }
    _externalIconPacks = nil
    _externalIconPackOrder = nil
    _statusIconAssetItemsCache = {}
    return key
end

-- Public extension point: other addons register/refresh custom status-icon
-- packs through these globals. No internal callers by design -- keep exported.
ExportPublic("MSUF_RegisterStatusIconPack", function(key, label, folder, opts)
    return GF.RegisterStatusIconPack(key, label, folder, opts)
end)
ExportPublic("MSUF_RefreshStatusIconPacks", function()
    _texturePathExistsCache = {}
    _statusIconAssetItemsCache = {}
    return GF.RefreshExternalStatusIconPacks(true)
end)

local INDICATOR_STYLE_KEYS = {
    roleIcon       = "roleIconStyle",
    leaderIcon     = "leaderIconStyle",
    assistIcon     = "assistIconStyle",
    raidMarker     = "raidMarkerStyle",
    readyCheckIcon = "readyCheckIconStyle",
    summonIcon     = "summonIconStyle",
    resurrectIcon  = "resurrectIconStyle",
    pvpIcon        = "pvpIconStyle",
    phaseIcon      = "phaseIconStyle",
}

--- Midnight art is a "_midnight" file variant of a pack, not a pack of its own, so it used to
--- ride on the scope-wide useMidnightIcons flag. The flag now travels inside the per-indicator
--- style value ("UXPRO@MIDNIGHT") instead, which lets one dropdown per indicator cover every
--- icon type. Splitting happens in the texture entry points, so any caller that just forwards a
--- stored style value keeps working. useMidnightIcons stays as the fallback for older profiles.
local MIDNIGHT_STYLE_SUFFIX = "@MIDNIGHT"

local function SplitIconStyle(style)
    if type(style) ~= "string" then return nil, false end
    local base = style:match("^(.+)@MIDNIGHT$")
    if base then return base, true end
    return style, false
end

local function JoinIconStyle(style, useMidnight)
    if type(style) ~= "string" or style == "" or useMidnight ~= true then return style end
    return style .. MIDNIGHT_STYLE_SUFFIX
end

local function NormalizeIconStyle(style, fallback)
    style = (SplitIconStyle(style))
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then
        style = (SplitIconStyle(fallback)) or "BLIZZARD"
    end
    if style == "BLIZZARD" or CUSTOM_STYLES[style] then return style end
    if ExternalIconPackByKey(style) then return style end
    return "BLIZZARD"
end

local function IndicatorIconStyle(conf, indicatorKey)
    conf = (type(conf) == "table") and conf or {}
    local styleKey = INDICATOR_STYLE_KEYS[indicatorKey]
    local style, midnight = SplitIconStyle(styleKey and conf[styleKey] or nil)
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then
        style, midnight = SplitIconStyle(conf.iconStyle or "MSUF_ROLES")
        if not midnight then midnight = conf.useMidnightIcons == true end
    end
    return NormalizeIconStyle(style, "BLIZZARD"), midnight == true
end

--- Per-indicator override wins over the stored indicator style; both may carry the suffix.
local function ResolveIndicatorIconStyle(conf, indicatorKey, styleOverride)
    local base, midnight = SplitIconStyle(styleOverride)
    if type(base) == "string" and base ~= "" and base ~= "DEFAULT" then
        return NormalizeIconStyle(base, "BLIZZARD"), midnight == true
    end
    return IndicatorIconStyle(conf, indicatorKey)
end

local function CustomIconPath(style, file, useMidnight)
    local folder = CUSTOM_STYLES[style]
    if not folder then return nil end
    if ROLE_ONLY_CUSTOM_STYLES[style] and not ROLE_ONLY_ICON_FILES[file] then return nil end
    if useMidnight and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[style] then
        file = file .. "_midnight"
    end
    return MEDIA_PREFIX .. folder .. "\\" .. file
end

local function StatusIconFile(iconType, variant)
    iconType = tostring(iconType or "")
    if iconType == "role" then return ROLE_MAP[variant] or "dps" end
    if iconType == "leader" then return "leader" end
    if iconType == "assist" then return "assist" end
    if iconType == "raidMarker" or iconType == "raidmarker" then
        return RAID_MARKER_FILES[tonumber(variant) or variant] or "raid_skull"
    end
    if iconType == "readyCheck" or iconType == "readycheck" then
        return READY_FILES[tostring(variant or "")] or "ready_waiting"
    end
    if iconType == "summon" then
        return SUMMON_FILES[tonumber(variant) or variant] or "summon_pending"
    end
    if iconType == "pvp" then
        return PVP_FILES[variant] or PVP_FILES[tostring(variant or ""):lower()] or "pvp_alliance"
    end
    if iconType == "elite" then
        variant = tostring(variant or ""):upper()
        if variant == "BOSS" or variant == "WORLDBOSS" then return "elite_boss" end
        if variant == "RARE" or variant == "RAREELITE" then return "elite_rare" end
        return "elite_elite"
    end
    return SIMPLE_STATUS_ICON_FILES[iconType]
end

local function RaidMarkerTexCoord(index)
    index = tonumber(index) or 8
    if index < 1 or index > 8 then index = 8 end
    local col = (index - 1) % 4
    local row = math_floor((index - 1) / 4)
    local size = 0.25
    return col * size, (col + 1) * size, row * size, (row + 1) * size
end

local function BuiltinStatusIconTexture(iconType, variant)
    iconType = tostring(iconType or "")
    if iconType == "leader" then return BLIZZARD_LEADER_TEX, 0, 1, 0, 1 end
    if iconType == "assist" then return BLIZZARD_ASSIST_TEX, 0, 1, 0, 1 end
    if iconType == "role" then
        local c = BLIZZARD_ROLE_COORDS[variant] or BLIZZARD_ROLE_COORDS.DAMAGER
        return BLIZZARD_ROLE_TEX, c[1], c[2], c[3], c[4]
    end
    if iconType == "raidMarker" or iconType == "raidmarker" then
        local l, r, t, b = RaidMarkerTexCoord(variant)
        return BLIZZARD_RAID_MARKER_TEX, l, r, t, b
    end
    if iconType == "readyCheck" or iconType == "readycheck" then
        return BLIZZARD_READY_TEXTURES[tostring(variant or "")] or BLIZZARD_READY_TEXTURES.waiting, 0, 1, 0, 1
    end
    if iconType == "summon" then
        local key = SUMMON_FILES[tonumber(variant) or variant]
        if key == "summon_accepted" then return BLIZZARD_SUMMON_TEXTURES.accepted, 0, 1, 0, 1 end
        if key == "summon_declined" then return BLIZZARD_SUMMON_TEXTURES.declined, 0, 1, 0, 1 end
        return BLIZZARD_SUMMON_TEXTURES.pending, 0, 1, 0, 1
    end
    if iconType == "incomingRes" or iconType == "resurrect" then return BLIZZARD_REZ_TEXTURE, 0, 1, 0, 1 end
    if iconType == "phase" then return BLIZZARD_PHASE_TEXTURE, 0, 1, 0, 1 end
    if iconType == "pvp" then
        return BLIZZARD_PVP_TEXTURES[variant] or BLIZZARD_PVP_TEXTURES[tostring(variant or "")] or BLIZZARD_PVP_TEXTURES.Alliance, 0, 1, 0, 1
    end
    if iconType == "combat" then return BLIZZARD_STATE_TEXTURE, 0.5, 1, 0, 0.5 end
    if iconType == "resting" then return BLIZZARD_STATE_TEXTURE, 0, 0.5, 0, 0.5 end
    if iconType == "elite" then return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 0, 1, 0, 1 end
    return nil
end

local function ExternalIconPath(pack, file, useMidnight)
    if not (pack and file) then return nil end
    if type(pack.files) == "table" then
        if useMidnight == true and pack.files[file .. "_midnight"] then
            return pack.files[file .. "_midnight"]
        end
        return pack.files[file]
    end
    if type(pack.folder) ~= "string" or pack.folder == "" then return nil end
    local path = pack.folder .. "\\" .. file
    if useMidnight == true and not pack.noMidnightSuffix then
        local midnightPath = pack.folder .. "\\" .. file .. "_midnight"
        if pack.hasMidnightSuffix or TexturePathExists(midnightPath) then path = midnightPath end
    end
    if TexturePathExists(path) then return path end
    return nil
end

local function StatusIconAssetCacheKey(iconType, variant, includeDefault, includeStyleSets)
    return tostring(iconType or "") .. "\031" .. tostring(variant or "") .. "\031" .. (includeDefault and "1" or "0") .. "\031" .. (includeStyleSets and "1" or "0")
end

local function AddStatusIconAssetItem(out, used, value, text)
    if type(value) ~= "string" or value == "" or used[value] then return end
    used[value] = true
    out[#out + 1] = {
        value = value,
        text = text or value,
        texture = value,
        texturePreview = value,
        previewKind = "icon",
    }
end

local function AddSharedMediaIconAssetItems(out, used)
    local lsm = LSM()
    if not (lsm and type(lsm.HashTable) == "function") then return end
    for _, mediaType in ipairs({ "msuf_statusicon", "background", "statusbar" }) do
        local hash = lsm:HashTable(mediaType)
        if type(hash) == "table" then
            local names = {}
            for name in pairs(hash) do names[#names + 1] = name end
            table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
            for i = 1, #names do
                local name = names[i]
                local path = hash[name]
                local packLabel, file = ParseLSMStatusIconName(name)
                local isIconMedia = mediaType == "msuf_statusicon" or (packLabel ~= nil and file ~= nil)
                if isIconMedia and type(path) == "string" and path ~= "" then
                    AddStatusIconAssetItem(out, used, path, "SharedMedia: " .. tostring(name))
                end
            end
        end
    end
end

function GF.GetStatusIconAssetItems(iconType, variant, includeDefault, includeStyleSets)
    includeStyleSets = includeStyleSets == true
    local cacheKey = StatusIconAssetCacheKey(iconType, variant, includeDefault == true, includeStyleSets)
    if _statusIconAssetItemsCache[cacheKey] then return _statusIconAssetItemsCache[cacheKey] end
    local out, used = {}, {}
    if includeDefault == true then
        out[#out + 1] = { value = "", text = "Use default icon" }
        used[""] = true
    end
    local file = StatusIconFile(iconType, variant)
    if file then
        if includeStyleSets then
            for i = 1, #GF.ICON_STYLE_ITEMS do
                local item = GF.ICON_STYLE_ITEMS[i]
                local style = item.value or item.key
                local label = item.text or item.label or style
                local path = CustomIconPath(style, file, false)
                if path then AddStatusIconAssetItem(out, used, path, tostring(label) .. ": " .. file) end
                if path and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[style] then
                    local midnightPath = CustomIconPath(style, file, true)
                    AddStatusIconAssetItem(out, used, midnightPath, tostring(label) .. " Midnight: " .. file)
                end
            end
        end
        for i = 1, #STANDALONE_STATUS_ICON_FOLDERS do
            local item = STANDALONE_STATUS_ICON_FOLDERS[i]
            AddStatusIconAssetItem(out, used, MEDIA_PREFIX .. item.folder .. "\\" .. file, item.label .. ": " .. file)
        end
        if includeStyleSets then
            GF.RefreshExternalStatusIconPacks()
            for i = 1, #(_externalIconPackOrder or {}) do
                local pack = _externalIconPackOrder[i]
                local path = ExternalIconPath(pack, file, false)
                if path then AddStatusIconAssetItem(out, used, path, tostring(pack.label or pack.key) .. ": " .. file) end
                local midnightPath = ExternalIconPath(pack, file, true)
                if midnightPath and midnightPath ~= path then
                    AddStatusIconAssetItem(out, used, midnightPath, tostring(pack.label or pack.key) .. " Midnight: " .. file)
                end
            end
        end
    end
    AddSharedMediaIconAssetItems(out, used)
    _statusIconAssetItemsCache[cacheKey] = out
    return out
end

function GF.GetStatusIconTexture(style, iconType, variant, useMidnight)
    local base, midnight = SplitIconStyle(style)
    useMidnight = (useMidnight == true) or midnight
    style = NormalizeIconStyle(base, "BLIZZARD")
    local file = StatusIconFile(iconType, variant)
    local folder = CUSTOM_STYLES[style]
    if folder and file then
        local path = CustomIconPath(style, file, useMidnight == true)
        if path then return path, 0, 1, 0, 1 end
    end
    local external = ExternalIconPackByKey(style)
    if external and file then
        local path = ExternalIconPath(external, file, useMidnight == true)
        if path then return path, 0, 1, 0, 1 end
    end
    return BuiltinStatusIconTexture(iconType, variant)
end

function GF.StatusIconPackSupports(style, iconType, variant, useMidnight)
    local base, midnight = SplitIconStyle(style)
    useMidnight = (useMidnight == true) or midnight
    style = base
    if type(style) ~= "string" or style == "" or style == "DEFAULT" then return true end
    style = NormalizeIconStyle(style, "BLIZZARD")
    if style == "BLIZZARD" then return BuiltinStatusIconTexture(iconType, variant) ~= nil end
    local file = StatusIconFile(iconType, variant)
    if not file then return false end
    if CUSTOM_STYLES[style] then return file ~= nil and CustomIconPath(style, file, useMidnight == true) ~= nil end
    local external = ExternalIconPackByKey(style)
    if external then return ExternalIconPath(external, file, useMidnight == true) ~= nil end
    return false
end

function GF.GetIndicatorIconStyle(kind, indicatorKey)
    local conf = GF.GetConf(kind)
    return IndicatorIconStyle(conf, indicatorKey)
end

function GF.GetRoleTexture(kind, role, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "roleIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "role", role, useMidnight)
end

function GF.GetLeaderTexture(kind, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "leaderIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "leader", nil, useMidnight)
end

function GF.GetAssistTexture(kind, styleOverride)
    local conf = GF.GetConf(kind)
    local style, useMidnight = ResolveIndicatorIconStyle(conf, "assistIcon", styleOverride)
    return GF.GetStatusIconTexture(style, "assist", nil, useMidnight)
end

GF.ICON_STYLE_ITEMS = {
    { key = "BLIZZARD",      label = "Blizzard (Default)" },
    { key = "MSUF_ROLES",    label = "MSUF Roles"         },
    { key = "CLASSIC",       label = "Classic"            },
    { key = "MIDNIGHT",      label = "Midnight"           },
    { key = "UXPRO",         label = "UX Pro"             },
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

--- includeMidnight appends the "_midnight" art of every pack that ships one as its own entry,
--- so a single dropdown covers all icon types instead of pairing a style list with a separate
--- Midnight toggle. Packs without midnight art (and BLIZZARD) contribute one entry only.
function GF.GetIconStyleItems(includeDefault, includeMidnight)
    local out = {}
    local seenValues, seenLabels = {}, {}
    local function LabelKey(label)
        if type(label) ~= "string" then return nil end
        label = label:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "):lower()
        return label ~= "" and label or nil
    end
    local function AddStyleItem(value, text, hasMidnight)
        value = type(value) == "string" and value or nil
        text = type(text) == "string" and text or value
        if not value or value == "" then return end
        local lk = LabelKey(text)
        if seenValues[value] or (lk and seenLabels[lk]) then return end
        seenValues[value] = true
        if lk then seenLabels[lk] = true end
        out[#out + 1] = { value = value, text = text }
        if not (includeMidnight and hasMidnight) then return end
        local midnightValue = JoinIconStyle(value, true)
        local midnightText = text .. " (Midnight)"
        local mlk = LabelKey(midnightText)
        if seenValues[midnightValue] or (mlk and seenLabels[mlk]) then return end
        seenValues[midnightValue] = true
        if mlk then seenLabels[mlk] = true end
        out[#out + 1] = { value = midnightValue, text = midnightText }
    end
    if includeDefault then
        AddStyleItem("DEFAULT", "Follow global style")
    end
    for i = 1, #GF.ICON_STYLE_ITEMS do
        local item = GF.ICON_STYLE_ITEMS[i]
        local key = item.value or item.key
        AddStyleItem(key, item.text or item.label or key,
            CUSTOM_STYLES[key] ~= nil and not CUSTOM_STYLES_NO_MIDNIGHT_SUFFIX[key])
    end
    GF.RefreshExternalStatusIconPacks()
    for i = 1, #(_externalIconPackOrder or {}) do
        local pack = _externalIconPackOrder[i]
        AddStyleItem(pack.key, pack.label, pack.noMidnightSuffix ~= true)
    end
    return out
end

--- Options/EditMode need the same encoding to show a stored style in a dropdown.
GF.SplitIconStyle = SplitIconStyle
GF.JoinIconStyle = JoinIconStyle

ExportPublic("MSUF_GetStatusIconPackValues", function(includeDefault, includeMidnight)
    return GF.GetIconStyleItems(includeDefault == true, includeMidnight == true)
end)

ExportPublic("MSUF_SplitStatusIconStyle", SplitIconStyle)

ExportPublic("MSUF_GetStatusIconTexture", function(style, iconType, variant, useMidnight)
    return GF.GetStatusIconTexture(style, iconType, variant, useMidnight == true)
end)

ExportPublic("MSUF_StatusIconPackSupports", function(style, iconType, variant, useMidnight)
    return GF.StatusIconPackSupports(style, iconType, variant, useMidnight == true)
end)

ExportPublic("MSUF_GetStatusIconAssetValues", function(iconType, variant, includeDefault, includeStyleSets)
    return GF.GetStatusIconAssetItems(iconType, variant, includeDefault == true, includeStyleSets == true)
end)

ExportPublic("MSUF_GetRoleStatusIconTexture", function(style, role, useMidnight)
    return GF.GetStatusIconTexture(style, "role", role, useMidnight == true)
end)

ExportPublic("MSUF_GetLeaderStatusIconTexture", function(style, useMidnight)
    return GF.GetStatusIconTexture(style, "leader", nil, useMidnight == true)
end)

ExportPublic("MSUF_GetAssistStatusIconTexture", function(style, useMidnight)
    return GF.GetStatusIconTexture(style, "assist", nil, useMidnight == true)
end)

---
--- Public DB-config bridges: consumed by Options/EditMode/Assistant by global
--- name. Stable ABI -- keep exported even when internal callers are few.
---
ExportPublic("MSUF_GF_EnsureDB", GF.EnsureDB)
ExportPublic("MSUF_GF_MigrateAuraConfig", GF.MigrateAuraConfig)
ExportPublic("MSUF_GF_GetConf", GF.GetConf)
ExportPublic("MSUF_GF_GetPriorityConf", GF.GetPriorityConf)
ExportPublic("MSUF_GF_Val", GF.Val)
ExportPublic("MSUF_GF_GetHighlightVal", GF.GetHighlightVal)
ExportPublic("MSUF_GF_InvalidateConfCache", GF.InvalidateConfCache)
ExportPublic("MSUF_GF_ResetAllToDefaults", GF.ResetAllToDefaults)
