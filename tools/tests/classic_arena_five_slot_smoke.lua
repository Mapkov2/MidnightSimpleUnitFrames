-- classic_arena_five_slot_smoke.lua
-- TBC and Mists field five arena opponents (_G.MSUF_MAX_ARENA_FRAMES = 5,
-- published by Game/Shared/Initialize.lua). This smoke proves the Classic Aura
-- chain and the Classic profile defaults follow that count:
--   Defaults: arena4..N owners are seeded once as deep copies of arena1,
--             stamped with _msufA3ArenaAuraSlots, never overwritten, retried
--             while arena1 is missing, and a no-op at 3 slots or fewer.
--   Compile:  arena4..N are managed units behind showArena, and Hide Permanent
--             for every arena scope reads through arena1.
--   Menu:     the arena scope fans out to arena1..N.
--   Runtime:  arena4..N get the arena identity event tables.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()

local function Read(relative)
    local file = assert(io.open(root .. "/" .. relative, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end

local function DeepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- True when the two trees share no table identity at any depth.
local function Detached(a, b, seen)
    seen = seen or {}
    if type(a) ~= "table" or type(b) ~= "table" then return true end
    if a == b then return false end
    for k, v in pairs(a) do
        if type(v) == "table" and not Detached(v, b[k], seen) then return false end
    end
    return true
end

-- Defaults ------------------------------------------------------------------

function GetLocale() return "enUS" end
function UnitClass() return "Hunter", "HUNTER" end
function UnitName() return "Tester" end
function GetRealmName() return "TestRealm" end
function InCombatLockdown() return false end

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()

-- The arena slot count is read at file load, so the client fact must be
-- published before every consumer on the five-slot clients.
local addonPrefix = root:gsub("\\", "/") .. "/MidnightSimpleUnitFrames/"
for _, flavor in ipairs({ "TBC", "Mists" }) do
    local index = {}
    for i, path in ipairs(manifest.Paths(root, flavor)) do
        local relative = path:sub(#addonPrefix + 1)
        index[relative] = i
    end
    local fact = index["Game/Shared/Initialize.lua"]
    Check(fact, flavor .. " TOC does not load Game/Shared/Initialize.lua")
    for _, consumer in ipairs({
        "State/MSUF_Defaults.lua",
        "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
        "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua",
    }) do
        Check(index[consumer] and index[consumer] > fact,
            flavor .. ": " .. consumer .. " does not load after the arena slot fact")
    end
end

--- Load the Classic defaults chain fresh with the given arena slot count.
--- The count is read at load (runtime unit list, builders) and at call time
--- (seed), exactly like the published client fact.
local function LoadDefaults(flavor, slots)
    _G.MSUF_MAX_ARENA_FRAMES = slots
    local ns = { Client = { Family = "Classic", IsClassic = true } }
    ns.ExportPublic = function(name, value) _G[name] = value end
    _G.MSUF_NS = ns
    _G.MSUF_MaterializeUnitAuraLaneOwners = nil
    _G.MSUF_CreateCanonicalUnitAuras = nil
    local function load(path) assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MSUF", ns) end
    load("State/MSUF_StateHelpers.lua")
    load("State/MSUF_ProfileCodec.lua")
    manifest.LoadSelected(root, flavor, ns, {
        "State/MSUF_AuraDefaults.lua", "State/Defaults/MSUF_Defaults_Shell.lua",
        "State/Defaults/MSUF_Defaults_Bars.lua", "State/Defaults/MSUF_Defaults_Units.lua",
        "State/MSUF_Defaults.lua",
    })
    return assert(_G.MSUF_MaterializeUnitAuraLaneOwners, "Materialize export missing"),
        assert(_G.MSUF_CreateCanonicalUnitAuras, "canonical Unit Aura builder export missing")
end

local function ArenaOwner(offsetX)
    return {
        overrideLayout = true,
        overrideSharedLayout = true,
        overrideStyle = true,
        overrideFilters = true,
        layout = { debuffGroupOffsetX = offsetX, buffGroupIconSize = 26 },
        layoutShared = { maxDebuffs = 4, debuffFrameEffectColor = { 0.1, 0.2, 0.3, 1 } },
        filters = { buffs = { enabled = true }, debuffs = { enabled = true, dispellable = true } },
    }
end

local function MarkerProfile()
    return {
        _msufA3UnitLaneOwners_v1 = true,
        profileModelRevision = 1,
        shared = {},
        perUnit = { arena1 = ArenaOwner(777), arena2 = ArenaOwner(12), arena3 = ArenaOwner(13) },
    }
end

for _, flavor in ipairs({ "TBC", "Mists" }) do
    local Materialize, Canonical = LoadDefaults(flavor, 5)

    -- (1) An old-shaped profile (owners materialized, three arena slots).
    local auras = MarkerProfile()
    Check(Materialize(auras) == true, flavor .. ": marker profile was not seeded to five arena slots")
    Check(auras._msufA3ArenaAuraSlots == 5, flavor .. ": arena slot marker not stamped")
    for i = 4, 5 do
        local owner = auras.perUnit["arena" .. i]
        Check(type(owner) == "table", flavor .. ": arena" .. i .. " owner missing")
        Check(DeepEqual(owner, auras.perUnit.arena1), flavor .. ": arena" .. i .. " is not arena1's layout")
        Check(owner.layout.debuffGroupOffsetX == 777, flavor .. ": arena" .. i .. " lost arena1's offset")
        Check(Detached(owner, auras.perUnit.arena1), flavor .. ": arena" .. i .. " shares tables with arena1")
    end
    Check(Detached(auras.perUnit.arena4, auras.perUnit.arena5), flavor .. ": arena4 and arena5 share tables")
    Check(auras.perUnit.arena6 == nil, flavor .. ": seeded past the slot count")
    Check(auras.perUnit.arena2.layout.debuffGroupOffsetX == 12, flavor .. ": seeding touched arena2")

    -- (2) Idempotent: a second pass changes nothing.
    local snapshot = DeepCopy(auras)
    Check(Materialize(auras) == false, flavor .. ": second pass reported work")
    Check(DeepEqual(auras, snapshot), flavor .. ": second pass mutated the profile")
    auras.perUnit.arena1.layout.debuffGroupOffsetX = 1
    Check(auras.perUnit.arena4.layout.debuffGroupOffsetX == 777, flavor .. ": arena4 aliases arena1")

    -- Count-gated: a stamped profile is never re-seeded, even without arena5.
    auras.perUnit.arena5 = nil
    Check(Materialize(auras) == false and auras.perUnit.arena5 == nil,
        flavor .. ": a stamped profile was re-seeded")

    -- (3) A customised arena4 survives; only the missing arena5 is seeded.
    auras = MarkerProfile()
    auras.perUnit.arena4 = ArenaOwner(55)
    Check(Materialize(auras) == true, flavor .. ": partial profile was not seeded")
    Check(auras.perUnit.arena4.layout.debuffGroupOffsetX == 55, flavor .. ": customised arena4 was overwritten")
    Check(DeepEqual(auras.perUnit.arena5, auras.perUnit.arena1), flavor .. ": arena5 is not arena1's layout")
    Check(auras._msufA3ArenaAuraSlots == 5, flavor .. ": partial profile not stamped")

    -- An older three-slot stamp still seeds on a five-slot client.
    auras = MarkerProfile()
    auras._msufA3ArenaAuraSlots = 3
    Check(Materialize(auras) == true and auras.perUnit.arena5 ~= nil, flavor .. ": three-slot stamp blocked seeding")

    -- (5) A pre-marker profile ends with both markers and arena1-shaped owners.
    auras = {
        shared = { debuffGroupOffsetX = 9, buffGroupOffsetY = 40 },
        perUnit = {
            arena1 = { overrideLayout = true, layout = { debuffGroupOffsetX = 777 } },
            arena2 = { overrideLayout = true, layout = { debuffGroupOffsetX = 12 } },
            arena3 = { overrideLayout = true, layout = { debuffGroupOffsetX = 13 } },
        },
    }
    Check(Materialize(auras) == true, flavor .. ": pre-marker profile was not materialized")
    Check(auras._msufA3UnitLaneOwners_v1 == true, flavor .. ": owner marker missing")
    Check(auras._msufA3ArenaAuraSlots == 5, flavor .. ": arena slot marker missing after materialization")
    for i = 4, 5 do
        local owner = auras.perUnit["arena" .. i]
        Check(type(owner) == "table" and owner.overrideLayout == true and type(owner.layoutShared) == "table",
            flavor .. ": pre-marker arena" .. i .. " is not a materialized owner")
        Check(owner.layout.debuffGroupOffsetX == 777, flavor .. ": pre-marker arena" .. i .. " did not follow arena1")
        Check(DeepEqual(owner, auras.perUnit.arena1), flavor .. ": pre-marker arena" .. i .. " differs from arena1")
        Check(Detached(owner, auras.perUnit.arena1), flavor .. ": pre-marker arena" .. i .. " shares tables")
    end
    Check(Materialize(auras) == false, flavor .. ": materialized pre-marker profile reported more work")

    -- A pre-marker profile without arena1 materializes every owner from
    -- Shared and is stamped by the pass after the snapshot.
    auras = { shared = { debuffGroupOffsetX = 9 }, perUnit = {} }
    Check(Materialize(auras) == true, flavor .. ": empty pre-marker profile was not materialized")
    Check(auras._msufA3UnitLaneOwners_v1 == true and auras._msufA3ArenaAuraSlots == 5,
        flavor .. ": empty pre-marker profile lacks both markers")
    Check(type(auras.perUnit.arena1) == "table" and type(auras.perUnit.arena5) == "table"
        and auras.perUnit.arena5.layout.debuffGroupOffsetX == 9,
        flavor .. ": empty pre-marker profile lacks Shared-shaped arena owners")

    -- (6) Without arena1 nothing is stamped; the next pass seeds.
    auras = MarkerProfile()
    auras.perUnit.arena1 = nil
    Check(Materialize(auras) == false, flavor .. ": seeded without arena1")
    Check(auras._msufA3ArenaAuraSlots == nil and auras.perUnit.arena4 == nil,
        flavor .. ": missing arena1 still stamped or seeded")
    auras.perUnit.arena1 = ArenaOwner(321)
    Check(Materialize(auras) == true, flavor .. ": arena1 arriving later did not seed")
    Check(auras.perUnit.arena5.layout.debuffGroupOffsetX == 321 and auras._msufA3ArenaAuraSlots == 5,
        flavor .. ": late seed did not copy arena1")

    -- New profiles get five arena owners from the builders.
    local canonical = Canonical()
    Check(type(canonical.perUnit.arena5) == "table" and canonical.perUnit.arena5.layout.debuffGroupOffsetX == 234,
        flavor .. ": canonical Unit Auras lack the arena5 default")
    Check(canonical._msufA3ArenaAuraSlots == 5, flavor .. ": canonical Unit Auras lack the slot marker")
    -- The compact factory snapshot needs the in-game codec; a minimal payload
    -- is enough because the factory Unit Aura state is authored in Lua.
    _G.MSUF_TryDecodeCompactString = function() return { general = {} } end
    local factory = assert(_G.MSUF_CreateFactoryDefaultProfile, "factory profile export missing")()
    local factoryArena = type(factory) == "table" and type(factory.auras3) == "table"
        and factory.auras3.perUnit and factory.auras3.perUnit.arena5
    Check(type(factoryArena) == "table" and factoryArena.layout.debuffGroupOffsetX == 131
        and factoryArena.layoutShared.maxDebuffs == 4,
        flavor .. ": factory profile arena5 lacks the factory arena layout")
end

-- (4) At three slots (Mainline count), without the global, and on Vanilla (0)
-- the seed is a no-op and no marker is written.
for _, case in ipairs({ { "TBC", 3 }, { "Mists", nil }, { "Vanilla", 0 } }) do
    local flavor, slots = case[1], case[2]
    local label = flavor .. "/" .. tostring(slots)
    local Materialize, Canonical = LoadDefaults(flavor, slots)
    local auras = MarkerProfile()
    Check(Materialize(auras) == false, label .. ": marker profile reported arena work")
    Check(auras.perUnit.arena4 == nil and auras._msufA3ArenaAuraSlots == nil, label .. ": seeded arena4 or stamped")
    auras = MarkerProfile()
    auras._msufA3ArenaAuraSlots = 2
    Check(Materialize(auras) == false and auras._msufA3ArenaAuraSlots == 2,
        label .. ": a stale slot marker was rewritten at three slots or fewer")
    auras = { shared = {}, perUnit = { arena1 = ArenaOwner(777) } }
    Check(Materialize(auras) == true, label .. ": pre-marker profile was not materialized")
    Check(auras.perUnit.arena4 == nil and auras._msufA3ArenaAuraSlots == nil,
        label .. ": pre-marker materialization created arena4 or stamped")
    Check(type(auras.perUnit.arena3) == "table", label .. ": arena3 owner is no longer materialized")
    local canonical = Canonical()
    Check(type(canonical.perUnit.arena3) == "table" and canonical.perUnit.arena3.layout.debuffGroupOffsetX == 234
        and canonical.perUnit.arena4 == nil
        and canonical._msufA3ArenaAuraSlots == nil, label .. ": canonical arena owners are not exactly 1-3")
end

-- (7) Compile --------------------------------------------------------------

local function NewAuraNamespace()
    local namespace = {
        Client = { IsClassic = true },
        MSUF_Auras3 = {},
        MSUF_DeepCopy = DeepCopy,
        UF = { elements = {}, RegisterElement = function() end },
        ExportPublic = function(name, value) _G[name] = value; return value end,
    }
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    return namespace, namespace.MSUF_Auras3
end

local function LoadAura(namespace, file)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/" .. file))("MidnightSimpleUnitFrames", namespace)
end

local function CompileWith(slots)
    _G.MSUF_MAX_ARENA_FRAMES = slots
    local namespace, A3 = NewAuraNamespace()
    -- MSUF_Auras3_UnitFrames.lua provides the NormalizeClassic* value helpers in
    -- game; lane compilation only needs them to pass values through here.
    setmetatable(A3, { __index = function(_, key)
        if type(key) == "string" and key:match("^NormalizeClassic") then
            return function(value) return value end
        end
    end })
    LoadAura(namespace, "MSUF_Auras3_Compile.lua")
    Check(type(A3._ClassicCompile) == "table", "Classic compile exports missing")
    return A3
end

local A3 = CompileWith(5)
local managed = A3._ClassicCompile.MANAGED_UNITS
Check(managed.arena4 == true and managed.arena5 == true and managed.arena6 == nil,
    "Compile does not manage exactly arena1..5 at five slots")
Check(A3._ClassicCompile.NormalizeRuntimeUnit("arena5") == "arena5", "arena5 is not a runtime unit")

local function HidePermanentDB(arena1Value, arena5Value)
    _G.MSUF_DB = { auras3 = {
        enabled = true, showArena = true, shared = {},
        perUnit = {
            arena1 = { overrideBlacklist = true, blacklist = { debuffs = { hidePermanent = arena1Value } } },
            arena5 = { overrideBlacklist = true, blacklist = { debuffs = { hidePermanent = arena5Value } } },
        },
    } }
end
HidePermanentDB(true, false)
for _, scope in ipairs({ "arena", "arena1", "arena4", "arena5" }) do
    Check(A3._ClassicReadBlacklistHidePermanent(scope, "debuff") == true,
        "Hide Permanent for " .. scope .. " does not read through arena1")
end
HidePermanentDB(false, true)
Check(A3._ClassicReadBlacklistHidePermanent("arena5", "debuff") == false,
    "Hide Permanent for arena5 read its own lane instead of arena1")

Check(A3.ResolveUnitFrameConfig("arena5").enabled == true, "arena5 Aura lanes are not enabled by showArena")
_G.MSUF_DB.auras3.showArena = false
A3._runtimeConfigCache = nil
Check(A3.ResolveUnitFrameConfig("arena5").enabled == false, "arena5 Aura lanes ignore showArena")

A3 = CompileWith(3)
Check(A3._ClassicCompile.MANAGED_UNITS.arena4 == nil, "Compile manages arena4 at three slots")

-- (8) Menu compat ----------------------------------------------------------

local function MenuCompatWith(slots)
    _G.MSUF_MAX_ARENA_FRAMES = slots
    local namespace, menuA3 = NewAuraNamespace()
    local auras = { shared = { blacklist = { spells = {} } }, perUnit = {} }
    menuA3.EnsureDB = function() return auras, auras.shared end
    menuA3._ClassicReadBlacklistHidePermanent = function() return false end
    menuA3.MenuModel = { WriteBlacklistHidePermanent = function() return true end }
    LoadAura(namespace, "MSUF_Auras3_Menu_Compat.lua")
    Check(menuA3.__classicAuraMenuCompatLoaded == true, "Classic Aura menu compat did not load")
    return menuA3.MenuModel, auras
end

for _, scope in ipairs({ "arena", "arena5" }) do
    local Model, auras = MenuCompatWith(5)
    Model.WriteBlacklistHidePermanent(scope, "debuff", true)
    for i = 1, 5 do
        Check(auras.perUnit["arena" .. i] and auras.perUnit["arena" .. i].overrideBlacklist == true,
            "menu scope " .. scope .. " did not reach arena" .. i)
    end
    Check(auras.perUnit.arena6 == nil, "menu scope " .. scope .. " reached arena6")
end
do
    local Model, auras = MenuCompatWith(3)
    Model.WriteBlacklistHidePermanent("arena", "debuff", true)
    Check(auras.perUnit.arena3 ~= nil and auras.perUnit.arena4 == nil, "menu arena scope reached arena4 at three slots")
end

-- (9) Runtime identity events ----------------------------------------------

local unitFrames = Read("MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
local _, requestLoops = unitFrames:gsub('for i = 1, math_max%(3, tonumber%(_G%.MSUF_MAX_ARENA_FRAMES%) or 3%) do\n%s*didWork = ApplyRuntimeUnit%("arena" %.%. i%)', "")
Check(requestLoops == 2, "RequestUnitNow arena loops do not follow MSUF_MAX_ARENA_FRAMES")
Check(not unitFrames:find('for i = 1, 3 do\n%s*didWork = ApplyRuntimeUnit%("arena"'),
    "a RequestUnitNow arena loop is still fixed at three")

-- Reason: this run is plain assignments, not a declaration, so it keeps
-- explicit markers; the shared slicer makes a miss fatal and names the file.
local identityBlock = Slice.Block(unitFrames,
    "A3._ClassicTargetIdentityAuraEvents = A3._ClassicTargetIdentityAuraEvents",
    "A3._ClassicIdentityAuraEvent = A3._ClassicIdentityAuraEvent or {",
    "MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
Check(identityBlock:find("for i = 4, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do", 1, true),
    "identity event loop marker for arena4..N is missing")
local runIdentity = assert(loadstring("local A3 = ...\n" .. identityBlock))

_G.MSUF_MAX_ARENA_FRAMES = 5
local sentinel = { "SENTINEL" }
local fake = { _ClassicIdentityAuraEventsByUnit = { arena4 = sentinel } }
runIdentity(fake)
Check(fake._ClassicIdentityAuraEventsByUnit.arena4 == sentinel, "identity loop overwrote an existing arena4 entry")
Check(fake._ClassicIdentityAuraEventsByUnit.arena5 == fake._ClassicArenaIdentityAuraEvents,
    "arena5 lacks the arena identity events")
Check(fake._ClassicIdentityCombatAuraEventsByUnit.arena4 == fake._ClassicArenaIdentityCombatAuraEvents
    and fake._ClassicIdentityCombatAuraEventsByUnit.arena5 == fake._ClassicArenaIdentityCombatAuraEvents,
    "arena4/5 lack the arena combat identity events")
Check(fake._ClassicIdentityAuraEventsByUnit.arena6 == nil, "identity events reached arena6")

_G.MSUF_MAX_ARENA_FRAMES = 3
fake = {}
runIdentity(fake)
Check(fake._ClassicIdentityAuraEventsByUnit.arena3 ~= nil and fake._ClassicIdentityAuraEventsByUnit.arena4 == nil,
    "identity events reached arena4 at three slots")

print("PASS Classic arena five-slot Auras: seeded arena4/5 owners, idempotent and count-gated; compile, menu and identity fan-out")
