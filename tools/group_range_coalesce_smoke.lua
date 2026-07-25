_G = _G or _ENV

local corePath = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local rangePath = "MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"
local handle = io.open(corePath, "r")
if not handle then
    corePath = "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
    rangePath = "UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"
else
    handle:close()
end

local SECRET_UNIT = {}
local SECRET_RANGE = {}
local MSUF = {
    UF = {
        Metadata = {
            runtimeUpdateOwners = { GroupRangeFade = true },
        },
    },
    GF = { frames = {} },
}

_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
_G.UnitGUID = function(unit) return unit end
local rangePolls = 0
_G.UnitInRange = function()
    rangePolls = rangePolls + 1
    return true, true
end
_G.GetTime = function() return 1 end
_G.issecretvalue = function(value)
    return value == SECRET_UNIT or value == SECRET_RANGE
end
local settleTimers = {}
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function(delay, callback)
        local timer = { delay = delay, callback = callback }
        function timer:Cancel() self.cancelled = true end
        settleTimers[#settleTimers + 1] = timer
        return timer
    end,
}

local settleDriver
_G.CreateFrame = function()
    local driver = { events = {}, scripts = {} }
    function driver:SetScript(kind, callback) self.scripts[kind] = callback end
    function driver:RegisterEvent(event) self.events[event] = true end
    function driver:UnregisterEvent(event) self.events[event] = nil end
    settleDriver = driver
    return driver
end

local coreChunk, coreErr = loadfile(corePath)
assert(coreChunk, coreErr)
coreChunk("MidnightSimpleUnitFrames", MSUF)

local rangeChunk, rangeErr = loadfile(rangePath)
assert(rangeChunk, rangeErr)
rangeChunk("MidnightSimpleUnitFrames", MSUF)

local UF = assert(MSUF.UF, "UF namespace missing")
assert(UF.elements.GroupRangeFade, "group range element missing")

local function NewFrame(unit)
    local frame = {
        unit = unit,
        unitEvents = {},
        genericEvents = {},
        hooks = {},
        maxUnitTokens = 0,
    }
    function frame:SetScript(kind, callback) self[kind] = callback end
    function frame:HookScript(kind, callback)
        local list = self.hooks[kind] or {}
        list[#list + 1] = callback
        self.hooks[kind] = list
    end
    function frame:IsVisible() return true end
    function frame:UnregisterAllEvents()
        self.unitEvents = {}
        self.genericEvents = {}
    end
    function frame:RegisterUnitEvent(event, ...)
        local count = select("#", ...)
        self.maxUnitTokens = math.max(self.maxUnitTokens, count)
        assert(count == 1, "group range must register exactly one unit token per frame")
        self.unitEvents[event] = select(1, ...)
        return true
    end
    function frame:RegisterEvent(event) self.genericEvents[event] = true end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        self.booleanValue = value
        self.booleanInAlpha = inAlpha
        self.booleanOutAlpha = outAlpha
    end
    return frame
end

local function ApplyRangeFrame(unit, key)
    local frame = NewFrame(unit)
    MSUF.GF.frames[frame] = true
    UF.ApplySpec(frame, {
        unit = unit,
        key = key,
        scope = "group",
        enabled = true,
        group = {
            rangeFadeEnabled = true,
            rangeFadeAlpha = 0.4,
            rangeFadeLayer = "frame",
        },
    })
    return frame
end

local partyFrames = {}
for i = 1, 4 do
    partyFrames[i] = ApplyRangeFrame("party" .. i, "party")
end

local raidFrames = {}
for i = 1, 40 do
    raidFrames[i] = ApplyRangeFrame("raid" .. i, "raid")
end

for _, collection in ipairs({ partyFrames, raidFrames }) do
    for i = 1, #collection do
        local frame = collection[i]
        assert(frame.maxUnitTokens == 1,
            "party and raid range routes must stay below Blizzard's four-token cap")
        assert(frame.unitEvents.UNIT_IN_RANGE_UPDATE == frame.unit,
            "range update must be filtered to the frame's bound unit")
        assert(frame.unitEvents.UNIT_PHASE == frame.unit
            and frame.unitEvents.UNIT_CTR_OPTIONS == frame.unit
            and frame.unitEvents.UNIT_OTHER_PARTY_CHANGED == frame.unit,
            "range invalidation events must be frame-local unit events")
        assert(frame.genericEvents.UNIT_IN_RANGE_UPDATE == nil,
            "range update must not use an unfiltered global subscription")
    end
end

local restrictedFrame = raidFrames[20]
restrictedFrame.booleanValue = nil
local auraRangeCalls = 0
restrictedFrame._msufApplyPartyAuraRangeGate = function(frame, inRange)
    auraRangeCalls = auraRangeCalls + 1
    frame.auraRangeValue = inRange
end
restrictedFrame.OnEvent(restrictedFrame, "UNIT_IN_RANGE_UPDATE", SECRET_UNIT, SECRET_RANGE)
assert(restrictedFrame.booleanValue == SECRET_RANGE,
    "secret event unit must be ignored while secret inRange reaches SetAlphaFromBoolean")
assert(restrictedFrame.booleanInAlpha == 1 and restrictedFrame.booleanOutAlpha == 0.4,
    "secret range update must retain the configured in/out alpha mapping")
assert(auraRangeCalls == 1 and restrictedFrame.auraRangeValue == SECRET_RANGE,
    "group range route did not forward the opaque payload to its compiled aura follower")

UF.OnUnitChanged(restrictedFrame, "raid20", "raid41")
assert(restrictedFrame.unitEvents.UNIT_IN_RANGE_UPDATE == "raid41",
    "range event filter must follow a rebound secure-header unit")

UF.ApplySpec(restrictedFrame, {
    unit = "raid41",
    key = "raid",
    scope = "group",
    enabled = true,
    group = { rangeFadeEnabled = false, hideOfflineEnabled = false },
})
assert(restrictedFrame.unitEvents.UNIT_IN_RANGE_UPDATE == nil,
    "disabling group range must remove the frame-local range subscription")
assert(restrictedFrame.alpha == 1,
    "disabling group range must restore full frame alpha")

assert(settleDriver and settleDriver.events.PLAYER_ENTERING_WORLD,
    "range settle driver must remain available for initial/world-state catch-up")

local disabledRebindChecks = 0
MSUF.GF.IsHeaderLayoutRebindActive = function()
    disabledRebindChecks = disabledRebindChecks + 1
    return false
end
local disabledPollsBefore = rangePolls
restrictedFrame.hooks.OnShow[#restrictedFrame.hooks.OnShow](restrictedFrame)
assert(disabledRebindChecks == 0 and rangePolls == disabledPollsBefore,
    "disabled group range performed work from its permanent OnShow hook")

local coalescedFrame = partyFrames[1]
local headerRebindActive = true
MSUF.GF.IsHeaderLayoutRebindActive = function(candidate)
    return headerRebindActive and candidate == coalescedFrame
end
local pollsBefore = rangePolls
for i = 1, #coalescedFrame.hooks.OnShow do
    coalescedFrame.hooks.OnShow[i](coalescedFrame)
end
assert(rangePolls == pollsBefore and coalescedFrame._msufGFRangeSettleDeferred == true,
    "header relayout must defer the range settle instead of polling before the scan")
assert(UF.FlushDeferredGroupRangeSettle(coalescedFrame) == true
    and rangePolls == pollsBefore + 1
    and coalescedFrame._msufGFRangeSettleDeferred == nil,
    "post-scan range settle must run exactly once")
headerRebindActive = false
pollsBefore = rangePolls
for i = 1, #coalescedFrame.hooks.OnShow do
    coalescedFrame.hooks.OnShow[i](coalescedFrame)
end
assert(rangePolls == pollsBefore + 1,
    "ordinary range OnShow must retain its immediate settled-state refresh")

-- A delayed world-settle belongs only to the currently visible consumers.
-- Hiding the final consumer must cancel the native timer instead of retaining
-- all group-frame references until it wakes.
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_ENTERING_WORLD")
local delayedSettle = settleTimers[#settleTimers]
assert(delayedSettle and delayedSettle.delay == 0.2,
    "world transition did not arm the cancellable delayed settle")
for _, collection in ipairs({ partyFrames, raidFrames }) do
    for i = 1, #collection do
        local candidate = collection[i]
        local hooks = candidate.hooks.OnHide or {}
        for j = 1, #hooks do hooks[j](candidate) end
    end
end
assert(delayedSettle.cancelled == true,
    "last hidden group range consumer retained its delayed settle timer")
assert(settleDriver.events.PLAYER_ENTERING_WORLD == nil,
    "last hidden group range consumer retained the shared settle events")

print("group_range_coalesce_smoke: ok")
