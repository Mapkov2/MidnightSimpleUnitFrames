local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors_Context.lua"

-- Advanced Colors page: context-color reference registry.
-- Owns the semantic color targets (bar, health, unit, cast, aura, group,
-- gameplay, power, class power, gradient) that feature pages reference by id,
-- plus M.ResolveContextColorReferences. Split from MSUF_Menu2_AdvancedColors.lua:
-- it loads after that page and its Group and Resources siblings and picks every
-- reader/writer it adapts from M.ColorsPage.
local AP = M.AdvancedPage or {}
local GP = M.GlobalPage or {}
local max = math.max
local min = math.min
local DB, G, Bars, Gameplay = AP.DB, AP.G, AP.Bars, AP.Gameplay
local CurrentBarsScope, NormalizeScopeKey, GradientScopeGet, GradientScopeSet = GP.CurrentBarsScope, GP.NormalizeScopeKey, GP.GradientScopeGet, GP.GradientScopeSet
local CP = M.ColorsPage or {}
M.ColorsPage = CP
local ApplyColors, ApplyUnitframeColorWithReload, ApplyCastbarColors, ApplyBossTargetHighlightColor = CP.ApplyColors, CP.ApplyUnitframeColorWithReload, CP.ApplyCastbarColors, CP.ApplyBossTargetHighlightColor
local ApplyGameplayColors, ApplyAuraColors, ApplyScopedBarGradientColors, ApplyGlobalOutlineColor = CP.ApplyGameplayColors, CP.ApplyAuraColors, CP.ApplyScopedBarGradientColors, CP.ApplyGlobalOutlineColor
local ColorAPI, ApiCall, ApiRGB, ApiSetRGB = CP.ColorAPI, CP.ApiCall, CP.ApiRGB, CP.ApiSetRGB
local GeneralRGB, SetGeneralRGB, GeneralRGBAlias, SetGeneralRGBAlias = CP.GeneralRGB, CP.SetGeneralRGB, CP.GeneralRGBAlias, CP.SetGeneralRGBAlias
local TableRGB, SetTableRGB, HighlightRGB, SetHighlightRGB = CP.TableRGB, CP.SetTableRGB, CP.HighlightRGB, CP.SetHighlightRGB
local COLOR_DATA, ClassColorRGB, SetAllPortraitRGB = CP.COLOR_DATA, CP.ClassColorRGB, CP.SetAllPortraitRGB
local GROUP_COLOR_DB_KEYS, GroupNum, GroupRGB, SetGroupRGB = CP.GROUP_COLOR_DB_KEYS, CP.GroupNum, CP.GroupRGB, CP.SetGroupRGB
local SetGroupRGBA, GroupHealthBarRGB, SetGroupHealthBarRGB = CP.SetGroupRGBA, CP.GroupHealthBarRGB, CP.SetGroupHealthBarRGB
local GetPowerOverrideRGB, SetPowerOverrideRGB, GetClassPowerRGB, SetClassPowerRGB = CP.GetPowerOverrideRGB, CP.SetPowerOverrideRGB, CP.GetClassPowerRGB, CP.SetClassPowerRGB
local GetClassPowerBgRGB, SetClassPowerBgRGB, ClassPowerSlotToken, ClassPowerSlotCount = CP.GetClassPowerBgRGB, CP.SetClassPowerBgRGB, CP.ClassPowerSlotToken, CP.ClassPowerSlotCount
local GetClassPowerSlotMode, SetClassPowerSlotMode, GetClassPowerSlotRGB = CP.GetClassPowerSlotMode, CP.SetClassPowerSlotMode, CP.GetClassPowerSlotRGB
local ClassPowerFullColorToken, ClassPowerFullColorEnabled, SetClassPowerFullColorEnabled, GetClassPowerFullRGB = CP.ClassPowerFullColorToken, CP.ClassPowerFullColorEnabled, CP.SetClassPowerFullColorEnabled, CP.GetClassPowerFullRGB

-- Feature pages reference these semantic ids instead of duplicating Colors
-- storage or apply logic.  Resolution is click-only (see
-- W.AttachContextColorReferences), so this registry adds no combat/idle path
-- and never forces a lazy Advanced Colors category to build.
local function ContextTarget(id, label, getRGB, setRGB, opts)
    opts = opts or {}
    return {
        _msuf2ContextColorId = id,
        label = label,
        getRGB = getRGB,
        setRGB = setRGB,
        isEnabled = opts.isEnabled,
        historyLabel = opts.historyLabel or (label .. " color"),
        hasOpacity = opts.hasOpacity == true,
        getOpacity = opts.getOpacity,
        captureState = opts.captureState,
        restoreState = opts.restoreState,
    }
end
local function ContextCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do copy[ContextCopy(key, seen)] = ContextCopy(item, seen) end
    return copy
end
-- Cancel/restore path only; the live setters below keep this check inline.
local function RunApply(apply)
    if type(apply) == "function" then apply() else ApplyColors() end
end
-- Snapshots the named keys of a table as { key, present, copy } rows, and writes such a snapshot back.
local function CaptureKeys(source, keys)
    local state = {}
    for i = 1, #keys do
        local key = keys[i]
        state[i] = { key, type(source) == "table" and rawget(source, key) ~= nil, type(source) == "table" and ContextCopy(source[key]) }
    end
    return state
end
local function RestoreKeys(target, state)
    for i = 1, #(state or {}) do
        local item = state[i]
        if item[2] then target[item[1]] = ContextCopy(item[3]) else target[item[1]] = nil end
    end
end
local function ContextStoredState(getTable, keys, apply)
    return {
        captureState = function() return CaptureKeys(getTable(), keys) end,
        restoreState = function(state)
            RestoreKeys(getTable(), state)
            if apply ~= false then RunApply(apply) end
        end,
    }
end
local function ContextDBRowsState(rowKeys, keys, apply)
    return {
        captureState = function()
            local db, state = DB(), {}
            for i = 1, #rowKeys do
                local row = db[rowKeys[i]]
                state[i] = { rowKeys[i], type(row) == "table", CaptureKeys(row, keys) }
            end
            return state
        end,
        restoreState = function(state)
            local db = DB()
            for i = 1, #(state or {}) do
                local rowState = state[i]
                local row = db[rowState[1]]
                if type(row) ~= "table" then
                    row = {}
                    db[rowState[1]] = row
                end
                RestoreKeys(row, rowState[3])
                if rowState[2] ~= true and next(row) == nil then db[rowState[1]] = nil end
            end
            if apply ~= false then RunApply(apply) end
        end,
    }
end
-- A state provider is also a valid ContextTarget opts table (captureState/restoreState);
-- this installs one on a target a helper already built.
local function ContextWithState(target, state)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
-- The picker's colour wheel sends no opacity (a is nil). The stored opacity stays
-- then; the default only fills in a colour that never had one.
local function StoredColorAlpha(getName, prefix, dr, dg, db, default)
    local _, _, _, apiAlpha = ApiRGB(getName, dr, dg, db)
    local _, _, _, storedAlpha = GeneralRGB(prefix, dr, dg, db)
    return tonumber(apiAlpha) or storedAlpha or default
end
local function ContextStoredApi(id, label, getName, setName, prefix, dr, dg, db, da, apply, applyAfterSet)
    local keys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    if da ~= nil then keys[#keys + 1] = prefix .. "A" end
    local target = ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            local alpha = type(a) == "number" and a or StoredColorAlpha(getName, prefix, dr, dg, db, da)
            local ok = ApiSetRGB(setName, r, g, b, alpha)
            if not ok then SetGeneralRGB(prefix, r, g, b, alpha) end
            if not ok or applyAfterSet == true then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
    if da ~= nil then
        target.hasOpacity = true
        target.getOpacity = function()
            local _, _, _, a = ApiRGB(getName, dr, dg, db)
            return tonumber(a) or da
        end
    end
    return ContextWithState(target, ContextStoredState(G, keys, apply))
end
local function ContextStoredApiScopedOpacity(id, label, getName, setName, prefix,
        dr, dg, db, da, opacityKey, opacityDefault, opacityReason)
    local scope = type(CurrentBarsScope) == "function" and CurrentBarsScope() or "shared"
    local generalState = ContextStoredState(G, {
        prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A", opacityKey,
    }, false)
    local scopedState
    local globalPage = M.GlobalPage or {}
    if scope ~= "shared" and type(globalPage.ScopeDBKeys) == "function" then
        scopedState = ContextDBRowsState(globalPage.ScopeDBKeys(scope) or {}, { opacityKey, "hlOverride" }, false)
    end
    local target = ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            if type(a) == "number" and type(globalPage.BarScopeSet) == "function" then
                globalPage.BarScopeSet(opacityKey, a, opacityReason)
                return
            end
            local _, _, _, legacyAlpha = ApiRGB(getName, dr, dg, db)
            local ok = ApiSetRGB(setName, r, g, b, tonumber(legacyAlpha) or da)
            if not ok then SetGeneralRGB(prefix, r, g, b, tonumber(legacyAlpha) or da) end
            ApplyColors()
        end,
        { hasOpacity = true })
    target.getOpacity = function()
        local fallback = tonumber(G()[opacityKey]) or opacityDefault
        if type(globalPage.BarScopeGet) == "function" then return tonumber(globalPage.BarScopeGet(opacityKey, fallback)) or fallback end
        return fallback
    end
    target.captureState = function()
        return {
            general = generalState.captureState(),
            scoped = scopedState and scopedState.captureState() or nil,
        }
    end
    target.restoreState = function(state)
        if not state then return end
        generalState.restoreState(state.general)
        if scopedState then scopedState.restoreState(state.scoped) end
        ApplyColors()
    end
    return target
end
local function ContextApi(id, label, getName, setName, dr, dg, db, apply)
    return ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            if not ApiSetRGB(setName, r, g, b, a) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
end
local function ContextApiOrGeneral(id, label, getName, setName, prefix, dr, dg, db, apply, alpha)
    return ContextTarget(id, label,
        function()
            local api = ColorAPI()
            if type(api[getName]) == "function" then return ApiRGB(getName, dr, dg, db) end
            return GeneralRGB(prefix, dr, dg, db)
        end,
        function(r, g, b, a)
            local nextAlpha = type(a) == "number" and a or StoredColorAlpha(getName, prefix, dr, dg, db, alpha)
            local ok = nextAlpha ~= nil and ApiCall(setName, r, g, b, nextAlpha) or ApiCall(setName, r, g, b)
            if not ok then
                SetGeneralRGB(prefix, r, g, b, nextAlpha)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
end
local function ContextGeneral(id, label, prefix, dr, dg, db, apply)
    return ContextTarget(id, label,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, b, a)
            SetGeneralRGB(prefix, r, g, b, a)
            if type(apply) == "function" then apply() else ApplyColors() end
        end,
        ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A" }, apply))
end
local function ContextTable(id, label, getTable, key, dr, dg, db, apply, opts)
    local target = ContextTarget(id, label,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, b)
            SetTableRGB(getTable(), key, r, g, b)
            if type(apply) == "function" then apply() end
        end,
        opts)
    if target.captureState then return target end
    return ContextWithState(target, ContextStoredState(getTable, { key }, apply))
end
local function ContextGroup(id, label, prefix, dr, dg, db, alphaKey, defaultAlpha)
    local target = ContextTarget(id, label,
        function() return GroupRGB(prefix, dr, dg, db) end,
        function(r, g, b, a)
            if alphaKey then SetGroupRGBA(prefix, alphaKey, r, g, b, a, "MSUF2_GROUP_COLORS", "visual")
            else SetGroupRGB(prefix, r, g, b, "MSUF2_GROUP_COLORS", "visual") end
        end)
    local stateKeys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    if alphaKey then stateKeys[#stateKeys + 1] = alphaKey end
    ContextWithState(target, ContextDBRowsState(GROUP_COLOR_DB_KEYS, stateKeys, ApplyColors))
    if alphaKey then
        target.hasOpacity = true
        target.getOpacity = function() return GroupNum(alphaKey, defaultAlpha or 1) end
    end
    return target
end
local function ContextValue(value, context)
    if type(value) == "function" then return value(context) end
    return value
end
local function ContextUnit(context)
    local unit = ContextValue(context and context.unit, context)
    return type(unit) == "string" and unit ~= "" and unit or "player"
end
local function ContextPreviewUnitData(unit)
    local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
    local data = model and model.UNIT_DATA
    return data and data[unit] or nil
end
local function ContextUnitExists(unit)
    return type(UnitExists) ~= "function" or UnitExists(unit) == true
end
local function ContextIsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end
local function ContextUnitClassToken(unit)
    if type(UnitClass) ~= "function" then return nil end
    local _, token = UnitClass(unit)
    return token
end
local function ContextPlainUnitValue(api, unit)
    if type(api) ~= "function" then return nil end
    local value = api(unit)
    if ContextIsSecret(value) then return nil end
    return value
end
local function ContextPowerToken(context)
    local token = ContextValue(context and context.powerToken, context)
    if type(token) ~= "string" or token == "" then
        local unit = ContextUnit(context)
        if ContextUnitExists(unit) and type(UnitPowerType) == "function" then
            local _, powerToken = UnitPowerType(unit)
            token = powerToken
        end
    end
    if type(token) ~= "string" or token == "" then
        local preview = ContextPreviewUnitData(ContextUnit(context))
        token = preview and preview.powerToken or nil
    end
    return type(token) == "string" and token ~= "" and token or "MANA"
end
local function ContextClassPowerToken(context)
    local token = ContextValue(context and context.resourceToken, context)
    if type(token) ~= "string" or token == "" then
        local spec = type(M.GetClassPowerPreviewSpec) == "function" and M.GetClassPowerPreviewSpec()
        token = type(spec) == "table" and spec.token or nil
    end
    return type(token) == "string" and token ~= "" and token or (M.colorsCPToken or "COMBO_POINTS")
end
local function ContextClassToken(context)
    local token = ContextValue(context and context.classToken, context)
    if type(token) ~= "string" or token == "" then
        token = ContextUnitClassToken(ContextUnit(context))
    end
    if type(token) ~= "string" or token == "" then
        local preview = ContextPreviewUnitData(ContextUnit(context))
        token = preview and preview.class or nil
    end
    if type(token) ~= "string" or token == "" then
        token = ContextUnitClassToken("player")
    end
    return type(token) == "string" and token ~= "" and token or "WARRIOR"
end
local CONTEXT_COLOR_FACTORIES
local function ContextReactionKind(context)
    local kind = ContextValue(context and context.reaction, context)
    if kind == "friendly" or kind == "neutral" or kind == "enemy" or kind == "dead" then return kind end
    local unit = ContextUnit(context)
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit) then return "dead" end
    local reaction = type(UnitReaction) == "function" and tonumber(UnitReaction(unit, "player")) or nil
    if reaction and reaction >= 5 then return "friendly" end
    if reaction == 4 then return "neutral" end
    local preview = ContextPreviewUnitData(unit)
    local previewKind = preview and (preview.npcKind or preview.reactionKind)
    if type(previewKind) == "string" and previewKind ~= "" then return previewKind end
    return "enemy"
end
local function ContextClassColor(context)
    local token = ContextClassToken(context)
    local state = ContextStoredState(DB, { "classColors" }, ApplyUnitframeColorWithReload)
    state.historyLabel = "Class color"
    return ContextTarget("unit.class.current", (COLOR_DATA.CLASS_LABELS[token] or token) .. " class color",
        function() return ClassColorRGB(token) end,
        function(r, g, b)
            if ApiCall("SetClassColor", token, r, g, b) then
                M.RefreshActiveHealthBackgroundInlinePreview()
            else
                ApplyUnitframeColorWithReload()
            end
        end,
        state)
end
local NPC_CONTEXT_DEFAULTS = {
    friendly = { 0, 1, 0 }, neutral = { 1, 1, 0 }, enemy = { 0.85, 0.10, 0.10 }, dead = { 0.40, 0.40, 0.40 },
    npcBoss = { 0.74, 0.11, 0 }, npcMiniboss = { 0.56, 0, 0.74 }, npcCaster = { 0, 0.45, 0.74 },
    npcMelee = { 0.99, 0.99, 0.99 }, npcRegular = { 0.70, 0.56, 0.33 },
}
local NPC_CONTEXT_LABELS = {
    friendly = "Friendly NPC", neutral = "Neutral NPC", enemy = "Enemy NPC", dead = "Dead NPC",
    npcBoss = "Boss NPC", npcMiniboss = "Miniboss / Lieutenant", npcCaster = "Caster NPC",
    npcMelee = "Melee NPC", npcRegular = "Regular NPC",
}
local function ContextNPCColor(kind)
    local defaults = NPC_CONTEXT_DEFAULTS[kind] or NPC_CONTEXT_DEFAULTS.enemy
    return ContextTarget("unit.npc." .. tostring(kind), (NPC_CONTEXT_LABELS[kind] or tostring(kind)) .. " color",
        function() return ApiRGB("GetNPCColor", defaults[1], defaults[2], defaults[3], kind) end,
        function(r, g, b)
            if not ApiCall("SetNPCColor", kind, r, g, b) then ApplyUnitframeColorWithReload() end
        end,
        ContextStoredState(DB, { "npcColors" }, ApplyUnitframeColorWithReload))
end
local function ContextGlobalHealthMode()
    local general = G()
    local mode = general.barMode
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
        mode = general.useClassColors and "class" or "dark"
    end
    if mode == "gradient" and general.enableHealthGradient == false then mode = "class" end
    return mode
end
local CONTEXT_HEALTH_MODES = { GRADIENT = "gradient", UNIFIED = "unified", CLASS = "class" }
local function ContextHealthMode(context)
    local mode = ContextValue(context and context.healthMode, context)
    if mode == nil then
        local conf = DB()[ContextUnit(context)]
        mode = type(conf) == "table" and conf.healthColorMode or nil
    end
    mode = type(mode) == "string" and mode or "GLOBAL"
    local upper = mode:upper()
    if upper == "GLOBAL" or upper == "" then return ContextGlobalHealthMode() end
    return CONTEXT_HEALTH_MODES[upper] or "dark"
end
local function ContextUnitKey(context)
    local key = ContextValue(context and context.unitKey, context)
    if type(key) == "string" and key ~= "" then return key end
    local unit = ContextUnit(context)
    if unit:match("^boss%d+$") then return "boss" end
    if unit:match("^arena%d+$") then return "arena" end
    return unit
end
-- UFBarTextCommon.UnitNPCKind with the NPC-type switches of the General settings, for a
-- bar ("health") or a text ("text") consumer.
local function ContextNPCKind(unit, key, exists, section, colorKey, forText)
    local common = MSUF and MSUF.UFBarTextCommon
    if not (exists and common and type(common.UnitNPCKind) == "function") then return nil end
    local general = G()
    return common.UnitNPCKind(nil, unit, { key = key, [section] = {
        npcColorMode = general.npcColorMode == "type" and "type" or "reaction",
        [colorKey] = general[colorKey] ~= false,
        npcTypeTarget = general.npcTypeTarget ~= false,
        npcTypeFocus = general.npcTypeFocus ~= false,
        npcTypeBoss = general.npcTypeBoss ~= false,
        npcTypeToT = general.npcTypeToT ~= false,
    } }, forText, key)
end
local function ContextNPCHealthTarget(context)
    local unit, key, general = ContextUnit(context), ContextUnitKey(context), G()
    local exists = ContextUnitExists(unit)
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    if preview and preview.isPlayer == true and type(preview.class) == "string" and preview.class ~= "" then
        return ContextClassColor({ unit = unit, classToken = preview.class })
    end
    if general.npcClassColorBar == true and key ~= "pet" and key ~= "boss" then
        local reaction = type(UnitReaction) == "function" and UnitReaction(unit, "player") or nil
        if not ContextIsSecret(reaction) and tonumber(reaction) and tonumber(reaction) >= 5 then
            local token = ContextUnitClassToken(unit)
            if not ContextIsSecret(token) and type(token) == "string" and token ~= "" then
                return ContextClassColor({ unit = unit, classToken = token })
            end
        end
    end

    local kind = ContextNPCKind(unit, key, exists, "health", "npcTypeColorBar", false)
    if type(kind) ~= "string" then
        preview = preview or ContextPreviewUnitData(unit)
        kind = preview and (preview.npcKind or preview.reactionKind) or nil
    end
    return ContextNPCColor(type(kind) == "string" and kind or ContextReactionKind(context))
end

local function ContextNameColorFlags(key)
    local general, conf = G(), DB()[key]
    local classColor = general.nameClassColor == true
    local npcColor = general.npcNameRed == true
    local npcClassColor = general.nameNpcClassColor == true
    if type(conf) == "table" and conf.fontOverride == true then
        if conf.nameClassColor ~= nil then classColor = conf.nameClassColor == true end
        if conf.npcNameRed ~= nil then npcColor = conf.npcNameRed == true end
        if conf.nameNpcClassColor ~= nil then npcClassColor = conf.nameNpcClassColor == true end
    end
    -- ResolveToTInline intentionally inherits the Target frame's NPC-type text
    -- switch for TARGET_NAME, TOT_NAME and AUTO.
    local targetTypeColor = general.npcColorMode == "type" and general.npcTypeColorText ~= false
    return classColor, npcColor or targetTypeColor, npcClassColor
end

local function ContextTextNPCKind(unit, key)
    local kind = ContextNPCKind(unit, key, ContextUnitExists(unit), "text", "npcTypeColorText", true)
    if type(kind) ~= "string" then
        local preview = ContextPreviewUnitData(unit)
        kind = preview and (preview.npcKind or preview.reactionKind) or nil
    end
    return type(kind) == "string" and kind or ContextReactionKind({ unit = unit })
end

local function ContextNameEntityTarget(unit, key, classColor, npcColor, npcClassColor, npcKey)
    local exists = ContextUnitExists(unit)
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    local isPlayer = exists and ContextPlainUnitValue(UnitIsPlayer, unit) or (preview and preview.isPlayer)
    local classToken
    if exists then
        classToken = ContextUnitClassToken(unit)
        if ContextIsSecret(classToken) then classToken = nil end
    elseif preview then
        classToken = preview.class
    end
    if isPlayer == true then
        if classColor and type(classToken) == "string" and classToken ~= "" then
            return ContextClassColor({ unit = unit, classToken = classToken })
        end
        return CONTEXT_COLOR_FACTORIES["font.global"]()
    end
    if npcClassColor and type(classToken) == "string" and classToken ~= "" then
        return ContextClassColor({ unit = unit, classToken = classToken })
    end
    if npcColor or npcClassColor then return ContextNPCColor(ContextTextNPCKind(unit, npcKey or key)) end
    return CONTEXT_COLOR_FACTORIES["font.global"]()
end

CONTEXT_COLOR_FACTORIES = {}
local function ContextFactory(id, builder) CONTEXT_COLOR_FACTORIES[id] = builder end
local function FixedContextFactory(id, builder) ContextFactory(id, function() return builder() end) end

-- Plain General-row colors: id, label, General prefix, default r g b, apply.
local GENERAL_CONTEXT_COLORS = {
    { "bar.heal_prediction", "Heal prediction", "healPredictionColor", 0, 1, 0, ApplyColors },
    { "bar.health_loss", "Health loss glow", "healthLossColor", 1, 0.55, 0.08, ApplyColors },
    { "bar.power_loss", "Power loss glow", "powerLossColor", 0.70, 0.90, 1, ApplyColors },
    { "bar.outline", "Bar outline", "barOutlineColor", 0, 0, 0, ApplyGlobalOutlineColor },
    { "health.unified", "Unified health bar", "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload },
    { "health.gradient.low", "Health gradient - low", "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload },
    { "health.gradient.mid", "Health gradient - middle", "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload },
    { "health.gradient.high", "Health gradient - high", "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload },
}
local function TableFactory(id, label, getTable, key, dr, dg, db, apply, opts)
    FixedContextFactory(id, function() return ContextTable(id, label, getTable, key, dr, dg, db, apply, opts) end)
end
local function GroupFactory(id, label, prefix, dr, dg, db, alphaKey, defaultAlpha)
    FixedContextFactory(id, function() return ContextGroup(id, label, prefix, dr, dg, db, alphaKey, defaultAlpha) end)
end
-- Registration is grouped by color family; the groups run in the original
-- registration order so CONTEXT_COLOR_FACTORIES ends up with the same keys.
local function RegisterBarContextFactories()
    local function GradientTargets()
        return {
            CONTEXT_COLOR_FACTORIES["health.gradient.low"](),
            CONTEXT_COLOR_FACTORIES["health.gradient.mid"](),
            CONTEXT_COLOR_FACTORIES["health.gradient.high"](),
        }
    end
    for _, row in ipairs(GENERAL_CONTEXT_COLORS) do
        FixedContextFactory(row[1], function() return ContextGeneral(row[1], row[2], row[3], row[4], row[5], row[6], row[7]) end)
    end
    FixedContextFactory("bar.absorb", function()
        return ContextStoredApiScopedOpacity("bar.absorb", "Absorb", "GetAbsorbOverlayColor", "SetAbsorbOverlayColor",
            "absorbBarColor", 1, 1, 1, 0.45, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY")
    end)
    FixedContextFactory("bar.heal_absorb", function()
        return ContextStoredApiScopedOpacity("bar.heal_absorb", "Heal absorb", "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor",
            "healAbsorbBarColor", 0.7, 0, 0, 0.45, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY")
    end)
    FixedContextFactory("bar.power_background", function()
        return ContextStoredApi("bar.power_background", "Power background", "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", "powerBarBgColor", 0, 0,
            0, 1, ApplyColors, true)
    end)
    FixedContextFactory("bar.aggro_border", function()
        return ContextWithState(ContextApi("bar.aggro_border", "Aggro border", "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0),
            ContextStoredState(G, {
                "hlAggroColorR", "hlAggroColorG", "hlAggroColorB",
                "aggroBorderColorR", "aggroBorderColorG", "aggroBorderColorB",
                "aggroBorderR", "aggroBorderG", "aggroBorderB",
            }, ApplyColors))
    end)
    FixedContextFactory("bar.purge_border", function()
        return ContextTarget("bar.purge_border", "Purge border",
            function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0) end,
            function(r, g, b) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, b) end,
            ContextStoredState(G, {
                "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
                "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB",
            }, ApplyColors))
    end)
    FixedContextFactory("bar.background_tint", function()
        return ContextStoredApi("bar.background_tint", "Bar background tint", "GetClassBarBgColor", "SetClassBarBgColor", "classBarBg", 0, 0, 0, 1,
            ApplyUnitframeColorWithReload, true)
    end)
    ContextFactory("health.background.current", function(context)
        local mode = M.ColorsBackgroundMode.GetColor()
        if mode == "health_gradient" then return GradientTargets() end
        if mode ~= "custom" then return nil end
        local id = context and context.group == true and "group.background" or "bar.background_tint"
        local factory = CONTEXT_COLOR_FACTORIES[id]
        return type(factory) == "function" and factory(context) or nil
    end)
    ContextFactory("health.current", function(context)
        local mode = ContextHealthMode(context)
        if mode == "gradient" then return GradientTargets() end
        if mode == "unified" then return CONTEXT_COLOR_FACTORIES["health.unified"]() end
        if mode == "class" then
            local unit, key = ContextUnit(context), ContextUnitKey(context)
            if key == "pet" then return CONTEXT_COLOR_FACTORIES["unit.pet"]() end
            local exists = ContextUnitExists(unit)
            local isPlayer = exists and ContextPlainUnitValue(UnitIsPlayer, unit) or nil
            if not exists then
                local preview = ContextPreviewUnitData(unit)
                if preview and preview.isPlayer == true then
                    return ContextClassColor({ unit = unit, classToken = preview.class })
                end
                return ContextNPCHealthTarget(context)
            end
            if isPlayer == false then return ContextNPCHealthTarget(context) end
            return ContextClassColor(context)
        end
        return nil
    end)
end
-- Colors the Colors page stores on the General row and on every unit row at once.
local ALL_UNIT_COLOR_ROWS = { "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }
local function AllRowsColorTarget(id, label, key, dr, dg, db, setRGB, apply)
    return ContextTarget(id, label,
        function() return GeneralRGB(key, dr, dg, db) end,
        setRGB,
        ContextDBRowsState(ALL_UNIT_COLOR_ROWS, { key .. "R", key .. "G", key .. "B" }, apply))
end
local function RegisterUnitContextFactories()
    ContextFactory("unit.class.current", ContextClassColor)
    ContextFactory("unit.npc.current", function(context) return ContextNPCColor(ContextReactionKind(context)) end)
    for _, kind in ipairs({ "friendly", "neutral", "enemy", "dead", "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }) do
        ContextFactory("unit.npc." .. kind, function() return ContextNPCColor(kind) end)
    end
    FixedContextFactory("unit.pet", function()
        local target = ContextWithState(
            ContextApi("unit.pet", "Pet frame", "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload),
            ContextStoredState(G, { "petFrameColorR", "petFrameColorG", "petFrameColorB" }, ApplyUnitframeColorWithReload))
        local setRGB = target.setRGB
        target.setRGB = function(r, g, b) setRGB(r, g, b); ApplyUnitframeColorWithReload() end
        return target
    end)
    FixedContextFactory("highlight.mouseover", function()
        return ContextTarget("highlight.mouseover", "Mouseover highlight", HighlightRGB, SetHighlightRGB,
            ContextStoredState(G, { "highlightColor" }, ApplyColors))
    end)
    TableFactory("highlight.boss_target", "Boss target highlight", G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
    FixedContextFactory("portrait.border", function()
        return AllRowsColorTarget("portrait.border", "Portrait border", "portraitBorderColor", 1, 1, 1,
            function(r, g, b) SetAllPortraitRGB("portraitBorderColor", r, g, b) end, ApplyColors)
    end)
    FixedContextFactory("portrait.background", function()
        return AllRowsColorTarget("portrait.background", "Portrait background", "portraitBgColor", 0.05, 0.05, 0.05,
            function(r, g, b) SetAllPortraitRGB("portraitBgColor", r, g, b) end, ApplyColors)
    end)
    for _, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", label = "Texture layer" },
        { id = "texture_layer2", prefix = "texLayer2", label = "Texture layer 2" },
        { id = "texture_layer3", prefix = "texLayer3", label = "Texture layer 3" },
    }) do
        local slotId, slotPrefix, slotLabel = texSlot.id, texSlot.prefix, texSlot.label
        FixedContextFactory(slotId .. ".color", function()
            return AllRowsColorTarget(slotId .. ".color", slotLabel, slotPrefix .. "Color", 1, 1, 1,
                function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Color", r, g, b) end, M._ApplyTextureLayerColors)
        end)
        FixedContextFactory(slotId .. ".gradient", function()
            return AllRowsColorTarget(slotId .. ".gradient", M.Format("%s gradient end", M.Tr(slotLabel)), slotPrefix .. "Gradient2", 0, 0, 0,
                function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Gradient2", r, g, b) end, M._ApplyTextureLayerColors)
        end)
    end
    FixedContextFactory("font.global", function()
        return ContextTarget("font.global", "Default font", M._ContextConfiguredGlobalFontRGB,
            function(r, g, b)
                if not ApiSetRGB("SetGlobalFontColor", r, g, b) then
                    local general = G()
                    general.useCustomFontColor = true
                    general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = r, g, b
                    ApplyColors()
                end
            end,
            ContextStoredState(G, { "useCustomFontColor", "fontColorCustomR", "fontColorCustomG", "fontColorCustomB" }, ApplyColors))
    end)
    ContextFactory("font.default.current", function(context)
        local globalPage = M.GlobalPage or {}
        local scope = ContextValue(context and context.scope, context) or "shared"
        if type(globalPage.NormalizeScopeKey) == "function" then scope = globalPage.NormalizeScopeKey(scope) end
        local localColor = type(globalPage.IsGFScope) == "function" and globalPage.IsGFScope(scope) == true
            and type(globalPage.FontOverrideGetFor) == "function" and globalPage.FontOverrideGetFor(scope) == true
            and type(globalPage.FontScopeGetFor) == "function"
            and globalPage.FontScopeGetFor(scope, "useGlobalFontColor", true) == false
        if not localColor then return CONTEXT_COLOR_FACTORIES["font.global"]() end

        local target = ContextTarget("font.default." .. tostring(scope), "Group font color",
            function()
                return tonumber(globalPage.FontScopeGetFor(scope, "fontR", 1)) or 1,
                    tonumber(globalPage.FontScopeGetFor(scope, "fontG", 1)) or 1,
                    tonumber(globalPage.FontScopeGetFor(scope, "fontB", 1)) or 1
            end,
            function(r, g, b)
                globalPage.FontScopeSetFor(scope, "fontR", r, nil, nil, true)
                globalPage.FontScopeSetFor(scope, "fontG", g, nil, nil, true)
                globalPage.FontScopeSetFor(scope, "fontB", b, nil, nil, true)
                globalPage.FontScopeSetFor(scope, "useGlobalFontColor", false, nil, nil, true)
                if type(globalPage.ApplyFontsFor) == "function" then
                    globalPage.ApplyFontsFor(scope, "MSUF2_CONTEXT_GROUP_FONT_COLOR")
                else
                    ApplyColors()
                end
            end)
        local state = ContextDBRowsState(
            type(globalPage.ScopeDBKeys) == "function" and (globalPage.ScopeDBKeys(scope) or {}) or {},
            { "fontOverride", "fontR", "fontG", "fontB", "useGlobalFontColor" }, false)
        target.captureState = state.captureState
        target.restoreState = function(saved)
            state.restoreState(saved)
            if type(globalPage.ApplyFontsFor) == "function" then
                globalPage.ApplyFontsFor(scope, "MSUF2_CONTEXT_GROUP_FONT_RESTORE")
            else
                ApplyColors()
            end
        end
        return target
    end)
    ContextFactory("text.inline_tot.current", function()
        local conf = DB().targettarget or DB().tot or {}
        local mode = tostring(conf.totInlineColorMode or "AUTO"):upper()
        if mode == "DEFAULT" then return CONTEXT_COLOR_FACTORIES["font.global"]() end
        if mode == "NPC" then
            local unit = "targettarget"
            local exists = ContextUnitExists(unit)
            local preview = not exists and ContextPreviewUnitData(unit) or nil
            local isPlayer = exists and ContextPlainUnitValue(UnitIsPlayer, unit) or (preview and preview.isPlayer)
            if isPlayer ~= false then return CONTEXT_COLOR_FACTORIES["font.global"]() end
            return ContextNPCColor(ContextTextNPCKind(unit, "targettarget"))
        end

        local unit, key
        if mode == "TARGET_NAME" then
            unit, key = "target", "target"
        else
            -- AUTO deliberately applies Target-name rules to the ToT entity;
            -- TOT_NAME instead uses the Target-of-Target frame's own name rules.
            unit, key = "targettarget", mode == "TOT_NAME" and "targettarget" or "target"
        end
        local classColor, npcColor, npcClassColor = ContextNameColorFlags(key)
        return ContextNameEntityTarget(unit, key, classColor, npcColor, npcClassColor,
            unit == "targettarget" and "targettarget" or key)
    end)
end
local CAST_DETAIL_PREFIX = {
    player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast", arena = "arenaCast",
}
local function RegisterCastContextFactories()
    -- A Get/Set API color with the stored keys its snapshot restores.
    local function CastFactory(id, label, getName, setName, dr, dg, db, keys)
        FixedContextFactory(id, function()
            return ContextWithState(ContextApi(id, label, getName, setName, dr, dg, db, ApplyCastbarColors),
                ContextStoredState(G, keys, ApplyCastbarColors))
        end)
    end
    local function CastColorKeys(prefix) return { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "Color" } end
    CastFactory("cast.interruptible", "Interruptible cast", "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8,
        CastColorKeys("castbarInterruptible"))
    CastFactory("cast.non_interruptible", "Non-interruptible cast", "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01,
        CastColorKeys("castbarNonInterruptible"))
    CastFactory("cast.interrupt_feedback", "Interrupt feedback", "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1, 0.82, 0,
        CastColorKeys("castbarInterruptFeedback"))
    CastFactory("cast.interrupt_unavailable", "Interrupt unavailable", "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor",
        1, 0.494117647, 0.137254902, CastColorKeys("castbarInterruptUnavailable"))
    CastFactory("cast.text", "Cast text", "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1,
        { "castbarFontR", "castbarFontG", "castbarFontB" })
    CastFactory("cast.target_text", "Cast target text", "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1,
        { "castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB" })
    CastFactory("cast.player_override", "Player cast override", "GetPlayerCastbarOverrideColor", "SetPlayerCastbarOverrideColor", 0, 0.6, 1,
        { "playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB" })
    -- Castbar border/background: an API color that falls back to General, with an opacity.
    local function CastBackdropFactory(id, label, getName, setName, prefix, dr, dg, db, alpha)
        FixedContextFactory(id, function()
            local target = ContextApiOrGeneral(id, label, getName, setName, prefix, dr, dg, db, ApplyCastbarColors, alpha)
            target.hasOpacity, target.getOpacity = true, function()
                local _, _, _, a = ApiRGB(getName, dr, dg, db)
                return tonumber(a) or alpha
            end
            return ContextWithState(target,
                ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A" }, ApplyCastbarColors))
        end)
    end
    CastBackdropFactory("cast.border", "Castbar border", "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, 1)
    CastBackdropFactory("cast.background", "Castbar background", "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg",
        0.10, 0.10, 0.10, 0.85)
    TableFactory("cast.kick_ready", "Kick ready", G, "kickReadyColor", 0, 1, 0, ApplyCastbarColors)
    TableFactory("cast.kick_not_ready", "Kick not ready", G, "kickNotReadyColor", 1, 0, 0, ApplyCastbarColors)
    -- Per-castbar detail text colors. A detail with no complete stored triple is
    -- still following the shared castbar color, so the factory hands back that
    -- shared target instead of a swatch whose first click would quietly create an
    -- override nobody asked for. The unit-prefix table is also the native Cancel
    -- snapshot owner; context readers keep their existing exported API route.
    local function CastDetailContextTarget(context, detail, label, sharedId)
        local unit = ContextUnit(context)
        local prefix = CAST_DETAIL_PREFIX[unit]
        if not prefix then return CONTEXT_COLOR_FACTORIES[sharedId]() end
        local read = MSUF.Require("MSUF_GetCastbarDetailTextColor", FILE)
        local write = MSUF.Require("MSUF_SetCastbarDetailTextColor", FILE)
        local _, _, _, custom = read(unit, detail)
        if custom ~= true then return CONTEXT_COLOR_FACTORIES[sharedId]() end
        local key = prefix .. detail .. "Color"
        return ContextTarget("cast.detail." .. unit .. "." .. detail, label,
            function()
                local r, g, b = read(unit, detail)
                return r, g, b
            end,
            function(r, g, b)
                write(unit, detail, r, g, b)
                ApplyCastbarColors()
            end,
            ContextStoredState(G, { key .. "R", key .. "G", key .. "B" }, ApplyCastbarColors))
    end
    for _, row in ipairs({
        { "cast.spell_text.current", "SpellName", "Cast spell text", "cast.text" },
        { "cast.time_text.current", "Time", "Cast time text", "cast.text" },
        { "cast.target_text.current", "TargetName", "Cast target text", "cast.target_text" },
    }) do
        ContextFactory(row[1], function(context) return CastDetailContextTarget(context, row[2], row[3], row[4]) end)
    end
    -- Status text indicators (level/race/class/raid group and the Dead, Ghost, AFK
    -- and DND states). An unset indicator follows the frame's font color, so it
    -- resolves to the shared font target for the same reason as the castbar
    -- details above.
    ContextFactory("status.text.current", function(context)
        local unit = ContextUnit(context)
        local prefix = ContextValue(context and context.colorPrefix, context)
        local conf = type(prefix) == "string" and prefix ~= "" and DB()[unit] or nil
        if not conf then return CONTEXT_COLOR_FACTORIES["font.global"]() end
        return ContextTarget("status.text." .. unit .. "." .. prefix,
            ContextValue(context and context.colorLabel, context) or "Status text",
            function()
                local r = tonumber(conf[prefix .. "ColorR"])
                local g = tonumber(conf[prefix .. "ColorG"])
                local b = tonumber(conf[prefix .. "ColorB"])
                if r and g and b then return r, g, b end
                return M._ContextConfiguredGlobalFontRGB()
            end,
            function(r, g, b)
                conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = r, g, b
                M.RequestGeneralDomains("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false, colors = true, colorScope = unit })
            end,
            ContextStoredState(function() return conf end,
                { prefix .. "ColorR", prefix .. "ColorG", prefix .. "ColorB" },
                function() M.RequestGeneralDomains("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false, colors = true, colorScope = unit }) end))
    end)
    -- Level difficulty palette. Global bands shared by every unit and group
    -- level text, so the ::: on a Level Text card edits the same five colors as
    -- Colors > Status Text Colors. Rows and defaults come from the Colors page
    -- table so the two surfaces cannot drift.
    local levelReferences = {}
    for i = 1, #(M._levelDifficultyColor or {}) do
        local row = M._levelDifficultyColor[i]
        FixedContextFactory(row[6], function()
            return ContextGeneral(row[6], row[2], row[1], row[3], row[4], row[5], ApplyColors)
        end)
        levelReferences[i] = row[6]
    end
    M._levelDifficultyColorReferences = levelReferences
    -- Threat % colors: the three global curve colors of Colors > Status Text Colors,
    -- listed by the ::: on a Threat % card while it colors itself by threat.
    local threatReferences = {}
    for i = 1, #(M._threatCurveColor or {}) do
        local row = M._threatCurveColor[i]
        FixedContextFactory(row[6], function()
            return ContextGeneral(row[6], row[2], row[1], row[3], row[4], row[5], M._ApplyThreatCurveColors)
        end)
        threatReferences[i] = row[6]
    end
    M._threatCurveColorReferences = threatReferences
end
local function RegisterAuraContextFactories()
    local function ContextDispelType(id, dispelType)
        return ContextTarget(id, dispelType .. " dispel",
            function() return M._GetDispelTypeRGB(dispelType, true) end,
            function(r, g, b) M._SetDispelTypeRGB(dispelType, r, g, b) end,
            ContextStoredState(G, { "dispelTypeColorOverrides" }, function()
                M._SetDispelColorPreviewType(dispelType)
                ApplyAuraColors()
            end))
    end
    FixedContextFactory("aura.cooldown.safe", function()
        return ContextTarget("aura.cooldown.safe", "Cooldown safe", M._ContextGetAuraSafeRGB, M._ContextSetAuraSafeRGB,
            ContextStoredState(G, { "aurasCooldownTextSafeColor" }, ApplyAuraColors))
    end)
    TableFactory("aura.cooldown.warning", "Cooldown warning", G, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, ApplyAuraColors)
    TableFactory("aura.cooldown.urgent", "Cooldown urgent", G, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, ApplyAuraColors)
    for _, dispelType in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
        local id = "aura.dispel." .. dispelType:lower()
        FixedContextFactory(id, function() return ContextDispelType(id, dispelType) end)
    end
end
local function RegisterGroupContextFactories()
    local GROUP_HEALTH_KEYS = {
        "gfDarkR", "gfDarkG", "gfDarkB", "gfUnifiedR", "gfUnifiedG", "gfUnifiedB",
        "healthCustomR", "healthCustomG", "healthCustomB",
    }
    FixedContextFactory("group.healer_mana_text", function()
        local state = ContextDBRowsState(GROUP_COLOR_DB_KEYS,
            { "healerManaTextR", "healerManaTextG", "healerManaTextB" }, CP.ApplyHealerManaText)
        state.historyLabel = "Text color"
        return ContextTarget("group.healer_mana_text", "Text color", CP.HealerManaTextRGB, CP.SetHealerManaTextRGB, state)
    end)
    ContextFactory("group.health", function(context)
        local scope = ContextValue(context and context.scope, context)
        if scope == "party" or scope == "raid" or scope == "mythicraid" then scope = "gf_" .. scope end
        if scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid" then
            local function Conf() return DB()[scope] or {} end
            local function Prefix()
                local mode = Conf().gfBarMode
                if mode == "dark" then return "gfDark", 0, 0, 0 end
                if mode == "unified" then return "gfUnified", .10, .60, .90 end
                return "healthCustom", .20, .80, .20
            end
            return ContextTarget("group.health." .. scope, "Group health bar",
                function()
                    local conf = Conf()
                    local prefix, r, g, b = Prefix()
                    return tonumber(conf[prefix .. "R"]) or r, tonumber(conf[prefix .. "G"]) or g,
                        tonumber(conf[prefix .. "B"]) or b
                end,
                function(r, g, b)
                    local conf, prefix = Conf(), Prefix()
                    conf[prefix .. "R"], conf[prefix .. "G"], conf[prefix .. "B"] = r, g, b
                    ApplyColors()
                end,
                ContextStoredState(Conf, GROUP_HEALTH_KEYS, ApplyColors))
        end
        return ContextTarget("group.health", "Group health bar", GroupHealthBarRGB, SetGroupHealthBarRGB,
            ContextDBRowsState(GROUP_COLOR_DB_KEYS, GROUP_HEALTH_KEYS, ApplyColors))
    end)
    GroupFactory("group.background", "Group bar background", "bg", 0.10, 0.10, 0.10)
    GroupFactory("group.dead", "Dead / offline background", "deadBg", 0.60, 0.05, 0.05, "deadBgA", 0.90)
    GroupFactory("group.debuff_stripe", "Debuff stripe", "debuffStripeColor", 0.80, 0.20, 0.20, "debuffStripeAlpha", 0.60)
    GroupFactory("group.target", "Target highlight", "target", 1, 1, 1)
    GroupFactory("group.focus", "Focus highlight", "hlFocusColor", 0.50, 0.50, 1)
    GroupFactory("group.border", "Group border", "groupBorder", 0.38, 0.68, 1, "groupBorderA", 0.95)
    GroupFactory("group.aggro", "Corner aggro", "ciAggroColor", 1, 0.55, 0)
    GroupFactory("group.portrait.border", "Party portrait border", "portraitBorderColor", 1, 1, 1, "portraitBorderColorA", 1)
end
local function RegisterGameplayContextFactories()
    TableFactory("gameplay.timer", "Combat timer", Gameplay, "combatTimerColor", 1, 1, 1, ApplyGameplayColors)
    FixedContextFactory("gameplay.enter", function()
        return ContextTarget("gameplay.enter", "Combat enter",
            function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
            function(r, g, b)
                local gameplay = Gameplay()
                SetTableRGB(gameplay, "combatStateEnterColor", r, g, b)
                if gameplay.combatStateColorSync then SetTableRGB(gameplay, "combatStateLeaveColor", r, g, b) end
                ApplyGameplayColors()
            end,
            ContextStoredState(Gameplay, { "combatStateEnterColor", "combatStateLeaveColor" }, ApplyGameplayColors))
    end)
    TableFactory("gameplay.leave", "Combat leave", Gameplay, "combatStateLeaveColor", 0.7, 0.7, 0.7, ApplyGameplayColors, {
        isEnabled = function() return Gameplay().combatStateColorSync ~= true end,
    })
    TableFactory("gameplay.crosshair_in", "Crosshair in range", Gameplay, "crosshairInRangeColor", 0, 1, 0, ApplyGameplayColors)
    TableFactory("gameplay.crosshair_out", "Crosshair out of range", Gameplay, "crosshairOutRangeColor", 1, 0, 0, ApplyGameplayColors)
end
local function RegisterPowerContextFactories()
    local function PowerTokenTarget(id, token, label)
        return ContextTarget(id, label,
            function() return GetPowerOverrideRGB(token) end,
            function(r, g, b) SetPowerOverrideRGB(token, r, g, b) end,
            ContextStoredState(G, { "powerColorOverrides" }, ApplyColors))
    end
    ContextFactory("power.current", function(context)
        local token = ContextPowerToken(context)
        local target = PowerTokenTarget("power.current." .. token, token, (token:gsub("_", " ")) .. " power")
        target.getColorByClass = M.PowerBarColorByClass.Get
        target.setColorByClass = M.PowerBarColorByClass.Set
        return ContextWithState(target,
            ContextStoredState(G, { "powerColorOverrides", "powerColorMode", "powerBarColorMode" }, ApplyColors))
    end)
    -- The unit's own power bar border colour. Unset, the border follows the frame
    -- outline colour (CompileUnitPower), so the picker starts from that colour.
    local POWER_BORDER_KEYS = { "powerBarBorderColorR", "powerBarBorderColorG", "powerBarBorderColorB" }
    local POWER_BORDER_APPLY = { power = true, preview = true }
    ContextFactory("power.border", function(context)
        local unitKey = ContextUnitKey(context)
        local function Conf()
            local db = DB()
            db[unitKey] = db[unitKey] or {}
            return db[unitKey]
        end
        local function Apply() M.RequestUnitDomains(unitKey, "MSUF2_POWER_BORDER_COLOR", POWER_BORDER_APPLY) end
        local function Channel(conf, general, suffix)
            local own = tonumber(conf["powerBarBorderColor" .. suffix])
            if own then return own end
            local outline = conf.hlOverride == true and conf["barOutlineColor" .. suffix]
            if outline == nil or outline == false then outline = general["barOutlineColor" .. suffix] end
            if outline == nil then outline = general["barBorder" .. suffix] end
            return tonumber(outline) or 0
        end
        return ContextTarget("power.border." .. unitKey, "Power bar border",
            function()
                local conf, general = Conf(), G()
                return Channel(conf, general, "R"), Channel(conf, general, "G"), Channel(conf, general, "B")
            end,
            function(r, g, b)
                local conf = Conf()
                conf.powerBarBorderColorR, conf.powerBarBorderColorG, conf.powerBarBorderColorB = r, g, b
                Apply()
            end,
            ContextDBRowsState({ unitKey }, POWER_BORDER_KEYS, Apply))
    end)
    -- A single unit has one resource, so "power.current" resolves it from context.
    -- A party or raid roster mixes every resource type at once, so group cards name
    -- each color instead: one "power.token.<token>" id per power the Colors page
    -- lists (COLOR_POWER_TOKENS, MSUF_Menu2_AdvancedColors), with its label. Each
    -- entry edits the same shared override table.
    local powerTokens = CP.COLOR_POWER_TOKENS or {}
    for i = 1, #powerTokens do
        local token, label = powerTokens[i].value, powerTokens[i].text
        local id = "power.token." .. token:lower()
        ContextFactory(id, function() return PowerTokenTarget(id, token, label) end)
    end
    ContextFactory("class_power.current", function(context)
        local token = ContextClassPowerToken(context)
        local spec = type(M.GetClassPowerPreviewSpec) == "function" and M.GetClassPowerPreviewSpec() or nil
        local slot = max(1, min(ClassPowerSlotCount(token), tonumber(ContextValue(context and context.slot, context)) or tonumber(spec and spec.value) or 1))
        local generalState = ContextStoredState(G, { "classPowerColorOverrides", "classPowerBgColorOverrides" }, false)
        local barsState = ContextStoredState(Bars, { "classPowerSlotColorModes", "classPowerComboPointColorMode", "classPowerFullColorEnabled" }, false)
        local function CaptureClassPowerState()
            return { generalState.captureState(), barsState.captureState() }
        end
        local function RestoreClassPowerState(state)
            generalState.restoreState(state and state[1])
            barsState.restoreState(state and state[2])
            CP.ApplyClassPowerColors()
        end
        local function ClassPowerTarget(id, label, getRGB, setRGB)
            return ContextTarget(id, label, getRGB, setRGB, {
                captureState = CaptureClassPowerState,
                restoreState = RestoreClassPowerState,
            })
        end
        local targets = {
            ClassPowerTarget("class_power.foreground." .. token, token:gsub("_", " ") .. " foreground",
                function() return GetClassPowerRGB(token) end,
                function(r, g, b) SetClassPowerRGB(token, r, g, b) end),
            ClassPowerTarget("class_power.background." .. token, token:gsub("_", " ") .. " background",
                function() return GetClassPowerBgRGB(token) end,
                function(r, g, b) SetClassPowerBgRGB(token, r, g, b) end),
        }
        if ClassPowerSlotCount(token) > 0 and ContextValue(context and context.includeSlots, context) ~= false then
            targets[#targets + 1] = ClassPowerTarget("class_power.full." .. token, token:gsub("_", " ") .. " full",
                function() return GetClassPowerFullRGB(token) end,
                function(r, g, b)
                    if not ClassPowerFullColorEnabled(token) then SetClassPowerFullColorEnabled(token, true) end
                    SetClassPowerRGB(ClassPowerFullColorToken(token), r, g, b)
                end)
            targets[#targets + 1] = ClassPowerTarget("class_power.slot." .. token .. "." .. tostring(slot), token:gsub("_", " ") .. " slot " .. tostring(slot),
                function() return GetClassPowerSlotRGB(token, slot) end,
                function(r, g, b)
                    if GetClassPowerSlotMode(token) ~= "custom" then SetClassPowerSlotMode(token, "custom") end
                    SetClassPowerRGB(ClassPowerSlotToken(token, slot), r, g, b)
                end)
        end
        return targets
    end)
    local function ClassPowerOverrideFactory(id, label, token)
        FixedContextFactory(id, function()
            return ContextTarget(id, label,
                function() return GetClassPowerRGB(token) end,
                function(r, g, b) SetClassPowerRGB(token, r, g, b) end,
                ContextStoredState(G, { "classPowerColorOverrides" }, ApplyColors))
        end)
    end
    ClassPowerOverrideFactory("class_power.text", "Class resource text", "RESOURCE_TEXT")
    ClassPowerOverrideFactory("class_power.alt_mana", "Alternative mana", "MANA")
end
local function RegisterGradientContextFactories()
    local function ContextGradientFactory(id, label, prefix, reason)
        FixedContextFactory(id, function()
            local scope = type(CurrentBarsScope) == "function" and CurrentBarsScope() or "shared"
            if type(NormalizeScopeKey) == "function" then scope = NormalizeScopeKey(scope) end
            local rows
            if scope == "gf_raid" then rows = { "gf_raid", "gf_mythicraid" }
            elseif scope == "shared" or type(scope) ~= "string" or scope == "" then rows = { "general" }
            else rows = { scope } end
            return ContextTarget(id, label,
                function()
                    return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
                        tonumber(GradientScopeGet(prefix .. "G", 0)) or 0,
                        tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
                end,
                function(r, g, b)
                    GradientScopeSet(prefix .. "R", r)
                    GradientScopeSet(prefix .. "G", g)
                    GradientScopeSet(prefix .. "B", b)
                    ApplyScopedBarGradientColors(reason)
                end,
                ContextDBRowsState(rows, {
                    prefix .. "R", prefix .. "G", prefix .. "B", "hlOverride", "gradientOverride",
                    "gradientOverrideVersion", "gradientOverrideKeys",
                }, function() ApplyScopedBarGradientColors(reason) end))
        end)
    end
    ContextGradientFactory("gradient.health", "Health bar gradient", "healthBarGradientColor", "MSUF2_HP_GRADIENT_COLOR")
    ContextGradientFactory("gradient.power", "Power bar gradient", "powerBarGradientColor", "MSUF2_POWER_GRADIENT_COLOR")
end
RegisterBarContextFactories()
RegisterUnitContextFactories()
RegisterCastContextFactories()
RegisterAuraContextFactories()
RegisterGroupContextFactories()
RegisterGameplayContextFactories()
RegisterPowerContextFactories()
RegisterGradientContextFactories()

local function AppendContextTargets(out, seen, value, reference)
    if type(value) ~= "table" then return end
    if type(value.getRGB) == "function" and type(value.setRGB) == "function" then
        if type(reference) == "table" and type(reference.label) == "string" then value.label = reference.label end
        local identity = value._msuf2ContextColorId or value
        if not seen[identity] then
            seen[identity] = true
            out[#out + 1] = value
        end
        return
    end
    for i = 1, #value do AppendContextTargets(out, seen, value[i], reference) end
end
function M.ResolveContextColorReferences(references, context)
    references = ContextValue(references, context)
    context = type(context) == "table" and context or {}
    if type(references) == "string" then references = { references } end
    if type(references) ~= "table" then return {} end
    local targets, seen = {}, {}
    for i = 1, #references do
        local reference = ContextValue(references[i], context)
        local id = type(reference) == "table" and reference.id or reference
        local enabled = type(reference) ~= "table" or type(reference.when) ~= "function" or reference.when(context) ~= false
        local factory = enabled and CONTEXT_COLOR_FACTORIES[id] or nil
        if type(factory) == "function" then AppendContextTargets(targets, seen, factory(context, reference), reference) end
    end
    return targets
end
M.ContextColorReferenceFactories = CONTEXT_COLOR_FACTORIES

-- Native Cast colors use existing exact-presence providers; unit details freeze
-- the selected family's raw keys instead of borrowing an inherited shared target.
local function NativeColorId(path) return M.ControlMeta("opt_colors", "advanced", path).controlId end
local NATIVE_CAST_COLOR_STATES, NATIVE_CAST_DETAIL_STATES = {}, {}
for path, reference in pairs({
    ["api.SetInterruptibleCastColor"] = "cast.interruptible",
    ["api.SetNonInterruptibleCastColor"] = "cast.non_interruptible",
    ["api.SetInterruptFeedbackCastColor"] = "cast.interrupt_feedback",
    ["api.SetCastbarTextColor"] = "cast.text",
    ["api.SetCastbarTargetNameColor"] = "cast.target_text",
    ["general.castbarBorder"] = "cast.border",
    ["general.castbarBg"] = "cast.background",
    ["castbar.player_override.custom_color"] = "cast.player_override",
    ["table.kickReadyColor"] = "cast.kick_ready",
    ["table.kickNotReadyColor"] = "cast.kick_not_ready",
    ["api.SetInterruptUnavailableCastColor"] = "cast.interrupt_unavailable",
}) do
    NATIVE_CAST_COLOR_STATES[NativeColorId(path)] = reference
end
for path, suffix in pairs({
    ["castbar.text_color.spell_name"] = "SpellName",
    ["castbar.text_color.time"] = "Time",
    ["castbar.text_color.target_name"] = "TargetName",
}) do
    NATIVE_CAST_DETAIL_STATES[NativeColorId(path)] = suffix
end
-- Native resource owners share the existing exact-presence context snapshot.
local NATIVE_CLASS_POWER_COLOR_STATES = {}
for _, path in ipairs({
    "class_power.editor.foreground_color", "class_power.editor.background_color", "class_power.full_resource.color",
}) do
    NATIVE_CLASS_POWER_COLOR_STATES[NativeColorId(path)] = 0
end
for slot = 1, 10 do
    NATIVE_CLASS_POWER_COLOR_STATES[NativeColorId("class_power.resource_slots.slot." .. tostring(slot))] = slot
end
local NATIVE_CLASS_POWER_SELECTOR = NativeColorId("class_power.editor.resource_selector")
local NATIVE_CAST_DETAIL_SELECTOR = NativeColorId("castbar.text_color.unit")
local function NativeSelectorValue(controlId, missing)
    return assert(M.RuntimeControlCatalog.Get(controlId), missing).widget._msuf2CommandAction.get()
end
local function CaptureNativeCastDetailState(suffix)
    local unit = NativeSelectorValue(NATIVE_CAST_DETAIL_SELECTOR, "native cast detail selector missing")
    local key = assert(CAST_DETAIL_PREFIX[unit], "native cast detail family missing") .. suffix .. "Color"
    local provider = ContextStoredState(G, { key .. "R", key .. "G", key .. "B" }, ApplyCastbarColors)
    return { provider.restoreState, provider.captureState() }
end
local function CaptureNativeClassPowerState(slot)
    local token = NativeSelectorValue(NATIVE_CLASS_POWER_SELECTOR, "native class power selector missing")
    assert(type(token) == "string" and token ~= "", "native class power token missing")
    local provider = assert(M.ResolveContextColorReferences("class_power.current",
        { resourceToken = token, slot = slot })[1], "native class power state missing")
    return { provider.restoreState, provider.captureState() }
end
function CP.AttachNativeCastColorState(color, metadata)
    local id = metadata and metadata.controlId
    local reference, suffix = NATIVE_CAST_COLOR_STATES[id], NATIVE_CAST_DETAIL_STATES[id]
    local slot = NATIVE_CLASS_POWER_COLOR_STATES[id]
    if not reference and not suffix and slot == nil then return color end
    local state = reference and assert(M.ResolveContextColorReferences(reference)[1], "native cast color state missing")
    color._msuf2CaptureColorState = function()
        if state then return { state.restoreState, state.captureState() } end
        if suffix then return CaptureNativeCastDetailState(suffix) end
        return CaptureNativeClassPowerState(slot)
    end
    color._msuf2RestoreColorState = function(self, captured)
        captured[1](captured[2])
        local r, g, b = self._msuf2CommandAction.get()
        self._msuf2ColorHasOpacity = self._msuf2GetColorOpacity() ~= nil
        self:SetRGB(r or 1, g or 1, b or 1)
    end
    return color
end
