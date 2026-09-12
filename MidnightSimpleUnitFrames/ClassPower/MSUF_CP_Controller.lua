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
local ExportPublic = MSUF.ExportPublic

--- The player-frame resolver is owned by ClassPower/MSUF_CP_Core.lua, which
--- the TOC loads before this file.
local CoreUnitFrame = _G.MSUF_CP_CoreUnitFrame

--- Perf locals (eliminate global lookups in hot paths)
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local GetUnitChargedPowerPoints = GetUnitChargedPowerPoints
local math_floor = math.floor
local math_min = math.min
local string_format = string.format
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
local GetRuneCooldown = GetRuneCooldown
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local C_Timer = C_Timer
local GetPowerRegenForPowerType = GetPowerRegenForPowerType
local SMOOTH_INTERP = _G.Enum and _G.Enum.StatusBarInterpolation
SMOOTH_INTERP = SMOOTH_INTERP and SMOOTH_INTERP.ExponentialEaseOut or nil

--- Aura API (player-only class resources; unitframe aura display is native 12.1)
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook

--- Secret-value guard (Midnight/12.1)
local _issecretvalue = _G.issecretvalue
local _canaccesstable = _G.canaccesstable
local NotSecret = MSUF.Secrets.NotSecret

local CanAccessTableValue = MSUF.Secrets.CanAccessTable

local CanAccessOptionalTableValue = MSUF.Secrets.CanAccessOptionalTable

--- Spec API (12.0: C_SpecializationInfo preferred, fallback to global)
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization

--- Player class (resolved once, never changes)
local PLAYER_CLASS = select(2, UnitClass("player"))

--- Phase 1 CP split: shared constants / profiles now live in ClassPower/*.lua
--- Keeps the core chunk smaller and reduces WoW's top-level local pressure.
local CPConst = _G.MSUF_CP_CONST or {}
local CPK = CPConst.CPK or { MODE = { NONE = 0, SEGMENTED = 1, FRACTIONAL = 2, RUNE_CD = 3, AURA_SEGMENTED = 4, AURA_SINGLE = 5, CONTINUOUS = 6, TIMER_BAR = 8, STAGGER = 9, IRONFUR = 10, NATIVE_AURA = 11 }, SPEC = {}, SPELL = {}, BAL = {}, THRESH = {} }
local TIP = CPConst.TIP or {}
local PT = CPConst.PT or {}
local POWER_TYPE_TOKENS = CPConst.POWER_TYPE_TOKENS or {}

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
local function RefreshPlayerPowerBar()
    local refresh = _G.MSUF_RefreshPlayerPowerBar
    if refresh then refresh() end
end
--- DH Vengeance: Soul Fragments via C_Spell.GetSpellCastCount (MCR-sourced)

--- Phase 5 CP split: Balance Druid Astral Power prediction + eclipse colors now
--- live in ClassPower/MSUF_CP_BalanceDruid.lua. The core keeps only the
--- global color invalidation hook call, so this file stays closer to a pure
--- orchestrator.

--- Hunter Survival: Tip of the Spear (talent 260285)
--- Evoker Augmentation: native 12.1 Ebon Might duration text.

--- The TOC-loaded AltMana builder replaces this before any consumer runs.
local NeedsAltManaBar = CP_Noop

--- Cold configuration helpers live in ClassPower/MSUF_CP_Controller_Config.lua:
--- the cached DB config (_cpDB), SavedVariables defaults, feature gates,
--- class/spec -> render-mode routing, the structural signature and the per-mode
--- event profile. Hot paths keep _cpDB as an upvalue; everything else runs at
--- FullRefresh cadence and is read through the CPConfig table.
local CPConfig = CP_CallBuilder(CPCoreBuilders.CONTROLLER_CONFIG, {
    CPConst = CPConst,
    CPK = CPK,
    PT = PT,
    TIP = TIP,
    PLAYER_CLASS = PLAYER_CLASS,
    GetSpec = GetSpec,
    NotSecret = NotSecret,
    NeedsAltManaBar = function() return NeedsAltManaBar() end,
})
local _cpDB = CPConfig._cpDB
local CP_GetModeEventProfile = CPConfig.GetModeEventProfile

--- Colour resolution lives in ClassPower/MSUF_CP_Controller_Colors.lua. The
--- resolvers cache per token; mode runners receive them by value through their
--- build env and CP_CompileVisual reads them once per refresh.
local CPColors = CP_CallBuilder(CPCoreBuilders.CONTROLLER_COLORS, {
    _cpDB = _cpDB,
    POWER_TYPE_TOKENS = POWER_TYPE_TOKENS,
})

--- Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
--- v6.1 behavior: rebuild the reused 1-based slot map when the charged-point
--- event or a segmented structural refresh requests it.
local _chargedMap = {}
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
    augCompositeActive = false, --- Ebon Might owns the Player Power bar
    ebonSensorDesired = false,
    ebonTextLayerRetryPending = false,
    augLifecycleRetryPending = false,
    augLifecycleDisablePending = false,
    augLifecycleTarget = nil,
    --- Spell Tracker state (Tip of the Spear only - Whirlwind is native aura-owned)
    spStacks    = 0,       --- current stack count
    spExpires   = nil,     --- GetTime() expiry timestamp (nil = no timer)
}

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
        baseR, baseG, baseB = CPColors.ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end
    local bgR, bgG, bgB = CPColors.ResolveClassPowerBgColor(powerType)
    local chargedR, chargedG, chargedB = CPColors.ResolveChargedColor()

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
    local slotMode = CPColors.ResolveSlotColorMode(visual.powerToken)
    local segmentedMode = renderMode == CPK.MODE.SEGMENTED
        or renderMode == CPK.MODE.FRACTIONAL
        or renderMode == CPK.MODE.RUNE_CD
        or renderMode == CPK.MODE.AURA_SEGMENTED
    visual.useSlotColors = segmentedMode and (slotMode == "ramp" or slotMode == "custom")
    visual.useFullColor, visual.fullR, visual.fullG, visual.fullB = CPColors.ResolveFullResourceColor(
        visual.powerToken, baseR, baseG, baseB)
    if not segmentedMode then visual.useFullColor = false end

    if visual.useSlotColors then
        visual.slotR, visual.slotG, visual.slotB = CP.slotR, CP.slotG, CP.slotB
        for i = 1, math_min(tonumber(maxP) or 0, 10) do
            local r, g, bl = CPColors.ResolveSlotColor(visual.powerToken, i, baseR, baseG, baseB)
            visual.slotR[i], visual.slotG[i], visual.slotB[i] = r, g, bl
        end
    end

    return visual
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
            CP_ResolveTexture = CPConfig.ResolveTexture,
        })
    if build then
        CP_EnsureBars = build.CP_EnsureBars or CP_EnsureBars
        CP_Create = build.CP_Create or CP_Create
        CP_EnsureRuneText = build.CP_EnsureRuneText
        CP_EnsureMainText = build.CP_EnsureMainText
    end
end

--- Font / text-offset presentation helpers now live in the PRESENTATION
--- builder of ClassPower/MSUF_CP_Core.lua.
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
            ResolveClassPowerBgColor = CPColors.ResolveClassPowerBgColor,
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
--- ClassPower/MSUF_CP_Modes.lua. The core builds them with local env closures so
--- the public runtime stays identical while the main chunk gets smaller.
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
        ResolveClassPowerColor = CPColors.ResolveClassPowerColor,
        ResolveClassPowerBgColor = CPColors.ResolveClassPowerBgColor,
        ResolveChargedColor = CPColors.ResolveChargedColor,
        ResolveSlotColor = CPColors.ResolveSlotColor,
        ResolveFullResourceColor = CPColors.ResolveFullResourceColor,
        ResolveMWAbove5Color = CPColors.ResolveMWAbove5Color,
        CP_CheckAutoHide = CP_CheckAutoHide,
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

--- Phase 7A CP split: pure presentation helpers now live in the PRESENTATION
--- builder of ClassPower/MSUF_CP_Core.lua. This keeps the core smaller without
--- touching build/layout/value flow.
do
    local presentation = CP_CallBuilder(CPCoreBuilders.PRESENTATION, {
            CP = CP,
            _cpDB = _cpDB,
            PT = PT,
            math_floor = math_floor,
            tonumber = tonumber,
            ResolveClassPowerColor = CPColors.ResolveClassPowerColor,
            CP_ResolveTexture = CPConfig.ResolveTexture,
            GetUpdateFn = function() return CP_UpdateValues end,
        })
    if presentation then
        CDM_GetScaledWidth = presentation.CDM_GetScaledWidth or CDM_GetScaledWidth
        CP_ApplyFont = presentation.CP_ApplyFont or CP_ApplyFont
        CP_ApplyColors = presentation.CP_ApplyColors or CP_ApplyColors
        CP_RefreshTexture = presentation.CP_RefreshTexture or CP_RefreshTexture
    end
end
ExportPublic("MSUF_CDM_GetScaledWidth", CDM_GetScaledWidth)

--- Apply-time surface helpers live in ClassPower/MSUF_CP_Controller_Surface.lua:
--- the Ebon Might host/style on the Player Power bar, the Aug composite reset,
--- the hidden anchor for a detached Power bar, the DK Rune display order and the
--- cooldown-frame width sync. The builder installs CP.GetEbonTextLevel and the
--- CP.CDMWidth* helpers on the shared state table; it runs after BUILD and
--- LAYOUT so the bound create/layout closures can be passed by value.
local CPSurface = CP_CallBuilder(CPCoreBuilders.CONTROLLER_SURFACE, {
    CP = CP,
    _cpDB = _cpDB,
    CPConst = CPConst,
    ResolveClassPowerColor = CPColors.ResolveClassPowerColor,
    CP_ResolveTexture = CPConfig.ResolveTexture,
    CP_Create = CP_Create,
    CP_EnsureBars = CP_EnsureBars,
    CP_Layout = CP_Layout,
})

CP.ebonNative = CP_CallBuilder(CPCoreBuilders.EBON_MIGHT, {
    CP = CP,
    EBON = CPConst.EBON or {},
    _cpDB = _cpDB,
    CreateFrame = CreateFrame,
    GetHost = CPSurface.ResolveEbonHost,
    GetStyle = CPSurface.GetEbonStyle,
    GetTextLevel = CP.GetEbonTextLevel,
})
--- MSUF_ClassPower_MountEbonMight (the Power element's mount callback) is
--- exported by the CONTROLLER_SURFACE builder next to the host resolver.

--- Legacy color-only refresh / texture refresh now live in the PRESENTATION
--- builder of ClassPower/MSUF_CP_Core.lua.

--- CPK.MODE.FRACTIONAL: Destruction Warlock - partial Soul Shard fill.
--- UnitPower(unit, type, true) / UnitPowerDisplayMod(type) gives e.g. 3.7
--- Fractional mode runner moved to ClassPower/MSUF_CP_Modes.lua (FRACTIONAL builder)

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
        ResolveClassPowerColor = CPColors.ResolveClassPowerColor,
        ResolveClassPowerBgColor = CPColors.ResolveClassPowerBgColor,
        CP_CheckAutoHide = CP_CheckAutoHide,
        CP_ApplyRuneSortOrder = CPSurface.ApplyRuneSortOrder,
        GetRuneMap = CPSurface.GetRuneMap,
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

--- Phase 5 CP split: class/resource specials now live in the SPECIALS builder
--- of ClassPower/MSUF_CP_Core.lua. The core builds the handlers from a
--- small feature builder so event wiring stays identical while class-specific
--- logic stops bloating the orchestrator chunk.
local OnWarlockCastStart
local OnWarlockCastEnd
local OnTipOfTheSpearSpellCast
local OnSpellTrackerReset
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

--- Phase 4 CP split: continuous + stagger mode runners now live in the
--- CONTINUOUS and STAGGER builders of ClassPower/MSUF_CP_Modes.lua.
--- The core keeps only orchestration and event wiring, while the heavy single-bar
--- runners live outside the main chunk.

local CP_RefreshEventBindings

-- Lazily allocate only the active class's native slots. No aura/cast event feed.
function CP.SyncNativeAuras()
    if not CP.nativeAuras and PLAYER_CLASS == "WARRIOR" then
        local build = MSUF.CPBuilders and MSUF.CPBuilders.NativeAuras
        if build then
            CP.nativeAuras = build({ CP = CP, db = _cpDB,
                Texture = CPConfig.ResolveTexture, TextLevel = CP.GetEbonTextLevel })
        end
    end
    if CP.nativeAuras then
        CP.nativeAuras.Sync()
        if CP_RefreshEventBindings then CP_RefreshEventBindings() end
    end
end

--- Update function dispatch table (set in FullRefresh, called in hot path)
local MODE_UPDATE_FN = {
    [CPK.MODE.NATIVE_AURA]    = function() CP_CheckAutoHide(nil, nil) end,
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
            ResolveClassPowerColor = CPColors.ResolveClassPowerColor,
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

--- "Sync width to Class Resource" matches the live container or the hidden
--- anchor maintained for an attached detached Power bar. Nothing else observes
--- that transition - the cooldown-width observers watch Blizzard viewers - so
--- notify the Power element from the show/hide path itself. Width-only: no config
--- compile and no element routing.
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
    return PHP.visible == true or CPConfig.PlayerHPBarEnabled()
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
            ResolveTexture = CPConfig.ResolveTexture,
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

--- Full refresh (called on spec change, form change, config change)
--- FullRefresh runs a fixed sequence of cold stages. The stage functions live
--- on one table so the split spends a single main-chunk local (this file sits
--- near the Lua 5.1 local ceiling). Execution order is unchanged: every stage
--- runs exactly where its body used to sit inline.
local Refresh = {}

--- Player Power source override. Missing/AUTO preserves the exact existing
--- profile behavior below (Elemental/Shadow row ownership and Aug Ebon
--- Might). MANA is explicit, applies only to a real player Mana pool, and
--- yields to vehicle power until the structural exit event fires.
function Refresh.ResolveDisplayOwnership(cpEnabled, powerType, renderMode)
    local inVehicle = (UnitHasVehicleUI and UnitHasVehicleUI("player")) or false
    local playerManaEnabled = CPConfig.PlayerManaOverrideEnabled(inVehicle)
    local playerManaOverride = playerManaEnabled and not inVehicle or false
    local wasDisplayMana = _G.MSUF_PlayerPowerManaOverrideActive == true
        or _G.MSUF_EleMaelstromActive == true or _G.MSUF_ShadowManaActive == true

    --- Elemental: AUTO keeps the current ownership contract. When Maelstrom
    --- owns MSUF's Class Resource row, the ordinary Player surface shows Mana.
    local isEleMaelstrom = (cpEnabled and PLAYER_CLASS == "SHAMAN"
        and powerType == PT.Maelstrom and renderMode == CPK.MODE.CONTINUOUS) or false
    local isShadowMana = (cpEnabled and PLAYER_CLASS == "PRIEST"
        and powerType == PT.Insanity and renderMode == CPK.MODE.CONTINUOUS) or false
    local displayManaChanged = wasDisplayMana
        ~= (playerManaOverride or isEleMaelstrom or isShadowMana)
    ExportPublic("MSUF_EleMaelstromActive", isEleMaelstrom)
    ExportPublic("MSUF_ShadowManaActive", isShadowMana)
    return playerManaEnabled, playerManaOverride, displayManaChanged
end

--- Augmentation uses a two-resource model: segmented Essence remains active
--- while Ebon Might occupies a native companion row. The
--- hidden Player Power bar carries their combined geometry; optional Mana
--- remains available through AltMana.
--- Yields false when the hand-off was deferred to PLAYER_REGEN_ENABLED; the
--- caller must then stop the refresh at once.
function Refresh.ApplyAugLifecycle(b, cpEnabled, powerType, playerManaOverride, displayManaChanged)
    local wantsAugComposite = (not playerManaOverride
        and cpEnabled and powerType == PT.Essence
        and PLAYER_CLASS == "EVOKER"
        and GetSpec and GetSpec() == CPK.SPEC.EVOKER_AUG
        and b.showEbonMight ~= false) or false
    local wasAugComposite = CP.augCompositeActive == true

    --- Creating the native AuraContainer is restricted work, and the Power
    --- element cannot re-skin or re-anchor its bar during lockdown either. Keep
    --- both sides of the hand-off on one PLAYER_REGEN_ENABLED pass.
    local augTransition = wasAugComposite ~= wantsAugComposite
    if augTransition and InCombatLockdown and InCombatLockdown() then
        CP.augLifecycleRetryPending = true
        CP.augLifecycleTarget = wantsAugComposite
        if CP_RefreshEventBindings then CP_RefreshEventBindings() end
        return false
    end
    if CP.augLifecycleRetryPending == true then
        --- A second structural change can return to the already-published side
        --- before regen (vehicle enter -> exit, or spec/settings reversal).
        --- Clear the obsolete hand-off and finish the ordinary refresh: vehicle,
        --- class-resource and event state may still have changed underneath it.
        CP.augLifecycleRetryPending = false
        CP.augLifecycleTarget = nil
    end

    -- Publish only after any protected Aug/Ebon hand-off can happen. During a
    -- combat-deferred transition the old flag must continue to describe the
    -- surface that is actually still mounted.
    ExportPublic("MSUF_PlayerPowerManaOverrideActive", playerManaOverride)

    --- Publish the intent before the Power element re-applies: it reads the
    --- public flag to decide whether this bar renders Ebon Might or ordinary
    --- Mana, and calls back into MSUF_ClassPower_MountEbonMight once its bar is
    --- laid out - which is the first moment the host is guaranteed to exist.
    if wantsAugComposite or not wasAugComposite then
        CP.ebonSensorDesired = wantsAugComposite
    end
    local augChanged = wantsAugComposite ~= wasAugComposite
        or wantsAugComposite ~= (_G.MSUF_AugEvokerActive == true)
    if wantsAugComposite then
        --- Entry order is state -> Power -> sensor: the element reads the public
        --- flag to decide whether this bar renders Ebon Might or Mana, and calls
        --- back into MSUF_ClassPower_MountEbonMight once its bar is laid out,
        --- which is the first moment the host is guaranteed to exist.
        if augChanged then
            CP.augCompositeActive = true
            ExportPublic("MSUF_AugEvokerActive", true)
            RefreshPlayerPowerBar()
        end
        CP.SetEbonSensorActive(true)
        if CP.ebonSensor == nil then
            --- Blizzard_AuraContainer could not be created (notably a UI start
            --- in combat). Fall back to an ordinary Mana bar instead of leaving
            --- an empty one behind; the event driver retries after regen.
            CP.augCompositeActive = false
            ExportPublic("MSUF_AugEvokerActive", false)
            RefreshPlayerPowerBar()
        end
    else
        --- Exit order is state -> sensor -> Power, matching CP.DisableNow: the
        --- flag has to be down before the element re-applies, or the bar would
        --- immediately re-enter Ebon mode.
        if augChanged then
            CP.augCompositeActive = false
            ExportPublic("MSUF_AugEvokerActive", false)
        end
        CP.SetEbonSensorActive(false)
        if augChanged then RefreshPlayerPowerBar() end
    end

    --- Aug entry/exit already reapplied the same Player surface.
    if displayManaChanged and not augChanged then RefreshPlayerPowerBar() end
    return true
end

--- Resolve max power based on render mode
function Refresh.ResolveMaxPower(powerType, renderMode)
    local maxP
    if renderMode == CPK.MODE.NATIVE_AURA then
        maxP = 1 -- one native fill; separators do not need aura slots
    elseif renderMode == CPK.MODE.RUNE_CD then
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
    return maxP
end

--- Active branch: build, lay out, compile and dispatch the first update.
function Refresh.ShowClassPower(playerFrame, b, cpHeight, powerType, renderMode, isAuraPower)
    CP_Create(playerFrame)

    local maxP = Refresh.ResolveMaxPower(powerType, renderMode)

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

    --- Seed the v6.1 charged map only for active Rogue Combo Points.
    if PLAYER_CLASS == "ROGUE" and renderMode == CPK.MODE.SEGMENTED
        and powerType == PT.ComboPoints
        and CP.visual and CP.visual.showCharged == true
    then
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
    CP.SyncNativeAuras()
    if CP.augCompositeActive == true then
        --- Keep-alive only. The host is the Player Power bar, so its
        --- geometry and visibility belong to the Power element.
        CP.SetEbonSensorActive(true)
    end
    --- The container is measurable only now, so a synced detached Power bar
    --- can finally match it.
    CP.RefreshSyncedPowerWidth(playerFrame)
    --- Belt-and-suspenders: ensure outline survives parent Hide/Show cycle
    if CP._outline then
        local outlineBars = _cpDB.bars or {}
        local outlineShape = renderMode == CPK.MODE.NATIVE_AURA and "BAR"
            or tostring(outlineBars.classPowerShape or "BAR"):upper()
        local outlineSize = tonumber(outlineBars.classPowerOutline) or 1
        if outlineShape == "BAR" and outlineSize > 0 and CP._msufRoundedOutlineSuppressed ~= true then
            CP._outline:Show()
        else
            CP._outline:Hide()
        end
    end
end

--- Hidden branch: clean up resource runtime state when hiding.
--- The Aug exit (state -> sensor -> Power) has already run in ApplyAugLifecycle,
--- so the sensor teardown here is unconditional.
function Refresh.HideClassPower(playerFrame, cpHeight)
    CP.SetEbonSensorActive(false)
    if CP.ironfur and CP.ironfur.SetActive then CP.ironfur.SetActive(false) end
    CP.visual = nil
    if (CP.renderMode == CPK.MODE.RUNE_CD or CP.runeOUAAny or CP.runeNativeAny) and CP_StopRuneOnUpdates then
        CP_StopRuneOnUpdates(true)
    end
    if (CP.essenceOUAAny or CP.essenceNativeAny) and CP_StopEssenceOnUpdates then CP_StopEssenceOnUpdates() end
    CP_StopCentralTick()
    local maintainedAnchor = CPSurface.EnsureHiddenAnchorGeometry(playerFrame, cpHeight)
    if CP.container then
        if not maintainedAnchor then
            CP.container._msufAnchorOnly = nil
        end
        CP.container:Hide()
    end
    CP.visible = false
    if CP.nativeAuras then CP.nativeAuras.Disable() end
    --- Re-resolve against the maintained hidden anchor when present;
    --- otherwise return the detached Power bar to its configured width.
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

--- --- AltMana ---
function Refresh.ApplyAltMana(playerFrame, amEnabled, inEditMode)
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
end

--- Texture refresh for every visible surface (settings apply and the live
--- bar-texture hook share it).
function Refresh.VisibleTextures()
    if CP.visible then CP_RefreshTexture() end
    if AM.visible then AM_RefreshTexture() end
    if PHP.visible then
        PHP._textureStamp = nil
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
end

local CP_SetStructuralEventsBound = CP_Noop
local function FullRefresh()
    if not MSUF_DB then return end
    CPConfig.RefreshConfig()  --- P0: rebuild cached config
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
        powerType, renderMode, isAuraPower = CPConfig.GetClassPowerType()
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
    local cpHeight = CPConfig.ResolveClassPowerHeight(b)

    --- Hook player frame resize only when ClassPower can use it. Once hooked,
    --- the callback exits without DB work while ClassPower is disabled.
    if cpEnabled and not playerFrame._msufCPSizeHooked then
        playerFrame._msufCPSizeHooked = true
        playerFrame:HookScript("OnSizeChanged", function()
            if not CPConfig.ClassPowerEnabled() then return end
            if _G.MSUF_ClassPower_Apply then
                _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, syncNow = false })
            elseif _G.MSUF_ClassPower_Refresh then
                _G.MSUF_ClassPower_Refresh()
            end
        end)
    end

    local playerManaEnabled, playerManaOverride, displayManaChanged =
        Refresh.ResolveDisplayOwnership(cpEnabled, powerType, renderMode)
    if not Refresh.ApplyAugLifecycle(b, cpEnabled, powerType, playerManaOverride, displayManaChanged) then
        return
    end

    if cpEnabled and powerType and renderMode ~= CPK.MODE.NONE then
        Refresh.ShowClassPower(playerFrame, b, cpHeight, powerType, renderMode, isAuraPower)
    else
        Refresh.HideClassPower(playerFrame, cpHeight)
    end

    Refresh.ApplyAltMana(playerFrame, amEnabled, inEditMode)

    if CP_PlayerHPNeedsRefresh() then
        CP_PlayerHPRefresh(playerFrame)
    end

    CP.structuralFlags, CP.structuralPowerType, CP.structuralRenderMode = CPConfig.ComputeStructuralSignature()
    CP_RefreshEventBindings()
    local anyFeatureEnabled = CPConfig.AnyFeatureEnabled(playerManaEnabled)
    CP_SetStructuralEventsBound(anyFeatureEnabled)
    if CP.SyncControllerEvents then CP.SyncControllerEvents(anyFeatureEnabled) end
    if type(_G.MSUF_BAL_RefreshRuntime) == "function" then
        _G.MSUF_BAL_RefreshRuntime()
    end
end

--- Event-driven updates (hot path: minimal work)
--- Runtime handlers now come from the CP runtime feature builder below.

--- Phase 6 CP split: runtime/light-refresh handlers now live in the RUNTIME
--- builder of ClassPower/MSUF_CP_Core.lua. The core keeps event-frame wiring,
--- while hot-path glue and structural light-refresh helpers live in that
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
            CP_ComputeStructuralSignature = CPConfig.ComputeStructuralSignature,
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

--- The CP.CDMWidth* sync helpers are installed by the CONTROLLER_SURFACE builder
--- above; only their event (un)binding stays here next to the event frame.
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
    local wantPointCharge = CP.visible
        and profile.pointCharge == true
        and PLAYER_CLASS == "ROGUE"
        and CP.powerType == PT.ComboPoints
        and CP.visual ~= nil
        and CP.visual.showCharged == true
    local wantWarlockPred = CP.visible and profile.warlockPred == true
    local wantSpellSucceeded = CP.visible and profile.spellSucceeded == true
    local wantDisplayPower = CP.visible or AM.visible
    local wantRegen = CP.nativeAuraPending == true
        or (_autoHideActive and CP.visible)
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
            --- Whirlwind has no addon-owned cast tracker.
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
            --- Rebuild the v6.1 charged map on the dedicated Rogue point event.
            if CP.visible and CP.renderMode == CPK.MODE.SEGMENTED
                and PLAYER_CLASS == "ROGUE"
                and CP.powerType == PT.ComboPoints
                and CP.visual and CP.visual.showCharged == true
            then
                RefreshChargedPoints()
                CP_UpdateValues(CP.powerType, CP.currentMax)
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
            if CP.nativeAuraPending then CP.SyncNativeAuras() end
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
            CP_RunActiveUpdate(CP.powerType, CP.currentMax)
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
        CPConfig.EnsureDefaults()
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
        CPConfig.EnsureDefaults()
        return
    end

    if event == "ADDON_LOADED" then
        if arg1 ~= "Blizzard_CooldownViewer" and arg1 ~= "Blizzard_EditMode" then return end
        if CP.CDMWidthHasConfiguredSync and CP.CDMWidthHasConfiguredSync() then
            if type(CP.RefreshCDMWidthBindings) == "function" then
                CP.RefreshCDMWidthBindings(false)
            else
                CPConfig.RefreshConfig()
                if CP_RefreshEventBindings then CP_RefreshEventBindings() end
            end
        end
        return
    end
end

-- Bound directly: the handler already takes the (frame, event, arg1..arg3)
-- shape OnEvent hands it, so a forwarding closure would only add a call frame
-- to every UNIT_POWER_FREQUENT.
eventFrame:SetScript("OnEvent", ClassPowerOnEvent)

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
CP.SyncControllerEvents(CPConfig.AnyFeatureEnabled())

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
    CPColors.InvalidateCaches()
    FullRefresh()
end
ExportPublic("MSUF_ClassPower_Refresh", CP.RefreshPublic)

CP.RefreshCDMWidthBindings = function(syncNow)
    CPConfig.RefreshConfig()
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
    CPConfig.RefreshConfig()
    CP_PlayerHPRefresh(GetPlayerFrame())
    CP_RefreshEventBindings()
    CP_SetStructuralEventsBound(CPConfig.AnyFeatureEnabled())
end
ExportPublic("MSUF_ClassPower_PlayerHP_Refresh", CP.PlayerHPRefreshPublic)

CP.PlayerHPRefreshTextures = function()
    CPConfig.RefreshConfig()
    if PHP.visible then
        PHP._textureStamp = nil
        CP_PlayerHPRefresh(GetPlayerFrame())
    end
end
ExportPublic("MSUF_ClassPower_PlayerHP_RefreshTextures", CP.PlayerHPRefreshTextures)

--- Refresh bar textures (call after texture change in settings)
CP.RefreshTexturesPublic = function()
    CPConfig.RefreshConfig()
    Refresh.VisibleTextures()
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
    local cpHeight = CPConfig.ResolveClassPowerHeight(b)
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
    CP.SyncNativeAuras()
    return true
end

ExportPublic("MSUF_ClassPower_RefreshLayout", function()
    CPConfig.RefreshConfig()
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
    CPConfig.RefreshConfig()
    if CP.visible then
        --- CP_ApplyFont re-applies on its own font-serial / apply-epoch stamps;
        --- every global font change advances one of them.
        CP_ApplyFont()
        CP.SetEbonSensorActive(CP.augCompositeActive == true)
        if CP.RefreshEbonStyle then CP.RefreshEbonStyle() end
        CP.ApplyEbonTextStyle()
        CP.SyncNativeAuras()
    end
    if PHP.visible then
        PHP._fontStamp = nil
        CP_PlayerHPApplyFont()
    end
end
ExportPublic("MSUF_ClassPower_ApplyFonts", CP.ApplyFontsPublic)

CP.RefreshVisualsPublic = function()
    CPConfig.RefreshConfig()
    CPColors.InvalidateCaches()
    if CP.visible then
        CP_CompileVisual(CP.powerType, CP.renderMode, CP.currentMax)
        if CP_RefreshTexture then CP_RefreshTexture() end
        if CP_ApplyFont then CP_ApplyFont() end
        if CP_ApplyColors then CP_ApplyColors(CP.powerType) end
        if CP.RefreshEbonStyle then CP.RefreshEbonStyle() end
        CP.ApplyEbonTextStyle()
        CP.SyncNativeAuras()
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
            if opts.text == true and CP.visible then
                CP_RunActiveUpdate(CP.powerType, CP.currentMax)
            end
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
        CPConfig.RefreshConfig()
        CP_RefreshEventBindings()
        CP_SetStructuralEventsBound(CPConfig.AnyFeatureEnabled())
        did = true
    end

    if not did then
        CPConfig.RefreshConfig()
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
                    Refresh.VisibleTextures()
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
--- combat: Disable() retains the live surface and the event driver calls this
--- once on PLAYER_REGEN_ENABLED. Clear every Player-power ownership flag before
--- the refresh so no class-resource identity survives module shutdown.
function CP.DisableNow()
    CPConfig.RefreshConfig()
    CP.augLifecycleRetryPending = false
    CP.augLifecycleDisablePending = false
    CP.augLifecycleTarget = nil

    local augWasActive = CP.augCompositeActive == true or _G.MSUF_AugEvokerActive == true
    local displayPowerWasOverridden = _G.MSUF_EleMaelstromActive == true
        or _G.MSUF_ShadowManaActive == true
        or _G.MSUF_PlayerPowerManaOverrideActive == true
    ExportPublic("MSUF_EleMaelstromActive", false)
    ExportPublic("MSUF_ShadowManaActive", false)
    ExportPublic("MSUF_PlayerPowerManaOverrideActive", false)

    CP_RefreshEventBindings()
    CP_SetStructuralEventsBound(false)
    CP.SyncControllerEvents(false)
    CPSurface.ClearAugCompositeState()
    CP.SetEbonSensorActive(false)
    if CP.nativeAuras then CP.nativeAuras.Disable() end
    if CP.container then CP.container:Hide() end
    if AM.container then AM.container:Hide() end
    if PHP.container then PHP.container:Hide() end
    CP.visible, AM.visible, PHP.visible = false, false, false
    if augWasActive or displayPowerWasOverridden then RefreshPlayerPowerBar() end
end

--- Phase 4: Module Registration
do
    if type(_G.MSUF_RegisterModule) == "function" then
        _G.MSUF_RegisterModule("ClassPower", {
            order = 30,
            IsEnabled = function()
                return CPConfig.AnyFeatureEnabled()
            end,
            Enable = function()
                --- Re-enable before regen cancels a deferred module teardown.
                --- FullRefresh below either keeps the still-correct composite or
                --- arms the ordinary transition retry for the new live state.
                CP.augLifecycleDisablePending = false
                CP.augLifecycleRetryPending = false
                CP.augLifecycleTarget = nil
                CP.SyncControllerEvents(true)
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
                CPColors.ResetTokens()
                FullRefresh()
            end,
            Shutdown = function()
                CPColors.ResetTokens()
            end,
        })
    end
end

--- Balance Druid prediction/runtime moved to ClassPower\\MSUF_CP_BalanceDruid.lua.
