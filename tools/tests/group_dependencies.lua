-- Hard group dependencies for narrow fixtures that do not boot the Kernel.
return function(namespace)
    namespace.Require = namespace.Require or function(name)
        local value = _G[name]
        assert(type(value) == "function" or type(value) == "table", "fixture lacks " .. tostring(name))
        return value
    end
    -- MSUF_UF_Text_Runtime.lua's display-name reader with no resolver installed:
    -- the plain UnitName read (the fixture's own UnitName, looked up per call).
    namespace.UFText = namespace.UFText or {}
    namespace.UFText.ReadDisplayName = namespace.UFText.ReadDisplayName
        or function(unit) return _G.UnitName(unit) end
    _G.MSUF_PixelLayoutRegion = function(region, policy, ...)
        if type(policy) == "string" then return region[policy](region, ...) end
        return region
    end
end
