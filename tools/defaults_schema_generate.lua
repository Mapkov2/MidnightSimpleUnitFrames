-- Generate portable runtime data from the canonical typed defaults schema.
local root, out = assert(arg[1]), assert(arg[2])
local S = assert(loadfile(root .. "/tools/fixtures/defaults/schema.lua"))()
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local entries, stages = {}, {}
for _, policy in ipairs(S.persistence) do
    local row, value = S.fields[policy.field], S.fields[policy.field][policy.context]
    assert(#row.path == 2 and policy.certificate == "all_profile_menu_fill")
    for _, client in pairs(S.clients) do
        assert(H.Literal(client[policy.context][policy.field] or value) == H.Literal(value), "non-portable default")
    end
    entries[#entries + 1] = { scope = row.scope, key = row.path[2], kind = value[1], default = value[2] }
end
for id, stage in pairs(S.stages) do
    assert(stage.scope == "general")
    stages[id] = {}
    for key, value in pairs(stage.fields) do stages[id][key] = value[2] end
end
local file = assert(io.open(out, "wb"))
file:write("-- Runtime data derived from the canonical defaults schema.\r\nreturn ",
    H.Literal({ entries = entries, stages = stages }), "\r\n")
file:close()
local ns = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Schema.lua"))("MidnightSimpleUnitFrames", ns)
assert(H.Literal(ns.DefaultsSchema.PersistenceEntries) == H.Literal(entries), "runtime persistence data differs")
assert(H.Literal(ns.DefaultsSchema.SeedStages) == H.Literal(stages), "runtime seed data differs")
print("defaults_schema_generate: portable entries and literal stages match")
