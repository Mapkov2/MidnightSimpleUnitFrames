_G = _G or _ENV

local corePath = "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"
local rangePath = "MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"
local handle = io.open(corePath, "r")
if not handle then
    corePath = "UnitFrames/Engine/MSUF_UF_Core.lua"
    rangePath = "UnitFrames/Range/MSUF_UF_Group_RangeFade.lua"
else
    handle:close()
end

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

local inCombat = false
local connected = {}
local now = 100
local timers = {}
local SECRET_UNIT = {}

_G.InCombatLockdown = function() return inCombat end
_G.UnitExists = function() return true end
_G.UnitIsConnected = function(unit) return connected[unit] ~= false end
_G.UnitGUID = function(unit) return unit end
_G.GetTime = function() return now end
_G.issecretvalue = function(value) return value == SECRET_UNIT end
_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = { at = now + delay, callback = callback, cancelled = false }
        function timer:Cancel() self.cancelled = true end
        timers[#timers + 1] = timer
        return timer
    end,
    After = function(delay, callback)
        timers[#timers + 1] = { at = now + delay, callback = callback, cancelled = false }
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

local function FlushTimers(targetTime)
    now = targetTime
    local ran = true
    while ran do
        ran = false
        for i = 1, #timers do
            local timer = timers[i]
            if timer and not timer.cancelled and not timer.ran and timer.at <= now then
                timer.ran = true
                timer.callback()
                ran = true
            end
        end
    end
end

assert(loadfile(corePath))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(rangePath))("MidnightSimpleUnitFrames", MSUF)

local UF = assert(MSUF.UF, "UF namespace missing")

local function NewFrame(unit)
    local frame = {
        unit = unit,
        unitEvents = {},
        genericEvents = {},
        hooks = {},
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
    function frame:RegisterUnitEvent(event, unitToken)
        self.unitEvents[event] = unitToken
    end
    function frame:RegisterEvent(event) self.genericEvents[event] = true end
    function frame:SetAlpha(value) self.alpha = value end
    return frame
end

local function ApplyOfflineFrame(unit, hideInCombat, delay)
    local frame = NewFrame(unit)
    MSUF.GF.frames[frame] = true
    UF.ApplySpec(frame, {
        unit = unit,
        key = "party",
        scope = "group",
        enabled = true,
        group = {
            rangeFadeEnabled = false,
            offlineAlpha = 0.35,
            hideOfflineEnabled = true,
            hideOfflineInCombat = hideInCombat == true,
            hideOfflineDelay = delay or 0,
        },
    })
    return frame
end

connected.party2 = false
local alwaysHiddenFrame = ApplyOfflineFrame("party2", true, 0)
assert(alwaysHiddenFrame.alpha == 0,
    "Hide offline in combat must hide an offline member outside combat")
assert(settleDriver and not settleDriver.events.PLAYER_REGEN_DISABLED,
    "always-hidden offline frames must not add a combat-transition subscription")

connected.party1 = false
local protectedFrame = ApplyOfflineFrame("party1", false, 0)
assert(protectedFrame.unitEvents.UNIT_CONNECTION == "party1",
    "offline visibility must use a frame-local UNIT_CONNECTION route")
assert(protectedFrame.alpha == 0,
    "an offline member must hide immediately outside combat when delay is zero")
assert(settleDriver and settleDriver.events.PLAYER_REGEN_DISABLED,
    "combat-sensitive offline visibility must subscribe to the central combat transition")
for i = 1, #protectedFrame.hooks.OnHide do
    protectedFrame.hooks.OnHide[i](protectedFrame)
end
assert(settleDriver.events.PLAYER_REGEN_DISABLED == nil,
    "a hidden combat-sensitive frame must release the central combat transition")
for i = 1, #protectedFrame.hooks.OnShow do
    protectedFrame.hooks.OnShow[i](protectedFrame)
end
assert(settleDriver.events.PLAYER_REGEN_DISABLED,
    "a shown combat-sensitive frame must restore the central combat transition")

inCombat = true
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_REGEN_DISABLED")
assert(protectedFrame.alpha == 0.35,
    "an offline member must remain visible at offline opacity when combat hiding is disabled")

inCombat = false
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_REGEN_ENABLED")
assert(protectedFrame.alpha == 0,
    "an offline member must hide again immediately after combat")

connected.party1 = true
protectedFrame.OnEvent(protectedFrame, "UNIT_CONNECTION", SECRET_UNIT, true)
assert(protectedFrame.alpha == 1,
    "UNIT_CONNECTION must restore a reconnected member without inspecting a restricted unit payload")

inCombat = true
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_REGEN_DISABLED")
assert(alwaysHiddenFrame.alpha == 0,
    "Hide offline in combat must keep an offline member hidden in combat")

connected.party3 = false
local delayedFrame = ApplyOfflineFrame("party3", false, 10)
assert(delayedFrame.alpha == 0.35,
    "an offline delay must keep the member at configured offline opacity")
FlushTimers(110)
assert(delayedFrame.alpha == 0.35,
    "an elapsed delay must not hide the member while combat hiding is disabled")
inCombat = false
settleDriver.scripts.OnEvent(settleDriver, "PLAYER_REGEN_ENABLED")
assert(delayedFrame.alpha == 0,
    "an elapsed offline delay must hide immediately when combat ends")

connected.party4 = false
local reconnectFrame = ApplyOfflineFrame("party4", false, 20)
assert(reconnectFrame.alpha == 0.35, "delayed offline member did not enter offline opacity")
connected.party4 = true
reconnectFrame.OnEvent(reconnectFrame, "UNIT_CONNECTION", "party4", true)
assert(reconnectFrame.alpha == 1, "reconnect before delay expiry did not restore full opacity")
assert(timers[#timers].cancelled == true,
    "removing the last offline-delay frame left its native timer armed")
FlushTimers(130)
assert(reconnectFrame.alpha == 1,
    "a stale offline-delay callback must not hide a reconnected member")

UF.ApplySpec(protectedFrame, {
    unit = "party1",
    key = "party",
    scope = "group",
    enabled = true,
    group = { rangeFadeEnabled = false, hideOfflineEnabled = false },
})
assert(protectedFrame.unitEvents.UNIT_CONNECTION == nil and protectedFrame.alpha == 1,
    "disabling offline visibility must remove its unit event and restore full opacity")

for _, frame in ipairs({ alwaysHiddenFrame, delayedFrame, reconnectFrame }) do
    UF.ApplySpec(frame, {
        unit = frame.unit,
        key = "party",
        scope = "group",
        enabled = true,
        group = { rangeFadeEnabled = false, hideOfflineEnabled = false },
    })
end
assert(settleDriver.events.PLAYER_REGEN_DISABLED == nil,
    "the central combat-transition subscription must disappear with its last consumer")

print("group offline visibility smoke: ok")
