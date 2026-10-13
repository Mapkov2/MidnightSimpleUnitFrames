-- Auras3 runtime: IdentityEvents.
-- Native identity event dispatch. Topology, coalescing and world repair have separate owners.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.IdentityEvents = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Identity = Runtime.Identity
local IdentityRefresh = Runtime.IdentityRefresh
local Presence = Runtime.Presence
local pairs = pairs
local type = type
local InCombat = dependencies.Platform.InCombat
local issecretvalue = dependencies.Platform.issecretvalue

local WorldTransition = dependencies.WorldTransition
local Topology = dependencies.IdentityTopology
local SyncDirectIdentityRefreshEvents = Topology.SyncDirectIdentityRefreshEvents
local SetDirectIdentityRefreshEvent = Topology.SetDirectIdentityRefreshEvent
local function HandleGroupAssistEvent(frame, event, unit, arg2)
    local hasGroupAssist = Identity.HasGroupAuraAssistOwners()
    local partyPresenceEvent = event == "PARTY_MEMBER_ENABLE"
        or event == "PARTY_MEMBER_DISABLE"
    if partyPresenceEvent then
        local knownGroupUnit = issecretvalue(unit) ~= true
            and Identity.IsGroupUnitToken(unit)
        if knownGroupUnit then
            Presence.SetGroupAuraPresenceDisabled(
                unit, event == "PARTY_MEMBER_DISABLE",
                event == "PARTY_MEMBER_ENABLE")
        elseif event == "PARTY_MEMBER_ENABLE" then
            if InCombat() then
                -- The restricted payload cannot identify the member.
                -- Defer the bounded one-candidate latch release to the
                -- same OOC group reconciliation as the broad scan.
                Presence.CaptureSingleGroupAuraPresenceDisabled()
            else
                Presence.InvalidateSingleGroupAuraPresenceDisabled()
            end
        end
        -- The payload is a useful directional hint, but Blizzard's
        -- own PartyFrame treats these events group-wide. Reconcile
        -- once without reparsing, disabling, or hiding a container.
        Presence.ScheduleGroupAuraPresenceRefreshAll(false)
        if hasGroupAssist then
            Identity.UpdateAllGroupAuraAssistStates(false, false)
        end
        return
    end
    if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then
        -- The payload itself may be restricted even though the
        -- registered party/raid tokens are ordinary strings. Read
        -- those states now: deferring two cinematic flag events to
        -- one final-value scan could otherwise miss the transient
        -- false edge that makes the native filter stale.
        if hasGroupAssist then Identity.UpdateAllGroupAuraAssistStates(false, false) end
        Presence.ScheduleGroupAuraPresenceRefreshAll(false)
        return
    end
    local taxiLanding, refreshNonGroup = false, event == "UNIT_FACTION"
    if event == "UNIT_FLAGS" and unit == "player" then
        local wasOnTaxi, isOnTaxi = IdentityRefresh.UpdateDirectIdentityPlayerTaxiState()
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
                Identity.UpdateAllGroupAuraAssistStates(false, taxiLanding)
            end
        elseif Identity.IsGroupUnitToken(unit) then
            Identity.UpdateGroupAuraAssistState(unit, false, false, false)
        end
    end

    if event ~= "UNIT_FACTION" and event ~= "UNIT_FLAGS" then
        if InCombat() then
            if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                if unit == "player" then
                    Presence.UpdateAllGroupAuraPresencePhaseStates()
                elseif Identity.IsGroupUnitToken(unit) then
                    Presence.UpdateGroupAuraPresencePhaseState(unit, false)
                end
            elseif event == "UNIT_CONNECTION" and Identity.IsGroupUnitToken(unit) then
                Presence.UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
            end
            Presence.ScheduleGroupAuraPresenceRefreshAll(false, false)
        elseif unit == "player" then
            Presence.ScheduleGroupAuraPresenceRefreshAll(false)
        elseif Identity.IsGroupUnitToken(unit) then
            Presence.UpdateGroupAuraPresenceState(unit, false, false)
        end
    end

    if refreshNonGroup and (unit == "player" or not Identity.IsGroupUnitToken(unit)) then
        IdentityRefresh.ScheduleDirectIdentityEventRefresh(unit, unit == "player")
    end
    -- A player faction edge flips UnitCanAssist for unit-frame owners too.
    local owners = event == "UNIT_FACTION" and unit == "player" and A3._unitAuraIdentityOwnersByUnit
    if owners then
        for u in pairs(owners) do
            if u ~= "player" and not Identity.IsGroupUnitToken(u) then IdentityRefresh.ScheduleDirectIdentityEventRefresh(u, true) end
        end
    end
    return
end

local function OnEvent(frame, event, unit, arg2)
    if event == "PLAYER_REGEN_ENABLED" then
        if InCombat() then return end
        -- Drain every already-merged cold request through one shared
        -- next-frame job. Presence runs before the identity/geometry
        -- repair so composed output has its final OOC state first.
        IdentityRefresh.QueueDeferredDirectIdentityColdWork()
        return
    end
    if event == "PLAYER_CONTROL_LOST" then
        local _, isOnTaxi = IdentityRefresh.UpdateDirectIdentityPlayerTaxiState()
        local hasGroupAssist = Identity.HasGroupAuraAssistOwners()
        if hasGroupAssist then
            SyncDirectIdentityRefreshEvents(frame)
        else
            SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS", isOnTaxi ~= false, "player")
        end
        -- Capture a transient false state as early as possible. This is
        -- a direct rare-event scan, not a recurring flight/combat loop.
        if hasGroupAssist then Identity.UpdateAllGroupAuraAssistStates(false, false) end
        return
    end
    if A3._directIdentityRefreshAllEvents[event] == true then
        if event == "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY" then
            -- Payloadless portal notification: reconcile the hard
            -- presence reasons once, but never invalidate native Aura
            -- ownership. Identity filters are refreshed only if their
            -- actual UnitCanAssist value changed.
            Presence.ScheduleGroupAuraPresenceRefreshAll(true, true)
            return
        end
        WorldTransition.HandleEvent(event, unit, arg2)
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        -- Roster bursts can reuse the same unit token with a different
        -- GUID while UnitCanAssist remains true. Keep the 6.06 assist
        -- identity path combat-live, but defer the new 6.07 map/other-
        -- instance reconciliation until OOC.
        if InCombat() then
            Presence.UpdateAllGroupAuraPresenceIdentityStates()
            Presence.ScheduleGroupAuraPresenceRefreshAll(true, false)
            Identity.ScheduleGroupAuraAssistRefreshAll(true, false)
        else
            Presence.ScheduleGroupAuraPresenceRefreshAll(true, true)
        end
        return
    end
    local groupAssistEvent = event == "UNIT_FACTION" or event == "UNIT_PHASE"
        or event == "UNIT_CTR_OPTIONS"
        or event == "UNIT_CONNECTION" or event == "UNIT_FLAGS"
        or event == "UNIT_OTHER_PARTY_CHANGED"
        or event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE"
    if groupAssistEvent then return HandleGroupAssistEvent(frame, event, unit, arg2) end
    local units = A3._directIdentityEventUnits[event]
    if not units then return end
    local deferBossBurst = event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT"
    if event == "ARENA_OPPONENT_UPDATE" then
        -- Opponent updates flap in bursts at gate-open (stealth
        -- openers flip seen/unseen many times per second) and a
        -- synchronous UpdateAllAuras per event per unit re-walks
        -- secret data three times per flap. Honor the event's own
        -- unit token and drain through the deduped next-frame
        -- coalescer instead.
        local issecret = _G.issecretvalue
        if type(unit) == "string" and (not issecret or issecret(unit) ~= true)
            and A3._directIdentityRefreshUnits[unit] == true then
            IdentityRefresh.ScheduleDirectIdentityEventRefresh(unit)
        else
            for i = 1, #units do
                IdentityRefresh.ScheduleDirectIdentityEventRefresh(units[i])
            end
        end
        return
    end
    for i = 1, #units do
        if deferBossBurst then
            -- Blizzard refreshes all boss tokens synchronously and can
            -- repeat the notification while a reset settles. Native
            -- AuraContainer reparses are the expensive follower here;
            -- merge the burst through the existing identity scheduler
            -- instead of running every Boss lane inside the event tick.
            IdentityRefresh.ScheduleDirectIdentityEventRefresh(units[i])
        else
            IdentityRefresh.DirectIdentityRefreshUnit(units[i])
        end
    end
end
return { OnEvent = OnEvent }
end
