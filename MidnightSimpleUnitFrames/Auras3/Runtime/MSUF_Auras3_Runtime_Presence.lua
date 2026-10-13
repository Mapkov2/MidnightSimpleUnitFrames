-- Auras3 runtime: Presence.
-- Group token generation, connection/phase and out-of-combat presence state. Presence hides output without interrupting native incremental tracking.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Presence = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Identity = Runtime.Identity
local Presence = Runtime.Presence
local SpellIndicatorsRuntime = A3.SpellIndicators
local pairs = pairs
local type = type
local C_Timer = dependencies.Platform.C_Timer
local RunNextFrame = _G.MSUF_RunNextFrame
local InCombat = dependencies.Platform.InCombat
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local SetAssistAlpha = dependencies.Identity.SetAssistAlpha
local UpdateAuraGroupEffectiveFilters = dependencies.Containers.UpdateAuraGroupEffectiveFilters
local UpdateAuraSlotEffectiveFilters = dependencies.Containers.UpdateAuraSlotEffectiveFilters
local issecretvalue = dependencies.Platform.issecretvalue

-- Group Aura presence is deliberately independent from geometric range and
-- from identity-filter permission.  Unknown state remains visible; only hard,
-- distance-independent negatives hide the output.  Native AuraContainers stay
-- shown and enabled so Blizzard can continue delivering incremental UNIT_AURA
-- updates while another party member is in a different instance.
Presence.ReadGroupAuraPresenceMapID = function(unit)
    local unitPosition = _G.UnitPosition
    if type(unitPosition) ~= "function" then return nil, false end
    local _, _, _, mapID = unitPosition(unit)
    if issecretvalue(mapID) == true or type(mapID) ~= "number" or mapID <= 0 then
        return nil, false
    end
    return mapID, true
end

Presence.ApplyGroupAuraPresenceFrame = function(frame, present, unit, revision)
    if not IsLiveGroupAuraFrame(frame) or type(present) ~= "boolean" then return false end
    frame._msufA3GroupAuraPresenceVisible = present
    frame._msufA3GroupAuraPresenceUnit = unit
    frame._msufA3GroupAuraPresenceRevision = revision
    local root = frame.Auras
    local any = false
    if root and root._msufA3NativeRoot == true and root.SetAlphaFromBoolean then
        root:SetAlphaFromBoolean(present, 1, 0)
        any = true
    elseif root and root._msufA3NativeRoot == true and root.SetAlpha then
        root:SetAlpha(present and 1 or 0)
        any = true
    end
    any = SpellIndicatorsRuntime.ApplyGroupPresenceGate(frame, present) or any
    return any
end

Presence.ApplyGroupAuraPresenceContainer = function(container, present, assistState)
    if not container or type(present) ~= "boolean" then return false end
    local outputVisible = present
    if outputVisible and Identity.ContainerOwnsGroupAuraAssistGate(container) then
        outputVisible = assistState ~= nil and assistState.assistKnown == true
            and assistState.dirty ~= true
            and Identity.GroupAuraAssistOwnerVisible(container, assistState.canAssist)
    end
    local config = container._msufA3NativeLaneConfig
    local trueAlpha = container._msufA3GroupSlotsRoot == true
        and 1 or type(config) == "table" and (config.alpha or 1) or 1
    return SetAssistAlpha(container, outputVisible == true, trueAlpha)
end

Presence.ApplyGroupAuraPresenceStateToUnit = function(unit, present, revision)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers or type(present) ~= "boolean" then return false end
    local assistState = A3._groupAuraAssistState and A3._groupAuraAssistState[unit]
    local parents, any = {}, false
    for container in pairs(containers) do
        local parentFrame = container and container._msufA3ParentFrame
        if IsLiveGroupAuraFrame(parentFrame) then
            if parents[parentFrame] ~= true then
                parents[parentFrame] = true
                any = Presence.ApplyGroupAuraPresenceFrame(
                    parentFrame, present, unit, revision) or any
            end
            any = Presence.ApplyGroupAuraPresenceContainer(
                container, present, assistState) or any
        end
    end
    return any
end

Presence.GroupAuraPresenceUnitHasOwners = function(unit)
    local counts = A3._directIdentityGroupOwnerCounts
    return counts ~= nil and (counts[unit] or 0) > 0
end

Presence.EnsureGroupAuraPresenceState = function(unit, allowUnregistered)
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return nil end
    if unit ~= "player" and not Identity.IsGroupUnitToken(unit) then return nil end
    if allowUnregistered ~= true and not Presence.GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
        return nil
    end
    local states = A3._groupAuraPresenceState
    if not states then
        states = {}
        A3._groupAuraPresenceState = states
    end
    local state = states[unit]
    if not state then
        state = { revision = 0 }
        states[unit] = state
    end
    return state
end

local function GroupAuraPresenceDerivedValue(state)
    return not (state.awaitingFullPresence == true or state.disabled == true
        or state.mapMismatch == true or state.phaseAbsent == true
        or state.otherParty == true or state.offline == true)
end

Presence.CommitGroupAuraPresenceState = function(unit, state, forceApply)
    if not state then return false end
    local hadState = state.initialized == true
    local previous = state.present ~= false
    local present = unit == "player" or GroupAuraPresenceDerivedValue(state)
    state.initialized = true
    state.present = present
    local changed = hadState ~= true or previous ~= present
    if changed then state.revision = (state.revision or 0) + 1 end
    if changed or forceApply == true then
        return Presence.ApplyGroupAuraPresenceStateToUnit(unit, present, state.revision)
    end
    return true
end

-- Token generations must remain live in combat so a reused raidN/partyN slot
-- can never inherit the previous member's absence latches.  This path reads no
-- map, phase, other-party, or connection state.
Presence.UpdateGroupAuraPresenceIdentityState = function(unit, forceApply, allowUnregistered)
    local state = Presence.EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then
        state.guid = nil
        state.guidKnown = true
        state.awaitingFullPresence = nil
        return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
    end
    local unitGUID = _G.UnitGUID
    if type(unitGUID) ~= "function" then return Presence.CommitGroupAuraPresenceState(unit, state, forceApply) end
    local guid = unitGUID(unit)
    if issecretvalue(guid) == true or type(guid) ~= "string" then
        return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
    end
    local hadIdentity = state.guidKnown == true
    local identityChanged = state.initialized == true
        and (hadIdentity ~= true or state.guid ~= guid)
    state.guid = guid
    state.guidKnown = true
    if identityChanged then
        state.disabled = nil
        state.mapMismatch = nil
        state.phaseAbsent = nil
        state.otherParty = nil
        state.offline = nil
        -- A readable new token generation must never inherit absence from the
        -- prior member. Unknown remains visible by policy; cold map/instance
        -- validation is merged separately and runs only OOC.
        state.awaitingFullPresence = nil
    end
    return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
end

Presence.UpdateAllGroupAuraPresenceIdentityStates = function()
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = Presence.UpdateGroupAuraPresenceIdentityState(unit, false) or any
        end
    end
    return any
end

-- Phase and connection are combat-relevant hard states.  Their narrow readers
-- intentionally do not consult UnitPosition or UnitInOtherParty; those 6.07
-- presence checks are owned exclusively by the OOC full reconciliation below.
Presence.UpdateGroupAuraPresencePhaseState = function(unit, forceApply, allowUnregistered)
    local state = Presence.EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then return Presence.CommitGroupAuraPresenceState(unit, state, forceApply) end
    -- UnitPhaseReason is SecretWhenUnitIdentityRestricted: assign its result
    -- first, and test it only after issecretvalue says it is plain.
    local unitPhaseReason = _G.UnitPhaseReason
    local phaseReason = nil
    if type(unitPhaseReason) == "function" then phaseReason = unitPhaseReason(unit) end
    if issecretvalue(phaseReason) ~= true then
        state.phaseAbsent = phaseReason ~= nil or nil
    end
    return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
end

Presence.UpdateAllGroupAuraPresencePhaseStates = function()
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = Presence.UpdateGroupAuraPresencePhaseState(unit, false) or any
        end
    end
    return any
end

Presence.UpdateGroupAuraPresenceConnectionState = function(
    unit, connectedPayload, forceApply, allowUnregistered)
    local state = Presence.EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    if unit == "player" then return Presence.CommitGroupAuraPresenceState(unit, state, forceApply) end
    local connected = connectedPayload
    if issecretvalue(connected) == true or type(connected) ~= "boolean" then
        local unitIsConnected = _G.UnitIsConnected
        if type(unitIsConnected) == "function" then connected = unitIsConnected(unit) end
    end
    if issecretvalue(connected) ~= true and type(connected) == "boolean" then
        state.offline = connected == false or nil
    end
    return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
end

Presence.UpdateGroupAuraPresenceState = function(
    unit, checkIdentity, forceApply, playerMapID, playerMapKnown, allowUnregistered)
    local state = Presence.EnsureGroupAuraPresenceState(unit, allowUnregistered)
    if not state then return false end
    -- Full presence is a cold OOC operation.  Seed/rebind/world callbacks can
    -- reach this function during combat; retain/apply the cached gate, update
    -- only token identity, and merge one post-combat reconciliation request.
    if InCombat() then
        local needsInitialFullPresence = state.initialized ~= true
        if checkIdentity == true or needsInitialFullPresence then
            Presence.UpdateGroupAuraPresenceIdentityState(unit, false, allowUnregistered)
            state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit] or state
        end
        if forceApply == true then
            Presence.ApplyGroupAuraPresenceStateToUnit(unit, state.present ~= false, state.revision or 0)
        end
        if type(Presence.ScheduleGroupAuraPresenceRefreshAll) == "function" then
            Presence.ScheduleGroupAuraPresenceRefreshAll(checkIdentity, false)
        end
        return true
    end

    if checkIdentity == true or state.initialized ~= true then
        Presence.UpdateGroupAuraPresenceIdentityState(unit, false, allowUnregistered)
        state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit] or state
    end
    if unit == "player" then
        state.mapMismatch = nil
        state.phaseAbsent = nil
        state.otherParty = nil
        state.offline = nil
        state.disabled = nil
        state.awaitingFullPresence = nil
    else
        if playerMapKnown == nil then
            playerMapID, playerMapKnown = Presence.ReadGroupAuraPresenceMapID("player")
        end
        local unitMapID, unitMapKnown = Presence.ReadGroupAuraPresenceMapID(unit)
        state.mapMismatch = playerMapKnown == true and unitMapKnown == true
            and playerMapID ~= unitMapID or nil

        local unitPhaseReason = _G.UnitPhaseReason
        local phaseReason = nil
        if type(unitPhaseReason) == "function" then phaseReason = unitPhaseReason(unit) end
        state.phaseAbsent = issecretvalue(phaseReason) ~= true and phaseReason ~= nil or nil

        -- Blizzard checks this before its other party-frame not-present
        -- reasons. It is the dedicated signal for a member that is currently
        -- inside a different instance group, including same-map copies where
        -- mapID and phase alone cannot distinguish presence.
        local unitInOtherParty = _G.UnitInOtherParty
        local inOtherParty = type(unitInOtherParty) == "function"
            and unitInOtherParty(unit) or nil
        state.otherParty = issecretvalue(inOtherParty) ~= true
            and type(inOtherParty) == "boolean" and inOtherParty == true or nil

        local unitIsConnected = _G.UnitIsConnected
        local connected = type(unitIsConnected) == "function" and unitIsConnected(unit) or nil
        state.offline = issecretvalue(connected) ~= true
            and type(connected) == "boolean" and connected == false or nil
        state.awaitingFullPresence = nil
    end
    return Presence.CommitGroupAuraPresenceState(unit, state, forceApply)
end

Presence.SetGroupAuraPresenceDisabled = function(unit, disabled, deferReveal)
    if issecretvalue(unit) == true or not Identity.IsGroupUnitToken(unit)
        or (not Presence.GroupAuraPresenceUnitHasOwners(unit)
            and (A3._directIdentityGroupOwnerCount or 0) <= 0) then return false end
    -- PARTY_MEMBER_DISABLE can precede the secure child's final registration.
    -- Keep one bounded token hint without invoking the cold presence reader;
    -- the later owner seed consumes this state immediately.
    local state = Presence.EnsureGroupAuraPresenceState(unit, true)
    if not state then return false end
    state.memberEventRevision = (state.memberEventRevision or 0) + 1
    local wasDisabled = state.disabled == true
    state.disabled = disabled == true or nil
    state.initialized = true
    if disabled == true then
        state.awaitingFullPresence = nil
    elseif deferReveal == true and (wasDisabled or state.present == false) then
        -- ENABLE is an invalidation, not proof that the unit has returned to
        -- this instance. Keep the previous fail-closed output until the
        -- coalesced reader has refreshed map, phase and connection state.
        state.awaitingFullPresence = true
        Presence.CommitGroupAuraPresenceState(unit, state, false)
        return true
    end
    Presence.CommitGroupAuraPresenceState(unit, state, false)
    -- A valid directional hint may precede the owner's secure-header
    -- registration, so retaining state counts as success without an alpha sink.
    return true
end

Presence.InvalidateSingleGroupAuraPresenceDisabled = function()
    local states = A3._groupAuraPresenceState
    if not states then return false end
    local candidate
    for unit, state in pairs(states) do
        if state and state.disabled == true and Presence.GroupAuraPresenceUnitHasOwners(unit) then
            if candidate ~= nil then
                -- A restricted ENABLE payload cannot identify which of several
                -- absent members returned. Keep all fail-closed rather than
                -- revealing an unrelated same-map instance member.
                return false
            end
            candidate = unit
        end
    end
    if candidate == nil then return false end
    states[candidate].disabled = nil
    return true
end

Presence.CaptureSingleGroupAuraPresenceDisabled = function()
    local states = A3._groupAuraPresenceState
    local candidate, revision, candidateState
    for unit, state in pairs(states or {}) do
        if state and state.disabled == true and Presence.GroupAuraPresenceUnitHasOwners(unit) then
            if candidate ~= nil then
                candidate = nil
                break
            end
            candidate = unit
            candidateState = state
            revision = state.memberEventRevision or 0
        end
    end
    A3._groupAuraPresenceRefreshAllEnableCandidate = candidate
    A3._groupAuraPresenceRefreshAllEnableCandidateRevision = candidate and revision or nil
    A3._groupAuraPresenceRefreshAllEnableCandidateState = candidate and candidateState or nil
    return candidate ~= nil
end

Presence.InvalidateCapturedGroupAuraPresenceDisabled = function()
    local unit = A3._groupAuraPresenceRefreshAllEnableCandidate
    local revision = A3._groupAuraPresenceRefreshAllEnableCandidateRevision
    local capturedState = A3._groupAuraPresenceRefreshAllEnableCandidateState
    A3._groupAuraPresenceRefreshAllEnableCandidate = nil
    A3._groupAuraPresenceRefreshAllEnableCandidateRevision = nil
    A3._groupAuraPresenceRefreshAllEnableCandidateState = nil
    local state = unit and A3._groupAuraPresenceState
        and A3._groupAuraPresenceState[unit]
    if not state or state ~= capturedState or state.disabled ~= true
        or (state.memberEventRevision or 0) ~= revision then
        return false
    end
    state.disabled = nil
    return true
end

Presence.FlushScheduledGroupAuraPresenceRefreshAll = function()
    A3._groupAuraPresenceRefreshAllTimerPending = nil
    if A3._groupAuraPresenceRefreshAllPending ~= true then return false end
    -- A timer queued just before the pull must not leak cold map/instance reads
    -- into combat. Keep the merged request intact for PLAYER_REGEN_ENABLED.
    if InCombat() then return false end
    A3._groupAuraPresenceRefreshAllPending = nil
    local checkIdentity = A3._groupAuraPresenceRefreshAllCheckIdentity == true
    local checkAssist = A3._groupAuraPresenceRefreshAllCheckAssist == true
    local invalidateSingleDisabled =
        A3._groupAuraPresenceRefreshAllEnableCandidate ~= nil
    A3._groupAuraPresenceRefreshAllCheckIdentity = nil
    A3._groupAuraPresenceRefreshAllCheckAssist = nil
    if invalidateSingleDisabled then
        Presence.InvalidateCapturedGroupAuraPresenceDisabled()
    end
    local playerMapID, playerMapKnown = Presence.ReadGroupAuraPresenceMapID("player")
    local any = false
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            any = Presence.UpdateGroupAuraPresenceState(
                unit, checkIdentity, false, playerMapID, playerMapKnown) or any
        end
    end
    if checkAssist then
        any = Identity.UpdateAllGroupAuraAssistStates(checkIdentity, false) or any
    end
    return any
end

Presence.QueueGroupAuraPresenceRefreshAllFlush = function()
    if A3._groupAuraPresenceRefreshAllPending ~= true
        or A3._groupAuraPresenceRefreshAllTimerPending == true
        or InCombat() then return false end
    A3._groupAuraPresenceRefreshAllTimerPending = true
    if RunNextFrame then
        RunNextFrame(Presence.FlushScheduledGroupAuraPresenceRefreshAll)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, Presence.FlushScheduledGroupAuraPresenceRefreshAll)
    else
        Presence.FlushScheduledGroupAuraPresenceRefreshAll()
    end
    return true
end

Presence.ScheduleGroupAuraPresenceRefreshAll = function(checkIdentity, checkAssist)
    if (A3._directIdentityGroupOwnerCount or 0) <= 0 then return false end
    if checkIdentity == true then A3._groupAuraPresenceRefreshAllCheckIdentity = true end
    if checkAssist == true then A3._groupAuraPresenceRefreshAllCheckAssist = true end
    A3._groupAuraPresenceRefreshAllPending = true
    Presence.QueueGroupAuraPresenceRefreshAllFlush()
    return true
end

Presence.SeedGroupAuraPresenceGate = function(frame, fallbackUnit, cachedOnly)
    if not IsLiveGroupAuraFrame(frame) then return false end
    local unit = frame.MSUFUnitKey
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
        unit = fallbackUnit
    end
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return false end
    if unit ~= "player" and not Identity.IsGroupUnitToken(unit) then return false end
    local state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit]
    if cachedOnly ~= true or not (state and state.initialized == true) then
        Presence.UpdateGroupAuraPresenceState(unit, true, false, nil, nil, true)
        state = A3._groupAuraPresenceState and A3._groupAuraPresenceState[unit]
    end
    local present = not state or state.present ~= false
    local revision = state and state.revision or 0
    local any = Presence.ApplyGroupAuraPresenceFrame(frame, present, unit, revision)
    -- The primary SecureGroupHeader AuraContainer can be a direct child of the
    -- member frame instead of frame.Auras. Re-apply the cached state to every
    -- registered owner after config/rebind so that container cannot bypass the
    -- root gate during its first visible frame.
    if Presence.GroupAuraPresenceUnitHasOwners(unit) then
        any = Presence.ApplyGroupAuraPresenceStateToUnit(unit, present, revision) or any
    end
    return any
end

local function SyncCuratedBigDefensiveContainer(container)
    local config = container and container._msufA3NativeLaneConfig
    if not config then return false end
    local changed = false
    if container._msufA3GroupSlotsRoot == true then
        local slotLanes = config.slotLanes
        for i = 1, #(slotLanes or {}) do
            local lane = slotLanes[i]
            if lane and lane._msufA3BigDefensiveFilter then
                changed = UpdateAuraSlotEffectiveFilters(container, lane) or changed
            end
        end
        local flowLane = config.flowLane
        if flowLane and flowLane._msufA3BigDefensiveFilter then
            changed = UpdateAuraGroupEffectiveFilters(container, flowLane) or changed
        end
    elseif config._msufA3BigDefensiveFilter then
        if container._msufA3StandaloneAuraSlot == true then
            changed = UpdateAuraSlotEffectiveFilters(container, config)
        else
            changed = UpdateAuraGroupEffectiveFilters(container, config)
        end
    end
    return changed
end
Presence.SyncCuratedBigDefensiveContainer = SyncCuratedBigDefensiveContainer

local exports = {
    SyncCuratedBigDefensiveContainer = SyncCuratedBigDefensiveContainer,
}
for name, value in pairs(exports) do Presence[name] = value end
return Presence
end
