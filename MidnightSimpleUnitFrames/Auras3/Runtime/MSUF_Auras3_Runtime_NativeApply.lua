-- Auras3 runtime: NativeApply.
-- Container retirement/reuse and configuration application. Keep ownership changes atomic and preserve native handoff, geometry and protected-click retirement contracts.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.NativeApply = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_max = math.max
local tostring = tostring
local type = type
local AURA_CONTAINER_ADDON = dependencies.Platform.AURA_CONTAINER_ADDON
local ApplyManagedAuraGroupLayout = dependencies.Containers.ApplyManagedAuraGroupLayout
local AuraSortEnums = dependencies.Sort.AuraSortEnums
local AuraSortSignature = dependencies.Sort.AuraSortSignature
local ConfigGen = dependencies.NativeContract.ConfigGen
local ConfigureNativeAuraContainer = dependencies.NativeContract.ConfigureNativeAuraContainer
local ConfigureStandaloneAuraDurationText = dependencies.DurationText.ConfigureStandaloneAuraDurationText
local CreateFrame = dependencies.Platform.CreateFrame
local CreateManagedNativeLane = dependencies.Containers.CreateManagedNativeLane
local CreateManagedNativeSlotLane = dependencies.Containers.CreateManagedNativeSlotLane
local CreateManagedPriorityNativeLane = dependencies.Containers.CreateManagedPriorityNativeLane
local CreateNativeAuraContainer = dependencies.Containers.CreateNativeAuraContainer
local CreateNativeDispelSensor = dependencies.Containers.CreateNativeDispelSensor
local CreateNativeDispelSensorRoot = dependencies.Containers.CreateNativeDispelSensorRoot
local CreateNativeGroupSlots = dependencies.Containers.CreateNativeGroupSlots
local EFFECT_ROOT_FIELDS = dependencies.OwnerConfig.EFFECT_ROOT_FIELDS
local EFFECT_ROOT_KEYS = dependencies.OwnerConfig.EFFECT_ROOT_KEYS
local EffectiveLaneFilters = dependencies.ConfigValues.EffectiveLaneFilters
local EnsureBlizzardAuraContainerLoaded = dependencies.Platform.EnsureBlizzardAuraContainerLoaded
local EnsureRoot = dependencies.NativeContract.EnsureRoot
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local LaneLayoutSignature = dependencies.Signatures.LaneLayoutSignature
local GetNativeOwnerPlan = dependencies.OwnerConfig.GetNativeOwnerPlan
local LaneStructuralSignature = dependencies.Signatures.LaneStructuralSignature
local LaneTrackingSignature = dependencies.Signatures.LaneTrackingSignature
local ManagedAuraKey = dependencies.Containers.ManagedAuraKey
local ManagedLaneFrameLevel = dependencies.CustomConfig.ManagedLaneFrameLevel
local NORMAL_LANE_ROOT_KEYS = dependencies.OwnerConfig.NORMAL_LANE_ROOT_KEYS
local PrepareAuraButton = dependencies.ButtonVisuals.PrepareAuraButton
local RememberGroupOwner = dependencies.Containers.RememberGroupOwner
local ResolveFrameStrata = dependencies.Platform.ResolveFrameStrata
local ResolveLaneParentFrame = dependencies.CustomConfig.ResolveLaneParentFrame
local RootAppliedConfigIsCurrent = dependencies.NativeContract.RootAppliedConfigIsCurrent
local SensorLayoutSignature = dependencies.Signatures.SensorLayoutSignature
local SensorStructuralSignature = dependencies.Signatures.SensorStructuralSignature
local SetAssistAlpha = dependencies.Identity.SetAssistAlpha
local Shape = dependencies.Appearance.Shape
local SyncContainerGeometry = dependencies.ButtonVisuals.SyncContainerGeometry
local SyncDispelSensorGeometry = dependencies.Containers.SyncDispelSensorGeometry
local SyncDispelSensorRootGeometry = dependencies.Containers.SyncDispelSensorRootGeometry
local SyncFrameStrata = dependencies.Platform.SyncFrameStrata
local SyncGroupSlotsGeometry = dependencies.Containers.SyncGroupSlotsGeometry
local UpdateAuraGroupEffectiveFilters = dependencies.Containers.UpdateAuraGroupEffectiveFilters
local UpdateDispelSensorRootSlots = dependencies.Containers.UpdateDispelSensorRootSlots
local UpdateGroupFlowLane = dependencies.Containers.UpdateGroupFlowLane
local UpdateGroupLaneSlot = dependencies.Containers.UpdateGroupLaneSlot
local UsesStandaloneAuraSlot = dependencies.Signatures.UsesStandaloneAuraSlot
local ValidateNativeAuraButtonContract = dependencies.NativeContract.ValidateNativeAuraButtonContract
local VisualGen = dependencies.NativeContract.VisualGen

local ApplyLane, EnsureNativeAuraRefreshDriver, RecreateGroupSlots, RefreshAppliedNativeRoot, RegisterNativeContainer

RegisterNativeContainer = function(container, forceRefresh)
    if not container then return false end
    if forceRefresh ~= true and container._msufA3NativeRegistered == true then
        -- Reuse paths apply geometry after rebinding, which restores the lane's
        -- configured alpha. Re-seed only registered exact-ID Unit owners here
        -- so that cold layout/config work cannot expose the wrong polarity.
        if container._msufA3DirectIdentityUnitGated == true then
            A3._SeedUnitAuraIdentityOwner(container, container.unit)
        elseif type(container.IsEnabled) == "function" and container:IsEnabled() == false
            and type(container.SetEnabled) == "function"
            and not IsLiveGroupAuraFrame(container._msufA3ParentFrame) then
            -- A Unit owner that lost its identity polarity keeps the disabled
            -- flag written by its last gate pass; ungated owners stay enabled.
            container:SetEnabled(true)
        end
        return true
    end
    if not A3._NativeContainerVisible(container) then
        container._msufA3NativeRegistrationPending = true
        return true
    end

    -- Enable the container so Blizzard registers it for UNIT_AURA on this unit
    -- (ShouldRegisterForEvents = IsVisible() and IsEnabled()). Without this the
    -- container never self-updates: a hidden->shown transition reparses via
    -- OnShow, but a same-token target swap or an aura expiring/refreshing does
    -- not, so content goes stale. Enabling routes all steady-state updates
    -- through the container's cheap incremental delta path (added/updated/
    -- removed) instead of an MSUF forced reparse. SetEnabled is a secure
    -- delegate (safe to call directly) and is idempotent.
    container:SetEnabled(true)
    -- The identity seed runs inside registration and may immediately disable an
    -- ineligible exact-ID owner. Mark lifecycle ownership first so that initial
    -- seed uses the same SetEnabled gate as every later identity refresh.
    container._msufA3NativeRegistered = true
    A3._RegisterDirectIdentityRefreshContainer(container)
    container._msufA3NativeRegistrationPending = nil
    return true
end

A3._UnregisterNativeContainer = function(container)
    if not container then return true end
    A3._UnregisterDirectIdentityRefreshContainer(container)
    container:SetEnabled(false)
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    return true
end

A3._RebindNativeContainerUnit = function(container, unit)
    if not (container and type(unit) == "string" and unit ~= "") then return false end
    local changed = container.unit ~= unit or (type(container.GetUnit) == "function" and container:GetUnit() ~= unit)
    container.unit = unit
    if changed and type(container.SetUnit) == "function" then
        container:SetUnit(unit)
    end
    A3._RegisterDirectIdentityRefreshContainer(container)
    return changed
end

A3._CreateNativeLane = function(root, lane, parentFrame)
    if not EnsureBlizzardAuraContainerLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = AURA_CONTAINER_ADDON .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end

    -- Blizzard sizes AuraContainers to their current visible contents. Keep the
    -- user-selected MSUF anchor on a fixed addon-owned host so that native
    -- layout can remain completely unwrapped without shifting right/bottom
    -- anchored lanes as aura counts change.
    parentFrame = ResolveLaneParentFrame(parentFrame, lane)
    local host = CreateFrame("Frame", nil,
        lane and lane.portraitOverlay == true and (parentFrame._msufHealthVisualRoot or parentFrame) or root)
    if not host then return nil end
    -- Birth-order levels: the host receives its final strata/level BEFORE the
    -- container (and later its batch-created AuraButtons) are born as its
    -- children. Children spawn at parent level + 1, so the whole chain starts
    -- at the correct absolute level without ever needing a SetFrameLevel call
    -- on the sealed intrinsic objects. Layer/strata changes recreate the lane
    -- (tracking signature), which re-runs this birth ordering.
    if parentFrame then
        local hostStrata = ResolveFrameStrata(parentFrame, lane and lane.strata)
        if hostStrata then SyncFrameStrata(host, hostStrata) end
        if host.SetFrameLevel and parentFrame.GetFrameLevel then
            host:SetFrameLevel(ManagedLaneFrameLevel(parentFrame, lane))
        end
    end
    local container = CreateNativeAuraContainer(root, host)
    if not container then
        if host.Hide then host:Hide() end
        return nil
    end
    container._msufA3LayoutHost = host
    container._msufA3HostParented = true
    if UsesStandaloneAuraSlot(lane) then
        return CreateManagedNativeSlotLane(container, lane, parentFrame)
    end
    if lane and lane.customPriority == true then
        return CreateManagedPriorityNativeLane(container, lane, parentFrame)
    end
    return CreateManagedNativeLane(container, lane, parentFrame)
end

A3._HideLane = function(lane)
    if lane then
        A3._UnregisterNativeContainer(lane)
        lane:Hide()
        if lane._msufA3LayoutHost and lane._msufA3LayoutHost.Hide then
            lane._msufA3LayoutHost:Hide()
        end
        local config = lane._msufA3NativeLaneConfig
        local holder = config and config.portraitOverlay == true and lane._msufA3ParentFrame
        if config and config.portraitPositionWhenDisabled == true then
            local frame = holder and (holder._msufUnitFrameOwner or (holder.GetParent and holder:GetParent()))
            local element = UF and UF.elements and UF.elements.Portrait
            if frame and element and type(element.ReleasePositionAnchor) == "function" then
                element.ReleasePositionAnchor(frame)
            end
        end
    end
end

A3._NormalLaneForRootKey = function(lanes, rootKey)
    if type(lanes) ~= "table" or rootKey == nil then return nil end
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.rootKey == rootKey then return lane end
    end
end

local function GroupSlotsOwnsLane(groupSlots, lane)
    if not (groupSlots and lane) then return false end
    local owned = groupSlots.allOwnedLaneKeys or groupSlots.ownedLaneKeys
    return owned and owned[lane.rootKey] == true or false
end

A3._HideNormalLaneContainers = function(root, lanes, groupSlots)
    if not root then return end
    for i = 1, #NORMAL_LANE_ROOT_KEYS do
        local key = NORMAL_LANE_ROOT_KEYS[i]
        local lane = A3._NormalLaneForRootKey(lanes, key)
        if GroupSlotsOwnsLane(groupSlots, lane) or not (lane and lane.enabled == true) then
            A3._HideLane(root[key])
            root[key] = nil
        end
    end
end

A3._ApplyNormalLaneContainers = function(root, lanes, parentFrame, forceRecreate, groupSlots)
    A3._HideNormalLaneContainers(root, lanes, groupSlots)
    if type(lanes) ~= "table" then return true, false end
    local ok, any = true, false
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            any = true
            if not ApplyLane(root, lane, parentFrame, forceRecreate) then ok = false end
        end
    end
    return ok, any
end

ApplyLane = function(root, lane, parentFrame, forceRecreate)
    if not (root and lane and lane.enabled) then return nil end
    local key = lane.rootKey
    local trackingSignature = lane._msufA3TrackingSignature or LaneTrackingSignature(lane)
    local structuralSignature = lane._msufA3StructuralSignature or LaneStructuralSignature(lane)
    local layoutSignature = lane._msufA3LayoutSignature or LaneLayoutSignature(lane)
    local nativeFilter, _, candidateFilterSignature = EffectiveLaneFilters(lane)
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, lane.unit)
        if current._msufA3StandaloneAuraSlot == true then
            UpdateGroupLaneSlot(current, lane)
            SyncContainerGeometry(current, lane, parentFrame)
            current:Show()
            if not RegisterNativeContainer(current) then return nil end
            current._msufA3TrackingSignature = trackingSignature
            current._msufA3StructuralSignature = structuralSignature
            current._msufA3LayoutSignature = layoutSignature
            current._msufA3MaxFrameCount = 1
            return current
        end
        if current._msufA3PriorityAuraGroups == true then
            SyncContainerGeometry(current, lane, parentFrame)
            current:Show()
            if not RegisterNativeContainer(current) then return nil end
            current._msufA3TrackingSignature = trackingSignature
            current._msufA3StructuralSignature = structuralSignature
            current._msufA3LayoutSignature = layoutSignature
            return current
        end
        local layoutChanged = current._msufA3LayoutSignature ~= layoutSignature
        UpdateAuraGroupEffectiveFilters(current, lane)
        if current._msufA3MaxFrameCount ~= lane.max then
            current:SetAuraGroupMaxFrameCount(current._msufA3ManagedGroupKey, lane.max)
            current._msufA3MaxFrameCount = lane.max
        end
        local sortSignature = AuraSortSignature(lane)
        if current._msufA3SortSignature ~= sortSignature then
            local sortMethod, sortDirection = AuraSortEnums(lane)
            current:SetAuraGroupSortMethod(current._msufA3ManagedGroupKey, sortMethod, sortDirection)
            current._msufA3SortSignature = sortSignature
        end
        if layoutChanged then
            ApplyManagedAuraGroupLayout(current, current._msufA3ManagedGroupKey, lane)
        end
        SyncContainerGeometry(current, lane, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = A3._CreateNativeLane(root, lane, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        current._msufA3MaxFrameCount = lane.max
        current._msufA3FilterString = nativeFilter
        current._msufA3CandidateFilterSignature = candidateFilterSignature
        root[key] = current
    end
    return current
end

local function ApplyDispelSensor(root, sensor, parentFrame, forceRecreate)
    if not (root and sensor and sensor.enabled) then return nil end
    local key = sensor.rootKey
    local structuralSignature = sensor._msufA3StructuralSignature or SensorStructuralSignature(sensor)
    local layoutSignature = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, sensor.unit)
        local filters = current._msufA3SensorSlotFilterStrings or {}
        current._msufA3SensorSlotFilterStrings = filters
        for i = 1, math_max(1, sensor.max or 1) do
            local slotKey = ManagedAuraKey(sensor) .. "_" .. tostring(i)
            if filters[slotKey] ~= sensor.nativeFilter then
                current:SetAuraSlotFilterString(slotKey, sensor.nativeFilter)
                filters[slotKey] = sensor.nativeFilter
            end
        end
        SyncDispelSensorGeometry(current, sensor, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = CreateNativeDispelSensor(root, sensor, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        sensor._msufA3StructuralSignature = structuralSignature
        sensor._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function ApplyDispelSensorRoot(root, sensorRoot, parentFrame, forceRecreate)
    if not (root and sensorRoot and sensorRoot.enabled == true and sensorRoot.sensorRoot == true) then return nil end
    local key = sensorRoot.rootKey or "DispelSensor"
    local structuralSignature = sensorRoot._msufA3StructuralSignature
    local layoutSignature = sensorRoot._msufA3LayoutSignature
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, sensorRoot.unit)
        UpdateDispelSensorRootSlots(current, sensorRoot)
        SyncDispelSensorRootGeometry(current, sensorRoot, parentFrame)
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    A3._HideLane(current)
    root[key] = nil
    current = CreateNativeDispelSensorRoot(root, sensorRoot, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

local function HideGroupSlots(root, parentFrame, groupSlots, rootKeyOverride)
    local rootKey = rootKeyOverride or (groupSlots and groupSlots.rootKey) or "GroupSlots"
    local current = root[rootKey]
    if current and current._msufA3SpellIndicatorRoot == true then
        local currentConfig = current._msufA3NativeLaneConfig
        SpellIndicatorsRuntime.HideRootMissing(
            parentFrame, currentConfig and currentConfig.spellIndicatorRoot, current)
        SpellIndicatorsRuntime.ReleaseContainerEffects(current, parentFrame)
    end
    A3._HideLane(current)
    root[rootKey] = nil
end

local function ApplyGroupSlots(root, groupSlots, parentFrame, forceRecreate)
    if not (root and groupSlots) then return nil end
    local rootKey = groupSlots.rootKey or "GroupSlots"
    local structuralSignature = groupSlots._msufA3StructuralSignature
    local current = root[rootKey]
    local parked = parentFrame and parentFrame._msufA3GroupOwners
        and parentFrame._msufA3GroupOwners[rootKey]
    if not current and parked and parked._msufA3StructuralSignature == structuralSignature then
        current = parked
        current._msufA3Root = root
        root[rootKey] = current
    end
    local headerContainer = parentFrame and parentFrame.AuraContainer
    if rootKey == "GroupSlots"
        and not current
        and headerContainer
        and headerContainer._msufA3GroupSlotsRoot == true
        and headerContainer._msufA3StructuralSignature == structuralSignature then
        current = headerContainer
        current._msufA3Root = root
        root[rootKey] = current
    end
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        A3._RebindNativeContainerUnit(current, groupSlots.unit)
        local spellRoot = groupSlots.spellIndicatorRoot
        if spellRoot then SpellIndicatorsRuntime.UpdateSlots(current, spellRoot) end
        local sensorRoot = groupSlots.sensorRoot
        if sensorRoot then
            UpdateDispelSensorRootSlots(current, sensorRoot)
        end
        local slotLanes = groupSlots.slotLanes
        if slotLanes then
            for i = 1, #slotLanes do UpdateGroupLaneSlot(current, slotLanes[i]) end
        end
        if groupSlots.flowLane then UpdateGroupFlowLane(current, groupSlots.flowLane) end
        SyncGroupSlotsGeometry(current, groupSlots, parentFrame)
        if current._msufA3LayoutHost then current._msufA3LayoutHost:Show() end
        current:Show()
        if not RegisterNativeContainer(current) then return nil end
        RememberGroupOwner(parentFrame, rootKey, current)
        current._msufA3StructuralSignature = structuralSignature
        return current
    end
    HideGroupSlots(root, parentFrame, groupSlots)
    current = CreateNativeGroupSlots(root, groupSlots, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        root[rootKey] = current
        RememberGroupOwner(parentFrame, rootKey, current)
    end
    return current
end

RecreateGroupSlots = function(container)
    if not (container and container._msufA3GroupSlotsRoot == true) then return nil end
    local groupSlots = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local root = container._msufA3Root or container:GetParent()
    if not (root and groupSlots and parentFrame) then return nil end
    local replacement = ApplyGroupSlots(root, groupSlots, parentFrame, true)
    if replacement then
        replacement._msufA3ForceManagedAuraGeometry = nil
        replacement._msufA3ForceSpellIndicatorGeometry = nil
    end
    return replacement
end

A3._ApplyGroupSlots = ApplyGroupSlots



local function RefreshNativeContainer(container, forceRefresh, lane, parentFrame)
    lane = lane or (container and container._msufA3NativeLaneConfig)
    if container then
        container._msufA3NativeLaneConfig = lane or container._msufA3NativeLaneConfig
        container._msufA3ParentFrame = parentFrame or container._msufA3ParentFrame
    end
    local forceGeometry = container and (container._msufA3ForceManagedAuraGeometry == true
        or container._msufA3ForceSpellIndicatorGeometry == true)
    if not A3._SyncManagedAuraContainerGeometry(container, forceGeometry) then return false end
    if not RegisterNativeContainer(container, forceRefresh == true) then return false end
    if not A3._NativeContainerVisible(container) then return true end
    if forceRefresh == true and type(container.UpdateAllAuras) == "function" then
        container:UpdateAllAuras()
    end
    return true
end

RefreshAppliedNativeRoot = function(root, forceRefresh)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    local cfg = root._msufA3Config
    local lanes = cfg and cfg.lanes or nil
    if not lanes then return false end

    local ok, any = true, false
    local parentFrame = root._msufA3ParentFrame or root:GetParent()
    local group = cfg.group == true
    local groupSlots = GetNativeOwnerPlan(cfg)
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes[order[i]]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            any = true
            ok = RefreshNativeContainer(root[lane.rootKey], forceRefresh, lane, parentFrame) and ok
        end
    end
    for i = 1, #groupSlots.keys do
        local key = groupSlots.keys[i]
        local owner = groupSlots.owners[key]
        if owner then
            any = true
            ok = RefreshNativeContainer(root[key], forceRefresh, owner, parentFrame) and ok
        end
    end
    for i = group and 4 or 1, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        if SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot) then
            any = true
            ok = RefreshNativeContainer(root[spellIndicatorRoot.rootKey], forceRefresh, spellIndicatorRoot, parentFrame) and ok
        end
    end
    if ok and any then A3.nativeAuraRuntimeError = nil end
    return ok and any
end

A3._RefreshAppliedNativeAuras = function(frame, forceRefresh)
    return RefreshAppliedNativeRoot(frame and frame.Auras, forceRefresh)
end

EnsureNativeAuraRefreshDriver = function()
    if A3._nativeAuraRefreshDriver then return A3._nativeAuraRefreshDriver end
    A3._nativeAuraRefreshDriver = true
    return true
end

local MANAGED_ROOT_KEYS = {
    "Buffs", "TrackedBuffs", "Debuffs", "Externals", "CustomAuras1",
    "CustomAuras2", "CustomAuras3", "CustomAuras4", "DefensivePortrait", "TargetDotPortrait",
    "GroupSlots", "GroupAuraFlow", "GroupAuraAssist", "GroupAuraHostile", "DispelSensor",
    "DispelSensorNeutral", "DispelSensorHostile", "DispelBorderSensor", "DispelOverlaySensor", "DispelCornerSensor",
    "SpellIndicators", "SpellIndicatorsAssist", "SpellIndicatorsHostile", "LaneEffects", "LaneEffectsAssist",
    "LaneEffectsHostile", "TargetDotEffects", "TargetDotEffectsAssist", "TargetDotEffectsHostile",
}

local function HideState(frame)
    local root = frame and frame.Auras
    if not (root and root._msufA3NativeRoot) then return end
    for i = 1, #MANAGED_ROOT_KEYS do
        local key = MANAGED_ROOT_KEYS[i]
        A3._HideLane(root[key])
    end
    SpellIndicatorsRuntime.HideAll(frame)
    root._msufA3Config = nil
    root._msufA3Applied = nil
    root._msufA3ConfigGen = nil
    root._msufA3VisualGen = nil
    root._msufA3AppliedUnit = nil
    root._msufA3FrameSpec = nil
    root:Hide()
    local unit = frame and frame.MSUFUnitKey
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit and A3._unitFrameOwners and A3._unitFrameOwners[unit] == frame then
        A3._unitFrameOwners[unit] = nil
    end
    for i = 1, #MANAGED_ROOT_KEYS do root[MANAGED_ROOT_KEYS[i]] = nil end
    frame._msufA3UnitAuraOwner = nil
end

local function ApplyConfig(frame, cfg, reason)
    if not (frame and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    local root = EnsureRoot(frame)
    if not root then return false end
    A3._SeedGroupAuraPresenceGate(frame, cfg.unit, false)
    if RootAppliedConfigIsCurrent(root, frame, cfg, reason) then
        RefreshAppliedNativeRoot(root, false)
        A3._SeedGroupAuraAssistGate(frame)
        A3._SeedGroupAuraPresenceGate(frame, cfg.unit, true)
        return true
    end
    root.unit = cfg.unit or frame.MSUFUnitKey
    root:SetAllPoints(frame)
    root:Show()
    local lanes = cfg.lanes or {}
    local group = cfg.group == true
    local groupSlots = GetNativeOwnerPlan(cfg)
    local forceRecreate = false
    local ok = true
    local lanesOk = true
    lanesOk = A3._ApplyNormalLaneContainers(root, lanes, frame, forceRecreate, groupSlots)
    ok = lanesOk and ok
    local firstEffectRoot = group and 4 or 1
    local anyEffectRoot = false
    for i = 1, #groupSlots.keys do
        local key = groupSlots.keys[i]
        local owner = groupSlots.owners[key]
        if owner then
            anyEffectRoot = anyEffectRoot or owner.spellIndicatorRoot ~= nil
            local apply = owner.sensorRoot == true and ApplyDispelSensorRoot or ApplyGroupSlots
            if not apply(root, owner, frame, forceRecreate) then ok = false end
        else
            HideGroupSlots(root, frame, nil, key)
        end
    end
    for i = firstEffectRoot, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        local active = SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot)
        local key = active and spellIndicatorRoot.rootKey or EFFECT_ROOT_KEYS[i]
        if active then
            anyEffectRoot = true
            if not SpellIndicatorsRuntime.Apply(root, spellIndicatorRoot, frame, forceRecreate) then ok = false end
        else
            -- Reminder placeholders and click-to-cast buttons live on the
            -- UnitFrame, not inside the container, so hiding the lane alone
            -- would leave a dimmed icon and an invisible click target.
            if SpellIndicatorsRuntime.RetireRoot(frame, key, root[key]) == true
                and type(A3._QueueDeferredAuraRuntime) == "function"
            then
                A3._QueueDeferredAuraRuntime(cfg.unit, "AURAS3_REMINDER_CLICK_CAST")
            end
            A3._HideLane(root[key])
            root[key] = nil
        end
    end
    if not anyEffectRoot and SpellIndicatorsRuntime.HideAll(frame) == true
        and type(A3._QueueDeferredAuraRuntime) == "function"
    then
        -- Click-to-cast buttons are protected; combat defers their retirement.
        A3._QueueDeferredAuraRuntime(cfg.unit, "AURAS3_REMINDER_CLICK_CAST")
    end
    A3._HideLane(root.DispelBorderSensor)
    A3._HideLane(root.DispelOverlaySensor)
    A3._HideLane(root.DispelCornerSensor)
    root._msufA3Config = cfg
    root._msufA3Applied = ok == true
    root._msufA3ConfigGen = ConfigGen(cfg)
    root._msufA3VisualGen = VisualGen(cfg)
    root._msufA3AppliedUnit = cfg.unit or frame.MSUFUnitKey
    root._msufA3FrameSpec = frame.MSUFSpec
    root.needFullUpdate = nil
    root:Show()
    A3._SeedGroupAuraAssistGate(frame)
    A3._SeedGroupAuraPresenceGate(frame, cfg.unit, true)
    return ok == true
end

local function RootCanReuseContainersForConfig(root, cfg)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true and cfg and cfg.enabled == true) then
        return false
    end
    local lanes = cfg.lanes or {}
    local group = cfg.group == true
    local groupSlots = GetNativeOwnerPlan(cfg)
    for i = 1, #NORMAL_LANE_ROOT_KEYS do
        local key = NORMAL_LANE_ROOT_KEYS[i]
        local lane = A3._NormalLaneForRootKey(lanes, key)
        local current = root[key]
        if lane and lane.enabled == true and not GroupSlotsOwnsLane(groupSlots, lane) then
            if not (current and current._msufA3StructuralSignature == (lane._msufA3StructuralSignature or LaneStructuralSignature(lane))) then
                return false
            end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
    end
    for i = 1, #groupSlots.keys do
        local key = groupSlots.keys[i]
        local owner, current = groupSlots.owners[key], root[key]
        if owner then
            if not (current and current._msufA3StructuralSignature == owner._msufA3StructuralSignature) then return false end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
    end
    for i = group and 4 or 1, #EFFECT_ROOT_FIELDS do
        local spellIndicatorRoot = cfg[EFFECT_ROOT_FIELDS[i]]
        local active = SpellIndicatorsRuntime.IsRoot(spellIndicatorRoot)
        local key = active and spellIndicatorRoot.rootKey or EFFECT_ROOT_KEYS[i]
        local current = root[key]
        if active then
            if not (current and current._msufA3StructuralSignature == spellIndicatorRoot._msufA3StructuralSignature) then return false end
        elseif current and current.IsShown and current:IsShown() == true then
            return false
        end
    end
    return true
end

local function CreateClassPowerAuraSensor(parent, key, spellIDs, initializeFrame)
    if not (parent and type(spellIDs) == "table" and type(initializeFrame) == "function") then return nil end
    if not EnsureBlizzardAuraContainerLoaded() then return nil end

    local container = CreateNativeAuraContainer(parent)
    if not container then return nil end
    -- This standalone slot receives its geometry from a caller-owned
    -- initializeFrame callback and deliberately has no managed lane descriptor.
    -- The shared identity registry may therefore reparse its candidate filters
    -- on UNIT_FACTION/player UNIT_FLAGS, while geometry ownership remains with
    -- the caller instead of the generic world/zone repair path.
    container.unit = "player"
    ConfigureNativeAuraContainer(container, "player")
    container:AddAuraSlot(tostring(key or "msuf_classpower"), "HELPFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = spellIDs },
        initializeFrame = initializeFrame,
    })
    if not RegisterNativeContainer(container) then
        container:Hide()
        return nil
    end
    container:Show()
    return container
end

return {
    ApplyConfig = ApplyConfig,
    ApplyLane = ApplyLane,
    CreateClassPowerAuraSensor = CreateClassPowerAuraSensor,
    EnsureNativeAuraRefreshDriver = EnsureNativeAuraRefreshDriver,
    HideState = HideState,
    RecreateGroupSlots = RecreateGroupSlots,
    RefreshAppliedNativeRoot = RefreshAppliedNativeRoot,
    RegisterNativeContainer = RegisterNativeContainer,
    RootCanReuseContainersForConfig = RootCanReuseContainersForConfig,
    Initialize = function()
        SpellIndicatorsRuntime.Install({
            addonName = AURA_CONTAINER_ADDON,
            EnsureLoaded = EnsureBlizzardAuraContainerLoaded,
            CreateContainer = CreateNativeAuraContainer,
            ConfigureContainer = ConfigureNativeAuraContainer,
            RegisterContainer = RegisterNativeContainer,
            RebindUnit = A3._RebindNativeContainerUnit,
            IsVisible = A3._NativeContainerVisible,
            HideContainer = A3._HideLane,
            RecreateGroupSlots = RecreateGroupSlots,
            SetAssistAlpha = SetAssistAlpha,
            ValidateAuraButton = ValidateNativeAuraButtonContract,
            PrepareAuraButton = PrepareAuraButton,
            ConfigureStandaloneAuraDurationText = ConfigureStandaloneAuraDurationText,
            -- Buff Reminder placeholders reuse the shared aura icon shape module so
            -- a masked slot cannot leave uncovered placeholder corners.
            IconShape = Shape,
        })
    end,
}
end
