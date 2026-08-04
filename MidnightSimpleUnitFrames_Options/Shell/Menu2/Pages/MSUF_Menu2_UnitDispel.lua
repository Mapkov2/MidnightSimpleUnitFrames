local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- UnitFrame dispel presentation belongs beside the unit's Aura workspace.
-- Persistence and runtime ownership stay unchanged: a frame with a Bars
-- override edits its unit table, while a frame following Shared edits general.
local W = M.Widgets or {}
local T = M.Theme or {}
local UP = M.UnitPage or {}
local min, max = math.min, math.max
local VT = M.ValueTextList
local SetControlEnabled = UP.SetControlEnabled or W.SetControlEnabled
local SetControlsEnabled = W.SetControlsEnabled
local GetConf = UP.GetConf
local GetGeneral = UP.GetGeneral

local SUPPORTED_UNITS = { player = true, target = true, focus = true, boss = true }
local SUPPORTED_UNIT_ORDER = { "player", "target", "focus", "boss" }
local UNITFRAME_DISPEL_AURA_WARNING = "No UnitFrame auras: Dispel Border/Overlay need Player/Target/Focus/Boss auras."
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = { 0.90, 0.84, 0.76, 1 }
local UNIT_APPLY_OPTS = { history = false, preview = true, auras = true, notify = false }

local UNIT_DISPEL_TRIGGERS = VT("BORDER", "Use Dispel border detects", "BY_ME", "Dispellable by me",
    "BY_RAID", "Dispellable by group", "DISPEL_TYPE", "Any dispel type")
local UNIT_DISPEL_STYLES = VT("FULL", "Full Frame", "TOP", "Top Fade", "BOTTOM", "Bottom Fade",
    "LEFT", "Left Fade", "RIGHT", "Right Fade")
local UNIT_DISPEL_SYMBOL_STYLES = VT(
    "BLIZZARD", "Blizzard symbol",
    "BLIZZARD_RING", "Blizzard ring + symbol",
    "BLIZZARD_BORDER", "Blizzard ring",
    "MSUF_LETTERS", "MSUF Letters",
    "MSUF_SHAPES", "MSUF Shapes",
    "MSUF_GLYPHS", "MSUF Glyphs",
    "MSUF_MINIMAL", "MSUF Minimal")
local UNIT_DISPEL_SYMBOL_MODES = VT("TOP", "Highest priority only", "ALL", "One per dispel type")
local UNIT_DISPEL_SYMBOL_GROWTH = VT("RIGHT", "Right", "LEFT", "Left", "UP", "Up", "DOWN", "Down")
local UNIT_DISPEL_SYMBOL_STRATA = VT("AUTO", "Automatic", "BACKGROUND", "Background", "LOW", "Low",
    "MEDIUM", "Medium", "HIGH", "High", "DIALOG", "Dialog")
local UNIT_DISPEL_SYMBOL_ANCHORS = VT("TOPLEFT", "Top Left", "TOP", "Top", "TOPRIGHT", "Top Right",
    "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
    "BOTTOMLEFT", "Bottom Left", "BOTTOM", "Bottom", "BOTTOMRIGHT", "Bottom Right")

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

local function UsesUnitBarsOverride(unit)
    local conf = GetConf and GetConf(unit)
    return conf and conf.hlOverride == true or false
end

local function ValueOwner(unit)
    if UsesUnitBarsOverride(unit) then return GetConf(unit), "unit" end
    return GetGeneral(), "shared"
end

local function ReadValue(unit, key, defaultValue)
    local conf = GetConf and GetConf(unit)
    local value
    if conf and conf.hlOverride == true and conf[key] ~= nil then value = conf[key] end
    if value == nil then
        local general = GetGeneral and GetGeneral()
        value = general and general[key]
    end
    if value == nil then return defaultValue end
    return value
end

local function StoreValue(unit, key, value)
    local owner = ValueOwner(unit)
    if not owner or owner[key] == value then return false end
    owner[key] = value
    return true
end

local function RequestUnitRuntime(unit, reason)
    if type(M.RequestUnitApply) == "function" then
        return M.RequestUnitApply(unit, reason, UNIT_APPLY_OPTS)
    end
    local service = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if service and type(service.RequestUnit) == "function" then
        return service.RequestUnit(unit, reason, UNIT_APPLY_OPTS)
    end
    return false
end

local function RequestRuntime(unit, reason)
    reason = reason or "MSUF2_UF_DISPEL"
    if UsesUnitBarsOverride(unit) then return RequestUnitRuntime(unit, reason) end
    local changed = false
    for i = 1, #SUPPORTED_UNIT_ORDER do
        changed = RequestUnitRuntime(SUPPORTED_UNIT_ORDER[i], reason) ~= false or changed
    end
    return changed
end

local function SetValue(unit, key, value, reason)
    if not StoreValue(unit, key, value) then return false end
    RequestRuntime(unit, reason)
    return true
end

local function UnitAuraEnabled(unit)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function") then return true end
    return model.UnitEnabled(unit) == true
end

local function SourceHint(unit)
    local source = UsesUnitBarsOverride(unit)
        and M.Tr("Settings source: This frame's custom Bars settings.")
        or M.Tr("Settings source: Shared Bars. Changes here update the shared default.")
    if not UnitAuraEnabled(unit) then source = source .. "\n" .. M.Tr(UNITFRAME_DISPEL_AURA_WARNING) end
    return source
end

local function RefreshSourceHint(hint, unit)
    if not hint then return end
    local auraEnabled = UnitAuraEnabled(unit)
    hint:SetText(SourceHint(unit))
    if hint.SetTextColor then
        local color = auraEnabled and (T.colors and T.colors.muted) or UNITFRAME_DISPEL_AURA_WARNING_COLOR
        if color then hint:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    end
end

local function Meta(ctx, unit, path, key, classification)
    local meta = UP.ControlMeta and UP.ControlMeta(ctx, "dispel." .. tostring(path), classification or "setting") or {}
    if key then
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "This UnitFrame page edits Shared Bars or the unit Bars override, whichever currently owns the effective value."
        meta.assistantSettingKeys = { "general." .. tostring(key), tostring(unit) .. "." .. tostring(key) }
    end
    return meta
end

local function OverlaySectionHeight(ctx)
    local width = min(900, max(320, (((ctx and ctx.width) or 720) - 40)))
    return width >= 760 and 436 or 546
end

local function BuildUnitDispelOverlaySection(ctx, builder, unit)
    local sectionHeight = OverlaySectionHeight(ctx)
    local wide = sectionHeight == 436
    local section = builder:CollapsibleSection("unit_dispel_overlay", "Dispel Overlay", sectionHeight, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    wide = cardW >= 760
    local card = W.ControlCard(section, "Behavior & Style",
        "Tints unit-frame health bars when a configured debuff condition is active.",
        20, -38, cardW, wide and 372 or 482)
    local Sync = M.RefreshProxy()

    local function BindDropdown(label, values, key, defaultValue, normalizer, reason, y)
        local dropdown = W.Dropdown(card, label, values, 280)
        M.BindDropdownWidget(ctx, dropdown,
            function()
                local value = ReadValue(unit, key, defaultValue)
                return normalizer and normalizer(value) or value
            end,
            function(value)
                SetValue(unit, key, normalizer and normalizer(value) or (value or defaultValue), reason)
            end,
            Meta(ctx, unit, "overlay." .. key, key))
        W.MoveWidget(dropdown, card, 16, y, min(280, cardW - 32), "LEFT")
        return dropdown
    end

    local function BindToggle(label, key, defaultOn, reason, y)
        local toggle = W.ToggleAt(card, label, 16, y, cardW - 32)
        M.BindBoolWidget(ctx, toggle,
            function() return ReadValue(unit, key, defaultOn) ~= false end,
            function(value)
                SetValue(unit, key, value and true or false, reason)
                Sync()
            end,
            Meta(ctx, unit, "overlay." .. key, key))
        return toggle
    end

    local function BindSlider(label, key, defaultValue, reason, y)
        local slider = W.Slider(card, label, 0.05, 1, 0.05, 340)
        M.BindNumberWidget(ctx, slider,
            function() return tonumber(ReadValue(unit, key, defaultValue)) or defaultValue end,
            function(value) SetValue(unit, key, tonumber(value) or defaultValue, reason) end,
            defaultValue, Meta(ctx, unit, "overlay." .. key, key))
        W.MoveWidget(slider, card, 16, y, min(360, cardW - 72), "CENTER")
        return slider
    end

    local master = W.SwitchAt(card, "Dispel Overlay", cardW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, master,
        function() return ReadValue(unit, "unitDispelOverlayEnabled", false) == true end,
        function(value)
            SetValue(unit, "unitDispelOverlayEnabled", value and true or false, "MSUF2_UF_DISPEL_OVERLAY")
            Sync()
        end,
        Meta(ctx, unit, "overlay.enabled", "unitDispelOverlayEnabled"))
    local controls = {
        BindDropdown("Overlay detects", UNIT_DISPEL_TRIGGERS, "unitDispelOverlayTrigger", "BORDER",
            NormalizeUnitDispelOverlayTrigger, "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", -74),
        BindDropdown("Overlay style", UNIT_DISPEL_STYLES, "unitDispelOverlayStyle", "FULL", nil,
            "MSUF2_UF_DISPEL_OVERLAY_STYLE", -126),
        BindToggle("Show on current health only", "unitDispelOverlayOnHealth", true,
            "MSUF2_UF_DISPEL_OVERLAY_HEALTH", -174),
        BindSlider("Overlay opacity", "unitDispelOverlayAlpha", 0.35, "MSUF2_UF_DISPEL_OVERLAY_ALPHA", -218),
    }
    local preview = W.ToggleAt(card, "Preview overlay", 16, -266, cardW - 32)
    M.BindBoolWidget(ctx, preview,
        function() return _G.MSUF_DispelOverlayPreviewMode == true and _G.MSUF_DispelOverlayPreviewScope == unit end,
        function(value)
            local fn = _G.MSUF_SetDispelOverlayPreview
            if type(fn) == "function" then fn(value and true or false, unit) end
        end,
        Meta(ctx, unit, "overlay.preview", nil, "ephemeral"))
    preview:HookScript("OnHide", function(self)
        local fn = _G.MSUF_SetDispelOverlayPreview
        if _G.MSUF_DispelOverlayPreviewMode == true and _G.MSUF_DispelOverlayPreviewScope == unit
            and type(fn) == "function"
        then
            fn(false)
            if self.SetChecked then self:SetChecked(false) end
        end
    end)
    if M.AddTooltip then
        M.AddTooltip(preview, "Preview overlay",
            "Paints a stand-in tint so the overlay can be judged without a real dispellable debuff. Turns itself off when this page closes.",
            { hook = true })
    end
    controls[#controls + 1] = preview
    local hint = W.Text(card, SourceHint(unit), 16, wide and -328 or -428, cardW - 32, T.colors and T.colors.muted)
    if hint.SetWordWrap then hint:SetWordWrap(true) end

    M.TrackRefresh(ctx, Sync(function()
        local enabled = ReadValue(unit, "unitDispelOverlayEnabled", false) == true
        if not enabled and _G.MSUF_DispelOverlayPreviewMode == true
            and _G.MSUF_DispelOverlayPreviewScope == unit
        then
            local clear = _G.MSUF_SetDispelOverlayPreview
            if type(clear) == "function" then clear(false) end
        end
        SetControlEnabled(master, true)
        SetControlsEnabled(controls, enabled)
        RefreshSourceHint(hint, unit)
    end))
end

local symbolSyncByUnit = {}
local symbolMoveHandlerInstalled = false
local function EnsureSymbolMoveHandler()
    if symbolMoveHandlerInstalled then return end
    local setter = _G.MSUF_SetDispelSymbolPreviewMoveHandler
    if type(setter) ~= "function" then return end
    setter(function(scope, x, y)
        scope = tostring(scope or "")
        if not SUPPORTED_UNITS[scope] then return end
        local changed = StoreValue(scope, "unitDispelSymbolX", tonumber(x) or 0)
        changed = StoreValue(scope, "unitDispelSymbolY", tonumber(y) or 0) or changed
        if changed then RequestRuntime(scope, "MSUF2_UF_DISPEL_SYMBOL_DRAG") end
        if type(M.RefreshVisibleSliders) == "function" then M.RefreshVisibleSliders("UNIT_DISPEL_SYMBOL_PREVIEW_DRAG") end
        local sync = symbolSyncByUnit[scope]
        if type(sync) == "function" then sync() end
    end)
    symbolMoveHandlerInstalled = true
end

local function SymbolSectionHeight(ctx)
    local width = min(900, max(320, (((ctx and ctx.width) or 720) - 40)))
    return width >= 760 and 554 or 814
end

local function BuildUnitDispelSymbolSection(ctx, builder, unit)
    local sectionHeight = SymbolSectionHeight(ctx)
    local wide = sectionHeight == 554
    local section = builder:CollapsibleSection("unit_dispel_symbol", "Dispel Symbol", sectionHeight, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    wide = cardW >= 760
    local card = W.ControlCard(section, "Symbol & Placement",
        "Shows a symbol naming the dispel type of an active debuff.",
        20, -38, cardW, wide and 490 or 730)
    local Sync = M.RefreshProxy()
    symbolSyncByUnit[unit] = Sync
    EnsureSymbolMoveHandler()
    local fieldW = min(280, cardW - 32)
    local sliderW = min(360, cardW - 72)
    local rightX = wide and (cardW - sliderW - 16) or 16

    local function BindDropdown(label, values, key, defaultValue, reason, x, y)
        local dropdown = W.Dropdown(card, label, values, 280)
        M.BindDropdownWidget(ctx, dropdown,
            function() return ReadValue(unit, key, defaultValue) end,
            function(value)
                SetValue(unit, key, value or defaultValue, reason)
                Sync()
            end,
            Meta(ctx, unit, "symbol." .. key, key))
        W.MoveWidget(dropdown, card, x, y, fieldW, "LEFT")
        return dropdown
    end

    local function BindSlider(label, key, defaultValue, minValue, maxValue, step, reason, x, y)
        local slider = W.Slider(card, label, minValue, maxValue, step, 340)
        M.BindNumberWidget(ctx, slider,
            function() return tonumber(ReadValue(unit, key, defaultValue)) or defaultValue end,
            function(value) SetValue(unit, key, tonumber(value) or defaultValue, reason) end,
            defaultValue, Meta(ctx, unit, "symbol." .. key, key))
        W.MoveWidget(slider, card, x, y, sliderW, "CENTER")
        return slider
    end

    local master = W.SwitchAt(card, "Dispel Symbol", cardW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, master,
        function() return ReadValue(unit, "unitDispelSymbolEnabled", false) == true end,
        function(value)
            SetValue(unit, "unitDispelSymbolEnabled", value and true or false, "MSUF2_UF_DISPEL_SYMBOL")
            Sync()
        end,
        Meta(ctx, unit, "symbol.enabled", "unitDispelSymbolEnabled"))
    local styleDrop = BindDropdown("Symbol set", UNIT_DISPEL_SYMBOL_STYLES, "unitDispelSymbolStyle",
        "BLIZZARD", "MSUF2_UF_DISPEL_SYMBOL_STYLE", 16, -62)
    local modeDrop = BindDropdown("Show", UNIT_DISPEL_SYMBOL_MODES, "unitDispelSymbolMode",
        "ALL", "MSUF2_UF_DISPEL_SYMBOL_MODE", 16, -114)
    local triggerDrop = BindDropdown("Symbol detects", UNIT_DISPEL_TRIGGERS, "unitDispelSymbolTrigger",
        "BORDER", "MSUF2_UF_DISPEL_SYMBOL_TRIGGER", 16, -166)
    local anchorDrop = BindDropdown("Symbol anchor", UNIT_DISPEL_SYMBOL_ANCHORS, "unitDispelSymbolAnchor",
        "TOPRIGHT", "MSUF2_UF_DISPEL_SYMBOL_ANCHOR", 16, -218)
    local sizeSlider = BindSlider("Symbol size", "unitDispelSymbolSize", 14, 4, 48, 1,
        "MSUF2_UF_DISPEL_SYMBOL_SIZE", 16, -270)
    local offsetXSlider = BindSlider("Offset X", "unitDispelSymbolX", 0, -128, 128, 1,
        "MSUF2_UF_DISPEL_SYMBOL_X", 16, -318)
    local offsetYSlider = BindSlider("Offset Y", "unitDispelSymbolY", 0, -128, 128, 1,
        "MSUF2_UF_DISPEL_SYMBOL_Y", 16, -366)
    local growthDrop = BindDropdown("Grow", UNIT_DISPEL_SYMBOL_GROWTH, "unitDispelSymbolGrowth",
        "RIGHT", "MSUF2_UF_DISPEL_SYMBOL_GROWTH", rightX, wide and -218 or -414)
    local spacingSlider = BindSlider("Symbol spacing", "unitDispelSymbolSpacing", 2, 0, 32, 1,
        "MSUF2_UF_DISPEL_SYMBOL_SPACING", rightX, wide and -270 or -462)
    local alphaSlider = BindSlider("Symbol opacity", "unitDispelSymbolAlpha", 1, 0.05, 1, 0.05,
        "MSUF2_UF_DISPEL_SYMBOL_ALPHA", rightX, wide and -318 or -510)
    local layerSlider = BindSlider("Effect Layer (0-30)", "unitDispelSymbolLayer", 8, 0, 30, 1,
        "MSUF2_UF_DISPEL_SYMBOL_LAYER", rightX, wide and -366 or -558)
    local strataDrop = BindDropdown("Symbol strata", UNIT_DISPEL_SYMBOL_STRATA, "unitDispelSymbolStrata",
        "AUTO", "MSUF2_UF_DISPEL_SYMBOL_STRATA", rightX, wide and -414 or -606)
    local preview = W.ToggleAt(card, "Preview symbol (drag to place)", rightX, wide and -62 or -654, sliderW)
    M.BindBoolWidget(ctx, preview,
        function() return _G.MSUF_DispelSymbolPreviewMode == true and _G.MSUF_DispelSymbolPreviewScope == unit end,
        function(value)
            local fn = _G.MSUF_SetDispelSymbolPreview
            if type(fn) == "function" then fn(value and true or false, unit) end
        end,
        Meta(ctx, unit, "symbol.preview", nil, "ephemeral"))
    preview:HookScript("OnHide", function(self)
        local fn = _G.MSUF_SetDispelSymbolPreview
        if _G.MSUF_DispelSymbolPreviewMode == true and _G.MSUF_DispelSymbolPreviewScope == unit
            and type(fn) == "function"
        then
            fn(false)
            if self.SetChecked then self:SetChecked(false) end
        end
    end)
    if M.AddTooltip then
        M.AddTooltip(preview, "Preview symbol",
            "Shows stand-in symbols so placement can be judged without a real debuff, and lets you drag them into position. Turns itself off when this page closes.",
            { hook = true })
    end
    local controls = { styleDrop, modeDrop, triggerDrop, anchorDrop, sizeSlider, offsetXSlider,
        offsetYSlider, alphaSlider, layerSlider, strataDrop, preview }
    local allModeControls = { growthDrop, spacingSlider }
    local hint = W.Text(card, SourceHint(unit), 16, wide and -462 or -702, cardW - 32, T.colors and T.colors.muted)
    if hint.SetWordWrap then hint:SetWordWrap(true) end

    M.TrackRefresh(ctx, Sync(function()
        local enabled = ReadValue(unit, "unitDispelSymbolEnabled", false) == true
        if not enabled and _G.MSUF_DispelSymbolPreviewMode == true
            and _G.MSUF_DispelSymbolPreviewScope == unit
        then
            local clear = _G.MSUF_SetDispelSymbolPreview
            if type(clear) == "function" then clear(false) end
        end
        SetControlEnabled(master, true)
        SetControlsEnabled(controls, enabled)
        SetControlsEnabled(allModeControls, enabled and ReadValue(unit, "unitDispelSymbolMode", "ALL") == "ALL")
        RefreshSourceHint(hint, unit)
    end))
end

if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "unit_dispel_overlay",
        title = "Dispel Overlay",
        height = OverlaySectionHeight,
        placement = "after_auras",
        order = 10,
        units = SUPPORTED_UNITS,
        build = BuildUnitDispelOverlaySection,
    })
    UP.RegisterSection({
        id = "unit_dispel_symbol",
        title = "Dispel Symbol",
        height = SymbolSectionHeight,
        placement = "after_auras",
        order = 20,
        units = SUPPORTED_UNITS,
        build = BuildUnitDispelSymbolSection,
    })
end
