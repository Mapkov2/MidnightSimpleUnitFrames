-- Observe executed exports separately at core and Options load boundaries.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/+$", ""), assert(arg[2])
local World = assert(loadfile(root .. '/tools/tests/client_world.lua'))()
local Corpus = assert(loadfile(root .. '/tools/profile_corpus_golden.lua'))()
local owners, seen = {}, {}
local function Record(world, file, phase)
    local values = {}
    for name, value in pairs(world.core.PublicGlobals or {}) do values[name] = value end
    for name, value in pairs(world.env) do
        if type(name) == 'string' and name:match('^MSUF') then values[name] = value end
    end
    for name, value in pairs(values) do
        if value ~= seen[name] then
            seen[name], owners[name] = value, { file = file, phase = phase }
        end
    end
end
local world = Corpus.NewWorld(root, flavor, 'Namespace-Realm', function(w)
    local load = w.LoadFile
    w.LoadFile = function(self, path, addon, ns)
        local ok, message = load(self, path, addon, ns)
        Record(self, path:sub(#root + 2), addon == 'MidnightSimpleUnitFrames' and 'core' or 'Options')
        return ok, message
    end
end)
local beforeLogin = arg[3] and arg[3]:match('^before%-login:(.+)$')
if beforeLogin then
    world.core.ExportPublic(beforeLogin, nil)
    rawset(world.env, beforeLogin, nil)
end
Corpus.Login(world, {})
-- Native event isolation must not let a failed core Require borrow an Options
-- provider from a later snapshot. Ordinary fixture frame errors are separate.
for _, caught in ipairs(world.isolated) do
    assert(not caught.message:find('missing required dependency', 1, true),
        'core login required-provider failure: ' .. caught.message)
end
for name, value in pairs(world.core.Client) do
    if type(value) == 'boolean' then print('CAP\t' .. name .. '\t' .. tostring(value)) end
end
local client = world.client
local suffix = client.tocSuffix or flavor
local gameType = client.isForever and 'camelot' or nil
local function Snapshot(phase)
    local names = {}
    for name in pairs(world.env) do
        if type(name) == 'string' and name:match('^MSUF') then names[name] = true end
    end
    for name in pairs(names) do print('PROVIDER\t' .. phase .. '\t' .. name) end
    Record(world, '<login>', phase)
    local required = {}
    for name in pairs(world.core.PublicGlobals) do required[name] = true end
    for name in pairs(names) do required[name] = true end
    for name in pairs(required) do
        local owner = owners[name] or { file = '<unknown>', phase = phase }
        print(table.concat({ 'REGISTRY', phase, name, type(world.core.Optional(name)), owner.file, owner.phase }, '\t'))
    end
end
for _, phase in ipairs({ 'core', 'Options' }) do
    local addon = phase == 'core' and 'MidnightSimpleUnitFrames' or 'MidnightSimpleUnitFrames_Options'
    local toc = phase == 'core' and World.CoreTOC(suffix) or World.OptionsTOC(suffix)
    local paths = World.Graph(root, toc, world.env.GetLocale(), gameType)
    if phase ~= 'core' then world:LoadGraph(addon, paths, world.options) end
    for _, path in ipairs(paths) do print('FILE\t' .. phase .. '\t' .. path:sub(#root + 2)) end
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ': ' .. failure.message))
    -- Tool-only fault injection: erase an actual provider after its owner has
    -- loaded, while leaving its deferred consumer command unexecuted.
    if arg[3] then
        world.core.ExportPublic(arg[3], nil)
        rawset(world.env, arg[3], nil)
    end
    Snapshot(phase)
end
