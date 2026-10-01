-- Resetting a profile that is not active stores a complete, stamped profile
-- (review F5). An unstamped {} was archived as a pre-6.0 profile at the next
-- login, which also cleared every character binding, spec mapping and the
-- new-character default that named it.
-- Usage: lua tools/tests/profile_reset_stored_smoke.lua <repoRoot> [flavor]
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
local F = ns.ProfileFields
env.MSUF_DB = { general = {}, player = { width = 150 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local active = env.MSUF_ActiveProfile
-- The harness has no native CBOR decoder for the embedded factory string.
local factory = F.CopySnapshot(env.MSUF_DB)
factory.player.width = 275
ns.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
assert(env.MSUF_CopyProfile(active, "Healer"))
local healer = env.MSUF_GlobalDB.profiles.Healer
healer.player.width = 300
env.MSUF_GlobalDB.char["Alt-Realm"] = { activeProfile = "Healer", specProfileMap = { [257] = "Healer" } }
env.MSUF_SetDefaultProfileForNewCharacters("Healer")

assert(env.MSUF_ResetProfile("Healer"), "resetting a stored profile failed")
local reset = env.MSUF_GlobalDB.profiles.Healer
assert(type(reset) == "table" and tonumber(reset._msufProfileSchema) == 600, "the reset profile has no schema stamp")
assert(reset.player and reset.player.width == 275, "the reset profile does not hold the factory settings")
assert(env.MSUF_ActiveProfile == active, "resetting a stored profile switched profiles")

-- Next login: the first-load policy runs on the saved state before anything else.
local saved = F.CopySnapshot(env.MSUF_GlobalDB)
local G = { MSUF_GlobalDB = saved, MSUF_DB = saved.profiles[active], time = os.time }
setmetatable(G, { __index = _G })
local nsLogin = { ExportPublic = function(name, value) G[name] = value end, GetAddonVersion = function() return "6.5" end, Client = {} }
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))
setfenv(chunk, G)
chunk("MidnightSimpleUnitFrames", nsLogin)
assert(type(saved.profiles.Healer) == "table", "the next login archived the reset profile")
assert(saved.char["Alt-Realm"].activeProfile == "Healer" and saved.char["Alt-Realm"].specProfileMap[257] == "Healer",
    "the next login cleared the bindings of the reset profile")
assert(saved.global.defaultProfileForNewChars == "Healer", "the next login cleared the new-character default")
print("profile_reset_stored_smoke: OK (" .. flavor .. ")")
