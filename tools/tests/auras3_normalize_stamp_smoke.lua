-- auras3_normalize_stamp_smoke.lua <repoRoot> <flavor>
--
-- A3.EnsureDB skips the Auras3 profile normalization while the profile it
-- normalized last is unchanged (same profile table, aura tree and player
-- defensive container, same runtime config revision). This smoke boots the
-- flavor's whole shipped graph and checks both halves of that contract:
--
--   * repeated reads of an unchanged profile do not normalize again (the menu
--     reads the aura model dozens of times per preview repaint);
--   * every change normalization exists for still normalizes: a replaced aura
--     tree or profile table (reset, import, factory profile, switch), a lost or
--     reshaped player defensive container, and an aura apply (the runtime
--     config revision bump that profile imports and menu applies raise).
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "auras3_normalize_stamp_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "auras3_normalize_stamp_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local env, MSUF = world.env, world.core
env.MSUF_EnsureDB(true)
local A3 = MSUF.MSUF_Auras3
Check(type(A3) == "table" and type(A3.EnsureDB) == "function" and type(A3.NormalizeProfileDB) == "function",
    "no Auras3 profile adapter")

local normalizes = 0
local normalize = A3.NormalizeProfileDB
A3.NormalizeProfileDB = function(...)
    normalizes = normalizes + 1
    return normalize(...)
end
local function Normalizes(fn)
    local before = normalizes
    fn()
    return normalizes - before
end
local function Defensive(auras)
    return auras and auras.customContainers and auras.customContainers.perUnit
        and auras.customContainers.perUnit.player and auras.customContainers.perUnit.player.items
        and auras.customContainers.perUnit.player.items[4]
end

-- Warm: the first read after boot may normalize once.
A3.EnsureDB()
Check(Normalizes(function() for _ = 1, 25 do A3.EnsureDB() end end) == 0,
    "an unchanged profile is normalized again on every read")
local auras = A3.EnsureDB()
Check(auras == env.MSUF_DB.auras3, "A3.EnsureDB does not return the current aura tree")
-- Review 2026-10-02: nothing read A3.DBRef; the write-only export stays gone.
Check(A3.DBRef == nil, "the write-only A3.DBRef export is back")

-- An aura apply bumps the runtime config revision: normalize once, then stop.
A3.BumpRuntimeConfig()
Check(Normalizes(function() A3.EnsureDB(); A3.EnsureDB(); A3.EnsureDB() end) == 1,
    "an aura apply does not normalize exactly once")

-- The player defensive container lost or reshaped.
local items = auras.customContainers.perUnit.player.items
items[4] = nil
Check(Normalizes(function() A3.EnsureDB() end) == 1 and type(Defensive(A3.EnsureDB())) == "table",
    "a removed player defensive container is not recreated")
local item = Defensive(auras)
item.name, item.targetDots = "Renamed", true
Check(Normalizes(function() A3.EnsureDB() end) == 1 and item.name == "Defensive Buffs" and item.targetDots == nil,
    "the player defensive container's fixed fields are not restored")
item.placed = nil
Check(Normalizes(function() A3.EnsureDB() end) == 1 and type(item.placed) == "table" and item.placed.size ~= nil,
    "a player defensive container without its placement is not refilled")

-- A factory profile carries its policy marker into a new aura tree; an apply
-- on the same tree normalizes too.
local marker = A3.PlayerDefensiveFactoryPolicyMarker
Check(type(marker) == "string", "no player defensive factory policy marker name")
env.MSUF_DB[marker] = false
A3.BumpRuntimeConfig()
Check(Normalizes(function() A3.EnsureDB() end) == 1 and env.MSUF_DB[marker] == nil and item.enabled == false,
    "the factory policy marker is not consumed after an apply")
item.enabled = true

-- A replaced aura tree (reset, import) and a replaced profile (switch).
env.MSUF_DB.auras3 = {}
local fresh = A3.EnsureDB()
Check(fresh == env.MSUF_DB.auras3 and type(Defensive(fresh)) == "table",
    "a replaced aura tree is not normalized")
Check(Normalizes(function() A3.EnsureDB(); A3.EnsureDB() end) == 0, "the replaced aura tree is normalized twice")
local profile = env.MSUF_DB
local other = {}
for key, value in pairs(profile) do other[key] = value end
other.auras3 = nil
env.MSUF_DB = other
local switched = A3.EnsureDB()
Check(switched == other.auras3 and switched ~= fresh and type(Defensive(switched)) == "table",
    "a switched profile is not normalized")
env.MSUF_DB = profile
Check(A3.EnsureDB() == profile.auras3, "switching back does not read the original profile")

print(string.format("auras3_normalize_stamp_smoke: ok (%s)", flavor))
