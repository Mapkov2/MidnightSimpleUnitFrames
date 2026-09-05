-- Public-runtime regressions for the follow-up world-boss hotpath changes.
local root = arg and arg[1] or "."
local function Load(path, ns)
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
local SECRET = setmetatable({}, {
    __eq = function() error("secret compared") end,
    __index = function() error("secret indexed") end,
})
_G.issecretvalue = function(value) return rawequal(value, SECRET) end
_G.CreateFrame = function() return nil end
_G.InCombatLockdown = function() return false end

-- Both native providers, their legacy absence and secret/nil fallbacks. Every
-- non-dispatch call must still read fresh native state, including resurrection.
local cases = {
    { ghost = true, dead = false, value = true, known = true, fallback = false },
    { ghost = false, dead = false, value = false, known = true, fallback = true },
    { ghost = false, dead = true, value = true, known = true, fallback = true },
    { ghost = nil, dead = true, value = true, known = true, fallback = true },
    { ghost = SECRET, dead = true, value = true, known = true, fallback = true },
    { ghost = SECRET, dead = false, value = false, known = true, fallback = true },
    { ghost = SECRET, dead = SECRET, value = false, known = false, fallback = true },
    { ghost = nil, dead = nil, value = false, known = false, fallback = true },
    { ghost = 1, dead = false, value = true, known = true, fallback = false },
    { ghost = 0, dead = true, value = false, known = true, fallback = false },
}
local ghost, dead, ghostCalls, deadCalls
_G.UnitIsDeadOrGhost = function() ghostCalls = ghostCalls + 1; return ghost end
_G.UnitIsDead = function() deadCalls = deadCalls + 1; return dead end
local ns = {}
Load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua", ns)
local UF = ns.UF
local frame = { MSUFUnitKey = "party1", _msufDispatchToken = 10 }
for _, case in ipairs(cases) do
    ghost, dead = case.ghost, case.dead
    ghostCalls, deadCalls = 0, 0
    frame._msufUnitState = { ready = true, unit = "party1", dispatchToken = 10,
        deadKnown = true, dead = not case.value }
    for i = 1, 2 do
        local value, known = UF.ReadDeadCached(frame, "party1")
        assert(value == case.value and known == case.known, "native death result drifted")
    end
    assert(ghostCalls == 2 and deadCalls == (case.fallback and 2 or 0),
        "non-dispatch state was reused or a native fallback changed")
end
-- Explicit snapshots take precedence even without an active dispatch/frame.
ghostCalls, deadCalls = 0, 0
local value, known = UF.ReadDeadCached(nil, "party1", { deadKnown = true, dead = true })
assert(value and known and ghostCalls == 0 and deadCalls == 0, "explicit death snapshot lost priority")
-- Active dispatch still shares one native read, expires on the next token,
-- and never shares a dependent unit's read with its bound unit.
frame._msufUnitState, frame._msufDispatchActive = {}, true
ghost, dead, ghostCalls, deadCalls = true, false, 0, 0
assert(UF.ReadDeadCached(frame, "party1") == true)
ghost = false
assert(UF.ReadDeadCached(frame, "party1") == true and ghostCalls == 1, "dispatch did not share death read")
frame._msufDispatchToken = 11
assert(UF.ReadDeadCached(frame, "party1") == false and ghostCalls == 2, "death cache survived next dispatch")
ghost = true
assert(UF.ReadDeadCached(frame, "party1target") == true and ghostCalls == 3, "dependent unit reused bound death")
assert(UF.ReadDeadCached(frame, "party1") == false and ghostCalls == 3, "dependent read polluted bound death")
frame._msufDispatchActive = nil
assert(UF.ReadDeadCached(frame, "party1") == true and ghostCalls == 4, "non-dispatch read reused previous event")

for _, providers in ipairs({ {true, false}, {false, true}, {false, false} }) do
    ghostCalls, deadCalls, ghost, dead = 0, 0, true, true
    _G.UnitIsDeadOrGhost = providers[1] and function() ghostCalls = ghostCalls + 1; return ghost end or nil
    _G.UnitIsDead = providers[2] and function() deadCalls = deadCalls + 1; return dead end or nil
    local legacy = {}
    Load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua", legacy)
    value, known = legacy.UF.ReadDeadCached(nil, "party1")
    assert(value == (providers[1] or providers[2]) and known == true, "missing provider fallback drifted")
end

-- Count only the cache probes which cannot serve the non-dispatch route.
local probes = 0
for i = 1, 100 do
    local name, fn = debug.getupvalue(UF.ReadDeadCached, i)
    if not name then break end
    if name == "FreshUnitState" or name == "IdentityDispatchState" then
        debug.setupvalue(UF.ReadDeadCached, i, function(...) probes = probes + 1; return fn(...) end)
    end
end
for i = 1, 1000 do UF.ReadDeadCached(frame, "party1") end
assert(probes == 0, "non-dispatch hot path retained empty cache probes")

-- The unresolved Aura must be queried on every separate fallback flush. A
-- failed native lookup must not lose registration or prevent a later success.
local onEvent, onUpdate, scans, registration, result = nil, nil, 0, nil, nil
_G.CreateFrame = function()
    return {
        SetScript = function(_, kind, fn)
            if kind == "OnEvent" then onEvent = fn else onUpdate = fn end
        end,
        RegisterUnitEvent = function(_, event, unit) registration = unit end,
        UnregisterAllEvents = function() registration = nil end,
    }
end
_G.C_Spell = { GetSpellName = function() return "Tracked Aura" end }
_G.C_UnitAuras = { GetAuraDataBySpellName = function(unit, name, filter)
    assert(unit == "target" and name == "Tracked Aura" and filter == "HELPFUL")
    scans = scans + 1
    if scans % 3 == 0 and not result then error("native lookup restricted") end
    return result
end }
_G.C_Timer = { After = function(_, fn) fn() end }
local auraNS = { MSUF_Auras3 = { RequestScope = function() end } }
Load("Auras3/MSUF_Auras3_AuraNameResolver.lua", auraNS)
local resolver = auraNS.MSUF_Auras3.AuraNameResolver
local scan, syncCalls
for i = 1, 100 do
    local name, fn = debug.getupvalue(resolver.SetContainerActive, i)
    if not name then break end
    if name == "ScanContainer" then scan = fn; break end
end
assert(scan, "activation scan was not found")
syncCalls = 0
for i = 1, 100 do
    local name, fn = debug.getupvalue(scan, i)
    if not name then break end
    if name == "SyncContainerActiveWork" then
        debug.setupvalue(scan, i, function(...) syncCalls = syncCalls + 1; return fn(...) end)
    end
end
local container = { unit = "target", _msufA3NativeLaneConfig = {
    nativeFilter = "HELPFUL", nameAliasSpellIDs = { [123] = true },
    candidateFilters = { includeSpellIDs = { [123] = true } },
} }
assert(resolver.SyncContainer(container))
assert(registration == "target" and container._msufA3AuraAliasHasActiveWork == true)
syncCalls = 0
for i = 1, 1000 do
    onEvent(nil, "UNIT_AURA", "target", { isFullUpdate = true })
    assert(onUpdate, "unresolved Aura stopped queuing lookups")
    onUpdate()
end
assert(scans == 1001 and syncCalls == 0, "unchanged scan repeated work synchronization")
result = { name = "Tracked Aura", spellId = 456 }
onEvent(nil, "UNIT_AURA", "target", { isFullUpdate = true }); onUpdate()
assert(syncCalls == 1 and container._msufA3AuraAliasHasActiveWork == nil,
    "exhausted list retained active work")
assert(auraNS.MSUF_Auras3.AuraSpellIDAliases[123][1] == 456, "later Aura was missed")
onEvent(nil, "UNIT_AURA", "target", { isFullUpdate = true })
assert(onUpdate == nil, "exhausted list retained fallback driver")
resolver.SetContainerActive(container, false)
result = nil
resolver.SetContainerActive(container, true)
assert(container._msufA3AuraAliasHasActiveWork == true and registration == "target",
    "reactivation failed to restore unresolved work")
onEvent(nil, "UNIT_AURA", "target", { isFullUpdate = true })
assert(onUpdate, "reactivated unresolved Aura did not queue")
resolver.UnregisterContainer(container)
assert(onUpdate == nil and registration == nil, "unregister retained pending work")
print("worldboss_followup_hotpath_smoke: ok (native death/cache parity, Aura lifecycle, zero redundant probes)")
