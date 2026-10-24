-- Auras3 runtime: Identity.
-- Friendly/enemy transition gates and deferred reveal. Unit gates control native enablement; Group gates intentionally retain enabled tracking and change
-- alpha only.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Identity = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Identity = Runtime.Identity
local SpellIndicatorsRuntime = A3.SpellIndicators
local next = next
local pairs = pairs
local tonumber = tonumber
local type = type
local RunNextFrame = dependencies.Platform.RunNextFrame
local GetGroupSlotsRootConfig = dependencies.OwnerConfig.GetGroupSlotsRootConfig
local IsGroupFrame = dependencies.ConfigValues.IsGroupFrame
local UnitCanAssistForAuraIdentity = dependencies.ConfigValues.UnitCanAssistForAuraIdentity
local issecretvalue = dependencies.Platform.issecretvalue

-- UnitCanAssist is a normal non-secret boolean in the 12.1 API contract. Keep
-- the write on the native boolean sink so every affected owner receives one
-- direct alpha update without inspecting any restricted aura data.
local function SetAssistAlpha(region, value, trueAlpha)
    if not region then return false end
    if region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(value, trueAlpha, 0)
    elseif region.SetAlpha then
        region:SetAlpha(value and trueAlpha or 0)
    else
        return false
    end
    return true
end

local function IsLiveGroupAuraFrame(frame)
    return frame and frame._msufGFIsPreviewFrame ~= true and IsGroupFrame(frame) or false
end

local function ApplyGroupLaneAccessGate(root, lanes, laneKey, rootKey, canAssist, ready)
    local lane = lanes and lanes[laneKey]
    if not (lane and lane.groupAccessGate == true) then return false end
    -- The sole caller already folded the secret/type check into this plain
    -- ready flag. Keep the short circuit before inspecting canAssist.
    local parentFrame = root and root.GetParent and root:GetParent()
    local present = not parentFrame or parentFrame._msufA3GroupAuraPresenceVisible ~= false
    local visible = present and ready and (lane.identityCandidateMode == "hostile"
        and canAssist == false or lane.identityCandidateMode ~= "hostile" and canAssist == true)
    return SetAssistAlpha(root[rootKey], visible, lane.alpha or 1)
end

local function NeedsGroupAuraAssistGate(cfg)
    if not (cfg and cfg.group == true and cfg.enabled == true) then return false end
    local groupSlots = GetGroupSlotsRootConfig(cfg)
    if groupSlots and (groupSlots.assistGated == true
        or groupSlots.secondaryRoot and groupSlots.secondaryRoot.assistGated == true
        or groupSlots.tertiaryRoot and groupSlots.tertiaryRoot.assistGated == true) then
        return true
    end
    local lanes = cfg.lanes
    return lanes and (
        lanes.buff and lanes.buff.enabled == true and lanes.buff.groupAccessGate == true
        or lanes.debuff and lanes.debuff.enabled == true and lanes.debuff.groupAccessGate == true
        or lanes.trackedBuff and lanes.trackedBuff.enabled == true and lanes.trackedBuff.groupAccessGate == true
        or lanes.external and lanes.external.enabled == true and lanes.external.groupAccessGate == true)
        or false
end
Identity.NeedsGroupAuraAssistGate = NeedsGroupAuraAssistGate

-- Exact-ID owners are polarity-aware: helpful filters are valid only while
-- assistable, harmful filters only while non-assistable. Ordinary token-only
-- Buff/Debuff and Dispel flows remain under incremental UNIT_AURA ownership.
local function ApplyGroupAuraAssistGate(frame, canAssist, ready)
    local root = frame.Auras
    if not (root and root._msufA3NativeRoot == true) then return false end
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    ready = ready ~= false and known
    frame._msufA3GroupAuraAssistReady = ready
    if known then
        frame._msufA3GroupAuraCanAssist = canAssist
    else
        frame._msufA3GroupAuraCanAssist = nil
    end
    local present = frame._msufA3GroupAuraPresenceVisible ~= false

    local cfg = root._msufA3Config
    local groupSlots = GetGroupSlotsRootConfig(cfg)
    local any = false
    if groupSlots then
        -- The compiled config already owns these three descriptors. Walking
        -- them directly avoids a temporary table on every identity refresh;
        -- a missing secondary must not hide an existing tertiary owner.
        local owner = groupSlots
        for index = 1, 3 do
            if owner and owner.assistGated == true then
                local visible = present and ready and (owner.identityCandidateMode == "hostile"
                    and canAssist == false or owner.identityCandidateMode ~= "hostile" and canAssist == true)
                any = SetAssistAlpha(root[owner.rootKey or "GroupSlots"], visible, 1) or any
            end
            if index == 1 then owner = groupSlots.secondaryRoot
            else owner = groupSlots.tertiaryRoot end
        end
    end

    local lanes = cfg and cfg.lanes
    any = ApplyGroupLaneAccessGate(root, lanes, "buff", "Buffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "debuff", "Debuffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "trackedBuff", "TrackedBuffs", canAssist, ready) or any
    any = ApplyGroupLaneAccessGate(root, lanes, "external", "Externals", canAssist, ready) or any

    any = SpellIndicatorsRuntime.ApplyGroupAssistGate(frame, canAssist, ready) or any
    return any
end

Identity.SeedGroupAuraAssistGate = function(frame, fallbackUnit)
    if not IsLiveGroupAuraFrame(frame) then return false end
    local root = frame.Auras
    if not NeedsGroupAuraAssistGate(root and root._msufA3Config) then return false end
    -- Secure-header retirement/rebinding can briefly clear MSUFUnitKey while
    -- the native container is still present in the direct-identity registry.
    -- That registry key is the authoritative fallback for this cold check.
    local unit = frame.MSUFUnitKey
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
        unit = fallbackUnit
    end
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if unit ~= "player" and not (Identity.IsGroupUnitToken and Identity.IsGroupUnitToken(unit)) then
        return false
    end
    if type(Identity.UpdateGroupAuraAssistState) == "function" then
        return Identity.UpdateGroupAuraAssistState(unit, false, true)
    end
    if type(UnitCanAssist) ~= "function" then return ApplyGroupAuraAssistGate(frame, nil, false) end
    local canAssist = UnitCanAssistForAuraIdentity(unit)
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    if not known then canAssist = nil end
    return ApplyGroupAuraAssistGate(frame, canAssist, known)
end

A3._directIdentityRefreshUnits = A3._directIdentityRefreshUnits or {
    player = true,
    target = true,
    focus = true,
    boss1 = true,
    boss2 = true,
    boss3 = true,
    boss4 = true,
    boss5 = true,
    arena1 = true,
    arena2 = true,
    arena3 = true,
}

A3._directIdentityRefreshAllEvents = A3._directIdentityRefreshAllEvents or {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED_NEW_AREA = true,
    ENTERED_DIFFERENT_INSTANCE_FROM_PARTY = true,
}

A3._directIdentityEventUnits = A3._directIdentityEventUnits or {
    PLAYER_TARGET_CHANGED = { "target" },
    PLAYER_FOCUS_CHANGED = { "focus" },
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = { "boss1", "boss2", "boss3", "boss4", "boss5" },
    ARENA_OPPONENT_UPDATE = { "arena1", "arena2", "arena3" },
}

Identity.HasDirectIdentityRefreshContainers = function()
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then return false end
    for unit, containers in pairs(byUnit) do
        if containers and next(containers) then return true end
        byUnit[unit] = nil
    end
    return false
end

Identity.IsGroupUnitToken = MSUF.Require("MSUF_IsGroupUnitToken", "Auras3/Runtime/MSUF_Auras3_Runtime_Identity.lua")

Identity.DirectIdentityRefreshUnitEligible = function(unit)
    if A3._directIdentityRefreshUnits[unit] == true then return true end
    return Identity.IsGroupUnitToken(unit)
end

local function NativeFilterOwnsHelpfulAuras(nativeFilter)
    return type(nativeFilter) == "string"
        and nativeFilter:find("HELPFUL", 1, true) ~= nil
end

local function GroupSlotsOwnHelpfulAuras(groupSlots)
    if not groupSlots then return false end
    local flowLane = groupSlots.flowLane
    if flowLane and NativeFilterOwnsHelpfulAuras(flowLane.nativeFilter) then
        return true
    end
    local slotLanes = groupSlots.slotLanes
    for i = 1, #(slotLanes or {}) do
        local lane = slotLanes[i]
        if lane and NativeFilterOwnsHelpfulAuras(lane.nativeFilter) then
            return true
        end
    end
    return false
end

local function ContainerOwnsHelpfulAuras(container, lane)
    if container and container._msufA3GroupSlotsRoot == true then
        return GroupSlotsOwnHelpfulAuras(lane)
    end
    return lane and NativeFilterOwnsHelpfulAuras(lane.nativeFilter)
end

-- Identity-sensitive group owners are deliberately discoverable from their
-- cold compiled descriptors. Lifecycle events therefore route by unit and scan
-- only that unit's tiny native-owner set; no frame-local event or roster walk is
-- needed for a normal per-unit edge.
Identity.ContainerOwnsGroupAuraAssistGate = function(container)
    local parentFrame = container and container._msufA3ParentFrame
    if not IsLiveGroupAuraFrame(parentFrame) then return false end
    local config = container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if container._msufA3GroupSlotsRoot == true then
        return config.assistGated == true
    end
    return config.groupAccessGate == true
end

Identity.GroupAuraAssistOwnerVisible = function(container, canAssist)
    if issecretvalue(canAssist) == true or type(canAssist) ~= "boolean" then return false end
    local config = container and container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if config.identityCandidateMode == "hostile" then return canAssist ~= true end
    return canAssist == true
end

Identity.GroupAuraAssistUnitHasOwners = function(unit)
    local counts = A3._groupAuraAssistOwnerCounts
    return counts ~= nil and (counts[unit] or 0) > 0
end

Identity.HasGroupAuraAssistOwners = function()
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then
        A3._groupAuraAssistOwnerCount = 0
        return false
    end
    return (A3._groupAuraAssistOwnerCount or 0) > 0
end

-- One gate applier per readiness: ready=true reveals the owners' parent frames
-- for a known assist state, ready=false hides them. The closure keeps the call
-- shape of the two entry points below unchanged.
local function CreateGroupAuraAssistGateApplier(ready)
    return function(unit, canAssist)
        local byUnit = A3._directIdentityAuraContainers
        local containers = byUnit and byUnit[unit]
        if not containers then return false end
        local parents, any = {}, false
        for container in pairs(containers) do
            if Identity.ContainerOwnsGroupAuraAssistGate(container) then
                local parentFrame = container._msufA3ParentFrame
                if parentFrame and parents[parentFrame] ~= true then
                    parents[parentFrame] = true
                    any = ApplyGroupAuraAssistGate(parentFrame, canAssist, ready) or any
                end
            end
        end
        return any
    end
end

Identity.ApplyGroupAuraAssistStateToUnit = CreateGroupAuraAssistGateApplier(true)

Identity.HideGroupAuraAssistOwners = CreateGroupAuraAssistGateApplier(false)

Identity.ReadGroupAuraAssistIdentity = function(unit, readGUID)
    if type(UnitCanAssist) ~= "function" then return nil, false, nil, false end
    -- Blizzard_AuraContainerUtil deliberately ignores immune/uninteractable
    -- restrictions for identity candidate filters. Follower-dungeon partyN
    -- units can otherwise report false here and hide every HELPFUL owner.
    local canAssist = UnitCanAssistForAuraIdentity(unit)
    local assistKnown = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    if not assistKnown then canAssist = nil end

    if readGUID ~= true then return canAssist, assistKnown, nil, false end
    local unitGUID = UnitGUID
    if type(unitGUID) ~= "function" then return canAssist, assistKnown, nil, false end
    local guid = unitGUID(unit)
    if issecretvalue(guid) == true or (guid ~= nil and type(guid) ~= "string") then
        return canAssist, assistKnown, nil, false
    end
    return canAssist, assistKnown, guid, true
end

-- Unit-frame exact-ID owners use the same Blizzard identity contract as Group
-- owners, but they deliberately stay out of the Group roster/flag lifecycle.
-- Their only live inputs are the already-owned target/focus/boss identity
-- events and the existing UNIT_FACTION route.
Identity.ContainerOwnsUnitAuraIdentityGate = function(container)
    if not container or IsLiveGroupAuraFrame(container._msufA3ParentFrame) then return false end
    local config = container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    return config.identityCandidateMode == "assist"
        or config.identityCandidateMode == "hostile"
end

Identity.UnitAuraIdentityOwnerVisible = function(container, canAssist)
    if issecretvalue(canAssist) == true or type(canAssist) ~= "boolean" then return false end
    local config = container and container._msufA3NativeLaneConfig
    if type(config) ~= "table" then return false end
    if config.identityCandidateMode == "hostile" then return canAssist ~= true end
    return config.identityCandidateMode == "assist" and canAssist == true
end

Identity.UnitAuraIdentityUnitHasOwners = function(unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    return set ~= nil and next(set) ~= nil
end

Identity.SetUnitAuraIdentityOwnerReady = function(container, canAssist, ready)
    if not Identity.ContainerOwnsUnitAuraIdentityGate(container) then return false end
    local config = container._msufA3NativeLaneConfig
    local polarityVisible = Identity.UnitAuraIdentityOwnerVisible(container, canAssist)
    local visible = ready == true and polarityVisible
    local any = SetAssistAlpha(container, visible, tonumber(config.alpha) or 1)
    -- Alpha only hides the output: a HELPFUL exact-ID owner on an enemy target
    -- (or a HARMFUL one on a friend) would otherwise stay registered for
    -- UNIT_AURA and keep parsing every delta into an invisible slot. Follow the
    -- known polarity with Blizzard's own enable flag: SetEnabled(false) drops
    -- the registration, SetEnabled(true) is Blizzard's full reparse, and the
    -- reveal above still owns the visible alpha. Only live registered owners
    -- take this path; creation keeps enabling inside RegisterNativeContainer.
    if container._msufA3NativeRegistered == true and type(container.SetEnabled) == "function" then
        container:SetEnabled(polarityVisible == true)
    end
    if container._msufA3SpellIndicatorRoot == true then
        any = SpellIndicatorsRuntime.ApplyUnitIdentityGate(
            container, canAssist, ready) or any
    end
    return any
end

Identity.ApplyUnitAuraIdentityStateToUnit = function(unit, canAssist, ready)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    if not set then return false end
    local any = false
    for container in pairs(set) do
        any = Identity.SetUnitAuraIdentityOwnerReady(container, canAssist, ready) or any
    end
    return any
end

Identity.EnsureUnitAuraIdentityState = function(unit)
    local states = A3._unitAuraIdentityState
    if not states then
        states = {}
        A3._unitAuraIdentityState = states
    end
    local state = states[unit]
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    return state
end

Identity.RefreshUnitAuraIdentityState = function(unit)
    if not Identity.UnitAuraIdentityUnitHasOwners(unit) then return nil end
    local state = Identity.EnsureUnitAuraIdentityState(unit)
    local canAssist, assistKnown = Identity.ReadGroupAuraAssistIdentity(unit, false)
    state.revision = (state.revision or 0) + 1
    state.initialized = true
    state.assistKnown = assistKnown == true
    if assistKnown == true then state.canAssist = canAssist else state.canAssist = nil end
    return state
end

Identity.FlushUnitAuraIdentityReveal = function()
    A3._unitAuraIdentityRevealPending = nil
    local units = A3._unitAuraIdentityRevealUnits
    local states = A3._unitAuraIdentityState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        units[unit] = nil
        local state = states[unit]
        if state and state.revision == revision and state.assistKnown == true then
            any = Identity.ApplyUnitAuraIdentityStateToUnit(unit, state.canAssist, true) or any
        end
    end
    return any
end

Identity.ScheduleUnitAuraIdentityReveal = function(unit, revision)
    local units = A3._unitAuraIdentityRevealUnits
    if not units then
        units = {}
        A3._unitAuraIdentityRevealUnits = units
    end
    units[unit] = revision
    if A3._unitAuraIdentityRevealPending == true then return true end
    A3._unitAuraIdentityRevealPending = true
    RunNextFrame(Identity.FlushUnitAuraIdentityReveal)
    return true
end

Identity.SeedUnitAuraIdentityOwner = function(container, unit)
    if not Identity.ContainerOwnsUnitAuraIdentityGate(container) then return false end
    local state = Identity.EnsureUnitAuraIdentityState(unit)
    if state.initialized ~= true then
        local canAssist, assistKnown = Identity.ReadGroupAuraAssistIdentity(unit, false)
        state.revision = (state.revision or 0) + 1
        state.initialized = true
        state.assistKnown = assistKnown == true
        if assistKnown == true then state.canAssist = canAssist else state.canAssist = nil end
    end
    Identity.SetUnitAuraIdentityOwnerReady(container, state.canAssist, false)
    if state.assistKnown == true then
        Identity.ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    return true
end

Identity.RefreshGroupAuraAssistOwners = function(unit, canAssist)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local any = false
    for container in pairs(containers) do
        if Identity.ContainerOwnsGroupAuraAssistGate(container)
            and Identity.GroupAuraAssistOwnerVisible(container, canAssist) then
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                -- Alpha zero does not make a Frame non-visible. Marking a
                -- temporarily hidden owner dirty is still safe: Blizzard's
                -- RunWhenVisibleOnce processes it on the next visible frame.
                update(container)
                any = true
            end
        end
    end
    return any
end

Identity.FlushGroupAuraAssistReveal = function()
    A3._groupAuraAssistRevealPending = nil
    local units = A3._groupAuraAssistRevealUnits
    A3._groupAuraAssistRevealUnits = nil
    local states = A3._groupAuraAssistState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        local state = states[unit]
        if state and state.revision == revision
            and state.assistKnown == true and state.dirty == true then
            state.dirty = false
            any = Identity.ApplyGroupAuraAssistStateToUnit(unit, state.canAssist) or any
        end
    end
    return any
end

Identity.ScheduleGroupAuraAssistReveal = function(unit, revision)
    local units = A3._groupAuraAssistRevealUnits
    if not units then
        units = {}
        A3._groupAuraAssistRevealUnits = units
    end
    units[unit] = revision
    if A3._groupAuraAssistRevealPending == true then return true end
    A3._groupAuraAssistRevealPending = true
    RunNextFrame(Identity.FlushGroupAuraAssistReveal)
    return true
end

Identity.FlushScheduledGroupAuraAssistRefresh = function()
    A3._groupAuraAssistRefreshPending = nil
    if A3._directIdentityRefreshPending == true
        and A3._directIdentityRefreshSkipLiveGroup ~= true then
        -- A portal/world job already covers every group identity owner. Let the
        -- wider job win regardless of callback order: an all-owner pass adopts
        -- the satisfied parse, while a group-presence pass queues one fresh
        -- eligible-polarity repair after it invalidates native assignments.
        A3._groupAuraAssistRefreshUnits = nil
        return false
    end
    local units = A3._groupAuraAssistRefreshUnits
    A3._groupAuraAssistRefreshUnits = nil
    local states = A3._groupAuraAssistState
    if not (units and states) then return false end
    local any = false
    for unit, revision in pairs(units) do
        local state = states[unit]
        if state and state.revision == revision
            and state.assistKnown == true and state.dirty == true then
            any = Identity.RefreshGroupAuraAssistOwners(unit, state.canAssist) or any
            Identity.ScheduleGroupAuraAssistReveal(unit, revision)
        end
    end
    return any
end

Identity.ScheduleGroupAuraAssistRefresh = function(unit, revision)
    local units = A3._groupAuraAssistRefreshUnits
    if not units then
        units = {}
        A3._groupAuraAssistRefreshUnits = units
    end
    units[unit] = revision
    if A3._groupAuraAssistRefreshPending == true then return true end
    A3._groupAuraAssistRefreshPending = true
    RunNextFrame(Identity.FlushScheduledGroupAuraAssistRefresh)
    return true
end

-- State transitions are fail-closed. Both polarity owners stay hidden while
-- UnitCanAssist is unavailable/secret. A known edge keeps both hidden, reparses
-- only the newly eligible owner, then reveals it on the following one-shot tick.
Identity.UpdateGroupAuraAssistState = function(unit, checkIdentity, forceApply, forceRefresh, reparseSatisfied)
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if not Identity.GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
        return false
    end

    local states = A3._groupAuraAssistState
    if not states then
        states = {}
        A3._groupAuraAssistState = states
    end
    local state = states[unit]
    local hadState = state ~= nil and state.initialized == true
    local canAssist, assistKnown, guid, guidKnown = Identity.ReadGroupAuraAssistIdentity(
        unit, checkIdentity == true or hadState ~= true)
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    local previous = state.canAssist
    local previousKnown = state.assistKnown == true
    local identityChanged = checkIdentity == true and hadState == true
        and (guidKnown ~= true or state.guidKnown ~= true or state.guid ~= guid)
    if guidKnown == true then
        state.guid = guid
        state.guidKnown = true
    end
    state.initialized = true
    if assistKnown then state.canAssist = canAssist else state.canAssist = nil end
    state.assistKnown = assistKnown == true

    local needsRefresh = hadState ~= true or previousKnown ~= (assistKnown == true)
        or assistKnown == true and previous ~= canAssist
        or identityChanged or forceRefresh == true
    if reparseSatisfied == true then
        -- The direct identity path has already reparsed every owner for this
        -- unit. Adopt that parse into the state machine instead of scheduling
        -- the eligible polarity a second time. Bumping the revision also makes
        -- any older queued refresh/reveal a harmless no-op.
        state.revision = (state.revision or 0) + 1
        state.dirty = nil
        if assistKnown ~= true then
            Identity.HideGroupAuraAssistOwners(unit, nil)
        else
            Identity.ApplyGroupAuraAssistStateToUnit(unit, canAssist)
        end
        return true
    end
    if assistKnown ~= true then
        if needsRefresh or forceApply == true then
            state.revision = (state.revision or 0) + 1
            state.dirty = nil
            Identity.HideGroupAuraAssistOwners(unit, nil)
        end
        return true
    end
    if needsRefresh then
        state.revision = (state.revision or 0) + 1
        state.dirty = true
        -- Both polarity owners stay fail-closed until the newly eligible owner
        -- has reparsed. Passing ready=false hides HELPFUL and HARMFUL custom
        -- owners together without touching neutral aura flows.
        Identity.HideGroupAuraAssistOwners(unit, canAssist)
        Identity.ScheduleGroupAuraAssistRefresh(unit, state.revision)
    elseif state.dirty == true then
        if forceApply == true then Identity.HideGroupAuraAssistOwners(unit, canAssist) end
        Identity.ScheduleGroupAuraAssistRefresh(unit, state.revision)
    elseif forceApply == true then
        Identity.ApplyGroupAuraAssistStateToUnit(unit, canAssist)
    end
    return true
end

Identity.UpdateAllGroupAuraAssistStates = function(checkIdentity, forceRefresh)
    local counts = A3._groupAuraAssistOwnerCounts
    if not counts then return false end
    local any = false
    for unit, count in pairs(counts) do
        if count > 0 then
            any = Identity.UpdateGroupAuraAssistState(unit, checkIdentity, false, forceRefresh) or any
        end
    end
    return any
end

Identity.FlushScheduledGroupAuraAssistRefreshAll = function()
    A3._groupAuraAssistRefreshAllPending = nil
    local checkIdentity = A3._groupAuraAssistRefreshAllCheckIdentity == true
    local forceRefresh = A3._groupAuraAssistRefreshAllForce == true
    A3._groupAuraAssistRefreshAllCheckIdentity = nil
    A3._groupAuraAssistRefreshAllForce = nil
    return Identity.UpdateAllGroupAuraAssistStates(checkIdentity, forceRefresh)
end

Identity.ScheduleGroupAuraAssistRefreshAll = function(checkIdentity, forceRefresh)
    if not Identity.HasGroupAuraAssistOwners() then return false end
    if checkIdentity == true then A3._groupAuraAssistRefreshAllCheckIdentity = true end
    if forceRefresh == true then A3._groupAuraAssistRefreshAllForce = true end
    if A3._groupAuraAssistRefreshAllPending == true then return true end
    A3._groupAuraAssistRefreshAllPending = true
    RunNextFrame(Identity.FlushScheduledGroupAuraAssistRefreshAll)
    return true
end

local exports = {
    ContainerOwnsHelpfulAuras = ContainerOwnsHelpfulAuras,
    IsLiveGroupAuraFrame = IsLiveGroupAuraFrame,
    SetAssistAlpha = SetAssistAlpha,
}
for name, value in pairs(exports) do Identity[name] = value end
return Identity
end
