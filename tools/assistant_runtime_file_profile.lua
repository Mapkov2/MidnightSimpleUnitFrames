_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {}, bars = {}, gameplay = {}, player = {}, target = {}, focus = {}, pet = {},
    units = { player = {}, target = {}, focus = {}, pet = {} },
    groups = { party = {}, raid = {}, mythicraid = {} },
}

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local Loader = dofile(loaderPath)
local entries = Loader.ReadRuntimeEntries()
local rows = {}
local aliasRows = {}
local currentName
local registryWrapped = false
local startedTotal = os.clock()

for i = 1, #entries do
    local entry = entries[i]
    local name = entry.relative:match("^Assistant/(.+%.lua)$")
    if name then
        currentName = name
        local beforeKb = collectgarbage("count")
        local started = os.clock()
        local chunk = assert(loadfile(entry.path))
        chunk("MidnightSimpleUnitFrames", MSUF)
        rows[#rows + 1] = {
            name = name,
            ms = (os.clock() - started) * 1000,
            kb = collectgarbage("count") - beforeKb,
        }
        local Registry = MSUF.Assistant and MSUF.Assistant.Registry
        if not registryWrapped and Registry and type(Registry.RegisterSetting) == "function" then
            registryWrapped = true
            local originalRegisterSetting = Registry.RegisterSetting
            Registry.RegisterSetting = function(self, spec)
                local row = aliasRows[currentName]
                if not row then
                    row = { settings = 0, aliases = 0, exact = 0, maxAliases = 0, maxExact = 0, registerMs = 0 }
                    aliasRows[currentName] = row
                end
                local aliases = type(spec) == "table" and type(spec.aliases) == "table" and #spec.aliases or 0
                local exact = type(spec) == "table" and type(spec.exactAliases) == "table" and #spec.exactAliases or 0
                row.settings = row.settings + 1
                row.aliases = row.aliases + aliases
                row.exact = row.exact + exact
                row.maxAliases = math.max(row.maxAliases, aliases)
                row.maxExact = math.max(row.maxExact, exact)
                local started = os.clock()
                local result = originalRegisterSetting(self, spec)
                row.registerMs = row.registerMs + (os.clock() - started) * 1000
                return result
            end
        end
    end
end

table.sort(rows, function(a, b) return a.ms > b.ms end)
for i = 1, math.min(#rows, tonumber(arg and arg[1]) or 25) do
    local row = rows[i]
    io.write(string.format("%8.3f ms %10.1f kb %s\n", row.ms, row.kb, row.name))
end
io.write(string.format("total_ms=%.3f scripts=%d\n", (os.clock() - startedTotal) * 1000, #rows))

if tostring(arg and arg[2] or "") == "aliases" then
    local rawRows = {}
    for name, row in pairs(aliasRows) do
        row.name = name
        rawRows[#rawRows + 1] = row
    end
    table.sort(rawRows, function(a, b) return (a.aliases + a.exact) > (b.aliases + b.exact) end)
    for i = 1, math.min(#rawRows, 25) do
        local row = rawRows[i]
        io.write(string.format(
            "raw_aliases=%d raw_exact=%d settings=%d register_ms=%.3f max_aliases=%d max_exact=%d %s\n",
            row.aliases, row.exact, row.settings, row.registerMs, row.maxAliases, row.maxExact, row.name
        ))
    end
end
