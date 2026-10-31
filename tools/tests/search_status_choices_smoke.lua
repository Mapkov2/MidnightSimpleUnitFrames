-- Every choice the current client offers has a cold exact search destination.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = locale })
local M, api = mw.M, mw.M.Search._CoreAPI
assert(mw.core.FinalizeLocale() == locale)
local function Ready()
    api.GetSearchRecords()
    for _ = 1, 1000 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search timers did not drain")
end
Ready()
local byId = {}
for _, row in ipairs(api.GetSearchRecords()) do
    local id = M.Search.StaticIndex.TargetField(row, "controlId")
    if id then byId[id] = row end
end
local count, failures = 0, {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end
for _, target in ipairs({
    { "uf_player", "unitStatusIndicator", "missingIndicator" },
    { "gf_indicators", "groupStatus", "player_roleIcon" },
    { "gf_indicators", "groupStatus", "party_missingIndicator" },
    { "uf_player", "groupStatus", "party_roleIcon" },
}) do
    Check(not M.SupportsSearchTarget(target[1], nil, target[2], target[3]), "invalid target accepted " .. target[3])
end
local legacy = { statusPetHappiness = "pet_happiness", statusPetXP = "pet_xp", statusThreat = "threat" }
local cases = {}
for page in pairs(M.pages) do
    local unit = page:match("^uf_(.+)$")
    if unit and M.SupportsUnitPage(page) then
        for _, choice in ipairs(M.UnitPage.StatusValues(unit)) do
            local id = "menu2." .. page .. ".unit.status.indicator." .. (legacy[choice.value] or choice.value:lower())
            local row = byId[id]
            Check(row ~= nil, "missing allowed choice " .. id)
            if row then
                local query = M.Tr(M.navSubpageLabels[page] or M.UnitPage.UnitTopLabelKey(unit)) .. " " .. M.Tr(choice.text)
                cases[#cases + 1] = { row = row, query = query, unit = unit, value = choice.value }
            end
        end
    end
end
for _, scopeInfo in ipairs(M.GroupPage.SCOPE_VALUES) do
    local scope = scopeInfo.value
    for _, spec in ipairs(M.GroupPage.GF_STATUS_ICON_SPECS) do
        local id = "menu2.gf_indicators.group.status.indicator." .. scope .. "." .. spec.value:lower()
        local row = byId[id]
        if mw.core.Client.SupportsGroupKind(scope) then
            Check(row ~= nil, "missing group choice " .. id)
            if row then cases[#cases + 1] = { row = row, query = M.Tr(scopeInfo.text) .. " " .. M.Tr(spec.text),
                scope = scope, value = spec.value } end
        else
            Check(row == nil, "unsupported group scope leaked " .. id)
        end
    end
end
-- Ranking uses the actual translated labels, before any target is built.
for _, case in ipairs(cases) do
    local found = false
    for rank, row in ipairs(api.SearchPages(case.query)) do
        if row == case.row then found = rank <= 6 break end
    end
    Check(found, "cold label missed " .. case.query)
end
Check(not M.cache.uf_player and not M.cache.gf_indicators, "cold label search constructed a destination")
local function Serialize(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = Serialize(key) .. "=" .. Serialize(value[key]) end
    return "{" .. table.concat(parts, "|") .. "}"
end
local warmed = {}
-- Cold routes build their destination once; cached view changes must preserve
-- the complete profile and reuse that tree while changing only menu selection.
for _, case in ipairs(cases) do
    local row, exact = case.row, case.row.exactTarget
    M.unitStatusSelection = M.unitStatusSelection or {}
    M.unitStatusTabSelection = M.unitStatusTabSelection or {}
    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    if case.unit then
        M.unitStatusSelection[case.unit], M.unitStatusTabSelection[case.unit] = "leader", "advanced"
    else
        M.gfScope, M.gfStatusIconSelection, M.gfStatusIconTabSelection[case.scope] = "party", "roleIcon", "advanced"
    end
    local viewKey = row.key .. ":" .. (case.scope or "")
    local before = warmed[viewKey] and Serialize(mw.env.MSUF_DB)
    local wrapper = warmed[viewKey] and M.cache[row.key].wrapper
    local opened, anchor, matched = api.OpenSearchTarget(row.key, case.query, row.label, nil, nil, exact)
    Ready()
    Check(opened and anchor and matched, "exact route failed " .. exact.controlId)
    if case.unit then
        Check(M.unitStatusSelection[case.unit] == case.value and M.unitStatusTabSelection[case.unit] == "basic",
            "unit selection/tab wrong " .. exact.controlId)
    else
        Check(M.gfScope == case.scope and M.gfStatusIconSelection == case.value
            and M.gfStatusIconTabSelection[case.scope] == "basic", "group selection/tab wrong " .. exact.controlId)
    end
    if before then
        Check(Serialize(mw.env.MSUF_DB) == before, "navigation changed profile " .. exact.controlId)
        Check(M.cache[row.key].wrapper == wrapper, "navigation rebuilt cached page " .. exact.controlId)
    end
    warmed[viewKey] = true
    count = count + 1
end
for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, #failures .. " status choice regressions")
print("search_status_choices_smoke " .. flavor .. " " .. locale .. ": " .. count .. " cold choices and exact destinations")
