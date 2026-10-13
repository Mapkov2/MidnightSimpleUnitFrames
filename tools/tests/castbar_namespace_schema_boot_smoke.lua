-- Boot the real graph and preserve the schema across namespace publication.
local root = assert(arg[1], "repository root required")
local flavor = assert(arg[2], "client flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local load = world.LoadFile
local schema, published, namespace

function world:LoadFile(path, addon, ns)
    local publicAPI = path:match("/MSUF_Castbars_PublicAPI%.lua$")
    if publicAPI then schema = ns.Castbars.UNIT_CASTBAR end
    local ok, message = load(self, path, addon, ns)
    if publicAPI then
        published = ns.Castbars.UNIT_CASTBAR
        namespace = ns.Castbars
    end
    return ok, message
end

world:Boot()
assert(type(schema) == "table", "shared castbar schema did not load before publication")
assert(published == schema, "namespace publication replaced the shared castbar schema")
for _, unit in ipairs({ "player", "target", "focus", "boss", "arena" }) do
    assert(type(schema[unit]) == "table", "shared castbar schema lost " .. unit)
    assert(type(schema[unit].x) == "string" and type(schema[unit].h) == "string", "castbar keys lost for " .. unit)
end
assert(type(namespace.Frames.Get) == "function", "namespace frame provider missing")
assert(type(namespace.Config.Read) == "function", "compiled castbar provider missing")
local failure = world:FirstFailure()
assert(not failure, failure and failure.file .. ": " .. failure.message)
print("PASS castbar namespace/schema full boot: " .. flavor)
