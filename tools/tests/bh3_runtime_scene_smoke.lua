local root = assert(arg[1])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local function visible(frame)
  if not frame then return false end
  while frame do if not frame.shown then return false end; frame=frame.parent end
  return true
end
local h = Harness.New(root, "Mainline", { beforeBoot = function(h)
  h.env.Enum.ClientSceneType = { MinigameSceneType = 1 }
  h.env.C_ClientScene = { IsSceneTypeActive = function() return h.scene == true end }
end })
local gf = h.GF
gf.EnsureDB()
local party = gf.GetConf("party")
party.enabled, party.showPlayer, party.hideInClientScene = true, true, true
h:SetRoster({"player", "party1"})
gf.RefreshHeaderLayout(); h:RunTimers()
assert(visible(gf.FrameForUnit("party1")), "party absent before scene")
local runtimeFrame
for _, frame in ipairs(h.widgets.frames) do
  if frame.events and frame.events.CLIENT_SCENE_OPENED then runtimeFrame = frame end
end
assert(runtimeFrame, "scene listener missing")
local registers, unregisters = 0, 0
local register, unregister = runtimeFrame.RegisterEvent, runtimeFrame.UnregisterAllEvents
runtimeFrame.RegisterEvent = function(self, ...) registers = registers + 1; return register(self, ...) end
runtimeFrame.UnregisterAllEvents = function(self, ...) unregisters = unregisters + 1; return unregister(self, ...) end
for _ = 1, 100 do gf.RefreshHeaderLayout() end
assert(registers == 0 and unregisters == 0, "unchanged layout rebuilt runtime subscriptions")
h.scene=true; h:Event("CLIENT_SCENE_OPENED"); h:RunTimers()
assert(not visible(gf.FrameForUnit("party1")), "client scene did not hide group")
h.scene=false; h:Event("CLIENT_SCENE_CLOSED"); h:RunTimers()
assert(visible(gf.FrameForUnit("party1")), "client scene close did not restore group")
h:EnterCombat(); h.scene=true; h:Event("CLIENT_SCENE_OPENED");h:RunTimers()
assert(#h.violations == 0, "scene wrote protected frames in combat")
h:LeaveCombat(); h:RunTimers()
assert(not visible(gf.FrameForUnit("party1")), "deferred scene hide missing")
h.scene=false;h:Event("CLIENT_SCENE_CLOSED");h:RunTimers()
party.hideInClientScene=false;gf.RefreshVisuals("party",gf.DIRTY_VISUAL)
h.scene=true;h:Event("CLIENT_SCENE_OPENED");h:RunTimers()
assert(visible(gf.FrameForUnit("party1")), "scene setting false ignored")
print("PASS client scene events, setting, restore and combat deferral")
