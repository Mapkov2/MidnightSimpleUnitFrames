-- Regression: joining a party while Menu2 owns the Party preview must invalidate
-- the preview cache, hide the dummy owner, and restore/apply the live header.
_G = _G or _ENV

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function Read(path)
  local handle = assert(io.open(path, "rb"))
  local source = handle:read("*a")
  handle:close()
  return source
end

local inGroup = false
local inRaid = false
local groupCount = 0
local inCombat = false
local timers = {}
local actions = {}

_G.InCombatLockdown = function() return inCombat end
_G.IsInGroup = function() return inGroup end
_G.IsInRaid = function() return inRaid end
_G.GetNumGroupMembers = function() return groupCount end

local function VisibleFrame()
  return { IsShown = function() return true end }
end

local M = {
  activeKey = "gf_layout",
  gfScope = "party",
  frame = VisibleFrame(),
  MenuTimer = {
    After = function(delay, callback)
      timers[#timers + 1] = { delay = delay, callback = callback }
    end,
  },
}

function M.KeySetFromWords(words)
  local out = {}
  for word in tostring(words or ""):gmatch("%S+") do out[word] = true end
  return out
end

local previewGF = {
  _previewActive = {},
  _previewLayoutFrame = {},
}

function previewGF.GetConf(kind)
  if kind == "party" then return { enabled = true, showSolo = false } end
  return { enabled = false }
end

function previewGF.GetLiveRaidKind() return "raid" end

function previewGF.ShowPreview(kind)
  actions[#actions + 1] = { op = "show", kind = kind }
  previewGF._previewActive[kind] = true
  return true
end

function previewGF.HidePreview(kind)
  actions[#actions + 1] = { op = "hide", kind = kind }
  previewGF._previewActive[kind] = nil
  return true
end

function previewGF.SetPreviewAnchor(kind)
  actions[#actions + 1] = { op = "anchor", kind = kind }
  return true
end

function previewGF.UpdateGroupVisibility()
  actions[#actions + 1] = {
    op = "restore",
    previewActive = previewGF._previewActive.party == true,
    inGroup = inGroup,
  }
  return true
end

local previewMSUF = { MSUF2 = M, GF = previewGF }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PagePreviews.lua"))(
  "MidnightSimpleUnitFrames_Options", previewMSUF)

local function DrainOneTimer(expectedDelay)
  local timer = table.remove(timers, 1)
  Check(timer ~= nil, "expected a queued group preview sync")
  Equal(timer.delay, expectedDelay, "group preview sync delay")
  timer.callback()
end

-- Solo Party page: the visual-only preview owns the configured group position.
M.SyncGFPagePreviewForKey("gf_layout", true)
Check(previewGF._previewActive.party == true, "solo Party page did not show its preview")
Equal(actions[#actions].op, "show", "solo Party page did not finish with preview ownership")

-- GROUP_ROSTER_UPDATE follows this same non-forced request path from Window.lua.
-- It stays deferred, then notices the changed roster despite an unchanged page.
local beforeJoinRequest = #actions
inGroup = true
groupCount = 2
M.RequestGFPagePreviewForKey("gf_layout")
Equal(#actions, beforeJoinRequest, "roster request mutated secure ownership synchronously")
DrainOneTimer(0.09)
Check(previewGF._previewActive.party ~= true, "joined Party kept the stale dummy preview active")

local hideIndex
for index = beforeJoinRequest + 1, #actions do
  local action = actions[index]
  if action.op == "hide" and action.kind == "party" then hideIndex = index; break end
end
Check(hideIndex ~= nil, "joined Party never released preview ownership")
local handoff = actions[hideIndex + 1]
Check(handoff and handoff.op == "restore",
  "joined Party did not restore the live header immediately after preview hide")
Check(handoff.previewActive == false and handoff.inGroup == true,
  "live Party header restore ran while preview suppression was still active")

-- A same-roster refresh may schedule, but the cache deduplicates its final work.
local afterJoin = #actions
M.RequestGFPagePreviewForKey("gf_layout")
DrainOneTimer(0.09)
Equal(#actions, afterJoin, "unchanged Party roster bypassed preview cache deduplication")

-- Leaving the group changes the same roster key and hands ownership back to preview.
inGroup = false
groupCount = 0
M.RequestGFPagePreviewForKey("gf_layout")
DrainOneTimer(0.09)
Check(previewGF._previewActive.party == true, "leaving Party did not restore preview ownership")
Equal(actions[#actions].op, "show", "leaving Party did not finish with preview ownership")

-- A roster event may still reach the menu while lockdown is active. Its
-- deferred callback must not touch previews, anchors, or secure headers.
local beforeCombat = #actions
inCombat = true
inGroup = true
groupCount = 2
M.RequestGFPagePreviewForKey("gf_layout")
Equal(#actions, beforeCombat, "combat roster request mutated group ownership synchronously")
DrainOneTimer(0.09)
Equal(#actions, beforeCombat, "combat roster sync made a protected group-frame call")
inCombat = false

-- Header.lua must only report a child scan as handled while the secure header
-- is visible. Runtime then owns Show -> scan for a newly born hidden header.
local headersSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua")
Check(headersSource:find("and header.IsShown and header:IsShown()", 1, true),
  "hidden SecureGroupHeader can consume the pre-OnShow child scan")
Check(headersSource:find("return header, scanHandled", 1, true),
  "SetupHeader no longer reports the actual scan ownership state")

local runtimeEventFrame
local runtimeGF = { headers = {}, _previewActive = {} }
local scanCalls = 0
local appliedChildren = 0

function runtimeGF.GetConf(kind)
  if kind == "party" then return { enabled = true, showSolo = false } end
  return { enabled = false }
end

function runtimeGF.EnsureDB() end
function runtimeGF.GetLiveRaidKind() return "raid" end
function runtimeGF.ApplyBlizzardGroupFrameOwnership() end
function runtimeGF.ApplyGroupBorder() end

function runtimeGF.SetupHeader(key, kind)
  local header = runtimeGF.headers[key]
  if header then
    -- Mirrors the visible hide/show rebind path in Headers.lua: that owner has
    -- already applied the now-existing children and Runtime must not scan twice.
    runtimeGF.ScheduleScan(key, kind)
    return header, true
  end
  header = { shown = false, children = {}, _msufGFKind = kind }
  function header:Show()
    if self.shown then return end
    self.shown = true
    -- Mirrors SecureGroupHeaderTemplate: managed children are born in OnShow.
    self.children[1] = { unit = "player" }
    self.children[2] = { unit = "party1" }
  end
  function header:Hide() self.shown = false end
  runtimeGF.headers[key] = header
  return header, false
end

function runtimeGF.ScheduleScan(key)
  scanCalls = scanCalls + 1
  local header = runtimeGF.headers[key]
  Check(header and header.shown == true, "runtime scanned a hidden SecureGroupHeader")
  for index = 1, #header.children do
    header.children[index].applied = true
    appliedChildren = appliedChildren + 1
  end
  return #header.children > 0
end

function runtimeGF.RetireHeader(key)
  runtimeGF.headers[key] = nil
  return true
end

_G.InCombatLockdown = function() return false end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 2 end
_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:SetScript(_, callback) self.script = callback end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterAllEvents() self.events = {} end
  runtimeEventFrame = frame
  return frame
end

local runtimeMSUF = { GF = runtimeGF, UF = {} }
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))(
  "MidnightSimpleUnitFrames", runtimeMSUF)
Check(runtimeEventFrame ~= nil, "group runtime event owner was not created")
runtimeGF.UpdateGroupVisibility()
local liveHeader = runtimeGF.headers.party
Check(liveHeader and liveHeader.shown == true, "live Party header was not restored")
Equal(scanCalls, 1, "new Party header was not scanned exactly once after Show")
Equal(appliedChildren, 2, "new Party children were not applied on first restore")
for index = 1, #liveHeader.children do
  Check(liveHeader.children[index].applied == true,
    "first restore left Party child" .. index .. " unapplied")
end

runtimeGF.UpdateGroupVisibility()
Equal(scanCalls, 2, "visible handled scan was duplicated by group runtime")
Equal(appliedChildren, 4, "visible handled scan did not apply each existing Party child once")

print("PASS group preview roster handoff: roster cache, combat guard, first-show and handled scans")
