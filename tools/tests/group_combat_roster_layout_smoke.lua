-- Exercise the group runtime, real addon frames and the secure-header emulator.
local root, flavor = assert(arg[1]), assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local compiledChunks = {}

local function World(zone, raid, partyMode, configure)
  local h = Harness.New(root, flavor, { compiledChunks = compiledChunks, nativeLayout = true, beforeBoot = function(world)
    local env = world.env
    env.IsInInstance = function() return zone ~= "none", zone end
    env.GetInstanceInfo = function() return "Area", zone, zone == "raid" and 14 or 0 end
    local subgroupCount = env.GetNumSubgroupMembers
    env.GetNumSubgroupMembers = function() return world.reportedCompanions or subgroupCount() end
    local name = env.UnitName
    env.UnitName = function(unit)
      if world.pendingName == unit then return nil end
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
    if configure then configure(world) end
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

local function LateDungeonPartyName(option)
  local h = World("party", false)
  local conf = h.GF.GetConf("party")
  conf.sortMode, conf.playerFirstInRole, conf.sortClassPriority = "ROLE", false, false
  conf[option] = true
  h.GF.Rebuild("party")
  h:RunDeferred()
  local header = assert(h.GF.headers.party)
  assert(header:GetAttribute("sortMethod") == "NAMELIST", "custom Party sort should start active")

  h.pendingName = "party2"
  h:SetRoster({ "player", "party1", "party2" })
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  assert(header:GetAttribute("nameList") == nil, "third join published an incomplete Party nameList: " .. option)
  h.pendingName = nil
  h:Event("UNIT_NAME_UPDATE", "party2")
  local visibleOnFirstTurn = false
  h:RunDeferred(nil, function(turn)
    if turn ~= 1 then return end
    local names = header:GetAttribute("nameList")
    local frame = h.GF.FrameForUnit("party2")
    visibleOnFirstTurn = names and names:find("Arrival", 1, true) and frame and Visible(frame)
  end)
  assert(visibleOnFirstTurn and Ordered(h, header) == "player,party1,party2",
    "third member must be visible on the first layout after its name event: " .. option)

  -- A readable name can still acquire its full identity after the first roster snapshot.
  h.rosterNames = { party2 = "Arrival-Realm" }
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Arrival-Realm", 1, true) and Visible(assert(h.GF.FrameForUnit("party2"))),
    "a completed list retained the old Party identity")

  h.reportedCompanions = 1
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  assert(header:GetAttribute("nameList") == nil, "stale subgroup count filtered an existing Party token")
  h:EnterCombat()
  h.reportedCompanions = nil
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:RunDeferred()
  assert(header:GetAttribute("nameList") == nil, "late identity changed the frozen dungeon header")
  h:LeaveCombat()
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Arrival-Realm", 1, true), "regen lost custom Party sorting")

  conf.enabled = false
  h.GF.RefreshHeaderLayout("party")
  assert(not h.GF.headers.party, "disabled Party header stayed active")
  conf.enabled = true
  h.pendingName = "party2"
  h.GF.UpdateGroupVisibility()
  assert(h.GF.headers.party == header and not header:GetAttribute("nameList"), "Party header was not restored")
  h.pendingName = nil
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:RunDeferred()
  assert(header:GetAttribute("nameList"), "restoring Party visibility did not resume name updates")

  conf[option] = false
  h.GF.Rebuild("party")
  h:RunDeferred()
  local layouts, refresh = 0, h.GF.RefreshHeaderLayout
  h.GF.RefreshHeaderLayout = function(...)
    layouts = layouts + 1
    return refresh(...)
  end
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:RunDeferred()
  assert(layouts == 0 and not header:GetAttribute("nameList"), "native Party sorting scheduled a layout for a name")
  assert(#h.violations == 0, h.violations[1])
end

local function PartyNameBurst(option)
  local h = World("party", false)
  local gf, conf = h.GF, h.GF.GetConf("party")
  conf.sortMode, conf[option] = "ROLE", true
  h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
  gf.Rebuild("party")
  h:RunDeferred()
  local header = assert(gf.headers.party)
  local initialNames = assert(header:GetAttribute("nameList"))
  h:EnterCombat()
  h:RunDeferred()
  local deferrals, layouts = 0, 0
  local defer, refresh = gf.DeferGroupRuntime, gf.RefreshHeaderLayout
  gf.DeferGroupRuntime = function(...)
    deferrals = deferrals + 1
    return defer(...)
  end
  gf.RefreshHeaderLayout = function(...)
    layouts = layouts + 1
    return refresh(...)
  end
  h.rosterNames = { party2 = "Arrival-Realm" }
  for i = 1, 20 do h:Event("UNIT_NAME_UPDATE", "party" .. ((i - 1) % 4 + 1)) end
  for i = 1, 20 do h:Event("UNIT_NAME_UPDATE", "nameplate1") end
  h:RunDeferred()
  assert(deferrals == 1, option .. ": expected one frozen-roster request, got " .. deferrals)
  assert(layouts == 0 and header:GetAttribute("nameList") == initialNames, "name burst rebuilt the header in combat")
  gf.DeferGroupRuntime, gf.RefreshHeaderLayout = defer, refresh
  h:LeaveCombat()
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Arrival-Realm", 1, true), "regen missed the new Party identity")

  h:EnterCombat()
  h:LeaveCombat()
  h.rosterNames.party2 = "Arrival-Home"
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Arrival-Home", 1, true), "quiet combat did not restore name updates")
  assert(#h.violations == 0, h.violations[1])
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
  local h = World("none", false, partyMode, function(world)
    world.env.SetPortraitTexture = function(texture, unit) texture.portraitUnit = unit end
  end)
  if partyMode == "solo" then
    local conf = h.GF.GetConf("party")
    conf.portraitMode, conf.portraitRender = "RIGHT", "2D"
    h.GF.Rebuild("party")
    h:RunDeferred()
  end
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
  if partyMode == "solo" then
    assert(Visible(newcomer.MSUFPortraitHolder) and newcomer.portrait.portraitUnit == unit,
      "first invite after a solo pull did not paint the 2D portrait during combat")
    assert(newcomer:GetAttribute("*type1") == "target", "first invite lost secure targeting")
  end
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

local function SoloCombatPortraitInvite()
  local secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
  local h = World("none", false, nil, function(world)
    world.env.issecretvalue = secrets.IsSecret
    world.widgets.Methods.SetUnit = function(model, unit) model.boundUnit = unit end
  end)
  local gf, conf = h.GF, h.GF.GetConf("party")
  conf.portraitMode, conf.portraitRender, conf.portraitClickable = "RIGHT", "3D", true
  conf.powerBarEnabled, conf.powerHeight, conf.powerShowDamager = true, 7, true
  gf.Rebuild("party")
  h:RunDeferred()
  local child = assert(gf.FrameForUnit("party1"))
  local bar, holder, button = child.hpBar, child.MSUFPortraitHolder, child.MSUFPortraitClickTarget
  local model = assert(holder.model3D)
  local inset = bar._msufHealthPowerInset
  assert(inset > 0 and model.boundUnit == "party1" and button:IsShown(), "initial clickable party portrait missing")

  local function CheckHitBounds()
    assert(button:GetNumPoints() == holder:GetNumPoints() and holder:GetNumPoints() > 0)
    for i = 1, holder:GetNumPoints() do
      local point, anchor, relPoint, x, y = holder:GetPoint(i)
      local bp, ba, br, bx, by = button:GetPoint(i)
      assert(bp == point and ba == anchor and br == relPoint and bx == x and by == y,
        "secure hit target does not match the portrait anchors")
    end
    if holder:GetNumPoints() == 1 then
      assert(button:GetWidth() == holder:GetWidth() and button:GetHeight() == holder:GetHeight(), "wrong portrait hit size")
    end
  end

  -- A secure click button also protects the regions it is anchored to. The ordinary
  -- header fixture models parent protection only. Refuse the reported native writes.
  local blocked = {}
  local function Guard(region, method, restricted)
    local original = region[method]
    region[method] = function(self, ...)
      if h.env.InCombatLockdown() and restricted() then
        blocked[#blocked + 1] = self:GetObjectType() .. ":" .. method
        return
      end
      return original(self, ...)
    end
  end
  -- The client can retain protection on a previously anchored health bar.
  h.Protect(bar)
  bar.IsProtected = function() return true, false end
  bar.CanChangeProtectedState = function() return not h.env.InCombatLockdown() end
  Guard(bar, "ClearAllPoints", bar.IsProtected)
  Guard(bar, "SetPoint", bar.IsProtected)
  local function HolderAnchorsSecureButton()
    return button.allPoints == holder or select(2, button:GetPoint()) == holder
  end
  Guard(holder, "Show", HolderAnchorsSecureButton)
  Guard(holder, "SetShown", HolderAnchorsSecureButton)
  Guard(holder, "ClearAllPoints", HolderAnchorsSecureButton)

  h:SetRoster({"player"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  assert(not gf.FrameForUnit("party1") and not holder:IsShown(), "leaving the group did not retire the slot")
  local _, _, _, _, oldOffset = bar:GetPoint(2)
  assert(oldOffset == 0, "retired slot still reserves the old occupant's power bar")
  model.boundUnit = nil
  h.rosterNames = { party1 = "Incoming" }
  h:EnterCombat()
  h:SetRoster({"player", "party1"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  assert(#blocked == 0, "solo combat invite attempted protected geometry: " .. tostring(blocked[1]))
  assert(gf.FrameForUnit("party1") == child and child:GetAttribute("unit") == "party1"
    and Visible(holder) and Visible(model) and model.boundUnit == "party1"
    and child.nameText:GetText() == "Incoming", "retired portrait did not display the new occupant during combat")
  local _, _, _, _, combatOffset = bar:GetPoint(2)
  assert(combatOffset == oldOffset and bar._msufHealthPowerInset == oldOffset, "locked bar committed an unapplied inset")
  h:SetRoster({"player", "party1", "party2"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  local fresh = assert(gf.FrameForUnit("party2"))
  assert(fresh.hpBar._msufHealthPowerInset == inset and Visible(fresh.MSUFPortraitHolder.model3D)
    and fresh.MSUFPortraitHolder.model3D.boundUnit == "party2", "fresh combat child lost its health geometry or portrait")

  -- The native widget-security answer can itself be secret.
  local secret = secrets.New("boolean")
  local function Opaque() return secret end
  local stop = secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua", { strict = true })
  bar.CanChangeProtectedState = Opaque
  h.core.UF.elements.Health.Layout(child)
  bar.CanChangeProtectedState, bar.IsProtected = nil, Opaque
  h.core.UF.elements.Health.Layout(child)
  local misuse = stop()
  assert(#misuse == 0, misuse[1])
  assert(#blocked == 0, "opaque protection state allowed a health anchor write")

  h:LeaveCombat()
  h:RunDeferred()
  local _, _, _, _, restoredOffset = bar:GetPoint(2)
  assert(restoredOffset == inset and bar._msufHealthPowerInset == inset, "regen did not restore the current health inset")
  CheckHitBounds()
  conf.portraitOffsetX, conf.portraitOffsetY = 6, -4
  for _, placement in ipairs({"OVERLAY", "DETACHED", "ATTACHED"}) do
    conf.portraitPlacement, conf.portraitOverlayAlign = placement, "FULL"
    gf.Rebuild("party")
    CheckHitBounds()
  end
  -- A reapply may see new placement before the already-active secure target can move.
  h:EnterCombat()
  conf.portraitOffsetX = 19
  gf.InvalidateCompiledSpecs("party")
  assert(gf.ApplyButton(child, "party", "UNIT_CHANGED"))
  CheckHitBounds()
  h:LeaveCombat()
  h:RunDeferred()
  CheckHitBounds()
  assert(holder._msufX == 19, "regen lost deferred portrait placement")
  assert(button:IsShown() and button:GetAttribute("useparent-unit") and Visible(model), "regen did not restore portrait targeting")
  assert(#h.violations == 0, h.violations[1])
end

local function SoloInviteWorldTransition()
  local h = World("none", false, "solo")
  h:EnterCombat()
  h:SetRoster({"player", "party1"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:Event("PLAYER_LEAVING_WORLD")
  h:RunDeferred()
  h:Event("PLAYER_ENTERING_WORLD")
  h:RunDeferred()
  local child = h.GF.FrameForUnit("party1")
  assert(child and Visible(child) and child:GetAttribute("unit") == "party1" and child.nameText:GetText() == "Arrival",
    "returning to the outdoor world lost the invite queued during combat")

  h:SetRoster({"player", "party1", "party2"})
  h:Event("GROUP_ROSTER_UPDATE")
  h:Event("PLAYER_LEAVING_WORLD")
  h.env.IsInInstance = function() return true, "party" end
  h:Event("PLAYER_ENTERING_WORLD")
  h:RunDeferred()
  assert(not h.GF.FrameForUnit("party2"), "an outdoor binding was applied inside the instance in combat")
  h:LeaveCombat()
  h:RunDeferred()
  assert(h.GF.FrameForUnit("party2"), "regen lost the member on entry to the instance")
  assert(#h.violations == 0, h.violations[1])
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


local function PartyAlongsideRaid()
  local h = World("raid", true)
  local gf = h.GF
  local party = gf.GetConf("party")
  assert(party.showPartyInRaid == false and gf.GetDefault("raid", "showPartyInRaid") == nil,
    "parallel party frames must be opt-in and scoped to Party")

  local function Roster(size, subgroup)
    h:SetRaid(size, subgroup)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunDeferred()
  end

  local function RefreshParty()
    gf.RefreshHeaderLayout("party")
    h:RunDeferred()
  end

  Roster(4, {2, 4})
  assert(gf.headers.raid and not gf.headers.party, "raid should start with only its normal frame")
  party.smallRaidAsParty = true
  gf.RefreshHeaderLayout()
  h:RunDeferred()
  assert(not gf.headers.raid and Ordered(h, assert(gf.headers.party)) == "raid1,raid2,raid3,raid4",
    "the existing small-raid setting should use the whole roster")

  party.showPartyInRaid = true
  party.sortMode, party.playerFirstInRole, party.groupBorderEnabled = "ROLE", true, true
  RefreshParty()
  local header = assert(gf.headers.party)
  local border = assert(gf.anchors.party.MSUFGFGroupBorder)
  local _, edge = next(border)
  assert(edge and Visible(edge), "parallel party frames must show their border")
  assert(Ordered(h, header) == "player,party1,party2" and not header:GetAttribute("showRaid"),
    "parallel small raid must display only the subgroup via native party tokens")
  assert(Ordered(h, assert(gf.headers.raid)) == "raid1,raid2,raid3,raid4",
    "party-scoped refresh must restore the Raid layout for a small raid")
  assert(header:GetAttribute("nameList"), "Party role/player-first sort must remain available in raid")

  -- The native list is also a filter, so unreadable names must fall back to native membership.
  h.rosterNames = { party2 = "" }
  RefreshParty()
  assert(Ordered(h, header) == "player,party1,party2" and not header:GetAttribute("nameList"),
    "a partial sort list must not hide a subgroup member")
  h.rosterNames = nil
  RefreshParty()

  h:EnterCombat()
  h.rosterNames = { party2 = "Subgroup-Realm" }
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:LeaveCombat()
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Subgroup-Realm", 1, true),
    "a subgroup-only name event must also refresh the Party header alongside Raid")
  h.rosterNames = nil
  RefreshParty()

  h:EnterCombat()
  Roster(6, {5, 6})
  assert(gf.headers.party == header and not header:GetAttribute("showRaid"),
    "crossing the small-raid threshold in combat must retain party-token bindings")
  assert(#h.violations == 0, h.violations[1])
  h:LeaveCombat()
  h:RunDeferred()
  assert(Ordered(h, header) == "player,party1,party2"
    and h.env.UnitGUID("party1") == h.env.UnitGUID("raid5")
    and h.env.UnitGUID("party2") == h.env.UnitGUID("raid6"), "subgroup slots must rebind to the new members")
  assert(Ordered(h, assert(gf.headers.raid)) == "raid1,raid2,raid3,raid4,raid5,raid6",
    "raid layout must still include every member")

  Roster(6, {})
  assert(Ordered(h, header) == "player", "a singleton subgroup should show the player")
  party.showPlayer = false
  RefreshParty()
  assert(Ordered(h, header) == "" and gf.headers.raid and not Visible(edge),
    "an empty subgroup must hide its frames and border")

  party.showPlayer = true
  Roster(4, {2, 4})
  h:EnterCombat()
  party.showPartyInRaid = false
  RefreshParty()
  party.spacing = party.spacing + 1
  RefreshParty()
  assert(gf.headers.raid and not header:GetAttribute("showRaid"), "a combat refresh must defer protected visibility")
  h:LeaveCombat()
  h:RunDeferred()
  assert(not gf.headers.raid and Ordered(h, assert(gf.headers.party)) == "raid1,raid2,raid3,raid4",
    "deferred party-scoped refresh must restore the small-raid layout")
  Roster(6, {5, 6})
  assert(gf.headers.raid and not gf.headers.party, "turning off the setting must hide Party in a larger raid")
  assert(#h.violations == 0, h.violations[1])
end

local function NativeRaidFallbackAlongsideParty()
  local proxy, driver
  local function Tick(h)
    local value = h.env.UnitExists("raid6") and "show" or "hide"
    local state = "state-" .. driver
    h.RunSecure(function()
      if driver == "visibility" then
        proxy:SetShown(value == "show")
      elseif proxy:GetAttribute(state) ~= value then
        proxy:SetAttribute(state, value)
        local handler = assert(loadstring(proxy:GetAttribute("_onstate-" .. driver)))
        setfenv(handler, { self = proxy, newstate = value })
        handler()
      end
    end)
  end

  local h = Harness.New(root, flavor, { compiledChunks = compiledChunks, beforeBoot = function(world)
    local env = world.env
    local register = env.RegisterStateDriver
    env.RegisterStateDriver = function(frame, state, condition)
      if frame:GetName() ~= "MSUF_GF_BlizzardSmallRaidParent" then return register(frame, state, condition) end
      assert(condition == "[@raid6,exists] show; hide", "unexpected native raid proxy driver")
      proxy, driver = frame, state
      Tick(world)
    end
  end })
  local parent = h.env.CreateFrame("Frame", nil, h.env.UIParent)
  local container = h.env.CreateFrame("Frame", "CompactRaidFrameContainer", parent)
  h.env.CompactRaidFrameContainer = container
  local gf = h.GF
  local party, raid = gf.GetConf("party"), gf.GetConf("raid")
  party.enabled, party.smallRaidAsParty = true, true
  raid.enabled, raid.blizzardFallbackMode = false, "SHOW"
  h:SetRaid(4, {2, 4})
  gf.RefreshHeaderLayout()
  h:RunDeferred()
  assert(container:GetParent() == proxy and not Visible(container), "legacy small raid must hide the Blizzard raid frames")

  party.showPartyInRaid = true
  gf.RefreshHeaderLayout("party")
  h:RunDeferred()
  assert(not Visible(container), "addon refresh must defer the Blizzard visibility change to the native driver")
  Tick(h)
  assert(Visible(container) and Ordered(h, assert(gf.headers.party)) == "player,party1,party2" and not gf.headers.raid,
    "parallel Party mode must coexist with the configured Blizzard raid frames")
  parent:Hide()
  gf.ApplyBlizzardGroupFrameOwnership("addon-loaded:test")
  assert(Visible(container) and container:GetParent() == proxy, "reparenting must preserve effective visibility")
  parent:Show()
  gf.ApplyBlizzardGroupFrameOwnership("addon-loaded:test")
  assert(Visible(container) and container:GetParent() == parent, "visible native parent should regain the container")
  Tick(h)

  party.showPartyInRaid = false
  gf.RefreshHeaderLayout("party")
  h:RunDeferred()
  Tick(h)
  assert(not Visible(container), "legacy behavior must return when the parallel setting is off")
  assert(#h.violations == 0, h.violations[1])
end

SoloCombatPortraitInvite()
SoloInviteWorldTransition()
LateDungeonPartyName("playerFirstInRole")
LateDungeonPartyName("sortClassPriority")
PartyNameBurst("playerFirstInRole")
PartyNameBurst("sortClassPriority")
ResizedSoloParty(false)
ResizedSoloParty(true)
PartyAlongsideRaid()
NativeRaidFallbackAlongsideParty()

FrozenRoster("raid")
FrozenRoster("party")
FrozenRoster("raid", true)
do
  local h = World("none", false, "named")
  h.pendingName = "party2"
  h:SetRoster({ "player", "party1", "party2" })
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  local header = assert(h.GF.headers.party)
  assert(not header:GetAttribute("nameList"), "outdoor join must start on native sorting while its name is missing")
  h:EnterCombat()
  h.pendingName = nil
  h:Event("UNIT_NAME_UPDATE", "party2")
  h:LeaveCombat()
  h:RunDeferred()
  assert(header:GetAttribute("nameList"):find("Arrival", 1, true), "regen lost an outdoor name that arrived during combat")
  assert(#h.violations == 0, h.violations[1])
end
OpenWorldInvite("existing")
OpenWorldInvite("named")
OpenWorldInvite("solo")
OpenWorldRaidReinvite()
print("combat roster layout " .. flavor .. ": ok")
