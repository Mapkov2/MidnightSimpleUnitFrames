-- Required provider shape failures are named at load; restricted inputs never reach request state.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
local world = World.New(root, flavor)
world.env.issecretvalue = Secrets.IsSecret
world:Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local ns, preview = world.core, world.core.UF.Preview
local FILE = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PagePreviews.lua"
-- The seven request inputs, as one string, for before/after comparison.
local function Requests()
    local out = {}
    for _, key in ipairs({ "editMode", "all", "boss", "arena", "bossPage", "arenaPage", "unitPage" }) do
        out[#out + 1] = tostring(preview.State[key])
    end
    return table.concat(out, "/")
end
local function Missing(label, field, value)
    local previous = field[1][field[2]]
    field[1][field[2]] = value
    local ok, message = world:LoadFile(FILE, "MidnightSimpleUnitFrames_Options", world.options)
    field[1][field[2]] = previous
    assert(not ok and message:find(label, 1, true), "missing named load failure: " .. tostring(message))
end
Missing("UF.Preview", { ns.UF, "Preview" }, nil)
Missing("UF.Preview", { ns.UF, "Preview" }, false)
Missing("UF.Preview.Validate", { preview, "Validate" }, false)
for _, name in ipairs({ "SetEditMode", "SetAll", "SetBoss", "SetArena", "SetBossPage", "SetArenaPage", "SetUnitPage",
    "Set", "Bind", "InitializeBoss" }) do
    Missing("UF.Preview." .. name, { preview, name }, nil)
    Missing("UF.Preview." .. name, { preview, name }, {})
end
Missing("preview state", { preview, "State" }, false)
Missing("preview state", { preview, "ForcedUnits" }, false)
local provider = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Preview.lua"
local saved = ns.Secrets
ns.Secrets = nil
local ok, message = world:LoadFile(provider, "MidnightSimpleUnitFrames", ns)
ns.Secrets = saved
assert(not ok and message:find("Secrets", 1, true), "missing secret provider was not named")
local savedPredicate = ns.Secrets.IsSecret
ns.Secrets.IsSecret = {}
ok, message = world:LoadFile(provider, "MidnightSimpleUnitFrames", ns)
ns.Secrets.IsSecret = savedPredicate
assert(not ok and message:find("Secrets.IsSecret", 1, true), "wrong secret predicate was not named")
local stop = Secrets.Watch(provider, { strict = true })
local calls = 0
for _, kind in ipairs({ "number", "string", "boolean", "table" }) do
    local secret = Secrets.New(kind)
    local before = Requests()
    local applied = pcall(preview.Set, secret, true)
    assert(not applied, "restricted key accepted")
    for _, setter in ipairs({ "SetEditMode", "SetAll", "SetBoss", "SetArena", "SetBossPage", "SetArenaPage", "SetUnitPage" }) do
        applied = pcall(preview[setter], secret)
        assert(not applied, "restricted request accepted by " .. setter)
        calls = calls + 1
    end
    assert(Requests() == before, "restricted request mutated a preview input")
end
-- Named closures preserve invalid-type and ignored-extra-argument contracts.
for _, setter in ipairs({ "SetEditMode", "SetAll", "SetBoss", "SetArena", "SetBossPage", "SetArenaPage", "SetUnitPage" }) do
    for _, value in ipairs({ 0, "true", {}, function() end }) do
        local before = Requests()
        local accepted, failure = pcall(preview[setter], value)
        assert(not accepted and failure:find("expected boolean or nil", 1, true), setter .. " accepted invalid type")
        assert(Requests() == before, setter .. " invalid type changed a preview input")
    end
    local value = preview.State[setter:sub(4, 4):lower() .. setter:sub(5)]
    assert(preview[setter](value, true, "ignored") == false, setter .. " changed vararg contract")
end
for _, key in ipairs({ "editMode", "all", "boss", "arena", "bossPage", "arenaPage", "unitPage" }) do
    for _, value in ipairs({ true, false }) do
        local command = preview.Bind(key, value)
        local changed = preview.State[key] ~= value
        assert(command("ignored", Secrets.New("boolean")) == changed, "bound operation used runtime input")
        assert(preview.State[key] == value)
        assert(command() == false, "bound operation no-op changed state")
    end
    local clear = preview.Bind(key, nil)
    clear()
    assert(preview.State[key] == nil, "bound clear left a request")
end
for _, kind in ipairs({ "number", "string", "boolean", "table" }) do
    local secret = Secrets.New(kind)
    assert(not pcall(preview.Bind, secret, true), "bound protected key accepted")
    assert(not pcall(preview.Bind, "all", secret), "bound protected value accepted")
end
for _, value in ipairs({ 0, "true", {}, function() end }) do
    assert(not pcall(preview.Bind, "all", value), "bound invalid type accepted")
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
print("PASS preview strict requests and named provider failures " .. flavor .. ": " .. calls .. " restricted setter calls")
