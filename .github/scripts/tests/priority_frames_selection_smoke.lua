-- Priority Frames: resolver order, character-local pins, hover binding, and
-- disabled-state ownership. This module must create no event frame of its own.
local root = arg and arg[1] or "."

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local roster = {
  { name = "TankA-Realm", guid = "Player-1", role = "TANK" },
  { name = "TankB-Realm", guid = "Player-2", role = "TANK" },
  { name = "DpsA-Realm", guid = "Player-3", role = "DAMAGER" },
  { name = "HealA-Realm", guid = "Player-4", role = "HEALER" },
}
local inRaid = true
local inGroup = true
local refreshes = 0
local createdFrames = 0
local raidConf = { enabled = true }
local partyConf = { enabled = true }
local partyRoster = {
  player = { name = "Self", realm = "Realm", guid = "Player-Self", role = "TANK" },
  party1 = { name = "PartyDps", realm = "OtherRealm", guid = "Player-PartyDps", role = "DAMAGER" },
  party2 = { name = "HealRenamed", realm = "Realm", guid = "Player-4", role = "HEALER" },
}
local conf = {
  enabled = true,
  autoTanks = true,
  maxFrames = 5,
  growth = "DOWN",
  spacing = 2,
  anchorMode = "RAID_RIGHT",
  attachGap = 8,
  attachOffset = 0,
  point = "CENTER",
  relativePoint = "CENTER",
  offsetX = -120,
  offsetY = 0,
}

_G.MSUF_GlobalDB = { char = { ["Tester-Realm"] = {} } }
_G.MSUF_GetCharKey = function() return "Tester-Realm" end
_G.IsInRaid = function() return inRaid end
_G.IsInGroup = function() return inGroup end
_G.GetNumGroupMembers = function() return inRaid and #roster or (inGroup and 3 or 0) end
_G.GetNumSubgroupMembers = function() return not inRaid and inGroup and 2 or 0 end
_G.GetRaidRosterInfo = function(index) return roster[index] and roster[index].name end
_G.UnitName = function(unit)
  local entry = partyRoster[unit]
  return entry and entry.name or nil, entry and entry.realm or nil
end
_G.UnitGUID = function(unit)
  if partyRoster[unit] and not inRaid then return partyRoster[unit].guid end
  local index = tonumber(type(unit) == "string" and unit:match("^raid(%d+)$"))
  return index and roster[index] and roster[index].guid or nil
end
_G.UnitGroupRolesAssigned = function(unit)
  if partyRoster[unit] and not inRaid then return partyRoster[unit].role end
  local index = tonumber(type(unit) == "string" and unit:match("^raid(%d+)$"))
  return index and roster[index] and roster[index].role or "NONE"
end
_G.issecretvalue = function() return false end
_G.wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end; return tbl end
_G.CreateFrame = function() createdFrames = createdFrames + 1; return {} end
_G.UIErrorsFrame = { AddMessage = function() end }
_G.GetMouseFoci = nil

local MSUF = { GF = {} }
function MSUF.ExportPublic(name, value) _G[name] = value; return value end
function MSUF.GF.EnsureDB() end
function MSUF.GF.GetPriorityConf() return conf end
function MSUF.GF.GetLiveRaidKind() return "raid" end
function MSUF.GF.GetConf(kind) return kind == "party" and partyConf or raidConf end
function MSUF.GF.RefreshPriorityFrames()
  refreshes = refreshes + 1
  return true
end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Priority.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local GF = MSUF.GF

Check(createdFrames == 0, "Priority selection module created a permanent frame")
local nameList, count = GF.ResolvePrioritySelection()
Check(count == 2 and nameList == "TankA-Realm,TankB-Realm", "automatic tank order is not deterministic")

local ok, code = GF.TogglePriorityUnit("raid3")
Check(ok and code == "ADDED" and refreshes == 1, "hover pin did not apply immediately")
nameList, count = GF.ResolvePrioritySelection()
Check(count == 3 and nameList == "TankA-Realm,TankB-Realm,DpsA-Realm", "manual pin did not follow tanks")

local pins = GF.GetPriorityPins()
Check(#pins == 1 and pins[1].guid == "Player-3" and pins[1].name == "DpsA-Realm",
  "pin was not stored in character-local GUID/name form")
local view = GF.GetPriorityPinView()
Check(#view == 1 and view[1].present and view[1].active and view[1].unit == "raid3",
  "pin view did not expose live roster state")

ok, code = GF.TogglePriorityUnit("raid3")
Check(ok and code == "REMOVED" and #GF.GetPriorityPins() == 0, "second toggle did not remove the pin")

conf.maxFrames = 2
ok, code = GF.TogglePriorityUnit("raid4")
Check(not ok and code == "FULL" and #GF.GetPriorityPins() == 0, "visible slot cap was not enforced")

conf.enabled = false
ok, code = GF.TogglePriorityUnit("raid1")
Check(ok and code == "ADDED_AUTO_TANK" and conf.enabled == true,
  "first hotkey use did not enable automatic tank Priority Frames")

conf.autoTanks = false
conf.maxFrames = 5
ok, code = GF.TogglePriorityUnit("raid4")
Check(ok and code == "ADDED", "manual healer pin failed")
roster[4] = nil
nameList, count = GF.ResolvePrioritySelection()
Check(count == 0 and nameList == nil and #GF.GetPriorityPins() == 1,
  "absent player pin was not preserved while hidden")
view = GF.GetPriorityPinView(view)
Check(view[1].waitingReason == "NOT_PRESENT", "absent pin status is incorrect")
roster[4] = { name = "HealA-Realm", guid = "Player-4", role = "HEALER" }
nameList, count = GF.ResolvePrioritySelection()
Check(count == 1 and nameList == "HealA-Realm", "returning player pin did not reactivate")

raidConf.enabled = false
local state
state, view = GF.GetPriorityMenuSnapshot({}, view)
Check(state.selectedCount == 1 and state.visibleCount == 0 and state.activeCount == 0 and not state.active,
  "menu state reported selected players as visible while Raid frames were disabled")
Check(view[1].selected and not view[1].active and view[1].waitingReason == "GROUP_FRAMES_DISABLED",
  "pin row reported Visible while its owning Raid frames were disabled")
raidConf.enabled = true

local hovered = {
  _msufIsGroupFrame = true,
  _msufGFKind = "raid",
  _msufGFIsPreviewFrame = false,
  GetAttribute = function(_, key) return key == "unit" and "raid4" or nil end,
}
_G.GetMouseFoci = function() return { hovered } end
Check(GF.GetHoveredPriorityUnit() == "raid4", "PTR table-form GetMouseFoci was not resolved")

local notified = 0
GF.RegisterPriorityListener("smoke", function() notified = notified + 1 end)
GF.SetPriorityOption("growth", "RIGHT")
Check(conf.growth == "RIGHT" and notified == 1, "menu mutation listener did not fire")
GF.UnregisterPriorityListener("smoke")

conf.enabled = false
roster[4] = { name = "Other-Realm", guid = "Player-99", role = "DAMAGER" }
view = GF.GetPriorityPinView(view)
Check(view[1].present == false and view[1].unit == nil and view[1].waitingReason == "NOT_PRESENT",
  "disabled pin view reused stale roster identity from the preceding raid snapshot")

inRaid = false
conf.enabled = true
conf.autoTanks = true
nameList, count, units = GF.ResolvePrioritySelection()
Check(count == 2 and nameList == "Self-Realm,HealRenamed-Realm"
  and units[1] == "player" and units[2] == "party2",
  "party resolver did not order the player tank before the GUID-remapped pin")
state, view = GF.GetPriorityMenuSnapshot(state, view)
Check(GF.GetPriorityPins()[1].name == "HealRenamed-Realm",
  "party GUID match did not self-heal the saved secure-header name")
Check(state.inGroup and state.inParty and not state.inRaid and state.baseKind == "party"
  and state.baseFramesEnabled and state.visibleCount == 2,
  "party menu state did not expose the active Party frame dependency")

partyConf.enabled = false
state, view = GF.GetPriorityMenuSnapshot(state, view)
Check(state.visibleCount == 0 and not view[1].active
  and view[1].waitingReason == "GROUP_FRAMES_DISABLED",
  "disabled Party frames were reported as visible Priority Frames")
partyConf.enabled = true

hovered._msufGFKind = "party"
hovered.GetAttribute = function(_, key) return key == "unit" and "party1" or nil end
Check(GF.GetHoveredPriorityUnit() == "party1", "Party frame mouseover did not resolve party1")
ok, code = GF.TogglePriorityUnit("party1")
Check(ok and code == "ADDED", "cross-realm Party member could not be pinned")
nameList, count = GF.ResolvePrioritySelection()
Check(count == 3 and nameList == "Self-Realm,HealRenamed-Realm,PartyDps-OtherRealm",
  "Party nameList did not mirror Blizzard UnitName plus realm semantics")

inGroup = false
nameList, count = GF.ResolvePrioritySelection()
Check(nameList == nil and count == 0, "Priority Frames resolved units while solo")
ok, code = GF.TogglePriorityUnit("party1")
Check(not ok and code == "NOT_IN_GROUP" and #GF.GetPriorityPins() == 2,
  "solo toggle did not preserve Party/Raid pins with NOT_IN_GROUP feedback")

print("PASS priority frames selection: Party/Raid secure-list policy and zero-frame ownership")
