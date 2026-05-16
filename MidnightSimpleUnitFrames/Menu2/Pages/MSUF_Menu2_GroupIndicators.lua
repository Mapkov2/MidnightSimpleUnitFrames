local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local Tr = M.Tr or function(text)
    if text == nil then return "" end
    local key = tostring(text)
    if type(ns.TR) == "function" then
        local translated = ns.TR(key)
        if translated ~= nil then return translated end
    end
    local locale = ns.L or _G.MSUF_L
    return (type(locale) == "table" and locale[key]) or key
end

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
local ApplyScopeEnabledGate = GP.ApplyScopeEnabledGate
local SetSectionHeaderStatus = GP.SetSectionHeaderStatus

local function HeaderHintColor()
    return { 0.45, 0.52, 0.65, 1 }
end
local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local indicators = b:CollapsibleSection("indicators", "Indicators", 650, true)
    local indicatorsW = indicators._msuf2Width or ctx.width or 720
    local leftX = 30
    local rightX = max(430, min(520, floor(indicatorsW * 0.50)))
    local leftW = max(270, min(340, rightX - leftX - 70))
    local rightW = max(280, min(360, indicatorsW - rightX - 42))

    local function IsMouseoverHighlightEnabled()
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        return not (gen and gen.highlightEnabled == false)
    end

    W.LabelAt(indicators, "Aggro / Dispel / Target Highlight", leftX, -42, 280, "GameFontNormalSmall", T.colors.accent)
    local hlHint = W.Text(indicators, "Controlled from: |cff38c7f0Global Style > Bars|r > |cff38c7f0Outline & Highlight Border|r\nEnable/disable, colors, size, offset, priority - all in one place.", leftX, -64, indicatorsW - 60, T.colors.muted)
    if hlHint.SetWordWrap then hlHint:SetWordWrap(true) end
    W.DividerAt(indicators, -112, leftX, 30)

    W.LabelAt(indicators, "Group Number", leftX, -140, 180, "GameFontNormalSmall", T.colors.accent)
    local groupNumberToggle = BindScopeToggle(ctx, W.ToggleAt(indicators, "Show Group Number", leftX, -170, leftW), "showGroupNumber", false, "visual")
    local groupNumberSize = BindScopeSlider(ctx, W.Slider(indicators, "Size", 6, 24, 1, leftW), "groupNumberSize", 10, "font")
    local groupNumberAnchor = BindScopeDropdown(ctx, W.Dropdown(indicators, "Anchor", AURA_ANCHORS, leftW), "groupNumberAnchor", "BOTTOMRIGHT", "geometry")
    local groupNumberX = BindScopeSlider(ctx, W.Slider(indicators, "X Offset", -100, 100, 1, leftW), "groupNumberX", -2, "geometry")
    local groupNumberY = BindScopeSlider(ctx, W.Slider(indicators, "Y Offset", -100, 100, 1, leftW), "groupNumberY", 2, "geometry")
    W.MoveWidget(groupNumberSize, indicators, leftX, -214, leftW, "CENTER")
    W.MoveWidget(groupNumberAnchor, indicators, leftX, -268, leftW, "LEFT")
    W.MoveWidget(groupNumberX, indicators, leftX, -322, leftW, "CENTER")
    W.MoveWidget(groupNumberY, indicators, leftX, -376, leftW, "CENTER")

    W.LabelAt(indicators, "Hover Highlight", rightX, -140, 180, "GameFontNormalSmall", T.colors.accent)
    local hoverHint = W.Text(indicators, "Enable + color: |cff38c7f0Global Style > Colors|r > Mouseover Highlight", rightX, -162, rightW, T.colors.muted)
    local hoverSize = W.Slider(indicators, "Border Thickness", 1, 6, 1, rightW)
    M.BindSlider(ctx, hoverSize,
        function()
            local gf = GF and GF()
            if gf and type(gf.GetHighlightVal) == "function" then
                return tonumber(gf.GetHighlightVal(CurrentScope(), "hlHoverSize")) or 1
            end
            return Num(CurrentScope(), "hlHoverSize", 1)
        end,
        function(value)
            local kind = CurrentScope()
            local conf = Conf(kind)
            conf.hlHoverSize = floor((tonumber(value) or 1) + 0.5)
            conf.hlOverride = true
            QueueGF(kind, "visual")
        end)
    W.MoveWidget(hoverSize, indicators, rightX, -210, rightW, "CENTER")

    W.LabelAt(indicators, "Focus Highlight", rightX, -274, 180, "GameFontNormalSmall", T.colors.accent)
    local focusToggle = BindScopeToggle(ctx, W.ToggleAt(indicators, "Enable Focus Glow", rightX, -304, rightW), "hlFocusEnabled", true, "visual")
    local focusHint = W.Text(indicators, "Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus.", rightX, -332, rightW, T.colors.muted)
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusSize = BindScopeSlider(ctx, W.Slider(indicators, "Border Thickness", 1, 6, 1, rightW), "hlFocusSize", 2, "visual")
    local focusColor = W.Color(indicators, "Focus Glow Color")
    M.BindColor(ctx, focusColor,
        function()
            return Num(CurrentScope(), "hlFocusColorR", 0.50),
                Num(CurrentScope(), "hlFocusColorG", 0.50),
                Num(CurrentScope(), "hlFocusColorB", 1.00)
        end,
        function(r, g, bcol)
            local conf = Conf(CurrentScope())
            conf.hlFocusColorR = r
            conf.hlFocusColorG = g
            conf.hlFocusColorB = bcol
            QueueGF(CurrentScope(), "visual")
        end)
    W.MoveWidget(focusSize, indicators, rightX, -384, rightW, "CENTER")
    W.MoveWidget(focusColor, indicators, rightX, -438, rightW)

    W.LabelAt(indicators, "Group Border", leftX, -430, 180, "GameFontNormalSmall", T.colors.accent)
    local groupBorderToggle = BindScopeToggle(ctx, W.ToggleAt(indicators, "Show Group Border", leftX, -460, leftW), "groupBorderEnabled", false, "visual")
    local groupBorderSize = BindScopeSlider(ctx, W.Slider(indicators, "Border Thickness", 1, 12, 1, leftW), "groupBorderSize", 1, "visual")
    local groupBorderPadding = BindScopeSlider(ctx, W.Slider(indicators, "Padding", 0, 40, 1, leftW), "groupBorderPadding", 2, "visual")
    local groupBorderColor = W.Color(indicators, "Group Border Color")
    M.BindColor(ctx, groupBorderColor,
        function()
            return Num(CurrentScope(), "groupBorderR", 0.38),
                Num(CurrentScope(), "groupBorderG", 0.68),
                Num(CurrentScope(), "groupBorderB", 1.00)
        end,
        function(r, g, bcol)
            local conf = Conf(CurrentScope())
            conf.groupBorderR = r
            conf.groupBorderG = g
            conf.groupBorderB = bcol
            QueueGF(CurrentScope(), "visual")
        end)
    W.MoveWidget(groupBorderSize, indicators, leftX, -504, leftW, "CENTER")
    W.MoveWidget(groupBorderPadding, indicators, leftX, -558, leftW, "CENTER")
    W.MoveWidget(groupBorderColor, indicators, leftX, -614, leftW)

    local groupNumberControls = { groupNumberSize, groupNumberAnchor, groupNumberX, groupNumberY }
    local focusControls = { focusSize, focusColor }
    local groupBorderControls = { groupBorderSize, groupBorderPadding, groupBorderColor }
    local function RefreshIndicatorsState()
        local groupNumberEnabled = Bool(CurrentScope(), "showGroupNumber", false)
        SetOptionsEnabled(groupNumberControls, groupNumberEnabled)
        SetOptionEnabled(groupNumberToggle, true)

        local hoverEnabled = IsMouseoverHighlightEnabled()
        SetOptionEnabled(hoverSize, hoverEnabled)
        local hoverColor = hoverEnabled and T.colors.muted or T.colors.dim
        hoverHint:SetTextColor(hoverColor[1], hoverColor[2], hoverColor[3], hoverEnabled and 1 or 0.70)

        local focusEnabled = Bool(CurrentScope(), "hlFocusEnabled", true)
        SetOptionsEnabled(focusControls, focusEnabled)
        SetOptionEnabled(focusToggle, true)
        local focusColorText = focusEnabled and T.colors.muted or T.colors.dim
        focusHint:SetTextColor(focusColorText[1], focusColorText[2], focusColorText[3], focusEnabled and 1 or 0.70)

        local groupBorderEnabled = Bool(CurrentScope(), "groupBorderEnabled", false)
        SetOptionsEnabled(groupBorderControls, groupBorderEnabled)
        SetOptionEnabled(groupBorderToggle, true)
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(indicators, nil) end
    end
    M.AddRefresher(ctx, RefreshIndicatorsState)
    RefreshIndicatorsState()
    do
        local entry = indicators and indicators._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshIndicatorsState end
    end

    local sicons = b:CollapsibleSection("sicons", "Status Icons", 444, false)
    local siconW = sicons._msuf2Width or ctx.width or 720
    local siconLeftX = 30
    local siconRightX = max(410, min(540, floor(siconW * 0.52)))
    local siconLeftW = max(250, min(330, siconRightX - siconLeftX - 70))
    local siconRightW = max(280, min(380, siconW - siconRightX - 34))

    W.LabelAt(sicons, "Style", siconLeftX, -42, siconLeftW, "GameFontNormalSmall", T.colors.accent)
    local iconStyle = BindScopeDropdown(ctx, W.Dropdown(sicons, "Icon style", IconStyleValues, siconLeftW), "iconStyle", "BLIZZARD", "visual")
    W.MoveWidget(iconStyle, sicons, siconLeftX, -66, siconLeftW, "LEFT")
    local midnightStyle = BindScopeToggle(ctx, W.ToggleAt(sicons, "Use Midnight Style", siconLeftX, -126, siconLeftW), "useMidnightIcons", false, "visual")

    W.LabelAt(sicons, "Selected Indicator", siconLeftX, -174, siconLeftW, "GameFontNormalSmall", T.colors.accent)
    local statusSelector = W.Dropdown(sicons, "Indicator", GF_STATUS_ICON_VALUES, siconLeftW)
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
    W.MoveWidget(statusSelector, sicons, siconLeftX, -198, siconLeftW, "LEFT")

    local statusEnabled = W.ToggleAt(sicons, "Enabled", siconLeftX, -260, siconLeftW)
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

    -- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = CreateFrame("Frame", nil, sicons)
    roleFilterGroup:SetPoint("TOPLEFT", sicons, "TOPLEFT", 0, -294)
    roleFilterGroup:SetSize((siconLeftW + siconLeftX + 10), 60)

    W.LabelAt(roleFilterGroup, "Show for:", siconLeftX, -8, siconLeftW, "GameFontNormalSmall", T.colors.accent)

    local rfColW   = floor(siconLeftW / 3)
    local rfLabelW = rfColW - 30  -- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local rfTank   = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Tank",   siconLeftX,              -26, rfLabelW), "roleIconShowTank",   true, "visual")
    local rfHealer = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Healer", siconLeftX + rfColW,     -26, rfLabelW), "roleIconShowHealer", true, "visual")
    local rfDPS    = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "DPS",    siconLeftX + rfColW * 2, -26, rfLabelW), "roleIconShowDPS",    true, "visual")

    W.LabelAt(sicons, "Status Preview", siconRightX, -42, siconRightW, "GameFontNormalSmall", T.colors.accent)
    local previewCurrent = W.Button(sicons, "Preview current", 142)
    previewCurrent:SetScript("OnClick", function()
        local gf = GF()
        M.gfStatusPreviewMode = "current"
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("current") end
        if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        if RefreshGFPreview then RefreshGFPreview() end
    end)
    previewCurrent:ClearAllPoints()
    previewCurrent:SetPoint("TOPLEFT", sicons, "TOPLEFT", siconRightX, -66)
    previewCurrent:SetSize(142, 24)

    local previewAll = W.Button(sicons, "Show all", 112)
    previewAll:SetScript("OnClick", function()
        local gf = GF()
        M.gfStatusPreviewMode = "all"
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("all") end
        if RefreshGFPreview then RefreshGFPreview() end
    end)
    previewAll:ClearAllPoints()
    previewAll:SetPoint("LEFT", previewCurrent, "RIGHT", 10, 0)
    previewAll:SetSize(112, 24)

    local statusReset = W.Button(sicons, "Reset selected", 160)
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
    statusReset:ClearAllPoints()
    statusReset:SetPoint("TOPLEFT", sicons, "TOPLEFT", siconRightX, -108)
    statusReset:SetSize(160, 24)

    W.LabelAt(sicons, "Placement", siconRightX, -154, siconRightW, "GameFontNormalSmall", T.colors.accent)
    local statusSize = W.Slider(sicons, "Size", 6, 40, 1, siconRightW)
    M.BindSlider(ctx, statusSize,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.size, spec.defaultSize)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.size, floor((tonumber(value) or spec.defaultSize) + 0.5), "visual")
        end)
    W.MoveWidget(statusSize, sicons, siconRightX, -178, siconRightW, "LEFT")

    local statusAnchor = W.Dropdown(sicons, "Anchor", STATUS_ICON_ANCHORS, siconRightW)
    M.BindDropdown(ctx, statusAnchor,
        function()
            local spec = CurrentGFStatusSpec()
            return Val(CurrentScope(), spec.anchor, spec.defaultAnchor)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.anchor, value or spec.defaultAnchor, "geometry")
        end)
    W.MoveWidget(statusAnchor, sicons, siconRightX, -232, siconRightW, "LEFT")

    local statusX = W.Slider(sicons, "X Offset", -100, 100, 1, siconRightW)
    M.BindSlider(ctx, statusX,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.x, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.x, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(statusX, sicons, siconRightX, -286, siconRightW, "LEFT")

    local statusY = W.Slider(sicons, "Y Offset", -100, 100, 1, siconRightW)
    M.BindSlider(ctx, statusY,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.y, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.y, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(statusY, sicons, siconRightX, -340, siconRightW, "LEFT")

    local statusLayer = W.Slider(sicons, "Layer", 0, 30, 1, siconRightW)
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
    W.MoveWidget(statusLayer, sicons, siconRightX, -394, siconRightW, "LEFT")

    local function RefreshStatusIconState()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, true)
        SetOptionEnabled(statusSize, enabled)
        SetOptionEnabled(statusAnchor, enabled)
        SetOptionEnabled(statusX, enabled)
        SetOptionEnabled(statusY, enabled)
        SetOptionEnabled(statusLayer, enabled)
        SetOptionEnabled(statusReset, spec ~= nil)
        SetOptionEnabled(previewCurrent, spec ~= nil)
        SetOptionEnabled(previewAll, true)
        SetOptionEnabled(midnightStyle, true)
        local isRoleIcon = spec.value == "roleIcon"
        roleFilterGroup:SetShown(isRoleIcon)
        if isRoleIcon then
            SetOptionEnabled(rfTank,   enabled)
            SetOptionEnabled(rfHealer, enabled)
            SetOptionEnabled(rfDPS,    enabled)
        end
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(sicons, nil) end
    end
    M.AddRefresher(ctx, RefreshStatusIconState)
    RefreshStatusIconState()
    do
        local entry = sicons and sicons._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshStatusIconState end
    end

    local spells = b:CollapsibleSection("si", Tr("Spell Indicators"), 824, false)
    local siW = spells._msuf2Width or ctx.width or 720
    local siLeftX = 30
    local siRightX = max(430, min(560, floor(siW * 0.52)))
    local siLeftW = max(300, min(370, siRightX - siLeftX - 60))
    local siRightW = max(300, min(390, siW - siRightX - 34))

    local function SpellIndicatorRuntime()
        local gf = GF()
        return gf and gf.SpellIndicators
    end

    local function EnsureSpellDefaults(kind, specKey)
        local si = SpellIndicatorRuntime()
        if si and type(si.EnsureSpecConfig) == "function" and specKey then
            si.EnsureSpecConfig(SpellIndicators(kind), specKey)
        end
    end

    local function SpellConfigFor(kind, specKey, auraName, create)
        if not (specKey and auraName and auraName ~= "") then return nil end
        local cfg = SpellIndicators(kind)
        cfg.specs = cfg.specs or {}
        if create and not cfg.specs[specKey] then cfg.specs[specKey] = {} end
        local specCfg = cfg.specs[specKey]
        if not specCfg then return nil end
        if create and type(specCfg[auraName]) ~= "table" then
            specCfg[auraName] = { enabled = true, onlyOwn = true }
        end
        return specCfg[auraName]
    end

    local function CurrentAuraInfo(kind)
        local si = SpellIndicatorRuntime()
        local specKey = EffectiveSpellSpec(kind)
        local auraName = CurrentSpellAura(kind)
        local trackable = specKey and si and si.TrackableAuras and si.TrackableAuras[specKey]
        if type(trackable) == "table" then
            for i = 1, #trackable do
                local info = trackable[i]
                if info and info.name == auraName then return info, specKey, auraName end
            end
        end
        return nil, specKey, auraName
    end

    local function CurrentAuraColor(kind)
        local info = CurrentAuraInfo(kind)
        return (info and info.color) or { 1, 1, 1 }
    end

    W.LabelAt(spells, Tr("Spell Set"), siLeftX, -42, siLeftW, "GameFontNormalSmall", T.colors.accent)
    local siEnable = W.ToggleAt(spells, Tr("Enable Spell Indicators"), siLeftX, -72, siLeftW)
    M.BindToggle(ctx, siEnable,
        function() return SpellIndicators(CurrentScope()).enabled == true end,
        function(value)
            SpellIndicators(CurrentScope()).enabled = value and true or false
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            QueueSpellIndicators(CurrentScope())
        end)
    local siLayer = BindNestedSlider(ctx, W.Slider(spells, Tr("Layer"), 1, 15, 1, siRightW), function() return SpellIndicators(CurrentScope()) end, "layer", 9, "visual")
    W.MoveWidget(siLayer, spells, siRightX, -48, siRightW, "LEFT")

    local specDrop = W.Dropdown(spells, Tr("Spec"), SpellSpecValues, siLeftW)
    M.BindDropdown(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[kind] = nil
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            QueueSpellIndicators(kind)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    W.MoveWidget(specDrop, spells, siLeftX, -108, siLeftW, "LEFT")

    local multiSpecDrop = W.Dropdown(spells, Tr("Multi-Spec Entry"), function() return SpellTrackedSpecValues() end, siRightW)
    M.BindDropdown(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[CurrentScope()] = value or ""
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    W.MoveWidget(multiSpecDrop, spells, siRightX, -108, siRightW, "LEFT")

    local multiSpecEnabled = W.ToggleAt(spells, Tr("Track selected multi spec"), siRightX, -168, siRightW)
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

    W.LabelAt(spells, Tr("Tracked Spells"), siLeftX, -166, siLeftW, "GameFontNormalSmall", T.colors.accent)
    local spellTileHint = W.Text(spells, Tr("Left-click configures, right-click toggles, drag to sort."), siLeftX, -187, siLeftW, T.colors.muted)

    local spellTiles = CreateFrame("Frame", nil, spells, "BackdropTemplate")
    spellTiles:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX, -214)
    spellTiles:SetSize(siLeftW, 150)
    spellTiles._tiles = {}

    local TILE_SIZE, TILE_GAP = 52, 6
    local tilesPerRow = max(1, floor((siLeftW + TILE_GAP) / (TILE_SIZE + TILE_GAP)))

    local function TileSlotPos(slot)
        local col = (slot - 1) % tilesPerRow
        local row = floor((slot - 1) / tilesPerRow)
        return col * (TILE_SIZE + TILE_GAP), -(row * (TILE_SIZE + TILE_GAP))
    end

    local function EnsureSortOrder(siCfg, specKey, trackable)
        siCfg.sortOrder = siCfg.sortOrder or {}
        if type(siCfg.sortOrder[specKey]) ~= "table" then
            local order = {}
            for i = 1, #(trackable or {}) do order[#order + 1] = trackable[i].name end
            siCfg.sortOrder[specKey] = order
        end
        return siCfg.sortOrder[specKey]
    end

    local function GetOrderedTrackable(si, siCfg, specKey)
        local trackable = si and si.TrackableAuras and si.TrackableAuras[specKey]
        if type(trackable) ~= "table" then return nil end
        local order = siCfg.sortOrder and siCfg.sortOrder[specKey]
        if type(order) ~= "table" or #order == 0 then return trackable end
        local byName, result = {}, {}
        for i = 1, #trackable do byName[trackable[i].name] = trackable[i] end
        for i = 1, #order do
            local info = byName[order[i]]
            if info then
                result[#result + 1] = info
                byName[order[i]] = nil
            end
        end
        for i = 1, #trackable do
            local info = trackable[i]
            if byName[info.name] then result[#result + 1] = info end
        end
        return result
    end

    local function InsertSpellAt(siCfg, specKey, trackable, auraName, targetSlot)
        local order = EnsureSortOrder(siCfg, specKey, trackable)
        if not order then return end
        local from
        for i = 1, #order do
            if order[i] == auraName then from = i; break end
        end
        if not from then return end
        targetSlot = max(1, min(#order, tonumber(targetSlot) or from))
        if from == targetSlot then return end
        table.remove(order, from)
        if targetSlot > from then targetSlot = targetSlot - 1 end
        table.insert(order, targetSlot, auraName)
    end

    local function RefreshSpellTiles()
        local kind = CurrentScope()
        local si = SpellIndicatorRuntime()
        local specKey = EffectiveSpellSpec(kind)
        if specKey then EnsureSpellDefaults(kind, specKey) end
        local siCfg = SpellIndicators(kind)
        local trackable = specKey and GetOrderedTrackable(si, siCfg, specKey)
        local selected = CurrentSpellAura(kind)

        for i = 1, #spellTiles._tiles do spellTiles._tiles[i]:Hide() end
        if not trackable or #trackable == 0 then
            spellTileHint:SetText(Tr("No spells for current spec."))
            return
        end
        spellTileHint:SetText(Tr("Left-click configures, right-click toggles, drag to sort."))

        for i = 1, #trackable do
            local info = trackable[i]
            local tile = spellTiles._tiles[i]
            if not tile then
                tile = CreateFrame("Frame", nil, spellTiles, "BackdropTemplate")
                tile:SetSize(TILE_SIZE, TILE_SIZE)
                tile:SetMovable(true)
                tile:EnableMouse(true)
                tile:RegisterForDrag("LeftButton")
                tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
                tile:SetBackdropColor(0.035, 0.040, 0.070, 0.96)

                tile.icon = tile:CreateTexture(nil, "ARTWORK")
                tile.icon:SetSize(36, 36)
                tile.icon:SetPoint("TOP", tile, "TOP", 0, -3)
                tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                tile.label = tile:CreateFontString(nil, "OVERLAY")
                tile.label:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
                tile.label:SetPoint("BOTTOM", tile, "BOTTOM", 0, 2)
                tile.label:SetWidth(TILE_SIZE - 4)
                tile.label:SetMaxLines(1)
                tile.label:SetJustifyH("CENTER")
                spellTiles._tiles[i] = tile
            end

            local x, y = TileSlotPos(i)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", spellTiles, "TOPLEFT", x, y)
            tile._slot = i
            tile._auraName = info.name
            tile._specKey = specKey
            tile._trackable = trackable
            tile._dragged = false

            local auraCfg = SpellConfigFor(kind, specKey, info.name, false)
            local disabled = auraCfg and auraCfg.enabled == false
            local selectedTile = info.name == selected
            local c = info.color or { 0.55, 0.65, 0.85 }

            if si and type(si.GetAuraIcon) == "function" then
                tile.icon:SetTexture(si.GetAuraIcon(specKey, info.name))
            else
                tile.icon:SetTexture(136243)
            end
            tile.icon:SetDesaturated(disabled)
            tile.icon:SetAlpha(disabled and 0.35 or 1)
            tile.label:SetText(info.display or info.name)
            tile.label:SetTextColor(disabled and 0.45 or 0.92, disabled and 0.45 or 0.92, disabled and 0.45 or 0.92, 1)
            tile:SetBackdropBorderColor(
                selectedTile and 0.38 or (c[1] * 0.62),
                selectedTile and 0.66 or (c[2] * 0.62),
                selectedTile and 1.00 or (c[3] * 0.62),
                selectedTile and 1.00 or 0.82
            )

            tile:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(info.display or info.name, 1, 1, 1)
                if info.secret then GameTooltip:AddLine(Tr("Secret aura (name/fingerprint matched)"), 0.72, 0.62, 0.95) end
                GameTooltip:AddLine(Tr("Left-click to configure"), 0.75, 0.78, 0.86)
                GameTooltip:AddLine(Tr("Right-click to toggle"), 0.55, 0.82, 0.55)
                GameTooltip:AddLine(Tr("Drag to reorder"), 0.55, 0.70, 0.95)
                GameTooltip:Show()
                self:SetBackdropColor(0.070, 0.085, 0.125, 1)
                self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            end)
            tile:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
                local isSelected = self._auraName == CurrentSpellAura(CurrentScope())
                self:SetBackdropBorderColor(
                    isSelected and 0.38 or (c[1] * 0.62),
                    isSelected and 0.66 or (c[2] * 0.62),
                    isSelected and 1.00 or (c[3] * 0.62),
                    isSelected and 1.00 or 0.82
                )
            end)
            tile:SetScript("OnDragStart", function(self)
                GameTooltip:Hide()
                self._dragged = true
                self:StartMoving()
                self:SetFrameStrata("TOOLTIP")
            end)
            tile:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self:SetFrameStrata(spellTiles:GetFrameStrata())
                local hostLeft, hostTop = spellTiles:GetLeft(), spellTiles:GetTop()
                local cx, cy = self:GetCenter()
                if not (hostLeft and hostTop and cx and cy) then return end
                local bestSlot, bestDist = self._slot or 1, math.huge
                for slot = 1, #(self._trackable or {}) do
                    local sx, sy = TileSlotPos(slot)
                    local tx = hostLeft + sx + TILE_SIZE / 2
                    local ty = hostTop + sy - TILE_SIZE / 2
                    local dx, dy = cx - tx, cy - ty
                    local dist = dx * dx + dy * dy
                    if dist < bestDist then
                        bestSlot, bestDist = slot, dist
                    end
                end
                local currentKind = CurrentScope()
                local function ReorderSpellIndicator()
                    InsertSpellAt(SpellIndicators(currentKind), self._specKey, self._trackable, self._auraName, bestSlot)
                    QueueSpellIndicators(currentKind)
                end
                if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                    M.CaptureHistory("Spell Indicator Order", "group:spellOrder:" .. tostring(currentKind) .. ":" .. tostring(self._specKey), ReorderSpellIndicator)
                else
                    ReorderSpellIndicator()
                end
                if M.SelectPage then M.SelectPage(ctx.key) end
            end)
            tile:SetScript("OnMouseUp", function(self, button)
                if self._dragged then
                    self._dragged = false
                    return
                end
                local currentKind = CurrentScope()
                if button == "RightButton" then
                    local function ToggleSpellIndicator()
                        local cfg = SpellConfigFor(currentKind, self._specKey, self._auraName, true)
                        if cfg then cfg.enabled = cfg.enabled == false and true or false end
                        QueueSpellIndicators(currentKind)
                    end
                    if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                        M.CaptureHistory("Toggle Spell Indicator", "group:spellToggle:" .. tostring(currentKind) .. ":" .. tostring(self._specKey) .. ":" .. tostring(self._auraName), ToggleSpellIndicator)
                    else
                        ToggleSpellIndicator()
                    end
                else
                    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
                    M.gfSpellIndicatorSelection[currentKind] = self._auraName
                    if RefreshGFPreview then RefreshGFPreview() end
                end
                if M.SelectPage then M.SelectPage(ctx.key) end
            end)
            tile:Show()
        end
    end

    W.LabelAt(spells, Tr("Selected Spell"), siRightX, -204, siRightW, "GameFontNormalSmall", T.colors.accent)
    local auraDrop = W.Dropdown(spells, Tr("Spell"), function() return SpellAuraValues(CurrentScope()) end, siRightW)
    M.BindDropdown(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[CurrentScope()] = value
            if RefreshGFPreview then RefreshGFPreview() end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    W.MoveWidget(auraDrop, spells, siRightX, -228, siRightW, "LEFT")

    local spellEnabled = W.ToggleAt(spells, Tr("Enabled"), siRightX, -288, siRightW)
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

    local onlyMine = W.ToggleAt(spells, Tr("Only my cast"), siRightX, -320, siRightW)
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

    W.LabelAt(spells, Tr("Placed Indicator"), siLeftX, -386, siLeftW, "GameFontNormalSmall", T.colors.accent)
    local placedType = W.Dropdown(spells, Tr("Indicator Type"), PLACED_INDICATOR_TYPES, siLeftW)
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
    W.MoveWidget(placedType, spells, siLeftX, -410, siLeftW, "LEFT")

    local placedAnchor = W.Dropdown(spells, Tr("Anchor"), STATUS_ICON_ANCHORS, siLeftW)
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
    W.MoveWidget(placedAnchor, spells, siLeftX, -464, siLeftW, "LEFT")

    local placedSize = W.Slider(spells, Tr("Size"), 6, 48, 1, siLeftW)
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
    W.MoveWidget(placedSize, spells, siLeftX, -518, siLeftW, "LEFT")

    local placedX = W.Slider(spells, Tr("X Offset"), -100, 100, 1, siLeftW)
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
    W.MoveWidget(placedX, spells, siLeftX, -572, siLeftW, "LEFT")

    local placedY = W.Slider(spells, Tr("Y Offset"), -100, 100, 1, siLeftW)
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
    W.MoveWidget(placedY, spells, siLeftX, -626, siLeftW, "LEFT")

    local placedBarWidth = W.Slider(spells, Tr("Bar Width"), 8, 120, 1, siLeftW)
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
    W.MoveWidget(placedBarWidth, spells, siLeftX, -680, siLeftW, "LEFT")

    local placedGrowth = W.Dropdown(spells, Tr("Growth"), SPELL_GROWTH_VALUES, siLeftW)
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
    W.MoveWidget(placedGrowth, spells, siLeftX, -734, siLeftW, "LEFT")

    W.LabelAt(spells, Tr("Frame Effect"), siRightX, -366, siRightW, "GameFontNormalSmall", T.colors.accent)
    local frameType = W.Dropdown(spells, Tr("Frame Effect"), FRAME_EFFECT_TYPES, siRightW)
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
                if not cfg.frame.color then
                    local c = CurrentAuraColor(CurrentScope())
                    cfg.frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
                end
                cfg.frame.priority = cfg.frame.priority or 5
            end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(frameType, spells, siRightX, -390, siRightW, "LEFT")

    local frameColor = W.Color(spells, Tr("Color"))
    M.BindColor(ctx, frameColor,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            local c = frame and frame.color
            if c then return c[1] or 1, c[2] or 1, c[3] or 1 end
            c = CurrentAuraColor(CurrentScope())
            return c[1] or 1, c[2] or 1, c[3] or 1
        end,
        function(r, g, bcol)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then
                local a = (frame.color and frame.color[4]) or frame.alpha or 0.8
                frame.color = { r, g, bcol, a }
            end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(frameColor, spells, siRightX, -446, siRightW)

    local framePriority = W.Slider(spells, Tr("Priority"), 1, 10, 1, siRightW)
    M.BindSlider(ctx, framePriority,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return tonumber(frame and frame.priority) or 5
        end,
        function(value)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then frame.priority = floor((tonumber(value) or 5) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(framePriority, spells, siRightX, -500, siRightW, "LEFT")

    local frameAlpha = W.Slider(spells, Tr("Tint Alpha"), 5, 100, 5, siRightW)
    M.BindSlider(ctx, frameAlpha,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return floor(((frame and (frame.alpha or (frame.color and frame.color[4])) or 0.25) * 100) + 0.5)
        end,
        function(value)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then
                local alpha = (tonumber(value) or 25) / 100
                frame.alpha = alpha
                if frame.color then frame.color[4] = alpha end
            end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(frameAlpha, spells, siRightX, -554, siRightW, "LEFT")

    local frameThickness = W.Slider(spells, Tr("Border / Glow Thickness"), 1, 8, 1, siRightW)
    M.BindSlider(ctx, frameThickness,
        function()
            local frame = FrameEffectConfig(CurrentScope(), false)
            return tonumber(frame and frame.thickness) or 2
        end,
        function(value)
            local frame = FrameEffectConfig(CurrentScope(), true)
            if frame then frame.thickness = floor((tonumber(value) or 2) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(frameThickness, spells, siRightX, -608, siRightW, "LEFT")

    W.LabelAt(spells, Tr("Utilities"), siRightX, -660, siRightW, "GameFontNormalSmall", T.colors.accent)
    local placedMissing = W.ToggleAt(spells, Tr("Show when missing"), siRightX, -690, siRightW)
    M.BindToggle(ctx, placedMissing,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.missing == true or false
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.missing = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedCooldown = W.ToggleAt(spells, Tr("Show Cooldown Text"), siRightX, -722, siRightW)
    M.BindToggle(ctx, placedCooldown,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.showCooldown ~= false or false
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.showCooldown = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedCooldownSize = W.Slider(spells, Tr("Cooldown Text Size"), 6, 24, 1, siRightW)
    M.BindSlider(ctx, placedCooldownSize,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return tonumber(placed and placed.cooldownSize) or 8
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.cooldownSize = floor((tonumber(value) or 8) + 0.5) end
            QueueSpellIndicators(CurrentScope())
        end)
    W.MoveWidget(placedCooldownSize, spells, siRightX, -754, siRightW, "LEFT")

    local function RefreshSpellIndicatorState()
        EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
        RefreshSpellTiles()
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
        local hasSpell = EffectiveSpellSpec(CurrentScope()) ~= nil and CurrentSpellAura(CurrentScope()) ~= ""
        local frame = FrameEffectConfig(CurrentScope(), false)
        local frameKind = frame and frame.type or "none"
        local hasFrame = hasSpell and frameKind ~= "none"
        local cdRelevant = placedEnabled and placed.type ~= "bar" and placed.type ~= "number"
        local barRelevant = placedEnabled and placed.type == "bar"
        SetOptionEnabled(spellEnabled, hasSpell)
        SetOptionEnabled(onlyMine, hasSpell)
        SetOptionEnabled(placedType, hasSpell)
        SetOptionEnabled(frameType, hasSpell)
        SetOptionEnabled(placedAnchor, placedEnabled)
        SetOptionEnabled(placedSize, placedEnabled)
        SetOptionEnabled(placedX, placedEnabled)
        SetOptionEnabled(placedY, placedEnabled)
        SetOptionEnabled(placedBarWidth, barRelevant)
        SetOptionEnabled(placedGrowth, placedEnabled)
        SetOptionEnabled(placedMissing, placedEnabled)
        SetOptionEnabled(placedCooldown, cdRelevant)
        SetOptionEnabled(placedCooldownSize, cdRelevant and placed and placed.showCooldown ~= false)
        SetOptionEnabled(frameColor, hasFrame)
        SetOptionEnabled(framePriority, hasFrame)
        SetOptionEnabled(frameAlpha, hasFrame and (frameKind == "healthtint" or frameKind == "pulse"))
        SetOptionEnabled(frameThickness, hasFrame and (frameKind == "border" or frameKind == "glow"))
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(spells, nil) end
    end
    M.AddRefresher(ctx, RefreshSpellIndicatorState)
    RefreshSpellIndicatorState()
    do
        local entry = spells and spells._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshSpellIndicatorState end
    end

    local corners = b:CollapsibleSection("ci", "Corner Indicators", 620, false)
    local cornerW = corners._msuf2Width or ctx.width or 720
    local leftX = 30
    local rightX = max(430, min(560, floor(cornerW * 0.52)))
    local leftW = max(300, min(360, rightX - leftX - 56))
    local rightW = max(330, min(440, cornerW - rightX - 42))

    W.LabelAt(corners, "Global", leftX, -42, leftW, "GameFontNormalSmall", T.colors.accent)
    local ciEnable = BindScopeToggle(ctx, W.ToggleAt(corners, "Enable corner indicators", leftX, -72, leftW), "ciEnabled", true, "visual")
    local ciSize = BindScopeSlider(ctx, W.Slider(corners, "Icon Size", 4, 24, 1, leftW), "ciSize", 8, "visual")
    local ciAlpha = W.Slider(corners, "Alpha", 10, 100, 5, leftW)
    M.BindSlider(ctx, ciAlpha,
        function() return floor((Num(CurrentScope(), "ciAlpha", 1) * 100) + 0.5) end,
        function(value) Set(CurrentScope(), "ciAlpha", (tonumber(value) or 100) / 100, "visual") end)
    W.MoveWidget(ciSize, corners, leftX, -116, leftW, "LEFT")
    W.MoveWidget(ciAlpha, corners, leftX, -170, leftW, "LEFT")

    W.LabelAt(corners, "Slot Assignments", leftX, -228, leftW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Assign what each corner dot should show. Choosing Custom Spell enables that slot's editor on the right.", leftX, -250, leftW, T.colors.muted)

    local slotControls = {}
    local slotPositions = {
        TL = { x = leftX, y = -304 },
        TR = { x = leftX + floor(leftW / 2) + 10, y = -304 },
        BL = { x = leftX, y = -386 },
        BR = { x = leftX + floor(leftW / 2) + 10, y = -386 },
        C = { x = leftX + floor(leftW / 4) + 4, y = -468 },
    }
    local slotW = floor((leftW - 12) / 2)

    for i = 1, #CI_SLOT_VALUES do
        local slotInfo = CI_SLOT_VALUES[i]
        local slotKey = slotInfo.value
        local p = slotPositions[slotKey] or { x = leftX, y = -304 - (i - 1) * 58 }
        local w = slotKey == "C" and slotW or slotW
        local slotDrop = W.Dropdown(corners, (slotInfo.text or slotKey) .. " Indicator", CICategoryValues, w)
        M.BindDropdown(ctx, slotDrop,
            function()
                return Val(CurrentScope(), "ciSlot" .. slotKey, CI_SLOT_DEFAULTS[slotKey] or "none")
            end,
            function(value)
                M.gfCornerSlotSelection = slotKey
                Set(CurrentScope(), "ciSlot" .. slotKey, value or "none", "visual")
                if M.SelectPage then M.SelectPage(ctx.key) end
            end)
        W.MoveWidget(slotDrop, corners, p.x, p.y, w, "LEFT")
        slotControls[#slotControls + 1] = slotDrop
    end

    W.LabelAt(corners, "Custom Spell Editor", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Pick a slot, set it to Custom Spell, then enter spell IDs. This edits one slot at a time and keeps the five slot assignments visible.", rightX, -64, rightW, T.colors.muted)

    local slotDrop = W.Dropdown(corners, "Editor Slot", CI_SLOT_VALUES, rightW)
    M.BindDropdown(ctx, slotDrop,
        function() return CurrentCISlot() end,
        function(value)
            M.gfCornerSlotSelection = value or "TL"
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)
    W.MoveWidget(slotDrop, corners, rightX, -122, rightW, "LEFT")

    local categoryDrop = W.Dropdown(corners, "Selected Slot Indicator", CICategoryValues, rightW)
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
    W.MoveWidget(categoryDrop, corners, rightX, -176, rightW, "LEFT")

    local customStatus = W.Text(corners, "", rightX, -230, rightW, T.colors.muted)
    if customStatus.SetWordWrap then customStatus:SetWordWrap(true) end

    local customSpells = W.TextInput(corners, "Spell IDs (comma-separated)", rightW)
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
    W.MoveWidget(customSpells, corners, rightX, -286, rightW)

    local customMode = W.Dropdown(corners, "When", CIModeValues, rightW)
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
    W.MoveWidget(customMode, corners, rightX, -350, rightW, "LEFT")

    local customFilter = W.Dropdown(corners, "Filter", CIFilterValues, rightW)
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
    W.MoveWidget(customFilter, corners, rightX, -404, rightW, "LEFT")

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
    W.MoveWidget(customColor, corners, rightX, -458, rightW)

    local customHelp = W.Text(corners, "Tip: HELPFUL|PLAYER and HARMFUL|PLAYER are the safest filters because WoW exposes your own spell IDs reliably.", rightX, -506, rightW, T.colors.dim)
    if customHelp.SetWordWrap then customHelp:SetWordWrap(true) end

    local function RefreshCornerIndicatorState()
        local slot = CurrentCISlot()
        local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        local showCustom = category == "custom"
        local enabled = Bool(CurrentScope(), "ciEnabled", true)
        SetOptionEnabled(ciEnable, true)
        SetOptionsEnabled({ ciSize, ciAlpha }, enabled)
        SetOptionsEnabled(slotControls, enabled)
        SetOptionsEnabled({ slotDrop, categoryDrop }, enabled)
        SetOptionsEnabled({ customSpells, customMode, customFilter, customColor }, enabled and showCustom)
        local slotLabel = slot
        for i = 1, #CI_SLOT_VALUES do
            if CI_SLOT_VALUES[i].value == slot then
                slotLabel = CI_SLOT_VALUES[i].text or slot
                break
            end
        end
        if showCustom then
            customStatus:SetText(M.Format("%s is using Custom Spell. These settings are active.", slotLabel))
            customStatus:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 0.95)
        else
            customStatus:SetText(M.Format("%s is set to %s. Set Selected Slot Indicator to Custom Spell to activate this editor.", slotLabel, tostring(category or "none")))
            customStatus:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(corners, nil) end
    end
    M.AddRefresher(ctx, RefreshCornerIndicatorState)
    RefreshCornerIndicatorState()
    do
        local entry = corners and corners._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshCornerIndicatorState end
    end

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_indicators", { title = "MSUF Group Indicators", build = BuildGFIndicators, version = 11 })
