-- Menu schema: saved-key ownership, dropdown domains, and legacy defaults.
-- This factory runs once when the menu adapter loads. Routing tables are derived
-- from the runtime lane schema, so controls and compiled config agree on scope.
-- Do not mutate these tables during reads or seed new canonical profile aliases.
local _, MSUF = ...
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

-- The filter keys buffs and debuffs share; each side adds its own on top.
local function NewFilterSection()
    return {
        enabled = true,
        onlyMine = false,
        onlyImportant = false,
        includeDispellable = false,
        dispellableAny = false,
        raid = false,
        raidInCombat = false,
        includeNameplateOnly = false,
        exclusive = "none",
    }
end

-- Build fresh dropdown domains for each menu schema instance.
local function UnitDropdownChoices(shared)
    local choices = {
            { value = "player", text = "Player" },
            { value = "pet", text = "Pet" },
            { value = "target", text = "Target" },
            { value = "focus", text = "Focus" },
            { value = "boss", text = "Boss" },
            { value = "arena", text = "Arena" },
    }
    if shared then table.insert(choices, 1, { value = "shared", text = "Shared" }) end
    return choices
end

local function BuildDropdownDomains()
    return {
        PUBLIC_UNITS = UnitDropdownChoices(false),

        STYLE_SCOPES = UnitDropdownChoices(true),

        GROWTH_VALUES = {
            { value = "RIGHT", text = "Right" },
            { value = "LEFT", text = "Left" },
            { value = "UP", text = "Up" },
            { value = "DOWN", text = "Down" },
        },
        GROWTH_OK = { RIGHT=true, LEFT=true, UP=true, DOWN=true },

        ROW_WRAP_OK = { DOWN=true, UP=true },

        STACK_ANCHORS = {
            { value = "TOPRIGHT", text = "Top Right" },
            { value = "TOPLEFT", text = "Top Left" },
            { value = "BOTTOMRIGHT", text = "Bottom Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" },
        },
        STACK_ANCHOR_OK = { TOPRIGHT=true, TOPLEFT=true, BOTTOMRIGHT=true, BOTTOMLEFT=true },

        DEBUFF_TYPE_BORDER_MODE_VALUES = {
            { value = "OFF", text = "Off" },
            { value = "BORDER", text = "Border" },
            { value = "SYMBOL", text = "Border + Symbol" },
        },

        DURATION_BAR_DISPLAY_VALUES = {
            { value = "BAR_ONLY", text = "Bar Only" },
            { value = "OVERLAY", text = "Icon + Bar" },
        },
        DURATION_BAR_DISPLAY_OK = { BAR_ONLY=true, OVERLAY=true },

        DURATION_BAR_POSITION_VALUES = {
            { value = "BOTTOM", text = "Bottom" },
            { value = "TOP", text = "Top" },
        },
        DURATION_BAR_POSITION_OK = { BOTTOM=true, TOP=true },

        DURATION_BAR_DIRECTION_VALUES = {
            { value = "REMAINING", text = "Remaining" },
            { value = "ELAPSED", text = "Elapsed" },
        },
        DURATION_BAR_DIRECTION_OK = { REMAINING=true, ELAPSED=true },

        AURA_ANCHORS = {
            { value = "TOPLEFT", text = "Top Left" },
            { value = "TOP", text = "Top" },
            { value = "TOPRIGHT", text = "Top Right" },
            { value = "LEFT", text = "Left" },
            { value = "CENTER", text = "Center" },
            { value = "RIGHT", text = "Right" },
            { value = "BOTTOMLEFT", text = "Bottom Left" },
            { value = "BOTTOM", text = "Bottom" },
            { value = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        AURA_ANCHOR_OK = {
            TOPLEFT=true, TOP=true, TOPRIGHT=true,
            LEFT=true, CENTER=true, RIGHT=true,
            BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true,
        },
        FRAME_STRATA_OK = {
            AUTO=true, BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true,
            DIALOG=true, FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true,
        },

        LANE_GROWTH_VALUES = {
            { value = "RIGHTDOWN", text = "Right then Down" },
            { value = "LEFTDOWN", text = "Left then Down" },
            { value = "RIGHTUP", text = "Right then Up" },
            { value = "LEFTUP", text = "Left then Up" },
            { value = "UP", text = "Up (Single Column)" },
            { value = "DOWN", text = "Down (Single Column)" },
        },
        LANE_GROWTH_PARTS = {
            RIGHTDOWN = { "RIGHT", "DOWN" },
            LEFTDOWN = { "LEFT", "DOWN" },
            RIGHTUP = { "RIGHT", "UP" },
            LEFTUP = { "LEFT", "UP" },
            UP = { "UP", "UP" },
            DOWN = { "DOWN", "DOWN" },
        },

        -- Reserve the remaining result keys so later assignments do not resize the hash.
        BOSS_LOOKUP = nil,
        BOSS_UNITS = nil,
        ARENA_UNITS = nil,
        ARENA_LOOKUP = nil,
        CUSTOM_CONTAINER_MAX = nil,
        DEFAULT_GENERAL = nil,
        DEFAULT_SHARED = nil,
        GROUPS = nil,
        LANE_STYLE_KEYS = nil,
        LAYOUT_KEYS = nil,
        PLAYER_DEFENSIVE_CONTAINER_INDEX = nil,
        SCOPE_MATERIALIZED_LAYOUT_KEYS = nil,
        SHARED_LAYOUT_KEYS = nil,
        STYLE_LAYOUT_KEYS = nil,
        STYLE_SHARED_LAYOUT_KEYS = nil,
        TARGET_DOT_CONTAINER_INDEX = nil,
        UNIT_FLAG = nil,
    }
end

function Factories.Schema(A3)
    -- Unit lane keys, their owners, the lane specs, the show flags and the legacy
    -- Shared defaults come from the one lane-key schema in Auras3/MSUF_Auras3_Core.lua.
    -- The runtime schema takes the same tables on Mainline, so controls and
    -- compiled config agree on every key's scope.
    local LaneKeySchema = assert(A3.LaneKeySchema, "Auras3 core must load before the menu schema")
    local BOSS_UNITS = LaneKeySchema.UNIT_FAMILIES.boss
    local ARENA_UNITS = LaneKeySchema.UNIT_FAMILIES.arena
    local BOSS_LOOKUP, ARENA_LOOKUP = {}, {}
    for index = 1, #BOSS_UNITS do BOSS_LOOKUP[BOSS_UNITS[index]] = true end
    for index = 1, #ARENA_UNITS do ARENA_LOOKUP[ARENA_UNITS[index]] = true end
    -- Each runtime unit's show flag (the lane-key schema in the Auras3 core),
    -- plus the menu's Boss and Arena scopes.
    local UNIT_FLAG = { boss = LaneKeySchema.UNIT_FLAG.boss1, arena = LaneKeySchema.UNIT_FLAG.arena1 }
    for unit, flag in pairs(LaneKeySchema.UNIT_FLAG) do UNIT_FLAG[unit] = flag end

    local Schema = BuildDropdownDomains()

    Schema.LAYOUT_KEYS = LaneKeySchema.LAYOUT_KEYS
    Schema.SHARED_LAYOUT_KEYS = LaneKeySchema.SHARED_LAYOUT_KEYS
    Schema.STYLE_LAYOUT_KEYS = LaneKeySchema.STYLE_LAYOUT_KEYS
    Schema.STYLE_SHARED_LAYOUT_KEYS = LaneKeySchema.STYLE_SHARED_LAYOUT_KEYS
    Schema.SCOPE_MATERIALIZED_LAYOUT_KEYS = LaneKeySchema.SCOPE_MATERIALIZED_LAYOUT_KEYS
    Schema.GROUPS = LaneKeySchema.LANE_SPECS
    Schema.LANE_STYLE_KEYS = LaneKeySchema.LANE_STYLE_KEYS

    local DEFAULT_SHARED = LaneKeySchema.SeedDefaults()
    DEFAULT_SHARED.filters = {
        enabled = true,
        buffs = NewFilterSection(),
        debuffs = NewFilterSection(),
    }
    local buffFilters, debuffFilters = DEFAULT_SHARED.filters.buffs, DEFAULT_SHARED.filters.debuffs
    buffFilters.cancelable = false
    buffFilters.notCancelable = false
    buffFilters.externalDefensive = false
    buffFilters.bigDefensive = false
    debuffFilters.crowdControl = false
    debuffFilters.nonPlayer = false

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
    Schema.CUSTOM_CONTAINER_MAX = A3.CUSTOM_CONTAINER_COUNT
    Schema.TARGET_DOT_CONTAINER_INDEX = A3.PRESET_CUSTOM_CONTAINER_INDEX
    Schema.PLAYER_DEFENSIVE_CONTAINER_INDEX = A3.PRESET_CUSTOM_CONTAINER_INDEX

    -- Private dependency API; public menu methods remain on A3.MenuModel.
    Schema.BOSS_LOOKUP = BOSS_LOOKUP
    Schema.BOSS_UNITS = BOSS_UNITS
    Schema.ARENA_UNITS = ARENA_UNITS
    Schema.ARENA_LOOKUP = ARENA_LOOKUP
    Schema.DEFAULT_GENERAL = DEFAULT_GENERAL
    Schema.DEFAULT_SHARED = DEFAULT_SHARED
    Schema.UNIT_FLAG = UNIT_FLAG
    return Schema
end
