-- Auras: Style responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AurasParts
if not Parts then return end
local AnchorLabel = Parts.AnchorLabel
local AuraCatalogToken = Parts.AuraCatalogToken
local A3 = Parts.A3
local AURA_COOLDOWN_COLOR_REFERENCES = Parts.AURA_COOLDOWN_COLOR_REFERENCES
local AURA_SHARED_COLOR_NOTE = Parts.AURA_SHARED_COLOR_NOTE
local AddAuraTooltipHelp = Parts.AddAuraTooltipHelp
local AddTooltip = Parts.AddTooltip
local ApplyService = Parts.ApplyService
local ApplyUnit = Parts.ApplyUnit
local AuraControlMeta = Parts.AuraControlMeta
local AurasPage = Parts.AurasPage
local BindDropdown = Parts.BindDropdown
local BindSlider = Parts.BindSlider
local BindSwitch = Parts.BindSwitch
local COOLDOWN_SWIPE_DIRECTION_VALUES = Parts.COOLDOWN_SWIPE_DIRECTION_VALUES
local CUSTOM_FRAME_EFFECTS = Parts.CUSTOM_FRAME_EFFECTS
local C_Timer = Parts.C_Timer
local ChoiceLabel = Parts.ChoiceLabel
local CurrentLane = Parts.CurrentLane
local DEBUFF_TYPE_BORDER_MODE_VALUES = Parts.DEBUFF_TYPE_BORDER_MODE_VALUES
local DURATION_BAR_DIRECTION_VALUES = Parts.DURATION_BAR_DIRECTION_VALUES
local DURATION_BAR_DISPLAY_VALUES = Parts.DURATION_BAR_DISPLAY_VALUES
local DURATION_BAR_POSITION_VALUES = Parts.DURATION_BAR_POSITION_VALUES
local FlushApplyService = Parts.FlushApplyService
local GFAnchorValues = Parts.GFAnchorValues
local LaneDurationBarChoice = Parts.LaneDurationBarChoice
local LaneFrameEffectSearchRouteMetadata = Parts.LaneFrameEffectSearchRouteMetadata
local LaneTitle = Parts.LaneTitle
local Model = Parts.Model
local NormalizeDebuffTypeBorderMode = Parts.NormalizeDebuffTypeBorderMode
local RequestAuraRuntime = Parts.RequestAuraRuntime
local RequestUFPreviewRefresh = Parts.RequestUFPreviewRefresh
local Round = Parts.Round
local Tr = Parts.Tr
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type

local function AddUnitStyleScopeAccessors(S)
    local unit, lane, appearanceKind, appearanceGlobalsOnly = S.unit, S.lane, S.appearanceKind, S.appearanceGlobalsOnly
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
    function S.ReadScopeDebuffBorderMode()
        if type(Model.ReadDebuffTypeBorderMode) == "function" then return Model.ReadDebuffTypeBorderMode(unit) end
        return ReadScopeBool("useDebuffTypeBorders", false) and "SYMBOL" or "OFF"
    end
    function S.WriteScopeDebuffBorderMode(value)
        value = NormalizeDebuffTypeBorderMode(value, "OFF")
        if type(Model.WriteDebuffTypeBorderMode) == "function" then
            Model.WriteDebuffTypeBorderMode(unit, value)
        else
            WriteScopeBool("useDebuffTypeBorders", value ~= "OFF")
        end
    end
    function S.ReadScopeNumber(key, defaultValue, minValue, maxValue)
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceNumber) == "function" then
            return Model.ReadSharedAppearanceNumber(appearanceKind, key, defaultValue, minValue, maxValue)
        end
        if type(Model.ReadLaneStyleNumber) == "function" then return Model.ReadLaneStyleNumber(unit, lane, key, defaultValue, minValue, maxValue) end
        return Model.ReadNumber(unit, key, defaultValue, minValue, maxValue)
    end
    function S.WriteScopeNumber(key, value, minValue, maxValue)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceNumber) == "function" then
            Model.WriteSharedAppearanceNumber(appearanceKind, key, value, minValue, maxValue)
        elseif type(Model.WriteLaneStyleNumber) == "function" then
            Model.WriteLaneStyleNumber(unit, lane, key, value, minValue, maxValue)
        else
            Model.WriteNumber(unit, key, value, minValue, maxValue)
        end
    end
    function S.ReadScopeIconShape()
        if appearanceGlobalsOnly and type(Model.ReadSharedAppearanceIconShape) == "function" then
            return Model.ReadSharedAppearanceIconShape(appearanceKind)
        end
        local appearanceKind = lane == "debuff" and "debuff" or "buff"
        local value = type(Model.ReadSharedAppearanceIconShape) == "function"
            and Model.ReadSharedAppearanceIconShape(appearanceKind) or "RECTANGLE"
        return type(A3.NormalizeAuraIconShape) == "function" and A3.NormalizeAuraIconShape(value) or value
    end
    function S.WriteScopeIconShape(value)
        if appearanceGlobalsOnly and type(Model.WriteSharedAppearanceIconShape) == "function" then
            Model.WriteSharedAppearanceIconShape(appearanceKind, value or "RECTANGLE")
            return
        end
        -- Icon Shape belongs exclusively to the global Appearance product.
    end
    function S.ReadScopeCooldownAnchor()
        if type(Model.ReadLaneCooldownAnchor) == "function" then return Model.ReadLaneCooldownAnchor(unit, lane) end
        if type(Model.ReadCooldownAnchor) == "function" then return Model.ReadCooldownAnchor(unit) end
        return "CENTER"
    end
    function S.WriteScopeCooldownAnchor(value)
        if type(Model.WriteLaneCooldownAnchor) == "function" then
            Model.WriteLaneCooldownAnchor(unit, lane, value)
        elseif type(Model.WriteCooldownAnchor) == "function" then
            Model.WriteCooldownAnchor(unit, value)
        end
    end
    function S.ReadScopeSwipeDirection()
        return ReadScopeBool("cooldownSwipeReverse", false) and "REVERSE" or "NORMAL"
    end
    function S.WriteScopeSwipeDirection(value)
        WriteScopeBool("cooldownSwipeReverse", value == "REVERSE")
    end
    S.ReadScopeDurationBarDisplay, S.WriteScopeDurationBarDisplay =
        LaneDurationBarChoice(unit, lane, "DurationBarDisplay", "durationBarDisplay", "BAR_ONLY", "OVERLAY")
    S.ReadScopeDurationBarPosition, S.WriteScopeDurationBarPosition =
        LaneDurationBarChoice(unit, lane, "DurationBarPosition", "durationBarPosition", "BOTTOM", "TOP")
    S.ReadScopeDurationBarDirection, S.WriteScopeDurationBarDirection =
        LaneDurationBarChoice(unit, lane, "DurationBarDirection", "durationBarDirection", "REMAINING", "ELAPSED")
    S.ReadScopeBool, S.WriteScopeBool = ReadScopeBool, WriteScopeBool
end
-- The style binders: each write applies the unit, repaints the preview and
-- runs its afterSet; the control joins the page's style-control list.
local function AddUnitStyleBinders(S)
    local ctx, unit, lane, styleCatalogLane, styleControls = S.ctx, S.unit, S.lane, S.styleCatalogLane, S.styleControls
    local ReadScopeBool, WriteScopeBool, ReadScopeNumber, WriteScopeNumber = S.ReadScopeBool, S.WriteScopeBool, S.ReadScopeNumber, S.WriteScopeNumber
    local FlushStyleApply, RefreshStylePreview = S.FlushStyleApply, S.RefreshStylePreview
    local function AddStyleControl(control)
        M.AppendValues(styleControls, control)
        return control
    end
    -- refresh: a master switch that gates other controls re-runs the page refreshers.
    function S.BindStyleSwitch(parent, label, x, y, width, key, defaultValue, reason, afterSet, refresh)
        return AddStyleControl(BindSwitch(ctx, parent, label, x, y, width,
            function() return ReadScopeBool(key, defaultValue) end,
            function(v)
                WriteScopeBool(key, v)
                ApplyUnit(ctx, unit, reason, refresh == true)
                -- Switches are discrete writes. Compile/apply the new value
                -- before repainting so Menu and Edit Mode observe one state.
                -- ApplyService itself defers this flush during combat.
                FlushStyleApply()
                RefreshStylePreview()
                if type(afterSet) == "function" then afterSet() end
            end,
            AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken(key))))
    end
    function S.BindStyleDropdown(parent, label, x, y, values, width, getValue, setValue, reason, afterSet)
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
    function S.BindStyleSlider(parent, label, x, y, minVal, maxVal, step, width, key, defaultValue, readMin, readMax, writeMin, writeMax, reason, afterSet)
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
    S.AddStyleControl = AddStyleControl
end
-- Unit Style is built from one state record: the scope readers/writers and the
-- style binders above are created once, and each accordion builder re-establishes
-- the same local names from that record so the bodies read exactly as before.
local function CreateUnitStyleState(ctx, b, scope, options)
    local StyleState = {}
    options = type(options) == "table" and options or nil
    local embeddedUnitPreview = options and options.embeddedUnitPreview == true
    local appearanceGlobalsOnly = options and options.appearanceGlobalsOnly == true
    local previewContainer = options and options.previewContainer
    local appearanceKind = previewContainer or CurrentLane("auraStyleGFLane", "debuff")
    local unit = scope == "appearance" and "shared" or scope
    local lane = CurrentLane("auraStyleGFLane", "debuff")
    -- Runs on every style slider tick: one call that refreshes inline.
    local function RefreshStylePreview()
        if StyleState.refreshMiniPreview then
            AurasPage.RefreshMiniAuraPreviewNow(StyleState.refreshMiniPreview)
        elseif embeddedUnitPreview then
            local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
            if type(refreshOwnedPreview) == "function" then
                refreshOwnedPreview("AURAS3_UNIT_STYLE_DUMMY")
            else
                RequestUFPreviewRefresh("AURAS3_UNIT_STYLE_DUMMY")
            end
        end
    end
    local function BodyWidth(body)
        return body and (body._msuf2Width or body.GetWidth and body:GetWidth()) or b.width or 720
    end
    M.Assign(StyleState, {
        ctx = ctx, b = b, scope = scope,
        embeddedUnitPreview = embeddedUnitPreview, appearanceGlobalsOnly = appearanceGlobalsOnly, previewContainer = previewContainer,
        appearanceKind = appearanceKind, unit = unit, lane = lane,
        styleCatalogLane = appearanceGlobalsOnly and appearanceKind or lane, styleControls = {},
        baseId = "aura_style_" .. tostring(scope or "unit") .. "_" .. lane,
        RefreshStylePreview = RefreshStylePreview, FlushStyleApply = FlushApplyService, BodyWidth = BodyWidth,
    })
    AddUnitStyleScopeAccessors(StyleState)
    AddUnitStyleBinders(StyleState)
    return StyleState
end
local function BuildUnitStyleFrameBasics(StyleState)
    local ctx, b, appearanceGlobalsOnly, unit, lane, baseId, ReadScopeBool, ReadScopeDebuffBorderMode, WriteScopeDebuffBorderMode, BindStyleSwitch,
        BindStyleDropdown, BindStyleSlider, BodyWidth =
        StyleState.ctx, StyleState.b, StyleState.appearanceGlobalsOnly, StyleState.unit, StyleState.lane, StyleState.baseId, StyleState.ReadScopeBool,
        StyleState.ReadScopeDebuffBorderMode, StyleState.WriteScopeDebuffBorderMode, StyleState.BindStyleSwitch, StyleState.BindStyleDropdown,
        StyleState.BindStyleSlider, StyleState.BodyWidth
    local frameBasics
    local stealableStyleControl
    if not appearanceGlobalsOnly then
        local stealableLane = lane == "buff" and unit ~= "player"
        frameBasics = AurasPage.Section(b, baseId .. "_frame_basics", "Basics", stealableLane and 228 or 194, true)
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
                basicsCol, "showStealable", false, "AURAS3_STEALABLE_MARKER", nil, true)
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
            -- The Classic aura backends mark stealable buffs from their own scan,
            -- so the native AuraButton note is not true there.
            if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
                AddTooltip(stealableEnabled, "Native stealable marker",
                    "Uses Blizzard's 12.1 AuraButton stealable filter. It adds no MSUF aura scan, ticker, or OnUpdate.")
            end
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
    StyleState.frameBasics, StyleState.stealableStyleControl = frameBasics, stealableStyleControl
end
-- Icon Border & Shadow writes for the selected aura type. Switches and the
-- border style apply the shared runtime at once; slider drags repaint only the
-- preview and apply once on release, or after the trailing delay that wheel,
-- +/- and typed input share. iconStyleGates.Apply is read at each write, so the
-- skin wrapper installed later keeps gating the detail controls.
local function CreateIconStyleApply(StyleState, iconStyleGates)
    local appearanceKind, RefreshStylePreview = StyleState.appearanceKind, StyleState.RefreshStylePreview
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
        -- flush; the preview refresh below is combat-gated as well. Inline:
        -- this runs on every Icon Border/Shadow colour drag tick.
        ApplyService.Flush()
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
    return ApplyIconStyleRuntime, IconStyleWrite, FlushIconStyleApply, ScheduleIconStyleReleaseApply, QueueIconStyleApply
end
-- One RGB target of the Icon Border & Shadow ::: picker; alpha stays on its slider.
local function IconStyleColorTarget(label, historyLabel, colorKey, defaultColor, reason, ReadColor, Write)
    return {
        label = label,
        historyLabel = historyLabel,
        getRGB = function()
            local c = ReadColor(colorKey, defaultColor)
            return c[1] or 0, c[2] or 0, c[3] or 0
        end,
        setRGB = function(r, g, blue)
            local c = ReadColor(colorKey, defaultColor)
            Write(colorKey, { r, g, blue, c[4] or defaultColor[4] }, reason)
        end,
        defaultR = 0, defaultG = 0, defaultB = 0,
    }
end
local function BuildUnitStyleIconStyle(StyleState)
    local ctx, b, appearanceGlobalsOnly, appearanceKind, baseId, RefreshStylePreview, ReadScopeBool, ReadScopeNumber, AddStyleControl, BodyWidth =
        StyleState.ctx, StyleState.b, StyleState.appearanceGlobalsOnly, StyleState.appearanceKind, StyleState.baseId, StyleState.RefreshStylePreview,
        StyleState.ReadScopeBool, StyleState.ReadScopeNumber, StyleState.AddStyleControl, StyleState.BodyWidth
    local iconStyleGates = { border = {}, shadow = {}, Apply = function() end }
    if appearanceGlobalsOnly then
    -- Border and shadow are global for the selected Aura product. There is no
    -- frame-level opt-out; UF/GF Style owns only the remaining local details.
    -- Detail controls gray out while their master toggle is off, matching the
    -- rest of the aura style pages. Collected here so both the page refresher
    -- and the icon-style writes can re-apply the gate without a page rebuild.
    local iconStyle = AurasPage.Section(b, baseId .. "_icon_style", "Icon Border & Shadow", 278, false)
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
    local ApplyIconStyleRuntime, IconStyleWrite, FlushIconStyleApply, ScheduleIconStyleReleaseApply, QueueIconStyleApply =
        CreateIconStyleApply(StyleState, iconStyleGates)
    local function IconStyleReadColor(colorKey, defaultColor)
        local c = type(Model.ReadSharedAppearanceValue) == "function"
            and Model.ReadSharedAppearanceValue(appearanceKind, colorKey, defaultColor) or defaultColor
        if type(c) ~= "table" then c = defaultColor end
        return c
    end
    -- A drag applies the runtime once on release; hiding the page flushes it.
    local function HookReleaseApply(slider)
        slider:HookScript("OnMouseUp", ScheduleIconStyleReleaseApply)
        slider:HookScript("OnHide", FlushIconStyleApply)
        return slider
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
        return HookReleaseApply(slider)
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
                IconStyleWrite(colorKey, { c[1] or defaultColor[1], c[2] or defaultColor[2], c[3] or defaultColor[3], (tonumber(value) or 100) / 100 },
                    reason, true)
                QueueIconStyleApply(slider, reason)
            end,
            AuraControlMeta(ctx, "style.appearance.icon-style." .. AuraCatalogToken(colorKey) .. "-alpha")))
        return HookReleaseApply(slider)
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
                    IconStyleColorTarget("Icon Border Color", "Aura icon border color", "styleBorderColor",
                        ICON_STYLE_BORDER_DEFAULT, "AURAS3_ICON_STYLE_BORDER_COLOR", IconStyleReadColor, IconStyleWrite),
                    IconStyleColorTarget("Icon Shadow Color", "Aura icon shadow color", "styleShadowColor",
                        ICON_STYLE_SHADOW_DEFAULT, "AURAS3_ICON_STYLE_SHADOW_COLOR", IconStyleReadColor, IconStyleWrite),
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
        "Solid draws a crisp pixel ring around the icon. Soft Glow adds a halo, and Shadow shades the icon's own edges. The Blizzard entries and any "
            .. "LibSharedMedia border are drawn as edge art. Thickness scales the edge.")
    iconStyleGates.border[1] = borderStyleDropdown
    iconStyleGates.border[2] = IconStyleSlider("Border Thickness", 0, -122, 1, 8, "styleBorderThickness", 1, "AURAS3_ICON_STYLE_BORDER")
    iconStyleGates.border[3] = IconStyleAlphaSlider("Border Alpha (%)", 1, -122, "styleBorderColor", ICON_STYLE_BORDER_DEFAULT,
        "AURAS3_ICON_STYLE_BORDER_COLOR")
    IconStyleSwitch("Icon Shadow", -178, "styleShadowEnabled", "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[1] = IconStyleSlider("Shadow Size", 0, -210, 1, 16, "styleShadowSize", 4, "AURAS3_ICON_STYLE_SHADOW")
    iconStyleGates.shadow[2] = IconStyleAlphaSlider("Shadow Alpha (%)", 1, -210, "styleShadowColor", ICON_STYLE_SHADOW_DEFAULT,
        "AURAS3_ICON_STYLE_SHADOW_COLOR")
    end
    StyleState.iconStyleGates = iconStyleGates
end
local function BuildUnitStyleStack(StyleState)
    local ctx, b, scope, unit, lane, baseId, RefreshStylePreview, AddStyleControl, BindStyleSwitch, BindStyleSlider, BodyWidth =
        StyleState.ctx, StyleState.b, StyleState.scope, StyleState.unit, StyleState.lane, StyleState.baseId, StyleState.RefreshStylePreview,
        StyleState.AddStyleControl, StyleState.BindStyleSwitch, StyleState.BindStyleSlider, StyleState.BodyWidth
    local stack = AurasPage.Section(b, baseId .. "_stack", "Stack Count", 296, false)
    AurasPage.AttachTextColorShortcut(stack, unit, {
        title = M.Format("%s Stack Text Settings", Tr(LaneTitle(lane))),
        historyLabel = "Aura stack text color",
        historySource = "menu:auras-stack-text-color",
    }, {
        colorReferences = { "font.global" },
        colorTitle = "Aura Stack Text Color",
        subtitle = "Aura stack text follows the shared Fonts settings.",
    })
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
    StyleState.stack = stack
end
local function BuildUnitStyleCooldown(StyleState)
    local b, scope, unit, lane, baseId, ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, ReadScopeSwipeDirection, WriteScopeSwipeDirection,
        BindStyleDropdown, BindStyleSlider, BodyWidth =
        StyleState.b, StyleState.scope, StyleState.unit, StyleState.lane, StyleState.baseId, StyleState.ReadScopeCooldownAnchor,
        StyleState.WriteScopeCooldownAnchor, StyleState.ReadScopeSwipeDirection, StyleState.WriteScopeSwipeDirection, StyleState.BindStyleDropdown,
        StyleState.BindStyleSlider, StyleState.BodyWidth
    -- The final slider begins at -328 and its control sits another 24px lower.
    -- Leave a 16px footer so its buttons cannot bleed into Duration Bar.
    local cooldown = AurasPage.Section(b, baseId .. "_cooldown", "Cooldown Text", 392, true)
    AurasPage.AttachTextColorShortcut(cooldown, unit, {
        title = M.Format("%s Cooldown Text Settings", Tr(LaneTitle(lane))),
        historyLabel = "Aura cooldown text color",
        historySource = "menu:auras-cooldown-text-color",
    }, {
        colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
        colorTitle = M.Format("%s Cooldown Colors", Tr(LaneTitle(lane))),
        subtitle = "Aura cooldown text follows the shared Fonts settings.",
    })
    local cw = BodyWidth(cooldown)
    BindStyleSlider(cooldown, "Text Size", 24, -48, 6, 40, 1, cw - 48, "cooldownTextSize", 14, 6, 40, nil, nil, "AURAS3_COOLDOWN_SIZE")
    BindStyleDropdown(cooldown, "Anchor", 24, -104, type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues(), cw - 48,
        ReadScopeCooldownAnchor, WriteScopeCooldownAnchor, "AURAS3_COOLDOWN_ANCHOR")
    BindStyleSlider(cooldown, "X", 24, -162, -40, 40, 1, cw - 48, "cooldownTextOffsetX", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_X")
    BindStyleSlider(cooldown, "Y", 24, -222, -40, 40, 1, cw - 48, "cooldownTextOffsetY", 0, -2000, 2000, nil, nil, "AURAS3_COOLDOWN_Y")
    local swipeDirection = BindStyleDropdown(cooldown, "Swipe Direction", 24, -270, COOLDOWN_SWIPE_DIRECTION_VALUES, cw - 48, ReadScopeSwipeDirection,
        WriteScopeSwipeDirection, "AURAS3_COOLDOWN_SWIPE_DIRECTION")
    AddTooltip(swipeDirection, "Cooldown swipe direction", "Reverses only the swipe overlay. Icon size and position stay unchanged.")
    local decimal = BindStyleSlider(cooldown, "Decimals below sec", 24, -328, 0, 30, 1, cw - 48, "cooldownDecimalSeconds", 3, 0, 30, nil, nil,
        "AURAS3_COOLDOWN_FORMAT")
    AddTooltip(decimal, "Cooldown text format", "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and "
        .. "localized minutes above it. Set 0 for whole seconds only.")
    StyleState.cooldown = cooldown
end
local function BuildUnitStyleDurationBar(StyleState)
    local b, lane, baseId, ReadScopeBool, ReadScopeNumber, ReadScopeDurationBarDisplay, WriteScopeDurationBarDisplay, ReadScopeDurationBarPosition,
        WriteScopeDurationBarPosition, ReadScopeDurationBarDirection, WriteScopeDurationBarDirection, BindStyleSwitch, BindStyleDropdown, BindStyleSlider,
        BodyWidth =
        StyleState.b, StyleState.lane, StyleState.baseId, StyleState.ReadScopeBool, StyleState.ReadScopeNumber, StyleState.ReadScopeDurationBarDisplay,
        StyleState.WriteScopeDurationBarDisplay, StyleState.ReadScopeDurationBarPosition, StyleState.WriteScopeDurationBarPosition,
        StyleState.ReadScopeDurationBarDirection, StyleState.WriteScopeDurationBarDirection, StyleState.BindStyleSwitch, StyleState.BindStyleDropdown,
        StyleState.BindStyleSlider, StyleState.BodyWidth
    local refreshDurationBarSummary
    local durationInline = (b.width or 720) >= 520
    -- Dropdown buttons sit 24 px below their labels and carry a soft edge/glow.
    -- Keep a real footer inside the body so that art cannot bleed into the next
    -- accordion header in either the inline or narrow stacked layout.
    local durationBar = AurasPage.Section(b, baseId .. "_duration_bar", "Duration Bar", durationInline and 220 or 332, false)
    AurasPage.AttachDurationBarColor(durationBar, lane)
    local dbw = BodyWidth(durationBar)
    local durationChoiceWidth = durationInline and floor(((dbw - 48) - 20) / 3) or (dbw - 48)
    refreshDurationBarSummary = function()
        if not W.SetCollapsibleBadges then return end
        local enabled = ReadScopeBool("showDurationBar", false)
        W.SetCollapsibleBadges(durationBar, {{
            text = enabled and (tostring(Round(ReadScopeNumber("durationBarHeight", 2, 1, 16))) .. "px / "
                .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, ReadScopeDurationBarDisplay(), "Bar Only") .. " / "
                .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, ReadScopeDurationBarPosition(), "Bottom")) or "Off",
            kind = enabled and "accent" or "muted", showWhenClosed = true,
        }})
    end
    BindStyleSwitch(durationBar, "Show Duration Bar", 24, -48, dbw - 48, "showDurationBar", false, "AURAS3_DURATION_BAR", refreshDurationBarSummary)
    BindStyleSlider(durationBar, "Height", 24, -104, 1, 16, 1, dbw - 48, "durationBarHeight", 2, 1, 16, nil, nil, "AURAS3_DURATION_BAR_HEIGHT",
        refreshDurationBarSummary)
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
    StyleState.durationBar, StyleState.refreshDurationBarSummary = durationBar, refreshDurationBarSummary
end
local function BuildUnitStyleFrameEffect(StyleState)
    local ctx, b, unit, lane, baseId, RefreshStylePreview, AddStyleControl, BodyWidth =
        StyleState.ctx, StyleState.b, StyleState.unit, StyleState.lane, StyleState.baseId, StyleState.RefreshStylePreview, StyleState.AddStyleControl,
        StyleState.BodyWidth
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
    local frameEffect = AurasPage.Section(b, baseId .. "_full_frame", "Full-Frame Effect", 210, false)
    local few = BodyWidth(frameEffect)
    local effectCol = max(140, floor((few - 68) / 3))
    local effectGap = 10
    AddStyleControl(BindDropdown(ctx, frameEffect, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, few - 48,
        function() return tostring(ReadEffectValue("Type", "none")) end,
        function(value) WriteEffectValue("Type", value or "none", "AURAS3_LANE_FRAME_EFFECT") end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.type", nil,
            LaneFrameEffectSearchRouteMetadata(unit, lane, "type"))))
    local effectColor = W.Color(frameEffect, "Color")
    AurasPage.BindColor(ctx, effectColor,
        function()
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88
        end,
        function(r, g, blue)
            local c = ReadEffectValue("Color", { 0.69, 0.50, 0.88, 0.80 })
            WriteEffectValue("Color", { r, g, blue, c[4] or 0.80 }, "AURAS3_LANE_FRAME_EFFECT_COLOR")
        end,
        AuraControlMeta(ctx, "style.lane." .. AuraCatalogToken(lane) .. ".full-frame.color", nil,
            LaneFrameEffectSearchRouteMetadata(unit, lane, "color")))
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
                LaneFrameEffectSearchRouteMetadata(unit, lane, suffix))))
    end
    EffectSlider("Opacity", 0, -96, 5, 100, 5, "Alpha", 0.80, "AURAS3_LANE_FRAME_EFFECT_ALPHA")
    EffectSlider("Layer (0-30)", 1, -96, 0, 30, 1, "Layer", 0, "AURAS3_LANE_FRAME_EFFECT_LAYER")
    EffectSlider("Thickness", 2, -96, 1, 16, 1, "Thickness", 2, "AURAS3_LANE_FRAME_EFFECT_THICKNESS")
    EffectSlider("Priority", 0, -150, 1, 10, 1, "Priority", 5, "AURAS3_LANE_FRAME_EFFECT_PRIORITY")
    StyleState.frameEffect, StyleState.ReadEffectValue = frameEffect, ReadEffectValue
end
local function TrackUnitStyleBadges(StyleState)
    local ctx, unit, lane, styleControls, ReadScopeBool, ReadScopeDebuffBorderMode, ReadScopeNumber, ReadScopeCooldownAnchor, ReadScopeSwipeDirection,
        frameBasics, stealableStyleControl, iconStyleGates, stack, cooldown, refreshDurationBarSummary, frameEffect, ReadEffectValue =
        StyleState.ctx, StyleState.unit, StyleState.lane, StyleState.styleControls, StyleState.ReadScopeBool, StyleState.ReadScopeDebuffBorderMode,
        StyleState.ReadScopeNumber, StyleState.ReadScopeCooldownAnchor, StyleState.ReadScopeSwipeDirection, StyleState.frameBasics,
        StyleState.stealableStyleControl, StyleState.iconStyleGates, StyleState.stack, StyleState.cooldown, StyleState.refreshDurationBarSummary,
        StyleState.frameEffect, StyleState.ReadEffectValue
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
                    text = M.Format("Border %s", M.Tr(ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode))),
                    kind = borderMode == "OFF" and "muted" or "accent",
                    showWhenClosed = true,
                }
            elseif lane == "buff" then
                frameBasicsBadges[#frameBasicsBadges + 1] = ToggleBadge("Stealable", ReadScopeBool("showStealable", false))
            end
            if frameBasics then W.SetCollapsibleBadges(frameBasics, frameBasicsBadges) end

            local stackEnabled = ReadScopeBool("showStackCount", true)
            W.SetCollapsibleBadges(stack, {{
                text = stackEnabled and (tostring(Round(ReadScopeNumber("stackTextSize", 14, 6, 40))) .. "px / "
                    .. AnchorLabel(type(Model.ReadLaneStackAnchor) == "function" and Model.ReadLaneStackAnchor(unit, lane)
                    or Model.ReadStackAnchor(unit))) or "Off",
                kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
            }})

            local cooldownEnabled = ReadScopeBool("showCooldownText", true)
            local decimal = Round(ReadScopeNumber("cooldownDecimalSeconds", 3, 0, 30))
            W.SetCollapsibleBadges(cooldown, {
                { text = cooldownEnabled and (tostring(Round(ReadScopeNumber("cooldownTextSize", 14, 6, 40))) .. "px / "
                    .. AnchorLabel(ReadScopeCooldownAnchor()) .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, ReadScopeSwipeDirection(), "Normal"))
                    or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
            })

            refreshDurationBarSummary()

            if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
                local effectType = tostring(ReadEffectValue("Type", "none"))
                W.SetCollapsibleBadges(frameEffect, {{
                    text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                    kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
                }})
            end

        end
    end)
end
function AurasPage.BlizzardVisibilityControlId(setting)
    local path = setting == "auras3.shared.hideBlizzardBuffFrame" and "hide-buffs"
        or setting == "auras3.shared.hideBlizzardDebuffFrame" and "hide-debuffs"
    if not path then return nil end
    return AuraControlMeta({ key = "auras3_styling" }, "style.appearance.blizzard-aura-frames." .. path).controlId
end
function AurasPage.BuildBlizzardVisibility(ctx, b, baseId)
    local blizzardFrames = AurasPage.Section(b, baseId .. "_blizzard_aura_frames", "Blizzard Buff & Debuff Frames", 152, false)
    local bfw = blizzardFrames._msuf2Width or b.width or 720
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

local function BuildUnitStyle(ctx, b, scope, options)
    local StyleState = CreateUnitStyleState(ctx, b, scope, options)
    local embeddedUnitPreview, appearanceGlobalsOnly, previewContainer, unit, lane, baseId, RefreshStylePreview, ReadScopeIconShape, WriteScopeIconShape,
        BindStyleDropdown, BodyWidth =
        StyleState.embeddedUnitPreview, StyleState.appearanceGlobalsOnly, StyleState.previewContainer, StyleState.unit, StyleState.lane, StyleState.baseId,
        StyleState.RefreshStylePreview, StyleState.ReadScopeIconShape, StyleState.WriteScopeIconShape, StyleState.BindStyleDropdown, StyleState.BodyWidth

    if not embeddedUnitPreview then
        StyleState.refreshMiniPreview = AurasPage.BuildAuraStylePreviewWorkbench(ctx, b, unit, lane, previewContainer)
    end

    BuildUnitStyleFrameBasics(StyleState)

    if appearanceGlobalsOnly then
        local appearanceShape = AurasPage.Section(b, baseId .. "_appearance_shape", "Icon Shape", 112, false)
        local ssw = BodyWidth(appearanceShape)
        local appearanceLabel = previewContainer == "playerDefensives" and "Player Defensives"
            or previewContainer == "targetDots" and "Dots on Target" or LaneTitle(lane)
        local shape = BindStyleDropdown(appearanceShape, M.Format("%s Icon Shape", Tr(appearanceLabel)), 24, -48,
            M.AURA_ICON_SHAPE_VALUES, ssw - 48, ReadScopeIconShape, WriteScopeIconShape, "AURAS3_ICON_SHAPE")
        AddTooltip(shape, "Global icon shape",
            "Applies to every UnitFrame and GroupFrame icon of this Aura type. Spell Icons use the Buff appearance.")
    end

    AurasPage.BuildIconSkinSection(StyleState)
    BuildUnitStyleIconStyle(StyleState)
    local iconStyleGates = AurasPage.WrapIconSkinGates(StyleState)

    if appearanceGlobalsOnly then
        -- Re-apply the master-toggle gates whenever any Appearance page is
        -- revisited. This must not live in the Buff-only Native Aura Flow
        -- section: Debuffs, Player Defensives and Dots share these controls.
        M.TrackRefresh(ctx, function() iconStyleGates.Apply(true) end)
    end

    if appearanceGlobalsOnly and (previewContainer == "buff" or previewContainer == "debuff")
        and not AurasPage.BlizzardVisibilityType() then
        AurasPage.BuildBlizzardVisibility(ctx, b, baseId)
    end

    if appearanceGlobalsOnly and previewContainer == "buff" then
        local nativeFlow = AurasPage.Section(b, baseId .. "_native_flow", "Native Aura Flow", 112, false)
        local nfw = BodyWidth(nativeFlow)
        local weaponEnchants = BindSwitch(ctx, nativeFlow, "Show Weapon Enchants on Player", 24, -44, nfw - 48,
            function() return Model.ReadSharedBool("showWeaponEnchants", false) end,
            function(value)
                Model.WriteSharedBool("showWeaponEnchants", value == true)
                RequestAuraRuntime("shared", "AURAS3_WEAPON_ENCHANTS")
                RefreshStylePreview()
            end,
            AuraControlMeta(ctx, "style.appearance.native-flow.weapon-enchants"))
        M.DeclareExactViewContract(weaponEnchants, "auraStyleContainer", { buff = true }, function()
            M.auraAppearanceContainer = "buff"
            return true
        end)
        AddTooltip(weaponEnchants, "Native weapon enchant auras",
            "Adds Blizzard's temporary weapon-enchantment buttons to the Player Buff container. This is one shared setting and uses the native aura flow "
                .. "without an MSUF ticker or OnUpdate.")
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

    BuildUnitStyleStack(StyleState)
    BuildUnitStyleCooldown(StyleState)
    BuildUnitStyleDurationBar(StyleState)
    -- No Classic aura backend renders a lane Full-Frame Effect; its badge is
    -- skipped under the same gate in TrackUnitStyleBadges.
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then BuildUnitStyleFrameEffect(StyleState) end
    TrackUnitStyleBadges(StyleState)
end


-- Explicit load-time exports for the following responsibility modules.
Parts.BuildUnitStyle = BuildUnitStyle
