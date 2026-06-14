-- Menu2 search text index: provides normalized labels and help strings for Search/Assistant.
-- Keep entries data-like and side-effect free so lookup remains deterministic.
local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Search = M.Search or {}
M.Search = Search
local SearchData = M.SearchData or {}
local Text = Search.Text or {}
Search.Text = Text

-- Search text utilities and shared search UI context.
-- Normalizes labels, placeholder text, content metrics, and keyword tables for index/render/
-- routing shards. This file should not expand sections or select controls by itself.
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

local SEARCH_KEYWORDS, SEARCH_TEXT_FOLDS, SEARCH_UTF_PUNCTUATION = M.PickDefaults(SearchData, [[KEYWORDS TEXT_FOLDS UTF_PUNCTUATION]])

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
    -- The placeholder is translated through Menu2, but always has an English fallback so the
    -- search box remains useful when locale data loads late.
    local text = M.Tr("Ask MSUF anything...")
    if type(text) ~= "string" or text == "" then text = "Ask MSUF anything..." end
    return text
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
    --- Preserve non-ASCII letters so native localized FAQ keywords can match.
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
    if type(MSUF.GetEffectiveLocale) == "function" then
        local ok, locale = pcall(MSUF.GetEffectiveLocale)
        if ok and type(locale) == "string" and locale ~= "" then return locale end
    end
    if type(MSUF.LOCALE) == "string" and MSUF.LOCALE ~= "" then return MSUF.LOCALE end
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

    if type(MSUF.RegisterLocale) == "function" then
        local L = MSUF.RegisterLocale(SearchEffectiveLocale())
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


Text.ContentMetrics = ContentMetrics
Text.ContentWidth = ContentWidth
Text.ContentHeight = ContentHeight
Text.TrimText = TrimText
Text.ShortLabel = ShortLabel
Text.SearchPlaceholderText = SearchPlaceholderText
Text.SearchBoxHasText = SearchBoxHasText
Text.RefreshSearchPlaceholder = RefreshSearchPlaceholder
Text.UpdateSearchPlaceholder = UpdateSearchPlaceholder
Text.NormalizeSearchText = NormalizeSearchText
Text.DisplaySearchText = DisplaySearchText
Text.IsSearchLocaleKey = IsSearchLocaleKey
Text.SearchEffectiveLocale = SearchEffectiveLocale
Text.SearchLocaleTranslations = SearchLocaleTranslations
Text.SearchDisplayText = SearchDisplayText
Text.AddSearchText = AddSearchText
Text.AddSearchTextVariants = AddSearchTextVariants
Text.AddRawSearchText = AddRawSearchText
Text.SearchTextVariants = SearchTextVariants
Text.ForEachLocaleSearchPattern = ForEachLocaleSearchPattern
Text.AddSearchPatternText = AddSearchPatternText
Text.AddSearchValuePatternText = AddSearchValuePatternText
Text.AddToggleQuestionSearchText = AddToggleQuestionSearchText
Text.AddControlQuestionSearchText = AddControlQuestionSearchText
Text.KEYWORDS = SEARCH_KEYWORDS
Text.KIND_ACTION_KEYWORDS = SEARCH_KIND_ACTION_KEYWORDS
Text.KIND_PATTERNS = SEARCH_KIND_PATTERNS
Text.ClearLocaleCaches = function()
    SEARCH_LOCALE_TEXT_CACHE = {}
end
