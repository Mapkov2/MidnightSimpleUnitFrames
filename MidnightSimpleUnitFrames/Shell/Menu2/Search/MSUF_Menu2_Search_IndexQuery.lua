--- Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua
--- Cold-path search indexing, query scoring, target routing, and navigation.
---
--- Owns: search registry, background index construction, query matching,
--- route resolution, and anchor scrolling. Result UI rendering lives in
--- MSUF_Menu2_Search_Render.lua; public wrappers live in Search_API.lua.
local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets
local Search = M.Search or {}
M.Search = Search
local SearchData = M.SearchData or {}
local NAV_ITEMS = M.navItems or {}

local max = math.max

local SearchText = Search.Text or {}
local ContentWidth, ContentHeight, TrimText, ShortLabel, SearchPlaceholderText, SearchBoxHasText, RefreshSearchPlaceholder, UpdateSearchPlaceholder, NormalizeSearchText, DisplaySearchText, SearchEffectiveLocale, SearchDisplayText, AddSearchText, AddRawSearchText, AddToggleQuestionSearchText, AddControlQuestionSearchText = M.Pick(SearchText, [[ContentWidth ContentHeight TrimText ShortLabel SearchPlaceholderText SearchBoxHasText RefreshSearchPlaceholder UpdateSearchPlaceholder NormalizeSearchText DisplaySearchText SearchEffectiveLocale SearchDisplayText AddSearchText AddRawSearchText AddToggleQuestionSearchText AddControlQuestionSearchText]])
local SEARCH_KEYWORDS = SearchText.KEYWORDS or SearchData.KEYWORDS or {}

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
    if SearchText.ClearLocaleCaches then SearchText.ClearLocaleCaches() end
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

local SEARCH_NOISE_TEXT, SEARCH_STOP_WORDS, SEARCH_QUERY_SOFT_STOP_WORDS, SEARCH_QUERY_ALIASES,
    SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_OVERLAY_KEYWORDS,
    SEARCH_DEBUFF_STRIPE_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS, SEARCH_UNIT_AURA_DISPEL_KEYWORDS,
    SEARCH_DASHBOARD_RECOVERY_KEYWORDS, SEARCH_DASHBOARD_DISCORD_KEYWORDS, SEARCH_DASHBOARD_SUPPORT_KEYWORDS,
    SEARCH_DASHBOARD_WAGO_KEYWORDS, SEARCH_DASHBOARD_SCALING_KEYWORDS, SEARCH_DASHBOARD_CHANGELOG_KEYWORDS,
    CONTROL_KIND_LABEL = M.PickDefaults(SearchData, [[
        NOISE_TEXT STOP_WORDS QUERY_SOFT_STOP_WORDS QUERY_ALIASES
        DISPEL_DEBUFF_KEYWORDS HIGHLIGHT_BORDER_KEYWORDS DISPEL_OVERLAY_KEYWORDS
        DEBUFF_STRIPE_KEYWORDS BLIZZARD_DISPEL_KEYWORDS UNIT_AURA_DISPEL_KEYWORDS
        DASHBOARD_RECOVERY_KEYWORDS DASHBOARD_DISCORD_KEYWORDS DASHBOARD_SUPPORT_KEYWORDS
        DASHBOARD_WAGO_KEYWORDS DASHBOARD_SCALING_KEYWORDS DASHBOARD_CHANGELOG_KEYWORDS
        CONTROL_KIND_LABEL
    ]])

local function SearchIgnoreQueryWord(word)
    return SEARCH_STOP_WORDS[word] or SEARCH_QUERY_SOFT_STOP_WORDS[word]
end

local function SearchKeywordList(...)
    local out = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        if type(list) == "table" then
            for k = 1, #list do out[#out + 1] = list[k] end
        elseif type(list) == "string" and list:find("|", 1, true) then
            for keyword in list:gmatch("[^|]+") do out[#out + 1] = keyword end
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

for _, row in ipairs({
    { "gf_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS },
    { "gf_auras", SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS },
    { "gf_indicators", SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS },
    { "opt_bars", SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_DISPEL_OVERLAY_KEYWORDS },
    { "auras3", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "home", SEARCH_DASHBOARD_RECOVERY_KEYWORDS, SEARCH_DASHBOARD_SUPPORT_KEYWORDS, SEARCH_DASHBOARD_WAGO_KEYWORDS, SEARCH_DASHBOARD_SCALING_KEYWORDS, SEARCH_DASHBOARD_CHANGELOG_KEYWORDS },
}) do
    for i = 2, #row do AppendSearchKeywords(row[1], row[i]) end
end

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

local SEARCH_CANONICAL_PAIRS = {}
local function AddSearchCanonicalPairs(result, firstWords, secondWords)
    for first in tostring(firstWords or ""):gmatch("%S+") do
        local bucket = SEARCH_CANONICAL_PAIRS[first]
        if not bucket then
            bucket = {}
            SEARCH_CANONICAL_PAIRS[first] = bucket
        end
        for second in tostring(secondWords or ""):gmatch("%S+") do
            bucket[second] = result
        end
    end
end

for _, row in ipairs({
    "demonhunter|demon|hunter",
    "deathknight|death|knight",
    "windshear|wind|shear",
    "castbar|cast|bar",
    "healthbar|health|bar",
    "powerbar|power|bar",
    "showbuffs|show|buffs",
    "maxbuffs|max|buffs",
    "customcaps|custom|caps",
    "smoothfill|smooth soft fluid|fill",
    "smoothfill|weiche weichen sanfte fluessige|fuellung",
    "smoothfill|relleno llenado|suave fluido",
    "smoothfill|remplissage|doux fluide",
    "smoothfill|riempimento|fluido morbido",
    "smoothfill|preenchimento|suave fluido",
    "classpower|class|resource resources power",
    "clickcast|click|cast casting",
    "clickthrough|click|through",
    "editmode|edit|mode",
    "loadconditions|load|condition conditions",
    "readycheck|ready|check",
    "raidmarker|raid|marker",
    "groupnumber|group|number",
    "nameshortening|name|shortening",
    "globalcooldown|global|cooldown",
    "fokuskick|focus|kick",
    "interruptready|interrupt|ready",
    "leveltext|level|text",
    "levelindicator|level|indicator",
    "statusindicators|status|indicator indicators",
    "statusicons|status|icon icons",
    "onoff|turn|off",
    "minimapicon|minimap|icon button",
    "kofi|ko|fi",
    "menuscale|menu|scale",
    "uiscale|ui|scale",
    "targetsound|target|sound sounds",
    "unitauras|unit|aura auras",
    "globalstyle|global|style",
    "spellid|spell|id",
    "healthtext|health|text",
    "powertext|power|text",
    "nametext|name|text",
    "classcolor|class|color",
    "rangecheck|range|check checker checking",
    "distancecheck|distance|check checker checking",
    "outofrange|out|range",
    "unitframe|unit|frame frames",
    "playerframe|player|frame",
    "targetframe|target|frame",
    "focusframe|focus|frame",
    "petframe|pet|frame",
    "bossframes|boss|frame frames",
    "partyframes|party|frame frames",
    "raidframes|raid|frame frames",
}) do
    local result, firstWords, secondWords = row:match("^([^|]*)|([^|]*)|(.+)$")
    AddSearchCanonicalPairs(result, firstWords, secondWords)
end

local function SearchCanonicalWords(raw)
    local words = {}
    local i = 1
    while i <= #raw do
        local word = raw[i]
        local nextWord = raw[i + 1]
        local canonical = nextWord and SEARCH_CANONICAL_PAIRS[word] and SEARCH_CANONICAL_PAIRS[word][nextWord]
        if canonical then
            words[#words + 1] = canonical
            i = i + 2
        elseif (word == "ÃÂ¿ÃÂ»ÃÂ°ÃÂ²ÃÂ½ÃÂ¾ÃÂµ" or word == "ÃÂ¿ÃÂ»ÃÂ°ÃÂ²ÃÂ½ÃÂ°Ã‘Â") and (nextWord == "ÃÂ·ÃÂ°ÃÂ¿ÃÂ¾ÃÂ»ÃÂ½ÃÂµÃÂ½ÃÂ¸ÃÂµ" or nextWord == "ÃÂ·ÃÂ°ÃÂ»ÃÂ¸ÃÂ²ÃÂºÃÂ°") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "Ã«Â¶â‚¬Ã«â€œÅ“Ã«Å¸Â¬Ã¬Å¡Â´" and nextWord == "Ã¬Â±â€žÃ¬Å¡Â°ÃªÂ¸Â°") or (word == "Ã«Â§â€°Ã«Å’â‚¬" and nextWord == "Ã¬â€¢Â Ã«â€¹Ë†Ã«Â©â€Ã¬ÂÂ´Ã¬â€¦Ëœ") then
            words[#words + 1] = "smoothfill"
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
    for word in ("missing|gone|invisible|broken|bugged|wrong|offscreen|overlap|overlapping|lag|fps|lockdown"):gmatch("[^|]+") do
        if normalized:find(word, 1, true) then return true end
    end
    if normalized:find("not showing", 1, true) or normalized:find("doesnt show", 1, true) or normalized:find("not working", 1, true) then return true end
    if normalized:find("too big", 1, true) or normalized:find("too small", 1, true) or normalized:find("too many", 1, true) then return true end
    for word in ("move|drag|resize|hide|show|enable|disable|change|reset|import|export"):gmatch("[^|]+") do
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

local SEARCH_CONTROL_QUERY_TERMS = "toggle checkbox switch enable disable enabled disabled show hide dropdown select choose slider adjust increase decrease color colour swatch input field textfield editbox aktivier deaktivier einschalt ausschalt anzeigen ausblenden auswahl auswaehlen dropdown regler schieberegler aument reducir ajustar seleccionar choisir activer desactiver selezionare attivare disattivare ativar desativar ÃÂ²Ã‘â€¹ÃÂ±Ã‘â‚¬ÃÂ°Ã‘â€šÃ‘Å’ ÃÂ²ÃÂºÃÂ»Ã‘Å½Ã‘â€¡ÃÂ¸Ã‘â€šÃ‘Å’ ÃÂ¾Ã‘â€šÃÂºÃÂ»Ã‘Å½Ã‘â€¡ÃÂ¸Ã‘â€šÃ‘Å’ Ã¬â€žÂ¤Ã¬Â â€¢ Ã¬â€žÂ Ã­Æ’Â Ã¬â€šÂ¬Ã¬Å¡Â© Ã«Â¹â€žÃ­â„¢Å“Ã¬â€žÂ± Ã­â„¢Å“Ã¬â€žÂ± Ã¤Â¸â€¹Ã¦â€¹â€° Ã©â‚¬â€°Ã¦â€¹Â© Ã¥â€¢Å¸Ã§â€Â¨ Ã¥ÂÅ“Ã§â€Â¨ Ã©ÂÂ¸Ã¦â€œâ€¡"

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

local SEARCH_GENERIC_LOCATION_QUESTION_TERMS = "where|where is|where are|where do|where can|where to|how do|how to|how can|wo|wo ist|wo sind|wo kann|wo finde|wie|wie kann"

local SEARCH_GENERIC_LOCATION_ACTION_TERMS = "change|changed|changing|configure|customize|customise|edit|find|set|select|choose|adjust|move|resize|enable|disable|show|hide|turn on|turn off|aendern|aendere|andern|einstellen|finden|auswaehlen|verschieben|aktivieren|deaktivieren|anzeigen|ausblenden"

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
    if type(terms) == "string" then
        for term in terms:gmatch("[^|]+") do
            if SearchContainsTerm(normalized, term) then return true end
        end
        return false
    end
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
        widget = widget,
        pageKey = pageKey,
        label = label,
        kind = meta.kind or widget._msuf2ControlKind or "control",
        anchor = meta.anchor or widget._msuf2Title or widget._msuf2Label or widget,
        values = CopyStaticSearchValues(meta.values or widget.values),
        command = meta.command or widget._msuf2CommandAction,
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

local function BuildButtonCommandAction(widget, entry)
    if not (widget and type(entry) == "table" and entry.kind == "button") then return nil end
    local function ReadClickHandler()
        if type(widget.GetScript) ~= "function" then return nil end
        local ok, handler = pcall(widget.GetScript, widget, "OnClick")
        if ok and type(handler) == "function" then return handler end
        return nil
    end
    if not ReadClickHandler() then return nil end
    return {
        kind = "button",
        label = entry.label,
        set = function()
            local handler = ReadClickHandler()
            if not handler then return false end
            if type(widget.IsEnabled) == "function" then
                local ok, enabled = pcall(widget.IsEnabled, widget)
                if ok and enabled == false then return false end
            end
            if type(widget.Click) == "function" then
                widget:Click("LeftButton", true)
            else
                handler(widget, "LeftButton", true)
            end
            return true
        end,
        labelFn = function()
            if widget.GetText then
                local ok, text = pcall(widget.GetText, widget)
                if ok and text and text ~= "" then return text end
            end
            return entry.label or "Button"
        end,
        sourceFn = function(label)
            return tostring(entry.pageKey or "page") .. ":button:" .. tostring(label or entry.label or "button")
        end,
    }
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
        local widget = entry.widget
        local command = entry.command or (widget and widget._msuf2CommandAction) or BuildButtonCommandAction(widget, entry)
        if command then
            rec.command = command
            rec.widget = widget
        end
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

local function SubmitAssistantSearchQuery(query)
    query = TrimText(query)
    if query == "" then return false end
    local A = (MSUF and MSUF.Assistant) or M.Assistant
    if not (A and type(A.SubmitDeferred) == "function") then return false end
    if type(M.SelectPage) == "function" and M.activeKey ~= "home" then
        M.SelectPage("home")
    end
    A.SubmitDeferred(query)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.search")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return true
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
    if SubmitAssistantSearchQuery(query) then return end
    RunSearchInputQuery(query, true)
end

Search._RoutingContext = {
    M = M,
    NormalizeSearchText = NormalizeSearchText,
    BuildSearchQueryClauses = BuildSearchQueryClauses,
    BuildSearchTokenList = BuildSearchTokenList,
    SearchEditDistanceWithin = SearchEditDistanceWithin,
    SearchCombatLocked = SearchCombatLocked,
    ContentWidth = ContentWidth,
    ContentHeight = ContentHeight,
    DASHBOARD_ROUTE_RECOVERY = DASHBOARD_ROUTE_RECOVERY,
    DASHBOARD_ROUTE_SCALING = DASHBOARD_ROUTE_SCALING,
    DASHBOARD_ROUTE_CHANGELOG = DASHBOARD_ROUTE_CHANGELOG,
}

local function OpenSearchTarget(...)
    local routing = Search._RoutingAPI
    if routing and routing.OpenSearchTarget then return routing.OpenSearchTarget(...) end
end

Search._RenderContext = {
    M = M,
    W = W,
    T = T,
    TrimText = TrimText,
    SearchCombatLocked = SearchCombatLocked,
    NormalizeSearchText = NormalizeSearchText,
    MIN_SEARCH_QUERY_LEN = MIN_SEARCH_QUERY_LEN,
    SearchPages = SearchPages,
    SEARCH_STATE = SEARCH_STATE,
    SEARCH_VISIBLE_RESULTS = SEARCH_VISIBLE_RESULTS,
    CONTROL_KIND_LABEL = CONTROL_KIND_LABEL,
    ShortLabel = ShortLabel,
    OpenSearchTarget = OpenSearchTarget,
    OpenSearchResults = OpenSearchResults,
    ContentHeight = ContentHeight,
}

Search._CoreAPI = {
    BumpSearchInputSerial = function()
        SEARCH_STATE.inputSerial = SEARCH_STATE.inputSerial + 1
    end,
    CancelSearchBackgroundIndex = CancelSearchBackgroundIndex,
    ClearSearchLocaleCaches = ClearSearchLocaleCaches,
    ClearSearchRegistryPage = ClearSearchRegistryPage,
    MarkSearchIndexDirty = MarkSearchIndexDirty,
    OpenSearchResults = OpenSearchResults,
    OpenSearchTarget = OpenSearchTarget,
    RefreshSearchResultsPage = RefreshSearchResultsPage,
    RefreshSearchPlaceholder = RefreshSearchPlaceholder,
    RunSearchInputQuery = RunSearchInputQuery,
    ScheduleSearchInputQuery = ScheduleSearchInputQuery,
    SearchBoxHasText = SearchBoxHasText,
    SearchPages = SearchPages,
    SearchPlaceholderText = SearchPlaceholderText,
    ShortLabel = ShortLabel,
    TrimText = TrimText,
    UpdateSearchPlaceholder = UpdateSearchPlaceholder,
}
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF2_Menu2_Search", function()
        SEARCH_STATE.localeKey = nil
        ClearSearchLocaleCaches()
        CancelSearchBackgroundIndex()
        MarkSearchIndexDirty()
        if M.activeKey == "search" then RefreshSearchResultsPage() end
    end)
end
