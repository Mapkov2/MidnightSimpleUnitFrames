-- public_globals_smoke.lua <repoRoot> <flavor> [--inventory | --probe <file> | --ledger <file>]
--
-- The runtime half of the public-globals ledger (tools/public-globals.tsv,
-- maintained by tools/public_globals_ledger.py). Boots one client's real core
-- and Options load graph in the fake client of tools/tests/client_world.lua,
-- delivers ADDON_LOADED, PLAYER_LOGIN and PLAYER_ENTERING_WORLD the way the
-- client does, spawns every unit frame, and then asserts that every ledgered
-- name the ledger lists for this client exists in _G with the kind the ledger
-- records: another addon, the Suite, a binding or the client itself reads it by
-- that name, so a rename or a move into the addon namespace breaks the reader.
-- A nsfield row (MSUF_NS.L, MSUF2.Undo) is a field of an exported table: the
-- table must exist and the field must be non-nil, which is what the reader needs.
-- Rows whose clients column is "static" are not reachable offline; the ledger
-- tool proves their exporter in the source instead.
--
-- Client facts the harness does not model are supplied here exactly as the
-- client supplies them: the TOC metadata the unit-frame framework names its
-- frames from (X-MSUF-UnitFrames-Prefix), a real StaticPopupDialogs table, and
-- global names for frames that CreateFrame names.
--
-- --inventory prints every global the load graph wrote, one line per name
-- (name, final type, phase, writing file:line), for tools/public_globals_ledger.py.
-- --probe <file> reads Table<TAB>field lines and prints which of those fields the
-- booted client holds (the fields of the exported tables that outside addons read).
-- --ledger <file> checks another ledger file than tools/public-globals.tsv, which
-- is how tools/tests/public_globals_ledger_smoke.py proves this smoke can fail.
--
-- Plain Lua 5.1 with the repo root as arg 1 and a client flavor as arg 2.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a matrix Suffix or Forever)")
local inventoryMode = arg[3] == "--inventory"
local probePath = arg[3] == "--probe" and assert(arg[4], "--probe needs a file") or nil
local ledgerPath = arg[3] == "--ledger" and assert(arg[4], "--ledger needs a file") or (root .. "/tools/public-globals.tsv")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "public_globals_smoke: tools/tests/client_world.lua is missing")()

local KNOWN_FLAVORS = {}
for _, name in ipairs((World.Flavors(root))) do KNOWN_FLAVORS[name] = true end
assert(KNOWN_FLAVORS[flavor], "unknown flavor " .. flavor)

local function ReadFile(path)
    local handle = assert(io.open(path, "rb"), "missing file " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

-- TOC metadata of the core addon for this flavor: the first value of each key,
-- without its [AllowLoadGameType ...] condition.
local function TocMetadata()
    local suffix = World.ClientFor(root, flavor).tocSuffix
    local meta = {}
    local text = ReadFile(root .. "/" .. World.CoreTOC(suffix))
    for line in text:gmatch("[^\n]+") do
        local key, value = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
        if key and meta[key] == nil then meta[key] = (value:gsub("%s*%[.-%]%s*$", "")) end
    end
    return meta
end

local function RelativeSource(info)
    local source = tostring(info.source or ""):gsub("^@", ""):gsub("\\", "/")
    local index = source:find("/MidnightSimpleUnitFrames", 1, true)
    if not index then return nil end
    return source:sub(index + 1) .. ":" .. tostring(info.currentline)
end

-- Boot ---------------------------------------------------------------------

local function Boot()
    local world = World.New(root, flavor)
    local env = world.env

    -- Names the addon owns read nil until its own file creates them. The
    -- harness does that for every key containing "MSUF"; a name that starts
    -- with the addon folder name (MidnightSimpleUnitFrames...) has no such
    -- substring.
    local meta = getmetatable(env)
    local lookup = meta.__index
    meta.__index = function(table_, key)
        if type(key) == "string" and key:find("^MidnightSimpleUnitFrames") then return nil end
        return lookup(table_, key)
    end

    local toc = TocMetadata()
    local baseGet = env.C_AddOns.GetAddOnMetadata
    local function GetMetadata(addon, field)
        if toc[field] ~= nil and field:find("^X%-MSUF%-Unit") then return toc[field] end
        return baseGet(addon, field)
    end
    env.C_AddOns.GetAddOnMetadata = GetMetadata
    env.GetAddOnMetadata = GetMetadata
    rawset(env, "StaticPopupDialogs", {})
    -- FrameXML constants the unit-frame spawn reads.
    rawset(env, "MAX_BOSS_FRAMES", 5)
    rawset(env, "MAX_TOTEMS", 4)

    -- Every global the graph writes, with the first writer inside the addon.
    local before = {}
    for key in pairs(env) do before[key] = true end
    local writes, order, phase = {}, {}, "boot"
    meta.__newindex = function(table_, key, value)
        if type(key) == "string" and writes[key] == nil and not before[key] then
            local site
            for level = 2, 10 do
                local info = debug.getinfo(level, "Sl")
                if not info then break end
                local relative = RelativeSource(info)
                if relative and not relative:find("MSUF_Bootstrap%.lua") then
                    site = relative
                    break
                end
            end
            writes[key] = { phase = phase, site = site or "-" }
            order[#order + 1] = key
        end
        rawset(table_, key, value)
    end

    -- A named frame is a global of the same name in the client.
    local createFrame = env.CreateFrame
    env.CreateFrame = function(frameType, name, parent, template)
        local frame = createFrame(frameType, name, parent, template)
        if type(name) == "string" and name ~= "" then env[name] = frame end
        return frame
    end

    world:Boot()

    -- One event, delivered to every frame that registered for it. A handler
    -- that raises in the harness must not stop the others, so each call is
    -- guarded here (smokes may pcall; addon code may not).
    local function Deliver(event, ...)
        local bus = world.core.EventBus
        local frames = world.widgets.frames
        for index = 1, #frames do
            local frame = frames[index]
            local events = rawget(frame, "events")
            local scripts = rawget(frame, "scripts")
            local handler = scripts and scripts.OnEvent
            if handler and events and events[event] then
                if bus and frame == bus.driver then
                    local entry = bus.handlers[event]
                    local list = entry and entry.list or {}
                    for position = 1, #list do
                        local item = list[position]
                        if item.fn and not item.dead then pcall(item.fn, event, ...) end
                    end
                else
                    pcall(handler, frame, event, ...)
                end
            end
        end
    end
    phase = "addon"
    Deliver("ADDON_LOADED", "MidnightSimpleUnitFrames")
    Deliver("ADDON_LOADED", "MidnightSimpleUnitFrames_Options")
    phase = "login"
    Deliver("PLAYER_LOGIN")
    phase = "world"
    Deliver("PLAYER_ENTERING_WORLD", true, false)
    -- The live client has every managed unit by now; the harness stops at the
    -- first unit its stubs cannot paint, so each one is spawned on its own.
    phase = "spawn"
    local UF = world.core.UF
    local factory = UF and UF.Factory
    if factory and factory.Apply and UF.unitOrder then
        for index = 1, #UF.unitOrder do pcall(factory.Apply, UF.unitOrder[index]) end
    end
    return world, writes, order
end

local world, writes, order = Boot()
local env = world.env

local function Describe(value)
    if value == nil then return "nil" end
    return type(value)
end

-- A widget answers GetObjectType; a plain table, or a strict one that raises on an unknown key, does not.
local function IsWidget(value)
    if type(value) ~= "table" then return false end
    local ok, method = pcall(function() return value.GetObjectType end)
    return ok and type(method) == "function"
end

if inventoryMode then
    for _, name in ipairs(order) do
        local record = writes[name]
        local value = rawget(env, name)
        print(table.concat({ name, Describe(value), record.phase, record.site, IsWidget(value) and "frame" or "-" }, "\t"))
    end
    for _, special in ipairs(rawget(env, "UISpecialFrames") or {}) do print("#special\t" .. tostring(special)) end
    -- MSUF_* fields of the two addon namespaces: the Suite reads some as host.MSUF_X.
    local fields = {}
    for _, namespace in ipairs({ world.core, world.options }) do
        for key, value in pairs(namespace) do
            if type(key) == "string" and key:find("^MSUF_") and fields[key] == nil then fields[key] = Describe(value) end
        end
    end
    local sorted = {}
    for key in pairs(fields) do sorted[#sorted + 1] = key end
    table.sort(sorted)
    for _, key in ipairs(sorted) do print("#ns\t" .. key .. "\t" .. fields[key]) end
    return
end

if probePath then
    for line in (ReadFile(probePath) .. "\n"):gmatch("(.-)\n") do
        local tableName, field = line:match("^([^\t]+)\t([^\t]+)$")
        local holder = tableName and rawget(env, tableName)
        if type(holder) == "table" then
            local ok, value = pcall(function() return holder[field] end)
            if ok and value ~= nil then print("#field\t" .. tableName .. "\t" .. field .. "\t" .. type(value)) end
        end
    end
    return
end

-- Ledger ---------------------------------------------------------------------

local LEDGER_COLUMNS = { "name", "kind", "exporter", "consumers", "readers", "addons", "evidence", "clients", "note" }
local KINDS = {
    ["function"] = true, table = true, frame = true, value = true, savedvar = true,
    slash = true, popup = true, binding = true, dynamic = true, nsfield = true,
}

-- What the booted client holds under a row's name: a global, a popup key, or a field of an exported table.
local function Lookup(row)
    if row.kind == "popup" then return rawget(env, "StaticPopupDialogs")[row.name] end
    if row.kind == "nsfield" then
        local tableName, field = row.name:match("^([^.]+)%.(.+)$")
        local holder = tableName and rawget(env, tableName)
        if type(holder) ~= "table" then return nil end
        local ok, value = pcall(function() return holder[field] end)
        if ok then return value end
        return nil
    end
    return rawget(env, row.name)
end

local function Split(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
    return fields
end

local rows, problems = {}, {}
local function Problem(message) problems[#problems + 1] = message end

local ledgerLines = {}
for line in (ReadFile(ledgerPath) .. "\n"):gmatch("(.-)\n") do
    ledgerLines[#ledgerLines + 1] = line
end

for number, line in ipairs(ledgerLines) do
    if line:match("%S") and line:sub(1, 1) ~= "#" then
        local fields = Split(line)
        if fields[1] == "name" then
            for index, column in ipairs(LEDGER_COLUMNS) do
                if fields[index] ~= column then
                    Problem("tools/public-globals.tsv header column " .. index .. " is " .. tostring(fields[index])
                        .. ", expected " .. column)
                end
            end
        elseif #fields ~= #LEDGER_COLUMNS then
            Problem("tools/public-globals.tsv line " .. number .. " has " .. #fields .. " columns, expected " .. #LEDGER_COLUMNS)
        else
            local row = { line = number }
            for index, column in ipairs(LEDGER_COLUMNS) do row[column] = fields[index] end
            rows[#rows + 1] = row
        end
    end
end

local function ClientsOf(row)
    local set, valid = {}, true
    if row.clients == "all" then
        for name in pairs(KNOWN_FLAVORS) do set[name] = true end
    elseif row.clients ~= "static" then
        for name in row.clients:gmatch("[^,]+") do
            if KNOWN_FLAVORS[name] then set[name] = true else valid = false end
        end
    end
    return set, valid
end

local function Consumers(row)
    local shown = row.consumers:gsub("|", ", ")
    return shown ~= "" and shown or "-"
end

local checked = 0
for _, row in ipairs(rows) do
    local clients, valid = ClientsOf(row)
    if not valid or not KINDS[row.kind] or row.consumers == "" then
        Problem(row.name .. " (line " .. row.line .. ") is malformed: kind=" .. row.kind .. " clients=" .. row.clients)
    elseif clients[flavor] and row.kind ~= "dynamic" then
        checked = checked + 1
        local value = Lookup(row)
        local ok
        if row.kind == "function" then ok = type(value) == "function"
        elseif row.kind == "slash" or row.kind == "binding" then ok = type(value) == "string"
        elseif row.kind == "table" or row.kind == "frame" or row.kind == "popup" or row.kind == "savedvar" then
            ok = type(value) == "table"
        else ok = value ~= nil end
        if not ok then
            Problem(flavor .. ": " .. row.name .. " is " .. Describe(value) .. " after login, the ledger records a "
                .. row.kind .. " exported at " .. row.exporter .. ". Readers that would break (" .. row.readers
                .. "): " .. Consumers(row))
        end
    end
end

-- A boot that fails part-way would make every later name look missing for the
-- wrong reason, so the load failures come first.
local failures = {}
for _, failure in ipairs(world.failures) do
    failures[#failures + 1] = flavor .. ": load failed in " .. failure.file .. ": " .. failure.message
end
if #failures > 0 or #problems > 0 then
    local all = {}
    for _, message in ipairs(failures) do all[#all + 1] = message end
    for _, message in ipairs(problems) do all[#all + 1] = message end
    error(#all .. " public-globals problem(s)\n  " .. table.concat(all, "\n  "), 0)
end
if checked < 1 then error(flavor .. ": the ledger lists no name for this client", 0) end
print(string.format("public_globals_smoke: ok (%s, %d of %d ledgered names present in _G after login)",
    flavor, checked, #rows))
