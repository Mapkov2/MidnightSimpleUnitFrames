-- startup_login_budget_smoke.lua <repoRoot> <flavor>
--
-- Startup budget for a /reload, the path behind the addon profiler's load
-- spike. Two deterministic measures, never wall-clock time: Lua VM
-- instructions (count hook, in thousands) and widget API calls (every call
-- into a frame, texture or font string method, plus CreateFrame: each one is
-- native work in the client). The flavor's real core load graph runs in the
-- fake client of tools/tests/client_world.lua with a real, anonymized Retail
-- SavedVariables file (tools/fixtures/profiles/sv/sv_retail_rev16_17.lua, the
-- character its corpus entry logs in with), in the client's order:
--
--   load         the main chunk of every core file (compiling excluded)
--   login        ADDON_LOADED, then PLAYER_LOGIN, which builds every unit frame
--   enter_world  the reload's PLAYER_ENTERING_WORLD (isInitialLogin false,
--                isReloadingUi true)
--   settle       every C_Timer callback those queued, first in first out,
--                including the ones they queue (next frame and settle retries)
--
-- Each measure runs in its own fresh world: counting widget calls wraps every
-- method, which would add Lua instructions to the other measure. A broken
-- build would look cheap, so each run must end with no handler or timer error
-- and with every unit frame spawned. The Options addon is load on demand and
-- stays unloaded, as at a real login. No live CPU claim: what a native call
-- costs in the client (frame creation, font and texture loads) is not modelled.
--
-- Limits are the measurement plus 2%. Raise one only with the measurement and
-- the reason in a dated line here; never to hide a regression.
-- 2026-10-16 (76eb2c69b): Mainline load 156k / 237 calls, login 1812k / 18985,
-- enter_world 1169k / 2061, settle 2302k / 8617; PLAYER_LOGIN creates 337
-- frames. The reload's PLAYER_ENTERING_WORLD used to recompile every unit spec
-- and reapply the PvP indicator elements of every frame although the
-- PLAYER_LOGIN build had compiled them against the same cached PvP context; it
-- now recompiles only for a changed context (uf_engine_client_gates_smoke pins
-- the rule): enter_world 1169k -> 824k instructions, 2061 -> 1981 calls (one
-- player alone; group frames repaint on top of that).

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (Mainline)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "startup_login_budget_smoke loads the real TOC graph; run it with plain Lua 5.1")

-- [flavor] = { [phase] = { k instructions, widget API calls } }
local BUDGETS = {
    Mainline = {
        load = { 160, 242 }, login = { 1849, 19365 }, enter_world = { 841, 2021 }, settle = { 2349, 8790 },
    },
}
local SV_FIXTURE = "tools/fixtures/profiles/sv/sv_retail_rev16_17.lua"
local LOGIN_CHARACTER, LOGIN_REALM = "Char16", "Realm03"
local PHASES = { "load", "login", "enter_world", "settle" }

local budget = assert(BUDGETS[flavor], "no startup budget for flavor " .. flavor)

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local Emulator = assert(loadfile(root .. "/tools/tests/encoding_util_emulator.lua"))()

-- The fake client answers the core TOC's own metadata, as the real client
-- does: the unit-frame framework names its frames after X-MSUF-UnitFrames-Prefix
-- ("MSUF_player"), and the harness keeps addon-owned globals nil until the
-- frame that owns the name exists.
local function ReadTocMetadata(client)
    local metadata = {}
    local path = root .. "/" .. World.CoreTOC(client.tocSuffix or flavor)
    local handle = assert(io.open(path, "rb"), "missing core TOC " .. path)
    for line in handle:read("*a"):gmatch("[^\r\n]+") do
        local key, value = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)%s*$")
        if key and metadata[key] == nil then metadata[key] = value end
    end
    handle:close()
    return metadata
end

local function FormatNumber(value) return tostring(tonumber(value) or 0) end
local function Noop() end
local function False() return false end

-- One fresh fake client, set up the way a login sees it.
local function NewWorld()
    local world = World.New(root, flavor)
    local env = world.env
    local tocMetadata = ReadTocMetadata(world.client)
    local fallback = env.C_AddOns.GetAddOnMetadata
    env.C_AddOns.GetAddOnMetadata = function(addon, field)
        if addon == "MidnightSimpleUnitFrames" and tocMetadata[field] ~= nil then return tocMetadata[field] end
        return fallback(addon, field)
    end
    env.GetAddOnMetadata = env.C_AddOns.GetAddOnMetadata

    -- Globals the login handlers read that the harness leaves as stubs (the
    -- set tools/profile_corpus_golden.lua installs), plus the login character.
    env.MAX_TOTEMS, env.MAX_BOSS_FRAMES = 4, 5
    env.TotemFrame = false
    env.time = function() return 1790000000 end
    env.GetServerTime = env.time
    env.C_EncodingUtil = Emulator.New()
    env.Enum = setmetatable({
        CompressionMethod = Emulator.CompressionMethod,
        CompressionLevel = Emulator.CompressionLevel,
    }, { __index = function() return World.Stub end })
    env.UnitName = function() return LOGIN_CHARACTER, nil end
    env.GetRealmName = function() return LOGIN_REALM end
    env.GetScreenWidth = function() return 1920 end
    env.GetScreenHeight = function() return 1080 end
    env.GetPhysicalScreenSize = function() return 1920, 1080 end
    -- An idle player at full health; class power reads a five-point maximum.
    env.UnitHealth, env.UnitHealthMax = function() return 100 end, function() return 100 end
    env.UnitPower, env.UnitPowerMax = function() return 0 end, function() return 5 end
    -- Blizzard's number formatters, which the unit texts capture at load.
    env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.BreakUpLargeNumbers = FormatNumber, FormatNumber, FormatNumber

    -- Widget methods the build calls that the shared stub does not model. Each
    -- answers what an idle client answers.
    local methods = world.widgets.Methods
    for _, name in ipairs({ "SetRoundLayoutToNearestPixel", "SetScaleAnimationMode", "SetTextureSliceMargins",
        "SetTextureSliceMode", "SetToFinalAlpha", "SetVertexColorFromBoolean" }) do
        if methods[name] == nil then methods[name] = Noop end
    end
    if methods.IsForbidden == nil then methods.IsForbidden = False end
    if methods.GetAllowRadialWheel == nil then methods.GetAllowRadialWheel = False end
    if methods.GetTargetInfo == nil then methods.GetTargetInfo = Noop end
    if methods.GetScaledRect == nil then
        methods.GetScaledRect = function(self)
            return rawget(self, "left") or 0, rawget(self, "bottom") or 0,
                rawget(self, "width") or 0, rawget(self, "height") or 0
        end
    end
    -- A frame parented to a global the harness does not model has the
    -- permissive stub as its parent; stop the effective-scale walk at the first
    -- non-widget (as tools/profile_corpus_golden.lua does).
    methods.GetEffectiveScale = function(self)
        local scale, parent, seen = rawget(self, "scale") or 1, rawget(self, "parent"), {}
        while type(parent) == "table" and rawget(parent, "__env") ~= nil and not seen[parent] do
            seen[parent] = true
            scale = scale * (rawget(parent, "scale") or 1)
            parent = rawget(parent, "parent")
        end
        return scale
    end
    return world
end

-- Counts every widget method call and CreateFrame call of a world.
local function CountWidgetCalls(world)
    local counter = { calls = 0 }
    local methods = world.widgets.Methods
    local names = {}
    for name, fn in pairs(methods) do
        if type(fn) == "function" then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do
        local fn = methods[name]
        methods[name] = function(...)
            counter.calls = counter.calls + 1
            return fn(...)
        end
    end
    local createFrame = world.env.CreateFrame
    world.env.CreateFrame = function(...)
        counter.calls = counter.calls + 1
        return createFrame(...)
    end
    return counter
end

-- One login: the four phases of the header, measured by `mode`
-- ("instructions" or "calls"). Returns the per-phase measure and facts.
local function RunStartup(mode)
    local world = NewWorld()
    local env = world.env
    local counter = mode == "calls" and CountWidgetCalls(world) or nil
    local measured, failures = {}, {}
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    local function Measure(phase, fn)
        if counter then
            local before = counter.calls
            fn()
            measured[phase] = counter.calls - before
            return
        end
        ticks = 0
        debug.sethook(Tick, "", 1000)
        fn()
        debug.sethook()
        measured[phase] = ticks
    end
    -- The client isolates every frame script and timer: one failure does not
    -- stop the others. Collect them all and fail the run below.
    local function Traceback(message)
        return tostring(message) .. " | " .. debug.traceback("", 2):gsub("%s+", " ")
    end
    local eventArgs
    local function Dispatch(event, ...)
        eventArgs = { ... }
        local frames = world.widgets.frames
        for index = 1, #frames do
            local frame = frames[index]
            local events = rawget(frame, "events")
            local scripts = rawget(frame, "scripts")
            local handler = scripts and scripts.OnEvent
            if handler and events and (events[event] or events["*"]) then
                local ok, message = xpcall(function() return handler(frame, event, unpack(eventArgs)) end, Traceback)
                if not ok then failures[#failures + 1] = event .. ": " .. tostring(message) end
            end
        end
    end
    local timersRun = 0
    local function RunTimers()
        local timers = world.widgets.timers
        while #timers > 0 and timersRun < 2000 do
            local entry = table.remove(timers, 1)
            timersRun = timersRun + 1
            if not entry.cancelled and type(entry.callback) == "function" then
                local ok, message = xpcall(entry.callback, Traceback)
                if not ok then failures[#failures + 1] = "timer: " .. tostring(message) end
            end
        end
        Check(#timers == 0, "the startup timers did not settle within 2000 callbacks")
    end

    local client = world.client
    local gameType = client.isForever and "camelot" or (client.isClassic and nil or "standard")
    local paths = World.Graph(root, World.CoreTOC(client.tocSuffix or flavor), env.GetLocale(), gameType)
    Check(#paths > 200, "the core load graph is unexpectedly small: " .. #paths .. " files")
    local chunks = {}
    for index = 1, #paths do
        local chunk, compileError = loadfile(paths[index])
        Check(chunk ~= nil, "does not compile: " .. tostring(compileError))
        setfenv(chunk, env)
        chunks[index] = chunk
    end
    Measure("load", function()
        for index = 1, #chunks do
            world.loading = paths[index]
            local ok, message = pcall(chunks[index], "MidnightSimpleUnitFrames", world.core)
            if not ok then failures[#failures + 1] = "load " .. paths[index] .. ": " .. tostring(message) end
        end
        world.loading = nil
    end)
    Check(#failures == 0, "the core graph failed to load: " .. tostring(failures[1]))

    for name, value in pairs(Corpus.LoadSavedVariablesFixture(root, SV_FIXTURE)) do rawset(env, name, value) end
    Measure("login", function()
        Dispatch("ADDON_LOADED", "MidnightSimpleUnitFrames", false)
        Dispatch("PLAYER_LOGIN")
    end)
    Measure("enter_world", function() Dispatch("PLAYER_ENTERING_WORLD", false, true) end)
    Measure("settle", RunTimers)

    Check(#failures == 0, mode .. " run: " .. #failures .. " startup failure(s); first: " .. tostring(failures[1]))
    local UF = world.core.UF
    Check(UF and UF.spawned == true and UF.initialized == true, "PLAYER_LOGIN did not spawn the unit frames")
    local frames = 0
    for _ in pairs(UF.frames or {}) do frames = frames + 1 end
    Check(frames >= 15, "PLAYER_LOGIN built only " .. frames .. " unit frames")
    return measured, { files = #paths, frames = frames, timers = timersRun }
end

local instructions, facts = RunStartup("instructions")
local calls = RunStartup("calls")
local over = {}
for _, phase in ipairs(PHASES) do
    local limit = budget[phase]
    print(string.format("%s %-12s %6dk instructions (budget %dk), %6d widget calls (budget %d)",
        flavor, phase, instructions[phase], limit[1], calls[phase], limit[2]))
    if instructions[phase] > limit[1] then
        over[#over + 1] = string.format("%s %dk > %dk instructions", phase, instructions[phase], limit[1])
    end
    if calls[phase] > limit[2] then
        over[#over + 1] = string.format("%s %d > %d widget calls", phase, calls[phase], limit[2])
    end
end
Check(#over == 0, "startup budget exceeded: " .. table.concat(over, ", "))
print(string.format("PASS startup login budget %s: %d core files, %d unit frames, %d startup timers",
    flavor, facts.files, facts.frames, facts.timers))
