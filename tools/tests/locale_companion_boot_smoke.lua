-- Boot real client graphs with a saved language independent of the text locale.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local Manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local addon = "MidnightSimpleUnitFrames_Locales"

-- Auto resolution pinned to 5b774c1b: all twelve supported client locales
-- retain themselves; unsupported ptPT falls through to English.
local baselineAuto = {
    enUS = "enUS", enGB = "enGB", deDE = "deDE", esES = "esES", esMX = "esMX", frFR = "frFR",
    itIT = "itIT", koKR = "koKR", ptBR = "ptBR", ruRU = "ruRU", zhCN = "zhCN", zhTW = "zhTW",
    ptPT = "enUS",
}

local function Boot(clientLocale, menuLocale, reason, ignoreConditions, combat)
    local world = World.New(root, flavor, { locale = clientLocale })
    world.env.TotemFrame = false -- no native widget in this startup-language fixture
    local calls, hints, executions, callbacks = 0, 0, 0, 0
    local suffix = world.client.tocSuffix
    local load = world.LoadFile
    function world:LoadFile(path, name, namespace)
        local ok, message = load(self, path, name, namespace)
        if path:match("/Locales/MSUF_Localization%.lua$") then
            local register = namespace.RegisterLocaleLoader
            namespace.RegisterLocaleLoader = function(locale, loader)
                return register(locale, function()
                    executions = executions + 1
                    loader()
                end)
            end
            namespace.RegisterLocaleCallback("boot-test", function() callbacks = callbacks + 1 end)
        end
        return ok, message
    end
    world.env.C_AddOns.LoadAddOn = function(name)
        assert(name == addon, "unexpected companion")
        assert(not world.env.InCombatLockdown(), "locale companion loaded in combat")
        calls = calls + 1
        assert(calls == 1, "reentrant finalization reloaded the companion")
        if reason then return false, reason end
        assert(world.core.FinalizeLocale() == menuLocale, "reentrant finalization changed the requested locale")
        assert(executions == 0 and callbacks == 0, "reentrant finalization ran loaders early")
        world:LoadGraph(addon, Manifest.Paths(root, suffix, nil, nil, addon), {})
        world:FireEvent("ADDON_LOADED", addon)
        return true
    end
    world.env.print = function(message)
        if tostring(message):find(addon, 1, true) then hints = hints + 1 end
    end
    if ignoreConditions then
        world.corePaths = Manifest.Paths(root, suffix)
        world.optionsPaths = Manifest.Paths(root, suffix, nil, nil, "MidnightSimpleUnitFrames_Options")
        world:LoadGraph("MidnightSimpleUnitFrames", world.corePaths, world.core)
        world:LoadGraph("MidnightSimpleUnitFrames_Options", world.optionsPaths, world.options)
    else
        world:Boot()
    end
    assert(not world:FirstFailure(), "chunk failed during boot")
    if combat then world:EnterCombat() end
    local profile = { _msufProfileSchema = 600, general = { menuLocale = menuLocale } }
    world:LoadSavedVariables("MidnightSimpleUnitFrames", {
        MSUF_DB = profile,
        MSUF_GlobalDB = { profiles = { Default = profile },
            char = { ["Tester-Realm"] = { activeProfile = "Default" } }, global = {} },
    })
    local clientMenuLocale = assert(baselineAuto[clientLocale])
    local requested = menuLocale == "auto" and clientMenuLocale or menuLocale
    local expected = (reason or combat) and clientMenuLocale or requested
    assert(world.core.LOCALE == expected, "saved locale resolved to " .. tostring(world.core.LOCALE))
    if clientLocale == "ptPT" and not ignoreConditions then
        local english, portuguese = false, false
        for _, path in ipairs(world.corePaths) do
            english = english or path:match("/Locales/enUS%.lua$") ~= nil
            portuguese = portuguese or path:match("/Locales/ptBR%.lua$") ~= nil
        end
        assert(english and not portuguese, "ptPT must load enUS instead of the unused ptBR menu pack")
    end
    local key = "Player Name Position"
    if expected == "deDE" then
        assert(world.core.L[key] == "Position des Spielernamens", "chosen pack did not provide German strings")
    elseif expected == "enUS" then
        assert(world.core.L[key] == key, "fallback did not provide English")
    end
    local needsCompanion = requested ~= clientMenuLocale and not ignoreConditions
    assert(calls == (needsCompanion and not combat and 1 or 0), "wrong companion load count")
    assert(hints == (needsCompanion and (reason or combat) and 1 or 0), "wrong fallback hint count")
    local retained = 0
    for locale, dictionary in pairs(world.core.LocaleRegistry) do
        retained = retained + 1
        assert(locale == expected and dictionary == world.core.L, "inactive pack retained")
    end
    assert(retained == 1, "active dictionary missing")
    assert(executions == 1 and callbacks == 1, "loader or callback did not execute exactly once")
    assert(not world.core.RegisterLocaleLoader("frFR", function() error("late loader ran") end), "late registration accepted")
    world.core.FinalizeLocale()
    assert(executions == 1 and callbacks == 1, "loader or callback repeated")
    assert(calls == (needsCompanion and not combat and 1 or 0), "finalize reloaded companion")
    assert(hints == (needsCompanion and (reason or combat) and 1 or 0), "fallback hint repeated")
    assert(world.env.MSUF_DB.general.menuLocale == menuLocale, "saved language mutated")
    if menuLocale == "auto" then
        local menu = assert(world.core.MSUF2)
        local prompts, hidden = 0, 0
        menu.ShowPrompt = function() prompts = prompts + 1 end
        menu.HidePrompt = function() hidden = hidden + 1 end
        assert(menu.GetLocaleSelection() == "auto", "auto selection was not preserved")
        assert(menu.ResolveLocaleSelection("auto") == clientMenuLocale, "Follow Blizzard differs from baseline")
        for i = 1, 2 do
            local active, selection, reload = menu.ApplyLocaleSelection("auto")
            assert(active == clientMenuLocale and selection == "auto" and not reload,
                clientLocale .. ": Follow Blizzard requested a reload after auto startup")
            assert(not world.core.PendingLocale and not world.core.LocaleReloadRequired, "pending reload loop")
        end
        assert(prompts == 0 and hidden == 2, "auto displayed a reload prompt")
    end
end

Boot("ptPT", "auto")
Boot("ptPT", "auto", "DISABLED")
Boot("ptPT", "auto", nil, true)
for _, locale in ipairs({ "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT",
    "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
    Boot(locale, "auto")
end
Boot("ptPT", "ptBR")
Boot("ptPT", "ptBR", "MISSING")
Boot("enUS", "enUS")
Boot("deDE", "deDE")
Boot("enUS", "deDE")
Boot("deDE", "enUS")
Boot("enUS", "deDE", "MISSING")
Boot("enUS", "deDE", "DISABLED")
Boot("deDE", "enUS", "MISSING")
Boot("enUS", "deDE", nil, true)
Boot("enUS", "deDE", nil, false, true)
print("PASS locale companion boot: " .. flavor .. " (26 cases; baseline auto parity, no reload loop, companion lifecycle)")
