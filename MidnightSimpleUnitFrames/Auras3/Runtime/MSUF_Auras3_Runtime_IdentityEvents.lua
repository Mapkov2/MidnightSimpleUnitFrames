-- Auras3 runtime: IdentityEvents.
-- Owner registration, narrow event topology and coalesced identity refresh. Registration is batched during roster setup; unchanged identity edges do not reparse auras.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.IdentityEvents = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local math_floor = math.floor
local math_max = math.max
local next = next
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local type = type
local ApplyLane
local C_Timer = dependencies.Platform.C_Timer
local ContainerOwnsHelpfulAuras = dependencies.Identity.ContainerOwnsHelpfulAuras
local CreateFrame = dependencies.Platform.CreateFrame
local InCombat = dependencies.Platform.InCombat
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local RecreateGroupSlots
local SyncCuratedBigDefensiveContainer = dependencies.Presence.SyncCuratedBigDefensiveContainer
local issecretvalue = dependencies.Platform.issecretvalue

-- Presence transitions never invalidate native aura ownership.  They only
-- recompute the plain per-unit output gate; the still-enabled containers keep
-- their incremental UNIT_AURA stream while absent.
A3._DirectGroupPresenceRefreshUnit = function(unit)
    return A3._UpdateGroupAuraPresenceState(unit, false, false)
end

A3._DirectIdentityRefreshUnitBase = function(
    unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    -- Only Party/Raid registry units (plus the Party self-frame shared under
    -- "player") can own an assist-gated group aura parent. Target, focus and
    -- boss identity refreshes must not inspect group state.
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)

    if forceSpellIndicatorGeometry ~= true then
        -- Target/focus swaps use this direct route. Keep the exceptional
        -- world-transition recreation machinery out of the steady path while
        -- still consuming any one-shot geometry marker left by a hidden frame.
        local any = false
        for container in pairs(containers) do
            if skipLiveGroup ~= true
                or not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
                local filterChanged = SyncCuratedBigDefensiveContainer(container)
                local update = container and container.UpdateAllAuras
                if type(update) == "function" then
                    if not filterChanged and A3._NativeContainerVisible(container) then update(container) end
                    if container._msufA3ForceManagedAuraGeometry == true
                        or container._msufA3ForceSpellIndicatorGeometry == true then
                        A3._SyncManagedAuraContainerGeometry(container, true)
                    end
                    any = true
                end
            end
        end
        if seedGroupAssist then
            A3._UpdateGroupAuraAssistState(unit, false, true, false, true)
        end
        return any
    end

    local any, spellRecreates, helpfulRecreates = false, nil, nil
    for container in pairs(containers) do
        local liveGroup = IsLiveGroupAuraFrame(container and container._msufA3ParentFrame)
        if skipLiveGroup == true and liveGroup then
            -- Geometry is addon-owned and can be repaired without touching the
            -- native Aura cache, assignment, enabled state, or shown state.
            any = A3._SyncManagedAuraContainerGeometry(container, true) or any
        else
            local lane = container and container._msufA3NativeLaneConfig
            local deferSpellRecreate = container and container._msufA3SpellIndicatorRoot == true
            local recreateHelpfulContainer = recreateHelpfulAuras == true
                and not deferSpellRecreate
                and ContainerOwnsHelpfulAuras(container, lane)
            if deferSpellRecreate then
                spellRecreates = spellRecreates or {}
                spellRecreates[#spellRecreates + 1] = container
                any = true
            elseif recreateHelpfulContainer then
                helpfulRecreates = helpfulRecreates or {}
                helpfulRecreates[#helpfulRecreates + 1] = container
                any = true
            else
                local filterChanged = SyncCuratedBigDefensiveContainer(container)
                if container and A3._ManagedAuraContainerSupportsGeometryRepair(container) then
                    -- Hidden containers cannot be repaired in this pass. Keep the
                    -- request on the container so its next visible/config sync consumes
                    -- it instead of trusting stale desired-geometry metadata.
                    if container._msufA3SpellIndicatorRoot == true then
                        container._msufA3ForceSpellIndicatorGeometry = true
                    else
                        container._msufA3ForceManagedAuraGeometry = true
                    end
                end
                if container and type(container.UpdateAllAuras) == "function" then
                    if not filterChanged and A3._NativeContainerVisible(container) then
                        container:UpdateAllAuras()
                    end
                    -- Zone/world transitions can desync a reused container while cache looks current.
                    -- Keep the normal cached fast path by applying geometry repair only once here.
                    if container._msufA3ForceManagedAuraGeometry == true
                        or container._msufA3ForceSpellIndicatorGeometry == true then
                        A3._SyncManagedAuraContainerGeometry(container, true)
                    end
                    any = true
                end
            end
        end
    end
    -- A full UpdateAllAuras parse can retain the existing frame for the same
    -- aura instance without reassigning its stable duration object. If that
    -- object captured the early-login near-zero state, long-lived buffs keep
    -- rendering 0.1 even though their tooltip already has the correct expiry.
    -- Recreate every registered owner that contains a HELPFUL lane on
    -- PLAYER_ENTERING_WORLD so pre-existing buffs on player, target, focus,
    -- boss and group units all receive fresh duration assignments. Mixed
    -- group owners are recreated as one native container; harmful-only owners
    -- are left alone. This stays entirely off UNIT_AURA and identity hotpaths.
    if helpfulRecreates then
        for i = 1, #helpfulRecreates do
            local container = helpfulRecreates[i]
            local root = container and container._msufA3Root
            local lane = container and container._msufA3NativeLaneConfig
            local parentFrame = container and container._msufA3ParentFrame
            if container and container._msufA3GroupSlotsRoot == true then
                any = RecreateGroupSlots(container) ~= nil or any
            elseif root and lane then
                any = ApplyLane(root, lane, parentFrame, true) ~= nil or any
            end
        end
    end
    -- Recreating unregisters the old container and registers a replacement in
    -- the same per-unit set. Do it after iteration so the set is never mutated
    -- under pairs(). This is the safe PTR path for forbidden native buttons.
    if spellRecreates then
        for i = 1, #spellRecreates do
            any = SpellIndicatorsRuntime.Recreate(spellRecreates[i]) ~= nil or any
        end
    end
    if seedGroupAssist then
        -- PLAYER_ENTERING_WORLD may replace helpful containers instead of
        -- reparsing the registered instance in place. Let an already-dirty
        -- assist revision finish normally in that exceptional recreation pass;
        -- all in-place direct refreshes can adopt the satisfied parse.
        A3._UpdateGroupAuraAssistState(
            unit, false, true, false, recreateHelpfulAuras ~= true)
    end
    return any
end

-- The player token can simultaneously own a standalone ClassPower candidate
-- slot and the Party self-frame. Player disposition/taxi events must refresh
-- the former without bypassing the latter's assist-gated state machine.
A3._DirectIdentityRefreshNonGroupUnitBase = function(unit)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local any = false
    for container in pairs(containers) do
        if not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if not filterChanged and A3._NativeContainerVisible(container) then update(container) end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    return any
end

-- Selected only while at least one ordinary Unit-frame exact-ID owner exists.
-- The normal identity pass keeps gating, the existing native rebuild, and
-- geometry repair in the same per-unit owner loop. No UNIT_AURA branch, second
-- refresh, polling callback, or per-event table allocation is introduced.
A3._DirectIdentityRefreshUnitWithUnitAuraGate = function(
    unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    if not A3._UnitAuraIdentityUnitHasOwners(unit) then
        return A3._DirectIdentityRefreshUnitBase(
            unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    end
    if forceSpellIndicatorGeometry == true then
        -- World/login geometry repair is cold. Keep exact owners fail-closed
        -- across replacement, then seed the final registered instances once.
        A3._ApplyUnitAuraIdentityStateToUnit(unit, nil, false)
        local any = A3._DirectIdentityRefreshUnitBase(
            unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
        local state = A3._RefreshUnitAuraIdentityState(unit)
        if state and state.assistKnown == true then
            A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
        end
        return any
    end

    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local state = A3._RefreshUnitAuraIdentityState(unit)
    local canAssist = state and state.canAssist
    local assistKnown = state and state.assistKnown == true
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)
    local any = false
    for container in pairs(containers) do
        if skipLiveGroup ~= true
            or not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local identityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
            local identityEligible = true
            if identityGated then
                A3._SetUnitAuraIdentityOwnerReady(container, canAssist, false)
                identityEligible = assistKnown
                    and A3._UnitAuraIdentityOwnerVisible(container, canAssist)
            end
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if identityEligible and not filterChanged
                    and A3._NativeContainerVisible(container) then
                    update(container)
                end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    if state and state.assistKnown == true then
        A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    if seedGroupAssist then
        A3._UpdateGroupAuraAssistState(unit, false, true, false, true)
    end
    return any
end

A3._DirectIdentityRefreshNonGroupUnitWithUnitAuraGate = function(unit)
    if not A3._UnitAuraIdentityUnitHasOwners(unit) then
        return A3._DirectIdentityRefreshNonGroupUnitBase(unit)
    end
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local state = A3._RefreshUnitAuraIdentityState(unit)
    local canAssist = state and state.canAssist
    local assistKnown = state and state.assistKnown == true
    local any = false
    for container in pairs(containers) do
        if not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local identityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
            local identityEligible = true
            if identityGated then
                A3._SetUnitAuraIdentityOwnerReady(container, canAssist, false)
                identityEligible = assistKnown
                    and A3._UnitAuraIdentityOwnerVisible(container, canAssist)
            end
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if identityEligible and not filterChanged
                    and A3._NativeContainerVisible(container) then
                    update(container)
                end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    A3._SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    if state and state.assistKnown == true then
        A3._ScheduleUnitAuraIdentityReveal(unit, state.revision)
    end
    return any
end

A3._DirectIdentityRefreshUnit = A3._DirectIdentityRefreshUnitBase
A3._DirectIdentityRefreshNonGroupUnit = A3._DirectIdentityRefreshNonGroupUnitBase
A3._SyncUnitAuraIdentityRefreshRoute = function()
    local active = (A3._unitAuraIdentityOwnerCount or 0) > 0
    A3._DirectIdentityRefreshUnit = active
        and A3._DirectIdentityRefreshUnitWithUnitAuraGate
        or A3._DirectIdentityRefreshUnitBase
    A3._DirectIdentityRefreshNonGroupUnit = active
        and A3._DirectIdentityRefreshNonGroupUnitWithUnitAuraGate
        or A3._DirectIdentityRefreshNonGroupUnitBase
    return active
end

A3._DirectIdentityRefreshAll = function(
    groupOnly, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then return false end
    -- A recreation can temporarily remove and then re-add a unit key while
    -- swapping its final registered owner. Snapshot the unit tokens first so
    -- mutating the registry cannot make pairs() skip another unit family.
    local units = {}
    for unit in pairs(byUnit) do
        units[#units + 1] = unit
    end
    local any = false
    for i = 1, #units do
        if groupOnly == true then
            any = A3._DirectGroupPresenceRefreshUnit(units[i]) or any
        else
            any = A3._DirectIdentityRefreshUnit(
                units[i], forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup) or any
        end
    end
    return any
end

A3._FlushScheduledDirectIdentityRefreshAll = function()
    A3._directIdentityRefreshTimerPending = nil
    if A3._directIdentityRefreshPending ~= true then return false end
    if InCombat() then return false end
    local groupOnly = A3._directIdentityRefreshGroupOnly == true
    local forceSpellIndicatorGeometry = A3._directIdentityRefreshForceSpellIndicatorGeometry == true
    local recreateHelpfulAuras = A3._directIdentityRefreshRecreateHelpfulAuras == true
    local skipLiveGroup = A3._directIdentityRefreshSkipLiveGroup == true
    A3._directIdentityRefreshPending = nil
    A3._directIdentityRefreshGroupOnly = nil
    A3._directIdentityRefreshForceSpellIndicatorGeometry = nil
    A3._directIdentityRefreshRecreateHelpfulAuras = nil
    A3._directIdentityRefreshSkipLiveGroup = nil
    if not A3._HasDirectIdentityRefreshContainers() then return false end
    A3._DirectIdentityRefreshAll(
        groupOnly, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
end

A3._QueueDirectIdentityRefreshAllFlush = function()
    if A3._directIdentityRefreshPending ~= true
        or A3._directIdentityRefreshTimerPending == true
        or InCombat() then return false end
    A3._directIdentityRefreshTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledDirectIdentityRefreshAll)
    else
        A3._FlushScheduledDirectIdentityRefreshAll()
    end
    return true
end

-- Presence and world/geometry work can be invalidated by the same transition
-- while combat is active. Resume both cold queues through one next-frame job so
-- a portal+zone+world burst never allocates two post-combat timers.
A3._FlushDeferredDirectIdentityColdWork = function()
    A3._directIdentityColdResumeTimerPending = nil
    if InCombat() then return false end
    local any = A3._FlushScheduledGroupAuraPresenceRefreshAll()
    any = A3._FlushScheduledDirectIdentityRefreshAll() or any
    return any
end

A3._QueueDeferredDirectIdentityColdWork = function()
    if A3._directIdentityColdResumeTimerPending == true
        or (A3._groupAuraPresenceRefreshAllPending ~= true
            and A3._directIdentityRefreshPending ~= true) then return false end
    A3._directIdentityColdResumeTimerPending = true
    -- Reserve both constituent queues for this shared callback. Any OOC event
    -- arriving before it runs only merges flags instead of allocating another
    -- one-shot timer.
    A3._groupAuraPresenceRefreshAllTimerPending = true
    A3._directIdentityRefreshTimerPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushDeferredDirectIdentityColdWork)
    else
        A3._FlushDeferredDirectIdentityColdWork()
    end
    return true
end

A3._ScheduleDirectIdentityRefreshAll = function(
    groupOnly, forceSpellIndicatorGeometry, skipLiveGroup)
    if not A3._HasDirectIdentityRefreshContainers() then return false end
    if A3._directIdentityRefreshPending == true then
        if groupOnly ~= true then A3._directIdentityRefreshGroupOnly = nil end
        if forceSpellIndicatorGeometry == true then
            A3._directIdentityRefreshForceSpellIndicatorGeometry = true
        end
        if skipLiveGroup ~= true then A3._directIdentityRefreshSkipLiveGroup = nil end
        A3._QueueDirectIdentityRefreshAllFlush()
        return true
    end
    A3._directIdentityRefreshPending = true
    A3._directIdentityRefreshGroupOnly = groupOnly == true
    A3._directIdentityRefreshForceSpellIndicatorGeometry = forceSpellIndicatorGeometry == true
    A3._directIdentityRefreshSkipLiveGroup = skipLiveGroup == true
    A3._QueueDirectIdentityRefreshAllFlush()
    return true
end

-- Non-group identity owners retain the existing burst coalescer. Group owners
-- take the narrower UnitCanAssist state path above, so player events can refresh
-- standalone candidate slots without touching Party self-frame containers.
A3._FlushScheduledDirectIdentityEventRefresh = function()
    A3._directIdentityEventRefreshPending = nil
    local units = A3._directIdentityEventRefreshUnits
    if not units then return false end
    local any = false
    for unit, mode in pairs(units) do
        units[unit] = nil
        if mode == "nonGroup" then
            any = A3._DirectIdentityRefreshNonGroupUnit(unit) or any
        else
            any = A3._DirectIdentityRefreshUnit(unit) or any
        end
    end
    return any
end

A3._ScheduleDirectIdentityEventRefresh = function(unit, nonGroupOnly)
    if type(unit) ~= "string" or unit == "" then return false end
    local containers = A3._directIdentityAuraContainers
    containers = containers and containers[unit]
    if not (containers and next(containers)) then return false end
    local units = A3._directIdentityEventRefreshUnits
    if not units then
        units = {}
        A3._directIdentityEventRefreshUnits = units
    end
    local requestedMode = nonGroupOnly == true and "nonGroup" or "all"
    if units[unit] ~= "all" then units[unit] = requestedMode end
    if A3._directIdentityEventRefreshPending == true then return true end
    A3._directIdentityEventRefreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushScheduledDirectIdentityEventRefresh)
    else
        A3._FlushScheduledDirectIdentityEventRefresh()
    end
    return true
end

-- UNIT_FLAGS covers many unrelated player states. For the missing flightpath
-- lifecycle, only the taxi landing edge matters: parsing while UnitOnTaxi is
-- true can still use the transient reaction, while the false edge is the first
-- useful point to restore the configured candidate-filter assignments. Cache
-- this cold state so ordinary player flag churn never schedules an aura parse.
A3._UpdateDirectIdentityPlayerTaxiState = function()
    local unitOnTaxi = _G.UnitOnTaxi
    if type(unitOnTaxi) ~= "function" then return nil, nil end
    local onTaxi = unitOnTaxi("player")
    if issecretvalue(onTaxi) == true or onTaxi == nil then return nil, nil end
    local current = onTaxi == true
    local previous = A3._directIdentityPlayerOnTaxi
    A3._directIdentityPlayerOnTaxi = current
    return previous, current
end

-- The shared driver is active exactly while at least one eligible native
-- container exists. Its event set follows the active unit families so a
-- group-only runtime never receives target/focus/boss identity callbacks.
local directIdentityRefreshEventFrame
local directIdentityRefreshRegisteredEvents = {}
local directIdentityEventTopologyBatchDepth = 0
local directIdentityEventTopologySyncPending = false

-- Unit identity events can be noisy across every visible world unit. Keep the
-- group-token variants outside the shared global driver: stable four-token
-- RegisterUnitEvent shards match
-- Blizzard's 12.1 MAX_UNIT_TOKENS_IN_EVENT contract. A roster change only
-- rebuilds the affected cold topology; movement and foreign-unit flags never
-- enter Lua. A real flag edge on a registered raid token costs one cached
-- UnitCanAssist comparison and no aura rebuild when the value is unchanged.
A3._groupAuraAssistShardEvents = A3._groupAuraAssistShardEvents or {
    "UNIT_FLAGS", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_CONNECTION",
    "UNIT_OTHER_PARTY_CHANGED",
}
A3._GroupAuraAssistFlagBucket = function(unit)
    if issecretvalue(unit) == true or type(unit) ~= "string" then return nil end
    local partyIndex = tonumber(unit:match("^party(%d+)$"))
    if partyIndex and partyIndex >= 1 and partyIndex <= 4 then return 1 end
    local raidIndex = tonumber(unit:match("^raid(%d+)$"))
    if raidIndex and raidIndex >= 1 and raidIndex <= 40 then
        return 2 + math_floor((raidIndex - 1) / 4)
    end
    return nil
end

A3._ClearGroupAuraAssistFlagShards = function()
    local shards = A3._groupAuraAssistFlagShards
    if not shards then return false end
    for _, shard in pairs(shards) do
        shard:UnregisterAllEvents()
        shard._msufA3Units = nil
        shard._msufA3UnitSet = nil
        shard._msufA3AssistUnits = nil
        shard._msufA3AssistUnitSet = nil
        shard._msufA3Signature = nil
    end
    return true
end

A3._SyncGroupAuraAssistFlagShards = function()
    local desired = {}
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            local bucket = A3._GroupAuraAssistFlagBucket(unit)
            if bucket then
                local record = desired[bucket]
                if not record then
                    record = { units = {}, assistUnits = {} }
                    desired[bucket] = record
                end
                record.units[#record.units + 1] = unit
            end
        end
    end
    for unit, count in pairs(A3._groupAuraAssistOwnerCounts or {}) do
        if count > 0 then
            local bucket = A3._GroupAuraAssistFlagBucket(unit)
            local record = bucket and desired[bucket]
            if record then record.assistUnits[#record.assistUnits + 1] = unit end
        end
    end

    local shards = A3._groupAuraAssistFlagShards
    if not shards then
        if next(desired) == nil then return false end
        shards = {}
        A3._groupAuraAssistFlagShards = shards
    end
    for bucket, record in pairs(desired) do
        local units, assistUnits = record.units, record.assistUnits
        table_sort(units)
        table_sort(assistUnits)
        local signature = table_concat(units, "\030") .. "\029"
            .. table_concat(assistUnits, "\030")
        local shard = shards[bucket]
        if not shard then
            shard = CreateFrame("Frame")
            shard:SetScript("OnEvent", function(self, event, unit, arg2)
                local knownUnit = issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
                if knownUnit then
                    if event ~= "UNIT_FLAGS"
                        and self._msufA3UnitSet and self._msufA3UnitSet[unit] then
                        if InCombat() then
                            if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                                A3._UpdateGroupAuraPresencePhaseState(unit, false)
                            elseif event == "UNIT_CONNECTION" then
                                A3._UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
                            end
                            -- Map-ID, UnitInOtherParty and the composite scan
                            -- are deliberately cold and resume after combat.
                            A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                        else
                            A3._UpdateGroupAuraPresenceState(unit, false, false)
                        end
                    end
                    if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[unit] then
                        A3._UpdateGroupAuraAssistState(unit, false, false, false)
                    end
                    return
                end
                -- Restricted payload fallback stays bounded to this shard's at
                -- most four registered tokens and reads the transient edge now.
                local shardUnits = event == "UNIT_FLAGS"
                    and (self._msufA3AssistUnits or {}) or (self._msufA3Units or {})
                for i = 1, #shardUnits do
                    local shardUnit = shardUnits[i]
                    if event ~= "UNIT_FLAGS" then
                        if InCombat() then
                            if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                                A3._UpdateGroupAuraPresencePhaseState(shardUnit, false)
                            elseif event == "UNIT_CONNECTION" then
                                -- A restricted payload cannot safely be shared
                                -- across the shard. Fall back to one bounded
                                -- UnitIsConnected read per registered token.
                                A3._UpdateGroupAuraPresenceConnectionState(shardUnit, nil, false)
                            end
                        else
                            A3._UpdateGroupAuraPresenceState(shardUnit, false, false)
                        end
                    end
                    if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[shardUnit] then
                        A3._UpdateGroupAuraAssistState(shardUnit, false, false, false)
                    end
                end
                if event ~= "UNIT_FLAGS" and InCombat() then
                    A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                end
            end)
            shards[bucket] = shard
        end
        if shard._msufA3Signature ~= signature then
            shard:UnregisterAllEvents()
            shard._msufA3Units = units
            shard._msufA3UnitSet = {}
            for i = 1, #units do shard._msufA3UnitSet[units[i]] = true end
            shard._msufA3AssistUnits = assistUnits
            shard._msufA3AssistUnitSet = {}
            for i = 1, #assistUnits do
                shard._msufA3AssistUnitSet[assistUnits[i]] = true
            end
            shard._msufA3Signature = signature
            for eventIndex = 1, #A3._groupAuraAssistShardEvents do
                local event = A3._groupAuraAssistShardEvents[eventIndex]
                local eventUnits = event == "UNIT_FLAGS" and assistUnits or units
                if #eventUnits > 0 then
                    local registered = shard:RegisterUnitEvent(event, eventUnits)
                    if registered == false then
                        shard:UnregisterEvent(event)
                        local unpackUnits = _G.unpack or table.unpack
                        registered = unpackUnits and shard:RegisterUnitEvent(
                            event, unpackUnits(eventUnits, 1, #eventUnits)) or false
                        if registered == false then
                            -- Last-resort correctness fallback for a client rejecting
                            -- both documented forms. Foreign plain payloads are ignored.
                            shard:RegisterEvent(event)
                        end
                    end
                end
            end
        end
    end
    for bucket, shard in pairs(shards) do
        if desired[bucket] == nil then
            shard:UnregisterAllEvents()
            shard._msufA3Units = nil
            shard._msufA3UnitSet = nil
            shard._msufA3AssistUnits = nil
            shard._msufA3AssistUnitSet = nil
            shard._msufA3Signature = nil
        end
    end
    return next(desired) ~= nil
end

local function DirectIdentityBossUnit(unit)
    return unit == "boss1" or unit == "boss2" or unit == "boss3"
        or unit == "boss4" or unit == "boss5"
end

local function SetDirectIdentityRefreshEvent(frame, event, enabled, unit)
    local desiredMode = enabled == true and (unit and ("unit:" .. unit) or "global") or nil
    local currentMode = directIdentityRefreshRegisteredEvents[event]
    if currentMode == desiredMode then return end
    if currentMode ~= nil then
        frame:UnregisterEvent(event)
        directIdentityRefreshRegisteredEvents[event] = nil
    end
    if desiredMode ~= nil then
        if unit and type(frame.RegisterUnitEvent) == "function" then
            local registered = frame:RegisterUnitEvent(event, unit)
            if registered == false then
                frame:RegisterEvent(event)
                desiredMode = "global"
            end
        else
            frame:RegisterEvent(event)
        end
        directIdentityRefreshRegisteredEvents[event] = desiredMode
    end
end

local function SyncDirectIdentityRefreshEvents(frame)
    local byUnit = A3._directIdentityAuraContainers
    local hasAny, hasGroup, hasPlayer, hasTarget, hasFocus, hasBoss = false, false, false, false, false, false
    local hasGroupAssist = A3._HasGroupAuraAssistOwners()
    hasGroup = (A3._directIdentityGroupOwnerCount or 0) > 0
    if byUnit then
        for unit, containers in pairs(byUnit) do
            if containers and next(containers) then
                hasAny = true
                if not A3._IsGroupUnitToken(unit) then
                    if unit == "player" then
                        hasPlayer = true
                    elseif unit == "target" then
                        hasTarget = true
                    elseif unit == "focus" then
                        hasFocus = true
                    elseif DirectIdentityBossUnit(unit) then
                        hasBoss = true
                    end
                end
            else
                byUnit[unit] = nil
            end
        end
    end
    if not hasAny then return false end

    SetDirectIdentityRefreshEvent(frame, "PLAYER_ENTERING_WORLD", true)
    SetDirectIdentityRefreshEvent(frame, "ZONE_CHANGED_NEW_AREA", true)
    -- Cold Presence/world work can be queued by a transition that happens
    -- while combat lockdown is active. Keep one stable OOC resume callback;
    -- no combat-start callback or event-registration churn is introduced.
    SetDirectIdentityRefreshEvent(frame, "PLAYER_REGEN_ENABLED", hasAny)
    SetDirectIdentityRefreshEvent(frame, "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "UNIT_FACTION", true)
    SetDirectIdentityRefreshEvent(frame, "GROUP_ROSTER_UPDATE", hasGroup)
    -- Group-token payloads stay in the four-token shards. A player-side
    -- phase/connection edge can change the relative presence of every member,
    -- so keep one filtered rare-event observer while live Group owners exist.
    SetDirectIdentityRefreshEvent(frame, "UNIT_PHASE", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_CTR_OPTIONS", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_CONNECTION", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "UNIT_OTHER_PARTY_CHANGED", hasGroup, "player")
    SetDirectIdentityRefreshEvent(frame, "PARTY_MEMBER_ENABLE", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "PARTY_MEMBER_DISABLE", hasGroup)
    SetDirectIdentityRefreshEvent(frame, "PLAYER_CONTROL_LOST", hasPlayer or hasGroupAssist)
    if hasGroup then
        A3._SyncGroupAuraAssistFlagShards()
    else
        A3._ClearGroupAuraAssistFlagShards()
    end
    local playerOnTaxi
    if hasPlayer or hasGroupAssist then
        _, playerOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
    end
    -- Group-unit flags are handled by the four-token shards above. The shared
    -- driver binds only the player observer, and only while a taxi transition
    -- is active/unknown, then removes it immediately on the landing edge.
    SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS",
        (hasPlayer or hasGroupAssist) and playerOnTaxi ~= false, "player")
    SetDirectIdentityRefreshEvent(frame, "PLAYER_TARGET_CHANGED", hasTarget)
    SetDirectIdentityRefreshEvent(frame, "PLAYER_FOCUS_CHANGED", hasFocus)
    SetDirectIdentityRefreshEvent(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", hasBoss)
    return true
end

-- A secure Raid header can bind every visible child in one synchronous scan.
-- Each first container for a new unit changes the identity topology, but no
-- event can be delivered between those child applies. Defer the shared event
-- and four-token shard rebuild until the scan boundary so a 20/40-player cold
-- setup performs one authoritative topology pass instead of one pass per unit.
local function RequestDirectIdentityRefreshEventSync(frame)
    if directIdentityEventTopologyBatchDepth > 0 then
        directIdentityEventTopologySyncPending = true
        return true
    end
    directIdentityEventTopologySyncPending = false
    return SyncDirectIdentityRefreshEvents(frame)
end

A3._BeginDirectIdentityEventTopologyBatch = function()
    directIdentityEventTopologyBatchDepth = directIdentityEventTopologyBatchDepth + 1
    return directIdentityEventTopologyBatchDepth
end

A3._EndDirectIdentityEventTopologyBatch = function()
    if directIdentityEventTopologyBatchDepth <= 0 then return false end
    directIdentityEventTopologyBatchDepth = directIdentityEventTopologyBatchDepth - 1
    if directIdentityEventTopologyBatchDepth > 0
        or directIdentityEventTopologySyncPending ~= true then
        return false
    end
    directIdentityEventTopologySyncPending = false
    local frame = directIdentityRefreshEventFrame
    if not frame then return false end
    return SyncDirectIdentityRefreshEvents(frame)
end

local function DrainDirectIdentityEventTopologyBatch()
    local drained = directIdentityEventTopologyBatchDepth > 0
    while directIdentityEventTopologyBatchDepth > 0 do
        A3._EndDirectIdentityEventTopologyBatch()
    end
    return drained
end

local function DirectIdentityRefreshEventsAlreadyCover(unit)
    if directIdentityRefreshRegisteredEvents.PLAYER_ENTERING_WORLD == nil
        or directIdentityRefreshRegisteredEvents.ZONE_CHANGED_NEW_AREA == nil
        or directIdentityRefreshRegisteredEvents.PLAYER_REGEN_ENABLED == nil
        or directIdentityRefreshRegisteredEvents.UNIT_FACTION == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and directIdentityRefreshRegisteredEvents.ENTERED_DIFFERENT_INSTANCE_FROM_PARTY == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and directIdentityRefreshRegisteredEvents.GROUP_ROSTER_UPDATE == nil then
        return false
    end
    if (A3._directIdentityGroupOwnerCount or 0) > 0
        and (directIdentityRefreshRegisteredEvents.PARTY_MEMBER_ENABLE == nil
            or directIdentityRefreshRegisteredEvents.PARTY_MEMBER_DISABLE == nil) then
        return false
    end
    if unit == "player" then
        return directIdentityRefreshRegisteredEvents.PLAYER_CONTROL_LOST ~= nil
    end
    if unit == "target" then
        return directIdentityRefreshRegisteredEvents.PLAYER_TARGET_CHANGED ~= nil
    end
    if unit == "focus" then
        return directIdentityRefreshRegisteredEvents.PLAYER_FOCUS_CHANGED ~= nil
    end
    if DirectIdentityBossUnit(unit) then
        return directIdentityRefreshRegisteredEvents.INSTANCE_ENCOUNTER_ENGAGE_UNIT ~= nil
    end
    return true
end

A3._EnsureDirectIdentityRefreshFrame = function()
    if directIdentityRefreshEventFrame then return directIdentityRefreshEventFrame end
    local frame = A3._directIdentityAuraFrame
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", function(_, event, unit, arg2)
            if event == "PLAYER_REGEN_ENABLED" then
                if InCombat() then return end
                -- Drain every already-merged cold request through one shared
                -- next-frame job. Presence runs before the identity/geometry
                -- repair so composed output has its final OOC state first.
                A3._QueueDeferredDirectIdentityColdWork()
                return
            end
            if event == "PLAYER_CONTROL_LOST" then
                local _, isOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
                local hasGroupAssist = A3._HasGroupAuraAssistOwners()
                if hasGroupAssist then
                    SyncDirectIdentityRefreshEvents(frame)
                else
                    SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS", isOnTaxi ~= false, "player")
                end
                -- Capture a transient false state as early as possible. This is
                -- a direct rare-event scan, not a recurring flight/combat loop.
                if hasGroupAssist then A3._UpdateAllGroupAuraAssistStates(false, false) end
                return
            end
            if A3._directIdentityRefreshAllEvents[event] == true then
                if event == "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY" then
                    -- Payloadless portal notification: reconcile the hard
                    -- presence reasons once, but never invalidate native Aura
                    -- ownership. Identity filters are refreshed only if their
                    -- actual UnitCanAssist value changed.
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                    return
                end
                local initialOrReload = event == "PLAYER_ENTERING_WORLD"
                    and (unit == true or arg2 == true)
                A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                if initialOrReload then
                    A3._directIdentityRefreshRecreateHelpfulAuras = true
                end
                -- Login/reload retains the pre-existing duration repair. Normal
                -- zone/instance transitions repair addon-owned geometry but
                -- explicitly skip every live Group AuraContainer.
                A3._ScheduleDirectIdentityRefreshAll(false, true, not initialOrReload)
                return
            end
            if event == "GROUP_ROSTER_UPDATE" then
                -- Roster bursts can reuse the same unit token with a different
                -- GUID while UnitCanAssist remains true. Keep the 6.06 assist
                -- identity path combat-live, but defer the new 6.07 map/other-
                -- instance reconciliation until OOC.
                if InCombat() then
                    A3._UpdateAllGroupAuraPresenceIdentityStates()
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, false)
                    A3._ScheduleGroupAuraAssistRefreshAll(true, false)
                else
                    A3._ScheduleGroupAuraPresenceRefreshAll(true, true)
                end
                return
            end
            local groupAssistEvent = event == "UNIT_FACTION" or event == "UNIT_PHASE"
                or event == "UNIT_CTR_OPTIONS"
                or event == "UNIT_CONNECTION" or event == "UNIT_FLAGS"
                or event == "UNIT_OTHER_PARTY_CHANGED"
                or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE"
            if groupAssistEvent then
                local hasGroupAssist = A3._HasGroupAuraAssistOwners()
                local partyPresenceEvent = event == "PARTY_MEMBER_ENABLE"
                    or event == "PARTY_MEMBER_DISABLE"
                if partyPresenceEvent then
                    local knownGroupUnit = issecretvalue(unit) ~= true
                        and A3._IsGroupUnitToken(unit)
                    if knownGroupUnit then
                        A3._SetGroupAuraPresenceDisabled(
                            unit, event == "PARTY_MEMBER_DISABLE",
                            event == "PARTY_MEMBER_ENABLE")
                    elseif event == "PARTY_MEMBER_ENABLE" then
                        if InCombat() then
                            -- The restricted payload cannot identify the member.
                            -- Defer the bounded one-candidate latch release to the
                            -- same OOC group reconciliation as the broad scan.
                            A3._CaptureSingleGroupAuraPresenceDisabled()
                        else
                            A3._InvalidateSingleGroupAuraPresenceDisabled()
                        end
                    end
                    -- The payload is a useful directional hint, but Blizzard's
                    -- own PartyFrame treats these events group-wide. Reconcile
                    -- once without reparsing, disabling, or hiding a container.
                    A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    if hasGroupAssist then
                        A3._UpdateAllGroupAuraAssistStates(false, false)
                    end
                    return
                end
                if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
                    -- The payload itself may be restricted even though the
                    -- registered party/raid tokens are ordinary strings. Read
                    -- those states now: deferring two cinematic flag events to
                    -- one final-value scan could otherwise miss the transient
                    -- false edge that makes the native filter stale.
                    if hasGroupAssist then A3._UpdateAllGroupAuraAssistStates(false, false) end
                    A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    return
                end
                local taxiLanding, refreshNonGroup = false, event == "UNIT_FACTION"
                if event == "UNIT_FLAGS" and unit == "player" then
                    local wasOnTaxi, isOnTaxi = A3._UpdateDirectIdentityPlayerTaxiState()
                    taxiLanding = wasOnTaxi == true and isOnTaxi == false
                    refreshNonGroup = wasOnTaxi == nil or isOnTaxi == nil or taxiLanding
                    if isOnTaxi == false then
                        SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS", false)
                    end
                end

                if hasGroupAssist then
                    if unit == "player" then
                        -- A player disposition edge changes the observer side of
                        -- UnitCanAssist("player", raidN), so evaluate each active
                        -- assist-gated token once. Taxi landing forces one repair
                        -- even if a short false interval escaped the final cache.
                        if event ~= "UNIT_FLAGS" or refreshNonGroup then
                            A3._UpdateAllGroupAuraAssistStates(false, taxiLanding)
                        end
                    elseif A3._IsGroupUnitToken(unit) then
                        A3._UpdateGroupAuraAssistState(unit, false, false, false)
                    end
                end

                if event ~= "UNIT_FACTION" and event ~= "UNIT_FLAGS" then
                    if InCombat() then
                        if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                            if unit == "player" then
                                A3._UpdateAllGroupAuraPresencePhaseStates()
                            elseif A3._IsGroupUnitToken(unit) then
                                A3._UpdateGroupAuraPresencePhaseState(unit, false)
                            end
                        elseif event == "UNIT_CONNECTION" and A3._IsGroupUnitToken(unit) then
                            A3._UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
                        end
                        A3._ScheduleGroupAuraPresenceRefreshAll(false, false)
                    elseif unit == "player" then
                        A3._ScheduleGroupAuraPresenceRefreshAll(false)
                    elseif A3._IsGroupUnitToken(unit) then
                        A3._UpdateGroupAuraPresenceState(unit, false, false)
                    end
                end

                if refreshNonGroup and (unit == "player" or not A3._IsGroupUnitToken(unit)) then
                    A3._ScheduleDirectIdentityEventRefresh(unit, unit == "player")
                end
                return
            end
            local units = A3._directIdentityEventUnits[event]
            if not units then return end
            local deferBossBurst = event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
            for i = 1, #units do
                if deferBossBurst then
                    -- Blizzard refreshes all boss tokens synchronously and can
                    -- repeat the notification while a reset settles. Native
                    -- AuraContainer reparses are the expensive follower here;
                    -- merge the burst through the existing identity scheduler
                    -- instead of running every Boss lane inside the event tick.
                    A3._ScheduleDirectIdentityEventRefresh(units[i])
                else
                    A3._DirectIdentityRefreshUnit(units[i])
                end
            end
        end)
        A3._directIdentityAuraFrame = frame
    end
    directIdentityRefreshEventFrame = frame
    return frame
end

A3._RegisterUnitAuraIdentityOwner = function(container, unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    if not owners then
        owners = {}
        A3._unitAuraIdentityOwnersByUnit = owners
    end
    local set = owners[unit]
    if not set then
        set = {}
        owners[unit] = set
    end
    if set[container] == true then return false end
    set[container] = true
    A3._unitAuraIdentityOwnerCount = (A3._unitAuraIdentityOwnerCount or 0) + 1
    A3._EnsureUnitAuraIdentityState(unit)
    A3._SyncUnitAuraIdentityRefreshRoute()
    return true
end

A3._UnregisterUnitAuraIdentityOwner = function(container, unit)
    local owners = A3._unitAuraIdentityOwnersByUnit
    local set = owners and owners[unit]
    if not (set and set[container] == true) then return false end
    set[container] = nil
    A3._unitAuraIdentityOwnerCount = math_max(0, (A3._unitAuraIdentityOwnerCount or 0) - 1)
    if not next(set) then
        owners[unit] = nil
        local states = A3._unitAuraIdentityState
        if states then states[unit] = nil end
        local revealUnits = A3._unitAuraIdentityRevealUnits
        if revealUnits then revealUnits[unit] = nil end
    end
    A3._SyncUnitAuraIdentityRefreshRoute()
    return true
end

A3._RegisterDirectIdentityRefreshContainer = function(container)
    local unit = container and container.unit
    if not container or container._msufA3SkipDirectIdentityRefresh == true
        or not A3._DirectIdentityRefreshUnitEligible(unit) then
        A3._UnregisterDirectIdentityRefreshContainer(container)
        return false
    end
    if not A3._directIdentityAuraContainers then
        A3._directIdentityAuraContainers = {}
        A3._groupAuraAssistOwnerCount = 0
        A3._directIdentityGroupOwnerCount = 0
        A3._directIdentityGroupOwnerCounts = {}
    end
    A3._groupAuraAssistOwnerCounts = A3._groupAuraAssistOwnerCounts or {}
    A3._directIdentityGroupOwnerCounts = A3._directIdentityGroupOwnerCounts or {}
    local oldUnit = container._msufA3DirectIdentityUnit
    local oldAssistGated = container._msufA3DirectIdentityAssistGated == true
    local oldGroupOwner = container._msufA3DirectIdentityGroupOwner == true
    local oldUnitIdentityGated = container._msufA3DirectIdentityUnitGated == true
    local unitIdentityGated = A3._ContainerOwnsUnitAuraIdentityGate(container)
    local topologyChanged = false
    local ownerCounts = A3._groupAuraAssistOwnerCounts
    local groupCounts = A3._directIdentityGroupOwnerCounts
    local oldUnitAssistCountBefore = oldUnit and (ownerCounts[oldUnit] or 0) or 0
    local newUnitAssistCountBefore = ownerCounts[unit] or 0
    local totalAssistCountBefore = A3._groupAuraAssistOwnerCount or 0
    local totalGroupCountBefore = A3._directIdentityGroupOwnerCount or 0
    local oldUnitGroupCountBefore = oldUnit and (groupCounts[oldUnit] or 0) or 0
    local newUnitGroupCountBefore = groupCounts[unit] or 0
    if oldUnit and oldUnit ~= unit then
        local oldSet = A3._directIdentityAuraContainers[oldUnit]
        if oldSet then
            oldSet[container] = nil
            if not next(oldSet) then
                A3._directIdentityAuraContainers[oldUnit] = nil
                topologyChanged = true
            end
        end
    end
    local set = A3._directIdentityAuraContainers[unit]
    if not set then
        set = {}
        A3._directIdentityAuraContainers[unit] = set
        topologyChanged = true
    end
    set[container] = true
    container._msufA3DirectIdentityUnit = unit
    if oldUnitIdentityGated and (oldUnit ~= unit or not unitIdentityGated) then
        A3._UnregisterUnitAuraIdentityOwner(container, oldUnit)
    end
    if unitIdentityGated and (not oldUnitIdentityGated or oldUnit ~= unit) then
        A3._RegisterUnitAuraIdentityOwner(container, unit)
    end
    local assistGated = A3._ContainerOwnsGroupAuraAssistGate(container)
    local groupOwner = IsLiveGroupAuraFrame(container._msufA3ParentFrame)
    container._msufA3DirectIdentityUnitGated = unitIdentityGated == true
    container._msufA3DirectIdentityAssistGated = assistGated == true
    container._msufA3DirectIdentityGroupOwner = groupOwner == true
    if oldAssistGated and (oldUnit ~= unit or not assistGated) then
        ownerCounts[oldUnit] = math_max(0, (ownerCounts[oldUnit] or 0) - 1)
        if ownerCounts[oldUnit] == 0 then ownerCounts[oldUnit] = nil end
        A3._groupAuraAssistOwnerCount = math_max(0, (A3._groupAuraAssistOwnerCount or 0) - 1)
    end
    if assistGated and (not oldAssistGated or oldUnit ~= unit) then
        ownerCounts[unit] = (ownerCounts[unit] or 0) + 1
        A3._groupAuraAssistOwnerCount = (A3._groupAuraAssistOwnerCount or 0) + 1
    end
    if oldGroupOwner and (oldUnit ~= unit or not groupOwner) then
        groupCounts[oldUnit] = math_max(0, (groupCounts[oldUnit] or 0) - 1)
        if groupCounts[oldUnit] == 0 then groupCounts[oldUnit] = nil end
        A3._directIdentityGroupOwnerCount = math_max(
            0, (A3._directIdentityGroupOwnerCount or 0) - 1)
    end
    if groupOwner and (not oldGroupOwner or oldUnit ~= unit) then
        groupCounts[unit] = (groupCounts[unit] or 0) + 1
        A3._directIdentityGroupOwnerCount = (A3._directIdentityGroupOwnerCount or 0) + 1
    end
    local assistUnitTopologyChanged = oldUnit ~= nil
        and ((oldUnitAssistCountBefore == 0) ~= ((ownerCounts[oldUnit] or 0) == 0))
        or ((newUnitAssistCountBefore == 0) ~= ((ownerCounts[unit] or 0) == 0))
    local assistGlobalTopologyChanged = (totalAssistCountBefore == 0)
        ~= ((A3._groupAuraAssistOwnerCount or 0) == 0)
    local groupGlobalTopologyChanged = (totalGroupCountBefore == 0)
        ~= ((A3._directIdentityGroupOwnerCount or 0) == 0)
    local groupUnitTopologyChanged = oldUnit ~= nil
        and ((oldUnitGroupCountBefore == 0) ~= ((groupCounts[oldUnit] or 0) == 0))
        or ((newUnitGroupCountBefore == 0) ~= ((groupCounts[unit] or 0) == 0))
    if oldUnit and oldUnit ~= unit and oldAssistGated
        and not A3._GroupAuraAssistUnitHasOwners(oldUnit) then
        local states = A3._groupAuraAssistState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldAssistGated and not assistGated
        and not A3._GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
    end
    if oldUnit and oldUnit ~= unit and not A3._GroupAuraPresenceUnitHasOwners(oldUnit) then
        local states = A3._groupAuraPresenceState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldGroupOwner and not groupOwner
        and not A3._GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    local frame = A3._EnsureDirectIdentityRefreshFrame()
    -- A visible boss frame commonly registers three native lanes, and five
    -- bosses can appear in the same callback. The first lane establishes the
    -- shared boss event; rescanning every per-unit container and repeating all
    -- five RegisterEvent state checks for the other fourteen lanes is pure
    -- lifecycle overhead. Additions can take this O(1) coverage gate. Rebinds
    -- that removed a unit family still use the authoritative topology scan so
    -- no obsolete target/focus/boss subscription can survive.
    if topologyChanged or assistUnitTopologyChanged or assistGlobalTopologyChanged
        or groupGlobalTopologyChanged or groupUnitTopologyChanged
        or (assistGated and directIdentityRefreshRegisteredEvents.GROUP_ROSTER_UPDATE == nil)
        or not DirectIdentityRefreshEventsAlreadyCover(unit) then
        RequestDirectIdentityRefreshEventSync(frame)
    end
    if groupOwner then
        local presenceState = A3._groupAuraPresenceState
            and A3._groupAuraPresenceState[unit]
        if presenceState and presenceState.initialized == true then
            A3._ApplyGroupAuraPresenceFrame(container._msufA3ParentFrame,
                presenceState.present ~= false, unit, presenceState.revision or 0)
            A3._ApplyGroupAuraPresenceContainer(container,
                presenceState.present ~= false,
                A3._groupAuraAssistState and A3._groupAuraAssistState[unit])
        end
    end
    if unitIdentityGated then A3._SeedUnitAuraIdentityOwner(container, unit) end
    return true
end

A3._UnregisterDirectIdentityRefreshContainer = function(container)
    local unit = container and container._msufA3DirectIdentityUnit
    if not unit then return end
    local wasAssistGated = container._msufA3DirectIdentityAssistGated == true
    local wasGroupOwner = container._msufA3DirectIdentityGroupOwner == true
    local wasUnitIdentityGated = container._msufA3DirectIdentityUnitGated == true
    local unitAssistCountBefore = A3._groupAuraAssistOwnerCounts
        and (A3._groupAuraAssistOwnerCounts[unit] or 0) or 0
    local totalAssistCountBefore = A3._groupAuraAssistOwnerCount or 0
    local totalGroupCountBefore = A3._directIdentityGroupOwnerCount or 0
    local unitGroupCountBefore = A3._directIdentityGroupOwnerCounts
        and (A3._directIdentityGroupOwnerCounts[unit] or 0) or 0
    local topologyChanged = false
    local byUnit = A3._directIdentityAuraContainers
    local set = byUnit and byUnit[unit]
    if set then
        set[container] = nil
        if not next(set) then
            byUnit[unit] = nil
            topologyChanged = true
            if unit == "player" then A3._directIdentityPlayerOnTaxi = nil end
        end
    end
    container._msufA3DirectIdentityUnit = nil
    container._msufA3DirectIdentityAssistGated = nil
    container._msufA3DirectIdentityGroupOwner = nil
    container._msufA3DirectIdentityUnitGated = nil
    if wasUnitIdentityGated then A3._UnregisterUnitAuraIdentityOwner(container, unit) end
    if wasAssistGated then
        local ownerCounts = A3._groupAuraAssistOwnerCounts
        if ownerCounts then
            ownerCounts[unit] = math_max(0, (ownerCounts[unit] or 0) - 1)
            if ownerCounts[unit] == 0 then ownerCounts[unit] = nil end
        end
        A3._groupAuraAssistOwnerCount = math_max(0, (A3._groupAuraAssistOwnerCount or 0) - 1)
    end
    if wasGroupOwner then
        local groupCounts = A3._directIdentityGroupOwnerCounts
        if groupCounts then
            groupCounts[unit] = math_max(0, (groupCounts[unit] or 0) - 1)
            if groupCounts[unit] == 0 then groupCounts[unit] = nil end
        end
        A3._directIdentityGroupOwnerCount = math_max(
            0, (A3._directIdentityGroupOwnerCount or 0) - 1)
    end
    local assistUnitTopologyChanged = wasAssistGated and unitAssistCountBefore == 1
    local assistGlobalTopologyChanged = wasAssistGated and totalAssistCountBefore == 1
    local groupGlobalTopologyChanged = wasGroupOwner and totalGroupCountBefore == 1
    local groupUnitTopologyChanged = wasGroupOwner and unitGroupCountBefore == 1
    if wasAssistGated and not A3._GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
        local refreshUnits = A3._groupAuraAssistRefreshUnits
        if refreshUnits then refreshUnits[unit] = nil end
        local revealUnits = A3._groupAuraAssistRevealUnits
        if revealUnits then revealUnits[unit] = nil end
    end
    if wasGroupOwner and not A3._GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    if not A3._HasDirectIdentityRefreshContainers() then
        A3._directIdentityRefreshPending = nil
        A3._directIdentityRefreshTimerPending = nil
        A3._directIdentityColdResumeTimerPending = nil
        A3._directIdentityRefreshGroupOnly = nil
        A3._directIdentityRefreshForceSpellIndicatorGeometry = nil
        A3._directIdentityRefreshRecreateHelpfulAuras = nil
        A3._directIdentityRefreshSkipLiveGroup = nil
        A3._groupAuraAssistState = nil
        A3._groupAuraAssistOwnerCount = 0
        A3._groupAuraAssistOwnerCounts = nil
        A3._directIdentityGroupOwnerCount = 0
        A3._directIdentityGroupOwnerCounts = nil
        A3._groupAuraPresenceState = nil
        A3._groupAuraPresenceRefreshAllPending = nil
        A3._groupAuraPresenceRefreshAllTimerPending = nil
        A3._groupAuraPresenceRefreshAllCheckIdentity = nil
        A3._groupAuraPresenceRefreshAllCheckAssist = nil
        A3._groupAuraPresenceRefreshAllEnableCandidate = nil
        A3._groupAuraPresenceRefreshAllEnableCandidateRevision = nil
        A3._groupAuraPresenceRefreshAllEnableCandidateState = nil
        A3._groupAuraAssistRefreshUnits = nil
        A3._groupAuraAssistRefreshPending = nil
        A3._groupAuraAssistRevealUnits = nil
        A3._groupAuraAssistRevealPending = nil
        A3._groupAuraAssistRefreshAllPending = nil
        A3._groupAuraAssistRefreshAllCheckIdentity = nil
        A3._groupAuraAssistRefreshAllForce = nil
        A3._unitAuraIdentityOwnersByUnit = nil
        A3._unitAuraIdentityOwnerCount = 0
        A3._unitAuraIdentityState = nil
        A3._unitAuraIdentityRevealUnits = nil
        A3._SyncUnitAuraIdentityRefreshRoute()
        local frame = A3._directIdentityAuraFrame
        if frame then frame:UnregisterAllEvents() end
        A3._ClearGroupAuraAssistFlagShards()
        directIdentityRefreshRegisteredEvents = {}
        directIdentityRefreshEventFrame = nil
    elseif topologyChanged or assistUnitTopologyChanged or assistGlobalTopologyChanged
        or groupGlobalTopologyChanged or groupUnitTopologyChanged then
        RequestDirectIdentityRefreshEventSync(directIdentityRefreshEventFrame)
    end
end

return {
    DrainDirectIdentityEventTopologyBatch = DrainDirectIdentityEventTopologyBatch,
    -- Bootstrap-only cycle resolution; no lookup or forwarding wrapper is added to events.
    Bind = function(dependencies)
        ApplyLane = dependencies.ApplyLane
        RecreateGroupSlots = dependencies.RecreateGroupSlots
    end,
}
end
