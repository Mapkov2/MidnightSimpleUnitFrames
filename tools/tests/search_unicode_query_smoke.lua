-- search_unicode_query_smoke.lua <repoRoot>
--
-- Menu search over non-Latin text (quality program A-C6, C6.7), on the real
-- Mainline core and Options graph:
--   * Cyrillic capitals fold like Latin ones (string.lower folds ASCII only),
--     and Ё/ё fold to е, so "Полоса" finds what "полоса" finds;
--   * an alias key of two words ("мини карта", "재사용 대기시간") matches the
--     two typed words as one clause instead of never matching;
--   * the minimum query length counts characters: one Cyrillic or CJK
--     character (two or three bytes) is not a query yet, two are;
--   * the current-page boost follows the page the search started from
--     (searchReturnKey) while the results page is showing;
--   * byte cuts (query, record haystacks) never end inside a UTF-8 character.
-- Plain Lua 5.1, repo root as arg 1.
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Boot(locale)
    local world = World.New(root, "Mainline", { locale = locale })
    world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, locale .. ": boot failed: " .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    assert(core.FinalizeLocale() == locale, locale .. ": locale pack not selected")
    local M = core.MSUF2
    M.frame = env.CreateFrame("Frame", nil, env.UIParent)
    M.frame:Show()
    return world, M
end

local function ValidUtf8(text)
    local i, n = 1, #text
    while i <= n do
        local b = text:byte(i)
        local length = b < 128 and 1 or (b >= 240 and 4 or (b >= 224 and 3 or (b >= 194 and 2 or 0)))
        if length == 0 or i + length - 1 > n then return false end
        for j = i + 1, i + length - 1 do
            local c = text:byte(j)
            if c < 128 or c > 191 then return false end
        end
        i = i + length
    end
    return true
end

local function Keys(rows)
    local out = {}
    for i = 1, #rows do out[i] = tostring(rows[i].key) .. "|" .. tostring(rows[i].label) end
    return table.concat(out, ";")
end

local function ClauseWords(clauses)
    local out = {}
    for i = 1, #clauses do out[i] = clauses[i].word end
    return table.concat(out, ",")
end

local function HasTerm(clauses, term)
    for i = 1, #clauses do
        for k = 1, #clauses[i].terms do
            if clauses[i].terms[k] == term then return true end
        end
    end
    return false
end

-- ruRU ------------------------------------------------------------------------
do
    local _, M = Boot("ruRU")
    local Text = M.Search.Text
    local api = M.Search._CoreAPI
    local routing = M.Search._RoutingContext
    Check(Text.NormalizeSearchText("ПОЛОСА Заклинаний") == "полоса заклинаний",
        "ruRU: Cyrillic capitals do not fold: " .. Text.NormalizeSearchText("ПОЛОСА Заклинаний"))
    Check(Text.NormalizeSearchText("Ёлка ёж ЭЮЯ Ѐ") == "елка еж эюя ѐ",
        "ruRU: Ё/ё or the late capitals do not fold: " .. Text.NormalizeSearchText("Ёлка ёж ЭЮЯ Ѐ"))
    local lower = api.SearchPages("полоса заклинаний")
    local upper = api.SearchPages("Полоса Заклинаний")
    Check(#lower > 0, "ruRU: the lowercase castbar query found nothing")
    Check(Keys(lower) == Keys(upper), "ruRU: a capitalized query finds other results than the lowercase one")

    local _, clauses = routing.BuildSearchQueryClauses("мини карта")
    Check(#clauses == 1 and clauses[1].word == "мини карта" and HasTerm(clauses, "minimap"),
        "ruRU: the two-word alias key did not become one clause (" .. ClauseWords(clauses) .. ")")
    local rows = api.SearchPages("мини карта")
    local minimapFirst = rows[1] and tostring(rows[1].haystack or ""):find("minimap", 1, true) ~= nil
    Check(minimapFirst, "ruRU: the two-word alias did not rank a minimap result first")

    Check(#api.SearchPages("п") == 0, "ruRU: one Cyrillic character already ran a search")
    Check(#api.SearchPages("по") >= 0, "ruRU: two Cyrillic characters must be a query")
    local queryLen = M.Search._RenderContext.QueryLength
    Check(type(queryLen) == "function" and queryLen("п") == 1 and queryLen("по") == 2,
        "ruRU: the results page does not count query characters")

    -- Byte cuts.
    Check(Text.Utf8BytePrefix ~= nil, "Text.Utf8BytePrefix missing")
    if Text.Utf8BytePrefix then
        local sample = "аб"  -- four bytes
        Check(Text.Utf8BytePrefix(sample, 3) == "а" and Text.Utf8BytePrefix(sample, 4) == sample
            and Text.Utf8BytePrefix(sample, 1) == "", "Utf8BytePrefix cut inside a character")
    end
    -- One ASCII byte first: the 256-byte cut lands inside the 128th "я".
    local _, cutClauses = routing.BuildSearchQueryClauses("a" .. string.rep("я", 200))
    Check(#cutClauses > 0, "ruRU: the long query built no clause")
    for i = 1, #cutClauses do
        Check(ValidUtf8(cutClauses[i].word), "ruRU: the 256-byte query cut split a character")
    end
    -- Provider records cut their haystack at 1200 bytes. Two labels one ASCII
    -- byte apart put the cut inside a character for one of them.
    local keywords = {}
    for i = 1, 96 do keywords[i] = string.rep("ж", 6) end
    M.RegisterSearchProvider("C6.7 smoke", function()
        return {
            { pageKey = "opt_bars", kind = "toggle", label = "Тест a", keywords = keywords },
            { pageKey = "opt_bars", kind = "toggle", label = "Тест ab", keywords = keywords },
        }
    end)
    local records = api.GetSearchRecords()
    local provided, bad = 0, 0
    for i = 1, #records do
        local rec = records[i]
        if rec.haystack and not ValidUtf8(rec.haystack) then bad = bad + 1 end
        if rec.provided and (rec.label == "Тест a" or rec.label == "Тест ab") then provided = provided + 1 end
    end
    Check(provided == 2, "ruRU: the provider rows did not become records (" .. provided .. ")")
    Check(bad == 0, "ruRU: " .. bad .. " record haystacks end inside a UTF-8 character")
    M.RegisterSearchProvider("C6.7 smoke", nil)
end

-- koKR: the Korean two-word alias key ------------------------------------------
do
    local _, M = Boot("koKR")
    local _, clauses = M.Search._RoutingContext.BuildSearchQueryClauses("재사용 대기시간")
    Check(#clauses == 1 and HasTerm(clauses, "cooldown"),
        "koKR: the two-word alias key did not become one clause (" .. ClauseWords(clauses) .. ")")
    local _, typo = M.Search._RoutingContext.BuildSearchQueryClauses("채력")
    Check(#typo == 1 and HasTerm(typo, "체력") and HasTerm(typo, "기력") and HasTerm(typo, "채팅")
        and #typo[1].terms <= 18, "koKR: an arbitrary typo alias displaced equally close native meanings")
end

-- zhCN: one CJK character is not a query --------------------------------------
do
    local _, M = Boot("zhCN")
    local api = M.Search._CoreAPI
    Check(#api.SearchPages("施") == 0, "zhCN: one CJK character already ran a search")
    Check(#api.SearchPages("施法条") > 0, "zhCN: the castbar query found nothing")
    for query, count in pairs({ ["目标框体大小"] = 3, ["施法条颜色"] = 2 }) do
        local _, clauses = M.Search._RoutingContext.BuildSearchQueryClauses(query)
        Check(#clauses == count, "zhCN: compact independent concepts collapsed to OR: " .. query)
    end
end

-- enUS: the page the search started from gets the current-page boost ----------
do
    local _, M = Boot("enUS")
    local api = M.Search._CoreAPI
    Check(Keys(api.SearchPages("DoT")) == Keys(api.SearchPages("dot")),
        "enUS: a typed acronym was mistaken for a camelCase setting key")
    M.activeKey = "home"
    local neutral = api.SearchPages("texture")
    local rec
    for i = 1, #neutral do
        if neutral[i].key ~= "home" and neutral[i].key ~= neutral[1].key then rec = neutral[i]; break end
    end
    if Check(rec ~= nil, "enUS: texture search found no record on a second page") then
        local before = rec.score
        -- The user typed on rec's page: the results page is showing now.
        M.activeKey, M.searchReturnKey = "search", rec.key
        api.SearchPages("texture")
        Check(rec.score == before + 120, "enUS: the page the search started from (" .. tostring(rec.key)
            .. ") got no current-page boost (" .. tostring(before) .. " -> " .. tostring(rec.score) .. ")")
        M.activeKey = rec.key
        api.SearchPages("texture")
        Check(rec.score == before + 120, "enUS: the active page lost its current-page boost")
    end
end

if #failures > 0 then
    error("search_unicode_query_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("search_unicode_query_smoke: ok (Cyrillic folding, two-word aliases, character minimum, return-page boost, UTF-8 cuts)")
