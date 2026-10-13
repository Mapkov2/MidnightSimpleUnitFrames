-- Explicit binding must not move visual construction or spec switches earlier.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end
local function Profile(width)
    return { _msufProfileSchema = 600, general = {}, player = { width = width } }
end
local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
local env, ns = world.env, world.core
local earlyAuraApply = 0
local auras = ns.MSUF_Auras3
local request = auras.RequestApply
auras.RequestApply = function(...)
    if ns.Lifecycle.Phase == "ready" then earlyAuraApply = earlyAuraApply + 1 end
    return request(...)
end
env.MSUF_GetPlayerSpecID = function() return 66 end
local notifications = {}
ns.SuiteLink.NotifyProfileChanged = function(name)
    notifications[#notifications + 1] = name
end
Corpus.Login(world, {
    MSUF_GlobalDB = {
        profiles = { Solo = Profile(181), Raid = Profile(282) },
        char = { ["Tester-Realm"] = {
            activeProfile = "Solo", specAutoSwitch = true,
            specProfileMapVersion = 1, specProfileMap = { [66] = "Raid" },
        } },
    },
})
Check(earlyAuraApply == 0, "locale callback requested group visuals at ADDON_LOADED")
Check(env.MSUF_ActiveProfile == "Solo", "spec auto-switch moved from PLAYER_ENTERING_WORLD to PLAYER_LOGIN")
Check(#world.runtimeApplies == 0 and #notifications == 0, "login applied a spec profile or notified Suite before frame startup")
local frame = assert(env.MSUF_SpecProfileEventFrame)
assert(frame.events.PLAYER_ENTERING_WORLD, "the original spec event is missing")
frame.scripts.OnEvent(frame, "PLAYER_ENTERING_WORLD", true, false)
Check(env.MSUF_ActiveProfile == "Raid" and env.MSUF_DB.player.width == 282,
    "PLAYER_ENTERING_WORLD did not apply the mapped spec profile")
Check(#world.runtimeApplies == 1 and #notifications == 1 and notifications[1] == "Raid",
    "the world-entry spec switch did not apply and notify Suite exactly once")
if #failures > 0 then error(table.concat(failures, "\n")) end
print("profile_startup_phase_smoke: ok (" .. flavor .. ")")
