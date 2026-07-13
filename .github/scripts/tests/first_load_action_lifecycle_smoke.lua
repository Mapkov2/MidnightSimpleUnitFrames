-- Regression: one-time FirstLoad actions cannot revive completed/dismissed
-- onboarding, while the independent Guided Setup remains restartable.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Contains(value, needle, message)
    value = tostring(value or "")
    if not value:find(needle, 1, true) then
        error((message or "text mismatch") .. ": missing " .. tostring(needle) .. " in " .. value, 2)
    end
end

local CLOSED = "First-load onboarding is already closed. Use Guided Setup on the Dashboard to run the tour again."
local UNAVAILABLE = "First-load actions are unavailable right now. Use Guided Setup on the Dashboard instead."
local ACTIONS = { "personalize", "import_profile", "use_defaults", "whats_new", "not_now", "full_settings" }

local function LoadFixture(saved)
    saved = type(saved) == "table" and saved or {}
    _G.MSUF_DB = saved.db
    _G.MSUF_GlobalDB = saved.globalDB
    _G.MSUF_ActiveProfile = saved.activeProfile or "Default"
    _G.MSUF = nil
    _G.MSUF_NS = nil
    _G.MSUF2 = nil
    _G.C_AddOns = {
        GetAddOnMetadata = function() return "6.0-test" end,
    }
    _G.time = function() return 123456 end
    _G.UnitName = function() return "Tester" end
    _G.issecretvalue = function() return false end
    _G.CreateFrame = function() error("unexpected frame creation during lifecycle smoke", 2) end

    local MSUF = {}
    local registered = {}
    local effects = { invalidates = 0, selects = 0, closes = 0, imports = 0 }
    -- Forward declaration: SetMenuStateValue/GetPersistentMenuStateTable close
    -- over M, which is not in scope inside its own table constructor.
    local M
    M = {
        Tr = function(text) return text end,
        BlockCombatAction = function() return false end,
        RegisterVirtualRuntimeControl = function(record)
            registered[record.actionKey] = record
            return true
        end,
        RegisterPage = function() return true end,
        InvalidatePage = function()
            effects.invalidates = effects.invalidates + 1
        end,
        SelectPage = function(_, pageKey)
            -- Support both dot and colon style stubs without coupling the test
            -- to the caller's invocation convention.
            effects.selects = effects.selects + 1
            effects.lastPage = pageKey or _
            return true
        end,
        HideSlashMenuAndMinibar = function()
            effects.closes = effects.closes + 1
            return true
        end,
        SetMenuStateValue = function(key, value)
            M[key] = value
        end,
        GetPersistentMenuStateTable = function(key)
            M[key] = type(M[key]) == "table" and M[key] or {}
            return M[key]
        end,
        SearchBridge = {
            OpenSearchTarget = function()
                effects.imports = effects.imports + 1
                return true, true
            end,
        },
    }
    MSUF.MSUF2 = M
    _G.MSUF = MSUF
    _G.MSUF_NS = MSUF
    _G.MSUF2 = M

    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_GuidedTour.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_FirstLoad.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"))("MidnightSimpleUnitFrames", MSUF)

    return MSUF, M, registered, effects
end

-- MSUF 5.71 used MSUF_DB plus MSUF_GlobalDB.profiles/chars without a profile
-- schema marker. That untouched SavedVariables shape must select the upgrade
-- scene and offer the existing profile instead of fresh defaults.
do
    local legacyProfile = { general = { barTexture = "MSUF Flat" }, player = { width = 220 } }
    local MSUF = LoadFixture({
        db = legacyProfile,
        globalDB = {
            profiles = { Raid = legacyProfile },
            chars = { ["Tester-Realm"] = { activeProfile = "Raid" } },
        },
        activeProfile = "Raid",
    })
    local firstLoad = MSUF.FirstLoad6
    local state, detection = firstLoad:GetState(), firstLoad:GetDetection()
    Equal(state.installKind, "upgrade", "5.71 profile was classified as a fresh install")
    Equal(state.installReason, "legacy_saved_profiles", "5.71 profile stored the wrong detection reason")
    Check(detection.existingProfile == true, "5.71 existing profile was not detected")
    Check(detection.legacyProfile == true, "5.71 schema-less profile was not classified as legacy")
    Check(firstLoad:ShouldShowDashboard() == true, "5.71 profile lost the one-time continue choice")

    local ok = MSUF.MSUF2.ExecuteFirstLoadDashboardAction("use_defaults")
    Check(ok == true, "continue-current-profile action failed for 5.71 profile")
    Equal(firstLoad:GetState().status, "completed", "continue-current-profile did not complete onboarding")
    Equal(firstLoad:GetState().step, "current_profile", "upgrade action was recorded as fresh defaults")
end

-- Very old installations may only have the single MSUF_DB table. They are
-- still existing users and must receive the same non-destructive upgrade path.
do
    local MSUF = LoadFixture({ db = { general = { fontSize = 12 } } })
    local state, detection = MSUF.FirstLoad6:GetState(), MSUF.FirstLoad6:GetDetection()
    Equal(state.installKind, "upgrade", "pre-profile-system DB was classified as fresh")
    Equal(state.installReason, "legacy_saved_profile", "old single DB stored the wrong detection reason")
    Check(detection.existingProfile == true, "old single DB was not detected as an existing profile")
end

-- A stale fresh marker from an earlier beta/debug run must not win over an
-- untouched schema-less 5.71 profile that is now present in SavedVariables.
do
    local legacyProfile = { general = { healthTexture = "Old Texture" } }
    local MSUF = LoadFixture({
        db = legacyProfile,
        globalDB = {
            global = {
                firstLoad6 = {
                    schema = 1,
                    revision = 1,
                    installKind = "fresh",
                    status = "pending",
                    step = "welcome",
                    firstSeenVersion = "6.0-beta-test",
                },
            },
            profiles = { Default = legacyProfile },
        },
    })
    local state = MSUF.FirstLoad6:GetState()
    Equal(state.installKind, "upgrade", "stale fresh marker overruled a legacy profile")
    Equal(state.installReason, "reclassified_legacy_saved_profiles", "legacy reclassification reason was lost")
    Check(MSUF.FirstLoad6:ShouldShowDashboard() == true, "reclassified legacy profile did not show continue choice")
end

local function ResetEffects(effects)
    effects.invalidates = 0
    effects.selects = 0
    effects.closes = 0
    effects.imports = 0
    effects.lastPage = nil
end

-- Completing the welcome via defaults makes every stale/virtual FirstLoad
-- action unavailable before it can navigate, start a tour, or mutate state.
do
    local MSUF, M, registered, effects = LoadFixture()
    local firstLoad, tour = MSUF.FirstLoad6, MSUF.GuidedTour6
    local ok = M.ExecuteFirstLoadDashboardAction("use_defaults")
    Check(ok == true, "pending defaults action failed")
    Equal(firstLoad:GetState().status, "completed", "defaults did not complete onboarding")
    ResetEffects(effects)

    for i = 1, #ACTIONS do
        local actionOk, message = M.ExecuteFirstLoadDashboardAction(ACTIONS[i])
        Check(actionOk == false, "terminal action unexpectedly succeeded: " .. ACTIONS[i])
        Equal(message, CLOSED, "terminal action returned unclear status: " .. ACTIONS[i])
        Equal(firstLoad:GetState().status, "completed", "terminal action changed completed status")
    end
    Equal(tour:GetState().status, "inactive", "blocked FirstLoad action started the tour")
    Equal(effects.invalidates, 0, "blocked FirstLoad action invalidated a page")
    Equal(effects.selects, 0, "blocked FirstLoad action navigated")
    Equal(effects.closes, 0, "blocked FirstLoad action closed the menu")
    Equal(effects.imports, 0, "blocked FirstLoad action opened profile import")

    local virtual = assert(registered["first_load.personalize"], "personalize virtual action was not registered")
    local virtualOk, virtualError = pcall(virtual.command.set)
    Check(virtualOk == false, "terminal virtual action did not fail")
    Contains(virtualError, CLOSED, "terminal virtual action lost the lifecycle status")

    local lifecycleStarted, reason = firstLoad:Start("guided_tour")
    Check(lifecycleStarted == false, "terminal FirstLoad lifecycle was revived directly")
    Equal(reason, "completed", "completed lifecycle guard returned the wrong reason")

    -- Normal Dashboard/slash Guided Setup is a separate controller: it starts
    -- its own state even though FirstLoad correctly refuses to become active.
    local guidedStarted = M.StartGuidedTour({ source = "dashboard", restart = true })
    Check(guidedStarted == true, "independent guided tour did not restart")
    Equal(tour:GetState().status, "active", "guided tour restart did not become active")
    Equal(firstLoad:GetState().status, "completed", "guided tour restart revived FirstLoad")
    Check(firstLoad:ShouldShowDashboard() == false, "guided restart resurfaced the one-time dashboard")
end

-- Dismissal is equally terminal, but still permits the separate tour launcher.
do
    local MSUF, M = LoadFixture()
    local firstLoad, tour = MSUF.FirstLoad6, MSUF.GuidedTour6
    local ok = M.ExecuteFirstLoadDashboardAction("full_settings")
    Check(ok == true, "pending full-settings action failed")
    Equal(firstLoad:GetState().status, "dismissed", "full settings did not dismiss onboarding")

    local staleOk, message = M.ExecuteFirstLoadDashboardAction("import_profile")
    Check(staleOk == false, "dismissed onboarding accepted profile import")
    Equal(message, CLOSED, "dismissed onboarding returned unclear status")
    local lifecycleStarted, reason = firstLoad:Start("import")
    Check(lifecycleStarted == false, "dismissed FirstLoad lifecycle was revived directly")
    Equal(reason, "dismissed", "dismissed lifecycle guard returned the wrong reason")

    Check(M.StartGuidedTour({ source = "dashboard", restart = true }) == true,
        "guided tour could not start after FirstLoad dismissal")
    Equal(tour:GetState().status, "active", "tour stayed inactive after dismissal")
    Equal(firstLoad:GetState().status, "dismissed", "tour restart changed dismissed FirstLoad status")
end

-- Any explicit choice retires the one-time welcome scene permanently: "Not now"
-- persists as `later`, stays hidden across reloads, and stale virtual actions
-- cannot override it.
do
    local MSUF, M = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    local ok = M.ExecuteFirstLoadDashboardAction("not_now")
    Check(ok == true, "not-now action failed")
    Equal(firstLoad:GetState().status, "later", "not-now did not persist later status")
    Check(firstLoad.deferredThisSession == true, "not-now did not defer this session")
    Check(firstLoad:ShouldShowDashboard() == false, "not-now left the welcome scene visible")

    local staleOk, message = M.ExecuteFirstLoadDashboardAction("use_defaults")
    Check(staleOk == false, "deferred session accepted a stale FirstLoad action")
    Equal(message, UNAVAILABLE, "deferred action returned unclear status")
    Equal(firstLoad:GetState().status, "later", "deferred action changed persisted state")

    -- Simulated reload: the state module re-reads the persisted SavedVariables.
    -- A chosen route must keep the welcome scene retired in the next session.
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", MSUF)
    local reloaded = MSUF.FirstLoad6
    Equal(reloaded:GetState().status, "later", "reload lost the persisted later status")
    Check(reloaded.deferredThisSession == false, "reload kept the session-only defer flag")
    Check(reloaded:ShouldShowDashboard() == false, "welcome scene resurfaced after reload despite a chosen route")
end

-- Viewing the changelog counts as a choice too and survives a reload, while an
-- untouched (pending) install keeps offering the welcome scene next session.
do
    local MSUF, M = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    Check(firstLoad:ShouldShowDashboard() == true, "pending install did not offer the welcome scene")
    Check(M.ExecuteFirstLoadDashboardAction("whats_new") == true, "whats-new action failed")
    Equal(firstLoad:GetState().status, "later", "whats-new did not persist later status")

    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", MSUF)
    Check(MSUF.FirstLoad6:ShouldShowDashboard() == false, "welcome scene resurfaced after reload despite viewing the changelog")

    -- `/msuf firstload` relies on Reset to deliberately re-arm the retired
    -- welcome scene for testing, including forcing the install-kind variant.
    Check(MSUF.FirstLoad6:Reset("fresh") == true, "reset helper failed")
    Equal(MSUF.FirstLoad6:GetState().status, "pending", "reset did not re-arm the pending status")
    Equal(MSUF.FirstLoad6:GetInstallKind(), "fresh", "reset did not force the fresh install kind")
    Check(MSUF.FirstLoad6:ShouldShowDashboard() == true, "reset did not resurface the welcome scene")
    Check(MSUF.FirstLoad6:Reset("upgrade") == true, "upgrade reset helper failed")
    Equal(MSUF.FirstLoad6:GetInstallKind(), "upgrade", "reset did not force the upgrade install kind")
end

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function Count(value, needle)
    local count, from = 0, 1
    while true do
        local at = value:find(needle, from, true)
        if not at then return count end
        count = count + 1
        from = at + #needle
    end
end

-- A successful import launched directly from the Profiles page must retire the
-- welcome scene too; it does not require the welcome import card to be clicked.
do
    local MSUF = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    Check(firstLoad:CompleteProfileImport() == true, "direct profile import did not complete onboarding")
    Equal(firstLoad:GetState().status, "completed", "direct profile import left onboarding pending")
    Equal(firstLoad:GetState().step, "import", "direct profile import stored the wrong completion step")
    Check(firstLoad:ShouldShowDashboard() == false, "welcome scene remained visible after direct profile import")

    firstLoad:Reset("fresh")
    Check(firstLoad:Start("guided_tour") == true, "guided-tour fixture did not start")
    local completed, reason = firstLoad:CompleteProfileImport()
    Check(completed == false, "profile import completion interrupted an active guided tour")
    Equal(reason, "active", "guided-tour import guard returned the wrong reason")
    Equal(firstLoad:GetState().step, "guided_tour", "guided-tour step changed during import completion guard")
end

-- Recover the exact stale state reported in-game: a fresh pending lifecycle
-- already has the named profile that the import created and activated.
do
    local MSUF = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    _G.MSUF_ActiveProfile = "Imported Profile"
    Check(firstLoad:ShouldShowDashboard() == false, "named imported profile did not retire stale onboarding")
    Equal(firstLoad:GetState().status, "completed", "named imported profile left stale onboarding pending")
    Equal(firstLoad:GetState().step, "import_recovered", "stale imported profile stored the wrong recovery step")
    Check(_G.MSUF_GlobalDB.global.firstLoad6ProfileImported == true, "import recovery receipt was not persisted")
end

-- The completion hook belongs to the shared data mutation boundaries, not a
-- single menu page, so compact, legacy/UUF, and external imports cannot bypass it.
do
    local profiles = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
    Check(Count(profiles, "MSUF.ProfileIOCompleteFirstLoadImport()") >= 6,
        "not every successful profile mutation records first-load completion")
    Check(not profiles:find("CompletePendingFirstLoadImport", 1, true),
        "first-load completion is still coupled to the Menu2 profile page")
end

print("PASS first-load action lifecycle: terminal/deferred guards and independent guided restart")
