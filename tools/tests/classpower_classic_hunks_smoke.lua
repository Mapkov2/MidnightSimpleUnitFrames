-- ClassPower Classic hunks: present on the Classic clients, absent on Mainline.
--
-- Every client runs the Retail-named ClassPower core (constants, modes, core and
-- controller). Its Classic behaviour sits in hunks gated on MSUF.Client.IsClassic,
-- so Midnight and WoW Forever must keep executing exactly the Retail statements.
-- This smoke loads each client's real ClassPower stack in TOC order and pins
-- both sides of that contract: the Mists power ids, tokens, Arcane Charges data,
-- the signed Eclipse mode with its event profile, updater, visible-max and
-- frequent-power terms, the Classic aura watch set and the inert Ebon Might
-- hooks exist on Classic Era, TBC and Mists, and none of them leaks into the
-- Mainline stack. It also pins the Classic-only C_Spell nets: no Classic game
-- type loads a Blizzard call site for GetSpellCastCount or
-- GetSpellMaxCumulativeAuraApplications, so all four call sites (both Maelstrom
-- Weapon maximums, the Soul Cleave cast count and the Dark Heart maximum) carry
-- a net on the Classic build while Mainline still calls C_Spell directly.
--
-- Usage (cwd = repo root):
--   lua tools/tests/classpower_classic_hunks_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()

local CLIENTS = {
    { name = "Vanilla", toc = "Vanilla", classic = true },
    { name = "TBC", toc = "TBC", classic = true },
    { name = "Mists", toc = "Mists", classic = true },
    { name = "Mainline", toc = "Mainline" },
    { name = "Forever", toc = "Mainline", forever = true },
}

local CLEARED_GLOBALS = {
    "__MSUF_ClassPower_Loaded", "__MSUF_CP_Balance_Loaded", "MSUF_CP_CONST", "MSUF_CP_CORE_BUILDERS",
    "MSUF_CP_MODE_BUILDERS", "MSUF_CP_FEATURE_BUILDERS", "MSUF_CP_CoreUnitFrame", "MSUF_ClassPowerContainer",
    "MSUF_player", "MSUF_CP_MODE_EVENT_PROFILE",
}

-- The Classic-only values, as the Classic ClassPower shadows defined them.
local MISTS_ARCANE_CHARGE = 36032
local SIGNED_CONTINUOUS = 12
local CLASSIC_POWER = { BurningEmbers = 14, DemonicFury = 15, Balance = 26, ShadowOrbs = 28 }
local CLASSIC_TOKENS = {
    [14] = "BURNING_EMBERS", [15] = "DEMONIC_FURY", [26] = "BALANCE", [28] = "SHADOW_ORBS",
    MISTS_ARCANE_CHARGES = "ARCANE_CHARGES",
}

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

local function Load(client)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true, time = 100 })
    env:InstallGlobals({ secretValue = true, time = true })
    for index = 1, #CLEARED_GLOBALS do _G[CLEARED_GLOBALS[index]] = nil end

    -- Game/Classic/BlizzardFrames.lua publishes this on the Classic clients only.
    local suppressed = {}
    local ns = {
        Client = {
            Family = client.classic and "Classic" or "Mainline",
            Flavor = client.toc,
            IsClassic = client.classic == true,
            IsRetail = not client.classic,
            IsForever = client.forever == true,
            SupportsEvent = function() return true end,
        },
        Compat = {
            SetBlizzardClassResourcesSuppressed = function(suppress)
                suppressed[#suppressed + 1] = tostring(suppress)
                return true
            end,
        },
    }
    ns.ExportPublic = function(name, value) _G[name] = value return value end
    local player = env:CreateFrame("Frame", "MSUF_player", UIParent)
    player.shown = true
    ns.UF = { GetFrame = function(unit) if unit == "player" then return player end end }
    _G.MSUF_NS = ns

    -- A Rogue: target-owned combo points everywhere but Midnight, where they
    -- are player-owned; the class resource is visible on every client.
    local combo = 2
    function UnitClass() return "Rogue", "ROGUE" end
    function UnitPowerType() return 3 end
    function UnitPower(_, powerType) return powerType == 4 and combo or 50 end
    function UnitPowerMax() return 5 end
    function UnitPartialPower() return 0 end
    function UnitPowerDisplayMod() return 1 end
    function GetComboPoints() return combo end
    function UnitHasVehicleUI() return false end
    function GetSpecialization() return 1 end
    function UnitAffectingCombat() return false end
    function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
    canaccesstable = function() return true end
    C_SpellBook = { IsSpellKnown = function() return false end }
    -- The namespace exists on every client; the entry points this stack
    -- reaches for do not, which is the case each net below stands in for.
    C_Spell = {}
    C_UnitAuras = { GetPlayerAuraBySpellID = function() return nil end }
    MSUF_UF_NormalizeClassPowerShape = function(shape) return shape or "BAR" end
    MSUF_UF_NormalizeShapeAlign = function(value) return value or "CENTER" end
    MSUF_ApplyResolvedFont = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true, path, "requested"
    end
    MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
    MSUF_DB = { general = {}, bars = { showClassPower = true, showAltMana = false, playerHPBarEnabled = false } }

    local module
    function MSUF_RegisterModule(name, callbacks)
        if name == "ClassPower" then module = callbacks end
    end
    local order = ClassPowerLoadOrder(client.toc)
    for index = 1, #order do
        assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. order[index]))("MidnightSimpleUnitFrames", ns)
    end
    assert(module, "controller did not register")

    local wrapper = Upvalue(module.Enable, "FullRefresh")
    local CP = Upvalue(wrapper, "CP")
    -- The texture-hook wrapper replaces FullRefresh; the tables live on the original.
    local refresh = CP._origFullRefresh or wrapper
    -- The client's own class resource frames hide while the bar shows and
    -- return at module shutdown.
    module.Enable()
    env:RunTimers()
    local shown = CP.visible == true
    -- A target-owned combo point change can arrive with the Energy token; the
    -- provider rule needs the player's class to accept it.
    local eventFrame = Upvalue(CP.SyncControllerEvents, "eventFrame")
    local powerEvent = eventFrame.events.UNIT_POWER_FREQUENT and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE"
    combo = 4
    eventFrame.scripts.OnEvent(eventFrame, powerEvent, "player", "ENERGY")
    local filled = 0
    for index = 1, CP.currentMax or 0 do
        if CP.bars[index] and CP.bars[index].value == 1 then filled = filled + 1 end
    end
    module.Disable()
    module.Shutdown()
    local shouldUseFrequentPower = Upvalue(
        Upvalue(refresh, "CP_RefreshEventBindings"), "CP_ShouldUseFrequentPowerEvents")
    return {
        K = assert(_G.MSUF_CP_CONST, "constants missing"),
        profiles = assert(_G.MSUF_CP_MODE_EVENT_PROFILE, "mode event profiles missing"),
        modeBuilders = assert(_G.MSUF_CP_MODE_BUILDERS, "mode builders missing"),
        featureBuilders = assert(_G.MSUF_CP_FEATURE_BUILDERS, "feature builders missing"),
        AM = Upvalue(shouldUseFrequentPower, "AM"),
        ShouldUseFrequentPower = shouldUseFrequentPower,
        CP = CP,
        CPAuras = Upvalue(refresh, "CPAuras"),
        ResolveMaxPower = Upvalue(refresh, "Refresh").ResolveMaxPower,
        modeUpdate = Upvalue(refresh, "MODE_UPDATE_FN"),
        shown = shown,
        filledAfterEnergy = filled,
        suppressed = table.concat(suppressed, ","),
    }
end

local function Check(where, condition, message)
    if not condition then error(where .. ": " .. message, 2) end
end

-- A plain-value predicate: these paths never see a secret in this harness.
local function NotSecret() return true end

-- The RUNTIME feature builder only binds locals from its env and returns them,
-- so it can be built directly. C_Spell is deliberately empty: that is both the
-- resolution the Classic build performs once at build time and the guard case.
local function BuildRuntime(t, CP)
    return t.featureBuilders.RUNTIME({
        CP = CP, AM = { visible = false }, _cpDB = {},
        CPK = t.K.CPK, PT = t.K.PT, TIP = t.K.TIP, CPConst = t.K,
        POWER_TYPE_TOKENS = t.K.POWER_TYPE_TOKENS,
        UnitPowerMax = function() return 5 end,
        NotSecret = NotSecret, C_Spell = {},
        tonumber = tonumber, math_floor = math.floor,
    })
end

-- The aura render mode, on a client whose C_Spell has neither entry point.
local function BuildAuraMode(t)
    return t.modeBuilders.AURA({
        CP = { bars = {}, ticks = {}, maxBars = 0, spStacks = 0 }, _cpDB = {},
        CPK = t.K.CPK, CPConst = t.K, C_Spell = {}, C_UnitAuras = {},
        GetTrackedPlayerAura = function() return nil end,
        NotSecret = NotSecret, GetTime = function() return 100 end,
        CP_CheckAutoHide = function() end,
        GetVisual = function() return nil end,
        GetFilledAlpha = function() return 1 end,
        GetEmptyAlpha = function() return 0.3 end,
        ResolveClassPowerBgColor = function() return 0, 0, 0 end,
        ResolveMWAbove5Color = function() return 1, 1, 1 end,
    })
end

local function Run(client)
    local where = client.name
    local isClassic = client.classic == true
    local t = Load(client)
    local K, CPK = t.K, t.K.CPK
    local signedUpdate = t.modeBuilders.CONTINUOUS({ CP = { bars = {}, ticks = {} }, _cpDB = {} }).UpdateSigned
    Check(where, t.shown, "the Rogue class resource did not show")
    -- Target-owned combo points (Classic, Forever) accept the Energy token;
    -- Midnight's player-owned points ignore it.
    local energyFilled = (client.classic or client.forever) and 4 or 2
    Check(where, t.filledAfterEnergy == energyFilled, "after an Energy-token power event " .. t.filledAfterEnergy
        .. " combo points show, expected " .. energyFilled)

    -- Two Classic-only terms the ClassPower collapse must keep. Both are inert
    -- in the live stack - ResolveMaxPower stamps currentMax 1 for the signed
    -- mode, and the Mists provider claims PT.Balance before the frequent-power
    -- fallback chain runs - so only a direct call shows whether they are there.
    -- SIGNED_CONTINUOUS is 12 on Classic and unused on Mainline, where the same
    -- render mode id must fall through both terms untouched.
    local signedMax = BuildRuntime(t, { visible = true, powerType = "MISTS_ARCANE_CHARGES",
        renderMode = SIGNED_CONTINUOUS, currentMax = 5 }).GetResolvedVisibleMax()
    Check(where, signedMax == (isClassic and 1 or 5), "render mode " .. SIGNED_CONTINUOUS
        .. " resolved " .. tostring(signedMax) .. " visible segments, expected "
        .. (isClassic and "the signed Eclipse bar's 1" or "Mainline's untouched currentMax 5"))
    t.AM.visible = false
    t.CP.visible, t.CP.renderMode, t.CP.powerType = true, SIGNED_CONTINUOUS, "MISTS_ARCANE_CHARGES"
    -- No flavor provider claims this power type, so the fallback chain decides.
    local frequent = t.ShouldUseFrequentPower()
    Check(where, frequent == isClassic, "render mode " .. SIGNED_CONTINUOUS .. " asked for "
        .. (frequent and "UNIT_POWER_FREQUENT" or "UNIT_POWER_UPDATE") .. ", expected "
        .. (isClassic and "the frequent event a continuous bar needs"
            or "Mainline's untouched UNIT_POWER_UPDATE"))
    t.CP.renderMode = CPK.MODE.RUNE_CD
    Check(where, t.ShouldUseFrequentPower() == false,
        "a non-continuous render mode asked for UNIT_POWER_FREQUENT, so the term above proves nothing")
    t.CP.visible = false
    -- Mainline defines no such render mode, so both terms would sit inert there
    -- even without their Classic gate - the coincidence this pins against. Lend
    -- Mainline the mode id for one call each: the gate itself, not the missing
    -- constant, has to be what keeps Midnight and WoW Forever out.
    if not isClassic then
        CPK.MODE.SIGNED_CONTINUOUS = SIGNED_CONTINUOUS
        local lentMax = BuildRuntime(t, { visible = true, powerType = "MISTS_ARCANE_CHARGES",
            renderMode = SIGNED_CONTINUOUS, currentMax = 5 }).GetResolvedVisibleMax()
        t.CP.visible, t.CP.renderMode = true, SIGNED_CONTINUOUS
        local lentFrequent = t.ShouldUseFrequentPower()
        t.CP.visible = false
        CPK.MODE.SIGNED_CONTINUOUS = nil
        Check(where, lentMax == 5,
            "the signed visible-max term ran on Mainline, so it is not gated on the Classic clients")
        Check(where, lentFrequent == false,
            "the signed frequent-power term ran on Mainline, so it is not gated on the Classic clients")
    end

    -- Neither C_Spell entry point below has a Blizzard call site that a Classic
    -- game type loads (Blizzard_CooldownViewer is AllowLoadGameType standard,
    -- Blizzard_PersonalResourceDisplay is mainline, and DemonHunterSoulFragmentsBar
    -- is in the Mainline Blizzard_UnitFrame TOC), so the Classic build carries a
    -- net for both and Mainline must still call C_Spell directly.
    local aura = BuildAuraMode(t)
    local nets = {
        { "the Soul Cleave cast count", function() return aura.UpdateSegmented("SOUL_FRAGMENTS_VENG", 6) end },
        { "the Dark Heart maximum", aura.UpdateSingle },
        { "the Maelstrom Weapon visible maximum", BuildRuntime(t, { visible = true,
            powerType = "MAELSTROM_WEAPON", renderMode = CPK.MODE.AURA_SEGMENTED,
            currentMax = 3 }).GetResolvedVisibleMax },
        -- Refresh.ResolveMaxPower runs first on the activation path
        -- (Refresh.ShowClassPower calls it before any core refresh), so the core
        -- net above is only ever reached on a client this one survives too.
        { "the Maelstrom Weapon activation maximum",
            function() return t.ResolveMaxPower("MAELSTROM_WEAPON", CPK.MODE.AURA_SEGMENTED) end },
    }
    for index = 1, #nets do
        local ok, failure = pcall(nets[index][2])
        if isClassic then
            Check(where, ok, nets[index][1] .. " has no net on a client without the C_Spell entry "
                .. "point: " .. tostring(failure))
        else
            Check(where, not ok, nets[index][1] .. " stopped calling C_Spell directly on Mainline")
        end
    end

    if client.classic then
        Check(where, t.suppressed == "true,false",
            "Blizzard class resource suppression calls were [" .. t.suppressed .. "], expected [true,false]")
        Check(where, CPK.MODE.SIGNED_CONTINUOUS == SIGNED_CONTINUOUS, "signed Eclipse mode id is " .. tostring(CPK.MODE.SIGNED_CONTINUOUS))
        Check(where, CPK.SPELL.MISTS_ARCANE_CHARGE == MISTS_ARCANE_CHARGE, "Arcane Charge aura id missing")
        local arcane = K.MISTS_ARCANE_CHARGES
        Check(where, arcane and arcane.AURA_ID == MISTS_ARCANE_CHARGE and arcane.MAX_STACKS == 4, "Arcane Charges data missing")
        for name, id in pairs(CLASSIC_POWER) do
            Check(where, K.PT[name] == id, "power id " .. name .. " is " .. tostring(K.PT[name]))
        end
        for key, token in pairs(CLASSIC_TOKENS) do
            Check(where, K.POWER_TYPE_TOKENS[key] == token, "power token " .. tostring(key) .. " is " .. tostring(K.POWER_TYPE_TOKENS[key]))
        end
        local profile = t.profiles[SIGNED_CONTINUOUS]
        Check(where, profile and profile.power == true and profile.maxPower == false and profile.aura == false,
            "signed Eclipse mode lost its event profile")
        Check(where, type(signedUpdate) == "function", "the continuous mode builder has no signed updater")
        Check(where, type(t.modeUpdate[SIGNED_CONTINUOUS]) == "function", "the dispatch table has no signed updater")
        Check(where, t.modeUpdate[SIGNED_CONTINUOUS] == t.CP.UpdateSignedContinuous, "signed updater differs from the builder's")
        local watched = {}
        for spellID in pairs(t.CPAuras.watched) do watched[#watched + 1] = spellID end
        Check(where, #watched == 1 and watched[1] == MISTS_ARCANE_CHARGE,
            "Classic watches " .. #watched .. " auras; only Arcane Charges is a Classic aura resource")
        -- Arcane Charges owns its aura updates: an incremental one names the
        -- charge aura, and the fallback refreshes that one aura, reporting no
        -- change while it stays absent instead of rebuilding every time.
        Check(where, t.CPAuras.ActiveSpellKind("MISTS_ARCANE_CHARGES", CPK.MODE.AURA_SEGMENTED, MISTS_ARCANE_CHARGE) == "stacks",
            "the Arcane Charge aura is not an active resource aura")
        Check(where, t.CPAuras.ActiveSpellKind("MISTS_ARCANE_CHARGES", CPK.MODE.AURA_SEGMENTED, 12345) == nil,
            "an unrelated aura counted as Arcane Charges")
        Check(where, t.CPAuras.RefreshActive("MISTS_ARCANE_CHARGES", CPK.MODE.AURA_SEGMENTED) == false,
            "the Arcane Charges fallback rebuilt instead of refreshing its one aura")
        Check(where, _G.MSUF_CP_CORE_BUILDERS.EBON_MIGHT == nil, "a Classic TOC loaded the Retail Ebon Might builder")
        Check(where, t.CP.SetEbonSensorActive(true) == false, "the Classic Ebon sensor hook must stay inert")
        Check(where, type(t.CP.ApplyEbonTextStyle) == "function", "the Classic Ebon text hook is missing")
        Check(where, t.CP.RefreshEbonStyle == nil, "Classic gained an Ebon style refresh")
    else
        Check(where, t.suppressed == "", "Mainline drove the Classic Blizzard frame suppression: [" .. t.suppressed .. "]")
        Check(where, CPK.MODE.SIGNED_CONTINUOUS == nil, "the Classic signed Eclipse mode leaked into Mainline")
        Check(where, CPK.SPELL.MISTS_ARCANE_CHARGE == nil and K.MISTS_ARCANE_CHARGES == nil, "Mists Arcane Charges leaked into Mainline")
        for name in pairs(CLASSIC_POWER) do
            Check(where, K.PT[name] == nil, "Classic power id " .. name .. " leaked into Mainline")
        end
        for key in pairs(CLASSIC_TOKENS) do
            Check(where, K.POWER_TYPE_TOKENS[key] == nil, "Classic power token " .. tostring(key) .. " leaked into Mainline")
        end
        Check(where, t.profiles[SIGNED_CONTINUOUS] == nil, "a Classic mode event profile leaked into Mainline")
        Check(where, signedUpdate == nil, "the continuous mode builder built the Classic signed updater")
        Check(where, t.modeUpdate[SIGNED_CONTINUOUS] == nil and t.CP.UpdateSignedContinuous == nil,
            "the Classic signed updater leaked into the Mainline dispatch table")
        Check(where, t.CPAuras.watched[MISTS_ARCANE_CHARGE] == nil, "Mainline watches the Mists Arcane Charge aura")
        Check(where, t.CPAuras.ActiveSpellKind("MISTS_ARCANE_CHARGES", CPK.MODE.AURA_SEGMENTED, MISTS_ARCANE_CHARGE) == nil,
            "the Classic Arcane Charges aura rule leaked into Mainline")
        Check(where, t.CPAuras.watched[CPK.SPELL.MAELSTROM_WEAPON] == true, "Mainline lost its Retail aura watch set")
        Check(where, type(_G.MSUF_CP_CORE_BUILDERS.EBON_MIGHT) == "function", "Mainline lost the Ebon Might builder")
        Check(where, type(t.CP.RefreshEbonStyle) == "function", "Mainline Ebon hooks were replaced")
    end
end

local failures = {}
for _, client in ipairs(CLIENTS) do
    local ok, err = pcall(Run, client)
    if not ok then failures[#failures + 1] = tostring(err) end
end
if #failures > 0 then
    for index = 1, #failures do io.stderr:write("FAIL " .. failures[index] .. "\n") end
    os.exit(1)
end
print(string.format("PASS ClassPower Classic hunks: present on the Classic clients, absent on Mainline (%d clients)", #CLIENTS))
