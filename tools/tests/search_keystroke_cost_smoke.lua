-- search_keystroke_cost_smoke.lua <repoRoot>
--
-- Menu search runs SearchPages on every debounced keystroke over the whole
-- index (about 3,000-3,600 records). Its cost is pinned per locale with two
-- deterministic measures, never wall-clock time:
--   * Lua VM instructions per keystroke (count hook, every typed prefix);
--   * kilobytes allocated per keystroke, with the collector stopped.
-- Review 2026-09-30 (F3) measured the fuzzy typo matcher at 2-4x the old
-- cost and up to 4 MB of garbage per keystroke outside English: it re-ran
-- UTF-8 pattern tests and built character tables for every record token.
--
-- Budgets sit about 40% above the fixed matcher on the current index and
-- below the old one. When the index grows for real, re-measure with this smoke
-- and raise a budget together with the reason; never to hide a regression.
--
-- Boots the real Mainline core and Options graph once per locale.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local CASES = {
    { locale = "enUS", instructions = 1050, kilobytes = 120, queries = {
        "health text color", "castbar", "focus kick", "helth txt colr", "castbr colour", "fokus kick",
        "raid auras", "bar colors", "class color", "minimap icn", "absorb shiled", "party frmes hidden",
        "how do i make text bigger", "raid", "threat" } },
    { locale = "deDE", instructions = 1600, kilobytes = 120, queries = {
        "lebenstext farbe", "zauberleiste", "größe ändern", "schriftgröße", "lebensbalken farbe",
        "zauberleiste groesse", "schriftgrosse", "gruppenframes versteckt", "castbar farbe", "zielframe groesser" } },
    { locale = "ruRU", instructions = 2400, kilobytes = 120, queries = {
        "цвет текста здоровья", "полоса заклинаний", "здоровя цвет", "полоса заклинанй",
        "размер рамки цели", "скрытые рамки группы" } },
    { locale = "zhCN", instructions = 1500, kilobytes = 120, queries = {
        "生命值文字颜色", "施法条", "我想调大目标框体", "施法条颜色", "目标框体大小", "隐藏小队框体" } },
    { locale = "koKR", instructions = 1800, kilobytes = 120, queries = {
        "체력 텍스트 색상", "시전바", "시전 바 색상", "대상 프레임 크기", "숨겨진 파티 프레임" } },
}

local summary = {}
for _, case in ipairs(CASES) do
    local world = World.New(root, "Mainline", { locale = case.locale })
    world.env.MAX_BOSS_FRAMES = 5 -- Harness gap only: every client defines it.
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, case.locale .. ": boot failed: " .. tostring(failure and failure.message))
    local e, n = world.env, world.core
    assert(n.FinalizeLocale() == case.locale, case.locale .. ": locale pack not selected")
    local api = assert(n.MSUF2.Search._CoreAPI, case.locale .. ": search core API missing")
    n.MSUF2.frame = e.CreateFrame("Frame", nil, e.UIParent)
    n.MSUF2.frame:Show()
    -- Warm like a typing session: the index is built and every record tokenized.
    for _, query in ipairs(case.queries) do api.SearchPages(query) end
    local strokes, ticks, kilobytes, results = 0, 0, 0, 0
    local function Tick() ticks = ticks + 1 end
    for _, query in ipairs(case.queries) do
        local prefix, count = "", 0
        for character in query:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            prefix, count = prefix .. character, count + 1
            if count >= 2 then
                collectgarbage("collect")
                collectgarbage("stop")
                local before = collectgarbage("count")
                debug.sethook(Tick, "", 1000)
                local rows = api.SearchPages(prefix)
                debug.sethook()
                kilobytes = kilobytes + (collectgarbage("count") - before)
                collectgarbage("restart")
                strokes, results = strokes + 1, results + #rows
            end
        end
    end
    assert(strokes > 0 and results > 0, case.locale .. ": the queries found nothing")
    local perStroke, kbPerStroke = ticks / strokes, kilobytes / strokes
    assert(perStroke <= case.instructions, string.format("%s: %.0f k instructions per keystroke, budget %d k",
        case.locale, perStroke, case.instructions))
    assert(kbPerStroke <= case.kilobytes, string.format("%s: %.0f KB allocated per keystroke, budget %d KB",
        case.locale, kbPerStroke, case.kilobytes))
    summary[#summary + 1] = string.format("%s %.0fk/%.0fKB", case.locale, perStroke, kbPerStroke)
end
print("search_keystroke_cost_smoke: ok (per keystroke: " .. table.concat(summary, ", ") .. ")")
