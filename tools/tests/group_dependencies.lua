-- Hard group dependencies for narrow fixtures; text comes from the real core graph.
return function(namespace, root)
    root = assert(root, "group fixture repository root required"):gsub("\\", "/"):gsub("/$", "")
    dofile(root .. "/tools/tests/group_text_fixture.lua")(namespace, root)
    _G.MSUF_NS = namespace
    -- The shipped Kernel API (Bootstrap's export policy and registry, then Require); a
    -- harness export stub that keeps no registry is replaced, so required providers
    -- resolve exactly as in the client.
    assert(loadfile(root .. "/tools/tests/require_fixture.lua"))().InstallKernel(root, namespace, _G, loadfile, true)
    namespace.ExportPublic("MSUF_PixelLayoutRegion", function(region, policy, ...)
        if type(policy) == "string" then return region[policy](region, ...) end
        return region
    end)
    -- The group files bind their core providers when they load. A provider this
    -- narrow fixture does not load (fonts, textures, media, profile defaults) gets
    -- a forwarder that raises naming the provider if a smoke ever uses it unloaded.
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    RequireFixture.DeferRequiredIn(root, namespace, "GroupFrames/")
    RequireFixture.DeferRequiredIn(root, namespace, "Engine/Group/")
end
