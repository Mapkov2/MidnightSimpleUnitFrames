-- Exercise the real Party/Raid color routes after an observed resurrection.
local root, flavor = assert(arg[1]), assert(arg[2])
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretGUID = Secrets.New("string")
local secretClass = Secrets.New("string")
local secretPlayer = Secrets.New("boolean")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local member, dead, misread, clock, class = nil, false, false, 10, "SHAMAN"
local classReads, guidReads, playerReads, healthPercent = 0, 0, 0, 15
local opaquePlayer, replacementName = false, nil
local guidReadable, nameMissing, rejectNativeClass = false, false, false
local secretClassPaints = 0
local colors = { SHAMAN = { r = 0, g = .44, b = .87 }, MAGE = { r = .24, g = .78, b = .9 } }
local h = Harness.New(root, flavor, { beforeBoot = function(world)
  local env = world.env
  env.type, env.issecretvalue = type, issecretvalue
  env.GetTime = function() return clock end
  env.UnitIsDeadOrGhost = function(unit) return unit == member and dead end
  env.UnitIsDead = env.UnitIsDeadOrGhost
  env.UnitIsGhost = function() return false end
  env.UnitIsPlayer = function(unit)
    if unit == member then
      playerReads = playerReads + 1
      if opaquePlayer then return secretPlayer end
    end
    return unit ~= member or not misread
  end
  local unitName = env.UnitName
  env.UnitName = function(unit)
    if unit == member and nameMissing then return nil end
    if unit == member and replacementName then return replacementName end
    return unitName(unit)
  end
  env.UnitHealthPercent = function(unit) return unit == member and (dead and 0 or healthPercent) or 100 end
  env.UnitHealth = function(unit) return unit == member and (dead and 0 or healthPercent * 10) or 1000 end
  env.UnitHealthMax = function() return 1000 end
  env.UnitReaction = function() return 5 end
  env.UnitClass = function(unit)
    if unit == member then classReads = classReads + 1 end
    return class, class
  end
  env.UnitGUID = function(unit)
    if unit == member then guidReads = guidReads + 1 end
    if unit == member and guidReadable then return "Player-0-001" end
    return secretGUID
  end
  env.RAID_CLASS_COLORS = colors
  env.C_ClassColor = { GetClassColor = function(token)
    assert(rawequal(token, secretClass), "secret class did not reach the native resolver intact")
    if rejectNativeClass then
      rejectNativeClass = false
      return nil
    end
    secretClassPaints = secretClassPaints + 1
    return { GetRGB = function() return 0, .44, .87 end }
  end }
end })
local function CheckColor(frame, want, label)
  local bar = frame.hpBar
  local epsilon = 1e-6
  assert(bar._msufStatusR ~= nil and math.abs(bar._msufStatusR - want.r) < epsilon
    and math.abs(bar._msufStatusG - want.g) < epsilon
    and math.abs(bar._msufStatusB - want.b) < epsilon,
    ("%s: expected %.2f %.2f %.2f, got %s %s %s"):format(label, want.r, want.g, want.b,
      tostring(bar._msufStatusR), tostring(bar._msufStatusG), tostring(bar._msufStatusB)))
end
local grey = {r=.35,g=.35,b=.35}
local green = {r=0,g=1,b=0}
local deadBlack = {r=.28,g=.28,b=.28}
for _, scope in ipairs({ "party", "raid" }) do
  member = scope .. "1"
  dead, misread, class, replacementName = false, false, "SHAMAN", nil
  local conf = h.GF.GetConf(scope)
  conf.enabled = true
  conf.gfBarMode = "class"
  h.GF.RefreshHeaderLayout()
  if scope == "raid" then h:SetRaid(5) else h:SetRoster({ "player", "party1" }) end
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunTimers()
  local frame = assert(h.GF.FrameForUnit(member), member)
  local function Fire(event)
    frame.scripts.OnEvent(frame, event, member)
  end
  local function Kill()
    dead = true
    Fire("UNIT_FLAGS")
    CheckColor(frame, grey, member .. " dead")
  end
  local function Revive(event)
    dead = false
    Fire(event or "UNIT_HEALTH")
  end
  CheckColor(frame, colors.SHAMAN, member .. " class setup")
  local function CheckSteadyHealth(label)
    local classes, guids, players = classReads, guidReads, playerReads
    for _ = 1, 50 do Fire("UNIT_HEALTH") end
    assert(classReads == classes and guidReads == guids and playerReads == players,
      member .. " " .. label .. " health ticks made identity reads")
  end
  local function CheckRecovery(pct, label)
    misread, healthPercent = false, pct
    local bar = frame.hpBar
    local nativeSetValue, actual = bar.SetValue
    bar.SetValue = function(self, value, ...)
      actual = value
      return nativeSetValue(self, value, ...)
    end
    Fire("UNIT_HEALTH")
    bar.SetValue = nativeSetValue
    -- Percent clients write 0..100 and absolute clients write 0..1000 here.
    assert(actual == pct or actual == pct * 10, member .. " " .. label .. " health fill " .. tostring(actual))
    CheckColor(frame, colors[class], member .. " " .. label .. " first positive health event")
    CheckSteadyHealth(label)
  end
  CheckSteadyHealth("normal")

  Kill()
  Revive()
  CheckColor(frame, colors.SHAMAN, member .. " normal rez")
  misread = true
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, colors.SHAMAN, member .. " post-rez false on name update")
  for _ = 1, 10 do Fire("UNIT_HEALTH") end
  CheckColor(frame, colors.SHAMAN, member .. " post-rez HP updates")
  misread = false
  Fire("UNIT_FLAGS")

  Kill()
  misread = true
  Revive("UNIT_FLAGS")
  CheckColor(frame, colors.SHAMAN, member .. " false at first alive event")
  class, opaquePlayer = secretClass, true
  local secretPaints = secretClassPaints
  local stopWatching = Secrets.Watch(
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", { strict = true })
  Fire("UNIT_NAME_UPDATE")
  local secretViolations = stopWatching()
  assert(#secretViolations == 0, table.concat(secretViolations, "\n"))
  assert(secretClassPaints == secretPaints + 1, member .. " secret class skipped the native resolver")
  opaquePlayer = false
  local originalSchedule, retry = h.core.Scheduler.RunNextFrame
  h.core.Scheduler.RunNextFrame = function(fn)
    assert(retry == nil, member .. " queued a duplicate retry")
    retry = fn
  end
  class = nil
  Fire("UNIT_NAME_UPDATE")
  Fire("UNIT_NAME_UPDATE")
  h.core.Scheduler.RunNextFrame = originalSchedule
  CheckColor(frame, deadBlack, member .. " unresolved class")
  class = "MAGE"
  assert(retry, member .. " missing one-shot retry")
  retry()
  CheckColor(frame, colors.MAGE, member .. " retry used the current class")

  clock = clock + 2
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, green, member .. " expired rez window")
  CheckRecovery(78, "late identity after rez window")

  Kill()
  class = nil
  Revive("UNIT_FLAGS")
  class = "SHAMAN"
  CheckRecovery(81, "known player with late class")

  Kill()
  class, opaquePlayer = nil, true
  Revive("UNIT_FLAGS")
  Fire("UNIT_NAME_UPDATE")
  class, opaquePlayer, healthPercent = secretClass, false, 83
  local beforeOpaqueRecovery = secretClassPaints
  local stopRecoveryWatch = Secrets.Watch(
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", { strict = true })
  rejectNativeClass = true
  Fire("UNIT_HEALTH")
  assert(not rejectNativeClass and secretClassPaints == beforeOpaqueRecovery, member .. " native class refused once")
  Fire("UNIT_HEALTH")
  local recoveryViolations = stopRecoveryWatch()
  assert(#recoveryViolations == 0, table.concat(recoveryViolations, "\n"))
  assert(secretClassPaints == beforeOpaqueRecovery + 1, member .. " native class repainted on next health event")
  CheckSteadyHealth("recovered native class")
  class = "SHAMAN"
  Fire("UNIT_NAME_UPDATE")

  misread, class = false, "SHAMAN"
  Fire("UNIT_FLAGS")
  Kill()
  Revive()
  misread, class = true, "MAGE"
  h:Event("GROUP_ROSTER_UPDATE")
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, green, member .. " roster update expires provisional class")
  CheckRecovery(100, "current class after same-token roster update")
  misread, class = false, "SHAMAN"
  h:RunTimers()
  frame = assert(h.GF.FrameForUnit(member))
  Fire("UNIT_FLAGS")

  for _, binding in ipairs({ "unavailable identity", "GUID to name" }) do
    guidReadable = binding == "GUID to name"
    Kill()
    Revive()
    guidReadable, nameMissing, misread = false, binding == "unavailable identity", true
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunDeferred()
    frame = assert(h.GF.FrameForUnit(member))
    for _ = 1, 3 do Fire("UNIT_HEALTH") end
    CheckColor(frame, green, member .. " provisional class expired on roster settle")
    nameMissing = false
    CheckRecovery(binding == "unavailable identity" and 71 or 73, binding .. " on the same settled occupant")
  end

  -- A complete combat death and rez can leave reaction green until combat ends.
  -- Even after UnitIsPlayer recovers, positive combat HP must keep its old cost.
  h:EnterCombat()
  Kill()
  misread = true
  Revive("UNIT_FLAGS")
  local reads = classReads
  Fire("UNIT_NAME_UPDATE")
  assert(classReads == reads, member .. " combat workaround queried class")
  CheckColor(frame, green, member .. " no extra rez color in combat")
  misread, healthPercent = false, 79
  CheckSteadyHealth("combat-only rez")
  CheckColor(frame, green, member .. " combat HP did not repaint")
  misread = true
  h:LeaveCombat()
  h:RunDeferred()
  CheckRecovery(82, "first out-of-combat HP after combat-only rez")

  -- A full-health member may never generate another HP event after combat.
  h:EnterCombat()
  Kill()
  misread, healthPercent = true, 100
  Revive("UNIT_FLAGS")
  Fire("UNIT_NAME_UPDATE")
  misread = false
  Fire("UNIT_HEALTH")
  CheckColor(frame, green, member .. " full health before combat ends")
  h:LeaveCombat()
  h:RunDeferred()
  CheckColor(frame, colors[class], member .. " full health on regen without another HP event")

  -- An unconfirmed OOC read is already pending before the pull. The combat
  -- event handler must go dormant, then resume on the first valid OOC HP tick.
  Kill()
  Revive()
  clock = clock + 2
  misread = true
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, green, member .. " late out-of-combat read before pull")
  h:EnterCombat()
  CheckSteadyHealth("pre-pull pending and still unresolved")
  misread, healthPercent = false, 87
  CheckSteadyHealth("pre-pull pending with readable combat identity")
  CheckColor(frame, green, member .. " pre-pull watch stayed dormant in combat")
  misread = true
  h:LeaveCombat()
  h:RunDeferred()
  CheckRecovery(88, "first out-of-combat HP after pending case crossed pull")

  -- One roster event can replace a member in place, without a vacant token.
  Kill()
  Revive()
  misread, class, replacementName = true, "MAGE", "Friendly Companion"
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  frame = assert(h.GF.FrameForUnit(member))
  Fire("UNIT_HEALTH")
  CheckColor(frame, green, member .. " same-token replacement NPC reaction")
  CheckSteadyHealth("settled same-token replacement NPC")
  misread, class, replacementName = false, "SHAMAN", nil
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunDeferred()
  frame = assert(h.GF.FrameForUnit(member))
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, colors.SHAMAN, member .. " next player has its own class")

  -- The old occupant dies and leaves. A friendly NPC with a readable class
  -- then takes the same token. Its health ticks must keep its own reaction.
  Kill()
  h:SetRoster({ "player" })
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunTimers()
  dead, misread, class = false, true, "MAGE"
  if scope == "raid" then h:SetRaid(5) else h:SetRoster({ "player", "party1" }) end
  h:Event("GROUP_ROSTER_UPDATE")
  h:RunTimers()
  frame = assert(h.GF.FrameForUnit(member))
  Fire("UNIT_NAME_UPDATE")
  Fire("UNIT_HEALTH")
  CheckColor(frame, green, member .. " replacement NPC reaction")
  CheckSteadyHealth("replacement NPC")
end
print("group rez class color " .. flavor .. ": ok")
