local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry

local floor = math.floor

local UNIT_LABELS = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focustarget = "Focus Target",
    focus = "Focus",
    pet = "Pet",
    boss = "Boss",
    party = "Party",
    raid = "Raid",
    mythicraid = "Mythic Raid",
}

local UNIT_ALIASES = {
    player = { "player", "spieler", "self", "ich" },
    target = { "target", "ziel" },
    targettarget = { "targettarget", "target of target", "tot", "ziel des ziels" },
    focustarget = { "focustarget", "focus target", "fokus ziel" },
    focus = { "focus", "fokus" },
    pet = { "pet", "begleiter" },
    boss = { "boss", "boss frames", "bossframes" },
    party = { "party", "party frame", "party frames", "partyframe", "group", "group frames", "gruppenframes", "gruppe" },
    raid = { "raid", "raid frame", "raid frames", "raidframe", "schlachtzug" },
    mythicraid = { "mythicraid", "mythic raid", "mythic raid frame", "mythic raid frames", "mythicraidframe" },
}
A.UnitAliases = UNIT_ALIASES
A.UnitLabels = UNIT_LABELS

local function EnsureDB()
    if M and type(M.EnsureDB) == "function" then return M.EnsureDB() end
    _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
    _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
    return _G.MSUF_DB
end

local function UnitDB(unit)
    local db = EnsureDB()
    if unit == "tot" then unit = "targettarget" end
    db[unit] = type(db[unit]) == "table" and db[unit] or {}
    if unit == "targettarget" then db.tot = db[unit] end
    return db[unit]
end

local function GeneralDB()
    local db = EnsureDB()
    db.general = type(db.general) == "table" and db.general or {}
    return db.general
end

local function BarsDB()
    local db = EnsureDB()
    db.bars = type(db.bars) == "table" and db.bars or {}
    return db.bars
end

local function GameplayDB()
    local db = EnsureDB()
    db.gameplay = type(db.gameplay) == "table" and db.gameplay or {}
    return db.gameplay
end

local function GroupDB(scope)
    local db = EnsureDB()
    local key = scope == "raid" and "gf_raid" or (scope == "mythicraid" and "gf_mythicraid" or "gf_party")
    db[key] = type(db[key]) == "table" and db[key] or {}
    return db[key]
end

local function ClampNumber(value, minValue, maxValue, step)
    value = tonumber(value)
    if value == nil then return nil end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    step = tonumber(step)
    if step and step > 0 then
        value = floor((value / step) + 0.5) * step
    end
    if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
    return value
end
A.ClampNumber = A.ClampNumber or ClampNumber

local function CallGlobal(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then fn(...) end
end

local function ApplyUnit(unit, reason, opts)
    if M and type(M.RequestUnitApply) == "function" then
        M.RequestUnitApply(unit, reason or "MSUF_ASSISTANT_UNIT", opts or { preview = true })
    else
        local UF = MSUF and MSUF.UF
        if UF and type(UF.Apply) == "function" then UF.Apply(unit) end
    end
end

local function ApplyGeneral(reason, opts)
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply(reason or "MSUF_ASSISTANT_GENERAL", opts or { preview = true })
    end
end

local ApplyAura

local function ApplyVisuals(reason)
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then api.PushVisualUpdates() end
    ApplyGeneral(reason or "MSUF_ASSISTANT_VISUALS", { preview = true, applyAll = false })
    CallGlobal("MSUF_UpdateAllFonts_Immediate")
    CallGlobal("MSUF_UpdateAllFonts")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_VISUALS")
end

local function ApplyColors(reason)
    reason = reason or "MSUF_ASSISTANT_COLORS"
    ApplyVisuals(reason)
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_PrioRows_Reinit")
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshColors) == "function" then gf.RefreshColors() end
    if gf and type(gf.RefreshVisuals) == "function" then gf.RefreshVisuals() end
end

local function ApplyCastbarColors(reason)
    ApplyColors(reason or "MSUF_ASSISTANT_CASTBAR_COLORS")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_UpdateCastbarVisuals")
    local fn = MSUF and MSUF.MSUF_UpdateCastbarVisuals
    if type(fn) == "function" then fn() end
    fn = MSUF and MSUF.MSUF_UpdateCastbarTextures_Immediate
    if type(fn) == "function" then fn() end
end

local function ApplyGameplayColors(reason)
    ApplyColors(reason or "MSUF_ASSISTANT_GAMEPLAY_COLORS")
    if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        MSUF.MSUF_ApplyGameplayVisuals()
    elseif M and type(M.ApplyGameplay) == "function" then
        M.ApplyGameplay()
    end
end

local function ApplyClassPowerColors(reason)
    ApplyColors(reason or "MSUF_ASSISTANT_CLASS_POWER_COLORS")
    CallGlobal("MSUF_ClassPower_InvalidateColors")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
end

local function ApplyAuraColors(reason)
    ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_COLORS")
    ApplyColors(reason or "MSUF_ASSISTANT_AURA_COLORS")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_Auras3_RefreshAll")
    CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
end

local function ApplyPortraitColors(reason)
    ApplyColors(reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_PORTRAIT_COLORS")
end

local function ApplyFonts(reason)
    ApplyGeneral(reason or "MSUF_ASSISTANT_FONTS", { preview = true, applyAll = false })
    CallGlobal("MSUF_UpdateAllFonts_Immediate")
    CallGlobal("MSUF_UpdateAllFonts")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_FONTS")
end

local function ApplyBars(reason)
    ApplyGeneral(reason or "MSUF_ASSISTANT_BARS", { preview = true, applyAll = false })
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    CallGlobal("MSUF_UpdateAllBarTextures")
    CallGlobal("MSUF_UpdateAbsorbBarTextures")
    CallGlobal("MSUF_InvalidateAbsorbCache")
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_BARS")
end

local function ApplyBarGradients(reason)
    ApplyGeneral(reason or "MSUF_ASSISTANT_BAR_GRADIENT", { preview = true, applyAll = false, notify = false })
    CallGlobal("MSUF_UpdateAllBarGradients")
end

local function ApplyBarOutline(reason)
    ApplyBars(reason or "MSUF_ASSISTANT_BAR_OUTLINE")
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    CallGlobal("MSUF_GF_RefreshOutlineGeometry")
    CallGlobal("MSUF_ApplyRoundedUnitframes")
end

local function ApplyRoundedBars(reason)
    ApplyBars(reason or "MSUF_ASSISTANT_ROUNDED_BARS")
    CallGlobal("MSUF_ApplyRoundedUnitframes")
    CallGlobal("MSUF_GF_RefreshPreviewLayout", "party")
    CallGlobal("MSUF_GF_RefreshPreviewLayout", "raid")
    CallGlobal("MSUF_GF_RefreshPreviewLayout", "mythicraid")
    CallGlobal("MSUF_GF_RefreshPreviewBox")
end

local function ApplyAggroBorder(reason)
    ApplyBars(reason or "MSUF_ASSISTANT_AGGRO_BORDER")
    CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_AGGRO_BORDER")
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    CallGlobal("MSUF_AggroOutline_ApplyEventRegistration")
end

local function ApplyDispelPurgeBorder(reason)
    ApplyBars(reason or "MSUF_ASSISTANT_DISPEL_PURGE_BORDER")
    CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_DISPEL_PURGE_BORDER")
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    CallGlobal("MSUF_DispelOutline_ApplyEventRegistration")
    CallGlobal("MSUF_RefreshDispelOutlineStates", true)
    CallGlobal("MSUF_RefreshUnitDispelOverlays")
end

local function ApplyBossTargetBorder(reason)
    ApplyBars(reason or "MSUF_ASSISTANT_BOSS_TARGET_BORDER")
    CallGlobal("MSUF_UFCore_RefreshSettingsCache", "MSUF_ASSISTANT_BOSS_TARGET_BORDER")
    local UF = MSUF and MSUF.UF
    if UF and type(UF.ForceUpdate) == "function" then UF.ForceUpdate(nil) end
end

local function ApplyHighlightBorders(reason)
    ApplyAggroBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
    ApplyDispelPurgeBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
    ApplyBossTargetBorder(reason or "MSUF_ASSISTANT_HIGHLIGHT_BORDERS")
end

local function ApplyAbsorbBars(reason)
    CallGlobal("MSUF_InvalidateAbsorbCache")
    ApplyBars(reason or "MSUF_ASSISTANT_ABSORB_BARS")
end

local function ApplyClassPower(reason)
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    ApplyGeneral(reason or "MSUF_ASSISTANT_CLASSPOWER", { preview = true, applyAll = false })
end

local function ApplyDetachedPowerBar(reason)
    CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    ApplyGeneral(reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
end

local function ApplyDetachedPowerBarOutline(reason)
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar(reason or "MSUF_ASSISTANT_DETACHED_POWER_BAR_OUTLINE")
end

local function ApplyGameplay(reason)
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        MSUF.MSUF_RequestGameplayApply(reason or "MSUF_ASSISTANT_GAMEPLAY")
    elseif MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        MSUF.MSUF_ApplyGameplayVisuals()
    elseif M and type(M.ApplyGameplay) == "function" then
        M.ApplyGameplay()
    end
end

local function ApplyCastbar(reason)
    ApplyGeneral(reason or "MSUF_ASSISTANT_CASTBAR", { castbar = true, preview = true, applyAll = false })
    CallGlobal("MSUF_Castbars_OnSettingsChanged", "assistant")
    CallGlobal("MSUF_UpdateCastbarVisuals")
end

local function ApplyGroup(scope, mode)
    local GP = M and M.GroupPage
    if GP and type(GP.QueueGF) == "function" then
        GP.QueueGF(scope or "party", mode or "visual")
    elseif MSUF and MSUF.GF then
        if mode == "rebuild" and type(MSUF.GF.RebuildAll) == "function" then
            MSUF.GF.RebuildAll()
        elseif type(MSUF.GF.RefreshVisuals) == "function" then
            MSUF.GF.RefreshVisuals()
        end
    end
    if M and type(M.RefreshGFNativePreviews) == "function" then M.RefreshGFNativePreviews() end
end

local function AuraModel()
    local a3 = MSUF and MSUF.MSUF_Auras3
    return (a3 and a3.MenuModel) or _G.MSUF_Auras3_MenuModel
end

function ApplyAura(scope, reason)
    local Model = AuraModel()
    if Model and type(Model.Apply) == "function" then
        Model.Apply(scope or "shared", reason or "MSUF_ASSISTANT_AURAS")
        return
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RequestApply) == "function" then
        a3.RequestApply()
    else
        CallGlobal("MSUF_Auras3_RefreshAll")
    end
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "MSUF_ASSISTANT_AURAS")
end

local function ApplyAuraText(reason)
    CallGlobal("MSUF_A3_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_A3_ForceCooldownTextRecolor")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_TEXT")
    ApplyGroup("party", "visual")
    ApplyGroup("raid", "visual")
    ApplyGroup("mythicraid", "visual")
end

local function EnsureAuraFallbackDB()
    local db = EnsureDB()
    db.auras3 = type(db.auras3) == "table" and db.auras3 or {}
    local auras = db.auras3
    auras.enabled = auras.enabled ~= false
    auras.shared = type(auras.shared) == "table" and auras.shared or {}
    auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
    return auras, auras.shared
end

local AURA_UNIT_FLAGS = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss = "showBoss",
}

local function AuraRuntimeUnit(unit)
    if unit == "boss" or unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5" then return "boss1" end
    if unit == "target" or unit == "focus" then return unit end
    return "player"
end

local function AuraSharedBool(key, defaultValue)
    local Model = AuraModel()
    if Model and type(Model.ReadSharedBool) == "function" then return Model.ReadSharedBool(key, defaultValue) end
    local _, shared = EnsureAuraFallbackDB()
    if shared[key] == nil then return defaultValue and true or false end
    return shared[key] == true
end

local function SetAuraSharedBool(key, value)
    local Model = AuraModel()
    if Model and type(Model.WriteSharedBool) == "function" then
        Model.WriteSharedBool(key, value)
        return
    end
    local _, shared = EnsureAuraFallbackDB()
    shared[key] = value and true or false
end

local function AuraUnitEnabled(unit)
    local Model = AuraModel()
    if Model and type(Model.UnitEnabled) == "function" then return Model.UnitEnabled(unit) end
    local auras = EnsureAuraFallbackDB()
    local flag = AURA_UNIT_FLAGS[unit]
    return auras.enabled == true and flag and auras[flag] == true
end

local function SetAuraUnitEnabled(unit, enabled)
    local Model = AuraModel()
    if Model and type(Model.SetUnitEnabled) == "function" then
        Model.SetUnitEnabled(unit, enabled)
        return
    end
    local auras = EnsureAuraFallbackDB()
    local flag = AURA_UNIT_FLAGS[unit]
    if enabled then auras.enabled = true end
    if flag then auras[flag] = enabled and true or false end
end

local function AuraLaneMaxKey(kind)
    return kind == "buff" and "maxBuffs" or "maxDebuffs"
end

local function AuraLaneSizeKey(kind)
    return kind == "buff" and "buffGroupIconSize" or "debuffGroupIconSize"
end

local function AuraLaneXKey(kind)
    return kind == "buff" and "buffGroupOffsetX" or "debuffGroupOffsetX"
end

local function AuraLaneYKey(kind)
    return kind == "buff" and "buffGroupOffsetY" or "debuffGroupOffsetY"
end

local function AuraLaneDefaultMax(kind)
    return kind == "buff" and 8 or 12
end

local function AuraLaneDefaultY(kind)
    return kind == "buff" and 36 or 6
end

local function AuraReadNumber(scope, key, defaultValue, minValue, maxValue)
    local Model = AuraModel()
    if Model and type(Model.ReadNumber) == "function" then return Model.ReadNumber(scope, key, defaultValue, minValue, maxValue) end
    local _, shared = EnsureAuraFallbackDB()
    return ClampNumber(shared[key] ~= nil and shared[key] or defaultValue, minValue, maxValue, 1) or defaultValue
end

local function AuraWriteNumber(scope, key, value, minValue, maxValue)
    local Model = AuraModel()
    if Model and type(Model.WriteNumber) == "function" then
        Model.WriteNumber(scope, key, value, minValue, maxValue)
        return
    end
    local _, shared = EnsureAuraFallbackDB()
    shared[key] = ClampNumber(value, minValue, maxValue, 1)
end

local function AuraReadLanePerRow(scope, kind)
    local Model = AuraModel()
    if Model and type(Model.ReadLanePerRow) == "function" then return Model.ReadLanePerRow(scope, kind) end
    return AuraReadNumber(scope, kind == "buff" and "buffPerRow" or "debuffPerRow", 12, 1, 40)
end

local function AuraWriteLanePerRow(scope, kind, value)
    local Model = AuraModel()
    if Model and type(Model.WriteLanePerRow) == "function" then
        Model.WriteLanePerRow(scope, kind, value)
        return
    end
    AuraWriteNumber(scope, kind == "buff" and "buffPerRow" or "debuffPerRow", value, 1, 40)
end

local function AuraReadLaneGrowth(scope, kind)
    local Model = AuraModel()
    if Model and type(Model.ReadLaneGrowth) == "function" then return Model.ReadLaneGrowth(scope, kind) end
    local key = kind == "buff" and "buffGrowthX" or "debuffGrowthX"
    local _, shared = EnsureAuraFallbackDB()
    local value = shared[key] or "RIGHT"
    if value == "LEFT" or value == "UP" or value == "DOWN" then return value end
    return "RIGHT"
end

local function AuraWriteLaneGrowth(scope, kind, value)
    if value ~= "LEFT" and value ~= "UP" and value ~= "DOWN" then value = "RIGHT" end
    local Model = AuraModel()
    if Model and type(Model.WriteLaneGrowth) == "function" then
        Model.WriteLaneGrowth(scope, kind, value)
        return
    end
    local _, shared = EnsureAuraFallbackDB()
    shared[kind == "buff" and "buffGrowthX" or "debuffGrowthX"] = value
end

local function AuraReadStackAnchor(scope)
    local Model = AuraModel()
    if Model and type(Model.ReadStackAnchor) == "function" then return Model.ReadStackAnchor(scope) end
    local _, shared = EnsureAuraFallbackDB()
    local value = shared.stackCountAnchor or "TOPRIGHT"
    if value == "TOPLEFT" or value == "BOTTOMRIGHT" or value == "BOTTOMLEFT" then return value end
    return "TOPRIGHT"
end

local function AuraWriteStackAnchor(scope, value)
    if value ~= "TOPLEFT" and value ~= "BOTTOMRIGHT" and value ~= "BOTTOMLEFT" then value = "TOPRIGHT" end
    local Model = AuraModel()
    if Model and type(Model.WriteStackAnchor) == "function" then
        Model.WriteStackAnchor(scope, value)
        return
    end
    local _, shared = EnsureAuraFallbackDB()
    shared.stackCountAnchor = value
end

local function AuraLaneShown(unit, kind)
    local Model = AuraModel()
    if Model and type(Model.GroupShown) == "function" then
        return Model.UnitEnabled(unit) and Model.GroupShown(unit, kind)
    end
    return AuraUnitEnabled(unit) and AuraReadNumber(unit, AuraLaneMaxKey(kind), AuraLaneDefaultMax(kind), 0, 80) > 0
end

local function SetAuraLaneShown(unit, kind, shown)
    local Model = AuraModel()
    if shown then
        SetAuraUnitEnabled(unit, true)
        SetAuraSharedBool(kind == "buff" and "showBuffs" or "showDebuffs", true)
        if Model and type(Model.SetGroupShown) == "function" then
            Model.SetGroupShown(unit, kind, true)
        else
            AuraWriteNumber(unit, AuraLaneMaxKey(kind), AuraLaneDefaultMax(kind), 0, 80)
        end
    else
        if Model and type(Model.SetGroupShown) == "function" then
            Model.SetGroupShown(unit, kind, false)
        else
            AuraWriteNumber(unit, AuraLaneMaxKey(kind), 0, 0, 80)
        end
        if not AuraLaneShown(unit, kind == "buff" and "debuff" or "buff") then
            SetAuraUnitEnabled(unit, false)
        end
    end
end

local function AuraUseSharedVisuals(scope)
    local Model = AuraModel()
    if Model and type(Model.UseSharedVisuals) == "function" then return Model.UseSharedVisuals(scope) end
    local auras = EnsureAuraFallbackDB()
    local pu = auras.perUnit and auras.perUnit[AuraRuntimeUnit(scope)]
    return not (pu and (pu.overrideLayout == true or pu.overrideSharedLayout == true))
end

local function AuraSetUseSharedVisuals(scope, value)
    local Model = AuraModel()
    if Model and type(Model.SetUseSharedVisuals) == "function" then
        Model.SetUseSharedVisuals(scope, value)
        return
    end
    local auras = EnsureAuraFallbackDB()
    local unit = AuraRuntimeUnit(scope)
    auras.perUnit[unit] = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
    auras.perUnit[unit].overrideLayout = not value
    auras.perUnit[unit].overrideSharedLayout = not value
end

local function AuraUseSharedRules(scope)
    local Model = AuraModel()
    if Model and type(Model.UseSharedRules) == "function" then return Model.UseSharedRules(scope) end
    return true
end

local function AuraSetUseSharedRules(scope, value)
    local Model = AuraModel()
    if Model and type(Model.SetUseSharedRules) == "function" then Model.SetUseSharedRules(scope, value) end
end

local function AuraFiltersEnabled(scope)
    local Model = AuraModel()
    if Model and type(Model.ScopeFiltersEnabled) == "function" then return Model.ScopeFiltersEnabled(scope) end
    return true
end

local function AuraSetFiltersEnabled(scope, value)
    local Model = AuraModel()
    if Model and type(Model.SetScopeFiltersEnabled) == "function" then Model.SetScopeFiltersEnabled(scope, value) end
end

local function AuraReadFilter(scope, kind, key, defaultValue)
    local Model = AuraModel()
    if Model and type(Model.ReadFilter) == "function" then return Model.ReadFilter(scope, kind, key, defaultValue) end
    return defaultValue
end

local function AuraWriteFilter(scope, kind, key, value)
    local Model = AuraModel()
    if Model and type(Model.WriteFilter) == "function" then Model.WriteFilter(scope, kind, key, value) end
end

local function GFAurasRoot(scope)
    local conf = GroupDB(scope)
    conf.auras = type(conf.auras) == "table" and conf.auras or {}
    conf.auras.blizzardTypes = type(conf.auras.blizzardTypes) == "table" and conf.auras.blizzardTypes or {}
    conf.auras.buff = type(conf.auras.buff) == "table" and conf.auras.buff or {}
    conf.auras.debuff = type(conf.auras.debuff) == "table" and conf.auras.debuff or {}
    return conf.auras
end

local function GFAuraGroup(scope, lane)
    local root = GFAurasRoot(scope)
    lane = lane == "debuff" and "debuff" or "buff"
    root[lane] = type(root[lane]) == "table" and root[lane] or {}
    return root[lane]
end

local function GFAuraLaneShown(scope, lane)
    lane = lane == "debuff" and "debuff" or "buff"
    local root = GFAurasRoot(scope)
    local nativeKey = lane == "buff" and "buffs" or "debuffs"
    if type(root.blizzardTypes) == "table" and root.blizzardTypes[nativeKey] == true then return true end
    local group = GFAuraGroup(scope, lane)
    return root.enabled ~= false and group.enabled ~= false
end

local function SetGFAuraLaneShown(scope, lane, shown)
    lane = lane == "debuff" and "debuff" or "buff"
    shown = shown and true or false
    local root = GFAurasRoot(scope)
    root.enabled = shown and true or root.enabled
    root.blizzardTypes[lane == "buff" and "buffs" or "debuffs"] = shown
    GFAuraGroup(scope, lane).enabled = shown
end

local function GFReadAuraNumber(scope, lane, key, defaultValue)
    return tonumber(GFAuraGroup(scope, lane)[key]) or defaultValue or 0
end

local function GFWriteAuraNumber(scope, lane, key, value, minValue, maxValue, step)
    GFAuraGroup(scope, lane)[key] = ClampNumber(value, minValue, maxValue, step or 1)
end

local function GFReadAuraValue(scope, lane, key, defaultValue)
    local value = GFAuraGroup(scope, lane)[key]
    if value == nil then return defaultValue end
    return value
end

local function GFWriteAuraValue(scope, lane, key, value)
    GFAuraGroup(scope, lane)[key] = value
end

function Registry:RegisterSetting(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.settingsByKey[spec.key] then return self.settingsByKey[spec.key] end
    spec.aliases = type(spec.aliases) == "table" and spec.aliases or {}
    self.settings[#self.settings + 1] = spec
    self.settingsByKey[spec.key] = spec
    self._findSettingsIndex = nil
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetSetting(key)
    return self.settingsByKey[key]
end

function Registry:AllSettings()
    return self.settings
end

local function AddFindIndex(index, bucket, key, setting)
    key = tostring(key or "")
    if key == "" then return end
    local byKey = index[bucket]
    byKey[key] = byKey[key] or {}
    byKey[key][#byKey[key] + 1] = setting
end

function Registry:BuildFindSettingsIndex()
    local index = {
        byUnit = {},
        byFrameType = {},
        byAttribute = {},
        byType = {},
    }
    for i = 1, #self.settings do
        local setting = self.settings[i]
        AddFindIndex(index, "byUnit", setting.unit, setting)
        AddFindIndex(index, "byFrameType", setting.frameType, setting)
        AddFindIndex(index, "byAttribute", setting.attribute, setting)
        AddFindIndex(index, "byType", setting.type, setting)
    end
    self._findSettingsIndex = index
    self._findSettingsIndexCount = #self.settings
    return index
end

function Registry:FindSettingsCandidateList(filter, unitSet)
    local index = self._findSettingsIndex
    if not index or self._findSettingsIndexCount ~= #self.settings then
        index = self:BuildFindSettingsIndex()
    end
    local best
    local function consider(list)
        if type(list) == "table" and (not best or #list < #best) then best = list end
    end
    if type(filter.unit) == "string" then
        consider(index.byUnit[filter.unit])
    elseif type(filter.units) == "table" and #filter.units == 1 then
        consider(index.byUnit[filter.units[1]])
    end
    if filter.frameType then consider(index.byFrameType[filter.frameType]) end
    if filter.attribute then consider(index.byAttribute[filter.attribute]) end
    if filter.type then consider(index.byType[filter.type]) end
    return best or self.settings
end

function Registry:FindSettings(filter)
    filter = filter or {}
    local out = {}
    local unitSet
    if type(filter.units) == "table" then
        unitSet = {}
        for i = 1, #filter.units do unitSet[filter.units[i]] = true end
    elseif type(filter.unit) == "string" then
        unitSet = { [filter.unit] = true }
    end
    local candidates = self:FindSettingsCandidateList(filter, unitSet)
    for i = 1, #candidates do
        local setting = candidates[i]
        local ok = true
        if unitSet and not unitSet[setting.unit] then ok = false end
        if ok and filter.frameType and setting.frameType ~= filter.frameType then ok = false end
        if ok and filter.attribute and setting.attribute ~= filter.attribute then ok = false end
        if ok and filter.type and setting.type ~= filter.type then ok = false end
        if ok then out[#out + 1] = setting end
    end
    return out
end

function Registry:RegisterAction(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.actionsByKey[spec.key] then return self.actionsByKey[spec.key] end
    spec.aliases = type(spec.aliases) == "table" and spec.aliases or {}
    self.actions[#self.actions + 1] = spec
    self.actionsByKey[spec.key] = spec
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetAction(key)
    return self.actionsByKey[key]
end

function Registry:AllActions()
    return self.actions
end

function Registry:RegisterTodo(text)
    self.todos[#self.todos + 1] = tostring(text or "")
end

function Registry:GetTodos()
    return self.todos
end

local function AddAliasesForUnit(out, unit, noun, nounDE)
    local aliases = UNIT_ALIASES[unit] or { unit }
    for i = 1, #aliases do
        local u = aliases[i]
        out[#out + 1] = u .. " " .. noun
        out[#out + 1] = noun .. " " .. u
        if nounDE then
            out[#out + 1] = u .. " " .. nounDE
            out[#out + 1] = nounDE .. " " .. u
            out[#out + 1] = nounDE .. " vom " .. u
        end
    end
end

local function RegisterUnitBoolean(unit, attr, dbKey, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. dbKey,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = UnitDB(unit)[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            UnitDB(unit)[dbKey] = value and true or false
        end,
        apply = function()
            ApplyUnit(unit, opts.reason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or { preview = true, text = opts.text, power = opts.power, alpha = opts.alpha })
            if opts.refresh then CallGlobal(opts.refresh) end
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterUnitNumber(unit, attr, dbKey, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = unit .. "." .. dbKey,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / " .. (opts.category or "Frame"),
        unit = unit,
        frameType = opts.frameType or "unitframe",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        get = function()
            local value = tonumber(UnitDB(unit)[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            UnitDB(unit)[dbKey] = ClampNumber(value, minValue, maxValue, opts.step or 1)
        end,
        apply = function()
            ApplyUnit(unit, opts.reason or "MSUF_ASSISTANT_UNIT", opts.applyOpts or { preview = true, text = opts.text, power = opts.power, alpha = opts.alpha })
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterGeneralBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = GeneralDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            GeneralDB()[dbKey] = value and true or false
            if dbKey == "showMinimapIcon" then
                local g = GeneralDB()
                g.minimapIconDB = type(g.minimapIconDB) == "table" and g.minimapIconDB or {}
                g.minimapIconDB.hide = not (value and true or false)
            end
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyGeneral(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), opts.applyOpts or { preview = false, applyAll = false })
            end
            if dbKey == "showMinimapIcon" then
                local fn = _G.MSUF_SetMinimapIconEnabled
                if type(fn) == "function" then fn(GeneralDB().showMinimapIcon ~= false) end
            elseif dbKey == "playTargetSelectLostSounds" then
                CallGlobal("MSUF_TargetSoundDriver_ResetState")
                if GeneralDB().playTargetSelectLostSounds == true then CallGlobal("MSUF_TargetSoundDriver_Ensure") end
            elseif dbKey == "hideAdvancedMenu" and M and type(M.RefreshAdvancedNavVisibility) == "function" then
                M.RefreshAdvancedNavVisibility()
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterGeneralNumberSetting(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        percent = opts.percent == true,
        get = function()
            local value = tonumber(GeneralDB()[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            GeneralDB()[dbKey] = ClampNumber(value, minValue, maxValue, opts.step or 1)
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyGeneral(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), opts.applyOpts or { preview = true, applyAll = false })
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterGeneralEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local g = GeneralDB()
            local value = g[dbKey]
            if allowed[value] then return value end
            if dbKey == "barMode" then
                if g.useClassColors == true then return "class" end
                if g.darkMode == true then return "dark" end
            end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            GeneralDB()[dbKey] = value
            if dbKey == "barMode" then
                local g = GeneralDB()
                g.darkMode = value == "dark"
                g.useClassColors = value == "class"
            end
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyGeneral(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), opts.applyOpts or { preview = true, applyAll = false })
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local function RegisterGeneralString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        mediaType = opts.mediaType,
        get = function()
            local value = GeneralDB()[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            if opts.normalizeValue then value = opts.normalizeValue(value) end
            GeneralDB()[dbKey] = tostring(value or "")
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyGeneral(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), opts.applyOpts or { preview = true, applyAll = false })
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterGeneralMappedEnum(dbKey, attr, label, defaultValue, values, storageByValue, aliases, opts)
    opts = opts or {}
    local allowed = {}
    local valueByStorage = {}
    for i = 1, #(values or {}) do
        local value = values[i]
        allowed[value] = true
        valueByStorage[storageByValue[value]] = value
    end
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Global",
        unit = opts.unit or "global",
        frameType = opts.frameType or "global",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local stored = GeneralDB()[dbKey]
            local value = valueByStorage[stored]
            if value then return value end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            GeneralDB()[dbKey] = storageByValue[value]
            if opts.afterSet then opts.afterSet(value, storageByValue[value]) end
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyGeneral(opts.reason or ("MSUF_ASSISTANT_" .. dbKey), opts.applyOpts or { preview = true, applyAll = false })
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterBarsBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = BarsDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            BarsDB()[dbKey] = value and true or false
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyClassPower(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterBarsString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Bars",
        unit = opts.unit or "global",
        frameType = opts.frameType or "globalBars",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        mediaType = opts.mediaType,
        get = function()
            local value = BarsDB()[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            if opts.normalizeValue then value = opts.normalizeValue(value) end
            BarsDB()[dbKey] = tostring(value or "")
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyBars(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterBarsNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        percent = opts.percent == true,
        get = function()
            local value = tonumber(BarsDB()[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            BarsDB()[dbKey] = ClampNumber(value, minValue, maxValue, opts.step or 1)
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyClassPower(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local function RegisterBarsEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "bars." .. dbKey,
        label = label,
        category = opts.category or "Global / Class Resources",
        unit = opts.unit or "global",
        frameType = opts.frameType or "classPower",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local value = BarsDB()[dbKey]
            if value == nil and opts.nilValue then return opts.nilValue end
            if allowed[value] then return value end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            if opts.nilValue and value == opts.nilValue then
                BarsDB()[dbKey] = nil
            else
                BarsDB()[dbKey] = value
            end
        end,
        apply = function()
            if opts.apply then
                opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            else
                ApplyClassPower(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
            end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        requiresReload = opts.requiresReload == true,
        description = opts.description,
    })
end

local function ClassPowerAliases(noun, ...)
    local aliases = {}
    local prefixes = { "class power", "class resource", "class resources", "class bar", "resource bar" }
    for i = 1, #prefixes do aliases[#aliases + 1] = prefixes[i] .. " " .. noun end
    for i = 1, select("#", ...) do aliases[#aliases + 1] = select(i, ...) end
    return aliases
end

local RegisterGameplayBoolean

local GLOBAL_SCOPE_ORDER = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "gf_party", "gf_raid" }
local GLOBAL_SCOPE_META = {
    shared = { label = "Shared", aliases = { "shared", "global", "all" } },
    player = { label = "Player", aliases = { "player", "player frame", "player unitframe" } },
    target = { label = "Target", aliases = { "target", "target frame", "target unitframe" } },
    targettarget = { label = "Target of Target", aliases = { "targettarget", "target of target", "tot" } },
    focustarget = { label = "Focus Target", aliases = { "focustarget", "focus target" } },
    focus = { label = "Focus", aliases = { "focus", "focus frame", "focus unitframe" } },
    pet = { label = "Pet", aliases = { "pet", "pet frame", "pet unitframe" } },
    boss = { label = "Boss", aliases = { "boss", "boss frames", "bossframes" } },
    gf_party = { label = "Party", aliases = { "party", "party frames", "party group", "group frames", "group frame" } },
    gf_raid = { label = "Raid", aliases = { "raid", "raid frames", "mythic raid", "mythicraid", "raid group" } },
}

local function NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.NormalizeScopeKey) == "function" then
        scope = GP.NormalizeScopeKey(scope)
    else
        scope = tostring(scope or "shared"):lower()
        scope = scope:gsub("%s+", "")
        scope = scope:gsub("%-", "_")
        if scope == "party" or scope == "group" or scope == "groupframes" or scope == "gfparty" then scope = "gf_party" end
        if scope == "raid" or scope == "mythic" or scope == "mythicraid" or scope == "gfraid" or scope == "gf_mythicraid" then scope = "gf_raid" end
        if scope == "targetoftarget" or scope == "tot" then scope = "targettarget" end
        if scope == "focustargettarget" or scope == "focus_target" then scope = "focustarget" end
        if scope == "" or scope == "global" or scope == "all" then scope = "shared" end
    end
    if scope == "gf_mythicraid" then scope = "gf_raid" end
    if GLOBAL_SCOPE_META[scope] then return scope end
    return "shared"
end

local function GlobalScopeLabel(scope)
    scope = NormalizeGlobalScope(scope)
    local meta = GLOBAL_SCOPE_META[scope]
    return meta and meta.label or tostring(scope)
end

local function GlobalScopeDBKeys(scope)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeDBKeys) == "function" then
        local keys = GP.ScopeDBKeys(scope)
        if type(keys) == "table" then return keys end
    end
    if scope == "gf_party" then return { "gf_party" } end
    if scope == "gf_raid" then return { "gf_raid", "gf_mythicraid" } end
    if scope ~= "shared" and GLOBAL_SCOPE_META[scope] then return { scope } end
    return nil
end

local function GlobalScopeIsGroup(scope)
    scope = NormalizeGlobalScope(scope)
    return scope == "gf_party" or scope == "gf_raid"
end

local function GlobalScopeHasOverride(scope, flag)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeHasOverride) == "function" then return GP.ScopeHasOverride(scope, flag) and true or false end
    local keys = GlobalScopeDBKeys(scope)
    if not keys then return false end
    local db = EnsureDB()
    for i = 1, #keys do
        local entry = db[keys[i]]
        if type(entry) == "table" and entry[flag] == true then return true end
    end
    return false
end

local function GlobalScopeSetOverride(scope, flag, enabled)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeSetOverride) == "function" then
        GP.ScopeSetOverride(scope, flag, enabled and true or false)
        return
    end
    local keys = GlobalScopeDBKeys(scope)
    if not keys then return end
    local db = EnsureDB()
    for i = 1, #keys do
        local key = keys[i]
        db[key] = type(db[key]) == "table" and db[key] or {}
        db[key][flag] = enabled and true or false
    end
end

local function GlobalScopeRead(scope, flag, sharedTable, key, defaultValue)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeRead) == "function" then return GP.ScopeRead(scope, flag, sharedTable, key, defaultValue) end
    if scope ~= "shared" and GlobalScopeHasOverride(scope, flag) then
        local keys = GlobalScopeDBKeys(scope)
        local db = EnsureDB()
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if type(entry) == "table" and entry[key] ~= nil then return entry[key] end
        end
    end
    local value = sharedTable and sharedTable[key]
    if value == nil then return defaultValue end
    return value
end

local function GlobalScopeWrite(scope, flag, sharedTable, key, value)
    scope = NormalizeGlobalScope(scope)
    local GP = M and M.GlobalPage
    if GP and type(GP.ScopeWrite) == "function" then
        GP.ScopeWrite(scope, flag, sharedTable, key, value)
        return
    end
    if scope == "shared" then
        sharedTable[key] = value
        return
    end
    GlobalScopeSetOverride(scope, flag, true)
    local keys = GlobalScopeDBKeys(scope)
    local db = EnsureDB()
    for i = 1, #(keys or {}) do
        local keyName = keys[i]
        db[keyName] = type(db[keyName]) == "table" and db[keyName] or {}
        db[keyName][key] = value
    end
end

local function GlobalScopeAliases(scope, aliases, suffix)
    scope = NormalizeGlobalScope(scope)
    local out = {}
    local scopeAliases = GLOBAL_SCOPE_META[scope] and GLOBAL_SCOPE_META[scope].aliases or { scope }
    for i = 1, #scopeAliases do
        local scopeName = scopeAliases[i]
        for j = 1, #(aliases or {}) do
            local alias = aliases[j]
            out[#out + 1] = scopeName .. " " .. alias
            out[#out + 1] = alias .. " " .. scopeName
            if suffix then out[#out + 1] = scopeName .. " " .. alias .. " " .. suffix end
        end
    end
    return out
end

local function ScopedSharedTable(kind)
    if kind == "bars" then return BarsDB() end
    if kind == "db" then return EnsureDB() end
    return GeneralDB()
end

local function RegisterScopedSetting(kind, scope, dbKey, attr, label, settingType, defaultValue, aliases, opts)
    opts = opts or {}
    scope = NormalizeGlobalScope(scope)
    local values = opts.values or {}
    local allowed = {}
    for i = 1, #values do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = (opts.keyPrefix or kind) .. "." .. scope .. "." .. dbKey,
        label = GlobalScopeLabel(scope) .. " " .. label,
        category = opts.category or (kind == "fontScope" and "Global / Fonts / Scoped" or "Global / Bars / Scoped"),
        unit = scope,
        frameType = opts.frameType or (kind == "fontScope" and "fonts" or "globalBars"),
        attribute = attr,
        type = settingType,
        aliases = aliases,
        values = opts.values,
        valueAliases = opts.valueAliases,
        min = opts.min,
        max = opts.max,
        step = opts.step or 1,
        percent = opts.percent == true,
        get = function()
            if opts.get then return opts.get(scope) end
            local value = GlobalScopeRead(scope, opts.flag, ScopedSharedTable(opts.shared), dbKey, defaultValue)
            if settingType == "boolean" then
                if value == nil then return defaultValue and true or false end
                return value and true or false
            elseif settingType == "number" then
                return tonumber(value) or defaultValue
            elseif settingType == "enum" then
                if allowed[value] then return value end
                return defaultValue
            elseif settingType == "string" then
                if type(value) ~= "string" or value == "" then return defaultValue or "" end
                return value
            end
            return value
        end,
        set = function(value)
            if opts.set then opts.set(scope, value); return end
            if settingType == "boolean" then
                value = value and true or false
            elseif settingType == "number" then
                value = ClampNumber(value, opts.min, opts.max, opts.step or 1)
            elseif settingType == "enum" then
                if not allowed[value] then value = defaultValue end
            elseif settingType == "string" then
                if opts.normalizeValue then value = opts.normalizeValue(value) end
                value = tostring(value or "")
            end
            GlobalScopeWrite(scope, opts.flag, ScopedSharedTable(opts.shared), dbKey, value)
        end,
        apply = function()
            if opts.apply then opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterScopedMappedEnum(kind, scope, dbKey, attr, label, defaultValue, values, storageByValue, aliases, opts)
    opts = opts or {}
    local valueByStorage = {}
    for i = 1, #(values or {}) do
        local value = values[i]
        valueByStorage[storageByValue[value]] = value
    end
    local rawGet, rawSet = opts.get, opts.set
    opts.values = values
    opts.get = function(scopeKey)
        local stored = rawGet and rawGet(scopeKey) or GlobalScopeRead(scopeKey, opts.flag, ScopedSharedTable(opts.shared), dbKey, storageByValue[defaultValue])
        return valueByStorage[stored] or defaultValue
    end
    opts.set = function(scopeKey, value)
        local stored = storageByValue[value] or storageByValue[defaultValue]
        if rawSet then rawSet(scopeKey, stored) else GlobalScopeWrite(scopeKey, opts.flag, ScopedSharedTable(opts.shared), dbKey, stored) end
    end
    RegisterScopedSetting(kind, scope, dbKey, attr, label, "enum", defaultValue, aliases, opts)
end

function RegisterGameplayBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            GameplayDB()[dbKey] = value and true or false
        end,
        apply = function()
            ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        matchLabel = opts.matchLabel,
        description = opts.description,
    })
end

local function RegisterGameplayNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = opts.step or 1,
        get = function()
            local value = tonumber(GameplayDB()[dbKey])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            value = ClampNumber(value, minValue, maxValue, opts.step or 1)
            if dbKey == "nameplateMeleeSpellID" and M and type(M.SetGameplayMeleeSpellID) == "function" then
                M.SetGameplayMeleeSpellID(value)
                return
            end
            GameplayDB()[dbKey] = value
            if dbKey == "nameplateMeleeSpellID" then
                local g = GameplayDB()
                if g.meleeSpellPerSpec == true then
                    local specID = MSUF and type(MSUF.MSUF_GetPlayerSpecID) == "function" and MSUF.MSUF_GetPlayerSpecID() or nil
                    if specID then
                        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
                        g.nameplateMeleeSpellIDBySpec[specID] = value
                    end
                end
                if g.meleeSpellPerClass == true and UnitClass then
                    local _, class = UnitClass("player")
                    if class then
                        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
                        g.nameplateMeleeSpellIDByClass[class] = value
                    end
                end
            end
        end,
        apply = function()
            ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterGameplayEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    local allowed = {}
    for i = 1, #(values or {}) do allowed[values[i]] = true end
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "enum",
        aliases = aliases,
        values = values,
        valueAliases = opts.valueAliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if allowed[value] then return value end
            return defaultValue
        end,
        set = function(value)
            if not allowed[value] then value = defaultValue end
            GameplayDB()[dbKey] = value
        end,
        apply = function()
            ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function RegisterGameplayString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "gameplay." .. dbKey,
        label = label,
        category = opts.category or "Gameplay",
        unit = opts.unit or "global",
        frameType = opts.frameType or "gameplay",
        attribute = attr,
        type = "string",
        aliases = aliases,
        valuePrefixes = opts.valuePrefixes or aliases,
        get = function()
            local value = GameplayDB()[dbKey]
            if type(value) ~= "string" or value == "" then return defaultValue or "" end
            return value
        end,
        set = function(value)
            GameplayDB()[dbKey] = tostring(value or "")
        end,
        apply = function()
            ApplyGameplay(opts.reason or ("MSUF_ASSISTANT_" .. dbKey))
        end,
        combatSafe = opts.combatSafe == true,
        confirmRequired = opts.confirmRequired == true,
        description = opts.description,
    })
end

local function GameplayAliases(prefix, noun, ...)
    local aliases = {
        prefix .. " " .. noun,
        noun .. " " .. prefix,
    }
    for i = 1, select("#", ...) do aliases[#aliases + 1] = select(i, ...) end
    return aliases
end

local function UnitDefaultPower(unit)
    return not (unit == "pet" or unit == "targettarget" or unit == "focustarget")
end


A.RegistryCore = {
    M = M,
    A = A,
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    UNIT_ALIASES = UNIT_ALIASES,
    floor = floor,
    EnsureDB = EnsureDB,
    UnitDB = UnitDB,
    GeneralDB = GeneralDB,
    BarsDB = BarsDB,
    GameplayDB = GameplayDB,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    CallGlobal = CallGlobal,
    ApplyUnit = ApplyUnit,
    ApplyGeneral = ApplyGeneral,
    ApplyVisuals = ApplyVisuals,
    ApplyColors = ApplyColors,
    ApplyCastbarColors = ApplyCastbarColors,
    ApplyGameplayColors = ApplyGameplayColors,
    ApplyClassPowerColors = ApplyClassPowerColors,
    ApplyAuraColors = ApplyAuraColors,
    ApplyPortraitColors = ApplyPortraitColors,
    ApplyFonts = ApplyFonts,
    ApplyBars = ApplyBars,
    ApplyBarGradients = ApplyBarGradients,
    ApplyBarOutline = ApplyBarOutline,
    ApplyRoundedBars = ApplyRoundedBars,
    ApplyAggroBorder = ApplyAggroBorder,
    ApplyDispelPurgeBorder = ApplyDispelPurgeBorder,
    ApplyBossTargetBorder = ApplyBossTargetBorder,
    ApplyHighlightBorders = ApplyHighlightBorders,
    ApplyAbsorbBars = ApplyAbsorbBars,
    ApplyClassPower = ApplyClassPower,
    ApplyDetachedPowerBar = ApplyDetachedPowerBar,
    ApplyDetachedPowerBarOutline = ApplyDetachedPowerBarOutline,
    ApplyGameplay = ApplyGameplay,
    ApplyCastbar = ApplyCastbar,
    ApplyGroup = ApplyGroup,
    AuraModel = AuraModel,
    ApplyAura = ApplyAura,
    ApplyAuraText = ApplyAuraText,
    EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    AURA_UNIT_FLAGS = AURA_UNIT_FLAGS,
    AuraRuntimeUnit = AuraRuntimeUnit,
    AuraSharedBool = AuraSharedBool,
    SetAuraSharedBool = SetAuraSharedBool,
    AuraUnitEnabled = AuraUnitEnabled,
    SetAuraUnitEnabled = SetAuraUnitEnabled,
    AuraLaneMaxKey = AuraLaneMaxKey,
    AuraLaneSizeKey = AuraLaneSizeKey,
    AuraLaneXKey = AuraLaneXKey,
    AuraLaneYKey = AuraLaneYKey,
    AuraLaneDefaultMax = AuraLaneDefaultMax,
    AuraLaneDefaultY = AuraLaneDefaultY,
    AuraReadNumber = AuraReadNumber,
    AuraWriteNumber = AuraWriteNumber,
    AuraReadLanePerRow = AuraReadLanePerRow,
    AuraWriteLanePerRow = AuraWriteLanePerRow,
    AuraReadLaneGrowth = AuraReadLaneGrowth,
    AuraWriteLaneGrowth = AuraWriteLaneGrowth,
    AuraReadStackAnchor = AuraReadStackAnchor,
    AuraWriteStackAnchor = AuraWriteStackAnchor,
    AuraLaneShown = AuraLaneShown,
    SetAuraLaneShown = SetAuraLaneShown,
    AuraUseSharedVisuals = AuraUseSharedVisuals,
    AuraSetUseSharedVisuals = AuraSetUseSharedVisuals,
    AuraUseSharedRules = AuraUseSharedRules,
    AuraSetUseSharedRules = AuraSetUseSharedRules,
    AuraFiltersEnabled = AuraFiltersEnabled,
    AuraSetFiltersEnabled = AuraSetFiltersEnabled,
    AuraReadFilter = AuraReadFilter,
    AuraWriteFilter = AuraWriteFilter,
    GFAurasRoot = GFAurasRoot,
    GFAuraGroup = GFAuraGroup,
    GFAuraLaneShown = GFAuraLaneShown,
    SetGFAuraLaneShown = SetGFAuraLaneShown,
    GFReadAuraNumber = GFReadAuraNumber,
    GFWriteAuraNumber = GFWriteAuraNumber,
    GFReadAuraValue = GFReadAuraValue,
    GFWriteAuraValue = GFWriteAuraValue,
    AddAliasesForUnit = AddAliasesForUnit,
    RegisterUnitBoolean = RegisterUnitBoolean,
    RegisterUnitNumber = RegisterUnitNumber,
    RegisterGeneralBoolean = RegisterGeneralBoolean,
    RegisterGeneralNumberSetting = RegisterGeneralNumberSetting,
    RegisterGeneralEnum = RegisterGeneralEnum,
    RegisterGeneralString = RegisterGeneralString,
    RegisterGeneralMappedEnum = RegisterGeneralMappedEnum,
    RegisterBarsBoolean = RegisterBarsBoolean,
    RegisterBarsString = RegisterBarsString,
    RegisterBarsNumber = RegisterBarsNumber,
    RegisterBarsEnum = RegisterBarsEnum,
    ClassPowerAliases = ClassPowerAliases,
    RegisterGameplayBoolean = RegisterGameplayBoolean,
    RegisterGameplayNumber = RegisterGameplayNumber,
    RegisterGameplayEnum = RegisterGameplayEnum,
    RegisterGameplayString = RegisterGameplayString,
    GameplayAliases = GameplayAliases,
    UnitDefaultPower = UnitDefaultPower,
    GLOBAL_SCOPE_ORDER = GLOBAL_SCOPE_ORDER,
    GLOBAL_SCOPE_META = GLOBAL_SCOPE_META,
    NormalizeGlobalScope = NormalizeGlobalScope,
    GlobalScopeLabel = GlobalScopeLabel,
    GlobalScopeDBKeys = GlobalScopeDBKeys,
    GlobalScopeIsGroup = GlobalScopeIsGroup,
    GlobalScopeHasOverride = GlobalScopeHasOverride,
    GlobalScopeSetOverride = GlobalScopeSetOverride,
    GlobalScopeRead = GlobalScopeRead,
    GlobalScopeWrite = GlobalScopeWrite,
    GlobalScopeAliases = GlobalScopeAliases,
    ScopedSharedTable = ScopedSharedTable,
    RegisterScopedSetting = RegisterScopedSetting,
    RegisterScopedMappedEnum = RegisterScopedMappedEnum,
}
