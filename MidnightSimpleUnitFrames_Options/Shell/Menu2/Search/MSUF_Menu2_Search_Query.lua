-- Search lexicon, query clauses, fuzzy matching and ranking.
local _, MSUF = ...
local Parts = MSUF.SearchIndexParts
local AddSearchText = Parts.AddSearchText
local EMPTY_SEARCH_RECORDS = Parts.EMPTY_SEARCH_RECORDS
local M = Parts.M
local NormalizeSearchText = Parts.NormalizeSearchText
local SEARCH_BLIZZARD_DISPEL_KEYWORDS = Parts.SEARCH_BLIZZARD_DISPEL_KEYWORDS
local SEARCH_DASHBOARD_CHANGELOG_KEYWORDS = Parts.SEARCH_DASHBOARD_CHANGELOG_KEYWORDS
local SEARCH_DASHBOARD_RECOVERY_KEYWORDS = Parts.SEARCH_DASHBOARD_RECOVERY_KEYWORDS
local SEARCH_DASHBOARD_SCALING_KEYWORDS = Parts.SEARCH_DASHBOARD_SCALING_KEYWORDS
local SEARCH_DASHBOARD_SUPPORT_KEYWORDS = Parts.SEARCH_DASHBOARD_SUPPORT_KEYWORDS
local SEARCH_DASHBOARD_WAGO_KEYWORDS = Parts.SEARCH_DASHBOARD_WAGO_KEYWORDS
local SEARCH_DEBUFF_STRIPE_KEYWORDS = Parts.SEARCH_DEBUFF_STRIPE_KEYWORDS
local SEARCH_DISPEL_DEBUFF_KEYWORDS = Parts.SEARCH_DISPEL_DEBUFF_KEYWORDS
local SEARCH_DISPEL_OVERLAY_KEYWORDS = Parts.SEARCH_DISPEL_OVERLAY_KEYWORDS
local SEARCH_HIGHLIGHT_BORDER_KEYWORDS = Parts.SEARCH_HIGHLIGHT_BORDER_KEYWORDS
local SEARCH_MAX_QUERY_CLAUSES = Parts.SEARCH_MAX_QUERY_CLAUSES
local SEARCH_MAX_RAW_WORDS = Parts.SEARCH_MAX_RAW_WORDS
local SEARCH_MAX_RECORD_TOKENS = Parts.SEARCH_MAX_RECORD_TOKENS
local SEARCH_MAX_TERMS_PER_CLAUSE = Parts.SEARCH_MAX_TERMS_PER_CLAUSE
local SEARCH_QUERY_ALIASES = Parts.SEARCH_QUERY_ALIASES
local SEARCH_QUERY_SOFT_STOP_WORDS = Parts.SEARCH_QUERY_SOFT_STOP_WORDS
local SEARCH_STATE = Parts.SEARCH_STATE
local SEARCH_STOP_WORDS = Parts.SEARCH_STOP_WORDS
local SEARCH_UNIT_AURA_DISPEL_KEYWORDS = Parts.SEARCH_UNIT_AURA_DISPEL_KEYWORDS
local SearchData = Parts.SearchData
local SearchText = Parts.SearchText
local byte = Parts.byte
-- Locale dictionaries use natural spellings. Fold their keys exactly like
-- input so accents/case never turn grammar into an unmatched required clause.
-- Built on the first visible, out-of-combat query, and again after a source
-- dictionary gains a key (a companion addon may add words after that query)
-- or M.InvalidateSearchLexicon() (for words added to an existing key). The
-- SearchData source tables stay intact.
local LEXICON_SOURCES = { stop = SEARCH_STOP_WORDS, soft = SEARCH_QUERY_SOFT_STOP_WORDS, aliases = SEARCH_QUERY_ALIASES }
local searchLexiconReady = false
local compactQueryKeys
function M.InvalidateSearchLexicon()
    searchLexiconReady, LEXICON_SOURCES.job = false, nil
    SEARCH_STATE.recordsReady = false
    SEARCH_STATE.dirtySerial = SEARCH_STATE.dirtySerial + 1
end
LEXICON_SOURCES.watch = { __newindex = function(dictionary, key, value)
    rawset(dictionary, key, value)
    M.InvalidateSearchLexicon()
end }
if getmetatable(LEXICON_SOURCES.stop) == nil then setmetatable(LEXICON_SOURCES.stop, LEXICON_SOURCES.watch) end
if getmetatable(LEXICON_SOURCES.soft) == nil then setmetatable(LEXICON_SOURCES.soft, LEXICON_SOURCES.watch) end
local aliasMeta = getmetatable(LEXICON_SOURCES.aliases)
local writeAlias = aliasMeta.__newindex
aliasMeta.__newindex = function(dictionary, key, value)
    writeAlias(dictionary, key, value)
    M.InvalidateSearchLexicon()
end
local function EnsureSearchLexicon(deadline)
    if searchLexiconReady then return true end
    if not SearchData.EnsureQueryAliases(deadline) then return false end
    local job = LEXICON_SOURCES.job
    if not job then
        job = { phase = 1, stop = {}, soft = {}, keys = {}, aliases = {}, seen = {}, multiWord = {} }
        LEXICON_SOURCES.job = job
    end
    local function Due() return deadline and debugprofilestop() >= deadline end
    local function FoldFlags(source, result)
        local key, value = next(source, job.key)
        while key ~= nil do
            local folded = NormalizeSearchText(key)
            if folded ~= "" then result[folded] = value end
            job.key = key
            if Due() then return false end
            key, value = next(source, key)
        end
        job.key = nil
        return true
    end
    if job.phase == 1 then
        if not FoldFlags(LEXICON_SOURCES.stop, job.stop) then return false end
        job.phase = 2
    end
    if job.phase == 2 then
        if not FoldFlags(LEXICON_SOURCES.soft, job.soft) then return false end
        for key in pairs(LEXICON_SOURCES.aliases) do job.keys[#job.keys + 1] = key end
        table.sort(job.keys)
        job.phase, job.index = 3, 1
    end
    if job.phase == 3 then
        for i = job.index, #job.keys do
            local key = job.keys[i]
            local folded = NormalizeSearchText(key)
            if folded ~= "" then
                local terms = job.aliases[folded]
                if not terms then terms = {} job.aliases[folded], job.seen[folded] = terms, {} end
                local seen = job.seen[folded]
                for _, term in ipairs(LEXICON_SOURCES.aliases[key]) do
                    term = NormalizeSearchText(term)
                    if term ~= "" and not seen[term] then terms[#terms + 1], seen[term] = term, true end
                end
            end
            if Due() then job.index = i + 1 return false end
        end
        job.phase = 4
    end
    if job.phase == 4 then
        local folded = next(job.aliases, job.key)
        while folded ~= nil do
            if folded:find(" ", 1, true) then
                local words = {}
                for word in folded:gmatch("%S+") do words[#words + 1] = word end
                local bucket = job.multiWord[words[1]] or {}
                job.multiWord[words[1]] = bucket
                bucket[#bucket + 1] = { key = folded, words = words }
            end
            job.key = folded
            if Due() then return false end
            folded = next(job.aliases, folded)
        end
    end
    for _, bucket in pairs(job.multiWord) do
        table.sort(bucket, function(a, b) return #a.words == #b.words and a.key < b.key or #a.words > #b.words end)
    end
    SEARCH_STOP_WORDS, SEARCH_QUERY_SOFT_STOP_WORDS, SEARCH_QUERY_ALIASES = job.stop, job.soft, job.aliases
    SEARCH_STATE.multiWordAliases = job.multiWord
    local compounds = {}
    for source, expanded in pairs(SearchData.QUERY_COMPOUNDS or EMPTY_SEARCH_RECORDS) do
        source, expanded = NormalizeSearchText(source), NormalizeSearchText(expanded)
        if source ~= "" and source ~= expanded then compounds[#compounds + 1] = { source, expanded } end
    end
    table.sort(compounds, function(a, b) return #a[1] == #b[1] and a[1] < b[1] or #a[1] > #b[1] end)
    SEARCH_STATE.queryCompounds = compounds
    compactQueryKeys = nil
    SEARCH_STATE.aliasTypoKeys, SEARCH_STATE.aliasTypoKeyLengths = nil, nil
    SEARCH_STATE.aliasTypoCache, SEARCH_STATE.aliasTypoCount = {}, 0
    SEARCH_STATE.queryClauseCacheNorm, SEARCH_STATE.queryClauseCacheClauses = nil, nil
    SEARCH_STATE.lexiconGeneration = (SEARCH_STATE.lexiconGeneration or 0) + 1
    searchLexiconReady, LEXICON_SOURCES.job = true, nil
    return true
end

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

-- Loops at chunk level would hold their control variables as chunk locals
-- (the chunk has a local budget), so each table fill runs in a function.
local function AppendPageKeywordRows(rows)
    for _, row in ipairs(rows) do
        for i = 2, #row do AppendSearchKeywords(row[1], row[i]) end
    end
end
AppendPageKeywordRows({
    { "gf_bars", SEARCH_DISPEL_OVERLAY_KEYWORDS, SEARCH_DEBUFF_STRIPE_KEYWORDS },
    { "gf_auras", SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_BLIZZARD_DISPEL_KEYWORDS },
    { "gf_indicators", SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_HIGHLIGHT_BORDER_KEYWORDS },
    { "opt_bars", SEARCH_HIGHLIGHT_BORDER_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS, SEARCH_DISPEL_OVERLAY_KEYWORDS },
    { "uf_player", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "uf_target", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "uf_focus", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "uf_boss", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "uf_arena", SEARCH_UNIT_AURA_DISPEL_KEYWORDS, SEARCH_DISPEL_DEBUFF_KEYWORDS },
    { "home", SEARCH_DASHBOARD_RECOVERY_KEYWORDS, SEARCH_DASHBOARD_SUPPORT_KEYWORDS, SEARCH_DASHBOARD_WAGO_KEYWORDS, SEARCH_DASHBOARD_SCALING_KEYWORDS },
    { "changelog", SEARCH_DASHBOARD_CHANGELOG_KEYWORDS },
})

local DASHBOARD_ROUTE_RECOVERY = { state = { dashboardRecoveryOpen = true } }
local DASHBOARD_ROUTE_SCALING = { state = { dashboardScalingOpen = true } }
local DASHBOARD_ROUTE_CHANGELOG = { state = { dashboardChangelogOpen = true } }

--- allowSoftStop keeps words like "enable"/"visible"/"off" usable as search terms.
--- They are normally dropped because they are filler in a sentence, but they are
--- also real control labels, and a query made only of them must not collapse.
--- "all" keeps the hard stop words too, for labels made only of them ("To", "Aus").
local function AddSearchTermUnique(list, seen, term, allowSoftStop)
    if #list >= SEARCH_MAX_TERMS_PER_CLAUSE then return end
    term = NormalizeSearchText(term)
    if term == "" or seen[term] then return end
    if allowSoftStop then
        if allowSoftStop ~= "all" and SEARCH_STOP_WORDS[term] then return end
    elseif SearchIgnoreQueryWord(term) then
        return
    end
    seen[term] = true
    list[#list + 1] = term
end

-- Compact CJK text has no whitespace. Use the finite translated concept
-- vocabulary, longest term first, and preserve unknown runs as normal terms.
-- This is query-only and bounded by the input/word limits.
-- Keys are bucketed by their first character in that global order, so each
-- position only compares the keys that can start there (compactQueryKeys is
-- declared with the lexicon, which drops it on every rebuild).
local function UTF8LeadLength(first)
    return first >= 240 and 4 or (first >= 224 and 3 or (first >= 192 and 2 or 1))
end
local function CompactQueryKeys()
    if compactQueryKeys then return compactQueryKeys end
    local keys, seen = {}, {}
    for _, dictionary in ipairs({ SEARCH_QUERY_ALIASES, SEARCH_STOP_WORDS, SEARCH_QUERY_SOFT_STOP_WORDS }) do
        for key in pairs(dictionary) do
            if key:find("[\227-\237][\128-\191][\128-\191]") and not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    table.sort(keys, function(a, b) return #a == #b and a < b or #a > #b end)
    -- A key shorter than its own first character (malformed UTF-8) keeps the
    -- any-position comparison; rank decides between it and a bucket key.
    local byLead, short, rank = {}, {}, {}
    for i = 1, #keys do
        local key = keys[i]
        rank[key] = i
        local leadLength = UTF8LeadLength(byte(key, 1))
        if #key < leadLength then
            short[#short + 1] = key
        else
            local lead = key:sub(1, leadLength)
            local bucket = byLead[lead]
            if not bucket then
                bucket = {}
                byLead[lead] = bucket
            end
            bucket[#bucket + 1] = key
        end
    end
    compactQueryKeys = { byLead = byLead, short = short, rank = rank }
    return compactQueryKeys
end
local function CompactKeyAt(compact, word, index)
    local found
    local bucket = compact.byLead[word:sub(index, index + UTF8LeadLength(byte(word, index)) - 1)]
    if bucket then
        for k = 1, #bucket do
            local key = bucket[k]
            if word:sub(index, index + #key - 1) == key then
                found = key
                break
            end
        end
    end
    local short = compact.short
    for k = 1, #short do
        local key = short[k]
        if word:sub(index, index + #key - 1) == key then
            if not found or compact.rank[key] < compact.rank[found] then found = key end
            break
        end
    end
    return found
end
local function SearchRawWords(normalized, allowSoftStop)
    for _, compound in ipairs(SEARCH_STATE.queryCompounds or EMPTY_SEARCH_RECORDS) do
        local offset = 1
        while true do
            local first, last = normalized:find(compound[1], offset, true)
            if not first then break end
            normalized = normalized:sub(1, first - 1) .. compound[2] .. normalized:sub(last + 1)
            offset = first + #compound[2]
        end
    end
    local raw = {}
    local function Add(word)
        local ignored
        if allowSoftStop then ignored = allowSoftStop ~= "all" and SEARCH_STOP_WORDS[word] else ignored = SearchIgnoreQueryWord(word) end
        if not ignored and word ~= "" and #raw < SEARCH_MAX_RAW_WORDS then raw[#raw + 1] = word end
    end
    local words = {}
    for word in tostring(normalized or ""):gmatch("%S+") do words[#words + 1] = word end
    local multiWord = SEARCH_STATE.multiWordAliases or EMPTY_SEARCH_RECORDS
    local position = 0
    while position < #words do
        position = position + 1
        local word = words[position]
        local bucket = multiWord[word]
        for b = 1, bucket and #bucket or 0 do
            local candidate = bucket[b].words
            local matched = true
            for k = 2, #candidate do
                if words[position + k - 1] ~= candidate[k] then
                    matched = false
                    break
                end
            end
            if matched then
                word = bucket[b].key
                position = position + #candidate - 1
                break
            end
        end
        if not SEARCH_QUERY_ALIASES[word] and word:find("[\227-\237][\128-\191][\128-\191]") then
            local compact, index, unknown = CompactQueryKeys(), 1, ""
            while index <= #word and #raw < SEARCH_MAX_RAW_WORDS do
                local found = CompactKeyAt(compact, word, index)
                if found then
                    Add(unknown)
                    unknown = ""
                    Add(found)
                    index = index + #found
                else
                    local length = UTF8LeadLength(byte(word, index))
                    unknown = unknown .. word:sub(index, index + length - 1)
                    index = index + length
                end
            end
            Add(unknown)
        else
            Add(word)
        end
        if #raw >= SEARCH_MAX_RAW_WORDS then break end
    end
    return raw
end

local SearchEditDistanceWithin

-- ASCII keeps the allocation-free byte path. Native text uses bounded cached
-- UTF-8 symbols so one typed character is one edit in every supported locale.
local utfTokens, utfTokenCount = {}, 0
local function SearchUTFCharacters(text)
    local cached = utfTokens[text]
    if cached then return cached end
    local chars = {}
    for char in text:gmatch("[%z\001-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    if utfTokenCount >= 512 then utfTokens, utfTokenCount = {}, 0 end
    utfTokens[text], utfTokenCount = chars, utfTokenCount + 1
    return chars
end
-- #SearchUTFCharacters(text) without building the table: one character per
-- lead byte of that pattern. ASCII text is its byte length.
local SearchCharCount = SearchText.CharCount
local function SearchTypoDistance(text)
    local native = text:find("[\128-\255]") ~= nil
    local length = native and SearchCharCount(text) or #text
    if length < (native and 2 or 5) then return nil end
    return length >= 8 and 2 or 1
end
-- The characters of SearchUTFCharacters as numbers in a reused array: a lead
-- byte and its continuation bytes in base 256 (unique per byte sequence). A
-- character longer than four bytes returns nil; the caller then compares the
-- strings. Edit-distance rows are reused too: every cell is written before
-- it is read, so nothing is allocated per comparison.
local EDIT_SCRATCH = { codesA = {}, codesB = {}, rowA = {}, rowB = {}, rowC = {}, asciiA = {}, asciiB = {} }
local function SearchUTFCodes(text, out)
    local count, i, n = 0, 1, #text
    while i <= n do
        local lead = byte(text, i)
        if lead < 128 or (lead >= 194 and lead <= 244) then
            local code, j = lead, i + 1
            while j <= n do
                local continuation = byte(text, j)
                if continuation < 128 or continuation > 191 then break end
                code = code * 256 + continuation
                j = j + 1
            end
            if j - i > 4 then return nil end
            count = count + 1
            out[count] = code
            i = j
        else
            i = i + 1
        end
    end
    return count
end
local function SearchUTFEditDistanceWithin(a, b, distance)
    local first, second = EDIT_SCRATCH.codesA, EDIT_SCRATCH.codesB
    local la, lb = SearchUTFCodes(a, first), SearchUTFCodes(b, second)
    if not (la and lb) then
        first, second = SearchUTFCharacters(a), SearchUTFCharacters(b)
        la, lb = #first, #second
    end
    if math.abs(la - lb) > distance then return false end
    local before, previous, current = EDIT_SCRATCH.rowA, EDIT_SCRATCH.rowB, EDIT_SCRATCH.rowC
    for j = 0, lb do previous[j] = j end
    for i = 1, la do
        current[0] = i
        local rowMin = i
        for j = 1, lb do
            local cost = first[i] == second[j] and 0 or 1
            local value = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            if i > 1 and j > 1 and first[i] == second[j - 1] and first[i - 1] == second[j] then
                value = math.min(value, before[j - 2] + 1)
            end
            current[j] = value
            if value < rowMin then rowMin = value end
        end
        if rowMin > distance then return false end
        before, previous, current = previous, current, before
    end
    return previous[lb] <= distance
end

local function SearchAliasTypoKeys()
    if SEARCH_STATE.aliasTypoKeys then return SEARCH_STATE.aliasTypoKeys, SEARCH_STATE.aliasTypoKeyLengths end
    local keys = {}
    for key in pairs(SEARCH_QUERY_ALIASES) do
        if SearchTypoDistance(key) then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    local lengths = {}
    for i = 1, #keys do lengths[i] = SearchCharCount(keys[i]) end
    SEARCH_STATE.aliasTypoKeys, SEARCH_STATE.aliasTypoKeyLengths = keys, lengths
    return keys, lengths
end

local function SearchAliasKeysForTypo(word)
    local maxDistance = SearchTypoDistance(word)
    if not SearchEditDistanceWithin or not maxDistance then return nil end
    if SEARCH_STATE.aliasTypoCache[word] ~= nil then return SEARCH_STATE.aliasTypoCache[word] or nil end
    local bestKeys, bestDistance, bestDelta, bestLength
    local keys, lengths = SearchAliasTypoKeys()
    local wordLength = SearchCharCount(word)
    for i = 1, #keys do
        local key = keys[i]
        local lengthDelta = lengths[i] - wordLength
        if lengthDelta <= maxDistance and lengthDelta >= -maxDistance and SearchEditDistanceWithin(word, key, maxDistance) then
            local delta = math.abs(#key - #word)
            local distance = maxDistance == 1 and 1 or (SearchEditDistanceWithin(word, key, 1) and 1 or maxDistance)
            if not bestKeys or distance < bestDistance or (distance == bestDistance
                and (delta < bestDelta or (delta == bestDelta and #key < bestLength))) then
                bestKeys, bestDistance, bestDelta, bestLength = { key }, distance, delta, #key
            elseif distance == bestDistance and delta == bestDelta and #key == bestLength and #bestKeys < 4 then
                bestKeys[#bestKeys + 1] = key
            end
        end
    end
    SEARCH_STATE.aliasTypoCount = (SEARCH_STATE.aliasTypoCount or 0) + 1
    if SEARCH_STATE.aliasTypoCount > 128 then
        SEARCH_STATE.aliasTypoCache = {}
        SEARCH_STATE.aliasTypoCount = 1
    end
    SEARCH_STATE.aliasTypoCache[word] = bestKeys or false
    return bestKeys
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

local function AddSearchCanonicalRows(text)
    -- Rows end at ";" or at a line break; a wrapped line never joins two rows.
    for row in text:gmatch("[^;\n]+") do
        row = row:match("^%s*(.-)%s*$")
        local result, firstWords, secondWords = row:match("^([^|]*)|([^|]*)|(.+)$")
        if result then AddSearchCanonicalPairs(result, firstWords, secondWords) end
    end
end
AddSearchCanonicalRows([[
demonhunter|demon|hunter;deathknight|death|knight;windshear|wind|shear;castbar|cast|bar;healthbar|health|bar;powerbar|power|bar;showbuffs|show|buffs;
maxbuffs|max|buffs;customcaps|custom|caps
smoothfill|smooth soft fluid|fill;smoothfill|weiche weichen sanfte fluessige|fuellung;smoothfill|relleno llenado|suave fluido;
smoothfill|remplissage|doux fluide;smoothfill|riempimento|fluido morbido;smoothfill|preenchimento|suave fluido
classpower|class|resource resources power;clickcast|click|cast casting;clickthrough|click|through;editmode|edit|mode;
loadconditions|load|condition conditions;readycheck|ready|check;raidmarker|raid|marker;groupnumber|group|number
nameshortening|name|shortening;globalcooldown|global|cooldown;fokuskick|focus|kick;interruptready|interrupt|ready;leveltext|level|text;
levelindicator|level|indicator;statusindicators|status|indicator indicators;statusicons|status|icon icons
onoff|turn|off;minimapicon|minimap|icon button;kofi|ko|fi;menuscale|menu|scale;uiscale|ui|scale;targetsound|target|sound sounds;
unitauras|unit|aura auras;globalstyle|global|style;spellid|spell|id
healthtext|health|text;powertext|power|text;nametext|name|text;classcolor|class|color;rangecheck|range|check checker checking;
distancecheck|distance|check checker checking;outofrange|out|range;unitframe|unit|frame frames
playerframe|player|frame;targetframe|target|frame;focusframe|focus|frame;petframe|pet|frame;bossframes|boss|frame frames;
arenaframes|arena|frame frames;partyframes|party|frame frames;raidframes|raid|frame frames
]])

--- Also returns, by word position, the typed pair a canonical word replaced:
--- labels that spell it out ("global cooldown", "Ko-fi") must still match.
local function SearchCanonicalWords(raw)
    local words, phrases = {}, nil
    local i = 1
    while i <= #raw do
        local word = raw[i]
        local nextWord = raw[i + 1]
        local canonical = nextWord and SEARCH_CANONICAL_PAIRS[word] and SEARCH_CANONICAL_PAIRS[word][nextWord]
        if canonical then
            words[#words + 1] = canonical
            phrases = phrases or {}
            phrases[#words] = word .. " " .. nextWord
            i = i + 2
        elseif (word == "плавное" or word == "плавная") and (nextWord == "заполнение" or nextWord == "заливка") then
            words[#words + 1] = "smoothfill"
            i = i + 2
        elseif (word == "부드러운" and nextWord == "채우기") or (word == "막대" and nextWord == "애니메이션") then
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
    return words, phrases
end

local function BuildSearchQueryClauses(query)
    EnsureSearchLexicon()
    local normalized = NormalizeSearchText(SearchText.Utf8BytePrefix(tostring(query or ""), 256))
    if normalized == SEARCH_STATE.queryClauseCacheNorm and SEARCH_STATE.queryClauseCacheClauses then
        return normalized, SEARCH_STATE.queryClauseCacheClauses
    end

    local function Collect(allowSoftStop)
        local raw = SearchRawWords(normalized, allowSoftStop)
        local words, phrases = SearchCanonicalWords(raw)
        local clauses = {}
        for i = 1, #words do
            if #clauses >= SEARCH_MAX_QUERY_CLAUSES then break end
            local word = words[i]
            local terms, seen = {}, {}
            AddSearchTermUnique(terms, seen, word, allowSoftStop)
            if phrases and phrases[i] then AddSearchTermUnique(terms, seen, phrases[i], allowSoftStop) end
            local aliases = SEARCH_QUERY_ALIASES[word]
            if not aliases then
                local typoKeys = SearchAliasKeysForTypo(word)
                if typoKeys then
                    -- Keep a bounded set of equally close native spellings.
                    -- A new synonym must not displace the typed word's meaning.
                    for _, key in ipairs(typoKeys) do AddSearchTermUnique(terms, seen, key, allowSoftStop) end
                    for _, key in ipairs(typoKeys) do
                        for _, term in ipairs(SEARCH_QUERY_ALIASES[key]) do AddSearchTermUnique(terms, seen, term, allowSoftStop) end
                    end
                end
            end
            if aliases then
                for k = 1, #aliases do AddSearchTermUnique(terms, seen, aliases[k], allowSoftStop) end
            end
            if #terms > 0 then
                local literal = phrases and phrases[i] or word
                for _, term in ipairs(terms) do
                    if term ~= word and term:gsub(" ", "") == word then literal = term break end
                end
                clauses[#clauses + 1] = { word = word, literal = literal, terms = terms }
            end
        end
        return clauses
    end

    local clauses = Collect(false)
    -- "enable", "visible", "off", "aktivieren" and friends are soft stop words, so a
    -- query consisting only of them produced no clauses at all and search returned
    -- nothing. Those are real control labels; retry keeping them as terms.
    if #clauses == 0 and normalized ~= "" then clauses = Collect(true) end
    -- A label made only of hard stop words ("To", "Not now", "Zu", "Aus") is still a label.
    if #clauses == 0 and normalized ~= "" then clauses = Collect("all") end

    SEARCH_STATE.queryClauseCacheNorm = normalized
    SEARCH_STATE.queryClauseCacheClauses = clauses
    return normalized, clauses
end

local searchTokenSeenScratch = {}
local searchTokenSeenScratchBusy = false
local function BuildSearchTokenList(normalized, limit)
    limit = tonumber(limit) or SEARCH_MAX_RECORD_TOKENS
    local tokens = {}
    local wasBusy = searchTokenSeenScratchBusy
    local seen = wasBusy and {} or searchTokenSeenScratch
    searchTokenSeenScratchBusy = true
    for token in tostring(normalized or ""):gmatch("%S+") do
        if #token >= 2 and not SEARCH_STOP_WORDS[token] and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
            if #tokens >= limit then break end
        end
    end
    for i = 1, #tokens do seen[tokens[i]] = nil end
    searchTokenSeenScratchBusy = wasBusy
    return tokens
end

SearchEditDistanceWithin = function(a, b, maxDistance)
    if a == b then return true end
    maxDistance = tonumber(maxDistance) or 1
    if a:find("[\128-\255]") or b:find("[\128-\255]") then
        return SearchUTFEditDistanceWithin(a, b, maxDistance)
    end
    local la, lb = #a, #b
    if math.abs(la - lb) > maxDistance then return false end

    if maxDistance <= 1 then
        if la == lb then
            local firstMismatch, mismatches = nil, 0
            for i = 1, la do
                if byte(a, i) ~= byte(b, i) then
                    mismatches = mismatches + 1
                    firstMismatch = firstMismatch or i
                    if mismatches > 2 then return false end
                end
            end
            if mismatches <= 1 then return true end
            return mismatches == 2
                and firstMismatch < la
                and byte(a, firstMismatch) == byte(b, firstMismatch + 1)
                and byte(a, firstMismatch + 1) == byte(b, firstMismatch)
        end

        local short, long = a, b
        if la > lb then short, long = b, a end
        local i, j, edits = 1, 1, 0
        while i <= #short and j <= #long do
            if byte(short, i) == byte(long, j) then
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

    local prev, curr = EDIT_SCRATCH.asciiA, EDIT_SCRATCH.asciiB
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        curr[0] = i
        local rowMin = curr[0]
        local ca = byte(a, i)
        for j = 1, lb do
            local cost = (ca == byte(b, j)) and 0 or 1
            local value = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            curr[j] = value
            if value < rowMin then rowMin = value end
        end
        if rowMin > maxDistance then return false end
        prev, curr = curr, prev
    end
    return prev[lb] <= maxDistance
end

-- Runs for every record and clause a keystroke does not match literally. Per
-- query, termCache keeps the term's typo distance [1] and character count [2]
-- beside its token results (string keys); a record's token character counts
-- are computed once with its tokens. Only the length test runs per token.
local function SearchTokenCharCounts(rec, tokens)
    local counts = rec.tokenCharCounts
    if counts and rec.tokenCharCountsFor == tokens then return counts end
    counts = {}
    for i = 1, #tokens do counts[i] = SearchCharCount(tokens[i]) end
    rec.tokenCharCounts, rec.tokenCharCountsFor = counts, tokens
    return counts
end
local function SearchFuzzyTokenMatch(rec, term, distanceCache)
    if not rec then return false end
    local termCache = distanceCache[term]
    if not termCache then
        local maxDistance = not term:find(" ", 1, true) and SearchTypoDistance(term) or false
        termCache = { maxDistance or false, maxDistance and SearchCharCount(term) or 0 }
        distanceCache[term] = termCache
    end
    local maxDistance = termCache[1]
    if not maxDistance then return false end
    local tokens = rec.tokens
    if not tokens or rec.tokensLexicon ~= SEARCH_STATE.lexiconGeneration then
        -- Tokens drop stop words, so a rebuilt lexicon re-tokenizes once.
        tokens = BuildSearchTokenList(rec.haystack or "", rec.tokenLimit)
        rec.tokens, rec.tokensLexicon = tokens, SEARCH_STATE.lexiconGeneration
    end
    local counts = rec.tokenCharCounts
    if not counts or rec.tokenCharCountsFor ~= tokens then counts = SearchTokenCharCounts(rec, tokens) end
    local termLength = termCache[2]
    for i = 1, #tokens do
        local lengthDelta = counts[i] - termLength
        if lengthDelta <= maxDistance and lengthDelta >= -maxDistance then
            local token = tokens[i]
            local matched = termCache[token]
            if matched == nil then
                matched = SearchEditDistanceWithin(token, term, maxDistance)
                termCache[token] = matched
            end
            if matched then return true end
        end
    end
    return false
end

local function SearchClauseScore(rec, clause, fuzzyDistanceCache)
    local haystack = rec.haystack or ""
    local source = rec.sourceLabelNorm or rec.labelNorm
    local best = 0
    for i = 1, #clause.terms do
        local term = clause.terms[i]
        local score = 0
        if haystack:find(term, 1, true) then
            if rec.labelNorm == term or source == term or rec.titleNorm == term then score = score + 180 end
            if rec.labelNorm:find(term, 1, true) == 1 or source:find(term, 1, true) == 1 or rec.titleNorm:find(term, 1, true) == 1 then score = score + 90 end
            if rec.labelNorm:find(term, 1, true) or source:find(term, 1, true) then score = score + 70 end
            if rec.titleNorm:find(term, 1, true) then score = score + 55 end
            if rec.hintNorm and rec.hintNorm:find(term, 1, true) then score = score + 45 end
            if rec.groupNorm:find(term, 1, true) then score = score + 35 end
            score = score + 10
            if term == clause.word or term == clause.literal then score = score + 120
            else score = math.min(score, 40) end
        elseif term == clause.word and SearchFuzzyTokenMatch(rec, term, fuzzyDistanceCache) then
            score = 28
        end
        if score > best then best = score end
    end
    return best > 0, best
end

local function SearchLooksLikeSupportQuestion(query, normalized)
    normalized = normalized or NormalizeSearchText(query)
    if normalized == "" then return false end
    if tostring(query or ""):find("?", 1, true) then return true end
    if normalized:find("how ", 1, true) or normalized:find("where ", 1, true) or normalized:find("why ", 1, true) then return true end
    if normalized:find("what ", 1, true) or normalized:find("help ", 1, true) then return true end
    if normalized:find("do i", 1, true) or normalized:find("can i", 1, true) then return true end
    if normalized:find("can you", 1, true) or normalized:find("could you", 1, true)
        or normalized:find("would you", 1, true) or normalized:find("please ", 1, true) then return true end
    if normalized:find("kannst du", 1, true) or normalized:find("konntest du", 1, true)
        or normalized:find("kannst ", 1, true) or normalized:find("bitte ", 1, true) then return true end
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

local SEARCH_CONTROL_QUERY_TERMS = "toggle checkbox switch enable disable enabled disabled show hide dropdown select choose slider adjust " ..
    "increase decrease color colour swatch input field textfield editbox aktivier deaktivier einschalt ausschalt anzeigen ausblenden auswahl " ..
    "auswaehlen dropdown regler schieberegler aument reducir ajustar seleccionar choisir activer desactiver selezionare attivare disattivare " ..
    "ativar desativar выбрать включить отключить 설정 선택 사용 비활성 활성 下拉 选择 启用 停用 選擇 啟用 停用"

local function SearchLooksLikeControlQuestion(query, normalized)
    normalized = normalized or NormalizeSearchText(query)
    if normalized == "" then return false end
    if normalized:find("turn on", 1, true) or normalized:find("turn off", 1, true) then return true end
    for term in SEARCH_CONTROL_QUERY_TERMS:gmatch("%S+") do
        if normalized:find(term, 1, true) then return true end
    end
    return false
end

local SEARCH_GENERIC_LOCATION_QUESTION_TERMS = "where|where is|where are|where do|where can|where to|how do|how to|how can|wo|wo ist|wo sind|wo " ..
    "kann|wo finde|wie|wie kann"

local SEARCH_GENERIC_LOCATION_ACTION_TERMS = "change|changed|changing|configure|customize|customise|edit|find|set|select|choose|adjust|move|" ..
    "resize|enable|disable|show|hide|turn on|turn off|aendern|aendere|andern|einstellen|finden|auswaehlen|verschieben|aktivieren|deaktivieren|" ..
    "anzeigen|ausblenden"

local SEARCH_CONTROL_KINDS = M.KeySetFromWords "toggle dropdown segment slider color button textinput"

local function SearchContainsTerm(normalized, term)
    normalized = tostring(normalized or "")
    if normalized == "" or term == "" then return false end
    if term:find(" ", 1, true) then return normalized:find(term, 1, true) ~= nil end
    return (" " .. normalized .. " "):find(" " .. term .. " ", 1, true) ~= nil
end

local function SearchContainsAnyTerm(normalized, terms)
    for term in terms:gmatch("[^|]+") do
        if SearchContainsTerm(normalized, term) then return true end
    end
    return false
end

local function SearchLooksLikeGenericLocationQuestion(query, normalized)
    normalized = normalized or NormalizeSearchText(query)
    if normalized == "" then return false end
    local hasQuestion = SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_QUESTION_TERMS)
    if not hasQuestion then return false end
    if normalized:find("where is", 1, true) or normalized:find("where are", 1, true) then return true end
    if normalized:find("wo ist", 1, true) or normalized:find("wo sind", 1, true) then return true end
    return SearchContainsAnyTerm(normalized, SEARCH_GENERIC_LOCATION_ACTION_TERMS)
end

local function SearchGenericLocationSubjectClauses(query, normalized)
    normalized = normalized or NormalizeSearchText(query)
    if not SearchLooksLikeGenericLocationQuestion(query, normalized) then return nil, nil end
    local raw = SearchRawWords(normalized)
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
    local labelText = (rec.labelNorm or "") .. " " .. (rec.sourceLabelNorm or "") .. " " .. (rec.titleNorm or "")
    local contextText = labelText .. " " .. tostring(rec.hintNorm or "") .. " " .. tostring(rec.groupNorm or "")
    local haystack = tostring(rec.haystack or "")
    local labelMatches, contextMatches, haystackMatches = 0, 0, 0
    for i = 1, #clauses do
        local terms = clauses[i] and clauses[i].terms
        local inLabel, inContext, inHaystack = false, false, false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if term == clauses[i].word or term == clauses[i].literal then
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

local function SearchGenericLocationBoost(rec, clauses, matchedClauses, missedClauses, normalized)
    if not rec or type(clauses) ~= "table" or #clauses == 0 then return 0 end
    if rec.labelNorm == normalized or rec.sourceLabelNorm == normalized then return 860 + #clauses * 160 end
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
    local source, title = rec.sourceLabelNorm or label, rec.titleNorm or ""
    local direct = 0
    for i = 1, clauseCount do
        local clause = clauses[i]
        local terms = clause and clause.terms
        local matched = false
        if type(terms) == "table" then
            for k = 1, #terms do
                local term = terms[k]
                if (term == clause.word or term == clause.literal)
                    and (label:find(term, 1, true) or source:find(term, 1, true) or title:find(term, 1, true)) then
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


function SearchText.ReleaseQueryCaches()
    searchLexiconReady, LEXICON_SOURCES.job, compactQueryKeys = false, nil, nil
    SEARCH_STOP_WORDS, SEARCH_QUERY_SOFT_STOP_WORDS = LEXICON_SOURCES.stop, LEXICON_SOURCES.soft
    SEARCH_QUERY_ALIASES = LEXICON_SOURCES.aliases
    utfTokens, utfTokenCount = {}, 0
end

Parts.AddPageLocalizedSearchKeywords = AddPageLocalizedSearchKeywords
Parts.BuildSearchQueryClauses = BuildSearchQueryClauses
Parts.BuildSearchTokenList = BuildSearchTokenList
Parts.DASHBOARD_ROUTE_CHANGELOG = DASHBOARD_ROUTE_CHANGELOG
Parts.DASHBOARD_ROUTE_RECOVERY = DASHBOARD_ROUTE_RECOVERY
Parts.DASHBOARD_ROUTE_SCALING = DASHBOARD_ROUTE_SCALING
Parts.EnsureSearchLexicon = EnsureSearchLexicon
Parts.SearchCharCount = SearchCharCount
Parts.SearchClauseScore = SearchClauseScore
Parts.SearchEditDistanceWithin = SearchEditDistanceWithin
Parts.SearchGenericLocationBoost = SearchGenericLocationBoost
Parts.SearchGenericLocationSubjectClauses = SearchGenericLocationSubjectClauses
Parts.SearchIgnoreQueryWord = SearchIgnoreQueryWord
Parts.SearchKeywordList = SearchKeywordList
Parts.SearchLooksLikeControlQuestion = SearchLooksLikeControlQuestion
Parts.SearchLooksLikeSupportQuestion = SearchLooksLikeSupportQuestion
Parts.SearchResultSpecificityBoost = SearchResultSpecificityBoost
Parts.SearchSupportQuestionBoost = SearchSupportQuestionBoost
Parts.SearchTokenCharCounts = SearchTokenCharCounts
