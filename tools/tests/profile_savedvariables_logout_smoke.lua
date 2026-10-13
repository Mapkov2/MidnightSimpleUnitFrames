-- Keep the declared legacy variable readable until the final logout handler.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end
for _, suffix in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. suffix .. ".toc", "rb"))
    local text = file:read("*a")
    file:close()
    Check(text:match("## SavedVariables:%s*MSUF_DB,%s*MSUF_GlobalDB"), suffix .. ": legacy MSUF_DB is not declared")
end
local w = Corpus.NewWorld(root, flavor, "Tester-Realm")
local env, ns = w.env, w.core
local observer = env.CreateFrame("Frame")
local seen, seenWidth
observer:RegisterEvent("PLAYER_LOGOUT")
observer:SetScript("OnEvent", function()
    seen = env.MSUF_DB
    seenWidth = seen.player.width
end)
Corpus.Login(w, { MSUF_DB = { _msufProfileSchema = 600, general = {}, player = { width = 333 } } })
local profile = env.MSUF_DB
Check(profile == env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile], "the runtime alias is not bound")
-- Enabling these after login creates their lazy logout drivers after the final
-- cleanup frame. The lifecycle still restores/flushes first, and those drivers
-- must not re-read or recreate the alias after it has been cleared.
env.MSUF_GlobalDB.profiles.Peer = Corpus.Copy(profile)
assert(ns.ProfileSync.Replace({ {
    name = "Frames", members = { Default = true, Peer = true }, modules = { unitframes = true },
} }))
assert(ns.ProfileVariants.Replace(profile, { version = 1, entries = {
    { name = "Always", patch = { { path = { "player", "width" }, value = 444 } } },
} }))
Check(profile.player.width == 444, "the late-enabled variant did not materialize")
profile.player.height = 69
local restores, flushes = 0, 0
local restore, flush = ns.ProfileVariants.Restore, ns.ProfileSync.Flush
ns.ProfileVariants.Restore = function(...)
    Check(env.MSUF_DB == profile, "variant restoration lost the alias before logout work")
    restores = restores + 1
    return restore(...)
end
ns.ProfileSync.Flush = function(...)
    Check(env.MSUF_DB == profile, "sync flush lost the alias before logout work")
    flushes = flushes + 1
    return flush(...)
end
w:FireEvent("PLAYER_LOGOUT")
Check(seen == profile and seenWidth == 444, "another addon's earlier logout handler lost the runtime profile")
Check(restores > 0 and flushes > 0, "logout omitted the lifecycle's variant/sync work")
Check(rawget(env, "MSUF_DB") == nil, "the post-logout SavedVariables still write the duplicate profile")
Check(env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] == profile and profile.player.width == 333,
    "clearing the alias removed the stored profile")
Check(env.MSUF_GlobalDB.profiles.Peer.player.height == 69, "late-enabled sync lost the final edit")
if #failures > 0 then error(table.concat(failures, "\n")) end
print("profile_savedvariables_logout_smoke: ok (" .. flavor .. ")")
