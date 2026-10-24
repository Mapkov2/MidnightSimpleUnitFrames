-- A test-only view for smokes written before namespace-only publication.
-- Never install this metatable on the client's environment: shipped code must
-- continue seeing the real globals and the real Require/Optional policy.
return function(world)
    local env, core = world.env, world.core
    return setmetatable({}, {
        __index = function(_, name)
            local live = rawget(env, name)
            if live ~= nil then return live end
            local public = core.PublicGlobals
            local value = public and public[name]
            if value ~= nil then return value end
            return env[name]
        end,
        __newindex = function(_, name, value)
            if core.PublicGlobals and core.PublicGlobals[name] ~= nil then
                core.ExportPublic(name, value)
            else
                env[name] = value
            end
        end,
    })
end
