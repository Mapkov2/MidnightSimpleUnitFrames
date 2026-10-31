-- Actual cold search and cached navigation; no page builders run to seed search.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = locale })
local M, failures, checked = mw.M, {}, 0
assert(mw.core.FinalizeLocale() == locale)
local api, index = M.Search._CoreAPI, M.Search.StaticIndex
local function Check(ok, message)
    checked = checked + 1
    if not ok then failures[#failures + 1] = message end
end
local function Ready()
    api.GetSearchRecords()
    for _ = 1, 1000 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search timers did not drain")
end
local function Status(row, page)
    local section = index.TargetField(row, "sectionId")
    local id = index.TargetField(row, "controlId") or ""
    return (not page or row.key == page) and
        (section == "status_icons" or section == "sicons" or id:find(".status.", 1, true))
end
local function Find(query, page, limit)
    Ready()
    local rows = api.SearchPages(query)
    for i = 1, math.min(limit or 5, #rows) do
        if Status(rows[i], page) then return rows[i] end
    end
    return nil, rows[1] and (rows[1].key .. "/" .. rows[1].label) or "empty"
end
Ready()
local cold = {
    { "status icons" }, { "statusicons" }, { "Status-Icons" },
    { "where are status icons" }, { "where are player status icons", "uf_player" },
    { "where are party status icons", "gf_indicators" },
    { "player status icons", "uf_player" }, { "target status icons", "uf_target" },
    { "party status icons", "gf_indicators" }, { "raid status icons", "gf_indicators" },
    { "combat icon", "uf_player" }, { "resting icon", "uf_player" },
    { "leader icon", "uf_player" }, { "assist icon", "uf_player" },
    { "ready check", "gf_indicators" }, { "role icon", "gf_indicators" },
    { M.Tr("Assist Icon"), "uf_player" }, { M.Tr("Rested (player only)"), "uf_player" },
}
if locale == "deDE" then
    for _, case in ipairs({ { "Statussymbole" }, { "Status Symbole" }, { "Kampfsymbol", "uf_player" },
        { "Ruhesymbol", "uf_player" }, { "Gruppenleiter", "uf_player" }, { "Rollensymbol", "gf_indicators" } }) do
        cold[#cold + 1] = case
    end
end
for _, case in ipairs(cold) do
    local found, first = Find(case[1], case[2])
    Check(found ~= nil, "cold query " .. case[1] .. " -> " .. tostring(first))
end
Check(not M.cache.uf_player and not M.cache.gf_indicators, "cold search built a destination page")
local routes = {
    { "player assist icon", "uf_player", "player", "assist" },
    { "player assist icon size", "uf_player", "player", "assist" },
    { "player combat icon size", "uf_player", "player", "statusCombat" },
    { "target race text color", "uf_target", "target", "raceText" },
    { "player combat icon", "uf_player", "player", "statusCombat" },
    { "player resting icon", "uf_player", "player", "statusResting" },
    { "target race text", "uf_target", "target", "raceText" },
    { "target class text", "uf_target", "target", "classText" },
    { "boss number", "uf_boss", "boss", "bossNumber" },
    { M.Tr("Player") .. " " .. M.Tr("Assist Icon"), "uf_player", "player", "assist" },
}
for _, case in ipairs(routes) do
    if not M.SupportsUnitPage(case[2]) then
        Check(Find(case[1], case[2]) == nil, "unsupported unit found: " .. case[2])
    else
    for pass = 1, 2 do
        M.unitStatusSelection = M.unitStatusSelection or {}
        M.unitStatusSelection[case[3]] = "leader"
        local row = Find(case[1], case[2])
        Check(row ~= nil, "route query " .. case[1] .. " pass " .. pass)
        if row then
            local opened, anchor, exact = api.OpenSearchTarget(row.key, case[1], row.label, nil, row.route, row.exactTarget)
            Ready()
            Check(opened and anchor and exact, "exact navigation " .. case[1] .. " pass " .. pass)
            Check(M.unitStatusSelection[case[3]] == case[4], "wrong selection " .. case[1] .. ": " ..
                tostring(M.unitStatusSelection[case[3]]))
        end
    end
    end
end
for _, failure in ipairs(failures) do print("FAIL: " .. failure) end
assert(#failures == 0, #failures .. " search regressions")
print("search_status_findability_smoke " .. flavor .. " " .. locale .. ": " .. checked .. " checks")
