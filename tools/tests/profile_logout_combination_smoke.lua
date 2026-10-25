-- Real TOC/login/logout graph: variant edits, recording cancellation and sync
-- survive sparse and compatibility serialization into independent fresh worlds.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
assert(flavor == "Mainline", "logout combination is client-independent; run Mainline only")
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Copy(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Healthy(world, stage)
    local errors = C.UnexpectedErrors({ world = world, flavor = flavor }, {})
    assert(#errors == 0, stage .. ": " .. table.concat(errors, "; "))
end
local function Login(saved)
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, saved or {}, true)
    Healthy(world, "login")
    assert(world.core.Lifecycle.Phase == "running", "login did not finish lifecycle")
    assert(world.env.MSUF_DB == world.env.MSUF_GlobalDB.profiles[world.env.MSUF_ActiveProfile],
        "login did not bind public alias to active stored profile")
    return world, world.env, world.core
end
-- Serialize exactly the TOC's SavedVariables, like profile_rollback_full_graph_smoke.
local function Saved(env)
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc", "rb"))
    local names = assert(file:read("*a"):match("## SavedVariables: ([^\n]+)"))
    file:close()
    local lines = {}
    for name in names:gmatch("[%w_]+") do
        local value = rawget(env, name)
        if value ~= nil then lines[#lines + 1] = name .. "=" .. H.Literal(value) end
    end
    local disk, chunk = {}, assert(loadstring(table.concat(lines, "\n")))
    setfenv(chunk, disk)
    chunk()
    return disk
end
local seedWorld, seedEnv = Login()
local active = seedEnv.MSUF_ActiveProfile
local seed = Copy(seedEnv.MSUF_GlobalDB)
seed.profiles = { [active] = Copy(seedEnv.MSUF_DB), Plain = Copy(seedEnv.MSUF_DB), Local = Copy(seedEnv.MSUF_DB) }
local source = seed.profiles[active]
source.player.width, source.player.height, source.player.offsetX, source.player.offsetY = 311, 41, 11, 21
source.profileVariants = { version = 1, entries = {
    { name = "Always", patch = { { path = { "player", "width" }, value = 401 } } },
} }
for _, name in ipairs({ "Plain", "Local" }) do
    local target = seed.profiles[name]
    target.player.width, target.player.height, target.player.offsetX, target.player.offsetY = 511, 51, 15, 25
end
seed.profiles.Local.profileVariants = { version = 1, entries = {
    { name = "Target local", patch = { { path = { "player", "offsetY" }, value = 99 } } },
} }
seed.global.profileSyncGroups = {
    { name = "Logout", members = { [active] = true, Plain = true, Local = true },
        modules = { unitframes = true }, exclude = { { "player", "offsetX" } } },
}
seedWorld, seedEnv = nil, nil
local cases = 0
for _, mode in ipairs({ "sparse", "compat" }) do
    for _, recording in ipairs({ false, true }) do
        local world, env, ns = Login({ MSUF_GlobalDB = Copy(seed) })
        local db, pool = env.MSUF_DB, env.MSUF_GlobalDB.profiles
        local variants, sync = ns.ProfileVariants, ns.ProfileSync
        assert(env.MSUF_ActiveProfile == active and variants.IsMaterialized(db) and db.player.width == 401,
            "source variant was not active at login")
        local expected = Copy(pool)
        expected[active].player.width = 311
        -- Edit the overlaid field and three ordinary fields. Only eligible base
        -- edits may reach members; source/target patches and exclusions stay local.
        db.player.width, db.player.height, db.player.offsetX, db.player.offsetY = 421, 61, 31, 41
        expected[active].player.height, expected[active].player.offsetX, expected[active].player.offsetY = 61, 31, 41
        expected[active].profileVariants.entries[1].patch[1].value = 421
        expected.Plain.player.height, expected.Local.player.height = 61, 61
        expected.Plain.player.offsetY = 41
        assert(pool.Plain.player.height == 51, "pending sync edit reached target before flush")
        if recording then
            -- BeginRecording intentionally flushes preceding base edits. New
            -- pending edits below are unsaved recording work and must be discarded.
            assert(variants.BeginRecording("Always"))
            assert(variants.IsRecording() and variants.RecordingName() == "Always")
            assert(pool.Plain.player.height == 61, "recording start did not flush preceding edits")
            db.player.width, db.player.height, db.player.offsetX, db.player.offsetY = 777, 78, 88, 98
            local ok, why = sync.Flush()
            assert(not ok and why == "finish editing the variant first", "sync accepted an active recording")
            assert(pool.Plain.player.height == 61, "recording leaked to sync target")
        end
        if mode == "compat" then ns.SlashCommands.Dispatch("compatsave") end
        local bindings, groups = H.Literal(env.MSUF_GlobalDB.char), H.Literal(sync.GetGroups())
        -- Do not call Restore/CancelRecording/Flush/Persist here: the native
        -- registered handlers must perform the entire terminal sequence.
        world:FireEvent("PLAYER_LOGOUT")
        Healthy(world, mode .. " logout")
        assert(rawget(env, "MSUF_DB") == nil, "logout retained duplicate public SavedVariable")
        assert(not variants.IsRecording() and not variants.IsMaterialized(db), "logout retained runtime variant state")
        assert(pool[active] == db, "logout replaced the stored active profile")
        local disk = Saved(env)
        assert(disk.MSUF_DB == nil, "serialized a duplicate public profile")
        if mode == "sparse" then
            for _, profile in pairs(pool) do
                assert(type(profile._msufSparseDefaultsV3) == "string", "logout did not use sparse persistence")
            end
        else
            assert(env.MSUF_GlobalDB._compatSave == "saved", "compatibility save did not finish")
            for _, profile in pairs(pool) do
                assert(profile._msufSparseDefaultsV3 == nil and profile._msufSparseDefaultsV2 == nil,
                    "compatibility save retained sparse metadata")
            end
            assert(H.Literal(pool) == H.Literal(expected), "compatibility save changed complete base profiles")
        end
        local reloaded, again, fresh = Login(disk)
        assert(reloaded ~= world and again ~= env and fresh ~= ns, "reload reused the previous world")
        assert(again.MSUF_ActiveProfile == active and again.MSUF_DB == again.MSUF_GlobalDB.profiles[active],
            "fresh login changed active binding or profile alias identity")
        assert(H.Literal(again.MSUF_GlobalDB.char) == bindings, "fresh login changed character bindings")
        assert(H.Literal(fresh.ProfileSync.GetGroups()) == groups, "fresh login changed sync groups")
        assert(not fresh.ProfileVariants.IsRecording() and fresh.ProfileVariants.GetManual() == nil,
            "recording/manual runtime state survived login")
        assert(again.MSUF_GlobalDB._compatSave == nil, "login did not disarm compatibility save")
        assert(again.MSUF_DB.player.width == 421 and fresh.ProfileVariants.IsMaterialized(again.MSUF_DB),
            "fresh login did not apply the saved variant patch")
        local base = assert(fresh.ProfileVariants.BaseSnapshot(again.MSUF_DB, true))
        assert(base.player.width == 311, "variant or recording overwrote the remembered base")
        local actual = Copy(again.MSUF_GlobalDB.profiles)
        actual[active] = base
        assert(H.Literal(actual) == H.Literal(expected), "fresh login changed base values, targets or variant patches")
        Healthy(reloaded, mode .. " reload")
        cases = cases + 1
    end
end
print("PASS profile logout combination Mainline: " .. cases .. " variant/recording x sparse/compat fresh logins")
