-- Auras3 runtime: Signatures.
-- The canonical distinction between tracking, structural and layout changes. A sealed native child is recreated when its immutable inputs change.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Signatures = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local tostring = tostring

local LaneButtonSignature, LaneLayoutSignature, LaneStructuralSignature, LaneTrackingSignature
local SensorLayoutSignature, SensorStructuralSignature

-- Field order is the persisted native park contract. Nested colors keep the
-- historical array/RGB fallback and false/nil encoding; global inputs use the
-- content token. Derivations declare fields represented by finalized outputs.
local BUTTON_FIELDS = {
    "size", "iconZoom", "spacing", "iconShape", "requestedIconShape", "buttonWidth", "buttonHeight",
    "step", "stepX", "stepY", "perRow", "cols", "rows", "width", "height", "layer", "strata", "xSign",
    "ySign", "verticalGrowth", "initialAnchor", "showCooldownText", "showCooldownSwipe", "cooldownSwipeReverse",
    "cooldownSize", "cooldownAnchor", "cooldownX", "cooldownY", "cooldownDecimalSeconds", "showDurationBar",
    "durationBarHeight", "durationBarDisplay", "durationBarPosition", "durationBarDirection", "showStacks",
    "stackAnchor", "stackSize", "stackX", "stackY", "showTooltip", "auraTooltipAnchor", "showAuraBorder",
    "showAuraSymbol", "showStealableMarker", "stealableStyle", "pandemicEnabled", "pandemicVisualEnabled",
    "pandemicStyle", { path = { "pandemicColor", 1 }, fallback = "r" }, { path = { "pandemicColor", 2 }, fallback = "g" },
    { path = { "pandemicColor", 3 }, fallback = "b" }, "pandemicThickness", "pandemicPadding", "pandemicBorderAlpha",
    "pandemicTintAlpha", "pandemicBlend", { path = { "pandemicFrameEffect", "type" } }, { path = { "pandemicFrameEffect", "priority" } },
    { path = { "pandemicFrameEffect", "thickness" } }, { path = { "pandemicFrameEffect", "layer" } },
    { path = { "pandemicFrameEffect", "tintAlpha" } }, { path = { "pandemicFrameEffect", "strata" } },
    { path = { "pandemicFrameEffect", "color", 1 } }, { path = { "pandemicFrameEffect", "color", 2 } },
    { path = { "pandemicFrameEffect", "color", 3 } }, { path = { "pandemicFrameEffect", "color", 4 } },
    "padding", "portraitPositionWhenDisabled", "portraitLevelOffset", { path = { "iconStyle", "signature" } },
}
local TRACKING_FIELDS = {
    "unit", "kind", "nativeFilter", "max", "candidateFilterSignature",
    "initialAnchor", "layer", "strata", "weaponEnchants",
}
local LAYOUT_FIELDS = { "anchor", "x", "y", "alpha" }
-- Current compilers leave smoothing absent. Preserve their historical bytes;
-- an explicit optional value must still distinguish immutable timer binding.
local OPTIONAL_BUTTON_FIELDS = { "durationBarSmooth" }
local SIGNATURE_SCHEMA = {
    Fields = { Button = BUTTON_FIELDS, Tracking = TRACKING_FIELDS, Layout = LAYOUT_FIELDS, Optional = OPTIONAL_BUTTON_FIELDS },
    EncodedBy = {
        -- CompilePortraitAuraLane assigns a distinct kind to every portrait lane.
        portraitOverlay = "kind",
        -- FinalizeLane resolves the appearance kind to the complete iconStyle signature.
        appearanceKind = "iconStyle",
    },
}
local buttonParts, trackingParts, layoutParts = {}, {}, {}
local table_concat = table.concat
local function CompileFields(fields)
    local keys, positions, nested = {}, {}, {}
    for index = 1, #fields do
        local field = fields[index]
        if type(field) == "string" then
            keys[#keys + 1], positions[#positions + 1] = field, index
        else
            field.position = index
            nested[#nested + 1] = field
        end
    end
    return { keys = keys, positions = positions, nested = nested, count = #fields, scalar = #nested == 0 }
end
local buttonFields = CompileFields(BUTTON_FIELDS)
local trackingFields = CompileFields(TRACKING_FIELDS)
local layoutFields = CompileFields(LAYOUT_FIELDS)

local function ReadField(lane, field)
    local path = field.path
    local value = lane[path[1]]
    if not value then return value end
    local child = value[path[2]]
    if #path == 2 then
        if field.fallback then return child or value[field.fallback] end
        return child
    end
    if #path == 3 then return child and child[path[3]] end
    for index = 2, #path do
        if not value then return value end
        if index == #path and field.fallback then
            value = value[path[index]] or value[field.fallback]
        else
            value = value[path[index]]
        end
    end
    return value
end

local function FieldsSignature(lane, fields, parts)
    local keys, positions, nested = fields.keys, fields.positions, fields.nested
    if fields.scalar then
        for index = 1, #keys do parts[index] = tostring(lane[keys[index]]) end
        return table_concat(parts, "\030", 1, fields.count)
    end
    for index = 1, #keys do parts[positions[index]] = tostring(lane[keys[index]]) end
    for index = 1, #nested do
        local field = nested[index]
        parts[field.position] = tostring(ReadField(lane, field))
    end
    return table_concat(parts, "\030", 1, fields.count)
end

LaneTrackingSignature = function(lane)
    -- initialAnchor, layer, and strata are tracking-level on purpose: the
    -- container is anchored once and born at its final level/strata as a child
    -- of the MSUF-owned host (it is sealed after AddAuraGroup), so growth,
    -- layer, or strata changes must recreate the container rather than mutate
    -- a live sealed one. Recreate is the only path PTR 7 guarantees.
    return FieldsSignature(lane, trackingFields, trackingParts)
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

LaneStructuralSignature = function(lane, buttonSignature)
    -- PTR 5 applies access restrictions immediately after initializeFrame.
    -- Any option that changes a button must therefore create a fresh native
    -- container so all setup remains inside that callback.
    -- The public 12.1 group-filter setter reparses native assignments in place.
    -- Button visuals and item-enchantment slots still belong to container
    -- creation and remain structural.
    -- Where a lane sits and how opaque it is are not: Blizzard's flow layout
    -- anchors every AuraGroup button to its container, MSUF anchors that to an
    -- addon-owned host and fades the container, so the reuse path moves and
    -- fades the lane (SyncContainerGeometry) without touching a button. A
    -- standalone AuraSlot anchors its button in initializeFrame, so its offsets
    -- stay; an owner that sets each button's alpha adds it (OwnerConfig).
    local standalone = UsesStandaloneAuraSlot(lane)
    return tostring(lane.kind) .. "\030" .. tostring(lane.identityCandidateMode)
        .. "\030" .. (buttonSignature or LaneButtonSignature(lane))
        .. "\030" .. (standalone and (tostring(lane.anchor) .. "\030" .. tostring(lane.x)
            .. "\030" .. tostring(lane.y)) or "host")
        .. "\030" .. tostring(lane.weaponEnchants)
        .. "\030" .. tostring(lane.customPriority)
        .. "\030" .. tostring(lane.customPrioritySignature)
        .. "\030" .. tostring(lane.customPriority and lane.max or nil)
        .. "\030" .. tostring(lane.customPriority and lane.candidateFilterSignature or nil)
        .. "\030" .. tostring(standalone)
end

LaneLayoutSignature = function(lane, buttonSignature)
    return (buttonSignature or LaneButtonSignature(lane)) .. "\030"
        .. FieldsSignature(lane, layoutFields, layoutParts)
end

LaneButtonSignature = function(lane, sharedSignatures)
    local shared = sharedSignatures and sharedSignatures[lane.kind]
    if shared then return shared end
    local optional = ""
    for index = 1, #OPTIONAL_BUTTON_FIELDS do
        local field = OPTIONAL_BUTTON_FIELDS[index]
        if lane[field] ~= nil then optional = optional .. "\030" .. field .. ":" .. tostring(lane[field]) end
    end
    local signature = FieldsSignature(lane, buttonFields, buttonParts)
        .. "\030" .. tostring(A3.GetNativeVisualSignature and A3.GetNativeVisualSignature() or "0")
        .. optional
    if sharedSignatures then sharedSignatures[lane.kind] = signature end
    return signature
end

-- FinalizeLane: both signatures embed the button signature; build it once
-- (2026-10-11 raid trace: 96 lanes, 192 builds, 2.73 ms). Same strings.
local function LaneShapeSignatures(lane, sharedSignatures)
    local buttonSignature = LaneButtonSignature(lane, sharedSignatures)
    return LaneStructuralSignature(lane, buttonSignature), LaneLayoutSignature(lane, buttonSignature)
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
        .. "\030" .. tostring(sensor.trigger) .. "\030" .. tostring(A3.GetNativeVisualSignature and A3.GetNativeVisualSignature() or "0")
end

return {
    LaneSignatureSchema = SIGNATURE_SCHEMA,
    LaneLayoutSignature = LaneLayoutSignature,
    LaneShapeSignatures = LaneShapeSignatures,
    LaneStructuralSignature = LaneStructuralSignature,
    LaneTrackingSignature = LaneTrackingSignature,
    SensorLayoutSignature = SensorLayoutSignature,
    SensorStructuralSignature = SensorStructuralSignature,
    UsesStandaloneAuraSlot = UsesStandaloneAuraSlot,
}
end
