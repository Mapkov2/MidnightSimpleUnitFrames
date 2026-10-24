local _, MSUF = ...

-- Generated persistence entries of tools/fixtures/defaults/schema.lua. The
-- complete schema verifies every provider. The storage codec below restores
-- its versioned defaults before ordinary migrations or runtime readers.
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
-- Declarative defaults. Storage dictionaries below are frozen decoder data,
-- independent of these current authored values. All seeds use Fill.
local values = {
    UnitText = {
        healthTextDecimals = false, hpAbsorbIcon = false, hpOffsetX = -2, hpOffsetY = -18, hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0, hpTextLayer = 5, hpTextLeftOffsetX = 0, hpTextLeftOffsetY = 0, hpTextMode = "CURPERCENT",
        hpTextMouseover = false, hpTextMouseoverFadeIn = 0, hpTextMouseoverFadeOut = 0, hpTextRightOffsetX = 0, hpTextRightOffsetY = 0,
        nameOffsetX = 7, nameOffsetY = -4, nameTextAnchor = "TOPLEFT", nameTextLayer = 5, nameTextMouseover = false,
        nameTextMouseoverFadeIn = 0, nameTextMouseoverFadeOut = 0, powerFontSize = 10, powerOffsetX = -6, powerOffsetY = 2,
        powerTextCenter = "NONE", powerTextCenterOffsetX = 0, powerTextCenterOffsetY = 0, powerTextLayer = 2, powerTextLeft = "NONE",
        powerTextLeftOffsetX = 0, powerTextLeftOffsetY = 0, powerTextMouseover = false, powerTextMouseoverFadeIn = 0,
        powerTextMouseoverFadeOut = 0, powerTextRight = "CURRENT", powerTextRightOffsetX = 0, powerTextRightOffsetY = 0,
        raidGroupNameAnchor = "NAMERIGHT", raidGroupNameOffsetX = 3, raidGroupNameOffsetY = 0, raidGroupNameStyle = "PAREN",
        showRaidGroupInName = false, textCenter = "NONE", textLeft = "NONE", textRight = "CURPERCENT",
    },
    UnitFrames = {
        player = {
        height = 40, offsetX = -256, offsetY = -180, portraitClassStyle = "BLIZZARD", portraitMode = "LEFT", powerFontSize = 12,
        showHP = true, showInterrupt = true, showInterruptSource = false, showLevelIndicator = false, showName = false, showPower = true,
        showPowerText = true, width = 275,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        --- (false = normal left->right fill)
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        target = {
        height = 40, offsetX = 320, offsetY = -180, portraitClassStyle = "BLIZZARD", portraitMode = "RIGHT", powerFontSize = 12,
        showHP = true, showInterrupt = true, showInterruptSource = false, showLevelIndicator = false, showName = true, showPower = true,
        showPowerText = true, width = 275,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        focus = {
        height = 30, offsetX = -260, offsetY = -300, portraitClassStyle = "BLIZZARD", portraitMode = "OFF", showHP = true,
        showInterrupt = true, showInterruptSource = false, showLevelIndicator = false, showName = true, showPower = false,
        showPowerText = false, width = 180,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
        --- Focus-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
    },
        targettarget = {
        height = 30, offsetX = 220, offsetY = -300, showHP = true, showLevelIndicator = false, showName = false, showPower = false,
        showPowerText = false, width = 180,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        focustarget = {
        enabled = false, height = 30, offsetX = 260, offsetY = 180, showHP = true, showLevelIndicator = false, showName = true,
        showPower = false, showPowerText = false, width = 180,
        --- Focus Target is a lightweight child-style frame: no castbar or auras.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        pettarget = {
        enabled = false, height = 30, offsetX = -275, offsetY = -290, powerBarBgTexture = "", powerBarTexture = "",
        reverseFillBars = false, showHP = true, showLevelIndicator = false, showName = true, showPower = false, showPowerText = false,
        verticalFillBars = false, width = 180,
    },
        pet = {
        height = 30, offsetX = -275, offsetY = -250, width = 220,
        --- Pet-only: optional relative anchor for positioning.
        --- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        --- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL", showHP = true, showLevelIndicator = false, showName = true, showPower = true, showPowerText = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        boss = {
        height = 30, offsetX = 360, offsetY = 230, spacing = -96, width = 180,
        --- Layout mode: "VERTICAL_DOWN" | "VERTICAL_UP" | "HORIZONTAL_RIGHT" | "HORIZONTAL_LEFT"
        --- Kept invertBossOrder for one-shot migration (see below).
        bossLayoutMode = "VERTICAL_DOWN", invertBossOrder = false, portraitMode = "OFF", showHP = true, showInterrupt = true,
        showInterruptSource = false, showLevelIndicator = false, showName = true, showPower = false, showPowerText = true,
        --- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        --- Per-unitframe: vertical fill axis for HP + Power bars.
        --- (false = horizontal fill; true = vertical, combines with reverseFillBars)
        verticalFillBars = false,
        --- Per-unitframe power bar art. Empty = follow bars.powerBarTexture,
        --- which itself falls back to this frame's bar texture.
        powerBarBgTexture = "", powerBarTexture = "",
    },
        arena = {
        height = 30, offsetX = 360, offsetY = -40, spacing = -96, width = 180,
        --- Arena reuses the boss stacked-container model and its exact key
        --- names (spacing/bossLayoutMode), so the engine delta math, Edit Mode
        --- drag path, and copy-coverage allowlists apply unchanged.
        bossLayoutMode = "VERTICAL_DOWN", portraitMode = "OFF", powerBarBgTexture = "", powerBarTexture = "", reverseFillBars = false,
        showHP = true, showInterrupt = true, showInterruptSource = false, showLevelIndicator = false, showName = true, showPower = true,
        showPowerText = false, verticalFillBars = false,
     trinketSize = 20, trinketAnchor = "RIGHT", trinketOffsetX = 4, trinketOffsetY = 0, trinketLayer = 10 },
    },
    AuraFilters = {
            enabled = true, hidePermanent = false,
            buffs = {
                bigDefensive = false, cancelable = false, dispellableAny = false, exclusive = "none", externalDefensive = false,
                includeDispellable = false, includeNameplateOnly = false, notCancelable = false, onlyImportant = false, onlyMine = false,
                raid = false, raidInCombat = false,
            },
            debuffs = {
                crowdControl = false, dispellableAny = false, exclusive = "none", includeDispellable = false, includeNameplateOnly = false,
                onlyImportant = false, onlyMine = false, raid = false, raidInCombat = false,
            },
        },
    UnitAuras = {
        enabled = true, profileModelRevision = 1, showArena = true, showBoss = true, showFocus = false, showPet = true, showPlayer = false,
        showTarget = true,
        customDisplays = {
            serial = 0,
            shared = { items = {} },
            perUnit = {},
        },
        customContainers = {
            perUnit = {
                player = {
                    items = {
                    },
                },
            },
        },
        shared = {
            arenaEditTogether = true, bossEditTogether = true, buffGroupIconSize = 26, buffGroupOffsetX = 0, buffGroupOffsetY = 36,
            buffIconZoom = 100, cooldownTextSize = 14, debuffGroupIconSize = 26, debuffGroupOffsetX = 0, debuffGroupOffsetY = 6,
            debuffIconZoom = 100, hideBlizzardBuffFrame = false, hideBlizzardDebuffFrame = false, iconSize = 26, iconZoom = 100,
            appearanceIconShapes = { playerDefensives = "FOLLOW_PORTRAIT" },
            buffFrameEffectType = "none", buffGrowthX = "RIGHT", buffGrowthY = "DOWN", buffShowStealable = false,
            buffSortMethod = "DEFAULT", buffSortReverse = false, buffSpacing = 2, buffStealableStyle = "BORDER_ICON",
            cooldownSwipeReverse = false, debuffGrowthX = "RIGHT", debuffGrowthY = "DOWN", debuffSortMethod = "DEFAULT",
            debuffSortReverse = false, debuffSpacing = 2, debuffTypeBorderMode = "OFF", durationBarDirection = "REMAINING",
            durationBarDisplay = "BAR_ONLY", durationBarHeight = 2, durationBarPosition = "BOTTOM", growth = "RIGHT", maxBuffs = 12,
            maxDebuffs = 12, perRow = 12, showBuffs = true, showCooldownSwipe = true, showCooldownText = true, showDebuffs = true,
            showDurationBar = false, showStackCount = true, showTooltip = true, spacing = 2, stackTextSize = 14,
            useDebuffTypeBorders = false,
            buffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
            buffFrameEffectLayer = 0, buffFrameEffectPriority = 5, buffFrameEffectStrata = "AUTO", buffFrameEffectThickness = 2,
            debuffFrameEffectType = "none",
            debuffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
            buffAnchor = "BOTTOMRIGHT", buffLayer = 5, cooldownDecimalSeconds = 3, cooldownTextAnchor = "CENTER", cooldownTextOffsetX = 0,
            cooldownTextOffsetY = 0, debuffAnchor = "TOPLEFT", debuffFrameEffectLayer = 0, debuffFrameEffectPriority = 5,
            debuffFrameEffectStrata = "AUTO", debuffFrameEffectThickness = 2, debuffLayer = 6, showInEditMode = true,
            stackCountAnchor = "TOPRIGHT", stackTextOffsetX = -1, stackTextOffsetY = 1,
        },
        perUnit = {
            target = {
                overrideFilters = false, overrideLayout = true,
                layout = {
                    buffGroupIconSize = 34, buffGroupOffsetX = -3, buffGroupOffsetY = 0, buffSpacing = 2, debuffGroupIconSize = 34,
                    debuffGroupOffsetX = 230, debuffGroupOffsetY = 2, debuffSpacing = 2,
                },
                overrideSharedLayout = true,
                layoutShared = {
                    buffGrowthX = "RIGHT", buffGrowthY = "UP", debuffGrowthX = "UP", debuffGrowthY = "UP", maxBuffs = 4, maxDebuffs = 3,
                    perRow = 8,
                },
            },
            focus = {
                overrideFilters = false, overrideLayout = true,
                layout = {
                    buffGroupIconSize = 30, buffGroupOffsetX = -1, buffGroupOffsetY = 0, buffSpacing = 2, debuffGroupIconSize = 26,
                    debuffGroupOffsetX = 125, debuffGroupOffsetY = 1, debuffSpacing = 2,
                },
            },
        },
    },
    BossAuraOwner = {
            overrideFilters = false, overrideLayout = true,
            layout = {
                buffGroupIconSize = 40, buffGroupOffsetX = -1, buffGroupOffsetY = -3, buffSpacing = 2, debuffGroupIconSize = 26,
                debuffGroupOffsetX = 234, debuffGroupOffsetY = -45, debuffSpacing = 2,
            },
        },
    ArenaAuraOwner = {
            overrideFilters = false, overrideLayout = true,
            layout = {
                buffGroupIconSize = 26, buffGroupOffsetX = -1, buffGroupOffsetY = -3, buffSpacing = 2, debuffGroupIconSize = 26,
                debuffGroupOffsetX = 234, debuffGroupOffsetY = -45, debuffSpacing = 2,
            },
        },
    PredictionBars = {
    absorbAnchorMode = 5, absorbBarHeight = 0, absorbBarOffsetY = 0, absorbBarOpacity = 1, absorbBarTexture = "MSUF Smooth v2",
    absorbTextMode = 2, enableAbsorbBar = true, healAbsorbAnchorMode = 3, healAbsorbBarHeight = 0, healAbsorbBarOffsetY = 0,
    healAbsorbBarOpacity = 1, healAbsorbBarTexture = "Solid", healAbsorbEnabled = true, healPredAllHealers = false, healPredAnchorMode = 3,
    healPredEnabled = true, healPredictionBarHeight = 0, healPredictionBarOffsetY = 0, healPredictionBarOpacity = 0.45,
    healPredictionBarTexture = "", overAbsorbOverlay = true, tempMaxHealthBackgroundOpacity = 0.65, tempMaxHealthColorB = 0.10,
    tempMaxHealthColorG = 0.10, tempMaxHealthColorR = 0.70, tempMaxHealthEnabled = false, tempMaxHealthOpacity = 1,
    tempMaxHealthTexture = "Solid",
},
    CoreShortenNames = { shortenNames = false },
    CoreTexLayerLinkGeometry = { texLayerLinkGeometry = false, texLayerLinkSize = false },
    CoreOocFadeEnabled = { oocFadeEnabled = false, oocFadeAlpha = 0.5 },
    CoreAlphaExcludeTextPortrait = { alphaExcludeTextPortrait = false, alphaExcludePredictionBars = false },
    CoreHpBarAlpha = { hpBarAlpha = 1, powerBarAlpha = 1, hpBgAlpha = 0.85 },
    CoreSmoothFill = { smoothFill = false },
    CoreUseBlizzardFrame = { useBlizzardFrame = false },
    CoreEnabled = { enabled = true },
    CorePlayerDefensives = { playerDefensives = "FOLLOW_PORTRAIT" },
    CoreEliteIconOffsetX = { eliteIconOffsetX = 18, eliteIconOffsetY = 0, eliteIconLayer = 25, eliteIconStyle = "BLIZZARD" },
    CoreShowEliteIcon = { showEliteIcon = true, eliteIconSize = 18, eliteIconAnchor = "TOPRIGHT" },
    CorePvpIndicatorSize = {
        pvpIndicatorAnchor = "TOPRIGHT", pvpIndicatorLayer = 7, pvpIndicatorOffsetX = 0, pvpIndicatorOffsetY = 0, pvpIndicatorSize = 18,
    },
    CoreShowPetXPBar = {
        petXPBarAnchor = "BOTTOM", petXPBarLayer = 7, petXPBarOffsetX = 0, petXPBarOffsetY = -5, petXPBarSize = 8, petXPBarWidth = 80,
        showPetXPBar = true,
    },
    CoreShowPetHappinessIndicator = {
        petHappinessIndicatorAnchor = "RIGHT", petHappinessIndicatorLayer = 7, petHappinessIndicatorOffsetX = -7,
        petHappinessIndicatorOffsetY = -4, petHappinessIndicatorSize = 24, showPetHappinessIndicator = true,
    },
    CoreRaidMarkerSize = { raidMarkerSize = 14, raidMarkerLayer = 7 },
    CoreRaidMarkerOffsetY = { raidMarkerOffsetY = 3 },
    CoreShowRaidMarker = { showRaidMarker = true },
    CoreShowRestingIndicator = { showRestingIndicator = true },
    CoreCombatStateIndicatorPos = { combatStateIndicatorPos = 'TOPLEFT' },
    CoreShowIncomingResIndicator = { showIncomingResIndicator = true, incomingResIndicatorPos = 'TOPRIGHT' },
    CoreRaidGroupNameStyle = { raidGroupNameStyle = 'PAREN' },
    CoreRaidGroupNameAnchor = { raidGroupNameAnchor = 'NAMERIGHT' },
    CoreLevelIndicatorAnchor = { levelIndicatorAnchor = 'NAMERIGHT' },
    CoreBarBorderStyle = { barBorderStyle = "THIN" },
    CoreUseBarBorder = { useBarBorder = true },
    CoreNpcTypeTarget = { npcTypeTarget = true, npcTypeFocus = true, npcTypeBoss = true, npcTypeToT = true },
    CoreNpcColorMode = { npcColorMode = "reaction" },
    CoreUseClassColors = { useClassColors = true },
    CoreGradientStrength = { gradientStrength = 0.45 },
    CoreEnablePowerGradient = { enablePowerGradient = false },
    CoreBarBgClassColor = { barBgClassColor = false },
    CoreBarBgMatchHPColor = { barBgMatchHPColor = false },
    CoreDarkBgCustomColor = { darkBgCustomColor = false },
    CoreDarkBgBrightness = { darkBgBrightness = 0.25 },
    CorePlayerDefensives003 = { playerDefensives = "FOLLOW_PORTRAIT" },
    CoreAlphaExcludeTextPortrait002 = { alphaExcludeTextPortrait = false, alphaExcludePredictionBars = false, oocFadeEnabled = false, oocFadeAlpha = 0.5 },
    CoreHpBarAlpha001 = { hpBarAlpha = 1, powerBarAlpha = 1, hpBgAlpha = 0.85 },
    UnitsAlphaExcludeTextPortrait = { alphaExcludeTextPortrait = false },
    UnitsHpBarAlpha = { hpBarAlpha = 1, powerBarAlpha = 1, hpBgAlpha = 0.85 },
    UnitsPortraitClickable = { portraitClickable = false, portraitBlizzardElite = false },
    UnitsRangeFadeEnabled = { rangeFadeEnabled = true, rangeFadeAlpha = 0.4, rangeFadeLayerMode = "frame" },
    UnitsRangeFadeEnabled006 = { rangeFadeEnabled = true },
    UnitsRangeFadeCastbar = { rangeFadeCastbar = false, rangeFadeAuras = false },
    UnitsRangeFadeCastbar004 = { rangeFadeCastbar = false, rangeFadeAuras = false, showTrinket = true },
    UnitsShowToTInTargetName = { showToTInTargetName = false, totInlineSeparator = "|", totInlineCustomSeparator = "", totInlineColorMode = "AUTO" },
    UnitsChannelTickUseCustom = { channelTickUseCustom = false },
    Units_portraitScopeKey = { _portraitScopeKey = "shared" },
    BarsBarBackgroundAlpha = { barBackgroundAlpha = 90 },
    BarsBarOutlineLayer = { barOutlineLayer = 0, barOutlineTexture = "" },
    BarsDetachedPowerBarOutline = {
        detachedPowerBarOutline = 1, embedPowerBarIntoHealth = true, playerHPBarAnchor = "CLASS_TOP", playerHPBarBgAlpha = 0.35,
        playerHPBarBgTexture = "", playerHPBarColorMode = "GLOBAL", playerHPBarEnabled = false, playerHPBarFrameLevelOffset = 7,
        playerHPBarGap = 2, playerHPBarHeight = 6, playerHPBarOffsetX = 0, playerHPBarOffsetY = 0, playerHPBarOrbSize = 54,
        playerHPBarOutline = 1, playerHPBarShape = "BAR", playerHPBarSmoothFill = false, playerHPBarTextCenter = "NONE",
        playerHPBarTextEnabled = true, playerHPBarTextLeft = "NONE", playerHPBarTextOffsetX = 0, playerHPBarTextOffsetY = 0,
        playerHPBarTextReverse = false, playerHPBarTextRight = "CURPERCENT", playerHPBarTextSeparator = "", playerHPBarTextSize = 14,
        playerHPBarTexture = "", playerHPBarUsePlayerText = true, playerHPBarWidth = 0, playerHPBarWidthMode = "class",
        realtimePowerText = true, roundedCastbars = false, roundedClassResources = false, roundedCornerStrength = 3,
        roundedFramesEnabled = false, roundedGroupFrames = true, roundedMouseover = true, roundedPowerBars = true,
        roundedUnitFrames = true, slantedCastbars = false, slantedClassResources = false, slantedGroupFrames = true,
        slantedMouseover = true, slantedPowerBars = true, slantedUnitFrames = true,
    },
    BarsPowerBarTexture = { powerBarTexture = "", powerBarBgTexture = "" },
    BarsClassPowerComboPointColorMode = { classPowerComboPointColorMode = "default", classPowerShape = "BAR", classPowerShapeAlign = "CENTER" },
    BarsShowTargetPowerBar = {
        chunkedPowerBar = false, powerBarHeight = 3, showArenaPowerBar = true, showBarBorder = true, showBossPowerBar = true,
        showFocusPowerBar = true, showPlayerPowerBar = true, showTargetPowerBar = true, smoothPowerBar = false,
    },
    BarsAbsorbAnchorMode = { absorbAnchorMode = 5 },
    BarsShowSelfHealPrediction = { showSelfHealPrediction = true },
    BarsEnableAbsorbBar = { enableAbsorbBar = true },
    BarsHpPowerTextSelectedKey = { hpPowerTextSelectedKey = "shared" },
    BarsKickReadyShowTarget = {
        kickReadyAnchor = "RIGHT", kickReadyOffsetX = 4, kickReadyOffsetY = 0, kickReadyShowArena = false, kickReadyShowBoss = false,
        kickReadyShowFocus = false, kickReadyShowTarget = false, kickReadySize = 8, kickReadyStyle = "border",
    },
    BarsCastbarTexture = { castbarTexture = "MSUF Lucent" },
    BarsCastbarBackgroundTexture = { castbarBackgroundTexture = "Solid" },
    BarsFontSize = { fontSize = 14 },
    BarsCastbarGlobalWidth = { castbarGlobalWidth = 200, castbarGlobalHeight = 18 },
    BarsCastbarShakeStrength = { castbarShakeStrength = 8 },
    BarsArenaCastbarOffsetX = { arenaCastbarOffsetX = 2, arenaCastbarOffsetY = 0, arenaCastbarWidth = 176, arenaCastbarHeight = 12 },
    BarsArenaCastTimeFormat = { arenaCastTimeFormat = "CURRENT" },
    BarsCastbarShowPushback = { castbarShowPushback = false },
    BarsCastbarHideTradeSkills = { castbarHideTradeSkills = false },
    BarsCastbarOpositeDirectionTarget = { castbarOpositeDirectionTarget = false },
    BarsCastbarUnifiedDirection = { castbarUnifiedDirection = false },
    BarsPlayerCastbarOverrideMode = { playerCastbarOverrideMode = "CLASS" },
    ShellMeleeSpellPerClass = { meleeSpellPerClass = false, meleeSpellPerSpec = false },
    ShellEnableCombatTimer = {
        combatFontSize = 24, combatOffsetX = 0, combatOffsetY = -200, combatStateDuration = 1.5, combatStateFontSize = 24,
        combatStateOffsetX = 0, combatStateOffsetY = 80, cooldownIcons = false, crosshairSize = 40, crosshairThickness = 2,
        enableCombatCrosshair = false, enableCombatCrosshairMeleeRangeColor = false, enableCombatStateText = false,
        enableCombatTimer = false, lockCombatState = false, lockCombatTimer = false, nameplateMeleeSpellID = 0,
    },
    ShellPowerTextMode = { powerTextMode = "CURPERCENT" },
    ShellShowAFK = { showAFK = false, showDND = false, showDead = true, showGhost = true },
    ShellBossTargetHighlightEnabled = { bossTargetHighlightEnabled = true },
    ShellHighlightEnabled = { highlightEnabled = true },
    ShellUseCustomFontColor = { useCustomFontColor = false },
    ShellShortenNameMaxChars = { shortenNameMaxChars = 6, shortenNameClipSide = "LEFT", shortenNameFrontMaskPx = 8, shortenNameShowDots = true },
    ShellEditModeSnapToGrid = { editModeSnapToGrid = false },
    ShellColorPowerTextByType = { colorPowerTextByType = true },
    ShellPlayTargetSelectLostSounds = { playTargetSelectLostSounds = false },
    ShellHide = { hide = false, minimapPos = 220, radius = 80 },
    ShellNsrtNicknameIntegration = { nsrtNicknameIntegration = true },
    ShellEllesmereEditModeIntegration = { ellesmereEditModeIntegration = true },
    ShellTooltipShowAuraCasterNames = { tooltipShowAuraCasterNames = false },
    ShellTooltipShowAuraSpellIDs = { tooltipShowAuraSpellIDs = false },
    ShellShowWelcomeMessage = { showWelcomeMessage = true },
    ShellPlayerResourcePingEnabled = { playerResourcePingEnabled = true },
    ShellShowMinimapIcon = { showMinimapIcon = true },
    FreshUnitTooltipProvider = {
        disableUnitInfoTooltips = true, previewDragHintAnimationEnabled = true, showGameMenuButton = true,
        unitInfoTooltipStyle = "classic", unitTooltipAnchor = "EXTERNAL", unitTooltipMode = "ALWAYS", unitTooltipModifier = "ALT",
        unitTooltipProvider = "GAME",
    },
    FreshMsufUiScale = {
        msufUiScale = 1.0,
    },
    FreshEnabled = {
        Enabled = false, Scale = 1.0,
    },
    FreshAnchorToCooldown = {
        anchorName = "UIParent", anchorToCooldown = false, disableScaling = false, globalUiScalePreset = "auto",
    },
    FreshShowAFK = {
        showAFK = false, showDND = false,
    },
    FreshRoundedFramesEnabled = {
        roundedCastbars = false, roundedClassResources = false, roundedCornerStrength = 3, roundedFramesEnabled = false,
        roundedGroupFrames = true, roundedMouseover = true, roundedPowerBars = true, roundedUnitFrames = true,
    },
    FreshShowAltMana = {
        altManaOffsetX = 0, altManaWidth = 0, altManaWidthMode = "player", guardianIronfurShowHashLines = true, showAltMana = false,
        showGuardianIronfur = false, showSweepingStrikes = false,
    },
    FreshSortRolesAcrossRaid = {
        sortAlphabeticalWithinRole = false, sortRolesAcrossRaid = false,
    },
    FreshAlphaExcludePredictionBars = {
        alphaExcludePredictionBars = false,
    },
    FreshShowName = {
        showName = false,
    },
    FreshCooldownSwipeReverse = {
        cooldownSwipeReverse = false, durationBarDirection = "REMAINING", durationBarDisplay = "BAR_ONLY", durationBarHeight = 2,
        durationBarPosition = "BOTTOM", showDurationBar = false, sortMethod = "DEFAULT", sortReverse = false,
    },
    FreshStrata = {
        strata = "AUTO",
    },
    FreshBlizzardIconSize = {
        blizzardContainerAnchor = "FRAME", blizzardContainerX = 0, blizzardContainerY = 0, blizzardDispelBorder = false,
        blizzardDispelMode = "allDispellable", blizzardIconSize = 20, blizzardOrganizationType = "default",
        blizzardShowCooldownText = true,
    },
    FreshBuffs = {
        buffs = true, debuffs = true, dispels = true, externals = true,
    },
    FreshRenderer = {
        renderer = "NATIVE_12_1",
    },
    FreshTrackedStrata = { trackedStrata = "AUTO" },
    FreshHidePermanent = { hidePermanent = false },
    PortraitDragon = {
        portraitDragonArtwork = false, portraitDragonFlip = false, portraitDragonInInstances = true, portraitDragonLayer = "OVERLAY",
        portraitDragonLevel = 1, portraitDragonScale = 100, portraitDragonX = 0, portraitDragonY = 0,
    },
    GCD = {
        gcdBarCombatOnly = false, gcdBarDetached = false, gcdBarHeight = 12, gcdBarIdle = false, gcdBarOpacity = 100, gcdBarWidth = 180,
        gcdBarX = 0, gcdBarY = -180, kickReadyTimeMarker = false,
    },
    ArenaTrinket = { showTrinket = true, trinketSize = 20, trinketAnchor = "RIGHT", trinketOffsetX = 4, trinketOffsetY = 0, trinketLayer = 10 },
    PetHappiness = {
        petHappinessIndicatorAnchor = "RIGHT", petHappinessIndicatorLayer = 7, petHappinessIndicatorOffsetX = -7,
        petHappinessIndicatorOffsetY = -4, petHappinessIndicatorSize = 24, showPetHappinessIndicator = true,
    },
    FactoryDbkeyDispelSymbolTrigger = {
        dispelSymbolTrigger = "BY_ME",
    },
    FactoryDbkeyUnitDispelSymbolTrigger = {
        unitDispelSymbolTrigger = "BY_ME",
    },
    FactoryDbgeneralUnitDispelSymbolTrigger = {
        unitDispelSymbolTrigger = "BY_ME",
    },
    FactoryG_msufFactoryNameShorteningFixed_v1 = {
        _msufFactoryNameShorteningFixed_v1 = true, _msufFactoryScopedNameShorteningFixed_v1 = true,
    },
    FactoryGDispelBorderTrigger = {
        dispelBorderTrigger = "BY_RAID",
    },
    FactoryGCastbarFillDirection = {
        castbarFillDirection = "LTR",
    },
    FactoryGEditModeGridEnabled = {
        editModeBgAlpha = 0.55, editModeGridEnabled = true, editModeGridStep = 36, editModeSnapEnabled = true,
    },
    FactoryGUnitPreviewGuidesEnabled = {
        classPowerPreviewGuidesEnabled = false, unitPreviewGuidesEnabled = false,
    },
    FactoryG_msufPreviewDragHintExperienced = {
        _msufPreviewDragHintExperienced = false,
    },
    FactoryGBarTexture = {
        barTexture = "MSUF Lucent", castbarTexture = "MSUF Lucent",
    },
    FactoryGSlashMenuScale = {
        slashMenuScale = 0.8,
    },
    FactoryDbfocustargetEnabled = {
        enabled = false,
    },
    FactoryDbgfpartyEnabled = {
        enabled = true,
    },

    FactoryDbkeySmoothFill = {
        chunkedFill = false, powerChunkedFill = false, powerSmoothFill = false, smoothFill = false,
    },
    FactoryDbbarsClassPowerSmoothFill = {
        altManaSmoothFill = false, classPowerSmoothFill = false,
    },
    FactoryDbbarsChunkedPowerBar = {
        chunkedPowerBar = false,
    },
    FactoryDbbarsSmoothPowerBar = {
        smoothPowerBar = false,
    },
    FactoryConfAnchorToUnitframe = {
        anchorToUnitframe = "GLOBAL",
    },
    GroupAuraLane = {
            _filterMigV3 = true,






            iconScale = 100, iconZoom = 100,




            strata = "AUTO",

            blacklistCats = {},
            blacklist = { hidePermanent = false, spells = {} },
            cooldownSwipeReverse = false, durationBarDirection = "REMAINING", durationBarDisplay = "BAR_ONLY", durationBarHeight = 2,
            durationBarPosition = "BOTTOM", showCooldown = true, showCooldownSwipe = true, showDurationBar = false, showTooltip = true,
            sortMethod = "DEFAULT", sortReverse = false,


            cooldownAnchor = "CENTER", cooldownDecimalSeconds = 3, cooldownX = 0, cooldownY = 0,

            stackAnchor = "BOTTOMRIGHT", stackX = 0, stackY = 0,
        },
    GroupAuras = {
            dynamicScale = false, enabled = true, iconZoom = 100, profileModelRevision = 1, renderer = "NATIVE_12_1", showTooltip = true,
            blizzardTypes = {
                buffs = false, debuffs = true, dispels = true, externals = true, privateAuras = true,
            },
            blizzardContainerAnchor = "FRAME", blizzardContainerX = 0, blizzardContainerY = 0, blizzardDispelBorder = false,
            blizzardDispelMode = "allDispellable", blizzardIconSize = 20, blizzardOrganizationType = "default",
            blizzardShowCooldownText = true,
        },
    GroupRaidLanes = {
        buff = {
                anchor = "TOPLEFT", growth = "RIGHTDOWN", layer = 8, max = 1, perRow = 1, size = 12, spacing = 0, x = 14, y = -2,
                 stackSize = 10,
            },
        debuff = {
                anchor = "BOTTOMLEFT", filterToken = "ALL", growth = "RIGHTUP", layer = 10, max = 1, perRow = 1, size = 18, spacing = 0,
                stackSize = 10, x = 20, y = 2,
            },
        externals = {
                anchor = "BOTTOMLEFT", filterToken = "RAID", growth = "RIGHTUP", layer = 11, max = 1, perRow = 1, showStacks = false,
                size = 16, spacing = 1, stackSize = 10, x = 2, y = 2,
            },
    },
    GroupPartyLanes = {
        buff = {
                anchor = "TOPLEFT", growth = "RIGHTDOWN", layer = 8, max = 1, perRow = 1, size = 14, spacing = 0, x = 44, y = -2,
                 stackSize = 10,
            },
        debuff = {
                anchor = "BOTTOMLEFT", filterToken = "ALL", growth = "RIGHTUP", layer = 10, max = 1, perRow = 1, size = 20, spacing = 0,
                stackSize = 12, x = 22, y = 2,
            },
        externals = {
                anchor = "BOTTOMLEFT", filterToken = "RAID", growth = "RIGHTUP", layer = 11, max = 1, perRow = 1, showStacks = false,
                size = 18, spacing = 1, stackSize = 11, x = 2, y = 2,
            },
    },
    GroupAuraState = { privateAuras = {
                anchor = "RIGHT", direction = "LEFT", enabled = false, layer = 12, max = 1, showCountdown = true, showNumbers = false,
                size = 12, spacing = 1, x = -4, y = 0,
            }, spellIndicators = {
                enabled = false, spec = "auto", specs = {},
                iconScale = 100, iconZoom = 100, layer = 9, strata = "AUTO",
                _autoSeededSpecs = {},
            } },
    UnitPortrait = {
        portraitAlpha = 100, portraitBgColorA = 0.85, portraitBgColorB = 0.05, portraitBgColorG = 0.05, portraitBgColorR = 0.05,
        portraitBgEnabled = false, portraitBlizzardDirection = "AUTO", portraitBorderArt = "FLAT", portraitBorderColorA = 1,
        portraitBorderColorB = 1, portraitBorderColorG = 1, portraitBorderColorR = 1, portraitBorderDirection = "UP",
        portraitBorderStyle = "NONE", portraitBorderThickness = 2, portraitClassStyle = "BLIZZARD", portraitDetachedPoint = "RIGHT",
        portraitDetachedTo = "LEFT", portraitDragonArtwork = false, portraitDragonFlip = false, portraitDragonInInstances = true,
        portraitDragonLayer = "OVERLAY", portraitDragonLevel = 1, portraitDragonScale = 100, portraitDragonX = 0, portraitDragonY = 0,
        portraitEdgeSoftness = 0, portraitFillBorder = false, portraitFlip = false, portraitHeight = 0, portraitInnerShadow = 0,
        portraitLevelOffset = 7, portraitOffsetX = 0, portraitOffsetY = 0, portraitOverlayAlign = "LEFT", portraitPanX = 0,
        portraitPanY = 0, portraitPlacement = "ATTACHED", portraitShape = "SQUARE", portraitSizeMode = "UNIFORM", portraitSizeOverride = 0,
        portraitWidth = 0, portraitZoom = 100,
    },
}
Schema.Values = values

-- Read metadata only: absent optional fields remain absent in saved profiles.
Schema.ReadDefaults = {
    gameplay = {
        combatFontSize = 24, combatOffsetX = 0, combatOffsetY = -200, combatStateDuration = 1.5, combatStateEnterText = "+Combat",
        combatStateFontSize = 24, combatStateLeaveText = "-Combat", combatStateOffsetX = 0, combatStateOffsetY = 80,
        combatTimerAnchor = "none", combatTimerClickThrough = false, crosshairSize = 40, crosshairThickness = 3,
        enableCombatCrosshair = false, enableCombatCrosshairMeleeRangeColor = false, enableCombatStateText = false,
        enableCombatTimer = false, enablePlayerTotems = false, lockCombatState = false, lockCombatTimer = false,
        meleeSpellPerClass = false, meleeSpellPerSpec = false, playerTotemsAnchorFrom = "TOPLEFT", playerTotemsAnchorTo = "BOTTOMLEFT",
        playerTotemsIconSize = 24, playerTotemsOffsetX = 0, playerTotemsOffsetY = -6,
    },
    unit = {
        alphaExcludePredictionBars = false, alphaExcludeTextPortrait = false, hpBarAlpha = 1, hpBgAlpha = 0.85, oocFadeAlpha = 0.5,
        oocFadeEnabled = false, powerBarAlpha = 1, powerBarBgAlpha = 0.85, rangeFadeAlpha = 0.4, rangeFadeEnabled = true,
        rangeFadeLayerMode = "frame", rangeFadeUpdateRate = 0,
    },
    bars = {
        arcaneWindowTextFrom = 0, arcaneWindowWarnLastGCD = false, manaGainPulse = false, manaRegenPause = false, manaUpcomingCost = false,
        resourceExtraOffsetX = 0, showArcaneWindow = false, showIgnorePain = false,
    },
}

-- Nil-only recursive fill; every created owner is private to the destination.
-- overwrite is used only for authored factory invariants, never profile repair.
function Schema.Fill(owner, defaults, overwrite)
    if type(owner) ~= "table" then return owner end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if owner[key] == nil or overwrite then owner[key] = {} end
            if type(owner[key]) == "table" then Schema.Fill(owner[key], value, overwrite) end
        elseif owner[key] == nil or overwrite then
            owner[key] = value
        end
    end
    return owner
end

Schema.SeedStages = stages

function Schema.SeedGeneral(owner, id)
    Schema.Fill(owner, stages[id])
end


local menuDefaults = {}
for _, entry in ipairs(entries) do
    if not entry.normalizerOnly then menuDefaults[entry.key] = entry.default end
end

function Schema.FillMenuDefaults(profile)
    if type(profile) ~= "table" then return end
    local general = profile.general
    if type(general) ~= "table" then
        general = {}
        profile.general = general
    end
    Schema.Fill(general, menuDefaults)
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

-- BEGIN SPARSE V3 INHERITED DEFAULTS
-- Generated by tools/defaults_schema_generate.lua --sparse-v3.
-- Slot paths/order are fixed; values intentionally follow current defaults.
local sparseV3Fields = {
    sparseV2Fields[339],
    { "absorbBarHeight", 0 },
    { "absorbBarOffsetY", 0 },
    sparseV2Fields[341],
    sparseV2Fields[696],
    sparseV2Fields[342],
    { "alphaExcludePredictionBars", false },
    { "alphaExcludeTextPortrait", false },
    sparseV2Fields[1],
    { "chunkedFill", false },
    sparseV2Fields[2],
    sparseV2Fields[3],
    sparseV2Fields[4],
    { "eliteIconOffsetY", 0 },
    sparseV2Fields[5],
    sparseV2Fields[6],
    sparseV2Fields[7],
    sparseV2Fields[506],
    sparseV2Fields[8],
    sparseV2Fields[539],
    { "healAbsorbBarHeight", 0 },
    { "healAbsorbBarOffsetY", 0 },
    sparseV2Fields[540],
    sparseV2Fields[785],
    sparseV2Fields[541],
    { "healPredAllHealers", false },
    sparseV2Fields[542],
    sparseV2Fields[543],
    { "healPredictionBarHeight", 0 },
    { "healPredictionBarOffsetY", 0 },
    sparseV2Fields[544],
    { "healPredictionBarTexture", "" },
    { "healthTextDecimals", false },
    sparseV2Fields[9],
    { "hpAbsorbIcon", false },
    sparseV2Fields[10],
    sparseV2Fields[11],
    sparseV2Fields[12],
    { "hpTextCenterOffsetX", 0 },
    { "hpTextCenterOffsetY", 0 },
    sparseV2Fields[13],
    { "hpTextLeftOffsetX", 0 },
    { "hpTextLeftOffsetY", 0 },
    sparseV2Fields[14],
    { "hpTextMouseover", false },
    { "hpTextMouseoverFadeIn", 0 },
    { "hpTextMouseoverFadeOut", 0 },
    { "hpTextReverse", false },
    { "hpTextRightOffsetX", 0 },
    { "hpTextRightOffsetY", 0 },
    sparseV2Fields[15],
    sparseV2Fields[16],
    sparseV2Fields[17],
    sparseV2Fields[18],
    sparseV2Fields[19],
    { "nameTextMouseover", false },
    { "nameTextMouseoverFadeIn", 0 },
    { "nameTextMouseoverFadeOut", 0 },
    { "offsetX", 610 },
    { "offsetY", -244 },
    sparseV2Fields[20],
    { "oocFadeEnabled", false },
    sparseV2Fields[580],
    sparseV2Fields[21],
    sparseV2Fields[22],
    sparseV2Fields[23],
    sparseV2Fields[24],
    sparseV2Fields[25],
    { "portraitBgEnabled", false },
    sparseV2Fields[26],
    { "portraitBlizzardElite", false },
    sparseV2Fields[27],
    sparseV2Fields[28],
    sparseV2Fields[29],
    sparseV2Fields[30],
    sparseV2Fields[31],
    sparseV2Fields[32],
    sparseV2Fields[33],
    sparseV2Fields[34],
    sparseV2Fields[35],
    { "portraitClickable", false },
    sparseV2Fields[36],
    sparseV2Fields[37],
    { "portraitDragonArtwork", false },
    { "portraitDragonFlip", false },
    sparseV2Fields[38],
    sparseV2Fields[39],
    sparseV2Fields[40],
    sparseV2Fields[41],
    { "portraitDragonX", 0 },
    { "portraitDragonY", 0 },
    { "portraitEdgeSoftness", 0 },
    { "portraitFillBorder", false },
    { "portraitFlip", false },
    { "portraitHeight", 0 },
    { "portraitInnerShadow", 0 },
    sparseV2Fields[42],
    sparseV2Fields[43],
    { "portraitOffsetX", 0 },
    { "portraitOffsetY", 0 },
    sparseV2Fields[44],
    { "portraitPanX", 0 },
    { "portraitPanY", 0 },
    sparseV2Fields[45],
    sparseV2Fields[46],
    sparseV2Fields[47],
    sparseV2Fields[48],
    { "portraitSizeOverride", 0 },
    { "portraitWidth", 0 },
    sparseV2Fields[49],
    sparseV2Fields[50],
    sparseV2Fields[51],
    { "powerBarBgTexture", "" },
    { "powerBarBorderEnabled", false },
    sparseV2Fields[52],
    { "powerBarTexture", "" },
    { "powerChunkedFill", false },
    sparseV2Fields[53],
    sparseV2Fields[54],
    sparseV2Fields[55],
    { "powerSmoothFill", false },
    sparseV2Fields[56],
    { "powerTextCenterOffsetX", 0 },
    { "powerTextCenterOffsetY", 0 },
    sparseV2Fields[57],
    sparseV2Fields[58],
    { "powerTextLeftOffsetX", 0 },
    { "powerTextLeftOffsetY", 0 },
    sparseV2Fields[59],
    { "powerTextMouseover", false },
    { "powerTextMouseoverFadeIn", 0 },
    { "powerTextMouseoverFadeOut", 0 },
    sparseV2Fields[60],
    { "powerTextRightOffsetX", 0 },
    { "powerTextRightOffsetY", 0 },
    sparseV2Fields[61],
    sparseV2Fields[62],
    sparseV2Fields[63],
    { "pvpIndicatorOffsetX", 0 },
    { "pvpIndicatorOffsetY", 0 },
    sparseV2Fields[64],
    sparseV2Fields[65],
    sparseV2Fields[66],
    { "raidGroupNameOffsetY", 0 },
    sparseV2Fields[67],
    sparseV2Fields[73],
    { "rangeFadeAuras", false },
    { "rangeFadeCastbar", false },
    sparseV2Fields[74],
    sparseV2Fields[75],
    { "reverseFillBars", false },
    sparseV2Fields[76],
    sparseV2Fields[77],
    sparseV2Fields[78],
    { "showInterruptSource", false },
    { "showLevelIndicator", false },
    sparseV2Fields[79],
    sparseV2Fields[80],
    sparseV2Fields[81],
    { "showPowerText", false },
    { "showPvpIndicator", false },
    { "showRaidGroupInName", false },
    sparseV2Fields[83],
    { "smoothFill", false },
    sparseV2Fields[84],
    { "statusAFKTextEnabled", false },
    { "statusDNDTextEnabled", false },
    sparseV2Fields[85],
    sparseV2Fields[86],
    sparseV2Fields[624],
    sparseV2Fields[625],
    sparseV2Fields[626],
    sparseV2Fields[627],
    { "tempMaxHealthEnabled", false },
    sparseV2Fields[628],
    sparseV2Fields[629],
    sparseV2Fields[87],
    sparseV2Fields[88],
    sparseV2Fields[89],
    { "texLayer2Atlas", "" },
    sparseV2Fields[90],
    sparseV2Fields[91],
    sparseV2Fields[92],
    sparseV2Fields[93],
    sparseV2Fields[94],
    sparseV2Fields[95],
    sparseV2Fields[96],
    { "texLayer2CustomTexturePath", "" },
    { "texLayer2EdgeSoftness", 0 },
    { "texLayer2Enabled", false },
    sparseV2Fields[97],
    { "texLayer2Gradient2B", 0 },
    { "texLayer2Gradient2G", 0 },
    { "texLayer2Gradient2R", 0 },
    { "texLayer2GradientDirDown", false },
    { "texLayer2GradientDirLeft", false },
    sparseV2Fields[98],
    { "texLayer2GradientDirUp", false },
    { "texLayer2GradientEnabled", false },
    sparseV2Fields[99],
    sparseV2Fields[100],
    { "texLayer2MirrorH", false },
    { "texLayer2MirrorV", false },
    { "texLayer2OffsetX", 0 },
    { "texLayer2OffsetY", 0 },
    { "texLayer2RoundedClip", false },
    sparseV2Fields[101],
    { "texLayer2Texture", "" },
    sparseV2Fields[102],
    { "texLayer2Width", 0 },
    sparseV2Fields[103],
    sparseV2Fields[104],
    sparseV2Fields[105],
    { "texLayer3Atlas", "" },
    sparseV2Fields[106],
    sparseV2Fields[107],
    sparseV2Fields[108],
    sparseV2Fields[109],
    sparseV2Fields[110],
    sparseV2Fields[111],
    sparseV2Fields[112],
    { "texLayer3CustomTexturePath", "" },
    { "texLayer3EdgeSoftness", 0 },
    { "texLayer3Enabled", false },
    sparseV2Fields[113],
    { "texLayer3Gradient2B", 0 },
    { "texLayer3Gradient2G", 0 },
    { "texLayer3Gradient2R", 0 },
    { "texLayer3GradientDirDown", false },
    { "texLayer3GradientDirLeft", false },
    sparseV2Fields[114],
    { "texLayer3GradientDirUp", false },
    { "texLayer3GradientEnabled", false },
    sparseV2Fields[115],
    sparseV2Fields[116],
    { "texLayer3MirrorH", false },
    { "texLayer3MirrorV", false },
    { "texLayer3OffsetX", 0 },
    { "texLayer3OffsetY", 0 },
    { "texLayer3RoundedClip", false },
    sparseV2Fields[117],
    { "texLayer3Texture", "" },
    sparseV2Fields[118],
    { "texLayer3Width", 0 },
    sparseV2Fields[119],
    sparseV2Fields[120],
    sparseV2Fields[121],
    { "texLayerAtlas", "" },
    sparseV2Fields[122],
    sparseV2Fields[123],
    sparseV2Fields[124],
    sparseV2Fields[125],
    sparseV2Fields[126],
    sparseV2Fields[127],
    sparseV2Fields[128],
    { "texLayerCustomTexturePath", "" },
    { "texLayerEdgeSoftness", 0 },
    { "texLayerEnabled", false },
    sparseV2Fields[129],
    { "texLayerGradient2B", 0 },
    { "texLayerGradient2G", 0 },
    { "texLayerGradient2R", 0 },
    { "texLayerGradientDirDown", false },
    { "texLayerGradientDirLeft", false },
    sparseV2Fields[130],
    { "texLayerGradientDirUp", false },
    { "texLayerGradientEnabled", false },
    sparseV2Fields[131],
    sparseV2Fields[132],
    { "texLayerMirrorH", false },
    { "texLayerMirrorV", false },
    { "texLayerOffsetX", 0 },
    { "texLayerOffsetY", 0 },
    { "texLayerRoundedClip", false },
    sparseV2Fields[133],
    { "texLayerTexture", "" },
    sparseV2Fields[134],
    { "texLayerWidth", 0 },
    sparseV2Fields[135],
    sparseV2Fields[136],
    sparseV2Fields[137],
    sparseV2Fields[138],
    sparseV2Fields[139],
    sparseV2Fields[140],
    { "trinketOffsetY", 0 },
    sparseV2Fields[141],
    sparseV2Fields[142],
    { "unitDispelOverlayEnabled", false },
    sparseV2Fields[143],
    sparseV2Fields[144],
    sparseV2Fields[145],
    sparseV2Fields[146],
    sparseV2Fields[147],
    { "unitDispelSymbolEnabled", false },
    sparseV2Fields[148],
    sparseV2Fields[149],
    sparseV2Fields[150],
    sparseV2Fields[151],
    sparseV2Fields[152],
    sparseV2Fields[153],
    sparseV2Fields[154],
    { "unitDispelSymbolTrigger", "BY_ME" },
    { "unitDispelSymbolX", 0 },
    { "unitDispelSymbolY", 0 },
    { "useBlizzardFrame", false },
    { "verticalFillBars", false },
    sparseV2Fields[155],
    { "bigDefensive", false },
    { "cancelable", false },
    { "crowdControl", false },
    { "dispellableAny", false },
    sparseV2Fields[156],
    { "externalDefensive", false },
    { "hidePermanent", false },
    { "includeDispellable", false },
    { "includeNameplateOnly", false },
    { "notCancelable", false },
    { "onlyImportant", false },
    { "onlyMine", false },
    { "raid", false },
    { "raidInCombat", false },
    { 1, 0.68999999999999995 },
    { 2, 0.5 },
    { 3, 0.88 },
    { 4, 0.80000000000000004 },
    { "layer", 0 },
    { "priority", 5 },
    sparseV2Fields[662],
    { "thickness", 2 },
    { "type", "none" },
    { "anchor", "TOPRIGHT" },
    { "barWidth", 54 },
    { "growth", "LEFTDOWN" },
    { "max", 8 },
    { "perRow", 4 },
    sparseV2Fields[656],
    sparseV2Fields[240],
    sparseV2Fields[657],
    { "size", 24 },
    sparseV2Fields[245],
    { "type", "icon" },
    { "x", -293 },
    { "y", 11 },
    { "auraType", "BUFF" },
    { "autoBlacklistPlayerBuffs", true },
    { "disabledPredefinedSpellIDs", {} },
    sparseV2Fields[694],
    { "name", "Defensive Buffs" },
    { "playerDefensives", true },
    { "portraitCooldownText", true },
    { "portraitIcon", true },
    { "portraitMaxIcons", 1 },
    { "portraitPositionWhenDisabled", false },
    { "sourceUnit", "player" },
    { "spellIDs", "" },
    { "items", {} },
    { "perUnit", {} },
    { "serial", 0 },
    { "buffAnchor", "BOTTOMLEFT" },
    { "buffCooldownTextOffsetX", 0 },
    { "buffCooldownTextOffsetY", 0 },
    sparseV2Fields[157],
    sparseV2Fields[158],
    { "buffGroupIconSize", 31 },
    sparseV2Fields[159],
    { "buffGroupOffsetY", 28 },
    sparseV2Fields[160],
    sparseV2Fields[161],
    { "buffSpacing", 0 },
    sparseV2Fields[162],
    sparseV2Fields[163],
    sparseV2Fields[164],
    sparseV2Fields[165],
    { "buffStylePadding", 0 },
    { "debuffAnchor", "BOTTOMRIGHT" },
    { "debuffCooldownTextOffsetX", 0 },
    { "debuffCooldownTextOffsetY", 0 },
    sparseV2Fields[166],
    sparseV2Fields[167],
    { "debuffGroupIconSize", 32 },
    { "debuffGroupOffsetX", 131 },
    { "debuffGroupOffsetY", -2 },
    sparseV2Fields[168],
    sparseV2Fields[169],
    { "debuffSpacing", 0 },
    sparseV2Fields[170],
    sparseV2Fields[171],
    sparseV2Fields[172],
    sparseV2Fields[173],
    { "debuffStylePadding", 0 },
    sparseV2Fields[174],
    { "buffCooldownSwipeReverse", false },
    sparseV2Fields[175],
    sparseV2Fields[176],
    sparseV2Fields[177],
    sparseV2Fields[178],
    { "buffFrameEffectLayer", 0 },
    sparseV2Fields[179],
    sparseV2Fields[180],
    sparseV2Fields[181],
    sparseV2Fields[182],
    sparseV2Fields[183],
    sparseV2Fields[184],
    { "buffPerRow", 4 },
    sparseV2Fields[185],
    sparseV2Fields[186],
    { "buffShowDurationBar", false },
    sparseV2Fields[187],
    { "buffShowStealable", false },
    sparseV2Fields[188],
    sparseV2Fields[189],
    { "buffSortReverse", false },
    sparseV2Fields[190],
    sparseV2Fields[191],
    sparseV2Fields[192],
    { "debuffCooldownSwipeReverse", false },
    sparseV2Fields[193],
    sparseV2Fields[194],
    sparseV2Fields[195],
    sparseV2Fields[196],
    { "debuffFrameEffectLayer", 0 },
    sparseV2Fields[197],
    sparseV2Fields[198],
    sparseV2Fields[199],
    sparseV2Fields[200],
    sparseV2Fields[201],
    sparseV2Fields[202],
    { "debuffPerRow", 4 },
    sparseV2Fields[203],
    sparseV2Fields[204],
    { "debuffShowDurationBar", false },
    sparseV2Fields[205],
    sparseV2Fields[206],
    sparseV2Fields[207],
    { "debuffSortReverse", false },
    sparseV2Fields[208],
    sparseV2Fields[209],
    { "maxBuffs", 3 },
    { "maxDebuffs", 4 },
    sparseV2Fields[210],
    sparseV2Fields[211],
    { "useDebuffTypeBorders", false },
    sparseV2Fields[212],
    sparseV2Fields[213],
    sparseV2Fields[214],
    sparseV2Fields[215],
    { "buffGroupOffsetX", -2 },
    { "buffGroupOffsetY", 32 },
    { "debuffGroupOffsetX", 0 },
    sparseV2Fields[216],
    sparseV2Fields[217],
    sparseV2Fields[218],
    sparseV2Fields[219],
    { 1, 0 },
    { 2, 0 },
    { 3, 0 },
    { 4, 1 },
    { "styleBorderEnabled", false },
    sparseV2Fields[220],
    sparseV2Fields[221],
    { "styleShadowEnabled", false },
    sparseV2Fields[222],
    sparseV2Fields[223],
    sparseV2Fields[224],
    { "buffGroupIconSize", 28 },
    { "buffGroupOffsetX", 0 },
    { "buffGroupOffsetY", 34 },
    sparseV2Fields[225],
    sparseV2Fields[226],
    { "cooldownSwipeReverse", false },
    sparseV2Fields[227],
    { "cooldownTextOffsetX", 0 },
    { "cooldownTextOffsetY", 0 },
    sparseV2Fields[228],
    { "debuffGroupIconSize", 28 },
    { "debuffGroupOffsetX", 330 },
    { "debuffGroupOffsetY", 34 },
    sparseV2Fields[229],
    sparseV2Fields[230],
    sparseV2Fields[231],
    sparseV2Fields[232],
    sparseV2Fields[233],
    sparseV2Fields[234],
    { "hideBlizzardBuffFrame", false },
    { "hideBlizzardDebuffFrame", false },
    sparseV2Fields[235],
    sparseV2Fields[236],
    sparseV2Fields[237],
    sparseV2Fields[238],
    sparseV2Fields[239],
    sparseV2Fields[241],
    { "showDurationBar", false },
    sparseV2Fields[242],
    sparseV2Fields[243],
    sparseV2Fields[244],
    sparseV2Fields[246],
    sparseV2Fields[247],
    sparseV2Fields[248],
    sparseV2Fields[249],
    sparseV2Fields[250],
    sparseV2Fields[251],
    { "showFocus", true },
    sparseV2Fields[252],
    sparseV2Fields[895],
    sparseV2Fields[253],
    sparseV2Fields[254],
    { "altManaColorG", 0 },
    { "altManaColorR", 0 },
    { "altManaOffsetX", 0 },
    { "altManaSmoothFill", false },
    { "altManaWidth", 0 },
    sparseV2Fields[255],
    sparseV2Fields[256],
    { "barOutlineLayer", 0 },
    { "barOutlineTexture", "" },
    sparseV2Fields[257],
    { "chunkedPowerBar", false },
    sparseV2Fields[258],
    sparseV2Fields[259],
    sparseV2Fields[260],
    sparseV2Fields[261],
    { "classPowerFillReverse", false },
    sparseV2Fields[262],
    sparseV2Fields[263],
    sparseV2Fields[264],
    { "classPowerGap", 2 },
    { "classPowerHideOOC", false },
    { "classPowerHideWhenEmpty", false },
    { "classPowerHideWhenFull", false },
    { "classPowerOffsetX", 0 },
    { "classPowerOffsetY", -41 },
    { "classPowerOutline", 2 },
    sparseV2Fields[265],
    sparseV2Fields[266],
    sparseV2Fields[267],
    { "classPowerShowText", false },
    { "classPowerSmoothFill", false },
    { "classPowerSyncPlayerPowerOOC", false },
    sparseV2Fields[268],
    { "classPowerTextOffsetX", 0 },
    { "classPowerTextOffsetY", 0 },
    sparseV2Fields[269],
    { "classPowerWidth", 0 },
    sparseV2Fields[270],
    { "detachedPowerBarOutline", 0 },
    sparseV2Fields[271],
    sparseV2Fields[272],
    sparseV2Fields[273],
    { "playerHPBarBgTexture", "" },
    sparseV2Fields[274],
    { "playerHPBarEnabled", false },
    sparseV2Fields[275],
    sparseV2Fields[276],
    sparseV2Fields[277],
    { "playerHPBarOffsetX", 0 },
    { "playerHPBarOffsetY", 0 },
    sparseV2Fields[278],
    sparseV2Fields[279],
    sparseV2Fields[280],
    { "playerHPBarSmoothFill", false },
    sparseV2Fields[281],
    sparseV2Fields[282],
    sparseV2Fields[283],
    { "playerHPBarTextOffsetX", 0 },
    { "playerHPBarTextOffsetY", 0 },
    { "playerHPBarTextReverse", false },
    sparseV2Fields[284],
    { "playerHPBarTextSeparator", "" },
    sparseV2Fields[285],
    { "playerHPBarTexture", "" },
    sparseV2Fields[286],
    { "playerHPBarWidth", 0 },
    sparseV2Fields[287],
    sparseV2Fields[288],
    { "roundedCastbars", false },
    { "roundedClassResources", false },
    sparseV2Fields[289],
    { "roundedFramesEnabled", false },
    sparseV2Fields[290],
    sparseV2Fields[291],
    sparseV2Fields[292],
    sparseV2Fields[293],
    sparseV2Fields[294],
    sparseV2Fields[295],
    sparseV2Fields[296],
    sparseV2Fields[297],
    sparseV2Fields[298],
    sparseV2Fields[299],
    sparseV2Fields[300],
    sparseV2Fields[301],
    { "showEleMaelstrom", false },
    sparseV2Fields[302],
    { "showGuardianIronfur", false },
    sparseV2Fields[303],
    { "showShadowMana", false },
    sparseV2Fields[304],
    { "showSweepingStrikes", false },
    sparseV2Fields[305],
    { "slantedCastbars", false },
    { "slantedClassResources", false },
    sparseV2Fields[306],
    sparseV2Fields[307],
    sparseV2Fields[308],
    sparseV2Fields[309],
    { "smoothPowerBar", false },
    sparseV2Fields[310],
    sparseV2Fields[311],
    { "alphaExcludePredictionBars", true },
    { "alphaExcludeTextPortrait", true },
    sparseV2Fields[313],
    { "hpBgAlpha", 0.80000001192092896 },
    { "hpOffsetX", 0 },
    { "hpOffsetY", -3 },
    { "invertBossOrder", false },
    { "offsetX", 511 },
    { "offsetY", 370 },
    { "powerBarAlpha", 0.90000003576278687 },
    { "powerBarBgAlpha", 0.80000001192092896 },
    { "showPower", false },
    sparseV2Fields[312],
    { "eliteIconOffsetX", 3 },
    { "eliteIconOffsetY", 5 },
    { "hpOffsetX", -1 },
    { "hpOffsetY", -6 },
    { "levelIndicatorAnchor", "CENTER" },
    { "offsetX", -373 },
    { "offsetY", -340 },
    { "pvpIndicatorOffsetX", 3 },
    { "pvpIndicatorOffsetY", 4 },
    sparseV2Fields[314],
    { "stateIconsTestMode", false },
    { "statusAFKTextEnabled", true },
    { "enabled", false },
    { "hpOffsetY", -8 },
    sparseV2Fields[315],
    sparseV2Fields[316],
    sparseV2Fields[317],
    { "showPowerBar", false },
    { 1, 1 },
    { 2, 1 },
    { 3, 1 },
    { 1, 0.69999999999999996 },
    { 2, 0.69999999999999996 },
    { 3, 0.69999999999999996 },
    sparseV2Fields[318],
    { "combatOffsetX", 0 },
    sparseV2Fields[319],
    { "combatStateColorSync", false },
    sparseV2Fields[320],
    sparseV2Fields[321],
    sparseV2Fields[322],
    sparseV2Fields[323],
    { "combatStateOffsetX", 0 },
    sparseV2Fields[324],
    sparseV2Fields[325],
    sparseV2Fields[326],
    { "cooldownIcons", false },
    sparseV2Fields[327],
    sparseV2Fields[328],
    { "enableCombatCrosshair", false },
    { "enableCombatCrosshairMeleeRangeColor", false },
    { "enableCombatStateText", false },
    { "enableCombatTimer", false },
    sparseV2Fields[329],
    { "lockCombatState", false },
    { "lockCombatTimer", false },
    { "meleeSpellPerClass", false },
    { "meleeSpellPerSpec", false },
    { "nameplateMeleeSpellID", 0 },
    { "nameplateMeleeSpellIDByClass", {} },
    { "nameplateMeleeSpellIDBySpec", {} },
    sparseV2Fields[330],
    sparseV2Fields[331],
    sparseV2Fields[332],
    { "playerTotemsOffsetX", 0 },
    sparseV2Fields[333],
    { "shownGameplayColorsTip", false },
    { "Enabled", false },
    sparseV2Fields[334],
    { 2, 0.81999999999999995 },
    { "top", 785.769287109375 },
    { "left", 1106.666748046875 },
    { "top", 752.0001220703125 },
    { "top", 629.166748046875 },
    { "left", 1036.666748046875 },
    { "top", 774.99993896484375 },
    { "1", 1 },
    { "2", 0 },
    { "3", 0 },
    { "1", 0 },
    { "2", 1 },
    { "hide", false },
    sparseV2Fields[335],
    sparseV2Fields[336],
    { "showAFK", false },
    { "showDND", false },
    sparseV2Fields[337],
    sparseV2Fields[338],
    sparseV2Fields[343],
    sparseV2Fields[344],
    sparseV2Fields[345],
    { "anchorToCooldown", false },
    sparseV2Fields[346],
    sparseV2Fields[347],
    { "arenaCastIconBorderThickness", 0 },
    { "arenaCastIconOffsetX", 0 },
    { "arenaCastIconOffsetY", 0 },
    sparseV2Fields[348],
    sparseV2Fields[349],
    sparseV2Fields[350],
    sparseV2Fields[351],
    sparseV2Fields[352],
    { "arenaCastSpellNameMaxWidth", 0 },
    sparseV2Fields[353],
    sparseV2Fields[354],
    sparseV2Fields[355],
    sparseV2Fields[356],
    sparseV2Fields[357],
    { "arenaCastTargetNameOffsetX", 0 },
    sparseV2Fields[358],
    sparseV2Fields[359],
    { "arenaCastTextOffsetX", 0 },
    { "arenaCastTextOffsetY", 0 },
    sparseV2Fields[360],
    sparseV2Fields[361],
    { "arenaCastTimeOffsetX", 0 },
    { "arenaCastTimeOffsetY", 0 },
    sparseV2Fields[362],
    sparseV2Fields[363],
    sparseV2Fields[364],
    sparseV2Fields[365],
    sparseV2Fields[366],
    { "arenaCastbarOffsetY", 0 },
    { "arenaCastbarTestMode", false },
    sparseV2Fields[367],
    sparseV2Fields[368],
    sparseV2Fields[369],
    sparseV2Fields[370],
    { "barBgClassColor", false },
    sparseV2Fields[371],
    sparseV2Fields[372],
    { "barBgMatchHPColor", false },
    sparseV2Fields[373],
    sparseV2Fields[374],
    sparseV2Fields[375],
    sparseV2Fields[376],
    { "boldText", false },
    sparseV2Fields[377],
    sparseV2Fields[378],
    { "bossCastIconBorderThickness", 0 },
    { "bossCastIconOffsetX", 0 },
    { "bossCastIconOffsetY", 0 },
    sparseV2Fields[379],
    sparseV2Fields[380],
    sparseV2Fields[381],
    sparseV2Fields[382],
    sparseV2Fields[383],
    { "bossCastSpellNameMaxWidth", 0 },
    sparseV2Fields[384],
    sparseV2Fields[385],
    sparseV2Fields[386],
    sparseV2Fields[387],
    sparseV2Fields[388],
    { "bossCastTargetNameOffsetX", 0 },
    sparseV2Fields[389],
    sparseV2Fields[390],
    { "bossCastTextOffsetX", 0 },
    { "bossCastTextOffsetY", 0 },
    sparseV2Fields[391],
    sparseV2Fields[392],
    { "bossCastTimeOffsetX", 0 },
    { "bossCastTimeOffsetY", 0 },
    sparseV2Fields[393],
    sparseV2Fields[394],
    sparseV2Fields[395],
    sparseV2Fields[396],
    sparseV2Fields[397],
    { "bossCastbarOffsetY", 0 },
    { "bossCastbarTestMode", false },
    sparseV2Fields[398],
    sparseV2Fields[399],
    sparseV2Fields[400],
    sparseV2Fields[401],
    { "castbarAccentLastTick", false },
    sparseV2Fields[402],
    { "castbarFillDirection", "LTR" },
    sparseV2Fields[403],
    sparseV2Fields[404],
    sparseV2Fields[405],
    sparseV2Fields[406],
    sparseV2Fields[407],
    { "castbarFocusIconBorderThickness", 0 },
    { "castbarFocusIconOffsetX", 0 },
    { "castbarFocusIconOffsetY", 0 },
    sparseV2Fields[408],
    sparseV2Fields[409],
    sparseV2Fields[410],
    sparseV2Fields[411],
    sparseV2Fields[412],
    sparseV2Fields[413],
    sparseV2Fields[414],
    { "castbarFocusShowTargetName", false },
    sparseV2Fields[415],
    sparseV2Fields[416],
    { "castbarFocusSpellNameMaxWidth", 0 },
    sparseV2Fields[417],
    sparseV2Fields[418],
    sparseV2Fields[419],
    sparseV2Fields[420],
    sparseV2Fields[421],
    { "castbarFocusTargetNameOffsetX", 0 },
    sparseV2Fields[422],
    sparseV2Fields[423],
    { "castbarFocusTextOffsetX", 0 },
    { "castbarFocusTextOffsetY", 0 },
    sparseV2Fields[424],
    sparseV2Fields[425],
    sparseV2Fields[426],
    { "castbarFocusTimeOffsetY", 0 },
    sparseV2Fields[427],
    sparseV2Fields[428],
    sparseV2Fields[429],
    sparseV2Fields[430],
    { "castbarHideTradeSkills", false },
    { "castbarIconOffsetX", 0 },
    { "castbarIconOffsetY", 0 },
    sparseV2Fields[431],
    sparseV2Fields[432],
    sparseV2Fields[433],
    sparseV2Fields[434],
    sparseV2Fields[435],
    { "castbarOpositeDirectionTarget", false },
    sparseV2Fields[436],
    sparseV2Fields[437],
    sparseV2Fields[438],
    sparseV2Fields[439],
    sparseV2Fields[440],
    { "castbarPlayerIconBorderThickness", 0 },
    { "castbarPlayerIconOffsetX", 0 },
    { "castbarPlayerIconOffsetY", 0 },
    sparseV2Fields[441],
    sparseV2Fields[442],
    sparseV2Fields[443],
    sparseV2Fields[444],
    sparseV2Fields[445],
    { "castbarPlayerPreviewEnabled", false },
    sparseV2Fields[446],
    sparseV2Fields[447],
    sparseV2Fields[448],
    sparseV2Fields[449],
    { "castbarPlayerSpellNameMaxWidth", 0 },
    sparseV2Fields[450],
    sparseV2Fields[451],
    sparseV2Fields[452],
    { "castbarPlayerTextOffsetX", 0 },
    { "castbarPlayerTextOffsetY", 0 },
    sparseV2Fields[453],
    sparseV2Fields[454],
    sparseV2Fields[455],
    { "castbarPlayerTimeOffsetY", 0 },
    sparseV2Fields[456],
    sparseV2Fields[457],
    sparseV2Fields[458],
    { "castbarShowChannelTicks", false },
    { "castbarShowGlow", false },
    sparseV2Fields[459],
    { "castbarShowLatencyText", false },
    { "castbarShowPushback", false },
    { "castbarShowSpark", false },
    sparseV2Fields[460],
    sparseV2Fields[461],
    { "castbarSpellNameFontSize", 0 },
    sparseV2Fields[462],
    sparseV2Fields[463],
    { "castbarTargetBarWidth", 271 },
    sparseV2Fields[464],
    sparseV2Fields[465],
    { "castbarTargetIconBorderThickness", 0 },
    { "castbarTargetIconOffsetX", 0 },
    { "castbarTargetIconOffsetY", 0 },
    sparseV2Fields[466],
    sparseV2Fields[467],
    sparseV2Fields[468],
    { "castbarTargetOffsetX", -2 },
    { "castbarTargetOffsetY", -59 },
    sparseV2Fields[469],
    sparseV2Fields[470],
    { "castbarTargetShowTargetName", false },
    sparseV2Fields[471],
    sparseV2Fields[472],
    { "castbarTargetSpellNameMaxWidth", 0 },
    sparseV2Fields[473],
    sparseV2Fields[474],
    sparseV2Fields[475],
    sparseV2Fields[476],
    sparseV2Fields[477],
    { "castbarTargetTargetNameOffsetX", 0 },
    sparseV2Fields[478],
    sparseV2Fields[479],
    { "castbarTargetTextOffsetX", 0 },
    { "castbarTargetTextOffsetY", 0 },
    sparseV2Fields[480],
    sparseV2Fields[481],
    sparseV2Fields[482],
    { "castbarTargetTimeOffsetY", 0 },
    sparseV2Fields[483],
    sparseV2Fields[484],
    sparseV2Fields[485],
    { "castbarTimeFontSize", 0 },
    { "castbarUnifiedDirection", false },
    { "classBarBgB", 0 },
    { "classBarBgG", 0 },
    { "classBarBgR", 0 },
    { "classPowerPreviewGuidesEnabled", false },
    { "colorHealthTextByHealth", false },
    sparseV2Fields[486],
    sparseV2Fields[487],
    sparseV2Fields[488],
    sparseV2Fields[489],
    sparseV2Fields[490],
    sparseV2Fields[491],
    { "darkBgCustomColor", false },
    { "darkMode", false },
    sparseV2Fields[492],
    { "disableScaling", false },
    sparseV2Fields[493],
    sparseV2Fields[494],
    { "dispelBorderTrigger", "BY_RAID" },
    sparseV2Fields[495],
    sparseV2Fields[496],
    sparseV2Fields[497],
    { "editModeBgAlpha", 0.55000000000000004 },
    sparseV2Fields[498],
    { "editModeGridStep", 36 },
    sparseV2Fields[499],
    { "editModeSnapEnabled", true },
    sparseV2Fields[500],
    { "editModeSnapModeFrames", false },
    sparseV2Fields[501],
    { "editModeSnapToGrid", false },
    sparseV2Fields[502],
    sparseV2Fields[503],
    sparseV2Fields[504],
    sparseV2Fields[505],
    sparseV2Fields[507],
    sparseV2Fields[508],
    sparseV2Fields[509],
    { "enableFocusKickIcon", false },
    { "enableGradient", false },
    sparseV2Fields[510],
    sparseV2Fields[511],
    { "enablePowerGradient", false },
    sparseV2Fields[512],
    sparseV2Fields[513],
    sparseV2Fields[514],
    sparseV2Fields[515],
    sparseV2Fields[516],
    sparseV2Fields[517],
    sparseV2Fields[518],
    sparseV2Fields[519],
    sparseV2Fields[520],
    { "focusCastbarTestMode", false },
    sparseV2Fields[521],
    sparseV2Fields[522],
    { "focusKickIconOffsetY", 0 },
    sparseV2Fields[523],
    { "focusKickShowCastbar", false },
    { "fontBaselineOffset", 0 },
    sparseV2Fields[524],
    sparseV2Fields[525],
    { "fontMonochrome", false },
    sparseV2Fields[526],
    sparseV2Fields[527],
    sparseV2Fields[528],
    { "fontSlug", true },
    sparseV2Fields[529],
    { "fullHealthAbsorbStripe", false },
    { "gcdBarCombatOnly", false },
    { "gcdBarDetached", false },
    sparseV2Fields[530],
    { "gcdBarIdle", false },
    sparseV2Fields[531],
    sparseV2Fields[532],
    { "gcdBarX", 0 },
    sparseV2Fields[533],
    sparseV2Fields[534],
    { "gradientDirDown", false },
    { "gradientDirLeft", false },
    sparseV2Fields[535],
    { "gradientDirUp", false },
    sparseV2Fields[536],
    sparseV2Fields[537],
    sparseV2Fields[538],
    { "healthBarGradientColorB", 0 },
    { "healthBarGradientColorG", 0 },
    { "healthBarGradientColorR", 0 },
    { "healthGradientHighB", 0 },
    sparseV2Fields[545],
    { "healthGradientHighR", 0 },
    { "healthGradientLowB", 0 },
    { "healthGradientLowG", 0 },
    sparseV2Fields[546],
    { "healthGradientMidB", 0 },
    sparseV2Fields[547],
    sparseV2Fields[548],
    { "healthLossColorB", 0.080000000000000002 },
    { "healthLossColorG", 0.55000000000000004 },
    { "healthLossColorR", 1 },
    sparseV2Fields[549],
    sparseV2Fields[550],
    sparseV2Fields[551],
    sparseV2Fields[552],
    sparseV2Fields[553],
    sparseV2Fields[554],
    sparseV2Fields[555],
    sparseV2Fields[556],
    sparseV2Fields[557],
    sparseV2Fields[558],
    sparseV2Fields[559],
    { "kickReadyOffsetY", 0 },
    { "kickReadyShowArena", false },
    { "kickReadyShowBoss", false },
    { "kickReadyShowFocus", false },
    { "kickReadyShowTarget", false },
    sparseV2Fields[560],
    sparseV2Fields[561],
    { "kickReadyTimeSegment", false },
    sparseV2Fields[562],
    { "leaderIconOffsetX", 0 },
    sparseV2Fields[563],
    sparseV2Fields[564],
    sparseV2Fields[565],
    sparseV2Fields[566],
    { "levelIndicatorOffsetX", 0 },
    { "levelIndicatorOffsetY", 0 },
    sparseV2Fields[567],
    { "menuAppearancePreset", "classicGlass" },
    sparseV2Fields[568],
    { "msuf2WindowH", 1200 },
    { "msuf2WindowW", 1216 },
    sparseV2Fields[569],
    { "nameClassColor", false },
    sparseV2Fields[570],
    { "nameNpcClassColor", false },
    { "noOutline", false },
    { "npcClassColorBar", false },
    sparseV2Fields[571],
    { "npcNameRed", false },
    sparseV2Fields[572],
    sparseV2Fields[573],
    sparseV2Fields[574],
    sparseV2Fields[575],
    sparseV2Fields[576],
    sparseV2Fields[577],
    sparseV2Fields[578],
    sparseV2Fields[579],
    { "playTargetSelectLostSounds", true },
    sparseV2Fields[581],
    sparseV2Fields[582],
    sparseV2Fields[583],
    sparseV2Fields[584],
    sparseV2Fields[585],
    { "playerCastbarTestMode", false },
    sparseV2Fields[586],
    { "powerBarGradientColorB", 0 },
    { "powerBarGradientColorG", 0 },
    { "powerBarGradientColorR", 0 },
    sparseV2Fields[587],
    { "powerGradientDirDown", false },
    { "powerGradientDirLeft", false },
    sparseV2Fields[588],
    { "powerGradientDirUp", false },
    sparseV2Fields[589],
    sparseV2Fields[590],
    { "powerLossColorB", 1 },
    { "powerLossColorG", 0.90000000000000002 },
    { "powerLossColorR", 0.69999999999999996 },
    sparseV2Fields[591],
    { "quickSetupClassBarOffered", true },
    sparseV2Fields[592],
    sparseV2Fields[593],
    sparseV2Fields[594],
    sparseV2Fields[595],
    sparseV2Fields[596],
    sparseV2Fields[597],
    sparseV2Fields[598],
    sparseV2Fields[599],
    sparseV2Fields[600],
    sparseV2Fields[601],
    sparseV2Fields[602],
    sparseV2Fields[603],
    sparseV2Fields[604],
    { "showArenaCastTargetName", false },
    sparseV2Fields[605],
    sparseV2Fields[606],
    sparseV2Fields[607],
    { "showBossCastTargetName", false },
    sparseV2Fields[608],
    sparseV2Fields[609],
    sparseV2Fields[610],
    { "showGCDBar", false },
    sparseV2Fields[611],
    sparseV2Fields[612],
    sparseV2Fields[613],
    sparseV2Fields[614],
    sparseV2Fields[615],
    { "showLevel", false },
    sparseV2Fields[616],
    sparseV2Fields[617],
    sparseV2Fields[618],
    sparseV2Fields[619],
    sparseV2Fields[620],
    sparseV2Fields[621],
    { "showTotalAbsorbAmount", false },
    sparseV2Fields[622],
    { "slashMenuScale", 0.80000000000000004 },
    sparseV2Fields[623],
    { "targetCastbarTestMode", false },
    sparseV2Fields[630],
    sparseV2Fields[631],
    { "tooltipShowAuraCasterNames", false },
    { "tooltipShowAuraSpellIDs", false },
    sparseV2Fields[632],
    sparseV2Fields[633],
    sparseV2Fields[634],
    sparseV2Fields[636],
    { "unitPreviewGuidesEnabled", false },
    sparseV2Fields[637],
    sparseV2Fields[638],
    sparseV2Fields[639],
    sparseV2Fields[640],
    sparseV2Fields[641],
    sparseV2Fields[642],
    { "useCustomFontColor", false },
    { "buffs", false },
    sparseV2Fields[643],
    sparseV2Fields[644],
    sparseV2Fields[645],
    sparseV2Fields[646],
    { "spells", {} },
    sparseV2Fields[647],
    { "blacklistCats", {} },
    sparseV2Fields[648],
    sparseV2Fields[649],
    { "cooldownX", 0 },
    { "cooldownY", 0 },
    sparseV2Fields[650],
    sparseV2Fields[651],
    sparseV2Fields[652],
    sparseV2Fields[653],
    sparseV2Fields[654],
    sparseV2Fields[655],
    sparseV2Fields[658],
    sparseV2Fields[659],
    { "sortReverse", false },
    { "spacing", 0 },
    sparseV2Fields[660],
    sparseV2Fields[661],
    { "stackX", 0 },
    { "stackY", 0 },
    sparseV2Fields[663],
    sparseV2Fields[664],
    sparseV2Fields[665],
    sparseV2Fields[666],
    sparseV2Fields[667],
    sparseV2Fields[668],
    sparseV2Fields[669],
    sparseV2Fields[670],
    sparseV2Fields[671],
    sparseV2Fields[672],
    sparseV2Fields[673],
    sparseV2Fields[674],
    sparseV2Fields[675],
    sparseV2Fields[676],
    { "showStacks", false },
    sparseV2Fields[677],
    sparseV2Fields[678],
    sparseV2Fields[679],
    sparseV2Fields[680],
    { "blizzardContainerX", 0 },
    { "blizzardContainerY", 0 },
    { "blizzardDispelBorder", false },
    sparseV2Fields[681],
    sparseV2Fields[682],
    sparseV2Fields[683],
    sparseV2Fields[684],
    { "dynamicScale", false },
    sparseV2Fields[686],
    sparseV2Fields[687],
    sparseV2Fields[688],
    sparseV2Fields[689],
    sparseV2Fields[690],
    { "showNumbers", false },
    sparseV2Fields[691],
    sparseV2Fields[692],
    { "y", 0 },
    sparseV2Fields[693],
    sparseV2Fields[695],
    { "specs", {} },
    { "aggroB", 0 },
    sparseV2Fields[697],
    { "aggroG", 0 },
    sparseV2Fields[698],
    sparseV2Fields[699],
    sparseV2Fields[700],
    sparseV2Fields[701],
    { "assistIconCustomIcon", "" },
    sparseV2Fields[702],
    sparseV2Fields[703],
    sparseV2Fields[704],
    sparseV2Fields[705],
    { "assistIconY", 0 },
    { "autoScaleAurasOnResize", false },
    { "autoScaleIndicatorsOnResize", false },
    { "autoScaleTrackedOnResize", false },
    sparseV2Fields[706],
    sparseV2Fields[707],
    sparseV2Fields[708],
    sparseV2Fields[709],
    sparseV2Fields[710],
    { "borderB", 0 },
    sparseV2Fields[711],
    { "borderG", 0 },
    { "borderR", 0 },
    sparseV2Fields[712],
    sparseV2Fields[713],
    sparseV2Fields[714],
    { "buffCoverageCombat", false },
    { "buffCoverageEnabled", false },
    { "buffCoverageGlow", false },
    sparseV2Fields[715],
    sparseV2Fields[716],
    sparseV2Fields[717],
    { "buffCoverageSpirit", false },
    sparseV2Fields[718],
    { "buffCoverageThorns", false },
    sparseV2Fields[719],
    sparseV2Fields[720],
    { "buffCoverageX", 0 },
    sparseV2Fields[721],
    { "centerSolo", false },
    { "ciAggroColorB", 0 },
    sparseV2Fields[722],
    sparseV2Fields[723],
    sparseV2Fields[724],
    sparseV2Fields[725],
    sparseV2Fields[726],
    sparseV2Fields[727],
    sparseV2Fields[728],
    sparseV2Fields[729],
    sparseV2Fields[730],
    sparseV2Fields[731],
    sparseV2Fields[732],
    sparseV2Fields[733],
    sparseV2Fields[734],
    sparseV2Fields[735],
    { "collapseEmptyGroups", false },
    sparseV2Fields[736],
    sparseV2Fields[737],
    { "deadBgEnabled", false },
    sparseV2Fields[738],
    sparseV2Fields[739],
    sparseV2Fields[740],
    sparseV2Fields[741],
    sparseV2Fields[742],
    sparseV2Fields[743],
    sparseV2Fields[744],
    sparseV2Fields[745],
    { "debuffStripeEnabled", false },
    sparseV2Fields[746],
    sparseV2Fields[747],
    sparseV2Fields[748],
    { "detachedPowerBarOffsetX", 0 },
    sparseV2Fields[749],
    { "detachedPowerBarTextOnBar", false },
    { "detachedPowerBarWidth", 0 },
    sparseV2Fields[750],
    sparseV2Fields[751],
    { "dispelOverlayEnabled", false },
    { "dispelOverlayLayer", 0 },
    sparseV2Fields[752],
    sparseV2Fields[753],
    sparseV2Fields[754],
    sparseV2Fields[755],
    sparseV2Fields[756],
    sparseV2Fields[757],
    { "dispelSymbolEnabled", false },
    sparseV2Fields[758],
    sparseV2Fields[759],
    sparseV2Fields[760],
    sparseV2Fields[761],
    sparseV2Fields[762],
    sparseV2Fields[763],
    sparseV2Fields[764],
    { "dispelSymbolTrigger", "BY_ME" },
    { "dispelSymbolX", 0 },
    { "dispelSymbolY", 0 },
    { "excludeHiddenGroups", false },
    { "fontOverride", false },
    sparseV2Fields[765],
    { "friendlyBossEnabled", false },
    sparseV2Fields[766],
    sparseV2Fields[767],
    sparseV2Fields[768],
    sparseV2Fields[769],
    sparseV2Fields[770],
    sparseV2Fields[771],
    sparseV2Fields[772],
    sparseV2Fields[773],
    { "groupBorderEnabled", false },
    sparseV2Fields[774],
    sparseV2Fields[775],
    sparseV2Fields[776],
    sparseV2Fields[777],
    sparseV2Fields[778],
    sparseV2Fields[779],
    sparseV2Fields[780],
    sparseV2Fields[781],
    sparseV2Fields[782],
    sparseV2Fields[783],
    sparseV2Fields[784],
    { "healerManaEnabled", false },
    sparseV2Fields[786],
    sparseV2Fields[787],
    sparseV2Fields[788],
    sparseV2Fields[789],
    sparseV2Fields[790],
    sparseV2Fields[791],
    sparseV2Fields[792],
    sparseV2Fields[793],
    sparseV2Fields[794],
    sparseV2Fields[795],
    sparseV2Fields[796],
    sparseV2Fields[797],
    sparseV2Fields[798],
    sparseV2Fields[799],
    { "healthFadeEnabled", false },
    sparseV2Fields[800],
    sparseV2Fields[801],
    sparseV2Fields[802],
    { "hideInHousing", false },
    { "hideMythicGroupsFiveToEight", false },
    { "hideNameOnDeadOffline", false },
    { "hideOfflineDelay", 0 },
    { "hideOfflineEnabled", false },
    { "hideOfflineInCombat", false },
    sparseV2Fields[803],
    sparseV2Fields[804],
    sparseV2Fields[805],
    sparseV2Fields[806],
    { "hlFocusOffset", 0 },
    sparseV2Fields[807],
    sparseV2Fields[808],
    sparseV2Fields[809],
    { "hpOffsetY", 0 },
    sparseV2Fields[810],
    { "layoutTiersEnabled", false },
    sparseV2Fields[811],
    sparseV2Fields[812],
    { "leaderIconCustomIcon", "" },
    sparseV2Fields[813],
    sparseV2Fields[814],
    sparseV2Fields[815],
    { "leaderIconX", 0 },
    { "leaderIconY", 0 },
    { "levelText", false },
    sparseV2Fields[816],
    sparseV2Fields[817],
    sparseV2Fields[818],
    sparseV2Fields[819],
    sparseV2Fields[820],
    sparseV2Fields[821],
    sparseV2Fields[822],
    sparseV2Fields[823],
    sparseV2Fields[824],
    sparseV2Fields[825],
    { "nameBarEnabled", false },
    sparseV2Fields[826],
    sparseV2Fields[827],
    sparseV2Fields[828],
    sparseV2Fields[829],
    sparseV2Fields[830],
    sparseV2Fields[831],
    sparseV2Fields[832],
    sparseV2Fields[833],
    { "nameMaxChars", 0 },
    { "nameNoEllipsis", false },
    sparseV2Fields[834],
    { "nameOffsetY", 0 },
    sparseV2Fields[835],
    { "offlineFadeEnabled", false },
    sparseV2Fields[836],
    sparseV2Fields[837],
    sparseV2Fields[838],
    { "petsEnabled", false },
    sparseV2Fields[839],
    sparseV2Fields[840],
    sparseV2Fields[841],
    sparseV2Fields[842],
    sparseV2Fields[843],
    sparseV2Fields[844],
    sparseV2Fields[845],
    sparseV2Fields[846],
    { "phaseIconCustomIcon", "" },
    sparseV2Fields[847],
    sparseV2Fields[848],
    sparseV2Fields[849],
    { "phaseX", 0 },
    { "phaseY", 0 },
    { "playerFirstInRole", false },
    sparseV2Fields[850],
    { "powerBarDetached", false },
    sparseV2Fields[853],
    sparseV2Fields[854],
    sparseV2Fields[855],
    { "powerOffsetX", 0 },
    { "powerOffsetY", 0 },
    { "powerShowDamager", false },
    sparseV2Fields[856],
    sparseV2Fields[857],
    sparseV2Fields[858],
    sparseV2Fields[859],
    sparseV2Fields[860],
    { "preserveRaidGroups", false },
    sparseV2Fields[861],
    sparseV2Fields[862],
    { "pvpIconCustomIcon", "" },
    sparseV2Fields[863],
    sparseV2Fields[864],
    sparseV2Fields[865],
    sparseV2Fields[866],
    { "pvpIconY", 0 },
    sparseV2Fields[867],
    sparseV2Fields[873],
    sparseV2Fields[874],
    { "readyCheckIconCustomIcon", "" },
    sparseV2Fields[875],
    sparseV2Fields[876],
    sparseV2Fields[877],
    { "readyCheckX", 0 },
    { "readyCheckY", 0 },
    sparseV2Fields[878],
    sparseV2Fields[879],
    { "resurrectIconCustomIcon", "" },
    sparseV2Fields[880],
    sparseV2Fields[881],
    sparseV2Fields[882],
    { "resurrectX", 0 },
    { "resurrectY", 0 },
    { "reverseFill", false },
    sparseV2Fields[883],
    sparseV2Fields[884],
    { "roleIconCustomIcon", "" },
    sparseV2Fields[885],
    sparseV2Fields[886],
    sparseV2Fields[887],
    sparseV2Fields[888],
    sparseV2Fields[889],
    sparseV2Fields[890],
    sparseV2Fields[891],
    { "roleIconY", 0 },
    sparseV2Fields[892],
    sparseV2Fields[893],
    sparseV2Fields[894],
    { "showSolo", false },
    { "smallRaidAsParty", false },
    { "sortAlphabeticalWithinRole", false },
    { "sortByRole", false },
    { "sortClassPriority", false },
    sparseV2Fields[896],
    { "sortRolesAcrossRaid", false },
    { "statusAFKOffsetX", 0 },
    { "statusAFKOffsetY", 0 },
    sparseV2Fields[897],
    sparseV2Fields[898],
    sparseV2Fields[899],
    sparseV2Fields[900],
    { "statusAFKTimerOffsetX", 0 },
    sparseV2Fields[901],
    { "statusAFKTimerText", false },
    sparseV2Fields[902],
    sparseV2Fields[903],
    sparseV2Fields[904],
    { "statusDNDOffsetX", 0 },
    { "statusDNDOffsetY", 0 },
    sparseV2Fields[905],
    sparseV2Fields[906],
    sparseV2Fields[907],
    sparseV2Fields[908],
    { "statusGhostOffsetX", 0 },
    { "statusGhostOffsetY", 0 },
    sparseV2Fields[909],
    sparseV2Fields[910],
    sparseV2Fields[911],
    sparseV2Fields[912],
    { "statusOffsetX", 0 },
    { "statusOffsetY", 0 },
    sparseV2Fields[913],
    sparseV2Fields[914],
    sparseV2Fields[915],
    sparseV2Fields[916],
    sparseV2Fields[917],
    sparseV2Fields[918],
    { "summonIconCustomIcon", "" },
    sparseV2Fields[919],
    sparseV2Fields[920],
    sparseV2Fields[921],
    { "summonX", 0 },
    { "summonY", 0 },
    sparseV2Fields[922],
    sparseV2Fields[923],
    sparseV2Fields[924],
    sparseV2Fields[925],
    sparseV2Fields[926],
    { "targetsEnabled", false },
    sparseV2Fields[927],
    { "targetsIncludePlayer", false },
    sparseV2Fields[928],
    sparseV2Fields[929],
    sparseV2Fields[930],
    sparseV2Fields[931],
    sparseV2Fields[932],
    sparseV2Fields[933],
    sparseV2Fields[934],
    { "threatText", false },
    { "threatTextAnchor", "TOP" },
    { "threatTextBackground", false },
    { "threatTextColorCurve", true },
    { "threatTextLayer", 7 },
    { "threatTextSize", 9 },
    { "threatTextX", 0 },
    { "threatTextY", -1 },
    sparseV2Fields[935],
    { "tier10Height", 0 },
    { "tier10Position", false },
    { "tier10Width", 0 },
    { "tier10X", 0 },
    { "tier10Y", 0 },
    sparseV2Fields[936],
    { "tier20Height", 0 },
    { "tier20Position", false },
    { "tier20Width", 0 },
    { "tier20X", 0 },
    { "tier20Y", 0 },
    sparseV2Fields[937],
    { "tier25Height", 0 },
    { "tier25Position", false },
    { "tier25Width", 0 },
    { "tier25X", 0 },
    { "tier25Y", 0 },
    sparseV2Fields[938],
    { "tier40Height", 0 },
    { "tier40Position", false },
    { "tier40Width", 0 },
    { "tier40X", 0 },
    { "tier40Y", 0 },
    sparseV2Fields[939],
    sparseV2Fields[940],
    { "useMidnightIcons", false },
    sparseV2Fields[941],
    sparseV2Fields[942],
    sparseV2Fields[943],
    sparseV2Fields[944],
    sparseV2Fields[945],
    sparseV2Fields[946],
    sparseV2Fields[947],
    { "height", 55 },
    sparseV2Fields[948],
    sparseV2Fields[949],
    { "nameOffsetY", 7 },
    { "offsetX", -476 },
    { "offsetY", 129 },
    { "portraitCastSpellIcon", false },
    sparseV2Fields[950],
    sparseV2Fields[951],
    { "roleIcon", false },
    { "roleIconShowDPS", false },
    { "roleIconShowHealer", false },
    { "roleIconShowTank", false },
    sparseV2Fields[952],
    { "showGroupNumber", false },
    { "threatText", true },
    { "threatTextBackground", true },
    { "width", 165 },
    sparseV2Fields[953],
    sparseV2Fields[954],
    { "attachOffset", 0 },
    sparseV2Fields[955],
    { "height", 0 },
    sparseV2Fields[956],
    sparseV2Fields[957],
    { "offsetY", 0 },
    sparseV2Fields[958],
    { "width", 0 },
    { "hpOffsetY", -2 },
    { "petHappinessIndicatorAnchor", "RIGHT" },
    { "petHappinessIndicatorLayer", 7 },
    { "petHappinessIndicatorOffsetX", -7 },
    { "petHappinessIndicatorOffsetY", -4 },
    { "petHappinessIndicatorSize", 24 },
    { "showPetHappinessIndicator", true },
    sparseV2Fields[959],
    sparseV2Fields[960],
    sparseV2Fields[961],
    sparseV2Fields[962],
    sparseV2Fields[963],
    { "channelTickPosPct", {} },
    { "channelTickUseCustom", false },
    { "combatStateIndicatorOffsetX", 0 },
    { "combatStateIndicatorOffsetY", 3 },
    sparseV2Fields[964],
    sparseV2Fields[965],
    sparseV2Fields[966],
    { "hpOffsetX", -9 },
    { "hpOffsetY", -7 },
    { "incomingResIndicatorOffsetX", 0 },
    { "incomingResIndicatorOffsetY", 0 },
    { "nameOffsetX", 6 },
    { "nameOffsetY", -11 },
    { "nameTextMouseoverFadeIn", 0.34999999403953552 },
    { "nameTextMouseoverFadeOut", 0.34999999403953552 },
    { "offsetX", -326 },
    sparseV2Fields[967],
    sparseV2Fields[968],
    { "portraitShape", "BLIZZARD" },
    { "powerOffsetX", -13 },
    { "powerOffsetY", 4 },
    { "showLevelIndicator", true },
    { "unitDispelOverlayAlpha", 0.5 },
    { "unitDispelOverlayEnabled", true },
    { "unitDispelOverlayTrigger", "DISPEL_TYPE" },
    { "unitDispelSymbolEnabled", true },
    { "unitDispelSymbolSize", 23 },
    { "unitDispelSymbolX", -50 },
    { "unitDispelSymbolY", -8 },
    sparseV2Fields[969],
    { "offsetX", 326 },
    { "eliteIconOffsetX", 11 },
    { "eliteIconOffsetY", 14 },
    { "hpOffsetX", 2 },
    { "hpOffsetY", -13 },
    { "nameFontSize", 11 },
    { "nameOffsetX", 0 },
    { "offsetX", 546 },
    { "showToTInTargetName", false },
    sparseV2Fields[970],
    { "totInlineCustomSeparator", "" },
    sparseV2Fields[971],
    { "width", 135 },
}
local sparseV3Runs = {
    { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, },
    { 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, },
    { 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, },
    { 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, },
    { 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, },
    { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, },
    { 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, },
    { 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, },
    { 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, },
    { 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, },
    { 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, },
    { 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, },
    { 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, },
    { 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, },
    { 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, },
    { 301, 302, 303, 304, 305, 306, 307, },
    { 308, 309, 310, 311, 19, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, },
    { 322, 323, 324, 325, },
    { 326, 327, 328, 329, 330, },
    { 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, },
    { 344, 345, 346, 19, 347, 348, 349, 350, 351, 352, 353, 354, 355, 328, },
    { 356, },
    { 357, 358, },
    { 308, 309, 311, 19, 312, 313, 315, 316, 317, 318, 319, 320, 321, },
    { 310, 311, 19, 312, 315, 316, 318, 319, 320, 321, },
    { 19, 314, },
    { 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, },
    { 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, },
    { 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, },
    { 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, },
    { 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, },
    { 443, 444, 445, 446, },
    { 359, 360, 361, 362, 363, 364, 447, 448, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, },
    { 379, 380, 383, 384, 385, 386, 387, 388, 389, 390, },
    { 359, 360, 361, 362, 363, 367, 368, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 383, 384, 386, },
    { 387, 388, 389, 390, },
    { 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 429, 430, 431, 432, 433, },
    { 434, 435, 436, 438, 440, 441, },
    { 359, 360, 361, 362, 363, 367, 368, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 449, 383, 384, },
    { 386, 387, 388, 389, 390, },
    { 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 428, 429, 430, 431, 432, },
    { 433, 434, 435, 436, 438, 440, 441, },
    { 450, 451, 452, 453, },
    { 454, 455, 456, 457, },
    { 454, 455, 456, 325, },
    { 458, 459, 460, 461, 462, },
    { 308, 309, 311, 312, 313, 315, 316, 317, 318, 319, 320, 321, },
    { 310, 311, 312, 315, 316, 318, 319, 320, 321, },
    { 463, 464, 359, 397, 398, 399, 400, 401, 465, 466, 467, 402, 403, 367, 368, 409, 411, 412, 468, 414, },
    { 469, 470, 471, 472, 473, 474, 375, 421, 422, 423, 424, 425, 475, 476, 477, 426, 427, 383, 384, 434, },
    { 435, 478, 437, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 440, 337, 491, 441, 492, },
    { 493, 494, 495, 340, 496, 497, 498, 499, 442, },
    { 19, 500, 501, 502, 503, 504, 505, },
    { 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, },
    { 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, },
    { 17, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, },
    { 565, 566, 567, 568, 569, 570, 571, 572, 573, 113, 116, 574, 575, 576, 577, 578, 579, 580, 581, 582, },
    { 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, },
    { 603, 604, 605, 606, 607, },
    { 1, 2, 3, 4, 5, 6, 608, 609, 610, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, },
    { 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 611, 612, 613, 39, },
    { 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 614, 52, 53, 54, 55, 56, 57, 58, },
    { 615, 616, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, },
    { 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, },
    { 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 617, 618, 113, 114, 115, 116, 117, 118, },
    { 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 142, 143, },
    { 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 619, 159, 620, 162, 164, 165, },
    { 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, },
    { 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, },
    { 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, },
    { 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, },
    { 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, },
    { 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 287, 288, 289, 290, },
    { 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, },
    { 1, 2, 3, 4, 5, 6, 608, 609, 610, 10, 11, 12, 621, 622, 15, 16, 17, 18, 19, 20, },
    { 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 611, 623, 624, 39, 40, },
    { 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 625, 52, 53, 54, 55, 56, 57, 58, 626, },
    { 627, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, },
    { 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, },
    { 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 617, 618, 113, 114, 115, 116, 117, 118, 119, },
    { 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 628, },
    { 629, 141, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 154, 155, 156, 157, 619, 159, 160, 630, },
    { 162, 164, 631, 632, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, },
    { 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, },
    { 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, },
    { 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, },
    { 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, },
    { 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 287, },
    { 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, },
    { 1, 2, 3, 4, 5, 6, 7, 8, 610, 10, 11, 12, 13, 14, 15, 16, 17, 18, 633, 20, },
    { 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 612, 634, 39, 40, },
    { 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 635, 636, },
    { 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 99, 100, 101, },
    { 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 637, 116, 117, 118, 119, 120, },
    { 141, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 156, 157, 619, 638, 160, 630, 162, 164, 166, },
    { 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, },
    { 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, },
    { 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, },
    { 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, },
    { 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, },
    { 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 302, 305, 306, 307, },
    { 639, 640, 641, },
    { 642, 643, 644, },
    { 454, 640, 456, },
    { 639, 455, 456, },
    { 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, },
    { 665, 666, 667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, },
    { 678, 679, },
    { 639, 680, 456, },
    { 681, },
    { 682, 683, },
    { 684, },
    { 685, 686, },
    { 687, 688, 689, },
    { 690, 691, 689, },
    { 692, 693, 694, },
    { 695, 696, 697, 698, },
    { 1, 2, 3, 4, 5, 6, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, },
    { 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, },
    { 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, },
    { 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767, 768, 769, 770, 771, 772, },
    { 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785, 786, 787, 788, 789, 790, 791, 792, },
    { 793, 794, 795, 796, 797, 798, 799, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, },
    { 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831, 832, },
    { 833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847, 848, 849, 850, 851, 852, },
    { 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863, 864, 865, 866, 867, 868, 869, 870, 871, 872, },
    { 873, 874, 875, 876, 877, 878, 879, 880, 881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 892, },
    { 893, 894, 895, 896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911, 912, },
    { 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927, 928, 929, 930, 931, 932, },
    { 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943, 944, 18, 945, 946, 947, 948, 949, 950, 951, },
    { 952, 953, 954, 955, 956, 957, 958, 959, 960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, },
    { 972, 973, 974, 975, 976, 977, 978, 979, 980, 981, 982, 983, 984, 985, 986, 987, 988, 989, 990, 991, },
    { 992, 993, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 994, 995, 996, 997, 998, },
    { 999, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 44, 51, 1016, },
    { 1017, 1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1036, },
    { 1037, 1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, },
    { 63, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 64, 65, 66, 67, 68, 69, 72, 73, 74, 75, 76, },
    { 77, 78, 79, 80, 82, 83, 92, 93, 95, 97, 99, 100, 101, 102, 103, 104, 106, 107, 108, 109, },
    { 110, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 129, 136, 1078, 137, 138, 139, },
    { 140, 141, 1079, 142, 143, 144, 145, 149, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, },
    { 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 630, },
    { 162, 1111, 1112, 1113, 1114, 1115, 1116, 1117, 631, 1118, 170, 171, 172, 173, 174, 175, 176, 1119, 1120, 1121, },
    { 1122, 1123, 1124, 1125, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, },
    { 303, 304, 1126, 1127, 1128, 1129, 1130, 1131, 1132, 1133, 1134, },
    { 1135, 1136, 1137, 1138, 1139, },
    { 314, 1140, },
    { 1141, 1142, 1143, 469, 1144, 470, 1145, 1146, 479, 480, 481, 482, 19, 1147, 1148, 1149, 487, 1150, 1151, 1152, },
    { 336, 337, 492, 338, 495, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 328, 1161, 1162, 1163, },
    { 1164, 1142, 1143, 469, 1144, 470, 1145, 1146, 1165, 479, 480, 481, 482, 19, 1166, 1167, 1149, 487, 1168, 1151, },
    { 1152, 336, 337, 492, 338, 495, 1169, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 328, 1170, 1171, },
    { 1164, 1172, 1142, 1143, 469, 1144, 470, 1145, 1146, 479, 480, 481, 482, 19, 1173, 1167, 1149, 487, 1174, 1151, },
    { 1152, 336, 337, 492, 1175, 495, 1176, 1154, 1155, 1177, 1157, 1158, 1159, 1160, 328, 1178, 1171, },
    { 1179, 1180, 1181, 1182, 1183, 1184, 1185, 1186, 1187, 19, 487, 1188, 495, },
    { 1189, 1190, 633, 1191, 1151, 1192, 1193, 1194, 1177, 1195, 1196, },
    { 1197, 1143, 469, 1144, 470, 1145, 1146, 479, 480, 481, 482, 337, 491, 492, 338, 495, 1157, 1158, 1159, 1160, },
    { 633, 1149, 487, 347, 1198, 1199, 328, },
    { 1, 2, 3, 4, 5, 1200, 1201, 1202, 1203, 1204, 7, 8, 1205, 1206, 1207, 1208, 1209, 1210, 1211, 1212, },
    { 1213, 1214, 1215, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228, 1229, 1230, 1231, 1232, },
    { 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241, 10, 1242, 1243, 1244, 1245, 1246, 1247, 1248, 1249, 1250, 1251, },
    { 1252, 1253, 1254, 1255, 1256, 1257, 1258, 1259, 1260, 1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, },
    { 1272, 1273, 1274, 1275, 1276, 1277, 1278, 1279, 1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289, 1290, 1291, },
    { 1292, 1293, 1294, 1295, 1296, 1297, 17, 633, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305, 1306, 1307, 1308, 1309, },
    { 1310, 1311, 1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321, 20, 21, 22, 23, 24, 25, 26, 27, },
    { 28, 29, 30, 31, 32, 1322, 1323, 1324, 1325, 1326, 1327, 1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, },
    { 1337, 1338, 33, 1339, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 35, 36, 1353, },
    { 1354, 612, 1355, 39, 40, 42, 43, 48, 49, 50, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, },
    { 1366, 1367, 1368, 1369, 1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385, },
    { 1386, 1387, 1388, 1389, 55, 1390, 1391, 1392, 1393, 61, 62, 63, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, },
    { 1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, 1410, 1411, 111, 112, 114, 115, 1412, 1413, 117, 1414, 1415, 1416, },
    { 1417, 1418, 1419, 1420, 121, 1421, 123, 124, 1422, 125, 126, 127, 128, 1423, 134, 135, 1424, 1425, 1426, 1427, },
    { 1428, 1429, 1430, 1431, 1432, 1433, 146, 149, 150, 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, },
    { 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455, 1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, },
    { 157, 504, 619, 160, 1465, 1466, 164, 1467, 1468, 1469, 1470, 1471, 1177, 1472, 1473, 1474, 1475, 1476, 1477, 1478, },
    { 1479, 1480, 1481, 1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, },
    { 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, 1515, 1516, 1517, 1518, },
    { 1519, 1520, 1521, 170, 171, 172, 173, 174, 175, 176, 279, 1522, 1523, 280, 1524, 1525, 1526, 1527, 1528, 1529, },
    { 1530, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545, 1546, 1547, 1548, 1549, },
    { 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, },
    { 1142, 1143, 469, 1144, 470, 1145, 1146, 479, 480, 481, 482, 19, 1147, 1149, 487, 1150, 1151, 1152, 336, 337, },
    { 492, 338, 495, 1561, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 328, 1161, },
    { 1164, 1142, 1143, 469, 1144, 470, 1145, 1146, 479, 480, 481, 482, 19, 1166, 1167, 1149, 487, 1168, 336, 337, },
    { 492, 338, 495, 1562, 1154, 1155, 1157, 1563, 1159, 1160, 328, 1564, },
    { 1152, 336, 337, 492, 1175, 495, 1169, 1154, 1155, 1177, 1157, 1565, 1159, 1160, 328, 1178, },
    { 1179, 1180, 1181, 1182, 1183, 1566, 1185, 1186, 1187, 19, 487, 1188, 495, },
    { 1189, 1190, 633, 1191, 1151, 1192, 1193, 1153, 1177, 1195, 1196, },
    { 1292, 1293, 1294, 1295, 1296, 1297, 17, 19, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305, 1306, 1307, 1308, 1309, },
    { 1337, 1338, 33, 1567, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 35, 36, 1354, },
    { 39, 40, 42, 43, 48, 49, 50, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, },
    { 1369, 1370, 1371, 1372, 1568, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1569, 1386, 1387, 1570, },
    { 55, 1390, 1391, 1571, 1572, 61, 62, 63, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, },
    { 1406, 1407, 1408, 1409, 1410, 1411, 64, 65, 66, 67, 68, 69, 72, 73, 74, 75, 76, 77, 78, 79, },
    { 1573, 80, 81, 82, 83, 92, 93, 95, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, },
    { 109, 110, 111, 112, 114, 115, 1412, 1413, 117, 1414, 1574, 1416, 1417, 1419, 1420, 121, 1421, 123, 124, 1422, },
    { 125, 126, 127, 128, 1423, 134, 135, 1424, 1425, 1426, 1427, 1428, 1575, 1430, 1431, 1432, 1433, 146, 149, 150, },
    { 1434, 1435, 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1576, 1452, 1453, },
    { 1454, 1577, 1578, 1579, 1580, 1459, 1460, 1461, 1462, 1581, 1464, 157, 504, 619, 160, 1465, 1466, 164, 1467, 1468, },
    { 1469, 1470, 1471, 1177, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481, 1482, 1483, 1484, 1485, 1486, 1487, },
    { 1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, },
    { 1508, 1509, 1510, 1511, 1512, 1513, 1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 170, 171, 172, 173, 174, 175, },
    { 176, 1522, 1523, 280, 1582, 1526, 1583, 1528, 1529, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, },
    { 1542, 1543, 1544, 1545, 1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1584, },
    { 1585, 1586, 1587, 1588, 633, 1321, 1589, 1590, 1591, 1592, 1411, 1593, 340, 1557, 1594, },
    { 492, 338, 495, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 328, 1161, },
    { 492, 338, 495, 1169, 1154, 1155, 1157, 1158, 1159, 1160, 328, 1170, },
    { 1152, 336, 337, 492, 1175, 495, 1176, 1154, 1155, 1177, 1157, 1158, 1159, 1160, 328, 1178, },
    { 1337, 1338, 33, 1340, 1341, 1342, 1343, 1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 35, 36, 1354, 39, },
    { 40, 42, 43, 48, 49, 50, 1356, 1357, 1358, 1359, 1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369, },
    { 1370, 1371, 1372, 1373, 1374, 1375, 1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1569, 1386, 1387, 55, 1390, },
    { 1391, 61, 62, 63, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, 1406, 1407, 1408, 1409, },
    { 1410, 111, 112, 114, 115, 1412, 1413, 117, 1414, 1574, 1416, 1417, 1419, 1420, 121, 1421, 123, 124, 1422, 125, },
    { 126, 127, 128, 1423, 134, 135, 1425, 1426, 1427, 1428, 1575, 1430, 1431, 1432, 1433, 146, 149, 150, 1434, 1435, },
    { 1436, 1437, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1576, 1452, 1453, 1454, 1577, },
    { 1578, 1579, 1580, 1459, 1460, 1461, 1462, 1581, 1464, 157, 504, 619, 160, 1465, 1466, 164, 1467, 1468, 1469, 1470, },
    { 1471, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481, 1482, 1483, 1484, 1485, 1486, 1487, 1488, 1489, 1490, },
    { 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1507, 1508, 1509, 1510, },
    { 1511, 1512, 1513, 1514, 1515, 1516, 1517, 1518, 1519, 1520, 1521, 170, 171, 172, 173, 174, 175, 176, 1522, 1523, },
    { 280, 1525, 1526, 1527, 1528, 1529, 1531, 1532, 1533, 1534, 1535, 1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, },
    { 1545, 1546, 1547, 1548, 1549, 1550, 1551, 1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, },
    { 1, 2, 3, 4, 5, 6, 7, 8, 610, 10, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, },
    { 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 612, 1595, 39, 40, 41, 42, 43, 44, 45, 46, },
    { 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 61, 62, 63, 1596, 1597, 1598, 1599, 1600, },
    { 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, },
    { 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 99, 100, 101, 102, 103, 104, },
    { 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, },
    { 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 142, 143, 144, 145, 146, 149, 150, 151, },
    { 153, 156, 157, 1601, 158, 159, 620, 162, 164, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, },
    { 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, },
    { 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, },
    { 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, },
    { 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, },
    { 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, },
    { 277, 278, 279, 280, 281, 302, 305, 306, 1602, },
    { 7, 8, 17, 633, 33, 34, 35, 1603, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, },
    { 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 1604, 1605, 61, 62, 64, 65, 66, 67, 68, },
    { 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, },
    { 89, 90, 91, 92, 93, 94, 95, 96, 97, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, },
    { 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, },
    { 130, 131, 132, 133, 134, 135, 136, 142, 143, 144, 145, 146, 149, 150, 151, 153, 156, 157, 619, 638, },
    { 160, 162, 164, 166, 167, 168, 169, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, },
    { 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, },
    { 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, },
    { 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, },
    { 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, },
    { 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 305, 306, 307, },
    { 1606, 1607, 1608, },
    { 1, 2, 3, 4, 5, 6, 608, 609, 610, 10, 1609, 1610, 1611, 1612, 17, 18, 19, 20, 21, 22, },
    { 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 1613, 35, 611, 1614, 1615, 39, 40, 41, 42, },
    { 43, 44, 45, 46, 47, 48, 49, 50, 51, 1616, 1617, 625, 1618, 1619, 54, 55, 56, 1620, 1621, 1622, },
    { 1623, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, },
    { 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 1624, 99, },
    { 100, 101, 102, 103, 104, 105, 1625, 107, 108, 109, 110, 617, 618, 113, 114, 115, 116, 117, 1068, 1626, },
    { 1627, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, },
    { 140, 141, 142, 143, 144, 145, 151, 153, 154, 155, 1628, 157, 158, 159, 620, 630, 162, 164, 166, 167, },
    { 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, },
    { 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, },
    { 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, },
    { 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, },
    { 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, },
    { 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 1629, 1630, 289, 290, 1631, 292, },
    { 293, 1632, 295, 296, 297, 1633, 299, 300, 301, 302, 1634, 1635, 305, 306, 1636, },
    { 1, 2, 3, 4, 5, 6, 608, 609, 610, 10, 1609, 1610, 1611, 1612, 11, 12, 13, 14, 15, 16, },
    { 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 1613, 35, 611, },
    { 1614, 1615, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 1616, 1617, 625, 1618, 1619, },
    { 54, 55, 56, 1620, 1621, 1637, 1623, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, },
    { 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, },
    { 94, 95, 96, 97, 1624, 99, 100, 101, 102, 103, 104, 105, 1625, 107, 108, 109, 110, 617, 618, 113, },
    { 114, 115, 116, 117, 1068, 1626, 1627, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, },
    { 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 154, 155, },
    { 1628, 157, 158, 159, 620, 630, 162, 164, 631, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, },
    { 277, 278, 279, 280, 281, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, },
    { 302, 303, 304, 305, 306, 1636, },
    { 1, 2, 3, 4, 5, 6, 7, 8, 610, 10, 11, 12, 1638, 1639, 15, 16, 17, 18, 19, 20, },
    { 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 1640, 1641, 39, 40, },
    { 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 1642, 1643, 53, 54, 55, 56, 57, 58, 1644, },
    { 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 99, 100, },
    { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 637, 116, 117, 118, 119, },
    { 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, },
    { 140, 141, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 156, 157, 619, 638, 160, 630, 162, 1645, },
    { 164, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, },
    { 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, },
    { 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, },
    { 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, },
    { 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, },
    { 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 1646, 1647, 1648, },
    { 302, 305, 306, 1649, },
}
local sparseV3Owners = {
    { path = {[1]="arena"}, lists = {}, runs = {
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    } },
    { path = {[1]="auras3",[2]="customContainers",[3]="perUnit",[4]="player",[5]="items",[6]=4,[7]="filters"}, lists = {[6]=true}, runs = {
        17,
    } },
    { path = {[1]="auras3",[2]="customContainers",[3]="perUnit",[4]="player",[5]="items",[6]=4,[7]="frame",[8]="color"}, lists = {[6]=true,[9]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="customContainers",[3]="perUnit",[4]="player",[5]="items",[6]=4,[7]="frame"}, lists = {[6]=true}, runs = {
        19,
    } },
    { path = {[1]="auras3",[2]="customContainers",[3]="perUnit",[4]="player",[5]="items",[6]=4,[7]="placed"}, lists = {[6]=true}, runs = {
        20,
    } },
    { path = {[1]="auras3",[2]="customContainers",[3]="perUnit",[4]="player",[5]="items",[6]=4}, lists = {[6]=true}, runs = {
        21,
    } },
    { path = {[1]="auras3",[2]="customDisplays",[3]="shared"}, lists = {}, runs = {
        22,
    } },
    { path = {[1]="auras3",[2]="customDisplays"}, lists = {}, runs = {
        23,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena1"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena2"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="arena3"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss1"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss2"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss3"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss4"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layout"}, lists = {}, runs = {
        27, 28,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="boss5"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layout"}, lists = {}, runs = {
        33, 34,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus",[4]="layoutShared"}, lists = {}, runs = {
        29, 30, 31,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="focus"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layout"}, lists = {}, runs = {
        35, 36,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player",[4]="layoutShared"}, lists = {}, runs = {
        29, 37, 38,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="player"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters",[5]="buffs"}, lists = {}, runs = {
        24,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters",[5]="debuffs"}, lists = {}, runs = {
        25,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layout"}, lists = {}, runs = {
        39, 40,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layoutShared",[5]="buffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layoutShared",[5]="debuffFrameEffectColor"}, lists = {[6]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target",[4]="layoutShared"}, lists = {}, runs = {
        29, 41, 42,
    } },
    { path = {[1]="auras3",[2]="perUnit",[3]="target"}, lists = {}, runs = {
        32,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconShapes"}, lists = {}, runs = {
        43,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="buff",[5]="styleBorderColor"}, lists = {[6]=true}, runs = {
        44,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="buff",[5]="styleShadowColor"}, lists = {[6]=true}, runs = {
        45,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="buff"}, lists = {}, runs = {
        46,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="debuff",[5]="styleBorderColor"}, lists = {[6]=true}, runs = {
        44,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="debuff",[5]="styleShadowColor"}, lists = {[6]=true}, runs = {
        45,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="debuff"}, lists = {}, runs = {
        46,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="playerDefensives",[5]="styleBorderColor"}, lists = {[6]=true}, runs = {
        44,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="playerDefensives",[5]="styleShadowColor"}, lists = {[6]=true}, runs = {
        45,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="playerDefensives"}, lists = {}, runs = {
        46,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="targetDots",[5]="styleBorderColor"}, lists = {[6]=true}, runs = {
        44,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="targetDots",[5]="styleShadowColor"}, lists = {[6]=true}, runs = {
        45,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="appearanceIconStyles",[4]="targetDots"}, lists = {}, runs = {
        46,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="buffFrameEffectColor"}, lists = {[4]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="debuffFrameEffectColor"}, lists = {[4]=true}, runs = {
        18,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters",[4]="buffs"}, lists = {}, runs = {
        47,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters",[4]="debuffs"}, lists = {}, runs = {
        48,
    } },
    { path = {[1]="auras3",[2]="shared",[3]="filters"}, lists = {}, runs = {
        26,
    } },
    { path = {[1]="auras3",[2]="shared"}, lists = {}, runs = {
        49, 50, 51, 52,
    } },
    { path = {[1]="auras3"}, lists = {}, runs = {
        53,
    } },
    { path = {[1]="bars"}, lists = {}, runs = {
        54, 55, 56, 57, 58, 59,
    } },
    { path = {[1]="boss"}, lists = {}, runs = {
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    } },
    { path = {[1]="focus"}, lists = {}, runs = {
        75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
    } },
    { path = {[1]="focustarget"}, lists = {}, runs = {
        90, 91, 92, 4, 93, 94, 7, 95, 96, 97, 98, 99, 100, 101,
    } },
    { path = {[1]="gameplay",[2]="combatStateEnterColor"}, lists = {[3]=true}, runs = {
        102,
    } },
    { path = {[1]="gameplay",[2]="combatStateLeaveColor"}, lists = {[3]=true}, runs = {
        103,
    } },
    { path = {[1]="gameplay",[2]="combatTimerColor"}, lists = {[3]=true}, runs = {
        102,
    } },
    { path = {[1]="gameplay",[2]="crosshairInRangeColor"}, lists = {[3]=true}, runs = {
        104,
    } },
    { path = {[1]="gameplay",[2]="crosshairOutRangeColor"}, lists = {[3]=true}, runs = {
        105,
    } },
    { path = {[1]="gameplay"}, lists = {}, runs = {
        106, 107,
    } },
    { path = {[1]="general",[2]="UIScale"}, lists = {}, runs = {
        108,
    } },
    { path = {[1]="general",[2]="bossTargetHighlightColor"}, lists = {[3]=true}, runs = {
        109,
    } },
    { path = {[1]="general",[2]="editModePopupPos",[3]="MSUF_EM2_AuraPopup"}, lists = {}, runs = {
        110,
    } },
    { path = {[1]="general",[2]="editModePopupPos",[3]="MSUF_EM2_ExternalPopup"}, lists = {}, runs = {
        111,
    } },
    { path = {[1]="general",[2]="editModePopupPos",[3]="MSUF_EM2_GFPopup_party"}, lists = {}, runs = {
        112,
    } },
    { path = {[1]="general",[2]="editModePopupPos",[3]="MSUF_EM2_GFPopup_raid"}, lists = {}, runs = {
        113,
    } },
    { path = {[1]="general",[2]="kickNotReadyColor"}, lists = {}, runs = {
        114,
    } },
    { path = {[1]="general",[2]="kickReadyColor"}, lists = {}, runs = {
        115,
    } },
    { path = {[1]="general",[2]="minimapIconDB"}, lists = {}, runs = {
        116,
    } },
    { path = {[1]="general",[2]="statusIndicators"}, lists = {}, runs = {
        117,
    } },
    { path = {[1]="general"}, lists = {}, runs = {
        118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="blizzardTypes"}, lists = {}, runs = {
        145,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="buff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="buff"}, lists = {}, runs = {
        147, 148,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="debuff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="debuff"}, lists = {}, runs = {
        149, 150,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="externals",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras",[3]="externals"}, lists = {}, runs = {
        151, 152,
    } },
    { path = {[1]="gf_mythicraid",[2]="auras"}, lists = {}, runs = {
        153,
    } },
    { path = {[1]="gf_mythicraid",[2]="privateAuras"}, lists = {}, runs = {
        154,
    } },
    { path = {[1]="gf_mythicraid",[2]="spellIndicators",[3]="style"}, lists = {}, runs = {
        155,
    } },
    { path = {[1]="gf_mythicraid",[2]="spellIndicators"}, lists = {}, runs = {
        156,
    } },
    { path = {[1]="gf_mythicraid"}, lists = {}, runs = {
        157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="blizzardTypes"}, lists = {}, runs = {
        145,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="buff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="buff"}, lists = {}, runs = {
        179, 180,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="debuff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="debuff"}, lists = {}, runs = {
        181, 182,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="externals",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_party",[2]="auras",[3]="externals"}, lists = {}, runs = {
        151, 183,
    } },
    { path = {[1]="gf_party",[2]="auras"}, lists = {}, runs = {
        184,
    } },
    { path = {[1]="gf_party",[2]="privateAuras"}, lists = {}, runs = {
        185,
    } },
    { path = {[1]="gf_party",[2]="spellIndicators",[3]="style"}, lists = {}, runs = {
        155,
    } },
    { path = {[1]="gf_party",[2]="spellIndicators"}, lists = {}, runs = {
        156,
    } },
    { path = {[1]="gf_party"}, lists = {}, runs = {
        157, 158, 159, 160, 161, 186, 163, 164, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201,
    } },
    { path = {[1]="gf_priority"}, lists = {}, runs = {
        202,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="blizzardTypes"}, lists = {}, runs = {
        145,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="buff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="buff"}, lists = {}, runs = {
        179, 203,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="debuff",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="debuff"}, lists = {}, runs = {
        181, 204,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="externals",[4]="blacklist"}, lists = {}, runs = {
        146,
    } },
    { path = {[1]="gf_raid",[2]="auras",[3]="externals"}, lists = {}, runs = {
        151, 205,
    } },
    { path = {[1]="gf_raid",[2]="auras"}, lists = {}, runs = {
        153,
    } },
    { path = {[1]="gf_raid",[2]="privateAuras"}, lists = {}, runs = {
        154,
    } },
    { path = {[1]="gf_raid",[2]="spellIndicators",[3]="style"}, lists = {}, runs = {
        155,
    } },
    { path = {[1]="gf_raid",[2]="spellIndicators"}, lists = {}, runs = {
        156,
    } },
    { path = {[1]="gf_raid"}, lists = {}, runs = {
        157, 158, 159, 160, 161, 186, 163, 164, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218,
    } },
    { path = {[1]="pet"}, lists = {}, runs = {
        219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232,
    } },
    { path = {[1]="pettarget"}, lists = {}, runs = {
        233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244,
    } },
    { path = {[1]="player",[2]="castbar"}, lists = {}, runs = {
        245,
    } },
    { path = {[1]="player"}, lists = {}, runs = {
        246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260,
    } },
    { path = {[1]="target"}, lists = {}, runs = {
        261, 262, 263, 264, 265, 266, 267, 268, 269, 227, 228, 229, 230, 231, 270, 271,
    } },
    { path = {[1]="targettarget"}, lists = {}, runs = {
        272, 273, 274, 249, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285,
    } },
}
-- END SPARSE V3 INHERITED DEFAULTS

-- Additional typed defaults with exact presence and reusable logout scratch.
local sparseV3 = {}
do
    local marker = "_msufSparseDefaultsV3"
    local before, tables, nibbles, pieces = {}, {}, {}, {}
    local absent, size = {}, 0
    for i, spec in ipairs(sparseV3Owners) do
        spec.fields = {}
        for _, run in ipairs(spec.runs) do
            for _, id in ipairs(sparseV3Runs[run]) do spec.fields[#spec.fields + 1] = id end
        end
        spec.offset = size
        tables[i] = false
        for j, id in ipairs(spec.fields) do
            local field = sparseV3Fields[id]
            before[size + j] = false
            field.bytes = #tostring(field[1]) + (type(field[2]) == "table" and 2 or #tostring(field[2])) + 4
        end
        size = size + #spec.fields
    end
    local maskSize = math.ceil(size / 4)
    for i = 1, maskSize do nibbles[i], pieces[i] = 0, "" end
    local function Bit(slot)
        local bit = sparseV2Bits[(slot - 1) % 4 + 1]
        return math.floor(nibbles[math.floor((slot - 1) / 4) + 1] / bit) % 2 == 1
    end
    function sparseV3.Resolve(profile, refs, lists)
        for i, spec in ipairs(sparseV3Owners) do
            local node = profile
            for depth = 1, #spec.path + 1 do
                if type(node) ~= "table" or (lists[node] and not spec.lists[depth]) then
                    node = nil
                    break
                end
                if refs[node] ~= 1 then return false end
                if depth <= #spec.path then node = node[spec.path[depth]] end
            end
            if node then
                for _, id in ipairs(spec.fields) do
                    local field = sparseV3Fields[id]
                    local value = node[field[1]]
                    if type(field[2]) == "table" and type(value) == "table" and refs[value] ~= 1 then return false end
                end
            end
            tables[i] = node or false
        end
        return true
    end
    function sparseV3.Release(rollback)
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local slot = spec.offset + j
                local value = before[slot]
                if rollback and owner then
                    if value == absent then owner[field[1]] = nil else owner[field[1]] = value end
                end
                before[slot] = false
            end
            tables[i] = false
        end
    end
    function sparseV3.Capture()
        local count, bytes = 0, 0
        for i = 1, maskSize do nibbles[i] = 0 end
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local slot, value = spec.offset + j
                if owner then value = owner[field[1]] end
                if value == nil then before[slot] = absent else before[slot] = value end
                if value == field[2] or (type(field[2]) == "table" and type(value) == "table" and next(value) == nil) then
                    local index = math.floor((slot - 1) / 4) + 1
                    nibbles[index] = nibbles[index] + sparseV2Bits[(slot - 1) % 4 + 1]
                    count = count + 1
                    bytes = bytes + field.bytes
                end
            end
        end
        return count, bytes
    end
    function sparseV3.Mask()
        for i = 1, maskSize do pieces[i] = sparseV2Symbols[nibbles[i]] end
        return table.concat(pieces)
    end
    function sparseV3.Validate(profile)
        local mask = profile[marker]
        if mask == nil then return true end
        if type(mask) ~= "string" or #mask ~= maskSize then return false end
        local nonzero = false
        for i = 1, maskSize do
            local byte, value = mask:byte(i)
            if byte >= 48 and byte <= 57 then value = byte - 48
            elseif byte >= 97 and byte <= 102 then value = byte - 87
            else return false end
            nibbles[i] = value
            if value ~= 0 then nonzero = true end
        end
        local tail = size % 4
        if not nonzero or (tail ~= 0 and nibbles[maskSize] >= 2 ^ tail) then return false end
        for i, spec in ipairs(sparseV3Owners) do
            if not tables[i] then
                for j = 1, #spec.fields do if Bit(spec.offset + j) then return false end end
            end
        end
        return true
    end
    function sparseV3.Apply(restore, prepared)
        local count = 0
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            if owner then
                for j, id in ipairs(spec.fields) do
                    local field = sparseV3Fields[id]
                    if Bit(spec.offset + j) then
                        local key, default = field[1], field[2]
                        if restore then
                            if owner[key] == nil then
                                if type(default) ~= "table" then owner[key] = default
                                elseif prepared then owner[key] = before[spec.offset + j]
                                else owner[key] = {} end
                            end
                        elseif owner[key] == default or (type(default) == "table" and type(owner[key]) == "table"
                            and next(owner[key]) == nil) then
                            owner[key] = nil
                            count = count + 1
                        end
                    end
                end
            end
        end
        return count
    end
    function sparseV3.Same()
        for i, spec in ipairs(sparseV3Owners) do
            local owner = tables[i]
            for j, id in ipairs(spec.fields) do
                local field = sparseV3Fields[id]
                local original, value = before[spec.offset + j]
                if original == absent then original = nil end
                if owner then value = owner[field[1]] end
                if type(value) ~= type(original) or value ~= original then return false end
            end
        end
        return true
    end
    sparseV3.Marker, sparseV3.Overhead = marker, maskSize + #marker + 8
end

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
    sparseV3.Release(rollback)
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
            and (profile[sparseV3.Marker] == nil or sparseV3.Resolve(profile, scratchRefs, scratchLists))
        ClearScratch()
        if not ok then return false end
    end
    -- Validate the entire mask and all referenced owners before the first write.
    if not ValidateSparseV2MaskOwners() or not sparseV3.Validate(profile) then return false end
    if profile[sparseV3.Marker] ~= nil then sparseV3.Apply(true, prepared) end
    ApplySparseV2(true)
    profile[sparseV3.Marker] = nil
    profile[sparseV2Marker] = nil
    profile._msufDefaultsRevision = 17
    return true
end

-- Capture stored newer data at the shared decoder entry, before either the
-- profile translator or the defaults normalizer can change it. Private copies
-- have no stored owner and must not overwrite the account's original backup.
local function CopyNewerProfile(value, seen)
    if MSUF.Util.IsSecret(value) or type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[CopyNewerProfile(key, seen)] = CopyNewerProfile(child, seen)
    end
    return copy
end

local function SaveNewerRevisionBackup(store, name, profile)
    local backups = store._newerRevisionBackups
    if type(backups) ~= "table" then
        backups = {}
        store._newerRevisionBackups = backups
    end
    if backups[name] ~= nil then return end
    backups[name] = { revision = profile._msufDefaultsRevision, data = CopyNewerProfile(profile, {}) }
    print("|cffffd700MSUF:|r " .. string.format(MSUF.Translate(
        "Profile '%s' uses a newer MSUF revision (%s). An untouched backup was saved."), name, tostring(profile._msufDefaultsRevision)))
end

local function BackupNewerRevision(profile)
    local revision = tonumber(profile._msufDefaultsRevision)
    if not revision or revision <= 17 or revision == sparseToken then return end
    local store = MSUF_GlobalDB
    if type(store) ~= "table" then return end
    local found = false
    if type(store.profiles) == "table" then
        for name, stored in pairs(store.profiles) do
            if stored == profile then
                SaveNewerRevisionBackup(store, name, profile)
                found = true
            end
        end
    end
    if found then return end
    -- Startup copies a standalone/donor profile before adding its named entry.
    -- Preserve the selected saved source, not the already-changing private copy.
    local legacy = MSUF.FirstLoad6.GetLegacyProfileDB()
    local charKey = MSUF.Require("MSUF_GetCharKey", "State/Defaults/MSUF_Defaults_Schema.lua")()
    local name, source = MSUF.ResolveStartupProfile(store, legacy, charKey)
    if not Plain(source) or MSUF.Util.IsSecret(source._msufDefaultsRevision) then return end
    revision = tonumber(source._msufDefaultsRevision)
    if revision and revision > 17 and revision ~= sparseToken then SaveNewerRevisionBackup(store, name, source) end
end

function Schema.RestorePersistence(profile)
    if not Plain(profile) or MSUF.Util.IsSecret(profile._msufDefaultsRevision) then return false end
    BackupNewerRevision(profile)
    local marker = profile[sparseV2Marker]
    if MSUF.Util.IsSecret(marker) or MSUF.Util.IsSecret(profile[sparseV3.Marker]) then return false end
    -- An older loader that materialised the profile (6.50x stamps 17) may leave
    -- an obsolete V2 mask; its revision owns the data, so never use that mask to
    -- invent leaves. A newer revision owns a string mask: refuse and leave it
    -- intact. A non-string marker is nobody's mask and is dropped.
    local revision = profile._msufDefaultsRevision
    local stale = (marker ~= nil or profile[sparseV3.Marker] ~= nil) and (revision == nil or (type(revision) == "number" and revision < sparseToken)
        or (revision ~= sparseToken and type(marker) ~= "string" and type(profile[sparseV3.Marker]) ~= "string"))
    if stale then
        profile[sparseV2Marker] = nil
        profile[sparseV3.Marker] = nil
    elseif marker ~= nil then
        local restored = RestoreSparseV2(profile, false)
        ReleaseSparseV2(false)
        return restored
    end
    if profile[sparseV3.Marker] ~= nil then return false end
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
        or profile[sparseV3.Marker] ~= nil or refs[profile] ~= 1 then return 0 end
    if not ResolveSparseV2Owners(profile, refs, lists) or not sparseV3.Resolve(profile, refs, lists) then
        ReleaseSparseV2(false)
        return 0
    end
    local legacyRemoved = CaptureSparseV2()
    local removed, bytes = sparseV3.Capture()
    -- A short/incomplete profile remains full when the fixed mask would cost more.
    if legacyRemoved == 0 or bytes <= sparseV2MaskSize + #sparseV2Marker + 32 + sparseV3.Overhead then
        ReleaseSparseV2(false)
        return 0
    end
    for i = 1, sparseV2MaskSize do sparseV2Pieces[i] = sparseV2Symbols[sparseV2Nibbles[i]] end
    local mask = table.concat(sparseV2Pieces)
    local extension = sparseV3.Mask()
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    profile[sparseV3.Marker] = extension
    local elided = sparseV3.Apply(false) + ApplySparseV2(false)
    -- The real decoder's nil-only fill runs against the existing owner tables.
    -- Compare every known original field by type AND value, including nil/false/0.
    -- Only these fields and the two stamps can change; all other keys and table
    -- identities are untouched. Rollback returns the complete original profile.
    local restored = RestoreSparseV2(profile, true)
    if elided ~= removed or not restored or not SameSparseV2() or not sparseV3.Same() then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        profile[sparseV3.Marker] = nil
        return 0
    end
    local committed = sparseV3.Apply(false) + ApplySparseV2(false)
    if committed ~= removed then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        profile[sparseV3.Marker] = nil
        return 0
    end
    ReleaseSparseV2(false)
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    profile[sparseV3.Marker] = extension
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

-- Immutable factory payloads, loaded before profile initialization on every client.
MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = (
    [[MSUF3:7b1bjGPpdR66Wd1zUWsyGYx1ElbPaNSjy2ikjJJMtSy3HNszZPFSrOJ181KbhoACi9xVRTSLpLlZ3V1KgIxhB0GCIH4I8p]] ..
    [[DzJkuKj499Yh9LDzNAgATOQxJAfgrgJIgRQMgFOLGRh4T7QZoHn/9+Xf8uVnVV34Z60HSRm3v/+//Xv9a3vrX+tX6rOJ1NDoajsJ]] ..
    [[gLD3ono3n+ODo5+Mb3zI9zd4fjwWZvNCpE/aPwuLe+FhSnvdPRpDf4MB28vod/lRtG03BUnw0ns+H8tDI8nPXmw8n4udJ42t+cjC]] ..
    [[az6IPiYTgOZ73RR2ufK8/DB/Nsr393MJtM42a/F833e7PW8DgsTMbz5vDbobdzHI5P8F874WlQLo3n4eyg1w+/lRkMauPoW5XhYD]] ..
    [[w8PELXHk9HYXs8nBdmveMQfREOhr1v4R9G38o/mM7CKLrfO73lh4cno97sr87nB8FNMuJCrz+fzE7r9F0z0+loGA7iFhtLYdI/ib]] ..
    [[K92e5wMD9K/15wczrqnbZ6s8Nw3gxHYX9enkTz5uRkPIhiP5r35mGpPxlHrTCaVyaDcFHm743/2pqF6GFoOhroztnDSm/eP9qqk6]] ..
    [[8XwU31ic2jyX36lCp6m0UHPzWcbdIravfC2Ww4CP1Uq49/W5/cD2ctPJOnrdNpGAfpCP28NO5PjofjQz+MSuPBsN9Dbyleq07uVz]] ..
    [[s4iMJ5987PF9slNPmj8Lt58p8UXkyydOGgMJscF0eT/R5a1BBdvXfv3biYH/f2R+Fg4R+FvdH8qDjrDYbhGM3FfTSm3iwc9/BQ8U]] ..
    [[zQRwRefdCb3c0eZmd4scZoMX7yda95gparNZmM5sMpmv576JVmuWKmkt9BXxygVUDzXvz4vf9ym/zPn05m81lvOM+F8x6Sv0Frki]] ..
    [[vnCy0fv2wRzVIFCUr2ZD6fjOMWvzY7maGbkhnOpppiZHj6kdSF40Gu0mwXmvuTKMKfY8kTIxb3OCS/z3z83p/SkQSfVZdKLhObzp]] ..
    [[Q+ydqD1B+yB60Fr/HH4wmjI24dDft38TR5zem9qVg/9gQveB0UCLYsSADEm8rRZUbDw3HeLxW3Wn7v8HA2EXfFork5OTho4dXM7E]] ..
    [[eT2X5m3D+iX1xr49HR29RO5qPhOMQfp4L0IXrkRn4wJIKONybb67E5c/7H7/32P8H/+z9beMWpimieHu9PRniLv1w5QLsUy29mND]] ..
    [[3qpdB8jIbf/nZvNoBu3lAXke7K3w8+r+5k/LJo/8zm4RiJf2H4IBxgoa0ROdnMIaFqoueP4mCdzzv5G/+sNTsZoykJc5l2q1ab4n]] ..
    [[1VxtdQ+anh+UG7YCDm+SbaEmiPNMm+59NJ567YqtWxeFaxrJE1bc5PR2GutVWqBp8j48U/O4nqk4jNNttxZLD6s9Eu+LMf4f/9UZ]] ..
    [[nP7S9PJsfpQXBzTvcPVhiZkxmZmHCG3yVakJ2xG46QHkCbI4p6h2HcjOjM4Cs2R+h3SGzINqrii/3ecFBBGzWcxbqQwzMUpLnGJu]] ..
    [[Kh7vcG1uiDyf0xeWu8iDn8ymRIdSG7eL/Fu/pmzQ1nIVGS2Xa9MT453g9nmf39WXiPzh/WD3V1T2ARejVIYzOxOepF0bCfmaP/+u]] ..
    [[G9YYTuslbjtxebJ61tXzQEtARD/ES2O+6iveeHvcEpmVQsbgvxGzp2/KbNaa+P5AvpSmsS1PXOZfydtin2VNB3tXEg+ecjbKoKgX]] ..
    [[+4K5QUtKWDtHwGVgfYSiFdexjOCtman8v7wr7QN8CvJhY1Dt7o46kjhgQJ+L1heL94giQj4ooeXQCqPG6mb0Aa108pigialxb6wa]] ..
    [[A4m5xMFfXpVfitmke9aVhoNtoZP187muIZaobT3oxssq/5WGugS5CQodee98b9MFUTS0e3FJ2bRsTXkQ8k9tnrUMtG1ci/ESJPp4]] ..
    [[gAiXJ4D00oGdnzvqp6tkJsyV4ypCvwgrdVXdTsT6bhwKGRSuMJ06iLpm5It9C9iylA9QdexxTewmR23JsXN9u+n6+2pPUltozevl]] ..
    [[As17KZ8jbCIhggtCat2Ni60vB1NbOMNi62xLPNTLnlcwHEFofvpZu2VAqZqIdMfzfHvSlRAdhktEd4Sq33EttI7jBTXPR1JILrH6]] ..
    [[GZGuGVEBbz+cYhm0WhSagY7Jozxx79ptCp9d448AClJrb6LccYpbmuEGRXGI5G5IUPTtAO47enIuM1NamnglqqIrVGN/Jr6jChaQ]] ..
    [[DsVqX3gMiwVz5A+/iogJ7anT64wd+4TeGUmI+FmGzyEEvQO8T6FOFpFKqASY4Ff7iEbiEFgnY4Wv67aDoiB4jNpvyQKJmMsrnieo]] ..
    [[/AkKwiaYbAKupSgYsIanxEoUZdkQIfz7vY86pSbVsLSu1qx9KmRGV//N4fH5D/0RnC+JQ9hUIEz5YxbQeKl8CgEEEw5DbgFzmZhf]]
) ..
(
    [[nmZDQcBOsQoCjjsaXXg3VrsNxwEQveUPYtlaqtfNDK+9VMuaFr58xsniuUM60mnfm6utoLRYMocxx8FhoZ2RxYMLey5dIv/3LGz7]] ..
    [[XMPV9Eixy3LYnFSoJNSluTC+E51chOIiadeki7YmDiLsQAkpfvYN2QtXTRoi4sAtvt15vz8HiKNswW0bgcoP53uq71iGAy8YLR94]] ..
    [[pE6RR2FuQfuWpusUX+gW4ZlwikPEIeYCzMK/MNgfcM1i2hqo3pKGJ/yn04xcIFn3PsNIFXsvlybbc+640Pw0JPwf+fhQejC2NTd3]] ..
    [[Gll6J7cFz51dg25Rsz3kW4cr831yUCDY0j3zq1aQLE+qm24RhR/L6e+ouAA4ZwABrrXe4CRHFbeyflx7ZdCtaE6alPpidTNKjv+/]] ..
    [[jN9vKVjT1MEpCPfzM3Cg/mP83+r6/98eZ8Mv1prvPWP2qLy4oFctEe1tbsytyv/uMOvTLzL/68I67MP0CQe4xcA+Wmub/fZpf+gr]] ..
    [[cmn40hunbZ337lkF6W+5Vf6FjPRqIwP2WXbg7b+/TSz27/7u44ms2r2OigZVXdo5ZpPZif8AYsEcJwNJVJFFuwrm0qjNUrRE65hX]] ..
    [[9J9SYwosxN5lFcPYlCuW2juIzx0MbucIyQ2tb69d/fNdEwA6r5bHevkg9uDnpjpKMiyPnr2CpA2WC7hA2hO4rSIfTfi1aErSLmB7]] ..
    [[BW4rtkW9jK4M7fCNaFxaF0DWeuOhuWP1sU/qw2QQRYivlHJk8Yzk0EnnzTpranCFVrukgahRrec/PTj9/7r9TrE+haGCOu93bN9R]] ..
    [[b0hUBG/H2b3MMj2KNEFm1BORGG+bUrq717w0MyBYTRiqsYb1cm40n/aIYcSjSp+HZIVJBykASTA2R1vZa6xXWHq6naDD6G3SM2J7]] ..
    [[qJ9b3gNcgSsde+8+WaYuWp7AviCK8JNYCLpob/KTB71eHyaka2eHAlVKTLkUaGd52aRzTTk5NZP6yj6eZzVGaAnow35lcaAAtPbH]] ..
    [[6znGk2O8puLczwavaiu/UHL5o2EsN6e6Np0+CrS9aaYCO/8AdkTzO4ioSjNs5la60tuc+21tf+OUN7ZMgc7e1yYmVIHX/uXXlVIc]] ..
    [[Rk8fP3j4bz0GBKbSzARQCPgWzKpg5/KJSu1qr5mgISy0jJLpxuUfAmNCdCfSoQNCu4GuEumMyAdBdqfB6zhwxg/phqFoHYkK3sh8]] ..
    [[fYJ8y0WpnNrXyuhEUQmg+m23XPPm3NLUOc7wsnoIq2OBbm2cl0PkRrQ+69iX7S3lNccfQ3Wjs0+uxGzmVONHZItcsqvNhFcoJFAO]] ..
    [[+Q0vhgwiBrFG9hjpgYnoqkYJCZeRFaFRhXU2Sh6h2LeyFo+kUI5QbCHeCsP1cMNrnCiZGmRhbR8S3KPWTmuZFMrwN0TuAx7E1/wT]] ..
    [[eCQwMJMavyeaBLuIOn81b5pI/EA3Srux5ZBEO96340sesaNS61AKRp6SwGafrdHudq93rj4XGPXG3h66zwyoK05QnoK2k7XnS3Ft]] ..
    [[rlckMRKEa/MOa3zjdLiH3duWRSv3574+v0fYXCIe+ruvzSC5QbiKgNF+mlw28hexokIbGrrQP2r5eD1wBGXhAlxHlphqODLW2vxo]] ..
    [[rKAdxsU7CRWb8/P6ImtW1pHmoLWwaIlrsSYBU0jV+Vgo4XpLBPNFnbIhXJzEn3nUlqlUhq83gymR/durdhkpGQt2QrLsGEwpin69]] ..
    [[UVAWGhgTqOvwkwim6ykL6G4t42hI3yQ4Tjh2gYm/lqC9OmNsGlr3/LJuQkIoVBTNGrkwiMGk9pKnZxB001fq9F60D9k6mO9dQ7qt]] ..
    [[3KTe6PF9uwUti19KbOFup+l9s75IHCd4Obyv68P0Yw/Wg47aD/oOlIJcfFAs/XiC8iRvl6Bo3DBNhZAbB1rt6iPIL1XzlBk9MM5y]] ..
    [[dTsspUSsIZjuACc4fhlLUz9DveIgoFOcFoNiF18rOxTp65nGsZS5NwBgqNSnHGu2fzqDceh6MWGnW0qDJDiWOyCPUtGuaODzz6kq]] ..
    [[bfJvCOQuq9UEE2dvO0P8KaPHzwaeRn4fDwBPSzWmQSCCJh3CHmq1tURLc0qjr2+T5VYoaqX4hMAXqrWfQ8wHFnFcIymD5AbtjnYP]] ..
    [[ZTIiapp2wBq/WMCScEDZmEBXrfcN4bjsD3NakKJIA//PaPi//sM3/TJg0DDyb/fK+C5hPZwCm+Npf97jb7E8lX+k8K+NKTKF3PHS]] ..
    [[FMvmggG4lvgkzrYZjFREcswh5k2tMD4lvWlQhAXDnUvMe2GRAnegskaWGV3hghdR6qfOi1HRKmRz+bjMP8PoKed1uaICvbCCB/CL]] ..
    [[R6QZKN3FFZ7NoRbslnV6lYCQKyoUEq7F0vBJIWOLUQhoN9NLzcCV3Cn9zxWsIOo3fA4OFgNLkfUwVOp2HLdInb1jJgRfiTr3u+pj]]
) ..
(
    [[yoLXm7qWzU+kl0hJ8PRQYF9mJ3J+JBHhHFDfqyWWmoYsuQN9HszXsEQzdkkItxAinIMHK64E+o4yFEiaJGEVIwrK30mCgsMyaJDP]] ..
    [[vXUh+/9z9+cfrdf3/jFxVvjHK+RT+TKyErsqvjSUm+QvG94FoRjYQ4pSTmSMJ42V4UYuVJL/FUBw556PcXQmuL5Bjp4ejhWnLBQr]] ..
    [[j8xCjoDLUEMuQFv5t518vc9jIbqSpVFnxLxHVVaCl8AlSY7+30meXJHvoiPCcoTuZCEKGuTubag1PkwV4bP7g1mYvki+PJCdoHdn]] ..
    [[JNFu27IZDWQ/dd2/KBFCSiAz/u0+5y9xPHanaxM5mZIRSJuQQLOeicDRTvLabKJ1GY5fkOcfOQsCvtIUkqoulDud7JfAJ4G8EalJ]] ..
    [[qERgjHyAOvgZnPqgruFtK5sCJaW2hbkVDLwukqBm/qqs4IzJgKSDjKJXTVr5xMhlFYpeYH/xDP6RpL82DeV27WO9zCCvrBNJyhBe]] ..
    [[0jvdgG8JlYsppUz3SBjdguB73YoGQG93AAfIA5zhhAuMg2YiGrSAMVWzQsI/rXtnvEkOPNtdUu1fFD51biDskZyiCfTM6ZYA9ZVE]] ..
    [[klo+KqzL4hDhhJBJHOL/mshXM4MtNp2Jvhl6ECU+7TpI4i/o+5eAqCt15HpC64fqPEnM0Ai5JY0TZ5WxpM3GHUG1bksaIBsl7L/A]] ..
    [[EB6HUVaSuLXBGBHzyj2wiX1/M+dj1E/BJZg3B8OD8S2p05VxJuPSfwM/YmSdCtXS0Van6lrUmMkeaiq5fKcIDUyxuwpdB4nbaGYj]] ..
    [[VEYeKoouCzOjgSTpEjlRb0WsNpKHaA2FeCfPLV7AcWz2zV6ixIDjjGhlvmjrK25yrpIlBzY3IPpxrhwTHqQeYR5geHYXNyMKcQ1B]] ..
    [[WKDjxIzXbv/Lxl4o33qdMt15psTpCewvKyC+l59IbiJy2NZtHer0ojpzzrtIA053xyXGcSSz7H18dNnTKiSsaJZ5D/ZkmMn2qpos]] ..
    [[cpZ69lmmtqUNVoCbHdHTNaTBnzxfbRtCCpExjKSvRSV+ACAX8LH4egyFsXOFe6aOlva+VdfG6q6+kM4bOwPFnxot31a79uJAs53E]] ..
    [[Alj4HBt44ZxmQAAVLuSGvruThhIVPezXSbSTGQbnoj+BIxPArIrB+dIh3aG2E5pm+OHToDGOo0IYA/il5NFSIcBG5oykAnmRBuvR]] ..
    [[ty9fWikdIoY+7SUSceMP3tQswv+h3a16EIpjGO1RbGYgqy7TpPrAfGgcQXKIJSTOmbTSDx14HsNsVTfR2JRBgdh2hfQomspk7oep]] ..
    [[ZDFni6+bFsgWVsSBSjczSty3wCnKUeDnbC00JEWHyAoC0KghbCdRnj/bmAVMckiVTgr6YaAGJB3WK2u+dnSjk1CLy7fv1fBut2NM]] ..
    [[VYqzcZE1OeIMFlJwBEWHbv3tf/+s8ptLXNbcFeehGMbWn2raXifp0cciVkCCaXRgqSUygNhSHI/W0JkRZVoWt0MtLJBwdeVQa5Md]] ..
    [[z++L3/j1FocqYtea/wjEByN1fMVcEFcM5X4AQO2vQZVILwZ8EoA46cfLkhA1A4kVLKMMGjSvCIuHhFBhUVOFa04z9GvpJmO7hPqU]] ..
    [[Bv/XLK6I9ODtkhi02ABYl3jZxsct9SLlp0LIpdGrEG3TwqJVzZI0/jbz7ncy99J4Fd9KxBEMg2jL0iIGhT4zqoOUq/rQWteA6Qr6]] ..
    [[NYdbtZpDz/TXmsbJCXGyqqo4jDyP8WCnRtF3Bo1UfuEP0wZEdW1q2rdbwrzXf3hsEnAOGHBj2vQkEEcy+dzGM3JfKNcCQcKdhp+o]] ..
    [[tN9SOBIWgas4H1cWIuvpuP1cRrVjBKYVR85lGSs0pNcQrr8ICkKX2UCiuENeTKf1FDe+tkhi0ntfpMkRT7Qzr3FXwAKxeOhsfIxM]] ..
    [[42b/21W23sTpJXG+McN/SCJEG53h+hZcEvL14F7eN59tSfjMJFLTo5PqaJInQn5vKFTLvcqvSHGRzoYPlfFSrj/A5FLAsYGLZp1l]] ..
    [[2msIOXjeOYr5Sns+E9tLPwHop+pxgyRVoacChANs7mce9BKk8W/aUK3ZMn4zkG0XHm1Ms8+EIxYpJY6ClJ4Tskx4UcL4gWuYjkK9]] ..
    [[Nh5Ko5rtYqVCFSKSgKldoWThtxBoUSvLnHqTmkfCKycXnsIC5O6Futp35UnjLBxGJQLfql3F621q7mmnudjQqe/tJ4a3ISYcp/c/]] ..
    [[9QprTu9I9OxnfDAc5jWfh0sCT7kA+gfEi4NvJSwZvtPexPI+Hu5ybHveHYD6e94SxVH4T7JwcH1P/CeLCQrbVatUqDrQZ9Wfyv93]] ..
    [[08GCYBwujP0ILjb6lA0YQLZSzEs6gcjZS4kbdF84mQYi30hySivzOWxiP9xQr9PX8NcjnyZCaL4gCJIHKqRTyobTxJk+rEyPNuiG]]
) ..
(
    [[ZlUGeYAAGxCUu9DNYHgj+nXxKHDvOqi8pef8hXsLMRM8zZInumj9yDUYRw6NQQhK5nMjdrRaq7/RTT8uopEF8KP7oP25bspshUz6]] ..
    [[JwUSbyxu++TUOveB5TTXrhZojdZz5/JXTbKKTpaOCRrtYASmVozY9mYY9Mq3ScF7vm7LBhfOGsGC/jSnFeagvdGK3paJDeSwjrbh]] ..
    [[M4yY5aybHQGdmZEeL0KOzfRV6RvDXLmmFweEf+rHvLOq6Vx2kZ0R/ksPh/+GWmDXi2aoVEO0bDaL7Zm0cfdPrME2cL3QzRdA6ia0]] ..
    [[RTvMR1UbyD9DCa+dbkbjgO0iR/s+jX2vW9LaRjyiS5ba/zLkF2CCT070ZxBZm6/l0MdwTJTzRY4ZCE70tEOeVqu9XM6ZuZBy8XIv]] ..
    [[yzrleYhjN/cj+F/ha/Kw2xvsXWLz2o8vFqO6IkXuo3iWKph8h+jnGQpYAFYBR9sEPuT3+0QxWBVI8MXNGjczzSgvcFHRWSNPJfgn]] ..
    [[y5lvVaA3mhcNpKfr6SKVVL1WKJD7TriX8GXlP5ETfbTC9R1f5imV9Mntagip59ch9psrih3IKCmLUdbKL4JtoaCgeVmK5KOD+aDL]] ..
    [[il8rVRR9gP3Mpm/L1atdxt9dUHiU2pDiEu71FJQNqiczsuUB0rhGybvsp55exVUM4w7apKlCo+RcpZ1jOna5kHn3lcwqNPxjLSU1]] ..
    [[ddR8It1wqFMyRJX4ALytWNK5YrbR+dX8jErtLu02IH8/FEjfhBx1Sdp2IRGIbFx+efbCJgixAAQgWeECn7y65X4Z9hpzD6filkme]] ..
    [[1RXKQSjf9BViqK8+TvhQbSkFfE79BUJpJgAvE86owR7NPDSdJEmPCY5I9rs8PeePhtMld4KOjppAKBMtdybB9+2cdBpSyX1iwZ58]] ..
    [[PtvFfAnZfDTIay9RbOrbf29Gy9R7HLPv107LLU1oxkuIaznWqmVerk997d2Ht319oo7HBpwc9U8i1drFl+eXlwitDMsE9WecGwf/]] ..
    [[DNaz8O0rqvY4FYIl5bdbJl6gMg4lYgqWNFzwHMAm+XE1+GP53aFs5g16uKfxN8db3EYX1wvUwewEHTFkLsUnR9e/SLpoHJiZ+/Qw]] ..
    [[ZBV/J5X8Ob5IEe8oTREAl8++l7BweHCfEMMJeqNhNn1ckNr+2KNzK8GEJA8Cwkr6LB7bg8mfQFjvzJHa9+EoU8kZ+ce1gEt8yJtm]] ..
    [[i0bUw7sQMgFQG+yTxQ1puCYuK3sQ/wIqO3CmfxjnQWuh6UTLUj7x68XJUIF9//U3WJi3VfSAxDmQlaAkH6iIudvaOR8FALR5T6+b]] ..
    [[kGdSowlezMrKrJ51IBqrKJFInRSSxzXb6zEQnbIePWSyj44oAbeRTJHTnAawATinSD+Cll3roe88CKqZbw3eX7dT3NL6MZ4lX5hn]] ..
    [[imX6nJ2+kcBxYv4ag8R7wYxTeG86eUmxOpIVR6dZIfjYZT9JTFNpkGKtgt+WBVqomvz85zfvze/6SxlKbisZfGlJ3kBzPAyOMW8/]] ..
    [[q7uN4JzlVSKIa2KfiUp9ZIHRnhle5bkZvEHPZjqgo3hOfRJi66XnOgZ3wLfVNXGA0lYbRApifw6mIzC8ZGjIJQb2yNsBIbTebZcm]] ..
    [[48GYfKjgu8hqYPlD2L3lcQVdw+gERVwIevp1GIu4ijHbx8zNkJXCYThawt189IR6gEDo+lMWaqSWwmujTK9GeTKMLHvRZ1KUDG6u]] ..
    [[/a6py629skWIr/DtZU9iHw+FT6ZCqVTUGZjhrBJ/L87G8L2i6PvulHH6jgh4KDT9X3SFJQGA6QW0wuUqx9PsLL/sMEiAFDqIdzbF]] ..
    [[3gsB6ZsFZBUknAQ3XYFOR0BvjK9whFtBxe0jGWgtQ4FoXBj4pMc3iNSIrWDt21VLdvEcSF1W6pmssHvmZpNWW4uX8otfy2LPYSK/]] ..
    [[wNVzXkwGjvuHeIDFGpPxSnUwbOYM2OtPnIV+E7gowxpWmlrCcPVGvsdoUSiiLEPXCcnygztcg0sIFw6B5JPEi+xUe38Pm/FOVdoR]] ..
    [[Qef2VqsbJsXrAoMMW7YChnjCeJFJTAq1Q+mlKDQu+vGIJ6bzDAusc+Et6gvPLmiISR++E4ZDWGJH1YZNEITZtpZ3OlisdMpqKFmI]] ..
    [[JjlbpKQnksQKa8621LDRy3dbjKl6aiCVlMNX7XK+OQGA/MLxIy9oR4aPJZlehM/bhIldom0WkdY1645tuW0GvBzWbwckkEXBaKeA]] ..
    [[aewnB3X7BVdvbj9/4tO+lnoq2u1zENL8PRFbFvWr3x3bgmXhHvpHqTI3FkNiy3oq5ei3+94Bw9XU8EfdsDsDRBRbtprHPHeo2hyk]] ..
    [[BLZ4AnEm1/OZF0jJvIHjW0xxA7XMWh26hOshBOjsfPabfHhVqEnOWGBwfD/sloTlNrYy2ggMRNyJIR0vHFKpTF/GCMoh9z/1RLLq]]
) ..
(
    [[yyiZGuk+GFigYryeFSBjmzKa5MNJHblveMayrKoWQq0b5dydYwRGCta5leabiQAnHFzFy3/DxFxci9oWeeRWJULG19d80fwEfvtC]] ..
    [[DuSyr2zKZs4S6KaS1SRVf0qkzauD6iMADff5uw5n6tnG8qEQiaBngyuxfGdg6VnQFZmnMVQ6ZeyR+7QZBTjURMWpnqzjtb+Uw577]] ..
    [[+Ty1QyRaTskRtq4rPX9uRpKnGKmntJVbnQBPCoMbfuGrMvDIHHZFjUL2Az4Xvq5KGJ+m9/+Bvfejv+V3bBm+1j5LISwY9SdSkseh]] ..
    [[yXPk4WJNhh04zffG1rropjcJOAifyD/uhkEGrwM1o0taAgU8EszCLQND1FnnCiuI6m/WQ06vRGJ7TeVVyje0DmRnRsxElXiYgn5z]] ..
    [[iaGijXFdnAKB/4kj+hs616n5pMUu15rcINDY27AememkosIpVYZrfm7ACbb1+Yuoay+jbWdKSNLV31Acy6atActcJwhnD3mITfm3]] ..
    [[tIwU1G93C1TnyyjiREMIHL8AAj06wslVyqCEWjVRUXl4S56FXI9EWSwNjh2gyraLR9ROqrtOnKLdmMZcSheAQECe4k9wrSqkySI3]] ..
    [[csF2RRFRCG7c7/SCVc4X00fWq6gshPUjaajF7LX+Pxs0nKek3dIddu7SxPUFe8bQQze6cII1hwSt3vSHD+Q+NP/84bH/qqY0uXpC]] ..
    [[o1PBlafqpkfpkJSXxoYv67X8J5VOorKIsAcR6BV9WxGVESDRlZ5VOmxFQNT1dIpO4PELJEeWkSqK4JI5Mxefmq+IpOhK9CFUqSLX]] ..
    [[S7pNfisiPwyMqLexLtUpNzywPsyk7PpriVLBfocwSpW+iNRviYl8De+fvkLNg/qCoLgrdKhe0KnbkCwvPYf4fPem3LQcY+rhISIu]] ..
    [[sn6rVECw25SPyIsCtVaG1agJlGSkT9y7+Yw1lLH6U+r2cGxc6DBwn63UfSTeZvQyaXb7ab2Afn39ymY1EVhiNbpi5uVhnOZpNZZ+]] ..
    [[Eo1RCkxZVmoqtMqpkBMLohNzt76CsNfivzBbTcmpZ4Gx/r5XCAK6UuasMxEr85zqomcGJBZjQ/GtKaz7Gy98leqtAqzOxcQ1zjqV]] ..
    [[8IgmHTsxATcJtvJJkn4yp23DFugjdq7WTuNa0p2ih6NfEAJuaOssgXSptxl0eWj6Vq8hUhNsrYrLXpXivQyEccrIuXKUxGo8l9Yt]] ..
    [[SIXMVlIcQ4+VyKEJdQva6DGAmXMChZR95E5nFJOSebjd293psfve88Z5SUs7NW5STxmfohkKPekN5RYrEHd73lCr8ViVakzizL4E]] ..
    [[7OkRuc3krnIOQcCgCmqBcu8Lu6+mhhs0Iq29TQa5SqmbIYLlUiHW2z2pdbCT5ikHLieOhtPfXnco90kGbcH6KNe8rOUxhVlZ0RNL]] ..
    [[NI8gUqGrSN1aXJnTSW2DF4Jv5eNX3isimrpvHDRtMcFYqr2goU5d8bTKBCrv1kmc4z6hCbATdAuwtcYdc7MGaimGruYfOGPpqciD]] ..
    [[oNsRV0kyrF3tBwEWK5TNrRL6AMMRCxk+9kKTAF1uKEiQUPur2xVNDNLDZ8vqCb2MICiZwvsKaAfbNYARxVE4rf2nC+bpoUQ9yQKz]] ..
    [[yb0KrBmIBIKnZgRODkYt+2jm3C0Ti9ADBQv+B8JXzrGCbg01ak4Bxxr8WIrJmoii2kc91N6yU2fE95NUuybAZB7Fa1oICceHV6pW]] ..
    [[xwU2lu7eBVuflpHNAMcP30vfKP/uiswrnnr14gtryoW5aG1peeshUCzY+RacGrLznq4MJ1CtombGFFG9dt02bBMLloWa8mZtKIvh]] ..
    [[n4zE8lRhTOXT4WqAsLzhxB0vB5fgGENSXoIPWlbma4z8HsJ5D2Vo1ZFxcv4YghJLel6T/j5E9Dii+XLOeR+PMcf3cexhZbLzsKxw]] ..
    [[OibLPlfDXXln6AOss2as7K1+TzsMOsBlV8CQyf4+SJnDdFR0hS4fM6EX4jSMOyXxp7yVVdDVEvpgSxzULq+KyJCnlaOpRTUVJScY]] ..
    [[9dYM8SzXDWCWwpvMpEiA8FIuHntHFZKGIp+Rkq2//y4UYG0oc2xMBdZTZIcwNnKRy47QIQjABOm0rOXBEId6VZQLcVPUmfE+1vQo]] ..
    [[xAsVgbtjEGu8EASopPvxJrA4vZ1hRukdhd+PiD88CZRbMLP40PSeUDIN5Jp9zbhlbSpFh8Z8iBcIJYyUf+J1OqZtSWUg0atU08AM]] ..
    [[P33Vp0oIVA9sxBUoOkC9lKUD1d6GSMGgH9ggHc/dRZnCSNrgg1sKHOfEsLD3DpaAPcCFJMDaku0DrjSxeO48xG+Rbd+fFTSXWaql]] ..
    [[MtUnsNOPfvCIY6yWW49oRJYNtWwveAAiEGx9Gl5XN099xNxscuMt7OGeOpUnf2JLBl/QtaWhyCzzpOuMxythVr1EVV8ejQ4CudvN]]
) ..
(
    [[8qIWO7R7LJ+KyIWrRS50iA6CzXatkH64vbLrJhqpwOw09pavRekxRnVmU+eCGplqlwOfhhB2eNYoOmV3Q1YHSyni9K3omg2wIu0i]] ..
    [[G3uKWZOxBORLpC3xLZlGTKbtuO9dJxLrGCsEuywTUYZNwJeE3oIGWmCb8gvRhKcYC1EhnL/0MDb6HdClpipGVApj+hiDMQfTR9sK]] ..
    [[0FXIyhIj1GfMgjT45vf5T6onH093IJfqi34aWQ/gBkOJvv/2aq+ZB8P6D/YNb/MZD8mhJ5lph900pCvQ2vW5pR5/QhpAFDmGeZ2I]] ..
    [[eh8yeY3/9man4J/L7TwjwzRD/gB56b5H/uUZP8sJd7CSx/Usk3zeY6WIoEoj8BXT0c55/kUSfy/1A7wWuXGBS4tVxQwK5r/GwHAy]] ..
    [[wX6VEEA5KKJ151oODaUxAoMHmGT3hgACSVLiEkAFFkpgN2nnCAQgBeSgTAqkVlM4jnYP4h19tF+id6zo+E+jeofYAzdodvXfzAFc]] ..
    [[QHLA7+iYgMONIDzhcfcIYCEgh/d5TAYjos8gKmgRxRuiuIDiyf+AyVamWZsFafcne4AIy/gIEDI0/KGQfUKG1ntACOOjhSbK4wYi]] ..
    [[BZADt48TARA4OAgpLqoBiBlY2nJ/MlsaVwsCApURAOHOjZAK5kSkcgYbmogZZICnLECfS0GXKwue1zhgscKbXAkRqLhrdjBnZc4S]] ..
    [[IhAys5JoG9tWIISTEYOL5gBkzsAIIrMqPk1l9i2AAKR0HhrBgMzUPhngtEDuzE2YR4X0LWCMzcW4kgZgzTldXhDMwCuRpm6psz7c]] ..
    [[KKPDryLex4A5TaxyMDdRU7EjV4aaEBMCJhBwfA6I+dn8jKxn6U+uqVHgC4svjAxQ8F3PkBECMw1UGCMl7iSMAVBgdcRggMfT8DQY]] ..
    [[IXzp/+r0UKCArVQwVJOQwPfxAAUsVJoYLrq1DBk3IUoHCVoYLgNag1Gg+FXXIgwTZDT0QIwXI9H/9BAdj5vbqTAo8wjvD21Z8dgG]] ..
    [[IH3iXGDt5eHSh4LDEE2Gc6X/QgeA3qVXQpsYXElLtHFGUwHXwrzAB4dBrP8M4quPDIgguXcORAxhhiM8bg9E/PH2h44o8amGGah4]] ..
    [[g/QH70MjGJlyzuH+REkiIXyzPrP/2lH+DSfJcev4B59EuOYdjcBRi1cKWdnDNsYYe5YkcKp/tIQ4LNCLwzT/2wzBQrWrd8hMEZyL]] ..
    [[DoIiOIAVBRSeEKOBaQELSA4phgzAKk9U2mTQ1YfNUZsHCEJsCYzuXHK6y4gFV3lMRvNrMZ/2GiFq5sSyd9CsUw9JCSLEyoZGw+7w]] ..
    [[ormDkH9glLOGhhp7W+arP1cD4rEK849zkEO0G3pa1PbbZPmnV9Awx2OBNwQfoSDmIA0QoriOCKSNvZRklxpovEM6wwiRnEsYIYdh]] ..
    [[zFiKglpXgtcwACzpe7zCAGUDvL6Dnuzr0B+e2lShSpJHVC8tMyacaeHQKBMovNWCqcaSwjRW8lBEussIgz49iKcSdQSshanpHAYA]] ..
    [[S3aQRjPfUziSkormgGgUnnjWgkRPjsuIadx2DFNCqHB3vHp3MEv2nXs4Or6noGlU4DKxdCdRWXbH5mFX98Jtue3WloFTZffuL7nD]] ..
    [[nqhD5kq7PXn9hWZ3Cxx4fveKZWzV21OgNanUH1m5frdmaWa1w1PFs1PFs1PFs1PFs1PFs1PFs1PFs1PHt8Dc+AEr7xJ7Hz2XW9j4]] ..
    [[iSeZFKyLowWpk8JZ3O1G4vCR1izmx35ihzfKmNz2Kw8dmtVeOzT2TjM4uOfXYan4n69hfveQbXr38ELc/M9i9Jfc+U0qSX1QLNKC]] ..
    [[Gvd0HrTJnVp0oE/YPQbzdW/dCe0X5oets7syGao6K/q4+T1lzNagjKjhjUlZ5oSd0pktrvwF0J7G4IRiu1JZukac3eLtAjDcwuhd]] ..
    [[qliWZqdmXnJVumJfWPsHpVGH2mztE6zdWliTd4M5qand0ozehT4UhvMhuBxWCbjppEUKwJzCV1T1M6hHRvuXI3zFY6soPa2b1NtG]] ..
    [[ZqXlIzNaVNptEsTe1dpzbISugiZvVMi6+gZ5rdQwZsj5bQ2g3onGY0YqvyF1HhGdhrK6FxmnFy5iW4KZrROc08EaOfFXiopml6J0]] ..
    [[CrY9qi3sfpmLgONNeiWiPlsrDgmJcp+qXcHp3Ovc67RtM0tePRS2q3NOKYZ09JDyatQ9oNvUMaUCbR1RdN65MJd2kCTjWJXk/uPm]] ..
    [[ifSm5rBvRBg/pqKU3JXlw62QpqxpXQPlJ0SkvsWAakICQ347pYDzW9Lxkc/oebpynoXxVhR/s3q3Oa0a3M1TfNaDh3rsZpQKqu2a]] ..
    [[5Nz/ay+qMBvcjMLCerZZp6ClDpj6f30YNzlyp7/SGX2M5GDLY9S273BzZw7n7FzjDSOoKKPmhJRyMdnRM1B5uupVLF5NLbo5l9qZ]]
) ..
(
    [[Zri2Yn9esds6Euk86EMVeGmdYv09FJ+5xt0bSOq7xFrKtD3EN1QTM69vKzZD/5z/8Q6H7m7qB7jjZoao9crQcblPeu9ut2tD7WBZ]] ..
    [[Q8w1u+71lCV2a48Z/WqxlMGLK7QJ/VAS2hxZ3ogrY5xYedX3jyu51dqPDpnY+BesnGkeaH6XFm4rVVPVPgqPJfcNUzDV5DwrfVm0]] ..
    [[6HOOpgJISzxuKPvYFZcBMcJOu9eM5DzQ9d/xTO2ll1NFum4mlvVfF0iePK7grgrsPK5zh5/OiOGbsS3O3s2POfMQZz8VedyT7hB4]] ..
    [[nPcWD4kkuKnnW0V8aVXgdtGc/bPPPo7hNfIfRcZ3Uf83ncJ63/F3BSzzow+PRU8VxcqIHXm/DBzIseZn1M51bPdz414dTpOqguyP]] ..
    [[G19DkLXiacE1XC3s5jnuCRTucBTasN25nh9Cs8pikAMZS8o7OWyx/OdB3YhjuoAyczzbPBYPHPRHsRvAWfm7MKFoOnNJfvdmN3Z7]] ..
    [[LYR5j+TKhnZR+ITOr1CLLY5rHFpY7Dgec1E+tygvXLkk7zLdXo5cULUKVgcWrrdCVwsFavIgrTiq5DwEscs02oK3KJRzgd9eWMY5]] ..
    [[wuLhc8fH6BQpRABNBZZEMpzKHV4U08LWuch3dWzDizKKSsW+UsEWEd21wnI4Y0TpxwJBI8dp9QBorli/wJeK7WWZUyocZ0wklOuK]] ..
    [[qVfYgTiM456mSVaciJV6n8mSvtYvUYidsfPARxe1nNqpZgc/35ZF4a41iiGASBYGezvC6N9wwQvjeWqU255CnzJ7lE5YrNfXxFKd]] ..
    [[c+fwlsrmmBnoFqk2fSt2e2q3r5Uvjcy2495TCHl0HnPh2tpy6zfOTaivVNYn0tEPust6D69PIM8sO3mTqr/uOXzkUdo80rEBhRJU]] ..
    [[IVvP+ElYZckm5OIiJA0tkohnR1bLPEuvIF/lZCi6mE9gRnN5J6xOUbL51oNihISTG/cwVFEx8Tz6zl8H76nOTyFfDHZhAVYlyXKS]] ..
    [[WYSDpDibRuAiCpNZWLvbYbUYFhpcunrAHqEI7PX5S2BikXV8wKYq01Igss/QgRbVZaEBzSA3nqM8hf7hef2WWZy5SW0GQ1MDIzpJ]] ..
    [[Yhv500oh29dtQLtMhwmHU2Q7xqnppnxo4vkotrBA5s2voLVm3AhIi0kzrW8vqWqQ/orAF55fQyxLk36QnEVmlM9zjRSmBc87xFAp]] ..
    [[3JTa5kGpB6BeLIUIzYjI0kMLyJYWM4Ynvu0r0wUwtGxayoO5zkwXjmv7t0pOt8HZGcIUAgRrBkNyS7+Ge+N0Mv+1HqrWeVZv7fV5]] ..
    [[sffIUNjz4p2cPXXNnDCc2NcHGoq88MdtYjvVLOeNXW6LIY5P0rYJCTSrc+vkTg1CesZ9FTRD4rYBgXSFs8o4zzmybjTOtozIbIgM]] ..
    [[5jmH624MhilWz8TNHOry5NOz+mvkSSncXn4vexw/5EpDk/Mb2KroisvqJWRcktQBJSo8/fr8jis8/Tp+gZSKk2qVio6RDAzloU7F]] ..
    [[WQ5SCledkU+lldBkBC/XxpvSDhbob3Ye7YTcsnpECYyQxWyysz9eCcFD/IJgE0vxUKMNJinL3CErh/OBMHDAC4+GoZ4nnX5LacVD]] ..
    [[+UcWRF6i6f6HeQ2vuTKEJXTU7IFq908n6rhFTUHq7Od1HKf7m+IRDXD7OXCRlgrow6B7ea1CwRjgXwGn939oAMw4TO2HAkAIi22N]] ..
    [[Szk8R29Pk2AwpAtArsO+TITHez6yAzamdOAAEMIPX+3KGCpKZEYGKhFTgw4rN2rOEVR5cvO2DgCg/YoZpLDBgYWRZwxEbPq0jOxj]] ..
    [[x3LjoYRFOSzu0gckJCgBUyMCNsri5IUHq1K09gaSbekTgAk+bwiTFXKEWLYLIQwQ9d8ZVLzkZPSHSzIwTu5C843LFzgEsd8bz0l5]] ..
    [[/RgEH6h481YHApEQJYVzzLoYIL5ZpfRchglWH+9MQHUtefhvjAQ+aYp66+PIgdF3giE8xBQAsDjFWK+aqwyCrF/Kq4/ktIMX/i65]] ..
    [[Q8Cxnl4Hlw8+z/Odj5i2WSX6hmydOcSZ6U3nUZRUsWT3nRkisinc9bm8SRMrBU0MNJFwNsnjNkcPms8bJBiOyF88NhZkES61+GeG]] ..
    [[KgZbmDoYfidMvmkMOMsMXVm/wrkIMNksHL1BjJgjVG9IRym3NMYv1sdhbmgXUe0cWzw4S9g30H2O8L8MAAbQuE8S3y18wFAOh8F6]] ..
    [[m7TL64I1R9ieyvO7ddzf4EGdqEAMoFSGCNzrSpfWc0MbmZuos8NUlhM9gJBc4TIsh2/pYZtoZjxSAXvTS57Mro42SwFd68ZBYYjN]] ..
    [[fb/C8cOHYx1cGbe8fRyUGd9h2tTmZIN7H+nLz/6P+BNdVsHhL7GC0KpNny7d8Vcfl6nwiCaKIYfac4DWcYDXynQOvm/2YebePj6D]]
) ..
(
    [[vX/2CLtonKRe+r7YeC18Vbs2YVaJ+MEQRiuQRvkDFmbpcnSEaJMBZmk2Pk76ONtHfvXQQLyWNy4UE4job3wijGD+6Hg99jXTqv5+]] ..
    [[an0zCHu0uZDXZfLJNGU6wjtccam21hq43Dp0ALpszppzMPvpn64tY+a5iW/gYPMK6x5qTCL6BdrzAxUfLzm61MtVjO6403SVfSdF]] ..
    [[r4qaxZi9b4lHYbpO1PhWRr3ajEYmzh1cGdVXPZdqHAG22JHOveA9ICMZUj219M2C1y7yLtMBr9ntGatBRizY6vo0Xy+2iKSM/M2W]] ..
    [[S0KGNNITrRVcaT+Saag5D0fV2IYVUHshtsZny62O7Li7Ym49FpBUnOwh+OiQlRWscuWuwzLHxoUedhDV29KO8PD8XoFzk8hkWDN4]] ..
    [[6VX1TwrUvH+PV76EUoA/JPS3Phh1C5wG+V7+NN++vIR/vMt39c/Gef+ckd7+P3/uzt+A9/41tfEe3Xtqaz4WSGlMJzqvjSWfa2Ix]] ..
    [[KSxYLP5D64OWAyjFV+eIDeETc6Ixvgg+DzTKo3je3DOz9gySa+VQaf5YjVvpN8g/1OHof+f/a3WhOm4uieoLkAcXlE/ks/+/AbPm]] ..
    [[3egbQcHhLZRjs0nXevtFmr7uKvCcbIHxyE/Xmdv2qLtv3AQqW3ca6RGyq9XOusQYjVxrVl3JtW5W+Qi8l2ZIPCremNSxVdV6Ff0r]] ..
    [[z5Luk9yNurKL3d0KSTz3KJHdZIGmuOtT7eMW/ry5GhLUha3sVN/pnaN67DW6LwywxeIEjjrzeh/msd9Ruri0nTmIYWl9OONUObSw]] ..
    [[guHYd6P+mKy0XjQwtuqmMzWuEF69b8mo35YCGomSvVtl5FvCWRe6rwcCsetlDX7ZenktS60JTQmzmXQJGKIM9WExAtvd9fmV5Rp2]] ..
    [[YneF1/hjGVnTNu1nbvBbqgyTLe5hOu268Wghw5Y0tHi21l2C3zh8TG7Mq9pt+Q7zhQvLi4QJqF/xDeH/bjyDC2kDwQybjWklco+3]] ..
    [[Q3WTg1JcLWtS1vpG7uVuLWrgidizVpXON/FqgRjQtU+354iz2RJbN5bWN8rIvjrimLgsEWXZdE2Vv8N6WlGuxdTkTjrvTnyvizkm]] ..
    [[ik6bhx4MnXUz695Yv5OeEhgfSvqWpOGVtqR32xhnYJ7ZVsjLwF3mXX2lVsTsjPrQYy8GDEyJsqnKvSz+RsNI0fk2GyKbZ7aXVsFU]] ..
    [[F+0FQmSUw8MHXdN7n4Qyu7Q78iK/l8C3xQ3VyLW+Yn3fTr7mcEXt2eEi6oDCVw1Pc9AdbyRNn+P+JvE/8lIT4YrsFwTwdxJkSEwO]] ..
    [[CyQK9IJyT6v53voGFYB8bU3lMO2xwoHZQxAmj0Bqwm2O3dFXZbYbcVdlthtxV2W2G3FXZbYbcVdntqsNvtFXZbYbcVdlthtxV2W2]] ..
    [[G3FXZbYbcVdntqsNvXV9hthd1W2G2F3VbYbYXdVththd1W2O1pwG4sse63VgvwmBYARs2fHL2+tlLrF1Tr6bcvW6+/aev1rzycXl]] ..
    [[95fyvvb+X9rby/lfd3Fd5fgTSl2Fgxbyvdu9K9K9270r0r5m3FvK2YtxXz9lRETUmZ0BV2W2G3FXZbYbcVdltht6vAbvdX2O2C2G]] ..
    [[3tEbDrt1bY7emMmtLq7quo6eNagBU+XuHjFT5e4eMVPl7h44fBx94KHl80++Srj4Db/OrD4WOYW6NR09VZ0xWyWCGLFbJYIYsVsl]] ..
    [[hFTVdR0xXz9vScNV1lvK2w2wq7rbDbCrutsNsKu62w2wq7PR1RU0K8rQr0rsDbCrytwNsKvK3A2wq8rcDbCrw9FeCtSpvSMaUffZ]] ..
    [[d3zPqgEIWzYW/kFSKC3L5DW9N9QGxiAR9xiNk3H26fgenqmNvLD4bz1uQQ2eJwFiu6w4ZvkbkzIWUJYzkImxFwqj09GXWBu+p1aw]] ..
    [[t41UjX+KyD3kvNgVPrJ0CNiwEqBZW8lACuWn3ItG0N+dvdTDLxSWa1jWUpOxp++9u92SDLr1rsqh/n5M8Xwmq+ZCuQz5sLH9wiU1]] ..
    [[wa48XDaD8+v3NgWCH6CMiOOp2GTh9GTS6F9bvGFjyP2oIV1DKN/c6lpkzVwfXUb59n6IoC1bSYeyTwe5iDMdRToivmD9yoVQUFa3]] ..
    [[7fBa8rkWaDASTzuo6c1mqRAdCcdptsMCp4iichWmASNcS9kIv4Ds0+ZM4tVQnjF8DhavWm07A3wzJY4t04o+/lyBYSTTm3aYp0bj]] ..
    [[KP5IcFBnDEB1aj0VqhVi7XdvfqNb/lZ0otlw9Vj0yknQTdYScCAI/rqW0N5wBTh6DoINGRsVAc0PIUSqj6fGNgYcp638RYAA1hrg]] ..
    [[e2q9H3rKn9rTppzErfnsqN53mplvKp0Ngpei1a2gEeOrtWSJR6J9rLuFkrl3K+8jFvHOwrN+Kf1ZTP8EtdV4TlCR4lk94neIS5J3]]
) ..
(
    [[x8rBkw1TdO0sjByLSmtKcyttkj3kt5bYtoTAQcaT/XFhGkOEizXrAYopaRiajdx51gcQdYVvHuo9StimgYTxRIRWmPPQiV1t5B2m]] ..
    [[oyztuP+3qLavzDwma7iWkl0R+aNGpPbUfHk8n8CDcEX7T1LuLC+xE3o62nOwvZjJpfAzctJz3BixOqSO78AGgpb/eHf7XB72QOHW]] ..
    [[gCL3pg3/ZxJ+9wsDkaThfbc72jeoXiMPTn7GQ6j2tGw3vldbiEkNXDhj5uGxezzt4d4GPc1rtpTcNG0avp7eOzqZbex5192tT6k9]] ..
    [[MPP37vIyryu+Hxfjioszbz6GUm9LJY9HzOHpKfZD5+709vk/91TpCQURyDO6Mj8aIN4wvtctk3O7ijYVpr0X2hgOdhq46MmHivwm]] ..
    [[Q0Qh4U3h9EguKyEFc0sFj0t8YLl8OWWnxS7427nn9Eho0njyHSCK+i8uKsHXtKip0QsptSrK2e9PYb+V6FrhIHCGUi3+zdrle5OF]] ..
    [[FsUURQGg+3SX9DxYc/WbZ8pxdvoouV6W2eHu9PRkVFiZir4n/83m/ThazwW5He9Kl6bz+azPbl3q1Wmu3CrSbZlbfubQCbnO8duZ]] ..
    [[XprcpH0wy5Gba2Uqg3hCpUFAkX/V1dUbRmYW9OmtHX0GuUqpmyGC5VFx1tc9qXB68hlDw5RvjQD6PSGA26N5+IaRQjlrPItEPwzV]] ..
    [[Re7p0O0qH7wxGSgkKmvJvpNoUMMTZuysTNNBu7phBwJRS81ie4Hzm889AYV/farr4fBXjKtuvmQmbFQrYNmaAqPl/wMxWEH+9NxV]] ..
    [[OwiXm1pk90NlXjN+bLuX00RW9Epvmn7x0cHOq7gklHvjkZDQdNLBMZLjgUk3kNUx67X65qq1VMiUHwZwZpS0e0ZsPDw3C2kys16/]] ..
    [[nyXquL/n8y6WMFR8aGoDyg7LmMWYMI7rxrvHoRVH8+nhC0qE1pjqTSsXd7C+sqAlOxluavU+E3Jth/K1su/fIvZ/wc9LxMyucbiy]] ..
    [[4f1lfX5JtZag7Q7FmvcETmPv22ZdqQzugZC2SsONJn65DRJLY3BoxBURiDpipelpm+zaejpYkJ16vtQYh8xiNpTMhkbSLHU0wfee]] ..
    [[P0oCUUhmqyiYtTVwYQ+7p9U022XPrZZEpMArY+bf6gnBjKEMkQjQhwtUz5NTlHt605Mt6PU/2KvQm8hty/XEar/CO2Lk1Nlqg0IF]] ..
    [[1WYZqcLqMUkueEJNy29FTTGiyyQgjh9uYnUa6aw68ltbEyhSab0zNfKkmvKpZAIRcaclHUqZdSwsGcZceUm4gbb+wOB/MjryYU7y]] ..
    [[FTVOUf/ZGNM6SisI0XlcKP3/uTH+H//ZGQOfYA/kCOZOWOVNc/h1xPvI5cPPH3aw19m2dm81yhnGlBqiK41gYsRXuKdI5tJC1sd1]] ..
    [[vRAAa28yEUh4z/fz8g/wvWrbmqjRmQk+a5GU6R24zF4mvw6xOTBmk1pFv59fnBYdicHMyxXfRAZN9VYA3dCq/I9abmXt9hmg2qUd]] ..
    [[5QfBl3xDN07CRhCl1iw9gqbKwtiAiuCi3eUDcMueELtRlFdthcoCFEi2K/F833e7Pv1vtHvfE4HLWGjC99rqF8Up9E9f78g5byUT]] ..
    [[sKqZVZNOQ7s70qMTY25XgrFdvVUqHmS/2WHYXjAf4mny3nq7m29CjUZbAxqiJAfL52mCmh6u9mDy9E/gGhHrWdhDxL7oRobqGUSG]] ..
    [[Uj15Esc0abctkVTbkTP6mlvmaNBbg8U2NsLYI0vEmQX7RrriGDE/lsd6+SNzZLMSXIZ+aTKZLf0rGiiq58Ps7NUS+KdCmBECDRFp]] ..
    [[aaM3Su3AsqQys+NBa40aOjmmBH/gBPaKFYrmUzZQAm+EgPWq4rUyo//aUf3L4tdx3zCQzMWRSY03TFtxY1rmG5rAZvaAoo2+vfPZ]] ..
    [[xh51ho3v9KNW/L2m5o1f9yac6VhCJSQjCEfh8ejolzZ2A7P1VCKFa1DdT2FY8m0VyxfnFrhN/UsH+M07YGRqIhmXIZUIbCpjOIyv]] ..
    [[9uYpDic8VfGmPVv9gZS6z4VUW1KQBQTLBuNKVnbDiL/HKVftBRdza1NVc3mVQNgGCL7wxxE14Ys5JyPFQR+pqNo5RYPePnqxVusK]] ..
    [[VfIZaMi1AHQqHIFtYMhU6G38DCS6eNCUMstiNRw0SpL9oM84S9gbrsSDrY/L/V1M0ApSbwE6SSYEYJ5pbIphZKYkNdADGNFj6TPp]] ..
    [[uml6sUb3Fluqa7XkLGtHX1Uy0NSNdm+yTe8g0FvDHEDVvGrtfUeKnm5GTWx8FHEzIxmNrWnV4+KrE3tTfa6R+djO+GA8ORum25NX]] ..
    [[W0iHO0CUfChtbJczaV35tMDPYbVbOE36zORiGlgWP71oRoCmXzBc+rTEzwTlWKM00Msd0b0FXlUiVEiahP+oMXBMr30U5C87aRk4]]
) ..
(
    [[aMg0u6OwqTMbF4L1m2g8/xrm63bNpD4GJ+54Y0UQhc0HAI3RKZwo7qBlighzznRSnzttcDeGUIZekIT1HeVT42KkdSxW3wwRoaob]] ..
    [[PwGW+mYkX7MwXasZ1qWX+xQjZ0LnolQRzGNUMpYmaoIX0NPlDr/jyomUTvBJ6PH1TWDE4sucTbNruQv4/V7HrqZ6rcjFDpjHdBO1]] ..
    [[4aEzMOMIdd6X/WR71+SIQGuSSZza18zlp6irnFXHAREUozeLsDeQNIVW8dHuwh5DQ//Sj19/TwwQJh5OhkhgktzcgW+0NqOrBpQX]] ..
    [[t1NDweomFv3vprt0hWBPGVxlh/o2ePcJy83seivIkANl/VbaTn5tlTf4KkuxadHB9PxiLQx6Mjlf4wc4gACNOZFRou53co4p2Ofh]] ..
    [[K35eYYHovZ+0p5OhveQ0uaOZn1ot/haHFRGnCGjqiWzePeg1SehE9eqtCgJkL8ODwZZ069zIMv8Jh1qkBhG/XsSQC7enK8j4OuuQ]] ..
    [[hrgLpw1bnsVChfTWWkKCJQjlBJcHOPq2+sS5v9yTSsDA8RnsQvywIh6V8tz9CU8Qj9KyRloDTeQiKFxrjY3D/0BdOj6XFfAVP8ie]] ..
    [[VDYvXJWwRvtveQhJ00p2E/NznuDcc+wtPDWaoush+H0xDbCZ7GSSk3Ep8a3419PBC23Fz4tPdH4/q3dFw1A9fFlaMRyaqi4/JkAK]] ..
    [[XQH+K3fFHV/+kvVujv+VuQy5FbOUHATSVLdFwIRk3axkj0BPBLDqngYL5OnpEAPMmjqOz1h3ytOxt6IITk8pwZB4HUbm2EtmA4w8]] ..
    [[JCWY4ijUn7qcbAUh2+ZmLY/k6IgXjb+xR8oQVKgYGPErptREQ1hgGzoPKwYmjiTBgSfWgNAEON4NoRNp34MdIvwSnR+pyy0X3hrN]] ..
    [[hIk84hVsEtdGMkQ6NBei8hYrKNZZBpIp9sHCpKLKtzTY+g1OTtyfQKzmpHvkb3luWA5XtYWf0BiXl/+GWmcbjDUNlHZuDuaBih+Z]] ..
    [[pHH7iys4g2ell4xzs0Was1uRuOgzSehL2iX2vX97aQHiuToPVe591tkdEXxRW0Jn2kNxRflmhJFukuEQWI0wUzp29mHqTfKZA8oq]] ..
    [[7HsgBT6G+ZKU0S7RBEDNODKh+wts1K4q1+0zxbQ5Kjog92yP3tHCMtichKTaKjQlJI/oul9AZX5Wdlu5T4QLue+GfgJSQ3UvvxYl]] ..
    [[nkGuKnASkyQDbMTqRkISlZU8Q+6skCSSlfcJpjWR1CXN6jooAUTed2zDI/hJQp+VHnEbTPgIKGPW5VpFT5KdKM/3rmdC3z4C89Lu]] ..
    [[HRJ2MJ6XmpTtWSnmR5hiTpC3BBubpxxXKl7aPzC5nYVXpSH5TZkqrvMx6RA5jP+PwTnESJUAdCIp4QKfvLrlfhn+Hcmuj7JZ7jGc]] ..
    [[U8lxP9g6xUxNJSFxoSjIM0v4N1skU8jyJrPPZqbzRS8jnlj2uzw954+G0yV3go6OkHvZPRXM18FGP78Mt+72Q+yXJppemQD7fzXg]] ..
    [[V3Xs7PlHLK1ls4t97aU7P1Pv0odtmnn45dltqaEU4inO1UM61SJ7/37sbeu7vWRqHTTqnBli7WjGYrD04RpBn2ySovZC7FfwrSuk]] ..
    [[NlIeNtmtlDtkx9AJCthR5224qeA50FnjMJY1t4nF2vKv5N0Oj1Evd8gutl8gCOmraQmyBFlz4867mzL5oG7CfE0Q4ZEl3X560Eiz]] ..
    [[JzNslIrj1suoXJwV6r8Fcjf6bKGGui+20eIUfQq2jIPDYzKnB4pjIcjPGd8S2iRXDLnHdC2ikM1/PbvShCW5eCczB0UxHonR4kI8]] ..
    [[wA2SlxEyHYwenmUdi/a/nscL7EjvREmPtiJE9ormJWuIpViZbxKD5Vl0/WfTUxWHoH/K/3sViMJvOsTzIwd/aORsKd5rkXP7dU7o]] ..
    [[V8KBVEK2CQlG9Rl69uRI12yKD1oMCOfJYrB4PKt5/akUuoZK8kpl9obh8lC6vygZRQIMEVPuE3jIwK4gTRERP2JCkZA86wqOqyE5]] ..
    [[NMuuokPxoNp+h1FttkUuiu2KG8EJ30Lb5FFnqSRlnxxdCs/7c//I1vvR3/q6ZCR4hzG9t0I1FTP4CzFoCcD8mhIdkQc65JvZkWAk]] ..
    [[U6Bu744RbTLl3PzhihfGL6+1aK07ZYqWBNY8rQLPyYnZESPmsxRexsURI+C4YJyMGvqsLAYSmw2SK0bYU6tl6/JieWEgdwllZzoC]] ..
    [[eUygizQkQpAagCkYXAqwsFKI4ryHVQNnxFvC6Js7PBcTVQJmqgwqZa33ba/GU9RV0FXkKCX0PTzERPCjZf0JSUc0ELoAgqIU2ESf]] ..
    [[dte7tQxdr/+L3/0PjTv/PGh35zABDYZmKNYJx2pJnpegrxECyTXGPSmWaGXKHZaONFwkR0VCdrfHI8fs5X6UKewcKITyCw0SQACu]]
) ..
(
    [[3sKNOfTaII8+WLulxdY6Ps2jNFBc5I8qyo86QQ6Xp2j7KbKT9WI8hVEP3RbwvWOI++6UcfqLCYwsZP1fcwsm+G4SAcNMlFCg7Mk9]] ..
    [[MCP0wAnzC4fjjKw+U22AeMFHIkCZKqrryCqc+A5XkS50sth6R19K1geO6lwLBY9VlyeI1yeDXgMNcWAeU4Ll6q5vKBP7DSzj5+74]] ..
    [[9prhU+XEoFOkopLKqu8xVbgPkBKzeSxttL/SFXBeUJNUgcuSnGHqeJi/1JRbqumLBciIbo2WHJygDdQVoqzcaoKeXSEGRTLQP90q]] ..
    [[clpp4xNlOo1vxmOdNs+twiKyp4W74FztPgE6dcUefaikOGBUPD494h5VXIYirnMIosGEnNQVdFz9qCNGgsBCkX9LNmPxyHsZmGUD]] ..
    [[STUrT8t/IB8p44AF6YkeWSsLcLR0rctnzh2BFxB46xINVFNQKhG5CLntvL1trVXHOvs1HlU6xgroS8OuFGGOBEIHn1YxlCXbjS73]] ..
    [[aYsSTvz0FK8LIzC68mno81U72pZc28YJsGCfTdZx6Y+W75eYJ7WxKpqGInP40bbJyqzKnjwuGqBQ850YehvdgegImVFS2kFOuhCZ]] ..
    [[afVqDn/Ys0HpJJacZHja6zVFPtlmRqO6bqYG5oQ50xpqH+C7XtSjiEvMPmyexeGGuhMSSQArIFdgZ5S8q3iqG0tIZPaYBDAOIhl6]] ..
    [[VtEk/wa+V8E8gJZNAnm+LesyZ/2/L5sZ03UqQr2lXIQG3u6ZFZH/m+xdFkvzfCIyYTESdl+AVpsYlzw4ODYf9kND+lPytSVSpZAo]] ..
    [[mvu2tQAgNx0kX+h4rXsikjM5mJRtFzZ+epZ+mC1/b2xc7m+kj4rjU6q0oKvSZQVJ3LVDw9O9NKwquyjaBkWZkw0mdmS3V5E84Pql]] ..
    [[Hl7hqzUMyOoc1JUFNhOEOWc0yi/2xyfK9ENrhI2Fs2F5EtnJLoaGbcMVDVUAYGQCs2EXg11+pH08LJaNTpjU5CpDNm81hPxNPURx]] ..
    [[Gpj230AyYKNzQ9xxJnmloUncfHtQS7VMcGt+R+deld6aSH5n1oX2msHJFPKNFOEGrIubN0c1HoZiJL1P+XOXhfss8ZsIXwhY5S90]] ..
    [[Tm4/f+J8tjT0hLXviqpsYrTw9qAhl12hJkU809pOsmo3shTVEmGD1FXrBGHK5WprrzzlY+U8777+QylUwx7zuODlopeM4MbqajkC]] ..
    [[oF8+j8AXx+EsxXQQpadYJJuJLOJ5q5P2OxYyVlfeFOo8PIZXwYKrHn/0gXcnP/UGYwmE41kgFlufgs18WtuIJw5ehpaXleXZon5d]] ..
    [[SjI5exSE38JnHQmTrIeiopQJVaVW4EYjbzU8w2cZdJ7vrAA7P6nNmRznRSIzGOJrHKyL4QxX11zuKq4jDgrdfQiRPMr2hmVU9zF1]] ..
    [[bHKltRFV/R6djV7qvY8JpIzaE7KK5oVzJrSzBa7xijbuV4p5bN5YvVpyl+GPqThHUOysoF+iIiwlDojUb7SFULHN8YOA9lKARm8H]] ..
    [[KQ1olB5XXOmxuHxFzSr/4UvXuIsJFI6I4WZbpvzZw2qoV3+hg2EK0SfRC8Sc7cV5Gzeo+VdWGrRc0xPq2fQ7Y6+vCoRS3bVp2ZQj]] ..
    [[OVskPuSwDeFjLnSBjH2MQs2vJztSBHTX5MMUQVSR12kmS6mLzCpPefa8jvhDX/dywN6bPyO8yLTghlK1kzFsZszGhSND6jQG4fxV]] ..
    [[UKUThGRUIj31iWTBBhAnGsu6m8IfIUyOukGvp01GqbC1pVilRWwC+6qMhLir3pmvo48VLMX8e4F68K3dDX62zwItMy7pirwwttfo]] ..
    [[EscE7D3zTCz/AWrq+gDFbkhRo3JIm7+AUyuOaWeHdCueRHYaUXjqL5bHKszRp0s9rJHCOlVJu9w+ZkNiaH88Lx4fzoWlMXF16EUP]] ..
    [[xOVHGwHtP12spnCpHso19LeEUDCL9ck7dktWLNOejeebulLYnItHXlxjUNmSaHPekt2qpQYoN+imPqcZ0JvXl5kFae3I5CKnGU2G]] ..
    [[fzRvY6k9ymMj9KZTDxyPzxdH6qb5Nde7uSqxa+/IJ4k5gP8GWZDrHyVWWEWHzbhsAo5yJabMh0tCKqZPxAgk82KRSmeXXlOqoqSB]] ..
    [[6roB7i4PXDE6Sah70xwkPjgxNqGXrRURnNRxTX1Bdip3mV5cAiEg44QsVU3hF+0YHUHUgzGGni5dnJOCSzgwBOHLymjNBUVS/UWJ]] ..
    [[aqUCuqUMkzweyEFFER98NwOhwfYrB6N4xwcrFYKrr/+QwZ6oA/AgmEMbe0DNEMiykasayfUlblz1OWnoP9V7TFyMr6VCTaok/7ws]] ..
    [[r0F3sc39dH+BWf4ohgk9D1KmRWkdkjiHazF/XJQuf3J+MKye5XJUEsZZWpRl4Ps86LywhJDdK6SEuIFNf4AOnRyGihagG6odZM1c]]
) ..
(
    [[qVmiFDXOM22IQpCshOE6C39oA0fm2+fc98uDgjZgg1cXiZqYcHjCCFKO8opqahXMoOdxPqcw+hWd0gd99Ur2X8DaHrM/SyhTokRf]] ..
    [[mqepofA9phfDtet7hl7m8Cw8jNNDWonYF8nxjTTfHEeAdn+bPaYb8rwxoqgt7uiajjNs4i2iN+cem494AqpufKvTleJ5amXaJ/Id]] ..
    [[32Ik8euXNfVHhDkHNEUFNdeQLPYke/xSx9b3w3itUw5NYhrY93+uFbDXoog3hIjPzE3kHw2piX0KuEozCkWcO57CkOvXzApqo1we]] ..
    [[U6RRW7dIWElo56Q+JXpd+uK/cmcvRrqVSqpZwCKYe9e8SSFr9GQ8dtOmH0j01+N4RQWEyC5l1oV5EbEevQVEfF3ee2GFNp7GOUTQ]] ..
    [[fipbxddXQ4UNY6Qrvw8CgOvgiOgsyDvMUieN0xRUQaPqiNJvhYs3jEokqfxzVaOt0RQ0P7UBlbykMaUL6baDeqvh7D1Ajo8NCqL+]] ..
    [[6mVDw/FgOro92Alg5PJb4zhxb/2qfvWlfujfCDfDqPe/3kl7yGOi30ndrgFHjKu5ObIE1rLDp9UxH4sP/ha0MnU7ogZnFcZLJLXY]] ..
    [[cWPktozVY3XVdfQs65OpA8BgagXJIPm6djY7owAWGtQWuiuI4t8/ZEuP8KmwpbPgOvOO2djia9wR+UxtM+84aKhyGCor3RR2ufK8]] ..
    [[9ZHv5gNpmihaH2AU8+fydvBx8nwX/thKdBmRxVPECu2rcyg0FtHH2Lpyw1h8fTUSjdjG9VkPXpfQv/MPpW/gF236L7vdNbfnh4Mu]] ..
    [[rN/up8fhDcJKC90OsjTXdap4mmmel0NCSan46FKHKuMtO/F9zEb0kxWhMtYX9enkT43OR4EFEGldBOUSuMSIxwUebvjf/aQtCAWE]] ..
    [[SMtLOHld68f7RVZ/vtpvrEpkCC5Ngw2xzMfnIu18erin4rTDyDu0Ganuq0q3WI16Ibgm+Tny+2S4Tq+m6eMl7B63vHzHEhm5Bw43]] ..
    [[XsAs+xI1MUfhplMfhJsPLkPhoTKReMh4pnQjA5g97sbvYwO8OLhXfvT77uNXHQn4Wh0fTfG+K8iGKmkt9BXxwMyQGmoqABXYwRQc]] ..
    [[1411SQoGRP5nM1F02vbiZGxlyVcDzI4dBDE5dXxp9jyRMjdh/B+ay6VHKZeLVlfZK1B6k/ZA9aC17jj8cTZgTDPPgk6uugQIgD+G]] ..
    [[nxpnJ0BLvQOK5PKHJxV8KVI5vqOF6DR0dvwwAV/jgVpA/RIzd4ZWG8MRmVEbujcOCB/5crOGBKuCriHqD5YDQQdPOGuoh0V/5+8H]] ..
    [[l1J5Pz55htD8dI/AvDB9T7pplLmzmMarHejYN1Pu/kb/yzFsLGfWwWMOdEcXZ5EnFy2C50cBNtiTk+4qKe+dRzgqr73IOihGBrq1]] ..
    [[QNPkfG2yQ8ZH3CVK1KFRjPLgry1shQCW7O6f7BCgMnpuPXCWf4XSLqT+6GI6QH0OaIot5hGGOPAs8MvgKfVG8OWY0885ypLuTwDC]] ..
    [[HIzzQ2jSUp+72BNTrJs8BvTXg8/MoKscP3W5yUGTWmYZb9/Vl4j85fEaxtFqSxmSB2dNjPzNF/RRlMKwlXjJpuX+Kp0dA52x130d]] ..
    [[7zMY3Y5ETMQvyGjp2AQpZ2FbxuTYK63rmMv+M4ZrurjUNxIZqqQuAf7golBW1pdxk1FlcW9oW+AamTyxc1Dt6QXgUS8HvDEHmdSD]] ..
    [[IEi4AuAFWeiFbBqXqKIoLmZZkSaixBzK7O4mOtQXk+9NpzXOM3VRNLl1FO2UpCjQ8k9tnrUMtG1ci/ESJPp8jKdvZV1UN9s5fsim]] ..
    [[pvq7qIHL8dODRSaTxhGnXR1A3pFrp3MQXWWOuYwluYzI578+Jm2/dxSorU/NiW0dsz2mMbYREMEFqTVmxsXWn4uppZRhsXW+LZZq]] ..
    [[bc8rkA7itFwW7aUilkoh4y/d0c92glE2wy2nrdFTFvr1s7zBQXfR2J4PpHaKZGeCWExXy+cSgPplNNQsVg15w59ug39UxgQKmJrX]] ..
    [[7LMUZprisE2WGfnLzwwQnaYecq9ha8pg4TmgbAblV6Dyi3VD5A+/gIRwS60wc3+Bu3KZwS87EQk00eYgk6jbAV4WkUqoBJjgV/uI]] ..
    [[RiwhPtcLT8d9F0RA4Qm00xHy2jbK4YKD9nCKxasF3CRXlsvX5oVq3ge15Vqm1rQalddRSUE5GCDqeU+CSxlF9bxrQdKF5CEuVa5l]] ..
    [[WwDgEKwpyn14N1a7DccBEL3lD2LUt4zQetvF/NlB2Zq03mHaurvVA0iDLHwWehkYlsHFno0tzzRbTIcduSWKwk2KS0NbkQnlON7K]] ..
    [[RNEUZb7IqBibvIBJQO5yN1XbSoC4vAdvv1xBRFFs6WubvfKxKlU9hZkH/kqjlamRmXpYhJ7hvJgIyFeWW+IfCe56+89znHThN4JZ]]
) ..
(
    [[sv13bt4LowZMZgdGFs6i6u9FJ0D44rP6va3i5U8AQNjSPfOrVpAsT6qbbhGFH8vp76i4ADhnAAGutd7gJEcVt7J+XHtl0K1oTpqU]] ..
    [[+mJ1M0qO/7JMcsX9nYwyQB+fg3c6PwYP7T7P/62h9vzifTn+Y6b/2jtrisWCAX7WFtza7M/eo/7tArM//izzviyjw7n6neNPf32+]] ..
    [[zSX/DW5LMxRNcu+9uvHNLLcr/yCx3r2aSgCrt0c9jep5d+dvt3d8fRbF7FRgctq+oetUzrwfyEN2CJEIajqUyi2IJ1bVNhrG6UK1]] ..
    [[K9CZIIMMFhnJMolNs2issYD23sDscIqW2tX//95AJ9wc1BD6clR5Dz17FVgLLBdgkbIk/PZU/pvxetCFtFzA9grSRqxwhbGdz5G8]] ..
    [[G6sDiUruGB+c5GnFAMT50gegqOz/8QH/hlhnMTgSfftKm41OfShfKciXe75noL+kIgI1EBCSpIRzkRhvm1K6u9e8NDMgWE0YqrGG]] ..
    [[9XJuNJ/2iGHEo0qfh2SFSQcpAEkwNkdb2WusV1h6up2gw+ht0jNie6ifW94DXIErHXvvPlmmLlqexDOWtNDf9TYPaqw+XVjGzx4E]] ..
    [[qoSJcjjQzvOjWPPK5XR9MtTgIwQE+bifErDYAlM+07ym4tzPBq9qK79QcvmjYSw3p7o2nT4KtL1ppgI8+PDTC4ioSjNs5la60tuc]] ..
    [[+21tf+OUN7NOmOoT1nSlVVCDFZ/Pz9o+E8NJhSGwtwEcBjIJvSXejv0CzS7nKLgjehORHqU4GgWcHVCHfBZAaku1Dj8yhSUX5sHH]] ..
    [[KyE5NKBzxJ2ZgPptt1z96dYSucgCra4rwE4JCEQHAmOPpJe09xxdHf4sCIy5xo7JBql1V4sYvkBIsA3iGl8cGEQdYo3sIcMTE8FU]] ..
    [[nB4MJN0KrAuJoFehS946huB6HcQLgDnPXnisFZ+G/R1MgiOr5FGdffEVGZdYDOCTyGvekv+EZwaCAhZlU+D3QJd0gxovJJH4kH6F]] ..
    [[Z3PbIIhnrX/Whi1zVqXGoBSNOyAwlp+t0e52r3euPhcY9cnVDwKkhbnoC+kkkdQxqKQDH6hTG/PGe1TjsvSib167c3vh7LiLx4X7]] ..
    [[0SVtvaQERtuEgvHX4L2dMgCYldbR2wf70cvAYw8oIoIc5LMxwdbGl7NVZUDuBmJzX/aFuah9rClgGi5a4EWAVN41eloOMFKdBk1b]] ..
    [[ZFKtLU0LNaihhkJOQtuWtoOTBP16srAsJCA3UcfxNgFCcGSV9DTdoQNsoPR2quAURw6evfsgk5iUhhEFP06iQCo8ZTmopd3BnS7N]] ..
    [[VF60D9U3Rie0e1W6QK7TasFHYtvamzhbrf5fYOeaDw3eCmsj9J46ij4bSD/oPL8iTHxQLPWSLYXWND5+otyiNY/5UTNDnNcH4yJa]] ..
    [[tMpSSc4QguMHcYTlk7Q7/jLaJQkBOMU+EBdfKzsU6euZxrqGAHFBqV4tykWXG8HHxEGjuSdrD93giXZbQ7m3j0JU2/DcxbryAbu3]] ..
    [[naH2FNHj74NPKzcHh4AvpZLdojDCMSxh1ivrpFRXRLo6pjqA6H6hfyAiTPAxx3ViEsg+kD5IZ9DmY/JWKSesoWMKvmRkmUXV3gLq]] ..
    [[zz3nAEvq9JVSAB/CHpGvk3bdIQp6pA5J/vVdB8IhtIzqjlst/dZn8i+Ur/SQFfehKl6zl8vHTRQDaSpHDNe4e4Kv74bmzW3rCbnF]] ..
    [[QONe8xqWqGC6DphKE8YcDbEO2QMD362WQc5klpJrj+BtpGAPlDDxQAtS927Qi35LOrVKwEAdnQIBX2rhcCSQucWgjDAT4hIBJ47n]] ..
    [[gtYYfRO2DwcDCa3I+pAqfTsGW6xG1rGbAi/MnXPV9THtSWvN1UNmr9JDrCz4cigwJ7sbvTfBv8iChmWUZZaajipO4nDRnk4ueIzt]] ..
    [[/RRIQUDGsrPSYKy4xJYrlDH7/3P35x+t1/f+MXFW+Mcr5FP5MrISuyq+NJSb7CfU+KaCQy+ZCE8bK9KMTKk+UEqg4c8tDvL4TWFs]] ..
    [[kx0sPRw7XkgkXS4U0JZMgLfjfzrpe57WU2UlWqLMTZ67oqtKzrvK3CfI8e9SDppb4IzwmKk7kQRKirk7n24BR5sNem5RjmIvniGB]] ..
    [[cPBpJrsmjfQU146L5rWz6QgkR04Md92l3uftLkdORMZmYIRWIuwUIOOmfjOPqOe3yIjPHmIWFX2kOSVETTh0hhBcDbCNag1CQ0Qj]] ..
    [[hGHnikFWNVBXcL6VxYEa0ttK1IqGXhdBWDNxOOxIv5sB3lErrqV04mwyg0a/izNA/mfeVmvcMtrKAfTMMZWtA+Lr0O4DOxZGbd3R]] ..
    [[eM2C4HvdigZAb3cAB8gDnOGEC4yDZiIatIAxU7K5mzBF68ubbapTp+6NzZEANoVdNUcy65kqvK7BvigClnHYRT1sI5HBnRsZcKTL]]
) ..
(
    [[lPkzqKNFNZXzwFwbsKvy+cv1FizmaARUmsaJu8LQ0m7jDqjfRXVTRA1muZPyAAva4ibWWRna1VRfySn9mRJXWs4k7Oo6VtTWKMNB]] ..
    [[ddvVSGA6Re3oAthcbrtDUUqyEKE0fJGlIdHAmnyJFKCz0jLHaA2FeCfErqTga604Zb5o6ytucq6SJQM1BtCz6R6wxFBx6kZrt3fv]] ..
    [[6szj913suHF7hZ7EJ6Hr2h+ElCscAqjZyKQy99cgiyziSW9o/Ax1KaOmVElYwTzwSeLTF+Cq761zLNNTWoarSE2O6OGS2mjPlCOQ]] ..
    [[f/skAvBpSV6KWuwAUC/ha4oAM9+ikKOizAfj9K3sXnprqezhA+C8uTFS/aXb/260aykMMNBDqxmGFMBhAg5Y60tp6LE7ImMkkxkG]] ..
    [[56I/gSMTwKyKwfnUa4xQqWY/rm2KEzgKFOEwL4o+jVVCEiR1s0ZaCTTAi33g25+nrRSGmUMXfpqBMPmP52Iea3RgrbhCKYxjhWWx]] ..
    [[iLKci26zyxHhgHEl+gCAppaQec8Q9eB7LbFE/1dSQSYXQcon0JJbJazVI9yyELPN38WLbAMjYkitE5mtZlPgHOUg8HO+FpISIsfm]] ..
    [[KdSbjwpqMbESkHJfFXUw0AsaBuMdvdw6eA1CDw7vr1fxms29EUY63eZExMedKnhVnQK4iw7N69r//1n1Noa5vbgr30Ihjb0uxbS8]] ..
    [[X9OjnkSsgQTC6NFCSnUBoKQ5D72xIiLapC1+hkpJMPDryqDHJjuC3OECozbcl7hWcE0t7wDrpSwQVwzlfgBA7a9MGFSHkkwYgy4M]] ..
    [[jJlxsyAIUTKaUMEzyqBI9oSSAGFRU4VvTOaOnY0mwH9ynNYm3icsroj04O2SGLTYAFiXeNnGx2bihadCyKXRoxVuFApYQre+Rp/M]] ..
    [[3nfO6l7ySwi541CALZhrFXBARtalzHFmsnrAWteA6Qr6NYdbtZpDz/jVbg6GWghaazDtgu4NCqj9wh+mHIjqysW1freFea7+4Ng0]] ..
    [[8Awg8Nel6FggjmXjqZx25K5BvhSDhSsNP0F5vqRwJDgP0ycWIuvpuP1cRrVjBKYVSKhwckIemjVLhqsnThJks3HkmTpfXUj5KK8j]] ..
    [[2+nktAaTuo7xJUNfDKmi5ZddOuoKnSOVonPSu9kc7RBGnxOJogZVNWwVK9nOklNEB66yEaIL30yBogvXxZfTS+Y/TRWPU9Orvv0T]] ..
    [[Idjt66ij4rS3c4+syjFo9zt1e5seps9FA9jF79hPQweuvyexi98qT0MLq6zfWJ6l1kdykSDvgltii69uOnvEUR1PDh7KZEUAHkS+]] ..
    [[9E5Cwq+Wh7Ehndh6zmJ1aJyzM7DGnVJh+qr5DVSeXpaC3kLOZ5jjZDopnJhfsLuTronNFo6OGbCcEtY+ASxWD3oCUb+FiVzB19IZ]] ..
    [[Zo2XPeDj2X119nmU46WpOcpTrhcOPgKIB8vuY2F2phk1jx2leq911OVxq1RZNeH1nvTbZqRPOMNqLRO5gZ/Wfc/bS0CsZq5z2tPZ]] ..
    [[xdxlnpNZNUd1ltC2V0HjQaYTnqQi/bdkbvmniBxjOy6RvUbMaou600flymw4zesBtq6W2fzz5Hixl3iW+1k3hCh49L6TdjVP7mLX]] ..
    [[T0TjeX1VFGq+Pu6imjdAhayJYySjMarZD70g1kgMY6rq4qFbFvcAXK2Gpa09T6aeh9FR5FIxmjeZmraj5YYh9oLmN2aDPa0yS0RE]] ..
    [[noJqNFXXyxCmUxP6Q2rt5LBm44ozUleKgmMnYDBauHjKuVBlQRXu0pZDQhgtrOaO1iHJ0fklrGJHXgEP1jrG4tUCceuDUQ0NfCSk]] ..
    [[c0usaoTU2SW2kAXWOSm9iYTZESm8YoDUhEsxi47addfUbt5OZqDGN1kNF6weidXxK7l4BdXuDmaQnHe+3mM1bLH1erGL2FzvkaxA]] ..
    [[BdfqBONkbTGiD30mqOY/a9sxrFJHfmceRwLV2CAUyBAhoRgS1kRFcvqMsS3IzMbAwo2sSoPZ601mpKh1m4ad6lt4Jx9dBbriuM2R]] ..
    [[pP9GxJ6gztrBVgNzoEmv/B/VDP2SPG1cpRaWuU0IcE7iq5ZI8Yrf0q2FUNaBNjtYw9R3cYqJNSUstLqMWZ0QzaavNr9GBavisMa2]] ..
    [[r8D8xWOXB3XrABjKuBs9bkGWj+4ug0Lvq/5HCu0Eepz+tZOrEz3T9BkftIjMlEbciU7s12Ezvb/Jvb9KGqZnBkrtTFzSrD2Wwy6y]] ..
    [[wcBRKCtLjSTC+VCS4zAC835K5mD32lwW9lvoCW59ISb+PzfgbD6aI2HCM5m+NcZoIbFrRbwWhIKy3HyianbS1o7WN2miCu8YQr1s]] ..
    [[JlISbgNt8xMmfFVWK4Y9wE78jaydxrWlO0UfRq4gG8UypcjPhCKSzuosTysVQfviLERhmbtTbdawUa4oiDdfEyhcloNLlPrBeRq7]]
) ..
(
    [[gshJg0oxEXil59WjUFMRIuYVDijLyJzKmSck52Fbt7vTc/et95uicpf2atytngMxVBIEe9oXQaSyqx4K5yXOG3ImGJ1JnFENyJMn]] ..
    [[KD01vpZIOcQ4G0FPXCBX5XVx8tbD9IPZkaeo1SNVMWw2XdWbTNal9uJduIQcqJ4zG29dSfyz3SGUbD/SHauKfsFINRy9gZKjNLE1]] ..
    [[+gjkDbWF2aUkmDhh2DUOLvVdMnLpuyKgk/bNjMURe4qq1AUf69wQQq5NpPFsc8o/qvGVkDtLsAEHaVAWMmiqnmHjZv6KPJyVx2FD]] ..
    [[Wja1Kl2BsaLv0rl0k7cAUU/wVCc/KdLAWm4Fec+LDg0bU3loqumSV+zxddE1tYQI7zRdAUVG+WCIDDZ0LxWxvO102TYogbcoVnE1]] ..
    [[qrl/SYTCgxYITa5GLftg5LwmE3vewuUDXgfIVz6xgm4DNOpMwb8aPFiKyZqIotpJPaTeslNnxPeTVLsmyqQOxW9Ri/nHh1eqVscF]] ..
    [[Npbu3gVbn5acDPjGT99L3yj/7orHK1568ZILa8qBaWhtaXnm0VAs0Pb2lRqi85qs/C1QHaJmxhpRLXbdNmwTC5aFmvJmbSCLMZ+M]] ..
    [[xPJYYOzl20FajGCs4cQdLwKXoBhDUl6GDvpW5muM9B4Sew81ZlVxfpLuGIISS3pek/47wN0IvLeRD9PIfOnUegxdbLjsLxgCjbbD]] ..
    [[lfzbWlH6B127VQc1a+pmhoz6wGVXwJVJ7jvIecN0VHSPbg8zrjfSNIw7JfGnvJtVQNUS+mBIPNYuf43IfW70yHcipKSiqpsQvsWa]] ..
    [[IZzjr3LIVXmQjxoUAk/HQ0LsZELCU/uWT7Xz7cPkD60IYYuGu7Bmlu4CyFAzc7AKIOwBlPSY4rAuGu7wrotqIneXKi/U2IESgWa8]] ..
    [[M2xmAPFkBJ8elXgmpgCdmaQiISuwsfRXAe87L4dOGn8SGpfABEMOncetvQSpoUi+8MORBOECu0yP9kStUMz1KqQeOwiQdg+L5biw]] ..
    [[60EMieOdhokHQhWwmqYgudUlFDnV8wgLufOot8pGEUoQY21JlvaXEALh1tgBtBiqkh1QVaZ3ypowG7WTRFd378VFJ1JLNhKHDa3h]] ..
    [[H1dLLIcMUHk6m2rYTvAWU5DI6jS4vW6O65m3WPXay7nRzGc6Lu7Elgy7oGtLSAg2jIjgv1cFoVa9RFVfHo0OArnbzfKiFju0fSxv]] ..
    [[isiAqwUudIgOgskmrZB+uL2y6ywex12tTovSYpiazKfPBCUgVR4XLw4wnL9mxXdDVgdLKeLwrNiejaAi6NIbe4pZk7EE5EukLfEt]] ..
    [[mUZMpu24710gEtsYKwS7LBNRhk3Al4TejbZOYDvyC9GEpxgBUKGZ3/QwNvod0KWmKkZc7b0x0IM5o+2NYCLoFQkR4jPqyRJ4emP0]] ..
    [[p90TiGe7kEP9RR8FJIfwAynM33fzPVfEi+H9B/MOv/GEh+TYk8S8y+aSWhjoLXLc2oc/oQ0oAhzLNM7MPQ+RPM738zNb8Eft9pYZ]] ..
    [[4Zoh/wA89N8j/3qEl+2Mu9BJY/qdCaZnMdLEUC0Z+Arh6O80/yqBP5f6iJ37VLDArcWi4oYFcTfraDAZaL9CiCAUklC686UHDtKQ]] ..
    [[gUmDzDJzwwAJJKlxASgCgy0wE7TzhAIQAvJQJgVYCyGcRzMP+Q6+0i/RM950dC/RvUPsAZu8O3Ln7gCuIDFgf/REQGHOkB54sPOE]] ..
    [[MBCYS/O0pgMR0WeQHTQI4o3RVEB5bPcIYKpLKUV6s7uDtcAMZfwMCBkSfljANqlLYzWuDoXg+n2FxhxECyAHbw4mEiBgYBBSXVQT]] ..
    [[ECKxtPT+ZLYkvhYEFSoiAcONCzAVzJlI5AwnJRAy2RFOSIE+hpM+Rgc9vnDBc4UmqBszMWDW/HDOy4wkVCBlZyTAJ7a8UQkmIwcH]] ..
    [[zBDJjYAQRXZEZJor/EsAEUjoLCWTEYmofCPReIHNiJswnxvoSsEZi5txJBzBimK6vDGZgFcjXM1Ddn2oUVeXTkW9jxBii1j0cG6i]] ..
    [[p2JGrw0kIDYETCDg6A0R87P5EVa/0o9dUrPQBwZfGBix8KuPMDIEZgqoMEZbzEkYArDA64jBAY+n4GggQvnD/9X4sUEBSqhwqSch]] ..
    [[ge/iAApIqTQgXXV6GCJ+UoQOEqQwXBa1BDMh4Ku+RAgm2GnogQguV6Pv6DArDze3UnBR5hHOHtqz87AMUOvEuMHby9OlDwWGIIsM]] ..
    [[90vuhB8BrUIehSYguJKXePKMpgOvhWmAHw6DSe4Z1VcOGRBRcu4ciBjDHEZozB6Z+eP9DwxB81MMM0DxF/gPzoZWISL1ncP8iJJE]] ..
    [[UulmfWf/pLP8A1+C49fgHz6Jccw7C5CzBq4Uo7OWfYwg5zxY4UTveRhgSbEXhnnvphmSlWtG75CIMzkGHRRUYQA6CiksIVcCwgIW]]
) ..
(
    [[gBxTHBmAVI65tMmxqw+KozYOEITYAxncuPV1hxAavAKInfbGYz/sNELVzZlk76FIph6CElWYFQydh83hVWMHMO7BOWcNDCTmt91W]] ..
    [[br4XxWIF5x7nMIdoJuS1uf2myftMj6BhjscCbggvQlHMQAohVWEMEVkbazjZLiTBeJZ1hhEjOIYwUx7DiKEVFLSvFa5gAEnC93mU]] ..
    [[EMoEiW0enbnXsD8ttL1SJSSeqE5Kdl0ow9OwQCZRabsVQ401hGit5KCJZYYRFnxrEV406glJC1PCOBwQhu0wjGeupnElNQXNEMAp]] ..
    [[POG9FIiPDZcQ07j8GOaZCmOhu/I8sg9ll3NFaJP/pOcRrOMJr5ToHWRftOHm2w4+g71//frYg1wXtfLXEbvC6Gz8oII4U4RrPKo0]] ..
    [[vkLrnwIBxHw3thFOP79sPB77FGDddz89NpmMPlC80uKi+WSa1iVoTVY0Wwt7DtwSeagCq+mdNPZx58M/XFrX1WXDv9DX6uao31px]] ..
    [[CrSysmYmtU8vObrUy1WM7rPRhIY4p0WnASJFSBNJ3a+4I1iScdMIT20Aoai7newpOPm2vksu1CgddqFlR87wEJAqVyxCSKCbtF7l]] ..
    [[2kzSai3zO6U5RCrHHxdaTUarmPpoj0VZhNRosyFghRtbwynsw3cVNu0vpjIYZVHciGIJnx6WK7Ly/amoxHpxXcUs5HsBOrdqV7yK]] ..
    [[LFPsOoCi3qPKyhqxfl/eGhGP0ih8ewaPDeIfKLCr516Ri/fg+9CGW7/mlpLlxDKhf4rfJ9rEN+HbnWn/n2j4v/7DM/ueN9/N6fvR]] ..
    [[3/4W986yuiUvfWdDaczJBSeU6VTjrL3nZEjCqWaybWwc0BE1FsusMD9I4D3uTxA+LJZnCvxVitucy3xu/k8UG7n/1+ZcLYUGIH4x]] ..
    [[r/s0DXKi6MyFm8D32f1k5Eqg8/kVy9Q7navdJmrdpixRW59JOeeHEJf0adxBr5WmnSgdug4c9UQROePP4iZ1Wz5iT+rRb+nij9/M]] ..
    [[EB71fhVekNuSVN30ITFBp3Agpqk+rfOdappsnfQq0A3jLHSaIoTWMQLb7WPAb5ZpW/s96ApE1HBf20Y321uYTclEVlS6HR0uYThE]] ..
    [[x2+MVolZTO9akaf3NeCH3XmjxeVFyb5c81jRuSyWkbz1fHdlNfeK3yuFsqut4W0qdEk1yr0wcqinXXeF5d7KRDJVBWoTdnN3xTvA]] ..
    [[gN92jfBulfawHzFNzaUe6Qfr0t5V6VGFKsnk4Pb39oiYG8PdkshuFWlwn6XhlGcGvXEhvV8QcXPLjVkEPnS96RH2n6nzyMkVRex9]] ..
    [[pSell7H1AE24Z84kK2bMtdp7IKSkPHFAXNveaClCTmlpJogS/Ilp6/Ihlundr2tvkDaqaDm+rYjJYARPlSg8oFOufsVcB2L3tc6w]] ..
    [[L7P0jbm0afqTSgCPVVa0gxFXvxdf22xku2QDVCVzNZ4+669L6iwVkE1qULdm1JZU0QbF3ElwBSDw0prMy0LXaTl0uUEVa0zw79jE]] ..
    [[jY8x17MWjyGbet9Hh7zPHQ9ww8xLum/V/OVn0G7tAxksQ7JiqiOAZCQfkzHrjsE6B706caQxZPIjDk3RUMWcGQFQxZwZAVDFnBkB]] ..
    [[UMWcGQxwNDbq9gyAqGrGDICoasYMgKhqxgyAqGPB4Y8vUVDFnBkBUMWcGQFQxZwZAVDFnBkEcOQ1h+yfdXk4Ge9FSCsTefDjCWfn]] ..
    [[uFxp5oNJZ+OxGOrS2Bxr7yRKCxN1dobIXGVmjsKUNjhR5OYN1YESIrQmRFiKwIkZUJXpnglQleESKPPi5D2ux8f0UFXB0MWVvBkC]] ..
    [[cahqwlw5D7S8CQWysmYAVDVjBkBUNWMOSCcRlazncVl3lq4zJPCSeU/uoKjT3ZcZmvJsIxbwk09tUVKbRCYys0tkJjF47LrM7LrO]] ..
    [[Iyq7jMKi6zMsErE7wywStC5DGdl1mlh6xgyAqGrGDICoasYMgKhqxgyGOIyxA6ZFXFbIVDVjhkhUNWOGSFQ1Y4ZIVDHj0OqdJOCE]] ..
    [[wao+/yYu8fFKJwNuyNvEJ0hKDKgPVDoDXiCzi1NWbffPhzZ0CTOmZc8oPhvDU5RAo4nCXCEo4xvOUwxusNAqS022uAohrpmpD1X3]] ..
    [[jp0kGAolJfSjD/upFbT21LU3VzCaMN3lMHBK+3sTzzdj9Z/qPFrvpxTt5tIez6S1XakgfPJu4zEzutumG565HLTDqt71m777cMiV]] ..
    [[12S7i3gLlZ8o/oOWKvJaIE1cSvVSJNgYocm88bKR2f18DQ53UruqZCFI+IGV0txTqKNiFkz3AYchEbCNivVm86DXsz3FejxJuORN]] ..
    [[/LEdERvUe2aYJabjKP5IcFtsvFB1Y/lVqhVi7XdvfqNb/lZ0otF9xIsj2a1bBMH9Bnpd43bQpgvsy3xuow+p71Ar9VJ11elI5Lv+]]
) ..
(
    [[55XqqlfCqbR9Nr0QQO8JDYtWLq1TvRDtHNWrmU85WPRadW5Uaig5zyGX6p68qSPMGjZDLyBI8w94SPT3PNnN60w4luTWcTpCpJG9]] ..
    [[ER2vHDCEG0tS2iWpC9px1kaHu/uHJ4sHd8invcYAX5UeqgInqm4p20qM3C6GSGYaqGmov9Ie3ohDtSzXPhaHiMQMhs89Zfu0VMHG]] ..
    [[mDO8a9sZGSGxGlrLUnpj+mDY/wq2/jlvV7fq2cb/onUVgcTfZ7I9w8lEx1XOkPM4doSlj7swpV47znZRE3BcOdkGqHpAXvyfF+SD]] ..
    [[qo3yhPZ8N7vXmYwU2mRI+pRWnAgTdpG4g7O6VoX56XKlS1IGtJGi5lTr3Mgy9wVZxiHZvoshC9TB8WLUhnpht18ZJct1doJzLala]] ..
    [[so5AXsgxt4wc093rsPt8Jr9ifTsDI8RJYIvyYzNXca5dlkJFrMvUysdGm8NTmJ0BgXm/uHvmj2vdNXOk37Ss9Q/sSyMmXBm+2943]] ..
    [[B80pyG/dzkuDcc++G0N5yl6oJEQaoW9/NjeL/BJp6+Hf7X+z4eDFtzLt3aHKCx/Vs6tprRwjSuHI0IfKVj84jAYkGKC/0hftMX1d]] ..
    [[6M6dcr9PfCihI0iQQE45TeIHuYFS1K28aTNFEGeiZnxfzthmhiRPPK0ng+YQ2TsfHSO1sSF4wwHLUjeSvSKnOznGk2oZ50dt/jrl]] ..
    [[cbodGHM9FkcK1Idb6f2p4f4X5+ZF+ytcwUduR2qrC7MRuvdq7uIr+dKic0jymg6VvglaZHvYhIVQx3Om0N1E6Loh+zHJTs0brYNW]] ..
    [[eHDeMLsgEka1FXxTv/VvN4Mpkf3bq30aSzhDvUtdCN0ZqOBuk9qLc3fy8sE6yln0+Emapb5n+u7aDRDU43j8L+3cCrybuz1o+iM3]] ..
    [[gUDaM531Mv1fjzuI7Jkz51f0DsxodvMT3Am65W9nnztc3ePPqg04dZAaIjXgI9ySBNFGDRr7Xre1tIu5SJ4t/rvKu2oKsgTNpHu1]] ..
    [[nBpkR3MWtRImoJN6LLnL6ZefBygUDVrsf8qpTahoyq3n5vFKYHVT5ebV+UxEt9x/ADdsh96cU7zPMXCpED1Vpk8H50NEjOyH+Jeu]] ..
    [[Z61WsNEkmREh9g1xP/DLzmwElEUGX+YplfTJ4GoMbGwGJwdyIFJivIfDuy7Kw/cHNGet++8h5da6TLO7djBo+EGG0zsuuckvSqk5]] ..
    [[Mw2xZyASmSZWrXM6drmQefedTioU/CMvJRpxqHbmjSPL1WKJwhK/rEX1Byblyx5Gg7JUmMxA7RnUAI4KXq+4xAEM1nff6J6KYZeE]] ..
    [[Jo7C+7XoV/hiFm9P0Sb5KIvFHm+6N/kDWJYuqjLzSIFQdpfgeLRxbPo245Hnu1NxopTrr8cW122BsPv01mBQ8FPf2gdzKaq56yGN]] ..
    [[uHb/laA0zqPj/c3noF3Fs55M7mlM21cG6utSd/cz2KffTpJ20fpbZmpNdyOBMNv3etfUBnl3Y+b+lSy3qHlwenCHYM+2QRF76A42]] ..
    [[g0GB/iPr9pCdCGxxTqa0tMxGirTrYG03O05S/Rc0iJF3rY4yl6DigVeLuifb3hqm4Ln63rVcW/CUa8XuJjDa6XyQM4wNlCGFuKqG]] ..
    [[+PftE0UDRxPnbIIOjKXS8zf4A86tr20ZS3dzeaLTPol0dofTjQfLusZ/YMvrYr3sBwNcoY+aF7bh4hV8mraIA4Lk8mfQHzfnLHw2]] ..
    [[3WK8PBGI+TdLVdBLfMiSUuttLJ+vltiQrjioDH5L3VLqy+NkLizwoBlWC+6/kcVCqgWvONssI3qkpUjR/3qbpEsbrzIkalTAzZ/U]] ..
    [[Xp18U7e0cj4UYWjshipW81qBegNumuCXTOOsbX5HOp/FTZvHL4D3hPReE91eXbmyFaMu6MhqJ90ZadPIp4TqQHr+KOKI3j6f7wUz]] ..
    [[tykboe85WKKagJeddrqBuNPOXFqnxDPNOv1BRPQF3JCu+iTYMjxO2g4yccgjFG3j9e3pwIURX/qjrJj0bDKXrKYptMA5XzlnywKu]] ..
    [[SKS5P5+L3/eUD+11S8bEGA+wN34/AttjO7nt2xvm3uA9r2XduXaE1/zGIpwt8qcsuXwy5HNTo5PkYGhG2QV2yyoYvshepBKuqmrh]] ..
    [[I3hD6rZ/x8tUCmJ/DqYm8LWkWMAr+CCFxQHzfrKdsu8BqaZiC7t8ZVp6CQuH1Q59v/+L3/0PjTv/PGh35TnVrO4YubZA+ZM/mnt8]] ..
    [[n/IG+VCq3wN02iCIkKbv0e1QkReXI8fs5XORfKewn2SDSpRyaYGEuk06NMfzaJItxqflGXomTIwa6t1xl3MMJ6j0/QDZU7CLzOlB]] ..
    [[l3qkTQPwhDdkPZK5SqqNGG7LytffTbgnLLo2/60Qcq9OH9xvcwemuG4YD0u0YXKTY/T4jRHyYADRhAPZyL6oKG9cgEtQqeSoIfqk]]
) ..
(
    [[Om4KczIFi+R2zncqhJR1oKXuNItNWH0khUXJrDa5TDq4HBwGgyz/qEZt4iwAur41I1lw80PaMn0+h6hI7s+R2qGaj9oJtGAUr5+1]] ..
    [[jbpOul/pBvxqauNTU1bG+LojCaFabkdLPCaEZF1DkEIn+mKpQtFPS8+nZFhYXf3D+Ulq1lYCF6Z8AYok3737nOVi0Es68COioqf4]] ..
    [[t/FrPJItwYYXDrXOXk2FQvGFwa9w6pxaToTdOzTDn9MR1GTVFwhAysqC+MtCVlkzdHQ+RuNPvhOGTDkIxhsZ738Tary5nVNh+1zF]] ..
    [[mvouGiuCRUzAKkv5H7yQhgRue1dYArgiUq3M7Vm7GmncVVEkHRxdEttA5BxR1VUatKxKdBOnnj7q2OMTWCVp9Q48zhJ7e/wcsKva]] ..
    [[vdVuj0rqfQ3Ag0WgIvUaIA82jqxL5q9cZ3Y2ml/dS2tMzILRGLkBseHAz7yKk+pTGWujqt5CbacvjoLdqaXNXGjAuvaKGdWOeJW7]] ..
    [[PhIZLNAs06qSvAJReir726nE4qRJto3za1O2rC1dC+ogEQdf0x6GIvosIz+RTyNpsns3thrEUQup70mwJ0E+GGEEK4Jf9WtiqddR]] ..
    [[ynIih9ey4EIVetVfPloykVOHzxoqJBUnIBg6vZFPecNJHYls+MywfoITWWJbUo0iXtCjZnUe+PkPu32YvmXIsquDh4uSwsOKZdin]] ..
    [[4pt0enc6/zLlP2LT9P9u0OHwp+7W0hLt014n9nTzHYWBDfi7/3DRU0ZVNUSW0qgSeGy4pelUmUGKPU9MhASTlVptjyUtBL09tlUq]] ..
    [[U51yBkNpHDKZYieG1vX+xyPm/CB0KbzQRtPtuxqnOD84YoHIteDN7QlLuMdQho918ptNM2LFXz1xrqZ+y5/4U+l72M7wU3ibnPPy]] ..
    [[C5Kxp6jBYNnCBHZYntq7ihYGYb6NSl7OiBW2rtiiI2tsOWBM/aWolIAGcgdKed+11NLRgoAtgS/asirEoGeuZ/+8Pf+Nbb8b+qo4]] ..
    [[U6GY06vdFJiLTNbB5XuKqndEHHhqlE0JitZgokbmrIXntPjVIholwX7iWXvhrdfQKuxltzdXNq6q+I1F+DJooUhjO0rcZkH1Tlnq]] ..
    [[axOjpAXyzvdiStNxFX6j6qYdfumj7RImy61x9yie1sxM09pJ4mo3toT2GnmIDoFLEANWLLW5nqzjtb+Uw577+Ty1Qyxbzf1qeR7Z]] ..
    [[+vyBgcX9MiVQGbNEefrmXgAX4M21Dv+4Ynh5Y8V2iXy5qDTdeyJBIKeGAW+bF/RvcK2v8EhpLpCdLqBsBPqiPRQHI8X1TF2rHN8x]] ..
    [[8ZTaIYU7LGhqOIzKcigHxilffn6fMM75bJBJTpBGjytGtNBUNwMALoegguyjAyuBDIr1WkgIKUqoRUxLTlp5PheM6dGrmnA4/6xl]] ..
    [[2VL9N2HkSAILOmAy8i5w0ZFBWit69OGM88CH7yn/9hQ+e6sKevwS9m7vPZ7l4lXxPWI2OS8VXxFX3xbbmSsYKwAs8OkQeetErBmi]] ..
    [[/eSMtC0QWUJpxxQ1cu0C8Ft1vojUb7SKELAN3QXRw0rYIubsmBKlZKWZquB4TXu15dALRc7xij9cW2XOvYn6J5DREmwf47oe4itB]] ..
    [[90P0h5HNqvdHPtHB7sTVnS3O9KZ1uVmu2eoHq2cfxij9iHEjJtRI9Ez5V7c+xMsKyLEv2r2Ju+yJf9zn2Ri4gg/Qg5nvfCuvIEnp]] ..
    [[iCfot8Rwwdo1ilhspUz9L//yj1M0aKkcRFZIybbZ/5F0n6B6lSsqgbggQqbLabmA/g39ymM6QqYEfWTV3crDKczSazzkJ8cltk5q]] ..
    [[TFRcVZb4CdI+Sx4621EHk5P8AkM8/ipfm7Box8ucHvYg67wenFygTdBFv7RUsMwsc4Ixwgn2y6IJOXHyE5J3vFhJw1KnvyLvJVhI]] ..
    [[c7nyDzhQ2oGAQReplv40+Z4uVuZmtCUHTHuDlWGbWTude05maj6NXEg5k71+J3VRLusqmLpd/Uxb0OyU8yAsfJx1IF/YoQFWVsDb]] ..
    [[ksbH/eKNB4TBysi5cpTEajyX2ykESW4iaGxhwtiI0trufCWeaDq/cQRIclJze5PwbTf+TtZFKYFHaiAthz6r350fv22/leUh7QWp]] ..
    [[ULms6SgClBYi43pGsG5waZ6+ELfFnh9yCBldRZ+T8JmT5yZ9Nb6d6VnDch54pe4bthV9cbLWxnjtE7b9WQVixVM2UxXAZEtf1qX2]] ..
    [[7lCYlByhnjanR97fNyo3SG0XB/iLbxaSFT3s10m0Jo2OkeV3CPnAPwpWPoz7jFwFtXIc/NJVHS4YxlpamgNN5ZV0WcJBHU9CnLpm]] ..
    [[r8xsJvloG+n753cHCYEOwDSTAz5PdCVZv1Ykr8vcGEKOT6jw3hZTPcB2w6SQxp71ME9ZKfsrg3qRjsXdjSFoHPi5xnnDPZnBzM8Q]]
) ..
(
    [[p6TEU3w2lvhmc58zUGD3G6LP6Gy5J8CUsTya8UnUL0iIjvvbFUfE9fS6Rs1iFtRe+cGOsDdKNiWW8LPH6+IJ+MdKxV+FDJDKQHcI]] ..
    [[RP6ENrg/m6PVJtr5SI2WRK7CH2ZdqmFSSYh52W1aOBctZuW7MGRwZVGxEgz1LsVS6mVf4RW6mmJmJ04yINVKHjMa1GV9rk29ZMVM]] ..
    [[X20aFt03oJZEyUV7Ok0FfX3DxdZDlZYhcrMYOGXBR16qXcCERmbPng01Ip0Hjlw4TjhGyxW/Fbc4su1mcTs2zkLIkWIftSQ9chmd]] ..
    [[k8VyhnWpBeCK6hzSsQGFElQhW83wa2dXuKdI9tyyzwJVct69XEdBnLYqAyP5UYs5AmVNFWNpEitdFtExxDyrWYqkgJxCbGEQ6Qmp]] ..
    [[pBOUdAIIHZl1hXvsDfUhgJiSnoyu/qw5Xn+BqqqFMrVVPIC0rSyXHwmRFGGL8nCVW3q6VCzZc6JzsKxwOiBrPlfDXXlnBdtRk2zM]] ..
    [[vK6eHadocpfKqSkujEbQ7kNX9LZ7NvyIjEO0Ealr/S2NvFceuckwHQxa2YEnl1LR0oqRjEl7utF0W6jtoFNgjB0qYTt6UYekXhaM]] ..
    [[T1pwHHxfdM4CS5Usk3K7MmJFyE24aH9FyJgTT8FEA7m/k0UI4QsL0sMCPycTg8JFqnNMZ6B2SPhf0Z9fohwbRIXWU2t/K5IG35ol]] ..
    [[zXWKyyCLLqstj1xPJqYqwTrFLWARkQ3xkbRAB0umGB8EBL3XOc+vcMhlkMmEtLB8I9SPU2+d2UxLAXXGE/IblEJ9BcQTWa94Wa8c]] ..
    [[ok2MU/U918Y3ydhRmEJTMoZnlD/S3M2wtVx/1i4DwKTESXhb7ESRI6OPdT1akW7r9mJxjZfHNTV7OUP8YvZMeOxGpqglRHyzpHyn]] ..
    [[gklG9LiwUoKErj59UTRF6VjotrwrWLENDSlaK5GiaxEHxBoi1yYXodtpZEiTlZZu0cl4CGPsllzW7kJF7iiMVFS1v6k8/Urq6pAV]] ..
    [[d3qhx0wo9oA2wQMggQYdukaTet0pjucaKV5F5Q9PNStLWifSF7QIBHB5pkvJ9tuFTE+JtjR8Ew4iGTPS/MviH62ZSBFkQKT7Zdl6]] ..
    [[TNbdtdFMulgd6OkVPCMUSDEritCS7+QHylQrFcy2bKELbKpASWJYe6C81GO+Pna9TsCpAUt7QwOhcClozzd5cOdu6CpgJJAciBS9]] ..
    [[bWVOp2aNx0AbYWgLHOeiQlq65gs3hziknmF3SSOX5mSOaPH4Jk1rQITC9fgE8+mzdWte4LzwBZ/Bc4WWzavuA1JHxbvel0iK2U4R]] ..
    [[pTT10zpvFZ5LEFAy6BMg5ugoOkTs2KT35q+ORvpnqXwCc7DeglE8su6/YE0MuW83IpbLLmfVwCm+wCNJdBJ4Om9eGI5PMdFLk8nt]] ..
    [[hb8cRJPLHlXyXwxCAfDAPHS2Z7l+d2XwdtGXe3TQ/PInYTfDHTdTwXxXtpPO5V0LUwlQAStTCNc3V8reWnuJgWk7iFiBXAq1uGs4]] ..
    [[U8Pxddm+jmPRLSFvSiJXX7JuxrPmWsrdMFPieBi/YfpC5Ibb70FbC7CcwtSNQ6+VWDml8ipHX5VKvFNYPnWS9IszqpAZhIAHhWM0]] ..
    [[kA5EES7UXwFpwKYJJ8MOu6NGeyDEEKE7EJqUQ2IZoUlEsmiNlrQwSxyYDB7GxSDhXM0yZFmQGK36ZZX7wAeQsxlTa3CmTm6bFfmL]] ..
    [[J05co5KV6bwwWizldP3xqhcBePDAYtnLS+m78FmD9nDFbGbWMtqJKUs2JGPZwBWUfg1U6sSIiFmrlZwToZMaRx4gTuGKSoEzJ+GG]] ..
    [[v7J2CoysnQJoT5EoKDMOdsk7VAyNGRDlWgpyo+St16VinbHyylwV59+Nxgk7yt0JrB6M/ZyXQen4vLdaiHpyEFuCPBrXVAZTmC94]] ..
    [[VlsoF1Jlc46gRjY8ymM7lnh1u5Hb7iDODrD8vYdkzfQT0l/UklboPXhuP+5Hg4PvRDC1d6iSxu/ipZ3OC1PqkO0kSoKzT5kWsJRu]] ..
    [[jpSR9umPLY/fKZDG+QtnQE84B3cqVmPV/ea3XR/y/PA1uDCO68++gyjXVfR55VAo11corR+bjht5/IJGOYI7bq3JDJ2sxm/OUoYz]] ..
    [[vU/GxTxZabejlU8fmShpP06kOSzJYdU25yFgH90/fKP/ojG2dIRfHQKcfPFjMdrFtzJcpHgKz1uVOKH46ptiieK6ConX5t2xZElT]] ..
    [[xdJvW42O9F8/3e7Lv1/lFvPA5HrSFr+vFcQ/mkPonq/fkHLeWjdsSS0J+e9OX4HEy4nS0DMA5wzNZ2aq8gDdqO3l42xW6pOdeJAJ]] ..
    [[Vwd9Kx52Pi3RzDT3/pB7dvW+e6nMQ9ECcwMyWW5l9b1nZDq/6XL4/9p7bBke7QGmmBJa3GgDUwXogjIYxghdmhsILKln3VkXADho]]
) ..
(
    [[mc8QiQ/jPJ4SsIQZipHM4kFT0OQfyKpWMRYHwUILSgKIQj90IG5N5ykqRWMloC3Q+HINxJDQ7uzYyPw2EHMzDQ0oB0bbZP4mffsK]] ..
    [[MYTvJY46Wak5NZP3TnPruiyGDoQUtxTIoq2AETOzcCIn9dUYalkh+f1yIH75iJm+D5csBVFYXyIMJ3mexwPZz40iVGFYCYBRzxsU]] ..
    [[APLceaQHOfNzXcOphg5VoulV0JRomMqIJl/cUKQVS+EsdYMm3Buj+vQZpE7wQekMkQJ2Ys0EjCeupnzEiGK4pAzDgYok2IIVhLb8]] ..
    [[SKuYjIpK63XclvW7j+SW82P/0o9feuqnORXVpNrYTmqny1ZMsiR4mmR9y46KVH0rgo/ata46JXHl/jIqNa4qNrWvRFZ9OihJKHcN]] ..
    [[TkCpoauUMqSe2OjDplWiAEN+w4Ow5yvjZIQI2xx9ANSVB5WDE0SdljHH04R5Ok+HE0SfLBJkl6BMXZJUkrfXp1LZJefmQtktLvrH]] ..
    [[okPdM9kj7zcD2S/tIT38blpVWPpIfqkfSZVY+ky+0/9iz1SPr0qkfSZfVIkukO/+kpb43Eq9u7EyTObJT0vJUD4eycdCkn3q4ZLQ]] ..
    [[8ebeckVz0OZz+lpP4PcErDY2mzpDfJAHss/dyT1mNJL7i+fF+l5TIklmivZPSZOaOrUlK+xMN3XNIak4iuGws9jwKuYA42YNIK+j]] ..
    [[qapABpGcrZRVfzKTNzAwpGXLD7E0se/r6VhaQWWV6iF5TZdGxx3uZQCV3UrBYucCLV5bWXgntxwU2n9NrhcA8ao8ed1p4qIQdvqc]] ..
    [[5VvOOZ1dhF2HOomd9l9LnSil5rRbsv1AELPLBznrZYQOzhstpjGXmYRscRRwLOqj3WM9oeC45EwW2ywCZMSmORlKshkNmS3NGmT+]] ..
    [[mbZTYd0lufm/2Q7FY8duRw2d5YahP2C7TGYoSjUK35zXKm2YR6Y23Lt4jhSvxLtshSjkrwdlZndVQ4R2csOEVN7+FjBn/Pbo+l9k]] ..
    [[hwBMWBkyZA659srV3NNfc6G2CrpEvqk6VU2XRlyKmthl6WLbKciXJm5y8tseWFpE5Z7mMJRvcjuAmR2kKrwcapypzZOmtxBa2zRN]] ..
    [[cjo2GblQ1qN8hydeZLaEt07oZZVpL3Uh2zwNZt1ApiWdomlL9fK+ebD9U9C2hJZXbQiqGOIT7yfYujyX5vhEdM+6QlJeEltFdjvW]] ..
    [[8kS6C21oJyDLRKpS/pLbaM5GHRX8udQKced0vujWV1RfI1gaLq3Oi85c6TMzt+Ldl5K+GIn946yegIBbRoEg229OZWS6cLWh2zXK]] ..
    [[21khtyaX227AZYZ7SeUlqb3YAajIFNuZZsquVq43iu7lpQLpzSnjCpbafSFkumyX3JPgpg9daCeyMn1tAAWrU7ip4avSgv0H3Lcb]] ..
    [[rPypJzJlmLRlxwqpurB5ej2VRNdYJJZPGyu3FpLa+WbMVlFadxpdHpHYnBrpGudEO9uxnvEf0wzbfgk9auBMZlj8Uv2Y3LbHp2VS]] ..
    [[25drX7qv3lzR6+RqNXu9WVq0mXq8jXpXTq0hpgJjTTOm/6mtYIGGrcBfWPkx27+hg2EK0SfYADSLN5SLK0o8XWIfoPNmAfvtWgaX]] ..
    [[1kAzNsjoU3eG1ML5mHlXAUhjTvJJc9xczABy1q/FoTpHgiLgvpdIUwH0e9Ia1z83ZduTcZx6+lUqmWkkdYDnv3yI4vfo0ym22Kke]] ..
    [[gfm/xuiwp3mWlYQLuK3Ig4M011VFy7t8WYkJXGQkAH4qW8XXV0mMdpHaFZPTyKgy+CoyDzIG+xCF53TBGBax/URhN8MEY8YlGlz+]] ..
    [[PWNZ3uiKHVTubK2FKe5yuTJHujK6/Hlnw2OebMny/upvQSOBYDq6N9gpYOTyW+M5ueO//ap+9aV+4dN5Wnc1rmJ7/kNdRpoe/UBq]] ..
    [[fAU96d3GTRNhedvqnwy+1/+NrQyZQuOtjRGxeZ7FLJbuFsdGu2uum6+hJyztWB5PE2BOWSfNg8HRvThe2jtQatiaLZWubtiXD/FT]] ..
    [[YVtnwGXr43Q9P6UeqtZ7VX3f++2jLCZ3Spe5jCFJ+UIsPXXEWGE+pO2OmWV1FA2JXtvrjSQsEXLDsBnvZ6+RPdhm7/CtrQXXoliU]] ..
    [[upF5x6+FoS3pm1JKxudAnVJRiX91CFJbxnooOd4kTirLjFM9q27k0zc4KG2GZDZEDhI01AoYnFqibxM9W77tWl6xs7SkyIQOISgf]] ..
    [[YzayADYXNJy2zSugJPSM2Jy+lqd+5iFI+s4x0UB7iEIsrJp7UTKihfQmUK56H2Z7Pyspm7B4StoPxE6+zjVXTcA/Mwn+xyEyA3B5]] ..
    [[aaMGtJwPVg3AGyhHYXZkkzs1iMVZXgnLUk4EPCdqDMqjlhlNRznxJ214+AD7eBVSRcUXwZtHnXrADhrB8BFS20ivJcfv0IR+Hj/U]]
) ..
(
    [[kUoasmJ2SLVzp5v1VCKmoPpy5etKC1fdocPPkIhM3g7KKEYhCumpyuEp4Jda/guhI8k/DOHlCK1F2fwBFZA3JU7AoF7moQcN0As0]] ..
    [[YFkCELVp1wFLB2F98CsxTtQhFAkW+gQve5Q2xJpU3B6hFW90Gjkrxdh/YVx/F8OzvMFW+zQ5yXWGDCSH2Ai0voBbqTirheoGQ1WB]] ..
    [[5Gqelg1ypK6CpslXowS0uAoUZHFWZXIHnpXAdH+S648x7cWMJViFSr2M2Szn/oKutwyUWrE4qK2EW+3EV04HqGOeQeRR8esRjEVp]] ..
    [[3Jqik1HRL3IxKyhXAX0m9jnAKyaMvPyZF6TnnIj6mgV9HK4SRGydDKK8zjN8815HcCRPw7dpL/s/I7HACZEGZAZrWzU4SNGdX/uM]] ..
    [[wXuX0UV2l0QjSC9ZU3FmSnPMYjGOqm8oZI8MnrpBr6dNRqmwtCKSKtOpjcxy+6qMhLir3pmvo48VLMDcZ5aRgC0z1zvc4GL2Qk7p]] ..
    [[irwyjq4At7x9HJQU7Lj6NHaVk+1N69d2NlsLLTr35D4kjjF8jgwJHs70fjIGGlF46i+WxyrM0adDMkyjiTKdVm77A5mY0J7RCOD+]] ..
    [[dH15q6uFDnpbEvfifAhvWYLvIk5WcKLeijX0uVQGmqX67JW9JUOGsOunfebmlLIky3K0TSNGSa0Fj0Fm1VKDF0PMVHWuM6E3rzcu]] ..
    [[QdySe3Ix4nJQdv2LwR5Mokt6nMj9C9LfnI/PF0fqpvk117u5KrFr78gmR74qggkXqKR8XKV5URYvFtGwKjtl5iQ6ajFae+jB/I5D]] ..
    [[A2KdSBQS6NvI6qChJdE4RBHLx+eNKbDYa9cWk2GR+c0MyNXnRUxi0J4pr6QqwgrrIcWETCAc8gw6n2R/hFB1J3RHaEanYyDsnsDI]] ..
    [[/DOHhNGaGpql6osWCiUCuqUEm2kxUZJCrifhhOERrFyWR3wwjX5xFLRfc/nyFDHfBHIIEw5pbGO2dYTNGIZQuCsip/nrL0HD+9oi]] ..
    [[1GVhxFIQMt6tO+sFtw8D2O7+uHEYGkEWwSul6FzCoyciTjbLMX9WmUdX8yrlBbpu5vvpRVphpFPygiHBNuHZCkBmldpCXqjmt8gJ]] ..
    [[QFjBaqFqAbas1UrYK30mWIa9wGmzBFAdnHeOmtobbM2nz7nvlwUWbREGribLNUHHjAXY+ob5LzJ6amoVzKaGtyNGEPubG6Qe6+qV]] ..
    [[7L8qsJ15+hly3UISnKV9XTvJLeDjsPg9ctbpn7m3i35GaaGtQ4y/eJMd0UT4zzvcFgMs7hKGfu7nCMVnQ02jw4nq8VIjTzx73U/w]] ..
    [[8=]]
)
