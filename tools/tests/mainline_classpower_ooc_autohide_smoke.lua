-- Mainline ClassPower out-of-combat auto-hide.
-- Loads the real Retail-path ClassPower stack in Mainline TOC order,
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
    "Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua",
    "Game/Forever/ClassPower.lua",
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

-- Every client runs this Retail-named controller. The Classic flavors also load
-- their provider adapter before it; Mainline never does.
do
    local base = repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_"
    local retailLine = "\nClassPower\\MSUF_CP_Controller.lua\n"
    local routingLine = "\nGame\\Classic\\ClassPower\\MSUF_CP_ClassicRouting.lua\n"
    local mainline = ReadFile(base .. "Mainline.toc")
    assert(mainline:find(retailLine, 1, true), "Mainline TOC lost the Retail ClassPower controller")
    assert(not mainline:find(routingLine, 1, true), "Mainline TOC loads the Classic ClassPower routing")
    for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
        local toc = ReadFile(base .. flavor .. ".toc")
        local controllerAt = toc:find(retailLine, 1, true)
        local routingAt = toc:find(routingLine, 1, true)
        assert(controllerAt, flavor .. " TOC lost the ClassPower controller")
        assert(routingAt and routingAt < controllerAt,
            flavor .. " TOC must load the Classic ClassPower routing before the controller")
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
    player.MSUFUnitKey = "player"
    ns.UF = {
        GetFrame = function(unit) if unit == "player" then return player end end,
        RegisterElement = function(name, element)
            if name == "Power" then t.powerElement = element end
        end,
    }
    ns.UFBarTextCommon = { UF = ns.UF }
    ns.UFText = { UF = ns.UF, tonumber = tonumber, floor = math.floor, max = math.max, CreateFrame = CreateFrame }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    _G.MSUF_NS = ns
    t.ns = ns
    t.player = player

    -- The actual Power element owns all surfaces. The text layout module owns
    -- the independent hover overlay, which must not reveal hidden power text.
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))("MidnightSimpleUnitFrames", ns)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))("MidnightSimpleUnitFrames", ns)
    local bar = env:CreateFrame("StatusBar", nil, player)
    bar.MSUFPowerBorderHost = env:CreateFrame("Frame", nil, player)
    local background = player:CreateTexture()
    local trail = env:CreateFrame("StatusBar", nil, player)
    local secondTrail = env:CreateFrame("StatusBar", nil, player)
    trail._msufLossTrailPool = { trail, secondTrail }
    player.targetPowerBar = bar
    player.powerBarBG = background
    player.powerLossTrail = trail
    player.MSUFPowerTextLayer = env:CreateFrame("Frame", nil, player)
    t.bar, t.background, t.trail = bar, background, trail

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
            classPowerSyncPlayerPowerOOC = spec.syncPower == true,
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

local function PowerHidden(t)
    return t.player._msufClassPowerOocHidden == true
        and t.bar.alpha == 0
        and t.background.alpha == 0
        and t.bar.MSUFPowerBorderHost.alpha == 0
        and t.trail:GetStatusBarTexture().alpha == 0
        and t.player.MSUFPowerTextLayer.alpha == 0
end

Case("opt-in hides all Player Power surfaces out of combat", function()
    local t = Start({ hideOOC = true, syncPower = true })
    assert(PowerHidden(t), "Player Power surfaces were not hidden with Class Resource")
    assert(t.trail._msufLossTrailPool[2]:GetStatusBarTexture().alpha == 0,
        "second loss snapshot was not hidden")
    return t
end)

Case("detached Power reapplies while hidden without changing geometry", function()
    local t = Start({ hideOOC = true, syncPower = true })
    assert(PowerHidden(t), "precondition: Player Power was not hidden")
    local spec = {
        key = "player", scope = "unit", texture = "Interface\\Buttons\\WHITE8X8",
        power = {
            enabled = true, detached = true, detachedWidth = 90, detachedHeight = 8,
            detachedX = 7, detachedY = -3, r = 0.2, g = 0.4, b = 0.8, alpha = 1,
            background = { r = 0, g = 0, b = 0, a = 0.5 },
        },
    }
    t.player.MSUFSpec = spec
    local overlay = t.player.MSUFPowerTextLayer
    t.player._msufHoverPower = overlay
    overlay._msufHoverAlpha = 1
    overlay.alpha = 1
    t.powerElement.Apply(t.player, spec)
    assert(t.bar._msufDetached == true and t.bar.width == 90 and t.bar.height == 8,
        "detached Power geometry was not applied")
    assert(PowerHidden(t), "Power.Apply repaint exposed a hidden detached bar or text")
    local point, relativeTo, relativePoint, x, y = t.bar:GetPoint(1)
    t.powerElement.Apply(t.player, spec)
    local p2, r2, rp2, x2, y2 = t.bar:GetPoint(1)
    assert(p2 == point and r2 == relativeTo and rp2 == relativePoint and x2 == x and y2 == y,
        "reapply changed detached Power anchor")
    t.player.mouseOver = true
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(t.bar.alpha == 1 and overlay.alpha == 1,
        "combat did not reveal detached Player Power and hovered text")
    return t
end)

Case("combat entry restores all Player Power surfaces before lockdown", function()
    local t = Start({ hideOOC = true, syncPower = true })
    assert(PowerHidden(t), "precondition: Player Power was not hidden")
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(t.bar.alpha == 1 and t.background.alpha == 1
        and t.bar.MSUFPowerBorderHost.alpha == 1
        and t.trail:GetStatusBarTexture().alpha == 1
        and t.player.MSUFPowerTextLayer.alpha == 1,
        "Player Power surfaces did not return on combat entry")
    t.S.affecting = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    assert(PowerHidden(t), "Player Power did not hide again on combat exit")
    return t
end)

Case("Edit Mode reveals Player Power and restores OOC rule", function()
    local t = Start({ hideOOC = true, syncPower = true })
    assert(PowerHidden(t), "precondition: Player Power was not hidden")
    _G.MSUF_UnitEditModeActive = true
    t.module.RefreshSettings()
    assert(t.bar.alpha == 1 and t.player.MSUFPowerTextLayer.alpha == 1,
        "Edit Mode left Player Power hidden")
    _G.MSUF_UnitEditModeActive = nil
    t.module.RefreshSettings()
    assert(PowerHidden(t), "leaving Edit Mode did not restore OOC hide")
    return t
end)

Case("disabling Class Resource restores Player Power", function()
    local t = Start({ hideOOC = true, syncPower = true })
    assert(PowerHidden(t), "precondition: Player Power was not hidden")
    MSUF_DB.bars.showClassPower = false
    t.module.RefreshSettings()
    assert(t.bar.alpha == 1 and t.player.MSUFPowerTextLayer.alpha == 1,
        "disabled Class Resource left Player Power hidden")
    return t
end)

Case("module shutdown restores Player Power", function()
    local t = Start({ hideOOC = true, syncPower = true })
    t.module.Disable()
    assert(t.bar.alpha == 1 and t.player.MSUFPowerTextLayer.alpha == 1,
        "ClassPower module shutdown left Player Power hidden")
    return t
end)

Case("disabling sync restores Player Power without changing Class Resource", function()
    local t = Start({ hideOOC = true, syncPower = true })
    MSUF_DB.bars.classPowerSyncPlayerPowerOOC = false
    t.module.RefreshSettings()
    assert(not PowerHidden(t) and t.bar.alpha == 1,
        "sync switch off left Player Power hidden")
    assert(not Shown(t), "sync switch off changed Class Resource visibility")
    return t
end)

Case("turning off Class Resource OOC rule restores Player Power", function()
    local t = Start({ hideOOC = true, syncPower = true })
    MSUF_DB.bars.classPowerHideOOC = false
    t.module.RefreshSettings()
    assert(t.bar.alpha == 1 and t.player.MSUFPowerTextLayer.alpha == 1,
        "OOC rule off left Player Power hidden")
    assert(Shown(t), "OOC rule off left Class Resource hidden")
    return t
end)

Case("lockdown state reveals Player Power", function()
    local t = Start({ hideOOC = true, syncPower = true })
    t.env.inCombat = true
    t.module.RefreshSettings()
    assert(t.bar.alpha == 1 and t.background.alpha == 1,
        "lockdown state left Player Power hidden")
    return t
end)

Case("power text retains mouseover fade when combat reveals it", function()
    local t = Start({ hideOOC = true, syncPower = true })
    local overlay = t.player.MSUFPowerTextLayer
    t.player._msufHoverPower = overlay
    t.player.mouseOver = false
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(overlay.alpha == 0, "off-hover power text appeared during combat")
    t.S.affecting = false
    Fire(t, "PLAYER_REGEN_ENABLED")
    t.player.mouseOver = true
    t.S.affecting = true
    Fire(t, "PLAYER_REGEN_DISABLED")
    assert(overlay.alpha == 1, "hovered power text did not return during combat")
    return t
end)

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
