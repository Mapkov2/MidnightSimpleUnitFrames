-- The baked search index stores English text. Localized labels are layered on at
-- decode time, so a player on a non-English client must still find a control by its
-- translated name -- and by its English name, since both end up in the haystack.
--
-- This is easy to break silently: drop the M.Tr overlay in the decoder, or bake a
-- normalization that no longer matches the runtime normalizer, and every non-English
-- client quietly loses half its search while enUS stays perfect.
local repoRoot = ...
repoRoot = tostring(repoRoot or "."):gsub("[/\\]+$", "")

local SEARCH_DIR = repoRoot .. "/MidnightSimpleUnitFrames/Shell/Menu2/Search/"
local LOCALE_DIR = repoRoot .. "/MidnightSimpleUnitFrames/Locales/"
local LOCALES = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

-- Sampled rather than exhaustive: the full sweep is ~17k queries. Every locale still
-- gets an independent sample spread across the whole label list.
local SAMPLE_TARGET = 25
local MINIMUM_FINDABLE = 0.85
local MINIMUM_TRANSLATED = 200

local function PickValues(source, names, defaultEmpty)
    local values, count = {}, 0
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = source[name]
        if defaultEmpty then value = value or {} end
        values[count] = value
    end
    return unpack(values, 1, count)
end

-- English labels come from the blob itself; a decoded record already carries the
-- translated label and cannot be used to look its own translation up.
local englishLabels = (function()
    local scratch = { MSUF2 = {} }
    local chunk = assert(loadfile(SEARCH_DIR .. "MSUF_Menu2_Search_StaticIndex_Data.lua"))
    chunk("MidnightSimpleUnitFrames", scratch)
    local blob = assert(scratch.MSUF2.Search and scratch.MSUF2.Search.StaticIndexBlob,
        "static index blob missing")
    local seen, out = {}, {}
    for line in blob:gmatch("[^\n]+") do
        local label = line:match("^[^\t]*\t([^\t]*)\t")
        if label and label ~= "" and not seen[label] then
            seen[label] = true
            out[#out + 1] = label
        end
    end
    return out
end)()
assert(#englishLabels > 400, "static index exposed only " .. #englishLabels .. " distinct labels")

local function RunLocale(locale)
    local L = {}
    local M
    M = {
        SearchData = {}, navItems = {}, pages = {}, cache = {},
        Theme = {}, Widgets = {}, activeKey = "search",
        Pick = function(s, n) return PickValues(s, n) end,
        PickDefaults = function(s, n) return PickValues(s, n, true) end,
        KeySetFromWords = function(text)
            local out = {}
            for key in tostring(text or ""):gmatch("%S+") do out[key] = true end
            return out
        end,
        -- Mirrors the direct-hit branch of MSUF_Menu2_Theme's Tr.
        Tr = function(text) return rawget(L, text) or text end,
        InvalidatePage = function() end,
        SelectPage = function() end,
    }
    local MSUF = { LOCALE = locale, L = L, MSUF2 = M, RegisterLocale = function() return L end }
    _G.MSUF_NS = MSUF
    _G.InCombatLockdown = function() return false end
    _G.UnitAffectingCombat = function() return false end
    _G.GetLocale = function() return locale end
    _G.C_Timer = { After = function(_, callback) if callback then callback() end end }

    local localeChunk = assert(loadfile(LOCALE_DIR .. locale .. ".lua"),
        "missing locale file for " .. locale)
    assert(pcall(localeChunk, "MidnightSimpleUnitFrames", MSUF), locale .. " locale file failed")

    for _, file in ipairs({
        "MSUF_Menu2_Search_Data.lua", "MSUF_Menu2_Search_Keywords.lua",
        "MSUF_Menu2_Search_QueryAliases.lua", "MSUF_Menu2_Search_Text.lua",
        "MSUF_Menu2_Search_StaticIndex_Data.lua", "MSUF_Menu2_Search_StaticIndex.lua",
        "MSUF_Menu2_Search_IndexQuery.lua",
    }) do
        local chunk, err = loadfile(SEARCH_DIR .. file)
        assert(chunk, file .. ": " .. tostring(err))
        local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
        assert(ok, locale .. " / " .. file .. ": " .. tostring(result))
    end

    local SearchPages = assert(M.Search and M.Search._CoreAPI and M.Search._CoreAPI.SearchPages,
        "search API missing for " .. locale)

    local translated = {}
    for i = 1, #englishLabels do
        local english = englishLabels[i]
        local localized = rawget(L, english)
        -- Skip labels whose translation is too short to be a legal query, and the
        -- ones the locale renders as a stop word ("Aus", "Zu"). Those are the same
        -- class that is unreachable by bare label in English too.
        if type(localized) == "string" and localized ~= english and #localized > 3 then
            translated[#translated + 1] = { english = english, localized = localized }
        end
    end
    assert(#translated >= MINIMUM_TRANSLATED, string.format(
        "%s translates only %d indexed labels; the locale overlay is probably broken",
        locale, #translated))

    local step = math.max(1, math.floor(#translated / SAMPLE_TARGET))
    local checked, foundLocalized, foundEnglish, misses = 0, 0, 0, {}
    for i = 1, #translated, step do
        local row = translated[i]
        checked = checked + 1
        local okLocal, localResults = pcall(SearchPages, row.localized)
        if okLocal and #localResults > 0 then
            foundLocalized = foundLocalized + 1
        elseif #misses < 5 then
            misses[#misses + 1] = row.localized .. " (" .. row.english .. ")"
        end
        local okEnglish, englishResults = pcall(SearchPages, row.english)
        if okEnglish and #englishResults > 0 then foundEnglish = foundEnglish + 1 end
    end

    local localizedRatio = foundLocalized / checked
    assert(localizedRatio >= MINIMUM_FINDABLE, string.format(
        "%s finds only %d/%d controls by their translated name (%.0f%%): %s",
        locale, foundLocalized, checked, localizedRatio * 100, table.concat(misses, ", ")))
    -- English has to keep working too: the baked haystack is what makes the index
    -- bilingual, and losing it would strand anyone using English setting names.
    local englishRatio = foundEnglish / checked
    assert(englishRatio >= MINIMUM_FINDABLE, string.format(
        "%s finds only %d/%d controls by their English name (%.0f%%)",
        locale, foundEnglish, checked, englishRatio * 100))

    return checked, localizedRatio, englishRatio
end

local report = {}
for _, locale in ipairs(LOCALES) do
    local checked, localizedRatio, englishRatio = RunLocale(locale)
    report[#report + 1] = string.format("%s %.0f%%/%.0f%%", locale,
        localizedRatio * 100, englishRatio * 100)
    -- Each locale gets a clean namespace; the search modules cache per load.
    _G.MSUF_NS = nil
end

io.write("menu2_search_locale_coverage_smoke: ok (localized/english) " ..
    table.concat(report, " ") .. "\n")
