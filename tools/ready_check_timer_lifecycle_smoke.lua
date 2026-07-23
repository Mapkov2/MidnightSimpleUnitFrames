_G = _G or _ENV

local now = 100
local readyState
local timers = {}

_G.GetTime = function() return now end
_G.GetReadyCheckStatus = function() return readyState end
_G.issecretvalue = function() return false end
_G.C_Timer = {
  After = function(delay, callback)
    local timer = { delay = delay, callback = callback }
    timers[#timers + 1] = timer
  end,
}

local elements = {}
local UF = {
  Layers = {},
  RegisterElement = function(name, element) elements[name] = element end,
  UnitExistsSafe = function() return true end,
  FreshUnitState = function() return nil end,
}
local MSUF = {
  UF = UF,
  Apply = {},
  Secrets = {},
}
_G.MSUF_NS = MSUF

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
  "MidnightSimpleUnitFrames", MSUF)

local runtime = assert(MSUF.UFStatusRuntime, "status runtime missing")
local status = { readyCheck = { enabled = true } }

local function NewFrame(unit)
  local icon = { shown = true, writes = 0, _msufStatusShown = true, _aShown = true }
  function icon:IsShown() return self.shown end
  function icon:SetShown(shown)
    self.shown = shown == true
    self.writes = self.writes + 1
  end
  return { MSUFUnitKey = unit, readyCheckIcon = icon }
end

-- Removing a pending result leaves the one compact shared wake as a no-op.
local first = NewFrame("party1")
runtime.UpdateReadyCheck(first, status, "READY_CHECK_FINISHED")
assert(#timers == 1 and timers[1].delay == 6,
  "ready-check result did not arm one six-second timer")
runtime.CancelReadyCheckTimer(first)
timers[1].callback()
assert(first.readyCheckIcon.writes == 0,
  "cancelled ready-check result was still retained by the timer queue")

-- Multiple frames share one wake. Cancelling one must preserve the other; the
-- due callback hides exactly the remaining result.
local second = NewFrame("party2")
local third = NewFrame("party3")
runtime.UpdateReadyCheck(second, status, "READY_CHECK_FINISHED")
runtime.UpdateReadyCheck(third, status, "READY_CHECK_FINISHED")
assert(#timers == 2, "two ready-check results did not share one timer")
runtime.CancelReadyCheckTimer(second)
now = 106
timers[2].callback()
assert(second.readyCheckIcon.writes == 0 and third.readyCheckIcon.writes == 1
    and third.readyCheckIcon.shown == false,
  "shared ready-check timer did not hide exactly the remaining due frame")

-- Cancelling every member leaves one bounded no-op wake, not per-frame timers.
now = 200
local fourth = NewFrame("raid1")
local fifth = NewFrame("raid2")
runtime.UpdateReadyCheck(fourth, status, "READY_CHECK_FINISHED")
runtime.UpdateReadyCheck(fifth, status, "READY_CHECK_FINISHED")
assert(#timers == 3, "new ready-check batch did not arm one shared timer")
runtime.CancelReadyCheckTimer(fourth)
runtime.CancelReadyCheckTimer(fifth)
now = 206
timers[3].callback()
assert(fourth.readyCheckIcon.writes == 0 and fifth.readyCheckIcon.writes == 0,
  "cancelled shared ready-check batch retained a frame")

print("ready_check_timer_lifecycle_smoke: ok")
