-- Test wiring for earlier synthetic A3 fixtures. Production has explicit roles;
-- fixture private names route to those same records, without copying behavior.
local Fixture = {}
local layouts = {}
local function Layout(root)
    if layouts[root] then return layouts[root] end
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local layout = { roles = {}, helpers = {} }
    for role in source:gmatch("Runtime%.(%w+) = Runtime%.%w+ or {}") do
        layout.roles[#layout.roles + 1] = role
        local path = root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_" .. role .. ".lua"
        local module = assert(io.open(path, "rb"))
        local text = module:read("*a")
        module:close()
        for name in text:gmatch(role .. "%.([%w_]+)%s*=") do layout.helpers["_" .. name] = { role, name } end
        for name in text:gmatch("function " .. role .. "%.([%w_]+)%s*%(") do layout.helpers["_" .. name] = { role, name } end
    end
    layouts[root] = layout
    return layout
end

function Fixture.Attach(root, A3)
    if A3._fixtureRuntimeRoles then return A3 end
    local layout = Layout(root)
    A3.Runtime = A3.Runtime or {}
    for _, role in ipairs(layout.roles) do A3.Runtime[role] = A3.Runtime[role] or {} end
    for key, location in pairs(layout.helpers) do
        local value = rawget(A3, key)
        if value ~= nil then A3.Runtime[location[1]][location[2]] = value rawset(A3, key, nil) end
    end
    local meta = getmetatable(A3) or {}
    local previousIndex, previousNewIndex = meta.__index, meta.__newindex
    meta.__index = function(self, key)
        local location = layout.helpers[key]
        if location then return self.Runtime[location[1]][location[2]] end
        if type(previousIndex) == "function" then return previousIndex(self, key) end
        if type(previousIndex) == "table" then return previousIndex[key] end
    end
    meta.__newindex = function(self, key, value)
        local location = layout.helpers[key]
        if location then self.Runtime[location[1]][location[2]] = value return end
        if previousNewIndex then previousNewIndex(self, key, value) else rawset(self, key, value) end
    end
    setmetatable(A3, meta)
    rawset(A3, "_fixtureRuntimeRoles", true)
    return A3
end

function Fixture.Prepare(root, namespace)
    local factories = namespace.Auras3RuntimeFactories
    if not factories then return end
    for _, role in ipairs({ "WorldTransition", "IdentityRefresh", "IdentityTopology" }) do
        if not factories[role] then
            assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_" .. role .. ".lua"))("MSUF", namespace)
        end
    end
    local pending = {}
    for name, factory in pairs(factories) do if type(factory) == "function" then pending[name] = factory end end
    for name, factory in pairs(pending) do
        factories[name] = function(addon, MSUF, A3, UF, export, dependencies)
            Fixture.Attach(root, A3)
            local topology, world
            if name == "IdentityEvents" and not dependencies.WorldTransition then
                world = pending.WorldTransition(addon, MSUF, A3, UF, export, dependencies)
                dependencies.WorldTransition = world
                pending.IdentityRefresh(addon, MSUF, A3, UF, export, dependencies)
                topology = pending.IdentityTopology(addon, MSUF, A3, UF, export, dependencies)
                dependencies.IdentityTopology = topology
            end
            if name == "Facade" and not dependencies.IdentityTopology then
                dependencies.IdentityTopology = dependencies.IdentityEvents
            end
            local result = factory(addon, MSUF, A3, UF, export, dependencies)
            if topology then
                topology.Bind({ OnEvent = result.OnEvent })
                result.DrainDirectIdentityEventTopologyBatch = topology.DrainDirectIdentityEventTopologyBatch
                result.Bind = world.Bind
            end
            return result
        end
    end
end

return Fixture
