--- ClassPower/MSUF_CP_Controller.lua - class resource controller
--- Features:
--- 1. ClassPower (segmented): Combo Points, Holy Power, Soul Shards (incl.
--- fractional for Destruction), Arcane Charges, Chi, Essence.
--- 2. DK Runes: individual per-rune cooldown animation + sort order.
--- 3. DH Devourer: Soul Fragments (aura-based, normalized 0-1, dual color).
--- 4. Enh Shaman: Maelstrom Weapon stacks (aura-based segments).
--- 5. Vehicle: auto-switch to combo points in vehicle UI.
--- 6. AltMana: extra Mana bar for dual-resource specs.
--- 7. Stagger: Brewmaster Monk stagger bar (3-color threshold).
--- Architecture:
--- - Self-contained: own event frame, own DB defaults, own layout.
--- - Independent overlay (Unhalted approach): no HP bar reservation.
--- - Render modes: each class/spec resolves to a render mode at FullRefresh.
--- Hot-path dispatch is a single mode check - zero branching for inactive.
--- - Secret-safe: raw UnitPower/UnitPowerMax (2 args), nil-guarded.
--- - Max performance: Rune and Essence use native 12.1 duration objects;
--- Ebon is fully AuraContainer-owned. Lua polling remains only for active
--- Stagger or a degraded non-Ebon API path.

--- Guard: only load once.
if _G.__MSUF_ClassPower_Loaded then return end
_G.__MSUF_ClassPower_Loaded = true

local MSUF = select(2, ...)
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function CoreUnitFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end

--- Perf locals (eliminate global lookups in hot paths)
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor = math.floor
local math_min = math.min
local string_format = string.format
local table_sort = table.sort
local wipe = wipe
local CreateFrame = CreateFrame
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPartialPower = UnitPartialPower
local UnitHealth = UnitHealth
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
local C_Timer = C_Timer
local GetPowerRegenForPowerType = GetPowerRegenForPowerType
local StatusBarInterpolation = _G.Enum and _G.Enum.StatusBarInterpolation
local SMOOTH_INTERP = StatusBarInterpolation and StatusBarInterpolation.ExponentialEaseOut or nil

--- Aura API (player-only class resources; unitframe aura display is native 12.1)
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook

--- Secret-value guard (Midnight/12.1)
local _issecretvalue = _G.issecretvalue
local _canaccesstable = _G.canaccesstable
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

local function CanAccessTableValue(value)
    if NotSecret(value) == false or value == nil or type(value) ~= "table" then return false end
    if _canaccesstable and _canaccesstable(value) == false then return false end
    return true
end

local function CanAccessOptionalTableValue(value)
    if NotSecret(value) == false then return false end
    if value == nil then return true end
    return CanAccessTableValue(value)
end

--- P0 PERF: Cached DB config (eliminates ~46 MSUF_DB traversals per event)
--- Rebuilt once per FullRefresh (login, profile switch, option change).
--- Hot-path functions read _cpDB.* instead of MSUF_DB.bars.*/general.*.
--- Secret-safe: only reads DB booleans/numbers, no secret comparisons.
local _cpDB = {
    colorByType    = true,   showCharged    = true,
    bgAlpha        = 0.3,    showPrediction = true,
    showText       = true,   fontSize       = 14,
    classSmooth    = true,   altManaSmooth = true,
    colorOverrides = nil,
    bgColorOverrides = nil,  bars = nil, general = nil,
    comboPointColorMode = "default", slotColorModes = nil, fullColorEnabled = nil,
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
    _cpDB.classSmooth       = (b.classPowerSmoothFill == true)
    _cpDB.altManaSmooth     = (b.altManaSmoothFill == true)
    _cpDB.colorOverrides    = (type(g.classPowerColorOverrides) == "table") and g.classPowerColorOverrides or nil
    _cpDB.bgColorOverrides  = (type(g.classPowerBgColorOverrides) == "table") and g.classPowerBgColorOverrides or nil
    _cpDB.comboPointColorMode = cpMode
    _cpDB.slotColorModes    = (type(b.classPowerSlotColorModes) == "table") and b.classPowerSlotColorModes or nil
    _cpDB.fullColorEnabled  = (type(b.classPowerFullColorEnabled) == "table") and b.classPowerFullColorEnabled or nil
end

local function CP_ConfigClassPowerEnabled()
    local b = _cpDB.bars
    if not b then
        local db = MSUF_DB
        b = db and db.bars
    end
    return not b or b.showClassPower ~= false
end

local function CP_ConfigAltManaEnabled()
    local b = _cpDB.bars
    if not b then
        local db = MSUF_DB
        b = db and db.bars
    end
    return b and b.showAltMana == true or false
end

local function CP_ConfigPlayerHPBarEnabled()
    local b = _cpDB.bars
    if not b then
        local db = MSUF_DB
        b = db and db.bars
    end
    return b and b.playerHPBarEnabled == true or false
end

local function CP_ConfigAnyFeatureEnabled()
    return CP_ConfigClassPowerEnabled() or CP_ConfigAltManaEnabled() or CP_ConfigPlayerHPBarEnabled()
end

--- Spec API (12.0: C_SpecializationInfo preferred, fallback to global)
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization

--- Player class (resolved once, never changes)
local _, PLAYER_CLASS = UnitClass("player")

--- Phase 1 CP split: shared constants / profiles now live in ClassPower/*.lua
--- Keeps the core chunk smaller and reduces WoW's top-level local pressure.
local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { MODE = { NONE = 0, SEGMENTED = 1, FRACTIONAL = 2, RUNE_CD = 3, AURA_SEGMENTED = 4, AURA_SINGLE = 5, CONTINUOUS = 6, TIMER_BAR = 8, STAGGER = 9, IRONFUR = 10 }, SPEC = {}, SPELL = {}, BAL = {}, THRESH = {} }
local TIP = CPConst.TIP or {}
local EBON = CPConst.EBON or {}
local PT = CPConst.PT or {}
local PT_STAGGER = CPConst.PT_STAGGER or -1
local POWER_TYPE_TOKENS = CPConst.POWER_TYPE_TOKENS or {}
local CP_MODE_EVENT_PROFILE = _G.MSUF_CP_MODE_EVENT_PROFILE or {}

--- Cached split registries (load-time only; avoids repeated global table lookups
--- and keeps the post-split core wiring easier to follow).

--- ---
--- ALT_MANA builder - registered EARLY so the consumer ~line 1134
--- (CP_CallBuilder(CPCoreBuilders.ALT_MANA, ...)) sees it at file-parse
--- time. Previous layout had this block at file bottom -> builder was
--- nil when consumer ran -> AM_Create/AM_Layout/AM_ApplyColor/AM_UpdateValue
--- stayed nil -> FullRefresh crashed for every spec with a mana pool
--- (Shadow Priest, Druid, Monk WW, Ret Pala, Shaman Ele/Enh, Aug Evoker)
--- whenever needsAlt==true. Wrapped in do...end to scope the 'builders'
--- local (avoids shadowing the 'builders' locals at later file sections).
--- ---

--- AltMana builder moved to ClassPower\\MSUF_CP_AltMana.lua.

local CPCoreBuilders = (type(_G.MSUF_CP_CORE_BUILDERS) == "table") and _G.MSUF_CP_CORE_BUILDERS or {}
local CPModeBuilders = (type(_G.MSUF_CP_MODE_BUILDERS) == "table") and _G.MSUF_CP_MODE_BUILDERS or {}
local CPFeatureBuilders = (type(_G.MSUF_CP_FEATURE_BUILDERS) == "table") and _G.MSUF_CP_FEATURE_BUILDERS or {}

local function CP_CallBuilder(builder, env)
    if type(builder) ~= "function" then return nil end
    local result = builder(env)
    return (result) and result or nil
end

local function CP_Noop() end
--- DH Vengeance: Soul Fragments via C_Spell.GetSpellCastCount (MCR-sourced)

--- Whirlwind Tracker (Sensei pattern - own event frame, event-driven render)
local _wwRender  --- forward-declared; set after CP_UpdateValues_AuraSegmented exists

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
    local SEEN_CAST_GUID_MAX = 32
    local seenCastGUID, seenCastRing = {}, {}
    local seenCastWrite, seenCastCount = 1, 0
    local _expiryTimer = nil  --- pending C_Timer handle for expiry
    local _eventsBound = false
    local ResetSeenCastGUID

    WW.MAX_STACKS = MAX_STACKS

    function WW.GetStacks()
        if expiresAt and GetTime() >= expiresAt then
            stacks = 0
            expiresAt = nil
        end
        return stacks
    end

    local function ResetState()
        stacks = 0
        expiresAt = nil
        noConsumeUntil = 0
        _expiryTimer = (_expiryTimer or 0) + 1
        ResetSeenCastGUID()
    end

    --- Schedule a one-shot expiry timer (replaces per-frame polling)
    local function ScheduleExpiry()
        if not expiresAt then return end
        local remaining = expiresAt - GetTime()
        if remaining <= 0 then
            stacks = 0
            expiresAt = nil
            if _wwRender then _wwRender() end
            return
        end
        --- Cancel previous timer token by bumping generation counter
        _expiryTimer = (_expiryTimer or 0) + 1
        local myTimer = _expiryTimer
        C_Timer.After(remaining + 0.05, function()
            if myTimer ~= _expiryTimer then return end  --- stale
            if expiresAt and GetTime() >= expiresAt then
                stacks = 0
                expiresAt = nil
                if _wwRender then _wwRender() end
            end
        end)
    end

    function ResetSeenCastGUID()
        for i = 1, SEEN_CAST_GUID_MAX do
            local guid = seenCastRing[i]
            if guid then
                seenCastGUID[guid] = nil
                seenCastRing[i] = nil
            end
        end
        seenCastWrite, seenCastCount = 1, 0
    end

    local function CastGUIDSeen(guid)
        if not guid then return false end
        if seenCastGUID[guid] then return true end

        if seenCastCount >= SEEN_CAST_GUID_MAX then
            local old = seenCastRing[seenCastWrite]
            if old then seenCastGUID[old] = nil end
        else
            seenCastCount = seenCastCount + 1
        end

        seenCastRing[seenCastWrite] = guid
        seenCastGUID[guid] = true
        seenCastWrite = (seenCastWrite % SEEN_CAST_GUID_MAX) + 1

        return false
    end

    --- Warrior-only: own event frame (Sensei pattern)
    if PLAYER_CLASS == "WARRIOR" then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
            if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                ResetState()
                if _wwRender then _wwRender() end
                return
            end
            if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end

            local known = C_SpellBook and C_SpellBook.IsSpellKnown

            --- castGUID dedup
            if CastGUIDSeen(castGUID) then return end

            --- Unhinged no-consume window
            if known and known(UNHINGED) and BLADESTORMS[spellID] then
                noConsumeUntil = GetTime() + 2
            end

            --- Generator -> max stacks
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

            --- Spender -> consume 1
            if SPENDERS[spellID] then
                if spellID == 23881 and GetTime() < noConsumeUntil then return end
                if stacks > 0 then
                    stacks = stacks - 1
                    if stacks == 0 then expiresAt = nil end
                    if _wwRender then _wwRender() end
                end
            end
        end)

        function WW.SetActive(active)
            active = active and CP_ConfigClassPowerEnabled() or false
            if _eventsBound == active then return end
            _eventsBound = active
            if active then
                f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                f:RegisterEvent("PLAYER_DEAD")
                f:RegisterEvent("PLAYER_ALIVE")
            else
                f:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                f:UnregisterEvent("PLAYER_DEAD")
                f:UnregisterEvent("PLAYER_ALIVE")
                ResetState()
                if _wwRender then _wwRender() end
            end
        end
    end
end

--- Phase 5 CP split: Balance Druid Astral Power prediction + eclipse colors now
--- live in ClassPower/Features/MSUF_CP_Balance.lua. The core keeps only the
--- global color invalidation hook call, so this file stays closer to a pure
--- orchestrator.

--- Hunter Survival: Tip of the Spear (talent 260285)
--- Evoker Augmentation: native 12.1 Ebon Might duration text.
--- DB Defaults (self-contained; runs on every login, no-ops if keys exist)
local function EnsureDefaults()
    if not MSUF_DB then return end
    if not MSUF_DB.bars then MSUF_DB.bars = {} end
    local b = MSUF_DB.bars

    --- ClassPower defaults
    if b.showClassPower       == nil then b.showClassPower       = true  end
    if b.classPowerHeight     == nil then b.classPowerHeight     = 4     end
    if b.classPowerShape      == nil then b.classPowerShape      = "BAR" end
    if b.classPowerShapeAlign == nil then b.classPowerShapeAlign = "CENTER" end
    if b.classPowerColorByType == nil then b.classPowerColorByType = true end
    if b.classPowerBgAlpha    == nil then b.classPowerBgAlpha    = 0.3   end
    if b.classPowerTickWidth  == nil then b.classPowerTickWidth  = 1     end
    if b.classPowerOutline    == nil then b.classPowerOutline    = 1     end
    if b.classPowerWidth      == nil then b.classPowerWidth      = 0     end
    if b.classPowerWidthMode  == nil then b.classPowerWidthMode  = "player" end
    if b.classPowerOffsetX    == nil then b.classPowerOffsetX    = 0     end
    if b.classPowerOffsetY    == nil then b.classPowerOffsetY    = 0     end
    if b.classPowerFrameLevelOffset == nil then b.classPowerFrameLevelOffset = 5 end
    if b.classPowerTextLayer  == nil then b.classPowerTextLayer  = 5     end
    if b.smoothPowerBar       == nil then b.smoothPowerBar       = false end
    if b.classPowerSmoothFill == nil then b.classPowerSmoothFill = (b.smoothPowerBar == true) end
    if b.showChargedComboPoints == nil then b.showChargedComboPoints = true end
    if b.classPowerComboPointColorMode == nil then b.classPowerComboPointColorMode = "default" end
    if b.classPowerShowText    == nil then b.classPowerShowText    = false end
    if b.classPowerFontSize    == nil then b.classPowerFontSize    = 16    end
    if b.classPowerShowPrediction == nil then b.classPowerShowPrediction = true end
    if b.classPowerTextOffsetX    == nil then b.classPowerTextOffsetX    = 0    end
    if b.classPowerTextOffsetY    == nil then b.classPowerTextOffsetY    = 0    end
    if b.detachedPowerBarOutline  == nil then b.detachedPowerBarOutline  = 1    end

    --- AltMana defaults
    if b.showAltMana          == nil then b.showAltMana          = false end
    if b.altManaHeight        == nil then b.altManaHeight        = 4     end
    if b.altManaWidthMode ~= "custom" then b.altManaWidthMode   = "player" end
    if b.altManaWidth         == nil then b.altManaWidth         = 0     end
    if b.altManaOffsetX       == nil then b.altManaOffsetX       = 0     end
    if b.altManaOffsetY       == nil then b.altManaOffsetY       = -2    end
    if b.altManaColorR        == nil then b.altManaColorR        = 0.0   end
    if b.altManaColorG        == nil then b.altManaColorG        = 0.0   end
    if b.altManaColorB        == nil then b.altManaColorB        = 0.8   end
    if b.altManaSmoothFill    == nil then b.altManaSmoothFill    = (b.smoothPowerBar == true) end

    --- Class Resources-owned second Player HP bar (off by default)
    if b.playerHPBarEnabled     == nil then b.playerHPBarEnabled     = false end
    if b.playerHPBarAnchor      == nil then b.playerHPBarAnchor      = "CLASS_TOP" end
    if b.playerHPBarWidthMode   == nil then b.playerHPBarWidthMode   = "class" end
    if b.playerHPBarWidth       == nil then b.playerHPBarWidth       = 0 end
    if b.playerHPBarHeight      == nil then b.playerHPBarHeight      = 6 end
    if b.playerHPBarGap         == nil then b.playerHPBarGap         = 2 end
    if b.playerHPBarOffsetX     == nil then b.playerHPBarOffsetX     = 0 end
    if b.playerHPBarOffsetY     == nil then b.playerHPBarOffsetY     = 0 end
    if b.playerHPBarFrameLevelOffset == nil then b.playerHPBarFrameLevelOffset = 7 end
    if b.playerHPBarShape       == nil then b.playerHPBarShape       = "BAR" end
    if b.playerHPBarOrbSize     == nil then b.playerHPBarOrbSize     = 54 end
    if b.playerHPBarTexture     == nil then b.playerHPBarTexture     = "" end
    if b.playerHPBarBgTexture   == nil then b.playerHPBarBgTexture   = "" end
    if b.playerHPBarBgAlpha     == nil then b.playerHPBarBgAlpha     = 0.35 end
    if b.playerHPBarOutline     == nil then b.playerHPBarOutline     = 1 end
    if b.playerHPBarColorMode   == nil then b.playerHPBarColorMode   = "GLOBAL" end
    if b.playerHPBarSmoothFill  == nil then b.playerHPBarSmoothFill  = false end
    if b.playerHPBarTextEnabled == nil then b.playerHPBarTextEnabled = true end
    if b.playerHPBarUsePlayerText == nil then b.playerHPBarUsePlayerText = true end
    if b.playerHPBarTextLeft    == nil then b.playerHPBarTextLeft    = "NONE" end
    if b.playerHPBarTextCenter  == nil then b.playerHPBarTextCenter  = "NONE" end
    if b.playerHPBarTextRight   == nil then b.playerHPBarTextRight   = "CURPERCENT" end
    if b.playerHPBarTextSeparator == nil then b.playerHPBarTextSeparator = "" end
    if b.playerHPBarTextReverse == nil then b.playerHPBarTextReverse = false end
    if b.playerHPBarTextSize    == nil then b.playerHPBarTextSize    = 14 end
    if b.playerHPBarTextOffsetX == nil then b.playerHPBarTextOffsetX = 0 end
    if b.playerHPBarTextOffsetY == nil then b.playerHPBarTextOffsetY = 0 end

    --- Stagger bar defaults (Brewmaster Monk)
    if b.showStagger          == nil then b.showStagger          = true  end
    if b.staggerHeight        == nil then b.staggerHeight        = 4     end
    if b.staggerOffsetY       == nil then b.staggerOffsetY       = -2    end

    --- DK Rune sort order: "asc" = ready first, "desc" = recharging first, nil = natural
    if b.runeSortOrder        == nil then b.runeSortOrder        = "asc" end
    --- DK Runes: show per-rune cooldown time text on the runes (Sensei-style)
    if b.runeShowTime == nil and b.runeShowTimeText ~= nil then b.runeShowTime = b.runeShowTimeText and true or false end
    if b.runeShowTime        == nil then b.runeShowTime        = true end

    --- Ele Shaman: Maelstrom Power continuous bar (off by default - niche preference)
    if b.showEleMaelstrom     == nil then b.showEleMaelstrom     = false end
    --- Evoker Aug: native Ebon Might duration bar and text (on by default)
    if b.showEbonMight        == nil then b.showEbonMight        = true  end
    --- Shadow Priest: show Mana as main bar, Insanity as class resource (off by default)
    if b.showShadowMana       == nil then b.showShadowMana       = false end
    --- Guardian Druid: estimated per-cast Ironfur lifetime bar (opt-in).
    if b.showGuardianIronfur   == nil then b.showGuardianIronfur   = false end
    if b.guardianIronfurShowHashLines == nil then b.guardianIronfurShowHashLines = true end

    --- Auto-hide: visibility conditions
    if b.classPowerHideOOC       == nil then b.classPowerHideOOC       = false end
    if b.classPowerHideWhenFull  == nil then b.classPowerHideWhenFull  = false end
    if b.classPowerHideWhenEmpty == nil then b.classPowerHideWhenEmpty = false end

    --- Pip alpha (0.0-1.0)
    if b.classPowerFilledAlpha   == nil then b.classPowerFilledAlpha   = 1.0   end
    if b.classPowerEmptyAlpha    == nil then b.classPowerEmptyAlpha    = 0.3   end

    --- Gap between pips (pixels, 0 = no gap - only tick separators)
    if b.classPowerGap           == nil then b.classPowerGap           = 0     end

    --- Fill direction: false = left->right (default), true = right->left
    if b.classPowerFillReverse   == nil then b.classPowerFillReverse   = false end
end

--- Power-type detection (resolved per spec/form change, cached)
--- Returns: powerType, renderMode, isAuraPower
--- powerType: Enum.PowerType or string token for aura-based
--- renderMode: MODE_* constant for hot-path dispatch
--- isAuraPower: true if driven by UNIT_AURA instead of UNIT_POWER_UPDATE

--- ClassPower: returns powerType, renderMode, isAuraPower
local function GetClassPowerType()
    --- Vehicle override: always combo points.
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
        --- Essence remains the segmented Class Resource for every Evoker spec.
        --- Augmentation's Ebon Might is rendered as an additional native row;
        --- it must not replace the Essence event/value mode.
        return PT.Essence, CPK.MODE.SEGMENTED, false

    elseif PLAYER_CLASS == "MAGE" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.MAGE_ARCANE then return PT.ArcaneCharges, CPK.MODE.SEGMENTED, false end
        if spec == CPK.SPEC.MAGE_FROST then return "ICICLES", CPK.MODE.AURA_SEGMENTED, true end

    elseif PLAYER_CLASS == "MONK" then
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.MONK_WINDWALKER then return PT.Chi, CPK.MODE.SEGMENTED, false end
        --- Brewmaster: Stagger as class resource (3-color threshold, CDM-synced).
        --- Energy is primary -> main power bar. Stagger -> class power overlay.
        if spec == CPK.SPEC.MONK_BREWMASTER then
            local bb = _cpDB.bars
            if not bb or bb.showStagger ~= false then
                return PT_STAGGER, CPK.MODE.STAGGER, false
            end
        end

    elseif PLAYER_CLASS == "DRUID" then
        --- Mirror Blizzard's DruidComboPointBar: Energy as the active primary
        --- power is the authoritative signal, including Cat-form variants.
        local primaryPower = UnitPowerType("player")
        if NotSecret(primaryPower) then
            if primaryPower == PT.Energy then return PT.ComboPoints, CPK.MODE.SEGMENTED, false end
        else
            --- Compatibility fallback when the primary power itself is secret.
            local form = GetShapeshiftFormID and GetShapeshiftFormID()
            if form == 1 then return PT.ComboPoints, CPK.MODE.SEGMENTED, false end
        end
        local spec = GetSpec and GetSpec()
        local bb = _cpDB.bars
        if spec == CPK.SPEC.DRUID_GUARDIAN and bb and bb.showGuardianIronfur == true
            and NotSecret(primaryPower) and primaryPower == PT.Rage then
            return "IRONFUR", CPK.MODE.IRONFUR, false
        end
        --- Balance/Boomkin: Astral Power is already the main power bar -> no class power.
        --- Other forms (Bear etc.): main bar shows Rage/Mana -> no secondary resource overlay.

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
            --- Only if talent is known
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
        --- Shadow: when showShadowMana is ON, main bar shows Mana -> Insanity as class resource
        local spec = GetSpec and GetSpec()
        if spec == CPK.SPEC.PRIEST_SHADOW then
            local b = _cpDB.bars
            if b and b.showShadowMana then
                return PT.Insanity, CPK.MODE.CONTINUOUS, false
            end
        end

    elseif PLAYER_CLASS == "WARRIOR" then
        --- All Warrior specs use Whirlwind as class resource (Fury, Arms, Prot).
        --- No talent gate: IsSpellKnown(12950) unreliable in 12.0 for passive talents.
        --- If player doesn't have Improved Whirlwind, stacks stay 0 -> auto-hide handles it.
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

--- Stagger detection (Brewmaster Monk only)

--- AltMana: helper declarations now bind through ClassPower/MSUF_CP_AltMana.lua
local function NeedsAltManaBar()
    --- Ele Shaman: when Maelstrom is in class power, main bar shows Mana -> no alt needed
    if _G.MSUF_EleMaelstromActive then return false end
    --- Aug Evoker: the composite replaces the ordinary Power surface, so an
    --- explicitly enabled AltMana bar remains the optional Mana display.
    if _G.MSUF_AugEvokerActive then return true end
    --- Shadow Priest: main bar shows Mana -> no AltMana needed
    if _G.MSUF_ShadowManaActive then return false end
    local pType = UnitPowerType("player")
    --- pType == 0 = Mana primary -> no alt bar needed
    if NotSecret(pType) then
        if pType == nil or pType == PT.Mana then return false end
    end
    --- Must actually have a mana pool (Warriors, Rogues, DKs etc. have 0 max mana)
    local maxMana = UnitPowerMax("player", PT.Mana)
    if NotSecret(maxMana) and maxMana ~= nil and maxMana <= 0 then
        return false
    end
    --- Non-secret primary + has mana pool -> check class/spec heuristic
    if not NotSecret(pType) then
        local SPECS_NEED_ALT = {
            PRIEST  = { [3] = true },           --- Shadow
            SHAMAN  = { [1] = true, [2] = true }, --- Ele, Enh
            DRUID   = { [1] = true, [2] = true, [3] = true }, --- Balance, Feral, Guardian
            PALADIN = { [3] = true },           --- Ret
            MONK    = { [3] = true },           --- WW
        }
        local specs = SPECS_NEED_ALT[PLAYER_CLASS]
        if not specs then return false end
        local si = GetSpec and GetSpec()
        return si and specs[si] or false
    end
    return true
end

--- Color resolution (uses MSUF's PowerBarColor override system)
local _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
local _cachedColorToken = nil
local _cachedBgColorToken = nil
local _cachedBgColorR, _cachedBgColorG, _cachedBgColorB = 0, 0, 0
local _staggerCachedTier = 0  --- Stagger: avoid redundant SetStatusBarColor when tier unchanged
local _cachedChargedR, _cachedChargedG, _cachedChargedB

--- Maelstrom Weapon 5+ threshold color (cached independently)
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
    _mwAbove5R, _mwAbove5G, _mwAbove5B = 1.00, 0.50, 0.00  --- Sensei orange default
    return _mwAbove5R, _mwAbove5G, _mwAbove5B
end

local function ResolveClassPowerColor(powerType)
    --- Token resolution: numeric powerType -> string token, string -> use directly
    local token = POWER_TYPE_TOKENS[powerType]
    if not token and type(powerType) == "string" then
        token = powerType  --- already a string token (e.g. "RESOURCE_TEXT", "SOUL_FRAGMENTS")
    end
    if token == _cachedColorToken and _cachedColorToken then
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    _cachedColorToken = token

    --- 1. Custom class-power color override (from Colors panel)
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

    --- 2. MSUF power bar color override
    if _G.MSUF_GetPowerBarColor and token then
        local r, g, b = _G.MSUF_GetPowerBarColor(powerType, token)
        if type(r) == "number" then
            _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
            return r, g, b
        end
    end

    --- Fallback: Blizzard PowerBarColor
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

    --- Hard fallback
    if token == "IRONFUR" then
        _cachedColorR, _cachedColorG, _cachedColorB = 1.00, 0.49, 0.04
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
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

local function CP_InvalidateColorCaches()
    _cachedColorToken = nil
    _cachedBgColorToken = nil
    _cachedChargedR = nil
    _cachedChargedG = nil
    _cachedChargedB = nil
    _staggerCachedTier = 0
    _mwAbove5Resolved = false
end

--- Public: invalidate class power color cache (called from Colors panel)
local function MSUF_ClassPower_InvalidateColors()
    CP_InvalidateColorCaches()
    --- Balance Druid: refresh eclipse + prediction overlay colors
    if _G.MSUF_BAL_InvalidateColors then
        _G.MSUF_BAL_InvalidateColors()
    end
    if _G.MSUF_ClassPower_Apply then
        _G.MSUF_ClassPower_Apply({ visuals = true, playerHP = true })
    elseif _G.MSUF_ClassPower_Refresh then
        _G.MSUF_ClassPower_Refresh()
    end
end
ExportPublic("MSUF_ClassPower_InvalidateColors", MSUF_ClassPower_InvalidateColors)

--- Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
--- GetUnitChargedPowerPoints("player") returns a table of 1-based indices
--- that represent which combo point slots are "charged". These are non-secret
--- in WoW 12.0 builds.
local _chargedMap = {}    --- reused [index] = true map
local _chargedAny = false

local function RefreshChargedPoints()
    for index in pairs(_chargedMap) do
        _chargedMap[index] = nil
    end
    _chargedAny = false
    if type(GetUnitChargedPowerPoints) ~= "function" then return end

    local indices = GetUnitChargedPowerPoints("player")
    if not CanAccessTableValue(indices) or #indices == 0 then return end

    for i = 1, #indices do
        local idx = indices[i]
        if type(idx) == "number" then
            _chargedMap[idx] = true
            _chargedAny = true
        end
    end
end

--- Charged/empowered color resolution

local function ResolveChargedColor()
    if _cachedChargedR then
        return _cachedChargedR, _cachedChargedG, _cachedChargedB
    end

    --- 1. Custom override from Colors panel
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

    --- 2. Default: MidnightRogueBars purple
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

local function ResolveSlotColorMode(powerToken)
    local modes = _cpDB.slotColorModes
    local mode = modes and modes[powerToken]
    -- Preserve existing Rogue profiles and Assistant actions without copying
    -- the legacy value into every profile.
    if mode == nil and powerToken == "COMBO_POINTS" then mode = _cpDB.comboPointColorMode end
    if mode ~= "ramp" and mode ~= "custom" then return "default" end
    return mode
end

local function ResolveSlotColor(powerToken, slot, baseR, baseG, baseB)
    local mode = ResolveSlotColorMode(powerToken)
    if mode ~= "ramp" and mode ~= "custom" then return nil end

    slot = tonumber(slot) or 1
    if slot < 1 then slot = 1 elseif slot > 10 then slot = 10 end

    if mode == "custom" then
        local ov = _cpDB.colorOverrides
        local slotToken = powerToken == "COMBO_POINTS" and COMBO_POINT_SLOT_TOKENS[slot]
            or (powerToken and (powerToken .. "_" .. tostring(slot)))
        local c = slotToken and ov and ov[slotToken]
        if type(c) == "table" then
            local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b
            end
        end
        if powerToken ~= "COMBO_POINTS" then return baseR, baseG, baseB end
    end

    -- The established Rogue ramp remains the fallback for untouched custom
    -- slots. Resources with 8-10 segments continue with its final red tier.
    local rampSlot = slot > 7 and 7 or slot
    return COMBO_POINT_RAMP_R[rampSlot] or baseR, COMBO_POINT_RAMP_G[rampSlot] or baseG, COMBO_POINT_RAMP_B[rampSlot] or baseB
end

local function ResolveFullResourceColor(powerToken, baseR, baseG, baseB)
    local enabled = _cpDB.fullColorEnabled
    if not (powerToken and enabled and enabled[powerToken] == true) then return false, baseR, baseG, baseB end
    local overrides = _cpDB.colorOverrides
    local color = overrides and overrides[powerToken .. "_FULL"]
    if type(color) == "table" then
        local r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return true, r, g, b end
    end
    return true, baseR, baseG, baseB
end

--- ClassPower visual: segmented bars (created lazily on player frame)
--- Scale-compensated width helper lives in ClassPower presentation helpers
local CDM_GetScaledWidth

local CP = {
    bars      = {},      --- [i] = StatusBar
    ticks     = {},      --- [i] = Texture (separator lines)
    bgTex     = nil,     --- background texture
    container = nil,     --- parent frame
    textFrame = nil,     --- Shared elevated overlay for resource and Rune text
    text      = nil,     --- FontString: resource count (e.g. "4")
    maxBars   = 0,       --- currently allocated bar count
    currentMax = 0,      --- current max power (e.g. 5 combo pts)
    powerType = nil,     --- current Enum.PowerType or string token
    renderMode = CPK.MODE.NONE,  --- active render mode
    isAuraPower = false, --- true ? driven by UNIT_AURA
    updateFn   = nil,    --- cached active mode update fn (avoids hot-path table lookups)
    modeProfile = nil,   --- cached active mode event profile for lite runtime bindings
    structuralFlags = nil, --- allocation-free structural state for rare/display-power checks
    structuralPowerType = nil,
    structuralRenderMode = nil,
    isVehicle = false,   --- true ? vehicle combo points active
    visible   = false,
    height    = 4,
    --- Warlock shard prediction state (Jay's approach: predicted post-cast value)
    wlPredDelta = 0,       --- shard delta for active cast (0 = no prediction)
    runeOUAAny  = false,   --- true if any rune bar currently has an OnUpdate
    runeNativeAny = false, --- true while any Rune bar uses a native duration
    essenceOUAAny = false, --- true if Essence recharge pip has an OnUpdate
    essenceNativeAny = false, --- true while one Essence pip uses a native duration
    powerToken  = nil,     --- cached POWER_TYPE_TOKENS[powerType] for hot event filters
    visual      = nil,     --- compiled static visual runtime values for active mode
    slotR       = {},      --- persistent compiled per-slot colors (no refresh allocations)
    slotG       = {},
    slotB       = {},
    augCompositeActive = false, --- Aug Essence + native Ebon replacement surface
    augCompositeHeight = nil,
    augEssenceHeight = nil,
    augEbonHeight = nil,
    augCompositeGap = nil,
    ebonSensorDesired = false,
    ebonTextLayerRetryPending = false,
    augLifecycleRetryPending = false,
    augLifecycleDisablePending = false,
    augLifecycleTarget = nil,
    --- Spell Tracker state (Tip of the Spear only - Whirlwind uses WW module)
    spStacks    = 0,       --- current stack count
    spExpires   = nil,     --- GetTime() expiry timestamp (nil = no timer)
}

--- Cold-path geometry contract consumed by the Player Power element. The
--- ordinary Power StatusBar remains the positioning/width carrier while its
--- own Mana visuals and events are disabled for the Augmentation composite.
function CP.GetAugPowerReplacementMetrics(frame)
    if CP.augCompositeActive ~= true then return false end
    if frame and frame.MSUFUnitKey and frame.MSUFUnitKey ~= "player" then return false end
    local essenceHeight = CP.augEssenceHeight
    local gap = CP.augCompositeGap
    local ebonHeight = CP.augEbonHeight
    local powerSpec = frame and frame.MSUFSpec and frame.MSUFSpec.power or nil
    local liveEbonHeight = tonumber(powerSpec and powerSpec.height)
    if liveEbonHeight then
        if liveEbonHeight < 1 then liveEbonHeight = 1 elseif liveEbonHeight > 30 then liveEbonHeight = 30 end
        if liveEbonHeight ~= ebonHeight then
            ebonHeight = liveEbonHeight
            CP.augEbonHeight = liveEbonHeight
            CP.augCompositeHeight = (tonumber(essenceHeight) or 4) + (tonumber(gap) or 2) + liveEbonHeight
            if CP.ebonHost and CP.ebonHost.SetHeight then
                CP.ebonHost:SetHeight(liveEbonHeight)
            end
        end
    end
    return true,
        CP.augCompositeHeight,
        essenceHeight,
        gap,
        ebonHeight,
        true
end
ExportPublic("MSUF_GetAugPowerReplacementMetrics", CP.GetAugPowerReplacementMetrics)

local function CP_ClearAugCompositeState()
    local wasActive = CP.augCompositeActive == true or _G.MSUF_AugEvokerActive == true
    CP.augCompositeActive = false
    CP.augCompositeHeight = nil
    CP.augEssenceHeight = nil
    CP.augEbonHeight = nil
    CP.augCompositeGap = nil
    CP.ebonSensorDesired = false
    CP.ebonSensorRetryPending = nil
    CP.ebonTextLayerRetryPending = nil
    ExportPublic("MSUF_AugEvokerActive", false)
    return wasActive
end

local CPAuras = {
    watched = {},
    bySpell = {},
    spellByInstance = {},
}

function CPAuras.NormalizeID(value)
    if value == nil then return nil end
    if NotSecret(value) == false then return nil end
    return tonumber(value)
end

function CPAuras.AddSpell(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if spellID then CPAuras.watched[spellID] = true end
end

function CPAuras.AuraSpellID(aura)
    return aura and CPAuras.NormalizeID(aura.spellId or aura.spellID or aura.id) or nil
end

function CPAuras.AuraInstanceID(aura)
    return aura and CPAuras.NormalizeID(aura.auraInstanceID) or nil
end

function CPAuras.ClearSpell(spellID, auraInstanceID)
    spellID = CPAuras.NormalizeID(spellID)
    auraInstanceID = CPAuras.NormalizeID(auraInstanceID)
    if auraInstanceID then CPAuras.spellByInstance[auraInstanceID] = nil end
    if spellID then
        local current = CPAuras.bySpell[spellID]
        if not auraInstanceID or not current or CPAuras.AuraInstanceID(current) == auraInstanceID then
            CPAuras.bySpell[spellID] = nil
        end
    end
end

function CPAuras.Store(aura)
    if not CanAccessTableValue(aura) then return false end
    local spellID = CPAuras.AuraSpellID(aura)
    if not (spellID and CPAuras.watched[spellID]) then return false end

    local auraInstanceID = CPAuras.AuraInstanceID(aura)
    if auraInstanceID then
        local oldSpellID = CPAuras.spellByInstance[auraInstanceID]
        if oldSpellID and oldSpellID ~= spellID then
            CPAuras.ClearSpell(oldSpellID, auraInstanceID)
        end
        CPAuras.spellByInstance[auraInstanceID] = spellID
    end

    CPAuras.bySpell[spellID] = aura
    return true
end

function CPAuras.ClearAll()
    if wipe then
        wipe(CPAuras.bySpell)
        wipe(CPAuras.spellByInstance)
        return
    end
    for k in pairs(CPAuras.bySpell) do CPAuras.bySpell[k] = nil end
    for k in pairs(CPAuras.spellByInstance) do CPAuras.spellByInstance[k] = nil end
end

function CPAuras.Fetch(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not (spellID and C_UnitAuras) then return nil end

    local aura
    if type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    elseif type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
        aura = C_UnitAuras.GetUnitAuraBySpellID("player", spellID)
    end
    if CanAccessTableValue(aura) then
        CPAuras.Store(aura)
    else
        aura = nil
    end
    return aura
end

local function CPAuraFieldEqual(left, right, key)
    local a = left and left[key]
    local b = right and right[key]
    if NotSecret(a) == false or NotSecret(b) == false then return false end
    return a == b
end

function CPAuras.SameState(left, right, stateKind)
    if left == right then return true end
    if not left or not right then return false end
    if stateKind == "timer" then
        return CPAuraFieldEqual(left, right, "expirationTime")
    end
    if stateKind == "tip" then
        return CPAuraFieldEqual(left, right, "applications")
            and CPAuraFieldEqual(left, right, "expirationTime")
    end
    --- Stack resources only render presence/application changes. Aura-instance
    --- and duration churn must not repaint ten Enhancement segments.
    return CPAuraFieldEqual(left, right, "applications")
end

function CPAuras.RefreshSpell(spellID, stateKind)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return false end

    local previous = CPAuras.bySpell[spellID]
    CPAuras.ClearSpell(spellID, previous and CPAuras.AuraInstanceID(previous))
    local current = CPAuras.Fetch(spellID)
    return not CPAuras.SameState(previous, current, stateKind)
end

function CPAuras.ActiveSpellKind(powerType, renderMode, spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return nil end
    if powerType == "MAELSTROM_WEAPON" and spellID == CPK.SPELL.MAELSTROM_WEAPON then return "stacks" end
    if powerType == "ICICLES" and CPConst.ICICLES and spellID == CPConst.ICICLES.AURA_ID then return "stacks" end
    if powerType == "SOUL_FRAGMENTS" then
        if spellID == CPK.SPELL.VOID_METAMORPHOSIS
            or spellID == CPK.SPELL.SILENCE_THE_WHISPERS
            or spellID == CPK.SPELL.DARK_HEART then
            return "stacks"
        end
    end
    return nil
end

function CPAuras.RefreshActive(powerType, renderMode)
    local changed = false
    local handled = true
    local function Refresh(spellID, stateKind)
        if CPAuras.RefreshSpell(spellID, stateKind) then changed = true end
    end

    if powerType == "MAELSTROM_WEAPON" then
        Refresh(CPK.SPELL.MAELSTROM_WEAPON, "stacks")
    elseif powerType == "ICICLES" then
        Refresh(CPConst.ICICLES and CPConst.ICICLES.AURA_ID, "stacks")
    elseif powerType == "SOUL_FRAGMENTS" then
        Refresh(CPK.SPELL.VOID_METAMORPHOSIS, "stacks")
        Refresh(CPK.SPELL.SILENCE_THE_WHISPERS, "stacks")
        Refresh(CPK.SPELL.DARK_HEART, "stacks")
    elseif powerType == "SOUL_FRAGMENTS_VENG" then
        --- Vengeance reads the native spell cast count; UNIT_AURA is only a
        --- value-change signal and does not require any aura-cache queries.
        changed = true
    else
        handled = false
    end

    if not handled then
        CPAuras.Rebuild()
        return true
    end
    return changed
end

function CPAuras.IsExpired(aura)
    local expirationTime = aura and aura.expirationTime
    if NotSecret(expirationTime) == false or expirationTime == nil then return false end
    expirationTime = tonumber(expirationTime)
    return expirationTime and expirationTime > 0 and expirationTime <= GetTime()
end

function CPAuras.Get(spellID)
    spellID = CPAuras.NormalizeID(spellID)
    if not spellID then return nil end

    local aura = CPAuras.bySpell[spellID]
    if aura then
        if not CPAuras.IsExpired(aura) then return aura end
        CPAuras.ClearSpell(spellID, CPAuras.AuraInstanceID(aura))
    end

    return CPAuras.Fetch(spellID)
end

function CPAuras.Rebuild()
    CPAuras.ClearAll()
    local canFetchBySpell = C_UnitAuras and (
        type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
        or type(C_UnitAuras.GetUnitAuraBySpellID) == "function"
    )
    if canFetchBySpell then
        --- Only the small watched set matters to ClassPower. This avoids a
        --- full helpful-aura scan on secret UNIT_AURA fallback updates.
        for spellID in pairs(CPAuras.watched) do
            CPAuras.Fetch(spellID)
        end
    else
        CPAuras.ScanUnitAuras()
    end
end

function CPAuras.FetchByInstanceID(auraInstanceID)
    auraInstanceID = CPAuras.NormalizeID(auraInstanceID)
    if not (auraInstanceID and C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function") then
        return nil
    end
    return C_UnitAuras.GetAuraDataByAuraInstanceID("player", auraInstanceID)
end

function CPAuras.CanProcessIncrementalUpdate(unitAuraUpdateInfo)
    if not CanAccessTableValue(unitAuraUpdateInfo) then return false end

    --- Midnight/PTR can mark UNIT_AURA update fields secret. Addon code may
    --- pass those values to issecretvalue, but it must not branch on them or
    --- iterate secret tables. Fall back to the small player-aura rebuild.
    local isFullUpdate = unitAuraUpdateInfo.isFullUpdate
    if NotSecret(isFullUpdate) == false or isFullUpdate then return false end

    local addedAuras = unitAuraUpdateInfo.addedAuras
    local updatedAuraInstanceIDs = unitAuraUpdateInfo.updatedAuraInstanceIDs
    local removedAuraInstanceIDs = unitAuraUpdateInfo.removedAuraInstanceIDs
    return CanAccessOptionalTableValue(addedAuras)
        and CanAccessOptionalTableValue(updatedAuraInstanceIDs)
        and CanAccessOptionalTableValue(removedAuraInstanceIDs)
end

function CPAuras.ScanUnitAuras()
    if not (C_UnitAuras and type(C_UnitAuras.GetUnitAuras) == "function") then return end
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if not CanAccessTableValue(auras) then return end
    for i = 1, #auras do
        CPAuras.Store(auras[i])
    end
end

function CPAuras.ProcessUnitAuraUpdate(unitAuraUpdateInfo, powerType, renderMode)
    if powerType == "ICICLES" then
        --- Icicles owns one exact player aura. Refresh it directly on each
        --- UNIT_AURA signal instead of relying on incremental aura identity,
        --- which can be restricted, incomplete, or unrelated on Midnight.
        --- The returned applications value remains secret-safe because the
        --- segmented renderer passes it only to native StatusBar setters.
        CPAuras.RefreshSpell(CPConst.ICICLES and CPConst.ICICLES.AURA_ID, "stacks")
        return true
    end

    if not CPAuras.CanProcessIncrementalUpdate(unitAuraUpdateInfo) then
        --- Midnight can hide the incremental payload. Refresh only the aura(s)
        --- consumed by the active resource instead of querying every class.
        return CPAuras.RefreshActive(powerType, renderMode)
    end

    local changed = powerType == "SOUL_FRAGMENTS_VENG"
    local addedAuras = unitAuraUpdateInfo.addedAuras
    if addedAuras then
        for i = 1, #addedAuras do
            local aura = addedAuras[i]
            local spellID = CanAccessTableValue(aura) and CPAuras.AuraSpellID(aura) or nil
            if CPAuras.Store(aura) and CPAuras.ActiveSpellKind(powerType, renderMode, spellID) then
                changed = true
            end
        end
    end

    local updatedAuraInstanceIDs = unitAuraUpdateInfo.updatedAuraInstanceIDs
    if updatedAuraInstanceIDs then
        for i = 1, #updatedAuraInstanceIDs do
            local auraInstanceID = CPAuras.NormalizeID(updatedAuraInstanceIDs[i])
            local spellID = auraInstanceID and CPAuras.spellByInstance[auraInstanceID]
            if spellID then
                local previous = CPAuras.bySpell[spellID]
                local aura = CPAuras.FetchByInstanceID(auraInstanceID)
                local current
                if CanAccessTableValue(aura) then
                    CPAuras.Store(aura)
                    current = aura
                else
                    CPAuras.ClearSpell(spellID, auraInstanceID)
                end
                local stateKind = CPAuras.ActiveSpellKind(powerType, renderMode, spellID)
                if stateKind and not CPAuras.SameState(previous, current, stateKind) then changed = true end
            end
        end
    end

    local removedAuraInstanceIDs = unitAuraUpdateInfo.removedAuraInstanceIDs
    if removedAuraInstanceIDs then
        for i = 1, #removedAuraInstanceIDs do
            local auraInstanceID = CPAuras.NormalizeID(removedAuraInstanceIDs[i])
            local spellID = auraInstanceID and CPAuras.spellByInstance[auraInstanceID]
            if spellID then
                CPAuras.ClearSpell(spellID, auraInstanceID)
                if CPAuras.ActiveSpellKind(powerType, renderMode, spellID) then changed = true end
            end
        end
    end
    return changed
end

CPAuras.AddSpell(CPK.SPELL.MAELSTROM_WEAPON)
CPAuras.AddSpell(CPConst.ICICLES and CPConst.ICICLES.AURA_ID)
CPAuras.AddSpell(CPK.SPELL.VOID_METAMORPHOSIS)
CPAuras.AddSpell(CPK.SPELL.SILENCE_THE_WHISPERS)
CPAuras.AddSpell(CPK.SPELL.DARK_HEART)
for spellID in pairs(CPConst.ECLIPSE_AURAS or {}) do
    CPAuras.AddSpell(spellID)
end

ExportPublic("MSUF_CP_GetTrackedPlayerAura", CPAuras.Get)

--- Cached alpha values (resolved once in FullRefresh, used in hot paths)
local _filledAlpha = 1.0
local _emptyAlpha  = 0.3

--- DK Rune map: [display_slot] = rune_id (1-6), sorted per sortOrder
local _runeMap = { 1, 2, 3, 4, 5, 6 }
local _runeAppliedSortOrder = "natural"

local function CP_CompileVisual(powerType, renderMode, maxP)
    local b = _cpDB.bars or {}
    local visual = CP.visual
    if not visual then
        visual = {}
        CP.visual = visual
    elseif wipe then
        wipe(visual)
    else
        for k in pairs(visual) do visual[k] = nil end
    end

    local colorByType = _cpDB.colorByType ~= false
    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end
    local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
    local chargedR, chargedG, chargedB = ResolveChargedColor()

    visual.powerType = powerType
    CP.visualVersion = (CP.visualVersion or 0) + 1
    visual.version = CP.visualVersion
    visual.powerToken = POWER_TYPE_TOKENS[powerType] or (type(powerType) == "string" and powerType or nil)
    visual.renderMode = renderMode
    visual.maxP = maxP
    visual.colorByType = colorByType
    visual.showText = _cpDB.showText == true
    visual.showPrediction = _cpDB.showPrediction ~= false
    visual.showCharged = _cpDB.showCharged ~= false
    visual.smoothInterp = _cpDB.classSmooth and SMOOTH_INTERP or nil
    visual.filledAlpha = _filledAlpha
    visual.emptyAlpha = _emptyAlpha
    visual.bgAlpha = _cpDB.bgAlpha or 0.3
    visual.baseR, visual.baseG, visual.baseB = baseR, baseG, baseB
    visual.bgR, visual.bgG, visual.bgB = bgR, bgG, bgB
    visual.chargedR, visual.chargedG, visual.chargedB = chargedR, chargedG, chargedB
    visual.runeShowTime = b.runeShowTime ~= false
    visual.timerShowText = b.classPowerShowText == true
    local slotMode = ResolveSlotColorMode(visual.powerToken)
    local segmentedMode = renderMode == CPK.MODE.SEGMENTED
        or renderMode == CPK.MODE.FRACTIONAL
        or renderMode == CPK.MODE.RUNE_CD
        or renderMode == CPK.MODE.AURA_SEGMENTED
    visual.useSlotColors = segmentedMode and (slotMode == "ramp" or slotMode == "custom")
    visual.useFullColor, visual.fullR, visual.fullG, visual.fullB = ResolveFullResourceColor(
        visual.powerToken, baseR, baseG, baseB)
    if not segmentedMode then visual.useFullColor = false end

    if visual.useSlotColors then
        visual.slotR, visual.slotG, visual.slotB = CP.slotR, CP.slotG, CP.slotB
        for i = 1, math_min(tonumber(maxP) or 0, 10) do
            local r, g, bl = ResolveSlotColor(visual.powerToken, i, baseR, baseG, baseB)
            visual.slotR[i], visual.slotG[i], visual.slotB[i] = r, g, bl
        end
    end

    return visual
end

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
    --- Fallback: global bar texture -> flat white
    local getBar = _G.MSUF_GetBarTexture
    return (getBar and getBar()) or "Interface\\Buttons\\WHITE8x8"
end

local CP_EnsureBars
local CP_Create
local CP_EnsureRuneText
local CP_EnsureMainText

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
        CP_EnsureRuneText = build.CP_EnsureRuneText
        CP_EnsureMainText = build.CP_EnsureMainText
    end
end

--- Font / text-offset presentation helpers now live in
--- ClassPower presentation helpers.
local CP_ApplyTextOffset
local CP_ApplyFont
local CP_ApplyColors
local CP_RefreshTexture

--- Auto-Hide: visibility check after each update (OOC / Full / Empty)
--- Zero overhead when all three are disabled (early-out on first check).
local _autoHideActive = false  --- true if any auto-hide option is enabled

local function CP_CheckAutoHide(cur, maxP)
    if not _autoHideActive or not CP.visible then return end
    if not CP.container then return end

    if _G.MSUF_UnitEditModeActive == true then
        CP.container:SetAlpha(1)
        return
    end

    local b = _cpDB.bars or {}

    --- OOC: hide when out of combat
    if b.classPowerHideOOC and not InCombatLockdown() then
        CP.container:SetAlpha(0)
        return
    end

    --- Full: hide when all resources are at max
    if b.classPowerHideWhenFull and NotSecret(cur) and NotSecret(maxP) then
        if cur ~= nil and maxP ~= nil and cur >= maxP and maxP > 0 then
            CP.container:SetAlpha(0)
            return
        end
    end

    --- Empty: hide when zero resources
    if b.classPowerHideWhenEmpty and NotSecret(cur) then
        if cur ~= nil and cur <= 0 then
            CP.container:SetAlpha(0)
            return
        end
    end

    --- Visible: restore alpha
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

--- Secret-safe value update + per-bar coloring (charged/empowered support)
--- Phase 2 CP split: segmented / fractional / aura mode runners now live in
--- ClassPower/Modes/*.lua. The core builds them with local env closures so the
--- public runtime stays identical while the main chunk gets smaller.
local CP_UpdateValues
local CP_UpdateValues_Fractional
local CP_UpdateValues_AuraSegmented
local CP_UpdateValues_AuraSingle
local CP_UpdateValues_Continuous
local CP_UpdateValues_RuneCD
local CP_UpdateEbonHost
local CP_UpdateValues_Stagger
local CP_StopEssenceOnUpdates
local _essenceRuntimeTick
local _staggerRuntimeTick

do
    local commonEnv = {
        CP = CP,
        _cpDB = _cpDB,
        CPConst = CPConst,
        CPK = CPK,
        PT = PT,
        PLAYER_CLASS = PLAYER_CLASS,
        UnitPower = UnitPower,
        UnitPartialPower = UnitPartialPower,
        UnitPowerDisplayMod = UnitPowerDisplayMod,
        C_UnitAuras = C_UnitAuras,
        GetTrackedPlayerAura = CPAuras.Get,
        C_Spell = C_Spell,
        GetSpec = GetSpec,
        GetTime = GetTime,
        NotSecret = NotSecret,
        ResolveClassPowerColor = ResolveClassPowerColor,
        ResolveClassPowerBgColor = ResolveClassPowerBgColor,
        ResolveChargedColor = ResolveChargedColor,
        ResolveSlotColor = ResolveSlotColor,
        ResolveFullResourceColor = ResolveFullResourceColor,
        ResolveMWAbove5Color = ResolveMWAbove5Color,
        CP_CheckAutoHide = CP_CheckAutoHide,
        WW = WW,
        TIP = TIP,
        GetFilledAlpha = function() return _filledAlpha end,
        GetEmptyAlpha = function() return _emptyAlpha end,
        GetVisual = function() return CP.visual end,
        GetChargedMap = function() return _chargedAny and _chargedMap or nil end,
        GetPowerRegenForPowerType = GetPowerRegenForPowerType,
        C_DurationUtil = _G.C_DurationUtil,
        C_StringUtil = _G.C_StringUtil,
        Enum = _G.Enum,
        EnsureRuneText = CP_EnsureRuneText,
        EnsureMainText = CP_EnsureMainText,
        ApplyFont = function() if CP_ApplyFont then CP_ApplyFont() end end,
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

    commonEnv.UnitStagger = UnitStagger
    commonEnv.UnitHealthMax = UnitHealthMax
    commonEnv.STAGGER_CONST = CPConst.STAGGER or {}
    local stagger = CP_CallBuilder(CPModeBuilders.STAGGER, commonEnv)
    if stagger and type(stagger.Update) == "function" then CP_UpdateValues_Stagger = stagger.Update end
    if stagger and type(stagger.RuntimeTick) == "function" then _staggerRuntimeTick = stagger.RuntimeTick end
    --- Ironfur is built lazily on the first enabled Guardian/Bear refresh so
    --- the default-off feature creates no frames and binds no events.
    CP.ironfur = nil
    CP.BuildIronfur = PLAYER_CLASS == "DRUID" and function()
        return CP_CallBuilder(CPModeBuilders.IRONFUR, {
            PLAYER_CLASS = PLAYER_CLASS,
            CP = CP,
            CPK = CPK,
            _cpDB = _cpDB,
            GetTime = GetTime,
            CP_CheckAutoHide = CP_CheckAutoHide,
            EnsureMainText = CP_EnsureMainText,
            ApplyFont = function() if CP_ApplyFont then CP_ApplyFont() end end,
            GetVisual = function() return CP.visual end,
        })
    end or nil
end

--- Phase 7A CP split: pure presentation helpers now live in
--- ClassPower presentation helpers. This keeps the core smaller without
--- touching build/layout/value flow.
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
ExportPublic("MSUF_CDM_GetScaledWidth", CDM_GetScaledWidth)

local function CP_EnsureEbonHost()
    if CP.ebonHost then return CP.ebonHost end
    local container = CP.container
    if not container then return nil end
    local host = CreateFrame("Frame", nil, container)
    if host.EnableMouse then host:EnableMouse(false) end
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(host)
    CP.ebonHostBG = bg
    host:Hide()
    CP.ebonHost = host
    return host
end

local function CP_LayoutEbonHost()
    local host = CP_EnsureEbonHost()
    if not (host and CP.container and CP.augCompositeActive == true) then return host end
    local h = tonumber(CP.augEbonHeight) or 3
    local gap = tonumber(CP.augCompositeGap) or 2
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", CP.container, "BOTTOMLEFT", 0, -gap)
    host:SetPoint("TOPRIGHT", CP.container, "BOTTOMRIGHT", 0, -gap)
    host:SetHeight(h)
    if host.SetFrameLevel and CP.container.GetFrameLevel then
        host:SetFrameLevel((CP.container:GetFrameLevel() or 0) + 1)
    end
    local bg = CP.ebonHostBG
    if bg then
        local b = _cpDB.bars or {}
        local bgPath = CP_ResolveTexture(b.classPowerBgTexture or b.classPowerTexture)
        local r, g, blue = ResolveClassPowerBgColor("EBON_MIGHT")
        bg:SetTexture(bgPath)
        bg:SetVertexColor(tonumber(r) or 0, tonumber(g) or 0, tonumber(blue) or 0,
            tonumber(b.classPowerBgAlpha) or 0.3)
    end
    return host
end

function CP.GetEbonTextLevel()
    local b = _cpDB.bars or {}
    local textLayer = tonumber(b.classPowerTextLayer) or 5
    if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
    textLayer = math_floor(textLayer + 0.5)
    local layers = MSUF.UF and MSUF.UF.Layers
    return layers and layers.TextLevel and layers.TextLevel(CP.container, textLayer, 5)
        or (layers and layers.ElementLevel and layers.ElementLevel(textLayer, 5, 8))
        or ((CP.container and CP.container.GetFrameLevel and CP.container:GetFrameLevel() or 0) + 10)
end

local function CP_GetEbonStyle()
    local b = _cpDB.bars or {}
    local r, g, blue = 1, 1, 1
    if _cpDB.colorByType ~= false then
        r, g, blue = ResolveClassPowerColor("EBON_MIGHT")
    end
    local style = {
        texture = CP_ResolveTexture(b.classPowerTexture),
        barR = r, barG = g, barB = blue, barA = _filledAlpha,
        textLevel = CP.GetEbonTextLevel(),
        textOffsetX = tonumber(b.classPowerTextOffsetX) or 0,
        textOffsetY = tonumber(b.classPowerTextOffsetY) or 0,
    }
    local source = CP.text
    if source then
        if type(source.GetFont) == "function" then
            style.fontPath, style.fontSize, style.fontFlags = source:GetFont()
        end
        if type(source.GetTextColor) == "function" then
            style.textR, style.textG, style.textB, style.textA = source:GetTextColor()
        end
        if type(source.GetShadowColor) == "function" then
            style.shadowR, style.shadowG, style.shadowB, style.shadowA = source:GetShadowColor()
        end
        if type(source.GetShadowOffset) == "function" then
            style.shadowX, style.shadowY = source:GetShadowOffset()
        end
    end
    return style
end

CP.ebonNative = CP_CallBuilder(CPCoreBuilders.EBON_MIGHT, {
    CP = CP,
    EBON = EBON,
    _cpDB = _cpDB,
    CreateFrame = CreateFrame,
    GetHost = CP_LayoutEbonHost,
    GetStyle = CP_GetEbonStyle,
    GetTextLevel = CP.GetEbonTextLevel,
})

--- Legacy color-only refresh / texture refresh now live in
--- ClassPower presentation helpers.

--- CPK.MODE.FRACTIONAL: Destruction Warlock - partial Soul Shard fill.
--- UnitPower(unit, type, true) / UnitPowerDisplayMod(type) gives e.g. 3.7
--- Fractional mode runner moved to ClassPower/Modes/MSUF_CP_Mode_Fractional.lua

--- Rune cooldown animation and the Stagger fallback share one central driver.
--- Ebon Might is fully native in 12.1 and never enters this driver.
local CP_StopRuneOnUpdates

--- Central CP runtime tick for Stagger and guarded degraded fallbacks.
local _cpTickFrame
local _cpTickActive = false
local _cpTickFn = nil
local _cpTickElapsed = 0
local CP_TICK_INTERVAL = 1 / 30
local CP_StopCentralTick

local function CP_CentralTickOnUpdate(_, elapsed)
    if not _cpTickFn then return end
    _cpTickElapsed = _cpTickElapsed + (elapsed or 0)
    if _cpTickElapsed < CP_TICK_INTERVAL then return end
    local dt = _cpTickElapsed
    _cpTickElapsed = 0
    if _cpTickFn(dt) == false then
        CP_StopCentralTick()
    end
end

local function CP_StartCentralTick(tickFn)
    if type(tickFn) ~= "function" then return end
    local previousTickFn = _cpTickFn
    _cpTickFn = tickFn
    if not _cpTickActive then
        _cpTickElapsed = 0
        if not _cpTickFrame then
            _cpTickFrame = CreateFrame("Frame", nil, UIParent)
        end
        _cpTickFrame:SetScript("OnUpdate", CP_CentralTickOnUpdate)
        _cpTickFrame:Show()
        _cpTickActive = true
    elseif previousTickFn ~= tickFn then
        --- Mode switch mid-tick: swap function and restart its elapsed budget.
        _cpTickElapsed = 0
    end
end

CP_StopCentralTick = function()
    if not _cpTickActive then return end
    _cpTickFn = nil
    _cpTickElapsed = 0
    _cpTickFrame:SetScript("OnUpdate", nil)
    _cpTickFrame:Hide()
    _cpTickActive = false
end

local _runeRuntimeTick

do
    local commonEnv = {
        CP = CP,
        _cpDB = _cpDB,
        CPK = CPK,
        NotSecret = NotSecret,
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
        GetVisual = function() return CP.visual end,
        EnsureRuneText = CP_EnsureRuneText,
        ApplyFont = function() if CP_ApplyFont then CP_ApplyFont() end end,
    }

    local rune = CP_CallBuilder(CPModeBuilders.RUNE, commonEnv)
    if rune then
        if type(rune.Update) == "function" then CP_UpdateValues_RuneCD = rune.Update end
        if type(rune.StopOnUpdates) == "function" then CP_StopRuneOnUpdates = rune.StopOnUpdates end
        if type(rune.RuntimeTick) == "function" then _runeRuntimeTick = rune.RuntimeTick end
    end

    local timer = CP_CallBuilder(CPModeBuilders.TIMER, commonEnv)
    if timer then
        if type(timer.Update) == "function" then CP_UpdateEbonHost = timer.Update end
    end
end

local function CP_SyncRuntimeOnUpdates(timerActive)
    local mode = CP.renderMode

    --- Determine active tick function based on current mode + animation state.
    if mode == CPK.MODE.RUNE_CD then
        --- Rune mode: stop others, tick runes if any active.
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if CP.runeOUAAny and _runeRuntimeTick then
            CP_StartCentralTick(_runeRuntimeTick)
        else
            CP_StopCentralTick()
        end
        return
    end

    --- Not rune mode: stop rune animations.
    if (CP.runeOUAAny or CP.runeNativeAny) and CP_StopRuneOnUpdates then
        CP_StopRuneOnUpdates(false)
    end

    if mode == CPK.MODE.STAGGER then
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        if timerActive and _staggerRuntimeTick then
            CP_StartCentralTick(_staggerRuntimeTick)
        else
            CP_StopCentralTick()
        end
        return
    end

    if mode == CPK.MODE.TIMER_BAR then
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        CP_StopCentralTick()
    else
        --- SEGMENTED mode: essence may tick.
        if CP.essenceOUAAny and _essenceRuntimeTick then
            CP_StartCentralTick(_essenceRuntimeTick)
        else
            CP_StopCentralTick()
        end
    end
end

local CP_RunActiveUpdate

--- Phase 5 CP split: class/resource specials now live in
--- ClassPower/Features/MSUF_CP_Specials.lua. The core builds the handlers from a
--- small feature builder so event wiring stays identical while class-specific
--- logic stops bloating the orchestrator chunk.
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
            C_Timer = C_Timer,
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

--- Phase 4 CP split: continuous + stagger mode runners now live in
--- ClassPower/Modes/MSUF_CP_Mode_Continuous.lua and MSUF_CP_Mode_Stagger.lua.
--- The core keeps only orchestration and event wiring, while the heavy single-bar
--- runners live outside the main chunk.

--- Update function dispatch table (set in FullRefresh, called in hot path)
local MODE_UPDATE_FN = {
    [CPK.MODE.SEGMENTED]      = CP_UpdateValues,
    [CPK.MODE.FRACTIONAL]     = CP_UpdateValues_Fractional,
    [CPK.MODE.RUNE_CD]        = CP_UpdateValues_RuneCD,
    [CPK.MODE.AURA_SEGMENTED] = CP_UpdateValues_AuraSegmented,
    [CPK.MODE.AURA_SINGLE]    = CP_UpdateValues_AuraSingle,
    [CPK.MODE.CONTINUOUS]     = CP_UpdateValues_Continuous,
    [CPK.MODE.TIMER_BAR]      = CP_UpdateEbonHost,
    [CPK.MODE.STAGGER]        = CP_UpdateValues_Stagger,
    [CPK.MODE.IRONFUR]        = CP.ironfur and CP.ironfur.Update or nil,
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
    --- Tip is fully spellcast-tracked. Do not bind UNIT_AURA or touch
    --- its protected aura payload for a resource whose state is deterministic.
    if powerType == "TIP_OF_THE_SPEAR" then profile.aura = false end
    profile.deadAlive = (powerType == "TIP_OF_THE_SPEAR")
    return profile
end

CP_RunActiveUpdate = function(powerType, maxP)
    local updateFn = CP.updateFn
    if not updateFn then return false end
    if not CP.visual then
        CP_CompileVisual(powerType or CP.powerType, CP.renderMode, maxP or CP.currentMax)
    end
    local timerActive = (updateFn(powerType or CP.powerType, maxP or CP.currentMax) == true)
    CP_SyncRuntimeOnUpdates(timerActive)
    return timerActive
end

local function CP_ComputeStructuralSignature()
    local b = _cpDB.bars or {}
    local cpEnabled = b.showClassPower ~= false
    local newPowerType, newRenderMode, newAuraPower
    if cpEnabled then
        newPowerType, newRenderMode, newAuraPower = GetClassPowerType()
    else
        newRenderMode = CPK.MODE.NONE
    end
    local newVehicle = (cpEnabled and UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
    local wantAugComposite = cpEnabled and newPowerType == PT.Essence
        and PLAYER_CLASS == "EVOKER"
        and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
        and b.showEbonMight ~= false
    local wantCPVisible = cpEnabled and newPowerType and newRenderMode ~= CPK.MODE.NONE
    local wantAMVisible = (b.showAltMana == true) and NeedsAltManaBar() and (_G.MSUF_UnitEditModeActive ~= true)
    local flags = (wantCPVisible and 1 or 0)
        + (wantAMVisible and 2 or 0)
        + (newAuraPower and 4 or 0)
        + (newVehicle and 8 or 0)
        + (wantAugComposite and 16 or 0)
    return flags, newPowerType, newRenderMode or CPK.MODE.NONE
end

--- Forward declaration (AM defined later)
local AM

--- AltMana visual: single StatusBar (created lazily on player frame)
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

--- Master show/hide + layout integration

local function GetPlayerFrame()
    return CoreUnitFrame("player") or _G.MSUF_player or nil
end

--- "Sync width to Class Resource" matches the container only while it is really
--- shown. Nothing else observes that transition - the cooldown-width observers
--- watch Blizzard viewers, and CP_Layout only runs while the bar is alive - so
--- notify the Power element from the show/hide path itself. Width-only: no
--- config compile and no element routing.
--- Lives on CP instead of a file-scope local: this file is at the Lua 5.1
--- 200-local ceiling.
function CP.RefreshSyncedPowerWidth(playerFrame)
    playerFrame = playerFrame or GetPlayerFrame()
    local spec = playerFrame and playerFrame.MSUFSpec
    local power = spec and spec.power
    if not (power and power.detachedSyncClass == true) then return false end
    --- Geometry stays out of lockdown like every other layout path here; the
    --- element refresh queues itself until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        local queued = _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey
        return type(queued) == "function" and queued("player") and true or false
    end
    local elements = MSUF and MSUF.UF and MSUF.UF.Elements
    local element = elements and elements.Power
    local refresh = element and element.RefreshDetachedSyncedWidth
    if type(refresh) ~= "function" then return false end
    return refresh(playerFrame, power) and true or false
end

local PHP = { visible = false }
local CP_PlayerHPRefresh = CP_Noop
local CP_PlayerHPUpdate = CP_Noop
local CP_PlayerHPApplyFont = CP_Noop

local function CP_PlayerHPNeedsRefresh()
    return PHP.visible == true or CP_ConfigPlayerHPBarEnabled()
end

do
    local playerHP = CP_CallBuilder(CPCoreBuilders.PLAYER_HP, {
            PHP = PHP,
            CP = CP,
            _cpDB = _cpDB,
            UnitHealth = UnitHealth,
            UnitHealthMax = UnitHealthMax,
            UnitClass = UnitClass,
            RAID_CLASS_COLORS = RAID_CLASS_COLORS,
            CreateFrame = CreateFrame,
            GetPlayerFrame = GetPlayerFrame,
            ResolveTexture = CP_ResolveTexture,
            tonumber = tonumber,
            type = type,
            tostring = tostring,
            pairs = pairs,
            math_floor = math_floor,
            string_format = string_format,
        })
    if playerHP then
        PHP = playerHP.PHP or PHP
        CP_PlayerHPRefresh = playerHP.Refresh or CP_PlayerHPRefresh
        CP_PlayerHPUpdate = playerHP.Update or CP_PlayerHPUpdate
        CP_PlayerHPApplyFont = playerHP.ApplyFont or CP_PlayerHPApplyFont
    end
end

local function CP_ShouldMaintainHiddenAnchor()
    local p = MSUF_DB and MSUF_DB.player
    if not p or p.powerBarDetached ~= true or p.detachedPowerBarAnchorToClassPower ~= true then
        return false
    end
    local b = _cpDB.bars or {}
    return b.showClassPower ~= false
end

local function CP_EnsureHiddenAnchorGeometry(playerFrame, cpHeight)
    if not (playerFrame and CP_Create and CP_EnsureBars and CP_Layout) then return false end
    if not CP_ShouldMaintainHiddenAnchor() then return false end

    CP_Create(playerFrame)

    local maxP = tonumber(CP.currentMax) or 5
    if maxP < 1 then maxP = 5 end
    if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end

    CP_EnsureBars(playerFrame, maxP)
    CP_Layout(playerFrame, maxP, cpHeight, CP.powerType)
    CP._pf = playerFrame
    CP._layoutH = cpHeight

    if CP.container then
        CP.container._msufAnchorOnly = true
        CP.container:Hide()
    end
    return true
end

--- Full refresh (called on spec change, form change, config change)
local CP_RefreshEventBindings
local CP_SetStructuralEventsBound = CP_Noop
local function FullRefresh()
    if not MSUF_DB then return end
    _CP_RefreshConfig()  --- P0: rebuild cached config
    local b = _cpDB.bars or {}
    --- A module disable requested during combat keeps the complete, still-valid
    --- Aug surface alive until regen. Settings/public refreshes must not tear a
    --- piece of it down while that lifecycle transition is pending.
    if CP.augLifecycleDisablePending == true then
        CP.augLifecycleRetryPending = true
        if CP_RefreshEventBindings then CP_RefreshEventBindings() end
        return
    end
    local playerFrame = GetPlayerFrame()
    if not playerFrame then return end
    CPAuras.Rebuild()

    --- Edit mode: keep class power visible as live preview so bars-menu
    --- adjustments (width, height, offsets) are visible immediately.
    --- Alt-mana remains a live Menu2/runtime surface, not an Edit Mode mover.
    local inEditMode = (_G.MSUF_UnitEditModeActive == true)

    --- --- ClassPower ---
    local cpEnabled = (b.showClassPower ~= false)
    local amEnabled = (b.showAltMana == true)
    local powerType, renderMode, isAuraPower
    if cpEnabled then
        powerType, renderMode, isAuraPower = GetClassPowerType()
    else
        renderMode = CPK.MODE.NONE
        isAuraPower = false
    end
    if powerType == "IRONFUR" and not CP.ironfur then
        CP.ironfur = CP.BuildIronfur and CP.BuildIronfur() or nil
        if CP.ironfur then CP.BuildIronfur = nil end
        MODE_UPDATE_FN[CPK.MODE.IRONFUR] = CP.ironfur and CP.ironfur.Update or nil
    end
    if CP.ironfur and CP.ironfur.SetActive and powerType ~= "IRONFUR" then
        CP.ironfur.SetActive(false)
    end
    local cpHeight = tonumber(b.classPowerHeight) or 4
    if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end

    --- Hook player frame resize only when ClassPower can use it. Once hooked,
    --- the callback exits without DB work while ClassPower is disabled.
    if cpEnabled and not playerFrame._msufCPSizeHooked then
        playerFrame._msufCPSizeHooked = true
        playerFrame:HookScript("OnSizeChanged", function()
            if not CP_ConfigClassPowerEnabled() then return end
            if _G.MSUF_ClassPower_Apply then
                _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
            elseif _G.MSUF_ClassPower_Refresh then
                _G.MSUF_ClassPower_Refresh()
            end
        end)
    end

    --- Ele Shaman: main power bar ALWAYS shows Mana (Maelstrom is UnitPowerType default).
    --- showEleMaelstrom only controls whether the class resource bar displays Maelstrom.
    --- Flag is unconditional for Ele spec -> all hot paths (UnitframeCore, Text) override pType to Mana.
    local isEleShaman = (cpEnabled and PLAYER_CLASS == "SHAMAN" and GetSpec and GetSpec() == CPK.SPEC.SHAMAN_ELEMENTAL)
    local eleMaelChanged = ((isEleShaman or false) ~= (_G.MSUF_EleMaelstromActive == true))
    ExportPublic("MSUF_EleMaelstromActive", isEleShaman or false)
    --- Force player power bar refresh so it immediately switches Mana ↔ Maelstrom
    if eleMaelChanged then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    --- Augmentation uses a two-resource model: segmented Essence remains active
    --- while Ebon Might occupies a native companion row. The
    --- hidden Player Power bar carries their combined geometry; optional Mana
    --- remains available through AltMana.
    local wantsAugComposite = (cpEnabled and powerType == PT.Essence
        and PLAYER_CLASS == "EVOKER"
        and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
        and b.showEbonMight ~= false) or false
    local powerSpec = playerFrame.MSUFSpec and playerFrame.MSUFSpec.power or nil
    local ebonHeight = tonumber(powerSpec and powerSpec.height) or 3
    if ebonHeight < 1 then ebonHeight = 1 elseif ebonHeight > 30 then ebonHeight = 30 end
    local compositeGap = 2
    local compositeHeight = cpHeight + compositeGap + ebonHeight
    local wasAugComposite = CP.augCompositeActive == true
    local wasAugGlobal = _G.MSUF_AugEvokerActive == true
    local oldCompositeHeight = CP.augCompositeHeight
    local oldEssenceHeight = CP.augEssenceHeight
    local oldEbonHeight = CP.augEbonHeight
    local oldCompositeGap = CP.augCompositeGap

    --- Power.Apply and CP_Layout both defer/freeze geometry in lockdown. Keep
    --- entry and exit atomic by retaining the old complete surface until one
    --- PLAYER_REGEN_ENABLED refresh can perform both sides of the hand-off.
    local augTransition = wasAugComposite ~= wantsAugComposite
    if augTransition and InCombatLockdown and InCombatLockdown() then
        CP.augLifecycleRetryPending = true
        CP.augLifecycleTarget = wantsAugComposite
        if CP_RefreshEventBindings then CP_RefreshEventBindings() end
        return
    end
    if CP.augLifecycleRetryPending == true then
        --- A second structural change can return to the already-published side
        --- before regen (vehicle enter -> exit, or spec/settings reversal).
        --- Cancel the pending hand-off without rebuilding that stable surface.
        if CP.augLifecycleTarget ~= nil
            and CP.augLifecycleTarget ~= wantsAugComposite
            and wasAugComposite == wantsAugComposite
        then
            CP.augLifecycleRetryPending = false
            CP.augLifecycleTarget = nil
            if CP_RefreshEventBindings then CP_RefreshEventBindings() end
            return
        end
        CP.augLifecycleRetryPending = false
        CP.augLifecycleTarget = nil
    end

    --- Resolve the native Ebon owner before replacing the ordinary Player
    --- Power surface. If Blizzard_AuraContainer cannot load (notably when the
    --- UI starts in combat), Essence and normal Power keep their usual layout
    --- while the existing event driver waits for one PLAYER_REGEN retry.
    if wantsAugComposite or not wasAugComposite then
        CP.ebonSensorDesired = wantsAugComposite
    end
    local ebonReady = false
    if wantsAugComposite then
        CP.augCompositeActive = true
        CP.augCompositeHeight = compositeHeight
        CP.augEssenceHeight = cpHeight
        CP.augEbonHeight = ebonHeight
        CP.augCompositeGap = compositeGap
        CP_Create(playerFrame)
        if CP_EnsureMainText then CP_EnsureMainText() end
        CP_ApplyFont()
        CP_LayoutEbonHost()
        ebonReady = CP.SetEbonSensorActive(true) == true
    elseif not wasAugComposite then
        CP.SetEbonSensorActive(false)
    end
    local isAugComposite = wantsAugComposite and ebonReady
    local augChanged = isAugComposite ~= wasAugGlobal
    local augGeometryChanged = wasAugComposite ~= isAugComposite
        or (isAugComposite and (oldCompositeHeight ~= compositeHeight
            or oldEssenceHeight ~= cpHeight
            or oldEbonHeight ~= ebonHeight
            or oldCompositeGap ~= compositeGap))
    local refreshAugPowerAfterClassLayout = wasAugComposite and not isAugComposite
        and (augChanged or augGeometryChanged)
    if refreshAugPowerAfterClassLayout then
        --- CP_Core uses this internal bit to select its carrier anchor. Leave
        --- the public state, sensor, and geometry intact until normal CP_Layout
        --- has severed that anchor below.
        CP.augCompositeActive = false
    else
        CP.augCompositeActive = isAugComposite
        CP.augCompositeHeight = isAugComposite and compositeHeight or nil
        CP.augEssenceHeight = isAugComposite and cpHeight or nil
        CP.augEbonHeight = isAugComposite and ebonHeight or nil
        CP.augCompositeGap = isAugComposite and compositeGap or nil
        ExportPublic("MSUF_AugEvokerActive", isAugComposite)
    end
    if (augChanged or augGeometryChanged) and not refreshAugPowerAfterClassLayout then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    --- Shadow Priest: when showShadowMana is ON, main power bar shows Mana
    --- instead of Insanity. Insanity moves to CP class resource (CONTINUOUS).
    local isShadowMana = (cpEnabled and PLAYER_CLASS == "PRIEST" and GetSpec and GetSpec() == CPK.SPEC.PRIEST_SHADOW
        and b.showShadowMana == true)
    local shadowChanged = ((isShadowMana or false) ~= (_G.MSUF_ShadowManaActive == true))
    ExportPublic("MSUF_ShadowManaActive", isShadowMana or false)
    if shadowChanged then
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    if WW.SetActive then
        WW.SetActive(cpEnabled and powerType == "WHIRLWIND" and renderMode ~= CPK.MODE.NONE)
    end

    if cpEnabled and powerType and renderMode ~= CPK.MODE.NONE then
        CP_Create(playerFrame)

        --- Resolve max power based on render mode
        local maxP
        if renderMode == CPK.MODE.RUNE_CD then
            maxP = 6  --- DK always 6 runes
        elseif renderMode == CPK.MODE.AURA_SINGLE then
            --- DH Devourer mirrors Blizzard and Elemental: one continuous bar,
            --- normalized against the real Soul Fragment maximum at runtime.
            maxP = 1
        elseif renderMode == CPK.MODE.CONTINUOUS then
            maxP = 1  --- Ele Maelstrom: single continuous bar
        elseif renderMode == CPK.MODE.STAGGER then
            maxP = 1  --- Brewmaster Monk: single stagger bar (max = UnitHealthMax inside update fn)
        elseif renderMode == CPK.MODE.TIMER_BAR then
            maxP = 1  --- Ebon Might: one host for the native duration text
        elseif renderMode == CPK.MODE.IRONFUR then
            maxP = 1  --- Guardian Ironfur: normalized longest remaining lifetime
        elseif renderMode == CPK.MODE.AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                --- Maelstrom Weapon: max stacks from spell data
                maxP = 10  --- default
                local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.MAELSTROM_WEAPON)
                if NotSecret(spellMax) and spellMax ~= nil then
                    local resolvedMax = tonumber(spellMax)
                    if resolvedMax and resolvedMax > 0 then maxP = resolvedMax end
                end
            elseif powerType == "SOUL_FRAGMENTS_VENG" then
                maxP = 6  --- Vengeance: 6 soul fragment segments
            elseif powerType == "WHIRLWIND" then
                maxP = WW.MAX_STACKS  --- Warrior: 4 Whirlwind cleave stacks
            elseif powerType == "TIP_OF_THE_SPEAR" then
                maxP = TIP.MAX_STACKS  --- Survival Hunter: 3 Tip of the Spear stacks
                CP.spStacks = 0
                CP.spExpires = nil
            elseif powerType == "ICICLES" then
                maxP = CPConst.ICICLES and CPConst.ICICLES.MAX_STACKS or 5
            else
                maxP = 10
            end
        else
            --- Standard / Fractional: UnitPowerMax
            maxP = UnitPowerMax("player", powerType)
            if not NotSecret(maxP) or maxP == nil then
                --- Heuristic fallback (safe; most are 5-6)
                if powerType == PT.Runes then maxP = 6
                elseif powerType == PT.ComboPoints then maxP = 7
                else maxP = 5 end
            end
        end
        maxP = math_floor(maxP)
        if maxP < 1 then maxP = 1 end
        if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end

        CP_EnsureBars(playerFrame, maxP)
        CP._outlineEdge = -1  --- force outline rebuild on mode/size changes
        CP_Layout(playerFrame, maxP, cpHeight, powerType)
        --- Layout switches geometry and clipping, while presentation owns the
        --- actual media paths. Refresh immediately so CIRCLE/DIAMOND/HEX -> BAR
        --- cannot retain a pip fill/background texture until the next reload.
        if CP_RefreshTexture then CP_RefreshTexture() end
        --- Cache layout params for lightweight CDM relayout (avoids FullRefresh)
        CP._pf = playerFrame
        CP._layoutH = cpHeight
        CP.powerType = powerType
        CP.powerToken = POWER_TYPE_TOKENS[powerType] or (type(powerType) == "string" and powerType or nil)
        CP.renderMode = renderMode
        CP.isAuraPower = isAuraPower
        CP.isVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
        CP.updateFn = MODE_UPDATE_FN[renderMode]
        CP.modeProfile = CP_GetModeEventProfile(renderMode, powerType, isAuraPower)
        CP_CompileVisual(powerType, renderMode, maxP)

        --- Charged points only for standard segmented (CP/HP)
        if renderMode == CPK.MODE.SEGMENTED then
            RefreshChargedPoints()
        end

        --- Warlock: reset prediction state
        CP.wlPredDelta = 0

        --- Runtime OnUpdate policy: only the active mode may keep a tick path alive.
        if renderMode ~= CPK.MODE.RUNE_CD and CP_StopRuneOnUpdates then
            CP_StopRuneOnUpdates(true)
        end
        if (renderMode ~= CPK.MODE.SEGMENTED or powerType ~= PT.Essence) and CP_StopEssenceOnUpdates then
            CP_StopEssenceOnUpdates()
        end

        if (b.classPowerShowText == true or CP.augCompositeActive == true) and CP_EnsureMainText then
            CP_EnsureMainText()
        end
        CP_ApplyFont()

        --- Mark the bar active before the first update: CP_CheckAutoHide gates on
        --- CP.visible, so the refresh that turns Class Power on (login, spec swap,
        --- feature toggle) would otherwise skip its own auto-hide evaluation and
        --- leave the bar at the alpha 1 reset below until the next runtime event.
        CP.visible = true

        --- Reset container alpha before update (auto-hide in updateFn may override)
        CP.container:SetAlpha(1)

        if CP.ironfur and CP.ironfur.SetActive then
            CP.ironfur.SetActive(powerType == "IRONFUR")
        end

        --- Dispatch to correct update function
        CP_RunActiveUpdate(powerType, maxP)

        CP.container._msufAnchorOnly = nil
        CP.container:Show()
        if CP.augCompositeActive == true then
            CP_LayoutEbonHost()
            CP.SetEbonSensorActive(true)
        end
        --- The container is measurable only now, so a synced detached Power bar
        --- can finally match it.
        CP.RefreshSyncedPowerWidth(playerFrame)
        --- Belt-and-suspenders: ensure outline survives parent Hide/Show cycle
        if CP._outline then
            local outlineBars = _cpDB.bars or {}
            local outlineShape = tostring(outlineBars.classPowerShape or "BAR"):upper()
            local outlineSize = tonumber(outlineBars.classPowerOutline) or 1
            if outlineShape == "BAR" and outlineSize > 0 and CP._msufRoundedOutlineSuppressed ~= true then
                CP._outline:Show()
            else
                CP._outline:Hide()
            end
        end

    else
        --- Clean up resource runtime state when hiding.
        if not refreshAugPowerAfterClassLayout then
            CP.SetEbonSensorActive(false)
        end
        if CP.ironfur and CP.ironfur.SetActive then CP.ironfur.SetActive(false) end
        CP.visual = nil
        if (CP.renderMode == CPK.MODE.RUNE_CD or CP.runeOUAAny or CP.runeNativeAny) and CP_StopRuneOnUpdates then
            CP_StopRuneOnUpdates(true)
        end
        if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
        CP_StopCentralTick()
        local maintainedAnchor = CP_EnsureHiddenAnchorGeometry(playerFrame, cpHeight)
        if CP.container then
            if not maintainedAnchor then
                CP.container._msufAnchorOnly = nil
            end
            CP.container:Hide()
        end
        CP.visible = false
        --- No class bar left to match: return a synced detached Power bar to its
        --- own configured width instead of freezing at the last class width.
        CP.RefreshSyncedPowerWidth(playerFrame)
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
    end

    if refreshAugPowerAfterClassLayout then
        CP_ClearAugCompositeState()
        CP.SetEbonSensorActive(false)
        if _G.MSUF_RefreshPlayerPowerBar then
            _G.MSUF_RefreshPlayerPowerBar()
        end
    end

    --- --- AltMana ---
    local needsAlt = amEnabled and NeedsAltManaBar() or false

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

    if CP_PlayerHPNeedsRefresh() then
        CP_PlayerHPRefresh(playerFrame)
    end

    CP.structuralFlags, CP.structuralPowerType, CP.structuralRenderMode = CP_ComputeStructuralSignature()
    CP_RefreshEventBindings()
    CP_SetStructuralEventsBound(CP_ConfigAnyFeatureEnabled())
    if CP.SyncControllerEvents then CP.SyncControllerEvents(CP_ConfigAnyFeatureEnabled()) end
    if type(_G.MSUF_BAL_RefreshRuntime) == "function" then
        _G.MSUF_BAL_RefreshRuntime()
    end
end

--- Event-driven updates (hot path: minimal work)
--- Runtime handlers now come from the CP runtime feature builder below.

--- Phase 6 CP split: runtime/light-refresh handlers now live in
--- ClassPower/Features/MSUF_CP_Runtime.lua. The core keeps event-frame wiring,
--- while hot-path glue and structural light-refresh helpers live in a separate
--- feature builder to keep the orchestrator chunk thin.

local ThrottledFullRefresh
local CP_ShouldUseLiteBindings

--- Event frame (single frame handles all events)
local eventFrame = CreateFrame("Frame")
local _cpStructuralEventsBound = false

CP_SetStructuralEventsBound = function(active)
    active = active and true or false
    if _cpStructuralEventsBound == active then return end
    _cpStructuralEventsBound = active
    if active then
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        eventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    else
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        eventFrame:UnregisterEvent("UNIT_EXITED_VEHICLE")
        eventFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:UnregisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    end
end

--- Throttle for rare events (spec/form changes)
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
            CP_SyncRuntimeOnUpdates = CP_SyncRuntimeOnUpdates,
            CP_ShouldUseLiteBindings = function() return CP_ShouldUseLiteBindings() end,
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

--- Pre-allocated callback for deferred PBEmbedLayout re-layout after zone transitions.
--- Frame geometry may not have settled on the first FullRefresh; this second pass
--- clears the stamp cache so the detached power bar picks up final dimensions.
--- Defined once at file scope - zero closure allocations per PLAYER_ENTERING_WORLD.
local function _CP_DeferredPBRelayout()
    if not (CP.visible or AM.visible or PHP.visible or CP.CDMWidthWantsSync()) then return end
    local fr = CoreUnitFrame("player") or _G.MSUF_player
    if fr and fr._msufStampCache then
        fr._msufStampCache["PBEmbedLayout"] = nil
    end
    if _G.MSUF_ClassPower_Apply then
        _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
    else
        FullRefresh()
    end
end

--- Dynamic hot-path event binding (CP-1): only keep runtime events that the
--- currently active class-power / alt-mana mode actually needs. Structural and
--- hot events are both detached when the complete Class Resources feature is off.
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

local function CP_CDMWidthResolveFrame(frameName)
    if type(frameName) ~= "string" or frameName == "" then return nil end
    local resolver = _G.MSUF_GetEffectiveCooldownFrame
    local frame = type(resolver) == "function" and resolver(frameName) or nil
    return frame or _G[frameName]
end

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
    -- The Detached width mode drives the bar with or without width sync, so this
    -- watcher must not be gated on sync: doing so watched the one case where the
    -- source is a fallback and went blind in the case where it owns the width.
    if not player or player.powerBarDetached ~= true then return nil end
    if readEnabled and readEnabled("player", db) == false then return nil end
    return cdmName
end

function CP.CDMWidthGetConfiguredNames()
    local b = _cpDB.bars or {}
    local cpName = (CP.visible and CPConst.CDM_FRAMES and CPConst.CDM_FRAMES[b.classPowerWidthMode or ""]) or nil
    local pbName = CP.CDMWidthGetDetachedPowerBarName()
    return cpName, pbName
end

function CP.CDMWidthHasConfiguredSync()
    local cpName, pbName = CP.CDMWidthGetConfiguredNames()
    return cpName ~= nil or pbName ~= nil
end

function CP.CDMWidthFrameUsable(frameName)
    local cdm = CP_CDMWidthResolveFrame(frameName)
    if not (cdm and cdm.GetWidth) or cdm._msufLegacyCooldownAnchor == true then return false end
    if cdm.IsShown and not cdm:IsShown() then return false end
    local w = cdm:GetWidth()
    return type(w) == "number" and w >= 1
end

function CP.CDMWidthGetNames()
    local cpName, pbName = CP.CDMWidthGetConfiguredNames()
    if cpName and not CP.CDMWidthFrameUsable(cpName) then cpName = nil end
    if pbName and not CP.CDMWidthFrameUsable(pbName) then pbName = nil end
    return cpName, pbName
end

function CP.CDMWidthWantsSync()
    local cpName, pbName = CP.CDMWidthGetNames()
    return cpName ~= nil or pbName ~= nil
end

function CP.CDMWidthReadSig(frameName)
    local cdm = CP_CDMWidthResolveFrame(frameName)
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
        CP_Layout(CP._pf, CP.currentMax, CP._layoutH or (b.classPowerHeight or 4), CP.powerType)
        if CP.ironfur and CP.ironfur.InvalidateLayout then
            CP.ironfur.InvalidateLayout()
        end
    end
    if pbChanged and type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
end

function CP.CDMWidthSetEvents()
    CP_SetEventBound(eventFrame, "SPELL_UPDATE_COOLDOWN", false)
    CP_SetEventBound(eventFrame, "ACTIONBAR_UPDATE_COOLDOWN", false)
    CP_SetEventBound(eventFrame, "BAG_UPDATE_COOLDOWN", false)
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

local function CP_ShouldUseFrequentPowerEvents()
    if AM.visible then return true end
    if not CP.visible then return false end
    local mode = CP.renderMode
    return mode == CPK.MODE.CONTINUOUS
        or mode == CPK.MODE.FRACTIONAL
        or (mode == CPK.MODE.SEGMENTED and CP.powerType == PT.Essence)
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

    if not CP.visible and not AM.visible and not PHP.visible then
        local wantAugLifecycleRegen = CP.augLifecycleRetryPending == true
            or CP.augLifecycleDisablePending == true
            or CP.ebonSensorRetryPending == true
            or CP.ebonTextLayerRetryPending == true
        CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_AURA", false, "player")
        CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", false)
        CP_SetEventBound(eventFrame, "UNIT_HEALTH", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", false, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", false, "player")
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", wantAugLifecycleRegen)
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", false)
        CP_SetEventBound(eventFrame, "PLAYER_DEAD", false)
        CP_SetEventBound(eventFrame, "PLAYER_ALIVE", false)
        CP.CDMWidthSetEvents()
        return
    end

    if not useLite then
        CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_AURA", true, "player")
        CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", true)
        CP_SetEventBound(eventFrame, "UNIT_HEALTH", true, "player")
        local wantMaxHealth = PHP.visible or (CP.visible and CP.renderMode == CPK.MODE.STAGGER)
        CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", wantMaxHealth, "player")
        CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", wantMaxHealth, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", true, "player")
        CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", true, "player")
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", true)
        CP_SetEventBound(eventFrame, "PLAYER_DEAD", true)
        CP_SetEventBound(eventFrame, "PLAYER_ALIVE", true)
        CP.CDMWidthSetEvents()
        return
    end

    local profile = CP.modeProfile or CP_GetModeEventProfile(CP.renderMode, CP.powerType, CP.isAuraPower)
    local wantPower = CP_ShouldUseValuePowerEvents()
    local wantMaxPower = CP_ShouldUseMaxPowerEvent()
    local wantAura = CP.visible and profile.aura == true
    local wantRune = CP.visible and profile.rune == true
    local wantHealth = (CP.visible and profile.health == true) or PHP.visible
    local wantMaxHealth = (CP.visible and profile.health == true) or PHP.visible
    local wantPointCharge = CP.visible and profile.pointCharge == true
    local wantWarlockPred = CP.visible and profile.warlockPred == true
    local wantSpellSucceeded = CP.visible and profile.spellSucceeded == true
    local wantDisplayPower = CP.visible or AM.visible
    local wantRegen = (_autoHideActive and CP.visible)
        or CP.ebonSensorRetryPending == true
        or CP.ebonTextLayerRetryPending == true
        or CP.augLifecycleRetryPending == true
        or CP.augLifecycleDisablePending == true
    local wantDeadAlive = (CP.visible and profile.deadAlive == true) or PHP.visible

    local wantFrequentPower = wantPower and CP_ShouldUseFrequentPowerEvents()
    CP_SetEventBound(eventFrame, "UNIT_POWER_UPDATE", wantPower and not wantFrequentPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_FREQUENT", wantFrequentPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAXPOWER", wantMaxPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_DISPLAYPOWER", wantDisplayPower, "player")
    CP_SetEventBound(eventFrame, "UNIT_POWER_POINT_CHARGE", wantPointCharge, "player")
    CP_SetEventBound(eventFrame, "UNIT_AURA", wantAura, "player")
    CP_SetEventBound(eventFrame, "RUNE_POWER_UPDATE", wantRune)
    CP_SetEventBound(eventFrame, "UNIT_HEALTH", wantHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAXHEALTH", wantMaxHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", wantMaxHealth, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_START", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_STOP", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_FAILED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", wantWarlockPred, "player")
    CP_SetEventBound(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", wantSpellSucceeded, "player")
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_ENABLED", wantRegen)
    CP_SetEventBound(eventFrame, "PLAYER_REGEN_DISABLED", wantRegen)
    CP_SetEventBound(eventFrame, "PLAYER_DEAD", wantDeadAlive)
    CP_SetEventBound(eventFrame, "PLAYER_ALIVE", wantDeadAlive)
    CP.CDMWidthSetEvents()
end

local _cpAuraDeferred = false
local function CP_RunDeferredAuraUpdate()
    _cpAuraDeferred = false
    local profile = CP.modeProfile or CP_GetModeEventProfile(CP.renderMode, CP.powerType, CP.isAuraPower)
    if CP._liteBindingsActive == false or (CP.visible and profile and profile.aura == true) then
        OnAuraUpdate("player")
    end
end

local function CP_DeferAuraUpdate()
    if _cpAuraDeferred then return end
    _cpAuraDeferred = true
    local scheduleOnce = _G.MSUF_ScheduleOnce
    if type(scheduleOnce) == "function" then
        scheduleOnce("MSUF_CP_AURA_UPDATE", CP_RunDeferredAuraUpdate)
    else
        C_Timer.After(0, CP_RunDeferredAuraUpdate)
    end
end

local function ClassPowerOnEvent(_, event, arg1, arg2, arg3)
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
            --- Stagger uses UNIT_AURA only as a lightweight change signal and
            --- never reads aura payloads. Avoid rebuilding the aura cache for it.
            local resourceChanged = false
            if CP.isAuraPower then
                resourceChanged = CPAuras.ProcessUnitAuraUpdate(arg2, CP.powerType, CP.renderMode)
            end
            if resourceChanged or CP.renderMode == CPK.MODE.STAGGER then
                CP_DeferAuraUpdate()
            end
        end
        return
    end

    if event == "RUNE_POWER_UPDATE" then
        --- arg1 = runeID (1-6), arg2 = energize boolean
        OnRuneUpdate(arg1, arg2)
        return
    end

    --- Spellcast: Warlock shard prediction + Balance Druid AP prediction
    --- arg1 = unitTarget, arg2 = castGUID, arg3 = spellID
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
            --- Balance/Warlock: clear prediction on successful cast
            OnSpellcastEnd()
            --- Tip of the Spear: spell-tracked via main handler
            if CP.visible and CP.powerType == "TIP_OF_THE_SPEAR" then
                OnTipOfTheSpearSpellCast(arg3)
            end
            --- Whirlwind: handled by WW module's own event frame (no call needed here)
            --- DH Vengeance: soul fragment count changes on spellcast
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
            --- Only relevant for standard segmented mode (CP/HP)
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

    --- Stagger: health changes affect threshold colors + bar max
    if event == "UNIT_HEALTH" then
        if arg1 == "player" then
            if PHP.visible then
                CP_PlayerHPUpdate(event)
            end
            --- CP stagger: max health = bar max, threshold recalculation
            if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
                CP_RunActiveUpdate(CP.powerType, CP.currentMax)
            end
        end
        return
    end

    if event == "UNIT_MAXHEALTH" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        if arg1 == "player" then
            if PHP.visible then
                CP_PlayerHPUpdate(event)
            end
            if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
                CP_RunActiveUpdate(CP.powerType, CP.currentMax)
            end
        end
        return
    end

    --- Vehicle enter/exit: rebuild everything (CP type may change)
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then
            C_Timer.After(0.1, FullRefresh)
        end
        return
    end

    --- Combat state change: re-evaluate auto-hide (OOC toggle)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "PLAYER_REGEN_ENABLED" then
            if CP.augLifecycleDisablePending == true and CP.DisableNow then
                CP.DisableNow()
                return
            end
            if CP.augLifecycleRetryPending == true
                or CP.ebonSensorRetryPending == true
                or CP.ebonTextLayerRetryPending == true
            then
                CP.augLifecycleRetryPending = false
                CP.augLifecycleTarget = nil
                FullRefresh()
                return
            end
        end
        CP_RefreshEventBindings()
        if event == "PLAYER_REGEN_ENABLED" then
            CP.CDMWidthSyncLayouts(true)
        end
        if _autoHideActive and CP.visible and CP.container then
            --- Re-run the current mode's update to trigger CP_CheckAutoHide
            CP_RunActiveUpdate(CP.powerType, CP.currentMax)
        end
        return
    end

    --- Death/resurrection: reset spell tracker state (Sensei pattern)
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        OnSpellTrackerReset()
        if PHP.visible then
            CP_PlayerHPUpdate(event)
        end
        if CP.visible then
            CP_UpdateValues_AuraSegmented(CP.powerType, CP.currentMax)
        end
        return
    end

    --- Rare: only rebuild on actual structural changes; otherwise do a light re-sync.
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
        --- Retry until the Core player frame is available after login load.
        local retries = 0
        local function TryRefresh()
            retries = retries + 1
            local pf = CoreUnitFrame("player") or _G.MSUF_player
            if pf then
                FullRefresh()
                --- Deferred re-layout: frame dimensions and CDM frames may not
                --- have settled on the first FullRefresh. Schedule a second pass
                --- that clears the PBEmbedLayout stamp so the detached power bar
                --- re-computes its width from the now-correct frame geometry.
                --- Uses pre-allocated _CP_DeferredPBRelayout (zero closures).
                if CP.visible or AM.visible or PHP.visible or CP.CDMWidthWantsSync() then
                    C_Timer.After(0.35, _CP_DeferredPBRelayout)
                end
            elseif retries < 20 then
                --- Not ready yet - retry quickly (total max about 1s)
                C_Timer.After(0.05, TryRefresh)
            end
        end
        C_Timer.After(0.05, TryRefresh)
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureDefaults()
        return
    end

    if event == "ADDON_LOADED" then
        if arg1 ~= "Blizzard_CooldownViewer" and arg1 ~= "Blizzard_EditMode" then return end
        if CP.CDMWidthHasConfiguredSync and CP.CDMWidthHasConfiguredSync() then
            if type(CP.RefreshCDMWidthBindings) == "function" then
                CP.RefreshCDMWidthBindings(false)
            else
                _CP_RefreshConfig()
                if CP_RefreshEventBindings then CP_RefreshEventBindings() end
            end
        end
        return
    end
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    return ClassPowerOnEvent(self, event, arg1, arg2, arg3)
end)

CP.SyncControllerEvents = function(active)
    active = active == true
    if not active then
        eventFrame:UnregisterAllEvents()
        _cpStructuralEventsBound = false
        for event in pairs(_cpBoundEvents) do
            _cpBoundEvents[event] = nil
            _cpBoundUnits[event] = nil
        end
        return false
    end
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ADDON_LOADED")
    return true
end

--- Startup events exist only while at least one Class Resource feature is enabled.
CP.SyncControllerEvents(CP_ConfigAnyFeatureEnabled())

--- Public API (for Options, Edit Mode, and other modules)

CP.IsRuntimeActive = function()
    return CP.visible == true
        or AM.visible == true
        or PHP.visible == true
        or _cpTickActive == true
        or _cpStructuralEventsBound == true
end
ExportPublic("MSUF_ClassPower_IsRuntimeActive", CP.IsRuntimeActive)

--- Force full refresh (call after changing DB values)
CP.RefreshPublic = function()
    CP_InvalidateColorCaches()
    FullRefresh()
end
ExportPublic("MSUF_ClassPower_Refresh", CP.RefreshPublic)

CP.RefreshCDMWidthBindings = function(syncNow)
    _CP_RefreshConfig()
    if CP_PlayerHPNeedsRefresh() then
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
    CP_RefreshEventBindings()
    if syncNow == true and (CP.visible or AM.visible or CP.CDMWidthWantsSync()) then
        CP.CDMWidthSyncLayouts(true)
    end
end
ExportPublic("MSUF_ClassPower_RefreshCDMWidthBindings", CP.RefreshCDMWidthBindings)

CP.PlayerHPRefreshPublic = function()
    _CP_RefreshConfig()
    CP_PlayerHPRefresh(GetPlayerFrame())
    CP_RefreshEventBindings()
    CP_SetStructuralEventsBound(CP_ConfigAnyFeatureEnabled())
end
ExportPublic("MSUF_ClassPower_PlayerHP_Refresh", CP.PlayerHPRefreshPublic)

CP.PlayerHPRefreshTextures = function()
    _CP_RefreshConfig()
    if PHP.visible then
        PHP._textureStamp = nil
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
end
ExportPublic("MSUF_ClassPower_PlayerHP_RefreshTextures", CP.PlayerHPRefreshTextures)

--- Refresh bar textures (call after texture change in settings)
CP.RefreshTexturesPublic = function()
    _CP_RefreshConfig()
    if CP.visible then CP_RefreshTexture() end
    if AM.visible then AM_RefreshTexture() end
    if PHP.visible then
        PHP._textureStamp = nil
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
end
ExportPublic("MSUF_ClassPower_RefreshTextures", CP.RefreshTexturesPublic)

CP.RefreshLayoutCurrent = function()
    if not (CP.visible and CP_Layout) then
        return false
    end
    local playerFrame = GetPlayerFrame()
    if not playerFrame then
        return false
    end
    local b = _cpDB.bars or {}
    local cpHeight = tonumber(b.classPowerHeight) or 4
    if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end
    local maxP = tonumber(CP.currentMax) or 0
    if maxP <= 0 then
        return false
    end
    CP_Layout(playerFrame, maxP, cpHeight, CP.powerType)
    if CP.ironfur and CP.ironfur.InvalidateLayout then
        CP.ironfur.InvalidateLayout()
    end
    CP._pf = playerFrame
    CP._layoutH = cpHeight
    return true
end

ExportPublic("MSUF_ClassPower_RefreshLayout", function()
    _CP_RefreshConfig()
    return CP.RefreshLayoutCurrent()
end)

-- Source-size callbacks already run against the live profile table. Avoid the
-- generic ClassPower apply/config/event path and redistribute only the visible
-- resource layout whose configured cooldown source actually changed.
ExportPublic("MSUF_ClassPower_RefreshExternalWidth", function(sourceName)
    local b = _cpDB and _cpDB.bars
    local sources = CPConst and CPConst.CDM_FRAMES
    if not (b and sources and sources[b.classPowerWidthMode or ""] == sourceName) then
        return false
    end
    local refreshed = CP.RefreshLayoutCurrent()
    if refreshed and PHP.visible and tostring(b.playerHPBarWidthMode or "class"):lower() == "class" then
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
    return refreshed
end)

--- Refresh class power text font (called from UpdateAllFonts)
CP.ApplyFontsPublic = function()
    _CP_RefreshConfig()
    if CP.visible then
        _cpFontRev = 0  --- force re-apply
        CP_ApplyFont()
        CP.SetEbonSensorActive(CP.augCompositeActive == true)
        CP.ApplyEbonTextStyle()
    end
    if PHP.visible then
        PHP._fontStamp = nil
        CP_PlayerHPApplyFont()
    end
end
ExportPublic("MSUF_ClassPower_ApplyFonts", CP.ApplyFontsPublic)

CP.RefreshVisualsPublic = function()
    _CP_RefreshConfig()
    CP_InvalidateColorCaches()
    if CP.visible then
        CP_CompileVisual(CP.powerType, CP.renderMode, CP.currentMax)
        if CP_RefreshTexture then CP_RefreshTexture() end
        if CP_ApplyFont then CP_ApplyFont() end
        if CP_ApplyColors then CP_ApplyColors(CP.powerType) end
        CP.ApplyEbonTextStyle()
        if CP.powerType == "IRONFUR" and CP.ironfur and CP.ironfur.RefreshVisual then
            CP.ironfur.RefreshVisual()
        end
    end
    if AM.visible and AM_RefreshTexture then AM_RefreshTexture() end
    if PHP.visible then
        PHP._textureStamp = nil
        PHP._fontStamp = nil
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
end
ExportPublic("MSUF_ClassPower_RefreshVisuals", CP.RefreshVisualsPublic)

CP.ApplyRoundedSurfacePublic = function(masterEnabled)
    local rounded = MSUF and MSUF.RoundedSurface
    local applyAltMana = rounded and rounded.ApplyAltMana
    if type(applyAltMana) == "function" then applyAltMana(AM, masterEnabled) end
    local applyClassPower = rounded and rounded.ApplyClassPower
    if type(applyClassPower) ~= "function" then return false end
    return applyClassPower(CP, masterEnabled)
end
ExportPublic("MSUF_ClassPower_ApplyRoundedSurface", CP.ApplyRoundedSurfacePublic)

CP.ApplyPublic = function(opts)
    if type(opts) ~= "table" then
        CP.RefreshPublic()
        return true
    end

    local did = false
    if opts.full == true or opts.structure == true or opts.layout == true then
        CP.RefreshPublic()
        did = true
    else
        local visuals = opts.visuals == true or opts.colors == true or opts.textures == true
        if visuals then
            if opts.colors == true and _G.MSUF_BAL_InvalidateColors then
                _G.MSUF_BAL_InvalidateColors()
            end
            CP.RefreshVisualsPublic()
            did = true
        end
        if (opts.fonts == true or opts.text == true) and not visuals then
            CP.ApplyFontsPublic()
            did = true
        end
        if opts.anchor == true or opts.reanchor == true or opts.geometry == true then
            if _G.MSUF_ClassPower_RefreshLayout and _G.MSUF_ClassPower_RefreshLayout() then
                did = true
            end
        end
    end

    if opts.playerHPTextures == true then
        CP.PlayerHPRefreshTextures()
        did = true
    elseif opts.playerHP == true then
        CP.PlayerHPRefreshPublic()
        did = true
    end

    if opts.cdm == true or opts.width == true then
        CP.RefreshCDMWidthBindings(opts.syncNow ~= false)
        did = true
    elseif opts.events == true then
        _CP_RefreshConfig()
        CP_RefreshEventBindings()
        CP_SetStructuralEventsBound(CP_ConfigAnyFeatureEnabled())
        did = true
    end

    if not did then
        _CP_RefreshConfig()
    end
    return true
end
ExportPublic("MSUF_ClassPower_Apply", CP.ApplyPublic)

if type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
    _G.MSUF_RegisterAnyEditModeListener(function(active)
        if not (CP.visible and CP.container) then return end
        if active == true then
            CP.container:SetAlpha(1)
        else
            CP_RunActiveUpdate(CP.powerType, CP.currentMax)
        end
    end)
end

do
    if MSUF and MSUF.UF and type(MSUF.UF.RegisterVisualRefreshCallback) == "function" then
        MSUF.UF.RegisterVisualRefreshCallback("ClassPower", function(unit)
            if unit == "player" then
                CP.ApplyPublic({ visuals = true, playerHP = true })
            end
        end)
    end
end

--- Compatibility: hook bar texture change for live refresh.
--- Options panels should prefer MSUF_ClassPower_Apply(opts) after DB changes.
do
    --- Deferred hook: MSUF_TryApplyBarTextureLive is created in Options (LoadOnDemand).
    --- We post-hook it on first FullRefresh when it exists.
    CP._texHooked = false
    CP._origFullRefresh = FullRefresh
    FullRefresh = function()
        if not CP._texHooked then
            local origTex = _G.MSUF_TryApplyBarTextureLive
            if type(origTex) == "function" then
                ExportPublic("MSUF_TryApplyBarTextureLive", function(...)
                    origTex(...)
                    if CP.visible then CP_RefreshTexture() end
                    if AM.visible then AM_RefreshTexture() end
                    if PHP.visible then
                        PHP._textureStamp = nil
                        CP_PlayerHPRefresh(GetPlayerFrame())
                    end
                end)
                CP._texHooked = true
            end
        end
        CP._origFullRefresh()
    end
end

--- Smooth Player Power compatibility entry point.
--- UFCore owns the actual StatusBar interpolation. Class Resources only owns
--- the detached Player bar's layout and exposes the same per-player setting.
CP.SmoothPowerBarApply = function()
    --- Refresh the cached flags in UFCore's DIRECT_APPLY hot path.
    if _G.MSUF_UFCore_RefreshSettingsCache then
        _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER")
    end
end
ExportPublic("MSUF_SmoothPowerBar_Apply", CP.SmoothPowerBarApply)

--- Complete the ClassPower module teardown. Active Aug is never routed here in
--- combat: Disable() retains the old composite and the event driver calls this
--- once on PLAYER_REGEN_ENABLED. The normal CP anchor must be restored before
--- the public replacement state disappears, otherwise detached Player Power
--- can resolve an anchor cycle when it comes back.
function CP.DisableNow()
    _CP_RefreshConfig()
    CP.augLifecycleRetryPending = false
    CP.augLifecycleDisablePending = false
    CP.augLifecycleTarget = nil

    local augWasActive = CP.augCompositeActive == true or _G.MSUF_AugEvokerActive == true
    if augWasActive and CP.augCompositeActive == true
        and not (InCombatLockdown and InCombatLockdown())
    then
        local playerFrame = GetPlayerFrame()
        if playerFrame and CP.container and CP_Layout then
            local maxP = tonumber(CP.currentMax) or 5
            if maxP < 1 then maxP = 1 end
            if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end
            CP.augCompositeActive = false
            CP_Layout(playerFrame, maxP, tonumber(CP._layoutH) or 4, CP.powerType or PT.Essence)
        end
    end

    CP_RefreshEventBindings()
    CP_SetStructuralEventsBound(false)
    CP.SyncControllerEvents(false)
    CP_ClearAugCompositeState()
    CP.SetEbonSensorActive(false)
    if CP.container then CP.container:Hide() end
    if AM.container then AM.container:Hide() end
    if PHP.container then PHP.container:Hide() end
    CP.visible, AM.visible, PHP.visible = false, false, false
    if augWasActive and _G.MSUF_RefreshPlayerPowerBar then
        _G.MSUF_RefreshPlayerPowerBar()
    end
end

--- Phase 4: Module Registration
do
    if type(_G.MSUF_RegisterModule) == "function" then
        _G.MSUF_RegisterModule("ClassPower", {
            order = 30,
            IsEnabled = function()
                if not MSUF_DB then return true end
                local b = MSUF_DB.bars
                return not b
                    or b.showClassPower ~= false
                    or b.showAltMana == true
                    or b.playerHPBarEnabled == true
            end,
            Init = function()
                EnsureDefaults()
            end,
            Enable = function()
                --- Re-enable before regen cancels a deferred module teardown.
                --- FullRefresh below either keeps the still-correct composite or
                --- arms the ordinary transition retry for the new live state.
                CP.augLifecycleDisablePending = false
                CP.augLifecycleRetryPending = false
                CP.augLifecycleTarget = nil
                CP.SyncControllerEvents(true)
                _CP_RefreshConfig()
                FullRefresh()
            end,
            Disable = function()
                if CP.augCompositeActive == true
                    and InCombatLockdown and InCombatLockdown()
                then
                    CP.augLifecycleDisablePending = true
                    CP.augLifecycleRetryPending = true
                    CP.augLifecycleTarget = false
                    CP_RefreshEventBindings()
                    return
                end
                CP.DisableNow()
            end,
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

--- Balance Druid prediction/runtime moved to ClassPower\\MSUF_CP_BalanceDruid.lua.
