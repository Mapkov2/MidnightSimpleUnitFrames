-- integration_profile_reads_after_login_smoke.lua <repoRoot> <case>
--
-- The client loads the SavedVariables after every Lua file of the addon ran,
-- so a setting read while a file loads sees no saved profile. Three
-- integrations used to act on such a read while the file loaded, when their
-- partner addon was already present:
--   mapko     The MapkoSkin menu skin (MapkoSkin loads first, as an
--             OptionalDep) connected and decided "skin on" at load, so the
--             "Use MapkoSkin for MSUF menus" opt-out was ignored after every
--             /reload. It connects at PLAYER_LOGIN and follows the profile
--             MSUF binds for the character (MSUF_InitProfiles).
--   analytics Telemetry read the account opt-out at load.
--   anchors   A cooldown anchor provider that was already loaded (ArcUI here)
--             was acquired at load, which reads the profile's anchor settings.
-- Real core files in a Mainline client world; plain Lua 5.1, repo root as
-- arg 1, case as arg 2.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local case = assert(arg[2], "case required: mapko, analytics or anchors")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function LoginHandler(world, fileName)
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame:GetScript("OnEvent")
        if handler and frame:IsEventRegistered("PLAYER_LOGIN")
            and debug.getinfo(handler, "S").source:find(fileName, 1, true) then
            return function() handler(frame, "PLAYER_LOGIN") end
        end
    end
    error("no PLAYER_LOGIN listener in " .. fileName)
end

local function SingleFileWorld()
    local world = World.New(root, "Mainline")
    local env, ns = world.env, world.core
    ns.ExportPublic = function(name, value) env[name] = value end
    ns.Optional = function(name) return rawget(env, name) end
    ns.Require = function(name) return assert(rawget(env, name), "missing " .. name) end
    ns.Util = { InCombat = function() return world.widgets:IsInCombat() end }
    -- The pixel regions are the core's (Kernel/MSUF_Util.lua); this single-file world lays out no
    -- pixels, so the shared stand-in serves the files that require them at load.
    env.MSUF_PixelLayoutRegion = assert(loadfile(root .. "/tools/tests/classpower_collaborators.lua"))()
        .STANDINS.MSUF_PixelLayoutRegion
    local function Load(path)
        local ok, err = world:LoadFile(root .. "/MidnightSimpleUnitFrames/" .. path, "MidnightSimpleUnitFrames", ns)
        assert(ok, tostring(err))
    end
    return world, env, ns, Load
end

if case == "mapko" then
    -- The whole core graph, with MapkoSkin present before MSUF loads.
    local world = World.New(root, "Mainline")
    local env = world.env
    env.MAX_TOTEMS, env.MAX_BOSS_FRAMES = 4, 5
    env.TotemFrame = false
    local registrations = 0
    local skinAppearance = {}
    local api = {}
    function api:RegisterAddon()
        registrations = registrations + 1
        return { ReleaseAll = function() end, Release = function() end }
    end
    function api:IsEnabled() return true end
    function api:GetAppearanceSnapshot()
        return { menuAnimations = skinAppearance.menuAnimations, smoothScrolling = skinAppearance.smoothScrolling,
            reduceMotion = skinAppearance.reduceMotion }
    end
    function api:GetColor() return 0.5, 0.5, 0.5, 1 end
    function api:OnAppearanceChanged() end
    env.MapkoSkin = { GetAPI = function() return api end }
    if arg[3] then
        local originalLoad = world.LoadFile
        function world:LoadFile(path, addonName, namespace)
            if path:match("/MSUF_MapkoSkin%.lua$") then path = arg[3] end
            return originalLoad(self, path, addonName, namespace)
        end
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    assert(registrations == 0, "the menu skin connected while the files loaded, before the SavedVariables")

    -- This character uses "Default", which opts out; another character's
    -- "Bright" keeps the skin. MSUF_DB is the copy the last session saved.
    local Default = { _msufProfileSchema = 600, general = { mapkoSkinMenus = false } }
    local Bright = { _msufProfileSchema = 600, general = {} }
    local global = { profiles = { Default = Default, Bright = Bright },
        char = { ["Tester-Realm"] = { activeProfile = "Default" } }, global = {} }
    world:LoadSavedVariables("MidnightSimpleUnitFrames",
        { MSUF_DB = { _msufProfileSchema = 600, general = { mapkoSkinMenus = false } }, MSUF_GlobalDB = global })
    local listenerSource = arg[3] and arg[3]:gsub("\\", "/"):match("[^/]+$") or "MSUF_MapkoSkin.lua"
    LoginHandler(world, listenerSource)()
    local Skin = world.core.MenuSkin
    assert(registrations == 1, "the menu skin did not connect at PLAYER_LOGIN")
    assert(not Skin.IsActive(), "the saved mapkoSkinMenus opt-out was ignored after a reload")
    env.MSUF_InitProfiles()
    assert(env.MSUF_ActiveProfile == "Default" and not Skin.IsActive(), "binding the opted-out profile turned the skin on")

    -- Binding another profile repaints from that profile (a rebind runs the
    -- runtime fan-out; unit rendering is not part of this surface).
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    env.MSUF_GF_RebuildAll = function() end
    env.MSUF_ClassPower_Apply = function() end
    global.char["Tester-Realm"].activeProfile = "Bright"
    env.MSUF_InitProfiles()
    assert(env.MSUF_ActiveProfile == "Bright" and Skin.IsActive(), "binding a profile without the opt-out kept the skin off")
    -- The real bridge must separate menu animations from scrolling, settle
    -- active animations, honor opt-out and defer a changed snapshot in combat.
    local oldMenu, stopped = world.core.MSUF2, 0
    world.core.MSUF2 = { Theme = { StopAllMenuAnimations = function() stopped = stopped + 1 end } }
    assert(type(Skin.MotionReduced) == "function" and type(Skin.ScrollMotionReduced) == "function",
        "menu skin motion contract missing")
    assert(not Skin.MotionReduced() and not Skin.ScrollMotionReduced(), "default skin disabled motion")
    skinAppearance.menuAnimations = false
    Skin.Refresh(nil, "motion")
    assert(Skin.MotionReduced() and not Skin.ScrollMotionReduced(), "skin menu animation opt-out was ignored")
    assert(stopped == 1, "menu motion opt-out did not settle active animations")
    skinAppearance.menuAnimations, skinAppearance.smoothScrolling = true, false
    Skin.Refresh(nil, "motion")
    assert(not Skin.MotionReduced() and Skin.ScrollMotionReduced(), "skin scroll opt-out changed menu animation policy")
    assert(stopped == 1, "scroll-only preference settled unrelated menu animations")
    skinAppearance.reduceMotion = true
    Skin.Refresh(nil, "motion")
    assert(Skin.MotionReduced() and Skin.ScrollMotionReduced() and stopped == 2, "skin reduce-motion policy drifted")
    skinAppearance.reduceMotion, skinAppearance.smoothScrolling = false, true
    Skin.Refresh(nil, "motion")
    assert(not Skin.MotionReduced() and not Skin.ScrollMotionReduced(), "restored skin motion preferences stayed reduced")
    world:EnterCombat()
    skinAppearance.menuAnimations = false
    Skin.Refresh(nil, "motion")
    assert(Skin.pending and stopped == 2 and not Skin.MotionReduced(), "combat motion refresh was not deferred")
    world:LeaveCombat()
    world:FireEvent("PLAYER_REGEN_ENABLED")
    assert(not Skin.pending and Skin.MotionReduced() and stopped == 3, "deferred motion refresh did not settle after combat")
    world.core.MSUF2 = oldMenu
    global.char["Tester-Realm"].activeProfile = "Default"
    env.MSUF_InitProfiles()
    assert(env.MSUF_ActiveProfile == "Default" and not Skin.IsActive(), "binding the opted-out profile kept the skin on")
    assert(registrations == 1, "a profile bind registered the skin again")
    assert(not Skin.MotionReduced() and not Skin.ScrollMotionReduced(), "inactive skin leaked its motion policy")
elseif case == "analytics" then
    local world, env, ns, Load = SingleFileWorld()
    local reads, libraryCalls = 0, 0
    env.MSUF_GlobalDB = setmetatable({}, { __index = function() reads = reads + 1 end })
    env.LibStub = function() libraryCalls = libraryCalls + 1 end
    Load("Features/Telemetry/MSUF_Analytics.lua")
    assert(reads == 0, "telemetry read the account settings while the file loaded")
    env.MSUF_GlobalDB = { global = { analytics = { enabled = false } } }
    world:FireEvent("PLAYER_LOGIN")
    world.widgets:RunTimers()
    assert(libraryCalls == 0, "telemetry started at login although the account opted out")
    ns.Analytics.SetEnabled(true, true)
    assert(libraryCalls == 1, "opting in did not start telemetry")
elseif case == "anchors" then
    local world, env, ns, Load = SingleFileWorld()
    local reads = 0
    env.MSUF_DB = setmetatable({}, { __index = function() reads = reads + 1 end })
    env.MSUF_UI = { HidePrompt = function() end, ShowPrompt = function() end }
    ns.Client = { HostsCooldownManager = true }
    ns.SuiteLink = { HasCooldownAnchor = function() return false end, InstallerBusy = function() return false end }
    local anchor = env.CreateFrame("Frame", "ExternalAnchor", env.UIParent)
    anchor:SetSize(300, 30)
    env.ArcUI_Public = { GetGroupAnchor = function() return anchor end }
    env.C_AddOns = { IsAddOnLoaded = function(name) return name == "ArcUI" end }
    env.EventRegistry = { RegisterCallback = function() end }
    -- The consent text translates through the core localization (MSUF.L), which loads before it.
    Load("Locales/MSUF_Localization.lua")
    Load("Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
    assert(reads == 0, "acquiring an already loaded anchor provider read the profile while the file loaded")
    world:FireEvent("ADDON_LOADED", "ArcUI")
    assert(reads == 0, "an anchor provider's ADDON_LOADED read the profile before login")
    assert(ns.GetArcUICooldownAnchor() == nil, "the anchor provider was acquired before login")
    env.MSUF_DB = { general = { anchorToCooldown = false }, bars = {} }
    world:FireEvent("PLAYER_LOGIN")
    assert(ns.GetArcUICooldownAnchor() == anchor, "login did not acquire the already loaded anchor provider")
else
    error("unknown case " .. case)
end
print("integration_profile_reads_after_login_smoke: " .. case .. " OK")
