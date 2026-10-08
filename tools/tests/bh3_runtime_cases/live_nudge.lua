-- Probe: arrow-key nudge of a LIVE Party block in MSUF Edit Mode.
-- Real Group EM2 login handler + real State.Enter; the party is live (in group).
local root = assert(arg[1])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline")
world.env.MAX_BOSS_FRAMES = 5
world.env.IsInGroup = function() return true end
world.env.IsInRaid = function() return false end
world.env.GetNumGroupMembers = function() return 3 end
world.env.GetNumSubgroupMembers = function() return 2 end
world.env.UnitExists = function(u) return u == "player" or u == "party1" or u == "party2" end
world:Boot()
assert(not world:FirstFailure(), "boot failed")
local env, gf = world.env, world.core.GF
env.WIDTH, env.HEIGHT = "Width", "Height"
env.PET, env.TARGET, env.HEALER, env.BOSS = "Pet", "Target", "Healer", "Boss"
-- In a 3-player party.
env.IsInGroup = function() return true end
env.IsInRaid = function() return false end
env.GetNumGroupMembers = function() return 3 end
env.GetNumSubgroupMembers = function() return 2 end
env.UnitExists = function(u) return u == "player" or u == "party1" or u == "party2" end
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
gf.EnsureDB()
local party = gf.GetConf("party")
party.enabled = true
gf.InvalidateCompiledSpecs("party")
if gf.RebuildAll then gf.RebuildAll() end
world.widgets:RunTimers(1000)
for _, frame in ipairs(world.widgets.frames) do
  local cb = frame:GetScript("OnEvent")
  if frame:IsEventRegistered("PLAYER_LOGIN") and cb and debug.getinfo(cb, "S").source:find("Group_EM2", 1, true) then
    cb(frame, "PLAYER_LOGIN")
  end
end
world.widgets:RunTimers(1000)
assert(env.MSUF_EM2.State.Enter("player"), "edit entry failed")
world.widgets:RunTimers(1000)

local anchor = gf.anchors and gf.anchors.party
print("live party anchor exists:", anchor ~= nil, "shown:", anchor and anchor:IsShown())
local function AnchorX()
  if not anchor then return nil end
  local _, _, _, x, y = anchor:GetPoint(1)
  return x, y
end
local x0, y0 = AnchorX()
local cx0 = party.offsetX
print("before: conf.offsetX", cx0, "anchor x", x0)
local ok = env.MSUF_GF_EM2_NudgePreview("party", 10, 0)
world.widgets:RunTimers(1000)
local x1, y1 = AnchorX()
print("nudge returned:", ok)
print("after : conf.offsetX", party.offsetX, "anchor x", x1)
print("expected: anchor x moves with conf (+10); observed delta:", (x1 or 0) - (x0 or 0))
-- For comparison, the popup path (GroupPopup.Apply -> RefreshAfterPopupApply -> RefreshGeometry)
if gf.RefreshGeometry then gf.RefreshGeometry("party") end
world.widgets:RunTimers(1000)
local x2 = AnchorX()
print("after an explicit RefreshGeometry: anchor x", x2)

assert(ok and x1 - x0 == 10, "live nudge failed to move runtime anchor")
