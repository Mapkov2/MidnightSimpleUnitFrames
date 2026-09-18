-- WoW Forever onboarding-scene smoke.
--
--   lua tools/tests/forever_onboarding_scenes_smoke.lua <repo root>
--
-- The Forever beta client does not keep SavedVariables between sessions, a
-- Blizzard bug that hits every addon. Both one-time scenes - the first-start
-- welcome and the 6.0 release highlights - live in those variables, so every
-- login reads as a clean install and would greet the player again.
-- Client.SupportsOnboardingScenes retires them on Forever alone, while
-- `/msuf firstload` still re-arms either one for a deliberate preview.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Client fact
---------------------------------------------------------------------------
local function LoadClient(isForever)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_ID = 1, 1
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", isForever and 16001 or 120105 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.GameEvent = isForever and { RegisterCamelotEvents = function() end } or nil
    _G.MSUF, _G.MSUF_NS = nil, nil
    local namespace = {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace.Client
end

Check(LoadClient(true).SupportsOnboardingScenes == false, "Forever must retire the onboarding scenes")
Check(LoadClient(false).SupportsOnboardingScenes == true, "Midnight must keep the onboarding scenes")

---------------------------------------------------------------------------
-- Lifecycles
---------------------------------------------------------------------------
-- Both modules read the raw SavedVariables at load, which is how they tell a
-- clean install from an upgrade. Absent variables are a fresh install; any
-- saved table is an upgrade, the only state with a pending release tour.
local function LoadLifecycles(client, savedVariables)
    _G.MSUF, _G.MSUF_NS = nil, nil
    _G.MSUF_DB, _G.MSUF_ActiveProfile = nil, nil
    _G.MSUF_GlobalDB = savedVariables
    local namespace = { Client = client }
    assert(loadfile(core .. "State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(core .. "State/MSUF_UpgradeHighlights.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace.FirstLoad6, namespace.UpgradeHighlights
end

local SHOWS = { SupportsOnboardingScenes = true, AddonVersion = "6.5-test" }
local RETIRED = { SupportsOnboardingScenes = false, AddonVersion = "6.5-test" }

---------------------------------------------------------------------------
-- First-start welcome
---------------------------------------------------------------------------
local firstLoad = LoadLifecycles(SHOWS, nil)
Check(firstLoad:GetInstallKind() == "fresh", "absent SavedVariables must read as a fresh install")
Check(firstLoad:ShouldShowDashboard() == true, "a fresh install greets the player on every other client")

firstLoad = LoadLifecycles(RETIRED, nil)
Check(firstLoad:GetInstallKind() == "fresh", "the client fact must not change install detection")
Check(firstLoad:ShouldShowDashboard() == false, "Forever must not greet the player on every login")
firstLoad:Reset("fresh")
Check(firstLoad:ShouldShowDashboard() == true, "/msuf firstload must still preview the welcome on Forever")
firstLoad:Complete("defaults")
Check(firstLoad:ShouldShowDashboard() == false, "finishing the preview retires the welcome again")

-- Retail carries no client table at all, so the gate has to fail open.
firstLoad = LoadLifecycles(nil, nil)
Check(firstLoad:ShouldShowDashboard() == true, "without a client table the welcome must stay")

---------------------------------------------------------------------------
-- Release highlights
---------------------------------------------------------------------------
local _, highlights = LoadLifecycles(SHOWS, { global = {} })
Check(highlights:ShouldShow() == true, "an upgrade offers the release tour on every other client")

local upgraded
upgraded, highlights = LoadLifecycles(RETIRED, { global = {} })
Check(upgraded:GetInstallKind() == "upgrade", "saved variables must still read as an upgrade")
Check(highlights:ShouldShow() == false, "Forever must not re-arm the release tour on every login")
highlights:ResetCurrent()
Check(highlights:ShouldShow() == true, "/msuf firstload must still preview the release tour on Forever")

_, highlights = LoadLifecycles(nil, { global = {} })
Check(highlights:ShouldShow() == true, "without a client table the release tour must stay")

print("forever_onboarding_scenes_smoke: ok")
