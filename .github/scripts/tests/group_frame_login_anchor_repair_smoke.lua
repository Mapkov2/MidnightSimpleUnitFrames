-- Regression: raid anchors must repair themselves after login/roster secure
-- header sizing and after the saved scale pass, without opening Menu2/Edit Mode.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
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

local Frame = {}
Frame.__index = Frame

local function NewFrame(name, parent, hidden)
  return setmetatable({
    name = name,
    parent = parent,
    shown = hidden ~= true,
    width = 0,
    height = 0,
    attributes = {},
    events = {},
    scripts = {},
  }, Frame)
end

function Frame:EnableMouse() end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
  self.point = {
    point = point,
    relativeTo = relativeTo,
    relativePoint = relativePoint,
    x = x or 0,
    y = y or 0,
  }
end
function Frame:IsShown() return self.shown == true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetChildren() return nil end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetScript(name, callback) self.scripts[name] = callback end

local function RunCase(liveKind)
  local combat = false
  local timers = {}
  local refreshReasons = {}
  local runtimeFrame

  local UIParent = NewFrame("UIParent", nil, false)
  UIParent:SetSize(1000, 600)
  function UIParent:GetLeft() return 0 end
  function UIParent:GetRight() return self.width end
  function UIParent:GetBottom() return 0 end
  function UIParent:GetTop() return self.height end

  _G.UIParent = UIParent
  _G.PetBattleFrameHider = UIParent
  _G.InCombatLockdown = function() return combat end
  _G.IsInGroup = function() return true end
  _G.IsInRaid = function() return true end
  _G.GetNumGroupMembers = function() return 20 end
  _G.GetNumSubgroupMembers = function() return 0 end
  _G.C_Timer = {
    After = function(delay, callback)
      Equal(delay, 0, liveKind .. " settle delay")
      timers[#timers + 1] = callback
    end,
  }
  _G.CreateFrame = function(_, name, parent, template)
    local frame = NewFrame(name, parent, template == "SecureGroupHeaderTemplate")
    if name == nil and parent == nil and template == nil then runtimeFrame = frame end
    return frame
  end

  local partyConf = { enabled = false }
  local raidConf = {
    enabled = true,
    width = 50,
    height = 20,
    spacing = 0,
    growth = "DOWN",
    unitsPerColumn = 5,
    maxColumns = 8,
    preserveRaidGroups = false,
    showPlayer = true,
    sortMode = "INDEX",
    frameScaleMode = "off",
    point = "TOPLEFT",
    relativePoint = "TOPLEFT",
    offsetX = 850,
    offsetY = -10,
    positionMode = "GRID_BOUNDS_V2",
  }
  local mythicConf = {}
  for key, value in pairs(raidConf) do mythicConf[key] = value end

  local GF = { headers = {}, anchors = {}, _headerPool = {}, Metadata = {} }
  function GF.EnsureDB() end
  function GF.GetConf(kind)
    if kind == "party" then return partyConf end
    return kind == "mythicraid" and mythicConf or raidConf
  end
  function GF.AnyMSUFGroupFrameEnabled() return true end
  function GF.GetLiveRaidKind() return liveKind end
  function GF.GetScaledFrameMetrics() return 50, 20, 0 end
  function GF.GetGridMetrics() return 0, 0, 100, 50 end
  function GF.EnsureStableGridPosition() return false end
  function GF.GetConfigDBKey(kind) return "gf_" .. kind end
  function GF.ScheduleScan() return true end
  function GF.ForEachFrame(_, _, reason)
    refreshReasons[#refreshReasons + 1] = reason
    return false
  end
  function GF.UntrackFrame() end

  local MSUF = {
    GF = GF,
    UF = {},
    ExportPublic = function(name, value)
      _G[name] = value
      return value
    end,
  }
  _G.MSUF_NS = MSUF
  _G.MSUF = MSUF

  local headersChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"))
  headersChunk("MidnightSimpleUnitFrames", MSUF)
  local runtimeChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))
  runtimeChunk("MidnightSimpleUnitFrames", MSUF)

  Check(runtimeFrame and runtimeFrame.scripts.OnEvent, liveKind .. " runtime driver missing")
  runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_LOGIN")
  local header = GF.headers.raid
  local anchor = GF.anchors.raid
  Check(header and anchor, liveKind .. " login did not create the live raid header")
  Equal(header._msufGFKind, liveKind, liveKind .. " login selected the wrong config")
  Equal(anchor.point.x, 850, liveKind .. " estimated login anchor")
  Equal(#timers, 0, liveKind .. " PLAYER_LOGIN unexpectedly queued a settle")

  runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_ENTERING_WORLD")
  runtimeFrame.scripts.OnEvent(runtimeFrame, "GROUP_ROSTER_UPDATE")
  runtimeFrame.scripts.OnEvent(runtimeFrame, "GROUP_ROSTER_UPDATE")
  runtimeFrame.scripts.OnEvent(runtimeFrame, "ZONE_CHANGED_NEW_AREA")
  Equal(#timers, 1, liveKind .. " login/roster settles did not coalesce")
  Equal(anchor.point.x, 850, liveKind .. " anchor repaired before Blizzard settled")

  -- Blizzard's secure layout has now replaced the transient estimate with the
  -- real footprint. The queued MSUF pass must measure and clamp this value.
  header:SetSize(300, 100)
  refreshReasons = {}
  local settle = table.remove(timers, 1)
  settle()

  Check(GF.headers.raid == header, liveKind .. " settle recreated the secure header")
  Check(GF.anchors.raid == anchor, liveKind .. " settle replaced the anchor")
  Equal(header._msufGFKind, liveKind, liveKind .. " settle changed the live config")
  Equal(anchor.width, 300, liveKind .. " settle ignored the real header width")
  Equal(anchor.height, 100, liveKind .. " settle ignored the real header height")
  Equal(anchor.point.point, "TOPLEFT", liveKind .. " anchor point")
  Equal(anchor.point.relativePoint, "TOPLEFT", liveKind .. " relative anchor point")
  Equal(anchor.point.x, 700, liveKind .. " settled clamp X")
  Equal(anchor.point.y, -10, liveKind .. " settled clamp Y")
  Equal(refreshReasons[1], "GROUP_ROSTER_UPDATE", liveKind .. " coalescing lost the roster reason")
  Equal(refreshReasons[2], "PLAYER_ROLES_ASSIGNED", liveKind .. " coalescing lost the role refresh")
  Equal(#timers, 0, liveKind .. " settle left an extra timer")

  -- If combat begins after the roster event but before the queued callback,
  -- the repair must join the existing regen replay instead of touching the
  -- protected header or being lost.
  runtimeFrame.scripts.OnEvent(runtimeFrame, "GROUP_ROSTER_UPDATE")
  Equal(#timers, 1, liveKind .. " combat bridge did not queue a settle")
  header:SetSize(350, 100)
  combat = true
  table.remove(timers, 1)()
  Check(GF._pendingGroupRuntime == true, liveKind .. " combat settle was not deferred")
  Equal(anchor.point.x, 700, liveKind .. " combat settle touched the protected anchor")

  combat = false
  runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_REGEN_ENABLED")
  Check(GF._pendingGroupRuntime == nil, liveKind .. " regen did not consume the deferred settle")
  Equal(anchor.width, 350, liveKind .. " regen ignored the settled header width")
  Equal(anchor.point.x, 650, liveKind .. " regen did not repair the settled clamp")

  if liveKind == "raid" then
    -- Normal and mythic modes reuse the same secure raid header. The immediate
    -- difficulty pass can therefore still see the old mode's footprint; its
    -- queued settle must keep the header and clamp against the new one.
    mythicConf.offsetX = 780
    liveKind = "mythicraid"
    runtimeFrame.scripts.OnEvent(runtimeFrame, "PLAYER_DIFFICULTY_CHANGED")
    Check(GF.headers.raid == header, "difficulty switch replaced the shared raid header")
    Equal(header._msufGFKind, "mythicraid", "difficulty switch kept the normal raid config")
    Equal(#timers, 1, "difficulty switch did not queue a settle")
    Equal(anchor.point.x, 650, "difficulty switch did not expose the stale footprint")

    header:SetSize(260, 100)
    table.remove(timers, 1)()
    Equal(anchor.width, 260, "difficulty settle ignored the mythic footprint")
    Equal(anchor.point.x, 740, "difficulty settle did not repair the mythic clamp")

    runtimeFrame.scripts.OnEvent(runtimeFrame, "ZONE_CHANGED_NEW_AREA")
    Equal(#timers, 1, "zone switch did not queue the shared settle path")
    table.remove(timers, 1)()
    Equal(anchor.point.x, 740, "zone settle changed the stable mythic clamp")
  end
end

RunCase("raid")
RunCase("mythicraid")

-- Saved addon/UI scale is itself applied after login. Its existing coalesced
-- reanchor flush must include group geometry as well as ordinary unit frames.
local scaleRuntime = Read("MidnightSimpleUnitFrames/Runtime/MSUF_UIScaleRuntime.lua")
Check(scaleRuntime:find("local function RefreshGroupFrameGeometryAfterScale()", 1, true),
  "saved-scale reanchor has no group-frame bridge")
Check(Count(scaleRuntime, "RefreshGroupFrameGeometryAfterScale()") >= 3,
  "saved-scale reanchor does not cover both OOC and combat-deferred paths")

print("PASS group frame login anchor repair: raid/mythic secure settle, coalesced roster/difficulty replay, saved-scale bridge")
