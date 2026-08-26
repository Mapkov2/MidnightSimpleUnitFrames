_G = _G or _ENV

local corePath = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local rangePath = "MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"

local SECRET_UNIT = {}
local SECRET_RANGE = {}
local SECRET_CHECK = {}
local instanceType = "party"
local nativeInRange, nativeChecked = true, true
local rangePolls, timerStarts = 0, 0
local inCombat = false

local MSUF = {
    UF = { Metadata = { runtimeUpdateOwners = { GroupRangeFade = true } } },
    GF = { frames = {} },
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.InCombatLockdown = function() return inCombat end
_G.GetTime = function() return 1 end
_G.UnitExists = function() return true end
_G.UnitGUID = function(unit) return unit end
_G.UnitIsVisible = function() return true end
_G.UnitPhaseReason = function() return nil end
_G.IsInInstance = function() return true, instanceType end
_G.UnitInRange = function(unit)
    assert(type(unit) == "string" and unit ~= "", "range query did not use the bound plain unit")
    rangePolls = rangePolls + 1
    return nativeInRange, nativeChecked
end
_G.issecretvalue = function(value)
    return value == SECRET_UNIT or value == SECRET_RANGE or value == SECRET_CHECK
end
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function(_, callback)
        timerStarts = timerStarts + 1
        return { Cancel = function() end, callback = callback }
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

local UF = assert(MSUF.UF, "UF namespace missing")
local batchBegins, batchEnds = 0, 0
local originalBegin = assert(UF.BeginEventRegistrationBatch)
local originalEnd = assert(UF.EndEventRegistrationBatch)
UF.BeginEventRegistrationBatch = function(...)
    batchBegins = batchBegins + 1
    return originalBegin(...)
end
UF.EndEventRegistrationBatch = function(...)
    batchEnds = batchEnds + 1
    return originalEnd(...)
end

local rangeChunk, rangeErr = loadfile(rangePath)
assert(rangeChunk, rangeErr)
rangeChunk("MidnightSimpleUnitFrames", MSUF)
assert(UF.elements.GroupRangeFade, "group range element missing")

local function NewFrame(unit)
    local frame = {
        unit = unit,
        visible = true,
        unitEvents = {},
        genericEvents = {},
        hooks = {},
    }
    function frame:SetScript(kind, callback) self[kind] = callback end
    function frame:HookScript(kind, callback)
        local hooks = self.hooks[kind] or {}
        hooks[#hooks + 1] = callback
        self.hooks[kind] = hooks
    end
    function frame:IsVisible() return self.visible end
    function frame:UnregisterAllEvents()
        self.unitEvents = {}
        self.genericEvents = {}
    end
    function frame:RegisterUnitEvent(event, ...)
        assert(select("#", ...) == 1, "range route registered more than one unit")
        self.unitEvents[event] = select(1, ...)
        return true
    end
    function frame:RegisterEvent(event) self.genericEvents[event] = true end
    function frame:UnregisterEvent(event)
        self.unitEvents[event] = nil
        self.genericEvents[event] = nil
    end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:SetAlphaFromBoolean(value, inAlpha, outAlpha)
        self.booleanValue = value
        self.booleanInAlpha = inAlpha
        self.booleanOutAlpha = outAlpha
    end
    return frame
end

local function ApplyRangeFrame(unit)
    local frame = NewFrame(unit)
    MSUF.GF.frames[frame] = true
    UF.ApplySpec(frame, {
        unit = unit,
        key = unit == "player" and "party" or "raid",
        scope = "group",
        enabled = true,
        group = {
            rangeFadeEnabled = true,
            rangeFadeAlpha = 0.4,
            rangeFadeLayerMode = "frame",
        },
    })
    return frame
end

local function FireVisibility(frame, script)
    frame.visible = script == "OnShow"
    local hooks = frame.hooks[script] or {}
    for i = 1, #hooks do hooks[i](frame) end
end

local active = ApplyRangeFrame("raid1")
local hidden = ApplyRangeFrame("raid2")
assert(settleDriver and settleDriver.scripts.OnEvent, "range settle driver missing")

-- PvE must retain the direct compiled event callback: no UnitInRange call.
active.booleanValue = nil
local pollsBefore = rangePolls
nativeInRange, nativeChecked = true, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", false)
assert(rangePolls == pollsBefore and active.booleanValue == false,
    "PvE range event gained a native requery or ignored its payload")
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore and active._msufGFInRangeRaw == true,
    "PvE direct route did not retain the event-owned value")

-- Hide one consumer before the mode flip; it must repair its route on OnShow.
FireVisibility(hidden, "OnHide")
assert(hidden.unitEvents.UNIT_IN_RANGE_UPDATE == nil,
    "hidden range frame retained its unit event")

-- WoW reports ordinary Battlegrounds and Brawls through instanceType "pvp".
instanceType = "pvp"
settleDriver.scripts.OnEvent(settleDriver, "ZONE_CHANGED_NEW_AREA")
assert(batchBegins == 1 and batchEnds == 1,
    "PvE-to-Battleground route flip was not one registration batch")

active.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = false, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore + 1 and active.booleanValue == false,
    "Battleground event did not requery the bound unit exactly once")

-- Arena shares the compiled PvP route without a redundant topology rebuild.
instanceType = "arena"
settleDriver.scripts.OnEvent(settleDriver, "ZONE_CHANGED_NEW_AREA")
assert(batchBegins == 1 and batchEnds == 1,
    "Battleground-to-Arena transition rebuilt an identical range route")
pollsBefore = rangePolls
nativeInRange, nativeChecked = true, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", false)
assert(rangePolls == pollsBefore + 1 and active.booleanValue == true,
    "Arena event did not use its refreshed native value")

-- Secret checked/inRange returns must reach SetAlphaFromBoolean untouched.
active.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = SECRET_RANGE, SECRET_CHECK
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", SECRET_UNIT, false)
assert(rangePolls == pollsBefore + 1 and active.booleanValue == SECRET_RANGE,
    "secret PvP range return was inspected or lost")

-- An unchecked native result conservatively retains the event payload.
active.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = false, false
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore + 1 and active.booleanValue == true,
    "unchecked PvP query discarded the event-owned fallback")

-- Self and known-not-present members never pay the PvP range query.
local player = ApplyRangeFrame("player")
pollsBefore = rangePolls
player.OnEvent(player, "UNIT_IN_RANGE_UPDATE", "player", false)
assert(rangePolls == pollsBefore, "player group frame performed a PvP range query")

active._msufGFRangePresenceUnit = "raid1"
active._msufGFRangePresenceKnown = true
active._msufGFRangeNotPresent = true
active._msufGFRangeVisibilityNotPresent = nil
active.booleanValue = nil
pollsBefore = rangePolls
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore and active.booleanValue == false,
    "known-not-present member performed a PvP range query")
active._msufGFRangePresenceKnown = nil
active._msufGFRangeNotPresent = nil

nativeInRange, nativeChecked = true, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", false)
assert(active._msufGFInRangeRaw == true,
    "Arena route did not restore a known value before the PvE transition")

FireVisibility(hidden, "OnShow")
hidden.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = false, true
hidden.OnEvent(hidden, "UNIT_IN_RANGE_UPDATE", "raid2", true)
assert(rangePolls == pollsBefore + 1 and hidden.booleanValue == false,
    "hidden frame did not repair its compiled PvP route on show")

instanceType = "party"
settleDriver.scripts.OnEvent(settleDriver, "ZONE_CHANGED_NEW_AREA")
assert(batchBegins == 2 and batchEnds == 2,
    "return to PvE was not one registration batch")
active.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = true, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", false)
assert(rangePolls == pollsBefore and active.booleanValue == false,
    "PvP requery remained in the recurring PvE event path")

-- With every range consumer hidden the driver is inert and forgets its mode.
-- The first OnShow inside PvP must detect the context and repair only itself,
-- without a global registration batch.
FireVisibility(active, "OnHide")
FireVisibility(hidden, "OnHide")
FireVisibility(player, "OnHide")
local batchesBeforeHiddenEntry = batchBegins
instanceType = "pvp"
FireVisibility(active, "OnShow")
assert(batchBegins == batchesBeforeHiddenEntry and batchEnds == batchesBeforeHiddenEntry,
    "all-hidden PvP entry performed a redundant global route rebuild")
active.booleanValue = nil
pollsBefore = rangePolls
nativeInRange, nativeChecked = false, true
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore + 1 and active.booleanValue == false,
    "first visible PvP frame did not repair its range route")

-- Event registration is unprotected. A zone edge in combat must still swap
-- the compiled callback immediately; only the separate settle poll defers.
inCombat = true
instanceType = "party"
settleDriver.scripts.OnEvent(settleDriver, "ZONE_CHANGED_NEW_AREA")
assert(batchBegins == batchesBeforeHiddenEntry + 1
    and batchEnds == batchesBeforeHiddenEntry + 1,
    "combat PvP-to-PvE edge did not rebuild the visible event route once")
active.booleanValue = nil
pollsBefore = rangePolls
active.OnEvent(active, "UNIT_IN_RANGE_UPDATE", "raid1", true)
assert(rangePolls == pollsBefore and active.booleanValue == true,
    "combat context edge left the PvP query in the PvE callback")
inCombat = false
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_REGEN_ENABLED")

-- Drain the existing one-shot zone settle and prove no recurring work remains.
local flushes = 0
while settleDriver.scripts.OnUpdate do
    local callback = settleDriver.scripts.OnUpdate
    callback(settleDriver)
    flushes = flushes + 1
    assert(flushes < 10, "coalesced range settle did not drain")
end
assert(timerStarts == 0, "PvP route selection added a timer")
assert(settleDriver.events.PVP_MATCH_STATE_CHANGED == nil,
    "range fix added an unrelated PvP event subscription")

print("group_range_pvp_requery_smoke: ok")
