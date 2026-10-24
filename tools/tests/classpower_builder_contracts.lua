-- Load the real client graph up to the controller, then break internal load contracts.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
local controller = root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Controller.lua"
local cases = {
    { "CORE", "BUILD", "CP_Create" }, { "CORE", "LAYOUT", "CP_Layout" },
    { "CORE", "PRESENTATION", "CP_ApplyFont" }, { "CORE", "ALT_MANA", "AM_UpdateValue" },
    { "CORE", "CONTROLLER_CONFIG", "GetClassPowerType" }, { "CORE", "CONTROLLER_COLORS", "ResolveClassPowerColor" },
    { "CORE", "CONTROLLER_AURAS", "Get" }, { "CORE", "CONTROLLER_SURFACE", "ResolveEbonHost" },
    { "CORE", "CONTROLLER_TICKER", "SyncRuntimeOnUpdates" }, { "CORE", "CONTROLLER_EVENTS", "RefreshEventBindings" },
    { "CORE", "PLAYER_HP", "Refresh" }, { "CORE", "PLAYER_HP_REQUIRE" },
    { "MODE", "SEGMENTED", "Update" }, { "MODE", "FRACTIONAL", "Update" },
    { "MODE", "AURA", "UpdateSingle" }, { "MODE", "CONTINUOUS", "Update" },
    { "MODE", "STAGGER", "RuntimeTick" }, { "MODE", "RUNE", "Update" }, { "MODE", "TIMER", "Update" },
    { "FEATURE", "SPECIALS", "OnWarlockCastStart" }, { "FEATURE", "RUNTIME", "OnPowerUpdate" },
}
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
    local w = World.New(root, flavor)
    local paths = World.Graph(root, World.CoreTOC(w.client.tocSuffix or flavor), w.env.GetLocale(), w.client.isForever and "camelot" or nil)
    for _, path in ipairs(paths) do
        if path == controller then break end
        local ok, err = w:LoadFile(path, "MidnightSimpleUnitFrames", w.core)
        assert(ok, path .. ": " .. tostring(err))
    end
    local k = w.core.Require("MSUF_CP_CONST", "builder test")
    local function Load()
        w.core.PublicGlobals.__MSUF_ClassPower_Loaded = nil
        return w:LoadFile(controller, "MidnightSimpleUnitFrames", w.core)
    end
    local ok, err = Load()
    assert(ok, flavor .. " intact controller failed: " .. tostring(err))
    local clientCases = {}
    for _, case in ipairs(cases) do clientCases[#clientCases + 1] = case end
    if not w.core.Client.IsClassic then clientCases[#clientCases + 1] = { "CORE", "EBON_MIGHT", "SetActive" } end
    for _, case in ipairs(clientCases) do
        local registry = k.BuilderRegistry("MSUF_CP_" .. case[1] .. "_BUILDERS")
        local name, field = case[2], case[3]
        local original = assert(registry[name], name)
        local variants = { "missing", "nil return", "wrong return" }
        if field then variants[#variants + 1] = "missing field" end
        for _, variant in ipairs(variants) do
            if variant == "missing" then registry[name] = nil
            elseif variant == "nil return" then registry[name] = function() return nil end
            elseif variant == "wrong return" then registry[name] = function() return 5 end
            else registry[name] = function(env)
                local value = original(env)
                local copy = {}
                for key, entry in pairs(value) do copy[key] = entry end
                copy[field] = nil
                return copy
            end end
            local loaded, message = Load()
            registry[name] = original
            assert(not loaded and tostring(message):find(name, 1, true),
                flavor .. " " .. name .. " " .. variant .. " was not diagnosed by name: " .. tostring(message))
        end
    end
    local mode = k.BuilderRegistry("MSUF_CP_MODE_BUILDERS")
    if w.core.Client.SupportsClassResource("IRONFUR") then
        local ironfur, core = mode.IRONFUR, k.BuilderRegistry("MSUF_CP_CORE_BUILDERS")
        local build, cp, builds = core.BUILD, nil, 0
        core.BUILD = function(env) cp = env.CP return build(env) end
        w.env.UnitClass = function() return "Druid", "DRUID", 11 end
        mode.IRONFUR = nil
        local loaded, message = Load()
        assert(not loaded and tostring(message):find("IRONFUR", 1, true), "missing lazy Ironfur builder accepted")
        mode.IRONFUR = function(env) builds = builds + 1 return ironfur(env) end
        assert(Load())
        assert(builds == 0 and cp.ironfur == nil and cp.BuildIronfur, "default-off Ironfur was instantiated")
        for _, variant in ipairs({ "nil return", "missing Update" }) do
            mode.IRONFUR = function(env)
                if variant == "nil return" then return nil end
                local value = ironfur(env)
                value.Update = nil
                return value
            end
            assert(Load())
            local built, failure = pcall(cp.BuildIronfur)
            assert(not built and tostring(failure):find("IRONFUR", 1, true), "bad lazy instance accepted")
        end
        mode.IRONFUR = ironfur
        assert(Load())
        local frames = #w.widgets.frames
        local instance = cp.BuildIronfur()
        assert(type(instance.Update) == "function" and #w.widgets.frames == frames + 2, "first Ironfur build contract failed")
        core.BUILD = build
    end
    -- Lazy Ironfur must stay lazy; its renderer is bound at first enabled refresh.
    local runners = { Segmented = function() end, Fractional = function() end, Rune = function() end,
        AuraSegmented = function() end, AuraSingle = function() end, Continuous = function() end,
        Timer = function() end, Stagger = function() end, NativeAura = function() end, SignedContinuous = function() end }
    runners.Segmented = nil
    local bound, message = pcall(k.BindModeRunners, runners)
    assert(not bound and tostring(message):find("Segmented", 1, true), "missing renderer accepted")
    print("classpower_builder_contracts: PASS " .. flavor)
end
