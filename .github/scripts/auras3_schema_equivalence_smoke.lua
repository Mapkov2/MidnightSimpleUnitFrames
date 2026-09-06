-- Compare concrete schema values and shared-reference topology with a frozen source.
local root = assert(arg[1], "candidate source root required")
local baseline = assert(arg[2], "frozen baseline root required")
local function ReadSchemas(source)
    local ns, a3 = {}, {}
    assert(loadfile(source .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Schema.lua"))("MidnightSimpleUnitFrames", ns)
    local runtime = ns.Auras3RuntimeFactories.Schema("MidnightSimpleUnitFrames", ns, a3, {}, function() end)
    assert(a3.UnitLaneSpecs == runtime.LANE_SPECS, "runtime lane schema must remain shared")
    assert(a3.UnitStyleSharedLayoutKeys == runtime.STYLE_SHARED_LAYOUT_KEYS, "style ownership must remain shared")
    assert(loadfile(source .. "/MidnightSimpleUnitFrames/Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua"))("MidnightSimpleUnitFrames", ns)
    local menu = ns.Auras3MenuModelFactories.Schema(a3)
    assert(menu.GROUPS == runtime.LANE_SPECS, "menu lane schema must remain shared")
    assert(menu.STYLE_SHARED_LAYOUT_KEYS == runtime.STYLE_SHARED_LAYOUT_KEYS, "menu style ownership must remain shared")
    return { runtime = runtime, public = a3, menu = menu, standalone = ns.Auras3MenuModelFactories.Schema({}) }
end
local seen, reverse, scalarCount, tableCount = {}, {}, 0, 0
local function Equal(a, b, path)
    assert(type(a) == type(b), path .. ": changed type")
    if type(a) ~= "table" then
        assert(a == b, path .. ": changed value " .. tostring(a) .. " -> " .. tostring(b))
        scalarCount = scalarCount + 1
        return
    end
    if seen[a] then
        assert(seen[a] == b, path .. ": lost shared table identity")
        return
    end
    assert(not reverse[b], path .. ": unexpectedly merged independent tables")
    seen[a], reverse[b] = b, a
    tableCount = tableCount + 1
    for key, value in pairs(a) do
        assert(b[key] ~= nil, path .. "." .. tostring(key) .. ": missing")
        Equal(value, b[key], path .. "." .. tostring(key))
    end
    for key in pairs(b) do assert(a[key] ~= nil, path .. "." .. tostring(key) .. ": added") end
end
Equal(ReadSchemas(baseline), ReadSchemas(root), "schema")
print("PASS schema equivalence: " .. scalarCount .. " scalar values, " .. tableCount
    .. " tables, shared identity, native menu and standalone fallback")
