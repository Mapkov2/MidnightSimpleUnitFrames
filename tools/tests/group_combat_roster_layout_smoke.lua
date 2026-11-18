-- Exercise the group runtime, real addon frames and the secure-header emulator.
local root, flavor = assert(arg[1]), assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function World(zone, raid, partyMode)
  local h = Harness.New(root, flavor, { nativeLayout = true, beforeBoot = function(world)
    local env = world.env
    env.IsInInstance = function() return zone ~= "none", zone end
    env.GetInstanceInfo = function() return "Area", zone, zone == "raid" and 14 or 0 end
    local name = env.UnitName
    env.UnitName = function(unit)
      if world.rosterNames and world.rosterNames[unit] then return world.rosterNames[unit] end
      if raid and zone == "none" and unit == "raid11" and env.UnitExists(unit) then return "Arrival" end
      if unit == (partyMode == "solo" and "party1" or "party2") and env.UnitExists(unit) then return "Arrival" end
      return name(unit)
    end
    local guid, raidInfo = env.UnitGUID, env.GetRaidRosterInfo
    env.UnitGUID = function(unit)
      if world.rosterNames and world.rosterNames[unit] then return "Player-" .. world.rosterNames[unit] end
      return guid(unit)
    end
    env.GetRaidRosterInfo = function(index)
      local unit = world.units[index]
      if world.rosterNames and world.rosterNames[unit] then
        return world.rosterNames[unit], 0, 1, 60, "Warrior", "WARRIOR", nil, true
      end
      return raidInfo(index)
    end
    if raid then
      env.UnitHealth = function() return 81 end
      env.UnitHealthMax = function() return 100 end
      env.UnitPowerType = function() return 0, "MANA" end
      env.UnitPower = function() return 47 end
      env.UnitPowerMax = function() return 100 end
      env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.BreakUpLargeNumbers = tostring, tostring, tostring
    end
  end })
  for _, kind in ipairs({ "party", "raid" }) do
    local conf = h.GF.GetConf(kind)
    conf.enabled, conf.smallRaidAsParty, conf.preserveRaidGroups, conf.showName = true, false, false, true
  end
  if partyMode == "named" then
    local conf = h.GF.GetConf("party")
    conf.sortMode, conf.playerFirstInRole = "ROLE", true
  end
  if raid then
    local conf = h.GF.GetConf("raid")
    conf.showHPText, conf.textRight = true, "CURRENT"
    conf.powerBarEnabled, conf.powerHeight, conf.powerShowDamager = true, 6, true
    h.GF.SetPowerTextEnabled("raid", true)
    conf.powerTextLeft, conf.powerTextCenter, conf.powerTextRight = "CURRENT", "NONE", "NONE"
  end
  if raid then h:SetRaid(4) elseif partyMode ~= "solo" then h:SetRoster({ "player", "party1" }) end
  h.GF.RefreshAll()
  h:Event("PLAYER_ENTERING_WORLD")
  h:RunDeferred()
  return h
end

local function Visible(frame)
  while frame do
    if not frame:IsShown() then return false end
    frame = frame:GetParent()
  end
  return true
end

local function Rect(frame)
  return table.concat({frame:GetRect()}, ",")
end

local function Ordered(h, header)
  local seen = {}
  for _, child in ipairs(h:Children(header)) do
    if Visible(child) then seen[#seen + 1] = assert(child:GetAttribute("unit")) end
  end
  return table.concat(seen, ",")
end

local function FrozenRoster(zone, raidAsParty)
  local raid = zone == "raid"
  local h = World(zone, raid)
  local kind = raid and not raidAsParty and "raid" or "party"
  if raidAsParty then h.GF.GetConf("party").smallRaidAsParty = true end
  local function SetMembers(names)
    local tokens = {}
    h.rosterNames = {}
    for i, name in ipairs(names) do
      local unit = raid and "raid" .. i or (i == 1 and "player" or "party" .. (i - 1))
      tokens[i], h.rosterNames[unit] = unit, name
    end
    if raid then h:SetRaid(#names) else h:SetRoster(tokens) end
    h:Event("GROUP_ROSTER_UPDATE")
  end
  if raid and not raidAsParty then
    SetMembers({"Alpha", "Bravo"})
    h:RunDeferred()
    assert(not h.GF.FrameForUnit("raid3"), "instance raid fixture started with a third visible member")
  end
  SetMembers({"Alpha", "Bravo", "Cora"})
  h:RunDeferred()
  if raid and not raidAsParty then
    local invitee = assert(h.GF.FrameForUnit("raid3"), "missing instance raid invite outside combat")
    local header = assert(h.GF.headers.raid)
    assert(Ordered(h, header) == "raid1,raid2,raid3" and Visible(invitee)
      and invitee:GetWidth() > 0 and invitee:GetHeight() > 0
      and Rect(invitee) ~= Rect(assert(h.GF.FrameForUnit("raid2"))), "instance raid invite failed to lay out before pull")
    for field, value in pairs({nameText = "Cora", hpTextRight = "81", powerTextLeft = "47"}) do
      local region = assert(invitee[field])
      assert(Visible(region) and tostring(region:GetText()) == value, "instance raid invite " .. field .. " missing before pull")
    end
  end
  local priority
  if raidAsParty then
    assert(h.GF.TogglePriorityUnit("raid2"))
    assert(h.GF.TogglePriorityUnit("raid3"))
    h.GF.RefreshAll()
    h:RunDeferred()
    priority = assert(h.GF.headers.priority)
    assert(Ordered(h, priority) == "raid2,raid3", "priority fixture must show both pinned members")
  end
  local header = assert(h.GF.headers[kind])
  local expected = table.concat(h.units, ",")
  assert(Ordered(h, header) == expected, zone .. " fixture has missing slots")
  local original, mutations, nextSlot = {}, {}, 0
  local buttons = h:Children(header)
  local priorityButtons = priority and h:Children(priority)
  local function Watch(frame)
    for _, key in ipairs({"SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent",
        "SetSize", "SetWidth", "SetHeight", "SetScale", "Show", "Hide", "SetShown", "SetAttribute", "ClearAttribute"}) do
      local originalMethod = frame[key]
      if originalMethod then
        frame[key] = function(self, ...)
          local keyName = ...
          if (key ~= "SetAttribute" and key ~= "ClearAttribute") or keyName == "unit" then
            mutations[#mutations + 1] = key
          end
          return originalMethod(self, ...)
        end
      end
    end
  end
  local function Record(frame)
    original[#original + 1] = { frame = frame, rect = Rect(frame), visible = Visible(frame),
      unit = frame:GetAttribute("unit"), parent = frame:GetParent() }
    Watch(frame)
  end
  Record(header)
  for _, child in ipairs(buttons) do
    local unit = child:GetAttribute("unit")
    if unit then
      nextSlot = nextSlot + 1
      Record(child)
      local visual = assert(h.GF.FrameForUnit(unit))
      if visual ~= child then Record(visual) end
    end
  end
  if priority then
    Record(priority)
    for _, child in ipairs(priorityButtons) do Record(child) end
  end
  assert(nextSlot == 3 and Rect(header:GetAttribute("child1")) ~= Rect(header:GetAttribute("child2")),
    "fixture must use distinct native slot coordinates")
  local function CheckPositions(phase)
    assert(header == h.GF.headers[kind] and Ordered(h, header) == expected, zone .. " " .. phase .. " changed slot order")
    for i, child in ipairs(buttons) do assert(header:GetAttribute("child" .. i) == child, phase .. " replaced a button") end
    if priority then
      assert(priority == h.GF.headers.priority and Ordered(h, priority) == "raid2,raid3", phase .. " repacked priority")
      for i, child in ipairs(priorityButtons) do assert(priority:GetAttribute("child" .. i) == child, phase .. " replaced a priority button") end
    end
    for _, slot in ipairs(original) do
      local frame = slot.frame
      assert(Rect(frame) == slot.rect and Visible(frame) == slot.visible and frame:GetParent() == slot.parent
        and frame:GetAttribute("unit") == slot.unit, phase .. " moved, hid, replaced or rebound a slot")
    end
  end
  h:EnterCombat()
  CheckPositions("pull")
  assert(#mutations == 0, "pull repainted protected geometry through " .. tostring(mutations[1]))
  local born, layouts, headers = #h.born, h.headerUpdates, #h.headers
  local geometryCalls = 0
  for _, method in ipairs({"RefreshHeaderLayout", "SetupHeader", "InvalidateLayoutRoster", "ApplyGroupBorder"}) do
    local geometry = h.GF[method]
    h.GF[method] = function(...)
      geometryCalls = geometryCalls + 1
      return geometry(...)
    end
  end
  local function AssertFrozen(phase)
    CheckPositions(phase)
    assert(#mutations == 0, phase .. " performed a protected layout write " .. tostring(mutations[1]))
    assert(#h.born == born and h.headerUpdates == layouts and #h.headers == headers, phase .. " rebuilt a native header")
    assert(geometryCalls == 0, phase .. " invoked group geometry")
  end
  -- A join, a departure with a different member taking its slot, and a reorder
  -- are distinct combat events. A single coalesced final snapshot can miss them.
  for _, roster in ipairs({
      {"Alpha", "Bravo", "Cora", "Delta", "Echo"},
      {"Alpha", "Cora", "Delta", "Echo"},
      {"Alpha", "Echo", "Cora", "Delta"},
  }) do
    SetMembers(roster)
    AssertFrozen("roster event")
    h:Event("UNIT_NAME_UPDATE", h.units[2])
    AssertFrozen("name event")
    h:RunDeferred(nil, nil, function() AssertFrozen("deferred roster or name event") end)
  end
  for i = 1, 8 do
    h:Event("UNIT_HEALTH", h.units[2])
    h:Event("UNIT_POWER_UPDATE", h.units[2], "MANA")
  end
  h:RunDeferred()
  AssertFrozen("ordinary unit updates")
  assert(#h.violations == 0, h.violations[1])
  h:LeaveCombat()
  h:RunDeferred()
  assert(Ordered(h, assert(h.GF.headers[kind])) == table.concat(h.units, ","), "regen failed to reconcile latest slots")
  for _, unit in ipairs(h.units) do
    local frame = assert(h.GF.FrameForUnit(unit))
    assert(Visible(frame) and frame.nameText:GetText() == h.rosterNames[unit], "regen kept stale occupant in " .. unit)
  end
  if priority then
    assert(Ordered(h, assert(h.GF.headers.priority)) == "raid3", "regen retained a departed priority member")
  end
end

local function OpenWorldInvite(partyMode)
  local h = World("none", false, partyMode)
  local unit = partyMode == "solo" and "party1" or "party2"
  local roster = partyMode == "solo" and {"player", "party1"} or {"player", "party1", "party2"}
  local previous = h.GF.FrameForUnit("party1")
  if partyMode ~= "solo" then assert(previous and Visible(previous), "initial outdoor party member missing") end
  assert(not h.GF.FrameForUnit(unit), "outdoor fixture already contains the newcomer")
  if partyMode == "named" then
    assert(h.GF.headers.party:GetAttribute("nameList"), "outdoor fixture must start on a fixed name list")
  end
  h:EnterCombat()
  if partyMode == "solo" then
    assert(not h.GF.headers.raid and not h.GF._headerPool.raid, "solo combat prepared an unused raid header")
  end
  h:SetRoster(roster)
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  local newcomer = assert(h.GF.FrameForUnit(unit), partyMode .. " outdoor invite missing before regen")
  assert(Visible(newcomer) and newcomer:GetWidth() > 0 and newcomer:GetHeight() > 0,
    "outdoor invite has no visible footprint before regen")
  if previous then
    assert(previous == h.GF.FrameForUnit("party1") and Visible(previous) and Rect(newcomer) ~= Rect(previous),
      "outdoor invite displaced or covered the existing member")
  end
  assert(newcomer.nameText and Visible(newcomer.nameText) and newcomer.nameText:GetText() == "Arrival",
    "newcomer's name missing before regen")
  local layouts, born = h.headerUpdates, #h.born
  for i = 1, 8 do
    h:Event("UNIT_HEALTH", unit)
    h:Event("UNIT_POWER_UPDATE", unit, "MANA")
  end
  h:RunDeferred()
  assert(h.headerUpdates == layouts and #h.born == born, "ordinary outdoor unit updates rebuilt the roster")
  assert(#h.violations == 0, h.violations[1])
  if partyMode == "named" then
    h:LeaveCombat()
    h:RunDeferred()
    local names = h.GF.headers.party:GetAttribute("nameList")
    assert(names and names:find("Arrival", 1, true), "regen did not restore the saved sort with the new member")
  end
end

local function OpenWorldRaidReinvite()
  local h = World("none", true)
  local function RosterChanged()
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunDeferred()
  end
  h:SetRaid(11)
  RosterChanged()
  local retired = assert(h.GF.FrameForUnit("raid11"))
  h:SetRoster({"player"})
  RosterChanged()
  h:SetRaid(10)
  RosterChanged()
  assert(not h.GF.FrameForUnit("raid11"), "warm raid fixture retained the departing member")
  h:EnterCombat()
  h:SetRaid(11)
  RosterChanged()
  local newcomer = assert(h.GF.FrameForUnit("raid11"), "outdoor raid invite missing before regen")
  assert(newcomer == retired and Visible(newcomer), "outdoor raid failed to reuse its previous native slot")
  assert(Visible(newcomer.nameText) and newcomer.nameText:GetText() == "Arrival"
    and Visible(newcomer.hpTextRight) and tostring(newcomer.hpTextRight:GetText()) == "81",
    "reused outdoor raid member missing current name or HP")
  assert(#h.violations == 0, h.violations[1])
end

-- Blizzard creates child1 even for an empty secure header. Its initial size
-- recipe runs once, so a pooled button must pick up later profile dimensions.
local function ResizedSoloParty(withPreview)
  local h = World("none", false, "solo")
  local conf = h.GF.GetConf("party")
  conf.width, conf.height, conf.showSolo = 120, 40, false
  h.GF.RefreshAll()
  h:RunDeferred()
  h:EnterCombat()
  local child = assert(h.GF.headers.party:GetAttribute("child1"))
  assert(not child:IsShown() and child:GetWidth() == 120 and child:GetHeight() == 40, "missing old-size parked child")
  h:LeaveCombat()
  h:RunDeferred()

  local nextConf = {}
  for key, value in pairs(conf) do nextConf[key] = value end
  nextConf.width, nextConf.height, nextConf.showPlayer = 229, 59, false
  h.env.MSUF_DB.gf_party = nextConf
  h.GF.InvalidateConfCache()
  h.GF.RefreshAll()
  h:RunDeferred()
  if withPreview then
    -- Blizzard's UnitFrame.lua provides this constant to additional previews.
    h.env.MAX_BOSS_FRAMES = 5
    h.core.ExportPublic("MSUF2_GFPagePreviewActive", true)
    assert(h.GF.ShowPreview("party", 5) ~= false and h.GF._previewActive.party)
  end
  h:EnterCombat()
  if withPreview then h.env.MAX_BOSS_FRAMES = nil end
  assert(child:GetWidth() == 229 and child:GetHeight() == 59, "hidden party button kept the previous profile's size")
  h:SetRoster({"player", "party1"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  assert(h.GF.headers.party:GetAttribute("child1") == child and child:GetAttribute("unit") == "party1"
    and Visible(child) and child:GetWidth() == 229 and child:GetHeight() == 59, "wrong click target for first outdoor invite")
  assert(#h.violations == 0, h.violations[1])
end


ResizedSoloParty(false)
ResizedSoloParty(true)

FrozenRoster("raid")
FrozenRoster("party")
FrozenRoster("raid", true)
OpenWorldInvite("existing")
OpenWorldInvite("named")
OpenWorldInvite("solo")
OpenWorldRaidReinvite()
print("combat roster layout " .. flavor .. ": ok")
