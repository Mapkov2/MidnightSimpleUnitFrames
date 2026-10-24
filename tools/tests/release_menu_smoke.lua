-- Real shipped graph and the existing schema projection capture, without
-- slicing or matching product source. Build every registered page and section.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local capture = assert(loadfile(root .. "/tools/menu_schema_capture.lua"))()
local watched = false
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true,
    beforeOptions = function(world)
        local load = world.LoadFile
        function world:LoadFile(path, ...)
            local ok, message = load(self, path, ...)
            if ok and not watched and self.core.MSUF2 and self.core.MSUF2.ControlSchema then
                __MSUF_WatchSchema(self.core.MSUF2)
                watched = true
            end
            return ok, message
        end
    end })
local M = mw.M
local pages = {}
for key in pairs(M.pages) do pages[#pages + 1] = key end
table.sort(pages)
local failures = {}
for _, key in ipairs(pages) do
    local ok, err = pcall(function()
        assert(mw:Select(key), "selection refused")
        local entry = assert(M.cache[key], "selected page built no entry")
        -- Expanding one section may create more nested lazy sections.
        for _ = 1, 3 do
            for _, section in pairs(entry.sections or {}) do
                local disclosure = section._msuf2CollapsibleEntry
                if disclosure then disclosure.SetOpenImmediate(true) end
            end
            mw:RunTimers()
        end
        assert(not entry._msuf2BuildIncomplete, "page did not finish")
    end)
    if not ok then failures[#failures + 1] = key .. ": " .. tostring(err) end
end
assert(#pages > 20, "page registry unexpectedly small")
capture.Start(M, M.RuntimeControlCatalog)
local projected = 0
for _ in pairs(capture.Data()) do projected = projected + 1 end
assert(projected > 200, "schema projection missed the built controls")

-- Query and navigate the exact result, as a real search result click does.
local hit
for _, row in ipairs(M.Search._CoreAPI.SearchPages("player power bar height")) do
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
