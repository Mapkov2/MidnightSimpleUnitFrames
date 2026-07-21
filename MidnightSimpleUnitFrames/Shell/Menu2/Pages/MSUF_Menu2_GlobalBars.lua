local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Bars page.
-- Binds shared/scoped texture, gradient, outline, absorb, and highlight controls. Page code
-- updates DB through GlobalPage helpers and lets runtime refreshers repaint live frames.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local min = math.min
local unpack = unpack or table.unpack
local DISPEL_BORDER_121_PTR_DISABLED = false
local PURGE_BORDER_121_PTR_DISABLED = true
local DISPEL_PURGE_BORDER_121_PTR_MESSAGE = "Dispel uses native 12.1 AuraContainer detection. Purge border stays disabled until Blizzard exposes a safe purge/stealable filter."
local UNITFRAME_DISPEL_AURA_WARNING = "No UnitFrame auras: Dispel Border/Overlay need Player/Target/Focus/Boss auras."
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = { 0.90, 0.84, 0.76, 1 }
local UNITFRAME_DISPEL_AURA_UNITS = { "player", "target", "focus", "boss" }
local UNITFRAME_AURA_APPLY_OPTS = { preview = true, auras = true, notify = false }
local ROUNDED_PREVIEW_MASK_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\Masks\\"
local ROUNDED_PREVIEW_MASK = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_4x.tga"
local ROUNDED_PREVIEW_EDGE = ROUNDED_PREVIEW_MASK_ROOT .. "rounded_bar_edge_4x.tga"
local GRADIENT_DIR_KEYS, PRIORITY_LABELS = M.PickDefaults(GP, [[GRADIENT_DIR_KEYS PRIORITY_LABELS]])
local DISPEL_TRIGGERS = VT("BY_ME", "Dispellable by me", "BY_RAID", "Dispellable by group",
    "DISPEL_TYPE", "Any dispel type")
local UNIT_DISPEL_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
    "BY_RAID", "Dispellable by group", "DISPEL_TYPE", "Any dispel type")
local UNIT_DISPEL_STYLES = VT("FULL", "Full Frame", "TOP", "Top Fade", "BOTTOM", "Bottom Fade",
    "LEFT", "Left Fade", "RIGHT", "Right Fade")
local Call, DB, G, Bars, ReadG, ReadGBool, ReadB, NormalizeScopeKey, ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, CurrentBarsScope, IsGFScope, BarScopeGet, BarScopeSet, BarScopeGetBars, BarScopeSetBars, GradientScopeGet, GradientScopeSet, GradientScopeHasExplicit, TextureValues, CurrentPowerBarScopeUnit, SmoothPowerGet, SmoothPowerSet, PriorityOrder, PriorityColor, RefreshBorderTestModes, SetAbsorbTextureTest, SetControlEnabled, SetControlsEnabled, ApplyBars, ControlMeta, RegisterControl = M.Pick(GP, [[Call DB G Bars ReadG ReadGBool ReadB NormalizeScopeKey ScopeDBKeys ScopeHasOverride ScopeSetOverride CurrentBarsScope IsGFScope BarScopeGet BarScopeSet BarScopeGetBars BarScopeSetBars GradientScopeGet GradientScopeSet GradientScopeHasExplicit TextureValues CurrentPowerBarScopeUnit SmoothPowerGet SmoothPowerSet PriorityOrder PriorityColor RefreshBorderTestModes SetAbsorbTextureTest SetControlEnabled SetControlsEnabled ApplyBars ControlMeta RegisterControl]])
local IsAbsorbTextureTestEnabled = GP.IsAbsorbTextureTestEnabled or function() return _G.MSUF_AbsorbTextureTestMode == true end
local BAR_SETTING_BY_PATH = {
    ["highlight.boss_target.mode"] = "general.bossTargetOutlineMode",
    ["rounded.roundedFramesEnabled"] = "bars.roundedFramesEnabled",
    ["rounded.roundedUnitFrames"] = "bars.roundedUnitFrames",
    ["rounded.roundedGroupFrames"] = "bars.roundedGroupFrames",
    ["rounded.roundedPowerBars"] = "bars.roundedPowerBars",
    ["rounded.roundedMouseover"] = "bars.roundedMouseover",
    ["power.realtime_text"] = "bars.realtimePowerText",
}
local BAR_ACTION_BY_PATH = {
    ["scope.overrides.reset"] = "reset_all_scoped_global_bars_overrides",
}
local BAR_DYNAMIC_SETTING_KEYS_BY_PATH = {
    ["textures.foreground"] = { "general.barTexture" },
    ["textures.background"] = { "general.barBackgroundTexture" },
    ["gradient.enableGradient"] = { "general.enableGradient" },
    ["gradient.enablePowerGradient"] = { "general.enablePowerGradient" },
    ["gradient.health.strength"] = { "general.gradientStrength" },
    ["gradient.power.strength"] = { "general.powerGradientStrength" },
    ["temp_max_health.enabled"] = { "general.tempMaxHealthEnabled" },
    ["temp_max_health.texture"] = { "general.tempMaxHealthTexture" },
    ["temp_max_health.color"] = {
        "general.tempMaxHealthColorR", "general.tempMaxHealthColorG", "general.tempMaxHealthColorB",
    },
    ["temp_max_health.opacity"] = { "general.tempMaxHealthOpacity" },
    ["temp_max_health.background_opacity"] = { "general.tempMaxHealthBackgroundOpacity" },
    ["absorb.display_mode"] = { "general.absorbTextMode" },
    ["absorb.absorbAnchorMode"] = { "general.absorbAnchorMode" },
    ["absorb.absorbBarOpacity"] = { "general.absorbBarOpacity" },
    ["absorb.absorbBarTexture"] = { "general.absorbBarTexture" },
    ["absorb.healAbsorbBarOpacity"] = { "general.healAbsorbBarOpacity" },
    ["absorb.healAbsorbBarTexture"] = { "general.healAbsorbBarTexture" },
    ["absorb.healPredAnchorMode"] = { "general.healPredAnchorMode" },
    ["absorb.heal_prediction.enabled"] = { "general.healPredEnabled", "general.showSelfHealPrediction" },
    ["absorb.healPredEnabled"] = { "general.healPredEnabled", "general.showSelfHealPrediction" },
    ["absorb.positive.enabled"] = { "general.enableAbsorbBar", "general.absorbTextMode" },
    ["absorb.positive.anchor"] = { "general.absorbAnchorMode" },
    ["absorb.positive.height"] = { "general.absorbBarHeight" },
    ["absorb.positive.offset_y"] = { "general.absorbBarOffsetY" },
    ["absorb.positive.texture"] = { "general.absorbBarTexture" },
    ["absorb.positive.opacity"] = { "general.absorbBarOpacity" },
    ["absorb.positive.over_absorb"] = { "general.overAbsorbOverlay" },
    ["absorb.positive.full_health_stripe"] = { "general.fullHealthAbsorbStripe" },
    ["absorb.negative.enabled"] = { "general.healAbsorbEnabled" },
    ["absorb.negative.anchor"] = { "general.healAbsorbAnchorMode" },
    ["absorb.negative.height"] = { "general.healAbsorbBarHeight" },
    ["absorb.negative.offset_y"] = { "general.healAbsorbBarOffsetY" },
    ["absorb.negative.texture"] = { "general.healAbsorbBarTexture" },
    ["absorb.negative.opacity"] = { "general.healAbsorbBarOpacity" },
    ["absorb.heal_prediction.anchor"] = { "general.healPredAnchorMode" },
    ["absorb.heal_prediction.height"] = { "general.healPredictionBarHeight" },
    ["absorb.heal_prediction.offset_y"] = { "general.healPredictionBarOffsetY" },
    ["absorb.heal_prediction.texture"] = { "general.healPredictionBarTexture" },
    ["absorb.heal_prediction.opacity"] = { "general.healPredictionBarOpacity" },
    ["absorb.over_absorb_overlay"] = { "general.overAbsorbOverlay" },
    ["absorb.full_health_stripe"] = { "general.fullHealthAbsorbStripe" },
    ["outline.thickness"] = { "bars.barOutlineThickness" },
    ["outline.layer"] = { "bars.barOutlineLayer" },
    ["outline.color"] = { "general.barOutlineColor" },
    ["highlight.border_thickness"] = { "general.highlightBorderThickness" },
    ["highlight.border_mode.aggroOutlineMode"] = { "general.aggroOutlineMode" },
    ["highlight.aggro.roles"] = { "general.aggroMode" },
    ["highlight.border_mode.dispelOutlineMode"] = { "general.dispelOutlineMode" },
    ["highlight.dispel.trigger"] = { "general.dispelBorderTrigger" },
    ["highlight.border_mode.purgeOutlineMode"] = { "general.purgeOutlineMode" },
    ["highlight.priority.enabled"] = { "general.hlPrioEnabled" },
    ["unit_dispel_overlay.enabled"] = { "general.unitDispelOverlayEnabled" },
    ["unit_dispel_overlay.unitDispelOverlayTrigger"] = { "general.unitDispelOverlayTrigger" },
    ["unit_dispel_overlay.unitDispelOverlayStyle"] = { "general.unitDispelOverlayStyle" },
    ["unit_dispel_overlay.unitDispelOverlayOnHealth"] = { "general.unitDispelOverlayOnHealth" },
    ["unit_dispel_overlay.unitDispelOverlayAlpha"] = { "general.unitDispelOverlayAlpha" },
    ["power.smooth_fill"] = { "bars.smoothPowerBar" },
}
local BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH = {
    ["scope.override.enabled"] = "override",
    ["textures.foreground"] = "barTexture",
    ["textures.background"] = "barBackgroundTexture",
    ["gradient.enableGradient"] = "enableGradient",
    ["gradient.enablePowerGradient"] = "enablePowerGradient",
    ["gradient.health.strength"] = "gradientStrength",
    ["gradient.power.strength"] = "powerGradientStrength",
    ["temp_max_health.enabled"] = "tempMaxHealthEnabled",
    ["temp_max_health.texture"] = "tempMaxHealthTexture",
    ["temp_max_health.color"] = "tempMaxHealthColorR",
    ["temp_max_health.opacity"] = "tempMaxHealthOpacity",
    ["temp_max_health.background_opacity"] = "tempMaxHealthBackgroundOpacity",
    ["absorb.display_mode"] = "absorbTextMode",
    ["absorb.absorbAnchorMode"] = "absorbAnchorMode",
    ["absorb.absorbBarOpacity"] = "absorbBarOpacity",
    ["absorb.absorbBarTexture"] = "absorbBarTexture",
    ["absorb.healAbsorbBarOpacity"] = "healAbsorbBarOpacity",
    ["absorb.healAbsorbBarTexture"] = "healAbsorbBarTexture",
    ["absorb.healPredAnchorMode"] = "healPredAnchorMode",
    ["absorb.heal_prediction.enabled"] = "healPredEnabled",
    ["absorb.healPredEnabled"] = "healPredEnabled",
    ["absorb.positive.enabled"] = "enableAbsorbBar",
    ["absorb.positive.anchor"] = "absorbAnchorMode",
    ["absorb.positive.height"] = "absorbBarHeight",
    ["absorb.positive.offset_y"] = "absorbBarOffsetY",
    ["absorb.positive.texture"] = "absorbBarTexture",
    ["absorb.positive.opacity"] = "absorbBarOpacity",
    ["absorb.positive.over_absorb"] = "overAbsorbOverlay",
    ["absorb.positive.full_health_stripe"] = "fullHealthAbsorbStripe",
    ["absorb.negative.enabled"] = "healAbsorbEnabled",
    ["absorb.negative.anchor"] = "healAbsorbAnchorMode",
    ["absorb.negative.height"] = "healAbsorbBarHeight",
    ["absorb.negative.offset_y"] = "healAbsorbBarOffsetY",
    ["absorb.negative.texture"] = "healAbsorbBarTexture",
    ["absorb.negative.opacity"] = "healAbsorbBarOpacity",
    ["absorb.heal_prediction.anchor"] = "healPredAnchorMode",
    ["absorb.heal_prediction.height"] = "healPredictionBarHeight",
    ["absorb.heal_prediction.offset_y"] = "healPredictionBarOffsetY",
    ["absorb.heal_prediction.texture"] = "healPredictionBarTexture",
    ["absorb.heal_prediction.opacity"] = "healPredictionBarOpacity",
    ["absorb.over_absorb_overlay"] = "overAbsorbOverlay",
    ["absorb.full_health_stripe"] = "fullHealthAbsorbStripe",
    ["outline.thickness"] = "barOutlineThickness",
    ["outline.layer"] = "barOutlineLayer",
    ["outline.color"] = "barOutlineColor",
    ["highlight.border_thickness"] = "highlightBorderThickness",
    ["highlight.border_mode.aggroOutlineMode"] = "aggroOutlineMode",
    ["highlight.aggro.roles"] = "aggroMode",
    ["highlight.border_mode.dispelOutlineMode"] = "dispelOutlineMode",
    ["highlight.dispel.trigger"] = "dispelBorderTrigger",
    ["highlight.border_mode.purgeOutlineMode"] = "purgeOutlineMode",
    ["highlight.priority.enabled"] = "hlPrioEnabled",
    ["unit_dispel_overlay.enabled"] = "unitDispelOverlayEnabled",
    ["unit_dispel_overlay.unitDispelOverlayTrigger"] = "unitDispelOverlayTrigger",
    ["unit_dispel_overlay.unitDispelOverlayStyle"] = "unitDispelOverlayStyle",
    ["unit_dispel_overlay.unitDispelOverlayOnHealth"] = "unitDispelOverlayOnHealth",
    ["unit_dispel_overlay.unitDispelOverlayAlpha"] = "unitDispelOverlayAlpha",
}
local BAR_DYNAMIC_SETTING_PATTERNS_BY_PATH = {
    ["absorb.positive.enabled"] = {
        "^barScope%.[%w_]+%.enableAbsorbBar$",
        "^barScope%.[%w_]+%.absorbTextMode$",
    },
}
local function IsDynamicBarPath(path)
    path = tostring(path or "")
    return path == "scope.override.enabled"
        or path == "power.smooth_fill"
        or path:find("^textures%.") ~= nil
        or path:find("^gradient%.") ~= nil
        or path:find("^temp_max_health%.") ~= nil
        or path:find("^absorb%.") ~= nil
        or path:find("^outline%.") ~= nil
        or (path:find("^highlight%.") ~= nil and path ~= "highlight.boss_target.mode")
        or path:find("^unit_dispel_overlay%.") ~= nil
end
local function Meta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    resolved.settingKey = resolved.settingKey or BAR_SETTING_BY_PATH[path]
    resolved.actionKey = resolved.actionKey or BAR_ACTION_BY_PATH[path]
    local kind = classification or "setting"
    if (kind == "setting" or kind == "action") and not resolved.settingKey and not resolved.actionKey
        and IsDynamicBarPath(path)
    then
        resolved.assistantDisposition = resolved.assistantDisposition or "dynamic"
        resolved.assistantDispositionReason = resolved.assistantDispositionReason
            or "The exact DB and Registry target is selected by the explicit Bars scope; Shared, unit, Party, and Raid scopes own distinct setting keys."
        resolved.assistantSettingKeys = resolved.assistantSettingKeys or BAR_DYNAMIC_SETTING_KEYS_BY_PATH[path]
        resolved.assistantSettingKeyPatterns = resolved.assistantSettingKeyPatterns
            or BAR_DYNAMIC_SETTING_PATTERNS_BY_PATH[path]
        local suffix = BAR_DYNAMIC_SETTING_SUFFIX_BY_PATH[path]
        if suffix and not resolved.assistantSettingKeyPatterns then
            resolved.assistantSettingKeyPatterns = { "^barScope%.[%w_]+%." .. suffix .. "$" }
        end
    end
    return ControlMeta("opt_bars", "global", path, classification, resolved)
end
local function RegisterSegment(segment, path, values)
    RegisterControl(segment, Meta(path, "ephemeral"), nil, "segment", values)
    if segment and type(segment.buttons) == "table" then
        for i = 1, #segment.buttons do
            local item = values and values[i] or {}
            RegisterControl(segment.buttons[i], Meta(path .. ".option." .. tostring(item.value), "ephemeral"),
                item.text or item.label or item.value or "", "button")
        end
    end
    return segment
end
local HIGHLIGHT_ORDER_KEYS = { "dispel", "aggro", "purge", "bossTarget" }
local HIGHLIGHT_ORDER_ALLOWED = { dispel = true, aggro = true, purge = true, bossTarget = true }
local HIGHLIGHT_ORDER_VALUES = {}
local function BuildHighlightOrderValues(prefix, used)
    if #prefix == #HIGHLIGHT_ORDER_KEYS then
        local value = table.concat(prefix, ",")
        HIGHLIGHT_ORDER_VALUES[#HIGHLIGHT_ORDER_VALUES + 1] = { value = value, text = value }
        return
    end
    for i = 1, #HIGHLIGHT_ORDER_KEYS do
        local key = HIGHLIGHT_ORDER_KEYS[i]
        if not used[key] then
            used[key], prefix[#prefix + 1] = true, key
            BuildHighlightOrderValues(prefix, used)
            prefix[#prefix], used[key] = nil, nil
        end
    end
end
BuildHighlightOrderValues({}, {})
local function ParseHighlightOrder(value)
    if type(value) ~= "string" then return nil end
    local order, used = {}, {}
    for token in value:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$")
        if token:lower() == "bosstarget" or token:lower() == "boss target" then token = "bossTarget"
        else token = token:lower() end
        if not HIGHLIGHT_ORDER_ALLOWED[token] or used[token] then return nil end
        used[token], order[#order + 1] = true, token
    end
    if #order ~= #HIGHLIGHT_ORDER_KEYS then return nil end
    return order
end
local HIGHLIGHT_ORDER_COMMAND = {
    kind = "dragrow",
    source = "global/highlight/priority/order",
    valueKind = "enum",
    values = HIGHLIGHT_ORDER_VALUES,
    get = function() return table.concat(PriorityOrder(), ",") end,
    set = function(value)
        local order = ParseHighlightOrder(value)
        if not order then return false end
        BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER")
        if CurrentBarsScope() == "shared" then
            G().hlPrioOrder = order
            G().highlightPrioOrder = order
        end
        return true
    end,
    canExecute = function() return true end,
}
local function RegisterDragRows(container, path)
    local rows = container and container.rows or {}
    local owner = rows[1] and rows[1].frame
    if owner then
        RegisterControl(owner, Meta(path .. ".order", "setting", {
            assistantSettingKeyPatterns = { "^barScope%.[%w_]+%.hlPrioOrder$" },
            command = HIGHLIGHT_ORDER_COMMAND,
        }), "Highlight priority order", "dragrow")
        -- The remaining visible rows are handles for the same atomic four-item
        -- order. They must resolve to one catalog owner, not four competing
        -- setting routes.
        if M.MarkRuntimeControlComponent then
            for i = 2, #rows do M.MarkRuntimeControlComponent(rows[i].frame, owner) end
        end
    end
    return container
end
local function AnyUnitFrameAuraEnabled()
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function") then return true end
    for i = 1, #UNITFRAME_DISPEL_AURA_UNITS do
        if model.UnitEnabled(UNITFRAME_DISPEL_AURA_UNITS[i]) then return true end
    end
    return false
end

-- Scope rules are shared by all page sections. Keeping them outside the page builder
-- prevents every widget callback from being routed through one giant closure.
local function SharedScope() return CurrentBarsScope() == "shared" end
local function GroupScope()
    local scope = CurrentBarsScope()
    return type(IsGFScope) == "function" and IsGFScope(scope)
        or scope == "gf_party" or scope == "gf_raid"
end
local function ScopedControls() return SharedScope() or ScopeHasOverride(CurrentBarsScope(), "hlOverride") end
local function HighlightControls() return CurrentBarsScope() ~= nil end
local function BorderTestScope()
    local scope = CurrentBarsScope()
    return scope == "gf_party" and "party" or scope == "gf_raid" and "raid" or scope
end

-- ApplyService owns batching, combat deferral and compatibility fallbacks.
-- The old page duplicated all of that logic in seven near-identical request functions.
local function RequestApply(method, reason, scope)
    local service = M.ApplyService or _G.MSUF_Menu2_ApplyService
    local request = service and service[method]
    if type(request) == "function" then return request(reason, scope) end
    return ApplyBars(reason)
end
local function RequestOutlineRuntime() return RequestApply("RequestBarOutline", "MSUF2_BAR_OUTLINE", CurrentBarsScope()) end
local function RequestAggroBorderRuntime() return RequestApply("RequestAggroBorder", "MSUF2_AGGRO_BORDER_RUNTIME", CurrentBarsScope()) end
local function RequestBossTargetBorderRuntime() return RequestApply("RequestBossTargetBorder", "MSUF2_BOSS_TARGET_BORDER_RUNTIME", "boss") end
local function RequestHighlightPriorityRuntime(reason)
    return RequestApply("RequestHighlightPriority", reason or "MSUF2_HIGHLIGHT_PRIORITY_RUNTIME", CurrentBarsScope())
end
local function RequestAllHighlightBorderRuntime()
    return RequestApply("RequestHighlightBorders", "MSUF2_ALL_HIGHLIGHT_BORDER_RUNTIME", CurrentBarsScope())
end
local function RequestDispelPurgeBorderRuntime()
    local result = RequestApply("RequestDispelPurgeBorder", "MSUF2_DISPEL_PURGE_BORDER_RUNTIME", CurrentBarsScope())
    for _, test in ipairs({
        { "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode" },
        { "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode" },
    }) do
        local setter = _G[test[2]]
        if _G[test[1]] and type(setter) == "function" then setter(true, BorderTestScope()) end
    end
    return result
end
local function RequestUnitDispelOverlayRuntime(reason)
    reason = reason or "MSUF2_UF_DISPEL_OVERLAY"
    local service = M.ApplyService or _G.MSUF_Menu2_ApplyService
    local request = service and service.RequestUnit
    if type(request) ~= "function" then return ApplyBars(reason) end
    local scope = CurrentBarsScope()
    if scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then
        return request(scope, reason, UNITFRAME_AURA_APPLY_OPTS)
    end
    local result = false
    for i = 1, #UNITFRAME_DISPEL_AURA_UNITS do
        result = request(UNITFRAME_DISPEL_AURA_UNITS[i], reason, UNITFRAME_AURA_APPLY_OPTS) ~= false or result
    end
    return result
end
local function ApplyRoundedRuntime()
    return RequestApply("RequestRoundedBars", "MSUF2_ROUNDED", CurrentBarsScope())
end

local function ShowRoundedReloadRequiredPopup()
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then
        if _G.print then _G.print(M.Tr("|cffffd700MSUF:|r Rounded frame texture changed. Reload the UI with /reload.")) end
        return
    end
    M.InstallStaticPopup("MSUF2_ROUNDED_RELOAD_REQUIRED", {
        text = M.Tr("Rounded frame texture was changed.\n\nA UI reload is required because this style rebuilds frame masks and protected frame visuals.\n\nReload now?"),
        button1 = _G.RELOAD or M.Tr("Reload"), hideOnEscape = false,
        OnAccept = function()
            if _G.InCombatLockdown and _G.InCombatLockdown() then
                if _G.print then _G.print(M.Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")) end
            elseif type(_G.ReloadUI) == "function" then
                _G.ReloadUI()
            end
        end,
    })
    _G.StaticPopup_Show("MSUF2_ROUNDED_RELOAD_REQUIRED")
end
local function SetRoundedBool(key, value, requireReload)
    value = value and true or false
    local bars = Bars()
    if bars[key] == value then return end
    bars[key] = value
    ApplyRoundedRuntime()
    if requireReload then ShowRoundedReloadRequiredPopup() end
end
local function RegisterRoundedSearch(control, label, extraKeywords, help, kind, meta)
    if not (control and type(M.RegisterSearchWidget) == "function") then return end
    local keywords = {
        "rounded texture", "rounded frame texture", "rounded frames", "round corners", "rounded corners",
        "bars rounded", "enable rounded frames", "disable rounded frames", "abgerundete frames", "runde kanten",
    }
    if type(extraKeywords) == "string" then
        for keyword in extraKeywords:gmatch("[^|]+") do keywords[#keywords + 1] = keyword end
    elseif type(extraKeywords) == "table" then
        for i = 1, #extraKeywords do keywords[#keywords + 1] = extraKeywords[i] end
    end
    local payload = {
        label = label, kind = kind or control._msuf2ControlKind or "toggle",
        anchor = control._msuf2Title or control._msuf2Label or control,
        values = { "On", "Off", "Enable", "Disable", "Einschalten", "Ausschalten" },
        keywords = keywords,
        help = help or "Controls the rounded frame texture style for unit frames, group frames, power bars, and mouseover highlights.",
    }
    if type(meta) == "table" then for key, value in pairs(meta) do payload[key] = value end end
    M.RegisterSearchWidget(control, payload)
end

-- This page preview intentionally remains lightweight; live unit/group previews are
-- refreshed by ApplyService. Descriptors remove the former texture-by-texture boilerplate.
local function CreateRoundedTexturePreview(parent, x, y, width)
    width = max(320, floor((tonumber(width) or 560) + 0.5))
    local card = W.ControlCard(parent, "Preview", nil, x, y, width, 88)
    if not card then return end
    local sample, sampleW, sampleH, powerH = CreateFrame("Frame", nil, card), min(440, max(280, width - 44)), 46, 8
    sample:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -40)
    sample:SetSize(sampleW, sampleH)
    card._msuf2RoundedPreviewSample = sample
    local regions = {
        { "bg", "BACKGROUND", -7, { 0.015, 0.020, 0.032, 0.96 }, function(t) t:SetAllPoints(sample) end },
        { "healthBg", "BORDER", -1, { 0.060, 0.070, 0.075, 1 }, function(texture)
            texture:SetPoint("TOPLEFT", sample)
            texture:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", 0, powerH)
        end },
        { "health", "ARTWORK", 1, { 0.70, 0.69, 0.30, 0.94 }, function(texture)
            texture:SetPoint("TOPLEFT", sample)
            texture:SetSize(floor(sampleW * 0.78 + 0.5), sampleH - powerH)
        end },
        { "powerBg", "ARTWORK", 2, { 0.090, 0.055, 0.115, 1 }, function(texture)
            texture:SetPoint("BOTTOMLEFT", sample)
            texture:SetPoint("BOTTOMRIGHT", sample)
            texture:SetHeight(powerH)
        end },
        { "power", "ARTWORK", 3, { 0.62, 0.12, 0.78, 1 }, function(texture)
            texture:SetPoint("BOTTOMLEFT", sample)
            texture:SetSize(floor(sampleW * 0.66 + 0.5), powerH)
        end },
        { "gloss", "ARTWORK", 4, { 1, 1, 1, 0.045 }, function(texture)
            texture:SetPoint("TOPLEFT", sample)
            texture:SetPoint("BOTTOMRIGHT", sample, "RIGHT", 0, -1)
        end },
    }
    local helpers = M.PreviewHelpers or {}
    for i = 1, #regions do
        local spec = regions[i]
        local tex = sample:CreateTexture(nil, spec[2], nil, spec[3])
        spec[5](tex)
        tex:SetColorTexture(unpack(spec[4]))
        if helpers.SnapOff then helpers.SnapOff(tex) end
        local mask = helpers.EnsureRoundedMask and helpers.EnsureRoundedMask(sample, spec[1], sample, tex, "_msuf2RoundedPreviewMasks", ROUNDED_PREVIEW_MASK)
        if helpers.SetMask then helpers.SetMask(sample, tex, mask, "_msuf2RoundedPreviewMasked") end
    end
    for _, textSpec in ipairs({ { "Mapkotwo", "LEFT", 10, 0.42 }, { "404K - 100.0%", "RIGHT", -10, 0.50 } }) do
        local label = T.Font(sample, "GameFontHighlightSmall", textSpec[1], T.colors.text)
        label:SetPoint(textSpec[2], sample, textSpec[2], textSpec[3], 4)
        label:SetWidth(floor(sampleW * textSpec[4]))
        label:SetJustifyH(textSpec[2])
        if label.SetShadowOffset then label:SetShadowOffset(1, -1) end
    end
    for i = 1, 2 do
        local edge = sample:CreateTexture(nil, "OVERLAY", nil, 6)
        edge:SetTexture(ROUNDED_PREVIEW_EDGE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        edge:SetPoint("TOPLEFT", sample, "TOPLEFT", -i, i)
        edge:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", i, -i)
        edge:SetVertexColor(0, 0, 0, 1)
        if helpers.SnapOff then helpers.SnapOff(edge) end
    end
    function card:RefreshRoundedPreview() sample:SetAlpha(ReadB("roundedFramesEnabled", false) == true and 1 or 0.62) end
    card:RefreshRoundedPreview()
    return card
end

local function NormalizeDispelTrigger(value)
    local normalize = _G.MSUF_NormalizeDispelBorderTrigger
    if type(normalize) == "function" then return normalize(value) end
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    return "BY_ME"
end
local function NormalizeUnitDispelOverlayTrigger(value)
    local normalize = _G.MSUF_NormalizeUnitDispelOverlayTrigger
    if type(normalize) == "function" then return normalize(value) end
    if value == "BORDER" or value == "INHERIT" or value == "SAME" then return "BORDER" end
    return NormalizeDispelTrigger(value)
end
local function NormalizeAggroMode(value)
    value = tostring(value or "ALL"):upper()
    if value == "TANK_ONLY" then return "TANK" end
    if value == "HEALER_ONLY" then return "HEALER" end
    return (value == "NON_TANK" or value == "HEALER" or value == "TANK") and value or "ALL"
end

local function GradientControlsActive() return ScopedControls() end
local function TextureControlsActive() return SharedScope() or GroupScope() and ScopedControls() end
local POWER_GRADIENT_DIR_KEYS = {
    LEFT = "powerGradientDirLeft",
    RIGHT = "powerGradientDirRight",
    UP = "powerGradientDirUp",
    DOWN = "powerGradientDirDown",
}
local function GradientDirectionKeys(kind)
    return kind == "power" and POWER_GRADIENT_DIR_KEYS or GRADIENT_DIR_KEYS
end
local function CurrentGradientDirectionsForScope(kind)
    local keys = GradientDirectionKeys(kind)
    if kind == "power" then
        local hasPower, hasLegacy = false, false
        for direction, key in pairs(POWER_GRADIENT_DIR_KEYS) do
            hasPower = hasPower or GradientScopeHasExplicit(key)
            hasLegacy = hasLegacy or GradientScopeHasExplicit(GRADIENT_DIR_KEYS[direction])
        end
        if not hasPower and hasLegacy then keys = GRADIENT_DIR_KEYS end
    end
    local directions, any = {}, false
    for direction, key in pairs(keys) do
        directions[direction] = GradientScopeGet(key, false) == true
        any = any or directions[direction]
    end
    if not any then
        local directionKey = kind == "power" and "powerGradientDirection" or "gradientDirection"
        local legacyKey = kind == "power" and "gradientDirection" or nil
        local legacy = GradientScopeGet(directionKey, "RIGHT", legacyKey)
        directions[keys[legacy] and legacy or "RIGHT"] = true
    end
    return directions
end
local function FreezePowerGradientScope()
    local current = CurrentGradientDirectionsForScope("power")
    for direction, key in pairs(POWER_GRADIENT_DIR_KEYS) do
        if not GradientScopeHasExplicit(key) then GradientScopeSet(key, current[direction] == true) end
    end
    if not GradientScopeHasExplicit("powerGradientStrength") then
        GradientScopeSet("powerGradientStrength", GradientScopeGet("powerGradientStrength", 0.45, "gradientStrength"))
    end
end
local function ToggleGradientDirectionForScope(kind, direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    if kind == "health" then FreezePowerGradientScope() end
    local keys = GradientDirectionKeys(kind)
    local directions = CurrentGradientDirectionsForScope(kind)
    directions[direction] = not directions[direction]
    local any = false
    for candidate in pairs(GRADIENT_DIR_KEYS) do any = any or directions[candidate] == true end
    if not any then directions[direction] = true end
    for candidate, key in pairs(keys) do GradientScopeSet(key, directions[candidate] == true) end
    GradientScopeSet(kind == "power" and "powerGradientDirection" or "gradientDirection", direction)
end
local function ApplyGradientRuntime(reason, kind)
    local enabledKey = kind == "power" and "enablePowerGradient" or "enableGradient"
    local strengthKey = kind == "power" and "powerGradientStrength" or "gradientStrength"
    local legacyStrengthKey = kind == "power" and "gradientStrength" or nil
    if GradientScopeGet(enabledKey, false) == true then
        local strength = tonumber(GradientScopeGet(strengthKey, 0.45, legacyStrengthKey))
        if not (strength and strength > 0) then GradientScopeSet(strengthKey, 0.45) end
    end
    return RequestApply("RequestBarGradients", reason or "MSUF2_GRADIENT", CurrentBarsScope())
end

local function SetOutlineRGB(entry, r, g, b)
    if entry.barOutlineColorR == r and entry.barOutlineColorG == g and entry.barOutlineColorB == b
        and entry.barOutlineColorA == 1 and entry.barOutlineColorMode == nil then return false end
    entry.barOutlineColorMode = nil
    entry.barOutlineColorR, entry.barOutlineColorG, entry.barOutlineColorB, entry.barOutlineColorA = r, g, b, 1
    return true
end
local function SetOutlineColorForScope(r, g, b)
    r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
    local scope, keys = CurrentBarsScope(), ScopeDBKeys(CurrentBarsScope())
    if scope == "shared" or not keys then return SetOutlineRGB(G(), r, g, b) end
    ScopeSetOverride(scope, "hlOverride", true)
    local db, changed = DB(), false
    for i = 1, #keys do
        db[keys[i]] = db[keys[i]] or {}
        changed = SetOutlineRGB(db[keys[i]], r, g, b) or changed
    end
    return changed
end
local function GeneralBarBackgroundTextureKey()
    local general = G()
    return general.barBackgroundTexture == nil and (general.barBgTexture or "") or general.barBackgroundTexture
end
local function BarTextureForScope()
    return not SharedScope() and not GroupScope() and ReadG("barTexture", "Blizzard")
        or BarScopeGet("barTexture", ReadG("barTexture", "Blizzard"))
end
local function SetBarTextureForScope(value)
    value = value or "Blizzard"
    if not SharedScope() and not GroupScope() or BarTextureForScope() == value then return false end
    BarScopeSet("barTexture", value, "MSUF2_BAR_TEXTURE")
    return true
end
local function BarBackgroundTextureForScope()
    local scope = CurrentBarsScope()
    if scope ~= "shared" and not GroupScope() then return GeneralBarBackgroundTextureKey() end
    if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
        local db, keys = DB(), ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if entry and entry.barBackgroundTexture ~= nil then return entry.barBackgroundTexture end
            if entry and entry.barBgTexture ~= nil then return entry.barBgTexture end
        end
    end
    return GeneralBarBackgroundTextureKey()
end
local function SetBarBackgroundTextureForScope(value)
    value = value or ""
    local scope, keys = CurrentBarsScope(), ScopeDBKeys(CurrentBarsScope())
    if scope == "shared" then
        local general = G()
        if general.barBackgroundTexture == value then return false end
        general.barBackgroundTexture = value
        return true
    end
    if not GroupScope() then return false end
    if not keys then
        local general = G()
        if general.barBackgroundTexture == value then return false end
        general.barBackgroundTexture = value
        return true
    end
    ScopeSetOverride(scope, "hlOverride", true)
    local db, changed = DB(), false
    for i = 1, #keys do
        db[keys[i]] = db[keys[i]] or {}
        changed = db[keys[i]].barBackgroundTexture ~= value or db[keys[i]].barBgTexture ~= value or changed
        db[keys[i]].barBackgroundTexture, db[keys[i]].barBgTexture = value, value
    end
    return changed
end
local function BuildScopeSection(ctx, b)
    local scopeValues = GP.SCOPE_VALUES
    local function RefreshBarsPage(reason)
        if M.RequestRefresh then
            M.RequestRefresh(ctx, reason)
        elseif M.Refresh then
            M.Refresh(ctx)
        elseif M.SelectPage then
            M.SelectPage(ctx.key)
        end
    end
    GP.BuildScopeOverrideSection(ctx, b, {
        values = scopeValues,
        selectorMeta = Meta("scope.selector", "ephemeral"),
        selectorOptionMeta = function(value) return Meta("scope.selector.option." .. tostring(value), "ephemeral") end,
        overrideMeta = Meta("scope.override.enabled"),
        resetMeta = Meta("scope.overrides.reset", "action"),
        getValue = function() return CurrentBarsScope() end,
        setValue = function(v)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(v)
            RefreshBorderTestModes()
            RefreshBarsPage("bars-scope-change")
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "hlOverride")
        end,
        getOverride = function()
            local key = CurrentBarsScope()
            return ScopeHasOverride(key, "hlOverride")
        end,
        setOverride = function(v)
            local key = CurrentBarsScope()
            if key ~= "shared" then
                ScopeSetOverride(key, "hlOverride", v)
                ApplyBars("MSUF2_BARS_OVERRIDE")
            end
            RefreshBarsPage("bars-scope-override")
        end,
        reset = function()
            for i = 1, #scopeValues do
                local key = scopeValues[i].value
                if key ~= "shared" then ScopeSetOverride(key, "hlOverride", false) end
            end
            ApplyBars("MSUF2_BARS_RESET_OVERRIDES")
            RefreshBarsPage("bars-reset-overrides")
        end,
        hint = "Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.",
        updateHint = function(hint, current, active, shared)
            if shared then
                hint:SetText("Textures are shared except Party/Raid group-frame overrides. Gradients can be customized per unit or group scope.")
            elseif IsGFScope(current) and ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This group scope can use custom textures and gradients. Raid also applies to Mythic Raid.")
            elseif ScopeHasOverride(current, "hlOverride") then
                hint:SetText("This scope can use custom gradients and bar settings. Textures still follow Shared.")
            else
                hint:SetText("This scope follows Shared bar settings. Turn on custom settings here when this scope needs different gradients or bar settings.")
            end
        end,
    })
end

local function BuildTextureSection(ctx, b)
    local compactTextures = (ctx.width or 720) < 560
    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 458 or 330, true)
    local leftX, topY = 14, -42
    local rightX = compactTextures and leftX or math.max(340, math.floor((ctx.width or 720) * 0.50))
    local leftW = compactTextures and math.max(220, (ctx.width or 720) - 42) or math.min(300, math.max(220, rightX - 48))
    local gradientY = compactTextures and (topY - 126) or topY
    local function BindTextureDropdown(label, values, getValue, setValue, y, path)
        local control = W.Dropdown(textures, label, values, leftW)
        M.BindDropdownWidget(ctx, control, getValue, setValue, Meta(path))
        W.MoveWidget(control, textures, leftX, y, leftW, "LEFT")
        return control
    end
    local barTexture = BindTextureDropdown("Bar textures (SharedMedia)", function() return TextureValues(nil) end, BarTextureForScope,
        function(v)
            if SetBarTextureForScope(v) then
                ApplyBars("MSUF2_BAR_TEXTURE")
            end
        end, topY, "textures.foreground")
    local bgTexture = BindTextureDropdown("Background texture", function() return TextureValues("Use foreground texture") end, BarBackgroundTextureForScope,
        function(v)
            if SetBarBackgroundTextureForScope(v) then
                ApplyBars("MSUF2_BAR_BG_TEXTURE")
            end
        end, topY - 54, "textures.background")
    local gradLabel = T.Font(textures, "GameFontHighlightSmall", M.Tr("Gradient"), T.colors.muted)
    gradLabel:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX, gradientY)
    local SyncGradientControls = M.RefreshProxy()
    local function BindGradientToggle(label, y, width, key, reason, kind)
        local control = W.ToggleAt(textures, label, rightX, y, width)
        M.BindBoolWidget(ctx, control,
            function() return GradientScopeGet(key, false) == true end,
            function(v)
                GradientScopeSet(key, v and true or false)
                ApplyGradientRuntime(reason, kind)
                SyncGradientControls()
            end,
            Meta("gradient." .. key))
        return control
    end
    local colors = T.Button(textures, "Gradient colors", 142, 22)
    colors:SetPoint("TOPLEFT", textures, "TOPLEFT", rightX + 88, gradientY + 8)
    T.CenterButtonLabel(colors)
    if M.AddTooltip then
        M.AddTooltip(colors, "Gradient colors", "Open Colors > Bar Gradient Colors for separate Health and Power gradient colors in the selected Bars scope.", { hook = true })
    end
    colors:SetScript("OnClick", function()
        _G.MSUF_EM2_MenuFocusRequest = {
            pageKey = "opt_colors",
            sectionId = "colors_bar_gradients",
            explicit = true,
            consumed = false,
            source = "bars-gradient-colors",
            changedAt = GetTime and GetTime() or 0,
        }
        if M.SelectPage and M.SelectPage("opt_colors") == false then _G.MSUF_EM2_MenuFocusRequest = nil end
    end)
    RegisterControl(colors, Meta("gradient.colors", "navigation", { navigationKey = "opt_colors" }), "Gradient colors", "button")
    local hpY = gradientY - 28
    local powerY = gradientY - 138
    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local compactStrengthW = math.max(150, padX - rightX - 14)
    local hpGradient = BindGradientToggle("Health gradient", hpY, compactTextures and 150 or 180, "enableGradient", "MSUF2_HP_GRADIENT", "health")
    local powerGradient = BindGradientToggle("Power gradient", powerY, compactTextures and 170 or 190, "enablePowerGradient", "MSUF2_POWER_GRADIENT", "power")
    local function BindGradientStrength(kind, y, key, legacyKey, path, reason)
        local label = kind == "power" and "Power strength" or "Health strength"
        local control = W.Slider(textures, label, 0, 1, 0.05, 220)
        M.BindNumberWidget(ctx, control,
            function() return tonumber(GradientScopeGet(key, 0.45, legacyKey)) or 0.45 end,
            function(v)
                if kind == "health" then FreezePowerGradientScope() end
                GradientScopeSet(key, tonumber(v) or 0.45)
                ApplyGradientRuntime(reason, kind)
            end,
            0.45,
            Meta(path))
        W.MoveWidget(control, textures, rightX, y, compactTextures and compactStrengthW or 220, "LEFT")
        return control
    end
    local hpStrength = BindGradientStrength("health", hpY - 36, "gradientStrength", nil,
        "gradient.health.strength", "MSUF2_HP_GRADIENT_STRENGTH")
    local powerStrength = BindGradientStrength("power", powerY - 36, "powerGradientStrength", "gradientStrength",
        "gradient.power.strength", "MSUF2_POWER_GRADIENT_STRENGTH")
    local padW, padH = 104, 78
    local padButtonW, padButtonH = 22, 18
    local directionButtons = { health = {}, power = {} }
    local pads = {}
    local function BuildDirectionPad(kind, y)
        local pad = T.Panel(textures, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
        pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, y)
        pad:SetSize(padW, padH)
        local center = pad:CreateTexture(nil, "ARTWORK")
        center:SetPoint("CENTER", pad, "CENTER", 0, 0)
        center:SetSize(10, 10)
        local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
        center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
        local function PadButton(text, value, x, buttonY)
            local btn = T.Button(pad, text, padButtonW, padButtonH)
            btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, buttonY)
            T.CenterButtonLabel(btn)
            btn:SetScript("OnClick", function()
                ToggleGradientDirectionForScope(kind, value or "RIGHT")
                ApplyGradientRuntime(kind == "power" and "MSUF2_POWER_GRADIENT_DIRECTION" or "MSUF2_HP_GRADIENT_DIRECTION", kind)
                SyncGradientControls()
            end)
            RegisterControl(btn, Meta("gradient." .. kind .. ".direction." .. tostring(value), "action"), text, "button")
            directionButtons[kind][value] = btn
        end
        local centerX = (padW - padButtonW) * 0.5
        local centerY = (padH - padButtonH) * 0.5
        local sideOffset = 23
        PadButton("^", "UP", centerX, -(centerY - sideOffset))
        PadButton("<", "LEFT", centerX - sideOffset, -centerY)
        PadButton(">", "RIGHT", centerX + sideOffset, -centerY)
        PadButton("v", "DOWN", centerX, -(centerY + sideOffset))
        pads[kind] = pad
    end
    BuildDirectionPad("health", hpY - 2)
    BuildDirectionPad("power", powerY - 2)
    local textureControls = { barTexture, bgTexture }
    local gradientControls = { hpGradient, powerGradient }
    M.TrackRefresh(ctx, SyncGradientControls(function()
        local hpDirections = CurrentGradientDirectionsForScope("health")
        local powerDirections = CurrentGradientDirectionsForScope("power")
        local textureControlsActive = TextureControlsActive()
        local gradientControlsActive = GradientControlsActive()
        local hpActive = gradientControlsActive and GradientScopeGet("enableGradient", false) == true
        local powerActive = gradientControlsActive and GradientScopeGet("enablePowerGradient", false) == true
        SetControlsEnabled(textureControls, textureControlsActive)
        SetControlsEnabled(gradientControls, gradientControlsActive)
        SetControlEnabled(hpStrength, hpActive)
        SetControlEnabled(powerStrength, powerActive)
        pads.health:SetAlpha(hpActive and 1 or 0.45)
        pads.power:SetAlpha(powerActive and 1 or 0.45)
        for value, btn in pairs(directionButtons.health) do
            btn:SetActive(hpDirections[value] == true)
            SetControlEnabled(btn, hpActive)
        end
        for value, btn in pairs(directionButtons.power) do
            btn:SetActive(powerDirections[value] == true)
            SetControlEnabled(btn, powerActive)
        end
    end))
end

local function BuildAbsorbSectionLegacy(ctx, b)
    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 460, true)
    local absorbW = absorb._msuf2Width or ctx.width or 720
    local absorbLeftX = 30
    local absorbRightX = max(430, min(560, floor(absorbW * 0.52)))
    local absorbLeftW = max(300, min(380, absorbRightX - absorbLeftX - 58))
    local absorbRightW = max(300, min(420, absorbW - absorbRightX - 42))
    W.LabelAt(absorb, "Display", absorbLeftX, -42, absorbLeftW, "GameFontNormalSmall", T.colors.accent)
    local absorbMode = W.Dropdown(absorb, "Display mode", VT(1, "Absorb off", 2, "Absorb bar"), absorbLeftW)
    local function ReadAbsorbDisplayMode()
        local mode = tonumber(BarScopeGet("absorbTextMode", 2)) or 2
        return (mode == 1 or mode == 4) and 1 or 2
    end
    local function ApplyAbsorbRuntime(reason) ApplyBars(reason) end
    local SyncAbsorbControls = M.RefreshProxy()
    local function AbsorbDefault(value) return type(value) == "function" and value() or value end
    local function ResolveBarPreviewTexture(key, fallback)
        key = type(key) == "string" and key ~= "" and key or fallback
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            local texture = resolve(key)
            if type(texture) == "string" and texture ~= "" then return texture end
        end
        return "Interface\\Buttons\\WHITE8X8"
    end
    local function AbsorbAnchorPreview(item)
        local foregroundKey = BarTextureForScope()
        local backgroundKey = BarBackgroundTextureForScope()
        local absorbKey = BarScopeGet("absorbBarTexture", ReadG("absorbBarTexture", ""))
        local opacity = tonumber(BarScopeGet("absorbBarOpacity", ReadG("absorbBarOpacity", 0.75))) or 0.75
        return {
            mode = tonumber(item and item.value) or 3,
            dualDirection = true,
            showAbsorbEdgeGlow = ReadGBool("fullHealthAbsorbStripe", false),
            healthFraction = tonumber(item and item.value) == 4 and 0.84 or 0.68,
            overlayFraction = 0.22,
            healthTexture = ResolveBarPreviewTexture(foregroundKey, "Blizzard"),
            backgroundTexture = ResolveBarPreviewTexture(backgroundKey, foregroundKey),
            overlayTexture = ResolveBarPreviewTexture(absorbKey, foregroundKey),
            healthColor = { 0.12, 0.62, 0.25, 1 },
            backgroundColor = { 0.025, 0.075, 0.045, 0.92 },
            overlayColor = {
                tonumber(BarScopeGet("absorbBarColorR", ReadG("absorbBarColorR", 1))) or 1,
                tonumber(BarScopeGet("absorbBarColorG", ReadG("absorbBarColorG", 1))) or 1,
                tonumber(BarScopeGet("absorbBarColorB", ReadG("absorbBarColorB", 1))) or 1,
                max(0, min(1, opacity)),
            },
        }
    end
    local function AbsorbAnchorValues()
        return {
            { value = 1, text = "Anchor to left side", previewKind = "barOverlay", barPreview = AbsorbAnchorPreview },
            { value = 2, text = "Anchor to right side", previewKind = "barOverlay", barPreview = AbsorbAnchorPreview },
            { value = 3, text = "Follow HP bar", previewKind = "barOverlay", barPreview = AbsorbAnchorPreview },
            { value = 4, text = "Follow HP bar (overflow)", previewKind = "barOverlay", barPreview = AbsorbAnchorPreview },
            { value = 5, text = "Reverse from max", previewKind = "barOverlay", barPreview = AbsorbAnchorPreview },
        }
    end
    local function BindAbsorbDropdown(label, values, key, defaultValue, reason, x, y, width, numeric)
        local control = W.Dropdown(absorb, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local fallback = AbsorbDefault(defaultValue)
                local value = BarScopeGet(key, fallback)
                return numeric and (tonumber(value) or fallback) or value
            end,
            function(v)
                local fallback = AbsorbDefault(defaultValue)
                BarScopeSet(key, numeric and (tonumber(v) or fallback) or (v or fallback), reason, true)
                ApplyAbsorbRuntime(reason)
                SyncAbsorbControls()
            end,
            Meta("absorb." .. key))
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BindAbsorbSlider(label, minValue, maxValue, step, key, defaultValue, reason, x, y, width)
        local control = W.Slider(absorb, label, minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                BarScopeSet(key, tonumber(v) or defaultValue, reason, true)
                ApplyAbsorbRuntime(reason)
                SyncAbsorbControls()
            end,
            defaultValue,
            Meta("absorb." .. key))
        W.MoveWidget(control, absorb, x, y, width, "LEFT")
        return control
    end
    local function BuildAbsorbControlSpecs(specs)
        return M.BuildControlSpecs(specs, {
            dropdown = function(s, i) return BindAbsorbDropdown(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10]), s[11] or s[4] or i end,
            slider = function(s, i) return BindAbsorbSlider(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[6] or i end,
        })
    end
    M.BindDropdownWidget(ctx, absorbMode,
        ReadAbsorbDisplayMode,
        function(v)
            local mode = (tonumber(v) == 1) and 1 or 2
            BarScopeSet("absorbTextMode", mode, "MSUF2_ABSORB_MODE", true)
            ApplyAbsorbRuntime("MSUF2_ABSORB_MODE")
            SyncAbsorbControls()
        end,
        Meta("absorb.display_mode"))
    W.MoveWidget(absorbMode, absorb, absorbLeftX, -70, absorbLeftW, "LEFT")
    local predictionAnchors = VT(
        1, "Anchor to left side", 2, "Anchor to right side", 3, "Follow HP bar",
        4, "Follow HP bar (overflow)", 5, "Reverse from max")
    local absorbControls = BuildAbsorbControlSpecs({
        { "dropdown", "Absorb bar anchoring", AbsorbAnchorValues, "absorbAnchorMode", 2, "MSUF2_ABSORB_ANCHOR", absorbLeftX, -124, absorbLeftW, true, "anchor" },
        { "dropdown", "Heal prediction anchoring", predictionAnchors, "healPredAnchorMode", 3, "MSUF2_HEALPRED_ANCHOR", absorbLeftX, -240, absorbLeftW, true, "healAnchor" },
        { "slider", "Absorb bar opacity", 0, 1, 0.05, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY", absorbLeftX, -294, absorbLeftW, "opacity" },
        { "dropdown", "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, "absorbBarTexture", function() return ReadG("absorbBarTexture", "") end, "MSUF2_ABSORB_TEXTURE", absorbRightX, -70, absorbRightW, nil, "texture" },
        { "dropdown", "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, "healAbsorbBarTexture", function() return ReadG("healAbsorbBarTexture", "") end, "MSUF2_HEAL_ABSORB_TEXTURE", absorbRightX, -124, absorbRightW, nil, "healTexture" },
        { "slider", "Heal-absorb bar opacity", 0, 1, 0.05, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY", absorbRightX, -348, absorbRightW, "healOpacity" },
    })
    local healPredToggle = W.ToggleAt(absorb, "Heal Prediction Overlay", absorbLeftX, -186, absorbLeftW)
    M.BindBoolWidget(ctx, healPredToggle,
        function()
            if GroupScope() then return BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true end
            return ReadGBool("showSelfHealPrediction", false)
        end,
        function(v)
            if GroupScope() then
                BarScopeSet("healPredEnabled", v and true or false, "MSUF2_GF_HEALPRED", true)
                ApplyBars("MSUF2_GF_HEALPRED")
                SyncAbsorbControls()
                return
            end
            G().showSelfHealPrediction = v and true or false
            Call("MSUF_RefreshSelfHealPredUnitEvent")
            ApplyBars("MSUF2_SELF_HEAL")
            SyncAbsorbControls()
        end,
        Meta("absorb.heal_prediction.enabled"))
    W.LabelAt(absorb, "Textures", absorbRightX, -42, absorbRightW, "GameFontNormalSmall", T.colors.accent)
    local absorbTest = W.ToggleAt(absorb, "Test prediction bars", absorbRightX, -186, absorbRightW)
    M.BindBoolWidget(ctx, absorbTest,
        function() return _G.MSUF_AbsorbTextureTestMode and true or false end,
        function(v) SetAbsorbTextureTest(v and true or false) end,
        Meta("absorb.preview.test", "ephemeral"))
    local overAbsorbOverlay = W.ToggleAt(absorb, "Over-absorb overlay", absorbRightX, -240, absorbRightW)
    M.BindBoolWidget(ctx, overAbsorbOverlay,
        function() return BarScopeGet("overAbsorbOverlay", ReadGBool("overAbsorbOverlay", false)) == true end,
        function(v)
            BarScopeSet("overAbsorbOverlay", v and true or false, "MSUF2_OVER_ABSORB_OVERLAY", true)
            ApplyAbsorbRuntime("MSUF2_OVER_ABSORB_OVERLAY")
            SyncAbsorbControls()
        end,
        Meta("absorb.over_absorb_overlay"))
    local fullHealthStripe = W.ToggleAt(absorb, "Full-health absorb stripe", absorbRightX, -294, absorbRightW)
    M.BindBoolWidget(ctx, fullHealthStripe,
        function() return ReadGBool("fullHealthAbsorbStripe", false) end,
        function(v)
            G().fullHealthAbsorbStripe = v and true or false
            ApplyAbsorbRuntime("MSUF2_FULL_HEALTH_ABSORB_STRIPE")
            SyncAbsorbControls()
        end,
        Meta("absorb.full_health_stripe"))
    if M.AddTooltip then
        M.AddTooltip(fullHealthStripe, "Full-health absorb stripe",
            "Show Blizzard's shield edge when health is full and an absorb is active.", { hook = true })
    end
    local absorbBarControls = { absorbControls.anchor, absorbControls.texture, absorbControls.healTexture, absorbControls.opacity, absorbControls.healOpacity, overAbsorbOverlay }
    M.TrackRefresh(ctx, SyncAbsorbControls(function()
        local mode = ReadAbsorbDisplayMode()
        local showBar = mode == 2
        local scopedActive = ScopedControls()
        local sharedActive = SharedScope()
        local groupScope = GroupScope()
        local healPredOn
        if groupScope then
            healPredOn = BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true
        else
            healPredOn = ReadGBool("showSelfHealPrediction", false)
        end
        SetControlEnabled(absorbMode, scopedActive)
        SetControlsEnabled(absorbBarControls, scopedActive and showBar)
        SetControlEnabled(fullHealthStripe, showBar)
        SetControlEnabled(absorbTest, true)
        SetControlEnabled(healPredToggle, groupScope and scopedActive or sharedActive)
        SetControlEnabled(absorbControls.healAnchor, scopedActive and healPredOn)
        if absorbControls.anchor.RefreshPreview then absorbControls.anchor:RefreshPreview() end
    end))
end

local function BuildTempMaxHealthSection(ctx, b)
    local sectionW = ctx.width or 720
    local compact = sectionW < 700
    local section = b:CollapsibleSection("bars_temp_max_health", "Maximum Health Loss", compact and 482 or 294, true)
    sectionW = section._msuf2Width or sectionW
    local leftX = compact and 20 or 30
    local rightX = compact and 20 or max(390, min(540, floor(sectionW * 0.52)))
    local leftW = compact and max(240, sectionW - 40) or max(280, rightX - leftX - 54)
    local rightW = compact and leftW or max(280, sectionW - rightX - 32)
    local SyncControls = M.RefreshProxy()

    W.Text(section, "Shows the part of maximum health that is temporarily unavailable.",
        20, -36, sectionW - 40, T.colors.muted)

    local function Refresh(reason)
        local scope = CurrentBarsScope()
        if type(_G.MSUF_RefreshTempMaxHealth) == "function" then
            _G.MSUF_RefreshTempMaxHealth(scope, reason or "MSUF2_TEMP_MAX_HEALTH")
        else
            ApplyBars(reason or "MSUF2_TEMP_MAX_HEALTH")
        end
        if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh(reason or "MSUF2_TEMP_MAX_HEALTH")
        end
        if type(M.RefreshGFNativePreviews) == "function" then
            M.RefreshGFNativePreviews(reason or "MSUF2_TEMP_MAX_HEALTH")
        end
        SyncControls()
    end

    local enabled = W.ToggleAt(section, "Show maximum-health loss", leftX, -78, leftW)
    M.BindBoolWidget(ctx, enabled,
        function() return BarScopeGet("tempMaxHealthEnabled", ReadGBool("tempMaxHealthEnabled", false)) == true end,
        function(value)
            BarScopeSet("tempMaxHealthEnabled", value and true or false, "MSUF2_TEMP_MAX_HEALTH_ENABLED", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_ENABLED")
        end,
        Meta("temp_max_health.enabled"))

    local textureY = compact and -132 or -132
    local texture = W.Dropdown(section, "Texture", function() return TextureValues("Use foreground texture") end, leftW)
    M.BindDropdownWidget(ctx, texture,
        function() return BarScopeGet("tempMaxHealthTexture", ReadG("tempMaxHealthTexture", "Solid")) end,
        function(value)
            BarScopeSet("tempMaxHealthTexture", value or "", "MSUF2_TEMP_MAX_HEALTH_TEXTURE", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_TEXTURE")
        end,
        Meta("temp_max_health.texture"))
    W.MoveWidget(texture, section, leftX, textureY, leftW, "LEFT")

    local colorY = compact and -204 or -204
    local color = W.Color(section, "Loss color")
    W.MoveWidget(color, section, leftX, colorY)
    M.BindColor(ctx, color,
        function()
            return tonumber(BarScopeGet("tempMaxHealthColorR", ReadG("tempMaxHealthColorR", 0.70))) or 0.70,
                tonumber(BarScopeGet("tempMaxHealthColorG", ReadG("tempMaxHealthColorG", 0.10))) or 0.10,
                tonumber(BarScopeGet("tempMaxHealthColorB", ReadG("tempMaxHealthColorB", 0.10))) or 0.10
        end,
        function(r, g, b)
            BarScopeSet("tempMaxHealthColorR", tonumber(r) or 0.70, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorG", tonumber(g) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            BarScopeSet("tempMaxHealthColorB", tonumber(b) or 0.10, "MSUF2_TEMP_MAX_HEALTH_COLOR", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_COLOR")
        end,
        Meta("temp_max_health.color"))

    local opacityY = compact and -266 or -78
    local opacity = W.Slider(section, "Overlay opacity", 0.05, 1, 0.05, rightW)
    M.BindNumberWidget(ctx, opacity,
        function() return tonumber(BarScopeGet("tempMaxHealthOpacity", ReadG("tempMaxHealthOpacity", 1))) or 1 end,
        function(value)
            BarScopeSet("tempMaxHealthOpacity", tonumber(value) or 1, "MSUF2_TEMP_MAX_HEALTH_OPACITY", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_OPACITY")
        end,
        1, Meta("temp_max_health.opacity"))
    W.MoveWidget(opacity, section, rightX, opacityY, rightW, "LEFT")

    local backgroundY = compact and -330 or -142
    local background = W.Slider(section, "Background opacity", 0, 1, 0.05, rightW)
    M.BindNumberWidget(ctx, background,
        function()
            return tonumber(BarScopeGet("tempMaxHealthBackgroundOpacity",
                ReadG("tempMaxHealthBackgroundOpacity", 0.65))) or 0.65
        end,
        function(value)
            BarScopeSet("tempMaxHealthBackgroundOpacity", tonumber(value) or 0.65,
                "MSUF2_TEMP_MAX_HEALTH_BACKGROUND", true)
            Refresh("MSUF2_TEMP_MAX_HEALTH_BACKGROUND")
        end,
        0.65, Meta("temp_max_health.background_opacity"))
    W.MoveWidget(background, section, rightX, backgroundY, rightW, "LEFT")

    local previewY = compact and -402 or -214
    local preview = W.ToggleAt(section, "Preview effect", rightX, previewY, rightW)
    M.BindBoolWidget(ctx, preview,
        function() return IsAbsorbTextureTestEnabled("tempMaxHealth") == true end,
        function(value) SetAbsorbTextureTest(value and true or false, "tempMaxHealth") end,
        Meta("temp_max_health.preview", "ephemeral"))

    local options = { texture, color, opacity, background }
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        local on = BarScopeGet("tempMaxHealthEnabled", ReadGBool("tempMaxHealthEnabled", false)) == true
        SetControlEnabled(enabled, scopedActive)
        SetControlsEnabled(options, scopedActive and on)
        SetControlEnabled(preview, true)
    end))
end

local function BuildAbsorbSection(ctx, b)
    local section = b:CollapsibleSection("bars_absorb", "Absorb Display", 414, true)
    local sectionW = section._msuf2Width or ctx.width or 720
    local leftX = 30
    local rightX = max(430, min(560, floor(sectionW * 0.52)))
    local leftW = max(300, min(380, rightX - leftX - 58))
    local rightW = max(300, min(420, sectionW - rightX - 42))
    local tabFrames = {}
    local tabValues = VT(
        "positive", "Absorb (positive)",
        "negative", "Absorb (negative)",
        "heal", "Heal Prediction")
    M.globalBarsAbsorbTabSelection = M.globalBarsAbsorbTabSelection or {}
    local function CurrentTab()
        local key = M.globalBarsAbsorbTabSelection[CurrentBarsScope()] or "positive"
        if key ~= "positive" and key ~= "negative" and key ~= "heal" then key = "positive" end
        return key
    end
    local positive, negative, heal = M.UnitSectionsShared.MakeTabFrames(
        section, -64, sectionW, tabFrames, "positive", "negative", "heal")
    local tabs = W.SegmentTabs(ctx, section, {
        label = "", values = tabValues, width = min(660, sectionW - 48),
        frames = tabFrames, defaultTab = "positive", get = CurrentTab,
        set = function(value) M.globalBarsAbsorbTabSelection[CurrentBarsScope()] = value or "positive" end,
        x = 20, y = -12,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, Meta("absorb.workspace_tab", "ephemeral"), "Absorb area", "segment")

    local SyncControls = M.RefreshProxy()
    local function Apply(reason)
        ApplyBars(reason)
        SyncControls()
    end
    local function TextureDefault(key)
        return function() return ReadG(key, "") end
    end
    local function ResolveDefault(value)
        return type(value) == "function" and value() or value
    end
    local function BindDropdown(parent, label, values, key, defaultValue, reason, x, y, width, numeric, path)
        local control = W.Dropdown(parent, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local fallback = ResolveDefault(defaultValue)
                local value = BarScopeGet(key, fallback)
                return numeric and (tonumber(value) or fallback) or value
            end,
            function(value)
                local fallback = ResolveDefault(defaultValue)
                BarScopeSet(key, numeric and (tonumber(value) or fallback) or (value or fallback), reason, true)
                Apply(reason)
            end,
            Meta(path or ("absorb." .. key)))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end
    local function BindSlider(parent, label, minValue, maxValue, step, key, defaultValue, reason, x, y, width, path)
        local control = W.Slider(parent, label, minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(value)
                BarScopeSet(key, tonumber(value) or defaultValue, reason, true)
                Apply(reason)
            end,
            defaultValue, Meta(path or ("absorb." .. key)))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end
    local function BindToggle(parent, label, key, defaultValue, reason, x, y, width, path, onSet)
        local control = W.ToggleAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return BarScopeGet(key, defaultValue) == true end,
            function(value)
                value = value and true or false
                BarScopeSet(key, value, reason, true)
                if onSet then onSet(value) end
                Apply(reason)
            end,
            Meta(path or ("absorb." .. key)))
        return control
    end
    local function BindTest(parent, category, x, y, width, path)
        local control = W.ToggleAt(parent, "Test prediction bars", x, y, width)
        M.BindBoolWidget(ctx, control,
            function() return IsAbsorbTextureTestEnabled(category) == true end,
            function(value) SetAbsorbTextureTest(value and true or false, category) end,
            Meta(path, "ephemeral"))
        return control
    end
    local function ResolveBarPreviewTexture(key, fallback)
        key = type(key) == "string" and key ~= "" and key or fallback
        local resolve = _G.MSUF_ResolveStatusbarTextureKey
        if type(resolve) == "function" then
            local texture = resolve(key)
            if type(texture) == "string" and texture ~= "" then return texture end
        end
        return "Interface\\Buttons\\WHITE8X8"
    end
    local function AnchorPreview(category)
        return function(item)
            local foregroundKey = BarTextureForScope()
            local backgroundKey = BarBackgroundTextureForScope()
            local mode = tonumber(item and item.value) or 3
            local textureKey, opacity, color, showAbsorbEdgeGlow
            if category == "negative" then
                textureKey = BarScopeGet("healAbsorbBarTexture", ReadG("healAbsorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("healAbsorbBarOpacity", ReadG("healAbsorbBarOpacity", 1))) or 1
                color = {
                    tonumber(ReadG("healAbsorbBarColorR", 0.70)) or 0.70,
                    tonumber(ReadG("healAbsorbBarColorG", 0)) or 0,
                    tonumber(ReadG("healAbsorbBarColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            elseif category == "heal" then
                textureKey = BarScopeGet("healPredictionBarTexture", ReadG("healPredictionBarTexture", ""))
                opacity = tonumber(BarScopeGet("healPredictionBarOpacity", ReadG("healPredictionColorA", 0.45))) or 0.45
                color = {
                    tonumber(ReadG("healPredictionColorR", 0)) or 0,
                    tonumber(ReadG("healPredictionColorG", 1)) or 1,
                    tonumber(ReadG("healPredictionColorB", 0)) or 0,
                    max(0, min(1, opacity)),
                }
            else
                textureKey = BarScopeGet("absorbBarTexture", ReadG("absorbBarTexture", ""))
                opacity = tonumber(BarScopeGet("absorbBarOpacity", ReadG("absorbBarOpacity", 0.75))) or 0.75
                color = {
                    tonumber(ReadG("absorbBarColorR", 1)) or 1,
                    tonumber(ReadG("absorbBarColorG", 1)) or 1,
                    tonumber(ReadG("absorbBarColorB", 1)) or 1,
                    max(0, min(1, opacity)),
                }
                showAbsorbEdgeGlow = BarScopeGet("fullHealthAbsorbStripe", ReadGBool("fullHealthAbsorbStripe", false)) == true
            end
            return {
                mode = mode,
                category = category,
                dualDirection = true,
                followInsideHealth = category == "negative",
                showAbsorbEdgeGlow = showAbsorbEdgeGlow,
                healthFraction = mode == 4 and 0.84 or 0.68,
                overlayFraction = category == "negative" and 0.16 or 0.22,
                healthTexture = ResolveBarPreviewTexture(foregroundKey, "Blizzard"),
                backgroundTexture = ResolveBarPreviewTexture(backgroundKey, foregroundKey),
                overlayTexture = ResolveBarPreviewTexture(textureKey, foregroundKey),
                healthColor = { 0.12, 0.62, 0.25, 1 },
                backgroundColor = { 0.025, 0.075, 0.045, 0.92 },
                overlayColor = color,
            }
        end
    end
    local positivePreview = AnchorPreview("positive")
    local negativePreview = AnchorPreview("negative")
    local healPreview = AnchorPreview("heal")
    local anchorValues = {
        { value = 1, text = "Anchor to left side", previewKind = "barOverlay", barPreview = positivePreview },
        { value = 2, text = "Anchor to right side", previewKind = "barOverlay", barPreview = positivePreview },
        { value = 3, text = "Follow HP bar", previewKind = "barOverlay", barPreview = positivePreview },
        { value = 4, text = "Follow HP bar (overflow)", previewKind = "barOverlay", barPreview = positivePreview },
        { value = 5, text = "Reverse from max", previewKind = "barOverlay", barPreview = positivePreview },
    }
    local negativeAnchorValues = {
        { value = 1, text = "Anchor to left side", previewKind = "barOverlay", barPreview = negativePreview },
        { value = 2, text = "Anchor to right side", previewKind = "barOverlay", barPreview = negativePreview },
        { value = 3, text = "Follow HP bar", previewKind = "barOverlay", barPreview = negativePreview },
        { value = 5, text = "Reverse from max", previewKind = "barOverlay", barPreview = negativePreview },
    }
    local healAnchorValues = {
        { value = 1, text = "Anchor to left side", previewKind = "barOverlay", barPreview = healPreview },
        { value = 2, text = "Anchor to right side", previewKind = "barOverlay", barPreview = healPreview },
        { value = 3, text = "Follow HP bar", previewKind = "barOverlay", barPreview = healPreview },
        { value = 4, text = "Follow HP bar (overflow)", previewKind = "barOverlay", barPreview = healPreview },
        { value = 5, text = "Reverse from max", previewKind = "barOverlay", barPreview = healPreview },
    }

    local positiveEnabled = BindToggle(positive, "Show positive absorbs", "enableAbsorbBar", true,
        "MSUF2_ABSORB_ENABLED", leftX, -10, leftW, "absorb.positive.enabled", function(value)
            BarScopeSet("absorbTextMode", value and 2 or 1, "MSUF2_ABSORB_ENABLED", true)
        end)
    local positiveAnchor = BindDropdown(positive, "Anchor", anchorValues, "absorbAnchorMode", 2,
        "MSUF2_ABSORB_ANCHOR", leftX, -64, leftW, true, "absorb.positive.anchor")
    local positiveHeight = BindSlider(positive, "Bar height (0 = full)", 0, 100, 1, "absorbBarHeight", 0,
        "MSUF2_ABSORB_HEIGHT", leftX, -118, leftW, "absorb.positive.height")
    local positiveOffset = BindSlider(positive, "Vertical offset", -100, 100, 1, "absorbBarOffsetY", 0,
        "MSUF2_ABSORB_OFFSET", leftX, -182, leftW, "absorb.positive.offset_y")
    local positiveTexture = BindDropdown(positive, "Texture", function() return TextureValues("Use foreground texture") end,
        "absorbBarTexture", TextureDefault("absorbBarTexture"), "MSUF2_ABSORB_TEXTURE",
        rightX, -10, rightW, false, "absorb.positive.texture")
    local positiveOpacity = BindSlider(positive, "Opacity", 0, 1, 0.05, "absorbBarOpacity", 0.75,
        "MSUF2_ABSORB_OPACITY", rightX, -64, rightW, "absorb.positive.opacity")
    local positiveTest = BindTest(positive, "absorb", rightX, -128, rightW, "absorb.positive.preview.test")
    local overAbsorb = BindToggle(positive, "Over-absorb overlay", "overAbsorbOverlay", false,
        "MSUF2_OVER_ABSORB_OVERLAY", rightX, -182, rightW, "absorb.positive.over_absorb")
    local fullStripe = BindToggle(positive, "Full-health absorb stripe", "fullHealthAbsorbStripe", false,
        "MSUF2_FULL_HEALTH_ABSORB_STRIPE", rightX, -236, rightW, "absorb.positive.full_health_stripe")

    local negativeEnabled = BindToggle(negative, "Show negative heal absorbs", "healAbsorbEnabled", true,
        "MSUF2_HEAL_ABSORB_ENABLED", leftX, -10, leftW, "absorb.negative.enabled")
    local negativeAnchor = BindDropdown(negative, "Anchor", negativeAnchorValues, "healAbsorbAnchorMode", 3,
        "MSUF2_HEAL_ABSORB_ANCHOR", leftX, -64, leftW, true, "absorb.negative.anchor")
    local negativeHeight = BindSlider(negative, "Bar height (0 = full)", 0, 100, 1, "healAbsorbBarHeight", 0,
        "MSUF2_HEAL_ABSORB_HEIGHT", leftX, -118, leftW, "absorb.negative.height")
    local negativeOffset = BindSlider(negative, "Vertical offset", -100, 100, 1, "healAbsorbBarOffsetY", 0,
        "MSUF2_HEAL_ABSORB_OFFSET", leftX, -182, leftW, "absorb.negative.offset_y")
    local negativeTexture = BindDropdown(negative, "Texture", function() return TextureValues("Use foreground texture") end,
        "healAbsorbBarTexture", TextureDefault("healAbsorbBarTexture"), "MSUF2_HEAL_ABSORB_TEXTURE",
        rightX, -10, rightW, false, "absorb.negative.texture")
    local negativeOpacity = BindSlider(negative, "Opacity", 0, 1, 0.05, "healAbsorbBarOpacity", 1,
        "MSUF2_HEAL_ABSORB_OPACITY", rightX, -64, rightW, "absorb.negative.opacity")
    local negativeTest = BindTest(negative, "healAbsorb", rightX, -128, rightW, "absorb.negative.preview.test")

    local healEnabled = BindToggle(heal, "Show heal prediction", "healPredEnabled",
        ReadGBool("showSelfHealPrediction", false), "MSUF2_HEAL_PRED_ENABLED", leftX, -10, leftW,
        "absorb.heal_prediction.enabled", function(value)
            if SharedScope() then
                G().showSelfHealPrediction = value
                Call("MSUF_RefreshSelfHealPredUnitEvent")
            end
        end)
    local healAnchor = BindDropdown(heal, "Anchor", healAnchorValues, "healPredAnchorMode", 3,
        "MSUF2_HEALPRED_ANCHOR", leftX, -64, leftW, true, "absorb.heal_prediction.anchor")
    local healHeight = BindSlider(heal, "Bar height (0 = full)", 0, 100, 1, "healPredictionBarHeight", 0,
        "MSUF2_HEALPRED_HEIGHT", leftX, -118, leftW, "absorb.heal_prediction.height")
    local healOffset = BindSlider(heal, "Vertical offset", -100, 100, 1, "healPredictionBarOffsetY", 0,
        "MSUF2_HEALPRED_OFFSET", leftX, -182, leftW, "absorb.heal_prediction.offset_y")
    local healTexture = BindDropdown(heal, "Texture", function() return TextureValues("Use foreground texture") end,
        "healPredictionBarTexture", "", "MSUF2_HEALPRED_TEXTURE", rightX, -10, rightW, false,
        "absorb.heal_prediction.texture")
    local healOpacity = BindSlider(heal, "Opacity", 0, 1, 0.05, "healPredictionBarOpacity", 0.45,
        "MSUF2_HEALPRED_OPACITY", rightX, -64, rightW, "absorb.heal_prediction.opacity")
    local healTest = BindTest(heal, "heal", rightX, -128, rightW, "absorb.heal_prediction.preview.test")

    local positiveOptions = { positiveAnchor, positiveHeight, positiveOffset, positiveTexture, positiveOpacity, overAbsorb, fullStripe }
    local negativeOptions = { negativeAnchor, negativeHeight, negativeOffset, negativeTexture, negativeOpacity }
    local healOptions = { healAnchor, healHeight, healOffset, healTexture, healOpacity }
    M.TrackRefresh(ctx, SyncControls(function()
        local scopedActive = ScopedControls()
        SetControlEnabled(positiveEnabled, scopedActive)
        SetControlEnabled(negativeEnabled, scopedActive)
        SetControlEnabled(healEnabled, scopedActive)
        SetControlsEnabled(positiveOptions, scopedActive and BarScopeGet("enableAbsorbBar", true) ~= false)
        SetControlsEnabled(negativeOptions, scopedActive and BarScopeGet("healAbsorbEnabled", true) ~= false)
        SetControlsEnabled(healOptions, scopedActive and BarScopeGet("healPredEnabled", ReadGBool("showSelfHealPrediction", false)) == true)
        SetControlEnabled(positiveTest, true)
        SetControlEnabled(negativeTest, true)
        SetControlEnabled(healTest, true)
        if positiveAnchor.RefreshPreview then positiveAnchor:RefreshPreview() end
        if negativeAnchor.RefreshPreview then negativeAnchor:RefreshPreview() end
        if healAnchor.RefreshPreview then healAnchor:RefreshPreview() end
    end))
end

local function BuildOutlineSection(ctx, b)
    local outline = b:CollapsibleSection("bars_outline", "Frame Outline", 220, false)
    local outlineSlider = W.Slider(outline, "Bar outline thickness", 0, 8, 1, 300)
    M.BindNumberWidget(ctx, outlineSlider,
        function() return tonumber(BarScopeGetBars("barOutlineThickness", 1)) or 1 end,
        function(v)
            BarScopeSetBars("barOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_BAR_OUTLINE", true)
            RequestOutlineRuntime()
        end,
        1, Meta("outline.thickness", "setting", { step = 1, roundStep = true }))
    local outlineLayer = W.Slider(outline, "Frame outline layer (0-30)", 0, 30, 1, 300)
    M.BindNumberWidget(ctx, outlineLayer,
        function() return tonumber(BarScopeGetBars("barOutlineLayer", 0)) or 0 end,
        function(v)
            BarScopeSetBars("barOutlineLayer", floor((tonumber(v) or 0) + 0.5), "MSUF2_BAR_OUTLINE_LAYER", true)
            RequestOutlineRuntime()
        end,
        0, Meta("outline.layer", "setting", { step = 1, roundStep = true }))
    local outlineColor = W.Color(outline, "Outline color")
    W.MoveWidget(outlineColor, outline, 30, -150)
    M.BindColor(ctx, outlineColor,
        function()
            return tonumber(BarScopeGet("barOutlineColorR", ReadG("barOutlineColorR", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorG", ReadG("barOutlineColorG", 0))) or 0,
                tonumber(BarScopeGet("barOutlineColorB", ReadG("barOutlineColorB", 0))) or 0
        end,
        function(r, g, b)
            if SetOutlineColorForScope(r, g, b) then
                RequestOutlineRuntime()
            end
        end,
        Meta("outline.color"))
    M.BindGateGroup(ctx, nil, {
        { controls = { outlineSlider, outlineLayer, outlineColor }, on = ScopedControls },
    })
end

local function BuildRoundedSection(ctx, b)
    local rounded = b:CollapsibleSection("bars_rounded", "Rounded Texture", 246, true)
    local roundLeftX = 30
    local roundRightX = 330
    local roundW = 250
    RegisterRoundedSearch(rounded, "Rounded Texture",
        "rounded section|rounded menu|rounded options|where rounded frames|wo rounded frames",
        "Open this section to enable or disable rounded frame textures and its per-surface toggles.", "section")
    local SyncRoundedControls = M.RefreshProxy()
    local function BindRoundedToggle(label, x, y, key, defaultOn, requireReload, searchKeywords, help, useSwitch)
        local control = (useSwitch and W.SwitchAt or W.ToggleAt)(rounded, label, x, y, roundW)
        M.BindBoolWidget(ctx, control,
            function()
                local value = ReadB(key, defaultOn)
                return defaultOn and value ~= false or value == true
            end,
            function(v)
                SetRoundedBool(key, v, requireReload)
                SyncRoundedControls()
            end,
            Meta("rounded." .. key))
        RegisterRoundedSearch(control, label, searchKeywords, help, nil, Meta("rounded." .. key))
        return control
    end
    local roundedControls = M.BuildControlSpecs({
        { "master", "Rounded frame texture", roundLeftX, -52, "roundedFramesEnabled", false, true, "master toggle|all rounded frames|rounded frames master|rounded frames on|rounded frames off|rounded frames einschalten|rounded frames ausschalten|alle abgerundeten frames", "Master switch for the rounded frame texture style.", true },
        { "units", "Unit frames", roundLeftX, -90, "roundedUnitFrames", true, nil, "rounded unit frames|rounded unitframes|unit frame corners|unitframe corners|abgerundete unitframes|unitframes abgerundet|player target focus boss rounded", "Enable or disable rounded textures on unit frames." },
        { "groups", "Group frames", roundLeftX, -128, "roundedGroupFrames", true, nil, "rounded group frames|rounded party frames|rounded raid frames|group frame corners|abgerundete gruppenframes|party raid abgerundet", "Enable or disable rounded textures on group frames." },
        { "power", "Power bars", roundRightX, -52, "roundedPowerBars", true, nil, "rounded power bars|rounded powerbar|power bar corners|powerbar corners|powerbars abgerundet|powerbar abrunden", "Enable or disable rounded textures on power bars." },
        { "mouseover", "Mouseover highlights", roundRightX, -90, "roundedMouseover", true, nil, "rounded mouseover|rounded hover|rounded hover border|mouseover rounded|mouseover highlight rounded|mouseover abgerundet|hover abgerundet", "Enable or disable rounded mouseover highlight edges." },
    }, { ["*"] = function(s) return BindRoundedToggle(s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10]), s[1] end })
    local roundedPreview = CreateRoundedTexturePreview(rounded, roundLeftX, -154, max(320, (rounded._msuf2Width or ctx.width or 720) - 60))
    RegisterRoundedSearch(roundedPreview, "Rounded Texture Preview",
        "rounded preview|rounded example|rounded image|rounded frame preview|preview rounded frames|rounded frames aussehen|vorschau abgerundete frames",
        "Shows a small preview of the rounded frame texture style.", "preview")
    local roundedDependentControls = { roundedControls.units, roundedControls.groups, roundedControls.power, roundedControls.mouseover }
    SyncRoundedControls(M.BindGateGroup(ctx, nil, {
        { controls = roundedDependentControls, on = function() return ReadB("roundedFramesEnabled", false) == true end },
    }, {
        also = function() if roundedPreview and roundedPreview.RefreshRoundedPreview then roundedPreview:RefreshRoundedPreview() end end,
    }))
end

local function BuildHighlightSection(ctx, b)
    local highlights = b:CollapsibleSection("bars_highlight", "Highlight Borders", 710, true)
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlPreviewX = hlLeftX
    local hlPreviewW = max(280, min(440, hlInnerW - 28))
    local highlightTabFrames = {}
    local modesFrame, previewFrame, priorityFrame =
        M.UnitSectionsShared.MakeTabFrames(highlights, -88, hlW, highlightTabFrames, "modes", "preview", "priority")
    RegisterSegment(W.SegmentTabs(ctx, highlights, {
        stateKey = "barsHighlightTab", label = "Highlight area",
        values = VT("modes", "Modes", "preview", "Preview", "priority", "Priority"),
        width = min(520, hlInnerW), frames = highlightTabFrames, defaultTab = "modes",
        x = hlLeftX, y = -44,
    }), "highlight.workspace_tab", VT("modes", "Modes", "preview", "Preview", "priority", "Priority"))
    W.ControlCard(modesFrame, "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 542)
    local priorityCardW = min(360, max(260, hlLeftW + 28))
    local priorityCard = W.ControlCard(priorityFrame, "Priority Order", nil, hlLeftX - 14, -38, priorityCardW, 296)
    W.ControlCard(previewFrame, "Preview", nil, hlPreviewX - 14, -38, hlPreviewW + 28, 248)
    local function HighlightPriorityEnabled()
        local value = BarScopeGet("hlPrioEnabled", nil)
        if value == nil then value = BarScopeGet("highlightPrioEnabled", false) end
        return value == true or value == 1 or value == "1"
    end
    local highlight = W.Slider(modesFrame, "Highlight border thickness", 1, 30, 1, hlLeftW)
    M.BindNumberWidget(ctx, highlight,
        function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
        function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER", true)
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER", true)
            RequestAllHighlightBorderRuntime()
        end,
        2, Meta("highlight.border_thickness", "setting", { step = 1, roundStep = true }))
    W.MoveWidget(highlight, modesFrame, hlLeftX, -70, hlLeftW, "LEFT")
    local borderModes = VT(0, "Off", 1, "On")
    local function StopBorderTest(flag, setter, value)
        if value == 1 or not _G[flag] then return end
        local fn = _G[setter]
        if type(fn) == "function" then fn(false) end
    end
    local function BindHighlightDropdown(label, values, y, getValue, setValue, path)
        local control = W.Dropdown(modesFrame, label, values, hlLeftW)
        M.BindDropdownWidget(ctx, control, getValue, setValue, Meta(path))
        W.MoveWidget(control, modesFrame, hlLeftX, y, hlLeftW, "LEFT")
        return control
    end
    local function BindBorderModeDropdown(label, key, defaultValue, reason, y, flag, setter, apply)
        return BindHighlightDropdown(label, borderModes, y,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(v)
                local value = tonumber(v) or defaultValue
                BarScopeSet(key, value, reason, true)
                StopBorderTest(flag, setter, value)
                apply()
            end,
            "highlight.border_mode." .. key)
    end
    local aggroModeValues = VT("ALL", "All roles", "NON_TANK", "Non-tanks", "HEALER", "Healers only", "TANK", "Tanks only")
    local aggro = BindBorderModeDropdown("Aggro border", "aggroOutlineMode", 1, "MSUF2_AGGRO_BORDER", -136,
        "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", RequestAggroBorderRuntime)
    local aggroMode = BindHighlightDropdown("Aggro shows for", aggroModeValues, -190,
        function() return NormalizeAggroMode(BarScopeGet("aggroMode", "ALL")) end,
        function(v)
            BarScopeSet("aggroMode", NormalizeAggroMode(v), "MSUF2_AGGRO_MODE", true)
            RequestAggroBorderRuntime()
        end,
        "highlight.aggro.roles")
    local dispelBorder = BindBorderModeDropdown("Dispel border", "dispelOutlineMode", 1, "MSUF2_DISPEL_BORDER", -244,
        "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", RequestDispelPurgeBorderRuntime)
    local dispelTrigger = BindHighlightDropdown("Dispel border detects", DISPEL_TRIGGERS, -298,
        function() return NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "DISPEL_TYPE")) end,
        function(v)
            BarScopeSet("dispelBorderTrigger", NormalizeDispelTrigger(v), "MSUF2_DISPEL_TRIGGER", true)
            RequestDispelPurgeBorderRuntime()
        end,
        "highlight.dispel.trigger")
    local purge = BindBorderModeDropdown("Purge border", "purgeOutlineMode", 0, "MSUF2_PURGE_BORDER", -352,
        "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", RequestDispelPurgeBorderRuntime)
    local bossTarget = BindHighlightDropdown("Boss target border", borderModes, -406,
        function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        function(v)
            local value = tonumber(v) or 1
            local general = G()
            general.bossTargetOutlineMode = value
            general.bossTargetHighlightEnabled = value == 1
            StopBorderTest("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", value)
            RequestBossTargetBorderRuntime()
        end,
        "highlight.boss_target.mode")
    local dispelPurgePtrHint = W.Text(modesFrame, DISPEL_PURGE_BORDER_121_PTR_MESSAGE, hlLeftX, -456, hlLeftW, T.colors.dim)
    if dispelPurgePtrHint.SetWordWrap then dispelPurgePtrHint:SetWordWrap(true) end
    local bossSharedHint = W.Text(modesFrame, "Boss target border is a shared boss-frame setting.", hlLeftX, -486, hlLeftW, T.colors.dim)
    if bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end
    local unitAuraDispelHint = W.Text(modesFrame, UNITFRAME_DISPEL_AURA_WARNING, hlLeftX, -516, hlLeftW, UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if unitAuraDispelHint.SetWordWrap then unitAuraDispelHint:SetWordWrap(true) end
    local function ScopeBorderModeOn(key, defaultValue) return tonumber(BarScopeGet(key, defaultValue)) == 1 end
    local function BossTargetBorderOn()
        local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
        return (tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback) == 1
    end
    local function BindBorderTestToggle(label, y, flagName, setterName, enabledFn, noScope, path)
        local control = W.ToggleAt(previewFrame, label, hlPreviewX, y, hlPreviewW)
        M.BindBoolWidget(ctx, control,
            function() return _G[flagName] and true or false end,
            function(v)
                if v and not enabledFn() then
                    if M.RequestRefresh then M.RequestRefresh(ctx, "bars-border-test-disabled") elseif M.Refresh then M.Refresh(ctx) end
                    return
                end
                local fn = _G[setterName]
                if type(fn) == "function" then
                    if noScope then fn(v and true or false)
                    else fn(v and true or false, BorderTestScope()) end
                end
            end,
            Meta(path, "ephemeral"))
        control:HookScript("OnHide", function(self)
            local fn = _G[setterName]
            if _G[flagName] and type(fn) == "function" then
                fn(false)
                self:SetChecked(false)
            end
        end)
        return control
    end
    local aggroTest = BindBorderTestToggle("Test aggro border", -72, "MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", function() return ScopeBorderModeOn("aggroOutlineMode", 1) end, nil, "highlight.preview.aggro")
    local dispelTest = BindBorderTestToggle("Test dispel border", -104, "MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", function() return ScopeBorderModeOn("dispelOutlineMode", 1) end, nil, "highlight.preview.dispel")
    local purgeTest = BindBorderTestToggle("Test purge border", -214, "MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", function() return ScopeBorderModeOn("purgeOutlineMode", 0) end, nil, "highlight.preview.purge")
    local bossTargetTest = BindBorderTestToggle("Test boss target border", -246, "MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", BossTargetBorderOn, true, "highlight.preview.boss_target")
    local scopedBorderControls = { highlight, aggro, dispelBorder, purge }
    local dispelBorderControls = { dispelTrigger, dispelTest }
    local function ClearBorderTestIfDisabled(flagName, setterName, enabled)
        local fn = _G[setterName]
        if _G[flagName] and not enabled and type(fn) == "function" then fn(false) end
    end
    M.TrackRefresh(ctx, function()
        local scopedActive = HighlightControls()
        local sharedActive = SharedScope()
        local aggroOn = ScopeBorderModeOn("aggroOutlineMode", 1)
        local dispelOn = ScopeBorderModeOn("dispelOutlineMode", 1)
        local purgeOn = ScopeBorderModeOn("purgeOutlineMode", 0)
        local bossTargetOn = BossTargetBorderOn()
        ClearBorderTestIfDisabled("MSUF_AggroBorderTestMode", "MSUF_SetAggroBorderTestMode", aggroOn)
        ClearBorderTestIfDisabled("MSUF_DispelBorderTestMode", "MSUF_SetDispelBorderTestMode", dispelOn and not DISPEL_BORDER_121_PTR_DISABLED)
        ClearBorderTestIfDisabled("MSUF_PurgeBorderTestMode", "MSUF_SetPurgeBorderTestMode", purgeOn and not PURGE_BORDER_121_PTR_DISABLED)
        ClearBorderTestIfDisabled("MSUF_BossTargetBorderTestMode", "MSUF_SetBossTargetBorderTestMode", sharedActive and bossTargetOn)
        SetControlsEnabled(scopedBorderControls, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive and not DISPEL_BORDER_121_PTR_DISABLED)
        SetControlEnabled(purge, scopedActive and not PURGE_BORDER_121_PTR_DISABLED)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroMode, scopedActive and aggroOn)
        SetControlEnabled(aggroTest, scopedActive and aggroOn)
        SetControlsEnabled(dispelBorderControls, scopedActive and dispelOn and not DISPEL_BORDER_121_PTR_DISABLED)
        SetControlEnabled(purgeTest, scopedActive and purgeOn and not PURGE_BORDER_121_PTR_DISABLED)
        SetControlEnabled(bossTargetTest, sharedActive and bossTargetOn)
        if dispelPurgePtrHint and dispelPurgePtrHint.SetShown then dispelPurgePtrHint:SetShown(PURGE_BORDER_121_PTR_DISABLED) end
        if unitAuraDispelHint and unitAuraDispelHint.SetShown then unitAuraDispelHint:SetShown((not GroupScope()) and not AnyUnitFrameAuraEnabled()) end
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1)
    end)
    local RefreshPriorityRows
    local prio = W.SwitchAt(priorityCard, "Custom highlight priority", 16, -54, priorityCardW - 32)
    M.BindBoolWidget(ctx, prio,
        HighlightPriorityEnabled,
        function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioEnabled = on and 1 or 0
                G().highlightPrioEnabled = on and 1 or 0
            end
            RequestHighlightPriorityRuntime()
            if RefreshPriorityRows then RefreshPriorityRows() end
        end,
        Meta("highlight.priority.enabled"))
    local rowMax = 4
    local prioContainer, prioRows, prioCount
    local function SavePriorityRows()
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioOrder = order
                G().highlightPrioOrder = order
            end
            RequestHighlightPriorityRuntime()
        end
        M.RunWithHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
    end
    local function SetPriorityRowsEnabled(enabled)
        prioContainer:SetRowsEnabled(enabled)
    end
    prioContainer = RegisterDragRows(M.UnitSectionsShared.MakeDragSortRows(priorityCard, nil, {
        x = 16, y = -82, width = min(220, priorityCardW - 32), rowHeight = 22, gap = 4, maxRows = rowMax,
        bg = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.30, 0.30, 0.30, 0.60 },
        disabledAlpha = 0.4,
        dragAllowed = function() return HighlightControls() and HighlightPriorityEnabled() end,
        onReorder = SavePriorityRows,
    }), "highlight.priority.order")
    prioRows = prioContainer.rows
    RefreshPriorityRows = function()
        SetControlEnabled(prio, HighlightControls())
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(M.Tr(PRIORITY_LABELS[key] or key))
            row.frame._numText:SetText(tostring(i))
        end
        prioContainer:SetActiveCount(prioCount)
        SetPriorityRowsEnabled(HighlightControls() and HighlightPriorityEnabled())
    end
    M.TrackRefresh(ctx, RefreshPriorityRows)
end

-- Unit-frame dispel tinting is a separate section and has no dependency on the
-- highlight-tab frames. Keeping its bindings isolated also leaves headroom for new controls.
local function BuildUnitDispelOverlaySection(ctx, b)
    local overlayCardWProbe = min(900, max(320, (ctx.width or 720) - 40))
    local overlayWide = overlayCardWProbe >= 760
    local ufOverlay = b:CollapsibleSection("bars_unit_dispel_overlay", "UnitFrame Dispel Overlay",
        overlayWide and 358 or 468, false)
    local ufOverlayW = ufOverlay._msuf2Width or ctx.width or 720
    local ufOverlayCardW = min(900, max(320, ufOverlayW - 40))
    overlayWide = ufOverlayCardW >= 760
    local ufOverlayCard = W.ControlCard(ufOverlay, "Behavior & Style",
        "Tints unit-frame health bars when a configured debuff condition is active.",
        20, -38, ufOverlayCardW, overlayWide and 294 or 404)
    local SyncUFOverlayControls = M.RefreshProxy()
    local function BindDropdown(label, values, key, defaultValue, normalizer, reason, y)
        local dropdown = W.Dropdown(ufOverlayCard, label, values, 280)
        M.BindDropdownWidget(ctx, dropdown,
            function()
                local value = BarScopeGet(key, defaultValue)
                return normalizer and normalizer(value) or value
            end,
            function(value)
                BarScopeSet(key, normalizer and normalizer(value) or (value or defaultValue), reason, true)
                RequestUnitDispelOverlayRuntime(reason)
            end,
            Meta("unit_dispel_overlay." .. key))
        W.MoveWidget(dropdown, ufOverlayCard, 16, y, min(280, ufOverlayCardW - 32), "LEFT")
        return dropdown
    end
    local function BindToggle(label, key, defaultOn, reason, y)
        local toggle = W.ToggleAt(ufOverlayCard, label, 16, y, ufOverlayCardW - 32)
        M.BindBoolWidget(ctx, toggle,
            function() return BarScopeGet(key, defaultOn) ~= false end,
            function(value)
                BarScopeSet(key, value and true or false, reason, true)
                RequestUnitDispelOverlayRuntime(reason)
                SyncUFOverlayControls()
            end,
            Meta("unit_dispel_overlay." .. key))
        return toggle
    end
    local function BindSlider(label, key, defaultValue, reason, y)
        local slider = W.Slider(ufOverlayCard, label, 0.05, 1, 0.05, 340)
        M.BindNumberWidget(ctx, slider,
            function() return tonumber(BarScopeGet(key, defaultValue)) or defaultValue end,
            function(value)
                BarScopeSet(key, tonumber(value) or defaultValue, reason, true)
                RequestUnitDispelOverlayRuntime(reason)
            end,
            defaultValue, Meta("unit_dispel_overlay." .. key))
        W.MoveWidget(slider, ufOverlayCard, 16, y, min(360, ufOverlayCardW - 72), "CENTER")
        return slider
    end
    local master = W.SwitchAt(ufOverlayCard, "UnitFrame Dispel Overlay", ufOverlayCardW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, master,
        function() return BarScopeGet("unitDispelOverlayEnabled", false) == true end,
        function(value)
            BarScopeSet("unitDispelOverlayEnabled", value and true or false, "MSUF2_UF_DISPEL_OVERLAY", true)
            RequestUnitDispelOverlayRuntime("MSUF2_UF_DISPEL_OVERLAY")
            SyncUFOverlayControls()
        end,
        Meta("unit_dispel_overlay.enabled"))
    local controls = {
        BindDropdown("Overlay detects", UNIT_DISPEL_TRIGGERS, "unitDispelOverlayTrigger", "BORDER",
            NormalizeUnitDispelOverlayTrigger, "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", -74),
        BindDropdown("Overlay style", UNIT_DISPEL_STYLES, "unitDispelOverlayStyle", "FULL", nil,
            "MSUF2_UF_DISPEL_OVERLAY_STYLE", -126),
        BindToggle("Show on current health only", "unitDispelOverlayOnHealth", true,
            "MSUF2_UF_DISPEL_OVERLAY_HEALTH", -174),
        BindSlider("Overlay opacity", "unitDispelOverlayAlpha", 0.35, "MSUF2_UF_DISPEL_OVERLAY_ALPHA", -218),
    }
    local hintY = overlayWide and -284 or -384
    local groupHint = W.Text(ufOverlayCard,
        "Group frame scopes use Group Frames > Dispel Overlay.",
        16, hintY, ufOverlayCardW - 32, T.colors.muted)
    local auraHint = W.Text(ufOverlayCard, UNITFRAME_DISPEL_AURA_WARNING,
        16, hintY, ufOverlayCardW - 32, UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if groupHint.SetWordWrap then groupHint:SetWordWrap(true) end
    if auraHint.SetWordWrap then auraHint:SetWordWrap(true) end
    M.TrackRefresh(ctx, SyncUFOverlayControls(function()
        local groupScope = GroupScope()
        local activeScope = not groupScope and ScopedControls()
        SetControlEnabled(master, activeScope)
        SetControlsEnabled(controls,
            activeScope and BarScopeGet("unitDispelOverlayEnabled", false) == true)
        groupHint:SetShown(groupScope)
        auraHint:SetShown(not groupScope and not AnyUnitFrameAuraEnabled())
    end))
end

local function BuildPowerSection(ctx, b)
    local power = b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 152, false)
    local smoothPower = W.Toggle(power, "Smooth power bar")
    M.BindBoolWidget(ctx, smoothPower,
        function() return SmoothPowerGet() end,
        function(v) SmoothPowerSet(v, "MSUF2_BARS_SMOOTH_POWER") end,
        Meta("power.smooth_fill"))
    local realtimePower = W.Toggle(power, "Realtime power text")
    M.BindBoolWidget(ctx, realtimePower,
        function() return ReadB("realtimePowerText", true) ~= false end,
        function(v)
            v = v and true or false
            local bars = Bars()
            if bars.realtimePowerText == v then return end
            bars.realtimePowerText = v
            -- Recompile Player and rebind both Power and PowerText events.
            -- A generic Bars layout refresh leaves this event option dead.
            M.RequestUnitApply("player", "MSUF2_BARS_REALTIME_POWER", {
                preview = true, power = true, text = true,
            })
        end,
        Meta("power.realtime_text"))
    M.BindGateGroup(ctx, nil, {
        { controls = smoothPower, on = function() return CurrentPowerBarScopeUnit() ~= nil end },
        { controls = realtimePower, on = SharedScope },
    })
end

local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Bars", "Textures, gradients, outlines and highlight borders.", 72)
    BuildScopeSection(ctx, b)
    BuildTextureSection(ctx, b)
    BuildTempMaxHealthSection(ctx, b)
    BuildAbsorbSection(ctx, b)
    BuildOutlineSection(ctx, b)
    BuildRoundedSection(ctx, b)
    BuildHighlightSection(ctx, b)
    BuildUnitDispelOverlaySection(ctx, b)
    BuildPowerSection(ctx, b)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 16 })
