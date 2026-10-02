-- Hard group dependencies for narrow fixtures that do not boot the Kernel.
return function(namespace)
    namespace.Require = namespace.Require or function(name)
        local value = _G[name]
        assert(type(value) == "function" or type(value) == "table", "fixture lacks " .. tostring(name))
        return value
    end
    _G.MSUF_PixelLayoutRegion = function(region, policy, ...)
        if type(policy) == "string" then return region[policy](region, ...) end
        return region
    end
end
