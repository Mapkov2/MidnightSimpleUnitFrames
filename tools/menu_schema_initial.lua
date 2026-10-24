-- Real core/Options initial declaration projection, shared with release checks.
return function(root, flavor, directory)
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local capture = assert(loadfile(root .. "/tools/menu_schema_capture.lua"))()
if directory then capture.Stream(directory, flavor .. "-initial") end
capture.InitialObservation()
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
local projected = capture.Count()
return { world = mw, menu = M, pages = pages, failures = failures, count = projected, capture = capture }
end
