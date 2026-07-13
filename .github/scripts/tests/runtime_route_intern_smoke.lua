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

local MSUF = { UF = { Metadata = { defaultApplyMask = { StatusTextIndicator = true } } } }
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
    return 80, 100, false
end
UF.RegisterElement("Health", Health)

local NameText = {
    IsEnabled = function() return true end,
    Create = function() end,
    Apply = function() end,
    GetEvents = function() return {} end,
}
function NameText.Update(frame, event, unit)
    frame.nameCalls = (frame.nameCalls or 0) + 1
    frame.lastNameEvent, frame.lastNameUnit = event, unit
end
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
first.dynamicPowerUpdate = function(frame) frame.powerCalls = (frame.powerCalls or 0) + 1 end
second.dynamicPowerUpdate = function(frame) frame.powerCalls = (frame.powerCalls or 0) + 1 end
UF.ApplyElementToFrame(first, "Power", spec)
UF.ApplyElementToFrame(second, "Power", spec)
Check(first.UNIT_POWER_UPDATE ~= second.UNIT_POWER_UPDATE,
    "frame-owned update closures were incorrectly interned")
first.UNIT_POWER_UPDATE(first, "UNIT_POWER_UPDATE", "player")
second.UNIT_POWER_UPDATE(second, "UNIT_POWER_UPDATE", "player")
Check(first.powerCalls == 1 and second.powerCalls == 1, "private routes lost frame-local update state")

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
