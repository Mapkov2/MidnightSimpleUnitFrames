-- classpower_hotpath_budget_smoke.lua <repoRoot> [print]
--
-- Deterministic cost budgets for the ClassPower controller hot paths, never
-- wall-clock time:
--   * Lua VM instructions per event (count hook, every instruction);
--   * bytes allocated per event, with the collector stopped.
-- The REAL ClassPower stack of each client TOC runs against the shared test
-- stubs (the same harness as classpower_target_combo_trace_smoke.lua). Covered:
--   * Midnight Rogue: combo point UNIT_POWER_UPDATE and the Energy
--     UNIT_POWER_FREQUENT tick the controller must drop;
--   * Mists Rogue: target-owned combo points on UNIT_POWER_FREQUENT;
--   * Midnight Death Knight: RUNE_POWER_UPDATE;
--   * Midnight Evoker: Essence on UNIT_POWER_FREQUENT;
--   * Midnight Enhancement Shaman: a Maelstrom Weapon stack change on UNIT_AURA,
--     and aura churn without one;
--   * Midnight Brewmaster Monk: one central Stagger tick.
-- Budgets were frozen on 2026-10-02 from the cost measured before the
-- CP_Controller split, plus 2 % (AGENTS_QUALITY.md §1.2). A restructure may
-- only stay inside them. "print" reports the measured values.
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local printOnly = arg[2] == "print"
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

-- instructions, bytes per operation (8 bytes: below any per-operation table).
-- A Maelstrom Weapon stack change allocated 252 bytes before the split too:
-- the per-call refresh closure (CPAuras.RefreshActive), the deferred
-- update's timer entry and the segmented repaint.
local BUDGETS = {
    ["Mainline ROGUE combo UNIT_POWER_UPDATE"] = { 790, 8 },
    ["Mainline ROGUE energy UNIT_POWER_FREQUENT"] = { 64, 8 },
    ["Mists ROGUE target combo UNIT_POWER_FREQUENT"] = { 815, 8 },
    ["Mainline DEATHKNIGHT RUNE_POWER_UPDATE"] = { 1026, 8 },
    ["Mainline EVOKER essence UNIT_POWER_FREQUENT"] = { 751, 8 },
    ["Mainline SHAMAN maelstrom UNIT_AURA"] = { 2047, 258 },
    ["Mainline SHAMAN unchanged UNIT_AURA"] = { 573, 62 },
    ["Mainline MONK stagger tick"] = { 232, 8 },
}

local WARMUP, INSTRUCTION_REPS, ALLOCATION_REPS = 40, 200, 2000
local measured = {}

local function Measure(label, operation)
    assert(BUDGETS[label], "no budget for " .. label)
    for _ = 1, WARMUP do operation() end
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, INSTRUCTION_REPS do operation() end
    debug.sethook()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, ALLOCATION_REPS do operation() end
    local bytes = (collectgarbage("count") - before) * 1024
    collectgarbage("restart")
    measured[#measured + 1] = {
        label = label, instructions = ticks / INSTRUCTION_REPS, bytes = bytes / ALLOCATION_REPS,
    }
end

--------------------------------------------------------------------------
-- Harness (classpower_target_combo_trace_smoke.lua without the recorder)
--------------------------------------------------------------------------

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "__MSUF_CP_Balance_Loaded", "MSUF_CP_CONST",
    "MSUF_CP_CORE_BUILDERS", "MSUF_CP_MODE_BUILDERS", "MSUF_CP_FEATURE_BUILDERS",
    "MSUF_CP_TARGET_COMBO", "MSUF_CP_CoreUnitFrame", "MSUF_ClassPowerContainer",
    "MSUF_player", "MSUF_ScheduleOnce", "MSUF_SetRoundLayoutToNearestPixel",
    "MSUF_BAL_RefreshRuntime", "MSUF_BAL_InvalidateColors", "MSUF_EleMaelstromActive",
    "MSUF_ShadowManaActive", "MSUF_PlayerPowerManaOverrideActive", "MSUF_AugEvokerActive",
    "MSUF_ClassPower_Refresh", "MSUF_ClassPower_Apply", "MSUF_ClassPower_ApplyFonts",
    "MSUF_RefreshPlayerPowerBar",
}

local PT_MANA, PT_ENERGY, PT_COMBO, PT_ESSENCE = 0, 3, 4, 19

--- Every ClassPower entry of a client's TOC, in TOC order.
local function ClassPowerLoadOrder(tocName)
    local path = repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. tocName .. ".toc"
    local file = assert(io.open(path, "rb"), "missing TOC: " .. path)
    local raw = file:read("*a")
    file:close()
    local order = { "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua" }
    for line in raw:gmatch("[^\r\n]+") do
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:find("ClassPower", 1, true) then
            order[#order + 1] = entry:gsub("\\", "/")
        end
    end
    return order
end

local function Upvalue(fn, wanted)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

local function Start(toc, class, spec, primary)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 1000 })
    env:InstallGlobals({ secretValue = true, time = true })
    for index = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[index]] = nil end
    local classic = toc ~= "Mainline"
    local ns = {
        Client = {
            Family = classic and "Classic" or "Mainline",
            Flavor = toc,
            IsClassic = classic,
            IsRetail = not classic,
            IsForever = false,
            SupportsEvent = function(event)
                if not classic then return true end
                return event ~= "UNIT_POWER_POINT_CHARGE" and event ~= "WAR_MODE_STATUS_UPDATE"
            end,
        },
    }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    _G.MSUF_NS = ns

    local S = { class = class, spec = spec, primary = primary, combo = 3, auraStacks = 2 }
    function UnitClass() return S.class, S.class end
    function UnitPowerType() return S.primary end
    function UnitPower(_, powerType)
        if powerType == PT_COMBO then return S.combo end
        if powerType == S.primary then return 50 end
        return 3
    end
    function UnitPowerMax(_, powerType)
        if powerType == S.primary then return 100 end
        return 5
    end
    function UnitPartialPower() return 0 end
    function UnitPowerDisplayMod() return 1 end
    function GetComboPoints() return S.combo end
    function UnitHasVehicleUI() return false end
    function PlayerVehicleHasComboPoints() return false end
    function GetShapeshiftFormID() return nil end
    function GetSpecialization() return S.spec end
    function GetRuneCooldown(runeID)
        if runeID <= 3 then return 0, 10, true end
        return 995, 10, false
    end
    function GetRuneType() return 1 end
    function GetUnitChargedPowerPoints() return nil end
    function UnitStagger() return S.stagger or 400 end
    function UnitHealth() return 500 end
    function UnitHealthMax() return 1000 end
    function UnitAffectingCombat() return true end
    function InCombatLockdown() return false end
    function GetPowerRegenForPowerType() return 0, 0 end
    function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    canaccesstable = function() return true end
    MSUF_UF_NormalizeClassPowerShape = function(shape)
        shape = shape and tostring(shape):upper() or "BAR"
        if shape == "" then shape = "BAR" end
        return shape
    end
    MSUF_UF_NormalizeShapeAlign = function(value) return value or "CENTER" end
    MSUF_ApplyResolvedFont = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true, path, "requested"
    end
    MSUF_SetFontChecked = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true
    end
    MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    C_SpellBook = {
        IsSpellKnown = function() return true end,
        IsSpellKnownOrInSpellBook = function() return true end,
    }
    C_Spell = {
        GetSpellMaxCumulativeAuraApplications = function() return 10 end,
        GetSpellCastCount = function() return 4 end,
        GetSpellInfo = function() return nil end,
    }
    -- The client hands out a new aura table on every query. Two tables per
    -- stack count (S.auraVariant), built on first use, model that without a
    -- per-query allocation in the stub.
    local auraByKey = {}
    C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            local key = S.auraStacks * 2 + (S.auraVariant or 0)
            local aura = auraByKey[key]
            if not aura then
                aura = { auraInstanceID = 11, applications = S.auraStacks, expirationTime = 0, duration = 0 }
                auraByKey[key] = aura
            end
            aura.spellId = spellID
            return aura
        end,
        GetAuraDataBySpellName = function() return nil end,
    }
    MSUF_DB = {
        general = {},
        bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false },
    }
    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    local order = ClassPowerLoadOrder(toc)
    for index = 1, #order do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. order[index]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register: " .. toc .. " " .. class)
    module.Enable()
    env:RunTimers()
    local CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    local eventFrame = Upvalue(assert(CP.SyncControllerEvents), "eventFrame")
    return {
        env = env, S = S, CP = CP, eventFrame = eventFrame,
        onEvent = assert(eventFrame.scripts.OnEvent, "controller OnEvent script missing"),
    }
end

--- Number of widget setter calls (Set*) fn makes: what a repaint costs the client.
local function CountSetters(t, fn)
    local count = 0
    local methods, saved = t.env.Methods, {}
    for name, method in pairs(methods) do
        if name:find("^Set") then
            saved[name] = method
            methods[name] = function(...)
                count = count + 1
                return method(...)
            end
        end
    end
    fn()
    for name, method in pairs(saved) do methods[name] = method end
    return count
end

--- Fires one event straight into the controller's OnEvent script, as the client
--- would for a bound event.
local function Dispatcher(t, event, a1, a2, a3)
    local onEvent, frame = t.onEvent, t.eventFrame
    return function() onEvent(frame, event, a1, a2, a3) end
end

--------------------------------------------------------------------------
-- Scenarios
--------------------------------------------------------------------------

do
    local t = Start("Mainline", "ROGUE", 1, PT_ENERGY)
    assert(t.CP.visible and t.CP.powerType == PT_COMBO, "Midnight Rogue did not route combo points")
    local combo = 0
    local update = Dispatcher(t, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
    Measure("Mainline ROGUE combo UNIT_POWER_UPDATE", function()
        combo = combo % 5 + 1
        t.S.combo = combo
        update()
    end)
    Measure("Mainline ROGUE energy UNIT_POWER_FREQUENT", Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "ENERGY"))
end

do
    local t = Start("Mists", "ROGUE", 1, PT_ENERGY)
    assert(t.CP.visible and t.CP.powerType == PT_COMBO, "Mists Rogue did not route combo points")
    local combo = 0
    local update = Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    Measure("Mists ROGUE target combo UNIT_POWER_FREQUENT", function()
        combo = combo % 5 + 1
        t.S.combo = combo
        update()
    end)
end

do
    local t = Start("Mainline", "DEATHKNIGHT", 1, 6)
    assert(t.CP.visible, "Midnight Death Knight did not route runes")
    local rune = 0
    local onEvent, frame = t.onEvent, t.eventFrame
    Measure("Mainline DEATHKNIGHT RUNE_POWER_UPDATE", function()
        rune = rune % 6 + 1
        onEvent(frame, "RUNE_POWER_UPDATE", rune, false)
    end)
end

do
    local t = Start("Mainline", "EVOKER", 1, PT_MANA)
    assert(t.CP.visible and t.CP.powerType == PT_ESSENCE, "Midnight Evoker did not route Essence")
    Measure("Mainline EVOKER essence UNIT_POWER_FREQUENT", Dispatcher(t, "UNIT_POWER_FREQUENT", "player", "ESSENCE"))
end

do
    local t = Start("Mainline", "SHAMAN", 2, PT_MANA)
    assert(t.CP.visible and t.CP.isAuraPower, "Midnight Enhancement did not route Maelstrom Weapon")
    local stacks = 0
    local update = Dispatcher(t, "UNIT_AURA", "player", { isFullUpdate = true })
    Measure("Mainline SHAMAN maelstrom UNIT_AURA", function()
        stacks = stacks % 10 + 1
        t.S.auraStacks = stacks
        update()
        t.env:RunTimers()
    end)
    -- Aura churn without a stack change: the cache compares the new aura's
    -- fields and repaints nothing.
    local variant = 0
    Measure("Mainline SHAMAN unchanged UNIT_AURA", function()
        variant = 1 - variant
        t.S.auraVariant = variant
        update()
        t.env:RunTimers()
    end)
    local function Fire() update() t.env:RunTimers() end
    t.S.auraVariant = 1 - variant
    local unchanged = CountSetters(t, Fire)
    t.S.auraStacks = stacks % 10 + 1
    local changed = CountSetters(t, Fire)
    assert(unchanged == 0 and changed > 0, "Maelstrom Weapon repaint does not follow the stack count")
end

do
    local t = Start("Mainline", "MONK", 1, PT_ENERGY)
    assert(t.CP.visible, "Midnight Brewmaster did not route Stagger")
    local tickFrame
    for _, frame in ipairs(t.env.frames or {}) do
        if frame.scripts and frame.scripts.OnUpdate and frame ~= t.eventFrame then tickFrame = frame end
    end
    assert(tickFrame, "Brewmaster has no running central tick")
    local onUpdate = tickFrame.scripts.OnUpdate
    Measure("Mainline MONK stagger tick", function() onUpdate(tickFrame, 0.05) end)
    -- The central tick runs its mode at 30 Hz at most.
    t.S.stagger = 650
    local early = CountSetters(t, function() onUpdate(tickFrame, 0.02) end)
    local due = CountSetters(t, function() onUpdate(tickFrame, 0.02) end)
    assert(early == 0 and due > 0, "the central tick does not throttle Stagger to 30 Hz")
    -- Leaving Brewmaster stops the central tick: no OnUpdate is left running.
    t.S.spec = 3
    t.CP.RefreshPublic()
    t.env:RunTimers()
    assert(tickFrame.scripts.OnUpdate == nil and not tickFrame.shown, "the central tick outlived Stagger")
end

--------------------------------------------------------------------------
-- Verdict
--------------------------------------------------------------------------

local failures = {}
for _, row in ipairs(measured) do
    local budget = BUDGETS[row.label]
    local line = ("%-48s %8.1f instructions (budget %d)  %7.1f bytes (budget %d)"):format(
        row.label, row.instructions, budget[1], row.bytes, budget[2])
    if printOnly then
        print(line)
    elseif row.instructions > budget[1] or row.bytes > budget[2] then
        failures[#failures + 1] = line
    end
end
if printOnly then return end
if #failures > 0 then
    error("classpower_hotpath_budget_smoke: over budget:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("classpower_hotpath_budget_smoke: ok (%d hot paths within budget)"):format(#measured))
