-- Classic ClassPower controller contracts.
-- Loads the real Classic ClassPower stack once per case (the same files and
-- order as the client TOC), runs module.Enable against a stub player frame and
-- drives events through the controller's own OnEvent script.
--
-- 1. "Displayed resource: Mana" (MSUF_DB.player.playerPowerSource = "MANA").
--    The controller owns the public flag MSUF_PlayerPowerManaOverrideActive.
--    The Power element, the power text and AltMana read that flag, so it has to
--    be published before the Player power bar is re-applied, and that re-apply
--    has to run once per change instead of on every refresh.
-- 2. PLAYER_DEAD / PLAYER_ALIVE repaint class power through the updater of the
--    active render mode. The aura renderer only knows aura-backed resources and
--    paints every other resource empty.
-- Usage:
--   lua tools/tests/classic_classpower_controller_smoke.lua <repoRoot> <Vanilla|TBC|Mists>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
assert(flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists", "unknown flavor: " .. tostring(flavor))

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

-- Ids the Classic constants fall back to when Enum is absent (checked after load).
local PT = { Mana = 0, Energy = 3, ComboPoints = 4, Runes = 5, DemonicFury = 15, Balance = 26 }
local ARCANE_CHARGE = 36032
local MANA_FLAG = "MSUF_PlayerPowerManaOverrideActive"

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS", "MSUF_CP_MODE_BUILDERS",
    "MSUF_CP_FEATURE_BUILDERS", "MSUF_ClassPowerContainer", "MSUF_AltManaContainer",
    "MSUF_ClassPowerPlayerHealthBar", "MSUF_player", "MSUF_ScheduleOnce",
    "MSUF_SetRoundLayoutToNearestPixel", "MSUF_RefreshPlayerPowerBar",
    MANA_FLAG, "MSUF_EleMaelstromActive", "MSUF_ShadowManaActive", "MSUF_AugEvokerActive",
}

-- The secret-value library plus every ClassPower file the client TOC loads, in
-- TOC order, so the cases run the stack this flavor ships.
local LOAD_ORDER = {}
do
    local manifest = assert(loadfile(repo .. "/tools/tests/client_manifest.lua"))()
    local controllers = 0
    for _, path in ipairs(manifest.Paths(repo, flavor)) do
        if path:find("/ClassPower", 1, true) or path:find("/MSUF_UF_Secrets.lua", 1, true) then
            LOAD_ORDER[#LOAD_ORDER + 1] = path
            if path:find("/MSUF_CP_Controller.lua", 1, true) then controllers = controllers + 1 end
        end
    end
    assert(controllers == 1, flavor .. " TOC loads " .. controllers .. " ClassPower controllers")
end

local function Upvalue(fn, wanted)
    for i = 1, 255 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

local function Near(value, expected)
    return type(value) == "number" and math.abs(value - expected) < 1e-6
end

--------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------

local function Start(spec)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 100 })
    env:InstallGlobals({ secretValue = true, time = true })
    for i = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[i]] = nil end

    local S = {
        class = spec.class,
        spec = spec.spec,
        primary = spec.primary or PT.Mana,
        power = spec.power or {},
        max = spec.max or {},
        combo = spec.combo or 0,
        inVehicle = false,
        hasMana = spec.hasMana == true,
        arcane = spec.arcane or 0,
        readyRunes = 3,
    }
    local t = { env = env, S = S, powerBarRefreshes = 0 }

    local ns = { Client = { IsClassic = true, SupportsEvent = function(event)
        return event ~= "UNIT_POWER_POINT_CHARGE" and event ~= "WAR_MODE_STATUS_UPDATE"
    end } }
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value end
    _G.MSUF_NS = ns

    -- UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua owns this entry
    -- point in game: it re-applies the Player power bar, which reads the public
    -- flag while it runs. Record what that re-apply would have seen.
    _G.MSUF_RefreshPlayerPowerBar = function()
        t.powerBarRefreshes = t.powerBarRefreshes + 1
        t.flagSeenByPowerBar = _G[MANA_FLAG]
    end

    function UnitClass() return S.class, S.class end
    function UnitPowerType() return S.primary end
    function UnitPower(_, powerType) return S.power[powerType] or 0 end
    function UnitPowerMax(_, powerType) return S.max[powerType] or 0 end
    function UnitPowerDisplayMod() return 1 end
    function UnitHasPowerType(_, powerType) return powerType == PT.Mana and S.hasMana end
    function GetComboPoints() return S.combo end
    function UnitHasVehicleUI() return S.inVehicle end
    function PlayerVehicleHasComboPoints() return false end
    function GetShapeshiftFormID() return spec.form end
    function GetSpecialization() return S.spec end
    function GetRuneCooldown(runeID)
        if runeID <= S.readyRunes then return 0, 10, true end
        return 95, 10, false
    end
    function GetRuneType() return 1 end
    function UnitAffectingCombat() return false end
    function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    canaccesstable = function() return true end
    MSUF_UF_NormalizeClassPowerShape = function(shape)
        shape = shape and tostring(shape):upper() or "BAR"
        if shape == "" then shape = "BAR" end
        return shape
    end
    MSUF_UF_NormalizeShapeAlign = function(value) return value or "CENTER" end
    MSUF_UF_NormalizePlayerHPShape = MSUF_UF_NormalizeClassPowerShape
    function UnitHealth() return 900 end
    function UnitHealthMax() return 1000 end
    MSUF_ApplyResolvedFont = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true, path, "requested"
    end
    MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    C_SpellBook = { IsSpellKnown = function() return false end }
    C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            if spellID == ARCANE_CHARGE and S.arcane > 0 then
                return { spellId = ARCANE_CHARGE, auraInstanceID = 7, applications = S.arcane, expirationTime = 0 }
            end
            return nil
        end,
    }
    MSUF_DB = {
        general = spec.general or {},
        player = { playerPowerSource = spec.source },
        bars = {
            showClassPower = spec.showClassPower ~= false,
            showAltMana = spec.showAltMana == true,
            playerHPBarEnabled = spec.playerHP == true,
        },
    }

    local module
    function MSUF_RegisterModule(name, callbacks)
        assert(name == "ClassPower", "unexpected module " .. tostring(name))
        module = callbacks
    end
    for i = 1, #LOAD_ORDER do
        assert(loadfile(LOAD_ORDER[i]))("MSUF", ns)
    end
    assert(module, "controller did not register")
    local K = assert(MSUF_CP_CONST)
    for name, id in pairs(PT) do assert(K.PT[name] == id, "power type id drifted: " .. name) end
    t.MODE = K.CPK.MODE

    t.module = module
    t.FullRefresh = Upvalue(module.Enable, "FullRefresh")
    t.CP = Upvalue(t.FullRefresh, "CP")
    -- The texture-hook wrapper replaces FullRefresh; the stages live on the original.
    local refresh = t.CP._origFullRefresh or t.FullRefresh
    t.AM = Upvalue(Upvalue(refresh, "Refresh").ApplyAltMana, "AM")
    t.eventFrame = Upvalue(Upvalue(refresh, "CP_RefreshEventBindings"), "eventFrame")
    t.onEvent = assert(t.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    assert(_G[MANA_FLAG] == nil, "the flag must start unpublished, or the case below proves nothing")
    if module.IsEnabled() then module.Enable() end
    return t
end

local function Registered(t, event)
    return t.eventFrame.events[event] == true
end

-- Only registered events are delivered by the client, so refuse anything else.
local function Fire(t, event, ...)
    assert(Registered(t, event), event .. " is not registered, so the client would never deliver it")
    t.onEvent(t.eventFrame, event, ...)
end

local function ExpectBars(t, expected, label)
    local CP = t.CP
    assert(CP.visible == true, label .. ": class power is not visible")
    assert(CP.currentMax == #expected, label .. ": max " .. tostring(CP.currentMax) .. ", expected " .. #expected)
    for i = 1, #expected do
        local bar = CP.bars[i]
        local value = bar and bar.value
        assert(Near(value, expected[i]), string.format("%s: bar %d is %s, expected %s",
            label, i, tostring(value), tostring(expected[i])))
    end
end

-- The published flag and the number of Player power bar re-applies so far.
local function ExpectMana(t, active, refreshes, label)
    assert(_G[MANA_FLAG] == active, string.format("%s: %s is %s, expected %s",
        label, MANA_FLAG, tostring(_G[MANA_FLAG]), tostring(active)))
    assert(t.powerBarRefreshes == refreshes, string.format("%s: the Player power bar was re-applied %d time(s), expected %d",
        label, t.powerBarRefreshes, refreshes))
end

--------------------------------------------------------------------------
-- Cases
--------------------------------------------------------------------------

local CASES = {}
local MISTS = { Mists = true }

local function Case(name, flavors, run)
    CASES[#CASES + 1] = { name = name, flavors = flavors, run = run }
end

local CAT_DRUID = { class = "DRUID", spec = 2, primary = PT.Energy, combo = 2, hasMana = true,
    power = { [PT.Mana] = 600 }, max = { [PT.ComboPoints] = 5, [PT.Mana] = 1000 } }

local function With(base, extra)
    local out = {}
    for key, value in pairs(base) do out[key] = value end
    for key, value in pairs(extra) do out[key] = value end
    return out
end

Case("mana source publishes before one re-apply", nil, function()
    local t = Start(With(CAT_DRUID, { source = "MANA" }))
    ExpectMana(t, true, 1, "cat druid with the Mana source")
    assert(t.flagSeenByPowerBar == true,
        "the Player power bar was re-applied before the flag was published, saw " .. tostring(t.flagSeenByPowerBar))
    ExpectBars(t, { 1, 1, 0, 0, 0 }, "class power next to the Mana source")
    -- An unchanged refresh is not a change: no second re-apply.
    t.FullRefresh()
    _G.MSUF_ClassPower_Refresh()
    ExpectMana(t, true, 1, "unchanged refreshes")
    return t
end)

Case("mana source follows the setting", nil, function()
    local t = Start(CAT_DRUID)
    ExpectMana(t, false, 0, "Auto source")
    MSUF_DB.player.playerPowerSource = "MANA"
    t.FullRefresh()
    ExpectMana(t, true, 1, "switched to Mana")
    assert(t.flagSeenByPowerBar == true, "switching to Mana re-applied the bar before the flag was published")
    MSUF_DB.player.playerPowerSource = "AUTO"
    t.FullRefresh()
    ExpectMana(t, false, 2, "switched back to Auto")
    assert(t.flagSeenByPowerBar == false, "switching back re-applied the bar before the flag was cleared")
    t.FullRefresh()
    ExpectMana(t, false, 2, "unchanged Auto refresh")
    return t
end)

Case("mana source without a Mana pool stays off", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 3, max = { [PT.ComboPoints] = 5 },
        hasMana = false, source = "MANA" })
    ExpectMana(t, false, 0, "rogue with the Mana source")
    ExpectBars(t, { 1, 1, 1, 0, 0 }, "rogue with the Mana source")
    return t
end)

Case("mana source alone keeps the module alive", nil, function()
    local t = Start(With(CAT_DRUID, { source = "MANA", showClassPower = false }))
    assert(t.module.IsEnabled() == true, "the Mana source must keep the ClassPower module enabled")
    ExpectMana(t, true, 1, "Mana source without class power")
    assert(t.CP.visible == false, "class power was switched off")
    return t
end)

Case("AltMana yields to the Player bar", nil, function()
    local t = Start(With(CAT_DRUID, { showAltMana = true }))
    assert(t.AM.visible == true, "a cat druid on the Auto source must get the AltMana bar")
    MSUF_DB.player.playerPowerSource = "MANA"
    t.FullRefresh()
    ExpectMana(t, true, 1, "AltMana with the Mana source")
    assert(t.AM.visible == false, "the Player bar already shows Mana; AltMana must not duplicate it")
    MSUF_DB.player.playerPowerSource = nil
    t.FullRefresh()
    assert(t.AM.visible == true, "AltMana must return with the Auto source")
    return t
end)

Case("teardown clears the flag", nil, function()
    local t = Start(With(CAT_DRUID, { source = "MANA" }))
    ExpectMana(t, true, 1, "before teardown")
    t.module.Disable()
    ExpectMana(t, false, 2, "after teardown")
    assert(t.flagSeenByPowerBar == false, "teardown re-applied the bar before the flag was cleared")
    t.tornDown = true
    return t
end)

Case("vehicle power masks the Mana source", MISTS, function()
    local t = Start(With(CAT_DRUID, { source = "MANA" }))
    ExpectMana(t, true, 1, "before the vehicle")
    t.S.inVehicle = true
    Fire(t, "UNIT_ENTERED_VEHICLE", "player")
    t.env:RunTimers()
    ExpectMana(t, false, 2, "inside the vehicle")
    assert(Registered(t, "UNIT_EXITED_VEHICLE"), "the vehicle exit must stay bound while the Mana source waits")
    t.S.inVehicle = false
    Fire(t, "UNIT_EXITED_VEHICLE", "player")
    t.env:RunTimers()
    ExpectMana(t, true, 3, "after the vehicle")
    assert(t.flagSeenByPowerBar == true, "leaving the vehicle re-applied the bar before the flag was published")
    return t
end)

-- perfLiteClassPowerEvents = false binds PLAYER_DEAD and PLAYER_ALIVE for every
-- visible resource; the lite profile binds them with the Player HP bar.
local NON_LITE = { perfLiteClassPowerEvents = false }

Case("death and resurrect keep combo points", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 3, max = { [PT.ComboPoints] = 5 },
        general = NON_LITE })
    assert(t.CP.renderMode == t.MODE.SEGMENTED and t.CP.powerType == PT.ComboPoints, "rogue route")
    ExpectBars(t, { 1, 1, 1, 0, 0 }, "rogue")
    Fire(t, "PLAYER_DEAD")
    ExpectBars(t, { 1, 1, 1, 0, 0 }, "rogue after PLAYER_DEAD")
    -- No power event in between: the repaint itself has to read the new value.
    t.S.combo = 2
    Fire(t, "PLAYER_ALIVE")
    ExpectBars(t, { 1, 1, 0, 0, 0 }, "rogue after PLAYER_ALIVE")
    return t
end)

-- The default lite profile: the Player HP bar is what binds the two events.
Case("death and resurrect with the Player HP bar", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 4, max = { [PT.ComboPoints] = 5 },
        playerHP = true })
    assert(t.CP._liteBindingsActive == true, "the default profile must use the lite bindings")
    ExpectBars(t, { 1, 1, 1, 1, 0 }, "rogue with the Player HP bar")
    Fire(t, "PLAYER_DEAD")
    ExpectBars(t, { 1, 1, 1, 1, 0 }, "rogue with the Player HP bar after PLAYER_DEAD")
    return t
end)

Case("death and resurrect keep runes", MISTS, function()
    local t = Start({ class = "DEATHKNIGHT", spec = 1, primary = 6, general = NON_LITE })
    assert(t.CP.renderMode == t.MODE.RUNE_CD and t.CP.powerType == PT.Runes, "DK route")
    local function Count()
        local ready, cooling = 0, 0
        for i = 1, 6 do
            local bar = t.CP.bars[i]
            if Near(bar.value, 1) and bar.maximum == 1 then ready = ready + 1 end
            if Near(bar.value, 5) and bar.maximum == 10 then cooling = cooling + 1 end
        end
        return ready, cooling
    end
    local ready, cooling = Count()
    assert(ready == 3 and cooling == 3, "rune values: ready " .. ready .. ", cooling " .. cooling)
    Fire(t, "PLAYER_DEAD")
    ready, cooling = Count()
    assert(ready == 3 and cooling == 3, "PLAYER_DEAD repainted the runes: ready " .. ready .. ", cooling " .. cooling)
    t.S.readyRunes = 6
    Fire(t, "PLAYER_ALIVE")
    ready, cooling = Count()
    assert(ready == 6 and cooling == 0, "PLAYER_ALIVE must repaint the runes: ready " .. ready .. ", cooling " .. cooling)
    return t
end)

Case("death and resurrect keep the eclipse range", MISTS, function()
    local t = Start({ class = "DRUID", spec = 1, primary = PT.Mana, hasMana = true, general = NON_LITE,
        power = { [PT.Balance] = -40 }, max = { [PT.Balance] = 100 } })
    assert(t.CP.renderMode == t.MODE.SIGNED_CONTINUOUS, "balance route")
    ExpectBars(t, { -40 }, "balance")
    Fire(t, "PLAYER_DEAD")
    ExpectBars(t, { -40 }, "balance after PLAYER_DEAD")
    local bar = t.CP.bars[1]
    assert(bar.minimum == -100 and bar.maximum == 100,
        "PLAYER_DEAD broke the eclipse range: " .. tostring(bar.minimum) .. ".." .. tostring(bar.maximum))
    return t
end)

Case("death and resurrect keep demonic fury", MISTS, function()
    local t = Start({ class = "WARLOCK", spec = 2, primary = PT.Mana, hasMana = true, general = NON_LITE,
        power = { [PT.DemonicFury] = 200 }, max = { [PT.DemonicFury] = 1000 } })
    assert(t.CP.renderMode == t.MODE.CONTINUOUS, "demonology route")
    Fire(t, "PLAYER_ALIVE")
    ExpectBars(t, { 200 }, "demonology after PLAYER_ALIVE")
    assert(t.CP.bars[1].maximum == 1000, "PLAYER_ALIVE broke the fury range: " .. tostring(t.CP.bars[1].maximum))
    return t
end)

-- The aura renderer stays the updater of an aura-backed resource.
Case("death and resurrect keep an aura resource", MISTS, function()
    local t = Start({ class = "MAGE", spec = 1, primary = PT.Mana, hasMana = true, arcane = 2, general = NON_LITE })
    assert(t.CP.renderMode == t.MODE.AURA_SEGMENTED, "arcane route")
    ExpectBars(t, { 1, 1, 0, 0 }, "arcane with 2 charges")
    Fire(t, "PLAYER_DEAD")
    ExpectBars(t, { 1, 1, 0, 0 }, "arcane after PLAYER_DEAD")
    return t
end)

--------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------

local passed, failures = 0, {}
for _, case in ipairs(CASES) do
    if case.flavors == nil or case.flavors[flavor] then
        local ok, err = pcall(function()
            local t = case.run()
            if not t.tornDown then t.module.Disable() end
            t.module.Shutdown()
            assert(_G[MANA_FLAG] == false, "the flag outlived the module: " .. tostring(_G[MANA_FLAG]))
        end)
        if ok then
            passed = passed + 1
        else
            failures[#failures + 1] = case.name .. ": " .. tostring(err)
        end
    end
end

if #failures > 0 then
    for i = 1, #failures do
        io.stderr:write("FAIL " .. flavor .. " " .. failures[i] .. "\n")
    end
    os.exit(1)
end
print(string.format("PASS %s ClassPower controller: Mana source flag and death/resurrect repaint, %d cases", flavor, passed))
