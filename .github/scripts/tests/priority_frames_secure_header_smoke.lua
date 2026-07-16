-- Priority Frames secure header: NAMELIST recipe, inherited metrics, duplicate
-- marker ordering, combat deferral, and strict disabled event teardown.
local root = arg and arg[1] or "."
local unpack = unpack or table.unpack
local combat, deferred, scans, untracked = false, 0, 0, 0
local expectedScanKind = "raid"

_G.InCombatLockdown = function() return combat end
_G.issecretvalue = function() return false end
_G.IsInRaid = function() return true end
_G.IsInGroup = function() return true end
_G.GetNumGroupMembers = function() return 20 end
_G.GetNumSubgroupMembers = function() return 4 end

local Frame = {}
Frame.__index = Frame
local function NewFrame(parent)
  return setmetatable({ parent = parent, shown = true, width = 100, height = 40,
    left = 0, bottom = 0, attrs = {}, events = {}, children = {}, points = {} }, Frame)
end
function Frame:EnableMouse() end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetWidth(w) self.width = w end
function Frame:SetHeight(h) self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetLeft() return self.left end
function Frame:GetRight() return self.left + self.width end
function Frame:GetBottom() return self.bottom end
function Frame:GetTop() return self.bottom + self.height end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, relative, relativePoint, x, y)
  self.points[1] = { point, relative, relativePoint, x or 0, y or 0 }
end
function Frame:IsShown() return self.shown end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:GetAttribute(key) return self.attrs[key] end
function Frame:SetAttribute(key, value) self.attrs[key] = value end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:GetChildren() return unpack(self.children) end

local Header = setmetatable({}, { __index = Frame })
Header.__index = Header
function Header:Show()
  self.shown = true
  local names = self.attrs.nameList or ""
  local count = 0
  for _ in names:gmatch("[^,]+") do count = count + 1 end
  for i = 1, count do
    local child = self.children[i]
    if not child then child = NewFrame(self); self.children[i] = child end
    child.attrs.unit = "raid" .. i
    child.shown = true
  end
  for i = count + 1, #self.children do self.children[i].shown = false end
end

local UIParent = NewFrame(nil)
UIParent:SetSize(1920, 1080)
_G.UIParent, _G.PetBattleFrameHider = UIParent, UIParent

_G.CreateFrame = function(_, _, parent, template)
  local frame
  if template == "SecureGroupHeaderTemplate" then
    frame = setmetatable(NewFrame(parent), Header)
    frame.shown = false
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_NAME_UPDATE")
  else
    frame = NewFrame(parent)
  end
  return frame
end

local priorityConf = {
  enabled = true, autoTanks = true, maxFrames = 5, growth = "DOWN", spacing = 3,
  anchorMode = "RAID_RIGHT", attachGap = 8, attachOffset = 0,
  point = "CENTER", relativePoint = "CENTER", offsetX = -120, offsetY = 0,
}
local GF = { headers = {}, anchors = {}, _headerPool = {} }
function GF.EnsureDB() end
function GF.GetPriorityConf() return priorityConf end
function GF.GetConf() return { showPlayer = true, width = 80, height = 32 } end
function GF.GetScaledFrameMetrics(kind)
  if kind == "party" then return 120, 40, 1 end
  return 80, 32, 1
end
function GF.UntrackFrame() untracked = untracked + 1 end
function GF.ScheduleScan(key, kind)
  scans = scans + 1
  assert(key == "priority" and kind == expectedScanKind)
  for _, child in ipairs(GF.headers.priority.children) do
    if child.shown then assert(child._msufGFPriorityFrame == true, "child scanned before duplicate marker") end
  end
  return true
end
function GF.DeferGroupRuntime(reason) assert(reason == "priority"); deferred = deferred + 1 end

local UF = {}
function UF.GetSecureHeaderUnitButtonTemplate() return "SecureUnitButtonTemplate, PingableUnitFrameTemplate" end
function UF.ForEachPingBindingAttribute(callback) callback("ping-receiver", true) end
local MSUF = { GF = GF, UF = UF }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua"))(
  "MidnightSimpleUnitFrames", MSUF)

local raidAnchor = NewFrame(UIParent)
raidAnchor.left, raidAnchor.bottom = 200, 300
raidAnchor:SetSize(400, 320)
GF.anchors.raid = raidAnchor
local partyAnchor = NewFrame(UIParent)
partyAnchor.left, partyAnchor.bottom = 40, 120
partyAnchor:SetSize(300, 220)
GF.anchors.party = partyAnchor

local header = assert(GF.SetupPriorityHeader("raid", "TankA-Realm,TankB-Realm,DpsA-Realm", 3))
assert(header:IsShown() and header:GetAttribute("sortMethod") == "NAMELIST")
assert(header:GetAttribute("nameList") == "TankA-Realm,TankB-Realm,DpsA-Realm")
assert(header:GetAttribute("showRaid") == true and header:GetAttribute("showParty") == false)
assert(header:GetAttribute("showPlayer") == true and header:GetAttribute("showSolo") == false)
assert(#header.children == 3 and scans == 1, "secure header did not build/scan three children")
assert(GF.anchors.priority.width == 80 and GF.anchors.priority.height == 102,
  "priority bounds did not inherit raid size and configured spacing")
assert(header.events.GROUP_ROSTER_UPDATE and header.events.UNIT_NAME_UPDATE,
  "active secure header is missing Blizzard roster events")

expectedScanKind = "mythicraid"
assert(GF.SetupPriorityHeader("mythicraid", "TankA-Realm,TankB-Realm,DpsA-Realm", 3) == header)
assert(scans == 2 and header.children[1]._msufGFKind == "mythicraid",
  "live Raid to Mythic Raid style switch did not rescan priority children")

expectedScanKind = "party"
assert(GF.SetupPriorityHeader("party", "Self-Realm,DpsA-Realm", 2) == header)
assert(header:GetAttribute("showParty") == true and header:GetAttribute("showRaid") == false
  and header:GetAttribute("showPlayer") == true and header:GetAttribute("showSolo") == false,
  "reused secure header did not switch from Raid to Party visibility")
assert(scans == 3 and header.children[1]._msufGFKind == "party",
  "Raid-to-Party style switch did not rescan Priority children")
assert(GF.anchors.priority.width == 120 and GF.anchors.priority.height == 83,
  "Party Priority bounds did not inherit Party metrics")
assert(GF.anchors.priority.points[1] and GF.anchors.priority.points[1][2] == partyAnchor,
  "Party Priority strip did not attach to the Party anchor")
expectedScanKind = "raid"

assert(GF.RetireHeader("priority") == true)
assert(next(header.events) == nil, "disabled priority header retained Blizzard events")
assert(GF.anchors.priority:IsShown() == false and untracked == 3,
  "priority retirement did not hide and detach every child")

local reused = assert(GF.SetupPriorityHeader("raid", "TankA-Realm", 1))
assert(reused == header and reused.events.GROUP_ROSTER_UPDATE and reused.events.UNIT_NAME_UPDATE,
  "pooled priority header did not restore its secure events")

combat = true
assert(GF.SetupPriorityHeader("raid", "TankA-Realm,TankB-Realm", 2) == nil and deferred == 1,
  "combat setup did not defer protected header mutation")

print("PASS priority frames secure header: name-list lifecycle and inert retirement")
