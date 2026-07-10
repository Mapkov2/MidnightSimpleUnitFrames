--- ============================================================================
--- MidnightSimpleUnitFrames - Localization Core
---
--- Single-locale localization scaffold:
--- - MSUF.L: active translation table with fallback to the key itself.
--- - MSUF.LOCALE: locale selected from SavedVariables/client locale at load time.
--- - English data ships in the main addon. Non-English data ships in one
---   LoadOnDemand companion; active-pack guards retain only the selected table.
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
MSUF.LOCALE = MSUF.SUPPORTED_LOCALES[MSUF.LOCALE or ""] and MSUF.LOCALE or SavedLocale()
if not MSUF.SUPPORTED_LOCALES[MSUF.LOCALE] then MSUF.LOCALE = "enUS" end

MSUF.L = MSUF.L or {}
local L = MSUF.L

local function EnsureFallback(tableRef)
    if not getmetatable(tableRef) then
        setmetatable(tableRef, { __index = function(_, k) return k end })
    end
end

EnsureFallback(L)

--- Keep the legacy registry shape for diagnostics without retaining every locale.
MSUF.LocaleRegistry = { [MSUF.LOCALE] = L }

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

function MSUF.RegisterLocaleCallback()
    --- Locale tables are immutable for the session, so callbacks are intentionally
    --- not retained. The compatibility function remains for existing modules.
    return false
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

--- English packs follow this file directly in the main TOC. Non-English packs
--- share one LoadOnDemand addon; every source file has an active-locale guard,
--- so only the selected dictionary executes and remains resident.
if MSUF.LOCALE ~= "enUS" and MSUF.LOCALE ~= "enGB" then
    local localeAddon = "MidnightSimpleUnitFrames_Locales"
    local loadAddOn = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
    MSUF.LocaleAddonName = localeAddon
    if type(loadAddOn) == "function" then
        local loaded, reason = loadAddOn(localeAddon)
        if loaded then
            MSUF.LocaleAddonLoaded = true
            MSUF.LocaleAddonLoadError = nil
        else
            MSUF.LocaleAddonLoaded = false
            MSUF.LocaleAddonLoadError = reason
        end
    else
        MSUF.LocaleAddonLoaded = false
        MSUF.LocaleAddonLoadError = "LoadAddOn unavailable"
    end
else
    MSUF.LocaleAddonName = nil
    MSUF.LocaleAddonLoaded = nil
    MSUF.LocaleAddonLoadError = nil
end
