-- classpower_max_resolution_smoke.lua <repoRoot>
--
-- One resolver answers the visible segment count of the active class
-- resource (Refresh.ResolveMaxPower in ClassPower/MSUF_CP_Controller.lua).
-- The full refresh and the light refresh after UNIT_MAXPOWER or a talent
-- event use it with one difference each, which this smoke pins:
--   * a secret or missing maximum: the full refresh guesses 5, the light
--     refresh keeps the current count (runes 6 and combo points 7 always);
--   * Tip of the Spear: only the full refresh resets the tracked stacks.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

--- A world whose class resource maximum follows S.max (S.secretMax: restricted).
local function Start(class, spec, primary)
    return World.Start(repo, "Mainline", class, spec, primary, nil, { beforeLoad = function(_, S)
        local native = UnitPowerMax
        UnitPowerMax = function(unit, powerType, unmodified)
            if powerType ~= S.primary then
                if S.secretMax then return { __secret = true } end
                if S.max then return S.max end
            end
            return native(unit, powerType, unmodified)
        end
    end })
end

local function MaxPower(t, token)
    t.onEvent(t.eventFrame, "UNIT_MAXPOWER", "player", token)
    t.env:RunTimers()
end

-- Affliction soul shards: plain, light, secret light, secret full.
do
    local t = Start("WARLOCK", 1, PT.MANA)
    Check(t.CP.currentMax == 5, "Affliction did not start with 5 shards")
    t.S.max = 4
    MaxPower(t, "SOUL_SHARDS")
    Check(t.CP.currentMax == 4, "a plain UNIT_MAXPOWER did not resize the shards")
    t.S.secretMax = true
    MaxPower(t, "SOUL_SHARDS")
    Check(t.CP.currentMax == 4, "a secret maximum on the light refresh must keep the current count")
    t.CP.RefreshPublic()
    t.env:RunTimers()
    Check(t.CP.currentMax == 5, "a secret maximum on the full refresh must fall back to 5")
end

-- Combo points keep their own secret fallback (7) on both refreshes.
do
    local t = Start("ROGUE", 1, PT.ENERGY)
    t.S.secretMax = true
    MaxPower(t, "COMBO_POINTS")
    Check(t.CP.currentMax == 7, "secret combo point maximum (light) is not 7")
    t.CP.RefreshPublic()
    t.env:RunTimers()
    Check(t.CP.currentMax == 7, "secret combo point maximum (full) is not 7")
end

-- Tip of the Spear: a talent event keeps the stacks, a full refresh resets them.
do
    local t = Start("HUNTER", 3, 2)
    Check(t.CP.powerType == "TIP_OF_THE_SPEAR" and t.CP.currentMax == 3, "Survival did not route Tip of the Spear")
    t.CP.spStacks, t.CP.spExpires = 2, 1e9
    t.onEvent(t.eventFrame, "PLAYER_TALENT_UPDATE")
    t.env:RunTimers()
    Check(t.CP.spStacks == 2, "a light refresh reset the Tip of the Spear stacks")
    t.CP.RefreshPublic()
    t.env:RunTimers()
    Check(t.CP.spStacks == 0 and t.CP.spExpires == nil, "a full refresh kept the Tip of the Spear stacks")
end

-- Fixed counts.
for _, case in ipairs({
    { "DEATHKNIGHT", 1, 6, 6, "runes" },
    { "MONK", 1, PT.ENERGY, 1, "Stagger" },
    { "SHAMAN", 2, PT.MANA, 10, "Maelstrom Weapon" },
    { "WARRIOR", 2, PT.RAGE, 1, "Whirlwind" },
}) do
    local t = Start(case[1], case[2], case[3])
    Check(t.CP.currentMax == case[4], case[5] .. " count is " .. tostring(t.CP.currentMax))
    t.onEvent(t.eventFrame, "PLAYER_TALENT_UPDATE")
    t.env:RunTimers()
    Check(t.CP.currentMax == case[4], case[5] .. " count after a light refresh is " .. tostring(t.CP.currentMax))
end

if #failures > 0 then
    error("classpower_max_resolution_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_max_resolution_smoke: ok (shards, combo points, Tip of the Spear, fixed counts)")
