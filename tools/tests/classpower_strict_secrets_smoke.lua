-- classpower_strict_secrets_smoke.lua <repoRoot>
--
-- Every ClassPower mode under client-strict secrets. On Midnight (and WoW
-- Forever) each source a class resource reads can arrive secret (Blizzard
-- UnitDocumentation.lua and friends): UnitPower, UnitPartialPower and
-- GetUnitChargedPowerPoints (SecretWhenUnitPowerRestricted), UnitPowerMax
-- (SecretWhenUnitPowerMaxRestricted), UnitStagger (ConditionalSecret),
-- UnitHealth, UnitHealthPercent (SecretReturns), UnitHealthMax
-- (SecretWhenUnitHealthMaxRestricted), GetPowerRegenForPowerType
-- (SecretWhenUnitStatsRestricted), the player aura getters and their fields
-- (SecretWhenUnitAuraRestricted), C_Spell.GetSpellCastCount
-- (SecretWhenCooldownsRestricted), C_Spell.GetSpellMaxCumulativeAuraApplications
-- (SecretWhenUnitAuraRestricted), the target combo points on Forever, and the
-- UNIT_AURA payload itself.
--
-- Each mode is started plain, then every one of those sources turns secret
-- and the mode is driven through its events, a full refresh, a colour edit, a
-- relayout, combat edges, timers and OnUpdate ticks; a second pass starts the
-- mode with every source already secret. Secrets come from
-- tools/tests/classpower_secrets.lua: type() answers the secret's kind, every
-- operation raises, and a line hook over every ClassPower file the TOC loads
-- records == / ~= / not on a local that holds a secret. A mode passes when
-- nothing raised and no line was recorded.
--
-- Runs the real ClassPower stack (tools/tests/classpower_world.lua).
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(repo .. "/tools/tests/classpower_world.lua"))()
local Secrets = assert(loadfile(repo .. "/tools/tests/classpower_secrets.lua"))()
local PT = World.PT

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

--- Every ClassPower file of the Mainline TOC (Forever reads the same TOC).
local function WatchedFiles()
    local file = assert(io.open(repo .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc", "rb"))
    local raw = file:read("*a")
    file:close()
    local paths = {}
    for line in raw:gmatch("[^\r\n]+") do
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:find("ClassPower", 1, true) then
            paths[#paths + 1] = repo .. "/MidnightSimpleUnitFrames/" .. entry:gsub("\\", "/")
        end
    end
    return paths
end
local WATCHED = WatchedFiles()

local SPELL = {
    MAELSTROM_WEAPON = 344179, MAELSTROM_WEAPON_TALENT = 187880, ICICLES = 205473,
    VOID_METAMORPHOSIS = 1217607, SILENCE_THE_WHISPERS = 1227702, DARK_HEART = 1225789,
    SOLAR_ECLIPSE = 1233346, EBON_MIGHT = 395296, WHIRLWIND = 85739,
}

--- Wraps the world's client APIs (classpower_world.lua InstallClient) so that
--- every secret-capable source answers a fresh secret while strict.on is true
--- (only the sources named in strict.only, when a case lists them: one
--- restriction can apply without the others, e.g. stats without power).
--- Called from beforeLoad: the addon files capture these globals at load.
local function InstallSecretSources(env, S, strict)
    Secrets.Install()
    local function Secret(kind) return Secrets.New(kind or "number") end
    local plainCanAccess = canaccesstable
    canaccesstable = function(value)
        if Secrets.IsSecret(value) then return false end
        return plainCanAccess(value)
    end
    local function On(source)
        return strict.on and (strict.only == nil or strict.only[source] == true)
    end
    --- secretValue(plain, ...) answers while the source is secret.
    local function Wrap(name, secretValue, source)
        local plain = _G[name]
        if type(plain) ~= "function" then return end
        source = source or name
        _G[name] = function(...)
            if On(source) then return secretValue(plain, ...) end
            return plain(...)
        end
    end
    Wrap("UnitPower", function() return Secret() end, "power")
    Wrap("UnitPowerMax", function(plain, ...)
        if strict.max then return Secret() end
        return plain(...)
    end, "power")
    Wrap("UnitPartialPower", function() return Secret() end, "power")
    Wrap("GetUnitChargedPowerPoints", function() return Secret("table") end, "power")
    Wrap("GetComboPoints", function() return Secret() end, "power")
    Wrap("GetPowerRegenForPowerType", function() return Secret(), Secret() end, "stats")
    Wrap("UnitStagger", function() return Secret() end, "health")
    Wrap("UnitHealth", function() return Secret() end, "health")
    Wrap("UnitHealthMax", function() return Secret() end, "healthMax")
    _G.UnitHealthPercent = function() return On("health") and Secret() or 50 end
    _G.UnitPowerPercent = function(_, _, _, curve)
        if curve then return { GetRGB = function() return 1, 1, 1 end } end
        return On("power") and Secret() or 40
    end
    _G.UnitGetTotalAbsorbs = function() return On("health") and Secret() or 0 end
    _G.UnitCastingInfo = function()
        if On("cast") then return nil, nil, nil, nil, nil, nil, nil, nil, Secret() end
        return nil, nil, nil, nil, nil, nil, nil, nil, 116
    end
    _G.UnitChannelInfo = function() return nil end

    -- Aura data: a restricted aura keeps its table but every field the
    -- resources read is secret.
    local auras = C_UnitAuras
    local plainAura = auras.GetPlayerAuraBySpellID
    local function SecretAura(spellID)
        return {
            spellId = strict.secretIDs and Secret() or spellID,
            auraInstanceID = strict.secretIDs and Secret() or 11,
            applications = Secret(), charges = Secret(),
            expirationTime = Secret(), duration = Secret(),
        }
    end
    auras.GetPlayerAuraBySpellID = function(spellID)
        if strict.auraSpells and not strict.auraSpells[spellID] then return nil end
        if On("aura") then return SecretAura(spellID) end
        return plainAura(spellID)
    end
    auras.GetUnitAuraBySpellID = function(_, spellID) return auras.GetPlayerAuraBySpellID(spellID) end
    auras.GetAuraDataByAuraInstanceID = function(_, auraInstanceID)
        if On("aura") then return SecretAura(SPELL.MAELSTROM_WEAPON) end
        return nil
    end
    auras.GetUnitAuras = function()
        if On("aura") then return { SecretAura(SPELL.MAELSTROM_WEAPON) } end
        return {}
    end
    auras.GetAuraApplicationDisplayCount = function() return On("aura") and Secret("string") or "" end
    C_Spell.GetSpellCastCount = function() return On("cooldown") and Secret() or 4 end
    C_Spell.GetSpellMaxCumulativeAuraApplications = function() return On("aura") and Secret() or 10 end
    C_Spell.GetSpellPowerCost = function()
        return { { type = 0, cost = On("cast") and Secret() or 120 } }
    end

    -- FontString:SetFormattedText takes secret arguments natively; the shared
    -- stub formats in Lua, which a secret cannot pass through.
    env.Methods.SetFormattedText = function(self, format, ...)
        self.formatted = { format, ... }
        self.text = "<formatted>"
    end
end

--- The events a mode can see, in a client-plausible order, each delivered to
--- every frame that registered it (the controller, Balance, Ironfur, Ebon
--- Might, alt mana, the second Player HP bar).
local function Drive(t)
    local env = t.env
    local secretPayload = { isFullUpdate = Secrets.New("boolean") }
    local addedPayload = { addedAuras = { { spellId = SPELL.MAELSTROM_WEAPON, auraInstanceID = 11,
        applications = Secrets.New(), expirationTime = Secrets.New() } },
        updatedAuraInstanceIDs = { 11 }, removedAuraInstanceIDs = { 12 } }
    local function Fire(event, ...)
        env:FireEvent(event, ...)
        env:RunTimers()
    end
    local token = t.CP.powerToken or "COMBO_POINTS"
    -- Target-owned combo points arrive with the Energy token too (Forever),
    -- first while the bar still shows the plain points it painted.
    Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
    Fire("UNIT_POWER_UPDATE", "player", token)
    Fire("UNIT_POWER_FREQUENT", "player", token)
    Fire("UNIT_POWER_UPDATE", "player", "MANA")
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Fire("UNIT_MAXPOWER", "player", token)
    Fire("UNIT_MAXPOWER", "player", "MANA")
    Fire("UNIT_POWER_POINT_CHARGE", "player")
    Fire("UNIT_AURA", "player", { isFullUpdate = true })
    Fire("UNIT_AURA", "player", secretPayload)
    Fire("UNIT_AURA", "player", addedPayload)
    Fire("UNIT_AURA", "player", nil)
    Fire("UNIT_HEALTH", "player")
    Fire("UNIT_MAXHEALTH", "player")
    Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    Fire("RUNE_POWER_UPDATE", 1, true)
    Fire("UNIT_SPELLCAST_START", "player", "Cast-1", t.castSpell or 686)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", t.castSpell or 686)
    Fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", t.castSpell or 686)
    Fire("PLAYER_TARGET_CHANGED")
    env:EnterCombat()
    env:RunTimers()
    Fire("UNIT_POWER_UPDATE", "player", token)
    Fire("UNIT_DISPLAYPOWER", "player")
    env:LeaveCombat()
    env:RunTimers()
    t.CP.RefreshPublic()
    env:RunTimers()
    if _G.MSUF_ClassPower_InvalidateColors then _G.MSUF_ClassPower_InvalidateColors() end
    env:RunTimers()
    if _G.MSUF_ClassPower_RefreshLayout then _G.MSUF_ClassPower_RefreshLayout() end
    env:RunTimers()
    env:AdvanceTime(0.5)
    for index = 1, #env.frames do
        local frame = env.frames[index]
        local onUpdate = frame.scripts and frame.scripts.OnUpdate
        if onUpdate then onUpdate(frame, 0.5) end
    end
    env:RunTimers()
    Fire("UNIT_POWER_UPDATE", "player", token)
end

local EXTRA_GLOBALS = { "Enum", "C_DurationUtil", "C_CurveUtil", "CreateColor", "hooksecurefunc", "UnitSpellHaste" }

local function Run(case, coldSecret)
    for index = 1, #EXTRA_GLOBALS do _G[EXTRA_GLOBALS[index]] = nil end
    local strict = { on = coldSecret == true, max = case.secretMax == true, secretIDs = case.secretIDs == true,
        only = case.only, auraSpells = case.auraSpells }
    local stop
    local ok, err = pcall(function()
        local t = World.Start(repo, "Mainline", case.class, case.spec, case.primary, case.bars, {
            beforeLoad = function(env, S)
                if case.forever then MSUF_NS.Client.IsForever = true end
                if case.setup then case.setup(env, S) end
                InstallSecretSources(env, S, strict)
                if coldSecret then stop = Secrets.Watch(WATCHED) end
            end,
        })
        if case.route then
            Check(case.route(t.CP), case.name .. ": the mode did not route (" .. tostring(t.CP.powerType) .. ")")
        end
        if not coldSecret then
            strict.on = true
            stop = Secrets.Watch(WATCHED)
        end
        t.castSpell = case.cast
        Drive(t)
    end)
    local violations = stop and stop() or {}
    if stop == nil then debug.sethook() end
    local label = case.name .. (coldSecret and " (secret from the start)" or " (secret after a plain start)")
    Check(ok, label .. " raised: " .. tostring(err))
    Check(#violations == 0, label .. " compared or tested a secret:\n    " .. table.concat(violations, "\n    "))
end

--- The unit-frame helpers the second Player HP bar reads from the engine.
local function PlayerHPClient()
    _G.MSUF_UF_NormalizePlayerHPShape = function(value)
        value = value and tostring(value):upper() or "BAR"
        return value ~= "" and value or "BAR"
    end
    _G.MSUF_UF_ShapeOutlineAlpha = function() return 1 end
    _G.CurveConstants = { ScaleTo100 = { curve = "ScaleTo100" } }
end

--- The client surface the optional resource helpers (resource marks, mana
--- extras, Ignore Pain and the Arcane window) reach for: the Player power bar
--- as their host, hooksecurefunc, colour curves and duration objects.
local function ExtrasClient(env)
    local player = MSUF_NS.UF.GetFrame("player")
    local powerBar = env:CreateFrame("StatusBar", nil, player)
    powerBar.shown = true
    powerBar._msufPowerType, powerBar._msufPowerDisplayMana = 0, true
    player.targetPowerBar = powerBar
    _G.hooksecurefunc = function(target, method, hook)
        if type(target) == "string" then target, method, hook = _G, target, method end
        local original = target[method]
        target[method] = function(...)
            local a, b, c, d = original(...)
            hook(...)
            return a, b, c, d
        end
    end
    local function Color(r, g, b, a)
        local color = { r = r, g = g, b = b, a = a }
        function color.SetRGBA(self, nr, ng, nb, na) self.r, self.g, self.b, self.a = nr, ng, nb, na end
        function color.GetRGB(self) return self.r, self.g, self.b end
        return color
    end
    _G.CreateColor = Color
    _G.C_CurveUtil = { CreateColorCurve = function()
        return {
            SetType = function() end, ClearPoints = function() end, AddPoint = function() end,
            EvaluateUnpacked = function() return 1, 1, 1 end,
        }
    end }
    _G.Enum = _G.Enum or {}
    Enum.LuaCurveType = { Step = 1 }
    Enum.StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }
    Enum.StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }
    _G.C_DurationUtil = { CreateDuration = function()
        return { SetTimeFromStart = function() end, SetTimeFromEnd = function() end, Reset = function() end }
    end }
    env.Methods.SetTimerDuration = function(self, duration) self.timerDuration = duration end
    _G.UnitSpellHaste = function() return 10 end
end

local MARKS = {
    { target = "CLASS", mode = "ABSOLUTE", value = 3, threshold = true, color = { 1, 0, 0 } },
    { target = "PLAYER", mode = "PERCENT", value = 50, threshold = true, direction = "BELOW", color = { 0, 1, 0 } },
    { target = "ALTMANA", mode = "PERCENT", value = 25, color = { 0, 0, 1 } },
}

local function Is(value) return function(CP) return CP.visible and CP.powerType == value end end

local CASES = {
    { name = "Rogue combo points (segmented, charged)", class = "ROGUE", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, route = Is(PT.COMBO) },
    { name = "Rogue combo points with a secret maximum", class = "ROGUE", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true, classPowerHideWhenFull = true }, secretMax = true },
    { name = "Feral combo points", class = "DRUID", spec = 2, primary = PT.ENERGY,
        bars = { classPowerShowText = true, classPowerHideWhenEmpty = true }, route = Is(PT.COMBO) },
    { name = "Retribution holy power", class = "PALADIN", spec = 3, primary = PT.MANA,
        bars = { classPowerShowText = true, classPowerTextMode = "CURMAX" }, route = Is(9) },
    { name = "Affliction soul shards", class = "WARLOCK", spec = 1, primary = PT.MANA, cast = 686,
        bars = { classPowerShowText = true }, route = Is(PT.SHARDS) },
    { name = "Destruction soul shards (fractional)", class = "WARLOCK", spec = 3, primary = PT.MANA,
        cast = 29722, bars = { classPowerShowText = true }, route = Is(PT.SHARDS) },
    { name = "Devastation essence", class = "EVOKER", spec = 1, primary = PT.MANA,
        bars = { classPowerShowText = true }, route = Is(PT.ESSENCE) },
    { name = "Augmentation essence and Ebon Might", class = "EVOKER", spec = 3, primary = PT.MANA,
        bars = { classPowerShowText = true }, route = Is(PT.ESSENCE) },
    { name = "Arcane charges", class = "MAGE", spec = 1, primary = PT.MANA,
        bars = { classPowerShowText = true }, route = Is(16) },
    { name = "Frost icicles (aura segmented)", class = "MAGE", spec = 3, primary = PT.MANA,
        bars = { classPowerShowText = true }, route = Is("ICICLES") },
    { name = "Windwalker chi", class = "MONK", spec = 3, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, route = Is(12) },
    { name = "Brewmaster stagger", class = "MONK", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, route = Is(-1) },
    { name = "Unholy runes", class = "DEATHKNIGHT", spec = 3, primary = 6,
        bars = { classPowerShowText = true }, route = Is(5) },
    { name = "Enhancement Maelstrom Weapon", class = "SHAMAN", spec = 2, primary = PT.MANA,
        bars = { classPowerShowText = true }, route = Is("MAELSTROM_WEAPON") },
    { name = "Enhancement Maelstrom Weapon with secret aura IDs", class = "SHAMAN", spec = 2,
        primary = PT.MANA, bars = { classPowerShowText = true }, secretIDs = true },
    { name = "Elemental Maelstrom (continuous)", class = "SHAMAN", spec = 1, primary = PT.MANA,
        bars = { classPowerShowText = true, showEleMaelstrom = true }, route = Is(11) },
    { name = "Shadow Insanity (continuous) and alt mana", class = "PRIEST", spec = 3, primary = PT.MANA,
        bars = { classPowerShowText = true, showShadowMana = true, showAltMana = true }, route = Is(13) },
    { name = "Devourer soul fragments (aura single)", class = "DEMONHUNTER", spec = 3, primary = 17,
        bars = { classPowerShowText = true }, route = Is("SOUL_FRAGMENTS") },
    { name = "Devourer Dark Heart outside Void Metamorphosis", class = "DEMONHUNTER", spec = 3, primary = 17,
        bars = { classPowerShowText = true }, auraSpells = { [1225789] = true } },
    { name = "Vengeance soul fragments", class = "DEMONHUNTER", spec = 2, primary = 17,
        bars = { classPowerShowText = true }, route = Is("SOUL_FRAGMENTS_VENG") },
    { name = "Fury Whirlwind (native aura)", class = "WARRIOR", spec = 2, primary = PT.RAGE,
        bars = { classPowerShowText = true }, route = Is("WHIRLWIND") },
    { name = "Guardian Ironfur", class = "DRUID", spec = 3, primary = PT.RAGE, cast = 192081,
        bars = { classPowerShowText = true, showGuardianIronfur = true }, route = Is("IRONFUR") },
    { name = "Balance eclipse, prediction and alt mana", class = "DRUID", spec = 1, primary = 8,
        bars = { showAltMana = true }, cast = 190984, setup = ExtrasClient },
    { name = "Balance eclipse with secret aura IDs", class = "DRUID", spec = 1, primary = 8,
        bars = { showAltMana = true }, cast = 194153, secretIDs = true, setup = ExtrasClient },
    { name = "Survival Tip of the Spear", class = "HUNTER", spec = 3, primary = 2, cast = 259489,
        bars = { classPowerShowText = true }, route = Is("TIP_OF_THE_SPEAR") },
    { name = "Second Player HP bar", class = "WARRIOR", spec = 1, primary = PT.RAGE, setup = PlayerHPClient,
        bars = { playerHPBarEnabled = true, playerHPBarUsePlayerText = false,
            playerHPBarTextLeft = "CURRENT", playerHPBarTextCenter = "PERCENT",
            playerHPBarTextRight = "CURPERCENT" } },
    { name = "WoW Forever target combo points", class = "ROGUE", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, forever = true, route = Is(PT.COMBO) },

    -- One restriction without the others.
    { name = "Devastation essence, stats restricted only", class = "EVOKER", spec = 1, primary = PT.MANA,
        bars = { classPowerShowText = true }, only = { stats = true }, setup = ExtrasClient },
    { name = "Devastation essence, power restricted only", class = "EVOKER", spec = 1, primary = PT.MANA,
        bars = { classPowerShowText = true }, only = { power = true }, setup = ExtrasClient },
    { name = "Brewmaster stagger, maximum health restricted only", class = "MONK", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, only = { healthMax = true } },
    { name = "Brewmaster stagger, stagger restricted only", class = "MONK", spec = 1, primary = PT.ENERGY,
        bars = { classPowerShowText = true }, only = { health = true } },
    { name = "Enhancement Maelstrom Weapon, aura fields only", class = "SHAMAN", spec = 2, primary = PT.MANA,
        bars = { classPowerShowText = true, classPowerTextMode = "CURMAX" }, only = { aura = true } },
    { name = "Vengeance soul fragments, cooldowns restricted only", class = "DEMONHUNTER", spec = 2,
        primary = 17, bars = { classPowerShowText = true }, only = { cooldown = true } },
    { name = "Unholy runes with native durations", class = "DEATHKNIGHT", spec = 3, primary = 6,
        bars = { classPowerShowText = true, runeShowTime = true }, setup = ExtrasClient },

    -- The optional resource helpers.
    { name = "Resource marks on class power, Player power and alt mana", class = "ROGUE", spec = 1,
        primary = PT.ENERGY, setup = ExtrasClient, bars = { classPowerShowText = true, resourceMarks = MARKS } },
    { name = "Resource marks on Shadow Insanity and alt mana", class = "PRIEST", spec = 3, primary = PT.MANA,
        setup = ExtrasClient, bars = { showShadowMana = true, showAltMana = true, resourceMarks = MARKS } },
    { name = "Resource marks on WoW Forever target combo points", class = "ROGUE", spec = 1,
        primary = PT.ENERGY, forever = true, setup = ExtrasClient,
        bars = { classPowerShowText = true, resourceMarks = MARKS } },
    { name = "Mana extras on WoW Forever", class = "MAGE", spec = 1, primary = PT.MANA, forever = true,
        cast = 116, setup = ExtrasClient,
        bars = { manaRegenPause = true, manaGainPulse = true, manaUpcomingCost = true } },
    { name = "Upcoming mana cost on Midnight", class = "MAGE", spec = 1, primary = PT.MANA, cast = 116,
        setup = ExtrasClient, bars = { manaUpcomingCost = true, classPowerShowText = true } },
    { name = "Ignore Pain", class = "WARRIOR", spec = 3, primary = PT.RAGE, setup = ExtrasClient,
        bars = { showIgnorePain = true } },
    { name = "Arcane window", class = "MAGE", spec = 1, primary = PT.MANA, setup = ExtrasClient,
        bars = { showArcaneWindow = true, classPowerShowText = true } },
}

for _, case in ipairs(CASES) do
    Run(case, false)
    Run(case, true)
end

if #failures > 0 then
    error("classpower_strict_secrets_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print(("classpower_strict_secrets_smoke: ok (%d modes, plain then secret and secret from the start)"):format(#CASES))
