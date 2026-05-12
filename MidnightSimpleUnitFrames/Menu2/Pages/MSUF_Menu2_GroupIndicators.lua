local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local SCOPE_VALUES = GP.SCOPE_VALUES or {}
local GROWTH_VALUES = GP.GROWTH_VALUES or {}
local HEALTH_MODES = GP.HEALTH_MODES or {}
local TEXT_MODES = GP.TEXT_MODES or {}
local ANCHORS = GP.ANCHORS or {}
local AURA_ANCHORS = GP.AURA_ANCHORS or {}
local GF_RENDERERS = GP.GF_RENDERERS or {}
local GF_AURA_FILTERS = GP.GF_AURA_FILTERS or {}
local GF_AURA_ORG = GP.GF_AURA_ORG or {}
local SORT_MODES = GP.SORT_MODES or {}
local GF_BAR_MODES = GP.GF_BAR_MODES or {}
local SIMPLE_TEXTURES = GP.SIMPLE_TEXTURES or {}
local GF_ANCHOR_TO = GP.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = GP.GF_ANCHOR_POINTS or {}
local TOOLTIP_MODES = GP.TOOLTIP_MODES or {}
local TOOLTIP_MODIFIERS = GP.TOOLTIP_MODIFIERS or {}
local STATUS_ICON_ANCHORS = GP.STATUS_ICON_ANCHORS or {}
local GF_STATUS_ICON_SPECS = GP.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES = GP.GF_STATUS_ICON_VALUES or {}
local PLACED_INDICATOR_TYPES = GP.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES = GP.FRAME_EFFECT_TYPES or {}
local SPELL_GROWTH_VALUES = GP.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES = GP.CI_SLOT_VALUES or {}
local CI_SLOT_DEFAULTS = GP.CI_SLOT_DEFAULTS or {}
local DISPEL_OVERLAY_STYLES = GP.DISPEL_OVERLAY_STYLES or {}
local DEBUFF_STRIPE_EDGES = GP.DEBUFF_STRIPE_EDGES or {}

local GF = GP.GF
local RefreshGFPreview = GP.RefreshGFPreview
local Conf = GP.Conf
local Val = GP.Val
local QueueGF = GP.QueueGF
local Set = GP.Set
local Bool = GP.Bool
local Num = GP.Num
local ScopeSection = GP.ScopeSection
local CurrentScope = GP.CurrentScope
local BindScopeToggle = GP.BindScopeToggle
local BindScopeSlider = GP.BindScopeSlider
local BindScopeDropdown = GP.BindScopeDropdown
local BuildGrowthDirectionTiles = GP.BuildGrowthDirectionTiles
local BuildRoleOrderRows = GP.BuildRoleOrderRows
local AurasRoot = GP.AurasRoot
local AuraGroup = GP.AuraGroup
local PrivateAuras = GP.PrivateAuras
local SpellIndicators = GP.SpellIndicators
local IconStyleValues = GP.IconStyleValues
local CurrentGFStatusSpec = GP.CurrentGFStatusSpec
local QueueSpellIndicators = GP.QueueSpellIndicators
local SpellSpecValues = GP.SpellSpecValues
local SpellTrackedSpecValues = GP.SpellTrackedSpecValues
local CurrentSpellMultiSpec = GP.CurrentSpellMultiSpec
local EffectiveSpellSpec = GP.EffectiveSpellSpec
local SpellAuraValues = GP.SpellAuraValues
local CurrentSpellAura = GP.CurrentSpellAura
local CurrentSpellConfig = GP.CurrentSpellConfig
local PlacedConfig = GP.PlacedConfig
local FrameEffectConfig = GP.FrameEffectConfig
local CICategoryValues = GP.CICategoryValues
local CIFilterValues = GP.CIFilterValues
local CIModeValues = GP.CIModeValues
local CurrentCISlot = GP.CurrentCISlot
local CICustomConfig = GP.CICustomConfig
local BindNestedToggle = GP.BindNestedToggle
local BindNestedSlider = GP.BindNestedSlider
local BindNestedDropdown = GP.BindNestedDropdown
local SetOptionEnabled = GP.SetOptionEnabled
local SetOptionsEnabled = GP.SetOptionsEnabled
local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local indicators = b:CollapsibleSection("indicators", "Indicators", 520, true)
    W.Text(indicators, "Aggro, dispel and target highlight are controlled from Global Style > Bars.", 14, -38, ctx.width - 28, T.colors.muted)
    indicators._msuf2CursorY = -78
    BindScopeToggle(ctx, W.Toggle(indicators, "Show group number"), "showGroupNumber", false, "visual")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number size", 6, 24, 1, 260), "groupNumberSize", 10, "font")
    BindScopeDropdown(ctx, W.Dropdown(indicators, "Group number anchor", AURA_ANCHORS, 220), "groupNumberAnchor", "TOPLEFT", "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number X", -100, 100, 1, 260), "groupNumberX", -2, "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Group number Y", -100, 100, 1, 260), "groupNumberY", 2, "geometry")
    BindScopeSlider(ctx, W.Slider(indicators, "Hover highlight border", 1, 6, 1, 260), "hlHoverSize", 1, "visual")
    BindScopeToggle(ctx, W.Toggle(indicators, "Enable Focus Glow"), "hlFocusEnabled", true, "visual")
    BindScopeSlider(ctx, W.Slider(indicators, "Focus border thickness", 1, 6, 1, 260), "hlFocusSize", 2, "visual")

    local sicons = b:CollapsibleSection("sicons", "Status Icons", 672, false)
    BindScopeDropdown(ctx, W.Dropdown(sicons, "Icon style", IconStyleValues, 260), "iconStyle", "BLIZZARD", "visual")
    BindScopeToggle(ctx, W.Toggle(sicons, "Use Midnight Style"), "useMidnightIcons", false, "visual")

    local statusSelector = W.Dropdown(sicons, "Indicator", GF_STATUS_ICON_VALUES, 260)
    M.BindDropdown(ctx, statusSelector,
        function() return CurrentGFStatusSpec().value end,
        function(value)
            for i = 1, #GF_STATUS_ICON_SPECS do
                if GF_STATUS_ICON_SPECS[i].value == value then
                    M.gfStatusIconSelection = value
                    local gf = GF()
                    if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(value) end
                    if M.SelectPage then M.SelectPage(ctx.key) end
                    return
                end
            end
        end)

    local statusEnabled = W.Toggle(sicons, "Enabled")
    M.BindToggle(ctx, statusEnabled,
        function()
            local spec = CurrentGFStatusSpec()
            return Bool(CurrentScope(), spec.enabled, true)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.enabled, value and true or false, "visual")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local statusSize = W.Slider(sicons, "Size", 6, 40, 1, 300)
    M.BindSlider(ctx, statusSize,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.size, spec.defaultSize)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.size, floor((tonumber(value) or spec.defaultSize) + 0.5), "visual")
        end)

    local statusAnchor = W.Dropdown(sicons, "Anchor", STATUS_ICON_ANCHORS, 220)
    M.BindDropdown(ctx, statusAnchor,
        function()
            local spec = CurrentGFStatusSpec()
            return Val(CurrentScope(), spec.anchor, spec.defaultAnchor)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.anchor, value or spec.defaultAnchor, "geometry")
        end)

    local statusX = W.Slider(sicons, "X Offset", -100, 100, 1, 300)
    M.BindSlider(ctx, statusX,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.x, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.x, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)

    local statusY = W.Slider(sicons, "Y Offset", -100, 100, 1, 300)
    M.BindSlider(ctx, statusY,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.y, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.y, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)

    local statusLayer = W.Slider(sicons, "Layer", 0, 30, 1, 300)
    M.BindSlider(ctx, statusLayer,
        function()
            local spec = CurrentGFStatusSpec()
            local value = Num(CurrentScope(), spec.layer, spec.defaultLayer)
            if value < 0 then value = 0 elseif value > 30 then value = 30 end
            return value
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            value = floor((tonumber(value) or spec.defaultLayer) + 0.5)
            if value < 0 then value = 0 elseif value > 30 then value = 30 end
            Set(CurrentScope(), spec.layer, value, "visual")
        end)

    local statusReset = W.Button(sicons, "Reset selected", 150)
    statusReset:SetScript("OnClick", function()
        local kind = CurrentScope()
        local spec = CurrentGFStatusSpec()
        local conf = Conf(kind)
        local gf = GF()
        for _, key in ipairs({ spec.size, spec.anchor, spec.x, spec.y, spec.layer }) do
            if key then
                conf[key] = gf and gf.GetDefault and gf.GetDefault(kind, key) or nil
            end
        end
        QueueGF(kind, "visual")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local previewCurrent = W.Button(sicons, "Preview current", 142)
    previewCurrent:SetScript("OnClick", function()
        local gf = GF()
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("current") end
        if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        QueueGF(CurrentScope(), "visual")
    end)
    local previewAll = W.Button(sicons, "Show all", 112)
    previewAll:SetScript("OnClick", function()
        local gf = GF()
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("all") end
        QueueGF(CurrentScope(), "visual")
    end)

    M.AddRefresher(ctx, function()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, true)
        SetOptionEnabled(statusSize, enabled)
        SetOptionEnabled(statusAnchor, enabled)
        SetOptionEnabled(statusX, enabled)
        SetOptionEnabled(statusY, enabled)
        SetOptionEnabled(statusLayer, enabled)
        SetOptionEnabled(statusReset, spec ~= nil)
    end)

    local spells = b:CollapsibleSection("si", "Spell Indicators", 922, false)
    M.BindToggle(ctx, W.Toggle(spells, "Enable Spell Indicators"),
        function() return SpellIndicators(CurrentScope()).enabled == true end,
        function(value)
            SpellIndicators(CurrentScope()).enabled = value and true or false
            QueueSpellIndicators(CurrentScope())
        end)
    BindNestedSlider(ctx, W.Slider(spells, "Layer", 1, 15, 1, 300), function() return SpellIndicators(CurrentScope()) end, "layer", 9, "visual")

    local specDrop = W.Dropdown(spells, "Spec", SpellSpecValues, 260)
    M.BindDropdown(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[kind] = nil
            QueueSpellIndicators(kind)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local multiSpecDrop = W.Dropdown(spells, "Multi-Spec Entry", function() return SpellTrackedSpecValues() end, 300)
    M.BindDropdown(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[CurrentScope()] = value or ""
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local multiSpecEnabled = W.Toggle(spells, "Track selected multi spec")
    M.BindToggle(ctx, multiSpecEnabled,
        function()
            local cfg = SpellIndicators(CurrentScope())
            local specKey = CurrentSpellMultiSpec(CurrentScope())
            return cfg.spec == "multi" and specKey ~= "" and cfg.multiSpecs and cfg.multiSpecs[specKey] == true
        end,
        function(value)
            local kind = CurrentScope()
            local cfg = SpellIndicators(kind)
            local specKey = CurrentSpellMultiSpec(kind)
            if specKey == "" then return end
            cfg.multiSpecs = cfg.multiSpecs or {}
            cfg.multiSpecs[specKey] = value and true or nil
            QueueSpellIndicators(kind)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local auraDrop = W.Dropdown(spells, "Spell", function() return SpellAuraValues(CurrentScope()) end, 300)
    M.BindDropdown(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[CurrentScope()] = value
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local spellEnabled = W.Toggle(spells, "Selected spell enabled")
    M.BindToggle(ctx, spellEnabled,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.enabled ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.enabled = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local onlyMine = W.Toggle(spells, "Only my cast")
    M.BindToggle(ctx, onlyMine,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.onlyOwn ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.onlyOwn = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedType = W.Dropdown(spells, "Indicator Type", PLACED_INDICATOR_TYPES, 260)
    M.BindDropdown(ctx, placedType,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.type or "none"
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if not cfg then return end
            if value == "none" then
                cfg.placed = false
            else
                cfg.placed = cfg.placed or {}
                cfg.placed.type = value or "icon"
                cfg.placed.anchor = cfg.placed.anchor or "TOPLEFT"
                cfg.placed.size = tonumber(cfg.placed.size) or 18
            end
            QueueSpellIndicators(CurrentScope())
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local placedAnchor = W.Dropdown(spells, "Indicator Anchor", STATUS_ICON_ANCHORS, 220)
    M.BindDropdown(ctx, placedAnchor,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.anchor or "TOPLEFT"
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.anchor = value or "TOPLEFT" end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedSize = W.Slider(spells, "Indicator Size", 6, 48, 1, 300)
    M.BindSlider(ctx, placedSize,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.size) or 18
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.size = floor((tonumber(value) or 18) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedX = W.Slider(spells, "Indicator X", -100, 100, 1, 300)
    M.BindSlider(ctx, placedX,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.x) or 0
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.x = floor((tonumber(value) or 0) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedY = W.Slider(spells, "Indicator Y", -100, 100, 1, 300)
    M.BindSlider(ctx, placedY,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.y) or 0
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.y = floor((tonumber(value) or 0) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedBarWidth = W.Slider(spells, "Bar Width", 8, 120, 1, 300)
    M.BindSlider(ctx, placedBarWidth,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.barWidth) or 42
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.barWidth = floor((tonumber(value) or 42) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedGrowth = W.Dropdown(spells, "Growth", SPELL_GROWTH_VALUES, 240)
    M.BindDropdown(ctx, placedGrowth,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.growth or "RIGHTDOWN"
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.growth = value or "RIGHTDOWN" end
            QueueSpellIndicators(CurrentScope())
        end)

    local frameType = W.Dropdown(spells, "Frame Effect", FRAME_EFFECT_TYPES, 260)
    M.BindDropdown(ctx, frameType,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return frame and frame.type or "none"
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if not cfg then return end
            if value == "none" then
                cfg.frame = false
            else
                cfg.frame = cfg.frame or {}
                cfg.frame.type = value
            end
            QueueSpellIndicators(CurrentScope())
        end)

    M.AddRefresher(ctx, function()
        local multi = SpellIndicators(CurrentScope()).spec == "multi"
        if W.SetControlShown then
            W.SetControlShown(multiSpecDrop, multi)
            W.SetControlShown(multiSpecEnabled, multi)
        else
            multiSpecDrop:SetShown(multi)
            multiSpecEnabled:SetShown(multi)
        end
        local placed = PlacedConfig(CurrentScope(), false)
        local placedEnabled = placed and placed.type and placed.type ~= "none"
        local hasSpell = CurrentSpellConfig(CurrentScope(), false) ~= nil
        SetOptionEnabled(spellEnabled, hasSpell)
        SetOptionEnabled(onlyMine, hasSpell)
        SetOptionEnabled(placedType, hasSpell)
        SetOptionEnabled(frameType, hasSpell)
        SetOptionEnabled(placedAnchor, placedEnabled)
        SetOptionEnabled(placedSize, placedEnabled)
        SetOptionEnabled(placedX, placedEnabled)
        SetOptionEnabled(placedY, placedEnabled)
        SetOptionEnabled(placedBarWidth, placedEnabled and placed.type == "bar")
        SetOptionEnabled(placedGrowth, placedEnabled)
    end)

    local corners = b:CollapsibleSection("ci", "Corner Indicators", 1046, false)
    BindScopeToggle(ctx, W.Toggle(corners, "Enable"), "ciEnabled", true, "visual")
    BindScopeSlider(ctx, W.Slider(corners, "Icon Size", 4, 24, 1, 300), "ciSize", 8, "visual")
    local ciAlpha = W.Slider(corners, "Alpha", 10, 100, 5, 300)
    M.BindSlider(ctx, ciAlpha,
        function() return floor((Num(CurrentScope(), "ciAlpha", 1) * 100) + 0.5) end,
        function(value) Set(CurrentScope(), "ciAlpha", (tonumber(value) or 100) / 100, "visual") end)

    for i = 1, #CI_SLOT_VALUES do
        local slotInfo = CI_SLOT_VALUES[i]
        local slotKey = slotInfo.value
        local slotDrop = W.Dropdown(corners, slotInfo.text .. " Indicator", CICategoryValues, 260)
        M.BindDropdown(ctx, slotDrop,
            function()
                return Val(CurrentScope(), "ciSlot" .. slotKey, CI_SLOT_DEFAULTS[slotKey] or "none")
            end,
            function(value)
                M.gfCornerSlotSelection = slotKey
                Set(CurrentScope(), "ciSlot" .. slotKey, value or "none", "visual")
                if M.SelectPage then M.SelectPage(ctx.key) end
            end)
    end

    local slotDrop = W.Dropdown(corners, "Custom editor slot", CI_SLOT_VALUES, 220)
    M.BindDropdown(ctx, slotDrop,
        function() return CurrentCISlot() end,
        function(value)
            M.gfCornerSlotSelection = value or "TL"
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local categoryDrop = W.Dropdown(corners, "Selected slot indicator", CICategoryValues, 260)
    M.BindDropdown(ctx, categoryDrop,
        function()
            local slot = CurrentCISlot()
            return Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        end,
        function(value)
            local slot = CurrentCISlot()
            Set(CurrentScope(), "ciSlot" .. slot, value or "none", "visual")
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local customSpells = W.TextInput(corners, "Custom Spell IDs", 380)
    M.BindTextInput(ctx, customSpells,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.spells or ""
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.spells = value or "" end
            QueueGF(CurrentScope(), "visual")
        end,
        true)

    local customMode = W.Dropdown(corners, "Custom Mode", CIModeValues, 260)
    M.BindDropdown(ctx, customMode,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.mode or "present"
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.mode = value or "present" end
            QueueGF(CurrentScope(), "visual")
        end)

    local customFilter = W.Dropdown(corners, "Custom Filter", CIFilterValues, 260)
    M.BindDropdown(ctx, customFilter,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return cfg and cfg.filter or "HELPFUL|PLAYER"
        end,
        function(value)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.filter = value or "HELPFUL|PLAYER" end
            QueueGF(CurrentScope(), "visual")
        end)

    local customColor = W.Color(corners, "Custom Color")
    M.BindColor(ctx, customColor,
        function()
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
            return (cfg and cfg.r) or 0.40, (cfg and cfg.g) or 1.00, (cfg and cfg.b) or 0.40
        end,
        function(r, g, b)
            local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
            if cfg then cfg.r, cfg.g, cfg.b = r, g, b end
            QueueGF(CurrentScope(), "visual")
        end)

    M.AddRefresher(ctx, function()
        local slot = CurrentCISlot()
        local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        local showCustom = category == "custom"
        for _, control in ipairs({ customSpells, customMode, customFilter, customColor }) do
            if control then
                control:SetShown(showCustom)
                if control._msuf2Title then control._msuf2Title:SetShown(showCustom) end
            end
        end
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_indicators", { title = "MSUF Group Indicators", build = BuildGFIndicators, version = 5 })
