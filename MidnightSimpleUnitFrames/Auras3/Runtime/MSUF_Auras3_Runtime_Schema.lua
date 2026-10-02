-- Auras3 runtime: Schema.
-- Runtime-side lane tables: group lane specs, managed units and refresh reasons.
-- Unit lane keys and defaults derive from A3.LaneKeySchema (Auras3 core).
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Schema = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)

local IDENTITY_AURA_REFRESH_REASONS = {
    MSUF_UNIT_IDENTITY_AURAS = true,
    MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
    MSUF_GF_UNIT_IDENTITY = true,
}
local COLD_APPLY_REASONS = {
    MSUF_ELEMENT_REFRESH = true,
}

local MANAGED_UNITS = {
    player = true, pet = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
    arena1 = true, arena2 = true, arena3 = true,
}

-- The menu exposes one Boss filter scope, while layout remains frame-local for
-- boss1..boss5. Keep boss1 as the persisted token/blacklist rule owner so an
-- older profile with absent or stale siblings cannot compile different filters.
-- Arena mirrors the same owner-collapse pattern onto arena1.
local BOSS_FILTER_SCOPE_OWNER = {
    boss1 = "boss1", boss2 = "boss1", boss3 = "boss1", boss4 = "boss1", boss5 = "boss1",
    arena1 = "arena1", arena2 = "arena1", arena3 = "arena1",
}

local UNIT_FLAG = {
    player = "showPlayer", pet = "showPet",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
    arena1 = "showArena",
    arena2 = "showArena",
    arena3 = "showArena",
}

-- Unit lane keys, their owners and the fallback defaults come from the one
-- lane-key schema in Auras3/MSUF_Auras3_Core.lua. The menu schema takes the
-- same tables, so a new lane key cannot reach one side only.
local LaneKeySchema = assert(A3.LaneKeySchema, "Auras3 core must load before the runtime schema")
local DEFAULT_SHARED = LaneKeySchema.FallbackDefaults()
local LANE_SPECS = LaneKeySchema.LANE_SPECS
local STYLE_SHARED_LAYOUT_KEYS = LaneKeySchema.STYLE_SHARED_LAYOUT_KEYS

-- Group lanes use their own persisted suffixes and defaults. Build their
-- common fields once; optional filter keys stay explicit below so an absent key
-- does not accidentally opt a lane into include filtering or non-player rules.
local function GroupLaneSpec(prefix, rootKey, filter, defaultSize, defaultMax, defaultAnchor, defaultLayer)
    return {
        rootKey = rootKey, filter = filter,
        showKey = "show" .. rootKey, maxKey = "max" .. rootKey, sizeKey = prefix .. "IconSize",
        iconZoomKey = prefix .. "IconZoom", iconShapeKey = prefix .. "IconShape",
        spacingKey = prefix .. "Spacing", perRowKey = prefix .. "PerRow",
        growthXKey = prefix .. "GrowthX", growthYKey = prefix .. "GrowthY",
        anchorKey = prefix .. "Anchor", xKey = prefix .. "OffsetX", yKey = prefix .. "OffsetY",
        layerKey = prefix .. "Layer", filterKey = prefix .. "Filter", strataKey = prefix .. "Strata",
        alphaKey = prefix .. "Alpha", blacklistHashKey = prefix .. "BlacklistHash",
        hidePermanentKey = prefix .. "HidePermanent", maxDurationKey = prefix .. "MaxDuration",
        showTextKey = prefix .. "ShowCooldown", showStackKey = prefix .. "ShowStacks",
        swipeKey = prefix .. "ShowCooldownSwipe", swipeReverseKey = prefix .. "CooldownSwipeReverse",
        tooltipKey = prefix .. "ShowTooltip",
        sortMethodKey = prefix .. "SortMethod", sortReverseKey = prefix .. "SortReverse",
        showDurationBarKey = prefix .. "ShowDurationBar", durationBarHeightKey = prefix .. "DurationBarHeight",
        durationBarDisplayKey = prefix .. "DurationBarDisplay",
        durationBarPositionKey = prefix .. "DurationBarPosition",
        durationBarDirectionKey = prefix .. "DurationBarDirection",
        cooldownSizeKey = prefix .. "CooldownSize", stackSizeKey = prefix .. "StackSize",
        cooldownAnchorKey = prefix .. "CooldownAnchor", cooldownXKey = prefix .. "CooldownX",
        cooldownYKey = prefix .. "CooldownY", stackAnchorKey = prefix .. "StackAnchor",
        cooldownDecimalKey = prefix .. "CooldownDecimalSeconds",
        stackXKey = prefix .. "StackX", stackYKey = prefix .. "StackY",
        defaultSize = defaultSize, defaultMax = defaultMax, defaultPerRow = defaultMax,
        defaultAnchor = defaultAnchor, defaultLayer = defaultLayer,
    }
end

local GROUP_LANE_SPECS = {
    buff = GroupLaneSpec("buff", "Buffs", "HELPFUL", 22, 4, "BOTTOMRIGHT", 5),
    trackedBuff = GroupLaneSpec("trackedBuff", "TrackedBuffs", "HELPFUL", 22, 4, "TOPLEFT", 9),
    debuff = GroupLaneSpec("debuff", "Debuffs", "HARMFUL", 20, 3, "TOPLEFT", 6),
    -- EXTERNAL_DEFENSIVE already means a defensive received from another
    -- player. Match Blizzard's 12.1 ExternalDefensivesFrame exactly; adding
    -- !PLAYER needlessly makes the query depend on caster identity and can
    -- suppress valid externals such as Ironbark on restricted group units.
    external = GroupLaneSpec("external", "Externals", "HELPFUL|EXTERNAL_DEFENSIVE", 28, 2, "CENTER", 7),
}
GROUP_LANE_SPECS.buff.includeHashKey = "buffIncludeHash"
GROUP_LANE_SPECS.buff.includeSignatureKey = "buffIncludeSignature"
GROUP_LANE_SPECS.trackedBuff.includeHashKey = "trackedBuffIncludeHash"
GROUP_LANE_SPECS.debuff.nonPlayerKey = "debuffNonPlayer"

return {
    BOSS_FILTER_SCOPE_OWNER = BOSS_FILTER_SCOPE_OWNER,
    COLD_APPLY_REASONS = COLD_APPLY_REASONS,
    DEFAULT_SHARED = DEFAULT_SHARED,
    GROUP_LANE_SPECS = GROUP_LANE_SPECS,
    IDENTITY_AURA_REFRESH_REASONS = IDENTITY_AURA_REFRESH_REASONS,
    LANE_SPECS = LANE_SPECS,
    MANAGED_UNITS = MANAGED_UNITS,
    STYLE_SHARED_LAYOUT_KEYS = STYLE_SHARED_LAYOUT_KEYS,
    UNIT_FLAG = UNIT_FLAG,
}
end
