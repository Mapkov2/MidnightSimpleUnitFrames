--- Auras3/MSUF_Auras3_Menu_Model.lua
--- Cold-path DB adapter for Auras3 menu surfaces.
---
--- The model writes profile values and invalidates prepared runtime config.
--- It intentionally does not install live aura render logic.
---
--- Menus should use this model instead of touching MSUF_DB directly. The model
--- preserves shared-vs-per-unit override semantics and knows which writes must
--- invalidate prepared native runtime config.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local type, tonumber, tostring, pairs, ipairs, next = type, tonumber, tostring, pairs, ipairs, next
local math_floor = math.floor
local table_sort = table.sort
local C_Spell = _G.C_Spell
local GetSpellInfo = _G.GetSpellInfo
local UnitClass = _G.UnitClass

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local Model = A3.MenuModel
if type(Model) ~= "table" then
    Model = {}
    A3.MenuModel = Model
end

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
local FALLBACK_PUBLIC_AURA_SPELLS = {
    PRESERVATION_EVOKER = {
        [355941] = true, [363502] = true, [364343] = true, [366155] = true,
        [367364] = true, [373267] = true, [376788] = true, [409895] = true,
    },
    AUGMENTATION_EVOKER = {
        [360827] = true, [395152] = true, [395296] = true, [410089] = true, [410263] = true,
        [410686] = true, [413984] = true,
    },
    RESTO_DRUID = {
        [774] = true, [8936] = true, [33763] = true, [48438] = true, [155777] = true,
        [439530] = true,
    },
    DISC_PRIEST = {
        [17] = true, [194384] = true, [1253593] = true,
        [1300008] = true, [1300009] = true,
    },
    HOLY_PRIEST = {
        [139] = true, [41635] = true, [77489] = true,
    },
    MISTWEAVER_MONK = {
        [115175] = true, [119611] = true, [124682] = true, [450769] = true,
        [1292922] = true,
    },
    RESTO_SHAMAN = {
        [974] = true, [383648] = true, [61295] = true, [382024] = true,
        [207400] = true, [444490] = true,
    },
    HOLY_PALADIN = {
        [53563] = true, [156322] = true, [156910] = true, [1244893] = true,
        [200025] = true, [431381] = true,
    },
    RAID_BUFFS = {
        [1459]   = true,   --- Arcane Intellect
        [6673]   = true,   --- Battle Shout
        [21562]  = true,   --- Power Word: Fortitude
        [369459] = true,   --- Source of Magic
        [462854] = true,   --- Skyfury
        [474754] = true,   --- Symbiotic Relationship
    },
    BLESSING_BRONZE = {
        [381732] = true, [381741] = true, [381746] = true, [381748] = true,
        [381749] = true, [381750] = true, [381751] = true, [381752] = true,
        [381753] = true, [381754] = true, [381756] = true, [381757] = true,
        [381758] = true,
    },
    SELF_BUFFS = {
        [433568] = true, [433583] = true,
    },
    ROGUE_POISONS = {
        [2823] = true, [8679] = true, [3408] = true, [5761] = true,
        [315584] = true, [381637] = true, [381664] = true,
    },
    SHAMAN_IMBUE = {
        [319773] = true, [319778] = true, [382021] = true, [382022] = true,
        [457496] = true, [457481] = true, [462757] = true, [462742] = true,
    },
    RESOURCE_AURAS = {
        [205473] = true, [260286] = true,
    },
    COOLDOWNS = {
        [8690] = true, [20608] = true,
    },
    SATED = {
        [57723] = true, [57724] = true, [80354] = true,
        [95809] = true, [160455] = true, [264689] = true,
        [390435] = true,
    },
    DESERTER = {
        [26013] = true, [71041] = true,
    },
    --- Never-secret debuff sets shared by EnhanceQoL's Global Aura Ignore list
    --- (copied with permission; EQoL re-verifies them daily against the Wago
    --- SpellMisc "Aura never secret" attribute).
    CHALLENGE_DEBUFFS = {
        [206151] = true, [308312] = true, [1254550] = true,
    },
    CLASS_UTILITY = {
        [124255] = true, [405189] = true, [462742] = true,
        [462757] = true, [1217607] = true,
    },
    SKYRIDING = {
        [369968] = true, [377234] = true, [388367] = true,
        [404464] = true, [404468] = true, [418590] = true,
        [427490] = true, [447959] = true, [447960] = true,
    },
}

local FALLBACK_PUBLIC_AURA_META = {
    { key = "RAID_BUFFS", label = "Long-term Raid Buffs", category = "Raid", tooltip = "Long duration raid buffs Blizzard exposes as non-secret." },
    { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", category = "Healer", tooltip = "Dream Breath, Dream Flight, Echo, Reversion, Lifebind, Verdant Embrace." },
    { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", category = "Support", tooltip = "Blistering Scales, Ebon Might, Prescience, Inferno's Blessing, Symbiotic Bloom, Shifting Sands." },
    { key = "RESTO_DRUID", label = "Restoration Druid", category = "Healer", tooltip = "Rejuvenation, Regrowth, Lifebloom, Wild Growth, Germination, Symbiotic Blooms." },
    { key = "DISC_PRIEST", label = "Discipline Priest", category = "Healer", tooltip = "Power Word: Shield, Atonement, Void Shield, and Unfolding Vision variants." },
    { key = "HOLY_PRIEST", label = "Holy Priest", category = "Healer", tooltip = "Renew, Prayer of Mending, Echo of Light." },
    { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", category = "Healer", tooltip = "Soothing Mist, Renewing Mist, Enveloping Mist, Aspect of Harmony, Coalescence." },
    { key = "RESTO_SHAMAN", label = "Restoration Shaman", category = "Healer", tooltip = "Earth Shield, Riptide, Earthliving Weapon, Ancestral Vigor, Hydrobubble." },
    { key = "HOLY_PALADIN", label = "Holy Paladin", category = "Healer", tooltip = "Beacon variants, Eternal Flame, and Dawnlight." },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", category = "Raid", tooltip = "All class-specific Blessing of the Bronze variants." },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs", category = "Class", tooltip = "Rite of Sanctification and Rite of Adjuration." },
    { key = "ROGUE_POISONS", label = "Rogue Poisons", category = "Class", tooltip = "Deadly, Wound, Crippling, Numbing, Instant, Atrophic, Amplifying." },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", category = "Class", tooltip = "Windfury, Flametongue, Earthliving, Tidecaller's Guard, Thunderstrike Ward." },
    { key = "RESOURCE_AURAS", label = "Resource Auras", category = "Utility", tooltip = "Mage Icicles and Hunter Tip of the Spear." },
    { key = "COOLDOWNS", label = "Cooldowns", category = "Utility", tooltip = "Hearthstone and Shaman Reincarnation. Mythic+ teleports are not listed by Wowhead." },
    { key = "SATED", label = "Sated / Exhaustion", category = "Utility", tooltip = "Bloodlust/Heroism exhaustion lockout auras." },
    { key = "DESERTER", label = "Deserter", category = "Utility", tooltip = "Dungeon and battleground deserter lockout auras." },
    { key = "CHALLENGE_DEBUFFS", label = "Challenge/Instance Debuffs", category = "Utility", tooltip = "Challenger's Burden and other instance-wide timer debuffs." },
    { key = "CLASS_UTILITY", label = "Class/Utility Auras", category = "Utility", tooltip = "Stagger and similar class utility debuffs (Demon Hunter, Druid, Monk, Shaman)." },
    { key = "SKYRIDING", label = "Skyriding/Ride Along Auras", category = "Utility", tooltip = "Skyriding and Ride Along utility auras." },
}

local PRESET_CATEGORY_ORDER = { "Raid", "Healer", "Support", "Class", "Utility", "Other" }
local PRESET_CATEGORY_RANK = { Raid = 1, Healer = 2, Support = 3, Class = 4, Utility = 5, Other = 6 }
local PRESET_LABELS = {
    RAID_BUFFS = "Long-term Raid Buffs",
    PRESERVATION_EVOKER = "Preservation Evoker",
    AUGMENTATION_EVOKER = "Augmentation Evoker",
    RESTO_DRUID = "Restoration Druid",
    DISC_PRIEST = "Discipline Priest",
    HOLY_PRIEST = "Holy Priest",
    MISTWEAVER_MONK = "Mistweaver Monk",
    RESTO_SHAMAN = "Restoration Shaman",
    HOLY_PALADIN = "Holy Paladin",
    BLESSING_BRONZE = "Blessing of the Bronze",
    SELF_BUFFS = "Long-term Self Buffs",
    ROGUE_POISONS = "Rogue Poisons",
    SHAMAN_IMBUE = "Shaman Imbuements",
    RESOURCE_AURAS = "Resource Auras",
    COOLDOWNS = "Cooldowns",
    SATED = "Sated / Exhaustion",
    DESERTER = "Deserter",
    CHALLENGE_DEBUFFS = "Challenge/Instance Debuffs",
    CLASS_UTILITY = "Class/Utility Auras",
    SKYRIDING = "Skyriding/Ride Along Auras",
}
local PRESET_CATEGORIES = {
    RAID_BUFFS = "Raid",
    BLESSING_BRONZE = "Raid",
    PRESERVATION_EVOKER = "Healer",
    RESTO_DRUID = "Healer",
    DISC_PRIEST = "Healer",
    HOLY_PRIEST = "Healer",
    MISTWEAVER_MONK = "Healer",
    RESTO_SHAMAN = "Healer",
    HOLY_PALADIN = "Healer",
    AUGMENTATION_EVOKER = "Support",
    SELF_BUFFS = "Class",
    ROGUE_POISONS = "Class",
    SHAMAN_IMBUE = "Class",
    RESOURCE_AURAS = "Utility",
    COOLDOWNS = "Utility",
    SATED = "Utility",
    DESERTER = "Utility",
    CHALLENGE_DEBUFFS = "Utility",
    CLASS_UTILITY = "Utility",
    SKYRIDING = "Utility",
}

-- UnitFrame preset menus are lane-specific. These harmful-aura sets mirror
-- EnhanceQoL's curated NeverSecret list, so every supported UnitFrame and
-- Group Frame can expose the same exact Debuff presets honestly.
local UNIT_BUFF_PRESET_KEYS = {
    RAID_BUFFS = true,
    PRESERVATION_EVOKER = true,
    AUGMENTATION_EVOKER = true,
    RESTO_DRUID = true,
    DISC_PRIEST = true,
    HOLY_PRIEST = true,
    MISTWEAVER_MONK = true,
    RESTO_SHAMAN = true,
    HOLY_PALADIN = true,
    BLESSING_BRONZE = true,
    SELF_BUFFS = true,
    ROGUE_POISONS = true,
    SHAMAN_IMBUE = true,
    RESOURCE_AURAS = true,
    COOLDOWNS = true,
}
local UNIT_CURATED_DEBUFF_PRESET_KEYS = {
    SATED = true,
    DESERTER = true,
    CHALLENGE_DEBUFFS = true,
}

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end

local function Default(tbl, key, value)
    if tbl[key] == nil then tbl[key] = DeepCopy(value) end
end

local function DefaultsInto(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(tbl[key]) ~= "table" then tbl[key] = {} end
            DefaultsInto(tbl[key], value)
        else
            Default(tbl, key, value)
        end
    end
end

-- Menu reads can call EnsureDB hundreds of times while constructing one page.
-- Seed each concrete profile table once, then invalidate at the next apply
-- boundary. Replaced profile/subtables naturally miss this weak-key cache.
local defaultsSeedCache = setmetatable({}, { __mode = "k" })
local function MarkDefaultsSeeded(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    local seeded = { defaults = defaults, childKeys = {}, childTables = {} }
    defaultsSeedCache[tbl] = seeded
    for key, value in pairs(defaults) do
        if type(value) == "table" and type(tbl[key]) == "table" then
            local childIndex = #seeded.childKeys + 1
            seeded.childKeys[childIndex] = key
            seeded.childTables[childIndex] = tbl[key]
            MarkDefaultsSeeded(tbl[key], value)
        end
    end
end
local function DefaultsIntoOnce(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    local seeded = defaultsSeedCache[tbl]
    if seeded and seeded.defaults == defaults then
        local childrenMatch = true
        for i = 1, #seeded.childKeys do
            if tbl[seeded.childKeys[i]] ~= seeded.childTables[i] then
                childrenMatch = false
                break
            end
        end
        if childrenMatch then return end
    end
    DefaultsInto(tbl, defaults)
    MarkDefaultsSeeded(tbl, defaults)
end
function Model.InvalidateDefaultSeedCache()
    defaultsSeedCache = setmetatable({}, { __mode = "k" })
end

local function ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -math_floor((-value) + 0.5) end
    return math_floor(value + 0.5)
end

local function Clamp01(value, defaultValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ReadRGB(tbl, key, defaultR, defaultG, defaultB)
    local c = tbl and tbl[key]
    if type(c) ~= "table" then return defaultR, defaultG, defaultB end
    return Clamp01(c[1] or c["1"] or c.r, defaultR),
        Clamp01(c[2] or c["2"] or c.g, defaultG),
        Clamp01(c[3] or c["3"] or c.b, defaultB)
end

local function NormalizeUnit(unit)
    unit = tostring(unit or "player")
    if unit == "boss" or BOSS_LOOKUP[unit] then return "boss" end
    if unit == "target" or unit == "focus" then return unit end
    return "player"
end

local function RuntimeUnit(unit)
    unit = tostring(unit or "player")
    if BOSS_LOOKUP[unit] then return unit end
    unit = NormalizeUnit(unit)
    return unit == "boss" and "boss1" or unit
end

local function EachRuntimeUnit(unit, fn)
    unit = NormalizeUnit(unit)
    if unit == "boss" then
        for i = 1, #BOSS_UNITS do fn(BOSS_UNITS[i]) end
    else
        fn(unit)
    end
end

local function NormalizeScope(scope)
    scope = tostring(scope or "shared")
    if scope == "shared" then return "shared" end
    return NormalizeUnit(scope)
end

local function NormalizeKind(kind)
    kind = tostring(kind or "buff"):lower()
    if kind == "buffs" then return "buff" end
    if kind == "debuffs" then return "debuff" end
    if kind ~= "debuff" then return "buff" end
    return kind
end

local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end

local function NormalizeGroupScope(scope)
    scope = tostring(scope or "raid"):lower()
    if scope == "party" then return "party" end
    return "raid"
end

local function GroupScopeKinds(scope)
    scope = NormalizeGroupScope(scope)
    if scope == "party" then return "party" end
    return "raid", "mythicraid"
end

local function AuraFilter()
    return _G.MSUF_GF_AuraFilter
end

local function PublicAuraPresetSpells()
    local af = AuraFilter()
    return (af and (af.PUBLIC_AURA_PRESET_SPELLS or af.DECLASSIFIED_SPELLS)) or FALLBACK_PUBLIC_AURA_SPELLS
end

local function PublicAuraPresetMeta()
    local af = AuraFilter()
    return (af and (af.PUBLIC_AURA_PRESET_META or af.DECLASSIFIED_META)) or FALLBACK_PUBLIC_AURA_META
end

local _gfBlacklistHashCache = setmetatable({}, { __mode = "k" })

local function GroupBlacklistSpellID(value)
    value = tostring(value or "")
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    return id and math_floor(id + 0.5) or nil
end

local function DirectGroupBlacklistSpells(group)
    if type(group) ~= "table" then return nil end
    local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
    local spells = blacklist and blacklist.spells
    if type(spells) == "table" then return spells end
    spells = group.blacklistSpells
    return type(spells) == "table" and spells or nil
end

local function GroupBlacklistSignature(group)
    if type(group) ~= "table" then return nil end
    local parts, count = nil, 0
    local cats = group.blacklistCats
    if type(cats) == "table" then
        for key, enabled in pairs(cats) do
            if enabled == true and type(key) == "string" and key ~= "" then
                if not parts then parts = {} end
                count = count + 1
                parts[count] = "cat:" .. key
            end
        end
    end
    local spells = DirectGroupBlacklistSpells(group)
    if type(spells) == "table" then
        for key, enabled in pairs(spells) do
            if enabled == true then
                local spellID = GroupBlacklistSpellID(key)
                if spellID then
                    if not parts then parts = {} end
                    count = count + 1
                    parts[count] = "spell:" .. tostring(spellID)
                end
            end
        end
    end
    if count == 0 then return nil end
    table_sort(parts)
    return table.concat(parts, "\001")
end

local function AddGroupBlacklistSpell(hash, n, spellID)
    spellID = GroupBlacklistSpellID(spellID)
    if not spellID then return hash, n end
    if not hash then hash = {} end
    if hash[spellID] ~= true then
        hash[spellID] = true
        n = n + 1
    end
    return hash, n
end

local function AddGroupBlacklistEntry(hash, n, key, value)
    local valueType = type(value)
    if value == true then
        return AddGroupBlacklistSpell(hash, n, key)
    elseif valueType == "number" or valueType == "string" then
        local nextHash, nextN = AddGroupBlacklistSpell(hash, n, value)
        if nextN ~= n then return nextHash, nextN end
        return AddGroupBlacklistSpell(hash, n, key)
    elseif valueType == "table" then
        local nextHash, nextN = AddGroupBlacklistSpell(hash, n, value.spellID or value.spellId or value.id or value[1])
        if nextN ~= n then return nextHash, nextN end
        if value.enabled ~= false then return AddGroupBlacklistSpell(hash, n, key) end
    elseif value ~= false then
        return AddGroupBlacklistSpell(hash, n, key)
    end
    return hash, n
end

local function BuildGroupBlacklistHash(group)
    if type(group) ~= "table" then return nil end
    local cats = group.blacklistCats
    local signature = GroupBlacklistSignature(group)
    if not signature then return nil end

    local cached = _gfBlacklistHashCache[group]
    if cached and cached.signature == signature then return cached.hash end

    local presets = PublicAuraPresetSpells()
    local hash, n = nil, 0
    if type(cats) == "table" then
        for catKey, enabled in pairs(cats) do
            if enabled == true then
                local spells = presets and presets[catKey]
                if type(spells) == "table" then
                    for spellID, value in pairs(spells) do
                        hash, n = AddGroupBlacklistEntry(hash, n, spellID, value)
                    end
                end
            end
        end
    end

    local directSpells = DirectGroupBlacklistSpells(group)
    if type(directSpells) == "table" then
        for spellID, value in pairs(directSpells) do
            hash, n = AddGroupBlacklistEntry(hash, n, spellID, value)
        end
    end

    if n == 0 then
        _gfBlacklistHashCache[group] = nil
        return nil
    end

    _gfBlacklistHashCache[group] = { signature = signature, hash = hash }
    return hash
end

local GF_AURA_FILTER = _G.MSUF_GF_AuraFilter
if type(GF_AURA_FILTER) ~= "table" then
    GF_AURA_FILTER = {}
    ExportPublic("MSUF_GF_AuraFilter", GF_AURA_FILTER)
end
GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS = GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS or FALLBACK_PUBLIC_AURA_SPELLS
GF_AURA_FILTER.PUBLIC_AURA_PRESET_META = GF_AURA_FILTER.PUBLIC_AURA_PRESET_META or FALLBACK_PUBLIC_AURA_META
GF_AURA_FILTER.DECLASSIFIED_SPELLS = GF_AURA_FILTER.DECLASSIFIED_SPELLS or GF_AURA_FILTER.PUBLIC_AURA_PRESET_SPELLS
GF_AURA_FILTER.DECLASSIFIED_META = GF_AURA_FILTER.DECLASSIFIED_META or GF_AURA_FILTER.PUBLIC_AURA_PRESET_META
GF_AURA_FILTER.BUFF_FILTER_ITEMS = {
    { value = "ALL", text = "All Buffs" },
    { value = "Player", text = "Cast by Me" },
    { value = "BigDefensive", text = "Big Defensive" },
    { value = "BigDefensivePlayer", text = "Big Defensive by Me" },
    { value = "ExternalDefensive", text = "External Defensive" },
    { value = "ExternalDefensivePlayer", text = "External Defensive by Me" },
    { value = "RaidInCombat", text = "Raid In Combat" },
    { value = "Raid", text = "Applicable by Me (Raid)" },
    { value = "RaidPlayer", text = "Applicable and Cast by Me" },
}
GF_AURA_FILTER.DEBUFF_FILTER_ITEMS = {
    { value = "ALL", text = "All Debuffs" },
    { value = "Player", text = "Cast by Me" },
    { value = "Raid", text = "Dispellable by Me (Raid)" },
    { value = "RaidInCombat", text = "Raid In Combat" },
    { value = "RAID_PLAYER_DISPELLABLE", text = "Dispellable by Group" },
    { value = "DISPELLABLE", text = "Any Dispel Type" },
    { value = "CROWD_CONTROL", text = "Crowd Control" },
    { value = "NonPlayer", text = "Non-Player Auras" },
}
local function GFNativeFilterKey(token)
    return tostring(token or "ALL"):upper():gsub("[^A-Z0-9]", "")
end
local GF_CURRENT_BUFF_FILTER_TOKENS = {
    ALL = "ALL",
    PLAYER = "Player",
    BIGDEFENSIVE = "BigDefensive",
    BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
    EXTERNALDEFENSIVE = "ExternalDefensive",
    EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
    RAIDINCOMBAT = "RaidInCombat",
    RAID = "Raid",
    RAIDPLAYER = "RaidPlayer",
}
local GF_CURRENT_DEBUFF_FILTER_TOKENS = {
    ALL = "ALL",
    PLAYER = "Player",
    RAID = "Raid",
    RAIDINCOMBAT = "RaidInCombat",
    RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    DISPELLABLE = "DISPELLABLE",
    CROWDCONTROL = "CROWD_CONTROL",
    NONPLAYER = "NonPlayer",
}
--- Stored Group Aura filters must never retain a token that the current UI no
--- longer exposes. Reset retired/unknown filters to the lane's visible default
--- instead of silently continuing an uneditable Blizzard filter expression.
local function NormalizeGFStoredFilterToken(lane, token)
    local current = lane == "debuff" and GF_CURRENT_DEBUFF_FILTER_TOKENS
        or lane == "buff" and GF_CURRENT_BUFF_FILTER_TOKENS
        or nil
    if not current then return token end
    return current[GFNativeFilterKey(token)] or "ALL"
end
GF_AURA_FILTER.NormalizeFilterToken = NormalizeGFStoredFilterToken
local GF_NATIVE_BUFF_FILTERS = {
    ALL = false,
    PLAYER = "PLAYER",
    BIGDEFENSIVEPLAYER = "BIG_DEFENSIVE|PLAYER",
    EXTERNALDEFENSIVEPLAYER = "EXTERNAL_DEFENSIVE|PLAYER",
    RAIDPLAYER = "RAID|PLAYER",
    BIGDEFENSIVE = "BIG_DEFENSIVE",
    EXTERNALDEFENSIVE = "EXTERNAL_DEFENSIVE",
    RAIDINCOMBAT = "RAID_IN_COMBAT",
    RAID = "RAID",
}
local GF_NATIVE_DEBUFF_FILTERS = {
    ALL = false,
    PLAYER = "PLAYER",
    RAID = "RAID",
    RAIDINCOMBAT = "RAID_IN_COMBAT",
    RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    DISPELLABLE = "DISPELLABLE",
    CROWDCONTROL = "CROWD_CONTROL",
    NONPLAYER = false,
}
local function ResolveGFNativeFilter(lane, token, baseFilter, filterMap)
    local key = GFNativeFilterKey(token)
    local current = lane == "debuff" and GF_CURRENT_DEBUFF_FILTER_TOKENS or GF_CURRENT_BUFF_FILTER_TOKENS
    if not current[key] then key = "ALL" end
    local filter = filterMap[key]
    if filter == false then return baseFilter end
    if type(filter) == "string" and filter ~= "" then return baseFilter .. "|" .. filter end
    return baseFilter
end
GF_AURA_FILTER.ResolveBuffFilter = function(token)
    return ResolveGFNativeFilter("buff", token, "HELPFUL", GF_NATIVE_BUFF_FILTERS)
end
GF_AURA_FILTER.ResolveDebuffFilter = function(token)
    return ResolveGFNativeFilter("debuff", token, "HARMFUL", GF_NATIVE_DEBUFF_FILTERS)
end
GF_AURA_FILTER.IsNonPlayerDebuffFilter = function(token)
    return GFNativeFilterKey(token) == "NONPLAYER"
end
-- Blizzard's 12.1 external-defensive token already selects defensives received
-- from other players. Keep the dedicated lane identical to the native viewer;
-- !PLAYER adds a redundant caster-identity dependency on restricted group units.
GF_AURA_FILTER.EXTERNALS_TOKEN = "HELPFUL|EXTERNAL_DEFENSIVE"
GF_AURA_FILTER.BuildBlacklistHash = GF_AURA_FILTER.BuildBlacklistHash or BuildGroupBlacklistHash
GF_AURA_FILTER.InvalidateBlacklistHash = GF_AURA_FILTER.InvalidateBlacklistHash or function(group)
    if type(group) == "table" then _gfBlacklistHashCache[group] = nil end
end

local function GroupConf(kind)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
    local key = kind == "raid" and "gf_raid" or (kind == "mythicraid" and "gf_mythicraid" or "gf_party")
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

local function GroupAuraRoot(kind)
    local conf = GroupConf(kind)
    if type(conf.auras) ~= "table" then conf.auras = {} end
    if conf.auras.renderer ~= "CUSTOM" then conf.auras.renderer = "CUSTOM" end
    if type(conf.auras.buff) ~= "table" then conf.auras.buff = {} end
    if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = {} end
    return conf.auras
end

local function GroupAuraGroup(kind, groupKey)
    groupKey = NormalizeKind(groupKey)
    local root = GroupAuraRoot(kind)
    if type(root[groupKey]) ~= "table" then root[groupKey] = {} end
    return root[groupKey]
end

local function InvalidateGroupBlacklist(scope, groupKey)
    local af = AuraFilter()
    local a, b = GroupScopeKinds(scope)
    if af and type(af.InvalidateBlacklistHash) == "function" then
        af.InvalidateBlacklistHash(GroupAuraGroup(a, groupKey))
        if b then af.InvalidateBlacklistHash(GroupAuraGroup(b, groupKey)) end
    end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.InvalidateCompiledSpecs) == "function" then
        gf.InvalidateCompiledSpecs(a)
        if b then gf.InvalidateCompiledSpecs(b) end
    end
end

local function CompactKey(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function SpellInfo(spellID)
    spellID = tonumber(spellID)
    if not spellID then return nil end
    local name, icon
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            name = info.name
            icon = info.iconID or info.icon
            spellID = tonumber(info.spellID) or spellID
        end
    end
    if not icon and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        icon = C_Spell.GetSpellTexture(spellID)
    end
    if not name and type(GetSpellInfo) == "function" then
        local oldName, _, oldIcon, _, _, _, oldID = GetSpellInfo(spellID)
        name = oldName
        icon = icon or oldIcon
        spellID = tonumber(oldID) or spellID
    end
    return spellID, name, icon
end

local function SpellIDFromInput(value)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    if id then return math_floor(id + 0.5) end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(value)
        if type(info) == "table" and tonumber(info.spellID) then
            return math_floor(tonumber(info.spellID) + 0.5)
        end
    end
    if type(GetSpellInfo) == "function" then
        local _, _, _, _, _, _, spellID = GetSpellInfo(value)
        if tonumber(spellID) then return math_floor(tonumber(spellID) + 0.5) end
    end
    return nil
end

local function SpellLabel(spellID)
    local id, name = SpellInfo(spellID)
    id = id or tonumber(spellID) or 0
    if type(name) ~= "string" or name == "" then name = "Spell" end
    return name .. " (#" .. tostring(id) .. ")"
end

local NormalizeSparseVisualOverrides

--- Ensure the Auras3 DB shape for menu operations. This is coldpath and may
--- seed defaults; live native aura rendering consumes compiled config from the
--- UnitFrames backend after Model.Apply invalidates it.
function Model.EnsureDB()
    local auras, shared
    if A3.EnsureDB then
        auras, shared = A3.EnsureDB()
    else
        local db = _G.MSUF_DB
        if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
        if type(db.auras3) ~= "table" then db.auras3 = {} end
        auras = db.auras3
        shared = auras.shared
    end

    if type(auras) ~= "table" then return nil, nil end
    if auras.enabled == nil then auras.enabled = true end
    Default(auras, "showPlayer", false)
    Default(auras, "showTarget", true)
    Default(auras, "showFocus", false)
    Default(auras, "showBoss", true)
    if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    if type(shared) ~= "table" then shared = {}; auras.shared = shared end
    if type(auras.customDisplays) ~= "table" then auras.customDisplays = {} end
    if type(auras.customDisplays.shared) ~= "table" then auras.customDisplays.shared = { items = {} } end
    if type(auras.customDisplays.shared.items) ~= "table" then auras.customDisplays.shared.items = {} end
    if type(auras.customDisplays.perUnit) ~= "table" then auras.customDisplays.perUnit = {} end
    if type(auras.customDisplays.serial) ~= "number" then auras.customDisplays.serial = 0 end
    if type(auras.customContainers) ~= "table" then auras.customContainers = {} end
    if type(auras.customContainers.perUnit) ~= "table" then auras.customContainers.perUnit = {} end
    -- An existing `specialStyles` table is legacy upgrade input only.  Do not
    -- seed it for new profiles: current Player Defensive and Target-DoT Style
    -- lives on the owning UnitFrame like every other Custom Aura container.
    -- Appearance is now unconditional per Aura product; remove the former
    -- frame participation and shape-follow switches from upgraded profiles.
    shared.styleScopeDisabled = nil
    shared.iconShapeFollowSharedScopes = nil
    local canonicalAuraModel = tonumber(auras.profileModelRevision) == 2
    if canonicalAuraModel then
        -- The Defaults-owned factory is deliberately sparse and authoritative.
        -- Runtime/Menu readers already provide fallbacks, so do not densify a
        -- freshly reset tree with compatibility aliases merely by opening UI.
        if type(shared.filters) ~= "table" then
            shared.filters = DeepCopy(DEFAULT_SHARED.filters)
        end
    else
        DefaultsIntoOnce(shared, DEFAULT_SHARED)
    end
    -- The canonical profile model is already normalized.  Never seed legacy
    -- migration markers back into a freshly hard-reset Aura tree.
    if tonumber(auras.profileModelRevision) ~= 2
        and shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
        shared.debuffTypeBorderMode = shared.useDebuffTypeBorders == true and "SYMBOL" or NormalizeDebuffTypeBorderMode(shared.debuffTypeBorderMode, "OFF")
        shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
    end
    if not canonicalAuraModel then
        NormalizeSparseVisualOverrides(auras, shared)
    end
    return auras, shared
end

local function EnsureGeneralDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
    if type(db.general) ~= "table" then db.general = {} end
    DefaultsIntoOnce(db.general, DEFAULT_GENERAL)
    return db.general
end

function Model.ReadGeneralBool(key, defaultValue)
    local g = EnsureGeneralDB()
    if g[key] == nil then return defaultValue and true or false end
    return g[key] == true
end

function Model.WriteGeneralBool(key, value)
    local g = EnsureGeneralDB()
    g[key] = value and true or false
end

function Model.ReadGeneralNumber(key, defaultValue, minValue, maxValue)
    local g = EnsureGeneralDB()
    return ClampNumber(g[key], defaultValue, minValue, maxValue)
end

function Model.WriteGeneralNumber(key, value, minValue, maxValue)
    local g = EnsureGeneralDB()
    value = ClampNumber(value, 0, minValue, maxValue)
    if math_floor(value) == value then value = Round(value) end
    g[key] = value
end

function Model.ReadGeneralColor(key, defaultR, defaultG, defaultB)
    return ReadRGB(EnsureGeneralDB(), key, defaultR, defaultG, defaultB)
end

function Model.WriteGeneralColor(key, r, g, b)
    local general = EnsureGeneralDB()
    general[key] = { Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1) }
end

-- One cold-path source of truth for the aura duration bar and every preview.
-- The Safe timer color is also the live duration-bar color; when it has not
-- been customized, it inherits the configured global font color just like the
-- cooldown formatter.
function Model.GetDurationBarColor()
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    local color = general and general.aurasCooldownTextSafeColor
    local r, g, b
    if type(color) == "table" then
        r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b
    elseif type(_G.MSUF_GetConfiguredFontColor) == "function" then
        r, g, b = _G.MSUF_GetConfiguredFontColor()
    end
    return Clamp01(r, 1), Clamp01(g, 1), Clamp01(b, 1)
end
A3.GetDurationBarColor = Model.GetDurationBarColor

local function PerUnit(auras, unit, create)
    if type(auras) ~= "table" then return nil end
    unit = RuntimeUnit(unit)
    if create and type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    local pu = auras.perUnit and auras.perUnit[unit]
    if create and type(pu) ~= "table" then
        pu = {}
        auras.perUnit[unit] = pu
    end
    return pu
end

--- Layout values can come from shared defaults, per-unit layout overrides, or
--- per-unit shared-layout overrides. Keep that fallback order centralized here
--- so pages, assistant commands, and edit-mode popups do not diverge.
local function EffectiveLayoutTables(auras, unit)
    local pu = PerUnit(auras, unit, false)
    local layout = (pu and type(pu.layout) == "table") and pu.layout or nil
    local sharedLayout = (pu and type(pu.layoutShared) == "table") and pu.layoutShared or nil
    return layout, sharedLayout, pu
end

local function TableHasAny(tbl)
    if type(tbl) ~= "table" then return false end
    return next(tbl) ~= nil
end

local function TableHasAnyKey(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
    for key in pairs(keys) do
        if tbl[key] ~= nil then return true end
    end
    return false
end

local function ClearKeys(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return end
    for key in pairs(keys) do tbl[key] = nil end
end

local function UnitHasStyleOverride(pu)
    return type(pu) == "table"
        and (TableHasAnyKey(pu.layout, STYLE_LAYOUT_KEYS) or TableHasAnyKey(pu.layoutShared, STYLE_SHARED_LAYOUT_KEYS))
end

local function UnitStyleOverrideActive(pu)
    if type(pu) ~= "table" then return false end
    if pu.overrideStyle ~= nil then return pu.overrideStyle == true end
    return UnitHasStyleOverride(pu)
end

local function RefreshLayoutOverrideFlags(pu)
    if type(pu) ~= "table" then return end
    pu.overrideLayout = TableHasAny(pu.layout) and true or false
    pu.overrideSharedLayout = TableHasAny(pu.layoutShared) and true or false
end

local function LooksLikeLegacySeededVisualLayout(layout)
    if type(layout) ~= "table" then return false end
    if layout.iconSize == nil or layout.buffGroupIconSize == nil or layout.debuffGroupIconSize == nil then return false end
    local hits = 0
    for key in pairs(LAYOUT_KEYS) do
        if layout[key] ~= nil then hits = hits + 1 end
    end
    return hits >= 10
end

local function ClearInheritedLayoutKey(layout, shared, key)
    if type(layout) ~= "table" or type(shared) ~= "table" then return end
    if layout[key] ~= nil and layout[key] == shared[key] then layout[key] = nil end
end

local function ClearInheritedBasicLayoutKeys(layout, shared, keys, styleKeys)
    if type(keys) ~= "table" then return end
    for key in pairs(keys) do
        if not SCOPE_MATERIALIZED_LAYOUT_KEYS[key] and not (styleKeys and styleKeys[key]) then
            ClearInheritedLayoutKey(layout, shared, key)
        end
    end
end

NormalizeSparseVisualOverrides = function(auras, shared)
    local perUnit = type(auras) == "table" and auras.perUnit or nil
    if type(perUnit) ~= "table" then return end
    for _, pu in pairs(perUnit) do
        if type(pu) == "table" and pu._msufA3SparseVisualOverrides_v2 ~= true then
            if pu.overrideStyle == nil and UnitHasStyleOverride(pu) then pu.overrideStyle = true end
            if pu.overrideLayout == true and pu.overrideSharedLayout == true and LooksLikeLegacySeededVisualLayout(pu.layout) then
                ClearInheritedBasicLayoutKeys(pu.layout, shared, LAYOUT_KEYS, STYLE_LAYOUT_KEYS)
                ClearInheritedBasicLayoutKeys(pu.layoutShared, shared, SHARED_LAYOUT_KEYS, STYLE_SHARED_LAYOUT_KEYS)
                RefreshLayoutOverrideFlags(pu)
            end
            pu._msufA3SparseVisualOverrides_v2 = true
        end
    end
end

local function ReadKeyRaw(auras, shared, unit, key)
    local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
    if LAYOUT_KEYS[key] then
        if layout and layout[key] ~= nil then return layout[key] end
    end
    if SHARED_LAYOUT_KEYS[key] then
        if sharedLayout and sharedLayout[key] ~= nil then return sharedLayout[key] end
    end
    return nil
end

local function WriteUnitLayoutValue(auras, shared, unit, key, value)
    EachRuntimeUnit(unit, function(runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
        local styleKey = STYLE_LAYOUT_KEYS[key] == true or STYLE_SHARED_LAYOUT_KEYS[key] == true
        if SHARED_LAYOUT_KEYS[key] then
            if type(pu.layoutShared) ~= "table" then pu.layoutShared = {} end
            pu.overrideSharedLayout = true
            pu.layoutShared[key] = value
            if STYLE_SHARED_LAYOUT_KEYS[key] then pu.overrideStyle = true end
        else
            if type(pu.layout) ~= "table" then pu.layout = {} end
            pu.overrideLayout = true
            pu.layout[key] = value
            if STYLE_LAYOUT_KEYS[key] then pu.overrideStyle = true end
        end
    end)
end

function Model.PublicUnits()
    return PUBLIC_UNITS
end

function Model.StyleScopes()
    return STYLE_SCOPES
end

function Model.GrowthValues()
    return GROWTH_VALUES
end

function Model.RowWrapValues()
    return ROW_WRAP_VALUES
end

function Model.AuraAnchorValues()
    return AURA_ANCHORS
end

function Model.LaneGrowthValues()
    return LANE_GROWTH_VALUES
end

function Model.StackAnchorValues()
    return STACK_ANCHORS
end

function Model.DebuffTypeBorderModeValues()
    return DEBUFF_TYPE_BORDER_MODE_VALUES
end

--- Border styles for the shared aura icon style. Built fresh because
--- LibSharedMedia borders can be registered after login; only ever called
--- while a dropdown is opening.
function Model.BorderStyleValues()
    local B = MSUF.BorderStyles
    if not (B and type(B.List) == "function") then
        return { { value = "SOLID", text = "Solid" } }
    end
    return B.List()
end

local SHARED_APPEARANCE_KINDS = {
    buff = true,
    debuff = true,
    playerDefensives = true,
    targetDots = true,
}

local function NormalizeSharedAppearanceKind(kind)
    kind = tostring(kind or "buff")
    if kind == "playerdefensives" then kind = "playerDefensives" end
    if kind == "targetdots" then kind = "targetDots" end
    return SHARED_APPEARANCE_KINDS[kind] and kind or "buff"
end

--- Shared Appearance is selected only by Aura product, never by Unit/Group
--- frame. Legacy scalar values are materialized once by Defaults and are not
--- active read owners afterwards.
function Model.ReadSharedAppearanceIconShape(kind)
    kind = NormalizeSharedAppearanceKind(kind)
    local _, shared = Model.EnsureDB()
    local shapes = type(shared) == "table" and shared.appearanceIconShapes or nil
    local value = type(shapes) == "table" and shapes[kind] or nil
    value = tostring(value or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE"))
    return type(A3.NormalizeAuraIconShape) == "function" and A3.NormalizeAuraIconShape(value) or value
end

function Model.WriteSharedAppearanceIconShape(kind, value)
    kind = NormalizeSharedAppearanceKind(kind)
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return false end
    shared.appearanceIconShapes = type(shared.appearanceIconShapes) == "table"
        and shared.appearanceIconShapes or {}
    value = tostring(value or "RECTANGLE")
    if type(A3.NormalizeAuraIconShape) == "function" then value = A3.NormalizeAuraIconShape(value) end
    if shared.appearanceIconShapes[kind] == value then return false end
    shared.appearanceIconShapes[kind] = value
    return true
end

--- Appearance values are global by Aura product. They deliberately have no
--- UnitFrame/GroupFrame scope and no participation switch.
function Model.ReadSharedAppearanceValue(kind, key, defaultValue)
    kind = NormalizeSharedAppearanceKind(kind)
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return defaultValue end
    local styles = type(shared.appearanceIconStyles) == "table" and shared.appearanceIconStyles or nil
    local style = type(styles) == "table" and styles[kind] or nil
    if type(style) == "table" and style[key] ~= nil then return style[key] end
    return defaultValue
end

function Model.WriteSharedAppearanceValue(kind, key, value)
    kind = NormalizeSharedAppearanceKind(kind)
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return false end
    shared.appearanceIconStyles = type(shared.appearanceIconStyles) == "table"
        and shared.appearanceIconStyles or {}
    local style = shared.appearanceIconStyles[kind]
    if type(style) ~= "table" then
        style = {}
        shared.appearanceIconStyles[kind] = style
    end
    if style[key] == value then return false end
    style[key] = value
    return true
end

function Model.ReadSharedAppearanceBool(kind, key, defaultValue)
    return Model.ReadSharedAppearanceValue(kind, key, defaultValue and true or false) == true
end

function Model.WriteSharedAppearanceBool(kind, key, value)
    return Model.WriteSharedAppearanceValue(kind, key, value == true)
end

--- Buff and Debuff Appearance mirror these two profile-wide values. The
--- controls stay synchronized between pages while each Blizzard frame remains
--- independently configurable.
local function EnsureBlizzardAuraFrameSettings(shared)
    if type(shared) ~= "table" then return end
    local legacy = shared.hideBlizzardAuraFrames
    if legacy ~= nil then
        if shared.hideBlizzardBuffFrame == nil then
            shared.hideBlizzardBuffFrame = legacy == true
        end
        if shared.hideBlizzardDebuffFrame == nil then
            shared.hideBlizzardDebuffFrame = legacy == true
        end
        shared.hideBlizzardAuraFrames = nil
    end
end

local function ReadHideBlizzardAuraFrame(key)
    local _, shared = Model.EnsureDB()
    EnsureBlizzardAuraFrameSettings(shared)
    return type(shared) == "table" and shared[key] == true
end

local function WriteHideBlizzardAuraFrame(key, value)
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return false end
    EnsureBlizzardAuraFrameSettings(shared)
    value = value == true
    local changed = shared[key] ~= value
    shared[key] = value
    local UF = MSUF and MSUF.UF
    if UF and type(UF.ApplyBlizzardAuraVisibility) == "function" then
        UF.ApplyBlizzardAuraVisibility()
    end
    return changed
end

function Model.ReadHideBlizzardBuffFrame()
    return ReadHideBlizzardAuraFrame("hideBlizzardBuffFrame")
end

function Model.WriteHideBlizzardBuffFrame(value)
    return WriteHideBlizzardAuraFrame("hideBlizzardBuffFrame", value)
end

function Model.ReadHideBlizzardDebuffFrame()
    return ReadHideBlizzardAuraFrame("hideBlizzardDebuffFrame")
end

function Model.WriteHideBlizzardDebuffFrame(value)
    return WriteHideBlizzardAuraFrame("hideBlizzardDebuffFrame", value)
end

function Model.ReadSharedAppearanceNumber(kind, key, defaultValue, minValue, maxValue)
    return ClampNumber(Model.ReadSharedAppearanceValue(kind, key, defaultValue), defaultValue, minValue, maxValue)
end

function Model.WriteSharedAppearanceNumber(kind, key, value, minValue, maxValue)
    value = ClampNumber(value, 0, minValue, maxValue)
    if math_floor(value) == value then value = Round(value) end
    return Model.WriteSharedAppearanceValue(kind, key, value)
end

function Model.ReadSharedAppearanceBorderStyle(kind)
    local B = MSUF.BorderStyles
    local value = Model.ReadSharedAppearanceValue(kind, "styleBorderStyle", "SOLID")
    if B and type(B.Normalize) == "function" then return B.Normalize(value) end
    return type(value) == "string" and value ~= "" and value or "SOLID"
end

function Model.WriteSharedAppearanceBorderStyle(kind, value)
    local B = MSUF.BorderStyles
    if B and type(B.Normalize) == "function" then value = B.Normalize(value) end
    return Model.WriteSharedAppearanceValue(kind, "styleBorderStyle", value)
end

function Model.DurationBarDisplayValues()
    return DURATION_BAR_DISPLAY_VALUES
end

function Model.DurationBarPositionValues()
    return DURATION_BAR_POSITION_VALUES
end

function Model.DurationBarDirectionValues()
    return DURATION_BAR_DIRECTION_VALUES
end

function Model.ScopeLabel(scope)
    scope = NormalizeScope(scope)
    if scope == "shared" then return "Shared" end
    if scope == "player" then return "Player" end
    if scope == "target" then return "Target" end
    if scope == "focus" then return "Focus" end
    return "Boss"
end

function Model.UnitSupported(unit)
    unit = NormalizeUnit(unit)
    return unit == "player" or unit == "target" or unit == "focus" or unit == "boss"
end

function Model.UnitEnabled(unit)
    local auras = Model.EnsureDB()
    local flag = UNIT_FLAG[NormalizeUnit(unit)]
    return type(auras) == "table" and auras.enabled == true and flag and auras[flag] == true
end

function Model.SetUnitEnabled(unit, enabled)
    local auras = Model.EnsureDB()
    if type(auras) ~= "table" then return end
    local flag = UNIT_FLAG[NormalizeUnit(unit)]
    if enabled then auras.enabled = true end
    if flag then auras[flag] = enabled and true or false end
end

function Model.UseSharedVisuals(unit)
    return false
end

local function EnsureUnitStyleOverrides(auras, runtimeUnit)
    local pu = PerUnit(auras, runtimeUnit, true)
    if not pu then return end
    pu.layout = type(pu.layout) == "table" and pu.layout or {}
    pu.layoutShared = type(pu.layoutShared) == "table" and pu.layoutShared or {}
    if pu.overrideStyle ~= true then
        ClearKeys(pu.layout, STYLE_LAYOUT_KEYS)
        ClearKeys(pu.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
    end
    pu.overrideStyle = true
end

function Model.SetUseSharedVisuals(unit, useShared)
    local auras = Model.EnsureDB()
    if type(auras) ~= "table" then return end
    EachRuntimeUnit(unit, function(runtimeUnit)
        EnsureUnitStyleOverrides(auras, runtimeUnit)
    end)
end

function Model.ReadValue(unit, key, defaultValue)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return defaultValue end
    if NormalizeScope(unit) == "shared" then
        if shared[key] ~= nil then return shared[key] end
        return defaultValue
    end
    local value = ReadKeyRaw(auras, shared, unit, key)
    if value ~= nil then return value end
    return defaultValue
end

function Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    return ClampNumber(Model.ReadValue(unit, key, defaultValue), defaultValue, minValue, maxValue)
end

function Model.WriteValue(unit, key, value)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return end
    if NormalizeScope(unit) == "shared" then
        shared[key] = value
    elseif LAYOUT_KEYS[key] or SHARED_LAYOUT_KEYS[key] then
        WriteUnitLayoutValue(auras, shared, unit, key, value)
    end
end

function Model.WriteNumber(unit, key, value, minValue, maxValue)
    value = ClampNumber(value, 0, minValue, maxValue)
    if math_floor(value) == value then value = Round(value) end
    Model.WriteValue(unit, key, value)
end

function Model.ReadBool(unit, key, defaultValue)
    local value = Model.ReadValue(unit, key, defaultValue and true or false)
    if value == nil then return defaultValue and true or false end
    return value == true
end

function Model.WriteBool(unit, key, value)
    Model.WriteValue(unit, key, value and true or false)
end

function Model.ReadGrowth(unit)
    local v = tostring(Model.ReadValue(unit, "growth", "RIGHT") or "RIGHT")
    return GROWTH_OK[v] and v or "RIGHT"
end

function Model.WriteGrowth(unit, value)
    value = GROWTH_OK[value] and value or "RIGHT"
    Model.WriteValue(unit, "growth", value)
end

function Model.ReadRowWrap(unit)
    local v = tostring(Model.ReadValue(unit, "rowWrap", "DOWN") or "DOWN")
    return ROW_WRAP_OK[v] and v or "DOWN"
end

function Model.WriteRowWrap(unit, value)
    value = ROW_WRAP_OK[value] and value or "DOWN"
    Model.WriteValue(unit, "rowWrap", value)
end

function Model.ReadLanePerRow(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    return Model.ReadNumber(unit, spec and spec.perRowKey or "perRow", 12, 1, 40)
end

function Model.WriteLanePerRow(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    Model.WriteNumber(unit, spec and spec.perRowKey or "perRow", value, 1, 40)
end

function Model.ReadLaneSpacing(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    return Model.ReadNumber(unit, spec and spec.spacingKey or "spacing", 2, 0, 64)
end

function Model.WriteLaneSpacing(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    Model.WriteNumber(unit, spec and spec.spacingKey or "spacing", value, 0, 64)
end

function Model.ReadLaneGrowth(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local fallback = "RIGHT"
    local v = tostring(Model.ReadValue(unit, spec and spec.growthKey or "growth", fallback) or fallback)
    return GROWTH_OK[v] and v or fallback
end

function Model.WriteLaneGrowth(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    value = GROWTH_OK[value] and value or "RIGHT"
    Model.WriteValue(unit, spec and spec.growthKey or "growth", value)
end

function Model.ReadLaneGrowthPair(unit, kind)
    kind = NormalizeKind(kind)
    local growth = Model.ReadLaneGrowth(unit, kind)
    if growth == "UP" or growth == "DOWN" then return growth end
    local rowWrap = Model.ReadLaneRowWrap(unit, kind)
    local pair = tostring(growth or "RIGHT") .. tostring(rowWrap or "DOWN")
    return LANE_GROWTH_PARTS[pair] and pair or "RIGHTDOWN"
end

function Model.WriteLaneGrowthPair(unit, kind, value)
    kind = NormalizeKind(kind)
    local parts = LANE_GROWTH_PARTS[value] or LANE_GROWTH_PARTS.RIGHTDOWN
    Model.WriteLaneGrowth(unit, kind, parts[1])
    Model.WriteLaneRowWrap(unit, kind, parts[2])
end

function Model.ReadLaneRowWrap(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local fallback = "DOWN"
    local v = tostring(Model.ReadValue(unit, spec and spec.wrapKey or "rowWrap", fallback) or fallback)
    return ROW_WRAP_OK[v] and v or fallback
end

function Model.WriteLaneRowWrap(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    value = ROW_WRAP_OK[value] and value or "DOWN"
    Model.WriteValue(unit, spec and spec.wrapKey or "rowWrap", value)
end

function Model.ReadLaneAnchor(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local fallback = spec and spec.defaultAnchor or "TOPLEFT"
    local value = tostring(Model.ReadValue(unit, spec and spec.anchorKey or "buffAnchor", fallback) or fallback)
    return AURA_ANCHOR_OK[value] and value or fallback
end

function Model.WriteLaneAnchor(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    value = AURA_ANCHOR_OK[value] and value or (spec and spec.defaultAnchor) or "TOPLEFT"
    Model.WriteValue(unit, spec and spec.anchorKey or "buffAnchor", value)
end

function Model.ReadLaneLayer(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    return Model.ReadNumber(unit, spec and spec.layerKey or "buffLayer", spec and spec.defaultLayer or 5, 0, 30)
end

function Model.ReadLaneStrata(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local value = tostring(Model.ReadValue(unit, spec and spec.strataKey or "buffStrata", "AUTO") or "AUTO"):upper()
    return FRAME_STRATA_OK[value] and value or "AUTO"
end

local function CustomDisplayRoot()
    local auras = Model.EnsureDB()
    return auras and auras.customDisplays
end

local function CustomDisplayScope(scope, create)
    local root = CustomDisplayRoot()
    if not root then return nil end
    scope = NormalizeScope(scope)
    if scope == "shared" then return root.shared end
    local record = root.perUnit[scope]
    if create and type(record) ~= "table" then
        record = { override = false, items = {} }
        root.perUnit[scope] = record
    end
    return record
end

function Model.UseSharedCustomDisplays(scope)
    scope = NormalizeScope(scope)
    if scope == "shared" then return false end
    local record = CustomDisplayScope(scope, false)
    return not (record and record.override == true)
end

function Model.SetUseSharedCustomDisplays(scope, useShared)
    scope = NormalizeScope(scope)
    if scope == "shared" then return end
    local root = CustomDisplayRoot()
    local record = CustomDisplayScope(scope, true)
    if not (root and record) then return end
    if useShared then
        record.override = false
    elseif record.override ~= true then
        record.items = DeepCopy(root.shared.items or {})
        record.override = true
    end
end

function Model.CustomDisplayItems(scope, editable)
    scope = NormalizeScope(scope)
    local root = CustomDisplayRoot()
    if not root then return {} end
    if scope == "shared" then return root.shared.items end
    local record = CustomDisplayScope(scope, editable == true)
    if editable == true and record and record.override ~= true then
        record.items = DeepCopy(root.shared.items or {})
        record.override = true
    end
    if record and record.override == true and type(record.items) == "table" then return record.items end
    return root.shared.items
end

function Model.AddCustomDisplay(scope)
    local root = CustomDisplayRoot()
    if not root then return nil end
    local items = Model.CustomDisplayItems(scope, true)
    root.serial = (tonumber(root.serial) or 0) + 1
    local item = {
        id = root.serial,
        name = "Custom Aura " .. tostring(#items + 1),
        enabled = true,
        auraType = "BUFF",
        spellIDs = "",
        onlyOwn = false,
        layer = 9,
        strata = "AUTO",
        placed = {
            type = "icon", anchor = "TOPRIGHT", x = 0, y = 0,
            size = 24, barWidth = 54, iconShape = "RECTANGLE", showCooldown = true,
            showCooldownSwipe = true, showStacks = true,
        },
        frame = { type = "none", color = { 0.69, 0.50, 0.88, 0.80 }, priority = 5, thickness = 2, layer = 0, strata = "AUTO" },
    }
    items[#items + 1] = item
    return item
end

function Model.RemoveCustomDisplay(scope, id)
    local items = Model.CustomDisplayItems(scope, true)
    for i = #items, 1, -1 do
        if items[i] == id or tostring(items[i] and items[i].id) == tostring(id) then
            table.remove(items, i)
            return true
        end
    end
    return false
end

function Model.CustomDisplayByID(scope, id, editable)
    local items = Model.CustomDisplayItems(scope, editable == true)
    for i = 1, #items do
        if tostring(items[i] and items[i].id) == tostring(id) then return items[i], i end
    end
    return items[1], 1
end

local CUSTOM_CONTAINER_MAX = 4
local TARGET_DOT_CONTAINER_INDEX = 4
local PLAYER_DEFENSIVE_CONTAINER_INDEX = 4
local PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER =
    A3.PlayerDefensiveCoreDefaultMarker or "_msufA3PlayerDefensivesCoreDefault_v1"

local function EnforcePlayerDefensiveContainer(item, canonicalAuraModel)
    if type(item) ~= "table" then return item end
    -- Fallback for standalone menu-model consumers and old profiles that have
    -- not passed through Auras3 Core yet. This is one-shot by design: once the
    -- user turns the feature off in Menu2, later normalization preserves it.
    -- Canonical profiles are already Defaults-owned and intentionally carry no
    -- legacy marker, so their saved false value must never be treated as new.
    if canonicalAuraModel ~= true and item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] ~= true then
        item.enabled = true
        item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] = true
    end
    item.name = "Defensive Buffs"
    item.auraType = "BUFF"
    item.sourceUnit = "player"
    item.targetDots = nil
    item.playerDefensives = true
    item.portraitIcon = item.portraitIcon == true
    -- Preserve the original one-icon portrait behavior for existing profiles.
    -- Users can opt into a wider outward-growing row from the setup slider.
    item.portraitMaxIcons = math_floor(ClampNumber(item.portraitMaxIcons, 1, 1, 8))
    item.portraitCooldownText = item.portraitCooldownText ~= false
    item.portraitPositionWhenDisabled = item.portraitPositionWhenDisabled == true
    item.autoBlacklistPlayerBuffs = item.autoBlacklistPlayerBuffs ~= false
    item.disabledPredefinedSpellIDs = type(item.disabledPredefinedSpellIDs) == "table"
        and item.disabledPredefinedSpellIDs or {}
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.placed.iconShape = type(A3.NormalizeAuraIconShape) == "function"
        and A3.NormalizeAuraIconShape(item.placed.iconShape) or (item.placed.iconShape or "RECTANGLE")
    item.filters = type(item.filters) == "table" and item.filters or {}
    item.filters.enabled = true
    item.filters.onlyMine = false
    item.filters.onlyImportant = false
    item.filters.raid = false
    item.filters.raidInCombat = false
    item.filters.includeNameplateOnly = false
    item.filters.includeDispellable = false
    item.filters.dispellableAny = false
    item.filters.cancelable = false
    item.filters.notCancelable = false
    item.filters.crowdControl = false
    item.filters.externalDefensive = false
    item.filters.bigDefensive = false
    item.filters.exclusive = "none"
    -- Pre-preset custom4 profiles may carry a DEBUFF-era duration ceiling;
    -- since 6.09 compiles maxDuration for every lane it would silently hide
    -- long or permanent defensives, so the pin clears it like other filters.
    item.filters.maxDuration = nil
    return item
end

local function EnforceTargetDotContainer(item)
    if type(item) ~= "table" then return item end
    item.name = "Dots on target"
    item.auraType = "DEBUFF"
    -- The saved scope is shared by the five Boss frames, but the runtime binds
    -- this lane to the concrete frame unit (target/focus/boss1..boss5).
    item.sourceUnit = nil
    item.targetDots = true
    item.playerDefensives = nil
    item.portraitIcon = item.portraitIcon == true
    item.portraitMaxIcons = math_floor(ClampNumber(item.portraitMaxIcons, 1, 1, 8))
    item.portraitCooldownText = item.portraitCooldownText ~= false
    item.portraitPositionWhenDisabled = item.portraitPositionWhenDisabled == true
    item.autoBlacklistDebuffs = item.autoBlacklistDebuffs ~= false
    item.autoBlacklistPlayerBuffs = nil
    item.disabledPredefinedSpellIDs = nil
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.placed.iconShape = type(A3.NormalizeAuraIconShape) == "function"
        and A3.NormalizeAuraIconShape(item.placed.iconShape) or (item.placed.iconShape or "RECTANGLE")
    item.placed.pandemicEnabled = item.placed.pandemicEnabled == true
    if type(A3.NormalizePandemicStyle) == "function" then
        item.placed.pandemicStyle = A3.NormalizePandemicStyle(item.placed.pandemicStyle)
    else
        local pandemicStyle = tostring(item.placed.pandemicStyle or "BORDER"):upper()
        if pandemicStyle == "ALL" then pandemicStyle = "BORDER_TINT"
        elseif pandemicStyle ~= "BORDER" and pandemicStyle ~= "TINT" and pandemicStyle ~= "BORDER_TINT" then pandemicStyle = "BORDER" end
        item.placed.pandemicStyle = pandemicStyle
    end
    local pandemicColor = type(item.placed.pandemicColor) == "table" and item.placed.pandemicColor or nil
    item.placed.pandemicColor = {
        ClampNumber(pandemicColor and (pandemicColor[1] or pandemicColor.r), 1, 0, 1),
        ClampNumber(pandemicColor and (pandemicColor[2] or pandemicColor.g), 0.24, 0, 1),
        ClampNumber(pandemicColor and (pandemicColor[3] or pandemicColor.b), 0.08, 0, 1),
    }
    item.placed.pandemicThickness = ClampNumber(item.placed.pandemicThickness, 2, 1, 12)
    item.placed.pandemicPadding = ClampNumber(item.placed.pandemicPadding, 1, -8, 16)
    item.placed.pandemicBorderAlpha = ClampNumber(item.placed.pandemicBorderAlpha, 1, 0.05, 1)
    item.placed.pandemicTintAlpha = ClampNumber(item.placed.pandemicTintAlpha, 0.22, 0.05, 1)
    item.placed.pandemicBlend = tostring(item.placed.pandemicBlend or "ADD"):upper() == "BLEND" and "BLEND" or "ADD"
    item.frame = type(item.frame) == "table" and item.frame or {
        type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
        priority = 5, thickness = 2, layer = 0, strata = "AUTO",
    }
    item.frame.onlyInPandemicWindow = item.frame.onlyInPandemicWindow == true
    item.filters = type(item.filters) == "table" and item.filters or {}
    item.filters.enabled = true
    item.filters.onlyMine = true
    item.filters.onlyImportant = false
    item.filters.raid = false
    item.filters.raidInCombat = false
    item.filters.includeNameplateOnly = false
    item.filters.includeDispellable = false
    item.filters.dispellableAny = false
    item.filters.cancelable = false
    item.filters.notCancelable = false
    item.filters.crowdControl = false
    item.filters.externalDefensive = false
    item.filters.bigDefensive = false
    item.filters.exclusive = "none"
    return item
end

local function NewCustomContainer(index, unit)
    local item = {
        enabled = false,
        name = "Custom " .. tostring(index),
        auraType = "BUFF",
        spellIDs = "",
        filters = {
            enabled = true,
            hidePermanent = false,
            onlyMine = false,
            onlyImportant = false,
            raid = false,
            raidInCombat = false,
            includeNameplateOnly = false,
            includeDispellable = false,
            dispellableAny = false,
            cancelable = false,
            notCancelable = false,
            crowdControl = false,
            externalDefensive = false,
            bigDefensive = false,
            exclusive = "none",
        },
        placed = {
            type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN",
            x = 0, y = 0, size = 24, barWidth = 54,
            max = 8, perRow = 4, spacing = 2,
            iconShape = "RECTANGLE",
            showCooldown = true, showCooldownSwipe = true, showStacks = true,
        },
        layer = 9,
        strata = "AUTO",
        frame = {
            type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
            priority = 5, thickness = 2, layer = 0, strata = "AUTO",
            onlyInPandemicWindow = false,
        },
    }
    if index == PLAYER_DEFENSIVE_CONTAINER_INDEX and NormalizeScope(unit) == "player" then
        return EnforcePlayerDefensiveContainer(item)
    end
    return index == TARGET_DOT_CONTAINER_INDEX and EnforceTargetDotContainer(item) or item
end

local function UpgradeLegacyCustomContainer(dst, legacy, index)
    if type(dst) ~= "table" or type(legacy) ~= "table" then return dst end
    dst.enabled = legacy.enabled ~= false
    dst.name = legacy.name or dst.name
    dst.auraType = legacy.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
    dst.spellIDs = legacy.spellIDs or legacy.includeSpellIDs or ""
    dst.layer = legacy.layer or dst.layer
    dst.strata = legacy.strata or dst.strata
    if type(legacy.placed) == "table" then
        for key, value in pairs(legacy.placed) do dst.placed[key] = DeepCopy(value) end
    end
    if type(legacy.frame) == "table" then dst.frame = DeepCopy(legacy.frame) end
    if legacy.onlyOwn == true then dst.filters.onlyMine = true end
    dst._migratedFromCustomDisplay = legacy.id or index
    return dst
end

local function EnsureUnitCustomContainers(unit, create)
    unit = NormalizeScope(unit)
    if unit == "shared" then unit = "player" end
    local auras = Model.EnsureDB()
    local root = auras.customContainers
    local record = root.perUnit[unit]
    if type(record) ~= "table" and create then
        record = { items = {} }
        root.perUnit[unit] = record
    end
    if type(record) ~= "table" then return nil, auras end
    if type(record.items) ~= "table" then record.items = {} end
    if record._msufA3CustomContainersMigrated_v1 ~= true then
        local oldRoot = Model.EnsureDB().customDisplays
        local oldRecord = oldRoot and oldRoot.perUnit and oldRoot.perUnit[unit]
        local oldItems = oldRecord and oldRecord.override == true and oldRecord.items
            or (oldRoot and oldRoot.shared and oldRoot.shared.items)
        if type(oldItems) == "table" then
            for i = 1, math.min(CUSTOM_CONTAINER_MAX, #oldItems) do
                if type(record.items[i]) ~= "table" then
                    record.items[i] = UpgradeLegacyCustomContainer(NewCustomContainer(i, unit), oldItems[i], i)
                end
            end
        end
        record._msufA3CustomContainersMigrated_v1 = true
    end
    return record, auras
end

function Model.CustomContainerMax()
    return CUSTOM_CONTAINER_MAX
end

local MigrateLegacySpecialStyle

function Model.CustomContainer(unit, index, create)
    unit = NormalizeScope(unit)
    if unit == "shared" then unit = "player" end
    index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
    local record, auras = EnsureUnitCustomContainers(unit, create == true)
    if not record then return nil end
    local item = record.items[index]
    if type(item) ~= "table" and create == true then
        item = NewCustomContainer(index, unit)
        record.items[index] = item
    end
    if index == PLAYER_DEFENSIVE_CONTAINER_INDEX and unit == "player" then
        EnforcePlayerDefensiveContainer(item, (tonumber(auras and auras.profileModelRevision) or 0) >= 1)
    elseif index == TARGET_DOT_CONTAINER_INDEX then
        EnforceTargetDotContainer(item)
    end
    if MigrateLegacySpecialStyle then MigrateLegacySpecialStyle(unit, index, item) end
    return item
end

function Model.CustomContainers(unit, create)
    local record = EnsureUnitCustomContainers(unit, create == true)
    return record and record.items or {}
end

--- Copies only the controls exposed by the UnitFrame Aura Style tools.
--- Visibility, positioning, filters, whitelists and tracked spells stay owned
--- by the destination. This is a cold-path Copy To operation.
Model.CustomContainerStylePlacedKeys = Model.CustomContainerStylePlacedKeys or {
    iconZoom = true,
    showTooltip = true,
    alpha = true,
    debuffTypeBorderMode = true,
    showStacks = true,
    stackSize = true,
    stackAnchor = true,
    stackX = true,
    stackY = true,
    showCooldown = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    cooldownSize = true,
    cooldownAnchor = true,
    cooldownX = true,
    cooldownY = true,
    cooldownDecimalSeconds = true,
    showDurationBar = true,
    durationBarHeight = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    pandemicEnabled = true,
    pandemicStyle = true,
    pandemicColor = true,
    pandemicThickness = true,
    pandemicPadding = true,
    pandemicBorderAlpha = true,
    pandemicTintAlpha = true,
    pandemicBlend = true,
    sortMethod = true,
    sortReverse = true,
}

--- Custom-4 represents two different products: Player Defensive buffs on
--- Player and Target DoTs everywhere else. Their common presentation can be
--- copied, but these destination-only controls have no compatible value on the
--- opposite product. Preserve them instead of clearing them to defaults (or
--- importing a sort method from the wrong helpful/harmful domain).
local INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS = {
    debuffTypeBorderMode = true,
    sortMethod = true,
    sortReverse = true,
    pandemicEnabled = true,
    pandemicStyle = true,
    pandemicColor = true,
    pandemicThickness = true,
    pandemicPadding = true,
    pandemicBorderAlpha = true,
    pandemicTintAlpha = true,
    pandemicBlend = true,
}

local function CustomContainerStyleProduct(unit, index)
    if index ~= PLAYER_DEFENSIVE_CONTAINER_INDEX then return nil end
    return NormalizeUnit(unit) == "player" and "playerDefensives" or "targetDots"
end

--- Older builds stored Custom-4 presentation in one global specialStyles
--- record.  Materialize that last effective look into every owning frame once,
--- then keep all future edits frame-local.  Content, filters, placement and
--- tracked spells never pass through this migration.
MigrateLegacySpecialStyle = function(unit, index, item)
    if index ~= 4 or type(item) ~= "table" or item._msufA3LocalStyleFromShared_v1 == true then return end
    local normalizedUnit = NormalizeUnit(unit)
    local kind = normalizedUnit == "player" and "playerDefensives" or "targetDots"
    local auras, shared = Model.EnsureDB()
    local styles = type(shared) == "table" and shared.specialStyles or nil
    local legacy = type(styles) == "table" and type(styles[kind]) == "table" and styles[kind] or nil
    if legacy then
        item.placed = type(item.placed) == "table" and item.placed or {}
        local sourcePlaced = type(legacy.placed) == "table" and legacy.placed or nil
        if sourcePlaced then
            for key in pairs(Model.CustomContainerStylePlacedKeys) do
                if sourcePlaced[key] ~= nil then item.placed[key] = DeepCopy(sourcePlaced[key]) end
            end
        end
        if type(legacy.frame) == "table" then item.frame = DeepCopy(legacy.frame) end
    end
    item._msufA3LocalStyleFromShared_v1 = true
end

function Model.CustomContainerStyleItem(unit, index, create)
    return Model.CustomContainer(unit, index, create)
end

local function SelectedCopy(source, keys)
    local out = {}
    if type(source) ~= "table" then return out end
    for key in pairs(keys) do
        if source[key] ~= nil then out[key] = DeepCopy(source[key]) end
    end
    return out
end

--- Captures only the values exposed by Aura Style.  Aura Options can therefore
--- replace the rest of a frame's Aura workspace without accidentally changing
--- its visual presentation.
function Model.CaptureUnitStyle(unit)
    unit = NormalizeUnit(unit)
    local auras = Model.EnsureDB()
    if type(auras) ~= "table" then return nil end
    local sourceRecord = PerUnit(auras, unit, false)
    local snapshot = {
        ownsStyle = UnitStyleOverrideActive(sourceRecord),
        layout = SelectedCopy(sourceRecord and sourceRecord.layout, STYLE_LAYOUT_KEYS),
        layoutShared = SelectedCopy(sourceRecord and sourceRecord.layoutShared, STYLE_SHARED_LAYOUT_KEYS),
        custom = {},
    }
    for index = 1, CUSTOM_CONTAINER_MAX do
        local item = Model.CustomContainer(unit, index, true)
        local placed = type(item) == "table" and type(item.placed) == "table" and item.placed or nil
        snapshot.custom[index] = {
            product = CustomContainerStyleProduct(unit, index),
            placed = SelectedCopy(placed, Model.CustomContainerStylePlacedKeys),
            frame = type(item) == "table" and type(item.frame) == "table" and DeepCopy(item.frame) or nil,
        }
    end
    return snapshot
end

function Model.ApplyUnitStyleSnapshot(destinationUnit, snapshot)
    destinationUnit = NormalizeUnit(destinationUnit)
    if type(snapshot) ~= "table" then return false end
    local auras = Model.EnsureDB()
    if type(auras) ~= "table" then return false end

    EachRuntimeUnit(destinationUnit, function(runtimeUnit)
        local destinationRecord = PerUnit(auras, runtimeUnit, true)
        if not destinationRecord then return end
        destinationRecord.layout = type(destinationRecord.layout) == "table" and destinationRecord.layout or {}
        destinationRecord.layoutShared = type(destinationRecord.layoutShared) == "table" and destinationRecord.layoutShared or {}
        ClearKeys(destinationRecord.layout, STYLE_LAYOUT_KEYS)
        ClearKeys(destinationRecord.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
        if snapshot.ownsStyle == true then
            for key, value in pairs(snapshot.layout or {}) do destinationRecord.layout[key] = DeepCopy(value) end
            for key, value in pairs(snapshot.layoutShared or {}) do destinationRecord.layoutShared[key] = DeepCopy(value) end
            destinationRecord.overrideStyle = true
        else
            destinationRecord.overrideStyle = false
        end
        RefreshLayoutOverrideFlags(destinationRecord)
    end)

    for index = 1, CUSTOM_CONTAINER_MAX do
        local destinationItem = Model.CustomContainer(destinationUnit, index, true)
        local sourceStyle = type(snapshot.custom) == "table" and snapshot.custom[index] or nil
        if destinationItem and type(sourceStyle) == "table" then
            destinationItem.placed = type(destinationItem.placed) == "table" and destinationItem.placed or {}
            local destinationProduct = CustomContainerStyleProduct(destinationUnit, index)
            local preserveDestinationProductStyle = sourceStyle.product ~= nil
                and destinationProduct ~= nil
                and sourceStyle.product ~= destinationProduct
            local destinationProductStyle
            local destinationPandemicFrameCondition
            if preserveDestinationProductStyle then
                destinationProductStyle = SelectedCopy(
                    destinationItem.placed, INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS)
                destinationPandemicFrameCondition = type(destinationItem.frame) == "table"
                    and destinationItem.frame.onlyInPandemicWindow == true or false
            end
            ClearKeys(destinationItem.placed, Model.CustomContainerStylePlacedKeys)
            for key, value in pairs(sourceStyle.placed or {}) do destinationItem.placed[key] = DeepCopy(value) end
            if preserveDestinationProductStyle then
                -- Iterate the complete schema so an absent destination value
                -- also removes an incompatible source-only value.
                for key in pairs(INCOMPATIBLE_CUSTOM4_DESTINATION_STYLE_KEYS) do
                    destinationItem.placed[key] = DeepCopy(destinationProductStyle[key])
                end
            end
            destinationItem.frame = type(sourceStyle.frame) == "table" and DeepCopy(sourceStyle.frame) or nil
            if preserveDestinationProductStyle and type(destinationItem.frame) == "table" then
                destinationItem.frame.onlyInPandemicWindow = destinationPandemicFrameCondition
            end
            destinationItem._msufA3LocalStyleFromShared_v1 = true
            -- Re-apply the product invariants without replacing copied Style.
            Model.CustomContainer(destinationUnit, index, true)
        end
    end
    return true
end

function Model.CopyUnitStyle(sourceUnit, destinationUnit)
    sourceUnit, destinationUnit = NormalizeUnit(sourceUnit), NormalizeUnit(destinationUnit)
    if sourceUnit == destinationUnit then return false end
    return Model.ApplyUnitStyleSnapshot(destinationUnit, Model.CaptureUnitStyle(sourceUnit))
end

function Model.ResetCustomContainer(unit, index)
    unit = NormalizeScope(unit)
    if unit == "shared" then unit = "player" end
    local record = EnsureUnitCustomContainers(unit, true)
    index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
    record.items[index] = NewCustomContainer(index, unit)
    return record.items[index]
end

local function CustomContainerSpellSet(item)
    local set = {}
    local raw = item and item.spellIDs
    if type(raw) == "string" then
        for token in raw:gmatch("%d+") do
            local spellID = tonumber(token)
            if spellID and spellID > 0 then set[math_floor(spellID)] = true end
        end
    elseif type(raw) == "table" then
        for key, enabled in pairs(raw) do
            local spellID = tonumber((type(enabled) == "number" or type(enabled) == "string") and enabled or key)
            if enabled ~= false and spellID and spellID > 0 then set[math_floor(spellID)] = true end
        end
    end
    return set
end

local function WriteCustomContainerSpellSet(item, set)
    local ids = {}
    for spellID, enabled in pairs(set or {}) do
        if enabled == true then ids[#ids + 1] = tonumber(spellID) end
    end
    table_sort(ids)
    for i = 1, #ids do ids[i] = tostring(ids[i]) end
    item.spellIDs = table.concat(ids, ", ")
end

local function ReconcileCustomContainerSpellPriority(item, create)
    local set = CustomContainerSpellSet(item)
    local raw = item and item.prioritySpellIDs
    local ordered, seen = {}, {}
    local function Add(value)
        local spellID = tonumber(value)
        if spellID then spellID = math_floor(spellID + 0.5) end
        if spellID and spellID > 0 and set[spellID] == true and not seen[spellID] then
            seen[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end
    if type(raw) == "string" then
        for token in raw:gmatch("%d+") do Add(token) end
    elseif type(raw) == "table" then
        for i = 1, #raw do Add(raw[i]) end
        for key, value in pairs(raw) do
            if type(key) ~= "number" or key < 1 or key > #raw or key % 1 ~= 0 then
                Add((type(value) == "number" or type(value) == "string") and value or key)
            end
        end
    end
    if create == true then
        local missing = {}
        for spellID in pairs(set) do
            if not seen[spellID] then
                local _, name = SpellInfo(spellID)
                missing[#missing + 1] = {
                    spellID = spellID,
                    key = tostring(name or ""):lower() .. "\030" .. tostring(spellID),
                }
            end
        end
        table_sort(missing, function(a, b) return a.key < b.key end)
        for i = 1, #missing do ordered[#ordered + 1] = missing[i].spellID end
    end
    if create == true or raw ~= nil then item.prioritySpellIDs = ordered end
    return ordered
end

function Model.EnableCustomContainerSpellPriority(unit, index)
    local item = Model.CustomContainer(unit, index, true)
    if not item then return false end
    ReconcileCustomContainerSpellPriority(item, true)
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.placed.sortMethod = "CUSTOM_PRIORITY"
    item.placed.sortReverse = false
    return true
end

function Model.MoveCustomContainerSpell(unit, index, value, direction)
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false, "invalid" end
    local ordered = ReconcileCustomContainerSpellPriority(item, true)
    local from
    for i = 1, #ordered do
        if ordered[i] == spellID then from = i; break end
    end
    direction = tonumber(direction) or 0
    local to = from and (direction < 0 and from - 1 or direction > 0 and from + 1 or from)
    if not (from and to and to >= 1 and to <= #ordered and to ~= from) then return false, "unchanged" end
    ordered[from], ordered[to] = ordered[to], ordered[from]
    item.prioritySpellIDs = ordered
    return true
end

function Model.MoveCustomContainerSpellToIndex(unit, index, value, targetIndex)
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false, "invalid" end
    local ordered = ReconcileCustomContainerSpellPriority(item, true)
    local from
    for i = 1, #ordered do
        if ordered[i] == spellID then from = i; break end
    end
    local to = math_floor(tonumber(targetIndex) or 0)
    if not from or to < 1 or to > #ordered or to == from then return false, "unchanged" end
    table.remove(ordered, from)
    table.insert(ordered, to, spellID)
    item.prioritySpellIDs = ordered
    return true
end

function Model.AddCustomContainerSpell(unit, index, value, allowCustomID)
    unit = NormalizeScope(unit)
    if unit == "shared" then unit = "player" end
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false, "invalid" end
    if unit == "player" and index == PLAYER_DEFENSIVE_CONTAINER_INDEX
        and Model.IsPlayerDefensiveSpell(spellID)
        and type(Model.SetPlayerDefensiveSpellEnabled) == "function"
    then
        return Model.SetPlayerDefensiveSpellEnabled(unit, spellID, true)
    end
    local customTargetDot = unit ~= "player" and index == TARGET_DOT_CONTAINER_INDEX
        and not Model.IsTargetDotSpell(spellID)
    if customTargetDot and allowCustomID ~= true then return false, "not-dot" end
    local set = CustomContainerSpellSet(item)
    if set[spellID] == true then
        if customTargetDot then
            item.customSpellIDs = type(item.customSpellIDs) == "table" and item.customSpellIDs or {}
            if item.customSpellIDs[spellID] ~= true then
                item.customSpellIDs[spellID] = true
                return true
            end
        end
        return false, "unchanged"
    end
    local count = 0
    for _, enabled in pairs(set) do if enabled == true then count = count + 1 end end
    if count >= 40 then return false, "full" end
    if customTargetDot then
        item.customSpellIDs = type(item.customSpellIDs) == "table" and item.customSpellIDs or {}
        item.customSpellIDs[spellID] = true
    end
    set[spellID] = true
    WriteCustomContainerSpellSet(item, set)
    if item.prioritySpellIDs ~= nil then ReconcileCustomContainerSpellPriority(item, true) end
    return true
end

function Model.RemoveCustomContainerSpell(unit, index, value)
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false, "invalid" end
    local set = CustomContainerSpellSet(item)
    if set[spellID] ~= true then return false, "unchanged" end
    set[spellID] = nil
    if type(item.customSpellIDs) == "table" then item.customSpellIDs[spellID] = nil end
    WriteCustomContainerSpellSet(item, set)
    if item.prioritySpellIDs ~= nil then ReconcileCustomContainerSpellPriority(item, false) end
    return true
end

function Model.ClearCustomContainerSpells(unit, index)
    local item = Model.CustomContainer(unit, index, true)
    if not item then return 0 end
    local count = 0
    for _, enabled in pairs(CustomContainerSpellSet(item)) do
        if enabled == true then count = count + 1 end
    end
    if count > 0 then WriteCustomContainerSpellSet(item, {}) end
    item.customSpellIDs = nil
    item.prioritySpellIDs = nil
    return count
end

function Model.CustomContainerSpellEntries(unit, index)
    local item = Model.CustomContainer(unit, index, false)
    local customSpellIDs = type(item and item.customSpellIDs) == "table" and item.customSpellIDs or nil
    local out, bySpellID = {}, {}
    for spellID in pairs(CustomContainerSpellSet(item)) do
        local id, name, icon = SpellInfo(spellID)
        id = id or spellID
        local entry = {
            value = tostring(id), spellID = id, icon = icon,
            text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
            customID = customSpellIDs and customSpellIDs[id] == true or false,
        }
        out[#out + 1] = entry
        bySpellID[id] = entry
    end
    table_sort(out, function(a, b) return tostring(a.text) < tostring(b.text) end)
    local priority = ReconcileCustomContainerSpellPriority(item, false)
    if #priority > 0 then
        local prioritized, used = {}, {}
        for i = 1, #priority do
            local entry = bySpellID[priority[i]]
            if entry then prioritized[#prioritized + 1] = entry; used[entry] = true end
        end
        for i = 1, #out do
            if not used[out[i]] then prioritized[#prioritized + 1] = out[i] end
        end
        out = prioritized
    end
    for i = 1, #out do out[i].priority = i end
    return out
end

--- Entries the runtime would actually track for a custom container, for 1:1
--- previews. The target-dot container mirrors the runtime include filter: only
--- curated dot IDs plus explicitly allowed custom IDs survive. Empty means
--- empty - previews outside edit mode render nothing for this container.
function Model.CustomContainerPreviewEntries(unit, index)
    unit = NormalizeScope(unit)
    if unit == "shared" then unit = "player" end
    index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
    local entries = Model.CustomContainerSpellEntries(unit, index)
    if unit == "player" and index == PLAYER_DEFENSIVE_CONTAINER_INDEX then
        local out, seen = {}, {}
        local builtins = type(Model.PlayerDefensivePreviewEntries) == "function"
            and Model.PlayerDefensivePreviewEntries() or {}
        for i = 1, #builtins do
            local entry = builtins[i]
            if entry and entry.spellID then
                seen[entry.spellID] = true
                out[#out + 1] = entry
            end
        end
        for i = 1, #entries do
            local entry = entries[i]
            if entry and entry.spellID and not seen[entry.spellID] then
                seen[entry.spellID] = true
                out[#out + 1] = entry
            end
        end
        return out
    end
    if index ~= TARGET_DOT_CONTAINER_INDEX or #entries == 0 then return entries end
    local out = {}
    for i = 1, #entries do
        local entry = entries[i]
        if entry.customID == true or Model.IsTargetDotSpell(entry.spellID) then
            out[#out + 1] = entry
        end
    end
    return out
end

local TARGET_DOT_CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}
local TARGET_DOT_CLASS_LABELS = {
    DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", DRUID = "Druid",
    EVOKER = "Evoker", HUNTER = "Hunter", MAGE = "Mage", MONK = "Monk",
    PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
    WARLOCK = "Warlock", WARRIOR = "Warrior",
}

local function TargetDotLookup()
    local lookup = A3._targetDotLookup
    if lookup then return lookup end
    lookup = {}
    for _, spells in pairs(A3.TargetDotData or {}) do
        for i = 1, #spells do lookup[tonumber(spells[i][1])] = true end
    end
    A3._targetDotLookup = lookup
    return lookup
end

function Model.IsTargetDotSpell(value)
    local spellID = SpellIDFromInput(value)
    return spellID and TargetDotLookup()[spellID] == true or false
end

function Model.TargetDotValues()
    local values = {}
    local playerClass
    if type(UnitClass) == "function" then local _; _, playerClass = UnitClass("player") end
    local order = {}
    if playerClass and A3.TargetDotData and A3.TargetDotData[playerClass] then order[#order + 1] = playerClass end
    for i = 1, #TARGET_DOT_CLASS_ORDER do
        local class = TARGET_DOT_CLASS_ORDER[i]
        if class ~= playerClass then order[#order + 1] = class end
    end
    for i = 1, #order do
        local class = order[i]
        local spells = A3.TargetDotData and A3.TargetDotData[class]
        if type(spells) == "table" and #spells > 0 then
            values[#values + 1] = { text = TARGET_DOT_CLASS_LABELS[class] or class, header = true, disabled = true, translate = false }
            for j = 1, #spells do
                local spellID, fallback = tonumber(spells[j][1]), spells[j][2]
                local id, name, icon = SpellInfo(spellID)
                values[#values + 1] = {
                    value = tostring(id or spellID), spellID = id or spellID, icon = icon,
                    text = (type(name) == "string" and name ~= "" and name or fallback or "Spell") .. " (#" .. tostring(id or spellID) .. ")",
                    class = class,
                }
            end
        end
    end
    return values
end

local function PlayerDefensiveLookup()
    local lookup = A3._playerDefensiveLookup
    if lookup then return lookup end
    lookup = {}
    for _, spells in pairs(A3.PlayerDefensiveData or {}) do
        for i = 1, #spells do lookup[tonumber(spells[i][1])] = true end
    end
    A3._playerDefensiveLookup = lookup
    return lookup
end

function Model.IsPlayerDefensiveSpell(value)
    local spellID = SpellIDFromInput(value)
    return spellID and PlayerDefensiveLookup()[spellID] == true or false
end

local function PlayerClassToken()
    if type(UnitClass) == "function" then
        local _, class = UnitClass("player")
        if type(class) == "string" and class ~= "" then return class end
    end
end

local function DefensiveEntry(spellID, fallback, class)
    local id, name, icon = SpellInfo(spellID)
    id = id or spellID
    return {
        value = tostring(id), spellID = id, icon = icon,
        text = (type(name) == "string" and name ~= "" and name or fallback or "Spell")
            .. " (#" .. tostring(id) .. ")",
        class = class,
        predefined = true,
    }
end

local function PlayerDefensiveDisabledSet(unit, create)
    local item = Model.CustomContainer(unit or "player", PLAYER_DEFENSIVE_CONTAINER_INDEX, create == true)
    if not item then return nil end
    local disabled = item.disabledPredefinedSpellIDs
    if type(disabled) ~= "table" and create == true then
        disabled = {}
        item.disabledPredefinedSpellIDs = disabled
    end
    return type(disabled) == "table" and disabled or nil
end

function Model.PlayerDefensiveSpellEnabled(unit, value)
    local spellID = SpellIDFromInput(value)
    if not (spellID and PlayerDefensiveLookup()[spellID] == true) then return false end
    local disabled = PlayerDefensiveDisabledSet(unit, false)
    return not (disabled and (disabled[spellID] == true or disabled[tostring(spellID)] == true))
end

function Model.SetPlayerDefensiveSpellEnabled(unit, value, enabled)
    local spellID = SpellIDFromInput(value)
    if not (spellID and PlayerDefensiveLookup()[spellID] == true) then return false, "invalid" end
    local disabled = PlayerDefensiveDisabledSet(unit, true)
    local wasEnabled = not (disabled[spellID] == true or disabled[tostring(spellID)] == true)
    enabled = enabled == true
    if wasEnabled == enabled then return false, "unchanged" end
    if enabled then
        disabled[spellID] = nil
    else
        disabled[spellID] = true
    end
    disabled[tostring(spellID)] = nil
    return true
end

function Model.PlayerDefensiveClassEntries(includeDisabled)
    local class = PlayerClassToken()
    local spells = class and A3.PlayerDefensiveData and A3.PlayerDefensiveData[class]
    local out = {}
    if type(spells) ~= "table" then return out end
    for i = 1, #spells do
        local entry = DefensiveEntry(tonumber(spells[i][1]), spells[i][2], class)
        entry.enabled = Model.PlayerDefensiveSpellEnabled("player", entry.spellID)
        if includeDisabled == true or entry.enabled then out[#out + 1] = entry end
    end
    return out
end

function Model.PlayerDefensiveValues()
    local values, playerClass, order = {}, PlayerClassToken(), {}
    if playerClass and A3.PlayerDefensiveData and A3.PlayerDefensiveData[playerClass] then
        order[#order + 1] = playerClass
    end
    for i = 1, #TARGET_DOT_CLASS_ORDER do
        local class = TARGET_DOT_CLASS_ORDER[i]
        if class ~= playerClass then order[#order + 1] = class end
    end
    for i = 1, #order do
        local class = order[i]
        local spells = A3.PlayerDefensiveData and A3.PlayerDefensiveData[class]
        if type(spells) == "table" and #spells > 0 then
            values[#values + 1] = {
                text = TARGET_DOT_CLASS_LABELS[class] or class,
                header = true, disabled = true, translate = false,
            }
            for j = 1, #spells do
                values[#values + 1] = DefensiveEntry(tonumber(spells[j][1]), spells[j][2], class)
            end
        end
    end
    return values
end

function Model.PlayerDefensivePreviewEntries()
    return Model.PlayerDefensiveClassEntries(false)
end

function Model.WriteLaneLayer(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    Model.WriteNumber(unit, spec and spec.layerKey or "buffLayer", value, 0, 30)
end

function Model.WriteLaneStrata(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    value = tostring(value or "AUTO"):upper()
    if not FRAME_STRATA_OK[value] then value = "AUTO" end
    Model.WriteValue(unit, spec and spec.strataKey or "buffStrata", value)
end

function Model.ReadStackAnchor(unit)
    local v = tostring(Model.ReadValue(unit, "stackCountAnchor", "TOPRIGHT") or "TOPRIGHT")
    return STACK_ANCHOR_OK[v] and v or "TOPRIGHT"
end

function Model.WriteStackAnchor(unit, value)
    value = STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
    Model.WriteValue(unit, "stackCountAnchor", value)
end

local function LaneStyleKey(kind, key)
    kind = NormalizeKind(kind)
    local map = LANE_STYLE_KEYS[kind]
    return map and map[key] or key
end

local function ReadLaneStyleRaw(unit, kind, key)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return nil end
    local laneKey = LaneStyleKey(kind, key)
    if NormalizeScope(unit) == "shared" then return shared[laneKey] end
    local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
    local localOwner = STYLE_SHARED_LAYOUT_KEYS[laneKey] and sharedLayout or layout
    if type(localOwner) == "table" then
        return localOwner[laneKey]
    end
    return nil
end

function Model.ReadLaneStyleBool(unit, kind, key, defaultValue)
    local value = ReadLaneStyleRaw(unit, kind, key)
    if value == nil then return defaultValue and true or false end
    return value == true
end

function Model.WriteLaneStyleBool(unit, kind, key, value)
    Model.WriteValue(unit, LaneStyleKey(kind, key), value and true or false)
end

function Model.ReadLaneStyleString(unit, kind, key, defaultValue)
    if key == "iconShape" then
        return Model.ReadSharedAppearanceIconShape(kind)
    end
    local value = ReadLaneStyleRaw(unit, kind, key)
    return tostring(value or defaultValue or "")
end

function Model.WriteLaneStyleString(unit, kind, key, value)
    if key == "iconShape" then
        Model.WriteSharedAppearanceIconShape(kind, value)
        return
    end
    Model.WriteValue(unit, LaneStyleKey(kind, key), tostring(value or ""))
end

function Model.ReadDebuffTypeBorderMode(unit)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return "OFF" end
    if NormalizeScope(unit) ~= "shared" then
        local _, sharedLayout = EffectiveLayoutTables(auras, unit)
        if type(sharedLayout) == "table" then
            local storedMode = sharedLayout.debuffTypeBorderMode
            if storedMode == nil then storedMode = sharedLayout.dispelBorderMode end
            if storedMode ~= nil then
                local mode = NormalizeDebuffTypeBorderMode(storedMode, "OFF")
                return (mode == "OFF" and sharedLayout.useDebuffTypeBorders == true) and "SYMBOL" or mode
            end
            if sharedLayout.useDebuffTypeBorders ~= nil then
                return sharedLayout.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
            end
        end
    end
    local storedMode = shared.debuffTypeBorderMode
    if storedMode == nil then storedMode = shared.dispelBorderMode end
    if storedMode ~= nil then
        local mode = NormalizeDebuffTypeBorderMode(storedMode, "OFF")
        return (mode == "OFF" and shared.useDebuffTypeBorders == true) and "SYMBOL" or mode
    end
    return shared.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
end

function Model.WriteDebuffTypeBorderMode(unit, value)
    value = NormalizeDebuffTypeBorderMode(value, "OFF")
    Model.WriteValue(unit, "debuffTypeBorderMode", value)
    Model.WriteValue(unit, "useDebuffTypeBorders", value ~= "OFF")
end

function Model.ReadLaneStyleNumber(unit, kind, key, defaultValue, minValue, maxValue)
    local value = ReadLaneStyleRaw(unit, kind, key)
    return ClampNumber(value, defaultValue, minValue, maxValue)
end

function Model.WriteLaneStyleNumber(unit, kind, key, value, minValue, maxValue)
    value = ClampNumber(value, 0, minValue, maxValue)
    if math_floor(value) == value then value = Round(value) end
    Model.WriteValue(unit, LaneStyleKey(kind, key), value)
end

function Model.ReadLaneStackAnchor(unit, kind)
    local value = tostring(ReadLaneStyleRaw(unit, kind, "stackCountAnchor") or "TOPRIGHT")
    return STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
end

function Model.WriteLaneStackAnchor(unit, kind, value)
    value = STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
    Model.WriteValue(unit, LaneStyleKey(kind, "stackCountAnchor"), value)
end

function Model.ReadCooldownAnchor(unit)
    local v = tostring(Model.ReadValue(unit, "cooldownTextAnchor", "CENTER") or "CENTER")
    return AURA_ANCHOR_OK[v] and v or "CENTER"
end

function Model.WriteCooldownAnchor(unit, value)
    value = AURA_ANCHOR_OK[value] and value or "CENTER"
    Model.WriteValue(unit, "cooldownTextAnchor", value)
end

function Model.ReadLaneCooldownAnchor(unit, kind)
    local value = tostring(ReadLaneStyleRaw(unit, kind, "cooldownTextAnchor") or "CENTER")
    return AURA_ANCHOR_OK[value] and value or "CENTER"
end

function Model.WriteLaneCooldownAnchor(unit, kind, value)
    value = AURA_ANCHOR_OK[value] and value or "CENTER"
    Model.WriteValue(unit, LaneStyleKey(kind, "cooldownTextAnchor"), value)
end

local function NormalizeDurationBarPosition(value, fallback)
    value = tostring(value or fallback or "BOTTOM"):upper()
    return DURATION_BAR_POSITION_OK[value] and value or "BOTTOM"
end

local function NormalizeDurationBarDirection(value, fallback)
    value = tostring(value or fallback or "REMAINING"):upper()
    if value == "ELAPSED_TIME" then value = "ELAPSED" end
    return DURATION_BAR_DIRECTION_OK[value] and value or "REMAINING"
end

local function NormalizeDurationBarDisplay(value, fallback)
    value = tostring(value or fallback or "BAR_ONLY"):upper()
    if value == "ICON" or value == "ICONS" or value == "ICON_BAR" or value == "ICON+BAR" then value = "OVERLAY" end
    return DURATION_BAR_DISPLAY_OK[value] and value or "BAR_ONLY"
end

function Model.ReadLaneDurationBarPosition(unit, kind)
    local value = ReadLaneStyleRaw(unit, kind, "durationBarPosition")
    return NormalizeDurationBarPosition(value, "BOTTOM")
end

function Model.WriteLaneDurationBarPosition(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarPosition"), NormalizeDurationBarPosition(value, "BOTTOM"))
end

function Model.ReadLaneDurationBarDirection(unit, kind)
    local value = ReadLaneStyleRaw(unit, kind, "durationBarDirection")
    return NormalizeDurationBarDirection(value, "REMAINING")
end

function Model.WriteLaneDurationBarDirection(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDirection"), NormalizeDurationBarDirection(value, "REMAINING"))
end

function Model.ReadLaneDurationBarDisplay(unit, kind)
    local value = ReadLaneStyleRaw(unit, kind, "durationBarDisplay")
    return NormalizeDurationBarDisplay(value, "BAR_ONLY")
end

function Model.WriteLaneDurationBarDisplay(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDisplay"), NormalizeDurationBarDisplay(value, "BAR_ONLY"))
end

function Model.GroupShown(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if not spec or Model.ReadBool(unit, spec.showKey, true) ~= true then return false end
    return Model.ReadNumber(unit, spec.maxKey, 12, 0, 80) > 0
end

function Model.SetGroupShown(unit, kind, shown)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if not spec then return end
    Model.WriteBool(unit, spec.showKey, shown == true)
    if shown then
        if Model.ReadNumber(unit, spec.maxKey, 0, 0, 80) <= 0 then
            Model.WriteNumber(unit, spec.maxKey, kind == "buff" and 8 or 12, 0, 80)
        end
    end
end

--- Filter scopes are independent from visual layout scopes. A unit can share
--- its icon positions while overriding aura rules, so reads/writes go through
--- EnsureScopeFilters rather than the layout helpers above.
local function EnsureRuntimeFilters(auras, shared, unit, create)
    local pu = PerUnit(auras, unit, create)
    if not pu then return DEFAULT_SHARED.filters end
    if create then
        pu.overrideFilters = true
        if type(pu.filters) ~= "table" then pu.filters = DeepCopy(DEFAULT_SHARED.filters) end
        DefaultsIntoOnce(pu.filters, DEFAULT_SHARED.filters)
        return pu.filters
    end
    if type(pu.filters) == "table" then
        DefaultsIntoOnce(pu.filters, DEFAULT_SHARED.filters)
        return pu.filters
    end
    return DEFAULT_SHARED.filters
end

local function EnsureScopeFilters(scope, create)
    local auras, shared = Model.EnsureDB()
    scope = NormalizeScope(scope)
    if scope == "shared" then
        DefaultsIntoOnce(shared.filters, DEFAULT_SHARED.filters)
        return shared.filters
    end
    return EnsureRuntimeFilters(auras, shared, RuntimeUnit(scope), create)
end

local function ForEachScopeFilters(scope, create, callback)
    if type(callback) ~= "function" then return end
    local auras, shared = Model.EnsureDB()
    scope = NormalizeScope(scope)
    if scope == "shared" then
        DefaultsIntoOnce(shared.filters, DEFAULT_SHARED.filters)
        callback(shared.filters, true, shared)
        return
    end
    EachRuntimeUnit(scope, function(runtimeUnit)
        callback(EnsureRuntimeFilters(auras, shared, runtimeUnit, create), false, shared)
    end)
end

function Model.UseSharedRules(scope)
    return false
end

function Model.SetUseSharedRules(scope, useShared)
    scope = NormalizeScope(scope)
    if scope == "shared" then return end
    local auras, shared = Model.EnsureDB()
    EachRuntimeUnit(scope, function(runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
        local f = EnsureRuntimeFilters(auras, shared, runtimeUnit, true)
        pu.filters = f
        pu.overrideFilters = true
    end)
end

function Model.ReadFilter(scope, kind, key, defaultValue)
    local filters = EnsureScopeFilters(scope, false)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    local group = filters and filters[tableKey]
    if type(group) ~= "table" then return defaultValue end
    local value = group[key]
    if key == "exclusive" and value == "important" then return "none" end
    if value ~= nil then return value end
    return defaultValue
end

function Model.WriteFilter(scope, kind, key, value)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    if key == "exclusive" and value == "important" then value = "none" end
    ForEachScopeFilters(scope, true, function(filters)
        if type(filters) ~= "table" then return end
        if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
        filters[tableKey][key] = value
    end)
end

function Model.LaneFiltersEnabled(scope, kind)
    local filters = EnsureScopeFilters(scope, false)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    local lane = type(filters) == "table" and filters[tableKey] or nil
    return type(lane) ~= "table" or lane.enabled ~= false
end

function Model.SetLaneFiltersEnabled(scope, kind, enabled)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    ForEachScopeFilters(scope, true, function(filters)
        if type(filters) ~= "table" then return end
        if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
        filters[tableKey].enabled = enabled == true
    end)
end

function Model.ScopeFiltersEnabled(scope)
    return Model.LaneFiltersEnabled(scope, "buff")
        and Model.LaneFiltersEnabled(scope, "debuff")
end

local function ApplyScopeFiltersEnabled(filters, enabled, sharedScope, shared)
    if type(filters) ~= "table" then return end

    local snap = filters.disabledSnapshot
    if enabled then
        if type(snap) == "table" then
            for groupKey, keys in pairs(RUNTIME_FILTER_KEYS) do
                local group = filters[groupKey]
                local groupSnap = snap[groupKey]
                if type(group) == "table" and type(groupSnap) == "table" then
                    for i = 1, #keys do
                        local key = keys[i]
                        if groupSnap[key] ~= nil then group[key] = groupSnap[key] end
                    end
                end
            end
            if sharedScope and type(shared) == "table" then
                if snap.onlyMyBuffs ~= nil then shared.onlyMyBuffs = snap.onlyMyBuffs end
                if snap.onlyMyDebuffs ~= nil then shared.onlyMyDebuffs = snap.onlyMyDebuffs end
            end
            if snap.hidePermanent ~= nil then
                filters.hidePermanent = snap.hidePermanent == true
            end
            filters.disabledSnapshot = nil
        end
        filters.enabled = true
        return
    end

    if type(snap) ~= "table" then
        snap = {}
        for groupKey, keys in pairs(RUNTIME_FILTER_KEYS) do
            local group = filters[groupKey]
            if type(group) == "table" then
                local groupSnap = {}
                for i = 1, #keys do
                    local key = keys[i]
                    groupSnap[key] = group[key]
                end
                snap[groupKey] = groupSnap
            end
        end
        if sharedScope and type(shared) == "table" then
            snap.onlyMyBuffs = shared.onlyMyBuffs
            snap.onlyMyDebuffs = shared.onlyMyDebuffs
        end
        filters.disabledSnapshot = snap
    end

    if type(filters.buffs) == "table" then
        filters.buffs.onlyMine = false
        filters.buffs.onlyImportant = false
        filters.buffs.raid = false
        filters.buffs.raidInCombat = false
        filters.buffs.includeNameplateOnly = false
        filters.buffs.includeDispellable = false
        filters.buffs.dispellableAny = false
        filters.buffs.cancelable = false
        filters.buffs.notCancelable = false
        filters.buffs.externalDefensive = false
        filters.buffs.bigDefensive = false
        filters.buffs.exclusive = "none"
    end
    if type(filters.debuffs) == "table" then
        filters.debuffs.onlyMine = false
        filters.debuffs.onlyImportant = false
        filters.debuffs.raid = false
        filters.debuffs.raidInCombat = false
        filters.debuffs.includeNameplateOnly = false
        filters.debuffs.includeDispellable = false
        filters.debuffs.dispellableAny = false
        filters.debuffs.crowdControl = false
        filters.debuffs.nonPlayer = false
        filters.debuffs.exclusive = "none"
    end
    if sharedScope and type(shared) == "table" then
        shared.onlyMyBuffs = false
        shared.onlyMyDebuffs = false
    end
    filters.enabled = false
end

function Model.SetScopeFiltersEnabled(scope, enabled)
    ForEachScopeFilters(scope, true, function(filters, sharedScope, shared)
        ApplyScopeFiltersEnabled(filters, enabled == true, sharedScope, shared)
        filters.buffs = type(filters.buffs) == "table" and filters.buffs or {}
        filters.debuffs = type(filters.debuffs) == "table" and filters.debuffs or {}
        filters.buffs.enabled = enabled == true
        filters.debuffs.enabled = enabled == true
    end)
end

--- Blacklists remain saved in human-editable form. The 12.1 native runtime does
--- not rebuild blacklist tables during aura display updates.
local function BlacklistLane(root, kind, create)
    if type(root) ~= "table" then return nil end
    if kind ~= "buff" and kind ~= "debuff" then
        if type(root.spells) ~= "table" and create then root.spells = {} end
        return root
    end
    local key = kind == "buff" and "buffs" or "debuffs"
    if type(root[key]) ~= "table" and create then
        root[key] = { spells = DeepCopy(type(root.spells) == "table" and root.spells or {}) }
    end
    local lane = root[key]
    if type(lane) == "table" and type(lane.spells) ~= "table" and create then lane.spells = {} end
    return lane
end

local function EnsureRuntimeBlacklist(auras, runtimeUnit, create, kind)
    local pu = PerUnit(auras, runtimeUnit, true)
    if not pu then return nil end
    pu.overrideBlacklist = true -- retained only for old profile/import compatibility
    if type(pu.blacklist) ~= "table" then pu.blacklist = { spells = {} } end
    if type(pu.blacklist.spells) ~= "table" then pu.blacklist.spells = {} end
    return BlacklistLane(pu.blacklist, kind, create) or BlacklistLane(pu.blacklist, kind, true)
end

local function EnsureBlacklist(scope, create, kind)
    local auras = Model.EnsureDB()
    scope = NormalizeScope(scope)
    if scope == "shared" then return nil end
    return EnsureRuntimeBlacklist(auras, RuntimeUnit(scope), create, kind)
end

local function ForEachFrameBlacklist(scope, create, kind, callback)
    scope = NormalizeScope(scope)
    if scope == "shared" or type(callback) ~= "function" then return end
    local auras = Model.EnsureDB()
    EachRuntimeUnit(scope, function(runtimeUnit)
        callback(EnsureRuntimeBlacklist(auras, runtimeUnit, create, kind))
    end)
end

--- Expose the manual-entry resolver so blacklist UIs can inspect what an
--- input resolves to (a typed name resolves to the player's cast SpellID,
--- which is not always the SpellID of the aura left on the unit).
function Model.ResolveSpellInputID(value)
    return SpellIDFromInput(value)
end

local function LiveAuraSecretHelpers()
    local Secrets = type(MSUF.Secrets) == "table" and MSUF.Secrets or nil
    local SafeNumber = Secrets and Secrets.SafeNumber or tonumber
    local NotSecret = Secrets and Secrets.NotSecret or function(_) return true end
    return SafeNumber, NotSecret, Secrets
end

--- Tainted aura queries hard-error under Blizzard's addon restrictions. The
--- observed denial contexts are encounters, Mythic+ (challenge restrictions),
--- PvP matches, and instanced combat while aura secrecy is active; plain
--- open-world combat keeps the query callable with per-field secrets.
local function LiveAuraAccessRestricted()
    local IsEncounterInProgress = _G.IsEncounterInProgress
    if type(IsEncounterInProgress) == "function" and IsEncounterInProgress() then return true end
    local ChallengeMode = _G.C_ChallengeMode
    if type(ChallengeMode) == "table" and type(ChallengeMode.IsChallengeModeActive) == "function"
        and ChallengeMode.IsChallengeModeActive() then return true end
    local PartyInfo = _G.C_PartyInfo
    if type(PartyInfo) == "table" and type(PartyInfo.ChallengeModeRestrictionsActive) == "function"
        and PartyInfo.ChallengeModeRestrictionsActive() then return true end
    local PvP = _G.C_PvP
    if type(PvP) == "table" and type(PvP.IsMatchActive) == "function"
        and PvP.IsMatchActive() then return true end
    local SecretsAPI = _G.C_Secrets
    if type(SecretsAPI) == "table" and type(SecretsAPI.ShouldAurasBeSecret) == "function"
        and SecretsAPI.ShouldAurasBeSecret() == true then
        local IsInInstance = _G.IsInInstance
        if type(IsInInstance) == "function" then
            local inInstance = IsInInstance()
            if inInstance == true or inInstance == 1 then return true end
        end
    end
    return false
end

--- Walk every readable aura on the live unit(s) behind a menu scope. Secret
--- aura fields are the callback's problem to skip; this only guards the unit
--- and API surface. Returns walked, accessBlockedCount (non-zero when the
--- restricted context above forbids querying at all); the callback may
--- return false to stop the walk early.
local function ForEachLiveUnitAura(scope, kind, callback)
    local CUA = _G.C_UnitAuras
    local UnitExists = _G.UnitExists
    if type(UnitExists) ~= "function" or type(CUA) ~= "table" then return false, 0 end
    local GetByIndex = type(CUA.GetAuraDataByIndex) == "function" and CUA.GetAuraDataByIndex or nil
    if not GetByIndex then return false, 0 end
    scope = NormalizeScope(scope)
    if scope == "shared" then return false, 0 end
    if LiveAuraAccessRestricted() then return false, 1 end
    local _, _, Secrets = LiveAuraSecretHelpers()
    local UnitThere = Secrets and Secrets.UnitExistsPlain
        or function(unit) local exists = UnitExists(unit) return exists == true or exists == 1 end
    local filter = NormalizeKind(kind) == "debuff" and "HARMFUL" or "HELPFUL"
    local stop = false
    EachRuntimeUnit(scope, function(runtimeUnit)
        if stop or not UnitThere(runtimeUnit) then return end
        for i = 1, 80 do
            local aura = GetByIndex(runtimeUnit, i, filter)
            if type(aura) ~= "table" then break end
            if callback(aura) == false then stop = true return end
        end
    end)
    return true, 0
end

--- Coldpath check for the manual blacklist inputs: report whether the entered
--- SpellID is visible on the live unit right now, or whether only a same-named
--- aura with a different SpellID is (the cast-ID vs aura-ID trap). Secret aura
--- fields are skipped, never compared; unreadable data yields no verdict.
function Model.FindLiveBlacklistAura(scope, spellID, kind)
    spellID = tonumber(spellID)
    if not spellID then return nil end
    local SafeNumber, NotSecret = LiveAuraSecretHelpers()
    local wantedName
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            wantedName = info.name
        end
    end
    local active, suggestion
    local walked = ForEachLiveUnitAura(scope, kind, function(aura)
        local auraID = SafeNumber(aura.spellId)
        if not auraID then return end
        if auraID == spellID then active = true return false end
        if wantedName and not suggestion then
            local auraName = aura.name
            if NotSecret(auraName) and type(auraName) == "string" and auraName == wantedName then
                suggestion = { spellID = auraID, name = auraName }
            end
        end
    end)
    if not walked then return nil end
    if active then return { status = "active", spellID = spellID, name = wantedName } end
    if suggestion then
        return { status = "mismatch", spellID = spellID, name = wantedName,
            suggestID = suggestion.spellID, suggestName = suggestion.name }
    end
    return nil
end

--- Values list for the live-aura blacklist dropdown: every aura whose SpellID
--- is readable on the unit(s) right now, carrying the exact ID the aura uses.
--- Auras with secret IDs cannot be listed (and could not be matched anyway).
function Model.LiveBlacklistAuraValues(scope, kind)
    local values = {}
    local SafeNumber, NotSecret = LiveAuraSecretHelpers()
    local seen = {}
    local unreadable = 0
    local _, secretSkipped = ForEachLiveUnitAura(scope, kind, function(aura)
        local auraID = SafeNumber(aura.spellId)
        if not auraID then unreadable = unreadable + 1 return end
        if seen[auraID] then return end
        seen[auraID] = true
        local name = aura.name
        if not (NotSecret(name) and type(name) == "string" and name ~= "") then name = nil end
        local icon = aura.icon
        if not (NotSecret(icon) and (type(icon) == "number" or type(icon) == "string")) then icon = nil end
        if not name or not icon then
            local _, staticName, staticIcon = SpellInfo(auraID)
            name = name or staticName
            icon = icon or staticIcon
        end
        local text = (type(name) == "string" and name ~= "" and name or "Spell")
            .. " (#" .. tostring(auraID) .. ")"
        values[#values + 1] = { value = auraID, text = text, name = name, icon = icon }
    end)
    table_sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
    -- The second return reports auras hidden by secret data (secret index or
    -- secret SpellID), so scan UIs can say "hidden" instead of under-counting.
    -- The third reports that Blizzard denies aura access entirely right now:
    -- under restrictions every index probes secret, so nothing is readable.
    unreadable = unreadable + (tonumber(secretSkipped) or 0)
    return values, unreadable, (#values == 0 and (tonumber(secretSkipped) or 0) > 0)
end

function Model.AddBlacklistSpell(scope, value, kind)
    local spellID = SpellIDFromInput(value)
    if not spellID then return false end
    value = tostring(spellID)
    local changed = false
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" and type(list.spells) == "table" then
            if list.spells[value] ~= true then changed = true end
            list.spells[value] = true
        end
    end)
    return changed
end

function Model.ReadBlacklistHidePermanent(scope, kind)
    local list = EnsureBlacklist(scope, false, kind)
    return type(list) == "table" and list.hidePermanent == true
end

function Model.WriteBlacklistHidePermanent(scope, kind, value)
    local nextValue = value == true
    local changed = false
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" and list.hidePermanent ~= nextValue then
            list.hidePermanent = nextValue
            changed = true
        end
    end)
    return changed
end

function Model.ReadBlacklistMaxDuration(scope, kind)
    local list = EnsureBlacklist(scope, false, kind)
    return ClampNumber(type(list) == "table" and list.maxDuration, 0, 0, 180)
end

function Model.WriteBlacklistMaxDuration(scope, kind, value)
    local nextValue = Round(ClampNumber(value, 0, 0, 180))
    local changed = false
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" and (tonumber(list.maxDuration) or 0) ~= nextValue then
            list.maxDuration = nextValue
            changed = true
        end
    end)
    return changed
end

function Model.RemoveBlacklistSpell(scope, value, kind)
    local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID = SpellIDFromInput(raw)
    local changed = false
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" and type(list.spells) == "table" then
            if spellID and list.spells[tostring(spellID)] ~= nil then
                list.spells[tostring(spellID)] = nil
                changed = true
            end
            if raw ~= "" and list.spells[raw] ~= nil then
                list.spells[raw] = nil
                changed = true
            end
        end
    end)
    return changed
end

function Model.BlacklistSummary(scope, kind)
    local list = EnsureBlacklist(scope, false, kind)
    local spells = type(list) == "table" and list.spells
    if type(spells) ~= "table" then return "No blacklisted spells." end
    local out = {}
    for key, enabled in pairs(spells) do
        if enabled == true then
            local spellID = SpellIDFromInput(key)
            out[#out + 1] = spellID and SpellLabel(spellID) or (tostring(key) .. " (unresolved)")
        end
    end
    table_sort(out)
    if #out == 0 then return "No blacklisted spells." end
    return table.concat(out, "\n")
end

function Model.BlacklistEntries(scope, kind)
    local list = EnsureBlacklist(scope, false, kind)
    local spells = type(list) == "table" and list.spells
    local out = {}
    if type(spells) ~= "table" then return out end
    for key, enabled in pairs(spells) do
        if enabled == true then
            local spellID = SpellIDFromInput(key)
            if spellID then
                local id, name, icon = SpellInfo(spellID)
                id = id or spellID
                out[#out + 1] = {
                    value = tostring(id),
                    spellID = id,
                    text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
                    icon = icon,
                }
            else
                out[#out + 1] = {
                    value = tostring(key),
                    text = tostring(key) .. " (unresolved)",
                }
            end
        end
    end
    table_sort(out, function(a, b) return tostring(a.text) < tostring(b.text) end)
    return out
end

local function CountBlacklistSpells(spells)
    if type(spells) ~= "table" then return 0 end
    local count = 0
    for _, enabled in pairs(spells) do
        if enabled == true then count = count + 1 end
    end
    return count
end

function Model.ClearBlacklistSpells(scope, kind)
    local effective = EnsureBlacklist(scope, false, kind)
    local count = CountBlacklistSpells(type(effective) == "table" and effective.spells or nil)
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" then list.spells = {} end
    end)
    return count
end

function Model.BlacklistPreparedCount(scope, kind)
    local list = EnsureBlacklist(scope, false, kind)
    local spells = type(list) == "table" and list.spells
    if type(spells) ~= "table" then return 0 end
    local count = 0
    for key, enabled in pairs(spells) do
        if enabled == true and SpellIDFromInput(key) then count = count + 1 end
    end
    return count
end

local function CleanPresetLabel(key, fallback)
    if PRESET_LABELS[key] then return PRESET_LABELS[key] end
    fallback = tostring(fallback or key or "")
    fallback = fallback:gsub("^Midnight%s+", "")
    fallback = fallback:gsub("^Healer%s*%-%s*", "")
    return fallback ~= "" and fallback or tostring(key or "")
end

local function BuildBlacklistPresetValues(allowedKeys)
    local meta = PublicAuraPresetMeta()
    local buckets = {}
    local values = {}
    for i = 1, #meta do
        local item = meta[i]
        if item and item.key and (allowedKeys == nil or allowedKeys[item.key] == true) then
            local category = PRESET_CATEGORIES[item.key] or item.category or "Other"
            if not PRESET_CATEGORY_RANK[category] then category = "Other" end
            local bucket = buckets[category]
            if not bucket then
                bucket = {}
                buckets[category] = bucket
            end
            bucket[#bucket + 1] = {
                value = item.key,
                text = CleanPresetLabel(item.key, item.label),
                tooltip = item.tooltip,
                _order = i,
            }
        end
    end
    for i = 1, #PRESET_CATEGORY_ORDER do
        local category = PRESET_CATEGORY_ORDER[i]
        local bucket = buckets[category]
        if bucket and #bucket > 0 then
            table_sort(bucket, function(a, b) return (a._order or 0) < (b._order or 0) end)
            values[#values + 1] = { text = category, header = true, disabled = true, translate = false }
            for j = 1, #bucket do
                local item = bucket[j]
                item._order = nil
                values[#values + 1] = item
            end
        end
    end
    return values
end

local function BlacklistPresetKeysForKind(kind)
    if NormalizeKind(kind) == "debuff" then return UNIT_CURATED_DEBUFF_PRESET_KEYS end
    return UNIT_BUFF_PRESET_KEYS
end

function Model.BlacklistPresetValues()
    return BuildBlacklistPresetValues(nil)
end

function Model.UnitBlacklistPresetAllowed(scope, kind, presetKey)
    kind = NormalizeKind(kind)
    presetKey = tostring(presetKey or "")
    if NormalizeScope(scope) == "shared" then return false end
    return BlacklistPresetKeysForKind(kind)[presetKey] == true
end

function Model.UnitBlacklistPresetValues(scope, kind)
    kind = NormalizeKind(kind)
    if NormalizeScope(scope) == "shared" then return {} end
    return BuildBlacklistPresetValues(BlacklistPresetKeysForKind(kind))
end

function Model.UnitBlacklistDefaultPreset(scope, kind)
    kind = NormalizeKind(kind)
    if NormalizeScope(scope) == "shared" then return nil end
    if kind == "buff" then return "RAID_BUFFS" end
    return "SATED"
end

function Model.BlacklistSpellValues(presetKey)
    local spells = PublicAuraPresetSpells()
    local set = spells and spells[presetKey or "RAID_BUFFS"] or nil
    local values = {}
    if type(set) ~= "table" then return values end
    for spellID in pairs(set) do
        local id, name, icon = SpellInfo(spellID)
        if id then
            values[#values + 1] = {
                value = tostring(id),
                text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
                icon = icon,
            }
        end
    end
    table_sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
    return values
end

function Model.UnitBlacklistSpellValues(scope, kind, presetKey)
    if not Model.UnitBlacklistPresetAllowed(scope, kind, presetKey) then return {} end
    return Model.BlacklistSpellValues(presetKey)
end

function Model.AddBlacklistPresetSpell(scope, spellID, kind)
    return Model.AddBlacklistSpell(scope, spellID, kind)
end

function Model.AddBlacklistPresetGroup(scope, presetKey, kind)
    local values = Model.UnitBlacklistSpellValues(scope, kind, presetKey)
    local count = 0
    for i = 1, #values do
        local item = values[i]
        if item and item.value and Model.AddBlacklistSpell(scope, item.value, kind) then
            count = count + 1
        end
    end
    return count
end

local function EnsureGroupBlacklistSpells(kind, groupKey, create)
    local group = GroupAuraGroup(kind, groupKey)
    if type(group.blacklist) ~= "table" then
        if not create then return nil end
        group.blacklist = {}
    end
    if type(group.blacklist.spells) ~= "table" then
        if not create then return nil end
        group.blacklist.spells = {}
    end
    return group.blacklist.spells
end

function Model.AddGroupBlacklistSpell(scope, groupKey, value)
    local spellID = SpellIDFromInput(value)
    if not spellID then return false end
    local key = tostring(spellID)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local spells = EnsureGroupBlacklistSpells(kind, groupKey, true)
        if spells and spells[key] ~= true then
            spells[key] = true
            changed = true
        end
    end
    write(a)
    if b then write(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.RemoveGroupBlacklistSpell(scope, groupKey, value)
    local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID = SpellIDFromInput(raw)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function remove(kind)
        local spells = EnsureGroupBlacklistSpells(kind, groupKey, false)
        if type(spells) ~= "table" then return end
        if spellID and spells[tostring(spellID)] ~= nil then
            spells[tostring(spellID)] = nil
            changed = true
        end
        if raw ~= "" and spells[raw] ~= nil then
            spells[raw] = nil
            changed = true
        end
    end
    remove(a)
    if b then remove(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.ClearGroupBlacklistSpells(scope, groupKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local count, changed = 0, false
    local a, b = GroupScopeKinds(scope)
    local function clear(kind)
        local spells = EnsureGroupBlacklistSpells(kind, groupKey, false)
        local n = CountBlacklistSpells(spells)
        if n > 0 then
            count = count + n
            local group = GroupAuraGroup(kind, groupKey)
            if type(group.blacklist) ~= "table" then group.blacklist = {} end
            group.blacklist.spells = {}
            changed = true
        end
    end
    clear(a)
    if b then clear(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return count
end

function Model.GroupBlacklistSummary(scope, groupKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local a = GroupScopeKinds(scope)
    local spells = EnsureGroupBlacklistSpells(a, groupKey, false)
    if type(spells) ~= "table" then return "No blacklisted spells." end
    local out = {}
    for key, enabled in pairs(spells) do
        if enabled == true then
            local spellID = SpellIDFromInput(key)
            out[#out + 1] = spellID and SpellLabel(spellID) or (tostring(key) .. " (unresolved)")
        end
    end
    table_sort(out)
    if #out == 0 then return "No blacklisted spells." end
    return table.concat(out, "\n")
end

function Model.ReadGroupBlacklistHidePermanent(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    local group = GroupAuraGroup(kind, groupKey)
    local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
    return blacklist and blacklist.hidePermanent == true or false
end

function Model.WriteGroupBlacklistHidePermanent(scope, groupKey, value)
    local nextValue = value == true
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function Write(kind)
        local group = GroupAuraGroup(kind, groupKey)
        if type(group.blacklist) ~= "table" then group.blacklist = {} end
        if group.blacklist.hidePermanent ~= nextValue then
            group.blacklist.hidePermanent = nextValue
            changed = true
        end
    end
    Write(a)
    if b then Write(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.ReadGroupBlacklistMaxDuration(scope, groupKey)
    local kind = GroupScopeKinds(scope)
    local group = GroupAuraGroup(kind, groupKey)
    local blacklist = type(group.blacklist) == "table" and group.blacklist or nil
    return ClampNumber(blacklist and blacklist.maxDuration, 0, 0, 180)
end

function Model.WriteGroupBlacklistMaxDuration(scope, groupKey, value)
    local nextValue = Round(ClampNumber(value, 0, 0, 180))
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function Write(kind)
        local group = GroupAuraGroup(kind, groupKey)
        if type(group.blacklist) ~= "table" then group.blacklist = {} end
        if (tonumber(group.blacklist.maxDuration) or 0) ~= nextValue then
            group.blacklist.maxDuration = nextValue
            changed = true
        end
    end
    Write(a)
    if b then Write(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.GroupBlacklistEntries(scope, groupKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local a = GroupScopeKinds(scope)
    local spells = EnsureGroupBlacklistSpells(a, groupKey, false)
    local out = {}
    if type(spells) ~= "table" then return out end
    for key, enabled in pairs(spells) do
        if enabled == true then
            local spellID = SpellIDFromInput(key)
            local icon
            if spellID then
                local _, _, resolvedIcon = SpellInfo(spellID)
                icon = resolvedIcon
            end
            out[#out + 1] = {
                value = spellID and tostring(spellID) or tostring(key),
                text = spellID and SpellLabel(spellID) or (tostring(key) .. " (unresolved)"),
                icon = icon,
            }
        end
    end
    table_sort(out, function(x, y) return tostring(x.text) < tostring(y.text) end)
    return out
end

function Model.GroupBlacklistPresetAllowed(groupKey, presetKey)
    presetKey = tostring(presetKey or "")
    return BlacklistPresetKeysForKind(groupKey)[presetKey] == true
end

function Model.GroupBlacklistPresetValues(groupKey)
    return BuildBlacklistPresetValues(BlacklistPresetKeysForKind(groupKey))
end

function Model.GroupBlacklistSpellValues(groupKey, presetKey)
    if not Model.GroupBlacklistPresetAllowed(groupKey, presetKey) then return {} end
    return Model.BlacklistSpellValues(presetKey)
end

function Model.AddGroupBlacklistPresetGroup(scope, groupKey, presetKey)
    local values = Model.GroupBlacklistSpellValues(groupKey, presetKey)
    local count = 0
    for i = 1, #values do
        local item = values[i]
        if item and item.value and Model.AddGroupBlacklistSpell(scope, groupKey, item.value) then
            count = count + 1
        end
    end
    return count
end

function Model.GroupBlacklistCategoryValues()
    local meta = PublicAuraPresetMeta()
    local values = {}
    if type(meta) ~= "table" then return values end
    for i = 1, #meta do
        local item = meta[i]
        if item and item.key then
            values[#values + 1] = {
                key = item.key,
                value = item.key,
                label = item.label or item.key,
                text = item.label or item.key,
                category = item.category,
                tooltip = item.tooltip,
            }
        end
    end
    return values
end

function Model.GroupBlacklistCategoryLabel(catKey)
    if catKey == "RAID_BUFFS" then return "Raid / Mythic Buffs" end
    local values = Model.GroupBlacklistCategoryValues()
    for i = 1, #values do
        local item = values[i]
        if item.key == catKey then return item.label or item.key end
    end
    return tostring(catKey or "")
end

function Model.ResolveGroupBlacklistCategory(value)
    local compact = CompactKey(value)
    if compact == "" then return nil end
    local values = Model.GroupBlacklistCategoryValues()
    local bestKey, bestLen
    for i = 1, #values do
        local item = values[i]
        local key = item.key
        local keyCompact = CompactKey(key)
        local labelCompact = CompactKey(item.label or item.text or key)
        local categoryCompact = CompactKey(item.category)
        local matchLen
        if compact == keyCompact or compact == labelCompact then
            matchLen = math.max(#keyCompact, #labelCompact)
        elseif #labelCompact >= 5 and compact:find(labelCompact, 1, true) then
            matchLen = #labelCompact
        elseif #keyCompact >= 5 and compact:find(keyCompact, 1, true) then
            matchLen = #keyCompact
        elseif #categoryCompact >= 5 and compact == categoryCompact then
            matchLen = #categoryCompact
        end
        if matchLen and (not bestLen or matchLen > bestLen) then
            bestKey, bestLen = key, matchLen
        end
    end
    return bestKey
end

function Model.ReadGroupBlacklistCategory(scope, groupKey, catKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
    if type(catKey) ~= "string" or catKey == "" then return false end
    local a = GroupScopeKinds(scope)
    local group = GroupAuraGroup(a, groupKey)
    return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
end

function Model.ReadGroupBlacklistCategoryState(scope, groupKey, catKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
    local a, b = GroupScopeKinds(scope)
    if type(catKey) ~= "string" or catKey == "" then
        if b then return { raid = false, mythicraid = false } end
        return { party = false }
    end
    local function read(kind)
        local group = GroupAuraGroup(kind, groupKey)
        return type(group.blacklistCats) == "table" and group.blacklistCats[catKey] == true
    end
    if b then
        return { raid = read(a), mythicraid = read(b) }
    end
    return { party = read(a) }
end

function Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, value)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
    if type(catKey) ~= "string" or catKey == "" then return false end
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local group = GroupAuraGroup(kind, groupKey)
        if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
        local nextValue = value and true or nil
        if group.blacklistCats[catKey] == nextValue then return end
        group.blacklistCats[catKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.WriteGroupBlacklistCategoryState(scope, groupKey, catKey, state)
    if type(state) ~= "table" then return Model.WriteGroupBlacklistCategory(scope, groupKey, catKey, state) end
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    catKey = Model.ResolveGroupBlacklistCategory(catKey) or catKey
    if type(catKey) ~= "string" or catKey == "" then return false end
    local changed = false
    local a, b = GroupScopeKinds(scope)
    local function write(kind)
        local group = GroupAuraGroup(kind, groupKey)
        if type(group.blacklistCats) ~= "table" then group.blacklistCats = {} end
        local nextValue = state[kind] == true and true or nil
        if group.blacklistCats[catKey] == nextValue then return end
        group.blacklistCats[catKey] = nextValue
        changed = true
    end
    write(a)
    if b then write(b) end
    if changed then InvalidateGroupBlacklist(scope, groupKey) end
    return changed
end

function Model.GroupBlacklistCategorySummary(scope, groupKey)
    scope = NormalizeGroupScope(scope)
    groupKey = NormalizeKind(groupKey)
    local a = GroupScopeKinds(scope)
    local group = GroupAuraGroup(a, groupKey)
    local cats = type(group.blacklistCats) == "table" and group.blacklistCats or nil
    if type(cats) ~= "table" then return "No blacklisted aura categories." end
    local out = {}
    for key, enabled in pairs(cats) do
        if enabled == true then out[#out + 1] = Model.GroupBlacklistCategoryLabel(key) end
    end
    table_sort(out)
    if #out == 0 then return "No blacklisted aura categories." end
    return table.concat(out, "\n")
end

function Model.ReadSharedBool(key, defaultValue)
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" or shared[key] == nil then return defaultValue and true or false end
    return shared[key] == true
end

function Model.WriteSharedBool(key, value)
    local _, shared = Model.EnsureDB()
    if type(shared) == "table" then shared[key] = value and true or false end
end

function Model.ReadSharedNumber(key, defaultValue, minValue, maxValue)
    local _, shared = Model.EnsureDB()
    return ClampNumber(type(shared) == "table" and shared[key] or nil, defaultValue, minValue, maxValue)
end

function Model.WriteSharedNumber(key, value, minValue, maxValue)
    local _, shared = Model.EnsureDB()
    if type(shared) == "table" then shared[key] = ClampNumber(value, 0, minValue, maxValue) end
end

function Model.ReadPreviewConfig(unit)
    unit = NormalizeUnit(unit)
    local auras, shared = Model.EnsureDB()
    if type(auras) ~= "table" or type(shared) ~= "table" then return nil end
    local runtimeCfg = type(A3.ResolveUnitFrameConfig) == "function" and A3.ResolveUnitFrameConfig(RuntimeUnit(unit)) or nil
    local buildMetrics = runtimeCfg and type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics or nil
    local buffMetrics = buildMetrics and buildMetrics(runtimeCfg, "buff") or nil
    local debuffMetrics = buildMetrics and buildMetrics(runtimeCfg, "debuff") or nil
    local customMetrics = {}
    if buildMetrics then
        for index = 1, CUSTOM_CONTAINER_MAX do
            customMetrics[index] = buildMetrics(runtimeCfg, "custom" .. tostring(index))
        end
    end
    local unitEnabled = runtimeCfg and runtimeCfg.enabled == true or Model.UnitEnabled(unit)
    local showBuffs = false
    local showDebuffs = false
    if unitEnabled then
        if buffMetrics then showBuffs = buffMetrics.enabled == true else showBuffs = Model.GroupShown(unit, "buff") end
        if debuffMetrics then showDebuffs = debuffMetrics.enabled == true else showDebuffs = Model.GroupShown(unit, "debuff") end
    end
    return {
        unit = unit,
        enabled = unitEnabled,
        showBuffs = showBuffs == true,
        showDebuffs = showDebuffs == true,
        buffMetrics = buffMetrics,
        debuffMetrics = debuffMetrics,
        customMetrics = customMetrics,
        buffX = buffMetrics and buffMetrics.x or Model.ReadNumber(unit, "buffGroupOffsetX", 0, -4096, 4096),
        buffY = buffMetrics and buffMetrics.y or Model.ReadNumber(unit, "buffGroupOffsetY", 36, -4096, 4096),
        debuffX = debuffMetrics and debuffMetrics.x or Model.ReadNumber(unit, "debuffGroupOffsetX", 0, -4096, 4096),
        debuffY = debuffMetrics and debuffMetrics.y or Model.ReadNumber(unit, "debuffGroupOffsetY", 6, -4096, 4096),
        buffAnchor = buffMetrics and buffMetrics.anchor or Model.ReadLaneAnchor(unit, "buff"),
        debuffAnchor = debuffMetrics and debuffMetrics.anchor or Model.ReadLaneAnchor(unit, "debuff"),
        buffLayer = Model.ReadLaneLayer(unit, "buff"),
        debuffLayer = Model.ReadLaneLayer(unit, "debuff"),
        buffSize = buffMetrics and buffMetrics.size or Model.ReadNumber(unit, "buffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        debuffSize = debuffMetrics and debuffMetrics.size or Model.ReadNumber(unit, "debuffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        buffIconZoom = buffMetrics and buffMetrics.iconZoom or Model.ReadLaneStyleNumber(unit, "buff", "iconZoom", 100, 100, 200),
        debuffIconZoom = debuffMetrics and debuffMetrics.iconZoom or Model.ReadLaneStyleNumber(unit, "debuff", "iconZoom", 100, 100, 200),
        buffIconShape = buffMetrics and buffMetrics.iconShape or Model.ReadLaneStyleString(unit, "buff", "iconShape", "RECTANGLE"),
        debuffIconShape = debuffMetrics and debuffMetrics.iconShape or Model.ReadLaneStyleString(unit, "debuff", "iconShape", "RECTANGLE"),
        buffRequestedIconShape = buffMetrics and buffMetrics.requestedIconShape,
        debuffRequestedIconShape = debuffMetrics and debuffMetrics.requestedIconShape,
        spacing = (buffMetrics and buffMetrics.spacing) or (debuffMetrics and debuffMetrics.spacing) or Model.ReadNumber(unit, "spacing", 2, 0, 64),
        stylePadding = (buffMetrics and buffMetrics.padding) or (debuffMetrics and debuffMetrics.padding) or Model.ReadNumber(unit, "stylePadding", 0, 0, 16),
        perRow = (buffMetrics and buffMetrics.perRow) or (debuffMetrics and debuffMetrics.perRow) or Model.ReadNumber(unit, "perRow", 12, 1, 40),
        buffPerRow = buffMetrics and buffMetrics.perRow or Model.ReadLanePerRow(unit, "buff"),
        debuffPerRow = debuffMetrics and debuffMetrics.perRow or Model.ReadLanePerRow(unit, "debuff"),
        buffSpacing = buffMetrics and buffMetrics.spacing or Model.ReadLaneSpacing(unit, "buff"),
        debuffSpacing = debuffMetrics and debuffMetrics.spacing or Model.ReadLaneSpacing(unit, "debuff"),
        maxBuffs = buffMetrics and buffMetrics.num or Model.ReadNumber(unit, "maxBuffs", 12, 0, 80),
        maxDebuffs = debuffMetrics and debuffMetrics.num or Model.ReadNumber(unit, "maxDebuffs", 12, 0, 80),
        growth = (buffMetrics and buffMetrics.growth) or (debuffMetrics and debuffMetrics.growth) or Model.ReadGrowth(unit),
        rowWrap = (buffMetrics and buffMetrics.rowWrap) or (debuffMetrics and debuffMetrics.rowWrap) or Model.ReadRowWrap(unit),
        buffGrowthX = buffMetrics and buffMetrics.growth or Model.ReadLaneGrowth(unit, "buff"),
        buffGrowthY = buffMetrics and buffMetrics.rowWrap or Model.ReadLaneRowWrap(unit, "buff"),
        debuffGrowthX = debuffMetrics and debuffMetrics.growth or Model.ReadLaneGrowth(unit, "debuff"),
        debuffGrowthY = debuffMetrics and debuffMetrics.rowWrap or Model.ReadLaneRowWrap(unit, "debuff"),
        showStackCount = Model.ReadBool(unit, "showStackCount", true),
        showCooldownText = Model.ReadBool(unit, "showCooldownText", true),
        buffShowStackCount = Model.ReadLaneStyleBool(unit, "buff", "showStackCount", true),
        buffShowCooldownText = Model.ReadLaneStyleBool(unit, "buff", "showCooldownText", true),
        buffShowCooldownSwipe = Model.ReadLaneStyleBool(unit, "buff", "showCooldownSwipe", true),
        buffCooldownSwipeReverse = Model.ReadLaneStyleBool(unit, "buff", "cooldownSwipeReverse", false),
        buffShowStealable = Model.ReadLaneStyleBool(unit, "buff", "showStealable", false),
        buffStealableStyle = Model.ReadLaneStyleString(unit, "buff", "stealableStyle", "BORDER_ICON"),
        debuffShowStackCount = Model.ReadLaneStyleBool(unit, "debuff", "showStackCount", true),
        debuffShowCooldownText = Model.ReadLaneStyleBool(unit, "debuff", "showCooldownText", true),
        debuffShowCooldownSwipe = Model.ReadLaneStyleBool(unit, "debuff", "showCooldownSwipe", true),
        debuffCooldownSwipeReverse = Model.ReadLaneStyleBool(unit, "debuff", "cooldownSwipeReverse", false),
        debuffTypeBorderMode = Model.ReadDebuffTypeBorderMode(unit),
        useDebuffTypeBorders = Model.ReadLaneStyleBool(unit, "debuff", "useDebuffTypeBorders", false),
        stackAnchor = (runtimeCfg and runtimeCfg.stackAnchor) or Model.ReadStackAnchor(unit),
        buffStackAnchor = Model.ReadLaneStackAnchor(unit, "buff"),
        debuffStackAnchor = Model.ReadLaneStackAnchor(unit, "debuff"),
        stackSize = Model.ReadNumber(unit, "stackTextSize", 14, 6, 40),
        stackX = Model.ReadNumber(unit, "stackTextOffsetX", -1, -2000, 2000),
        stackY = Model.ReadNumber(unit, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = Model.ReadNumber(unit, "cooldownTextSize", 14, 6, 40),
        cooldownAnchor = Model.ReadCooldownAnchor(unit),
        cooldownX = Model.ReadNumber(unit, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = Model.ReadNumber(unit, "cooldownTextOffsetY", 0, -2000, 2000),
        buffStackSize = Model.ReadLaneStyleNumber(unit, "buff", "stackTextSize", 14, 6, 40),
        buffStackX = Model.ReadLaneStyleNumber(unit, "buff", "stackTextOffsetX", -1, -2000, 2000),
        buffStackY = Model.ReadLaneStyleNumber(unit, "buff", "stackTextOffsetY", 1, -2000, 2000),
        buffCooldownSize = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextSize", 14, 6, 40),
        buffCooldownAnchor = Model.ReadLaneCooldownAnchor(unit, "buff"),
        buffCooldownX = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextOffsetX", 0, -2000, 2000),
        buffCooldownY = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextOffsetY", 0, -2000, 2000),
        buffCooldownDecimalSeconds = Model.ReadLaneStyleNumber(unit, "buff", "cooldownDecimalSeconds", 3, 0, 30),
        buffShowDurationBar = Model.ReadLaneStyleBool(unit, "buff", "showDurationBar", false),
        buffDurationBarHeight = Model.ReadLaneStyleNumber(unit, "buff", "durationBarHeight", 2, 1, 16),
        buffDurationBarDisplay = Model.ReadLaneDurationBarDisplay(unit, "buff"),
        buffDurationBarPosition = Model.ReadLaneDurationBarPosition(unit, "buff"),
        buffDurationBarDirection = Model.ReadLaneDurationBarDirection(unit, "buff"),
        debuffStackSize = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextSize", 14, 6, 40),
        debuffStackX = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetX", -1, -2000, 2000),
        debuffStackY = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetY", 1, -2000, 2000),
        debuffCooldownSize = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextSize", 14, 6, 40),
        debuffCooldownAnchor = Model.ReadLaneCooldownAnchor(unit, "debuff"),
        debuffCooldownX = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetX", 0, -2000, 2000),
        debuffCooldownY = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetY", 0, -2000, 2000),
        debuffCooldownDecimalSeconds = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownDecimalSeconds", 3, 0, 30),
        debuffShowDurationBar = Model.ReadLaneStyleBool(unit, "debuff", "showDurationBar", false),
        debuffDurationBarHeight = Model.ReadLaneStyleNumber(unit, "debuff", "durationBarHeight", 2, 1, 16),
        debuffDurationBarDisplay = Model.ReadLaneDurationBarDisplay(unit, "debuff"),
        debuffDurationBarPosition = Model.ReadLaneDurationBarPosition(unit, "debuff"),
        debuffDurationBarDirection = Model.ReadLaneDurationBarDirection(unit, "debuff"),
    }
end

function Model.Apply(unit, reason)
    Model.InvalidateDefaultSeedCache()
    reason = reason or "AURAS3_MENU"
    local function IsGroupApplyScope(scope)
        scope = tostring(scope or ""):lower()
        return scope == "group" or scope == "groups"
            or scope == "party" or scope == "raid" or scope == "mythicraid"
            or scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid"
    end
    local normalizedScope = unit and NormalizeScope(unit) or "shared"
    local globalScope = (not unit) or normalizedScope == "shared" or IsGroupApplyScope(unit)
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true then
        if type(A3._QueueDeferredAuraRuntime) == "function" then
            return A3._QueueDeferredAuraRuntime(unit or "shared", reason, false)
        end
        return false
    end
    if globalScope and A3.BumpRuntimeConfig then A3.BumpRuntimeConfig() end
    local function RefreshGroup(scope)
        if A3.RequestUnit then
            return A3.RequestUnit(scope)
        end
        local gf = MSUF and MSUF.GF
        if gf and type(gf.RefreshVisuals) == "function" then
            if scope == "party" or scope == "gf_party" then
                return gf.RefreshVisuals("party", gf.DIRTY_AURAS)
            elseif scope == "mythicraid" or scope == "gf_mythicraid" then
                return gf.RefreshVisuals("mythicraid", gf.DIRTY_AURAS)
            elseif scope == "raid" or scope == "gf_raid" then
                local didWork = gf.RefreshVisuals("raid", gf.DIRTY_AURAS)
                return gf.RefreshVisuals("mythicraid", gf.DIRTY_AURAS) or didWork
            end
            return gf.RefreshVisuals(nil, gf.DIRTY_AURAS)
        end
        return false
    end
    local function Refresh(runtimeUnit)
        -- RefreshUnit owns both the runtime lane and its Edit Mode follower.
        -- UpdateUnitAnchor is only the preview half of the same operation and
        -- calling both repaints every dummy twice.
        if type(A3.RefreshUnit) == "function" then
            A3.RefreshUnit(runtimeUnit)
        elseif type(A3.UpdateUnitAnchor) == "function" then
            A3.UpdateUnitAnchor(runtimeUnit)
        end
        return "OFF"
    end
    if unit and IsGroupApplyScope(unit) then
        RefreshGroup(unit)
    elseif unit and NormalizeScope(unit) ~= "shared" then
        EachRuntimeUnit(unit, Refresh)
    else
        Refresh("player")
        Refresh("target")
        Refresh("focus")
        for i = 1, #BOSS_UNITS do Refresh(BOSS_UNITS[i]) end
        RefreshGroup("group")
    end
    if type(A3._NotifyAuraColdpathPreview) == "function" then
        A3._NotifyAuraColdpathPreview(reason, unit or normalizedScope)
    elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason)
    end
end
