-- Observe executed exports separately at core and Options load boundaries.
local root, flavor = assert(arg[1]), assert(arg[2])
local World = assert(loadfile(root .. '/tools/tests/client_world.lua'))()
local Corpus = assert(loadfile(root .. '/tools/profile_corpus_golden.lua'))()
local world = Corpus.NewWorld(root, flavor, 'Namespace-Realm')
Corpus.Login(world, {})
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
end
for _, phase in ipairs({ 'core', 'Options' }) do
    local addon = phase == 'core' and 'MidnightSimpleUnitFrames' or 'MidnightSimpleUnitFrames_Options'
    local toc = phase == 'core' and World.CoreTOC(suffix) or World.OptionsTOC(suffix)
    local paths = World.Graph(root, toc, world.env.GetLocale(), gameType)
    if phase ~= 'core' then world:LoadGraph(addon, paths, world.options) end
    for _, path in ipairs(paths) do print('FILE\t' .. phase .. '\t' .. path:sub(#root + 2)) end
    local failure = world:FirstFailure()
    assert(not failure, failure and (failure.file .. ': ' .. failure.message))
    Snapshot(phase)
end
