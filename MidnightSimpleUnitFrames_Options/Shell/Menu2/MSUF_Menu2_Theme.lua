local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local SharedUI = MSUF.UI

T.fontSizes = SharedUI.fontSizes
function T.FontSize(role, fallback)
    -- Menu-only readability floor; gameplay fonts keep their own sizing.
    if role == "micro" then return 11 end
    if role == "navigation" then return 14 end
    if role == "caption" or role == "supporting" then return 12 end
    return SharedUI.FontSize(role, fallback)
end
T.NormalizeFontSize = SharedUI.NormalizeFontSize
T.spacing = SharedUI.spacing
T.Space = SharedUI.Space

-- Menu2 theme and widget styling layer.
-- Owns reusable visual primitives, locale-aware labels, and skin helpers for the options UI.
-- Page modules should call this layer instead of restyling frames ad hoc.
T.collapseHintClickHideThreshold = T.collapseHintClickHideThreshold or 8
local ENGLISH_LOCALES = { enUS = true, enGB = true }
local LOCALE_ORDER = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local function ActiveLocale()
    return MSUF.GetEffectiveLocale()
end
-- The effective locale is immutable for the session (MSUF.SetLocale requires a
-- reload), so the English check is resolved once instead of per tracked key.
local activeLocaleIsEnglish
local localeKeyCount = 0
local MAX_TRACKED_LOCALE_KEYS = 8192 -- Diagnostics must not retain unlimited user/composed text.
local function TrackLocaleKey(key, translated)
    -- Locale coverage is collected while UI text is resolved. This gives diagnostics a cheap
    -- way to list missing translations without a separate scan of every page file.
    M.localeKeys = M.localeKeys or {}
    if M.localeKeys[key] or localeKeyCount >= MAX_TRACKED_LOCALE_KEYS then return end
    localeKeyCount = localeKeyCount + 1
    M.localeKeys[key] = true
    if activeLocaleIsEnglish == nil then
        activeLocaleIsEnglish = ENGLISH_LOCALES[ActiveLocale()] == true
    end
    if activeLocaleIsEnglish or translated then return end
    M.missingLocaleKeys = M.missingLocaleKeys or {}
    M.missingLocaleKeys[key] = true
end
function M.GetLocaleCoverage()
    local keys, missing = M.localeKeys or {}, M.missingLocaleKeys or {}
    local total, missingTotal, missingList = 0, 0, {}
    for key in pairs(keys) do total = total + 1 end
    for key in pairs(missing) do
        missingTotal = missingTotal + 1
        missingList[#missingList + 1] = key
    end
    table.sort(missingList)
    return total, missingTotal, missingList
end
local function Tr(text)
    if type(text) ~= "string" then return text end
    local translated = MSUF.Translate(text)
    TrackLocaleKey(text, translated ~= text)
    return translated
end
M.Tr = Tr
local function ClientLocale()
    return GetLocale() or MSUF.CLIENT_LOCALE or "enUS"
end
local function IsSupportedLocale(locale)
    local supported = MSUF.SUPPORTED_LOCALES
    return type(locale) == "string" and supported[locale] == true
end
function M.GetLocaleDropdownValues()
    local names = MSUF.LOCALE_NAMES
    local values = {
        { value = "auto", text = "Follow Blizzard" },
    }
    for i = 1, #LOCALE_ORDER do
        local locale = LOCALE_ORDER[i]
        values[#values + 1] = { value = locale, text = names[locale] or locale, translate = false }
    end
    return values
end
function M.GetLocaleSelection()
    local g = M.GetGeneralDB()
    local selected = type(g) == "table" and g.menuLocale
    if IsSupportedLocale(selected) then return selected end
    return "auto"
end
function M.ResolveLocaleSelection(selection)
    if IsSupportedLocale(selection) then return selection end
    local locale = ClientLocale()
    if IsSupportedLocale(locale) then return locale end
    return "enUS"
end
function M.ShowLocaleReloadRequired()
    M.ShowPrompt("MSUF2_LOCALE_RELOAD_REQUIRED", {
        text = M.Tr("Menu language was changed. MSUF loads only one language per session, so a UI reload is required to apply it.\n\nReload now?"),
        accept = RELOADUI or RELOAD or M.Tr("Reload"),
        cancel = CANCEL or M.Tr("Not now"),
        onAccept = function() ReloadUI() end,
    })
    return true
end
function M.ApplyLocaleSelection(selection)
    local selected = selection or M.GetLocaleSelection()
    local locale = M.ResolveLocaleSelection(selected)
    local active, reloadRequired = MSUF.LOCALE, locale ~= MSUF.LOCALE
    active, reloadRequired = MSUF.SetLocale(locale)
    if selection ~= nil then
        if reloadRequired then
            M.ShowLocaleReloadRequired()
        else
            M.HidePrompt("MSUF2_LOCALE_RELOAD_REQUIRED")
        end
    end
    return active or MSUF.LOCALE, selected, reloadRequired
end
M.Format = function(text, ...)
    local translated = M.Tr(text)
    if select("#", ...) == 0 then return translated end
    return string.format(translated, ...)
end
