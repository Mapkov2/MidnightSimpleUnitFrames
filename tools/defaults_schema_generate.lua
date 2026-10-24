-- Use --write [--sparse-v2|--sparse-v3] to refresh the generated storage data file.
-- Generate portable runtime data from the canonical typed defaults schema.
local root, out = assert(arg[1]), assert(arg[2])
local check = out == "--check" or arg[3] == "--check" or arg[4] == "--check"
local sparse = out == "--check" or out == "--write" or arg[3] == "--sparse-v2"
local outputParts = {}
local dataPath = root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_StorageData.lua"
local function ReadStorageData()
    local source = assert(io.open(dataPath, "rb"))
    local text = source:read("*a")
    source:close()
    return text
end
local function Output()
    if not check and out ~= "--write" then return assert(io.open(out, "wb")) end
    return {
        write = function(_, ...)
            for i = 1, select("#", ...) do outputParts[#outputParts + 1] = tostring(select(i, ...)) end
        end,
        close = function()
            if out ~= "--write" then return end
            local text, block = ReadStorageData(), table.concat(outputParts)
            local marker = arg[3] == "--sparse-v3" and "SPARSE V3 INHERITED DEFAULTS" or "FROZEN SPARSE V2 DATA"
            local pattern = "%-%- BEGIN " .. marker .. ".-%-%- END " .. marker .. "\r?\n"
            local replaced, count = text:gsub(pattern, function() return block end)
            assert(count == 1, "generated storage section missing or duplicated")
            local file = assert(io.open(dataPath, "wb"))
            file:write(replaced)
            file:close()
        end,
    }
end
local S = assert(loadfile(root .. "/tools/fixtures/defaults/schema.lua"))()
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
-- V3 presence slots inherit the current default; paths/order are the wire identity.
-- Factory-only leaves are safe because presence records exactly what was stored.
if arg[3] == "--sparse-v3" then
    local owners, names = {}, {}
    local function Eligible(path)
        for _, key in ipairs(path) do
            if type(key) == "string" then
                local lower = key:lower()
                if key:sub(1, 1) == "_" or lower:find("migration", 1, true) or lower:find("version", 1, true)
                    or lower:find("revision", 1, true) or lower:find("marker", 1, true) then return false end
            end
        end
        return path[#path] ~= "positionMode"
    end
    for id, row in ipairs(S.fields) do
        local value = row.factory
        local valid = #row.path >= 2 and Eligible(row.path)
            and (value[1] == "boolean" or value[1] == "number" or value[1] == "string" or value[1] == "table")
        for _, client in pairs(S.clients) do
            local observed = client.factory[id] or value
            if observed[1] ~= value[1] or observed[2] ~= value[2] then valid = false end
        end
        if valid then
            local path = {}
            for i = 1, #row.path - 1 do path[i] = row.path[i] end
            local name = H.Literal(path)
            if not owners[name] then
                local lists, node = {}, S.factoryContexts.clients.Mainline.expectedRuntime
                for depth = 1, #path + 1 do
                    if type(node) == "table" then
                        for key in pairs(node) do if type(key) == "number" then lists[depth] = true end end
                        node = node[path[depth]]
                    end
                end
                owners[name] = { path = path, lists = lists, fields = {} }
                names[#names + 1] = name
            end
            owners[name].fields[#owners[name].fields + 1] = { row.path[#row.path], value[2] }
        end
    end
    table.sort(names)
    local runtimeText = ReadStorageData()
    local old = assert(loadstring("return " .. assert(runtimeText:match("local sparseV2Fields = (%b{})"))))()
    local existing, pool, ids = {}, {}, {}
    for id, field in ipairs(old) do existing[H.Literal({ field[1], field[2] })] = id end
    for _, name in ipairs(names) do
        for _, field in ipairs(owners[name].fields) do
            if field[2] == nil then field[2] = {} end
            local signature = H.Literal(field)
            if not ids[signature] then
                pool[#pool + 1] = field
                ids[signature] = #pool
            end
        end
    end
    -- Reject slot insertion/removal/reordering even outside --check. Values may
    -- evolve, but changing presence identities requires a new codec version.
    local previous = runtimeText:match("%-%- BEGIN SPARSE V3 INHERITED DEFAULTS.-%-%- END SPARSE V3 INHERITED DEFAULTS")
    if previous then
        local previousFields, previousOwners, previousRuns = assert(loadstring("local sparseV2Fields = "
            .. assert(runtimeText:match("local sparseV2Fields = (%b{})")) .. "\n" .. previous
            .. "\nreturn sparseV3Fields, sparseV3Owners, sparseV3Runs"))()
        assert(#previousOwners == #names, "V3 owner identities changed; use a new codec version")
        for i, name in ipairs(names) do
            local owner, prior = owners[name], previousOwners[i]
            if prior.runs then
                prior.fields = {}
                for _, run in ipairs(prior.runs) do
                    for _, id in ipairs(previousRuns[run]) do prior.fields[#prior.fields + 1] = id end
                end
            end
            assert(H.Literal(owner.path) == H.Literal(prior.path) and H.Literal(owner.lists) == H.Literal(prior.lists)
                and #owner.fields == #prior.fields, "V3 owner/slot identities changed; use a new codec version")
            for j, field in ipairs(owner.fields) do
                assert(field[1] == previousFields[prior.fields[j]][1], "V3 field identities changed; use a new codec version")
            end
        end
    end
    local runs, runIds = {}, {}
    for _, name in ipairs(names) do
        local owner = owners[name]
        owner.runs = {}
        for first = 1, #owner.fields, 20 do
            local run = {}
            for i = first, math.min(first + 19, #owner.fields) do run[#run + 1] = ids[H.Literal(owner.fields[i])] end
            local signature = H.Literal(run)
            if not runIds[signature] then
                runs[#runs + 1] = run
                runIds[signature] = #runs
            end
            owner.runs[#owner.runs + 1] = runIds[signature]
        end
    end
    local file, count = Output(), 0
    file:write("-- BEGIN SPARSE V3 INHERITED DEFAULTS\r\n",
        "-- Generated by tools/defaults_schema_generate.lua --sparse-v3.\r\n",
        "-- Slot paths/order are fixed; values intentionally follow current defaults.\r\n",
        "local sparseV3Fields = {\r\n")
    for _, field in ipairs(pool) do
        local oldId = existing[H.Literal(field)]
        if oldId then file:write("    sparseV2Fields[", oldId, "],\r\n")
        else file:write("    { ", H.Literal(field[1]), ", ", H.Literal(field[2]), " },\r\n") end
    end
    file:write("}\r\nlocal sparseV3Runs = {\r\n")
    for _, run in ipairs(runs) do
        file:write("    { ")
        for _, id in ipairs(run) do file:write(id, ", ") end
        file:write("},\r\n")
    end
    file:write("}\r\nlocal sparseV3Owners = {\r\n")
    for _, name in ipairs(names) do
        local owner = owners[name]
        file:write("    { path = ", H.Literal(owner.path), ", lists = ", H.Literal(owner.lists), ", runs = {\r\n        ")
        for i, run in ipairs(owner.runs) do
            file:write(run, ",")
            if i < #owner.runs then file:write(" ") end
        end
        file:write("\r\n    } },\r\n")
        count = count + #owner.fields
    end
    file:write("}\r\n-- END SPARSE V3 INHERITED DEFAULTS\r\n")
    file:close()
    if check then
        local generated = table.concat(outputParts)
        local current = runtimeText:match("(%-%- BEGIN SPARSE V3 INHERITED DEFAULTS.-%-%- END SPARSE V3 INHERITED DEFAULTS\r?\n)")
        assert(current == generated, "Sparse V3 generated defaults differ")
    end
    print(("defaults_schema_generate: V3 %d inherited fields, %d owners, %d pooled pairs"):format(count, #names, #pool))
    return
end

-- Freeze a separate decoder dictionary; its field order is a wire contract.
-- Presence bits distinguish absent/lazy fields from explicitly stored defaults.
if sparse then
    -- Keep existing decoder slots even when future encodings must retain a leaf.
    -- Broad marker-name retention also protects visual marker keys conservatively.
    local function RetainPath(path)
        for _, key in ipairs(path) do
            local lower = key:lower()
            if lower:find("migration", 1, true) or lower:find("version", 1, true)
                or lower:find("revision", 1, true) or lower:find("marker", 1, true) then return true end
        end
        -- 6.50 geometry uses this discriminator before its count-based conversion.
        return path[#path] == "positionMode"
    end
    local owners, ordered = {}, {}
    for id, row in ipairs(S.fields) do
        local value, valid = row.factory, #row.path >= 2
        local kind, default = value[1], value[2]
        valid = valid and (kind == "boolean" and default == true or kind == "number" and default ~= 0
            or kind == "string" and default ~= "")
        for _, key in ipairs(row.path) do
            if type(key) ~= "string" or key:sub(1, 1) == "_" or key:match("^%d+$") then valid = false end
        end
        for _, client in pairs(S.clients) do
            for _, context in ipairs({ "factory", "repair" }) do
                local observed = client[context][id] or row[context]
                if observed[1] ~= kind or observed[2] ~= default then valid = false end
            end
        end
        if valid then
            local path = {}
            for i = 1, #row.path - 1 do path[i] = row.path[i] end
            local name = H.Literal(path)
            local owner = owners[name]
            if not owner then
                owner = { path = path, fields = {}, retained = {} }
                owners[name], ordered[#ordered + 1] = owner, name
            end
            local key = row.path[#row.path]
            owner.fields[key] = default
            owner.retained[key] = RetainPath(row.path)
        end
    end
    table.sort(ordered)
    local fields, fieldIds, total = {}, {}, 0
    for _, name in ipairs(ordered) do
        local owner = owners[name]
        local keys = {}; for key in pairs(owner.fields) do keys[#keys + 1] = key end; table.sort(keys)
        owner.ids = {}
        for _, key in ipairs(keys) do
            local field = { key, owner.fields[key] }
            local signature = H.Literal(field)
            if not fieldIds[signature] then
                fields[#fields + 1] = field
                fieldIds[signature] = #fields
            end
            if owner.retained[key] then fields[fieldIds[signature]].retain = true end
            owner.ids[#owner.ids + 1] = fieldIds[signature]
            total = total + 1
        end
    end
    local file = Output()
    file:write("-- BEGIN FROZEN SPARSE V2 DATA\r\n",
        "-- Generated by tools/defaults_schema_generate.lua --sparse-v2; never reorder this wire dictionary.\r\n",
        "local sparseV2Fields = {\r\n")
    for _, field in ipairs(fields) do
        file:write("    { ", H.Literal(field[1]), ", ", H.Literal(field[2]),
            field.retain and ", retain = true" or "", " },\r\n")
    end
    file:write("}\r\nlocal sparseV2Owners = {\r\n")
    for _, name in ipairs(ordered) do
        local owner = owners[name]
        file:write("    { path = ", H.Literal(owner.path), ", fields = {\r\n")
        for i, id in ipairs(owner.ids) do
            if (i - 1) % 30 == 0 then file:write("        ") end
            file:write(id, ",")
            if i % 30 == 0 or i == #owner.ids then file:write("\r\n") else file:write(" ") end
        end
        file:write("    } },\r\n")
    end
    file:write("}\r\n-- END FROZEN SPARSE V2 DATA\r\n")
    file:close()
    if check then
        local text = ReadStorageData()
        local frozen = text:match("(%-%- BEGIN FROZEN SPARSE V2 DATA.-%-%- END FROZEN SPARSE V2 DATA\r?\n)")
        assert(frozen == table.concat(outputParts), "frozen Sparse V2 dictionary differs")
        print("defaults_schema_generate: frozen Sparse V2 dictionary identical")
    end
    print(("defaults_schema_generate: V2 %d scalar fields, %d owners, %d pooled key/value pairs"):format(
        total, #ordered, #fields))
    return
end

local entries, stages = {}, {}
for _, policy in ipairs(S.persistence) do
    local row, value = S.fields[policy.field], S.fields[policy.field][policy.context]
    local normalizerOnly = policy.certificate == "all_profile_preview_marker_fill"
    assert(#row.path == 2 and (policy.certificate == "all_profile_menu_fill" or normalizerOnly))
    assert(not normalizerOnly or row.scope == "general" and row.path[2] == "_msufPreviewDragHintExperienced"
        and value[1] == "boolean" and value[2] == true, "invalid preview marker certificate")
    for _, client in pairs(S.clients) do
        assert(H.Literal(client[policy.context][policy.field] or value) == H.Literal(value), "non-portable default")
    end
    entries[#entries + 1] = { scope = row.scope, key = row.path[2], kind = value[1], default = value[2],
        normalizerOnly = normalizerOnly or nil }
end
for id, stage in pairs(S.stages) do
    assert(stage.scope == "general")
    stages[id] = {}
    for key, value in pairs(stage.fields) do stages[id][key] = value[2] end
end
local file = Output()
file:write("-- Runtime data derived from the canonical defaults schema.\r\nreturn ",
    H.Literal({ entries = entries, stages = stages }), "\r\n")
file:close()
local ns = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Schema.lua"))("MidnightSimpleUnitFrames", ns)
assert(H.Literal(ns.DefaultsSchema.PersistenceEntries) == H.Literal(entries), "runtime persistence data differs")
assert(H.Literal(ns.DefaultsSchema.SeedStages) == H.Literal(stages), "runtime seed data differs")
print("defaults_schema_generate: portable entries and literal stages match")
