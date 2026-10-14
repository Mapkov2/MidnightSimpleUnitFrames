-- Required group text fields fail by name at load on every real client graph.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local consumer = "MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Text.lua"
local fields = {
    FormatValue = "MSUF_UF_Text_Format.lua",
    FormatPercentValue = "MSUF_UF_Text_Format.lua",
    FormatHealthString = "MSUF_UF_Text_Format.lua",
    FormatPowerString = "MSUF_UF_Text_Format.lua",
    TruncateName = "MSUF_UF_Text_Runtime.lua",
    PercentFromValues = "MSUF_UF_Text_Runtime.lua",
    MissingHealthFromValues = "MSUF_UF_Text_Runtime.lua",
}
local omissions = 0
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor)
    local load = world.LoadFile
    local ready = false
    function world:LoadFile(path, addon, namespace)
        if path == root .. "/" .. consumer then
            assert(self.env.MSUF_NS == namespace, "required public namespace must own the actual module")
            for name, owner in pairs(fields) do
                local fn = namespace.UFText[name]
                assert(type(fn) == "function", flavor .. ": provider not ready before group text: " .. name)
                assert(debug.getinfo(fn, "S").source:find(owner, 1, true), "fixture substituted " .. name)
            end
            ready = true
            path = arg[2] or path
        end
        return load(self, path, addon, namespace)
    end
    world:Boot()
    assert(not world:FirstFailure(), flavor .. ": client graph failed to boot")
    assert(ready, flavor .. ": graph never loaded group text")
    local Text = world.core.UFText
    local path = arg[2] or root .. "/" .. consumer
    local requireOwner = world.core.Require
    local requires = 0
    world.core.Require = function(name, file)
        assert(name == "MSUF_NS" and file == "GroupFrames/MSUF_GroupFrames_DB_Text.lua", "wrong dependency owner")
        requires = requires + 1
        return requireOwner(name, file)
    end
    local function Missing(name)
        local ok, problem = load(world, path, "MidnightSimpleUnitFrames", world.core)
        assert(not ok and tostring(problem):find(name, 1, true)
            and tostring(problem):find("GroupFrames/MSUF_GroupFrames_DB_Text.lua", 1, true),
            flavor .. ": missing " .. name .. " did not raise a named load-time error: " .. tostring(problem))
        omissions = omissions + 1
    end
    world.core.UFText = nil
    Missing("UFText")
    world.core.UFText = Text
    for name in pairs(fields) do
        local fn = Text[name]
        for _, invalid in ipairs({ {}, { false }, { {} }, { 42 } }) do
            Text[name] = invalid[1]
            Missing("UFText." .. name)
        end
        Text[name] = fn
    end
    world.env.MSUF_NS = nil
    Missing("MSUF_NS")
    world.env.MSUF_NS = world.core
    assert(requires == 30, "consumer bypassed named public namespace resolution")
    world.core.Require = requireOwner
    assert(load(world, root .. "/" .. consumer, "MidnightSimpleUnitFrames", world.core))
end
print("group_text_required_helpers_smoke: ok (5 real client load orders, " .. omissions .. " named dependency counterexamples)")
