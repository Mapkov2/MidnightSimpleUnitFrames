-- Auras3 runtime: IdentityRefresh.
-- Coalesced identity refresh through one parameterized owner loop.
local _, MSUF = ...
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.IdentityRefresh = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Containers = Runtime.Containers
local Identity = Runtime.Identity
local IdentityRefresh = Runtime.IdentityRefresh
local Presence = Runtime.Presence
local next, pairs, type = next, pairs, type
local RunNextFrame = dependencies.Platform.RunNextFrame
local InCombat = dependencies.Platform.InCombat
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local SyncCuratedBigDefensiveContainer = dependencies.Presence.SyncCuratedBigDefensiveContainer
local issecretvalue = dependencies.Platform.issecretvalue

local WorldTransition = dependencies.WorldTransition
-- Presence transitions never invalidate native aura ownership.  They only
-- recompute the plain per-unit output gate; the still-enabled containers keep
-- their incremental UNIT_AURA stream while absent.
IdentityRefresh.DirectGroupPresenceRefreshUnit = function(unit)
    return Presence.UpdateGroupAuraPresenceState(unit, false, false)
end

local function RefreshOwners(unit, skipLiveGroup, gateIdentity, seedGroupAssist)
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    local state = gateIdentity and Identity.RefreshUnitAuraIdentityState(unit) or nil
    local canAssist = state and state.canAssist
    local assistKnown = state and state.assistKnown == true
    local any = false
    for container in pairs(containers) do
        if skipLiveGroup ~= true
            or not IsLiveGroupAuraFrame(container and container._msufA3ParentFrame) then
            local identityEligible = true
            if gateIdentity and Identity.ContainerOwnsUnitAuraIdentityGate(container) then
                Identity.SetUnitAuraIdentityOwnerReady(container, canAssist, false)
                identityEligible = assistKnown and Identity.UnitAuraIdentityOwnerVisible(container, canAssist)
            end
            local filterChanged = SyncCuratedBigDefensiveContainer(container)
            local update = container and container.UpdateAllAuras
            if type(update) == "function" then
                if identityEligible and not filterChanged and Containers.NativeContainerVisible(container) then update(container) end
                if container._msufA3ForceManagedAuraGeometry == true
                    or container._msufA3ForceSpellIndicatorGeometry == true then
                    Containers.SyncManagedAuraContainerGeometry(container, true)
                end
                any = true
            end
        end
    end
    if state and state.assistKnown == true then Identity.ScheduleUnitAuraIdentityReveal(unit, state.revision) end
    if seedGroupAssist then Identity.UpdateGroupAuraAssistState(unit, false, true, false, true) end
    return any
end

IdentityRefresh.DirectIdentityRefreshUnitBase = function(unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)
    if forceSpellIndicatorGeometry ~= true then return RefreshOwners(unit, skipLiveGroup, false, seedGroupAssist) end
    local byUnit = A3._directIdentityAuraContainers
    local containers = byUnit and byUnit[unit]
    if not containers then return false end
    return WorldTransition.RefreshUnit(unit, containers, recreateHelpfulAuras, skipLiveGroup, seedGroupAssist)
end

-- Player disposition events must leave the Party self-frame's gate intact.
IdentityRefresh.DirectIdentityRefreshNonGroupUnitBase = function(unit)
    return RefreshOwners(unit, true, false, false)
end

IdentityRefresh.DirectIdentityRefreshUnitWithUnitAuraGate = function(
    unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    if not Identity.UnitAuraIdentityUnitHasOwners(unit) then
        return IdentityRefresh.DirectIdentityRefreshUnitBase(unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
    end
    if forceSpellIndicatorGeometry == true then
        Identity.ApplyUnitAuraIdentityStateToUnit(unit, nil, false)
        local any = IdentityRefresh.DirectIdentityRefreshUnitBase(unit, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
        local state = Identity.RefreshUnitAuraIdentityState(unit)
        if state and state.assistKnown == true then Identity.ScheduleUnitAuraIdentityReveal(unit, state.revision) end
        return any
    end
    local seedGroupAssist = skipLiveGroup ~= true
        and (unit == "player" or A3._directIdentityRefreshUnits[unit] ~= true)
    return RefreshOwners(unit, skipLiveGroup, true, seedGroupAssist)
end

IdentityRefresh.DirectIdentityRefreshNonGroupUnitWithUnitAuraGate = function(unit)
    return RefreshOwners(unit, true, Identity.UnitAuraIdentityUnitHasOwners(unit), false)
end

IdentityRefresh.DirectIdentityRefreshUnit = IdentityRefresh.DirectIdentityRefreshUnitBase
IdentityRefresh.DirectIdentityRefreshNonGroupUnit = IdentityRefresh.DirectIdentityRefreshNonGroupUnitBase
IdentityRefresh.SyncUnitAuraIdentityRefreshRoute = function()
    local active = (A3._unitAuraIdentityOwnerCount or 0) > 0
    IdentityRefresh.DirectIdentityRefreshUnit = active
        and IdentityRefresh.DirectIdentityRefreshUnitWithUnitAuraGate
        or IdentityRefresh.DirectIdentityRefreshUnitBase
    IdentityRefresh.DirectIdentityRefreshNonGroupUnit = active
        and IdentityRefresh.DirectIdentityRefreshNonGroupUnitWithUnitAuraGate
        or IdentityRefresh.DirectIdentityRefreshNonGroupUnitBase
    return active
end

IdentityRefresh.DirectIdentityRefreshAll = function(
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
            any = IdentityRefresh.DirectGroupPresenceRefreshUnit(units[i]) or any
        else
            any = IdentityRefresh.DirectIdentityRefreshUnit(
                units[i], forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup) or any
        end
    end
    return any
end

IdentityRefresh.FlushScheduledDirectIdentityRefreshAll = function()
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
    if not Identity.HasDirectIdentityRefreshContainers() then return false end
    IdentityRefresh.DirectIdentityRefreshAll(
        groupOnly, forceSpellIndicatorGeometry, recreateHelpfulAuras, skipLiveGroup)
end

IdentityRefresh.QueueDirectIdentityRefreshAllFlush = function()
    if A3._directIdentityRefreshPending ~= true
        or A3._directIdentityRefreshTimerPending == true
        or InCombat() then return false end
    A3._directIdentityRefreshTimerPending = true
    RunNextFrame(IdentityRefresh.FlushScheduledDirectIdentityRefreshAll)
    return true
end

-- Presence and world/geometry work can be invalidated by the same transition
-- while combat is active. Resume both cold queues through one next-frame job so
-- a portal+zone+world burst never allocates two post-combat timers.
IdentityRefresh.FlushDeferredDirectIdentityColdWork = function()
    A3._directIdentityColdResumeTimerPending = nil
    if InCombat() then return false end
    local any = Presence.FlushScheduledGroupAuraPresenceRefreshAll()
    any = IdentityRefresh.FlushScheduledDirectIdentityRefreshAll() or any
    return any
end

IdentityRefresh.QueueDeferredDirectIdentityColdWork = function()
    if A3._directIdentityColdResumeTimerPending == true
        or (A3._groupAuraPresenceRefreshAllPending ~= true
            and A3._directIdentityRefreshPending ~= true) then return false end
    A3._directIdentityColdResumeTimerPending = true
    -- Reserve both constituent queues for this shared callback. Any OOC event
    -- arriving before it runs only merges flags instead of allocating another
    -- one-shot timer.
    A3._groupAuraPresenceRefreshAllTimerPending = true
    A3._directIdentityRefreshTimerPending = true
    RunNextFrame(IdentityRefresh.FlushDeferredDirectIdentityColdWork)
    return true
end

IdentityRefresh.ScheduleDirectIdentityRefreshAll = function(
    groupOnly, forceSpellIndicatorGeometry, skipLiveGroup)
    if not Identity.HasDirectIdentityRefreshContainers() then return false end
    if A3._directIdentityRefreshPending == true then
        if groupOnly ~= true then A3._directIdentityRefreshGroupOnly = nil end
        if forceSpellIndicatorGeometry == true then
            A3._directIdentityRefreshForceSpellIndicatorGeometry = true
        end
        if skipLiveGroup ~= true then A3._directIdentityRefreshSkipLiveGroup = nil end
        IdentityRefresh.QueueDirectIdentityRefreshAllFlush()
        return true
    end
    A3._directIdentityRefreshPending = true
    A3._directIdentityRefreshGroupOnly = groupOnly == true
    A3._directIdentityRefreshForceSpellIndicatorGeometry = forceSpellIndicatorGeometry == true
    A3._directIdentityRefreshSkipLiveGroup = skipLiveGroup == true
    IdentityRefresh.QueueDirectIdentityRefreshAllFlush()
    return true
end

-- Non-group identity owners retain the existing burst coalescer. Group owners
-- take the narrower UnitCanAssist state path above, so player events can refresh
-- standalone candidate slots without touching Party self-frame containers.
IdentityRefresh.FlushScheduledDirectIdentityEventRefresh = function()
    A3._directIdentityEventRefreshPending = nil
    local units = A3._directIdentityEventRefreshUnits
    if not units then return false end
    local any = false
    for unit, mode in pairs(units) do
        units[unit] = nil
        if mode == "nonGroup" then
            any = IdentityRefresh.DirectIdentityRefreshNonGroupUnit(unit) or any
        else
            any = IdentityRefresh.DirectIdentityRefreshUnit(unit) or any
        end
    end
    return any
end

IdentityRefresh.ScheduleDirectIdentityEventRefresh = function(unit, nonGroupOnly)
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
    RunNextFrame(IdentityRefresh.FlushScheduledDirectIdentityEventRefresh)
    return true
end

-- UNIT_FLAGS covers many unrelated player states. For the missing flightpath
-- lifecycle, only the taxi landing edge matters: parsing while UnitOnTaxi is
-- true can still use the transient reaction, while the false edge is the first
-- useful point to restore the configured candidate-filter assignments. Cache
-- this cold state so ordinary player flag churn never schedules an aura parse.
IdentityRefresh.UpdateDirectIdentityPlayerTaxiState = function()
    local unitOnTaxi = UnitOnTaxi
    if type(unitOnTaxi) ~= "function" then return nil, nil end
    local onTaxi = unitOnTaxi("player")
    if issecretvalue(onTaxi) == true or onTaxi == nil then return nil, nil end
    local current = onTaxi == true
    local previous = A3._directIdentityPlayerOnTaxi
    A3._directIdentityPlayerOnTaxi = current
    return previous, current
end

return IdentityRefresh
end
