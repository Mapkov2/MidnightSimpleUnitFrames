-- Classic ClassPower with Class Resources ENABLED.
-- Loads the real Classic ClassPower stack once per class route, runs
-- module.Enable against a stub player frame and drives events through the
-- controller's own OnEvent script. It asserts bar values, bound events and
-- teardown, so the show path, event binding and mode updates stay covered.
-- Usage (cwd = repo root):
--   lua tools/tests/classic_classpower_enabled_smoke.lua <repoRoot> <Vanilla|TBC|Mists>
local repo = assert(arg[1], "repo root required")
local flavor = assert(arg[2], "flavor required")
assert(flavor == "Vanilla" or flavor == "TBC" or flavor == "Mists", "unknown flavor: " .. tostring(flavor))

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

-- Ids the Classic constants fall back to when Enum is absent (checked after load).
local PT = {
    Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4, Runes = 5, SoulShards = 7, HolyPower = 9,
    Chi = 12, BurningEmbers = 14, DemonicFury = 15, Balance = 26, ShadowOrbs = 28,
}
local MODE = {
    NONE = 0, SEGMENTED = 1, FRACTIONAL = 2, RUNE_CD = 3, AURA_SEGMENTED = 4,
    CONTINUOUS = 6, SIGNED_CONTINUOUS = 12,
}
local AFFLICTION_SPELL = 74434
local ARCANE_CHARGE = 36032

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS", "MSUF_CP_MODE_BUILDERS",
    "MSUF_CP_FEATURE_BUILDERS", "MSUF_ClassPowerContainer", "MSUF_player", "MSUF_ScheduleOnce",
    "MSUF_SetRoundLayoutToNearestPixel",
}

-- Same order as tools/tests/classic_classpower_runtime_smoke.lua and the TOCs.
local LOAD_ORDER = {
    "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    "Game/Classic/ClassPower/MSUF_CP_Constants.lua",
    "Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua",
    "Game/" .. flavor .. "/ClassPower.lua",
    "Game/Classic/ClassPower/MSUF_CP_Modes.lua",
    "Game/Classic/ClassPower/MSUF_CP_Core.lua",
    "ClassPower/MSUF_CP_AltMana.lua",
    "ClassPower/MSUF_CP_PlayerHP.lua",
    "ClassPower/MSUF_CP_Controller_Config.lua",
    "ClassPower/MSUF_CP_Controller_Colors.lua",
    "ClassPower/MSUF_CP_Controller_Surface.lua",
    "Game/Classic/ClassPower/MSUF_CP_Controller.lua",
}

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
        vehicleCombo = spec.vehicleCombo or 0,
        inVehicle = spec.inVehicle == true,
        form = spec.form,
        known = spec.known == true,
        arcane = spec.arcane or 0,
        affecting = false,
        readyRunes = 3,
    }
    local t = { env = env, S = S, containerShows = 0, containerHides = 0 }

    -- Record unit filters and reject an explicit nil unit, as the client does.
    env.Methods.RegisterUnitEvent = function(self, event, ...)
        local count = select("#", ...)
        local unit1, unit2 = ...
        assert(count >= 1 and unit1 ~= nil, "RegisterUnitEvent without a unit: " .. event)
        assert(count < 2 or unit2 ~= nil, "RegisterUnitEvent received an explicit nil unit: " .. event)
        self.events[event] = true
        self.unitFilters = self.unitFilters or {}
        self.unitFilters[event] = unit2 and (unit1 .. "+" .. unit2) or unit1
    end
    local baseShow, baseHide = env.Methods.Show, env.Methods.Hide
    env.Methods.Show = function(self)
        if self.frameName == "MSUF_ClassPowerContainer" then t.containerShows = t.containerShows + 1 end
        return baseShow(self)
    end
    env.Methods.Hide = function(self)
        if self.frameName == "MSUF_ClassPowerContainer" then t.containerHides = t.containerHides + 1 end
        return baseHide(self)
    end

    local denied = { UNIT_POWER_POINT_CHARGE = true, WAR_MODE_STATUS_UPDATE = true }
    for _, event in ipairs(spec.deny or {}) do denied[event] = true end
    local ns = { Client = { IsClassic = true, SupportsEvent = function(event) return denied[event] ~= true end } }
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    -- The factory builds this root on every Classic TOC; spec.visualRoot mirrors that.
    if spec.visualRoot then
        player._msufHealthVisualRoot = env:CreateFrame("Frame", nil, player)
    end
    t.player = player
    t.roundLayoutCalls = {}
    if spec.roundLayout then
        _G.MSUF_SetRoundLayoutToNearestPixel = function(frame, enabled)
            t.roundLayoutCalls[#t.roundLayoutCalls + 1] = { frame = frame, enabled = enabled }
            return true
        end
    end
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value end
    _G.MSUF_NS = ns
    t.ns = ns

    function UnitClass() return S.class, S.class end
    function UnitPowerType(unit)
        if unit == "vehicle" then return S.inVehicle and PT.ComboPoints or nil end
        return S.primary
    end
    function UnitPower(_, powerType) return S.power[powerType] or 0 end
    function UnitPowerMax(_, powerType) return S.max[powerType] or 0 end
    -- A client modifier of 1 would render raw ember power as whole embers.
    function UnitPowerDisplayMod() return 1 end
    function GetComboPoints(unit)
        if unit == "vehicle" then return S.vehicleCombo end
        return S.combo
    end
    function UnitHasVehicleUI() return S.inVehicle end
    function PlayerVehicleHasComboPoints() return S.inVehicle end
    function GetShapeshiftFormID() return S.form end
    function GetSpecialization() return S.spec end
    function GetRuneCooldown(runeID)
        if runeID <= S.readyRunes then return 0, 10, true end
        return 95, 10, false
    end
    -- Mists exposes rune types; the controller must still not bind RUNE_TYPE_UPDATE.
    function GetRuneType() return 1 end
    function UnitAffectingCombat() return S.affecting end
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
    MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    C_SpellBook = { IsSpellKnown = function(spellID) return spellID == AFFLICTION_SPELL and S.known end }
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
        bars = {
            showClassPower = true,
            showAltMana = false,
            playerHPBarEnabled = false,
            classPowerHideOOC = spec.hideOOC == true,
        },
    }

    local module
    function MSUF_RegisterModule(name, callbacks)
        assert(name == "ClassPower", "unexpected module " .. tostring(name))
        module = callbacks
    end
    for i = 1, #LOAD_ORDER do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. LOAD_ORDER[i]))("MSUF", ns)
    end
    assert(module, "controller did not register")
    local K = assert(MSUF_CP_CONST)
    for name, id in pairs(PT) do assert(K.PT[name] == id, "power type id drifted: " .. name) end
    for name, id in pairs(MODE) do assert(K.CPK.MODE[name] == id, "render mode id drifted: " .. name) end

    t.module = module
    t.FullRefresh = Upvalue(module.Enable, "FullRefresh")
    t.CP = Upvalue(t.FullRefresh, "CP")
    t.eventFrame = Upvalue(Upvalue(t.FullRefresh, "CP_RefreshEventBindings"), "eventFrame")
    t.onEvent = assert(t.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    module.Enable()
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
    assert(CP.currentMax == #expected,
        label .. ": max " .. tostring(CP.currentMax) .. ", expected " .. #expected)
    for i = 1, #expected do
        local bar = CP.bars[i]
        local value = bar and bar.value
        assert(Near(value, expected[i]), string.format("%s: bar %d is %s, expected %s",
            label, i, tostring(value), tostring(expected[i])))
    end
end

local function ExpectHidden(t, label)
    assert(t.CP.visible == false, label .. ": class power should be hidden")
    local container = _G.MSUF_ClassPowerContainer
    assert(container == nil or container.shown == false, label .. ": container is still shown")
end

local function Teardown(t, label)
    t.module.Disable()
    t.module.Shutdown()
    local left = {}
    for event in pairs(t.eventFrame.events) do left[#left + 1] = event end
    table.sort(left)
    assert(#left == 0, label .. ": events left after teardown: " .. table.concat(left, ", "))
    local container = _G.MSUF_ClassPowerContainer
    assert(container == nil or container.shown == false, label .. ": container still shown after teardown")
end

--------------------------------------------------------------------------
-- Cases
--------------------------------------------------------------------------

local CASES = {}
local ERA = { Vanilla = true, TBC = true }
local MISTS = { Mists = true }

local function Case(name, flavors, run)
    CASES[#CASES + 1] = { name = name, flavors = flavors, run = run }
end

Case("rogue combo points", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 3, max = { [PT.ComboPoints] = 5 } })
    assert(t.CP.renderMode == MODE.SEGMENTED and t.CP.powerType == PT.ComboPoints, "rogue route")
    ExpectBars(t, { 1, 1, 1, 0, 0 }, "rogue")
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "rogue lost PLAYER_TARGET_CHANGED")
    assert(Registered(t, "COMBO_TARGET_CHANGED"), "rogue lost COMBO_TARGET_CHANGED")
    assert(Registered(t, "UNIT_POWER_FREQUENT") and not Registered(t, "UNIT_POWER_UPDATE"), "rogue power binding")
    assert(t.eventFrame.unitFilters.UNIT_POWER_FREQUENT == "player", "rogue power event must stay player-only")
    assert(not Registered(t, "SPELLS_CHANGED"), "rogue bound the Warlock-only SPELLS_CHANGED")
    t.S.combo = 5
    Fire(t, "COMBO_TARGET_CHANGED")
    ExpectBars(t, { 1, 1, 1, 1, 1 }, "rogue after COMBO_TARGET_CHANGED")
    t.S.combo = 2
    Fire(t, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    ExpectBars(t, { 1, 1, 0, 0, 0 }, "rogue after UNIT_POWER_FREQUENT")
    return t
end)

Case("rogue without lite bindings", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 },
        general = { perfLiteClassPowerEvents = false } })
    ExpectBars(t, { 1, 0, 0, 0, 0 }, "non-lite rogue")
    assert(Registered(t, "COMBO_TARGET_CHANGED"), "non-lite rogue lost COMBO_TARGET_CHANGED")
    assert(Registered(t, "PLAYER_TARGET_CHANGED"), "non-lite rogue lost PLAYER_TARGET_CHANGED")
    return t
end)

Case("cat druid", nil, function()
    local t = Start({ class = "DRUID", spec = 2, primary = PT.Energy, combo = 2, max = { [PT.ComboPoints] = 5 } })
    ExpectBars(t, { 1, 1, 0, 0, 0 }, "cat druid")
    return t
end)

Case("caster druid", nil, function()
    local t = Start({ class = "DRUID", spec = 2, primary = PT.Mana, combo = 2, max = { [PT.ComboPoints] = 5 } })
    ExpectHidden(t, "caster druid")
    assert(Registered(t, "UPDATE_SHAPESHIFT_FORM"), "hidden druid must keep watching form changes")
    return t
end)

Case("paladin has no Era resource", ERA, function()
    local t = Start({ class = "PALADIN", spec = 1, primary = PT.Mana, power = { [PT.HolyPower] = 2 },
        max = { [PT.HolyPower] = 3 } })
    ExpectHidden(t, "Era paladin")
    return t
end)

Case("out-of-combat auto-hide", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 },
        hideOOC = true })
    local container = assert(t.CP.container, "OOC container")
    assert(container.alpha == 0, "out of combat the bar must be hidden, alpha " .. tostring(container.alpha))
    -- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true.
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(container.alpha == 1, "combat entry left the bar hidden, alpha " .. tostring(container.alpha))
    t.S.affecting = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    assert(container.alpha == 0, "combat exit left the bar shown, alpha " .. tostring(container.alpha))
    return t
end)

Case("form change rebuilds once", nil, function()
    local t = Start({ class = "DRUID", spec = 2, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 } })
    ExpectBars(t, { 1, 0, 0, 0, 0 }, "cat form")
    -- Leaving cat form delivers both events; the deferred check must not rebuild again.
    local hides = t.containerHides
    t.S.primary = PT.Mana
    t.env:AdvanceTime(1)
    Fire(t, "UPDATE_SHAPESHIFT_FORM")
    Fire(t, "UNIT_DISPLAYPOWER", "player")
    t.env:RunTimers()
    ExpectHidden(t, "caster form")
    assert(t.containerHides - hides == 1, "leaving cat form rebuilt " .. (t.containerHides - hides) .. " times")
    -- Hidden class power drops UNIT_DISPLAYPOWER, so the form event alone must rebuild.
    local shows = t.containerShows
    assert(not Registered(t, "UNIT_DISPLAYPOWER"), "hidden class power kept UNIT_DISPLAYPOWER")
    t.S.primary = PT.Energy
    t.env:AdvanceTime(1)
    Fire(t, "UPDATE_SHAPESHIFT_FORM")
    t.env:RunTimers()
    ExpectBars(t, { 1, 0, 0, 0, 0 }, "cat form again")
    assert(t.containerShows - shows == 1, "entering cat form showed the bar " .. (t.containerShows - shows) .. " times")
    return t
end)

Case("unsupported structural event stays unregistered", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 },
        deny = { "TRAIT_CONFIG_UPDATED" } })
    assert(not Registered(t, "TRAIT_CONFIG_UPDATED"), "SupportsEvent denial ignored for TRAIT_CONFIG_UPDATED")
    assert(Registered(t, "PLAYER_TALENT_UPDATE"), "supported structural events must still register")
    assert(Registered(t, "PLAYER_ENTERING_WORLD"), "startup events must still register")
    return t
end)

Case("resolve env table is reused", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 } })
    local provider = t.ns.CPClient
    local realResolve = provider.Resolve
    local seen = {}
    provider.Resolve = function(resolveEnv)
        seen[#seen + 1] = resolveEnv
        return realResolve(resolveEnv)
    end
    t.FullRefresh()
    Fire(t, "UNIT_DISPLAYPOWER", "player")
    t.FullRefresh()
    provider.Resolve = realResolve
    assert(#seen >= 3, "resolver was not consulted: " .. #seen)
    for i = 2, #seen do
        assert(seen[i] == seen[1], "resolve env table was reallocated on call " .. i)
    end
    return t
end)

-- The container parents like Retail: the health visual root when present.
Case("container parents to the health visual root", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 },
        visualRoot = true, roundLayout = true })
    local root = assert(t.player._msufHealthVisualRoot, "stub visual root missing")
    local container = assert(t.CP.container, "container was not created")
    assert(container == _G.MSUF_ClassPowerContainer, "container lost its global name")
    assert(container:GetParent() == root, "container must parent to the health visual root")
    assert(root:GetParent() == t.player, "stub visual root must stay a child of the player frame")
    local rounded = 0
    for i = 1, #t.roundLayoutCalls do
        local call = t.roundLayoutCalls[i]
        if call.frame == container then
            assert(call.enabled == true, "container round layout must be enabled")
            rounded = rounded + 1
        end
    end
    assert(rounded == 1, "container round layout calls: " .. rounded)
    assert(container:GetFrameLevel() == t.player:GetFrameLevel() + 5,
        "explicit container frame level lost: " .. tostring(container:GetFrameLevel()))
    ExpectBars(t, { 1, 0, 0, 0, 0 }, "root-parented rogue")
    return t
end)

Case("container falls back to the player frame", nil, function()
    local t = Start({ class = "ROGUE", spec = 1, primary = PT.Energy, combo = 1, max = { [PT.ComboPoints] = 5 } })
    assert(t.player._msufHealthVisualRoot == nil, "fallback case must not have a visual root")
    assert(_G.MSUF_SetRoundLayoutToNearestPixel == nil, "fallback case must run without the round layout helper")
    local container = assert(t.CP.container, "container was not created")
    assert(container:GetParent() == t.player, "without a visual root the container must parent to the player frame")
    assert(container:GetFrameLevel() == t.player:GetFrameLevel() + 5,
        "explicit container frame level lost: " .. tostring(container:GetFrameLevel()))
    ExpectBars(t, { 1, 0, 0, 0, 0 }, "player-parented rogue")
    return t
end)

Case("death knight runes", MISTS, function()
    local t = Start({ class = "DEATHKNIGHT", spec = 1, primary = 6 })
    assert(t.CP.renderMode == MODE.RUNE_CD and t.CP.powerType == PT.Runes, "DK route")
    assert(t.CP.currentMax == 6, "DK must show 6 runes, got " .. tostring(t.CP.currentMax))
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
    assert(ready == 3 and cooling == 3, "fallback rune values: ready " .. ready .. ", cooling " .. cooling)
    assert(Registered(t, "RUNE_POWER_UPDATE"), "DK lost RUNE_POWER_UPDATE")
    assert(not Registered(t, "RUNE_TYPE_UPDATE"), "rune type colouring is an owner decision; RUNE_TYPE_UPDATE must stay unbound")
    t.S.readyRunes = 4
    Fire(t, "RUNE_POWER_UPDATE", 4, true)
    ready, cooling = Count()
    assert(ready == 4 and cooling == 2, "RUNE_POWER_UPDATE: ready " .. ready .. ", cooling " .. cooling)
    return t
end)

Case("holy paladin", MISTS, function()
    local t = Start({ class = "PALADIN", spec = 1, primary = PT.Mana, power = { [PT.HolyPower] = 2 },
        max = { [PT.HolyPower] = 3 } })
    ExpectBars(t, { 1, 1, 0 }, "holy paladin")
    assert(Registered(t, "UNIT_POWER_UPDATE"), "Holy Power must bind UNIT_POWER_UPDATE")
    assert(not Registered(t, "UNIT_POWER_FREQUENT"), "Holy Power must not bind UNIT_POWER_FREQUENT")
    t.S.power[PT.HolyPower] = 3
    Fire(t, "UNIT_POWER_UPDATE", "player", "HOLY_POWER")
    ExpectBars(t, { 1, 1, 1 }, "holy paladin after UNIT_POWER_UPDATE")
    return t
end)

Case("monk chi", MISTS, function()
    local t = Start({ class = "MONK", spec = 3, primary = PT.Energy, power = { [PT.Chi] = 2 }, max = { [PT.Chi] = 4 } })
    ExpectBars(t, { 1, 1, 0, 0 }, "monk")
    t.S.power[PT.Chi] = 4
    Fire(t, "UNIT_POWER_FREQUENT", "player", "CHI")
    ExpectBars(t, { 1, 1, 1, 1 }, "monk after UNIT_POWER_FREQUENT")
    return t
end)

Case("affliction with the shard spell", MISTS, function()
    local t = Start({ class = "WARLOCK", spec = 1, primary = PT.Mana, known = true,
        power = { [PT.SoulShards] = 2 }, max = { [PT.SoulShards] = 3 } })
    ExpectBars(t, { 1, 1, 0 }, "affliction")
    assert(Registered(t, "SPELLS_CHANGED"), "Warlock lost SPELLS_CHANGED")
    return t
end)

Case("affliction learns the shard spell", MISTS, function()
    local t = Start({ class = "WARLOCK", spec = 1, primary = PT.Mana, known = false,
        power = { [PT.SoulShards] = 2 }, max = { [PT.SoulShards] = 3 } })
    ExpectHidden(t, "affliction without the spell")
    assert(Registered(t, "SPELLS_CHANGED"), "hidden Warlock must keep SPELLS_CHANGED")
    C_SpellBook.IsSpellKnown = function(spellID) return spellID == AFFLICTION_SPELL end
    t.env:AdvanceTime(1)
    Fire(t, "SPELLS_CHANGED")
    ExpectBars(t, { 1, 1, 0 }, "affliction after SPELLS_CHANGED")
    local shows = t.containerShows
    t.env:AdvanceTime(1)
    Fire(t, "SPELLS_CHANGED")
    assert(t.containerShows == shows, "an unchanged SPELLS_CHANGED rebuilt the bar")
    return t
end)

Case("demonology fury", MISTS, function()
    local t = Start({ class = "WARLOCK", spec = 2, primary = PT.Mana,
        power = { [PT.DemonicFury] = 200 }, max = { [PT.DemonicFury] = 1000 } })
    assert(t.CP.renderMode == MODE.CONTINUOUS, "demonology route")
    ExpectBars(t, { 200 }, "demonology")
    assert(t.CP.bars[1].maximum == 1000, "demonology max")
    return t
end)

Case("destruction embers", MISTS, function()
    local t = Start({ class = "WARLOCK", spec = 3, primary = PT.Mana,
        power = { [PT.BurningEmbers] = 25 }, max = { [PT.BurningEmbers] = 4 } })
    assert(t.CP.renderMode == MODE.FRACTIONAL, "destruction route")
    ExpectBars(t, { 1, 1, 0.5, 0 }, "destruction with a client display modifier of 1")
    return t
end)

Case("arcane mage without charges", MISTS, function()
    local t = Start({ class = "MAGE", spec = 1, primary = PT.Mana, arcane = 0 })
    assert(t.CP.renderMode == MODE.AURA_SEGMENTED, "arcane route")
    ExpectBars(t, { 0, 0, 0, 0 }, "arcane without charges")
    assert(Registered(t, "UNIT_AURA"), "arcane lost UNIT_AURA")
    return t
end)

Case("arcane charges fall off", MISTS, function()
    local t = Start({ class = "MAGE", spec = 1, primary = PT.Mana, arcane = 2 })
    ExpectBars(t, { 1, 1, 0, 0 }, "arcane with 2 charges")
    t.S.arcane = 0
    Fire(t, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 7 } })
    t.env:RunTimers()
    ExpectBars(t, { 0, 0, 0, 0 }, "arcane after the charges fell off")
    return t
end)

Case("shadow priest orbs", MISTS, function()
    local t = Start({ class = "PRIEST", spec = 3, primary = PT.Mana,
        power = { [PT.ShadowOrbs] = 1 }, max = { [PT.ShadowOrbs] = 3 } })
    ExpectBars(t, { 1, 0, 0 }, "shadow priest")
    return t
end)

Case("discipline priest has no resource", MISTS, function()
    local t = Start({ class = "PRIEST", spec = 1, primary = PT.Mana,
        power = { [PT.ShadowOrbs] = 1 }, max = { [PT.ShadowOrbs] = 3 } })
    ExpectHidden(t, "discipline priest")
    return t
end)

Case("balance eclipse", MISTS, function()
    local t = Start({ class = "DRUID", spec = 1, primary = PT.Mana,
        power = { [PT.Balance] = -40 }, max = { [PT.Balance] = 100 } })
    assert(t.CP.renderMode == MODE.SIGNED_CONTINUOUS, "balance route")
    ExpectBars(t, { -40 }, "balance")
    local bar = t.CP.bars[1]
    assert(bar.minimum == -100 and bar.maximum == 100, "balance range " .. tostring(bar.minimum) .. ".." .. tostring(bar.maximum))
    return t
end)

Case("vehicle combo points", MISTS, function()
    local t = Start({ class = "WARRIOR", spec = 1, primary = PT.Rage, inVehicle = true, vehicleCombo = 2,
        max = { [PT.ComboPoints] = 5 } })
    assert(t.CP.isVehicle == true and t.CP.powerType == PT.ComboPoints, "vehicle route")
    ExpectBars(t, { 1, 1, 0, 0, 0 }, "vehicle combo points")
    assert(t.eventFrame.unitFilters.UNIT_POWER_FREQUENT == "player+vehicle",
        "vehicle combo points must also listen to the vehicle unit, got "
        .. tostring(t.eventFrame.unitFilters.UNIT_POWER_FREQUENT))
    assert(Registered(t, "COMBO_TARGET_CHANGED"), "vehicle combo points lost COMBO_TARGET_CHANGED")
    t.S.vehicleCombo = 4
    Fire(t, "UNIT_POWER_FREQUENT", "vehicle", "COMBO_POINTS")
    ExpectBars(t, { 1, 1, 1, 1, 0 }, "vehicle combo points after the vehicle power event")
    t.S.inVehicle = false
    Fire(t, "UNIT_EXITED_VEHICLE", "player")
    t.env:RunTimers()
    ExpectHidden(t, "warrior after leaving the vehicle")
    assert(not Registered(t, "UNIT_POWER_FREQUENT"), "vehicle power event outlived the vehicle")
    return t
end)

--------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------

local passed, failures = 0, {}
for _, case in ipairs(CASES) do
    if case.flavors == nil or case.flavors[flavor] then
        local ok, err = pcall(function()
            Teardown(case.run(), case.name)
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
print(string.format("PASS %s enabled ClassPower routes: %d cases", flavor, passed))
