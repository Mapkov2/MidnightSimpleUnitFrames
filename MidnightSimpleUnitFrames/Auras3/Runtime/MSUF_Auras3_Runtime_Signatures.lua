-- Auras3 runtime: Signatures.
-- The canonical distinction between tracking, structural and layout changes. A sealed native child is recreated when its immutable inputs change.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Signatures = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local tostring = tostring

local LaneLayoutSignature, LaneStructuralSignature, LaneTrackingSignature, SensorLayoutSignature, SensorStructuralSignature

LaneTrackingSignature = function(lane)
    -- initialAnchor, layer, and strata are tracking-level on purpose: the
    -- container is anchored once and born at its final level/strata as a child
    -- of the MSUF-owned host (it is sealed after AddAuraGroup), so growth,
    -- layer, or strata changes must recreate the container rather than mutate
    -- a live sealed one. Recreate is the only path PTR 7 guarantees.
    return tostring(lane.unit) .. "\030" .. tostring(lane.kind) .. "\030" .. tostring(lane.nativeFilter)
        .. "\030" .. tostring(lane.max) .. "\030" .. tostring(lane.candidateFilterSignature)
        .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.layer) .. "\030" .. tostring(lane.strata)
        .. "\030" .. tostring(lane.weaponEnchants)
end

local function UsesStandaloneAuraSlot(lane)
    -- Blizzard AuraGroups allocate frames in batches of ten. A normal lane
    -- that can display exactly one aura needs neither that pool nor flow
    -- layout, so use the one-frame AuraSlot primitive instead. Weapon enchants
    -- and custom-priority lanes retain AuraGroups because they own additional
    -- group-local ordering/layout behavior.
    return lane and lane.max == 1
        and lane.weaponEnchants ~= true
        and lane.customPriority ~= true
end

LaneStructuralSignature = function(lane)
    -- PTR 5 applies access restrictions immediately after initializeFrame.
    -- Any option that changes a button must therefore create a fresh native
    -- container so all setup remains inside that callback.
    -- The public 12.1 group-filter setter reparses native assignments in place.
    -- Button visuals and item-enchantment slots still belong to container
    -- creation and remain structural.
    return tostring(lane.kind) .. "\030" .. tostring(lane.identityCandidateMode)
        .. "\030" .. tostring(LaneLayoutSignature(lane))
        .. "\030" .. tostring(lane.weaponEnchants)
        .. "\030" .. tostring(lane.customPriority)
        .. "\030" .. tostring(lane.customPrioritySignature)
        .. "\030" .. tostring(lane.customPriority and lane.candidateFilterSignature or nil)
        .. "\030" .. tostring(UsesStandaloneAuraSlot(lane))
end

LaneLayoutSignature = function(lane)
    return tostring(lane.size) .. "\030" .. tostring(lane.iconZoom) .. "\030" .. tostring(lane.spacing)
        .. "\030" .. tostring(lane.iconShape) .. "\030" .. tostring(lane.requestedIconShape)
        .. "\030" .. tostring(lane.buttonWidth) .. "\030" .. tostring(lane.buttonHeight)
        .. "\030" .. tostring(lane.step) .. "\030" .. tostring(lane.stepX) .. "\030" .. tostring(lane.stepY)
        .. "\030" .. tostring(lane.perRow)
        .. "\030" .. tostring(lane.cols) .. "\030" .. tostring(lane.rows)
        .. "\030" .. tostring(lane.width) .. "\030" .. tostring(lane.height)
        .. "\030" .. tostring(lane.anchor) .. "\030" .. tostring(lane.x)
        .. "\030" .. tostring(lane.y) .. "\030" .. tostring(lane.layer)
        .. "\030" .. tostring(lane.strata)
        .. "\030" .. tostring(lane.xSign) .. "\030" .. tostring(lane.ySign)
        .. "\030" .. tostring(lane.verticalGrowth) .. "\030" .. tostring(lane.initialAnchor)
        .. "\030" .. tostring(lane.showCooldownText) .. "\030" .. tostring(lane.showCooldownSwipe)
        .. "\030" .. tostring(lane.cooldownSwipeReverse) .. "\030" .. tostring(lane.cooldownSize)
        .. "\030" .. tostring(lane.cooldownAnchor) .. "\030" .. tostring(lane.cooldownX)
        .. "\030" .. tostring(lane.cooldownY) .. "\030" .. tostring(lane.cooldownDecimalSeconds)
        .. "\030" .. tostring(lane.showDurationBar) .. "\030" .. tostring(lane.durationBarHeight)
        .. "\030" .. tostring(lane.durationBarDisplay) .. "\030" .. tostring(lane.durationBarPosition)
        .. "\030" .. tostring(lane.durationBarDirection)
        .. "\030" .. tostring(lane.showStacks) .. "\030" .. tostring(lane.stackAnchor)
        .. "\030" .. tostring(lane.stackSize) .. "\030" .. tostring(lane.stackX)
        .. "\030" .. tostring(lane.stackY) .. "\030" .. tostring(lane.showTooltip)
        .. "\030" .. tostring(lane.auraTooltipAnchor)
        .. "\030" .. tostring(lane.showAuraBorder) .. "\030" .. tostring(lane.showAuraSymbol)
        .. "\030" .. tostring(lane.showStealableMarker) .. "\030" .. tostring(lane.stealableStyle)
        .. "\030" .. tostring(lane.pandemicEnabled) .. "\030" .. tostring(lane.pandemicVisualEnabled)
        .. "\030" .. tostring(lane.pandemicStyle)
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[1] or lane.pandemicColor.r))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[2] or lane.pandemicColor.g))
        .. "\030" .. tostring(lane.pandemicColor and (lane.pandemicColor[3] or lane.pandemicColor.b))
        .. "\030" .. tostring(lane.pandemicThickness) .. "\030" .. tostring(lane.pandemicPadding)
        .. "\030" .. tostring(lane.pandemicBorderAlpha) .. "\030" .. tostring(lane.pandemicTintAlpha)
        .. "\030" .. tostring(lane.pandemicBlend)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.type)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.priority)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.thickness)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.layer)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.tintAlpha)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.strata)
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[1])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[2])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[3])
        .. "\030" .. tostring(lane.pandemicFrameEffect and lane.pandemicFrameEffect.color and lane.pandemicFrameEffect.color[4])
        .. "\030" .. tostring(lane.alpha)
        .. "\030" .. tostring(lane.padding)
        .. "\030" .. tostring(lane.portraitPositionWhenDisabled)
        .. "\030" .. tostring(lane.portraitLevelOffset)
        .. "\030" .. tostring(lane.iconStyle and lane.iconStyle.signature)
        .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

SensorStructuralSignature = function(sensor)
    return tostring(sensor.kind) .. "\030" .. tostring(sensor.max)
        .. "\030" .. tostring(sensor.nativeFilter)
        .. "\030" .. tostring(sensor.filterCount) .. "\030" .. tostring(sensor.filterMax)
        .. "\030" .. tostring(SensorLayoutSignature(sensor))
end

SensorLayoutSignature = function(sensor)
    return tostring(sensor.visual) .. "\030" .. tostring(sensor.target)
        .. "\030" .. tostring(sensor.style) .. "\030" .. tostring(sensor.alpha)
        .. "\030" .. tostring(sensor.thickness) .. "\030" .. tostring(sensor.layer) .. "\030" .. tostring(sensor.strata)
        .. "\030" .. tostring(sensor.detail) .. "\030" .. tostring(sensor.candidateFilterSignature)
        .. "\030" .. tostring(sensor.r) .. "\030" .. tostring(sensor.g) .. "\030" .. tostring(sensor.b)
        .. "\030" .. tostring(sensor.size) .. "\030" .. tostring(sensor.slotSignature)
        .. "\030" .. tostring(sensor.mode) .. "\030" .. tostring(sensor.growth)
        .. "\030" .. tostring(sensor.spacing) .. "\030" .. tostring(sensor.anchor)
        .. "\030" .. tostring(sensor.x) .. "\030" .. tostring(sensor.y)
        .. "\030" .. tostring(sensor.trigger) .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

return {
    LaneLayoutSignature = LaneLayoutSignature,
    LaneStructuralSignature = LaneStructuralSignature,
    LaneTrackingSignature = LaneTrackingSignature,
    SensorLayoutSignature = SensorLayoutSignature,
    SensorStructuralSignature = SensorStructuralSignature,
    UsesStandaloneAuraSlot = UsesStandaloneAuraSlot,
}
end
