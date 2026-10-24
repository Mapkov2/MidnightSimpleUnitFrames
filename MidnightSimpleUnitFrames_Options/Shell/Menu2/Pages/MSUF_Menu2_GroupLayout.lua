-- Menu2 Group Layout page: builds secure-header layout controls for party and raid frames.
-- UI writes must delegate rebuild/defer behavior to GroupFrame runtime helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Shared = M.UnitSectionsShared
local W = M.Widgets
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.GroupOptions()
local CUSTOM_OPTIONS = Schema.UnitOptions()
local MIXED_OPTIONS = { bind = function(ctx, widget, row, kind)
    local options = (row.meta or row.bind) and CUSTOM_OPTIONS or ROW_OPTIONS
    options.bind(ctx, widget, row, kind)
end }
local T = M.Theme
local GP = M.GroupPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local SCOPE_VALUES, GROWTH_VALUES, SORT_MODES, GF_ANCHOR_TO = GP.SCOPE_VALUES or {}, GP.GROWTH_VALUES or {}, GP.SORT_MODES or {}, GP.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = GP.GF_ANCHOR_POINTS or {}
local GROUP_FRAME_PROVIDER_VALUES = GP.GROUP_FRAME_PROVIDER_VALUES or {}
local GROUP_RAID_MANAGER_VALUES = GP.GROUP_RAID_MANAGER_VALUES or {}
local Conf, Val, QueueGF, Set, Bool, Num, ScopeSection = GP.Conf, GP.Val, GP.QueueGF, GP.Set, GP.Bool, GP.Num, GP.ScopeSection
local CurrentScope = GP.CurrentScope
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
    return Schema.Build(ctx, parent, {
        { "toggle", key, false, { label, x, y, width }, domain = "visual",
            beforeBind = function(widget) AttachGroupFocus(widget, "bars") end,
            bind = function(widget)
                GP.BindExclusiveScopeToggle(ctx, widget, key, peerKey, historyLabel, "healthFillMode", function()
                    if M.RequestRefresh then M.RequestRefresh(ctx, "group-health-fill-mode") end
                end)
                Schema.Owned(widget, "group", "visual")
            end, scope = "group" },
    }, CUSTOM_OPTIONS)[key]
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
    local enable = Schema.Build(ctx, section, {
        { "sectionSwitch", "enable", nil, { "Enable", "Enable" }, get = function() return Bool(CurrentScope(), "enabled", false) end,
            set = function(value)
                -- Keep the configured Blizzard fallback when toggling MSUF off.
                Set(CurrentScope(), "enabled", value == true, "rebuild")
                M.Refresh(ctx)
            end,
            meta = ControlMeta(ctx, "field.enabled"), domain = "rebuild",
            flagsBefore = { _msuf2GroupFrameGateAlwaysEnabled = true }, scope = "group" },
    }, CUSTOM_OPTIONS)["enable"]
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
local function BuildProviderControls(ctx, general, generalLeftX, generalLeftW, generalRightX, generalRightW)
    local heading = W.LabelAt(general, "Behavior", generalRightX, -38, generalRightW, "GameFontNormalSmall", T.colors.accent)
    Schema.Custom(heading, {
        id = "menu2.gf_layout.basics.behavior_title", kind = "font", scope = "group", applyDomain = "presentation", owner = heading })
    local providerControls = Schema.Build(ctx, general, {
        { "dropdown", "frameProvider", nil, { "Frames used in this scope", GROUP_FRAME_PROVIDER_VALUES, min(300, generalLeftW) },
            get = function() return FrameProvider(CurrentScope()) end,
            set = function(value)
                SetFrameProvider(CurrentScope(), value)
                RefreshContext(ctx)
            end,
            meta = ControlMeta(ctx, "basics.frame_provider"), domain = "rebuild",
            beforeBind = function(widget)
                AttachGroupFocus(widget, "layout")
                W.MoveWidget(widget, general, generalLeftX, -64, min(300, generalLeftW), "LEFT")
                widget._msuf2GroupFrameGateAlwaysEnabled = true
            end, scope = "group" },
        { "text", "menu2.gf_layout.basics.providerHelp", nil,
            { "Choose MSUF, follow WoW's own Blizzard frame settings, force Blizzard frames, or hide both. Party, Raid, and Mythic Raid are independent.",
            generalRightX, -58, generalRightW, T.colors.muted }, scope = "group" },
    }, CUSTOM_OPTIONS)
    local frameProvider = providerControls["frameProvider"]
    if M.AddTooltip then
        M.AddTooltip(frameProvider,
            function() return M.Format("%s frame provider", ScopeLabel()) end,
            function() return FrameProviderTooltip(CurrentScope()) end,
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local providerHelp = providerControls["menu2.gf_layout.basics.providerHelp"]
    if providerHelp and providerHelp.SetWordWrap then providerHelp:SetWordWrap(true) end
end

local function BuildGFGeneralSection(ctx, b)
    local general = b:CollapsibleSection("general", "Basics", 520, false)
    if general._msuf2CollapsibleEntry then Schema.Section(general, "group") end
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
    BuildProviderControls(ctx, general, generalLeftX, generalLeftW, generalRightX, generalRightW)
    local msufControls = {}
    msufControls[#msufControls + 1] = BindExclusiveFillToggle(ctx, general, "Smooth health fill",
        generalRightX, -124, generalRightToggleW, "smoothFill", "chunkedFill", "Smooth group health fill")
    msufControls[#msufControls + 1] = BindExclusiveFillToggle(ctx, general, "Chunked health loss",
        generalRightX, -154, generalRightToggleW, "chunkedFill", "smoothFill", "Chunked group health loss")
    local rows = {
        { "toggle", "showPlayer", true, { "Show player", generalLeftX, -124, generalLeftToggleW }, domain = "rebuild", scope = "group" },
        { "toggle", "showSolo", false, { "Show while solo", generalLeftX, -154, generalLeftToggleW }, domain = "rebuild", scope = "group" },
        { "toggle", "hideInHousing", false, { "Hide in Housing", generalLeftX, -184, generalLeftToggleW }, domain = "visual", scope = "group" },
        { "toggle", "reverseFill", false, { "Reverse fill direction", generalRightX, -184, generalRightToggleW }, domain = "visual",
            beforeBind = function(widget) AttachGroupFocus(widget, "bars") end, scope = "group" },
        { "toggle", "hideInClientScene", true, { "Hide during client scene", generalRightX, -214, generalRightToggleW }, domain = "visual", scope = "group" },
        { "toggle", "clickCastEnabled", true, { "Click casting / Clique", generalRightX, -244, generalRightToggleW }, domain = "rebuild", scope = "group" },
    }
    for _, row in ipairs(rows) do
        row.beforeBind = row.beforeBind or function(widget) AttachGroupFocus(widget, "layout") end
    end
    local basics = Schema.Build(ctx, general, rows, ROW_OPTIONS)
    for _, row in ipairs(rows) do msufControls[#msufControls + 1] = basics[row[2]] end
    --- Blizzard's Raid Manager tab is one shared frame, so this control is deliberately
    --- not scope-bound: it reads and writes Party, Raid and Mythic Raid together. It also
    --- stays live on the Blizzard providers, where MSUF's ownership pass never hides the
    --- tab -- so it must not join msufControls, which grey out when the provider is not MSUF.
    local managerControls = Schema.Build(ctx, general, {
        { "dropdown", "raidManager", nil, { "Blizzard Raid Manager", GROUP_RAID_MANAGER_VALUES, min(300, generalLeftW) },
            get = function() return RaidManagerMode() end,
            set = function(value) SetRaidManagerMode(value) end,
            meta = ControlMeta(ctx, "basics.raid_manager"), domain = "visual",
            beforeBind = function(widget)
                AttachGroupFocus(widget, "layout")
                W.MoveWidget(widget, general, generalLeftX, -220, min(300, generalLeftW), "LEFT")
                widget._msuf2GroupFrameGateAlwaysEnabled = true
            end, scope = "group" },
        { "text", "menu2.gf_layout.basics.raidManagerHelp", nil,
            { "Shared by Party, Raid, and Mythic Raid. Automatic keeps the tab hidden while MSUF provides the group frames.", generalLeftX,
            -278, generalW - generalLeftX - 32, T.colors.muted }, scope = "group" },
    }, CUSTOM_OPTIONS)
    local raidManager = managerControls["raidManager"]
    if M.AddTooltip then
        M.AddTooltip(raidManager,
            function() return M.Tr("Blizzard Raid Manager") end,
            function()
                return M.Tr("Blizzard's tab at the left screen edge with ready check, raid markers, and role filters. One shared frame, so " ..
                    "this setting is the same for Party, Raid, and Mythic Raid.")
            end,
            { hook = true, owner = "ANCHOR_RIGHT" })
    end
    local raidManagerHelp = managerControls["menu2.gf_layout.basics.raidManagerHelp"]
    if raidManagerHelp and raidManagerHelp.SetWordWrap then raidManagerHelp:SetWordWrap(true) end
    W.DividerAt(general, -326, generalLeftX, 32)
    local heading = W.LabelAt(general, "Offline Members", generalLeftX, -344, generalLeftW, "GameFontNormalSmall", T.colors.accent)
    Schema.Custom(heading, {
        id = "menu2.gf_layout.basics.offline_title", kind = "font", scope = "group", applyDomain = "presentation", owner = heading })
    local offlineControls = Schema.Build(ctx, general, {
        { "switch", "hideOfflineEnabled", false, { "Offline Members", generalLeftX,
        -370, generalLeftW }, domain = "visual",
        beforeBind = function(widget) AttachGroupFocus(widget, "layout") end, scope = "group" },
        { "toggle", "hideOfflineInCombat", false, { "Hide offline in combat", generalRightX, -370, generalRightToggleW }, domain = "visual",
            beforeBind = function(widget) AttachGroupFocus(widget, "layout") end, scope = "group" },
        { "slider", "hideOfflineDelay", 0, { "Hide offline after", 0, 120, 1,
        offlineSliderW }, { generalLeftX,
        -404, offlineSliderW, "LEFT" }, domain = "visual", scope = "group" },
    }, ROW_OPTIONS)
    local hideOfflineEnabled = offlineControls["hideOfflineEnabled"]
    local hideOfflineCombat = offlineControls["hideOfflineInCombat"]
    local hideOffline = AttachGroupFocus(offlineControls["hideOfflineDelay"], "layout")
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
        Schema.Owned(generalNoticeButton, "group", "rebuild")
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
                generalNotice:SetMessage(M.Format("%s forces Blizzard frames visible. Use this only when the normal WoW settings option does not show them.",
                    ScopeLabel()), "warning")
            elseif provider == "NONE" then
                generalNotice:SetMessage(M.Format("%s hides both MSUF and Blizzard group frames.", ScopeLabel()), "warning")
            end
        end
    end
    TrackSectionRefresh(ctx, general, RefreshHideOfflineState)
end

-- Text, Resource Bar and Range Fade are built by M.GroupFrameLayoutSections (the Bars page file), resolved when the section builds.
local function DelegatedSection(name)
    return function(ctx, b)
        local layoutSections = M.GroupFrameLayoutSections
        if layoutSections and layoutSections[name] then return layoutSections[name](ctx, b) end
    end
end
local BuildGFTextSection = DelegatedSection("BuildText")
local BuildGFResourceBarSection = DelegatedSection("BuildResourceBar")
local BuildGFRangeFadeSection = DelegatedSection("BuildRangeFade")

local function BuildGFTransparencySection(ctx, b)
    -- Keep Group Frame opacity controls visually aligned with the Unitframe
    -- Transparency section while binding them to the currently selected scope.
    local transparency = b:CollapsibleSection("transparency", "Transparency", nil, false)
    if transparency._msuf2CollapsibleEntry then Schema.Section(transparency, "group") end
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
    local opacityCards = Schema.Build(ctx, transparency, {
        { "card", "menu2.gf_layout.transparency.healthOpacityCard", nil,
        { "Health Bar", nil, transparencyLeftX, transparencyCardY,
        transparencyCardW, transparencyCardH }, domain = "layout", scope = "group" },
        { "card", "menu2.gf_layout.transparency.opacityOptionsCard", nil,
        { "Options", nil, transparencyRightX, transparencyCardY,
        transparencyRightW, transparencyCardH }, domain = "layout", scope = "group" },
        { "card", "menu2.gf_layout.transparency.oocCard", nil, { "Out of Combat",
        nil, transparencyLeftX, transparencyCardY,
        transparencyInnerW, transparencyCardH }, domain = "layout", scope = "group" },
    })
    local healthOpacityCard = opacityCards["menu2.gf_layout.transparency.healthOpacityCard"]
    local opacityOptionsCard = opacityCards["menu2.gf_layout.transparency.opacityOptionsCard"]
    local oocCard = opacityCards["menu2.gf_layout.transparency.oocCard"]
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(healthOpacityCard, CurrentGroupHealthColorRefs, {
            title = "Group Health Bar Colors",
            note = function()
                return GroupHealthColorNote("Foreground follows the selected group color mode; editable group colors are shared by Party, Raid and Mythic " ..
                    "Raid.")
            end,
            historySource = "menu:group-transparency-colors",
            maxTargets = 7,
            context = CurrentGroupHealthColorContext,
            isRelevant = CurrentGroupHealthColorShortcutRelevant,
        })
    end
    local function AddAlphaSlider(parent, width, spec)
        local slider = Schema.Build(ctx, parent, {
            { "slider", spec.key, spec.default, { spec.label, 0, 1, 0.05, width },
                get = function() return Num(CurrentScope(), spec.key, spec.default) end,
                set = function(value) Set(CurrentScope(), spec.key, tonumber(value) or spec.default, "visual") end,
                meta = ControlMeta(ctx, "field." .. tostring(spec.key)), domain = "visual",
                beforeBind = function(widget)
                    M.UsePercentInput(widget)
                end, scope = "group" },
        }, CUSTOM_OPTIONS)[spec.key]
        W.MoveWidget(slider, parent, 16, spec.y, width - 58, "LEFT")
        return AttachGroupFocus(slider, "bars")
    end
    AddAlphaSlider(healthOpacityCard, transparencyCardW, { label = "Foreground", key = "hpBarAlpha", default = 1, y = -54 })
    AddAlphaSlider(healthOpacityCard, transparencyCardW, { label = "Background", key = "hpBgAlpha", default = 0.85, y = -112 })
    Schema.Build(ctx, opacityOptionsCard, {
        { "toggle", "alphaExcludeTextPortrait", false, { "Keep text + portrait visible", 16, -62, transparencyRightW - 32 },
            domain = "visual", beforeBind = function(widget) AttachGroupFocus(widget, "bars") end, scope = "group" },
        { "toggle", "alphaExcludePredictionBars", false, { "Keep Absorbs + Prediction Visible", 16, -112, transparencyRightW - 32 },
            domain = "visual", beforeBind = function(widget) AttachGroupFocus(widget, "bars") end, scope = "group" },
    }, ROW_OPTIONS)

    -- Out of Combat tab: whole-member-frame fade; min-composed with range and
    -- offline fades at runtime (strongest fade wins). Slider greys while off.
    Schema.Build(ctx, oocCard, {
        { "toggle", "oocFadeEnabled", false, { "Fade frame out of combat", 16, -54, transparencyCardW + 40 }, domain = "visual",
            beforeBind = function(widget) AttachGroupFocus(widget, "bars") end, scope = "group" },
    }, ROW_OPTIONS)
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
    for _, card in ipairs({ healthOpacityCard, opacityOptionsCard, oocCard }) do
        card._msuf2ExactTabView = {
            kind = "groupTransparencyTab", value = card == oocCard and "ooc" or "combat",
            select = function(value)
                transparencyTab = value
                ApplyTransparencyTab()
            end,
        }
    end
    Schema.Build(ctx, transparency, {
        { "scopebar", "transparencyState", nil, { {
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
    } }, domain = "menuState", beforeBind = function(widget)
                if RegisterControl then RegisterControl(widget, ctx, "transparency.state_selector", "Editing", "segment", "ephemeral") end
            end, scope = "group" },
    })
    ApplyTransparencyTab()
    if b.FinishSection then b:FinishSection(transparency, 48) end
end

local function BuildGFGeometrySection(ctx, b)
    local section = b:CollapsibleSection("layout_advanced", "Group Layout", GEOMETRY_SECTION_HEIGHT, false)
    if section._msuf2CollapsibleEntry then Schema.Section(section, "group") end
    local width = section._msuf2Width or b.width or 720
    local inner = width - 40
    local col = (inner - 16) / 2
    local geometryCards = Schema.Build(ctx, section, {
        { "card", "menu2.gf_layout.geometry.grid", nil, { "Grid", nil, 20, -38, col, 190 }, domain = "layout", scope = "group" },
        { "card", "menu2.gf_layout.geometry.growth", nil, { "Growth", nil, col + 36, -38, col, 190 }, domain = "layout", scope = "group" },
    })
    local grid = geometryCards["menu2.gf_layout.geometry.grid"]
    local growth = geometryCards["menu2.gf_layout.geometry.growth"]
    local growthTiles = BuildGrowthDirectionTiles(ctx, growth, { x = 16, y = -68, tileWidth = 64, tileHeight = 64, gap = 8, advanceCursor = false })
    for _, tile in ipairs({ growthTiles:GetChildren() }) do Schema.Owned(tile, "group", "layout") end
    local gridControls = Schema.Build(ctx, grid, {
        { "slider", "unitsPerColumn", 5, { "Units per column", 1, 40, 1, col - 64 }, { 16, -40, col - 64, "LEFT" }, domain = "rebuild" },
        { "slider", "maxColumns", 8, { "Max columns", 1, 8, 1, col - 64 }, { 16, -100, col - 64, "LEFT" }, domain = "rebuild" },
        { "toggle", "preserveRaidGroups", false, { "Preserve raid groups", 16, -152, col - 32 },
            domain = "rebuild", beforeBind = function(widget) AttachGroupFocus(widget, "layout") end },
    }, ROW_OPTIONS)
    AttachGroupFocus(gridControls.unitsPerColumn, "layout")
    AttachGroupFocus(gridControls.maxColumns, "layout")
    local preserve = gridControls.preserveRaidGroups
    local visibilityRows = {
        {"Collapse empty preserved raid groups", "collapseEmptyGroups"},
        {"Center party frames while solo", "centerSolo"},
        {"Use Party layout for raids up to 5 players", "smallRaidAsParty"},
    }
    if MYTHIC_RAID_SUPPORTED then
        table.insert(visibilityRows, 2, {"Hide groups 5–8 in Mythic raids", "hideMythicGroupsFiveToEight"})
    end
    local missingRows = 4 - #visibilityRows
    local rules = Schema.Build(ctx, section, { { "card", "menu2.gf_layout.geometry.rules", nil, { "Group visibility", nil, 20,
        -246, inner, 262 - missingRows * 36 }, domain = "layout", scope = "group" }, })["menu2.gf_layout.geometry.rules"]
    local rows = {}
    for i, entry in ipairs(visibilityRows) do
        rows[#rows + 1] = { "toggle", entry[2], false, { entry[1], 16, -40 - (i - 1) * 36, inner - 32 },
            domain = "rebuild", beforeBind = function(widget) AttachGroupFocus(widget, "layout") end }
    end
    rows[#rows + 1] = { "text", "menu2.gf_layout.geometry.visibility_help", nil,
        { "Group visibility options apply only to their matching Party, Raid, or Mythic Raid scope. Empty groups " ..
            "collapse when Preserve raid groups is enabled.",
            16, -188 + missingRows * 36, inner - 32, T.colors.muted }, scope = "group" }
    local organization = Schema.Build(ctx, rules, rows, ROW_OPTIONS)
    for _, entry in ipairs(visibilityRows) do M.GroupFrameAdditionalSections.ExactScope(organization[entry[2]], entry[2]) end
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
    local sortOrder, present = CLASS_SORT_ORDER, nil
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
    Schema.Custom(holder, { id = "menu2.gf_layout.sorting.class_priority", kind = "dragSort",
        scope = "group", applyDomain = "rebuild", owner = holder })
    for _, row in ipairs(holder.rows) do Schema.Owned(row.frame, "group", "rebuild") end
    return holder
end

local function BuildGFSortingSection(ctx, b)
    local sorting = b:CollapsibleSection("sorting", "Sorting", nil, false)
    if sorting._msuf2CollapsibleEntry then Schema.Section(sorting, "group") end
    local sortingW = sorting._msuf2Width or b.width or 720
    local sortingGap = 16
    local sortingLeftX = 20
    local sortingInnerW = max(320, sortingW - 40)
    local sortingLeftW = floor((sortingInnerW - sortingGap) * 0.52)
    local sortingRightX = sortingLeftX + sortingLeftW + sortingGap
    local sortingRightW = sortingInnerW - sortingLeftW - sortingGap
    local sortingCards = Schema.Build(ctx, sorting, {
        { "card", "menu2.gf_layout.sorting.sortCard", nil, { "Sort mode", nil, sortingLeftX, -38, sortingLeftW, 218 }, domain = "layout", scope = "group" },
        { "card", "menu2.gf_layout.sorting.roleCard", nil, { "Role Priority",
        "Drag rows with mouse to reorder.", sortingRightX, -38, sortingRightW, 192 }, domain = "layout", scope = "group" },
    })
    local sortCard = sortingCards["menu2.gf_layout.sorting.sortCard"]
    local roleCard = sortingCards["menu2.gf_layout.sorting.roleCard"]
    local refreshSortingControls
    local sortControls = Schema.Build(ctx, sortCard, {
        { "dropdown", "sortMode", nil, { "Sort Mode", SORT_MODES, min(260, sortingLeftW - 32) }, get = function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode end
            return conf.sortByRole and "ROLE" or "INDEX"
        end,
            set = function(v)
                local conf = Conf(CurrentScope())
                conf.sortMode = v or "INDEX"
                conf.sortByRole = (conf.sortMode == "ROLE")
                QueueGF(CurrentScope(), "rebuild")
                if refreshSortingControls then refreshSortingControls() end
            end,
            meta = ControlMeta(ctx, "field.sortMode"), domain = "rebuild",
            beforeBind = function(widget)
                W.MoveWidget(widget, sortCard, 16, -28, min(260, sortingLeftW - 32), "LEFT")
                if widget._msuf2Title then
                    widget._msuf2Title:ClearAllPoints()
                    widget._msuf2Title:SetPoint("LEFT", widget, "RIGHT", 8, 0)
                    widget._msuf2Title:SetJustifyH("LEFT")
                    widget._msuf2Title:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
                end
            end, scope = "group" },
        { "toggle", "roleSort", nil, { "Sort by Role", 16, -86, sortingLeftW - 32 }, get = function()
            local conf = Conf(CurrentScope())
            if conf.sortMode then return conf.sortMode == "ROLE" end
            return conf.sortByRole and true or false
        end,
            set = function(v)
                local conf = Conf(CurrentScope())
                conf.sortByRole = v and true or false
                conf.sortMode = v and "ROLE" or "INDEX"
                QueueGF(CurrentScope(), "rebuild")
                if refreshSortingControls then refreshSortingControls() end
            end,
            meta = ControlMeta(ctx, "field.sortByRole"), domain = "rebuild", scope = "group" },
        { "toggle", "playerFirstInRole", false, { "Player first in role", 16, -116, sortingLeftW - 32 }, domain = "rebuild", scope = "group" },
        { "toggle", "sortRolesAcrossRaid", false, { "Sort roles across entire raid", 16, -146, sortingLeftW - 32 }, domain = "rebuild", scope = "group" },
        { "toggle", "sortAlphabeticalWithinRole", false,
        { "Alphabetize names within roles", 16, -176, sortingLeftW - 32 }, domain = "rebuild", scope = "group" },
    }, MIXED_OPTIONS)
    local sortMode = sortControls["sortMode"]
    local roleSort = sortControls["roleSort"]
    local playerFirst = sortControls["playerFirstInRole"]
    --- Raid/Mythic only: By Role with Preserve raid groups (and Group + Role) sort
    --- roles inside each raid group; this orders them across the entire raid.
    local raidWideRoles = sortControls["sortRolesAcrossRaid"]
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
            "Orders tanks, healers, and damage dealers across the whole raid instead of within each raid group. Raid and " ..
                "Mythic Raid only: applies to By Role together with Preserve raid groups, and to Group + Role.",
            { hook = true, labelHit = true })
    end
    local alphabeticalInRole = sortControls["sortAlphabeticalWithinRole"]
    if M.AddTooltip then
        M.AddTooltip(alphabeticalInRole, "Alphabetize names within roles",
            "Sorts names alphabetically after role priority. Works within each raid group or across the entire raid, " ..
                "according to the role sorting options above. Raid and Mythic Raid only.",
            { hook = true, labelHit = true })
    end
    local roleRows = BuildRoleOrderRows(ctx, roleCard, {
        x = 16,
        y = -66,
        width = min(250, sortingRightW - 32),
        advanceCursor = false,
    })
    Schema.Custom(roleRows, { id = "menu2.gf_layout.sorting.role_priority", kind = "dragSort",
        scope = "group", applyDomain = "rebuild", owner = roleRows })
    for _, row in ipairs(roleRows.rows) do Schema.Owned(row.frame, "group", "rebuild") end
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
    local classCard = Schema.Build(ctx, sorting, {
        { "card", "menu2.gf_layout.sorting.classCard", nil, { "Class priority",
            "Drag classes to reorder within the current group and role order.", 20, -280, sortingInnerW, 120 }, domain = "layout", scope = "group" },
    })["menu2.gf_layout.sorting.classCard"]
    -- Measure once during construction, including a wrapped description.
    local classToggleY = -56 - max(16, classCard.subtitle:GetStringHeight())
    M.GroupFrameAdditionalSections.ExactScope(Schema.Build(ctx, classCard, { { "toggle", "sortClassPriority", false, { "Use class priority", 16, classToggleY,
        sortingInnerW - 32 }, domain = "rebuild", scope = "group" } }, ROW_OPTIONS)["sortClassPriority"], "sortClassPriority")
    local classRowsY = classToggleY - 40
    local classRows = BuildClassPriorityRows(ctx, classCard, sortingInnerW, classRowsY)
    local classCardHeight = -classRowsY + classRows:GetHeight() + 16
    classCard:SetHeight(classCardHeight)
    classCard._msuf2ContextColorHeight = classCardHeight
    sorting._msuf2CursorY = -280 - classCardHeight
    b:FinishSection(sorting, 24)
    TrackSectionRefresh(ctx, sorting, refreshSortingControls)
end

local function BuildScalingGeneral(ctx, general, col, inner, sizingOptions)
    local sizingCards = Schema.Build(ctx, general, {
        { "card", "menu2.gf_layout.scaling.sizeCard", nil, { "Base dimensions",
        "Used before scaling and raid size overrides.", 20, -4, col, 248 }, domain = "layout", scope = "group" },
        { "card", "menu2.gf_layout.scaling.modeCard", nil, { "Scaling",
        "Changes base dimensions, spacing, and resource bar height.", col + 36, -4, col, 248 }, domain = "layout", scope = "group" },
    })
    local sizeCard = sizingCards["menu2.gf_layout.scaling.sizeCard"]
    local modeCard = sizingCards["menu2.gf_layout.scaling.modeCard"]
    Schema.Build(ctx, sizeCard, {
        { "slider", "width", 120, { "Width", 40, 300, 1, col - 64 }, { 16, -84, col - 64, "LEFT" }, domain = "rebuild", scope = "group" },
        { "slider", "height", 40, { "Height", 16, 120, 1, col - 64 }, { 16, -142, col - 64, "LEFT" }, domain = "rebuild", scope = "group" },
        { "slider", "spacing", 1, { "Spacing", 0, 60, 1, col - 64 }, { 16, -200, col - 64, "LEFT" }, domain = "rebuild", scope = "group" },
    }, sizingOptions)
    local scaleControls = Schema.Build(ctx, modeCard, {
        { "dropdown", "frameScaleMode", "off", { "Scale Mode", VT("off", "Off", "manual", "Manual",
        "auto", "By group size"), col - 32 }, { 16, -80, col - 32, "LEFT" },
        domain = "rebuild", scope = "group" },
        { "slider", "frameScaleManual", 100, { "Manual scale (%)", 50, 150, 5, col - 64 }, { 16,
        -166, col - 64, "LEFT" }, domain = "rebuild", scope = "group" },
    }, sizingOptions)
    local manual = scaleControls["frameScaleManual"]
    local rules = Schema.Build(ctx, general, { { "card", "menu2.gf_layout.scaling.rules", nil, { "Raid size overrides", nil, 20,
        -270, inner, 158 }, domain = "layout", scope = "group" }, })["menu2.gf_layout.scaling.rules"]
    local tierOptions = Schema.Build(ctx, rules, {
        { "toggle", "layoutTiersEnabled", false, { "Use raid size overrides", 16, -38, inner - 32 }, domain = "rebuild", scope = "group" },
        { "toggle", "excludeHiddenGroups", false, { "Exclude hidden groups from group size", 16, -76, inner - 32 }, domain = "rebuild", scope = "group" },
        { "text", "menu2.gf_layout.scaling.size_help", nil,
            { "Group size selects both the scaling percentage and raid overrides. Raid overrides are unavailable for Party frames.", 16,
            -112, inner - 32, T.colors.muted }, scope = "group" },
    }, sizingOptions)
    local useTiers = tierOptions["layoutTiersEnabled"]
    local exclude = tierOptions["excludeHiddenGroups"]
    local appearance = Schema.Build(ctx, general, { { "card", "menu2.gf_layout.scaling.appearance", nil, { "Resize appearance",
        nil, 20, -446, inner, 154 }, domain = "layout", scope = "group" }, })["menu2.gf_layout.scaling.appearance"]
    local appearanceRows = {}
    for i, entry in ipairs({
        {"Scale indicators with frame dimensions", "autoScaleIndicatorsOnResize"},
        {"Scale auras with frame dimensions", "autoScaleAurasOnResize"},
        {"Scale tracked buffs with frame dimensions", "autoScaleTrackedOnResize"},
    }) do
        appearanceRows[#appearanceRows + 1] = { "toggle", entry[2], false, { entry[1], 16, -38 - (i - 1) * 36, inner - 32 }, domain = "rebuild" }
    end
    Schema.Build(ctx, appearance, appearanceRows, sizingOptions)
    return manual, useTiers, exclude
end

local function BuildGFScalingSection(ctx, b)
    local scale = b:CollapsibleSection("scaling", "Size & Scaling", 720, false)
    if scale._msuf2CollapsibleEntry then Schema.Section(scale, "group") end
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
    Schema.Owned(tabs, "group", "menuState")
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
    local sizingOptions = Schema.UnitOptions()
    sizingOptions.bind = function(bindCtx, widget, row, kind)
        local meta = SizingMeta(row[2], row.tab or "general")
        local binder = kind == "slider" and GP.BindScopeSlider or kind == "toggle" and GP.BindScopeToggle or GP.BindScopeDropdown
        binder(bindCtx, widget, row[2], row[3], row.domain, meta)
        if kind ~= "toggle" then meta.label = row[4][1] end
        meta.kind = kind
        if kind == "dropdown" then meta.values = row[4][2] end
        M.RegisterSearchWidget(widget, meta)
        M.GroupFrameAdditionalSections.ExactScope(widget, row[2], meta.prepareExactSearchTarget)
        if kind == "slider" then AttachGroupFocus(widget, "layout") end
        Schema.Owned(widget, "group", row.domain)
    end
    local manual, useTiers, exclude = BuildScalingGeneral(ctx, frames.general, col, inner, sizingOptions)
    local function BeginAutoScalePreview(slider, previewCount)
        if not (slider and previewCount and type(M.SetGFScalingBreakpointPreview) == "function") then return end
        if Val(CurrentScope(), "frameScaleMode", "off") ~= "auto" then return end
        if (InCombatLockdown and InCombatLockdown()) or MSUF.PublicGlobals.MSUF_InCombat == true then return end
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
        local percentage = Schema.Build(ctx, tab, { { "slider", entry.key, entry.default, { "Group size scale (%)", 50, 100, 5, inner - 64 }, { 36, -44,
            inner - 64, "LEFT" }, domain = "rebuild", tab = entry.prefix, scope = "group" } }, sizingOptions)[entry.key]
        BindAutoScalePreview(percentage, entry.count)
        autoControls[#autoControls + 1] = percentage
        Schema.Build(ctx, tab, {
            { "text", "menu2.gf_layout.scaling." .. entry.prefix .. ".help", nil,
                { "The percentage applies in By group size mode. Exact raid dimensions below replace scaled width or height; 0 " ..
                    "keeps the scaled base. Spacing and resource bar height still use the scaling percentage.",
                20, -104, inner, T.colors.muted }, scope = "group" },
        })
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
            { text = OptionText(VT("off", "Off", "manual", "Manual", "auto", "By group size"), scalingMode, "Off"),
                kind = scalingMode == "off" and "muted" or "info" },
            OnOffBadge(raid and Bool(CurrentScope(), "layoutTiersEnabled", false), "Raid overrides", "Base dimensions"),
        })
    end)
end

local function BuildGFAnchorSection(ctx, b)
    local anchor = b:CollapsibleSection("anchor", "Anchor", 220, false)
    if anchor._msuf2CollapsibleEntry then Schema.Section(anchor, "group") end
    local anchorW = anchor._msuf2Width or b.width or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, anchorW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
    Schema.Build(ctx, anchor, {
        { "dropdown", "anchorTo", nil, { "Anchor To", function()
        return M.AnchorTargetValues(GF_ANCHOR_TO, Conf(CurrentScope()).anchorToFrame)
    end, anchorControlW }, get = function() return Conf(CurrentScope()).anchorToFrame or "FREE" end,
            set = function(v)
                local conf = Conf(CurrentScope())
                local selectedValue1
                if not ((v == "FREE")) then selectedValue1 = v end
                conf.anchorToFrame = selectedValue1
                QueueGF(CurrentScope(), "rebuild")
            end,
            meta = ControlMeta(ctx, "field.anchorToFrame"), domain = "rebuild",
            beforeBind = function(widget)
                M.UnitSectionsShared.PlaceDropdown(anchor, widget, anchorLeftX, -38, anchorControlW)
            end, scope = "group" },
        { "dropdown", "anchorPoint", "CENTER", { "Anchor Point", GF_ANCHOR_POINTS,
        anchorControlW }, { anchorRightX, -38,
        anchorControlW, "LEFT" }, domain = "rebuild", scope = "group" },
    }, MIXED_OPTIONS)
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
    Schema.Custom(customAnchor, { id = "menu2.gf_layout.anchor.custom", kind = "anchorPicker",
        scope = "group", applyDomain = "rebuild", owner = customAnchor,
        get = CurrentCustomAnchor, set = SetCustomAnchor })
    for _, widget in ipairs({ customAnchor.box, customAnchor.clear, customAnchor.pick }) do
        Schema.Owned(widget, "group", "rebuild")
    end
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
}
-- The master-switch sections (buff coverage to healer mana) declare themselves in the Additional file.
for _, spec in ipairs(AdditionalSections.LayoutSpecs()) do
    GROUP_LAYOUT_SECTION_SPECS[#GROUP_LAYOUT_SECTION_SPECS + 1] = spec
end

-- Declare the existing lazy header before its body is requested by navigation.
for _, spec in ipairs(GROUP_LAYOUT_SECTION_SPECS) do
    local prepare = spec.prepareShell
    spec.prepareShell = function(ctx, section, ...)
        Schema.Section(section, "group")
        if prepare then return prepare(ctx, section, ...) end
    end
end

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
