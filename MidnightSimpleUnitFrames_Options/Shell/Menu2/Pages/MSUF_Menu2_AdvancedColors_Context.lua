local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

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
local COLOR_DATA, ClassDefaultRGB, ClassColorRGB, SetAllPortraitRGB = CP.COLOR_DATA, CP.ClassDefaultRGB, CP.ClassColorRGB, CP.SetAllPortraitRGB
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
local function ContextStoredState(getTable, keys, apply)
    return {
        captureState = function()
            local source, state = getTable(), {}
            for i = 1, #keys do
                local key = keys[i]
                state[i] = { key, rawget(source, key) ~= nil, ContextCopy(source[key]) }
            end
            return state
        end,
        restoreState = function(state)
            local target = getTable()
            for i = 1, #(state or {}) do
                local item = state[i]
                target[item[1]] = item[2] and ContextCopy(item[3]) or nil
            end
            if apply ~= false then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
    }
end
local function ContextDBRowsState(rowKeys, keys, apply)
    return {
        captureState = function()
            local db, state = DB(), {}
            for i = 1, #rowKeys do
                local rowKey, row = rowKeys[i], db[rowKeys[i]]
                state[i] = { rowKey, type(row) == "table", {} }
                for j = 1, #keys do
                    local key = keys[j]
                    state[i][3][j] = { key, type(row) == "table" and rawget(row, key) ~= nil, type(row) == "table" and ContextCopy(row[key]) or nil }
                end
            end
            return state
        end,
        restoreState = function(state)
            local db = DB()
            for i = 1, #(state or {}) do
                local rowState = state[i]
                local row = db[rowState[1]]
                if type(row) ~= "table" then row = {}; db[rowState[1]] = row end
                for j = 1, #(rowState[3] or {}) do
                    local item = rowState[3][j]
                    row[item[1]] = item[2] and ContextCopy(item[3]) or nil
                end
                if rowState[2] ~= true and next(row) == nil then db[rowState[1]] = nil end
            end
            if apply ~= false then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
    }
end
local function ContextStoredApi(id, label, getName, setName, prefix, dr, dg, db, da, apply, applyAfterSet)
    local keys = { prefix .. "R", prefix .. "G", prefix .. "B" }
    if da ~= nil then keys[#keys + 1] = prefix .. "A" end
    local target = ContextTarget(id, label,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, b, a)
            local ok = ApiSetRGB(setName, r, g, b, type(a) == "number" and a or da)
            if not ok then SetGeneralRGB(prefix, r, g, b, type(a) == "number" and a or da) end
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
    local state = ContextStoredState(G, keys, apply)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
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
            local nextAlpha = type(a) == "number" and a or alpha
            local ok = nextAlpha ~= nil and ApiCall(setName, r, g, b, nextAlpha) or ApiCall(setName, r, g, b)
            if not ok then
                SetGeneralRGB(prefix, r, g, b, nextAlpha)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end)
end
local function ContextGeneral(id, label, prefix, dr, dg, db, apply)
    local target = ContextTarget(id, label,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, b, a)
            SetGeneralRGB(prefix, r, g, b, a)
            if type(apply) == "function" then apply() else ApplyColors() end
        end)
    local state = ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "A" }, apply)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
end
local function ContextTable(id, label, getTable, key, dr, dg, db, apply, opts)
    local target = ContextTarget(id, label,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, b)
            SetTableRGB(getTable(), key, r, g, b)
            if type(apply) == "function" then apply() end
        end,
        opts)
    if not target.captureState then
        local state = ContextStoredState(getTable, { key }, apply)
        target.captureState, target.restoreState = state.captureState, state.restoreState
    end
    return target
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
    local state = ContextDBRowsState(GROUP_COLOR_DB_KEYS, stateKeys, ApplyColors)
    target.captureState, target.restoreState = state.captureState, state.restoreState
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
local function ContextPlainUnitValue(api, unit)
    if type(api) ~= "function" then return nil end
    local value = api(unit)
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(value) == true then return nil end
    return value
end
local function ContextPowerToken(context)
    local token = ContextValue(context and context.powerToken, context)
    if type(token) ~= "string" or token == "" then
        local unit = ContextUnit(context)
        local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
        if exists and type(_G.UnitPowerType) == "function" then
            local _, powerToken = _G.UnitPowerType(unit)
            token = powerToken
        end
    end
    if type(token) ~= "string" or token == "" then
        local model = MSUF and MSUF.UFPreview and MSUF.UFPreview.Model
        local data = model and model.UNIT_DATA
        local preview = data and data[ContextUnit(context)]
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
        if type(_G.UnitClass) == "function" then
            local _, classToken = _G.UnitClass(ContextUnit(context))
            token = classToken
        end
    end
    if type(token) ~= "string" or token == "" then
        local preview = ContextPreviewUnitData(ContextUnit(context))
        token = preview and preview.class or nil
    end
    if (type(token) ~= "string" or token == "") and type(_G.UnitClass) == "function" then
        local _, playerClass = _G.UnitClass("player")
        token = playerClass
    end
    return type(token) == "string" and token ~= "" and token or "WARRIOR"
end
local CONTEXT_COLOR_FACTORIES
local function ContextReactionKind(context)
    local kind = ContextValue(context and context.reaction, context)
    if kind == "friendly" or kind == "neutral" or kind == "enemy" or kind == "dead" then return kind end
    local unit = ContextUnit(context)
    if type(_G.UnitIsDeadOrGhost) == "function" and _G.UnitIsDeadOrGhost(unit) then return "dead" end
    local reaction = type(_G.UnitReaction) == "function" and tonumber(_G.UnitReaction(unit, "player")) or nil
    if reaction and reaction >= 5 then return "friendly" end
    if reaction == 4 then return "neutral" end
    local preview = ContextPreviewUnitData(unit)
    local previewKind = preview and (preview.npcKind or preview.reactionKind)
    if type(previewKind) == "string" and previewKind ~= "" then return previewKind end
    return "enemy"
end
local function ContextClassColor(context)
    local token = ContextClassToken(context)
    local dr, dg, db = ClassDefaultRGB(token)
    local target = ContextTarget("unit.class.current", (COLOR_DATA.CLASS_LABELS[token] or token) .. " class color",
        function() return ClassColorRGB(token) end,
        function(r, g, b)
            if ApiCall("SetClassColor", token, r, g, b) then
                M.RefreshActiveHealthBackgroundInlinePreview()
            else
                ApplyUnitframeColorWithReload()
            end
        end,
        { historyLabel = "Class color" })
    local state = ContextStoredState(DB, { "classColors" }, ApplyUnitframeColorWithReload)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
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
    local target = ContextTarget("unit.npc." .. tostring(kind), (NPC_CONTEXT_LABELS[kind] or tostring(kind)) .. " color",
        function() return ApiRGB("GetNPCColor", defaults[1], defaults[2], defaults[3], kind) end,
        function(r, g, b)
            if not ApiCall("SetNPCColor", kind, r, g, b) then ApplyUnitframeColorWithReload() end
        end)
    local state = ContextStoredState(DB, { "npcColors" }, ApplyUnitframeColorWithReload)
    target.captureState, target.restoreState = state.captureState, state.restoreState
    return target
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
local function ContextHealthMode(context)
    local mode = ContextValue(context and context.healthMode, context)
    if mode == nil then
        local conf = DB()[ContextUnit(context)]
        mode = type(conf) == "table" and conf.healthColorMode or nil
    end
    mode = type(mode) == "string" and mode or "GLOBAL"
    local upper = mode:upper()
    if upper == "GLOBAL" or upper == "" then return ContextGlobalHealthMode() end
    if upper == "GRADIENT" then return "gradient" end
    if upper == "UNIFIED" then return "unified" end
    if upper == "CLASS" then return "class" end
    return "dark"
end
local function ContextUnitKey(context)
    local key = ContextValue(context and context.unitKey, context)
    if type(key) == "string" and key ~= "" then return key end
    local unit = ContextUnit(context)
    if unit:match("^boss%d+$") then return "boss" end
    return unit
end
local function ContextNPCHealthTarget(context)
    local unit, key, general = ContextUnit(context), ContextUnitKey(context), G()
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    if preview and preview.isPlayer == true and type(preview.class) == "string" and preview.class ~= "" then
        return ContextClassColor({ unit = unit, classToken = preview.class })
    end
    if general.npcClassColorBar == true and key ~= "pet" and key ~= "boss" then
        local reaction = type(_G.UnitReaction) == "function" and _G.UnitReaction(unit, "player") or nil
        local secret = type(_G.issecretvalue) == "function" and _G.issecretvalue(reaction) == true
        if not secret and tonumber(reaction) and tonumber(reaction) >= 5 and type(_G.UnitClass) == "function" then
            local _, token = _G.UnitClass(unit)
            if type(_G.issecretvalue) ~= "function" or _G.issecretvalue(token) ~= true then
                if type(token) == "string" and token ~= "" then
                    return ContextClassColor({ unit = unit, classToken = token })
                end
            end
        end
    end

    local kind
    local common = MSUF and MSUF.UFBarTextCommon
    if exists and common and type(common.UnitNPCKind) == "function" then
        local health = {
            npcColorMode = general.npcColorMode == "type" and "type" or "reaction",
            npcTypeColorBar = general.npcTypeColorBar ~= false,
            npcTypeTarget = general.npcTypeTarget ~= false,
            npcTypeFocus = general.npcTypeFocus ~= false,
            npcTypeBoss = general.npcTypeBoss ~= false,
            npcTypeToT = general.npcTypeToT ~= false,
        }
        kind = common.UnitNPCKind(nil, unit, { key = key, health = health }, false, key)
    end
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
    local general = G()
    local common = MSUF and MSUF.UFBarTextCommon
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local kind
    if exists and common and type(common.UnitNPCKind) == "function" then
        local text = {
            npcColorMode = general.npcColorMode == "type" and "type" or "reaction",
            npcTypeColorText = general.npcTypeColorText ~= false,
            npcTypeTarget = general.npcTypeTarget ~= false,
            npcTypeFocus = general.npcTypeFocus ~= false,
            npcTypeBoss = general.npcTypeBoss ~= false,
            npcTypeToT = general.npcTypeToT ~= false,
        }
        kind = common.UnitNPCKind(nil, unit, { key = key, text = text }, true, key)
    end
    if type(kind) ~= "string" then
        local preview = ContextPreviewUnitData(unit)
        kind = preview and (preview.npcKind or preview.reactionKind) or nil
    end
    return type(kind) == "string" and kind or ContextReactionKind({ unit = unit })
end

local function ContextNameEntityTarget(unit, key, classColor, npcColor, npcClassColor, npcKey)
    local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
    local preview = not exists and ContextPreviewUnitData(unit) or nil
    local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or (preview and preview.isPlayer)
    local _, classToken
    if exists and type(_G.UnitClass) == "function" then
        _, classToken = _G.UnitClass(unit)
        if type(_G.issecretvalue) == "function" and _G.issecretvalue(classToken) == true then classToken = nil end
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

-- Registration is grouped by color family; the groups run in the original
-- registration order so CONTEXT_COLOR_FACTORIES ends up with the same keys.
local function RegisterBarContextFactories()
    FixedContextFactory("bar.absorb", function()
        return ContextStoredApiScopedOpacity("bar.absorb", "Absorb", "GetAbsorbOverlayColor", "SetAbsorbOverlayColor",
            "absorbBarColor", 1, 1, 1, 0.45, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY")
    end)
    FixedContextFactory("bar.heal_absorb", function()
        return ContextStoredApiScopedOpacity("bar.heal_absorb", "Heal absorb", "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor",
            "healAbsorbBarColor", 0.7, 0, 0, 0.45, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY")
    end)
    FixedContextFactory("bar.power_background", function()
        return ContextStoredApi("bar.power_background", "Power background", "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", "powerBarBgColor", 0, 0, 0, 1, ApplyColors, true)
    end)
    FixedContextFactory("bar.aggro_border", function()
        local target = ContextApi("bar.aggro_border", "Aggro border", "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0)
        local state = ContextStoredState(G, {
            "hlAggroColorR", "hlAggroColorG", "hlAggroColorB",
            "aggroBorderColorR", "aggroBorderColorG", "aggroBorderColorB",
            "aggroBorderR", "aggroBorderG", "aggroBorderB",
        }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("bar.heal_prediction", function()
        return ContextGeneral("bar.heal_prediction", "Heal prediction", "healPredictionColor", 0, 1, 0, ApplyColors)
    end)
    FixedContextFactory("bar.health_loss", function()
        return ContextGeneral("bar.health_loss", "Health loss glow", "healthLossColor", 1, 0.55, 0.08, ApplyColors)
    end)
    FixedContextFactory("bar.power_loss", function()
        return ContextGeneral("bar.power_loss", "Power loss glow", "powerLossColor", 0.70, 0.90, 1, ApplyColors)
    end)
    FixedContextFactory("bar.purge_border", function()
        local target = ContextTarget("bar.purge_border", "Purge border",
            function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1, 0.85, 0) end,
            function(r, g, b) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, b) end)
        local state = ContextStoredState(G, {
            "hlPurgeColorR", "hlPurgeColorG", "hlPurgeColorB",
            "purgeBorderColorR", "purgeBorderColorG", "purgeBorderColorB",
        }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("bar.outline", function() return ContextGeneral("bar.outline", "Bar outline", "barOutlineColor", 0, 0, 0, ApplyGlobalOutlineColor) end)
    FixedContextFactory("bar.background_tint", function()
        return ContextStoredApi("bar.background_tint", "Bar background tint", "GetClassBarBgColor", "SetClassBarBgColor", "classBarBg", 0, 0, 0, 1, ApplyUnitframeColorWithReload, true)
    end)
    FixedContextFactory("health.unified", function() return ContextGeneral("health.unified", "Unified health bar", "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload) end)
    FixedContextFactory("health.gradient.low", function() return ContextGeneral("health.gradient.low", "Health gradient - low", "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload) end)
    FixedContextFactory("health.gradient.mid", function() return ContextGeneral("health.gradient.mid", "Health gradient - middle", "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload) end)
    FixedContextFactory("health.gradient.high", function() return ContextGeneral("health.gradient.high", "Health gradient - high", "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload) end)
    ContextFactory("health.background.current", function(context)
        local mode = M.ColorsBackgroundMode.GetColor()
        if mode == "health_gradient" then
            return {
                CONTEXT_COLOR_FACTORIES["health.gradient.low"](),
                CONTEXT_COLOR_FACTORIES["health.gradient.mid"](),
                CONTEXT_COLOR_FACTORIES["health.gradient.high"](),
            }
        end
        if mode ~= "custom" then return nil end
        local id = context and context.group == true and "group.background" or "bar.background_tint"
        local factory = CONTEXT_COLOR_FACTORIES[id]
        return type(factory) == "function" and factory(context) or nil
    end)
    ContextFactory("health.current", function(context)
        local mode = ContextHealthMode(context)
        if mode == "gradient" then
            return {
                CONTEXT_COLOR_FACTORIES["health.gradient.low"](),
                CONTEXT_COLOR_FACTORIES["health.gradient.mid"](),
                CONTEXT_COLOR_FACTORIES["health.gradient.high"](),
            }
        end
        if mode == "unified" then return CONTEXT_COLOR_FACTORIES["health.unified"]() end
        if mode == "class" then
            local unit, key = ContextUnit(context), ContextUnitKey(context)
            if key == "pet" then return CONTEXT_COLOR_FACTORIES["unit.pet"]() end
            local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
            local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or nil
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
local function RegisterUnitContextFactories()
    ContextFactory("unit.class.current", ContextClassColor)
    ContextFactory("unit.npc.current", function(context) return ContextNPCColor(ContextReactionKind(context)) end)
    for _, kind in ipairs({ "friendly", "neutral", "enemy", "dead", "npcBoss", "npcMiniboss", "npcCaster", "npcMelee", "npcRegular" }) do
        local npcKind = kind
        ContextFactory("unit.npc." .. npcKind, function() return ContextNPCColor(npcKind) end)
    end
    FixedContextFactory("unit.pet", function()
        local target = ContextApi("unit.pet", "Pet frame", "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
        local state = ContextStoredState(G, { "petFrameColorR", "petFrameColorG", "petFrameColorB" }, ApplyUnitframeColorWithReload)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        local setRGB = target.setRGB
        target.setRGB = function(r, g, b) setRGB(r, g, b); ApplyUnitframeColorWithReload() end
        return target
    end)
    FixedContextFactory("highlight.mouseover", function()
        local target = ContextTarget("highlight.mouseover", "Mouseover highlight", HighlightRGB, SetHighlightRGB)
        local state = ContextStoredState(G, { "highlightColor" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("highlight.boss_target", function()
        return ContextTable("highlight.boss_target", "Boss target highlight", G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
    end)
    FixedContextFactory("portrait.border", function()
        local target = ContextTarget("portrait.border", "Portrait border",
            function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
            function(r, g, b) SetAllPortraitRGB("portraitBorderColor", r, g, b) end)
        local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
            { "portraitBorderColorR", "portraitBorderColorG", "portraitBorderColorB" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("portrait.background", function()
        local target = ContextTarget("portrait.background", "Portrait background",
            function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
            function(r, g, b) SetAllPortraitRGB("portraitBgColor", r, g, b) end)
        local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
            { "portraitBgColorR", "portraitBgColorG", "portraitBgColorB" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    for _, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", label = "Texture layer" },
        { id = "texture_layer2", prefix = "texLayer2", label = "Texture layer 2" },
        { id = "texture_layer3", prefix = "texLayer3", label = "Texture layer 3" },
    }) do
        local slotId, slotPrefix, slotLabel = texSlot.id, texSlot.prefix, texSlot.label
        FixedContextFactory(slotId .. ".color", function()
            local target = ContextTarget(slotId .. ".color", slotLabel,
                function() return GeneralRGB(slotPrefix .. "Color", 1, 1, 1) end,
                function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Color", r, g, b) end)
            local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
                { slotPrefix .. "ColorR", slotPrefix .. "ColorG", slotPrefix .. "ColorB" }, M._ApplyTextureLayerColors)
            target.captureState, target.restoreState = state.captureState, state.restoreState
            return target
        end)
        FixedContextFactory(slotId .. ".gradient", function()
            local target = ContextTarget(slotId .. ".gradient", M.Format("%s gradient end", M.Tr(slotLabel)),
                function() return GeneralRGB(slotPrefix .. "Gradient2", 0, 0, 0) end,
                function(r, g, b) M._SetAllTextureLayerRGB(slotPrefix .. "Gradient2", r, g, b) end)
            local state = ContextDBRowsState({ "general", "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" },
                { slotPrefix .. "Gradient2R", slotPrefix .. "Gradient2G", slotPrefix .. "Gradient2B" }, M._ApplyTextureLayerColors)
            target.captureState, target.restoreState = state.captureState, state.restoreState
            return target
        end)
    end
    FixedContextFactory("font.global", function()
        local target = ContextTarget("font.global", "Default font", M._ContextConfiguredGlobalFontRGB,
            function(r, g, b)
                if not ApiSetRGB("SetGlobalFontColor", r, g, b) then
                    local general = G()
                    general.useCustomFontColor = true
                    general.fontColorCustomR, general.fontColorCustomG, general.fontColorCustomB = r, g, b
                    ApplyColors()
                end
            end)
        local state = ContextStoredState(G, { "useCustomFontColor", "fontColorCustomR", "fontColorCustomG", "fontColorCustomB" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
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
            local exists = type(_G.UnitExists) ~= "function" or _G.UnitExists(unit) == true
            local preview = not exists and ContextPreviewUnitData(unit) or nil
            local isPlayer = exists and ContextPlainUnitValue(_G.UnitIsPlayer, unit) or (preview and preview.isPlayer)
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
local function RegisterCastContextFactories()
    local function CastApiFactory(id, label, getName, setName, prefix, dr, dg, db)
        FixedContextFactory(id, function()
            local target = ContextApi(id, label, getName, setName, dr, dg, db, ApplyCastbarColors)
            local state = ContextStoredState(G, { prefix .. "R", prefix .. "G", prefix .. "B", prefix .. "Color" }, ApplyCastbarColors)
            target.captureState, target.restoreState = state.captureState, state.restoreState
            return target
        end)
    end
    CastApiFactory("cast.interruptible", "Interruptible cast", "GetInterruptibleCastColor", "SetInterruptibleCastColor", "castbarInterruptible", 0, 0.9, 0.8)
    CastApiFactory("cast.non_interruptible", "Non-interruptible cast", "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", "castbarNonInterruptible", 0.4, 0.01, 0.01)
    CastApiFactory("cast.interrupt_feedback", "Interrupt feedback", "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", "castbarInterruptFeedback", 1, 0.82, 0)
    CastApiFactory("cast.interrupt_unavailable", "Interrupt unavailable", "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", "castbarInterruptUnavailable", 1, 0.494117647, 0.137254902)
    local function CastStoredFactory(id, label, getName, setName, defaults, keys)
        FixedContextFactory(id, function()
            local target = ContextApi(id, label, getName, setName, defaults[1], defaults[2], defaults[3], ApplyCastbarColors)
            local state = ContextStoredState(G, keys, ApplyCastbarColors)
            target.captureState, target.restoreState = state.captureState, state.restoreState
            return target
        end)
    end
    CastStoredFactory("cast.text", "Cast text", "GetCastbarTextColor", "SetCastbarTextColor", { 1, 1, 1 }, { "castbarFontR", "castbarFontG", "castbarFontB" })
    CastStoredFactory("cast.target_text", "Cast target text", "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", { 1, 1, 1 }, { "castbarTargetNameR", "castbarTargetNameG", "castbarTargetNameB" })
    CastStoredFactory("cast.player_override", "Player cast override", "GetPlayerCastbarOverrideColor", "SetPlayerCastbarOverrideColor", { 0, 0.6, 1 }, { "playerCastbarOverrideR", "playerCastbarOverrideG", "playerCastbarOverrideB" })
    FixedContextFactory("cast.border", function()
        local target = ContextApiOrGeneral("cast.border", "Castbar border", "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, ApplyCastbarColors, 1)
        local state = ContextStoredState(G, { "castbarBorderR", "castbarBorderG", "castbarBorderB", "castbarBorderA" }, ApplyCastbarColors)
        target.hasOpacity, target.getOpacity = true, function() local _, _, _, a = ApiRGB("GetCastbarBorderColor", 0, 0, 0); return tonumber(a) or 1 end
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("cast.background", function()
        local target = ContextApiOrGeneral("cast.background", "Castbar background", "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, ApplyCastbarColors, 0.85)
        local state = ContextStoredState(G, { "castbarBgR", "castbarBgG", "castbarBgB", "castbarBgA" }, ApplyCastbarColors)
        target.hasOpacity, target.getOpacity = true, function() local _, _, _, a = ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10); return tonumber(a) or 0.85 end
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("cast.kick_ready", function() return ContextTable("cast.kick_ready", "Kick ready", G, "kickReadyColor", 0, 1, 0, ApplyCastbarColors) end)
    FixedContextFactory("cast.kick_not_ready", function() return ContextTable("cast.kick_not_ready", "Kick not ready", G, "kickNotReadyColor", 1, 0, 0, ApplyCastbarColors) end)
    -- Per-castbar detail text colors. A detail with no complete stored triple is
    -- still following the shared castbar color, so the factory hands back that
    -- shared target instead of a swatch whose first click would quietly create an
    -- override nobody asked for. Locals stay inside this IIFE: it sits at the Lua
    -- 5.1 upvalue ceiling, so the DB reach-through goes via the exported globals.
    local CAST_DETAIL_PREFIX = {
        player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast",
    }
    local function CastDetailContextTarget(context, detail, label, sharedId)
        local unit = ContextUnit(context)
        local read = _G.MSUF_GetCastbarDetailTextColor
        local write = _G.MSUF_SetCastbarDetailTextColor
        local prefix = CAST_DETAIL_PREFIX[unit]
        if not (prefix and type(read) == "function" and type(write) == "function") then
            return CONTEXT_COLOR_FACTORIES[sharedId]()
        end
        local _, _, _, custom = read(unit, detail)
        if custom ~= true then return CONTEXT_COLOR_FACTORIES[sharedId]() end
        local key = prefix .. detail .. "Color"
        local target = ContextTarget("cast.detail." .. unit .. "." .. detail, label,
            function()
                local r, g, b = read(unit, detail)
                return r, g, b
            end,
            function(r, g, b)
                write(unit, detail, r, g, b)
                ApplyCastbarColors()
            end)
        local state = ContextStoredState(G, { key .. "R", key .. "G", key .. "B" }, ApplyCastbarColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end
    ContextFactory("cast.spell_text.current", function(context)
        return CastDetailContextTarget(context, "SpellName", "Cast spell text", "cast.text")
    end)
    ContextFactory("cast.time_text.current", function(context)
        return CastDetailContextTarget(context, "Time", "Cast time text", "cast.text")
    end)
    ContextFactory("cast.target_text.current", function(context)
        return CastDetailContextTarget(context, "TargetName", "Cast target text", "cast.target_text")
    end)
    -- Status text indicators (level/race/class/raid group and the Dead, Ghost, AFK
    -- and DND states). An unset indicator follows the frame's font color, so it
    -- resolves to the shared font target for the same reason as the castbar
    -- details above.
    ContextFactory("status.text.current", function(context)
        local unit = ContextUnit(context)
        local prefix = ContextValue(context and context.colorPrefix, context)
        local conf = type(prefix) == "string" and prefix ~= "" and DB()[unit] or nil
        if not conf then return CONTEXT_COLOR_FACTORIES["font.global"]() end
        local target = ContextTarget("status.text." .. unit .. "." .. prefix,
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
                M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false })
            end)
        local state = ContextStoredState(function() return conf end,
            { prefix .. "ColorR", prefix .. "ColorG", prefix .. "ColorB" },
            function() M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false }) end)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
end
local function RegisterAuraContextFactories()
    local function AuraTableFactory(id, label, key, dr, dg, db)
        FixedContextFactory(id, function() return ContextTable(id, label, G, key, dr, dg, db, ApplyAuraColors) end)
    end
    local function ContextDispelType(id, dispelType)
        local target = ContextTarget(id, dispelType .. " dispel",
            function() return M._GetDispelTypeRGB(dispelType, true) end,
            function(r, g, b) M._SetDispelTypeRGB(dispelType, r, g, b) end)
        local state = ContextStoredState(G, { "dispelTypeColorOverrides" }, function()
            M._SetDispelColorPreviewType(dispelType)
            ApplyAuraColors()
        end)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end
    FixedContextFactory("aura.cooldown.safe", function()
        local target = ContextTarget("aura.cooldown.safe", "Cooldown safe", M._ContextGetAuraSafeRGB, M._ContextSetAuraSafeRGB)
        local state = ContextStoredState(G, { "aurasCooldownTextSafeColor" }, ApplyAuraColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    AuraTableFactory("aura.cooldown.warning", "Cooldown warning", "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
    AuraTableFactory("aura.cooldown.urgent", "Cooldown urgent", "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
    FixedContextFactory("aura.dispel.magic", function() return ContextDispelType("aura.dispel.magic", "Magic") end)
    FixedContextFactory("aura.dispel.curse", function() return ContextDispelType("aura.dispel.curse", "Curse") end)
    FixedContextFactory("aura.dispel.disease", function() return ContextDispelType("aura.dispel.disease", "Disease") end)
    FixedContextFactory("aura.dispel.poison", function() return ContextDispelType("aura.dispel.poison", "Poison") end)
    FixedContextFactory("aura.dispel.bleed", function() return ContextDispelType("aura.dispel.bleed", "Bleed") end)
end
local function RegisterGroupContextFactories()
    FixedContextFactory("group.health", function()
        local target = ContextTarget("group.health", "Group health bar", GroupHealthBarRGB, SetGroupHealthBarRGB)
        local state = ContextDBRowsState(GROUP_COLOR_DB_KEYS, {
            "gfDarkR", "gfDarkG", "gfDarkB", "gfUnifiedR", "gfUnifiedG", "gfUnifiedB",
            "healthCustomR", "healthCustomG", "healthCustomB",
        }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("group.background", function() return ContextGroup("group.background", "Group bar background", "bg", 0.10, 0.10, 0.10) end)
    FixedContextFactory("group.dead", function() return ContextGroup("group.dead", "Dead / offline background", "deadBg", 0.60, 0.05, 0.05, "deadBgA", 0.90) end)
    FixedContextFactory("group.debuff_stripe", function() return ContextGroup("group.debuff_stripe", "Debuff stripe", "debuffStripeColor", 0.80, 0.20, 0.20, "debuffStripeAlpha", 0.60) end)
    FixedContextFactory("group.target", function() return ContextGroup("group.target", "Target highlight", "target", 1, 1, 1) end)
    FixedContextFactory("group.focus", function() return ContextGroup("group.focus", "Focus highlight", "hlFocusColor", 0.50, 0.50, 1) end)
    FixedContextFactory("group.border", function() return ContextGroup("group.border", "Group border", "groupBorder", 0.38, 0.68, 1, "groupBorderA", 0.95) end)
    FixedContextFactory("group.aggro", function() return ContextGroup("group.aggro", "Corner aggro", "ciAggroColor", 1, 0.55, 0) end)
    FixedContextFactory("group.portrait.border", function()
        return ContextGroup("group.portrait.border", "Party portrait border",
            "portraitBorderColor", 1, 1, 1, "portraitBorderColorA", 1)
    end)
end
local function RegisterGameplayContextFactories()
    FixedContextFactory("gameplay.timer", function() return ContextTable("gameplay.timer", "Combat timer", Gameplay, "combatTimerColor", 1, 1, 1, ApplyGameplayColors) end)
    FixedContextFactory("gameplay.enter", function()
        local target = ContextTarget("gameplay.enter", "Combat enter",
            function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
            function(r, g, b)
                local gameplay = Gameplay()
                SetTableRGB(gameplay, "combatStateEnterColor", r, g, b)
                if gameplay.combatStateColorSync then SetTableRGB(gameplay, "combatStateLeaveColor", r, g, b) end
                ApplyGameplayColors()
            end)
        local state = ContextStoredState(Gameplay, { "combatStateEnterColor", "combatStateLeaveColor" }, ApplyGameplayColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("gameplay.leave", function()
        return ContextTable("gameplay.leave", "Combat leave", Gameplay, "combatStateLeaveColor", 0.7, 0.7, 0.7, ApplyGameplayColors, {
            isEnabled = function() return Gameplay().combatStateColorSync ~= true end,
        })
    end)
    FixedContextFactory("gameplay.crosshair_in", function() return ContextTable("gameplay.crosshair_in", "Crosshair in range", Gameplay, "crosshairInRangeColor", 0, 1, 0, ApplyGameplayColors) end)
    FixedContextFactory("gameplay.crosshair_out", function() return ContextTable("gameplay.crosshair_out", "Crosshair out of range", Gameplay, "crosshairOutRangeColor", 1, 0, 0, ApplyGameplayColors) end)
end
local function RegisterPowerContextFactories()
    local function PowerTokenTarget(id, token, label)
        local target = ContextTarget(id, label,
            function() return GetPowerOverrideRGB(token) end,
            function(r, g, b) SetPowerOverrideRGB(token, r, g, b) end)
        local state = ContextStoredState(G, { "powerColorOverrides" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end
    ContextFactory("power.current", function(context)
        local token = ContextPowerToken(context)
        local target = PowerTokenTarget("power.current." .. token, token, (token:gsub("_", " ")) .. " power")
        target.getColorByClass = M.PowerBarColorByClass.Get
        target.setColorByClass = M.PowerBarColorByClass.Set
        local state = ContextStoredState(G, { "powerColorOverrides", "powerColorMode", "powerBarColorMode" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    -- A single unit has one resource, so "power.current" resolves it from context.
    -- A party or raid roster mixes every resource type at once, so group cards name
    -- each color instead. Labels are spelled out rather than read from the page's
    -- COLOR_POWER_TOKENS list: this registry is an IIFE sitting at 60 upvalues, and
    -- reaching for one more file-level local breaks Lua 5.1's limit. They must stay
    -- in sync with that list, and each entry edits the same shared override table.
    local POWER_TOKEN_CONTEXT_IDS = {
        { "power.token.mana", "MANA", "Mana" },
        { "power.token.rage", "RAGE", "Rage" },
        { "power.token.energy", "ENERGY", "Energy" },
        { "power.token.focus", "FOCUS", "Focus" },
        { "power.token.runic_power", "RUNIC_POWER", "Runic Power" },
        { "power.token.insanity", "INSANITY", "Insanity" },
        { "power.token.fury", "FURY", "Fury" },
        { "power.token.pain", "PAIN", "Pain" },
        { "power.token.essence", "ESSENCE", "Essence" },
        { "power.token.lunar_power", "LUNAR_POWER", "Astral Power" },
        { "power.token.maelstrom", "MAELSTROM", "Maelstrom" },
    }
    for i = 1, #POWER_TOKEN_CONTEXT_IDS do
        local entry = POWER_TOKEN_CONTEXT_IDS[i]
        local id, token, label = entry[1], entry[2], entry[3]
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
            generalState.restoreState(state and state[1]); barsState.restoreState(state and state[2]); ApplyColors()
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
    FixedContextFactory("class_power.text", function()
        local target = ContextTarget("class_power.text", "Class resource text",
            function() return GetClassPowerRGB("RESOURCE_TEXT") end,
            function(r, g, b) SetClassPowerRGB("RESOURCE_TEXT", r, g, b) end)
        local state = ContextStoredState(G, { "classPowerColorOverrides" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
    FixedContextFactory("class_power.alt_mana", function()
        local target = ContextTarget("class_power.alt_mana", "Alternative mana",
            function() return GetClassPowerRGB("MANA") end,
            function(r, g, b) SetClassPowerRGB("MANA", r, g, b) end)
        local state = ContextStoredState(G, { "classPowerColorOverrides" }, ApplyColors)
        target.captureState, target.restoreState = state.captureState, state.restoreState
        return target
    end)
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
            local target = ContextTarget(id, label,
            function()
                    return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
                        tonumber(GradientScopeGet(prefix .. "G", 0)) or 0,
                        tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
            end,
            function(r, g, b)
                    GradientScopeSet(prefix .. "R", r); GradientScopeSet(prefix .. "G", g); GradientScopeSet(prefix .. "B", b)
                    ApplyScopedBarGradientColors(reason)
            end)
            local state = ContextDBRowsState(rows, {
                prefix .. "R", prefix .. "G", prefix .. "B", "hlOverride", "gradientOverride",
                "gradientOverrideVersion", "gradientOverrideKeys",
            }, function() ApplyScopedBarGradientColors(reason) end)
            target.captureState, target.restoreState = state.captureState, state.restoreState
            return target
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
        if not seen[identity] then seen[identity] = true; out[#out + 1] = value end
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
