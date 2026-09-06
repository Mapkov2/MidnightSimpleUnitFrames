-- Menu schema: saved-key ownership, dropdown domains, and legacy defaults.
-- This factory runs once when the menu adapter loads. Routing tables are derived
-- from the runtime lane schema, so controls and compiled config agree on scope.
-- Do not mutate these tables during reads or seed new canonical profile aliases.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.Schema(A3)
    local tostring = tostring
    local pairs = pairs
    local ipairs = ipairs

    local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
    local BOSS_LOOKUP = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
    local UNIT_FLAG = {
        player = "showPlayer",
        target = "showTarget",
        focus = "showFocus",
        boss = "showBoss",
        boss1 = "showBoss",
        boss2 = "showBoss",
        boss3 = "showBoss",
        boss4 = "showBoss",
        boss5 = "showBoss",
    }

    local PUBLIC_UNITS = {
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
        { value = "boss", text = "Boss" },
    }

    local STYLE_SCOPES = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
        { value = "boss", text = "Boss" },
    }

    local GROWTH_VALUES = {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "UP", text = "Up" },
        { value = "DOWN", text = "Down" },
    }
    local GROWTH_OK = { RIGHT=true, LEFT=true, UP=true, DOWN=true }

    local ROW_WRAP_VALUES = {
        { value = "DOWN", text = "Down" },
        { value = "UP", text = "Up" },
    }
    local ROW_WRAP_OK = { DOWN=true, UP=true }

    local STACK_ANCHORS = {
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "TOPLEFT", text = "Top Left" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
    }
    local STACK_ANCHOR_OK = { TOPRIGHT=true, TOPLEFT=true, BOTTOMRIGHT=true, BOTTOMLEFT=true }

    local DEBUFF_TYPE_BORDER_MODE_VALUES = {
        { value = "OFF", text = "Off" },
        { value = "BORDER", text = "Border" },
        { value = "SYMBOL", text = "Border + Symbol" },
    }

    local DURATION_BAR_DISPLAY_VALUES = {
        { value = "BAR_ONLY", text = "Bar Only" },
        { value = "OVERLAY", text = "Icon + Bar" },
    }
    local DURATION_BAR_DISPLAY_OK = { BAR_ONLY=true, OVERLAY=true }

    local DURATION_BAR_POSITION_VALUES = {
        { value = "BOTTOM", text = "Bottom" },
        { value = "TOP", text = "Top" },
    }
    local DURATION_BAR_POSITION_OK = { BOTTOM=true, TOP=true }

    local DURATION_BAR_DIRECTION_VALUES = {
        { value = "REMAINING", text = "Remaining" },
        { value = "ELAPSED", text = "Elapsed" },
    }
    local DURATION_BAR_DIRECTION_OK = { REMAINING=true, ELAPSED=true }

    local AURA_ANCHORS = {
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOP", text = "Top" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOM", text = "Bottom" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    }
    local AURA_ANCHOR_OK = {
        TOPLEFT=true, TOP=true, TOPRIGHT=true,
        LEFT=true, CENTER=true, RIGHT=true,
        BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true,
    }
    local FRAME_STRATA_OK = {
        AUTO=true, BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true,
        DIALOG=true, FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true,
    }

    local LANE_GROWTH_VALUES = {
        { value = "RIGHTDOWN", text = "Right then Down" },
        { value = "LEFTDOWN", text = "Left then Down" },
        { value = "RIGHTUP", text = "Right then Up" },
        { value = "LEFTUP", text = "Left then Up" },
        { value = "UP", text = "Up (Single Column)" },
        { value = "DOWN", text = "Down (Single Column)" },
    }
    local LANE_GROWTH_PARTS = {
        RIGHTDOWN = { "RIGHT", "DOWN" },
        LEFTDOWN = { "LEFT", "DOWN" },
        RIGHTUP = { "RIGHT", "UP" },
        LEFTUP = { "LEFT", "UP" },
        UP = { "UP", "UP" },
        DOWN = { "DOWN", "DOWN" },
    }

    local LAYOUT_KEYS = {
        iconSize = true,
        buffIconZoom = true,
        debuffIconZoom = true,
        stylePadding = true,
        spacing = true,
        buffSpacing = true,
        debuffSpacing = true,
        offsetX = true,
        offsetY = true,
        buffGroupOffsetX = true,
        buffGroupOffsetY = true,
        debuffGroupOffsetX = true,
        debuffGroupOffsetY = true,
        buffGroupIconSize = true,
        debuffGroupIconSize = true,
        buffAnchor = true,
        debuffAnchor = true,
        buffLayer = true,
        debuffLayer = true,
        buffStrata = true,
        debuffStrata = true,
        stackTextSize = true,
        stackTextOffsetX = true,
        stackTextOffsetY = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        durationBarHeight = true,
        buffStackTextSize = true,
        buffStackTextOffsetX = true,
        buffStackTextOffsetY = true,
        buffCooldownTextSize = true,
        buffCooldownTextOffsetX = true,
        buffCooldownTextOffsetY = true,
        buffDurationBarHeight = true,
        debuffStackTextSize = true,
        debuffStackTextOffsetX = true,
        debuffStackTextOffsetY = true,
        debuffCooldownTextSize = true,
        debuffCooldownTextOffsetX = true,
        debuffCooldownTextOffsetY = true,
        debuffDurationBarHeight = true,
    }

    local STYLE_LAYOUT_KEYS = A3.UnitStyleLayoutKeys or {
        iconZoom = true,
        buffIconZoom = true,
        debuffIconZoom = true,
        stylePadding = true,
        buffStylePadding = true,
        debuffStylePadding = true,
        stackTextSize = true,
        stackTextOffsetX = true,
        stackTextOffsetY = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        durationBarHeight = true,
        buffStackTextSize = true,
        buffStackTextOffsetX = true,
        buffStackTextOffsetY = true,
        buffCooldownTextSize = true,
        buffCooldownTextOffsetX = true,
        buffCooldownTextOffsetY = true,
        buffDurationBarHeight = true,
        debuffStackTextSize = true,
        debuffStackTextOffsetX = true,
        debuffStackTextOffsetY = true,
        debuffCooldownTextSize = true,
        debuffCooldownTextOffsetX = true,
        debuffCooldownTextOffsetY = true,
        debuffDurationBarHeight = true,
    }

    local SHARED_LAYOUT_KEYS = {
        showTooltip = true,
        showCooldownSwipe = true,
        cooldownSwipeReverse = true,
        sortMethod = true,
        sortReverse = true,
        showDurationBar = true,
        durationBarDisplay = true,
        durationBarPosition = true,
        durationBarDirection = true,
        showCooldownText = true,
        showStackCount = true,
        debuffTypeBorderMode = true,
        dispelBorderMode = true,
        useDebuffTypeBorders = true,
        buffShowCooldownSwipe = true,
        buffCooldownSwipeReverse = true,
        buffSortMethod = true,
        buffSortReverse = true,
        buffShowDurationBar = true,
        buffDurationBarDisplay = true,
        buffDurationBarPosition = true,
        buffDurationBarDirection = true,
        buffShowTooltip = true,
        buffShowCooldownText = true,
        buffShowStackCount = true,
        buffShowStealable = true,
        buffStealableStyle = true,
        buffStackCountAnchor = true,
        buffCooldownTextAnchor = true,
        debuffShowCooldownSwipe = true,
        debuffCooldownSwipeReverse = true,
        debuffSortMethod = true,
        debuffSortReverse = true,
        debuffShowDurationBar = true,
        debuffDurationBarDisplay = true,
        debuffDurationBarPosition = true,
        debuffDurationBarDirection = true,
        debuffShowTooltip = true,
        debuffShowCooldownText = true,
        debuffShowStackCount = true,
        debuffStackCountAnchor = true,
        debuffCooldownTextAnchor = true,
        perRow = true,
        buffPerRow = true,
        debuffPerRow = true,
        maxBuffs = true,
        maxDebuffs = true,
        growth = true,
        rowWrap = true,
        buffGrowthX = true,
        buffGrowthY = true,
        debuffGrowthX = true,
        debuffGrowthY = true,
        stackCountAnchor = true,
        cooldownTextAnchor = true,
        cooldownDecimalSeconds = true,
        buffCooldownDecimalSeconds = true,
        debuffCooldownDecimalSeconds = true,
        buffFrameEffectType = true,
        buffFrameEffectColor = true,
        buffFrameEffectPriority = true,
        buffFrameEffectThickness = true,
        buffFrameEffectLayer = true,
        buffFrameEffectStrata = true,
        debuffFrameEffectType = true,
        debuffFrameEffectColor = true,
        debuffFrameEffectPriority = true,
        debuffFrameEffectThickness = true,
        debuffFrameEffectLayer = true,
        debuffFrameEffectStrata = true,
    }

    local STYLE_SHARED_LAYOUT_KEYS = A3.UnitStyleSharedLayoutKeys or {
        showTooltip = true,
        showCooldownSwipe = true,
        cooldownSwipeReverse = true,
        sortMethod = true,
        sortReverse = true,
        showDurationBar = true,
        durationBarDisplay = true,
        durationBarPosition = true,
        durationBarDirection = true,
        showCooldownText = true,
        showStackCount = true,
        debuffTypeBorderMode = true,
        dispelBorderMode = true,
        useDebuffTypeBorders = true,
        buffShowCooldownSwipe = true,
        buffCooldownSwipeReverse = true,
        buffSortMethod = true,
        buffSortReverse = true,
        buffShowDurationBar = true,
        buffDurationBarDisplay = true,
        buffDurationBarPosition = true,
        buffDurationBarDirection = true,
        buffShowTooltip = true,
        buffShowCooldownText = true,
        buffShowStackCount = true,
        buffShowStealable = true,
        buffStealableStyle = true,
        buffStackCountAnchor = true,
        buffCooldownTextAnchor = true,
        debuffShowCooldownSwipe = true,
        debuffCooldownSwipeReverse = true,
        debuffSortMethod = true,
        debuffSortReverse = true,
        debuffShowDurationBar = true,
        debuffDurationBarDisplay = true,
        debuffDurationBarPosition = true,
        debuffDurationBarDirection = true,
        debuffShowTooltip = true,
        debuffShowCooldownText = true,
        debuffShowStackCount = true,
        debuffStackCountAnchor = true,
        debuffCooldownTextAnchor = true,
        stackCountAnchor = true,
        cooldownTextAnchor = true,
        cooldownDecimalSeconds = true,
        buffCooldownDecimalSeconds = true,
        debuffCooldownDecimalSeconds = true,
        buffFrameEffectType = true,
        buffFrameEffectColor = true,
        buffFrameEffectPriority = true,
        buffFrameEffectThickness = true,
        buffFrameEffectLayer = true,
        buffFrameEffectStrata = true,
        debuffFrameEffectType = true,
        debuffFrameEffectColor = true,
        debuffFrameEffectPriority = true,
        debuffFrameEffectThickness = true,
        debuffFrameEffectLayer = true,
        debuffFrameEffectStrata = true,
    }

    local GROUPS = A3.UnitLaneSpecs or {
        buff = {
            showKey = "showBuffs",
            maxKey = "maxBuffs",
            xKey = "buffGroupOffsetX",
            yKey = "buffGroupOffsetY",
            sizeKey = "buffGroupIconSize",
            anchorKey = "buffAnchor",
            layerKey = "buffLayer",
            strataKey = "buffStrata",
            perRowKey = "buffPerRow",
            spacingKey = "buffSpacing",
            growthKey = "buffGrowthX",
            wrapKey = "buffGrowthY",
            defaultAnchor = "BOTTOMRIGHT",
            defaultLayer = 5,
        },
        debuff = {
            showKey = "showDebuffs",
            maxKey = "maxDebuffs",
            xKey = "debuffGroupOffsetX",
            yKey = "debuffGroupOffsetY",
            sizeKey = "debuffGroupIconSize",
            anchorKey = "debuffAnchor",
            layerKey = "debuffLayer",
            strataKey = "debuffStrata",
            perRowKey = "debuffPerRow",
            spacingKey = "debuffSpacing",
            growthKey = "debuffGrowthX",
            wrapKey = "debuffGrowthY",
            defaultAnchor = "TOPLEFT",
            defaultLayer = 6,
        },
    }

    -- Lane geometry/cap ownership is declared by GROUPS. Derive the routing maps
    -- from that schema as well, so adding a lane-specific key cannot silently make
    -- the menu write Shared while the runtime reads the unit scope (the gap bug).
    local LANE_LAYOUT_FIELDS = A3.UnitLaneLayoutFields
        or { "xKey", "yKey", "sizeKey", "anchorKey", "layerKey", "strataKey", "spacingKey" }
    local LANE_SHARED_LAYOUT_FIELDS = A3.UnitLaneSharedLayoutFields
        or { "showKey", "maxKey", "perRowKey", "growthKey", "wrapKey" }
    local SCOPE_MATERIALIZED_LAYOUT_KEYS = {}
    for key in pairs(STYLE_LAYOUT_KEYS) do LAYOUT_KEYS[key] = true end
    for key in pairs(STYLE_SHARED_LAYOUT_KEYS) do SHARED_LAYOUT_KEYS[key] = true end
    for _, spec in pairs(GROUPS) do
        for _, field in ipairs(LANE_LAYOUT_FIELDS) do
            local key = spec[field]
            if key then LAYOUT_KEYS[key] = true end
        end
        for _, field in ipairs(LANE_SHARED_LAYOUT_FIELDS) do
            local key = spec[field]
            if key then SHARED_LAYOUT_KEYS[key] = true end
        end
        if spec.spacingKey then SCOPE_MATERIALIZED_LAYOUT_KEYS[spec.spacingKey] = true end
    end
    for key in pairs(LAYOUT_KEYS) do
        assert(SHARED_LAYOUT_KEYS[key] ~= true,
            "MSUF Auras3 key has conflicting layout ownership: " .. tostring(key))
    end

    local LANE_STYLE_KEYS = {
        buff = {
            iconZoom = "buffIconZoom",
            stylePadding = "buffStylePadding",
            iconShape = "buffIconShape",
            showCooldownSwipe = "buffShowCooldownSwipe",
            cooldownSwipeReverse = "buffCooldownSwipeReverse",
            sortMethod = "buffSortMethod",
            sortReverse = "buffSortReverse",
            showDurationBar = "buffShowDurationBar",
            durationBarHeight = "buffDurationBarHeight",
            durationBarDisplay = "buffDurationBarDisplay",
            durationBarPosition = "buffDurationBarPosition",
            durationBarDirection = "buffDurationBarDirection",
            showTooltip = "buffShowTooltip",
            showCooldownText = "buffShowCooldownText",
            showStackCount = "buffShowStackCount",
            showStealable = "buffShowStealable",
            stealableStyle = "buffStealableStyle",
            stackCountAnchor = "buffStackCountAnchor",
            cooldownTextAnchor = "buffCooldownTextAnchor",
            stackTextSize = "buffStackTextSize",
            stackTextOffsetX = "buffStackTextOffsetX",
            stackTextOffsetY = "buffStackTextOffsetY",
            cooldownTextSize = "buffCooldownTextSize",
            cooldownTextOffsetX = "buffCooldownTextOffsetX",
            cooldownTextOffsetY = "buffCooldownTextOffsetY",
            cooldownDecimalSeconds = "buffCooldownDecimalSeconds",
        },
        debuff = {
            iconZoom = "debuffIconZoom",
            stylePadding = "debuffStylePadding",
            iconShape = "debuffIconShape",
            showCooldownSwipe = "debuffShowCooldownSwipe",
            cooldownSwipeReverse = "debuffCooldownSwipeReverse",
            sortMethod = "debuffSortMethod",
            sortReverse = "debuffSortReverse",
            showDurationBar = "debuffShowDurationBar",
            durationBarHeight = "debuffDurationBarHeight",
            durationBarDisplay = "debuffDurationBarDisplay",
            durationBarPosition = "debuffDurationBarPosition",
            durationBarDirection = "debuffDurationBarDirection",
            showTooltip = "debuffShowTooltip",
            showCooldownText = "debuffShowCooldownText",
            showStackCount = "debuffShowStackCount",
            debuffTypeBorderMode = "debuffTypeBorderMode",
            useDebuffTypeBorders = "useDebuffTypeBorders",
            stackCountAnchor = "debuffStackCountAnchor",
            cooldownTextAnchor = "debuffCooldownTextAnchor",
            stackTextSize = "debuffStackTextSize",
            stackTextOffsetX = "debuffStackTextOffsetX",
            stackTextOffsetY = "debuffStackTextOffsetY",
            cooldownTextSize = "debuffCooldownTextSize",
            cooldownTextOffsetX = "debuffCooldownTextOffsetX",
            cooldownTextOffsetY = "debuffCooldownTextOffsetY",
            cooldownDecimalSeconds = "debuffCooldownDecimalSeconds",
        },
    }

    local RUNTIME_FILTER_KEYS = {
        buffs = { "onlyMine", "onlyImportant", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "dispellableAny", "cancelable", "notCancelable", "externalDefensive", "bigDefensive", "exclusive" },
        debuffs = { "onlyMine", "onlyImportant", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "dispellableAny", "crowdControl", "nonPlayer", "exclusive" },
    }

    local DEFAULT_SHARED = {
        showBuffs = true,
        showDebuffs = true,
        showTooltip = true,
        showCooldownSwipe = true,
        cooldownSwipeReverse = false,
        showDurationBar = false,
        durationBarHeight = 2,
        durationBarDisplay = "BAR_ONLY",
        durationBarPosition = "BOTTOM",
        durationBarDirection = "REMAINING",
        showCooldownText = true,
        showStackCount = true,
        debuffTypeBorderMode = "OFF",
        useDebuffTypeBorders = false,
        buffShowCooldownSwipe = true,
        buffCooldownSwipeReverse = false,
        buffSortMethod = "DEFAULT",
        buffSortReverse = false,
        buffShowDurationBar = false,
        buffDurationBarHeight = 2,
        buffDurationBarDisplay = "BAR_ONLY",
        buffDurationBarPosition = "BOTTOM",
        buffDurationBarDirection = "REMAINING",
        buffShowTooltip = true,
        buffShowCooldownText = true,
        buffShowStackCount = true,
        buffShowStealable = false,
        buffStealableStyle = "BORDER_ICON",
        debuffShowCooldownSwipe = true,
        debuffCooldownSwipeReverse = false,
        debuffSortMethod = "DEFAULT",
        debuffSortReverse = false,
        debuffShowDurationBar = false,
        debuffDurationBarHeight = 2,
        debuffDurationBarDisplay = "BAR_ONLY",
        debuffDurationBarPosition = "BOTTOM",
        debuffDurationBarDirection = "REMAINING",
        debuffShowTooltip = true,
        debuffShowCooldownText = true,
        debuffShowStackCount = true,
        buffFrameEffectType = "none",
        buffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
        buffFrameEffectPriority = 5,
        buffFrameEffectThickness = 2,
        buffFrameEffectLayer = 0,
        buffFrameEffectStrata = "AUTO",
        debuffFrameEffectType = "none",
        debuffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
        debuffFrameEffectPriority = 5,
        debuffFrameEffectThickness = 2,
        debuffFrameEffectLayer = 0,
        debuffFrameEffectStrata = "AUTO",
        iconSize = 26,
        iconZoom = 100,
        buffIconZoom = 100,
        debuffIconZoom = 100,
        iconShape = "RECTANGLE",
        buffIconShape = "RECTANGLE",
        debuffIconShape = "RECTANGLE",
        spacing = 2,
        perRow = 12,
        maxBuffs = 12,
        maxDebuffs = 12,
        growth = "RIGHT",
        rowWrap = "DOWN",
        offsetX = 0,
        offsetY = 6,
        buffOffsetX = 0,
        buffOffsetY = 30,
        buffGroupOffsetX = 0,
        buffGroupOffsetY = 36,
        debuffGroupOffsetX = 0,
        debuffGroupOffsetY = 6,
        buffGroupIconSize = 26,
        debuffGroupIconSize = 26,
        buffAnchor = "BOTTOMRIGHT",
        debuffAnchor = "TOPLEFT",
        buffLayer = 5,
        debuffLayer = 6,
        stackCountAnchor = "TOPRIGHT",
        buffStackCountAnchor = "TOPRIGHT",
        debuffStackCountAnchor = "TOPRIGHT",
        cooldownTextAnchor = "CENTER",
        buffCooldownTextAnchor = "CENTER",
        debuffCooldownTextAnchor = "CENTER",
        stackTextSize = 14,
        stackTextOffsetX = -1,
        stackTextOffsetY = 1,
        cooldownTextSize = 14,
        cooldownTextOffsetX = 0,
        cooldownTextOffsetY = 0,
        cooldownDecimalSeconds = 3,
        buffStackTextSize = 14,
        buffStackTextOffsetX = -1,
        buffStackTextOffsetY = 1,
        buffCooldownTextSize = 14,
        buffCooldownTextOffsetX = 0,
        buffCooldownTextOffsetY = 0,
        buffCooldownDecimalSeconds = 3,
        debuffStackTextSize = 14,
        debuffStackTextOffsetX = -1,
        debuffStackTextOffsetY = 1,
        debuffCooldownTextSize = 14,
        debuffCooldownTextOffsetX = 0,
        debuffCooldownTextOffsetY = 0,
        debuffCooldownDecimalSeconds = 3,
        filters = {
            enabled = true,
            buffs = {
                enabled = true,
                onlyMine = false,
                onlyImportant = false,
                includeDispellable = false,
                dispellableAny = false,
                raid = false,
                raidInCombat = false,
                includeNameplateOnly = false,
                cancelable = false,
                notCancelable = false,
                externalDefensive = false,
                bigDefensive = false,
                exclusive = "none",
            },
            debuffs = {
                enabled = true,
                onlyMine = false,
                onlyImportant = false,
                includeDispellable = false,
                dispellableAny = false,
                raid = false,
                raidInCombat = false,
                includeNameplateOnly = false,
                crowdControl = false,
                nonPlayer = false,
                exclusive = "none",
            },
        },
    }

    local DEFAULT_GENERAL = {
        aurasCooldownTextUseBuckets = false,
        aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 },
        aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 },
        aurasCooldownTextSafeSeconds = 60,
        aurasCooldownTextWarningSeconds = 15,
        aurasCooldownTextUrgentSeconds = 5,
    }

    -- Blizzard PTR 6 build 68824 Aura Classifications. These healer/support auras
    -- were removed from NeverSecret, but remain eligible for exact SpellID filters
    -- as helpful auras on assistable units. SATED below is the explicitly documented
    -- NeverSecret harmful-aura family unlocked for friendly-unit filtering in PTR 6.
    local CUSTOM_CONTAINER_MAX = 4
    local TARGET_DOT_CONTAINER_INDEX = 4
    local PLAYER_DEFENSIVE_CONTAINER_INDEX = 4

    -- Private dependency API; public menu methods remain on A3.MenuModel.
    return {
        AURA_ANCHORS = AURA_ANCHORS,
        AURA_ANCHOR_OK = AURA_ANCHOR_OK,
        BOSS_LOOKUP = BOSS_LOOKUP,
        BOSS_UNITS = BOSS_UNITS,
        CUSTOM_CONTAINER_MAX = CUSTOM_CONTAINER_MAX,
        DEBUFF_TYPE_BORDER_MODE_VALUES = DEBUFF_TYPE_BORDER_MODE_VALUES,
        DEFAULT_GENERAL = DEFAULT_GENERAL,
        DEFAULT_SHARED = DEFAULT_SHARED,
        DURATION_BAR_DIRECTION_OK = DURATION_BAR_DIRECTION_OK,
        DURATION_BAR_DIRECTION_VALUES = DURATION_BAR_DIRECTION_VALUES,
        DURATION_BAR_DISPLAY_OK = DURATION_BAR_DISPLAY_OK,
        DURATION_BAR_DISPLAY_VALUES = DURATION_BAR_DISPLAY_VALUES,
        DURATION_BAR_POSITION_OK = DURATION_BAR_POSITION_OK,
        DURATION_BAR_POSITION_VALUES = DURATION_BAR_POSITION_VALUES,
        FRAME_STRATA_OK = FRAME_STRATA_OK,
        GROUPS = GROUPS,
        GROWTH_OK = GROWTH_OK,
        GROWTH_VALUES = GROWTH_VALUES,
        LANE_GROWTH_PARTS = LANE_GROWTH_PARTS,
        LANE_GROWTH_VALUES = LANE_GROWTH_VALUES,
        LANE_STYLE_KEYS = LANE_STYLE_KEYS,
        LAYOUT_KEYS = LAYOUT_KEYS,
        PLAYER_DEFENSIVE_CONTAINER_INDEX = PLAYER_DEFENSIVE_CONTAINER_INDEX,
        PUBLIC_UNITS = PUBLIC_UNITS,
        ROW_WRAP_OK = ROW_WRAP_OK,
        ROW_WRAP_VALUES = ROW_WRAP_VALUES,
        RUNTIME_FILTER_KEYS = RUNTIME_FILTER_KEYS,
        SCOPE_MATERIALIZED_LAYOUT_KEYS = SCOPE_MATERIALIZED_LAYOUT_KEYS,
        SHARED_LAYOUT_KEYS = SHARED_LAYOUT_KEYS,
        STACK_ANCHORS = STACK_ANCHORS,
        STACK_ANCHOR_OK = STACK_ANCHOR_OK,
        STYLE_LAYOUT_KEYS = STYLE_LAYOUT_KEYS,
        STYLE_SCOPES = STYLE_SCOPES,
        STYLE_SHARED_LAYOUT_KEYS = STYLE_SHARED_LAYOUT_KEYS,
        TARGET_DOT_CONTAINER_INDEX = TARGET_DOT_CONTAINER_INDEX,
        UNIT_FLAG = UNIT_FLAG,
    }
end
