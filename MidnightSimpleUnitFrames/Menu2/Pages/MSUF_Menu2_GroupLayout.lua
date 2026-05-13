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
local ApplyScopeEnabledGate = GP.ApplyScopeEnabledGate
local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local general = b:CollapsibleSection("general", "General", 310, false)
    local generalW = general._msuf2Width or b.width or 720
    local generalLeftX = 32
    local generalRightX = min(max(430, floor(generalW * 0.52)), max(360, generalW - 360))
    local generalLeftW = max(250, generalRightX - generalLeftX - 42)
    local generalRightW = max(250, generalW - generalRightX - 32)
    local offlineSliderW = max(320, min(520, generalW - generalLeftX - 170))

    W.LabelAt(general, "Frame", generalLeftX, -38, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(general, "Behavior", generalRightX, -38, generalRightW, "GameFontNormalSmall", T.colors.accent)
    local enableGroup = BindScopeToggle(ctx, W.Toggle(general, "Enable group frames"), "enabled", false, "rebuild")
    enableGroup._msuf2GroupFrameGateAlwaysEnabled = true
    local showPlayer = BindScopeToggle(ctx, W.Toggle(general, "Show player"), "showPlayer", true, "rebuild")
    local showSolo = BindScopeToggle(ctx, W.Toggle(general, "Show solo"), "showSolo", false, "rebuild")
    local reverseFill = BindScopeToggle(ctx, W.Toggle(general, "Reverse fill direction"), "reverseFill", false, "visual")
    local smoothFill = BindScopeToggle(ctx, W.Toggle(general, "Smooth health fill"), "smoothFill", true, "visual")
    local hideClient = BindScopeToggle(ctx, W.Toggle(general, "Hide in client scene"), "hideInClientScene", true, "visual")
    W.MoveWidget(enableGroup, general, generalLeftX, -64)
    W.MoveWidget(showPlayer, general, generalLeftX, -94)
    W.MoveWidget(showSolo, general, generalLeftX, -124)
    W.MoveWidget(smoothFill, general, generalRightX, -64)
    W.MoveWidget(reverseFill, general, generalRightX, -94)
    W.MoveWidget(hideClient, general, generalRightX, -124)

    W.DividerAt(general, -166, generalLeftX, 32)
    W.LabelAt(general, "Offline Members", generalLeftX, -184, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    local hideOfflineEnabled = BindScopeToggle(ctx, W.Toggle(general, "Hide offline members"), "hideOfflineEnabled", false, "visual")
    local hideOfflineCombat = BindScopeToggle(ctx, W.Toggle(general, "Hide offline in combat"), "hideOfflineInCombat", false, "visual")
    local hideOffline = BindScopeSlider(ctx, W.Slider(general, "Hide offline after", 0, 120, 1, offlineSliderW), "hideOfflineDelay", 0, "visual")
    W.MoveWidget(hideOfflineEnabled, general, generalLeftX, -210)
    W.MoveWidget(hideOfflineCombat, general, generalRightX, -210)
    W.MoveWidget(hideOffline, general, generalLeftX, -244, offlineSliderW, "LEFT")

    local function RefreshHideOfflineState()
        local enabled = Bool(CurrentScope(), "hideOfflineEnabled", false)
        SetOptionEnabled(hideOfflineCombat, enabled)
        SetOptionEnabled(hideOffline, enabled)
    end
    M.AddRefresher(ctx, RefreshHideOfflineState)
    RefreshHideOfflineState()

    local layout = b:CollapsibleSection("layout", "Layout", 450, false)
    local layoutW = layout._msuf2Width or b.width or 720
    local layoutLeftX = 32
    local layoutRightX = min(max(500, floor(layoutW * 0.52)), max(420, layoutW - 300))
    local layoutSliderW = max(340, min(480, layoutRightX - layoutLeftX - 56))
    local widthSlider = BindScopeSlider(ctx, W.Slider(layout, "Width", 40, 300, 1, layoutSliderW), "width", 120, "rebuild")
    local heightSlider = BindScopeSlider(ctx, W.Slider(layout, "Height", 16, 120, 1, layoutSliderW), "height", 40, "rebuild")
    local spacingSlider = BindScopeSlider(ctx, W.Slider(layout, "Spacing", 0, 20, 1, layoutSliderW), "spacing", 1, "rebuild")
    BuildGrowthDirectionTiles(ctx, layout, { x = layoutRightX, y = -38, advanceCursor = false })
    local unitsSlider = BindScopeSlider(ctx, W.Slider(layout, "Units per column", 1, 40, 1, layoutSliderW), "unitsPerColumn", 5, "rebuild")
    local maxColumnsSlider = BindScopeSlider(ctx, W.Slider(layout, "Max columns", 1, 8, 1, layoutSliderW), "maxColumns", 8, "rebuild")
    local preserveRaidGroups = BindScopeToggle(ctx, W.Toggle(layout, "Preserve raid groups"), "preserveRaidGroups", false, "rebuild")
    W.MoveWidget(widthSlider, layout, layoutLeftX, -58, layoutSliderW, "LEFT")
    W.MoveWidget(heightSlider, layout, layoutLeftX, -112, layoutSliderW, "LEFT")
    W.MoveWidget(spacingSlider, layout, layoutLeftX, -166, layoutSliderW, "LEFT")
    W.MoveWidget(unitsSlider, layout, layoutLeftX, -252, layoutSliderW, "LEFT")
    W.MoveWidget(maxColumnsSlider, layout, layoutLeftX, -306, layoutSliderW, "LEFT")
    W.MoveWidget(preserveRaidGroups, layout, layoutLeftX, -360)
    local function RefreshRaidGroupLayoutState()
        SetOptionEnabled(preserveRaidGroups, CurrentScope() ~= "party")
    end
    M.AddRefresher(ctx, RefreshRaidGroupLayoutState)
    RefreshRaidGroupLayoutState()

    local sorting = b:CollapsibleSection("sorting", "Sorting", 300, false)
    local sortingW = sorting._msuf2Width or b.width or 720
    local sortingLeftX = 32
    local sortingRightX = min(max(470, floor(sortingW * 0.54)), max(380, sortingW - 310))
    local sortMode = W.Dropdown(sorting, "Sort Mode", SORT_MODES, 260)
    W.MoveWidget(sortMode, sorting, sortingLeftX, -54, 260, "LEFT")
    if sortMode._msuf2Title then
        sortMode._msuf2Title:ClearAllPoints()
        sortMode._msuf2Title:SetPoint("LEFT", sortMode, "RIGHT", 8, 0)
        sortMode._msuf2Title:SetJustifyH("LEFT")
        sortMode._msuf2Title:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
    end
    local refreshSortingControls
    M.BindDropdown(ctx, sortMode,
        function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.sortMode = v or "INDEX"
            conf.sortByRole = (conf.sortMode == "ROLE")
            QueueGF(CurrentScope(), "rebuild")
            if refreshSortingControls then refreshSortingControls() end
        end)
    local roleSort = W.Toggle(sorting, "Sort by Role")
    W.MoveWidget(roleSort, sorting, sortingLeftX, -94)
    M.BindToggle(ctx, roleSort,
        function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.sortByRole = v and true or false
            conf.sortMode = v and "ROLE" or "INDEX"
            QueueGF(CurrentScope(), "rebuild")
            if refreshSortingControls then refreshSortingControls() end
        end)
    local playerFirst = BindScopeToggle(ctx, W.Toggle(sorting, "Player first in role"), "playerFirstInRole", false, "rebuild")
    W.MoveWidget(playerFirst, sorting, sortingLeftX, -130)
    local roleRows = BuildRoleOrderRows(ctx, sorting, {
        x = sortingRightX,
        y = -54,
        width = 250,
        title = "Role Priority",
        hint = "Drag rows with mouse to reorder.",
        advanceCursor = false,
    })
    refreshSortingControls = function()
        local conf = Conf(CurrentScope())
        local currentMode = conf.sortMode or (conf.sortByRole and "ROLE" or "INDEX")
        local enabled = currentMode == "ROLE"
        if sortMode.SetValue then sortMode:SetValue(currentMode) end
        if roleSort.SetChecked then roleSort:SetChecked(enabled) end
        SetOptionEnabled(playerFirst, enabled)
        if roleRows then
            if roleRows.Refresh then roleRows.Refresh() end
            if roleRows.SetRowsEnabled then roleRows:SetRowsEnabled(enabled) end
        end
    end
    M.AddRefresher(ctx, refreshSortingControls)

    local scale = b:CollapsibleSection("scaling", "Frame Scaling", 380, false)
    local scaleW = scale._msuf2Width or b.width or 720
    local scaleLeftX = 32
    local scaleRightX = min(max(470, floor(scaleW * 0.54)), max(380, scaleW - 380))
    local scaleLeftW = max(280, min(360, scaleRightX - scaleLeftX - 70))
    local scaleRightW = max(280, min(360, scaleW - scaleRightX - 38))
    local RefreshScalingState
    local scaleMode = W.Dropdown(scale, "Scale Mode", {
        { value = "off", text = "Off (100%)" },
        { value = "auto", text = "Auto (by group size)" },
        { value = "manual", text = "Manual" },
    }, scaleLeftW)
    M.BindDropdown(ctx, scaleMode,
        function() return Val(CurrentScope(), "frameScaleMode", "off") end,
        function(v)
            Set(CurrentScope(), "frameScaleMode", v or "off", "rebuild")
            if RefreshScalingState then RefreshScalingState() end
        end)

    local function PlaceDropdown(control, x, y, width)
        if not control then return end
        width = width or 220
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", scale, "TOPLEFT", x, y)
        control:SetSize(width, 22)
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("LEFT", control, "RIGHT", 8, 0)
            control._msuf2Title:SetJustifyH("LEFT")
            control._msuf2Title:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
        end
    end

    local function PlaceScaleSlider(control, x, y, width)
        W.MoveWidget(control, scale, x, y, width or 220, "LEFT")
    end

    local function BindScaleSlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), "rebuild")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(floor((tonumber(value) or default or 0) + 0.5)))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    PlaceDropdown(scaleMode, scaleLeftX, -54, scaleLeftW)
    local manualScale = BindScaleSlider(W.Slider(scale, "", 50, 150, 5, scaleLeftW), "frameScaleManual", 100,
        function(v) return string.format("Manual Scale: %d%%", v) end)
    PlaceScaleSlider(manualScale, scaleLeftX, -100, scaleLeftW)

    local autoLabel = T.Font(scale, "GameFontNormalSmall", "Auto Breakpoints", T.colors.accent)
    autoLabel:SetPoint("TOPLEFT", scale, "TOPLEFT", scaleRightX, -54)
    autoLabel:SetWidth(scaleRightW)

    local scaleAt10 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, scaleRightW), "scaleAt10", 100,
        function(v) return string.format("1-10 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt10, scaleRightX, -88, scaleRightW)
    local scaleAt20 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, scaleRightW), "scaleAt20", 85,
        function(v) return string.format("11-20 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt20, scaleRightX, -142, scaleRightW)
    local scaleAt25 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, scaleRightW), "scaleAt25", 80,
        function(v) return string.format("21-25 players: %d%%", v) end)
    PlaceScaleSlider(scaleAt25, scaleRightX, -196, scaleRightW)
    local scaleOver25 = BindScaleSlider(W.Slider(scale, "", 50, 100, 5, scaleRightW), "scaleOver25", 70,
        function(v) return string.format("26+ players: %d%%", v) end)
    PlaceScaleSlider(scaleOver25, scaleRightX, -250, scaleRightW)

    local scaleHint = W.Text(scale, "Scales frame size, fonts, and icons proportionally.\nBuff/debuff positions stay relative to their anchors.", scaleLeftX, -154, scaleLeftW, T.colors.dim)
    if scaleHint.SetWordWrap then scaleHint:SetWordWrap(true) end

    RefreshScalingState = function()
        local mode = Val(CurrentScope(), "frameScaleMode", "off")
        local manualOn = mode == "manual"
        local autoOn = mode == "auto"
        SetOptionEnabled(manualScale, manualOn)
        SetOptionEnabled(scaleAt10, autoOn)
        SetOptionEnabled(scaleAt20, autoOn)
        SetOptionEnabled(scaleAt25, autoOn)
        SetOptionEnabled(scaleOver25, autoOn)
        if autoLabel then
            if autoOn then
                autoLabel:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
                autoLabel:SetAlpha(1)
            else
                autoLabel:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
                autoLabel:SetAlpha(0.55)
            end
        end
        if scaleHint then scaleHint:SetAlpha((manualOn or autoOn) and 1 or 0.55) end
    end
    M.AddRefresher(ctx, RefreshScalingState)
    RefreshScalingState()

    local transparency = b:CollapsibleSection("border", "Transparency", 310, false)
    local transparencyW = transparency._msuf2Width or b.width or 720
    local transLeftX = 32
    local transRightX = min(max(470, floor(transparencyW * 0.54)), max(380, transparencyW - 380))
    local transLeftW = max(280, min(360, transRightX - transLeftX - 70))
    local transRightW = max(280, min(360, transparencyW - transRightX - 38))
    local tHint = W.Text(transparency, "Outline border thickness is configured in\nGlobal Style > Bars > Outline & Highlight Border.", transLeftX, -38, transLeftW, { 0.60, 0.75, 1.00, 1 })
    if tHint.SetWordWrap then tHint:SetWordWrap(true) end

    local bgColor = W.Color(transparency, "Background Color")
    if bgColor._msuf2Title then
        bgColor._msuf2Title:ClearAllPoints()
        bgColor._msuf2Title:SetPoint("TOPLEFT", transparency, "TOPLEFT", transLeftX, -100)
        bgColor._msuf2Title:SetWidth(120)
        bgColor._msuf2Title:SetJustifyH("LEFT")
    end
    bgColor:ClearAllPoints()
    bgColor:SetPoint("TOPLEFT", transparency, "TOPLEFT", transLeftX + 138, -98)
    bgColor:SetSize(34, 16)
    M.BindColor(ctx, bgColor,
        function()
            local conf = Conf(CurrentScope())
            return conf.bgR or 0.10, conf.bgG or 0.10, conf.bgB or 0.10
        end,
        function(r, g, b)
            local conf = Conf(CurrentScope())
            conf.bgR, conf.bgG, conf.bgB = r, g, b
            QueueGF(CurrentScope(), "visual")
        end)

    local function PlaceTransparencySlider(control, x, y, width)
        W.MoveWidget(control, transparency, x, y, width or 270, "LEFT")
    end

    local function BindTransparencySlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = tonumber(v) or default or 0
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then
                widget._msuf2Title:SetText(labelFn(tonumber(value) or default or 0))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local bgAlpha = BindTransparencySlider(W.Slider(transparency, "", 0, 1, 0.05, transLeftW), "bgA", 0.85,
        function(v) return string.format("Background Alpha: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceTransparencySlider(bgAlpha, transLeftX, -130, transLeftW)

    local hpFg = BindTransparencySlider(W.Slider(transparency, "", 0.3, 1, 0.05, transRightW), "hpBarAlpha", 1,
        function(v) return string.format("HP Bar Foreground: %.0f%%", (tonumber(v) or 0) * 100) end)
    PlaceTransparencySlider(hpFg, transRightX, -82, transRightW)

    local preserveHP = W.ToggleAt(transparency, "Preserve HP color", transRightX, -128, transRightW)
    M.BindToggle(ctx, preserveHP,
        function() return Bool(CurrentScope(), "alphaPreserveHPColor", false) end,
        function(v) Set(CurrentScope(), "alphaPreserveHPColor", v and true or false, "visual") end)

    local textIgnore = W.ToggleAt(transparency, "Text ignores HP opacity", transLeftX, -184, transLeftW)
    M.BindToggle(ctx, textIgnore,
        function() return Bool(CurrentScope(), "hpTextIgnoreAlpha", true) end,
        function(v) Set(CurrentScope(), "hpTextIgnoreAlpha", v and true or false, "visual") end)

    local hpBg = W.Slider(transparency, "", 0, 1, 0.05, transRightW)
    M.BindSlider(ctx, hpBg,
        function()
            local conf = Conf(CurrentScope())
            return tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85
        end,
        function(v)
            local n = tonumber(v) or 0.85
            local conf = Conf(CurrentScope())
            if conf.hpBgAlpha == n then return end
            conf.hpBgAlpha = n
            QueueGF(CurrentScope(), "visual")
        end)
    local function RefreshHPBgLabel()
        if hpBg and hpBg._msuf2Title then
            local conf = Conf(CurrentScope())
            hpBg._msuf2Title:SetText(string.format("HP Background: %.0f%%", (tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85) * 100))
        end
    end
    hpBg:HookScript("OnValueChanged", function(_, value)
        if hpBg._msuf2Title then hpBg._msuf2Title:SetText(string.format("HP Background: %.0f%%", (tonumber(value) or 0) * 100)) end
    end)
    M.AddRefresher(ctx, RefreshHPBgLabel)
    RefreshHPBgLabel()
    PlaceTransparencySlider(hpBg, transRightX, -176, transRightW)

    local anchor = b:CollapsibleSection("anchor", "Anchoring", 220, false)

    local function PlaceAnchorDropdown(control, x, y, width)
        if not control then return end
        width = width or 200
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("LEFT")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local anchorTo = W.Dropdown(anchor, "Anchor To", GF_ANCHOR_TO, 200)
    PlaceAnchorDropdown(anchorTo, 14, -38, 200)
    M.BindDropdown(ctx, anchorTo,
        function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.anchorToFrame = (v == "FREE") and nil or v
            QueueGF(CurrentScope(), "rebuild")
        end)

    local anchorPoint = W.Dropdown(anchor, "Anchor Point", GF_ANCHOR_POINTS, 160)
    PlaceAnchorDropdown(anchorPoint, 254, -38, 160)
    BindScopeDropdown(ctx, anchorPoint, "anchorPoint", "CENTER", "rebuild")

    local customLabel = T.Font(anchor, "GameFontHighlightSmall", "Custom Anchor Frame", { 0.62, 0.74, 0.96, 1 })
    customLabel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 14, -104)
    customLabel:SetJustifyH("LEFT")

    local customBox = CreateFrame("EditBox", nil, anchor, "InputBoxTemplate")
    customBox:SetPoint("TOPLEFT", anchor, "TOPLEFT", 14, -126)
    customBox:SetSize(200, 22)
    customBox:SetAutoFocus(false)
    customBox:SetMaxLetters(100)
    customBox:SetJustifyH("LEFT")
    T.SkinEditBox(customBox)

    local function IsStandardAnchorTarget(value)
        return value == nil or value == "" or value == "FREE" or value == "player" or value == "target"
            or value == "targettarget" or value == "focus"
    end

    local function RefreshCustomAnchorBox()
        local value = Conf(CurrentScope()).anchorToFrame or ""
        if customBox and not customBox:HasFocus() then
            customBox:SetText(IsStandardAnchorTarget(value) and "" or value)
        end
    end

    customBox:SetScript("OnEnterPressed", function(self)
        local value = self:GetText() or ""
        local kind = CurrentScope()
        local function CommitCustomAnchor()
            local conf = Conf(kind)
            conf.anchorToFrame = (value ~= "") and value or nil
            QueueGF(kind, "rebuild")
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Set Group Anchor", "group:anchorCustom:" .. tostring(kind), CommitCustomAnchor)
        else
            CommitCustomAnchor()
        end
        self:ClearFocus()
    end)
    customBox:SetScript("OnEscapePressed", function(self)
        RefreshCustomAnchorBox()
        self:ClearFocus()
    end)
    customBox:SetScript("OnEditFocusLost", RefreshCustomAnchorBox)

    local pick = T.Button(anchor, "Pick", 50, 22)
    pick:SetPoint("LEFT", customBox, "RIGHT", 6, 0)
    pick._msuf2Label:ClearAllPoints()
    pick._msuf2Label:SetPoint("CENTER", pick, "CENTER", 0, 0)
    pick._msuf2Label:SetJustifyH("CENTER")
    pick:SetScript("OnClick", function()
        local overlay = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker() or nil
        if not overlay then return end
        overlay._onPick = function(frameName)
            local kind = CurrentScope()
            local function PickGroupAnchor()
                local conf = Conf(kind)
                conf.anchorToFrame = frameName
                customBox:SetText(frameName or "")
                QueueGF(kind, "rebuild")
            end
            if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Pick Group Anchor", "group:anchorPick:" .. tostring(kind), PickGroupAnchor)
            else
                PickGroupAnchor()
            end
        end
        overlay:Show()
    end)

    local clear = T.SkinDangerButton(T.Button(anchor, "Clear", 50, 22))
    clear:SetPoint("LEFT", pick, "RIGHT", 4, 0)
    clear._msuf2Label:ClearAllPoints()
    clear._msuf2Label:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear._msuf2Label:SetJustifyH("CENTER")
    clear:SetScript("OnClick", function()
        local conf = Conf(CurrentScope())
        conf.anchorToFrame = nil
        customBox:SetText("")
        QueueGF(CurrentScope(), "rebuild")
    end)

    M.AddRefresher(ctx, RefreshCustomAnchorBox)

    local tooltip = b:CollapsibleSection("tooltip", "Tooltip", 150, false)
    local tooltipW = tooltip._msuf2Width or b.width or 720
    local tooltipLeftX = 32
    local tooltipRightX = min(max(470, floor(tooltipW * 0.54)), max(380, tooltipW - 340))
    local tooltipLeftW = max(240, min(300, tooltipRightX - tooltipLeftX - 70))
    local tooltipRightW = max(200, min(260, tooltipW - tooltipRightX - 38))
    local refreshTooltipState
    local tooltipMode = W.Dropdown(tooltip, "Tooltip Mode", TOOLTIP_MODES, tooltipLeftW)
    W.MoveWidget(tooltipMode, tooltip, tooltipLeftX, -54, tooltipLeftW, "LEFT")
    M.BindDropdown(ctx, tooltipMode,
        function() return Val(CurrentScope(), "tooltipMode", "ALWAYS") end,
        function(v)
            Set(CurrentScope(), "tooltipMode", v or "ALWAYS", "visual")
            if refreshTooltipState then refreshTooltipState() end
        end)

    local tooltipModifier = BindScopeDropdown(ctx, W.Dropdown(tooltip, "Modifier Key", TOOLTIP_MODIFIERS, tooltipRightW), "tooltipModifier", "ALT", "visual")
    W.MoveWidget(tooltipModifier, tooltip, tooltipRightX, -54, tooltipRightW, "LEFT")
    refreshTooltipState = function()
        SetOptionEnabled(tooltipModifier, Val(CurrentScope(), "tooltipMode", "ALWAYS") == "MODIFIER")
    end
    M.AddRefresher(ctx, refreshTooltipState)
    refreshTooltipState()

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 13 })
