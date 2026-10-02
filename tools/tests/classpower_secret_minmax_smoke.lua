-- classpower_secret_minmax_smoke.lua <repoRoot>
--
-- CP_StampMinMax (ClassPower/MSUF_CP_Modes.lua) caches a bar's min/max and
-- skips an unchanged write. type() reports "number" for a secret number on
-- the 12.x client, so a type guard alone let a secret maximum (Stagger's
-- UnitHealthMax, SecretWhenUnitHealthMaxRestricted) into the cache and the
-- next update compared it. A secret range must clear the cache and go
-- straight to SetMinMaxValues.
--
-- Secrets come from tools/tests/classpower_secrets.lua (client-strict: type()
-- answers "number", comparisons raise, a line hook records == / ~= on a secret
-- local). Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local MODES = repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Modes.lua"
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local Secrets = assert(loadfile(repo .. "/tools/tests/classpower_secrets.lua"))()
local PT = World.PT

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local t = World.Start(repo, "Mainline", "MONK", 1, PT.ENERGY, nil,
    { beforeLoad = function() Secrets.Install() end })
local CP, bar = t.CP, t.CP.bars[1]
Check(CP.visible and CP.powerType == -1, "Brewmaster did not route Stagger")
Check(bar.maximum == 1000, "plain Stagger maximum not painted")

local function Tick()
    local stop = Secrets.Watch(MODES)
    local ok, err = pcall(CP.RefreshPublic)
    local violations = stop()
    return ok, err, violations
end

-- Two updates in a row with a restricted maximum health.
for pass = 1, 2 do
    t.S.healthMax = Secrets.New("number")
    local ok, err, violations = Tick()
    Check(ok, "Stagger update " .. pass .. " with a secret maximum raised: " .. tostring(err))
    Check(#violations == 0, "Stagger update " .. pass .. " compared a secret:\n    "
        .. table.concat(violations, "\n    "))
    Check(rawequal(bar.maximum, t.S.healthMax), "Stagger update " .. pass .. " did not hand the secret maximum to the bar")
    Check(bar._msufCPMax == nil, "a secret maximum entered the min/max cache")
end

-- A plain maximum afterwards is written again, not skipped against the cache.
t.S.healthMax = 1000
local ok, err = Tick()
Check(ok, "Stagger update with a plain maximum raised: " .. tostring(err))
Check(bar.maximum == 1000, "the plain maximum after a secret one was skipped")

if #failures > 0 then
    error("classpower_secret_minmax_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_secret_minmax_smoke: ok (secret Stagger maximum bypasses the min/max cache)")
