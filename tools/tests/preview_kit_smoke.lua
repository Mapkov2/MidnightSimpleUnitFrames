-- preview_kit_smoke.lua <repoRoot>
--
-- The preview kit (UnitFrames/Engine/MSUF_UF_PreviewKit.lua) on its own: a host lifecycle and frame pools with no
-- addon, unit-frame or client dependency. Pins that
--   * a host builds once, paints on Activate, and owns no timer, signal or script while closed;
--   * Request coalesces a burst into one repaint on the next frame, ignores a closed host and defers through
--     an `allowed` gate; a repaint queued before Deactivate never runs after it;
--   * Acquire / Release / ReleaseAll pool objects per kind, and Deactivate returns everything it handed out.
-- Plain Lua 5.1, no sandbox.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local function Check(condition, message)
    if not condition then error("preview_kit_smoke: " .. message, 2) end
end

local MSUF = {}
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_PreviewKit.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local Kit = assert(MSUF.UF and MSUF.UF.PreviewKit, "the kit did not publish MSUF.UF.PreviewKit")
Check(type(Kit.NewHost) == "function", "the kit lacks NewHost")

-- A fake timer queue the tests drive by hand.
local queue, scheduled = {}, 0
local function After(delay, fn)
    scheduled = scheduled + 1
    queue[#queue + 1] = { delay = delay, fn = fn }
end
-- Run the timers queued right now.
local function Run()
    local batch = queue
    queue = {}
    for _, entry in ipairs(batch) do entry.fn() end
    return #batch
end

local function NewTrackedHost(extra)
    local log = { built = 0, activated = 0, deactivated = 0, painted = {}, created = 0, allowed = true }
    local opts = {
        after = After,
        build = function() log.built = log.built + 1 end,
        activate = function() log.activated = log.activated + 1 end,
        deactivate = function() log.deactivated = log.deactivated + 1 end,
        paint = function(_, reason) log.painted[#log.painted + 1] = reason end,
        allowed = function() return log.allowed end,
        create = function(kind) log.created = log.created + 1 return { kind = kind, shown = true, Hide = function(self) self.shown = false end } end,
    }
    for key, value in pairs(extra or {}) do opts[key] = value end
    return Kit.NewHost({}, opts), log
end

---------------------------------------------------------------------------
-- 1. Lifecycle: build once, paint on activate, nothing while closed.
---------------------------------------------------------------------------
local host, log = NewTrackedHost()
Check(scheduled == 0, "a new host scheduled a timer")
Check(host:Request("early") == false and scheduled == 0, "a closed host queued a repaint")
Check(host:Refresh("early") == false and #log.painted == 0, "a closed host painted")
Check(host:Activate() == true and host:IsActive(), "activate failed")
Check(host:Activate() == false and log.activated == 1, "a second activate ran the hook again")
Check(log.built == 1 and #log.painted == 1 and log.painted[1] == "activate", "activate built or painted wrongly")
Check(scheduled == 0, "an active host holds a timer with nothing to repaint, has " .. scheduled)
Check(host:Deactivate() == true and not host:IsActive() and log.deactivated == 1, "deactivate failed")
Check(host:Deactivate() == false and log.deactivated == 1, "a second deactivate ran the hook again")
-- Open again: the build does not repeat.
host:Activate()
Check(log.built == 1 and log.activated == 2 and #log.painted == 2, "re-activate rebuilt or skipped the paint")

---------------------------------------------------------------------------
-- 2. Request: one repaint per burst, on the next frame, with the last reason.
---------------------------------------------------------------------------
host, log = NewTrackedHost()
host:Activate()
local before = scheduled
for _, reason in ipairs({ "a", "b", "c", "d", "e" }) do Check(host:Request(reason) == true, "request refused") end
Check(scheduled == before + 1, "five requests scheduled " .. (scheduled - before) .. " timers")
Check(queue[#queue].delay == 0, "a request is not due on the next frame")
local runner = queue[#queue].fn
Check(#log.painted == 1, "a request painted before its frame")
Run()
Check(#log.painted == 2 and log.painted[2] == "e", "the burst did not paint once with the last reason")
host:Request("again")
Check(queue[#queue].fn == runner, "a request allocated a new closure")
Run()
Check(#log.painted == 3, "a second burst did not paint")
-- A repaint queued before Deactivate never runs after it.
host:Request("late")
host:Deactivate()
Run()
Check(#log.painted == 3, "a repaint queued before deactivate ran after it")
host:Activate()
Check(#log.painted == 4 and log.painted[4] == "activate", "re-activate did not paint")
-- The allowed gate defers a repaint (combat); the next request after it opens paints.
log.allowed = false
host:Request("blocked")
Run()
Check(#log.painted == 4, "the allowed gate did not defer the repaint")
log.allowed = true
Check(host:Refresh("now") == true and #log.painted == 5, "refresh did not paint once allowed")
host:Request("open")
Run()
Check(#log.painted == 6 and log.painted[6] == "open", "a request after the gate opened did not paint")

---------------------------------------------------------------------------
-- 3. Pools.
---------------------------------------------------------------------------
host, log = NewTrackedHost()
host:Activate()
local a, b = host:Acquire("icon"), host:Acquire("icon")
local c = host:Acquire("bar")
Check(a ~= b and log.created == 3, "acquire did not create distinct objects")
Check(host:Release("icon", a) == true and a.shown == false, "release did not reset the object (default: Hide)")
Check(host:Release("icon", a) == false and host:Release("icon", {}) == false and host:Release("none", a) == false, "release accepted a foreign or repeated object")
Check(host:Acquire("icon") == a and log.created == 3, "a released object was not reused")
host:ReleaseAll("icon")
Check(a.shown == false and b.shown == false and c.shown == true, "release-all missed an object or touched another kind")
Check(host:Acquire("icon") ~= nil and log.created == 3, "release-all did not return objects to the pool")
host:Deactivate()
Check(c.shown == false, "deactivate kept an acquired object")
host:Activate()
Check(host:Acquire("bar") == c and log.created == 3, "deactivate did not pool what it released")
local reset = {}
local custom = Kit.NewHost({}, { after = After, paint = function() end,
    create = function() return {} end, reset = function(kind, object) reset[#reset + 1] = kind object.reset = true end })
custom:Activate()
local object = custom:Acquire("k")
custom:ReleaseAll("k")
Check(object.reset == true and reset[1] == "k", "a custom reset was not used")

print("preview_kit_smoke: PASS")
