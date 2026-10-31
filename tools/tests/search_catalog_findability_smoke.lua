-- Every uniquely named cold catalog entry must be visible in the first results.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local mw = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open(root, flavor, { page = "home", locale = locale })
assert(mw.core.FinalizeLocale() == locale)
local M, api = mw.M, mw.M.Search._CoreAPI
api.GetSearchRecords()
for pass = 1, 1000 do
    if #mw.world.widgets.timers == 0 then break end
    mw:RunTimers(1000)
    assert(pass < 1000, "cold catalog did not settle")
end
local names, records, checked, failures = {}, api.GetSearchRecords(), 0, {}
for _, row in ipairs(records) do
    local name = M.Search.Text.NormalizeSearchText(row.label)
    if name ~= "" then names[name] = (names[name] or 0) + 1 end
end
for _, expected in ipairs(records) do
    local name = M.Search.Text.NormalizeSearchText(expected.label)
    if names[name] == 1 and #name >= 2 then
        local found = false
        for rank, row in ipairs(api.SearchPages(expected.label)) do
            if row == expected then found = rank <= 6 break end
        end
        checked = checked + 1
        if not found then failures[#failures + 1] = expected.key .. "/" .. expected.label end
    end
end
assert(checked > 100, "cold catalog audit did not cover the real menu")
for _, message in ipairs(failures) do print("FAIL: exact catalog name " .. message) end
assert(#failures == 0, #failures .. " catalog labels absent from first six results")
assert(not M.cache.uf_player and not M.cache.gf_indicators, "catalog queries built a destination")
print("search_catalog_findability_smoke " .. flavor .. " " .. locale .. ": " .. checked .. " unique catalog names in first six")
