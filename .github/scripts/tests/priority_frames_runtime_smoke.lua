-- Priority runtime uses the existing group event owner, merges combat-deferred
-- selection with pending visual work, and registers UNIT_NAME_UPDATE only while
-- the feature can be active in a party or raid.
local root = arg and arg[1] or "."
local combat, inRaid = false, true
local inGroup = true
local runtimeFrame
local setups, retires = 0, 0
local priorityEnabled = true
local partyBaseEnabled, raidBaseEnabled = true, true
local timerQueue = {}
local setupKinds = {}

_G.InCombatLockdown = function() return combat end
_G.IsInGroup = function() return inGroup end
_G.IsInRaid = function() return inRaid end
_G.GetNumGroupMembers = function() return 20 end
_G.issecretvalue = function() return false end
_G.C_Timer = { After = function(_, callback) timerQueue[#timerQueue + 1] = callback end }
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:UnregisterAllEvents() self.events = {} end
  function frame:SetScript(kind, callback) if kind == "OnEvent" then self.onEvent = callback end end
  runtimeFrame = frame
  return frame
end

local GF = { Metadata = {}, headers = {}, frames = {}, frameList = {} }
function GF.EnsureDB() end
function GF.GetConf(kind)
  local enabled = raidBaseEnabled
  if kind == "party" then enabled = partyBaseEnabled end
  return { enabled = enabled, showSolo = true }
end
function GF.AnyMSUFGroupFrameEnabled() return true end
function GF.GetLiveRaidKind() return "raid" end
function GF.SetupHeader() return { Show = function() end }, true end
function GF.RetireHeader(key) if key == "priority" then retires = retires + 1 end; GF.headers[key] = nil; return true end
function GF.PriorityFramesConfigured() return priorityEnabled end
function GF.ResolvePrioritySelection() return "TankA-Realm", 1 end
function GF.SetupPriorityHeader(kind)
  setups = setups + 1
  setupKinds[#setupKinds + 1] = kind
  local header = { Show = function() end, _msufGFKind = kind }
  GF.headers.priority = header
  return header, true
end
function GF.ForEachFrame() return false end

local MSUF = {
  GF = GF,
  UF = {},
  ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
assert(runtimeFrame and type(runtimeFrame.onEvent) == "function")
local priorityObserverCalls, lastPriorityObserverKind = 0
GF.RegisterRuntimeObserver("priority-transition-test", function(operation, kind)
  if operation == "refreshPriority" then
    priorityObserverCalls = priorityObserverCalls + 1
    lastPriorityObserverKind = kind
  end
end)

local function Fire(event, unit) runtimeFrame.onEvent(runtimeFrame, event, unit) end
local function FlushTimers()
  while #timerQueue > 0 do
    local callback = table.remove(timerQueue, 1)
    callback()
  end
end
Fire("PLAYER_LOGIN")
assert(setups == 1 and runtimeFrame.events.UNIT_NAME_UPDATE,
  "login did not activate priority header and conditional name event")
assert(setupKinds[#setupKinds] == "raid", "raid login built Priority Frames with the wrong base kind")

combat = true
Fire("PLAYER_REGEN_DISABLED")
GF.DeferGroupRuntime("refresh", "raid", 8)
GF.RefreshPriorityFrames("hotkey")
assert(GF._pendingGroupRuntimeReason == "priority" and GF._pendingGroupRuntimeMask == 8,
  "priority selection did not merge with pending visual work")
assert(setups == 1, "combat selection mutated the protected header")
assert(priorityObserverCalls == 0, "combat-deferred Priority mutation notified observers before the header changed")

combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(setups == 2 and GF._pendingGroupRuntime == nil,
  "regen did not flush deferred priority selection exactly once")
assert(priorityObserverCalls == 1 and lastPriorityObserverKind == "raid",
  "committed Priority header mutation did not notify runtime owners exactly once")

combat = true
GF.DeferGroupRuntime("layout", "party")
GF.RefreshPriorityFrames("party-layout-overlap")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(setups == 3 and GF._pendingPriorityRefresh == nil,
  "party-scoped layout swallowed the orthogonal priority update")

combat = true
GF.DeferGroupRuntime("rebuild", "party")
GF.RefreshPriorityFrames("party-rebuild-overlap")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(setups == 4 and GF._pendingPriorityRefresh == nil,
  "party-scoped rebuild swallowed the orthogonal priority update")

Fire("UNIT_NAME_UPDATE", "raid7")
Fire("UNIT_NAME_UPDATE", "raid8")
assert(setups == 4 and #timerQueue == 1,
  "raid name-update burst was not coalesced before rebuilding Priority Frames")
FlushTimers()
assert(setups == 5, "coalesced raid name update did not refresh active priority selection")
Fire("UNIT_NAME_UPDATE", "party1")
assert(setups == 5, "non-raid name update touched priority selection")

priorityEnabled = false
GF.RefreshPriorityFrames("disabled")
assert(retires > 0 and runtimeFrame.events.UNIT_NAME_UPDATE == nil,
  "disabled priority runtime retained header or conditional name event")

inRaid = false
priorityEnabled = true
GF.RefreshPriorityFrames("entered-party")
assert(setups == 6 and setupKinds[#setupKinds] == "party" and runtimeFrame.events.UNIT_NAME_UPDATE,
  "Party transition did not rebuild Priority Frames with Party style/events")
assert(lastPriorityObserverKind == "party", "Party Priority transition notified observers with a stale Raid kind")

partyBaseEnabled = false
GF.RefreshPriorityFrames("party-base-disabled")
assert(setups == 6 and runtimeFrame.events.UNIT_NAME_UPDATE == nil and GF.headers.priority == nil,
  "disabled Party base retained Priority header or conditional name events: setups=" .. tostring(setups)
    .. " nameEvent=" .. tostring(runtimeFrame.events.UNIT_NAME_UPDATE)
    .. " header=" .. tostring(GF.headers.priority))
partyBaseEnabled = true
GF.RefreshPriorityFrames("party-base-enabled")
assert(setups == 7 and setupKinds[#setupKinds] == "party" and runtimeFrame.events.UNIT_NAME_UPDATE,
  "re-enabled Party base did not restore Priority Frames")

local beforePartyLayout = setups
GF.RefreshHeaderLayout("party")
assert(setups == beforePartyLayout + 1 and setupKinds[#setupKinds] == "party",
  "party-scoped layout refresh skipped the inherited Priority header")

local beforePartyNames = setups
Fire("UNIT_NAME_UPDATE", "player")
Fire("UNIT_NAME_UPDATE", "party1")
Fire("UNIT_NAME_UPDATE", "raid7")
assert(setups == beforePartyNames and #timerQueue == 1,
  "Party name-update burst was not coalesced or accepted a stale raid token")
FlushTimers()
assert(setups == beforePartyNames + 1 and setupKinds[#setupKinds] == "party",
  "coalesced Party name update did not rebuild Party Priority Frames")

inGroup = false
GF.RefreshPriorityFrames("left-group")
assert(runtimeFrame.events.UNIT_NAME_UPDATE == nil,
  "priority name event remained registered while solo")

print("PASS priority frames runtime: Party/Raid shared events, combat merge, and conditional teardown")
