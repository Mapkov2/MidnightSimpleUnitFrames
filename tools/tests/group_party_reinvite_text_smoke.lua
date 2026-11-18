-- Exercise a real secure party button through group leave and later re-use.
local root, flavor = assert(arg[1]), assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local compiledChunks = {}

local function CheckGroup(location, joinInCombat, equalShieldAtBind)
  local name, hp, mana, role = "First Member", 999, 717, "DAMAGER"
  local delayed = location == "none" and joinInCombat and (flavor == "Mainline" or flavor == "Forever")
  local ready, leaderLocation = true, location
  local h = Harness.New(root, flavor, { compiledChunks = compiledChunks, beforeBoot = function(world)
    local env = world.env
    env.IsInInstance = function() return location ~= "none", location end
    env.GetInstanceInfo = function() return "Area", location, location == "none" and 0 or 1 end
    -- IsInInstance describes the local character. The inviting party leader
    -- can be in another zone, outside visibility and party range.
    env.UnitIsGroupLeader = function(unit) return unit == "party1" and env.UnitExists(unit) end
    env.UnitIsVisible = function(unit) return env.UnitExists(unit) and (unit ~= "party1" or location == leaderLocation) end
    env.UnitInRange = function(unit) return env.UnitIsVisible(unit), true end
    local baseName = env.UnitName
    env.UnitName = function(unit)
      if unit == "party1" then return name end
      return baseName(unit)
    end
    env.UnitHealth = function() if ready then return hp end end
    env.UnitHealthMax = function() if ready then return hp end end
    env.UnitHealthPercent = function() if ready then return 100 end end
    env.UnitPower = function() if ready then return mana end end
    local powerMax = env.UnitPowerMax
    env.UnitPowerMax = function(unit, token)
      if unit ~= "party1" then return powerMax(unit, token) end
      if ready then return 2000 end
    end
    if delayed then env.UnitGetTotalAbsorbs = function() if ready or equalShieldAtBind then return 388 end end end
    env.UnitPowerType = function() return 0, "MANA" end
    env.UnitGroupRolesAssigned = function() return role end
    env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.BreakUpLargeNumbers = tostring, tostring, tostring
  end })
  local conf = h.GF.GetConf("party")
  conf.enabled, conf.showName, conf.showHPText = true, true, true
  conf.powerBarEnabled, conf.powerHeight, conf.powerShowDamager = true, 6, true
  conf.powerShowTank = false
  h.GF.SetPowerTextEnabled("party", true)
  conf.textLeft, conf.textCenter, conf.textRight = "PERCENT", "NONE", "CURRENT"
  if delayed then conf.textCenter = "ABSORB" end
  conf.hpTextLeftHidePercentSymbol = true
  conf.powerTextLeft, conf.powerTextCenter, conf.powerTextRight = "CURRENT", "NONE", "NONE"
  h.GF.RefreshAll()
  h:Event("PLAYER_ENTERING_WORLD")
  h:RunDeferred()

  local function Roster(units)
    h:SetRoster(units)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunDeferred()
  end
  local function CheckTexts(frame, step)
    assert(frame and frame:IsShown(), step .. " missing visible party frame")
    local function Check(key, expected)
      local region = frame[key]
      local value = region and region:GetText()
      assert(tostring(value) == expected, step .. " " .. key .. " expected " .. expected .. ", got " .. tostring(value))
      assert(region:IsShown(), step .. " " .. key .. " contains " .. expected .. " but is hidden")
    end
    Check("nameText", name)
    Check("hpTextLeft", "100")
    Check("hpTextRight", tostring(hp))
    if role == "TANK" then
      assert(not frame.powerTextLeft or not frame.powerTextLeft:IsShown(), step .. " ignored hidden tank power")
    else
      Check("powerTextLeft", tostring(mana))
    end
    if delayed then
      Check("hpTextCenter", "388")
    else
      assert(not frame.hpTextCenter or not frame.hpTextCenter:IsShown(), step .. " enabled unused HP slot")
    end
    assert(not frame.powerTextRight or not frame.powerTextRight:IsShown(), step .. " enabled unused power slot")
  end
  Roster({ "player", "party1" })
  local first = assert(h.GF.FrameForUnit("party1"))
  CheckTexts(first, "first " .. location)
  local function QueueBothTextUpdates(frame)
    frame.scripts.OnEvent(frame, "UNIT_HEALTH", "party1")
    frame.scripts.OnEvent(frame, "UNIT_POWER_UPDATE", "party1", "MANA")
    assert(frame._msufTextDirtyMask == 3, "health and power updates did not both enqueue")
  end
  if delayed then QueueBothTextUpdates(first) end
  Roster({ "player" })
  if delayed then assert(first._msufTextDirtyMask == nil, "retirement kept queued text updates") end
  assert(not h.GF.FrameForUnit("party1"), "leave retained indexed unit")
  -- Observe native visibility writes on the actual reused numeric regions.
  -- A name or value refresh elsewhere on the frame is free to run normally.
  local writes, measuredSlots = 0, {}
  local unexpectedShows = 0
  for _, field in ipairs({ "hpTextLeft", "hpTextCenter", "hpTextRight", "powerTextLeft", "powerTextRight", "powerTextCenter" }) do
    local fs = first[field]
    if fs then
      local configured = field == "hpTextLeft" or field == "hpTextRight" or field == "powerTextLeft" or (delayed and field == "hpTextCenter")
      if configured then measuredSlots[#measuredSlots + 1] = fs end
      local function CountShow()
        writes = writes + 1
        if not configured then unexpectedShows = unexpectedShows + 1 end
      end
      local setShown, show = fs.SetShown, fs.Show
      fs.SetShown = function(self, visible)
        if visible then CountShow() end
        return setShown(self, visible)
      end
      fs.Show = function(self)
        CountShow()
        return show(self)
      end
    end
  end
  local function HiddenBeforeEligibility()
    for _, fs in ipairs(measuredSlots) do if not fs:IsShown() then return true end end
    return false
  end
  local function CheckNoRepair(phase)
    assert(writes == 0, phase .. " performed " .. writes .. " numeric visibility writes")
  end
  local dungeonCombatWrites = 0
  if location == "party" and joinInCombat then
    for _, field in ipairs({"nameText", "hpTextLeft", "hpTextRight", "powerTextLeft"}) do
      local region = assert(first[field])
      for _, method in ipairs({"Show", "Hide", "SetShown", "SetText", "SetFormattedText"}) do
        local original = region[method]
        if original then
          region[method] = function(self, ...)
            if h.env.InCombatLockdown() then dungeonCombatWrites = dungeonCombatWrites + 1 end
            return original(self, ...)
          end
        end
      end
    end
  end
  local function CheckUnchangedRoster()
    local previous = writes
    Roster({ "player", "party1" })
    Roster({ "player", "party1" })
    assert(writes == previous, "repeat roster events showed numeric regions again")
    assert(unexpectedShows == 0, "binding showed a disabled numeric slot")
  end
  local hiddenBeforeEligibility = HiddenBeforeEligibility()
  name = "Second Member"
  leaderLocation = location == "none" and "party" or "none"
  if delayed then
    ready = false
  else
    hp, mana = 1884, 1762
  end
  if joinInCombat then
    h:EnterCombat()
    -- The same combat spans a loading screen before the member joins.
    h:Event("PLAYER_LEAVING_WORLD")
    h:Event("PLAYER_ENTERING_WORLD", false, false)
    h:RunDeferred()
  end
  if delayed then
    local function CheckNoOldText()
      local parent = first
      while parent and parent ~= h.env.UIParent do
        if not parent:IsShown() then return end
        parent = parent:GetParent()
      end
      for field, oldValue in pairs({ hpTextRight = hp, powerTextLeft = mana, hpTextCenter = 388 }) do
        local region = first[field]
        if field ~= "hpTextCenter" or not equalShieldAtBind then
          assert(not region:IsShown() or tostring(region:GetText()) ~= tostring(oldValue), field .. " exposed a previous member")
        end
      end
    end
    h:SetRoster({ "player", "party1" })
    h:Event("GROUP_ROSTER_UPDATE")
    CheckNoOldText()
    h:RunDeferred(nil, nil, CheckNoOldText)
    assert(h.GF.FrameForUnit("party1") == first and first:IsShown() and first.nameText:GetText() == name,
      "outdoor re-invite must bind the new occupant before regen")
    assert(not HiddenBeforeEligibility() and writes > 0, "outdoor combat did not restore configured numeric slots")
    if equalShieldAtBind then
      assert(tostring(first.hpTextCenter:GetText()) == "388", "new occupant's equal shield was lost at binding")
    end
    CheckUnchangedRoster()
    -- Equal values from a different occupant must render after clearing the old ones.
    ready = true
    for _, event in ipairs({ "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_ABSORB_AMOUNT_CHANGED" }) do
      h:Event(event, "party1")
    end
    h:Event("UNIT_HEALTH", "party1")
    h:Event("UNIT_POWER_UPDATE", "party1", "MANA")
    h:RunDeferred()
    -- The harness drains timers and next-frame work. Advance repeating tickers
    -- separately to model the client's regular value-text update.
    h.widgets:AdvanceTime(.25)
    for _, ticker in ipairs(h.widgets.tickers) do
      if ticker.delay == .25 and not ticker.cancelled then ticker.callback() end
    end
    CheckTexts(first, "outdoor late values before regen")
    CheckUnchangedRoster()
    h:LeaveCombat()
    h:RunDeferred()
  else
    Roster({ "player", "party1" })
    if joinInCombat then
      if location == "none" then
        CheckTexts(first, "outdoor re-invite before regen")
        CheckUnchangedRoster()
      else
        CheckNoRepair(location .. " combat")
        assert(not h.GF.FrameForUnit("party1") and dungeonCombatWrites == 0,
          "dungeon combat repainted or installed the retired party slot before regen")
      end
      hiddenBeforeEligibility = HiddenBeforeEligibility()
      h:LeaveCombat()
      h:RunDeferred()
    end
  end
  local replacement = assert(h.GF.FrameForUnit("party1"))
  assert(replacement == first, "fixture did not reuse original party button")
  assert(h.env.UnitIsGroupLeader("party1") and not h.env.UnitIsVisible("party1"), "expected a remote inviting leader")
  CheckTexts(replacement, "rejoin " .. location .. (joinInCombat and " after combat" or ""))
  if hiddenBeforeEligibility then
    assert(writes > 0, "previously hidden slots were never shown on the current member")
  end
  if location == "party" then CheckUnchangedRoster() end
  if delayed then
    QueueBothTextUpdates(replacement)
    replacement:DisableElement("HealthText")
    replacement:DisableElement("PowerText")
    assert(replacement._msufTextDirtyMask == nil and not replacement.hpTextRight:IsShown()
      and not replacement.hpTextCenter:IsShown() and not replacement.powerTextLeft:IsShown(), "direct disable left active text")
  end
  if location == "none" and not joinInCombat then
    for _, newRole in ipairs({ "TANK", "DAMAGER" }) do
      Roster({ "player" })
      role = newRole
      Roster({ "player", "party1" })
      local rebound = assert(h.GF.FrameForUnit("party1"))
      assert(rebound == first, "role change did not reuse the party button")
      CheckTexts(rebound, newRole .. " on reused party button")
      if newRole == "TANK" then
        -- Rebuild the saved layout while this role has no power text.
        -- The next damage dealer must pick up the new value on rebind.
        conf.nameFontSize = (conf.nameFontSize or 12) + 1
        h.GF.RefreshAll()
        h:RunDeferred()
        mana = 123
      end
    end
    -- Walk through the portal to the inviter. A normal OOC world-entry pass
    -- must show the same group with current values before another roster event.
    location, hp, mana = leaderLocation, 1520, 413
    h:Event("PLAYER_ENTERING_WORLD", false, false)
    h:RunDeferred()
    assert(h.env.UnitIsVisible("party1"), "expected the leader in the same dungeon after zoning")
    CheckTexts(h.GF.FrameForUnit("party1"), "enter the inviting leader's dungeon out of combat")
  end
end

CheckGroup("none", false)
CheckGroup("party", false)
CheckGroup("none", true)
if flavor == "Mainline" or flavor == "Forever" then CheckGroup("none", true, true) end
CheckGroup("party", true)
print("party re-invite texts " .. flavor .. ": ok")
