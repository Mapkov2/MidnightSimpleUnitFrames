--- ============================================================================
--- MidnightSimpleUnitFrames - Localization Core
---
--- Single-locale localization scaffold:
--- - MSUF.L: active translation table with fallback to the key itself.
--- - MSUF.LOCALE: locale selected from SavedVariables at ADDON_LOADED.
--- - Locale files register cold loader functions while the addon files execute;
---   after SavedVariables are available, only the selected loader is run.
--- - Changing locale requires ReloadUI.
--- - MSUF.SetLocale(locale): records whether a reload is required. It never rebuilds
---   translation tables during play.
---
--- Translator workflow:
--- - Add translations in the matching Locales/<locale>.lua file.
--- - Keys are the original English UI strings (the current UI text).
---
--- Notes:
--- - This is UI-only (no combat/secure/secret interactions).
--- - Safe: does not touch protected frames or unit APIs.
--- ============================================================================
local addonName, MSUF = ...
MSUF = MSUF or {}

---@diagnostic disable-next-line: undefined-global
local CLIENT_LOCALE = (type(GetLocale) == "function" and GetLocale()) or "enUS"

MSUF.SUPPORTED_LOCALES = MSUF.SUPPORTED_LOCALES or {
    enUS = true,
    enGB = true,
    deDE = true,
    esES = true,
    esMX = true,
    frFR = true,
    itIT = true,
    koKR = true,
    ptBR = true,
    ruRU = true,
    zhCN = true,
    zhTW = true,
}

MSUF.LOCALE_NAMES = MSUF.LOCALE_NAMES or {
    enUS = "English (US)",
    enGB = "English (UK)",
    deDE = "Deutsch",
    esES = "Español (EU)",
    esMX = "Español (AL)",
    frFR = "Français",
    itIT = "Italiano",
    koKR = "한국어",
    ptBR = "Português (BR)",
    ruRU = "Русский",
    zhCN = "简体中文",
    zhTW = "繁體中文",
}

local function LocaleFromDB(db)
    local general = type(db) == "table" and db.general
    local value = type(general) == "table" and general.menuLocale
    if type(value) == "string" and MSUF.SUPPORTED_LOCALES[value] then return value end
    return nil
end

local function ActiveProfileLocale()
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    local profiles = type(globalDB) == "table" and globalDB.profiles
    local characters = type(globalDB) == "table" and globalDB.char
    if type(profiles) ~= "table" or type(characters) ~= "table" then return nil end

    local unitName = _G.UnitName
    local getRealmName = _G.GetRealmName
    if type(unitName) ~= "function" or type(getRealmName) ~= "function" then return nil end
    local name = unitName("player")
    local realm = getRealmName()
    if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then return nil end

    local character = characters[name .. "-" .. realm]
    local activeProfile = type(character) == "table" and character.activeProfile
    local profile = type(activeProfile) == "string" and profiles[activeProfile]
    return LocaleFromDB(profile)
end

local function SavedLocale()
    local value = ActiveProfileLocale() or LocaleFromDB(rawget(_G, "MSUF_DB"))
    if value then return value end
    return CLIENT_LOCALE
end

MSUF.CLIENT_LOCALE = CLIENT_LOCALE
--- SavedVariables are not reliable while addon Lua files are still executing.
--- Keep the client locale as a harmless provisional value until ADDON_LOADED,
--- when the active profile and its menuLocale can be resolved deterministically.
MSUF.LOCALE = CLIENT_LOCALE
if not MSUF.SUPPORTED_LOCALES[MSUF.LOCALE] then MSUF.LOCALE = "enUS" end

MSUF.L = MSUF.L or {}
local L = MSUF.L

local function EnsureFallback(tableRef)
    if not getmetatable(tableRef) then
        setmetatable(tableRef, { __index = function(_, k) return k end })
    end
end

EnsureFallback(L)

MSUF.LocaleRegistry = {}

local LocaleLoaders = {}
local LocaleFinalizers = {}
local LocaleCallbacks = {}
local localeFinalized = false

--- Defensive sink for third-party callers that try to register an inactive pack.
--- Built-in packs return before registration, so this table never receives data.
local INACTIVE_LOCALE = setmetatable({}, { __newindex = function() end })

local function NormalizeLocale(locale)
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = CLIENT_LOCALE end
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    return locale
end

function MSUF.RegisterLocale(locale)
    if locale == MSUF.LOCALE then return L end
    return INACTIVE_LOCALE
end

function MSUF.RegisterLocaleLoader(locale, loader)
    if localeFinalized or not MSUF.SUPPORTED_LOCALES[locale or ""] or type(loader) ~= "function" then return false end
    LocaleLoaders[locale] = loader
    return true
end

function MSUF.RegisterLocaleFinalizer(loader)
    if localeFinalized or type(loader) ~= "function" then return false end
    LocaleFinalizers[#LocaleFinalizers + 1] = loader
    return true
end

function MSUF.GetEffectiveLocale()
    return MSUF.LOCALE or CLIENT_LOCALE or "enUS"
end

function MSUF.ResolveConfiguredLocale(db)
    return LocaleFromDB(db) or CLIENT_LOCALE or "enUS"
end

function MSUF.SetLocale(locale)
    locale = NormalizeLocale(locale)
    local reloadRequired = locale ~= MSUF.LOCALE
    MSUF.PendingLocale = reloadRequired and locale or nil
    MSUF.LocaleReloadRequired = reloadRequired or nil
    return MSUF.LOCALE, reloadRequired
end

function MSUF.RegisterLocaleCallback(key, callback)
    if localeFinalized or type(key) ~= "string" or type(callback) ~= "function" then return false end
    LocaleCallbacks[key] = callback
    return true
end

function MSUF.Translate(text)
    if type(text) ~= "string" then return text end
    local direct = rawget(L, text)
    if direct ~= nil then return direct end
    return text
end

--- Public global handle for external modules / debugging.
_G.MSUF_L = L

function MSUF.AddLocale(locale, dict)
    if locale ~= MSUF.LOCALE or type(dict) ~= "table" then return end
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            L[k] = v
        end
    end
end

local function Wipe(tableRef)
    for key in pairs(tableRef) do tableRef[key] = nil end
end

function MSUF.FinalizeLocale()
    if localeFinalized then return MSUF.LOCALE end
    localeFinalized = true

    MSUF.LOCALE = NormalizeLocale(SavedLocale())
    Wipe(L)
    local loader = LocaleLoaders[MSUF.LOCALE]
    Wipe(LocaleLoaders)
    if type(loader) == "function" then loader() end

    for i = 1, #LocaleFinalizers do
        LocaleFinalizers[i]()
    end
    Wipe(LocaleFinalizers)

    MSUF.LocaleRegistry = { [MSUF.LOCALE] = L }
    for _, callback in pairs(LocaleCallbacks) do callback(MSUF.LOCALE) end
    Wipe(LocaleCallbacks)
    return MSUF.LOCALE
end

if type(_G.CreateFrame) == "function" then
    local localeFrame = _G.CreateFrame("Frame")
    localeFrame:RegisterEvent("ADDON_LOADED")
    localeFrame:SetScript("OnEvent", function(self, _, loadedAddon)
        if loadedAddon ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
        MSUF.FinalizeLocale()
    end)
end

--- All language packs follow this file directly in the main TOC. They retain
--- only loader bytecode during startup; FinalizeLocale executes the selected
--- pack and releases every inactive loader immediately afterward.
MSUF.LocaleAddonName = nil
MSUF.LocaleAddonLoaded = nil
MSUF.LocaleAddonLoadError = nil
