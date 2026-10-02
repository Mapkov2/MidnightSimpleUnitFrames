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
    local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
    local BOSS_LOOKUP = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
    local ARENA_UNITS = { "arena1", "arena2", "arena3" }
    local ARENA_LOOKUP = { arena1=true, arena2=true, arena3=true }
    local UNIT_FLAG = {
        player = "showPlayer",
        pet = "showPet",
        target = "showTarget",
        focus = "showFocus",
        boss = "showBoss",
        boss1 = "showBoss",
        boss2 = "showBoss",
        boss3 = "showBoss",
        boss4 = "showBoss",
        boss5 = "showBoss",
        arena = "showArena",
        arena1 = "showArena",
        arena2 = "showArena",
        arena3 = "showArena",
    }
    -- Arena slots 4..N follow the client arena fact (5 on TBC/Mists, 3 on Mainline).
    for arenaIndex = 4, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do
        local arenaUnit = "arena" .. arenaIndex
        ARENA_UNITS[#ARENA_UNITS + 1] = arenaUnit
        ARENA_LOOKUP[arenaUnit] = true
        UNIT_FLAG[arenaUnit] = "showArena"
    end

    local PUBLIC_UNITS = {
        { value = "player", text = "Player" },
        { value = "pet", text = "Pet" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
        { value = "boss", text = "Boss" },
        { value = "arena", text = "Arena" },
    }

    local STYLE_SCOPES = {
        { value = "shared", text = "Shared" },
        { value = "player", text = "Player" },
        { value = "pet", text = "Pet" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
        { value = "boss", text = "Boss" },
        { value = "arena", text = "Arena" },
    }

    local GROWTH_VALUES = {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "UP", text = "Up" },
        { value = "DOWN", text = "Down" },
    }
    local GROWTH_OK = { RIGHT=true, LEFT=true, UP=true, DOWN=true }

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

    -- Unit lane keys, their owners, the lane specs and the legacy Shared
    -- defaults come from the one lane-key schema in Auras3/MSUF_Auras3_Core.lua.
    -- The runtime schema takes the same tables on Mainline, so controls and
    -- compiled config agree on every key's scope.
    local LaneKeySchema = assert(A3.LaneKeySchema, "Auras3 core must load before the menu schema")
    local LAYOUT_KEYS = LaneKeySchema.LAYOUT_KEYS
    local SHARED_LAYOUT_KEYS = LaneKeySchema.SHARED_LAYOUT_KEYS
    local STYLE_LAYOUT_KEYS = LaneKeySchema.STYLE_LAYOUT_KEYS
    local STYLE_SHARED_LAYOUT_KEYS = LaneKeySchema.STYLE_SHARED_LAYOUT_KEYS
    local SCOPE_MATERIALIZED_LAYOUT_KEYS = LaneKeySchema.SCOPE_MATERIALIZED_LAYOUT_KEYS
    local GROUPS = LaneKeySchema.LANE_SPECS
    local LANE_STYLE_KEYS = LaneKeySchema.LANE_STYLE_KEYS

    local DEFAULT_SHARED = LaneKeySchema.SeedDefaults()
    DEFAULT_SHARED.filters = {
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
    local CUSTOM_CONTAINER_MAX = A3.CUSTOM_CONTAINER_COUNT
    local TARGET_DOT_CONTAINER_INDEX = A3.PRESET_CUSTOM_CONTAINER_INDEX
    local PLAYER_DEFENSIVE_CONTAINER_INDEX = A3.PRESET_CUSTOM_CONTAINER_INDEX

    -- Private dependency API; public menu methods remain on A3.MenuModel.
    return {
        AURA_ANCHORS = AURA_ANCHORS,
        AURA_ANCHOR_OK = AURA_ANCHOR_OK,
        BOSS_LOOKUP = BOSS_LOOKUP,
        BOSS_UNITS = BOSS_UNITS,
        ARENA_UNITS = ARENA_UNITS,
        ARENA_LOOKUP = ARENA_LOOKUP,
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
