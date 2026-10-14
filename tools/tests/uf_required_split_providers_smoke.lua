-- Split owners must be ready in the real graph, including omission failures.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = dofile(root .. "/tools/tests/client_world.lua")
local owners = {
    { "Elements/MSUF_UF_Prediction_Glow.lua", "PredictionGlow" },
    { "Elements/MSUF_UF_Status_Regions.lua", "StatusRegions" },
    { "Elements/MSUF_UF_Status_Indicators.lua", "StatusIndicatorArt" },
    { "Elements/MSUF_UF_Status_GroupRuntime.lua", "StatusGroupRuntime" },
    { "Elements/MSUF_UF_Status_Level.lua", "StatusLevelBadge" },
    { "Elements/MSUF_UF_Text_SlotCompile.lua", "TextSlotCompile" },
    { "Elements/MSUF_UF_Text_Drain.lua", "TextDrain" },
    { "Elements/MSUF_UF_Text_Name.lua", "TextName" },
    { "MSUF_UF_Factory_Spawn.lua", "FactorySpawn" },
    { "MSUF_UF_Factory_Anchors.lua", "FactoryAnchors" },
    { "MSUF_UF_Factory_CooldownWidth.lua", "FactoryCooldownWidth" },
}
local consumers = {
    PredictionGlow = "Elements/MSUF_UF_Elements_Prediction.lua",
    StatusRegions = "Elements/MSUF_UF_Elements_Status.lua",
    StatusIndicatorArt = "Elements/MSUF_UF_Elements_Status.lua",
    StatusGroupRuntime = "Elements/MSUF_UF_Elements_Status.lua",
    StatusLevelBadge = "Elements/MSUF_UF_Elements_Status.lua",
    TextSlotCompile = "Elements/MSUF_UF_Text_Format.lua",
    TextDrain = "Elements/MSUF_UF_Text_Runtime.lua",
    TextName = "Elements/MSUF_UF_Text_Runtime.lua",
    FactorySpawn = "MSUF_UF_Factory.lua",
    FactoryAnchors = "MSUF_UF_Factory.lua",
    FactoryCooldownWidth = "MSUF_UF_Factory.lua",
}
local problems = {}
local function CheckFailure(world, key, label)
    local failure = world:FirstFailure()
    local message = tostring(failure and failure.message)
    if not (failure and message:find(key, 1, true) and message:find(consumers[key], 1, true)
        and failure.file:find(consumers[key], 1, true)) then
        problems[#problems + 1] = label .. ": " .. key .. ": " .. message
    end
end
local engine = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/"
local world = World.New(root, flavor)
world:Boot()
assert(not world:FirstFailure(), flavor .. ": complete graph failed to boot")
local factories = world.core.UFModuleFactories
assert(type(factories) == "table", "required UF responsibility factories are missing")
for _, owner in ipairs(owners) do
    local path, key = engine .. owner[1], owner[2]
    assert(type(factories[key]) == "function", flavor .. ": required provider " .. key)
    assert(debug.getinfo(factories[key], "S").source:find(owner[1], 1, true), "substituted " .. key)
    local omitted = World.New(root, flavor)
    local load = omitted.LoadFile
    function omitted:LoadFile(candidate, addon, namespace)
        if candidate == path then return true end
        return load(self, candidate, addon, namespace)
    end
    omitted:Boot()
    local failure = omitted:FirstFailure()
    assert(failure and tostring(failure.message):find(key, 1, true),
        flavor .. ": omission did not name " .. key .. ": " .. tostring(failure and failure.message))
    CheckFailure(omitted, key, "omission")
    for _, shape in ipairs({ {}, false, 17, "invalid", setmetatable({}, { __call = function() error("fake factory used") end }) }) do
        local malformed = World.New(root, flavor)
        local realLoad = malformed.LoadFile
        function malformed:LoadFile(candidate, addon, namespace)
            local ok, diagnostic = realLoad(self, candidate, addon, namespace)
            if candidate == path and ok then namespace.UFModuleFactories[key] = shape end
            return ok, diagnostic
        end
        malformed:Boot()
        CheckFailure(malformed, key, "wrong shape " .. type(shape))
    end
end
assert(#problems == 0, flavor .. ": readiness failures:\n" .. table.concat(problems, "\n"))
print("uf_required_split_providers_smoke: ok (" .. flavor .. ": real boot, 11 omissions and 55 wrong shapes)")
