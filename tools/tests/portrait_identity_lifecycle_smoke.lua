-- The real core OnShow path may consume the following target-change event.
-- Its portrait and elite paint must already describe the newly visible target.
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local state = { identity = "old", guid = "old-guid", classification = "elite", calls = 0 }
local installed = false
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local w = World.New(root, flavor, { beforeFile = function(_, env)
  if installed then return end
  installed = true
  local guid, isPlayer = env.UnitGUID, env.UnitIsPlayer
  env.UnitGUID = function(unit)
    if unit == "target" then return state.guid end
    return guid(unit)
  end
  env.UnitIsPlayer = function(unit)
    if unit == "target" then return false end
    return isPlayer(unit)
  end
  env.UnitIsVisible = function() return true end
  env.UnitClassification = function() return state.classification end
  env.SetPortraitTexture = function(texture, unit)
    state.calls = state.calls + 1
    texture.nativePortrait = state.identity
  end
end })
local UF, frame = w.UF, w.single
local db = UF.Config.GetDB()
db.target.showPortrait, db.target.portraitMode, db.target.portraitRender = true, "LEFT", "2D"
db.target.portraitShape, db.target.portraitBlizzardElite = "BLIZZARD", true
UF.Config.Refresh()
UF.ApplySpec(frame, UF.Config.GetSpec("target"), "MSUF_APPLY", true)
assert(frame.MSUFSpec.portrait.enabled and frame.MSUFSpec.portrait.blizzardElite)
local dragon = assert(frame.MSUFPortraitHolder.blizzElite)
assert(dragon:IsShown())
local onHide, onShow = assert(frame:GetScript("OnHide")), assert(frame:GetScript("OnShow"))
for _, guidKind in ipairs({ "plain", "secret", "missing" }) do
  state.identity, state.classification = "old-" .. guidKind, "elite"
  state.guid = guidKind == "plain" and "old-guid" or guidKind == "secret" and w.Secrets.New("string") or nil
  frame:GetScript("OnEvent")(frame, "PLAYER_TARGET_CHANGED")
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY_SOFT")
  UF.RunLeanIdentity(frame, "MSUF_UNIT_IDENTITY_SOFT")
  assert(frame.portrait.nativePortrait == "old-" .. guidKind and frame.portrait._msufPortraitKey ~= nil,
    "old portrait cache was not seeded")
  assert(dragon:IsShown(), "old elite dragon was not seeded")
  frame:Hide()
  onHide(frame)
  state.identity, state.classification = guidKind, "normal"
  state.guid = guidKind == "plain" and "new-guid" or guidKind == "secret" and w.Secrets.New("string") or nil
  state.calls = 0
  frame:Show()
  onShow(frame)
  assert(frame.portrait.nativePortrait == guidKind, "real core OnShow kept old " .. guidKind .. " portrait")
  assert(not dragon:IsShown(), "real core OnShow kept elite dragon")
  local before = state.calls
  frame:GetScript("OnEvent")(frame, "PLAYER_TARGET_CHANGED")
  if guidKind == "plain" then
    assert(state.calls == before, "plain GUID follower must still coalesce")
  end
  assert(frame.portrait.nativePortrait == guidKind)
  assert(not dragon:IsShown())
end
print("portrait_identity_lifecycle_smoke: ok (" .. flavor .. ", actual loaded core OnShow and target follower)")
