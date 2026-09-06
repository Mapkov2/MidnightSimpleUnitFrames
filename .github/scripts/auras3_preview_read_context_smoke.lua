-- Preview read-context contract. The reference below intentionally uses the
-- existing public getters: it is the pre-optimization behavior, including lazy
-- metric fallbacks, legacy migrations, and the historical false-value rules.
-- Compare complete results/SavedVariables and count actual DB read entries;
-- these counts describe work removed, not measured in-game CPU performance.
local root = arg and arg[1] or "."
local loader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
local CUSTOM_CONTAINER_MAX = 4
local function NormalizeUnit(unit)
    unit = tostring(unit or "player")
    if unit == "boss" or unit:match("^boss[1-5]$") then return "boss" end
    if unit == "target" or unit == "focus" then return unit end
    return "player"
end
local function RuntimeUnit(unit)
    unit = tostring(unit or "player")
    if unit:match("^boss[1-5]$") then return unit end
    unit = NormalizeUnit(unit)
    return unit == "boss" and "boss1" or unit
end
local function ReadThroughPublicGetters(Model, A3, unit)
    unit = NormalizeUnit(unit)
    local auras, shared = Model.EnsureDB()
    if type(auras) ~= "table" or type(shared) ~= "table" then return nil end
    local runtimeCfg = type(A3.ResolveUnitFrameConfig) == "function" and A3.ResolveUnitFrameConfig(RuntimeUnit(unit)) or nil
    local buildMetrics = runtimeCfg and type(A3.BuildAuraLaneMetrics) == "function" and A3.BuildAuraLaneMetrics or nil
    local buffMetrics = buildMetrics and buildMetrics(runtimeCfg, "buff") or nil
    local debuffMetrics = buildMetrics and buildMetrics(runtimeCfg, "debuff") or nil
    local customMetrics = {}
    if buildMetrics then
        for index = 1, CUSTOM_CONTAINER_MAX do
            customMetrics[index] = buildMetrics(runtimeCfg, "custom" .. tostring(index))
        end
    end
    local unitEnabled = runtimeCfg and runtimeCfg.enabled == true or Model.UnitEnabled(unit)
    local showBuffs = false
    local showDebuffs = false
    if unitEnabled then
        if buffMetrics then showBuffs = buffMetrics.enabled == true else showBuffs = Model.GroupShown(unit, "buff") end
        if debuffMetrics then showDebuffs = debuffMetrics.enabled == true else showDebuffs = Model.GroupShown(unit, "debuff") end
    end
    return {
        unit = unit,
        enabled = unitEnabled,
        showBuffs = showBuffs == true,
        showDebuffs = showDebuffs == true,
        buffMetrics = buffMetrics,
        debuffMetrics = debuffMetrics,
        customMetrics = customMetrics,
        buffX = buffMetrics and buffMetrics.x or Model.ReadNumber(unit, "buffGroupOffsetX", 0, -4096, 4096),
        buffY = buffMetrics and buffMetrics.y or Model.ReadNumber(unit, "buffGroupOffsetY", 36, -4096, 4096),
        debuffX = debuffMetrics and debuffMetrics.x or Model.ReadNumber(unit, "debuffGroupOffsetX", 0, -4096, 4096),
        debuffY = debuffMetrics and debuffMetrics.y or Model.ReadNumber(unit, "debuffGroupOffsetY", 6, -4096, 4096),
        buffAnchor = buffMetrics and buffMetrics.anchor or Model.ReadLaneAnchor(unit, "buff"),
        debuffAnchor = debuffMetrics and debuffMetrics.anchor or Model.ReadLaneAnchor(unit, "debuff"),
        buffLayer = Model.ReadLaneLayer(unit, "buff"),
        debuffLayer = Model.ReadLaneLayer(unit, "debuff"),
        buffSize = buffMetrics and buffMetrics.size or Model.ReadNumber(unit, "buffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        debuffSize = debuffMetrics and debuffMetrics.size or Model.ReadNumber(unit, "debuffGroupIconSize", Model.ReadNumber(unit, "iconSize", 26, 1, 128), 1, 128),
        buffIconZoom = buffMetrics and buffMetrics.iconZoom or Model.ReadLaneStyleNumber(unit, "buff", "iconZoom", 100, 100, 200),
        debuffIconZoom = debuffMetrics and debuffMetrics.iconZoom or Model.ReadLaneStyleNumber(unit, "debuff", "iconZoom", 100, 100, 200),
        buffIconShape = buffMetrics and buffMetrics.iconShape or Model.ReadLaneStyleString(unit, "buff", "iconShape", "RECTANGLE"),
        debuffIconShape = debuffMetrics and debuffMetrics.iconShape or Model.ReadLaneStyleString(unit, "debuff", "iconShape", "RECTANGLE"),
        buffRequestedIconShape = buffMetrics and buffMetrics.requestedIconShape,
        debuffRequestedIconShape = debuffMetrics and debuffMetrics.requestedIconShape,
        spacing = (buffMetrics and buffMetrics.spacing) or (debuffMetrics and debuffMetrics.spacing) or Model.ReadNumber(unit, "spacing", 2, 0, 64),
        stylePadding = (buffMetrics and buffMetrics.padding) or (debuffMetrics and debuffMetrics.padding) or Model.ReadNumber(unit, "stylePadding", 0, 0, 16),
        perRow = (buffMetrics and buffMetrics.perRow) or (debuffMetrics and debuffMetrics.perRow) or Model.ReadNumber(unit, "perRow", 12, 1, 40),
        buffPerRow = buffMetrics and buffMetrics.perRow or Model.ReadLanePerRow(unit, "buff"),
        debuffPerRow = debuffMetrics and debuffMetrics.perRow or Model.ReadLanePerRow(unit, "debuff"),
        buffSpacing = buffMetrics and buffMetrics.spacing or Model.ReadLaneSpacing(unit, "buff"),
        debuffSpacing = debuffMetrics and debuffMetrics.spacing or Model.ReadLaneSpacing(unit, "debuff"),
        maxBuffs = buffMetrics and buffMetrics.num or Model.ReadNumber(unit, "maxBuffs", 12, 0, 80),
        maxDebuffs = debuffMetrics and debuffMetrics.num or Model.ReadNumber(unit, "maxDebuffs", 12, 0, 80),
        growth = (buffMetrics and buffMetrics.growth) or (debuffMetrics and debuffMetrics.growth) or Model.ReadGrowth(unit),
        rowWrap = (buffMetrics and buffMetrics.rowWrap) or (debuffMetrics and debuffMetrics.rowWrap) or Model.ReadRowWrap(unit),
        buffGrowthX = buffMetrics and buffMetrics.growth or Model.ReadLaneGrowth(unit, "buff"),
        buffGrowthY = buffMetrics and buffMetrics.rowWrap or Model.ReadLaneRowWrap(unit, "buff"),
        debuffGrowthX = debuffMetrics and debuffMetrics.growth or Model.ReadLaneGrowth(unit, "debuff"),
        debuffGrowthY = debuffMetrics and debuffMetrics.rowWrap or Model.ReadLaneRowWrap(unit, "debuff"),
        showStackCount = Model.ReadBool(unit, "showStackCount", true),
        showCooldownText = Model.ReadBool(unit, "showCooldownText", true),
        buffShowStackCount = Model.ReadLaneStyleBool(unit, "buff", "showStackCount", true),
        buffShowCooldownText = Model.ReadLaneStyleBool(unit, "buff", "showCooldownText", true),
        buffShowCooldownSwipe = Model.ReadLaneStyleBool(unit, "buff", "showCooldownSwipe", true),
        buffCooldownSwipeReverse = Model.ReadLaneStyleBool(unit, "buff", "cooldownSwipeReverse", false),
        buffShowStealable = Model.ReadLaneStyleBool(unit, "buff", "showStealable", false),
        buffStealableStyle = Model.ReadLaneStyleString(unit, "buff", "stealableStyle", "BORDER_ICON"),
        debuffShowStackCount = Model.ReadLaneStyleBool(unit, "debuff", "showStackCount", true),
        debuffShowCooldownText = Model.ReadLaneStyleBool(unit, "debuff", "showCooldownText", true),
        debuffShowCooldownSwipe = Model.ReadLaneStyleBool(unit, "debuff", "showCooldownSwipe", true),
        debuffCooldownSwipeReverse = Model.ReadLaneStyleBool(unit, "debuff", "cooldownSwipeReverse", false),
        debuffTypeBorderMode = Model.ReadDebuffTypeBorderMode(unit),
        useDebuffTypeBorders = Model.ReadLaneStyleBool(unit, "debuff", "useDebuffTypeBorders", false),
        stackAnchor = (runtimeCfg and runtimeCfg.stackAnchor) or Model.ReadStackAnchor(unit),
        buffStackAnchor = Model.ReadLaneStackAnchor(unit, "buff"),
        debuffStackAnchor = Model.ReadLaneStackAnchor(unit, "debuff"),
        stackSize = Model.ReadNumber(unit, "stackTextSize", 14, 6, 40),
        stackX = Model.ReadNumber(unit, "stackTextOffsetX", -1, -2000, 2000),
        stackY = Model.ReadNumber(unit, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = Model.ReadNumber(unit, "cooldownTextSize", 14, 6, 40),
        cooldownAnchor = Model.ReadCooldownAnchor(unit),
        cooldownX = Model.ReadNumber(unit, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = Model.ReadNumber(unit, "cooldownTextOffsetY", 0, -2000, 2000),
        buffStackSize = Model.ReadLaneStyleNumber(unit, "buff", "stackTextSize", 14, 6, 40),
        buffStackX = Model.ReadLaneStyleNumber(unit, "buff", "stackTextOffsetX", -1, -2000, 2000),
        buffStackY = Model.ReadLaneStyleNumber(unit, "buff", "stackTextOffsetY", 1, -2000, 2000),
        buffCooldownSize = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextSize", 14, 6, 40),
        buffCooldownAnchor = Model.ReadLaneCooldownAnchor(unit, "buff"),
        buffCooldownX = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextOffsetX", 0, -2000, 2000),
        buffCooldownY = Model.ReadLaneStyleNumber(unit, "buff", "cooldownTextOffsetY", 0, -2000, 2000),
        buffCooldownDecimalSeconds = Model.ReadLaneStyleNumber(unit, "buff", "cooldownDecimalSeconds", 3, 0, 30),
        buffShowDurationBar = Model.ReadLaneStyleBool(unit, "buff", "showDurationBar", false),
        buffDurationBarHeight = Model.ReadLaneStyleNumber(unit, "buff", "durationBarHeight", 2, 1, 16),
        buffDurationBarDisplay = Model.ReadLaneDurationBarDisplay(unit, "buff"),
        buffDurationBarPosition = Model.ReadLaneDurationBarPosition(unit, "buff"),
        buffDurationBarDirection = Model.ReadLaneDurationBarDirection(unit, "buff"),
        debuffStackSize = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextSize", 14, 6, 40),
        debuffStackX = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetX", -1, -2000, 2000),
        debuffStackY = Model.ReadLaneStyleNumber(unit, "debuff", "stackTextOffsetY", 1, -2000, 2000),
        debuffCooldownSize = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextSize", 14, 6, 40),
        debuffCooldownAnchor = Model.ReadLaneCooldownAnchor(unit, "debuff"),
        debuffCooldownX = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetX", 0, -2000, 2000),
        debuffCooldownY = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownTextOffsetY", 0, -2000, 2000),
        debuffCooldownDecimalSeconds = Model.ReadLaneStyleNumber(unit, "debuff", "cooldownDecimalSeconds", 3, 0, 30),
        debuffShowDurationBar = Model.ReadLaneStyleBool(unit, "debuff", "showDurationBar", false),
        debuffDurationBarHeight = Model.ReadLaneStyleNumber(unit, "debuff", "durationBarHeight", 2, 1, 16),
        debuffDurationBarDisplay = Model.ReadLaneDurationBarDisplay(unit, "debuff"),
        debuffDurationBarPosition = Model.ReadLaneDurationBarPosition(unit, "debuff"),
        debuffDurationBarDirection = Model.ReadLaneDurationBarDirection(unit, "debuff"),
    }
end


local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v) end
    return out
end
local function Equal(a, b, path)
    path = path or "value"
    assert(type(a) == type(b), path .. " type changed")
    if type(a) ~= "table" then assert(a == b, path .. " changed"); return end
    for k, v in pairs(a) do Equal(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do assert(a[k] ~= nil, path .. " gained " .. tostring(k)) end
end
local group = assert(loader.Group(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua"))
local function Build(profile, metricMode, replaceOnCompile)
    local env = {}
    for key, value in pairs(_G) do env[key] = value end
    env._G = env
    env.MSUF_DB = Copy(profile)
    env.MSUF_GF_AuraFilter = nil
    local calls = { ensure = 0, bump = 0, requests = {}, previews = {}, scoped = {} }
    local A3 = {}
    local ns = { MSUF_Auras3 = A3 }
    env.MSUF_NS = ns
    function A3.EnsureDB()
        calls.ensure = calls.ensure + 1
        local auras = env.MSUF_DB.auras3
        return auras, auras.shared
    end
    function A3.NormalizeAuraIconShape(shape) return tostring(shape):upper() end
    if metricMode ~= "standalone" then
        function A3.ResolveUnitFrameConfig(unit)
            if replaceOnCompile then
                env.MSUF_DB = Copy(profile)
                env.MSUF_DB.auras3.perUnit = { [unit] = { layout = { iconSize = 41, buffGroupIconSize = 37 }, layoutShared = { buffShowCooldownText = false, debuffTypeBorderMode = "SYMBOL" } } }
            end
            return { enabled = metricMode == "full", stackAnchor = metricMode == "full" and "BOTTOMRIGHT" or nil }
        end
        function A3.BuildAuraLaneMetrics(cfg, kind)
            if kind:match("^custom") then return { enabled = false, kind = kind } end
            if metricMode == "partial" then return kind == "buff" and { enabled = true, size = 31, x = 0, y = false, growth = false } or nil end
            return { enabled = true, x = 0, y = 27, size = 30, anchor = "RIGHT", iconZoom = 130,
                iconShape = "CIRCLE", requestedIconShape = "FOLLOW_PORTRAIT", spacing = 0,
                padding = 3, perRow = 7, num = 11, growth = "LEFT", rowWrap = "UP" }
        end
    end
    A3.BumpRuntimeConfig = function() calls.bump = calls.bump + 1 end
    A3.RequestUnit = function(scope) calls.requests[#calls.requests + 1] = scope; return true end
    A3.RefreshUnit = function(scope) calls.requests[#calls.requests + 1] = scope end
    A3._NotifyAuraColdpathPreview = function(reason, scope) calls.previews[#calls.previews + 1] = { reason, scope } end
    env.InCombatLockdown = function() return false end
    for i = 1, #group do
        local chunk = assert(loadfile(group[i]))
        setfenv(chunk, env)
        chunk("MidnightSimpleUnitFrames", ns)
    end
    return A3.MenuModel, A3, env, calls
end

local profiles = {
    { auras3 = { shared = {}, showPlayer = true, showFocus = true } },
    { auras3 = { profileModelRevision = 2, shared = {}, showPlayer = false } },
    { auras3 = { profileModelRevision = 1, shared = {
        useDebuffTypeBorders = true, appearanceIconShapes = { buff = "circle", debuff = "rounded" },
    }, perUnit = {
        player = { overrideLayout = true, overrideSharedLayout = true,
            layout = { iconSize = 31, buffGroupIconSize = 34, debuffGroupIconSize = 28, spacing = 4, buffSpacing = 5,
                stackTextSize = 9, stackTextOffsetX = 2, stackTextOffsetY = 3, cooldownTextSize = 12, cooldownTextOffsetX = 1 },
            layoutShared = { buffShowCooldownText = false, useDebuffTypeBorders = true, debuffTypeBorderMode = "OFF" } },
        target = { layout = { buffSpacing = -4, debuffGroupIconSize = 500, buffStackTextSize = "21" },
            layoutShared = { growth = "invalid", buffGrowthX = "DOWN", debuffGrowthY = false, buffDurationBarDisplay = "ICON+BAR",
                debuffDurationBarDirection = "ELAPSED_TIME", cooldownTextAnchor = "RIGHT", buffStealableStyle = false } },
        boss1 = { layoutShared = { showBuffs = false, maxDebuffs = 0, dispelBorderMode = "ICON" } },
    } } },
}
local cases, oldReads, newReads = 0, 0, 0
for _, profile in ipairs(profiles) do
    for _, metricMode in ipairs({ "standalone", "partial", "full" }) do
        for _, replace in ipairs({ false, true }) do
            for _, unit in ipairs({ "player", "target", "focus", "boss", "boss3", "shared", "unknown" }) do
                local oldModel, oldA3, oldEnv, oldCalls = Build(profile, metricMode, replace)
                local newModel, newA3, newEnv, newCalls = Build(profile, metricMode, replace)
                for iteration = 1, 3 do
                    if iteration == 2 then
                        -- In-place writes are visible immediately; there is no cached context.
                        oldModel.WriteLaneStyleNumber(unit, "buff", "stackTextSize", 26, 6, 40)
                        newModel.WriteLaneStyleNumber(unit, "buff", "stackTextSize", 26, 6, 40)
                    elseif iteration == 3 then
                        oldEnv.MSUF_DB, newEnv.MSUF_DB = Copy(profile), Copy(profile)
                    end
                    oldCalls.ensure, newCalls.ensure = 0, 0
                    local expected = ReadThroughPublicGetters(oldModel, oldA3, unit)
                    local actual = newModel.ReadPreviewConfig(unit)
                    Equal(expected, actual, "preview")
                    Equal(oldEnv.MSUF_DB, newEnv.MSUF_DB, "SavedVariables")
                    Equal(oldCalls.requests, newCalls.requests, "refresh requests")
                    Equal(oldCalls.previews, newCalls.previews, "preview requests")
                    assert(newCalls.ensure == 2, "preview repeated DB resolution")
                    assert(oldCalls.ensure > newCalls.ensure, "preview removed no DB read work")
                    cases, oldReads, newReads = cases + 1, oldReads + oldCalls.ensure, newReads + newCalls.ensure
                end
            end
        end
    end
end

-- An unavailable DB on entry still returns nil. If runtime compilation drops
-- its DB provider, the existing public readers instead yield their defaults.
for _, unavailableAfterCompile in ipairs({ false, true }) do
    local oldModel, oldA3, oldEnv, oldCalls = Build(profiles[1], "partial", false)
    local newModel, newA3, newEnv, newCalls = Build(profiles[1], "partial", false)
    local function MakeUnavailable(A3, calls)
        A3.EnsureDB = function() calls.ensure = calls.ensure + 1; return nil, nil end
    end
    if unavailableAfterCompile then
        oldA3.ResolveUnitFrameConfig = function() MakeUnavailable(oldA3, oldCalls); return { enabled = false } end
        newA3.ResolveUnitFrameConfig = function() MakeUnavailable(newA3, newCalls); return { enabled = false } end
    else
        MakeUnavailable(oldA3, oldCalls)
        MakeUnavailable(newA3, newCalls)
    end
    Equal(ReadThroughPublicGetters(oldModel, oldA3, "target"), newModel.ReadPreviewConfig("target"), "unavailable DB")
    Equal(oldEnv.MSUF_DB, newEnv.MSUF_DB, "unavailable DB mutation")
end

-- Menu consumers without the new runtime API keep the old global fallback.
-- A runtime-provided narrow invalidator still uses the established refresh path.
local model, A3, _, calls = Build(profiles[1], "standalone", false)
for _, scope in ipairs({ "party", "raid", "mythicraid", "gf_party", "gf_raid", "gf_mythicraid", "group", "groups" }) do
    local before = calls.bump
    model.Apply(scope, "fallback")
    assert(calls.bump == before + 1 and calls.requests[#calls.requests] == scope)
end
A3.InvalidateGroupRuntimeConfig = function(scope) calls.scoped[#calls.scoped + 1] = scope; return true end
for _, scope in ipairs({ "party", "raid", "mythicraid", "gf_party", "gf_raid", "gf_mythicraid", "group", "groups" }) do
    local before = calls.bump
    model.Apply(scope, "scoped")
    assert(calls.bump == before and calls.scoped[#calls.scoped] == scope and calls.requests[#calls.requests] == scope)
end
local before = calls.bump
model.Apply("shared", "global appearance")
assert(calls.bump == before + 1, "shared appearance lost global invalidation")
A3.InvalidateGroupRuntimeConfig = function() return false end
before = calls.bump
model.Apply("party", "declined")
assert(calls.bump == before + 1, "declined group invalidation lost fallback")
print("PASS Auras3 preview read context: " .. cases .. " parity cases plus unavailable DB edges; DB reads " .. oldReads .. " -> " .. newReads .. "; 18 scoped/global Apply contracts")
