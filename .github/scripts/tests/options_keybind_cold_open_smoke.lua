-- Contract: the first options keybind demand splits synchronous LoadOnDemand
-- loading from window construction by one frame. Warm opens and hides remain
-- immediate, and repeated key presses cannot queue duplicate cold opens.
local root = arg and arg[1] or "."

local eventFrame
_G.GetTime = function() return 0 end
_G.InCombatLockdown = function() return false end
_G.GetCurrentBindingSet = function() return 2 end
_G.SaveBindings = function() end
_G.GetBindingAction = function() return "" end
_G.GetBindingKey = function() return nil end
_G.SetBinding = function() return true end
_G.CreateFrame = function()
  local frame = {}
  function frame:RegisterEvent() end
  function frame:SetScript(kind, callback)
    if kind == "OnEvent" then self.onEvent = callback end
  end
  eventFrame = frame
  return frame
end

local queued
local timerCalls = 0
_G.C_Timer = {
  After = function(delay, callback)
    assert(delay == 0, "cold keybind open did not use a next-frame delay")
    assert(not queued, "cold keybind open queued more than one callback")
    timerCalls = timerCalls + 1
    queued = callback
  end,
}

local MSUF = {}
function MSUF.ExportPublic(name, value)
  _G[name] = value
  return value
end
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
assert(eventFrame, "utility binding owner did not load")

local ready = false
local ensureCalls = 0
local openCalls = 0
local hideCalls = 0
local function OpenOptions()
  openCalls = openCalls + 1
end
local function ColdOpenStub()
  error("cold keybind dispatched through the synchronous options facade")
end

_G.MSUF_StandaloneOptionsWindow = nil
_G.MSUF_OpenStandaloneOptionsWindow = ColdOpenStub
_G.MSUF_IsOptionsLoaded = function() return ready end
_G.MSUF_EnsureOptionsLoaded = function(reason)
  assert(reason == "MSUF_OpenStandaloneOptionsWindow", "unexpected options demand reason")
  ensureCalls = ensureCalls + 1
  ready = true
  _G.MSUF_OpenStandaloneOptionsWindow = OpenOptions
  return true
end

_G.MSUF_Keybind_ToggleOptions()
assert(ensureCalls == 1 and timerCalls == 1 and openCalls == 0 and type(queued) == "function",
  "cold keybind did not split loading from window construction")
_G.MSUF_Keybind_ToggleOptions()
assert(ensureCalls == 1 and timerCalls == 1 and openCalls == 0,
  "pending cold keybind queued or opened twice")
local callback = queued
queued = nil
callback()
assert(openCalls == 1, "next-frame cold keybind did not open the options window")

_G.MSUF_Keybind_ToggleOptions()
assert(openCalls == 2 and timerCalls == 1,
  "warm keybind open was not immediate")

_G.MSUF_StandaloneOptionsWindow = {
  IsShown = function() return true end,
}
_G.MSUF_HideStandaloneOptionsWindow = function()
  hideCalls = hideCalls + 1
end
_G.MSUF_Keybind_ToggleOptions()
assert(hideCalls == 1 and openCalls == 2 and timerCalls == 1,
  "shown-window keybind no longer hides immediately")

_G.MSUF_StandaloneOptionsWindow = nil
_G.MSUF_OpenStandaloneOptionsWindow = ColdOpenStub
ready = false
_G.MSUF_EnsureOptionsLoaded = function()
  ensureCalls = ensureCalls + 1
  return false
end
_G.MSUF_Keybind_ToggleOptions()
assert(openCalls == 2 and timerCalls == 1 and queued == nil,
  "failed cold load still queued or opened the options window")

print("PASS options keybind cold open: deferred first build, warm open, hide, and failure")
