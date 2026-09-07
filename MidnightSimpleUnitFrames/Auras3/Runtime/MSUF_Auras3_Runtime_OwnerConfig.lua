-- Auras3 runtime: OwnerConfig.
-- Compile independent neutral, friendly and enemy owner partitions. A container-level gate covers all its slots, so different policies cannot share an owner.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.OwnerConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_max = math.max
local pairs = pairs
local table_concat = table.concat
local tostring = tostring
local type = type
local SensorLayoutSignature = dependencies.Signatures.SensorLayoutSignature
local SensorStructuralSignature = dependencies.Signatures.SensorStructuralSignature

local DISPEL_SENSOR_ORDER = { "dispelBorder", "purgeBorder", "dispelOverlay", "dispelCorner", "dispelSymbol" }
A3._normalAuraLaneOrder = {
    "buff", "trackedBuff", "debuff", "external",
    "custom1", "custom2", "custom3", "custom4", "defensivePortrait", "targetDotPortrait",
}
local NORMAL_LANE_ROOT_KEYS = {
    "Buffs", "TrackedBuffs", "Debuffs", "Externals",
    "CustomAuras1", "CustomAuras2", "CustomAuras3", "CustomAuras4", "DefensivePortrait", "TargetDotPortrait",
}
local EFFECT_ROOT_FIELDS = {
    "spellIndicators", "spellIndicatorsAssist", "spellIndicatorsHostile",
    "laneEffects", "laneEffectsAssist", "laneEffectsHostile",
    "targetDotEffects", "targetDotEffectsAssist", "targetDotEffectsHostile",
}
local EFFECT_ROOT_KEYS = {
    "SpellIndicators", "SpellIndicatorsAssist", "SpellIndicatorsHostile",
    "LaneEffects", "LaneEffectsAssist", "LaneEffectsHostile",
    "TargetDotEffects", "TargetDotEffectsAssist", "TargetDotEffectsHostile",
}
local UNIT_OWNER_KEYS = { "DispelSensor", "DispelSensorNeutral", "DispelSensorHostile" }
local GROUP_OWNER_KEYS = { "GroupSlots", "GroupAuraAssist", "GroupAuraHostile", "GroupAuraFlow" }

-- One native owner per identity polarity: the container is the alpha sink of
-- the Unit identity gate, so assist-gated cleanse visuals and the ungated
-- "Any dispel type" / Purge / "cast by me" sensors can never share one.
-- Group sensors use the existing neutral/assist/hostile owner partitions.
local function BuildDispelSensorRootConfig(sensors, identityCandidateMode, rootKey, preview)
    if type(sensors) ~= "table" then return nil end
    local list, structuralParts, layoutParts, unit, maxCount, layer
    for i = 1, #DISPEL_SENSOR_ORDER do
        local sensor = sensors[DISPEL_SENSOR_ORDER[i]]
        if sensor and sensor.enabled == true and (preview or sensor.identityCandidateMode == identityCandidateMode) then
            if not list then
                list, structuralParts, layoutParts = {}, {}, {}
                unit = sensor.unit
                maxCount = 0
                layer = 0
            end
            list[#list + 1] = sensor
            structuralParts[#structuralParts + 1] = sensor._msufA3StructuralSignature or SensorStructuralSignature(sensor)
            layoutParts[#layoutParts + 1] = sensor._msufA3LayoutSignature or SensorLayoutSignature(sensor)
            maxCount = maxCount + math_max(1, sensor.max or 1)
            layer = math_max(layer, sensor.layer or 0)
        end
    end
    if not list then return nil end
    return {
        sensor = true,
        sensorRoot = true,
        kind = "dispelSensors",
        rootKey = rootKey or "DispelSensor",
        unit = unit,
        enabled = true,
        sensors = list,
        max = maxCount,
        layer = layer,
        identityCandidateMode = identityCandidateMode,
        _msufA3StructuralSignature = "identity:" .. tostring(identityCandidateMode or "neutral")
            .. "\029" .. table_concat(structuralParts, "\029"),
        _msufA3LayoutSignature = table_concat(layoutParts, "\029"),
    }
end

local function GetDispelSensorRootConfig(cfg)
    if not cfg then return nil end
    local cached = cfg.sensorRoot
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    -- Group owners compile neutral sensors; Unit Frames compile their friendly
    -- cleanse visuals as the assist-polarity owner at the historical root key.
    local identityCandidateMode
    if cfg.group ~= true then identityCandidateMode = "assist" end
    cached = BuildDispelSensorRootConfig(cfg.sensors, identityCandidateMode, "DispelSensor",
        cfg.group == true and cfg.groupAssistGate ~= true)
    cfg.sensorRoot = cached or false
    return cached
end

-- Keep neutral and enemy-only sensors separate from friendly cleansing and
-- from each other: one container's identity alpha/enable gate covers all slots.
local function GetUnitDispelSensorRootConfig(cfg, identityCandidateMode)
    if not cfg or cfg.group == true then return nil end
    local cacheKey = identityCandidateMode == "hostile" and "hostileSensorRoot" or "neutralSensorRoot"
    local rootKey = identityCandidateMode == "hostile" and "DispelSensorHostile" or "DispelSensorNeutral"
    local cached = cfg[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    cached = BuildDispelSensorRootConfig(cfg.sensors, identityCandidateMode, rootKey)
    cfg[cacheKey] = cached or false
    return cached
end
local function BuildGroupAuraOwner(cfg, assistMode, includeFixed, rootKey, spellRootOverride)
    local sensorRoot = assistMode ~= nil and BuildDispelSensorRootConfig(cfg.sensors, assistMode)
        or (includeFixed and assistMode == nil and GetDispelSensorRootConfig(cfg)) or nil
    local spellRoot = spellRootOverride
    if spellRoot == nil and includeFixed and cfg.groupAssistGate ~= true then
        spellRoot = SpellIndicatorsRuntime.RootConfig(cfg)
    end
    local slotLanes, flowLane, ownedLaneKeys, signatureParts
    local lanes = cfg.lanes
    local order = A3._normalAuraLaneOrder
    for i = 1, #order do
        local lane = lanes and lanes[order[i]]
        local laneAssistMode = cfg.groupAssistGate == true and lane and lane.groupAccessGate == true
            and lane.identityCandidateMode or nil
        if lane and lane.enabled == true and laneAssistMode == assistMode then
            if lane.max == 1 then
                slotLanes = slotLanes or {}
                slotLanes[#slotLanes + 1] = lane
                ownedLaneKeys = ownedLaneKeys or {}
                ownedLaneKeys[lane.rootKey] = true
            elseif not flowLane then
                flowLane = lane
                ownedLaneKeys = ownedLaneKeys or {}
                ownedLaneKeys[lane.rootKey] = true
            end
        end
    end
    if not sensorRoot and not spellRoot and not slotLanes and not flowLane then return nil end

    signatureParts = {
        "identity:" .. tostring(assistMode or "neutral"),
        tostring(sensorRoot and sensorRoot._msufA3StructuralSignature or "-"),
        tostring(spellRoot and spellRoot._msufA3StructuralSignature or "-"),
        flowLane and ("flow:" .. tostring(flowLane.rootKey) .. ":"
            .. tostring(flowLane._msufA3StructuralSignature)) or "-",
    }
    if slotLanes then
        for i = 1, #slotLanes do
            local lane = slotLanes[i]
            signatureParts[#signatureParts + 1] = "slot:" .. tostring(lane.rootKey) .. ":"
                .. tostring(lane._msufA3StructuralSignature)
        end
    end
    return {
        kind = "groupAuraOwner",
        rootKey = rootKey,
        unit = (spellRoot or sensorRoot or flowLane or (slotLanes and slotLanes[1])).unit,
        sensorRoot = sensorRoot,
        spellIndicatorRoot = spellRoot,
        slotLanes = slotLanes,
        flowLane = flowLane,
        ownedLaneKeys = ownedLaneKeys,
        identityCandidateMode = assistMode,
        assistGated = assistMode ~= nil,
        _msufA3StructuralSignature = table_concat(signatureParts, "\028"),
    }
end

local function GetGroupSlotsRootConfig(cfg)
    if not (cfg and cfg.group == true) then return nil end
    local cached = cfg.groupSlotsRoot
    if cached ~= nil then return cached ~= false and cached or nil end

    local primary, secondary, tertiary
    if cfg.groupAssistGate == true then
        local spellRoot = SpellIndicatorsRuntime.RootConfig(cfg)
        local helpfulSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "assist", "GroupSpellAssist")
        local hostileSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "hostile", "GroupSpellHostile")
        local neutralSpellRoot = SpellIndicatorsRuntime.PartitionRoot(
            spellRoot, "neutral", "GroupSpellNeutral")
        primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots", neutralSpellRoot)
        secondary = BuildGroupAuraOwner(cfg, "assist", false, "GroupAuraAssist", helpfulSpellRoot)
        tertiary = BuildGroupAuraOwner(cfg, "hostile", false, "GroupAuraHostile", hostileSpellRoot)
        if not primary then primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots", false) end
        if not primary then
            primary = secondary or tertiary
            if primary == secondary then secondary = nil else tertiary = nil end
            if primary then primary.rootKey = "GroupSlots" end
        end
    else
        primary = BuildGroupAuraOwner(cfg, nil, true, "GroupSlots")
    end
    if not primary then
        cfg.groupSlotsRoot = false
        return nil
    end
    primary.secondaryRoot = secondary
    primary.tertiaryRoot = tertiary
    if secondary or tertiary then
        primary.allOwnedLaneKeys = {}
        for key in pairs(primary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
        for key in pairs(secondary and secondary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
        for key in pairs(tertiary and tertiary.ownedLaneKeys or {}) do primary.allOwnedLaneKeys[key] = true end
    else
        primary.allOwnedLaneKeys = primary.ownedLaneKeys
    end
    cfg.groupSlotsRoot = primary
    return primary
end

A3._GetGroupSlotsRootConfig = GetGroupSlotsRootConfig

-- Unit sensors already need a native owner. Share its cache with compatible
-- normal lanes, preserving the historical sensor root and each visual's layer.
-- Special lanes retain their own alias, portrait, priority or enchant lifecycle.
local function AttachUnitLanes(cfg, sensorRoot)
    if not sensorRoot then return nil end
    local flow, slots, owned
    local parts = { sensorRoot._msufA3StructuralSignature }
    local lanes = cfg.lanes
    for i = 1, #A3._normalAuraLaneOrder do
        local lane = lanes and lanes[A3._normalAuraLaneOrder[i]]
        if lane and lane.enabled == true and lane.identityCandidateMode == sensorRoot.identityCandidateMode
            and lane.portraitOverlay ~= true and lane.customPriority ~= true
            and lane.weaponEnchants ~= true and not lane.sourceSpellIDs
            and (lane.max == 1 or not flow) then
            if lane.max == 1 then
                slots = slots or {}
                slots[#slots + 1] = lane
            else
                flow = lane
            end
            owned = owned or {}
            owned[lane.rootKey] = true
            parts[#parts + 1] = lane.rootKey .. ":" .. lane._msufA3StructuralSignature
        end
    end
    if not owned then return sensorRoot end
    return { kind = "unitAuraOwner", rootKey = sensorRoot.rootKey, unit = sensorRoot.unit,
        enabled = true, sensorRoot = sensorRoot, flowLane = flow, slotLanes = slots,
        identityCandidateMode = sensorRoot.identityCandidateMode, ownedLaneKeys = owned,
        _msufA3StructuralSignature = table_concat(parts, "\028") }
end

-- Apply, refresh and reuse validation consume the same cold owner plan. This
-- prevents a lane merged at creation from acquiring a second update lifecycle.
local function GetNativeOwnerPlan(cfg)
    if cfg.nativeOwnerPlan then return cfg.nativeOwnerPlan end
    local group = cfg.group == true
    local plan = { keys = group and GROUP_OWNER_KEYS or UNIT_OWNER_KEYS, owners = {}, ownedLaneKeys = {} }
    local owners = plan.owners
    if group then
        local primary = GetGroupSlotsRootConfig(cfg)
        if primary then
            owners[primary.rootKey] = primary
            local secondary, tertiary = primary.secondaryRoot, primary.tertiaryRoot
            if secondary then owners[secondary.rootKey] = secondary end
            if tertiary then owners[tertiary.rootKey] = tertiary end
        end
    else
        owners.DispelSensor = AttachUnitLanes(cfg, GetDispelSensorRootConfig(cfg))
        owners.DispelSensorNeutral = AttachUnitLanes(cfg, GetUnitDispelSensorRootConfig(cfg))
        owners.DispelSensorHostile = AttachUnitLanes(cfg, GetUnitDispelSensorRootConfig(cfg, "hostile"))
    end
    for _, owner in pairs(owners) do
        for key in pairs(owner.ownedLaneKeys or {}) do plan.ownedLaneKeys[key] = true end
    end
    cfg.nativeOwnerPlan = plan
    return plan
end

return {
    EFFECT_ROOT_FIELDS = EFFECT_ROOT_FIELDS,
    EFFECT_ROOT_KEYS = EFFECT_ROOT_KEYS,
    GetDispelSensorRootConfig = GetDispelSensorRootConfig,
    GetGroupSlotsRootConfig = GetGroupSlotsRootConfig,
    GetUnitDispelSensorRootConfig = GetUnitDispelSensorRootConfig,
    GetNativeOwnerPlan = GetNativeOwnerPlan,
    NORMAL_LANE_ROOT_KEYS = NORMAL_LANE_ROOT_KEYS,
}
end
