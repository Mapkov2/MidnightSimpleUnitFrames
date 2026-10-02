-- classpower_paint_stamps_smoke.lua <repoRoot>
--
-- The ClassPower painters skip a widget write when the widget's _msufCP*
-- stamp already holds the value (MSUF_CP_Modes.lua stamp helpers). A writer
-- that paints the same widgets without those helpers must leave the stamps
-- truthful, or the next mode on the same bar skips a write it needs:
--   * Ironfur (Guardian Bear) paints pip 1 and the count text directly;
--     after Bear -> Cat the combo points must repaint pip 1 and the text.
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

local function SameColor(a, b)
    return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function DisplayPower(t, primary)
    t.S.primary = primary
    t.env:AdvanceTime(1)
    World.Dispatcher(t, "UNIT_DISPLAYPOWER", "player", "ENERGY")()
    t.env:RunTimers()
end

-- Ironfur: Cat (combo points) -> Bear (Ironfur) -> Cat.
do
    local t = World.Start(repo, "Mainline", "DRUID", 3, PT.ENERGY,
        { showGuardianIronfur = true, classPowerShowText = true })
    local CP = t.CP
    Check(CP.visible and CP.powerType == PT.COMBO, "Guardian in Cat form did not route combo points")
    local bar, text = CP.bars[1], CP.text
    local comboColor = { bar.color[1], bar.color[2], bar.color[3] }
    Check(bar.alpha == 1 and text and text.shown and text.text == 3, "Cat form did not paint 3 combo points")

    DisplayPower(t, PT.RAGE)
    Check(CP.powerType == "IRONFUR", "Guardian in Bear form did not route Ironfur")
    Check(not SameColor(bar.color, comboColor) and bar.alpha ~= 1 and text.shown == false,
        "Ironfur did not paint pip 1 and hide the count")

    DisplayPower(t, PT.ENERGY)
    Check(CP.powerType == PT.COMBO, "Guardian back in Cat form did not route combo points")
    Check(SameColor(bar.color, comboColor), "pip 1 kept the Ironfur colour after Bear -> Cat")
    Check(bar.alpha == 1, "pip 1 kept the Ironfur alpha after Bear -> Cat")
    Check(bar.value == 1, "pip 1 kept the Ironfur fill after Bear -> Cat")
    Check(text.shown == true and text.text == 3, "the combo count stayed hidden or stale after Bear -> Cat")
end

-- Stagger caches its colour tier. A colour edit or a return to Brewmaster
-- compiles a new visual and must repaint the tier colour.
do
    local t = World.Start(repo, "Mainline", "MONK", 1, PT.ENERGY)
    local CP, bar = t.CP, t.CP.bars[1]
    Check(CP.visible and CP.powerType == -1, "Brewmaster did not route Stagger")
    local yellow = bar.color and { bar.color[1], bar.color[2], bar.color[3] }
    Check(SameColor(yellow, { 1.00, 0.98, 0.72 }), "40 % Stagger is not the yellow tier")

    MSUF_DB.general.classPowerColorOverrides = { STAGGER_YELLOW = { 0.1, 0.2, 0.3 } }
    _G.MSUF_ClassPower_InvalidateColors()
    t.env:RunTimers()
    Check(SameColor(bar.color, { 0.1, 0.2, 0.3 }), "a Stagger colour edit did not repaint the current tier")

    MSUF_DB.general.classPowerColorOverrides = nil
    t.S.spec = 3
    CP.RefreshPublic()
    t.env:RunTimers()
    Check(CP.powerType == PT.CHI or CP.powerType == 12, "Windwalker did not route Chi")
    Check(not SameColor(bar.color, yellow), "Chi did not repaint pip 1")
    t.S.spec = 1
    CP.RefreshPublic()
    t.env:RunTimers()
    Check(CP.powerType == -1, "Brewmaster did not route Stagger again")
    Check(SameColor(bar.color, yellow), "returning to Brewmaster kept the Chi colour on the Stagger bar")
end

-- Balance eclipse colours the Player Power bar, which the Power element owns
-- and dedupes with its _msufR/_msufG/_msufB/_msufA stamp. When the eclipse
-- ends the bar must show the Power element's colour again.
do
    local SOLAR = 1233346
    local solarUntil
    local auras = {}
    local t = World.Start(repo, "Mainline", "DRUID", 1, 8, nil, { beforeLoad = function(_, S)
        C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
            if spellID == SOLAR and solarUntil then
                auras[spellID] = auras[spellID] or { spellId = spellID, auraInstanceID = 77, duration = 15 }
                auras[spellID].expirationTime = solarUntil
                return auras[spellID]
            end
            return nil
        end
    end })
    local playerFrame = MSUF_NS.UF.GetFrame("player")
    local bar = CreateFrame("StatusBar", nil, playerFrame)
    playerFrame.targetPowerBar = bar
    local BASE = { 0.30, 0.52, 0.90, 1 }
    -- What the Power element's SetColor leaves behind: colour and stamp.
    bar:SetStatusBarColor(BASE[1], BASE[2], BASE[3], BASE[4])
    bar._msufR, bar._msufG, bar._msufB, bar._msufA = BASE[1], BASE[2], BASE[3], BASE[4]
    local balanceFrame
    for _, frame in ipairs(t.env.frames) do
        if frame ~= t.eventFrame and frame.events and frame.events.UNIT_AURA
            and frame.events.UPDATE_SHAPESHIFT_FORM then balanceFrame = frame end
    end
    Check(balanceFrame ~= nil, "the Balance runtime did not bind its events")
    if balanceFrame then
        local function Aura()
            balanceFrame.scripts.OnEvent(balanceFrame, "UNIT_AURA", "player", { isFullUpdate = true })
            t.env:RunTimers()
        end
        solarUntil = GetTime() + 15
        Aura()
        Check(not SameColor(bar.color, BASE), "a Solar Eclipse did not colour the Player Power bar")
        -- The eclipse runs out: its aura is gone once its time has passed.
        t.env:AdvanceTime(16)
        solarUntil = nil
        Aura()
        Check(SameColor(bar.color, BASE), "the Player Power bar kept the eclipse colour after the eclipse ended")
        Check(bar._msufR == BASE[1] and bar._msufB == BASE[3], "the Power element's colour stamp no longer matches the bar")
    end
end

-- Native aura modes (Fury Whirlwind) hide the count text directly. A vehicle
-- with combo points hands the bar to the segmented painter, whose shown stamp
-- must not still say "shown" from the previous vehicle.
do
    local t = World.Start(repo, "Mainline", "WARRIOR", 2, PT.RAGE, { classPowerShowText = true })
    local CP = t.CP
    Check(CP.visible and CP.powerType == "WHIRLWIND", "Fury did not route Whirlwind")
    local function Vehicle(inVehicle)
        t.S.vehicle = inVehicle
        World.Dispatcher(t, inVehicle and "UNIT_ENTERED_VEHICLE" or "UNIT_EXITED_VEHICLE", "player")()
        t.env:RunTimers()
    end
    Vehicle(true)
    Check(CP.powerType == PT.COMBO and CP.text and CP.text.shown == true, "vehicle combo points show no count")
    Vehicle(false)
    Check(CP.powerType == "WHIRLWIND" and CP.text.shown == false, "Whirlwind did not hide the count")
    Vehicle(true)
    Check(CP.powerType == PT.COMBO and CP.text.shown == true,
        "the vehicle count stayed hidden after Whirlwind hid it")
end

-- Structural refreshes are throttled to one per 150 ms. A second form change
-- inside the window must still be shown: a trailing refresh follows.
do
    local t = World.Start(repo, "Mainline", "DRUID", 2, PT.ENERGY)
    local CP = t.CP
    Check(CP.visible and CP.powerType == PT.COMBO, "Feral in Cat form did not route combo points")
    t.env:AdvanceTime(1)
    t.S.primary = PT.RAGE
    World.Dispatcher(t, "UNIT_DISPLAYPOWER", "player", "RAGE")()
    Check(not CP.visible, "Bear form kept the combo points")
    t.env:AdvanceTime(0.05)
    t.S.primary = PT.ENERGY
    World.Dispatcher(t, "UNIT_DISPLAYPOWER", "player", "ENERGY")()
    t.env:AdvanceTime(0.2)
    t.env:RunTimers()
    Check(CP.visible and CP.powerType == PT.COMBO,
        "a form change inside the refresh throttle window was dropped (Cat form shows no combo points)")
end

if #failures > 0 then
    error("classpower_paint_stamps_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_paint_stamps_smoke: ok (Ironfur, Stagger tier, eclipse colour, native aura text, throttle)")
