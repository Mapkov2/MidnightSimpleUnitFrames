local root = (...) or "."
local path = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Reason: every assertion below is about what the global font fanout does, so
-- the slice is that one function and nothing else. It used to end at the doc
-- comment of the next function, which made editing that comment a red smoke.
local body = Slice.Function(source, "function A3.ApplyFontsFromGlobal", path)
local executable = body:gsub("%-%-[^\r\n]*", "")
Check(body:find('_QueueDeferredAuraRuntime%(scope or "shared", reason or "AURAS3_FONT_VISUALS"%)') ~= nil,
    "global aura font fanout no longer defers visual work during combat")
Check(not body:find("_deferredAuraRuntimeFonts", 1, true),
    "global aura font fanout retained the unused font deferral flag")
Check(body:find("A3%.InvalidateNativeVisualInputs%(%)") ~= nil,
    "global aura font fanout no longer invalidates native visual state")
Check(body:find("return A3%.RequestScope%(scope, reason or \"AURAS3_FONT_VISUALS\"%)") ~= nil,
    "scoped aura font updates no longer use RequestScope")
Check(body:find("RuntimeFrame%(runtimeUnit%)") ~= nil,
    "global aura font fanout does not target existing runtime frames directly")
Check(body:find('A3%.ForEachRuntimeUnit%("shared", RefreshRuntimeUnit%)') ~= nil,
    "global aura font fanout no longer covers the bounded standalone unit families")
Check(body:find("gf%.ForEachFrame") ~= nil,
    "global aura font fanout does not cover existing group frames")
Check(body:find("A3%.RenderFrame%(frame, visualReason%)") ~= nil,
    "global aura font fanout does not use the native aura renderer")
Check(executable:find("A3%.RefreshAll", 1, false) == nil,
    "global aura font fanout still rebuilds the complete aura/runtime route")
Check(executable:find("RefreshVisuals", 1, true) == nil,
    "global aura font fanout still enters GroupFrame structural refresh")
Check(executable:find("ApplyElementToFrame", 1, true) == nil,
    "global aura font fanout still rebuilds UnitFrame element routes")
Check(body:find('Facade%.NotifyAuraColdpathPreview%(visualReason, "shared"%)') ~= nil,
    "global aura font fanout no longer refreshes the coldpath preview")
Check(body:find("A3%.RefreshEditPreview%(%)") ~= nil,
    "global aura font fanout no longer refreshes the Edit Mode preview")

-- The fanout visits the standalone units through A3.ForEachRuntimeUnit("shared"). Run the real iterator
-- from the Core schema per client and pin the units it visits, in order: the old explicit list was
-- player, pet, target, focus, boss1-5 and arena1-3, and a client fielding more arena slots (TBC and
-- Mists: 5) extends only the arena family.
local function VisitedUnits(arenaSlots, scope)
    local namespace = {
        ExportPublic = function(_, value) return value end,
        MSUF_CreateCanonicalPlayerDefensiveAuraContainer = function() return { name = "Defensive Buffs", placed = {} } end,
    }
    if arenaSlots ~= nil then namespace.Client = { MaxArenaOpponents = arenaSlots } end
    local savedNamespace, savedAddon = _G.MSUF_NS, _G.MSUF
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua"))
    chunk("MidnightSimpleUnitFrames", namespace)
    _G.MSUF_NS, _G.MSUF = savedNamespace, savedAddon
    local A3 = assert(namespace.MSUF_Auras3, "Auras3 core did not publish A3")
    local visited = {}
    local context = {}
    local any = A3.ForEachRuntimeUnit(scope, function(unit, passed)
        Check(passed == context, "ForEachRuntimeUnit dropped its context argument")
        visited[#visited + 1] = unit
        return true
    end, context)
    Check(any == true, "ForEachRuntimeUnit did not report the callback work")
    return table.concat(visited, ",")
end

local function Expected(arenaCount)
    local units = { "player", "pet", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    for index = 1, arenaCount do units[#units + 1] = "arena" .. index end
    return table.concat(units, ",")
end

for _, client in ipairs({
    { "Mainline and Forever", 3, 3 }, { "TBC and Mists", 5, 5 }, { "Classic Era", 0, 3 }, { "no client facts", nil, 3 },
}) do
    local label, slots, arenaCount = client[1], client[2], client[3]
    local visited = VisitedUnits(slots, "shared")
    Check(visited == Expected(arenaCount),
        "global aura font fanout visits the wrong standalone units on " .. label .. ": " .. visited)
    Check(VisitedUnits(slots, "boss") == "boss1,boss2,boss3,boss4,boss5",
        "ForEachRuntimeUnit boss scope drifted on " .. label)
    local arena = {}
    for index = 1, arenaCount do arena[index] = "arena" .. index end
    Check(VisitedUnits(slots, "arena") == table.concat(arena, ","),
        "ForEachRuntimeUnit arena scope drifted on " .. label)
end

print("aura_font_fanout_smoke: ok")
