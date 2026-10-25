-- Legacy sparse decoding, safe-tree checks and reusable persistence scratch.
local _, MSUF = ...
local Parts = MSUF.DefaultsSchemaParts
-- Frozen version-1 storage dictionaries. New defaults must not change these
-- decoder values: add a new codec version instead. Only schema-owned scalar
-- leaves are eligible; false, zero, empty strings, lists and user keys stay full.
local sparseGeneralV1 = {
    _msufPreviewDragHintExperienced = true, absorbBarOpacity = 1, anchorName = "UIParent", arenaPreviewEnabled = true,
    auraFontSize = 25, barBackgroundTexture = "Solid", barTexture = "MSUF Lucent", blizzardEditModeIntegration = true,
    bossCastTimeFormat = "CURRENT", bossCastbarHeight = 12, bossCastbarOffsetX = 2, bossCastbarOffsetY = -46,
    bossCastbarWidth = 176, bossPreviewEnabled = true, castbarFillDirection = "RTL", castbarFocusBarHeight = 18,
    castbarFocusBarWidth = 175, castbarFocusOffsetX = 2, castbarFocusOffsetY = -50, castbarFocusShowIcon = true,
    castbarFocusShowSpellName = true, castbarFocusTimeFormat = "CURRENT", castbarIconZoom = 100,
    castbarInterruptColor = "red", castbarInterruptibleColor = "turquoise", castbarNonInterruptibleColor = "red",
    castbarPlayerBarHeight = 18, castbarPlayerBarWidth = 271, castbarPlayerOffsetX = -2, castbarPlayerOffsetY = -59,
    castbarPlayerPreviewEnabled = true, castbarPlayerShowIcon = true, castbarPlayerShowSpellName = true,
    castbarPlayerTimeFormat = "CURRENT", castbarPlayerTimeOffsetX = -2, castbarShowIcon = true,
    castbarShowSpellName = true, castbarSparkOverflow = true, castbarTargetBarHeight = 18, castbarTargetBarWidth = 272,
    castbarTargetOffsetY = -60, castbarTargetShowIcon = true, castbarTargetShowSpellName = true,
    castbarTargetTimeFormat = "CURRENT", combatStateIndicatorLayer = 7, dandersEditModeIntegration = true,
    darkBarTone = "black", detailsEditModeIntegration = true, disableUnitInfoTooltips = true,
    dispelBorderShowOn = "BOTH", dispelBorderTrigger = "DISPEL_TYPE", dispelOutlineMode = 1,
    dominosEditModeIntegration = true, editModeGridEnabled = true, editModeGridStep = 20,
    editModeHideWhiteArrows = true, editModeSnapMode = "grid", editModeSnapModeGrid = true, empowerColorStages = true,
    empowerStageBlink = true, enableArenaCastbar = true, enableBossCastbar = true, enableFocusCastbar = true,
    enableHealthGradient = true, enablePlayerCastbar = true, enableTargetCastbar = true, flashFullH = 700,
    flashFullPoint = "CENTER", flashFullRelPoint = "CENTER", flashFullW = 900, flashFullX = -60, flashFullXpx = -60,
    flashFullY = 10, flashFullYpx = 10, focusKickIconHeight = 40, focusKickIconOffsetX = 300, focusKickIconWidth = 40,
    gcdBarHeight = 12, gcdBarOpacity = 100, gcdBarWidth = 180, gcdBarY = -180, globalUiScalePreset = "auto",
    grid2EditModeIntegration = true, healAbsorbAnchorMode = 3, healAbsorbBarOpacity = 1, healAbsorbEnabled = true,
    healPredAnchorMode = 3, healthLossColorB = 0.08, healthLossColorG = 0.55, healthLossColorR = 1,
    hideAdvancedMenu = true, hpFontSize = 14, hpTextMode = "FULL_PLUS_PERCENT", hpTextSeparator = "-",
    incomingResIndicatorLayer = 7, leaderIconLayer = 7, leaderIconOffsetY = 3, leaderIconStyle = "BLIZZARD",
    levelIndicatorLayer = 7, linkEditModes = true, msufUiScale = 1.0, nameFontSize = 14, npcTypeColorBar = true,
    npcTypeColorText = true, overAbsorbOverlay = true, playerCastbarOverrideB = 1, playerCastbarOverrideEnabled = true,
    playerCastbarOverrideG = 1, playerCastbarOverrideR = 1, portraitAlpha = 100, portraitBgColorA = 0.85,
    portraitBgColorB = 0.05, portraitBgColorG = 0.05, portraitBgColorR = 0.05, portraitBorderArt = "FLAT",
    portraitBorderColorA = 1, portraitBorderColorB = 1, portraitBorderColorG = 1, portraitBorderColorR = 1,
    portraitBorderDirection = "UP", portraitBorderStyle = "NONE", portraitBorderThickness = 2,
    portraitClassStyle = "BLIZZARD", portraitDetachedPoint = "RIGHT", portraitDetachedTo = "LEFT",
    portraitLevelOffset = 7, portraitOverlayAlign = "LEFT", portraitPlacement = "ATTACHED", portraitShape = "SQUARE",
    portraitZoom = 100, powerFontSize = 12, powerLossColorB = 1, powerLossColorG = 0.90, powerLossColorR = 0.70,
    previewDragHintAnimationEnabled = true, pvpIndicatorAnchor = "TOPRIGHT", pvpIndicatorLayer = 7,
    pvpIndicatorSize = 18, raidGroupNameOffsetX = 3, restedStateIndicatorAnchor = "TOPLEFT",
    restedStateIndicatorIconStyle = "BLIZZARD", restedStateIndicatorLayer = 25,
    restedStateIndicatorSymbol = "rested_blizzard_animated", showArenaCastIcon = true, showArenaCastName = true,
    showArenaCastTime = true, showBossCastIcon = true, showBossCastName = true, showBossCastTime = true,
    showCombatStateIndicator = true, showFocusCastTime = true, showGCDBarSpell = true, showGCDBarTime = true,
    showGameMenuButton = true, showLeaderIcon = true, showPlayerCastTime = true, showPvpIndicator = true,
    showRaidMarker = true, showTargetCastTime = true, slashMenuSnapEnabled = true,
    tempMaxHealthBackgroundOpacity = 0.65, tempMaxHealthColorB = 0.10, tempMaxHealthColorG = 0.10,
    tempMaxHealthColorR = 0.70, tempMaxHealthOpacity = 1, textBackdrop = true, tipCycleIndex = 11,
    unitDispelOverlayAlpha = 0.35, unitDispelOverlayOnHealth = true, unitDispelOverlayStyle = "FULL",
    unitDispelOverlayTrigger = "BORDER", unitDispelSymbolAlpha = 1, unitDispelSymbolAnchor = "TOPRIGHT",
    unitDispelSymbolGrowth = "RIGHT", unitDispelSymbolLayer = 8, unitDispelSymbolMode = "ALL",
    unitDispelSymbolSize = 14, unitDispelSymbolSpacing = 2, unitDispelSymbolStrata = "AUTO",
    unitDispelSymbolStyle = "BLIZZARD", unitDispelSymbolTrigger = "BORDER", unitInfoTooltipStyle = "classic",
}
local sparseGroupV1 = {
    absorbAnchorMode = 5, absorbBarOpacity = 1, absorbBarTexture = "MSUF Smooth v2", aggroEnabled = true,
    aggroMode = "ALL", aggroR = 1, assistIconAnchor = "TOPRIGHT", assistIconLayer = 2, assistIconSize = 12,
    assistIconStyle = "DEFAULT", bgB = 0.1, bgG = 0.1, bgR = 0.1, blizzardFallbackMode = "AUTO", borderA = 1,
    borderEnabled = true, borderSize = 1, buffCoverageAnchor = "BOTTOM", buffCoverageBlessings = true,
    buffCoverageIntellect = true, buffCoverageLayer = 6, buffCoverageSize = 14, buffCoverageStamina = true,
    buffCoverageThornsTankOnly = true, buffCoverageWild = true, buffCoverageY = 2, ciAggroColorG = 0.55,
    ciAggroColorR = 1, ciAlpha = 1, ciEnabled = true, ciLayer = 7, ciSize = 8, ciSlotBL = "none", ciSlotBR = "none",
    ciSlotC = "none", ciSlotTL = "dispel", ciSlotTR = "aggro", ciStrata = "AUTO",
    classOrder = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER",
    clickCastEnabled = true, deadBgA = 0.9, deadBgB = 0.05, deadBgG = 0.05, deadBgOffline = true, deadBgR = 0.6,
    debuffStripeAlpha = 0.6, debuffStripeColorB = 0.2, debuffStripeColorG = 0.2, debuffStripeColorR = 0.8,
    debuffStripeEdge = "BOTTOM", debuffStripeHeight = 3, detachedPowerBarFrameLevelOffset = 6,
    detachedPowerBarHeight = 6, detachedPowerBarOffsetY = -4, dispelEnabled = true, dispelOverlayAlpha = 0.35,
    dispelOverlayOnHealth = true, dispelOverlayStrata = "AUTO", dispelOverlayStyle = "FULL",
    dispelOverlayTrigger = "BORDER", dispelSymbolAlpha = 1, dispelSymbolAnchor = "TOPRIGHT",
    dispelSymbolGrowth = "RIGHT", dispelSymbolLayer = 8, dispelSymbolMode = "ALL", dispelSymbolSize = 12,
    dispelSymbolSpacing = 2, dispelSymbolStrata = "AUTO", dispelSymbolStyle = "BLIZZARD",
    embedPowerBarIntoHealth = true, friendlyBossColumns = 1, friendlyBossHealerOnly = true, friendlyBossHeight = 24,
    friendlyBossTextSize = 11, friendlyBossWidth = 100, friendlyBossX = 250, friendlyBossY = 150, groupBorderA = 0.95,
    groupBorderB = 1, groupBorderG = 0.68, groupBorderPadding = 2, groupBorderR = 0.38, groupBorderSize = 1,
    groupNumberAnchor = "BOTTOMRIGHT", groupNumberSize = 10, groupNumberStyle = "PAREN", growth = "DOWN",
    healAbsorbAnchorMode = 3, healAbsorbBarOpacity = 1, healAbsorbBarTexture = "Solid", healAbsorbEnabled = true,
    healPredAnchorMode = 3, healPredictionBarOpacity = 0.45, healerManaHeight = 24, healerManaShowValue = true,
    healerManaTextB = 1, healerManaTextG = 1, healerManaTextR = 1, healerManaTextSize = 11, healerManaWidth = 100,
    healerManaX = 250, healerManaY = -150, healthColorMode = "CLASS", healthCustomB = 0.2, healthCustomG = 0.8,
    healthCustomR = 0.2, healthFadeAlpha = 0.45, healthFadeThreshold = 95, hideInClientScene = true, hlFocusColorB = 1,
    hlFocusColorG = 0.5, hlFocusColorR = 0.5, hlFocusEnabled = true, hlFocusSize = 2, hpBgAlpha = 0.85,
    hpFullValueShort = true, iconStyle = "MSUF_ROLES", leaderIconAnchor = "TOPRIGHT", leaderIconLayer = 2,
    leaderIconSize = 12, leaderIconStyle = "DEFAULT", levelTextAnchor = "BOTTOMLEFT", levelTextDifficultyColor = true,
    levelTextLayer = 7, levelTextSize = 10, levelTextX = 2, levelTextY = 2, nameBarAlpha = 0.95, nameBarB = 0.05,
    nameBarG = 0.05, nameBarHeight = 14, nameBarR = 0.05, nameColorB = 1, nameColorG = 1, nameColorMode = "DEFAULT",
    nameColorR = 1, nameTextLayer = 5, offlineAlpha = 0.5, oocFadeAlpha = 0.5, overAbsorbOverlay = true,
    petsColumns = 1, petsHeight = 24, petsMaxCount = 40, petsTextSize = 11, petsWidth = 100, petsX = -250, petsY = -150,
    phaseAnchor = "TOPLEFT", phaseIcon = true, phaseIconSize = 14, phaseIconStyle = "DEFAULT", phaseLayer = 3,
    point = "CENTER", powerBarBorderThickness = 1, powerBarEnabled = true, powerFontSize = 9, powerShowHealer = true,
    powerShowTank = true, powerTextCenter = "PERCENT", powerTextLayer = 2, powerTextLeft = "NONE",
    powerTextRight = "NONE", pvpIcon = true, pvpIconAnchor = "TOPLEFT", pvpIconLayer = 3, pvpIconStyle = "DEFAULT",
    pvpIconX = 14, raidManagerMode = "AUTO", raidMarkerAnchor = "CENTER", raidMarkerLayer = 3,
    raidMarkerStyle = "DEFAULT", rangeFadeAlpha = 0.4, rangeFadeEnabled = true, rangeFadeLayerMode = "frame",
    readyCheckAnchor = "CENTER", readyCheckIcon = true, readyCheckIconStyle = "DEFAULT", readyCheckLayer = 4,
    readyCheckSize = 16, resurrectAnchor = "CENTER", resurrectIcon = true, resurrectIconSize = 16,
    resurrectIconStyle = "DEFAULT", resurrectLayer = 4, roleIconAnchor = "LEFT", roleIconLayer = 1,
    roleIconStyle = "DEFAULT", roleOrder = "TANK,HEALER,DAMAGER", showHPText = true, showName = true, showPlayer = true,
    spacing = 1, statusAFKTextAnchor = "CENTER", statusAFKTextLayer = 7, statusAFKTextSize = 14,
    statusAFKTimerOffsetY = -10, statusAFKTimerTextAnchor = "CENTER", statusAFKTimerTextLayer = 7,
    statusAFKTimerTextSize = 10, statusGhostTextAnchor = "CENTER", statusGhostTextLayer = 7, statusGhostTextSize = 14,
    statusTextAnchor = "CENTER", statusTextLayer = 7, statusTextSize = 14, summonAnchor = "CENTER", summonIcon = true,
    summonIconSize = 16, summonIconStyle = "DEFAULT", summonLayer = 4, targetB = 1, targetG = 1, targetIndicator = true,
    targetR = 1, targetsColumns = 1, targetsHeight = 24, targetsTextSize = 11, targetsWidth = 100, targetsX = -250,
    targetsY = 150, tempMaxHealthBackgroundOpacity = 0.65, tempMaxHealthColorB = 0.1, tempMaxHealthColorG = 0.1,
    tempMaxHealthColorR = 0.7, tempMaxHealthOpacity = 1, tempMaxHealthTexture = "Solid", textLayer = 5,
    tier10Growth = "INHERIT", tier20Growth = "INHERIT", tier25Growth = "INHERIT", tier40Growth = "INHERIT",
    unitsPerColumn = 5, useGlobalFontColor = true,
}
-- Stored revision of a sparse profile. The exact-current guard in 6.50x
-- rejects 17.5 and enters its heavy normalizer, which can rerun migrations.
-- V2 keeps known migration markers when saving; older V2 masks still decode.
-- These protections do not establish complete backward compatibility.
local sparseToken = 17.5
local sparseScopes = { "general", "gf_party", "gf_raid", "gf_mythicraid" }
local sparseDefaults = { sparseGeneralV1, sparseGroupV1, sparseGroupV1, sparseGroupV1 }

local function Plain(value)
    return not MSUF.Util.IsSecret(value) and type(value) == "table" and getmetatable(value) == nil
end

-- A shared owner could serialize twice, with only one copy decoded later.
-- Reject aliases to an edited owner, cycles, secrets and unsupported SV values.
-- Unrelated tables and their scalar/list/user content are never edited.
local function SafeTree(value, profile, general, party, raid, mythic, depth)
    if MSUF.Util.IsSecret(value) then return false end
    local kind = type(value)
    if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
    if kind ~= "table" then return kind == "string" or kind == "boolean" end
    if depth > 64 or getmetatable(value) ~= nil then return false end
    if value == profile or value == general or value == party or value == raid or value == mythic then return false end
    for key, child in pairs(value) do
        if MSUF.Util.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return false end
        if not SafeTree(child, profile, general, party, raid, mythic, depth + 1) then return false end
    end
    return true
end

-- skipTree: the caller already scanned the whole SavedVariables root once.
local function ValidOwners(profile, complete, skipTree)
    if not Plain(profile) then return false end
    local general, party, raid, mythic = profile.general, profile.gf_party, profile.gf_raid, profile.gf_mythicraid
    if not Plain(general) or not Plain(party) or not Plain(raid) or not Plain(mythic) then return false end
    if general == party or general == raid or general == mythic or party == raid or party == mythic or raid == mythic then
        return false
    end
    for i = 1, #sparseScopes do
        local owner = profile[sparseScopes[i]]
        for key in pairs(sparseDefaults[i]) do
            local value = owner[key]
            if MSUF.Util.IsSecret(value) or (complete and value == nil) then return false end
        end
    end
    if skipTree then return true end
    for key, value in pairs(profile) do
        if MSUF.Util.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return false end
        if key == "general" or key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" then
            for field, child in pairs(value) do
                if MSUF.Util.IsSecret(field) or (type(field) ~= "string" and type(field) ~= "number") then return false end
                if not SafeTree(child, profile, general, party, raid, mythic, 1) then return false end
            end
        elseif not SafeTree(value, profile, general, party, raid, mythic, 1) then
            return false
        end
    end
    return true
end

local function FillSparseDefaults(profile)
    local count = 0
    for i = 1, #sparseScopes do
        local owner = profile[sparseScopes[i]]
        for key, value in pairs(sparseDefaults[i]) do
            if owner[key] == nil then
                owner[key] = value
                count = count + 1
            end
        end
    end
    return count
end

local function RestoreLegacyPersistence(profile)
    if not Plain(profile) or MSUF.Util.IsSecret(profile._msufDefaultsRevision)
        or (profile._msufDefaultsRevision ~= sparseToken and profile._msufDefaultsRevision ~= "MSUF_SPARSE_DEFAULTS_1")
        or not ValidOwners(profile, false) then return false end
    FillSparseDefaults(profile)
    profile._msufDefaultsRevision = 17
    return true
end

-- One pass over the whole SavedVariables root per logout replaces the repeated
-- scan of every other profile for each candidate. It rejects every value
-- the codec cannot store (secrets, metatables, cycles, unsupported types or
-- keys, nesting deeper than 64 below an owner field) and counts how often each
-- table is referenced. A profile is stored sparse only when its profile table
-- and every ancestor of an edited table are referenced exactly once, so no
-- other path can serialize a second copy of an edited owner. Numeric-keyed
-- tables are recorded here too; V2 never edits a list or anything inside it.
local function CountTables(value, refs, onPath, depth, lists)
    if MSUF.Util.IsSecret(value) then return false end
    local kind = type(value)
    if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
    if kind ~= "table" then return kind == "string" or kind == "boolean" end
    if depth > 68 or getmetatable(value) ~= nil or onPath[value] then return false end
    local seen = refs[value]
    refs[value] = (seen or 0) + 1
    if seen then return true end
    onPath[value] = true
    for key, child in pairs(value) do
        if MSUF.Util.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return false end
        if type(key) == "number" then lists[value] = true end
        if not CountTables(child, refs, onPath, depth + 1, lists) then return false end
    end
    onPath[value] = nil
    return true
end

-- One reference/list/path scratch set reused by every walk (logout persists
-- allocate nothing after the first); cleared after each walk so no saved table
-- stays referenced.
local scratchRefs, scratchLists, scratchPath = {}, {}, {}
local function ClearScratch()
    for key in pairs(scratchRefs) do scratchRefs[key] = nil end
    for key in pairs(scratchLists) do scratchLists[key] = nil end
    for key in pairs(scratchPath) do scratchPath[key] = nil end
end


Parts.ClearScratch = ClearScratch
Parts.CountTables = CountTables
Parts.Plain = Plain
Parts.RestoreLegacyPersistence = RestoreLegacyPersistence
Parts.scratchLists = scratchLists
Parts.scratchPath = scratchPath
Parts.scratchRefs = scratchRefs
Parts.sparseToken = sparseToken
