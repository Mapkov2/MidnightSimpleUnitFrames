-- profile_rename_suite_order_smoke.lua <repoRoot> <flavor>
--
-- MSUF_RenameProfile (State/MSUF_Profiles.lua) asks the MSUF Suite
-- (MSUFSuite.OnMSUFProfileLifecycle "rename") before it moves its own
-- profile. The Suite renames its own and its skin's profile and refuses, with
-- nothing changed, a name one of them already holds ("profile-exists") and
-- any rename in combat; MSUF then stops with a chat line and changes nothing
-- either. The variant overlay of the active profile is lifted before the
-- Suite is asked, so the Suite moves base settings, and laid again after a
-- refusal. A Suite that accepts (an older one, or a free name) gets the rename
-- as before; without a Suite the rename works alone.
-- Booted on the client's real load graph (tools/tests/client_world.lua) with
-- the real profile variants. Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

local w = World.New(root, flavor)
local env, ns = w.env, w.core
local combat = false
env.InCombatLockdown = function() return combat end
env.UnitAffectingCombat = function() return combat end
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        -- The real storage and variants; the frame renderers behind the
        -- runtime apply are outside this test.
        ns.ProfileRuntime.Apply = function()
            ns.ProfileVariants.ResolveCurrent()
            ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
        end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local V = ns.ProfileVariants
env.MSUF_DB = { general = {}, player = { width = 150 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
-- "Default" cannot be renamed: work on a copy.
local source = "Main"
Check(env.MSUF_CopyProfile(env.MSUF_ActiveProfile, source) and env.MSUF_SwitchProfile(source),
    "harness: the profile to rename was not created")
local db = env.MSUF_DB
db.player.width = 150
Check(V.Replace(db, { version = 1, entries = { { name = "Solo", conditions = { context = "solo" },
    patch = { { path = { "player", "width" }, value = 250 } } } } }), "harness: the variant was not saved")
Check(db.player.width == 250, "harness: the variant overlay is not laid")
local charKey = env.MSUF_GetCharKey()

local asked, refusals, suiteStore = {}, {}, nil
local function UseSuite()
    env.MSUFSuite = {
        OnMSUFProfileLifecycle = function(kind, from, to)
            local profiles = env.MSUF_GlobalDB.profiles
            asked[#asked + 1] = { kind = kind, from = from, to = to, fromStored = profiles[from] ~= nil,
                toStored = profiles[to] ~= nil, width = env.MSUF_DB.player.width }
            if combat then return false end
            -- true: an older Suite's refusal, which names no reason.
            if refusals[to] then return false, refusals[to] ~= true and refusals[to] or nil end
            if kind == "rename" and suiteStore then suiteStore[to], suiteStore[from] = suiteStore[from], nil end
            return true
        end,
        OnMSUFProfileChanged = function(name) asked[#asked + 1] = { kind = "changed", to = name } end,
    }
end
local function Said(fragment)
    for i = 1, #w.prints do if w.prints[i]:find(fragment, 1, true) then return true end end
    return false
end
local function Unchanged(label)
    local profiles = env.MSUF_GlobalDB.profiles
    Check(profiles[source] == db and env.MSUF_DB == db and env.MSUF_ActiveProfile == source
        and env.MSUF_GlobalDB.char[charKey].activeProfile == source, label .. ": MSUF renamed its profile")
end
local function AskedBeforeMove(label, entry)
    Check(entry and entry.kind == "rename" and entry.from == source and entry.fromStored and not entry.toStored,
        label .. ": the Suite was not asked before MSUF moved its profile")
    Check(entry.width == 150, label .. ": the Suite was asked while the variant overlay was laid")
end

-- 1. The Suite refuses a name its own or its skin's store already holds.
UseSuite()
refusals.Taken = "profile-exists"
w.prints = {}
local ok, why = env.MSUF_RenameProfile(source, "Taken")
Check(ok == false and why == "profile-exists", "a refused rename went ahead")
Check(env.MSUF_GlobalDB.profiles.Taken == nil and Said("Profile 'Taken' already exists."),
    "MSUF did not stop with the taken-name line")
Unchanged("refused")
Check(#asked == 1, "the Suite heard " .. #asked .. " notifications for one refused rename")
AskedBeforeMove("refused", asked[1])
Check(db.player.width == 250 and V.IsMaterialized(db), "the variant overlay was not laid again after the refusal")

-- 2. In combat the Suite refuses; MSUF names the combat and leaves the
--    overlay alone (a deferred re-lay would wait for the next context change).
asked, w.prints = {}, {}
combat = true
ok = env.MSUF_RenameProfile(source, "Later")
local widthInCombat = db.player.width
combat = false
Check(ok == false and env.MSUF_GlobalDB.profiles.Later == nil and Said("Cannot change profiles while in combat."),
    "a rename the Suite refused in combat was not stopped with the combat line")
Unchanged("combat")
Check(#asked == 1 and widthInCombat == 250 and V.IsMaterialized(db), "a rename refused in combat lifted the variant overlay")

-- 3. An older Suite refuses without a reason: MSUF still says why.
asked, w.prints = {}, {}
refusals.Odd = true
Check(env.MSUF_RenameProfile(source, "Odd") == false and Said("Profile names can be at most 80 bytes long."),
    "a refusal without a reason was not reported")
Unchanged("refused without a reason")

-- 4. A Suite that accepts gets the rename first, then MSUF renames and switches.
--    The Suite lends its store to sync and variants and creates a profile it
--    is asked for by a name it does not hold (MSUF_Suite Core/ProfileVariants.lua),
--    and the profile is in a sync group: once the Suite moved the store, no
--    later step may ask for the old name and bring it back.
suiteStore = { [source] = { marker = source } }
ns.ProfileFields.RegisterExternal("suiteModules", { Resolve = function(name, create)
    if suiteStore[name] == nil and create then suiteStore[name] = {} end
    return suiteStore[name]
end })
Check(env.MSUF_CopyProfile(source, "Peer") == true, "harness: the sync peer was not created")
Check(ns.ProfileSync.Replace({ { name = "Shared", members = { [source] = true, Peer = true }, modules = { unitframes = true } } }),
    "harness: the sync group was not saved")
asked = {}
Check(env.MSUF_RenameProfile(source, "Renamed") == true, "an accepted rename failed")
AskedBeforeMove("accepted", asked[1])
Check(env.MSUF_GlobalDB.profiles.Renamed == db and env.MSUF_GlobalDB.profiles[source] == nil
    and env.MSUF_ActiveProfile == "Renamed" and env.MSUF_GlobalDB.char[charKey].activeProfile == "Renamed",
    "MSUF did not rename its profile after the Suite accepted")
Check(asked[#asked].kind == "changed" and asked[#asked].to == "Renamed", "the Suite did not follow the renamed profile")
Check(db.player.width == 250, "the variant overlay was not laid on the renamed profile")
Check(suiteStore.Renamed and suiteStore.Renamed.marker == source and suiteStore[source] == nil,
    "the Suite's store got a profile under the old name back after the rename")

-- 5. Without the Suite the rename works alone.
env.MSUFSuite = nil
Check(env.MSUF_RenameProfile("Renamed", "Alone") == true and env.MSUF_ActiveProfile == "Alone",
    "a rename without the Suite failed")

print("profile_rename_suite_order_smoke: ok (" .. flavor .. ")")
