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
    local effects = { invalidates = 0, selects = 0, closes = 0, imports = 0, generalWrites = 0, applyFlushes = 0 }
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
        GetGeneralDB = function()
            _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
            _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
            return _G.MSUF_DB.general, _G.MSUF_DB
        end,
        SetGeneralValue = function(key, value)
            local general = M.GetGeneralDB()
            if general[key] == value then return false end
            general[key] = value
            effects.generalWrites = effects.generalWrites + 1
            return true
        end,
        ApplyService = {
            Flush = function()
                effects.applyFlushes = effects.applyFlushes + 1
                return true
            end,
        },
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
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_UpgradeHighlights.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_GuidedTour.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_FirstLoad.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_GuidedTour.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_UpgradeHighlights.lua"))("MidnightSimpleUnitFrames", MSUF)

    return MSUF, M, registered, effects
end

-- Frame placement must not start on an implicit default. The guided Edit Mode
-- step records an explicit answer and writes the real global Unitframe anchor
-- setting before any movers are opened.
do
    local MSUF, M, _, effects = LoadFixture({ db = { general = { anchorToCooldown = false } } })
    Check(MSUF.GuidedTour6:Start("Default", "edit_mode") == true, "guided tour did not start at Edit Mode")
    Equal(M.GetGuidedCooldownAnchorDecision(), nil, "Edit Mode inferred an anchor choice without user input")
    Check(M.IsGuidedEditModePlacementUnlocked() == false, "frame placement unlocked before the anchor choice")
    Check(M.IsGuidedEditModePlacementComplete() == false, "Edit Mode placement completed without a real move")
    Check(M.SetGuidedCooldownAnchorDecision("cooldown") == true, "Cooldown Manager anchor choice failed")
    Equal(_G.MSUF_DB.general.anchorToCooldown, true, "Cooldown Manager choice did not enable the real anchor setting")
    Equal(M.GetGuidedCooldownAnchorDecision(), "cooldown", "Cooldown Manager choice was not persisted in tour state")
    Check(M.IsGuidedEditModePlacementUnlocked() == true, "frame placement stayed locked after the anchor choice")
    M.EditModeLifecycleStatus = function() return { active = false, combatLocked = false } end
    Check(M.ShouldShowGuidedEditModeOpenCue() == true, "toolbar Edit Mode cue stayed hidden after the anchor choice")
    M.EditModeLifecycleStatus = function() return { active = true, combatLocked = false } end
    Check(M.ShouldShowGuidedEditModeOpenCue() == false, "toolbar Edit Mode cue remained visible after opening Edit Mode")
    M.EditModeLifecycleStatus = function() return { active = false, combatLocked = false } end
    local advanced, blockedReason = M.RunGuidedTourStep("next")
    Check(advanced == false, "guided Edit Mode advanced before a real move")
    Equal(blockedReason, "guided_edit_mode_move_required", "blocked Edit Mode advance returned the wrong reason")
    Equal(MSUF.GuidedTour6:GetState().currentStageId, "edit_mode", "blocked Edit Mode advance changed stages")
    Check(M.NotifyGuidedEditModeMoved("player") == true, "real Edit Mode movement was not accepted")
    Check(M.IsGuidedEditModePlacementComplete() == true, "Edit Mode movement did not complete placement")
    Check(M.ShouldShowGuidedEditModeOpenCue() == false, "toolbar Edit Mode cue returned after placement completed")
    Equal(MSUF.GuidedTour6:GetState().preferences.editModeMovedKey, "player", "moved frame key was not persisted")
    Check(M.SetGuidedCooldownAnchorDecision("independent") == true, "independent anchor choice failed")
    Equal(_G.MSUF_DB.general.anchorToCooldown, false, "independent choice did not disable the Cooldown Manager anchor")
    Equal(M.GetGuidedCooldownAnchorDecision(), "independent", "independent choice was not persisted in tour state")
    Check(M.IsGuidedEditModePlacementComplete() == false, "changing the anchor did not require fresh placement")
    Check(M.NotifyGuidedEditModeMoved("target") == true, "fresh placement after anchor change was rejected")
    Check(M.IsGuidedEditModePlacementComplete() == true, "fresh placement after anchor change was not recorded")
    Equal(effects.generalWrites, 2, "anchor choices did not use the real general setting mutation path")
    Equal(effects.applyFlushes, 2, "anchor choices were not applied before frame placement")
    Check(M.SetGuidedCooldownAnchorDecision("invalid") == false, "invalid anchor choice was accepted")
end

-- Menu Basics and Edit Mode are consecutive special stages that render
-- different bodies into the same guided_setup page key. Advancing must rebuild
-- the invalidated active page immediately; a later resize must not be required.
do
    local MSUF, M, _, effects = LoadFixture()
    Check(MSUF.GuidedTour6:Start("Default", "menu_basics") == true, "guided tour did not start at Menu Basics")
    Check(MSUF.GuidedTour6:SetPreference("playstyle", "dungeons") == true, "playstyle fixture preference failed")
    Check(MSUF.GuidedTour6:SetPreference("informationStyle", "balanced") == true, "information-style fixture preference failed")
    M.frame = { IsShown = function() return true end }
    M.activeKey = "guided_setup"
    M.cache = { guided_setup = { wrapper = {} } }
    M.InvalidatePage = function(key)
        effects.invalidates = effects.invalidates + 1
        M.cache[key] = nil
    end
    M.SelectPage = function(key)
        effects.selects = effects.selects + 1
        effects.lastPage = key
        M.activeKey = key
        return true
    end

    Check(M.RunGuidedTourStep("next") == true, "Menu Basics did not advance")
    Equal(MSUF.GuidedTour6:GetState().currentStageId, "edit_mode", "Menu Basics advanced to the wrong stage")
    Equal(effects.invalidates, 1, "same-page guided transition did not invalidate the old body")
    Equal(effects.selects, 1, "same-page guided transition did not rebuild immediately")
    Equal(effects.lastPage, "guided_setup", "same-page guided transition rebuilt the wrong page")
    M.cache.guided_setup = { wrapper = {} }
    Check(M.RunGuidedTourStep("back") == true, "Edit Mode did not return to Menu Basics")
    Equal(MSUF.GuidedTour6:GetState().currentStageId, "menu_basics", "Edit Mode returned to the wrong stage")
    Equal(effects.invalidates, 2, "reverse same-page guided transition did not invalidate the Edit Mode body")
    Equal(effects.selects, 2, "reverse same-page guided transition did not rebuild immediately")
end

-- Spell Icons own a complete guided stage on the Group Auras page. The normal
-- Aura stage excludes that section, while the dedicated stage includes its
-- selector and preview controls as well as persistent settings/actions.
do
    local _, M = LoadFixture()
    Check(M.IsGuidedTourSectionIncluded("gf_spell_icons", "si") == true, "Spell Icons stage lost the spell-indicator section")
    Check(M.IsGuidedTourSectionIncluded("gf_spell_icons", "auras") == false, "Spell Icons stage includes unrelated Aura sections")
    Check(M.IsGuidedTourSectionIncluded("gf_auras", "si") == false, "Group Auras stage still duplicates Spell Icons")
    Check(M.IsGuidedTourSectionIncluded("gf_auras", "auras") == true, "Group Auras stage lost the Aura workspace")
    Check(M.GuidedTourIncludesEphemeralControls("gf_spell_icons") == true, "Spell Icons stage omits selector or preview controls")
    Check(M.GuidedTourIncludesEphemeralControls("gf_auras") == false, "ordinary Group Auras stage unexpectedly includes ephemeral controls")
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

    local ok, message = MSUF.MSUF2.ExecuteFirstLoadDashboardAction("use_defaults")
    Check(ok == false, "generic continue action bypassed the upgrade highlight warning")
    Contains(message, "release highlights", "blocked generic action did not explain the upgrade flow")
    Equal(firstLoad:GetState().status, "pending", "blocked generic action changed onboarding")
end

-- Existing 5.71 profiles receive the release highlights before the generic
-- first-load chooser. Reviewing or skipping the tour never changes the profile
-- and terminally closes only this release's one-time lifecycle.
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
    local highlights, firstLoad = MSUF.UpgradeHighlights, MSUF.FirstLoad6
    Check(highlights:ShouldShow() == true, "5.71 profile did not receive the upgrade highlight tour")
    local releaseKey, spec, record = highlights:GetCurrent()
    Equal(releaseKey, "6.0", "wrong release highlight tour selected")
    Equal(#spec.highlights, 7, "6.0 highlight tour lost its curated seven-item contract")
    Equal(spec.highlights[1].id, "custom_aura_tracking", "first 6.0 highlight is not the new Unitframe Custom Aura gameplay feature")
    Equal(spec.highlights[1].pageKey, "uf_player", "Custom Aura highlight does not open a supported Unitframe")
    Equal(spec.highlights[1].route.unitAuraTab, "custom1", "Custom Aura highlight does not select a Custom lane")
    Equal(spec.highlights[1].route.unitAuraTool, "whitelist", "Custom Aura highlight does not open its exact-spell whitelist")
    Equal(spec.highlights[1].route.accordion, "uf_player:auras", "Custom Aura highlight does not expand the Unitframe Aura workspace")
    Equal(spec.highlights[2].id, "auras3_rework", "second 6.0 highlight is not the full Auras3 menu rework")
    local healthText = spec.highlights[4]
    Equal(healthText.id, "health_text", "fourth 6.0 highlight is not the HP text editor")
    Equal(healthText.pageKey, "uf_player", "HP values highlight does not open a Unitframe editor")
    Equal(healthText.route.unit, "player", "HP values highlight does not target Player")
    Equal(healthText.route.unitTextTab, "hp", "HP values highlight does not select the HP Text tab")
    Equal(healthText.route.accordion, "uf_player:text", "HP values highlight does not expand the Text editor")
    MSUF.MSUF2.ApplyUpgradeHighlightTargetRoute(healthText)
    Equal(MSUF.MSUF2.unitTextTabSelection.player, "hp", "HP highlight route did not apply the HP Text tab")
    Equal(MSUF.MSUF2.accordionState["uf_player:text"], true, "HP highlight route did not open the Text editor")
    Equal(record.status, "pending", "upgrade highlight tour did not start pending")

    Check(highlights:Start() == true, "upgrade highlight tour did not start")
    Equal(record.status, "active", "started highlight tour is not active")
    Equal(record.index, 1, "highlight tour did not start at the first item")
    Check(highlights:Advance("reviewed") == true, "first highlight could not be reviewed")
    Equal(record.index, 2, "reviewed highlight did not advance")
    Equal(record.outcomes.custom_aura_tracking, "reviewed", "highlight outcome was not persisted")
    Check(highlights:RequestSkip() == true, "skip warning could not be requested")
    Equal(record.status, "skip_warning", "skip did not require the consequence warning")
    Equal(record.pendingSkipCount, 6, "skip warning did not count only unreviewed highlights")
    Check(highlights:CancelSkip() == true, "skip warning could not return to the tour")
    Equal(record.status, "active", "cancelled skip did not resume the tour")
    Check(highlights:RequestSkip() == true, "second skip warning could not be requested")
    Check(highlights:ConfirmSkip() == true, "confirmed highlight skip failed")
    Equal(record.status, "skipped", "confirmed release tour was not persisted as skipped")
    Equal(record.skippedCount, 6, "confirmed skip lost the remaining-highlight count")
    Check(highlights:ShouldShow() == false, "skipped release tour resurfaced")
    Equal(firstLoad:GetState().status, "completed", "skipping release highlights did not close generic onboarding")
end

-- A genuine 6.0 fresh install baselines the current release. Adding a later
-- release to the registry is enough to queue its own independent tour.
do
    local MSUF = LoadFixture()
    local highlights, data = MSUF.UpgradeHighlights, MSUF.UpgradeHighlightData
    Check(highlights:ShouldShow() == false, "fresh 6.0 install incorrectly received the upgrade tour")
    Equal(highlights:GetState().releases["6.0"].status, "baseline", "fresh install did not baseline 6.0")

    data.releaseOrder[#data.releaseOrder + 1] = "6.1"
    data.releases["6.1"] = {
        title = "6.1 test highlights",
        highlights = { { id = "future", title = "Future release", pageKey = "home" } },
    }
    Check(highlights:ShouldShow() == true, "future release was not queued from the release registry")
    local releaseKey, _, record = highlights:GetCurrent()
    Equal(releaseKey, "6.1", "future release selection did not respect release order")
    Equal(record.status, "pending", "future release was not initialized pending")
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

-- The debug command must be able to preview the fresh-install scene even when
-- the currently active profile is named/imported. Normal stale-state recovery
-- above remains enabled for organically detected fresh installs.
do
    local MSUF = LoadFixture()
    local firstLoad = MSUF.FirstLoad6
    _G.MSUF_ActiveProfile = "Imported Profile"
    Check(firstLoad:Reset("fresh") == true, "fresh debug reset failed with a named profile")
    Equal(firstLoad:GetState().installReason, "debug_forced_fresh", "fresh debug reset lost its force marker")
    Check(firstLoad:ShouldShowDashboard() == true, "named profile immediately retired the forced fresh preview")
    Equal(firstLoad:GetState().status, "pending", "forced fresh preview did not stay pending")
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
