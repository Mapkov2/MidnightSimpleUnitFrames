local _, MSUF = ...

-- Generated persistence entries of tools/fixtures/defaults/schema.lua. The
-- complete schema verifies every provider. The storage codec below restores
-- its versioned scalar defaults before ordinary migrations or runtime readers.
local Schema = { Version = 1 }
MSUF.DefaultsSchema = Schema
local entries = {
    { scope = "general", key = "previewDragHintAnimationEnabled", kind = "boolean", default = true },
    { scope = "general", key = "showGameMenuButton", kind = "boolean", default = true },
    { scope = "general", key = "_msufPreviewDragHintExperienced", kind = "boolean", default = true, normalizerOnly = true },
}
Schema.PersistenceEntries = entries

local stages = {
    ["bars_01"] = {
        castbarInterruptColor = "red",
        castbarInterruptibleColor = "turquoise",
        castbarNonInterruptibleColor = "red",
        playerCastbarOverrideEnabled = true,
    },
    ["bars_02"] = {
        castbarFillDirection = "RTL",
        playerCastbarOverrideB = 1,
        playerCastbarOverrideG = 1,
        playerCastbarOverrideR = 1,
    },
    ["bars_03"] = {
        castbarAccentLastTick = false,
        castbarShowChannelTicks = false,
        castbarShowLatencyText = false,
        kickReadyTimeMarker = false,
        kickReadyTimeSegment = false,
    },
    ["bars_04"] = {
        empowerColorStages = true,
        empowerStageBlink = true,
        gcdBarCombatOnly = false,
        gcdBarDetached = false,
        gcdBarHeight = 12,
        gcdBarIdle = false,
        gcdBarOpacity = 100,
        gcdBarWidth = 180,
        gcdBarX = 0,
        gcdBarY = -180,
        showGCDBar = false,
        showGCDBarSpell = true,
        showGCDBarTime = true,
    },
    ["bars_05"] = {
        enableArenaCastbar = true,
        enableBossCastbar = true,
        enableFocusCastbar = true,
        enablePlayerCastbar = true,
        enableTargetCastbar = true,
    },
    ["bars_06"] = {
        bossCastTimeFormat = "CURRENT",
        castbarFocusTimeFormat = "CURRENT",
        castbarPlayerTimeFormat = "CURRENT",
        castbarTargetTimeFormat = "CURRENT",
        showArenaCastTime = true,
        showBossCastTime = true,
        showFocusCastTime = true,
        showPlayerCastTime = true,
        showTargetCastTime = true,
    },
    ["bars_07"] = {
        bossCastbarHeight = 12,
        bossCastbarOffsetX = 2,
        bossCastbarOffsetY = -46,
        bossCastbarWidth = 176,
    },
    ["bars_08"] = {
        castbarShowIcon = true,
        castbarShowSpellName = true,
    },
    ["bars_09"] = {
        castbarFocusOffsetX = 2,
        castbarFocusOffsetY = -50,
        castbarIconOffsetX = 0,
        castbarIconOffsetY = 0,
        castbarIconZoom = 100,
        castbarPlayerOffsetX = -2,
        castbarPlayerOffsetY = -59,
        castbarPlayerTimeOffsetX = -2,
        castbarPlayerTimeOffsetY = 0,
        castbarSpellNameFontSize = 0,
        castbarTargetOffsetX = 0,
        castbarTargetOffsetY = -60,
        castbarTimeFontSize = 0,
    },
    ["bars_10"] = {
        castbarFocusBarHeight = 18,
        castbarFocusBarWidth = 175,
        castbarPlayerBarHeight = 18,
        castbarPlayerBarWidth = 271,
        castbarPlayerPreviewEnabled = true,
        castbarTargetBarHeight = 18,
        castbarTargetBarWidth = 272,
    },
    ["bars_11"] = {
        auraFontSize = 25,
        hpFontSize = 14,
        nameFontSize = 14,
        powerFontSize = 12,
    },
    ["bars_12"] = {
        castbarShowGlow = false,
        castbarShowSpark = false,
        castbarSparkOverflow = true,
    },
    ["bars_13"] = {
        castbarFocusShowIcon = true,
        castbarFocusShowSpellName = true,
        castbarFocusShowTargetName = false,
        castbarPlayerShowIcon = true,
        castbarPlayerShowSpellName = true,
        castbarTargetShowIcon = true,
        castbarTargetShowSpellName = true,
        castbarTargetShowTargetName = false,
        showArenaCastTargetName = false,
        showBossCastTargetName = false,
    },
    ["bars_14"] = {
        castbarFocusIconOffsetX = 0,
        castbarFocusIconOffsetY = 0,
        castbarFocusTextOffsetX = 0,
        castbarFocusTextOffsetY = 0,
        castbarPlayerIconOffsetX = 0,
        castbarPlayerIconOffsetY = 0,
        castbarPlayerTextOffsetX = 0,
        castbarPlayerTextOffsetY = 0,
        castbarTargetIconOffsetX = 0,
        castbarTargetIconOffsetY = 0,
        castbarTargetTextOffsetX = 0,
        castbarTargetTextOffsetY = 0,
    },
    ["bars_15"] = {
        bossCastIconOffsetX = 0,
        bossCastIconOffsetY = 0,
        bossCastTextOffsetX = 0,
        bossCastTextOffsetY = 0,
        bossCastTimeOffsetX = 0,
        bossCastTimeOffsetY = 0,
        bossPreviewEnabled = true,
        showBossCastIcon = true,
        showBossCastName = true,
    },
    ["bars_16"] = {
        arenaCastIconOffsetX = 0,
        arenaCastIconOffsetY = 0,
        arenaCastTextOffsetX = 0,
        arenaCastTextOffsetY = 0,
        arenaCastTimeOffsetX = 0,
        arenaCastTimeOffsetY = 0,
        arenaPreviewEnabled = true,
        showArenaCastIcon = true,
        showArenaCastName = true,
    },
    ["bars_17"] = {
        enableFocusKickIcon = false,
        focusKickIconHeight = 40,
        focusKickIconOffsetX = 300,
        focusKickIconOffsetY = 0,
        focusKickIconWidth = 40,
        focusKickShowCastbar = false,
    },
    ["bars_18"] = {
        barBackgroundTexture = "Solid",
        barTexture = "MSUF Lucent",
    },
    ["bars_19"] = {
        absorbBarOpacity = 1,
        healAbsorbBarOpacity = 1,
        tempMaxHealthEnabled = false,
    },
    ["bars_20"] = {
        tempMaxHealthBackgroundOpacity = 0.65,
        tempMaxHealthColorB = 0.10,
        tempMaxHealthColorG = 0.10,
        tempMaxHealthColorR = 0.70,
        tempMaxHealthOpacity = 1,
    },
    ["bars_21"] = {
        hpTextMode = "FULL_PLUS_PERCENT",
        hpTextSeparator = "-",
    },
    ["bars_22"] = {
        healAbsorbAnchorMode = 3,
        healAbsorbEnabled = true,
        healPredAllHealers = false,
        healPredAnchorMode = 3,
        healPredictionBarHeight = 0,
        healPredictionBarOffsetY = 0,
    },
    ["bars_23"] = {
        absorbBarHeight = 0,
        absorbBarOffsetY = 0,
        healAbsorbBarHeight = 0,
        healAbsorbBarOffsetY = 0,
    },
    ["bars_24"] = {
        fullHealthAbsorbStripe = false,
        overAbsorbOverlay = true,
    },
    ["base_01"] = {
        darkBarTone = "black",
        darkMode = false,
    },
    ["base_02"] = {
        enableGradient = false,
        enableHealthGradient = true,
    },
    ["base_03"] = {
        healthLossColorB = 0.08,
        healthLossColorG = 0.55,
        healthLossColorR = 1,
        powerLossColorB = 1,
        powerLossColorG = 0.90,
        powerLossColorR = 0.70,
    },
    ["base_04"] = {
        gradientDirDown = false,
        gradientDirLeft = false,
        gradientDirRight = false,
        gradientDirUp = false,
    },
    ["base_05"] = {
        powerGradientDirDown = false,
        powerGradientDirLeft = false,
        powerGradientDirRight = false,
        powerGradientDirUp = false,
    },
    ["base_06"] = {
        npcClassColorBar = false,
        npcTypeColorBar = true,
        npcTypeColorText = true,
    },
    ["base_07"] = {
        leaderIconLayer = 7,
        leaderIconOffsetX = 0,
        leaderIconOffsetY = 3,
        leaderIconStyle = "BLIZZARD",
        showLeaderIcon = true,
    },
    ["base_08"] = {
        levelIndicatorOffsetX = 0,
        levelIndicatorOffsetY = 0,
    },
    ["base_09"] = {
        levelIndicatorLayer = 7,
        showRaidGroupInName = false,
    },
    ["base_10"] = {
        raidGroupNameOffsetX = 3,
        raidGroupNameOffsetY = 0,
    },
    ["base_11"] = {
        incomingResIndicatorLayer = 7,
        showCombatStateIndicator = true,
    },
    ["base_12"] = {
        combatStateIndicatorLayer = 7,
        pvpIndicatorAnchor = "TOPRIGHT",
        pvpIndicatorLayer = 7,
        pvpIndicatorOffsetX = 0,
        pvpIndicatorOffsetY = 0,
        pvpIndicatorSize = 18,
        showPvpIndicator = true,
    },
    ["base_13"] = {
        restedStateIndicatorAnchor = "TOPLEFT",
        restedStateIndicatorIconStyle = "BLIZZARD",
        restedStateIndicatorSymbol = "rested_blizzard_animated",
    },
    ["base_14"] = {
        restedStateIndicatorLayer = 25,
        stateIconsTestMode = false,
    },
    ["base_15"] = {
        showLevel = false,
        showRaidMarker = true,
    },
    ["shell_01"] = {
        anchorName = "UIParent",
        anchorToCooldown = false,
    },
    ["shell_02"] = {
        disableScaling = false,
        globalUiScalePreset = "auto",
    },
    ["shell_03"] = {
        flashFullH = 700,
        flashFullPoint = "CENTER",
        flashFullRelPoint = "CENTER",
        flashFullW = 900,
        flashFullX = -60,
        flashFullXpx = -60,
        flashFullY = 10,
        flashFullYpx = 10,
        msufUiScale = 1.0,
        tipCycleIndex = 11,
    },
    ["shell_04"] = {
        blizzardEditModeIntegration = true,
        dandersEditModeIntegration = true,
        detailsEditModeIntegration = true,
        dominosEditModeIntegration = true,
        grid2EditModeIntegration = true,
    },
    ["shell_05"] = {
        colorHealthTextByHealth = false,
        hideAdvancedMenu = true,
        previewDragHintAnimationEnabled = true,
        slashMenuSnapEnabled = true,
    },
    ["shell_06"] = {
        classPowerPreviewGuidesEnabled = false,
        showGameMenuButton = true,
        unitPreviewGuidesEnabled = false,
    },
    ["shell_07"] = {
        editModeGridEnabled = true,
        editModeGridStep = 20,
        editModeHideWhiteArrows = true,
        editModeSnapEnabled = false,
        editModeSnapMode = "grid",
        editModeSnapModeFrames = false,
        editModeSnapModeGrid = true,
        linkEditModes = true,
    },
    ["shell_08"] = {
        boldText = false,
        nameClassColor = false,
        nameNpcClassColor = false,
        noOutline = false,
        npcNameRed = false,
    },
    ["shell_09"] = {
        fontMonochrome = false,
        fontSlug = false,
        textBackdrop = true,
    },
    ["shell_10"] = {
        dispelBorderShowOn = "BOTH",
        dispelBorderTrigger = "DISPEL_TYPE",
        dispelOutlineMode = 1,
        unitDispelOverlayAlpha = 0.35,
        unitDispelOverlayEnabled = false,
        unitDispelOverlayOnHealth = true,
        unitDispelOverlayStyle = "FULL",
        unitDispelOverlayTrigger = "BORDER",
    },
    ["shell_11"] = {
        unitDispelSymbolAlpha = 1,
        unitDispelSymbolAnchor = "TOPRIGHT",
        unitDispelSymbolEnabled = false,
        unitDispelSymbolGrowth = "RIGHT",
        unitDispelSymbolLayer = 8,
        unitDispelSymbolMode = "ALL",
        unitDispelSymbolSize = 14,
        unitDispelSymbolSpacing = 2,
        unitDispelSymbolStrata = "AUTO",
        unitDispelSymbolStyle = "BLIZZARD",
        unitDispelSymbolTrigger = "BORDER",
        unitDispelSymbolX = 0,
        unitDispelSymbolY = 0,
    },
    ["shell_12"] = {
        disableUnitInfoTooltips = true,
        unitInfoTooltipStyle = "classic",
    },
    ["units_01"] = {
        portraitHeight = 0,
        portraitPlacement = "ATTACHED",
        portraitShape = "SQUARE",
        portraitSizeOverride = 0,
        portraitWidth = 0,
    },
    ["units_02"] = {
        portraitAlpha = 100,
        portraitBgColorA = 0.85,
        portraitBgColorB = 0.05,
        portraitBgColorG = 0.05,
        portraitBgColorR = 0.05,
        portraitBgEnabled = false,
        portraitBorderColorA = 1,
        portraitBorderColorB = 1,
        portraitBorderColorG = 1,
        portraitBorderColorR = 1,
        portraitBorderStyle = "NONE",
        portraitBorderThickness = 2,
        portraitClassStyle = "BLIZZARD",
        portraitDetachedPoint = "RIGHT",
        portraitDetachedTo = "LEFT",
        portraitEdgeSoftness = 0,
        portraitLevelOffset = 7,
        portraitOffsetX = 0,
        portraitOffsetY = 0,
        portraitOverlayAlign = "LEFT",
        portraitPanX = 0,
        portraitPanY = 0,
        portraitZoom = 100,
    },
    ["units_03"] = {
        portraitBorderArt = "FLAT",
        portraitBorderDirection = "UP",
        portraitFillBorder = false,
    },
}
Schema.SeedStages = stages

function Schema.SeedGeneral(owner, id)
    for key, value in pairs(stages[id]) do
        if owner[key] == nil then owner[key] = value end
    end
end


function Schema.FillMenuDefaults(profile)
    if type(profile) ~= "table" then return end
    local general = profile.general
    if type(general) ~= "table" then
        general = {}
        profile.general = general
    end
    for i = 1, #entries do
        local entry = entries[i]
        if not entry.normalizerOnly and general[entry.key] == nil then general[entry.key] = entry.default end
    end
end

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

-- BEGIN FROZEN SPARSE V2 DATA
-- Generated by tools/defaults_schema_generate.lua --sparse-v2; never reorder this wire dictionary.
local sparseV2Fields = {
    { "bossLayoutMode", "VERTICAL_DOWN" },
    { "eliteIconAnchor", "TOPRIGHT" },
    { "eliteIconLayer", 25 },
    { "eliteIconOffsetX", 18 },
    { "eliteIconSize", 18 },
    { "eliteIconStyle", "BLIZZARD" },
    { "embedPowerBarIntoHealth", true },
    { "enabled", true },
    { "height", 30 },
    { "hpBgAlpha", 0.84999999999999998 },
    { "hpOffsetX", -2 },
    { "hpOffsetY", -18 },
    { "hpTextLayer", 5 },
    { "hpTextMode", "CURPERCENT" },
    { "hpTextSeparator", "-" },
    { "nameOffsetX", 7 },
    { "nameOffsetY", -4 },
    { "nameTextAnchor", "TOPLEFT" },
    { "nameTextLayer", 5 },
    { "oocFadeAlpha", 0.5 },
    { "portraitAlpha", 100 },
    { "portraitBgColorA", 0.84999999999999998 },
    { "portraitBgColorB", 0.050000000000000003 },
    { "portraitBgColorG", 0.050000000000000003 },
    { "portraitBgColorR", 0.050000000000000003 },
    { "portraitBlizzardDirection", "AUTO" },
    { "portraitBorderArt", "FLAT" },
    { "portraitBorderColorA", 1 },
    { "portraitBorderColorB", 1 },
    { "portraitBorderColorG", 1 },
    { "portraitBorderColorR", 1 },
    { "portraitBorderDirection", "UP" },
    { "portraitBorderStyle", "NONE" },
    { "portraitBorderThickness", 2 },
    { "portraitClassStyle", "BLIZZARD" },
    { "portraitDetachedPoint", "RIGHT" },
    { "portraitDetachedTo", "LEFT" },
    { "portraitDragonInInstances", true },
    { "portraitDragonLayer", "OVERLAY" },
    { "portraitDragonLevel", 1 },
    { "portraitDragonScale", 100 },
    { "portraitLevelOffset", 7 },
    { "portraitMode", "OFF" },
    { "portraitOverlayAlign", "LEFT" },
    { "portraitPlacement", "ATTACHED" },
    { "portraitRender", "2D" },
    { "portraitShape", "SQUARE" },
    { "portraitSizeMode", "UNIFORM" },
    { "portraitZoom", 100 },
    { "powerBarAlpha", 1 },
    { "powerBarBgAlpha", 0.84999999999999998 },
    { "powerBarBorderThickness", 1 },
    { "powerFontSize", 10 },
    { "powerOffsetX", -6 },
    { "powerOffsetY", 2 },
    { "powerTextCenter", "NONE" },
    { "powerTextLayer", 2 },
    { "powerTextLeft", "NONE" },
    { "powerTextMode", "CURPERCENT" },
    { "powerTextRight", "CURPERCENT" },
    { "powerTextSeparator", "-" },
    { "pvpIndicatorAnchor", "TOPRIGHT" },
    { "pvpIndicatorLayer", 7 },
    { "pvpIndicatorSize", 18 },
    { "raidGroupNameAnchor", "NAMERIGHT" },
    { "raidGroupNameOffsetX", 3 },
    { "raidGroupNameStyle", "PAREN" },
    { "raidMarkerAnchor", "TOPLEFT", retain = true },
    { "raidMarkerLayer", 7, retain = true },
    { "raidMarkerOffsetX", 16, retain = true },
    { "raidMarkerOffsetY", 3, retain = true },
    { "raidMarkerSize", 14, retain = true },
    { "rangeFadeAlpha", 0.40000000000000002 },
    { "rangeFadeEnabled", true },
    { "rangeFadeLayerMode", "frame" },
    { "showEliteIcon", true },
    { "showHP", true },
    { "showInterrupt", true },
    { "showName", true },
    { "showPower", true },
    { "showPowerBar", true },
    { "showRaidMarker", true, retain = true },
    { "showTrinket", true },
    { "spacing", -96 },
    { "statusDeadTextEnabled", true },
    { "statusGhostTextEnabled", true },
    { "texLayer2Alpha", 1 },
    { "texLayer2Anchor", "TOP" },
    { "texLayer2AnchorTarget", "FRAME" },
    { "texLayer2BlendMode", "BLEND" },
    { "texLayer2ColorB", 1 },
    { "texLayer2ColorG", 1 },
    { "texLayer2ColorMode", "CUSTOM" },
    { "texLayer2ColorR", 1 },
    { "texLayer2ColorTreatment", "ORIGINAL" },
    { "texLayer2CropMode", "FULL" },
    { "texLayer2FollowFrameAlpha", true },
    { "texLayer2GradientDirRight", true },
    { "texLayer2Height", 16 },
    { "texLayer2Level", 1 },
    { "texLayer2Strata", "AUTO" },
    { "texLayer2Visibility", "ALWAYS" },
    { "texLayer3Alpha", 1 },
    { "texLayer3Anchor", "TOP" },
    { "texLayer3AnchorTarget", "FRAME" },
    { "texLayer3BlendMode", "BLEND" },
    { "texLayer3ColorB", 1 },
    { "texLayer3ColorG", 1 },
    { "texLayer3ColorMode", "CUSTOM" },
    { "texLayer3ColorR", 1 },
    { "texLayer3ColorTreatment", "ORIGINAL" },
    { "texLayer3CropMode", "FULL" },
    { "texLayer3FollowFrameAlpha", true },
    { "texLayer3GradientDirRight", true },
    { "texLayer3Height", 16 },
    { "texLayer3Level", 1 },
    { "texLayer3Strata", "AUTO" },
    { "texLayer3Visibility", "ALWAYS" },
    { "texLayerAlpha", 1 },
    { "texLayerAnchor", "TOP" },
    { "texLayerAnchorTarget", "FRAME" },
    { "texLayerBlendMode", "BLEND" },
    { "texLayerColorB", 1 },
    { "texLayerColorG", 1 },
    { "texLayerColorMode", "CUSTOM" },
    { "texLayerColorR", 1 },
    { "texLayerColorTreatment", "ORIGINAL" },
    { "texLayerCropMode", "FULL" },
    { "texLayerFollowFrameAlpha", true },
    { "texLayerGradientDirRight", true },
    { "texLayerHeight", 16 },
    { "texLayerLevel", 1 },
    { "texLayerStrata", "AUTO" },
    { "texLayerVisibility", "ALWAYS" },
    { "textCenter", "NONE" },
    { "textLeft", "NONE" },
    { "textRight", "CURPERCENT" },
    { "trinketAnchor", "RIGHT" },
    { "trinketLayer", 10 },
    { "trinketOffsetX", 4 },
    { "trinketSize", 20 },
    { "unitDispelOverlayAlpha", 0.34999999999999998 },
    { "unitDispelOverlayOnHealth", true },
    { "unitDispelOverlayStyle", "FULL" },
    { "unitDispelOverlayTrigger", "BORDER" },
    { "unitDispelSymbolAlpha", 1 },
    { "unitDispelSymbolAnchor", "TOPRIGHT" },
    { "unitDispelSymbolGrowth", "RIGHT" },
    { "unitDispelSymbolLayer", 8 },
    { "unitDispelSymbolMode", "ALL" },
    { "unitDispelSymbolSize", 14 },
    { "unitDispelSymbolSpacing", 2 },
    { "unitDispelSymbolStrata", "AUTO" },
    { "unitDispelSymbolStyle", "BLIZZARD" },
    { "width", 180 },
    { "exclusive", "none" },
    { "buffCooldownTextSize", 14 },
    { "buffDurationBarHeight", 2 },
    { "buffGroupOffsetX", -1 },
    { "buffIconZoom", 100 },
    { "buffLayer", 5 },
    { "buffStackTextOffsetX", -1 },
    { "buffStackTextOffsetY", 1 },
    { "buffStackTextSize", 14 },
    { "buffStrata", "AUTO" },
    { "debuffCooldownTextSize", 14 },
    { "debuffDurationBarHeight", 2 },
    { "debuffIconZoom", 100 },
    { "debuffLayer", 6 },
    { "debuffStackTextOffsetX", -1 },
    { "debuffStackTextOffsetY", 1 },
    { "debuffStackTextSize", 14 },
    { "debuffStrata", "AUTO" },
    { "buffCooldownDecimalSeconds", 3 },
    { "buffCooldownTextAnchor", "CENTER" },
    { "buffDurationBarDirection", "REMAINING" },
    { "buffDurationBarDisplay", "BAR_ONLY" },
    { "buffDurationBarPosition", "BOTTOM" },
    { "buffFrameEffectPriority", 5 },
    { "buffFrameEffectStrata", "AUTO" },
    { "buffFrameEffectThickness", 2 },
    { "buffFrameEffectType", "none" },
    { "buffGrowthX", "RIGHT" },
    { "buffGrowthY", "DOWN" },
    { "buffShowCooldownSwipe", true },
    { "buffShowCooldownText", true },
    { "buffShowStackCount", true },
    { "buffShowTooltip", true },
    { "buffSortMethod", "DEFAULT" },
    { "buffStackCountAnchor", "TOPRIGHT" },
    { "buffStealableStyle", "BORDER_ICON" },
    { "debuffCooldownDecimalSeconds", 3 },
    { "debuffCooldownTextAnchor", "CENTER" },
    { "debuffDurationBarDirection", "REMAINING" },
    { "debuffDurationBarDisplay", "BAR_ONLY" },
    { "debuffDurationBarPosition", "BOTTOM" },
    { "debuffFrameEffectPriority", 5 },
    { "debuffFrameEffectStrata", "AUTO" },
    { "debuffFrameEffectThickness", 2 },
    { "debuffFrameEffectType", "none" },
    { "debuffGrowthX", "RIGHT" },
    { "debuffGrowthY", "DOWN" },
    { "debuffShowCooldownSwipe", true },
    { "debuffShowCooldownText", true },
    { "debuffShowStackCount", true },
    { "debuffShowTooltip", true },
    { "debuffSortMethod", "DEFAULT" },
    { "debuffStackCountAnchor", "TOPRIGHT" },
    { "debuffTypeBorderMode", "OFF" },
    { "showBuffs", true },
    { "showDebuffs", true },
    { "overrideFilters", true },
    { "overrideLayout", true },
    { "overrideSharedLayout", true },
    { "overrideStyle", true },
    { "buff", "RECTANGLE" },
    { "debuff", "RECTANGLE" },
    { "playerDefensives", "FOLLOW_PORTRAIT" },
    { "targetDots", "RECTANGLE" },
    { "styleBorderStyle", "SOLID" },
    { "styleBorderThickness", 1 },
    { "styleShadowSize", 4 },
    { "arenaEditTogether", true },
    { "bossEditTogether", true },
    { "buffSpacing", 2 },
    { "cooldownDecimalSeconds", 3 },
    { "cooldownTextAnchor", "CENTER" },
    { "cooldownTextSize", 14 },
    { "debuffSpacing", 2 },
    { "durationBarDirection", "REMAINING" },
    { "durationBarDisplay", "BAR_ONLY" },
    { "durationBarHeight", 2 },
    { "durationBarPosition", "BOTTOM" },
    { "growth", "RIGHT" },
    { "iconSize", 26 },
    { "iconZoom", 100 },
    { "maxBuffs", 12 },
    { "maxDebuffs", 12 },
    { "perRow", 12 },
    { "showCooldownSwipe", true },
    { "showCooldownText", true },
    { "showInEditMode", true },
    { "showStackCount", true },
    { "showTooltip", true },
    { "spacing", 2 },
    { "stackCountAnchor", "TOPRIGHT" },
    { "stackTextOffsetX", -1 },
    { "stackTextOffsetY", 1 },
    { "stackTextSize", 14 },
    { "showArena", true },
    { "showBoss", true },
    { "showPet", true },
    { "showTarget", true },
    { "altManaColorB", 0.80000000000000004 },
    { "altManaWidthMode", "player" },
    { "barBackgroundAlpha", 90 },
    { "barOutlineThickness", 2 },
    { "classPowerBgAlpha", 0.29999999999999999 },
    { "classPowerColorByType", true },
    { "classPowerComboPointColorMode", "default" },
    { "classPowerEmptyAlpha", 0.29999999999999999 },
    { "classPowerFilledAlpha", 1 },
    { "classPowerFontSize", 16 },
    { "classPowerFrameLevelOffset", 5 },
    { "classPowerShape", "BAR" },
    { "classPowerShapeAlign", "CENTER" },
    { "classPowerShowPrediction", true },
    { "classPowerTextLayer", 5 },
    { "classPowerTickWidth", 1 },
    { "classPowerWidthMode", "player" },
    { "guardianIronfurShowHashLines", true },
    { "playerHPBarAnchor", "CLASS_TOP" },
    { "playerHPBarBgAlpha", 0.34999999999999998 },
    { "playerHPBarColorMode", "GLOBAL" },
    { "playerHPBarFrameLevelOffset", 7 },
    { "playerHPBarGap", 2 },
    { "playerHPBarHeight", 6 },
    { "playerHPBarOrbSize", 54 },
    { "playerHPBarOutline", 1 },
    { "playerHPBarShape", "BAR" },
    { "playerHPBarTextCenter", "NONE" },
    { "playerHPBarTextEnabled", true },
    { "playerHPBarTextLeft", "NONE" },
    { "playerHPBarTextRight", "CURPERCENT" },
    { "playerHPBarTextSize", 14 },
    { "playerHPBarUsePlayerText", true },
    { "playerHPBarWidthMode", "class" },
    { "realtimePowerText", true },
    { "roundedCornerStrength", 3 },
    { "roundedGroupFrames", true },
    { "roundedMouseover", true },
    { "roundedPowerBars", true },
    { "roundedUnitFrames", true },
    { "runeShowTime", true },
    { "runeSortOrder", "asc" },
    { "showArenaPowerBar", true },
    { "showBarBorder", true },
    { "showBossPowerBar", true },
    { "showChargedComboPoints", true },
    { "showClassPower", true },
    { "showEbonMight", true },
    { "showFocusPowerBar", true },
    { "showPlayerPowerBar", true },
    { "showStagger", true },
    { "showTargetPowerBar", true },
    { "slantedGroupFrames", true },
    { "slantedMouseover", true },
    { "slantedPowerBars", true },
    { "slantedUnitFrames", true },
    { "staggerHeight", 4 },
    { "staggerOffsetY", -2 },
    { "showPowerText", true },
    { "anchorToUnitframe", "GLOBAL" },
    { "showPvpIndicator", true },
    { "offsetX", 260 },
    { "offsetY", 180 },
    { "powerBarHeight", 3 },
    { "combatFontSize", 24 },
    { "combatOffsetY", -200 },
    { "combatStateDuration", 1.5 },
    { "combatStateEnterText", "+Combat" },
    { "combatStateFontSize", 24 },
    { "combatStateLeaveText", "-Combat" },
    { "combatStateOffsetY", 80 },
    { "combatTimerAnchor", "none" },
    { "combatTimerClickThrough", true },
    { "crosshairSize", 40 },
    { "crosshairThickness", 2 },
    { "enablePlayerTotems", true },
    { "playerTotemsAnchorFrom", "TOPLEFT" },
    { "playerTotemsAnchorTo", "BOTTOMLEFT" },
    { "playerTotemsIconSize", 24 },
    { "playerTotemsOffsetY", -6 },
    { "Scale", 1 },
    { "minimapPos", 220 },
    { "radius", 80 },
    { "showDead", true },
    { "showGhost", true },
    { "absorbAnchorMode", 5 },
    { "absorbBarColorMigrationV2", true, retain = true },
    { "absorbBarOpacity", 1 },
    { "absorbTextMode", 2 },
    { "aggroIndicatorMode", "off" },
    { "aggroOutlineMode", 1 },
    { "anchorName", "UIParent" },
    { "arenaCastFrameLevelOffset", 6 },
    { "arenaCastIconBorderStyle", "DARK" },
    { "arenaCastIconPosition", "LEFT" },
    { "arenaCastIconSpacing", 1 },
    { "arenaCastIconZoom", 100 },
    { "arenaCastSpellNameAlign", "LEFT" },
    { "arenaCastSpellNameFont", "GLOBAL" },
    { "arenaCastSpellNameOutline", "GLOBAL" },
    { "arenaCastSpellNamePosition", "LEFT" },
    { "arenaCastSpellNameTruncate", "AUTO" },
    { "arenaCastTargetNameAlign", "RIGHT" },
    { "arenaCastTargetNameFontSize", 10 },
    { "arenaCastTargetNameOffsetY", 1 },
    { "arenaCastTargetNamePosition", "BELOW" },
    { "arenaCastTimeFont", "GLOBAL" },
    { "arenaCastTimeFormat", "CURRENT" },
    { "arenaCastTimeOutline", "GLOBAL" },
    { "arenaCastTimePosition", "RIGHT" },
    { "arenaCastbarBackend", "MSUF" },
    { "arenaCastbarHeight", 12 },
    { "arenaCastbarOffsetX", 2 },
    { "arenaCastbarWidth", 176 },
    { "arenaPreviewEnabled", true },
    { "auraFontSize", 25 },
    { "barBackgroundTexture", "Solid" },
    { "barBgColorMode", "custom" },
    { "barBgFillMode", "full" },
    { "barBorderStyle", "THIN" },
    { "barMode", "class" },
    { "barTexture", "MSUF Lucent" },
    { "blizzardEditModeIntegration", true },
    { "bossCastFrameLevelOffset", 6 },
    { "bossCastIconBorderStyle", "DARK" },
    { "bossCastIconPosition", "LEFT" },
    { "bossCastIconSpacing", 1 },
    { "bossCastIconZoom", 100 },
    { "bossCastSpellNameAlign", "LEFT" },
    { "bossCastSpellNameFont", "GLOBAL" },
    { "bossCastSpellNameOutline", "GLOBAL" },
    { "bossCastSpellNamePosition", "LEFT" },
    { "bossCastSpellNameTruncate", "AUTO" },
    { "bossCastTargetNameAlign", "RIGHT" },
    { "bossCastTargetNameFontSize", 10 },
    { "bossCastTargetNameOffsetY", 1 },
    { "bossCastTargetNamePosition", "BELOW" },
    { "bossCastTimeFont", "GLOBAL" },
    { "bossCastTimeFormat", "CURRENT" },
    { "bossCastTimeOutline", "GLOBAL" },
    { "bossCastTimePosition", "RIGHT" },
    { "bossCastbarBackend", "MSUF" },
    { "bossCastbarHeight", 12 },
    { "bossCastbarOffsetX", 2 },
    { "bossCastbarWidth", 176 },
    { "bossPreviewEnabled", true },
    { "bossTargetHighlightEnabled", true },
    { "bossTargetOutlineMode", 1 },
    { "castbarBackgroundTexture", "Solid" },
    { "castbarFocusBackend", "MSUF" },
    { "castbarFocusBarHeight", 18 },
    { "castbarFocusBarWidth", 175 },
    { "castbarFocusFrameLevelOffset", 6 },
    { "castbarFocusIconBorderStyle", "DARK" },
    { "castbarFocusIconPosition", "LEFT" },
    { "castbarFocusIconSpacing", 1 },
    { "castbarFocusIconZoom", 100 },
    { "castbarFocusOffsetX", 2 },
    { "castbarFocusOffsetY", -50 },
    { "castbarFocusShowIcon", true },
    { "castbarFocusShowSpellName", true },
    { "castbarFocusSpellNameAlign", "LEFT" },
    { "castbarFocusSpellNameFont", "GLOBAL" },
    { "castbarFocusSpellNameOutline", "GLOBAL" },
    { "castbarFocusSpellNamePosition", "LEFT" },
    { "castbarFocusSpellNameTruncate", "AUTO" },
    { "castbarFocusTargetNameAlign", "RIGHT" },
    { "castbarFocusTargetNameFontSize", 10 },
    { "castbarFocusTargetNameOffsetY", 1 },
    { "castbarFocusTargetNamePosition", "BELOW" },
    { "castbarFocusTimeFont", "GLOBAL" },
    { "castbarFocusTimeFormat", "CURRENT" },
    { "castbarFocusTimeOffsetX", -2 },
    { "castbarFocusTimeOutline", "GLOBAL" },
    { "castbarFocusTimePosition", "RIGHT" },
    { "castbarGlobalHeight", 18 },
    { "castbarGlobalWidth", 200 },
    { "castbarIconZoom", 100 },
    { "castbarInterruptColor", "red" },
    { "castbarInterruptFeedbackDuration", 0.5 },
    { "castbarInterruptibleColor", "turquoise" },
    { "castbarNonInterruptibleColor", "red" },
    { "castbarPlayerBackend", "MSUF" },
    { "castbarPlayerBarHeight", 18 },
    { "castbarPlayerBarWidth", 271 },
    { "castbarPlayerFrameLevelOffset", 6 },
    { "castbarPlayerIconBorderStyle", "DARK" },
    { "castbarPlayerIconPosition", "LEFT" },
    { "castbarPlayerIconSpacing", 1 },
    { "castbarPlayerIconZoom", 100 },
    { "castbarPlayerOffsetX", -2 },
    { "castbarPlayerOffsetY", -59 },
    { "castbarPlayerShowIcon", true },
    { "castbarPlayerShowSpellName", true },
    { "castbarPlayerSpellNameAlign", "LEFT" },
    { "castbarPlayerSpellNameFont", "GLOBAL" },
    { "castbarPlayerSpellNameOutline", "GLOBAL" },
    { "castbarPlayerSpellNamePosition", "LEFT" },
    { "castbarPlayerSpellNameTruncate", "AUTO" },
    { "castbarPlayerTimeFont", "GLOBAL" },
    { "castbarPlayerTimeFormat", "CURRENT" },
    { "castbarPlayerTimeOffsetX", -2 },
    { "castbarPlayerTimeOutline", "GLOBAL" },
    { "castbarPlayerTimePosition", "RIGHT" },
    { "castbarShakeStrength", 8 },
    { "castbarShowIcon", true },
    { "castbarShowSpellName", true },
    { "castbarSparkOverflow", true },
    { "castbarTargetBackend", "MSUF" },
    { "castbarTargetBarHeight", 18 },
    { "castbarTargetFrameLevelOffset", 6 },
    { "castbarTargetIconBorderStyle", "DARK" },
    { "castbarTargetIconPosition", "LEFT" },
    { "castbarTargetIconSpacing", 1 },
    { "castbarTargetIconZoom", 100 },
    { "castbarTargetShowIcon", true },
    { "castbarTargetShowSpellName", true },
    { "castbarTargetSpellNameAlign", "LEFT" },
    { "castbarTargetSpellNameFont", "GLOBAL" },
    { "castbarTargetSpellNameOutline", "GLOBAL" },
    { "castbarTargetSpellNamePosition", "LEFT" },
    { "castbarTargetSpellNameTruncate", "AUTO" },
    { "castbarTargetTargetNameAlign", "RIGHT" },
    { "castbarTargetTargetNameFontSize", 10 },
    { "castbarTargetTargetNameOffsetY", 1 },
    { "castbarTargetTargetNamePosition", "BELOW" },
    { "castbarTargetTimeFont", "GLOBAL" },
    { "castbarTargetTimeFormat", "CURRENT" },
    { "castbarTargetTimeOffsetX", -2 },
    { "castbarTargetTimeOutline", "GLOBAL" },
    { "castbarTargetTimePosition", "RIGHT" },
    { "castbarTexture", "MSUF Lucent" },
    { "colorPowerTextByType", true },
    { "combatStateIndicatorLayer", 7 },
    { "combatStateIndicatorPos", "TOPLEFT" },
    { "dandersEditModeIntegration", true },
    { "darkBarTone", "black" },
    { "darkBgBrightness", 0.25 },
    { "detailsEditModeIntegration", true },
    { "disableUnitInfoTooltips", true },
    { "dispelBorderShowOn", "BOTH" },
    { "dispelOutlineMode", 1 },
    { "dominosEditModeIntegration", true },
    { "dropdownStyleMode", "msuf" },
    { "editModeGridEnabled", true },
    { "editModeHideWhiteArrows", true },
    { "editModeSnapMode", "grid" },
    { "editModeSnapModeGrid", true },
    { "ellesmereEditModeIntegration", true },
    { "empowerColorStages", true },
    { "empowerStageBlink", true },
    { "empowerStageBlinkTime", 0.25 },
    { "enableAbsorbBar", true },
    { "enableArenaCastbar", true },
    { "enableBossCastbar", true },
    { "enableFocusCastbar", true },
    { "enableHealthGradient", true },
    { "enablePlayerCastbar", true },
    { "enableTargetCastbar", true },
    { "flashFullH", 700 },
    { "flashFullPoint", "CENTER" },
    { "flashFullRelPoint", "CENTER" },
    { "flashFullW", 900 },
    { "flashFullX", -60 },
    { "flashFullXpx", -60 },
    { "flashFullY", 10 },
    { "flashFullYpx", 10 },
    { "focusKickIconHeight", 40 },
    { "focusKickIconOffsetX", 300 },
    { "focusKickIconWidth", 40 },
    { "fontColor", "white" },
    { "fontKey", "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf" },
    { "fontShadowDistance", 1 },
    { "fontShadowOpacity", 1 },
    { "fontSize", 14 },
    { "fontTextAlpha", 1 },
    { "gcdBarHeight", 12 },
    { "gcdBarOpacity", 100 },
    { "gcdBarWidth", 180 },
    { "gcdBarY", -180 },
    { "globalUiScalePreset", "auto" },
    { "gradientDirRight", true },
    { "gradientDirection", "RIGHT" },
    { "gradientStrength", 0.45000000000000001 },
    { "grid2EditModeIntegration", true },
    { "healAbsorbAnchorMode", 3 },
    { "healAbsorbBarOpacity", 1 },
    { "healAbsorbEnabled", true },
    { "healPredAnchorMode", 3 },
    { "healPredEnabled", true },
    { "healPredictionBarOpacity", 0.45000000000000001 },
    { "healthGradientHighG", 1 },
    { "healthGradientLowR", 1 },
    { "healthGradientMidG", 1 },
    { "healthGradientMidR", 1 },
    { "hideAdvancedMenu", true },
    { "highlightColor", "white" },
    { "highlightEnabled", true },
    { "highlightStyle", "GRADIENT" },
    { "highlightThickness", 6 },
    { "hpFontSize", 14 },
    { "hpPowerTextSelectedKey", "shared" },
    { "incomingResIndicatorLayer", 7 },
    { "incomingResIndicatorPos", "TOPRIGHT" },
    { "kickReadyAnchor", "RIGHT" },
    { "kickReadyOffsetX", 4 },
    { "kickReadySize", 8 },
    { "kickReadyStyle", "border" },
    { "leaderIconLayer", 7 },
    { "leaderIconOffsetY", 3 },
    { "leaderIconStyle", "BLIZZARD" },
    { "levelIndicatorAnchor", "NAMERIGHT" },
    { "levelIndicatorLayer", 7 },
    { "linkEditModes", true },
    { "menuFontKey", "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf" },
    { "msufUiScale", 1 },
    { "nameFontSize", 14 },
    { "npcColorMode", "reaction" },
    { "npcTypeBoss", true },
    { "npcTypeColorBar", true },
    { "npcTypeColorText", true },
    { "npcTypeFocus", true },
    { "npcTypeTarget", true },
    { "npcTypeToT", true },
    { "nsrtNicknameIntegration", true },
    { "numberAbbrevStyle", "GAME" },
    { "overAbsorbOverlay", true },
    { "playerCastbarOverrideB", 1 },
    { "playerCastbarOverrideEnabled", true },
    { "playerCastbarOverrideG", 1 },
    { "playerCastbarOverrideMode", "CLASS" },
    { "playerCastbarOverrideR", 1 },
    { "playerResourcePingEnabled", true },
    { "powerFontSize", 12 },
    { "powerGradientDirRight", true },
    { "powerGradientDirection", "RIGHT" },
    { "powerGradientStrength", 0.45000000000000001 },
    { "previewDragHintAnimationEnabled", true },
    { "restedStateIndicatorAnchor", "TOPLEFT" },
    { "restedStateIndicatorIconStyle", "BLIZZARD" },
    { "restedStateIndicatorLayer", 25 },
    { "restedStateIndicatorOffsetX", -40 },
    { "restedStateIndicatorOffsetY", 50 },
    { "restedStateIndicatorSize", 39 },
    { "restedStateIndicatorSymbol", "rested_blizzard_animated" },
    { "shortenNameClipSide", "LEFT" },
    { "shortenNameFrontMaskPx", 8 },
    { "shortenNameMaxChars", 6 },
    { "shortenNameShowDots", true },
    { "showArenaCastIcon", true },
    { "showArenaCastName", true },
    { "showArenaCastTime", true },
    { "showBossCastIcon", true },
    { "showBossCastName", true },
    { "showBossCastTime", true },
    { "showCombatStateIndicator", true },
    { "showFocusCastTime", true },
    { "showGCDBarSpell", true },
    { "showGCDBarTime", true },
    { "showGameMenuButton", true },
    { "showIncomingResIndicator", true },
    { "showLeaderIcon", true },
    { "showMinimapIcon", true },
    { "showNavigationIcons", true },
    { "showPlayerCastTime", true },
    { "showRestingIndicator", true },
    { "showSelfHealPrediction", true },
    { "showTargetCastTime", true },
    { "showWelcomeMessage", true },
    { "slashMenuSnapEnabled", true },
    { "tempMaxHealthBackgroundOpacity", 0.65000000000000002 },
    { "tempMaxHealthColorB", 0.10000000000000001 },
    { "tempMaxHealthColorG", 0.10000000000000001 },
    { "tempMaxHealthColorR", 0.69999999999999996 },
    { "tempMaxHealthOpacity", 1 },
    { "tempMaxHealthTexture", "Solid" },
    { "textBackdrop", true },
    { "tipCycleIndex", 11 },
    { "unifiedBarB", 0.90000000000000002 },
    { "unifiedBarG", 0.59999999999999998 },
    { "unifiedBarR", 0.10000000000000001 },
    { "unitDispelOwnershipVersion", 1, retain = true },
    { "unitInfoTooltipStyle", "classic" },
    { "unitTooltipAnchor", "EXTERNAL" },
    { "unitTooltipMode", "ALWAYS" },
    { "unitTooltipModifier", "ALT" },
    { "unitTooltipProvider", "GAME" },
    { "useBarBorder", true },
    { "useClassColors", true },
    { "debuffs", true },
    { "dispels", true },
    { "externals", true },
    { "privateAuras", true },
    { "anchor", "TOPLEFT" },
    { "cooldownAnchor", "CENTER" },
    { "cooldownSize", 10 },
    { "filterToken", "MSUF_GROUP_HIGHLIGHTS_V1" },
    { "growth", "RIGHTDOWN" },
    { "iconScale", 100 },
    { "layer", 8 },
    { "max", 1 },
    { "perRow", 1 },
    { "showCooldown", true },
    { "showStacks", true },
    { "size", 12 },
    { "sortMethod", "DEFAULT" },
    { "stackAnchor", "BOTTOMRIGHT" },
    { "stackSize", 10 },
    { "strata", "AUTO" },
    { "trackedStrata", "AUTO" },
    { "x", 14 },
    { "y", -2 },
    { "anchor", "BOTTOMLEFT" },
    { "dispelBorderMode", "OFF" },
    { "filterToken", "ALL" },
    { "growth", "RIGHTUP" },
    { "layer", 10 },
    { "size", 18 },
    { "x", 20 },
    { "y", 2 },
    { "autoBlacklistBuffs", true },
    { "filterToken", "RAID" },
    { "layer", 11 },
    { "size", 16 },
    { "spacing", 1 },
    { "x", 2 },
    { "blizzardContainerAnchor", "FRAME" },
    { "blizzardDispelMode", "allDispellable" },
    { "blizzardIconSize", 18 },
    { "blizzardOrganizationType", "default" },
    { "blizzardShowCooldownText", true },
    { "profileModelRevision", 1, retain = true },
    { "renderer", "NATIVE_12_1" },
    { "anchor", "RIGHT" },
    { "direction", "LEFT" },
    { "layer", 12 },
    { "showCountdown", true },
    { "size", 10 },
    { "x", -4 },
    { "alpha", 1 },
    { "layer", 9 },
    { "spec", "auto" },
    { "absorbBarTexture", "MSUF Smooth v2" },
    { "aggroEnabled", true },
    { "aggroMode", "ALL" },
    { "aggroR", 1 },
    { "assistIcon", true },
    { "assistIconAnchor", "TOPRIGHT" },
    { "assistIconLayer", 2 },
    { "assistIconSize", 12 },
    { "assistIconStyle", "DEFAULT" },
    { "assistIconX", 14 },
    { "bgB", 0.10000000000000001 },
    { "bgG", 0.10000000000000001 },
    { "bgR", 0.10000000000000001 },
    { "blizzardFallbackMode", "AUTO" },
    { "borderA", 1 },
    { "borderEnabled", true },
    { "borderSize", 1 },
    { "buffCoverageAnchor", "BOTTOM" },
    { "buffCoverageBlessings", true },
    { "buffCoverageIntellect", true },
    { "buffCoverageLayer", 6 },
    { "buffCoverageSize", 14 },
    { "buffCoverageStamina", true },
    { "buffCoverageThornsTankOnly", true },
    { "buffCoverageWild", true },
    { "buffCoverageY", 2 },
    { "ciAggroColorG", 0.55000000000000004 },
    { "ciAggroColorR", 1 },
    { "ciAlpha", 1 },
    { "ciEnabled", true },
    { "ciLayer", 7 },
    { "ciSize", 8 },
    { "ciSlotBL", "none" },
    { "ciSlotBR", "none" },
    { "ciSlotC", "none" },
    { "ciSlotTL", "dispel" },
    { "ciSlotTR", "aggro" },
    { "ciStrata", "AUTO" },
    { "classOrder", "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER" },
    { "clickCastEnabled", true },
    { "deadBgA", 0.90000000000000002 },
    { "deadBgB", 0.050000000000000003 },
    { "deadBgG", 0.050000000000000003 },
    { "deadBgOffline", true },
    { "deadBgR", 0.59999999999999998 },
    { "debuffStripeAlpha", 0.59999999999999998 },
    { "debuffStripeColorB", 0.20000000000000001 },
    { "debuffStripeColorG", 0.20000000000000001 },
    { "debuffStripeColorR", 0.80000000000000004 },
    { "debuffStripeEdge", "BOTTOM" },
    { "debuffStripeHeight", 3 },
    { "detachedPowerBarFrameLevelOffset", 6 },
    { "detachedPowerBarHeight", 6 },
    { "detachedPowerBarOffsetY", -4 },
    { "dispelEnabled", true },
    { "dispelOverlayAlpha", 0.34999999999999998 },
    { "dispelOverlayOnHealth", true },
    { "dispelOverlayStrata", "AUTO" },
    { "dispelOverlayStyle", "FULL" },
    { "dispelOverlayTrigger", "BORDER" },
    { "dispelSymbolAlpha", 1 },
    { "dispelSymbolAnchor", "TOPRIGHT" },
    { "dispelSymbolGrowth", "RIGHT" },
    { "dispelSymbolLayer", 8 },
    { "dispelSymbolMode", "ALL" },
    { "dispelSymbolSize", 12 },
    { "dispelSymbolSpacing", 2 },
    { "dispelSymbolStrata", "AUTO" },
    { "dispelSymbolStyle", "BLIZZARD" },
    { "friendlyBossColumns", 1 },
    { "friendlyBossHealerOnly", true },
    { "friendlyBossHeight", 24 },
    { "friendlyBossTextSize", 11 },
    { "friendlyBossWidth", 100 },
    { "friendlyBossX", 250 },
    { "friendlyBossY", 150 },
    { "groupBorderA", 0.94999999999999996 },
    { "groupBorderB", 1 },
    { "groupBorderG", 0.68000000000000005 },
    { "groupBorderPadding", 2 },
    { "groupBorderR", 0.38 },
    { "groupBorderSize", 1 },
    { "groupNumberAnchor", "BOTTOMRIGHT" },
    { "groupNumberLayer", 7 },
    { "groupNumberSize", 10 },
    { "groupNumberStyle", "PAREN" },
    { "groupNumberX", -2 },
    { "groupNumberY", 2 },
    { "growth", "DOWN" },
    { "healAbsorbBarTexture", "Solid" },
    { "healerManaHeight", 24 },
    { "healerManaShowValue", true },
    { "healerManaTextB", 1 },
    { "healerManaTextG", 1 },
    { "healerManaTextR", 1 },
    { "healerManaTextSize", 11 },
    { "healerManaWidth", 100 },
    { "healerManaX", 250 },
    { "healerManaY", -150 },
    { "healthColorMode", "CLASS" },
    { "healthCustomB", 0.20000000000000001 },
    { "healthCustomG", 0.80000000000000004 },
    { "healthCustomR", 0.20000000000000001 },
    { "healthFadeAlpha", 0.45000000000000001 },
    { "healthFadeThreshold", 95 },
    { "height", 32 },
    { "hideInClientScene", true },
    { "hlFocusColorB", 1 },
    { "hlFocusColorG", 0.5 },
    { "hlFocusColorR", 0.5 },
    { "hlFocusEnabled", true },
    { "hlFocusSize", 2 },
    { "hpFontSize", 9 },
    { "hpFullValueShort", true },
    { "iconStyle", "MSUF_ROLES" },
    { "leaderIcon", true },
    { "leaderIconAnchor", "TOPRIGHT" },
    { "leaderIconLayer", 2 },
    { "leaderIconSize", 12 },
    { "leaderIconStyle", "DEFAULT" },
    { "levelTextAnchor", "BOTTOMLEFT" },
    { "levelTextDifficultyColor", true },
    { "levelTextLayer", 7 },
    { "levelTextSize", 10 },
    { "levelTextX", 2 },
    { "levelTextY", 2 },
    { "maxColumns", 8 },
    { "nameAnchor", "LEFT" },
    { "nameBarAlpha", 0.94999999999999996 },
    { "nameBarB", 0.050000000000000003 },
    { "nameBarG", 0.050000000000000003 },
    { "nameBarHeight", 14 },
    { "nameBarR", 0.050000000000000003 },
    { "nameColorB", 1 },
    { "nameColorG", 1 },
    { "nameColorMode", "DEFAULT" },
    { "nameColorR", 1 },
    { "nameFontSize", 10 },
    { "nameOffsetX", 28 },
    { "offlineAlpha", 0.5 },
    { "offsetX", -419.5 },
    { "offsetY", -82 },
    { "petsColumns", 1 },
    { "petsHeight", 24 },
    { "petsMaxCount", 40 },
    { "petsTextSize", 11 },
    { "petsWidth", 100 },
    { "petsX", -250 },
    { "petsY", -150 },
    { "phaseAnchor", "TOPLEFT" },
    { "phaseIcon", true },
    { "phaseIconSize", 14 },
    { "phaseIconStyle", "DEFAULT" },
    { "phaseLayer", 3 },
    { "point", "CENTER" },
    { "positionMigrationCount", 10, retain = true },
    { "positionMode", "GRID_CENTER_V1", retain = true },
    { "powerBarEnabled", true },
    { "powerFontSize", 9 },
    { "powerHeight", 4 },
    { "powerShowHealer", true },
    { "powerShowTank", true },
    { "powerTextCenter", "PERCENT" },
    { "powerTextDelimiter", " / " },
    { "powerTextRight", "NONE" },
    { "pvpIcon", true },
    { "pvpIconAnchor", "TOPLEFT" },
    { "pvpIconLayer", 3 },
    { "pvpIconSize", 12 },
    { "pvpIconStyle", "DEFAULT" },
    { "pvpIconX", 14 },
    { "raidManagerMode", "AUTO" },
    { "raidMarker", true, retain = true },
    { "raidMarkerAnchor", "CENTER", retain = true },
    { "raidMarkerLayer", 3, retain = true },
    { "raidMarkerSize", 12, retain = true },
    { "raidMarkerStyle", "DEFAULT", retain = true },
    { "readyCheckAnchor", "CENTER" },
    { "readyCheckIcon", true },
    { "readyCheckIconStyle", "DEFAULT" },
    { "readyCheckLayer", 4 },
    { "readyCheckSize", 16 },
    { "resurrectAnchor", "CENTER" },
    { "resurrectIcon", true },
    { "resurrectIconSize", 16 },
    { "resurrectIconStyle", "DEFAULT" },
    { "resurrectLayer", 4 },
    { "roleIcon", true },
    { "roleIconAnchor", "LEFT" },
    { "roleIconLayer", 1 },
    { "roleIconShowDPS", true },
    { "roleIconShowHealer", true },
    { "roleIconShowTank", true },
    { "roleIconSize", 14 },
    { "roleIconStyle", "DEFAULT" },
    { "roleIconX", 4 },
    { "roleOrder", "TANK,HEALER,DAMAGER" },
    { "showGroupNumber", true },
    { "showHPText", true },
    { "showPlayer", true },
    { "sortMode", "INDEX" },
    { "statusAFKText", true },
    { "statusAFKTextAnchor", "CENTER" },
    { "statusAFKTextLayer", 7 },
    { "statusAFKTextSize", 14 },
    { "statusAFKTimerOffsetY", -10 },
    { "statusAFKTimerTextAnchor", "CENTER" },
    { "statusAFKTimerTextLayer", 7 },
    { "statusAFKTimerTextSize", 10 },
    { "statusDNDText", true },
    { "statusDNDTextAnchor", "CENTER" },
    { "statusDNDTextLayer", 7 },
    { "statusDNDTextSize", 14 },
    { "statusGhostText", true },
    { "statusGhostTextAnchor", "CENTER" },
    { "statusGhostTextLayer", 7 },
    { "statusGhostTextSize", 14 },
    { "statusText", true },
    { "statusTextAnchor", "CENTER" },
    { "statusTextLayer", 7 },
    { "statusTextSize", 14 },
    { "summonAnchor", "CENTER" },
    { "summonIcon", true },
    { "summonIconSize", 16 },
    { "summonIconStyle", "DEFAULT" },
    { "summonLayer", 4 },
    { "targetB", 1 },
    { "targetG", 1 },
    { "targetIndicator", true },
    { "targetR", 1 },
    { "targetsColumns", 1 },
    { "targetsHeight", 24 },
    { "targetsTextSize", 11 },
    { "targetsWidth", 100 },
    { "targetsX", -250 },
    { "targetsY", 150 },
    { "textDelimiter", " / " },
    { "textLayer", 5 },
    { "textRight", "NONE" },
    { "tier10Growth", "INHERIT" },
    { "tier20Growth", "INHERIT" },
    { "tier25Growth", "INHERIT" },
    { "tier40Growth", "INHERIT" },
    { "unitsPerColumn", 5 },
    { "useGlobalFontColor", true },
    { "width", 80 },
    { "size", 14 },
    { "size", 20 },
    { "stackSize", 12 },
    { "x", 22 },
    { "stackSize", 11 },
    { "blizzardIconSize", 20 },
    { "maxColumns", 1 },
    { "nameFontSize", 12 },
    { "powerHeight", 6 },
    { "pvpIconSize", 14 },
    { "roleIconSize", 16 },
    { "anchorMode", "RAID_RIGHT" },
    { "attachGap", 8 },
    { "autoTanks", true },
    { "maxFrames", 5 },
    { "offsetX", -120 },
    { "relativePoint", "CENTER" },
    { "width", 220 },
    { "hpBarAlpha", 1 },
    { "offsetX", -275 },
    { "offsetY", -290 },
    { "channelTickCount", 5 },
    { "detachedPowerBarShape", "BAR" },
    { "detachedPowerOrbSize", 54 },
    { "height", 40 },
    { "offsetY", -180 },
    { "portraitMode", "LEFT" },
    { "width", 275 },
    { "totInlineColorMode", "AUTO" },
    { "totInlineSeparator", "|" },
}
local sparseV2Owners = {
    { path = {[1]="arena"}, fields = {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
        31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
        61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
        91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120,
        121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150,
        151, 152, 153, 154, 155,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layout"}, fields = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layout"}, fields = {
        157, 158, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
        204, 205, 206, 207, 208, 209, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layout"}, fields = {
        157, 158, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 203, 204, 205,
        206, 207, 208, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters",[5]="buffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters",[5]="debuffs"}, fields = {
        8, 156,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layout"}, fields = {
        157, 158, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layoutShared"}, fields = {
        174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 203, 204, 205, 206,
        207, 208, 210, 211,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target"}, fields = {
        212, 213, 214, 215,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconShapes"}, fields = {
        216, 217, 218, 219,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="buff"}, fields = {
        220, 221, 222,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="debuff"}, fields = {
        220, 221, 222,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="playerDefensives"}, fields = {
        220, 221, 222,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="targetDots"}, fields = {
        220, 221, 222,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters",[4]="buffs"}, fields = {
        156,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters",[4]="debuffs"}, fields = {
        156,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters"}, fields = {
        8,
    } },
    { path = {[1]="auras3",[2]="shared"}, fields = {
        223, 224, 179, 180, 181, 182, 183, 184, 160, 161, 189, 225, 191, 226, 227, 228, 197, 198, 199, 200, 201, 202, 168, 169, 207, 229, 209, 230, 231, 232,
        233, 234, 235, 236, 237, 238, 239, 210, 240, 241, 211, 242, 243, 244, 245, 246, 247, 248, 249,
    } },
    { path = {[1]="auras3"}, fields = {
        8, 250, 251, 252, 253,
    } },
    { path = {[1]="bars"}, fields = {
        254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 7, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282,
        283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311,
    } },
    { path = {[1]="boss"}, fields = {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 65, 66, 67, 68,
        69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 81, 312, 82, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99,
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129,
        130, 131, 132, 133, 134, 135, 136, 137, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155,
    } },
    { path = {[1]="focus"}, fields = {
        313, 2, 3, 5, 6, 7, 8, 9, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
        35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66,
        67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 81, 314, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98,
        99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128,
        129, 130, 131, 132, 133, 134, 135, 136, 137, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155,
    } },
    { path = {[1]="focustarget"}, fields = {
        2, 3, 4, 5, 6, 7, 9, 10, 13, 14, 15, 16, 17, 18, 19, 315, 316, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 317, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
        63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 79, 314, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96,
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126,
        127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 155,
    } },
    { path = {[1]="gameplay"}, fields = {
        318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333,
    } },
    { path = {[1]="general",[2]="UIScale"}, fields = {
        334,
    } },
    { path = {[1]="general",[2]="minimapIconDB"}, fields = {
        335, 336,
    } },
    { path = {[1]="general",[2]="statusIndicators"}, fields = {
        337, 338,
    } },
    { path = {[1]="general"}, fields = {
        339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368,
        369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398,
        399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428,
        429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458,
        459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488,
        489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518,
        519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548,
        549, 550, 551, 552, 553, 554, 555, 14, 15, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576,
        577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 42, 44, 45, 47,
        48, 49, 587, 588, 589, 590, 59, 61, 591, 62, 63, 64, 65, 66, 67, 74, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605,
        606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 314, 82, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633,
        634, 142, 143, 144, 145, 635, 146, 147, 148, 149, 150, 151, 152, 153, 154, 636, 637, 638, 639, 640, 641, 642,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="blizzardTypes"}, fields = {
        643, 644, 645, 646,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="buff"}, fields = {
        647, 648, 226, 649, 230, 231, 232, 233, 8, 650, 651, 652, 236, 653, 654, 655, 656, 240, 657, 244, 658, 659, 660, 661, 662, 663, 664, 665,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="debuff"}, fields = {
        666, 648, 226, 649, 667, 230, 231, 232, 233, 8, 668, 669, 652, 236, 670, 654, 655, 656, 240, 657, 244, 671, 659, 660, 661, 662, 672, 673,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="externals"}, fields = {
        666, 674, 648, 226, 649, 230, 231, 232, 233, 8, 675, 669, 652, 236, 676, 654, 655, 656, 240, 244, 677, 659, 678, 660, 661, 662, 679, 673,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras"}, fields = {
        680, 681, 682, 683, 684, 8, 236, 685, 686, 244,
    } },
    { path = {[1]="gf_mythicraid",[2]="privateAuras"}, fields = {
        687, 688, 689, 654, 690, 691, 678, 692,
    } },
    { path = {[1]="gf_mythicraid",[2]="spellIndicators",[3]="style"}, fields = {
        693, 648, 226, 649, 230, 231, 232, 233, 240, 241, 657, 244, 660, 661,
    } },
    { path = {[1]="gf_mythicraid",[2]="spellIndicators"}, fields = {
        652, 236, 694, 695, 662,
    } },
    { path = {[1]="gf_mythicraid"}, fields = {
        339, 341, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723,
        724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753,
        754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 7, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782,
        783, 784, 539, 540, 785, 541, 542, 543, 544, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 801, 802, 803, 804, 805, 806,
        807, 10, 808, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 833, 834, 19,
        835, 836, 837, 20, 580, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850, 851, 852, 50, 51, 52, 853, 854, 855, 856, 857, 858, 859,
        57, 58, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 872, 73, 74, 75, 873, 874, 875, 876, 877, 878, 879, 880, 881, 882, 883, 884,
        885, 886, 887, 888, 889, 890, 891, 892, 893, 894, 79, 895, 896, 678, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912,
        913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 624, 625, 626, 627, 628, 629, 135, 932, 933, 136, 934,
        935, 936, 937, 938, 939, 940, 941,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="blizzardTypes"}, fields = {
        643, 644, 645, 646,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="buff"}, fields = {
        648, 226, 649, 230, 231, 232, 233, 8, 650, 652, 236, 653, 654, 655, 656, 240, 657, 244, 942, 659, 660, 661, 662, 663,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="debuff"}, fields = {
        666, 648, 226, 649, 230, 231, 232, 233, 8, 668, 669, 652, 236, 670, 656, 240, 657, 244, 943, 659, 660, 944, 662, 945,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="externals"}, fields = {
        666, 674, 648, 226, 649, 230, 231, 232, 233, 8, 675, 669, 652, 236, 676, 654, 655, 656, 240, 244, 671, 659, 678, 660, 946, 662, 679,
    } },
    { path = {[1]="gf_party",[2]="auras"}, fields = {
        680, 681, 947, 683, 684, 8, 236, 685, 686, 244,
    } },
    { path = {[1]="gf_party",[2]="privateAuras"}, fields = {
        687, 688, 689, 654, 690, 658, 678, 692,
    } },
    { path = {[1]="gf_party",[2]="spellIndicators",[3]="style"}, fields = {
        693, 648, 226, 649, 230, 231, 232, 233, 240, 241, 657, 244, 660, 661,
    } },
    { path = {[1]="gf_party",[2]="spellIndicators"}, fields = {
        652, 236, 694, 695, 662,
    } },
    { path = {[1]="gf_party"}, fields = {
        339, 341, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723,
        724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753,
        754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 7, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782,
        783, 784, 539, 540, 785, 541, 542, 543, 544, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 802, 803, 804, 805, 806, 807,
        10, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 948, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 949, 19, 835, 20, 580,
        838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 42,
        43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 853, 854, 950, 856, 857, 858, 859, 57, 58, 860, 861, 862, 863, 951, 865, 866, 867, 868, 869, 870,
        72, 872, 73, 74, 75, 873, 874, 875, 876, 877, 878, 879, 880, 881, 882, 884, 885, 952, 890, 891, 892, 894, 79, 895, 896, 678, 897, 898, 899, 900,
        901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930,
        931, 624, 625, 626, 627, 628, 629, 932, 933, 136, 935, 936, 937, 938, 939, 940,
    } },
    { path = {[1]="gf_priority"}, fields = {
        953, 954, 955, 784, 956, 957, 850, 958, 245, 939,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="blizzardTypes"}, fields = {
        643, 644, 645, 646,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="buff"}, fields = {
        648, 226, 649, 230, 231, 232, 233, 8, 650, 652, 236, 653, 654, 655, 656, 240, 657, 244, 658, 659, 660, 661, 662, 663,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="debuff"}, fields = {
        666, 648, 226, 649, 230, 231, 232, 233, 8, 668, 669, 652, 236, 670, 656, 240, 657, 244, 671, 659, 660, 661, 662, 672,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="externals"}, fields = {
        666, 674, 648, 226, 649, 230, 231, 232, 233, 8, 675, 669, 652, 236, 676, 654, 655, 656, 240, 244, 677, 659, 678, 660, 661, 662, 679,
    } },
    { path = {[1]="gf_raid",[2]="auras"}, fields = {
        680, 681, 682, 683, 684, 8, 236, 685, 686, 244,
    } },
    { path = {[1]="gf_raid",[2]="privateAuras"}, fields = {
        687, 688, 689, 654, 690, 691, 678, 692,
    } },
    { path = {[1]="gf_raid",[2]="spellIndicators",[3]="style"}, fields = {
        693, 648, 226, 649, 230, 231, 232, 233, 240, 241, 657, 244, 660, 661,
    } },
    { path = {[1]="gf_raid",[2]="spellIndicators"}, fields = {
        652, 236, 694, 695, 662,
    } },
    { path = {[1]="gf_raid"}, fields = {
        339, 341, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723,
        724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753,
        754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 7, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782,
        783, 784, 539, 540, 785, 541, 542, 543, 544, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799, 800, 802, 803, 804, 805, 806, 807,
        10, 809, 810, 811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, 19, 835, 20, 580, 838,
        839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 50, 51, 52, 853, 854, 856, 857, 858, 859, 57, 58, 860, 861, 862, 863, 865, 866, 867, 868,
        869, 870, 872, 73, 74, 75, 873, 874, 875, 876, 877, 878, 879, 880, 881, 882, 884, 885, 890, 891, 892, 894, 79, 895, 896, 897, 898, 899, 900, 901,
        902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931,
        624, 625, 626, 627, 628, 629, 932, 933, 136, 935, 936, 937, 938, 939, 940,
    } },
    { path = {[1]="pet"}, fields = {
        313, 7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37,
        38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 65, 66, 67, 68, 69, 72, 73,
        74, 75, 77, 79, 80, 81, 312, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106,
        107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136,
        137, 959,
    } },
    { path = {[1]="pettarget"}, fields = {
        7, 9, 960, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 961, 962, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
        35, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 65, 66, 67, 68,
        69, 70, 71, 72, 73, 74, 75, 77, 79, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104,
        105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
        135, 136, 137, 155,
    } },
    { path = {[1]="player",[2]="castbar"}, fields = {
        963,
    } },
    { path = {[1]="player"}, fields = {
        964, 965, 7, 8, 966, 13, 14, 15, 18, 19, 967, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
        39, 40, 41, 42, 968, 44, 45, 46, 48, 49, 52, 587, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 72, 77, 78, 80,
        81, 312, 314, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
        111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 143, 144, 146,
        147, 148, 149, 150, 152, 153, 154, 969,
    } },
    { path = {[1]="target"}, fields = {
        2, 3, 4, 5, 6, 7, 8, 966, 13, 14, 15, 18, 19, 967, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
        36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 48, 49, 52, 587, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 69, 72, 73, 74,
        75, 76, 77, 78, 79, 80, 81, 312, 314, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104,
        105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
        135, 136, 137, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 969,
    } },
    { path = {[1]="targettarget"}, fields = {
        2, 3, 5, 6, 7, 8, 9, 10, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
        36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 317, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
        66, 67, 68, 69, 72, 73, 74, 75, 76, 77, 314, 82, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102,
        103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132,
        133, 134, 135, 136, 137, 970, 971,
    } },
}
-- END FROZEN SPARSE V2 DATA


-- V2 records only fields actually removed; unlike V1 it never reconstructs an
-- absent optional field merely because its owner exists. The field pool and
-- owner order above are immutable. Future dictionary changes need a new version.
local sparseV2Marker = "_msufSparseDefaultsV2"
local sparseV2Before, sparseV2Tables, sparseV2Nibbles, sparseV2Pieces = {}, {}, {}, {}
local sparseV2Absent = {}
local sparseV2Symbols, sparseV2Bits = {}, { 1, 2, 4, 8 }
for i = 0, 15 do sparseV2Symbols[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
local sparseV2Size = 0
for i = 1, #sparseV2Owners do
    local owner = sparseV2Owners[i]
    owner.offset = sparseV2Size
    sparseV2Tables[i] = false
    for j = 1, #owner.fields do sparseV2Before[sparseV2Size + j] = false end
    sparseV2Size = sparseV2Size + #owner.fields
end
for i = 1, #sparseV2Fields do
    local field = sparseV2Fields[i]
    field.bytes = #field[1] + #tostring(field[2]) + 4
end
local sparseV2MaskSize = math.ceil(sparseV2Size / 4)
for i = 1, sparseV2MaskSize do sparseV2Nibbles[i], sparseV2Pieces[i] = 0, "" end

local function ResolveSparseV2Owners(profile, refs, lists)
    for i = 1, #sparseV2Owners do
        local node = profile
        local path = sparseV2Owners[i].path
        for j = 1, #path do
            if type(node) ~= "table" or lists[node] then
                node = nil
                break
            end
            if refs[node] ~= 1 then return false end
            node = node[path[j]]
        end
        if type(node) == "table" then
            if refs[node] ~= 1 then return false end
            if lists[node] then node = nil end
        else
            node = nil
        end
        sparseV2Tables[i] = node or false
    end
    return true
end

local function ReleaseSparseV2(rollback)
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local slot = spec.offset + j
            local before = sparseV2Before[slot]
            if rollback and owner then
                local key = sparseV2Fields[spec.fields[j]][1]
                if before == sparseV2Absent then owner[key] = nil else owner[key] = before end
            end
            sparseV2Before[slot] = false
        end
        sparseV2Tables[i] = false
    end
end

local function SparseV2Bit(slot)
    local index = math.floor((slot - 1) / 4) + 1
    local bit = sparseV2Bits[(slot - 1) % 4 + 1]
    return math.floor(sparseV2Nibbles[index] / bit) % 2 == 1
end

local function ReadSparseV2Mask(mask)
    if type(mask) ~= "string" or #mask ~= sparseV2MaskSize then return false end
    local nonzero = false
    for i = 1, sparseV2MaskSize do
        local byte = mask:byte(i)
        local value
        if byte >= 48 and byte <= 57 then value = byte - 48
        elseif byte >= 97 and byte <= 102 then value = byte - 87
        else return false end
        sparseV2Nibbles[i] = value
        if value ~= 0 then nonzero = true end
    end
    local tail = sparseV2Size % 4
    return nonzero and (tail == 0 or sparseV2Nibbles[sparseV2MaskSize] < 2 ^ tail)
end

local function ValidateSparseV2MaskOwners()
    for i = 1, #sparseV2Owners do
        local spec = sparseV2Owners[i]
        if not sparseV2Tables[i] then
            for j = 1, #spec.fields do
                if SparseV2Bit(spec.offset + j) then return false end
            end
        end
    end
    return true
end

local function ApplySparseV2(restore)
    local count = 0
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        if owner then
            for j = 1, #spec.fields do
                if SparseV2Bit(spec.offset + j) then
                    local field = sparseV2Fields[spec.fields[j]]
                    local key, default = field[1], field[2]
                    if restore then
                        if owner[key] == nil then
                            owner[key] = default
                            count = count + 1
                        end
                    elseif owner[key] == default then
                        owner[key] = nil
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function RestoreSparseV2(profile, prepared)
    if profile._msufDefaultsRevision ~= sparseToken or not ReadSparseV2Mask(profile[sparseV2Marker]) then return false end
    if not prepared then
        local ok = CountTables(profile, scratchRefs, scratchPath, 0, scratchLists)
            and ResolveSparseV2Owners(profile, scratchRefs, scratchLists)
        ClearScratch()
        if not ok then return false end
    end
    -- Validate the entire mask and all referenced owners before the first write.
    if not ValidateSparseV2MaskOwners() then return false end
    ApplySparseV2(true)
    profile[sparseV2Marker] = nil
    profile._msufDefaultsRevision = 17
    return true
end

function Schema.RestorePersistence(profile)
    if not Plain(profile) or MSUF.Util.IsSecret(profile._msufDefaultsRevision) then return false end
    local marker = profile[sparseV2Marker]
    if MSUF.Util.IsSecret(marker) then return false end
    -- An older loader that materialised the profile (6.50x stamps 17) may leave
    -- an obsolete V2 mask; its revision owns the data, so never use that mask to
    -- invent leaves. A newer revision owns a string mask: refuse and leave it
    -- intact. A non-string marker is nobody's mask and is dropped.
    local revision = profile._msufDefaultsRevision
    local stale = marker ~= nil and (revision == nil or (type(revision) == "number" and revision < sparseToken)
        or (revision ~= sparseToken and type(marker) ~= "string"))
    if stale then
        profile[sparseV2Marker] = nil
    elseif marker ~= nil then
        local restored = RestoreSparseV2(profile, false)
        ReleaseSparseV2(false)
        return restored
    end
    return RestoreLegacyPersistence(profile) or stale
end

local function CaptureSparseV2()
    local count, bytes = 0, 0
    for i = 1, sparseV2MaskSize do sparseV2Nibbles[i] = 0 end
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local slot, field = spec.offset + j, sparseV2Fields[spec.fields[j]]
            local value
            if owner then value = owner[field[1]] end
            if value == nil then sparseV2Before[slot] = sparseV2Absent else sparseV2Before[slot] = value end
            if not field.retain and value == field[2] then
                local index = math.floor((slot - 1) / 4) + 1
                sparseV2Nibbles[index] = sparseV2Nibbles[index] + sparseV2Bits[(slot - 1) % 4 + 1]
                count, bytes = count + 1, bytes + field.bytes
            end
        end
    end
    return count, bytes
end

local function SameSparseV2()
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local before, value = sparseV2Before[spec.offset + j]
            if before == sparseV2Absent then before = nil end
            if owner then value = owner[sparseV2Fields[spec.fields[j]][1]] end
            if type(value) ~= type(before) or value ~= before then return false end
        end
    end
    return true
end

local function PersistProfile(profile, refs, lists)
    if not Plain(profile) or profile._msufDefaultsRevision ~= 17 or profile[sparseV2Marker] ~= nil
        or refs[profile] ~= 1 then return 0 end
    if not ResolveSparseV2Owners(profile, refs, lists) then
        ReleaseSparseV2(false)
        return 0
    end
    local removed, bytes = CaptureSparseV2()
    -- A short/incomplete profile remains full when the fixed mask would cost more.
    if bytes <= sparseV2MaskSize + #sparseV2Marker + 32 then
        ReleaseSparseV2(false)
        return 0
    end
    for i = 1, sparseV2MaskSize do sparseV2Pieces[i] = sparseV2Symbols[sparseV2Nibbles[i]] end
    local mask = table.concat(sparseV2Pieces)
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    local elided = ApplySparseV2(false)
    -- The real decoder's nil-only fill runs against the existing owner tables.
    -- Compare every known original field by type AND value, including nil/false/0.
    -- Only these fields and the two stamps can change; all other keys and table
    -- identities are untouched. Rollback returns the complete original profile.
    local restored = RestoreSparseV2(profile, true)
    if elided ~= removed or not restored or not SameSparseV2() then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        return 0
    end
    local committed = ApplySparseV2(false)
    if committed ~= removed then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        return 0
    end
    ReleaseSparseV2(false)
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    return committed
end

function Schema.PreparePersistence(globalDB)
    if not Plain(globalDB) or not Plain(globalDB.profiles) then return nil end
    return globalDB.profiles
end

function Schema.Persist(globalDB)
    local profiles = Schema.PreparePersistence(globalDB)
    if not profiles then return false end
    local count = 0
    if CountTables(globalDB, scratchRefs, scratchPath, 0, scratchLists) and scratchRefs[profiles] == 1 then
        for _, profile in pairs(profiles) do count = count + PersistProfile(profile, scratchRefs, scratchLists) end
    end
    ClearScratch()
    return true, count
end
