-- search_label_findability_smoke.lua <repoRoot> <flavor> <locale>
--
-- Typing an option's visible name finds it. On the real core and Options graph,
-- in one client language:
--   * every option of the generated index whose shown name no other option of
--     this client shares is in the first six results (the dropdown shows six)
--     when its name is typed;
--   * named cases that used to fail stay fixed (English clients): a label made of
--     stop words ("Player Enable", "To", "Not now"), a page name that other page
--     names contain ("Target ..." against Focus Target), a typed pair the parser
--     joins ("global cooldown", "Ko-fi"), a button whose name is typed, and an
--     easter egg that no longer empties the list for an ordinary word.
-- Names shorter than the search minimum (the class resource slot swatches "1"
-- to "9") are found by their slot name instead and are skipped here.
-- Plain Lua 5.1.
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor, locale = arg[2] or "Mainline", arg[3] or "enUS"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local world = World.New(root, flavor, { locale = locale })
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and (tostring(failure.file) .. ": " .. tostring(failure.message)))
local e, n = world.env, world.core
assert(n.FinalizeLocale() == locale, locale .. ": locale pack not selected")
local M = n.MSUF2
M.frame = e.CreateFrame("Frame", nil, e.UIParent)
M.frame:Show()
local api = M.Search._CoreAPI
local CharCount = M.Search.Text.CharCount
local Normalize = M.Search.Text.NormalizeSearchText
local PALETTE = 6

local function Rank(query, wanted)
    local rows = api.SearchPages(query)
    for i = 1, #rows do
        if wanted(rows[i]) then return i, rows end
    end
    return nil, rows
end

---------------------------------------------------------------------------
-- Every uniquely named option, by its shown name
---------------------------------------------------------------------------
local static, byName = {}, {}
for _, rec in ipairs(api.GetSearchRecords()) do
    if rec.static then
        static[#static + 1] = rec
        local name = Normalize(rec.label)
        byName[name] = (byName[name] or 0) + 1
    end
end
Check(#static > 1500, flavor .. " " .. locale .. ": only " .. #static .. " index rows reached search")
local tested, missed = 0, {}
for _, rec in ipairs(static) do
    local name = Normalize(rec.label)
    if byName[name] == 1 and CharCount(name) >= 2 then
        tested = tested + 1
        local rank = Rank(rec.label, function(row) return row.searchIdentity == rec.searchIdentity end)
        if not rank or rank > PALETTE then
            missed[#missed + 1] = string.format("%s \"%s\" (%s)", rec.key, rec.label, rank and ("rank " .. rank) or "not found")
        end
    end
end
Check(tested > 400, flavor .. " " .. locale .. ": only " .. tested .. " uniquely named options")
if #missed > 0 then
    Check(false, flavor .. " " .. locale .. ": " .. #missed .. " uniquely named options are not in the first "
        .. PALETTE .. " results for their own name, e.g. " .. table.concat(missed, "; ", 1, math.min(8, #missed)))
end

---------------------------------------------------------------------------
-- Named cases (English text)
---------------------------------------------------------------------------
if locale == "enUS" or locale == "enGB" then
    local function Expect(query, pageKey, label, limit)
        local rank, rows = Rank(query, function(row) return row.key == pageKey and row.label == label end)
        local got = {}
        for i = 1, math.min(4, #rows) do got[#got + 1] = tostring(rows[i].key) .. ":" .. tostring(rows[i].label) end
        Check(rank and rank <= limit, string.format("%s: \"%s\" ranks %s:%s at %s, want <= %d (got %s)",
            flavor, query, pageKey, label, tostring(rank), limit, table.concat(got, ", ")))
    end
    Expect("Player Enable", "uf_player", "Enable", 2)
    Expect("Target Fade in (seconds)", "uf_target", "Fade in (seconds)", 3)
    Expect("Target Size", "uf_target", "Size", PALETTE)
    if world.core.Client.IsRetail and not world.core.Client.IsForever then
        Expect("global cooldown", "classpower", "Warn during the last global cooldown", PALETTE)
    end
    Expect("Ko-fi", "home", "Ko-fi", PALETTE)
    Expect("Not now", "home", "Not now", PALETTE)
    if M.pages.gameplay then Expect("To", "gameplay", "To", PALETTE) end
    if M.pages.gf_auras then Expect("Selected Spell Color", "gf_auras", "Selected Spell Color", 1) end
    local spells = api.SearchPages("spells")
    Check(#spells > 3, flavor .. ": \"spells\" returns " .. #spells .. " result(s); an easter egg emptied the list")
    local castbarColor = api.SearchPages("castbar color")
    Check(castbarColor[1] and castbarColor[1].kind == "color",
        flavor .. ": \"castbar color\" ranks " .. tostring(castbarColor[1] and castbarColor[1].label) .. " first")
end

if #failures > 0 then
    error("search_label_findability_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print(string.format("search_label_findability_smoke: ok (%s %s, %d uniquely named options in the first %d)",
    flavor, locale, tested, PALETTE))
