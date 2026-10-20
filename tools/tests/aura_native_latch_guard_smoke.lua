-- Native aura runtime (Midnight and WoW Forever): a frozen Blizzard
-- AuraContainer is found on the unit-change refresh and on Park/Revive, and
-- rebuilt (Auras3/Runtime/MSUF_Auras3_Runtime_LatchGuard.lua).
--
-- Blizzard_AuraContainer runs every container through DirtyPhaseMixin
-- (12.1.5 Blizzard_SharedXML/MixinUtil.lua). MarkDirty arms the
-- RunWhenVisibleOnce OnUpdate only on a clean->dirty edge, and
-- ProcessDirtyFlags clears `dirty` only after a complete pass. One aborted pass
-- leaves the container dirty with its OnUpdate off for the rest of the session:
-- target buffs stayed empty, or showed a buff of an earlier target, until
-- /reload while debuffs kept working (reports 2026-10-19 and 2026-10-20, the
-- second one after the Buff lane already had its own container). The stub
-- below models exactly that contract, including OnHide/SetEnabled marking the
-- container. The real IdentityEvents, LatchGuard and NativeApply factories must
-- rebuild a frozen owner on the next frame after a target, focus, boss or arena
-- refresh (also when the frame is still hidden), leave healthy, disabled and
-- ineligible owners alone, stop at the session limit, and never revive a frozen
-- parked owner.
-- Arguments: repository root, then optionally replacement paths for
-- IdentityEvents, NativeApply and LatchGuard (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local runtimeDir = root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/"
local identityEventsPath = arg[2] or (runtimeDir .. "MSUF_Auras3_Runtime_IdentityEvents.lua")
local nativeApplyPath = arg[3] or (runtimeDir .. "MSUF_Auras3_Runtime_NativeApply.lua")
local latchGuardPath = arg[4] or (runtimeDir .. "MSUF_Auras3_Runtime_LatchGuard.lua")

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local RUN_WHEN_VISIBLE_ONCE, DISABLED = 2, 0
Enum = { OnUpdateMode = { Disabled = DISABLED, RunWhenVisibleOnce = RUN_WHEN_VISIBLE_ONCE } }

-- One shared next-frame queue for MSUF_RunNextFrame and Platform.RunNextFrame.
local frameQueue = {}
local function RunNextFrame(fn) frameQueue[#frameQueue + 1] = fn end
local function NextFrame()
    local list = frameQueue
    frameQueue = {}
    for i = 1, #list do list[i]() end
end
MSUF_RunNextFrame = RunNextFrame

-- DirtyPhaseMixin contract. Show/Hide/SetEnabled mark like OnShow/OnHide do.
local function Native(fields)
    local c = fields or {}
    c.dirty, c.mode, c.passes = false, DISABLED, 0
    if c.visible == nil then c.visible = true end
    if c.enabled == nil then c.enabled = true end
    function c:UpdateAllAuras()
        self.requests = (self.requests or 0) + 1
        if not self.dirty then
            self.dirty = true
            self.mode = RUN_WHEN_VISIBLE_ONCE
        end
    end
    function c:GetOnUpdateMode() return self.mode end
    function c:IsEnabled() return self.enabled end
    function c:SetEnabled(value)
        if self.enabled ~= (value == true) then
            self.enabled = value == true
            self:UpdateAllAuras()
        end
    end
    function c:Show() if not self.visible then self.visible = true; self:UpdateAllAuras() end end
    function c:Hide() if self.visible then self.visible = false; self:UpdateAllAuras() end end
    function c:IsShown() return self.visible end
    function c:IsVisible() return self.visible end
    -- The client resets RunWhenVisibleOnce to Disabled before running it.
    function c:Tick()
        if not (self.visible and self.mode == RUN_WHEN_VISIBLE_ONCE) then return end
        self.mode = DISABLED
        if self.failNextPass then
            self.failNextPass = nil
            return -- the pass aborted: `dirty` stays true
        end
        self.passes = self.passes + 1
        self.dirty = false
    end
    return c
end

local function Freeze(c)
    local wasVisible = c.visible
    c.visible = true
    c:UpdateAllAuras()
    c.failNextPass = true
    c:Tick()
    c.visible = wasVisible
    Check(c.dirty == true and c.mode == DISABLED, "precondition: the stub did not freeze")
end

local function Settle(...)
    for i = 1, select("#", ...) do select(i, ...):Tick() end
end

local function CreateFrame()
    local frame = { events = {} }
    function frame:SetScript(name, handler) self[name] = handler end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end

local reports = {}
local function LastReport() return reports[#reports] or "" end
-- Stands in for a secret value: comparing one would raise in the client.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-------------------------------------------------------------------------------
-- 1. Unit-change refresh: IdentityEvents + LatchGuard on stub owners.
-------------------------------------------------------------------------------
local MSUF = {
    Auras3RuntimeFactories = {},
    UF = { IsBossUnit = function(unit) return type(unit) == "string" and unit:match("^boss%d$") ~= nil end },
}
local registry = {}
local rebuilt = {}
local A3 = { SpellIndicators = {} }
local platform = {
    C_Timer = { After = function(_, fn) RunNextFrame(fn) end },
    CreateFrame = CreateFrame,
    InCombat = function() return false end,
    issecretvalue = function(value) return value == SECRET end,
    RunNextFrame = RunNextFrame,
}
assert(loadfile(identityEventsPath))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(latchGuardPath))("MidnightSimpleUnitFrames", MSUF)
local identityEvents = assert(MSUF.Auras3RuntimeFactories.IdentityEvents, "IdentityEvents factory did not register")(
    "MidnightSimpleUnitFrames", MSUF, A3, {}, function(_, value) return value end, {
        Platform = platform,
        Identity = {
            ContainerOwnsHelpfulAuras = function() return false end,
            IsLiveGroupAuraFrame = function(frame) return frame ~= nil and frame.liveGroup == true end,
        },
        Presence = {
            SyncCuratedBigDefensiveContainer = function(container)
                if container.filterSetterMarks then container:UpdateAllAuras(); return true end
                return false
            end,
        },
    })
local latchGuard = assert(MSUF.Auras3RuntimeFactories.LatchGuard, "LatchGuard factory did not register")(
    "MidnightSimpleUnitFrames", MSUF, A3, {}, function(_, value) return value end, { Platform = platform })

-- Fake forced paths: they replace the owner in its root and per-unit set the
-- way ApplyLane/ApplyDispelSensorRoot/RecreateGroupSlots do.
local function Replace(container, kind)
    rebuilt[#rebuilt + 1] = container
    local config = container._msufA3NativeLaneConfig
    local replacement = Native({ name = container.name .. "+", kind = kind })
    replacement._msufA3NativeLaneConfig, replacement._msufA3Root = config, container._msufA3Root
    replacement._msufA3ParentFrame = container._msufA3ParentFrame
    replacement._msufA3GroupSlotsRoot = container._msufA3GroupSlotsRoot
    container:Hide(); container:SetEnabled(false)
    local set = registry[config.unit]
    set[container] = nil
    set[replacement] = true
    container._msufA3Root[config.rootKey] = replacement
    replacement:UpdateAllAuras()
    return replacement
end
latchGuard.Bind({
    ApplyLane = function(_, config, _, force)
        Check(force == true, "a frozen lane was rebuilt without the forced path")
        return Replace(config._owner, "lane")
    end,
    ApplyDispelSensorRoot = function(_, config, _, force)
        Check(force == true, "a frozen sensor root was rebuilt without the forced path")
        return Replace(config._owner, "sensors")
    end,
    RecreateGroupSlots = function(container) return Replace(container, "groupSlots") end,
})
A3.SpellIndicators.Recreate = function(container) return Replace(container, "spell") end
A3._RecordNativeAuraRuntimeError = function(message) reports[#reports + 1] = message end
A3._NativeContainerVisible = function(container) return container.visible == true end
A3._SyncManagedAuraContainerGeometry = function() return true end
A3._UpdateGroupAuraAssistState = function() return true end
A3._HasGroupAuraAssistOwners = function() return false end
A3._IsGroupUnitToken = function(unit)
    return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end
A3._directIdentityRefreshUnits = { player = true, target = true, focus = true, boss1 = true, boss2 = true, arena1 = true }
A3._directIdentityRefreshAllEvents = { PLAYER_ENTERING_WORLD = true, ZONE_CHANGED_NEW_AREA = true }
A3._directIdentityEventUnits = {
    PLAYER_TARGET_CHANGED = { "target" },
    PLAYER_FOCUS_CHANGED = { "focus" },
    INSTANCE_ENCOUNTER_ENGAGE_UNIT = { "boss1", "boss2" },
    ARENA_OPPONENT_UPDATE = { "arena1" },
}
A3._directIdentityAuraContainers = registry

local driver = assert(A3._EnsureDirectIdentityRefreshFrame(), "the identity driver frame was not created")
local onEvent = assert(driver.OnEvent, "the identity driver has no OnEvent handler")

local unitRoots = {}
local function Owner(unit, rootKey, fields)
    local c = Native(fields)
    c.name = unit .. " " .. rootKey
    local config = { unit = unit, rootKey = rootKey, enabled = true }
    if fields and fields.sensorRoot then config.sensorRoot, config.sensor = true, true end
    config._owner = c
    unitRoots[unit] = unitRoots[unit] or {}
    c._msufA3NativeLaneConfig, c._msufA3Root, c._msufA3ParentFrame = config, unitRoots[unit], { unit = unit }
    unitRoots[unit][rootKey] = c
    registry[unit] = registry[unit] or {}
    registry[unit][c] = true
    c:Tick()
    return c
end
local function Current(unit, rootKey) return unitRoots[unit][rootKey] end

-- Keep every Fake replacement pointing at its own config.
local baseReplace = Replace
Replace = function(container, kind)
    local replacement = baseReplace(container, kind)
    local config = {}
    for key, value in pairs(container._msufA3NativeLaneConfig) do config[key] = value end
    config._owner = replacement
    replacement._msufA3NativeLaneConfig = config
    return replacement
end

-- 1a. Healthy owners: refreshed, nothing rebuilt.
local buffs = Owner("target", "Buffs")
local debuffs = Owner("target", "Debuffs")
local sensors = Owner("target", "DispelSensorNeutral", { sensorRoot = true })
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == 0, "a healthy native owner was rebuilt on a target swap")
Check(buffs.mode == RUN_WHEN_VISIBLE_ONCE and debuffs.mode == RUN_WHEN_VISIBLE_ONCE,
    "the target swap did not request the full rebuild")
Settle(buffs, debuffs, sensors)

-- 1b. The 2026-10-20 report: the standalone Buff owner froze earlier, Debuffs
-- and the Dispel/Purge owner stayed healthy. The next target swap rebuilds
-- exactly the frozen one, on the next frame.
Freeze(buffs)
onEvent(driver, "PLAYER_TARGET_CHANGED")
Check(#rebuilt == 0, "the rebuild ran inside the refresh loop instead of on the next frame")
NextFrame()
Check(#rebuilt == 1 and rebuilt[1] == buffs, "a frozen target Buff owner was not rebuilt on the next target swap")
Check(Current("target", "Buffs") ~= buffs and registry.target[buffs] == nil
    and registry.target[debuffs] == true and registry.target[sensors] == true,
    "recovery replaced the wrong owner")
Check(LastReport():find("target Buffs", 1, true) and LastReport():find("rebuilt", 1, true),
    "the rebuild was not reported with its unit and lane")
local fresh = Current("target", "Buffs")
fresh:Tick()
Check(fresh.passes == 1 and fresh.dirty == false, "the replacement owner does not process passes")

-- 1c. No target -> new target: the frame is still hidden when the event runs.
local hiddenBuffs = Current("target", "Buffs")
Freeze(hiddenBuffs)
hiddenBuffs:Hide()
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(rebuilt[#rebuilt] == hiddenBuffs, "a frozen owner of a not yet shown target frame was not rebuilt")
-- A hidden healthy owner is already marked by its OnHide: no extra work.
local quiet = Current("target", "Buffs")
quiet:Tick(); quiet:Hide()
local requests = quiet.requests
local before = #rebuilt
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == before and quiet.dirty == true and quiet.passes == 1,
    "a hidden healthy owner was rebuilt or processed while hidden")
Check(quiet.requests == requests + 1, "a hidden owner was not checked")
quiet:Show(); Settle(quiet)

-- 1d. A filter setter already requested the rebuild (curated Big Defensive):
-- no second request, but a frozen one is still found.
local marked = Owner("target", "Externals", { filterSetterMarks = true })
requests = marked.requests or 0
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(marked.requests == requests + 1, "a filter-setter mark was followed by a second full rebuild request")
Settle(marked)
before = #rebuilt
Freeze(marked)
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == before + 1 and rebuilt[#rebuilt] == marked, "a frozen owner behind a filter-setter mark was not rebuilt")

-- 1e. Focus (direct), boss (coalesced burst) and arena (coalesced) routes.
local focus = Owner("focus", "Buffs")
local boss = Owner("boss2", "Buffs")
local arenaSensors = Owner("arena1", "DispelSensorNeutral", { sensorRoot = true })
Freeze(focus); Freeze(boss); Freeze(arenaSensors)
before = #rebuilt
onEvent(driver, "PLAYER_FOCUS_CHANGED")
NextFrame()
Check(rebuilt[#rebuilt] == focus, "a frozen focus owner was not rebuilt on a focus change")
onEvent(driver, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
NextFrame(); NextFrame()
Check(rebuilt[#rebuilt] == boss, "a frozen boss owner was not rebuilt on an encounter engage")
onEvent(driver, "ARENA_OPPONENT_UPDATE", "arena1", "seen")
NextFrame(); NextFrame()
Check(rebuilt[#rebuilt] == arenaSensors and #rebuilt == before + 3,
    "a frozen arena Dispel/Purge owner was not rebuilt on an opponent update")

-- 1f. Owners the refresh must not touch: a disabled one and a frozen one that
-- is queued twice in the same frame (rebuilt once).
local disabled = Owner("target", "CustomAuras1")
Freeze(disabled)
disabled.enabled = false
local twice = Current("target", "Debuffs")
Freeze(twice)
before = #rebuilt
onEvent(driver, "PLAYER_TARGET_CHANGED")
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == before + 1 and rebuilt[#rebuilt] == twice,
    "a disabled owner was rebuilt or a frozen owner was rebuilt twice")
registry.target[disabled] = nil

-- A secret OnUpdate mode is never compared: the owner is skipped, not rebuilt.
local secretOwner = Owner("target", "CustomAuras4")
secretOwner.GetOnUpdateMode = function() return SECRET end
before = #rebuilt
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == before, "an owner with a secret OnUpdate mode was compared and rebuilt")
registry.target[secretOwner] = nil

-- 1g. The identity-gated route (exact-ID owners present): an ineligible gated
-- owner is not touched, an eligible frozen one is rebuilt.
A3._unitAuraIdentityOwnerCount = 1
A3._UnitAuraIdentityUnitHasOwners = function(unit) return unit == "target" end
A3._RefreshUnitAuraIdentityState = function() return { canAssist = false, assistKnown = true, revision = 1 } end
A3._ContainerOwnsUnitAuraIdentityGate = function(container) return container.gated == true end
A3._SetUnitAuraIdentityOwnerReady = function() end
A3._UnitAuraIdentityOwnerVisible = function(container) return container.eligible == true end
A3._ScheduleUnitAuraIdentityReveal = function() end
Check(A3._SyncUnitAuraIdentityRefreshRoute() == true, "precondition: the identity-gated route was not selected")
local gatedOff = Owner("target", "CustomAuras2", { gated = true, eligible = false })
local gatedOn = Owner("target", "CustomAuras3", { gated = true, eligible = true })
Freeze(gatedOff); Freeze(gatedOn)
requests = gatedOff.requests
before = #rebuilt
onEvent(driver, "PLAYER_TARGET_CHANGED")
NextFrame()
Check(#rebuilt == before + 1 and rebuilt[#rebuilt] == gatedOn and gatedOff.requests == requests,
    "the identity-gated route did not rebuild exactly the eligible frozen owner")
registry.target[gatedOff] = nil
A3._unitAuraIdentityOwnerCount = 0
A3._SyncUnitAuraIdentityRefreshRoute()

-- 1h. A trigger that keeps coming back is bounded: frames are never freed.
for _ = 1, 40 do
    local owner = Current("target", "Buffs")
    if not (owner.dirty and owner.mode == DISABLED) then Freeze(owner) end
    onEvent(driver, "PLAYER_TARGET_CHANGED")
    NextFrame()
end
Check(#rebuilt == 32, "the session rebuild limit is " .. #rebuilt .. " instead of 32")
Check(LastReport():find("limit", 1, true), "reaching the rebuild limit was not reported")

-------------------------------------------------------------------------------
-- 2. Park/Revive and the forced rebuild through the real NativeApply.
-------------------------------------------------------------------------------
local created = {}
local function NewNative()
    local c = Native({ enabled = false })
    local host = { shown = true }
    function host:Show() self.shown = true end
    function host:Hide() self.shown = false end
    c._msufA3LayoutHost = host
    function c:SetUnit(unit) self.boundUnit = unit end
    function c:GetUnit() return self.boundUnit end
    function c:SetAuraGroupMaxFrameCount() end
    function c:SetAuraGroupSortMethod() end
    created[#created + 1] = c
    return c
end
local function Stubs(fields)
    return setmetatable(fields or {}, { __index = function() return function() end end })
end
local applyMSUF = { Auras3RuntimeFactories = {} }
local applyA3 = { SpellIndicators = Stubs() }
local frame = {}
local laneRoot = {}
local function Bound(container, config)
    container._msufA3Root, container._msufA3ParentFrame, container._msufA3NativeLaneConfig = laneRoot, frame, config
    return container
end
local dependencies = setmetatable({
    Signatures = Stubs({
        LaneStructuralSignature = function(lane) return "S:" .. tostring(lane.size) end,
        LaneLayoutSignature = function(lane) return "L:" .. tostring(lane.size) end,
        LaneTrackingSignature = function(lane) return "T:" .. tostring(lane.unit) end,
        UsesStandaloneAuraSlot = function() return false end,
    }),
    ConfigValues = Stubs({ EffectiveLaneFilters = function() return "HELPFUL", nil, "none" end }),
    Sort = Stubs({ AuraSortSignature = function() return "DEFAULT:N" end, AuraSortEnums = function() return 0, 0 end }),
    OwnerConfig = Stubs({ NORMAL_LANE_ROOT_KEYS = { "Buffs" }, EFFECT_ROOT_FIELDS = {}, EFFECT_ROOT_KEYS = {} }),
    Identity = Stubs({ IsLiveGroupAuraFrame = function() return false end }),
    Containers = Stubs({
        CreateNativeDispelSensorRoot = function(_, sensorRoot)
            local c = Bound(NewNative(), sensorRoot)
            c:SetEnabled(true)
            return c
        end,
    }),
}, { __index = function(t, group)
    local stub = Stubs()
    rawset(t, group, stub)
    return stub
end })
assert(loadfile(nativeApplyPath))("MidnightSimpleUnitFrames", applyMSUF)
assert(loadfile(latchGuardPath))("MidnightSimpleUnitFrames", applyMSUF)
local nativeApply = applyMSUF.Auras3RuntimeFactories.NativeApply(
    "MidnightSimpleUnitFrames", applyMSUF, applyA3, {}, function() end, dependencies)
local applyGuard = applyMSUF.Auras3RuntimeFactories.LatchGuard(
    "MidnightSimpleUnitFrames", applyMSUF, applyA3, {}, function() end, { Platform = platform })
Check(nativeApply.ApplyDispelSensorRoot, "NativeApply exports no ApplyDispelSensorRoot")
applyGuard.Bind({
    ApplyLane = nativeApply.ApplyLane,
    ApplyDispelSensorRoot = nativeApply.ApplyDispelSensorRoot,
    RecreateGroupSlots = nativeApply.RecreateGroupSlots,
})
applyA3._RecordNativeAuraRuntimeError = function(message) reports[#reports + 1] = message end
applyA3._RegisterDirectIdentityRefreshContainer = function() end
applyA3._UnregisterDirectIdentityRefreshContainer = function() end
applyA3._NativeContainerVisible = function(container) return container.visible end
applyA3._CreateNativeLane = function(_, lane)
    local c = Bound(NewNative(), lane)
    c:SetEnabled(true)
    c._msufA3NativeRegistered = true
    return c
end
applyA3._normalAuraLaneOrder = { "buff" }

local function Lane(size)
    return { enabled = true, rootKey = "Buffs", unit = "target", kind = "buff", size = size, max = 3 }
end
local function Apply(size, force)
    local container = nativeApply.ApplyLane(laneRoot, Lane(size), frame, force)
    Check(container == laneRoot.Buffs and container.visible and container.enabled,
        "the applied lane container is not the root's live lane")
    return container
end

-- 2a. A healthy parked owner is revived as before.
local first = Apply(20)
local second = Apply(21)
Check(#created == 2 and not first.visible and not first.enabled, "precondition: the first lane was not parked")
Check(Apply(20) == first and #created == 2, "a healthy parked owner was not revived")

-- 2b. A frozen parked owner is never handed back: a fresh container is built
-- and the frozen one leaves the park.
Freeze(second)
Check(not second.visible, "precondition: the frozen parked owner is shown")
local replacement = Apply(21)
Check(replacement ~= second and #created == 3, "a frozen parked owner was revived")
local park = laneRoot._msufA3ParkedLanes and laneRoot._msufA3ParkedLanes.Buffs or {}
for _, parked in pairs(park) do Check(parked ~= second, "the frozen owner stayed parked") end
Check(LastReport():find("parked", 1, true), "dropping a frozen parked owner was not reported")

-- 2c. The forced rebuild of a frozen live lane and Dispel/Purge owner.
local live = laneRoot.Buffs
Freeze(live)
applyA3._RefreshNativeAuraOwner(live, false)
NextFrame()
Check(laneRoot.Buffs ~= live and laneRoot.Buffs.enabled and laneRoot.Buffs.visible,
    "a frozen live lane was not replaced through the forced path")
Check(not live.enabled and not live.visible, "the frozen lane stayed live")
for _, parked in pairs(laneRoot._msufA3ParkedLanes and laneRoot._msufA3ParkedLanes.Buffs or {}) do
    Check(parked ~= live, "the frozen lane was parked for reuse")
end
local sensorConfig = { sensor = true, sensorRoot = true, enabled = true, rootKey = "DispelSensorNeutral",
    unit = "target", _msufA3StructuralSignature = "sensors" }
local liveSensors = nativeApply.ApplyDispelSensorRoot(laneRoot, sensorConfig, frame, false)
Check(liveSensors and laneRoot.DispelSensorNeutral == liveSensors, "precondition: no sensor owner was applied")
Freeze(liveSensors)
applyA3._RefreshNativeAuraOwner(liveSensors, false)
NextFrame()
Check(laneRoot.DispelSensorNeutral ~= liveSensors and laneRoot.DispelSensorNeutral.enabled,
    "a frozen Dispel/Purge owner was not replaced through the forced path")

print("aura native latch guard smoke: OK (" .. #rebuilt .. " event-path rebuilds, " .. #created .. " containers)")
