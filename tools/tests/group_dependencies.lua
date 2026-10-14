-- Hard group dependencies for narrow fixtures; text comes from the real core graph.
return function(namespace, root)
    root = assert(root, "group fixture repository root required"):gsub("\\", "/"):gsub("/$", "")
    dofile(root .. "/tools/tests/group_text_fixture.lua")(namespace, root)
    _G.MSUF_NS = namespace
    namespace.ExportPublic = namespace.ExportPublic or function(name, value) _G[name] = value end
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", namespace)
    _G.MSUF_PixelLayoutRegion = function(region, policy, ...)
        if type(policy) == "string" then return region[policy](region, ...) end
        return region
    end
end
