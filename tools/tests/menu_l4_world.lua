-- Replay just this lane's owned sources against the current full client graph.
return function(root, flavor, options, baseline)
    local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    options = options or {}
    local beforeCore = options.beforeCore
    options.beforeCore = function(world)
        if beforeCore then beforeCore(world) end
        if not baseline then return end
        local load = world.LoadFile
        function world:LoadFile(path, addon, ns)
            local relative = path:sub(#root + 2)
            local handle = io.open(baseline .. "/" .. relative, "rb")
            if handle then handle:close(); path = baseline .. "/" .. relative end
            return load(self, path, addon, ns)
        end
    end
    return MW.Open(root, flavor, options)
end
