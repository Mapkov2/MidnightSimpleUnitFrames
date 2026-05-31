local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
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
local BLIZZARD_FALLBACK_VALUES = GP.BLIZZARD_FALLBACK_VALUES or {}
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
local SetSectionBadges = GP.SetSectionBadges or function() end
local OnOffBadge = GP.OnOffBadge or function(enabled, onText, offText) return { text = enabled and (onText or "Shown") or (offText or "Hidden"), kind = enabled and "ok" or "muted" } end
local BadgeNumber = GP.BadgeNumber or function(value) return tostring(value or 0) end
local OptionText = GP.OptionText or function(_, value, fallback) return tostring(value or fallback or "") end
local CreateSectionNotice = GP.CreateSectionNotice

local function ScopeLabel()
    local scope = CurrentScope() or "party"
    for i = 1, #SCOPE_VALUES do
        local info = SCOPE_VALUES[i]
        if info and info.value == scope then return info.text or scope end
    end
    return tostring(scope)
end

local function TooltipModeHint(mode)
    if mode == "OFF" then return "tooltip hidden" end
    if mode == "MODIFIER" then return "hold modifier to show" end
    return "tooltip always visible"
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

local LAYOUT_PRESET_VALUES = {
    { value = "PARTY", text = "5-Player" },
    { value = "RAID_GRID", text = "Raid Grid" },
    { value = "COMPACT_RAID", text = "Compact Raid" },
}

local LAYOUT_PRESETS = {
    PARTY = {
        label = "5-Player",
        intent = "Bigger rows for a five-player group.",
        width = 184,
        height = 49,
        spacing = 2,
        unitsPerColumn = 5,
        maxColumns = 1,
        growth = "DOWN",
        preserveRaidGroups = false,
        frameScaleMode = "off",
    },
    RAID_GRID = {
        label = "Raid Grid",
        intent = "Clear raid columns with readable names and status.",
        width = 100,
        height = 40,
        spacing = 2,
        unitsPerColumn = 5,
        maxColumns = 8,
        growth = "RIGHT",
        preserveRaidGroups = false,
        frameScaleMode = "off",
    },
    COMPACT_RAID = {
        label = "Compact Raid",
        intent = "Dense grid for larger raids and limited screen space.",
        width = 80,
        height = 32,
        spacing = 1,
        unitsPerColumn = 5,
        maxColumns = 8,
        growth = "RIGHT",
        preserveRaidGroups = false,
        frameScaleMode = "auto",
        scaleAt10 = 100,
        scaleAt20 = 90,
        scaleAt25 = 84,
        scaleOver25 = 76,
    },
}

local function RefreshPageControls(ctx)
    if not (ctx and ctx.refreshers) then return end
    for i = 1, #ctx.refreshers do
        local fn = ctx.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local function CurrentLayoutPreset(scope)
    local conf = Conf(scope)
    local preset = conf and conf.layoutIntentPreset
    if LAYOUT_PRESETS[preset] then return preset end
    local width = Num(scope, "width", scope == "party" and 184 or 100)
    local height = Num(scope, "height", scope == "party" and 49 or 40)
    local columns = Num(scope, "maxColumns", scope == "party" and 1 or 8)
    local scaleMode = Val(scope, "frameScaleMode", "off")
    if width <= 88 and height <= 34 and columns >= 5 then return "COMPACT_RAID" end
    if scope ~= "party" or columns > 1 or scaleMode == "auto" then return "RAID_GRID" end
    return "PARTY"
end

local function ApplyLayoutPreset(ctx, presetKey)
    local preset = LAYOUT_PRESETS[presetKey] or LAYOUT_PRESETS.PARTY
    local scope = CurrentScope()
    local conf = Conf(scope)
    if not conf then return end

    conf.layoutIntentPreset = presetKey
    conf.width = preset.width
    conf.height = preset.height
    conf.spacing = preset.spacing
    conf.unitsPerColumn = preset.unitsPerColumn
    conf.maxColumns = preset.maxColumns
    conf.growth = preset.growth
    conf.preserveRaidGroups = preset.preserveRaidGroups == true
    if preset.frameScaleMode then conf.frameScaleMode = preset.frameScaleMode end
    if preset.scaleAt10 then conf.scaleAt10 = preset.scaleAt10 end
    if preset.scaleAt20 then conf.scaleAt20 = preset.scaleAt20 end
    if preset.scaleAt25 then conf.scaleAt25 = preset.scaleAt25 end
    if preset.scaleOver25 then conf.scaleOver25 = preset.scaleOver25 end

    QueueGF(scope, "rebuild")
    RefreshPageControls(ctx)
end

local function BuildTopLayoutIntent(ctx, sec, helpers)
    if not (sec and helpers and helpers.MakeTopButton) then return end
    local buttons = {}
    local previous = helpers.wrapped and nil or helpers.lastScopeButton
    for i = 1, #LAYOUT_PRESET_VALUES do
        local info = LAYOUT_PRESET_VALUES[i]
        local width = info.value == "COMPACT_RAID" and 104 or (info.value == "RAID_GRID" and 82 or 76)
        local btn = helpers.MakeTopButton(sec, info.text, width, {
            bg = { 0.026, 0.040, 0.084, 0.95 },
            border = { 0.095, 0.165, 0.330, 0.62 },
            activeBg = { 0.055, 0.125, 0.300, 0.98 },
            activeBorder = { 0.220, 0.470, 0.900, 0.92 },
        })
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", previous == helpers.lastScopeButton and 16 or 6, 0)
        elseif helpers.wrapped then
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, helpers.intentY or -42)
        else
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, helpers.topY or -8)
        end
        btn:SetScript("OnClick", function()
            if CurrentLayoutPreset(CurrentScope()) == info.value then
                RefreshPageControls(ctx)
                return
            end
            local function ApplyPreset()
                ApplyLayoutPreset(ctx, info.value)
            end
            if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Layout Preset", "group:layout:preset:" .. tostring(CurrentScope()), ApplyPreset)
            else
                ApplyPreset()
            end
            if M.ShowStatusFeedback then M.ShowStatusFeedback((info.text or "") .. " layout applied", "ok", 1.2) end
        end)
        AttachGroupFocus(btn, "layout")
        buttons[info.value] = btn
        previous = btn
    end

    local function RefreshTopIntent()
        local current = CurrentLayoutPreset(CurrentScope())
        for i = 1, #LAYOUT_PRESET_VALUES do
            local value = LAYOUT_PRESET_VALUES[i].value
            local btn = buttons[value]
            if btn and btn.SetActive then btn:SetActive(current == value) end
        end
    end
    M.AddRefresher(ctx, RefreshTopIntent)
    RefreshTopIntent()
end

local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b, {
        buildTopIntent = function(sec, helpers)
            BuildTopLayoutIntent(ctx, sec, helpers)
        end,
    })
    M.GroupPreview.Add(ctx, b)

    local general = b:CollapsibleSection("general", "Availability", 430, false)
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
    local generalNotice, _, generalNoticeButton = CreateSectionNotice and CreateSectionNotice(general, -374, "Enable Scope", 104)
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
    do
        local entry = general and general._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshHideOfflineState end
    end

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
    do
        local entry = advancedLayout and advancedLayout._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshRaidGroupLayoutState end
    end

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
    do
        local entry = sorting and sorting._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = refreshSortingControls end
    end

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

    local scaleMode = W.Segment(scaleModeCard, "Scale Mode", {
        { value = "manual", text = "Manual" },
        { value = "auto", text = "Auto" },
    }, min(220, scaleLeftW - 32))
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
    do
        local entry = scale and scale._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshScalingState end
    end

    local transparency = b:CollapsibleSection("border", "Transparency", 620, false)
    local transparencyW = transparency._msuf2Width or b.width or 720
    local transGap = 16
    local transLeftX = 20
    local transInnerW = max(320, transparencyW - 40)
    local transLeftW = floor((transInnerW - transGap) * 0.48)
    local transRightX = transLeftX + transLeftW + transGap
    local transRightW = transInnerW - transLeftW - transGap

    local opacityCard = W.ControlCard(transparency, "Opacity", "Combat state alpha.", transLeftX, -38, transLeftW, 250)
    local targetCard = W.ControlCard(transparency, "Fade target", "Whole frame or one visual layer.", transRightX, -38, transRightW, 250)
    local backdropCard = W.ControlCard(transparency, "Backdrop", "Frame background and base opacity.", transLeftX, -314, transLeftW, 250)
    local healthCard = W.ControlCard(transparency, "Health layers", "Base opacity for health fill and track.", transRightX, -314, transRightW, 250)

    local function PercentValue(value)
        return tostring(floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
    end

    local function ParsePercentValue(text)
        local raw = tostring(text or "")
        local value = tonumber((raw:gsub("%%", ""):gsub(",", ".")))
        if value == nil then return nil end
        if raw:find("%%") or value > 1 then
            return value / 100
        end
        return value
    end

    local function UsePercentInput(widget)
        if widget and widget.SetValueFormatter then widget:SetValueFormatter(PercentValue) end
        if widget and widget.SetValueParser then widget:SetValueParser(ParsePercentValue) end
    end

    local function AlphaLabel(label, value)
        return label .. ": " .. PercentValue(value)
    end

    local function Clamp01(value, fallback)
        value = tonumber(value)
        if value == nil then value = fallback or 1 end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end

    local function NormalizeAlphaMode(mode)
        local gf = GF and GF()
        if gf and type(gf.NormalizeAlphaLayerMode) == "function" then
            return gf.NormalizeAlphaLayerMode(mode)
        end
        if mode == true or mode == 1 or mode == "background" then return "background" end
        if mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then return "health" end
        return "foreground"
    end

    local function AlphaModeValue(mode)
        if mode == "background" then return 1 end
        if mode == "health" then return 2 end
        return 0
    end

    local function CurrentOpacityMode(conf)
        conf = conf or Conf(CurrentScope())
        if conf and conf.alphaExcludeTextPortrait == true then
            return NormalizeAlphaMode(conf.alphaLayerMode)
        end
        return "frame"
    end

    local function AlphaKeysForMode(modeKey)
        if modeKey == "background" then
            return "alphaBGInCombat", "alphaBGOutOfCombat"
        elseif modeKey == "health" then
            return "alphaHPInCombat", "alphaHPOutOfCombat"
        elseif modeKey == "foreground" then
            return "alphaFGInCombat", "alphaFGOutOfCombat"
        end
        return "alphaInCombat", "alphaOutOfCombat"
    end

    local function CurrentAlphaKeys(conf)
        return AlphaKeysForMode(CurrentOpacityMode(conf))
    end

    local function ReadAlphaValue(inCombat)
        local scope = CurrentScope()
        local conf = Conf(scope)
        local inKey, outKey = CurrentAlphaKeys(conf)
        local key = inCombat and inKey or outKey
        local value = tonumber(conf and conf[key])
        if value ~= nil then return value end
        if key == "alphaHPInCombat" then
            value = tonumber(conf and conf.alphaFGInCombat)
        elseif key == "alphaHPOutOfCombat" then
            value = tonumber(conf and conf.alphaFGOutOfCombat)
        end
        if value ~= nil then return value end
        return Num(scope, inCombat and "alphaInCombat" or "alphaOutOfCombat", 1)
    end

    local function WriteNumber(conf, key, value, fallback)
        value = Clamp01(value, fallback)
        if conf[key] == value then return false end
        conf[key] = value
        return true
    end

    local function WriteBool(conf, key, value)
        value = value and true or false
        if conf[key] == value then return false end
        conf[key] = value
        return true
    end

    local function BindAlphaSlider(widget, inCombat, label)
        M.BindSlider(ctx, widget,
            function() return ReadAlphaValue(inCombat) end,
            function(v)
                local scope = CurrentScope()
                local conf = Conf(scope)
                local inKey, outKey = CurrentAlphaKeys(conf)
                local changed
                if inCombat then
                    changed = WriteNumber(conf, inKey, v, 1) or changed
                    if Bool(scope, "alphaSync", false) then
                        changed = WriteNumber(conf, outKey, v, 1) or changed
                        if M.Refresh then M.Refresh(ctx) end
                    end
                else
                    changed = WriteNumber(conf, outKey, v, 1) or changed
                end
                if changed then QueueGF(scope, "visual") end
            end)
        UsePercentInput(widget)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, ReadAlphaValue(inCombat)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, value))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local inCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), true, "In combat")
    W.MoveWidget(inCombat, opacityCard, 16, -62, transLeftW - 58, "LEFT")

    local outCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), false, "Out of combat")
    W.MoveWidget(outCombat, opacityCard, 16, -130, transLeftW - 58, "LEFT")

    local sync = W.ToggleAt(opacityCard, "Sync both", 16, -194, transLeftW - 32)
    M.BindToggle(ctx, sync,
        function() return Bool(CurrentScope(), "alphaSync", false) end,
        function(v)
            local scope = CurrentScope()
            local conf = Conf(scope)
            local changed = WriteBool(conf, "alphaSync", v)
            if v then
                local _, outKey = CurrentAlphaKeys(conf)
                changed = WriteNumber(conf, outKey, ReadAlphaValue(true), 1) or changed
            end
            if changed then QueueGF(scope, "visual") end
            if M.Refresh then M.Refresh(ctx) end
        end)

    local mode = W.Segment(targetCard, "Affects", {
        { value = "frame", text = "Whole" },
        { value = "foreground", text = "Bars" },
        { value = "health", text = "HP" },
        { value = "background", text = "Backdrop" },
    }, transRightW - 32)
    W.MoveWidget(mode, targetCard, 16, -62, transRightW - 32, "LEFT")
    do
        local buttons = mode.buttons or {}
        local count = #buttons
        local buttonGap = 8
        local bw = count > 0 and floor((mode:GetWidth() - buttonGap * (count - 1)) / count) or 120
        for i = 1, count do
            local btn = buttons[i]
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", mode, "LEFT", (i - 1) * (bw + buttonGap), 0)
            btn:SetSize(bw, 22)
        end
    end

    local function SetOpacityMode(value)
        local scope = CurrentScope()
        local conf = Conf(scope)
        local inValue = ReadAlphaValue(true)
        local outValue = ReadAlphaValue(false)
        local changed
        if value == "frame" then
            changed = WriteBool(conf, "alphaExcludeTextPortrait", false) or changed
        else
            changed = WriteBool(conf, "alphaExcludeTextPortrait", true) or changed
            local modeValue = AlphaModeValue(value)
            if conf.alphaLayerMode ~= modeValue then
                conf.alphaLayerMode = modeValue
                changed = true
            end
            local syncedOut = Bool(scope, "alphaSync", false) and inValue or outValue
            local fgIn, fgOut = AlphaKeysForMode("foreground")
            local hpIn, hpOut = AlphaKeysForMode("health")
            local bgIn, bgOut = AlphaKeysForMode("background")
            changed = WriteNumber(conf, fgIn, value == "foreground" and inValue or 1, 1) or changed
            changed = WriteNumber(conf, fgOut, value == "foreground" and syncedOut or 1, 1) or changed
            changed = WriteNumber(conf, hpIn, value == "health" and inValue or 1, 1) or changed
            changed = WriteNumber(conf, hpOut, value == "health" and syncedOut or 1, 1) or changed
            changed = WriteNumber(conf, bgIn, value == "background" and inValue or 1, 1) or changed
            changed = WriteNumber(conf, bgOut, value == "background" and syncedOut or 1, 1) or changed
        end
        if changed then QueueGF(scope, "visual") end
        if M.Refresh then M.Refresh(ctx) end
    end

    M.BindSegment(ctx, mode,
        function() return CurrentOpacityMode() end,
        SetOpacityMode)

    local bgColor = W.Color(backdropCard, "Background Color")
    if bgColor._msuf2Title then
        bgColor._msuf2Title:ClearAllPoints()
        bgColor._msuf2Title:SetPoint("TOPLEFT", backdropCard, "TOPLEFT", 16, -56)
        bgColor._msuf2Title:SetWidth(120)
        bgColor._msuf2Title:SetJustifyH("LEFT")
    end
    bgColor:ClearAllPoints()
    bgColor:SetPoint("TOPLEFT", backdropCard, "TOPLEFT", 154, -54)
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

    local function BindTransparencySlider(widget, key, default, labelFn)
        M.BindSlider(ctx, widget,
            function() return Num(CurrentScope(), key, default) end,
            function(v)
                local n = Clamp01(v, default or 0)
                local conf = Conf(CurrentScope())
                if conf[key] == n then return end
                conf[key] = n
                QueueGF(CurrentScope(), "visual")
            end)
        UsePercentInput(widget)
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

    local bgAlpha = BindTransparencySlider(W.Slider(backdropCard, "", 0, 1, 0.05, transLeftW), "bgA", 0.85,
        function(v) return AlphaLabel("Backdrop base", v) end)
    W.MoveWidget(bgAlpha, backdropCard, 16, -100, transLeftW - 58, "LEFT")

    local hpFg = BindTransparencySlider(W.Slider(healthCard, "", 0.3, 1, 0.05, transRightW), "hpBarAlpha", 1,
        function(v) return AlphaLabel("HP Fill", v) end)
    W.MoveWidget(hpFg, healthCard, 16, -62, transRightW - 58, "LEFT")

    local hpBg = W.Slider(healthCard, "", 0, 1, 0.05, transRightW)
    M.BindSlider(ctx, hpBg,
        function()
            local conf = Conf(CurrentScope())
            return tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85
        end,
        function(v)
            local n = Clamp01(v, 0.85)
            local conf = Conf(CurrentScope())
            if conf.hpBgAlpha == n then return end
            conf.hpBgAlpha = n
            QueueGF(CurrentScope(), "visual")
        end)
    UsePercentInput(hpBg)
    local function RefreshHPBgLabel()
        if hpBg and hpBg._msuf2Title then
            local conf = Conf(CurrentScope())
            hpBg._msuf2Title:SetText(AlphaLabel("HP Track", tonumber(conf.hpBgAlpha) or tonumber(conf.bgA) or 0.85))
        end
    end
    hpBg:HookScript("OnValueChanged", function(_, value)
        if hpBg._msuf2Title then hpBg._msuf2Title:SetText(AlphaLabel("HP Track", value)) end
    end)
    M.AddRefresher(ctx, RefreshHPBgLabel)
    RefreshHPBgLabel()
    W.MoveWidget(hpBg, healthCard, 16, -130, transRightW - 58, "LEFT")

    local preserveHP = W.ToggleAt(healthCard, "Preserve HP color", 16, -188, transRightW - 32)
    M.BindToggle(ctx, preserveHP,
        function() return Bool(CurrentScope(), "alphaPreserveHPColor", false) end,
        function(v)
            v = v and true or false
            Set(CurrentScope(), "alphaPreserveHPColor", v, "visual")
            if M.WarnPreserveHPColorIfNeeded then M.WarnPreserveHPColorIfNeeded(v) end
        end)

    local textIgnore = W.ToggleAt(healthCard, "Text ignores HP opacity", 16, -222, transRightW - 32)
    M.BindToggle(ctx, textIgnore,
        function() return Bool(CurrentScope(), "hpTextIgnoreAlpha", true) end,
        function(v) Set(CurrentScope(), "hpTextIgnoreAlpha", v and true or false, "visual") end)

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
    do
        local entry = anchor and anchor._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshAnchorHeader end
    end

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
        local mode = Val(CurrentScope(), "tooltipMode", "ALWAYS")
        local modifier = Val(CurrentScope(), "tooltipModifier", "ALT")
        SetOptionEnabled(tooltipModifier, mode == "MODIFIER")
        SetSectionBadges(tooltip, {
            { text = OptionText(TOOLTIP_MODES, mode, "Always"), kind = mode == "NEVER" and "muted" or "info" },
            { text = mode == "MODIFIER" and OptionText(TOOLTIP_MODIFIERS, modifier, "Alt") or TooltipModeHint(mode), kind = mode == "NEVER" and "muted" or "accent" },
        })
        if type(SetSectionHeaderStatus) == "function" then SetSectionHeaderStatus(tooltip, nil) end
    end
    M.AddRefresher(ctx, refreshTooltipState)
    refreshTooltipState()
    do
        local entry = tooltip and tooltip._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = refreshTooltipState end
    end

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 17 })
