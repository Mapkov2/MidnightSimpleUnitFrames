_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"
local handle = io.open(path, "r")
if not handle then path = "UnitFrames/Engine/MSUF_UF_Core.lua" else handle:close() end

local MSUF = { UF = { Metadata = { runtimeUpdateOwners = {
    GroupStatusRuntime = true,
    GroupVisuals = true,
    GroupRangeFade = true,
} } } }
_G.MSUF_NS = MSUF
_G.UnitExists = function() return true end
local secretValue = {}
_G.issecretvalue = function(value) return value == secretValue end
_G.InCombatLockdown = function() return false end
local lifecycleDriver
_G.CreateFrame = function()
    local driver = { events = {} }
    function driver:RegisterEvent(event) self.events[event] = true end
    function driver:SetScript(kind, script) self[kind] = script end
    lifecycleDriver = driver
    return driver
end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local UF = assert(MSUF.UF, "UF namespace missing")
local healthEvents = { "UNIT_HEALTH", "UNIT_CONNECTION" }
local expectedUnitState
local expectedIdentityReady
local healthUpdateCalls = 0
local powerUpdateCalls = 0
local statusUpdateCalls = 0
local visualUpdateCalls = 0
local healthMetadataCalls = 0
local healthUnits = {}
local powerUnits = {}
local statusUnits = {}
local visualUnits = {}
UF.RegisterElement("Health", {
    IsEnabled = function(_, spec) return spec.healthEnabled ~= false end,
    GetEvents = function() return healthEvents end,
    GetUnitlessEvents = function(_, spec)
        return spec.groupLifecycle and { "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" } or nil
    end,
    Update = function(runtimeFrame, _, unit)
        healthUpdateCalls = healthUpdateCalls + 1
        healthUnits[runtimeFrame] = unit
        if expectedUnitState then
            assert(runtimeFrame._msufUnitState == expectedUnitState,
                "dispatch must reuse the existing unit-state table")
            assert(expectedUnitState.ready == false,
                "dispatch must invalidate reused unit-state contents before the first consumer")
            assert(expectedUnitState.dispatchToken == nil
                and expectedUnitState.identityReady == expectedIdentityReady,
                "dispatch used the wrong event-specific identity invalidation policy")
            expectedUnitState.ready = true
            expectedUnitState.dispatchToken = runtimeFrame._msufDispatchToken
        end
    end,
    UpdateGroupLifecycleMetadata = function(runtimeFrame, _, unit)
        healthMetadataCalls = healthMetadataCalls + 1
        assert(runtimeFrame.MSUFUnitKey == unit, "AI metadata gate received the wrong bound unit")
        return false
    end,
})
UF.RegisterElement("Power", {
    IsEnabled = function(_, spec) return spec.powerEnabled ~= false end,
    GetEvents = function(_, spec)
        return spec.extendedEvents and { "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER" } or { "UNIT_POWER_UPDATE" }
    end,
    Update = function(runtimeFrame, _, unit)
        powerUpdateCalls = powerUpdateCalls + 1
        powerUnits[runtimeFrame] = unit
    end,
})
UF.RegisterElement("GroupRangeFade", {
    IsEnabled = function(_, spec) return spec.rangeEnabled == true end,
    GetEvents = function() return { "UNIT_IN_RANGE_UPDATE" } end,
    Update = function() end,
})
UF.RegisterElement("GroupStatusRuntime", {
    IsEnabled = function(_, spec) return spec.groupLifecycle == true end,
    -- Core's shared lifecycle plan owns PARTY_MEMBER_ENABLE/DISABLE and calls
    -- this active follower once; the element must not declare duplicate routes.
    GetEvents = function() return {} end,
    Update = function(runtimeFrame, _, unit)
        statusUpdateCalls = statusUpdateCalls + 1
        statusUnits[runtimeFrame] = unit
    end,
})
UF.RegisterElement("GroupVisuals", {
    IsEnabled = function(_, spec) return spec.groupLifecycle == true end,
    GetEvents = function() return {} end,
    Update = function(runtimeFrame, _, unit)
        visualUpdateCalls = visualUpdateCalls + 1
        visualUnits[runtimeFrame] = unit
    end,
})

local frame = { unitEvents = {}, genericEvents = {}, unregisterAllCount = 0 }
function frame:SetScript(kind, script) self[kind] = script end
function frame:IsVisible() return true end
function frame:UnregisterAllEvents()
    self.unregisterAllCount = self.unregisterAllCount + 1
    self.unitEvents = {}
    self.genericEvents = {}
end
function frame:RegisterUnitEvent(event, unit)
    assert(type(unit) == "string" and unit ~= "", "invalid unit token reached RegisterUnitEvent")
    self.unitEvents[event] = unit
end
function frame:RegisterEvent(event) self.genericEvents[event] = true end

local spec = { unit = "targettarget", key = "targettarget", scope = "single", enabled = true }
UF.ApplySpec(frame, spec)
assert(frame.unitEvents.UNIT_HEALTH == "targettarget", "health event must use frame-local RegisterUnitEvent")
assert(frame.unitEvents.UNIT_POWER_UPDATE == "targettarget", "power event must use frame-local RegisterUnitEvent")
assert(frame.unitEvents.UNIT_TARGET == "target", "dependent identity event must route through its parent unit")
assert(frame.genericEvents.UNIT_HEALTH == nil, "valid unit event must not fall back to global RegisterEvent")
assert(frame.unregisterAllCount == 1, "initial spec must build routing once")

expectedUnitState = { ready = true, dispatchToken = 0, identityReady = true }
expectedIdentityReady = true
frame._msufUnitState = expectedUnitState
frame.OnEvent(frame, "UNIT_HEALTH", "targettarget")
assert(healthUpdateCalls == 1, "health route did not execute")
assert(frame._msufUnitState == expectedUnitState and expectedUnitState.ready == true,
    "health route did not preserve and refill the reusable unit-state table")
assert(frame._msufDispatchActive == nil, "dispatch activity leaked after event completion")
frame.OnEvent(frame, "UNIT_HEALTH", "targettarget")
assert(healthUpdateCalls == 2 and frame._msufUnitState == expectedUnitState,
    "subsequent dispatch allocated or lost the reusable unit-state table")
expectedIdentityReady = nil
frame.OnEvent(frame, "UNIT_CONNECTION", "targettarget")
assert(healthUpdateCalls == 3 and expectedUnitState.identityReady == nil,
    "connection dispatch retained identity that may become newly readable")
expectedUnitState = nil
expectedIdentityReady = nil

UF.Config = {
    RefreshUnit = function() return spec end,
}
UF.frames.targettarget = frame
UF.frameList[1] = frame

local runtimePath = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Runtime.lua"
local runtimeHandle = io.open(runtimePath, "r")
if not runtimeHandle then runtimePath = "UnitFrames/Engine/MSUF_UF_Runtime.lua" else runtimeHandle:close() end
local runtimeChunk, runtimeErr = loadfile(runtimePath)
assert(runtimeChunk, runtimeErr)
runtimeChunk("MidnightSimpleUnitFrames", MSUF)

assert(UF.RefreshElements("targettarget", { "Health", "Power" }, "MSUF_COLOR_CHANGE") == true)
assert(frame.unregisterAllCount == 1,
    "visual refresh with unchanged event topology must not rebuild routing")

spec = {
    unit = "targettarget", key = "targettarget", scope = "single", enabled = true,
    extendedEvents = true,
}
healthEvents[2] = "UNIT_FLAGS"
assert(UF.RefreshElements("targettarget", { "Health", "Power" }, "MSUF_CONFIG") == true)
assert(frame.unregisterAllCount == 2,
    "multi-element refresh must rebuild changed routing exactly once")
assert(frame.unitEvents.UNIT_FLAGS == "targettarget", "changed health route missing")
assert(frame.unitEvents.UNIT_DISPLAYPOWER == "targettarget", "changed power route missing")

spec = {
    unit = "targettarget", key = "targettarget", scope = "single", enabled = true,
    extendedEvents = true, healthEnabled = false,
}
assert(UF.RefreshElements("targettarget", { "Health", "Power" }, "MSUF_CONFIG") == true)
assert(frame.unregisterAllCount == 3, "disabling an element must rebuild routing once")
assert(frame.unitEvents.UNIT_HEALTH == nil and frame.unitEvents.UNIT_FLAGS == nil,
    "disabled element left stale event handlers")
assert(frame.unitEvents.UNIT_POWER_UPDATE == "targettarget",
    "unrelated active element route was lost")

healthEvents[2] = nil
local groupFrame = { unitEvents = {}, genericEvents = {}, unregisterAllCount = 0 }
function groupFrame:SetScript(kind, script) self[kind] = script end
function groupFrame:HookScript(kind, script)
    self.hooks = self.hooks or {}
    self.hooks[kind] = script
end
function groupFrame:IsVisible() return true end
function groupFrame:UnregisterAllEvents()
    self.unregisterAllCount = self.unregisterAllCount + 1
    self.unitEvents, self.genericEvents = {}, {}
end
function groupFrame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
function groupFrame:RegisterEvent(event) self.genericEvents[event] = true end

UF.ApplySpec(groupFrame, {
    unit = "party1", key = "party", scope = "group", enabled = true, groupLifecycle = true,
})
assert(groupFrame.unitEvents.PARTY_MEMBER_ENABLE == nil
    and groupFrame.unitEvents.PARTY_MEMBER_DISABLE == nil,
    "party lifecycle events leaked into frame-local RegisterUnitEvent")
assert(groupFrame.genericEvents.PARTY_MEMBER_ENABLE == nil
    and groupFrame.genericEvents.PARTY_MEMBER_DISABLE == nil,
    "party lifecycle events must use the single shared driver, not per-frame RegisterEvent")
assert(lifecycleDriver and lifecycleDriver.events.PARTY_MEMBER_ENABLE
    and lifecycleDriver.events.PARTY_MEMBER_DISABLE and type(lifecycleDriver.OnEvent) == "function",
    "shared party lifecycle driver was not registered")
assert(groupFrame.hooks and type(groupFrame.hooks.OnShow) == "function",
    "group children must install an event-driven OnShow state catch-up")

local rangeVisible = true
local rangeFrame = { unitEvents = {}, genericEvents = {}, hooks = {} }
function rangeFrame:SetScript(kind, script) self[kind] = script end
function rangeFrame:HookScript(kind, script)
    local list = self.hooks[kind] or {}
    list[#list + 1] = script
    self.hooks[kind] = list
end
function rangeFrame:IsVisible() return rangeVisible end
function rangeFrame:UnregisterAllEvents()
    self.unitEvents, self.genericEvents = {}, {}
end
function rangeFrame:UnregisterEvent(event)
    self.unitEvents[event] = nil
    self.genericEvents[event] = nil
end
function rangeFrame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
function rangeFrame:RegisterEvent(event) self.genericEvents[event] = true end
UF.ApplySpec(rangeFrame, {
    unit = "target", key = "target", scope = "single", enabled = true,
    rangeEnabled = true,
})
assert(rangeFrame.unitEvents.UNIT_IN_RANGE_UPDATE == "target",
    "visible range frame must register its unit-filtered range event")
assert(type(rangeFrame.hooks.OnHide) == "table" and type(rangeFrame.hooks.OnShow) == "table",
    "core visibility hooks missing")

rangeVisible = false
for i = 1, #rangeFrame.hooks.OnHide do rangeFrame.hooks.OnHide[i](rangeFrame) end
assert(rangeFrame.unitEvents.UNIT_IN_RANGE_UPDATE == nil,
    "hidden frame retained the native range subscription")
assert(type(rangeFrame.UNIT_IN_RANGE_UPDATE) == "function",
    "hiding a frame must retain its compiled range route")

rangeVisible = true
for i = 1, #rangeFrame.hooks.OnShow do rangeFrame.hooks.OnShow[i](rangeFrame) end
assert(rangeFrame.unitEvents.UNIT_IN_RANGE_UPDATE == "target",
    "shown frame did not restore its unit-filtered range subscription")

local groupFrame2 = { unitEvents = {}, genericEvents = {}, unregisterAllCount = 0 }
function groupFrame2:SetScript(kind, script) self[kind] = script end
function groupFrame2:IsVisible() return true end
function groupFrame2:UnregisterAllEvents()
    self.unregisterAllCount = self.unregisterAllCount + 1
    self.unitEvents, self.genericEvents = {}, {}
end
function groupFrame2:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
function groupFrame2:RegisterEvent(event) self.genericEvents[event] = true end
UF.ApplySpec(groupFrame2, {
    unit = "party2", key = "party", scope = "group", enabled = true, groupLifecycle = true,
})

local healthOnlyFrame = { unitEvents = {}, genericEvents = {}, unregisterAllCount = 0 }
function healthOnlyFrame:SetScript(kind, script) self[kind] = script end
function healthOnlyFrame:IsVisible() return true end
function healthOnlyFrame:UnregisterAllEvents()
    self.unregisterAllCount = self.unregisterAllCount + 1
    self.unitEvents, self.genericEvents = {}, {}
end
function healthOnlyFrame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
function healthOnlyFrame:RegisterEvent(event) self.genericEvents[event] = true end
UF.ApplySpec(healthOnlyFrame, {
    unit = "party3", key = "party", scope = "group", enabled = true,
    groupLifecycle = true, powerEnabled = false,
})

local healthBefore, powerBefore = healthUpdateCalls, powerUpdateCalls
local statusBefore, visualBefore = statusUpdateCalls, visualUpdateCalls
local metadataBefore = healthMetadataCalls
MSUF.GF = {
    ResolveLifecycleFrame = function(unit)
        if unit == "party1" then return groupFrame, true end
        return nil, false
    end,
}
lifecycleDriver.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", "party1")
assert(healthUpdateCalls == healthBefore + 1 and powerUpdateCalls == powerBefore + 2,
    "validated lifecycle target must keep heavy health work O(1) while power stays global")
assert(healthMetadataCalls == metadataBefore + 2,
    "non-target frames must use the cheap compiled AI metadata gate")
assert(statusUpdateCalls == statusBefore + 3,
    "presence status must retain Blizzard's group-global lifecycle semantics")
assert(visualUpdateCalls == visualBefore + 3,
    "global-minimal lifecycle path must retain group visual presence followers")
assert(healthUnits[groupFrame] == "party1" and powerUnits[groupFrame] == "party1"
    and healthUnits[groupFrame2] ~= "party2" and powerUnits[groupFrame2] == "party2"
    and healthUnits[healthOnlyFrame] ~= "party3"
    and statusUnits[groupFrame] == "party1" and statusUnits[groupFrame2] == "party2"
    and statusUnits[healthOnlyFrame] == "party3"
    and visualUnits[groupFrame] == "party1" and visualUnits[groupFrame2] == "party2"
    and visualUnits[healthOnlyFrame] == "party3",
    "target-full/global-minimal lifecycle dependencies used the wrong bound units")
assert(groupFrame._msufGroupLifecyclePlan == groupFrame2._msufGroupLifecyclePlan,
    "identical group archetypes must share one interned lifecycle work plan")
assert(groupFrame._msufGroupLifecyclePlan ~= healthOnlyFrame._msufGroupLifecyclePlan
    and type(groupFrame._msufGroupLifecyclePlan.fullPath) == "function"
    and type(groupFrame._msufGroupLifecyclePlan.globalPath) == "function",
    "compiled lifecycle plan shape or archetype split is invalid")

healthBefore, powerBefore = healthUpdateCalls, powerUpdateCalls
statusBefore, visualBefore = statusUpdateCalls, visualUpdateCalls
metadataBefore = healthMetadataCalls
MSUF.GF.ResolveLifecycleFrame = function() return nil, false end
lifecycleDriver.OnEvent(lifecycleDriver, "PARTY_MEMBER_DISABLE", "party1")
assert(healthUpdateCalls == healthBefore + 3 and powerUpdateCalls == powerBefore + 2
    and statusUpdateCalls == statusBefore + 3 and visualUpdateCalls == visualBefore + 3,
    "index/rebind/alias miss must preserve the authoritative full broadcast fallback")
assert(healthMetadataCalls == metadataBefore,
    "full fallback must not run the global-minimal metadata path")

healthBefore = healthUpdateCalls
lifecycleDriver.OnEvent(lifecycleDriver, "PARTY_MEMBER_ENABLE", secretValue)
assert(healthUpdateCalls == healthBefore + 3,
    "secret UnitTokenVariant must fall back without token comparison")

healthBefore, powerBefore = healthUpdateCalls, powerUpdateCalls
statusBefore, visualBefore = statusUpdateCalls, visualUpdateCalls
groupFrame.hooks.OnShow(groupFrame)
assert(healthUpdateCalls == healthBefore + 1 and powerUpdateCalls == powerBefore + 1
    and statusUpdateCalls == statusBefore + 1 and visualUpdateCalls == visualBefore + 1,
    "OnShow must refresh exactly the newly visible group child")

local headerRebindActive = true
MSUF.GF.IsHeaderLayoutRebindActive = function(candidate)
    return headerRebindActive and candidate == groupFrame
end
healthBefore, powerBefore = healthUpdateCalls, powerUpdateCalls
statusBefore, visualBefore = statusUpdateCalls, visualUpdateCalls
groupFrame.hooks.OnShow(groupFrame)
assert(healthUpdateCalls == healthBefore and powerUpdateCalls == powerBefore
    and statusUpdateCalls == statusBefore and visualUpdateCalls == visualBefore
    and groupFrame._msufGFHeaderOnShowDeferred == true,
    "MSUF-owned header relayout must defer the expensive child lifecycle to its scan")
headerRebindActive = false
groupFrame.hooks.OnShow(groupFrame)
assert(healthUpdateCalls == healthBefore + 1 and powerUpdateCalls == powerBefore + 1
    and statusUpdateCalls == statusBefore + 1 and visualUpdateCalls == visualBefore + 1
    and groupFrame._msufGFHeaderOnShowDeferred == nil,
    "ordinary OnShow must clear a stale deferred marker and retain full catch-up behavior")

io.write("unit_event_routing_smoke: ok\n")
