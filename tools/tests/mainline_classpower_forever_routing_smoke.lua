-- Mainline ClassPower routing on WoW Forever.
-- Forever reads the _Mainline.toc, so it runs the Retail ClassPower stack, but
-- Blizzard loads none of the Retail class resource bars for the camelot game
-- type and keeps only the target-owned ComboFrame. With MSUF.Client.IsForever
-- the controller must route like the Classic Era provider: target-owned combo
-- points (GetComboPoints("player", "target"), refreshed on target changes) for
-- Rogues and Cat Form Druids, and nothing for any other class or Retail spec
-- index. Without the fact (no Client, or IsForever false) Retail routing and
-- event bindings stay exactly as they were.
-- Usage (cwd = repo root):
--   lua tools/tests/mainline_classpower_forever_routing_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required")

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

local PT = {
    Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4, SoulShards = 7,
    HolyPower = 9, ArcaneCharges = 16,
}
local MODE_NONE, MODE_SEGMENTED = 0, 1

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "__MSUF_CP_Balance_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS",
    "MSUF_CP_MODE_BUILDERS", "MSUF_CP_FEATURE_BUILDERS", "MSUF_CP_CoreUnitFrame", "MSUF_ClassPowerContainer",
    "MSUF_player", "MSUF_BAL_RefreshRuntime", "MSUF_BAL_InvalidateColors", "MSUF_EleMaelstromActive",
    "MSUF_ShadowManaActive", "MSUF_PlayerPowerManaOverrideActive", "MSUF_AugEvokerActive",
}

-- Same order as the ClassPower block of MidnightSimpleUnitFrames_Mainline.toc.
local LOAD_ORDER = {
    "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    "ClassPower/MSUF_CP_Constants.lua",
    "ClassPower/MSUF_CP_Modes.lua",
    "ClassPower/MSUF_CP_Core.lua",
    "ClassPower/MSUF_CP_AltMana.lua",
    "ClassPower/MSUF_CP_PlayerHP.lua",
    "ClassPower/MSUF_CP_BalanceDruid.lua",
    "ClassPower/MSUF_CP_Ironfur.lua",
    "ClassPower/MSUF_CP_EbonMight.lua",
    "ClassPower/MSUF_CP_NativeAuras.lua",
    "ClassPower/MSUF_CP_Controller_Config.lua",
    "ClassPower/MSUF_CP_Controller_Colors.lua",
    "ClassPower/MSUF_CP_Controller_Surface.lua",
    "ClassPower/MSUF_CP_Controller.lua",
}

local function Upvalue(fn, wanted)
    for i = 1, 255 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

-- spec fields: class, spec, primary, client ("forever" | "standard" | nil),
-- comboTargetEvent (false rejects COMBO_TARGET_CHANGED), bars (extra DB keys),
-- general (extra DB keys).
local function Start(spec)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 100 })
    env:InstallGlobals({ secretValue = true, time = true })
    for i = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[i]] = nil end

    local S = { target = 0, owned = 5, primary = spec.primary or PT.Mana, form = nil, comboCalls = 0 }
    local t = { env = env, S = S }

    env.Methods.RegisterUnitEvent = function(self, event)
        self.events[event] = true
    end

    local ns = {}
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    if spec.client == "forever" or spec.client == "standard" then
        ns.Client = {
            IsForever = spec.client == "forever",
            SupportsEvent = function(event)
                if event == "COMBO_TARGET_CHANGED" then return spec.comboTargetEvent ~= false end
                return true
            end,
        }
    end
    _G.MSUF_NS = ns
    t.ns = ns

    local className = spec.class
    function UnitClass() return className, className end
    function UnitPowerType() return S.primary end
    -- The player-owned (Retail) value differs from the target-owned one, so a
    -- route that reads the wrong source shows the wrong pip count.
    function UnitPower(_, powerType)
        if powerType == PT.ComboPoints then return S.owned end
        if powerType == S.primary then return 50 end
        return 2
    end
    function UnitPowerMax(_, powerType)
        if powerType == PT.ComboPoints or powerType == PT.HolyPower or powerType == PT.SoulShards
            or powerType == PT.ArcaneCharges then
            return 5
        end
        return 100
    end
    function GetComboPoints(unit, target)
        assert(unit == "player" and target == "target", "combo points must be read for player on target")
        S.comboCalls = S.comboCalls + 1
        return S.target
    end
    function GetShapeshiftFormID() return S.form end
    function UnitPowerDisplayMod() return 1 end
    function UnitHasVehicleUI() return false end
    function UnitAffectingCombat() return false end
    function GetSpecialization() return spec.spec or 1 end
    C_SpellBook = { IsSpellKnown = function() return true end }
    C_Spell = { GetSpellMaxCumulativeAuraApplications = function() return 10 end }
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
    local bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false }
    for key, value in pairs(spec.bars or {}) do bars[key] = value end
    local general = {}
    for key, value in pairs(spec.general or {}) do general[key] = value end
    MSUF_DB = { general = general, bars = bars }

    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    for i = 1, #LOAD_ORDER do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. LOAD_ORDER[i]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register")

    t.module = module
    t.CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    t.eventFrame = Upvalue(assert(t.CP.SyncControllerEvents, "SyncControllerEvents missing"), "eventFrame")
    t.onEvent = assert(t.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    module.Enable()
    return t
end

local function Registered(t, event)
    return t.eventFrame.events[event] == true
end

local function Fire(t, event, ...)
    assert(Registered(t, event), event .. " is not registered, so the client would never deliver it")
    t.onEvent(t.eventFrame, event, ...)
end

local function Filled(t)
    local count = 0
    for i = 1, t.CP.currentMax or 0 do
        local bar = t.CP.bars[i]
        if bar and bar.value == 1 then count = count + 1 end
    end
    return count
end

local function AssertHidden(t, label)
    assert(t.CP.visible ~= true, label .. ": class power bar is visible")
    assert(t.CP.renderMode == MODE_NONE, label .. ": render mode " .. tostring(t.CP.renderMode))
    assert(t.CP.powerType == nil, label .. ": power type " .. tostring(t.CP.powerType))
    assert(not Registered(t, "PLAYER_TARGET_CHANGED"), label .. ": PLAYER_TARGET_CHANGED bound")
    assert(not Registered(t, "COMBO_TARGET_CHANGED"), label .. ": COMBO_TARGET_CHANGED bound")
end

local function AssertCombo(t, label)
    assert(t.CP.visible == true, label .. ": combo point bar is hidden")
    assert(t.CP.renderMode == MODE_SEGMENTED and t.CP.powerType == PT.ComboPoints,
        label .. ": routed " .. tostring(t.CP.powerType) .. "/" .. tostring(t.CP.renderMode))
end

local CASES = {}
local function Case(name, run) CASES[#CASES + 1] = { name = name, run = run } end

-- Every Retail class resource Blizzard excludes for camelot, including the
-- spec-index and opt-in routes, must stay dark whatever index Forever reports.
local HIDDEN_ROUTES = {
    { class = "PALADIN", spec = 1 },
    { class = "PALADIN", spec = 3 },
    { class = "WARLOCK", spec = 1 },
    { class = "WARLOCK", spec = 3 },
    { class = "MAGE", spec = 1 },
    { class = "MAGE", spec = 3 },
    { class = "WARRIOR", spec = 1, bars = { showSweepingStrikes = true } },
    { class = "WARRIOR", spec = 2 },
    { class = "SHAMAN", spec = 1, bars = { showEleMaelstrom = true } },
    { class = "SHAMAN", spec = 2 },
    { class = "PRIEST", spec = 3, bars = { showShadowMana = true } },
    { class = "HUNTER", spec = 3 },
    { class = "DRUID", spec = 3, primary = PT.Rage, bars = { showGuardianIronfur = true } },
    { class = "DRUID", spec = 1, primary = PT.Mana },
}
for _, route in ipairs(HIDDEN_ROUTES) do
    Case("Forever hides " .. route.class .. " spec " .. route.spec, function()
        local t = Start({ client = "forever", class = route.class, spec = route.spec,
            primary = route.primary, bars = route.bars })
        AssertHidden(t, route.class .. " spec " .. route.spec)
        return t
    end)
end

Case("Forever rogue combo points are target-owned", function()
    local t = Start({ client = "forever", class = "ROGUE", primary = PT.Energy })
    AssertCombo(t, "rogue")
    assert(t.S.comboCalls > 0, "combo points were not read from GetComboPoints")
    assert(Filled(t) == 0, "no target: expected 0 filled pips, got " .. Filled(t))
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "PLAYER_TARGET_CHANGED is not bound")
    assert(Registered(t, "COMBO_TARGET_CHANGED"), "COMBO_TARGET_CHANGED is not bound")
    assert(Registered(t, "UNIT_POWER_FREQUENT"), "combo points must follow UNIT_POWER_FREQUENT")
    assert(not Registered(t, "UNIT_POWER_UPDATE"), "UNIT_POWER_UPDATE bound next to UNIT_POWER_FREQUENT")

    t.S.target = 4
    Fire(t, "PLAYER_TARGET_CHANGED")
    assert(Filled(t) == 4, "target swap: expected 4 filled pips, got " .. Filled(t))
    t.S.target = 1
    Fire(t, "COMBO_TARGET_CHANGED")
    assert(Filled(t) == 1, "combo target change: expected 1 filled pip, got " .. Filled(t))
    t.S.target = 3
    Fire(t, "UNIT_POWER_FREQUENT", "player", "ENERGY")
    assert(Filled(t) == 3, "energy power event: expected 3 filled pips, got " .. Filled(t))
    t.S.target = 5
    Fire(t, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    assert(Filled(t) == 5, "combo power event: expected 5 filled pips, got " .. Filled(t))
    t.S.target = 0
    Fire(t, "UNIT_POWER_FREQUENT", "player", "RAGE")
    assert(Filled(t) == 5, "an unrelated power token refreshed the combo points")
    return t
end)

Case("Forever rogue without lite bindings still follows the target", function()
    local t = Start({ client = "forever", class = "ROGUE", primary = PT.Energy,
        general = { perfLiteClassPowerEvents = false } })
    AssertCombo(t, "rogue full bindings")
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "PLAYER_TARGET_CHANGED is not bound")
    t.S.target = 2
    Fire(t, "PLAYER_TARGET_CHANGED")
    assert(Filled(t) == 2, "target swap: expected 2 filled pips, got " .. Filled(t))
    return t
end)

Case("Forever never registers a rejected COMBO_TARGET_CHANGED", function()
    local t = Start({ client = "forever", class = "ROGUE", primary = PT.Energy, comboTargetEvent = false })
    AssertCombo(t, "rogue")
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "PLAYER_TARGET_CHANGED is not bound")
    assert(not Registered(t, "COMBO_TARGET_CHANGED"), "rejected COMBO_TARGET_CHANGED was registered")
    return t
end)

Case("Forever druid combo points follow Cat Form", function()
    local t = Start({ client = "forever", class = "DRUID", spec = 2, primary = PT.Mana })
    AssertHidden(t, "caster druid")
    t.S.primary = PT.Energy
    Fire(t, "UPDATE_SHAPESHIFT_FORM")
    t.env:RunTimers()
    AssertCombo(t, "cat druid")
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "cat form: PLAYER_TARGET_CHANGED is not bound")
    t.S.target = 3
    Fire(t, "PLAYER_TARGET_CHANGED")
    assert(Filled(t) == 3, "cat form target swap: expected 3 filled pips, got " .. Filled(t))
    t.S.primary = PT.Rage
    t.env.now = t.env.now + 1
    Fire(t, "UNIT_DISPLAYPOWER", "player")
    t.env:RunTimers()
    AssertHidden(t, "bear druid")
    return t
end)

-- Retail keeps class and spec routing, reads player-owned combo points and never
-- binds the target events, with or without a client table.
for _, client in ipairs({ "standard", "none" }) do
    local clientSpec = client ~= "none" and client or nil
    Case("Retail (" .. client .. ") keeps Holy Power", function()
        local t = Start({ client = clientSpec, class = "PALADIN", spec = 3 })
        assert(t.CP.visible == true and t.CP.powerType == PT.HolyPower and t.CP.renderMode == MODE_SEGMENTED,
            "Retail paladin lost Holy Power")
        assert(not Registered(t, "PLAYER_TARGET_CHANGED"), "Retail bound PLAYER_TARGET_CHANGED")
        return t
    end)
    Case("Retail (" .. client .. ") keeps Arcane Charges", function()
        local t = Start({ client = clientSpec, class = "MAGE", spec = 1 })
        assert(t.CP.visible == true and t.CP.powerType == PT.ArcaneCharges, "Retail arcane mage lost Arcane Charges")
        return t
    end)
    Case("Retail (" .. client .. ") rogue combo points stay player-owned", function()
        local t = Start({ client = clientSpec, class = "ROGUE", primary = PT.Energy })
        AssertCombo(t, "Retail rogue")
        assert(t.S.comboCalls == 0, "Retail read GetComboPoints")
        assert(Filled(t) == 5, "Retail rogue: expected 5 player-owned pips, got " .. Filled(t))
        assert(not Registered(t, "PLAYER_TARGET_CHANGED"), "Retail bound PLAYER_TARGET_CHANGED")
        assert(not Registered(t, "COMBO_TARGET_CHANGED"), "Retail bound COMBO_TARGET_CHANGED")
        assert(Registered(t, "UNIT_POWER_UPDATE") and not Registered(t, "UNIT_POWER_FREQUENT"),
            "Retail rogue power event binding changed")
        t.S.owned = 2
        Fire(t, "UNIT_POWER_UPDATE", "player", "ENERGY")
        assert(Filled(t) == 5, "Retail accepted the Energy token for combo points")
        Fire(t, "UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
        assert(Filled(t) == 2, "Retail combo power event: expected 2 filled pips, got " .. Filled(t))
        return t
    end)
end

local passed, failures = 0, {}
for _, case in ipairs(CASES) do
    local ok, err = pcall(function()
        local t = case.run()
        t.module.Disable()
        t.module.Shutdown()
    end)
    if ok then
        passed = passed + 1
    else
        failures[#failures + 1] = case.name .. ": " .. tostring(err)
    end
end

if #failures > 0 then
    for i = 1, #failures do
        io.stderr:write("FAIL " .. failures[i] .. "\n")
    end
    os.exit(1)
end
print(string.format("PASS Mainline ClassPower Forever routing: %d cases", passed))
