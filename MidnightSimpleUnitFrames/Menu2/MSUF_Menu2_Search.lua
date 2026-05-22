local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets
local Search = M.Search or {}
M.Search = Search
local SearchData = M.SearchData or {}
local NAV_ITEMS = M.navItems or {}

local floor = math.floor
local max = math.max
local min = math.min

local function ContentMetrics()
    local w, h = 720, 520
    if type(M.GetContentMetrics) == "function" then
        local ok, cw, ch = pcall(M.GetContentMetrics)
        if ok then
            w = tonumber(cw) or w
            h = tonumber(ch) or h
        end
    end
    return w, h
end

local function ContentWidth()
    local w = ContentMetrics()
    return w
end

local function ContentHeight()
    local _, h = ContentMetrics()
    return h
end

local SEARCH_KEYWORDS = SearchData.KEYWORDS or {}


local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ShortLabel(text, limit)
    text = TrimText(text)
    limit = tonumber(limit) or 22
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end


local function SearchPlaceholderText()
    local text = M.Tr("Search")
    if type(text) ~= "string" or text == "" then text = "Search" end
    local ask = M.Tr("Ask...")
    if type(ask) ~= "string" or ask == "" then ask = "Ask..." end
    return text .. " / " .. ask
end

local function SearchBoxHasText(searchBox)
    if not (searchBox and searchBox.GetText) then return false end
    return (searchBox:GetText() or ""):match("%S") ~= nil
end

local function RefreshSearchPlaceholder(searchBox)
    if not searchBox then return end
    local text = SearchPlaceholderText()
    if searchBox.Instructions and searchBox.Instructions.SetText then
        searchBox.Instructions:SetText(text)
    end
    if searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then
        searchBox._msuf2SearchPlaceholder:SetText(text)
    end
end

local function UpdateSearchPlaceholder(searchBox)
    if not searchBox then return end
    RefreshSearchPlaceholder(searchBox)
    local placeholder = searchBox._msuf2SearchPlaceholder
    if not placeholder then return end
    local focused = (searchBox.HasFocus and searchBox:HasFocus()) and true or false
    if focused or SearchBoxHasText(searchBox) then
        placeholder:Hide()
    else
        placeholder:Show()
    end
end

local SEARCH_TEXT_FOLDS = SearchData.TEXT_FOLDS or {}

local SEARCH_UTF_PUNCTUATION = SearchData.UTF_PUNCTUATION or {}

local function NormalizeSearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("\195\132", "ae"):gsub("\195\164", "ae")
    text = text:gsub("\195\150", "oe"):gsub("\195\182", "oe")
    text = text:gsub("\195\156", "ue"):gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    for from, to in pairs(SEARCH_TEXT_FOLDS) do text = text:gsub(from, to) end
    for i = 1, #SEARCH_UTF_PUNCTUATION do text = text:gsub(SEARCH_UTF_PUNCTUATION[i], " ") end
    text = text:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", " ")
    text = text:gsub("[/\\_%-%.:;,%(%)]", " ")
    text = string.lower(text)
    text = text:gsub("[\001-\031\127]", " ")
    -- Preserve non-ASCII letters so native localized FAQ keywords can match.
    text = text:gsub("[!\"#$%%&'%*%+<=>%?%@%[%]%^`{|}~]+", " ")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local function DisplaySearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local SEARCH_LOCALE_KEY_PREFIX = "MSUF2_SEARCH_"
local SEARCH_DEFAULT_LOCALE = "enUS"
local SEARCH_LOCALE_TEXT_CACHE = {}

local function IsSearchLocaleKey(text)
    return type(text) == "string" and text:sub(1, #SEARCH_LOCALE_KEY_PREFIX) == SEARCH_LOCALE_KEY_PREFIX
end

local function SearchEffectiveLocale()
    if type(ns.GetEffectiveLocale) == "function" then
        local ok, locale = pcall(ns.GetEffectiveLocale)
        if ok and type(locale) == "string" and locale ~= "" then return locale end
    end
    if type(ns.LOCALE) == "string" and ns.LOCALE ~= "" then return ns.LOCALE end
    if type(_G.GetLocale) == "function" then
        local ok, locale = pcall(_G.GetLocale)
        if ok and type(locale) == "string" and locale ~= "" then return locale end
    end
    return SEARCH_DEFAULT_LOCALE
end

local function SearchLocaleCacheKey(text)
    return SearchEffectiveLocale() .. "\031" .. tostring(text or "")
end

local function AddUniqueSearchPart(parts, seen, text)
    text = DisplaySearchText(text)
    if text == "" or seen[text] then return end
    seen[text] = true
    parts[#parts + 1] = text
end

local function SearchLocaleTranslations(text)
    local cacheKey = SearchLocaleCacheKey(text)
    local cached = SEARCH_LOCALE_TEXT_CACHE[cacheKey]
    if cached then return cached end

    local out, seen = {}, {}
    local function add(value)
        value = DisplaySearchText(value)
        if value == "" or seen[value] then return end
        seen[value] = true
        out[#out + 1] = value
    end

    if type(M.Tr) == "function" then
        local translated = M.Tr(text)
        if translated and translated ~= text then add(translated) end
    end

    if type(ns.RegisterLocale) == "function" then
        local L = ns.RegisterLocale(SearchEffectiveLocale())
        local translated = L and L[text]
        if translated and translated ~= text then add(translated) end
    end

    SEARCH_LOCALE_TEXT_CACHE[cacheKey] = out
    return out
end

local function SearchDisplayText(text)
    text = DisplaySearchText(text)
    if text == "" then return "" end
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then return translations[1] end
    if IsSearchLocaleKey(text) then return "" end
    return text
end

local function AddSearchText(parts, text)
    if text == nil then return end
    text = DisplaySearchText(text)
    if text == "" then return end
    local seen = {}
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then
        for i = 1, #translations do
            AddUniqueSearchPart(parts, seen, translations[i])
        end
        if not IsSearchLocaleKey(text) then
            AddUniqueSearchPart(parts, seen, text)
        end
    elseif not IsSearchLocaleKey(text) then
        AddUniqueSearchPart(parts, seen, text)
    end
end

local function AddSearchTextVariants(out, seen, text)
    local translations = SearchLocaleTranslations(text)
    if #translations > 0 then
        for i = 1, #translations do
            AddUniqueSearchPart(out, seen, translations[i])
        end
        if not IsSearchLocaleKey(text) then
            AddUniqueSearchPart(out, seen, text)
        end
    elseif not IsSearchLocaleKey(text) then
        AddUniqueSearchPart(out, seen, text)
    end
end

local function AddRawSearchText(parts, text)
    if text == nil then return end
    text = tostring(text)
    if text ~= "" then parts[#parts + 1] = text end
end

local function SearchTextVariants(text)
    local out, seen = {}, {}
    AddSearchTextVariants(out, seen, text)
    return out
end

local SEARCH_CONTROL_ACTION_KEYWORDS = "MSUF2_SEARCH_CONTROL_ACTION_KEYWORDS"
local SEARCH_CONTROL_PATTERNS = "MSUF2_SEARCH_CONTROL_PATTERNS"
local SEARCH_TOGGLE_ACTION_KEYWORDS = "MSUF2_SEARCH_TOGGLE_ACTION_KEYWORDS"
local SEARCH_TOGGLE_PATTERNS = "MSUF2_SEARCH_TOGGLE_PATTERNS"
local SEARCH_DROPDOWN_ACTION_KEYWORDS = "MSUF2_SEARCH_DROPDOWN_ACTION_KEYWORDS"
local SEARCH_DROPDOWN_PATTERNS = "MSUF2_SEARCH_DROPDOWN_PATTERNS"
local SEARCH_SEGMENT_ACTION_KEYWORDS = "MSUF2_SEARCH_SEGMENT_ACTION_KEYWORDS"
local SEARCH_SEGMENT_PATTERNS = "MSUF2_SEARCH_SEGMENT_PATTERNS"
local SEARCH_SLIDER_ACTION_KEYWORDS = "MSUF2_SEARCH_SLIDER_ACTION_KEYWORDS"
local SEARCH_SLIDER_PATTERNS = "MSUF2_SEARCH_SLIDER_PATTERNS"
local SEARCH_COLOR_ACTION_KEYWORDS = "MSUF2_SEARCH_COLOR_ACTION_KEYWORDS"
local SEARCH_COLOR_PATTERNS = "MSUF2_SEARCH_COLOR_PATTERNS"
local SEARCH_BUTTON_ACTION_KEYWORDS = "MSUF2_SEARCH_BUTTON_ACTION_KEYWORDS"
local SEARCH_BUTTON_PATTERNS = "MSUF2_SEARCH_BUTTON_PATTERNS"
local SEARCH_TEXTINPUT_ACTION_KEYWORDS = "MSUF2_SEARCH_TEXTINPUT_ACTION_KEYWORDS"
local SEARCH_TEXTINPUT_PATTERNS = "MSUF2_SEARCH_TEXTINPUT_PATTERNS"
local SEARCH_VALUE_PATTERNS = "MSUF2_SEARCH_VALUE_PATTERNS"

local SEARCH_KIND_ACTION_KEYWORDS = {
    toggle = SEARCH_TOGGLE_ACTION_KEYWORDS,
    dropdown = SEARCH_DROPDOWN_ACTION_KEYWORDS,
    segment = SEARCH_SEGMENT_ACTION_KEYWORDS,
    slider = SEARCH_SLIDER_ACTION_KEYWORDS,
    color = SEARCH_COLOR_ACTION_KEYWORDS,
    button = SEARCH_BUTTON_ACTION_KEYWORDS,
    textinput = SEARCH_TEXTINPUT_ACTION_KEYWORDS,
}

local SEARCH_KIND_PATTERNS = {
    toggle = SEARCH_TOGGLE_PATTERNS,
    dropdown = SEARCH_DROPDOWN_PATTERNS,
    segment = SEARCH_SEGMENT_PATTERNS,
    slider = SEARCH_SLIDER_PATTERNS,
    color = SEARCH_COLOR_PATTERNS,
    button = SEARCH_BUTTON_PATTERNS,
    textinput = SEARCH_TEXTINPUT_PATTERNS,
}

local function ForEachLocaleSearchPattern(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    local translations = SearchLocaleTranslations(key)
    for i = 1, #translations do
        local text = translations[i]
        for pattern in tostring(text):gmatch("[^|]+") do
            pattern = TrimText(pattern)
            if pattern ~= "" then callback(pattern) end
        end
    end
end

local function AddSearchPatternText(parts, key, label)
    label = DisplaySearchText(label)
    if label == "" then return end
    local labels = SearchTextVariants(label)
    ForEachLocaleSearchPattern(key, function(pattern)
        for i = 1, #labels do
            local ok, formatted = pcall(string.format, pattern, labels[i])
            if ok then AddRawSearchText(parts, formatted) end
        end
    end)
end

local function AddSearchValuePatternText(parts, label, value)
    label = DisplaySearchText(label)
    value = DisplaySearchText(value)
    if label == "" or value == "" then return end
    local labels = SearchTextVariants(label)
    local values = SearchTextVariants(value)
    for i = 1, #labels do
        AddRawSearchText(parts, labels[i] .. " " .. value)
        AddRawSearchText(parts, value .. " " .. labels[i])
    end
    for i = 1, #values do
        AddRawSearchText(parts, label .. " " .. values[i])
        AddRawSearchText(parts, values[i] .. " " .. label)
    end
    ForEachLocaleSearchPattern(SEARCH_VALUE_PATTERNS, function(pattern)
        for i = 1, #labels do
            local ok, formatted = pcall(string.format, pattern, labels[i], value)
            if ok then AddRawSearchText(parts, formatted) end
        end
        for i = 1, #values do
            local ok, formatted = pcall(string.format, pattern, label, values[i])
            if ok then AddRawSearchText(parts, formatted) end
        end
    end)
end

local function AddToggleQuestionSearchText(parts, label)
    label = DisplaySearchText(label)
    if label == "" then return end
    AddRawSearchText(parts, "toggle " .. label)
end

local function AddControlQuestionSearchText(parts, label, kind, values)
    label = DisplaySearchText(label)
    if label == "" then return end

    kind = kind or "control"
    AddRawSearchText(parts, kind .. " " .. label)

    if type(values) ~= "table" then return end
    local limit = math.min(#values, 12)
    for i = 1, limit do
        local value = values[i]
        if type(value) == "table" then value = value.text or value.label or value.name or value.title or value.value or value.key end
        if value ~= nil then AddRawSearchText(parts, label .. " " .. tostring(value)) end
    end
end

local MIN_SEARCH_QUERY_LEN = 2
local SEARCH_TEXT_MAX_LEN = 170
local SEARCH_BACKGROUND_STEP_SEC = 0.22
local SEARCH_INPUT_DEBOUNCE_SEC = 0.10
local SEARCH_MAX_RESULTS = 24
local SEARCH_VISIBLE_RESULTS = 12
local SEARCH_MIN_RESULT_SCORE = 40
local SEARCH_MAX_RAW_WORDS = 12
local SEARCH_MAX_QUERY_CLAUSES = 8
local SEARCH_MAX_TERMS_PER_CLAUSE = 18
local SEARCH_MAX_RECORD_TOKENS = 90
local SEARCH_CONTROL_MAX_TOKENS = 36
local SEARCH_CONTROL_HAYSTACK_MAX_LEN = 1200
local SEARCH_STATE = {
    records = nil,
    recordsDirty = true,
    indexing = false,
    indexQueue = nil,
    inputSerial = 0,
    registrySerial = 0,
    aliasTypoKeys = nil,
    aliasTypoCache = {},
    queryClauseCacheNorm = nil,
    queryClauseCacheClauses = nil,
    registry = {},
    registryByPage = {},
    registryRecords = {},
    localeKey = nil,
}
M.searchRegistry = SEARCH_STATE.registry

local function MarkSearchIndexDirty()
    SEARCH_STATE.recordsDirty = true
end

local function ClearSearchLocaleCaches()
    SEARCH_LOCALE_TEXT_CACHE = {}
    SEARCH_STATE.queryClauseCacheNorm = nil
    SEARCH_STATE.queryClauseCacheClauses = nil
    SEARCH_STATE.registryRecords = {}
end

local function EnsureSearchLocaleFresh()
    local localeKey = SearchEffectiveLocale()
    if SEARCH_STATE.localeKey == localeKey then return end
    SEARCH_STATE.localeKey = localeKey
    ClearSearchLocaleCaches()
    MarkSearchIndexDirty()
end

local function SearchCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function CancelSearchBackgroundIndex()
    SEARCH_STATE.indexing = false
    SEARCH_STATE.indexQueue = nil
end

local SEARCH_NOISE_TEXT = SearchData.NOISE_TEXT or {}

local SEARCH_STOP_WORDS = SearchData.STOP_WORDS or {}

local SEARCH_QUERY_SOFT_STOP_WORDS = SearchData.QUERY_SOFT_STOP_WORDS or {}

local function SearchIgnoreQueryWord(word)
    return SEARCH_STOP_WORDS[word] or SEARCH_QUERY_SOFT_STOP_WORDS[word]
end

local SEARCH_QUERY_ALIASES = SearchData.QUERY_ALIASES or {}

local SEARCH_DISPEL_DEBUFF_KEYWORDS = SearchData.DISPEL_DEBUFF_KEYWORDS or {}

local SEARCH_HIGHLIGHT_BORDER_KEYWORDS = SearchData.HIGHLIGHT_BORDER_KEYWORDS or {}

local SEARCH_DISPEL_OVERLAY_KEYWORDS = SearchData.DISPEL_OVERLAY_KEYWORDS or {}

local SEARCH_DEBUFF_STRIPE_KEYWORDS = SearchData.DEBUFF_STRIPE_KEYWORDS or {}

local SEARCH_BLIZZARD_DISPEL_KEYWORDS = SearchData.BLIZZARD_DISPEL_KEYWORDS or {}

local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = SearchData.UNIT_AURA_DISPEL_KEYWORDS or {}

local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = SearchData.DASHBOARD_RECOVERY_KEYWORDS or {}

local SEARCH_DASHBOARD_DISCORD_KEYWORDS = SearchData.DASHBOARD_DISCORD_KEYWORDS or {}

local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = SearchData.DASHBOARD_SUPPORT_KEYWORDS or {}

local SEARCH_DASHBOARD_WAGO_KEYWORDS = SearchData.DASHBOARD_WAGO_KEYWORDS or {}

local SEARCH_DASHBOARD_SCALING_KEYWORDS = SearchData.DASHBOARD_SCALING_KEYWORDS or {}

local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = SearchData.DASHBOARD_CHANGELOG_KEYWORDS or {}

local function SearchKeywordList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        if type(list) == "table" then
            for k = 1, #list do out[#out + 1] = list[k] end
        elseif list then
            out[#out + 1] = list
        end
    end
    return out
end

local SEARCH_PAGE_LOCALIZED_KEYWORDS = {}

local function AppendSearchKeywords(pageKey, list)
    if not (pageKey and type(list) == "table" and #list > 0) then return end
    local pageList = SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey]
    if not pageList then
        pageList = {}
        SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey] = pageList
    end
    for i = 1, #list do pageList[#pageList + 1] = list[i] end
end

local function AddPageLocalizedSearchKeywords(parts, pageKey)
    local list = SEARCH_PAGE_LOCALIZED_KEYWORDS[pageKey]
    if type(list) ~= "table" then return end
    for i = 1, #list do AddSearchText(parts, list[i]) end
end

AppendSearchKeywords("gf_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS)
AppendSearchKeywords("gf_bars", SEARCH_DEBUFF_STRIPE_KEYWORDS)
AppendSearchKeywords("gf_auras", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("gf_auras", SEARCH_BLIZZARD_DISPEL_KEYWORDS)
AppendSearchKeywords("gf_indicators", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("gf_indicators", SEARCH_HIGHLIGHT_BORDER_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_HIGHLIGHT_BORDER_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("opt_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS)
AppendSearchKeywords("auras2", SEARCH_UNIT_AURA_DISPEL_KEYWORDS)
AppendSearchKeywords("auras2", SEARCH_DISPEL_DEBUFF_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_RECOVERY_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_SUPPORT_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_WAGO_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_SCALING_KEYWORDS)
AppendSearchKeywords("home", SEARCH_DASHBOARD_CHANGELOG_KEYWORDS)

local CONTROL_KIND_LABEL = SearchData.CONTROL_KIND_LABEL or {}

local DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } }
local DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } }
local DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } }

local function AddSearchTermUnique(list, seen, term)
    if #list >= SEARCH_MAX_TERMS_PER_CLAUSE then return end
    term = NormalizeSearchText(term)
    if term == "" or SearchIgnoreQueryWord(term) or seen[term] then return end
    seen[term] = true
    list[#list + 1] = term
end

local function SearchRawWords(normalized)
    local raw = {}
    for word in tostring(normalized or ""):gmatch("%S+") do
        if not SearchIgnoreQueryWord(word) then raw[#raw + 1] = word end
        if #raw >= SEARCH_MAX_RAW_WORDS then break end
    end
    return raw
end

local SearchEditDistanceWithin

local function SearchAliasTypoKeys()
    if SEARCH_STATE.aliasTypoKeys then return SEARCH_STATE.aliasTypoKeys end
    local keys = {}
    for key in pairs(SEARCH_QUERY_ALIASES) do
        if #key >= 5 then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    SEARCH_STATE.aliasTypoKeys = keys
    return keys
end

local function SearchAliasKeyForTypo(word)
    if not SearchEditDistanceWithin or #word < 5 then return nil end
    if SEARCH_STATE.aliasTypoCache[word] ~= nil then return SEARCH_STATE.aliasTypoCache[word] or nil end
    local maxDistance = (#word >= 8) and 2 or 1
    local bestKey, bestDelta
    local keys = SearchAliasTypoKeys()
    for i = 1, #keys do
        local key = keys[i]
        if math.abs(#key - #word) <= maxDistance and SearchEditDistanceWithin(word, key, maxDistance) then
            local delta = math.abs(#key - #word)
            if not bestKey or delta < bestDelta or (delta == bestDelta and #key < #bestKey) then
                bestKey = key
                bestDelta = delta
            end
        end
    end
    SEARCH_STATE.aliasTypoCache[word] = bestKey or false
    return bestKey
end

local function SearchCanonicalWords(raw)
    local words = {}
    local i = 1
    while i <= #raw do
        local word = raw[i]
        local nextWord = raw[i + 1]
        if word == "demon" and nextWord == "hunter" then
            words[#words + 1] = "demonhunter"
            i = i + 2
        elseif word == "death" and nextWord == "knight" then
            words[#words + 1] = "deathknight"
            i = i + 2
        elseif word == "wind" and nextWord == "shear" then
            words[#words + 1] = "windshear"
            i = i + 2
        elseif word == "cast" and nextWord == "bar" then
            words[#words + 1] = "castbar"
            i = i + 2
        elseif word == "health" and nextWord == "bar" then
            words[#words + 1] = "healthbar"
            i = i + 2
        elseif word == "power" and nextWord == "bar" then
            words[#words + 1] = "powerbar"
            i = i + 2
        elseif word == "show" and nextWord == "buffs" then
            words[#words + 1] = "showbuffs"
            i = i + 2
        elseif word == "max" and nextWord == "buffs" then
            words[#words + 1] = "maxbuffs"
            i = i + 2
        elseif word == "custom" and nextWord == "caps" then
            words[#words + 1] = "customcaps"
            i = i + 2
        elseif (word == "smooth" or word == "soft" or word == "fluid") and nextWord == "fill" then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "weiche" or word == "weichen" or word == "sanfte" or word == "fluessige") and nextWord == "fuellung" then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "relleno" or word == "llenado") and (nextWord == "suave" or nextWord == "fluido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "remplissage" and (nextWord == "doux" or nextWord == "fluide") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "riempimento" and (nextWord == "fluido" or nextWord == "morbido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "preenchimento" and (nextWord == "suave" or nextWord == "fluido") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "плавное" or word == "плавная") and (nextWord == "заполнение" or nextWord == "заливка") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "부드러운" and nextWord == "채우기") or (word == "막대" and nextWord == "애니메이션") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif word == "class" and (nextWord == "resource" or nextWord == "resources" or nextWord == "power") then
            words[#words + 1] = "classpower"
            i = i + 2
        elseif word == "click" and (nextWord == "cast" or nextWord == "casting") then
            words[#words + 1] = "clickcast"
            i = i + 2
        elseif word == "click" and nextWord == "through" then
            words[#words + 1] = "clickthrough"
            i = i + 2
        elseif word == "edit" and nextWord == "mode" then
            words[#words + 1] = "editmode"
            i = i + 2
        elseif word == "load" and (nextWord == "condition" or nextWord == "conditions") then
            words[#words + 1] = "loadconditions"
            i = i + 2
        elseif word == "ready" and nextWord == "check" then
            words[#words + 1] = "readycheck"
            i = i + 2
        elseif word == "raid" and nextWord == "marker" then
            words[#words + 1] = "raidmarker"
            i = i + 2
        elseif word == "group" and nextWord == "number" then
            words[#words + 1] = "groupnumber"
            i = i + 2
        elseif word == "name" and nextWord == "shortening" then
            words[#words + 1] = "nameshortening"
            i = i + 2
        elseif word == "global" and nextWord == "cooldown" then
            words[#words + 1] = "globalcooldown"
            i = i + 2
        elseif word == "focus" and nextWord == "kick" then
            words[#words + 1] = "fokuskick"
            i = i + 2
        elseif word == "interrupt" and nextWord == "ready" then
            words[#words + 1] = "interruptready"
            i = i + 2
        elseif word == "level" and nextWord == "text" then
            words[#words + 1] = "leveltext"
            i = i + 2
        elseif word == "level" and nextWord == "indicator" then
            words[#words + 1] = "levelindicator"
            i = i + 2
        elseif word == "status" and (nextWord == "indicator" or nextWord == "indicators") then
            words[#words + 1] = "statusindicators"
            i = i + 2
        elseif word == "status" and (nextWord == "icon" or nextWord == "icons") then
            words[#words + 1] = "statusicons"
            i = i + 2
        elseif word == "turn" and nextWord == "off" then
            words[#words + 1] = "onoff"
            i = i + 2
        elseif word == "minimap" and (nextWord == "icon" or nextWord == "button") then
            words[#words + 1] = "minimapicon"
            i = i + 2
        elseif word == "ko" and nextWord == "fi" then
            words[#words + 1] = "kofi"
            i = i + 2
        elseif word == "menu" and nextWord == "scale" then
            words[#words + 1] = "menuscale"
            i = i + 2
        elseif word == "ui" and nextWord == "scale" then
            words[#words + 1] = "uiscale"
            i = i + 2
        elseif word == "target" and (nextWord == "sound" or nextWord == "sounds") then
            words[#words + 1] = "targetsound"
            i = i + 2
        elseif word == "unit" and (nextWord == "aura" or nextWord == "auras") then
            words[#words + 1] = "unitauras"
            i = i + 2
        elseif word == "global" and nextWord == "style" then
            words[#words + 1] = "globalstyle"
            i = i + 2
        elseif word == "spell" and nextWord == "id" then
            words[#words + 1] = "spellid"
            i = i + 2
        elseif word == "health" and nextWord == "text" then
            words[#words + 1] = "healthtext"
            i = i + 2
        elseif word == "power" and nextWord == "text" then
            words[#words + 1] = "powertext"
            i = i + 2
        elseif word == "name" and nextWord == "text" then
            words[#words + 1] = "nametext"
            i = i + 2
        elseif word == "class" and nextWord == "color" then
            words[#words + 1] = "classcolor"
            i = i + 2
        elseif word == "range" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "rangecheck"
            i = i + 2
        elseif word == "distance" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "distancecheck"
            i = i + 2
        elseif word == "out" and nextWord == "range" then
            words[#words + 1] = "outofrange"
            i = i + 2
        elseif word == "unit" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "unitframe"
            i = i + 2
        elseif word == "player" and nextWord == "frame" then
            words[#words + 1] = "playerframe"
            i = i + 2
        elseif word == "target" and nextWord == "frame" then
            words[#words + 1] = "targetframe"
            i = i + 2
        elseif word == "focus" and nextWord == "frame" then
            words[#words + 1] = "focusframe"
            i = i + 2
        elseif word == "focus" and nextWord == "target" then
            words[#words + 1] = "focustarget"
            local thirdWord = raw[i + 2]
            if thirdWord == "frame" then
                words[#words + 1] = "focustargetframe"
                i = i + 3
            else
                i = i + 2
            end
        elseif word == "pet" and nextWord == "frame" then
            words[#words + 1] = "petframe"
            i = i + 2
        elseif word == "boss" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "bossframes"
            i = i + 2
        elseif word == "party" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "partyframes"
            i = i + 2
        elseif word == "raid" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "raidframes"
            i = i + 2
        else
            words[#words + 1] = word
            i = i + 1
        end
    end
    return words
end

local function BuildSearchQueryClauses(query)
    local normalized = NormalizeSearchText(query)
    if normalized == SEARCH_STATE.queryClauseCacheNorm and SEARCH_STATE.queryClauseCacheClauses then
        return normalized, SEARCH_STATE.queryClauseCacheClauses
    end
    local raw = SearchRawWords(normalized)
    local words = SearchCanonicalWords(raw)
    local clauses = {}
    for i = 1, #words do
        if #clauses >= SEARCH_MAX_QUERY_CLAUSES then break end
        local word = words[i]
        local terms, seen = {}, {}
        AddSearchTermUnique(terms, seen, word)
        local aliases = SEARCH_QUERY_ALIASES[word]
        if not aliases then
            local aliasKey = SearchAliasKeyForTypo(word)
            if aliasKey then
                AddSearchTermUnique(terms, seen, aliasKey)
                aliases = SEARCH_QUERY_ALIASES[aliasKey]
            end
        end
        if aliases then
            for k = 1, #aliases do AddSearchTermUnique(terms, seen, aliases[k]) end
        end
        if #terms > 0 then
            clauses[#clauses + 1] = { word = word, terms = terms }
        end
    end
    SEARCH_STATE.queryClauseCacheNorm = normalized
    SEARCH_STATE.queryClauseCacheClauses = clauses
    return normalized, clauses
end

local function BuildSearchTokenList(normalized, limit)
    limit = tonumber(limit) or SEARCH_MAX_RECORD_TOKENS
    local tokens, seen = {}, {}
    for token in tostring(normalized or ""):gmatch("%S+") do
        if #token >= 2 and not SEARCH_STOP_WORDS[token] and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
            if #tokens >= limit then break end
        end
    end
    return tokens
end

SearchEditDistanceWithin = function(a, b, maxDistance)
    if a == b then return true end
    maxDistance = tonumber(maxDistance) or 1
    local la, lb = #a, #b
    if math.abs(la - lb) > maxDistance then return false end

    if maxDistance <= 1 then
        if la == lb then
            local firstMismatch, mismatches = nil, 0
            for i = 1, la do
                if a:sub(i, i) ~= b:sub(i, i) then
                    mismatches = mismatches + 1
                    firstMismatch = firstMismatch or i
                    if mismatches > 2 then return false end
                end
            end
            if mismatches <= 1 then return true end
            return mismatches == 2
                and firstMismatch < la
                and a:sub(firstMismatch, firstMismatch) == b:sub(firstMismatch + 1, firstMismatch + 1)
                and a:sub(firstMismatch + 1, firstMismatch + 1) == b:sub(firstMismatch, firstMismatch)
        end

        local short, long = a, b
        if la > lb then short, long = b, a end
        local i, j, edits = 1, 1, 0
        while i <= #short and j <= #long do
            if short:sub(i, i) == long:sub(j, j) then
                i = i + 1
                j = j + 1
            else
                edits = edits + 1
                if edits > 1 then return false end
                j = j + 1
            end
        end
        return true
    end

    local prev, curr = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        curr[0] = i
        local rowMin = curr[0]
        local ca = a:sub(i, i)
        for j = 1, lb do
            local cost = (ca == b:sub(j, j)) and 0 or 1
            local value = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            curr[j] = value
            if value < rowMin then rowMin = value end
        end
        if rowMin > maxDistance then return false end
        prev, curr = curr, prev
    end
    return prev[lb] <= maxDistance
end

local function SearchFuzzyTokenMatch(rec, term)
    if not rec or #term < 5 or term:find(" ", 1, true) then return false end
    if not rec.tokens then
        rec.tokens = BuildSearchTokenList(rec.haystack or "", rec.tokenLimit)
    end
    if not rec.tokens then return false end
    local maxDistance = (#term >= 8) and 2 or 1
    for i = 1, #rec.tokens do
        local token = rec.tokens[i]
        if math.abs(#token - #term) <= maxDistance and SearchEditDistanceWithin(token, term, maxDistance) then
            return true
        end
    end
    return false
end

local function SearchTermScore(rec, term, queryWord)
    local haystack = rec.haystack or ""
    local score = 0
    if haystack:find(term, 1, true) then
        if rec.labelNorm == term or rec.titleNorm == term then score = score + 180 end
        if rec.labelNorm:sub(1, #term) == term or rec.titleNorm:sub(1, #term) == term then score = score + 90 end
        if rec.labelNorm:find(term, 1, true) then score = score + 70 end
        if rec.titleNorm:find(term, 1, true) then score = score + 55 end
        if rec.hintNorm and rec.hintNorm:find(term, 1, true) then score = score + 45 end
        if rec.groupNorm:find(term, 1, true) then score = score + 35 end
        if term ~= queryWord then score = score + 35 end
        return true, score + 10
    end
    if term == queryWord and SearchFuzzyTokenMatch(rec, term) then
        return true, (term == queryWord) and 28 or 20
    end
    return false, 0
end

local function SearchClauseScore(rec, clause)
    local best = 0
    for i = 1, #clause.terms do
        local matched, score = SearchTermScore(rec, clause.terms[i], clause.word)
        if matched and score > best then best = score end
    end
    return best > 0, best
end

local function SearchLooksLikeSupportQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    if tostring(query or ""):find("?", 1, true) then return true end
    if normalized:find("how ", 1, true) or normalized:find("where ", 1, true) or normalized:find("why ", 1, true) then return true end
    if normalized:find("what ", 1, true) or normalized:find("help ", 1, true) then return true end
    if normalized:find("do i", 1, true) or normalized:find("can i", 1, true) then return true end
    for _, word in ipairs({ "missing", "gone", "invisible", "broken", "bugged", "wrong", "offscreen", "overlap", "overlapping", "lag", "fps", "lockdown" }) do
        if normalized:find(word, 1, true) then return true end
    end
    if normalized:find("not showing", 1, true) or normalized:find("doesnt show", 1, true) or normalized:find("not working", 1, true) then return true end
    if normalized:find("too big", 1, true) or normalized:find("too small", 1, true) or normalized:find("too many", 1, true) then return true end
    for _, word in ipairs({ "move", "drag", "resize", "hide", "show", "enable", "disable", "change", "reset", "import", "export" }) do
        if normalized == word or normalized:find("^" .. word .. " ", 1, false) or normalized:find(" " .. word .. " ", 1, false) then
            return true
        end
    end
    if normalized:find("my ", 1, true) and (
        normalized:find("change", 1, true)
        or normalized:find("move", 1, true)
        or normalized:find("hide", 1, true)
        or normalized:find("show", 1, true)
        or normalized:find("not", 1, true)
    ) then
        return true
    end
    return false
end

local SEARCH_CONTROL_QUERY_TERMS = "toggle checkbox switch enable disable enabled disabled show hide dropdown select choose slider adjust increase decrease color colour swatch input field textfield editbox aktivier deaktivier einschalt ausschalt anzeigen ausblenden auswahl auswaehlen dropdown regler schieberegler aument reducir ajustar seleccionar choisir activer desactiver selezionare attivare disattivare ativar desativar выбрать включить отключить 설정 선택 사용 비활성 활성 下拉 选择 啟用 停用 選擇"

local function SearchLooksLikeControlQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    if normalized:find("turn on", 1, true) or normalized:find("turn off", 1, true) then return true end
    for term in SEARCH_CONTROL_QUERY_TERMS:gmatch("%S+") do
        term = NormalizeSearchText(term)
        if term ~= "" and normalized:find(term, 1, true) then return true end
    end
    return false
end

local SEARCH_GENERIC_LOCATION_QUESTION_TERMS = {
    "where", "where is", "where are", "where do", "where can", "where to",
    "how do", "how to", "how can", "wo", "wo ist", "wo sind", "wo kann", "wo finde",
    "wie", "wie kann",
}

local SEARCH_GENERIC_LOCATION_ACTION_TERMS = {
    "change", "changed", "changing", "configure", "customize", "customise", "edit",
    "find", "set", "select", "choose", "adjust", "move", "resize", "enable",
    "disable", "show", "hide", "turn on", "turn off", "aendern", "aendere", "andern",
    "einstellen", "finden", "auswaehlen", "verschieben",
    "aktivieren", "deaktivieren", "anzeigen", "ausblenden",
}

local SEARCH_CONTROL_KINDS = {
    toggle = true,
    dropdown = true,
    segment = true,
    slider = true,
    color = true,
    button = true,
    textinput = true,
}

local function SearchContainsTerm(normalized, term)
    normalized = tostring(normalized or "")
    term = NormalizeSearchText(term)
    if normalized == "" or term == "" then return false end
    if term:find(" ", 1, true) then return normalized:find(term, 1, true) ~= nil end
    return (" " .. normalized .. " "):find(" " .. term .. " ", 1, true) ~= nil
end

local function SearchContainsAnyTerm(normalized, terms)
    if type(terms) ~= "table" then return false end
    for i = 1, #terms do
        if SearchContainsTerm(normalized, terms[i]) then return true end
    end
    return false
end

local function SearchLooksLikeGenericLocationQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    local hasQuestion = SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_QUESTION_TERMS)
    if not hasQuestion then return false end
    if normalized:find("where is", 1, true) or normalized:find("where are", 1, true) then return true end
    if normalized:find("wo ist", 1, true) or normalized:find("wo sind", 1, true) then return true end
    return SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_ACTION_TERMS)
end

local function SearchGenericLocationSubjectClauses(query)
    if not SearchLooksLikeGenericLocationQuestion(query) then return nil, nil end
    local raw = SearchRawWords(NormalizeSearchText(query))
    if #raw == 0 then return nil, nil end
    local words = SearchCanonicalWords(raw)
    local subject = table.concat(words, " ")
    if subject == "" then return nil, nil end
    local subjectNorm, subjectClauses = BuildSearchQueryClauses(subject)
    if type(subjectClauses) ~= "table" or #subjectClauses == 0 then return nil, nil end
    return subjectNorm, subjectClauses
end

local function SearchDirectSubjectMatches(rec, clauses)
    if not rec or type(clauses) ~= "table" then return 0, 0, 0 end
    local labelText = tostring(rec.labelNorm or "") .. " " .. tostring(rec.titleNorm or "")
    local contextText = labelText .. " " .. tostring(rec.hintNorm or "") .. " " .. tostring(rec.groupNorm or "")
    local haystack = tostring(rec.haystack or "")
    local labelMatches, contextMatches, haystackMatches = 0, 0, 0
    for i = 1, #clauses do
        local terms = clauses[i] and clauses[i].terms
        local inLabel, inContext, inHaystack = false, false, false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if term and term ~= "" then
                    if labelText:find(term, 1, true) then inLabel = true end
                    if contextText:find(term, 1, true) then inContext = true end
                    if haystack:find(term, 1, true) then inHaystack = true end
                end
                if inLabel and inContext and inHaystack then break end
            end
        end
        if inLabel then labelMatches = labelMatches + 1 end
        if inContext then contextMatches = contextMatches + 1 end
        if inHaystack then haystackMatches = haystackMatches + 1 end
    end
    return labelMatches, contextMatches, haystackMatches
end

local function SearchGenericLocationBoost(rec, clauses, matchedClauses, missedClauses)
    if not rec or type(clauses) ~= "table" or #clauses == 0 then return 0 end
    local labelMatches, contextMatches, haystackMatches = SearchDirectSubjectMatches(rec, clauses)
    local direct = math.max(labelMatches, contextMatches)
    local allMatched = (tonumber(missedClauses) or 0) == 0 and (tonumber(matchedClauses) or 0) >= #clauses

    if SEARCH_CONTROL_KINDS[rec.kind or ""] then
        if labelMatches > 0 then return 860 + labelMatches * 160 end
        if contextMatches > 0 then return 640 + contextMatches * 120 end
        if allMatched then return 420 end
        return -120
    end
    if rec.kind == "section" then
        if labelMatches > 0 then return 560 + labelMatches * 120 end
        if contextMatches > 0 then return 360 + contextMatches * 80 end
        if allMatched then return 180 end
        return -80
    end
    if rec.kind == "page" then
        if direct > 0 then return 110 + direct * 45 end
        if haystackMatches > 0 then return 40 end
        return -80
    end
    if rec.kind == "faq" then
        if labelMatches >= #clauses and #clauses >= 2 then return 100 end
        if direct > 0 then return -120 end
        return -260
    end
    if direct > 0 then return 180 + direct * 60 end
    return allMatched and 80 or 0
end

local function SearchSupportQuestionBoost(rec, clauses)
    if not rec or rec.kind ~= "faq" then return 0 end
    local haystack = rec.haystack or ""
    local direct = 0
    for i = 1, #(clauses or {}) do
        local word = clauses[i].word
        if word and word ~= "" and haystack:find(word, 1, true) then
            direct = direct + 1
        end
    end
    if direct > 0 then return 160 + direct * 90 end
    return -160
end

local function SearchResultSpecificityBoost(rec, clauses)
    if not rec then return 0 end
    local clauseCount = #(clauses or {})
    if clauseCount == 0 then return 0 end

    local label = rec.labelNorm or ""
    local title = rec.titleNorm or ""
    local direct = 0
    for i = 1, clauseCount do
        local clause = clauses[i]
        local terms = clause and clause.terms
        local matched = false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if term and term ~= "" and (label:find(term, 1, true) or title:find(term, 1, true)) then
                    matched = true
                    break
                end
            end
        end
        if matched then direct = direct + 1 end
    end

    if direct == 0 then
        if rec.kind == "faq" and clauseCount >= 2 then return -90 end
        if rec.kind == "page" and clauseCount >= 3 then return -40 end
        return 0
    end

    local boost = direct * 45
    if direct == clauseCount and clauseCount >= 2 then
        if rec.kind == "page" then
            boost = boost + 90
        elseif rec.kind == "faq" then
            boost = boost + 100
        else
            boost = boost + 260
        end
    end
    return boost
end

local function IsSearchableDisplayText(text)
    text = DisplaySearchText(text)
    if text == "" or #text > SEARCH_TEXT_MAX_LEN then return false end
    local normalized = NormalizeSearchText(text)
    if normalized == "" or SEARCH_NOISE_TEXT[normalized] then return false end
    if #normalized < 2 then return false end
    return true
end

local function FontStringText(region)
    if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return nil end
    local raw = region._msuf2SearchText
    local text = raw
    if text == nil and region.GetText then text = region:GetText() end
    text = DisplaySearchText(text)
    if text == "" then return nil end
    return text
end

local function SearchValueText(item)
    if type(item) == "table" then
        return item.text or item.label or item.name or item.title or item.value or item.key
    end
    return item
end

local function AddValuesSearchText(parts, values)
    if type(values) == "function" then
        local ok, resolved = pcall(values)
        if not ok then return end
        values = resolved
    end
    if type(values) ~= "table" then return end
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        AddSearchText(parts, SearchValueText(item))
        if type(item) == "table" then
            AddSearchText(parts, item.tooltip)
            AddSearchText(parts, item.desc or item.description)
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            AddSearchText(parts, key)
            AddSearchText(parts, SearchValueText(item))
            if type(item) == "table" then
                AddSearchText(parts, item.tooltip)
                AddSearchText(parts, item.desc or item.description)
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
end

local function SearchSectionTitle(frame)
    if not frame then return nil end
    local entry = frame._msuf2CollapsibleEntry
    if entry and entry.label then
        local text = FontStringText(entry.label)
        if IsSearchableDisplayText(text) then return text end
    end
    if frame.title then
        local text = FontStringText(frame.title)
        if IsSearchableDisplayText(text) then return text end
    end
    if IsSearchableDisplayText(frame._msuf2SearchTitle) then return DisplaySearchText(frame._msuf2SearchTitle) end
    return nil
end

local function SectionPathForAnchor(anchor, pageTitle)
    local path, seen = {}, {}
    local parent = anchor and anchor.GetParent and anchor:GetParent()
    local pageNorm = NormalizeSearchText(pageTitle or "")
    while parent do
        local title = SearchSectionTitle(parent)
        local norm = NormalizeSearchText(title or "")
        if norm ~= "" and norm ~= pageNorm and not seen[norm] then
            seen[norm] = true
            table.insert(path, 1, title)
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return path
end

local function SearchHint(pageInfo, anchor)
    local parts, seen = {}, {}
    local function Add(text)
        text = SearchDisplayText(text)
        local norm = NormalizeSearchText(text)
        if norm ~= "" and not seen[norm] then
            seen[norm] = true
            parts[#parts + 1] = text
        end
    end
    Add(pageInfo.group)
    Add(pageInfo.label or pageInfo.title)
    local sections = SectionPathForAnchor(anchor, pageInfo.title or pageInfo.label)
    for i = 1, #sections do Add(sections[i]) end
    return table.concat(parts, " > ")
end

local function BuildSearchPageInfos()
    local groupLabels, navInfo = {}, {}
    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.header then groupLabels[item.id or item.header] = item.header end
    end

    local infos, seen = {}, {}
    local function AddPageInfo(key, label, group)
        if not key or key == "search" or seen[key] then return end
        seen[key] = true
        local spec = M.pages[key]
        local info = {
            key = key,
            label = M.Tr(label or (spec and spec.title) or key),
            group = group and M.Tr(group) or "",
            title = M.Tr((spec and spec.title) or label or key),
        }
        infos[#infos + 1] = info
        navInfo[key] = info
    end

    for i = 1, #NAV_ITEMS do
        local item = NAV_ITEMS[i]
        if item.key then
            AddPageInfo(item.key, item.label, item.group and groupLabels[item.group] or nil)
        end
    end
    for i = 1, #(M.pageOrder or {}) do
        local key = M.pageOrder[i]
        local spec = M.pages[key]
        AddPageInfo(key, spec and spec.title or key, nil)
    end
    return infos, navInfo
end

local function BuildSearchPageInfoForKey(pageKey)
    local spec = M.pages and M.pages[pageKey]
    local title = (spec and spec.title) or pageKey or ""
    return {
        key = pageKey,
        label = M.Tr(title),
        group = "",
        title = M.Tr(title),
    }
end

local function ClearSearchRegistryPage(pageKey)
    if not pageKey then return end
    local ids = SEARCH_STATE.registryByPage[pageKey]
    if ids then
        for i = 1, #ids do
            SEARCH_STATE.registry[ids[i]] = nil
            SEARCH_STATE.registryRecords[ids[i]] = nil
        end
        SEARCH_STATE.registryByPage[pageKey] = nil
        MarkSearchIndexDirty()
    end
end

local function CopyStaticSearchValues(values)
    if type(values) == "function" then
        local ok, resolved = pcall(values)
        if not ok then return nil end
        values = resolved
    end
    if type(values) ~= "table" then return nil end
    local out, count = {}, 0
    local limit = math.min(#values, 32)
    for i = 1, limit do
        local item = values[i]
        local text = SearchValueText(item)
        if text ~= nil then
            count = count + 1
            out[count] = text
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            count = count + 1
            out[count] = key
            local text = SearchValueText(item)
            if text ~= nil then
                count = count + 1
                out[count] = text
            end
            extra = extra + 1
            if extra >= 12 then break end
        end
    end
    return count > 0 and out or nil
end

local BuildRegistrySearchRecord

function M.RegisterSearchWidget(widget, meta)
    if not widget or type(meta) ~= "table" then return end
    EnsureSearchLocaleFresh()
    local pageKey = meta.pageKey or M._msuf2SearchBuildKey or M.activeKey
    if type(pageKey) ~= "string" or pageKey == "" or pageKey == "search" then return end

    local label = DisplaySearchText(meta.label or meta.title or meta.text or widget._msuf2SearchText or widget._msuf2SearchTitle)
    if not IsSearchableDisplayText(label) then return end

    local id = widget._msuf2SearchRegistryId
    if not id or widget._msuf2SearchRegistryPage ~= pageKey or not SEARCH_STATE.registry[id] then
        SEARCH_STATE.registrySerial = SEARCH_STATE.registrySerial + 1
        id = pageKey .. ":" .. tostring(SEARCH_STATE.registrySerial)
        widget._msuf2SearchRegistryId = id
        widget._msuf2SearchRegistryPage = pageKey
        SEARCH_STATE.registryByPage[pageKey] = SEARCH_STATE.registryByPage[pageKey] or {}
        SEARCH_STATE.registryByPage[pageKey][#SEARCH_STATE.registryByPage[pageKey] + 1] = id
    end

    local entry = {
        id = id,
        pageKey = pageKey,
        label = label,
        kind = meta.kind or widget._msuf2ControlKind or "control",
        anchor = meta.anchor or widget._msuf2Title or widget._msuf2Label or widget,
        values = CopyStaticSearchValues(meta.values or widget.values),
        keywords = meta.keywords,
        help = meta.help or meta.description,
    }
    SEARCH_STATE.registry[id] = entry
    SEARCH_STATE.registryRecords[id] = nil
    MarkSearchIndexDirty()
end

local function AddSearchRecord(records, seenRecords, pageInfo, label, anchor, kind, extraParts)
    label = DisplaySearchText(label)
    if not IsSearchableDisplayText(label) then return end

    kind = kind or "text"
    local displayLabel = SearchDisplayText(label)
    if displayLabel == "" then displayLabel = label end
    local displayHint = SearchHint(pageInfo, anchor)
    local hint = (kind == "faq") and "" or displayHint
    local parts = {}
    AddSearchText(parts, label)
    if kind ~= "faq" then
        AddSearchText(parts, hint)
        AddSearchText(parts, pageInfo.label)
        AddSearchText(parts, pageInfo.group)
        AddSearchText(parts, pageInfo.title)
    end
    if kind == "page" then
        AddRawSearchText(parts, SEARCH_KEYWORDS[pageInfo.key])
    end
    if kind == "toggle" then
        AddToggleQuestionSearchText(parts, label)
    end
    if extraParts then
        for i = 1, #extraParts do AddSearchText(parts, extraParts[i]) end
    end

    local recordId = table.concat({
        tostring(pageInfo.key or ""),
        tostring(kind or ""),
        tostring(anchor or ""),
        NormalizeSearchText(label),
        NormalizeSearchText(hint),
    }, "\031")
    if seenRecords[recordId] then return end
    seenRecords[recordId] = true

    displayHint = DisplaySearchText(displayHint)
    local displayGroup = (kind == "faq") and "" or SearchDisplayText(pageInfo.group or "")
    local displayTitle = (kind == "faq") and "" or SearchDisplayText(pageInfo.title or pageInfo.label or "")
    local labelNorm = NormalizeSearchText(displayLabel)
    local titleNorm = (kind == "faq") and "" or NormalizeSearchText(displayTitle)
    local groupNorm = (kind == "faq") and "" or NormalizeSearchText(displayGroup)
    local hintNorm = (kind == "faq") and "" or NormalizeSearchText(displayHint)
    local haystackText = table.concat(parts, " ")
    if kind ~= "faq" and kind ~= "page" and #haystackText > SEARCH_CONTROL_HAYSTACK_MAX_LEN then
        haystackText = haystackText:sub(1, SEARCH_CONTROL_HAYSTACK_MAX_LEN)
    end
    local haystackNorm = NormalizeSearchText(haystackText)
    local record = {
        key = pageInfo.key,
        label = displayLabel,
        group = displayGroup,
        title = displayTitle,
        hint = displayHint,
        kind = kind,
        anchor = anchor,
        labelNorm = labelNorm,
        groupNorm = groupNorm,
        titleNorm = titleNorm,
        hintNorm = hintNorm,
        haystack = haystackNorm,
        tokenLimit = (kind ~= "faq" and kind ~= "page")
            and SEARCH_CONTROL_MAX_TOKENS
            or SEARCH_MAX_RECORD_TOKENS,
        order = #records + 1,
    }
    records[#records + 1] = record
    return record
end

BuildRegistrySearchRecord = function(entry)
    if type(entry) ~= "table" then return nil end
    local info = BuildSearchPageInfoForKey(entry.pageKey)
    local extra = {}
    AddValuesSearchText(extra, entry.values)
    if type(entry.keywords) == "string" then
        AddSearchText(extra, entry.keywords)
    elseif type(entry.keywords) == "table" then
        for i = 1, #entry.keywords do AddSearchText(extra, entry.keywords[i]) end
    end
    AddControlQuestionSearchText(extra, entry.label, entry.kind, entry.values)
    AddSearchText(extra, entry.help)
    local tempRecords, seenRecords = {}, {}
    local rec = AddSearchRecord(tempRecords, seenRecords, info, entry.label, entry.anchor, entry.kind or "control", extra)
    if rec then
        rec.answer = entry.help
    end
    return rec
end

local SEARCH_FAQ = SearchData.BuildFAQ and SearchData.BuildFAQ({
    SearchKeywordList = SearchKeywordList,
    DASHBOARD_ROUTE_RECOVERY = DASHBOARD_ROUTE_RECOVERY,
    DASHBOARD_ROUTE_SCALING = DASHBOARD_ROUTE_SCALING,
    DASHBOARD_ROUTE_CHANGELOG = DASHBOARD_ROUTE_CHANGELOG,
    SEARCH_DISPEL_DEBUFF_KEYWORDS = SEARCH_DISPEL_DEBUFF_KEYWORDS,
    SEARCH_HIGHLIGHT_BORDER_KEYWORDS = SEARCH_HIGHLIGHT_BORDER_KEYWORDS,
    SEARCH_DISPEL_OVERLAY_KEYWORDS = SEARCH_DISPEL_OVERLAY_KEYWORDS,
    SEARCH_DEBUFF_STRIPE_KEYWORDS = SEARCH_DEBUFF_STRIPE_KEYWORDS,
    SEARCH_BLIZZARD_DISPEL_KEYWORDS = SEARCH_BLIZZARD_DISPEL_KEYWORDS,
    SEARCH_UNIT_AURA_DISPEL_KEYWORDS = SEARCH_UNIT_AURA_DISPEL_KEYWORDS,
    SEARCH_DASHBOARD_RECOVERY_KEYWORDS = SEARCH_DASHBOARD_RECOVERY_KEYWORDS,
    SEARCH_DASHBOARD_DISCORD_KEYWORDS = SEARCH_DASHBOARD_DISCORD_KEYWORDS,
    SEARCH_DASHBOARD_SUPPORT_KEYWORDS = SEARCH_DASHBOARD_SUPPORT_KEYWORDS,
    SEARCH_DASHBOARD_WAGO_KEYWORDS = SEARCH_DASHBOARD_WAGO_KEYWORDS,
    SEARCH_DASHBOARD_SCALING_KEYWORDS = SEARCH_DASHBOARD_SCALING_KEYWORDS,
    SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = SEARCH_DASHBOARD_CHANGELOG_KEYWORDS,
}) or {}

local SEARCH_EASTER_EGGS = SearchData.EASTER_EGGS or {}

local function BuildSearchRecords()
    local pageInfos, pageInfoByKey = BuildSearchPageInfos()

    local records, seenRecords = {}, {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local pageParts = {}
        AddSearchText(pageParts, info.group)
        AddSearchText(pageParts, info.title)
        AddRawSearchText(pageParts, SEARCH_KEYWORDS[info.key])
        AddPageLocalizedSearchKeywords(pageParts, info.key)
        AddSearchRecord(records, seenRecords, info, info.label or info.title or info.key, nil, "page", pageParts)
    end

    for _, entry in pairs(SEARCH_STATE.registry) do
        local rec = SEARCH_STATE.registryRecords[entry.id]
        if not rec and BuildRegistrySearchRecord then
            rec = BuildRegistrySearchRecord(entry)
            SEARCH_STATE.registryRecords[entry.id] = rec
        end
        if rec then
            rec.order = #records + 1
            records[#records + 1] = rec
        end
    end

    for i = 1, #SEARCH_FAQ do
        local faq = SEARCH_FAQ[i]
        local pageKey = faq.pageKey or "home"
        local info = pageInfoByKey[pageKey] or { key = pageKey, label = "FAQ", title = "FAQ", group = "" }
        local extra = { faq.answer, faq.target, faq.anchorText }
        for k = 1, #(faq.keywords or {}) do extra[#extra + 1] = faq.keywords[k] end
        local rec = AddSearchRecord(records, seenRecords, info, faq.label, nil, "faq", extra)
        if rec then
            rec.answer = faq.answer
            rec.target = faq.target
            rec.anchorFallback = faq.anchorText or faq.label
            rec.route = faq.route
            rec.priority = tonumber(faq.priority) or 0
            rec.faq = true
        end
    end

    for i = 1, #SEARCH_EASTER_EGGS do
        local egg = SEARCH_EASTER_EGGS[i]
        local info = { key = "search", label = "", title = "", group = "" }
        local rec = AddSearchRecord(records, seenRecords, info, egg.name, nil, "easteregg", { egg.result, egg.name })
        if rec then
            rec.answer = egg.result
            rec.noOpen = true
            rec.priority = 1200
            rec.easterEgg = true
        end
    end

    return records
end

local SearchPages

local function RefreshSearchResultsPage()
    if M.activeKey ~= "search" then return end
    local query = TrimText(M.searchQuery or "")
    if query == "" or #NormalizeSearchText(query) < MIN_SEARCH_QUERY_LEN then return end
    M.searchResults = nil
    M.searchResultsQuery = nil
    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if M.InvalidatePage then M.InvalidatePage("search") end
    if M.SelectPage then M.SelectPage("search") end
end

local function FinishSearchBackgroundIndex()
    SEARCH_STATE.indexing = false
    SEARCH_STATE.indexQueue = nil
    local query = TrimText(M.searchQuery or "")
    local shouldRefresh = M.activeKey == "search" and query ~= "" and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    if shouldRefresh and SEARCH_STATE.recordsDirty then
        SEARCH_STATE.records = BuildSearchRecords()
        SEARCH_STATE.recordsDirty = false
    end
    if shouldRefresh then RefreshSearchResultsPage() end
end

local function StartSearchBackgroundIndex()
    if SEARCH_STATE.indexing then return end
    if SearchCombatLocked() then return end
    if not (_G.C_Timer and _G.C_Timer.After) then return end
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    if not M.scrollChild then return end

    local pageInfos = BuildSearchPageInfos()
    local queue = {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local cached = M.cache and M.cache[info.key]
        if info.key ~= "search" and not (cached and cached.wrapper) then
            queue[#queue + 1] = info.key
        end
    end
    if #queue == 0 then return end

    SEARCH_STATE.indexing = true
    SEARCH_STATE.indexQueue = queue

    local function Step()
        if not SEARCH_STATE.indexing then return end
        if M.activeKey ~= "search" or SearchCombatLocked() or not (M.frame and M.frame.IsShown and M.frame:IsShown()) then
            CancelSearchBackgroundIndex()
            return
        end

        local key = table.remove(SEARCH_STATE.indexQueue, 1)
        if key then
            if M.BuildPageEntry then M.BuildPageEntry(key, true) end
            MarkSearchIndexDirty()
        end

        if SEARCH_STATE.indexQueue and #SEARCH_STATE.indexQueue > 0 then
            _G.C_Timer.After(SEARCH_BACKGROUND_STEP_SEC, Step)
        else
            FinishSearchBackgroundIndex()
        end
    end

    _G.C_Timer.After(0, Step)
end

local function GetSearchRecords()
    EnsureSearchLocaleFresh()
    if SEARCH_STATE.indexing and SEARCH_STATE.records and not SEARCH_STATE.recordsDirty then
        return SEARCH_STATE.records
    end
    if not SEARCH_STATE.records or SEARCH_STATE.recordsDirty then
        SEARCH_STATE.records = BuildSearchRecords()
        SEARCH_STATE.recordsDirty = false
    end
    StartSearchBackgroundIndex()
    return SEARCH_STATE.records
end

local function CurateSearchResults(results, supportQuestion)
    local topScore = results[1] and (tonumber(results[1].score) or 0) or 0
    local floorScore = SEARCH_MIN_RESULT_SCORE
    if topScore >= 600 then
        floorScore = math.max(floorScore, topScore * (supportQuestion and 0.70 or 0.42))
    elseif topScore >= 300 then
        floorScore = math.max(floorScore, topScore * 0.30)
    end

    local function SpecificControlMatch(rec)
        local clauseCount = tonumber(rec and rec.queryClauseCount) or 0
        if clauseCount < 2 then return false end
        if rec.kind == "page" or rec.kind == "faq" or rec.kind == "easteregg" then return false end
        return (tonumber(rec.missedClauses) or 0) == 0 and (tonumber(rec.matchedClauses) or 0) == clauseCount
    end

    local curated = {}
    for i = 1, #results do
        local rec = results[i]
        if rec and ((tonumber(rec.score) or 0) >= floorScore or SpecificControlMatch(rec)) then
            curated[#curated + 1] = rec
            if #curated >= SEARCH_MAX_RESULTS then break end
        end
    end
    return curated
end

function SearchPages(query)
    query = TrimText(query)
    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        return {}
    end
    local normalized, clauses = BuildSearchQueryClauses(query)
    if #clauses == 0 then return {} end
    if #normalized < MIN_SEARCH_QUERY_LEN then return {} end

    local supportQuestion = SearchLooksLikeSupportQuestion(query)
    local genericLocationSubject, genericLocationClauses = SearchGenericLocationSubjectClauses(query)
    local genericLocationQuestion = genericLocationSubject ~= nil and genericLocationClauses ~= nil
    local controlQuestion = SearchLooksLikeControlQuestion(query) or genericLocationQuestion
    local profileTransferQuestion = normalized:find("import", 1, true)
        or normalized:find("export", 1, true)
        or normalized:find("profile string", 1, true)
        or normalized:find("legacy import", 1, true)
    local wagoBrowseQuestion = (normalized:find("wago", 1, true) and normalized:find("profile", 1, true))
        or normalized:find("browse wago", 1, true)
        or normalized:find("wago hub", 1, true)
    if profileTransferQuestion then wagoBrowseQuestion = false end
    local requiredMatches = #clauses
    if supportQuestion and #clauses > 3 then
        requiredMatches = math.max(2, math.ceil(#clauses * 0.55))
    end
    local results = {}
    local records = GetSearchRecords()
    for i = 1, #records do
        local rec = records[i]
        local score = 0
        local matched = true
        local matchedClauses = 0
        local missedClauses = 0
        for c = 1, #clauses do
            local ok, clauseScore = SearchClauseScore(rec, clauses[c])
            if not ok then
                missedClauses = missedClauses + 1
                if requiredMatches == #clauses or (#clauses - missedClauses) < requiredMatches then
                    matched = false
                    break
                end
            else
                matchedClauses = matchedClauses + 1
                score = score + clauseScore
            end
        end
        if matched and matchedClauses >= requiredMatches then
            if rec.labelNorm == normalized or rec.titleNorm == normalized then score = score + 260 end
            if rec.labelNorm:sub(1, #normalized) == normalized then score = score + 130 end
            if rec.haystack and rec.haystack:find(normalized, 1, true) then score = score + 80 end
            if rec.kind == "section" then score = score + 70 end
            if rec.kind == "faq" then score = score + 55 end
            if supportQuestion and not genericLocationQuestion then score = score + SearchSupportQuestionBoost(rec, clauses) end
            if genericLocationQuestion then score = score + SearchGenericLocationBoost(rec, genericLocationClauses, matchedClauses, missedClauses) end
            score = score + SearchResultSpecificityBoost(rec, clauses)
            if missedClauses > 0 then score = score - (missedClauses * 60) end
            if rec.kind ~= "page" then score = score + 45 end
            if rec.kind == "slider" or rec.kind == "dropdown" or rec.kind == "toggle" then score = score + 25 end
            if controlQuestion
                and (rec.kind == "toggle" or rec.kind == "dropdown" or rec.kind == "slider" or rec.kind == "segment"
                    or rec.kind == "textinput" or rec.kind == "color")
                and #clauses >= 2 and missedClauses == 0 and matchedClauses == #clauses then
                score = score + 1300
            end
            if rec.priority then score = score + rec.priority end
            if profileTransferQuestion then
                if rec.key == "profiles" then score = score + 520 end
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score - 520 end
            elseif wagoBrowseQuestion then
                if rec.key == "home" and rec.labelNorm == "wago profile hub" then score = score + 720 end
                if rec.key == "profiles" and rec.kind == "page" then score = score - 180 end
            end
            rec.score = score
            rec.matchedClauses = matchedClauses
            rec.missedClauses = missedClauses
            rec.queryClauseCount = #clauses
            results[#results + 1] = rec
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.hint or "") ~= (b.hint or "") then return tostring(a.hint or "") < tostring(b.hint or "") end
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
        return tostring(a.label) < tostring(b.label)
    end)
    return CurateSearchResults(results, supportQuestion and not genericLocationQuestion)
end

local function SearchQueryReady(query)
    return #NormalizeSearchText(query or "") >= MIN_SEARCH_QUERY_LEN
end

local function ShowSearchPageForQuery(query)
    query = TrimText(query)
    if query ~= "" and M.activeKey ~= "search" then
        M.searchReturnKey = M.activeKey or M.searchReturnKey or "home"
    end
    M.InvalidatePage("search")
    if query ~= "" then
        M.SelectPage("search")
    elseif M.activeKey == "search" then
        M.SelectPage(M.searchReturnKey or "home")
    end
end

local function RunSearchInputQuery(query, openPage)
    query = TrimText(query)
    M.searchQuery = query
    M.searchResultsPending = nil

    if query == "" then
        M.searchResults = {}
        M.searchResultsQuery = ""
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage and M.activeKey ~= "search" then ShowSearchPageForQuery(query) end
        return
    end

    if not SearchQueryReady(query) then
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if openPage then ShowSearchPageForQuery(query) end
end

local function ScheduleSearchInputQuery(searchBox, query)
    query = TrimText(query)
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    local serial = SEARCH_STATE.inputSerial

    M.searchQuery = query

    if query == "" or SearchCombatLocked() or not SearchQueryReady(query) then
        RunSearchInputQuery(query, true)
        return
    end

    M.searchResultsPending = true
    M.searchResultsQuery = query
    if M.activeKey ~= "search" then
        M.searchResults = {}
        ShowSearchPageForQuery(query)
    end

    local function RunLatest()
        if serial ~= SEARCH_STATE.inputSerial then return end
        if searchBox and searchBox.GetText then
            local latest = TrimText(searchBox:GetText() or "")
            if latest ~= query then return end
        end
        RunSearchInputQuery(query, true)
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(SEARCH_INPUT_DEBOUNCE_SEC, RunLatest)
    else
        RunLatest()
    end
end

local function OpenSearchResults(query)
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    RunSearchInputQuery(query, true)
end

local function ScoreAnchorTextClauses(normalized, queryNorm, clauses)
    if normalized == "" or type(clauses) ~= "table" or #clauses == 0 then return 0 end
    local score, matched = 0, 0
    if queryNorm ~= "" then
        if normalized == queryNorm then score = score + 900 end
        if normalized:find(queryNorm, 1, true) then score = score + 260 end
    end
    local tokens = BuildSearchTokenList(normalized)
    for i = 1, #clauses do
        local clause = clauses[i]
        local best = 0
        for k = 1, #clause.terms do
            local term = clause.terms[k]
            if normalized == term then
                best = math.max(best, 220)
            elseif normalized:sub(1, #term) == term then
                best = math.max(best, 130)
            elseif normalized:find(term, 1, true) then
                best = math.max(best, 70)
            elseif #term >= 5 and not term:find(" ", 1, true) then
                local maxDistance = (#term >= 8) and 2 or 1
                for t = 1, #tokens do
                    if math.abs(#tokens[t] - #term) <= maxDistance and SearchEditDistanceWithin(tokens[t], term, maxDistance) then
                        best = math.max(best, 24)
                        break
                    end
                end
            end
        end
        if best > 0 then
            score = score + best
            matched = matched + 1
        end
    end
    if matched == 0 then return 0 end
    if matched == #clauses then score = score + 180 else score = score - ((#clauses - matched) * 35) end
    if #normalized <= 42 then score = score + 30 end
    if #normalized > 120 then score = score - 40 end
    return score
end

local function ScoreAnchorText(text, query, fallback)
    local normalized = NormalizeSearchText(text)
    if normalized == "" then return 0 end
    local queryNorm, clauses = BuildSearchQueryClauses(query)
    local queryScore = ScoreAnchorTextClauses(normalized, queryNorm, clauses)

    local fallbackScore = 0
    if fallback and fallback ~= query then
        local fallbackNorm, fallbackClauses = BuildSearchQueryClauses(fallback)
        fallbackScore = ScoreAnchorTextClauses(normalized, fallbackNorm, fallbackClauses)
    end

    if queryScore > 0 and fallbackScore > 0 then
        return queryScore + math.floor(fallbackScore * 0.25)
    end
    return math.max(queryScore, math.floor(fallbackScore * 0.75))
end

local function CollectSearchAnchorCandidates(frame, out, depth)
    if not frame or depth > 16 then return end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                local text = region:GetText()
                if text and text ~= "" then
                    out[#out + 1] = { region = region, text = text }
                end
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            CollectSearchAnchorCandidates(children[i], out, depth + 1)
        end
    end
end

local function FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return nil end
    if preferredAnchor and preferredAnchor.GetTop then return preferredAnchor end

    local candidates = {}
    CollectSearchAnchorCandidates(wrapper, candidates, 1)

    local best, bestScore
    for i = 1, #candidates do
        local candidate = candidates[i]
        local score = ScoreAnchorText(candidate.text, query, fallback)
        if score > 0 and (not bestScore or score > bestScore) then
            best, bestScore = candidate, score
        end
    end
    return best and best.region or nil
end

local function OpenAnchorCollapsibles(region)
    local entries, seen = {}, {}
    local parent = region and region.GetParent and region:GetParent()
    while parent do
        local entry = parent._msuf2CollapsibleEntry
        if entry and not seen[entry] then
            seen[entry] = true
            entries[#entries + 1] = entry
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end

    local opened = false
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry and not entry.open and entry.header and entry.header.Click then
            entry.header:Click()
            opened = true
        end
    end
    return opened
end

local function ClampScrollOffset(offset)
    offset = math.max(0, tonumber(offset) or 0)
    local childH = (M.scrollChild and M.scrollChild.GetHeight and M.scrollChild:GetHeight()) or ContentHeight()
    local frameH = (M.scrollFrame and M.scrollFrame.GetHeight and M.scrollFrame:GetHeight()) or ContentHeight()
    local maxScroll = math.max(0, childH - frameH)
    if offset > maxScroll then offset = maxScroll end
    return offset
end

local function SearchAnchorOffset(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return nil end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return nil end
    return ClampScrollOffset((wrapperTop - regionTop) - 42)
end

local function HighlightSearchAnchor(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return end

    local offset = math.max(0, wrapperTop - regionTop)
    local highlight = wrapper._msuf2SearchHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, wrapper)
        highlight:SetFrameLevel((wrapper.GetFrameLevel and wrapper:GetFrameLevel() or 1) + 40)
        local fill = highlight:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0.20, 0.58, 1.00, 0.16)
        local top = highlight:CreateTexture(nil, "ARTWORK")
        top:SetHeight(1)
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetColorTexture(0.38, 0.78, 1.00, 0.65)
        local bottom = highlight:CreateTexture(nil, "ARTWORK")
        bottom:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetColorTexture(0.38, 0.78, 1.00, 0.45)
        highlight._msuf2Anim = highlight:CreateAnimationGroup()
        local fade = highlight._msuf2Anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.75)
        fade:SetDuration(0.75)
        highlight._msuf2Anim:SetScript("OnFinished", function()
            if highlight then highlight:Hide() end
        end)
        wrapper._msuf2SearchHighlight = highlight
    end
    if highlight._msuf2Anim and highlight._msuf2Anim.Stop then highlight._msuf2Anim:Stop() end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 8, -math.max(0, offset - 9))
    highlight:SetSize(math.max(220, (wrapper.GetWidth and wrapper:GetWidth() or ContentWidth()) - 28), 32)
    highlight:SetAlpha(1)
    highlight:Show()
    if highlight._msuf2Anim and highlight._msuf2Anim.Play then highlight._msuf2Anim:Play() end
end

local function RunSoon(fn)
    if SearchCombatLocked() then
        fn()
        return
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end

local function SearchRouteHasAny(normalized, terms)
    if normalized == "" or type(terms) ~= "table" then return false end
    for i = 1, #terms do
        local term = NormalizeSearchText(terms[i])
        if term ~= "" and normalized:find(term, 1, true) then return true end
    end
    return false
end

local function SearchNewRoute()
    return { state = {}, accordion = {}, tables = {}, nestedTables = {}, general = {} }
end

local function SearchRouteIsEmpty(route)
    if type(route) ~= "table" then return true end
    for _ in pairs(route.state or {}) do return false end
    for _ in pairs(route.accordion or {}) do return false end
    for _ in pairs(route.general or {}) do return false end
    for _, values in pairs(route.tables or {}) do
        if type(values) == "table" then
            for _ in pairs(values) do return false end
        end
    end
    for _, firstLevel in pairs(route.nestedTables or {}) do
        if type(firstLevel) == "table" then
            for _, secondLevel in pairs(firstLevel) do
                if type(secondLevel) == "table" then
                    for _ in pairs(secondLevel) do return false end
                end
            end
        end
    end
    return true
end

local function SearchRouteOpenAccordion(route, pageKey, id)
    if not (route and pageKey and id) then return end
    route.accordion = route.accordion or {}
    route.accordion[tostring(pageKey) .. ":" .. tostring(id)] = true
end

local function SearchRouteSetState(route, field, value)
    if not (route and field) then return end
    route.state = route.state or {}
    route.state[field] = value
end

local function SearchRouteSetTable(route, tableName, key, value)
    if not (route and tableName and key ~= nil) then return end
    route.tables = route.tables or {}
    route.tables[tableName] = route.tables[tableName] or {}
    route.tables[tableName][key] = value
end

local function SearchRouteSetNestedTable(route, tableName, key1, key2, value)
    if not (route and tableName and key1 ~= nil and key2 ~= nil) then return end
    route.nestedTables = route.nestedTables or {}
    route.nestedTables[tableName] = route.nestedTables[tableName] or {}
    route.nestedTables[tableName][key1] = route.nestedTables[tableName][key1] or {}
    route.nestedTables[tableName][key1][key2] = value
end

local function SearchRouteSetGeneral(route, key, value)
    if not (route and key) then return end
    route.general = route.general or {}
    route.general[key] = value
end

local function SearchRouteApplySectionSpecs(route, pageKey, normalized, specs)
    if not (route and pageKey and type(specs) == "table") then return end
    for i = 1, #specs do
        local spec = specs[i]
        if spec and spec.id and SearchRouteHasAny(normalized, spec.terms) then
            SearchRouteOpenAccordion(route, pageKey, spec.id)
        end
    end
end

local function SearchGroupScopeForText(normalized)
    if SearchRouteHasAny(normalized, { "mythic raid", "mythicraid", "mythic" }) then return "mythicraid" end
    if SearchRouteHasAny(normalized, { "raid", "raids" }) then return "raid" end
    if SearchRouteHasAny(normalized, { "party", "group", "groups" }) then return "party" end
    return nil
end

local function SearchGlobalScopeForText(normalized)
    if SearchRouteHasAny(normalized, { "shared scope", "shared style", "global scope", "global style", "baseline" }) then return "shared" end
    if SearchRouteHasAny(normalized, { "raid frame", "raid frames", "raid unit", "raid units", "raid font", "raid fonts", "raid texture", "raid textures", "raid health", "raid text", "raid power", "raid bar", "raid bars" }) then return "gf_raid" end
    if SearchRouteHasAny(normalized, { "party frame", "party frames", "party unit", "party units", "party font", "party fonts", "party texture", "party textures", "party health", "party text", "party power", "party bar", "party bars", "group frame", "group frames", "group font", "group text" }) then return "gf_party" end
    if SearchRouteHasAny(normalized, { "target of target", "targettarget", "target target", "tot frame", "tot font", "tot text", "tot bar" }) then return "targettarget" end
    if SearchRouteHasAny(normalized, { "focus target", "focustarget", "focus target frame", "focus target font", "focus target text", "focus target bar" }) then return "focustarget" end
    if SearchRouteHasAny(normalized, { "player frame", "player unit", "player font", "player text", "player health", "player power", "player bar", "player bars" }) then return "player" end
    if SearchRouteHasAny(normalized, { "target frame", "target unit", "target font", "target text", "target health", "target power", "target bar", "target bars" }) then return "target" end
    if SearchRouteHasAny(normalized, { "focus frame", "focus unit", "focus font", "focus text", "focus health", "focus power", "focus bar", "focus bars" }) then return "focus" end
    if SearchRouteHasAny(normalized, { "pet frame", "pet unit", "pet font", "pet text", "pet health", "pet power", "pet bar", "pet bars" }) then return "pet" end
    if SearchRouteHasAny(normalized, { "boss frame", "boss frames", "boss unit", "boss units", "boss font", "boss text", "boss health", "boss power", "boss bar", "boss bars" }) then return "boss" end
    return nil
end

local function SearchTextKindForText(normalized)
    if SearchRouteHasAny(normalized, { "hp text", "health text", "hp slot", "health slot", "show hp", "percent hp", "hp percent", "left hp", "center hp", "right hp", "hp left", "hp center", "hp right", "left health", "center health", "right health", "health left", "health center", "health right" }) then
        return "hp"
    end
    if SearchRouteHasAny(normalized, { "power text", "power slot", "mana text", "energy text", "rage text", "show power", "left power", "center power", "right power", "power left", "power center", "power right" }) then
        return "power"
    end
    if SearchRouteHasAny(normalized, { "text layer", "draw order", "advanced text", "name layer", "hp layer", "power layer" }) then
        return "advanced"
    end
    if SearchRouteHasAny(normalized, { "name text", "show name", "name position", "name anchor", "raid group name", "left name", "center name", "right name" }) then
        return "name"
    end
    return nil
end

local function SearchTextSlotForText(normalized)
    if SearchRouteHasAny(normalized, { "left slot", "slot left", "left hp", "left health", "left power", "hp left", "health left", "power left" }) then return "left" end
    if SearchRouteHasAny(normalized, { "right slot", "slot right", "right hp", "right health", "right power", "hp right", "health right", "power right" }) then return "right" end
    if SearchRouteHasAny(normalized, { "center slot", "middle slot", "slot center", "slot middle", "center hp", "middle hp", "center health", "center power", "middle power", "hp center", "power center" }) then return "center" end
    return nil
end

local function SearchRouteTextState(route, tabTable, slotTable, scopeKey, normalized)
    local textKind = SearchTextKindForText(normalized)
    if not textKind then return end
    SearchRouteSetTable(route, tabTable, scopeKey, textKind)
    if textKind == "hp" or textKind == "power" then
        local slot = SearchTextSlotForText(normalized)
        if slot then SearchRouteSetNestedTable(route, slotTable, scopeKey, textKind, slot) end
    end
end

local function SearchRouteUnitStatusSelection(route, unit, normalized)
    if SearchRouteHasAny(normalized, { "incoming rez", "incoming res", "incoming resurrect", "incoming resurrection", "ress", "resurrect" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusIncomingRes")
    elseif SearchRouteHasAny(normalized, { "rested", "resting", "rest icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusResting")
    elseif SearchRouteHasAny(normalized, { "combat icon", "combat state", "in combat icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusCombat")
    elseif SearchRouteHasAny(normalized, { "dead text", "dead status", "offline text", "status text" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "statusText")
    elseif SearchRouteHasAny(normalized, { "elite", "rare", "elite icon", "rare icon" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "eliteicon")
    elseif SearchRouteHasAny(normalized, { "raid group", "group number", "subgroup" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "raidgroupname")
    elseif SearchRouteHasAny(normalized, { "level", "level text", "level indicator" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "level")
    elseif SearchRouteHasAny(normalized, { "raid marker", "marker" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "raidmarker")
    elseif SearchRouteHasAny(normalized, { "leader", "assist", "leader assist", "leader / assist" }) then
        SearchRouteSetTable(route, "unitStatusSelection", unit, "leader")
    end
end

local function SearchRouteGroupStatusSelection(route, normalized)
    if SearchRouteHasAny(normalized, { "ready check" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "readyCheckIcon")
    elseif SearchRouteHasAny(normalized, { "summon", "summoning" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "summonIcon")
    elseif SearchRouteHasAny(normalized, { "resurrect", "resurrection", "rez", "ress" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "resurrectIcon")
    elseif SearchRouteHasAny(normalized, { "phase", "phased" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "phaseIcon")
    elseif SearchRouteHasAny(normalized, { "ghost" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusGhostText")
    elseif SearchRouteHasAny(normalized, { "leader" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "leaderIcon")
    elseif SearchRouteHasAny(normalized, { "assist" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "assistIcon")
    elseif SearchRouteHasAny(normalized, { "raid marker", "marker" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "raidMarker")
    elseif SearchRouteHasAny(normalized, { "dead", "offline" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusText")
    elseif SearchRouteHasAny(normalized, { "afk", "dnd" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "statusAFKText")
    elseif SearchRouteHasAny(normalized, { "role icon", "tank", "healer", "dps" }) then
        SearchRouteSetState(route, "gfStatusIconSelection", "roleIcon")
    end
end

local function SearchPowerColorTokenForText(normalized)
    if SearchRouteHasAny(normalized, { "rage" }) then return "RAGE" end
    if SearchRouteHasAny(normalized, { "energy" }) then return "ENERGY" end
    if SearchRouteHasAny(normalized, { "focus power", "hunter focus" }) then return "FOCUS" end
    if SearchRouteHasAny(normalized, { "runic power" }) then return "RUNIC_POWER" end
    if SearchRouteHasAny(normalized, { "insanity" }) then return "INSANITY" end
    if SearchRouteHasAny(normalized, { "fury" }) then return "FURY" end
    if SearchRouteHasAny(normalized, { "pain" }) then return "PAIN" end
    if SearchRouteHasAny(normalized, { "essence" }) then return "ESSENCE" end
    if SearchRouteHasAny(normalized, { "astral power", "lunar power" }) then return "LUNAR_POWER" end
    if SearchRouteHasAny(normalized, { "maelstrom" }) then return "MAELSTROM" end
    if SearchRouteHasAny(normalized, { "mana" }) then return "MANA" end
    return nil
end

local function SearchClassPowerTokenForText(normalized)
    if SearchRouteHasAny(normalized, { "holy power" }) then return "HOLY_POWER" end
    if SearchRouteHasAny(normalized, { "soul shards", "soul shard" }) then return "SOUL_SHARDS" end
    if SearchRouteHasAny(normalized, { "chi" }) then return "CHI" end
    if SearchRouteHasAny(normalized, { "arcane charges", "arcane charge" }) then return "ARCANE_CHARGES" end
    if SearchRouteHasAny(normalized, { "runes" }) then return "RUNES" end
    if SearchRouteHasAny(normalized, { "empowered", "charged" }) then return "CHARGED" end
    if SearchRouteHasAny(normalized, { "soul fragments vengeance", "vengeance fragments" }) then return "SOUL_FRAGMENTS_VENG" end
    if SearchRouteHasAny(normalized, { "soul fragments void", "void meta" }) then return "SOUL_FRAGMENTS_META" end
    if SearchRouteHasAny(normalized, { "soul fragments", "soul fragment" }) then return "SOUL_FRAGMENTS" end
    if SearchRouteHasAny(normalized, { "maelstrom weapon 5" }) then return "MAELSTROM_ABOVE_5" end
    if SearchRouteHasAny(normalized, { "maelstrom weapon" }) then return "MAELSTROM" end
    if SearchRouteHasAny(normalized, { "astral prediction" }) then return "AP_PREDICTION" end
    if SearchRouteHasAny(normalized, { "astral power" }) then return "ASTRAL_POWER" end
    if SearchRouteHasAny(normalized, { "solar eclipse", "eclipse solar" }) then return "ECLIPSE_SOLAR" end
    if SearchRouteHasAny(normalized, { "lunar eclipse", "eclipse lunar" }) then return "ECLIPSE_LUNAR" end
    if SearchRouteHasAny(normalized, { "celestial alignment" }) then return "ECLIPSE_CA" end
    if SearchRouteHasAny(normalized, { "stagger light", "green stagger" }) then return "STAGGER_GREEN" end
    if SearchRouteHasAny(normalized, { "stagger moderate", "yellow stagger" }) then return "STAGGER_YELLOW" end
    if SearchRouteHasAny(normalized, { "stagger heavy", "red stagger" }) then return "STAGGER_RED" end
    if SearchRouteHasAny(normalized, { "insanity" }) then return "INSANITY" end
    if SearchRouteHasAny(normalized, { "maelstrom power" }) then return "MAELSTROM_POWER" end
    if SearchRouteHasAny(normalized, { "whirlwind" }) then return "WHIRLWIND" end
    if SearchRouteHasAny(normalized, { "tip of the spear" }) then return "TIP_OF_THE_SPEAR" end
    if SearchRouteHasAny(normalized, { "icicles" }) then return "ICICLES" end
    if SearchRouteHasAny(normalized, { "ebon might" }) then return "EBON_MIGHT" end
    if SearchRouteHasAny(normalized, { "resource text" }) then return "RESOURCE_TEXT" end
    if SearchRouteHasAny(normalized, { "essence" }) then return "ESSENCE" end
    if SearchRouteHasAny(normalized, { "combo points", "combo point" }) then return "COMBO_POINTS" end
    return nil
end

local SEARCH_UNIT_BY_PAGE = {
    uf_player = "player",
    uf_target = "target",
    uf_targettarget = "targettarget",
    uf_focustarget = "focustarget",
    uf_focus = "focus",
    uf_pet = "pet",
    uf_boss = "boss",
}

local function SearchRouteUnitPage(route, pageKey, normalized)
    local unit = SEARCH_UNIT_BY_PAGE[pageKey]
    if not unit then return end

    SearchRouteApplySectionSpecs(route, pageKey, normalized, {
        { id = "preview", terms = { "preview", "hide preview" } },
        { id = "frame_basics", terms = { "frame basics", "enable", "disable", "width", "height", "scale", "frame size", "smooth fill", "health animation" } },
        { id = "anchoring", terms = { "anchoring", "anchor", "position", "x offset", "y offset", "custom anchor", "global anchor" } },
        { id = "text", terms = { "text", "name text", "hp text", "health text", "power text", "font size", "text anchor", "text position", "draw order", "text layer" } },
        { id = "inline_text", terms = { "inline text", "inline color", "target of target text", "tot text", "tot color", "npc color", "npc type color" } },
        { id = "transparency", terms = { "transparency", "transparent", "alpha", "opacity", "fade", "in combat alpha", "out of combat alpha" } },
        { id = "portrait", terms = { "portrait", "class icon", "2d portrait", "3d portrait", "avatar", "face" } },
        { id = "power_bar", terms = { "power bar", "mana bar", "energy bar", "rage bar", "power height", "power smooth fill" } },
        { id = "castbar", terms = { "castbar", "cast bar", "spell name", "cast icon", "cast time" } },
        { id = "status_icons", terms = { "status icons", "status icon", "indicator", "level", "level text", "raid group", "group number", "raid marker", "leader", "assist", "elite", "rare", "dead", "offline", "combat icon", "rested", "incoming rez", "advanced status", "advanced x offset", "advanced y offset", "extended x offset", "extended y offset" } },
        { id = "load_conditions", terms = { "load conditions", "visibility conditions", "show conditions", "hide conditions", "when to show", "when to hide" } },
        { id = "boss_layout", terms = { "boss layout", "boss preview", "boss frames" } },
    })

    if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
    SearchRouteTextState(route, "unitTextTabSelection", "unitTextSlotSelection", unit, normalized)

    if SearchRouteHasAny(normalized, { "advanced status", "status icon advanced", "advanced x offset", "advanced y offset", "extended x offset", "extended y offset", "wide x offset", "wide y offset" }) then
        SearchRouteSetTable(route, "unitStatusTabSelection", unit, "advanced")
    elseif SearchRouteHasAny(normalized, { "status icons", "status icon", "indicator", "level", "raid group", "group number", "raid marker", "leader", "assist", "elite", "rare", "dead", "offline", "combat icon", "rested", "incoming rez" }) then
        SearchRouteSetTable(route, "unitStatusTabSelection", unit, "basic")
    end
    SearchRouteUnitStatusSelection(route, unit, normalized)
end

local function SearchRouteGroupPage(route, pageKey, normalized)
    local scope = SearchGroupScopeForText(normalized)
    if scope then SearchRouteSetState(route, "gfScope", scope) end

    if pageKey == "gf_layout" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "general", terms = { "general", "enable", "disable", "turn off", "off", "hide group frames", "hide raid frames", "hide party frames", "group frames off", "raid frames off", "party frames off", "use msuf group frames", "show player", "show solo", "solo", "visibility", "party frames not showing", "raid frames not showing", "ausschalten", "deaktivieren", "ausblenden" } },
            { id = "layout", terms = { "layout", "growth", "direction", "spacing", "columns", "rows", "width", "height" } },
            { id = "sorting", terms = { "sorting", "sort", "role order", "player first", "groups first" } },
            { id = "scaling", terms = { "frame scaling", "scale", "smooth health fill", "smooth fill", "party smooth fill", "raid smooth fill" } },
            { id = "border", terms = { "transparency", "alpha", "opacity", "fade" } },
            { id = "anchor", terms = { "anchoring", "anchor", "position", "move party", "move raid", "x offset", "y offset" } },
            { id = "tooltip", terms = { "tooltip", "tooltips", "mouseover tooltip" } },
        })
    elseif pageKey == "gf_bars" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "hcolor", terms = { "health colors", "health color", "class color", "hp color" } },
            { id = "bars", terms = { "bars custom", "health bar", "bar texture", "bar height" } },
            { id = "power", terms = { "power bar", "mana bar", "power text", "smooth fill" } },
            { id = "text", terms = { "text", "name text", "health text", "hp text", "power text", "font size" } },
            { id = "dispel", terms = { "dispel overlay", "overlay style", "overlay detects", "overlay priority", "health bar tint" } },
            { id = "dstripe", terms = { "debuff stripe", "stripe edge", "stripe height", "stripe opacity" } },
            { id = "range", terms = { "range fade", "range check", "distance check", "out of range" } },
        })
        if SearchTextKindForText(normalized) then SearchRouteOpenAccordion(route, pageKey, "text") end
        SearchRouteTextState(route, "gfTextTabSelection", "gfTextSlotSelection", scope or M.gfScope or "party", normalized)
    elseif pageKey == "gf_auras" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "blizzrenderer", terms = { "aura display mode", "blizzard dispels", "blizzard mode", "msuf dispel border glow", "native dispel icons" } },
            { id = "buffs", terms = { "buffs", "buff", "hots", "own buffs", "healer buffs" } },
            { id = "debuffs", terms = { "debuffs", "debuff", "boss debuff", "raid debuff", "magic", "curse", "poison", "disease" } },
            { id = "ext", terms = { "externals", "defensives", "external cooldowns" } },
            { id = "textcolor", terms = { "text coloring", "timer color", "cooldown text", "stack text", "pandemic" } },
            { id = "priv", terms = { "private auras", "private aura" } },
            { id = "masque", terms = { "cooldown style", "masque", "cooldown swipe" } },
            { id = "autil", terms = { "aura utilities", "custom aura", "custom buff", "custom debuff", "spell id" } },
        })
    elseif pageKey == "gf_indicators" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "indicators", terms = { "indicators", "spell indicators", "placed indicators", "focus glow", "frame effects" } },
            { id = "sicons", terms = { "status icons", "status icon", "dead icon", "ghost text", "offline icon", "afk", "dnd", "ready check", "summon", "resurrect", "phase", "leader icon", "assist icon", "role icon", "raid marker", "advanced status", "advanced x offset", "advanced y offset", "advanced placement", "extended x offset", "extended y offset" } },
            { id = "si", terms = { "spell indicators", "custom spell", "spell id", "indicator spell", "healer hots indicators" } },
            { id = "ci", terms = { "corner indicators", "corner dots", "corner indicator", "custom spell editor", "slot assignments" } },
        })
        local tabScope = scope or M.gfScope or "party"
        if SearchRouteHasAny(normalized, { "advanced status", "status icon advanced", "advanced x offset", "advanced y offset", "advanced placement", "extended x offset", "extended y offset", "draw order" }) then
            SearchRouteSetTable(route, "gfStatusIconTabSelection", tabScope, "advanced")
        elseif SearchRouteHasAny(normalized, { "status icons", "status icon", "ready check", "summon", "resurrect", "phase", "dead", "ghost", "offline", "afk", "dnd", "leader icon", "assist icon", "role icon", "raid marker" }) then
            SearchRouteSetTable(route, "gfStatusIconTabSelection", tabScope, "basic")
        end
        SearchRouteGroupStatusSelection(route, normalized)
        if SearchRouteHasAny(normalized, { "top left", "tl" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "TL")
        elseif SearchRouteHasAny(normalized, { "top right", "tr" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "TR")
        elseif SearchRouteHasAny(normalized, { "bottom left", "bl" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "BL")
        elseif SearchRouteHasAny(normalized, { "bottom right", "br" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "BR")
        elseif SearchRouteHasAny(normalized, { "center", "middle" }) then
            SearchRouteSetState(route, "gfCornerSlotSelection", "C")
        end
    end
end

local function SearchRouteGlobalPage(route, pageKey, normalized)
    if pageKey == "profiles" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "profiles_management", terms = { "profile management", "active profile", "rename", "copy profile", "reset profile" } },
            { id = "profiles_specs", terms = { "spec profiles", "specialization", "auto switch" } },
            { id = "profiles_io", terms = { "export", "import", "wago", "legacy import", "profile string", "backup", "share profile" } },
        })
        if SearchRouteHasAny(normalized, { "export unitframe", "export unitframes", "unitframe export", "unitframes export" }) then
            SearchRouteSetState(route, "profileExportKind", "unitframe")
        elseif SearchRouteHasAny(normalized, { "export castbar", "export castbars", "castbar export", "castbars export" }) then
            SearchRouteSetState(route, "profileExportKind", "castbar")
        elseif SearchRouteHasAny(normalized, { "export colors", "export colours", "colors export", "colours export" }) then
            SearchRouteSetState(route, "profileExportKind", "colors")
        elseif SearchRouteHasAny(normalized, { "export gameplay", "gameplay export" }) then
            SearchRouteSetState(route, "profileExportKind", "gameplay")
        elseif SearchRouteHasAny(normalized, { "export group", "export group frames", "group frames export", "groupframe export" }) then
            SearchRouteSetState(route, "profileExportKind", "groupframe")
        elseif SearchRouteHasAny(normalized, { "full profile", "export full", "full export", "complete profile" }) then
            SearchRouteSetState(route, "profileExportKind", "all")
        end
        if SearchRouteHasAny(normalized, { "import create new", "import new profile", "create new profile", "import and create new profile" }) then
            SearchRouteSetState(route, "profileImportCreateNew", true)
        elseif SearchRouteHasAny(normalized, { "import current profile", "import to current", "current profile import" }) then
            SearchRouteSetState(route, "profileImportCreateNew", false)
        end
    elseif pageKey == "modules" then
        SearchRouteOpenAccordion(route, pageKey, "modules_style")
    elseif pageKey == "opt_bars" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "hpPowerTextSelectedKey", scope) end
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "bars_textures", terms = { "textures", "texture", "gradient", "bar texture", "background texture" } },
            { id = "bars_absorb", terms = { "absorb", "heal prediction", "incoming heals", "shield" } },
            { id = "bars_outline", terms = { "frame outline", "outline", "bar outline", "border thickness" } },
            { id = "bars_rounded", terms = { "rounded", "round corners", "rounded texture", "rounded frames" } },
            { id = "bars_highlight", terms = { "highlight borders", "highlight border", "dispel border", "dispel glow", "aggro border", "purge border", "boss target border", "priority order" } },
            { id = "bars_unit_dispel_overlay", terms = { "unitframe dispel overlay", "unit frame dispel overlay", "overlay detects", "overlay priority", "unit dispel overlay" } },
            { id = "bars_power", terms = { "bar animation", "text accuracy", "smooth fill", "power animation" } },
        })
    elseif pageKey == "opt_fonts" then
        local scope = SearchGlobalScopeForText(normalized)
        if scope then SearchRouteSetGeneral(route, "_fontScopeKey", scope) end
        if not scope and SearchRouteHasAny(normalized, {
            "font", "fonts", "global font", "font family", "font dropdown", "sharedmedia",
            "change font", "change fonts", "where to change font", "where change font",
            "schriftart", "schriftart aendern", "schrift aendern",
        }) then
            SearchRouteSetGeneral(route, "_fontScopeKey", "shared")
        end
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "fonts_global_font", terms = { "global font", "font family", "font", "font dropdown", "sharedmedia", "change font", "change fonts", "where to change font", "where change font" } },
            { id = "fonts_text_style", terms = { "text style", "outline", "shadow", "font size" } },
            { id = "fonts_name_power_colors", terms = { "name colors", "power colors", "name color", "power color" } },
            { id = "fonts_name_shortening", terms = { "name shortening", "short names", "realm names", "truncate", "names too long" } },
        })
    elseif pageKey == "opt_castbar" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "castbar_behavior", terms = { "shake", "fill direction", "castbar direction", "castbar behavior" } },
            { id = "castbar_gcd", terms = { "gcd", "global cooldown", "gcd bar", "instant casts" } },
            { id = "castbar_textures", terms = { "textures", "texture", "outline", "castbar texture" } },
            { id = "castbar_empowered", terms = { "empowered casts", "evoker", "empower", "stage blink", "hold cast", "release cast" } },
            { id = "castbar_name_shortening", terms = { "name shortening", "spell name", "cast name", "max name length" } },
            { id = "castbar_focus_kick", terms = { "focus kick", "target kick", "interrupt focus", "kick cooldown" } },
            { id = "castbar_interrupt_ready", terms = { "interrupt ready", "demon hunter", "devour", "consume magic", "disrupt", "kick ready" } },
        })
    elseif pageKey == "opt_misc" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "misc_language", terms = { "language", "locale", "translation", "localization", "localisation" } },
            { id = "misc_menu_behavior", terms = { "menu behavior", "menu snap", "edge snap", "window snap", "menu resize" } },
            { id = "misc_updates", terms = { "update intervals", "performance", "lag", "fps", "cooldown text performance" } },
            { id = "misc_tooltips", terms = { "tooltips", "tooltip", "unitframe tooltips", "mouseover tooltip" } },
            { id = "misc_blizzard_frames", terms = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" } },
            { id = "misc_range_fade", terms = { "range fade", "range check", "distance check", "out of range" } },
        })
    elseif pageKey == "classpower" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "classpower_display", terms = { "layout", "display", "combo points", "holy power", "soul shards", "chi", "essence", "runes" } },
            { id = "classpower_behavior", terms = { "behavior", "prediction", "quick actions" } },
            { id = "classpower_visuals", terms = { "style", "visual", "texture", "spacing", "colors" } },
            { id = "classpower_visibility", terms = { "auto hide", "visibility", "hide empty" } },
            { id = "classpower_detached_power", terms = { "detached power", "detached power bar", "alternate power", "dual resource" } },
            { id = "classpower_alt_mana", terms = { "alternative mana", "alt mana", "mana bar" } },
        })
    elseif pageKey == "auras2" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "a2_display", terms = { "display", "click through", "click-through", "buffs", "debuffs", "show buffs", "show debuffs" } },
            { id = "a2_layout", terms = { "caps", "icons", "max buffs", "max debuffs", "icon size", "rows", "spacing", "anchor" } },
            { id = "a2_text_coloring", terms = { "text coloring", "cooldown text", "timer color", "stack text", "pandemic" } },
            { id = "a2_private", terms = { "private auras", "private aura" } },
            { id = "a2_filters", terms = { "aura filters", "filter", "sorting", "dispellable", "only mine", "own buffs", "own debuffs" } },
            { id = "a2_ignore", terms = { "ignore list", "global ignore", "blacklist" } },
            { id = "a2_reminders", terms = { "buff reminders", "reminders", "missing buff" } },
        })
        if SearchRouteHasAny(normalized, { "player" }) then
            SearchRouteSetState(route, "auraScope", "player")
        elseif SearchRouteHasAny(normalized, { "target" }) then
            SearchRouteSetState(route, "auraScope", "target")
        elseif SearchRouteHasAny(normalized, { "focus" }) then
            SearchRouteSetState(route, "auraScope", "focus")
        elseif SearchRouteHasAny(normalized, { "boss" }) then
            SearchRouteSetState(route, "auraScope", "boss")
        elseif SearchRouteHasAny(normalized, { "shared", "global" }) then
            SearchRouteSetState(route, "auraScope", "shared")
        end
    elseif pageKey == "opt_colors" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "colors_font", terms = { "global font color", "font color" } },
            { id = "colors_classes", terms = { "class bar colors", "class color", "class colored" } },
            { id = "colors_background", terms = { "bar background tint", "background color", "backdrop", "missing health", "dark mode", "preserve hp color" } },
            { id = "colors_appearance", terms = { "unitframe global coloring", "appearance", "dark mode" } },
            { id = "colors_unit", terms = { "unitframe colors", "unit frame colors", "reaction color" } },
            { id = "colors_npc_type", terms = { "npc type colors", "npc color" } },
            { id = "colors_bar_colors", terms = { "bar colors", "health color", "hp color" } },
            { id = "colors_dispel", terms = { "dispel", "magic color", "curse color", "poison color", "disease color" } },
            { id = "colors_castbar", terms = { "castbar colors", "castbar color", "spell color" } },
            { id = "colors_highlight", terms = { "mouseover highlight", "hover highlight" } },
            { id = "colors_gameplay", terms = { "gameplay", "crosshair", "target sound" } },
            { id = "colors_power", terms = { "power bar colors", "power bar color", "mana color", "rage color", "energy color", "focus power", "runic power", "insanity color", "fury color", "pain color", "essence color", "astral power", "lunar power", "maelstrom color" } },
            { id = "colors_class_power", terms = { "class power colors", "combo point color", "holy power color", "soul shard", "chi color", "arcane charges", "runes color", "essence color", "soul fragments", "maelstrom weapon", "astral power", "eclipse", "stagger", "icicles", "ebon might" } },
            { id = "colors_auras", terms = { "auras", "buff color", "debuff color" } },
            { id = "colors_portrait", terms = { "portrait colors", "portrait color" } },
        })
        local powerToken = SearchPowerColorTokenForText(normalized)
        if powerToken then SearchRouteSetState(route, "colorsPowerToken", powerToken) end
        local classPowerToken = SearchClassPowerTokenForText(normalized)
        if classPowerToken then SearchRouteSetState(route, "colorsCPToken", classPowerToken) end
        if powerToken or (SearchRouteHasAny(normalized, { "power color", "power colors" }) and not classPowerToken) then
            SearchRouteOpenAccordion(route, pageKey, "colors_power")
        end
        if classPowerToken then SearchRouteOpenAccordion(route, pageKey, "colors_class_power") end
    elseif pageKey == "gameplay" then
        SearchRouteApplySectionSpecs(route, pageKey, normalized, {
            { id = "gameplay_timer", terms = { "combat timer", "timer" } },
            { id = "gameplay_state", terms = { "combat enter", "combat leave", "enter combat", "leave combat" } },
            { id = "gameplay_class_specific", terms = { "class-specific", "class specific", "demon hunter", "interrupt", "devour" } },
            { id = "gameplay_crosshair", terms = { "combat crosshair", "crosshair", "targeting", "mouse" } },
        })
    end
end

local function SearchRouteForTarget(pageKey, query, fallback)
    local normalized = NormalizeSearchText((query or "") .. " " .. (fallback or ""))
    if normalized == "" then return nil end

    if pageKey == "home" then
        if SearchRouteHasAny(normalized, {
            "discord", "factory reset", "fullreset", "print help", "display recovery", "recovery tools",
            "recover menu", "reset all", "help reset", "copy discord", "support discord",
        }) then
            return DASHBOARD_ROUTE_RECOVERY
        end
        if SearchRouteHasAny(normalized, {
            "scaling", "ui scale", "menu scale", "msuf frame scale", "msuf menu scale",
            "make menu bigger", "make menu smaller", "options too big", "options too small",
            "resize window", "groesser", "kleiner", "skalierung",
        }) then
            return DASHBOARD_ROUTE_SCALING
        end
        if SearchRouteHasAny(normalized, {
            "changelog", "change log", "release notes", "patch notes", "version notes",
            "what changed", "latest changes", "aenderungen", "anderungen",
        }) then
            return DASHBOARD_ROUTE_CHANGELOG
        end
        return nil
    end

    local route = SearchNewRoute()
    SearchRouteUnitPage(route, pageKey, normalized)
    SearchRouteGroupPage(route, pageKey, normalized)
    SearchRouteGlobalPage(route, pageKey, normalized)
    return SearchRouteIsEmpty(route) and nil or route
end

local function ApplySearchRoute(pageKey, route)
    if type(route) ~= "table" then return false end

    local changed = false
    if type(M.EnsurePersistentMenuState) == "function" then M.EnsurePersistentMenuState() end
    local state = route.state
    if type(state) == "table" then
        for field, value in pairs(state) do
            if M[field] ~= value then
                if type(M.PersistMenuStateValue) == "function" then
                    M.PersistMenuStateValue(field, value)
                else
                    M[field] = value
                end
                changed = true
            end
        end
    end
    local accordion = route.accordion
    if type(accordion) == "table" then
        local target
        if type(M.GetPersistentMenuStateTable) == "function" then
            target = M.GetPersistentMenuStateTable("accordionState")
        end
        if type(target) ~= "table" then
            M.accordionState = M.accordionState or {}
            target = M.accordionState
        end
        for key, value in pairs(accordion) do
            local open = value and true or false
            if target[key] ~= open then
                target[key] = open
                changed = true
            end
        end
    end
    local tables = route.tables
    if type(tables) == "table" then
        for tableName, values in pairs(tables) do
            if type(tableName) == "string" and type(values) == "table" then
                local target = M[tableName]
                if type(target) ~= "table" then
                    target = {}
                    M[tableName] = target
                end
                for key, value in pairs(values) do
                    if target[key] ~= value then
                        target[key] = value
                        changed = true
                    end
                end
            end
        end
    end
    local nestedTables = route.nestedTables
    if type(nestedTables) == "table" then
        for tableName, firstLevel in pairs(nestedTables) do
            if type(tableName) == "string" and type(firstLevel) == "table" then
                local target = M[tableName]
                if type(target) ~= "table" then
                    target = {}
                    M[tableName] = target
                end
                for key1, secondLevel in pairs(firstLevel) do
                    if type(secondLevel) == "table" then
                        local nested = target[key1]
                        if type(nested) ~= "table" then
                            nested = {}
                            target[key1] = nested
                            changed = true
                        end
                        for key2, value in pairs(secondLevel) do
                            if nested[key2] ~= value then
                                nested[key2] = value
                                changed = true
                            end
                        end
                    end
                end
            end
        end
    end
    local general = route.general
    if type(general) == "table" then
        local db
        if type(M.GetGeneralDB) == "function" then
            db = M.GetGeneralDB()
        elseif type(M.EnsureDB) == "function" then
            local root = M.EnsureDB()
            if type(root) == "table" then
                root.general = type(root.general) == "table" and root.general or {}
                db = root.general
            end
        end
        if type(db) ~= "table" then
            _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
            _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
            db = _G.MSUF_DB.general
        end
        for key, value in pairs(general) do
            if db[key] ~= value then
                db[key] = value
                changed = true
            end
        end
    end
    if changed and pageKey and type(M.InvalidatePage) == "function" then
        M.InvalidatePage(pageKey)
    end
    return changed
end

local function ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if M.activeKey ~= pageKey then return end
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return end

    local region = FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if not region then return end
    local opened = OpenAnchorCollapsibles(region)
    local function finish()
        local offset = SearchAnchorOffset(wrapper, region)
        if offset and M.scrollFrame and M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(offset)
        end
        HighlightSearchAnchor(wrapper, region)
    end
    if opened then RunSoon(finish) else finish() end
end

local function OpenSearchTarget(pageKey, query, fallback, preferredAnchor, route)
    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
    route = route or SearchRouteForTarget(pageKey, query, fallback)
    local routeChanged = ApplySearchRoute(pageKey, route)
    if routeChanged then preferredAnchor = nil end
    M.SelectPage(pageKey)
    RunSoon(function() ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor) end)
end

local function SearchResultHasDetail(rec)
    if not rec then return false end
    if rec.kind == "faq" or rec.kind == "easteregg" then return rec.answer ~= nil and rec.answer ~= "" end
    return rec.answer ~= nil and rec.answer ~= ""
end

local function BuildSearchPage(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local combatLocked = SearchCombatLocked() and true or false
    local queryReady = not combatLocked and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = combatLocked and {} or SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end

    local b = W.PageBuilder(ctx)
    b:Header("Search", query ~= "" and M.Format("Results for \"%s\"", query) or "Type in the search box on the left.", 78)

    local maxVisible = SEARCH_VISIBLE_RESULTS
    local visible = math.min(#results, maxVisible)
    local hasExpandedResult = false
    for i = 1, visible do
        if SearchResultHasDetail(results[i]) then
            hasExpandedResult = true
            break
        end
    end
    local columns = (hasExpandedResult and 1) or (width >= 760 and 2 or 1)
    local gap = 12
    local colW = math.floor((width - 24 - gap * (columns - 1)) / columns)
    local rowH = hasExpandedResult and 62 or 30
    local resultTopY = SEARCH_STATE.indexing and -88 or -70
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * rowH + (SEARCH_STATE.indexing and 18 or 0))
    local sec = b:Section("Search Results", sectionH)

    if combatLocked then
        W.Text(sec, "Search is paused in combat.", 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "MSUF2 does not build or refresh the search index during combat.", 14, -70, width - 28, T.colors.dim)
    elseif query == "" then
        W.Text(sec, "Start typing to search every MSUF2 menu page.", 14, -44, width - 28, T.colors.muted)
    elseif not queryReady then
        W.Text(sec, M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), 14, -44, width - 28, T.colors.muted)
    elseif M.searchResultsPending then
        W.Text(sec, M.Format("Searching for \"%s\"...", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "Results update after you stop typing for a moment.", 14, -70, width - 28, T.colors.dim)
    elseif #results == 0 then
        W.Text(sec, M.Format("No results for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, SEARCH_STATE.indexing and "Still indexing menu pages..." or "Try a page name like bars, profiles, auras, castbar, colors, group, or target.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("Best %d match(es). Press Enter to open the first match.", visible), 14, -44, width - 28, T.colors.muted)
        if SEARCH_STATE.indexing then
            W.Text(sec, "Indexing more menu pages in the background.", 14, -62, width - 28, T.colors.dim)
        end
        for i = 1, visible do
            local rec = results[i]
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            local x = 14 + col * (colW + gap)
            local y = resultTopY - row * rowH
            local kind = CONTROL_KIND_LABEL[rec.kind or ""] or (rec.kind == "page" and "Page") or nil
            if kind and type(M.Tr) == "function" then kind = M.Tr(kind) end
            local prefix = rec.hint ~= "" and rec.hint or rec.group
            local text = prefix ~= "" and (ShortLabel(prefix, 42) .. " > " .. ShortLabel(rec.label, 38)) or rec.label
            if kind and rec.kind ~= "text" then text = text .. " [" .. kind .. "]" end
            local btn = T.Button(sec, text, colW, 22)
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            local pageKey = rec.key
            local fallback = rec.anchorFallback or rec.label or rec.title
            local anchor = rec.anchor
            local route = rec.route
            local noOpen = rec.noOpen
            btn:SetScript("OnClick", function()
                if noOpen then
                    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
                    return
                end
                OpenSearchTarget(pageKey, query, fallback, anchor, route)
            end)
            if SearchResultHasDetail(rec) then
                local answer = (type(M.Tr) == "function" and M.Tr(rec.answer)) or rec.answer
                W.Text(sec, ShortLabel(answer, 132), x + 8, y - 24, colW - 16, T.colors.dim)
                if rec.target and rec.target ~= "" then
                    local target = (type(M.Tr) == "function" and M.Tr(rec.target)) or rec.target
                    W.Text(sec, ShortLabel(target, 112), x + 8, y - 42, colW - 16, T.colors.muted)
                end
            end
        end
        if #results > maxVisible then
            W.Text(sec, M.Format("Showing the best %d matches. Add one more word to narrow it further.", maxVisible), 14, resultTopY - rows * rowH, width - 28, T.colors.dim)
        end
    end

    local quick = b:Section("Support Search Examples", 206)
    local shortcutDispel = "dispel border glow any debuff"
    local shortcutStripe = "where is debuff stripe"
    local shortcutHighlights = "highlight priority dispel aggro target"
    local shortcuts = {
        { "Move Frames", "where do I move my unitframe" },
        { "Background", "change my backgrond" },
        { "Raid Frames", "move raid frames" },
        { "Text Size", "make text bigger" },
        { "Profiles", "import profile wago" },
        { "Castbar", "evoker castbar" },
        { "Buffs", "show only my buffs" },
        { "Blizzard", "hide blizzard frames" },
        { "Range Check", "unit frame range check" },
        { "Level Text", "where is level text anchor" },
        { "Performance", "why is msuf lagging" },
        { "Minimap", "where is the minimap icon setting" },
        { "Rounded", "rounded frames ausschalten" },
        { "Dispel", shortcutDispel },
        { "Stripe", shortcutStripe },
        { "Highlights", shortcutHighlights },
    }
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local searchQuery = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 14 + col * (buttonW + 14), -38 - row * 28)
        btn:SetScript("OnClick", function()
            if M.nav and M.nav.searchBox then
                M.nav.searchBox._msuf2SearchInternal = true
                M.nav.searchBox:SetText(searchQuery)
                M.nav.searchBox._msuf2SearchInternal = nil
                M.nav.searchBox:ClearFocus()
            end
            OpenSearchResults(searchQuery)
        end)
    end

    ctx:SetContentHeight(math.max(ContentHeight(), math.abs(b.y) + 42))
end


Search.SearchPlaceholderText = SearchPlaceholderText
Search.SearchBoxHasText = SearchBoxHasText
Search.RefreshSearchPlaceholder = RefreshSearchPlaceholder
Search.UpdateSearchPlaceholder = UpdateSearchPlaceholder
Search.MarkIndexDirty = MarkSearchIndexDirty
Search.CancelBackgroundIndex = CancelSearchBackgroundIndex
Search.ClearRegistryPage = ClearSearchRegistryPage
Search.BumpInputSerial = function()
    SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
end
Search.RefreshResultsPage = RefreshSearchResultsPage
Search.ScheduleInputQuery = ScheduleSearchInputQuery
Search.RunInputQuery = RunSearchInputQuery
Search.OpenResults = OpenSearchResults
Search.OpenTarget = OpenSearchTarget
Search.SearchPages = SearchPages
Search.TrimText = TrimText
Search.ShortLabel = ShortLabel

if type(ns.RegisterLocaleCallback) == "function" then
    ns.RegisterLocaleCallback("MSUF2_Menu2_Search", function()
        SEARCH_STATE.localeKey = nil
        ClearSearchLocaleCaches()
        CancelSearchBackgroundIndex()
        MarkSearchIndexDirty()
        if M.activeKey == "search" then RefreshSearchResultsPage() end
    end)
end

M.RegisterPage("search", { title = "Search", build = BuildSearchPage, version = 1 })

