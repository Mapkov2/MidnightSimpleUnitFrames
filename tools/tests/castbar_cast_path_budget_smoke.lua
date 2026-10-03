-- castbar_cast_path_budget_smoke.lua <repoRoot> [print]
--
-- Cost budgets for whole castbar cast paths on the real Mainline core
-- (tools/tests/castbar_secret_world.lua in budget mode: every object a native
-- returns and every secret is reused, so the bytes below are the addon's own).
-- Each operation is one complete cast as the client delivers it, and is
-- measured three ways:
--   * Lua VM instructions inside addon files (the harness's own excluded);
--   * bytes the addon allocates, with a full collection before every run and
--     the collector stopped during it. The collection turns the nil fields of
--     the castbar frames into dead keys, as the client's collector does
--     between casts, so re-inserting a cleared field shows up as the table
--     growth it causes in game;
--   * native calls that return a new object in the client (a cooldown info
--     table, a duration object, a colour object, a C_Timer handle), which the
--     raid trace showed are invisible to the other two.
-- Paths: a target cast with its spell target name and interrupt-ready box,
-- readable and secret; a boss cast with secret values (the failsafe ticker);
-- the GCD bar for a readable and a secret GCD; an interrupt cooldown event.
-- "print" reports the measured values.
--
-- Plain Lua 5.1, repo root (absolute) as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local printOnly = arg[2] == "print"
local SecretWorld = assert(loadfile(root .. "/tools/tests/castbar_secret_world.lua"))()

-- instructions, bytes, native object calls per operation. Frozen 2026-10-02
-- from the measured cost plus 2 % (bytes: plus 10 %, a table regrowth moves
-- with the hash layout; native calls exact). Before this smoke the paths cost
-- (instructions / bytes / natives): target readable 7460 / 204 / 7, target
-- secret 7429 / 183 / 7, boss secret 7540 / 163 / 7, GCD readable
-- 1082 / 0 / 3, GCD secret 1554 / 0 / 19 (a SpellCooldownInfo table per
-- 0.1 s poll), cooldown event 1530 / 0 / 2. The GCD paths trade about 130
-- VM instructions for the cooldown info table and the C_Timer handle.
local BUDGETS = {
    ["target cast, readable"] = { 7660, 224, 5 },
    ["target cast, secret"] = { 7596, 202, 6 },
    ["boss cast, secret"] = { 7709, 180, 6 },
    ["GCD instant, readable"] = { 1238, 8, 1 },
    ["GCD instant, secret"] = { 1207, 8, 2 },
    ["interrupt cooldown event"] = { 1561, 8, 2 },
}

-- Natives whose result is a new Lua object in the client.
local OBJECT_NATIVES = { "GetSpellCooldown", "GetSpellCooldownDuration", "UnitDuration", "GetClassColor",
    "EvaluateColorFromBoolean", "NewTimer", "NewTicker" }

local world = SecretWorld.New(root, { budget = true })
local env = world.env
env.MSUF_EnsureDB(true)
local g = env.MSUF_DB.general
g.kickReadyShowTarget, g.kickReadyShowBoss, g.kickReadyStyle = true, true, "box"
g.castbarTargetShowTargetName, g.showBossCastTargetName = true, true
g.showGCDBar, g.showGCDBarTime, g.showGCDBarSpell = true, true, true
env.MSUF_Castbars_OnSettingsChanged()
env.MSUF_KickReady_RefreshAll()
world:Advance(0.5)
for index = #world.errors, 1, -1 do world.errors[index] = nil end

local target = assert(env.MSUF_TargetCastBar, "target castbar missing")
local boss = assert(env.MSUF_BossCastbars and env.MSUF_BossCastbars[1], "boss castbar missing")
local gcdDriver = assert(world:Named("MSUF_GCDBarDriver"), "GCD driver missing")
local readyFrame = assert(world:Named("MSUF_InterruptReady_EventFrame"), "interrupt-ready event frame missing")

-- Reused casts and payloads: the harness allocates nothing per operation.
local casts = {}
local function Cast(unit, seconds, barID)
    local cast = casts[unit] or {}
    casts[unit] = cast
    local startMS = math.floor(world.clock * 1000)
    cast.name, cast.startMS, cast.endMS, cast.spellID, cast.castBarID = "Shadow Bolt", startMS, startMS + seconds * 1000,
        133, barID
    world.casting[unit] = cast
end

-- One cast with a pushback: START, DELAYED, the manager ticks to the end, STOP
-- and its confirmation.
local function CastCycle(frame, unit)
    Cast(unit, 0.6, 7)
    world:Fire(frame, "UNIT_SPELLCAST_START", unit, nil, nil, 7)
    world:Advance(0.2)
    world:Fire(frame, "UNIT_SPELLCAST_DELAYED", unit, nil, nil, 7)
    world:Advance(0.5)
    world.casting[unit] = nil
    world:Fire(frame, "UNIT_SPELLCAST_STOP", unit, nil, nil, 7)
    world:Advance(0.6)
end

local OPERATIONS = {
    { "target cast, readable", function() world.secretCasts = false end, function() CastCycle(target, "target") end },
    { "target cast, secret", function() world.secretCasts = true end, function() CastCycle(target, "target") end },
    { "boss cast, secret", function() world.secretCasts = true end, function() CastCycle(boss, "boss1") end },
    { "GCD instant, readable", function() world.secretCooldowns = false end, function()
        world.cooldowns[61304] = world.cooldowns[61304] or {}
        world.cooldowns[61304].startTime, world.cooldowns[61304].total = world.clock, 1.5
        world:Fire(gcdDriver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1449)
        world:Advance(1.7)
    end },
    { "GCD instant, secret", function() world.secretCooldowns = true end, function()
        world.cooldowns[61304].startTime, world.cooldowns[61304].total = world.clock, 1.5
        world:Fire(gcdDriver, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1449)
        world:Advance(1.7)
    end },
    { "interrupt cooldown event", function()
        world.secretCooldowns, world.secretCasts = false, false
        world.cooldowns[2139] = { startTime = world.clock, total = 0 }
        Cast("target", 600, 9)
        world:Fire(target, "UNIT_SPELLCAST_START", "target", nil, nil, 9)
    end, function()
        world.cooldowns[2139].startTime, world.cooldowns[2139].total = world.clock, 0.5
        world:Fire(readyFrame, "SPELL_UPDATE_COOLDOWN", 2139, 2139)
        world:Advance(0.6)
    end },
}

-- A full collection also shrinks the Lua stack; the next deep call regrows it.
-- That is the collector's cost, not the cast path's, so the stack is regrown
-- before each measured run.
local function RegrowStack(depth)
    local a, b, c, d, e, f, g2, h = 1, 2, 3, 4, 5, 6, 7, 8
    if depth > 0 then return RegrowStack(depth - 1) + a + b + c + d + e + f + g2 + h end
    return 0
end

-- The frozen byte ceilings used 32-bit Lua strings (16-byte headers).
-- These casts create five short strings when readable and four when secret:
-- MSUF_Colors' detail key and its R/G/B suffixes, plus one additional transient
-- string in the readable path. Count their payloads and baseline headers, correcting
-- only the runtime's larger header representation, never other allocations.
local STRING_COUNTS = {
    ["target cast, readable"] = 5, ["target cast, secret"] = 4, ["boss cast, secret"] = 4,
}
collectgarbage("collect")
collectgarbage("stop")
RegrowStack(300)
local stringBefore = collectgarbage("count")
local stringProbe = string.rep("q", 257)
local stringHeader = (collectgarbage("count") - stringBefore) * 1024 - #stringProbe - 1
collectgarbage("restart")
assert(stringHeader == 16 or stringHeader == 24, "unexpected Lua 5.1 string representation")
local stringHeaderExcess = stringHeader - 16

local WARMUP, REPS = 4, 12
local measured = {}
for _, operation in ipairs(OPERATIONS) do
    local label, setup, run = operation[1], operation[2], operation[3]
    assert(BUDGETS[label], "no budget for " .. label)
    setup()
    for _ = 1, WARMUP do run() end
    local ticks = world:AddonInstructions(function()
        for _ = 1, REPS do run() end
    end)
    local before = {}
    for index = 1, #OBJECT_NATIVES do before[index] = world.counts[OBJECT_NATIVES[index]] end
    local bytes = 0
    for _ = 1, REPS do
        collectgarbage("collect")
        collectgarbage("stop")
        RegrowStack(300)
        local harness = world.harnessBytes
        local start = collectgarbage("count")
        run()
        bytes = bytes + (collectgarbage("count") - start) * 1024 - (world.harnessBytes - harness)
            - (STRING_COUNTS[label] or 0) * stringHeaderExcess
        collectgarbage("restart")
    end
    local natives, detail = 0, {}
    for index = 1, #OBJECT_NATIVES do
        local calls = world.counts[OBJECT_NATIVES[index]] - before[index]
        if calls > 0 then
            natives = natives + calls
            detail[#detail + 1] = ("%s %.1f"):format(OBJECT_NATIVES[index], calls / REPS)
        end
    end
    measured[#measured + 1] = { label = label, instructions = ticks / REPS, bytes = bytes / REPS,
        natives = natives / REPS, detail = table.concat(detail, ", ") }
end
assert(#world.errors == 0, "castbar errors during the measurement: " .. table.concat(world.errors, "; "))

-- Field churn. A field a cast clears to nil and the next cast sets again is
-- dead after the collector ran in between, so setting it inserts a new key
-- and can regrow the frame table (the raid trace's ApplyNativeTimeText and
-- ApplyCastTargetTextColor bytes). These per-cast flags stay false instead,
-- and an empty text cache is not cleared again. A __newindex recorder sees
-- every insertion of a key the table does not hold; only castbar files are
-- held to it (the shared text cache of Kernel/MSUF_Util.lua is not theirs).
local CHURN_WATCH = {
    _msufNativeTimeBound = true, _msufNativeTextUnsafe = true, _msufNativeCompletionTimer = true,
    _msufNativeCompletionDeadline = true, _msufNativeCompletionUnsafe = true, _msufNativeTimerUnsafe = true,
    _msufDurationSnapshotUnsafe = true, _msufLastText = true, _msufCastTargetColorPlain = true,
    _msufCastTargetClassSequence = true, _msufCastTargetClassGeneration = true,
}
local churned = {}
local function Record(widget, label)
    local meta = getmetatable(widget)
    setmetatable(widget, { __index = meta.__index, __newindex = function(t, key, value)
        if CHURN_WATCH[key] and debug.getinfo(2, "S").source:find("/Castbars/", 1, true) then
            churned[label .. "." .. key] = (value == nil) and "nil into an absent key" or "re-inserted"
        end
        rawset(t, key, value)
    end })
end
Record(target, "target")
Record(target.timeText, "target.timeText")
Record(target.castTargetText, "target.castTargetText")
Record(boss, "boss1")
for _, secret in ipairs({ false, true }) do
    world.secretCasts = secret
    CastCycle(target, "target")
    CastCycle(boss, "boss1")
end
for key in pairs(churned) do churned[key] = nil end
for _, secret in ipairs({ false, true }) do
    world.secretCasts = secret
    for _ = 1, 3 do
        CastCycle(target, "target")
        CastCycle(boss, "boss1")
    end
end
local churn = {}
for key, kind in pairs(churned) do churn[#churn + 1] = key .. " (" .. kind .. ")" end
table.sort(churn)

local failures = {}
for _, entry in ipairs(measured) do
    local budget = BUDGETS[entry.label]
    local line = ("%-26s %9.1f instructions %8.1f bytes %5.2f object natives (%s)  (budget %d / %d / %g)"):format(
        entry.label, entry.instructions, entry.bytes, entry.natives, entry.detail, budget[1], budget[2], budget[3])
    if printOnly then
        print(line)
    elseif entry.instructions > budget[1] or entry.bytes > budget[2] or entry.natives > budget[3] + 1e-9 then
        failures[#failures + 1] = line
    end
end
if printOnly then
    print("field churn: " .. (#churn > 0 and table.concat(churn, ", ") or "none"))
    return
end
if #churn > 0 then failures[#failures + 1] = "per-cast fields re-inserted every cast: " .. table.concat(churn, ", ") end
if #failures > 0 then
    error("castbar cast path over budget:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("castbar_cast_path_budget_smoke: ok (%d cast paths within instruction, byte and native budgets)"):format(#measured))
