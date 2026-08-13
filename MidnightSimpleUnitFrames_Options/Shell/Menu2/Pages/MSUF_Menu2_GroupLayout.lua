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
local SCOPE_VALUES, GROWTH_VALUES, SORT_MODES, GF_ANCHOR_TO, GF_ANCHOR_POINTS = M.PickDefaults(GP, [[SCOPE_VALUES GROWTH_VALUES SORT_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS]])
local GROUP_FRAME_PROVIDER_VALUES = GP.GROUP_FRAME_PROVIDER_VALUES or {}
local GROUP_RAID_MANAGER_VALUES = GP.GROUP_RAID_MANAGER_VALUES or {}
local GF, Conf, Val, QueueGF, Set, Bool, Num, ScopeSection, CurrentScope, BindScopeToggle, ScopeDropdown, ScopeSlider, BuildGrowthDirectionTiles, BuildRoleOrderRows, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, TrackSectionRefresh, OnOffBadge, BadgeNumber, OptionText, CreateSectionNotice, ControlMeta, RegisterControl, RefreshContext, FrameProvider, FrameProviderLabel, FrameProviderTooltip, SetFrameProvider, RaidManagerMode, SetRaidManagerMode = M.Pick(GP, [[GF Conf Val QueueGF Set Bool Num ScopeSection CurrentScope BindScopeToggle ScopeDropdown ScopeSlider BuildGrowthDirectionTiles BuildRoleOrderRows SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus TrackSectionRefresh OnOffBadge BadgeNumber OptionText CreateSectionNotice ControlMeta RegisterControl RefreshContext FrameProvider FrameProviderLabel FrameProviderTooltip SetFrameProvider RaidManagerMode SetRaidManagerMode]])
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
local function BindExclusiveFillToggle(ctx, parent, label, x, y, width, key, peerKey, historyLabel)
    local control = AttachGroupFocus(W.ToggleAt(parent, label, x, y, width), "bars")
    M.BindBoolWidget(ctx, control,
        function() return Bool(CurrentScope(), key, false) end,
        function(value)
            value = value == true
            local scope = CurrentScope()
            local function Write()
                local conf = Conf(scope)
                local changed = conf[key] ~= value
                conf[key] = value
                if value and conf[peerKey] ~= false then
                    conf[peerKey] = false
                    changed = true
                end
                if not changed then return false end
                QueueGF(scope, "visual")
                if M.RequestRefresh then M.RequestRefresh(ctx, "group-health-fill-mode") end
                return true
            end
            if type(M.RunWithHistory) == "function" then
                return M.RunWithHistory(historyLabel, "group:" .. tostring(scope) .. ":healthFillMode", Write)
            end
            return Write()
        end,
        ControlMeta(ctx, "field." .. tostring(key)))
    return control
end
local function CurrentGroupHealthMode()
    return tostring(Val(CurrentScope(), "gfBarMode", "GLOBAL") or "GLOBAL"):upper()
end
local function CurrentGroupEffectiveHealthMode()
    local mode = CurrentGroupHealthMode()
    if mode ~= "GLOBAL" then return mode end
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or {}
    mode = tostring(general.barMode or (general.useClassColors == true and "CLASS" or "DARK")):upper()
    if mode == "GRADIENT" and general.enableHealthGradient == false then return "CLASS" end
    return mode
end
local function GroupBackgroundUsesDerivedColor()
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or {}
    return general.barBgMatchHPColor == true or general.barBgClassColor == true
end
local function CurrentGroupHealthColorRefs()
    local mode = CurrentGroupHealthMode()
    local references
    if mode == "GLOBAL" or mode == "CLASS" or mode == "GRADIENT" then
        -- Class-colored group health is one color per member class, not a
        -- single editable color. Picking one of them here handed out an
        -- arbitrary class and wrote it into the shared class color table, so
        -- the class mode contributes no foreground color of its own.
        if CurrentGroupEffectiveHealthMode() == "CLASS" then
            references = {}
        else
            references = { "health.current" }
        end
    else
        references = { "group.health" }
    end
    if not GroupBackgroundUsesDerivedColor() then
        references[#references + 1] = "group.background"
    end
    return references
end
local function GroupHealthColorNote(sharedNote)
    if CurrentGroupEffectiveHealthMode() == "CLASS" then
        return "Class-colored health uses one color per class. Open Colors > Class Colors to change them."
    end
    return sharedNote
end
local function CurrentGroupHealthColorContext()
    return {
        unit = "player",
        unitKey = "player",
        healthMode = CurrentGroupHealthMode(),
    }
end
local function RefreshFrameBasicsProviderHeader(section)
    local provider = FrameProvider(CurrentScope())
    local usesMSUF = provider == "MSUF"
    local offlineHidden = usesMSUF and Bool(CurrentScope(), "hideOfflineEnabled", false)
    local badges = {
        { text = FrameProviderLabel(CurrentScope()), kind = usesMSUF and "accent" or (provider == "NONE" and "muted" or "info") },
    }
    if usesMSUF then
        badges[#badges + 1] = { text = Bool(CurrentScope(), "showPlayer", true) and "Player shown" or "Player hidden", kind = Bool(CurrentScope(), "showPlayer", true) and "info" or "muted" }
        local offlineFaded = not offlineHidden and Bool(CurrentScope(), "offlineFadeEnabled", false)
        local offlineText
        if offlineHidden then
            offlineText = "Offline " .. BadgeNumber(Num(CurrentScope(), "hideOfflineDelay", 0)) .. "s"
        elseif offlineFaded then
            offlineText = "Offline faded"
        else
            offlineText = "Offline visible"
        end
        badges[#badges + 1] = { text = offlineText, kind = (offlineHidden or offlineFaded) and "accent" or "muted" }
    end
    local status
    if usesMSUF then
        status = {
            hint = "MSUF provider",
            hintColor = { 0.66, 0.84, 1.00, 1 },
        }
    else
        status = {
            hint = provider == "NONE" and "all frames hidden" or "Blizzard provider",
            hintColor = { 0.90, 0.84, 0.76, 1 },
            bg = { 0.105, 0.082, 0.052, 0.44 },
        }
    end
    SetSectionBadgesAndStatus(section, badges, status)
    return provider, usesMSUF, offlineHidden
end
local function BuildGFGeneralSection(ctx, b)
    local general = b:CollapsibleSection("general", "Frame Basics", 520, false)
    local generalW = general._msuf2Width or b.width or 720
    local generalLeftX = 32
    local generalRightX = min(max(430, floor(generalW * 0.52)), max(360, generalW - 360))
    local generalLeftW = max(250, generalRightX - generalLeftX - 42)
    local generalRightW = max(250, generalW - generalRightX - 32)
    local generalLeftToggleW = max(80, generalLeftW - 34)
    local generalRightToggleW = max(80, generalRightW - 34)
    local offlineSliderW = max(320, min(520, generalW - generalLeftX - 170))
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(general, function()
            local references = CurrentGroupHealthColorRefs()
            if Bool(CurrentScope(), "deadBgEnabled", false) and CurrentGroupEffectiveHealthMode() ~= "GRADIENT" then
                references[#references + 1] = "group.dead"
            end
            references[#references + 1] = "bar.health_loss"
            return references
        end, {
            title = "Group Frame Colors",
            note = function() return GroupHealthColorNote("Shared by Party, Raid and Mythic Raid.") end,
            historySource = "menu:group-frame-basics-colors",
            maxTargets = 5,
            offsetY = -10,
            context = CurrentGroupHealthColorContext,
        })
    end
    W.LabelAt(general, "Frame", generalLeftX, -38, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(general, "Behavior", generalRightX, -38, generalRightW, "GameFontNormalSmall", T.colors.accent)
    local frameProvider = AttachGroupFocus(W.Dropdown(general, "Frames used in this scope", GROUP_FRAME_PROVIDER_VALUES, min(300, generalLeftW)), "layout")
    W.MoveWidget(frameProvider, general, generalLeftX, -64, min(300, generalLeftW), "LEFT")
    frameProvider._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindDropdownWidget(ctx, frameProvider,
        function() return FrameProvider(CurrentScope()) end,
        function(value)
            SetFrameProvider(CurrentScope(), value)
            RefreshContext(ctx)
        end,
        ControlMeta(ctx, "basics.frame_provider"))
    if M.AddTooltip then
        M.AddTooltip(frameProvider,
            function() return M.Format("%s frame provider", ScopeLabel()) end,
            function() return FrameProviderTooltip(CurrentScope()) end,
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local providerHelp = W.Text(general,
        "Choose MSUF, follow WoW's own Blizzard frame settings, force Blizzard frames, or hide both. Party, Raid, and Mythic Raid are independent.",
        generalRightX, -58, generalRightW, T.colors.muted)
    if providerHelp and providerHelp.SetWordWrap then providerHelp:SetWordWrap(true) end
    local msufControls = {}
    msufControls[#msufControls + 1] = BindExclusiveFillToggle(ctx, general, "Smooth health fill",
        generalRightX, -124, generalRightToggleW, "smoothFill", "chunkedFill", "Smooth group health fill")
    msufControls[#msufControls + 1] = BindExclusiveFillToggle(ctx, general, "Chunked health loss",
        generalRightX, -154, generalRightToggleW, "chunkedFill", "smoothFill", "Chunked group health loss")
    M.BuildControlSpecs({
        { "Show player", generalLeftX, -124, generalLeftToggleW, "layout", "showPlayer", true, "rebuild" },
        { "Show while solo", generalLeftX, -154, generalLeftToggleW, "layout", "showSolo", false, "rebuild" },
        { "Hide in Housing", generalLeftX, -184, generalLeftToggleW, "layout", "hideInHousing", false, "visual" },
        { "Reverse fill direction", generalRightX, -184, generalRightToggleW, "bars", "reverseFill", false, "visual" },
        { "Hide during client scene", generalRightX, -214, generalRightToggleW, "layout", "hideInClientScene", true, "visual" },
        { "Click casting / Clique", generalRightX, -244, generalRightToggleW, "layout", "clickCastEnabled", true, "rebuild" },
    }, { ["*"] = function(s) return BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, s[1], s[2], s[3], s[4]), s[5]), s[6], s[7], s[8]) end }, nil, msufControls)
    --- Blizzard's Raid Manager tab is one shared frame, so this control is deliberately
    --- not scope-bound: it reads and writes Party, Raid and Mythic Raid together. It also
    --- stays live on the Blizzard providers, where MSUF's ownership pass never hides the
    --- tab -- so it must not join msufControls, which grey out when the provider is not MSUF.
    local raidManager = AttachGroupFocus(W.Dropdown(general, "Blizzard Raid Manager", GROUP_RAID_MANAGER_VALUES, min(300, generalLeftW)), "layout")
    W.MoveWidget(raidManager, general, generalLeftX, -220, min(300, generalLeftW), "LEFT")
    raidManager._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindDropdownWidget(ctx, raidManager,
        function() return RaidManagerMode() end,
        function(value) SetRaidManagerMode(value) end,
        ControlMeta(ctx, "basics.raid_manager"))
    if M.AddTooltip then
        M.AddTooltip(raidManager,
            function() return M.Tr("Blizzard Raid Manager") end,
            function()
                return M.Tr("Blizzard's tab at the left screen edge with ready check, raid markers, and role filters. One shared frame, so this setting is the same for Party, Raid, and Mythic Raid.")
            end,
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local raidManagerHelp = W.Text(general,
        "Shared by Party, Raid, and Mythic Raid. Automatic keeps the tab hidden while MSUF provides the group frames.",
        generalLeftX, -278, generalW - generalLeftX - 32, T.colors.muted)
    if raidManagerHelp and raidManagerHelp.SetWordWrap then raidManagerHelp:SetWordWrap(true) end
    W.DividerAt(general, -326, generalLeftX, 32)
    W.LabelAt(general, "Offline Members", generalLeftX, -344, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    local hideOfflineEnabled = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Offline Members", generalLeftX, -370, generalLeftW), "layout"), "hideOfflineEnabled", false, "visual")
    local hideOfflineCombat = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, "Hide offline in combat", generalRightX, -370, generalRightToggleW), "layout"), "hideOfflineInCombat", false, "visual")
    local hideOffline = AttachGroupFocus(ScopeSlider(ctx, general, "Hide offline after", 0, 120, 1, offlineSliderW, "hideOfflineDelay", 0, "visual", generalLeftX, -404, offlineSliderW, "LEFT"), "layout")
    local hideOfflineControls = { hideOfflineCombat, hideOffline }
    local generalNotice, generalNoticeButton
    if type(CreateSectionNotice) == "function" then
        local _
        generalNotice, _, generalNoticeButton = CreateSectionNotice(general, -464, "Use MSUF", 104)
    end
    if generalNoticeButton then
        RegisterControl(generalNoticeButton, ctx, "scope.use_msuf_now", "Use MSUF", "button", "setting", {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This shortcut selects MSUF as the frame provider for the currently selected Group scope.",
            assistantSettingKeys = {
                "gf_party.enabled", "gf_party.blizzardFallbackMode",
                "gf_raid.enabled", "gf_raid.blizzardFallbackMode",
                "gf_mythicraid.enabled", "gf_mythicraid.blizzardFallbackMode",
            },
            command = {
                kind = "toggle", valueKind = "boolean",
                get = function() return FrameProvider(CurrentScope()) == "MSUF" end,
                set = function(value) SetFrameProvider(CurrentScope(), value == true and "MSUF" or "AUTO") end,
            },
        })
        generalNoticeButton:SetScript("OnClick", function()
            SetFrameProvider(CurrentScope(), "MSUF")
            RefreshContext(ctx)
        end)
    end
    local function RefreshHideOfflineState()
        local provider, usesMSUF, enabled = RefreshFrameBasicsProviderHeader(general)
        SetOptionsEnabled(msufControls, usesMSUF)
        SetOptionEnabled(hideOfflineEnabled, usesMSUF)
        SetOptionsEnabled(hideOfflineControls, usesMSUF and enabled)
        if generalNotice then
            generalNotice:SetShown(not usesMSUF)
            if provider == "AUTO" then
                generalNotice:SetMessage(M.Format("%s uses Blizzard frames. WoW's own settings decide when they appear.", ScopeLabel()), "info")
            elseif provider == "SHOW" then
                generalNotice:SetMessage(M.Format("%s forces Blizzard frames visible. Use this only when the normal WoW settings option does not show them.", ScopeLabel()), "warning")
            elseif provider == "NONE" then
                generalNotice:SetMessage(M.Format("%s hides both MSUF and Blizzard group frames.", ScopeLabel()), "warning")
            end
        end
    end
    TrackSectionRefresh(ctx, general, RefreshHideOfflineState)
end

local function BuildGFTextSection(ctx, b)
    local layoutSections = M.GroupFrameLayoutSections
    if layoutSections and layoutSections.BuildText then return layoutSections.BuildText(ctx, b) end
end

local function BuildGFResourceBarSection(ctx, b)
    local layoutSections = M.GroupFrameLayoutSections
    if layoutSections and layoutSections.BuildResourceBar then return layoutSections.BuildResourceBar(ctx, b) end
end

local function BuildGFRangeFadeSection(ctx, b)
    local layoutSections = M.GroupFrameLayoutSections
    if layoutSections and layoutSections.BuildRangeFade then return layoutSections.BuildRangeFade(ctx, b) end
end

local function BuildGFTransparencySection(ctx, b)
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
    -- State tab row: base cards edit the general, always-on opacities,
    -- the second tab holds the whole-member-frame out-of-combat fade.
    local _, transparencyBarY = W.NextRow(transparency, 34)
    local _, transparencyCardY = W.NextRow(transparency, transparencyCardH)
    local healthOpacityCard = W.ControlCard(transparency, "Health Bar", nil, transparencyLeftX, transparencyCardY, transparencyCardW, transparencyCardH)
    local opacityOptionsCard = W.ControlCard(transparency, "Options", nil, transparencyRightX, transparencyCardY, transparencyRightW, transparencyCardH)
    local oocCard = W.ControlCard(transparency, "Out of Combat", nil, transparencyLeftX, transparencyCardY, transparencyInnerW, transparencyCardH)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(healthOpacityCard, CurrentGroupHealthColorRefs, {
            title = "Group Health Bar Colors",
            note = function()
                return GroupHealthColorNote("Foreground follows the selected group color mode; editable group colors are shared by Party, Raid and Mythic Raid.")
            end,
            historySource = "menu:group-transparency-colors",
            context = CurrentGroupHealthColorContext,
        })
    end
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

    -- Out of Combat tab: whole-member-frame fade; min-composed with range and
    -- offline fades at runtime (strongest fade wins). Slider greys while off.
    BindScopeToggle(ctx,
        AttachGroupFocus(W.ToggleAt(oocCard, "Fade frame out of combat", 16, -54, transparencyCardW + 40), "bars"),
        "oocFadeEnabled", false, "visual", "field.oocFadeEnabled")
    local oocSlider = AddAlphaSlider(oocCard, transparencyCardW, { label = "Out of Combat Opacity", key = "oocFadeAlpha", default = 0.5, y = -112 })
    local function RefreshOocState()
        SetOptionEnabled(oocSlider, Bool(CurrentScope(), "oocFadeEnabled", false))
    end
    TrackSectionRefresh(ctx, transparency, RefreshOocState)
    RefreshOocState()

    -- Tab switch between the base opacity cards and the OOC fade card.
    local transparencyTab = "combat"
    local transparencyCombatCards = { healthOpacityCard, opacityOptionsCard }
    local function ApplyTransparencyTab()
        local ooc = transparencyTab == "ooc"
        for i = 1, #transparencyCombatCards do
            W.SetControlShown(transparencyCombatCards[i], not ooc)
        end
        W.SetControlShown(oocCard, ooc)
    end
    local stateBar = W.ScopeOverrideBar(ctx, transparency, {
        values = {
            { value = "combat", text = "General" },
            { value = "ooc", text = "Out of Combat" },
        },
        width = transparencyW,
        label = "Editing:",
        labelX = transparencyLeftX,
        labelWidth = 64,
        centerY = transparencyBarY - 16,
        getValue = function() return transparencyTab end,
        setValue = function(value)
            transparencyTab = value == "ooc" and "ooc" or "combat"
            ApplyTransparencyTab()
        end,
    })
    if RegisterControl then
        RegisterControl(stateBar, ctx, "transparency.state_selector", "Editing", "segment", "ephemeral")
    end
    ApplyTransparencyTab()
    if b.FinishSection then b:FinishSection(transparency, 48) end
end

local function BuildGFGeometrySection(ctx, b)
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
    LayoutSlider(sizeCard, "Spacing", 0, 60, 1, "spacing", 1, -162)
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
end

local function BuildGFSortingSection(ctx, b)
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
end

local function BuildGFScalingSection(ctx, b)
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
    local function BeginAutoScalePreview(slider, previewCount)
        if not (slider and previewCount and type(M.SetGFScalingBreakpointPreview) == "function") then return end
        if Val(CurrentScope(), "frameScaleMode", "off") ~= "auto" then return end
        if (_G.InCombatLockdown and _G.InCombatLockdown()) or _G.MSUF_InCombat == true then return end
        local kind = CurrentScope()
        slider._msuf2ScalingPreviewKind = kind
        slider._msuf2ScalingPreviewCount = previewCount
        M.SetGFScalingBreakpointPreview(kind, previewCount, slider:GetValue())
    end
    local function UpdateAutoScalePreview(slider, value)
        local kind = slider and slider._msuf2ScalingPreviewKind
        local count = slider and slider._msuf2ScalingPreviewCount
        if kind and count and type(M.SetGFScalingBreakpointPreview) == "function" then
            M.SetGFScalingBreakpointPreview(kind, count, value)
        end
    end
    local function EndAutoScalePreview(slider)
        local kind = slider and slider._msuf2ScalingPreviewKind
        if not kind then return end
        slider._msuf2ScalingPreviewKind = nil
        slider._msuf2ScalingPreviewCount = nil
        if type(M.SetGFScalingBreakpointPreview) == "function" then
            M.SetGFScalingBreakpointPreview(kind, nil, nil)
        end
    end
    local function BindAutoScalePreview(slider, previewCount)
        if not (slider and previewCount) then return end
        local function Begin() BeginAutoScalePreview(slider, previewCount) end
        local function End() EndAutoScalePreview(slider) end
        slider:HookScript("OnMouseDown", Begin)
        slider:HookScript("OnValueChanged", function(_, value) UpdateAutoScalePreview(slider, value) end)
        slider:HookScript("OnLeave", End)
        slider:HookScript("OnHide", End)
        if slider.editBox and slider.editBox.HookScript then
            slider.editBox:HookScript("OnEditFocusGained", Begin)
            slider.editBox:HookScript("OnEditFocusLost", End)
            slider.editBox:HookScript("OnHide", End)
        end
        for i = 1, #(slider._msuf2StepButtons or {}) do
            local button = slider._msuf2StepButtons[i]
            button:HookScript("OnClick", Begin)
            button:HookScript("OnLeave", End)
            button:HookScript("OnHide", End)
        end
    end
    local function AddScaleSlider(parent, spec, width)
        local label = spec.label
        local slider = BindScaleSlider(W.Slider(parent, "", 50, spec.max or 100, 5, width), spec.key, spec.default,
            spec.labelFn or function(v) return string.format("%s: %d%%", label, v) end)
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
        BindAutoScalePreview(slider, spec.previewCount)
        return slider
    end
    local manualScale = AddScaleSlider(manualCard, { key = "frameScaleManual", default = 100, max = 150, y = -64, label = "Manual Scale" }, scaleLeftW)
    local autoLabel = autoCard and autoCard.title
    local autoScaleControls = {}
    for i, spec in ipairs({
        { key = "scaleAt10", default = 100, y = -66, label = "1-10 players", previewCount = 10 },
        { key = "scaleAt20", default = 85, y = -120, label = "11-20 players", previewCount = 20 },
        { key = "scaleAt25", default = 80, y = -174, label = "21-25 players", previewCount = 25 },
        { key = "scaleOver25", default = 70, y = -228, label = "26+ players", previewCount = 30 },
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
end

local function BuildGFAnchorSection(ctx, b)
    local anchor = b:CollapsibleSection("anchor", "Anchoring", 220, false)
    local anchorW = anchor._msuf2Width or b.width or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, anchorW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
    local anchorTo = W.Dropdown(anchor, "Anchor To", GF_ANCHOR_TO, anchorControlW)
    M.UnitSectionsShared.PlaceDropdown(anchor, anchorTo, anchorLeftX, -38, anchorControlW)
    M.BindDropdownWidget(ctx, anchorTo,
        function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
        function(v)
            local conf = Conf(CurrentScope())
            conf.anchorToFrame = (v == "FREE") and nil or v
            QueueGF(CurrentScope(), "rebuild")
        end,
        ControlMeta(ctx, "field.anchorToFrame"))
    local anchorPoint = ScopeDropdown(ctx, anchor, "Anchor Point", GF_ANCHOR_POINTS, anchorControlW, "anchorPoint", "CENTER", "rebuild", anchorRightX, -38, anchorControlW)
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
        x = anchorLeftX,
        y = -112,
        width = customAnchorW,
        getValue = CurrentCustomAnchor,
        setValue = SetCustomAnchor,
        isCandidateAllowed = function(frame)
            local gf = MSUF.GF
            local owner = gf and gf.anchors and gf.anchors[CurrentScope()]
            local factory = MSUF.UF and MSUF.UF.Factory
            return not owner or not factory or type(factory.AnchorWouldCreateCycle) ~= "function"
                or (frame ~= owner and not factory.AnchorWouldCreateCycle(owner, frame))
        end,
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
    RegisterControl(customAnchor.clear, ctx, "anchor.custom.clear", "Clear", "button", "action", {
        actionKey = "clear_group_custom_anchor", actionInputArg = "scope",
    })
    RegisterControl(customAnchor.pick, ctx, "anchor.custom.pick", "Pick", "button", "action", {
        actionKey = "start_group_custom_anchor_picker", actionInputArg = "scope",
    })
    local function RefreshAnchorHeader()
        customAnchor.Refresh()
        SetSectionBadgesAndStatus(anchor, {
            { text = OptionText(GF_ANCHOR_TO, Conf(CurrentScope()).anchorToFrame or "FREE", "Free"), kind = "info" },
            { text = OptionText(GF_ANCHOR_POINTS, Val(CurrentScope(), "anchorPoint", "CENTER"), "CENTER"), kind = "accent" },
        })
    end
    TrackSectionRefresh(ctx, anchor, RefreshAnchorHeader)
end

local GROUP_LAYOUT_SECTION_SPECS = {
    {
        sectionId = "general", title = "Frame Basics", height = 520, build = BuildGFGeneralSection,
        prepareShell = function(ctx, section)
            local function RefreshProviderHeader() RefreshFrameBasicsProviderHeader(section) end
            if M.AddRefresherOnce then
                M.AddRefresherOnce(ctx, "group-frame-basics-provider-header", RefreshProviderHeader)
            elseif M.AddRefresher then
                M.AddRefresher(ctx, RefreshProviderHeader)
            end
            RefreshProviderHeader()
            return RefreshProviderHeader
        end,
    },
    {
        sectionId = function(ctx)
            if ctx and ctx.entry and ctx.entry.hiddenBuild then
                local state = type(M.GetPersistentMenuStateTable) == "function"
                    and M.GetPersistentMenuStateTable("accordionState") or M.accordionState
                if type(state) == "table" and state["gf_layout:portrait"] == true then
                    return nil
                end
            end
            return "portrait"
        end,
        title = "Portrait", height = 616,
        -- Resolve through GroupPage at build time. The desktop Assistant
        -- collector loads page specs before exercising lazy section builders.
        build = function(ctx, builder) return GP.BuildPortrait(ctx, builder) end,
        prepareShell = function(...) return GP.PreparePortraitShell(...) end,
    },
    { sectionId = "text", title = "Text", height = 690, build = BuildGFTextSection },
    { sectionId = "power", title = "Resource Bar", autoHeight = true, build = BuildGFResourceBarSection },
    { sectionId = "range", title = "Range Fade", height = 220, build = BuildGFRangeFadeSection },
    { sectionId = "transparency", title = "Transparency", autoHeight = true, build = BuildGFTransparencySection },
    { sectionId = "layout_advanced", title = "Geometry", height = 448, build = BuildGFGeometrySection },
    { sectionId = "sorting", title = "Sorting", height = 236, build = BuildGFSortingSection },
    { sectionId = "scaling", title = "Frame Scaling", height = 380, build = BuildGFScalingSection },
    { sectionId = "anchor", title = "Anchoring", height = 220, build = BuildGFAnchorSection },
}

local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
    for i = 1, #GROUP_LAYOUT_SECTION_SPECS do
        local spec = GROUP_LAYOUT_SECTION_SPECS[i]
        if type(buildLazy) == "function" then buildLazy(ctx, b, nil, spec)
        else spec.build(ctx, b) end
    end
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 28 })
