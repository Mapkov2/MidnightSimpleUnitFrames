-- Real visual builder: maximum native calls, invalidations, and strict secrets.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
-- Load the actual provider before the builder binds its methods, as in the TOC.
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, "Mainline")
world.env.issecretvalue = Secrets.IsSecret
world:LoadGraph("MidnightSimpleUnitFrames", World.Graph(root, World.CoreTOC("Mainline"), "enUS"), world.core)
assert(not world:FirstFailure(), "PlayerHP provider graph did not boot")
local common = assert(world.core.UFBarTextCommon)
local builders, php = {}, { visible = true, frame = { unit = "player" }, owner = { unit = "player" } }
local current, maximum, healthCalls, maxCalls = 500, 1000, 0, 0
local bar = {}
function bar:SetValue(value) self.value = value end
function bar:SetMinMaxValues(_, value) self.maximum = value end
function bar:SetStatusBarColor() end
php.bar, php._colorMode = bar, "DARK"
local ns = { UFBarTextCommon = common, UFText = { DISPATCH_KEY = { CURRENT = 1, CURRENT_MAX = 3, MAX = 2, PERCENT_MAX = 5, PERCENT = 4 } } }
function ns.Require(name)
    if name == "MSUF_CP_CONST" then return { BuilderRegistry = function() return builders end } end
    return function() end
end
assert(loadfile(path))("test", ns)
local visual = builders.PLAYER_HP_VISUAL({ PHP = php, _cpDB = { bars = {} },
    UnitHealth = function() healthCalls = healthCalls + 1 return current end,
    UnitHealthMax = function() maxCalls = maxCalls + 1 return maximum end,
})
visual.Update("FULL_REFRESH")
healthCalls, maxCalls = 0, 0
local vm = 0
debug.sethook(function()
    if debug.getinfo(2, "S").source == "@" .. path then vm = vm + 1 end
end, "", 1)
for _ = 1, 100 do visual.Update("UNIT_HEALTH") end
debug.sethook()
print(string.format("playerhp budget: health=%d max=%d /100 health events, %.0f VM/event", healthCalls, maxCalls, vm / 100))
assert(vm / 100 <= 94, "warm health event exceeded original VM budget")
assert(healthCalls == 100 and maxCalls == 0, "plain maximum was reread on health events")
maximum = 2000
visual.Update("UNIT_MAXHEALTH")
assert(bar.maximum == 2000 and maxCalls == 1, "UNIT_MAXHEALTH did not invalidate")
maximum = 3000
visual.Update("UNIT_MAX_HEALTH_MODIFIERS_CHANGED")
assert(bar.maximum == 3000, "max modifiers did not invalidate")
maximum = 4000
visual.Update("MSUF_UF_UNIT_CHANGED")
assert(bar.maximum == 4000, "identity event did not invalidate")
maximum = 5000
php.owner = { unit = "player" }
visual.Update("UNIT_HEALTH")
assert(bar.maximum == 5000, "new owner retained the old maximum")
maximum = 6000
php.frame.unit = "vehicle"
visual.Update("UNIT_HEALTH")
assert(bar.maximum == 6000, "new unit retained the old maximum")
local stop = Secrets.Watch(path, { strict = true })
current, maximum = Secrets.New("number"), Secrets.New("number")
local before, healthBefore = maxCalls, healthCalls
visual.Update("UNIT_HEALTH")
visual.Update("UNIT_HEALTH")
assert(healthCalls == healthBefore + 2 and maxCalls == before + 2 and Secrets.IsSecret(bar.maximum), "secret maximum was cached or stale plain max reused")
assert(php._maxHP == nil and php._hp == nil, "secret leaked into the plain cache")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
current, maximum = 200, 7000
visual.Update("UNIT_HEALTH")
assert(bar.maximum == 7000, "secret-to-plain transition lost maximum")
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect") collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, 1000 do visual.Update("UNIT_HEALTH") end
    minimum = math.min(minimum, collectgarbage("count") - kb)
    collectgarbage("restart")
end
assert(minimum <= 0.001, "health cache allocated")
print(string.format("classpower_playerhp_max_cache: PASS, %.3f KB/1000", minimum))
