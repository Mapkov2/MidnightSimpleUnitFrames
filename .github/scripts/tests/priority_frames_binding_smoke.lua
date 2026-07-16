-- Priority Frames managed binding: one-time adoption, explicit conflicts,
-- combat safety, persistence, and rollback on partial Blizzard API failure.
local root = arg and arg[1] or "."

local eventFrame
local combat = false
local savedSets = {}
local bindingByKey = {
  ["CTRL-O"] = "MSUF_TOGGLE_OPTIONS",
  ["ALT-P"] = "MSUF_PRIORITY_TOGGLE",
  ["CTRL-X"] = "SOME_OTHER_ACTION",
}
local failSet = {}

_G.GetTime = function() return 0 end
_G.InCombatLockdown = function() return combat end
_G.GetCurrentBindingSet = function() return 2 end
_G.SaveBindings = function(set) savedSets[#savedSets + 1] = set end
_G.GetBindingAction = function(key) return bindingByKey[key] or "" end
_G.GetBindingKey = function(command)
  local keys = {}
  for key, action in pairs(bindingByKey) do
    if action == command then keys[#keys + 1] = key end
  end
  table.sort(keys)
  return unpack(keys)
end
_G.SetBinding = function(key, command)
  if failSet[key] then return false end
  bindingByKey[key] = command
  return true
end
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:SetScript(kind, callback) if kind == "OnEvent" then self.onEvent = callback end end
  eventFrame = frame
  return frame
end

_G.MSUF_GlobalDB = {
  global = {
    bindings = {
      commands = {
        MSUF_TOGGLE_OPTIONS = { "CTRL-O" },
        MSUF_TOGGLE_EDITMODE = {},
        -- Intentionally missing: simulates upgrading from before Priority Frames.
      },
    },
  },
}

local MSUF = {}
function MSUF.ExportPublic(name, value) _G[name] = value; return value end
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(eventFrame and eventFrame.events.PLAYER_LOGIN and eventFrame.events.UPDATE_BINDINGS,
  "managed binding event owner was not installed")

eventFrame.onEvent(eventFrame, "PLAYER_LOGIN")
local stored = _G.MSUF_GlobalDB.global.bindings.commands
assert(stored.MSUF_PRIORITY_TOGGLE[1] == "ALT-P",
  "upgrade login erased the user's pre-existing Blizzard Priority binding")

local ok, code, action = _G.MSUF_SetManagedBinding("MSUF_PRIORITY_TOGGLE", "CTRL-X", false)
assert(not ok and code == "CONFLICT" and action == "SOME_OTHER_ACTION"
  and bindingByKey["CTRL-X"] == "SOME_OTHER_ACTION",
  "unconfirmed conflict replaced another action")

ok = _G.MSUF_SetManagedBinding("MSUF_PRIORITY_TOGGLE", "CTRL-X", true)
assert(ok and bindingByKey["CTRL-X"] == "MSUF_PRIORITY_TOGGLE" and bindingByKey["ALT-P"] == nil,
  "confirmed replacement did not atomically move the Priority binding")
assert(#stored.MSUF_PRIORITY_TOGGLE == 1 and stored.MSUF_PRIORITY_TOGGLE[1] == "CTRL-X"
  and savedSets[#savedSets] == 2, "successful binding change was not persisted")

combat = true
ok, code = _G.MSUF_ClearManagedBinding("MSUF_PRIORITY_TOGGLE")
assert(not ok and code == "COMBAT" and bindingByKey["CTRL-X"] == "MSUF_PRIORITY_TOGGLE",
  "combat binding mutation was not rejected")
combat = false

-- Recreate an old/new conflict and force the old-key clear to fail after the
-- new key was assigned. The operation must restore both actions and storage.
bindingByKey["ALT-P"] = "MSUF_PRIORITY_TOGGLE"
bindingByKey["CTRL-X"] = "SOME_OTHER_ACTION"
stored.MSUF_PRIORITY_TOGGLE = { "ALT-P" }
failSet["ALT-P"] = true
ok, code = _G.MSUF_SetManagedBinding("MSUF_PRIORITY_TOGGLE", "CTRL-X", true)
assert(not ok and code == "CLEAR_FAILED" and bindingByKey["ALT-P"] == "MSUF_PRIORITY_TOGGLE"
  and bindingByKey["CTRL-X"] == "SOME_OTHER_ACTION"
  and stored.MSUF_PRIORITY_TOGGLE[1] == "ALT-P",
  "partial binding failure was not rolled back")
failSet["ALT-P"] = nil

ok = _G.MSUF_ClearManagedBinding("MSUF_PRIORITY_TOGGLE")
assert(ok and bindingByKey["ALT-P"] == nil and #stored.MSUF_PRIORITY_TOGGLE == 0,
  "binding clear did not update Blizzard state and the global mirror")

bindingByKey["BUTTON4"] = "MSUF_PRIORITY_TOGGLE"
eventFrame.onEvent(eventFrame, "UPDATE_BINDINGS")
assert(stored.MSUF_PRIORITY_TOGGLE[1] == "BUTTON4",
  "external Blizzard binding change did not synchronize into the global mirror")

print("PASS priority frames binding: migration, conflict, combat, persistence, and rollback")
