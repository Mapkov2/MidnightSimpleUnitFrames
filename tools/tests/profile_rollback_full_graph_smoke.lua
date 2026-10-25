-- Full serialized 7.0 -> unchanged production 6.50x -> 7.0 profile roundtrip.
local root, flavor = assert(arg[1]), assert(arg[2])
local production = "C:/MSUF Beta Branch/MidnightSimpleUnitFrames"
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local W = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end
local version = W.Read(production .. "/VERSION"):match("^(%S+)")
assert(version:match("^6%.50%d*$"), "production is not a 6.50x checkout: " .. version)
local client = W.ClientFor(production, flavor)
local toc = W.CoreTOC(client.tocSuffix)
local gameType = client.isForever and "camelot" or (client.isClassic and client.gameType or "standard")
local graph = W.Graph(production, toc, "enUS", gameType, root)
local original = {}
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local walked = manifest.Walk(production, client.tocSuffix, "enUS", gameType)
assert(#walked.lua == #graph, "production TOC walkers disagree")
for index, path in ipairs(graph) do
    assert(walked.lua[index] == path, "production TOC order differs: " .. path)
    original[path] = Read(path)
end
for _, path in ipairs(walked.xml) do original[path] = Read(path) end
for _, path in ipairs({ toc, "VERSION", "tools/classic-client-matrix.tsv" }) do
    original[production .. "/" .. path] = Read(production .. "/" .. path)
end
local historicalRevision = assert(tonumber(original[production .. "/MidnightSimpleUnitFrames/State/MSUF_ProfileNormalize.lua"]
    :match("local MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = (%d+)")), "missing production normalization revision")

local function Saved(env)
    local lines = {}
    local names = assert(original[production .. "/" .. toc]:match("## SavedVariables: ([^\n]+)"))
    for name in names:gmatch("[%w_]+") do
        local value = rawget(env, name)
        if value ~= nil then lines[#lines + 1] = name .. "=" .. H.Literal(value) end
    end
    local bytes = table.concat(lines, "\n")
    local chunk = assert(loadstring(bytes))
    local disk = {}
    setfenv(chunk, disk)
    chunk()
    return disk
end
local historicalErrors = {}
local function Healthy(world, stage)
    local errors, checked = {}, { isolated = {} }
    for _, caught in ipairs(world.isolated) do
        -- The historical health painter reads an unmodelled runtime field.
        -- This aborts a frame repaint, never State/login/EnsureDB/logout code.
        local health = caught.context == "PLAYER_LOGIN" and caught.file == "MSUF_UF_Elements_Health.lua"
            and caught.detail:match("MSUF_UF_Elements_Health%.lua:951: attempt to compare number with table$")
        local highlight = flavor ~= "Mainline" and flavor ~= "Forever" and caught.context == "timer"
            and caught.file == "MSUF_UF_Highlight.lua"
            and caught.detail:match("MSUF_UF_Highlight%.lua:220: attempt to compare number with table$")
        if world.historical and (health or highlight) then
            historicalErrors[caught.context .. " | " .. caught.detail] = true
        else checked.isolated[#checked.isolated + 1] = caught end
    end
    errors = C.UnexpectedErrors({ world = checked, flavor = flavor }, {})
    if #errors > 0 then
        for _, caught in ipairs(world.isolated) do print(stage .. ": " .. (caught.detail or caught.message)) end
    end
    assert(#errors == 0, stage .. ": " .. table.concat(errors, "; "))
end
local function Login(saved, character, source)
    local world = C.NewWorld(root, flavor, character, nil, source, gameType)
    if source then
        assert(#world.corePaths == #graph, "historical graph count differs")
        for index, path in ipairs(graph) do
            assert(world.corePaths[index] == path, "historical graph was not loaded unchanged: " .. path)
        end
    end
    world.historical = source ~= nil
    C.Login(world, saved, true)
    Healthy(world, source and "production login" or "7.0 login")
    return world, world.env
end
local function Equal(env, expected, stage)
    if H.Literal(env.MSUF_GlobalDB.profiles) == expected then return end
    local reference, count = assert(loadstring("return " .. expected))(), 0
    local function Diff(a, b, path)
        if a == b or count >= 12 then return end
        if type(a) == "table" and type(b) == "table" then
            for key, value in pairs(a) do Diff(value, b[key], path .. "." .. tostring(key)) end
            for key, value in pairs(b) do if a[key] == nil then Diff(nil, value, path .. "." .. tostring(key)) end end
        else
            print(stage .. ": " .. path .. " " .. tostring(a) .. " -> " .. tostring(b))
            count = count + 1
        end
    end
    Diff(reference, env.MSUF_GlobalDB.profiles, "profiles")
    error(stage .. ": full profile bytes changed")
end
local cases, profiles = 0, 0
local function Roundtrip()
    for _, entry in ipairs(C.Manifest(root)) do
        local relevant = entry.kind == "factory"
        for _, name in ipairs(entry.clients) do if name == flavor then relevant = true end end
        if relevant then
            local character = entry.login or "Tester-Realm"
            local saved = entry.kind == "sv" and C.LoadSavedVariablesFixture(root, entry.file) or {}
            local world, env = Login(saved, character)
            for name in pairs(env.MSUF_GlobalDB.profiles) do assert(env.MSUF_SwitchProfile(name)) end
            local pool = env.MSUF_GlobalDB.profiles
            pool.Inactive = C.Copy(env.MSUF_DB)
            pool.Inactive.general.rollbackUnknown = { false, 0, "", [12345] = "spell" }
            pool.Inactive.general.castbarShowPushback = nil
            local full, active, bindings = H.Literal(pool), H.Literal(env.MSUF_DB), H.Literal(env.MSUF_GlobalDB.char)
            for _ in pairs(pool) do profiles = profiles + 1 end
            world:FireEvent("PLAYER_LOGOUT")
            assert(type(pool.Inactive._msufSparseDefaultsV3) == "string", "source was not V3 sparse")
            world, env = Login(Saved(env), character)
            world.core.SlashCommands.Dispatch("compatsave")
            world:FireEvent("PLAYER_LOGOUT")
            assert(env.MSUF_GlobalDB._compatSave == "saved", "full compatibility save did not finish")
            Equal(env, full, entry.id .. " compatibility save")
            world, env = Login(Saved(env), character, production)
            -- Each release owns its normalization stamp (currently 21 vs 22).
            -- Allow only that stamp through production login/EnsureDB/logout, then require
            -- the COMPLETE original profile bytes again on the returning 7.0 login.
            local historicalProfiles = assert(loadstring("return " .. full))()
            for _, profile in pairs(historicalProfiles) do profile._msufProfileNormalizationRevision = historicalRevision end
            local historicalFull = H.Literal(historicalProfiles)
            Equal(env, historicalFull, entry.id .. " production login")
            assert(env.MSUF_EnsureDB() == env.MSUF_DB, "production EnsureDB did not bind the active profile")
            Equal(env, historicalFull, entry.id .. " production EnsureDB")
            Healthy(world, "production EnsureDB")
            world:FireEvent("PLAYER_LOGOUT")
            Equal(env, historicalFull, entry.id .. " production logout")
            world, env = Login(Saved(env), character)
            Equal(env, full, entry.id .. " 7.0 return")
            assert(H.Literal(env.MSUF_DB) == active, entry.id .. ": active profile bytes changed")
            assert(H.Literal(env.MSUF_GlobalDB.char) == bindings, entry.id .. ": character binding bytes changed")
            assert(env.MSUF_GlobalDB._compatSave == nil, "7.0 return did not disarm compatibility saving")
            cases = cases + 1
        end
    end
end
local ok, failure = pcall(Roundtrip)
for path, bytes in pairs(original) do assert(Read(path) == bytes, "production source changed: " .. path) end
assert(ok, failure)
for detail in pairs(historicalErrors) do print("HARNESS historical frame repaint: " .. detail) end
print("PASS full downgrade " .. flavor .. ": production " .. version .. ", " .. #graph .. " unchanged TOC chunks; "
    .. cases .. " corpus cases / " .. profiles .. " complete profiles byte-identical after return")
