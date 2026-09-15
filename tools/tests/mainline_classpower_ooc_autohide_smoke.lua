-- Mainline ClassPower out-of-combat auto-hide.
-- Loads the real Retail-path ClassPower stack that only the Mainline TOC loads,
-- runs module.Enable against a stub player frame and drives combat events
-- through the controller's own OnEvent script.
-- PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns true, so
-- the combat-entry re-check must also accept UnitAffectingCombat("player").
-- Usage (cwd = repo root):
--   lua tools/tests/mainline_classpower_ooc_autohide_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required")

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

local PT_COMBO_POINTS = 4
local PT_ENERGY = 3
local MODE_SEGMENTED = 1

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS", "MSUF_CP_MODE_BUILDERS",
    "MSUF_CP_FEATURE_BUILDERS", "MSUF_CP_CoreUnitFrame", "MSUF_ClassPowerContainer", "MSUF_player",
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

local function ReadFile(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- The Retail controller must stay Mainline-only; the Classic flavors load their shadow.
do
    local base = repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_"
    local retailLine = "\nClassPower\\MSUF_CP_Controller.lua\n"
    assert(ReadFile(base .. "Mainline.toc"):find(retailLine, 1, true), "Mainline TOC lost the Retail ClassPower controller")
    for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
        local toc = ReadFile(base .. flavor .. ".toc")
        assert(not toc:find(retailLine, 1, true), flavor .. " TOC loads the Retail ClassPower controller")
        assert(toc:find("\nGame\\Classic\\ClassPower\\MSUF_CP_Controller.lua\n", 1, true),
            flavor .. " TOC lost the Classic ClassPower controller")
    end
end

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
    for i = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[i]] = nil end

    local S = { combo = spec.combo or 1, affecting = false }
    local t = { env = env, S = S }

    env.Methods.RegisterUnitEvent = function(self, event)
        self.events[event] = true
    end

    local ns = {}
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    _G.MSUF_NS = ns
    t.ns = ns

    function UnitClass() return "Rogue", "ROGUE" end
    function UnitPowerType() return PT_ENERGY end
    function UnitPower(_, powerType)
        if powerType == PT_COMBO_POINTS then return S.combo end
        return 0
    end
    function UnitPowerMax(_, powerType)
        if powerType == PT_COMBO_POINTS then return 5 end
        return 100
    end
    function UnitPowerDisplayMod() return 1 end
    function UnitHasVehicleUI() return false end
    function GetSpecialization() return 1 end
    function UnitAffectingCombat(unit)
        assert(unit == "player", "combat state must be read for the player")
        return S.affecting
    end
    function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    canaccesstable = function() return true end
    -- Shape and font helpers the Core captures at load time.
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
    MSUF_DB = {
        general = {},
        bars = {
            showClassPower = true,
            showAltMana = false,
            playerHPBarEnabled = false,
            classPowerHideOOC = spec.hideOOC == true,
            classPowerHideWhenEmpty = spec.hideWhenEmpty == true,
        },
    }

    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    for i = 1, #LOAD_ORDER do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. LOAD_ORDER[i]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register")

    t.module = module
    -- The texture-hook wrapper replaces FullRefresh; it still closes over CP.
    t.CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    t.eventFrame = Upvalue(assert(t.CP.SyncControllerEvents, "SyncControllerEvents missing"), "eventFrame")
    t.onEvent = assert(t.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    module.Enable()
    assert(t.CP.visible == true and t.CP.renderMode == MODE_SEGMENTED and t.CP.powerType == PT_COMBO_POINTS,
        "rogue combo points did not route to the segmented class power bar")
    t.container = assert(t.CP.container, "class power container missing")
    return t
end

local function Fire(t, event, ...)
    assert(t.eventFrame.events[event] == true, event .. " is not registered, so the client would never deliver it")
    t.onEvent(t.eventFrame, event, ...)
end

local function Shown(t)
    return t.container.shown ~= false and t.container.alpha ~= 0
end

local CASES = {}
local function Case(name, run) CASES[#CASES + 1] = { name = name, run = run } end

Case("combat entry shows the hidden bar", function()
    local t = Start({ hideOOC = true })
    assert(not Shown(t), "out of combat the bar must be hidden, alpha " .. tostring(t.container.alpha))
    -- The client delivers PLAYER_REGEN_DISABLED while InCombatLockdown() is still false.
    t.env.inCombat = false
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(t.container.alpha == 1 and t.container.shown ~= false,
        "combat entry left the bar hidden, alpha " .. tostring(t.container.alpha))
    return t
end)

Case("combat exit hides the bar again", function()
    local t = Start({ hideOOC = true })
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(t.container.alpha == 1, "combat entry left the bar hidden, alpha " .. tostring(t.container.alpha))
    t.S.affecting = false
    t.env.inCombat = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    assert(t.container.alpha == 0, "combat exit left the bar shown, alpha " .. tostring(t.container.alpha))
    return t
end)

Case("lockdown alone still counts as combat", function()
    local t = Start({ hideOOC = true })
    t.env.inCombat = true
    t.S.affecting = false
    t.module.RefreshSettings()
    assert(t.container.alpha == 1, "InCombatLockdown() true left the bar hidden, alpha " .. tostring(t.container.alpha))
    return t
end)

Case("setting off keeps the bar shown", function()
    local t = Start({ hideOOC = false })
    assert(Shown(t), "auto-hide off: bar hidden out of combat, alpha " .. tostring(t.container.alpha))
    t.S.affecting = true
    if t.eventFrame.events.PLAYER_REGEN_DISABLED then Fire(t, "PLAYER_REGEN_DISABLED") end
    assert(Shown(t), "auto-hide off: bar hidden in combat, alpha " .. tostring(t.container.alpha))
    t.S.affecting = false
    if t.eventFrame.events.PLAYER_REGEN_ENABLED then Fire(t, "PLAYER_REGEN_ENABLED") end
    assert(Shown(t), "auto-hide off: bar hidden after combat, alpha " .. tostring(t.container.alpha))
    return t
end)

-- Another auto-hide rule keeps the check running, so the OOC setting itself must gate the hide.
Case("setting off with another rule active keeps the bar shown", function()
    local t = Start({ hideOOC = false, hideWhenEmpty = true, combo = 1 })
    assert(t.container.alpha == 1, "OOC auto-hide off: bar hidden out of combat, alpha " .. tostring(t.container.alpha))
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(t.container.alpha == 1, "OOC auto-hide off: bar hidden in combat, alpha " .. tostring(t.container.alpha))
    t.S.affecting = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    assert(t.container.alpha == 1, "OOC auto-hide off: bar hidden after combat, alpha " .. tostring(t.container.alpha))
    return t
end)

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
        io.stderr:write("FAIL Mainline " .. failures[i] .. "\n")
    end
    os.exit(1)
end
print(string.format("PASS Mainline ClassPower OOC auto-hide: %d cases", passed))
