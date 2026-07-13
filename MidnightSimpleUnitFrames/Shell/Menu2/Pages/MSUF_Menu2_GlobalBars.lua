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
local OutlineStrata = {}
OutlineStrata.values = {
    { value = "AUTO", text = "Auto (Frame)" },
    { value = "BACKGROUND", text = "BACKGROUND" },
    { value = "LOW", text = "LOW" },
    { value = "MEDIUM", text = "MEDIUM" },
    { value = "HIGH", text = "HIGH" },
    { value = "DIALOG", text = "DIALOG" },
    { value = "FULLSCREEN", text = "FULLSCREEN" },
    { value = "FULLSCREEN_DIALOG", text = "FULLSCREEN_DIALOG" },
    { value = "TOOLTIP", text = "TOOLTIP" },
}
OutlineStrata.count = #OutlineStrata.values
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
local DISPEL_TRIGGERS = VT("BY_ME", "Dispellable by me", "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
local UNIT_DISPEL_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
    "DISPEL_TYPE", "Any dispel-type debuff", "ANY_DEBUFF", "Any debuff")
local UNIT_DISPEL_STYLES = VT("FULL", "Full Frame", "TOP", "Top Fade", "BOTTOM", "Bottom Fade",
    "LEFT", "Left Fade", "RIGHT", "Right Fade")
local Call, DB, G, Bars, ReadG, ReadGBool, ReadB, NormalizeScopeKey, ScopeDBKeys, ScopeHasOverride, ScopeSetOverride, CurrentBarsScope, IsGFScope, BarScopeGet, BarScopeSet, BarScopeGetBars, BarScopeSetBars, TextureValues, CurrentPowerBarScopeUnit, SmoothPowerGet, SmoothPowerSet, PriorityOrder, PriorityColor, RefreshBorderTestModes, SetAbsorbTextureTest, SetControlEnabled, SetControlsEnabled, ApplyBars, ControlMeta, RegisterControl = M.Pick(GP, [[Call DB G Bars ReadG ReadGBool ReadB NormalizeScopeKey ScopeDBKeys ScopeHasOverride ScopeSetOverride CurrentBarsScope IsGFScope BarScopeGet BarScopeSet BarScopeGetBars BarScopeSetBars TextureValues CurrentPowerBarScopeUnit SmoothPowerGet SmoothPowerSet PriorityOrder PriorityColor RefreshBorderTestModes SetAbsorbTextureTest SetControlEnabled SetControlsEnabled ApplyBars ControlMeta RegisterControl]])
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
    ["gradient.strength"] = { "general.gradientStrength" },
    ["absorb.display_mode"] = { "general.absorbTextMode" },
    ["absorb.absorbAnchorMode"] = { "general.absorbAnchorMode" },
    ["absorb.absorbBarOpacity"] = { "general.absorbBarOpacity" },
    ["absorb.absorbBarTexture"] = { "general.absorbBarTexture" },
    ["absorb.healAbsorbBarOpacity"] = { "general.healAbsorbBarOpacity" },
    ["absorb.healAbsorbBarTexture"] = { "general.healAbsorbBarTexture" },
    ["absorb.healPredAnchorMode"] = { "general.healPredAnchorMode" },
    ["absorb.heal_prediction.enabled"] = { "general.showSelfHealPrediction" },
    ["absorb.over_absorb_overlay"] = { "general.overAbsorbOverlay" },
    ["outline.thickness"] = { "bars.barOutlineThickness" },
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
    ["gradient.strength"] = "gradientStrength",
    ["absorb.display_mode"] = "absorbTextMode",
    ["absorb.absorbAnchorMode"] = "absorbAnchorMode",
    ["absorb.absorbBarOpacity"] = "absorbBarOpacity",
    ["absorb.absorbBarTexture"] = "absorbBarTexture",
    ["absorb.healAbsorbBarOpacity"] = "healAbsorbBarOpacity",
    ["absorb.healAbsorbBarTexture"] = "healAbsorbBarTexture",
    ["absorb.healPredAnchorMode"] = "healPredAnchorMode",
    ["absorb.heal_prediction.enabled"] = "healPredEnabled",
    ["absorb.over_absorb_overlay"] = "overAbsorbOverlay",
    ["outline.thickness"] = "barOutlineThickness",
    ["outline.strata"] = "barOutlineStrata",
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
local function IsDynamicBarPath(path)
    path = tostring(path or "")
    return path == "scope.override.enabled"
        or path == "power.smooth_fill"
        or path:find("^textures%.") ~= nil
        or path:find("^gradient%.") ~= nil
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
local function RegisterDragRows(container, path)
    local rows = container and container.rows or {}
    for i = 1, #rows do
        RegisterControl(rows[i].frame, Meta(path .. ".slot." .. tostring(i), "action"),
            "Highlight priority slot " .. tostring(i), "drag")
    end
    return container
end
function OutlineStrata.Normalize(value)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, "AUTO") end
    if value == nil or value == "" then return "AUTO" end
    value = tostring(value):upper()
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or "AUTO"
end
function OutlineStrata.Index(value)
    value = OutlineStrata.Normalize(value)
    local values = OutlineStrata.values
    for i = 1, #values do
        if values[i].value == value then return i - 1 end
    end
    return 0
end
function OutlineStrata.Value(index)
    index = floor((tonumber(index) or 0) + 0.5) + 1
    if index < 1 then index = 1 elseif index > OutlineStrata.count then index = OutlineStrata.count end
    return OutlineStrata.values[index].value
end
function OutlineStrata.Label(valueOrIndex)
    local value = type(valueOrIndex) == "number" and OutlineStrata.Value(valueOrIndex) or OutlineStrata.Normalize(valueOrIndex)
    local values = OutlineStrata.values
    for i = 1, #values do
        if values[i].value == value then return M.Tr(values[i].text) end
    end
    return M.Tr("Auto (Frame)")
end
function OutlineStrata.Parse(text)
    text = tostring(text or ""):upper()
    local values = OutlineStrata.values
    for i = 1, #values do
        if text == values[i].value or text == tostring(values[i].text):upper() then return i - 1 end
    end
    return OutlineStrata.Index(text)
end
function OutlineStrata.RefreshLabel(slider, value)
    if not slider then return end
    if slider._msuf2Title then
        slider._msuf2Title:SetText(M.Tr("Frame outline strata") .. ": " .. OutlineStrata.Label(value))
    end
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
    sample:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -38)
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
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "ANY_DEBUFF" end
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

local function GradientKeyActive(entry, key)
    return entry and entry.hlOverride == true and entry.gradientOverride == true
        and entry.gradientOverrideVersion == 2 and type(entry.gradientOverrideKeys) == "table"
        and entry.gradientOverrideKeys[key] == true
end
local function MarkGradientKey(entry, key)
    if not entry then return end
    entry.hlOverride, entry.gradientOverride, entry.gradientOverrideVersion = true, true, 2
    if type(entry.gradientOverrideKeys) ~= "table" then entry.gradientOverrideKeys = {} end
    entry.gradientOverrideKeys[key] = true
end
local function GradientScopeGet(key, defaultValue)
    local scope = CurrentBarsScope()
    if scope ~= "shared" and ScopeHasOverride(scope, "hlOverride") then
        local db, keys = DB(), ScopeDBKeys(scope)
        for i = 1, #(keys or {}) do
            local entry = db[keys[i]]
            if entry and entry.hlOverride == true and entry[key] ~= nil and not GradientKeyActive(entry, key)
                and entry[key] ~= ReadG(key, defaultValue) then MarkGradientKey(entry, key) end
            if GradientKeyActive(entry, key) and entry[key] ~= nil then return entry[key] end
        end
    end
    return ReadG(key, defaultValue)
end
local function GradientScopeSet(key, value)
    local scope = CurrentBarsScope()
    if scope == "shared" then
        G()[key] = value
        return
    end
    local db, keys = DB(), ScopeDBKeys(scope)
    for i = 1, #(keys or {}) do
        local entryKey = keys[i]
        db[entryKey] = db[entryKey] or {}
        MarkGradientKey(db[entryKey], key)
        db[entryKey][key] = value
    end
end
local function GradientControlsActive() return ScopedControls() end
local function TextureControlsActive() return SharedScope() or GroupScope() and ScopedControls() end
local function CurrentGradientDirectionsForScope()
    local directions, any = {}, false
    for direction, key in pairs(GRADIENT_DIR_KEYS) do
        directions[direction] = GradientScopeGet(key, false) == true
        any = any or directions[direction]
    end
    if not any then
        local legacy = GradientScopeGet("gradientDirection", "RIGHT")
        directions[GRADIENT_DIR_KEYS[legacy] and legacy or "RIGHT"] = true
    end
    return directions
end
local function ToggleGradientDirectionForScope(direction)
    direction = GRADIENT_DIR_KEYS[direction] and direction or "RIGHT"
    local directions = CurrentGradientDirectionsForScope()
    directions[direction] = not directions[direction]
    local any = false
    for candidate in pairs(GRADIENT_DIR_KEYS) do any = any or directions[candidate] == true end
    if not any then directions[direction] = true end
    for candidate, key in pairs(GRADIENT_DIR_KEYS) do GradientScopeSet(key, directions[candidate] == true) end
    GradientScopeSet("gradientDirection", direction)
end
local function ApplyGradientRuntime(reason)
    if GradientScopeGet("enableGradient", false) == true or GradientScopeGet("enablePowerGradient", false) == true then
        local strength = tonumber(GradientScopeGet("gradientStrength"))
        if not (strength and strength > 0) then GradientScopeSet("gradientStrength", 0.45) end
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
            if _G.MSUF_AbsorbTextureTestMode then SetAbsorbTextureTest(true) end
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
    local textures = b:CollapsibleSection("bars_textures", "Textures & Gradient", compactTextures and 326 or 214, true)
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
    local function BindGradientToggle(label, y, width, key, reason)
        local control = W.ToggleAt(textures, label, rightX, y, width)
        M.BindBoolWidget(ctx, control,
            function() return GradientScopeGet(key, false) == true end,
            function(v)
                GradientScopeSet(key, v and true or false)
                ApplyGradientRuntime(reason)
                SyncGradientControls()
            end,
            Meta("gradient." .. key))
        return control
    end
    local hpGradient = BindGradientToggle("HP bar gradient", gradientY - 24, compactTextures and 150 or 180, "enableGradient", "MSUF2_HP_GRADIENT")
    local powerGradient = BindGradientToggle("Power bar gradient", gradientY - 54, compactTextures and 170 or 190, "enablePowerGradient", "MSUF2_POWER_GRADIENT")
    local strength = W.Slider(textures, "Gradient strength", 0, 1, 0.05, 220)
    M.BindNumberWidget(ctx, strength,
        function() return tonumber(GradientScopeGet("gradientStrength", 0.45)) or 0.45 end,
        function(v)
            GradientScopeSet("gradientStrength", tonumber(v) or 0.45)
            ApplyGradientRuntime("MSUF2_GRADIENT_STRENGTH")
        end,
        0.45,
        Meta("gradient.strength"))
    W.MoveWidget(strength, textures, rightX, gradientY - 90, compactTextures and math.min(leftW, 300) or 220, "LEFT")
    local padX = compactTextures and math.min(rightX + 210, (ctx.width or 720) - 104) or math.min(rightX + 238, (ctx.width or 720) - 104)
    local pad = T.Panel(textures, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.55 }, T.colors.borderSoft)
    pad:SetPoint("TOPLEFT", textures, "TOPLEFT", padX, gradientY - 18)
    pad:SetSize(84, 64)
    local center = pad:CreateTexture(nil, "ARTWORK")
    center:SetPoint("CENTER", pad, "CENTER", 0, 0)
    center:SetSize(10, 10)
    local centerColor = T.colors.coreRim or { 0.043, 0.096, 0.150 }
    center:SetColorTexture(centerColor[1], centerColor[2], centerColor[3], 0.95)
    local directionButtons = {}
    local function PadButton(text, value, x, y)
        local btn = T.Button(pad, text, 22, 18)
        btn:SetPoint("TOPLEFT", pad, "TOPLEFT", x, y)
        T.CenterButtonLabel(btn)
        btn:SetScript("OnClick", function()
            ToggleGradientDirectionForScope(value or "RIGHT")
            ApplyGradientRuntime("MSUF2_GRADIENT_DIRECTION")
            SyncGradientControls()
        end)
        RegisterControl(btn, Meta("gradient.direction." .. tostring(value), "action"), text, "button")
        directionButtons[value] = btn
        return btn
    end
    PadButton("^", "UP", 31, -5)
    PadButton("<", "LEFT", 8, -27)
    PadButton(">", "RIGHT", 54, -27)
    PadButton("v", "DOWN", 31, -49)
    local textureControls = { barTexture, bgTexture }
    local gradientControls = { hpGradient, powerGradient }
    M.TrackRefresh(ctx, SyncGradientControls(function()
        local current = CurrentGradientDirectionsForScope()
        local textureControlsActive = TextureControlsActive()
        local gradientControlsActive = GradientControlsActive()
        local valueControlsActive = gradientControlsActive and ((GradientScopeGet("enableGradient", false) == true) or (GradientScopeGet("enablePowerGradient", false) == true))
        SetControlsEnabled(textureControls, textureControlsActive)
        SetControlsEnabled(gradientControls, gradientControlsActive)
        SetControlEnabled(strength, valueControlsActive)
        pad:SetAlpha(valueControlsActive and 1 or 0.45)
        for value, btn in pairs(directionButtons) do
            btn:SetActive(current[value] == true)
            SetControlEnabled(btn, valueControlsActive)
        end
    end))
end

local function BuildAbsorbSection(ctx, b)
    local absorb = b:CollapsibleSection("bars_absorb", "Absorb Display", 420, true)
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
    local absorbAnchors = VT(
        1, "Anchor to left side", 2, "Anchor to right side", 3, "Follow HP bar",
        4, "Follow HP bar (overflow)", 5, "Reverse from max")
    local absorbControls = BuildAbsorbControlSpecs({
        { "dropdown", "Absorb bar anchoring", absorbAnchors, "absorbAnchorMode", 2, "MSUF2_ABSORB_ANCHOR", absorbLeftX, -124, absorbLeftW, true, "anchor" },
        { "dropdown", "Heal prediction anchoring", absorbAnchors, "healPredAnchorMode", 3, "MSUF2_HEALPRED_ANCHOR", absorbLeftX, -240, absorbLeftW, true, "healAnchor" },
        { "slider", "Absorb bar opacity", 0, 1, 0.05, "absorbBarOpacity", 0.75, "MSUF2_ABSORB_OPACITY", absorbLeftX, -294, absorbLeftW, "opacity" },
        { "dropdown", "Absorb bar texture (SharedMedia)", function() return TextureValues("Use foreground texture") end, "absorbBarTexture", function() return ReadG("absorbBarTexture", "") end, "MSUF2_ABSORB_TEXTURE", absorbRightX, -70, absorbRightW, nil, "texture" },
        { "dropdown", "Heal-absorb texture", function() return TextureValues("Use foreground texture") end, "healAbsorbBarTexture", function() return ReadG("healAbsorbBarTexture", "") end, "MSUF2_HEAL_ABSORB_TEXTURE", absorbRightX, -124, absorbRightW, nil, "healTexture" },
        { "slider", "Heal-absorb bar opacity", 0, 1, 0.05, "healAbsorbBarOpacity", 1, "MSUF2_HEAL_ABSORB_OPACITY", absorbRightX, -294, absorbRightW, "healOpacity" },
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
        SetControlEnabled(absorbTest, true)
        SetControlEnabled(healPredToggle, groupScope and scopedActive or sharedActive)
        SetControlEnabled(absorbControls.healAnchor, scopedActive and healPredOn)
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
    outline._msuf2OutlineStrata = W.Slider(outline, "", 0, OutlineStrata.count - 1, 1, 300)
    outline._msuf2OutlineStrata:SetValueFormatter(function(value) return OutlineStrata.Label(value) end)
    outline._msuf2OutlineStrata:SetValueParser(function(text) return OutlineStrata.Parse(text) end)
    M.BindSlider(ctx, outline._msuf2OutlineStrata,
        function()
            return OutlineStrata.Index(BarScopeGetBars("barOutlineStrata", "AUTO"))
        end,
        function(v)
            BarScopeSetBars("barOutlineStrata", OutlineStrata.Value(v), "MSUF2_BAR_OUTLINE_STRATA", true)
            RequestOutlineRuntime()
        end,
        Meta("outline.strata"))
    outline._msuf2OutlineStrata:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        OutlineStrata.RefreshLabel(self, value)
    end)
    M.AddRefresher(ctx, function() OutlineStrata.RefreshLabel(outline._msuf2OutlineStrata, BarScopeGetBars("barOutlineStrata", "AUTO")) end)
    OutlineStrata.RefreshLabel(outline._msuf2OutlineStrata, BarScopeGetBars("barOutlineStrata", "AUTO"))
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
        { controls = { outlineSlider, outline._msuf2OutlineStrata, outlineColor }, on = ScopedControls },
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
    local ufOverlayCard = W.ControlCard(ufOverlay, "UnitFrame Dispel Overlay",
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
        "Group frame scopes use Group Frames > Health & Bars > Dispel Overlay.",
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
    BuildAbsorbSection(ctx, b)
    BuildOutlineSection(ctx, b)
    BuildRoundedSection(ctx, b)
    BuildHighlightSection(ctx, b)
    BuildUnitDispelOverlaySection(ctx, b)
    BuildPowerSection(ctx, b)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 16 })
