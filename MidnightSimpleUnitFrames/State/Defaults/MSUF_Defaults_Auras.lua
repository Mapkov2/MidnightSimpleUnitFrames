-- Aura model conversion, lane ownership and canonical aura defaults.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local ARENA_AURA_SLOTS = Parts.ARENA_AURA_SLOTS
local ExportPublic = Parts.ExportPublic
local IS_CLASSIC_FAMILY = Parts.IS_CLASSIC_FAMILY
local MSUF_DEFAULTS_SPEC = Parts.MSUF_DEFAULTS_SPEC
local MSUF_Defaults_DeepCopy = Parts.MSUF_Defaults_DeepCopy
local MSUF_Defaults_TableHasAnyValue = Parts.MSUF_Defaults_TableHasAnyValue
local MSUF_Defaults_ToNumber = Parts.MSUF_Defaults_ToNumber
local StateHelpers = Parts.StateHelpers
local MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE = {
    player = { 275, 40 },
    target = { 276, 40 },
    focus = { 216, 30 },
    targettarget = { 170, 36 },
    focustarget = { 170, 30 },
    boss = { 264, 35 },
}

local function MSUF_Defaults_A2AuraFrameKey(unit)
    if unit == "tot" or unit == "targetoftarget" then return "targettarget" end
    if unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    if type(unit) == "string" and unit:match("^arena%d+$") then return "arena" end
    return unit
end

local function MSUF_Defaults_A2AuraFrameSize(profile, unit)
    local key = MSUF_Defaults_A2AuraFrameKey(unit)
    local conf = type(profile) == "table" and type(profile[key]) == "table" and profile[key] or nil
    local defaults = MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE[key] or MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE.player
    local width = MSUF_Defaults_ToNumber(conf and (conf.width or conf.frameWidth)) or defaults[1]
    local height = MSUF_Defaults_ToNumber(conf and (conf.height or conf.frameHeight)) or defaults[2]
    if width < 1 then width = defaults[1] end
    if height < 1 then height = defaults[2] end
    return width, height
end

local function MSUF_Defaults_A2AuraReadNumber(primary, secondary, key, fallback)
    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
    if n ~= nil then return n end
    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
    if n ~= nil then return n end
    return fallback or 0
end

local function MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, profile)
    if type(auras) ~= "table" or auras._msufAuras3LegacyGeometry_v2 == true then return false end
    local shared = type(auras.shared) == "table" and auras.shared or {}
    auras.shared = shared
    -- Aura2 v11f anchored both lane containers with buff/debuffGroupOffsetX/Y.
    -- The older buff/debuffOffset aliases remained in SavedVariables (notably
    -- the default buffOffsetY = 30) but the 5.57 renderer no longer read them.
    -- Treating those dead aliases as live group offsets moves migrated auras.
    local useRetiredLaneOffsetAliases = shared._msufA2_migrated_v11f ~= true
    local repairV1 = auras._msufAuras3LegacyGeometry_v1 == true
    local changed = false
    if type(auras.perUnit) == "table" then
        for unit, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                local storedLayout = type(unitCfg.layout) == "table" and unitCfg.layout or nil
                local layout = unitCfg.overrideLayout == true and storedLayout or {}
                if unitCfg.layout ~= layout then unitCfg.layout = layout
                    changed = true end
                if unitCfg.overrideSharedLayout ~= true and type(unitCfg.layoutShared) == "table" then
                    unitCfg.layoutShared = {}
                    changed = true
                end
                local width, height = MSUF_Defaults_A2AuraFrameSize(profile, unit)
                local baseX = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetX", 0)
                local baseY = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetY", 0)
                local function ReadLaneNumber(primary, secondary, key, aliasKey, fallback)
                    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
                    if n ~= nil then return n end
                    if useRetiredLaneOffsetAliases then
                        n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[aliasKey]) or nil
                        if n ~= nil then return n end
                    end
                    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
                    if n ~= nil then return n end
                    if useRetiredLaneOffsetAliases then
                        n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[aliasKey]) or nil
                        if n ~= nil then return n end
                    end
                    return fallback or 0
                end
                for _, lane in ipairs({
                    { "buffGroupOffsetX", "buffGroupOffsetY", "buffAnchor", "buffOffsetX", "buffOffsetY" },
                    { "debuffGroupOffsetX", "debuffGroupOffsetY", "debuffAnchor", "debuffOffsetX", "debuffOffsetY" },
                }) do
                    local anchor = "BOTTOMLEFT"
                    local x
                    local y
                    if repairV1 then
                        x = ReadLaneNumber(layout, nil, lane[1], lane[4], 0)
                        y = ReadLaneNumber(layout, nil, lane[2], lane[5], 0)
                        local oldAnchor = tostring(layout[lane[3]] or ""):upper()
                        if oldAnchor == "TOPRIGHT" or oldAnchor == "BOTTOMRIGHT" then
                            x = x + width
                        end
                        if oldAnchor == "TOPLEFT" or oldAnchor == "TOPRIGHT" then
                            y = y + height
                        end
                    else
                        x = baseX + ReadLaneNumber(layout, shared, lane[1], lane[4], 0)
                        y = height + baseY + ReadLaneNumber(layout, shared, lane[2], lane[5], 0)
                    end
                    if layout[lane[3]] ~= anchor then layout[lane[3]] = anchor
                        changed = true end
                    if layout[lane[1]] ~= x then layout[lane[1]] = x
                        changed = true end
                    if layout[lane[2]] ~= y then layout[lane[2]] = y
                        changed = true end
                end
                if unitCfg.overrideLayout ~= true then unitCfg.overrideLayout = true
                    changed = true end
            end
        end
    end
    auras._msufAuras3LegacyGeometry_v1 = true
    auras._msufAuras3LegacyGeometry_v2 = true
    return true
end

local function MSUF_Defaults_NormalizeAuras3Profile(db)
    if type(db) ~= "table" then return false end
    local changed = false
    local fromLegacyAuras2 = false
    if db.auras ~= nil then
        db.auras = nil
        changed = true
    end
    if type(db.auras2) == "table" and (type(db.auras3) ~= "table" or tonumber(db._msufProfileSchema) ~= 600) then
        db.auras3 = {}
        MSUF_Defaults_DeepCopy(db.auras3, db.auras2)
        db.auras3._msufAuras3TranslatedFromLegacyAuras2 = true
        fromLegacyAuras2 = true
        changed = true
    end
    if db.auras2 ~= nil then
        db.auras2 = nil
        changed = true
    end
    local auras = db.auras3
    if type(auras) ~= "table" then return changed end
    if fromLegacyAuras2 or (auras._msufAuras3TranslatedFromLegacyAuras2 == true and auras._msufAuras3LegacyGeometry_v2 ~= true) then
        changed = MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, db) or changed
    end
    changed = StateHelpers.NormalizeAuraLayoutTable(auras.shared, MSUF_DEFAULTS_SPEC) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layout, MSUF_DEFAULTS_SPEC) or changed
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layoutShared, MSUF_DEFAULTS_SPEC) or changed
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then
                    unitCfg.overrideLayout = true
                    changed = true
                end
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then
                    unitCfg.overrideSharedLayout = true
                    changed = true
                end
            end
        end
    end
    return changed
end

local MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION = IS_CLASSIC_FAMILY and 1 or 2
local MSUF_DEFAULTS_GROUP_AURA_PROFILE_MODEL_REVISION = 1
local MSUF_DEFAULTS_GROUP_AURA_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid" }
local MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer = assert(
    MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer,
    "Aura defaults must load before profile defaults")

-- Unit Aura lanes no longer inherit mutable values from auras3.shared.  This
-- cold-path migration snapshots the profile's previously effective values
-- into the exact Unit + Buff/Debuff owner before runtime or Menu2 reads them.
-- The old Shared fields stay as import compatibility input, but changing them
-- afterwards cannot alter a Unit lane.
local MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS = {
    "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3",
}
-- TBC and Mists field five arena opponents (Game/Shared/Initialize.lua); every
-- other client keeps the three above, so this loop does not run there.
for i = 4, ARENA_AURA_SLOTS do
    MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[#MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS + 1] = "arena" .. i
end
local MSUF_DEFAULTS_UNIT_AURA_LANES = {
    buff = {
        prefix = "buff",
        showKey = "showBuffs", maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX", yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize", anchorKey = "buffAnchor",
        layerKey = "buffLayer", strataKey = "buffStrata",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow",
        growthKey = "buffGrowthX", wrapKey = "buffGrowthY",
        defaultAnchor = "BOTTOMRIGHT", defaultLayer = 5,
    },
    debuff = {
        prefix = "debuff",
        showKey = "showDebuffs", maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX", yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize", anchorKey = "debuffAnchor",
        layerKey = "debuffLayer", strataKey = "debuffStrata",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX", wrapKey = "debuffGrowthY",
        defaultAnchor = "TOPLEFT", defaultLayer = 6,
    },
}
local MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT = {
    { "IconZoom", "iconZoom", 100 },
    { "StylePadding", "stylePadding", 0 },
    { "DurationBarHeight", "durationBarHeight", 2 },
    { "StackTextSize", "stackTextSize", 14 },
    { "StackTextOffsetX", "stackTextOffsetX", -1 },
    { "StackTextOffsetY", "stackTextOffsetY", 1 },
    { "CooldownTextSize", "cooldownTextSize", 14 },
    { "CooldownTextOffsetX", "cooldownTextOffsetX", 0 },
    { "CooldownTextOffsetY", "cooldownTextOffsetY", 0 },
}
local MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED = {
    { "ShowCooldownText", "showCooldownText", true },
    { "ShowCooldownSwipe", "showCooldownSwipe", true },
    { "CooldownSwipeReverse", "cooldownSwipeReverse", false },
    { "SortMethod", "sortMethod", "DEFAULT" },
    { "SortReverse", "sortReverse", false },
    { "ShowDurationBar", "showDurationBar", false },
    { "DurationBarDisplay", "durationBarDisplay", "BAR_ONLY" },
    { "DurationBarPosition", "durationBarPosition", "BOTTOM" },
    { "DurationBarDirection", "durationBarDirection", "REMAINING" },
    { "ShowTooltip", "showTooltip", true },
    { "ShowStackCount", "showStackCount", true },
    { "StackCountAnchor", "stackCountAnchor", "TOPRIGHT" },
    { "CooldownTextAnchor", "cooldownTextAnchor", "CENTER" },
    { "CooldownDecimalSeconds", "cooldownDecimalSeconds", 3 },
}
local MSUF_DEFAULTS_AURA_APPEARANCE_KINDS = {
    "buff", "debuff", "playerDefensives", "targetDots",
}
local MSUF_DEFAULTS_AURA_APPEARANCE_STYLE_DEFAULTS = {
    styleBorderEnabled = false,
    styleBorderStyle = "SOLID",
    styleBorderThickness = 1,
    styleBorderColor = { 0, 0, 0, 1 },
    styleShadowEnabled = false,
    styleShadowSize = 4,
    styleShadowColor = { 0, 0, 0, 0.8 },
}

local function MSUF_Defaults_CopyAuraOwnedValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    MSUF_Defaults_DeepCopy(out, value)
    return out
end

local function MSUF_Defaults_ReadAuraLegacyOwner(owner, ownerActive, shared, laneKey, genericKey, fallback)
    if ownerActive and type(owner) == "table" then
        if owner[laneKey] ~= nil then return owner[laneKey] end
        if genericKey and owner[genericKey] ~= nil then return owner[genericKey] end
    end
    if type(shared) == "table" then
        if shared[laneKey] ~= nil then return shared[laneKey] end
        if genericKey and shared[genericKey] ~= nil then return shared[genericKey] end
    end
    return fallback
end

local function MSUF_Defaults_WriteAuraOwnedValue(owner, key, value)
    owner[key] = MSUF_Defaults_CopyAuraOwnedValue(value)
end

-- Profiles saved with three arena Aura owners gain arena4..N as copies of
-- arena1 once, on clients with more arena slots (TBC and Mists). Existing
-- owners are never overwritten. Without arena1 the slot marker stays unset,
-- so a later pass seeds once arena1 exists. Mainline (3 slots) is a no-op.
local function MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    local slots = tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3
    if slots <= 3 or type(auras) ~= "table" then return false end
    if (tonumber(auras._msufA3ArenaAuraSlots) or 3) >= slots then return false end
    local perUnit = auras.perUnit
    local source = type(perUnit) == "table" and perUnit.arena1 or nil
    if type(source) ~= "table" then return false end
    for i = 4, slots do
        if type(perUnit["arena" .. i]) ~= "table" then
            perUnit["arena" .. i] = MSUF_Defaults_CopyAuraOwnedValue(source)
        end
    end
    auras._msufA3ArenaAuraSlots = slots
    return true
end

local function MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    if type(auras) ~= "table" then return false end
    if auras._msufA3UnitLaneOwners_v1 == true then
        return MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    end
    auras.shared = type(auras.shared) == "table" and auras.shared or {}
    auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
    local shared = auras.shared
    -- Seed before the snapshot too, so a legacy arena1 owner (not the Shared
    -- fallback) becomes the source of the new arena4..N lanes.
    MSUF_Defaults_SeedExtraArenaAuraOwners(auras)

    for i = 1, #MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS do
        local unit = MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[i]
        local pu = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
        auras.perUnit[unit] = pu
        local oldLayout = type(pu.layout) == "table" and pu.layout or nil
        local oldSharedLayout = type(pu.layoutShared) == "table" and pu.layoutShared or nil
        local layoutActive = pu.overrideLayout == true
        local sharedLayoutActive = pu.overrideSharedLayout == true
        local styleActive = pu.overrideStyle == true
            or (pu.overrideStyle == nil and ((oldLayout and next(oldLayout)) or (oldSharedLayout and next(oldSharedLayout))))
        local layout, layoutShared = {}, {}

        for kind, spec in pairs(MSUF_DEFAULTS_UNIT_AURA_LANES) do
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.xKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.xKey, nil, 0))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.yKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.yKey, nil, kind == "buff" and 36 or 6))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.sizeKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.sizeKey, "iconSize", 26))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.anchorKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.anchorKey, nil, spec.defaultAnchor))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.layerKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.layerKey, nil, spec.defaultLayer))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.strataKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.strataKey, nil, "AUTO"))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.spacingKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.spacingKey, "spacing", 2))

            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.showKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.showKey, nil, true))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.maxKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.maxKey, nil, 12))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.perRowKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.perRowKey, "perRow", 12))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.growthKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.growthKey, "growth", "RIGHT"))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.wrapKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.wrapKey, "rowWrap", "DOWN"))

            for j = 1, #MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT do
                local field = MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT[j]
                local laneKey = spec.prefix .. field[1]
                MSUF_Defaults_WriteAuraOwnedValue(layout, laneKey,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive and styleActive,
                        shared, laneKey, field[2], field[3]))
            end
            for j = 1, #MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED do
                local field = MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED[j]
                local laneKey = spec.prefix .. field[1]
                MSUF_Defaults_WriteAuraOwnedValue(layoutShared, laneKey,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                        shared, laneKey, field[2], field[3]))
            end

            local framePrefix = spec.prefix .. "FrameEffect"
            for _, suffix in ipairs({ "Type", "Color", "Priority", "Thickness", "Layer", "Strata" }) do
                local key = framePrefix .. suffix
                local fallback = suffix == "Type" and "none"
                    or (suffix == "Color" and { 0.69, 0.50, 0.88, 0.80 })
                    or (suffix == "Priority" and 5)
                    or (suffix == "Thickness" and 2)
                    or (suffix == "Strata" and "AUTO") or 0
                MSUF_Defaults_WriteAuraOwnedValue(layoutShared, key,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                        shared, key, nil, fallback))
            end
        end

        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "buffShowStealable",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "buffShowStealable", nil, false))
        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "buffStealableStyle",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "buffStealableStyle", nil, "BORDER_ICON"))
        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "debuffTypeBorderMode",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "debuffTypeBorderMode", nil, shared.useDebuffTypeBorders == true and "SYMBOL" or "OFF"))
        layoutShared.useDebuffTypeBorders = layoutShared.debuffTypeBorderMode ~= "OFF"

        local sourceFilters = pu.overrideFilters == true and type(pu.filters) == "table" and pu.filters
            or (type(shared.filters) == "table" and shared.filters) or {}
        local filters = MSUF_Defaults_CopyAuraOwnedValue(sourceFilters)
        filters = type(filters) == "table" and filters or {}
        filters.buffs = type(filters.buffs) == "table" and filters.buffs or {}
        filters.debuffs = type(filters.debuffs) == "table" and filters.debuffs or {}
        if filters.buffs.enabled == nil then filters.buffs.enabled = sourceFilters.enabled ~= false end
        if filters.debuffs.enabled == nil then filters.debuffs.enabled = sourceFilters.enabled ~= false end

        pu.layout = layout
        pu.layoutShared = layoutShared
        pu.filters = filters
        pu.overrideLayout = true
        pu.overrideSharedLayout = true
        pu.overrideStyle = true
        pu.overrideFilters = true
    end

    -- Appearance is the one intentional global Aura owner, keyed by product.
    -- Snapshot legacy flat style/shape values so those old scalars become inert.
    shared.appearanceIconShapes = type(shared.appearanceIconShapes) == "table"
        and shared.appearanceIconShapes or {}
    shared.appearanceIconStyles = type(shared.appearanceIconStyles) == "table"
        and shared.appearanceIconStyles or {}
    for i = 1, #MSUF_DEFAULTS_AURA_APPEARANCE_KINDS do
        local kind = MSUF_DEFAULTS_AURA_APPEARANCE_KINDS[i]
        local harmful = kind == "debuff" or kind == "targetDots"
        if shared.appearanceIconShapes[kind] == nil then
            shared.appearanceIconShapes[kind] = shared[harmful and "debuffIconShape" or "buffIconShape"]
                or shared.iconShape or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE")
        end
        local style = type(shared.appearanceIconStyles[kind]) == "table"
            and shared.appearanceIconStyles[kind] or {}
        shared.appearanceIconStyles[kind] = style
        for key, fallback in pairs(MSUF_DEFAULTS_AURA_APPEARANCE_STYLE_DEFAULTS) do
            if style[key] == nil then
                style[key] = MSUF_Defaults_CopyAuraOwnedValue(
                    shared[key] ~= nil and shared[key] or fallback)
            end
        end
    end

    auras.profileModelRevision = MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
    auras._msufA3UnitLaneOwners_v1 = true
    MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    return true
end
ExportPublic("MSUF_MaterializeUnitAuraLaneOwners", MSUF_Defaults_MaterializeUnitAuraLaneOwners)
if type(MSUF) == "table" then
    MSUF.MSUF_MaterializeUnitAuraLaneOwners = MSUF_Defaults_MaterializeUnitAuraLaneOwners
end

local function MSUF_Defaults_CreateCanonicalUnitAuras()
    local schema = MSUF.DefaultsSchema
    local auras = schema.Fill({}, schema.Values.UnitAuras)
    auras.profileModelRevision = MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
    auras.customContainers.perUnit.player.items[4] = MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer()
    auras.shared.filters = schema.Fill({}, schema.Values.AuraFilters)
    for _, owner in pairs(auras.perUnit) do
        owner.filters = schema.Fill({}, schema.Values.AuraFilters)
    end
    for i = 1, 5 do
        local owner = schema.Fill({}, schema.Values.BossAuraOwner)
        owner.filters = schema.Fill({}, schema.Values.AuraFilters)
        auras.perUnit["boss" .. i] = owner
    end
    for i = 1, ARENA_AURA_SLOTS do
        local owner = schema.Fill({}, schema.Values.ArenaAuraOwner)
        owner.filters = schema.Fill({}, schema.Values.AuraFilters)
        auras.perUnit["arena" .. i] = owner
    end
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    return auras
end

ExportPublic("MSUF_CreateCanonicalUnitAuras", MSUF_Defaults_CreateCanonicalUnitAuras)
if type(MSUF) == "table" then
    MSUF.MSUF_CreateCanonicalUnitAuras = MSUF_Defaults_CreateCanonicalUnitAuras
end

--- Product-facing factory variant. Keep the hard-cut builder above stable:
--- pre-marker profiles preserve compiler-effective size/position by rebasing
--- against that baseline, while new/reset profiles use the authored 6.0 layout.
local function MSUF_Defaults_CreateFactoryUnitAuras()
    local auras = MSUF_Defaults_CreateCanonicalUnitAuras()
    auras.showPlayer = true
    auras.showFocus = true

    local shared = auras.shared
    shared.buffGroupOffsetX = 0
    shared.buffGroupOffsetY = 34
    shared.debuffGroupOffsetX = 330
    shared.debuffGroupOffsetY = 34
    shared.buffGroupIconSize = 28
    shared.debuffGroupIconSize = 28
    shared.buffAnchor = "BOTTOMLEFT"
    shared.debuffAnchor = "BOTTOMRIGHT"

    local perUnit = auras.perUnit
    local function SetScope(unit, values)
        local scope = type(perUnit[unit]) == "table" and perUnit[unit] or {}
        perUnit[unit] = scope
        scope.overrideLayout = true
        scope.layout = {
            offsetX = 243,
            offsetY = 27,
            iconSize = 28,
            buffGroupOffsetX = values.buffX,
            buffGroupOffsetY = values.buffY,
            debuffGroupOffsetX = values.debuffX,
            debuffGroupOffsetY = values.debuffY,
            buffGroupIconSize = 31,
            debuffGroupIconSize = 32,
            buffSpacing = 0,
            debuffSpacing = 0,
        }
        scope.overrideSharedLayout = true
        scope.layoutShared = {
            maxBuffs = values.maxBuffs,
            maxDebuffs = values.maxDebuffs,
            buffPerRow = 4,
            debuffPerRow = 4,
        }
    end

    SetScope("player", { buffX = -2, buffY = 41, debuffX = 2, debuffY = 40,
        maxBuffs = 3, maxDebuffs = 4 })
    SetScope("target", { buffX = -1, buffY = 42, debuffX = 0, debuffY = 42,
        maxBuffs = 3, maxDebuffs = 4 })
    SetScope("focus", { buffX = -2, buffY = 32, debuffX = 119, debuffY = 2,
        maxBuffs = 3, maxDebuffs = 4 })
    for i = 1, 5 do
        SetScope("boss" .. i, { buffX = -1, buffY = 28, debuffX = 131, debuffY = -2,
            maxBuffs = 3, maxDebuffs = 4 })
    end
    for i = 1, ARENA_AURA_SLOTS do
        SetScope("arena" .. i, { buffX = -1, buffY = 28, debuffX = 131, debuffY = -2,
            maxBuffs = 3, maxDebuffs = 4 })
    end

    local defensive = auras.customContainers.perUnit.player.items[4]
    defensive.portraitIcon = true
    defensive.placed.x = -293
    defensive.placed.y = 11
    auras._msufA3UnitLaneOwners_v1 = nil
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    return auras
end

--- Classic only. 6.5-alpha18 to 6.5-beta3 saved the factory scope above without
--- its final re-materialize: every authored owner kept only its sparse tables
--- under a lane-owner marker that was already set, so no pass ever completed it,
--- and the Classic aura compile, which reads only the owner, anchored buffs
--- BOTTOMRIGHT and debuffs TOPLEFT. Up to 6.5-beta2 only New Profile wrote
--- them; 6.5-beta3 also first login and reset, with player and target
--- retuned. Buff x/y and debuff x/y per unit family, as those builds saved them.
--- Midnight and WoW Forever never shipped those builds and never call this.
local MSUF_DEFAULTS_SPARSE_FACTORY_AURA_OFFSETS = {
    player = { { -2, 32, 3, 32 }, { -2, 46, 2, 49 } },
    target = { { -2, 32, 3, 32 }, { -1, 42, 0, 42 } },
    focus = { { -2, 32, 119, 2 } },
    boss = { { -1, 28, 131, -2 } },
    arena = { { -1, 28, 131, -2 } },
}

local function MSUF_Defaults_AuraValuesEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not MSUF_Defaults_AuraValuesEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

--- One-shot repair of those saved owners, decided per owner. An owner is
--- untouched only when it equals, key for key and value for value, what one
--- of those builds saved for its unit; the only extras allowed are the two a
--- mere read of the aura menu writes (_msufA3SparseVisualOverrides_v2 = true,
--- filters.debuffs.nonPlayer = false). An untouched owner is re-materialized in
--- place against the factory shared record, the pass a new profile runs; every
--- other owner, the saved shared record and the lane-owner marker stay as they
--- are. The stamp is written only with a repair, so a profile without an
--- untouched owner stays byte-for-byte unchanged.
local function MSUF_Defaults_RepairSparseFactoryAuraOwners(db)
    local auras = type(db) == "table" and db.auras3 or nil
    if type(auras) ~= "table" or type(auras.perUnit) ~= "table"
        or auras._msufA3UnitLaneOwners_v1 ~= true
        or auras._msufA3SparseLaneOwnersRepaired_v1 == true
        or auras.profileModelRevision ~= MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION then
        return false
    end
    local canonical, scope
    for i = 1, #MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS do
        local unit = MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[i]
        local owner = auras.perUnit[unit]
        local layout = type(owner) == "table" and owner.layout or nil
        -- Only the sparse factory tables carry these legacy keys, so complete
        -- owners leave here without allocating anything.
        if type(layout) == "table" and layout.offsetX == 243 and layout.offsetY == 27 and layout.iconSize == 28 then
            canonical = canonical or MSUF_Defaults_CreateCanonicalUnitAuras()
            local variants = MSUF_DEFAULTS_SPARSE_FACTORY_AURA_OFFSETS[unit:match("^%a+")] or {}
            local readFilters = type(owner.filters) == "table" and owner.filters.debuffs
            for v = 1, #variants do
                local offsets = variants[v]
                local saved = MSUF_Defaults_CopyAuraOwnedValue(canonical.perUnit[unit])
                saved.layout = {
                    offsetX = 243, offsetY = 27, iconSize = 28,
                    buffGroupOffsetX = offsets[1], buffGroupOffsetY = offsets[2],
                    debuffGroupOffsetX = offsets[3], debuffGroupOffsetY = offsets[4],
                    buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
                }
                saved.layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 }
                if owner._msufA3SparseVisualOverrides_v2 == true then saved._msufA3SparseVisualOverrides_v2 = true end
                if type(readFilters) == "table" and readFilters.nonPlayer == false then
                    saved.filters.debuffs.nonPlayer = false
                end
                if MSUF_Defaults_AuraValuesEqual(owner, saved) then
                    scope = scope or { shared = MSUF_Defaults_CreateFactoryUnitAuras().shared, perUnit = {} }
                    scope.perUnit[unit] = owner
                    break
                end
            end
        end
    end
    if not scope then return false end
    -- A scratch scope holding only the untouched owners: the pass completes
    -- them in place and every other table it builds is dropped with it.
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(scope)
    auras._msufA3SparseLaneOwnersRepaired_v1 = true
    return true
end

--- Canonical Group Aura baseline. This is intentionally authored as native
--- 6.0 data instead of being copied from the embedded compatibility snapshot.
--- Spell Indicators start empty and are populated by the current live
--- SpecDefaults seeder, so retired saved icons can never become factory data.
local function MSUF_Defaults_CreateCanonicalGroupAuraState(preserveExistingFilterDefaults)
    local schema = MSUF.DefaultsSchema
    local function Scope(isRaid)
        local scope = schema.Fill({}, schema.Values.GroupAuraState)
        local auras = schema.Fill({}, schema.Values.GroupAuras)
        scope.auras = auras
        local laneValues = isRaid and schema.Values.GroupRaidLanes or schema.Values.GroupPartyLanes
        for key, defaults in pairs(laneValues) do
            local lane = schema.Fill({}, defaults)
            schema.Fill(lane, schema.Values.GroupAuraLane)
            lane.enabled = lane.enabled ~= false
            lane.showStacks = lane.showStacks ~= false
            lane.cooldownSize = lane.cooldownSize or 10
            lane.stackSize = lane.stackSize or 10
            auras[key] = lane
        end
        auras.profileModelRevision = MSUF_DEFAULTS_GROUP_AURA_PROFILE_MODEL_REVISION
        auras.blizzardIconSize = isRaid and 18 or 20
        scope.privateAuras.size = isRaid and 10 or 12
        auras.buff.filterToken = preserveExistingFilterDefaults == true
            and (isRaid and "Raid" or "RaidPlayer") or "MSUF_GROUP_HIGHLIGHTS_V1"
        auras.externals.autoBlacklistBuffs = true
        auras.debuff.dispelBorderMode = "OFF"
        return scope
    end
    return { gf_party = Scope(false), gf_raid = Scope(true), gf_mythicraid = Scope(true) }
end

ExportPublic("MSUF_CreateCanonicalGroupAuraState", MSUF_Defaults_CreateCanonicalGroupAuraState)
if type(MSUF) == "table" then
    MSUF.MSUF_CreateCanonicalGroupAuraState = MSUF_Defaults_CreateCanonicalGroupAuraState
end

--- Factory profile flow:
--- The embedded compact string is a product baseline for brand-new installs.
--- It is decoded only when MSUF_DB is empty or contains only early bootstrap
--- buckets created before the UnitFrame factory runs, then normal defaults
--- and migrations still run afterward to fill fields added after the snapshot.

Parts.MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION = MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
Parts.MSUF_DEFAULTS_GROUP_AURA_SCOPES = MSUF_DEFAULTS_GROUP_AURA_SCOPES
Parts.MSUF_Defaults_CreateCanonicalGroupAuraState = MSUF_Defaults_CreateCanonicalGroupAuraState
Parts.MSUF_Defaults_CreateCanonicalUnitAuras = MSUF_Defaults_CreateCanonicalUnitAuras
Parts.MSUF_Defaults_CreateFactoryUnitAuras = MSUF_Defaults_CreateFactoryUnitAuras
Parts.MSUF_Defaults_NormalizeAuras3Profile = MSUF_Defaults_NormalizeAuras3Profile
Parts.MSUF_Defaults_RepairSparseFactoryAuraOwners = MSUF_Defaults_RepairSparseFactoryAuraOwners
