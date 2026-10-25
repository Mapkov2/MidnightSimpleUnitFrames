-- GlobalBars: Highlights responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GlobalBarsParts
local BarScopeGet = Parts.BarScopeGet
local BarScopeSet = Parts.BarScopeSet
local Bars = Parts.Bars
local BorderTestScope = Parts.BorderTestScope
local BuildAbsorbSection = Parts.BuildAbsorbSection
local BuildOutlineSection = Parts.BuildOutlineSection
local BuildRoundedSection = Parts.BuildRoundedSection
local BuildScopeSection = Parts.BuildScopeSection
local BuildSlantedSection = Parts.BuildSlantedSection
local BuildTempMaxHealthSection = Parts.BuildTempMaxHealthSection
local BuildTextureSection = Parts.BuildTextureSection
local ChunkedPowerGet = Parts.ChunkedPowerGet
local ChunkedPowerSet = Parts.ChunkedPowerSet
local CurrentBarsScope = Parts.CurrentBarsScope
local CurrentPowerBarScopeUnit = Parts.CurrentPowerBarScopeUnit
local DISPEL_COLOR_REFERENCES = Parts.DISPEL_COLOR_REFERENCES
local DISPEL_SHOW_ON = Parts.DISPEL_SHOW_ON
local DISPEL_TRIGGERS = Parts.DISPEL_TRIGGERS
local EnsureUnitFrameAuraSensorsForScope = Parts.EnsureUnitFrameAuraSensorsForScope
local G = Parts.G
local GP = Parts.GP
local GroupScope = Parts.GroupScope
local HighlightControls = Parts.HighlightControls
local NormalizeAggroMode = Parts.NormalizeAggroMode
local NormalizeDispelTrigger = Parts.NormalizeDispelTrigger
local PRIORITY_LABELS = Parts.PRIORITY_LABELS
local PriorityColor = Parts.PriorityColor
local PriorityOrder = Parts.PriorityOrder
local PurgeScopeSupported = Parts.PurgeScopeSupported
local ROUNDED_SECTION_HEIGHT = Parts.ROUNDED_SECTION_HEIGHT
local ReadB = Parts.ReadB
local ReadG = Parts.ReadG
local ReadGBool = Parts.ReadGBool
local RegisterDragRows = Parts.RegisterDragRows
local RegisterSegment = Parts.RegisterSegment
local RequestAggroBorderRuntime = Parts.RequestAggroBorderRuntime
local RequestAllHighlightBorderRuntime = Parts.RequestAllHighlightBorderRuntime
local RequestBossTargetBorderRuntime = Parts.RequestBossTargetBorderRuntime
local RequestDispelPurgeBorderRuntime = Parts.RequestDispelPurgeBorderRuntime
local RequestGroupAggroRoleRuntime = Parts.RequestGroupAggroRoleRuntime
local RequestHighlightPriorityRuntime = Parts.RequestHighlightPriorityRuntime
local Rows = Parts.Rows
local SetControlEnabled = Parts.SetControlEnabled
local SetControlsEnabled = Parts.SetControlsEnabled
local SharedScope = Parts.SharedScope
local ShowDispelBorderReloadRequiredPopup = Parts.ShowDispelBorderReloadRequiredPopup
local SmoothPowerGet = Parts.SmoothPowerGet
local SmoothPowerSet = Parts.SmoothPowerSet
local T = Parts.T
local UNITFRAME_DISPEL_AURA_WARNING = Parts.UNITFRAME_DISPEL_AURA_WARNING
local UNITFRAME_DISPEL_AURA_WARNING_COLOR = Parts.UNITFRAME_DISPEL_AURA_WARNING_COLOR
local UnitFrameAuraSensorMissingForScope = Parts.UnitFrameAuraSensorMissingForScope
local VT = Parts.VT
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

function GP.BuildHighlightModes(ctx, modesFrame, hlLeftX, hlLeftW)
    local borderModes = VT(0, "Off", 1, "On")
    local function BorderModeSet(key, fallback, reason, kind, apply, onEnabled, onChanged)
        return function(v)
            local value = tonumber(v) or fallback
            local previous = tonumber(BarScopeGet(key, fallback)) or fallback
            BarScopeSet(key, value, reason, true)
            if value == 1 and onEnabled then onEnabled() end
            Rows.testModes[kind].stop(value == 1)
            apply()
            if value ~= previous and onChanged then onChanged() end
        end
    end
    local function DispelShowOn(value)
        return (value == "FRIENDLY" or value == "ENEMY") and value or "BOTH"
    end
    local options = Rows.Options(BarScopeGet,
        function(key, value, row) BarScopeSet(key, value, row.reason, true) end,
        function(row) row.apply() end)
    local aggroModeValues = VT("ALL", "All roles", "NON_TANK", "Non-tanks", "HEALER", "Healers only", "TANK", "Tanks only")
    local controls = Rows.Build(ctx, modesFrame, {
        { "slider", "highlightBorderThickness", 2, { "Highlight border thickness", 1, 30, 1, hlLeftW },
            { hlLeftX, -70, hlLeftW, "LEFT" }, path = "highlight.border_thickness", exact = { step = 1, roundStep = true },
            get = function() return tonumber(BarScopeGet("highlightBorderThickness", BarScopeGet("hlAggroSize", 2))) or 2 end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = Rows.Schema.ScopedFields({ "hlAggroSize" }, "general", "hlOverride").keys,
            set = function(v)
            local n = floor((tonumber(v) or 2) + 0.5)
            BarScopeSet("highlightBorderThickness", n, "MSUF2_HIGHLIGHT_BORDER", true)
            BarScopeSet("hlAggroSize", n, "MSUF2_HIGHLIGHT_BORDER", true)
            RequestAllHighlightBorderRuntime()
        end },
        { "dropdown", "aggroOutlineMode", 1, { "Aggro border", borderModes, hlLeftW }, { hlLeftX, -136, hlLeftW, "LEFT" },
            path = "highlight.border_mode.aggroOutlineMode", numeric = true, set = BorderModeSet("aggroOutlineMode", 1,
                "MSUF2_AGGRO_BORDER", "aggro", RequestAggroBorderRuntime),
            tip = "Shows the aggro color on the border when the unit has threat: your frame while " ..
                "you hold aggro, enemies attacking you, and group members with high threat.", tipOpts = "plain" },
        { "dropdown", "aggroMode", "ALL", { "Group threat visuals show for", aggroModeValues, hlLeftW }, { hlLeftX, -190, hlLeftW, "LEFT" },
            path = "highlight.aggro.roles", readValue = NormalizeAggroMode, writeValue = NormalizeAggroMode,
            reason = "MSUF2_AGGRO_MODE", apply = RequestGroupAggroRoleRuntime },
        { "dropdown", "dispelOutlineMode", 1, { "Dispel border", borderModes, hlLeftW }, { hlLeftX, -244, hlLeftW, "LEFT" },
            path = "highlight.border_mode.dispelOutlineMode", numeric = true, set = BorderModeSet("dispelOutlineMode", 1,
                "MSUF2_DISPEL_BORDER", "dispel", RequestDispelPurgeBorderRuntime,
                EnsureUnitFrameAuraSensorsForScope, ShowDispelBorderReloadRequiredPopup),
            tip = "Colors the border by debuff type while the unit has a debuff that Dispel border detects. Changing it asks for a UI reload.",
            tipOpts = "plain" },
        { "dropdown", "dispelBorderTrigger", "DISPEL_TYPE", { "Dispel border detects", DISPEL_TRIGGERS, hlLeftW },
            { hlLeftX, -298, hlLeftW, "LEFT" }, path = "highlight.dispel.trigger", readValue = NormalizeDispelTrigger,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            local value = NormalizeDispelTrigger(v)
            local previous = NormalizeDispelTrigger(BarScopeGet("dispelBorderTrigger", "DISPEL_TYPE"))
            BarScopeSet("dispelBorderTrigger", value, "MSUF2_DISPEL_TRIGGER", true)
            RequestDispelPurgeBorderRuntime()
            if value ~= previous then ShowDispelBorderReloadRequiredPopup() end
        end },
        { "dropdown", "dispelBorderShowOn", "BOTH", { "Show on", DISPEL_SHOW_ON, hlLeftW }, { hlLeftX, -352, hlLeftW, "LEFT" },
            path = "highlight.dispel.show_on", readValue = DispelShowOn, writeValue = DispelShowOn,
            reason = "MSUF2_DISPEL_BORDER", apply = RequestDispelPurgeBorderRuntime },
        { "dropdown", "purgeOutlineMode", 0, { "Purge border", borderModes, hlLeftW }, { hlLeftX, -406, hlLeftW, "LEFT" },
            path = "highlight.border_mode.purgeOutlineMode", numeric = true, set = BorderModeSet("purgeOutlineMode", 0,
                "MSUF2_PURGE_BORDER", "purge", RequestDispelPurgeBorderRuntime),
            tip = "Colors the border while the unit has a buff you can purge or spellsteal. Only Target and Focus frames support it.", tipOpts = "plain" },
    }, options)
    local bossSupported = not M.SupportsUnitPage or M.SupportsUnitPage("uf_boss")
    local bossTarget = bossSupported and Rows.Build(ctx, modesFrame, {
        { "dropdown", "boss", 1, { "Boss target border", borderModes, hlLeftW }, { hlLeftX, -460, hlLeftW, "LEFT" },
            path = "highlight.boss_target.mode", get = function()
            local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
            return tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback
        end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
            local value = tonumber(v) or 1
            local general = G()
            general.bossTargetOutlineMode = value
            general.bossTargetHighlightEnabled = value == 1
            Rows.testModes.bossTarget.stop(value == 1)
            RequestBossTargetBorderRuntime()
        end,
            tip = "Highlights the Boss frame of the boss you are targeting. It is shared by all boss frames, so it changes only on the Shared scope.",
            tipOpts = "plain" },
    }, Rows.Commands).boss
    local bossSharedHint = bossSupported and Rows.Schema.Build(ctx, modesFrame, {
        { "text", "bossHint", nil, { "Boss target border is a shared boss-frame setting.", hlLeftX, -540, hlLeftW, T.colors.dim }, scope = "bars" },
    }).bossHint
    if bossSharedHint and bossSharedHint.SetWordWrap then bossSharedHint:SetWordWrap(true) end
    local unitAuraDispelHint = Rows.Schema.Build(ctx, modesFrame, {
        { "text", "auraHint", nil, { UNITFRAME_DISPEL_AURA_WARNING, hlLeftX, -570, hlLeftW, UNITFRAME_DISPEL_AURA_WARNING_COLOR }, scope = "bars" },
    }).auraHint
    if unitAuraDispelHint.SetWordWrap then unitAuraDispelHint:SetWordWrap(true) end
    return controls.highlightBorderThickness, controls.aggroOutlineMode, controls.aggroMode, controls.dispelOutlineMode,
        controls.dispelBorderTrigger, controls.dispelBorderShowOn, controls.purgeOutlineMode, bossSupported,
        bossTarget, bossSharedHint, unitAuraDispelHint
end

function GP.BuildHighlightPriority(ctx, priorityCard, priorityCardW, HighlightPriorityEnabled)
    local RefreshPriorityRows
    local prio = Rows.Build(ctx, priorityCard, {
        { "switch", "priority", false, { "Custom highlight priority", 16, -54, priorityCardW - 32 },
            path = "highlight.priority.enabled", get = HighlightPriorityEnabled,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(v)
            local on = v and true or false
            BarScopeSet("hlPrioEnabled", on, "MSUF2_HIGHLIGHT_PRIORITY", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioEnabled = on and 1 or 0
                G().highlightPrioEnabled = on and 1 or 0
            end
            RequestHighlightPriorityRuntime()
            if RefreshPriorityRows then RefreshPriorityRows() end
        end,
            tip = "When several highlight borders show at once, the highest one in the list wins. Turn this on to reorder the list by dragging.",
            tipOpts = "plain" },
    }, Rows.Commands).priority
    local rowMax = 4
    local prioContainer, prioRows, prioCount
    local function SavePriorityRows()
        local function WritePriorityRows()
            local sorted = {}
            for i = 1, prioCount do sorted[i] = prioRows[i] end
            table.sort(sorted, function(a, b) return a.slotIndex < b.slotIndex end)
            local order = {}
            for i = 1, prioCount do order[i] = sorted[i].key end
            BarScopeSet("hlPrioOrder", order, "MSUF2_HIGHLIGHT_PRIORITY_ORDER", true)
            if CurrentBarsScope() == "shared" then
                G().hlPrioOrder = order
                G().highlightPrioOrder = order
            end
            RequestHighlightPriorityRuntime()
        end
        M.RunWithHistory("Highlight Priority Order", "global:highlightPriorityOrder", WritePriorityRows)
    end
    local function SetPriorityRowsEnabled(enabled)
        prioContainer:SetRowsEnabled(enabled)
    end
    prioContainer = RegisterDragRows(M.UnitSectionsShared.MakeDragSortRows(priorityCard, nil, {
        x = 16, y = -82, width = min(220, priorityCardW - 32), rowHeight = 22, gap = 4, maxRows = rowMax,
        bg = { 0.12, 0.12, 0.12, 0.85 },
        border = { 0.30, 0.30, 0.30, 0.60 },
        disabledAlpha = 0.4,
        dragAllowed = function() return HighlightControls() and HighlightPriorityEnabled() end,
        onReorder = SavePriorityRows,
    }), "highlight.priority.order")
    prioRows = prioContainer.rows
    RefreshPriorityRows = function()
        SetControlEnabled(prio, HighlightControls())
        local order = PriorityOrder()
        prioCount = math.min(#order, rowMax)
        for i = 1, prioCount do
            local key = order[i]
            local r, g, bcol = PriorityColor(key)
            local row = prioRows[i]
            row.key = key
            row.slotIndex = i
            row.frame._stripe:SetColorTexture(r, g, bcol, 1)
            row.frame._label:SetText(PRIORITY_LABELS[key] or key)
            row.frame._numText:SetText(tostring(i))
        end
        prioContainer:SetActiveCount(prioCount)
        SetPriorityRowsEnabled(HighlightControls() and HighlightPriorityEnabled())
    end
    if ctx.entry then ctx.entry.refreshHighlightPriorityColors = RefreshPriorityRows end
    M.TrackRefresh(ctx, RefreshPriorityRows)
end

local function BuildHighlightSection(ctx, b)
    local highlights = Rows.Schema.Section(b:CollapsibleSection("bars_highlight", "Highlight Borders", 764, true), "bars")
    local hlW = highlights._msuf2Width or ctx.width or 720
    local hlGap = 28
    local hlLeftX = 30
    local hlInnerW = max(320, hlW - 60)
    local hlLeftW = max(220, min(380, floor((hlInnerW - hlGap) * 0.46)))
    local hlPreviewX = hlLeftX
    local hlPreviewW = max(280, min(440, hlInnerW - 28))
    local highlightTabFrames = {}
    local modesFrame, previewFrame, priorityFrame =
        M.UnitSectionsShared.MakeTabFrames(highlights, -88, hlW, highlightTabFrames, "modes", "preview", "priority")
    RegisterSegment(W.SegmentTabs(ctx, highlights, {
        stateKey = "barsHighlightTab", label = "Highlight area",
        values = VT("modes", "Modes", "preview", "Preview", "priority", "Priority"),
        width = min(520, hlInnerW), frames = highlightTabFrames, defaultTab = "modes",
        x = hlLeftX, y = -44,
    }), "highlight.workspace_tab", VT("modes", "Modes", "preview", "Preview", "priority", "Priority"))
    local priorityCardW = min(360, max(260, hlLeftW + 28))
    local cards = Rows.Schema.Build(ctx, modesFrame, {
        { "card", "modesCard", nil, { "Border Modes", nil, hlLeftX - 14, -38, hlLeftW + 28, 596 }, scope = "bars" },
        { "card", "priorityCard", nil, { "Priority Order", nil, hlLeftX - 14, -38, priorityCardW, 296 }, scope = "bars",
            parent = priorityFrame },
        { "card", "previewCard", nil, { "Preview", nil, hlPreviewX - 14, -38, hlPreviewW + 28, 248 }, scope = "bars",
            parent = previewFrame },
    })
    local modesCard, priorityCard = cards.modesCard, cards.priorityCard
    local function HighlightPriorityEnabled()
        local value = BarScopeGet("hlPrioEnabled", nil)
        if value == nil then value = BarScopeGet("highlightPrioEnabled", false) end
        return value == true or value == 1 or value == "1"
    end
    local highlight, aggro, aggroMode, dispelBorder, dispelTrigger, dispelShowOn, purge, bossSupported,
        bossTarget, bossSharedHint, unitAuraDispelHint = GP.BuildHighlightModes(ctx, modesFrame, hlLeftX, hlLeftW)
    local function ScopeBorderModeOn(key, defaultValue) return tonumber(BarScopeGet(key, defaultValue)) == 1 end
    local function BossTargetBorderOn()
        local fallback = ReadGBool("bossTargetHighlightEnabled", true) and 1 or 0
        return (tonumber(ReadG("bossTargetOutlineMode", fallback)) or fallback) == 1
    end
    Rows.Schema.Colors(modesCard, function()
        local references = {}
        for i = 1, #DISPEL_COLOR_REFERENCES do
            references[i] = DISPEL_COLOR_REFERENCES[i]
        end
        references[#references + 1] = "bar.aggro_border"
        if PurgeScopeSupported() then
            references[#references + 1] = "bar.purge_border"
        end
        if SharedScope() then references[#references + 1] = "highlight.boss_target" end
        return references
    end, {
        title = "Highlight Border Colors",
        note = "Shared Dispel type colors plus the other colors available to this card's border modes.",
        scopeTag = "Shared",
        historySource = "menu:bars-highlight-colors",
        maxTargets = 8,
    })
    local function BindBorderTestToggle(label, y, kind, enabledFn, noScope, path)
        local flag, fn = Rows.testModes[kind].flag, Rows.TestSetter(kind)
        local control = Rows.Schema.Build(ctx, previewFrame, {
            { "toggle", "test", false, { label, hlPreviewX, y, hlPreviewW }, path = path, classification = "ephemeral",
                get = flag,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
                if v and not enabledFn() then
                    if M.RequestRefresh then M.RequestRefresh(ctx, "bars-border-test-disabled") elseif M.Refresh then M.Refresh(ctx) end
                    return
                end
                if type(fn) == "function" then
                    if noScope then fn(v and true or false)
                    else fn(v and true or false, BorderTestScope()) end
                end
            end },
        }, Rows.Commands).test
        control:HookScript("OnHide", function(self)
            if flag() and type(fn) == "function" then
                fn(false)
                self:SetChecked(false)
            end
        end)
        return control
    end
    local aggroTest = BindBorderTestToggle("Test aggro border", -72, "aggro",
        function() return ScopeBorderModeOn("aggroOutlineMode", 1) end, nil, "highlight.preview.aggro")
    local dispelTest = BindBorderTestToggle("Test dispel border", -104, "dispel",
        function() return ScopeBorderModeOn("dispelOutlineMode", 1) end, nil, "highlight.preview.dispel")
    local purgeTest = BindBorderTestToggle("Test purge border", -214, "purge",
        function() return ScopeBorderModeOn("purgeOutlineMode", 0) end, nil, "highlight.preview.purge")
    local bossTargetTest = bossSupported and BindBorderTestToggle("Test boss target border", -246, "bossTarget",
        BossTargetBorderOn, true, "highlight.preview.boss_target")
    local scopedBorderControls = { highlight, aggro, dispelBorder, purge }
    local dispelBorderControls = { dispelTrigger, dispelShowOn, dispelTest }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        W.SetControlsDisabledReason(dispelBorderControls, W.TurnOnReason("Dispel border", function() return ScopeBorderModeOn("dispelOutlineMode", 1) end))
        W.SetControlDisabledReason(aggroTest, W.TurnOnReason("Aggro border", function() return ScopeBorderModeOn("aggroOutlineMode", 1) end))
        local purgeReason = W.TurnOnReason("Purge border", function() return ScopeBorderModeOn("purgeOutlineMode", 0) end)
        W.SetControlDisabledReason(purgeTest, function(control) return PurgeScopeSupported() and purgeReason(control) or nil end)
        if bossTarget then
            local bossOnReason = W.TurnOnReason("Boss target border", BossTargetBorderOn)
            local function BossReason(control)
                if not SharedScope() then return M.Tr("Boss target border is a shared boss-frame setting.") end
                return control == bossTargetTest and bossOnReason(control) or nil
            end
            W.SetControlDisabledReason(bossTarget, BossReason)
            W.SetControlDisabledReason(bossTargetTest, BossReason)
        end
    end
    M.TrackRefresh(ctx, function()
        local scopedActive = HighlightControls()
        local sharedActive = SharedScope()
        local aggroOn = ScopeBorderModeOn("aggroOutlineMode", 1)
        local dispelOn = ScopeBorderModeOn("dispelOutlineMode", 1)
        local purgeOn = ScopeBorderModeOn("purgeOutlineMode", 0)
        local purgeSupported = PurgeScopeSupported()
        local bossTargetOn = BossTargetBorderOn()
        Rows.testModes.aggro.stop(aggroOn)
        Rows.testModes.dispel.stop(dispelOn)
        Rows.testModes.purge.stop(purgeOn and purgeSupported)
        Rows.testModes.bossTarget.stop(sharedActive and bossTargetOn)
        SetControlsEnabled(scopedBorderControls, scopedActive)
        SetControlEnabled(dispelBorder, scopedActive)
        SetControlEnabled(purge, scopedActive and purgeSupported)
        SetControlEnabled(bossTarget, sharedActive)
        SetControlEnabled(aggroMode, scopedActive and (sharedActive or GroupScope()))
        SetControlEnabled(aggroTest, scopedActive and aggroOn)
        SetControlsEnabled(dispelBorderControls, scopedActive and dispelOn)
        SetControlEnabled(purgeTest, scopedActive and purgeSupported and purgeOn)
        SetControlEnabled(bossTargetTest, sharedActive and bossTargetOn)
        if unitAuraDispelHint and unitAuraDispelHint.SetShown then
            unitAuraDispelHint:SetShown((not GroupScope()) and dispelOn and UnitFrameAuraSensorMissingForScope())
        end
        local hintColor = sharedActive and T.colors.dim or T.colors.muted
        if bossSharedHint then bossSharedHint:SetTextColor(hintColor[1], hintColor[2], hintColor[3], sharedActive and 0.75 or 1) end
    end)
    GP.BuildHighlightPriority(ctx, priorityCard, priorityCardW, HighlightPriorityEnabled)
end

local function BuildPowerSection(ctx, b)
    local power = Rows.Schema.Section(b:CollapsibleSection("bars_power", "Bar Animation + Text Accuracy", 184, false), "bars")
    local function FillSetter(setValue, reason)
        return function(value)
            setValue(value, reason)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bars-power-fill-mode") end
        end
    end
    local controls = Rows.Build(ctx, power, {
        { "flowToggle", "smooth", false, { "Smooth power bar" }, path = "power.smooth_fill", get = SmoothPowerGet,
            set = FillSetter(SmoothPowerSet, "MSUF2_BARS_SMOOTH_POWER"),
            tip = "Power bars glide to new values instead of jumping; turns off Chunked power loss. " ..
                "Set per unit: pick a unit scope with a power bar, such as Player or Target.", tipOpts = "power" },
        { "flowToggle", "chunked", false, { "Chunked power loss" }, path = "power.chunked_fill", get = ChunkedPowerGet,
            set = FillSetter(ChunkedPowerSet, "MSUF2_BARS_CHUNKED_POWER"),
            tip = "Spent power drops at once while the spent part briefly stays highlighted, " ..
                "then fades; turns off Smooth power bar. Set per unit, like Smooth power bar.", tipOpts = "power" },
        { "flowToggle", "realtime", true, { "Realtime power text" }, path = "power.realtime_text",
            get = function() return ReadB("realtimePowerText", true) ~= false end,
            write = { source = Bars, boolean = true, skipEqual = true, after = function()
                M.RequestUnitDomains("player", "MSUF2_BARS_REALTIME_POWER", { preview = true, power = true, text = true })
            end } --[[schema setter: GlobalBars.19]],
            tip = "Updates the Player power text on every power tick instead of the regular " ..
                "update rate. Only the Player frame uses it; set it on the Shared scope.", tipOpts = "power" },
    }, Rows.Commands)
    local smoothPower, chunkedPower, realtimePower = controls.smooth, controls.chunked, controls.realtime
    M.BindGateGroup(ctx, nil, {
        { controls = { smoothPower, chunkedPower }, on = function() return CurrentPowerBarScopeUnit() ~= nil end },
        { controls = realtimePower, on = SharedScope },
    })
end

-- Every collapsible on this page goes through the shared lazy-section
-- registry in page order. Open sections get their shell (declared height)
-- in the click frame and their content one deferred refresh later; closed
-- sections build on first expand; hidden search-index builds stay synchronous
-- inside BuildSectionLazy. Heights of open sections must mirror the compact
-- thresholds their builders use internally.
function Rows.PrepareSection(_, section) Rows.Schema.Section(section, "bars") end
local GLOBAL_BARS_LAZY_SECTION_SPECS = {
    {
        sectionId = "bars_textures", prepareShell = Rows.PrepareSection,
        title = "Textures & Gradient",
        defaultOpen = true,
        height = function(lazyCtx) return (((lazyCtx and lazyCtx.width) or 720) < 560) and 766 or 448 end,
        build = BuildTextureSection,
    },
    {
        sectionId = "bars_temp_max_health", prepareShell = Rows.PrepareSection,
        title = "Maximum Health Loss",
        defaultOpen = true,
        height = function(lazyCtx) return (((lazyCtx and lazyCtx.width) or 720) < 700) and 414 or 274 end,
        build = BuildTempMaxHealthSection,
    },
    { sectionId = "bars_absorb", prepareShell = Rows.PrepareSection,
        title = "Absorb Display", height = 414, defaultOpen = true, build = BuildAbsorbSection },
    { sectionId = "bars_outline", prepareShell = Rows.PrepareSection,
        title = "Frame Outline", height = 226, build = BuildOutlineSection },
    { sectionId = "bars_rounded", prepareShell = Rows.PrepareSection,
        title = "Rounded Texture", height = ROUNDED_SECTION_HEIGHT, defaultOpen = true, build = BuildRoundedSection },
    { sectionId = "bars_slanted", prepareShell = Rows.PrepareSection,
        title = "Slanted Bars", height = 480, defaultOpen = true, build = BuildSlantedSection },
    { sectionId = "bars_highlight", prepareShell = Rows.PrepareSection,
        title = "Highlight Borders", height = 764, defaultOpen = true, build = BuildHighlightSection },
    { sectionId = "bars_power", prepareShell = Rows.PrepareSection,
        title = "Bar Animation + Text Accuracy", height = 184, build = BuildPowerSection },
}
local function BuildGlobalBarsSectionLazy(ctx, b, spec)
    local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
    if type(buildLazy) == "function" then return buildLazy(ctx, b, nil, spec) end
    return spec.build(ctx, b)
end

local function BuildBars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Bars", "Textures, gradients, outlines and highlight borders.", 72)
    BuildScopeSection(ctx, b)
    for i = 1, #GLOBAL_BARS_LAZY_SECTION_SPECS do
        BuildGlobalBarsSectionLazy(ctx, b, GLOBAL_BARS_LAZY_SECTION_SPECS[i])
    end
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_bars", { title = "MSUF Bars", build = BuildBars, version = 19 })

-- Explicit load-time exports for the following responsibility modules.
