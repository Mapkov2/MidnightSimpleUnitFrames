-- PlayerHP binds real BarsCommon methods once; native, secret and VM budgets.
-- <repoRoot> [measure]: measure is for the recorded pre-change baseline only.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local path = arg[3] or root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua"
local commonPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local function Read(file)
    local f = assert(io.open(file, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local commonSource = Read(commonPath)
local common = {}
for _, name in ipairs({ "SetBarMinMaxKnown", "SetBarValueKnown" }) do
    local body = assert(commonSource:match("local function " .. name .. "%b().-\nend\n"))
    common[name] = assert(loadstring(body .. "return " .. name, "@" .. commonPath))()
end
local function Noop() end
common.SetBarSmoothing = Noop
common.ClassColor = function() return .2, .4, .6 end
local gradientR, gradientG, gradientB = .3, .5, .7
common.GradientColor = function() return gradientR, gradientG, gradientB end
common.ApplyHealthStatusColor = function(bar) bar:SetStatusBarColor(.4, .6, .8) end
local builders = {}
local ns = { UFBarTextCommon = common,
    UFText = { DISPATCH_KEY = { CURRENT = 1, CURRENT_MAX = 3, MAX = 2, PERCENT_MAX = 5, PERCENT = 4 } } }
function ns.Require(name)
    if name == "MSUF_CP_CONST" then return { BuilderRegistry = function() return builders end } end
    return Noop
end
assert(loadfile(path))("test", ns)
local hp, maximum, healthCalls, maxCalls, values, ranges, colors = 500, 1000, 0, 0, 0, 0, 0
local bar = {}
function bar:SetValue(value, interp) self.value, self.interp = value, interp values = values + 1 end
function bar:SetMinMaxValues(_, value) self.maximum = value ranges = ranges + 1 end
function bar:SetStatusBarColor(r, g, b) self.r, self.g, self.b = r, g, b colors = colors + 1 end
local php = { visible = true, frame = { unit = "player" }, owner = {}, bar = bar, _colorMode = "DARK" }
local injected = { PHP = php, Common = common, _cpDB = { bars = {} }, GetPlayerFrame = function() return php.frame end,
    UnitHealth = function() healthCalls = healthCalls + 1 return hp end,
    UnitHealthMax = function() maxCalls = maxCalls + 1 return maximum end }
local visual = builders.PLAYER_HP_VISUAL(injected)
visual.Update("FULL_REFRESH")
local function Budget(label, operation, ceiling, expectedMax, expectedValue, expectedRange, expectedColor)
    for _ = 1, 30 do operation() end
    local vm = 0
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source
        if source == "@" .. path or source == "@" .. commonPath then vm = vm + 1 end
    end, "", 1)
    healthCalls, maxCalls, values, ranges, colors = 0, 0, 0, 0, 0
    for _ = 1, 100 do operation() end
    debug.sethook()
    assert(healthCalls == 100 and maxCalls == expectedMax and values == expectedValue and ranges == expectedRange,
        label .. " native read/write budget changed")
    assert(colors == (expectedColor or 0), label .. " native color budget changed")
    local minKB = math.huge
    for _ = 1, 2 do
        collectgarbage("collect") collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do operation() end
        minKB = math.min(minKB, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("%s: %.0f VM, %.3f KB/1000", label, vm / 100, minKB))
    assert(minKB <= 0.001, label .. " allocated")
    if not measure then assert(vm / 100 <= ceiling, label .. " VM budget exceeded") end
end
Budget("health unchanged", function() visual.Update("UNIT_HEALTH") end, 90, 0, 0, 0)
Budget("health changed", function() hp = hp == 500 and 501 or 500 visual.Update("UNIT_HEALTH") end, 127, 0, 100, 0)
Budget("max changed", function() maximum = maximum == 1000 and 1001 or 1000 visual.Update("UNIT_MAXHEALTH") end, 136, 100, 0, 100)
for _, sample in ipairs({ { "CLASS", 95 }, { "GRADIENT", 118 }, { "GLOBAL", 92 } }) do
    php._colorMode = sample[1]
    Budget("health " .. sample[1], function() visual.Update("UNIT_HEALTH") end, sample[2], 0, 0, 0,
        sample[1] == "GLOBAL" and 100 or 0)
end
php._colorMode = "DARK"
bar._msufSmoothInterp = 7
hp = 444 visual.Update("UNIT_HEALTH")
assert(bar.value == hp and bar.interp == 7 and bar._msufInterpolating == true, "smooth value sink changed")
bar._msufSmoothInterp = nil
hp = 445 visual.Update("UNIT_HEALTH")
assert(bar.value == hp and bar.interp == nil and bar._msufInterpolating == nil, "plain value sink changed")
hp, maximum = Secrets.New("number"), Secrets.New("number")
local stop = Secrets.Watch({ path, commonPath }, { strict = true })
local h, m, v, r = healthCalls, maxCalls, values, ranges
visual.Update("UNIT_HEALTH") visual.Update("UNIT_HEALTH")
assert(healthCalls == h + 2 and maxCalls == m + 2 and values == v + 2 and ranges == r + 2, "secret native reads/writes changed")
assert(php._hp == nil and php._maxHP == nil and bar._msufDirectValue == nil, "secret cached")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
Budget("health secret", function() visual.Update("UNIT_HEALTH") end, 144, 100, 100, 100)
if measure then return end
-- Poison the provider table after binding: event paths must use selected methods.
common.SetBarValueKnown = function() error("late value lookup") end
common.SetBarMinMaxKnown = function() error("late range lookup") end
common.ClassColor = function() error("late class color lookup") end
common.GradientColor = function() error("late gradient color lookup") end
common.ApplyHealthStatusColor = function() error("late status color lookup") end
hp, maximum = 200, 2000
visual.Update("FULL_REFRESH")
assert(bar.value == hp and bar.maximum == maximum, "bound sinks not used")
for _, sample in ipairs({ { "CLASS", .2, .4, .6 }, { "GRADIENT", .3, .5, .7 }, { "GLOBAL", .4, .6, .8 } }) do
    php._colorMode = sample[1]
    visual.Update("UNIT_HEALTH")
    assert(bar.r == sample[2] and bar.g == sample[3] and bar.b == sample[4], "bound " .. sample[1] .. " color changed")
end
gradientR, gradientG, gradientB = Secrets.New("number"), Secrets.New("number"), Secrets.New("number")
php._colorMode = "GRADIENT"
local colorStop = Secrets.Watch(path, { strict = true })
visual.Update("UNIT_HEALTH")
local colorViolations = colorStop()
assert(#colorViolations == 0, table.concat(colorViolations, "\n"))
assert(Secrets.IsSecret(bar.r) and php.bar._phpR == nil and php.bar._msufStatusR == nil, "secret gradient compared/cached")
for _, name in ipairs({ "SetBarMinMaxKnown", "SetBarValueKnown", "SetBarSmoothing", "ClassColor", "GradientColor", "ApplyHealthStatusColor" }) do
    local saved = common[name]
    for _, missing in ipairs({ false, 7, {} }) do
        common[name] = missing
        local ok, err = pcall(builders.PLAYER_HP_VISUAL, injected)
        assert(not ok and tostring(err):find(name, 1, true), "invalid Common." .. name .. " accepted at binding")
    end
    common[name] = nil
    local ok, err = pcall(builders.PLAYER_HP_VISUAL, injected)
    common[name] = saved
    assert(not ok and tostring(err):find(name, 1, true), "missing Common." .. name .. " accepted at binding")
end
-- The actual client graphs guarantee the production provider precedes this builder.
local World = dofile(root .. "/tools/tests/client_world.lua")
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local world = World.New(root, flavor)
    local paths = World.Graph(root, World.CoreTOC(world.client.tocSuffix or flavor), world.env.GetLocale(),
        world.client.isForever and "camelot" or nil)
    local seen = false
    for _, file in ipairs(paths) do
        if file:match("MSUF_CP_PlayerHP.lua$") then
            assert(world.core.UFBarTextCommon, flavor .. " Common provider loads late")
            seen = true
            break
        end
        local ok, err = world:LoadFile(file, "MidnightSimpleUnitFrames", world.core)
        assert(ok, flavor .. ": " .. tostring(err))
    end
    assert(seen, flavor .. " PlayerHP missing from graph")
end
print("classpower_playerhp_binding: PASS")
