-- forever_arena_zero_smoke.lua
-- WoW Forever runs the Mainline TOC/XML load graph with no arena units:
-- Game/Shared/Initialize.lua publishes MSUF.Client.MaxArenaOpponents 0,
-- MSUF_MAX_ARENA_FRAMES 0 and SupportsUnit("arena") false there. Before
-- Forever, only the Classic shadows ever ran with zero arena slots.
--
-- The smoke loads the whole core and Options Mainline graph twice, each in its
-- own sandbox of permissive WoW stubs: once as Midnight and once as Forever
-- (the Blizzard_Game camelot marker). It proves:
--   Load:    Forever raises in no chunk where Midnight does not raise the same
--            way, so zero arena slots add no load-time error to the graph.
--   Engine:  Midnight manages arena1-3; Forever manages no arena unit and
--            keeps focus and boss1-5.
--   Events:  Forever subscribes to no arena event; delivering the login, world
--            and arena events raises nothing on Forever that Midnight does not
--            raise the same way.
--   Castbars: the arena castbar pool and its previews are never built on
--            Forever, and a castbar settings refresh there keeps the
--            profile's arena castbar backend.
--   Menu2:   Forever registers no Arena unit page and offers no Arena copy
--            target (Unit page list, Copy To popup); Midnight keeps both.
-- Run with plain Lua 5.1 and the repo root as arg 1. Not through the aura test
-- driver: it replaces loadfile and io.open, and this smoke loads the real graph.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "forever_arena_zero_smoke loads the real TOC graph; run it with plain Lua 5.1, not auras3_test_driver.lua")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Normalize(path)
    local prefix = path:sub(1, 1) == "/" and "/" or ""
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then table.remove(parts)
        elseif part ~= "." then parts[#parts + 1] = part end
    end
    return prefix .. table.concat(parts, "/")
end

local function Read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- Lua paths in load order for one TOC, following XML <Script>/<Include> files.
local function LoadGraph(toc)
    local ordered, seen = {}, {}
    local function visit(path)
        path = Normalize(path)
        if path:match("%.lua$") then
            if not seen[path] then seen[path] = true; ordered[#ordered + 1] = path end
            return
        end
        local source = Read(path)
        local directory = assert(path:match("^(.*)/"))
        if path:match("%.xml$") then
            for child in source:gmatch('<[%w:]+%s+file="([^"]+)"') do visit(directory .. "/" .. child) end
        else
            for line in source:gmatch("[^\n]+") do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" and line:sub(1, 1) ~= "#" then visit(directory .. "/" .. line) end
            end
        end
    end
    visit(root .. "/" .. toc)
    return ordered
end

local CORE_TOC = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc"
local OPTIONS_TOC = "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_Mainline.toc"
local corePaths, optionsPaths = LoadGraph(CORE_TOC), LoadGraph(OPTIONS_TOC)
Check(#corePaths > 100 and #optionsPaths > 50, "Mainline load graph is unexpectedly small")

-- A callable, indexable stand-in for every WoW API the harness does not model.
-- Arithmetic yields 0 and concatenation drops the stub, so most load-time code
-- runs; the few chunks that still raise are compared between both runs.
local Stub
local stubMeta = {
    __index = function() return Stub end,
    __newindex = function() end,
    __call = function() return Stub end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __unm = function() return 0 end,
    __pow = function() return 0 end,
    __concat = function(a, b)
        return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "")
    end,
}
Stub = setmetatable({}, stubMeta)

local realG = _G
local realGetfenv = getfenv
-- Only the Lua 5.1 standard library enters a sandbox, so globals a test driver
-- installed in this process cannot change what either run sees.
local STANDARD_GLOBALS = {
    "assert", "collectgarbage", "error", "gcinfo", "getmetatable", "ipairs", "load", "loadfile",
    "loadstring", "newproxy", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
    "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "_VERSION", "coroutine", "debug", "io", "math", "os", "string", "table",
}

local function NewSandbox(forever)
    local env = {}
    for i = 1, #STANDARD_GLOBALS do env[STANDARD_GLOBALS[i]] = realG[STANDARD_GLOBALS[i]] end
    env._G = env
    env.getfenv = function(level)
        if level == 0 then return env end
        return realGetfenv(level)
    end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.table = setmetatable({ wipe = env.wipe }, { __index = realG.table })
    env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
    env.format, env.strfind, env.strmatch, env.gsub, env.strsub = string.format, string.find, string.match, string.gsub, string.sub
    env.strlower, env.strupper, env.strlen, env.strrep = string.lower, string.upper, string.len, string.rep
    env.strbyte, env.strchar = string.byte, string.char
    env.floor, env.ceil, env.abs, env.max, env.min, env.sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
    env.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strsplit = function(sep, s)
        local out = {}
        for piece in (tostring(s or "") .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
    env.Mixin = function(o, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if type(mixin) == "table" then for k, v in pairs(mixin) do o[k] = v end end
        end
        return o
    end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.GetLocale = function() return "enUS" end
    env.GetTime = function() return 100 end
    env.InCombatLockdown = function() return false end
    env.UnitAffectingCombat = function() return false end
    env.UnitExists = function() return false end
    env.debugprofilestop = function() return 0 end
    env.issecretvalue = function() return false end
    env.hooksecurefunc = function() end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitName = function() return "Tester" end
    env.GetRealmName = function() return "Realm" end
    env.IsLoggedIn = function() return false end
    env.SlashCmdList = {}
    env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_CLASSIC = 1, 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, env.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    env.WOW_PROJECT_ID = 1
    -- The untagged Mainline TOC: no X-MSUF-Client value.
    env.C_AddOns = { GetAddOnMetadata = function() return nil end }
    env.GetBuildInfo = function() return "test", "1", "test", forever and 16001 or 120105 end
    -- Blizzard_Game defines this only for the camelot game type (Forever).
    if forever then env.GameEvent = { RegisterCamelotEvents = function() end } end

    local absent = { GameEvent = true, MAX_ARENA_ENEMIES = true, C_GameRules = true, C_EventUtils = true }
    setmetatable(env, { __index = function(_, key)
        if absent[key] or (type(key) == "string" and (key:find("^MSUF") or key == "LibStub")) then return nil end
        return Stub
    end })
    return env
end

local function LoadAddOn(env, addonName, paths, namespace, failures)
    local prefix = root .. "/"
    for i = 1, #paths do
        local relative = paths[i]:sub(#prefix + 1)
        local chunk, compileError = loadfile(paths[i])
        Check(chunk ~= nil, "Mainline Lua does not compile: " .. tostring(compileError))
        setfenv(chunk, env)
        local ok, runError = pcall(chunk, addonName, namespace)
        if not ok then
            failures[#failures + 1] = relative .. " :: " .. tostring(runError):gsub("^.-:%d+: ", "")
        end
    end
end

local function Run(forever)
    local env = NewSandbox(forever)
    local core, options, failures = {}, {}, {}
    LoadAddOn(env, "MidnightSimpleUnitFrames", corePaths, core, failures)
    LoadAddOn(env, "MidnightSimpleUnitFrames_Options", optionsPaths, options, failures)
    return { env = env, core = core, failures = failures }
end

local midnight, forever = Run(false), Run(true)

-- Load ---------------------------------------------------------------------
local label = { [midnight] = "Midnight", [forever] = "Forever" }
for _, run in ipairs({ midnight, forever }) do
    local client = run.core.Client
    Check(type(client) == "table", label[run] .. ": Game/Shared/Initialize.lua built no client")
    Check(client.Family == "Mainline" and client.IsRetail == true, label[run] .. ": not the Mainline build")
    Check(client.IsForever == (run == forever), label[run] .. ": wrong Forever fact")
end
Check(midnight.core.Client.MaxArenaOpponents == 3 and midnight.env.MSUF_MAX_ARENA_FRAMES == 3,
    "Midnight lost its three arena slots")
Check(forever.core.Client.MaxArenaOpponents == 0 and forever.env.MSUF_MAX_ARENA_FRAMES == 0,
    "Forever arena slots are not zero")
Check(forever.core.Client.SupportsUnit("arena1") == false and midnight.core.Client.SupportsUnit("arena1") == true,
    "arena unit support does not follow the client")
-- Stubbed APIs make a few chunks raise in both runs. Forever may skip arena
-- work Midnight does, but must never raise where Midnight does not.
local midnightFailures = {}
for i = 1, #midnight.failures do midnightFailures[midnight.failures[i]] = true end
for i = 1, #forever.failures do
    Check(midnightFailures[forever.failures[i]] == true,
        "Forever raised at load where Midnight does not: " .. forever.failures[i]
            .. "\nMidnight load failures:\n  " .. table.concat(midnight.failures, "\n  "))
end
-- The harness must reach the consumers below; a broad stub failure would hide them.
Check(#forever.failures <= 3, "permissive load harness failed in too many chunks:\n  " .. table.concat(forever.failures, "\n  "))

-- Engine -------------------------------------------------------------------
local function ManagedArenaUnits(run)
    local uf = run.core.UF
    Check(type(uf) == "table" and type(uf.unitOrder) == "table", label[run] .. ": UF.unitOrder missing")
    local count = 0
    for _, unit in ipairs(uf.unitOrder) do
        if unit:match("^arena%d+$") then count = count + 1 end
    end
    for _, unit in ipairs({ "focus", "boss1", "boss5" }) do
        Check(uf.IsManagedUnit(unit) == true, label[run] .. ": lost managed unit " .. unit)
    end
    return count
end
Check(ManagedArenaUnits(midnight) == 3 and midnight.core.UF.IsManagedUnit("arena3") == true,
    "Midnight does not manage arena1-3")
Check(ManagedArenaUnits(forever) == 0 and forever.core.UF.IsManagedUnit("arena1") == false,
    "Forever manages arena units")

-- Events -------------------------------------------------------------------
local ARENA_EVENTS = { "ARENA_OPPONENT_UPDATE", "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "PVP_MATCH_STATE_CHANGED" }
local function Handlers(run, event)
    local bus = run.env.MSUF_EventBus
    Check(type(bus) == "table" and type(bus.handlers) == "table", label[run] .. ": EventBus missing")
    local ev = bus.handlers[event]
    local live = {}
    for i = 1, ev and #ev.list or 0 do
        if ev.list[i].fn then live[#live + 1] = ev.list[i] end
    end
    return live
end
local function HasHandler(run, event, key)
    for _, handler in ipairs(Handlers(run, event)) do
        if handler.key == key then return true end
    end
    return false
end
Check(HasHandler(midnight, "ARENA_OPPONENT_UPDATE", "MSUF_ARENA_CASTBARS_OPPONENT")
        and HasHandler(midnight, "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "MSUF_ARENA_CASTBARS_PREP"),
    "Midnight arena castbars stopped listening to the arena opponent events")
for _, event in ipairs(ARENA_EVENTS) do
    Check(#Handlers(forever, event) == 0, "Forever subscribes to " .. event)
end
-- Deliver the login, world and arena events to every subscriber in both runs.
-- Stubbed APIs make some handlers raise; Forever must raise nothing Midnight
-- does not raise the same way.
local function Deliver(run, event)
    local errors = {}
    for _, handler in ipairs(Handlers(run, event)) do
        local ok, message = pcall(handler.fn, event, "arena1")
        if not ok then errors[handler.key] = tostring(message):gsub("^.-:%d+: ", "") end
    end
    return errors
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ARENA_OPPONENT_UPDATE",
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS", "PVP_MATCH_STATE_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    local midnightErrors, foreverErrors = Deliver(midnight, event), Deliver(forever, event)
    for key, message in pairs(foreverErrors) do
        Check(midnightErrors[key] == message, "Forever " .. event .. " handler " .. key .. " raised: " .. message)
    end
end

-- Castbars -----------------------------------------------------------------
for _, name in ipairs({ "MSUF_ApplyArenaCastbarsEnabled", "MSUF_UpdateArenaCastbarPreview",
    "MSUF_ApplyArenaCastbarPositionSetting" }) do
    local fn = forever.env[name]
    Check(type(fn) == "function", "Forever lost the arena castbar export " .. name)
    local ok, message = pcall(fn)
    Check(ok, "Forever " .. name .. " raised: " .. tostring(message))
end
-- Every castbar settings refresh runs MSUF_ApplyArenaCastbarsEnabled. On
-- Forever it must leave the profile's arena castbar choice as Midnight stored it.
local foreverGeneral = { arenaCastbarBackend = "MSUF", enableArenaCastbar = true }
forever.env.MSUF_DB = { general = foreverGeneral }
local applied, applyError = pcall(forever.env.MSUF_ApplyArenaCastbarsEnabled)
forever.env.MSUF_DB = nil
Check(applied, "Forever arena castbar apply raised with a profile: " .. tostring(applyError))
Check(foreverGeneral.arenaCastbarBackend == "MSUF" and foreverGeneral.enableArenaCastbar == true,
    "Forever rewrote the profile's arena castbar backend to " .. tostring(foreverGeneral.arenaCastbarBackend))
Check(rawget(forever.env, "MSUF_ArenaCastbars") == nil, "Forever built the arena castbar pool")
Check(rawget(forever.env, "MSUF_ArenaCastbar1") == nil and rawget(forever.env, "MSUF_ArenaCastbarPreview1") == nil,
    "Forever built an arena castbar or preview")

-- Menu2 --------------------------------------------------------------------
local function UnitPage(run)
    local menu = run.core.MSUF2
    Check(type(menu) == "table" and type(menu.pages) == "table", label[run] .. ": Menu2 pages missing")
    Check(type(menu.UnitPage) == "table" and type(menu.UnitPage.UNIT_PAGES) == "table",
        label[run] .. ": Unit page contract missing")
    return menu, menu.UnitPage
end
local function HasCopyTarget(targets, unit)
    for i = 1, #targets do
        if targets[i].value == unit then return true end
    end
    return false
end
for _, run in ipairs({ midnight, forever }) do
    local menu, unitPage = UnitPage(run)
    local arena = run == midnight
    Check((menu.pages.uf_arena ~= nil) == arena and (unitPage.UNIT_PAGES.uf_arena ~= nil) == arena,
        label[run] .. ": Arena unit page registration")
    for _, key in ipairs({ "uf_player", "uf_focus", "uf_boss", "uf_focustarget" }) do
        Check(menu.pages[key] ~= nil and unitPage.UNIT_PAGES[key] ~= nil, label[run] .. ": lost unit page " .. key)
    end
    Check(HasCopyTarget(unitPage.UNIT_COPY_TARGETS, "arena") == arena, label[run] .. ": Arena copy target")
    Check(HasCopyTarget(unitPage.UNIT_COPY_TARGETS, "boss") and HasCopyTarget(unitPage.UNIT_COPY_TARGETS, "focus"),
        label[run] .. ": lost the Boss or Focus copy target")
    Check(unitPage.DefaultCopyTarget("player") == "target", label[run] .. ": default copy target moved")
    Check(menu.SupportsUnitPage("uf_arena") == arena, label[run] .. ": Arena page search gate")
end

-- The Unit page Copy To popup reads UF_COPY_TARGET_ORDER, a file-local list.
local sections = Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
local orderStart = assert(sections:find("local UF_COPY_TARGET_ORDER =", 1, true), "Copy To target order missing")
local orderStop = assert(sections:find("local UF_COPY_TARGET_WIDTHS", orderStart, true), "Copy To target order boundary missing")
local orderSource = "local MSUF, M = ...\n" .. sections:sub(orderStart, orderStop - 1) .. "\nreturn UF_COPY_TARGET_ORDER"
for _, run in ipairs({ midnight, forever }) do
    local chunk = assert(loadstring(orderSource, "@UF_COPY_TARGET_ORDER"))
    local order = chunk(run.core, run.core.MSUF2)
    local seen = {}
    for i = 1, #order do seen[order[i]] = true end
    Check((seen.arena == true) == (run == midnight), label[run] .. ": Arena Copy To target")
    Check(seen.boss and seen.focus and seen.all and #order == (run == midnight and 9 or 8),
        label[run] .. ": Copy To targets beyond Arena changed")
end
-- A namespace without a client table (Retail smoke harnesses) keeps all targets.
local plain = assert(loadstring(orderSource, "@UF_COPY_TARGET_ORDER"))({}, forever.core.MSUF2)
Check(#plain == 9, "Copy To targets changed without a client table")

print(string.format("forever_arena_zero_smoke: ok (%d core + %d Options Lua files, %d shared stub failures)",
    #corePaths, #optionsPaths, #forever.failures))
