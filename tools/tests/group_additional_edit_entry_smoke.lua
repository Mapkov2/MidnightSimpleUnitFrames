-- Native Edit Mode entry must show enabled Raid pets even while solo and without a pet.
local root = assert(arg[1], "usage: group_additional_edit_entry_smoke.lua <root>")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline")
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
assert(not world:FirstFailure(), "Mainline graph failed to boot")
local env, gf = world.env, world.core.GF
env.WIDTH, env.HEIGHT = "Width", "Height"
env.PET, env.TARGET, env.HEALER, env.BOSS, env.MAX_BOSS_FRAMES = "Pet", "Target", "Healer", "Boss", 5
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
gf.EnsureDB()
for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
    local conf = gf.GetConf(kind)
    conf.enabled, conf.petsEnabled = true, kind == "raid"
    conf.petsX, conf.petsY, conf.petsWidth, conf.petsHeight, conf.petsColumns = 0, -220, 100, 24, 1
end
local raid = gf.GetConf("raid")
raid.gfBarMode, raid.healthCustomR, raid.healthCustomG, raid.healthCustomB = "custom", .21, .43, .65
raid.bgR, raid.bgG, raid.bgB, raid.hpBgAlpha = .11, .22, .33, .66
raid.fontOverride, raid.nameColorMode = true, "CUSTOM"
raid.nameColorR, raid.nameColorG, raid.nameColorB = .31, .52, .73
gf.InvalidateCompiledSpecs("raid")
-- Dispatch the real Group EM2 login handler; unrelated login systems are not this test's scope.
for _, frame in ipairs(world.widgets.frames) do
    local callback = frame:GetScript("OnEvent")
    if frame:IsEventRegistered("PLAYER_LOGIN") and callback
        and debug.getinfo(callback, "S").source:find("Group_EM2", 1, true) then
        callback(frame, "PLAYER_LOGIN")
    end
end
world.widgets:RunTimers(1000)
assert(env.MSUF_EM2.Registry.Get("gf_raid"), "Raid mover was not registered")
assert(env.MSUF_EM2.State.Enter("player"), "actual native edit entry failed")
world.widgets:RunTimers(1000)
assert(env.MSUF_UnitEditModeActive == true, "compatibility active flag missing")
world.core.MSUF2.SyncGFPagePreviewForKey(nil, false, true)
world.widgets:RunTimers(1000)
local sample
for _, frame in ipairs(world.widgets.frames) do
    if rawget(frame, "buttons") and #frame.buttons == 30 then sample = frame end
end
assert(sample and sample:IsShown(), "Raid pet samples vanished after actual edit entry/menu cleanup")
assert(sample:GetWidth() == 100 and sample:GetHeight() == 778, "Raid pet sample bounds changed")
local point, relative, relativePoint, x, y = sample:GetPoint()
assert(point == "CENTER" and relative == env.UIParent and relativePoint == "CENTER" and x == 0 and y == -220, "screen sample location incorrect")
local ancestor = sample:GetParent()
while ancestor and ancestor ~= env.UIParent do
    assert(ancestor:IsShown(), "sample ancestor is hidden")
    ancestor = ancestor:GetParent()
end
local bar, name = sample.buttons[1].Health, sample.buttons[1].Name
assert(bar.color[1] == .21 and bar.color[2] == .43 and bar.color[3] == .65, "sample ignored Group health colors")
assert(name.textColor[1] == .31 and name.textColor[2] == .52 and name.textColor[3] == .73, "sample ignored Group name colors")
local external = env.MSUF_EM2.ExternalElements
local key = "external:msuf_group_extras:raid_pets"
local mover = assert(env.MSUF_EM2.Registry.Get(key), "independent pet mover missing")
assert(mover.getFrame() == sample and mover.isEnabled(), "mover does not own the Pet block")
local overlay = assert(env.MSUF_EM2.Movers.Get(key), "native Pet mover overlay missing")
assert(overlay:IsShown(), "native Pet mover overlay hidden")
assert(env.MSUF_EM2.Registry.Get("external:msuf_group_extras:party_targets"), "Party target mover missing")
assert(not env.MSUF_EM2.Registry.Get("external:msuf_group_extras:raid_targets"), "unsupported Raid target mover registered")
local state = assert(external.CaptureState(key))
assert(external.ApplyMove(key, state, 35, -17, nil, nil, "commit"), "pet drag adapter rejected")
assert(raid.petsX == 35 and raid.petsY == -237, "pet drag saved wrong configuration")
assert(external.Nudge(key, 1, 2), "pet nudge rejected")
assert(raid.petsX == 36 and raid.petsY == -235, "pet nudge saved wrong coordinates")
local dimensions = mover.externalRecord.extraControls
assert(dimensions[1].set(130) and dimensions[2].set(31), "pet numeric resize rejected")
assert(raid.petsWidth == 130 and raid.petsHeight == 31 and sample:GetWidth() == 130, "resize failed to refresh sample")
-- Configuration replacement models a profile switch: callbacks must resolve the current table.
local old = raid
local replacement = {}; for k, v in pairs(old) do replacement[k] = v end
env.MSUF_DB.gf_raid = replacement
gf.InvalidateConfCache(); gf.EnsureDB()
assert(external.ApplyMove(key, external.CaptureState(key), 3, 4, nil, nil, "commit"))
assert(replacement.petsX == 39 and old.petsX == 36, "mover retained old profile configuration")
local compact = gf.GetAdditionalPreviewSpec("raid", "pets", 30, { sampleCount = 3 })
assert(compact.count == 3 and compact.totalHeight == 97, "compact representative sample contract failed")
replacement.petsMaxCount, replacement.petsColumns = 5, 3
gf.ShowAdditionalGroupPreview("raid", 2)
assert(sample:GetWidth() == 394 and sample:GetHeight() == 64, "independent Pet mover lost cap-sized sparse preview bounds")
assert(sample.buttons[1]:IsShown() and sample.buttons[2]:IsShown() and not sample.buttons[3]:IsShown(), "edit samples exceeded requested count/cap")
local compactCap = gf.GetAdditionalPreviewSpec("raid", "pets", 30, { sampleCount = 3 })
assert(compactCap.count == 3 and compactCap.totalHeight == 31, "compact scene did not preserve capped sample count")
replacement.petsMaxCount, replacement.petsColumns = 40, 1
replacement.gfBarMode = "class"
gf.InvalidateCompiledSpecs("raid"); gf.RefreshAdditionalGroups()
local cr,cg,cb = world.core.UFBarTextCommon.ClassColorForToken("HUNTER")
assert(sample.buttons[1].Health.color[1] == cr and sample.buttons[1].Health.color[2] == cg and sample.buttons[1].Health.color[3] == cb, "CLASS pet samples remained fixed NPC green")
env.MSUF_EM2.State.Exit()
assert(not sample:IsShown(), "Raid pet samples survived edit exit")
print("group_additional_edit_entry_smoke: PASS")
