-- Exercise the login warning through the real core and Options load graphs.
local root, flavor = assert(arg[1]), assert(arg[2])
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local key = "MSUF_PROFILE_CHECK_70"
local options = "MidnightSimpleUnitFrames_Options"
local function OldAccount()
    return {
        profiles = { Raid = { _msufProfileSchema = 600, player = { width = 321 }, general = {} } },
        char = { ["Tester-Realm"] = { activeProfile = "Raid" } },
    }
end
local function Install(world)
    MW.InstallNativeUnitInputs(world)
    local env = world.env
    env.UnitName = function() return "Tester" end
    env.GetRealmName = function() return "Realm" end
end

local function EnterWorld(world)
    local callbacks = {}
    local scheduler = world.core.Scheduler
    local scheduleAfter = scheduler.ScheduleAfter
    scheduler.ScheduleAfter = function(id, _, callback)
        if id == key then callbacks[#callbacks + 1] = callback end
    end
    world:FireEvent("PLAYER_ENTERING_WORLD", true, false)
    scheduler.ScheduleAfter = scheduleAfter
    for _, callback in ipairs(callbacks) do callback() end
    return #callbacks
end

for _, saved in ipairs({ {}, { MSUF_GlobalDB = {
    profiles = OldAccount().profiles, _pre70ProfileBackup = {},
} } }) do
    local world = Corpus.NewWorld(root, flavor, "Tester-Realm", MW.InstallNativeUnitInputs)
    Corpus.Login(world, saved)
    assert(EnterWorld(world) == 0, "non-upgrade account scheduled the warning")
    assert(world.env.MSUF_GlobalDB.global.profileCheck70.status == "baseline", "non-upgrade account was armed")
    assert(not world.core.UI.IsPromptShown(key), "non-upgrade account saw the warning")
end

local enabled, loaded, attempts = false, false, 0
local account = OldAccount()
local function InstallLoader(world)
    local loadGraph, env = world.LoadGraph, world.env
    world:LoadSavedVariables("MidnightSimpleUnitFrames", { MSUF_GlobalDB = account })
    world.widgets:ClearTimers()
    env.C_AddOns.IsAddOnLoaded = function(addon)
        local ready = addon == options and loaded
        return ready, ready
    end
    env.C_AddOns.LoadAddOn = function(addon)
        assert(addon == options and not loaded, "unexpected addon load")
        attempts = attempts + 1
        if not enabled then return false, "DISABLED" end
        loadGraph(world, addon, world.optionsPaths, world.options)
        local failure = world:FirstFailure()
        assert(not failure, failure and (failure.file .. ": " .. failure.message))
        loaded = true
        world.core.MSUF2.ApplyService.Flush = function() return true end
        return true
    end
    function world:LoadGraph(addon, paths, ns)
        if addon ~= options then return loadGraph(self, addon, paths, ns) end
    end
end

local mw = MW.Open(root, flavor, {
    open = false, keepFlush = true, clientScriptBindings = true, beforeCore = Install, beforeOptions = InstallLoader,
})
local world, core, menu = mw.world, mw.core, mw.M
local show, prompt = core.UI.ShowPrompt
core.UI.ShowPrompt = function(id, spec, style)
    local frame = show(id, spec, style)
    if id == key then prompt = frame end
    return frame
end
local record = account.global.profileCheck70
assert(record.status == "pending")
assert(mw.env.MSUF_ActiveProfile == "Raid" and mw.env.MSUF_DB.player.width == 321, "legacy profile fixture failed to bind")
assert(EnterWorld(world) == 1, "upgrade did not schedule the warning on login")
world.widgets:ClearTimers()
assert(prompt and prompt:IsShown() and prompt._msufPromptText:GetText():find("Raid", 1, true))
assert(attempts == 0 and not loaded, "login eagerly loaded Options")
local openProfiles = prompt._msufPromptButtons[1]
openProfiles:Click()
assert(attempts == 1 and record.status == "pending" and prompt:IsShown(), "load refusal consumed the warning")

enabled = true
openProfiles:Click()
assert(attempts == 2 and loaded and not menu.frame and record.status == "pending", "first click did not defer the cold window build")
-- Model lockdown at the deferred click without dispatching unrelated frame updates.
world.widgets.inCombat = true
world.widgets:RunTimers()
assert(not menu.frame and record.status == "pending" and prompt:IsShown(), "combat before open consumed the warning")
world.widgets.inCombat = false
local selectPage = menu.SelectPage
menu.SelectPage = function(page)
    assert(page == "profiles")
    return false
end
openProfiles:Click()
assert(record.status == "pending" and prompt:IsShown(), "failed Profiles navigation consumed the warning")
menu.SelectPage = selectPage
openProfiles:Click()
world.widgets:RunTimers()
assert(menu.activeKey == "profiles" and menu.frame:IsShown() and menu.cache.profiles.wrapper:IsShown(), "button did not show Profiles")
assert(record.status == "done" and record.result == "opened" and not prompt:IsShown(), "successful navigation did not retire the warning")
assert(mw.env.MSUF_ActiveProfile == "Raid" and mw.env.MSUF_DB.player.width == 321, "navigation changed the active profile")
assert(not core.FirstLoad6.ShowProfileCheck(), "answered warning returned in the same session")

local reloaded = Corpus.NewWorld(root, flavor, "Tester-Realm", MW.InstallNativeUnitInputs)
Corpus.Login(reloaded, { MSUF_GlobalDB = account })
assert(EnterWorld(reloaded) == 0, "answered warning was scheduled on the next login")
assert(not reloaded.core.UI.IsPromptShown(key), "answered warning returned on the next login")
print("profile_upgrade_prompt_smoke: " .. flavor .. " login scope, cold open, retry, and one-time completion passed")
