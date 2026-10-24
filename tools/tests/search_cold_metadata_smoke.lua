-- Real cold search: dropdown choices, explicit aliases and help on unopened pages.
local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M = mw.M
assert(not M.cache.uf_player, "target page was already warm")
local cases = { { "camelot", "Round Level Badge" }, { "medallion", "Round Level Badge" } }
for _, case in ipairs(cases) do
    local found
    for _, row in ipairs(M.Search._CoreAPI.SearchPages(case[1])) do
        if row.key == "uf_player" and row.label == case[2] then found = row break end
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
for _, case in ipairs(cases) do
    local found
    for _, row in ipairs(M.Search._CoreAPI.SearchPages(case[1])) do
        if row.key == "uf_player" and row.label == case[2] then found = row break end
    end
    assert(found, "warming the page lost " .. case[1])
end
print("search_cold_metadata_smoke " .. flavor .. ": cold choices, keywords and help found; warm search retained")
