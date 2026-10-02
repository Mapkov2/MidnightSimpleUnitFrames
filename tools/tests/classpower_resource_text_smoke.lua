-- classpower_resource_text_smoke.lua <repoRoot>
--
-- The Class Resource count text. Every render mode paints it through one
-- helper (CP_PaintResourceText in ClassPower/MSUF_CP_Modes.lua): hidden unless
-- the text is switched on, an explicit text mode (Current, Max, Current / Max)
-- wins over the mode's own presentation, and a Warlock shard prediction adds a
-- "*". This smoke drives the real stack (tools/tests/classpower_world.lua)
-- through combo points, restricted combo points, Affliction, Demonology and
-- Destruction shards with and without a prediction, runes and Maelstrom Weapon,
-- and checks the text, its visibility and its colour.
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT

--- The count text is off by default; every case here turns it on unless it
--- says otherwise.
local function Start(class, spec, primary, bars)
    local merged = { classPowerShowText = true }
    for key, value in pairs(bars or {}) do merged[key] = value end
    return World.Start(repo, "Mainline", class, spec, primary, merged)
end

local failures = {}
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end

local function Text(t)
    local txt = t.CP.text
    return txt and txt.shown and txt:GetText() or nil
end

local function Color(t)
    local r, g, b = t.CP.text:GetTextColor()
    return ("%.2f,%.2f,%.2f"):format(r or -1, g or -1, b or -1)
end

local WHITE, RED = "1.00,1.00,1.00", "1.00,0.10,0.10"

local function Power(t, token)
    t.onEvent(t.eventFrame, "UNIT_POWER_UPDATE", "player", token)
    t.env:RunTimers()
end

-- Combo points: the default count, then every explicit text mode.
do
    local t = Start("ROGUE", 1, PT.ENERGY)
    Check(Text(t) == 3 and Color(t) == WHITE, "Rogue combo text is not a white 3: " .. tostring(Text(t)))
    t.S.combo = 4
    Power(t, "COMBO_POINTS")
    Check(Text(t) == 4, "Rogue combo text did not follow the power event")
    for mode, expected in pairs({ CURRENT = 4, MAX = 5, CURMAX = "4 / 5" }) do
        local m = Start("ROGUE", 1, PT.ENERGY, { classPowerTextMode = mode })
        m.S.combo = 4
        Power(m, "COMBO_POINTS")
        Check(Text(m) == expected, mode .. " text is " .. tostring(Text(m)))
    end
    local off = Start("ROGUE", 1, PT.ENERGY, { classPowerShowText = false })
    Check(Text(off) == nil, "the count shows although Class Resource text is off")
    -- Turned off later: the existing count hides and stays hidden.
    local later = Start("ROGUE", 1, PT.ENERGY)
    Check(Text(later) == 3, "the count did not show before it was turned off")
    MSUF_DB.bars.classPowerShowText = false
    later.CP.RefreshPublic()
    later.env:RunTimers()
    Power(later, "COMBO_POINTS")
    Check(later.CP.text and not later.CP.text.shown, "the count stays shown after Class Resource text was turned off")
end

-- Restricted combo points go straight to the native widget.
do
    local t = Start("ROGUE", 1, PT.ENERGY)
    t.S.secretPower = true
    Power(t, "COMBO_POINTS")
    local text = Text(t)
    Check(type(text) == "table" and text.__secret == true, "a restricted combo count was not passed through")
end

-- Warlock shards: prediction suffix and the low-shard colour (Demonology 3).
do
    local t = Start("WARLOCK", 1, PT.MANA)
    Check(Text(t) == 3 and Color(t) == WHITE, "Affliction shard text is not a white 3")
    t.CP.wlPredDelta = 1
    Power(t, "SOUL_SHARDS")
    Check(Text(t) == "3*" and Color(t) == WHITE, "Affliction prediction text is " .. tostring(Text(t)))
    local demo = Start("WARLOCK", 2, PT.MANA)
    demo.S.shards = 2
    Power(demo, "SOUL_SHARDS")
    Check(Text(demo) == 2 and Color(demo) == RED, "Demonology below 3 shards is not red")
    local nopred = Start("WARLOCK", 2, PT.MANA, { classPowerShowPrediction = false })
    nopred.S.shards = 2
    nopred.CP.wlPredDelta = 1
    Power(nopred, "SOUL_SHARDS")
    Check(Text(nopred) == 2 and Color(nopred) == WHITE, "prediction off still marks or colours the shards")
    local curmax = Start("WARLOCK", 1, PT.MANA, { classPowerTextMode = "CURMAX" })
    curmax.CP.wlPredDelta = 1
    Power(curmax, "SOUL_SHARDS")
    Check(Text(curmax) == "3* / 5", "Current / Max prediction text is " .. tostring(Text(curmax)))
end

-- Destruction: one decimal while a shard is partly filled, red below 2.
do
    local t = Start("WARLOCK", 3, PT.MANA)
    t.S.unmodified, t.S.displayMod = 37, 10
    Power(t, "SOUL_SHARDS")
    Check(Text(t) == "3.7" and Color(t) == WHITE, "Destruction partial shards text is " .. tostring(Text(t)))
    t.CP.wlPredDelta = 1
    Power(t, "SOUL_SHARDS")
    Check(Text(t) == "3.7*", "Destruction prediction text is " .. tostring(Text(t)))
    t.S.unmodified = 10
    Power(t, "SOUL_SHARDS")
    Check(Text(t) == "1*" and Color(t) == RED, "Destruction below 2 shards is not a red 1*: " .. tostring(Text(t)))
end

-- Runes and Maelstrom Weapon: the ready rune count and the stack count.
do
    local dk = Start("DEATHKNIGHT", 1, 6)
    Check(Text(dk) == 3, "the ready rune count is " .. tostring(Text(dk)))
    local shaman = Start("SHAMAN", 2, PT.MANA)
    Check(Text(shaman) == 2, "the Maelstrom Weapon stack count is " .. tostring(Text(shaman)))
end

-- Mists Balance: the signed Eclipse bar honours the Class Resource text mode
-- too; AUTO keeps its current / max presentation.
do
    local PT_BALANCE = 26
    for mode, expected in pairs({ AUTO = "3 / 5", CURRENT = 3, MAX = 5, CURMAX = "3 / 5" }) do
        local t = World.Start(repo, "Mists", "DRUID", 1, PT.MANA,
            { classPowerShowText = true, classPowerTextMode = mode })
        Check(t.CP.visible and t.CP.powerType == PT_BALANCE, "Mists Balance did not route Eclipse")
        Power(t, "BALANCE")
        Check(Text(t) == expected, "Mists Eclipse " .. mode .. " text is " .. tostring(Text(t)))
    end
end

if #failures > 0 then
    error("classpower_resource_text_smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_resource_text_smoke: ok (combo, restricted, shard, rune, aura and Eclipse counts)")
