-- A reset or import of the active profile stays in that profile (review F4).
-- Edits made before it still reach the other sync members, edits made after it
-- sync normally, and the reset or imported values themselves never overwrite
-- another member at the next profile switch.
-- Usage: lua tools/tests/profile_sync_rebase_smoke.lua <repoRoot> [flavor]
local root, flavor = assert(arg[1], "repo root required"), arg[2] or "Vanilla"
local w = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, ns = w.env, w.core
env.InCombatLockdown = function() return false end
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        ns.ProfileRuntime.Apply = function()
            ns.ProfileVariants.ResolveCurrent()
            ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
        end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure(); assert(not failure, failure and failure.message)
local S, F = ns.ProfileSync, ns.ProfileFields
env.MSUF_DB = { general = {}, player = { width = 150 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local A = env.MSUF_ActiveProfile
assert(env.MSUF_CopyProfile(A, "Main"))
local profiles = env.MSUF_GlobalDB.profiles
profiles[A].player.width, profiles.Main.player.width = 321, 321
assert(S.Replace({ { name = "Frames", members = { [A] = true, Main = true }, modules = { unitframes = true } } }))

-- Reset: the reset values stay in the reset profile.
assert(env.MSUF_ResetProfile(A))
assert(env.MSUF_DB.player.width ~= 321, "the reset did not reset the active profile")
assert(env.MSUF_SwitchProfile("Main"))
assert(profiles.Main.player.width == 321, "the reset of one profile overwrote another sync member")
assert(env.MSUF_SwitchProfile(A))
-- An edit after the reset syncs as usual.
env.MSUF_DB.player.width = 333
assert(env.MSUF_SwitchProfile("Main") and profiles.Main.player.width == 333, "sync stopped after a reset")
assert(env.MSUF_SwitchProfile(A))

-- Import: a pending edit reaches the members first, the import stays local.
local exported
env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = value; return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
assert(env.MSUF_ExportSelectionToString("all"))
local source = F.CopySnapshot(exported)
local payload = source.msuf6 and source.msuf6.payload or source.payload
payload.player.width = 999
env.MSUF_TryDecodeCompactString = function(str) if str == "MSUF3:captured" then return (F.CopySnapshot(source)) end end
env.MSUF_DB.player.height = 77
assert(env.MSUF_ImportFromString("MSUF3:captured"))
assert(env.MSUF_DB.player.width == 999, "the import did not reach the active profile")
assert(profiles.Main.player.height == 77, "an edit made before the import never reached the other member")
assert(env.MSUF_SwitchProfile("Main"))
assert(profiles.Main.player.width == 333, "the import into one profile overwrote another sync member")
-- External (Wago) import into the active profile behaves the same way.
assert(env.MSUF_SwitchProfile(A))
payload.player.width = 888
assert(env.MSUF_ImportExternal("MSUF3:captured", A))
assert(env.MSUF_DB.player.width == 888, "the external import did not reach the active profile")
assert(env.MSUF_SwitchProfile("Main"))
assert(profiles.Main.player.width == 333, "the external import into one profile overwrote another sync member")
print("profile_sync_rebase_smoke: OK (" .. flavor .. ")")
