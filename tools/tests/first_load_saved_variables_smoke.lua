-- first_load_saved_variables_smoke.lua <repoRoot>
--
-- The client loads SavedVariables after every Lua file of the addon ran and
-- right before ADDON_LOADED fires for it (Blizzard's own AddonList.lua assigns
-- its SavedVariablesMachine global an empty table at file load, which only
-- works because the saved value replaces it afterwards). State/MSUF_FirstLoad.lua
-- read MSUF_DB/MSUF_GlobalDB at file load, so in game every login looked like a
-- clean install: an upgrade from 5.x got the fresh-install welcome, pre-6
-- profiles were never archived and went on to normalization.
--
-- This smoke boots each client's real core graph through the client kit, then
-- runs the client's SavedVariables step (world:LoadSavedVariables) and pins:
--   1. a clean install reads as fresh, although files built a profile while
--      the addon loaded;
--   2. an upgrade from 5.x reads as an upgrade and its pre-6 profiles, the
--      standalone profile and the stale bindings are archived before any
--      profile initialization;
--   3. a saved 6.x lifecycle is followed, not replaced.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local ADDON = "MidnightSimpleUnitFrames"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    return world, world.env
end

local function Run(flavor)
    -- 1. Clean install: no saved values; whatever the files built stays.
    local world, env = Boot(flavor)
    Check(type(rawget(env, "MSUF_DB")) == "table",
        flavor .. ": no file built a profile while loading; the session-profile case is not exercised")
    world:LoadSavedVariables(ADDON, {})
    local FirstLoad = assert(world.core.FirstLoad6, flavor .. ": no MSUF.FirstLoad6")
    local detection = FirstLoad:GetDetection()
    Check(FirstLoad:GetInstallKind() == "fresh" and detection.reason == "no_saved_variables",
        flavor .. ": a clean install reads as " .. tostring(FirstLoad:GetInstallKind()) .. " ("
        .. tostring(detection.reason) .. ")")
    Check(env.MSUF_GlobalDB.global.firstLoad6 == FirstLoad:GetState(),
        flavor .. ": the clean-install lifecycle is not in the saved root")

    -- 2. Upgrade from 5.x: the saved tables replace the load-time ones.
    world, env = Boot(flavor)
    local legacy = { general = { marker = "legacy" } }
    local current = { _msufProfileSchema = 600, general = { marker = "current" } }
    local standalone = { general = { marker = "standalone" } }
    local savedGlobal = {
        profiles = { Legacy = legacy, Current = current },
        char = { ["Tester-Realm"] = { activeProfile = "Legacy", specProfileMap = { [1] = "Current" } } },
        global = { defaultProfileForNewChars = "Legacy" },
    }
    world:LoadSavedVariables(ADDON, { MSUF_DB = standalone, MSUF_GlobalDB = savedGlobal })
    Check(env.MSUF_GlobalDB == savedGlobal, flavor .. ": the saved MSUF_GlobalDB was replaced")
    Check(savedGlobal.profiles.Legacy == nil and savedGlobal.ignoredPre6Profiles
        and savedGlobal.ignoredPre6Profiles.Legacy == legacy,
        flavor .. ": the unversioned 5.x profile was not archived on ADDON_LOADED")
    Check(savedGlobal.ignoredPre6Profiles.__standalone == standalone and rawget(env, "MSUF_DB") == nil,
        flavor .. ": the standalone 5.x profile was not archived on ADDON_LOADED")
    Check(savedGlobal.profiles.Current == current and savedGlobal.char["Tester-Realm"].activeProfile == nil
        and savedGlobal.char["Tester-Realm"].specProfileMap[1] == "Current"
        and savedGlobal.global.defaultProfileForNewChars == nil,
        flavor .. ": the archive did not retire exactly the stale bindings")
    local state = savedGlobal.global.firstLoad6
    Check(type(state) == "table" and state.installKind == "upgrade",
        flavor .. ": an upgrade from 5.x reads as " .. tostring(state and state.installKind))
    Check(state.legacyProfileDetected == true and state.existingProfileDetected == true,
        flavor .. ": the upgrade evidence missed the saved 5.x profile")
    FirstLoad = world.core.FirstLoad6
    Check(FirstLoad:GetInstallKind() == "upgrade" and FirstLoad:GetState() == state,
        flavor .. ": the lifecycle API does not follow the saved state")

    -- 3. A returning 6.x user: the saved lifecycle wins.
    world, env = Boot(flavor)
    local done = { schema = 1, revision = 1, installKind = "upgrade", status = "completed", step = "defaults",
        firstSeenVersion = "6.0", installReason = "saved_profiles_schema" }
    savedGlobal = { profiles = { Default = current }, char = {}, global = { firstLoad6 = done } }
    world:LoadSavedVariables(ADDON, { MSUF_DB = current, MSUF_GlobalDB = savedGlobal })
    FirstLoad = world.core.FirstLoad6
    Check(FirstLoad:GetState() == done and done.status == "completed" and FirstLoad:IsTerminal(),
        flavor .. ": a completed 6.x lifecycle was replaced")
    Check(savedGlobal.profiles.Default == current and savedGlobal.ignoredPre6Profiles == nil,
        flavor .. ": a schema-600 profile was archived")
    print("first_load_saved_variables_smoke: ok (" .. flavor .. ")")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
