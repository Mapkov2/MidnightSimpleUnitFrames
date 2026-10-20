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
local MAX_REBUILDS = 32
local WATCH_FRAMES = 3
local rebuilds = 0
local queued, watching = {}, {}
local rebuildList, rebuildQueued, watchList, watchQueued
local FlushRebuilds, FlushWatch

local function Schedule(fn)
    if RunNextFrame then RunNextFrame(fn) else C_Timer.After(0, fn) end
end

local function Mode(container)
    local getMode = RUN_WHEN_VISIBLE_ONCE and container.GetOnUpdateMode
    if not getMode then return nil end
    local mode = getMode(container)
    if issecretvalue and issecretvalue(mode) then return nil end
    return mode
end

local function IsFrozen(container)
    local mode = Mode(container)
    return mode ~= nil and mode ~= RUN_WHEN_VISIBLE_ONCE
end

local function OwnerLabel(container)
    local config = container._msufA3NativeLaneConfig
    return tostring(config and config.unit or container.unit or "?") .. " "
        .. tostring(config and config.rootKey or container._msufA3NativeLane or "?")
end

local function Rebuild(container)
    if container._msufA3SpellIndicatorRoot == true then return SpellIndicatorsRuntime.Recreate(container) end
    if container._msufA3GroupSlotsRoot == true then return RecreateGroupSlots(container) end
    local config, root = container._msufA3NativeLaneConfig, container._msufA3Root
    if not (config and root and config.rootKey and root[config.rootKey] == container) then return nil end
    local frame = root._msufA3ParentFrame or root:GetParent()
    if config.sensorRoot == true then return ApplyDispelSensorRoot(root, config, frame, true) end
    if config.sensor ~= true and config.enabled == true then return ApplyLane(root, config, frame, true) end
    return nil
end

local function Watch(container, frames)
    if watching[container] or not (container._msufA3GroupLayout and container._msufA3ManagedGroupKey) then return end
    watching[container] = frames
    watchList = watchList or {}
    watchList[#watchList + 1] = container
    if not watchQueued then
        watchQueued = true
        Schedule(FlushWatch)
    end
end

local function QueueRebuild(container)
    if queued[container] then return true end
    queued[container] = true
    rebuildList = rebuildList or {}
    rebuildList[#rebuildList + 1] = container
    if not rebuildQueued then
        rebuildQueued = true
        Schedule(FlushRebuilds)
    end
    return true
end

FlushRebuilds = function()
    rebuildQueued = nil
    local list = rebuildList
    rebuildList = nil
    for i = 1, #list do
        local container = list[i]
        queued[container] = nil
        if IsFrozen(container) and container:IsEnabled() ~= false then
            if rebuilds >= MAX_REBUILDS then
                A3._RecordNativeAuraRuntimeError(
                    "Blizzard AuraContainer stopped updating again; rebuild limit reached until /reload")
            else
                rebuilds = rebuilds + 1
                local replacement = Rebuild(container)
                if replacement then Watch(replacement, WATCH_FRAMES) end
                A3._RecordNativeAuraRuntimeError(OwnerLabel(container) .. (replacement
                    and ": Blizzard AuraContainer stopped updating; rebuilt it"
                    or ": Blizzard AuraContainer stopped updating; it cannot be rebuilt until /reload"))
            end
        end
    end
end

FlushWatch = function()
    watchQueued = nil
    local list = watchList
    watchList = nil
    for i = 1, #list do
        local container = list[i]
        local frames = watching[container]
        watching[container] = nil
        if container:IsEnabled() ~= false and A3._NativeContainerVisible(container) then
            local mode = Mode(container)
            if mode == RUN_WHEN_VISIBLE_ONCE then
                if frames > 1 then Watch(container, frames - 1) end
            elseif mode ~= nil then
                container:SetAuraGroupLayout(container._msufA3ManagedGroupKey, container._msufA3GroupLayout)
                if IsFrozen(container) then QueueRebuild(container) end
            end
        end
    end
end

A3._RefreshNativeAuraOwner = function(container, marked)
    if marked ~= true then container:UpdateAllAuras() end
    if container:IsEnabled() == false then return false end
    if IsFrozen(container) then return QueueRebuild(container) end
    Watch(container, WATCH_FRAMES)
    return false
end

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
