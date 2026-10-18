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
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()

local SUPPORTED_UNITS = { player = true, target = true, focus = true, boss = true, arena = true }
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

local NormalizeDispelTrigger = _G.MSUF_NormalizeDispelBorderTrigger

local function NormalizeUnitDispelOverlayTrigger(value)
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
    if type(M.RequestUnitDomains) == "function" then
        return M.RequestUnitDomains(unit, reason, UNIT_APPLY_OPTS)
    end
    local service = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if service and type(service.RequestUnitDomains) == "function" then
        return service.RequestUnitDomains(unit, reason, UNIT_APPLY_OPTS)
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

local ModeEnabled = _G.MSUF_UF_OutlineModeEnabled

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
        meta.searchSettingKeys = { tostring(unit) .. "." .. tostring(key), "general." .. tostring(key) }
    end
    return meta
end

local function OverlaySectionHeight()
    return 390
end

-- Section master switches sit in the collapsible header; both sections share the shape.
local MASTER_SWITCHES = {
    overlay = { label = "Dispel Overlay", key = "unitDispelOverlayEnabled", reason = "MSUF2_UF_DISPEL_OVERLAY" },
    symbol = { label = "Dispel Symbol", key = "unitDispelSymbolEnabled", reason = "MSUF2_UF_DISPEL_SYMBOL" },
}
local function PrepareSwitch(ctx, sec, unit, which)
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local def = MASTER_SWITCHES[which]
    local meta = Meta(ctx, unit, which .. ".enabled", def.key)
    local master
    master = Schema.Build(ctx, sec, {{ "sectionSwitch", def.key, false, { def.label }, meta = meta,
        scope = unit, domain = "dispel",
        get = function() return ReadValue(unit, def.key, false) == true end,
        set = function(value)
            SetDispelMasterValue(unit, def.key, value, def.reason)
            if master.refreshDetails then master.refreshDetails() end
        end,
    }}, ROW_OPTIONS)[def.key]
    return master
end

-- Runtime previews paint the live UnitFrame through a core hook and clear when the page closes.
local PREVIEW_HOOKS = {
    overlay = { mode = "MSUF_DispelOverlayPreviewMode", scope = "MSUF_DispelOverlayPreviewScope",
        set = "MSUF_SetDispelOverlayPreview", label = "Runtime Preview: live UnitFrame",
        tip =
            "Paints a stand-in tint on the live UnitFrame so the overlay can be judged without a real dispellable debuff. Turns itself off when this page closes.",
    },
    symbol = { mode = "MSUF_DispelSymbolPreviewMode", scope = "MSUF_DispelSymbolPreviewScope",
        set = "MSUF_SetDispelSymbolPreview", label = "Runtime Preview: live UnitFrame (drag)",
        tip =
            "Shows stand-in symbols on the live UnitFrame and lets you drag them into position without a real debuff. Turns itself off when this page closes.",
    },
}
local function PreviewToggle(ctx, unit, card, which, x, y, width)
    local hook = PREVIEW_HOOKS[which]
    local function Active() return _G[hook.mode] == true and _G[hook.scope] == unit end
    local meta = Meta(ctx, unit, which .. ".preview", nil, "ephemeral")
    local preview = Schema.Build(ctx, card, {{ "toggle", "preview", false, { hook.label, x, y, width }, meta = meta,
        scope = unit, domain = "dispelPreview", get = Active,
        set = function(value)
            local fn = _G[hook.set]
            if type(fn) == "function" then fn(value and true or false, unit) end
        end,
    }}, ROW_OPTIONS).preview
    preview:HookScript("OnHide", function(self)
        local fn = _G[hook.set]
        if Active() and type(fn) == "function" then
            fn(false)
            if self.SetChecked then self:SetChecked(false) end
        end
    end)
    if M.AddTooltip then M.AddTooltip(preview, "Runtime Preview", hook.tip, { hook = true }) end
    return preview
end

-- Rows keep the old per-card read/write rules: stored value, then general fallback.
local function Row(ctx, unit, section, row, Sync, x, y, move, toggleWidth)
    local key, default, normalize = row.key, row.default, row.normalize
    local meta = Meta(ctx, unit, section .. "." .. key, key)
    local args, placement
    if row.kind == "toggle" then args = { row.label, x, y, toggleWidth }
    elseif row.kind == "dropdown" then args, placement = { row.label, row.values, 280 }, { x, y, move.dropdown, "LEFT" }
    else args, placement = { row.label, row.range[1], row.range[2], row.range[3], 340 }, { x, y, move.slider, "CENTER" } end
    local spec = { row.kind, key, default, args, placement, meta = meta, scope = unit, domain = "dispel" }
    if row.kind == "dropdown" then
        spec.get = function()
            local value = ReadValue(unit, key, default)
            return normalize and normalize(value) or value
        end
    elseif row.kind == "toggle" then
        spec.get = function() return ReadValue(unit, key, default) ~= false end
    else
        spec.get = function() return tonumber(ReadValue(unit, key, default)) or default end
    end
    spec.set = function(value)
        if row.kind == "dropdown" then value = normalize and normalize(value) or (value or default)
        elseif row.kind == "toggle" then value = value and true or false
        else value = tonumber(value) or default end
        SetValue(unit, key, value, row.reason)
        if row.sync then Sync() end
    end
    return spec
end

local OVERLAY_ROWS = {
    { kind = "dropdown", label = "Overlay detects", values = UNIT_DISPEL_TRIGGERS, key = "unitDispelOverlayTrigger",
        default = "BORDER", normalize = NormalizeUnitDispelOverlayTrigger, reason = "MSUF2_UF_DISPEL_OVERLAY_TRIGGER", y = -54 },
    { kind = "dropdown", label = "Overlay style", values = UNIT_DISPEL_STYLES, key = "unitDispelOverlayStyle",
        default = "FULL", reason = "MSUF2_UF_DISPEL_OVERLAY_STYLE", y = -106 },
    { kind = "toggle", label = "Show on current health only", key = "unitDispelOverlayOnHealth", default = true,
        reason = "MSUF2_UF_DISPEL_OVERLAY_HEALTH", y = -154, sync = true },
    { kind = "slider", label = "Overlay opacity", range = { 0.05, 1, 0.05 }, key = "unitDispelOverlayAlpha",
        default = 0.35, reason = "MSUF2_UF_DISPEL_OVERLAY_ALPHA", y = -198 },
}

local function BuildUnitDispelOverlaySection(ctx, builder, unit)
    local section = Schema.Section(builder:CollapsibleSection("unit_dispel_overlay", "Dispel Overlay", OverlaySectionHeight(ctx), false), unit)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    local card = Schema.Build(ctx, section, {{ "card", "dispel.overlay.card", nil, { nil, nil, 20, -38, cardW, 326 },
        scope = unit, domain = "layout" }})["dispel.overlay.card"]
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
    local master = PrepareSwitch(ctx, section, unit, "overlay")
    master.refreshDetails = function() Sync() end
    local move = { dropdown = min(280, cardW - 32), slider = min(360, cardW - 72) }
    local controls = {}
    for _, row in ipairs(OVERLAY_ROWS) do
        controls[#controls + 1] = Schema.Build(ctx, card, { Row(ctx, unit, "overlay", row, Sync, 16, row.y, move, cardW - 32) }, ROW_OPTIONS)[row.key]
    end
    controls[#controls + 1] = PreviewToggle(ctx, unit, card, "overlay", 16, -246, cardW - 32)
    local warning = Schema.Build(ctx, card, {{ "text", "dispel.overlay.warning", nil, { UNITFRAME_DISPEL_AURA_WARNING, 16, -286, cardW - 32,
        UNITFRAME_DISPEL_AURA_WARNING_COLOR }, scope = unit }})["dispel.overlay.warning"]
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

local SYMBOL_ROWS = {
    { kind = "dropdown", label = "Symbol set", values = UNIT_DISPEL_SYMBOL_STYLES, key = "unitDispelSymbolStyle",
        default = "BLIZZARD", reason = "MSUF2_UF_DISPEL_SYMBOL_STYLE", col = 1, yWide = -68, yNarrow = -106 },
    { kind = "dropdown", label = "Show", values = UNIT_DISPEL_SYMBOL_MODES, key = "unitDispelSymbolMode",
        default = "ALL", reason = "MSUF2_UF_DISPEL_SYMBOL_MODE", col = 1, yWide = -120, yNarrow = -158 },
    { kind = "dropdown", label = "Symbol detects", values = UNIT_DISPEL_TRIGGERS, key = "unitDispelSymbolTrigger",
        default = "BORDER", reason = "MSUF2_UF_DISPEL_SYMBOL_TRIGGER", col = 1, yWide = -172, yNarrow = -210 },
    { kind = "slider", label = "Symbol size", range = { 4, 48, 1 }, key = "unitDispelSymbolSize", default = 14,
        reason = "MSUF2_UF_DISPEL_SYMBOL_SIZE", col = 1, yWide = -224, yNarrow = -262 },
    { kind = "slider", label = "Symbol opacity", range = { 0.05, 1, 0.05 }, key = "unitDispelSymbolAlpha", default = 1,
        reason = "MSUF2_UF_DISPEL_SYMBOL_ALPHA", col = 1, yWide = -272, yNarrow = -310 },
    { kind = "dropdown", label = "Symbol anchor", values = UNIT_DISPEL_SYMBOL_ANCHORS, key = "unitDispelSymbolAnchor",
        default = "TOPRIGHT", reason = "MSUF2_UF_DISPEL_SYMBOL_ANCHOR", col = 2, yWide = -68, yNarrow = -362 },
    { kind = "dropdown", label = "Grow", values = UNIT_DISPEL_SYMBOL_GROWTH, key = "unitDispelSymbolGrowth",
        default = "RIGHT", reason = "MSUF2_UF_DISPEL_SYMBOL_GROWTH", col = 2, yWide = -120, yNarrow = -414, allMode = true },
    { kind = "slider", label = "Symbol spacing", range = { 0, 32, 1 }, key = "unitDispelSymbolSpacing", default = 2,
        reason = "MSUF2_UF_DISPEL_SYMBOL_SPACING", col = 2, yWide = -172, yNarrow = -462, allMode = true },
    { kind = "slider", label = "Effect Layer (0-30)", range = { 0, 30, 1 }, key = "unitDispelSymbolLayer", default = 8,
        reason = "MSUF2_UF_DISPEL_SYMBOL_LAYER", col = 2, yWide = -224, yNarrow = -510 },
    { kind = "dropdown", label = "Symbol strata", values = UNIT_DISPEL_SYMBOL_STRATA, key = "unitDispelSymbolStrata",
        default = "AUTO", reason = "MSUF2_UF_DISPEL_SYMBOL_STRATA", col = 2, yWide = -272, yNarrow = -558 },
}

local function BuildUnitDispelSymbolSection(ctx, builder, unit)
    local section = Schema.Section(builder:CollapsibleSection("unit_dispel_symbol", "Dispel Symbol", SymbolSectionHeight(ctx), false), unit)
    local sectionW = section._msuf2Width or ctx.width or 720
    local cardW = min(900, max(320, sectionW - 40))
    local wide = cardW >= 760
    local card = Schema.Build(ctx, section, {{ "card", "dispel.symbol.card", nil, { nil, nil, 20, -38, cardW, wide and 368 or 646 },
        scope = unit, domain = "layout" }})["dispel.symbol.card"]
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
        meta.searchSettingKeys = { unitSettingKey, legacySettingKey }
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
                return UP.WriteDispelSymbolOffsets("player", x, y, "MSUF2_UF_DISPEL_SYMBOL_SEARCH_OFFSET")
            end,
        }
        M.RegisterVirtualRuntimeControl(meta, "unit-preview-offset")
    end
    RegisterPreviewOffsetVirtual("x", "player.unitDispelSymbolX", "general.unitDispelSymbolX",
        "UnitFrame Dispel Symbol Offset X")
    RegisterPreviewOffsetVirtual("y", "player.unitDispelSymbolY", "general.unitDispelSymbolY",
        "UnitFrame Dispel Symbol Offset Y")

    local master = PrepareSwitch(ctx, section, unit, "symbol")
    master.refreshDetails = function() Sync() end
    --- Distinct from the Overlay card's preview on the same page: this one is
    --- draggable, and two identically labelled toggles gave no way to tell
    --- them apart. The "(drag)" wording already ships in every locale.
    local preview = PreviewToggle(ctx, unit, card, "symbol", previewX, wide and -16 or -54, previewW)
    local controls, allModeControls, move = {}, {}, { dropdown = controlW, slider = controlW }
    for _, row in ipairs(SYMBOL_ROWS) do
        row.sync = row.kind == "dropdown"
        local list = row.allMode and allModeControls or controls
        list[#list + 1] = Schema.Build(ctx, card, { Row(ctx, unit, "symbol", row, Sync,
            row.col == 1 and leftX or rightX, wide and row.yWide or row.yNarrow, move) }, ROW_OPTIONS)[row.key]
    end
    controls[#controls + 1] = preview
    local warning = Schema.Build(ctx, card, {{ "text", "dispel.symbol.warning", nil, { UNITFRAME_DISPEL_AURA_WARNING, 16, wide and -328 or -606, cardW - 32,
        UNITFRAME_DISPEL_AURA_WARNING_COLOR }, scope = unit }})["dispel.symbol.warning"]
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
        prepareShell = function(ctx, section, unit)
            return PrepareSwitch(ctx, section, unit, "overlay")
        end,
    })
    UP.RegisterSection({
        id = "unit_dispel_symbol",
        title = "Dispel Symbol",
        height = SymbolSectionHeight,
        placement = "after_auras",
        order = 20,
        units = SUPPORTED_UNITS,
        build = BuildUnitDispelSymbolSection,
        prepareShell = function(ctx, section, unit)
            return PrepareSwitch(ctx, section, unit, "symbol")
        end,
    })
end
