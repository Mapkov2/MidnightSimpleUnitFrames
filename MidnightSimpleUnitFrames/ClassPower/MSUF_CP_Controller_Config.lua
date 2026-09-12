--- ClassPower/MSUF_CP_Controller_Config.lua - controller configuration helpers
--- Cold-path configuration bundle for the ClassPower controller.
---
--- The controller owns events and live state; this file contributes the cached
--- DB config, the SavedVariables defaults, the feature gates, the class/spec
--- -> render-mode routing, the structural signature, the per-mode event profile
--- and the texture/height resolvers. Everything here runs at FullRefresh or
--- option-change cadence, never per event: the controller keeps _cpDB as an
--- upvalue for its hot paths and reads the rest through the returned table.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

--- Perf locals (same load-time captures the controller used before the split)
local type, tonumber, tostring = type, tonumber, tostring
local UnitPowerType = UnitPowerType
local UnitHasVehicleUI = UnitHasVehicleUI
local PlayerVehicleHasComboPoints = PlayerVehicleHasComboPoints
local GetShapeshiftFormID = GetShapeshiftFormID
local C_SpellBook = C_SpellBook
local CP_MODE_EVENT_PROFILE = _G.MSUF_CP_MODE_EVENT_PROFILE or {}

--- CONTROLLER_CONFIG is built once at controller load. E carries the values the
--- controller resolves itself (constants, player class, spec API, secret guard)
--- plus a getter for the AltMana builder binding, which the controller rebinds
--- after this builder has run.
builders.CONTROLLER_CONFIG = function(E)
    local CPConst = E.CPConst
    local CPK = E.CPK
    local PT = E.PT
    local TIP = E.TIP
    local PT_STAGGER = CPConst.PT_STAGGER or -1
    local PLAYER_CLASS = E.PLAYER_CLASS
    local GetSpec = E.GetSpec
    local NotSecret = E.NotSecret
    local NeedsAltManaBar = E.NeedsAltManaBar

    --- P0 PERF: Cached DB config (eliminates ~46 MSUF_DB traversals per event)
    --- Rebuilt once per FullRefresh (login, profile switch, option change).
    --- Hot-path functions read _cpDB.* instead of MSUF_DB.bars.*/general.*.
    --- Secret-safe: only reads DB booleans/numbers, no secret comparisons.
    local _cpDB = {
        colorByType    = true,   showCharged    = true,
        bgAlpha        = 0.3,    showPrediction = true,
        showText       = true,   textMode       = nil, fontSize = 14,
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
        local textMode = tostring(b.classPowerTextMode or ""):upper()
        -- nil is the compiled AUTO/legacy mode. Keeping AUTO out of the runtime
        -- cache lets every renderer take its original formatter path without an
        -- extra helper call; only explicit overrides enter the shared formatter.
        if textMode ~= "CURRENT" and textMode ~= "MAX" and textMode ~= "CURMAX" then textMode = nil end
        _cpDB.textMode          = textMode
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

    local function CP_ConfigPlayerHPBarEnabled()
        local b = _cpDB.bars
        if not b then
            local db = MSUF_DB
            b = db and db.bars
        end
        return b and b.playerHPBarEnabled == true or false
    end

    local function CP_ConfigPlayerManaOverrideEnabled(inVehicle)
        local db = MSUF_DB
        local player = db and db.player
        if not (player and player.playerPowerSource == "MANA") then
            return false
        end
        -- Keep the owner and UNIT_EXITED_VEHICLE lifecycle alive while vehicle
        -- power masks the player's own pools. The visible override still stays off.
        if inVehicle == nil then
            inVehicle = (_G.UnitHasVehicleUI and _G.UnitHasVehicleUI("player")) or false
        end
        if inVehicle then return true end
        -- Profiles can be shared across characters. Keep the ClassPower owner cold
        -- when the current class has no Mana pool, while retaining the preference
        -- for the next character that does. The API is absent on older clients.
        if not _G.UnitHasPowerType then return true end
        local manaType = (_G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.Mana) or 0
        local hasMana = _G.UnitHasPowerType("player", manaType)
        return NotSecret(hasMana) and hasMana == true or false
    end

    local function CP_ConfigAnyFeatureEnabled(playerManaEnabled)
        local db = MSUF_DB
        local b = db and db.bars
        return not b or b.showClassPower ~= false or b.showAltMana == true
            or b.playerHPBarEnabled == true or playerManaEnabled == true
            or (playerManaEnabled == nil and CP_ConfigPlayerManaOverrideEnabled())
    end

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

        --- DK Rune display order (static rune-id order, see CP_ApplyRuneSortOrder):
        --- "asc" = rune 1 first (natural), "desc" = rune 6 first, nil = natural
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
    local GetClassPowerType = E.GetClassPowerType or function()
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
            local spec = GetSpec and GetSpec()
            if spec == 2 then return "WHIRLWIND", CPK.MODE.NATIVE_AURA, false end
            if spec == 1 and _cpDB.bars and _cpDB.bars.showSweepingStrikes == true then
                return "SWEEPING_STRIKES", CPK.MODE.NATIVE_AURA, false
            end

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

    --- Per-mode event profile: which runtime events the active mode needs.
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
        profile.targetChanged = E.Client and E.Client.NeedsTargetChanged(powerType) == true or false
        return profile
    end

    --- Structural signature: cheap change detection for rare structural events.
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
        local wantAugComposite = _G.MSUF_PlayerPowerManaOverrideActive ~= true
            and cpEnabled and newPowerType == PT.Essence
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

    --- Configured texture key -> media path (shared by build/presentation/HP).
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

    --- Configured Class Resource bar height, clamped to the menu range. Shared by
    --- FullRefresh and the layout-only public refresh.
    local function CP_ResolveClassPowerHeight(b)
        local cpHeight = tonumber(b.classPowerHeight) or 4
        if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end
        return cpHeight
    end

    return {
        _cpDB = _cpDB,
        RefreshConfig = _CP_RefreshConfig,
        ClassPowerEnabled = CP_ConfigClassPowerEnabled,
        PlayerHPBarEnabled = CP_ConfigPlayerHPBarEnabled,
        PlayerManaOverrideEnabled = CP_ConfigPlayerManaOverrideEnabled,
        AnyFeatureEnabled = CP_ConfigAnyFeatureEnabled,
        EnsureDefaults = EnsureDefaults,
        GetClassPowerType = GetClassPowerType,
        GetModeEventProfile = CP_GetModeEventProfile,
        ComputeStructuralSignature = CP_ComputeStructuralSignature,
        ResolveTexture = CP_ResolveTexture,
        ResolveClassPowerHeight = CP_ResolveClassPowerHeight,
    }
end
