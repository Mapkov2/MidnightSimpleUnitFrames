-- Regression coverage for event-driven OFFLINE/DEAD/GHOST recovery.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local connected, dead, ghost, afk, dnd = true, false, false, false, false
local health, healthMax = 100, 100
local SECRET = {}

_G.issecretvalue = function(value) return value == SECRET end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function() return connected end
_G.UnitIsDeadOrGhost = function() return dead or ghost end
_G.UnitIsGhost = function() return ghost end
_G.UnitIsAFK = function() return afk end
_G.UnitIsDND = function() return dnd end
_G.UnitHealth = function() return health end
_G.UnitHealthMax = function() return healthMax end
_G.UnitHealthPercent = function() return health end
_G.UnitInPartyIsAI = function() return false end
_G.GetTime = function() return 1 end

local elements = {}
local UF = {
    elements = elements,
    Layers = {},
    RegisterElement = function(name, element) elements[name] = element end,
    UnitExistsSafe = function() return true end,
    FreshUnitState = function() return nil end,
    ReadConnectedCached = function()
        if connected == SECRET then return true, false end
        return connected == true, true
    end,
    ReadDeadCached = function()
        if dead == SECRET then return false, false end
        return dead == true, true
    end,
}

local MSUF = {
    UF = UF,
    Secrets = {
        IsSecret = function(value) return value == SECRET end,
        IsNil = function(value) return value == nil end,
    },
}
MSUF.UFBarTextCommon = {
    UF = UF,
    UnitHealth = _G.UnitHealth,
    UnitHealthMax = _G.UnitHealthMax,
    UnitHealthPercent = _G.UnitHealthPercent,
    SCALE_100 = {},
}
_G.MSUF_NS = MSUF

local function NewTextRegion()
    local region = { shown = false, text = "", textWrites = 0, shownWrites = 0 }
    function region:SetText(value)
        self.text = value or ""
        self.textWrites = self.textWrites + 1
    end
    function region:SetShown(value)
        self.shown = value == true
        self.shownWrites = self.shownWrites + 1
    end
    function region:SetFont() return true end
    function region:SetTextColor() end
    function region:SetDrawLayer() end
    function region:SetShadowOffset() end
    function region:SetShadowColor() end
    function region:SetJustifyH() end
    function region:SetJustifyV() end
    function region:SetAlpha() end
    function region:ClearAllPoints() end
    function region:SetPoint() end
    return region
end

local function NewBar()
    local bar = {}
    function bar:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function bar:SetValue(value) self.value = value end
    function bar:SetStatusBarColor() end
    function bar:SetStatusBarTexture() end
    return bar
end

local statusText = {
    enabled = true,
    showDead = true,
    showGhost = true,
    showAFK = true,
    showDND = true,
    size = 14,
    anchor = "CENTER",
    layer = 7,
}
local status = { enabled = true, alpha = 1, statusText = statusText }
local spec = { enabled = true, scope = "single", health = { mode = "dark" }, status = status }

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local StatusTextIndicator = assert(elements.StatusTextIndicator, "status text element missing")
local Health = assert(elements.Health, "health element missing")
local UpdateStatusText = assert(MSUF.UFStatusRuntime and MSUF.UFStatusRuntime.UpdateStatusText,
    "shared status runtime missing")

local function NewUnitFrame(scope)
    local frame = {
        unit = scope == "group" and "party1" or "target",
        MSUFSpec = spec,
        hpBar = NewBar(),
        statusIndicatorText = NewTextRegion(),
        _msufHealthRuntimeColorEnabled = false,
        _msufIsGroupFrame = scope == "group" or nil,
        _msufActiveElements = { Health = true, StatusTextIndicator = scope ~= "group" },
    }
    StatusTextIndicator.Apply(frame, spec)
    return frame
end

local single = NewUnitFrame("single")
local singleStatusCalls = 0
single._msufUpdateStatusTextIndicator = function(...)
    singleStatusCalls = singleStatusCalls + 1
    return StatusTextIndicator.Update(...)
end

-- Normal living health is the steady-state hot path: no status resolver call.
for _ = 1, 100 do Health.Update(single, "UNIT_HEALTH", "target") end
Check(singleStatusCalls == 0, "living health ticks entered the single status resolver")

-- Health alone must drive DEAD/GHOST boundaries and their positive-health recovery.
health, dead = 0, true
Health.Update(single, "UNIT_HEALTH", "target")
Check(single._msufStatusTextValue == "DEAD", "single health boundary did not show DEAD")
health, dead = 100, false
Health.Update(single, "UNIT_HEALTH", "target")
Check(single._msufStatusTextValue == nil and single.statusIndicatorText.shown == false,
    "positive single health did not clear DEAD")

health, ghost = 0, true
Health.Update(single, "UNIT_HEALTH", "target")
Check(single._msufStatusTextValue == "GHOST", "single health boundary did not show GHOST")
health, ghost = 100, false
Health.Update(single, "UNIT_HEALTH", "target")
Check(single._msufStatusTextValue == nil, "positive single health did not clear GHOST")

-- The same target token can bind a different GUID while the old memo state is
-- still present. An identity refresh must replace DEAD without waiting for a
-- later health tick (the exact target/focus regression).
health, dead = 0, true
UpdateStatusText(single, status, "MSUF_UNIT_IDENTITY")
Check(single._msufStatusTextValue == "DEAD", "dead target identity was not rendered")
single._msufStatusTextConnectionKey = 0
single._msufStatusTextFlagsKey = 0
single._msufStatusTextHealthKey = 0
health, dead = 100, false
UpdateStatusText(single, status, "MSUF_UNIT_IDENTITY")
Check(single._msufStatusTextValue == nil, "living target identity inherited DEAD from the old target")

-- An identity refresh may observe a transient disconnect. The next authoritative
-- connection or positive-health event must not alias memo state from the old unit.
single._msufStatusTextConnectionKey = 0
single._msufStatusTextFlagsKey = 0
single._msufStatusTextHealthKey = 0
connected = false
UpdateStatusText(single, status, "MSUF_UNIT_IDENTITY")
Check(single._msufStatusTextValue == "OFFLINE", "identity refresh did not show OFFLINE")
connected = true
StatusTextIndicator.Update(single, "UNIT_CONNECTION", "target", true)
Check(single._msufStatusTextValue == nil, "online connection event left OFFLINE stuck")

afk = true
StatusTextIndicator.Update(single, "UNIT_FLAGS", "target")
Check(single._msufStatusTextValue == "AFK", "UNIT_FLAGS did not preserve AFK status")
afk, dnd = false, true
StatusTextIndicator.Update(single, "UNIT_FLAGS", "target")
Check(single._msufStatusTextValue == "DND", "UNIT_FLAGS did not preserve DND status")
dnd = false
StatusTextIndicator.Update(single, "UNIT_FLAGS", "target")
Check(single._msufStatusTextValue == nil, "UNIT_FLAGS did not clear AFK/DND status")

connected = false
UpdateStatusText(single, status, "MSUF_UNIT_IDENTITY")
connected = true
Health.Update(single, "UNIT_HEALTH", "target")
Check(single._msufStatusTextValue == nil, "positive health recovery left transient OFFLINE stuck")

-- Group frames reuse the same resolver and the Health-owned transition handoff.
local group = NewUnitFrame("group")
local groupStatusCalls = 0
group._msufUpdateGroupStatusState = function(frame, event, _, seedHP)
    groupStatusCalls = groupStatusCalls + 1
    UpdateStatusText(frame, status, event, seedHP)
end
for _ = 1, 100 do Health.Update(group, "UNIT_HEALTH", "party1") end
Check(groupStatusCalls == 0, "living health ticks entered the group status resolver")

health, dead = 0, true
Health.Update(group, "UNIT_HEALTH", "party1")
Check(group._msufStatusTextValue == "DEAD", "group health boundary did not show DEAD")
health, dead = 100, false
Health.Update(group, "UNIT_HEALTH", "party1")
Check(group._msufStatusTextValue == nil, "positive group health did not clear DEAD")

connected = false
group._msufUpdateGroupStatusState(group, "UNIT_CONNECTION", "party1")
Check(group._msufStatusTextValue == "OFFLINE", "group connection event did not show OFFLINE")
connected = true
Health.Update(group, "UNIT_HEALTH", "party1")
Check(group._msufStatusTextValue == nil, "group health recovery left OFFLINE stuck")

-- Secret health is unknown: it must not fabricate DEAD/OFFLINE or enter the sink.
health = SECRET
local callsBeforeSecret = singleStatusCalls
Health.Update(single, "UNIT_HEALTH", "target")
Check(singleStatusCalls == callsBeforeSecret and single._msufStatusTextValue == nil,
    "secret health fabricated a gone state")

print("PASS status lifecycle: OFFLINE/DEAD/GHOST recover event-driven with zero living-tick sink calls")
