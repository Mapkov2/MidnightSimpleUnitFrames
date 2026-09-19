-- Behavioural call trace of the REAL ClassPower stack, per client.
--
-- Target-owned combo points exist on Classic Era, TBC, Mists and WoW Forever,
-- and the shared pieces that serve them live in one module instead of one copy
-- per client. This smoke proves that the collapse changed nothing a player can
-- see: it loads the genuine ClassPower files each TOC lists (the load order is
-- read from the TOC, never hard-coded), drives every class the client has
-- through login, spec and form changes, a vehicle, combat, death, resurrect and
-- power events, and records every widget and event call the controller makes.
-- The recorded trace is reduced to a digest per client and class; the digests
-- below were taken from the code before the collapse, so a routing, binding or
-- drawing difference on any client fails here.
--
-- Render modes are recorded by NAME, not by their number, so renumbering a mode
-- id (the ids are runtime-only and never persisted) is not a behaviour change.
--
-- Usage (cwd = repo root):
--   lua tools/tests/classpower_target_combo_trace_smoke.lua <repoRoot>
--   lua tools/tests/classpower_target_combo_trace_smoke.lua <repoRoot> print
-- "print" writes every trace line to stdout instead of asserting, which is how
-- the digests are produced and how two trees are compared line by line.
local repo = assert(arg[1], "repo root required")
local printMode = arg[2] == "print"

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

--------------------------------------------------------------------------
-- Clients
--------------------------------------------------------------------------

local ERA_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}
local MISTS_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
    "WARLOCK", "MONK", "DRUID",
}
local RETAIL_CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
    "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
--- WoW Forever has nine classes: no Death Knight, Monk, Demon Hunter or Evoker.
local FOREVER_CLASSES = ERA_CLASSES

--- Classic Era and TBC have no specialization API, so their spec is always nil.
--- Forever reports an index that the routing must ignore.
local CLIENTS = {
    { name = "Vanilla",  toc = "Vanilla",  classes = ERA_CLASSES,     specs = { false } },
    { name = "TBC",      toc = "TBC",      classes = ERA_CLASSES,     specs = { false } },
    { name = "Mists",    toc = "Mists",    classes = MISTS_CLASSES,   specs = { 1, 2, 3, 4 } },
    { name = "Mainline", toc = "Mainline", classes = RETAIL_CLASSES,  specs = { 1, 2, 3, 4 } },
    { name = "Forever",  toc = "Mainline", classes = FOREVER_CLASSES, specs = { 1, 2, 3 }, forever = true },
}

--- Digest of the full trace of one client and class, taken from the code
--- before the target-combo collapse. Regenerate with the "print" argument only
--- when a behaviour change is intended and reviewed.
local EXPECTED = {
    ["Vanilla/WARRIOR"] = "a50b51afde998314",
    ["Vanilla/PALADIN"] = "a50b51afde998314",
    ["Vanilla/HUNTER"] = "a50b51afde998314",
    ["Vanilla/ROGUE"] = "63b8a50bc6d9992c",
    ["Vanilla/PRIEST"] = "a50b51afde998314",
    ["Vanilla/SHAMAN"] = "a50b51afde998314",
    ["Vanilla/MAGE"] = "a50b51afde998314",
    ["Vanilla/WARLOCK"] = "a50b51afde998314",
    ["Vanilla/DRUID"] = "ff7bb48f208b916b",

    ["TBC/WARRIOR"] = "a50b51afde998314",
    ["TBC/PALADIN"] = "a50b51afde998314",
    ["TBC/HUNTER"] = "a50b51afde998314",
    ["TBC/ROGUE"] = "63b8a50bc6d9992c",
    ["TBC/PRIEST"] = "a50b51afde998314",
    ["TBC/SHAMAN"] = "a50b51afde998314",
    ["TBC/MAGE"] = "a50b51afde998314",
    ["TBC/WARLOCK"] = "a50b51afde998314",
    ["TBC/DRUID"] = "ff7bb48f208b916b",

    ["Mists/WARRIOR"] = "ef7f741cd5190dff",
    ["Mists/PALADIN"] = "38be83d819e5c124",
    ["Mists/HUNTER"] = "ef7f741cd5190dff",
    ["Mists/ROGUE"] = "a7279d7324cdacd4",
    ["Mists/PRIEST"] = "5ba23dd5ac9b8b26",
    ["Mists/DEATHKNIGHT"] = "bb2f14c7ca8d6068",
    ["Mists/SHAMAN"] = "ef7f741cd5190dff",
    ["Mists/MAGE"] = "56ee375fbf125b64",
    ["Mists/WARLOCK"] = "1e80070178ba2f70",
    ["Mists/MONK"] = "40d3a0ce1aa8ad94",
    ["Mists/DRUID"] = "651421f8c8820c67",

    ["Mainline/WARRIOR"] = "6b1b61ffa4165e4d",
    ["Mainline/PALADIN"] = "a3a7c6713dabcb71",
    ["Mainline/HUNTER"] = "966aed0ec83a8523",
    ["Mainline/ROGUE"] = "3ebdf16fef00a5c3",
    ["Mainline/PRIEST"] = "44acd3d8d8b98143",
    ["Mainline/DEATHKNIGHT"] = "a4aac5bb6719ba27",
    ["Mainline/SHAMAN"] = "496777e2752251e1",
    ["Mainline/MAGE"] = "016d2252aec0ef47",
    ["Mainline/WARLOCK"] = "030beac69a7284fa",
    ["Mainline/MONK"] = "4b786ce893df75a2",
    ["Mainline/DRUID"] = "568009f0e4431047",
    ["Mainline/DEMONHUNTER"] = "456b96e68f5a2c5b",
    ["Mainline/EVOKER"] = "fbdfc22966299360",

    ["Forever/WARRIOR"] = "74d205ba322dc1f9",
    ["Forever/PALADIN"] = "74d205ba322dc1f9",
    ["Forever/HUNTER"] = "74d205ba322dc1f9",
    ["Forever/ROGUE"] = "94fde2b6dbe23a86",
    ["Forever/PRIEST"] = "74d205ba322dc1f9",
    ["Forever/SHAMAN"] = "74d205ba322dc1f9",
    ["Forever/MAGE"] = "74d205ba322dc1f9",
    ["Forever/WARLOCK"] = "74d205ba322dc1f9",
    ["Forever/DRUID"] = "e783e22b23f6445e",
}

--------------------------------------------------------------------------
-- Load order straight from the TOC
--------------------------------------------------------------------------

--- Every ClassPower entry of a client's TOC, in TOC order. Each client's
--- provider, shared modules and controller all carry "ClassPower" in their
--- path, and no other core TOC entry does.
local function ClassPowerLoadOrder(tocName)
    local path = repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. tocName .. ".toc"
    local file = assert(io.open(path, "rb"), "missing TOC: " .. path)
    local raw = file:read("*a")
    file:close()
    local order = {
        --- The secret-value helpers load long before ClassPower on every TOC.
        "Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua",
    }
    for line in raw:gmatch("[^\r\n]+") do
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:find("ClassPower", 1, true) then
            order[#order + 1] = entry:gsub("\\", "/")
        end
    end
    assert(#order > 3, "no ClassPower entries in " .. path)
    return order
end

--------------------------------------------------------------------------
-- Trace
--------------------------------------------------------------------------

local function Digest(lines)
    --- Two independent moduli, so a reordering or a single changed byte moves
    --- the digest. Lua 5.1 has no bitwise operators; the products stay far
    --- below 2^53 and are therefore exact.
    local h1, h2 = 5381, 52711
    for index = 1, #lines do
        local line = lines[index]
        for position = 1, #line do
            local byte = line:byte(position)
            h1 = (h1 * 33 + byte) % 4294967291
            h2 = (h2 * 31 + byte) % 4294967279
        end
        h1 = (h1 * 33 + 10) % 4294967291
        h2 = (h2 * 31 + 10) % 4294967279
    end
    return string.format("%08x%08x", h1, h2)
end

local function Number(value)
    if type(value) ~= "number" then return tostring(value) end
    --- %.6g keeps a bar value readable and never prints platform float noise.
    return string.format("%.6g", value)
end

--------------------------------------------------------------------------
-- Harness
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

--- Power ids the constants fall back to without Enum, kept local so the
--- scenario can drive a specific resource.
local PT_MANA, PT_ENERGY, PT_RAGE, PT_COMBO = 0, 3, 1, 4

local function Upvalue(fn, wanted)
    for index = 1, 255 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing test seam: " .. wanted, 2)
end

local function Start(client, class)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 1000 })
    env:InstallGlobals({ secretValue = true, time = true })
    for index = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[index]] = nil end

    local S = {
        class = class,
        spec = client.specs[1] or nil,
        primary = PT_MANA,
        --- The player-owned combo value differs from the target-owned one, so a
        --- route reading the wrong source shows a different pip count.
        ownedCombo = 5,
        targetCombo = 2,
        vehicleCombo = 3,
        inVehicle = false,
        vehiclePower = nil,
        form = nil,
        inCombat = false,
        readyRunes = 3,
        auraStacks = 2,
    }
    local trace = {}
    local labels, labelCount = {}, 0
    local t = { env = env, S = S, trace = trace }

    local function Label(object)
        if object == nil then return "nil" end
        if type(object) ~= "table" then return tostring(object) end
        local known = labels[object]
        if known then return known end
        labelCount = labelCount + 1
        local name = rawget(object, "frameName")
        known = (name and tostring(name)) or ((rawget(object, "objectType") or "obj") .. "#" .. labelCount)
        labels[object] = known
        return known
    end
    t.Label = Label

    local function Record(line)
        trace[#trace + 1] = line
    end
    t.Record = Record

    --- Wrap exactly the calls a player would notice: event bindings, bar
    --- values, transparency, parenting, mouse handling and visibility.
    local methods = env.Methods
    local baseRegister = methods.RegisterEvent
    local baseRegisterUnit = methods.RegisterUnitEvent
    local baseUnregister = methods.UnregisterEvent
    local baseSetValue = methods.SetValue
    local baseSetAlpha = methods.SetAlpha
    local baseSetParent = methods.SetParent
    local baseEnableMouse = methods.EnableMouse
    local baseShow = methods.Show
    local baseHide = methods.Hide

    methods.RegisterEvent = function(self, event)
        Record("RegisterEvent " .. Label(self) .. " " .. tostring(event))
        return baseRegister(self, event)
    end
    methods.RegisterUnitEvent = function(self, event, unit1, unit2)
        assert(unit1 ~= nil, "RegisterUnitEvent without a unit: " .. tostring(event))
        Record("RegisterEvent " .. Label(self) .. " " .. tostring(event)
            .. " @" .. tostring(unit1) .. (unit2 and ("+" .. tostring(unit2)) or ""))
        return baseRegisterUnit(self, event, unit1, unit2)
    end
    methods.UnregisterEvent = function(self, event)
        Record("UnregisterEvent " .. Label(self) .. " " .. tostring(event))
        return baseUnregister(self, event)
    end
    methods.SetValue = function(self, value)
        Record("SetValue " .. Label(self) .. " " .. Number(value))
        return baseSetValue(self, value)
    end
    methods.SetAlpha = function(self, alpha)
        Record("SetAlpha " .. Label(self) .. " " .. Number(alpha))
        return baseSetAlpha(self, alpha)
    end
    methods.SetParent = function(self, parent)
        Record("SetParent " .. Label(self) .. " " .. Label(parent))
        return baseSetParent(self, parent)
    end
    methods.EnableMouse = function(self, enabled)
        Record("EnableMouse " .. Label(self) .. " " .. tostring(enabled))
        return baseEnableMouse(self, enabled)
    end
    methods.Show = function(self)
        Record("Show " .. Label(self))
        return baseShow(self)
    end
    methods.Hide = function(self)
        Record("Hide " .. Label(self))
        return baseHide(self)
    end

    local ns = {
        Client = {
            Family = client.forever and "Mainline" or (client.toc == "Mainline" and "Mainline" or "Classic"),
            Flavor = client.toc,
            IsClassic = client.toc ~= "Mainline",
            IsRetail = client.toc == "Mainline",
            IsForever = client.forever == true,
            SupportsEvent = function(event)
                --- The Classic harness denylist of classic_classpower_enabled_smoke.
                if client.toc == "Mainline" then return true end
                return event ~= "UNIT_POWER_POINT_CHARGE" and event ~= "WAR_MODE_STATUS_UPDATE"
            end,
        },
    }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    _G.MSUF_NS = ns
    t.ns = ns
    t.player = player

    function UnitClass() return S.class, S.class end
    function UnitPowerType(unit)
        if unit == "vehicle" then return S.vehiclePower end
        return S.primary
    end
    function UnitPower(_, powerType)
        if powerType == PT_COMBO then return S.ownedCombo end
        if powerType == S.primary then return 50 end
        return 3
    end
    function UnitPowerMax(_, powerType)
        if powerType == S.primary then return 100 end
        return 5
    end
    function UnitPartialPower() return 0 end
    function UnitPowerDisplayMod() return 1 end
    function GetComboPoints(unit)
        if unit == "vehicle" then return S.vehicleCombo end
        return S.targetCombo
    end
    function UnitHasVehicleUI() return S.inVehicle end
    function PlayerVehicleHasComboPoints() return S.inVehicle end
    function GetShapeshiftFormID() return S.form end
    function GetSpecialization() return S.spec or nil end
    function GetRuneCooldown(runeID)
        if runeID <= S.readyRunes then return 0, 10, true end
        return 95, 10, false
    end
    function GetRuneType() return 1 end
    function GetUnitChargedPowerPoints() return nil end
    function UnitStagger() return 40 end
    function UnitHealth() return 500 end
    function UnitHealthMax() return 1000 end
    function UnitAffectingCombat() return S.inCombat end
    function InCombatLockdown() return S.inCombat end
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
    C_UnitAuras = {
        GetPlayerAuraBySpellID = function(spellID)
            return {
                spellId = spellID, auraInstanceID = 11, applications = S.auraStacks,
                expirationTime = 0, duration = 0,
            }
        end,
        GetAuraDataBySpellName = function() return nil end,
    }
    --- Every feature switch at its shipped default, so the trace is the
    --- default player experience on each client.
    MSUF_DB = {
        general = {},
        bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false },
    }

    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    local order = ClassPowerLoadOrder(client.toc)
    for index = 1, #order do
        local path = repo .. "/MidnightSimpleUnitFrames/" .. order[index]
        assert(loadfile(path), "cannot load " .. order[index])("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register: " .. client.name .. " " .. class)

    t.module = module
    t.CP = Upvalue(Upvalue(module.Enable, "FullRefresh"), "CP")
    t.eventFrame = Upvalue(assert(t.CP.SyncControllerEvents, "SyncControllerEvents missing"), "eventFrame")
    t.onEvent = assert(t.eventFrame.scripts.OnEvent, "controller OnEvent script missing")
    t.K = assert(_G.MSUF_CP_CONST, "ClassPower constants missing")
    return t
end

--------------------------------------------------------------------------
-- Scenario
--------------------------------------------------------------------------

local function ModeName(t, mode)
    for name, value in pairs(t.K.CPK.MODE) do
        if value == mode then return name end
    end
    return "MODE(" .. tostring(mode) .. ")"
end

local function PowerName(t, powerType)
    if powerType == nil then return "none" end
    local token = t.K.POWER_TYPE_TOKENS[powerType]
    if token then return token end
    return tostring(powerType)
end

local function RecordRoute(t, label)
    local CP = t.CP
    t.Record("route " .. label
        .. " power=" .. PowerName(t, CP.powerType)
        .. " mode=" .. ModeName(t, CP.renderMode)
        .. " visible=" .. tostring(CP.visible == true)
        .. " max=" .. tostring(CP.currentMax)
        .. " vehicle=" .. tostring(CP.isVehicle == true))
end

--- Only a registered event reaches an addon, so an unbound one is recorded as
--- skipped instead of fired: the binding difference stays visible in the trace.
local function Fire(t, label, event, ...)
    if t.eventFrame.events[event] ~= true then
        t.Record("skip " .. label .. " " .. event)
        return false
    end
    t.Record("fire " .. label .. " " .. event)
    t.onEvent(t.eventFrame, event, ...)
    t.env:RunTimers()
    return true
end

--- Structural refreshes are throttled to 0.15s; step past it every time.
local function Step(t)
    t.env:AdvanceTime(1)
end

local function RunClass(client, class)
    local t = Start(client, class)

    t.Record("login")
    t.module.Enable()
    t.env:RunTimers()
    RecordRoute(t, "login")

    --- Spec resolution: every spec the client can report for this class.
    for index = 1, #client.specs do
        local spec = client.specs[index]
        t.S.spec = spec or nil
        Step(t)
        if not Fire(t, "spec" .. tostring(spec), "PLAYER_SPECIALIZATION_CHANGED", "player") then
            Fire(t, "spec" .. tostring(spec), "PLAYER_TALENT_UPDATE")
        end
        RecordRoute(t, "spec=" .. tostring(spec))
    end
    t.S.spec = client.specs[1] or nil
    Step(t)
    Fire(t, "specReset", "PLAYER_SPECIALIZATION_CHANGED", "player")

    --- Form change: Cat Form is the one that turns combo points on.
    t.S.primary = PT_ENERGY
    t.S.form = 1
    Step(t)
    Fire(t, "catform", "UPDATE_SHAPESHIFT_FORM")
    Fire(t, "catform", "UNIT_DISPLAYPOWER", "player")
    RecordRoute(t, "catform")

    t.S.primary = PT_RAGE
    t.S.form = 5
    Step(t)
    Fire(t, "bearform", "UPDATE_SHAPESHIFT_FORM")
    Fire(t, "bearform", "UNIT_DISPLAYPOWER", "player")
    RecordRoute(t, "bearform")

    t.S.primary = PT_MANA
    t.S.form = nil
    Step(t)
    Fire(t, "noform", "UPDATE_SHAPESHIFT_FORM")
    RecordRoute(t, "noform")

    --- Vehicle: entering hands combo points to the vehicle, leaving restores.
    t.S.inVehicle = true
    t.S.vehiclePower = PT_COMBO
    Step(t)
    Fire(t, "vehicleEnter", "UNIT_ENTERED_VEHICLE", "player")
    RecordRoute(t, "vehicleEnter")
    Fire(t, "vehiclePower", "UNIT_POWER_FREQUENT", "vehicle", "COMBO_POINTS")
    Fire(t, "vehiclePower", "UNIT_POWER_UPDATE", "vehicle", "COMBO_POINTS")

    t.S.inVehicle = false
    t.S.vehiclePower = nil
    Step(t)
    Fire(t, "vehicleExit", "UNIT_EXITED_VEHICLE", "player")
    RecordRoute(t, "vehicleExit")

    --- Combat: PLAYER_REGEN_DISABLED arrives before the lockdown turns true.
    t.S.inCombat = true
    Fire(t, "combatStart", "PLAYER_REGEN_DISABLED")
    t.S.inCombat = false
    Fire(t, "combatEnd", "PLAYER_REGEN_ENABLED")
    RecordRoute(t, "combat")

    Fire(t, "death", "PLAYER_DEAD")
    RecordRoute(t, "death")
    Fire(t, "resurrect", "PLAYER_ALIVE")
    RecordRoute(t, "resurrect")

    --- Power events: the resource token, the Energy token a target-owned combo
    --- point change arrives with, and an unrelated token that must be ignored.
    t.S.targetCombo = 4
    t.S.ownedCombo = 1
    for _, token in ipairs({ "COMBO_POINTS", "ENERGY", "RAGE", "HOLY_POWER", "RUNES" }) do
        Fire(t, "power=" .. token, "UNIT_POWER_UPDATE", "player", token)
        Fire(t, "power=" .. token, "UNIT_POWER_FREQUENT", "player", token)
    end
    RecordRoute(t, "power")
    Fire(t, "maxpower", "UNIT_MAXPOWER", "player", "COMBO_POINTS")
    Fire(t, "aura", "UNIT_AURA", "player", { isFullUpdate = true })
    Fire(t, "rune", "RUNE_POWER_UPDATE", 1, true)
    Fire(t, "targetChanged", "PLAYER_TARGET_CHANGED")
    Fire(t, "comboTarget", "COMBO_TARGET_CHANGED")
    RecordRoute(t, "final")

    t.module.Disable()
    t.module.Shutdown()
    local left = {}
    for event in pairs(t.eventFrame.events) do left[#left + 1] = event end
    table.sort(left)
    t.Record("afterTeardown events=" .. table.concat(left, ","))
    return t.trace
end

--------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------

--- The Blizzard resource frames each provider owns, and the restore call each
--- definition makes when MSUF stops suppressing them. Only the Classic
--- BlizzardFrames compat layer reads this list.
local BLIZZARD_FRAMES = {
    Vanilla = {
        ROGUE = { { "ComboFrame", "ComboFrame_UpdateMax" } },
        DRUID = { { "ComboFrame", "ComboFrame_UpdateMax" } },
    },
    TBC = {
        ROGUE = { { "ComboFrame", "ComboFrame_UpdateMax" } },
        DRUID = { { "ComboFrame", "ComboFrame_UpdateMax" } },
    },
    Mists = {
        ROGUE = { { "ComboFrame", "ComboFrame_UpdateMax" } },
        DRUID = { { "ComboFrame", "ComboFrame_UpdateMax" }, { "EclipseBarFrame", "UpdateShown" } },
        DEATHKNIGHT = { { "RuneFrame", "Show" } },
        PALADIN = { { "PaladinPowerBar", "Show,Update" } },
        WARLOCK = { { "WarlockPowerFrame", "SetUpCurrentPower" } },
        MONK = { { "MonkHarmonyBar", "Show,Update" } },
        PRIEST = { { "PriestBarFrame", "CheckAndShow" } },
    },
}

--- Provider contract per client. Midnight has no provider at all; WoW Forever
--- has one but owns no Blizzard resource frame, because its ComboFrame follows
--- Blizzard's target frame (Kernel/MSUF_BlizzardFrames.lua), not the class
--- resource suppression the Classic compat layer drives.
local function AssertProvider(client, class)
    local t = Start(client, class)
    local provider = t.ns.CPClient
    local where = client.name .. "/" .. class
    if client.name == "Mainline" then
        assert(provider == nil, where .. ": Midnight must have no ClassPower provider")
        return
    end
    assert(provider ~= nil, where .. ": no ClassPower provider")
    assert(provider.Flavor == client.name, where .. ": provider flavor " .. tostring(provider.Flavor))
    --- The Mainline controller reads the target-change rule through a Client
    --- table, the Classic controller reads it from the provider itself.
    local needsTargetChanged
    if client.name == "Forever" then
        assert(provider.NeedsTargetChanged == nil,
            where .. ": Mainline reads the target-change rule through Client")
        needsTargetChanged = assert(provider.Client, where .. ": no Client table").NeedsTargetChanged
    else
        assert(provider.Client == nil,
            where .. ": the Classic controller reads the target-change rule from the provider")
        needsTargetChanged = provider.NeedsTargetChanged
    end
    assert(needsTargetChanged(t.K.PT.ComboPoints) == true,
        where .. ": combo points must follow the target")
    assert(needsTargetChanged(t.K.PT.Mana) == false,
        where .. ": only combo points follow the target")
    assert(provider.AcceptPowerToken(t.K.PT.ComboPoints, "COMBO_POINTS", "COMBO_POINTS", class) == true,
        where .. ": combo point token rejected")
    local energyAccepted = provider.AcceptPowerToken(t.K.PT.ComboPoints, "ENERGY", "COMBO_POINTS", class) == true
    local comboClass = class == "ROGUE" or class == "DRUID"
    assert(energyAccepted == comboClass,
        where .. ": Energy token acceptance is " .. tostring(energyAccepted))
    assert(provider.UnitPower("player", t.K.PT.ComboPoints) == t.S.targetCombo,
        where .. ": combo points are not read from the target")
    assert(provider.UnitPower("player", t.K.PT.Rage) == 3,
        where .. ": other powers must delegate to the client")

    local expected = (BLIZZARD_FRAMES[client.name] or {})[class] or {}
    local definitions = provider.BlizzardFrames
    if client.name == "Forever" then
        assert(definitions == nil,
            where .. ": Forever's ComboFrame follows the Blizzard target frame, not the provider")
        return
    end
    assert(type(definitions) == "table", where .. ": BlizzardFrames must be a list")
    assert(#definitions == #expected,
        where .. ": " .. #definitions .. " Blizzard frames, expected " .. #expected)
    for index = 1, #expected do
        local definition = definitions[index]
        assert(definition.name == expected[index][1],
            where .. ": Blizzard frame " .. index .. " is " .. tostring(definition.name))
        local calls = {}
        local frame = t.env:CreateFrame("Frame", definition.name, UIParent)
        for _, method in ipairs({ "Update", "UpdateShown", "CheckAndShow", "SetUpCurrentPower" }) do
            frame[method] = function() calls[#calls + 1] = method end
        end
        frame.Show = function() calls[#calls + 1] = "Show" end
        _G.ComboFrame_UpdateMax = function() calls[#calls + 1] = "ComboFrame_UpdateMax" end
        definition.restore(frame)
        _G.ComboFrame_UpdateMax = nil
        assert(table.concat(calls, ",") == expected[index][2],
            where .. ": restoring " .. definition.name .. " called "
            .. table.concat(calls, ",") .. ", expected " .. expected[index][2])
    end
end

--- Mode ids key the hot-path dispatch tables, the mode event profiles and the
--- per-mode updaters. They must be unique inside one client's table and mean
--- the same thing across clients: a Classic-only mode that reuses a Retail id
--- would silently take that resource's updater once the two tables are merged.
local MODE_IDS = {}
local function AssertModeIds(client)
    local t = Start(client, "ROGUE")
    local seenHere = {}
    for name, value in pairs(t.K.CPK.MODE) do
        assert(type(value) == "number", client.name .. ": mode " .. name .. " is not a number")
        assert(seenHere[value] == nil,
            client.name .. ": mode id " .. tostring(value) .. " is used by both "
            .. tostring(seenHere[value]) .. " and " .. name)
        seenHere[value] = name
        local owner = MODE_IDS[value]
        assert(owner == nil or owner == name,
            client.name .. ": mode id " .. tostring(value) .. " is " .. name
            .. " here and " .. tostring(owner) .. " on another client")
        MODE_IDS[value] = name
    end
end

local failures, checked = {}, 0
for _, client in ipairs(CLIENTS) do
    --- The mode-id and provider contracts are structure checks, never part of
    --- the behaviour trace, so "print" keeps producing the same lines on a tree
    --- that predates the shared provider.
    if not printMode then AssertModeIds(client) end
    for _, class in ipairs(client.classes) do
        local key = client.name .. "/" .. class
        if not printMode then
            local providerOk, providerError = pcall(AssertProvider, client, class)
            if not providerOk then failures[#failures + 1] = tostring(providerError) end
        end
        local ok, result = pcall(RunClass, client, class)
        if not ok then
            failures[#failures + 1] = key .. ": " .. tostring(result)
        elseif printMode then
            print("=== " .. key .. " digest=" .. Digest(result) .. " lines=" .. #result)
            for index = 1, #result do print(key .. "| " .. result[index]) end
        else
            checked = checked + 1
            local expected = EXPECTED[key]
            local actual = Digest(result)
            if expected == nil then
                failures[#failures + 1] = key .. ": no recorded trace digest (actual " .. actual .. ")"
            elseif expected ~= actual then
                failures[#failures + 1] = key .. ": trace changed, expected " .. expected
                    .. " got " .. actual .. "\n  " .. table.concat(result, "\n  ")
            end
        end
    end
end

if #failures > 0 then
    for index = 1, #failures do
        io.stderr:write("FAIL " .. failures[index] .. "\n")
    end
    os.exit(1)
end
if printMode then
    io.stderr:write("printed ClassPower traces\n")
else
    print(string.format("PASS ClassPower target-combo behaviour trace: %d client/class traces", checked))
end
