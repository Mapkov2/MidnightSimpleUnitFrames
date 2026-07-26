-- Contract: every primary Edit Mode activation loads Options after combat
-- validation and before State.Enter; exits remain cold and load-free.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local calls = {}
local combat, ensureResult = false, true
local main = {
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
  UF = {},
}
local state = {
  Enter = function(unitKey)
    calls[#calls + 1] = "enter:" .. tostring(unitKey)
  end,
  Exit = function(reason)
    calls[#calls + 1] = "exit:" .. tostring(reason)
  end,
  IsActive = function() return false end,
}
local registered = {}
_G.MSUF_NS = main
_G.MSUF = main
_G.MSUF_EM2 = {
  Registry = {
    Register = function(spec)
      registered[#registered + 1] = spec.key
    end,
  },
  State = state,
  Util = {
    Round = function(value) return value end,
    ApplySettingsForKeySafe = function() end,
    ApplyAllSettingsSafe = function() end,
    Tr = function(text) return text end,
    ThemeColor = function(_, fallback) return fallback end,
    SharedUI = function() return nil end,
    IsConfigCombatLocked = function() return combat end,
    BlockConfigCombatLocked = function() return combat end,
  },
}
_G.MSUF_Edit = nil
_G.MSUF_EditState = nil
_G.MSUF_BlockConfigCombatLocked = nil
_G.InCombatLockdown = function() return combat end
_G.MSUF_ShowConfigCombatLockMessage = function()
  calls[#calls + 1] = "combat-lock"
end
_G.MSUF_EnsureOptionsLoaded = function(reason)
  calls[#calls + 1] = "ensure:" .. tostring(reason)
  return ensureResult
end

local moversPath = root
  .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua"
assert(loadfile(moversPath))("MidnightSimpleUnitFrames", main)
Check(type(_G.MSUF_SetMSUFEditModeDirect) == "function",
  "primary Edit Mode entry point was not exported")
Check(type(_G.MSUF_SetMSUFEditModeFromBlizzard) == "function",
  "Blizzard Edit Mode bridge was not exported")
Equal(#registered, 11, "Edit Mode mover registration count")

calls = {}
Equal(_G.MSUF_SetMSUFEditModeDirect(true, "target"), true,
  "successful Edit Mode activation")
Equal(#calls, 2, "successful activation call count")
Equal(calls[1], "ensure:edit-mode", "Options load must precede State.Enter")
Equal(calls[2], "enter:target", "State.Enter activation")

calls = {}
Equal(_G.MSUF_SetMSUFEditModeDirect(false, "target"), true,
  "Edit Mode exit result")
Equal(#calls, 1, "Edit Mode exit call count")
Equal(calls[1], "exit:direct", "Edit Mode exit must stay load-free")

calls = {}
ensureResult = false
Equal(_G.MSUF_SetMSUFEditModeDirect(true, "player"), false,
  "failed Options load activation result")
Equal(#calls, 1, "failed Options load must not enter Edit Mode")
Equal(calls[1], "ensure:edit-mode", "failed activation load reason")

calls = {}
ensureResult = true
combat = true
Equal(_G.MSUF_SetMSUFEditModeDirect(true, "focus"), false,
  "combat-blocked activation result")
Equal(#calls, 1, "combat activation must stop before Options demand")
Equal(calls[1], "combat-lock", "combat activation feedback")

calls = {}
combat = false
_G.MSUF_SetMSUFEditModeFromBlizzard(true)
Equal(calls[1], "ensure:edit-mode", "Blizzard bridge bypassed Options demand")
Equal(calls[2], "enter:nil", "Blizzard bridge did not enter through primary path")

local source = (function()
  local file = assert(io.open(moversPath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end)()
local ensureAt = assert(source:find('MSUF_EnsureOptionsLoaded("edit-mode")', 1, true))
local enterAt = assert(source:find("if active then EM2.State.Enter(unitKey)", ensureAt, true))
Check(ensureAt < enterAt, "source order no longer guarantees load before enter")

print("PASS: Edit Mode demand-load ordering, failure, exit, and combat contract")
