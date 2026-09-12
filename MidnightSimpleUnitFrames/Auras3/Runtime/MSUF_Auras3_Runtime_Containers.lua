-- Auras3 runtime: Containers.
-- Native groups/slots, creation and geometry repair. Blizzard owns incremental aura tracking; unchanged descriptors reuse native owners.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Containers = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_max = math.max
local math_min = math.min
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local AURA_CONTAINER_ADDON = dependencies.Platform.AURA_CONTAINER_ADDON
local ApplyAuraTooltipStyle = dependencies.Platform.ApplyAuraTooltipStyle
local AuraSortEnums = dependencies.Sort.AuraSortEnums
local AuraSortSignature = dependencies.Sort.AuraSortSignature
local ConfigureNativeAuraContainer = dependencies.NativeContract.ConfigureNativeAuraContainer
local CreateFrame = dependencies.Platform.CreateFrame
local DEFAULT_SHARED = dependencies.Schema.DEFAULT_SHARED
local DS = dependencies.Appearance.DS
local DispelSensorTarget = dependencies.DispelVisuals.DispelSensorTarget
local EffectiveLaneFilters = dependencies.ConfigValues.EffectiveLaneFilters
local EnsureBlizzardAuraContainerLoaded = dependencies.Platform.EnsureBlizzardAuraContainerLoaded
local ManagedLaneFrameLevel = dependencies.CustomConfig.ManagedLaneFrameLevel
local PrepareAuraButton = dependencies.ButtonVisuals.PrepareAuraButton
local PrepareDispelSensorButton = dependencies.DispelVisuals.PrepareDispelSensorButton
local ReadParentFrameStrata = dependencies.Platform.ReadParentFrameStrata
local RegisterNativeContainer
local ResolveFrameStrata = dependencies.Platform.ResolveFrameStrata
local SensorLayoutSignature = dependencies.Signatures.SensorLayoutSignature
local SyncContainerGeometry = dependencies.ButtonVisuals.SyncContainerGeometry
local SyncFrameStrata = dependencies.Platform.SyncFrameStrata
local ValidateNativeAuraContainerContract = dependencies.NativeContract.ValidateNativeAuraContainerContract

local ConfigureContainer, SyncDispelSensorGeometry

local function ManagedAuraKey(config)
    return "msuf_" .. tostring(config and config.kind or "auras")
end

local function BuildManagedAuraGroupOptions(container, lane)
    local nextIndex = 0
    local sortMethod, sortDirection = AuraSortEnums(lane)
    local _, candidateFilters = EffectiveLaneFilters(lane)
    return {
        maxFrameCount = lane.max,
        candidateFilters = candidateFilters,
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            nextIndex = nextIndex + 1
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = container._msufA3ParentFrame
            -- No MSUF-side button bookkeeping: 12.1 exposes
            -- GetAuraGroupFrame/GetAuraGroupFrameCount for enumeration.
            PrepareAuraButton(button, lane, nextIndex)
            -- A mixed owner stays at alpha 1 so fixed slots retain their own
            -- opacity and group range can gate the owner. Carry flow opacity on
            -- its buttons instead of multiplying every sibling AuraSlot.
            if container._msufA3GroupSlotsRoot == true then button:SetAlpha(lane.alpha or 1) end
        end,
    }
end

local function ManagedAuraGroupLayoutOptions(lane)
    local size = lane.size or DEFAULT_SHARED.iconSize
    local spacing = lane.spacing or DEFAULT_SHARED.spacing
    return {
        -- Blizzard 12.1.0 validates these per-group field names in
        -- Blizzard_CustomAuraContainer.lua. frameWidth/frameHeight (old) and
        -- elementSpacingX/elementSpacingY (pre-PTR7) are ignored; PTR 7 reads
        -- elementWidth/elementHeight plus elementSpacing (X) and lineSpacing (Y).
        elementWidth = lane.buttonWidth or size,
        elementHeight = lane.buttonHeight or size,
        elementSpacing = spacing,
        lineSpacing = spacing,
    }
end

local function ApplyManagedAuraGroupLayout(container, groupKey, lane)
    container:SetAuraGroupLayout(groupKey, ManagedAuraGroupLayoutOptions(lane))
    A3.nativeAuraRuntimeLayoutError = nil
    return true
end

local function CreateNativeAuraContainer(root, parentOverride)
    ApplyAuraTooltipStyle()
    local container = CreateFrame("AuraContainer", nil, parentOverride or root, "CustomAuraContainerTemplate")
    if not container then
        A3.nativeAuraRuntimeAvailable = false
        A3._RecordNativeAuraRuntimeError("CustomAuraContainerTemplate is unavailable")
        return nil
    end
    if not ValidateNativeAuraContainerContract(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    -- Event registrations on CustomAuraContainerTemplate are intrinsic and
    -- carry Blizzard's forbidden EventRegistrations aspect. Leave the static
    -- AURA_DATA_PROVIDER_SWITCH subscription entirely Blizzard-owned; addon
    -- calls to RegisterEvent/UnregisterEvent on this object taint execution.
    container._msufA3Root = root
    return container
end

local function PriorityAuraCandidateFilters(container, lane, spellID)
    local cache = container._msufA3PriorityCandidateFilters
    if not cache then
        cache = {}
        container._msufA3PriorityCandidateFilters = cache
    end
    local key = tonumber(spellID) or 0
    local filters = cache[key]
    if filters then return filters end
    filters = {}
    for name, value in pairs(type(lane.candidateFilters) == "table" and lane.candidateFilters or {}) do
        if name ~= "includeSpellIDs" then filters[name] = value end
    end
    local included = {}
    if key > 0 then
        if type(A3.AddAuraSpellIDAndAliases) == "function" then
            A3.AddAuraSpellIDAndAliases(included, key)
        else
            included[key] = true
        end
    end
    filters.includeSpellIDs = included
    cache[key] = filters
    return filters
end

local function PriorityAuraGroupKey(lane, index)
    return ManagedAuraKey(lane) .. "_priority_" .. tostring(index)
end

local function BuildManagedPriorityAuraGroupOptions(container, lane, index, spellID)
    local sortMethod, sortDirection = AuraSortEnums(lane)
    return {
        maxFrameCount = 1,
        candidateFilters = PriorityAuraCandidateFilters(container, lane, spellID),
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = container._msufA3ParentFrame
            container[index] = button
            PrepareAuraButton(button, lane, index)
        end,
    }
end

local function ManagedPriorityAuraGroupLayoutOptions(lane, index)
    local size = lane.size or DEFAULT_SHARED.iconSize
    local spacing = lane.spacing or DEFAULT_SHARED.spacing
    return {
        -- Each priority entry owns one native AuraGroup. Empty groups contribute
        -- no spacing, while non-empty groups are packed by Blizzard in ascending
        -- layoutIndex order. elementSpacing must stay zero here: the distance
        -- between these one-frame groups is owned by groupSpacing.
        elementWidth = lane.buttonWidth or size,
        elementHeight = lane.buttonHeight or size,
        elementSpacing = 0,
        lineSpacing = spacing,
        groupSpacing = spacing,
        groupLineSpacing = spacing,
        layoutIndex = index,
    }
end

local function CreateManagedPriorityNativeLane(container, lane, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container._msufA3ManagedAuraGroups = true
    container._msufA3PriorityAuraGroups = true
    container._msufA3PriorityGroupKeys = {}
    ConfigureNativeAuraContainer(container, lane.unit)

    local priority = lane.customPrioritySpellIDs or {}
    local groupCount = math_min(lane.max or 0, #priority)
    for i = 1, groupCount do
        local groupKey = PriorityAuraGroupKey(lane, i)
        container._msufA3PriorityGroupKeys[i] = groupKey
        container:AddAuraGroup(groupKey, lane.nativeFilter,
            BuildManagedPriorityAuraGroupOptions(container, lane, i, priority[i]))
        container:SetAuraGroupLayout(groupKey, ManagedPriorityAuraGroupLayoutOptions(lane, i))
    end
    container.createdButtons = groupCount
    container._msufA3MaxFrameCount = groupCount
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function CreateManagedNativeLane(container, lane, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container._msufA3ManagedAuraGroups = true
    container._msufA3ManagedGroupKey = ManagedAuraKey(lane)
    container.createdButtons = lane.max or 0
    ConfigureNativeAuraContainer(container, lane.unit)

    local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
    container:AddAuraGroup(container._msufA3ManagedGroupKey, nativeFilter, BuildManagedAuraGroupOptions(container, lane))
    container._msufA3FilterString = nativeFilter
    container._msufA3CandidateFilterSignature = candidateFilterSignature
    container._msufA3SortSignature = AuraSortSignature(lane)
    -- PTR 7 item enchantments: temporary weapon enchants render as native
    -- buttons inside the player buff flow. The frames are CustomAuraButtons,
    -- so the normal initializeFrame styling pipeline applies unchanged.
    -- weaponEnchants is part of the structural signature -> toggling recreates.
    if lane.weaponEnchants == true and type(container.AddItemEnchantment) == "function" then
        local slots = _G.AuraContainerItemEnchantmentSlot
        local enchantOptions = {
            initializeFrame = function(button)
                button._msufA3ManagedAuraButton = true
                button._msufA3ParentFrame = container._msufA3ParentFrame
                PrepareAuraButton(button, lane, 1)
            end,
        }
        container:AddItemEnchantment(slots and slots.MainHand or 0, enchantOptions)
        container:AddItemEnchantment(slots and slots.OffHand or 1, enchantOptions)
        if type(container.SetItemEnchantmentLayout) == "function" then
            local placement = _G.CustomAuraContainerItemEnchantmentPlacement
            container:SetItemEnchantmentLayout({
                placement = placement and placement.BeforeAuraGroups or 0,
                elementSpacing = lane.spacing or 0,
                lineSpacing = lane.spacing or 0,
            })
        end
    end
    if not ApplyManagedAuraGroupLayout(container, container._msufA3ManagedGroupKey, lane) then
        if container.Hide then container:Hide() end
        return nil
    end
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function BuildManagedAuraSlotOptions(container, sensor, parentFrame, buttonIndex, sensorIndex, visuals)
    return {
        maxFrameCount = 1,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            container[buttonIndex] = button
            PrepareDispelSensorButton(button, sensor, parentFrame, sensorIndex or buttonIndex, visuals)
        end,
    }
end

local function GroupLaneSlotKey(lane)
    return ManagedAuraKey(lane)
end

local function BuildGroupLaneSlotOptions(container, lane, parentFrame, buttonIndex)
    local sortMethod, sortDirection = AuraSortEnums(lane)
    local _, candidateFilters = EffectiveLaneFilters(lane)
    return {
        candidateFilters = candidateFilters,
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        initializeFrame = function(button)
            button._msufA3ManagedAuraButton = true
            button._msufA3ParentFrame = parentFrame
            container[buttonIndex] = button
            -- AuraSlots share one native container with Spell/Dispel slots and
            -- an optional flowing AuraGroup, so the container cannot represent
            -- several independently configured lane Layers. Give this button
            -- the same final level/strata it would receive in a standalone
            -- flowing lane while initializeFrame is still allowed to mutate it.
            -- The sealed update path deliberately never touches it again.
            if button.SetFrameLevel then
                button:SetFrameLevel(ManagedLaneFrameLevel(parentFrame, lane) + 1)
            end
            SyncFrameStrata(button, ResolveFrameStrata(parentFrame, lane.strata))
            PrepareAuraButton(button, lane, 1)
            -- One icon fills the old fixed-size lane host exactly, so anchoring
            -- that icon by the configured outer anchor preserves its position.
            button:ClearAllPoints()
            button:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)
            -- Standalone slots inherit the lane alpha from their container.
            -- Shared GroupSlots cannot do that because every slot can have a
            -- different alpha, so those buttons continue to own it directly.
            button:SetAlpha(container._msufA3StandaloneAuraSlot == true and 1 or (lane.alpha or 1))
        end,
    }
end

local function CreateManagedNativeSlotLane(container, lane, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    ConfigureContainer(container, lane, parentFrame)
    container._msufA3ManagedAuraSlots = true
    container._msufA3StandaloneAuraSlot = true
    container._msufA3ManagedSlotKey = GroupLaneSlotKey(lane)
    container._msufA3LaneSlotFilterStrings = {}
    container._msufA3LaneSlotCandidateSignatures = {}
    container._msufA3LaneSlotSortSignatures = {}
    container.createdButtons = 1
    ConfigureNativeAuraContainer(container, lane.unit)

    local slotKey = container._msufA3ManagedSlotKey
    local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
    container:AddAuraSlot(slotKey, nativeFilter,
        BuildGroupLaneSlotOptions(container, lane, parentFrame, 1))
    container._msufA3LaneSlotFilterStrings[slotKey] = nativeFilter
    container._msufA3LaneSlotCandidateSignatures[slotKey] = candidateFilterSignature
    container._msufA3LaneSlotSortSignatures[slotKey] = AuraSortSignature(lane)
    container._msufA3FilterString = nativeFilter
    container._msufA3CandidateFilterSignature = candidateFilterSignature
    container._msufA3SortSignature = AuraSortSignature(lane)
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateAuraGroupEffectiveFilters(container, lane)
    if not (container and lane and container._msufA3ManagedGroupKey) then return false end
    local groupKey = container._msufA3ManagedGroupKey
    local nativeFilter, candidateFilters, candidateSignature = EffectiveLaneFilters(lane)
    local oldFilter = container._msufA3FilterString
    local oldCandidateSignature = container._msufA3CandidateFilterSignature
    local filterChanged = oldFilter ~= nativeFilter
    local candidatesChanged = oldCandidateSignature ~= candidateSignature
    if not filterChanged and not candidatesChanged then return false end

    -- A new exact-ID include gate is fail-closed on its own. Install it before
    -- changing a native filter that may broaden (for example RAID -> HELPFUL).
    -- When removing the include gate, narrow the native filter first so there
    -- is likewise no intermediate unrestricted HELPFUL refresh.
    local installCandidatesFirst = filterChanged and candidatesChanged
        and candidateFilters and candidateFilters.includeSpellIDs ~= nil
    if installCandidatesFirst then
        container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
        container._msufA3CandidateFilterSignature = candidateSignature
    end
    if filterChanged then
        container:SetAuraGroupFilterString(groupKey, nativeFilter)
        container._msufA3FilterString = nativeFilter
    end
    if candidatesChanged and not installCandidatesFirst then
        container:SetAuraGroupCandidateFilters(groupKey, candidateFilters)
        container._msufA3CandidateFilterSignature = candidateSignature
    end
    return true
end

local function UpdateAuraSlotEffectiveFilters(container, lane)
    if not (container and lane) then return false end
    local slotKey = GroupLaneSlotKey(lane)
    local filters = container._msufA3LaneSlotFilterStrings
    local candidates = container._msufA3LaneSlotCandidateSignatures
    local nativeFilter, candidateFilters, candidateSignature = EffectiveLaneFilters(lane)
    local oldFilter = filters[slotKey]
    local oldCandidateSignature = candidates[slotKey]
    local filterChanged = oldFilter ~= nativeFilter
    local candidatesChanged = oldCandidateSignature ~= candidateSignature
    if not filterChanged and not candidatesChanged then return false end
    local installCandidatesFirst = filterChanged and candidatesChanged
        and candidateFilters and candidateFilters.includeSpellIDs ~= nil
    if installCandidatesFirst then
        container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        candidates[slotKey] = candidateSignature
    end
    if filterChanged then
        container:SetAuraSlotFilterString(slotKey, nativeFilter)
        filters[slotKey] = nativeFilter
    end
    if candidatesChanged and not installCandidatesFirst then
        container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        candidates[slotKey] = candidateSignature
    end
    return true
end

local function UpdateGroupLaneSlot(container, lane)
    if not (container and lane) then return false end
    local slotKey = GroupLaneSlotKey(lane)
    local sorts = container._msufA3LaneSlotSortSignatures
    UpdateAuraSlotEffectiveFilters(container, lane)
    local sortSignature = AuraSortSignature(lane)
    if sorts[slotKey] ~= sortSignature then
        local sortMethod, sortDirection = AuraSortEnums(lane)
        container:SetAuraSlotSortMethod(slotKey, sortMethod, sortDirection)
        sorts[slotKey] = sortSignature
    end
    return true
end

local function UpdateGroupFlowLane(container, lane)
    if not (container and lane and container._msufA3ManagedGroupKey) then return false end
    local groupKey = container._msufA3ManagedGroupKey
    UpdateAuraGroupEffectiveFilters(container, lane)
    if container._msufA3MaxFrameCount ~= lane.max then
        container:SetAuraGroupMaxFrameCount(groupKey, lane.max)
        container._msufA3MaxFrameCount = lane.max
    end
    local sortSignature = AuraSortSignature(lane)
    if container._msufA3SortSignature ~= sortSignature then
        local sortMethod, sortDirection = AuraSortEnums(lane)
        container:SetAuraGroupSortMethod(groupKey, sortMethod, sortDirection)
        container._msufA3SortSignature = sortSignature
    end
    container.createdButtons = (container._msufA3FixedButtonCount or 0) + (lane.max or 0)
    return true
end

local function CreateManagedDispelSensor(container, sensor, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3NativeLane = sensor.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = sensor.unit
    container.createdButtons = sensor.max or 1
    container._msufA3SensorSlotFilterStrings = {}
    ConfigureNativeAuraContainer(container, sensor.unit)
    SyncDispelSensorGeometry(container, sensor, parentFrame)

    for i = 1, container.createdButtons do
        local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(i)
        container:AddAuraSlot(slotKey, sensor.nativeFilter, BuildManagedAuraSlotOptions(container, sensor, parentFrame, i, i))
        container._msufA3SensorSlotFilterStrings[slotKey] = sensor.nativeFilter
    end
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

--- Symbol sensors in ALL mode narrow each slot to one dispel type; the PTR 8
--- Purge sensor narrows its single helpful slot to isStealable=true. Returns
--- the signature so the update path can skip a redundant native call.
function DS.SlotCandidateFilters(sensor, sensorIndex)
    local slot = sensor and sensor.visual == "symbol" and sensor.slots and sensor.slots[sensorIndex]
    if not slot then
        return sensor and sensor.candidateFilters, sensor and sensor.candidateFilterSignature
    end
    return slot.candidateFilters, slot.candidateFilterSignature
end

local function AddDispelSensorSlots(container, sensors, parentFrame, firstButtonIndex)
    local buttonIndex = firstButtonIndex or 0
    local first = buttonIndex + 1
    local slots, bySelection = container._msufA3SensorButtonSlots, {}
    -- Compile the whole selection plan before AddAuraSlot: its initializer can
    -- run immediately and seals each visual. Only exact selection/identity
    -- matches share a slot; ALL symbols retain one selection per dispel type.
    for sourceIndex = 1, #sensors do
        local sensor = sensors[sourceIndex]
        for sensorIndex = 1, math_max(1, sensor.max or 1) do
            local _, candidateSignature = DS.SlotCandidateFilters(sensor, sensorIndex)
            local key = sensor.nativeFilter .. "\030" .. tostring(candidateSignature)
                .. "\030" .. tostring(sensor.identityCandidateMode)
            local slot = bySelection[key]
            if slot then
                slot.visuals = slot.visuals or { { sensor = slot.sensor, sensorIndex = slot.sensorIndex } }
                slot.visuals[#slot.visuals + 1] = { sensor = sensor, sensorIndex = sensorIndex }
            else
                buttonIndex = buttonIndex + 1
                slot = { sensor = sensor, sensorIndex = sensorIndex, sourceIndex = sourceIndex,
                    slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(sensorIndex) }
                slots[buttonIndex], bySelection[key] = slot, slot
            end
        end
    end
    local filters, candidates = {}, {}
    container._msufA3SensorSlotFilterStrings = filters
    container._msufA3SensorSlotCandidateSignatures = candidates
    for i = first, buttonIndex do
        local slot = slots[i]
        local sensor, slotKey = slot.sensor, slot.slotKey
        container:AddAuraSlot(slotKey, sensor.nativeFilter,
            BuildManagedAuraSlotOptions(container, sensor, parentFrame, i, slot.sensorIndex, slot.visuals))
        filters[slotKey] = sensor.nativeFilter
        local candidateFilters, candidateSignature = DS.SlotCandidateFilters(sensor, slot.sensorIndex)
        if candidateFilters then
            container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
        end
        candidates[slotKey] = candidateSignature
    end
    container._msufA3SensorButtonStart = first
    container._msufA3SensorButtonEnd = buttonIndex
    return buttonIndex
end

local function SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame, forceGeometry)
    if not (container and sensorRoot and sensorRoot.sensorRoot == true) then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceManagedAuraGeometry == true
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = sensorRoot
    container._msufA3ParentFrame = parentFrame
    local sig = sensorRoot._msufA3LayoutSignature
    if forceGeometry ~= true
        and sig ~= nil
        and container._msufA3GeomSig == sig
        and container._msufA3GeomParent == parentFrame
    then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    local root = container:GetParent()
    if root then container:SetAllPoints(root) end
    if parentFrame and container.SetFrameLevel then
        -- The container owns native assignment only. Keep it at the health
        -- base so each AuraButton's explicit effect level remains authoritative
        -- and is not inherited above text/status overlays.
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1)
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
    end
    -- AuraButton setup is callback-only on PTR 5. Layout changes are part of
    -- the structural signature and replace this container instead.
    if forceGeometry == true then container._msufA3ForceManagedAuraGeometry = nil end
    return true
end

local function CreateManagedDispelSensorRoot(container, sensorRoot, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3NativeLane = sensorRoot.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container._msufA3SensorButtonSlots = {}
    container._msufA3SensorSlotFilterStrings = {}
    container.unit = sensorRoot.unit
    container.createdButtons = sensorRoot.max or 1
    ConfigureNativeAuraContainer(container, sensorRoot.unit)
    SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame)

    local sensors = sensorRoot.sensors or {}
    local buttonIndex = AddDispelSensorSlots(container, sensors, parentFrame, 0)
    container.createdButtons = buttonIndex
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateDispelSensorRootSlots(container, sensorRoot)
    local slots = container and container._msufA3SensorButtonSlots
    local sensors = sensorRoot and sensorRoot.sensors
    if not (slots and type(sensors) == "table") then return false end
    local filters, candidates = container._msufA3SensorSlotFilterStrings, container._msufA3SensorSlotCandidateSignatures
    for i = container._msufA3SensorButtonStart, container._msufA3SensorButtonEnd do
        local slot = slots[i]
        local sensor = sensors[slot.sourceIndex]
        local slotKey = slot.slotKey
        slot.sensor = sensor
        if filters[slotKey] ~= sensor.nativeFilter then
            container:SetAuraSlotFilterString(slotKey, sensor.nativeFilter)
            filters[slotKey] = sensor.nativeFilter
        end
        local candidateFilters, candidateSignature = DS.SlotCandidateFilters(sensor, slot.sensorIndex)
        if candidates[slotKey] ~= candidateSignature then
            container:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
            candidates[slotKey] = candidateSignature
        end
    end
    return true
end

SyncDispelSensorGeometry = function(container, sensor, parentFrame, forceGeometry)
    if not (container and sensor) then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceManagedAuraGeometry == true
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = sensor
    container._msufA3ParentFrame = parentFrame
    local target = DispelSensorTarget(parentFrame, sensor)
    local sig = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    if forceGeometry ~= true
        and sig ~= nil
        and container._msufA3GeomSig == sig
        and container._msufA3GeomParent == parentFrame
        and container._msufA3GeomTarget == target
    then
        return true
    end
    container._msufA3GeomSig = sig
    container._msufA3GeomParent = parentFrame
    container._msufA3GeomTarget = target
    local root = container:GetParent()
    if root then container:SetAllPoints(root) end
    if parentFrame and container.SetFrameLevel then
        container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1)
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
    end
    -- Do not touch already initialized AuraButtons here; they may be forbidden
    -- while aura data is secret.
    if forceGeometry == true then container._msufA3ForceManagedAuraGeometry = nil end
    return true
end

local function CreateNativeDispelSensor(root, sensor, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3._RecordNativeAuraRuntimeError(AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown"))
        return nil
    end
    local container = CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedDispelSensor(container, sensor, parentFrame)
end

local function CreateNativeDispelSensorRoot(root, sensorRoot, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3._RecordNativeAuraRuntimeError(AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown"))
        return nil
    end
    local container = CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedDispelSensorRoot(container, sensorRoot, parentFrame)
end

local function SyncGroupSlotsGeometry(container, groupSlots, parentFrame, forceGeometry)
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    local ok = true
    local sensorRoot = groupSlots.sensorRoot
    local spellRoot = groupSlots.spellIndicatorRoot
    local flowLane = groupSlots.flowLane
    -- Fixed AuraSlot buttons receive their final geometry in initializeFrame.
    -- Without a flow group, retain the existing full-root container geometry.
    -- With a flow group, its fixed host must win after Spell Indicator sync
    -- temporarily restores the slot-only full-root geometry.
    if sensorRoot and not flowLane then
        ok = SyncDispelSensorRootGeometry(container, sensorRoot, parentFrame, forceGeometry) and ok
    end
    if spellRoot then
        -- A flowing lane in the same container owns its level; see SyncGeometry.
        ok = SpellIndicatorsRuntime.SyncGeometry(container, spellRoot, parentFrame, forceGeometry,
            flowLane ~= nil) and ok
    end
    if flowLane then
        if spellRoot then container._msufA3GeomSig = nil end
        ok = SyncContainerGeometry(container, flowLane, parentFrame, forceGeometry, true) and ok
    elseif not sensorRoot and not spellRoot
        and (forceGeometry == true or container._msufA3LaneSlotParent ~= parentFrame) then
        local root = container:GetParent()
        if root then container:SetAllPoints(root) end
        if container.SetFrameLevel then container:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 1) end
        SyncFrameStrata(container, ReadParentFrameStrata(parentFrame))
        container._msufA3LaneSlotParent = parentFrame
    end
    container._msufA3NativeLaneConfig = groupSlots
    container._msufA3ParentFrame = parentFrame
    if container._msufA3FixedButtonCount ~= nil then
        container.createdButtons = container._msufA3FixedButtonCount
            + (flowLane and flowLane.max or 0)
    end
    -- Last container-level write is done: re-assert the absolute level of every
    -- full-frame effect surface so a moved container cannot carry it out of its
    -- configured 0..30 slot.
    SpellIndicatorsRuntime.RefreshFrameEffects(parentFrame)
    return ok
end

local function CreateManagedGroupSlots(container, groupSlots, parentFrame)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3GroupSlotsRoot = true
    container._msufA3NativeLane = groupSlots.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container._msufA3SensorButtonSlots = {}
    container._msufA3LaneSlotFilterStrings = {}
    container._msufA3LaneSlotCandidateSignatures = {}
    container._msufA3LaneSlotSortSignatures = {}
    container._msufA3GroupRootKey = groupSlots.rootKey or "GroupSlots"
    container.unit = groupSlots.unit
    ConfigureNativeAuraContainer(container, groupSlots.unit)
    container:SetAlpha(1)
    local flowLane = groupSlots.flowLane
    if flowLane then
        local root = container._msufA3Root or container:GetParent()
        local host = CreateFrame("Frame", nil, root)
        if not host then return nil end
        container._msufA3LayoutHost = host
    end
    if not SyncGroupSlotsGeometry(container, groupSlots, parentFrame) then return nil end

    local buttonIndex = 0
    local spellRoot = groupSlots.spellIndicatorRoot
    if spellRoot then
        buttonIndex = SpellIndicatorsRuntime.AttachSlots(container, spellRoot)
    end
    local sensorRoot = groupSlots.sensorRoot
    local sensors = sensorRoot and sensorRoot.sensors or nil
    if sensors then
        buttonIndex = AddDispelSensorSlots(container, sensors, parentFrame, buttonIndex)
    end
    local slotLanes = groupSlots.slotLanes
    if slotLanes then
        for i = 1, #slotLanes do
            local lane = slotLanes[i]
            local slotKey = GroupLaneSlotKey(lane)
            local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
            buttonIndex = buttonIndex + 1
            container:AddAuraSlot(slotKey, nativeFilter,
                BuildGroupLaneSlotOptions(container, lane, parentFrame, buttonIndex))
            container._msufA3LaneSlotFilterStrings[slotKey] = nativeFilter
            container._msufA3LaneSlotCandidateSignatures[slotKey] = candidateFilterSignature
            container._msufA3LaneSlotSortSignatures[slotKey] = AuraSortSignature(lane)
        end
    end
    container._msufA3FixedButtonCount = buttonIndex
    if flowLane then
        local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(flowLane)
        container._msufA3ManagedAuraGroups = true
        container._msufA3ManagedGroupKey = ManagedAuraKey(flowLane)
        container:AddAuraGroup(container._msufA3ManagedGroupKey, nativeFilter,
            BuildManagedAuraGroupOptions(container, flowLane))
        container._msufA3FilterString = nativeFilter
        container._msufA3MaxFrameCount = flowLane.max
        container._msufA3CandidateFilterSignature = candidateFilterSignature
        container._msufA3SortSignature = AuraSortSignature(flowLane)
        if not ApplyManagedAuraGroupLayout(container, container._msufA3ManagedGroupKey, flowLane) then
            if container.Hide then container:Hide() end
            return nil
        end
        buttonIndex = buttonIndex + (flowLane.max or 0)
    end
    container.createdButtons = buttonIndex
    container._msufA3NativeLaneConfig = groupSlots
    if not RegisterNativeContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function HeaderGroupSlotsContainer(root, parentFrame)
    local container = parentFrame and parentFrame.AuraContainer
    if not container or container._msufA3HeaderContainerConsumed == true then return nil end
    if not ValidateNativeAuraContainerContract(container) then return nil end
    container._msufA3HeaderContainerConsumed = true
    container._msufA3Root = root
    return container
end

local function RememberGroupOwner(parentFrame, rootKey, container)
    if not (parentFrame and rootKey and container) then return end
    local owners = parentFrame._msufA3GroupOwners
    if not owners then
        owners = {}
        parentFrame._msufA3GroupOwners = owners
    end
    owners[rootKey] = container
end

local function CreateNativeGroupSlots(root, groupSlots, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3._RecordNativeAuraRuntimeError(AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown"))
        return nil
    end
    -- SecureGroupHeader births one container with each party/raid child. Adopt
    -- it once for the fixed-slot owner; structural replacements deliberately
    -- fall back to a fresh container because AuraSlot definitions are immutable.
    local container = groupSlots.rootKey == "GroupSlots" and HeaderGroupSlotsContainer(root, parentFrame)
        or CreateNativeAuraContainer(root)
    if not container then return nil end
    return CreateManagedGroupSlots(container, groupSlots, parentFrame)
end

-- World transitions are the only path that deliberately distrusts cached
-- desired geometry. Keep the dispatch here so every managed Auras3 container
-- gets one cache-bypassing repair without adding live GetPoint work to normal
-- UNIT_AURA updates.
A3._ManagedAuraContainerSupportsGeometryRepair = function(container)
    if not container then return false end
    if container._msufA3SpellIndicatorRoot == true then
        return true
    end
    return type(container._msufA3NativeLaneConfig) == "table"
end

A3._SyncManagedAuraContainerGeometry = function(container, forceGeometry)
    if not A3._ManagedAuraContainerSupportsGeometryRepair(container) then return false end
    forceGeometry = forceGeometry == true
        or container._msufA3ForceManagedAuraGeometry == true
        or container._msufA3ForceSpellIndicatorGeometry == true
    local lane = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local ok
    if container._msufA3GroupSlotsRoot == true then
        ok = SyncGroupSlotsGeometry(container, lane, parentFrame, forceGeometry)
    elseif container._msufA3SpellIndicatorRoot == true then
        -- This boolean sync API cannot hand a replacement back to callers
        -- holding the old container. Keep a native-button repair pending here;
        -- the direct identity pass recreates it after leaving the set iterator.
        ok = SpellIndicatorsRuntime.SyncGeometry(container, lane, parentFrame, forceGeometry)
    elseif lane and lane.sensorRoot == true then
        ok = SyncDispelSensorRootGeometry(container, lane, parentFrame, forceGeometry)
    elseif lane and lane.sensor == true then
        ok = SyncDispelSensorGeometry(container, lane, parentFrame, forceGeometry)
    else
        ok = SyncContainerGeometry(container, lane, parentFrame, forceGeometry)
    end
    if ok == true and forceGeometry == true then
        container._msufA3ForceManagedAuraGeometry = nil
        if container._msufA3SpellIndicatorRoot ~= true and container._msufA3GroupSlotsRoot ~= true then
            container._msufA3ForceSpellIndicatorGeometry = nil
        end
    end
    return ok == true
end

ConfigureContainer = function(container, lane, parentFrame)
    container._msufA3NativeLane = lane.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = lane.unit
    SyncContainerGeometry(container, lane, parentFrame)
end

A3._NativeContainerVisible = function(container)
    if not container then return false end
    -- Native AuraContainers are Frames: IsVisible already includes both their
    -- own shown state and inherited parent visibility. Fall back to IsShown
    -- only for lightweight test/compatibility objects without IsVisible.
    if type(container.IsVisible) == "function" then
        return container:IsVisible() == true
    end
    if type(container.IsShown) == "function" then
        return container:IsShown() == true
    end
    return true
end

return {
    ApplyManagedAuraGroupLayout = ApplyManagedAuraGroupLayout,
    CreateManagedNativeLane = CreateManagedNativeLane,
    CreateManagedNativeSlotLane = CreateManagedNativeSlotLane,
    CreateManagedPriorityNativeLane = CreateManagedPriorityNativeLane,
    CreateNativeAuraContainer = CreateNativeAuraContainer,
    CreateNativeDispelSensor = CreateNativeDispelSensor,
    CreateNativeDispelSensorRoot = CreateNativeDispelSensorRoot,
    CreateNativeGroupSlots = CreateNativeGroupSlots,
    ManagedAuraKey = ManagedAuraKey,
    RememberGroupOwner = RememberGroupOwner,
    SyncDispelSensorGeometry = SyncDispelSensorGeometry,
    SyncDispelSensorRootGeometry = SyncDispelSensorRootGeometry,
    SyncGroupSlotsGeometry = SyncGroupSlotsGeometry,
    UpdateAuraGroupEffectiveFilters = UpdateAuraGroupEffectiveFilters,
    UpdateAuraSlotEffectiveFilters = UpdateAuraSlotEffectiveFilters,
    UpdateDispelSensorRootSlots = UpdateDispelSensorRootSlots,
    UpdateGroupFlowLane = UpdateGroupFlowLane,
    UpdateGroupLaneSlot = UpdateGroupLaneSlot,
    -- Bootstrap-only cycle resolution; no lookup or forwarding wrapper is added to events.
    Bind = function(dependencies)
        RegisterNativeContainer = dependencies.RegisterNativeContainer
    end,
}
end
