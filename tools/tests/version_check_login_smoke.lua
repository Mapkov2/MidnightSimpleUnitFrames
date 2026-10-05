-- version_check_login_smoke.lua <repoRoot>
--
-- The peer version check must run from login on every client. Its Enable used
-- to be reachable only through MSUF_ApplyModules, which no login path runs
-- outside WoW Forever (whose swing-timer driver happens to call it), so on
-- Classic Era, TBC, Mists and Midnight no CHAT_MSG_ADDON listener existed and
-- a newer peer never produced the update line (red without the fix).
--
-- Per client, on the real core + Options graph (tools/tests/client_world.lua):
--   1. after PLAYER_LOGIN the check is active and a newer peer prints the
--      update notice once;
--   2. turning the option off afterwards (the menu toggle runs
--      MSUF_ApplyModules) silences it, although the registry never switched
--      the module on itself;
--   3. the notice is one translated sentence: a German client prints the
--      German line (it was an English literal in every language).
-- Events reach each frame on their own (test-side pcall), so an unrelated
-- harness gap in another module's login handler cannot hide this one.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Fire(world, event, ...)
    local frames = world.widgets.frames
    for index = 1, #frames do
        local frame = frames[index]
        local events = rawget(frame, "events")
        local scripts = rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and (events[event] or events["*"]) then pcall(handler, frame, event, ...) end
    end
end

local function Notices(world, from)
    local count = 0
    for index = from + 1, #world.prints do
        if world.prints[index]:find("A newer version", 1, true) then count = count + 1 end
    end
    return count
end

local function Login(flavor, locale)
    local world = World.New(root, flavor, { locale = locale })
    rawset(world.env, "MAX_BOSS_FRAMES", 5)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": load failure in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_GlobalDB = {
            profiles = { Default = { _msufProfileSchema = 600, general = {} } },
            char = { ["Tester-Realm"] = { activeProfile = "Default" } },
            global = { firstLoad6 = { schema = 1, revision = 1, installKind = "upgrade", status = "completed", step = "defaults" } },
        },
    })
    Fire(world, "PLAYER_LOGIN")
    Fire(world, "PLAYER_ENTERING_WORLD", true, false)
    return world
end

local flavors = World.Flavors(root)
for _, flavor in ipairs(flavors) do
    local world = Login(flavor)
    local check = assert(world.core.VersionCheck, flavor .. ": MSUF.VersionCheck missing")
    assert(check.IsActive() == true, flavor .. ": the version check did not start at login")
    local before = #world.prints
    Fire(world, "CHAT_MSG_ADDON", "MSUF", "V:99.0", "GUILD", "Mate-Realm")
    Fire(world, "CHAT_MSG_ADDON", "MSUF", "V2:99000000400000:99.0", "GUILD", "Mate-Realm")
    assert(Notices(world, before) == 1, flavor .. ": a newer peer printed " .. Notices(world, before) .. " update notices after login (want 1)")

    -- The menu toggle writes the setting, then runs the real registry pass;
    -- the other modules' switches (class power, gameplay, rounded frames) are
    -- no-ops here because the harness cannot draw them.
    local quiet = Login(flavor)
    local noop = function() end
    for _, module in ipairs(quiet.core.MSUF_Modules) do
        if module.key ~= "VersionCheck" then module.Enable, module.Disable = noop, noop end
    end
    quiet.env.MSUF_DB.general.versionCheckEnabled = false
    quiet.env.MSUF_ApplyModules()
    local mark = #quiet.prints
    Fire(quiet, "CHAT_MSG_ADDON", "MSUF", "V:99.0", "GUILD", "Mate-Realm")
    assert(Notices(quiet, mark) == 0, flavor .. ": the update notice printed after the version check was turned off")
end

local german = Login("Vanilla", "deDE")
local mark = #german.prints
Fire(german, "CHAT_MSG_ADDON", "MSUF", "V:99.0", "GUILD", "Mate-Realm")
local line = german.prints[mark + 1] or ""
assert(line:find("Eine neuere Version (|cffffd10099.0|r) ist verfügbar!", 1, true),
    "deDE: the update notice is not translated: " .. line)

print("version_check_login_smoke: ok (" .. table.concat(flavors, ", ") .. ")")
