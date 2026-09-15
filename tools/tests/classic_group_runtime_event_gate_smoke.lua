-- Regression: the Retail-mirrored group runtime must not register the
-- Retail-only PVP_MATCH_STATE_CHANGED event on clients that lack it. Classic
-- arena clients (TBC, Mists) reject the registration, which would unwind
-- SetRuntimeEventsEnabled before UNIT_NAME_UPDATE is installed.
-- Run through .github/scripts/auras3_test_driver.lua with the repository root
-- as arg[1] and as the working directory.
_G = _G or _ENV

local root = assert(arg and arg[1], "repository root required")
root = tostring(root):gsub("\\", "/"):gsub("/$", "")

local RUNTIME_PATH = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"
local INITIALIZE_PATH = root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"
local MATCH_EVENT = "PVP_MATCH_STATE_CHANGED"

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function noop() end

_G.InCombatLockdown = function() return false end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 2 end
_G.C_Timer = { After = noop }

local createdFrames = {}
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:SetScript(name, callback)
    if name == "OnEvent" then self.onEvent = callback end
  end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:UnregisterAllEvents() self.events = {} end
  createdFrames[#createdFrames + 1] = frame
  return frame
end

local function NewRuntimeGF(arena)
  local runtimeGF = { headers = {}, _previewActive = {} }
  function runtimeGF.GetConf(kind)
    if kind == "party" then
      return { enabled = true, showSolo = false, playerFirstInRole = true, sortMode = "ROLE" }
    end
    return { enabled = false }
  end
  runtimeGF.EnsureDB = noop
  function runtimeGF.GetLiveGroupKind() return "party" end
  function runtimeGF.GetLiveRaidKind() return "raid" end
  runtimeGF.ApplyBlizzardGroupFrameOwnership = noop
  runtimeGF.ApplyGroupBorder = noop
  function runtimeGF.SetupHeader() return { Show = noop }, true end
  function runtimeGF.ScheduleScan() return false end
  function runtimeGF.RetireHeader() return true end
  function runtimeGF.IsArenaPartyContext() return arena == true end
  return runtimeGF
end

-- Loads a fresh runtime into its own namespace, drives the startup event and a
-- Party layout refresh, and returns the event owner's final registrations.
local function RunCase(label, arena, client, namespace)
  namespace = namespace or {}
  namespace.GF = NewRuntimeGF(arena)
  namespace.UF = { IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end }
  namespace.ExportPublic = noop
  namespace.Client = client

  local before = #createdFrames
  local chunk = assert(loadfile(RUNTIME_PATH))
  chunk("MidnightSimpleUnitFrames", namespace)
  Check(#createdFrames == before + 1, label .. ": group runtime did not create exactly one event owner")
  local eventFrame = createdFrames[#createdFrames]
  Check(type(eventFrame.onEvent) == "function", label .. ": group runtime installed no OnEvent script")
  Check(eventFrame.events.PLAYER_LOGIN == true, label .. ": startup PLAYER_LOGIN was not registered")

  eventFrame.onEvent(eventFrame, "PLAYER_LOGIN")
  namespace.GF.RefreshHeaderLayout("party")
  return eventFrame
end

local function SpyClient(answer)
  local asked = {}
  local client = {}
  function client.SupportsEvent(event)
    asked[event] = (asked[event] or 0) + 1
    return answer(event)
  end
  return client, asked
end

local function CheckBaseEvents(label, eventFrame)
  Check(eventFrame.events.GROUP_ROSTER_UPDATE == true, label .. ": GROUP_ROSTER_UPDATE was not registered")
  Check(eventFrame.events.UNIT_NAME_UPDATE == true,
    label .. ": arena Party nameList lost its UNIT_NAME_UPDATE registration")
end

-- (a) Arena on a client without the event: skip only the match-state event.
do
  local client, asked = SpyClient(function(event) return event ~= MATCH_EVENT end)
  local frame = RunCase("(a) unsupported arena", true, client)
  Check(frame.events[MATCH_EVENT] == nil, "(a) registered " .. MATCH_EVENT .. " on a client that lacks it")
  CheckBaseEvents("(a) unsupported arena", frame)
  Check((asked[MATCH_EVENT] or 0) > 0, "(a) runtime never consulted Client.SupportsEvent")
  -- The regen catch-up path re-runs SetRuntimeEventsEnabled through the same gate.
  frame.onEvent(frame, "PLAYER_REGEN_ENABLED")
  Check(frame.events[MATCH_EVENT] == nil, "(a) PLAYER_REGEN_ENABLED registered " .. MATCH_EVENT)
  CheckBaseEvents("(a) unsupported arena after regen", frame)
end

-- (b) Arena on a client that has the event: Retail behaviour is unchanged.
do
  local client = SpyClient(function() return true end)
  local frame = RunCase("(b) supported arena", true, client)
  Check(frame.events[MATCH_EVENT] == true, "(b) supported arena client lost " .. MATCH_EVENT)
  CheckBaseEvents("(b) supported arena", frame)
end

-- (c) PvE: never subscribe, and never ask the client about the event.
do
  local client, asked = SpyClient(function() return true end)
  local frame = RunCase("(c) no arena", false, client)
  Check(frame.events[MATCH_EVENT] == nil, "(c) PvE subscribed to " .. MATCH_EVENT)
  Check(frame.events.GROUP_ROSTER_UPDATE == true, "(c) GROUP_ROSTER_UPDATE was not registered")
  Check(asked[MATCH_EVENT] == nil, "(c) PvE asked Client.SupportsEvent about " .. MATCH_EVENT)
end

-- (d) Harness without MSUF.Client keeps the Retail registration.
do
  local frame = RunCase("(d) no client table", true, nil)
  Check(frame.events[MATCH_EVENT] == true, "(d) runtime without MSUF.Client dropped " .. MATCH_EVENT)
  CheckBaseEvents("(d) no client table", frame)
end

-- (e) The real shared client bootstrap on a TBC client without C_EventUtils.
do
  _G.WOW_PROJECT_MAINLINE = 1
  _G.WOW_PROJECT_CLASSIC = 2
  _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
  _G.WOW_PROJECT_MISTS_CLASSIC = 19
  _G.WOW_PROJECT_ID = 5
  _G.C_EventUtils = nil
  _G.C_AddOns = {
    GetAddOnMetadata = function(_, key)
      if key == "X-MSUF-Client" then return "TBC" end
      return nil
    end,
  }
  _G.GetBuildInfo = function() return "test", "test", "test", 20506 end

  local namespace = {}
  assert(loadfile(INITIALIZE_PATH))("MidnightSimpleUnitFrames", namespace)
  local client = namespace.Client
  Check(type(client) == "table" and client.IsTBC == true, "(e) shared bootstrap did not detect TBC")
  Check(client.SupportsEvent(MATCH_EVENT) == false, "(e) TBC client reports " .. MATCH_EVENT .. " as supported")

  local frame = RunCase("(e) TBC arena", true, client, namespace)
  Check(frame.events[MATCH_EVENT] == nil, "(e) TBC arena registered " .. MATCH_EVENT)
  CheckBaseEvents("(e) TBC arena", frame)
end

print("classic group runtime event gate smoke passed")
