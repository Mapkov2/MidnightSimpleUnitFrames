-- Stored character choice, configured default, missing donor and standalone seed.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local function Profile(width)
    return { _msufProfileSchema = 600, general = {}, player = { width = width } }
end
local pools = {
    { profiles = { Alpha = Profile(111), Default = Profile(222), B = Profile(333) } },
    { profiles = { Alpha = Profile(111), B = Profile(333) }, configured = "B" },
    { profiles = { Alpha = Profile(111), Default = Profile(222) } },
    { profiles = {} },
    { profiles = { Alpha = Profile(111), Zeta = Profile(555) }, configured = "Zeta" },
}
local runs = 0
for _, pool in ipairs(pools) do
    for _, choice in ipairs({ "B", "Missing", false }) do
        local active = choice or nil
        local name = active or (next(pool.profiles) and pool.configured) or "Default"
        local donor = pool.profiles[name] or pool.profiles.Default or pool.profiles.Alpha
        local width = donor and donor.player.width or 999
        local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
        Corpus.Login(world, {
            MSUF_DB = Profile(999),
            MSUF_GlobalDB = {
                profiles = Corpus.Copy(pool.profiles),
                char = { ["Tester-Realm"] = { activeProfile = active } },
                global = { defaultProfileForNewChars = pool.configured },
            },
        })
        assert(world.env.MSUF_ActiveProfile == name, "startup changed the character's profile choice")
        assert(world.env.MSUF_DB.player.width == width, "startup changed the original donor precedence")
        assert(world.env.MSUF_GlobalDB.legacyStandaloneProfiles == nil, "migration retained a standalone archive")
        runs = runs + 1
    end
end
print("profile_legacy_precedence_smoke: ok (" .. flavor .. ", " .. runs .. " cases)")
