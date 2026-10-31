local addonName, MSUF = ...
MSUF = MSUF or {}
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- The shared UnitFrame preview refresh is required at load and kept: unit style
-- previews refresh on every slider tick, so the hot path never resolves it.
local RequestUFPreviewRefresh = MSUF.Require("MSUF_UFPreview_RequestRefresh", FILE)
local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
local EnsureDB = M.EnsureDB

-- Menu2 Auras page.
-- Builds controls for Auras3 unit/group scopes, lanes, filters, and visual options. The page
-- talks to the Auras3 menu model; live tracking/filtering is handled by native 12.1 aura containers.
local W = M.Widgets
local T = M.Theme

local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel

local VTP = M.ValueTextPairs

if type(W) ~= "table" or type(T) ~= "table" or type(Model) ~= "table" then return end
-- Load-time dependency handoff; runtime callbacks retain their original local bindings.
local Parts = {}
M.AurasParts = Parts
-- Page builders share only the late-bound preview entry points. Settings and
-- control primitives have independent owners loaded before all aura pages.
local AurasPage = {}
local Schema, ROW_OPTIONS = M.ControlSchema, M.ControlSchema.UnitOptions()
-- Composite chrome (navigation, actions, selectors, native row grids) keeps its
-- registered owner; this declares it after that owner's sole binding. A widget
-- the search registry skipped (no widget, a noise or short label) has no record
-- and stays as the native registration left it.
function AurasPage.Own(widget)
    local record = widget and widget._msuf2RuntimeControlRecord
    if not record then return widget end
    if record.kind == "segment" then
        Schema.ScopeOwner(widget, "auras", "menuState")
        M.ControlSchema.SetSetting(widget, nil)
        widget._msuf2ControlSchema.ephemeralReason = "Selects the aura workspace; no profile setting is written."
        return widget
    end
    Schema.Owned(widget, "auras", record.classification == "ephemeral" and "menuState" or "auras")
    if record.kind == "dropdown" then widget._msuf2ControlSchema.values = widget.values end
    return widget
end
function AurasPage.Bound(native) return function(...) return AurasPage.Own(native(...)) end end
function AurasPage.Section(builder, ...) return Schema.Section(builder:CollapsibleSection(...), "auras") end
-- Ordinary aura controls are schema rows: Schema.Build creates, binds (through
-- the shared unit row policy) and places them. Each row's get/set pair keeps the
-- existing writer, apply reason and refresh; the metadata names the stable ID.
-- Ephemeral selectors and inputs declare menuState, settings the aura domain.
local function PrepareRow(row, scope)
    if type(row.set) == "table" then row.write, row.set = row.set.write, nil end
    row.customSetReason = row.customSetReason or "Resolves the selected aura scope and lane, canonicalizes values and requests the aura runtime."
    local meta = row.meta
    row[2], row[3] = meta.controlId, meta.fallback
    row.scope = scope or "auras"
    row.domain = meta.ephemeral and "menuState" or "auras"
    if row.scope == "groups" then
        row.companionWrites = { "gf_party.auras.renderer", "gf_raid.auras.renderer", "gf_mythicraid.auras.renderer" }
    end
    return row
end
function AurasPage.Row(ctx, parent, row, scope)
    PrepareRow(row, scope)
    local widget = Schema.Build(ctx, parent, { row }, ROW_OPTIONS)[row[2]]
    if row[1] == "dropdown" then widget._msuf2ControlSchema.values = widget.values end
    return widget
end
-- A native widget that must exist before its binding (a picker target whose
-- shortcut is attached first) binds through the same row policy.
function AurasPage.BindRow(ctx, widget, kind, row, scope)
    Schema.UnitBinding(ctx, widget, PrepareRow(row, scope), kind)
    return widget
end
-- Positional row constructors with the former native binder signatures, so a
-- call site reads as before while the schema owns construction and binding.
function AurasPage.Switch(ctx, parent, label, x, y, width, get, set, meta)
    return AurasPage.Row(ctx, parent, { "switch", nil, nil, { label, x, y, width or 180 }, get = get, set = set, meta = meta })
end
function AurasPage.Slider(ctx, parent, label, x, y, minVal, maxVal, step, width, get, set, meta)
    return AurasPage.Row(ctx, parent, { "slider", nil, nil, { label, minVal, maxVal, step, width }, { x, y, width },
        get = get, set = set, meta = meta })
end
function AurasPage.Dropdown(ctx, parent, label, x, y, values, width, get, set, meta)
    return AurasPage.Row(ctx, parent, { "dropdown", nil, nil, { label, values, width }, { x, y, width },
        get = get, set = set, meta = meta })
end
function AurasPage.TextInput(ctx, parent, label, x, y, width, get, set, commitOnBlur, meta)
    return AurasPage.Row(ctx, parent, { "textinput", nil, nil, { label, width }, { x, y, width },
        get = get, set = set, meta = meta, commitOnBlur = commitOnBlur, textAdapter = true })
end
function AurasPage.BindColor(ctx, widget, get, set, meta)
    return AurasPage.BindRow(ctx, widget, "color", { [4] = { widget._msuf2ColorLabel }, get = get, set = set, meta = meta })
end
local CreateFrame = CreateFrame
local C_Timer = M.MenuTimer or C_Timer
local function FlushApplyService()
    ApplyService.Flush()
end
-- Icon-style art and apply timing shared by the nested Aura workspaces.
M.AURA_SHADOW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Borders\\msuf_aura_border_shadow.tga"
M.AURA_ICON_STYLE_APPLY_DELAY = 0.18
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local AccessibleNumber = M.AuraSettings.AccessibleNumber
local AURA_SCOPE_LABELS = M.AuraSettings.AURA_SCOPE_LABELS

local LANE_VALUES = M.AuraControls.LANE_VALUES
-- Appearance > Auras owns only the genuinely global Aura theme selected
-- by Aura product. Every layout/filter/deep-Style value remains frame-local.
M.SHARED_AURA_STYLE_CONTAINER_VALUES = VTP
    "buff=Buffs|debuff=Debuffs|playerDefensives=Player Defensives|targetDots=Dots on Target"
-- Optional menu providers own their controls and profile data. No provider
-- leaves the original selector and all Blizzard visibility controls intact.
local appearanceTypes, appearanceValues = {}, nil
function AurasPage.RegisterAppearanceType(value, spec)
    assert(value ~= "buff" and value ~= "debuff" and value ~= "playerDefensives" and value ~= "targetDots")
    assert(spec.text and spec.build and spec.resetProvider)
    appearanceTypes[value] = spec
    appearanceValues = nil
    M.InvalidatePage("auras3_styling")
    M.InvalidatePage("auras3_buffs")
    M.InvalidatePage("auras3_debuffs")
    return true
end
function AurasPage.AppearanceType(value)
    return appearanceTypes[value]
end
function AurasPage.AppearanceValues()
    if not next(appearanceTypes) then return M.SHARED_AURA_STYLE_CONTAINER_VALUES end
    if not appearanceValues then
        appearanceValues = {}
        for _, value in ipairs(M.SHARED_AURA_STYLE_CONTAINER_VALUES) do
            appearanceValues[#appearanceValues + 1] = value
        end
        for value, spec in pairs(appearanceTypes) do
            appearanceValues[#appearanceValues + 1] = { value = value, text = spec.text }
        end
    end
    return appearanceValues
end
function AurasPage.BlizzardVisibilityType()
    for value, spec in pairs(appearanceTypes) do
        if spec.blizzardVisibility then return value end
    end
end
function AurasPage.AppearanceResetProvider(pageKey)
    if pageKey ~= "auras3_styling" then return nil end
    local spec = appearanceTypes[M.auraAppearanceContainer]
    return spec and spec.resetProvider
end
local UNIT_STYLE_CONTAINER_VALUES = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target"
local UNIT_STYLE_CONTAINER_VALUES_PLAYER = VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensive Buffs"
local CUSTOM_FRAME_EFFECTS = M.AuraSettings.CUSTOM_FRAME_EFFECTS
local DEBUFF_TYPE_BORDER_MODE_VALUES = M.AuraSettings.DEBUFF_TYPE_BORDER_MODE_VALUES
local COOLDOWN_SWIPE_DIRECTION_VALUES = M.AuraSettings.COOLDOWN_SWIPE_DIRECTION_VALUES
M.AURA_STEALABLE_STYLE_VALUES = M.AURA_STEALABLE_STYLE_VALUES
    or VTP "BORDER=Border|BORDER_ICON=Border + Icon|ICON=Icon"
M.AURA_PANDEMIC_STYLE_VALUES = M.AURA_PANDEMIC_STYLE_VALUES
    or VTP "BORDER=Border|TINT=Tint|BORDER_TINT=Border + Tint"
M.AURA_PANDEMIC_BLEND_VALUES = M.AURA_PANDEMIC_BLEND_VALUES or VTP "ADD=Additive|BLEND=Normal"
local AURA_SORT_DIRECTION_VALUES = M.AuraSettings.AURA_SORT_DIRECTION_VALUES
local DURATION_BAR_DISPLAY_VALUES = M.AuraSettings.DURATION_BAR_DISPLAY_VALUES
local DURATION_BAR_POSITION_VALUES = M.AuraSettings.DURATION_BAR_POSITION_VALUES
local DURATION_BAR_DIRECTION_VALUES = M.AuraSettings.DURATION_BAR_DIRECTION_VALUES
M.AURA_ICON_SHAPE_VALUES = VTP("RECTANGLE=Rectangular (current)|FOLLOW_PORTRAIT=Follow frame portrait|CIRCLE=Circle|ROUNDED=Rounded|DIAMOND=Diamond|"
    .. "HEXAGON=Hexagon|STAR=Star|BLIZZARD=Blizzard portrait")
--- The aura icon shapes for icons with no portrait to follow (castbar icons, the PvP trinket).
function M.IconShapeValues()
    local values = {}
    for _, item in ipairs(M.AURA_ICON_SHAPE_VALUES) do
        if item.value ~= "FOLLOW_PORTRAIT" then values[#values + 1] = item end
    end
    return values
end
local AURA_COOLDOWN_COLOR_REFERENCES = M.AuraSettings.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_DURATION_BAR_COLOR_REFERENCES = M.AuraSettings.AURA_DURATION_BAR_COLOR_REFERENCES
local AURA_SHARED_COLOR_NOTE = M.AuraSettings.AURA_SHARED_COLOR_NOTE
-- `title` arrives already localized; only the surrounding wording is a format key.
function M.AttachAuraFontsAndColors(section, title, unit)
    if not (section and W.AttachContextColorReferences) then return end
    local references = AURA_COOLDOWN_COLOR_REFERENCES()
    if #references == 1 then references[2] = AURA_DURATION_BAR_COLOR_REFERENCES[1] end
    W.AttachContextColorReferences(section, references, {
        title = M.Format("%s Fonts & Colors", title),
        historyLabel = M.Format("%s color", title),
        historySource = "menu:auras-fonts-colors",
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
        tooltipTitle = "Aura fonts & colors",
        tooltipText = "Open the shared font and colors used by every Aura scope.",
        textSettings = {
            scope = "shared",
            unit = unit,
            kind = "aura",
            colorReferences = references,
            colorTitle = M.Format("%s Colors", title),
            colorScopeTag = "Shared",
            colorNote = AURA_SHARED_COLOR_NOTE,
            subtitle = "Aura text follows the shared Fonts settings; duration colors stay synchronized with Aura Colors.",
            capabilities = {
                opacity = false, baseline = false,
                shadowAlpha = false, shadowDistance = false,
            },
        },
    })
end
local AuraSortMethodValues = M.AuraSettings.AuraSortMethodValues
local ChoiceLabel = M.AuraSettings.ChoiceLabel
local AnchorLabel = M.AuraSettings.AnchorLabel
local NormalizeAuraSortMethodForLane = M.AuraSettings.NormalizeAuraSortMethodForLane

-- The client model owns the answer, so a Mainline-family client (WoW Forever
-- included) keeps every Retail filter whatever project ID it reports and the
-- raw project is never asked here.
M.CLASSIC_AURA_FILTERS_REDUCED = MSUF.Client.IsClassic == true
local Tr = M.AuraSettings.Tr
-- Search-result suffix shared by every aura list status line.
local MatchSuffix = M.AuraSettings.MatchSuffix
local AuraCatalogToken = M.AuraControls.AuraCatalogToken

local function LaneFrameEffectSearchRouteMetadata(unit, lane, field)
    if field == "type" then
        return "auras3." .. tostring(unit or "shared") .. "."
            .. (lane == "buff" and "buff" or "debuff") .. ".frameEffectType"
    end
    return {}
end
M._customContainerSearchSuffixes = {
    "enabled", "filters.enabled", "filters.hidePermanent", "filters.onlyMine",
    "filters.onlyImportant", "filters.raid", "filters.raidInCombat",
    "filters.includeNameplateOnly", "filters.includeDispellable", "filters.dispellableAny",
    "filters.cancelable", "filters.notCancelable", "filters.externalDefensive",
    "filters.bigDefensive", "filters.crowdControl", "placed.anchor", "placed.growth",
    "placed.x", "placed.y", "placed.max", "placed.size", "placed.perRow", "placed.spacing",
    "placed.showStacks", "placed.showCooldown", "placed.showCooldownSwipe",
    "placed.reminderEnabled", "placed.reminderAlpha", "placed.reminderDesaturate",
    "placed.reminderClickCast", "placed.reminderOnlyCastable",
    "reminderEnchantMainHand", "reminderEnchantOffHand", "reminderEnchantDurationMinutes",
}
local AuraControlMeta = M.AuraControls.AuraControlMeta
local AuraControlMetaAtVisiblePath = M.AuraControls.AuraControlMetaAtVisiblePath
local RegisterAuraControl = AurasPage.Bound(M.AuraControls.RegisterAuraControl)
local RegisterAuraTextAction = AurasPage.Bound(M.AuraControls.RegisterAuraTextAction)
local function RegisterAuraChoiceBar(ctx, bar, values, path, routeContract)
    if not bar then return bar end
    RegisterAuraControl(ctx, bar, bar._msuf2SearchTitle or "Editing", "segment", path,
        routeContract and "setting" or "ephemeral", routeContract)
    return bar
end
local Round = M.AuraSettings.Round
local NormalizeDebuffTypeBorderMode = M.AuraSettings.NormalizeDebuffTypeBorderMode
local AddTooltip = M.AuraControls.AddTooltip
local AddAuraTooltipHelp = M.AuraControls.AddAuraTooltipHelp
local ActionButton = M.AuraControls.ActionButton
local CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY = "auraEnemyDebuffBlacklistInfoSeen"
local CUSTOM_DEBUFF_BLACKLIST_INFO_TITLE = "UnitFrame Debuff blacklist"
local CUSTOM_DEBUFF_BLACKLIST_INFO_BODY = "You can blacklist any debuff applied by the player on the %s UnitFrame using its exact Spell ID. The debuff on the "
    .. "unit can carry a different Spell ID than the spell you cast - use the ID from the debuff itself."

local function CustomDebuffBlacklistInfoSeen()
    local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    return type(general) == "table" and general[CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY] == true
end

local function StopCustomDebuffBlacklistInfoPulse(button)
    local pulse = button and button._msuf2CustomDebuffBlacklistInfoPulse
    if pulse and pulse.Stop then pulse:Stop() end
    if button and button.SetAlpha then button:SetAlpha(1) end
end

local function CreateCustomDebuffBlacklistInfoButton(parent, input, unit)
    local button = ActionButton(parent, "I", 28)
    button:SetSize(28, 26)
    button._msuf2SkipHistoryCheckpoint = true
    button._msuf2AllowCombatClick = true
    if M.MarkRuntimeControlComponent and input then M.MarkRuntimeControlComponent(button, input) end
    if T.CenterButtonLabel then T.CenterButtonLabel(button) end
    if button._msuf2Label and T.ApplyMenuFont then
        T.ApplyMenuFont(button._msuf2Label, 3, "heading")
    end
    local labelAnchor = input and input._msuf2Title
    if labelAnchor then
        local textWidth = labelAnchor.GetStringWidth and tonumber(labelAnchor:GetStringWidth()) or nil
        local titleWidth = labelAnchor.GetWidth and tonumber(labelAnchor:GetWidth()) or nil
        if textWidth and textWidth > 0 then
            local visibleTextWidth = titleWidth and min(textWidth, max(0, titleWidth - 36)) or textWidth
            button:SetPoint("LEFT", labelAnchor, "CENTER", floor((visibleTextWidth * 0.5) + 8), 0)
        else
            button:SetPoint("LEFT", labelAnchor, "RIGHT", 8, 0)
        end
    end
    local unitLabel = M.Tr(AURA_SCOPE_LABELS[unit] or tostring(unit or "Unit"))
    AddTooltip(button, CUSTOM_DEBUFF_BLACKLIST_INFO_TITLE,
        M.Format(CUSTOM_DEBUFF_BLACKLIST_INFO_BODY, unitLabel))
    button:SetScript("OnClick", function(self)
        local general = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
        if type(general) == "table" then general[CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY] = true end
        StopCustomDebuffBlacklistInfoPulse(self)
        return true
    end)

    if not CustomDebuffBlacklistInfoSeen()
        and button.CreateAnimationGroup
        and not (T.ReducedMotionEnabled and T.ReducedMotionEnabled())
    then
        local pulse = button:CreateAnimationGroup()
        if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(pulse) end
        if pulse.SetLooping then pulse:SetLooping("REPEAT") end
        local fadeOut = pulse:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end
        local fadeIn = pulse:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        if fadeIn.SetSmoothing then fadeIn:SetSmoothing("IN_OUT") end
        if pulse.SetScript then pulse:SetScript("OnStop", function() button:SetAlpha(1) end) end
        button._msuf2CustomDebuffBlacklistInfoPulse = pulse
        pulse:Play()
    end
    return button
end

local Rebuild = M.AuraControls.Rebuild
local function SelectPage(pageKey, scope)
    if scope then
        M.SetMenuStateValue("auraScope", scope)
        if scope == "party" or scope == "raid" then M.SetMenuStateValue("auraStyleGFScope", scope) end
    end
    if M.SelectPage then M.SelectPage(pageKey or "auras3") end
end
local RequestAuraRuntime = M.AuraControls.RequestAuraRuntime

local function HandleNestedScrollWheel(scrollFrame, delta, step)
    delta = tonumber(delta) or 0
    if delta == 0 or not scrollFrame then return end
    local range = AccessibleNumber(scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0, 0)
    local current = AccessibleNumber(scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll() or 0, 0)
    local leavingTop = delta > 0 and current <= 0.01
    local leavingBottom = delta < 0 and current >= range - 0.01
    if range <= 0 or leavingTop or leavingBottom then
        local main = M.scrollFrame
        local handler = main and main.GetScript and main:GetScript("OnMouseWheel")
        if type(handler) == "function" and main ~= scrollFrame then
            if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
            handler(main, delta)
        elseif scrollFrame.SetPropagateMouseWheel then
            scrollFrame:SetPropagateMouseWheel(true)
        end
        return
    end
    if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
    local value = current - (delta * (tonumber(step) or 42))
    if value < 0 then value = 0 elseif value > range then value = range end
    if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(value) end
end

function M._StyleNestedAuraScrollFrame(scrollFrame, anchor, step)
    if not scrollFrame then return end
    if scrollFrame.SetPropagateMouseWheel then scrollFrame:SetPropagateMouseWheel(false) end
    if type(T.StyleScrollFrame) == "function" then T.StyleScrollFrame(scrollFrame, anchor) end
    local function OnMouseWheel(_, delta)
        HandleNestedScrollWheel(scrollFrame, delta, step)
    end
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end
    scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)
    local child = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
    if child and child.EnableMouseWheel then
        child:EnableMouseWheel(true)
        child:SetScript("OnMouseWheel", OnMouseWheel)
    end
    local bar = scrollFrame._msuf2ScrollBar
    if bar and bar.EnableMouseWheel then
        bar:EnableMouseWheel(true)
        bar:SetScript("OnMouseWheel", OnMouseWheel)
    end
end

local QueueAurasPageRefresh = M.AuraControls.QueueAurasPageRefresh
local ApplyUnit = M.AuraControls.ApplyUnit
local BindSwitch, BindSlider = AurasPage.Switch, AurasPage.Slider
local BindDropdown, BindTextInput = AurasPage.Dropdown, AurasPage.TextInput
local ConfigureMaxDurationSlider = M.AuraControls.ConfigureMaxDurationSlider
local CurrentScope = M.AuraSettings.CurrentScope
local IsGroupScope = M.AuraSettings.IsGroupScope
local function FinishPage(ctx, b)
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 42) end
end
local CurrentLane = M.AuraSettings.CurrentLane
local SetCurrentLane = M.AuraSettings.SetCurrentLane
local LaneTitle = M.AuraSettings.LaneTitle
-- The ::: text shortcut of an aura text section (stack or cooldown text) on the
-- unit, custom and group Style pages: the shared Fonts text settings with the
-- section's colors; opacity, baseline and shadow tuning stay hidden. unit is
-- the frame scope whose text the picker previews (nil on Group Frames).
function AurasPage.AttachTextColorShortcut(section, unit, opts, textSettings)
    if not W.AttachContextColorShortcut then return end
    opts.scopeTag, opts.note = "Shared", AURA_SHARED_COLOR_NOTE
    textSettings.scope, textSettings.unit, textSettings.kind = "shared", unit, "aura"
    textSettings.capabilities = {
        opacity = false, baseline = false,
        shadowAlpha = false, shadowDistance = false,
    }
    opts.textSettings = textSettings
    W.AttachContextColorShortcut(section, opts)
end
-- The Duration Bar section's ::: color: the shared "safe" cooldown color.
function AurasPage.AttachDurationBarColor(section, lane)
    W.AttachContextColorReferences(section, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = M.Format("%s Duration Bar Color", Tr(LaneTitle(lane))),
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
end

local function CurrentAuraStyleContainer(scope)
    local container = scope == "appearance"
        and (M.auraAppearanceContainer or CurrentLane("auraStyleGFLane", "debuff"))
        or (M.auraStyleContainer or CurrentLane("auraStyleGFLane", "debuff"))
    if scope == "appearance" then
        if container ~= "buff" and container ~= "debuff"
            and container ~= "playerDefensives" and container ~= "targetDots"
            and not appearanceTypes[container]
        then
            container = CurrentLane("auraStyleGFLane", "debuff")
        end
        return container
    end
    local custom = tostring(container):match("^custom[1234]$") ~= nil
    if container ~= "buff" and container ~= "debuff" and not custom then container = "debuff" end
    if IsGroupScope(scope) and custom then
        container = CurrentLane("auraStyleGFLane", "debuff")
    end
    return container
end
--- The lane the Global Aura Appearance page themes for a container: Dots on
--- target and Debuffs are harmful, every other container helpful.
local function AppearanceThemeLane(container)
    return (container == "targetDots" or container == "debuff") and "debuff" or "buff"
end
local function BuildAuraStyleNav(ctx, b, scope)
    local values = scope == "appearance" and AurasPage.AppearanceValues()
        or ((not IsGroupScope(scope))
            and (scope == "player" and UNIT_STYLE_CONTAINER_VALUES_PLAYER or UNIT_STYLE_CONTAINER_VALUES)
            or LANE_VALUES)
    local h = 56
    if scope == "appearance" and next(appearanceTypes) then
        local metrics = W.MeasureScopeOverrideBar(values, { width = b.width, labelWidth = 88, centerY = -28 })
        h = max(h, abs(metrics.bottomY) + 16)
    end
    local section = T.Panel(b.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    T.ApplySurface(section, "card")
    section:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    section:SetSize(b.width, h)
    section._msuf2Width = b.width
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, section, "Aura container") end
    b.y = b.y - h - 12
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 28) end
    local w = section._msuf2Width or b.width or 720
    local bar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = w,
        label = scope == "appearance" and "Aura type:" or "Container:",
        labelWidth = 88,
        centerY = -28,
        getValue = function() return CurrentAuraStyleContainer(scope) end,
        setValue = function(container)
            M.SetMenuStateValue(scope == "appearance" and "auraAppearanceContainer" or "auraStyleContainer", container)
            if scope == "appearance" then
                SetCurrentLane("auraStyleGFLane", AppearanceThemeLane(container))
            elseif container == "buff" or container == "debuff" then
                SetCurrentLane("auraStyleGFLane", container)
            end
            local key = (ctx and ctx.key) or M.activeKey
            if key == "auras3_buffs" or key == "auras3_debuffs" then
                SelectPage("auras3_styling", CurrentScope())
            else
                Rebuild(ctx)
            end
        end,
    }), values, "style.container.selector")
    local current = CurrentAuraStyleContainer(scope)
    local title = current == "playerDefensives" and Tr("Player Defensives Appearance Preview")
        or current == "targetDots" and Tr("Dots on Target Appearance Preview")
        or scope == "appearance" and M.Format("%s Appearance Preview", Tr(LaneTitle(current)))
        or current == "custom4" and (scope == "player" and Tr("Defensive Buff Aura Style") or Tr("Dots on target Aura Style"))
        or (tostring(current):match("^custom[123]$") and M.Format("Custom %s Aura Style", tostring(current):match("(%d)$")))
        or M.Format("%s Aura Style", Tr(LaneTitle(current)))
    if not appearanceTypes[current] then M.AttachAuraFontsAndColors(section, title, scope) end
    -- Dock the container strip beneath the already-docked scope strip, like
    -- the unit pages' Editing strip: scope, container and preview form one fixed
    -- stack before the settings ScrollFrame begins.
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(section, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            builder = b,
            ctx = ctx,
            flowGap = 12,
        })
    end
    return current
end
local LaneMaxKey = M.AuraSettings.LaneMaxKey
local LaneSizeKey = M.AuraSettings.LaneSizeKey
local LaneDefaultMax = M.AuraSettings.LaneDefaultMax
local function UnitLaneShown(unit, kind)
    return Model.UnitEnabled(unit) and Model.GroupShown(unit, kind)
end
local UNIT_AURA_DISPEL_WARNING = "Dispel Border, Overlay, and Symbol need this UnitFrame's Aura sensor. Enable Buffs or Debuffs, or turn on a Dispel feature "
    .. "to enable the sensor automatically. Set both icon caps to 0 if you want no aura icons."
local function UnitAuraSensorEnabled(unit)
    return Model.UnitEnabled(unit) == true
end
local ModeEnabled = MSUF.Require("MSUF_UF_OutlineModeEnabled", FILE)
local function UnitDispelRequested(unit)
    local db = EnsureDB()
    local general = type(db) == "table" and type(db.general) == "table" and db.general or nil
    local conf = type(db) == "table" and type(db[unit]) == "table" and db[unit] or nil
    local overlay = conf and conf.unitDispelOverlayEnabled
    if overlay == nil then overlay = general and general.unitDispelOverlayEnabled end
    local symbol = conf and conf.unitDispelSymbolEnabled
    if symbol == nil then symbol = general and general.unitDispelSymbolEnabled end
    if overlay == true or symbol == true then return true end
    local mode
    if conf and conf.hlOverride == true then mode = conf.dispelOutlineMode end
    if mode == nil then mode = general and general.dispelOutlineMode end
    local legacy = general and (general.dispelBorderEnabled == true or general.hlDispelBorderEnabled == true)
    if general and general.dispelBorderEnabled == nil and general.hlDispelBorderEnabled == nil then legacy = true end
    return ModeEnabled(mode, legacy)
end
local function ShowNoUnitAuraDispelWarning()
    if type(M.ShowStatusFeedback) == "function" then
        M.ShowStatusFeedback(UNIT_AURA_DISPEL_WARNING, "warning", 3.0)
    end
end
local function SetUnitLaneShown(ctx, unit, kind, shown, reason)
    if shown then
        Model.SetUnitEnabled(unit, true)
        Model.SetGroupShown(unit, kind, true)
    else
        Model.SetGroupShown(unit, kind, false)
        -- Hiding the last native lane must not disable the shared Aura sensor.
        -- A 0 icon cap is the supported sensor-only state used by Dispel.
    end
    ApplyUnit(ctx, unit, reason or "AURAS3_VISIBILITY", true)
    if UnitDispelRequested(unit) and not UnitAuraSensorEnabled(unit) then ShowNoUnitAuraDispelWarning() end
end
local GFAnchorValues = M.AuraSettings.GFAnchorValues
-- A lane duration-bar choice (Display, Position, Fill Mode): the backend's lane
-- accessor when it has one, otherwise the unit-wide value. Only `alternate` or
-- `fallback` is ever read back or stored.
local function LaneDurationBarChoice(unit, lane, name, key, fallback, alternate)
    local readName, writeName = "ReadLane" .. name, "WriteLane" .. name
    local function Read()
        if type(Model[readName]) == "function" then return Model[readName](unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, key, fallback) or fallback
        return value == alternate and alternate or fallback
    end
    local function Write(value)
        value = value == alternate and alternate or fallback
        if type(Model[writeName]) == "function" then
            Model[writeName](unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, key, value)
        end
    end
    return Read, Write
end
-- The scope readers and writers of one Unit Style build. The global Appearance
-- page reads the shared appearance of its aura type; a frame reads its lane.

-- Explicit load-time exports for the following responsibility modules.
Parts.A3 = A3
Parts.AURA_COOLDOWN_COLOR_REFERENCES = AURA_COOLDOWN_COLOR_REFERENCES
Parts.AURA_SHARED_COLOR_NOTE = AURA_SHARED_COLOR_NOTE
Parts.AURA_SORT_DIRECTION_VALUES = AURA_SORT_DIRECTION_VALUES
Parts.ActionButton = ActionButton
Parts.AddAuraTooltipHelp = AddAuraTooltipHelp
Parts.AddTooltip = AddTooltip
Parts.AppearanceThemeLane = AppearanceThemeLane
Parts.ApplyService = ApplyService
Parts.ApplyUnit = ApplyUnit
Parts.AuraCatalogToken = AuraCatalogToken
Parts.AuraControlMeta = AuraControlMeta
Parts.AuraControlMetaAtVisiblePath = AuraControlMetaAtVisiblePath
Parts.AuraSortMethodValues = AuraSortMethodValues
Parts.AurasPage = AurasPage
Parts.BindDropdown = BindDropdown
Parts.BindSlider = BindSlider
Parts.BindSwitch = BindSwitch
Parts.BindTextInput = BindTextInput
Parts.BuildAuraStyleNav = BuildAuraStyleNav
Parts.COOLDOWN_SWIPE_DIRECTION_VALUES = COOLDOWN_SWIPE_DIRECTION_VALUES
Parts.CUSTOM_FRAME_EFFECTS = CUSTOM_FRAME_EFFECTS
Parts.C_Timer = C_Timer
Parts.ChoiceLabel = ChoiceLabel
Parts.ConfigureMaxDurationSlider = ConfigureMaxDurationSlider
Parts.CreateCustomDebuffBlacklistInfoButton = CreateCustomDebuffBlacklistInfoButton
Parts.CreateFrame = CreateFrame
Parts.CurrentAuraStyleContainer = CurrentAuraStyleContainer
Parts.CurrentLane = CurrentLane
Parts.DEBUFF_TYPE_BORDER_MODE_VALUES = DEBUFF_TYPE_BORDER_MODE_VALUES
Parts.DURATION_BAR_DIRECTION_VALUES = DURATION_BAR_DIRECTION_VALUES
Parts.DURATION_BAR_DISPLAY_VALUES = DURATION_BAR_DISPLAY_VALUES
Parts.DURATION_BAR_POSITION_VALUES = DURATION_BAR_POSITION_VALUES
Parts.FinishPage = FinishPage
Parts.FlushApplyService = FlushApplyService
Parts.GFAnchorValues = GFAnchorValues
Parts.LaneDefaultMax = LaneDefaultMax
Parts.LaneDurationBarChoice = LaneDurationBarChoice
Parts.LaneFrameEffectSearchRouteMetadata = LaneFrameEffectSearchRouteMetadata
Parts.LaneMaxKey = LaneMaxKey
Parts.LaneSizeKey = LaneSizeKey
Parts.LaneTitle = LaneTitle
Parts.Model = Model
Parts.NormalizeAuraSortMethodForLane = NormalizeAuraSortMethodForLane
Parts.NormalizeDebuffTypeBorderMode = NormalizeDebuffTypeBorderMode
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.QueueAurasPageRefresh = QueueAurasPageRefresh
Parts.Rebuild = Rebuild
Parts.RegisterAuraChoiceBar = RegisterAuraChoiceBar
Parts.RegisterAuraControl = RegisterAuraControl
Parts.RegisterAuraTextAction = RegisterAuraTextAction
Parts.RequestAuraRuntime = RequestAuraRuntime
Parts.RequestUFPreviewRefresh = RequestUFPreviewRefresh
Parts.Round = Round
Parts.SelectPage = SelectPage
Parts.SetCurrentLane = SetCurrentLane
Parts.SetUnitLaneShown = SetUnitLaneShown
Parts.T = T
Parts.Tr = Tr
Parts.UNIT_AURA_DISPEL_WARNING = UNIT_AURA_DISPEL_WARNING
Parts.UnitAuraSensorEnabled = UnitAuraSensorEnabled
Parts.UnitDispelRequested = UnitDispelRequested
Parts.UnitLaneShown = UnitLaneShown
Parts.VTP = VTP
Parts.W = W
Parts.abs = abs
Parts.floor = floor
Parts.max = max
Parts.min = min
Parts.pairs = pairs
Parts.tonumber = tonumber
Parts.tostring = tostring
Parts.type = type
Parts.AnchorLabel = AnchorLabel
