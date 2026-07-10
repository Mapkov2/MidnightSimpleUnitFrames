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

local type, tonumber, tostring, pairs, ipairs = type, tonumber, tostring, pairs, ipairs
local math_floor = math.floor
local table_sort = table.sort
local C_Spell = _G.C_Spell
local GetSpellInfo = _G.GetSpellInfo

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
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
}
local AURA_ANCHOR_OK = { TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true, CENTER=true }

local LANE_GROWTH_VALUES = {
    { value = "RIGHTDOWN", text = "Right then Down" },
    { value = "LEFTDOWN", text = "Left then Down" },
    { value = "RIGHTUP", text = "Right then Up" },
    { value = "LEFTUP", text = "Left then Up" },
    { value = "UP", text = "Up" },
    { value = "DOWN", text = "Down" },
}
local LANE_GROWTH_PARTS = {
    RIGHTDOWN = { "RIGHT", "DOWN" },
    LEFTDOWN = { "LEFT", "DOWN" },
    RIGHTUP = { "RIGHT", "UP" },
    LEFTUP = { "LEFT", "UP" },
    UP = { "UP", "DOWN" },
    DOWN = { "DOWN", "DOWN" },
}

local LAYOUT_KEYS = {
    iconSize = true,
    spacing = true,
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
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffCooldownDecimalSeconds = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffCooldownDecimalSeconds = true,
    debuffDurationBarHeight = true,
}

local STYLE_LAYOUT_KEYS = {
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffCooldownDecimalSeconds = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffCooldownDecimalSeconds = true,
    debuffDurationBarHeight = true,
}

local SHARED_LAYOUT_KEYS = {
    showTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    buffShowTooltip = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
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
}

local STYLE_SHARED_LAYOUT_KEYS = {
    showTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    buffShowTooltip = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
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
}

local GROUPS = {
    buff = {
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        perRowKey = "buffPerRow",
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
        perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
}

local LANE_STYLE_KEYS = {
    buff = {
        showCooldownSwipe = "buffShowCooldownSwipe",
        cooldownSwipeReverse = "buffCooldownSwipeReverse",
        showDurationBar = "buffShowDurationBar",
        durationBarHeight = "buffDurationBarHeight",
        durationBarDisplay = "buffDurationBarDisplay",
        durationBarPosition = "buffDurationBarPosition",
        durationBarDirection = "buffDurationBarDirection",
        showTooltip = "buffShowTooltip",
        showCooldownText = "buffShowCooldownText",
        showStackCount = "buffShowStackCount",
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
        showCooldownSwipe = "debuffShowCooldownSwipe",
        cooldownSwipeReverse = "debuffCooldownSwipeReverse",
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
    buffs = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "cancelable", "notCancelable", "externalDefensive", "bigDefensive", "exclusive" },
    debuffs = { "onlyMine", "raid", "raidInCombat", "includeNameplateOnly", "includeDispellable", "crowdControl", "exclusive" },
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
    buffShowDurationBar = false,
    buffDurationBarHeight = 2,
    buffDurationBarDisplay = "BAR_ONLY",
    buffDurationBarPosition = "BOTTOM",
    buffDurationBarDirection = "REMAINING",
    buffShowTooltip = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = false,
    debuffShowDurationBar = false,
    debuffDurationBarHeight = 2,
    debuffDurationBarDisplay = "BAR_ONLY",
    debuffDurationBarPosition = "BOTTOM",
    debuffDurationBarDirection = "REMAINING",
    debuffShowTooltip = true,
    debuffShowCooldownText = true,
    debuffShowStackCount = true,
    clickThroughAuras = false,
    iconSize = 26,
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
            onlyMine = false,
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
            onlyMine = false,
            includeDispellable = false,
            raid = false,
            raidInCombat = false,
            includeNameplateOnly = false,
            crowdControl = false,
            exclusive = "none",
        },
    },
}

local DEFAULT_GENERAL = {
    aurasCooldownTextUseBuckets = false,
    aurasCooldownTextSafeColor = { 1.00, 1.00, 1.00 },
    aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 },
    aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 },
    aurasStackCountColor = { 1.00, 1.00, 1.00 },
    aurasOwnBuffHighlightColor = { 1.00, 0.85, 0.20 },
    aurasOwnDebuffHighlightColor = { 1.00, 0.30, 0.30 },
    aurasCooldownTextSafeSeconds = 60,
    aurasCooldownTextWarningSeconds = 15,
    aurasCooldownTextUrgentSeconds = 5,
}

local FALLBACK_PUBLIC_AURA_SPELLS = {
    PRESERVATION_EVOKER = {
        [355941] = true, [363502] = true, [364343] = true, [366155] = true,
        [367364] = true, [373267] = true, [376788] = true,
    },
    AUGMENTATION_EVOKER = {
        [360827] = true, [395152] = true, [410089] = true, [410263] = true,
        [410686] = true, [413984] = true,
    },
    RESTO_DRUID = {
        [774] = true, [8936] = true, [33763] = true, [48438] = true, [155777] = true,
    },
    DISC_PRIEST = {
        [17] = true, [194384] = true, [1253593] = true,
    },
    HOLY_PRIEST = {
        [139] = true, [41635] = true, [77489] = true,
    },
    MISTWEAVER_MONK = {
        [115175] = true, [119611] = true, [124682] = true, [450769] = true,
    },
    RESTO_SHAMAN = {
        [974] = true, [383648] = true, [61295] = true,
    },
    HOLY_PALADIN = {
        [53563] = true, [156322] = true, [156910] = true, [1244893] = true,
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
    },
    DESERTER = {
        [26013] = true, [71041] = true,
    },
}

local FALLBACK_PUBLIC_AURA_META = {
    { key = "RAID_BUFFS", label = "Long-term Raid Buffs", category = "Raid", tooltip = "Long duration raid buffs Blizzard exposes as non-secret." },
    { key = "PRESERVATION_EVOKER", label = "Preservation Evoker", category = "Healer", tooltip = "Dream Breath, Echo, Reversion, Lifebind." },
    { key = "AUGMENTATION_EVOKER", label = "Augmentation Evoker", category = "Support", tooltip = "Blistering Scales, Ebon Might, Prescience, Shifting Sands." },
    { key = "RESTO_DRUID", label = "Restoration Druid", category = "Healer", tooltip = "Rejuvenation, Regrowth, Lifebloom, Wild Growth, Germination." },
    { key = "DISC_PRIEST", label = "Discipline Priest", category = "Healer", tooltip = "Power Word: Shield, Atonement, Void Shield." },
    { key = "HOLY_PRIEST", label = "Holy Priest", category = "Healer", tooltip = "Renew, Prayer of Mending, Echo of Light." },
    { key = "MISTWEAVER_MONK", label = "Mistweaver Monk", category = "Healer", tooltip = "Soothing Mist, Renewing Mist, Enveloping Mist, Aspect of Harmony." },
    { key = "RESTO_SHAMAN", label = "Restoration Shaman", category = "Healer", tooltip = "Earth Shield and Riptide." },
    { key = "HOLY_PALADIN", label = "Holy Paladin", category = "Healer", tooltip = "Beacon and Eternal Flame variants." },
    { key = "BLESSING_BRONZE", label = "Blessing of the Bronze", category = "Raid", tooltip = "All class-specific Blessing of the Bronze variants." },
    { key = "SELF_BUFFS", label = "Long-term Self Buffs", category = "Class", tooltip = "Rite of Sanctification and Rite of Adjuration." },
    { key = "ROGUE_POISONS", label = "Rogue Poisons", category = "Class", tooltip = "Deadly, Wound, Crippling, Numbing, Instant, Atrophic, Amplifying." },
    { key = "SHAMAN_IMBUE", label = "Shaman Imbuements", category = "Class", tooltip = "Windfury, Flametongue, Earthliving, Tidecaller's Guard, Thunderstrike Ward." },
    { key = "RESOURCE_AURAS", label = "Resource Auras", category = "Utility", tooltip = "Mage Icicles and Hunter Tip of the Spear." },
    { key = "COOLDOWNS", label = "Cooldowns", category = "Utility", tooltip = "Hearthstone and Shaman Reincarnation. Mythic+ teleports are not listed by Wowhead." },
    { key = "SATED", label = "Sated / Exhaustion", category = "Utility", tooltip = "Bloodlust/Heroism exhaustion lockout auras." },
    { key = "DESERTER", label = "Deserter", category = "Utility", tooltip = "Dungeon and battleground deserter lockout auras." },
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
    { value = "Player", text = "Player" },
    { value = "BigDefensivePlayer", text = "Big Defensive Player" },
    { value = "ExternalDefensivePlayer", text = "External Defensive Player" },
    { value = "RaidInCombatPlayer", text = "Raid In Combat Player" },
    { value = "CancelablePlayer", text = "Cancelable Player" },
    { value = "NotCancelablePlayer", text = "Not Cancelable Player" },
    { value = "RaidPlayer", text = "Raid Player" },
    { value = "BigDefensive", text = "Big Defensive" },
    { value = "ExternalDefensive", text = "External Defensive" },
    { value = "RaidInCombat", text = "Raid In Combat" },
    { value = "Cancelable", text = "Cancelable" },
    { value = "NotCancelable", text = "Not Cancelable" },
    { value = "Raid", text = "Raid" },
}
GF_AURA_FILTER.DEBUFF_FILTER_ITEMS = {
    { value = "ALL", text = "All Debuffs" },
    { value = "Player", text = "Player" },
    { value = "RaidPlayer", text = "Raid Player" },
    { value = "RaidInCombatPlayer", text = "Raid In Combat Player" },
    { value = "Raid", text = "Raid" },
    { value = "RaidInCombat", text = "Raid In Combat" },
    { value = "INCLUDE_NAME_PLATE_ONLY", text = "Include Nameplate-only" },
    { value = "RAID_PLAYER_DISPELLABLE", text = "Dispellable" },
    { value = "CROWD_CONTROL", text = "Crowd Control" },
}
local function GFNativeFilterKey(token)
    return tostring(token or "ALL"):upper():gsub("[^A-Z0-9]", "")
end
local GF_NATIVE_BUFF_FILTERS = {
    ALL = false,
    PLAYER = "PLAYER",
    BIGDEFENSIVEPLAYER = "BIG_DEFENSIVE|PLAYER",
    EXTERNALDEFENSIVEPLAYER = "EXTERNAL_DEFENSIVE|PLAYER",
    RAIDINCOMBATPLAYER = "RAID_IN_COMBAT|PLAYER",
    CANCELABLEPLAYER = "CANCELABLE|PLAYER",
    NOTCANCELABLEPLAYER = "!CANCELABLE|PLAYER",
    RAIDPLAYER = "RAID|PLAYER",
    BIGDEFENSIVE = "BIG_DEFENSIVE|!PLAYER",
    EXTERNALDEFENSIVE = "EXTERNAL_DEFENSIVE|!PLAYER",
    RAIDINCOMBAT = "RAID_IN_COMBAT|!PLAYER",
    CANCELABLE = "CANCELABLE|!PLAYER",
    NOTCANCELABLE = "!CANCELABLE|!PLAYER",
    RAID = "RAID|!PLAYER",
    INCLUDENAMEPLATEONLY = "INCLUDE_NAME_PLATE_ONLY",
}
local GF_NATIVE_DEBUFF_FILTERS = {
    ALL = false,
    PLAYER = "PLAYER",
    RAIDPLAYER = "RAID|PLAYER",
    RAIDINCOMBATPLAYER = "RAID_IN_COMBAT|PLAYER",
    RAID = "RAID|!PLAYER",
    RAIDINCOMBAT = "RAID_IN_COMBAT|!PLAYER",
    INCLUDENAMEPLATEONLY = "INCLUDE_NAME_PLATE_ONLY",
    RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    DISPELLABLE = "RAID_PLAYER_DISPELLABLE",
    CROWDCONTROL = "CROWD_CONTROL",
}
local function ResolveGFNativeFilter(token, baseFilter, filterMap)
    local filter = filterMap[GFNativeFilterKey(token)]
    if filter == false then return baseFilter end
    if type(filter) == "string" and filter ~= "" then return baseFilter .. "|" .. filter end
    return baseFilter
end
GF_AURA_FILTER.ResolveBuffFilter = function(token)
    return ResolveGFNativeFilter(token, "HELPFUL", GF_NATIVE_BUFF_FILTERS)
end
GF_AURA_FILTER.ResolveDebuffFilter = function(token)
    return ResolveGFNativeFilter(token, "HARMFUL", GF_NATIVE_DEBUFF_FILTERS)
end
GF_AURA_FILTER.EXTERNALS_TOKEN = "HELPFUL|EXTERNAL_DEFENSIVE|!PLAYER"
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
    Default(auras, "showFocus", true)
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
    DefaultsInto(shared, DEFAULT_SHARED)
    if shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
        shared.debuffTypeBorderMode = shared.useDebuffTypeBorders == true and "SYMBOL" or NormalizeDebuffTypeBorderMode(shared.debuffTypeBorderMode, "OFF")
        shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
    end
    NormalizeSparseVisualOverrides(auras, shared)
    return auras, shared
end

local function EnsureGeneralDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then db = {}; ExportPublic("MSUF_DB", db) end
    if type(db.general) ~= "table" then db.general = {} end
    DefaultsInto(db.general, DEFAULT_GENERAL)
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
    local layout = (pu and pu.overrideLayout == true and type(pu.layout) == "table") and pu.layout or nil
    local sharedLayout = (pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table") and pu.layoutShared or nil
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
        if not (styleKeys and styleKeys[key]) then ClearInheritedLayoutKey(layout, shared, key) end
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
    local layout, sharedLayout, pu = EffectiveLayoutTables(auras, unit)
    local styleActive = UnitStyleOverrideActive(pu)
    if LAYOUT_KEYS[key] then
        if layout and layout[key] ~= nil and (not STYLE_LAYOUT_KEYS[key] or styleActive) then return layout[key] end
    elseif SHARED_LAYOUT_KEYS[key] then
        if sharedLayout and sharedLayout[key] ~= nil and (not STYLE_SHARED_LAYOUT_KEYS[key] or styleActive) then return sharedLayout[key] end
    end
    return shared and shared[key]
end

local function WriteUnitLayoutValue(auras, shared, unit, key, value)
    EachRuntimeUnit(unit, function(runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
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
    local auras = Model.EnsureDB()
    local pu = PerUnit(auras, unit, false)
    return not UnitStyleOverrideActive(pu)
end

local function EnsureUnitStyleOverrides(auras, runtimeUnit)
    local pu = PerUnit(auras, runtimeUnit, true)
    if not pu then return end
    pu.layout = type(pu.layout) == "table" and pu.layout or {}
    pu.layoutShared = type(pu.layoutShared) == "table" and pu.layoutShared or {}
    pu.overrideStyle = true
end

function Model.SetUseSharedVisuals(unit, useShared)
    local auras, shared = Model.EnsureDB()
    if type(auras) ~= "table" then return end
    EachRuntimeUnit(unit, function(runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
        if useShared then
            pu.overrideStyle = false
            ClearKeys(pu.layout, STYLE_LAYOUT_KEYS)
            ClearKeys(pu.layoutShared, STYLE_SHARED_LAYOUT_KEYS)
            RefreshLayoutOverrideFlags(pu)
        else
            EnsureUnitStyleOverrides(auras, runtimeUnit)
        end
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
    else
        shared[key] = value
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
    local fallback = Model.ReadNumber(unit, "perRow", 12, 1, 40)
    return Model.ReadNumber(unit, spec and spec.perRowKey or "perRow", fallback, 1, 40)
end

function Model.WriteLanePerRow(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    Model.WriteNumber(unit, spec and spec.perRowKey or "perRow", value, 1, 40)
end

function Model.ReadLaneGrowth(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local fallback = Model.ReadGrowth(unit)
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
    local fallback = Model.ReadRowWrap(unit)
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
            size = 24, barWidth = 54, showCooldown = true,
            showCooldownSwipe = true, showStacks = true,
        },
        frame = { type = "none", color = { 0.69, 0.50, 0.88, 0.80 }, priority = 5, thickness = 2, strata = "AUTO" },
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

local CUSTOM_CONTAINER_MAX = 3

local function NewCustomContainer(index)
    return {
        enabled = false,
        name = "Custom " .. tostring(index),
        auraType = "BUFF",
        spellIDs = "",
        filters = {
            enabled = true,
            onlyMine = false,
            raid = false,
            raidInCombat = false,
            includeNameplateOnly = false,
            cancelable = false,
            notCancelable = false,
            includeDispellable = false,
            crowdControl = false,
            externalDefensive = false,
            bigDefensive = false,
            exclusive = "none",
        },
        placed = {
            type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN",
            x = 0, y = 0, size = 24, barWidth = 54,
            max = 8, perRow = 4, spacing = 2,
            showCooldown = true, showCooldownSwipe = true, showStacks = true,
        },
        layer = 9,
        strata = "AUTO",
        frame = {
            type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
            priority = 5, thickness = 2, strata = "AUTO",
        },
    }
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
    local root = Model.EnsureDB().customContainers
    local record = root.perUnit[unit]
    if type(record) ~= "table" and create then
        record = { items = {} }
        root.perUnit[unit] = record
    end
    if type(record) ~= "table" then return nil end
    if type(record.items) ~= "table" then record.items = {} end
    if record._msufA3CustomContainersMigrated_v1 ~= true then
        local oldRoot = Model.EnsureDB().customDisplays
        local oldRecord = oldRoot and oldRoot.perUnit and oldRoot.perUnit[unit]
        local oldItems = oldRecord and oldRecord.override == true and oldRecord.items
            or (oldRoot and oldRoot.shared and oldRoot.shared.items)
        if type(oldItems) == "table" then
            for i = 1, math.min(CUSTOM_CONTAINER_MAX, #oldItems) do
                if type(record.items[i]) ~= "table" then
                    record.items[i] = UpgradeLegacyCustomContainer(NewCustomContainer(i), oldItems[i], i)
                end
            end
        end
        record._msufA3CustomContainersMigrated_v1 = true
    end
    return record
end

function Model.CustomContainerMax()
    return CUSTOM_CONTAINER_MAX
end

function Model.CustomContainer(unit, index, create)
    index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
    local record = EnsureUnitCustomContainers(unit, create == true)
    if not record then return nil end
    local item = record.items[index]
    if type(item) ~= "table" and create == true then
        item = NewCustomContainer(index)
        record.items[index] = item
    end
    return item
end

function Model.CustomContainers(unit, create)
    local record = EnsureUnitCustomContainers(unit, create == true)
    return record and record.items or {}
end

function Model.ResetCustomContainer(unit, index)
    local record = EnsureUnitCustomContainers(unit, true)
    index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
    record.items[index] = NewCustomContainer(index)
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

function Model.AddCustomContainerSpell(unit, index, value)
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false end
    local set = CustomContainerSpellSet(item)
    if set[spellID] ~= true then
        local count = 0
        for _, enabled in pairs(set) do if enabled == true then count = count + 1 end end
        if count >= 40 then return false end
    end
    set[spellID] = true
    WriteCustomContainerSpellSet(item, set)
    return true
end

function Model.RemoveCustomContainerSpell(unit, index, value)
    local spellID = SpellIDFromInput(value)
    local item = Model.CustomContainer(unit, index, true)
    if not (spellID and item) then return false end
    local set = CustomContainerSpellSet(item)
    set[spellID] = nil
    WriteCustomContainerSpellSet(item, set)
    return true
end

function Model.CustomContainerSpellEntries(unit, index)
    local item = Model.CustomContainer(unit, index, false)
    local out = {}
    for spellID in pairs(CustomContainerSpellSet(item)) do
        local id, name, icon = SpellInfo(spellID)
        id = id or spellID
        out[#out + 1] = {
            value = tostring(id), spellID = id, icon = icon,
            text = (type(name) == "string" and name ~= "" and name or "Spell") .. " (#" .. tostring(id) .. ")",
        }
    end
    table_sort(out, function(a, b) return tostring(a.text) < tostring(b.text) end)
    return out
end

function Model.WriteLaneLayer(unit, kind, value)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    Model.WriteNumber(unit, spec and spec.layerKey or "buffLayer", value, 0, 30)
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

function Model.ReadLaneStyleBool(unit, kind, key, defaultValue)
    local laneKey = LaneStyleKey(kind, key)
    local value = Model.ReadValue(unit, laneKey, nil)
    if value == nil and laneKey ~= key then value = Model.ReadValue(unit, key, defaultValue and true or false) end
    if value == nil then return defaultValue and true or false end
    return value == true
end

function Model.WriteLaneStyleBool(unit, kind, key, value)
    Model.WriteValue(unit, LaneStyleKey(kind, key), value and true or false)
end

function Model.ReadDebuffTypeBorderMode(unit)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return "OFF" end
    if NormalizeScope(unit) ~= "shared" then
        local _, sharedLayout, pu = EffectiveLayoutTables(auras, unit)
        if UnitStyleOverrideActive(pu) and type(sharedLayout) == "table" then
            if sharedLayout.debuffTypeBorderMode ~= nil then
                local mode = NormalizeDebuffTypeBorderMode(sharedLayout.debuffTypeBorderMode, "OFF")
                return (mode == "OFF" and sharedLayout.useDebuffTypeBorders == true) and "SYMBOL" or mode
            end
            if sharedLayout.useDebuffTypeBorders ~= nil then
                return sharedLayout.useDebuffTypeBorders == true and "SYMBOL" or "OFF"
            end
        end
    end
    if shared.debuffTypeBorderMode ~= nil then
        local mode = NormalizeDebuffTypeBorderMode(shared.debuffTypeBorderMode, "OFF")
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
    local laneKey = LaneStyleKey(kind, key)
    local value = Model.ReadValue(unit, laneKey, nil)
    if value == nil and laneKey ~= key then value = Model.ReadValue(unit, key, defaultValue) end
    return ClampNumber(value, defaultValue, minValue, maxValue)
end

function Model.WriteLaneStyleNumber(unit, kind, key, value, minValue, maxValue)
    value = ClampNumber(value, 0, minValue, maxValue)
    if math_floor(value) == value then value = Round(value) end
    Model.WriteValue(unit, LaneStyleKey(kind, key), value)
end

function Model.ReadLaneStackAnchor(unit, kind)
    local laneKey = LaneStyleKey(kind, "stackCountAnchor")
    local value = tostring(Model.ReadValue(unit, laneKey, nil) or Model.ReadValue(unit, "stackCountAnchor", "TOPRIGHT") or "TOPRIGHT")
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
    local laneKey = LaneStyleKey(kind, "cooldownTextAnchor")
    local value = tostring(Model.ReadValue(unit, laneKey, nil) or "")
    if AURA_ANCHOR_OK[value] then return value end
    value = tostring(Model.ReadValue(unit, "cooldownTextAnchor", "CENTER") or "CENTER")
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
    local laneKey = LaneStyleKey(kind, "durationBarPosition")
    local value = Model.ReadValue(unit, laneKey, nil)
    if value == nil and laneKey ~= "durationBarPosition" then value = Model.ReadValue(unit, "durationBarPosition", "BOTTOM") end
    return NormalizeDurationBarPosition(value, "BOTTOM")
end

function Model.WriteLaneDurationBarPosition(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarPosition"), NormalizeDurationBarPosition(value, "BOTTOM"))
end

function Model.ReadLaneDurationBarDirection(unit, kind)
    local laneKey = LaneStyleKey(kind, "durationBarDirection")
    local value = Model.ReadValue(unit, laneKey, nil)
    if value == nil and laneKey ~= "durationBarDirection" then value = Model.ReadValue(unit, "durationBarDirection", "REMAINING") end
    return NormalizeDurationBarDirection(value, "REMAINING")
end

function Model.WriteLaneDurationBarDirection(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDirection"), NormalizeDurationBarDirection(value, "REMAINING"))
end

function Model.ReadLaneDurationBarDisplay(unit, kind)
    local laneKey = LaneStyleKey(kind, "durationBarDisplay")
    local value = Model.ReadValue(unit, laneKey, nil)
    if value == nil and laneKey ~= "durationBarDisplay" then value = Model.ReadValue(unit, "durationBarDisplay", "BAR_ONLY") end
    return NormalizeDurationBarDisplay(value, "BAR_ONLY")
end

function Model.WriteLaneDurationBarDisplay(unit, kind, value)
    Model.WriteValue(unit, LaneStyleKey(kind, "durationBarDisplay"), NormalizeDurationBarDisplay(value, "BAR_ONLY"))
end

function Model.GroupShown(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    local _, shared = Model.EnsureDB()
    if not spec or type(shared) ~= "table" or shared[spec.showKey] == false then return false end
    return Model.ReadNumber(unit, spec.maxKey, 12, 0, 80) > 0
end

function Model.SetGroupShown(unit, kind, shown)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if not spec then return end
    local _, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return end
    if shown then
        shared[spec.showKey] = true
        if Model.ReadNumber(unit, spec.maxKey, 0, 0, 80) <= 0 then
            Model.WriteNumber(unit, spec.maxKey, kind == "buff" and 8 or 12, 0, 80)
        end
    else
        Model.WriteNumber(unit, spec.maxKey, 0, 0, 80)
    end
end

--- Filter scopes are independent from visual layout scopes. A unit can share
--- its icon positions while overriding aura rules, so reads/writes go through
--- EnsureScopeFilters rather than the layout helpers above.
local function EnsureScopeFilters(scope, create)
    local auras, shared = Model.EnsureDB()
    scope = NormalizeScope(scope)
    if scope == "shared" then
        DefaultsInto(shared.filters, DEFAULT_SHARED.filters)
        return shared.filters
    end

    local unit = RuntimeUnit(scope)
    local pu = PerUnit(auras, unit, create)
    if not pu then return shared.filters end
    if create then
        pu.overrideFilters = true
        if type(pu.filters) ~= "table" then pu.filters = DeepCopy(shared.filters or DEFAULT_SHARED.filters) end
        DefaultsInto(pu.filters, DEFAULT_SHARED.filters)
        return pu.filters
    end
    if pu.overrideFilters == true and type(pu.filters) == "table" then
        DefaultsInto(pu.filters, DEFAULT_SHARED.filters)
        return pu.filters
    end
    return shared.filters
end

function Model.UseSharedRules(scope)
    scope = NormalizeScope(scope)
    if scope == "shared" then return true end
    local auras = Model.EnsureDB()
    local pu = PerUnit(auras, scope, false)
    return not (pu and pu.overrideFilters == true)
end

function Model.SetUseSharedRules(scope, useShared)
    scope = NormalizeScope(scope)
    if scope == "shared" then return end
    EachRuntimeUnit(scope, function(runtimeUnit)
        local pu = PerUnit(Model.EnsureDB(), runtimeUnit, true)
        if not pu then return end
        if useShared then
            pu.overrideFilters = false
        else
            local f = EnsureScopeFilters(runtimeUnit, true)
            pu.filters = f
            pu.overrideFilters = true
        end
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
    local filters = EnsureScopeFilters(scope, true)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
    if key == "exclusive" and value == "important" then value = "none" end
    filters[tableKey][key] = value
end

function Model.ScopeFiltersEnabled(scope)
    local filters = EnsureScopeFilters(scope, false)
    return type(filters) ~= "table" or filters.enabled ~= false
end

function Model.SetScopeFiltersEnabled(scope, enabled)
    local _, shared = Model.EnsureDB()
    local filters = EnsureScopeFilters(scope, true)
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
            if NormalizeScope(scope) == "shared" and type(shared) == "table" then
                if snap.onlyMyBuffs ~= nil then shared.onlyMyBuffs = snap.onlyMyBuffs end
                if snap.onlyMyDebuffs ~= nil then shared.onlyMyDebuffs = snap.onlyMyDebuffs end
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
        if NormalizeScope(scope) == "shared" and type(shared) == "table" then
            snap.onlyMyBuffs = shared.onlyMyBuffs
            snap.onlyMyDebuffs = shared.onlyMyDebuffs
        end
        filters.disabledSnapshot = snap
    end

    if type(filters.buffs) == "table" then
        filters.buffs.onlyMine = false
        filters.buffs.raid = false
        filters.buffs.raidInCombat = false
        filters.buffs.includeNameplateOnly = false
        filters.buffs.cancelable = false
        filters.buffs.notCancelable = false
        filters.buffs.externalDefensive = false
        filters.buffs.bigDefensive = false
        filters.buffs.exclusive = "none"
    end
    if type(filters.debuffs) == "table" then
        filters.debuffs.onlyMine = false
        filters.debuffs.raid = false
        filters.debuffs.raidInCombat = false
        filters.debuffs.includeNameplateOnly = false
        filters.debuffs.includeDispellable = false
        filters.debuffs.crowdControl = false
        filters.debuffs.exclusive = "none"
    end
    if NormalizeScope(scope) == "shared" and type(shared) == "table" then
        shared.onlyMyBuffs = false
        shared.onlyMyDebuffs = false
    end
    filters.enabled = false
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

function Model.RemoveBlacklistSpell(scope, value, kind)
    local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID = SpellIDFromInput(raw)
    ForEachFrameBlacklist(scope, true, kind, function(list)
        if type(list) == "table" and type(list.spells) == "table" then
            if spellID then list.spells[tostring(spellID)] = nil end
            if raw ~= "" then list.spells[raw] = nil end
        end
    end)
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

function Model.BlacklistPresetValues()
    local meta = PublicAuraPresetMeta()
    local buckets = {}
    local values = {}
    for i = 1, #meta do
        local item = meta[i]
        if item and item.key then
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

function Model.AddBlacklistPresetSpell(scope, spellID, kind)
    return Model.AddBlacklistSpell(scope, spellID, kind)
end

function Model.AddBlacklistPresetGroup(scope, presetKey, kind)
    local values = Model.BlacklistSpellValues(presetKey)
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
    return true
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
    return true
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

function Model.AddGroupBlacklistPresetGroup(scope, groupKey, presetKey)
    local values = Model.BlacklistSpellValues(presetKey)
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
    local buffMetrics = runtimeCfg and type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(runtimeCfg, "buff") or nil
    local debuffMetrics = runtimeCfg and type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics(runtimeCfg, "debuff") or nil
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
        buffX = buffMetrics and buffMetrics.x or Model.ReadNumber(unit, "buffGroupOffsetX", 0, -4096, 4096),
        buffY = buffMetrics and buffMetrics.y or Model.ReadNumber(unit, "buffGroupOffsetY", 36, -4096, 4096),
        debuffX = debuffMetrics and debuffMetrics.x or Model.ReadNumber(unit, "debuffGroupOffsetX", 0, -4096, 4096),
        debuffY = debuffMetrics and debuffMetrics.y or Model.ReadNumber(unit, "debuffGroupOffsetY", 6, -4096, 4096),
        buffAnchor = Model.ReadLaneAnchor(unit, "buff"),
        debuffAnchor = Model.ReadLaneAnchor(unit, "debuff"),
        buffLayer = Model.ReadLaneLayer(unit, "buff"),
        debuffLayer = Model.ReadLaneLayer(unit, "debuff"),
        buffSize = buffMetrics and buffMetrics.size or Model.ReadNumber(unit, "buffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        debuffSize = debuffMetrics and debuffMetrics.size or Model.ReadNumber(unit, "debuffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        spacing = runtimeCfg and runtimeCfg.spacing or Model.ReadNumber(unit, "spacing", 2, 0, 64),
        perRow = runtimeCfg and runtimeCfg.perRow or Model.ReadNumber(unit, "perRow", 12, 1, 40),
        buffPerRow = runtimeCfg and runtimeCfg.buffPerRow or Model.ReadLanePerRow(unit, "buff"),
        debuffPerRow = runtimeCfg and runtimeCfg.debuffPerRow or Model.ReadLanePerRow(unit, "debuff"),
        maxBuffs = runtimeCfg and runtimeCfg.maxBuffs or Model.ReadNumber(unit, "maxBuffs", 12, 0, 80),
        maxDebuffs = runtimeCfg and runtimeCfg.maxDebuffs or Model.ReadNumber(unit, "maxDebuffs", 12, 0, 80),
        growth = runtimeCfg and runtimeCfg.growth or Model.ReadGrowth(unit),
        rowWrap = runtimeCfg and runtimeCfg.rowWrap or Model.ReadRowWrap(unit),
        buffGrowthX = runtimeCfg and runtimeCfg.buffGrowthX or Model.ReadLaneGrowth(unit, "buff"),
        buffGrowthY = runtimeCfg and runtimeCfg.buffGrowthY or Model.ReadLaneRowWrap(unit, "buff"),
        debuffGrowthX = runtimeCfg and runtimeCfg.debuffGrowthX or Model.ReadLaneGrowth(unit, "debuff"),
        debuffGrowthY = runtimeCfg and runtimeCfg.debuffGrowthY or Model.ReadLaneRowWrap(unit, "debuff"),
        showStackCount = Model.ReadBool(unit, "showStackCount", true),
        showCooldownText = Model.ReadBool(unit, "showCooldownText", true),
        buffShowStackCount = Model.ReadLaneStyleBool(unit, "buff", "showStackCount", true),
        buffShowCooldownText = Model.ReadLaneStyleBool(unit, "buff", "showCooldownText", true),
        buffShowCooldownSwipe = Model.ReadLaneStyleBool(unit, "buff", "showCooldownSwipe", true),
        buffCooldownSwipeReverse = Model.ReadLaneStyleBool(unit, "buff", "cooldownSwipeReverse", false),
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
        debuffStackSize = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextSize", 14, 6, 40),
        debuffStackX = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetX", -1, -2000, 2000),
        debuffStackY = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetY", 1, -2000, 2000),
        debuffCooldownSize = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextSize", 14, 6, 40),
        debuffCooldownAnchor = Model.ReadLaneCooldownAnchor(unit, "debuff"),
        debuffCooldownX = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetX", 0, -2000, 2000),
        debuffCooldownY = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetY", 0, -2000, 2000),
        debuffCooldownDecimalSeconds = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownDecimalSeconds", 3, 0, 30),
    }
end

function Model.Apply(unit, reason)
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
        if type(A3.UpdateUnitAnchor) == "function" then A3.UpdateUnitAnchor(runtimeUnit) end
        if type(A3.RefreshUnit) == "function" then A3.RefreshUnit(runtimeUnit) end
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
