-- Auras3 runtime: GroupConfig.
-- Group configuration/cache and common preview metrics. Synthetic previews share immutable descriptors; live party/raid tokens retain separate identities.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.GroupConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local tostring = tostring
local type = type
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local CompileDispelSensor = dependencies.DispelConfig.CompileDispelSensor
local CompileGroupLane = dependencies.LaneConfig.CompileGroupLane
local EnsureDB = dependencies.ConfigValues.EnsureDB
local IsGroupFrame = dependencies.ConfigValues.IsGroupFrame
local NormalizeDurationBarDirection = dependencies.ConfigValues.NormalizeDurationBarDirection
local NormalizeDurationBarDisplay = dependencies.ConfigValues.NormalizeDurationBarDisplay
local NormalizeDurationBarPosition = dependencies.ConfigValues.NormalizeDurationBarPosition
local Shape = dependencies.Appearance.Shape
local SharedIconStyle = dependencies.ConfigValues.SharedIconStyle

-- A group edit must not evict UnitFrame configs or the global Appearance cache.
-- These three revisions advance only on configuration writes, never aura events.
-- The fallback also covers synthetic/legacy frames without a declared group kind.
local groupConfigRevisions = { party = 0, raid = 0, mythicraid = 0, [false] = 0 }

function A3.InvalidateGroupRuntimeConfig(scope)
    if type(scope) ~= "string" then return false end
    local party = scope == "party" or scope == "gf_party" or scope:match("^party%d+$") ~= nil
    local raid = scope == "raid" or scope == "gf_raid" or scope:match("^raid%d+$") ~= nil
    local mythic = raid or scope == "mythicraid" or scope == "gf_mythicraid"
    if scope == "group" or scope == "groups" then party, raid, mythic = true, true, true end
    if not (party or raid or mythic) then return false end
    if party then groupConfigRevisions.party = groupConfigRevisions.party + 1 end
    if raid then groupConfigRevisions.raid = groupConfigRevisions.raid + 1 end
    if mythic then groupConfigRevisions.mythicraid = groupConfigRevisions.mythicraid + 1 end
    groupConfigRevisions[false] = groupConfigRevisions[false] + 1
    return true
end

local function FirstEnabledIndicatorItem(items)
    if type(items) ~= "table" then return nil end
    for i = 1, #items do
        if type(items[i]) == "table" and items[i].enabled ~= false then
            return i
        end
    end
end

local function AppendEnabledIndicatorItems(out, items, first)
    if type(items) ~= "table" then return end
    for i = first or 1, #items do
        if type(items[i]) == "table" and items[i].enabled ~= false then
            out[#out + 1] = items[i]
        end
    end
end

local function BuildGroupSpellIndicatorSource(spellSource, cornerSource)
    local spells = type(spellSource) == "table" and spellSource.enabled == true and spellSource.items or nil
    local corners = type(cornerSource) == "table" and cornerSource.enabled == true and cornerSource.customSlots or nil
    local firstCorner = FirstEnabledIndicatorItem(corners)
    -- The ordinary Spell Icons path retains its source and original item indices.
    -- Only contributing corners require a merged list; never build a copy that
    -- would immediately be discarded, or allocate one for an empty owner.
    if not firstCorner then return FirstEnabledIndicatorItem(spells) and spellSource or nil end
    local items = {}
    AppendEnabledIndicatorItems(items, spells)
    AppendEnabledIndicatorItems(items, corners, firstCorner)
    return {
        enabled = true,
        items = items,
        layer = type(spellSource) == "table" and spellSource.layer or (type(cornerSource) == "table" and cornerSource.layer or 9),
        iconZoom = type(spellSource) == "table" and spellSource.iconZoom or 100,
        strata = type(spellSource) == "table" and spellSource.strata or "AUTO",
    }
end

local function CompileGroupSpellIndicatorStyle(spellSource, groupKind, portraitShape)
    local raw = type(spellSource) == "table" and type(spellSource.style) == "table" and spellSource.style or nil
    raw = raw or {}
    local _, shared = EnsureDB()
    local iconShape, requestedIconShape = Shape.Resolve(Shape.SharedValue(shared, "buff"), portraitShape)
    return {
        -- Spell Icons use the shared Buff Appearance theme. Every other field
        -- below belongs only to this Group scope's Spell Icon Style.
        iconStyle = SharedIconStyle("buff"),
        iconShape = iconShape,
        requestedIconShape = requestedIconShape,
        alpha = Clamp01(raw.alpha, 1),
        showTooltip = raw.showTooltip ~= false,
        showCooldownText = raw.showCooldownText ~= false,
        showCooldownSwipe = raw.showCooldownSwipe ~= false,
        cooldownSwipeReverse = raw.cooldownSwipeReverse == true,
        cooldownSize = ClampNumber(raw.cooldownSize, 8, 6, 40),
        cooldownAnchor = raw.cooldownAnchor or "CENTER",
        cooldownX = ClampNumber(raw.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(raw.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(raw.cooldownDecimalSeconds, 3, 0, 30),
        showDurationBar = raw.showDurationBar == true,
        durationBarHeight = ClampNumber(raw.durationBarHeight, 2, 1, 16),
        durationBarDisplay = NormalizeDurationBarDisplay(raw.durationBarDisplay, "BAR_ONLY"),
        durationBarPosition = NormalizeDurationBarPosition(raw.durationBarPosition, "BOTTOM"),
        durationBarDirection = NormalizeDurationBarDirection(raw.durationBarDirection, "REMAINING"),
        showStacks = raw.showStacks ~= false,
        stackSize = ClampNumber(raw.stackSize, 10, 6, 40),
        stackAnchor = raw.stackAnchor or "BOTTOMRIGHT",
        stackX = ClampNumber(raw.stackX, 0, -2000, 2000),
        stackY = ClampNumber(raw.stackY, 0, -2000, 2000),
    }
end

local function ResolveGroupFrameConfig(frame, unit)
    if not frame then return nil end
    unit = unit or frame.MSUFUnitKey
    local spec = frame.MSUFSpec
    local source = spec and (spec.auras or (spec.group and spec.group.auras))
    local spellSource = spec and spec.spellIndicators
    local cornerSource = spec and spec.cornerIndicators
    -- ReplaceTableContents keeps table identity across a visual-domain refresh,
    -- so identity alone cannot detect a symbol edit. The group config compiler
    -- stamps a signature when it reads the settings; this path only compares it,
    -- because it runs per frame per identity event.
    local symbolSignature = (spec and spec.dispelSymbol and spec.dispelSymbol.signature) or "-"
    local groupAssistGate = IsGroupFrame(frame) and frame._msufGFIsPreviewFrame ~= true
    -- The group kind doubles as the aura scope key for the shared icon style
    -- opt-out; party/raid/mythicraid can each be excluded independently.
    local groupKind = frame._msufGFKind
    -- Both counters only advance; never reset a scope revision. Their sum keeps
    -- the existing single generation check on cache hits. Kind is checked too:
    -- independent scopes can have equal sums when a pooled frame changes kind.
    local gen = (A3._runtimeConfigGen or 1)
        + (groupConfigRevisions[groupKind or false] or groupConfigRevisions[false])
    local visualGen = A3._nativeVisualGen or 0
    local cached = frame._msufA3NativeGroupConfig
    if cached and frame._msufA3NativeGroupSpec == spec
        and frame._msufA3NativeGroupSource == source and frame._msufA3NativeGroupSpellSource == spellSource
        and frame._msufA3NativeGroupCornerSource == cornerSource and frame._msufA3NativeGroupUnit == unit
        and frame._msufA3NativeGroupSymbolSignature == symbolSignature
        and frame._msufA3NativeGroupGen == gen and frame._msufA3NativeGroupVisualGen == visualGen
        and cached._msufA3GroupKind == groupKind
        and cached.groupAssistGate == groupAssistGate then
        return cached
    end
    -- Compiled group specs are immutable for their revision. Preview frames all
    -- use the same spec and the synthetic player unit, so compiling aura lanes,
    -- dispel sensors, and spell-indicator slots once per frame only duplicates
    -- tables without changing the result. Share that cold-path config on the spec;
    -- live frames with distinct unit tokens still receive distinct entries.
    local sharedCache = spec and spec._msufA3NativeGroupConfigCache
    local sharedKey = tostring(unit) .. "\031" .. tostring(groupKind) .. (groupAssistGate and "\031group" or "\031shared")
    local shared = sharedCache and sharedCache[sharedKey]
    if shared and shared.source == source and shared.spellSource == spellSource
        and shared.cornerSource == cornerSource and shared.symbolSignature == symbolSignature
        and shared.gen == gen and shared.visualGen == visualGen
    then
        cached = shared.config
        frame._msufA3NativeGroupSpec = spec
        frame._msufA3NativeGroupSource = source
        frame._msufA3NativeGroupSpellSource = spellSource
        frame._msufA3NativeGroupCornerSource = cornerSource
        frame._msufA3NativeGroupSymbolSignature = symbolSignature
        frame._msufA3NativeGroupUnit = unit
        frame._msufA3NativeGroupGen = gen
        frame._msufA3NativeGroupVisualGen = visualGen
        frame._msufA3NativeGroupConfig = cached
        return cached
    end
    local cfg = {
        unit = unit,
        enabled = false,
        lanes = {},
        sensors = {},
        group = true,
        groupAssistGate = groupAssistGate,
        _msufA3ConfigGen = gen,
        _msufA3GroupKind = groupKind,
        _msufA3VisualGen = visualGen,
        _msufA3Source = source,
    }
    local portraitShape = spec and spec.portrait and spec.portrait.shape
    local _, sharedAuraStyle = EnsureDB()
    local buff = type(source) == "table" and CompileGroupLane(unit, source, "buff", groupKind, portraitShape, sharedAuraStyle) or nil
    local combinedSpellSource = BuildGroupSpellIndicatorSource(spellSource, cornerSource)
    local spellIndicatorRoot
    if combinedSpellSource and type(unit) == "string" and unit ~= "" then
        local spellIndicatorStyle = CompileGroupSpellIndicatorStyle(spellSource, groupKind, portraitShape)
        spellIndicatorRoot = SpellIndicatorsRuntime.CompileSlots(unit, combinedSpellSource, spellIndicatorStyle)
    end
    cfg.spellIndicators = spellIndicatorRoot
    cfg.enabled = spellIndicatorRoot and spellIndicatorRoot.enabled == true or false
    if type(source) == "table" and type(unit) == "string" and unit ~= "" and source.enabled ~= false then
        local trackedBuff = CompileGroupLane(unit, source, "trackedBuff", groupKind, portraitShape, sharedAuraStyle)
        local debuff = CompileGroupLane(unit, source, "debuff", groupKind, portraitShape, sharedAuraStyle)
        local external = CompileGroupLane(unit, source, "external", groupKind, portraitShape, sharedAuraStyle)
        cfg.lanes.buff = buff
        cfg.lanes.trackedBuff = trackedBuff
        cfg.lanes.debuff = debuff
        cfg.lanes.external = external
        cfg.enabled = cfg.enabled == true
            or (buff and buff.enabled == true)
            or (trackedBuff and trackedBuff.enabled == true)
            or (debuff and debuff.enabled == true)
            or (external and external.enabled == true)
    end

    -- Frame highlights have their own compiled enable flags. In particular,
    -- inherited Cleanse borders must work with every aura icon lane and Dispel
    -- Overlay disabled; source.enabled only gates the icon lanes above.
    if type(unit) == "string" and unit ~= "" then
        local dispelBorder = CompileDispelSensor(unit, spec, true, "border")
        local dispelOverlay = CompileDispelSensor(unit, spec, true, "overlay")
        local dispelCorner = CompileDispelSensor(unit, spec, true, "corner")
        local dispelSymbol = CompileDispelSensor(unit, spec, true, "symbol")
        cfg.sensors.dispelBorder = dispelBorder
        cfg.sensors.dispelOverlay = dispelOverlay
        cfg.sensors.dispelCorner = dispelCorner
        cfg.sensors.dispelSymbol = dispelSymbol
        cfg.enabled = cfg.enabled == true
            or (dispelBorder and dispelBorder.enabled == true)
            or (dispelOverlay and dispelOverlay.enabled == true)
            or (dispelCorner and dispelCorner.enabled == true)
            or (dispelSymbol and dispelSymbol.enabled == true)
    end
    frame._msufA3NativeGroupSpec = spec
    frame._msufA3NativeGroupSource = source
    frame._msufA3NativeGroupSpellSource = spellSource
    frame._msufA3NativeGroupCornerSource = cornerSource
    frame._msufA3NativeGroupSymbolSignature = symbolSignature
    frame._msufA3NativeGroupUnit = unit
    frame._msufA3NativeGroupGen = gen
    frame._msufA3NativeGroupVisualGen = visualGen
    frame._msufA3NativeGroupConfig = cfg
    if spec then
        sharedCache = sharedCache or {}
        spec._msufA3NativeGroupConfigCache = sharedCache
        sharedCache[sharedKey] = {
            source = source,
            spellSource = spellSource,
            cornerSource = cornerSource,
            symbolSignature = symbolSignature,
            gen = gen,
            visualGen = visualGen,
            config = cfg,
        }
    end
    return cfg
end
local function FrameAuraConfig(frame, unit)
    if IsGroupFrame(frame) then
        return ResolveGroupFrameConfig(frame, unit or frame.MSUFUnitKey)
    end
    return A3.ResolveUnitFrameConfig(unit or (frame and frame.MSUFUnitKey), frame and frame.MSUFSpec)
end

--- Cold-path preview bridge. Menu mocks and synthetic Edit Mode rows consume
--- the exact finalized runtime lanes/slots instead of reimplementing their
--- geometry. Preview entry points are combat-guarded by their owners; this
--- function only resolves/caches immutable configuration and creates no frame,
--- event, timer, or OnUpdate.
function A3.ResolveAuraPreviewConfig(frame, unit, frameSpec)
    if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then return nil end
    if frameSpec ~= nil and frame and frameSpec ~= frame.MSUFSpec and IsGroupFrame(frame) then
        local proxy = frame._msufA3AuraPreviewConfigProxy
        if not proxy then
            proxy = {}
            frame._msufA3AuraPreviewConfigProxy = proxy
        end
        proxy._msufIsGroupFrame = true
        proxy._msufGFIsPreviewFrame = true
        proxy._msufGFKind = frame._msufGFKind
        proxy.MSUFUnitKey = unit or frame.MSUFUnitKey
        proxy.MSUFSpec = frameSpec
        return ResolveGroupFrameConfig(proxy, proxy.MSUFUnitKey)
    end
    return FrameAuraConfig(frame, unit or (frame and frame.MSUFUnitKey))
end

function A3.BuildAuraLaneMetrics(configOrUnit, kind)
    local rawKind = tostring(kind or "buff"):lower()
    local customIndex = rawKind:match("^custom(%d)$")
    if customIndex then
        customIndex = math_min(4, math_max(1, tonumber(customIndex) or 1))
        kind = "custom" .. tostring(customIndex)
    else
        kind = (rawKind == "debuff" or rawKind == "debuffs") and "debuff" or "buff"
    end
    local cfg = type(configOrUnit) == "table" and configOrUnit or A3.ResolveUnitFrameConfig(configOrUnit)
    local lane = cfg and cfg.lanes and cfg.lanes[kind]
    if not lane then return nil end
    local debuffBorderMode = lane.showAuraSymbol == true and "SYMBOL"
        or lane.showAuraBorder == true and "BORDER" or "OFF"
    return {
        enabled = lane.enabled == true,
        num = lane.max,
        size = lane.size,
        spacing = lane.spacing,
        step = lane.step,
        perRow = lane.perRow,
        cols = lane.cols,
        rows = lane.rows,
        width = lane.width,
        height = lane.height,
        alpha = lane.alpha,
        iconZoom = lane.iconZoom,
        iconShape = lane.iconShape,
        requestedIconShape = lane.requestedIconShape,
        growth = lane.growthX,
        rowWrap = lane.growthY,
        growthX = lane.xSign,
        growthY = lane.ySign,
        xSign = lane.xSign,
        ySign = lane.ySign,
        verticalGrowth = lane.verticalGrowth == true,
        initialAnchor = lane.initialAnchor,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
        layer = lane.layer,
        padding = lane.padding,
        iconStyle = lane.iconStyle,
        -- Edit Mode is a preview renderer for this already-compiled runtime
        -- lane. Hand it the finalized Style values instead of making it
        -- reinterpret layout/layoutShared ownership a second time.
        textConfig = {
            showStackCount = lane.showStacks == true,
            showCooldownText = lane.showCooldownText == true,
            showCooldownSwipe = lane.showCooldownSwipe == true,
            cooldownSwipeReverse = lane.cooldownSwipeReverse == true,
            stackSize = lane.stackSize,
            stackX = lane.stackX,
            stackY = lane.stackY,
            cooldownSize = lane.cooldownSize,
            cooldownX = lane.cooldownX,
            cooldownY = lane.cooldownY,
            cooldownDecimalSeconds = lane.cooldownDecimalSeconds,
            showDurationBar = lane.showDurationBar == true,
            durationBarHeight = lane.durationBarHeight,
            durationBarDisplay = lane.durationBarDisplay,
            durationBarPosition = lane.durationBarPosition,
            durationBarDirection = lane.durationBarDirection,
            stackAnchor = lane.stackAnchor,
            cooldownAnchor = lane.cooldownAnchor,
            debuffBorderMode = debuffBorderMode,
        },
    }
end

--- Compiled shared Appearance style for preview surfaces.
function A3.IconStylePreviewForKind(kind)
    return SharedIconStyle(kind)
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true or false
end

return {
    FrameAuraConfig = FrameAuraConfig,
    ResolveGroupFrameConfig = ResolveGroupFrameConfig,
}
end
