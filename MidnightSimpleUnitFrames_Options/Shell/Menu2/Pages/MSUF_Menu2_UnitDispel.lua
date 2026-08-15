local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- UnitFrame dispel presentation belongs beside the unit's Aura workspace and
-- is owned by that unit.  general.* remains a legacy/default fallback only;
-- changing Player must never mutate Target/Focus/Boss.
local W = M.Widgets or {}
local UP = M.UnitPage or {}
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil
local VT = M.ValueTextList
local SetControlEnabled = UP.SetControlEnabled or W.SetControlEnabled
local SetControlsEnabled = W.SetControlsEnabled
local GetConf = UP.GetConf
local GetGeneral = UP.GetGeneral

local SUPPORTED_UNITS = { player = true, target = true, focus = true, boss = true }
local UNITFRAME_DISPEL_AURA_WARNING = "Dispel Border, Overlay, and Symbol need this UnitFrame's Aura sensor. Enable Buffs or Debuffs, or turn on this Dispel feature to enable the sensor automatically. Set both icon caps to 0 if you want no aura icons."
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = { 0.90, 0.84, 0.76, 1 }
local UNIT_APPLY_OPTS = { history = false, preview = true, auras = true, notify = false }
local DISPEL_COLOR_REFERENCES = {
    "aura.dispel.magic", "aura.dispel.curse", "aura.dispel.disease",
    "aura.dispel.poison", "aura.dispel.bleed",
}

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

local function ValueOwner(unit)
    return GetConf and GetConf(unit) or nil
end

local function ReadValue(unit, key, defaultValue)
    local conf = GetConf and GetConf(unit)
    local value = conf and conf[key]
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
    return RequestUnitRuntime(unit, reason or "MSUF2_UF_DISPEL")
end

local function SetValue(unit, key, value, reason)
    if not StoreValue(unit, key, value) then return false end
    RequestRuntime(unit, reason)
    return true
end

local function SymbolOffset(value)
    value = tonumber(value) or 0
    value = value >= 0 and floor(value + 0.5) or ceil(value - 0.5)
    return min(128, max(-128, value))
end

function UP.ReadDispelSymbolOffsets(unit)
    if not SUPPORTED_UNITS[unit] then return nil end
    return SymbolOffset(ReadValue(unit, "unitDispelSymbolX", 0)),
        SymbolOffset(ReadValue(unit, "unitDispelSymbolY", 0)),
        "unitDispelSymbolX", "unitDispelSymbolY"
end

function UP.WriteDispelSymbolOffsets(unit, x, y, reason, applyRuntime)
    if not SUPPORTED_UNITS[unit] then return false end
    local changed = StoreValue(unit, "unitDispelSymbolX", SymbolOffset(x))
    changed = StoreValue(unit, "unitDispelSymbolY", SymbolOffset(y)) or changed
    if changed and applyRuntime ~= false then RequestRuntime(unit, reason) end
    return true
end

function UP.ApplyDispelSymbolOffsets(unit, reason)
    if not SUPPORTED_UNITS[unit] then return false end
    return RequestRuntime(unit, reason)
end

local function UnitAuraEnabled(unit)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.UnitEnabled) == "function") then return true end
    return model.UnitEnabled(unit) == true
end

local function ModeEnabled(value, fallback)
    if value == nil then value = fallback end
    if value == true or value == false then return value end
    value = tonumber(value)
    if value == nil then return fallback == true end
    return value == 1
end

local function UnitDispelRequested(unit)
    if ReadValue(unit, "unitDispelOverlayEnabled", false) == true
        or ReadValue(unit, "unitDispelSymbolEnabled", false) == true then
        return true
    end
    local conf, general = GetConf(unit), GetGeneral()
    local mode
    if conf and conf.hlOverride == true then mode = conf.dispelOutlineMode end
    if mode == nil then mode = general and general.dispelOutlineMode end
    local legacy = general and (general.dispelBorderEnabled == true or general.hlDispelBorderEnabled == true)
    if general and general.dispelBorderEnabled == nil and general.hlDispelBorderEnabled == nil then legacy = true end
    return ModeEnabled(mode, legacy)
end

local function SetDispelMasterValue(unit, key, enabled, reason)
    enabled = enabled and true or false
    local changed = StoreValue(unit, key, enabled)
    local sensorChanged = false
    if enabled and not UnitAuraEnabled(unit) then
        local a3 = MSUF and MSUF.MSUF_Auras3
        local model = a3 and a3.MenuModel
        if model and type(model.SetUnitEnabled) == "function" then
            model.SetUnitEnabled(unit, true)
            sensorChanged = true
            if type(M.ShowStatusFeedback) == "function" then
                M.ShowStatusFeedback("Aura sensor enabled for Dispel. Buff and Debuff icon caps may stay at 0.", "info", 3.0)
            end
        end
    end
    if changed or sensorChanged then RequestRuntime(unit, reason) end
    return changed or sensorChanged
end

local function RefreshAuraWarning(warning, unit)
    if not warning then return end
    warning:SetShown(UnitDispelRequested(unit) and not UnitAuraEnabled(unit))
end

local function Meta(ctx, unit, path, key, classification)
    local meta = UP.ControlMeta and UP.ControlMeta(ctx, "dispel." .. tostring(path), classification or "setting") or {}
    if key then
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "This control is owned by the UnitFrame currently open in Menu2."
        meta.assistantSettingKeys = { tostring(unit) .. "." .. tostring(key), "general." .. tostring(key) }
    end
    return meta
end

local function OverlaySectionHeight()
    return 390
end

local function BuildUnitDispelOverlaySection(ctx, builder, unit)
    local sectionHeight = OverlaySectionHeight(ctx)
    local section = builder:CollapsibleSection("unit_dispel_overlay", "Dispel Overlay", sectionHeight, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    local card = W.ControlCard(section, nil, nil, 20, -38, cardW, 326)
    local Sync = M.RefreshProxy()
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(section, DISPEL_COLOR_REFERENCES, {
            title = "Dispel Type Colors",
            note = "Shared by Dispel borders, overlays, symbols, and every related preview.",
            scopeTag = "Shared",
            historySource = "menu:unit-dispel-overlay-colors",
            maxTargets = 5,
        })
    end

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

    local master = W.SwitchAt(card, "Dispel Overlay", 16, -16, 0, "HIDDEN")
    M.BindBoolWidget(ctx, master,
        function() return ReadValue(unit, "unitDispelOverlayEnabled", false) == true end,
        function(value)
            SetDispelMasterValue(unit, "unitDispelOverlayEnabled", value, "MSUF2_UF_DISPEL_OVERLAY")
            Sync()
        end,
        Meta(ctx, unit, "overlay.enabled", "unitDispelOverlayEnabled"))
    local controls = {
        BindDropdown("Overlay detects", UNIT_DISPEL_TRIGGERS, "unitDispelOverlayTrigger", "BORDER",
            NormalizeUnitDispelOverlayTrigger, "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", -54),
        BindDropdown("Overlay style", UNIT_DISPEL_STYLES, "unitDispelOverlayStyle", "FULL", nil,
            "MSUF2_UF_DISPEL_OVERLAY_STYLE", -106),
        BindToggle("Show on current health only", "unitDispelOverlayOnHealth", true,
            "MSUF2_UF_DISPEL_OVERLAY_HEALTH", -154),
        BindSlider("Overlay opacity", "unitDispelOverlayAlpha", 0.35, "MSUF2_UF_DISPEL_OVERLAY_ALPHA", -198),
    }
    local preview = W.ToggleAt(card, "Runtime Preview: live UnitFrame", 16, -246, cardW - 32)
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
        M.AddTooltip(preview, "Runtime Preview",
            "Paints a stand-in tint on the live UnitFrame so the overlay can be judged without a real dispellable debuff. Turns itself off when this page closes.",
            { hook = true })
    end
    controls[#controls + 1] = preview
    local warning = W.Text(card, UNITFRAME_DISPEL_AURA_WARNING, 16, -286, cardW - 32,
        UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if warning.SetWordWrap then warning:SetWordWrap(true) end

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
        RefreshAuraWarning(warning, unit)
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
        UP.WriteDispelSymbolOffsets(scope, x, y, "MSUF2_UF_DISPEL_SYMBOL_DRAG")
        local sync = symbolSyncByUnit[scope]
        if type(sync) == "function" then sync() end
    end)
    symbolMoveHandlerInstalled = true
end

local function SymbolSectionHeight(ctx)
    local width = min(900, max(320, (((ctx and ctx.width) or 720) - 40)))
    return width >= 760 and 432 or 710
end

local function BuildUnitDispelSymbolSection(ctx, builder, unit)
    local sectionHeight = SymbolSectionHeight(ctx)
    local section = builder:CollapsibleSection("unit_dispel_symbol", "Dispel Symbol", sectionHeight, false)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    local wide = cardW >= 760
    local card = W.ControlCard(section, nil, nil, 20, -38, cardW, wide and 368 or 646)
    local Sync = M.RefreshProxy()
    symbolSyncByUnit[unit] = Sync
    EnsureSymbolMoveHandler()
    local leftX, columnGap = 16, 24
    local controlW = wide and floor((cardW - 32 - columnGap) * 0.5) or min(360, cardW - 32)
    local rightX = wide and (leftX + controlW + columnGap) or leftX
    local previewW = wide and min(380, cardW - 32) or controlW
    local previewX = wide and floor((cardW - previewW) * 0.5) or leftX

    local function RegisterPreviewOffsetVirtual(axis, unitSettingKey, legacySettingKey, label)
        if unit ~= "player" or type(M.RegisterVirtualRuntimeControl) ~= "function" then return end
        local path = "preview.selection.dispel_symbol_offset_" .. tostring(axis)
        local meta = UP.ControlMeta and UP.ControlMeta(ctx, path, "setting") or {}
        meta.kind = "textinput"
        meta.label = label
        meta.assistantDisposition = "dynamic"
        meta.assistantDispositionReason = "The lazy Unit Preview exact-offset field edits Player's Dispel Symbol coordinate."
        meta.assistantSettingKeys = { unitSettingKey, legacySettingKey }
        meta.command = {
            kind = "textinput",
            historyMode = "single",
            interaction = "preview.handle.offset",
            previewSurface = "unit",
            previewHandleKey = "dispelSymbol",
            previewUnitKey = "player",
            get = function()
                local x, y = UP.ReadDispelSymbolOffsets("player")
                return axis == "x" and x or y
            end,
            set = function(value)
                value = tonumber(value)
                if value == nil then return false end
                local x, y = UP.ReadDispelSymbolOffsets("player")
                if axis == "x" then x = value else y = value end
                return UP.WriteDispelSymbolOffsets("player", x, y, "MSUF2_UF_DISPEL_SYMBOL_ASSISTANT_OFFSET")
            end,
        }
        M.RegisterVirtualRuntimeControl(meta, "unit-preview-offset")
    end
    RegisterPreviewOffsetVirtual("x", "player.unitDispelSymbolX", "general.unitDispelSymbolX",
        "UnitFrame Dispel Symbol Offset X")
    RegisterPreviewOffsetVirtual("y", "player.unitDispelSymbolY", "general.unitDispelSymbolY",
        "UnitFrame Dispel Symbol Offset Y")

    local function BindDropdown(label, values, key, defaultValue, reason, x, y)
        local dropdown = W.Dropdown(card, label, values, 280)
        M.BindDropdownWidget(ctx, dropdown,
            function() return ReadValue(unit, key, defaultValue) end,
            function(value)
                SetValue(unit, key, value or defaultValue, reason)
                Sync()
            end,
            Meta(ctx, unit, "symbol." .. key, key))
        W.MoveWidget(dropdown, card, x, y, controlW, "LEFT")
        return dropdown
    end

    local function BindSlider(label, key, defaultValue, minValue, maxValue, step, reason, x, y)
        local slider = W.Slider(card, label, minValue, maxValue, step, 340)
        M.BindNumberWidget(ctx, slider,
            function() return tonumber(ReadValue(unit, key, defaultValue)) or defaultValue end,
            function(value) SetValue(unit, key, tonumber(value) or defaultValue, reason) end,
            defaultValue, Meta(ctx, unit, "symbol." .. key, key))
        W.MoveWidget(slider, card, x, y, controlW, "CENTER")
        return slider
    end

    local master = W.SwitchAt(card, "Dispel Symbol", 16, -16, 0, "HIDDEN")
    M.BindBoolWidget(ctx, master,
        function() return ReadValue(unit, "unitDispelSymbolEnabled", false) == true end,
        function(value)
            SetDispelMasterValue(unit, "unitDispelSymbolEnabled", value, "MSUF2_UF_DISPEL_SYMBOL")
            Sync()
        end,
        Meta(ctx, unit, "symbol.enabled", "unitDispelSymbolEnabled"))
    --- Distinct from the Overlay card's preview on the same page: this one is
    --- draggable, and two identically labelled toggles gave no way to tell
    --- them apart. The "(drag)" wording already ships in every locale.
    local preview = W.ToggleAt(card, "Runtime Preview: live UnitFrame (drag)", previewX,
        wide and -16 or -54, previewW)
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
        M.AddTooltip(preview, "Runtime Preview",
            "Shows stand-in symbols on the live UnitFrame and lets you drag them into position without a real debuff. Turns itself off when this page closes.",
            { hook = true })
    end
    local styleDrop = BindDropdown("Symbol set", UNIT_DISPEL_SYMBOL_STYLES, "unitDispelSymbolStyle",
        "BLIZZARD", "MSUF2_UF_DISPEL_SYMBOL_STYLE", leftX, wide and -68 or -106)
    local modeDrop = BindDropdown("Show", UNIT_DISPEL_SYMBOL_MODES, "unitDispelSymbolMode",
        "ALL", "MSUF2_UF_DISPEL_SYMBOL_MODE", leftX, wide and -120 or -158)
    local triggerDrop = BindDropdown("Symbol detects", UNIT_DISPEL_TRIGGERS, "unitDispelSymbolTrigger",
        "BORDER", "MSUF2_UF_DISPEL_SYMBOL_TRIGGER", leftX, wide and -172 or -210)
    local sizeSlider = BindSlider("Symbol size", "unitDispelSymbolSize", 14, 4, 48, 1,
        "MSUF2_UF_DISPEL_SYMBOL_SIZE", leftX, wide and -224 or -262)
    local alphaSlider = BindSlider("Symbol opacity", "unitDispelSymbolAlpha", 1, 0.05, 1, 0.05,
        "MSUF2_UF_DISPEL_SYMBOL_ALPHA", leftX, wide and -272 or -310)
    local anchorDrop = BindDropdown("Symbol anchor", UNIT_DISPEL_SYMBOL_ANCHORS, "unitDispelSymbolAnchor",
        "TOPRIGHT", "MSUF2_UF_DISPEL_SYMBOL_ANCHOR", rightX, wide and -68 or -362)
    local growthDrop = BindDropdown("Grow", UNIT_DISPEL_SYMBOL_GROWTH, "unitDispelSymbolGrowth",
        "RIGHT", "MSUF2_UF_DISPEL_SYMBOL_GROWTH", rightX, wide and -120 or -414)
    local spacingSlider = BindSlider("Symbol spacing", "unitDispelSymbolSpacing", 2, 0, 32, 1,
        "MSUF2_UF_DISPEL_SYMBOL_SPACING", rightX, wide and -172 or -462)
    local layerSlider = BindSlider("Effect Layer (0-30)", "unitDispelSymbolLayer", 8, 0, 30, 1,
        "MSUF2_UF_DISPEL_SYMBOL_LAYER", rightX, wide and -224 or -510)
    local strataDrop = BindDropdown("Symbol strata", UNIT_DISPEL_SYMBOL_STRATA, "unitDispelSymbolStrata",
        "AUTO", "MSUF2_UF_DISPEL_SYMBOL_STRATA", rightX, wide and -272 or -558)
    local controls = { styleDrop, modeDrop, triggerDrop, anchorDrop, sizeSlider,
        alphaSlider, layerSlider, strataDrop, preview }
    local allModeControls = { growthDrop, spacingSlider }
    local warning = W.Text(card, UNITFRAME_DISPEL_AURA_WARNING, 16, wide and -328 or -606, cardW - 32,
        UNITFRAME_DISPEL_AURA_WARNING_COLOR)
    if warning.SetWordWrap then warning:SetWordWrap(true) end

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
        RefreshAuraWarning(warning, unit)
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
