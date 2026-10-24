-- Real shipped graph and the existing schema projection capture, without
-- slicing or matching product source. Build every registered page and section.
local root, flavor = assert(arg[1]), assert(arg[2])
local initial = assert(loadfile(root .. "/tools/menu_schema_initial.lua"))()(root, flavor)
local mw, M = initial.world, initial.menu
local pages, failures, projected = initial.pages, initial.failures, initial.count
local expected = assert(tonumber(arg[3]), "exact schema projection count required")
assert(projected == expected, string.format("schema projection count: expected %d, built %d", expected, projected))

-- Query and navigate the exact result, as a real search result click does.
local hit
M.Search._CoreAPI.OpenSearchResults("player power bar height")
for _ = 1, 30 do
    if #mw.world.widgets.timers == 0 then break end
    mw:RunTimers(1000)
end
assert(not M.searchResultsPending, "search did not finish its deferred build")
for _, row in ipairs(M.searchResults or {}) do
    if row.exactTarget and row.exactTarget.settingKey == "player.powerBarHeight" then hit = row break end
end
assert(hit, "player power bar height query found no setting row")
assert(mw:Select("opt_misc"), "could not leave search target page")
local selected, _, exact = M.Search.OpenTarget(hit.key, hit.label, hit.anchorFallback or hit.label,
    hit.anchor, hit.route, hit.exactTarget)
mw:RunTimers()
local record, widget = M.RuntimeControlCatalog.ResolveExactTarget(hit.key, hit.exactTarget)
assert(selected == true and exact == true and widget and record, "search did not reach exact control")
assert(M.activeKey == hit.key, "search selected the wrong page")
local anchor = record.anchor or widget
while anchor do
    assert(anchor:IsShown(), "search control has a hidden ancestor")
    anchor = anchor:GetParent()
end
assert(#failures == 0, flavor .. " page build failures:\n" .. table.concat(failures, "\n"))
print(string.format("menu: %s, %d pages / %d projected controls; query and exact navigation passed", flavor, #pages, projected))
