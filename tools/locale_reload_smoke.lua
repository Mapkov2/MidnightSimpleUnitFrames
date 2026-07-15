_G = _G or _ENV

local function ExistingPath(primary, fallback)
    local handle = io.open(primary, "r")
    if handle then
        handle:close()
        return primary
    end
    return fallback
end

local function Read(path)
    local handle, err = io.open(path, "r")
    assert(handle, err)
    local text = handle:read("*a")
    handle:close()
    return text
end

local function Copy(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = type(value) == "table" and Copy(value) or value
    end
    return result
end

local runtimeLoaderPath = ExistingPath(
    "tools/assistant_runtime_manifest_loader.lua",
    "../tools/assistant_runtime_manifest_loader.lua"
)
local RuntimeManifest = dofile(runtimeLoaderPath)

local addonRoot = ExistingPath("MidnightSimpleUnitFrames/Locales/MSUF_Localization.lua", "Locales/MSUF_Localization.lua")
local profilePath = ExistingPath("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua", "State/MSUF_Profiles.lua")
local bindingsPath = ExistingPath("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Bindings.lua", "Shell/Menu2/MSUF_Menu2_Bindings.lua")
local miscPath = ExistingPath("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", "Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua")
local assistantPath = RuntimeManifest.ResolveCompanionRoot()
    .. "/Assistant/MSUF_AssistantRegistry_Global_BaseSettings.lua"

local localeLoads = 0
_G.GetLocale = function() return "enUS" end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.C_AddOns = {
    LoadAddOn = function()
        -- All locale packs ship in the main TOC; nothing may demand-load a
        -- companion addon anymore.
        localeLoads = localeLoads + 1
        error("localization requested an on-demand locale addon")
    end,
}
_G.MSUF_GlobalDB = {
    profiles = {
        Current = { general = { menuLocale = "deDE" } },
        Other = { general = { menuLocale = "enUS" } },
    },
    char = {
        ["Tester-Realm"] = { activeProfile = "Current" },
    },
}
_G.MSUF_DB = { general = { menuLocale = "frFR" } }

local MSUF = { Public = {} }
function MSUF.ExportPublic(name, value)
    _G[name] = value
    MSUF.Public[name] = value
    return value
end

local localeChunk, localeError = loadfile(addonRoot)
assert(localeChunk, localeError)
localeChunk("MidnightSimpleUnitFrames", MSUF)

assert(MSUF.LOCALE == "deDE", "active character profile must win over stale MSUF_DB and client locale")
assert(localeLoads == 0, "localization must not demand-load a locale companion addon")
assert(MSUF.LocaleAddonName == nil and MSUF.LocaleAddonLoaded == nil and MSUF.LocaleAddonLoadError == nil,
    "legacy locale companion state must stay cleared")
assert(MSUF.ResolveConfiguredLocale({ general = { menuLocale = "frFR" } }) == "frFR", "explicit profile locale resolution failed")
local active, reloadRequired = MSUF.SetLocale("enUS")
assert(active == "deDE" and reloadRequired == true, "locale changes must remain pending until reload")
active, reloadRequired = MSUF.SetLocale("deDE")
assert(active == "deDE" and reloadRequired == false, "active locale must not request reload")

local reloadPrompts = 0
MSUF.MSUF2 = {
    ShowLocaleReloadRequired = function() reloadPrompts = reloadPrompts + 1 end,
}
MSUF.UF = { Apply = function() return true end }
_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.MSUF_DB = _G.MSUF_GlobalDB.profiles.Current
_G.MSUF_ActiveProfile = "Current"
_G.CopyTable = Copy
_G.loadstring = _G.loadstring or load
_G.InCombatLockdown = function() return false end
_G.MSUF_EnsureDB = function()
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
end
_G.MSUF_UFCore_NotifyConfigChanged = function() return true end

local profileChunk, profileError = loadfile(profilePath)
assert(profileChunk, profileError)
profileChunk("MidnightSimpleUnitFrames", MSUF)
_G.MSUF_SwitchProfile("Other")
assert(_G.MSUF_DB == _G.MSUF_GlobalDB.profiles.Other, "profile switch did not install the selected profile")
assert(MSUF.PendingLocale == "enUS", "profile locale must be recorded as pending")
assert(reloadPrompts == 1, "profile locale change must show one reload notification")

local bindings = Read(bindingsPath)
assert(bindings:find("opts.noRuntime == true", 1, true), "menuLocale no-runtime guard missing")
local misc = Read(miscPath)
assert(misc:find("noRuntime = true", 1, true), "locale dropdown must request no runtime fanout")
local assistant = Read(assistantPath)
assert(not assistant:find('ApplyGeneral("MSUF_ASSISTANT_LOCALE"', 1, true), "assistant locale action must not request a broad runtime apply")

io.write("locale_reload_smoke: ok\n")
