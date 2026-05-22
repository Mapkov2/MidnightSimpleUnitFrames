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
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture

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

local function IconPackValues()
    local gf = GF()
    if gf and type(gf.GetIconStyleItems) == "function" then
        return gf.GetIconStyleItems(true)
    end
    local values = { { value = "DEFAULT", text = "Follow global style" } }
    local src = type(IconStyleValues) == "function" and IconStyleValues() or {}
    for i = 1, #src do
        local item = src[i]
        if type(item) == "table" then
            values[#values + 1] = {
                value = item.value or item.key,
                text = item.text or item.label or item.value or item.key,
            }
        end
    end
    return values
end

local STATUS_ICON_TAB_VALUES = {
    { value = "basic", text = "Basic" },
    { value = "advanced", text = "Advanced" },
}

local function HeaderHintColor()
    return { 0.45, 0.52, 0.65, 1 }
end
local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local indicators = b:CollapsibleSection("indicators", "Indicators", 650, true)
    local indicatorsW = indicators._msuf2Width or ctx.width or 720
    local cardGap = 16
    local leftX = 20
    local innerW = max(320, indicatorsW - 40)
    local leftW = floor((innerW - cardGap) * 0.48)
    local rightX = leftX + leftW + cardGap
    local rightW = innerW - leftW - cardGap

    local function IsMouseoverHighlightEnabled()
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        return not (gen and gen.highlightEnabled == false)
    end

    local highlightCard = W.ControlCard(indicators, "Aggro / Dispel / Target Highlight", nil, leftX, -38, innerW, 92)
    local hlHint = W.Text(highlightCard, "Controlled from: |cff38c7f0Global Style > Bars|r > |cff38c7f0Outline & Highlight Border|r\nEnable/disable, colors, size, offset, priority - all in one place.", 16, -42, innerW - 32, T.colors.muted)
    if hlHint.SetWordWrap then hlHint:SetWordWrap(true) end

    local groupNumberCard = W.ControlCard(indicators, "Group Number", "Small group index label on each frame.", leftX, -148, leftW, 246)
    local groupNumberToggle = BindScopeToggle(ctx, W.SwitchAt(groupNumberCard, "Group Number", leftW - 62, -24, 0, "HIDDEN"), "showGroupNumber", false, "visual")
    groupNumberToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupNumberSize = BindScopeSlider(ctx, W.Slider(groupNumberCard, "Size", 6, 24, 1, leftW), "groupNumberSize", 10, "font")
    local groupNumberAnchor = BindScopeDropdown(ctx, W.Dropdown(groupNumberCard, "Anchor", AURA_ANCHORS, leftW), "groupNumberAnchor", "BOTTOMRIGHT", "geometry")
    local groupNumberX = BindScopeSlider(ctx, W.Slider(groupNumberCard, "X Offset", -100, 100, 1, leftW), "groupNumberX", -2, "geometry")
    local groupNumberY = BindScopeSlider(ctx, W.Slider(groupNumberCard, "Y Offset", -100, 100, 1, leftW), "groupNumberY", 2, "geometry")
    W.MoveWidget(groupNumberSize, groupNumberCard, 16, -66, leftW - 58, "CENTER")
    W.MoveWidget(groupNumberAnchor, groupNumberCard, 16, -116, leftW - 32, "LEFT")
    W.MoveWidget(groupNumberX, groupNumberCard, 16, -166, leftW - 58, "CENTER")
    W.MoveWidget(groupNumberY, groupNumberCard, 16, -216, leftW - 58, "CENTER")

    local hoverCard = W.ControlCard(indicators, "Hover Highlight", "Enable + color: |cff38c7f0Global Style > Colors|r > Mouseover Highlight", rightX, -148, rightW, 126)
    local hoverHint = hoverCard and hoverCard.subtitle
    local hoverSize = W.Slider(hoverCard, "Border Thickness", 1, 6, 1, rightW)
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
    W.MoveWidget(hoverSize, hoverCard, 16, -70, rightW - 58, "CENTER")

    local focusCard = W.ControlCard(indicators, "Focus Highlight", "Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus.", rightX, -294, rightW, 190)
    local focusToggle = BindScopeToggle(ctx, W.SwitchAt(focusCard, "Focus Highlight", rightW - 62, -24, 0, "HIDDEN"), "hlFocusEnabled", true, "visual")
    focusToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local focusHint = focusCard and focusCard.subtitle
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusSize = BindScopeSlider(ctx, W.Slider(focusCard, "Border Thickness", 1, 6, 1, rightW), "hlFocusSize", 2, "visual")
    local focusColor = W.Color(focusCard, "Focus Glow Color")
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
    W.MoveWidget(focusSize, focusCard, 16, -88, rightW - 58, "CENTER")
    W.MoveWidget(focusColor, focusCard, 16, -142, rightW - 32)

    local groupBorderCard = W.ControlCard(indicators, "Group Border", "Optional border around the full group frame.", leftX, -412, leftW, 202)
    local groupBorderToggle = BindScopeToggle(ctx, W.SwitchAt(groupBorderCard, "Group Border", leftW - 62, -24, 0, "HIDDEN"), "groupBorderEnabled", false, "visual")
    groupBorderToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupBorderSize = BindScopeSlider(ctx, W.Slider(groupBorderCard, "Border Thickness", 1, 12, 1, leftW), "groupBorderSize", 1, "visual")
    local groupBorderPadding = BindScopeSlider(ctx, W.Slider(groupBorderCard, "Padding", 0, 40, 1, leftW), "groupBorderPadding", 2, "visual")
    local groupBorderColor = W.Color(groupBorderCard, "Group Border Color")
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
    W.MoveWidget(groupBorderSize, groupBorderCard, 16, -66, leftW - 58, "CENTER")
    W.MoveWidget(groupBorderPadding, groupBorderCard, 16, -116, leftW - 58, "CENTER")
    W.MoveWidget(groupBorderColor, groupBorderCard, 16, -168, leftW - 32)

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

    local sicons = b:CollapsibleSection("sicons", "Status Icons", 624, false)
    local siconW = sicons._msuf2Width or ctx.width or 720
    local siconGap = 16
    local siconLeftX = 20
    local siconInnerW = max(320, siconW - 40)
    local siconLeftW = floor((siconInnerW - siconGap) * 0.46)
    local siconRightX = siconLeftX + siconLeftW + siconGap
    local siconRightW = siconInnerW - siconLeftW - siconGap
    local siconTabW = min(420, siconInnerW)
    local siconTabs = W.Segment(sicons, "Status icon controls", STATUS_ICON_TAB_VALUES, siconTabW)
    W.MoveWidget(siconTabs, sicons, siconLeftX, -50, siconTabW, "LEFT")

    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    local function CurrentStatusIconTab()
        local key = M.gfStatusIconTabSelection[CurrentScope()] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local RefreshStatusIconTabs
    M.BindSegment(ctx, siconTabs,
        CurrentStatusIconTab,
        function(value)
            M.gfStatusIconTabSelection[CurrentScope()] = value or "basic"
            if RefreshStatusIconTabs then RefreshStatusIconTabs() end
        end)

    local siconBasicTab = CreateFrame("Frame", nil, sicons)
    siconBasicTab:SetPoint("TOPLEFT", sicons, "TOPLEFT", 0, -104)
    siconBasicTab:SetPoint("BOTTOMRIGHT", sicons, "BOTTOMRIGHT", 0, 12)
    siconBasicTab._msuf2Width = siconW

    local siconAdvancedTab = CreateFrame("Frame", nil, sicons)
    siconAdvancedTab:SetPoint("TOPLEFT", sicons, "TOPLEFT", 0, -104)
    siconAdvancedTab:SetPoint("BOTTOMRIGHT", sicons, "BOTTOMRIGHT", 0, 12)
    siconAdvancedTab._msuf2Width = siconW

    local styleCard = W.ControlCard(siconBasicTab, "Style", nil, siconLeftX, -38, siconLeftW, 132)
    local selectedCard = W.ControlCard(siconBasicTab, "Selected Indicator", nil, siconLeftX, -188, siconLeftW, 258)
    local previewCard = W.ControlCard(siconBasicTab, "Status Preview", nil, siconRightX, -38, siconRightW, 118)
    local placementCard = W.ControlCard(siconBasicTab, "Placement", nil, siconRightX, -174, siconRightW, 322)

    local iconStyle = BindScopeDropdown(ctx, W.Dropdown(styleCard, "Icon style", IconStyleValues, siconLeftW), "iconStyle", "BLIZZARD", "visual")
    W.MoveWidget(iconStyle, styleCard, 16, -56, siconLeftW - 32, "LEFT")
    local midnightStyle = BindScopeToggle(ctx, W.ToggleAt(styleCard, "Use Midnight Style", 16, -106, siconLeftW - 32), "useMidnightIcons", false, "visual")

    local statusSelector = W.Dropdown(selectedCard, "Indicator", GF_STATUS_ICON_VALUES, siconLeftW)
    M.BindDropdown(ctx, statusSelector,
        function() return CurrentGFStatusSpec().value end,
        function(value)
            for i = 1, #GF_STATUS_ICON_SPECS do
                if GF_STATUS_ICON_SPECS[i].value == value then
                    if type(M.PersistMenuStateValue) == "function" then
                        M.PersistMenuStateValue("gfStatusIconSelection", value)
                    else
                        M.gfStatusIconSelection = value
                    end
                    local gf = GF()
                    if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(value) end
                    if M.SelectPage then M.SelectPage(ctx.key) end
                    return
                end
            end
        end)
    W.MoveWidget(statusSelector, selectedCard, 16, -54, siconLeftW - 32, "LEFT")

    local statusEnabled = W.SwitchAt(selectedCard, "Enabled", siconLeftW - 62, -24, 0, "HIDDEN")
    statusEnabled._msuf2GroupFrameGateAlwaysEnabled = true
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

    local iconPack = W.Dropdown(selectedCard, "Icon pack", IconPackValues, siconLeftW)
    M.BindDropdown(ctx, iconPack,
        function()
            local spec = CurrentGFStatusSpec()
            return spec and spec.iconStyle and Val(CurrentScope(), spec.iconStyle, "DEFAULT") or "DEFAULT"
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            if not (spec and spec.iconStyle) then return end
            Set(CurrentScope(), spec.iconStyle, value or "DEFAULT", "visual")
            if RefreshGFPreview then RefreshGFPreview() end
        end)
    W.MoveWidget(iconPack, selectedCard, 16, -106, siconLeftW - 32, "LEFT")

    -- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = CreateFrame("Frame", nil, selectedCard)
    roleFilterGroup:SetPoint("TOPLEFT", selectedCard, "TOPLEFT", 0, -164)
    local roleFilterW = max(180, siconLeftW - 32)
    roleFilterGroup:SetSize(roleFilterW, 60)

    W.LabelAt(roleFilterGroup, "Show for:", 16, -8, siconLeftW - 32, "GameFontNormalSmall", T.colors.accent)

    local rfColW   = floor(roleFilterW / 3)
    local rfLabelW = max(34, rfColW - 30)  -- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local rfTank   = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Tank",   16,              -26, rfLabelW), "roleIconShowTank",   true, "visual")
    local rfHealer = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Healer", 16 + rfColW,     -26, rfLabelW), "roleIconShowHealer", true, "visual")
    local rfDPS    = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "DPS",    16 + rfColW * 2, -26, rfLabelW), "roleIconShowDPS",    true, "visual")

    local previewCurrent = W.Button(previewCard, "Preview current", 142)
    previewCurrent:SetScript("OnClick", function()
        local gf = GF()
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("gfStatusPreviewMode", "current")
        else
            M.gfStatusPreviewMode = "current"
        end
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("current") end
        if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        if RefreshGFPreview then RefreshGFPreview() end
    end)
    previewCurrent:ClearAllPoints()
    previewCurrent:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -54)
    previewCurrent:SetSize(142, 24)

    local previewAll = W.Button(previewCard, "Show all", 112)
    previewAll:SetScript("OnClick", function()
        local gf = GF()
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("gfStatusPreviewMode", "all")
        else
            M.gfStatusPreviewMode = "all"
        end
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode("all") end
        if RefreshGFPreview then RefreshGFPreview() end
    end)
    previewAll:ClearAllPoints()
    previewAll:SetPoint("LEFT", previewCurrent, "RIGHT", 10, 0)
    previewAll:SetSize(112, 24)

    local statusReset = W.Button(previewCard, "Reset selected", 160)
    statusReset:SetScript("OnClick", function()
        local kind = CurrentScope()
        local spec = CurrentGFStatusSpec()
        local conf = Conf(kind)
        local gf = GF()
        for _, key in ipairs({ spec.size, spec.anchor, spec.x, spec.y, spec.layer, spec.iconStyle }) do
            if key then
                conf[key] = gf and gf.GetDefault and gf.GetDefault(kind, key) or nil
            end
        end
        QueueGF(kind, "visual")
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)
    statusReset:ClearAllPoints()
    statusReset:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -86)
    statusReset:SetSize(160, 24)

    local statusSize = W.Slider(placementCard, "Size", 6, 40, 1, siconRightW)
    M.BindSlider(ctx, statusSize,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.size, spec.defaultSize)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.size, floor((tonumber(value) or spec.defaultSize) + 0.5), "visual")
        end)
    W.MoveWidget(statusSize, placementCard, 16, -58, siconRightW - 58, "LEFT")

    local statusAnchor = W.Dropdown(placementCard, "Anchor", STATUS_ICON_ANCHORS, siconRightW)
    M.BindDropdown(ctx, statusAnchor,
        function()
            local spec = CurrentGFStatusSpec()
            return Val(CurrentScope(), spec.anchor, spec.defaultAnchor)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.anchor, value or spec.defaultAnchor, "geometry")
        end)
    W.MoveWidget(statusAnchor, placementCard, 16, -108, siconRightW - 32, "LEFT")

    local statusX = W.Slider(placementCard, "X Offset", -100, 100, 1, siconRightW)
    M.BindSlider(ctx, statusX,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.x, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.x, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(statusX, placementCard, 16, -158, siconRightW - 58, "LEFT")

    local statusY = W.Slider(placementCard, "Y Offset", -100, 100, 1, siconRightW)
    M.BindSlider(ctx, statusY,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.y, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.y, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(statusY, placementCard, 16, -208, siconRightW - 58, "LEFT")

    local statusLayer = W.Slider(placementCard, "Layer", 0, 30, 1, siconRightW)
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
    W.MoveWidget(statusLayer, placementCard, 16, -258, siconRightW - 58, "LEFT")

    local advanced = {}
    advanced.card = W.ControlCard(siconAdvancedTab, "Advanced Placement", nil, siconLeftX, -38, siconInnerW, 316)
    advanced.x = W.Slider(advanced.card, "X Offset (extended)", -500, 500, 1, siconLeftW)
    M.BindSlider(ctx, advanced.x,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.x, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.x, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(advanced.x, advanced.card, 16, -58, siconLeftW - 58, "LEFT")

    advanced.y = W.Slider(advanced.card, "Y Offset (extended)", -500, 500, 1, siconRightW)
    M.BindSlider(ctx, advanced.y,
        function()
            local spec = CurrentGFStatusSpec()
            return Num(CurrentScope(), spec.y, 0)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.y, floor((tonumber(value) or 0) + 0.5), "geometry")
        end)
    W.MoveWidget(advanced.y, advanced.card, siconRightX - siconLeftX, -58, siconRightW - 58, "LEFT")

    advanced.layer = W.Slider(advanced.card, "Layer", 0, 30, 1, siconLeftW)
    M.BindSlider(ctx, advanced.layer,
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
    W.MoveWidget(advanced.layer, advanced.card, 16, -128, siconLeftW - 58, "LEFT")

    advanced.reset = W.Button(advanced.card, "Reset selected", 160)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if statusReset and statusReset.Click then statusReset:Click() end
    end)
    advanced.reset:ClearAllPoints()
    advanced.reset:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", siconRightX - siconLeftX, -150)
    advanced.reset:SetSize(160, 24)

    advanced.previewCurrent = W.Button(advanced.card, "Preview current", 142)
    advanced.previewCurrent:SetScript("OnClick", function()
        if previewCurrent and previewCurrent.Click then previewCurrent:Click() end
    end)
    advanced.previewCurrent:ClearAllPoints()
    advanced.previewCurrent:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", 16, -234)
    advanced.previewCurrent:SetSize(142, 24)

    advanced.previewAll = W.Button(advanced.card, "Show all", 112)
    advanced.previewAll:SetScript("OnClick", function()
        if previewAll and previewAll.Click then previewAll:Click() end
    end)
    advanced.previewAll:ClearAllPoints()
    advanced.previewAll:SetPoint("LEFT", advanced.previewCurrent, "RIGHT", 10, 0)
    advanced.previewAll:SetSize(112, 24)

    RefreshStatusIconTabs = function()
        local tab = CurrentStatusIconTab()
        siconBasicTab:SetShown(tab ~= "advanced")
        siconAdvancedTab:SetShown(tab == "advanced")
    end
    M.AddRefresher(ctx, RefreshStatusIconTabs)

    local function RefreshStatusIconState()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, true)
        SetOptionEnabled(statusSize, enabled)
        SetOptionEnabled(statusAnchor, enabled)
        SetOptionEnabled(statusX, enabled)
        SetOptionEnabled(statusY, enabled)
        SetOptionEnabled(statusLayer, enabled)
        SetOptionEnabled(advanced.x, enabled)
        SetOptionEnabled(advanced.y, enabled)
        SetOptionEnabled(advanced.layer, enabled)
        SetOptionEnabled(advanced.reset, spec ~= nil)
        SetOptionEnabled(advanced.previewCurrent, spec ~= nil)
        SetOptionEnabled(advanced.previewAll, true)
        SetOptionEnabled(statusReset, spec ~= nil)
        SetOptionEnabled(previewCurrent, spec ~= nil)
        SetOptionEnabled(previewAll, true)
        SetOptionEnabled(midnightStyle, true)
        SetOptionEnabled(statusEnabled, true)
        local hasIconPack = spec and spec.iconStyle
        if W.SetControlShown then
            W.SetControlShown(iconPack, hasIconPack and true or false)
        else
            iconPack:SetShown(hasIconPack and true or false)
            if iconPack._msuf2Title then iconPack._msuf2Title:SetShown(hasIconPack and true or false) end
        end
        SetOptionEnabled(iconPack, hasIconPack and enabled)
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
    RefreshStatusIconTabs()
    do
        local entry = sicons and sicons._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshStatusIconState end
    end

    local spells = b:CollapsibleSection("si", Tr("Spell Indicators"), 864, false)
    local siW = spells._msuf2Width or ctx.width or 720
    local siGap = 28
    local siLeftX = 30
    local siInnerW = max(320, siW - 60)
    local siLeftW = max(240, min(370, floor((siInnerW - siGap) * 0.46)))
    local siRightX = siLeftX + siLeftW + siGap
    local siRightW = max(240, min(390, siInnerW - siLeftW - siGap))
    do
        W.ControlCard(spells, Tr("Spell Set"), nil, siLeftX - 14, -38, siLeftW + 28, 334)
        W.ControlCard(spells, Tr("Selected Spell"), nil, siRightX - 14, -38, siRightW + 28, 304)
        W.ControlCard(spells, Tr("Placed Indicator"), nil, siLeftX - 14, -374, siLeftW + 28, 408)
        W.ControlCard(spells, Tr("Frame Effect"), nil, siRightX - 14, -356, siRightW + 28, 286)
        W.ControlCard(spells, Tr("Utilities"), nil, siRightX - 14, -650, siRightW + 28, 194)
    end

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

    local RefreshSpellIndicatorState
    local siEnable = W.SwitchAt(spells, Tr("Spell Indicators"), siLeftX, -72, siLeftW)
    siEnable._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindToggle(ctx, siEnable,
        function() return SpellIndicators(CurrentScope()).enabled == true end,
        function(value)
            SpellIndicators(CurrentScope()).enabled = value and true or false
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            QueueSpellIndicators(CurrentScope())
            if RefreshSpellIndicatorState then RefreshSpellIndicatorState() end
        end)
    local siLayer = BindNestedSlider(ctx, W.Slider(spells, Tr("Layer"), 1, 15, 1, siRightW), function() return SpellIndicators(CurrentScope()) end, "layer", 9, "visual")
    W.MoveWidget(siLayer, spells, siRightX, -72, siRightW, "LEFT")

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
    W.MoveWidget(multiSpecDrop, spells, siRightX, -136, siRightW, "LEFT")

    local multiSpecEnabled = W.ToggleAt(spells, Tr("Track selected multi spec"), siRightX, -196, siRightW)
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

    local trackedSpellsLabel = W.LabelAt(spells, Tr("Tracked Spells"), siLeftX, -166, siLeftW, "GameFontNormalSmall", T.colors.accent)
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
        local indicatorsOn = SpellIndicators(kind).enabled == true
        local si = SpellIndicatorRuntime()
        local specKey = EffectiveSpellSpec(kind)
        if specKey then EnsureSpellDefaults(kind, specKey) end
        local siCfg = SpellIndicators(kind)
        local trackable = specKey and GetOrderedTrackable(si, siCfg, specKey)
        local selected = CurrentSpellAura(kind)
        if spellTiles.SetAlpha then spellTiles:SetAlpha(indicatorsOn and 1 or 0.45) end
        if trackedSpellsLabel and trackedSpellsLabel.SetTextColor then
            local c = indicatorsOn and T.colors.accent or T.colors.dim
            trackedSpellsLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end

        for i = 1, #spellTiles._tiles do spellTiles._tiles[i]:Hide() end
        if not trackable or #trackable == 0 then
            spellTileHint:SetText(Tr("No spells for current spec."))
            if spellTileHint.SetTextColor then
                local c = indicatorsOn and T.colors.muted or T.colors.dim
                spellTileHint:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
            return
        end
        spellTileHint:SetText(Tr("Left-click configures, right-click toggles, drag to sort."))
        if spellTileHint.SetTextColor then
            local c = indicatorsOn and T.colors.muted or T.colors.dim
            spellTileHint:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end

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
            local tileEnabled = indicatorsOn and not disabled
            local selectedTile = info.name == selected
            local c = info.color or { 0.55, 0.65, 0.85 }

            if si and type(si.GetAuraIcon) == "function" then
                if type(MSUF_SetIconTexture) == "function" then
                    MSUF_SetIconTexture(tile.icon, si.GetAuraIcon(specKey, info.name), "")
                else
                    tile.icon:SetTexture(si.GetAuraIcon(specKey, info.name))
                end
            else
                tile.icon:SetTexture(136243)
            end
            tile:EnableMouse(indicatorsOn)
            tile.icon:SetDesaturated(not tileEnabled)
            tile.icon:SetAlpha(tileEnabled and 1 or 0.35)
            tile.label:SetText(info.display or info.name)
            tile.label:SetTextColor(tileEnabled and 0.92 or 0.45, tileEnabled and 0.92 or 0.45, tileEnabled and 0.92 or 0.45, 1)
            tile:SetBackdropBorderColor(
                (indicatorsOn and selectedTile) and 0.38 or (c[1] * 0.42),
                (indicatorsOn and selectedTile) and 0.66 or (c[2] * 0.42),
                (indicatorsOn and selectedTile) and 1.00 or (c[3] * 0.42),
                indicatorsOn and ((selectedTile and 1.00) or 0.82) or 0.45
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
                if SpellIndicators(CurrentScope()).enabled ~= true then return end
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

    local spellEnabled = W.SwitchAt(spells, Tr("Enabled"), siRightX, -288, siRightW)
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
                if cfg.placed.showCooldownSwipe == nil then cfg.placed.showCooldownSwipe = true end
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

    local placedCooldownSwipe = W.ToggleAt(spells, Tr("Show Cooldown Swipe"), siRightX, -722, siRightW)
    M.BindToggle(ctx, placedCooldownSwipe,
        function()
            local placed = PlacedConfig(CurrentScope(), false)
            return placed and placed.showCooldownSwipe ~= false or false
        end,
        function(value)
            local placed = PlacedConfig(CurrentScope(), true)
            if placed then placed.showCooldownSwipe = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)

    local placedCooldown = W.ToggleAt(spells, Tr("Show Cooldown Text"), siRightX, -754, siRightW)
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
    W.MoveWidget(placedCooldownSize, spells, siRightX, -786, siRightW, "LEFT")

    RefreshSpellIndicatorState = function()
        EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
        RefreshSpellTiles()
        local spellCfg = SpellIndicators(CurrentScope())
        local indicatorsOn = spellCfg.enabled == true
        local multi = spellCfg.spec == "multi"
        if W.SetControlShown then
            W.SetControlShown(multiSpecDrop, multi)
            W.SetControlShown(multiSpecEnabled, multi)
        else
            multiSpecDrop:SetShown(multi)
            multiSpecEnabled:SetShown(multi)
        end
        local placed = PlacedConfig(CurrentScope(), false)
        local hasSpell = indicatorsOn and EffectiveSpellSpec(CurrentScope()) ~= nil and CurrentSpellAura(CurrentScope()) ~= ""
        local placedEnabled = hasSpell and placed and placed.type and placed.type ~= "none"
        local frame = FrameEffectConfig(CurrentScope(), false)
        local frameKind = frame and frame.type or "none"
        local hasFrame = hasSpell and frameKind ~= "none"
        local cdRelevant = placedEnabled and placed.type == "icon"
        local barRelevant = placedEnabled and placed.type == "bar"
        SetOptionEnabled(siEnable, true)
        SetOptionEnabled(siLayer, indicatorsOn)
        SetOptionEnabled(specDrop, indicatorsOn)
        SetOptionEnabled(multiSpecDrop, indicatorsOn and multi)
        SetOptionEnabled(multiSpecEnabled, indicatorsOn and multi and CurrentSpellMultiSpec(CurrentScope()) ~= "")
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
        SetOptionEnabled(placedCooldownSwipe, cdRelevant)
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
    local cornerGap = 28
    local cornerInnerW = max(320, cornerW - 60)
    local leftW = max(240, min(360, floor((cornerInnerW - cornerGap) * 0.46)))
    local rightX = leftX + leftW + cornerGap
    local rightW = max(260, min(440, cornerInnerW - leftW - cornerGap))
    do
        W.ControlCardBackdrop(corners, leftX - 14, -38, leftW + 28, 170)
        W.ControlCardBackdrop(corners, leftX - 14, -218, leftW + 28, 334)
        W.ControlCardBackdrop(corners, rightX - 14, -38, rightW + 28, 526)
    end

    W.LabelAt(corners, "Global", leftX, -42, leftW, "GameFontNormalSmall", T.colors.accent)
    local ciEnable = BindScopeToggle(ctx, W.SwitchAt(corners, "Corner Indicators", leftX, -72, leftW), "ciEnabled", true, "visual")
    ciEnable._msuf2GroupFrameGateAlwaysEnabled = true
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
                if type(M.PersistMenuStateValue) == "function" then
                    M.PersistMenuStateValue("gfCornerSlotSelection", slotKey)
                else
                    M.gfCornerSlotSelection = slotKey
                end
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
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("gfCornerSlotSelection", value or "TL")
            else
                M.gfCornerSlotSelection = value or "TL"
            end
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

M.RegisterPage("gf_indicators", { title = "MSUF Group Indicators", build = BuildGFIndicators, version = 12 })
