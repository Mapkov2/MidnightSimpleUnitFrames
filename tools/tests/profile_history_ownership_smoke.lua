local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world:Boot()
assert(not world:FirstFailure(), "real core did not boot")
local core, env = world.core, world.env
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
local H, F, W = core.History, core.ProfileFields, core.ProfileWorkbench
local db = { general = {} }
env.MSUF_GlobalDB = { profiles = { Default = db }, global = {} }
env.MSUF_DB, env.MSUF_ActiveProfile = db, "Default"
H.EnsureDB()
local value, full = { amount = 1, enabled = false }, true
local calls = { root = 0, full = 0, restoreRoot = 0, restoreFull = 0 }
F.RegisterExternal("suiteModules", {
    Resolve = function() return value end,
    Snapshot = function(source) calls.root = calls.root + 1 return source, true end,
    Restore = function(_, source) calls.restoreRoot = calls.restoreRoot + 1 value = source return true end,
})
assert(H.StartHistorySession("ownership"))
assert(H.CaptureHistory("Legacy root edit", "ownership", function() value.amount = 2 return true end))
H.FlushDeferredHistory()
local legacyRoot = assert(H.CaptureGuidedTourRestorePoint())
local aliases, roots = { "legacy-full-owner" }, { suiteModules = true }
local mergeMutation
local metadata = { roots = roots, aliases = aliases,
    covers = function(state) if state.invalid then return nil end return state.modules ~= nil end,
    merge = function(state, profile)
        if mergeMutation then
            state.modules.amount, profile.suiteModules.amount = 777, 888
            if mergeMutation == "raise" then error("Deliberate mutating merge refusal") end
            return false
        end
        state.modules = F.CopySnapshot(profile.suiteModules)
        return state
    end }
local function Capture()
    calls.full = calls.full + 1
    return { modules = full and F.CopySnapshot(value) or nil, savedFalse = false }
end
local function Restore(state)
    calls.restoreFull = calls.restoreFull + 1
    if state.modules then value = F.CopySnapshot(state.modules) end
    return state.fail ~= true
end
assert(H.RegisterHistoryProvider("full-owner", Capture, Restore, metadata))
-- The public declaration is copied at registration, including alias strings.
roots.suiteModules, aliases[1] = false, "mutated-alias"
local beforeRoot = calls.root
local point = assert(H.CaptureGuidedTourRestorePoint())
assert(calls.root == beforeRoot and point.profileDB.suiteModules == nil, "full owner did not exclude duplicate root capture")
assert(point.externalProviders["full-owner"].savedFalse == false, "owner lost explicit false")
assert(H.Undo() and value.amount == 1, "late full owner hid an earlier root-only undo")
H.FlushDeferredHistory()
assert(not H.GetHistoryState().canResetAll, "late sparse undo left a false dirty session")
assert(H.Redo() and value.amount == 2, "late owner root-only redo did not restore")
local oldAlias = F.CopySnapshot(point)
oldAlias.externalProviders["legacy-full-owner"] = oldAlias.externalProviders["full-owner"]
oldAlias.externalProviders["full-owner"] = nil
value.amount = 3
assert(H.RestoreGuidedTourRestorePoint(oldAlias) and value.amount == 2, "saved provider alias did not restore")
value.amount = 4
assert(H.RestoreGuidedTourRestorePoint(legacyRoot) and value.amount == 2, "old root-only snapshot lost its fallback")
local partial = assert(H.CaptureGuidedTourRestorePoint())
full = false
beforeRoot = calls.root
partial = assert(H.CaptureGuidedTourRestorePoint())
assert(calls.root == beforeRoot + 1 and partial.profileDB.suiteModules.amount == 2, "partial provider hid root fallback")
value.amount = 9
assert(H.RestoreGuidedTourRestorePoint(partial) and value.amount == 2, "partial owner did not restore external fallback")
full = true
local failure = assert(H.CaptureGuidedTourRestorePoint())
failure.externalProviders["full-owner"].modules.amount = 99
failure.externalProviders["full-owner"].fail = true
value.amount = 7
local saved = F.CopySnapshot(failure)
assert(H.RestoreGuidedTourRestorePoint(failure) == false and value.amount == 7, "failed owner was not rolled back")
assert(F.Equal(failure, saved), "restore mutated its stored provider payload")
local missing = F.CopySnapshot(point)
missing.externalProviders.unknown = { data = 1 }
value.amount = 8
assert(H.RestoreGuidedTourRestorePoint(missing) == false and value.amount == 8, "unknown owner changed state or reported success")
for _, bad in ipairs({ { roots = true }, { aliases = false }, { aliases = { "legacy-full-owner" }, covers = true },
    { aliases = { [2] = "sparse" }, covers = function() return false end },
    { roots = { unknown = true }, covers = function() return true end } }) do
    local ok, accepted = pcall(H.RegisterHistoryProvider, "bad-metadata", Capture, Restore, bad)
    assert(ok and accepted == false, "invalid public metadata raised or was accepted")
end
assert(H.RegisterHistoryProvider("legacy-full-owner", Capture, Restore) == false, "alias collision overwrote its owner")
assert(H.RegisterHistoryProvider("collision", Capture, Restore, {
    roots = { suiteModules = true }, covers = function() return true end }) == false, "root collision was accepted")
-- Sparse legacy history can introduce a synthetic root beside a full owner.
-- A refused merge must keep both retained inputs and the live cursor intact.
H.FlushDeferredHistory()
local mergePoint = assert(H.CaptureGuidedTourRestorePoint())
mergePoint.profileDB.suiteModules = { amount = 3, enabled = false }
local pointBefore, valueBefore = F.CopySnapshot(mergePoint), F.CopySnapshot(value)
local coreBeforeMerge, cursorBeforeMerge = F.CopySnapshot(env.MSUF_DB), F.CopySnapshot(H.GetHistoryState())
for _, refusal in ipairs({ "false", "raise" }) do
    mergeMutation = refusal
    local ok, restored = pcall(H.RestoreGuidedTourRestorePoint, mergePoint)
    assert(ok and restored == false, "mutating merge refusal raised or reported success")
    assert(F.Equal(mergePoint, pointBefore), "mutating merge changed retained payload or root")
    assert(F.Equal(value, valueBefore) and F.Equal(env.MSUF_DB, coreBeforeMerge), "mutating merge changed live state")
    assert(F.Equal(H.GetHistoryState(), cursorBeforeMerge), "mutating merge changed history cursor state")
end
mergeMutation = nil
local refuseCapture = false
assert(H.RegisterHistoryProvider("refusing-owner", function() if refuseCapture then return false end return {} end, Restore))
refuseCapture = true
local coreBefore = F.CopySnapshot(env.MSUF_DB)
local ok, refused = pcall(H.CaptureGuidedTourRestorePoint)
assert(ok and refused == nil and F.Equal(coreBefore, env.MSUF_DB), "guided capture refusal raised or changed settings")
H.UnregisterHistoryProvider("refusing-owner")
-- A callback can unregister another owner; a prepared plan refuses the stale
-- registration deterministically instead of indexing its missing record.
assert(H.RegisterHistoryProvider("first-remover", function() return {} end, function()
    H.UnregisterHistoryProvider("second-remover") return true end))
assert(H.RegisterHistoryProvider("second-remover", function() return {} end, function()
    H.UnregisterHistoryProvider("first-remover") return true end))
local dynamic = { externalProviders = { ["first-remover"] = {}, ["second-remover"] = {} } }
ok, refused = pcall(core.HistoryProviders.Restore, dynamic)
assert(ok and refused == false, "provider removal during planned restore raised or reported success")
print("PASS profile history ownership " .. flavor .. ": late sparse undo/redo, aliases, partial fallback, rollback, metadata, refusal")
