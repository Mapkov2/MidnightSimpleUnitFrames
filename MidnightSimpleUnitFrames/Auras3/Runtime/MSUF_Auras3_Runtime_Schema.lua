-- Auras3 runtime: Schema.
-- The single owner of lane fields, defaults and persistence classifications. Menu and runtime deliberately share these exact table references.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Schema = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local pairs = pairs
local tostring = tostring

local IDENTITY_AURA_REFRESH_REASONS = {
    MSUF_UNIT_IDENTITY_AURAS = true,
    MSUF_UNIT_IDENTITY_SOFT_AURAS = true,
    MSUF_GF_UNIT_IDENTITY = true,
}
local COLD_APPLY_REASONS = {
    MSUF_ELEMENT_REFRESH = true,
}

local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

-- The menu exposes one Boss filter scope, while layout remains frame-local for
-- boss1..boss5. Keep boss1 as the persisted token/blacklist rule owner so an
-- older profile with absent or stale siblings cannot compile different filters.
local BOSS_FILTER_SCOPE_OWNER = {
    boss1 = "boss1", boss2 = "boss1", boss3 = "boss1", boss4 = "boss1", boss5 = "boss1",
}

local UNIT_FLAG = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
}

local DEFAULT_SHARED = {
    showBuffs = true,
    showDebuffs = true,
    showTooltip = true,
    buffShowTooltip = true,
    debuffShowTooltip = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = false,
    sortMethod = "DEFAULT",
    sortReverse = false,
    showDurationBar = false,
    durationBarHeight = 2,
    durationBarDisplay = "BAR_ONLY",
    durationBarPosition = "BOTTOM",
    durationBarDirection = "REMAINING",
    showCooldownText = true,
    showStackCount = true,
    debuffTypeBorderMode = "OFF",
    useDebuffTypeBorders = false,
    iconSize = 26,
    iconZoom = 100,
    spacing = 2,
    perRow = 12,
    maxBuffs = 12,
    maxDebuffs = 12,
    growth = "RIGHT",
    rowWrap = "DOWN",
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
    cooldownTextAnchor = "CENTER",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownDecimalSeconds = 3,
    showWeaponEnchants = false,
    stylePadding = 0,
    styleBorderEnabled = false,
    styleBorderStyle = "SOLID",
    styleBorderThickness = 1,
    styleBorderColor = { 0, 0, 0, 1 },
    styleShadowEnabled = false,
    styleShadowSize = 4,
    styleShadowColor = { 0, 0, 0, 0.8 },
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
}

-- Prefix expansion happens once at composition. Compilers still read concrete
-- field names directly, and the menu receives these exact descriptor tables.
local function UnitLaneSpec(prefix, rootKey, filter, defaultAnchor, defaultLayer)
    return {
        rootKey = rootKey, filter = filter, filterKey = prefix .. "s",
        showKey = "show" .. rootKey, maxKey = "max" .. rootKey,
        xKey = prefix .. "GroupOffsetX", yKey = prefix .. "GroupOffsetY",
        sizeKey = prefix .. "GroupIconSize", paddingKey = prefix .. "StylePadding",
        iconZoomKey = prefix .. "IconZoom", iconShapeKey = prefix .. "IconShape",
        anchorKey = prefix .. "Anchor", layerKey = prefix .. "Layer",
        strataKey = prefix .. "Strata", perRowKey = prefix .. "PerRow",
        spacingKey = prefix .. "Spacing", growthKey = prefix .. "GrowthX",
        wrapKey = prefix .. "GrowthY", showTextKey = prefix .. "ShowCooldownText",
        swipeKey = prefix .. "ShowCooldownSwipe",
        swipeReverseKey = prefix .. "CooldownSwipeReverse",
        sortMethodKey = prefix .. "SortMethod", sortReverseKey = prefix .. "SortReverse",
        showDurationBarKey = prefix .. "ShowDurationBar",
        durationBarHeightKey = prefix .. "DurationBarHeight",
        durationBarDisplayKey = prefix .. "DurationBarDisplay",
        durationBarPositionKey = prefix .. "DurationBarPosition",
        durationBarDirectionKey = prefix .. "DurationBarDirection",
        tooltipKey = prefix .. "ShowTooltip", showStackKey = prefix .. "ShowStackCount",
        stackAnchorKey = prefix .. "StackCountAnchor", stackSizeKey = prefix .. "StackTextSize",
        stackXKey = prefix .. "StackTextOffsetX", stackYKey = prefix .. "StackTextOffsetY",
        cooldownSizeKey = prefix .. "CooldownTextSize",
        cooldownAnchorKey = prefix .. "CooldownTextAnchor",
        cooldownXKey = prefix .. "CooldownTextOffsetX", cooldownYKey = prefix .. "CooldownTextOffsetY",
        cooldownDecimalKey = prefix .. "CooldownDecimalSeconds",
        defaultAnchor = defaultAnchor, defaultLayer = defaultLayer,
    }
end

local LANE_SPECS = {
    buff = UnitLaneSpec("buff", "Buffs", "HELPFUL", "BOTTOMRIGHT", 5),
    debuff = UnitLaneSpec("debuff", "Debuffs", "HARMFUL", "TOPLEFT", 6),
}

-- Cold-path consumers derive ownership/routing from the compiler schema.
-- Export the exact table so menu and runtime cannot drift on new lane keys.
A3.UnitLaneSpecs = LANE_SPECS

local STYLE_LAYOUT_KEYS = {
    iconZoom = true,
    buffIconZoom = true,
    debuffIconZoom = true,
    stylePadding = true,
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

local STYLE_SHARED_LAYOUT_KEYS = {
    -- Keep this set identical to the Menu Model. Basic per-unit layout values
    -- (visibility, counts, wrapping, and growth) must remain active even while
    -- the unit inherits shared styling.
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

-- Derive every lane-prefixed Style key from the compiler schema. Keeping the
-- field ownership in one place prevents a newly split lane setting from being
-- read from layout while Menu2 writes it to layoutShared (or vice versa).
local LANE_LAYOUT_FIELDS = {
    "xKey", "yKey", "sizeKey", "anchorKey", "layerKey", "strataKey", "spacingKey",
}
local LANE_SHARED_LAYOUT_FIELDS = {
    "showKey", "maxKey", "perRowKey", "growthKey", "wrapKey",
}
local STYLE_LANE_LAYOUT_FIELDS = {
    "iconZoomKey", "paddingKey", "durationBarHeightKey",
    "stackSizeKey", "stackXKey", "stackYKey",
    "cooldownSizeKey", "cooldownXKey", "cooldownYKey",
}
local STYLE_LANE_SHARED_FIELDS = {
    "showTextKey", "swipeKey", "swipeReverseKey",
    "sortMethodKey", "sortReverseKey", "showDurationBarKey",
    "durationBarDisplayKey", "durationBarPositionKey", "durationBarDirectionKey",
    "tooltipKey", "showStackKey", "stackAnchorKey", "cooldownAnchorKey",
    "cooldownDecimalKey",
}
for _, spec in pairs(LANE_SPECS) do
    for _, field in ipairs(STYLE_LANE_LAYOUT_FIELDS) do
        local key = spec[field]
        if key then STYLE_LAYOUT_KEYS[key] = true end
    end
    for _, field in ipairs(STYLE_LANE_SHARED_FIELDS) do
        local key = spec[field]
        if key then STYLE_SHARED_LAYOUT_KEYS[key] = true end
    end
end
for key in pairs(STYLE_LAYOUT_KEYS) do
    assert(STYLE_SHARED_LAYOUT_KEYS[key] ~= true,
        "MSUF Auras3 style key has conflicting layout ownership: " .. tostring(key))
end

-- Every setting field in LANE_SPECS must declare exactly one persistence
-- owner. This is a cold load-time contract: a future field cannot silently be
-- compiled from one table while Menu2 routes writes to another.
local LANE_FIELD_OWNERS = {}
local function RegisterLaneFieldOwners(fields, owner)
    for _, field in ipairs(fields) do
        assert(LANE_FIELD_OWNERS[field] == nil,
            "MSUF Auras3 lane field has conflicting ownership: " .. tostring(field))
        LANE_FIELD_OWNERS[field] = owner
    end
end
RegisterLaneFieldOwners(LANE_LAYOUT_FIELDS, "layout")
RegisterLaneFieldOwners(LANE_SHARED_LAYOUT_FIELDS, "layoutShared")
RegisterLaneFieldOwners(STYLE_LANE_LAYOUT_FIELDS, "styleLayout")
RegisterLaneFieldOwners(STYLE_LANE_SHARED_FIELDS, "styleLayoutShared")
local LANE_NON_SCOPED_FIELDS = {
    rootKey = true,
    filterKey = true,
    iconShapeKey = true,
}
for kind, spec in pairs(LANE_SPECS) do
    for field in pairs(spec) do
        if tostring(field):match("Key$") then
            assert(LANE_FIELD_OWNERS[field] ~= nil or LANE_NON_SCOPED_FIELDS[field] == true,
                "MSUF Auras3 lane field has no declared owner: " .. tostring(kind) .. "." .. tostring(field))
        end
    end
end

-- Menu and runtime must classify style participation from the same tables.
-- The Menu Model loads after this compiler and reuses these exact references;
-- keeping a second production copy previously let ownership drift silently.
A3.UnitStyleLayoutKeys = STYLE_LAYOUT_KEYS
A3.UnitStyleSharedLayoutKeys = STYLE_SHARED_LAYOUT_KEYS
A3.UnitLaneLayoutFields = LANE_LAYOUT_FIELDS
A3.UnitLaneSharedLayoutFields = LANE_SHARED_LAYOUT_FIELDS

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
