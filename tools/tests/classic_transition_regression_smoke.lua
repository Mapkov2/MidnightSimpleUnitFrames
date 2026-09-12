-- Exercise the production cancellation/deadline and group-world event routes.
local root = assert(arg[1], "repository root required")
local function Read(path)
    local f = assert(io.open(root .. "/" .. path, "rb"))
    local text = f:read("*a"); f:close(); return text
end
local function Between(source, first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a + #first, true), last)
    return source:sub(a, b - 1)
end
local source = Read("MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua")
local now, scheduled, hidden, cancelled = 0, {}, 0, 0
local env = setmetatable({
    GetTime = function() return now end,
    CancelScheduled = function(cb) scheduled[cb] = nil; cancelled = cancelled + 1 end,
    ScheduleDelayed = function(cb, delay) scheduled[cb] = now + delay end,
    HidePlayerFrameIfNoLongerCasting = function() hidden = hidden + 1 end,
    MarkPlayerStateInactive = function() end,
    ClearPendingPlayerInterrupt = function() end,
    EnsureDBLazy = function() end,
    DisableFrameOnUpdate = function() end,
    ReleaseRuntimeActive = function() end,
}, { __index = _G })
env._G = setmetatable({
    GetTime = function() return now end,
    MSUF_DB = { player = {} },
    MSUF_ApplyInterruptBarVisuals = function() end,
}, { __index = _G })
local chunk = assert(loadstring(
    Between(source, "local function InvalidatePlayerInterruptHide", "local function ApplyActiveCast")
    .. Between(source, "local function EnsureInterruptHideCallback", "local function DisablePlayerCastbar")
    .. "\nreturn InvalidatePlayerInterruptHide, ShowInterruptFeedback"))
setfenv(chunk, env)
local cancel, interrupt = chunk()
local frame = { statusBar = {} }
interrupt(frame)
local callback = assert(frame._msufPlayerInterruptHideCB)
assert(scheduled[callback] == 0.5)
-- Start another cast before feedback expires: cancel removes the queued work.
now = 0.1; cancel(frame)
assert(cancelled == 1 and scheduled[callback] == nil)
assert(frame._msufPlayerInterruptHidePending == nil, "cancelled hide stayed pending")
-- Its interruption must schedule a fresh deadline using the same callback.
now = 0.2; interrupt(frame)
assert(scheduled[callback] == 0.7, "second interrupt cannot expire")
now = 0.3; interrupt(frame)
assert(scheduled[callback] == 0.7, "duplicate interrupt replaced queued work")
now = 0.7; scheduled[callback] = nil; callback()
assert(hidden == 0 and scheduled[callback] == 0.8, "extended feedback deadline ignored")
now = 0.8; scheduled[callback] = nil; callback()
assert(hidden == 1 and frame._msufPlayerInterruptHidePending == nil)

source = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
local driver = { events = {} }
function driver:SetScript(_, fn) self.handler = fn end
function driver:RegisterEvent(event) self.events[event] = true end
local visible = { { shown = true, health = 0 }, { shown = true, health = 0 }, { shown = false, health = 0 } }
local snapshots = 0
env = setmetatable({
    CreateFrame = function() return driver end,
    IsUnitToken = function(unit) return type(unit) == "string" end,
    MSUF = {},
    BroadcastGroupLifecycle = function(event, mode)
        assert(event == "PLAYER_ENTERING_WORLD" and mode == "full")
        for _, f in ipairs(visible) do
            if f.shown then f.health = 100; snapshots = snapshots + 1 end
        end
    end,
}, { __index = _G })
chunk = assert(loadstring("local groupLifecycleDriver\n"
    .. Between(source, "local function EnsureGroupLifecycleDriver", "SyncGroupLifecycleDriver = function")
    .. "\nreturn EnsureGroupLifecycleDriver"))
setfenv(chunk, env)
chunk()()
assert(driver.events.PLAYER_ENTERING_WORLD, "group world recovery is not registered")
-- Entering-world payload booleans must take the full snapshot path, not a unit route.
driver.handler(driver, "PLAYER_ENTERING_WORLD", false, false)
assert(snapshots == 2 and visible[1].health == 100 and visible[2].health == 100)
assert(visible[3].health == 0, "hidden group child was touched")
print("Classic transition regressions passed: interrupted recast and summon/world recovery")
