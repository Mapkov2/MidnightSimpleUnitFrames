-- Contract: the historical Menu2 Support scale suffix was moved byte-for-byte
-- (after newline normalization) into the always-loaded core runtime.
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

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"), relativePath)
  local text = file:read("*a")
  file:close()
  return text:gsub("\r\n", "\n")
end

local function Count(text, needle)
  local count, from = 0, 1
  while true do
    local at = text:find(needle, from, true)
    if not at then return count end
    count = count + 1
    from = at + #needle
  end
end

local function StableHash(text)
  local hash, modulus = 0, 2147483647
  for index = 1, #text do
    hash = (hash * 131 + text:byte(index)) % modulus
  end
  return hash
end

local runtime = Read("MidnightSimpleUnitFrames/Runtime/MSUF_UIScaleRuntime.lua")
local support = Read(
  "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua")
local suffix = runtime:match("(local pendingMsufScale.*)")
Check(type(suffix) == "string", "extracted scale suffix start is missing")

-- These constants certify the exact 487-line suffix that previously started
-- at `local pendingMsufScale` in Menu2 Support.
Equal(#suffix, 20008, "newline-normalized scale suffix byte count")
Equal(StableHash(suffix), 21561430, "scale suffix extraction fingerprint")
Equal(Count(runtime, 'ExportPublic("MSUF_ApplyMsufScale"'), 1,
  "core scale export ownership")
Equal(Count(runtime, 'Runtime._quiesceScale = function'), 1,
  "core scale quiescence ownership")
Equal(Count(runtime, 'startupScaleEvents:RegisterEvent("PLAYER_LOGIN")'), 1,
  "core startup scale event ownership")
Equal(Count(runtime, 'scaleEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")'), 1,
  "core display scale event ownership")

Check(not support:find("local pendingMsufScale", 1, true),
  "Options Support still duplicates the scale suffix")
Check(not support:find('ExportPublic("MSUF_ApplyMsufScale"', 1, true),
  "Options Support still owns the scale export")
Check(not support:find('startupScaleEvents:RegisterEvent("PLAYER_LOGIN")', 1, true),
  "Options Support still owns the startup scale event")

local toc = Read("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc")
Check(toc:find("Runtime\\MSUF_UIScaleRuntime.lua", 1, true),
  "always-loaded scale runtime is absent from the core TOC")

local warning = Read("MidnightSimpleUnitFrames/Runtime/MSUF_PreviewBuildWarning.lua")
for _, line in ipairs({
  "|cffffd700MSUF 6.0 Beta|r \194\183 Built for WoW 12.1 PTR.",
  "|cffffd700Auras|r use Blizzard's native 12.1 system.",
  "|cff40ff40Thanks for testing!|r Report bugs on Discord or GitHub.",
}) do
  Equal(Count(warning, line), 1, "preserved login warning literal")
end

-- Execute the extracted runtime under a small deterministic WoW harness. This
-- certifies that the new always-loaded wrapper still applies the saved scale at
-- startup and preserves the old last-write-wins combat deferral.
local combat = false
local createdFrames, afterQueue, timerQueue = {}, {}, {}
local coreScales, groupScales = {}, {}
local coreFrame = {
  unit = "player",
  SetScale = function(_, value) coreScales[#coreScales + 1] = value end,
}
local groupFrame = {
  unit = "party1",
  _msufGFBuilt = true,
  _msufGFKind = "party",
  SetScale = function(_, value) groupScales[#groupScales + 1] = value end,
}

local function NewEventFrame()
  local frame = { events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:UnregisterAllEvents() self.events = {} end
  function frame:SetScript(kind, callback) self.scripts[kind] = callback end
  function frame:Fire(event)
    local callback = self.scripts.OnEvent
    if callback and self.events[event] then callback(self, event) end
  end
  createdFrames[#createdFrames + 1] = frame
  return frame
end

local main = {
  AddonName = "MidnightSimpleUnitFrames",
  MSUF2 = {},
  UF = {
    ForEachFrame = function(callback)
      callback(coreFrame)
      callback(groupFrame)
    end,
  },
  GF = {
    GetConf = function(kind)
      Check(kind == "party", "unexpected group scale kind")
      return { frameScaleMode = "off" }
    end,
    RefreshHeaderLayout = function() end,
  },
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
}

_G.MSUF_NS = main
_G.MSUF2 = nil
_G.MSUF_DB = { general = { msufUiScale = 1.25 } }
_G.MSUF_EnsureDB = function() end
_G.InCombatLockdown = function() return combat end
_G.CreateFrame = function(kind)
  Equal(kind, "Frame", "scale runtime frame kind")
  return NewEventFrame()
end
_G.C_Timer = {
  After = function(delay, callback)
    afterQueue[#afterQueue + 1] = { delay = delay, callback = callback }
  end,
  NewTimer = function(delay, callback)
    local timer = { delay = delay, callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timerQueue[#timerQueue + 1] = timer
    return timer
  end,
}
_G.MSUF_UpdateAllExternalAnchorProxies = function() end
_G.MSUF_ForceReanchorAllUnitFrames_Once = function() end

local runtimePath = root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_UIScaleRuntime.lua"
assert(loadfile(runtimePath))("MidnightSimpleUnitFrames", main)

Check(_G.MSUF_NS == main and _G.MSUF2 == main.MSUF2,
  "scale wrapper did not retain the canonical core namespace")
Check(type(main.MSUF2.MenuRuntime) == "table",
  "scale wrapper did not publish the shared MenuRuntime table")
Check(type(_G.MSUF_ApplyMsufScale) == "function"
    and type(_G.MSUF_GetSavedMsufScale) == "function",
  "scale wrapper did not publish the historical API")
Equal(_G.MSUF_GetSavedMsufScale(), 1.25, "saved scale wrapper result")
Equal(#createdFrames, 1, "scale runtime startup frame count")

local startupFrame = createdFrames[1]
Check(startupFrame.events.PLAYER_LOGIN
    and startupFrame.events.PLAYER_ENTERING_WORLD,
  "scale runtime startup events")
startupFrame:Fire("PLAYER_LOGIN")
Equal(#afterQueue, 1, "startup scale coalescing queue count")
Check(next(startupFrame.events) == nil and startupFrame.scripts.OnEvent == nil,
  "startup scale frame did not quiesce after its first event")
table.remove(afterQueue, 1).callback()
Equal(#coreScales, 1, "startup saved-scale apply count")
Equal(coreScales[1], 1.25, "startup saved-scale value")
Equal(#groupScales, 0, "disabled group frame was scaled at startup")

-- Flush the deferred reanchor so it cannot mask the later combat scenario.
Equal(#timerQueue, 1, "startup reanchor timer count")
local startupTimer = table.remove(timerQueue, 1)
startupTimer.callback()

combat = true
_G.MSUF_ApplyMsufScale(1.10)
_G.MSUF_ApplyMsufScale(1.40)
Equal(#coreScales, 1, "combat scale mutated a frame immediately")
Equal(#createdFrames, 2, "combat scale changes created more than one watcher")
local combatWatcher = createdFrames[2]
Check(combatWatcher.events.PLAYER_REGEN_ENABLED,
  "combat scale watcher did not register PLAYER_REGEN_ENABLED")

combat = false
combatWatcher:Fire("PLAYER_REGEN_ENABLED")
Equal(#coreScales, 2, "deferred combat scale apply count")
Equal(coreScales[2], 1.40, "combat scale did not preserve the last request")
Check(not combatWatcher.events.PLAYER_REGEN_ENABLED
    and combatWatcher.scripts.OnEvent == nil,
  "combat scale watcher did not quiesce")
Equal(#groupScales, 0, "disabled group frame was scaled after combat")

_G.MSUF_ApplyMsufScale(9)
Equal(coreScales[#coreScales], 1.5, "MSUF scale upper clamp")
Equal(#groupScales, 0, "disabled group frame was scaled by direct apply")

print("PASS: byte-stable scale extraction plus wrapper/startup/combat parity")
