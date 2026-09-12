local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
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
-- Page builders share only the late-bound preview entry points. Settings and
-- control primitives have independent owners loaded before all aura pages.
local AurasPage = {}
local CreateFrame = _G.CreateFrame
local C_Timer = M.MenuTimer or _G.C_Timer
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
M.AURA_ICON_SHAPE_VALUES = VTP "RECTANGLE=Rectangular (current)|FOLLOW_PORTRAIT=Follow frame portrait|CIRCLE=Circle|ROUNDED=Rounded|DIAMOND=Diamond|HEXAGON=Hexagon|STAR=Star|BLIZZARD=Blizzard portrait"
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


M.CLASSIC_AURA_FILTERS_REDUCED = MSUF.Client and MSUF.Client.IsClassic == true
    or (_G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_ID ~= _G.WOW_PROJECT_MAINLINE)
local Tr = M.AuraSettings.Tr
-- Search-result suffix shared by every aura list status line.
local MatchSuffix = M.AuraSettings.MatchSuffix
local AuraCatalogToken = M.AuraControls.AuraCatalogToken

local function LaneFrameEffectAssistantContract(unit, lane, field)
    if field == "type" then
        return "auras3." .. tostring(unit or "shared") .. "."
            .. (lane == "buff" and "buff" or "debuff") .. ".frameEffectType"
    end
    return {
        assistantDisposition = "compound",
        assistantDispositionReason = "This Full-Frame effect detail shares a compound color or numeric value; only its Effect dropdown has a direct Assistant setting contract.",
    }
end
M._customContainerAssistantSuffixes = {
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
local RegisterAuraControl = M.AuraControls.RegisterAuraControl
local RegisterAuraTextAction = M.AuraControls.RegisterAuraTextAction
local function RegisterAuraChoiceBar(ctx, bar, values, path, assistantContract)
    if not bar then return bar end
    RegisterAuraControl(ctx, bar, bar._msuf2SearchTitle or "Editing", "segment", path,
        assistantContract and "setting" or "ephemeral", assistantContract)
    return bar
end
local Round = M.AuraSettings.Round
local NormalizeDebuffTypeBorderMode = M.AuraSettings.NormalizeDebuffTypeBorderMode
local AddTooltip = M.AuraControls.AddTooltip
local AddAuraTooltipHelp = M.AuraControls.AddAuraTooltipHelp
local ActionButton = M.AuraControls.ActionButton

local CUSTOM_DEBUFF_BLACKLIST_INFO_SEEN_KEY = "auraEnemyDebuffBlacklistInfoSeen"
local CUSTOM_DEBUFF_BLACKLIST_INFO_TITLE = "UnitFrame Debuff blacklist"
local CUSTOM_DEBUFF_BLACKLIST_INFO_BODY = "You can blacklist any debuff applied by the player on the %s UnitFrame using its exact Spell ID. The debuff on the unit can carry a different Spell ID than the spell you cast - use the ID from the debuff itself."

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
local BindSwitch, BindSlider = M.BindSwitchAt, M.BindSliderAt
local BindDropdown, BindTextInput = M.BindDropdownAt, M.BindTextInputAt
local ConfigureMaxDurationSlider = M.AuraControls.ConfigureMaxDurationSlider

local CurrentScope = M.AuraSettings.CurrentScope
local IsGroupScope = M.AuraSettings.IsGroupScope

local function FinishPage(ctx, b)
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 42) end
end
local CurrentLane = M.AuraSettings.CurrentLane
local SetCurrentLane = M.AuraSettings.SetCurrentLane

local LaneTitle = M.AuraSettings.LaneTitle

local function CurrentAuraStyleContainer(scope)
    local container = scope == "appearance"
        and (M.auraAppearanceContainer or CurrentLane("auraStyleGFLane", "debuff"))
        or (M.auraStyleContainer or CurrentLane("auraStyleGFLane", "debuff"))
    if scope == "appearance" then
        if container ~= "buff" and container ~= "debuff"
            and container ~= "playerDefensives" and container ~= "targetDots"
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
local function BuildAuraStyleNav(ctx, b, scope)
    local h = 56
    local section = T.Panel(b.parent, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
    T.ApplySurface(section, "card")
    section:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    section:SetSize(b.width, h)
    section._msuf2Width = b.width
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, section, "Aura container") end
    b.y = b.y - h - 12
    if ctx and ctx.SetContentHeight then ctx:SetContentHeight(abs(b.y) + 28) end
    local w = section._msuf2Width or b.width or 720
    local values = scope == "appearance" and M.SHARED_AURA_STYLE_CONTAINER_VALUES
        or ((not IsGroupScope(scope))
            and (scope == "player" and UNIT_STYLE_CONTAINER_VALUES_PLAYER or UNIT_STYLE_CONTAINER_VALUES)
            or LANE_VALUES)
    local bar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = w,
        label = scope == "appearance" and "Aura type:" or "Container:",
        labelWidth = 88,
        centerY = -28,
        getValue = function() return CurrentAuraStyleContainer(scope) end,
        setValue = function(container)
            M.SetMenuStateValue(scope == "appearance" and "auraAppearanceContainer" or "auraStyleContainer", container)
            if container == "buff" or container == "debuff" then SetCurrentLane("auraStyleGFLane", container) end
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
    M.AttachAuraFontsAndColors(section, title, scope)
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
local UNIT_AURA_DISPEL_WARNING = "Dispel Border, Overlay, and Symbol need this UnitFrame's Aura sensor. Enable Buffs or Debuffs, or turn on a Dispel feature to enable the sensor automatically. Set both icon caps to 0 if you want no aura icons."
local function UnitAuraSensorEnabled(unit)
    return Model.UnitEnabled(unit) == true
end
local ModeEnabled = _G.MSUF_UF_OutlineModeEnabled
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
-- Unit Style is built from one state record: the scope readers/writers and the
-- style binders below are created once, and each accordion builder re-establishes
-- the same local names from that record so the bodies read exactly as before.
local function CreateUnitStyleState(ctx, b, scope, options)
    local S = {}
    options = type(options) == "table" and options or nil
    local embeddedUnitPreview = options and options.embeddedUnitPreview == true
    local appearanceGlobalsOnly = options and options.appearanceGlobalsOnly == true
    local previewContainer = options and options.previewContainer
    local appearanceKind = previewContainer or CurrentLane("auraStyleGFLane", "debuff")
    local unit = scope == "appearance" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    local styleCatalogLane = appearanceGlobalsOnly and appearanceKind or lane
    local styleControls = {}
    local function RefreshStylePreview()
        if S.refreshMiniPreview then
            AurasPage.RefreshMiniAuraPreviewNow(S.refreshMiniPreview)
        elseif embeddedUnitPreview then
            local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
            if type(refreshOwnedPreview) == "function" then
                refreshOwnedPreview("AURAS3_UNIT_STYLE_DUMMY")
            elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
                _G.MSUF_UFPreview_RequestRefresh("AURAS3_UNIT_STYLE_DUMMY")
            end
        end
    end
    local function FlushStyleApply()
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
    end
    local function ReadScopeBool(key, defaultValue)
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceBool) == "function" then
            return Model.ReadSharedAppearanceBool(appearanceKind, key, defaultValue)
        end
        if type(Model.ReadLaneStyleBool) == "function" then return Model.ReadLaneStyleBool(unit, lane, key, defaultValue) end
        if type(Model.ReadBool) == "function" then return Model.ReadBool(unit, key, defaultValue) end
        return Model.ReadSharedBool(key, defaultValue)
    end
    local function WriteScopeBool(key, value)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceBool) == "function" then
            Model.WriteSharedAppearanceBool(appearanceKind, key, value)
        elseif type(Model.WriteLaneStyleBool) == "function" then
            Model.WriteLaneStyleBool(unit, lane, key, value)
        elseif type(Model.WriteBool) == "function" then
            Model.WriteBool(unit, key, value)
        else
            Model.WriteSharedBool(key, value)
        end
    end
    local function ReadScopeDebuffBorderMode()
        if type(Model.ReadDebuffTypeBorderMode) == "function" then return Model.ReadDebuffTypeBorderMode(unit) end
        return ReadScopeBool("useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end
    local function WriteScopeDebuffBorderMode(value)
        value = NormalizeDebuffTypeBorderMode(value, "OFF")
        if type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(unit, value)
        else
            WriteScopeBool("useDebuffTypeBorders", value ~= "OFF")
        end
    end
    local function ReadScopeNumber(key, defaultValue, minValue, maxValue)
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceNumber) == "function" then
            return Model.ReadSharedAppearanceNumber(appearanceKind, key, defaultValue, minValue, maxValue)
        end
        if type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue) end
        return Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    end
    local function WriteScopeNumber(key, value, minValue, maxValue)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceNumber) == "function" then
            Model.WriteSharedAppearanceNumber(appearanceKind, key, value, minValue, maxValue)
        elseif type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        else
            Model.WriteNumber(unit, key, value, minValue, maxValue)
        end
    end
    local function ReadScopeIconShape()
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceIconShape) == "function" then
            return Model.ReadSharedAppearanceIconShape(appearanceKind)
        end
        local appearanceKind = lane == "debuff" and "debuff" or "buff"
        local value = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        return type(A3.NormalizeAuraIconShape) == "function" and A3.NormalizeAuraIconShape(value) or value
    end
    local function WriteScopeIconShape(value)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceIconShape) == "function" then
            Model.WriteSharedAppearanceIconShape(appearanceKind, value or "RECTANGLE")
            return
        end
        -- Icon Shape belongs exclusively to the global Appearance product.
    end
    local function ReadScopeCooldownAnchor()
        if type(Model.ReadLaneCooldownAnchor) == "function" then return Model.ReadLaneCooldownAnchor(unit, lane) end
        if type(Model.ReadCooldownAnchor) == "function" then return Model.ReadCooldownAnchor(unit) end
        return "CENTER"
    end
    local function WriteScopeCooldownAnchor(value)
        if type(Model.WriteLaneCooldownAnchor) == "function" then
            Model.WriteLaneCooldownAnchor(unit, lane, value)
        elseif type(Model.WriteCooldownAnchor) == "function" then
            Model.WriteCooldownAnchor(unit, value)
        end
    end
    local function ReadScopeSwipeDirection()
        return ReadScopeBool("cooldownSwipeReverse", false) and "REVERSE" or "NORMAL"
    end
    local function WriteScopeSwipeDirection(value)
        WriteScopeBool("cooldownSwipeReverse", value == "REVERSE")
    end
    local function ReadScopeDurationBarDisplay()
        if type(Model.ReadLaneDurationBarDisplay) == "function" then return Model.ReadLaneDurationBarDisplay(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDisplay", "BAR_ONLY") or "BAR_ONLY"
        return value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
    end
    local function WriteScopeDurationBarDisplay(value)
        value = value == "OVERLAY" and "OVERLAY" or "BAR_ONLY"
        if type(Model.WriteLaneDurationBarDisplay) == "function" then
            Model.WriteLaneDurationBarDisplay(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDisplay", value)
        end
    end
    local function ReadScopeDurationBarPosition()
        if type(Model.ReadLaneDurationBarPosition) == "function" then return Model.ReadLaneDurationBarPosition(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarPosition", "BOTTOM") or "BOTTOM"
        return value == "TOP" and "TOP" or "BOTTOM"
    end
    local function WriteScopeDurationBarPosition(value)
        value = value == "TOP" and "TOP" or "BOTTOM"
        if type(Model.WriteLaneDurationBarPosition) == "function" then
            Model.WriteLaneDurationBarPosition(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarPosition", value)
        end
    end
    local function ReadScopeDurationBarDirection()
        if type(Model.ReadLaneDurationBarDirection) == "function" then return Model.ReadLaneDurationBarDirection(unit, lane) end
        local value = Model.ReadValue and Model.ReadValue(unit, "durationBarDirection", "REMAINING") or "REMAINING"
        return value == "ELAPSED" and "ELAPSED" or "REMAINING"
    end
    local function WriteScopeDurationBarDirection(value)
        value = value == "ELAPSED" and "ELAPSED" or "REMAINING"
        if type(Model.WriteLaneDurationBarDirection) == "function" then
            Model.WriteLaneDurationBarDirection(unit, lane, value)
        elseif type(Model.WriteValue) == "function" then
            Model.WriteValue(unit, "durationBarDirection", value)
        end
    end
    local function AddStyleControl(control) M.AppendValues(styleControls, control); return control end
    local function BindStyleSwitch(parent, label, x, y, width, key, defaultValue, reason, afterSet)
        return AddStyleControl(BindSwitch(ctx, parent, label, x, y, width,
            function() return ReadScopeBool(key, defaultValue) end,
            function(v)
                WriteScopeBool(key, v)
                ApplyUnit(ctx, unit, reason)
                -- Switches are discrete writes. Compile/apply the new value
                -- before repainting so Menu and Edit Mode observe one state.
                -- ApplyService itself defers this flush during combat.
                FlushStyleApply()
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BindStyleDropdown(parent, label, x, y, values, width, getValue, setValue, reason, afterSet)
        return AddStyleControl(BindDropdown(ctx, parent, label, x, y, values, width,
            getValue,
            function(v)
                setValue(v)
                ApplyUnit(ctx, unit, reason)
                FlushStyleApply()
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(styleCatalogLane) .. "." .. AuraCatalogToken(reason))))
    end
    local function BindStyleSlider(parent, label, x, y, minVal, maxVal, step, width, key, defaultValue, readMin, readMax, writeMin, writeMax, reason, afterSet)
        readMin, readMax = readMin or minVal, readMax or maxVal
        writeMin, writeMax = writeMin or readMin, writeMax or readMax
        return AddStyleControl(BindSlider(ctx, parent, label, x, y, minVal, maxVal, step, width,
            function() return ReadScopeNumber(key, defaultValue, readMin, readMax) end,
            function(v)
                WriteScopeNumber(key, v, writeMin, writeMax)
                ApplyUnit(ctx, unit, reason)
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    local baseId = "aura_style_" .. tostring(scope or "unit") .. "_" .. lane
    M.Assign(S, {
        ctx = ctx, b = b, scope = scope,
        embeddedUnitPreview = embeddedUnitPreview, appearanceGlobalsOnly = appearanceGlobalsOnly, previewContainer = previewContainer,
        appearanceKind = appearanceKind, unit = unit, lane = lane,
        styleCatalogLane = styleCatalogLane, styleControls = styleControls, baseId = baseId,
        RefreshStylePreview = RefreshStylePreview, FlushStyleApply = FlushStyleApply, ReadScopeBool = ReadScopeBool,
        WriteScopeBool = WriteScopeBool, ReadScopeDebuffBorderMode = ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode = WriteScopeDebuffBorderMode,
        ReadScopeNumber = ReadScopeNumber, WriteScopeNumber = WriteScopeNumber, ReadScopeIconShape = ReadScopeIconShape,
        WriteScopeIconShape = WriteScopeIconShape, ReadScopeCooldownAnchor = ReadScopeCooldownAnchor, WriteScopeCooldownAnchor = WriteScopeCooldownAnchor,
        ReadScopeSwipeDirection = ReadScopeSwipeDirection, WriteScopeSwipeDirection = WriteScopeSwipeDirection, ReadScopeDurationBarDisplay = ReadScopeDurationBarDisplay,
        WriteScopeDurationBarDisplay = WriteScopeDurationBarDisplay, ReadScopeDurationBarPosition = ReadScopeDurationBarPosition, WriteScopeDurationBarPosition = WriteScopeDurationBarPosition,
        ReadScopeDurationBarDirection = ReadScopeDurationBarDirection, WriteScopeDurationBarDirection = WriteScopeDurationBarDirection, AddStyleControl = AddStyleControl,
        BindStyleSwitch = BindStyleSwitch, BindStyleDropdown = BindStyleDropdown, BindStyleSlider = BindStyleSlider,
        BodyWidth = BodyWidth,
    })
    return S
end
local function BuildUnitStyleFrameBasics(S)
    local ctx, b, appearanceGlobalsOnly, unit, lane, baseId, ReadScopeBool, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, BindStyleSwitch, BindStyleDropdown, BindStyleSlider, BodyWidth = S.ctx, S.b, S.appearanceGlobalsOnly, S.unit, S.lane, S.baseId, S.ReadScopeBool, S.ReadScopeDebuffBorderMode, S.WriteScopeDebuffBorderMode, S.BindStyleSwitch, S.BindStyleDropdown, S.BindStyleSlider, S.BodyWidth
    local frameBasics
    local stealableStyleControl
    if not appearanceGlobalsOnly then
        local stealableLane = lane == "buff" and unit ~= "player"
        frameBasics = b:CollapsibleSection(baseId .. "_frame_basics", "Frame Basics", stealableLane and 228 or 194, true)
        local basicsWidth = BodyWidth(frameBasics)
        local basicsGap = 10
        local basicsCol = max(180, floor((basicsWidth - 48 - basicsGap) / 2))
        local basicsRightX = 24 + basicsCol + basicsGap
        BindStyleSlider(frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, basicsCol,
            "iconZoom", 100, 100, 200, 100, 200, "AURAS3_ICON_ZOOM")
        BindStyleSlider(frameBasics, "Lane Padding", basicsRightX, -48, 0, 16, 1, basicsCol,
            "stylePadding", 0, 0, 16, 0, 16, "AURAS3_LANE_PADDING")
        AddAuraTooltipHelp(BindStyleSwitch(frameBasics, "Show Tooltip", 24, -106, basicsCol,
            "showTooltip", true, "AURAS3_TOOLTIP"))
        BindStyleSwitch(frameBasics, "Show Cooldown Text", basicsRightX, -106, basicsCol,
            "showCooldownText", true, "AURAS3_SHOW_COOLDOWN_TEXT")
        BindStyleSwitch(frameBasics, "Show Cooldown Swipe", 24, -140, basicsCol,
            "showCooldownSwipe", true, "AURAS3_SHOW_COOLDOWN_SWIPE")
        if stealableLane then
            local stealableEnabled = BindStyleSwitch(frameBasics, "Mark Stealable Buffs", basicsRightX, -140,
                basicsCol, "showStealable", false, "AURAS3_STEALABLE_MARKER")
            stealableStyleControl = BindStyleDropdown(frameBasics, "Stealable Marker Style", basicsRightX, -174,
                M.AURA_STEALABLE_STYLE_VALUES, basicsCol,
                function()
                    return type(Model.ReadLaneStyleString) == "function"
                        and Model.ReadLaneStyleString(unit, lane, "stealableStyle", "BORDER_ICON") or "BORDER_ICON"
                end,
                function(value)
                    if type(Model.WriteLaneStyleString) == "function" then
                        Model.WriteLaneStyleString(unit, lane, "stealableStyle", value or "BORDER_ICON")
                    end
                end,
                "AURAS3_STEALABLE_MARKER_STYLE")
            AddTooltip(stealableEnabled, "Native stealable marker",
                "Uses Blizzard's 12.1 AuraButton stealable filter. It adds no MSUF aura scan, ticker, or OnUpdate.")
            M.TrackRefresh(ctx, function()
                W.SetControlEnabled(stealableStyleControl, ReadScopeBool("showStealable", false))
            end)
        end
        if lane == "debuff" then
            BindStyleDropdown(frameBasics, "Dispel-type Border", basicsRightX, -140,
                type(Model.DebuffTypeBorderModeValues) == "function" and Model.DebuffTypeBorderModeValues() or DEBUFF_TYPE_BORDER_MODE_VALUES,
                basicsCol, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, "AURAS3_DEBUFF_TYPE_BORDER_MODE")
        end
    end
    S.frameBasics, S.stealableStyleControl = frameBasics, stealableStyleControl
end
local function BuildUnitStyleIconStyle(S)
    local ctx, b, appearanceGlobalsOnly, appearanceKind, baseId, RefreshStylePreview, ReadScopeBool, ReadScopeNumber, AddStyleControl, BodyWidth = S.ctx, S.b, S.appearanceGlobalsOnly, S.appearanceKind, S.baseId, S.RefreshStylePreview, S.ReadScopeBool, S.ReadScopeNumber, S.AddStyleControl, S.BodyWidth
    local iconStyleGates = { border = {}, shadow = {}, Apply = function() end }
    if appearanceGlobalsOnly then
    -- Border and shadow are global for the selected Aura product. There is no
    -- frame-level opt-out; UF/GF Style owns only the remaining local details.
    -- Detail controls gray out while their master toggle is off, matching the
    -- rest of the aura style pages. Collected here so both the page refresher
    -- and the icon-style writes can re-apply the gate without a page rebuild.
    local iconStyle = b:CollapsibleSection(baseId .. "_icon_style", "Icon Border & Shadow", 278, false)
    local isw = BodyWidth(iconStyle)
    local styleCol = max(140, floor((isw - 68) / 2))
    local styleGap = 10
    -- Re-runs the master-toggle gate. Assigned once the controls below exist;
    -- called from every icon-style write so flipping a toggle grays its detail
    -- controls immediately instead of waiting for a page rebuild.
    function iconStyleGates.Apply(editable)
        if type(W.SetControlsEnabled) ~= "function" then return end
        if editable == nil then
            editable = true
        end
        local function On(key)
            return editable and ReadScopeBool(key, false) == true
        end
        W.SetControlsEnabled(iconStyleGates.border, On("styleBorderEnabled"))
        W.SetControlsEnabled(iconStyleGates.shadow, On("styleShadowEnabled"))
    end
    local iconStyleApplyTimer
    local iconStyleApplyPending
    local iconStyleApplyReason
    local iconStyleReleaseScheduled
    local function CancelIconStyleApplyTimer()
        if iconStyleApplyTimer and type(iconStyleApplyTimer.Cancel) == "function" then
            iconStyleApplyTimer:Cancel()
        end
        iconStyleApplyTimer = nil
    end
    local function ApplyIconStyleRuntime(reason)
        iconStyleApplyPending = nil
        iconStyleApplyReason = nil
        iconStyleReleaseScheduled = nil
        CancelIconStyleApplyTimer()
        local ok = RequestAuraRuntime("shared", reason or "AURAS3_ICON_STYLE")
        -- The shared aura batch flushes on a delayed timer, but the workbench
        -- (and its Live container) re-reads the compiled runtime config. Flush
        -- now and repaint afterwards, or the preview keeps the previous style
        -- until some unrelated interaction repaints it. Combat defers the
        -- flush; the preview refresh below is combat-gated as well.
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
        RefreshStylePreview()
        return ok
    end
    local function IconStyleWrite(key, value, reason, previewOnly)
        if type(Model.WriteSharedAppearanceValue) == "function" then
            Model.WriteSharedAppearanceValue(appearanceKind, key, value)
        end
        if previewOnly ~= true then ApplyIconStyleRuntime(reason) end
        if key == "styleBorderEnabled" or key == "styleShadowEnabled" then iconStyleGates.Apply() end
        RefreshStylePreview()
    end
    local function FlushIconStyleApply()
        if not iconStyleApplyPending then return end
        iconStyleApplyPending = nil
        iconStyleReleaseScheduled = nil
        CancelIconStyleApplyTimer()
        local reason = iconStyleApplyReason
        iconStyleApplyReason = nil
        ApplyIconStyleRuntime(reason)
    end
    local function ScheduleIconStyleReleaseApply()
        if not iconStyleApplyPending then return end
        CancelIconStyleApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            -- The native Slider may emit its final OnValueChanged after
            -- OnMouseUp. Flush on the next event tick so that final value joins
            -- this single runtime apply instead of scheduling a second one.
            iconStyleReleaseScheduled = true
            iconStyleApplyTimer = C_Timer.NewTimer(0, function()
                iconStyleApplyTimer = nil
                iconStyleReleaseScheduled = nil
                FlushIconStyleApply()
            end)
        else
            FlushIconStyleApply()
        end
    end
    local function QueueIconStyleApply(slider, reason)
        iconStyleApplyPending = true
        iconStyleApplyReason = reason or iconStyleApplyReason
        -- Pointer drags write SavedVariables and repaint only this menu preview.
        -- MouseUp flushes once on the next event tick. Wheel, +/- and text input
        -- have no drag state, so they share one cancellable trailing apply.
        if slider and slider._msuf2SliderActive then
            iconStyleReleaseScheduled = nil
            CancelIconStyleApplyTimer()
            return
        end
        if iconStyleReleaseScheduled then return end
        CancelIconStyleApplyTimer()
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            iconStyleApplyTimer = C_Timer.NewTimer(M.AURA_ICON_STYLE_APPLY_DELAY, FlushIconStyleApply)
        else
            FlushIconStyleApply()
        end
    end
    local function IconStyleReadColor(colorKey, defaultColor)
        local c = type(Model.ReadSharedAppearanceValue) == "function"
            and Model.ReadSharedAppearanceValue(appearanceKind, colorKey, defaultColor) or defaultColor
        if type(c) ~= "table" then c = defaultColor end
        return c
    end
    local function IconStyleSwitch(label, y, key, reason)
        return AddStyleControl(BindSwitch(ctx, iconStyle, label, 24, y, styleCol,
            function() return ReadScopeBool(key, false) == true end,
            function(v) IconStyleWrite(key, v == true, reason) end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(key))))
    end
    local function IconStyleSlider(label, col, y, minVal, maxVal, key, defaultValue, reason)
        local slider
        slider = AddStyleControl(BindSlider(ctx, iconStyle, label, 24 + col * (styleCol + styleGap), y,
            minVal, maxVal, 1, styleCol,
            function()
                return ReadScopeNumber(key, defaultValue, minVal, maxVal)
            end,
            function(value)
                IconStyleWrite(key, tonumber(value) or defaultValue, reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(key))))
        slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)
        slider:HookScript("OnHide", FlushIconStyleApply)
        return slider
    end
    -- Border/Shadow color swatches now live on the Colors page (Auras section)
    -- and are reachable from this section via the three-dot context-color
    -- shortcut attached below; only the enable toggles, thickness/size and the
    -- alpha sliders remain inline here.
    local function IconStyleAlphaSlider(label, col, y, colorKey, defaultColor, reason)
        local slider
        slider = AddStyleControl(BindSlider(ctx, iconStyle, label, 24 + col * (styleCol + styleGap), y,
            0, 100, 1, styleCol,
            function()
                local c = IconStyleReadColor(colorKey, defaultColor)
                return floor(((tonumber(c[4]) or defaultColor[4]) * 100) + 0.5)
            end,
            function(value)
                local c = IconStyleReadColor(colorKey, defaultColor)
                IconStyleWrite(colorKey, { c[1] or defaultColor[1], c[2] or defaultColor[2], c[3] or defaultColor[3], (tonumber(value) or 100) / 100 }, reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(colorKey) .. "-alpha")))
        slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)
        slider:HookScript("OnHide", FlushIconStyleApply)
        return slider
    end
    local ICON_STYLE_BORDER_DEFAULT = { 0, 0, 0, 1 }
    local ICON_STYLE_SHADOW_DEFAULT = { 0, 0, 0, 0.8 }
    -- The RGB swatches were relocated to the Colors page (Auras section). This
    -- quiet three-dot shortcut opens the same two shared colors in the context
    -- picker; alpha stays on the inline sliders above, so the picker is RGB-only.
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(iconStyle, {
            title = "Icon Border & Shadow Colors",
            note = AURA_SHARED_COLOR_NOTE,
            scopeTag = "Shared",
            historySource = "menu:auras-icon-style-color",
            getTargets = function()
                return {
                    {
                        label = "Icon Border Color",
                        historyLabel = "Aura icon border color",
                        getRGB = function()
                            local c = IconStyleReadColor("styleBorderColor", ICON_STYLE_BORDER_DEFAULT)
                            return c[1] or 0, c[2] or 0, c[3] or 0
                        end,
                        setRGB = function(r, g, blue)
                            local c = IconStyleReadColor("styleBorderColor", ICON_STYLE_BORDER_DEFAULT)
                            IconStyleWrite("styleBorderColor", { r, g, blue, c[4] or ICON_STYLE_BORDER_DEFAULT[4] }, "AURAS3_ICON_STYLE_BORDER_COLOR")
                        end,
                        defaultR = 0, defaultG = 0, defaultB = 0,
                    },
                    {
                        label = "Icon Shadow Color",
                        historyLabel = "Aura icon shadow color",
                        getRGB = function()
                            local c = IconStyleReadColor("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT)
                            return c[1] or 0, c[2] or 0, c[3] or 0
                        end,
                        setRGB = function(r, g, blue)
                            local c = IconStyleReadColor("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT)
                            IconStyleWrite("styleShadowColor", { r, g, blue, c[4] or ICON_STYLE_SHADOW_DEFAULT[4] }, "AURAS3_ICON_STYLE_SHADOW_COLOR")
                        end,
                        defaultR = 0, defaultG = 0, defaultB = 0,
                    },
                }
            end,
        })
    end
    IconStyleSwitch("Icon Border", -34, "styleBorderEnabled", "AURAS3_ICON_STYLE_BORDER")
    local borderStyleDropdown = AddStyleControl(BindDropdown(ctx, iconStyle, "Border Style", 24, -70,
        Model.BorderStyleValues, isw - 48,
        function() return Model.ReadSharedAppearanceBorderStyle(appearanceKind) end,
        function(v)
            Model.WriteSharedAppearanceBorderStyle(appearanceKind, v)
            ApplyIconStyleRuntime("AURAS3_ICON_STYLE_BORDER")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "style.appearance.icon-style.border-style")))
    AddTooltip(borderStyleDropdown, "Icon border style",
        "Solid draws a crisp pixel ring around the icon. Soft Glow adds a halo, and Shadow shades the icon's own edges. The Blizzard entries and any LibSharedMedia border are drawn as edge art. Thickness scales the edge.")
    iconStyleGates.border[1] = borderStyleDropdown
    iconStyleGates.border[2] = IconStyleSlider("Border Thickness", 0, -122, 1, 8, "styleBorderThickness", 1, "AURAS3_ICON_STYLE_BORDER")
    iconStyleGates.border[3] = IconStyleAlphaSlider("Border Alpha (%)", 1, -122, "styleBorderColor", ICON_STYLE_BORDER_DEFAULT, "AURAS3_ICON_STYLE_BORDER_COLOR")
    IconStyleSwitch("Icon Shadow", -178, "styleShadowEnabled", "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[1] = IconStyleSlider("Shadow Size", 0, -210, 1, 16, "styleShadowSize", 4, "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)", 1, -210, "styleShadowColor", ICON_STYLE_SHADOW_DEFAULT, "AURAS3_ICON_STYLE_SHADOW_COLOR")
    end
    S.iconStyleGates = iconStyleGates
end
local function BuildUnitStyleStack(S)
    local ctx, b, scope, unit, lane, baseId, RefreshStylePreview, AddStyleControl, BindStyleSwitch, BindStyleSlider, BodyWidth = S.ctx, S.b, S.scope, S.unit, S.lane, S.baseId, S.RefreshStylePreview, S.AddStyleControl, S.BindStyleSwitch, S.BindStyleSlider, S.BodyWidth
    local stack = b:CollapsibleSection(baseId .. "_stack", "Stack Count", 296, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(stack, {
            title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Aura stack text color",
            historySource = "menu:auras-stack-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                unit = unit,
                kind = "aura",
                colorReferences = { "font.global" },
                colorTitle = "Aura Stack Text Color",
                subtitle = "Aura stack text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local sw = BodyWidth(stack)
    BindStyleSwitch(stack, "Show Stack Count", 24, -56, sw - 48, "showStackCount", true, "AURAS3_SHOW_STACKS")
    AddStyleControl(BindDropdown(ctx, stack, "Anchor", 24, -94, Model.StackAnchorValues(), sw - 48,
        function()
            if type(Model.ReadLaneStackAnchor) == "function" then return Model.ReadLaneStackAnchor(unit, lane) end
            return Model.ReadStackAnchor(unit)
        end,
        function(v)
            if type(Model.WriteLaneStackAnchor) == "function" then
                Model.WriteLaneStackAnchor(unit, lane, v)
            else
                Model.WriteStackAnchor(unit, v)
            end
            ApplyUnit(ctx, unit, "AURAS3_STACK_ANCHOR")
            RefreshStylePreview()
        end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".stack-anchor")))
    BindStyleSlider(stack, "Text Size", 24, -152, 6, 40, 1, sw - 48, "stackTextSize", 14, 6, 40, nil, nil, "AURAS3_STACK_SIZE")
    local stackSmallW = max(120, floor((sw - 72) / 2))
    BindStyleSlider(stack, "X", 24, -212, -40, 40, 1, stackSmallW, "stackTextOffsetX", -1, -2000, 2000, nil, nil, "AURAS3_STACK_X")
    BindStyleSlider(stack, "Y", 32 + stackSmallW, -212, -40, 40, 1, stackSmallW, "stackTextOffsetY", 1, -2000, 2000, nil, nil, "AURAS3_STACK_Y")
    S.stack = stack
end
local function BuildUnitStyleCooldown(S)
    local b, scope, unit, lane, baseId, ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, ReadScopeSwipeDirection, WriteScopeSwipeDirection, BindStyleDropdown, BindStyleSlider, BodyWidth = S.b, S.scope, S.unit, S.lane, S.baseId, S.ReadScopeCooldownAnchor, S.WriteScopeCooldownAnchor, S.ReadScopeSwipeDirection, S.WriteScopeSwipeDirection, S.BindStyleDropdown, S.BindStyleSlider, S.BodyWidth
    -- The final slider begins at -328 and its control sits another 24px lower.
    -- Leave a 16px footer so its buttons cannot bleed into Duration Bar.
    local cooldown = b:CollapsibleSection(baseId .. "_cooldown", "Cooldown Text", 392, true)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(cooldown, {
            title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
            historyLabel = "Aura cooldown text color",
            historySource = "menu:auras-cooldown-text-color",
            scopeTag = "Shared",
            note = AURA_SHARED_COLOR_NOTE,
            textSettings = {
                scope = "shared",
                unit = unit,
                kind = "aura",
                colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
                subtitle = "Aura cooldown text follows the shared Fonts settings.",
                capabilities = {
                    opacity = false, baseline = false,
                    shadowAlpha = false, shadowDistance = false,
                },
            },
        })
    end
    local cw = BodyWidth(cooldown)
    BindStyleSlider(cooldown, "Text Size", 24, -48, 6, 40, 1, cw - 48, "cooldownTextSize", 14, 6, 40, nil, nil, "AURAS3_COOLDOWN_SIZE")
    BindStyleDropdown(cooldown, "Anchor", 24, -104, type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues(), cw - 48, ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, "AURAS3_COOLDOWN_ANCHOR")
    BindStyleSlider(cooldown, "X", 24, -162, -40, 40, 1, cw - 48, "cooldownTextOffsetX", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_X")
    BindStyleSlider(cooldown, "Y", 24, -222, -40, 40, 1, cw - 48, "cooldownTextOffsetY", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_Y")
    local swipeDirection = BindStyleDropdown(cooldown, "Swipe Direction", 24, -270, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48, ReadScopeSwipeDirection, WriteScopeSwipeDirection, "AURAS3_COOLDOWN_SWIPE_DIRECTION")
    AddTooltip(swipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local decimal = BindStyleSlider(cooldown, "Decimals below sec", 24, -328, 0, 30, 1, cw - 48, "cooldownDecimalSeconds", 3, 0, 30, nil, nil, "AURAS3_COOLDOWN_FORMAT")
    AddTooltip(decimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")
    S.cooldown = cooldown
end
local function BuildUnitStyleDurationBar(S)
    local b, lane, baseId, ReadScopeBool, ReadScopeNumber, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, ReadScopeDurationBarPosition, WriteScopeDurationBarPosition, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, BindStyleSwitch, BindStyleDropdown, BindStyleSlider, BodyWidth = S.b, S.lane, S.baseId, S.ReadScopeBool, S.ReadScopeNumber, S.ReadScopeDurationBarDisplay, S.WriteScopeDurationBarDisplay, S.ReadScopeDurationBarPosition, S.WriteScopeDurationBarPosition, S.ReadScopeDurationBarDirection, S.WriteScopeDurationBarDirection, S.BindStyleSwitch, S.BindStyleDropdown, S.BindStyleSlider, S.BodyWidth
    local refreshDurationBarSummary
    local durationInline = (b.width or 720) >= 520
    -- Dropdown buttons sit 24 px below their labels and carry a soft edge/glow.
    -- Keep a real footer inside the body so that art cannot bleed into the next
    -- accordion header in either the inline or narrow stacked layout.
    local durationBar = b:CollapsibleSection(baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    W.AttachContextColorReferences(durationBar, AURA_DURATION_BAR_COLOR_REFERENCES, {
        title = M.Format("%s Duration Bar Color", Tr(LaneTitle(lane))),
        scopeTag = "Shared",
        note = AURA_SHARED_COLOR_NOTE,
    })
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local enabled = ReadScopeBool("showDurationBar", false)
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (tostring(Round(ReadScopeNumber("durationBarHeight", 2, 1, 16))) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, ReadScopeDurationBarDisplay(), "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, ReadScopeDurationBarPosition(), "Bottom")) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    BindStyleSwitch(durationBar, "Show Duration Bar", 24, -48, dbw - 48, "showDurationBar", false, "AURAS3_DURATION_BAR", refreshDurationBarSummary)
    BindStyleSlider(durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, "durationBarHeight", 2, 1, 16, nil, nil, "AURAS3_DURATION_BAR_HEIGHT", refreshDurationBarSummary)
    AddTooltip(BindStyleDropdown(durationBar, "Display", 24, -162,
        type(Model.DurationBarDisplayValues) == "function" and Model.DurationBarDisplayValues() or DURATION_BAR_DISPLAY_VALUES,
        durationChoiceWidth, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, "AURAS3_DURATION_BAR_DISPLAY", refreshDurationBarSummary),
        "Duration bar display", "Bar Only hides the aura icon. Icon + Bar keeps the icon and draws the duration bar on it.")
    AddTooltip(BindStyleDropdown(durationBar, "Position", durationInline and (34 + durationChoiceWidth) or 24, durationInline and -162 or -220,
        type(Model.DurationBarPositionValues) == "function" and Model.DurationBarPositionValues() or DURATION_BAR_POSITION_VALUES,
        durationChoiceWidth, ReadScopeDurationBarPosition, WriteScopeDurationBarPosition, "AURAS3_DURATION_BAR_POSITION", refreshDurationBarSummary),
        "Duration bar position", "Places the duration bar at the top or bottom edge of the aura slot.")
    AddTooltip(BindStyleDropdown(durationBar, "Fill Mode", durationInline and (44 + (durationChoiceWidth * 2)) or 24, durationInline and -162 or -278,
        type(Model.DurationBarDirectionValues) == "function" and Model.DurationBarDirectionValues() or DURATION_BAR_DIRECTION_VALUES,
        durationChoiceWidth, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, "AURAS3_DURATION_BAR_DIRECTION", refreshDurationBarSummary),
        "Duration bar fill mode", "Remaining shrinks as the aura expires. Elapsed grows until the aura expires.")
    S.durationBar, S.refreshDurationBarSummary = durationBar, refreshDurationBarSummary
end
local function BuildUnitStyleFrameEffect(S)
    local ctx, b, unit, lane, baseId, RefreshStylePreview, AddStyleControl, BodyWidth = S.ctx, S.b, S.unit, S.lane, S.baseId, S.RefreshStylePreview, S.AddStyleControl, S.BodyWidth
    local effectPrefix = lane == "buff" and "buff" or "debuff"
    local function EffectKey(suffix) return effectPrefix .. "FrameEffect" .. suffix end
    local function ReadEffectValue(suffix, fallback)
        return Model.ReadValue(unit, EffectKey(suffix), fallback)
    end
    local function WriteEffectValue(suffix, value, reason)
        Model.WriteValue(unit, EffectKey(suffix), value)
        ApplyUnit(ctx, unit, reason)
        RefreshStylePreview()
    end
    local frameEffect = b:CollapsibleSection(baseId .. "_full_frame", "Full-Frame Effect", 210, false)
    local few = BodyWidth(frameEffect)
    local effectCol = max(140, floor((few - 68) / 3))
    local effectGap = 10
    AddStyleControl(BindDropdown(ctx, frameEffect, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, few - 48,
        function() return tostring(ReadEffectValue("Type", "none")) end,
        function(value) WriteEffectValue("Type", value or "none", "AURAS3_LANE_FRAME_EFFECT") end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.type", nil,
            LaneFrameEffectAssistantContract(unit, lane, "type"))))
    local effectColor = W.Color(frameEffect, "Color")
    M.BindColor(ctx, effectColor,
        function()
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88
        end,
        function(r, g, blue)
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            WriteEffectValue("Color", { r, g, blue, c[4] or 0.80 }, "AURAS3_LANE_FRAME_EFFECT_COLOR")
        end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.color", nil,
            LaneFrameEffectAssistantContract(unit, lane, "color")))
    -- BindColor remains the single command/history owner and automatically
    -- feeds the card's three-dot picker.  The duplicate inline swatch is hidden
    -- so Full-Frame colors have one visible entry point only.
    effectColor:Hide()
    if effectColor._msuf2Title then
        effectColor._msuf2Title:Hide()
        effectColor._msuf2Title._msuf2AlwaysHidden = true
    end
    AddStyleControl(effectColor)
    local function EffectSlider(label, col, y, minValue, maxValue, step, suffix, fallback, reason)
        return AddStyleControl(BindSlider(ctx, frameEffect, label, 24 + col * (effectCol + effectGap), y,
            minValue, maxValue, step, effectCol,
            function()
                local value = ReadEffectValue(suffix, fallback)
                if suffix == "Alpha" then
                    local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
                    return floor(((tonumber(c[4]) or fallback) * 100) + 0.5)
                end
                return tonumber(value) or fallback
            end,
            function(value)
                if suffix == "Alpha" then
                    local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
                    WriteEffectValue("Color", { c[1] or 0.69, c[2] or 0.50, c[3] or 0.88, (tonumber(value) or 80) / 100 }, reason)
                else
                    WriteEffectValue(suffix, tonumber(value) or fallback, reason)
                end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame." .. AuraCatalogToken(suffix), nil,
                LaneFrameEffectAssistantContract(unit, lane, suffix))))
    end
    EffectSlider("Opacity", 0, -96, 5, 100, 5, "Alpha", 0.80, "AURAS3_LANE_FRAME_EFFECT_ALPHA")
    EffectSlider("Layer (0-30)", 1, -96, 0, 30, 1, "Layer", 0, "AURAS3_LANE_FRAME_EFFECT_LAYER")
    EffectSlider("Thickness", 2, -96, 1, 16, 1, "Thickness", 2, "AURAS3_LANE_FRAME_EFFECT_THICKNESS")
    EffectSlider("Priority", 0, -150, 1, 10, 1, "Priority", 5, "AURAS3_LANE_FRAME_EFFECT_PRIORITY")
    S.frameEffect, S.ReadEffectValue = frameEffect, ReadEffectValue
end
local function TrackUnitStyleBadges(S)
    local ctx, unit, lane, styleControls, ReadScopeBool, ReadScopeDebuffBorderMode, ReadScopeNumber, ReadScopeCooldownAnchor, ReadScopeSwipeDirection, frameBasics, stealableStyleControl, iconStyleGates, stack, cooldown, refreshDurationBarSummary, frameEffect, ReadEffectValue = S.ctx, S.unit, S.lane, S.styleControls, S.ReadScopeBool, S.ReadScopeDebuffBorderMode, S.ReadScopeNumber, S.ReadScopeCooldownAnchor, S.ReadScopeSwipeDirection, S.frameBasics, S.stealableStyleControl, S.iconStyleGates, S.stack, S.cooldown, S.refreshDurationBarSummary, S.frameEffect, S.ReadEffectValue
    M.TrackRefresh(ctx, function()
        -- Individual Style editors are always actionable. The first write to a
        -- formerly inherited lane activates its sparse per-frame override.
        local editable = true
        W.SetControlsEnabled(styleControls, true)
        if stealableStyleControl then
            W.SetControlEnabled(stealableStyleControl, editable and ReadScopeBool("showStealable", false))
        end
        -- Must come after the blanket pass above, which would otherwise
        -- re-enable detail controls whose master toggle is off.
        iconStyleGates.Apply(editable)
        if W.SetCollapsibleBadges then
            local ToggleBadge = W.ToggleBadge
            local frameBasicsBadges = {
                {
                    text = M.Format("Zoom %d%%", Round(ReadScopeNumber("iconZoom", 100, 100, 200))),
                    kind = "info", showWhenClosed = true,
                },
                ToggleBadge("Text", ReadScopeBool("showCooldownText", true)),
                ToggleBadge("Swipe", ReadScopeBool("showCooldownSwipe", true)),
                ToggleBadge("Tooltip", ReadScopeBool("showTooltip", true)),
            }
            if lane == "debuff" then
                local borderMode = ReadScopeDebuffBorderMode()
                frameBasicsBadges[#frameBasicsBadges + 1] = {
                    text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                    kind = borderMode == "OFF" and "muted" or "accent",
                    showWhenClosed = true,
                }
            elseif lane == "buff" then
                frameBasicsBadges[#frameBasicsBadges + 1] = ToggleBadge("Stealable", ReadScopeBool("showStealable", false))
            end
            if frameBasics then W.SetCollapsibleBadges(frameBasics, frameBasicsBadges) end

            local stackEnabled = ReadScopeBool("showStackCount", true)
            W.SetCollapsibleBadges(stack, {{
                text = stackEnabled and (tostring(Round(ReadScopeNumber("stackTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(unit, lane) or Model.ReadStackAnchor(unit))) or "Off",
                kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
            }})

            local cooldownEnabled = ReadScopeBool("showCooldownText", true)
            local decimal = Round(ReadScopeNumber("cooldownDecimalSeconds", 3, 0, 30))
            W.SetCollapsibleBadges(cooldown, {
                { text = cooldownEnabled and (tostring(Round(ReadScopeNumber("cooldownTextSize", 14, 6, 40))) .. "px / " .. AnchorLabel(ReadScopeCooldownAnchor()) .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, ReadScopeSwipeDirection(), "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
            })

            refreshDurationBarSummary()

            local effectType = tostring(ReadEffectValue("Type", "none"))
            W.SetCollapsibleBadges(frameEffect, {{
                text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
            }})

        end
    end)
end
local function BuildUnitStyle(ctx, b, scope, options)
    local S = CreateUnitStyleState(ctx, b, scope, options)
    local embeddedUnitPreview, appearanceGlobalsOnly, previewContainer, unit, lane, baseId, RefreshStylePreview, ReadScopeIconShape, WriteScopeIconShape, BindStyleDropdown, BodyWidth = S.embeddedUnitPreview, S.appearanceGlobalsOnly, S.previewContainer, S.unit, S.lane, S.baseId, S.RefreshStylePreview, S.ReadScopeIconShape, S.WriteScopeIconShape, S.BindStyleDropdown, S.BodyWidth

    if not embeddedUnitPreview then
        S.refreshMiniPreview = AurasPage.BuildAuraStylePreviewWorkbench(ctx, b, unit, lane, previewContainer)
    end

    BuildUnitStyleFrameBasics(S)

    if appearanceGlobalsOnly then
        local appearanceShape = b:CollapsibleSection(baseId .. "_appearance_shape", "Icon Shape", 112, false)
        local ssw = BodyWidth(appearanceShape)
        local appearanceLabel = previewContainer == "playerDefensives" and "Player Defensives"
            or previewContainer == "targetDots" and "Dots on Target" or LaneTitle(lane)
        local shape = BindStyleDropdown(appearanceShape, M.Format("%s Icon Shape", Tr(appearanceLabel)), 24, -48,
            M.AURA_ICON_SHAPE_VALUES, ssw - 48, ReadScopeIconShape, WriteScopeIconShape, "AURAS3_ICON_SHAPE")
        AddTooltip(shape, "Global icon shape",
            "Applies to every UnitFrame and GroupFrame icon of this Aura type. Spell Icons use the Buff appearance.")
    end

    BuildUnitStyleIconStyle(S)
    local iconStyleGates = S.iconStyleGates

    if appearanceGlobalsOnly then
        -- Re-apply the master-toggle gates whenever any Appearance page is
        -- revisited. This must not live in the Buff-only Native Aura Flow
        -- section: Debuffs, Player Defensives and Dots share these controls.
        M.TrackRefresh(ctx, function() iconStyleGates.Apply(true) end)
    end

    if appearanceGlobalsOnly and (previewContainer == "buff" or previewContainer == "debuff") then
        local blizzardFrames = b:CollapsibleSection(baseId .. "_blizzard_aura_frames", "Blizzard Buff & Debuff Frames", 152, false)
        local bfw = BodyWidth(blizzardFrames)
        local function RefreshBlizzardAuraFrameBadge()
            if not W.SetCollapsibleBadges then return end
            local buffsHidden = type(Model.ReadHideBlizzardBuffFrame) == "function"
                and Model.ReadHideBlizzardBuffFrame() == true
            local debuffsHidden = type(Model.ReadHideBlizzardDebuffFrame) == "function"
                and Model.ReadHideBlizzardDebuffFrame() == true
            W.SetCollapsibleBadges(blizzardFrames, {{
                text = Tr(buffsHidden and "Buffs hidden" or "Buffs visible"),
                kind = buffsHidden and "accent" or "muted",
                showWhenClosed = true,
            }, {
                text = Tr(debuffsHidden and "Debuffs hidden" or "Debuffs visible"),
                kind = debuffsHidden and "accent" or "muted",
                showWhenClosed = true,
            }})
        end
        local hideBlizzardBuffs = BindSwitch(ctx, blizzardFrames, "Hide Blizzard Buff Frame", 24, -44, bfw - 48,
            function()
                return type(Model.ReadHideBlizzardBuffFrame) == "function"
                    and Model.ReadHideBlizzardBuffFrame() == true
            end,
            function(value)
                if type(Model.WriteHideBlizzardBuffFrame) == "function" then
                    Model.WriteHideBlizzardBuffFrame(value == true)
                end
                RefreshBlizzardAuraFrameBadge()
            end,
            AuraControlMeta(ctx, "style.appearance.blizzard-aura-frames.hide-buffs"))
        AddTooltip(hideBlizzardBuffs, "Blizzard Buff & Debuff Frames",
            "Hides Blizzard's player Buff Frame near the minimap.")
        local hideBlizzardDebuffs = BindSwitch(ctx, blizzardFrames, "Hide Blizzard Debuff Frame", 24, -84, bfw - 48,
            function()
                return type(Model.ReadHideBlizzardDebuffFrame) == "function"
                    and Model.ReadHideBlizzardDebuffFrame() == true
            end,
            function(value)
                if type(Model.WriteHideBlizzardDebuffFrame) == "function" then
                    Model.WriteHideBlizzardDebuffFrame(value == true)
                end
                RefreshBlizzardAuraFrameBadge()
            end,
            AuraControlMeta(ctx, "style.appearance.blizzard-aura-frames.hide-debuffs"))
        AddTooltip(hideBlizzardDebuffs, "Blizzard Buff & Debuff Frames",
            "Hides only Blizzard's normal Debuff icons near the minimap. Private Auras and Deadly Debuff warnings remain visible.")
        RefreshBlizzardAuraFrameBadge()
        M.TrackRefresh(ctx, RefreshBlizzardAuraFrameBadge)
    end

    if appearanceGlobalsOnly and previewContainer == "buff" then
        local nativeFlow = b:CollapsibleSection(baseId .. "_native_flow", "Native Aura Flow", 112, false)
        local nfw = BodyWidth(nativeFlow)
        local weaponEnchants = BindSwitch(ctx, nativeFlow, "Show Weapon Enchants on Player", 24, -44, nfw - 48,
            function() return Model.ReadSharedBool("showWeaponEnchants", false) end,
            function(value)
                Model.WriteSharedBool("showWeaponEnchants", value == true)
                RequestAuraRuntime("shared", "AURAS3_WEAPON_ENCHANTS")
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.appearance.native-flow.weapon-enchants"))
        AddTooltip(weaponEnchants, "Native weapon enchant auras",
            "Adds Blizzard's temporary weapon-enchantment buttons to the Player Buff container. This is one shared setting and uses the native aura flow without an MSUF ticker or OnUpdate.")
        M.TrackRefresh(ctx, function()
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(nativeFlow, { {
                    text = Model.ReadSharedBool("showWeaponEnchants", false) and "Weapon Enchants On" or "Weapon Enchants Off",
                    kind = Model.ReadSharedBool("showWeaponEnchants", false) and "accent" or "muted",
                    showWhenClosed = true,
                } })
            end
        end)
    end
    if appearanceGlobalsOnly then return end

    BuildUnitStyleStack(S)
    BuildUnitStyleCooldown(S)
    BuildUnitStyleDurationBar(S)
    BuildUnitStyleFrameEffect(S)
    TrackUnitStyleBadges(S)
end

local function BuildUnitOrdering(ctx, b, unit, lane)
    lane = lane == "debuff" and "debuff" or "buff"
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local function OrderingAssistantContract(suffix)
        return {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This ordering control targets the selected UnitFrame Aura lane.",
            assistantSettingKeys = { "auras3." .. tostring(unit) .. "." .. lane .. "." .. suffix },
        }
    end
    local function ReadSortMethod()
        local value = type(Model.ReadLaneStyleString) == "function"
            and Model.ReadLaneStyleString(unit, lane, "sortMethod", "DEFAULT") or "DEFAULT"
        return NormalizeAuraSortMethodForLane(lane, value)
    end
    local function ReadSortDirection()
        local reverse = false
        if type(Model.ReadLaneStyleBool) == "function" then
            reverse = Model.ReadLaneStyleBool(unit, lane, "sortReverse", false)
        elseif type(Model.ReadBool) == "function" then
            reverse = Model.ReadBool(unit, "sortReverse", false)
        end
        return reverse == true and "REVERSE" or "NORMAL"
    end
    local function ApplyOrdering(reason)
        ApplyUnit(ctx, unit, reason)
        local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.Flush) == "function" then apply.Flush() end
        local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason)
        elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh(reason)
        end
    end
    local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        ReadSortMethod,
        function(value)
            value = NormalizeAuraSortMethodForLane(lane, value)
            if type(Model.WriteLaneStyleString) == "function" then
                Model.WriteLaneStyleString(unit, lane, "sortMethod", value)
            end
            ApplyOrdering("AURAS3_SORT_METHOD")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_METHOD"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method",
            nil, OrderingAssistantContract("sortMethod")))
    AddTooltip(sortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
    local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, width - 48,
        ReadSortDirection,
        function(value)
            if type(Model.WriteLaneStyleBool) == "function" then
                Model.WriteLaneStyleBool(unit, lane, "sortReverse", value == "REVERSE")
            elseif type(Model.WriteBool) == "function" then
                Model.WriteBool(unit, "sortReverse", value == "REVERSE")
            end
            ApplyOrdering("AURAS3_SORT_DIRECTION")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_DIRECTION"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction",
            nil, OrderingAssistantContract("sortReverse")))
    AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
end

local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    Model.EnsureDB()
    b:GlobalStyleHeader("Global Aura Appearance", "Global Appearance theme selected only by Aura type. All layout, filters, timers, text and effects stay scope-aware in the corresponding UnitFrame or GroupFrame.", 84)
    local container = BuildAuraStyleNav(ctx, b, "appearance")
    local themeLane = container == "targetDots" and "debuff" or "buff"
    if container == "debuff" then themeLane = "debuff" end
    SetCurrentLane("auraStyleGFLane", themeLane)
    BuildUnitStyle(ctx, b, "appearance", {
        appearanceGlobalsOnly = true,
        previewContainer = container,
    })
    FinishPage(ctx, b)
end
local function BuildAuraStyleLanePage(ctx, lane)
    SetCurrentLane("auraStyleGFLane", lane)
    M.SetMenuStateValue("auraAppearanceContainer", lane)
    BuildAuraStylePage(ctx)
end
local function UniformChoiceWidths(values, width)
    for i = 1, #values do values[i].width = width end
    return values
end
local UNIT_AURA_CHOICE_WIDTH = 92
local UNIT_AURA_WORKSPACE_TABS = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target", UNIT_AURA_CHOICE_WIDTH)
M._unitAuraWorkspaceTabsPlayer = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensives", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOLS = UniformChoiceWidths(VTP "layout=Layout|behavior=Ordering|filters=Filters|blacklist=Blacklist|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_CUSTOM_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|whitelist=Whitelist|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_TARGET_DOT_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|dots=Dots|style=Style", UNIT_AURA_CHOICE_WIDTH)
M._unitAuraPlayerDefensiveTools = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|defensives=Defensives|style=Style", UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOL_OK = { layout = true, behavior = true, filters = true, blacklist = true, style = true }
local UNIT_AURA_CUSTOM_TOOL_OK = { setup = true, behavior = true, whitelist = true, filters = true, layout = true, style = true }
local UNIT_AURA_TARGET_DOT_TOOL_OK = { setup = true, layout = true, behavior = true, filters = true, dots = true, style = true }
M._unitAuraPlayerDefensiveToolOK = { setup = true, layout = true, behavior = true, filters = true, defensives = true, style = true }

local function CurrentUnitAuraTool(unit, container)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then unitState = {}; M.unitAuraToolSelection[unit] = unitState end
    local custom = tostring(container or ""):match("^custom") ~= nil
    local playerDefensives = unit == "player" and container == "custom4"
    local targetDots = unit ~= "player" and container == "custom4"
    local tool = unitState[container]
    local valid = playerDefensives and M._unitAuraPlayerDefensiveToolOK
        or (targetDots and UNIT_AURA_TARGET_DOT_TOOL_OK or (custom and UNIT_AURA_CUSTOM_TOOL_OK or UNIT_AURA_NORMAL_TOOL_OK))
    if not valid[tool] then tool = custom and "setup" or "layout"; unitState[container] = tool end
    return tool
end

local function SetUnitAuraTool(unit, container, tool)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then unitState = {}; M.unitAuraToolSelection[unit] = unitState end
    unitState[container] = tool
end

local function BuildCompactUnitAuraLayout(ctx, b, unit, kind)
    local title = kind == "debuff" and Tr("Debuff Layout") or Tr("Buff Layout")
    -- Stufe-1 pilot: this section renders through the uniform W.SettingsRows
    -- grid (fixed cell metrics, per-value reset) instead of hand-placed
    -- offsets. Control identities, setters and apply reasons are unchanged.
    local section = b:Section(title, 208)
    M.AttachAuraFontsAndColors(section, title, unit)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local controls = {}
    local enable = BindSwitch(ctx, section, "Visible", 24, -62, 104,
        function() return UnitLaneShown(unit, kind) end,
        function(v) SetUnitLaneShown(ctx, unit, kind, v, "AURAS3_UNIT_PAGE_" .. (kind == "buff" and "BUFFS" or "DEBUFFS")) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout.visible", nil,
            "auras3." .. unit .. "." .. kind .. ".visible"))
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    local function LaneMeta(row, pathSuffix)
        local meta = AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout." .. pathSuffix)
        for key, value in pairs(meta) do
            if row[key] == nil then row[key] = value end
        end
        return row
    end
    local defaultAnchor = kind == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    local anchorRows = W.SettingsRows(ctx, section, {
        x = 24 + 126 + gap, y = -34, width = inner - 126 - gap, columns = 2, colGap = gap,
        rows = {
            LaneMeta({
                kind = "dropdown", label = "Anchor", id = "anchor",
                values = function()
                    return type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues()
                end,
                get = function()
                    return type(Model.ReadLaneAnchor) == "function" and Model.ReadLaneAnchor(unit, kind) or defaultAnchor
                end,
                set = function(v)
                    if type(Model.WriteLaneAnchor) == "function" then
                        Model.WriteLaneAnchor(unit, kind, v)
                        ApplyUnit(ctx, unit, "AURAS3_UNIT_ANCHOR")
                    end
                end,
            }, "anchor"),
            LaneMeta({
                kind = "dropdown", label = "Growth", id = "growth",
                values = function()
                    return type(Model.LaneGrowthValues) == "function" and Model.LaneGrowthValues() or Model.GrowthValues()
                end,
                get = function()
                    return type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind) or Model.ReadLaneGrowth(unit, kind)
                end,
                set = function(v)
                    if type(Model.WriteLaneGrowthPair) == "function" then Model.WriteLaneGrowthPair(unit, kind, v) else Model.WriteLaneGrowth(unit, kind, v) end
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_GROWTH", true)
                end,
            }, "growth"),
        },
    })
    local function NumberRow(label, id, semanticKey, minValue, maxValue, defaultValue, getValue, setValue)
        return LaneMeta({
            kind = "slider", label = label, id = id,
            min = minValue, max = maxValue, step = 1, default = defaultValue,
            get = getValue, set = setValue,
        }, AuraCatalogToken(semanticKey))
    end
    local numberRows = W.SettingsRows(ctx, section, {
        x = 24, y = -92, width = inner, columns = 4, colGap = gap,
        rows = {
            NumberRow("Max", "max", "max-icons", 0, 80, LaneDefaultMax(kind),
                function() return Model.ReadNumber(unit, LaneMaxKey(kind), LaneDefaultMax(kind), 0, 80) end,
                function(v) Model.WriteNumber(unit, LaneMaxKey(kind), v, 0, 80); ApplyUnit(ctx, unit, "AURAS3_UNIT_MAX") end),
            NumberRow("Size", "size", "icon-size", 10, 80, 26,
                function() return Model.ReadNumber(unit, LaneSizeKey(kind), 26, 1, 128) end,
                function(v) Model.WriteNumber(unit, LaneSizeKey(kind), v, 1, 128); ApplyUnit(ctx, unit, "AURAS3_UNIT_SIZE") end),
            NumberRow("Per row", "perRow", "per-row", 1, 40, nil,
                function() return Model.ReadLanePerRow(unit, kind) end,
                function(v) Model.WriteLanePerRow(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_PER_ROW") end),
            NumberRow("Gap", "gap", "spacing", 0, 12, 2,
                function() return Model.ReadLaneSpacing(unit, kind) end,
                function(v) Model.WriteLaneSpacing(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING") end),
            NumberRow("Layer (0-30)", "layer", "layer", 0, 30, kind == "buff" and 5 or 6,
                function() return type(Model.ReadLaneLayer) == "function" and Model.ReadLaneLayer(unit, kind) or (kind == "buff" and 5 or 6) end,
                function(v) if type(Model.WriteLaneLayer) == "function" then Model.WriteLaneLayer(unit, kind, v); ApplyUnit(ctx, unit, "AURAS3_UNIT_LAYER") end end),
        },
    })
    local function CollectRows(result)
        if not result then return end
        for i = 1, #result.list do controls[#controls + 1] = result.list[i] end
        for i = 1, #result.resets do controls[#controls + 1] = result.resets[i] end
    end
    CollectRows(anchorRows)
    CollectRows(numberRows)
    local perRowControl = numberRows and numberRows.controls and numberRows.controls.perRow
    M.TrackRefresh(ctx, function()
        local shown = UnitLaneShown(unit, kind)
        W.SetControlEnabled(enable, true)
        W.SetControlsEnabled(controls, shown)
        local growth = type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind)
            or Model.ReadLaneGrowth(unit, kind)
        growth = tostring(growth or ""):upper()
        if perRowControl then
            W.SetControlEnabled(perRowControl, shown and growth ~= "UP" and growth ~= "DOWN")
        end
    end)
end

local function CreateHidePermanentWriter(ctx, unit, lane)
    return function(value)
        if type(Model.WriteBlacklistHidePermanent) == "function"
        and Model.WriteBlacklistHidePermanent(unit, lane, value) then
            ApplyUnit(ctx, unit, "AURAS3_HIDE_PERMANENT", true)
        end
    end
end

local function BuildCompactUnitAuraFilters(ctx, b, unit, lane)
    local section = b:Section((lane == "debuff" and "Debuff" or "Buff") .. " Filters",
        M.CLASSIC_AURA_FILTERS_REDUCED == true and 118 or 256)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    local filterControls = {}
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        local onlyMine = BindSwitch(ctx, section, "Only mine", 24, -42, colW,
            function()
                return Model.LaneFiltersEnabled(unit, lane)
                    and Model.ReadFilter(unit, lane, "onlyMine", false) == true
            end,
            function(value)
                if value == true and Model.LaneFiltersEnabled(unit, lane) ~= true then
                    Model.SetLaneFiltersEnabled(unit, lane, true)
                end
                Model.WriteFilter(unit, lane, "onlyMine", value == true)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_onlyMine", true)
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.only-mine", nil,
                "auras3." .. unit .. "." .. lane .. ".filter.onlyMine"))
        AddTooltip(onlyMine, "Only mine", lane == "debuff"
            and "Only Debuffs applied by the player."
            or "Only auras applied by the player.")
        local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -42, colW,
            function()
                return type(Model.ReadBlacklistHidePermanent) == "function"
                    and Model.ReadBlacklistHidePermanent(unit, lane) == true
            end,
            CreateHidePermanentWriter(ctx, unit, lane),
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil,
                "auras3." .. unit .. "." .. lane .. ".blacklist.hidePermanent"))
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration.")
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(onlyMine, true)
            W.SetControlEnabled(hidePermanent, true)
        end)
        return
    end
    local enabled = BindSwitch(ctx, section, "Enable filters", 24, -42, colW,
        function() return Model.LaneFiltersEnabled(unit, lane) end,
        function(value) Model.SetLaneFiltersEnabled(unit, lane, value); ApplyUnit(ctx, unit, "AURAS3_FILTER_ENABLE", true) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.enabled", nil,
            "auras3." .. unit .. "." .. lane .. ".filtersEnabled"))
    AddTooltip(enabled, "Enable filters", "Turns aura classification filters on or off for this exact lane. Big Defensive uses MSUF's curated list on friendly frames.")
    local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -42, colW,
        function()
            return type(Model.ReadBlacklistHidePermanent) == "function"
                and Model.ReadBlacklistHidePermanent(unit, lane) == true
        end,
        CreateHidePermanentWriter(ctx, unit, lane),
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil,
            "auras3." .. unit .. "." .. lane .. ".blacklist.hidePermanent"))
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration, even when Blizzard token filters are disabled.")
    local maxDuration
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -174, 0, 180, 1, inner,
            function()
                return type(Model.ReadBlacklistMaxDuration) == "function"
                    and Model.ReadBlacklistMaxDuration(unit, lane) or 0
            end,
            function(value)
                if type(Model.WriteBlacklistMaxDuration) == "function"
                    and Model.WriteBlacklistMaxDuration(unit, lane, value) then
                    ApplyUnit(ctx, unit, "AURAS3_" .. tostring(lane):upper() .. "_MAX_DURATION", true)
                end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
    end
    local specs = lane == "buff" and {
        { "Only mine", "onlyMine", "Only auras applied by the player." },
        { "Important", "onlyImportant", "Only auras Blizzard flags as important." },
        { "Applicable by me", "raid", "Helpful auras your character can apply (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Buff filter." },
        { "Also include nameplate-only", "includeNameplateOnly", "Broadens the selected filter to also admit Buffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable / stealable by group", "includeDispellable", "Helpful enemy auras someone in your group can dispel, purge, or steal." },
        { "Any dispel / steal type", "dispellableAny", "Helpful enemy auras with any dispel type, even when your group cannot remove them." },
        { "External defensive", "externalDefensive", "External defensive Buffs." },
        { "Big defensive", "bigDefensive", "MSUF's curated major-defensive Spell-ID list on friendly frames; Blizzard's safe native classification is used where exact identity filtering is restricted." },
        { "Cancelable", "cancelable", "Only cancelable Buffs.", { "notCancelable" } },
        { "Not cancelable", "notCancelable", "Only non-cancelable Buffs.", { "cancelable" } },
    } or {
        { "Only mine", "onlyMine", "Only Debuffs applied by the player.", { "nonPlayer" } },
        { "Important", "onlyImportant", "Only Debuffs Blizzard flags as important." },
        { "Dispellable by me", "raid", "Harmful auras your character can dispel (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Debuff filter." },
        { "Also include nameplate-only", "includeNameplateOnly", "Broadens the selected filter to also admit Debuffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable by group", "includeDispellable", "Debuffs someone in your group can dispel." },
        { "Any dispel type", "dispellableAny", "Debuffs with a dispel type, even when your group cannot remove them." },
        { "Crowd control", "crowdControl", "Crowd-control Debuffs." },
        { "Non-player auras", "nonPlayer", "Only Debuffs not caused by any player or player pet.", { "onlyMine" } },
    }
    for i = 1, #specs do
        local spec = specs[i]
        local col = ((i - 1) % 4)
        local row = floor((i - 1) / 4)
        local settingContract = "auras3." .. unit .. "." .. lane .. ".filter." .. spec[2]
        if lane == "debuff" and spec[2] == "raid" then
            settingContract = {
                assistantDisposition = "dynamic",
                assistantDispositionReason = "The visible Raid switch folds the legacy exclusive Raid value into the canonical Debuff Raid filter.",
                assistantSettingKeys = {
                    "auras3." .. unit .. ".debuff.filter.raid",
                    "auras3." .. unit .. ".debuff.filter.exclusive",
                },
            }
        end
        local control = BindSwitch(ctx, section, spec[1], 24 + col * (colW + gap), -78 - row * 32, colW,
            function()
                if spec[2] == "raid" and Model.ReadFilter(unit, lane, "exclusive", "none") == "raid" then
                    return true
                end
                return Model.ReadFilter(unit, lane, spec[2], false) == true
            end,
            function(value)
                local key = spec[2]
                local modifier = key == "onlyMine" or key == "includeNameplateOnly"
                if value == true and not modifier then
                    -- Blizzard joins native filter tokens as an intersection.
                    -- Present classification choices as one active selector so
                    -- the switch UI cannot accidentally build empty AND chains;
                    -- caster and nameplate inclusion remain explicit modifiers.
                    for j = 1, #specs do
                        local otherKey = specs[j][2]
                        if otherKey ~= key and otherKey ~= "onlyMine" and otherKey ~= "includeNameplateOnly" then
                            Model.WriteFilter(unit, lane, otherKey, false)
                        end
                    end
                end
                if value == true and type(spec[4]) == "table" then for j = 1, #spec[4] do Model.WriteFilter(unit, lane, spec[4][j], false) end end
                -- Older profiles stored the same RAID token in a second
                -- Exclusive dropdown. Fold it into the visible Raid switch so
                -- the legacy restriction can also be turned off here.
                if spec[2] == "raid" then Model.WriteFilter(unit, lane, "exclusive", "none") end
                Model.WriteFilter(unit, lane, spec[2], value)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_" .. spec[2], true)
                if not modifier or spec[4] then QueueAurasPageRefresh(ctx, "auras-filter-conflict") end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters." .. AuraCatalogToken(spec[2]), nil,
                settingContract))
        AddTooltip(control, spec[1], spec[3])
        filterControls[#filterControls + 1] = control
    end
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(enabled, true)
        W.SetControlEnabled(hidePermanent, true)
        W.SetControlEnabled(maxDuration, true)
        W.SetControlsEnabled(filterControls, Model.LaneFiltersEnabled(unit, lane))
    end)
end

-- The unit blacklist editor shares one record B between its manual-entry block,
-- the live-scan block and the preset/list block; the late-bound refreshers
-- (refreshList, renderVerify, refreshLiveBlock, nonPresetHint) live on B.
local function EnsureAuraCombatScanner()
    -- The scanner overlay is a shared singleton parked on M.
    local s = M._auraCombatScanner
    if not s then
        s = CreateFrame("Frame", nil, _G.UIParent)
        M._auraCombatScanner = s
        s:SetSize(372, 100)
        s:SetPoint("TOP", _G.UIParent, "TOP", 0, -160)
        s:SetFrameStrata("DIALOG")
        s:SetMovable(true)
        s:EnableMouse(true)
        s:RegisterForDrag("LeftButton")
        s:SetScript("OnDragStart", function(self) self:StartMoving() end)
        s:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        s:SetClampedToScreen(true)
        if T.ApplyBackdrop then T.ApplyBackdrop(s, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        s.title = T.Font(s, "GameFontHighlightSmall", "", T.colors.accent)
        s.title:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -10)
        s.count = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
        s.count:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -28)
        s.hint = T.Font(s, "GameFontDisableSmall", "", T.colors.muted)
        s.hint:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -42)
        s.hint:SetPoint("TOPRIGHT", s, "TOPRIGHT", -12, -42)
        s.hint:SetJustifyH("LEFT")
        s.hint:Hide()
        s.icons = {}
        for i = 1, 12 do
            local tex = s:CreateTexture(nil, "ARTWORK")
            tex:SetSize(20, 20)
            tex:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 12 + (i - 1) * 24, 10)
            tex:Hide()
            s.icons[i] = tex
        end
        s.stopBtn = ActionButton(s, "Stop scan", 96)
        s.stopBtn:SetPoint("TOPRIGHT", s, "TOPRIGHT", -10, -10)
        s.stopBtn._msuf2AllowCombatClick = true
        s.stopBtn._msuf2SkipHistoryCheckpoint = true
        s.Finish = function(reopen)
            if not s:IsShown() then return end
            s:Hide()
            M.auraBlacklistVerify = {
                unit = s._scope, lane = s._lane, status = "scan",
                liveCount = s._lastLive or 0, sessionCount = s._count or 0,
                secretCount = s._unreadable or 0,
            }
            if reopen and not (M.BlockCombatAction and M.BlockCombatAction()) then
                M.Open(s._returnPage)
            end
        end
        s.stopBtn:SetScript("OnClick", function()
            s.Finish(not (M.BlockCombatAction and M.BlockCombatAction()))
            return true
        end)
        s:RegisterEvent("PLAYER_REGEN_ENABLED")
        s:SetScript("OnEvent", function(self)
            if self:IsShown() then self.Finish(true) end
        end)
        s:SetScript("OnUpdate", function(self, elapsed)
            self._accum = (self._accum or 0) + (tonumber(elapsed) or 0)
            if self._accum < 0.4 then return end
            self._accum = 0
            local live, unreadable, blocked
            if type(Model.LiveBlacklistAuraValues) == "function" then
                live, unreadable, blocked = Model.LiveBlacklistAuraValues(self._scope, self._lane)
            end
            if blocked then
                -- Access denial is temporary (encounter/M+/PvP); keep
                -- ticking cheaply so the scan resumes on its own.
                self._dots = ((self._dots or 0) % 3) + 1
                self.title:SetText(Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
                self.hint:SetText(Tr("Blocked by Blizzard during this fight - resumes automatically. In instances, use the curated presets."))
                self.hint:Show()
                return
            end
            live = live or {}
            self._lastLive = #live
            self._unreadable = tonumber(unreadable) or 0
            local store = M.auraBlacklistCaptured
            if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
            local capKey = tostring(self._scope) .. "|" .. tostring(self._lane)
            local captured = store[capKey]
            if type(captured) ~= "table" then captured = {} store[capKey] = captured end
            for i = 1, #live do
                local entry = live[i]
                local cap = captured[entry.value]
                if type(cap) ~= "table" then
                    cap = { name = type(cap) == "string" and cap or nil }
                    captured[entry.value] = cap
                    self._count = (self._count or 0) + 1
                    self._recent[#self._recent + 1] = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                end
                if type(entry.name) == "string" then cap.name = entry.name end
                if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
            end
            local total = #self._recent
            for i = 1, #self.icons do
                local tex = self.icons[i]
                local icon = self._recent[total - i + 1]
                if icon then tex:SetTexture(icon) tex:Show() else tex:Hide() end
            end
            self._dots = ((self._dots or 0) % 3) + 1
            self.title:SetText(Tr("Scanning auras - creating a list") .. string.rep(".", self._dots))
            if (self._unreadable or 0) > 0 then
                self.count:SetText(M.Format("%d captured so far - %d hidden by Blizzard",
                    self._count or 0, self._unreadable))
                self.hint:SetText(Tr("Hidden auras are Blizzard-secret - no addon can block them. Everything blockable was captured."))
                self.hint:Show()
            else
                self.count:SetText(M.Format("%d captured so far", self._count or 0))
                self.hint:Hide()
            end
        end)
    end
    return s
end
local function BuildUnitBlacklistLiveScan(B)
    local ctx, b, unit, lane, section, inner, showPresets, input = B.ctx, B.b, B.unit, B.lane, B.section, B.inner, B.showPresets, B.input
    local liveY = showPresets and -122 or -134
    local liveW = max(140, min(floor(inner * 0.62), inner - 266))
    local captureKey = unit .. "|" .. lane
    local function CapturedAuras(wipeStore)
        local store = M.auraBlacklistCaptured
        if type(store) ~= "table" then store = {} M.auraBlacklistCaptured = store end
        if wipeStore then store[captureKey] = nil end
        local captured = store[captureKey]
        if type(captured) ~= "table" then captured = {} store[captureKey] = captured end
        return captured
    end
    -- Scanning is strictly click-driven: only the Rescan/Block handlers
    -- call LiveAuraValues. Refreshes and the dropdown read the cached
    -- last scan, so an open menu never scans the unit on its own.
    local liveScanCache
    local function LiveAuraValues()
        local values, unreadable, blocked
        if type(Model.LiveBlacklistAuraValues) == "function" then
            values, unreadable, blocked = Model.LiveBlacklistAuraValues(unit, lane)
        end
        values = values or {}
        -- Every scan also feeds the session capture list, so short-lived
        -- combat debuffs stay pickable after they expire or combat ends.
        local captured = CapturedAuras(false)
        local liveSeen = {}
        for i = 1, #values do
            local entry = values[i]
            liveSeen[entry.value] = true
            local cap = captured[entry.value]
            if type(cap) ~= "table" then
                cap = { name = type(cap) == "string" and cap or nil }
                captured[entry.value] = cap
            end
            if type(entry.name) == "string" then cap.name = entry.name end
            if entry.icon ~= nil and cap.icon == nil then cap.icon = entry.icon end
        end
        local capturedOnly = {}
        for id, cap in pairs(captured) do
            if not liveSeen[id] then
                local capName = type(cap) == "table" and cap.name or (type(cap) == "string" and cap or nil)
                local label = (capName or "Spell") .. " (#" .. tostring(id) .. ")"
                capturedOnly[#capturedOnly + 1] = {
                    value = id, name = capName, icon = type(cap) == "table" and cap.icon or nil,
                    text = M.Format("%s - captured", label), captured = true,
                }
            end
        end
        table.sort(capturedOnly, function(a, b) return tostring(a.text) < tostring(b.text) end)
        for i = 1, #capturedOnly do values[#values + 1] = capturedOnly[i] end
        if #values == 0 then
            values = { { value = nil, text = Tr("No readable auras right now") } }
        end
        liveScanCache = values
        return values, tonumber(unreadable) or 0, blocked == true
    end
    local function CachedAuraValues()
        if liveScanCache then return liveScanCache end
        -- No scan ran in this menu session yet: show the session capture
        -- store as-is (a plain table read - no unit scan happens here).
        local captured = CapturedAuras(false)
        local values = {}
        for id, cap in pairs(captured) do
            local capName = type(cap) == "table" and cap.name or (type(cap) == "string" and cap or nil)
            local label = (capName or "Spell") .. " (#" .. tostring(id) .. ")"
            values[#values + 1] = {
                value = id, name = capName, icon = type(cap) == "table" and cap.icon or nil,
                text = M.Format("%s - captured", label), captured = true,
            }
        end
        if #values == 0 then
            return { { value = nil, text = Tr("No scan yet - click Rescan") } }
        end
        table.sort(values, function(a, b) return tostring(a.text) < tostring(b.text) end)
        return values
    end
    local function CurrentLiveAura()
        local values = CachedAuraValues()
        local selected = M.auraBlacklistLiveSpell
        for i = 1, #values do if values[i].value ~= nil and values[i].value == selected then return selected end end
        for i = 1, #values do if values[i].value ~= nil then return values[i].value end end
        return nil
    end
    local liveDrop = W.Dropdown(section, "Active auras on this frame", CachedAuraValues, liveW)
    W.MoveWidget(liveDrop, section, 24, liveY, liveW)
    M.BindDropdownWidget(ctx, liveDrop, CurrentLiveAura,
        function(value) M.auraBlacklistLiveSpell = value end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.live-aura-selection", "ephemeral"))
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(liveDrop, input) end
    AddTooltip(liveDrop, "Active auras on this frame",
        "Shows the result of the last scan: every readable aura with the exact ID it carried, plus everything captured earlier this session. Press Rescan to scan the current unit - blocking from this list always uses the aura's own ID. Secret auras cannot be listed.")
    local blockLive = ActionButton(section, "Block selected aura", 150, "primary")
    blockLive:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + liveW, liveY - 24)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(blockLive, input) end
    AddTooltip(blockLive, "Block selected aura",
        "Blocks the selected aura using the exact ID it carries right now.")
    blockLive:SetScript("OnClick", function()
        local spellID = CurrentLiveAura()
        if not spellID then return false end
        local auraName, liveNow
        local liveValues = type(Model.LiveBlacklistAuraValues) == "function"
            and Model.LiveBlacklistAuraValues(unit, lane) or {}
        for i = 1, #liveValues do
            if liveValues[i].value == spellID then liveNow = true auraName = liveValues[i].name break end
        end
        if not auraName then
            local values = LiveAuraValues()
            for i = 1, #values do if values[i].value == spellID then auraName = values[i].name break end end
        end
        local changed = Model.AddBlacklistSpell(unit, spellID, lane)
        M.auraBlacklistLiveSpell = nil
        -- Captured entries may no longer be on the unit; only claim the
        -- live-verified state when the aura is actually visible right now.
        M.auraBlacklistVerify = liveNow
            and { unit = unit, lane = lane, status = "active", enteredID = spellID, name = auraName } or nil
        if changed then
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            if B.refreshList then B.refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-live-added")
        else
            B.renderVerify()
        end
        return changed and true or false
    end)
    B.refreshLiveBlock = function(blocked)
        local liveSel = CurrentLiveAura()
        W.SetControlEnabled(blockLive, liveSel ~= nil and not blocked[tostring(liveSel)])
    end
    local rescan = ActionButton(section, "Rescan", 96)
    rescan:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + liveW + 158, liveY - 24)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(rescan, input) end
    rescan._msuf2SkipHistoryCheckpoint = true
    -- Scanning only reads C_UnitAuras and repaints plain menu widgets, so
    -- this click is safe during combat lockdown; blocking stays gated.
    rescan._msuf2AllowCombatClick = true
    AddTooltip(rescan, "Rescan",
        "Re-reads the auras on the current unit and adds everything it sees to this session's captured list - works in combat too. Shift-click clears the captured list.")
    rescan:SetScript("OnClick", function()
        if type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
            CapturedAuras(true)
        end
        M.auraBlacklistLiveSpell = nil
        local values, secretCount, blocked = LiveAuraValues()
        local liveCount = 0
        for i = 1, #values do
            if values[i].value ~= nil and not values[i].captured then liveCount = liveCount + 1 end
        end
        local sessionCount = 0
        for _ in pairs(CapturedAuras(false)) do sessionCount = sessionCount + 1 end
        M.auraBlacklistVerify = {
            unit = unit, lane = lane, status = "scan", blocked = blocked or nil,
            liveCount = liveCount, sessionCount = sessionCount, secretCount = secretCount,
        }
        if liveDrop.SetValue then liveDrop:SetValue(CurrentLiveAura()) end
        if B.refreshList then B.refreshList() end
        return true
    end)
    local startScan = ActionButton(section, "Start combat scan", 170)
    startScan:SetPoint("TOPLEFT", section, "TOPLEFT", 24, liveY - 54)
    if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(startScan, input) end
    startScan._msuf2SkipHistoryCheckpoint = true
    startScan._msuf2AllowCombatClick = true
    AddTooltip(startScan, "Start combat scan",
        "Closes the menu and keeps scanning this frame's auras until combat ends or you press Stop. Every aura an addon can block is captured with its icon - auras Blizzard keeps secret cannot be blocked by any addon.")
    startScan:SetScript("OnClick", function()
        local s = EnsureAuraCombatScanner()
        s._scope, s._lane = unit, lane
        s._returnPage = M.activeKey
        s._recent = {}
        s._accum = 1
        s._dots = 0
        s._lastLive = 0
        local sessionCount = 0
        for _ in pairs(CapturedAuras(false)) do sessionCount = sessionCount + 1 end
        s._count = sessionCount
        s.title:SetText(Tr("Scanning auras - creating a list"))
        s.count:SetText(M.Format("%d captured so far", sessionCount))
        if s.hint then s.hint:Hide() end
        for i = 1, #s.icons do s.icons[i]:Hide() end
        s:Show()
        M.HideSlashMenuAndMinibar(M.frame)
        return true
    end)
end
local function BuildUnitBlacklistManualEntry(B)
    local ctx, unit, lane, section, inner, isDebuff, enemyDebuff = B.ctx, B.unit, B.lane, B.section, B.inner, B.isDebuff, B.enemyDebuff
    if not isDebuff or enemyDebuff then
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 130))
        local inputLabel = enemyDebuff and "Enemy debuff Spell ID, link, or name"
            or "Enter buff Spell ID, link, or name"
        local addLabel = enemyDebuff and "Add enemy debuff" or "Add custom buff"
        local input = BindTextInput(ctx, section, inputLabel, 24, -36, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.manual-input", "ephemeral"))
        B.input = input
        if enemyDebuff then CreateCustomDebuffBlacklistInfoButton(section, input, unit) end
        AddTooltip(input, "Spell ID vs. aura ID",
            "The aura on the unit can use a different Spell ID than the spell you cast. Enter the ID shown on the aura itself. After adding, MSUF checks the live unit and warns when only a same-named aura with a different ID is active.")
        local add = ActionButton(section, addLabel, enemyDebuff and 132 or 118, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -60)
        local verifyText = W.Text(section, "", 24, -92, inner - 214, T.colors.muted)
        if verifyText.SetMaxLines then verifyText:SetMaxLines(2) end
        local swapBtn = ActionButton(section, "", 180, "primary")
        swapBtn:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -86)
        if M.MarkRuntimeControlComponent then M.MarkRuntimeControlComponent(swapBtn, input) end
        swapBtn:Hide()
        B.renderVerify = function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not mine then
                verifyText:SetText("")
            elseif mine.status == "scan" and mine.blocked then
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(Tr("Blizzard is blocking aura scanning right now (encounter, Mythic+, or PvP match). Use the curated presets - they cover everything blockable in instanced content."))
            elseif mine.status == "scan" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                if (mine.secretCount or 0) > 0 then
                    verifyText:SetText(M.Format("Scan complete: %d auras readable right now, %d captured this session. %d more are hidden by Blizzard and cannot be blocked by any addon.",
                        mine.liveCount or 0, mine.sessionCount or 0, mine.secretCount))
                else
                    verifyText:SetText(M.Format("Scan complete: %d auras readable right now, %d captured this session.",
                        mine.liveCount or 0, mine.sessionCount or 0))
                end
            elseif mine.status == "active" then
                local c = T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(M.Format("%s (#%d) is active on this frame right now - blacklist entry verified.",
                    tostring(mine.name or "Spell"), mine.enteredID or 0))
            else
                local c = T.colors.accent2 or T.colors.accent
                if c and verifyText.SetTextColor then verifyText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1) end
                verifyText:SetText(M.Format("#%d is not active on this frame, but %s is currently active as #%d. The aura's ID can differ from your cast's Spell ID.",
                    mine.enteredID or 0, tostring(mine.suggestName or "Spell"), mine.suggestID or 0))
            end
            local showSwap = mine ~= nil and mine.status == "mismatch" and mine.suggestID ~= nil
            if showSwap and swapBtn._msuf2Label and swapBtn._msuf2Label.SetText then
                swapBtn._msuf2Label:SetText(M.Format("Block #%d instead", mine.suggestID))
            end
            swapBtn:SetShown(showSwap)
            if B.nonPresetHint then B.nonPresetHint:SetShown(mine == nil) end
        end
        swapBtn:SetScript("OnClick", function()
            local state = M.auraBlacklistVerify
            local mine = state and state.unit == unit and state.lane == lane and state or nil
            if not (mine and mine.suggestID) then return false end
            if mine.enteredID and mine.enteredID ~= mine.suggestID then
                Model.RemoveBlacklistSpell(unit, mine.enteredID, lane)
            end
            Model.AddBlacklistSpell(unit, mine.suggestID, lane)
            M.auraBlacklistVerify = {
                unit = unit, lane = lane, status = "active",
                enteredID = mine.suggestID, name = mine.suggestName,
            }
            ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            if B.refreshList then B.refreshList() end
            QueueAurasPageRefresh(ctx, "aura-blacklist-swap-suggested")
            return true
        end)
        BuildUnitBlacklistLiveScan(B)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local spellID = type(Model.ResolveSpellInputID) == "function" and Model.ResolveSpellInputID(value) or nil
            local changed = Model.AddBlacklistSpell(unit, value, lane)
            if changed then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_ADD", true)
            end
            -- The aura left on the unit can carry a different SpellID than the
            -- cast the entry resolved to; compare against the live unit so the
            -- mismatch surfaces immediately instead of failing silently.
            M.auraBlacklistVerify = nil
            local verdict = spellID and type(Model.FindLiveBlacklistAura) == "function"
                and Model.FindLiveBlacklistAura(unit, spellID, lane) or nil
            if verdict then
                M.auraBlacklistVerify = {
                    unit = unit, lane = lane, status = verdict.status,
                    enteredID = spellID, name = verdict.name,
                    suggestID = verdict.suggestID, suggestName = verdict.suggestName,
                }
            end
            if changed then
                if B.refreshList then B.refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-manual-added")
            else
                B.renderVerify()
            end
            if input and input.SetText then input:SetText("") end
            inputValue = ""
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, addLabel,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-manual", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        if enemyDebuff then
            AddTooltip(add, "Add enemy debuff",
                "Adds one exact harmful aura to this Target, Focus, or Boss blacklist. Blizzard applies arbitrary SpellID filters only while the unit is not assistable.")
        else
            AddTooltip(add, "Add custom buff", "Adds one exact buff to this frame's blacklist.")
        end
    end
end
local function BuildUnitBlacklistPresetsAndList(B)
    local ctx, unit, lane, section, inner, isDebuff, enemyDebuff, showPresets, combinedManualAndPresets = B.ctx, B.unit, B.lane, B.section, B.inner, B.isDebuff, B.enemyDebuff, B.showPresets, B.combinedManualAndPresets
    local refreshList
    local curatedOffset = combinedManualAndPresets and -174 or 0
    local presetW = max(130, min(floor(inner * 0.62), inner - 138))
    local spellW = max(160, min(floor(inner * 0.68), inner - 108))
    local function PresetValues()
        return type(Model.UnitBlacklistPresetValues) == "function"
            and Model.UnitBlacklistPresetValues(unit, lane) or Model.BlacklistPresetValues()
    end
    local function CurrentPreset()
        local fallback = type(Model.UnitBlacklistDefaultPreset) == "function"
            and Model.UnitBlacklistDefaultPreset(unit, lane) or "RAID_BUFFS"
        local key = M.auraBlacklistPreset or fallback
        local values = PresetValues()
        for i = 1, #values do if values[i].value == key then return key end end
        for i = 1, #values do if values[i].value then return values[i].value end end
        return fallback
    end
    local function CurrentSpell()
        local values = type(Model.UnitBlacklistSpellValues) == "function"
            and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
            or Model.BlacklistSpellValues(CurrentPreset())
        local selected = M.auraBlacklistSpell
        local entries = Model.BlacklistEntries(unit, lane)
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        for i = 1, #values do
            if values[i].value == selected and not blocked[tostring(selected)] then return selected end
        end
        for i = 1, #values do
            if values[i].value ~= nil and not blocked[tostring(values[i].value)] then return values[i].value end
        end
        return nil
    end
    local selectedSummary, addSet, addSpell
    if showPresets then
        local preset = W.Dropdown(section, "Preset", PresetValues, presetW)
        W.MoveWidget(preset, section, 24, -36 + curatedOffset, presetW)
        M.BindDropdownWidget(ctx, preset, CurrentPreset, function(value) M.auraBlacklistPreset = value; M.auraBlacklistSpell = nil; QueueAurasPageRefresh(ctx, "aura-blacklist-preset") end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.preset-selection", "ephemeral"))
        addSet = ActionButton(section, "Add entire set", 126, "primary")
        addSet:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + presetW, -60 + curatedOffset)
        addSet:SetScript("OnClick", function()
            local count = Model.AddBlacklistPresetGroup(unit, CurrentPreset(), lane)
            if count > 0 then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_GROUP_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-group-added")
            end
            return count > 0
        end)
        RegisterAuraControl(ctx, addSet, "Add entire set", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-set", "action", {
            actionKey = "aura_blacklist_add_preset", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "preset",
        })
        AddTooltip(addSet, "Add entire set", "Blocks every aura in the selected curated MSUF set.")
        selectedSummary = W.Text(section, "", 24, -92 + curatedOffset, inner, T.colors.muted)
        local spell = W.Dropdown(section, "Spell", function()
            return type(Model.UnitBlacklistSpellValues) == "function"
                and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
                or Model.BlacklistSpellValues(CurrentPreset())
        end, spellW)
        W.MoveWidget(spell, section, 24, -120 + curatedOffset, spellW)
        M.BindDropdownWidget(ctx, spell,
            CurrentSpell,
            function(value) M.auraBlacklistSpell = value end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.spell-selection", "ephemeral"))
        addSpell = ActionButton(section, "Add spell", 96)
        addSpell:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + spellW, -144 + curatedOffset)
        addSpell:SetScript("OnClick", function()
            local changed = Model.AddBlacklistPresetSpell(unit, CurrentSpell(), lane)
            if changed then
                M.auraBlacklistSpell = nil
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_PRESET_ADD", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-preset-spell-added")
            end
            return changed and true or false
        end)
        RegisterAuraControl(ctx, addSpell, "Add spell", "button", "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.add-preset-spell", "action", {
            actionKey = "aura_blacklist_add_spell", actionFixedArgs = { scope = unit, lane = lane }, actionInputArg = "value",
        })
        AddTooltip(addSpell, "Add spell", "Blocks only the selected aura from the curated set.")
    else
        B.nonPresetHint = W.Text(section,
            "Enemy debuffs: hide only exact noisy SpellIDs. Selected Dots on target are handled automatically by that scope's Auto-blacklist toggle.",
            24, -104, inner, T.colors.muted)
    end
    local listOffset = showPresets and curatedOffset or (enemyDebuff and -48 or 44)
    local prepared = W.Text(section, "", 24, -186 + listOffset, inner, T.colors.accent)
    local searchValue = ""
    local searchInput = BindTextInput(ctx, section, "Search", 24, -210 + listOffset, inner,
        function() return searchValue end,
        function(value)
            searchValue = tostring(value or "")
            if refreshList then refreshList() end
        end,
        true, AuraControlMeta(ctx,
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.search", "ephemeral"))
    if searchInput and searchInput.HookScript then
        searchInput:HookScript("OnTextChanged", function(self)
            searchValue = self.GetText and tostring(self:GetText() or "") or ""
            if refreshList then refreshList() end
        end)
    end
    local emptyText = enemyDebuff and not showPresets and "No blocked enemy debuffs. Add an exact SpellID above."
        or (enemyDebuff and "No blocked spells. Add one above or use a preset.")
        or (isDebuff and "No blocked spells. Add one from the allowed presets above."
        or "No blocked spells. Add one above or use a preset.")
    local empty = W.Text(section, emptyText, 24, -284 + listOffset, inner, T.colors.muted)
    local listScroll = CreateFrame("ScrollFrame", nil, section)
    listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -260 + listOffset)
    listScroll:SetSize(inner - 20, 150)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(inner - 44, 150)
    listScroll:SetScrollChild(listChild)
    M._StyleNestedAuraScrollFrame(listScroll, section, 44)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, listChild)
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
        row:SetHeight(40)
        if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.icon:SetSize(28, 28)
        row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
        row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
        row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
        row.remove = ActionButton(row, "Remove", 80)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.remove:SetScript("OnClick", function()
            if row._spellID and Model.RemoveBlacklistSpell(unit, row._spellID, lane) then
                ApplyUnit(ctx, unit, "AURAS3_BLACKLIST_REMOVE", true)
                if refreshList then refreshList() end
                QueueAurasPageRefresh(ctx, "aura-blacklist-removed")
            end
        end)
        AddTooltip(row.remove, "Remove from blacklist", "Stops blocking this aura.")
        rows[i] = row
        return row
    end
    refreshList = function()
        local entries = Model.BlacklistEntries(unit, lane)
        local blocked = {}
        for i = 1, #entries do blocked[tostring(entries[i].value)] = true end
        if B.refreshLiveBlock then B.refreshLiveBlock(blocked) end
        if showPresets then
            local setSpells = type(Model.UnitBlacklistSpellValues) == "function"
                and Model.UnitBlacklistSpellValues(unit, lane, CurrentPreset())
                or Model.BlacklistSpellValues(CurrentPreset())
            local missing = 0
            for i = 1, #setSpells do if not blocked[tostring(setSpells[i].value)] then missing = missing + 1 end end
            selectedSummary:SetText(missing == 0
                and M.Format("%d spells in this set - all already blocked", #setSpells)
                or M.Format("%d spells in this set - %d can still be added", #setSpells, missing))
            W.SetControlEnabled(addSet, missing > 0)
            local selectedSpell = CurrentSpell()
            W.SetControlEnabled(addSpell, selectedSpell ~= nil and not blocked[tostring(selectedSpell)])
        end
        local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local visible = {}
        for i = 1, #entries do
            local entry = entries[i]
            local haystack = (tostring(entry.text or "") .. " "
                .. tostring(entry.spellID or entry.value or "")):lower()
            if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
        end
        prepared:SetText(M.Format("Blocked spells (%d)", #entries) .. MatchSuffix(query, #visible))
        empty:SetText(#entries == 0 and Tr(emptyText) or M.Format(Tr("No results for \"%s\"."), query))
        empty:SetShown(#visible == 0)
        listScroll:SetShown(#visible > 0)
        listChild:SetHeight(max(150, #visible * 44))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.value
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local name = tostring(entry.text or entry.value or "Spell"):gsub("%s*%(#%d+%)$", "")
                row.name:SetText(name)
                row.id:SetText(entry.spellID and (tostring("Spell ID ") .. tostring(entry.spellID)) or tostring(entry.value or ""))
                RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                    "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".blacklist.entry." .. AuraCatalogToken(entry.value) .. ".remove", "action")
                row:Show()
            elseif row then row._spellID = nil; row:Hide() end
        end
        if B.renderVerify then B.renderVerify() end
    end
    B.refreshList = refreshList
    M.TrackRefresh(ctx, refreshList)
end
local function BuildCompactUnitAuraBlacklist(ctx, b, unit, lane)
    local laneTitle = lane == "debuff" and "Debuff" or "Buff"
    local isDebuff = lane == "debuff"
    local enemyDebuff = isDebuff and unit ~= "player"
    local showPresets = not isDebuff or type(Model.UnitBlacklistPresetValues) ~= "function"
        or #Model.UnitBlacklistPresetValues(unit, lane) > 0
    local combinedManualAndPresets = (not isDebuff or enemyDebuff) and showPresets
    local section = b:Section(laneTitle .. " Blacklist",
        combinedManualAndPresets and 620 or ((not isDebuff or enemyDebuff) and 538 or 446))
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local B = {
        ctx = ctx, b = b, unit = unit, lane = lane, section = section, inner = inner,
        isDebuff = isDebuff, enemyDebuff = enemyDebuff, showPresets = showPresets,
        combinedManualAndPresets = combinedManualAndPresets,
    }
    BuildUnitBlacklistManualEntry(B)
    BuildUnitBlacklistPresetsAndList(B)
end

local CreateNestedAuraBuilder = W.CreateNestedAuraBuilder

function M.BuildAuras3UnitSection(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end
    ctx._auraAppearancePreviewRefresh = function(reason)
        local refreshOwnedPreview = ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason or "AURAS3_UNIT_STYLE_DUMMY")
        elseif type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
            _G.MSUF_UFPreview_RequestRefresh("AURAS3_UNIT_STYLE_DUMMY")
        end
    end
    M.unitAuraTabSelection = M.unitAuraTabSelection or {}
    local workspaceTabs = unit == "player" and M._unitAuraWorkspaceTabsPlayer or UNIT_AURA_WORKSPACE_TABS
    local function CurrentTab()
        local tab = M.unitAuraTabSelection[unit] or "buff"
        if tab ~= "buff" and tab ~= "debuff" and tab ~= "custom1" and tab ~= "custom2" and tab ~= "custom3" and tab ~= "custom4" then tab = "buff" end
        return tab
    end
    local currentTab = CurrentTab()
    local normalLane = currentTab == "buff" or currentTab == "debuff"
    local currentTool = CurrentUnitAuraTool(unit, currentTab)
    local customContainerPatterns = {}
    for i = 1, #M._customContainerAssistantSuffixes do
        local suffix = M._customContainerAssistantSuffixes[i]
        customContainerPatterns[i] = "^auras3%." .. tostring(unit):gsub("([^%w])", "%%%1") .. "%.custom%d+%."
            .. tostring(suffix):gsub("([^%w])", "%%%1") .. "$"
    end
    local customContainerContract = {
        assistantDisposition = "dynamic",
        assistantDispositionReason = "This selector opens the dynamic editor for any persisted setting on the selected Custom Aura container.",
        assistantSettingKeyPatterns = customContainerPatterns,
    }
    local outer = builder:CollapsibleSection("auras", "Auras", 120, false)
    local auraBuilder = CreateNestedAuraBuilder(ctx, builder, outer)
    local sectionW = auraBuilder.width or 720
    local tools = normalLane and UNIT_AURA_NORMAL_TOOLS
        or (currentTab == "custom4"
            and (unit == "player" and M._unitAuraPlayerDefensiveTools or UNIT_AURA_TARGET_DOT_TOOLS)
            or UNIT_AURA_CUSTOM_TOOLS)
    local containerCenterY = -28
    local containerMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(workspaceTabs, {
        width = sectionW,
        labelWidth = 72,
        centerY = containerCenterY,
    })
    local toolCenterY = min(-62, ((containerMetrics and containerMetrics.bottomY) or -40) - 22)
    local toolMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(tools, {
        width = sectionW,
        labelWidth = 72,
        centerY = toolCenterY,
    })
    local footerY = ((toolMetrics and toolMetrics.bottomY) or (toolCenterY - 12)) - 2
    local top = auraBuilder:Section("", max(104, abs(footerY) + 28))
    if top.title then top.title:Hide() end
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, top, "Aura container and tools", "unit_aura_tools")
    end
    local containerBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = workspaceTabs,
        width = sectionW,
        label = "Container:",
        labelWidth = 72,
        centerY = containerCenterY,
        getValue = CurrentTab,
        setValue = function(value)
            M.unitAuraTabSelection[unit] = value
            Rebuild(ctx)
        end,
    }), workspaceTabs, "unit-workspace.container-selector", customContainerContract)
    if containerBar then
        local exactKind = "unitAuraWorkspace"
        -- prepareValue -> { tab, tool, representative settingKey }. Changelog
        -- highlights and search deep-links use these to open the exact
        -- workspace view instead of flashing an unrelated control.
        local exactViews = {
            buff_layout = { tab = "buff", tool = "layout",
                settingKey = "auras3." .. tostring(unit) .. ".buff.visible" },
            custom1_reminder = { tab = "custom1", tool = "setup",
                settingKey = "auras3." .. tostring(unit) .. ".custom1.placed.reminderEnabled" },
        }
        if unit ~= "player" then
            exactViews.custom4_behavior = { tab = "custom4", tool = "behavior",
                settingKey = "auras3." .. tostring(unit) .. ".custom4.placed.sortMethod" }
            exactViews.debuff_blacklist = { tab = "debuff", tool = "blacklist",
                settingKey = "auras3." .. tostring(unit) .. ".debuff.blacklist.hidePermanent" }
        end
        local exactContracts = {}
        for value, view in pairs(exactViews) do exactContracts[value] = view.settingKey end
        containerBar._msuf2ExactTargetKinds = { [exactKind] = true }
        containerBar._msuf2ExactTargetContracts = {
            [exactKind] = exactContracts,
        }
        containerBar._msuf2PrepareExactSearchTarget = function(_, exactTarget)
            if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= exactKind then
                return false
            end
            local view = exactViews[tostring(exactTarget.prepareValue or "")]
            if not view then return false end
            local alreadySelected = M.unitAuraTabSelection[unit] == view.tab
                and CurrentUnitAuraTool(unit, view.tab) == view.tool
            if not alreadySelected then
                M.unitAuraTabSelection[unit] = view.tab
                SetUnitAuraTool(unit, view.tab, view.tool)
            end
            return true
        end
    end
    local toolBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = tools,
        width = sectionW,
        label = "Edit:",
        labelWidth = 72,
        centerY = toolCenterY,
        getValue = function() return CurrentUnitAuraTool(unit, currentTab) end,
        setValue = function(value) SetUnitAuraTool(unit, currentTab, value); Rebuild(ctx) end,
    }), tools, "unit-workspace.tool-selector")
    local openStyle = ActionButton(top, "Global Aura Appearance", 170, "normal")
    openStyle:SetPoint("TOPRIGHT", top, "TOPRIGHT", -16, footerY)
    openStyle:SetScript("OnClick", function()
        local previewContainer = currentTab == "custom4"
            and (unit == "player" and "playerDefensives" or "targetDots")
            or currentTab
        M.SetMenuStateValue("auraAppearanceContainer", previewContainer)
        if normalLane then SetCurrentLane("auraStyleGFLane", currentTab) end
        SelectPage("auras3_styling")
    end)
    RegisterAuraControl(ctx, openStyle, "Global Aura Appearance", "button", "unit-workspace.open-aura-style", "navigation", "auras3_styling")
    AddTooltip(openStyle, "Global Aura Appearance",
        "Opens the global Aura icon appearance: shape, border, shadow, colors and native Player weapon enchants. This frame's container Style stays here.")
    local workspaceHint = W.Text(top,
        "Aura Options, Ordering and Aura Style belong to this UnitFrame. Global icon appearance: Appearance > Auras.",
        16, footerY - 8, sectionW - 198, T.colors.muted)
    M.TrackRefresh(ctx, function()
        workspaceHint:SetText(normalLane and UnitDispelRequested(unit) and not UnitAuraSensorEnabled(unit)
            and UNIT_AURA_DISPEL_WARNING
            or "Aura Options, Ordering and Aura Style belong to this UnitFrame. Global icon appearance: Appearance > Auras.")
    end)

    if normalLane then
        SetCurrentLane("auraStyleGFLane", currentTab)
        SetCurrentLane("auraFilterLane", currentTab)
        if currentTool == "style" then
            BuildUnitStyle(ctx, auraBuilder, unit, { embeddedUnitPreview = true })
        elseif currentTool == "behavior" then
            BuildUnitOrdering(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "filters" then
            BuildCompactUnitAuraFilters(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "blacklist" then
            BuildCompactUnitAuraBlacklist(ctx, auraBuilder, unit, currentTab)
        else
            BuildCompactUnitAuraLayout(ctx, auraBuilder, unit, currentTab)
        end
    elseif type(M.BuildAuras3CompactCustomWorkspace) == "function" then
        M.BuildAuras3CompactCustomWorkspace(ctx, auraBuilder, unit, tonumber(currentTab:match("(%d)$")) or 1, currentTool)
    end
end


local function BuildMovedAuraPage(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Aura Controls moved to Frames", "Layout, filters, lists and every container-specific Style live in each frame. Appearance > Auras owns only the global icon theme.", 96)
    local section = b:Section("Open a Frame", 190)
    local w = section._msuf2Width or b.width or 720
    local pages = {
        { "Player", "uf_player" }, { "Target", "uf_target" }, { "Focus", "uf_focus" },
        { "Boss", "uf_boss" }, { "Group Frames", "gf_auras" },
    }
    local x = 24
    for i = 1, #pages do
        local page = pages[i]
        local button = ActionButton(section, page[1], i == 5 and 132 or 92)
        button:SetPoint("TOPLEFT", section, "TOPLEFT", x, -60)
        button:SetScript("OnClick", function() if M.SelectPage then M.SelectPage(page[2]) end end)
        RegisterAuraControl(ctx, button, page[1], "button", "moved-page.open." .. AuraCatalogToken(page[2]), "navigation", page[2])
        x = x + (i == 5 and 144 or 104)
    end
    W.Text(section, "Open the frame and expand Auras. Buffs and Debuffs contain their own layout, filters, blacklists and Style; Custom 1-3, Defensive Buffs and Dots on target expose controls appropriate to their content.", 24, -118, w - 48, T.colors.muted)
    FinishPage(ctx, b)
end

-- Old content/filter routes remain as compatibility landings. The Buff/Debuff
-- aliases open the matching global Appearance preview; individual Style stays on the
-- selected UnitFrame or GroupFrame page.
M.RegisterPage("auras3_buffs", { title = "Global Aura Appearance: Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 25 })
M.RegisterPage("auras3_debuffs", { title = "Global Aura Appearance: Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 25 })
M.RegisterPage("auras3_custom", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 2 })
M.RegisterPage("auras3_styling", { title = "Aura Style", build = BuildAuraStylePage, version = 53 })
M.RegisterPage("auras3_filters", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 31 })

M.AurasPage = AurasPage
