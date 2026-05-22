-- ============================================================================
-- MidnightSimpleUnitFrames - Localization Core
--
-- Runtime localization scaffold:
--   - ns.L: active translation table with fallback to the key itself.
--   - ns.LOCALE: active menu locale string.
--   - ns.AddLocale(locale, dict): register translations for any supported locale.
--   - ns.SetLocale(locale): switch menus independently from the Blizzard client;
--     combat requests are deferred until PLAYER_REGEN_ENABLED.
--
-- Translator workflow:
--   - Add translations in the matching Locales/<locale>.lua file.
--   - Keys are the original English UI strings (the current UI text).
--
-- Notes:
--   - This is UI-only (no combat/secure/secret interactions).
--   - Safe: does not touch protected frames or unit APIs.
-- ============================================================================
local addonName, ns = ...
ns = ns or {}
_G.MSUF_NS = ns

local CLIENT_LOCALE = (type(GetLocale) == "function" and GetLocale()) or "enUS"

ns.SUPPORTED_LOCALES = ns.SUPPORTED_LOCALES or {
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

ns.LOCALE_NAMES = ns.LOCALE_NAMES or {
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

local function SavedLocale()
    local db = rawget(_G, "MSUF_DB")
    local general = type(db) == "table" and db.general
    local value = type(general) == "table" and general.menuLocale
    if type(value) == "string" and ns.SUPPORTED_LOCALES[value] then return value end
    return CLIENT_LOCALE
end

ns.CLIENT_LOCALE = CLIENT_LOCALE
ns.LOCALE = ns.SUPPORTED_LOCALES[ns.LOCALE or ""] and ns.LOCALE or SavedLocale()
if not ns.SUPPORTED_LOCALES[ns.LOCALE] then ns.LOCALE = "enUS" end

ns.L = ns.L or {}
local L = ns.L

local function EnsureFallback(tableRef)
    if not getmetatable(tableRef) then
        setmetatable(tableRef, { __index = function(_, k) return k end })
    end
end

EnsureFallback(L)

ns.LocaleRegistry = ns.LocaleRegistry or {}
ns.LocaleProxies = ns.LocaleProxies or {}
ns.LocaleCallbacks = ns.LocaleCallbacks or {}

local function Registry(locale)
    if not ns.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    ns.LocaleRegistry[locale] = ns.LocaleRegistry[locale] or {}
    return ns.LocaleRegistry[locale]
end

local function RebuildActiveLocale()
    for k in pairs(L) do L[k] = nil end
    local dict = Registry(ns.LOCALE)
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            L[k] = v
        end
    end
    EnsureFallback(L)
end

local function NormalizeLocale(locale)
    if not ns.SUPPORTED_LOCALES[locale or ""] then locale = CLIENT_LOCALE end
    if not ns.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    return locale
end

local function InCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function ApplyLocale(locale)
    ns.LOCALE = NormalizeLocale(locale)
    RebuildActiveLocale()
    for _, callback in pairs(ns.LocaleCallbacks) do
        if type(callback) == "function" then
            pcall(callback, ns.LOCALE)
        end
    end
    return ns.LOCALE
end

local LocaleApplyFrame
local function EnsureLocaleApplyFrame()
    if LocaleApplyFrame or type(CreateFrame) ~= "function" then return end
    LocaleApplyFrame = CreateFrame("Frame")
    LocaleApplyFrame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local pending = ns.PendingLocale
        ns.PendingLocale = nil
        if pending then ApplyLocale(pending) end
    end)
end

function ns.RegisterLocale(locale)
    if not ns.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    if ns.LocaleProxies[locale] then return ns.LocaleProxies[locale] end
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            return Registry(locale)[key]
        end,
        __newindex = function(_, key, value)
            if type(key) ~= "string" or type(value) ~= "string" then return end
            Registry(locale)[key] = value
            if locale == ns.LOCALE then L[key] = value end
        end,
    })
    ns.LocaleProxies[locale] = proxy
    return proxy
end

function ns.GetEffectiveLocale()
    return ns.LOCALE or CLIENT_LOCALE or "enUS"
end

function ns.SetLocale(locale)
    locale = NormalizeLocale(locale)
    if InCombat() then
        ns.PendingLocale = locale
        EnsureLocaleApplyFrame()
        if LocaleApplyFrame then
            LocaleApplyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return ns.LOCALE
    end
    ns.PendingLocale = nil
    return ApplyLocale(locale)
end

function ns.RegisterLocaleCallback(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    ns.LocaleCallbacks[key] = callback
end

function ns.Translate(text)
    if type(text) ~= "string" then return text end
    local direct = rawget(L, text)
    if direct ~= nil then return direct end
    return text
end

-- Public global handle for external modules / debugging.
_G.MSUF_L = L

function ns.AddLocale(locale, dict)
    if not dict then return end
    local target = Registry(locale)
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            target[k] = v
            if locale == ns.LOCALE then L[k] = v end
        end
    end
end
