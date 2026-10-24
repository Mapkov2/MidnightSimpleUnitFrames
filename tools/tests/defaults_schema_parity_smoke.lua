-- Every factory/repair default, owning root, type and presence on all clients.
local root, flavor = assert(arg[1]), assert(arg[2])
local codeRoot = arg[3] or root
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local source = assert(loadfile(root .. "/tools/fixtures/defaults/schema.lua"))()
local function Read(profile, path)
    local value = profile
    for i = 1, #path do
        if type(value) ~= "table" then return nil end
        value = value[path[i]]
    end
    return value
end
local paths = {}
for _, row in ipairs(source.fields) do
    local id = H.Literal(row.path)
    assert(not paths[id], "duplicate schema path: " .. id)
    assert(row.scope == row.path[1], "schema scope differs: " .. id)
    paths[id] = true
end
for _, context in ipairs({ "factory", "repair" }) do
    local world = C.NewWorld(codeRoot, flavor, "Char01-Realm01")
    local saved = context == "factory" and {} or { MSUF_GlobalDB = {
        profiles = { Default = { player = {}, _msufProfileSchema = 600 } },
        char = { ["Char01-Realm01"] = { activeProfile = "Default" } }, global = {} } }
    C.Login(world, saved)
    local schema = assert(world.core.DefaultsSchema, "no canonical runtime defaults schema")
    assert(schema.Version == source.version, "schema generation version differs")
    local ledger = world.core.ProfileMigrations.Ledger
    assert(ledger[1][1] == "legacy_bar_names" and ledger[2][1] == "dispel_priority"
        and ledger[3][1] == "classic_sparse_aura_owners", "legacy ledger order changed")
    assert(ledger[#ledger][1] == "sparse_persistence_defaults" and ledger[#ledger][2] == schema.FillMenuDefaults,
        "sparse schema ledger step is absent or out of order")
    local fresh = {}
    world.core.ProfileMigrations.Apply(fresh)
    assert(next(fresh) == nil, "schema defaults/stamp preceded fresh factory seeding")
    for index, row in ipairs(source.fields) do
        local expected = source.clients[flavor][context][index] or row[context]
        local value = Read(world.env.MSUF_DB, row.path)
        assert(type(value) == expected[1], context .. ": schema type/presence differs at " .. H.Literal(row.path))
        assert(H.Literal(value == nil and {} or { value }) == H.Literal(expected[2] == nil and {} or { expected[2] }),
            context .. ": schema value differs at " .. H.Literal(row.path))
    end
    local function Covered(value, path)
        if type(value) ~= "table" or next(value) == nil then
            assert(paths[H.Literal(path)], "runtime default missing from schema: " .. H.Literal(path))
            return
        end
        for key, item in pairs(value) do
            local child = C.Copy(path)
            child[#child + 1] = key
            Covered(item, child)
        end
    end
    Covered(world.env.MSUF_DB, {})
    for id, stage in pairs(source.stages) do
        assert(stage.scope == "general", "literal stage scope differs")
        local generated = assert(schema.SeedStages[id], "generated literal stage absent")
        for key, value in pairs(stage.fields) do
            assert(type(generated[key]) == value[1] and generated[key] == value[2], "literal stage value/type differs")
        end
        for key in pairs(generated) do assert(stage.fields[key], "undeclared literal stage field") end
    end
    assert(#schema.PersistenceEntries == #source.persistence, "persistence generation differs")
    for i, policy in ipairs(source.persistence) do
        local row, runtime = source.fields[policy.field], schema.PersistenceEntries[i]
        local expected = source.clients[flavor][policy.context][policy.field] or row[policy.context]
        local normalizerOnly = policy.certificate == "all_profile_preview_marker_fill"
        assert(policy.certificate == "all_profile_menu_fill" or normalizerOnly, "uncertified persistence entry")
        assert(runtime.normalizerOnly == (normalizerOnly or nil), "persistence fill boundary differs")
        assert(not normalizerOnly or row.scope == "general" and row.path[2] == "_msufPreviewDragHintExperienced"
            and expected[1] == "boolean" and expected[2] == true, "invalid preview marker certificate")
        assert(#row.path == 2 and runtime.scope == row.scope and runtime.key == row.path[2], "persistence path differs")
        assert(runtime.kind == expected[1] and runtime.default == expected[2], "persistence default/type differs")
    end
    if context == "factory" then
        assert(world.env.MSUF_ResetProfile(), "factory runtime reset failed")
        assert(H.Literal(world.env.MSUF_DB) == H.Literal(source.factoryContexts.clients[flavor].expectedRuntime),
            "lazy factory/runtime defaults differ from the canonical context")
    end
    print("defaults_schema_parity_smoke: " .. flavor .. " " .. context .. " " .. #source.fields .. " fields ok")
end
