--- ============================================================================
--- MidnightSimpleUnitFrames - Localization Core
---
--- Runtime localization scaffold:
--- - MSUF.L: active translation table with fallback to the key itself.
--- - MSUF.LOCALE: active menu locale string.
--- - MSUF.AddLocale(locale, dict): register translations for any supported locale.
--- - MSUF.SetLocale(locale): switch menus independently from the Blizzard client;
--- combat requests are deferred until PLAYER_REGEN_ENABLED.
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
_G.MSUF_NS = MSUF

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

local function SavedLocale()
    local db = rawget(_G, "MSUF_DB")
    local general = type(db) == "table" and db.general
    local value = type(general) == "table" and general.menuLocale
    if type(value) == "string" and MSUF.SUPPORTED_LOCALES[value] then return value end
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

MSUF.LocaleRegistry = MSUF.LocaleRegistry or {}
MSUF.LocaleProxies = MSUF.LocaleProxies or {}
MSUF.LocaleCallbacks = MSUF.LocaleCallbacks or {}

local function Registry(locale)
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    MSUF.LocaleRegistry[locale] = MSUF.LocaleRegistry[locale] or {}
    return MSUF.LocaleRegistry[locale]
end

local function RebuildActiveLocale()
    for k in pairs(L) do L[k] = nil end
    local dict = Registry(MSUF.LOCALE)
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            L[k] = v
        end
    end
    EnsureFallback(L)
end

local function NormalizeLocale(locale)
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = CLIENT_LOCALE end
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    return locale
end

local function InCombat()
---@diagnostic disable-next-line: undefined-field
    return (_G.InCombatLockdown and _G.InCombatLockdown())
---@diagnostic disable-next-line: undefined-field
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function ApplyLocale(locale)
    MSUF.LOCALE = NormalizeLocale(locale)
    RebuildActiveLocale()
    for _, callback in pairs(MSUF.LocaleCallbacks) do
        if type(callback) == "function" then
            pcall(callback, MSUF.LOCALE)
        end
    end
    return MSUF.LOCALE
end

local LocaleApplyFrame
local function EnsureLocaleApplyFrame()
---@diagnostic disable-next-line: undefined-global
    if LocaleApplyFrame or type(CreateFrame) ~= "function" then return end
---@diagnostic disable-next-line: undefined-global
    LocaleApplyFrame = CreateFrame("Frame")
    LocaleApplyFrame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local pending = MSUF.PendingLocale
        MSUF.PendingLocale = nil
        if pending then ApplyLocale(pending) end
    end)
end

function MSUF.RegisterLocale(locale)
    if not MSUF.SUPPORTED_LOCALES[locale or ""] then locale = "enUS" end
    if MSUF.LocaleProxies[locale] then return MSUF.LocaleProxies[locale] end
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            return Registry(locale)[key]
        end,
        __newindex = function(_, key, value)
            if type(key) ~= "string" or type(value) ~= "string" then return end
            Registry(locale)[key] = value
            if locale == MSUF.LOCALE then L[key] = value end
        end,
    })
    MSUF.LocaleProxies[locale] = proxy
    return proxy
end

function MSUF.GetEffectiveLocale()
    return MSUF.LOCALE or CLIENT_LOCALE or "enUS"
end

function MSUF.SetLocale(locale)
    locale = NormalizeLocale(locale)
    if InCombat() then
        MSUF.PendingLocale = locale
        EnsureLocaleApplyFrame()
        if LocaleApplyFrame then
            LocaleApplyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return MSUF.LOCALE
    end
    MSUF.PendingLocale = nil
    return ApplyLocale(locale)
end

function MSUF.RegisterLocaleCallback(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    MSUF.LocaleCallbacks[key] = callback
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
    if not dict then return end
    local target = Registry(locale)
    for k, v in pairs(dict) do
        if type(k) == "string" and type(v) == "string" then
            target[k] = v
            if locale == MSUF.LOCALE then L[k] = v end
        end
    end
end
