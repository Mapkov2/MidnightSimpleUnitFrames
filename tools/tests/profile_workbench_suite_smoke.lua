local root, suiteRoot = assert(arg[1]), assert(arg[2])
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, "Mainline", { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end })
local env, core = mw.env, mw.core
env.C_AddOns = {
    GetAddOnMetadata = function() end,
    IsAddOnLoaded = function(name) return name == "MidnightSimpleUnitFrames", name == "MidnightSimpleUnitFrames" end,
    DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
local Suite = {}
local Support = assert(loadfile(suiteRoot .. "/tools/tests/suite_test_support.lua"))()
for _, file in ipairs(Support.TocFiles(suiteRoot, "MSUF_Suite", "Mainline")) do
    if file:match("%.lua$") then
        local ok, why = mw.world:LoadFile(suiteRoot .. "/MSUF_Suite/" .. file, "MSUF_Suite", Suite)
        assert(ok, file .. ": " .. tostring(why))
    end
    if file == "Core/ProfileVariants.lua" then break end
end
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local W = core.ProfileWorkbench
local before = assert(W.Snapshot())
assert(before.providers.suiteSkin.suite.modules.nameplates, "full restore points include native skin settings")
assert(before.providers.suiteSkin.suite.modules.loot, "full restore points include deliberate automation settings")
assert(not before.core.suiteModules, "the full provider avoids duplicate module restoration")
local current = Suite.DB.suite.modules
local oldWidth = current.objectives.width
current.loot.quickLoot = not current.loot.quickLoot
current.objectives.width = oldWidth + 30
assert(W.ApplySnapshot(before, "Suite restore"))
assert(Suite.DB.suite.modules.objectives.width == oldWidth)
assert(Suite.DB.suite.modules.loot.quickLoot == before.providers.suiteSkin.suite.modules.loot.quickLoot)
local after = assert(W.Snapshot())
after.providers.suiteSkin.suite.modules.objectives.width = oldWidth + 40
local review = assert(W.ReviewSnapshot(after, "Suite review"))
assert(#review.changes > 0)
assert(W.CommitReview(review))
assert(Suite.DB.suite.modules.objectives.width == oldWidth + 40)
assert(core.History.Undo())
assert(Suite.DB.suite.modules.objectives.width == oldWidth, "Suite provider participates in one shared undo")
local persisted, active = { accent = 1 }, "Default"
local fake = {
    Database = {
        GetActiveProfileName = function() return active end,
        SetProfile = function(_, value) persisted = value return true end,
        SetActiveProfile = function(name) active = name return true end,
        GetHistoryEpoch = function() return 0 end,
    },
}
Suite.SuiteProfiles.WorkbenchSkinEngine = function() return fake end
Suite.SuiteProfiles.WorkbenchSkinSnapshot = function() return Suite.CopyValue(persisted) end
local skinSnapshot = assert(W.Snapshot())
persisted.accent = 2
assert(W.ApplySnapshot(skinSnapshot, "Skin restore"))
assert(persisted.accent == 1)
print("profile_workbench_suite_smoke: full module state, review, undo and skin restoration passed")
