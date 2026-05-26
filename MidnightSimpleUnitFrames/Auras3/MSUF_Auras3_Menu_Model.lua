--- Auras3/MSUF_Auras3_Menu_Model.lua
--- Cold-path DB adapter for Auras3 menu surfaces.
---
--- The model writes profile values and invalidates prepared runtime config.
--- It intentionally does not hook UNIT_AURA and does not install render logic.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

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
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
}

local SHARED_LAYOUT_KEYS = {
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
}

local GROUPS = {
    buff = {
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        perRowKey = "buffPerRow",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
    },
    debuff = {
        showKey = "showDebuffs",
        maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
    },
}

local RUNTIME_FILTER_KEYS = {
    buffs = { "onlyMine", "onlyImportant", "includeStealable", "exclusive" },
    debuffs = { "onlyMine", "onlyImportant", "exclusive" },
}

local DEFAULT_SHARED = {
    showBuffs = true,
    showDebuffs = true,
    showTooltip = true,
    showCooldownSwipe = true,
    showCooldownText = true,
    showStackCount = true,
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
    stackCountAnchor = "TOPRIGHT",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    privateAurasEnabled = true,
    showPrivateAurasPlayer = true,
    privateAuraMaxPlayer = 4,
    privateGrowth = "RIGHT",
    privateAuraBorderScale = 3,
    filters = {
        enabled = true,
        buffs = {
            onlyMine = false,
            onlyImportant = false,
            includeStealable = false,
            raid = false,
            cancelable = false,
            notCancelable = false,
            exclusive = "none",
        },
        debuffs = {
            onlyMine = false,
            onlyImportant = false,
            includeDispellable = false,
            raid = false,
            boss = false,
            dispellable = false,
            notDispellable = false,
            exclusive = "none",
        },
    },
    blacklist = {
        spells = {},
    },
}

local DEFAULT_GENERAL = {
    aurasCooldownTextUseBuckets = true,
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

function Model.EnsureDB()
    local auras, shared
    if A3.EnsureDB then
        auras, shared = A3.EnsureDB()
    else
        local db = _G.MSUF_DB
        if type(db) ~= "table" then db = {}; _G.MSUF_DB = db end
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
    DefaultsInto(shared, DEFAULT_SHARED)
    return auras, shared
end

local function EnsureGeneralDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then db = {}; _G.MSUF_DB = db end
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

local function EffectiveLayoutTables(auras, unit)
    local pu = PerUnit(auras, unit, false)
    local layout = (pu and pu.overrideLayout == true and type(pu.layout) == "table") and pu.layout or nil
    local sharedLayout = (pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table") and pu.layoutShared or nil
    return layout, sharedLayout, pu
end

local function ReadKeyRaw(auras, shared, unit, key)
    local layout, sharedLayout = EffectiveLayoutTables(auras, unit)
    if LAYOUT_KEYS[key] then
        if layout and layout[key] ~= nil then return layout[key] end
    elseif SHARED_LAYOUT_KEYS[key] then
        if sharedLayout and sharedLayout[key] ~= nil then return sharedLayout[key] end
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
        else
            if type(pu.layout) ~= "table" then pu.layout = {} end
            pu.overrideLayout = true
            pu.layout[key] = value
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

function Model.StackAnchorValues()
    return STACK_ANCHORS
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
    return not (pu and (pu.overrideLayout == true or pu.overrideSharedLayout == true))
end

local function SeedUnitVisuals(auras, shared, runtimeUnit)
    local pu = PerUnit(auras, runtimeUnit, true)
    if not pu then return end
    local layout, sharedLayout = EffectiveLayoutTables(auras, runtimeUnit)
    local seededLayout = {}
    local seededShared = {}
    for key in pairs(LAYOUT_KEYS) do
        seededLayout[key] = (layout and layout[key] ~= nil and layout[key]) or (shared and shared[key])
    end
    for key in pairs(SHARED_LAYOUT_KEYS) do
        seededShared[key] = (sharedLayout and sharedLayout[key] ~= nil and sharedLayout[key]) or (shared and shared[key])
    end
    pu.layout = seededLayout
    pu.layoutShared = seededShared
    pu.overrideLayout = true
    pu.overrideSharedLayout = true
end

function Model.SetUseSharedVisuals(unit, useShared)
    local auras, shared = Model.EnsureDB()
    if type(auras) ~= "table" then return end
    EachRuntimeUnit(unit, function(runtimeUnit)
        local pu = PerUnit(auras, runtimeUnit, true)
        if not pu then return end
        if useShared then
            pu.overrideLayout = false
            pu.overrideSharedLayout = false
        else
            SeedUnitVisuals(auras, shared, runtimeUnit)
        end
    end)
end

function Model.ReadValue(unit, key, defaultValue)
    local auras, shared = Model.EnsureDB()
    if type(shared) ~= "table" then return defaultValue end
    if NormalizeScope(unit) == "shared" then
        return shared[key] ~= nil and shared[key] or defaultValue
    end
    local value = ReadKeyRaw(auras, shared, unit, key)
    return value ~= nil and value or defaultValue
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

function Model.ReadStackAnchor(unit)
    local v = tostring(Model.ReadValue(unit, "stackCountAnchor", "TOPRIGHT") or "TOPRIGHT")
    return STACK_ANCHOR_OK[v] and v or "TOPRIGHT"
end

function Model.WriteStackAnchor(unit, value)
    value = STACK_ANCHOR_OK[value] and value or "TOPRIGHT"
    Model.WriteValue(unit, "stackCountAnchor", value)
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
    return value ~= nil and value or defaultValue
end

function Model.WriteFilter(scope, kind, key, value)
    local filters = EnsureScopeFilters(scope, true)
    kind = NormalizeKind(kind)
    local tableKey = kind == "buff" and "buffs" or "debuffs"
    if type(filters[tableKey]) ~= "table" then filters[tableKey] = {} end
    filters[tableKey][key] = value
    if key == "exclusive" then
        filters[tableKey].onlyImportant = value == "important"
    elseif key == "onlyImportant" and value == true then
        filters[tableKey].exclusive = "important"
    elseif key == "onlyImportant" and value ~= true and filters[tableKey].exclusive == "important" then
        filters[tableKey].exclusive = "none"
    end
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
        filters.buffs.onlyImportant = false
        filters.buffs.includeStealable = false
        filters.buffs.exclusive = "none"
    end
    if type(filters.debuffs) == "table" then
        filters.debuffs.onlyMine = false
        filters.debuffs.onlyImportant = false
        filters.debuffs.exclusive = "none"
    end
    if NormalizeScope(scope) == "shared" and type(shared) == "table" then
        shared.onlyMyBuffs = false
        shared.onlyMyDebuffs = false
    end
    filters.enabled = false
end

local function EnsureBlacklist(scope, create)
    local auras, shared = Model.EnsureDB()
    scope = NormalizeScope(scope)
    if scope == "shared" then
        if type(shared.blacklist) ~= "table" then shared.blacklist = { spells = {} } end
        if type(shared.blacklist.spells) ~= "table" then shared.blacklist.spells = {} end
        return shared.blacklist
    end
    local pu = PerUnit(auras, scope, create)
    if not pu then return shared.blacklist end
    if create then
        pu.overrideBlacklist = true
        if type(pu.blacklist) ~= "table" then pu.blacklist = { spells = {} } end
        if type(pu.blacklist.spells) ~= "table" then pu.blacklist.spells = {} end
        return pu.blacklist
    end
    if pu.overrideBlacklist == true and type(pu.blacklist) == "table" then
        if type(pu.blacklist.spells) ~= "table" then pu.blacklist.spells = {} end
        return pu.blacklist
    end
    return shared.blacklist
end

function Model.UseSharedBlacklist(scope)
    scope = NormalizeScope(scope)
    if scope == "shared" then return true end
    local auras = Model.EnsureDB()
    local pu = PerUnit(auras, scope, false)
    return not (pu and pu.overrideBlacklist == true)
end

function Model.SetUseSharedBlacklist(scope, useShared)
    scope = NormalizeScope(scope)
    if scope == "shared" then return end
    EachRuntimeUnit(scope, function(runtimeUnit)
        local pu = PerUnit(Model.EnsureDB(), runtimeUnit, true)
        if not pu then return end
        if useShared then
            pu.overrideBlacklist = false
        else
            EnsureBlacklist(runtimeUnit, true)
            pu.overrideBlacklist = true
        end
    end)
end

function Model.AddBlacklistSpell(scope, value)
    local spellID = SpellIDFromInput(value)
    if not spellID then return false end
    value = tostring(spellID)
    local list = EnsureBlacklist(scope, true)
    if type(list) ~= "table" then return false end
    list.spells[value] = true
    return true
end

function Model.RemoveBlacklistSpell(scope, value)
    local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local spellID = SpellIDFromInput(raw)
    local list = EnsureBlacklist(scope, true)
    if type(list) == "table" and type(list.spells) == "table" then
        if spellID then list.spells[tostring(spellID)] = nil end
        if raw ~= "" then list.spells[raw] = nil end
    end
end

function Model.BlacklistSummary(scope)
    local list = EnsureBlacklist(scope, false)
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

function Model.BlacklistEntries(scope)
    local list = EnsureBlacklist(scope, false)
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

function Model.BlacklistPreparedCount(scope)
    local list = EnsureBlacklist(scope, false)
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

function Model.AddBlacklistPresetSpell(scope, spellID)
    return Model.AddBlacklistSpell(scope, spellID)
end

function Model.AddBlacklistPresetGroup(scope, presetKey)
    local values = Model.BlacklistSpellValues(presetKey)
    local count = 0
    for i = 1, #values do
        local item = values[i]
        if item and item.value and Model.AddBlacklistSpell(scope, item.value) then
            count = count + 1
        end
    end
    return count
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
        showStackCount = shared.showStackCount ~= false,
        showCooldownText = shared.showCooldownText ~= false,
        stackAnchor = (runtimeCfg and runtimeCfg.stackAnchor) or Model.ReadStackAnchor(unit),
        stackSize = Model.ReadNumber(unit, "stackTextSize", 14, 6, 40),
        stackX = Model.ReadNumber(unit, "stackTextOffsetX", -1, -2000, 2000),
        stackY = Model.ReadNumber(unit, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = Model.ReadNumber(unit, "cooldownTextSize", 14, 6, 40),
        cooldownX = Model.ReadNumber(unit, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = Model.ReadNumber(unit, "cooldownTextOffsetY", 0, -2000, 2000),
    }
end

function Model.Apply(unit, reason)
    if A3.BumpRuntimeConfig then A3.BumpRuntimeConfig() end
    reason = reason or "AURAS3_MENU"
    local function Refresh(runtimeUnit)
        if type(_G.MSUF_Auras3_UpdateUnitAnchor) == "function" then _G.MSUF_Auras3_UpdateUnitAnchor(runtimeUnit) end
        if type(_G.MSUF_Auras3_RefreshUnit) == "function" then _G.MSUF_Auras3_RefreshUnit(runtimeUnit) end
        if type(_G.MSUF_Auras3_RefreshEditPreview) == "function" then _G.MSUF_Auras3_RefreshEditPreview(runtimeUnit) end
    end
    if unit and NormalizeScope(unit) ~= "shared" then
        EachRuntimeUnit(unit, Refresh)
    else
        Refresh("player")
        Refresh("target")
        Refresh("focus")
        for i = 1, #BOSS_UNITS do Refresh(BOSS_UNITS[i]) end
    end
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh(reason) end
end

_G.MSUF_Auras3_MenuModel = Model
