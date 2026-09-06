-- Auras3 runtime: LaneConfig.
-- Standard Unit and Group lane compilation from the shared schema. Layout and filter ownership are resolved before native creation.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.LaneConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local math_max = math.max
local type = type
local AddHidePermanentCandidateFilter = dependencies.ConfigValues.AddHidePermanentCandidateFilter
local AddMaxDurationCandidateFilter = dependencies.ConfigValues.AddMaxDurationCandidateFilter
local AddNonPlayerCandidateFilter = dependencies.ConfigValues.AddNonPlayerCandidateFilter
local ButtonAnchor = dependencies.ConfigValues.ButtonAnchor
local CandidateFiltersFromBlacklistHash = dependencies.ConfigValues.CandidateFiltersFromBlacklistHash
local CandidateFiltersFromIncludeAndExcludeSpellIDs = dependencies.ConfigValues.CandidateFiltersFromIncludeAndExcludeSpellIDs
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local FinalizeLane = dependencies.ConfigValues.FinalizeLane
local GROUP_LANE_SPECS = dependencies.Schema.GROUP_LANE_SPECS
local GridShape = dependencies.ConfigValues.GridShape
local GroupGrowthParts = dependencies.ConfigValues.GroupGrowthParts
local GrowthParts = dependencies.ConfigValues.GrowthParts
local LANE_SPECS = dependencies.Schema.LANE_SPECS
local NativeFilter = dependencies.ConfigValues.NativeFilter
local NormalizeAuraSortMethod = dependencies.Sort.NormalizeAuraSortMethod
local NormalizeDurationBarDirection = dependencies.ConfigValues.NormalizeDurationBarDirection
local NormalizeDurationBarDisplay = dependencies.ConfigValues.NormalizeDurationBarDisplay
local NormalizeDurationBarPosition = dependencies.ConfigValues.NormalizeDurationBarPosition
local NormalizeFrameStrata = dependencies.Platform.NormalizeFrameStrata
local NormalizeNativeFilterString = dependencies.ConfigValues.NormalizeNativeFilterString
local ReadAnchor = dependencies.ConfigValues.ReadAnchor
local ReadBool = dependencies.ConfigValues.ReadBool
local ReadDebuffTypeBorderMode = dependencies.ConfigValues.ReadDebuffTypeBorderMode
local ReadGroupDebuffTypeBorderMode = dependencies.ConfigValues.ReadGroupDebuffTypeBorderMode
local ReadNumber = dependencies.ConfigValues.ReadNumber
local ReadRaw = dependencies.ConfigValues.ReadRaw
local ReadUnitLaneStyleAnchor = dependencies.ConfigValues.ReadUnitLaneStyleAnchor
local ReadUnitLaneStyleBool = dependencies.ConfigValues.ReadUnitLaneStyleBool
local ReadUnitLaneStyleNumber = dependencies.ConfigValues.ReadUnitLaneStyleNumber
local ReadUnitLaneStyleRaw = dependencies.ConfigValues.ReadUnitLaneStyleRaw
local ReadUnitStyleAnchor = dependencies.ConfigValues.ReadUnitStyleAnchor
local ReadUnitStyleBool = dependencies.ConfigValues.ReadUnitStyleBool
local ReadUnitStyleRaw = dependencies.ConfigValues.ReadUnitStyleRaw
local Round = dependencies.Platform.Round
local Shape = dependencies.Appearance.Shape
local issecretvalue = dependencies.Platform.issecretvalue

local function CompileUnitLane(unit, laneLayout, layout, filtersRoot, kind, candidateFilters, candidateFilterSignature, portraitShape, rootShared)
    local spec = LANE_SPECS[kind]
    local filters = type(filtersRoot) == "table" and type(filtersRoot[spec.filterKey]) == "table" and filtersRoot[spec.filterKey] or nil
    local filtersEnabled = type(filters) ~= "table" or filters.enabled ~= false
    candidateFilters, candidateFilterSignature = AddHidePermanentCandidateFilter(
        candidateFilters, candidateFilterSignature,
        kind == "buff" and type(filtersRoot) == "table"
            and (filtersRoot.hidePermanent == true or (filters and filters.hidePermanent == true)))
    candidateFilters, candidateFilterSignature = AddNonPlayerCandidateFilter(
        candidateFilters, candidateFilterSignature,
        kind == "debuff" and filtersEnabled and filters and filters.nonPlayer == true)
    local sizeDefault = ReadRaw(layout, nil, spec.sizeKey) or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local zoomDefault = ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
        spec.iconZoomKey, "iconZoom") or DEFAULT_SHARED.iconZoom
    local iconShapeSource = Shape.SharedValue(rootShared, kind)
    local iconShape, requestedIconShape = Shape.Resolve(iconShapeSource, portraitShape)
    local spacing = ReadNumber(layout, nil, spec.spacingKey, DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(laneLayout, nil, spec.perRowKey, DEFAULT_SHARED.perRow, 1, 40)
    local maxCount = ReadNumber(laneLayout, nil, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local enabled = ReadBool(laneLayout, nil, spec.showKey, true) and maxCount > 0
    local growth = ReadRaw(laneLayout, nil, spec.growthKey) or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(laneLayout, nil, spec.wrapKey) or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign, verticalGrowth = GrowthParts(growth, rowWrap)
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local lanePadding = Round(ClampNumber(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
        spec.paddingKey, nil), 0, 0, 16))
    local debuffTypeBorderMode = kind == "debuff" and ReadDebuffTypeBorderMode(laneLayout, nil) or "OFF"
    local cooldownAnchor = ReadUnitStyleAnchor(layout, laneLayout, rootShared,
        "cooldownTextAnchor", DEFAULT_SHARED.cooldownTextAnchor)
    local rawStrata = ReadRaw(layout, nil, spec.strataKey)
    if issecretvalue(rawStrata) == true then rawStrata = nil end
    return FinalizeLane({
        kind = kind,
        appearanceKind = kind,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        -- Each lane owns its own filter gate. Hide Permanent remains an
        -- independent candidate filter, matching the Menu2 contract.
        nativeFilter = NativeFilter(spec.filter, filtersEnabled and filters or nil),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(zoomDefault, DEFAULT_SHARED.iconZoom, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        padding = lanePadding,
        weaponEnchants = kind == "buff" and unit == "player"
            and ReadBool(rootShared, nil, "showWeaponEnchants", false),
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing + 2 * lanePadding),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing + 2 * lanePadding),
        x = Round(ReadNumber(layout, nil, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)),
        y = Round(ReadNumber(layout, nil, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)),
        anchor = ReadAnchor(layout, nil, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ReadNumber(layout, nil, spec.layerKey, spec.defaultLayer, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = 1,
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showTextKey, "showCooldownText", true),
        showCooldownSwipe = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.swipeKey, "showCooldownSwipe", true),
        cooldownSwipeReverse = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.swipeReverseKey, "cooldownSwipeReverse", false),
        -- Native sorting belongs to this exact Aura container. Unlike the
        -- other Style fields, it must not fall back to a generic unit-wide key.
        sortMethod = NormalizeAuraSortMethod(ReadUnitLaneStyleRaw(layout, laneLayout, rootShared,
            spec.sortMethodKey, nil)),
        sortReverse = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.sortReverseKey, nil, false),
        -- Duration-bar visibility belongs to the local lane-layout owner.
        showDurationBar = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showDurationBarKey, "showDurationBar", false),
        durationBarHeight = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.durationBarHeightKey, "durationBarHeight", DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarDisplayKey, "durationBarDisplay"),
            DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarPositionKey, "durationBarPosition"),
            DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(
            ReadUnitLaneStyleRaw(layout, laneLayout, rootShared, spec.durationBarDirectionKey, "durationBarDirection"),
            DEFAULT_SHARED.durationBarDirection),
        showStacks = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.showStackKey, "showStackCount", true),
        showTooltip = ReadUnitLaneStyleBool(layout, laneLayout, rootShared,
            spec.tooltipKey, "showTooltip", DEFAULT_SHARED.showTooltip),
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        showStealableMarker = kind == "buff" and ReadUnitStyleBool(layout, laneLayout, rootShared, "buffShowStealable", false),
        stealableStyle = kind == "buff" and A3.NormalizeStealableStyle(
            ReadUnitStyleRaw(layout, laneLayout, rootShared, "buffStealableStyle")) or nil,
        cooldownSize = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownSizeKey, "cooldownTextSize", DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared,
            spec.cooldownAnchorKey, "cooldownTextAnchor", cooldownAnchor),
        cooldownX = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownXKey, "cooldownTextOffsetX", DEFAULT_SHARED.cooldownTextOffsetX, -2000, 2000),
        cooldownY = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownYKey, "cooldownTextOffsetY", DEFAULT_SHARED.cooldownTextOffsetY, -2000, 2000),
        cooldownDecimalSeconds = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.cooldownDecimalKey, "cooldownDecimalSeconds", DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadUnitLaneStyleAnchor(layout, laneLayout, rootShared,
            spec.stackAnchorKey, "stackCountAnchor", DEFAULT_SHARED.stackCountAnchor),
        stackSize = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackSizeKey, "stackTextSize", DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackXKey, "stackTextOffsetX", DEFAULT_SHARED.stackTextOffsetX, -2000, 2000),
        stackY = ReadUnitLaneStyleNumber(layout, laneLayout, rootShared,
            spec.stackYKey, "stackTextOffsetY", DEFAULT_SHARED.stackTextOffsetY, -2000, 2000),
    })
end

local function CompileGroupLane(unit, source, kind, groupKind, portraitShape, shared)
    local spec = GROUP_LANE_SPECS[kind]
    if not (spec and type(source) == "table") then return nil end
    local candidateFilters, candidateFilterSignature
    if spec.includeHashKey then
        candidateFilters, candidateFilterSignature = CandidateFiltersFromIncludeAndExcludeSpellIDs(
            source[spec.includeHashKey], source[spec.blacklistHashKey],
            spec.includeSignatureKey and source[spec.includeSignatureKey])
    else
        candidateFilters, candidateFilterSignature = CandidateFiltersFromBlacklistHash(source[spec.blacklistHashKey])
    end
    candidateFilters, candidateFilterSignature = AddMaxDurationCandidateFilter(
        candidateFilters, candidateFilterSignature,
        spec.maxDurationKey and source[spec.maxDurationKey], source[spec.hidePermanentKey] == true)
    candidateFilters, candidateFilterSignature = AddNonPlayerCandidateFilter(
        candidateFilters, candidateFilterSignature,
        spec.nonPlayerKey and source[spec.nonPlayerKey] == true)
    local size = ClampNumber(source[spec.sizeKey] or source.iconSize, spec.defaultSize, 1, 256)
    local sharedLane = kind == "debuff" and "debuff" or "buff"
    local iconShapeSource = Shape.SharedValue(shared, sharedLane)
    local iconShape, requestedIconShape = Shape.Resolve(iconShapeSource, portraitShape)
    local spacing = ClampNumber(source[spec.spacingKey] or source.spacing, 1, 0, 64)
    local perRow = ClampNumber(source[spec.perRowKey] or source.perRow, spec.defaultPerRow, 1, 40)
    local maxCount = ClampNumber(source[spec.maxKey], spec.defaultMax, 0, 80)
    local enabled = source.enabled ~= false and source[spec.showKey] == true and maxCount > 0
    local growthX, growthY, xSign, ySign, verticalGrowth = GroupGrowthParts(source[spec.growthXKey], source[spec.growthYKey])
    local cols, rows = GridShape(maxCount, perRow, verticalGrowth)
    local debuffTypeBorderMode = kind == "debuff" and ReadGroupDebuffTypeBorderMode(source) or "OFF"
    local cooldownSwipeReverse = source[spec.swipeReverseKey]
    if cooldownSwipeReverse == nil then cooldownSwipeReverse = source.cooldownSwipeReverse end
    local showTooltip = source[spec.tooltipKey]
    if showTooltip == nil then showTooltip = source.showTooltip end
    local rawStrata = source[spec.strataKey]
    if issecretvalue(rawStrata) == true then rawStrata = nil end
    if rawStrata == nil then rawStrata = source.strata end
    local nativeFilter = NormalizeNativeFilterString(source[spec.filterKey], spec.filter)
    -- Blizzard applies exact spell-ID candidate filters only while the unit's
    -- current identity supports that aura polarity: HELPFUL while assistable,
    -- HARMFUL while non-assistable. Compile the access mode once so rare
    -- identity events never inspect saved settings. The standard group debuff
    -- blacklist is intentionally neutral: hiding that entire lane whenever a
    -- friendly unit is assistable would be worse than Blizzard's exclude-only
    -- 12.1 limitation. A future HARMFUL include-ID lane is handled correctly.
    local hasIncludeIDs = candidateFilters and candidateFilters.includeSpellIDs ~= nil
    local hasExactIDs = hasIncludeIDs
        or candidateFilters and candidateFilters.excludeSpellIDs ~= nil
    local identityCandidateMode
    if (kind == "trackedBuff" or kind == "external")
        -- Exact-ID HELPFUL lanes on party/raid tokens follow the same
        -- 12.1.0.69465 contract as the Buff branch below: Blizzard applies
        -- their include filters unconditionally, so the assist gate could only
        -- hide correct content while costing a second native owner per group
        -- unit plus the UNIT_FLAGS shard. Ungated lanes fold into the shared
        -- GroupSlots container. Older clients keep the fail-closed gate.
        and type(_G.UnitIsPlayerControlledOrGroupMember) ~= "function" then
        identityCandidateMode = "assist"
    elseif hasIncludeIDs and nativeFilter:find("HARMFUL", 1, true) ~= nil then
        identityCandidateMode = "hostile"
    elseif kind == "buff" and (hasExactIDs
        or nativeFilter:find("EXTERNAL_DEFENSIVE", 1, true) ~= nil
        or nativeFilter:find("BIG_DEFENSIVE", 1, true) ~= nil)
        -- Since Retail 12.1.0.69465 Blizzard always permits ordinary Group Buff
        -- identity candidate filters on player/party/raid tokens, including
        -- immune or temporarily uninteractable followers. Keep these lanes out
        -- of MSUF's assist state machine when that API contract is present;
        -- AuraContainer remains the sole per-aura filter owner. Older clients
        -- retain the conservative fail-closed gate.
        and type(_G.UnitIsPlayerControlledOrGroupMember) ~= "function" then
        identityCandidateMode = "assist"
    end
    return FinalizeLane({
        kind = kind,
        appearanceKind = sharedLane,
        rootKey = spec.rootKey,
        unit = unit,
        enabled = enabled == true,
        nativeFilter = nativeFilter,
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        identityCandidateMode = identityCandidateMode,
        groupAccessGate = identityCandidateMode ~= nil,
        max = Round(maxCount),
        size = size,
        iconZoom = ClampNumber(source[spec.iconZoomKey] or source.iconZoom, 100, 100, 200),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        spacing = spacing,
        step = size + spacing,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(ClampNumber(source[spec.xKey], 0, -4096, 4096)),
        y = Round(ClampNumber(source[spec.yKey], 0, -4096, 4096)),
        anchor = ReadAnchor(source, nil, spec.anchorKey, spec.defaultAnchor),
        layer = Round(ClampNumber(source[spec.layerKey], spec.defaultLayer, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = Clamp01(source[spec.alphaKey], 1),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = verticalGrowth == true,
        initialAnchor = ButtonAnchor(xSign, ySign),
        showCooldownText = source[spec.showTextKey] ~= false,
        showCooldownSwipe = source[spec.swipeKey] ~= false,
        cooldownSwipeReverse = cooldownSwipeReverse == true,
        sortMethod = NormalizeAuraSortMethod(source[spec.sortMethodKey]),
        sortReverse = source[spec.sortReverseKey] == true,
        showDurationBar = source[spec.showDurationBarKey] == true or source.showDurationBar == true,
        durationBarHeight = ClampNumber(source[spec.durationBarHeightKey] or source.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(source[spec.durationBarDisplayKey] or source.durationBarDisplay, DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = NormalizeDurationBarPosition(source[spec.durationBarPositionKey] or source.durationBarPosition, DEFAULT_SHARED.durationBarPosition),
        durationBarDirection = NormalizeDurationBarDirection(source[spec.durationBarDirectionKey] or source.durationBarDirection, DEFAULT_SHARED.durationBarDirection),
        showStacks = source[spec.showStackKey] ~= false,
        showTooltip = showTooltip ~= false,
        showAuraBorder = debuffTypeBorderMode ~= "OFF",
        showAuraSymbol = debuffTypeBorderMode == "SYMBOL",
        cooldownSize = ClampNumber(source[spec.cooldownSizeKey] or source.cooldownSize, DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = ReadAnchor(source, nil, spec.cooldownAnchorKey, "CENTER"),
        cooldownX = ClampNumber(source[spec.cooldownXKey] or source.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(source[spec.cooldownYKey] or source.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(source[spec.cooldownDecimalKey] or source.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = ReadAnchor(source, nil, spec.stackAnchorKey, "BOTTOMRIGHT"),
        stackSize = ClampNumber(source[spec.stackSizeKey] or source.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(source[spec.stackXKey] or source.stackX, 0, -2000, 2000),
        stackY = ClampNumber(source[spec.stackYKey] or source.stackY, 0, -2000, 2000),
    }, sharedLane)
end

return {
    CompileGroupLane = CompileGroupLane,
    CompileUnitLane = CompileUnitLane,
}
end
