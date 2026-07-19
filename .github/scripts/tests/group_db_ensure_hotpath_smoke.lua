-- Regression: Group DB repair is a cold path. Combat/runtime callers must use
-- cached config, and repeated defensive EnsureDB calls must not scan defaults.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local realPairs = pairs
local pairScans = 0
_G.pairs = function(tbl)
    pairScans = pairScans + 1
    return realPairs(tbl)
end
_G.wipe = function(tbl)
    for key in realPairs(tbl) do tbl[key] = nil end
    return tbl
end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in realPairs(value) do copy[key] = _G.CopyTable(child) end
    return copy
end
_G.MSUF_DB = { general = {} }

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local GF = assert(MSUF.GF, "group-frame API missing")
GF.EnsureDB()
local db = _G.MSUF_DB
Check(type(db.gf_party) == "table" and type(db.gf_raid) == "table"
    and type(db.gf_mythicraid) == "table" and type(db.gf_priority) == "table",
    "initial Group DB repair did not materialize all scopes")

pairScans = 0
for _ = 1, 100 do GF.EnsureDB() end
Check(pairScans == 0, "stable EnsureDB calls rescanned defaults or migrations")
collectgarbage("collect")
collectgarbage("stop")
local memoryBefore = collectgarbage("count")
for _ = 1, 10000 do GF.EnsureDB() end
local memoryAfter = collectgarbage("count")
collectgarbage("restart")
Check(memoryAfter == memoryBefore, "stable EnsureDB calls allocated Lua memory")

-- A real mutation invalidates the permanent fast path and repairs a missing
-- field exactly once; later calls return to the scan-free path.
db.gf_party.width = nil
GF.InvalidateConfCache()
_G.InCombatLockdown = function() return true end
pairScans = 0
GF.EnsureDB()
Check(db.gf_party.width == nil and pairScans == 0,
    "in-place Group DB repair still ran during combat")
_G.InCombatLockdown = function() return false end
pairScans = 0
GF.EnsureDB()
Check(db.gf_party.width == GF.PARTY_DEFAULTS.width,
    "invalidated in-place mutation was not repaired")
Check(pairScans > 0, "invalidated DB repair did not run")
pairScans = 0
GF.EnsureDB()
Check(pairScans == 0, "repaired DB did not return to the scan-free path")

-- Root/table replacement remains self-invalidating even without an explicit
-- cache notification, which preserves profile-switch/import safety.
db.gf_party = { enabled = false }
pairScans = 0
GF.EnsureDB()
Check(db.gf_party.enabled == false and db.gf_party.width == GF.PARTY_DEFAULTS.width,
    "replaced Group config did not preserve values and fill defaults")
Check(pairScans > 0, "replaced Group config incorrectly hit the ready fast path")

-- Legacy aura defaults must remain per-profile tables even though the immutable
-- templates are reused for missing-field scans.
local partyBuff = db.gf_party.auras.buff
local raidBuff = db.gf_raid.auras.buff
partyBuff.size = 77
Check(raidBuff.size ~= 77, "legacy aura default tables became shared mutable state")

local prioritySource = assert(io.open(
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Priority.lua", "rb"))
local priorityText = prioritySource:read("*a")
prioritySource:close()
local priorityConf = priorityText:match("local function PriorityConf%(%)%s*(.-)%s*end") or ""
Check(not priorityConf:find("EnsureDB", 1, true),
    "PriorityConf still runs Group DB repair from runtime event registration")

local runtimeSource = assert(io.open(
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua", "rb"))
local runtimeText = runtimeSource:read("*a")
runtimeSource:close()
Check(runtimeText:find("if not inCombat and GF.EnsureDB then GF.EnsureDB() end", 1, true) ~= nil,
    "RefreshHeaderLayout can still enter Group DB repair during combat")

_G.pairs = realPairs
print("group_db_ensure_hotpath_smoke: ok")
