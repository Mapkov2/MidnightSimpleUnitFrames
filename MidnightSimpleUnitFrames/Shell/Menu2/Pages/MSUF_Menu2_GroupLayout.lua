-- Menu2 Group Layout page: builds secure-header layout controls for party and raid frames.
-- UI writes must delegate rebuild/defer behavior to GroupFrame runtime helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local SCOPE_VALUES, GROWTH_VALUES, BLIZZARD_FALLBACK_VALUES, SORT_MODES, GF_ANCHOR_TO, GF_ANCHOR_POINTS = M.PickDefaults(GP, [[SCOPE_VALUES GROWTH_VALUES BLIZZARD_FALLBACK_VALUES SORT_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS]])
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, ScopeDropdown, ScopeSlider, BuildGrowthDirectionTiles, BuildRoleOrderRows, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge, BadgeNumber, OptionText, CreateSectionNotice, ControlMeta, RegisterControl = M.Pick(GP, [[GF Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle ScopeDropdown ScopeSlider BuildGrowthDirectionTiles BuildRoleOrderRows SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus TrackSectionRefresh OnOffBadge BadgeNumber OptionText CreateSectionNotice ControlMeta RegisterControl]])
local SIMPLE_TEXTURES = GP.SIMPLE_TEXTURES or function() return {} end
SetSectionBadgesAndStatus = SetSectionBadgesAndStatus or M.Noop
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
    W.AttachGroupEditFocus(widget, CurrentEditFocusKey, component or "layout")
    return widget
end
local function OpenGroupFrameColors()
    _G.MSUF_EM2_MenuFocusRequest = {
        pageKey = "opt_colors",
        sectionId = "colors_group_frames",
        explicit = true,
        consumed = false,
        source = "group-frame-basics",
        changedAt = GetTime and GetTime() or 0,
    }
    if M.SelectPage and M.SelectPage("opt_colors") == false then
        _G.MSUF_EM2_MenuFocusRequest = nil
    end
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
    local openColors = T.Button(general, "Colors", 112, 22)
    openColors:SetPoint("TOPRIGHT", general, "TOPRIGHT", -20, -8)
    if T.CenterButtonLabel then T.CenterButtonLabel(openColors) end
    if M.AddTooltip then
        M.AddTooltip(openColors, "Group Frame Colors", "Open Colors > Group Frame Colors for shared Party, Raid and Mythic Raid colors.", { hook = true })
    end
    openColors:SetScript("OnClick", OpenGroupFrameColors)
    RegisterControl(openColors, ctx, "navigation.group_colors", "Group Frame Colors", "button", "navigation", { navigationKey = "opt_colors" })
    W.LabelAt(general, "Frame", generalLeftX, -38, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(general, "Behavior", generalRightX, -38, generalRightW, "GameFontNormalSmall", T.colors.accent)
    local enableGroup = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Use MSUF group frames", generalLeftX, -64, generalLeftW), "layout"), "enabled", false, "rebuild")
    enableGroup._msuf2GroupFrameGateAlwaysEnabled = true
    M.BuildControlSpecs({
        { "Show player", generalLeftX, -94, generalLeftToggleW, "layout", "showPlayer", true, "rebuild" },
        { "Show while solo", generalLeftX, -124, generalLeftToggleW, "layout", "showSolo", false, "rebuild" },
        { "Hide in Housing", generalLeftX, -154, generalLeftToggleW, "layout", "hideInHousing", false, "visual" },
        { "Smooth health fill", generalRightX, -64, generalRightToggleW, "bars", "smoothFill", true, "visual" },
        { "Reverse fill direction", generalRightX, -94, generalRightToggleW, "bars", "reverseFill", false, "visual" },
        { "Hide during client scene", generalRightX, -124, generalRightToggleW, "layout", "hideInClientScene", true, "visual" },
        { "Click casting / Clique", generalRightX, -154, generalRightToggleW, "layout", "clickCastEnabled", true, "rebuild" },
    }, { ["*"] = function(s) return BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, s[1], s[2], s[3], s[4]), s[5]), s[6], s[7], s[8]) end })
    local fallbackModeW = min(260, generalLeftW)
    local fallbackMode = ScopeDropdown(ctx, general, "If this switch is off", BLIZZARD_FALLBACK_VALUES, fallbackModeW, "blizzardFallbackMode", "AUTO", "rebuild", generalLeftX, -196, fallbackModeW)
    fallbackMode._msuf2GroupFrameGateAlwaysEnabled = true
    AttachGroupFocus(fallbackMode, "layout")
    local fallbackHelp = W.Text(general, "Blizzard default is the simple off-state when no MSUF group-frame scope is active. If any MSUF group frames are on, Auto keeps Blizzard group frames hidden to avoid duplicates.", generalRightX, -184, generalRightW, T.colors.muted)
    if fallbackHelp and fallbackHelp.SetWordWrap then fallbackHelp:SetWordWrap(true) end
    W.DividerAt(general, -256, generalLeftX, 32)
    W.LabelAt(general, "Offline Members", generalLeftX, -274, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    local hideOfflineEnabled = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Offline Members", generalLeftX, -300, generalLeftW), "layout"), "hideOfflineEnabled", false, "visual")
    local hideOfflineCombat = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Hide offline in combat", generalRightX, -300, generalRightToggleW), "layout"), "hideOfflineInCombat", false, "visual")
    local hideOffline = AttachGroupFocus(ScopeSlider(ctx, general, "Hide offline after", 0, 120, 1, offlineSliderW, "hideOfflineDelay", 0, "visual", generalLeftX, -334, offlineSliderW, "LEFT"), "layout")
    local hideOfflineControls = { hideOfflineCombat, hideOffline }
    local generalNotice, generalNoticeButton
    if type(CreateSectionNotice) == "function" then
        local _
        generalNotice, _, generalNoticeButton = CreateSectionNotice(general, -374, "Enable Scope", 104)
    end
    if generalNoticeButton then
        RegisterControl(generalNoticeButton, ctx, "scope.enable_now", "Enable Scope", "button", "action")
        generalNoticeButton:SetScript("OnClick", function()
            Set(CurrentScope(), "enabled", true, "rebuild")
        end)
    end
    local function RefreshHideOfflineState()
        local enabled = Bool(CurrentScope(), "hideOfflineEnabled", false)
        local scopeEnabled = Bool(CurrentScope(), "enabled", false)
        SetOptionsEnabled(hideOfflineControls, enabled)
        local status
        if not scopeEnabled then
            status = {
                hint = "scope disabled",
                hintColor = { 0.90, 0.84, 0.76, 1 },
                bg = { 0.105, 0.082, 0.052, 0.44 },
                arrowColor = { 0.88, 0.62, 0.22, 1 },
            }
        end
        SetSectionBadgesAndStatus(general, {
            OnOffBadge(scopeEnabled, "Enabled", "Disabled"),
            { text = Bool(CurrentScope(), "showPlayer", true) and "Player shown" or "Player hidden", kind = Bool(CurrentScope(), "showPlayer", true) and "info" or "muted" },
            { text = enabled and ("Offline " .. BadgeNumber(Num(CurrentScope(), "hideOfflineDelay", 0)) .. "s") or "Offline visible", kind = enabled and "accent" or "muted" },
        }, status)
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
    TrackSectionRefresh(ctx, general, RefreshHideOfflineState)

    -- Keep Group Frame opacity controls visually aligned with the Unitframe
    -- Transparency section while binding them to the currently selected scope.
    local transparency = b:CollapsibleSection("transparency", "Transparency", nil, false)
    local transparencyW = transparency._msuf2Width or b.width or 720
    local transparencyGap = 16
    local transparencyLeftX = 20
    local transparencyInnerW = max(320, transparencyW - 40)
    local transparencyCardW = floor((transparencyInnerW - transparencyGap) / 2)
    local transparencyRightX = transparencyLeftX + transparencyCardW + transparencyGap
    local transparencyRightW = transparencyInnerW - transparencyCardW - transparencyGap
    local transparencyCardH = 180
    local _, transparencyCardY = W.NextRow(transparency, transparencyCardH)
    local healthOpacityCard = W.ControlCard(transparency, "Health Bar", nil, transparencyLeftX, transparencyCardY, transparencyCardW, transparencyCardH)
    local opacityOptionsCard = W.ControlCard(transparency, "Options", nil, transparencyRightX, transparencyCardY, transparencyRightW, transparencyCardH)
    local function AddAlphaSlider(parent, width, spec)
        local slider = W.Slider(parent, spec.label, 0, 1, 0.05, width)
        M.UsePercentInput(slider)
        M.BindNumberWidget(ctx, slider,
            function() return Num(CurrentScope(), spec.key, spec.default) end,
            function(value) Set(CurrentScope(), spec.key, tonumber(value) or spec.default, "visual") end,
            spec.default,
            ControlMeta(ctx, "field." .. tostring(spec.key)))
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
        return AttachGroupFocus(slider, "bars")
    end
    AddAlphaSlider(healthOpacityCard, transparencyCardW, { label = "Foreground", key = "hpBarAlpha", default = 1, y = -54 })
    AddAlphaSlider(healthOpacityCard, transparencyCardW, { label = "Background", key = "hpBgAlpha", default = 0.85, y = -112 })
    BindScopeToggle(ctx,
        AttachGroupFocus(W.ToggleAt(opacityOptionsCard, "Keep text + portrait visible", 16, -62, transparencyRightW - 32), "bars"),
        "alphaExcludeTextPortrait", false, "visual", "field.alphaExcludeTextPortrait")
    if b.FinishSection then b:FinishSection(transparency, 48) end

    local bars = b:CollapsibleSection("bars", "Bars", nil, false)
    local barsW = bars._msuf2Width or b.width or 720
    local barsGap = 16
    local barsLeftX = 20
    local barsInnerW = max(320, barsW - 40)
    local barsLeftW = floor((barsInnerW - barsGap) / 2)
    local barsRightX = barsLeftX + barsLeftW + barsGap
    local barsRightW = barsInnerW - barsLeftW - barsGap
    local _, barsCardY = W.NextRow(bars, 120)
    local foregroundTextureCard = W.ControlCard(bars, "Foreground", nil, barsLeftX, barsCardY, barsLeftW, 120)
    local backgroundTextureCard = W.ControlCard(bars, "Background", nil, barsRightX, barsCardY, barsRightW, 120)
    local textureValues = SIMPLE_TEXTURES()
    AttachGroupFocus(ScopeDropdown(ctx, foregroundTextureCard, "Texture", textureValues, min(290, barsLeftW - 32),
        "barTexture", "", "visual", 16, -64, min(290, barsLeftW - 32), "LEFT", "field.barTexture"), "bars")
    AttachGroupFocus(ScopeDropdown(ctx, backgroundTextureCard, "Texture", textureValues, min(290, barsRightW - 32),
        "barBgTexture", "", "visual", 16, -64, min(290, barsRightW - 32), "LEFT", "field.barBgTexture"), "bars")
    if b.FinishSection then b:FinishSection(bars, 36) end

    local advancedLayout = b:CollapsibleSection("layout_advanced", "Geometry", 448, false)
    local advancedLayoutW = advancedLayout._msuf2Width or b.width or 720
    local layoutGap = 16
    local advancedLeftX = 20
    local advancedInnerW = max(320, advancedLayoutW - 40)
    local advancedLeftW = floor((advancedInnerW - layoutGap) * 0.52)
    local advancedRightX = advancedLeftX + advancedLeftW + layoutGap
    local advancedRightW = advancedInnerW - advancedLeftW - layoutGap
    local layoutSliderW = max(180, min(360, advancedLeftW - 64))
    local sizeCard = W.ControlCard(advancedLayout, "Size", nil, advancedLeftX, -38, advancedLeftW, 188)
    local gridCard = W.ControlCard(advancedLayout, nil, nil, advancedLeftX, -244, advancedLeftW, 180)
    local growthCard = W.ControlCard(advancedLayout, "Growth", nil, advancedRightX, -38, advancedRightW, 188)
    local function LayoutSlider(parent, label, minValue, maxValue, step, key, defaultValue, y)
        return AttachGroupFocus(ScopeSlider(ctx, parent, label, minValue, maxValue, step, layoutSliderW, key, defaultValue, "rebuild", 16, y, layoutSliderW, "LEFT"), "layout")
    end
    LayoutSlider(sizeCard, "Width", 40, 300, 1, "width", 120, -66)
    LayoutSlider(sizeCard, "Height", 16, 120, 1, "height", 40, -114)
    LayoutSlider(sizeCard, "Spacing", 0, 20, 1, "spacing", 1, -162)
    BuildGrowthDirectionTiles(ctx, growthCard, { x = 16, y = -68, tileWidth = 64, tileHeight = 64, gap = 8, advanceCursor = false })
    LayoutSlider(gridCard, "Units per column", 1, 40, 1, "unitsPerColumn", 5, -28)
    LayoutSlider(gridCard, "Max columns", 1, 8, 1, "maxColumns", 8, -86)
    local preserveRaidGroups = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(gridCard, "Preserve raid groups", 16, -144, advancedLeftW - 32), "layout"), "preserveRaidGroups", false, "rebuild")
    local function RefreshRaidGroupLayoutState()
        SetOptionEnabled(preserveRaidGroups, CurrentScope() ~= "party")
        SetSectionBadgesAndStatus(advancedLayout, {
            { text = BadgeNumber(Num(CurrentScope(), "width", 120)) .. "x" .. BadgeNumber(Num(CurrentScope(), "height", 40)), kind = "info" },
            { text = OptionText(GROWTH_VALUES, Val(CurrentScope(), "growth", "DOWN"), "Down"), kind = "accent" },
            { text = "Grid " .. BadgeNumber(Num(CurrentScope(), "unitsPerColumn", 5)) .. "/" .. BadgeNumber(Num(CurrentScope(), "maxColumns", 8)), kind = CurrentScope() == "party" and "muted" or "info" },
        })
    end
    TrackSectionRefresh(ctx, advancedLayout, RefreshRaidGroupLayoutState)
    local sorting = b:CollapsibleSection("sorting", "Sorting", 236, false)
    local sortingW = sorting._msuf2Width or b.width or 720
    local sortingGap = 16
    local sortingLeftX = 20
    local sortingInnerW = max(320, sortingW - 40)
    local sortingLeftW = floor((sortingInnerW - sortingGap) * 0.52)
    local sortingRightX = sortingLeftX + sortingLeftW + sortingGap
    local sortingRightW = sortingInnerW - sortingLeftW - sortingGap
    local sortCard = W.ControlCard(sorting, "Sort mode", nil, sortingLeftX, -38, sortingLeftW, 174)
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
    M.BindDropdownWidget(ctx, sortMode,
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
        end,
        ControlMeta(ctx, "field.sortMode"))
    local roleSort = W.ToggleAt(sortCard, "Sort by Role", 16, -110, sortingLeftW - 32)
    M.BindBoolWidget(ctx, roleSort,
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
        end,
        ControlMeta(ctx, "field.sortByRole"))
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
        SetSectionBadgesAndStatus(sorting, {
            { text = OptionText(SORT_MODES, currentMode, "Index"), kind = "info" },
            { text = enabled and "Role order" or "Simple order", kind = enabled and "accent" or "muted" },
        })
    end
    TrackSectionRefresh(ctx, sorting, refreshSortingControls)
    local scale = b:CollapsibleSection("scaling", "Frame Scaling", 380, false)
    local scaleW = scale._msuf2Width or b.width or 720
    local scaleGap = 16
    local scaleLeftX = 20
    local scaleInnerW = max(320, scaleW - 40)
    local scaleLeftW = floor((scaleInnerW - scaleGap) * 0.48)
    local scaleRightX = scaleLeftX + scaleLeftW + scaleGap
    local scaleRightW = scaleInnerW - scaleLeftW - scaleGap
    local scaleModeCard = W.ControlCard(scale, "Mode", "Scales frame size, fonts, and icons proportionally.", scaleLeftX, -38, scaleLeftW, 128)
    local manualCard = W.ControlCard(scale, "Manual Scale", "Buff/debuff positions stay relative to their anchors.", scaleLeftX, -184, scaleLeftW, 144)
    local autoCard = W.ControlCard(scale, "Auto Breakpoints", "Automatically scale by group size.", scaleRightX, -38, scaleRightW, 290)
    local RefreshScalingState = M.RefreshProxy()
    M._msuf2LastGroupScaleMode = M._msuf2LastGroupScaleMode or {}
    local scaleEnabled = W.SwitchAt(scaleModeCard, "Frame scaling", scaleLeftW - 62, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, scaleEnabled,
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
            RefreshScalingState()
        end,
        ControlMeta(ctx, "field.frameScaleEnabled"))
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
            RefreshScalingState()
        end,
        ControlMeta(ctx, "field.frameScaleMode"))
    local function BindScaleSlider(widget, key, default, labelFn)
        M.BindNumberWidget(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                Set(CurrentScope(), key, floor((tonumber(v) or default or 0) + 0.5), "rebuild")
            end,
            default, (function()
                local meta = ControlMeta(ctx, "field." .. tostring(key))
                meta.step, meta.roundStep = 5, true
                return meta
            end)())
        local function RefreshLabel()
            if widget and widget._msuf2Title then widget._msuf2Title:SetText(labelFn(Num(CurrentScope(), key, default))) end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(floor((tonumber(value) or default or 0) + 0.5))) end
        end)
        M.TrackRefresh(ctx, RefreshLabel)
        return widget
    end
    local function AddScaleSlider(parent, spec, width)
        local label = spec.label
        local slider = BindScaleSlider(W.Slider(parent, "", 50, spec.max or 100, 5, width), spec.key, spec.default,
            spec.labelFn or function(v) return string.format("%s: %d%%", label, v) end)
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
        return slider
    end
    local manualScale = AddScaleSlider(manualCard, { key = "frameScaleManual", default = 100, max = 150, y = -64, label = "Manual Scale" }, scaleLeftW)
    local autoLabel = autoCard and autoCard.title
    local autoScaleControls = {}
    for i, spec in ipairs({
        { key = "scaleAt10", default = 100, y = -66, label = "1-10 players" },
        { key = "scaleAt20", default = 85, y = -120, label = "11-20 players" },
        { key = "scaleAt25", default = 80, y = -174, label = "21-25 players" },
        { key = "scaleOver25", default = 70, y = -228, label = "26+ players" },
    }) do autoScaleControls[i] = AddScaleSlider(autoCard, spec, scaleRightW) end
    local scaleHint = manualCard and manualCard.subtitle
    if scaleHint.SetWordWrap then scaleHint:SetWordWrap(true) end
    RefreshScalingState = RefreshScalingState(function()
        local mode = Val(CurrentScope(), "frameScaleMode", "off")
        local scalingOn = mode ~= "off"
        local manualOn = mode == "manual"
        local autoOn = mode == "auto"
        SetOptionEnabled(scaleEnabled, true)
        SetOptionEnabled(scaleMode, scalingOn)
        SetOptionEnabled(manualScale, manualOn)
        SetOptionsEnabled(autoScaleControls, autoOn)
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
        SetSectionBadgesAndStatus(scale, {
            OnOffBadge(scalingOn, "Scaling", "Off"),
            { text = manualOn and ("Manual " .. BadgeNumber(Num(CurrentScope(), "frameScaleManual", 100)) .. "%") or (autoOn and "Auto breakpoints" or "Native size"), kind = scalingOn and "info" or "muted" },
        })
    end)
    TrackSectionRefresh(ctx, scale, RefreshScalingState)

    local anchor = b:CollapsibleSection("anchor", "Anchoring", 220, false)
    local anchorTo = W.Dropdown(anchor, "Anchor To", GF_ANCHOR_TO, 200)
    M.UnitSectionsShared.PlaceDropdown(anchor, anchorTo, 14, -38, 200)
    M.BindDropdownWidget(ctx, anchorTo,
        function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.anchorToFrame = (v == "FREE") and nil or v
            QueueGF(CurrentScope(), "rebuild")
        end,
        ControlMeta(ctx, "field.anchorToFrame"))
    local anchorPoint = ScopeDropdown(ctx, anchor, "Anchor Point", GF_ANCHOR_POINTS, 160, "anchorPoint", "CENTER", "rebuild", 254, -38, 160)
    local function IsStandardAnchorTarget(value)
        return value == nil or value == "" or value == "FREE" or value == "player" or value == "target"
            or value == "targettarget" or value == "focustarget" or value == "focus"
    end
    local function CurrentCustomAnchor()
        local value = Conf(CurrentScope()).anchorToFrame or ""
        return IsStandardAnchorTarget(value) and "" or value
    end
    local function SetCustomAnchor(value)
        value = value or ""
        local kind = CurrentScope()
        Conf(kind).anchorToFrame = (value ~= "") and value or nil
        QueueGF(kind, "rebuild")
    end
    local customAnchor = M.UnitSectionsShared.CustomAnchorEditor(ctx, anchor, {
        getValue = CurrentCustomAnchor,
        setValue = SetCustomAnchor,
        clearValue = function() SetCustomAnchor("") end,
        commitTitle = "Set Group Anchor",
        commitKey = function() return "group:anchorCustom:" .. tostring(CurrentScope()) end,
        pickTitle = "Pick Group Anchor",
        pickKey = function() return "group:anchorPick:" .. tostring(CurrentScope()) end,
        controlDomain = "group",
        controlPageKey = ctx and ctx.key,
        controlPath = "anchor.custom",
        assistantDisposition = "dynamic",
        assistantDispositionReason = "Custom anchor editing targets the currently selected Group scope.",
    })
    local function RefreshAnchorHeader()
        customAnchor.Refresh()
        SetSectionBadgesAndStatus(anchor, {
            { text = OptionText(GF_ANCHOR_TO, Conf(CurrentScope()).anchorToFrame or "FREE", "Free"), kind = "info" },
            { text = OptionText(GF_ANCHOR_POINTS, Val(CurrentScope(), "anchorPoint", "CENTER"), "CENTER"), kind = "accent" },
        })
    end
    TrackSectionRefresh(ctx, anchor, RefreshAnchorHeader)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 20 })
