-- Auras3 runtime: IdentityTopology.
-- Native owner registration, nested topology batches and four-token event shards.
local _, MSUF = ...
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.IdentityTopology = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Identity = Runtime.Identity
local IdentityRefresh = Runtime.IdentityRefresh
local IdentityTopology = Runtime.IdentityTopology
local Presence = Runtime.Presence
local math_floor = math.floor
local math_max = math.max
local next = next
local pairs = pairs
local table_concat = table.concat
local table_sort = table.sort
local tonumber = tonumber
local type = type
local CreateFrame = dependencies.Platform.CreateFrame
local InCombat = dependencies.Platform.InCombat
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local issecretvalue = dependencies.Platform.issecretvalue

local OnEvent
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
IdentityTopology.GroupAuraAssistFlagBucket = function(unit)
    if issecretvalue(unit) == true or type(unit) ~= "string" then return nil end
    local partyIndex = tonumber(unit:match("^party(%d+)$"))
    if partyIndex and partyIndex >= 1 and partyIndex <= 4 then return 1 end
    local raidIndex = tonumber(unit:match("^raid(%d+)$"))
    if raidIndex and raidIndex >= 1 and raidIndex <= 40 then
        return 2 + math_floor((raidIndex - 1) / 4)
    end
    return nil
end

IdentityTopology.ClearGroupAuraAssistFlagShards = function()
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

local function OnShardEvent(self, event, unit, arg2)
    local knownUnit = issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
    if knownUnit then
        if event ~= "UNIT_FLAGS"
            and self._msufA3UnitSet and self._msufA3UnitSet[unit] then
            if InCombat() then
                if event == "UNIT_PHASE" or event == "UNIT_CTR_OPTIONS" then
                    Presence.UpdateGroupAuraPresencePhaseState(unit, false)
                elseif event == "UNIT_CONNECTION" then
                    Presence.UpdateGroupAuraPresenceConnectionState(unit, arg2, false)
                end
                -- Map-ID, UnitInOtherParty and the composite scan
                -- are deliberately cold and resume after combat.
                Presence.ScheduleGroupAuraPresenceRefreshAll(false, false)
            else
                Presence.UpdateGroupAuraPresenceState(unit, false, false)
            end
        end
        if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[unit] then
            Identity.UpdateGroupAuraAssistState(unit, false, false, false)
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
                    Presence.UpdateGroupAuraPresencePhaseState(shardUnit, false)
                elseif event == "UNIT_CONNECTION" then
                    -- A restricted payload cannot safely be shared
                    -- across the shard. Fall back to one bounded
                    -- UnitIsConnected read per registered token.
                    Presence.UpdateGroupAuraPresenceConnectionState(shardUnit, nil, false)
                end
            else
                Presence.UpdateGroupAuraPresenceState(shardUnit, false, false)
            end
        end
        if self._msufA3AssistUnitSet and self._msufA3AssistUnitSet[shardUnit] then
            Identity.UpdateGroupAuraAssistState(shardUnit, false, false, false)
        end
    end
    if event ~= "UNIT_FLAGS" and InCombat() then
        Presence.ScheduleGroupAuraPresenceRefreshAll(false, false)
    end
end

IdentityTopology.SyncGroupAuraAssistFlagShards = function()
    local desired = {}
    for unit, count in pairs(A3._directIdentityGroupOwnerCounts or {}) do
        if count > 0 then
            local bucket = IdentityTopology.GroupAuraAssistFlagBucket(unit)
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
            local bucket = IdentityTopology.GroupAuraAssistFlagBucket(unit)
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
            shard:SetScript("OnEvent", OnShardEvent)
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

local DirectIdentityBossUnit = MSUF.UF.IsBossUnit

local function DirectIdentityArenaUnit(unit)
    return unit == "arena1" or unit == "arena2" or unit == "arena3"
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
    local hasArena = false
    local hasGroupAssist = Identity.HasGroupAuraAssistOwners()
    hasGroup = (A3._directIdentityGroupOwnerCount or 0) > 0
    if byUnit then
        for unit, containers in pairs(byUnit) do
            if containers and next(containers) then
                hasAny = true
                if not Identity.IsGroupUnitToken(unit) then
                    if unit == "player" then
                        hasPlayer = true
                    elseif unit == "target" then
                        hasTarget = true
                    elseif unit == "focus" then
                        hasFocus = true
                    elseif DirectIdentityBossUnit(unit) then
                        hasBoss = true
                    elseif DirectIdentityArenaUnit(unit) then
                        hasArena = true
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
        IdentityTopology.SyncGroupAuraAssistFlagShards()
    else
        IdentityTopology.ClearGroupAuraAssistFlagShards()
    end
    local playerOnTaxi
    if hasPlayer or hasGroupAssist then
        _, playerOnTaxi = IdentityRefresh.UpdateDirectIdentityPlayerTaxiState()
    end
    -- Group-unit flags are handled by the four-token shards above. The shared
    -- driver binds only the player observer, and only while a taxi transition
    -- is active/unknown, then removes it immediately on the landing edge.
    SetDirectIdentityRefreshEvent(frame, "UNIT_FLAGS",
        (hasPlayer or hasGroupAssist) and playerOnTaxi ~= false, "player")
    SetDirectIdentityRefreshEvent(frame, "PLAYER_TARGET_CHANGED", hasTarget)
    SetDirectIdentityRefreshEvent(frame, "PLAYER_FOCUS_CHANGED", hasFocus)
    SetDirectIdentityRefreshEvent(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", hasBoss)
    SetDirectIdentityRefreshEvent(frame, "ARENA_OPPONENT_UPDATE", hasArena)
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

IdentityTopology.BeginDirectIdentityEventTopologyBatch = function()
    directIdentityEventTopologyBatchDepth = directIdentityEventTopologyBatchDepth + 1
    return directIdentityEventTopologyBatchDepth
end

IdentityTopology.EndDirectIdentityEventTopologyBatch = function()
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
        IdentityTopology.EndDirectIdentityEventTopologyBatch()
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
    if DirectIdentityArenaUnit(unit) then
        return directIdentityRefreshRegisteredEvents.ARENA_OPPONENT_UPDATE ~= nil
    end
    return true
end

IdentityTopology.EnsureDirectIdentityRefreshFrame = function()
    if directIdentityRefreshEventFrame then return directIdentityRefreshEventFrame end
    local frame = A3._directIdentityAuraFrame
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
        A3._directIdentityAuraFrame = frame
    end
    directIdentityRefreshEventFrame = frame
    return frame
end

IdentityTopology.RegisterUnitAuraIdentityOwner = function(container, unit)
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
    Identity.EnsureUnitAuraIdentityState(unit)
    IdentityRefresh.SyncUnitAuraIdentityRefreshRoute()
    return true
end

IdentityTopology.UnregisterUnitAuraIdentityOwner = function(container, unit)
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
    IdentityRefresh.SyncUnitAuraIdentityRefreshRoute()
    return true
end

IdentityTopology.RegisterDirectIdentityRefreshContainer = function(container)
    local unit = container and container.unit
    if not container or container._msufA3SkipDirectIdentityRefresh == true
        or not Identity.DirectIdentityRefreshUnitEligible(unit) then
        IdentityTopology.UnregisterDirectIdentityRefreshContainer(container)
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
    local unitIdentityGated = Identity.ContainerOwnsUnitAuraIdentityGate(container)
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
        IdentityTopology.UnregisterUnitAuraIdentityOwner(container, oldUnit)
    end
    if unitIdentityGated and (not oldUnitIdentityGated or oldUnit ~= unit) then
        IdentityTopology.RegisterUnitAuraIdentityOwner(container, unit)
    end
    local assistGated = Identity.ContainerOwnsGroupAuraAssistGate(container)
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
        and not Identity.GroupAuraAssistUnitHasOwners(oldUnit) then
        local states = A3._groupAuraAssistState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldAssistGated and not assistGated
        and not Identity.GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
    end
    if oldUnit and oldUnit ~= unit and not Presence.GroupAuraPresenceUnitHasOwners(oldUnit) then
        local states = A3._groupAuraPresenceState
        if states then states[oldUnit] = nil end
    end
    if oldUnit == unit and oldGroupOwner and not groupOwner
        and not Presence.GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    local frame = IdentityTopology.EnsureDirectIdentityRefreshFrame()
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
            Presence.ApplyGroupAuraPresenceFrame(container._msufA3ParentFrame,
                presenceState.present ~= false, unit, presenceState.revision or 0)
            Presence.ApplyGroupAuraPresenceContainer(container,
                presenceState.present ~= false,
                A3._groupAuraAssistState and A3._groupAuraAssistState[unit])
        end
    end
    if unitIdentityGated then Identity.SeedUnitAuraIdentityOwner(container, unit) end
    return true
end

IdentityTopology.UnregisterDirectIdentityRefreshContainer = function(container)
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
    if wasUnitIdentityGated then IdentityTopology.UnregisterUnitAuraIdentityOwner(container, unit) end
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
    if wasAssistGated and not Identity.GroupAuraAssistUnitHasOwners(unit) then
        local states = A3._groupAuraAssistState
        if states then states[unit] = nil end
        local refreshUnits = A3._groupAuraAssistRefreshUnits
        if refreshUnits then refreshUnits[unit] = nil end
        local revealUnits = A3._groupAuraAssistRevealUnits
        if revealUnits then revealUnits[unit] = nil end
    end
    if wasGroupOwner and not Presence.GroupAuraPresenceUnitHasOwners(unit) then
        local states = A3._groupAuraPresenceState
        if states then states[unit] = nil end
    end
    if not Identity.HasDirectIdentityRefreshContainers() then
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
        IdentityRefresh.SyncUnitAuraIdentityRefreshRoute()
        local frame = A3._directIdentityAuraFrame
        if frame then frame:UnregisterAllEvents() end
        IdentityTopology.ClearGroupAuraAssistFlagShards()
        directIdentityRefreshRegisteredEvents = {}
        directIdentityRefreshEventFrame = nil
    elseif topologyChanged or assistUnitTopologyChanged or assistGlobalTopologyChanged
        or groupGlobalTopologyChanged or groupUnitTopologyChanged then
        RequestDirectIdentityRefreshEventSync(directIdentityRefreshEventFrame)
    end
end

A3.BeginTopologyBatch = IdentityTopology.BeginDirectIdentityEventTopologyBatch
A3.EndTopologyBatch = IdentityTopology.EndDirectIdentityEventTopologyBatch

local exports = {
    DrainDirectIdentityEventTopologyBatch = DrainDirectIdentityEventTopologyBatch,
    SyncDirectIdentityRefreshEvents = SyncDirectIdentityRefreshEvents,
    SetDirectIdentityRefreshEvent = SetDirectIdentityRefreshEvent,
    Bind = function(callbacks) OnEvent = callbacks.OnEvent end,
}
for name, value in pairs(exports) do IdentityTopology[name] = value end
return IdentityTopology
end
