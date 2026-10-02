-- classpower_world.lua -- a fake client for ClassPower controller smokes.
--
-- Loads the REAL ClassPower stack a client TOC lists (in TOC order) against the
-- shared test stubs, enables the module and returns the controller seams. The
-- stubs are those of classpower_target_combo_trace_smoke.lua without its
-- recorder; the resource values come from the returned state table S:
--   S.combo          player combo points
--   S.shards         every other class resource (default 3)
--   S.unmodified     UnitPower(unit, type, true) for fractional resources
--   S.displayMod     UnitPowerDisplayMod (default 1)
--   S.secretPower    class resources arrive as restricted values
--   S.auraStacks     tracked player aura applications
--   S.auraVariant    0/1: a second aura table with the same applications
--   S.stagger        UnitStagger
--   S.health         UnitHealth (default 500)
--   S.healthMax      UnitHealthMax (default 1000)
--   S.vehicle        UnitHasVehicleUI and PlayerVehicleHasComboPoints
--   S.form           GetShapeshiftFormID
--
-- World.StrictPowerTypes() (from a beforeLoad hook) makes UnitPower and
-- UnitPowerMax take an Enum.PowerType number (or nil) only, exactly like the
-- client binding: a string token raises "bad argument #2". It is opt-in so the
-- budget smoke's instruction counts keep measuring the addon, not the stub.
--
--   local World = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))()
--   local t = World.Start(root, "Mainline", "ROGUE", 1, World.PT.ENERGY, { classPowerTextMode = "CURMAX" })
--
-- An optional seventh argument { beforeLoad = function(env, S) end } runs after
-- the stubs are installed and before the first addon file loads, so a smoke can
-- swap in stricter globals (classpower_secrets.lua) that the files capture.
-- The cross-file providers ClassPower requires come from
-- classpower_collaborators.lua unless the hook defined its own.
--
-- Plain Lua 5.1.

local World = {}
local Collaborators
World.PT = { MANA = 0, RAGE = 1, ENERGY = 3, COMBO = 4, SHARDS = 7, ESSENCE = 19 }

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

--- Every ClassPower entry of a client's TOC, in TOC order.
local function ClassPowerLoadOrder(repo, tocName)
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

function World.Upvalue(fn, wanted)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

local function InstallClient(S)
    local PT_COMBO = World.PT.COMBO
    local secret = { __secret = true }
    function UnitClass() return S.class, S.class end
    function UnitPowerType() return S.primary end
    function UnitPower(_, powerType, unmodified)
        if powerType == S.primary then return 50 end
        if S.secretPower then return secret end
        if powerType == PT_COMBO then return S.combo end
        if unmodified and S.unmodified then return S.unmodified end
        return S.shards
    end
    function UnitPowerMax(_, powerType)
        if powerType == S.primary then return 100 end
        return 5
    end
    function UnitPartialPower() return 0 end
    function UnitPowerDisplayMod() return S.displayMod end
    function GetComboPoints() return S.combo end
    function UnitHasVehicleUI() return S.vehicle == true end
    function PlayerVehicleHasComboPoints() return S.vehicle == true end
    function GetShapeshiftFormID() return S.form end
    function GetSpecialization() return S.spec end
    function GetRuneCooldown(runeID)
        if runeID <= 3 then return 0, 10, true end
        return 995, 10, false
    end
    function GetRuneType() return 1 end
    function GetUnitChargedPowerPoints() return nil end
    function UnitStagger() return S.stagger end
    function UnitHealth() return S.health end
    function UnitHealthMax() return S.healthMax end
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
            local key = S.auraStacks * 2 + S.auraVariant
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
end

--- Wraps UnitPower and UnitPowerMax with the client's argument check. Call it
--- from a beforeLoad hook: the addon files capture the APIs at load.
function World.StrictPowerTypes()
    for _, api in ipairs({ "UnitPower", "UnitPowerMax" }) do
        local inner = _G[api]
        _G[api] = function(unit, powerType, ...)
            if powerType ~= nil and type(powerType) ~= "number" then
                error(("bad argument #2 to '%s' (number expected, got %s)"):format(api, type(powerType)), 2)
            end
            return inner(unit, powerType, ...)
        end
    end
end

--- Loads toc's ClassPower stack for one class and spec, with MSUF_DB.bars
--- overrides, and enables the module.
function World.Start(repo, toc, class, spec, primary, bars, hooks)
    Collaborators = Collaborators or assert(loadfile(repo .. "/tools/tests/classpower_collaborators.lua"))()
    local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
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

    local S = {
        class = class, spec = spec, primary = primary,
        combo = 3, shards = 3, displayMod = 1, auraStacks = 2, auraVariant = 0, stagger = 400,
        health = 500, healthMax = 1000,
    }
    InstallClient(S)
    if hooks and hooks.beforeLoad then hooks.beforeLoad(env, S) end
    Collaborators.Install(repo, ns)
    MSUF_DB = {
        general = {},
        bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false },
    }
    for key, value in pairs(bars or {}) do MSUF_DB.bars[key] = value end
    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    local order = ClassPowerLoadOrder(repo, toc)
    for index = 1, #order do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. order[index]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register: " .. toc .. " " .. class)
    module.Enable()
    env:RunTimers()
    local CP = World.Upvalue(World.Upvalue(module.Enable, "FullRefresh"), "CP")
    local eventFrame = World.Upvalue(assert(CP.SyncControllerEvents), "eventFrame")
    return {
        env = env, S = S, CP = CP, eventFrame = eventFrame, module = module,
        onEvent = assert(eventFrame.scripts.OnEvent, "controller OnEvent script missing"),
    }
end

--- Number of widget setter calls (Set*) fn makes: what a repaint costs the client.
function World.CountSetters(t, fn)
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
function World.Dispatcher(t, event, a1, a2, a3)
    local onEvent, frame = t.onEvent, t.eventFrame
    return function() onEvent(frame, event, a1, a2, a3) end
end

return World
