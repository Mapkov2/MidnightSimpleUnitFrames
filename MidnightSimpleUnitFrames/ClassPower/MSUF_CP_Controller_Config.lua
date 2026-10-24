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
local FILE = "ClassPower/MSUF_CP_Controller_Config.lua"

local CPConstants = MSUF.Require("MSUF_CP_CONST", FILE)
local builders = CPConstants.BuilderRegistry("MSUF_CP_CORE_BUILDERS")
local ResolveStatusbarTextureKey = MSUF.Optional("MSUF_ResolveStatusbarTextureKey")
local GetBarTexture = MSUF.Require("MSUF_GetBarTexture", FILE)

--- Perf locals (same load-time captures the controller used before the split)
local type, tonumber, tostring = type, tonumber, tostring
local UnitPowerType = UnitPowerType
local UnitHasVehicleUI = UnitHasVehicleUI
local PlayerVehicleHasComboPoints = PlayerVehicleHasComboPoints
local GetShapeshiftFormID = GetShapeshiftFormID
local C_SpellBook = C_SpellBook
local CP_MODE_EVENT_PROFILE = CPConstants.ModeDescriptors
local supportsCharged = MSUF.Client.SupportsClassResource("CHARGED")

--- Bound once by CONTROLLER_CONFIG at controller load: the constants, the
--- player class, the spec API, the secret guard and the AltMana binding getter.
local E, CPConst, CPK, PT, TIP, PT_STAGGER
local PLAYER_CLASS, GetSpec, NotSecret, NeedsAltManaBar

--- P0 PERF: Cached DB config (eliminates ~46 MSUF_DB traversals per event)
--- Rebuilt once per FullRefresh (login, profile switch, option change).
--- Hot-path functions read _cpDB.* instead of MSUF_DB.bars.*/general.*.
--- Secret-safe: only reads DB booleans/numbers, no secret comparisons.
--- A new table per build (NewConfigCache).
local _cpDB

local function NewConfigCache()
    return {
            colorByType    = true,   showCharged    = true,
            bgAlpha        = 0.3,    showPrediction = true,
            showText       = true,   textMode       = nil, fontSize = 14,
            classSmooth    = true,   altManaSmooth = true,
            colorOverrides = nil,
            bgColorOverrides = nil,  bars = nil, general = nil,
            comboPointColorMode = "default", slotColorModes = nil, fullColorEnabled = nil,
    }
end
local function CreateConfigCompiler(_cpDB)
return function()
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

end
MSUF.ClassPowerConfig = { CreateCompiler = CreateConfigCompiler }

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
        inVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
    end
    if inVehicle then return true end
    -- Profiles can be shared across characters. Keep the ClassPower owner cold
    -- when the current class has no Mana pool, while retaining the preference
    -- for the next character that does. The API is absent on older clients.
    local manaType = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
    if not UnitHasPowerType then
        -- No Classic branch of Blizzard's UI calls UnitHasPowerType, so ask
        -- the pool instead of assuming one: a class without Mana reports a
        -- maximum of 0. Those clients have no secret power values.
        local maxMana = UnitPowerMax and UnitPowerMax("player", manaType)
        if maxMana == nil or not NotSecret(maxMana) then return true end
        return maxMana > 0
    end
    local hasMana = UnitHasPowerType("player", manaType)
    return NotSecret(hasMana) and hasMana == true or false
end

local function CP_ConfigAnyFeatureEnabled(playerManaEnabled)
    local db = MSUF_DB
    local b = db and db.bars
    local extrasWanted = MSUF.CPBuilders and MSUF.CPBuilders.ResourceExtrasWanted
    return not b or b.showClassPower ~= false or b.showAltMana == true
        or (extrasWanted ~= nil and extrasWanted(b))
        or b.playerHPBarEnabled == true or playerManaEnabled == true
        or (playerManaEnabled == nil and CP_ConfigPlayerManaOverrideEnabled())
end

--- Class Resource defaults: a key is written only while it is still nil. The
--- rows are alternating key and default value, grouped like the menu pages.
local BAR_DEFAULTS = {
    --- ClassPower defaults
    "showClassPower", true,
    "classPowerHeight", 4,
    "classPowerShape", "BAR",
    "classPowerShapeAlign", "CENTER",
    "classPowerColorByType", true,
    "classPowerBgAlpha", 0.3,
    "classPowerTickWidth", 1,
    "classPowerOutline", 1,
    "classPowerWidth", 0,
    "classPowerWidthMode", "player",
    "classPowerOffsetX", 0,
    "classPowerOffsetY", 0,
    "classPowerFrameLevelOffset", 5,
    "classPowerTextLayer", 5,
    "smoothPowerBar", false,
    "showChargedComboPoints", true,
    "classPowerComboPointColorMode", "default",
    "classPowerShowText", false,
    "classPowerFontSize", 16,
    "classPowerShowPrediction", true,
    "classPowerTextOffsetX", 0,
    "classPowerTextOffsetY", 0,
    "detachedPowerBarOutline", 1,
    --- AltMana defaults
    "showAltMana", false,
    "altManaHeight", 4,
    "altManaWidth", 0,
    "altManaOffsetX", 0,
    "altManaOffsetY", -2,
    "altManaColorR", 0.0,
    "altManaColorG", 0.0,
    "altManaColorB", 0.8,
    --- Class Resources-owned second Player HP bar (off by default)
    "playerHPBarEnabled", false,
    "playerHPBarAnchor", "CLASS_TOP",
    "playerHPBarWidthMode", "class",
    "playerHPBarWidth", 0,
    "playerHPBarHeight", 6,
    "playerHPBarGap", 2,
    "playerHPBarOffsetX", 0,
    "playerHPBarOffsetY", 0,
    "playerHPBarFrameLevelOffset", 7,
    "playerHPBarShape", "BAR",
    "playerHPBarOrbSize", 54,
    "playerHPBarTexture", "",
    "playerHPBarBgTexture", "",
    "playerHPBarBgAlpha", 0.35,
    "playerHPBarOutline", 1,
    "playerHPBarColorMode", "GLOBAL",
    "playerHPBarSmoothFill", false,
    "playerHPBarTextEnabled", true,
    "playerHPBarUsePlayerText", true,
    "playerHPBarTextLeft", "NONE",
    "playerHPBarTextCenter", "NONE",
    "playerHPBarTextRight", "CURPERCENT",
    "playerHPBarTextSeparator", "",
    "playerHPBarTextReverse", false,
    "playerHPBarTextSize", 14,
    "playerHPBarTextOffsetX", 0,
    "playerHPBarTextOffsetY", 0,
    --- Stagger bar defaults (Brewmaster Monk)
    "showStagger", true,
    "staggerHeight", 4,
    "staggerOffsetY", -2,
    --- DK Rune display order (static rune-id order, see CP_ApplyRuneSortOrder):
    --- "asc" = rune 1 first (natural), "desc" = rune 6 first, nil = natural
    "runeSortOrder", "asc",
    --- Ele Shaman: Maelstrom Power continuous bar (off by default - niche preference)
    "showEleMaelstrom", false,
    --- Evoker Aug: native Ebon Might duration bar and text (on by default)
    "showEbonMight", true,
    --- Shadow Priest: show Mana as main bar, Insanity as class resource (off by default)
    "showShadowMana", false,
    --- Guardian Druid: estimated per-cast Ironfur lifetime bar (opt-in).
    "showGuardianIronfur", false,
    "guardianIronfurShowHashLines", true,
    --- Auto-hide: visibility conditions
    "classPowerHideOOC", false,
    "classPowerSyncPlayerPowerOOC", false,
    "classPowerHideWhenFull", false,
    "classPowerHideWhenEmpty", false,
    --- Pip alpha (0.0-1.0)
    "classPowerFilledAlpha", 1.0,
    "classPowerEmptyAlpha", 0.3,
    --- Gap between pips (pixels, 0 = no gap - only tick separators)
    "classPowerGap", 0,
    --- Fill direction: false = left->right (default), true = right->left
    "classPowerFillReverse", false,
}

--- DB Defaults (self-contained; runs on every login, no-ops if keys exist)
local function EnsureDefaults()
    if not MSUF_DB then return end
    if not MSUF_DB.bars then MSUF_DB.bars = {} end
    local b = MSUF_DB.bars
    for i = 1, #BAR_DEFAULTS, 2 do
        local key = BAR_DEFAULTS[i]
        if b[key] == nil then b[key] = BAR_DEFAULTS[i + 1] end
    end

    --- Fill smoothing follows the older shared smooth-power-bar setting
    if b.classPowerSmoothFill == nil then b.classPowerSmoothFill = (b.smoothPowerBar == true) end
    if b.altManaSmoothFill   == nil then b.altManaSmoothFill   = (b.smoothPowerBar == true) end
    --- Alt Mana is always player-width unless a custom width is chosen
    if b.altManaWidthMode ~= "custom" then b.altManaWidthMode = "player" end
    --- DK Runes: show per-rune cooldown time text on the runes (Sensei-style); the
    --- older runeShowTimeText key seeds the current one
    if b.runeShowTime == nil and b.runeShowTimeText ~= nil then b.runeShowTime = b.runeShowTimeText and true or false end
    if b.runeShowTime == nil then b.runeShowTime = true end
end

--- Power-type detection (resolved per spec/form change, cached)
--- Returns: powerType, renderMode, isAuraPower
--- powerType: Enum.PowerType or string token for aura-based
--- renderMode: MODE_* constant for hot-path dispatch
--- isAuraPower: true if driven by UNIT_AURA instead of UNIT_POWER_UPDATE

--- ClassPower: returns powerType, renderMode, isAuraPower. The Midnight
--- routing; a client provider (Forever, the Classic flavors) replaces it
--- through E.GetClassPowerType.
local GetClassPowerType
local function CreateClassPowerType(PLAYER_CLASS, GetSpec, UnitPowerType, C_SpellBook, _cpDB,
    UnitHasVehicleUI, GetShapeshiftFormID)
return function()
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
end
function MSUF.ClassPowerConfig.CreateSampleResolver(sample)
    return CreateClassPowerType(sample.class, sample.GetSpec, sample.PrimaryPower, sample.SpellBook,
        sample.config, nil, sample.GetForm)
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
        pointCharge = base.pointCharge == true and supportsCharged,
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
    local provider = E.Client
    profile.targetChanged = provider and provider.NeedsTargetChanged(powerType) == true or false
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
    local wantAugComposite = not MSUF.ClassPowerOwnership.playerManaOverride
        and cpEnabled and newPowerType == PT.Essence
        and PLAYER_CLASS == "EVOKER"
        and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
        and b.showEbonMight ~= false
    local wantCPVisible = cpEnabled and newPowerType and newRenderMode ~= CPK.MODE.NONE
    local wantAMVisible = (b.showAltMana == true) and NeedsAltManaBar() and (MSUF_UnitEditModeActive ~= true)
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
        local p = ResolveStatusbarTextureKey(key)
        if p then return p end
    end
    --- Fallback: global bar texture -> flat white
    return GetBarTexture() or "Interface\\Buttons\\WHITE8x8"
end

--- Configured Class Resource bar height, clamped to the menu range. Shared by
--- FullRefresh and the layout-only public refresh.
local function CP_ResolveClassPowerHeight(b)
    local cpHeight = tonumber(b.classPowerHeight) or 4
    if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end
    return cpHeight
end

MSUF.ClassPowerConfig.ResolveTexture = CP_ResolveTexture
MSUF.ClassPowerConfig.ResolveHeight = CP_ResolveClassPowerHeight

--- CONTROLLER_CONFIG is built once at controller load. E carries the values the
--- controller resolves itself (constants, player class, spec API, secret guard)
--- plus a getter for the AltMana builder binding, which the controller rebinds
--- after this builder has run.
builders.CONTROLLER_CONFIG = function(boundE)
    E = boundE
    CPConst, CPK, PT, TIP = E.CPConst, E.CPK, E.PT, E.TIP
    PT_STAGGER = CPConst.PT_STAGGER or -1
    PLAYER_CLASS, GetSpec, NotSecret = E.PLAYER_CLASS, E.GetSpec, E.NotSecret
    NeedsAltManaBar = E.NeedsAltManaBar
    _cpDB = NewConfigCache()
    GetClassPowerType = E.GetClassPowerType or CreateClassPowerType(PLAYER_CLASS, GetSpec, UnitPowerType,
        C_SpellBook, _cpDB, UnitHasVehicleUI, GetShapeshiftFormID)
    return {
        _cpDB = _cpDB,
        RefreshConfig = CreateConfigCompiler(_cpDB),
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

function MSUF.ClassPowerConfig.CreatePowerTextLevel(CP)
local math_floor = math.floor
return function()
    local host = CP.ebonHost
    local p = MSUF_DB and MSUF_DB.player or nil
    local textLayer = tonumber(p and p.powerTextLayer) or 2
    if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
    textLayer = math_floor(textLayer + 0.5)
    if host and host.GetFrameLevel then
        return (host:GetFrameLevel() or 0) + 1 + textLayer
    end
    local layers = MSUF.UF and MSUF.UF.Layers
    return layers and layers.TextLevel and layers.TextLevel(CP.container, textLayer, 5)
        or (layers and layers.ElementLevel and layers.ElementLevel(textLayer, 5, 8))
        or ((CP.container and CP.container.GetFrameLevel and CP.container:GetFrameLevel() or 0) + 10)
end
end
