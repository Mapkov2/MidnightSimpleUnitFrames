-- client_world.lua -- a fake WoW client for whole-graph load tests.
--
-- Two jobs, both reusable by any smoke that wants to boot the addon offline:
--
--   1. Graph()  resolves a TOC into the exact ordered list of Lua files the
--      client loads, expanding the XML embed manifests the TOCs reference.
--   2. New()    builds one sandbox that behaves like the client of a given
--      flavor: project globals, interface number and the X-MSUF-Client TOC tag
--      come from tools/classic-client-matrix.tsv, so a new matrix row is picked
--      up without touching this file.
--
-- The widget and timer surface is .github/scripts/msuf_test_stubs.lua; this
-- file only adds the non-widget client APIs the load graph actually reaches.
--
-- Unknown globals: every read of a global this harness does not model is
-- recorded by name and answered with a permissive stub, so a file that reads an
-- API nobody modelled is *visible* (world.unknown) instead of silently nil.
-- Globals the addon owns (MSUF*) and the vendored libraries stay nil, because
-- those must read nil until the file that creates them has run.
--
-- Run with Lua 5.1 (the client dialect); loadstring/setfenv/unpack are used.

local World = {}

--------------------------------------------------------------------------
-- Paths and files
--------------------------------------------------------------------------

local function Normalize(path)
    local prefix = path:sub(1, 1) == "/" and "/" or ""
    local parts = {}
    for part in tostring(path):gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then table.remove(parts)
        elseif part ~= "." then parts[#parts + 1] = part end
    end
    return prefix .. table.concat(parts, "/")
end
World.Normalize = Normalize

local function Read(path)
    local file = assert(io.open(path, "rb"), "client_world: missing file " .. tostring(path))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
World.Read = Read

-- Ordered Lua load list for one TOC. A TOC line may name a Lua file or an XML
-- embed manifest; an XML manifest names further XML files and Lua scripts. The
-- client loads each file once, in first-mention order.
function World.Graph(root, tocRelative, locale)
    local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
    local ordered, seen, active = {}, {}, {}
    local function visit(path)
        path = Normalize(path)
        if path:match("%.lua$") then
            if not seen[path] then
                seen[path] = true
                ordered[#ordered + 1] = path
            end
            return
        end
        assert(not active[path], "client_world: manifest cycle at " .. path)
        active[path] = true
        local source = Read(path)
        local directory = assert(path:match("^(.*)/"), "client_world: no directory for " .. path)
        if path:match("%.xml$") then
            for child in source:gmatch('<[%w:]+%s+file="([^"]+)"') do visit(directory .. "/" .. child) end
        else
            for line in source:gmatch("[^\n]+") do
                local reference = manifest.TocReference(line, locale)
                if reference then visit(directory .. "/" .. reference) end
            end
        end
        active[path] = nil
    end
    visit(Normalize(root .. "/" .. tocRelative))
    return ordered
end

function World.CoreTOC(flavor)
    return "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. flavor .. ".toc"
end

function World.OptionsTOC(flavor)
    return "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_" .. flavor .. ".toc"
end

--------------------------------------------------------------------------
-- Client facts, from tools/classic-client-matrix.tsv
--------------------------------------------------------------------------

-- Blizzard's own numeric project IDs. The matrix names the project global per
-- flavor; only the client knows its value, so the mapping lives here. A matrix
-- row naming a global that is not listed fails loudly instead of booting a
-- client with a made-up project ID.
local PROJECT_ID_VALUES = {
    WOW_PROJECT_MAINLINE = 1,
    WOW_PROJECT_CLASSIC = 2,
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5,
    WOW_PROJECT_MISTS_CLASSIC = 19,
}
World.ProjectIDValues = PROJECT_ID_VALUES

-- WoW Forever is not a matrix row: it runs the Mainline TOC and is told apart
-- only by Blizzard_Game's camelot marker (see Game/Shared/Initialize.lua).
World.FOREVER_MARKER = "RegisterCamelotEvents"
local FOREVER = "Forever"
World.FOREVER = FOREVER

function World.Matrix(root)
    local text = Read(root .. "/tools/classic-client-matrix.tsv")
    local rows, header = {}, nil
    for line in text:gmatch("[^\n]+") do
        if line:match("%S") then
            local fields = {}
            for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
            if not header then
                header = fields
            else
                local row = {}
                for index = 1, #header do row[header[index]] = fields[index] or "" end
                rows[#rows + 1] = row
            end
        end
    end
    assert(#rows > 0, "client_world: tools/classic-client-matrix.tsv has no rows")
    return rows
end

-- Flavor -> { Suffix, interfaces, token, projectGlobal, projectID, isClassic }
function World.Clients(root)
    local clients, order = {}, {}
    for _, row in ipairs(World.Matrix(root)) do
        local interfaces = {}
        for number in row.Interfaces:gmatch("%d+") do interfaces[#interfaces + 1] = tonumber(number) end
        assert(#interfaces > 0, "client_world: matrix row " .. row.Suffix .. " has no interface number")
        table.sort(interfaces)
        local projectID = PROJECT_ID_VALUES[row.ProjectGlobal]
        assert(projectID ~= nil,
            "client_world: matrix row " .. row.Suffix .. " names project global " .. row.ProjectGlobal
                .. ", which has no known value; add it to PROJECT_ID_VALUES")
        clients[row.Suffix] = {
            suffix = row.Suffix,
            interfaces = interfaces,
            -- The newest interface the row lists is the client this row ships for.
            interface = interfaces[#interfaces],
            token = row.ClientToken ~= "" and row.ClientToken or nil,
            projectGlobal = row.ProjectGlobal,
            projectID = projectID,
            isClassic = row.IsClassic == "true",
            gameType = row.GameType,
        }
        order[#order + 1] = row.Suffix
    end
    return clients, order
end

-- Every flavor a boot test covers: one per matrix row, plus WoW Forever, which
-- shares the Mainline row and adds the camelot marker.
function World.Flavors(root)
    local clients, order = World.Clients(root)
    local flavors = {}
    for _, suffix in ipairs(order) do flavors[#flavors + 1] = suffix end
    assert(clients.Mainline ~= nil, "client_world: the matrix has no Mainline row for WoW Forever to share")
    flavors[#flavors + 1] = FOREVER
    return flavors, clients
end

-- The client facts for one flavor name, including the Forever pseudo-flavor.
function World.ClientFor(root, flavor)
    local clients = World.Clients(root)
    if flavor == FOREVER then
        local mainline = assert(clients.Mainline, "client_world: no Mainline matrix row")
        local forever = {}
        for key, value in pairs(mainline) do forever[key] = value end
        forever.suffix = FOREVER
        forever.tocSuffix = "Mainline"
        forever.isForever = true
        -- Forever ships an interface far below Midnight's; the Mainline row
        -- carries both, so the lowest number in that row is Forever's.
        forever.interface = mainline.interfaces[1]
        return forever
    end
    local client = assert(clients[flavor],
        "client_world: no matrix row for flavor " .. tostring(flavor))
    client.tocSuffix = flavor
    client.isForever = false
    return client
end

-- The reviewed set of globals the harness does not model, per flavor.
-- Rows: Global, Flavors ("*" or a comma list), Kind, Reason. "#" starts a
-- comment line. Returns { [global] = { flavors = {set}, all = bool,
-- kind = string, reason = string } }.
function World.GlobalsBaseline(root)
    local path = root .. "/tools/client-boot-globals.tsv"
    local baseline, header = {}, nil
    for line in Read(path):gmatch("[^\n]+") do
        if line:match("%S") and line:sub(1, 1) ~= "#" then
            local fields = {}
            for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
            if not header then
                header = fields
                assert(fields[1] == "Global" and fields[2] == "Flavors",
                    "client_world: unexpected header in tools/client-boot-globals.tsv")
            else
                local name = fields[1]
                assert(baseline[name] == nil,
                    "client_world: duplicate row for " .. name .. " in tools/client-boot-globals.tsv")
                local entry = { flavors = {}, all = fields[2] == "*", kind = fields[3], reason = fields[4] }
                if not entry.all then
                    for flavor in fields[2]:gmatch("[^,%s]+") do entry.flavors[flavor] = true end
                end
                baseline[name] = entry
            end
        end
    end
    assert(header ~= nil, "client_world: tools/client-boot-globals.tsv has no header")
    return baseline
end

--------------------------------------------------------------------------
-- The sandbox
--------------------------------------------------------------------------

local realG = _G
local realGetfenv = getfenv

-- Only the Lua 5.1 standard library enters the sandbox, so globals installed in
-- this process (by a test driver, say) cannot change what a run sees.
local STANDARD_GLOBALS = {
    "assert", "collectgarbage", "error", "gcinfo", "getmetatable", "ipairs", "load", "loadfile",
    "loadstring", "newproxy", "next", "pairs", "pcall", "rawequal", "rawget", "rawlen", "rawset",
    "require", "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack",
    "xpcall", "_VERSION", "coroutine", "debug", "io", "math", "os", "string", "table",
}

-- A callable, indexable stand-in for an API the harness does not model.
-- Arithmetic yields 0 and concatenation drops the stub, so load-time code that
-- merely passes the value along keeps running.
local Stub
Stub = setmetatable({}, {
    __index = function() return Stub end,
    __newindex = function() end,
    __call = function() return Stub end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __unm = function() return 0 end,
    __pow = function() return 0 end,
    __len = function() return 0 end,
    __lt = function() return false end, __le = function() return false end,
    __concat = function(a, b)
        return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "")
    end,
    __tostring = function() return "<client_world stub>" end,
})
World.Stub = Stub

-- Globals that must read nil until the file that creates them has run: the
-- addon's own namespace and the vendored libraries. Answering these with a stub
-- would make every `if not X then X = {} end` bootstrap skip its own creation --
-- and, worse, every `if _G.__MSUF_X_Loaded then return end` load-once guard
-- would swallow its whole file, because the stub is truthy. The match is
-- "contains MSUF", not "starts with", exactly because of those `__MSUF_*`
-- guards; the addon writes no other global of its own.
local function IsAddonOwned(key)
    if type(key) ~= "string" then return false end
    return key:find("MSUF", 1, true) ~= nil
        or key == "LibStub" or key == "CallbackHandler" or key == "WagoAnalytics"
end

-- WoW globals a smoke must be able to see as genuinely absent, because addon
-- code feature-detects them to place the client.
local ABSENT_BY_DEFAULT = {
    GameEvent = true,          -- Blizzard_Game, camelot builds only (WoW Forever)
    C_GameRules = true,        -- Mainline game modes; MSUF reads it nil-safely
    C_EventUtils = true,       -- IsEventValid; absent means "assume supported"
    MAX_ARENA_ENEMIES = true,  -- Blizzard arena constant; MSUF has its own
    MSUFEditModeFrame = true,
}

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local Methods = {}
Methods.__index = Methods

-- Load a chunk into this world's namespace. Returns ok, message.
function Methods:LoadFile(path, addonName, namespace)
    local chunk, compileError = loadfile(path)
    if chunk == nil then return false, "does not compile: " .. tostring(compileError) end
    setfenv(chunk, self.env)
    self.loading = path
    local ok, runError = pcall(chunk, addonName, namespace)
    self.loading = nil
    if ok then return true end
    return false, tostring(runError)
end

-- Load one addon's whole ordered graph. Failures are collected, never raised,
-- so the caller can report the first one with its file.
function Methods:LoadGraph(addonName, paths, namespace)
    local prefix = self.root .. "/"
    for index = 1, #paths do
        local path = paths[index]
        local relative = path:sub(1, #prefix) == prefix and path:sub(#prefix + 1) or path
        local ok, message = self:LoadFile(path, addonName, namespace)
        self.loaded[#self.loaded + 1] = relative
        if not ok then
            self.failures[#self.failures + 1] = { file = relative, message = message }
        end
    end
    return self
end

-- Core then Options, in TOC order, into one namespace each.
function Methods:Boot()
    local suffix = self.client.tocSuffix or self.flavor
    self.corePaths = World.Graph(self.root, World.CoreTOC(suffix), self.env.GetLocale())
    self.optionsPaths = World.Graph(self.root, World.OptionsTOC(suffix), self.env.GetLocale())
    self:LoadGraph("MidnightSimpleUnitFrames", self.corePaths, self.core)
    self:LoadGraph("MidnightSimpleUnitFrames_Options", self.optionsPaths, self.options)
    return self
end

-- Unknown globals in a stable order, with the file that first read each one.
function Methods:UnknownGlobals()
    local names = {}
    for name in pairs(self.unknown) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Methods:FirstFailure()
    return self.failures[1]
end

--------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------

-- options:
--   stubs   an msuf_test_stubs environment to reuse (one is built otherwise)
--   locale  GetLocale() result (default "enUS")
function World.New(root, flavor, options)
    options = options or {}
    root = Normalize(root):gsub("/$", "")
    local client = World.ClientFor(root, flavor)
    local Stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"),
        "client_world: .github/scripts/msuf_test_stubs.lua is missing")()
    -- Frames start shown and timers queue: a boot test must not run deferred
    -- work as a side effect of scheduling it.
    local widgets = options.stubs or Stubs.New({ shown = true, timer = "queue", time = 100 })

    local world = setmetatable({
        root = root,
        flavor = flavor,
        client = client,
        widgets = widgets,
        core = {},
        options = {},
        loaded = {},
        failures = {},
        unknown = {},
        prints = {},
    }, Methods)

    local env = {}
    world.env = env
    for index = 1, #STANDARD_GLOBALS do
        local name = STANDARD_GLOBALS[index]
        env[name] = realG[name]
    end
    env._G = env
    env.getfenv = function(level)
        if level == 0 then return env end
        return realGetfenv(level)
    end
    env.print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
        world.prints[#world.prints + 1] = table.concat(parts, " ")
    end

    -- Lua-side WoW dialect ------------------------------------------------
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
    env.table = setmetatable({ wipe = env.wipe }, { __index = realG.table })
    env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
    env.format, env.strfind, env.strmatch = string.format, string.find, string.match
    env.gsub, env.strsub, env.strrep = string.gsub, string.sub, string.rep
    env.strlower, env.strupper, env.strlen = string.lower, string.upper, string.len
    env.strbyte, env.strchar = string.byte, string.char
    env.floor, env.ceil, env.abs = math.floor, math.ceil, math.abs
    env.max, env.min, env.sqrt, env.random = math.max, math.min, math.sqrt, math.random
    env.bit = realG.bit or {
        band = function(a, b)
            local result, bitValue = 0, 1
            a, b = math.floor(a or 0), math.floor(b or 0)
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
                a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
            end
            return result
        end,
        bor = function(a, b)
            local result, bitValue = 0, 1
            a, b = math.floor(a or 0), math.floor(b or 0)
            while a > 0 or b > 0 do
                if a % 2 == 1 or b % 2 == 1 then result = result + bitValue end
                a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
            end
            return result
        end,
        bxor = function(a, b) return a + b end,
        lshift = function(a, n) return math.floor((a or 0) * 2 ^ (n or 0)) end,
        rshift = function(a, n) return math.floor((a or 0) / 2 ^ (n or 0)) end,
    }
    env.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strsplit = function(sep, s)
        local out = {}
        for piece in (tostring(s or "") .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
            out[#out + 1] = piece
        end
        return unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.strconcat = function(...) return table.concat({ ... }) end
    env.tContains = function(t, value)
        for _, entry in pairs(t) do if entry == value then return true end end
        return false
    end
    env.tIndexOf = function(t, value)
        for index = 1, #t do if t[index] == value then return index end end
        return nil
    end
    env.tDeleteItem = function(t, value)
        for index = #t, 1, -1 do if t[index] == value then table.remove(t, index) end end
    end
    env.tInvert = function(t)
        local out = {}
        for key, value in pairs(t) do out[value] = key end
        return out
    end
    env.CopyTable = function(t)
        local out = {}
        for key, value in pairs(t) do
            out[key] = type(value) == "table" and env.CopyTable(value) or value
        end
        return out
    end
    env.Mixin = function(object, ...)
        for index = 1, select("#", ...) do
            local mixin = select(index, ...)
            if type(mixin) == "table" then for key, value in pairs(mixin) do object[key] = value end end
        end
        return object
    end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.CreateAndInitFromMixin = function(mixin, ...)
        local object = env.Mixin({}, mixin)
        if type(object.Init) == "function" then object:Init(...) end
        return object
    end
    env.securecall = function(fn, ...)
        if type(fn) == "function" then return fn(...) end
    end
    env.securecallfunction = env.securecall
    env.hooksecurefunc = function(target, name, hook)
        if type(target) == "string" then target, name, hook = env, target, name end
        local original = target and target[name]
        if type(original) ~= "function" then return end
        target[name] = function(...)
            local a, b, c, d = original(...)
            hook(...)
            return a, b, c, d
        end
    end
    env.issecurevariable = function() return true end
    env.forceinsecure = function() end
    env.geterrorhandler = function() return function() end end
    env.seterrorhandler = function() end
    env.debugprofilestop = function() return 0 end
    env.debugstack = function() return "" end
    env.C_Timer = widgets:BuildTimerLibrary()
    env.C_Timer.NewTicker = env.C_Timer.NewTicker

    -- Widgets -------------------------------------------------------------
    env.CreateFrame = function(frameType, name, parent, template)
        local frame = widgets:CreateFrame(frameType, name, parent, template)
        return frame
    end
    env.UIParent = widgets.UIParent
    env.WorldFrame = widgets.WorldFrame
    env.GameTooltip = widgets:CreateFrame("GameTooltip", "GameTooltip", widgets.UIParent)
    env.GameFontNormal = widgets:Region("Font")
    env.GameFontHighlight = widgets:Region("Font")
    env.CreateFont = function(name)
        local font = widgets:Region("Font")
        font.frameName = name
        return font
    end
    env.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a,
            GetRGB = function(self) return self.r, self.g, self.b end,
            GetRGBA = function(self) return self.r, self.g, self.b, self.a end,
            GenerateHexColor = function() return "ffffffff" end,
            WrapTextInColorCode = function(_, text) return text end }
    end
    env.CreateColorFromHexString = function() return env.CreateColor(1, 1, 1, 1) end
    env.CreateObjectPool = function(creation, reset)
        return { creationFunc = creation, resetterFunc = reset,
            Acquire = function() return {} end, Release = function() end,
            ReleaseAll = function() end, EnumerateActive = function() return function() end end }
    end
    env.CreateFramePool = env.CreateObjectPool
    env.CreateTextureMarkup = function() return "" end
    env.CreateAtlasMarkup = function() return "" end

    -- Client facts ---------------------------------------------------------
    env.WOW_PROJECT_MAINLINE = PROJECT_ID_VALUES.WOW_PROJECT_MAINLINE
    env.WOW_PROJECT_CLASSIC = PROJECT_ID_VALUES.WOW_PROJECT_CLASSIC
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = PROJECT_ID_VALUES.WOW_PROJECT_BURNING_CRUSADE_CLASSIC
    env.WOW_PROJECT_MISTS_CLASSIC = PROJECT_ID_VALUES.WOW_PROJECT_MISTS_CLASSIC
    env.WOW_PROJECT_ID = client.projectID
    env.GetBuildInfo = function()
        return "test", "00000", "2026-01-01", client.interface
    end
    local metadata = { ["X-MSUF-Client"] = client.token }
    -- Blizzard addons this client family ships. Only the ones MSUF asks about at
    -- load belong here, and only where the answer is established: the cooldown
    -- manager is "AllowLoadGameType: standard, camelot", so both Mainline-family
    -- clients ship it and no Classic client does. A blanket false would make
    -- Client.HostsCooldownManager short-circuit before it reads C_CooldownViewer,
    -- which is exactly the read the globals baseline must keep seeing.
    local shippedBlizzardAddOns = {}
    if not client.isClassic then
        shippedBlizzardAddOns.Blizzard_CooldownViewer = true
    end
    env.C_AddOns = {
        GetAddOnMetadata = function(_, field) return metadata[field] end,
        IsAddOnLoaded = function() return false end,
        LoadAddOn = function() return false, "MISSING" end,
        GetAddOnEnableState = function() return 0 end,
        DoesAddOnExist = function(name) return shippedBlizzardAddOns[name] == true end,
        GetNumAddOns = function() return 0 end,
    }
    env.GetAddOnMetadata = env.C_AddOns.GetAddOnMetadata
    env.IsAddOnLoaded = env.C_AddOns.IsAddOnLoaded
    if client.isForever then
        -- Blizzard_Game publishes this before any addon, on camelot builds only.
        env.GameEvent = { RegisterCamelotEvents = function() end }
    end

    -- Client APIs the load graph reaches ------------------------------------
    env.GetLocale = function() return options.locale or "enUS" end
    env.GetTime = function() return widgets:GetTime() end
    env.time = os.time
    env.date = os.date
    env.GetServerTime = function() return 0 end
    env.InCombatLockdown = function() return widgets:IsInCombat() end
    env.UnitAffectingCombat = function() return false end
    env.IsLoggedIn = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.UnitExists = function() return false end
    env.UnitGUID = function() return nil end
    env.UnitName = function() return "Tester", nil end
    env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
    env.UnitIsUnit = function(a, b) return a == b end
    env.UnitLevel = function() return 1 end
    env.UnitFactionGroup = function() return "Alliance", "Alliance" end
    env.GetRealmName = function() return "Realm" end
    env.GetNormalizedRealmName = function() return "Realm" end
    env.GetNumGroupMembers = function() return 0 end
    env.IsInRaid = function() return false end
    env.IsInGroup = function() return false end
    env.issecretvalue = function() return false end
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    env.RegisterAttributeDriver = function() end
    env.UnregisterAttributeDriver = function() end
    env.RegisterStateDriver = function() end
    env.RegisterUnitWatch = function() end
    env.UnregisterUnitWatch = function() end
    env.GetCVar = function() return nil end
    env.GetCVarBool = function() return false end
    env.SetCVar = function() end
    env.C_CVar = { GetCVar = env.GetCVar, SetCVar = env.SetCVar, GetCVarBool = env.GetCVarBool }

    -- Sandbox lookup -------------------------------------------------------
    local absent = CopyTable(ABSENT_BY_DEFAULT)
    if client.isForever then absent.GameEvent = nil end
    setmetatable(env, { __index = function(_, key)
        if absent[key] or IsAddonOwned(key) then return nil end
        if type(key) == "string" then
            local where = world.unknown[key]
            if where == nil then world.unknown[key] = world.loading or "<harness>" end
        end
        return Stub
    end })

    return world
end

return World
