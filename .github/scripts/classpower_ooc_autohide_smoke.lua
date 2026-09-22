-- Class Resources "Hide out of combat" across a combat edge.
-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() is true. Combo
-- points recover on the next UNIT_POWER_UPDATE. Whirlwind is a native aura
-- with no power event, so the combat-entry check has to read
-- UnitAffectingCombat("player") or the bar stays hidden for the whole fight.
--
-- Usage (cwd = repo root):
--   lua .github/scripts/classpower_ooc_autohide_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required")
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

local PT_COMBO_POINTS = 4
local PT_ENERGY = 3
local MODE_SEGMENTED = 1
local MODE_NATIVE_AURA = 11

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

local function Start(spec)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 100 })
    env:InstallGlobals({ secretValue = true, time = true })
    _G.__MSUF_ClassPower_Loaded = nil
    _G.MSUF_CP_CONST = nil
    _G.MSUF_CP_CORE_BUILDERS = nil
    _G.MSUF_CP_MODE_BUILDERS = nil
    _G.MSUF_CP_FEATURE_BUILDERS = nil
    _G.MSUF_CP_CoreUnitFrame = nil
    _G.MSUF_ClassPowerContainer = nil
    _G.MSUF_player = nil

    local state = { combo = spec.combo or 0, affecting = false }
    local className = spec.class or "WARRIOR"
    local classFile = spec.classFile or "WARRIOR"
    local specIndex = spec.spec or 2

    local ns = {}
    local player = env:CreateFrame("Frame", "MSUF_player", _G.UIParent)
    player.shown = true
    player.MSUFSpec = { width = 240 }
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    _G.MSUF_NS = ns

    function _G.UnitClass() return className, classFile end
    function _G.UnitPowerType() return PT_ENERGY end
    function _G.UnitPower(_, powerType)
        if powerType == PT_COMBO_POINTS then return state.combo end
        return 0
    end
    function _G.UnitPowerMax(_, powerType)
        if powerType == PT_COMBO_POINTS then return 5 end
        return 100
    end
    function _G.UnitPowerDisplayMod() return 1 end
    function _G.UnitHasVehicleUI() return false end
    function _G.GetSpecialization() return specIndex end
    function _G.UnitAffectingCombat(unit)
        assert(unit == "player", "combat state must be read for the player")
        return state.affecting
    end
    function _G.wipe(tbl)
        for key in pairs(tbl) do tbl[key] = nil end
        return tbl
    end
    _G.canaccesstable = function() return true end
    _G.MSUF_UF_NormalizeClassPowerShape = function(shape)
        shape = shape and tostring(shape):upper() or "BAR"
        if shape == "" then shape = "BAR" end
        return shape
    end
    _G.MSUF_UF_NormalizeShapeAlign = function(value) return value or "CENTER" end
    _G.MSUF_ApplyResolvedFont = function(region, path, size, flags)
        if region.SetFont then region:SetFont(path, size, flags) end
        return true, path, "requested"
    end
    _G.MSUF_SetFontChecked = function(region, path, size, flags)
        if region.SetFont then region:SetFont(path, size, flags) end
        return true
    end
    _G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.MSUF_DB = {
        general = {},
        bars = {
            showClassPower = true,
            showAltMana = false,
            playerHPBarEnabled = false,
            classPowerHideOOC = spec.hideOOC == true,
            classPowerHideWhenEmpty = spec.hideWhenEmpty == true,
            classPowerHideWhenFull = false,
        },
    }

    local module
    function _G.MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    for i = 1, #LOAD_ORDER do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. LOAD_ORDER[i]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register")

    local harness = { env = env, state = state, module = module }
    harness.CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    harness.eventFrame = Upvalue(harness.CP.SyncControllerEvents, "eventFrame")
    harness.onEvent = assert(harness.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    module.Enable()
    harness.container = assert(harness.CP.container, "class power container missing")
    return harness
end

local function Fire(harness, event, ...)
    assert(harness.eventFrame.events[event] == true, event .. " is not registered")
    harness.onEvent(harness.eventFrame, event, ...)
end

local function EnterCombat(harness)
    harness.env.inCombat = false
    harness.state.affecting = true
    Fire(harness, "PLAYER_REGEN_DISABLED")
end

local function LeaveCombat(harness)
    harness.env.inCombat = false
    harness.state.affecting = false
    Fire(harness, "PLAYER_REGEN_ENABLED")
end

local cases = {}
local function Case(name, run) cases[#cases + 1] = { name = name, run = run } end

Case("whirlwind stays hidden out of combat and shows on combat entry", function()
    local harness = Start({ class = "Warrior", classFile = "WARRIOR", spec = 2, hideOOC = true })
    assert(harness.CP.powerType == "WHIRLWIND" and harness.CP.renderMode == MODE_NATIVE_AURA,
        "fury did not route to the native whirlwind bar")
    assert(harness.container.alpha == 0, "out of combat the bar must be hidden")
    EnterCombat(harness)
    assert(harness.container.alpha == 1, "combat entry left the whirlwind bar hidden")
    LeaveCombat(harness)
    assert(harness.container.alpha == 0, "combat exit left the whirlwind bar shown")
    harness.module.Disable()
    harness.module.Shutdown()
end)

Case("rogue combo points still show on the same combat edge", function()
    local harness = Start({ class = "Rogue", classFile = "ROGUE", spec = 1, combo = 1, hideOOC = true })
    assert(harness.CP.powerType == PT_COMBO_POINTS and harness.CP.renderMode == MODE_SEGMENTED,
        "rogue did not route to combo points")
    assert(harness.container.alpha == 0, "out of combat the combo bar must be hidden")
    EnterCombat(harness)
    assert(harness.container.alpha == 1, "combat entry left the combo bar hidden")
    LeaveCombat(harness)
    assert(harness.container.alpha == 0, "combat exit left the combo bar shown")
    harness.module.Disable()
    harness.module.Shutdown()
end)

Case("whirlwind stays shown when hide out of combat is off", function()
    local harness = Start({ class = "Warrior", classFile = "WARRIOR", spec = 2, hideOOC = false })
    assert(harness.container.alpha ~= 0, "auto-hide off hid the whirlwind bar")
    harness.module.Disable()
    harness.module.Shutdown()
end)

local failed = 0
for i = 1, #cases do
    local ok, err = pcall(cases[i].run)
    if not ok then
        failed = failed + 1
        io.stderr:write("FAIL " .. cases[i].name .. ": " .. tostring(err) .. "\n")
    end
end
if failed > 0 then os.exit(1) end
print("class power out-of-combat auto-hide smoke: ok")
