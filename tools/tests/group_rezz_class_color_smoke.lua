-- Exercise the real Party/Raid color routes after an observed resurrection.
local root, flavor = assert(arg[1]), assert(arg[2])
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secretGUID = Secrets.New("string")
local secretClass = Secrets.New("string")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local member, dead, misread, clock, class = nil, false, false, 10, "SHAMAN"
local classReads, guidReads = 0, 0
local secretClassPaints = 0
local colors = { SHAMAN = { r = 0, g = .44, b = .87 }, MAGE = { r = .24, g = .78, b = .9 } }
local h = Harness.New(root, flavor, { beforeBoot = function(world)
  local env = world.env
  env.type, env.issecretvalue = type, issecretvalue
  env.GetTime = function() return clock end
  env.UnitIsDeadOrGhost = function(unit) return unit == member and dead end
  env.UnitIsDead = env.UnitIsDeadOrGhost
  env.UnitIsGhost = function() return false end
  env.UnitIsPlayer = function(unit) return unit ~= member or not misread end
  env.UnitHealthPercent = function(unit) return unit == member and (dead and 0 or 15) or 100 end
  env.UnitHealth = function(unit) return unit == member and (dead and 0 or 150) or 1000 end
  env.UnitHealthMax = function() return 1000 end
  env.UnitReaction = function() return 5 end
  env.UnitClass = function(unit)
    if unit == member then classReads = classReads + 1 end
    return class, class
  end
  env.UnitGUID = function(unit)
    if unit == member then guidReads = guidReads + 1 end
    return secretGUID
  end
  env.RAID_CLASS_COLORS = colors
  env.C_ClassColor = { GetClassColor = function(token)
    assert(rawequal(token, secretClass), "secret class did not reach the native resolver intact")
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
  dead, misread, class = false, false, "SHAMAN"
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
  local classes, guids = classReads, guidReads
  for _ = 1, 50 do Fire("UNIT_HEALTH") end
  assert(classReads == classes and guidReads == guids, member .. " normal health ticks made identity reads")

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
  class = secretClass
  local secretPaints = secretClassPaints
  local stopWatching = Secrets.Watch(
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua", { strict = true })
  Fire("UNIT_NAME_UPDATE")
  local secretViolations = stopWatching()
  assert(#secretViolations == 0, table.concat(secretViolations, "\n"))
  assert(secretClassPaints == secretPaints + 1, member .. " secret class skipped the native resolver")
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

  misread, class = false, "SHAMAN"
  Fire("UNIT_FLAGS")
  Kill()
  Revive()
  misread, class = true, "MAGE"
  h:Event("GROUP_ROSTER_UPDATE")
  Fire("UNIT_NAME_UPDATE")
  CheckColor(frame, green, member .. " same-token roster update expires rez handling")
  misread, class = false, "SHAMAN"
  h:RunTimers()
  frame = assert(h.GF.FrameForUnit(member))
  Fire("UNIT_FLAGS")

  Kill()
  h:EnterCombat()
  misread = true
  Revive("UNIT_FLAGS")
  CheckColor(frame, green, member .. " no additional rez color in combat")
  local reads = classReads
  Fire("UNIT_NAME_UPDATE")
  assert(classReads == reads, member .. " combat workaround queried class")
  misread = false
  Fire("UNIT_FLAGS")
  CheckColor(frame, colors.SHAMAN, member .. " normal combat update restores class")
  h:LeaveCombat()
  h:RunTimers()
end
print("group rez class color " .. flavor .. ": ok")
