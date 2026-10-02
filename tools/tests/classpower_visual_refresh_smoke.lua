-- classpower_visual_refresh_smoke.lua <repoRoot>
--
-- A visual refresh (MSUF_ClassPower_RefreshVisuals: the Colors panel, a
-- texture or font change, MSUF_ClassPower_InvalidateColors) repaints the bars
-- with the ACTIVE render mode. It used to call the segmented painter for every
-- mode: it hands an aura resource's string token ("MAELSTROM_WEAPON") to
-- UnitPower, which the client binding rejects, and repaints Stagger or a
-- continuous bar as one full 0..1 pip.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local PT = World.PT
local STRICT = { beforeLoad = function() World.StrictPowerTypes() end }

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local function Refresh(t)
    local ok, err = pcall(t.CP.RefreshVisualsPublic)
    return ok, err
end

-- Brewmaster Stagger: one bar, max = UnitHealthMax, value = UnitStagger.
do
    local t = World.Start(repo, "Mainline", "MONK", 1, PT.ENERGY, nil, STRICT)
    local bar = t.CP.bars[1]
    Check(t.CP.visible and t.CP.powerType == -1, "Brewmaster did not route Stagger")
    Check(bar and bar.maximum == 1000 and bar.value == 400, "Stagger did not paint its first update")
    t.S.stagger = 650
    local ok, err = Refresh(t)
    Check(ok, "a visual refresh in Stagger mode raised: " .. tostring(err))
    Check(bar.maximum == 1000, "a visual refresh repainted Stagger with another painter (max "
        .. tostring(bar.maximum) .. ")")
    Check(bar.value == 650, "a visual refresh did not repaint the current Stagger value")
end

-- Elemental Maelstrom (continuous): one bar over UnitPowerMax.
do
    local t = World.Start(repo, "Mainline", "SHAMAN", 1, PT.MANA, { showEleMaelstrom = true }, STRICT)
    local bar = t.CP.bars[1]
    Check(t.CP.visible and t.CP.renderMode == t.CP.visual.renderMode, "Elemental did not route Maelstrom")
    Check(bar and bar.maximum == 5 and bar.value == 3, "Maelstrom did not paint its first update")
    t.S.shards = 4
    local ok, err = Refresh(t)
    Check(ok, "a visual refresh in continuous mode raised: " .. tostring(err))
    Check(bar.maximum == 5 and bar.value == 4,
        "a visual refresh repainted the continuous bar as one pip (min/max "
        .. tostring(bar.minimum) .. "/" .. tostring(bar.maximum) .. ", value " .. tostring(bar.value) .. ")")
end

-- Enhancement Maelstrom Weapon (aura segmented): its token is a string.
do
    local t = World.Start(repo, "Mainline", "SHAMAN", 2, PT.MANA, nil, STRICT)
    Check(t.CP.visible and t.CP.powerType == "MAELSTROM_WEAPON", "Enhancement did not route Maelstrom Weapon")
    -- The aura painter repaints the cached stacks (2 of 10); no UNIT_AURA ran.
    t.CP.bars[2].value, t.CP.bars[2]._msufCPValue = nil, nil
    local ok, err = Refresh(t)
    Check(ok, "a visual refresh in aura mode raised: " .. tostring(err))
    Check(t.CP.bars[2].value == 1 and t.CP.bars[3].value == 0,
        "a visual refresh did not repaint the Maelstrom Weapon stacks")
end

-- Segmented resources keep their painter.
do
    local t = World.Start(repo, "Mainline", "ROGUE", 1, PT.ENERGY, nil, STRICT)
    t.S.combo = 4
    local ok, err = Refresh(t)
    Check(ok, "a visual refresh in segmented mode raised: " .. tostring(err))
    Check(t.CP.bars[4].value == 1 and t.CP.bars[5].value == 0, "a visual refresh lost the combo points")
end

if #failures > 0 then
    error("classpower_visual_refresh_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_visual_refresh_smoke: ok (Stagger, continuous and segmented repaint with their own painter)")
