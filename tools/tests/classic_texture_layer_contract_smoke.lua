local root = assert(arg[1])
local menu = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
-- Every client loads the one unified page; the retired Classic copy must stay gone.
assert(io.open(menu .. "Pages/MSUF_Menu2_UnitTextureLayer_Classic.lua", "rb") == nil,
    "retired Classic Texture Layer page is back")
do
    local ns = { MSUF2 = {}, ExportPublic = function(name, value) _G[name] = value end }
    assert(loadfile(menu .. "MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", ns)
    local M = ns.MSUF2
    local section
    M.UnitPage = { RegisterSection = function(spec) section = spec end }
    local UP = M.UnitPage
    for _, name in ipairs({ "ReadBool", "SetBool", "ReadNumber", "SetNumber", "SetString",
        "SetControlEnabled", "GetConf", "ReviewedMeta" }) do
        UP[name] = function() return {} end
    end
    assert(UP.Call == nil, "removed wrapper must not exist in fixture")
    assert(loadfile(menu .. "Pages/MSUF_Menu2_UnitTextureLayer.lua"))("MidnightSimpleUnitFrames_Options", ns)
    assert(section and section.id == "texture_layer", "Texture Layer section was not registered")
    -- Stop exactly where real UI construction starts. The regression returned
    -- silently before this boundary solely because the unused UP.Call was absent.
    local reached = {}
    local builder = { CollapsibleSection = function(_, id)
        assert(id == "texture_layer")
        error(reached)
    end }
    local ok, err = pcall(section.build, { width = 720 }, builder, "player")
    assert(not ok and err == reached, "Texture Layer did not reach UI construction: " .. tostring(err))
    UP.GetConf = nil
    ok, err = pcall(section.build, {}, builder, "player")
    assert(not ok and tostring(err):find("Texture Layer requires the UnitPage settings API", 1, true),
        "missing required settings API must fail visibly")
end
print("PASS Texture Layer: unified page builds without removed wrapper; missing required API stays visible")
