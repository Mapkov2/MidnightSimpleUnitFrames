-- Auras3 runtime: WorldTransition.
-- Cold world-transition geometry and duration repair; the B3 policy is unchanged.
local _, MSUF = ...
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.WorldTransition = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local Runtime = A3.Runtime
local Containers = Runtime.Containers
local Identity = Runtime.Identity
local IdentityRefresh = Runtime.IdentityRefresh
local Presence = Runtime.Presence
local WorldTransition = Runtime.WorldTransition
local SpellIndicatorsRuntime = A3.SpellIndicators
local IsLiveGroupAuraFrame = dependencies.Identity.IsLiveGroupAuraFrame
local ContainerOwnsHelpfulAuras = dependencies.Identity.ContainerOwnsHelpfulAuras
local SyncCuratedBigDefensiveContainer = dependencies.Presence.SyncCuratedBigDefensiveContainer
local ApplyLane, RecreateGroupSlots
function WorldTransition.RefreshUnit(unit, containers, recreateHelpfulAuras, skipLiveGroup, seedGroupAssist)
    local any, spellRecreates, helpfulRecreates = false, nil, nil
    for container in pairs(containers) do
        local liveGroup = IsLiveGroupAuraFrame(container and container._msufA3ParentFrame)
        if skipLiveGroup == true and liveGroup then
            -- Geometry is addon-owned and can be repaired without touching the
            -- native Aura cache, assignment, enabled state, or shown state.
            any = Containers.SyncManagedAuraContainerGeometry(container, true) or any
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
                if container and Containers.ManagedAuraContainerSupportsGeometryRepair(container) then
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
                    if not filterChanged and Containers.NativeContainerVisible(container) then
                        container:UpdateAllAuras()
                    end
                    -- Zone/world transitions can desync a reused container while cache looks current.
                    -- Keep the normal cached fast path by applying geometry repair only once here.
                    if container._msufA3ForceManagedAuraGeometry == true
                        or container._msufA3ForceSpellIndicatorGeometry == true then
                        Containers.SyncManagedAuraContainerGeometry(container, true)
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
        Identity.UpdateGroupAuraAssistState(
            unit, false, true, false, recreateHelpfulAuras ~= true)
    end
    return any
end

function WorldTransition.Bind(callbacks)
    ApplyLane = callbacks.ApplyLane
    RecreateGroupSlots = callbacks.RecreateGroupSlots
end

function WorldTransition.HandleEvent(event, unit, arg2)
    local initialOrReload = event == "PLAYER_ENTERING_WORLD"
        and (unit == true or arg2 == true)
    Presence.ScheduleGroupAuraPresenceRefreshAll(true, true)
    if initialOrReload then
        A3._directIdentityRefreshRecreateHelpfulAuras = true
    end
    -- Login/reload retains the pre-existing duration repair. Normal
    -- zone/instance transitions repair addon-owned geometry but
    -- explicitly skip every live Group AuraContainer.
    IdentityRefresh.ScheduleDirectIdentityRefreshAll(false, true, not initialOrReload)
    return true
end
return WorldTransition
end
