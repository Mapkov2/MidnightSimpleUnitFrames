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
-- A renamed/removed seam must fail loudly: without the counter installed the
-- probe assertion below would be vacuously true.
local probes = 0
local function CountUpvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then
            debug.setupvalue(fn, i, function(...) probes = probes + 1; return value(...) end)
            return i
        end
    end
    error("missing upvalue '" .. tostring(wanted) .. "' in ReadDeadCached: the empty-cache probe count cannot be measured", 2)
end
assert(CountUpvalue(UF.ReadDeadCached, "FreshUnitState"))
assert(CountUpvalue(UF.ReadDeadCached, "IdentityDispatchState"))
for i = 1, 1000 do UF.ReadDeadCached(frame, "party1") end
assert(probes == 0, "non-dispatch hot path retained empty cache probes")

-- Aura aliases now have no live lifecycle: the retained catalog contract
-- rejects aura API reads, protected calls, event registration and scheduling.
assert(loadfile(root .. "/.github/scripts/auras3_alias_catalog_smoke.lua"))()
print("worldboss_followup_hotpath_smoke: ok (native death/cache parity, cold Aura aliases, zero redundant probes)")
