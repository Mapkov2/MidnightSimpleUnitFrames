-- Real cold/warm intent queries and the static/manual-tooltip lifecycle.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", locale = locale })
local M, api = mw.M, mw.M.Search._CoreAPI
local function Ready()
    for _ = 1, 1000 do
        local records = api.GetSearchRecords()
        if #records > 0 and #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("semantic search did not settle")
end
local cases = {
    { "ping system", "general.playerResourcePingEnabled" },
    { "how to ping my health", "general.playerResourcePingEnabled" },
    { "health ping", "general.playerResourcePingEnabled" },
    { "mana ping", "general.playerResourcePingEnabled" },
    { "wie pinge ich meine gesundheit", "general.playerResourcePingEnabled" },
    { "mana pingen", "general.playerResourcePingEnabled" },
    { "show the mana cost of my next spell", "bars.manaUpcomingCost" },
    { "manakosten des nächsten zaubers anzeigen", "bars.manaUpcomingCost" },
    { "five second mana regeneration rule", "bars.manaRegenPause" },
    { "fünf sekunden manaregeneration", "bars.manaRegenPause" },
    { "put a line at 35 percent mana", nil, ".marks.add" },
    { "markierung bei 35 prozent mana", nil, ".marks.add" },
    { "show healer mana in the raid", nil, ".field.healermanaenabled" },
    { "heilermana im raid anzeigen", nil, ".field.healermanaenabled" },
    { "track which healers are out of mana", nil, ".field.healermanaenabled" },
    { "which paladin blessing should each class have", nil, ".field.buffcoverageblessingpriorities" },
    { "welcher paladinsegen für welche klasse", nil, ".field.buffcoverageblessingpriorities" },
    { "prioritize tank blessings", nil, ".field.buffcoverageblessingtank1" },
    { "set boss focus with right click", "boss.rightClickFocusInCombat" },
    { "boss mit rechtsklick als fokus setzen", "boss.rightClickFocusInCombat" },
    { "right click arena enemy during combat", "arena.rightClickFocusInCombat" },
    { "new ping system", "general.playerResourcePingEnabled" },
    { "neues ping system", "general.playerResourcePingEnabled" },
}
local function Matches(row, case)
    local t = row.exactTarget or {}
    return case[2] and t.settingKey == case[2] or case[3] and (t.controlId or ""):sub(-#case[3]) == case[3]
end
local function Find(case, rows)
    for _, row in ipairs(rows or api.GetSearchRecords()) do if Matches(row, case) then return row end end
end
local function Ranked(case)
    for i, row in ipairs(api.SearchPages(case[1])) do
        if i > 6 then break end
        if Matches(row, case) then return row end
    end
end
Ready()
assert(not M.cache.opt_misc and not M.cache.classpower, "cold index opened a feature page")
local available = {}
for _, case in ipairs(cases) do
    if Find(case) then
        available[#available + 1] = case
        assert(Ranked(case), "cold intent missed: " .. case[1])
    end
end
local expected = { Mainline = 18, Forever = 20, Vanilla = 7, TBC = 8, Mists = 10 }
assert(#available == expected[flavor], "semantic corpus availability changed: " .. #available)
if flavor == "Mainline" or flavor == "Forever" then assert(Find(cases[1]), "native ping missing")
else assert(not Find(cases[1]), "native ping exposed on unsupported client") end
if flavor == "Mainline" then assert(not Find(cases[9]), "Classic regeneration exposed on Mainline") end
if flavor ~= "Forever" then assert(not Find(cases[16]), "Forever blessing priorities exposed") end
if flavor == "Vanilla" or flavor == "Forever" then assert(not Find(cases[21]), "arena feature exposed") end

-- Opening a scoped result must not alter the shared cached row or any setting.
M.SetMenuStateValue("gfScope", "party")
local raid = assert(Ranked(cases[13]))
assert(raid.exactTarget.prepareKind == "groupScope" and raid.exactTarget.prepareValue == "raid", "query lost explicit raid scope")
local scopeField = "healerManaEnabled"
local party, raidDB = mw.core.GF.GetConf("party"), mw.core.GF.GetConf("raid")
local oldParty, oldRaid = rawget(party, scopeField), rawget(raidDB, scopeField)
assert(api.OpenSearchTarget(raid.key, raid.label, cases[13][1], nil, raid.route, raid.exactTarget))
Ready()
assert(M.gfScope == "raid", "raid query opened another group scope")
assert(rawget(party, scopeField) == oldParty and rawget(raidDB, scopeField) == oldRaid, "search changed healer settings")
M.SetMenuStateValue("gfScope", "party")
local generic = assert(Ranked({ "healer mana", nil, ".field.healermanaenabled" }))
assert(api.OpenSearchTarget(generic.key, generic.label, "healer mana", nil, generic.route, generic.exactTarget))
Ready()
assert(M.gfScope == "party", "scoped query contaminated the generic cached result")

for _, case in ipairs(available) do
    local row = assert(Ranked(case), "warm intent missed: " .. case[1])
    assert(api.OpenSearchTarget(row.key, row.label, case[1], nil, row.route, row.exactTarget), "intent did not open: " .. case[1])
    Ready()
    assert(Ranked(case), "page visit lost intent: " .. case[1])
end

-- Tooltip before and after registration, without executing dynamic hover code.
local widget = mw.env.CreateFrame("Frame", nil, M.frame)
local calls = 0
M.AddTooltip(widget, "Static diagnostic title", "uniquedescriptionneedle", { hook = true })
M.RegisterSearchWidget(widget, { pageKey = "opt_misc", label = "Diagnostic choice", kind = "dropdown",
    values = { "firstoptionneedle", "lateoptionneedle" }, keywords = "stablekeywordneedle" })
Ready()
assert(#api.SearchPages("uniquedescriptionneedle") > 0, "tooltip before registration lost")
M.AddTooltip(widget, "Static diagnostic title", string.rep("long prose ", 150) .. " truncatedtailneedle", { hook = true })
Ready()
assert(#api.SearchPages("uniquedescriptionneedle") == 0, "late tooltip left a cached description")
for _, q in ipairs({ "lateoptionneedle", "stablekeywordneedle" }) do
    assert(#api.SearchPages(q) > 0, "long tooltip displaced choice/keyword: " .. q)
end
assert(#api.SearchPages("truncatedtailneedle") == 0, "description quota was not applied")
M.AddTooltip(widget, function() calls = calls + 1 end, function() calls = calls + 1 end, { hook = true })
Ready()
assert(calls == 0, "search executed dynamic tooltip callbacks")
M.AddTooltip(widget, "Auto help", "autohelpfeedbackneedle", { hook = true, autoHelp = true })
Ready()
assert(#api.SearchPages("autohelpfeedbackneedle") == 0, "automatic help fed back into search")
print("search_semantic_context_smoke " .. flavor .. " " .. locale .. ": " .. #available .. " cold/warm intents, scope and tooltip lifecycle passed")
