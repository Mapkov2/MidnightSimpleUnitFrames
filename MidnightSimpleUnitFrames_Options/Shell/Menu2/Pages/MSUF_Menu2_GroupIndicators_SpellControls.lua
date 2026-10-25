-- GroupIndicators: SpellControls responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.GroupIndicatorsParts
local Bool = Parts.Bool
local BuildIndicatorsSection = Parts.BuildIndicatorsSection
local CICategoryValues = Parts.CICategoryValues
local CICustomConfig = Parts.CICustomConfig
local CIFilterValues = Parts.CIFilterValues
local CI_SLOT_DEFAULTS = Parts.CI_SLOT_DEFAULTS
local CI_SLOT_VALUES = Parts.CI_SLOT_VALUES
local CORNER_MISSING_AVAILABLE = Parts.CORNER_MISSING_AVAILABLE
local CORNER_MISSING_NOTE_GAP = Parts.CORNER_MISSING_NOTE_GAP
local CORNER_MISSING_NOTICE = Parts.CORNER_MISSING_NOTICE
local C_Timer = Parts.C_Timer
local ControlMeta = Parts.ControlMeta
local CornerModeValues = Parts.CornerModeValues
local CurrentAuraColor = Parts.CurrentAuraColor
local CurrentCISlot = Parts.CurrentCISlot
local CurrentScope = Parts.CurrentScope
local CurrentSpellAura = Parts.CurrentSpellAura
local CurrentSpellConfig = Parts.CurrentSpellConfig
local CurrentSpellIsExternalDefensive = Parts.CurrentSpellIsExternalDefensive
local CurrentSpellMultiSpec = Parts.CurrentSpellMultiSpec
local CustomBuffSpellIDListText = Parts.CustomBuffSpellIDListText
local CustomBuffSpellIDs = Parts.CustomBuffSpellIDs
local EffectiveSpellSpec = Parts.EffectiveSpellSpec
local EnsureSpellDefaults = Parts.EnsureSpellDefaults
local ExternalAutoBlacklistActive = Parts.ExternalAutoBlacklistActive
local FRAME_EFFECT_TYPES = Parts.FRAME_EFFECT_TYPES
local FinalizeScopePage = Parts.FinalizeScopePage
local FrameEffectConfig = Parts.FrameEffectConfig
local GP = Parts.GP
local ICON_EFFECT_TYPES = Parts.ICON_EFFECT_TYPES
local IsAllSpecsSpellSpec = Parts.IsAllSpecsSpellSpec
local IsCustomBuffEntry = Parts.IsCustomBuffEntry
local OnOffBadge = Parts.OnOffBadge
local OptionText = Parts.OptionText
local PLACED_INDICATOR_TYPES = Parts.PLACED_INDICATOR_TYPES
local PlacedConfig = Parts.PlacedConfig
local QueueGF = Parts.QueueGF
local QueueSpellIndicators = Parts.QueueSpellIndicators
local ROW_OPTIONS = Parts.ROW_OPTIONS
local RefreshGFPreview = Parts.RefreshGFPreview
local RegisterControl = Parts.RegisterControl
local ResolvePlacedSpellIndicatorControlVisibility = Parts.ResolvePlacedSpellIndicatorControlVisibility
local SPELL_GROWTH_VALUES = Parts.SPELL_GROWTH_VALUES
local SPELL_INDICATORS_121_PTR_DISABLED = Parts.SPELL_INDICATORS_121_PTR_DISABLED
local STATUS_ICON_ANCHORS = Parts.STATUS_ICON_ANCHORS
local Schema = Parts.Schema
local ScopeSection = Parts.ScopeSection
local SetCurrentSpellAura = Parts.SetCurrentSpellAura
local SetManyEnabled = Parts.SetManyEnabled
local SetOptionEnabled = Parts.SetOptionEnabled
local SetOptionsEnabled = Parts.SetOptionsEnabled
local SetSectionBadgesAndStatus = Parts.SetSectionBadgesAndStatus
local SpellAuraValues = Parts.SpellAuraValues
local SpellIndicators = Parts.SpellIndicators
local SpellSpecValues = Parts.SpellSpecValues
local SpellTileGrid = Parts.SpellTileGrid
local SpellTrackedSpecValues = Parts.SpellTrackedSpecValues
local StatusIcons = Parts.StatusIcons
local StepMeta = Parts.StepMeta
local T = Parts.T
local Tr = Parts.Tr
local TrackSectionRefresh = Parts.TrackSectionRefresh
local VT = Parts.VT
local Val = Parts.Val
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

local function IconScaleLifecycle(iconScale)
    local pendingApply, pendingScope, releaseScheduled
    local function CombatLocked()
        if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() == true end
        return (InCombatLockdown and InCombatLockdown()) or MSUF.PublicGlobals.MSUF_InCombat == true
    end
    local function RefreshPreviewOnly(scope)
        if CombatLocked() then return false end
        if type(RefreshGFPreview) == "function" then RefreshGFPreview(scope or CurrentScope(), { spellOnly = true }) end
        return true
    end
    local function FlushRuntime()
        if not pendingApply then return end
        if CombatLocked() then
            releaseScheduled = nil
            return false
        end
        local scope = pendingScope or CurrentScope()
        pendingApply, pendingScope, releaseScheduled = nil, nil, nil
        QueueSpellIndicators(scope, "auras")
        return true
    end
    local function ScheduleRelease()
        if not pendingApply or releaseScheduled or CombatLocked() then return end
        releaseScheduled = true
        if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, FlushRuntime) else FlushRuntime() end
    end
    return {
        get = function() return tonumber(SpellIndicators(CurrentScope()).iconScale) or 100 end,
        customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
            value = floor((tonumber(value) or 100) + 0.5)
            local scope = CurrentScope()
            if pendingApply and pendingScope ~= scope then FlushRuntime() end
            local si = SpellIndicators(scope)
            if si.iconScale == value then return end
            si.iconScale = value
            pendingApply = true
            pendingScope = scope
            if iconScale._msuf2SliderActive == true or releaseScheduled then RefreshPreviewOnly(scope) else FlushRuntime() end
        end,
        default = 100,
        afterBind = function()
            iconScale:HookScript("OnMouseUp", ScheduleRelease)
            iconScale:HookScript("OnHide", FlushRuntime)
            iconScale:HookScript("OnShow", FlushRuntime)
        end,
    }
end

GP.BuildSpellIndicatorStyleSection = function(ctx, b)
    local section = b:CollapsibleSection("si_style", "Spell Icon Style", 844, false)
    local leftX, leftW, rightX, rightW, innerW = Schema.Columns(section, ctx.width, 30, 28, 0.46, 240, 370, 240, 390)
    W.ControlCard(section, "Basics", nil, leftX - 14, -38, leftW + 28, 322)
    W.ControlCard(section, "Cooldown Text", nil, rightX - 14, -38, rightW + 28, 430)
    W.ControlCard(section, "Stack Count", nil, leftX - 14, -376, leftW + 28, 296)
    W.ControlCard(section, "Duration Bar", nil, rightX - 14, -484, rightW + 28, 312)

    local function Style(kind)
        local si = SpellIndicators(kind or CurrentScope())
        if type(si.style) ~= "table" then si.style = {} end
        return si.style
    end
    local function StyleMeta(_, path, step)
        local meta = step and StepMeta(ctx, path, step) or ControlMeta(ctx, path)
        local suffix = path == "spell.icon_zoom" and "iconZoom"
            or (path == "spell.icon_scale" and "iconScale" or path:match("^spell%.style%.(.+)$"))
        if suffix then
            -- Scope changes refresh this page in place, so a key captured while
            -- building would become stale. The widget command resolves
            -- CurrentScope() at execution time, matching every other Group control.
            meta.searchSettingKeys = nil
            meta.searchSettingKeyPatterns = nil
        end
        return meta
    end
    local controls = {}
    local RefreshStyleState = M.RefreshProxy()
    local function Track(control)
        controls[#controls + 1] = control
        return control
    end
    local styleOwner = { config = Style, scope = CurrentScope, recordPath = "spellIndicators.style.",
        changed = function(scope) QueueSpellIndicators(scope, "auras") end,
        path = "spell.style.", meta = StyleMeta, stepMeta = StyleMeta, strictToggles = true, rawNumber = true }
    local styleRows, styleControls = Schema.GroupRecordOptions(styleOwner), {}
    styleRows.beforeBind = Track

    local halfRight = max(100, floor((rightW - 12) / 2))
    local halfLeft = max(100, floor((leftW - 12) / 2))
    Schema.Build(ctx, section, {
        { "slider", "iconZoom", 100, { "Icon Zoom (%)", 100, 200, 1, leftW },
            { leftX, -72, leftW, "LEFT" }, path = "spell.icon_zoom", setting = Schema.GroupKeys("spellIndicators.iconZoom"), source = SpellIndicators },
        { "slider", "iconScale", 100, { "Icon Scale (%)", 20, 300, 1, leftW }, { leftX, -128, leftW, "LEFT" },
            path = "spell.icon_scale", setting = Schema.GroupKeys("spellIndicators.iconScale"), lifecycle = IconScaleLifecycle },
        { "slider", "alpha", 100, { "Opacity", 10, 100, 5, leftW }, { leftX, -184, leftW, "LEFT" },
            get = function() return floor(((tonumber(Style().alpha) or 1) * 100) + 0.5) end,
            convert = function(value) return min(1, max(0.1, (tonumber(value) or 100) / 100)) end },
        { "toggle", "showTooltip", true, { "Show Tooltip", leftX, -240, leftW },
            tip = { "Spell Icon tooltip", "Controls native Aura tooltips for Spell Icons only.", { hook = true } } },
        { "toggle", "showCooldownText", true, { "Show Cooldown Text", rightX, -72, rightW } },
        { "toggle", "showCooldownSwipe", true, { "Show Cooldown Swipe", rightX, -104, rightW } },
        { "slider", "cooldownSize", 8, { "Cooldown Font", 6, 24, 1, rightW }, { rightX, -148, rightW, "LEFT" } },
        { "dropdown", "cooldownAnchor", "CENTER", { "Cooldown Anchor", STATUS_ICON_ANCHORS, rightW }, { rightX, -204, rightW, "LEFT" } },
        { "slider", "cooldownX", 0, { "Cooldown X", -40, 40, 1, halfRight }, { rightX, -260, halfRight, "LEFT" } },
        { "slider", "cooldownY", 0, { "Cooldown Y", -40, 40, 1, halfRight }, { rightX + halfRight + 12, -260, halfRight, "LEFT" } },
        { "dropdown", "cooldownSwipeReverse", "NORMAL",
            { "Swipe Direction", VT("NORMAL", "Normal", "REVERSE", "Reverse"), rightW }, { rightX, -316, rightW, "LEFT" },
            get = function() return Style().cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
            convert = function(value) return value == "REVERSE" end },
        { "slider", "cooldownDecimalSeconds", 3, { "Decimals below sec", 0, 30, 1, rightW }, { rightX, -372, rightW, "LEFT" },
            tip = { "Cooldown text format", "Below this value, remaining whole seconds may show one decimal place. Set 0 for whole seconds only.",
                { hook = true } } },
        { "toggle", "showStacks", true, { "Show Stack Count", leftX, -410, leftW } },
        { "slider", "stackSize", 10, { "Stack Font", 6, 24, 1, leftW }, { leftX, -452, leftW, "LEFT" } },
        { "dropdown", "stackAnchor", "BOTTOMRIGHT", { "Stack Anchor", STATUS_ICON_ANCHORS, leftW }, { leftX, -508, leftW, "LEFT" } },
        { "slider", "stackX", 0, { "Stack X", -40, 40, 1, halfLeft }, { leftX, -564, halfLeft, "LEFT" } },
        { "slider", "stackY", 0, { "Stack Y", -40, 40, 1, halfLeft }, { leftX + halfLeft + 12, -564, halfLeft, "LEFT" } },
        { "toggle", "showDurationBar", false, { "Show Duration Bar", rightX, -520, rightW } },
        { "slider", "durationBarHeight", 2, { "Height", 1, 16, 1, rightW }, { rightX, -562, rightW, "LEFT" } },
        { "dropdown", "durationBarDisplay", "BAR_ONLY", { "Display", VT("BAR_ONLY", "Bar Only", "OVERLAY", "Icon + Bar"), rightW },
            { rightX, -618, rightW, "LEFT" } },
        { "dropdown", "durationBarPosition", "BOTTOM", { "Position", VT("BOTTOM", "Bottom", "TOP", "Top"), halfRight },
            { rightX, -674, halfRight, "LEFT" } },
        { "dropdown", "durationBarDirection", "REMAINING", { "Fill Mode", VT("REMAINING", "Remaining", "ELAPSED", "Elapsed"), halfRight },
            { rightX + halfRight + 12, -674, halfRight, "LEFT" } },
    }, styleRows, styleControls)
    local swipeDirection = styleControls.cooldownSwipeReverse
    W.Text(section, M.Format("Shape, border and shadow: %s. All controls here remain Group-scope aware.", M.NavPath("auras3_buffs")),
        leftX, -814, innerW, T.colors.muted)


    RefreshStyleState = RefreshStyleState(function()
        local si = SpellIndicators(CurrentScope())
        local style = Style()
        local enabled = si.enabled == true
        SetOptionsEnabled(controls, enabled)
        SetManyEnabled(enabled and style.showCooldownText ~= false, styleControls.cooldownSize, styleControls.cooldownAnchor,
            styleControls.cooldownX, styleControls.cooldownY, styleControls.cooldownDecimalSeconds)
        SetOptionEnabled(swipeDirection, enabled and style.showCooldownSwipe ~= false)
        SetManyEnabled(enabled and style.showStacks ~= false, styleControls.stackSize, styleControls.stackAnchor,
            styleControls.stackX, styleControls.stackY)
        SetManyEnabled(enabled and style.showDurationBar == true, styleControls.durationBarHeight, styleControls.durationBarDisplay,
            styleControls.durationBarPosition, styleControls.durationBarDirection)
        local scope = CurrentScope()
        local scopeLabel = scope == "party" and "Party" or (scope == "mythicraid" and "Mythic Raid" or "Raid")
        SetSectionBadgesAndStatus(section, {
            { text = scopeLabel, kind = "info", important = true },
            { text = M.Format("Zoom %d%%", floor((tonumber(si.iconZoom) or 100) + 0.5)), kind = "info" },
            { text = "Buff Appearance", kind = "accent" },
            OnOffBadge(enabled, "Active", "Inactive"),
        })
    end)
    styleOwner.afterToggle = RefreshStyleState
    TrackSectionRefresh(ctx, section, RefreshStyleState)
end

-- The Spell Indicators section is assembled by SpellSection.Build from one stage
-- per card. Stages share one per-build `state` table and run in the order the
-- controls used to be created inline; state.RefreshState is a RefreshProxy, so
-- callbacks bound in earlier stages reach the refresh body wired last.
local SpellSection = {}
function SpellSection.Open(state, ctx, b, RefreshPage)
    local spells = b:CollapsibleSection("si", "Spell Indicators", 848, false)
    local siLeftX, siLeftW, siRightX, siRightW = Schema.Columns(spells, ctx.width, 30, 28, 0.46, 240, 370, 240, 390)
    state.spellSetCard = W.ControlCard(spells, "Choose Spells", nil, siLeftX - 14, -38, siLeftW + 28, 404)
    W.ControlCard(spells, "Edit Spell", nil, siRightX - 14, -38, siRightW + 28, 404)
    state.placedIndicatorCard = W.ControlCard(spells, "Show on Frame", nil, siLeftX - 14, -456, siLeftW + 28, 560)
    state.frameHighlightCard = W.ControlCard(spells, "Highlight Health Bar", nil, siRightX - 14, -456, siRightW + 28, 360)
    state.placedRows = Schema.GroupRecordOptions({ config = PlacedConfig, scope = CurrentScope,
        recordPath = "spellIndicators.specs.{spec}.{spell}.placed.",
        companionWrites = { "gf_{scope}.spellIndicators.specs.{spec}" },
        changed = QueueSpellIndicators, path = "spell.placed.", meta = ControlMeta, stepMeta = StepMeta })
    state.frameRows = Schema.GroupRecordOptions({ config = FrameEffectConfig, scope = CurrentScope,
        recordPath = "spellIndicators.specs.{spec}.{spell}.frame.",
        companionWrites = { "gf_{scope}.spellIndicators.specs.{spec}" },
        changed = QueueSpellIndicators, path = "spell.frame.", meta = ControlMeta, stepMeta = StepMeta })
    state.selectedRows = Schema.GroupRecordOptions({ config = CurrentSpellConfig, scope = CurrentScope,
        recordPath = "spellIndicators.specs.{spec}.{spell}.",
        companionWrites = { "gf_{scope}.spellIndicators.specs.{spec}" },
        changed = QueueSpellIndicators, path = "spell.selected.", meta = ControlMeta, stepMeta = StepMeta })
    state.RefreshState = M.RefreshProxy()
    function state.RequestControlRefresh(reason)
        if M.RequestRefresh then
            return M.RequestRefresh(ctx, reason or "gf-spell-indicators")
        elseif M.Refresh then
            return M.Refresh(ctx)
        end
        return RefreshPage()
    end
    state.b, state.RefreshPage, state.spells = b, RefreshPage, spells
    state.siLeftX, state.siLeftW, state.siRightX, state.siRightW = siLeftX, siLeftW, siRightX, siRightW
end
--- Show spell indicators, Layer, Spec, Preview all spells, the multi-spec pair
--- and the spell tile grid.
function SpellSection.BuildSpecControls(state, ctx)
    local spells, siLeftX, siLeftW, siRightX, siRightW = state.spells, state.siLeftX, state.siLeftW, state.siRightX, state.siRightW
    local RefreshSpellIndicatorState, RequestSpellControlRefresh = state.RefreshState, state.RequestControlRefresh
    local function ChangedSpec(kind, reason)
        EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
        CurrentSpellAura(kind)
        QueueSpellIndicators(kind)
        RefreshGFPreview()
        RefreshSpellIndicatorState()
        RequestSpellControlRefresh(reason)
    end
    local commandRows = Schema.GroupCommands({
        enabled = {
        get = function()
            if SPELL_INDICATORS_121_PTR_DISABLED then return false end
            return SpellIndicators(CurrentScope()).enabled == true
        end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            writeTargets = Schema.Record({ "gf_{scope}.spellIndicators" }),
        set = function(value)
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
        end,
        },
        spec = {
        get = function() return SpellIndicators(CurrentScope()).spec or "auto" end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            writeTargets = Schema.Record({ "gf_{scope}.spellIndicators" }),
        set = function(value)
            local kind = CurrentScope()
            SpellIndicators(kind).spec = value or "auto"
            ChangedSpec(kind, "gf-spell-spec")
        end,
        },
        multiSpec = {
        get = function() return CurrentSpellMultiSpec(CurrentScope()) end,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
            writeTargets = Schema.Record({ "gf_{scope}.spellIndicators" }),
        set = function(value)
            local kind = CurrentScope()
            M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
            M.gfSpellMultiSpecSelection[kind] = value or ""
            ChangedSpec(kind, "gf-spell-multi-spec")
        end,
        },
        tracked = {
        get = function()
            local cfg = SpellIndicators(CurrentScope())
            local specKey = CurrentSpellMultiSpec(CurrentScope())
            if IsAllSpecsSpellSpec(specKey) then return true end
            return cfg.spec == "multi" and specKey ~= "" and cfg.multiSpecs and cfg.multiSpecs[specKey] == true
        end,
        companionWrites = { "gf_{scope}.spellIndicators.multiSpecs" },
        customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
            local kind = CurrentScope()
            local cfg = SpellIndicators(kind)
            local specKey = CurrentSpellMultiSpec(kind)
            if specKey == "" or IsAllSpecsSpellSpec(specKey) then return end
            cfg.multiSpecs = cfg.multiSpecs or {}
            cfg.multiSpecs[specKey] = value and true or nil
            QueueSpellIndicators(kind)
            RefreshGFPreview()
            RefreshSpellIndicatorState()
            RequestSpellControlRefresh("gf-spell-multi-track")
        end,
        },
    }, ControlMeta, StepMeta)
    local function SelectedSpellConfigTable()
        return CurrentSpellConfig(CurrentScope(), true) or SpellIndicators(CurrentScope())
    end
    local specRows = Schema.Build(ctx, spells, {
        { "switch", "enabled", nil, { "Show spell indicators", siLeftX, -72, siLeftW },
            path = "spell.enabled", setting = Schema.GroupKeys("spellIndicators.enabled"),
            flagsBefore = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        { "slider", "layer", 9, { "Layer (0-30)", 0, 30, 1, siRightW }, { siRightX, -72, siRightW, "LEFT" },
            path = "spell.selected.layer", setting = Schema.Record({
                "gf_{scope}.spellIndicators.specs.{spec}.{spell}.layer", "gf_{scope}.spellIndicators.layer" }),
            source = SelectedSpellConfigTable, bind = Schema.GroupNestedBinding },
        { "dropdown", "spec", nil, { "Spec", SpellSpecValues, siLeftW }, { siLeftX, -116, siLeftW, "LEFT" },
            path = "spell.spec", setting = Schema.GroupKeys("spellIndicators.spec") },
    }, commandRows)
    local siEnable, siLayer, specDrop = specRows.enabled, specRows.layer, specRows.spec
    local function PreviewAllSpecIconsEnabled()
        local previewAllState = M.gfPreviewAllSpecSpellIcons
        return type(previewAllState) == "table" and previewAllState[CurrentScope()] == true
    end
    local previewAll = T.Button(spells, "Preview all spells", siLeftW, 28)
    if T.CenterButtonLabel then T.CenterButtonLabel(previewAll) end
    previewAll:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX, -162)
    local function RefreshPreviewAllButton()
        local enabled = PreviewAllSpecIconsEnabled()
        if T.ApplyButtonRole then T.ApplyButtonRole(previewAll, enabled and "success" or "danger") end
        if previewAll.SetActive then previewAll:SetActive(true) end
    end
    local function SetPreviewAllSpecIcons(enabled)
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false end
        if (InCombatLockdown and InCombatLockdown()) or MSUF.PublicGlobals.MSUF_InCombat == true then return false end
        local kind = CurrentScope()
        M.gfPreviewAllSpecSpellIcons = M.gfPreviewAllSpecSpellIcons or {}
        M.gfPreviewAllSpecSpellIcons[kind] = enabled == true or nil
        RefreshPreviewAllButton()
        RefreshGFPreview()
        RefreshSpellIndicatorState()
        return PreviewAllSpecIconsEnabled() == (enabled == true)
    end
    previewAll:SetScript("OnClick", function()
        SetPreviewAllSpecIcons(not PreviewAllSpecIconsEnabled())
    end)
    previewAll._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = PreviewAllSpecIconsEnabled,
        set = SetPreviewAllSpecIcons,
    }
    RegisterControl(previewAll, ctx, "spell.preview_all", "Preview all spells", "button", "ephemeral")
    if M.AddTooltip then
        M.AddTooltip(previewAll, "Preview all spells",
            "On previews every enabled spell of every tracked spec, including spells that only draw a frame effect. Off previews only the selected spell.",
            { hook = true })
    end
    RefreshPreviewAllButton()
    -- The Edit Spell column stacks Layer, the multi-spec pair and Aura Spell IDs
    -- above Choose spell. The multi-spec pair only shows in multi-spec mode, but
    -- it keeps its own rows so it never covers the ID input.
    local allSpecsHint
    local function PrepareTrackHint()
        allSpecsHint = W.Text(spells, "Shared entries apply to every spec.", siRightX, -184, siRightW, T.colors.accent)
        if allSpecsHint.SetWordWrap then allSpecsHint:SetWordWrap(true) end
        allSpecsHint:Hide()
    end
    local multiRows = Schema.Build(ctx, spells, {
        { "dropdown", "multiSpec", nil, { "Multi-Spec Entry", function() return SpellTrackedSpecValues() end, siRightW },
            { siRightX, -130, siRightW, "LEFT" }, path = "spell.multi_spec.selector", classification = "ephemeral" },
        { "toggle", "tracked", nil, { "Track selected multi spec", siRightX, -184, siRightW },
            path = "spell.multi_spec.tracked", setting = Schema.Record({ "gf_{scope}.spellIndicators.multiSpecs.{selected}" }), beforeBind = PrepareTrackHint },
    }, commandRows)
    local multiSpecDrop, multiSpecEnabled = multiRows.multiSpec, multiRows.tracked
    state.spellGrid = SpellTileGrid.New(ctx, spells, siLeftX, -254, siLeftW, state.RefreshPage)
    state.siEnable, state.siLayer, state.specDrop, state.RefreshPreviewAllButton = siEnable, siLayer, specDrop, RefreshPreviewAllButton
    state.multiSpecDrop, state.multiSpecEnabled, state.allSpecsHint = multiSpecDrop, multiSpecEnabled, allSpecsHint
end
--- Edit Spell: Choose spell, Show this spell, Aura Spell IDs, Only show my
--- casts and Hide duplicate Buff icon.
function SpellSection.BuildSelectedSpell(state, ctx)
    local spells, siRightX, siRightW = state.spells, state.siRightX, state.siRightW
    local RefreshSpellIndicatorState, RequestSpellControlRefresh = state.RefreshState, state.RequestControlRefresh
    local rows = Schema.Build(ctx, spells, {
        { "dropdown", "aura", nil, { "Choose spell", function() return SpellAuraValues(CurrentScope()) end, siRightW },
            { siRightX, -282, siRightW, "LEFT" }, path = "spell.selected_aura", classification = "ephemeral",
            writeTargets = Schema.Record({ "gf_{scope}.spellIndicators.specs.{spec}" }),
            get = function() return CurrentSpellAura(CurrentScope()) end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(value)
                SetCurrentSpellAura(CurrentScope(), value)
                RefreshGFPreview()
                RefreshSpellIndicatorState()
                RequestSpellControlRefresh("gf-spell-selection")
            end },
        { "switch", "enabled", true, { "Show this spell", siRightX, -342, siRightW } },
        { "textinput", "spells", "", { "Aura Spell IDs", siRightW }, { siRightX, -222, siRightW },
            path = "spell.selected.spell_ids", commitOnBlur = true, requireRecord = true, convert = function(value)
                local ids = CustomBuffSpellIDs(value)
                return ids and CustomBuffSpellIDListText(ids) or ""
            end },
        { "toggle", "onlyOwn", true, { "Only show my casts", siRightX, -374, siRightW }, path = "spell.selected.only_mine",
            get = function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                if not cfg then return false end
                if cfg.custom == true and cfg._msufCustomOnlyOwnExplicit ~= true then return false end
                return cfg.onlyOwn ~= false
            end,
            customSetReason = "Resolves the currently selected record or text slot at input time.",
            companionWrites = { "gf_{scope}.spellIndicators.specs.{spec}.{spell}._msufCustomOnlyOwnExplicit" },
            set = function(value)
                local cfg = CurrentSpellConfig(CurrentScope(), true)
                if cfg then
                    if cfg.custom == true then cfg._msufCustomOnlyOwnExplicit = true end
                    cfg.onlyOwn = value and true or false
                end
                QueueSpellIndicators(CurrentScope())
            end },
        { "toggle", "autoBlacklist", false, { "Hide duplicate Buff icon", siRightX, -406, siRightW },
            path = "spell.selected.auto_blacklist", uncheckedNil = true, get = function()
                local cfg = CurrentSpellConfig(CurrentScope(), false)
                if CurrentSpellIsExternalDefensive(CurrentScope()) and ExternalAutoBlacklistActive(CurrentScope()) then return true end
                return cfg and cfg.autoBlacklist == true or false
            end },
    }, state.selectedRows)
    local spellEnabled, customSpellIDs, onlyMine, autoBlacklist = rows.enabled, rows.spells, rows.onlyOwn, rows.autoBlacklist
    if M.AddTooltip then
        M.AddTooltip(autoBlacklist, "Hide duplicate Buff icon",
            "Hides this aura from the regular Buff icons while this spell indicator is enabled. External-defensive Spell Icons follow the active " ..
                "External Defensives container's Auto-blacklist from Buffs setting.",
            { hook = true, titleAsLine = true })
    end
    state.spellEnabled, state.customSpellIDs, state.onlyMine, state.autoBlacklist = spellEnabled, customSpellIDs, onlyMine, autoBlacklist
end
--- Shared color-history label for the selected spell.
function SpellSection.PrepareColorScopeTag(state)
    function state.ColorScopeTag()
        local kind = CurrentScope()
        return M.Format("%s: %s", GP.ScopeLabel(kind), tostring(CurrentSpellAura(kind) or ""))
    end
end
--- Show on Frame: Display as, its shape controls and the selected spell color.
function SpellSection.BuildPlacedCard(state, ctx)
    local siLeftX, siLeftW = state.siLeftX, state.siLeftW
    local RefreshSpellIndicatorState, RefreshPage = state.RefreshState, state.RefreshPage
    local placedType = Schema.Build(ctx, state.spells, {
        { "dropdown", "placed", "none", { "Display as", PLACED_INDICATOR_TYPES, siLeftW },
            { siLeftX, -492, siLeftW, "LEFT" }, subtype = true, path = "spell.selected.placed.type", defaults =
        function(placed)
            placed.type = placed.type or "icon"
            placed.anchor = placed.anchor or "TOPLEFT"
            placed.size = tonumber(placed.size) or 18
            placed.cooldownSize = tonumber(placed.cooldownSize) or 8
            placed.growth = placed.growth or "RIGHTDOWN"
            if placed.barSmoothFill == nil then placed.barSmoothFill = false end
            if placed.barShowTimer == nil then placed.barShowTimer = false end
            placed.barTimerAnchor = placed.barTimerAnchor or "CENTER"
            placed.barTimerX = tonumber(placed.barTimerX) or 0
            placed.barTimerY = tonumber(placed.barTimerY) or 0
            if placed.showCooldownSwipe == nil then placed.showCooldownSwipe = true end
        end, afterSet =
        -- Re-gate this section synchronously before the page-level refresh.
        -- A page reselect runs its refreshers behind the menu-data revision
        -- guard, and the surrounding history capture only bumps that revision
        -- after this setter returns. Without the direct call the controls of
        -- the previous shape stay as they were, so switching Icon to Square
        -- left Icon Effect visible until an unrelated interaction refreshed it.
        function()
            RefreshSpellIndicatorState()
            RefreshPage()
        end },
    }, state.selectedRows).placed
    local timerGap = 12
    local timerSliderW = floor((siLeftW - timerGap) * 0.5)
    local rows = Schema.Build(ctx, state.spells, {
        { "dropdown", "anchor", "TOPLEFT", { "Anchor", STATUS_ICON_ANCHORS, siLeftW }, { siLeftX, -546, siLeftW, "LEFT" } },
        { "slider", "size", 18, { "Size", 1, 48, 1, siLeftW }, { siLeftX, -600, siLeftW, "LEFT" } },
        { "slider", "barWidth", 42, { "Bar Width", 8, 120, 1, siLeftW }, { siLeftX, -654, siLeftW, "LEFT" } },
        { "dropdown", "growth", "RIGHTDOWN", { "Growth", SPELL_GROWTH_VALUES, siLeftW }, { siLeftX, -708, siLeftW, "LEFT" } },
        { "dropdown", "iconEffect", "none", { "Icon Effect", ICON_EFFECT_TYPES, siLeftW },
            { siLeftX, -762, siLeftW, "LEFT" }, afterSet = RefreshSpellIndicatorState },
        { "toggle", "barSmoothFill", false, { "Smooth fill", siLeftX, -762, siLeftW }, { siLeftX, -762, siLeftW, "LEFT" } },
        { "toggle", "barShowTimer", false, { "Show Timer Text", siLeftX, -802, siLeftW },
            { siLeftX, -802, siLeftW, "LEFT" }, afterSet = RefreshSpellIndicatorState },
        { "dropdown", "barTimerAnchor", "CENTER", { "Timer Anchor", STATUS_ICON_ANCHORS, siLeftW }, { siLeftX, -842, siLeftW, "LEFT" } },
        { "slider", "barTimerX", 0, { "Timer X", -100, 100, 1, timerSliderW }, { siLeftX, -896, timerSliderW, "LEFT" } },
        { "slider", "barTimerY", 0, { "Timer Y", -100, 100, 1, timerSliderW },
            { siLeftX + timerSliderW + timerGap, -896, timerSliderW, "LEFT" } },
    }, state.placedRows)
    local placedAnchor, placedSize, placedBarWidth, placedGrowth = rows.anchor, rows.size, rows.barWidth, rows.growth
    local placedIconEffect, placedBarSmoothFill, placedBarShowTimer = rows.iconEffect, rows.barSmoothFill, rows.barShowTimer
    local placedBarTimerAnchor, placedBarTimerX, placedBarTimerY = rows.barTimerAnchor, rows.barTimerX, rows.barTimerY
    state.placedColorRelevant = false
    state.placedColorShortcut = W.AttachContextColorShortcut(state.placedIndicatorCard, {
        title = "Selected Spell Color",
        note = "The selected spell color is shared by its bar, square, and icon glow.",
        tooltipTitle = "Selected Spell Color",
        tooltipText = "The selected spell color is shared by its bar, square, and icon glow.",
        scopeTag = state.ColorScopeTag,
        historySource = "menu:group-spell-indicator-color",
        isRelevant = function() return state.placedColorRelevant end,
        getTargets = function()
            local kind = CurrentScope()
            return {{
                label = "Selected Spell Color",
                getRGB = function()
                    local cfg = CurrentSpellConfig(kind, false)
                    local color = cfg and type(cfg.color) == "table" and cfg.color or CurrentAuraColor(kind)
                    return color[1] or 1, color[2] or 1, color[3] or 1
                end,
                setRGB = function(r, g, bcol)
                    local cfg = CurrentSpellConfig(kind, true)
                    if cfg then
                        local alpha = type(cfg.color) == "table" and cfg.color[4] or 1
                        cfg.color = { r, g, bcol, alpha }
                        QueueSpellIndicators(kind)
                    end
                end,
            }}
        end,
    })
    RegisterControl(state.placedColorShortcut, ctx, "spell.selected.color", "Selected Spell Color", "button", "action")
    M.ControlSchema.SetSetting(state.placedColorShortcut, Schema.Record({ "gf_{scope}.spellIndicators.specs.{spec}.{spell}.color" }))
    local function RefreshPlacedControlVisibility(placed)
        local iconSelected, barSelected, barTimerSelected = ResolvePlacedSpellIndicatorControlVisibility(placed)
        if placedSize._msuf2Title then placedSize._msuf2Title:SetText(barSelected and "Height" or "Size") end
        W.SetControlShown(placedIconEffect, iconSelected)
        W.SetControlShown(placedBarSmoothFill, barSelected)
        W.SetControlShown(placedBarShowTimer, barSelected)
        W.SetControlShown(placedBarTimerAnchor, barTimerSelected)
        W.SetControlShown(placedBarTimerX, barTimerSelected)
        W.SetControlShown(placedBarTimerY, barTimerSelected)
        return iconSelected, barSelected, barTimerSelected
    end
    -- Dropdowns are visible when constructed. Apply the selected Display-as
    -- shape immediately so a skipped/late page refresh cannot expose controls
    -- from another shape, including after toggling Preview all spells.
    RefreshPlacedControlVisibility(PlacedConfig(CurrentScope(), false))
    if M.AddTooltip then
        M.AddTooltip(placedGrowth, "Growth",
            "For Bar, the first direction controls the fill: Right fills left-to-right; " ..
                "Left fills right-to-left. Up or Down remains the secondary layout direction.",
            { hook = true, titleAsLine = true })
        M.AddTooltip(placedBarSmoothFill, "Smooth fill",
            "Uses Blizzard's native StatusBar interpolation when an active aura duration is refreshed. The countdown itself remains C-side.",
            { hook = true, titleAsLine = true })
    end
    state.placedType, state.placedAnchor, state.placedSize, state.placedBarWidth = placedType, placedAnchor, placedSize, placedBarWidth
    state.placedGrowth, state.placedIconEffect, state.placedBarSmoothFill = placedGrowth, placedIconEffect, placedBarSmoothFill
    state.placedBarShowTimer, state.placedBarTimerAnchor = placedBarShowTimer, placedBarTimerAnchor
    state.placedBarTimerX, state.placedBarTimerY, state.timerGap, state.timerSliderW = placedBarTimerX, placedBarTimerY, timerGap, timerSliderW
    state.RefreshPlacedControlVisibility = RefreshPlacedControlVisibility
end
--- Highlight Health Bar: Effect, its color and the effect sliders.
function SpellSection.BuildFrameCard(state, ctx)
    local spells, siRightX, siRightW = state.spells, state.siRightX, state.siRightW
    state.frameType = Schema.Build(ctx, spells, {
        { "dropdown", "frame", "none", { "Effect", FRAME_EFFECT_TYPES, siRightW },
            { siRightX, -490, siRightW, "LEFT" }, subtype = true, path = "spell.selected.frame.type", defaults =
        function(frame)
            if not frame.color then
                local c = CurrentAuraColor(CurrentScope())
                frame.color = { c[1] or 1, c[2] or 1, c[3] or 1, 0.8 }
            end
            frame.priority = frame.priority or 5
            frame.layer = tonumber(frame.layer) or 0
            frame.strata = frame.strata or "AUTO"
        end, afterSet = state.RefreshState },
    }, state.selectedRows).frame
    state.frameColorRelevant = false
    state.frameColorShortcut = W.AttachContextColorShortcut(state.frameHighlightCard, {
        title = "Health bar highlight",
        tooltipTitle = "Health bar highlight",
        scopeTag = state.ColorScopeTag,
        historySource = "menu:group-spell-frame-color",
        isRelevant = function() return state.frameColorRelevant end,
        getTargets = function()
            local kind = CurrentScope()
            return {{
                label = "Health bar highlight",
                getRGB = function()
                    local frame = FrameEffectConfig(kind, false)
                    local color = frame and frame.color or CurrentAuraColor(kind)
                    return color[1] or 1, color[2] or 1, color[3] or 1
                end,
                setRGB = function(r, g, bcol)
                    local frame = FrameEffectConfig(kind, true)
                    if frame then
                        -- Same order as the Tint Alpha slider, which keeps both in step.
                        local alpha = frame.alpha or (frame.color and frame.color[4]) or 0.8
                        frame.color = { r, g, bcol, alpha }
                    end
                    QueueSpellIndicators(kind)
                end,
            }}
        end,
    })
    RegisterControl(state.frameColorShortcut, ctx, "spell.frame.color", "Health bar highlight color", "button", "action")
    M.ControlSchema.SetSetting(state.frameColorShortcut, Schema.Record({ "gf_{scope}.spellIndicators.specs.{spec}.{spell}.frame.color" }))
    local rows = Schema.Build(ctx, spells, {
        { "slider", "priority", 5, { "Priority", 1, 10, 1, siRightW }, { siRightX, -544, siRightW, "LEFT" } },
        { "slider", "alpha", 25, { "Tint Alpha", 5, 100, 5, siRightW }, { siRightX, -598, siRightW, "LEFT" },
            get = function()
                local frame = FrameEffectConfig(CurrentScope(), false)
                return floor(((frame and (frame.alpha or (frame.color and frame.color[4])) or 0.25) * 100) + 0.5)
            end,
            convert = function(value) return (tonumber(value) or 25) / 100 end,
            afterWrite = function(frame, alpha) if frame.color then frame.color[4] = alpha end end },
        { "slider", "thickness", 2, { "Border / Glow Thickness", 1, 8, 1, siRightW }, { siRightX, -652, siRightW, "LEFT" } },
        { "slider", "layer", 0, { "Effect Layer (0-30)", 0, 30, 1, siRightW }, { siRightX, -706, siRightW, "LEFT" } },
    }, state.frameRows)
    state.framePriority, state.frameAlpha, state.frameThickness, state.frameLayer = rows.priority, rows.alpha, rows.thickness, rows.layer
end
--- The spell grid grows by rows; the Show on Frame card and its controls move
--- down with it and the section grows to fit.
function SpellSection.RefreshGridLayout(state, rows)
    rows = max(3, tonumber(rows) or 3)
    if rows == state.spellGridLayoutRows then return end
    state.spellGridLayoutRows = rows
    local spells, spellGrid, siLeftX, siLeftW = state.spells, state.spellGrid, state.siLeftX, state.siLeftW
    local timerSliderW, timerGap = state.timerSliderW, state.timerGap
    local extra = (rows - 3) * (spellGrid.tileSize + spellGrid.gap)
    state.spellSetCard:SetHeight(404 + extra)
    state.placedIndicatorCard:ClearAllPoints()
    state.placedIndicatorCard:SetPoint("TOPLEFT", spells, "TOPLEFT", siLeftX - 14, -456 - extra)
    W.MoveWidget(state.placedType, spells, siLeftX, -492 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedAnchor, spells, siLeftX, -546 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedSize, spells, siLeftX, -600 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarWidth, spells, siLeftX, -654 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedGrowth, spells, siLeftX, -708 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedIconEffect, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarSmoothFill, spells, siLeftX, -762 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarShowTimer, spells, siLeftX, -802 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarTimerAnchor, spells, siLeftX, -842 - extra, siLeftW, "LEFT")
    W.MoveWidget(state.placedBarTimerX, spells, siLeftX, -896 - extra, timerSliderW, "LEFT")
    W.MoveWidget(state.placedBarTimerY, spells, siLeftX + timerSliderW + timerGap, -896 - extra, timerSliderW, "LEFT")
    local contentHeight = max(1040, 1020 + extra)
    local entry = spells._msuf2CollapsibleEntry
    if entry and entry.contentHeight ~= contentHeight then
        entry.contentHeight = contentHeight
        spells:SetHeight(contentHeight)
        entry.outer:SetHeight(entry.headerHeight + (entry.open and contentHeight or 0))
        state.b:RequestRelayoutCollapsibles()
    end
end
--- One refresh gates every control of the section from the selected scope,
--- spec and spell, and sets the section badges.
function SpellSection.Refresh(state)
    local kind = CurrentScope()
    if SPELL_INDICATORS_121_PTR_DISABLED and SpellIndicators(kind).enabled ~= false then
        SpellIndicators(kind).enabled = false
        QueueSpellIndicators(kind)
    end
    EnsureSpellDefaults(kind, EffectiveSpellSpec(kind))
    SpellSection.RefreshGridLayout(state, state.spellGrid:Refresh())
    local spellCfg = SpellIndicators(kind)
    local indicatorsOn = (not SPELL_INDICATORS_121_PTR_DISABLED) and spellCfg.enabled == true
    local multi = spellCfg.spec == "multi"
    local allSpecs = multi and IsAllSpecsSpellSpec(CurrentSpellMultiSpec(kind))
    if W.SetControlShown then
        W.SetControlShown(state.multiSpecDrop, multi)
        W.SetControlShown(state.multiSpecEnabled, multi and not allSpecs)
    else
        state.multiSpecDrop:SetShown(multi)
        state.multiSpecEnabled:SetShown(multi and not allSpecs)
    end
    state.allSpecsHint:SetShown(allSpecs == true)
    local placed = PlacedConfig(kind, false)
    local hasSpell = indicatorsOn and EffectiveSpellSpec(kind) ~= nil and CurrentSpellAura(kind) ~= ""
    local currentCfg = CurrentSpellConfig(kind, false)
    local customSpell = hasSpell and IsCustomBuffEntry(CurrentSpellAura(kind), currentCfg)
    local placedEnabled = hasSpell and placed and placed.type and placed.type ~= "none"
    local frame = FrameEffectConfig(kind, false)
    local frameKind = frame and frame.type or "none"
    local hasFrame = hasSpell and frameKind ~= "none"
    state.RefreshPreviewAllButton()
    local iconSelected, barSelected, barTimerSelected = state.RefreshPlacedControlVisibility(placed)
    local cdRelevant = placedEnabled and iconSelected
    local barRelevant = placedEnabled and barSelected
    SetOptionEnabled(state.siEnable, not SPELL_INDICATORS_121_PTR_DISABLED)
    SetManyEnabled(indicatorsOn, state.siLayer, state.specDrop)
    SetOptionEnabled(state.multiSpecDrop, indicatorsOn and multi)
    SetOptionEnabled(state.multiSpecEnabled, indicatorsOn and multi and not allSpecs and CurrentSpellMultiSpec(kind) ~= "")
    local externalBlacklistManaged = hasSpell
        and CurrentSpellIsExternalDefensive(kind)
        and ExternalAutoBlacklistActive(kind)
    SetManyEnabled(hasSpell, state.spellEnabled, state.onlyMine, state.placedType)
    SetOptionEnabled(state.autoBlacklist, hasSpell and not externalBlacklistManaged)
    SetOptionEnabled(state.customSpellIDs, customSpell)
    SetManyEnabled(placedEnabled, state.placedAnchor, state.placedSize, state.placedGrowth)
    SetOptionEnabled(state.placedBarWidth, barRelevant)
    state.placedColorRelevant = placedEnabled and true or false
    if state.placedColorShortcut then state.placedColorShortcut:_msuf2RefreshContextColorVisibility() end
    SetOptionEnabled(state.placedIconEffect, cdRelevant)
    SetManyEnabled(barRelevant, state.placedBarSmoothFill, state.placedBarShowTimer)
    SetManyEnabled(barRelevant and barTimerSelected,
        state.placedBarTimerAnchor, state.placedBarTimerX, state.placedBarTimerY)
    SetOptionEnabled(state.frameType, hasSpell)
    state.frameColorRelevant = hasFrame and true or false
    if state.frameColorShortcut then state.frameColorShortcut:_msuf2RefreshContextColorVisibility() end
    SetManyEnabled(hasFrame, state.framePriority, state.frameAlpha, state.frameThickness, state.frameLayer)
    local badges = {
        OnOffBadge(indicatorsOn, "Enabled", "Disabled"),
    }
    if SPELL_INDICATORS_121_PTR_DISABLED then badges[#badges + 1] = { text = "12.1 PTR", kind = "muted", important = true } end
    badges[#badges + 1] = { text = OptionText(SpellSpecValues, SpellIndicators(kind).spec or "auto", "Auto"), kind = indicatorsOn and "info" or "muted" }
    badges[#badges + 1] = { text = hasSpell and tostring(CurrentSpellAura(kind) or "") or "No spell", kind = hasSpell and "accent" or "muted" }
    SetSectionBadgesAndStatus(state.spells, badges)
end
function SpellSection.Build(ctx, b, RefreshPage)
    local state = {}
    SpellSection.Open(state, ctx, b, RefreshPage)
    SpellSection.BuildSpecControls(state, ctx)
    SpellSection.BuildSelectedSpell(state, ctx)
    SpellSection.PrepareColorScopeTag(state)
    SpellSection.BuildPlacedCard(state, ctx)
    SpellSection.BuildFrameCard(state, ctx)
    local refresh = state.RefreshState(function() SpellSection.Refresh(state) end)
    TrackSectionRefresh(ctx, state.spells, refresh)
    GP.BuildSpellIndicatorStyleSection(ctx, b)
end

GP.BuildSpellIndicatorsSection = SpellSection.Build

--- Release links into a corner slot's Custom Spell "When" (present or missing):
--- one view per group scope and slot. The hook selects both in place.
local function DeclareExactCornerMode(control)
    local values = {}
    for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
        if MSUF.Client.SupportsGroupKind(scope) then
            for i = 1, #CI_SLOT_VALUES do
                local slot = CI_SLOT_VALUES[i].value
                values[scope .. "_" .. slot] = "gf_" .. scope .. ".ciCustom" .. slot .. ".mode"
            end
        end
    end
    return M.DeclareExactViewContract(control, "groupCornerSlot", values, function(value)
        local scope, slot = value:match("^(%a+)_(%w+)$")
        M.SetMenuStateValue("gfScope", scope)
        M.SetMenuStateValue("gfCornerSlotSelection", slot)
        return CurrentScope() == scope and CurrentCISlot() == slot
    end)
end
local function CurrentCornerField()
    local slot = CurrentCISlot()
    return "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none"
end
local function BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    local corners = b:CollapsibleSection("ci", "Corner Indicators", 674, false)
    local leftX, leftW, rightX, rightW = Schema.Columns(corners, ctx.width, 30, 28, 0.46, 240, 360, 260, 440)
    local cornerEditorCard
    do
        W.ControlCardBackdrop(corners, leftX - 14, -38, leftW + 28, 224)
        W.ControlCardBackdrop(corners, leftX - 14, -272, leftW + 28, 334)
        cornerEditorCard = W.ControlCardBackdrop(corners, rightX - 14, -38, rightW + 28, 526 + CORNER_MISSING_NOTE_GAP)
        cornerEditorCard._msuf2ControlCardTitle = "Custom Spell Editor"
    end
    W.LabelAt(corners, "Global", leftX, -42, leftW, "GameFontNormalSmall", T.colors.accent)
    local cornerRows = Schema.Build(ctx, corners, {
        { "switch", "ciEnabled", false, { "Corner Indicators", leftX, -72, leftW },
            flagsAfter = { _msuf2GroupFrameGateAlwaysEnabled = true } },
        { "slider", "ciSize", 8, { "Icon Size", 4, 24, 1, leftW }, { leftX, -116, leftW, "LEFT" } },
        { "slider", "ciAlpha", 1, { "Alpha", 10, 100, 5, leftW }, { leftX, -170, leftW, "LEFT" },
            path = "corner.alpha", binding = "scopeValue", scale = 100, fallback = 100 },
        { "slider", "ciLayer", 7, { "Layer (0-30)", 0, 30, 1, leftW }, { leftX, -224, leftW, "LEFT" } },
    }, ROW_OPTIONS)
    local ciEnable, ciSize, ciAlpha, ciLayer = cornerRows.ciEnabled, cornerRows.ciSize, cornerRows.ciAlpha, cornerRows.ciLayer
    W.LabelAt(corners, "Slot Assignments", leftX, -282, leftW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Assign what each corner dot should show. Choosing Custom Spell enables that slot's editor on the right.",
        leftX, -304, leftW, T.colors.muted)
    local slotControls = {}
    local slotPositions = {
        TL = { x = leftX, y = -358 },
        TR = { x = leftX + floor(leftW / 2) + 10, y = -358 },
        BL = { x = leftX, y = -440 },
        BR = { x = leftX + floor(leftW / 2) + 10, y = -440 },
        C = { x = leftX + floor(leftW / 4) + 4, y = -522 },
    }
    local slotW = floor((leftW - 12) / 2)
    for i = 1, #CI_SLOT_VALUES do
        local slotInfo = CI_SLOT_VALUES[i]
        local slotKey = slotInfo.value
        local p = slotPositions[slotKey] or { x = leftX, y = -304 - (i - 1) * 58 }
        local field, label = "ciSlot" .. slotKey, M.Format("%s Indicator", Tr(slotInfo.text or slotKey))
        local assignmentDrop = Schema.Build(ctx, corners, {
            { "dropdown", field, CI_SLOT_DEFAULTS[slotKey] or "none", { label, CICategoryValues, slotW }, { p.x, p.y, slotW, "LEFT" },
                path = "corner.assignment." .. tostring(slotKey), binding = "scopeValue", writeDefault = "none", afterSet = RefreshPage,
                select = { "gfCornerSlotSelection", slotKey } },
        }, ROW_OPTIONS)[field]
        slotControls[#slotControls + 1] = assignmentDrop
    end
    W.LabelAt(corners, "Custom Spell Editor", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)
    W.Text(corners, "Pick a slot, set it to Custom Spell, then enter spell IDs. This edits one slot at a time and keeps the five slot assignments visible.",
        rightX, -64, rightW, T.colors.muted)
    local editorCommands = Schema.GroupCommands({
        slot = { get = CurrentCISlot, customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            M.SetMenuStateValue("gfCornerSlotSelection", value or "TL")
            RefreshPage()
        end },
    }, ControlMeta, StepMeta)
    local slotDrop = Schema.Build(ctx, corners, {
        { "dropdown", "slot", nil, { "Editor Slot", CI_SLOT_VALUES, rightW }, { rightX, -122, rightW, "LEFT" },
            path = "corner.editor.slot", classification = "ephemeral" },
    }, editorCommands).slot
    local categoryDrop = Schema.Build(ctx, corners, {
        { "dropdown", "category", "none", { "Selected Slot Indicator", CICategoryValues, rightW }, { rightX, -176, rightW, "LEFT" },
            path = "corner.editor.category", setting = Schema.Record({ "gf_{scope}.ciSlot{selected}" }),
            binding = "scopeValue", writeDefault = "none", afterSet = RefreshPage, target = CurrentCornerField },
    }, ROW_OPTIONS).category
    local customStatus = W.Text(corners, "", rightX, -230, rightW, T.colors.muted)
    if customStatus.SetWordWrap then customStatus:SetWordWrap(true) end
    local customRows = Schema.GroupRecordOptions({ recordPath = "ciCustom{selected}.",
        companionWrites = { "gf_{scope}.ciCustom{selected}" },
        config = function(scope, create) return CICustomConfig(scope, CurrentCISlot(), create) end,
        scope = CurrentScope, changed = function(scope) QueueGF(scope, "visual") end,
        path = "corner.editor.", meta = ControlMeta, stepMeta = StepMeta,
    })
    local customSpells = Schema.Build(ctx, corners, {
        { "textinput", "spells", "", { "Spell IDs (comma-separated)", rightW }, { rightX, -286, rightW },
            path = "corner.editor.spell_ids", commitOnBlur = true },
    }, customRows).spells
    local customMode = DeclareExactCornerMode(Schema.Build(ctx, corners, {
        { "dropdown", "mode", "present", { "When", CornerModeValues, rightW }, { rightX, -350, rightW, "LEFT" },
            accept = function(value) return value ~= "missing" or CORNER_MISSING_AVAILABLE end },
    }, customRows).mode)
    if not CORNER_MISSING_AVAILABLE then
        local missingNote = W.Text(corners, "", rightX, -398, rightW, T.colors.muted)
        if missingNote.SetWordWrap then missingNote:SetWordWrap(true) end
        missingNote:SetText(CORNER_MISSING_NOTICE)
    end
    local customFilter = Schema.Build(ctx, corners, {
        { "dropdown", "filter", "HELPFUL|PLAYER", { "Filter", CIFilterValues, rightW },
            { rightX, -404 - CORNER_MISSING_NOTE_GAP, rightW, "LEFT" } },
    }, customRows).filter
    local customColor = Schema.Build(ctx, corners, {
        { "color", "color", { 0.40, 1.00, 0.40 }, { "Custom Color" }, { rightX, -458 - CORNER_MISSING_NOTE_GAP, rightW },
            channels = { "r", "g", "b" }, flagsBefore = {
                _msuf2ColorLabel = "Custom spell color", _msuf2ContextColorCardOverride = cornerEditorCard } },
    }, customRows).color
    local cornerColorShortcut
    if W.AttachContextColorShortcut then
        cornerColorShortcut = W.AttachContextColorShortcut(cornerEditorCard, {
            title = "Corner Indicator Color",
            getTargets = function()
                local slot = CurrentCISlot()
                local category = Val(CurrentScope(), "ciSlot" .. slot, CI_SLOT_DEFAULTS[slot] or "none")
                if category == "custom" then return { customColor } end
                if category == "aggro" and type(M.ResolveContextColorReferences) == "function" then
                    return M.ResolveContextColorReferences({ "group.aggro" }, {})
                end
                return {}
            end,
            note = "Uses the selected slot's Custom Spell color or the shared Corner Aggro color.",
            historySource = "menu:group-corner-indicator-color",
        })
    end
    local customHelp = W.Text(corners, "Tip: HELPFUL|PLAYER and HARMFUL|PLAYER are the safest filters because WoW exposes your own spell IDs reliably.",
        rightX, -506 - CORNER_MISSING_NOTE_GAP, rightW, T.colors.dim)
    if customHelp.SetWordWrap then customHelp:SetWordWrap(true) end
    local ciGlobalControls, ciEditorControls = { ciSize, ciAlpha, ciLayer }, { slotDrop, categoryDrop }
    local ciCustomControls = { customSpells, customMode, customFilter, customColor }
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
        if cornerColorShortcut then cornerColorShortcut:SetShown(enabled and (showCustom or category == "aggro")) end
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
            T.SetTranslatedText(customStatus, M.Format("%s is using Custom Spell. These settings are active.", Tr(slotLabel)))
            customStatus:SetTextColor(T.colors.ok[1], T.colors.ok[2], T.colors.ok[3], 0.95)
        else
            T.SetTranslatedText(customStatus, M.Format("%s is set to %s. Set Selected Slot Indicator to Custom Spell to activate this editor.",
                Tr(slotLabel), Tr(OptionText(CICategoryValues, category, "None"))))
            customStatus:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.90)
        end
    end
    TrackSectionRefresh(ctx, corners, RefreshCornerIndicatorState)
end

local function BuildGFIndicators(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.SelectPage(ctx.key) end
    BuildIndicatorsSection(ctx, b)
    StatusIcons.Build(ctx, b, RefreshPage)
    BuildCornerIndicatorsSection(ctx, b, RefreshPage)
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_indicators", { title = "MSUF Group Status & Indicators", build = BuildGFIndicators, version = 20 })

-- Explicit load-time exports for the following responsibility modules.
