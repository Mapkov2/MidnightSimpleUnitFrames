-- menu_named_page_interfaces.lua <root> <client> [ownedBaseline]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local captured = {}
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        local which = path:match("MSUF_Menu2_UnitSections.lua$") and "Layout"
            or path:match("MSUF_Menu2_UnitFrameVisuals.lua$") and "Castbar"
        if which then
            local factories = which == "Layout" and world.core.MSUF2.UnitSectionFactories or world.core.MSUF2.UnitVisualFactories
            local factory = factories[which]
            factories[which] = function(...)
                local prior = captured[which]
                captured[which] = { factory = factory, args = { ... }, calls = (prior and prior.calls or 0) + 1 }
                return factory(...)
            end
        end
        return load(self, path, addon, ns)
    end
end }, arg[3])
local count = 0
for _, name in ipairs({ "Layout", "Castbar" }) do
    local entry = assert(captured[name], name .. " factory was not bound")
    assert(#entry.args <= 5 and entry.args[1].GetGeneral, name .. " still takes a positional context list")
    for i, domain in ipairs(entry.args) do
        for key, value in pairs(domain) do
            domain[key] = nil
            local ok, message = pcall(entry.factory, unpack(entry.args))
            domain[key] = value
            assert(not ok and tostring(message):find(key, 1, true), name .. " did not reject missing named field " .. key)
            count = count + 1
        end
    end
    assert(entry.calls == 1, name .. " was rebound during page build")
end
mw:Select("uf_target")
mw:Select("uf_player")
assert(captured.Layout.calls == 1 and captured.Castbar.calls == 1, "named interfaces were allocated per build")
print("PASS named page interfaces " .. flavor .. ": " .. count .. " required fields; one binding per owner")
