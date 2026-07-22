-- Standalone regression for immutable event-list and direct-route interning.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:HookScript(name, callback) self.hooks[name] = callback end
function Frame:IsVisible() return self.visible ~= false end
function Frame:RegisterEvent(event) self.registered[event] = true end
function Frame:RegisterUnitEvent(event, unit)
    self.registered[event] = unit
end
function Frame:UnregisterEvent(event) self.registered[event] = nil end
function Frame:UnregisterAllEvents()
    for event in pairs(self.registered) do self.registered[event] = nil end
end

local function NewFrame(unit)
    return setmetatable({
        unit = unit,
        unitKey = unit,
        visible = true,
        scripts = {},
        hooks = {},
        registered = {},
    }, Frame)
end

_G.CreateFrame = function() return NewFrame(nil) end
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.issecretvalue = function() return false end

local MSUF = { UF = { Metadata = { defaultApplyMask = {
    StatusTextIndicator = true,
    Prediction = true,
    GroupVisuals = true,
} } } }
_G.MSUF_NS = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local UF = assert(MSUF.UF)

local calls = setmetatable({}, { __mode = "k" })
local Health = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION" } end,
}
function Health.Update(frame, event, unit)
    calls[frame] = (calls[frame] or 0) + 1
    frame.lastEvent, frame.lastUnit = event, unit
    return 80, 100, false, frame.seedCalc
end
UF.RegisterElement("Health", Health)

local Prediction = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_MAXHEALTH" } end,
}
function Prediction.Update(frame, event, unit, hp, hpMax, seedCalc)
    frame.predictionEvent = event
    frame.predictionUnit = unit
    frame.predictionHP = hp
    frame.predictionMax = hpMax
    frame.predictionCalc = seedCalc
end
UF.RegisterElement("Prediction", Prediction)

local HealthText = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_HEALTH", "UNIT_MAXHEALTH" } end,
}
function HealthText.Update(frame, event, unit, hp, hpMax)
    frame.healthTextEvent = event
    frame.healthTextUnit = unit
    frame.healthTextHP = hp
    frame.healthTextMax = hpMax
end
function HealthText.MarkValueDirty(frame, event, unit, hp, hpMax)
    frame.healthDirtyCalls = (frame.healthDirtyCalls or 0) + 1
    frame.healthDirtyEvent, frame.healthDirtyUnit = event, unit
    frame.healthDirtyHP, frame.healthDirtyMax = hp, hpMax
end
function HealthText.SelectEventUpdate(frame, spec, event, update)
    return event == "UNIT_HEALTH" and HealthText.MarkValueDirty or update
end
HealthText.NoDispatchUpdates = { [HealthText.MarkValueDirty] = true }
UF.RegisterElement("HealthText", HealthText)

local GroupVisuals = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_MAXHEALTH" } end,
}
function GroupVisuals.Update(frame, event, unit, hp, hpMax)
    frame.visualsEvent = event
    frame.visualsUnit = unit
    frame.visualsHP = hp
    frame.visualsMax = hpMax
end
UF.RegisterElement("GroupVisuals", GroupVisuals)

local NameText = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_NAME_UPDATE" } end,
}
function NameText.Update(frame, event, unit)
    frame.nameCalls = (frame.nameCalls or 0) + 1
    frame.lastNameEvent, frame.lastNameUnit = event, unit
end
NameText.NoDispatchUpdates = { [NameText.Update] = true }
UF.RegisterElement("NameText", NameText)

local StatusTextIndicator = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return {} end,
}
function StatusTextIndicator.Update(frame, event, unit)
    frame.statusCalls = (frame.statusCalls or 0) + 1
    frame.lastStatusEvent, frame.lastStatusUnit = event, unit
end
UF.RegisterElement("StatusTextIndicator", StatusTextIndicator)

local spec = { enabled = true, key = "player", unit = "player", scope = "group" }
local first, second = NewFrame("player"), NewFrame("player")
UF.AttachFrame(first, { scope = "group" })
UF.AttachFrame(second, { scope = "group" })
UF.ApplyElementToFrame(first, "Health", spec)
UF.ApplyElementToFrame(second, "Health", spec)
UF.ApplyElementToFrame(first, "NameText", spec)
UF.ApplyElementToFrame(second, "NameText", spec)

Check(type(first.UNIT_HEALTH) == "function", "first route missing")
Check(first.UNIT_HEALTH == second.UNIT_HEALTH, "identical direct routes were not interned")
Check(first._msufEventNames == second._msufEventNames, "event-name plans were not interned")
Check(first._msufElementEventRoutes.Health.events == second._msufElementEventRoutes.Health.events,
    "element event lists were not interned")
Check(first._msufElementEventRoutes.Health == second._msufElementEventRoutes.Health,
    "immutable route snapshots were not interned")
Check(first._msufElementEventRoutes == second._msufElementEventRoutes,
    "identical runtime route plans were not interned")
Check(first._msufEvents == nil and second._msufEvents == nil, "builder maps leaked into runtime state")
Check(first._msufIdentityFns == second._msufIdentityFns,
    "identity function sequences were retained per frame")
Check(first._msufIdentityLabels == second._msufIdentityLabels,
    "identity labels were retained per frame")

-- Event-specific static text markers must remain inside the interned direct
-- Health route. Falling back to the generic per-frame list would erase the
-- batching win and retain one closure per raid child.
local dirtyFirst, dirtySecond = NewFrame("party2"), NewFrame("party2")
local dirtySpec = { enabled = true, key = "party2", unit = "party2", scope = "group" }
UF.AttachFrame(dirtyFirst, { scope = "group" })
UF.AttachFrame(dirtySecond, { scope = "group" })
UF.ApplyElementToFrame(dirtyFirst, "Health", dirtySpec)
UF.ApplyElementToFrame(dirtySecond, "Health", dirtySpec)
UF.ApplyElementToFrame(dirtyFirst, "HealthText", dirtySpec)
UF.ApplyElementToFrame(dirtySecond, "HealthText", dirtySpec)
Check(dirtyFirst.UNIT_HEALTH == dirtySecond.UNIT_HEALTH,
    "event-specific HealthText dirty marker escaped shared direct-route interning")
dirtyFirst.UNIT_HEALTH(dirtyFirst, "UNIT_HEALTH", "party2")
Check(calls[dirtyFirst] == 1 and dirtyFirst.healthDirtyCalls == 1,
    "direct Health route did not run the bar and dirty marker exactly once")
Check(dirtyFirst.healthDirtyHP == 80 and dirtyFirst.healthDirtyMax == 100,
    "direct Health route dropped the bar payload before the static dirty marker")

local seeded = NewFrame("party1")
seeded.seedCalc = {}
local seededSpec = { enabled = true, key = "party1", unit = "party1", scope = "group" }
UF.AttachFrame(seeded, { scope = "group" })
UF.ApplyElementToFrame(seeded, "Health", seededSpec)
UF.ApplyElementToFrame(seeded, "Prediction", seededSpec)
UF.ApplyElementToFrame(seeded, "HealthText", seededSpec)
UF.ApplyElementToFrame(seeded, "GroupVisuals", seededSpec)
seeded.UNIT_MAXHEALTH(seeded, "UNIT_MAXHEALTH", "party1")
Check(seeded.predictionHP == 80 and seeded.predictionMax == 100,
    ("direct health route did not forward seeded health values (hp=%s max=%s event=%s unit=%s)")
        :format(tostring(seeded.predictionHP), tostring(seeded.predictionMax),
            tostring(seeded.predictionEvent), tostring(seeded.predictionUnit)))
Check(seeded.predictionCalc == seeded.seedCalc,
    "direct health route dropped the dispatch-owned prediction calculator")
Check(seeded.healthTextHP == 80 and seeded.healthTextMax == 100,
    "direct health route did not forward values to health text")
Check(seeded.visualsHP == 80 and seeded.visualsMax == 100,
    "direct health route did not forward values to group visuals")
seeded.predictionCalc = nil
Check(UF.RunLeanIdentity(seeded, "MSUF_UNIT_IDENTITY") == true,
    "seeded identity route did not run")
Check(seeded.predictionCalc == seeded.seedCalc,
    "identity route dropped the dispatch-owned prediction calculator")
Check(first._msufIdentityPath == second._msufIdentityPath,
    "identity dispatch closures were retained per frame")
Check(first._msufRuntimeAllFns == second._msufRuntimeAllFns,
    "full-runtime function sequences were retained per frame")
Check(first._msufRuntimeAllLabels == second._msufRuntimeAllLabels,
    "full-runtime labels were retained per frame")
Check(first._msufRuntimeAllPath == second._msufRuntimeAllPath,
    "full-runtime dispatch closures were retained per frame")
Check(first._msufIdentityBarPath == second._msufIdentityBarPath,
    "identity bar function pairs were not interned")

first.UNIT_HEALTH(first, "UNIT_HEALTH", "player")
second.UNIT_HEALTH(second, "UNIT_HEALTH", "player")
Check(calls[first] == 1 and calls[second] == 1, "shared route did not preserve frame-local dispatch")
Check(first.lastUnit == "player" and second.lastUnit == "player", "shared route changed unit binding")
first._msufDispatchToken = 17
first.UNIT_NAME_UPDATE(first, "UNIT_NAME_UPDATE", "player")
Check(first.nameCalls == 1 and first._msufDispatchToken == 17 and first._msufDispatchActive == nil,
    "state-free single route entered the shared unit-state dispatch")

-- A hidden single frame can miss its target/focus identity event. OnShow must
-- re-run the already compiled lean identity plan once, without a poll/driver.
local targetSpec = { enabled = true, key = "target", unit = "target", scope = "single" }
local target = NewFrame("target")
target.visible = false
UF.AttachFrame(target, { scope = "single" })
UF.ApplyElementToFrame(target, "Health", targetSpec)
UF.ApplyElementToFrame(target, "NameText", targetSpec)
UF.ApplyElementToFrame(target, "StatusTextIndicator", targetSpec)
target.nameCalls = 0
target.statusCalls = 0
target.visible = true
target.hooks.OnShow(target)
Check(target.nameCalls == 1 and target.lastNameEvent == "MSUF_UF_ONSHOW",
    "single OnShow did not reseed the lean identity plan")
Check(target.statusCalls == 1 and target.lastStatusEvent == "MSUF_UF_ONSHOW",
    "single OnShow did not reseed status for the visible unit identity")

Check(UF.PrivatizeRuntimeStatusStateForDiagnostics == nil,
    "removed in-game diagnostics runtime API was reintroduced")

-- A selector may intentionally return a closure that owns frame-local state.
-- Such a function must never enter the strong shared-prototype cache.
local Power = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_POWER_UPDATE" } end,
    SelectUpdate = function(frame) return frame.dynamicPowerUpdate end,
}
UF.RegisterElement("Power", Power)
local PowerText = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return { "UNIT_POWER_UPDATE" } end,
}
function PowerText.Update(frame, event, unit, power, powerMax, powerType, powerToken, metaChanged)
    frame.powerTextCalls = (frame.powerTextCalls or 0) + 1
    frame.lastPowerPayload = { event, unit, power, powerMax, powerType, powerToken, metaChanged }
end
UF.RegisterElement("PowerText", PowerText)
first.dynamicPowerUpdate = function(frame)
    frame.powerCalls = (frame.powerCalls or 0) + 1
    return 35, 100, 3, "ENERGY", false
end
second.dynamicPowerUpdate = function(frame)
    frame.powerCalls = (frame.powerCalls or 0) + 1
    return 35, 100, 3, "ENERGY", false
end
UF.ApplyElementToFrame(first, "Power", spec)
UF.ApplyElementToFrame(second, "Power", spec)
UF.ApplyElementToFrame(first, "PowerText", spec)
UF.ApplyElementToFrame(second, "PowerText", spec)
Check(first.UNIT_POWER_UPDATE ~= second.UNIT_POWER_UPDATE,
    "frame-owned update closures were incorrectly interned")
first._msufDispatchToken = 41
second._msufDispatchToken = 73
first.UNIT_POWER_UPDATE(first, "UNIT_POWER_UPDATE", "player")
second.UNIT_POWER_UPDATE(second, "UNIT_POWER_UPDATE", "player")
Check(first.powerCalls == 1 and second.powerCalls == 1, "private routes lost frame-local update state")
Check(first.powerTextCalls == 1 and second.powerTextCalls == 1,
    "direct power routes did not update bar and text exactly once")
Check(first.lastPowerPayload[3] == 35 and first.lastPowerPayload[4] == 100
    and first.lastPowerPayload[5] == 3 and first.lastPowerPayload[6] == "ENERGY"
    and first.lastPowerPayload[7] == false,
    "direct power routes did not forward the bar payload to power text")
Check(first._msufDispatchToken == 41 and second._msufDispatchToken == 73
    and first._msufDispatchActive == nil and second._msufDispatchActive == nil,
    "state-free power routes mutated the shared unit-state dispatch")

-- Core unit rebinding must not enter Auras3 at all when its element is off.
-- The permanent integration callback is a cold-path owner, not permission to
-- resolve disabled aura config on every target/header identity change.
local auraUnitChangeCalls = 0
MSUF.MSUF_Auras3 = {
    OnFrameUnitChanged = function()
        auraUnitChangeCalls = auraUnitChangeCalls + 1
    end,
}
UF.OnUnitChanged(second, "player", "target")
Check(auraUnitChangeCalls == 0,
    "disabled Auras3 received Core OnUnitChanged work")
second._msufActiveElements.Auras = true
UF.OnUnitChanged(second, "target", "focus")
Check(auraUnitChangeCalls == 1,
    "active Auras3 did not receive Core OnUnitChanged")
second._msufActiveElements.Auras = nil

-- A castbar may temporarily borrow this frame's existing health lifecycle
-- route. Detach must notify it before deleting the compiled route so the owner
-- can promote itself to its minimal fallback instead of remaining falsely
-- marked as UF-owned.
UF.frames.player = first
local lifecycleOwner = {}
local lifecycleDetachCalls = 0
local attached = UF.SetHealthLifecycleSink("player", function(owner, frame, event)
    Check(owner == lifecycleOwner and frame == first, "detach lifecycle sink lost its owner/frame")
    if event == "MSUF_UF_LIFECYCLE_DETACH" then
        lifecycleDetachCalls = lifecycleDetachCalls + 1
    end
end, lifecycleOwner)
Check(attached == true, "health lifecycle sink did not attach")
Check(first._msufHealthLifecycleSink ~= nil, "attached lifecycle sink state missing")

UF.DetachFrame(first)
Check(first.UNIT_HEALTH == nil, "detach retained compiled event function")
Check(next(first.registered) == nil, "detach retained native events")
Check(first._msufGroupIdentityFns == nil and first._msufGroupIdentityLabels == nil,
    "detach retained shared group identity plan references")
Check(lifecycleDetachCalls == 1, "detach did not notify the lifecycle sink exactly once")
Check(first._msufHealthLifecycleSink == nil and first._msufHealthLifecycleSinkOwner == nil,
    "detach retained lifecycle sink state")
Check(type(second.UNIT_HEALTH) == "function", "detaching one frame damaged shared route")

print("PASS runtime route interning: shared event/runtime plans, no in-game profiler API, isolated detach")
