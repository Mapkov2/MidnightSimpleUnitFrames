-- Real cold search: dropdown choices, explicit aliases and help on unopened pages.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = locale })
local M = mw.M
assert(mw.core.FinalizeLocale() == locale)
local function Ready()
    M.Search._CoreAPI.GetSearchRecords()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search metadata timers did not drain")
end
assert(not M.cache.uf_player, "target page was already warm")
Ready()
assert(not M.cache.uf_player, "metadata decode built the target page")
local translated = M.Tr(locale == "enGB" and "None (solid color)" or "By Role")
local normalized, choiceFound = M.Search.Text.NormalizeSearchText(translated), false
for _, row in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
    if row.key == (locale == "enGB" and "opt_bars" or "gf_layout") and row.kind == "dropdown"
        and row.haystack:find(normalized, 1, true) then
        choiceFound = true
        break
    end
end
assert(choiceFound, "unopened sorting dropdown omitted its translated choice " .. translated)
local cases = { { "camelot", "Round Level Badge" }, { "medallion", "Round Level Badge" } }
for _, case in ipairs(cases) do
    local found
    for _, row in ipairs(M.Search._CoreAPI.SearchPages(case[1])) do
        if row.key == "uf_player" and row.label == M.Tr(case[2]) then found = row break end
    end
    assert(found and found.static, "cold metadata query missed " .. case[1])
    assert(not M.cache.uf_player, "cold query built the target page")
end
-- The status anchor dropdown's choices contain BOTTOMRIGHT, unlike its label/path.
local records = M.Search.StaticIndex.GetRecords()
local choice
for _, row in ipairs(records) do
    local key = row.exactTarget and row.exactTarget.settingKey or ""
    if row.key == "uf_player" and row.kind == "dropdown" and key:find("[Aa]nchor")
        and row.haystack:find("bottom right", 1, true) then choice = row break end
end
assert(choice, "cold dropdown rows omitted their anchor choices")
assert(mw:Select("uf_player"))
Ready()
for _, case in ipairs(cases) do
    local found
    for _, row in ipairs(M.Search._CoreAPI.SearchPages(case[1])) do
        if row.key == "uf_player" and row.label == M.Tr(case[2]) then found = row break end
    end
    assert(found, "warming the page lost " .. case[1])
end
-- Curated provider phrases bind to one indexed setting, including on a warm
-- page. Shared phrases remain ambiguous until the provider changes its rows.
local rows = {}
local function Row(label, key, phrases)
    return {pageKey = "uf_player", kind = "toggle", label = label, settingKey = key,
        keywords = { "ordinary diagnostic keywords" }, queryPhrases = phrases}
end
local function Promoted(query)
    for _, result in ipairs(M.Search._CoreAPI.SearchPages(query)) do
        if result.exactQueryHit then return result.exactTarget.settingKey end
    end
end
rows[1] = Row("Diagnostic first option", "diag.first", {"my fixture", "muéstrame la primera", "opción compartida", "where is my fixture", "the ambiguous fixture", "shared diagnostic phrase"})
rows[2] = Row("Diagnostic second option", "diag.second", {"opción compartida", "where is my fixture", "the ambiguous fixture", "shared diagnostic phrase"})
rows[3] = Row("Diagnostic third option", "diag.first", {"SHARED diagnostic phrase"})
assert(M.RegisterSearchProvider("phrase-test", function() return rows end))
Ready()
assert(Promoted("my fixture") == "diag.first")
assert(Promoted("¿Muéstrame la primera?") == "diag.first" and not Promoted("¡Opción compartida!"))
assert(not Promoted("where is my fixture") and not Promoted("please the ambiguous fixture"))
assert(not Promoted("shared diagnostic phrase") and not Promoted("ordinary diagnostic keywords"))
rows[1], rows[2], rows[3] = rows[2], nil, nil
assert(M.InvalidateSearchProvider("phrase-test"))
Ready()
assert(Promoted("shared diagnostic phrase") == "diag.second" and Promoted("where is my fixture") == "diag.second")
assert(M.RegisterSearchProvider("phrase-test", nil))
Ready()
assert(not Promoted("shared diagnostic phrase"))
print("search_cold_metadata_smoke " .. flavor .. ": cold choices, keywords and help found; warm search retained")
