-- MSUF_ClassPower.lua — Class Resources + Alt Mana + Stagger
-- Features:
--   1. ClassPower (segmented): Combo Points, Holy Power, Soul Shards (incl.
--      fractional for Destruction), Arcane Charges, Chi, Essence.
--   2. DK Runes: individual per-rune cooldown animation + sort order (oUF).
--   3. DH Devourer: Soul Fragments (aura-based, normalized 0-1, dual color).
--   4. Enh Shaman: Maelstrom Weapon stacks (aura-based segments).
--   5. Vehicle: auto-switch to combo points in vehicle UI.
--   6. AltMana: extra Mana bar for dual-resource specs.
--   7. Stagger: Brewmaster Monk stagger bar (3-color threshold).
-- Architecture:
--   - Self-contained: own event frame, own DB defaults, own layout.
--   - Independent overlay (Unhalted approach): no HP bar reservation.
--   - Render modes: each class/spec resolves to a render mode at FullRefresh.
--     Hot-path dispatch is a single mode check — zero branching for inactive.
--   - Secret-safe: raw UnitPower/UnitPowerMax (2 args), nil-guarded.
--   - Max performance: event-driven only (zero polling except DK rune OnUpdate
--     which runs only on recharging runes, ~1-3 max simultaneous).

-- Guard: only load once.
if _G.__MSUF_ClassPower_Loaded then return end
_G.__MSUF_ClassPower_Loaded = true

-- Perf locals (eliminate global lookups in hot paths)
local type, tonumber, pairs = type, tonumber, pairs
local math_floor = math.floor
local math_min = math.min
local string_format = string.format
local table_sort = table.sort
local CreateFrame = CreateFrame
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitPowerDisplayMod = UnitPowerDisplayMod
local UnitClass = UnitClass
local UnitStagger = UnitStagger
local UnitHealthMax = UnitHealthMax
local UnitHasVehicleUI = UnitHasVehicleUI
local GetShapeshiftFormID = GetShapeshiftFormID
local GetRuneCooldown = GetRuneCooldown
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local GetPowerRegenForPowerType = GetPowerRegenForPowerType

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

-- P0 PERF: Cached DB config (eliminates ~46 MSUF_DB traversals per event)
-- Rebuilt once per FullRefresh (login, profile switch, option change).
-- Hot-path functions read _cpDB.* instead of MSUF_DB.bars.*/general.*.
-- Secret-safe: only reads DB booleans/numbers, no secret comparisons.
local _cpDB = {
    colorByType    = true,   showCharged    = true,
    bgAlpha        = 0.3,    showPrediction = true,
    showText       = true,   fontSize       = 14,
    smooth         = true,   colorOverrides = nil,
    bgColorOverrides = nil,  bars = nil, general = nil,
    comboPointColorMode = "default",
}
local function _CP_RefreshConfig()
    local db = MSUF_DB
    if not db then return end
    local b = db.bars or {}
    local g = db.general or {}
    local cpMode = b.classPowerComboPointColorMode
    if cpMode ~= "ramp" and cpMode ~= "custom" then cpMode = "default" end
    _cpDB.bars              = b
    _cpDB.general           = g
    _cpDB.colorByType       = (b.classPowerColorByType ~= false)
    _cpDB.showCharged       = (b.showChargedComboPoints ~= false)
    _cpDB.bgAlpha           = tonumber(b.classPowerBgAlpha) or 0.3
    _cpDB.showPrediction    = (b.classPowerShowPrediction ~= false)
    _cpDB.showText          = (b.classPowerShowText ~= false)
    _cpDB.fontSize          = tonumber(b.classPowerFontSize) or 14
    _cpDB.smooth            = (b.smoothPowerBar ~= false)
    _cpDB.colorOverrides    = (type(g.classPowerColorOverrides) == "table") and g.classPowerColorOverrides or nil
    _cpDB.bgColorOverrides  = (type(g.classPowerBgColorOverrides) == "table") and g.classPowerBgColorOverrides or nil
    _cpDB.comboPointColorMode = cpMode
end

-- Spec API (12.0: C_SpecializationInfo preferred, fallback to global)
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization

-- Player class (resolved once, never changes)
local _, PLAYER_CLASS = UnitClass("player")

-- Phase 1 CP split: shared constants / profiles now live in ClassPower/*.lua
-- Keeps the core chunk smaller and reduces WoW's top-level local pressure.
local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { MODE = { NONE = 0, SEGMENTED = 1, FRACTIONAL = 2, RUNE_CD = 3, AURA_SEGMENTED = 4, AURA_SINGLE = 5, CONTINUOUS = 6, TIMER_BAR = 8, STAGGER = 9 }, SPEC = {}, SPELL = {}, BAL = {}, THRESH = {} }
local TIP = CPConst.TIP or {}
local EBON = CPConst.EBON or {}
local PT = CPConst.PT or {}
local PT_STAGGER = CPConst.PT_STAGGER or -1
local POWER_TYPE_TOKENS = CPConst.POWER_TYPE_TOKENS or {}
local CP_MODE_EVENT_PROFILE = _G.MSUF_CP_MODE_EVENT_PROFILE or {}

-- Cached split registries (load-time only; avoids repeated global table lookups
-- and keeps the post-split core wiring easier to follow).

-- ═══════════════════════════════════════════════════════════════════
-- ALT_MANA builder — registered EARLY so the consumer ~line 1134
-- (CP_CallBuilder(CPCoreBuilders.ALT_MANA, ...)) sees it at file-parse
-- time. Previous layout had this block at file bottom → builder was
-- nil when consumer ran → AM_Create/AM_Layout/AM_ApplyColor/AM_UpdateValue
-- stayed nil → FullRefresh crashed for every spec with a mana pool
-- (Shadow Priest, Druid, Monk WW, Ret Pala, Shaman Ele/Enh, Aug Evoker)
-- whenever needsAlt==true. Wrapped in do…end to scope the 'builders'
-- local (avoids shadowing the 'builders' locals at later file sections).
-- ═══════════════════════════════════════════════════════════════════
do
-- MSUF_CP_AltMana.lua
-- MSUF_CP_AltMana.lua
-- Phase 7B: move AltMana helpers out of MSUF_ClassPower.lua with minimal risk.
-- No CP value/layout/build flow moved here beyond the isolated AltMana block.

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.ALT_MANA = function(E)
    local AM = E.AM
    local _cpDB = E._cpDB
    local PT = E.PT
    local PLAYER_CLASS = E.PLAYER_CLASS
    local GetSpec = E.GetSpec
    local NotSecret = E.NotSecret
    local UnitPowerType = E.UnitPowerType
    local UnitPower = E.UnitPower
    local UnitPowerMax = E.UnitPowerMax
    local Enum = E.Enum
    local tonumber = E.tonumber or tonumber
    local CreateFrame = E.CreateFrame
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local GetBarTexture = E.GetBarTexture

    local function NeedsAltManaBar()
        if _G.MSUF_EleMaelstromActive then return false end
        if _G.MSUF_AugEvokerActive then return true end
        if _G.MSUF_ShadowManaActive then return false end
        local pType = UnitPowerType("player")
        if NotSecret(pType) then
            if pType == nil or pType == PT.Mana then return false end
        end
        local maxMana = UnitPowerMax("player", PT.Mana)
        if NotSecret(maxMana) and maxMana ~= nil and maxMana <= 0 then
            return false
        end
        if not NotSecret(pType) then
            local SPECS_NEED_ALT = {
                PRIEST  = { [3] = true },
                SHAMAN  = { [1] = true, [2] = true },
                DRUID   = { [1] = true, [2] = true, [3] = true },
                PALADIN = { [3] = true },
                MONK    = { [3] = true },
            }
            local specs = SPECS_NEED_ALT[PLAYER_CLASS]
            if not specs then return false end
            local si = GetSpec and GetSpec()
            return si and specs[si] or false
        end
        return true
    end

    local function AM_Create(playerFrame)
        if AM.container then return end

        local c = CreateFrame("Frame", "MSUF_AltManaContainer", playerFrame)
        c:SetFrameLevel(playerFrame:GetFrameLevel() + 2)
        c:Hide()
        AM.container = c

        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.4)
        AM.bgTex = bg

        local border = CreateFrame("Frame", nil, c, "BackdropTemplate")
        border:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        border:SetBackdropColor(0, 0, 0, 0)
        border:SetBackdropBorderColor(0, 0, 0, 1)
        border:SetFrameLevel(c:GetFrameLevel() + 1)
        AM._border = border

        local bar = CreateFrame("StatusBar", nil, c)
        bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
        bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
        bar:SetMinMaxValues(0, 100)
        bar:SetValue(0)
        bar:SetFrameLevel(c:GetFrameLevel() + 1)
        AM.bar = bar
    end

    local function AM_Layout(playerFrame)
        if not AM.container then return end
        local b = _cpDB.bars or {}

        local h = tonumber(b.altManaHeight) or 4
        if h < 2 then h = 2 elseif h > 30 then h = 30 end
        local oY = tonumber(b.altManaOffsetY) or -2

        AM.container:ClearAllPoints()
        AM.container:SetPoint("TOPLEFT",  playerFrame, "BOTTOMLEFT",   2, oY)
        AM.container:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -2, oY)
        AM.container:SetHeight(h)
    end

    local function AM_ApplyColor()
        if not AM.bar then return end
        local b = _cpDB.bars or {}
        local r = tonumber(b.altManaColorR) or 0.0
        local g = tonumber(b.altManaColorG) or 0.0
        local bl = tonumber(b.altManaColorB) or 0.8

        local mr, mg, mb = ResolveClassPowerColor(PT.Mana)
        if mr then r, g, bl = mr, mg, mb end

        AM.bar:SetStatusBarColor(r, g, bl, 1)
    end

    local function AM_UpdateValue()
        if not AM.bar then return end

        local cur = UnitPower("player", PT.Mana)
        local mx  = UnitPowerMax("player", PT.Mana)
        if cur == nil then cur = 0 end
        if mx  == nil then mx  = 100 end

        local smoothOn = _cpDB.smooth
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
        AM.bar:SetStatusBarTexture(GetBarTexture and GetBarTexture() or "Interface\\Buttons\\WHITE8x8")
    end

    return {
        NeedsAltManaBar = NeedsAltManaBar,
        AM_Create = AM_Create,
        AM_Layout = AM_Layout,
        AM_ApplyColor = AM_ApplyColor,
        AM_UpdateValue = AM_UpdateValue,
        AM_RefreshTexture = AM_RefreshTexture,
    }
end
end

local CPCoreBuilders = (type(_G.MSUF_CP_CORE_BUILDERS) == "table") and _G.MSUF_CP_CORE_BUILDERS or {}
local CPModeBuilders = (type(_G.MSUF_CP_MODE_BUILDERS) == "table") and _G.MSUF_CP_MODE_BUILDERS or {}
local CPFeatureBuilders = (type(_G.MSUF_CP_FEATURE_BUILDERS) == "table") and _G.MSUF_CP_FEATURE_BUILDERS or {}

local function CP_CallBuilder(builder, env)
    if type(builder) ~= "function" then return nil end
    local result = builder(env)
    return (result) and result or nil
end

local function CP_Noop() end
-- DH Vengeance: Soul Fragments via C_Spell.GetSpellCastCount (MCR-sourced)

-- Whirlwind Tracker (Sensei pattern — own event frame, event-driven render)
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

-- Phase 5 CP split: Balance Druid Astral Power prediction + eclipse colors now
-- live in ClassPower/Features/MSUF_CP_Balance.lua. The core keeps only the
-- global color invalidation hook call, so this file stays closer to a pure
-- orchestrator.

-- Hunter Survival: Tip of the Spear (talent 260285)
-- Evoker Augmentation: Ebon Might timer bar (MCR-sourced)
-- DB Defaults (self-contained; runs on every login, no-ops if keys exist)
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
    if b.classPowerComboPointColorMode == nil then b.classPowerComboPointColorMode = "default" end
    if b.classPowerShowText    == nil then b.classPowerShowText    = false end
    if b.classPowerFontSize    == nil then b.classPowerFontSize    = 16    end
    if b.classPowerShowPrediction == nil then b.classPowerShowPrediction = true end
    if b.classPowerTextOffsetX    == nil then b.classPowerTextOffsetX    = 0    end
    if b.classPowerTextOffsetY    == nil then b.classPowerTextOffsetY    = 0    end

    -- AltMana defaults
    if b.showAltMana          == nil then b.showAltMana          = false end
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
    if b.runeShowTime == nil and b.runeShowTimeText ~= nil then b.runeShowTime = b.runeShowTimeText and true or false end
    if b.runeShowTime        == nil then b.runeShowTime        = true end

    -- Ele Shaman: Maelstrom Power continuous bar (off by default — niche preference)
    if b.showEleMaelstrom     == nil then b.showEleMaelstrom     = false end
    -- Evoker Aug: Ebon Might timer bar (on by default)
    if b.showEbonMight        == nil then b.showEbonMight        = true  end
    -- Shadow Priest: show Mana as main bar, Insanity as class resource (off by default)
    if b.showShadowMana       == nil then b.showShadowMana       = false end

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

-- Power-type detection (resolved per spec/form change, cached)
-- Returns: powerType, renderMode, isAuraPower
--   powerType:   Enum.PowerType or string token for aura-based
--   renderMode:  MODE_* constant for hot-path dispatch
--   isAuraPower: true if driven by UNIT_AURA instead of UNIT_POWER_UPDATE

-- ClassPower: returns powerType, renderMode, isAuraPower
local function GetClassPowerType()
    -- Vehicle override: always combo points (oUF pattern)
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then
        local hasCP = PlayerVehicleHasComboPoints and PlayerVehicleHasComboPoints()
        if hasCP then
            return PT.ComboPoints, CPK.MODE.SEGMENTED, false
        end
        return nil, CPK.MODE.NONE, false
    end

    if PLAYER_CLASS == "DEATHKNIGHT" then
        return PT.Runes, CPK.MODE.RUNE_CD, false

    elseif PLAYER_CLASS == "ROGUE" then
        return PT.ComboPoints, CPK.MODE.SEGMENTED, false

    elseif PLAYER_CLASS == "PALADIN" then
        return PT.HolyPower, CPK.MODE.SEGMENTED, false

    elseif PLAYER_CLASS == "WARLOCK" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.WARLOCK_DESTRUCTION then
            return PT.SoulShards, CPK.MODE.FRACTIONAL, false
        end
        return PT.SoulShards, CPK.MODE.SEGMENTED, false

    elseif PLAYER_CLASS == "EVOKER" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.EVOKER_AUG then
            local b = _cpDB.bars
            if b and b.showEbonMight then
                return "EBON_MIGHT", CPK.MODE.TIMER_BAR, false
            end
        end
        return PT.Essence, CPK.MODE.SEGMENTED, false

    elseif PLAYER_CLASS == "MAGE" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.MAGE_ARCANE then return PT.ArcaneCharges, CPK.MODE.SEGMENTED, false end

    elseif PLAYER_CLASS == "MONK" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.MONK_WINDWALKER then return PT.Chi, CPK.MODE.SEGMENTED, false end
        -- Brewmaster: Stagger as class resource (3-color threshold, CDM-synced).
        -- Energy is primary → main power bar. Stagger → class power overlay.
        if spec == CPK.SPEC.MONK_BREWMASTER then
            local bb = _cpDB.bars
            if not bb or bb.showStagger ~= false then
                return PT_STAGGER, CPK.MODE.STAGGER, false
            end
        end

    elseif PLAYER_CLASS == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        -- Cat Form: Combo Points as class power (Energy is main bar)
        if form == 1 then return PT.ComboPoints, CPK.MODE.SEGMENTED, false end
        -- Balance/Boomkin: Astral Power is already the main power bar → no class power.
        -- Other forms (Bear etc.): main bar shows Rage/Mana → no secondary resource overlay.

    elseif PLAYER_CLASS == "DEMONHUNTER" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.DH_DEVOURER then
            return "SOUL_FRAGMENTS", CPK.MODE.AURA_SINGLE, true
        end
        if spec == CPK.SPEC.DH_VENGEANCE then
            return "SOUL_FRAGMENTS_VENG", CPK.MODE.AURA_SEGMENTED, true
        end

    elseif PLAYER_CLASS == "SHAMAN" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.SHAMAN_ENHANCEMENT then
            -- Only if talent is known
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(CPK.SPELL.MAELSTROM_WEAPON_TALENT) then
                return "MAELSTROM_WEAPON", CPK.MODE.AURA_SEGMENTED, true
            end
        end
        if spec == CPK.SPEC.SHAMAN_ELEMENTAL then
            local b = _cpDB.bars
            if b and b.showEleMaelstrom then
                return PT.Maelstrom, CPK.MODE.CONTINUOUS, false
            end
        end

    elseif PLAYER_CLASS == "PRIEST" then
        -- Shadow: when showShadowMana is ON, main bar shows Mana → Insanity as class resource
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.PRIEST_SHADOW then
            local b = _cpDB.bars
            if b and b.showShadowMana then
                return PT.Insanity, CPK.MODE.CONTINUOUS, false
            end
        end

    elseif PLAYER_CLASS == "WARRIOR" then
        -- All Warrior specs use Whirlwind as class resource (Fury, Arms, Prot).
        -- No talent gate: IsSpellKnown(12950) unreliable in 12.0 for passive talents.
        -- If player doesn't have Improved Whirlwind, stacks stay 0 → auto-hide handles it.
        return "WHIRLWIND", CPK.MODE.AURA_SEGMENTED, false

    elseif PLAYER_CLASS == "HUNTER" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.HUNTER_SURVIVAL then
            local known = C_SpellBook and C_SpellBook.IsSpellKnown
            if known and known(TIP.TALENT_ID) then
                return "TIP_OF_THE_SPEAR", CPK.MODE.AURA_SEGMENTED, false
            end
        end
    end
    return nil, CPK.MODE.NONE, false
end

-- Stagger detection (Brewmaster Monk only)

-- AltMana: helper declarations now bind through ClassPower/Core/MSUF_CP_AltMana.lua
local function NeedsAltManaBar()
    -- Ele Shaman: when Maelstrom is in class power, main bar shows Mana → no alt needed
    if _G.MSUF_EleMaelstromActive then return false end
    -- Aug Evoker: main bar shows Essence → Mana needs AltMana bar
    if _G.MSUF_AugEvokerActive then return true end
    -- Shadow Priest: main bar shows Mana → no AltMana needed
    if _G.MSUF_ShadowManaActive then return false end
    local pType = UnitPowerType("player")
    -- pType == 0 = Mana primary → no alt bar needed
    if NotSecret(pType) then
        if pType == nil or pType == PT.Mana then return false end
    end
    -- Must actually have a mana pool (Warriors, Rogues, DKs etc. have 0 max mana)
    local maxMana = UnitPowerMax("player", PT.Mana)
    if NotSecret(maxMana) and maxMana ~= nil and maxMana <= 0 then
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

-- Color resolution (uses MSUF's PowerBarColor override system)
local _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
local _cachedColorToken = nil
local _cachedBgColorToken = nil
local _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = 0, 0, 0
local _staggerCachedTier = 0  -- Stagger: avoid redundant SetStatusBarColor when tier unchanged

-- Maelstrom Weapon 5+ threshold color (cached independently)
local _mwAbove5R, _mwAbove5G, _mwAbove5B
local _mwAbove5Resolved = false

local function ResolveMWAbove5Color()
    if _mwAbove5Resolved then return _mwAbove5R, _mwAbove5G, _mwAbove5B end
    _mwAbove5Resolved = true
    local ov = _cpDB.colorOverrides
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
    if _cpDB.general then
        local ov = _cpDB.colorOverrides
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

local function ResolveClassPowerBgColor(powerType)
    local token = POWER_TYPE_TOKENS[powerType]
    if not token and type(powerType) == "string" then
        token = powerType
    end
    if token == _cachedBgColorToken and _cachedBgColorToken then
        return _cachedBgColorR, _cachedBgColorG, _cachedBgColorB
    end
    _cachedBgColorToken = token

    if _cpDB.general then
        local ov = _cpDB.bgColorOverrides
        if type(ov) == "table" and token then
            local c = ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = r, g, b
                    return r, g, b
                end
            end
        end
    end

    _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = 0, 0, 0
    return 0, 0, 0
end

-- Public: invalidate class power color cache (called from Colors panel)
_G.MSUF_ClassPower_InvalidateColors = function()
    _cachedColorToken = nil
    _cachedBgColorToken = nil
    _cachedChargedR = nil  -- also invalidate charged cache
    _staggerCachedTier = 0  -- force stagger color re-apply
    _mwAbove5Resolved = false  -- force MW threshold color re-resolve
    -- Balance Druid: refresh eclipse + prediction overlay colors
    if _G.MSUF_BAL_InvalidateColors then
        _G.MSUF_BAL_InvalidateColors()
    end
    if _G.MSUF_ClassPower_Refresh then
        _G.MSUF_ClassPower_Refresh()
    end
end

-- Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
-- GetUnitChargedPowerPoints("player") returns a table of 1-based indices
-- that represent which combo point slots are "charged". These are non-secret
-- in WoW 12.0 builds.
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
    if _cpDB.general then
        local ov = _cpDB.colorOverrides
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

local COMBO_POINT_SLOT_TOKENS = {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}
local COMBO_POINT_RAMP_R = { 0.00, 0.00, 1.00, 1.00, 1.00, 1.00, 1.00 }
local COMBO_POINT_RAMP_G = { 0.95, 0.95, 1.00, 1.00, 1.00, 0.05, 0.05 }
local COMBO_POINT_RAMP_B = { 1.00, 1.00, 0.00, 0.00, 0.00, 0.05, 0.05 }

local function ResolveComboPointSlotColor(slot)
    local mode = _cpDB.comboPointColorMode
    if mode ~= "ramp" and mode ~= "custom" then return nil end

    slot = tonumber(slot) or 1
    if slot < 1 then slot = 1 elseif slot > 7 then slot = 7 end

    if mode == "custom" then
        local ov = _cpDB.colorOverrides
        local c = ov and ov[COMBO_POINT_SLOT_TOKENS[slot]]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end

    return COMBO_POINT_RAMP_R[slot], COMBO_POINT_RAMP_G[slot], COMBO_POINT_RAMP_B[slot]
end

-- ClassPower visual: segmented bars (created lazily on player frame)
-- Scale-compensated width helper lives in ClassPower/Core/MSUF_CP_Presentation.lua
local CDM_GetScaledWidth

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
    renderMode = CPK.MODE.NONE,  -- active render mode
    isAuraPower = false, -- true → driven by UNIT_AURA
    updateFn   = nil,    -- cached active mode update fn (avoids hot-path table lookups)
    modeProfile = nil,   -- cached active mode event profile for lite runtime bindings
    structuralSig = nil, -- cached structural signature for cheap rare/display-power checks
    isVehicle = false,   -- true → vehicle combo points active
    visible   = false,
    height    = 4,
    -- Warlock shard prediction state (Jay's approach: predicted post-cast value)
    wlPredDelta = 0,       -- shard delta for active cast (0 = no prediction)
    -- Timer Bar state (Ebon Might)
    tbCachedQ   = -1,      -- quantized percentage for skip-if-same
    tbOUA       = false,   -- true if timer-bar OnUpdate is active
    runeOUAAny  = false,   -- true if any rune bar currently has an OnUpdate
    essenceOUAAny = false, -- true if Essence recharge pip has an OnUpdate
    powerToken  = nil,     -- cached POWER_TYPE_TOKENS[powerType] for hot event filters
    -- Spell Tracker state (Tip of the Spear only — Whirlwind uses WW module)
    spStacks    = 0,       -- current stack count
    spExpires   = nil,     -- GetTime() expiry timestamp (nil = no timer)
    spCachedQ   = -1,      -- skip-if-same quantizer
}

-- DK Rune map: [display_slot] = rune_id (1-6), sorted per sortOrder
local _runeMap = { 1, 2, 3, 4, 5, 6 }
local _runeAppliedSortOrder = "natural"

local function CP_ApplyRuneSortOrder(sortOrder)
    local wanted = (sortOrder == "asc" or sortOrder == "desc") and sortOrder or "natural"
    if _runeAppliedSortOrder == wanted then return end

    if wanted == "asc" then
        table_sort(_runeMap, _runeAscSort)
    elseif wanted == "desc" then
        table_sort(_runeMap, _runeDescSort)
    else
        for i = 1, 6 do _runeMap[i] = i end
    end

    _runeAppliedSortOrder = wanted
end

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

local CP_EnsureBars
local CP_Create

do
    local build = CP_CallBuilder(CPCoreBuilders.BUILD, {
            CP = CP,
            _cpDB = _cpDB,
            CreateFrame = CreateFrame,
            CP_ResolveTexture = CP_ResolveTexture,
        })
    if build then
        CP_EnsureBars = build.CP_EnsureBars or CP_EnsureBars
        CP_Create = build.CP_Create or CP_Create
    end
end

-- Font / text-offset presentation helpers now live in
-- ClassPower/Core/MSUF_CP_Presentation.lua.
local CP_ApplyTextOffset
local CP_ApplyFont
local CP_ApplyColors
local CP_RefreshTexture

-- Cached alpha values (resolved once in FullRefresh, used in hot paths)
local _filledAlpha = 1.0
local _emptyAlpha  = 0.3

-- Auto-Hide: visibility check after each update (OOC / Full / Empty)
-- Zero overhead when all three are disabled (early-out on first check).
local _autoHideActive = false  -- true if any auto-hide option is enabled

local function CP_CheckAutoHide(cur, maxP)
    if not _autoHideActive or not CP.visible then return end
    if not CP.container then return end

    local b = _cpDB.bars or {}

    -- OOC: hide when out of combat
    if b.classPowerHideOOC and not InCombatLockdown() then
        CP.container:SetAlpha(0)
        return
    end

    -- Full: hide when all resources are at max
    if b.classPowerHideWhenFull and cur ~= nil and maxP ~= nil then
        -- Only check with non-secret values
        if NotSecret(cur) and cur ~= nil and maxP ~= nil then
            if cur >= maxP and maxP > 0 then
                CP.container:SetAlpha(0)
                return
            end
        end
    end

    -- Empty: hide when zero resources
    if b.classPowerHideWhenEmpty and cur ~= nil then
        if NotSecret(cur) and cur ~= nil then
            if cur <= 0 then
                CP.container:SetAlpha(0)
                return
            end
        end
    end

    -- Visible: restore alpha
    CP.container:SetAlpha(1)
end

local CP_Layout

do
    local layout = CP_CallBuilder(CPCoreBuilders.LAYOUT, {
            CP = CP,
            _cpDB = _cpDB,
            CPConst = CPConst,
            math_floor = math_floor,
            tonumber = tonumber,
            CreateFrame = CreateFrame,
            ResolveClassPowerBgColor = ResolveClassPowerBgColor,
            GetFilledAlpha = function() return _filledAlpha end,
            SetFilledAlpha = function(v) _filledAlpha = v end,
            GetEmptyAlpha = function() return _emptyAlpha end,
            SetEmptyAlpha = function(v) _emptyAlpha = v end,
            GetAutoHideActive = function() return _autoHideActive end,
            SetAutoHideActive = function(v) _autoHideActive = v end,
            GetCDMScaledWidth = function() return CDM_GetScaledWidth or _G.MSUF_CDM_GetScaledWidth end,
        })
    if layout then
        CP_Layout = layout.CP_Layout or CP_Layout
    end
end

-- Secret-safe value update + per-bar coloring (charged/empowered support)
-- Phase 2 CP split: segmented / fractional / aura mode runners now live in
-- ClassPower/Modes/*.lua. The core builds them with local env closures so the
-- public runtime stays identical while the main chunk gets smaller.
local CP_UpdateValues
local CP_UpdateValues_Fractional
local CP_UpdateValues_AuraSegmented
local CP_UpdateValues_AuraSingle
local CP_UpdateValues_Continuous
local CP_UpdateValues_RuneCD
local CP_UpdateValues_TimerBar
local CP_UpdateValues_Stagger
local CP_StopEssenceOnUpdates
local _essenceRuntimeTick

do
    local commonEnv = {
        CP = CP,
        _cpDB = _cpDB,
        CPConst = CPConst,
        CPK = CPK,
        PT = PT,
        PLAYER_CLASS = PLAYER_CLASS,
        UnitPower = UnitPower,
        UnitPowerDisplayMod = UnitPowerDisplayMod,
        C_UnitAuras = C_UnitAuras,
        C_Spell = C_Spell,
        GetSpec = GetSpec,
        GetTime = GetTime,
        NotSecret = NotSecret,
        ResolveClassPowerColor = ResolveClassPowerColor,
        ResolveClassPowerBgColor = ResolveClassPowerBgColor,
        ResolveChargedColor = ResolveChargedColor,
        ResolveComboPointSlotColor = ResolveComboPointSlotColor,
        ResolveMWAbove5Color = ResolveMWAbove5Color,
        CP_CheckAutoHide = CP_CheckAutoHide,
        WW = WW,
        TIP = TIP,
        GetFilledAlpha = function() return _filledAlpha end,
        GetEmptyAlpha = function() return _emptyAlpha end,
        GetChargedMap = function() return _chargedMap end,
        GetPowerRegenForPowerType = GetPowerRegenForPowerType,
    }
    local segmented = CP_CallBuilder(CPModeBuilders.SEGMENTED, commonEnv)
    if segmented and type(segmented.Update) == "function" then CP_UpdateValues = segmented.Update end
    if segmented and type(segmented.StopEssenceOnUpdates) == "function" then CP_StopEssenceOnUpdates = segmented.StopEssenceOnUpdates end
    if segmented and type(segmented.RuntimeTick) == "function" then _essenceRuntimeTick = segmented.RuntimeTick end
    local fractional = CP_CallBuilder(CPModeBuilders.FRACTIONAL, commonEnv)
    if fractional and type(fractional.Update) == "function" then CP_UpdateValues_Fractional = fractional.Update end
    local aura = CP_CallBuilder(CPModeBuilders.AURA, commonEnv)
    if aura then
        if type(aura.UpdateSegmented) == "function" then CP_UpdateValues_AuraSegmented = aura.UpdateSegmented end
        if type(aura.UpdateSingle) == "function" then CP_UpdateValues_AuraSingle = aura.UpdateSingle end
        if type(aura.BuildWWRender) == "function" then _wwRender = aura.BuildWWRender() end
    end

    commonEnv.UnitPower = UnitPower
    commonEnv.UnitPowerMax = UnitPowerMax
    local continuous = CP_CallBuilder(CPModeBuilders.CONTINUOUS, commonEnv)
    if continuous and type(continuous.Update) == "function" then CP_UpdateValues_Continuous = continuous.Update end

    commonEnv.NotSecret = NotSecret
    commonEnv.UnitStagger = UnitStagger
    commonEnv.UnitHealthMax = UnitHealthMax
    commonEnv.STAGGER_CONST = CPConst.STAGGER or {}
    local stagger = CP_CallBuilder(CPModeBuilders.STAGGER, commonEnv)
    if stagger and type(stagger.Update) == "function" then CP_UpdateValues_Stagger = stagger.Update end
end

-- Phase 7A CP split: pure presentation helpers now live in
-- ClassPower/Core/MSUF_CP_Presentation.lua. This keeps the core smaller without
-- touching build/layout/value flow.
do
    local presentation = CP_CallBuilder(CPCoreBuilders.PRESENTATION, {
            CP = CP,
            _cpDB = _cpDB,
            PT = PT,
            math_floor = math_floor,
            tonumber = tonumber,
            ResolveClassPowerColor = ResolveClassPowerColor,
            CP_ResolveTexture = CP_ResolveTexture,
            GetUpdateFn = function() return CP_UpdateValues end,
        })
    if presentation then
        CDM_GetScaledWidth = presentation.CDM_GetScaledWidth or CDM_GetScaledWidth
        CP_ApplyTextOffset = presentation.CP_ApplyTextOffset or CP_ApplyTextOffset
        CP_ApplyFont = presentation.CP_ApplyFont or CP_ApplyFont
        CP_ApplyColors = presentation.CP_ApplyColors or CP_ApplyColors
        CP_RefreshTexture = presentation.CP_RefreshTexture or CP_RefreshTexture
    end
end
_G.MSUF_CDM_GetScaledWidth = CDM_GetScaledWidth

-- Legacy color-only refresh / texture refresh now live in
-- ClassPower/Core/MSUF_CP_Presentation.lua.

-- CPK.MODE.FRACTIONAL: Destruction Warlock — partial Soul Shard fill (oUF pattern)
-- UnitPower(unit, type, true) / UnitPowerDisplayMod(type) gives e.g. 3.7
-- Fractional mode runner moved to ClassPower/Modes/MSUF_CP_Mode_Fractional.lua

-- CPK.MODE.RUNE_CD / CPK.MODE.TIMER_BAR
-- Phase 3 CP split: rune + timer mode runners now live in
-- ClassPower/Modes/MSUF_CP_Mode_Rune.lua and MSUF_CP_Mode_Timer.lua.
-- Unified CP tick: single OnUpdate frame drives all mode animations.
local CP_StopRuneOnUpdates
local SetTimerBarOnUpdate

-- Central CP runtime tick (unified driver for Rune/Essence/Timer animations).
local _cpTickFrame
local _cpTickActive = false
local _cpTickFn = nil

local function CP_CentralTickOnUpdate(_, elapsed)
    if _cpTickFn then _cpTickFn(elapsed) end
end

local function CP_StartCentralTick(tickFn)
    _cpTickFn = tickFn
    if not _cpTickActive then
        if not _cpTickFrame then _cpTickFrame = CreateFrame("Frame") end
        _cpTickFrame:SetScript("OnUpdate", CP_CentralTickOnUpdate)
        _cpTickActive = true
    elseif _cpTickFn ~= tickFn then
        -- Mode switch mid-tick: just swap function, no SetScript churn.
    end
end

local function CP_StopCentralTick()
    if not _cpTickActive then return end
    _cpTickFn = nil
    _cpTickFrame:SetScript("OnUpdate", nil)
    _cpTickActive = false
end

local _runeRuntimeTick
local _timerRuntimeTick

do
    local commonEnv = {
        CP = CP,
        _cpDB = _cpDB,
        CPK = CPK,
        EBON = EBON,
        C_UnitAuras = C_UnitAuras,
        GetTime = GetTime,
        GetRuneCooldown = GetRuneCooldown,
        UnitHasVehicleUI = UnitHasVehicleUI,
        ResolveClassPowerColor = ResolveClassPowerColor,
        ResolveClassPowerBgColor = ResolveClassPowerBgColor,
        CP_CheckAutoHide = CP_CheckAutoHide,
        CP_ApplyRuneSortOrder = CP_ApplyRuneSortOrder,
        GetRuneMap = function() return _runeMap end,
        GetFilledAlpha = function() return _filledAlpha end,
        GetEmptyAlpha = function() return _emptyAlpha end,
    }

    local rune = CP_CallBuilder(CPModeBuilders.RUNE, commonEnv)
    if rune then
        if type(rune.Update) == "function" then CP_UpdateValues_RuneCD = rune.Update end
        if type(rune.StopOnUpdates) == "function" then CP_StopRuneOnUpdates = rune.StopOnUpdates end
        if type(rune.RuntimeTick) == "function" then _runeRuntimeTick = rune.RuntimeTick end
    end

    local timer = CP_CallBuilder(CPModeBuilders.TIMER, commonEnv)
    if timer then
        if type(timer.Update) == "function" then CP_UpdateValues_TimerBar = timer.Update end
        if type(timer.SetOnUpdate) == "function" then SetTimerBarOnUpdate = timer.SetOnUpdate end
        if type(timer.RuntimeTick) == "function" then _timerRuntimeTick = timer.RuntimeTick end
    end
end

local function CP_SyncRuntimeOnUpdates(timerActive)
    local mode = CP.renderMode

    -- Determine active tick function based on current mode + animation state.
    if mode == CPK.MODE.RUNE_CD then
        -- Rune mode: stop others, tick runes if any active.
        if CP.essenceOUAAny and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if CP.runeOUAAny and _runeRuntimeTick then
            CP_StartCentralTick(_runeRuntimeTick)
        else
            CP_StopCentralTick()
        end
        return
    end

    -- Not rune mode: stop rune animations.
    if CP.runeOUAAny and CP_StopRuneOnUpdates then
        CP_StopRuneOnUpdates(false)
    end

    if mode == CPK.MODE.TIMER_BAR then
        if CP.essenceOUAAny and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if SetTimerBarOnUpdate then SetTimerBarOnUpdate(timerActive == true) end
        if timerActive and _timerRuntimeTick then
            CP_StartCentralTick(_timerRuntimeTick)
        else
            CP_StopCentralTick()
        end
    else
        if SetTimerBarOnUpdate then SetTimerBarOnUpdate(false) end
        -- SEGMENTED mode: essence may tick.
        if CP.essenceOUAAny and _essenceRuntimeTick then
            CP_StartCentralTick(_essenceRuntimeTick)
        else
            CP_StopCentralTick()
        end
    end
end

local CP_RunActiveUpdate

-- Phase 5 CP split: class/resource specials now live in
-- ClassPower/Features/MSUF_CP_Specials.lua. The core builds the handlers from a
-- small feature builder so event wiring stays identical while class-specific
-- logic stops bloating the orchestrator chunk.
local OnWarlockCastStart
local OnWarlockCastEnd
local OnTipOfTheSpearSpellCast
local OnSpellTrackerReset
local CP_GetResolvedVisibleMax
local CP_RefreshVisibleModeLight
local OnPowerUpdate
local OnAuraUpdate
local OnRuneUpdate
local OnSpellcastStart
local OnSpellcastEnd
local OnManaUpdate
local CP_HandleMaxPowerEvent
local CP_HandleDisplayPowerEvent
local CP_HandleRareStructuralEvent

do
    local specials = CP_CallBuilder(CPFeatureBuilders.SPECIALS, {
            CP = CP,
            _cpDB = _cpDB,
            CPConst = CPConst,
            TIP = TIP,
            PLAYER_CLASS = PLAYER_CLASS,
            GetSpec = GetSpec,
            GetTime = GetTime,
            math_min = math_min,
            C_SpellBook = C_SpellBook,
            RunActiveUpdate = function() return CP_RunActiveUpdate(CP.powerType, CP.currentMax) end,
            RunAuraSegmentedUpdate = function()
                if CP_UpdateValues_AuraSegmented then
                    return CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
                end
            end,
        })
    if specials then
        OnWarlockCastStart = specials.OnWarlockCastStart
        OnWarlockCastEnd = specials.OnWarlockCastEnd
        OnTipOfTheSpearSpellCast = specials.OnTipOfTheSpearSpellCast
        OnSpellTrackerReset = specials.OnSpellTrackerReset
    end

    OnWarlockCastStart = OnWarlockCastStart or CP_Noop
    OnWarlockCastEnd = OnWarlockCastEnd or CP_Noop
    OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast or CP_Noop
    OnSpellTrackerReset = OnSpellTrackerReset or CP_Noop
end

-- Phase 4 CP split: continuous + stagger mode runners now live in
-- ClassPower/Modes/MSUF_CP_Mode_Continuous.lua and MSUF_CP_Mode_Stagger.lua.
-- The core keeps only orchestration and event wiring, while the heavy single-bar
-- runners live outside the main chunk.

-- Update function dispatch table (set in FullRefresh, called in hot path)
local MODE_UPDATE_FN = {
    [CPK.MODE.SEGMENTED]      = CP_UpdateValues,
    [CPK.MODE.FRACTIONAL]     = CP_UpdateValues_Fractional,
    [CPK.MODE.RUNE_CD]        = CP_UpdateValues_RuneCD,
    [CPK.MODE.AURA_SEGMENTED] = CP_UpdateValues_AuraSegmented,
    [CPK.MODE.AURA_SINGLE]    = CP_UpdateValues_AuraSingle,
    [CPK.MODE.CONTINUOUS]     = CP_UpdateValues_Continuous,
    [CPK.MODE.TIMER_BAR]      = CP_UpdateValues_TimerBar,
    [CPK.MODE.STAGGER]        = CP_UpdateValues_Stagger,
}

local function CP_GetModeEventProfile(renderMode, powerType, isAuraPower)
    local base = CP_MODE_EVENT_PROFILE[renderMode] or CP_MODE_EVENT_PROFILE[CPK.MODE.NONE]
    local profile = {
        power = base.power == true,
        maxPower = base.maxPower == true,
        aura = (base.aura == true) or (isAuraPower == true),
        rune = base.rune == true,
        health = base.health == true,
        pointCharge = base.pointCharge == true,
        warlockPred = (base.warlockPred == true) and PLAYER_CLASS == "WARLOCK",
        spellSucceeded = false,
        deadAlive = false,
    }
    profile.spellSucceeded = profile.warlockPred
        or (powerType == "TIP_OF_THE_SPEAR")
        or (powerType == "SOUL_FRAGMENTS_VENG")
    profile.deadAlive = (powerType == "TIP_OF_THE_SPEAR")
    return profile
end

CP_RunActiveUpdate = function(powerType, maxP)
    local updateFn = CP.updateFn
    if not updateFn then return false end
    local timerActive = (updateFn(powerType or CP.powerType, maxP or CP.currentMax) == true)
    CP_SyncRuntimeOnUpdates(timerActive)
    return timerActive
end

local function CP_ComputeStructuralSignature()
    local b = _cpDB.bars or {}
    local newPowerType, newRenderMode, newAuraPower = GetClassPowerType()
    local newVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
    local wantCPVisible = (b.showClassPower ~= false) and newPowerType and newRenderMode ~= CPK.MODE.NONE
    local wantAMVisible = (b.showAltMana == true) and NeedsAltManaBar() and (_G.MSUF_UnitEditModeActive ~= true)
    return table.concat({
        wantCPVisible and 1 or 0,
        wantAMVisible and 1 or 0,
        tostring(newPowerType or "nil"),
        tostring(newRenderMode or CPK.MODE.NONE),
        newAuraPower and 1 or 0,
        newVehicle and 1 or 0,
    }, "|")
end

-- Forward declaration (AM defined later)
local AM

-- AltMana visual: single StatusBar (created lazily on player frame)
AM = {
    bar       = nil,
    container = nil,
    bgTex     = nil,
    visible   = false,
}

local AM_Create
local AM_Layout
local AM_ApplyColor
local AM_UpdateValue
local AM_RefreshTexture

do
    local altMana = CP_CallBuilder(CPCoreBuilders.ALT_MANA, {
            AM = AM,
            _cpDB = _cpDB,
            PT = PT,
            PLAYER_CLASS = PLAYER_CLASS,
            GetSpec = GetSpec,
            NotSecret = NotSecret,
            UnitPowerType = UnitPowerType,
            UnitPower = UnitPower,
            UnitPowerMax = UnitPowerMax,
            Enum = Enum,
            tonumber = tonumber,
            CreateFrame = CreateFrame,
            ResolveClassPowerColor = ResolveClassPowerColor,
            GetBarTexture = function()
                local getTexture = _G.MSUF_GetBarTexture
                return getTexture and getTexture() or "Interface\\Buttons\\WHITE8x8"
            end,
        })
    if altMana then
        NeedsAltManaBar = altMana.NeedsAltManaBar or NeedsAltManaBar
        AM_Create = altMana.AM_Create or AM_Create
        AM_Layout = altMana.AM_Layout or AM_Layout
        AM_ApplyColor = altMana.AM_ApplyColor or AM_ApplyColor
        AM_UpdateValue = altMana.AM_UpdateValue or AM_UpdateValue
        AM_RefreshTexture = altMana.AM_RefreshTexture or AM_RefreshTexture
    end
end

-- Master show/hide + layout integration

local function GetPlayerFrame()
    return _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player) or nil
end

-- Full refresh (called on spec change, form change, config change)
local CP_RefreshEventBindings
local function FullRefresh()
    if not MSUF_DB then return end
    _CP_RefreshConfig()  -- P0: rebuild cached config
    local b = _cpDB.bars or {}
    local playerFrame = GetPlayerFrame()
    if not playerFrame then return end

    -- Hook player frame resize → relayout bars inside the container.
    -- Container auto-stretches via dual-point anchoring, but individual
    -- bars use calculated pixel positions that need recalculating.
    if not playerFrame._msufCPSizeHooked then
        playerFrame._msufCPSizeHooked = true
        playerFrame:HookScript("OnSizeChanged", function()
            if _G.MSUF_ClassPower_Refresh then
                _G.MSUF_ClassPower_Refresh()
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
    local isEleShaman = (PLAYER_CLASS == "SHAMAN" and GetSpec and GetSpec() == CPK.SPEC.SHAMAN_ELEMENTAL)
    local eleMaelChanged = ((isEleShaman or false) ~= (_G.MSUF_EleMaelstromActive == true))
    _G.MSUF_EleMaelstromActive = isEleShaman or false
    -- Force player power bar refresh so it immediately switches Mana ↔ Maelstrom
    if eleMaelChanged then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    -- Aug Evoker: when Ebon Might is the CP class resource, main power bar shows Essence
    -- instead of Mana. Mana moves to AltMana bar. Same pattern as Ele Shaman.
    local isAugEvokerEB = (PLAYER_CLASS == "EVOKER" and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
        and b.showEbonMight ~= false)
    local augChanged = ((isAugEvokerEB or false) ~= (_G.MSUF_AugEvokerActive == true))
    _G.MSUF_AugEvokerActive = isAugEvokerEB or false
    if augChanged then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    -- Shadow Priest: when showShadowMana is ON, main power bar shows Mana
    -- instead of Insanity. Insanity moves to CP class resource (CONTINUOUS).
    local isShadowMana = (PLAYER_CLASS == "PRIEST" and GetSpec and GetSpec() == CPK.SPEC.PRIEST_SHADOW
        and b.showShadowMana == true)
    local shadowChanged = ((isShadowMana or false) ~= (_G.MSUF_ShadowManaActive == true))
    _G.MSUF_ShadowManaActive = isShadowMana or false
    if shadowChanged then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    if cpEnabled and powerType and renderMode ~= CPK.MODE.NONE then
        CP_Create(playerFrame)

        -- Resolve max power based on render mode
        local maxP
        if renderMode == CPK.MODE.RUNE_CD then
            maxP = 6  -- DK always 6 runes
        elseif renderMode == CPK.MODE.AURA_SINGLE then
            maxP = 1  -- DH Devourer: single normalized bar
        elseif renderMode == CPK.MODE.CONTINUOUS then
            maxP = 1  -- Ele Maelstrom: single continuous bar
        elseif renderMode == CPK.MODE.STAGGER then
            maxP = 1  -- Brewmaster Monk: single stagger bar (max = UnitHealthMax inside update fn)
        elseif renderMode == CPK.MODE.TIMER_BAR then
            maxP = 1  -- Ebon Might: single countdown bar
        elseif renderMode == CPK.MODE.AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                -- Maelstrom Weapon: max stacks from spell data
                maxP = 10  -- default
                if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                    local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.MAELSTROM_WEAPON)
                    if type(spellMax) == "number" and spellMax > 0 then maxP = spellMax end
                end
            elseif powerType == "SOUL_FRAGMENTS_VENG" then
                maxP = 6  -- Vengeance: 6 soul fragment segments
            elseif powerType == "WHIRLWIND" then
                maxP = WW.MAX_STACKS  -- Warrior: 4 Whirlwind cleave stacks
            elseif powerType == "TIP_OF_THE_SPEAR" then
                maxP = TIP.MAX_STACKS  -- Survival Hunter: 3 Tip of the Spear stacks
                CP.spStacks = 0
                CP.spExpires = nil
                CP.spCachedQ = -1
            else
                maxP = 10
            end
        else
            -- Standard / Fractional: UnitPowerMax
            maxP = UnitPowerMax("player", powerType)
            if not NotSecret(maxP) or maxP == nil then
                -- Heuristic fallback (safe; most are 5-6)
                if powerType == PT.Runes then maxP = 6
                elseif powerType == PT.ComboPoints then maxP = 7
                else maxP = 5 end
            end
        end
        maxP = math_floor(maxP)
        if maxP < 1 then maxP = 1 end
        if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end

        CP_EnsureBars(playerFrame, maxP)
        CP._outlineEdge = -1  -- force outline rebuild on mode/size changes
        CP_Layout(playerFrame, maxP, cpHeight)
        -- Cache layout params for lightweight CDM relayout (avoids FullRefresh)
        CP._pf = playerFrame
        CP._layoutH = cpHeight
        CP.powerType = powerType
        CP.powerToken = POWER_TYPE_TOKENS[powerType]
        CP.renderMode = renderMode
        CP.isAuraPower = isAuraPower
        CP.isVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
        CP.updateFn = MODE_UPDATE_FN[renderMode]
        CP.modeProfile = CP_GetModeEventProfile(renderMode, powerType, isAuraPower)

        -- Charged points only for standard segmented (CP/HP)
        if renderMode == CPK.MODE.SEGMENTED then
            RefreshChargedPoints()
        end

        -- Warlock: reset prediction state
        CP.wlPredDelta = 0

        -- Runtime OnUpdate policy: only the active mode may keep a tick path alive.
        if renderMode ~= CPK.MODE.RUNE_CD and CP_StopRuneOnUpdates then
            CP_StopRuneOnUpdates(true)
        end
        if renderMode ~= CPK.MODE.TIMER_BAR and SetTimerBarOnUpdate then
            SetTimerBarOnUpdate(false)
        end
        if (renderMode ~= CPK.MODE.SEGMENTED or powerType ~= PT.Essence) and CP_StopEssenceOnUpdates then
            CP_StopEssenceOnUpdates()
        end

        CP_ApplyFont()

        -- Reset container alpha before update (auto-hide in updateFn may override)
        CP.container:SetAlpha(1)

        -- Dispatch to correct update function
        CP_RunActiveUpdate(powerType, maxP)

        CP.container:Show()
        CP.visible = true
        -- Belt-and-suspenders: ensure outline survives parent Hide/Show cycle
        if CP._outline then CP._outline:Show() end

    else
        -- Clean up rune/timer/essence OnUpdate scripts when hiding
        if (CP.renderMode == CPK.MODE.RUNE_CD or CP.runeOUAAny) and CP_StopRuneOnUpdates then
            CP_StopRuneOnUpdates(true)
        end
        if SetTimerBarOnUpdate then SetTimerBarOnUpdate(false) end
        if CP.essenceOUAAny and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        CP_StopCentralTick()
        if CP.container then
            CP.container:Hide()
        end
        CP.visible = false
        CP.powerType = nil
        CP.powerToken = nil
        CP.renderMode = CPK.MODE.NONE
        CP.isAuraPower = false
        CP.isVehicle = false
        CP.updateFn = nil
        CP.modeProfile = nil
        CP.wlPredDelta = 0
        CP.spStacks = 0
        CP.spExpires = nil
        CP.spCachedQ = -1
    end

    -- ---- AltMana ----
    local amEnabled = (b.showAltMana == true)
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

    CP.structuralSig = CP_ComputeStructuralSignature()
    CP_RefreshEventBindings()
end

-- Event-driven updates (hot path: minimal work)
-- Runtime handlers now come from the CP runtime feature builder below.

-- Phase 6 CP split: runtime/light-refresh handlers now live in
-- ClassPower/Features/MSUF_CP_Runtime.lua. The core keeps event-frame wiring,
-- while hot-path glue and structural light-refresh helpers live in a separate
-- feature builder to keep the orchestrator chunk thin.

local ThrottledFullRefresh
local CP_ShouldUseLiteBindings

-- Event frame (single frame handles all events)
local eventFrame = CreateFrame("Frame")

-- Throttle for rare events (spec/form changes)
local _lastFullRefresh = 0
local FULL_REFRESH_THROTTLE = 0.15

ThrottledFullRefresh = function()
    local now = GetTime()
    if now - _lastFullRefresh < FULL_REFRESH_THROTTLE then return end
    _lastFullRefresh = now
    FullRefresh()
end

do
    local runtime = CP_CallBuilder(CPFeatureBuilders.RUNTIME, {
            CP = CP,
            AM = AM,
            _cpDB = _cpDB,
            CPK = CPK,
            PT = PT,
            TIP = TIP,
            WW = WW,
            CPConst = CPConst,
            POWER_TYPE_TOKENS = POWER_TYPE_TOKENS,
            PLAYER_CLASS = PLAYER_CLASS,
            UnitPowerMax = UnitPowerMax,
            NotSecret = NotSecret,
            C_Spell = C_Spell,
            tonumber = tonumber,
            math_floor = math_floor,
            C_Timer = C_Timer,
            GetPlayerFrame = GetPlayerFrame,
            CP_EnsureBars = CP_EnsureBars,
            CP_Layout = CP_Layout,
            RefreshChargedPoints = RefreshChargedPoints,
            RunActiveUpdate = function(powerType, maxP) return CP_RunActiveUpdate(powerType, maxP) end,
            RunAuraSegmentedUpdate = function()
                if CP_UpdateValues_AuraSegmented then
                    return CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
                end
            end,
            AM_UpdateValue = AM_UpdateValue,
            CP_ComputeStructuralSignature = CP_ComputeStructuralSignature,
            CP_RefreshEventBindings = function() return CP_RefreshEventBindings() end,
            ThrottledFullRefresh = function() return ThrottledFullRefresh() end,
            FullRefresh = function() return FullRefresh() end,
            SetTimerBarOnUpdate = SetTimerBarOnUpdate,
            CP_SyncRuntimeOnUpdates = CP_SyncRuntimeOnUpdates,
            CP_ShouldUseLiteBindings = function() return CP_ShouldUseLiteBindings() end,
            CP_UpdateValues_TimerBar = CP_UpdateValues_TimerBar,
            CP_UpdateValues_Stagger = CP_UpdateValues_Stagger,
            CP_UpdateValues_RuneCD = CP_UpdateValues_RuneCD,
            OnWarlockCastStart = OnWarlockCastStart,
            OnWarlockCastEnd = OnWarlockCastEnd,
            OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast,
            OnSpellTrackerReset = OnSpellTrackerReset,
        })
    if runtime then
        CP_GetResolvedVisibleMax = runtime.GetResolvedVisibleMax
        CP_RefreshVisibleModeLight = runtime.RefreshVisibleModeLight
        OnPowerUpdate = runtime.OnPowerUpdate
        OnAuraUpdate = runtime.OnAuraUpdate
        OnRuneUpdate = runtime.OnRuneUpdate
        OnSpellcastStart = runtime.OnSpellcastStart
        OnSpellcastEnd = runtime.OnSpellcastEnd
        OnManaUpdate = runtime.OnManaUpdate
        CP_HandleMaxPowerEvent = runtime.HandleMaxPowerEvent
        CP_HandleDisplayPowerEvent = runtime.HandleDisplayPowerEvent
        CP_HandleRareStructuralEvent = runtime.HandleRareStructuralEvent
    end

    CP_GetResolvedVisibleMax = CP_GetResolvedVisibleMax or function() return CP.currentMax end
    CP_RefreshVisibleModeLight = CP_RefreshVisibleModeLight or CP_Noop
    OnPowerUpdate = OnPowerUpdate or CP_Noop
    OnAuraUpdate = OnAuraUpdate or CP_Noop
    OnRuneUpdate = OnRuneUpdate or CP_Noop
    OnSpellcastStart = OnSpellcastStart or CP_Noop
    OnSpellcastEnd = OnSpellcastEnd or CP_Noop
    OnManaUpdate = OnManaUpdate or CP_Noop
    CP_HandleMaxPowerEvent = CP_HandleMaxPowerEvent or CP_Noop
    CP_HandleDisplayPowerEvent = CP_HandleDisplayPowerEvent or CP_Noop
    CP_HandleRareStructuralEvent = CP_HandleRareStructuralEvent or CP_Noop
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

-- Dynamic hot-path event binding (CP-1): only keep runtime events that the
-- currently active class-power / alt-mana mode actually needs. Rare structural
-- events remain registered permanently; hot events are rebound after FullRefresh.
local _cpBoundEvents = {}
local _cpBoundUnits = {}

local function CP_SetEventBound(frame, event, want, unit)
    if _cpBoundEvents[event] == want and _cpBoundUnits[event] == unit then return end
    frame:UnregisterEvent(event)
    if want then
        if unit then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:RegisterEvent(event)
        end
        _cpBoundEvents[event] = true
        _cpBoundUnits[event] = unit
    else
        _cpBoundEvents[event] = false
        _cpBoundUnits[event] = nil
    end
end

CP._cdmWidthSig = CP._cdmWidthSig or {}
CP._cdmWidthEventsActive = false

function CP.CDMWidthIsPositionLocked()
    if type(_G.MSUF_IsUnitFramePositionLocked) == "function" and _G.MSUF_IsUnitFramePositionLocked() then
        return true
    end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

function CP.CDMWidthGetDetachedPowerBarName()
    local b = _cpDB.bars or {}
    local cdmName = CPConst.CDM_FRAMES and CPConst.CDM_FRAMES[b.detachedPowerBarWidthMode or ""]
    if not cdmName then return nil end
    local db = MSUF_DB
    if not db then return nil end
    local readEnabled = _G.MSUF_ReadUnitPowerBarEnabled
    local player = db.player
    if not player or player.powerBarDetached ~= true or player.detachedPowerBarSyncClassPower == false then return nil end
    if readEnabled and readEnabled("player", db) == false then return nil end
    return cdmName
end

function CP.CDMWidthGetNames()
    local b = _cpDB.bars or {}
    local cpName = (CP.visible and CPConst.CDM_FRAMES and CPConst.CDM_FRAMES[b.classPowerWidthMode or ""]) or nil
    local pbName = CP.CDMWidthGetDetachedPowerBarName()
    return cpName, pbName
end

function CP.CDMWidthWantsSync()
    local cpName, pbName = CP.CDMWidthGetNames()
    return (cpName ~= nil or pbName ~= nil), (cpName == "BuffIconCooldownViewer" or pbName == "BuffIconCooldownViewer")
end

function CP.CDMWidthReadSig(frameName)
    local cdm = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(frameName)) or _G[frameName]
    if not cdm or not cdm.GetWidth or (cdm.IsShown and not cdm:IsShown()) then return 0 end
    local w = cdm:GetWidth()
    if not w or w < 1 then return 0 end
    local s = (cdm.GetEffectiveScale and cdm:GetEffectiveScale()) or 1
    if s <= 0 then s = 1 end
    return math_floor((w * s) + 0.5)
end

function CP.CDMWidthMarkChanged(tag, frameName, force)
    if not frameName then return false end
    local sig = CP.CDMWidthReadSig(frameName)
    local key = tag .. ":" .. frameName
    local cache = CP._cdmWidthSig
    if force or cache[key] ~= sig then
        cache[key] = sig
        return true
    end
    return false
end

function CP.CDMWidthSyncLayouts(force)
    if CP.CDMWidthIsPositionLocked() then return end
    local cpName, pbName = CP.CDMWidthGetNames()
    if not cpName and not pbName then return end

    local cpChanged = CP.CDMWidthMarkChanged("cp", cpName, force)
    local pbChanged = CP.CDMWidthMarkChanged("pb", pbName, force)

    if cpChanged and CP.visible and CP._pf and CP.currentMax and CP.currentMax > 0 and CP_Layout then
        local b = _cpDB.bars or {}
        CP_Layout(CP._pf, CP.currentMax, CP._layoutH or (b.classPowerHeight or 4))
    end
    if pbChanged and type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
end

function CP.CDMWidthSetEvents(active)
    CP._cdmWidthEventsActive = active == true
    CP_SetEventBound(eventFrame, "SPELL_UPDATE_COOLDOWN", active)
    CP_SetEventBound(eventFrame, "ACTIONBAR_UPDATE_COOLDOWN", active)
    CP_SetEventBound(eventFrame, "BAG_UPDATE_COOLDOWN", active)
end

local function CP_ShouldUseValuePowerEvents()
    if AM.visible then return true end
    local profile = CP.modeProfile
    return CP.visible and profile and profile.power == true or false
end

local function CP_ShouldUseMaxPowerEvent()
    if AM.visible then return true end
    local profile = CP.modeProfile
    return CP.visible and profile and profile.maxPower == true or false
end

CP_ShouldUseLiteBindings = function()
    local g = _cpDB.general
    if g and g.perfLiteClassPowerEvents == false then
        return false
    end
    return true
end

CP_RefreshEventBindings = function()
    local useLite = CP_ShouldUseLiteBindings()
    CP._liteBindingsActive = useLite
    local wantCDMWidthSync, wantCDMTrackedBuffs = CP.CDMWidthWantsSync()
    local cdmWidthEventsActive = wantCDMWidthSync and not CP.CDMWidthIsPositionLocked()

    if not useLite then
        CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_AURA", true, "player")
        CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", true)
        CP_SetEventBound(eventFrame, "UNIT_HEALTH", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", true, "player")
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_DEAD", true)
        CP_SetEventBound(eventFrame, "PLAYER_ALIVE", true)
        CP.CDMWidthSetEvents(cdmWidthEventsActive)
        return
    end

    local profile = CP.modeProfile or CP_GetModeEventProfile(CP.renderMode, CP.powerType, CP.isAuraPower)
    local wantPower = CP_ShouldUseValuePowerEvents()
    local wantMaxPower = CP_ShouldUseMaxPowerEvent()
    local wantAura = CP.visible and profile.aura == true
    local wantRune = CP.visible and profile.rune == true
    local wantHealth = CP.visible and profile.health == true
    local wantPointCharge = CP.visible and profile.pointCharge == true
    local wantWarlockPred = CP.visible and profile.warlockPred == true
    local wantSpellSucceeded = CP.visible and profile.spellSucceeded == true
    local wantDisplayPower = CP.visible or AM.visible
    local wantRegen = _autoHideActive and CP.visible
    local wantDeadAlive = CP.visible and profile.deadAlive == true

    CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", wantPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", false, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", wantMaxPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", wantDisplayPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", wantPointCharge, "player")
    CP_SetEventBound(eventFrame, "UNIT_AURA", wantAura or (wantCDMTrackedBuffs and cdmWidthEventsActive), "player")
    CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", wantRune)
    CP_SetEventBound(eventFrame, "UNIT_HEALTH", wantHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", wantSpellSucceeded, "player")
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", wantRegen or wantCDMWidthSync)
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", wantRegen or wantCDMWidthSync)
    CP_SetEventBound(eventFrame, "PLAYER_DEAD", wantDeadAlive)
    CP_SetEventBound(eventFrame, "PLAYER_ALIVE", wantDeadAlive)
    CP.CDMWidthSetEvents(cdmWidthEventsActive)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "UNIT_POWER_UPDATE" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate(arg2)
        end
        return
    end

    if event == "UNIT_POWER_FREQUENT" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate(arg2)
        end
        return
    end

    if event == "UNIT_AURA" then
        if arg1 == "player" then
            local profile = CP.modeProfile or CP_GetModeEventProfile(CP.renderMode, CP.powerType, CP.isAuraPower)
            if CP._liteBindingsActive == false or (CP.visible and profile and profile.aura == true) then
                OnAuraUpdate(arg1)
            end
            if CP._cdmWidthEventsActive then
                CP.CDMWidthSyncLayouts(false)
            end
        end
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN"
    or event == "ACTIONBAR_UPDATE_COOLDOWN"
    or event == "BAG_UPDATE_COOLDOWN"
    then
        CP.CDMWidthSyncLayouts(false)
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
            CP_HandleMaxPowerEvent(arg2)
        end
        return
    end

    if event == "UNIT_POWER_POINT_CHARGE" then
        if arg1 == "player" then
            -- Only relevant for standard segmented mode (CP/HP)
            if CP.renderMode == CPK.MODE.SEGMENTED then
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
            if CP_ShouldUseLiteBindings() then
                CP_HandleDisplayPowerEvent()
            else
                ThrottledFullRefresh()
            end
        end
        return
    end

    -- Stagger: health changes affect threshold colors + bar max
    if event == "UNIT_HEALTH" then
        if arg1 == "player" then
            -- CP stagger: max health = bar max, threshold recalculation
            if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
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
        CP_RefreshEventBindings()
        if event == "PLAYER_REGEN_ENABLED" then
            CP.CDMWidthSyncLayouts(true)
        end
        if _autoHideActive and CP.visible and CP.container then
            -- Re-run the current mode's update to trigger CP_CheckAutoHide
            CP_RunActiveUpdate(CP.powerType, CP.currentMax)
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

    -- Rare: only rebuild on actual structural changes; otherwise do a light re-sync.
    if event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
    or event == "PLAYER_TALENT_UPDATE"
    or event == "TRAIT_CONFIG_UPDATED"
    or event == "UPDATE_SHAPESHIFT_FORM"
    then
        CP_HandleRareStructuralEvent(true)
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

-- Register structural / rare events permanently. Hot-path runtime events are
-- rebound by CP_RefreshEventBindings() after each FullRefresh.
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

-- Public API (for Options, Edit Mode, and other modules)

-- Force full refresh (call after changing DB values)
function _G.MSUF_ClassPower_Refresh()
    _cachedColorToken = nil  -- Invalidate color cache
    _cachedBgColorToken = nil
    FullRefresh()
end

function _G.MSUF_ClassPower_RefreshCDMWidthBindings(syncNow)
    _CP_RefreshConfig()
    CP_RefreshEventBindings()
    if syncNow == true then
        CP.CDMWidthSyncLayouts(true)
    end
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

-- Smooth Power Bar Mode
-- The actual smooth bar logic lives in MSUF_UnitframeCore.lua (DIRECT_APPLY)
-- and MidnightSimpleUnitFrames.lua (_MSUF_Bars_SyncPower).
-- When enabled, those paths use raw UnitPower/UnitPowerMax + ExponentialEaseOut
-- on BOTH SetMinMaxValues AND SetValue — identical to MidnightRogueBars.
-- Secret-safe: nil-guarded, no arithmetic on return values.
-- This section only provides the public toggle API for the options panel.
_G.MSUF_SmoothPowerBar_Apply = function()
    -- Refresh the cached flags in UFCore's DIRECT_APPLY hot path.
    if _G.MSUF_UFCore_RefreshSettingsCache then
        _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER")
    end
end

-- Phase 4: Module Registration
do
    local reg = _G.MSUF_RegisterModule
    if type(reg) == "function" then
        reg("ClassPower", {
            order = 30,
            IsEnabled = function()
                if not MSUF_DB then return true end
                local b = MSUF_DB.bars
                return not b or b.showClassPower ~= false
            end,
            Init = function()
                EnsureDefaults()
            end,
            Enable = function()
                _CP_RefreshConfig()
                FullRefresh()
            end,
            Disable = function() end,
            RefreshSettings = function(_, source)
                _cachedColorToken = nil
                _cachedBgColorToken = nil
                _CP_RefreshConfig()
                FullRefresh()
            end,
            Shutdown = function()
                _cachedColorToken = nil
                _cachedBgColorToken = nil
            end,
        })
    end
end

-- MSUF_CP_Balance.lua — Balance Druid Astral Power prediction + eclipse colors
-- Self-contained feature module. Wrapped in do…end so the Druid-class-gate
-- below uses a scoped 'do return end' that skips only this block, not the
-- whole file. Previous layout used two file-scope 'return' statements which
-- aborted parsing of the rest of the file on non-Druid characters (meaning
-- any trailing code added after this block would silently vanish).
do
    local balanceBuilders = _G.MSUF_CP_FEATURE_BUILDERS
    if type(balanceBuilders) ~= "table" then
        balanceBuilders = {}
        _G.MSUF_CP_FEATURE_BUILDERS = balanceBuilders
    end

    -- Class gate: Balance-specific runtime setup only applies to Druids.
    -- Everything inside this do-block is cold-dead code for other classes
    -- (the mode/feature builders in MSUF_CP_Modes.lua are class-neutral
    -- registrations and remain registered for all classes — consumer-side
    -- spec checks gate which mode is actually rendered).
    local _, _playerClass = UnitClass("player")
    if _playerClass ~= "DRUID" then
        -- Scoped return: exits this do-block only, NOT the file.
        do return end
    end

    -- One-time load guard (scoped — only relevant once we know we're Druid).
    if _G.__MSUF_CP_Balance_Loaded then
        do return end
    end
    _G.__MSUF_CP_Balance_Loaded = true

    local UnitClass = UnitClass
    local UnitPowerType = UnitPowerType
    local UnitPowerMax = UnitPowerMax
    local GetTime = GetTime
    local CreateFrame = CreateFrame
    local C_UnitAuras = C_UnitAuras
    local C_Spell = C_Spell
    local C_SpellBook = C_SpellBook
    local type = type
    local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local PLAYER_CLASS = _playerClass

    local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { BAL = {}, SPELL = {} }
local _issecretvalue = _G.issecretvalue
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

local LUNAR_POWER = (Enum and Enum.PowerType and Enum.PowerType.LunarPower) or 8
local _active = false
local _castSpell = nil
local _predAmt = 0
local _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
local _predTex = nil
local _eclColor = nil

local function GetColorOverrides()
    local db = _G.MSUF_DB
    local g = db and db.general
    return g and g.classPowerColorOverrides or nil
end

local function ShowPredictionEnabled()
    local db = _G.MSUF_DB
    local b = db and db.bars
    return not (b and b.classPowerShowPrediction == false)
end

local function _checkActive()
    local spec = GetSpec and GetSpec()
    if spec ~= 1 then _active = false; return end
    local pType = UnitPowerType("player")
    _active = (NotSecret(pType) and pType == LUNAR_POWER) and true or false
end

local function _getPowerBar()
    local pf = _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player)
    return pf and pf.targetPowerBar or nil
end

local function _resolveEclColor(token)
    local ov = GetColorOverrides()
    if type(ov) == "table" then
        local c = token and ov[token]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    if token == "ECLIPSE_SOLAR" then return CPK.BAL.CLR_SOLAR[1], CPK.BAL.CLR_SOLAR[2], CPK.BAL.CLR_SOLAR[3] end
    if token == "ECLIPSE_LUNAR" then return CPK.BAL.CLR_LUNAR[1], CPK.BAL.CLR_LUNAR[2], CPK.BAL.CLR_LUNAR[3] end
    if token == "ECLIPSE_CA" then return CPK.BAL.CLR_CA[1], CPK.BAL.CLR_CA[2], CPK.BAL.CLR_CA[3] end
    return nil
end

local function _refreshEclipses()
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not getAura then return end
    _solarExp, _lunarExp, _caExp, _incExp = 0, 0, 0, 0
    for auraID, kind in pairs(CPConst.ECLIPSE_AURAS or {}) do
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
    local inCA, inInc = (_caExp > now), (_incExp > now)
    if inCA or inInc then
        local r, g, b = _resolveEclColor("ECLIPSE_CA")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_CA
    elseif _solarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_SOLAR")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_SOLAR
    elseif _lunarExp > now then
        local r, g, b = _resolveEclColor("ECLIPSE_LUNAR")
        _eclColor = r and { r, g, b } or CPK.BAL.CLR_LUNAR
    else
        _eclColor = nil
    end
end

local function _computeAP(spellID)
    if not spellID then return 0 end
    local base = (CPConst.AP_GENERATORS or {})[spellID]
    if not base then return 0 end
    if spellID == CPK.SPELL.AP_WRATH or spellID == CPK.SPELL.AP_STARFIRE then
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if known and known(CPK.SPELL.NATURES_BALANCE) then base = base + 2 end
        local now = GetTime()
        local inCA, inInc = (_caExp > now), (_incExp > now)
        local inEcl = false
        if spellID == CPK.SPELL.AP_WRATH then
            inEcl = (_solarExp > now) or inCA or inInc
        else
            inEcl = (_lunarExp > now) or inCA or inInc
        end
        if inEcl then base = base * 1.4 end
    end
    return base
end

local function _resolvePredColor()
    local ov = GetColorOverrides()
    if type(ov) == "table" then
        local c = ov["AP_PREDICTION"]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
    end
    if _G.MSUF_GetPowerBarColor then
        local r, g, b = _G.MSUF_GetPowerBarColor(LUNAR_POWER, "LUNAR_POWER")
        if type(r) == "number" then return r, g, b end
    end
    return 0.30, 0.52, 0.90
end

local function _applyEclipseColor()
    local bar = _getPowerBar()
    if not bar or not _eclColor then return end
    bar:SetStatusBarColor(_eclColor[1], _eclColor[2], _eclColor[3], 1)
end

local function _updateOverlay()
    local bar = _getPowerBar()
    if not bar then return end
    if ShowPredictionEnabled() == false then
        if _predTex then _predTex:Hide() end
        return
    end
    if not _predTex then
        local tex = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        local getBarTex = _G.MSUF_GetBarTexture
        tex:SetTexture(getBarTex and getBarTex() or "Interface\\Buttons\\WHITE8x8")
        tex:SetVertexColor(1, 1, 1, CPK.BAL.PRED_ALPHA)
        tex:SetHeight(1)
        tex:Hide()
        _predTex = tex
    end
    if _predAmt <= 0 or not _castSpell then
        _predTex:Hide()
        return
    end
    local rawMx = UnitPowerMax("player", LUNAR_POWER)
    if not NotSecret(rawMx) then _predTex:Hide(); return end
    local mx = tonumber(rawMx) or 100
    if mx <= 0 then mx = 100 end
    local predFrac = _predAmt / mx
    if predFrac > 1 then predFrac = 1 end
    local barW, barH = bar:GetWidth(), bar:GetHeight()
    if barW <= 0 or barH <= 0 then _predTex:Hide(); return end
    local predW = barW * predFrac
    if predW < 1 then _predTex:Hide(); return end
    if _eclColor then
        _predTex:SetVertexColor(_eclColor[1], _eclColor[2], _eclColor[3], CPK.BAL.PRED_ALPHA)
    else
        local pr, pg, pb = _resolvePredColor()
        _predTex:SetVertexColor(pr, pg, pb, CPK.BAL.PRED_ALPHA)
    end
    _predTex:ClearAllPoints()
    _predTex:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    _predTex:SetSize(predW, barH)
    _predTex:Show()
end

local function _cleanup()
    _castSpell, _predAmt, _eclColor = nil, 0, nil
    if _predTex then _predTex:Hide() end
end

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
    if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD" then
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
    if event == "UNIT_SPELLCAST_START" and arg1 == "player" then
        _castSpell = arg3
        _predAmt = _computeAP(arg3)
        _updateOverlay()
        return
    end
    if (event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED") and arg1 == "player" then
        _castSpell = nil
        _predAmt = 0
        _updateOverlay()
        return
    end
    if event == "UNIT_AURA" and arg1 == "player" then
        _refreshEclipses()
        _applyEclipseColor()
        if _castSpell then
            _predAmt = _computeAP(_castSpell)
            _updateOverlay()
        end
        return
    end
    if event == "UNIT_POWER_UPDATE" and arg1 == "player" then
        if _castSpell then _updateOverlay() end
        if _eclColor then _applyEclipseColor() end
    end
end)

_G.MSUF_BAL_InvalidateColors = function()
    if not _active then return end
    _refreshEclipses()
    _applyEclipseColor()
    if _castSpell then _updateOverlay() end
end

end -- close do-block started at Balance module header (Druid class gate)
