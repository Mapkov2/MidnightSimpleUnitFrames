-- A moved helper must remain lexical; unknown-global stubs must not mask it.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", beforeOptions = function(world)
    local meta = getmetatable(world.env)
    local lookup = meta.__index
    meta.__index = function(env, key)
        assert(key ~= "ResetButton" and key ~= "HideInlineSwatch", "moved helper escaped its lexical handoff: " .. key)
        return lookup(env, key)
    end
end })
local M = mw.M
for _, unit in ipairs({ "player", "target" }) do
    local key = "uf_" .. unit
    assert(mw:Select(key))
    local entry = M.cache[key]
    local ctx = M.CreateContext(key, entry.wrapper, entry)
    for index = 1, 4 do
        for _, tool in ipairs({ "filters", "layout", "appearance", "effect", "behavior", "setup", "whitelist" }) do
            M.BuildAuras3CompactCustomWorkspace(ctx, M.Widgets.PageBuilder(ctx), unit, index, tool)
        end
    end
end
print("PASS Custom Aura handoff " .. flavor .. ": all containers and tools use lexical helpers")
