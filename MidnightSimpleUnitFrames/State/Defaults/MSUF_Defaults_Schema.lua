local _, MSUF = ...

-- Generated persistence entries of tools/fixtures/defaults/schema.lua. The
-- complete schema verifies every provider. Only universal menu defaults
-- use portable reconstruction; all other fields retain their
-- native 6.50 representation.
local Schema = { Version = 1 }
MSUF.DefaultsSchema = Schema
local entries = {
    { scope = "general", key = "previewDragHintAnimationEnabled", kind = "boolean", default = true },
    { scope = "general", key = "showGameMenuButton", kind = "boolean", default = true },
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
        if general[entry.key] == nil then general[entry.key] = entry.default end
    end
end

-- Plan before writing: malformed/secret input retains its full representation.
-- No profile or nested table is replaced, and no live reader uses this path.
function Schema.PreparePersistence(globalDB)
    local IsSecret = MSUF.Util.IsSecret
    if IsSecret(globalDB) or type(globalDB) ~= "table" or getmetatable(globalDB) ~= nil then return nil end
    local profiles = globalDB.profiles
    if IsSecret(profiles) or type(profiles) ~= "table" or getmetatable(profiles) ~= nil then return nil end
    for _, profile in pairs(profiles) do
        if IsSecret(profile) or type(profile) ~= "table" or getmetatable(profile) ~= nil then return nil end
        local general = profile.general
        if IsSecret(general) or type(general) ~= "table" or getmetatable(general) ~= nil then return nil end
        for i = 1, #entries do
            local entry = entries[i]
            local value = general[entry.key]
            if IsSecret(value) then return nil end
        end
    end
    return profiles
end

function Schema.Persist(globalDB)
    local profiles = Schema.PreparePersistence(globalDB)
    if not profiles then return false end
    -- Validation and this commit cannot yield or call user code. The fixed
    -- entries and validated owners are the plan; no logout tables are allocated.
    local count = 0
    for _, profile in pairs(profiles) do
        local general = profile.general
        for i = 1, #entries do
            local entry = entries[i]
            if general[entry.key] == entry.default then
                general[entry.key] = nil
                count = count + 1
            end
        end
    end
    return true, count
end
