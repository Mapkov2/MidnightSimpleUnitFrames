local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList

local SCOPE_VALUES, GROWTH_VALUES, BLIZZARD_FALLBACK_VALUES, SORT_MODES, GF_ANCHOR_TO, GF_ANCHOR_POINTS = M.PickDefaults(GP, [[SCOPE_VALUES GROWTH_VALUES BLIZZARD_FALLBACK_VALUES SORT_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS]])
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, BindScopeSlider, BindScopeDropdown, BuildGrowthDirectionTiles, BuildRoleOrderRows, SetOptionEnabled, FinalizeScopePage, SetSectionHeaderStatus, SetSectionBadges, OnOffBadge, BadgeNumber, OptionText, CreateSectionNotice = M.Pick(GP, [[GF Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle BindScopeSlider BindScopeDropdown BuildGrowthDirectionTiles BuildRoleOrderRows SetOptionEnabled FinalizeScopePage SetSectionHeaderStatus SetSectionBadges OnOffBadge BadgeNumber OptionText CreateSectionNotice]])
SetSectionBadges = SetSectionBadges or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or M.OptionText


local function ScopeLabel()
    local scope = CurrentScope() or "party"
    for i = 1, #SCOPE_VALUES do
        local info = SCOPE_VALUES[i]
        if info and info.value == scope then return info.text or scope end
    end
    return tostring(scope)
end

local function CurrentEditFocusKey()
    local scope = CurrentScope() or "party"
    return "gf_" .. tostring(scope)
end

local function AttachGroupFocus(widget, component)
    if W.AttachEditFocus then
        W.AttachEditFocus(widget, CurrentEditFocusKey, component or "layout", nil, { source = "menu2-group" })
    end
    return widget
end

local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local general = b:CollapsibleSection("general", "Frame Basics", 430, false)
    local generalW = general._msuf2Width or b.width or 720
    local generalLeftX = 32
    local generalRightX = min(max(430, floor(generalW * 0.52)), max(360, generalW - 360))
    local generalLeftW = max(250, generalRightX - generalLeftX - 42)
    local generalRightW = max(250, generalW - generalRightX - 32)
    local generalLeftToggleW = max(80, generalLeftW - 34)
    local generalRightToggleW = max(80, generalRightW - 34)
    local offlineSliderW = max(320, min(520, generalW - generalLeftX - 170))

    W.LabelAt(general, "Frame", generalLeftX, -38, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(general, "Behavior", generalRightX, -38, generalRightW, "GameFontNormalSmall", T.colors.accent)
    local enableGroup = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Use MSUF group frames", generalLeftX, -64, generalLeftW), "layout"), "enabled", false, "rebuild")
    enableGroup._msuf2GroupFrameGateAlwaysEnabled = true
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Show player", generalLeftX, -94, generalLeftToggleW), "layout"), "showPlayer", true, "rebuild")
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Show while solo", generalLeftX, -124, generalLeftToggleW), "layout"), "showSolo", false, "rebuild")
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Smooth health fill", generalRightX, -64, generalRightToggleW), "bars"), "smoothFill", true, "visual")
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Reverse fill direction", generalRightX, -94, generalRightToggleW), "bars"), "reverseFill", false, "visual")
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Hide during client scene", generalRightX, -124, generalRightToggleW), "layout"), "hideInClientScene", true, "visual")
    BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Click casting / Clique", generalRightX, -154, generalRightToggleW), "layout"), "clickCastEnabled", true, "rebuild")

    local fallbackModeW = min(260, generalLeftW)
    local fallbackMode = W.Dropdown(general, "If this switch is off", BLIZZARD_FALLBACK_VALUES, fallbackModeW)
    fallbackMode._msuf2GroupFrameGateAlwaysEnabled = true
    W.MoveWidget(fallbackMode, general, generalLeftX, -196, fallbackModeW, "LEFT")
    AttachGroupFocus(fallbackMode, "layout")
    BindScopeDropdown(ctx, fallbackMode, "blizzardFallbackMode", "AUTO", "rebuild")

    local fallbackHelp = W.Text(general, "Blizzard default is the simple off-state when no MSUF group-frame scope is active. If any MSUF group frames are on, Auto keeps Blizzard group frames hidden to avoid duplicates.", generalRightX, -184, generalRightW, T.colors.muted)
    if fallbackHelp and fallbackHelp.SetWordWrap then fallbackHelp:SetWordWrap(true) end

    W.DividerAt(general, -256, generalLeftX, 32)
    W.LabelAt(general, "Offline Members", generalLeftX, -274, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    local hideOfflineEnabled = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Offline Members", generalLeftX, -300, generalLeftW), "layout"), "hideOfflineEnabled", false, "visual")
    local hideOfflineCombat = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Hide offline in combat", generalRightX, -300, generalRightToggleW), "layout"), "hideOfflineInCombat", false, "visual")
    local hideOffline = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(general, "Hide offline after", 0, 120, 1, offlineSliderW), "layout"), "hideOfflineDelay", 0, "visual")
    W.MoveWidget(hideOffline, general, generalLeftX, -334, offlineSliderW, "LEFT")
    local generalNotice, generalNoticeButton
    if type(CreateSectionNotice) == "function" then
        local _
        generalNotice, _, generalNoticeButton = CreateSectionNotice(general, -374, "Enable Scope", 104)
    end
    if generalNoticeButton then
        generalNoticeButton:SetScript("OnClick", function()
            Set(CurrentScope(), "enabled", true, "rebuild")
        end)
    end

    local function RefreshHideOfflineState()
        local enabled = Bool(CurrentScope(), "hideOfflineEnabled", false)
        local scopeEnabled = Bool(CurrentScope(), "enabled", false)
        SetOptionEnabled(hideOfflineCombat, enabled)
        SetOptionEnabled(hideOffline, enabled)
        SetSectionBadges(general, {
            OnOffBadge(scopeEnabled, "Enabled", "Disabled"),
            { text = Bool(CurrentScope(), "showPlayer", true) and "Player shown" or "Player hidden", kind = Bool(CurrentScope(), "showPlayer", true) and "info" or "muted" },
            { text = enabled and ("Offline " .. BadgeNumber(Num(CurrentScope(), "hideOfflineDelay", 0)) .. "s") or "Offline visible", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then
            if not scopeEnabled then
                SetSectionHeaderStatus(general, {
                    hint = "scope disabled",
                    hintColor = { 0.90, 0.84, 0.76, 1 },
                    bg = { 0.105, 0.082, 0.052, 0.44 },
                    arrowColor = { 0.88, 0.62, 0.22, 1 },
                })
            else
                SetSectionHeaderStatus(general, nil)
            end
        end
        if generalNotice then
            local scopeEnabled = Bool(CurrentScope(), "enabled", false)
            generalNotice:SetShown(not scopeEnabled)
            if not scopeEnabled then
                local mode = Val(CurrentScope(), "blizzardFallbackMode", "AUTO")
                local anyMSUF = Bool("party", "enabled", false) or Bool("raid", "enabled", false) or Bool("mythicraid", "enabled", false)
                local behavior = anyMSUF and "Blizzard frames stay hidden because another MSUF group scope is on." or "Blizzard decides normally."
                if mode == "SHOW" then
                    behavior = "Blizzard frames are forced visible."
                elseif mode == "NONE" then
                    behavior = "MSUF and Blizzard frames stay hidden."
                end
                generalNotice:SetMessage(ScopeLabel() .. " group frames are disabled. " .. behavior, "warning")
            end
        end
    end
    M.AddRefresher(ctx, RefreshHideOfflineState)
    RefreshHideOfflineState()
    M.SetCollapsibleRefreshState(general, RefreshHideOfflineState)

    local advancedLayout = b:CollapsibleSection("layout_advanced", "Geometry", 430, false)
    local advancedLayoutW = advancedLayout._msuf2Width or b.width or 720
    local layoutGap = 16
    local advancedLeftX = 20
    local advancedInnerW = max(320, advancedLayoutW - 40)
    local advancedLeftW = floor((advancedInnerW - layoutGap) * 0.52)
    local advancedRightX = advancedLeftX + advancedLeftW + layoutGap
    local advancedRightW = advancedInnerW - advancedLeftW - layoutGap
    local layoutSliderW = max(180, min(360, advancedLeftW - 64))

    local sizeCard = W.ControlCard(advancedLayout, "Size", "Dimensions and spacing for each group member.", advancedLeftX, -38, advancedLeftW, 188)
    local gridCard = W.ControlCard(advancedLayout, "Columns", "Column behavior for raid-like scopes.", advancedLeftX, -244, advancedLeftW, 158)
    local growthCard = W.ControlCard(advancedLayout, "Growth", "How new members fill the group frame.", advancedRightX, -38, advancedRightW, 188)

    local widthSlider = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(sizeCard, "Width", 40, 300, 1, layoutSliderW), "layout"), "width", 120, "rebuild")
    local heightSlider = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(sizeCard, "Height", 16, 120, 1, layoutSliderW), "layout"), "height", 40, "rebuild")
    local spacingSlider = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(sizeCard, "Spacing", 0, 20, 1, layoutSliderW), "layout"), "spacing", 1, "rebuild")
    W.MoveWidget(widthSlider, sizeCard, 16, -66, layoutSliderW, "LEFT")
    W.MoveWidget(heightSlider, sizeCard, 16, -114, layoutSliderW, "LEFT")
    W.MoveWidget(spacingSlider, sizeCard, 16, -162, layoutSliderW, "LEFT")

    BuildGrowthDirectionTiles(ctx, growthCard, { x = 16, y = -68, tileWidth = 64, tileHeight = 64, gap = 8, advanceCursor = false })

    local unitsSlider = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(gridCard, "Units per column", 1, 40, 1, layoutSliderW), "layout"), "unitsPerColumn", 5, "rebuild")
    local maxColumnsSlider = BindScopeSlider(ctx, AttachGroupFocus(W.Slider(gridCard, "Max columns", 1, 8, 1, layoutSliderW), "layout"), "maxColumns", 8, "rebuild")
    local preserveRaidGroups = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(gridCard, "Preserve raid groups", 16, -138, advancedLeftW - 32), "layout"), "preserveRaidGroups", false, "rebuild")
    W.MoveWidget(unitsSlider, gridCard, 16, -62, layoutSliderW, "LEFT")
    W.MoveWidget(maxColumnsSlider, gridCard, 16, -108, layoutSliderW, "LEFT")
    local function RefreshRaidGroupLayoutState()
        SetOptionEnabled(preserveRaidGroups, CurrentScope() ~= "party")
        SetSectionBadges(advancedLayout, {
            { text = BadgeNumber(Num(CurrentScope(), "width", 120)) .. "x" .. BadgeNumber(Num(CurrentScope(), "height", 40)), kind = "info" },
            { text = OptionText(GROWTH_VALUES, Val(CurrentScope(), "growth", "DOWN"), "Down"), kind = "accent" },
            { text = "Grid " .. BadgeNumber(Num(CurrentScope(), "unitsPerColumn", 5)) .. "/" .. BadgeNumber(Num(CurrentScope(), "maxColumns", 8)), kind = CurrentScope() == "party" and "muted" or "info" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(advancedLayout, nil) end
    end
    M.AddRefresher(ctx, RefreshRaidGroupLayoutState)
    RefreshRaidGroupLayoutState()
    M.SetCollapsibleRefreshState(advancedLayout, RefreshRaidGroupLayoutState)

    local sorting = b:CollapsibleSection("sorting", "Sorting", 236, false)
    local sortingW = sorting._msuf2Width or b.width or 720
    local sortingGap = 16
    local sortingLeftX = 20
    local sortingInnerW = max(320, sortingW - 40)
    local sortingLeftW = floor((sortingInnerW - sortingGap) * 0.52)
    local sortingRightX = sortingLeftX + sortingLeftW + sortingGap
    local sortingRightW = sortingInnerW - sortingLeftW - sortingGap
    local sortCard = W.ControlCard(sorting, "Sort mode", "Controls how group members are ordered.", sortingLeftX, -38, sortingLeftW, 174)
    local roleCard = W.ControlCard(sorting, "Role Priority", "Drag rows with mouse to reorder.", sortingRightX, -38, sortingRightW, 174)
    local sortMode = W.Dropdown(sortCard, "Sort Mode", SORT_MODES, min(260, sortingLeftW - 32))
    W.MoveWidget(sortMode, sortCard, 16, -62, min(260, sortingLeftW - 32), "LEFT")
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
    local roleSort = W.ToggleAt(sortCard, "Sort by Role", 16, -110, sortingLeftW - 32)
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
    local playerFirst = BindScopeToggle(ctx, W.ToggleAt(sortCard, "Player first in role", 16, -144, sortingLeftW - 32), "playerFirstInRole", false, "rebuild")
    local roleRows = BuildRoleOrderRows(ctx, roleCard, {
        x = 16,
        y = -66,
        width = min(250, sortingRightW - 32),
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
        SetSectionBadges(sorting, {
            { text = OptionText(SORT_MODES, currentMode, "Index"), kind = "info" },
            { text = enabled and "Role order" or "Simple order", kind = enabled and "accent" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(sorting, nil) end
    end
    M.AddRefresher(ctx, refreshSortingControls)
    refreshSortingControls()
    M.SetCollapsibleRefreshState(sorting, refreshSortingControls)

    local scale = b:CollapsibleSection("scaling", "Frame Scaling", 380, false)
    local scaleW = scale._msuf2Width or b.width or 720
    local scaleGap = 16
    local scaleLeftX = 20
    local scaleInnerW = max(320, scaleW - 40)
    local scaleLeftW = floor((scaleInnerW - scaleGap) * 0.48)
    local scaleRightX = scaleLeftX + scaleLeftW + scaleGap
    local scaleRightW = scaleInnerW - scaleLeftW - scaleGap
    local scaleModeCard = W.ControlCard(scale, "Frame scaling", "Scales frame size, fonts, and icons proportionally.", scaleLeftX, -38, scaleLeftW, 128)
    local manualCard = W.ControlCard(scale, "Manual Scale", "Buff/debuff positions stay relative to their anchors.", scaleLeftX, -184, scaleLeftW, 144)
    local autoCard = W.ControlCard(scale, "Auto Breakpoints", "Automatically scale by group size.", scaleRightX, -38, scaleRightW, 290)
    local RefreshScalingState
    M._msuf2LastGroupScaleMode = M._msuf2LastGroupScaleMode or {}
    local scaleEnabled = W.SwitchAt(scaleModeCard, "Frame scaling", scaleLeftW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, scaleEnabled,
        function() return Val(CurrentScope(), "frameScaleMode", "off") ~= "off" end,
        function(v)
            local scopeKey = CurrentScope()
            if v then
                Set(scopeKey, "frameScaleMode", M._msuf2LastGroupScaleMode[scopeKey] or "manual", "rebuild")
            else
                local mode = Val(scopeKey, "frameScaleMode", "off")
                if mode == "manual" or mode == "auto" then M._msuf2LastGroupScaleMode[scopeKey] = mode end
                Set(scopeKey, "frameScaleMode", "off", "rebuild")
            end
            if RefreshScalingState then RefreshScalingState() end
        end)

    local scaleMode = W.Segment(scaleModeCard, "Scale Mode", VT("manual", "Manual", "auto", "Auto"), min(220, scaleLeftW - 32))
    W.MoveWidget(scaleMode, scaleModeCard, 16, -72, min(220, scaleLeftW - 32))
    M.BindSegment(ctx, scaleMode,
        function()
            local mode = Val(CurrentScope(), "frameScaleMode", "off")
            return mode == "auto" and "auto" or "manual"
        end,
        function(v)
            local scopeKey = CurrentScope()
            local mode = (v == "auto") and "auto" or "manual"
            M._msuf2LastGroupScaleMode[scopeKey] = mode
            Set(scopeKey, "frameScaleMode", mode, "rebuild")
            if RefreshScalingState then RefreshScalingState() end
        end)

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

    local manualScale = BindScaleSlider(W.Slider(manualCard, "", 50, 150, 5, scaleLeftW), "frameScaleManual", 100,
        function(v) return string.format("Manual Scale: %d%%", v) end)
    W.MoveWidget(manualScale, manualCard, 16, -64, scaleLeftW - 58, "LEFT")

    local autoLabel = autoCard and autoCard.title

    local scaleAt10 = BindScaleSlider(W.Slider(autoCard, "", 50, 100, 5, scaleRightW), "scaleAt10", 100,
        function(v) return string.format("1-10 players: %d%%", v) end)
    W.MoveWidget(scaleAt10, autoCard, 16, -66, scaleRightW - 58, "LEFT")
    local scaleAt20 = BindScaleSlider(W.Slider(autoCard, "", 50, 100, 5, scaleRightW), "scaleAt20", 85,
        function(v) return string.format("11-20 players: %d%%", v) end)
    W.MoveWidget(scaleAt20, autoCard, 16, -120, scaleRightW - 58, "LEFT")
    local scaleAt25 = BindScaleSlider(W.Slider(autoCard, "", 50, 100, 5, scaleRightW), "scaleAt25", 80,
        function(v) return string.format("21-25 players: %d%%", v) end)
    W.MoveWidget(scaleAt25, autoCard, 16, -174, scaleRightW - 58, "LEFT")
    local scaleOver25 = BindScaleSlider(W.Slider(autoCard, "", 50, 100, 5, scaleRightW), "scaleOver25", 70,
        function(v) return string.format("26+ players: %d%%", v) end)
    W.MoveWidget(scaleOver25, autoCard, 16, -228, scaleRightW - 58, "LEFT")

    local scaleHint = manualCard and manualCard.subtitle
    if scaleHint.SetWordWrap then scaleHint:SetWordWrap(true) end

    RefreshScalingState = function()
        local mode = Val(CurrentScope(), "frameScaleMode", "off")
        local scalingOn = mode ~= "off"
        local manualOn = mode == "manual"
        local autoOn = mode == "auto"
        SetOptionEnabled(scaleEnabled, true)
        SetOptionEnabled(scaleMode, scalingOn)
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
        SetSectionBadges(scale, {
            OnOffBadge(scalingOn, "Scaling", "Off"),
            { text = manualOn and ("Manual " .. BadgeNumber(Num(CurrentScope(), "frameScaleManual", 100)) .. "%") or (autoOn and "Auto breakpoints" or "Native size"), kind = scalingOn and "info" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(scale, nil) end
    end
    M.AddRefresher(ctx, RefreshScalingState)
    RefreshScalingState()
    M.SetCollapsibleRefreshState(scale, RefreshScalingState)

    -- Unified, simple transparency: HP bar fill slider, background slider, background
    -- colour, and a toggle that keeps text + portrait opaque while bars fade. Range fade
    -- multiplies these at runtime. All coldpath.
    local transparency = b:CollapsibleSection("border", "Transparency", 200, false)
    local transparencyW = transparency._msuf2Width or b.width or 720
    local transGap = 16
    local transLeftX = 20
    local transInnerW = max(320, transparencyW - 40)
    local transLeftW = floor((transInnerW - transGap) * 0.5)
    local transRightX = transLeftX + transLeftW + transGap
    local transRightW = transInnerW - transLeftW - transGap

    local AlphaLabel = M.AlphaLabel
    local Clamp01 = M.Clamp01

    local opacityCard = W.ControlCard(transparency, "Opacity", "Fade the health bar and its background.", transLeftX, -38, transLeftW, 150)
    local optionsCard = W.ControlCard(transparency, "Background & Options", "Background colour and readability.", transRightX, -38, transRightW, 150)

    local function BindAlphaSlider(widget, key, default, label)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = Clamp01(v, default or 0)
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        return M.BindSliderLiveLabel(ctx, widget, function() return Num(CurrentScope(), key, default) end, function(value) return AlphaLabel(label, tonumber(value) or default or 0) end, true)
    end

    local hpAlpha = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), "hpBarAlpha", 1, "HP Bar")
    W.MoveWidget(hpAlpha, opacityCard, 16, -62, transLeftW - 58, "LEFT")

    local bgAlpha = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), "hpBgAlpha", 0.85, "Background")
    W.MoveWidget(bgAlpha, opacityCard, 16, -116, transLeftW - 58, "LEFT")

    local bgColor = W.Color(optionsCard, "Background Color")
    if bgColor._msuf2Title then
        bgColor._msuf2Title:ClearAllPoints()
        bgColor._msuf2Title:SetPoint("TOPLEFT", optionsCard, "TOPLEFT", 16, -62)
        bgColor._msuf2Title:SetWidth(120)
        bgColor._msuf2Title:SetJustifyH("LEFT")
    end
    bgColor:ClearAllPoints()
    bgColor:SetPoint("TOPLEFT", optionsCard, "TOPLEFT", 154, -60)
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

    local exclude = W.ToggleAt(optionsCard, "Keep text + portrait visible", 16, -100, transRightW - 32)
    M.BindToggle(ctx, exclude,
        function() return Bool(CurrentScope(), "alphaExcludeTextPortrait", false) end,
        function(v) Set(CurrentScope(), "alphaExcludeTextPortrait", v and true or false, "visual") end)

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

    local customLabel = T.Font(anchor, "GameFontHighlightSmall", M.Tr("Custom Anchor Frame"), { 0.62, 0.74, 0.96, 1 })
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
            or value == "targettarget" or value == "focustarget" or value == "focus"
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
    T.CenterButtonLabel(pick)
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
    T.CenterButtonLabel(clear)
    clear:SetScript("OnClick", function()
        local conf = Conf(CurrentScope())
        conf.anchorToFrame = nil
        customBox:SetText("")
        QueueGF(CurrentScope(), "rebuild")
    end)

    M.AddRefresher(ctx, RefreshCustomAnchorBox)
    local function RefreshAnchorHeader()
        if type(SetSectionHeaderStatus) ~= "function" then return end
        SetSectionBadges(anchor, {
            { text = OptionText(GF_ANCHOR_TO, Conf(CurrentScope()).anchorToFrame or "FREE", "Free"), kind = "info" },
            { text = OptionText(GF_ANCHOR_POINTS, Val(CurrentScope(), "anchorPoint", "CENTER"), "CENTER"), kind = "accent" },
        })
        SetSectionHeaderStatus(anchor, nil)
    end
    M.AddRefresher(ctx, RefreshAnchorHeader)
    RefreshAnchorHeader()
    M.SetCollapsibleRefreshState(anchor, RefreshAnchorHeader)

    FinalizeScopePage(ctx, b)
end

M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 18 })
