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
local UNAVAILABLE = "First-load actions are unavailable right now. Resume Guided Setup or reopen MSUF next session."
local ACTIONS = { "personalize", "import_profile", "use_defaults", "whats_new", "not_now", "full_settings" }

local function LoadFixture()
    _G.MSUF_DB = nil
    _G.MSUF_GlobalDB = nil
    _G.MSUF_ActiveProfile = "Default"
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
    local M = {
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

-- "Not now" owns the remainder of the session. The persisted `later` state is
-- eligible again next reload, but stale virtual actions cannot override it now.
do
    local MSUF, M = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    local ok = M.ExecuteFirstLoadDashboardAction("not_now")
    Check(ok == true, "not-now action failed")
    Equal(firstLoad:GetState().status, "later", "not-now did not persist later status")
    Check(firstLoad.deferredThisSession == true, "not-now did not defer this session")

    local staleOk, message = M.ExecuteFirstLoadDashboardAction("use_defaults")
    Check(staleOk == false, "deferred session accepted a stale FirstLoad action")
    Equal(message, UNAVAILABLE, "deferred action returned unclear status")
    Equal(firstLoad:GetState().status, "later", "deferred action changed persisted state")
end

print("PASS first-load action lifecycle: terminal/deferred guards and independent guided restart")
