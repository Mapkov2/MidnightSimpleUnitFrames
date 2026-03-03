-- ============================================================================
-- MSUF_ClassPower.lua — Class Resources + Alt Mana + Stagger
--
-- Features:
--   1. ClassPower (segmented): Combo Points, Holy Power, Soul Shards (incl.
--      fractional for Destruction), Arcane Charges, Chi, Essence.
--   2. DK Runes: individual per-rune cooldown animation + sort order (oUF).
--   3. DH Devourer: Soul Fragments (aura-based, normalized 0-1, dual color).
--   4. Enh Shaman: Maelstrom Weapon stacks (aura-based segments).
--   5. Vehicle: auto-switch to combo points in vehicle UI.
--   6. AltMana: extra Mana bar for dual-resource specs.
--   7. Stagger: Brewmaster Monk stagger bar (3-color threshold).
--
-- Architecture:
--   - Self-contained: own event frame, own DB defaults, own layout.
--   - Independent overlay (Unhalted approach): no HP bar reservation.
--   - Render modes: each class/spec resolves to a render mode at FullRefresh.
--     Hot-path dispatch is a single mode check — zero branching for inactive.
--   - Secret-safe: raw UnitPower/UnitPowerMax (2 args), nil-guarded.
--   - Max performance: event-driven only (zero polling except DK rune OnUpdate
--     which runs only on recharging runes, ~1-3 max simultaneous).
-- ============================================================================

-- Guard: only load once.
if _G.__MSUF_ClassPower_Loaded then return end
_G.__MSUF_ClassPower_Loaded = true

-- ============================================================================
-- Perf locals (eliminate global lookups in hot paths)
-- ============================================================================
local type, tonumber, pairs, select = type, tonumber, pairs, select
local math_floor, math_max, math_ceil = math.floor, math.max, math.ceil
local math_min = math.min
local string_format = string.format
local pairs = pairs
local table_sort = table.sort
local CreateFrame = CreateFrame
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitPowerPercent = UnitPowerPercent
local UnitPowerDisplayMod = UnitPowerDisplayMod
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitStagger = UnitStagger
local UnitHealthMax = UnitHealthMax
local UnitHasVehicleUI = UnitHasVehicleUI
local GetShapeshiftFormID = GetShapeshiftFormID
local GetRuneCooldown = GetRuneCooldown
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local CurveScale100 = (CurveConstants and CurveConstants.ScaleTo100) or true

-- Aura API (12.0)
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook

-- Secret-value guard (12.0 Midnight)
local _issecretvalue = _G.issecretvalue
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

-- Spec API (12.0: C_SpecializationInfo preferred, fallback to global)
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization

-- Player class (resolved once, never changes)
local _, PLAYER_CLASS = UnitClass("player")

-- ============================================================================
-- Render modes (resolved per FullRefresh, dispatch in hot paths)
-- ============================================================================
local MODE_NONE            = 0  -- no class resource active
local MODE_SEGMENTED       = 1  -- standard: filled/empty per segment (CP, HP, Chi, etc.)
local MODE_FRACTIONAL      = 2  -- Destruction Warlock: partial fill on current shard
local MODE_RUNE_CD         = 3  -- DK: per-rune cooldown animation with sort
local MODE_AURA_SEGMENTED  = 4  -- Enh Shaman: aura-stack count as segments
local MODE_AURA_SINGLE     = 5  -- DH Devourer: normalized 0-1 single bar
local MODE_CONTINUOUS      = 6  -- Ele Shaman Maelstrom: continuous bar (opt-in)
local MODE_TIMER_BAR       = 8  -- Ebon Might: aura countdown bar with OnUpdate
local MODE_STAGGER         = 9  -- Brewmaster Monk: stagger bar (3-color threshold)

-- ============================================================================
-- Spec constants (sourced from Blizzard_FrameXMLBase/Constants.lua)
-- ============================================================================
local SPEC_DH_DEVOURER       = _G.SPEC_DEMONHUNTER_DEVOURER or 3
local SPEC_MAGE_ARCANE        = _G.SPEC_MAGE_ARCANE or 1
local SPEC_MONK_WINDWALKER    = _G.SPEC_MONK_WINDWALKER or 3
local SPEC_MONK_BREWMASTER    = _G.SPEC_MONK_BREWMASTER or 1
local SPEC_SHAMAN_ENHANCEMENT = 2
local SPEC_SHAMAN_ELEMENTAL   = 1
local SPEC_WARLOCK_DESTRUCTION = _G.SPEC_WARLOCK_DESTRUCTION or 3
local SPEC_DRUID_BALANCE      = 1
local SPEC_DH_VENGEANCE       = _G.SPEC_DEMONHUNTER_VENGEANCE or 2
local SPEC_PRIEST_SHADOW      = 3
local SPEC_HUNTER_SURVIVAL    = 3
local SPEC_EVOKER_AUG         = 3

-- ============================================================================
-- Spell IDs (oUF-sourced: aura-based class powers)
-- ============================================================================
local SPELL_DARK_HEART          = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.DARK_HEART_SPELL_ID) or 1225789
local SPELL_SILENCE_THE_WHISPERS = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.SILENCE_THE_WHISPERS_SPELL_ID) or 1227702
local SPELL_VOID_METAMORPHOSIS  = (Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.VOID_METAMORPHOSIS_SPELL_ID) or 1217607
local SPELL_MAELSTROM_WEAPON       = 344179
local SPELL_MAELSTROM_WEAPON_TALENT = 187880
local MW_SPEND_THRESHOLD           = 5  -- stacks 6+ colored differently (spender empowered)

-- Balance Druid: Astral Power prediction + Eclipse tracking (MCR-sourced)
local SPELL_NATURES_BALANCE     = 406890
local SPELL_SOLAR_ECLIPSE       = 1233346
local SPELL_LUNAR_ECLIPSE       = 1233272
local SPELL_CELESTIAL_ALIGNMENT = 194223
local SPELL_ORBITAL_STRIKE_CA   = 383410
local SPELL_INCARNATION_BOOMKIN = 102560
local SPELL_ORBITAL_STRIKE_INC  = 390414
local SPELL_AP_WRATH            = 190984
local SPELL_AP_STARFIRE          = 194153

-- Balance: spellID → base AP generated
local AP_GENERATORS = {
    [190984] = 6,   -- Wrath
    [194153] = 8,   -- Starfire
    [274281] = 10,  -- New Moon
    [274282] = 20,  -- Half Moon
    [274283] = 40,  -- Full Moon
}

-- Balance: Eclipse aura IDs → type for fast lookup
local ECLIPSE_AURAS = {
    [SPELL_SOLAR_ECLIPSE]       = "SOLAR",
    [SPELL_LUNAR_ECLIPSE]       = "LUNAR",
    [SPELL_CELESTIAL_ALIGNMENT] = "CA",
    [SPELL_ORBITAL_STRIKE_CA]   = "CA",
    [SPELL_INCARNATION_BOOMKIN] = "INC",
    [SPELL_ORBITAL_STRIKE_INC]  = "INC",
}

-- Balance: Eclipse bar colors (MCR/Shrom defaults; overridable via Colors menu)
local BAL_CLR_SOLAR = { 0.82, 0.56, 0.25 }  -- #d18f3f
local BAL_CLR_LUNAR = { 0.41, 0.49, 0.82 }  -- #697ed1
local BAL_CLR_CA    = { 0.30, 1.00, 0.43 }  -- #4dff6d (CA / Incarnation)
local BAL_PRED_ALPHA = 0.50                   -- prediction overlay opacity

-- Warlock: per-spec spell → shard delta (positive = generates, negative = spends)
-- Only cast-time spells (UNIT_SPELLCAST_START): channels/instants don't show prediction.
-- Destruction values are fractional display units (1.0 = 1 shard); Demo/Affli are integers.
-- Jay's approach: show predicted post-cast value with "*" suffix during cast.
local WL_SHARD_DELTAS = {
    [1] = {  -- Affliction (integer)
        [686]    =  1,    -- Shadow Bolt: +1
    },
    [2] = {  -- Demonology (integer)
        [686]    =  1,    -- Shadow Bolt: +1
        [264178] =  2,    -- Demonbolt: +2
    },
    [3] = {  -- Destruction (fractional display units)
        [29722]  =  0.2,  -- Incinerate: +0.2
        [116858] = -2.0,  -- Chaos Bolt: −2.0 (spender)
    },
}

-- DH Vengeance: Soul Fragments via C_Spell.GetSpellCastCount (MCR-sourced)
local SPELL_SOUL_CLEAVE = 228477

-- ============================================================================
-- Whirlwind Tracker (Sensei pattern — own event frame, event-driven render)
-- ============================================================================
local _wwRender  -- forward-declared; set after CP_UpdateValues_AuraSegmented exists

local WW = {}
do
    local MAX_STACKS = 4
    local DURATION   = 20
    local CRASHING_THUNDER  = 436707
    local UNHINGED          = 386628
    local GENERATORS = { [190411]=true, [6343]=true, [435222]=true }
    local SPENDERS   = {
        [23881]=true, [85288]=true, [280735]=true, [202168]=true,
        [184367]=true, [335096]=true, [335097]=true, [5308]=true,
    }
    local BLADESTORMS = {
        [50622]=true, [46924]=true, [227847]=true, [184362]=true, [446035]=true,
    }

    local stacks       = 0
    local expiresAt    = nil
    local noConsumeUntil = 0
    local seenCastGUID = {}
    local _expiryTimer = nil  -- pending C_Timer handle for expiry

    WW.MAX_STACKS = MAX_STACKS

    function WW.GetStacks()
        if expiresAt and GetTime() >= expiresAt then
            stacks = 0
            expiresAt = nil
        end
        return stacks
    end

    -- Schedule a one-shot expiry timer (replaces per-frame polling)
    local function ScheduleExpiry()
        if not expiresAt then return end
        local remaining = expiresAt - GetTime()
        if remaining <= 0 then
            stacks = 0
            expiresAt = nil
            if _wwRender then _wwRender() end
            return
        end
        -- Cancel previous timer token by bumping generation counter
        _expiryTimer = (_expiryTimer or 0) + 1
        local myTimer = _expiryTimer
        C_Timer.After(remaining + 0.05, function()
            if myTimer ~= _expiryTimer then return end  -- stale
            if expiresAt and GetTime() >= expiresAt then
                stacks = 0
                expiresAt = nil
                if _wwRender then _wwRender() end
            end
        end)
    end

    -- Warrior-only: own event frame (Sensei pattern)
    if PLAYER_CLASS == "WARRIOR" then
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        f:RegisterEvent("PLAYER_DEAD")
        f:RegisterEvent("PLAYER_ALIVE")
        f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
            if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                stacks = 0
                expiresAt = nil
                seenCastGUID = {}
                if _wwRender then _wwRender() end
                return
            end
            if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end

            local known = C_SpellBook and C_SpellBook.IsSpellKnown

            -- castGUID dedup
            if castGUID and seenCastGUID[castGUID] then return end
            if castGUID then seenCastGUID[castGUID] = true end

            -- Unhinged no-consume window
            if known and known(UNHINGED) and BLADESTORMS[spellID] then
                noConsumeUntil = GetTime() + 2
            end

            -- Generator → max stacks
            if GENERATORS[spellID] then
                if (spellID == 6343 or spellID == 435222) then
                    if not (known and known(CRASHING_THUNDER)) then return end
                end
                stacks = MAX_STACKS
                expiresAt = GetTime() + DURATION
                ScheduleExpiry()
                if _wwRender then _wwRender() end
                return
            end

            -- Spender → consume 1
            if SPENDERS[spellID] then
                if spellID == 23881 and GetTime() < noConsumeUntil then return end
                if stacks > 0 then
                    stacks = stacks - 1
                    if stacks == 0 then expiresAt = nil end
                    if _wwRender then _wwRender() end
                end
            end
        end)
    end
end

-- ============================================================================
-- Balance Druid: Astral Power Prediction + Eclipse Colors on Main Power Bar
-- Self-contained module with own event frame (same pattern as WW tracker).
-- Only active when player is Balance spec AND primary power is Astral Power.
-- ============================================================================
do
    if PLAYER_CLASS == "DRUID" then
        local LUNAR_POWER = (Enum and Enum.PowerType and Enum.PowerType.LunarPower) or 8
        local _active = false  -- true when Balance spec + Astral Power primary
        local _castSpell = nil
        local _predAmt = 0
        local _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
        local _predTex = nil   -- lazy overlay on power bar
        local _eclColor = nil  -- {r,g,b} or nil

        -- Resolve if module should be active (called on spec/form change)
        local function _checkActive()
            local spec = GetSpec and GetSpec()
            if spec ~= 1 then _active = false; return end  -- not Balance
            local pType = UnitPowerType("player")
            if NotSecret(pType) and pType == LUNAR_POWER then
                _active = true
            else
                _active = false
            end
        end

        -- Get player power bar (lazy, may not exist early)
        local function _getPowerBar()
            local pf = _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player)
            return pf and pf.targetPowerBar or nil
        end

        -- Resolve eclipse color override from DB
        local function _resolveEclColor(token)
            local ov = MSUF_DB and MSUF_DB.general and MSUF_DB.general.classPowerColorOverrides
            if type(ov) == "table" then
                local c = token and ov[token]
                if type(c) == "table" then
                    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                        return r, g, b
                    end
                end
            end
            if token == "ECLIPSE_SOLAR" then return BAL_CLR_SOLAR[1], BAL_CLR_SOLAR[2], BAL_CLR_SOLAR[3] end
            if token == "ECLIPSE_LUNAR" then return BAL_CLR_LUNAR[1], BAL_CLR_LUNAR[2], BAL_CLR_LUNAR[3] end
            if token == "ECLIPSE_CA"    then return BAL_CLR_CA[1], BAL_CLR_CA[2], BAL_CLR_CA[3] end
            return nil
        end

        -- Scan eclipse auras → update expiry + bar color
        local function _refreshEclipses()
            local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            if not getAura then return end
            _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
            for auraID, kind in pairs(ECLIPSE_AURAS) do
                local aura = getAura(auraID)
                if aura and aura.expirationTime then
                    local exp = aura.expirationTime
                    if kind == "SOLAR" then _solarExp = exp
                    elseif kind == "LUNAR" then _lunarExp = exp
                    elseif kind == "CA" then _caExp = exp
                    elseif kind == "INC" then _incExp = exp end
                end
            end
            local now = GetTime()
            local inCA  = _caExp > now
            local inInc = _incExp > now
            if inCA or inInc then
                local r, g, b = _resolveEclColor("ECLIPSE_CA")
                _eclColor = r and { r, g, b } or BAL_CLR_CA
            elseif _solarExp > now then
                local r, g, b = _resolveEclColor("ECLIPSE_SOLAR")
                _eclColor = r and { r, g, b } or BAL_CLR_SOLAR
            elseif _lunarExp > now then
                local r, g, b = _resolveEclColor("ECLIPSE_LUNAR")
                _eclColor = r and { r, g, b } or BAL_CLR_LUNAR
            else
                _eclColor = nil
            end
        end

        -- Compute predicted AP for a given spell
        local function _computeAP(spellID)
            if not spellID then return 0 end
            local base = AP_GENERATORS[spellID]
            if not base then return 0 end
            if spellID == SPELL_AP_WRATH or spellID == SPELL_AP_STARFIRE then
                local known = C_SpellBook and C_SpellBook.IsSpellKnown
                if known and known(SPELL_NATURES_BALANCE) then base = base + 2 end
                local now = GetTime()
                local inCA  = _caExp > now
                local inInc = _incExp > now
                local inEcl = false
                if spellID == SPELL_AP_WRATH then
                    inEcl = (_solarExp > now) or inCA or inInc
                else
                    inEcl = (_lunarExp > now) or inCA or inInc
                end
                if inEcl then base = base * 1.4 end
            end
            return base
        end

        -- Resolve prediction overlay color (non-eclipse fallback)
        -- Reads AP_PREDICTION from classPowerColorOverrides, falls back to power bar color
        local function _resolvePredColor()
            local ov = MSUF_DB and MSUF_DB.general and MSUF_DB.general.classPowerColorOverrides
            if type(ov) == "table" then
                local c = ov["AP_PREDICTION"]
                if type(c) == "table" then
                    local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                        return r, g, b
                    end
                end
            end
            -- Fallback: main power bar color
            if _G.MSUF_GetPowerBarColor then
                local r, g, b = _G.MSUF_GetPowerBarColor(LUNAR_POWER, "LUNAR_POWER")
                if type(r) == "number" then return r, g, b end
            end
            return 0.30, 0.52, 0.90  -- MCR default
        end

        -- Apply eclipse color to main power bar
        local function _applyEclipseColor()
            local bar = _getPowerBar()
            if not bar then return end
            if _eclColor then
                bar:SetStatusBarColor(_eclColor[1], _eclColor[2], _eclColor[3], 1)
            end
            -- (when _eclColor is nil, normal ApplyPowerBarVisual color applies
            --  from the next UNIT_POWER_UPDATE cycle — no manual reset needed)
        end

        -- Update prediction overlay on main power bar
        local function _updateOverlay()
            local bar = _getPowerBar()
            if not bar then return end

            -- Lazy-create texture
            if not _predTex then
                local tex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
                local getBarTex = _G.MSUF_GetBarTexture
                tex:SetTexture(getBarTex and getBarTex() or "Interface\\Buttons\\WHITE8x8")
                tex:SetVertexColor(1, 1, 1, BAL_PRED_ALPHA)
                tex:SetHeight(1)
                tex:Hide()
                _predTex = tex
            end

            if _predAmt <= 0 or not _castSpell then
                _predTex:Hide()
                return
            end

            -- mx (UnitPowerMax) is NOT secret — safe for arithmetic
            local mx = UnitPowerMax("player", LUNAR_POWER) or 100
            if mx <= 0 then mx = 100 end
            local predFrac = _predAmt / mx
            if predFrac > 1 then predFrac = 1 end

            local barW = bar:GetWidth()
            local barH = bar:GetHeight()
            if barW <= 0 or barH <= 0 then _predTex:Hide(); return end

            local predW = barW * predFrac
            if predW < 1 then _predTex:Hide(); return end

            -- Eclipse-aware color
            if _eclColor then
                _predTex:SetVertexColor(_eclColor[1], _eclColor[2], _eclColor[3], BAL_PRED_ALPHA)
            else
                local pr, pg, pb = _resolvePredColor()
                _predTex:SetVertexColor(pr, pg, pb, BAL_PRED_ALPHA)
            end

            -- Anchor to fill texture right edge (secret-safe positioning)
            _predTex:ClearAllPoints()
            _predTex:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
            _predTex:SetSize(predW, barH)
            _predTex:Show()
        end

        -- Clean up when deactivating
        local function _cleanup()
            _castSpell = nil
            _predAmt = 0
            _eclColor = nil
            if _predTex then _predTex:Hide() end
        end

        -- Event frame
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        f:RegisterUnitEvent("UNIT_AURA", "player")
        f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        f:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function(_, event, arg1, _, arg3)
            -- Spec/form change → recalculate active state
            if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
            or event == "UPDATE_SHAPESHIFT_FORM"
            or event == "PLAYER_ENTERING_WORLD" then
                _checkActive()
                if _active then
                    _refreshEclipses()
                    _applyEclipseColor()
                else
                    _cleanup()
                end
                return
            end

            if not _active then return end

            -- Spellcast start → compute prediction
            if event == "UNIT_SPELLCAST_START" and arg1 == "player" then
                _castSpell = arg3
                _predAmt = _computeAP(arg3)
                _updateOverlay()
                return
            end

            -- Spellcast end → clear prediction
            if (event == "UNIT_SPELLCAST_STOP"
             or event == "UNIT_SPELLCAST_FAILED"
             or event == "UNIT_SPELLCAST_INTERRUPTED"
             or event == "UNIT_SPELLCAST_SUCCEEDED") and arg1 == "player" then
                _castSpell = nil
                _predAmt = 0
                _updateOverlay()
                return
            end

            -- Aura change → refresh eclipses, recolor bar, recompute prediction
            if event == "UNIT_AURA" and arg1 == "player" then
                _refreshEclipses()
                _applyEclipseColor()
                if _castSpell then
                    _predAmt = _computeAP(_castSpell)
                    _updateOverlay()
                end
                return
            end

            -- Power update → reposition overlay (bar fill changed)
            if event == "UNIT_POWER_UPDATE" and arg1 == "player" then
                if _castSpell then
                    _updateOverlay()
                end
                -- Re-apply eclipse color (ApplyPowerBarVisual may have overwritten it)
                if _eclColor then
                    _applyEclipseColor()
                end
            end
        end)

        -- Global hook: called by MSUF_ClassPower_InvalidateColors when user changes colors
        _G.MSUF_BAL_InvalidateColors = function()
            if not _active then return end
            _refreshEclipses()
            _applyEclipseColor()
            if _castSpell then
                _updateOverlay()
            end
        end
    end
end

-- Hunter Survival: Tip of the Spear (talent 260285)
local TIP_TALENT_ID     = 260285
local TIP_KILL_COMMAND   = 259489
local TIP_TWIN_FANG      = 1272139
local TIP_TAKEDOWN       = 1250646
local TIP_PRIMAL_SURGE   = 1272154
local TIP_MAX_STACKS     = 3
local TIP_DURATION        = 10
local TIP_SPENDERS = {
    [186270]=true, [1262293]=true, [1261193]=true, [1253859]=true,
    [259495]=true, [193265]=true, [1264949]=true, [1262343]=true,
    [265189]=true, [1251592]=true,
}

-- Evoker Augmentation: Ebon Might timer bar (MCR-sourced)
local SPELL_EBON_MIGHT = 395296
local EBON_MIGHT_MAX_DURATION = 20  -- seconds

-- ============================================================================
-- Stagger thresholds (oUF-sourced: Blizzard_UnitFrame)
-- ============================================================================
local STAGGER_YELLOW_TRANSITION = _G.STAGGER_YELLOW_TRANSITION or 0.3
local STAGGER_RED_TRANSITION    = _G.STAGGER_RED_TRANSITION    or 0.6

-- ============================================================================
-- PowerType constants (defensive: Enum.PowerType may not exist pre-load)
-- ============================================================================
local PT = {}
do
    local E = Enum and Enum.PowerType
    PT.Mana          = (E and E.Mana)          or 0
    PT.ComboPoints   = (E and E.ComboPoints)   or 4
    PT.Runes         = (E and E.Runes)         or 5
    PT.HolyPower     = (E and E.HolyPower)     or 9
    PT.SoulShards    = (E and E.SoulShards)     or 7
    PT.ArcaneCharges = (E and E.ArcaneCharges) or 16
    PT.Chi           = (E and E.Chi)            or 12
    PT.Essence       = (E and E.Essence)        or 19
    PT.LunarPower    = (E and E.LunarPower)     or 8
    PT.Energy        = (E and E.Energy)         or 3
    PT.Insanity      = (E and E.Insanity)       or 13
    PT.Maelstrom     = (E and E.Maelstrom)      or 11
end

-- Sentinel power type for Brewmaster stagger (not a real WoW power type).
-- Used only for internal CP system routing; never passed to UnitPower/UnitPowerMax.
local PT_STAGGER = -1

-- ============================================================================
-- DB Defaults (self-contained; runs on every login, no-ops if keys exist)
-- ============================================================================
local function EnsureDefaults()
    if not MSUF_DB then return end
    if not MSUF_DB.bars then MSUF_DB.bars = {} end
    local b = MSUF_DB.bars

    -- ClassPower defaults
    if b.showClassPower       == nil then b.showClassPower       = true  end
    if b.classPowerHeight     == nil then b.classPowerHeight     = 4     end
    if b.classPowerColorByType == nil then b.classPowerColorByType = true end
    if b.classPowerBgAlpha    == nil then b.classPowerBgAlpha    = 0.3   end
    if b.classPowerTickWidth  == nil then b.classPowerTickWidth  = 1     end
    if b.classPowerOutline    == nil then b.classPowerOutline    = 1     end
    if b.classPowerWidth      == nil then b.classPowerWidth      = 0     end
    if b.classPowerWidthMode  == nil then b.classPowerWidthMode  = "player" end
    if b.classPowerOffsetX    == nil then b.classPowerOffsetX    = 0     end
    if b.classPowerOffsetY    == nil then b.classPowerOffsetY    = 0     end
    if b.smoothPowerBar       == nil then b.smoothPowerBar       = false end
    if b.showChargedComboPoints == nil then b.showChargedComboPoints = true end
    if b.classPowerShowText    == nil then b.classPowerShowText    = false end
    if b.classPowerFontSize    == nil then b.classPowerFontSize    = 16    end

    -- AltMana defaults
    if b.showAltMana          == nil then b.showAltMana          = true  end
    if b.altManaHeight        == nil then b.altManaHeight        = 4     end
    if b.altManaOffsetY       == nil then b.altManaOffsetY       = -2    end
    if b.altManaColorR        == nil then b.altManaColorR        = 0.0   end
    if b.altManaColorG        == nil then b.altManaColorG        = 0.0   end
    if b.altManaColorB        == nil then b.altManaColorB        = 0.8   end

    -- Stagger bar defaults (Brewmaster Monk)
    if b.showStagger          == nil then b.showStagger          = true  end
    if b.staggerHeight        == nil then b.staggerHeight        = 4     end
    if b.staggerOffsetY       == nil then b.staggerOffsetY       = -2    end

    -- DK Rune sort order: "asc" = ready first, "desc" = recharging first, nil = natural
    if b.runeSortOrder        == nil then b.runeSortOrder        = "asc" end
    -- DK Runes: show per-rune cooldown time text on the runes (Sensei-style)
    if b.runeShowTime        == nil then b.runeShowTime        = true end

    -- Ele Shaman: Maelstrom Power continuous bar (off by default — niche preference)
    if b.showEleMaelstrom     == nil then b.showEleMaelstrom     = false end
    -- Evoker Aug: Ebon Might timer bar (on by default)
    if b.showEbonMight        == nil then b.showEbonMight        = true  end

    -- Auto-hide: visibility conditions
    if b.classPowerHideOOC       == nil then b.classPowerHideOOC       = false end
    if b.classPowerHideWhenFull  == nil then b.classPowerHideWhenFull  = false end
    if b.classPowerHideWhenEmpty == nil then b.classPowerHideWhenEmpty = false end

    -- Pip alpha (0.0-1.0)
    if b.classPowerFilledAlpha   == nil then b.classPowerFilledAlpha   = 1.0   end
    if b.classPowerEmptyAlpha    == nil then b.classPowerEmptyAlpha    = 0.3   end

    -- Gap between pips (pixels, 0 = no gap — only tick separators)
    if b.classPowerGap           == nil then b.classPowerGap           = 0     end

    -- Fill direction: false = left→right (default), true = right→left
    if b.classPowerFillReverse   == nil then b.classPowerFillReverse   = false end
end

-- ============================================================================
-- Power-type detection (resolved per spec/form change, cached)
-- Returns: powerType, renderMode, isAuraPower
--   powerType:   Enum.PowerType or string token for aura-based
--   renderMode:  MODE_* constant for hot-path dispatch
--   isAuraPower: true if driven by UNIT_AURA instead of UNIT_POWER_UPDATE
-- ============================================================================

-- ClassPower: returns powerType, renderMode, isAuraPower
local function GetClassPowerType()
    -- Vehicle override: always combo points (oUF pattern)
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then
        local hasCP = PlayerVehicleHasComboPoints and PlayerVehicleHasComboPoints()
        if hasCP then
            return PT.ComboPoints, MODE_SEGMENTED, false
        end
        return nil, MODE_NONE, false
    end

    if PLAYER_CLASS == "DEATHKNIGHT" then
        return PT.Runes, MODE_RUNE_CD, false

    elseif PLAYER_CLASS == "ROGUE" then
        return PT.ComboPoints, MODE_SEGMENTED, false

    elseif PLAYER_CLASS == "PALADIN" then
        return PT.HolyPower, MODE_SEGMENTED, false

    elseif PLAYER_CLASS == "WARLOCK" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_WARLOCK_DESTRUCTION then
            return PT.SoulShards, MODE_FRACTIONAL, false
        end
        return PT.SoulShards, MODE_SEGMENTED, false

    elseif PLAYER_CLASS == "EVOKER" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_EVOKER_AUG then
            local b = MSUF_DB and MSUF_DB.bars
            if b and b.showEbonMight then
                return "EBON_MIGHT", MODE_TIMER_BAR, false
            end
        end
        return PT.Essence, MODE_SEGMENTED, false

    elseif PLAYER_CLASS == "MAGE" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_MAGE_ARCANE then return PT.ArcaneCharges, MODE_SEGMENTED, false end

    elseif PLAYER_CLASS == "MONK" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_MONK_WINDWALKER then return PT.Chi, MODE_SEGMENTED, false end
        -- Brewmaster: Stagger as class resource (3-color threshold, CDM-synced).
        -- Energy is primary → main power bar. Stagger → class power overlay.
        if spec == SPEC_MONK_BREWMASTER then
            local bb = MSUF_DB and MSUF_DB.bars
            if not bb or bb.showStagger ~= false then
                return PT_STAGGER, MODE_STAGGER, false
            end
        end

    elseif PLAYER_CLASS == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        -- Cat Form: Combo Points as class power (Energy is main bar)
        if form == 1 then return PT.ComboPoints, MODE_SEGMENTED, false end
        -- Balance/Boomkin: Astral Power is already the main power bar → no class power.
        -- Other forms (Bear etc.): main bar shows Rage/Mana → no secondary resource overlay.

    elseif PLAYER_CLASS == "DEMONHUNTER" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_DH_DEVOURER then
            return "SOUL_FRAGMENTS", MODE_AURA_SINGLE, true
        end
        if spec == SPEC_DH_VENGEANCE then
            return "SOUL_FRAGMENTS_VENG", MODE_AURA_SEGMENTED, true
        end

    elseif PLAYER_CLASS == "SHAMAN" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_SHAMAN_ENHANCEMENT then
            -- Only if talent is known
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(SPELL_MAELSTROM_WEAPON_TALENT) then
                return "MAELSTROM_WEAPON", MODE_AURA_SEGMENTED, true
            end
        end
        if spec == SPEC_SHAMAN_ELEMENTAL then
            local b = MSUF_DB and MSUF_DB.bars
            if b and b.showEleMaelstrom then
                return PT.Maelstrom, MODE_CONTINUOUS, false
            end
        end

    elseif PLAYER_CLASS == "PRIEST" then
        -- Shadow: Insanity is primary resource → already shown in main power bar.
        -- No class power overlay needed (same pattern as Balance Druid Astral Power).

    elseif PLAYER_CLASS == "WARRIOR" then
        -- All Warrior specs use Whirlwind as class resource (Fury, Arms, Prot).
        -- No talent gate: IsSpellKnown(12950) unreliable in 12.0 for passive talents.
        -- If player doesn't have Improved Whirlwind, stacks stay 0 → auto-hide handles it.
        return "WHIRLWIND", MODE_AURA_SEGMENTED, false

    elseif PLAYER_CLASS == "HUNTER" then
        local spec = GetSpec and GetSpec()
        if spec == SPEC_HUNTER_SURVIVAL then
            local known = C_SpellBook and C_SpellBook.IsSpellKnown
            if known and known(TIP_TALENT_ID) then
                return "TIP_OF_THE_SPEAR", MODE_AURA_SEGMENTED, false
            end
        end
    end
    return nil, MODE_NONE, false
end

-- Stagger detection (Brewmaster Monk only)

-- AltMana: returns true if we need a mana bar (primary power != Mana)
local function NeedsAltManaBar()
    -- Ele Shaman: when Maelstrom is in class power, main bar shows Mana → no alt needed
    if _G.MSUF_EleMaelstromActive then return false end
    local pType = UnitPowerType("player")
    -- pType == 0 = Mana primary → no alt bar needed
    if NotSecret(pType) then
        if pType == nil or pType == PT.Mana then return false end
    end
    -- Must actually have a mana pool (Warriors, Rogues, DKs etc. have 0 max mana)
    local maxMana = UnitPowerMax("player", PT.Mana)
    if NotSecret(maxMana) and type(maxMana) == "number" and maxMana <= 0 then
        return false
    end
    -- Non-secret primary + has mana pool → check class/spec heuristic
    if not NotSecret(pType) then
        local SPECS_NEED_ALT = {
            PRIEST  = { [3] = true },           -- Shadow
            SHAMAN  = { [1] = true, [2] = true }, -- Ele, Enh
            DRUID   = { [1] = true, [2] = true, [3] = true }, -- Balance, Feral, Guardian
            PALADIN = { [3] = true },           -- Ret
            MONK    = { [3] = true },           -- WW
        }
        local specs = SPECS_NEED_ALT[PLAYER_CLASS]
        if not specs then return false end
        local si = GetSpec and GetSpec()
        return si and specs[si] or false
    end
    return true
end

-- PowerType → token mapping (for color resolution)
local POWER_TYPE_TOKENS = {
    [PT.ComboPoints]   = "COMBO_POINTS",
    [PT.Runes]         = "RUNES",
    [PT.HolyPower]     = "HOLY_POWER",
    [PT.SoulShards]    = "SOUL_SHARDS",
    [PT.ArcaneCharges] = "ARCANE_CHARGES",
    [PT.Chi]           = "CHI",
    [PT.Essence]       = "ESSENCE",
    [PT.Mana]          = "MANA",
    [PT.LunarPower]    = "ASTRAL_POWER",
    [PT.Insanity]      = "INSANITY",
    [PT.Maelstrom]     = "MAELSTROM",
    -- String-keyed aura-based types (not in Enum.PowerType)
    ["SOUL_FRAGMENTS"]      = "SOUL_FRAGMENTS",
    ["SOUL_FRAGMENTS_VENG"] = "SOUL_FRAGMENTS_VENG",
    ["MAELSTROM_WEAPON"]    = "MAELSTROM",  -- re-use Elemental's color token (oUF pattern)
    ["STAGGER"]             = "STAGGER",
    ["WHIRLWIND"]           = "WHIRLWIND",
    ["TIP_OF_THE_SPEAR"]    = "TIP_OF_THE_SPEAR",
    ["EBON_MIGHT"]          = "EBON_MIGHT",
}

-- ============================================================================
-- Color resolution (uses MSUF's PowerBarColor override system)
-- ============================================================================
local _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
local _cachedColorToken = nil
local _staggerCachedTier = 0  -- Stagger: avoid redundant SetStatusBarColor when tier unchanged

-- Maelstrom Weapon 5+ threshold color (cached independently)
local _mwAbove5R, _mwAbove5G, _mwAbove5B
local _mwAbove5Resolved = false

local function ResolveMWAbove5Color()
    if _mwAbove5Resolved then return _mwAbove5R, _mwAbove5G, _mwAbove5B end
    _mwAbove5Resolved = true
    local ov = MSUF_DB and MSUF_DB.general and MSUF_DB.general.classPowerColorOverrides
    if type(ov) == "table" then
        local c = ov["MAELSTROM_ABOVE_5"]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                _mwAbove5R, _mwAbove5G, _mwAbove5B = r, g, b
                return r, g, b
            end
        end
    end
    _mwAbove5R, _mwAbove5G, _mwAbove5B = 1.00, 0.50, 0.00  -- Sensei orange default
    return _mwAbove5R, _mwAbove5G, _mwAbove5B
end

local function ResolveClassPowerColor(powerType)
    -- Token resolution: numeric powerType → string token, string → use directly
    local token = POWER_TYPE_TOKENS[powerType]
    if not token and type(powerType) == "string" then
        token = powerType  -- already a string token (e.g. "RESOURCE_TEXT", "SOUL_FRAGMENTS")
    end
    if token == _cachedColorToken and _cachedColorToken then
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    _cachedColorToken = token

    -- 1. Custom class-power color override (from Colors panel)
    if MSUF_DB and MSUF_DB.general then
        local ov = MSUF_DB.general.classPowerColorOverrides
        if type(ov) == "table" and token then
            local c = ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
                    return r, g, b
                end
            end
        end
    end

    -- 2. MSUF power bar color override
    if _G.MSUF_GetPowerBarColor and token then
        local r, g, b = _G.MSUF_GetPowerBarColor(powerType, token)
        if type(r) == "number" then
            _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
            return r, g, b
        end
    end

    -- Fallback: Blizzard PowerBarColor
    local pbc = _G.PowerBarColor
    if pbc then
        local c = (token and pbc[token]) or pbc[powerType]
        if c then
            local r = c.r or c[1]
            local g = c.g or c[2]
            local b = c.b or c[3]
            if type(r) == "number" then
                _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
                return r, g, b
            end
        end
    end

    -- Hard fallback
    _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
    return 1, 1, 1
end

-- Public: invalidate class power color cache (called from Colors panel)
_G.MSUF_ClassPower_InvalidateColors = function()
    _cachedColorToken = nil
    _cachedChargedR = nil  -- also invalidate charged cache
    _staggerCachedTier = 0  -- force stagger color re-apply
    _mwAbove5Resolved = false  -- force MW threshold color re-resolve
    -- Balance Druid: refresh eclipse + prediction overlay colors
    if type(_G.MSUF_BAL_InvalidateColors) == "function" then
        _G.MSUF_BAL_InvalidateColors()
    end
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
end

-- ============================================================================
-- Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
-- ============================================================================
-- GetUnitChargedPowerPoints("player") returns a table of 1-based indices
-- that represent which combo point slots are "charged". These are non-secret
-- in WoW 12.0 builds.
-- ============================================================================
local _chargedMap = nil   -- [index] = true, or nil if none

local function RefreshChargedPoints()
    _chargedMap = nil
    if type(GetUnitChargedPowerPoints) ~= "function" then return end

    local indices = GetUnitChargedPowerPoints("player")
    if type(indices) ~= "table" or #indices == 0 then return end

    _chargedMap = {}
    for i = 1, #indices do
        local idx = indices[i]
        if type(idx) == "number" then
            _chargedMap[idx] = true
        end
    end
end

-- Charged/empowered color resolution
local _cachedChargedR, _cachedChargedG, _cachedChargedB

local function ResolveChargedColor()
    if _cachedChargedR then
        return _cachedChargedR, _cachedChargedG, _cachedChargedB
    end

    -- 1. Custom override from Colors panel
    if MSUF_DB and MSUF_DB.general then
        local ov = MSUF_DB.general.classPowerColorOverrides
        if type(ov) == "table" then
            local c = ov["CHARGED"]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    _cachedChargedR, _cachedChargedG, _cachedChargedB = r, g, b
                    return r, g, b
                end
            end
        end
    end

    -- 2. Default: MidnightRogueBars purple
    _cachedChargedR, _cachedChargedG, _cachedChargedB = 0.60, 0.20, 0.80
    return 0.60, 0.20, 0.80
end

-- ============================================================================
-- ClassPower visual: segmented bars (created lazily on player frame)
-- ============================================================================
local MAX_CLASS_POWER = 10  -- Warlock can have up to 5 shards, Rogue up to 8+ combo pts

-- CDM frame name lookup by width-mode key (shared between CP and DPB).
local CDM_FRAMES = {
    cooldown      = "EssentialCooldownViewer",
    utility       = "UtilityCooldownViewer",
    tracked_buffs = "BuffIconCooldownViewer",
}

-- Scale-compensated width: convert CDM width to target frame's coordinate space.
-- CDM frames (EditMode-managed) may have a different effective scale than our bars.
-- GetWidth() returns logical width in the frame's own coordinate space — we must
-- convert through screen pixels to get the equivalent width in targetFrame coords.
-- Sensei avoids this because its bars inherit CDM scale; our bars don't.
local function CDM_GetScaledWidth(cdmFrame, targetFrame)
    if not cdmFrame or not cdmFrame.GetWidth then return nil end
    local w = cdmFrame:GetWidth()
    if not w or w < 1 then return nil end
    local cdmScale = (cdmFrame.GetEffectiveScale and cdmFrame:GetEffectiveScale()) or 1
    local tgtScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
    if cdmScale <= 0 then cdmScale = 1 end
    if tgtScale <= 0 then tgtScale = 1 end
    -- Same scale → no conversion needed (fast path)
    if cdmScale == tgtScale then return math_floor(w + 0.5) end
    return math_floor(w * cdmScale / tgtScale + 0.5)
end
-- Expose for DPB width sync in MidnightSimpleUnitFrames.lua
_G.MSUF_CDM_GetScaledWidth = CDM_GetScaledWidth

-- CDM hook definitions (setup-time only, never re-created).
local CDM_HOOK_DEFS = {
    { name = "EssentialCooldownViewer", flag = "_ecvHooked",  mode = "cooldown" },
    { name = "UtilityCooldownViewer",   flag = "_ucvHooked",  mode = "utility" },
    { name = "BuffIconCooldownViewer",  flag = "_bicvHooked", mode = "tracked_buffs" },
}
local CP = {
    bars      = {},      -- [i] = StatusBar
    ticks     = {},      -- [i] = Texture (separator lines)
    bgTex     = nil,     -- background texture
    container = nil,     -- parent frame
    textFrame = nil,     -- Frame: elevated overlay for text (MRB pattern)
    text      = nil,     -- FontString: resource count (e.g. "4")
    maxBars   = 0,       -- currently allocated bar count
    currentMax = 0,      -- current max power (e.g. 5 combo pts)
    powerType = nil,     -- current Enum.PowerType or string token
    renderMode = MODE_NONE,  -- active render mode
    isAuraPower = false, -- true → driven by UNIT_AURA
    isVehicle = false,   -- true → vehicle combo points active
    visible   = false,
    height    = 4,
    -- Warlock shard prediction state (Jay's approach: predicted post-cast value)
    wlPredDelta = 0,       -- shard delta for active cast (0 = no prediction)
    -- Timer Bar state (Ebon Might)
    tbCachedQ   = -1,      -- quantized percentage for skip-if-same
    tbOUA       = false,   -- true if OnUpdate is active
    -- Spell Tracker state (Tip of the Spear only — Whirlwind uses WW module)
    spStacks    = 0,       -- current stack count
    spExpires   = nil,     -- GetTime() expiry timestamp (nil = no timer)
    spCachedQ   = -1,      -- skip-if-same quantizer
}

-- DK Rune map: [display_slot] = rune_id (1-6), sorted per sortOrder
local _runeMap = { 1, 2, 3, 4, 5, 6 }
local _runeHasSortOrder = false

local function CP_ResolveTexture(key)
    if key and key ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            local p = resolve(key)
            if p then return p end
        end
    end
    -- Fallback: global bar texture → flat white
    local getBar = _G.MSUF_GetBarTexture
    return (getBar and getBar()) or "Interface\\Buttons\\WHITE8x8"
end

local function CP_EnsureBars(parent, count)
    if count <= CP.maxBars then return end

    -- Resolve textures once for all new bars
    local b = MSUF_DB and MSUF_DB.bars or {}
    local fgPath = CP_ResolveTexture(b.classPowerTexture)
    local bgKey  = b.classPowerBgTexture
    local bgPath
    if bgKey and bgKey ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
    else
        bgPath = fgPath
    end

    for i = CP.maxBars + 1, count do
        local bar = CreateFrame("StatusBar", nil, CP.container)
        bar:SetStatusBarTexture(fgPath)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:Hide()

        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetTexture(bgPath)
        bg:SetVertexColor(0, 0, 0, 0.3)
        bar._bg = bg

        -- Per-rune cooldown time text (DK runes only; shown/hidden in MODE_RUNE_CD)
        local rfs = bar:CreateFontString(nil, "OVERLAY")
        rfs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        rfs:SetJustifyH("CENTER")
        if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
        rfs:SetFontObject("GameFontHighlightSmall")
        rfs:SetTextColor(1, 1, 1, 1)
        rfs:SetShadowColor(0, 0, 0, 1)
        rfs:SetShadowOffset(1, -1)
        rfs:Hide()
        bar._runeText = rfs
        bar._runeTextQ = -1

        CP.bars[i] = bar
    end

    -- Tick separators (between bars)
    for i = CP.maxBars + 1, count - 1 do
        if not CP.ticks[i] then
            local tick = CP.container:CreateTexture(nil, "OVERLAY")
            tick:SetTexture("Interface\\Buttons\\WHITE8x8")
            tick:SetVertexColor(0, 0, 0, 1)
            tick:Hide()
            CP.ticks[i] = tick
        end
    end

    CP.maxBars = count
end

local function CP_Create(playerFrame)
    if CP.container then return end

    local c = CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame)
    c:SetFrameLevel(playerFrame:GetFrameLevel() + 5)  -- above hpBar (Unhalted overlay approach)
    c:Hide()
    CP.container = c

    -- Background
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints(c)
    bg:SetVertexColor(0, 0, 0, 0.3)
    CP.bgTex = bg

    -- Pre-allocate common max (6 for DK, 5 for most others)
    CP_EnsureBars(playerFrame, 8)

    -- Text overlay (MRB pattern: separate Frame at elevated level so text
    -- is always above individual bar segments and tick separators)
    local tf = CreateFrame("Frame", nil, c)
    tf:SetAllPoints(c)
    tf:SetFrameLevel(c:GetFrameLevel() + 10)
    CP.textFrame = tf

    local fs = tf:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", tf, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    fs:SetFontObject("GameFontHighlightSmall")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:Hide()
    CP.text = fs
end

-- ============================================================================
-- Font application (MRB MSCB_Energy_ApplyFontFromDB pattern)
-- Reads global font settings from MSUF Fonts menu. Called on create,
-- FullRefresh, and when MSUF_UpdateAllFonts fires.
-- ============================================================================
local _cpFontRev = 0  -- serial for skip-if-same optimization

local function CP_ApplyFont()
    local fs = CP.text
    if not fs then return end

    -- Resolve global font settings (same source as MRB energy text)
    local path, flags, fr, fg, fb, baseSize, useShadow
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then
        path, flags, fr, fg, fb, baseSize, useShadow = _G.MSUF_GetGlobalFontSettings()
    end
    path     = path or "Fonts\\FRIZQT__.TTF"
    flags    = flags or "OUTLINE"
    fr       = fr or 1
    fg       = fg or 1
    fb       = fb or 1
    baseSize = baseSize or 14

    -- Use dedicated class power font size (independent of global power text size)
    local fontSize = baseSize
    if MSUF_DB and MSUF_DB.bars then
        fontSize = MSUF_DB.bars.classPowerFontSize or baseSize
    end
    if fontSize < 6 then fontSize = 6 end

    -- Content-based skip: avoid redundant C-side SetFont calls
    local rev = (_G.MSUF_FontPathSerial or 0) + fontSize * 1000003
    if _cpFontRev ~= rev then
        fs:SetFont(path, fontSize, flags)
        _cpFontRev = rev
    end

    -- Apply same font to per-rune texts (slightly smaller)
    local runeSize = fontSize - 2
    if runeSize < 6 then runeSize = 6 end
    for i = 1, (CP.maxBars or 0) do
        local bar = CP.bars[i]
        local rfs = bar and bar._runeText
        if rfs then
            rfs:SetFont(path, runeSize, flags)
        end
    end

    -- Text color: check for RESOURCE_TEXT override in classPowerColorOverrides
    -- (same DB path as all class power colors, editable in Colors panel)
    local tr, tg, tb = fr, fg, fb
    if MSUF_DB and MSUF_DB.general then
        local ov = MSUF_DB.general.classPowerColorOverrides
        if type(ov) == "table" then
            local c = ov["RESOURCE_TEXT"]
            if type(c) == "table" then
                local cr = c[1] or c.r
                local cg = c[2] or c.g
                local cb = c[3] or c.b
                if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                    tr, tg, tb = cr, cg, cb
                end
            end
        end
    end

    fs:SetTextColor(tr, tg, tb, 1)

    if useShadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- ============================================================================
-- Cached alpha values (resolved once in FullRefresh, used in hot paths)
-- ============================================================================
local _filledAlpha = 1.0
local _emptyAlpha  = 0.3

-- ============================================================================
-- Auto-Hide: visibility check after each update (OOC / Full / Empty)
-- Zero overhead when all three are disabled (early-out on first check).
-- ============================================================================
local _autoHideActive = false  -- true if any auto-hide option is enabled

local function CP_CheckAutoHide(cur, maxP)
    if not _autoHideActive or not CP.visible then return end
    if not CP.container then return end

    local b = MSUF_DB and MSUF_DB.bars or {}

    -- OOC: hide when out of combat
    if b.classPowerHideOOC and not InCombatLockdown() then
        CP.container:SetAlpha(0)
        return
    end

    -- Full: hide when all resources are at max
    if b.classPowerHideWhenFull and cur ~= nil and maxP ~= nil then
        -- Only check with non-secret values
        if NotSecret(cur) and type(cur) == "number" and type(maxP) == "number" then
            if cur >= maxP and maxP > 0 then
                CP.container:SetAlpha(0)
                return
            end
        end
    end

    -- Empty: hide when zero resources
    if b.classPowerHideWhenEmpty and cur ~= nil then
        if NotSecret(cur) and type(cur) == "number" then
            if cur <= 0 then
                CP.container:SetAlpha(0)
                return
            end
        end
    end

    -- Visible: restore alpha
    CP.container:SetAlpha(1)
end

local function CP_Layout(playerFrame, maxPower, height)
    if not CP.container or maxPower <= 0 then return end

    local h = height
    local b = MSUF_DB and MSUF_DB.bars or {}

    -- Tick width from DB (0 = no ticks)
    local tickW = tonumber(b.classPowerTickWidth) or 1
    if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end

    -- User-configurable dimensions & position.
    -- Width mode: "player" = match player frame, "cooldown"/"utility"/"tracked_buffs" = CDM, "custom" = DB value.
    local widthMode = b.classPowerWidthMode or "player"
    local userW

    -- CDM frame lookup (file-level CDM_FRAMES table)
    local cdmName = CDM_FRAMES[widthMode]
    if cdmName then
        local cdmFrame = _G[cdmName]
        -- Only read width when CDM is visible (Sensei pattern); hidden frames may return stale/0.
        if cdmFrame and cdmFrame.IsShown and cdmFrame:IsShown() then
            userW = CDM_GetScaledWidth(cdmFrame, CP.container)
        end
        if not userW or userW < 30 then
            -- Fallback: actual player frame width (runtime) → DB → 275.
            userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
            if userW < 30 then
                local playerConf = MSUF_DB and MSUF_DB.player
                userW = ((playerConf and tonumber(playerConf.width)) or 275)
            end
            userW = userW - 4
        end
    elseif widthMode == "custom" then
        userW = tonumber(b.classPowerWidth) or 0
        if userW < 30 then
            userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
            if userW < 30 then
                local playerConf = MSUF_DB and MSUF_DB.player
                userW = ((playerConf and tonumber(playerConf.width)) or 275)
            end
            userW = userW - 4
        end
    else
        -- "player" (default): actual frame width (runtime), DB fallback.
        userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
        if userW < 30 then
            local playerConf = MSUF_DB and MSUF_DB.player
            userW = ((playerConf and tonumber(playerConf.width)) or 275)
        end
        userW = userW - 4
    end

    local oX = tonumber(b.classPowerOffsetX) or 0
    local oY = tonumber(b.classPowerOffsetY) or 0

    -- Anchor: either to Essential Cooldown Viewer (MRB pattern) or to playerFrame.
    CP.container:ClearAllPoints()
    CP.container:SetSize(userW, h)
    if b.classPowerAnchorToCooldown == true then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv and ecv.IsShown and ecv:IsShown() then
            CP.container:SetPoint("TOP", ecv, "BOTTOM", oX, oY)
        else
            -- Fallback to player frame when ECV not available
            CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
        end
    else
        CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
    end

    -- Pixel-perfect outline (BackdropTemplate, same pattern as MSUF_ApplyBarOutline).
    -- Wraps the container with a snapped black border. Thickness from DB (0 = hidden).
    local outlineThick = tonumber(b.classPowerOutline) or 1
    if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end
    local snap = _G.MSUF_Snap

    if outlineThick > 0 then
        local edge = (type(snap) == "function") and snap(CP.container, outlineThick) or outlineThick
        if not CP._outline then
            local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
            local ol = CreateFrame("Frame", nil, CP.container, tpl)
            ol:EnableMouse(false)
            ol:SetFrameLevel(CP.container:GetFrameLevel() + 1)
            CP._outline = ol
            CP._outlineEdge = -1
        end
        if CP._outlineEdge ~= edge then
            CP._outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edge })
            CP._outline:SetBackdropBorderColor(0, 0, 0, 1)
            CP._outlineEdge = edge
        end
        CP._outline:ClearAllPoints()
        CP._outline:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
        CP._outline:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
        CP._outline:Show()
    else
        if CP._outline then CP._outline:Hide() end
    end

    local frameW = userW

    -- Gap between pips (pixels, 0 = no gap — only tick separators)
    local gap = tonumber(b.classPowerGap) or 0
    if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
    local snapGap = (gap > 0 and type(snap) == "function") and snap(CP.container, gap) or gap

    -- Fill reverse: bars fill right-to-left
    local fillReverse = (b.classPowerFillReverse == true)

    -- Bar width: subtract total tick + gap space, divide evenly.
    -- All values pixel-snapped via MSUF_Snap to avoid subpixel bleed.
    local numTicks = maxPower - 1
    local snapTickW = (tickW > 0 and type(snap) == "function") and snap(CP.container, tickW) or tickW
    local totalSepW = numTicks * (snapTickW + snapGap)
    local totalBarSpace = frameW - totalSepW
    local barW = math_floor(totalBarSpace / maxPower)

    -- BG alpha from config
    local bgA = tonumber(b.classPowerBgAlpha) or 0.3
    CP.bgTex:SetVertexColor(0, 0, 0, bgA)

    -- Cache filled/empty alpha for hot paths (read once per layout, not per update)
    _filledAlpha = tonumber(b.classPowerFilledAlpha) or 1.0
    _emptyAlpha  = tonumber(b.classPowerEmptyAlpha)  or 0.3
    if _filledAlpha < 0 then _filledAlpha = 0 elseif _filledAlpha > 1 then _filledAlpha = 1 end
    if _emptyAlpha  < 0 then _emptyAlpha  = 0 elseif _emptyAlpha  > 1 then _emptyAlpha  = 1 end

    -- Cache auto-hide state (avoid DB lookup in hot path)
    _autoHideActive = (b.classPowerHideOOC == true)
                   or (b.classPowerHideWhenFull == true)
                   or (b.classPowerHideWhenEmpty == true)

    -- Layout individual bars (pixel-snapped positions)
    local stepW = barW + snapTickW + snapGap  -- per-bar stride
    local xPos = 0
    for i = 1, maxPower do
        local bar = CP.bars[i]
        if bar then
            bar:ClearAllPoints()
            -- Last bar: stretch to exactly fill remaining space (absorbs rounding remainder)
            local thisW = (i == maxPower) and (frameW - xPos) or barW
            if fillReverse then
                bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -xPos, 0)
            else
                bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", xPos, 0)
            end
            bar:SetSize(thisW, h)
            bar._bg:SetVertexColor(0, 0, 0, bgA)
            bar:Show()
            xPos = xPos + thisW + snapTickW + snapGap
        end
    end

    -- (Outline handles all 4 edges — no separate border line needed)

    -- Hide excess bars
    for i = maxPower + 1, CP.maxBars do
        if CP.bars[i] then CP.bars[i]:Hide() end
    end

    -- Tick separators (between bars, pixel-snapped, centered in gap+tick space)
    if snapTickW > 0 then
        local tickX = barW + math_floor(snapGap / 2)  -- first tick after first bar + half gap
        local tickStride = barW + snapTickW + snapGap
        for i = 1, numTicks do
            local tick = CP.ticks[i]
            if tick then
                tick:ClearAllPoints()
                if fillReverse then
                    tick:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -(tickX), 0)
                else
                    tick:SetPoint("TOPLEFT", CP.container, "TOPLEFT", tickX, 0)
                end
                tick:SetSize(snapTickW, h)
                tick:Show()
            end
            tickX = tickX + tickStride
        end
    end
    -- Hide excess / all ticks when tickW == 0
    local hideFrom = (snapTickW > 0) and maxPower or 1
    for i = hideFrom, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    CP.currentMax = maxPower
    CP.height = h

    -- MRB syncEnergyWithCombo pattern:
    -- Master (class power) writes its container width directly into the slave's
    -- (power bar) DB width field, then calls Reanchor. Each bar draws its own
    -- outline independently — sync is pure container-to-container, no outline
    -- compensation needed. If both outlines match, they align pixel-perfect.
    local conf = MSUF_DB and MSUF_DB.player
    local needPBRefresh = false
    if conf and conf.powerBarDetached == true then
        if conf.detachedPowerBarSyncClassPower == true then
            conf.detachedPowerBarWidth = math_floor(userW + 0.5)
            needPBRefresh = true
        end
        -- When PB is anchored to CP container, reanchor after every layout
        if conf.detachedPowerBarAnchorToClassPower == true then
            needPBRefresh = true
        end
    end
    if needPBRefresh and type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" then
        local uf = _G.MSUF_UnitFrames
        local pf = uf and uf.player
        if pf and pf.targetPowerBar then
            local sc = pf._msufStampCache
            if sc then sc["PBEmbedLayout"] = nil end
            _G.MSUF_ApplyPowerBarEmbedLayout(pf)
        end
    end
end

-- Secret-safe value update + per-bar coloring (charged/empowered support)
local function CP_UpdateValues(powerType, maxPower)
    if maxPower <= 0 then return end

    -- Get current power count (regular number for most class resources)
    local cur = UnitPower("player", powerType)
    if not NotSecret(cur) then
        -- Secret value: show all filled (safe default)
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then bar:SetValue(1) end
        end
        -- Hide text overlay (secret values cannot be displayed)
        if CP.text then CP.text:Hide() end
        return
    end

    cur = tonumber(cur) or 0

    -- Resolve base color
    local colorByType = true
    if MSUF_DB and MSUF_DB.bars then
        colorByType = (MSUF_DB.bars.classPowerColorByType ~= false)
    end

    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end

    -- Charged point support (only for combo points)
    local showCharged = MSUF_DB and MSUF_DB.bars
        and (MSUF_DB.bars.showChargedComboPoints ~= false)
        and powerType == PT.ComboPoints
    local chargedR, chargedG, chargedB
    if showCharged and _chargedMap then
        chargedR, chargedG, chargedB = ResolveChargedColor()
    end

    -- Background alpha (from DB)
    local bgA = 0.3
    if MSUF_DB and MSUF_DB.bars then
        bgA = tonumber(MSUF_DB.bars.classPowerBgAlpha) or 0.3
    end

    -- Per-bar fill + color
    for i = 1, maxPower do
        local bar = CP.bars[i]
        if bar then
            local isFilled = (i <= cur)
            bar:SetValue(isFilled and 1 or 0)
            bar:SetAlpha(isFilled and _filledAlpha or _emptyAlpha)

            local isCharged = showCharged and _chargedMap and _chargedMap[i]

            if isCharged then
                -- Charged: empowered color (filled or dim)
                bar:SetStatusBarColor(chargedR, chargedG, chargedB, 1)
                if isFilled then
                    bar._bg:SetVertexColor(0, 0, 0, bgA)
                else
                    -- Dim charged bg (visible when empty, shows the slot is empowered)
                    local dR = chargedR * 0.45; if dR < 0.05 then dR = 0.05 end
                    local dG = chargedG * 0.45; if dG < 0.05 then dG = 0.05 end
                    local dB = chargedB * 0.45; if dB < 0.05 then dB = 0.05 end
                    bar._bg:SetVertexColor(dR, dG, dB, 1)
                end
            else
                -- Normal: base color
                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                bar._bg:SetVertexColor(0, 0, 0, bgA)
            end
        end
    end

    -- Resource count text (Jay's Warlock prediction: show predicted post-cast value)
    local txt = CP.text
    if txt then
        local showText = MSUF_DB and MSUF_DB.bars
            and (MSUF_DB.bars.classPowerShowText == true)
        if showText then
            local predDelta = CP.wlPredDelta
            if predDelta ~= 0 and PLAYER_CLASS == "WARLOCK" then
                -- Predicted value with "*" suffix (e.g. "3*" during Shadow Bolt)
                local predicted = cur + predDelta
                if predicted < 0 then predicted = 0 end
                if predicted > maxPower then predicted = maxPower end
                txt:SetText(predicted .. "*")
                txt:Show()
            elseif cur > 0 then
                txt:SetText(cur)
                txt:Show()
            else
                txt:Hide()
            end
        else
            txt:Hide()
        end
    end

    -- Auto-hide check
    CP_CheckAutoHide(cur, maxPower)
end

-- Legacy color-only refresh (called from FullRefresh for initial setup)
local function CP_ApplyColors(powerType)
    -- Now handled inline by CP_UpdateValues; this is kept for
    -- call sites that need a color refresh without value change.
    CP_UpdateValues(powerType, CP.currentMax)
end

local function CP_RefreshTexture()
    local b = MSUF_DB and MSUF_DB.bars or {}
    local fgKey = b.classPowerTexture     -- nil/empty = follow global bar texture
    local bgKey = b.classPowerBgTexture   -- nil/empty = follow foreground

    local fgPath = CP_ResolveTexture(fgKey)
    local bgPath
    if bgKey and bgKey ~= "" then
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
    else
        bgPath = fgPath
    end

    for i = 1, CP.maxBars do
        local bar = CP.bars[i]
        if bar then
            bar:SetStatusBarTexture(fgPath)
            if bar._bg then bar._bg:SetTexture(bgPath) end
        end
    end
    -- Container background
    if CP.bgTex then CP.bgTex:SetTexture(bgPath) end
end

-- ============================================================================
-- MODE_FRACTIONAL: Destruction Warlock — partial Soul Shard fill (oUF pattern)
-- UnitPower(unit, type, true) / UnitPowerDisplayMod(type) gives e.g. 3.7
-- ============================================================================
local function CP_UpdateValues_Fractional(powerType, maxPower)
    if maxPower <= 0 then return end

    -- Raw fractional value (3rd arg = true → unmodified)
    local rawCur = UnitPower("player", powerType, true)
    if not NotSecret(rawCur) then
        -- Fallback: show all filled
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then bar:SetValue(1) end
        end
        if CP.text then CP.text:Hide() end
        return
    end
    rawCur = tonumber(rawCur) or 0

    local mod = UnitPowerDisplayMod and UnitPowerDisplayMod(powerType) or 1
    -- Secret-safe: UnitPowerDisplayMod can return secret in 12.0.
    -- If secret or invalid, fall back to 100 for Soul Shards (standard Blizzard mod).
    if not NotSecret(mod) or type(mod) ~= "number" or mod <= 0 then
        mod = 100
    end
    local fractional = rawCur / mod  -- e.g. 3.7

    -- Resolve color
    local colorByType = true
    if MSUF_DB and MSUF_DB.bars then
        colorByType = (MSUF_DB.bars.classPowerColorByType ~= false)
    end
    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end

    local bgA = (MSUF_DB and MSUF_DB.bars and tonumber(MSUF_DB.bars.classPowerBgAlpha)) or 0.3

    -- Per-bar fill: full bars + partial current bar
    local fullBars = math_floor(fractional)
    local partial  = fractional - fullBars  -- 0.0 – 0.999

    for i = 1, maxPower do
        local bar = CP.bars[i]
        if bar then
            if i <= fullBars then
                bar:SetValue(1)
                bar:SetAlpha(_filledAlpha)
            elseif i == fullBars + 1 and partial > 0.001 then
                bar:SetValue(partial)
                bar:SetAlpha(_filledAlpha)
            else
                bar:SetValue(0)
                bar:SetAlpha(_emptyAlpha)
            end
            bar:SetStatusBarColor(baseR, baseG, baseB, 1)
            bar._bg:SetVertexColor(0, 0, 0, bgA)
        end
    end

    -- Text: show fractional value (Jay's prediction: predicted post-cast value with "*")
    local txt = CP.text
    if txt then
        local showText = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.classPowerShowText == true)
        if showText then
            local predDelta = CP.wlPredDelta
            if predDelta ~= 0 then
                -- Predicted post-cast value (e.g. "3.5*" during Incinerate, "1.3*" during Chaos Bolt)
                local predicted = fractional + predDelta
                if predicted < 0 then predicted = 0 end
                if predicted > maxPower then predicted = maxPower end
                local predPartial = predicted - math_floor(predicted)
                if predPartial > 0.001 then
                    txt:SetText(string_format("%.1f*", predicted))
                else
                    txt:SetText(math_floor(predicted) .. "*")
                end
            else
                if partial > 0.001 then
                    txt:SetText(string_format("%.1f", fractional))
                else
                    txt:SetText(fullBars)
                end
            end
            txt:Show()
        else
            txt:Hide()
        end
    end

    -- Auto-hide check (use integer shard count for full/empty)
    CP_CheckAutoHide(fullBars, maxPower)
end

-- ============================================================================
-- MODE_RUNE_CD: Death Knight — per-rune cooldown animation (oUF pattern)
-- Each rune bar animates its fill via OnUpdate when recharging.
-- Sort order: "asc" = ready first, "desc" = depleted first.
-- ============================================================================

-- Sort functions (oUF pattern, direct == on booleans is safe)
local function _runeAscSort(a, b)
    local aStart, _, aReady = GetRuneCooldown(a)
    local bStart, _, bReady = GetRuneCooldown(b)
    if aReady ~= bReady then
        return aReady  -- true sorts before false
    elseif aStart ~= bStart then
        return (aStart or 0) < (bStart or 0)
    else
        return a < b
    end
end

local function _runeDescSort(a, b)
    local aStart, _, aReady = GetRuneCooldown(a)
    local bStart, _, bReady = GetRuneCooldown(b)
    if aReady ~= bReady then
        return bReady
    elseif aStart ~= bStart then
        return (aStart or 0) > (bStart or 0)
    else
        return a > b
    end
end

-- Per-rune OnUpdate handler (only set on recharging runes)
local function _runeBarOnUpdate(bar, elapsed)
    local dur = (bar._runeDuration or 0) + elapsed
    bar._runeDuration = dur
    bar:SetValue(dur)

    -- Optional per-rune remaining time text (Sensei-style).
    -- No secret values involved (GetRuneCooldown + GetTime are safe).
    local rfs = bar._runeText
    if rfs and bar._runeShowTime and bar._runeTotalDuration and bar._runeTotalDuration > 0 then
        local rem = bar._runeTotalDuration - dur
        if rem < 0 then rem = 0 end

        -- Quantize to 0.1s to avoid excessive SetText spam.
        local q = math_floor(rem * 10 + 0.5) -- integer tenths
        if q ~= (bar._runeTextQ or -1) then
            bar._runeTextQ = q
            if q <= 0 then
                rfs:SetText("")
                rfs:Hide()
            else
                rfs:SetFormattedText("%.1f", q / 10)
                rfs:Show()
            end
        end
    elseif rfs then
        -- Ensure hidden when disabled
        if rfs:IsShown() then rfs:Hide() end
    end
end

local function CP_UpdateValues_RuneCD(powerType, maxPower)
    if maxPower <= 0 then return end

    -- Sort the rune map (oUF pattern)
    local b = MSUF_DB and MSUF_DB.bars or {}
    local sortOrder = b.runeSortOrder
    if sortOrder == "asc" then
        table_sort(_runeMap, _runeAscSort)
        _runeHasSortOrder = true
    elseif sortOrder == "desc" then
        table_sort(_runeMap, _runeDescSort)
        _runeHasSortOrder = true
    elseif _runeHasSortOrder then
        -- Reset to natural order
        for i = 1, 6 do _runeMap[i] = i end
        _runeHasSortOrder = false
    end

    -- Resolve color
    local colorByType = true
    if b then colorByType = (b.classPowerColorByType ~= false) end
    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end
    local bgA = tonumber(b.classPowerBgAlpha) or 0.3
    local showRuneTime = (b.runeShowTime ~= false)

    local now = GetTime()
    local readyCount = 0

    for displayIdx = 1, maxPower do
        local runeID = _runeMap[displayIdx]
        local bar = CP.bars[displayIdx]
        if not bar then break end

        if UnitHasVehicleUI and UnitHasVehicleUI("player") then
            bar:Hide()
        else
            local start, duration, runeReady = GetRuneCooldown(runeID)

            if runeReady then
                -- Fully charged: show full, no OnUpdate
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(1)
                bar:SetScript("OnUpdate", nil)
                bar._runeDuration = nil
                bar:SetAlpha(_filledAlpha)
                bar._runeTotalDuration = nil
                bar._runeShowTime = showRuneTime
                bar._runeTextQ = -1
                if bar._runeText then bar._runeText:SetText(""); bar._runeText:Hide() end
                readyCount = readyCount + 1
            elseif start and duration and duration > 0 then
                -- Recharging: animate fill via OnUpdate
                bar._runeDuration = now - start
                bar._runeTotalDuration = duration
                bar._runeShowTime = showRuneTime
                bar._runeTextQ = -1
                bar:SetMinMaxValues(0, duration)
                bar:SetValue(bar._runeDuration)
                bar:SetScript("OnUpdate", _runeBarOnUpdate)
                bar:SetAlpha(_filledAlpha)
                if showRuneTime and bar._runeText then
                    local rem = duration - bar._runeDuration
                    if rem < 0 then rem = 0 end
                    local q = math_floor(rem * 10 + 0.5)
                    bar._runeTextQ = q
                    if q > 0 then
                        bar._runeText:SetFormattedText("%.1f", q / 10)
                        bar._runeText:Show()
                    else
                        bar._runeText:SetText("")
                        bar._runeText:Hide()
                    end
                elseif bar._runeText then
                    bar._runeText:SetText("")
                    bar._runeText:Hide()
                end
            else
                -- Unknown state: show empty
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(0)
                bar:SetScript("OnUpdate", nil)
                bar._runeDuration = nil
                bar._runeTotalDuration = nil
                bar._runeShowTime = showRuneTime
                bar._runeTextQ = -1
                if bar._runeText then bar._runeText:SetText(""); bar._runeText:Hide() end
                bar:SetAlpha(_emptyAlpha)
            end

            bar:SetStatusBarColor(baseR, baseG, baseB, 1)
            bar._bg:SetVertexColor(0, 0, 0, bgA)
            bar:Show()
        end
    end

    -- Text: show ready count
    local txt = CP.text
    if txt then
        local showText = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.classPowerShowText == true)
        if showText and readyCount > 0 then
            txt:SetText(readyCount)
            txt:Show()
        else
            txt:Hide()
        end
    end

    -- Auto-hide check
    CP_CheckAutoHide(readyCount, maxPower)
end

-- ============================================================================
-- MODE_AURA_SEGMENTED: Aura-based stack display (oUF pattern)
--   Enhancement Shaman — Maelstrom Weapon (10 stacks)
--   Fury Warrior — Whirlwind cleave buff (2 stacks)
--   Survival Hunter — Tip of the Spear (3 stacks)
--   DH Vengeance — Soul Fragments (C_Spell.GetSpellCastCount, SECRET)
-- SECRET-SAFE (Vengeance): GetSpellCastCount returns secret in 12.0.
--   Trick: SetMinMaxValues(i-1, i) + SetValue(cur) per bar →
--   C-side StatusBar does the range check, zero Lua comparisons on cur.
--   Text: SetFormattedText("%d / %d", cur, mx) → C-side formats secret.
-- Non-secret types: read aura stacks via C_UnitAuras.GetPlayerAuraBySpellID.
-- ============================================================================
local function CP_UpdateValues_AuraSegmented(powerType, maxPower)
    if maxPower <= 0 then return end

    -- Resolve color
    local colorByType = true
    local b = MSUF_DB and MSUF_DB.bars or {}
    if b then colorByType = (b.classPowerColorByType ~= false) end
    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end
    local bgA = tonumber(b.classPowerBgAlpha) or 0.3

    if powerType == "SOUL_FRAGMENTS_VENG" then
        -- DH Vengeance: C_Spell.GetSpellCastCount → SECRET number in 12.0
        -- Zero Lua arithmetic on cur. C-side StatusBar handles range checks.
        -- Alpha: can't distinguish filled/empty in Lua for secrets → all _filledAlpha.
        local getCastCount = C_Spell and C_Spell.GetSpellCastCount
        local cur = getCastCount and getCastCount(SPELL_SOUL_CLEAVE) or 0

        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                -- C-side: if cur >= i → full, if cur < i-1 → empty
                bar:SetMinMaxValues(i - 1, i)
                bar:SetValue(cur)
                bar:SetAlpha(_filledAlpha)
                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                bar._bg:SetVertexColor(0, 0, 0, bgA)
            end
        end

        -- Text: SetFormattedText passes secret values to C-side
        local txt = CP.text
        if txt then
            local showText = b.classPowerShowText == true
            if showText then
                txt:SetFormattedText("%d / %d", cur, maxPower)
                txt:Show()
            else
                txt:Hide()
            end
        end
        -- Vengeance: no auto-hide for secret cur (can't compare)
    else
        -- Non-secret stack-based resources.
        -- Maelstrom Weapon: aura-driven (UNIT_AURA → GetPlayerAuraBySpellID).
        -- Whirlwind / Tip of the Spear: spell-tracked (UNIT_SPELLCAST_SUCCEEDED).
        local cur = 0
        if powerType == "MAELSTROM_WEAPON" then
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local info = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_MAELSTROM_WEAPON)
                if info and info.applications then
                    cur = info.applications
                end
            end
        elseif powerType == "WHIRLWIND" then
            -- Whirlwind: polled from self-contained WW module (own event frame)
            cur = WW.GetStacks()
        elseif powerType == "TIP_OF_THE_SPEAR" then
            -- Tip of the Spear: spell-tracked via main event handler
            if CP.spExpires and GetTime() >= CP.spExpires then
                CP.spStacks = 0
                CP.spExpires = nil
            end
            cur = CP.spStacks
        end

        -- Maelstrom Weapon: resolve threshold color for stacks > 5 (spender empowered)
        local mwAbove5 = (powerType == "MAELSTROM_WEAPON" and cur > MW_SPEND_THRESHOLD)
        local abR, abG, abB
        if mwAbove5 then
            abR, abG, abB = ResolveMWAbove5Color()
        end

        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                local isFilled = (i <= cur)
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(isFilled and 1 or 0)
                bar:SetAlpha(isFilled and _filledAlpha or _emptyAlpha)
                -- MW threshold: segments above 5 get "spender ready" color
                if mwAbove5 and isFilled and i > MW_SPEND_THRESHOLD then
                    bar:SetStatusBarColor(abR, abG, abB, 1)
                else
                    bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                end
                bar._bg:SetVertexColor(0, 0, 0, bgA)
            end
        end

        -- Text
        local txt = CP.text
        if txt then
            local showText = b.classPowerShowText == true
            if showText and cur > 0 then
                txt:SetText(cur)
                txt:Show()
            else
                txt:Hide()
            end
        end

        -- Auto-hide check
        CP_CheckAutoHide(cur, maxPower)
    end
end

-- Wire up WW event-driven render (forward-declared before WW module)
_wwRender = function()
    if CP.visible and CP.powerType == "WHIRLWIND" then
        CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
    end
end

-- ============================================================================
-- MODE_AURA_SINGLE: DH Devourer — Soul Fragments (oUF pattern)
-- Normalized to 0-1 in a single bar. Dual color: normal vs Void Metamorphosis.
-- Colors configurable via Colors menu (SOUL_FRAGMENTS / SOUL_FRAGMENTS_META).
-- ============================================================================

-- Resolve DH color from DB override → hardcoded default
local function ResolveDHColor(isVoidMeta)
    local ov = MSUF_DB and MSUF_DB.general and MSUF_DB.general.classPowerColorOverrides
    if type(ov) == "table" then
        local token = isVoidMeta and "SOUL_FRAGMENTS_META" or "SOUL_FRAGMENTS"
        local c = ov[token]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    -- Hardcoded defaults (oUF-sourced)
    if isVoidMeta then
        return 0.60, 0.20, 0.93  -- Void Meta purple
    else
        return 0.00, 0.80, 0.00  -- Normal green
    end
end

local function CP_UpdateValues_AuraSingle(powerType, maxPower)
    -- maxPower is always 1 for this mode (single normalized bar)
    local cur = 0

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local inMeta = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_VOID_METAMORPHOSIS)
        if inMeta then
            -- Void Metamorphosis: track Silence the Whispers
            local whispers = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_SILENCE_THE_WHISPERS)
            if whispers and whispers.applications then
                local cost = (type(GetCollapsingStarCost) == "function") and GetCollapsingStarCost() or 1
                if cost > 0 then
                    cur = whispers.applications / cost
                end
            end
        else
            -- Normal: track Dark Heart
            local darkHeart = C_UnitAuras.GetPlayerAuraBySpellID(SPELL_DARK_HEART)
            if darkHeart and darkHeart.applications then
                local maxApp = 1
                if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                    maxApp = C_Spell.GetSpellMaxCumulativeAuraApplications(SPELL_DARK_HEART) or 1
                end
                if maxApp > 0 then
                    cur = darkHeart.applications / maxApp
                end
            end
        end
    end
    if cur > 1 then cur = 1 end

    -- Color: meta vs normal (configurable via Colors menu)
    local colorByType = true
    local b = MSUF_DB and MSUF_DB.bars or {}
    if b then colorByType = (b.classPowerColorByType ~= false) end

    local r, g, bl
    if colorByType then
        local inMeta = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
            and C_UnitAuras.GetPlayerAuraBySpellID(SPELL_VOID_METAMORPHOSIS)
        r, g, bl = ResolveDHColor(inMeta and true or false)
    else
        r, g, bl = 1, 1, 1
    end

    local bgA = tonumber(b.classPowerBgAlpha) or 0.3
    local bar = CP.bars[1]
    if bar then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(cur)
        bar:SetAlpha(cur > 0.01 and _filledAlpha or _emptyAlpha)
        bar:SetStatusBarColor(r, g, bl, 1)
        bar._bg:SetVertexColor(0, 0, 0, bgA)
    end

    -- Hide bars 2+ (only 1 bar used)
    for i = 2, CP.maxBars do
        if CP.bars[i] then CP.bars[i]:Hide() end
    end
    -- Hide ticks (single bar = no separators)
    for i = 1, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    -- Text: show as percentage
    local txt = CP.text
    if txt then
        local showText = b.classPowerShowText == true
        if showText and cur > 0.01 then
            txt:SetText(math_floor(cur * 100 + 0.5) .. "%")
            txt:Show()
        else
            txt:Hide()
        end
    end

    -- Auto-hide: treat cur>0 as "has resource", 1.0 as "full"
    local intCur = (cur > 0.01) and 1 or 0
    CP_CheckAutoHide(intCur, 1)
end

-- ============================================================================
-- MODE_CONTINUOUS: Balance Druid — Astral Power bar + Eclipse colors + prediction
-- MCR-sourced architecture: single continuous bar, eclipse-aware coloring,
-- cast prediction overlay texture on bars[1].
-- SECRET-SAFE: UnitPower(LunarPower) may be secret → passed to SetValue
-- directly (C-side handles secret numbers). No Lua arithmetic on cur.
-- ============================================================================

-- (Balance Druid prediction + eclipse colors now live in self-contained BAL module
--  above, with own event frame on the main power bar. Zero CP dependency.)

local function CP_UpdateValues_Continuous(powerType, maxPower)
    -- SECRET-SAFE: cur may be a secret number in 12.0
    -- No arithmetic, no comparisons, no string concat on cur allowed
    local cur = UnitPower("player", powerType)
    local mx  = UnitPowerMax("player", powerType) or 100
    if mx <= 0 then mx = 100 end

    -- Single bar: maxPower is always 1 (one continuous bar)
    local bar = CP.bars[1]
    if not bar then return end

    -- Color from type (Ele Maelstrom / Shadow Insanity)
    local colorByType = true
    local b = MSUF_DB and MSUF_DB.bars or {}
    if b then colorByType = (b.classPowerColorByType ~= false) end
    if colorByType then
        local r, g, bl = ResolveClassPowerColor(powerType)
        bar:SetStatusBarColor(r, g, bl, 1)
    else
        bar:SetStatusBarColor(1, 1, 1, 1)
    end

    -- Secret-safe: pass values directly to widget, zero Lua arithmetic on cur
    bar:SetMinMaxValues(0, mx)
    bar:SetValue(cur)
    bar:SetAlpha(_filledAlpha)
    bar:Show()

    local bgA = (MSUF_DB and MSUF_DB.bars and tonumber(MSUF_DB.bars.classPowerBgAlpha)) or 0.3
    bar._bg:SetVertexColor(0, 0, 0, bgA)

    -- Hide bars 2+ (only 1 bar used)
    for i = 2, CP.maxBars do
        local b2 = CP.bars[i]
        if b2 then b2:Hide() end
    end
    -- Hide ticks (single bar = no separators)
    for i = 1, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    -- Text: secret value → SetFormattedText passes through to C-side safely
    local txt = CP.text
    if txt then
        local showText = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.classPowerShowText == true)
        if showText then
            txt:SetFormattedText("%d / %d", cur, mx)
            txt:Show()
        else
            txt:Hide()
        end
    end

    -- Auto-hide: cur may be secret → CP_CheckAutoHide handles NotSecret guard
    CP_CheckAutoHide(cur, mx)
end

-- ============================================================================
-- MODE_TIMER_BAR: Ebon Might — continuous countdown bar (MCR-sourced)
-- C_UnitAuras.GetPlayerAuraBySpellID(395296).expirationTime based.
-- Needs OnUpdate for smooth countdown (20fps cap = ~0.01ms overhead).
-- Secret-safe: expirationTime is NOT secret.
-- ============================================================================

local function CP_UpdateValues_TimerBar(powerType, maxPower)
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local aura = getAura and getAura(SPELL_EBON_MIGHT)
    local remaining = aura and (aura.expirationTime - GetTime()) or 0
    if remaining < 0 then remaining = 0 end
    local mx = EBON_MIGHT_MAX_DURATION

    -- Quantize to 0.1s for skip-if-same
    local qPct = math_floor(remaining * 10 + 0.5)
    if qPct == CP.tbCachedQ then return end
    CP.tbCachedQ = qPct

    local pct = remaining / mx
    if pct > 1 then pct = 1 end

    -- Single continuous bar
    local bar = CP.bars[1]
    if not bar then return end

    -- Resolve color
    local colorByType = true
    local b = MSUF_DB and MSUF_DB.bars or {}
    if b then colorByType = (b.classPowerColorByType ~= false) end
    local r, g, bl
    if colorByType then
        r, g, bl = ResolveClassPowerColor(powerType)
    else
        r, g, bl = 1, 1, 1
    end
    local bgA = tonumber(b.classPowerBgAlpha) or 0.3

    bar:SetStatusBarColor(r, g, bl, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(pct)
    bar:SetAlpha(remaining > 0 and _filledAlpha or _emptyAlpha)
    bar:Show()
    bar._bg:SetVertexColor(0, 0, 0, bgA)

    -- Hide bars 2+
    for i = 2, CP.maxBars do
        local b2 = CP.bars[i]
        if b2 then b2:Hide() end
    end
    for i = 1, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    -- Text: countdown "12.3s"
    local txt = CP.text
    if txt then
        local showText = b.classPowerShowText == true
        if showText then
            txt:SetText(string_format("%.1fs", remaining))
            txt:Show()
        else
            txt:Hide()
        end
    end

    -- Auto-hide: treat remaining>0 as "has resource"
    local intCur = remaining > 0.1 and 1 or 0
    CP_CheckAutoHide(intCur, 1)
end

-- Timer bar OnUpdate handler (pre-allocated, zero alloc) — 20fps cap
local _tbElapsed = 0
local function TimerBarOnUpdate_Tick(self, dt)
    _tbElapsed = _tbElapsed + dt
    if _tbElapsed < 0.05 then return end  -- 20fps cap
    _tbElapsed = 0
    CP_UpdateValues_TimerBar(CP.powerType, CP.currentMax)
end

local function SetTimerBarOnUpdate(on)
    if not CP.container then return end
    if on and not CP.tbOUA then
        CP.tbOUA = true
        _tbElapsed = 0
        CP.container:SetScript("OnUpdate", TimerBarOnUpdate_Tick)
    elseif not on and CP.tbOUA then
        CP.tbOUA = false
        CP.container:SetScript("OnUpdate", nil)
    end
end

-- ============================================================================
-- Warlock Shard Prediction: "*" indicator during generator casts
-- Text turns red when below spec-specific low shard threshold.
-- EVENT: UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED
-- ============================================================================

-- Called from event handler when warlock starts casting a known spell
local function OnWarlockCastStart(spellID)
    if PLAYER_CLASS ~= "WARLOCK" then return end
    local spec = GetSpec and GetSpec()
    local deltaTable = spec and WL_SHARD_DELTAS[spec]
    local delta = deltaTable and deltaTable[spellID]
    if delta then
        CP.wlPredDelta = delta
        -- Re-render with predicted value
        local updateFn = MODE_UPDATE_FN and MODE_UPDATE_FN[CP.renderMode]
        if updateFn then
            updateFn(CP.powerType, CP.currentMax)
        end
    end
end

-- Called when warlock cast ends (any reason)
local function OnWarlockCastEnd()
    if CP.wlPredDelta == 0 then return end
    CP.wlPredDelta = 0
    local updateFn = MODE_UPDATE_FN and MODE_UPDATE_FN[CP.renderMode]
    if updateFn then
        updateFn(CP.powerType, CP.currentMax)
    end
end

-- ============================================================================
-- Spell Tracker: Whirlwind / Tip of the Spear (Sensei-proven pattern)
-- UNIT_SPELLCAST_SUCCEEDED based — aura tracking unreliable for these.
-- castGUID dedup prevents double-counting on server echo.
-- ============================================================================

-- (Whirlwind tracking moved to self-contained WW module with own event frame)

local function OnTipOfTheSpearSpellCast(spellID)
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then return end
    if not known(TIP_TALENT_ID) then return end

    -- Kill Command → gain 1 (or 2 with Primal Surge)
    if spellID == TIP_KILL_COMMAND then
        local gain = known(TIP_PRIMAL_SURGE) and 2 or 1
        CP.spStacks = math_min(TIP_MAX_STACKS, CP.spStacks + gain)
        CP.spExpires = GetTime() + TIP_DURATION
        CP.spCachedQ = -1
        CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
        return
    end

    -- Takedown + Twin Fang → gain 2
    if spellID == TIP_TAKEDOWN and known(TIP_TWIN_FANG) then
        CP.spStacks = math_min(TIP_MAX_STACKS, CP.spStacks + 2)
        CP.spExpires = GetTime() + TIP_DURATION
        CP.spCachedQ = -1
        CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
        return
    end

    -- Spender → consume 1
    if TIP_SPENDERS[spellID] then
        if CP.spStacks > 0 then
            CP.spStacks = CP.spStacks - 1
            if CP.spStacks == 0 then CP.spExpires = nil end
            CP.spCachedQ = -1
            CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
        end
    end
end

-- PLAYER_DEAD / PLAYER_ALIVE: reset spell tracker state (Sensei pattern)
local function OnSpellTrackerReset()
    CP.spStacks = 0
    CP.spExpires = nil
    CP.spCachedQ = -1
end

-- ============================================================================
-- Stagger colors (oUF-sourced defaults; overridable via Colors menu)
-- Used by CP_UpdateValues_Stagger for 3-color threshold system.
-- ============================================================================
local STAGGER_COLOR_DEFAULTS = {
    { 0.52, 1.00, 0.52 },  -- green  (< 30%)
    { 1.00, 0.98, 0.72 },  -- yellow (30-60%)
    { 1.00, 0.42, 0.42 },  -- red    (> 60%)
}
local STAGGER_TOKENS = { "STAGGER_GREEN", "STAGGER_YELLOW", "STAGGER_RED" }

local function ResolveStaggerColor(tier)
    local ov = MSUF_DB and MSUF_DB.general and MSUF_DB.general.classPowerColorOverrides
    if type(ov) == "table" then
        local token = STAGGER_TOKENS[tier]
        local c = token and ov[token]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    local def = STAGGER_COLOR_DEFAULTS[tier]
    return def[1], def[2], def[3]
end

-- ============================================================================
-- MODE_STAGGER: Brewmaster Monk — stagger bar (oUF 3-color threshold pattern)
-- Reads UnitStagger("player") / UnitHealthMax("player"). Event-driven via
-- UNIT_AURA (stagger amount) and UNIT_HEALTH (max health = bar max).
-- Secret-safe: UnitStagger returns plain numbers, not secrets.
-- ============================================================================
local function CP_UpdateValues_Stagger(powerType, maxPower)
    local cur = UnitStagger and UnitStagger("player") or 0
    local mx  = UnitHealthMax("player") or 1
    if type(cur) ~= "number" then cur = 0 end
    if type(mx) ~= "number" or mx <= 0 then mx = 1 end

    local bar = CP.bars[1]
    if not bar then return end

    bar:SetMinMaxValues(0, mx)
    bar:SetValue(cur)
    bar:SetAlpha(_filledAlpha)
    bar:Show()

    -- 3-color threshold (oUF pattern; colors configurable via Colors menu)
    local perc = cur / mx
    local tier
    if perc >= STAGGER_RED_TRANSITION then tier = 3
    elseif perc > STAGGER_YELLOW_TRANSITION then tier = 2
    else tier = 1 end

    if tier ~= _staggerCachedTier then
        _staggerCachedTier = tier
        local r, g, b = ResolveStaggerColor(tier)
        bar:SetStatusBarColor(r, g, b, 1)
    end

    local bgA = (MSUF_DB and MSUF_DB.bars and tonumber(MSUF_DB.bars.classPowerBgAlpha)) or 0.3
    if bar._bg then bar._bg:SetVertexColor(0, 0, 0, bgA) end

    -- Hide bars 2+ (single bar mode)
    for i = 2, CP.maxBars do
        local b2 = CP.bars[i]
        if b2 then b2:Hide() end
    end
    -- Hide ticks (single bar = no separators)
    for i = 1, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    -- Text: show stagger amount in K (e.g. "12.3K") — more useful than %
    local txt = CP.text
    if txt then
        local showText = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.classPowerShowText == true)
        if showText then
            if cur >= 1000 then
                txt:SetFormattedText("%.1fK", cur / 1000)
            else
                txt:SetFormattedText("%d", cur)
            end
            txt:Show()
        else
            txt:Hide()
        end
    end

    CP_CheckAutoHide(cur, mx)
end

-- ============================================================================
-- Update function dispatch table (set in FullRefresh, called in hot path)
-- ============================================================================
local MODE_UPDATE_FN = {
    [MODE_SEGMENTED]      = CP_UpdateValues,
    [MODE_FRACTIONAL]     = CP_UpdateValues_Fractional,
    [MODE_RUNE_CD]        = CP_UpdateValues_RuneCD,
    [MODE_AURA_SEGMENTED] = CP_UpdateValues_AuraSegmented,
    [MODE_AURA_SINGLE]    = CP_UpdateValues_AuraSingle,
    [MODE_CONTINUOUS]     = CP_UpdateValues_Continuous,
    [MODE_TIMER_BAR]      = CP_UpdateValues_TimerBar,
    [MODE_STAGGER]        = CP_UpdateValues_Stagger,
}

-- Forward declaration (AM defined later)
local AM

-- ============================================================================
-- AltMana visual: single StatusBar (created lazily on player frame)
-- ============================================================================
AM = {
    bar       = nil,
    container = nil,
    bgTex     = nil,
    visible   = false,
}

local function AM_Create(playerFrame)
    if AM.container then return end

    local c = CreateFrame("Frame", "MSUF_AltManaContainer", playerFrame)
    c:SetFrameLevel(playerFrame:GetFrameLevel() + 2)
    c:Hide()
    AM.container = c

    -- Background
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints(c)
    bg:SetVertexColor(0, 0, 0, 0.4)
    AM.bgTex = bg

    -- Border (1px black outline via backdrop)
    local border = CreateFrame("Frame", nil, c, "BackdropTemplate")
    border:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:SetFrameLevel(c:GetFrameLevel() + 1)
    AM._border = border

    -- Status bar
    local getTexture = _G.MSUF_GetBarTexture
    local bar = CreateFrame("StatusBar", nil, c)
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    bar:SetStatusBarTexture(getTexture and getTexture() or "Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetFrameLevel(c:GetFrameLevel() + 1)
    AM.bar = bar
end

local function AM_Layout(playerFrame)
    if not AM.container then return end
    local b = MSUF_DB and MSUF_DB.bars or {}

    local h = tonumber(b.altManaHeight) or 4
    if h < 2 then h = 2 elseif h > 30 then h = 30 end
    local oY = tonumber(b.altManaOffsetY) or -2

    -- Below playerFrame, matching hpBar horizontal edges for width consistency.
    AM.container:ClearAllPoints()
    AM.container:SetPoint("TOPLEFT",  playerFrame, "BOTTOMLEFT",   2, oY)
    AM.container:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -2, oY)
    AM.container:SetHeight(h)
end

local function AM_ApplyColor()
    if not AM.bar then return end
    local b = MSUF_DB and MSUF_DB.bars or {}
    local r = tonumber(b.altManaColorR) or 0.0
    local g = tonumber(b.altManaColorG) or 0.0
    local bl = tonumber(b.altManaColorB) or 0.8

    -- Try MSUF override for Mana color
    local mr, mg, mb = ResolveClassPowerColor(PT.Mana)
    if mr then r, g, bl = mr, mg, mb end

    AM.bar:SetStatusBarColor(r, g, bl, 1)
end

-- Secret-safe mana value update (MidnightRogueBars approach)
local function AM_UpdateValue()
    if not AM.bar then return end

    -- Raw values, 2 args only (like MidnightRogueBars).
    local cur = UnitPower("player", PT.Mana)
    local mx  = UnitPowerMax("player", PT.Mana)
    if type(cur) ~= "number" then cur = 0 end
    if type(mx)  ~= "number" then mx  = 100 end

    -- Smooth interpolation when enabled.
    local smoothOn = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.smoothPowerBar ~= false)
    local interp = smoothOn and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
    if interp then
        AM.bar:SetMinMaxValues(0, mx, interp)
        AM.bar:SetValue(cur, interp)
    else
        AM.bar:SetMinMaxValues(0, mx)
        AM.bar:SetValue(cur)
    end
end

local function AM_RefreshTexture()
    if not AM.bar then return end
    local getTexture = _G.MSUF_GetBarTexture
    AM.bar:SetStatusBarTexture(getTexture and getTexture() or "Interface\\Buttons\\WHITE8x8")
end

-- ============================================================================
-- Master show/hide + layout integration
-- ============================================================================

local function GetPlayerFrame()
    return _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player) or nil
end

-- ============================================================================
-- Full refresh (called on spec change, form change, config change)
-- ============================================================================
local function FullRefresh()
    if not MSUF_DB then return end
    local b = MSUF_DB.bars or {}
    local playerFrame = GetPlayerFrame()
    if not playerFrame then return end

    -- Hook player frame resize → relayout bars inside the container.
    -- Container auto-stretches via dual-point anchoring, but individual
    -- bars use calculated pixel positions that need recalculating.
    if not playerFrame._msufCPSizeHooked then
        playerFrame._msufCPSizeHooked = true
        playerFrame:HookScript("OnSizeChanged", function()
            if type(_G.MSUF_ClassPower_Refresh) == "function" then
                _G.MSUF_ClassPower_Refresh()
            end
        end)
    end

    -- Hook CDM frames (Essential/Utility/Tracked Buffs) for width-sync + anchor mode.
    -- COMBAT LOCKDOWN: zero overhead in combat. OnSizeChanged fires but callback
    -- exits at first line (InCombatLockdown check). A single catch-up relayout
    -- runs on PLAYER_REGEN_ENABLED to sync any width changes that occurred mid-fight.
    -- Out of combat: lightweight CP_Layout only (not FullRefresh).
    for i = 1, 3 do
        local def = CDM_HOOK_DEFS[i]
        if not CP[def.flag] then
            local cdm = _G[def.name]
            if cdm and cdm.HookScript then
                CP[def.flag] = true
                local myMode = def.mode
                local function _cdmRefresh()
                    -- COMBAT LOCKDOWN: zero work in combat
                    if InCombatLockdown() then
                        CP._cdmDirty = true
                        return
                    end
                    local bars = MSUF_DB and MSUF_DB.bars
                    if not bars then return end
                    if (bars.classPowerWidthMode == myMode)
                    or (bars.classPowerAnchorToCooldown == true) then
                        if CP.visible and CP._pf and CP.currentMax and CP.currentMax > 0 then
                            CP_Layout(CP._pf, CP.currentMax, CP._layoutH or (bars.classPowerHeight or 4))
                        end
                    end
                    if bars.detachedPowerBarWidthMode == myMode then
                        if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
                            _G.MSUF_ApplyPowerBarEmbedLayout_All()
                        end
                    end
                end
                cdm:HookScript("OnSizeChanged", _cdmRefresh)
                cdm:HookScript("OnShow", _cdmRefresh)
                cdm:HookScript("OnHide", _cdmRefresh)
            end
        end
    end

    -- Combat end catch-up: single relayout for any CDM width changes during combat.
    if not CP._regenHooked then
        CP._regenHooked = true
        local regenFrame = CreateFrame("Frame")
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenFrame:SetScript("OnEvent", function()
            if not CP._cdmDirty then return end
            CP._cdmDirty = false
            if CP.visible and CP._pf and CP.currentMax and CP.currentMax > 0 then
                local bars = MSUF_DB and MSUF_DB.bars
                CP_Layout(CP._pf, CP.currentMax, CP._layoutH or (bars and bars.classPowerHeight or 4))
            end
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
                _G.MSUF_ApplyPowerBarEmbedLayout_All()
            end
        end)
    end

    -- Edit mode: keep class power visible as live preview so bars-menu
    -- adjustments (width, height, offsets) are visible immediately.
    -- Alt-mana bar has no user-facing settings → stay hidden in edit mode.
    local inEditMode = (_G.MSUF_UnitEditModeActive == true)

    -- ---- ClassPower ----
    local cpEnabled = (b.showClassPower ~= false)
    local powerType, renderMode, isAuraPower = GetClassPowerType()
    local cpHeight = tonumber(b.classPowerHeight) or 4
    if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end

    -- Ele Shaman: main power bar ALWAYS shows Mana (Maelstrom is UnitPowerType default).
    -- showEleMaelstrom only controls whether the class resource bar displays Maelstrom.
    -- Flag is unconditional for Ele spec → all hot paths (UnitframeCore, Text) override pType to Mana.
    local isEleShaman = (PLAYER_CLASS == "SHAMAN" and GetSpec and GetSpec() == SPEC_SHAMAN_ELEMENTAL)
    local eleMaelChanged = ((isEleShaman or false) ~= (_G.MSUF_EleMaelstromActive == true))
    _G.MSUF_EleMaelstromActive = isEleShaman or false
    -- Force player power bar refresh so it immediately switches Mana ↔ Maelstrom
    if eleMaelChanged then
        if type(_G.MSUF_RefreshPlayerPowerBar) == "function" then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    if cpEnabled and powerType and renderMode ~= MODE_NONE then
        CP_Create(playerFrame)

        -- Resolve max power based on render mode
        local maxP
        if renderMode == MODE_RUNE_CD then
            maxP = 6  -- DK always 6 runes
        elseif renderMode == MODE_AURA_SINGLE then
            maxP = 1  -- DH Devourer: single normalized bar
        elseif renderMode == MODE_CONTINUOUS then
            maxP = 1  -- Ele Maelstrom: single continuous bar
        elseif renderMode == MODE_STAGGER then
            maxP = 1  -- Brewmaster Monk: single stagger bar (max = UnitHealthMax inside update fn)
        elseif renderMode == MODE_TIMER_BAR then
            maxP = 1  -- Ebon Might: single countdown bar
        elseif renderMode == MODE_AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                -- Maelstrom Weapon: max stacks from spell data
                maxP = 10  -- default
                if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                    local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(SPELL_MAELSTROM_WEAPON)
                    if type(spellMax) == "number" and spellMax > 0 then maxP = spellMax end
                end
            elseif powerType == "SOUL_FRAGMENTS_VENG" then
                maxP = 6  -- Vengeance: 6 soul fragment segments
            elseif powerType == "WHIRLWIND" then
                maxP = WW.MAX_STACKS  -- Warrior: 4 Whirlwind cleave stacks
            elseif powerType == "TIP_OF_THE_SPEAR" then
                maxP = TIP_MAX_STACKS  -- Survival Hunter: 3 Tip of the Spear stacks
                CP.spStacks = 0
                CP.spExpires = nil
                CP.spCachedQ = -1
            else
                maxP = 10
            end
        else
            -- Standard / Fractional: UnitPowerMax
            maxP = UnitPowerMax("player", powerType)
            if not NotSecret(maxP) or type(maxP) ~= "number" then
                -- Heuristic fallback (safe; most are 5-6)
                if powerType == PT.Runes then maxP = 6
                elseif powerType == PT.ComboPoints then maxP = 7
                else maxP = 5 end
            end
        end
        maxP = math_floor(maxP)
        if maxP < 1 then maxP = 1 end
        if maxP > MAX_CLASS_POWER then maxP = MAX_CLASS_POWER end

        CP_EnsureBars(playerFrame, maxP)
        CP_Layout(playerFrame, maxP, cpHeight)
        -- Cache layout params for lightweight CDM relayout (avoids FullRefresh)
        CP._pf = playerFrame
        CP._layoutH = cpHeight
        CP.powerType = powerType
        CP.renderMode = renderMode
        CP.isAuraPower = isAuraPower
        CP.isVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false

        -- Charged points only for standard segmented (CP/HP)
        if renderMode == MODE_SEGMENTED then
            RefreshChargedPoints()
        end

        -- Warlock: reset prediction state
        CP.wlPredDelta = 0

        -- Timer bar: start/stop OnUpdate
        if renderMode == MODE_TIMER_BAR then
            SetTimerBarOnUpdate(true)
        else
            SetTimerBarOnUpdate(false)
        end

        CP_ApplyFont()

        -- Reset container alpha before update (auto-hide in updateFn may override)
        CP.container:SetAlpha(1)

        -- Dispatch to correct update function
        local updateFn = MODE_UPDATE_FN[renderMode]
        if updateFn then
            updateFn(powerType, maxP)
        end

        CP.container:Show()
        CP.visible = true

    else
        -- Clean up rune OnUpdate scripts when hiding
        if CP.renderMode == MODE_RUNE_CD then
            for i = 1, CP.maxBars do
                local bar = CP.bars[i]
                if bar then
                    bar:SetScript("OnUpdate", nil)
                    bar._runeDuration = nil
                end
            end
        end
        -- Stop timer bar OnUpdate
        SetTimerBarOnUpdate(false)
        if CP.container then
            CP.container:SetScript("OnUpdate", nil)
            CP.container:Hide()
        end
        CP.visible = false
        CP.powerType = nil
        CP.renderMode = MODE_NONE
        CP.isAuraPower = false
        CP.isVehicle = false
        CP.wlPredDelta = 0
        CP.spStacks = 0
        CP.spExpires = nil
        CP.spCachedQ = -1
    end

    -- ---- AltMana ----
    local amEnabled = (b.showAltMana ~= false)
    local needsAlt = NeedsAltManaBar()

    if amEnabled and needsAlt and not inEditMode then
        AM_Create(playerFrame)
        AM_Layout(playerFrame)
        AM_ApplyColor()
        AM_UpdateValue()
        AM.container:Show()
        AM.visible = true
    else
        if AM.container then AM.container:Hide() end
        AM.visible = false
    end
end

-- ============================================================================
-- Event-driven updates (hot path: minimal work)
-- ============================================================================

-- ClassPower value-only update (fires on UNIT_POWER_UPDATE for player)
local function OnPowerUpdate(powerToken)
    if not CP.visible or not CP.powerType then return end
    -- Aura-based modes are driven by UNIT_AURA, not UNIT_POWER_UPDATE
    if CP.isAuraPower then return end
    -- DK Runes use RUNE_POWER_UPDATE, not UNIT_POWER_UPDATE
    if CP.renderMode == MODE_RUNE_CD then return end
    -- Timer bar: driven by OnUpdate + UNIT_AURA
    if CP.renderMode == MODE_TIMER_BAR then return end
    -- Stagger: driven by UNIT_AURA + UNIT_HEALTH, not UNIT_POWER_UPDATE
    if CP.renderMode == MODE_STAGGER then return end

    -- Quick token filter: only react to our power type
    local expectedToken = POWER_TYPE_TOKENS[CP.powerType]
    if powerToken and expectedToken and powerToken ~= expectedToken then
        return
    end

    -- Dispatch to correct update function
    local updateFn = MODE_UPDATE_FN[CP.renderMode]
    if updateFn then
        updateFn(CP.powerType, CP.currentMax)
    end
end

-- Hot path: UNIT_AURA handler for aura-based class powers (DH, Enh Shaman)
-- Also handles Balance Druid eclipse tracking and Brewmaster stagger
local function OnAuraUpdate(unit)
    -- Class power: aura-based modes
    if CP.visible and CP.isAuraPower then
        local updateFn = MODE_UPDATE_FN[CP.renderMode]
        if updateFn then
            updateFn(CP.powerType, CP.currentMax)
        end
    end
    -- Balance Druid eclipse tracking now handled by BAL module's own event frame
    -- Timer bar: Ebon Might aura applied/refreshed/removed
    if CP.visible and CP.renderMode == MODE_TIMER_BAR then
        CP.tbCachedQ = -1  -- force refresh
        CP_UpdateValues_TimerBar(CP.powerType, CP.currentMax)
    end
    -- Stagger: aura-driven (Blizzard_UnitFrame uses UNIT_AURA for stagger updates)
    if CP.visible and CP.renderMode == MODE_STAGGER then
        CP_UpdateValues_Stagger(CP.powerType, CP.currentMax)
    end
end

-- Hot path: RUNE_POWER_UPDATE handler (DK only)
local function OnRuneUpdate(runeID, energize)
    if not CP.visible or CP.renderMode ~= MODE_RUNE_CD then return end
    CP_UpdateValues_RuneCD(CP.powerType, CP.currentMax)
end

-- Spellcast handlers: Warlock prediction + Balance Druid AP prediction
local function OnSpellcastStart(spellID)
    if not CP.visible then return end
    -- Warlock: shard generator prediction
    if PLAYER_CLASS == "WARLOCK" and (CP.renderMode == MODE_SEGMENTED or CP.renderMode == MODE_FRACTIONAL) then
        OnWarlockCastStart(spellID)
    end
end

local function OnSpellcastEnd()
    if not CP.visible then return end
    -- Warlock
    if CP.wlPredDelta ~= 0 then
        OnWarlockCastEnd()
    end
end

local function OnManaUpdate()
    if not AM.visible then return end
    AM_UpdateValue()
end

-- ============================================================================
-- Event frame (single frame handles all events)
-- ============================================================================
local eventFrame = CreateFrame("Frame")

-- Throttle for rare events (spec/form changes)
local _lastFullRefresh = 0
local FULL_REFRESH_THROTTLE = 0.15

local function ThrottledFullRefresh()
    local now = GetTime()
    if now - _lastFullRefresh < FULL_REFRESH_THROTTLE then return end
    _lastFullRefresh = now
    FullRefresh()
end

-- Pre-allocated callback for deferred PBEmbedLayout re-layout after zone transitions.
-- Frame geometry may not have settled on the first FullRefresh; this second pass
-- clears the stamp cache so the detached power bar picks up final dimensions.
-- Defined once at file scope — zero closure allocations per PLAYER_ENTERING_WORLD.
local function _CP_DeferredPBRelayout()
    local fr = _G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player
    if fr and fr._msufStampCache then
        fr._msufStampCache["PBEmbedLayout"] = nil
    end
    FullRefresh()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "UNIT_POWER_UPDATE" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate()
        end
        return
    end

    if event == "UNIT_POWER_FREQUENT" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate()
        end
        return
    end

    if event == "UNIT_AURA" then
        if arg1 == "player" then
            OnAuraUpdate(arg1)
        end
        return
    end

    if event == "RUNE_POWER_UPDATE" then
        -- arg1 = runeID (1-6), arg2 = energize boolean
        OnRuneUpdate(arg1, arg2)
        return
    end

    -- Spellcast: Warlock shard prediction + Balance Druid AP prediction
    -- arg1 = unitTarget, arg2 = castGUID, arg3 = spellID
    if event == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then
            OnSpellcastStart(arg3)
        end
        return
    end
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
       or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if arg1 == "player" then
            OnSpellcastEnd()
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            -- Balance/Warlock: clear prediction on successful cast
            OnSpellcastEnd()
            -- Tip of the Spear: spell-tracked via main handler
            if CP.visible and CP.powerType == "TIP_OF_THE_SPEAR" then
                OnTipOfTheSpearSpellCast(arg3)
            end
            -- Whirlwind: handled by WW module's own event frame (no call needed here)
            -- DH Vengeance: soul fragment count changes on spellcast
            if CP.visible and CP.powerType == "SOUL_FRAGMENTS_VENG" then
                CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
            end
        end
        return
    end

    if event == "UNIT_MAXPOWER" then
        if arg1 == "player" then
            -- Max power changed → full refresh (e.g. gained/lost combo point talent)
            ThrottledFullRefresh()
        end
        return
    end

    if event == "UNIT_POWER_POINT_CHARGE" then
        if arg1 == "player" then
            -- Only relevant for standard segmented mode (CP/HP)
            if CP.renderMode == MODE_SEGMENTED then
                RefreshChargedPoints()
                if CP.visible and CP.powerType then
                    CP_UpdateValues(CP.powerType, CP.currentMax)
                end
            end
        end
        return
    end

    if event == "UNIT_DISPLAYPOWER" then
        if arg1 == "player" then
            ThrottledFullRefresh()
        end
        return
    end

    -- Stagger: health changes affect threshold colors + bar max
    if event == "UNIT_HEALTH" then
        if arg1 == "player" then
            -- CP stagger: max health = bar max, threshold recalculation
            if CP.visible and CP.renderMode == MODE_STAGGER then
                CP_UpdateValues_Stagger(CP.powerType, CP.currentMax)
            end
        end
        return
    end

    -- Vehicle enter/exit: rebuild everything (CP type may change)
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, FullRefresh)
            else
                ThrottledFullRefresh()
            end
        end
        return
    end

    -- Combat state change: re-evaluate auto-hide (OOC toggle)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if _autoHideActive and CP.visible and CP.container then
            -- Re-run the current mode's update to trigger CP_CheckAutoHide
            local fn = MODE_UPDATE_FN[CP.renderMode]
            if fn then fn(CP.powerType, CP.currentMax) end
        end
        return
    end

    -- Death/resurrection: reset spell tracker state (Sensei pattern)
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        OnSpellTrackerReset()
        if CP.visible then
            CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
        end
        return
    end

    -- Rare: rebuild on spec/form/talent changes
    if event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
    or event == "PLAYER_TALENT_UPDATE"
    or event == "TRAIT_CONFIG_UPDATED"
    or event == "UPDATE_SHAPESHIFT_FORM"
    then
        -- Use C_Timer for safety (some of these fire before DB is ready)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, FullRefresh)
        else
            FullRefresh()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        EnsureDefaults()
        -- Retry until player frame is available (fixes slow load when
        -- MSUF_UnitFrames.player isn't ready after a single fixed delay).
        local retries = 0
        local function TryRefresh()
            retries = retries + 1
            local pf = _G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player
            if pf then
                FullRefresh()
                -- Deferred re-layout: frame dimensions and CDM frames may not
                -- have settled on the first FullRefresh. Schedule a second pass
                -- that clears the PBEmbedLayout stamp so the detached power bar
                -- re-computes its width from the now-correct frame geometry.
                -- Uses pre-allocated _CP_DeferredPBRelayout (zero closures).
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.35, _CP_DeferredPBRelayout)
                end
                -- CDM frames (from another addon) may load after MSUF.
                -- Retry hook installation at increasing intervals until all 3 CDM hooks are placed.
                if C_Timer and C_Timer.After then
                    local cdmRetries = 0
                    local function TryCDMHooks()
                        cdmRetries = cdmRetries + 1
                        local allHooked = CP._ecvHooked and CP._ucvHooked and CP._bicvHooked
                        if allHooked then return end
                        -- FullRefresh installs hooks for any newly-available CDM frame.
                        FullRefresh()
                        if cdmRetries < 8 then
                            -- Backoff: 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0 (total ~18s)
                            C_Timer.After(0.5 * cdmRetries, TryCDMHooks)
                        end
                    end
                    C_Timer.After(0.5, TryCDMHooks)
                end
            elseif retries < 20 then
                -- Not ready yet — retry quickly (total max ≈ 1s)
                C_Timer.After(0.05, TryRefresh)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, TryRefresh)
        else
            FullRefresh()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureDefaults()
        return
    end
end)

-- Register events
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
eventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
-- Spellcast events: Warlock shard prediction + Balance Druid AP prediction
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")

-- ============================================================================
-- Public API (for Options, Edit Mode, and other modules)
-- ============================================================================

-- Force full refresh (call after changing DB values)
function _G.MSUF_ClassPower_Refresh()
    _cachedColorToken = nil  -- Invalidate color cache
    FullRefresh()
end

-- Refresh bar textures (call after texture change in settings)
function _G.MSUF_ClassPower_RefreshTextures()
    CP_RefreshTexture()
    AM_RefreshTexture()
end

-- Refresh class power text font (called from UpdateAllFonts)
function _G.MSUF_ClassPower_ApplyFonts()
    _cpFontRev = 0  -- force re-apply
    CP_ApplyFont()
end

-- Query state (for options UI display)
function _G.MSUF_ClassPower_GetState()
    return {
        classPowerVisible = CP.visible,
        classPowerType    = CP.powerType,
        classPowerMax     = CP.currentMax,
        renderMode        = CP.renderMode,
        isVehicle         = CP.isVehicle,
        isAuraPower       = CP.isAuraPower,
        altManaVisible    = AM.visible,
        staggerVisible    = (CP.visible and CP.renderMode == MODE_STAGGER) or false,
    }
end

-- Compatibility: hook bar texture change for live refresh.
-- Options panels should call MSUF_ClassPower_Refresh() after DB changes.
do
    -- Deferred hook: MSUF_TryApplyBarTextureLive is created in Options (LoadOnDemand).
    -- We post-hook it on first FullRefresh when it exists.
    local _texHooked = false
    local _origFullRefresh = FullRefresh
    FullRefresh = function()
        if not _texHooked then
            local origTex = _G.MSUF_TryApplyBarTextureLive
            if type(origTex) == "function" then
                _G.MSUF_TryApplyBarTextureLive = function(...)
                    origTex(...)
                    CP_RefreshTexture()
                    AM_RefreshTexture()
                end
                _texHooked = true
            end
        end
        _origFullRefresh()
    end
end

-- ============================================================================
-- Smooth Power Bar Mode
-- ============================================================================
-- The actual smooth bar logic lives in MSUF_UnitframeCore.lua (DIRECT_APPLY)
-- and MidnightSimpleUnitFrames.lua (_MSUF_Bars_SyncPower).
--
-- When enabled, those paths use raw UnitPower/UnitPowerMax + ExponentialEaseOut
-- on BOTH SetMinMaxValues AND SetValue — identical to MidnightRogueBars.
-- Secret-safe: nil-guarded, no arithmetic on return values.
--
-- This section only provides the public toggle API for the options panel.
-- ============================================================================
_G.MSUF_SmoothPowerBar_Apply = function()
    -- Refresh the cached flags in UFCore's DIRECT_APPLY hot path.
    if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then
        _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER")
    end
end
