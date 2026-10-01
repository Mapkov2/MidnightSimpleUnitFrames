--- GroupFrames/MSUF_GroupFrames_DB.lua - group-frame defaults, DB normalization, and config access.
--- Geometry, text and textures live in the _DB_Geometry, _DB_Text and _DB_Textures
--- files beside it, which load right after this one.
--- Phase 12: 3-slot health text, name color, name max chars, power per-role,
--- smooth fill toggle, hideInClientScene, target/aggro upgrades
--- Midnight 12.0 secret-safe, zero combat overhead
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

MSUF.GF = MSUF.GF or {}
local GF = MSUF.GF
local ExportPublic = MSUF.ExportPublic
-- WoW Forever client fact, read once. Harnesses without MSUF.Client are not Forever.
local IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true

--==========================================================================--
-- GroupFrames API surface (MSUF.GF / _G.MSUF_*)
--==========================================================================--
-- This is the contract for the GroupFrames module. The module is split across
-- GroupFrames/*.lua and UnitFrames/Engine/Group/*.lua but shares ONE table
-- (MSUF.GF, aliased `GF` in every file). Keep the surface minimal:
--
--   * Public / external bridges  -> global _G.MSUF_* wrappers (see lists below).
--       Options, EditMode, slash/debug, LoadOnDemand modules and
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
--   DB config (this file):  MSUF_GF_EnsureDB, _GetConf, _Val (and _GetHighlightVal from DB_Textures),
--       _InvalidateConfCache, _ResetAllToDefaults.
--   DB repair (DB_Migrations): MSUF_GF_MigrateAuraConfig. The cold body of
--       EnsureDB (one-time migrations, defaults, legacy aura model, menu-domain
--       repair) lives in MSUF_GroupFrames_DB_Migrations.lua as GF.RepairGroupDB.
--   Status icon packs (DB_Textures):  MSUF_RegisterStatusIconPack /
--       MSUF_RefreshStatusIconPacks are a PUBLIC extension point for other
--       addons (no internal callers by design -- keep them). Plus
--       MSUF_GetStatusIconPackValues / MSUF_GetStatusIconTexture /
--       MSUF_Get{Role,Leader,Assist}StatusIconTexture.
--   Spell indicators (DB_SpellIndicators): MSUF_GF_Seed{,Current}SpellIndicator*.
--   EditMode popups (EM2): MSUF_EM2_*GFPopup*, MSUF_GF_EM2_*.
--   Blizzard frames (Blizzard): MSUF_GF_DisableBlizzard.
--==========================================================================--

local type = type
local pairs = pairs
local ipairs = ipairs

--- Saved positionMode values of a group block. V1 rendered a full-size header
--- shifted by the origin-to-first-centre delta; V2 stores the selected anchor
--- point of the complete grid bounds (see MSUF_GroupFrames_DB_Geometry.lua).
GF.GRID_POSITION_MODES = {
    LEGACY = "GRID_CENTER_V1",
    STABLE = "GRID_BOUNDS_V2",
}

---
--- Defaults
---
local PARTY_DEFAULTS = {
    smallRaidAsParty = false,
    --- Buff coverage icons (WoW Forever; Game/Forever/GroupFrames).
    buffCoverageEnabled = false,
    buffCoverageWild = true,
    buffCoverageThorns = false,
    buffCoverageIntellect = true,
    buffCoverageBlessings = true,
    buffCoverageStamina = true,
    buffCoverageSpirit = false,
    buffCoverageThornsTankOnly = true,
    buffCoverageGlow = false,
    buffCoverageCombat = false,
    buffCoverageSize = 14,
    buffCoverageAnchor = "BOTTOM",
    buffCoverageX = 0,
    buffCoverageY = 2,
    buffCoverageLayer = 6,
    nameBarEnabled = false,
    nameBarHeight = 14,
    nameBarR = 0.05,
    nameBarG = 0.05,
    nameBarB = 0.05,
    nameBarAlpha = 0.95,
    autoScaleIndicatorsOnResize = false,
    autoScaleAurasOnResize = false,
    autoScaleTrackedOnResize = false,
    layoutTiersEnabled = false,
    excludeHiddenGroups = false,
    collapseEmptyGroups = false,
    hideMythicGroupsFiveToEight = false,
    centerSolo = false,
    tier10Width = 0,
    tier10Height = 0,
    tier10Position = false,
    tier10X = 0,
    tier10Y = 0,
    tier10Growth = "INHERIT",
    tier20Width = 0,
    tier20Height = 0,
    tier20Position = false,
    tier20X = 0,
    tier20Y = 0,
    tier20Growth = "INHERIT",
    tier25Width = 0,
    tier25Height = 0,
    tier25Position = false,
    tier25X = 0,
    tier25Y = 0,
    tier25Growth = "INHERIT",
    tier40Width = 0,
    tier40Height = 0,
    tier40Position = false,
    tier40X = 0,
    tier40Y = 0,
    tier40Growth = "INHERIT",
    targetsEnabled = false,
    targetsWidth = 100,
    targetsHeight = 24,
    targetsColumns = 1,
    targetsX = -250,
    targetsY = 150,
    targetsTextSize = 11,
    petsEnabled = false,
    petsMaxCount = 40,
    petsWidth = 100,
    petsHeight = 24,
    petsColumns = 1,
    petsX = -250,
    petsY = -150,
    petsTextSize = 11,
    friendlyBossEnabled = false,
    friendlyBossWidth = 100,
    friendlyBossHeight = 24,
    friendlyBossColumns = 1,
    friendlyBossX = 250,
    friendlyBossY = 150,
    friendlyBossTextSize = 11,
    healerManaEnabled = false,
    healerManaWidth = 100,
    healerManaHeight = 24,
    healerManaX = 250,
    healerManaY = -150,
    healerManaTextSize = 11,
    targetsIncludePlayer = false,
    friendlyBossHealerOnly = true,
    healerManaShowValue = true,
    healerManaTextR = 1,
    healerManaTextG = 1,
    healerManaTextB = 1,
    sortClassPriority = false,
    classOrder = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER",
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
    --- Unified alpha exclusions keep selected informational elements opaque while
    --- bars dim (HP/background opacity live in hpBarAlpha / hpBgAlpha above).
    alphaExcludeTextPortrait = false,
    alphaExcludePredictionBars = false,
    --- Group Frame heal prediction is edited in Global Style > Bars using the
    --- Party/Raid bar scopes. hlOverride gates local values; otherwise the
    --- shared UnitFrame heal-prediction toggle is the fallback.
    healPredEnabled      = true,
    healPredAllHealers   = false,
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
    --- Level text (difficulty-colored like the unit-frame level indicator)
    levelText                = false,
    levelTextDifficultyColor = true,
    levelTextSize            = 10,
    levelTextAnchor          = "BOTTOMLEFT",
    levelTextX               = 2,
    levelTextY               = 2,
    levelTextLayer           = 7,
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
    --- Raid/Mythic only: order roles across the entire raid instead of within
    --- each raid group (preserved blocks fill from the raid-wide role order).
    sortRolesAcrossRaid = false,
    sortAlphabeticalWithinRole = false,
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
PARTY_DEFAULTS.portraitClickable = false
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

--- Threat percentage text (Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua): each
--- member's threat on the player's current target. Only the clients offering it
--- (MSUF.Client.SupportsThreatText) carry the keys, so Midnight and Mists profiles
--- stay unchanged. Top centre is free of every status icon and of the name. On by
--- default for Party only; a raid of 20 to 40 numbers is noise (owner decision
--- 2026-09-19).
if MSUF.Client and MSUF.Client.SupportsThreatText == true then
    for _, defaults in ipairs({ PARTY_DEFAULTS, RAID_DEFAULTS, MYTHIC_RAID_DEFAULTS }) do
        defaults.threatText = false
        defaults.threatTextColorCurve = true
        defaults.threatTextBackground = false
        defaults.threatTextSize = 9
        defaults.threatTextAnchor = "TOP"
        defaults.threatTextX = 0
        defaults.threatTextY = -1
        defaults.threatTextLayer = 7
    end
    PARTY_DEFAULTS.threatText = true
    -- The dark plate behind the number: Party only by default (owner, 2026-09-19).
    PARTY_DEFAULTS.threatTextBackground = true
end

--- Priority Frames are a small secure duplicate strip for important raid
--- members. Visuals intentionally inherit the active raid/mythic-raid spec;
--- this table owns only activation, selection policy, and container geometry.
local PRIORITY_DEFAULTS = {
    width         = 0,
    height        = 0,
    unitsPerColumn = 5,
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

local function ResolveLegacyHealPredictionEnabled(db)
    db = db or _G.MSUF_DB
    local gen = db and db.general
    if type(gen) ~= "table" then return false end
    if gen.healPredEnabled ~= nil then return gen.healPredEnabled == true end
    if gen.showSelfHealPrediction ~= nil then return gen.showSelfHealPrediction == true end
    if gen.enableHealPrediction ~= nil then return gen.enableHealPrediction ~= false end
    return false
end
--- The heal-prediction ownership migration (DB_Migrations) resolves the same
--- shared baseline.
GF.ResolveLegacyHealPredictionEnabled = ResolveLegacyHealPredictionEnabled

--- PERF: Group runtime has several defensive DB boundaries. A completed repair
--- remains valid across frames until an actual DB mutation invalidates it; table
--- identity checks still catch profile/root replacements without a scan.
local ensureDBReady = false
local ensureDBRoot, ensureDBParty, ensureDBRaid, ensureDBMythic, ensureDBPriority

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
    --- Cold body: materialize the scope tables and run the ordered repair
    --- pipeline (one-time migrations, defaults, legacy aura model, menu-domain
    --- repair). Defined in MSUF_GroupFrames_DB_Migrations.lua.
    GF.RepairGroupDB(db)
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
    if MSUF.Client and MSUF.Client.SupportsGroupKind and not MSUF.Client.SupportsGroupKind("mythicraid") then return false end
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

--- A raid of up to five shown with the Party layout. Only while the Party scope
--- itself is on: otherwise the Raid scope keeps the raid, or nothing would show.
function GF.IsSmallRaidPartyContext()
    if not _G.IsInRaid() then return false end
    local conf = GF.GetConf("party")
    local count = _G.GetNumGroupMembers()
    return conf.enabled == true and conf.smallRaidAsParty == true and count > 0 and count <= 5
end

function GF.GetLiveGroupKind()
    if GF.IsArenaPartyContext and GF.IsArenaPartyContext() then
        return "party"
    end
    if GF.IsSmallRaidPartyContext() then return "party" end
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
        conf.positionMode = GF.GRID_POSITION_MODES.LEGACY
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
    local _, instanceType, difficultyID = GetInstanceInfo()
    --- WoW Forever raids use Classic 10/20/40-player difficulties (Mainline
    --- DifficultyUtil RaidClassic10Normal/RaidClassic20Normal/Raid40). The
    --- 1.60.1 Difficulty table has no Mythic raid row, so every raid is "normal".
    if IS_FOREVER and instanceType == "raid" then return "normal" end
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
--- `alphaExcludeTextPortrait` / `alphaExcludePredictionBars` toggles. No
--- combat-state alpha, no layer modes -- the
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

---
--- Public DB-config bridges: consumed by Options/EditMode by global
--- name. Stable ABI -- keep exported even when internal callers are few.
---
ExportPublic("MSUF_GF_EnsureDB", GF.EnsureDB)
ExportPublic("MSUF_GF_GetConf", GF.GetConf)
ExportPublic("MSUF_GF_GetPriorityConf", GF.GetPriorityConf)
ExportPublic("MSUF_GF_Val", GF.Val)
ExportPublic("MSUF_GF_InvalidateConfCache", GF.InvalidateConfCache)
ExportPublic("MSUF_GF_ResetAllToDefaults", GF.ResetAllToDefaults)
