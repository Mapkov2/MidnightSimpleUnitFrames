-- Declarative defaults, seed metadata and nil-preserving fill API.
local _, MSUF = ...
local Parts = {}
MSUF.DefaultsSchemaParts = Parts

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


Parts.Schema = Schema
Parts.entries = entries
