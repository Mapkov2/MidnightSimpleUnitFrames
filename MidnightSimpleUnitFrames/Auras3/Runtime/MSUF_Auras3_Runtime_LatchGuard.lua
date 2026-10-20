-- Auras3 runtime: LatchGuard.
-- Finds a native AuraContainer that Blizzard stopped updating and rebuilds it. The checks ride the
-- existing unit-change refresh and Park/Revive: a healthy owner costs one C call, nothing runs per UNIT_AURA.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.LatchGuard = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local SpellIndicatorsRuntime = A3.SpellIndicators
local tostring = tostring
local C_Timer = dependencies.Platform.C_Timer
local RunNextFrame = dependencies.Platform.RunNextFrame
local issecretvalue = dependencies.Platform.issecretvalue
local ApplyLane, ApplyDispelSensorRoot, RecreateGroupSlots
local RUN_WHEN_VISIBLE_ONCE = Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.RunWhenVisibleOnce
-- Every rebuild allocates a container plus its first AuraButton batch, and frames
-- are never freed, so a trigger that keeps coming back is capped for the session.
local MAX_REBUILDS = 32
local rebuilds = 0
local pending, flushQueued
local queued = {}

-- Blizzard_AuraContainer runs every container through DirtyPhaseMixin
-- (Blizzard_SharedXML/MixinUtil.lua, 12.1.5 and Forever). MarkDirty arms the
-- RunWhenVisibleOnce OnUpdate only on a clean->dirty edge, and ProcessDirtyFlags
-- clears `dirty` only after a complete pass. One aborted pass (a Lua error or the
-- client's script time limit) leaves the container dirty with its OnUpdate off:
-- it never updates again, and only a new container recovers (2026-10-19/20
-- reports: target buffs gone until /reload while debuffs kept working). Right
-- after UpdateAllAuras a healthy container reports RunWhenVisibleOnce whether it
-- is shown, hidden or disabled (OnHide and SetEnabled mark it as well); a frozen
-- one reports Disabled. GetOnUpdateMode carries no secret-return flag (unlike
-- IsVisible in SimpleFrameAPIDocumentation); a secret mode would only skip the check.
local function IsFrozen(container)
    local getMode = RUN_WHEN_VISIBLE_ONCE and container.GetOnUpdateMode
    if not getMode then return false end
    local mode = getMode(container)
    if issecretvalue and issecretvalue(mode) then return false end
    return mode ~= RUN_WHEN_VISIBLE_ONCE
end

local function OwnerLabel(container)
    local config = container._msufA3NativeLaneConfig
    return tostring(config and config.unit or "?") .. " " .. tostring(config and config.rootKey or "?")
end

-- The forced paths PLAYER_ENTERING_WORLD uses: they discard the frozen owner
-- instead of parking it and drop its key's park. Returns the replacement.
local function Rebuild(container)
    if container._msufA3SpellIndicatorRoot == true then return SpellIndicatorsRuntime.Recreate(container) end
    if container._msufA3GroupSlotsRoot == true then return RecreateGroupSlots(container) end
    local config, root = container._msufA3NativeLaneConfig, container._msufA3Root
    local parentFrame = container._msufA3ParentFrame
    if not (config and root and parentFrame and config.rootKey and root[config.rootKey] == container) then
        return nil
    end
    if config.sensorRoot == true then return ApplyDispelSensorRoot(root, config, parentFrame, true) end
    if config.sensor ~= true and config.enabled == true then return ApplyLane(root, config, parentFrame, true) end
    return nil
end

-- Runs one frame after the refresh that found the owners, outside its registry
-- loop: a replacement re-registers in the same per-unit set. An owner a config
-- apply retired in between is disabled and skipped.
local function FlushRebuilds()
    flushQueued = nil
    local list = pending
    pending = nil
    for i = 1, #list do
        local container = list[i]
        queued[container] = nil
        if IsFrozen(container) and container:IsEnabled() ~= false then
            if rebuilds >= MAX_REBUILDS then
                A3._RecordNativeAuraRuntimeError(
                    "Blizzard AuraContainer stopped updating again; rebuild limit reached until /reload")
            else
                rebuilds = rebuilds + 1
                local rebuilt = Rebuild(container) ~= nil
                A3._RecordNativeAuraRuntimeError(OwnerLabel(container) .. (rebuilt
                    and ": Blizzard AuraContainer stopped updating; rebuilt it"
                    or ": Blizzard AuraContainer stopped updating; it cannot be rebuilt until /reload"))
            end
        end
    end
end

-- The unit-change refresh (target, focus, boss, arena) calls this in place of its
-- own UpdateAllAuras. `marked` means a filter setter already requested the full
-- rebuild. Hidden owners are checked too: a target picked from no target is still
-- hidden here, and its OnHide already marked it, so the request costs nothing.
A3._RefreshNativeAuraOwner = function(container, marked)
    if marked ~= true then container:UpdateAllAuras() end
    if queued[container] or container:IsEnabled() == false or not IsFrozen(container) then return false end
    queued[container] = true
    pending = pending or {}
    pending[#pending + 1] = container
    if not flushQueued then
        flushQueued = true
        if RunNextFrame then RunNextFrame(FlushRebuilds) else C_Timer.After(0, FlushRebuilds) end
    end
    return true
end

-- Park/Revive must never hand a frozen owner back. A parked owner is hidden and
-- disabled, so it already carries the mark; a frozen one leaves its park and the
-- caller builds a fresh container as if none had been parked.
A3._TakeRevivableNativeOwner = function(pool, signature)
    local parked = pool[signature]
    if not parked then return nil end
    parked:UpdateAllAuras()
    if not IsFrozen(parked) then return parked end
    pool[signature] = nil
    A3._RecordNativeAuraRuntimeError(OwnerLabel(parked)
        .. ": a parked Blizzard AuraContainer stopped updating; replaced it")
    return nil
end

return {
    Bind = function(dependencies)
        ApplyLane = dependencies.ApplyLane
        ApplyDispelSensorRoot = dependencies.ApplyDispelSensorRoot
        RecreateGroupSlots = dependencies.RecreateGroupSlots
    end,
}
end
