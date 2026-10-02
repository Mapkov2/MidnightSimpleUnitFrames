-- aura_lane_key_schema_smoke.lua <repoRoot> [--dump]
--
-- One lane-key schema source. The unit aura lane keys (which profile table
-- owns each key, which keys a unit inherits from Shared Style, and the Shared
-- defaults) used to be hand-kept in four copies: the menu schema's layout and
-- shared-layout key lists, its fallback style lists and lane specs (live on
-- the Classic flavors, which never load the runtime schema), the runtime
-- schema's style lists, and two default tables. They now derive from one
-- table, A3.LaneKeySchema in Auras3/MSUF_Auras3_Core.lua.
--
-- Part 1, equivalence. The refactor must not change one saved key or
-- default. On every client load path (Mainline with the runtime schema;
-- Classic Era, TBC and Mists without it) this smoke dumps:
--   a. every table both schema factories return. Menu GROUPS is dumped by the
--      14 fields its consumers read (Menu_Model, Menu_Appearance and the
--      schema itself); the Classic fallback specs carried exactly those;
--   b. where Model.WriteValue lands for every known key in every menu scope
--      (shared, player, pet, target, focus, boss, arena), with the override
--      flags it sets, and whether Model.ReadValue reads it back;
--   c. the Shared defaults Model.EnsureDB seeds into a legacy profile.
-- The dump must equal tools/tests/aura_lane_key_schema_golden.txt, captured
-- from the tree before the refactor. `--dump` prints the dump and stops.
--
-- Part 2, one source. The menu and runtime schemas hand the exact source
-- tables on, and neither file spells a unit lane key out again.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local dumpOnly = arg[2] == "--dump"
local addon = root .. "/MidnightSimpleUnitFrames/"

local function Load(path, namespace)
    local chunk = assert(loadfile(addon .. path))
    return chunk("MidnightSimpleUnitFrames", namespace)
end

local function ReadSource(path)
    local file = assert(io.open(addon .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function Scalar(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local out = {}
local function Emit(line) out[#out + 1] = line end

local function Dump(prefix, value, seen)
    if type(value) ~= "table" then Emit(prefix .. " = " .. Scalar(value)); return end
    seen = seen or {}
    if seen[value] then Emit(prefix .. " = <same as " .. seen[value] .. ">"); return end
    seen[value] = prefix
    local keys = SortedKeys(value)
    if #keys == 0 then Emit(prefix .. " = {}") end
    for _, key in ipairs(keys) do
        local child = value[key]
        if type(child) == "function" then
            Emit(prefix .. "." .. tostring(key) .. " = <function>")
        else
            Dump(prefix .. "." .. tostring(key), child, seen)
        end
    end
end

-- The lane descriptor fields the menu reads from Schema.GROUPS.
local GROUP_CONTRACT_FIELDS = {
    "showKey", "maxKey", "xKey", "yKey", "sizeKey", "anchorKey", "layerKey", "strataKey",
    "perRowKey", "spacingKey", "growthKey", "wrapKey", "defaultAnchor", "defaultLayer",
}
local function ContractGroups(groups)
    local projected = {}
    for kind, spec in pairs(groups) do
        local copy = {}
        for _, field in ipairs(GROUP_CONTRACT_FIELDS) do copy[field] = spec[field] end
        projected[kind] = copy
    end
    return projected
end

local SCOPES = { "shared", "player", "pet", "target", "focus", "boss", "arena" }
local checks = {}

local function RunPath(pathName, arenaSlots, loadRuntime)
    Emit("## path " .. pathName)
    local namespace = {
        Client = { Family = loadRuntime and "Mainline" or "Classic", IsClassic = not loadRuntime },
        ExportPublic = function(name, value) _G[name] = value; return value end,
        MSUF_CreateCanonicalPlayerDefensiveAuraContainer = function() return { name = "Defensive Buffs", placed = {} } end,
    }
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    _G.MSUF_MAX_ARENA_FRAMES = arenaSlots
    _G.MSUF_DB = nil
    _G.MSUF_NormalizeAuraDebuffTypeBorderMode = function(value, fallback)
        value = type(value) == "string" and value:upper() or nil
        if value == "OFF" or value == "BORDER" or value == "SYMBOL" then return value end
        return fallback or "OFF"
    end
    _G.MSUF_AuraTableHasAnyKey = function(tbl, keys)
        if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
        for key in pairs(keys) do if tbl[key] ~= nil then return true end end
        return false
    end

    Load("Auras3/MSUF_Auras3_Core.lua", namespace)
    local A3 = assert(namespace.MSUF_Auras3, "Auras3 core did not publish A3")
    -- The menu falls back to its own profile path without the core adapter;
    -- the adapter's profile normalization belongs to State and is not under test.
    A3.EnsureDB = nil

    local runtime
    if loadRuntime then
        Load("Auras3/Runtime/MSUF_Auras3_Runtime_Schema.lua", namespace)
        runtime = namespace.Auras3RuntimeFactories.Schema("MidnightSimpleUnitFrames", namespace, A3, {},
            namespace.ExportPublic, {})
        Dump("runtime", runtime)
    end

    for _, file in ipairs({ "Schema", "Common", "Storage" }) do
        Load("Auras3/MenuModel/MSUF_Auras3_Menu_" .. file .. ".lua", namespace)
    end
    local Factories = namespace.Auras3MenuModelFactories
    local Model = {}
    A3.MenuModel = Model
    local Schema = Factories.Schema(A3)
    local Common = Factories.Common(Schema)
    Factories.Storage(A3, Model, Schema, Common, namespace.ExportPublic)
    local menuTables = {}
    for key, value in pairs(Schema) do menuTables[key] = value end
    menuTables.GROUPS = ContractGroups(Schema.GROUPS)
    Dump("menu", menuTables)
    checks[#checks + 1] = { path = pathName, A3 = A3, menu = Schema, runtime = runtime }

    -- Every key any schema table names, plus every lane-spec key value.
    local known = {}
    local function Collect(tbl)
        if type(tbl) ~= "table" then return end
        for key in pairs(tbl) do if type(key) == "string" then known[key] = true end end
    end
    for _, name in ipairs({ "LAYOUT_KEYS", "SHARED_LAYOUT_KEYS", "STYLE_LAYOUT_KEYS", "STYLE_SHARED_LAYOUT_KEYS",
        "SCOPE_MATERIALIZED_LAYOUT_KEYS", "DEFAULT_SHARED" }) do
        Collect(Schema[name])
    end
    local laneSpecs = { menuTables.GROUPS }
    if runtime then
        Collect(runtime.DEFAULT_SHARED)
        Collect(runtime.STYLE_SHARED_LAYOUT_KEYS)
        laneSpecs[2] = runtime.LANE_SPECS
    end
    for _, specs in ipairs(laneSpecs) do
        for _, spec in pairs(specs) do
            for field, key in pairs(spec) do
                if type(field) == "string" and field:match("Key$") and type(key) == "string" then known[key] = true end
            end
        end
    end
    for _, lane in pairs(Schema.LANE_STYLE_KEYS) do
        for base, key in pairs(lane) do known[base] = true; known[key] = true end
    end
    known.filters = nil

    local SENTINEL = "__lane_key_probe__"
    local function Where(auras)
        local hits = {}
        if auras.shared and auras.shared.__probe == SENTINEL then hits[#hits + 1] = "shared" end
        for _, unit in ipairs(SortedKeys(auras.perUnit or {})) do
            local pu = auras.perUnit[unit]
            for _, owner in ipairs({ "layout", "layoutShared" }) do
                if type(pu[owner]) == "table" and pu[owner].__probe == SENTINEL then
                    hits[#hits + 1] = unit .. "." .. owner
                end
            end
            local flags = {}
            for _, flag in ipairs({ "overrideLayout", "overrideSharedLayout", "overrideStyle" }) do
                if pu[flag] ~= nil then flags[#flags + 1] = flag .. "=" .. tostring(pu[flag]) end
            end
            if #flags > 0 then hits[#hits + 1] = unit .. "{" .. table.concat(flags, ",") .. "}" end
        end
        return #hits > 0 and table.concat(hits, " ") or "-"
    end
    for _, key in ipairs(SortedKeys(known)) do
        local parts = {}
        for _, scope in ipairs(SCOPES) do
            _G.MSUF_DB = { auras3 = { profileModelRevision = 2, shared = { filters = {} } } }
            Model.WriteValue(scope, key, SENTINEL)
            local auras = _G.MSUF_DB.auras3
            -- Mark the tables that took the probe, whatever key it went under.
            if auras.shared[key] == SENTINEL then auras.shared.__probe = SENTINEL end
            for _, pu in pairs(auras.perUnit or {}) do
                for _, owner in ipairs({ "layout", "layoutShared" }) do
                    if type(pu[owner]) == "table" and pu[owner][key] == SENTINEL then pu[owner].__probe = SENTINEL end
                end
            end
            local readBack = Model.ReadValue(scope, key, "<default>") == SENTINEL and "read" or "unread"
            parts[#parts + 1] = scope .. ":" .. Where(auras) .. ":" .. readBack
        end
        Emit("route " .. key .. " | " .. table.concat(parts, " | "))
    end

    _G.MSUF_DB = { auras3 = {} }
    local _, shared = Model.EnsureDB()
    Dump("seeded.shared", shared)
end

RunPath("Mainline", 3, true)
RunPath("Vanilla", 0, false)
RunPath("TBC", 5, false)
RunPath("Mists", 5, false)

local dump = table.concat(out, "\n") .. "\n"
if dumpOnly then io.write(dump); return end

-- Part 1: equivalence with the pre-refactor tree.
local goldenPath = root .. "/tools/tests/aura_lane_key_schema_golden.txt"
local file = assert(io.open(goldenPath, "rb"), "golden dump missing: " .. goldenPath)
local golden = file:read("*a"):gsub("\r\n", "\n")
file:close()
if golden ~= dump then
    local goldenLines, dumpLines = {}, {}
    for line in golden:gmatch("([^\n]*)\n") do goldenLines[#goldenLines + 1] = line end
    for line in dump:gmatch("([^\n]*)\n") do dumpLines[#dumpLines + 1] = line end
    local shown = 0
    for i = 1, math.max(#goldenLines, #dumpLines) do
        if goldenLines[i] ~= dumpLines[i] then
            io.stderr:write(("line %d\n  golden: %s\n  now:    %s\n"):format(i, tostring(goldenLines[i]), tostring(dumpLines[i])))
            shown = shown + 1
            if shown >= 12 then break end
        end
    end
    error(("lane-key schema dump differs from the golden (%d golden lines, %d now)"):format(#goldenLines, #dumpLines))
end

-- Part 2: one source, handed on by reference on every client path.
local derivedKeys = {}
for _, check in ipairs(checks) do
    local source = check.A3.LaneKeySchema
    assert(type(source) == "table", check.path .. ": A3.LaneKeySchema missing from Auras3 core")
    local menu = check.menu
    for _, pair in ipairs({
        { "GROUPS", "LANE_SPECS" }, { "LAYOUT_KEYS", "LAYOUT_KEYS" }, { "SHARED_LAYOUT_KEYS", "SHARED_LAYOUT_KEYS" },
        { "STYLE_LAYOUT_KEYS", "STYLE_LAYOUT_KEYS" }, { "STYLE_SHARED_LAYOUT_KEYS", "STYLE_SHARED_LAYOUT_KEYS" },
        { "SCOPE_MATERIALIZED_LAYOUT_KEYS", "SCOPE_MATERIALIZED_LAYOUT_KEYS" }, { "LANE_STYLE_KEYS", "LANE_STYLE_KEYS" },
    }) do
        assert(menu[pair[1]] == source[pair[2]],
            ("%s: menu schema %s is not the source table %s"):format(check.path, pair[1], pair[2]))
    end
    if check.runtime then
        assert(check.runtime.LANE_SPECS == source.LANE_SPECS, check.path .. ": runtime LANE_SPECS is not the source table")
        assert(check.runtime.STYLE_SHARED_LAYOUT_KEYS == source.STYLE_SHARED_LAYOUT_KEYS,
            check.path .. ": runtime STYLE_SHARED_LAYOUT_KEYS is not the source table")
        for key in pairs(check.runtime.DEFAULT_SHARED) do derivedKeys[key] = true end
        assert(check.runtime.UNIT_FLAG == source.UNIT_FLAG and check.runtime.MANAGED_UNITS == source.MANAGED_UNITS,
            check.path .. ": the runtime unit tables are not the source tables")
    end
    for _, flag in pairs(source.UNIT_FLAG) do derivedKeys[flag] = true end
    for _, name in ipairs({ "LAYOUT_KEYS", "SHARED_LAYOUT_KEYS", "DEFAULT_SHARED" }) do
        for key in pairs(menu[name]) do derivedKeys[key] = true end
    end
end
derivedKeys.filters = nil
-- The Classic compiler takes the unit tables from the source too: no unit
-- maps to a show flag there again.
local compileSource = ReadSource("Game/Classic/Auras/MSUF_Auras3_Compile.lua")
for _, flag in ipairs({ "showPlayer", "showPet", "showTarget", "showFocus", "showBoss", "showArena" }) do
    assert(not compileSource:find('[^=~<>]=%s*"' .. flag .. '"'),
        "Game/Classic/Auras/MSUF_Auras3_Compile.lua maps a unit to the show flag " .. flag .. " again")
end
for _, path in ipairs({ "Auras3/MenuModel/MSUF_Auras3_Menu_Schema.lua", "Auras3/Runtime/MSUF_Auras3_Runtime_Schema.lua" }) do
    local source = ReadSource(path)
    for key in pairs(derivedKeys) do
        local hit = source:find('"' .. key .. '"', 1, true) or source:find("[%.%s{,]" .. key .. "%s*=")
        assert(not hit, ("%s spells the lane key %s out again; derive it from A3.LaneKeySchema"):format(path, key))
    end
end
print(("aura_lane_key_schema_smoke: ok (%d dump lines, 4 client paths, %d scopes, %d derived keys)")
    :format(#out, #SCOPES, (function() local n = 0; for _ in pairs(derivedKeys) do n = n + 1 end; return n end)()))
