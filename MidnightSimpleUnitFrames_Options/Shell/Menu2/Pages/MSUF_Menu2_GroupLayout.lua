-- Menu2 Group Layout page: builds secure-header layout controls for party and raid frames.
-- UI writes must delegate rebuild/defer behavior to GroupFrame runtime helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, called through _G so a hook installed on one later still applies.
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua", {
    "MSUF_ApplyRoundedUnitframes",
})
local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}
local Shared = M.UnitSectionsShared
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local SCOPE_VALUES, GROWTH_VALUES, SORT_MODES, GF_ANCHOR_TO = GP.SCOPE_VALUES or {}, GP.GROWTH_VALUES or {}, GP.SORT_MODES or {}, GP.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = GP.GF_ANCHOR_POINTS or {}
local GROUP_FRAME_PROVIDER_VALUES = GP.GROUP_FRAME_PROVIDER_VALUES or {}
local GROUP_RAID_MANAGER_VALUES = GP.GROUP_RAID_MANAGER_VALUES or {}
local FRAME_BAR_SHAPE_OPTIONS = {
    { value = "DEFAULT", text = "Use shared style" },
    { value = "SQUARE", text = "Straight" },
    { value = "ROUNDED", text = "Rounded" },
    { value = "SLANTED", text = "Slanted" },
}
local Conf, Val, QueueGF, Set, Bool, Num, ScopeSection = GP.Conf, GP.Val, GP.QueueGF, GP.Set, GP.Bool, GP.Num, GP.ScopeSection
local CurrentScope, BindScopeToggle, ScopeDropdown, ScopeSlider = GP.CurrentScope, GP.BindScopeToggle, GP.ScopeDropdown, GP.ScopeSlider
local BuildGrowthDirectionTiles, BuildRoleOrderRows, SetOptionEnabled = GP.BuildGrowthDirectionTiles, GP.BuildRoleOrderRows, GP.SetOptionEnabled
local SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus = GP.SetOptionsEnabled, GP.FinalizeScopePage, GP.SetSectionBadgesAndStatus
local TrackSectionRefresh, OnOffBadge, BadgeNumber, OptionText = GP.TrackSectionRefresh, GP.OnOffBadge, GP.BadgeNumber, GP.OptionText
local CreateSectionNotice, ControlMeta, RegisterControl, RefreshContext = GP.CreateSectionNotice, GP.ControlMeta, GP.RegisterControl, GP.RefreshContext
local FrameProvider, FrameProviderLabel, FrameProviderTooltip = GP.FrameProvider, GP.FrameProviderLabel, GP.FrameProviderTooltip
local SetFrameProvider, RaidManagerMode, SetRaidManagerMode = GP.SetFrameProvider, GP.RaidManagerMode, GP.SetRaidManagerMode
SetSectionBadgesAndStatus = SetSectionBadgesAndStatus or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or M.OptionText
-- Only Midnight has the Mythic Raid scope (MSUF.Client.SupportsGroupKind); the
-- other clients get no "Hide groups 5–8" option and a shorter Group Layout section.
local MYTHIC_RAID_SUPPORTED = not M.SupportsFrameScope or M.SupportsFrameScope("mythicraid")
local GEOMETRY_SECTION_HEIGHT = MYTHIC_RAID_SUPPORTED and 540 or 504
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
    return GP.BindExclusiveScopeToggle(ctx, control, key, peerKey, historyLabel, "healthFillMode", function()
        if M.RequestRefresh then M.RequestRefresh(ctx, "group-health-fill-mode") end
    end)
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
    references[#references + 1] = "health.background.current"
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
        group = true,
        scope = "gf_" .. CurrentScope(),
    }
end
local function CurrentGroupHealthColorShortcutRelevant()
    local resolver = M.ResolveContextColorReferences
    if type(resolver) ~= "function" then return false end
    local targets = resolver(CurrentGroupHealthColorRefs(), CurrentGroupHealthColorContext())
    local count = type(targets) == "table" and #targets or 0
    return count > 0 and count <= 7
end
local function PrepareFrameEnable(ctx, section)
    local entry = section and section._msuf2CollapsibleEntry
    if entry and entry.featureSwitch then return entry.featureSwitch end
    local enable = W.SectionSwitch(section, "Enable", "Enable")
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    M.BindBoolWidget(ctx, enable,
        function() return Bool(CurrentScope(), "enabled", false) end,
        function(value)
            -- Keep the configured Blizzard fallback when toggling MSUF off.
            Set(CurrentScope(), "enabled", value == true, "rebuild")
            M.Refresh(ctx)
        end,
        ControlMeta(ctx, "field.enabled"))
    enable:SetChecked(Bool(CurrentScope(), "enabled", false))
    return enable
end
local function RefreshFrameBasicsProviderHeader(section)
    local provider = FrameProvider(CurrentScope())
    local usesMSUF = provider == "MSUF"
    local offlineHidden = usesMSUF and Bool(CurrentScope(), "hideOfflineEnabled", false)
    local badges = {
        { text = FrameProviderLabel(CurrentScope()), kind = usesMSUF and "accent" or (provider == "NONE" and "muted" or "info") },
    }
    if usesMSUF then
        badges[#badges + 1] = { text = Bool(CurrentScope(), "showPlayer", true) and "Player shown" or "Player hidden",
            kind = Bool(CurrentScope(), "showPlayer", true) and "info" or "muted" }
        local offlineFaded = not offlineHidden and Bool(CurrentScope(), "offlineFadeEnabled", false)
        local offlineText
        if offlineHidden then
            offlineText = M.Format("Offline %s s", BadgeNumber(Num(CurrentScope(), "hideOfflineDelay", 0)))
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
    local general = b:CollapsibleSection("general", "Basics", 520, false)
    PrepareFrameEnable(ctx, general)
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
            maxTargets = 7,
            offsetY = -10,
            context = CurrentGroupHealthColorContext,
        })
    end
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
    }, { ["*"] = function(s) return BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(general, s[1], s[2], s[3], s[4]), s[5]), s[6], s[7],
        s[8]) end }, nil, msufControls)
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
        generalLeftX, -278, generalLeftW, T.colors.muted)
    if raidManagerHelp and raidManagerHelp.SetWordWrap then raidManagerHelp:SetWordWrap(true) end
    local barShape = AttachGroupFocus(W.Dropdown(general, "Frame bar shape", FRAME_BAR_SHAPE_OPTIONS, min(300, generalRightW)), "bars")
    W.MoveWidget(barShape, general, generalRightX, -278, min(300, generalRightW), "LEFT")
    M.BindDropdownWidget(ctx, barShape,
        function() return Val(CurrentScope(), "frameBarShape", "DEFAULT") end,
        function(value)
            if value ~= "SQUARE" and value ~= "ROUNDED" and value ~= "SLANTED" then value = "DEFAULT" end
            Set(CurrentScope(), "frameBarShape", value, "visual")
            _G.MSUF_ApplyRoundedUnitframes()
            RefreshContext(ctx)
        end,
        ControlMeta(ctx, "basics.frame_bar_shape"))
    msufControls[#msufControls + 1] = barShape
    if M.AddTooltip then
        M.AddTooltip(barShape, "Frame bar shape", M.Format("Choose the Health and Power shape for this frame. Use shared style follows %s.",
            M.NavPath("opt_bars")), { hook = true, owner = "ANCHOR_RIGHT" })
    end
    W.DividerAt(general, -326, generalLeftX, 32)
    W.LabelAt(general, "Offline Members", generalLeftX, -344, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    local hideOfflineEnabled = BindScopeToggle(ctx, AttachGroupFocus(W.SwitchAt(general, "Offline Members", generalLeftX, -370, generalLeftW), "layout"),
        "hideOfflineEnabled", false, "visual")
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
            searchSettingKeys = {
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
            maxTargets = 7,
            context = CurrentGroupHealthColorContext,
            isRelevant = CurrentGroupHealthColorShortcutRelevant,
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
    BindScopeToggle(ctx,
        AttachGroupFocus(W.ToggleAt(opacityOptionsCard, "Keep Absorbs + Prediction Visible", 16, -112, transparencyRightW - 32), "bars"),
        "alphaExcludePredictionBars", false, "visual", "field.alphaExcludePredictionBars")

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
    local section = b:CollapsibleSection("layout_advanced", "Group Layout", GEOMETRY_SECTION_HEIGHT, false)
    local width = section._msuf2Width or b.width or 720
    local inner = width - 40
    local col = (inner - 16) / 2
    local grid = W.ControlCard(section, "Grid", nil, 20, -38, col, 190)
    local growth = W.ControlCard(section, "Growth", nil, col + 36, -38, col, 190)
    BuildGrowthDirectionTiles(ctx, growth, { x = 16, y = -68, tileWidth = 64, tileHeight = 64, gap = 8, advanceCursor = false })
    AttachGroupFocus(ScopeSlider(ctx, grid, "Units per column", 1, 40, 1, col - 64, "unitsPerColumn", 5, "rebuild", 16, -40, col - 64, "LEFT"), "layout")
    AttachGroupFocus(ScopeSlider(ctx, grid, "Max columns", 1, 8, 1, col - 64, "maxColumns", 8, "rebuild", 16, -100, col - 64, "LEFT"), "layout")
    local preserve = BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(grid, "Preserve raid groups", 16, -152, col - 32), "layout"),
        "preserveRaidGroups", false, "rebuild")
    local visibilityRows = {
        {"Collapse empty preserved raid groups", "collapseEmptyGroups"},
        {"Center party frames while solo", "centerSolo"},
        {"Use Party layout for raids up to 5 players", "smallRaidAsParty"},
    }
    if MYTHIC_RAID_SUPPORTED then
        table.insert(visibilityRows, 2, {"Hide groups 5–8 in Mythic raids", "hideMythicGroupsFiveToEight"})
    end
    local missingRows = 4 - #visibilityRows
    local rules = W.ControlCard(section, "Group visibility", nil, 20, -246, inner, 262 - missingRows * 36)
    local organization = {}
    for i, entry in ipairs(visibilityRows) do
        organization[entry[2]] = M.GroupFrameAdditionalSections.ExactScope(BindScopeToggle(ctx, AttachGroupFocus(W.ToggleAt(rules, entry[1], 16, -40 - (i - 1) * 36, inner - 32), "layout"), entry[2], false, "rebuild"), entry[2])
    end
    W.Text(rules, "Group visibility options apply only to their matching Party, Raid, or Mythic Raid scope. Empty groups collapse when Preserve raid groups is enabled.", 16, -188 + missingRows * 36, inner - 32, T.colors.muted)
    TrackSectionRefresh(ctx, section, function()
        local scope = CurrentScope()
        SetOptionEnabled(preserve, scope ~= "party")
        SetOptionEnabled(organization.collapseEmptyGroups, scope ~= "party" and Bool(scope, "preserveRaidGroups", false))
        SetOptionEnabled(organization.hideMythicGroupsFiveToEight, scope == "mythicraid")
        SetOptionEnabled(organization.centerSolo, scope == "party")
        SetOptionEnabled(organization.smallRaidAsParty, scope == "party")
        SetSectionBadgesAndStatus(section, {
            { text = OptionText(GROWTH_VALUES, Val(CurrentScope(), "growth", "DOWN"), "Down"), kind = "accent" },
            { text = M.Format("Grid %s/%s", BadgeNumber(Num(CurrentScope(), "unitsPerColumn", 5)),
                BadgeNumber(Num(CurrentScope(), "maxColumns", 8))), kind = "info" },
        })
    end)
end

local function BuildClassPriorityRows(ctx, parent, width, topY)
    local tokens = "WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST,DEATHKNIGHT,SHAMAN,MAGE,WARLOCK,MONK,DRUID,DEMONHUNTER,EVOKER"
    -- Blizzard's CLASS_SORT_ORDER names exactly the classes this client has (9 on
    -- Classic Era, TBC and WoW Forever, 11 on Mists); RAID_CLASS_COLORS also
    -- carries Death Knight, Monk and Demon Hunter there. The rows keep MSUF's order.
    local sortOrder, present = _G.CLASS_SORT_ORDER, nil
    if type(sortOrder) == "table" and #sortOrder > 0 then
        present = {}
        for i = 1, #sortOrder do present[sortOrder[i]] = true end
    end
    local definitions, byKey = {}, {}
    for token in tokens:gmatch("[^,]+") do
        if present and present[token] or not present and RAID_CLASS_COLORS[token] then
            definitions[#definitions + 1] = { key = token, label = LOCALIZED_CLASS_NAMES_MALE[token] or token }
            byKey[token] = #definitions
        end
    end
    local holder
    local function Save()
        local rows = {}
        for i = 1, #holder.rows do rows[i] = holder.rows[i] end
        table.sort(rows, function(a, b) return a.slotIndex < b.slotIndex end)
        local order = {}
        for i = 1, #rows do order[i] = rows[i].key end
        Set(CurrentScope(), "classOrder", table.concat(order, ","), "rebuild")
    end
    holder = Shared.MakeDragSortRows(parent, definitions, {
        x = 16, y = topY, width = width - 32, rowHeight = 22, gap = 4,
        controlDomain = "group", controlPageKey = ctx.key, controlPath = "sorting.class_priority",
        controlClassification = "setting", onReorder = function()
            M.RunWithHistory("Class priority order", "group:classOrder:" .. CurrentScope(), Save)
        end,
    })
    M.TrackRefresh(ctx, function()
        local seen, slot = {}, 0
        for token in (Conf(CurrentScope()).classOrder or tokens):gmatch("[^,%s]+") do
            local index = byKey[token]
            if index and not seen[index] then
                slot=slot+1
                holder.rows[index].slotIndex=slot
                seen[index]=true
            end
        end
        for i=1,#holder.rows do
            if not seen[i] then
                slot=slot+1
                holder.rows[i].slotIndex=slot
            end
        end
        holder:SnapRows()
        holder:SetRowsEnabled(Conf(CurrentScope()).sortClassPriority == true)
    end)
    return holder
end

local function BuildGFSortingSection(ctx, b)
    local sorting = b:CollapsibleSection("sorting", "Sorting", nil, false)
    local sortingW = sorting._msuf2Width or b.width or 720
    local sortingGap = 16
    local sortingLeftX = 20
    local sortingInnerW = max(320, sortingW - 40)
    local sortingLeftW = floor((sortingInnerW - sortingGap) * 0.52)
    local sortingRightX = sortingLeftX + sortingLeftW + sortingGap
    local sortingRightW = sortingInnerW - sortingLeftW - sortingGap
    local sortCard = W.ControlCard(sorting, "Sort mode", nil, sortingLeftX, -38, sortingLeftW, 218)
    local roleCard = W.ControlCard(sorting, "Role Priority", "Drag rows with mouse to reorder.", sortingRightX, -38, sortingRightW, 192)
    local sortMode = W.Dropdown(sortCard, "Sort Mode", SORT_MODES, min(260, sortingLeftW - 32))
    W.MoveWidget(sortMode, sortCard, 16, -28, min(260, sortingLeftW - 32), "LEFT")
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
    local roleSort = W.ToggleAt(sortCard, "Sort by Role", 16, -86, sortingLeftW - 32)
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
    local playerFirst = BindScopeToggle(ctx, W.ToggleAt(sortCard, "Player first in role", 16, -116, sortingLeftW - 32), "playerFirstInRole", false, "rebuild")
    --- Raid/Mythic only: By Role with Preserve raid groups (and Group + Role) sort
    --- roles inside each raid group; this orders them across the entire raid.
    local raidWideRoles = BindScopeToggle(ctx, W.ToggleAt(sortCard, "Sort roles across entire raid", 16, -146, sortingLeftW - 32), "sortRolesAcrossRaid", false, "rebuild")
    raidWideRoles._msuf2ExactTargetKinds = { groupScope = true }
    raidWideRoles._msuf2ExactTargetContracts = {
        groupScope = {
            raid = "gf_raid.sortRolesAcrossRaid",
            mythicraid = "gf_mythicraid.sortRolesAcrossRaid",
        },
    }
    raidWideRoles._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= "groupScope" then return false end
        local scope = tostring(exactTarget.prepareValue or "")
        local settingKey = raidWideRoles._msuf2ExactTargetContracts.groupScope[scope]
        if not settingKey or tostring(exactTarget.settingKey or "") ~= settingKey then return false end
        M.SetMenuStateValue("gfScope", scope)
        return CurrentScope() == scope
    end
    if M.AddTooltip then
        M.AddTooltip(raidWideRoles, "Sort roles across entire raid",
            "Orders tanks, healers, and damage dealers across the whole raid instead of within each raid group. Raid and Mythic Raid only: applies to By Role together with Preserve raid groups, and to Group + Role.",
            { hook = true, labelHit = true })
    end
    local alphabeticalInRole = BindScopeToggle(ctx,
        W.ToggleAt(sortCard, "Alphabetize names within roles", 16, -176, sortingLeftW - 32),
        "sortAlphabeticalWithinRole", false, "rebuild")
    if M.AddTooltip then
        M.AddTooltip(alphabeticalInRole, "Alphabetize names within roles",
            "Sorts names alphabetically after role priority. Works within each raid group or across the entire raid, according to the role sorting options above. Raid and Mythic Raid only.",
            { hook = true, labelHit = true })
    end
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
        local usesRoles = enabled or currentMode == "GROUP_ROLE"
        if sortMode.SetValue then sortMode:SetValue(currentMode) end
        if roleSort.SetChecked then roleSort:SetChecked(enabled) end
        SetOptionEnabled(playerFirst, usesRoles)
        local raidWideEligible = CurrentScope() ~= "party" and usesRoles
        SetOptionEnabled(raidWideRoles, raidWideEligible)
        SetOptionEnabled(alphabeticalInRole, raidWideEligible)
        if roleRows then
            if roleRows.Refresh then roleRows.Refresh() end
            if roleRows.SetRowsEnabled then roleRows:SetRowsEnabled(usesRoles) end
        end
        local badges = {
            { text = OptionText(SORT_MODES, currentMode, "Index"), kind = "info" },
            { text = usesRoles and "Role order" or "Simple order", kind = usesRoles and "accent" or "muted" },
        }
        if raidWideEligible and Bool(CurrentScope(), "sortRolesAcrossRaid", false) then
            badges[#badges + 1] = { text = "Raid-wide roles", kind = "accent" }
        end
        if raidWideEligible and Bool(CurrentScope(), "sortAlphabeticalWithinRole", false) then
            badges[#badges + 1] = { text = "Alphabetical names", kind = "accent" }
        end
        SetSectionBadgesAndStatus(sorting, badges)
    end
    local classCard = W.ControlCard(sorting, "Class priority", "Drag classes to reorder within the current group and role order.", 20, -280, sortingInnerW, 120)
    -- Measure once during construction, including a wrapped description.
    local classToggleY = -56 - max(16, classCard.subtitle:GetStringHeight())
    M.GroupFrameAdditionalSections.ExactScope(BindScopeToggle(ctx, W.ToggleAt(classCard, "Use class priority", 16, classToggleY, sortingInnerW - 32),
        "sortClassPriority", false, "rebuild"), "sortClassPriority")
    local classRowsY = classToggleY - 40
    local classRows = BuildClassPriorityRows(ctx, classCard, sortingInnerW, classRowsY)
    local classCardHeight = -classRowsY + classRows:GetHeight() + 16
    classCard:SetHeight(classCardHeight)
    classCard._msuf2ContextColorHeight = classCardHeight
    sorting._msuf2CursorY = -280 - classCardHeight
    b:FinishSection(sorting, 24)
    TrackSectionRefresh(ctx, sorting, refreshSortingControls)
end

local function BuildGFScalingSection(ctx, b)
    local scale = b:CollapsibleSection("scaling", "Size & Scaling", 720, false)
    local width = scale._msuf2Width or b.width or 720
    local inner = width - 40
    local col = (inner - 16) / 2
    local frames = {}
    Shared.MakeTabFrames(scale, -64, width, frames, "general", "tier10", "tier20", "tier25", "tier40")
    M.gfSizingTabSelection = M.gfSizingTabSelection or {}
    local tabs, RefreshTabs, ReadTab, SetTab = W.SegmentTabs(ctx, scale, {
        label = "", values = VT("general", "General", "tier10", "1–10", "tier20", "11–20", "tier25", "21–25", "tier40", "26+"),
        width = min(580, inner), frames = frames, defaultTab = "general", x = 20, y = -12,
        get = function() return M.gfSizingTabSelection[CurrentScope()] or "general" end,
        set = function(value) M.gfSizingTabSelection[CurrentScope()] = value end,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    RegisterControl(tabs, ctx, "scaling.workspace_tab", "Size area", "segment", "ephemeral")
    scale._msuf2GuidedSelectTab = function(tab)
        if not frames[tab] then return false end
        SetTab(tab)
        return ReadTab() == tab
    end
    for key, frame in pairs(frames) do frame._msuf2GroupSizingTab = key end
    local tabLabels = { general = "General", tier10 = "1–10 players", tier20 = "11–20 players", tier25 = "21–25 players", tier40 = "26+ players" }
    for key, frame in pairs(frames) do frame._msuf2SearchTitle = M.Tr(tabLabels[key]) end
    local function SizingMeta(key, tab)
        local meta = ControlMeta(ctx, "field." .. key)
        meta.searchPrepareKind, meta.searchPrepareValue = "groupSizingTab", tab
        meta.keywords = "size scaling " .. tabLabels[tab]
        meta.prepareExactSearchTarget = function() return scale._msuf2GuidedSelectTab(tab) end
        return meta
    end
    local baseSlider, baseDropdown, baseToggle = ScopeSlider, ScopeDropdown, BindScopeToggle
    local function ScopeSlider(ctx, parent, label, low, high, step, sliderWidth, key, default, mode, x, y, placeWidth, justify)
        local tab = parent._msuf2GroupSizingTab or "general"
        local meta = SizingMeta(key, tab)
        local control = baseSlider(ctx, parent, label, low, high, step, sliderWidth, key, default, mode, x, y, placeWidth, justify, meta)
        meta.label, meta.kind = label, "slider"
        M.RegisterSearchWidget(control, meta)
        return AttachGroupFocus(M.GroupFrameAdditionalSections.ExactScope(control, key, meta.prepareExactSearchTarget), "layout")
    end
    local function ScopeDropdown(ctx, parent, label, values, sliderWidth, key, default, mode, x, y, placeWidth)
        local meta = SizingMeta(key, "general")
        local control = baseDropdown(ctx, parent, label, values, sliderWidth, key, default, mode, x, y, placeWidth, "LEFT", meta)
        meta.label, meta.kind, meta.values = label, "dropdown", values
        M.RegisterSearchWidget(control, meta)
        return M.GroupFrameAdditionalSections.ExactScope(control, key, meta.prepareExactSearchTarget)
    end
    local function BindScopeToggle(ctx, widget, key, default, mode)
        local meta = SizingMeta(key, "general")
        local control = baseToggle(ctx, widget, key, default, mode, meta)
        meta.kind = "toggle"
        M.RegisterSearchWidget(control, meta)
        return M.GroupFrameAdditionalSections.ExactScope(control, key, meta.prepareExactSearchTarget)
    end
    local general = frames.general
    local sizeCard = W.ControlCard(general, "Base dimensions", "Used before scaling and raid size overrides.", 20, -4, col, 248)
    local modeCard = W.ControlCard(general, "Scaling", "Changes base dimensions, spacing, and resource bar height.", col + 36, -4, col, 248)
    ScopeSlider(ctx, sizeCard, "Width", 40, 300, 1, col - 64, "width", 120, "rebuild", 16, -84, col - 64, "LEFT")
    ScopeSlider(ctx, sizeCard, "Height", 16, 120, 1, col - 64, "height", 40, "rebuild", 16, -142, col - 64, "LEFT")
    ScopeSlider(ctx, sizeCard, "Spacing", 0, 60, 1, col - 64, "spacing", 1, "rebuild", 16, -200, col - 64, "LEFT")
    local mode = ScopeDropdown(ctx, modeCard, "Scale Mode", VT("off", "Off", "manual", "Manual", "auto", "By group size"), col - 32,
        "frameScaleMode", "off", "rebuild", 16, -80, col - 32)
    local manual = ScopeSlider(ctx, modeCard, "Manual scale (%)", 50, 150, 5, col - 64, "frameScaleManual", 100, "rebuild", 16, -166, col - 64, "LEFT")
    local rules = W.ControlCard(general, "Raid size overrides", nil, 20, -270, inner, 158)
    local useTiers = BindScopeToggle(ctx, W.ToggleAt(rules, "Use raid size overrides", 16, -38, inner - 32), "layoutTiersEnabled", false, "rebuild")
    local exclude = BindScopeToggle(ctx, W.ToggleAt(rules, "Exclude hidden groups from group size", 16, -76, inner - 32), "excludeHiddenGroups", false, "rebuild")
    W.Text(rules, "Group size selects both the scaling percentage and raid overrides. Raid overrides are unavailable for Party frames.", 16, -112, inner - 32, T.colors.muted)
    local appearance = W.ControlCard(general, "Resize appearance", nil, 20, -446, inner, 154)
    for i, entry in ipairs({
        {"Scale indicators with frame dimensions", "autoScaleIndicatorsOnResize"},
        {"Scale auras with frame dimensions", "autoScaleAurasOnResize"},
        {"Scale tracked buffs with frame dimensions", "autoScaleTrackedOnResize"},
    }) do
        BindScopeToggle(ctx, W.ToggleAt(appearance, entry[1], 16, -38 - (i - 1) * 36, inner - 32), entry[2], false, "rebuild")
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
    local autoControls, tierControls = {}, {}
    local entries = {
        {prefix="tier10", key="scaleAt10", default=100, count=10},
        {prefix="tier20", key="scaleAt20", default=85, count=20},
        {prefix="tier25", key="scaleAt25", default=80, count=25},
        {prefix="tier40", key="scaleOver25", default=70, count=30},
    }
    for _, entry in ipairs(entries) do
        local tab = frames[entry.prefix]
        local percentage = ScopeSlider(ctx, tab, "Group size scale (%)", 50, 100, 5, inner - 64, entry.key, entry.default, "rebuild", 36, -44, inner - 64, "LEFT")
        BindAutoScalePreview(percentage, entry.count)
        autoControls[#autoControls + 1] = percentage
        W.Text(tab, "The percentage applies in By group size mode. Exact raid dimensions below replace scaled width or height; 0 keeps the scaled base. Spacing and resource bar height still use the scaling percentage.", 20, -104, inner, T.colors.muted)
        local controls = M.GroupFrameAdditionalSections.SizingTier(ctx, tab, entry.prefix, width, SizingMeta)
        for i = 1, #controls do tierControls[#tierControls + 1] = controls[i] end
    end
    TrackSectionRefresh(ctx, scale, function()
        local scalingMode = Val(CurrentScope(), "frameScaleMode", "off")
        local raid = CurrentScope() ~= "party"
        SetOptionEnabled(manual, scalingMode == "manual")
        SetOptionsEnabled(autoControls, scalingMode == "auto")
        SetOptionEnabled(useTiers, raid)
        SetOptionEnabled(exclude, raid)
        local overrides = raid and Bool(CurrentScope(), "layoutTiersEnabled", false)
        for i = 1, #tierControls do
            local control = tierControls[i]
            SetOptionEnabled(control, overrides and (not control._msuf2TierPositionKey or Bool(CurrentScope(), control._msuf2TierPositionKey, false)))
        end
        RefreshTabs()
        SetSectionBadgesAndStatus(scale, {
            { text = OptionText(VT("off", "Off", "manual", "Manual", "auto", "By group size"), scalingMode, "Off"), kind = scalingMode == "off" and "muted" or "info" },
            OnOffBadge(raid and Bool(CurrentScope(), "layoutTiersEnabled", false), "Raid overrides", "Base dimensions"),
        })
    end)
end

local function BuildGFAnchorSection(ctx, b)
    local anchor = b:CollapsibleSection("anchor", "Anchor", 220, false)
    local anchorW = anchor._msuf2Width or b.width or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, anchorW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
    local anchorTo = W.Dropdown(anchor, "Anchor To", function()
        return M.AnchorTargetValues(GF_ANCHOR_TO, Conf(CurrentScope()).anchorToFrame)
    end, anchorControlW)
    M.UnitSectionsShared.PlaceDropdown(anchor, anchorTo, anchorLeftX, -38, anchorControlW)
    M.BindDropdownWidget(ctx, anchorTo,
        function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
        function(v)
            local conf = Conf(CurrentScope())
            local selectedValue1
            if not ((v == "FREE")) then selectedValue1 = v end
            conf.anchorToFrame = selectedValue1
            QueueGF(CurrentScope(), "rebuild")
        end,
        ControlMeta(ctx, "field.anchorToFrame"))
    local anchorPoint = ScopeDropdown(ctx, anchor, "Anchor Point", GF_ANCHOR_POINTS, anchorControlW, "anchorPoint", "CENTER", "rebuild",
        anchorRightX, -38, anchorControlW)
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

local AdditionalSections = M.GroupFrameAdditionalSections

local GROUP_LAYOUT_SECTION_SPECS = {
    {
        sectionId = "general", title = "Basics", height = 520, build = BuildGFGeneralSection,
        prepareShell = function(ctx, section)
            PrepareFrameEnable(ctx, section)
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
    { sectionId = "anchor", title = "Anchor", height = 220, build = BuildGFAnchorSection },
    { sectionId = "scaling", title = "Size & Scaling", height = 720, build = BuildGFScalingSection },
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
        -- Resolve through GroupPage at build time. The desktop Search
        -- collector loads page specs before exercising lazy section builders.
        build = function(ctx, builder) return GP.BuildPortrait(ctx, builder) end,
        prepareShell = function(...) return GP.PreparePortraitShell(...) end,
    },
    { sectionId = "text", title = "Text", height = 690, build = BuildGFTextSection },
    { sectionId = "power", title = "Resource Bar", autoHeight = true, build = BuildGFResourceBarSection,
        prepareShell = function(ctx, sec) M.GroupFrameLayoutSections.PreparePowerSwitch(ctx, sec) end },
    { sectionId = "range", title = "Range Fade", height = 220, build = BuildGFRangeFadeSection,
        prepareShell = function(ctx, sec) M.GroupFrameLayoutSections.PrepareRangeSwitch(ctx, sec) end },
    { sectionId = "transparency", title = "Transparency", autoHeight = true, build = BuildGFTransparencySection },
    { sectionId = "layout_advanced", title = "Group Layout", height = GEOMETRY_SECTION_HEIGHT, build = BuildGFGeometrySection },
    { sectionId = "sorting", title = "Sorting", autoHeight = true, build = BuildGFSortingSection },
    -- clientCapability: the MSUF.Client fact that must be true for the section to
    -- exist, the same capability names Search/MSUF_Menu2_Search_IndexQuery.lua
    -- ties client-only static search rows to. frameScope: the unit or group scope
    -- the section needs (M.SupportsFrameScope), e.g. boss units for allied bosses.
    {
        sectionId = "buff_coverage", title = "Buff coverage (Forever)", height = 656, clientCapability = "IsForever", build = AdditionalSections.BuffCoverage,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "buffCoverageEnabled", "Show buff coverage icons", "visual")
        end,
    },
    {
        sectionId = "name_bar", title = "Name strip", height = 300, build = AdditionalSections.NameBar,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "nameBarEnabled", "Show names on a strip above the health bar", "rebuild")
        end,
    },
    {
        sectionId = "party_targets", title = "Member targets", height = 456, groupScope = "party", build = AdditionalSections.Targets,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "targetsEnabled", "Enable", "rebuild")
        end,
    },
    {
        sectionId = "group_pets", title = "Pet frames", height = 546, build = AdditionalSections.Pets,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "petsEnabled", "Enable", "rebuild")
        end,
    },
    {
        sectionId = "friendly_bosses", title = "Allied boss frames", height = 536, frameScope = "boss", build = AdditionalSections.FriendlyBosses,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "friendlyBossEnabled", "Enable", "rebuild")
        end,
    },
    {
        sectionId = "healer_mana", title = "Healer mana bars", height = 520, build = AdditionalSections.HealerMana,
        prepareShell = function(ctx, section)
            AdditionalSections.PrepareSwitch(ctx, section, "healerManaEnabled", "Enable", "rebuild")
        end,
    },
}

local function BuildGFLayout(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
    local client = MSUF.Client
    for i = 1, #GROUP_LAYOUT_SECTION_SPECS do
        local spec = GROUP_LAYOUT_SECTION_SPECS[i]
        local capability, frameScope = spec.clientCapability, spec.frameScope
        if type(spec.build) == "function" and (capability == nil or (client and client[capability] == true))
            and (spec.groupScope == nil or spec.groupScope == CurrentScope())
            and (frameScope == nil or not M.SupportsFrameScope or M.SupportsFrameScope(frameScope)) then
        if type(buildLazy) == "function" then buildLazy(ctx, b, nil, spec)
        else spec.build(ctx, b) end
        end
    end
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_layout", { title = "MSUF Group Layout", build = BuildGFLayout, version = 31,
    variantKey = CurrentScope, viewStateKeys = { gfScope = true } })
