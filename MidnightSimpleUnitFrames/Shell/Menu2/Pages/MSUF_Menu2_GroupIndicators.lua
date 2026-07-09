local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group Status & Indicators page.
-- Builds party/raid status icon, placed indicator, frame effect, and spell-indicator controls.
-- Runtime indicator dispatch remains in the GroupFrames engine.
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local Tr = M.TranslateText or M.Tr or function(text) return text end
local floor = math.floor
local max = math.max
local min = math.min
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture
local VT = M.ValueTextList
local WHITE_RGB = { 1, 1, 1 }
local SPELL_INDICATORS_121_PTR_DISABLED = false
local SPELL_INDICATORS_121_PTR_MESSAGE = "Native 12.1 AuraSlot SpellID filters are used for helpful auras on friendly Group Frames."
local SPELL_INDICATOR_FRAME_EFFECTS_DISABLED = true
local SPELL_INDICATOR_FRAME_EFFECTS_MESSAGE = "Frame effects are disabled for 12.1 PTR for now; icon placement and visuals stay active."
local STATUS_ICON_RESET_FIELDS = M.WordList "size anchor x y layer iconStyle customIcon"
local AURA_ANCHORS, STATUS_ICON_ANCHORS, GF_STATUS_ICON_SPECS, GF_STATUS_ICON_VALUES, PLACED_INDICATOR_TYPES, FRAME_EFFECT_TYPES, SPELL_GROWTH_VALUES, CI_SLOT_VALUES, CI_SLOT_DEFAULTS = M.PickDefaults(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS GF_STATUS_ICON_SPECS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES FRAME_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS]])
local GF, RefreshGFPreview, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, ScopeDropdown, ScopeSlider, ScopeColor, SpellIndicators, IconStyleValues, CurrentGFStatusSpec, QueueSpellIndicators, SpellSpecValues, SpellTrackedSpecValues, CurrentSpellMultiSpec, EffectiveSpellSpec, SpellAuraValues, CurrentSpellAura, CurrentSpellConfig, PlacedConfig, FrameEffectConfig, CICategoryValues, CIFilterValues, CIModeValues, CurrentCISlot, CICustomConfig, BindNestedSlider, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge, OptionText = M.Pick(GP, [[GF RefreshGFPreview Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle ScopeDropdown ScopeSlider ScopeColor SpellIndicators IconStyleValues CurrentGFStatusSpec QueueSpellIndicators SpellSpecValues SpellTrackedSpecValues CurrentSpellMultiSpec EffectiveSpellSpec SpellAuraValues CurrentSpellAura CurrentSpellConfig PlacedConfig FrameEffectConfig CICategoryValues CIFilterValues CIModeValues CurrentCISlot CICustomConfig BindNestedSlider SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus TrackSectionRefresh OnOffBadge OptionText]])
OnOffBadge = OnOffBadge or M.OnOffBadge
OptionText = OptionText or M.OptionText
local function IconPackValues()
    -- Style options come from the group runtime when available, with a small fallback for
    -- early load or test contexts where the runtime has not registered styles yet.
    local gf = GF()
    if gf and type(gf.GetIconStyleItems) == "function" then return gf.GetIconStyleItems(true) end
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
local STATUS_ICON_TAB_VALUES = VT("basic", "Basic", "advanced", "Advanced")
local TARGETED_SPELL_MODE_VALUES = VT("whenHealing", "When Healing", "always", "Always")
local TARGETED_SPELL_GROW_VALUES = VT("CENTER", "Centered", "RIGHT", "Right", "LEFT", "Left", "UP", "Up", "DOWN", "Down")
local function SetManyEnabled(enabled, ...)
    for i = 1, select("#", ...) do SetOptionEnabled(select(i, ...), enabled) end
end

local function BuildIndicatorsSection(ctx, b)
    local indicators = b:CollapsibleSection("indicators", "Frame Indicators", 650, true)
    local indicatorsW = indicators._msuf2Width or ctx.width or 720
    local cardGap = 16
    local leftX = 20
    local innerW = max(320, indicatorsW - 40)
    local leftW = floor((innerW - cardGap) * 0.48)
    local rightX = leftX + leftW + cardGap
    local rightW = innerW - leftW - cardGap
    local function IsMouseoverHighlightEnabled()
        local gen = _G.MSUF_DB and _G.MSUF_DB.general
        if gen and gen.highlightEnabled == nil and gen.enableHighlightOnHover ~= nil then return gen.enableHighlightOnHover == true end
        return not (gen and gen.highlightEnabled == false)
    end
    local function AddScopeSlider(list, parent, label, minValue, maxValue, step, width, key, defaultValue, mode, y, moveWidth)
        local control = ScopeSlider(ctx, parent, label, minValue, maxValue, step, width, key, defaultValue, mode, 16, y, moveWidth or (width - 58))
        M.AppendValues(list, control); return control
    end
    local function AddScopeDropdown(list, parent, label, values, width, key, defaultValue, mode, y)
        local control = ScopeDropdown(ctx, parent, label, values, width, key, defaultValue, mode, 16, y, width - 32)
        M.AppendValues(list, control); return control
    end
    local highlightCard = W.ControlCard(indicators, "Target Highlight", nil, leftX, -38, innerW, 92)
    local targetToggle = BindScopeToggle(ctx, W.SwitchAt(highlightCard, "Target Highlight", innerW - 62, -24, 0, "HIDDEN"), "targetIndicator", true, "visual")
    targetToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local function OpenBarsHighlight()
        _G.MSUF_EM2_MenuFocusRequest = {
            pageKey = "opt_bars",
            sectionId = "bars_highlight",
            explicit = true,
            consumed = false,
        }
        if M.SelectPage and M.SelectPage("opt_bars") == false then
            _G.MSUF_EM2_MenuFocusRequest = nil
        end
    end
    local openBars = T.Button(highlightCard, "Open Bars", 112, 22)
    openBars:SetPoint("TOPRIGHT", highlightCard, "TOPRIGHT", -16, -56)
    T.CenterButtonLabel(openBars)
    if M.AddTooltip then
        M.AddTooltip(openBars, "Open Bars", "Global Style > Bars > Highlight Borders", { hook = true })
    end
    openBars:SetScript("OnClick", OpenBarsHighlight)
    local hlHint = W.Text(highlightCard, "Shows a border around the current target in group frames. Aggro and dispel borders are controlled in Bars.", 16, -42, innerW - 164, T.colors.muted)
    if hlHint.SetWordWrap then hlHint:SetWordWrap(true) end
    local groupNumberCard = W.ControlCard(indicators, "Group Number", "Small group index label on each frame.", leftX, -148, leftW, 246)
    local groupNumberToggle = BindScopeToggle(ctx, W.SwitchAt(groupNumberCard, "Group Number", leftW - 62, -24, 0, "HIDDEN"), "showGroupNumber", false, "visual")
    groupNumberToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupNumberControls = {}
    AddScopeSlider(groupNumberControls, groupNumberCard, "Size", 6, 24, 1, leftW, "groupNumberSize", 10, "font", -66)
    AddScopeDropdown(groupNumberControls, groupNumberCard, "Anchor", AURA_ANCHORS, leftW, "groupNumberAnchor", "BOTTOMRIGHT", "geometry", -116)
    AddScopeSlider(groupNumberControls, groupNumberCard, "X Offset", -100, 100, 1, leftW, "groupNumberX", -2, "geometry", -166)
    AddScopeSlider(groupNumberControls, groupNumberCard, "Y Offset", -100, 100, 1, leftW, "groupNumberY", 2, "geometry", -216)
    local hoverCard = W.ControlCard(indicators, "Hover Highlight", "Enable + color: |cff38c7f0Global Style > Colors|r > Mouseover Highlight", rightX, -148, rightW, 126)
    local hoverHint = hoverCard and hoverCard.subtitle
    local hoverSize = W.Slider(hoverCard, "Border Thickness", 1, 6, 1, rightW)
    M.BindNumberWidget(ctx, hoverSize,
        function()
            local gf = GF and GF()
            if gf and type(gf.GetHighlightVal) == "function" then return tonumber(gf.GetHighlightVal(CurrentScope(), "hlHoverSize")) or 1 end
            return Num(CurrentScope(), "hlHoverSize", 1)
        end,
        function(value)
            local kind = CurrentScope()
            local conf = Conf(kind)
            conf.hlHoverSize = floor((tonumber(value) or 1) + 0.5)
            conf.hlOverride = true
            QueueGF(kind, "visual")
        end,
        1, { step = 1, roundStep = true })
    W.MoveWidget(hoverSize, hoverCard, 16, -70, rightW - 58, "CENTER")
    local focusCard = W.ControlCard(indicators, "Focus Highlight", "Shows a colored border around your Focus target. Priority: Dispel > Aggro > Target > Focus.", rightX, -294, rightW, 190)
    local focusToggle = BindScopeToggle(ctx, W.SwitchAt(focusCard, "Focus Highlight", rightW - 62, -24, 0, "HIDDEN"), "hlFocusEnabled", true, "visual")
    focusToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local focusHint = focusCard and focusCard.subtitle
    if focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    local focusControls = {}
    AddScopeSlider(focusControls, focusCard, "Border Thickness", 1, 6, 1, rightW, "hlFocusSize", 2, "visual", -88)
    focusControls[#focusControls + 1] = ScopeColor(ctx, focusCard, "Focus Glow Color", rightW, "hlFocusColorR", "hlFocusColorG", "hlFocusColorB", { 0.50, 0.50, 1.00 }, "visual", 16, -142, rightW - 32)
    local groupBorderCard = W.ControlCard(indicators, "Group Border", "Optional border around the full group frame.", leftX, -412, leftW, 202)
    local groupBorderToggle = BindScopeToggle(ctx, W.SwitchAt(groupBorderCard, "Group Border", leftW - 62, -24, 0, "HIDDEN"), "groupBorderEnabled", false, "visual")
    groupBorderToggle._msuf2GroupFrameGateAlwaysEnabled = true
    local groupBorderControls = {}
    AddScopeSlider(groupBorderControls, groupBorderCard, "Border Thickness", 1, 12, 1, leftW, "groupBorderSize", 1, "visual", -66)
    AddScopeSlider(groupBorderControls, groupBorderCard, "Padding", 0, 40, 1, leftW, "groupBorderPadding", 2, "visual", -116)
    groupBorderControls[#groupBorderControls + 1] = ScopeColor(ctx, groupBorderCard, "Group Border Color", leftW, "groupBorderR", "groupBorderG", "groupBorderB", { 0.38, 0.68, 1.00 }, "visual", 16, -168, leftW - 32)
    local function RefreshIndicatorsState()
        local groupNumberEnabled = Bool(CurrentScope(), "showGroupNumber", false)
        SetOptionsEnabled(groupNumberControls, groupNumberEnabled)
        SetOptionEnabled(groupNumberToggle, true)
        local targetEnabled = Bool(CurrentScope(), "targetIndicator", true)
        SetOptionEnabled(targetToggle, true)
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
        SetSectionBadgesAndStatus(indicators, {
            OnOffBadge(targetEnabled, "Target on", "Target off"),
            { text = hoverEnabled and "Hover on" or "Hover off", kind = hoverEnabled and "info" or "muted" },
            OnOffBadge(focusEnabled, "Focus on", "Focus off"),
            { text = groupNumberEnabled and "Group #" or (groupBorderEnabled and "Group border" or "Clean"), kind = (groupNumberEnabled or groupBorderEnabled) and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, indicators, RefreshIndicatorsState)
end

local function BuildStatusIconsSection(ctx, b, RefreshPage)
    local sicons = b:CollapsibleSection("sicons", "Status Icons", 624, false)
    local siconW = sicons._msuf2Width or ctx.width or 720
    local siconGap = 16
    local siconLeftX = 20
    local siconInnerW = max(320, siconW - 40)
    local siconLeftW = floor((siconInnerW - siconGap) * 0.46)
    local siconRightX = siconLeftX + siconLeftW + siconGap
    local siconRightW = siconInnerW - siconLeftW - siconGap
    M.gfStatusIconTabSelection = M.gfStatusIconTabSelection or {}
    local function CurrentStatusIconTab()
        local key = M.gfStatusIconTabSelection[CurrentScope()] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local siconTabFrames = {}
    local siconBasicTab, siconAdvancedTab = M.UnitSectionsShared.MakeTabFrames(sicons, -104, siconW, siconTabFrames, "basic", "advanced")
    W.SegmentTabs(ctx, sicons, {
        get = CurrentStatusIconTab,
        set = function(value) M.gfStatusIconTabSelection[CurrentScope()] = value or "basic" end,
        label = "Status icon controls", values = STATUS_ICON_TAB_VALUES, width = min(420, siconInnerW),
        frames = siconTabFrames,
        defaultTab = "basic", x = siconLeftX, y = -50,
    })
    local styleCard = W.ControlCard(siconBasicTab, "Style", nil, siconLeftX, -38, siconLeftW, 132)
    local selectedCard = W.ControlCard(siconBasicTab, "Selected Indicator", nil, siconLeftX, -188, siconLeftW, 316)
    local previewCard = W.ControlCard(siconBasicTab, "Status Preview", nil, siconRightX, -38, siconRightW, 164)
    local placementCard = W.ControlCard(siconBasicTab, "Placement", nil, siconRightX, -220, siconRightW, 322)
    local function RefreshStatusIconMenu()
        if M.RequestRefresh then
            M.RequestRefresh(ctx, "gf-indicators-status-icon")
        elseif M.Refresh then
            M.Refresh(ctx)
        else
            RefreshPage()
        end
    end
    local function StatusSpecDefault(spec, value)
        if type(value) == "function" then return value(spec) end
        return value
    end
    local function BindStatusDropdown(parent, label, values, width, specField, defaultValue, reason, x, y, moveWidth, afterSet)
        local control = W.Dropdown(parent, label, values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local spec = CurrentGFStatusSpec()
                local key = spec and spec[specField]
                return key and Val(CurrentScope(), key, StatusSpecDefault(spec, defaultValue)) or StatusSpecDefault(spec, defaultValue)
            end,
            function(value)
                local spec = CurrentGFStatusSpec()
                local key = spec and spec[specField]
                if not key then return end
                Set(CurrentScope(), key, value or StatusSpecDefault(spec, defaultValue), reason)
                if afterSet then afterSet(value, spec) end
            end)
        W.MoveWidget(control, parent, x, y, moveWidth or width, "LEFT")
        return control
    end
    local function BindStatusSlider(parent, label, minValue, maxValue, step, width, specField, defaultValue, reason, x, y, moveWidth, clamp)
        local control = W.Slider(parent, label, minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function()
                local spec = CurrentGFStatusSpec()
                local value = Num(CurrentScope(), spec[specField], StatusSpecDefault(spec, defaultValue))
                if clamp then
                    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
                end
                return value
            end,
            function(value)
                local spec = CurrentGFStatusSpec()
                value = floor((tonumber(value) or StatusSpecDefault(spec, defaultValue)) + 0.5)
                if clamp then
                    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
                end
                Set(CurrentScope(), spec[specField], value, reason)
            end,
            StatusSpecDefault(CurrentGFStatusSpec(), defaultValue), { step = step, roundStep = true })
        W.MoveWidget(control, parent, x, y, moveWidth or width, "LEFT")
        return control
    end
    local function BuildStatusControls(parent, specs)
        return M.BuildControlSpecs(specs, {
            dropdown = function(s, i) return BindStatusDropdown(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11]), s[12] or s[5] or i end,
            slider = function(s, i) return BindStatusSlider(parent, s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10], s[11], s[12], s[13]), s[14] or s[7] or i end,
        })
    end
    local function StatusIconPreviewEntries(spec)
        local value = spec and spec.value
        if value == "raidMarker" then return { { "raidMarker", 1 }, { "raidMarker", 5 }, { "raidMarker", 8 } } end
        if value == "readyCheckIcon" then return { { "readyCheck", "ready" }, { "readyCheck", "notready" }, { "readyCheck", "waiting" } } end
        if value == "summonIcon" then return { { "summon", 1 }, { "summon", 2 }, { "summon", 3 } } end
        if value == "resurrectIcon" then return { { "incomingRes", "resurrect" } } end
        if value == "pvpIcon" then return { { "pvp", "Alliance" }, { "pvp", "Horde" }, { "pvp", "FFA" } } end
        if value == "phaseIcon" then return { { "phase", "phase" } } end
        if value == "leaderIcon" then return { { "leader" } } end
        if value == "assistIcon" then return { { "assist" } } end
        if value == "roleIcon" then return { { "role", "TANK" }, { "role", "HEALER" }, { "role", "DAMAGER" } } end
        return nil
    end
    local function IsRoleStatusIconSpec(spec)
        local value = spec and spec.value
        return value == "roleIcon" or value == "leaderIcon" or value == "assistIcon"
    end
    local function StatusIconStyleLabel(spec)
        return "Role icon style"
    end
    local function SpecificIconLabel(spec)
        return "Custom icon"
    end
    local function SetDropdownTitle(control, label)
        if control and control._msuf2Title and control._msuf2Title.SetText then
            control._msuf2Title:SetText(Tr(label))
        end
    end
    local function IconPackValuesForCurrentStatus()
        local values = IconPackValues()
        local spec = CurrentGFStatusSpec()
        local entries = StatusIconPreviewEntries(spec)
        local supports = _G.MSUF_StatusIconPackSupports
        if type(supports) ~= "function" or type(entries) ~= "table" then return values end
        local out = {}
        local useMidnight = Bool(CurrentScope(), "useMidnightIcons", false)
        for i = 1, #values do
            local item = values[i]
            local value = item and (item.value or item.key)
            local keep = value == "DEFAULT"
            for j = 1, #entries do
                local entry = entries[j]
                if supports(value, entry[1], entry[2], useMidnight) then
                    keep = true
                    break
                end
            end
            if keep then out[#out + 1] = item end
        end
        return out
    end
    local function IconAssetValuesForCurrentStatus()
        local spec = CurrentGFStatusSpec()
        local entries = StatusIconPreviewEntries(spec)
        local valuesFn = _G.MSUF_GetStatusIconAssetValues
        if type(valuesFn) ~= "function" or type(entries) ~= "table" then
            return { { value = "", text = "Use default icon" } }
        end
        local out, used = {}, {}
        for i = 1, #entries do
            local entry = entries[i]
                local values = valuesFn(entry[1], entry[2], i == 1, true)
            for j = 1, #(values or {}) do
                local item = values[j]
                local value = item and item.value
                if type(value) == "string" and not used[value] then
                    used[value] = true
                    out[#out + 1] = item
                end
            end
        end
        if #out == 0 then out[1] = { value = "", text = "Use default icon" } end
        return out
    end
    local function ResolvePreviewStatusIcon(style, iconType, variant, useMidnight)
        local resolver = _G.MSUF_GetStatusIconTexture
        if type(resolver) ~= "function" then
            local gf = GF()
            resolver = gf and gf.GetStatusIconTexture
        end
        if type(resolver) ~= "function" then return nil end
        return resolver(style, iconType, variant, useMidnight == true)
    end
    local iconStyle = ScopeDropdown(ctx, styleCard, "Default role icon style", IconStyleValues, siconLeftW, "iconStyle", "BLIZZARD", "visual", 16, -56, siconLeftW - 32)
    local midnightStyle = BindScopeToggle(ctx, W.ToggleAt(styleCard, "Use Midnight Style", 16, -106, siconLeftW - 32), "useMidnightIcons", false, "visual")
    local statusSelector = W.Dropdown(selectedCard, "Indicator", GF_STATUS_ICON_VALUES, siconLeftW)
    M.BindDropdownWidget(ctx, statusSelector,
        function() return CurrentGFStatusSpec().value end,
        function(value)
            for i = 1, #GF_STATUS_ICON_SPECS do
                if GF_STATUS_ICON_SPECS[i].value == value then
                    M.SetMenuStateValue("gfStatusIconSelection", value)
                    local gf = GF()
                    if gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(value) end
                    RefreshStatusIconMenu()
                    return
                end
            end
        end)
    W.MoveWidget(statusSelector, selectedCard, 16, -54, siconLeftW - 32, "LEFT")
    local statusEnabled = W.SwitchAt(selectedCard, "Enabled", siconLeftW - 62, -24, 0, "HIDDEN")
    statusEnabled._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, statusEnabled,
        function()
            local spec = CurrentGFStatusSpec()
            return Bool(CurrentScope(), spec.enabled, false)
        end,
        function(value)
            local spec = CurrentGFStatusSpec()
            Set(CurrentScope(), spec.enabled, value and true or false, "visual")
            RefreshStatusIconMenu()
        end)
    local RefreshStatusIconState
    local iconPack = BindStatusDropdown(selectedCard, "Role icon style", IconPackValuesForCurrentStatus, siconLeftW, "iconStyle", "DEFAULT", "visual", 16, -106, siconLeftW - 32,
        function()
            M.CallIf(RefreshGFPreview)
            if RefreshStatusIconState then RefreshStatusIconState() end
        end)
    local customIcon = BindStatusDropdown(selectedCard, "Custom icon", IconAssetValuesForCurrentStatus, siconLeftW, "customIcon", "", "visual", 16, -158, siconLeftW - 32,
        function()
            M.CallIf(RefreshGFPreview)
            if RefreshStatusIconState then RefreshStatusIconState() end
        end)

    --- Role filter group: only visible when Role Icon indicator is selected
    local roleFilterGroup = CreateFrame("Frame", nil, selectedCard)
    roleFilterGroup:SetPoint("TOPLEFT", selectedCard, "TOPLEFT", 0, -216)
    local roleFilterW = max(180, siconLeftW - 32)
    roleFilterGroup:SetSize(roleFilterW, 60)
    W.LabelAt(roleFilterGroup, "Show for:", 16, -8, siconLeftW - 32, "GameFontNormalSmall", T.colors.accent)
    local rfColW   = floor(roleFilterW / 3)
    local rfLabelW = max(34, rfColW - 30)  --- subtract checkbox(24) + gap(6) so hit areas don't overlap the next column
    local rfTank   = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Tank",   16,              -26, rfLabelW), "roleIconShowTank",   true, "visual")
    local rfHealer = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "Healer", 16 + rfColW,     -26, rfLabelW), "roleIconShowHealer", true, "visual")
    local rfDPS    = BindScopeToggle(ctx, W.ToggleAt(roleFilterGroup, "DPS",    16 + rfColW * 2, -26, rfLabelW), "roleIconShowDPS",    true, "visual")
    local roleFilterControls = { rfTank, rfHealer, rfDPS }
    local previewInnerW = max(190, siconRightW - 32)
    local previewButtonGap = 8
    local previewCurrentW = min(142, max(112, floor(previewInnerW * 0.58)))
    local previewAllW = min(112, max(76, previewInnerW - previewCurrentW - previewButtonGap))
    previewCurrentW = max(96, previewInnerW - previewAllW - previewButtonGap)
    local function SetStatusPreviewMode(mode)
        local gf = GF()
        M.SetMenuStateValue("gfStatusPreviewMode", mode)
        if gf and gf.SetPreviewFocus then gf.SetPreviewFocus("sicons") end
        if gf and gf.SetStatusPreviewMode then gf.SetStatusPreviewMode(mode) end
        if mode == "current" and gf and gf._PreviewSelectStatusIcon then gf._PreviewSelectStatusIcon(CurrentGFStatusSpec().value) end
        M.CallIf(RefreshGFPreview)
    end
    local function PreviewActionButton(parent, label, width, onClick)
        local btn = W.Button(parent, label, width)
        btn:SetScript("OnClick", onClick)
        btn:ClearAllPoints()
        btn:SetSize(width, 24)
        return btn
    end
    local previewCurrent = PreviewActionButton(previewCard, "Preview current", previewCurrentW, function()
        SetStatusPreviewMode("current")
    end)
    previewCurrent:ClearAllPoints()
    previewCurrent:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -54)
    local previewAll = PreviewActionButton(previewCard, "Show all", previewAllW, function()
        SetStatusPreviewMode("all")
    end)
    previewAll:SetPoint("LEFT", previewCurrent, "RIGHT", previewButtonGap, 0)
    local statusReset = W.Button(previewCard, "Reset selected", min(160, previewInnerW))
    statusReset:SetScript("OnClick", function()
        local kind = CurrentScope()
        local spec = CurrentGFStatusSpec()
        local conf = Conf(kind)
        local gf = GF()
        for i = 1, #STATUS_ICON_RESET_FIELDS do
            local key = spec[STATUS_ICON_RESET_FIELDS[i]]
            if key then conf[key] = gf and gf.GetDefault and gf.GetDefault(kind, key) or nil end
        end
        QueueGF(kind, "visual")
        RefreshStatusIconMenu()
    end)
    statusReset:ClearAllPoints()
    statusReset:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -86)
    statusReset:SetSize(min(160, previewInnerW), 24)
    local iconPreviewLabel = W.LabelAt(previewCard, "Icon preview", 16, -120, previewInnerW, "GameFontNormalSmall", T.colors.accent)
    local iconPreviewStrip = CreateFrame("Frame", nil, previewCard)
    iconPreviewStrip:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -132)
    iconPreviewStrip:SetSize(previewInnerW, 24)
    local iconPreviewTextures = {}
    for i = 1, 5 do
        local holder = CreateFrame("Frame", nil, iconPreviewStrip)
        holder:SetSize(24, 24)
        holder:SetPoint("LEFT", iconPreviewStrip, "LEFT", (i - 1) * 28, 0)
        holder.bg = holder:CreateTexture(nil, "BACKGROUND")
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0.020, 0.026, 0.052, 0.70)
        holder.tex = holder:CreateTexture(nil, "ARTWORK")
        holder.tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.tex:SetSize(22, 22)
        iconPreviewTextures[i] = holder
    end
    local function RefreshIconPreviewStrip(spec, enabled)
        local entries = StatusIconPreviewEntries(spec)
        local shown = entries and spec and (IsRoleStatusIconSpec(spec) or spec.customIcon)
        iconPreviewLabel:SetShown(shown and true or false)
        iconPreviewStrip:SetShown(shown and true or false)
        if not shown then return end
        local style = IsRoleStatusIconSpec(spec) and Val(CurrentScope(), "iconStyle", "BLIZZARD") or "BLIZZARD"
        if type(style) ~= "string" or style == "" or style == "DEFAULT" then style = "BLIZZARD" end
        local customPath = spec and spec.customIcon and Val(CurrentScope(), spec.customIcon, "") or ""
        local useMidnight = Bool(CurrentScope(), "useMidnightIcons", false)
        iconPreviewStrip:SetAlpha(enabled and 1 or 0.46)
        for i = 1, #iconPreviewTextures do
            local holder = iconPreviewTextures[i]
            local entry = entries[i]
            if entry then
                local path, l, r, t, b
                if type(customPath) == "string" and customPath ~= "" then
                    path, l, r, t, b = customPath, 0, 1, 0, 1
                else
                    path, l, r, t, b = ResolvePreviewStatusIcon(style, entry[1], entry[2], useMidnight)
                end
                if type(path) == "string" and path ~= "" then
                    holder.tex:SetTexture(path)
                    holder.tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                    holder.tex:SetVertexColor(1, 1, 1, 1)
                    holder:Show()
                else
                    holder:Hide()
                end
            else
                holder:Hide()
            end
        end
    end
    local statusControls = BuildStatusControls(placementCard, {
        { "slider", "Size", 6, 40, 1, siconRightW, "size", function(spec) return spec.defaultSize end, "visual", 16, -58, siconRightW - 58 },
        { "dropdown", "Anchor", STATUS_ICON_ANCHORS, siconRightW, "anchor", function(spec) return spec.defaultAnchor end, "geometry", 16, -108, siconRightW - 32 },
        { "slider", "X Offset", -100, 100, 1, siconRightW, "x", 0, "geometry", 16, -158, siconRightW - 58 },
        { "slider", "Y Offset", -100, 100, 1, siconRightW, "y", 0, "geometry", 16, -208, siconRightW - 58 },
        { "slider", "Layer", 0, 30, 1, siconRightW, "layer", function(spec) return spec.defaultLayer end, "visual", 16, -258, siconRightW - 58, true },
    })
    local advanced = {}
    advanced.card = W.ControlCard(siconAdvancedTab, "Advanced Placement", nil, siconLeftX, -38, siconInnerW, 316)
    M.Assign(advanced, BuildStatusControls(advanced.card, {
        { "slider", "X Offset (extended)", -500, 500, 1, siconLeftW, "x", 0, "geometry", 16, -58, siconLeftW - 58 },
        { "slider", "Y Offset (extended)", -500, 500, 1, siconRightW, "y", 0, "geometry", siconRightX - siconLeftX, -58, siconRightW - 58 },
        { "slider", "Layer", 0, 30, 1, siconLeftW, "layer", function(spec) return spec.defaultLayer end, "visual", 16, -128, siconLeftW - 58, true },
    }))
    advanced.reset = W.Button(advanced.card, "Reset selected", 160)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if statusReset and statusReset.Click then statusReset:Click() end
    end)
    advanced.reset:ClearAllPoints()
    advanced.reset:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", siconRightX - siconLeftX, -150)
    advanced.reset:SetSize(160, 24)
    advanced.previewCurrent = PreviewActionButton(advanced.card, "Preview current", 142, function()
        if previewCurrent and previewCurrent.Click then previewCurrent:Click() end
    end)
    advanced.previewCurrent:SetPoint("TOPLEFT", advanced.card, "TOPLEFT", 16, -234)
    advanced.previewAll = PreviewActionButton(advanced.card, "Show all", 112, function()
        if previewAll and previewAll.Click then previewAll:Click() end
    end)
    advanced.previewAll:SetPoint("LEFT", advanced.previewCurrent, "RIGHT", 10, 0)
    local statusPlacementControls = { statusControls.size, statusControls.anchor, statusControls.x, statusControls.y, statusControls.layer, advanced.x, advanced.y, advanced.layer }
    local statusActionControls = { advanced.reset, advanced.previewCurrent, statusReset, previewCurrent }
    RefreshStatusIconState = function()
        local spec = CurrentGFStatusSpec()
        local enabled = Bool(CurrentScope(), spec.enabled, false)
        SetDropdownTitle(iconPack, StatusIconStyleLabel(spec))
        SetDropdownTitle(customIcon, SpecificIconLabel(spec))
        if iconPreviewLabel and iconPreviewLabel.SetText then
            iconPreviewLabel:SetText(IsRoleStatusIconSpec(spec) and Tr("Role icon preview") or Tr("Icon preview"))
        end
        SetOptionsEnabled(statusPlacementControls, enabled)
        SetOptionsEnabled(statusActionControls, spec ~= nil)
        SetManyEnabled(true, advanced.previewAll, previewAll, midnightStyle, statusEnabled)
        local hasIconPack = false
        local hasCustomIcon = spec and spec.customIcon
        if W.SetControlShown then
            W.SetControlShown(iconPack, hasIconPack and true or false)
            W.SetControlShown(customIcon, hasCustomIcon and true or false)
        else
            iconPack:SetShown(hasIconPack and true or false)
            if iconPack._msuf2Title then iconPack._msuf2Title:SetShown(hasIconPack and true or false) end
            customIcon:SetShown(hasCustomIcon and true or false)
            if customIcon._msuf2Title then customIcon._msuf2Title:SetShown(hasCustomIcon and true or false) end
        end
        SetOptionEnabled(iconPack, hasIconPack and enabled)
        SetOptionEnabled(customIcon, hasCustomIcon and enabled)
        local isRoleIcon = spec.value == "roleIcon"
        roleFilterGroup:SetShown(isRoleIcon)
        if isRoleIcon then SetOptionsEnabled(roleFilterControls, enabled) end
        RefreshIconPreviewStrip(spec, enabled)
        SetSectionBadgesAndStatus(sicons, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = spec and (spec.text or spec.value) or "Selected", kind = enabled and "info" or "muted" },
            { text = CurrentStatusIconTab() == "advanced" and "Advanced" or "Basic", kind = "accent" },
        })
    end
    TrackSectionRefresh(ctx, sicons, RefreshStatusIconState)
end

local function BuildTargetedSpellsSection(ctx, b)
    local targeted = b:CollapsibleSection("targetedSpells", Tr("Targeted Spells"), 448, false)
    local tsW = targeted._msuf2Width or ctx.width or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, tsW - 40)
    local leftW = floor((innerW - gap) * 0.46)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap
    local behavior = W.ControlCard(targeted, Tr("Behavior"), Tr("Party-only enemy nameplate cast tracker."), leftX, -38, leftW, 170)
    local stack = W.ControlCard(targeted, Tr("Icon Stack"), nil, leftX, -226, leftW, 190)
    local placement = W.ControlCard(targeted, Tr("Placement"), nil, rightX, -38, rightW, 270)
    local RefreshTargetedSpellState
    local function NotifyTargetedSpells()
        local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.RequestGroup) == "function" then
            apply.RequestGroup("party", "targetedSpells", "GF_TARGETED_SPELLS")
        else
            QueueGF("party", "visual")
            M.CallIf(RefreshGFPreview)
            if type(M.RefreshGFNativePreviews) == "function" then M.RefreshGFNativePreviews("GF_TARGETED_SPELLS") end
            local gf = GF and GF()
            local ts = gf and gf.TargetedSpells
            if ts and type(ts.RefreshConfig) == "function" then
                ts.RefreshConfig()
            end
        end
    end
    local function SetTS(key, value)
        Set("party", key, value, "visual")
        NotifyTargetedSpells()
        if RefreshTargetedSpellState then RefreshTargetedSpellState() end
    end
    local function BindTSToggle(widget, key, defaultValue)
        M.BindBoolWidget(ctx, widget,
            function() return Bool("party", key, defaultValue) end,
            function(value) SetTS(key, value and true or false) end)
        return widget
    end
    local function BindTSDropdown(parent, label, values, width, key, defaultValue, y)
        local control = W.Dropdown(parent, Tr(label), values, width)
        M.BindDropdownWidget(ctx, control,
            function() return Val("party", key, defaultValue) end,
            function(value) SetTS(key, value or defaultValue) end)
        W.MoveWidget(control, parent, 16, y, width - 32, "LEFT")
        return control
    end
    local function BindTSSlider(parent, label, minValue, maxValue, step, width, key, defaultValue, y)
        local control = W.Slider(parent, Tr(label), minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function() return Num("party", key, defaultValue) end,
            function(value) SetTS(key, floor((tonumber(value) or defaultValue) + 0.5)) end,
            defaultValue, { step = step, roundStep = true })
        W.MoveWidget(control, parent, 16, y, width - 58, "CENTER")
        return control
    end

    local enable = BindTSToggle(W.SwitchAt(behavior, Tr("Targeted Spell Indicators"), leftW - 62, -24, 0, "HIDDEN"), "targetedSpellsEnabled", false)
    local mode = BindTSDropdown(behavior, "Mode", TARGETED_SPELL_MODE_VALUES, leftW, "targetedSpellsMode", "whenHealing", -74)
    local status = W.Text(behavior, "", 16, -124, leftW - 32, T.colors.muted)
    if status.SetWordWrap then status:SetWordWrap(true) end
    local size = BindTSSlider(stack, "Icon Size", 8, 64, 1, leftW, "targetedSpellsIconSize", 24, -56)
    local maxIcons = BindTSSlider(stack, "Max Icons", 1, 5, 1, leftW, "targetedSpellsMaxIcons", 3, -108)
    local layer = BindTSSlider(stack, "Layer", 0, 30, 1, leftW, "targetedSpellsLayer", 10, -160)
    local anchor = BindTSDropdown(placement, "Anchor", STATUS_ICON_ANCHORS, rightW, "targetedSpellsAnchor", "CENTER", -56)
    local grow = BindTSDropdown(placement, "Growth", TARGETED_SPELL_GROW_VALUES, rightW, "targetedSpellsGrow", "CENTER", -108)
    local x = BindTSSlider(placement, "X Offset", -200, 200, 1, rightW, "targetedSpellsX", 0, -160)
    local y = BindTSSlider(placement, "Y Offset", -200, 200, 1, rightW, "targetedSpellsY", 0, -212)
    local controls = { mode, size, maxIcons, layer, anchor, grow, x, y }
    RefreshTargetedSpellState = function()
        local partyScope = CurrentScope() == "party"
        local enabled = Bool("party", "targetedSpellsEnabled", false)
        local modeValue = Val("party", "targetedSpellsMode", "whenHealing")
        SetOptionEnabled(enable, partyScope)
        SetOptionsEnabled(controls, partyScope and enabled)
        if not partyScope then
            status:SetText(Tr("Switch to Party scope to edit this feature."))
            status:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        elseif enabled then
            status:SetText(Tr("Runs only in party while the selected mode is active."))
            status:SetTextColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.95)
        else
            status:SetText(Tr("No nameplate cast events are registered while disabled."))
            status:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
        SetSectionBadgesAndStatus(targeted, {
            OnOffBadge(enabled, "Enabled", "Disabled"),
            { text = Tr("Party only"), kind = partyScope and "info" or "muted" },
            { text = OptionText(TARGETED_SPELL_MODE_VALUES, modeValue, modeValue), kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, targeted, RefreshTargetedSpellState)
end

local function BuildSpellIndicatorsSection(ctx, b, RefreshPage)
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
        if si and type(si.EnsureSpecConfig) == "function" and specKey then si.EnsureSpecConfig(SpellIndicators(kind), specKey) end
    end
    local function SpellConfigFor(kind, specKey, auraName, create)
        if not (specKey and auraName and auraName ~= "") then return nil end
        local cfg = SpellIndicators(kind)
        cfg.specs = cfg.specs or {}
        if create and not cfg.specs[specKey] then cfg.specs[specKey] = {} end
        local specCfg = cfg.specs[specKey]
        if not specCfg then return nil end
        if create and type(specCfg[auraName]) ~= "table" then specCfg[auraName] = { enabled = true, onlyOwn = true } end
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
        return (info and info.color) or WHITE_RGB
    end
    local RefreshSpellIndicatorState = M.RefreshProxy()
    local siEnable = W.SwitchAt(spells, Tr("Spell Indicators"), siLeftX, -72, siLeftW)
    siEnable._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, siEnable,
        function()
            if SPELL_INDICATORS_121_PTR_DISABLED then return false end
            return SpellIndicators(CurrentScope()).enabled == true
        end,
        function(value)
            if SPELL_INDICATORS_121_PTR_DISABLED then
                SpellIndicators(CurrentScope()).enabled = false
                QueueSpellIndicators(CurrentScope())
                RefreshSpellIndicatorState()
                return
            end
            SpellIndicators(CurrentScope()).enabled = value and true or false
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            QueueSpellIndicators(CurrentScope())
            RefreshSpellIndicatorState()
        end)
    local siPtrNotice = W.Text(spells, Tr(SPELL_INDICATORS_121_PTR_MESSAGE), siLeftX, -96, siLeftW, T.colors.dim)
    if siPtrNotice and siPtrNotice.SetWordWrap then siPtrNotice:SetWordWrap(false) end
    local siLayer = BindNestedSlider(ctx, W.Slider(spells, Tr("Layer"), 1, 15, 1, siRightW), function() return SpellIndicators(CurrentScope()) end, "layer", 9, "visual")
    W.MoveWidget(siLayer, spells, siRightX, -72, siRightW, "LEFT")
    local specDrop = W.Dropdown(spells, Tr("Spec"), SpellSpecValues, siLeftW)
    M.BindDropdownWidget(ctx, specDrop,
        function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[kind] = nil
            EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
            QueueSpellIndicators(kind)
            RefreshPage()
        end)
    W.MoveWidget(specDrop, spells, siLeftX, -116, siLeftW, "LEFT")
    local multiSpecDrop = W.Dropdown(spells, Tr("Multi-Spec Entry"), function() return SpellTrackedSpecValues() end, siRightW)
    M.BindDropdownWidget(ctx, multiSpecDrop,
        function() return CurrentSpellMultiSpec(CurrentScope()) end,
        function(value)
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[CurrentScope()] = value or ""
            EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
            RefreshPage()
        end)
    W.MoveWidget(multiSpecDrop, spells, siRightX, -136, siRightW, "LEFT")
    local multiSpecEnabled = W.ToggleAt(spells, Tr("Track selected multi spec"), siRightX, -196, siRightW)
    M.BindBoolWidget(ctx, multiSpecEnabled,
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
            RefreshPage()
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
    local function SetSpellTileBorder(tile, selected, color, scale, alpha)
        tile:SetBackdropBorderColor(
            selected and 0.38 or (color[1] * scale),
            selected and 0.66 or (color[2] * scale),
            selected and 1.00 or (color[3] * scale),
            selected and 1.00 or alpha
        )
    end
    local function SpellTileOnEnter(self)
        local info, c = self._info or {}, self._color or WHITE_RGB
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(info.display or info.name, 1, 1, 1)
        if info.secret then GameTooltip:AddLine(Tr("Secret aura (name/fingerprint matched)"), 0.72, 0.62, 0.95) end
        GameTooltip:AddLine(Tr("Left-click to configure"), 0.75, 0.78, 0.86)
        GameTooltip:AddLine(Tr("Right-click to toggle"), 0.55, 0.82, 0.55)
        GameTooltip:AddLine(Tr("Drag to reorder"), 0.55, 0.70, 0.95)
        GameTooltip:Show()
        self:SetBackdropColor(0.070, 0.085, 0.125, 1)
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    local function SpellTileOnLeave(self)
        GameTooltip:Hide()
        self:SetBackdropColor(0.035, 0.040, 0.070, 0.96)
        SetSpellTileBorder(self, self._auraName == CurrentSpellAura(CurrentScope()), self._color or WHITE_RGB, 0.62, 0.82)
    end
    local function SpellTileOnDragStart(self)
        GameTooltip:Hide()
        self._dragged = true
        self:StartMoving()
        self:SetFrameStrata("TOOLTIP")
    end
    local function SpellTileOnDragStop(self)
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
            if dist < bestDist then bestSlot, bestDist = slot, dist end
        end
        local currentKind = CurrentScope()
        local function ReorderSpellIndicator()
            InsertSpellAt(SpellIndicators(currentKind), self._specKey, self._trackable, self._auraName, bestSlot)
            QueueSpellIndicators(currentKind)
        end
        M.RunWithHistory("Spell Indicator Order", "group:spellOrder:" .. tostring(currentKind) .. ":" .. tostring(self._specKey), ReorderSpellIndicator)
        RefreshPage()
    end
    local function SpellTileOnMouseUp(self, button)
        if SpellIndicators(CurrentScope()).enabled ~= true then return end
        if self._dragged then self._dragged = false; return end
        local currentKind = CurrentScope()
        if button == "RightButton" then
            local function ToggleSpellIndicator()
                local cfg = SpellConfigFor(currentKind, self._specKey, self._auraName, true)
                if cfg then cfg.enabled = cfg.enabled == false and true or false end
                QueueSpellIndicators(currentKind)
            end
            M.RunWithHistory("Toggle Spell Indicator", "group:spellToggle:" .. tostring(currentKind) .. ":" .. tostring(self._specKey) .. ":" .. tostring(self._auraName), ToggleSpellIndicator)
        else
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[currentKind] = self._auraName
            M.CallIf(RefreshGFPreview)
        end
        RefreshPage()
    end
    local function EnsureSpellTile(index)
        local tile = spellTiles._tiles[index]
        if tile then return tile end
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
        -- Refreshes only update tile state; handlers are assigned once to avoid per-refresh closure churn.
        tile:SetScript("OnEnter", SpellTileOnEnter)
        tile:SetScript("OnLeave", SpellTileOnLeave)
        tile:SetScript("OnDragStart", SpellTileOnDragStart)
        tile:SetScript("OnDragStop", SpellTileOnDragStop)
        tile:SetScript("OnMouseUp", SpellTileOnMouseUp)
        spellTiles._tiles[index] = tile
        return tile
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
            local tile = EnsureSpellTile(i)
            local x, y = TileSlotPos(i)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", spellTiles, "TOPLEFT", x, y)
            tile._slot, tile._auraName, tile._specKey, tile._trackable, tile._info, tile._dragged = i, info.name, specKey, trackable, info, false
            local auraCfg = SpellConfigFor(kind, specKey, info.name, false)
            local disabled = auraCfg and auraCfg.enabled == false
            local tileEnabled = indicatorsOn and not disabled
            local selectedTile = info.name == selected
            local c = info.color or { 0.55, 0.65, 0.85 }
            tile._color = c
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
            SetSpellTileBorder(tile, indicatorsOn and selectedTile, c, 0.42, indicatorsOn and 0.82 or 0.45)
            tile:Show()
        end
    end
    local auraDrop = W.Dropdown(spells, Tr("Spell"), function() return SpellAuraValues(CurrentScope()) end, siRightW)
    M.BindDropdownWidget(ctx, auraDrop,
        function() return CurrentSpellAura(CurrentScope()) end,
        function(value)
            M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
            M.gfSpellIndicatorSelection[CurrentScope()] = value
            M.CallIf(RefreshGFPreview)
            RefreshPage()
        end)
    W.MoveWidget(auraDrop, spells, siRightX, -228, siRightW, "LEFT")
    local spellEnabled = W.SwitchAt(spells, Tr("Enabled"), siRightX, -288, siRightW)
    M.BindBoolWidget(ctx, spellEnabled,
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
    M.BindBoolWidget(ctx, onlyMine,
        function()
            local cfg = CurrentSpellConfig(CurrentScope(), false)
            return cfg and cfg.onlyOwn ~= false or false
        end,
        function(value)
            local cfg = CurrentSpellConfig(CurrentScope(), true)
            if cfg then cfg.onlyOwn = value and true or false end
            QueueSpellIndicators(CurrentScope())
        end)
    local function BindPlacedDropdown(label, values, key, default, y)
        local control = W.Dropdown(spells, Tr(label), values, siLeftW)
        M.BindDropdownWidget(ctx, control,
            function()
                local placed = PlacedConfig(CurrentScope(), false)
                return placed and placed[key] or default
            end,
            function(value)
                local placed = PlacedConfig(CurrentScope(), true)
                if placed then placed[key] = value or default end
                QueueSpellIndicators(CurrentScope())
            end)
        W.MoveWidget(control, spells, siLeftX, y, siLeftW, "LEFT")
        return control
    end
    local function BindConfigSlider(configFn, x, width, label, minValue, maxValue, step, key, default, y)
        local control = W.Slider(spells, Tr(label), minValue, maxValue, step, width)
        M.BindNumberWidget(ctx, control,
            function()
                local cfg = configFn(CurrentScope(), false)
                return tonumber(cfg and cfg[key]) or default
            end,
            function(value)
                local cfg = configFn(CurrentScope(), true)
                if cfg then cfg[key] = floor((tonumber(value) or default) + 0.5) end
                QueueSpellIndicators(CurrentScope())
            end,
            default, { step = step, roundStep = true })
        W.MoveWidget(control, spells, x, y, width, "LEFT")
        return control
    end
    local function BindPlacedSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(PlacedConfig, siLeftX, siLeftW, label, minValue, maxValue, step, key, default, y)
    end
    local function BindPlacedToggle(label, key, defaultWhenPlaced, y)
        local control = W.ToggleAt(spells, Tr(label), siRightX, y, siRightW)
        M.BindBoolWidget(ctx, control,
            function()
                local placed = PlacedConfig(CurrentScope(), false)
                if not placed then return false end
                local value = placed[key]
                if value == nil then return defaultWhenPlaced and true or false end
                return value and true or false
            end,
            function(value)
                local placed = PlacedConfig(CurrentScope(), true)
                if placed then placed[key] = value and true or false end
                QueueSpellIndicators(CurrentScope())
            end)
        return control
    end
    local function BindFrameSlider(label, minValue, maxValue, step, key, default, y)
        return BindConfigSlider(FrameEffectConfig, siRightX, siRightW, label, minValue, maxValue, step, key, default, y)
    end
    local function BindSpellSubType(label, values, x, y, width, field, applyDefaults, afterSet)
        local control = W.Dropdown(spells, Tr(label), values, width)
        M.BindDropdownWidget(ctx, control,
            function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                local sub = cfg and cfg[field]
                return type(sub) == "table" and sub.type or "none"
            end,
            function(value)
                local cfg = CurrentSpellConfig(CurrentScope(), true)
                if not cfg then return end
                if value == "none" then
                    cfg[field] = false
                else
                    cfg[field] = type(cfg[field]) == "table" and cfg[field] or {}
                    cfg[field].type = value
                    if applyDefaults then applyDefaults(cfg[field]) end
                end
                QueueSpellIndicators(CurrentScope())
                if afterSet then afterSet() end
            end)
        W.MoveWidget(control, spells, x, y, width, "LEFT")
        return control
    end
    local placedType = BindSpellSubType("Indicator Type", PLACED_INDICATOR_TYPES, siLeftX, -410, siLeftW, "placed",
        function(placed)
            placed.type = placed.type or "icon"
            placed.anchor = placed.anchor or "TOPLEFT"
            placed.size = tonumber(placed.size) or 18
            if placed.showCooldownSwipe == nil then placed.showCooldownSwipe = true end
        end,
        RefreshPage)
    local placedAnchor = BindPlacedDropdown("Anchor", STATUS_ICON_ANCHORS, "anchor", "TOPLEFT", -464)
    local placedSize = BindPlacedSlider("Size", 6, 48, 1, "size", 18, -518)
    local placedX = BindPlacedSlider("X Offset", -100, 100, 1, "x", 0, -572)
    local placedY = BindPlacedSlider("Y Offset", -100, 100, 1, "y", 0, -626)
    local placedBarWidth = BindPlacedSlider("Bar Width", 8, 120, 1, "barWidth", 42, -680)
    local placedGrowth = BindPlacedDropdown("Growth", SPELL_GROWTH_VALUES, "growth", "RIGHTDOWN", -734)
    local frameType = BindSpellSubType("Frame Effect", FRAME_EFFECT_TYPES, siRightX, -390, siRightW, "frame",
        function(frame)
            if not frame.color then
                local c = CurrentAuraColor(CurrentScope())
                frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
            end
            frame.priority = frame.priority or 5
        end)
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
    local framePriority = BindFrameSlider("Priority", 1, 10, 1, "priority", 5, -500)
    local frameAlpha = W.Slider(spells, Tr("Tint Alpha"), 5, 100, 5, siRightW)
    M.BindNumberWidget(ctx, frameAlpha,
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
        end,
        25, { step = 5, roundStep = true })
    W.MoveWidget(frameAlpha, spells, siRightX, -554, siRightW, "LEFT")
    local frameThickness = BindFrameSlider("Border / Glow Thickness", 1, 8, 1, "thickness", 2, -608)
    local frameEffectNotice = W.Text(spells, Tr(SPELL_INDICATOR_FRAME_EFFECTS_MESSAGE), siRightX, -634, siRightW, T.colors.dim)
    if frameEffectNotice and frameEffectNotice.SetWordWrap then frameEffectNotice:SetWordWrap(false) end
    local placedMissing = BindPlacedToggle("Show when missing", "missing", false, -690)
    local placedCooldownSwipe = BindPlacedToggle("Show Cooldown Swipe", "showCooldownSwipe", true, -722)
    local placedCooldown = BindPlacedToggle("Show Cooldown Text", "showCooldown", true, -754)
    local placedCooldownSize = BindConfigSlider(PlacedConfig, siRightX, siRightW, "Cooldown Text Size", 6, 24, 1, "cooldownSize", 8, -786)
    RefreshSpellIndicatorState = RefreshSpellIndicatorState(function()
        if SPELL_INDICATORS_121_PTR_DISABLED and SpellIndicators(CurrentScope()).enabled ~= false then
            SpellIndicators(CurrentScope()).enabled = false
            QueueSpellIndicators(CurrentScope())
        end
        EnsureSpellDefaults(CurrentScope(), EffectiveSpellSpec(CurrentScope()))
        RefreshSpellTiles()
        local spellCfg = SpellIndicators(CurrentScope())
        local indicatorsOn = (not SPELL_INDICATORS_121_PTR_DISABLED) and spellCfg.enabled == true
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
        local hasFrame = (not SPELL_INDICATOR_FRAME_EFFECTS_DISABLED) and hasSpell and frameKind ~= "none"
        local cdRelevant = placedEnabled and placed.type == "icon"
        local barRelevant = placedEnabled and placed.type == "bar"
        SetOptionEnabled(siEnable, not SPELL_INDICATORS_121_PTR_DISABLED)
        SetManyEnabled(indicatorsOn, siLayer, specDrop)
        SetOptionEnabled(multiSpecDrop, indicatorsOn and multi)
        SetOptionEnabled(multiSpecEnabled, indicatorsOn and multi and CurrentSpellMultiSpec(CurrentScope()) ~= "")
        SetManyEnabled(hasSpell, spellEnabled, onlyMine, placedType)
        SetManyEnabled(placedEnabled, placedAnchor, placedSize, placedX, placedY, placedGrowth)
        SetOptionEnabled(placedMissing, false)
        SetOptionEnabled(placedBarWidth, barRelevant)
        SetManyEnabled(cdRelevant, placedCooldownSwipe, placedCooldown)
        SetOptionEnabled(placedCooldownSize, cdRelevant and placed and placed.showCooldown ~= false)
        SetOptionEnabled(frameType, false)
        SetManyEnabled(hasFrame, frameColor, framePriority)
        SetOptionEnabled(frameAlpha, hasFrame and (frameKind == "healthtint" or frameKind == "pulse"))
        SetOptionEnabled(frameThickness, hasFrame and (frameKind == "border" or frameKind == "glow"))
        local badges = {
            OnOffBadge(indicatorsOn, "Enabled", "Disabled"),
        }
        if SPELL_INDICATORS_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
        if SPELL_INDICATOR_FRAME_EFFECTS_DISABLED then badges[#badges + 1] = { text = "Effects off", kind = "muted" } end
        badges[#badges + 1] = { text = OptionText(SpellSpecValues, SpellIndicators(CurrentScope()).spec or "auto", "Auto"), kind = indicatorsOn and "info" or "muted" }
        badges[#badges + 1] = { text = hasSpell and tostring(CurrentSpellAura(CurrentScope()) or "") or "No spell", kind = hasSpell and "accent" or "muted" }
        SetSectionBadgesAndStatus(spells, badges)
    end)
    TrackSectionRefresh(ctx, spells, RefreshSpellIndicatorState)
end

GP.BuildSpellIndicatorsSection = BuildSpellIndicatorsSection

local function BuildCornerIndicatorsSection(ctx, b, RefreshPage)
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
    local ciEnable = BindScopeToggle(ctx, W.SwitchAt(corners, "Corner Indicators", leftX, -72, leftW), "ciEnabled", false, "visual")
    ciEnable._msuf2GroupFrameGateAlwaysEnabled = true
    local ciSize = ScopeSlider(ctx, corners, "Icon Size", 4, 24, 1, leftW, "ciSize", 8, "visual", leftX, -116, leftW, "LEFT")
    local ciAlpha = W.Slider(corners, "Alpha", 10, 100, 5, leftW)
    M.BindNumberWidget(ctx, ciAlpha,
        function() return floor((Num(CurrentScope(), "ciAlpha", 1) * 100) + 0.5) end,
        function(value) Set(CurrentScope(), "ciAlpha", (tonumber(value) or 100) / 100, "visual") end,
        100, { step = 5, roundStep = true })
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
        M.BindDropdownWidget(ctx, slotDrop,
            function()
                return Val(CurrentScope(), "ciSlot" .. slotKey, CI_SLOT_DEFAULTS[slotKey] or "none")
            end,
            function(value)
                M.SetMenuStateValue("gfCornerSlotSelection", slotKey)
                Set(CurrentScope(), "ciSlot" .. slotKey, value or "none", "visual")
                RefreshPage()
            end)
        W.MoveWidget(slotDrop, corners, p.x, p.y, w, "LEFT")
        slotControls[#slotControls + 1] = slotDrop
    end
    W.LabelAt(corners, "Custom Spell Editor", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Pick a slot, set it to Custom Spell, then enter spell IDs. This edits one slot at a time and keeps the five slot assignments visible.", rightX, -64, rightW, T.colors.muted)
    local slotDrop = W.Dropdown(corners, "Editor Slot", CI_SLOT_VALUES, rightW)
    M.BindDropdownWidget(ctx, slotDrop,
        function() return CurrentCISlot() end,
        function(value)
            M.SetMenuStateValue("gfCornerSlotSelection", value or "TL")
            RefreshPage()
        end)
    W.MoveWidget(slotDrop, corners, rightX, -122, rightW, "LEFT")
    local categoryDrop = W.Dropdown(corners, "Selected Slot Indicator", CICategoryValues, rightW)
    M.BindDropdownWidget(ctx, categoryDrop,
        function()
            local slot = CurrentCISlot()
            return Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        end,
        function(value)
            local slot = CurrentCISlot()
            Set(CurrentScope(), "ciSlot" .. slot, value or "none", "visual")
            RefreshPage()
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
    local function BindCICustomDropdown(label, values, key, defaultValue, y)
        local control = W.Dropdown(corners, label, values, rightW)
        M.BindDropdownWidget(ctx, control,
            function()
                local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), false)
                return cfg and cfg[key] or defaultValue
            end,
            function(value)
                local cfg = CICustomConfig(CurrentScope(), CurrentCISlot(), true)
                if cfg then cfg[key] = value or defaultValue end
                QueueGF(CurrentScope(), "visual")
            end)
        W.MoveWidget(control, corners, rightX, y, rightW, "LEFT")
        return control
    end
    local customMode = BindCICustomDropdown("When", CIModeValues, "mode", "present", -350)
    local customFilter = BindCICustomDropdown("Filter", CIFilterValues, "filter", "HELPFUL|PLAYER", -404)
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
    local ciGlobalControls, ciEditorControls, ciCustomControls = { ciSize, ciAlpha }, { slotDrop, categoryDrop }, { customSpells, customMode, customFilter, customColor }
    local function RefreshCornerIndicatorState()
        local slot = CurrentCISlot()
        local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
        local showCustom = category == "custom"
        local enabled = Bool(CurrentScope(), "ciEnabled", false)
        SetOptionEnabled(ciEnable, true)
        SetOptionsEnabled(ciGlobalControls, enabled)
        SetOptionsEnabled(slotControls, enabled)
        SetOptionsEnabled(ciEditorControls, enabled)
        SetOptionsEnabled(ciCustomControls, enabled and showCustom)
        local slotLabel = slot
        for i = 1, #CI_SLOT_VALUES do
            if CI_SLOT_VALUES[i].value == slot then
                slotLabel = CI_SLOT_VALUES[i].text or slot
                break
            end
        end
        SetSectionBadgesAndStatus(corners, {
            OnOffBadge(enabled, "Enabled", "Disabled"),
            { text = slotLabel, kind = enabled and "info" or "muted" },
            { text = OptionText(CICategoryValues, category, "None"), kind = showCustom and "accent" or (enabled and "info" or "muted") },
        })
        if showCustom then
            customStatus:SetText(M.Format("%s is using Custom Spell. These settings are active.", slotLabel))
            customStatus:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 0.95)
        else
            customStatus:SetText(M.Format("%s is set to %s. Set Selected Slot Indicator to Custom Spell to activate this editor.", slotLabel, tostring(category or "none")))
            customStatus:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
    end
    TrackSectionRefresh(ctx, corners, RefreshCornerIndicatorState)
end

local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.CallIf(M.SelectPage, ctx.key) end
    BuildIndicatorsSection(ctx, b)
    BuildStatusIconsSection(ctx, b, RefreshPage)
    BuildTargetedSpellsSection(ctx, b)
    BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_indicators", { title = "MSUF Group Status & Indicators", build = BuildGFIndicators, version = 17 })
