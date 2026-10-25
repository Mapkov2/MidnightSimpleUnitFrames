-- Class-resource page construction and dependent control state.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.ClassPowerPageParts
local W = Parts.W
local T = Parts.T
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local Bars = Parts.Bars
local BoolValue = Parts.BoolValue
local NumValue = Parts.NumValue
local SetValue = Parts.SetValue
local Schema = Parts.Schema
local SetControlEnabled = Parts.SetControlEnabled
local RegisterControl = Parts.RegisterControl
local CLASSPOWER_SETTING_KEY_BY_PATH = Parts.CLASSPOWER_SETTING_KEY_BY_PATH
local Meta = Parts.Meta
local RegisterSegment = Parts.RegisterSegment
local MoveWidget = Parts.MoveWidget
local SetControlsEnabled = Parts.SetControlsEnabled
local AddTooltip = Parts.AddTooltip
local ApplyClassPower = Parts.ApplyClassPower
local ApplyClassPowerSource = Parts.ApplyClassPowerSource
local ApplyClassPowerVisuals = Parts.ApplyClassPowerVisuals
local ApplyClassPowerSmoothing = Parts.ApplyClassPowerSmoothing
local ApplyClassPowerText = Parts.ApplyClassPowerText
local TextureValues = Parts.TextureValues
local VT = Parts.VT
local PLAYER_POWER_SOURCE_VALUES = Parts.PLAYER_POWER_SOURCE_VALUES
local NormalizePlayerPowerSource = Parts.NormalizePlayerPowerSource
local NormalizeClassPowerShape = Parts.NormalizeClassPowerShape
local NormalizeClassPowerShapeAlign = Parts.NormalizeClassPowerShapeAlign
local NormalizeDetachedPowerShape = Parts.NormalizeDetachedPowerShape
local NormalizePlayerHPShape = Parts.NormalizePlayerHPShape
local ResolvePlayerHPShape = Parts.ResolvePlayerHPShape
local DETACHED_POWER_TEXT_PRESET_VALUES = Parts.DETACHED_POWER_TEXT_PRESET_VALUES
local CLASS_POWER_TEXT_MODE_VALUES = Parts.CLASS_POWER_TEXT_MODE_VALUES
local DETACHED_POWER_TEXT_OUTLINE_VALUES = Parts.DETACHED_POWER_TEXT_OUTLINE_VALUES
local PLAYER_HP_ANCHOR_VALUES = Parts.PLAYER_HP_ANCHOR_VALUES
local PLAYER_HP_WIDTH_VALUES = Parts.PLAYER_HP_WIDTH_VALUES
local ALT_MANA_WIDTH_VALUES = Parts.ALT_MANA_WIDTH_VALUES
local PLAYER_HP_SHAPE_VALUES = Parts.PLAYER_HP_SHAPE_VALUES
local PLAYER_HP_COLOR_VALUES = Parts.PLAYER_HP_COLOR_VALUES
local PLAYER_HP_TEXT_VALUES = Parts.PLAYER_HP_TEXT_VALUES
local DETACHED_POWER_SLOT_VALUES = Parts.DETACHED_POWER_SLOT_VALUES
local DETACHED_POWER_SEPARATORS = Parts.DETACHED_POWER_SEPARATORS
local TEXT_SLOT_VALUES = Parts.TEXT_SLOT_VALUES
local CLASS_POWER_PREVIEW_VALUES = Parts.CLASS_POWER_PREVIEW_VALUES
local ApplyDetachedPowerBar = Parts.ApplyDetachedPowerBar
local ApplyDetachedPowerSource = Parts.ApplyDetachedPowerSource
local ApplyDetachedPowerWidthMode = Parts.ApplyDetachedPowerWidthMode
local Player = Parts.Player
local ApplyDetachedPlayerPowerSmoothing = Parts.ApplyDetachedPlayerPowerSmoothing
local ApplyDetachedPowerText = Parts.ApplyDetachedPowerText
local ApplyDetachedPowerBarOutline = Parts.ApplyDetachedPowerBarOutline
local ApplyPlayerHPBar = Parts.ApplyPlayerHPBar
local ApplyPlayerHPTextures = Parts.ApplyPlayerHPTextures
local ApplyPlayerHPText = Parts.ApplyPlayerHPText
local PlayerFrameWidth = Parts.PlayerFrameWidth
local PlayerPowerOutline = Parts.PlayerPowerOutline
local SetPlayerPowerOutline = Parts.SetPlayerPowerOutline
local SetPlayerTextValue = Parts.SetPlayerTextValue
local PlayerPowerTextShown = Parts.PlayerPowerTextShown
local NormalizeDetachedPowerTextPreset = Parts.NormalizeDetachedPowerTextPreset
local SetDetachedPowerTextPreset = Parts.SetDetachedPowerTextPreset
local ExecuteQuickSetup = Parts.ExecuteQuickSetup
local MaybeOfferQuickSetup = Parts.MaybeOfferQuickSetup
local BuildInlineClassPowerPreview = Parts.BuildInlineClassPowerPreview
local Card = Parts.Card
local Page = Parts.Page
local PlaceColumn = Parts.PlaceColumn
local HasPercent = Parts.HasPercent
local HidePercentValue = Parts.HidePercentValue
local CurrentDetachedTextSlot = Parts.CurrentDetachedTextSlot
local DetachedTextOffsetKeys = Parts.DetachedTextOffsetKeys
local ShowQuickSetupTooltip = Parts.ShowQuickSetupTooltip

function Page.New(ctx)
    local groups = {}
    for _, key in ipairs({ "cp", "cpText", "detached", "detachedPlayer", "detachedText", "detachedSlot", "hp", "hpText", "hpCustomText", "hpTextPosition",
        "hpManual", "hpOrb", "hpTexture", "altMana" }) do groups[key] = {} end
    local self = setmetatable({ ctx = ctx, b = W.PageBuilder(ctx), width = ctx.width or 900, groups = groups, refresh = M.RefreshProxy() }, Page)
    ctx.resizeWidthOwner = self
    self.workspace = M.ClassPowerWorkspace.Attach(self, CLASSPOWER_SETTING_KEY_BY_PATH)
    Schema.Custom(self.workspace, { id = "menu2.classpower.workspace", kind = "workspace",
        scope = "classpower", applyDomain = "workspace", owner = self.workspace })
    self.applyWorkspace = function()
        ApplyClassPower()
        ApplyDetachedPowerBar()
        ApplyPlayerHPBar()
        self.refresh()
    end
    return self
end
function Page:Add(group, ...) M.AppendValues(self.groups[group], ...) end
function Page:AddNamed(group, controls, names) M.AppendNamedValues(self.groups[group], controls, names) end
function Page:WithRefresh(apply)
    return function(...)
        apply(...)
        self.refresh()
    end
end
-- Local policies keep the original saved-value semantics; the shared binder owns
-- input refusal and history. Sources are resolved again for every input/read.
function Page.BindRow(ctx, widget, row, kind)
    row.customSetReason = row.customSetReason or "Applies class-resource value conversions or coupled layout and text settings."
    local meta = row.meta
    local spec = { id = meta.controlId, kind = kind, key = row.field or row[2],
        labelKey = row[4][1], scope = "classpower", applyDomain = "classpower",
        meta = meta, get = row.get, set = row.set, write = row.write,
        writeTargets = row.writeTargets,
            companionWrites = row.companionWrites, customSetReason = row.customSetReason, source = row.source, apply = row.apply,
        defaultSource = function() return row[3] end, workspace = row.workspace }
    if kind == "slider" then
        spec.range = { row[4][2], row[4][3], row[4][4] }
        spec.roundStep = row.roundStep
    end
    Schema.Bind(ctx, widget, spec)
end
Page.RowOptions = { bind = Page.BindRow }
local function SwitchAt(ctx, parent, label, x, y, width, source, key, default, apply, meta)
    local row = { "switch", key, default, { label, x, y, width and width - 22 }, meta = meta,
        get = function() return BoolValue(source(), key, default) end,
        write = { call = SetValue, source = source, args = { apply } } --[[schema setter: AdvancedClassPower.1]] }
    local widget = Schema.Build(ctx, parent, { row }, Page.RowOptions)[row[2]]
    RegisterControl(widget, meta, label, "toggle")
    return widget
end
function Page.RowAccessors(page, row, source, apply)
    local key, default, kind, policy = row.field, row[3], row[1], row.policy
    apply = row.apply or apply
    row.source, row.apply = source, apply
    row.roundStep = kind == "slider"
    if not policy then return end
    row.workspace = "classpower"
    if policy == "comboColorMode" then
        row.companionWrites = { "bars.classPowerSlotColorModes.COMBO_POINTS" }
        return function() return M.ColorsPage.GetClassPowerSlotMode("COMBO_POINTS") end,
            function(value) M.ColorsPage.SetClassPowerSlotMode("COMBO_POINTS", value) end
    elseif policy == "playerPowerOutline" then
        row.companionWrites = { "player.powerBarBorderEnabled", "player.powerBarBorderThickness" }
        row.roundStep = false
        return PlayerPowerOutline, function(value) SetPlayerPowerOutline(value, apply) end
    elseif policy == "alpha" then
        row[3] = (default or 0) * 100
        row.write = { call = SetValue, source = Bars, args = { apply },
            convert = function(value)
                value = tonumber(value) or ((default or 0) * 100)
                if value < 0 then value = 0 elseif value > 100 then value = 100 end
                return value / 100
            end } --[[schema setter: J5.ClassPower.Alpha]]
        return function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end
    elseif policy == "detachedPowerWidth" then
        row.companionWrites = { "player.detachedPowerBarSyncClassPower" }
        row[3] = nil
        return function() return tonumber(source()[key]) or PlayerFrameWidth() end,
            function(value)
                local player = source()
                player.detachedPowerBarSyncClassPower = false
                SetValue(player, key, value, apply)
            end
    elseif policy == "nilDefaultDropdown" then
        row.write = { source = source, convert = function(value) return value ~= default and value or nil end,
            after = apply } --[[schema setter: J5.ClassPower.NilDropdown]]
        return function() return source()[key] or default end
    elseif policy == "detachedTextOnBar" then
        local function WriteRecord(record, field, value)
            local function Write()
                local changed = record[field] ~= value
                if changed then record[field] = value apply() end
                return changed
            end
            return M.RunWithHistory(tostring(field), "classpower:detachedPowerText:" .. field, Write)
        end
        row.write = { source = source, call = WriteRecord, boolean = true, returns = true
        } --[[schema setter: J5.ClassPower.TextOnBar]]
        return function() return BoolValue(source(), key, default) end
    elseif policy == "detachedTextPreset" then
        return function() return NormalizeDetachedPowerTextPreset(Player()) end,
            function(value)
                SetDetachedPowerTextPreset(value)
                apply()
                page.refresh()
            end
    end
end
function Page:Controls(parent, source, apply, prefix, rows)
    local controls = {}
    for _, row in ipairs(rows) do
        if prefix ~= "behavior" or not MSUF.Client.SupportsClassResourceSetting
            or MSUF.Client.SupportsClassResourceSetting("bars." .. row.field) then
            row.meta = row.meta or Meta(prefix .. "." .. row[2])
            row.get, row.set = Page.RowAccessors(self, row, source, apply)
            if row.help then row.tip = { row.helpTitle or row[4][1], row.help, { hook = true, owner = "ANCHOR_RIGHT" } } end
            local control = Schema.Build(self.ctx, parent, { row }, Page.RowOptions)[row[2]]
            controls[row[2]] = control
            if row[1] == "dropdown" then control._msuf2StableSearchLabel = control._msuf2StableSearchLabel or row[4][1] end
            local kind = row[1] == "flowToggle" and "toggle" or row[1]
            RegisterControl(control, row.meta, row[4][1], kind, kind == "dropdown" and row[4][2] or nil)
            for group in tostring(row.group or ""):gmatch("%S+") do self:Add(group, control) end
        end
    end
    return controls
end
function Page:SourceToggle(parent, label, source, key, apply, prefix)
    return Schema.Build(self.ctx, parent, { { "flowToggle", key, false, { label }, workspace = "classpower",
        meta = Meta(prefix .. "." .. key), get = function() return HidePercentValue(source(), key) end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "player.hpPowerTextOverride" },
            write = { call = source == Player and SetPlayerTextValue or SetValue,
            source = source ~= Player and source or nil, keyOnly = source == Player,
            boolean = true, args = { apply }
        } --[[schema setter: J5.ClassPower.SourceToggle]] } }, Page.RowOptions)[key]
end

function Page:BuildHeader()
    local b, ctx = self.b, self.ctx
    local head = T.Panel(b.parent, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(head, "status")
    head:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    head._msuf2Width = b.width
    local selectorH = M.ClassPowerWorkspace.BuildSelector(self.workspace, head, b.width)
    Schema.Owned(self.workspace.selector, "classpower", "workspace")
    local headerH = selectorH + 82
    head:SetSize(b.width, headerH)
    if W.RegisterGuidedRegion then W.RegisterGuidedRegion(ctx, head, "Class resource preview and quick setup") end
    b.y = b.y - headerH - 8
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(b.y) + 28) end
    local desiredPreviewW = min(330, max(180, self.width - 438))
    local previewW = min(desiredPreviewW, max(120, b.width - 264))
    local preview = W.Dropdown(head, "Preview resource", CLASS_POWER_PREVIEW_VALUES, previewW)
    preview._msuf2StableSearchLabel = "Preview resource"
    RegisterControl(preview, Meta("preview.resource", "setting", {
        settingKey = "menu.classPowerPreviewResource",
        schemaEphemeralReason = "Selects the class-resource preview; no profile setting is written.",
    }), "Preview resource", "dropdown", CLASS_POWER_PREVIEW_VALUES)
    MoveWidget(preview, head, 14, -selectorH - 16, previewW)
    preview:SetOnValueChanged(function(value)
        M.SetClassPowerPreviewSpecKey(value)
        preview:SetValue(M.GetClassPowerPreviewSpecKey())
    end)
    preview:SetValue(M.GetClassPowerPreviewSpecKey())
    AddTooltip(preview, "Class Resource Preview", "Shows the selected class/spec resource below without changing your character, spec or saved settings.")
    M.TrackRefresh(ctx, function() preview:SetValue(M.GetClassPowerPreviewSpecKey()) end)
    Schema.Owned(preview, "classpower", "preview")
    local quick = Schema.Build(ctx, head, {
        { "button", "quick", nil, { "Quick Setup: Class Bar", 158, 24, { history = true } },
            anchor = { "TOPRIGHT", head, "TOPRIGHT", -16, -selectorH - 16 },
            beforeBind = function(widget)
                if W.StyleTopSuccessButton then W.StyleTopSuccessButton(widget)
                elseif W.StyleTopActionButton then W.StyleTopActionButton(widget) end
            end,
            action = function()
                M.ShowPrompt("MSUF2_CLASSPOWER_QUICK_CONFIRM", {
                    text = M.Format(
                        "Set up Class Resources and Player Power?\n\nChanges visibility, anchors, sizes and positions.\nPlacement: %s.\n\nUndo is available.",
                        M.Tr("Essential Cooldowns or screen center")),
                    accept = M.Tr("Setup Now"), cancel = CANCEL, onAccept = ExecuteQuickSetup,
                })
            end },
    }).quick
    quick:SetScript("OnEnter", ShowQuickSetupTooltip)
    quick:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    RegisterControl(quick, Meta("quick_setup.class_bar", "action", { confirmRequired = true }), "Quick Setup: Class Bar", "button")
    Schema.Owned(quick, "classpower", "quickSetup")
    M.ResourceExtrasPreview.BuildHeader(self, head, selectorH, b.width, preview, quick)
    -- Dock the selector strip like the unit pages' Editing strip and the
    -- Colors category bar: both selector and preview occupy the fixed stack,
    -- in that order, before the settings ScrollFrame begins.
    if W.AttachStickyPageHeader then
        W.AttachStickyPageHeader(head, {
            pageKey = ctx and ctx.key,
            wrapper = ctx and ctx.wrapper,
            gap = 4,
            dynamicHeight = true,
            heightResolver = function() return selectorH + (self.workspace.selected == "extras" and 136 or 82) end,
            builder = b,
            ctx = ctx,
            flowGap = 8,
        })
    end
end

function Page:BuildClassLayout()
    local compact, width = self.width < 680, self.width
    local section = self:Section("classpower_display", "Layout", compact and 760 or 440, true)
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    local applySourceRefresh = self:WithRefresh(ApplyClassPowerSource)
    self.cpEnable = Schema.Build(self.ctx, section, { { "sectionSwitch", "cpEnable", nil, { "Class Resource" },
        workspace = "classpower", meta = Meta("layout.enabled"),
        get = function() return BoolValue(Bars(), "showClassPower", true) end,
        write = { call = SetValue, source = Bars, args = { applySourceRefresh } } --[[schema setter: AdvancedClassPower.3]] } }, Page.RowOptions).cpEnable
    self.cp = self:Controls(section, Bars, ApplyClassPower, "layout", {
        { "dropdown", "shape", "BAR", { "Class Resource shape", VT("BAR", "Bar", "CIRCLE", "Circle", "DIAMOND", "Diamond", "HEX", "Hex"), 260 },
            field = "classPowerShape", apply = applyRefresh },
        { "slider", "height", 4, { "Height", 1, 40, 1, 300 }, field = "classPowerHeight" },
        { "dropdown", "widthMode", "player", { "Width mode", VT("player", "Player frame", "auto_pips", "Auto fit pips", "cooldown",
            "Essential Cooldowns", "utility",
            "Utility Cooldowns", "tracked_buffs", "Tracked Buffs", "custom", "Custom"), 260 }, field = "classPowerWidthMode",
                apply = applySourceRefresh, help = "Auto fit pips is active only for Circle, Diamond and Hex. It uses pip count x pip size plus gaps." },
        { "slider", "width", 0, { "Width", 30, 800, 1, 300 }, field = "classPowerWidth" },
        { "slider", "x", 0, { "Offset X", -800, 800, 1, 300 }, field = "classPowerOffsetX" },
        { "slider", "y", 0, { "Offset Y", -800, 800, 1, 300 }, field = "classPowerOffsetY" },
        { "slider", "level", 5, { "Class Resource layer", 0, 30, 1, 300 }, field = "classPowerFrameLevelOffset" },
    })
    local alignValues = VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right")
    self.cpAlign = Schema.Build(self.ctx, section, { { "segment", "alignment", nil, { "Shape alignment", alignValues, 300 },
        meta = Meta("layout.shape_alignment"), get = function() return NormalizeClassPowerShapeAlign(Bars().classPowerShapeAlign) end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", write = {
                source = Bars, convert = NormalizeClassPowerShapeAlign, after = ApplyClassPower
            } --[[schema setter: H4.AdvancedClassPower.2]] } }, Page.RowOptions).alignment
    RegisterSegment(self.cpAlign, "layout.shape_alignment", alignValues, "setting")
    self:Add("cp", self.cp.shape, self.cp.height, self.cp.widthMode, self.cpAlign, self.cp.x, self.cp.y, self.cp.level)
    AddTooltip(self.cp.level, "Class Resource Layer", "Orders the Class Resource bar and pips. Its numeric, Rune and Ebon duration text uses the separate "
        .. "Class Resource text layer under Appearance > Text.")
    local rightX = compact and 32 or min(max(430, floor(width * .52)), max(360, width - 360))
    local leftW = compact and max(250, width - 64) or max(250, rightX - 74)
    local rightW = compact and leftW or max(250, width - rightX - 32)
    local controlW = min(300, leftW, rightW)
    Card(section, "Shape & Size", nil, 18, -38, leftW + 28, 370, "group")
    Card(section, "Position", nil, rightX - 14, compact and -430 or -38, rightW + 28, 286, "group")
    PlaceColumn(section, 32, -116, 54, controlW, "LEFT", self.cp.shape, self.cp.height, self.cp.widthMode, self.cp.width, self.cpAlign)
    PlaceColumn(section, rightX, compact and -484 or -92, 54, controlW, nil, self.cp.x, self.cp.y, self.cp.level)
end

function Page:BuildClassBehavior()
    local section = self:Section("classpower_behavior", "Behavior", 282, false)
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    local fields = self:Controls(section, Bars, ApplyClassPower, "behavior", {
        { "flowToggle", "anchor", false, { "Anchor to Essential Cooldown" }, field = "classPowerAnchorToCooldown", group = "cp" },
        { "flowToggle", "charged", true, { "Show empowered combo points" }, field = "showChargedComboPoints", group = "cp" },
        { "flowToggle", "text", false, { "Show resource text" }, field = "classPowerShowText", group = "cp" },
        { "flowToggle", "rune", true, { "Show rune time (per rune)" }, field = "runeShowTime", group = "cp" },
        { "flowToggle", "reverse", false, { "Fill right-to-left" }, field = "classPowerFillReverse", group = "cp" },
        { "flowToggle", "sweeping", false, { "Show Sweeping Strikes (Arms)" }, field = "showSweepingStrikes", apply = applyRefresh, group = "cp",
            helpTitle = "Sweeping Strikes",
            help = "Arms only. Shows actual aura charges in a segmented bar, using the same native display as Fury Whirlwind. These two trackers use a bar "
                .. "with static dividers; aura values are never read by the addon. Appearance changes during combat apply after combat." },
        { "flowToggle", "ele", false, { "Show Maelstrom bar (Ele)" }, field = "showEleMaelstrom", group = "cp" },
        { "flowToggle", "ebon", true, { "Show Ebon Might duration (Aug)" }, field = "showEbonMight", group = "cp",
            helpTitle = "Ebon Might On Player Power",
            help = "Augmentation Evoker only. The Player power bar shows the remaining Ebon Might duration instead of Mana, and uses the Player Power "
                .. "settings below for width, height, position, textures and text. Essence stays an ordinary Class Resource, and Mana is available through "
                .. "Alternative Mana. Turn this off to get a normal Mana bar back." },
        { "flowToggle", "shadow", false, { "Show Insanity bar (Shadow)" }, field = "showShadowMana", group = "cp" },
        { "flowToggle", "ironfur", false, { "Show Ironfur tracker (Guardian)" }, field = "showGuardianIronfur", apply = applyRefresh, group = "cp",
            helpTitle = "Guardian Ironfur Tracker",
            help = "In Bear Form, replaces the empty Guardian class-resource slot with an estimated Ironfur lifetime bar. Each successful cast adds one "
                .. "moving marker; Ursoc's Endurance and Guardian of Elune are included." },
        { "flowToggle", "ironfurHashes", true, { "Show Ironfur cast markers" }, field = "guardianIronfurShowHashLines", group = "cp",
            helpTitle = "Ironfur Cast Markers",
            help = "Shows one moving marker per tracked Ironfur cast. The 30 Hz motion ticker exists only while the optional tracker has active casts." },
        { "flowToggle", "prediction", true, { "Show resource prediction" }, field = "classPowerShowPrediction", group = "cp" },
        { "flowToggle", "smooth", false, { "Smooth fill" }, field = "classPowerSmoothFill", apply = ApplyClassPowerSmoothing, group = "cp",
            helpTitle = "Class Resource Smooth Fill", help = "Smooths resource changes. Runes, Essence recharge, and timers keep their own animation." },
    })
    local twoColumns = self.width >= 680
    local cardW = twoColumns and floor((self.width - 56) / 2) or self.width - 36
    local rightX = 52 + cardW
    local function PlaceSupported(x, y, keys)
        local count = 0
        for key in keys:gmatch("%S+") do
            if fields[key] then
                MoveWidget(fields[key], section, x, y - count * 32, cardW - 28)
                count = count + 1
            end
        end
        return count
    end
    local leftRows = PlaceSupported(32, -52, "anchor charged text rune reverse sweeping")
    local rightRows = PlaceSupported(twoColumns and rightX or 32, twoColumns and -52 or -52 - leftRows * 32,
        "ele ebon shadow ironfur ironfurHashes prediction smooth")
    local rows = twoColumns and max(leftRows, rightRows) or leftRows + rightRows
    local cardH = 22 + rows * 32
    local leftCard = W.ControlCardBackdrop(section, 18, -38, cardW, cardH)
    local rightCard = twoColumns and W.ControlCardBackdrop(section, rightX - 14, -38, cardW, cardH)
    self.ctx:AddResizeCallback(function()
        cardW = twoColumns and floor((self.width - 56) / 2) or self.width - 36
        rightX = 52 + cardW
        PlaceSupported(32, -52, "anchor charged text rune reverse sweeping")
        PlaceSupported(twoColumns and rightX or 32, twoColumns and -52 or -52 - leftRows * 32,
            "ele ebon shadow ironfur ironfurHashes prediction smooth")
        leftCard:SetWidth(cardW)
        if rightCard then
            rightCard:SetWidth(cardW)
            rightCard:ClearAllPoints()
            rightCard:SetPoint("TOPLEFT", section, "TOPLEFT", rightX - 14, -38)
        end
    end)
    section._msuf2CursorY = -38 - cardH
    self.b:FinishSection(section, 18)
    self.ironfurHashes = fields.ironfurHashes
end

function Page:BuildClassStyle()
    local section = self:Section("classpower_visuals", "Appearance", 482, false)
    local width, inner = section._msuf2Width or self.width, max(320, (section._msuf2Width or self.width) - 64)
    local cardW, frames = min(540, width - 36), {}
    local controlW = cardW - 32
    local resources, text, opacity, pips = M.UnitSectionsShared.MakeTabFrames(section, -108, width, frames, "resources", "text", "opacity", "pips")
    local values = VT("resources", "Textures", "text", "Text", "opacity", "Opacity", "pips", "Pips")
    local tabs, _, _, selectStyle = W.SegmentTabs(self.ctx, section, { stateKey = "classPowerStyleTab", label = "Style area", values = values,
        width = min(620, inner), frames = frames, defaultTab = "resources", x = 32, y = -44 })
    self.workspace.selectStyle = selectStyle
    RegisterSegment(tabs, "style.workspace_tab", values)
    M.Assign(self.cp, self:Controls(resources, Bars, ApplyClassPowerVisuals, "style.resources", {
        { "flowToggle", "color", true, { "Color by resource type" }, field = "classPowerColorByType", group = "cp" },
        { "dropdown", "comboColor", "default", { "Combo point colors", VT("default", "Resource color", "ramp", "Combo ramp", "custom",
            "Custom slots"), 260 }, field = "classPowerComboPointColorMode", policy = "comboColorMode", group = "cp" },
        { "dropdown", "fgTex", "", { "Foreground texture", function() return TextureValues("Use global bar texture") end, 300 },
            field = "classPowerTexture", group = "cp" },
        { "dropdown", "bgTex", "", { "Background texture", function() return TextureValues("Use foreground texture") end, 300 },
            field = "classPowerBgTexture", group = "cp" },
    }))
    M.Assign(self.cp, self:Controls(text, Bars, ApplyClassPowerText, "style.text", {
        { "dropdown", "mode", "AUTO", { "Resource text", CLASS_POWER_TEXT_MODE_VALUES, 300 }, field = "classPowerTextMode", group = "cpText" },
        { "slider", "font", 16, { "Font size", 6, 32, 1, 300 }, field = "classPowerFontSize", group = "cpText" },
        { "slider", "layer", 5, { "Class Resource text layer", 0, 30, 1, 300 }, field = "classPowerTextLayer", apply = ApplyClassPower, group = "cpText" },
        { "slider", "textX", 0, { "Text X", -200, 200, 1, 300 }, field = "classPowerTextOffsetX", group = "cpText" },
        { "slider", "textY", 0, { "Text Y", -200, 200, 1, 300 }, field = "classPowerTextOffsetY", group = "cpText" },
    }))
    AddTooltip(self.cp.mode, "Resource Text", "Automatic keeps each resource's established text, such as Current for Combo Points and Current / Maximum for "
        .. "Vengeance Soul Fragments. The explicit modes override only the central resource value; Rune timers, Ebon Might duration and the Ironfur stack "
        .. "counter keep their native formats.")
    AddTooltip(self.cp.layer, "Class Resource Text Layer",
        "Orders Class Resource numeric text, Rune times and the Ebon Might duration text independently from the Class Resource bar and Player Power text.")
    M.Assign(self.cp, self:Controls(opacity, Bars, ApplyClassPower, "style.opacity", {
        { "slider", "bg", .3, { "BG opacity", 0, 100, 1, 300 }, field = "classPowerBgAlpha", policy = "alpha", group = "cp" },
        { "slider", "filled", 1, { "Filled %", 0, 100, 5, 300 }, field = "classPowerFilledAlpha", policy = "alpha", group = "cp" },
        { "slider", "empty", .3, { "Empty %", 0, 100, 5, 300 }, field = "classPowerEmptyAlpha", policy = "alpha", group = "cp" },
    }))
    M.Assign(self.cp, self:Controls(pips, Bars, ApplyClassPower, "style.pips", {
        { "slider", "separator", 1, { "Separator", 0, 4, 1, 300 }, field = "classPowerTickWidth", group = "cp" },
        { "slider", "outline", 1, { "Outline", 0, 4, 1, 300 }, field = "classPowerOutline", group = "cp" },
        { "slider", "gap", 0, { "Pip gap", 0, 8, 1, 300 }, field = "classPowerGap", group = "cp" },
    }))
    local resourcesCard, textCard, pipsCard
    for _, card in ipairs({ { resources, "Resource & Textures", 252 }, { text, "Text", 318 }, { opacity, "Opacity", 214 }, { pips, "Pips & Border", 230 } }) do
        local controlCard = Card(card[1], card[2], nil, 18, -38, cardW, card[3], "group")
        if card[1] == resources then resourcesCard = controlCard end
        if card[1] == text then textCard = controlCard end
        if card[1] == pips then pipsCard = controlCard end
    end
    if W.AttachContextColorReferences then
        local function CurrentClassPowerRefs()
            return { "class_power.current" }
        end
        local function CurrentClassPowerContext(includeSlots)
            local spec = M.GetClassPowerPreviewSpec and M.GetClassPowerPreviewSpec() or nil
            return {
                resourceToken = type(spec) == "table" and spec.token or nil,
                slot = type(spec) == "table" and spec.value or nil,
                includeSlots = includeSlots,
            }
        end
        for _, card in ipairs({ { resourcesCard, "menu:class-power-resource-colors", false },
            { pipsCard, "menu:class-power-pip-colors", true } }) do
            W.AttachContextColorReferences(card[1], CurrentClassPowerRefs, {
                title = "Class Resource Colors",
                note = "Colors follow the currently selected preview resource.",
                historySource = card[2],
                context = function() return CurrentClassPowerContext(card[3]) end,
            })
        end
    end
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(textCard, {
            title = "Class Resource Text Settings",
            historyLabel = "Class resource text color",
            historySource = "menu:class-power-text-color",
            textSettings = {
                scope = "shared",
                kind = "class_power",
                colorReferences = { "class_power.text" },
                colorTitle = "Class Resource Text Color",
                subtitle = "Class Resource text follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    MoveWidget(self.cp.color, resources, 32, -76, controlW)
    MoveWidget(self.cp.comboColor, resources, 32, -112, controlW, "LEFT")
    PlaceColumn(resources, 32, -170, 58, controlW, nil, self.cp.fgTex, self.cp.bgTex)
    MoveWidget(self.cp.mode, text, 32, -84, controlW, "LEFT")
    PlaceColumn(text, 32, -136, 52, controlW, nil, self.cp.font, self.cp.layer, self.cp.textX, self.cp.textY)
    PlaceColumn(opacity, 32, -84, 52, controlW, nil, self.cp.bg, self.cp.filled, self.cp.empty)
    PlaceColumn(pips, 32, -84, 52, controlW, nil, self.cp.separator, self.cp.outline, self.cp.gap)
end

function Page:BuildClassVisibility()
    local section = self:Section("classpower_visibility", "Auto-Hide", 280, false)
    local width = min(560, (section._msuf2Width or self.width) - 28)
    Card(section, "Auto-Hide Rules", nil, 14, -54, width, 206)
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    for i, spec in ipairs({
        { "Hide out of combat", "classPowerHideOOC", "out_of_combat" },
        { "Hide when full", "classPowerHideWhenFull", "when_full" },
        { "Hide when empty", "classPowerHideWhenEmpty", "when_empty" },
    }) do
        self:Add("cp", SwitchAt(self.ctx, section, spec[1], 32, -54 - i * 32, width - 48, Bars, spec[2], false, applyRefresh, Meta("visibility." .. spec[3])))
    end
    self.cp.syncPlayerPowerOOC = SwitchAt(self.ctx, section, "Hide player power with Class Resource",
        32, -182, width - 48, Bars, "classPowerSyncPlayerPowerOOC", false,
        applyRefresh, Meta("visibility.sync_player_power_ooc"))
    self:Add("cp", self.cp.syncPlayerPowerOOC)
    AddTooltip(self.cp.syncPlayerPowerOOC, "Hide player power with Class Resource",
        "When Hide out of combat is enabled, hide the Player Power bar and its text with Class Resource. Player Power returns in combat. Edit Mode keeps them "
            .. "visible.")
    SetControlEnabled(self.cp.syncPlayerPowerOOC,
        BoolValue(Bars(), "showClassPower", true) and BoolValue(Bars(), "classPowerHideOOC", false))
    self:Add("cp", SwitchAt(self.ctx, section, "Independent of Player Frame visibility",
        32, -214, width - 48, Bars, "classPowerIndependentVisibility", false,
        applyRefresh, Meta("visibility.independent")))
end

function Page:BuildResourceVisibility(id, path, prefix, group, apply, combatOnly)
    local section = self:Section(id, "Auto-Hide", combatOnly and 184 or 248, false)
    local width = min(560, (section._msuf2Width or self.width) - 28)
    Card(section, "Auto-Hide Rules", nil, 14, -54, width, combatOnly and 110 or 174)
    local specs = {
        { "Independent of Player Frame visibility", "IndependentVisibility", "independent" },
        { "Hide out of combat", "HideOOC", "out_of_combat" },
    }
    if not combatOnly then
        specs[#specs + 1] = { "Hide when full", "HideWhenFull", "when_full" }
        specs[#specs + 1] = { "Hide when empty", "HideWhenEmpty", "when_empty" }
    end
    for i, spec in ipairs(specs) do
        local control = SwitchAt(self.ctx, section, spec[1], 32, -54 - i * 32, width - 48,
            Bars, prefix .. spec[2], false, self:WithRefresh(apply), Meta(path .. "." .. spec[3]))
        if group then self:Add(group, control) end
        if i == 1 then
            AddTooltip(control, "Independent of Player Frame visibility",
                combatOnly and "Resource helpers stay visible when Player is hidden. Marks and mana overlays keep their resource bar as the position source."
                    or "Uses this resource's Auto-Hide rules when Player Frame visibility hides Player. Player Power must be detached.")
        end
    end
end

function Page:Section(...)
    local section = self.b:CollapsibleSection(...)
    if not section._msuf2CollapsibleEntry.header._msuf2ControlSchema then Schema.Section(section, "classpower") end
    return section
end

function Page:BarArea(id, title, height, open)
    local section = self:Section(id, title, height, open)
    local cardW = min(650, (section._msuf2Width or self.width) - 28)
    local twoColumns = self.width >= 680 and cardW >= 620
    local controlW = twoColumns and floor((cardW - 56) / 2) or min(360, cardW - 36)
    return section, controlW, twoColumns and 52 + controlW or 32, twoColumns, cardW
end

function Page:BuildDetachedPower()
    local layout, controlW, rightX, twoColumns, cardW = self:BarArea("classpower_detached_power", "Layout", self.width < 680 and 932 or 600)
    Card(layout, "Detached Player Power",
        "When anchored here, Player power settings are managed by Class Resources. "
            .. "In Automatic mode, Augmentation Evoker shows Ebon Might on this bar.", 14, -38, cardW, twoColumns and 536 or 880)
    self.dpbUse = Schema.Build(self.ctx, layout, { { "sectionSwitch", "dpbUse", nil, { "Detached player power" },
        workspace = "classpower", meta = Meta("detached_power.enabled"),
        get = function() return Player().powerBarDetached == true end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = Schema.Fields({ "player" }, { "showPowerBar", "detachedPowerBarSyncClassPower",
                "detachedPowerBarAnchorToClassPower", "detachedPowerBarOffsetX", "detachedPowerBarOffsetY",
                "detachedPowerBarHeight", "detachedPowerBarFrameLevelOffset" }).recordPaths,
            set = function(value)
            local player = Player()
            player.powerBarDetached = value and true or false
            if value then
                player.showPowerBar = true
                if player.detachedPowerBarSyncClassPower == nil then player.detachedPowerBarSyncClassPower = true end
                if player.detachedPowerBarAnchorToClassPower == nil then player.detachedPowerBarAnchorToClassPower = true end
                player.detachedPowerBarOffsetX = tonumber(player.detachedPowerBarOffsetX) or 0
                player.detachedPowerBarOffsetY = tonumber(player.detachedPowerBarOffsetY) or -4
                player.detachedPowerBarHeight = tonumber(player.detachedPowerBarHeight) or 6
                player.detachedPowerBarFrameLevelOffset = tonumber(player.detachedPowerBarFrameLevelOffset) or 6
            end
            ApplyDetachedPowerSource()
            self.refresh()
        end } }, Page.RowOptions).dpbUse
    local smooth = SwitchAt(self.ctx, layout, "Smooth fill", twoColumns and rightX or 32, twoColumns and -104 or -138, controlW,
        Player, "powerSmoothFill", false, ApplyDetachedPlayerPowerSmoothing, Meta("detached_power.layout.smooth_fill"))
    local sourceMeta = Meta("detached_power.layout.resource_source", "setting", {
        label = M.PlayerPowerSourceSearchLabel,
        historySource = "classpower:playerPowerSource",
    })
    self.dpbSource = Schema.Build(self.ctx, layout, { { "dropdown", "resource_source", nil, { "Displayed resource", PLAYER_POWER_SOURCE_VALUES, 300 },
        workspace = "classpower", meta = sourceMeta, flagsBefore = { _msuf2StableSearchLabel = M.PlayerPowerSourceSearchLabel },
        get = function() return NormalizePlayerPowerSource(Player().playerPowerSource) end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = {
                source = Player, convert = NormalizePlayerPowerSource, skipEqual = true,
                after = function() M.ApplyPlayerPowerSource("MSUF2_CLASSPOWER_PLAYER_POWER_SOURCE") end
            } --[[schema setter: H4.AdvancedClassPower.4]] } }, Page.RowOptions).resource_source
    RegisterControl(self.dpbSource, sourceMeta,
        M.PlayerPowerSourceSearchLabel, "dropdown", PLAYER_POWER_SOURCE_VALUES)
    MoveWidget(self.dpbSource, layout, 32, twoColumns and -154 or -188, controlW, "LEFT")
    AddTooltip(self.dpbSource, "Displayed resource",
        M.PlayerPowerSourceTooltip)
    local mode = self:Controls(layout, Bars, ApplyDetachedPowerWidthMode, "detached_power.layout", {
        { "dropdown", "mode", "manual", { "Width mode", VT("manual", "Manual", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns",
            "tracked_buffs", "Tracked Buffs"), 260 }, field = "detachedPowerBarWidthMode", policy = "nilDefaultDropdown",
            apply = self:WithRefresh(ApplyDetachedPowerWidthMode), group = "detached" },
    })
    self.dpb = self:Controls(layout, Player, ApplyDetachedPowerBar, "detached_power.layout", {
        { "flowToggle", "anchor", false, { "Anchor to Class Resource" }, field = "detachedPowerBarAnchorToClassPower", group = "detachedPlayer" },
        { "flowToggle", "sync", true, { "Sync width to Class Resource" }, field = "detachedPowerBarSyncClassPower", apply = ApplyDetachedPowerSource,
            group = "detachedPlayer" },
        { "slider", "width", 0, { "Power width", 20, 800, 1, 300 }, field = "detachedPowerBarWidth", policy = "detachedPowerWidth",
            apply = self:WithRefresh(ApplyDetachedPowerSource), group = "detachedPlayer" },
        { "slider", "orbSize", 54, { "Orb size", 20, 160, 1, 300 }, field = "detachedPowerOrbSize", group = "detachedPlayer" },
        { "slider", "x", 0, { "Power X", -1000, 1000, 1, 300 }, field = "detachedPowerBarOffsetX", group = "detachedPlayer" },
        { "slider", "y", -4, { "Power Y", -1000, 1000, 1, 300 }, field = "detachedPowerBarOffsetY", group = "detachedPlayer" },
        { "slider", "height", 6, { "Power height", 2, 80, 1, 300 }, field = "detachedPowerBarHeight", group = "detachedPlayer" },
        { "slider", "layer", 6, { "Player Power layer", 0, 30, 1, 300 }, field = "detachedPowerBarFrameLevelOffset", group = "detachedPlayer" },
    })
    AddTooltip(self.dpbUse, "Detached Player Power", "Moves the Player power bar out of the unit frame. Anchor connects it to the Class Resources stack; Sync "
        .. "only follows the stack width. In Automatic mode, Augmentation Evoker uses this bar for Ebon Might; an explicit Mana selection keeps it as Mana.")
    AddTooltip(self.dpb.anchor, "Anchor To Class Resource",
        "Keeps detached Player power attached to the Class Resource bar. Player power controls are disabled while this connection is active.")
    AddTooltip(self.dpb.width, "Power Width", "Manual width for the detached Player power bar. Available while Width mode is Manual; dragging it releases "
        .. "Sync width to Class Resource, because that sync would otherwise win. Unset, the bar inherits the Player frame width.")
    AddTooltip(self.dpb.sync, "Sync Width",
        "Uses the Class Resource width for detached Player power without making Class Resources own the Player power controls.")
    AddTooltip(self.dpb.layer, "Player Power Layer", "Orders only the normal Player Power bar. It does not control Class Resource pips or their text.")
    self.cpPowerShape = Schema.Build(self.ctx, layout, { { "dropdown", "cpPowerShape", nil, { "Powerbar shape (independent)", VT("BAR", "Bar", "ROUND",
        "Round", "CRYSTAL", "Crystal", "ORB", "Orb"), 300 },
        workspace = "classpower", meta = Meta("layout.independent_powerbar_shape", "setting", { settingKey = "player.detachedPowerBarShape" }),
        get = function() return NormalizeDetachedPowerShape(Player().detachedPowerBarShape) end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "player.detachedPowerOrbSize" },
            set = function(value)
            local player = Player()
            player.detachedPowerBarShape = NormalizeDetachedPowerShape(value)
            if player.detachedPowerBarShape == "ORB" and player.detachedPowerOrbSize == nil then player.detachedPowerOrbSize = 54 end
            ApplyDetachedPowerSource()
            self.refresh()
        end } }, Page.RowOptions).cpPowerShape
    AddTooltip(self.cpPowerShape, "Independent Powerbar Shape",
        "Changes only the detached Player Powerbar. Class Resource shape on the left changes only Class Resources.")
    self:Add("detachedPlayer", self.cpPowerShape)
    MoveWidget(self.cpPowerShape, layout, twoColumns and rightX or 32, twoColumns and -154 or -254, controlW, "LEFT")
    PlaceColumn(layout, 32, twoColumns and -220 or -308, 54, controlW, "LEFT", self.dpb.anchor, self.dpb.sync, mode.mode, self.dpb.width, self.dpb.orbSize,
        self.dpb.height)
    PlaceColumn(layout, rightX, twoColumns and -220 or -694, 54, controlW, "LEFT", self.dpb.x, self.dpb.y, self.dpb.layer)
    self:Add("detachedPlayer", smooth)
end

function Page:BuildDetachedPowerText()
    local text, controlW, rightX, twoColumns, cardW = self:BarArea("classpower_detached_power_text", "Text", self.width < 680 and 1020 or 700)
    local powerTextCard = Card(text, "Power Text", nil, 14, -38, cardW, twoColumns and 620 or 962)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(powerTextCard, {
            title = "Player Power Text Settings",
            historyLabel = "Player power text color",
            historySource = "menu:class-power-player-power-text-color",
            textSettings = {
                scope = "player",
                unit = "player",
                kind = "power",
            },
        })
    end
    local textStateRefresh = self:WithRefresh(ApplyDetachedPowerText)
    self.dpbText = self:Controls(text, Player, ApplyDetachedPowerText, "detached_power.text", {
        { "flowToggle", "onBar", false, { "Power text on bar" }, field = "detachedPowerBarTextOnBar", policy = "detachedTextOnBar",
            apply = textStateRefresh, group = "detachedPlayer" },
        { "dropdown", "preset", nil, { "Power text", DETACHED_POWER_TEXT_PRESET_VALUES, 300 }, policy = "detachedTextPreset", group = "detachedPlayer" },
        { "dropdown", "right", "CURPERCENT", { "Right slot", DETACHED_POWER_SLOT_VALUES, 300 }, field = "powerTextRight", apply = textStateRefresh,
            group = "detachedText" },
        { "dropdown", "left", "NONE", { "Left slot", DETACHED_POWER_SLOT_VALUES, 300 }, field = "powerTextLeft", apply = textStateRefresh,
            group = "detachedText" },
        { "dropdown", "center", "NONE", { "Center slot", DETACHED_POWER_SLOT_VALUES, 300 }, field = "powerTextCenter", apply = textStateRefresh,
            group = "detachedText" },
        { "dropdown", "sep", "", { "Delimiter", DETACHED_POWER_SEPARATORS, 180 }, field = "powerTextSeparator", group = "detachedText" },
        { "slider", "size", 14, { "Power text size", 6, 48, 1, 300 }, field = "powerFontSize", group = "detachedText" },
        { "slider", "x", -4, { "Text X", -300, 300, 1, 300 }, field = "powerOffsetX", group = "detachedText" },
        { "slider", "y", 4, { "Text Y", -300, 300, 1, 300 }, field = "powerOffsetY", group = "detachedText" },
        { "slider", "layer", 2, { "Player Power text layer", 0, 30, 1, 300 }, field = "powerTextLayer", group = "detachedText" },
    })
    self.dpbHide = {
        self:SourceToggle(text, "Hide right % sign", Player, "powerTextRightHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
        self:SourceToggle(text, "Hide left % sign", Player, "powerTextLeftHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
        self:SourceToggle(text, "Hide center % sign", Player, "powerTextCenterHidePercentSymbol", ApplyDetachedPowerText, "detached_power.text"),
    }
    local fontOutline = Schema.Build(self.ctx, text, { { "segment", "outline", nil, { "Player text outline", DETACHED_POWER_TEXT_OUTLINE_VALUES, controlW },
        meta = Meta("detached_power.text.outline", "setting"), get = function()
        local globalPage = M.GlobalPage
        if globalPage and globalPage.FontOutlineGetFor then
            return globalPage.FontOutlineGetFor("player")
        end
        return "OUTLINE"
    end, customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(value)
        local globalPage = M.GlobalPage
        if globalPage and globalPage.FontOutlineSetFor then
            globalPage.FontOutlineSetFor("player", value, "MSUF2_DETACHED_POWER_TEXT_OUTLINE")
        end
        self.refresh()
    end } }, Page.RowOptions).outline
    RegisterSegment(fontOutline, "detached_power.text.outline", DETACHED_POWER_TEXT_OUTLINE_VALUES, "setting")
    M.classPowerDetachedPowerTextSlot = M.classPowerDetachedPowerTextSlot or "center"
    local slot = Schema.Build(self.ctx, text, { { "segment", "slot", nil, { "Slot", TEXT_SLOT_VALUES, controlW },
        meta = Meta("detached_power.text.slot_selector", "ephemeral"), get = CurrentDetachedTextSlot,
            customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
        M.classPowerDetachedPowerTextSlot = value or "center"
        if M.RequestRefresh then M.RequestRefresh(self.ctx, "classpower-detached-power-text-slot") elseif M.Refresh then M.Refresh(self.ctx) end
    end } }, Page.RowOptions).slot
    RegisterSegment(slot, "detached_power.text.slot_selector", TEXT_SLOT_VALUES, "ephemeral")
    local offsets = {}
    for index, axis in ipairs({ "X", "Y" }) do
        local slider = Schema.Build(self.ctx, text, { { "slider", "slider", 0, { "Slot " .. axis, -300, 300, 1, 300 },
            workspace = "classpower", meta = Meta("detached_power.text.slot_offset." .. axis:lower(), "setting", { step = 1, roundStep = true }),
            get = function()
                local x, y = DetachedTextOffsetKeys()
                return tonumber(Player()[index == 1 and x or y]) or 0
            end,
            customSetReason = "Resolves the currently selected record or text slot at input time.",
            companionWrites = { "player.hpPowerTextOverride" },
            set = function(value)
                local x, y = DetachedTextOffsetKeys()
                SetPlayerTextValue(index == 1 and x or y, value, ApplyDetachedPowerText)
            end } }, Page.RowOptions).slider
        offsets[index] = slider
    end
    AddTooltip(self.dpbText.preset, "Power Text", "Simple presets for Player power text while detached power is managed by Class Resources. Custom Slots "
        .. "means the existing slot layout is kept until you choose a preset.")
    AddTooltip(self.dpbText.onBar, "Power Text On Bar",
        "Places Player power text on the detached power bar. When off, the same Player power text remains positioned by the normal text layout.")
    AddTooltip(self.dpbText.x, "Text X", "Moves all detached Player power text slots together. Slot X/Y controls below add per-slot offsets.")
    AddTooltip(self.dpbText.layer, "Player Power Text Layer",
        "Orders only the normal Player Power text. The visible Essence count and Ebon Might time belong to Class Resource text.")
    AddTooltip(fontOutline, "Player Text Outline",
        "Sets the Player font scope used by detached Power text. Player Name and HP text share this outline setting.")
    PlaceColumn(text, 32, -104, 54, controlW, "LEFT", self.dpbText.onBar, self.dpbText.preset, self.dpbText.right)
    for i, control in ipairs({ self.dpbHide[1], self.dpbText.left, self.dpbHide[2], self.dpbText.center, self.dpbHide[3], self.dpbText.sep }) do
        MoveWidget(control, text, 32, ({ -264, -298, -350, -384, -436, -470 })[i], controlW, "LEFT")
    end
    PlaceColumn(text, rightX, twoColumns and -154 or -558, 54, controlW, "LEFT", self.dpbText.size, fontOutline, self.dpbText.x, self.dpbText.y,
        self.dpbText.layer, slot, offsets[1], offsets[2])
    self:Add("detachedText", fontOutline, unpack(self.dpbHide))
    self:Add("detachedSlot", slot, offsets[1], offsets[2])
end

function Page:BuildDetachedPowerTextures()
    local textures, controlW, _, _, cardW = self:BarArea("classpower_detached_power_textures", "Appearance", 240)
    -- Power art is owned by the Bars page and the Player unit page (detached or
    -- not); this tab keeps only the shape edge that Class Resources still owns.
    local powerTexturesCard = Card(textures, "Shape Outline", "Power textures live on the Bars page.", 14, -38, cardW, 160)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(powerTexturesCard, function()
            local refs = { "power.current" }
            local db = M.EnsureDB()
            local general = db and db.general or {}
            local bars = Bars()
            if not (general.powerBarBgMatchBarColor == true or bars.powerBarBgMatchBarColor == true) then
                refs[#refs + 1] = "bar.power_background"
            end
            return refs
        end, {
            title = "Detached Player Power Colors",
            note = "The resource color follows Player power. A matched background is derived from Health instead.",
            historySource = "menu:class-power-detached-power-colors",
            context = function() return { unit = "player" } end,
        })
    end
    local texture = self:Controls(textures, Bars, ApplyDetachedPowerBar, "detached_power.textures", {
        { "slider", "outline", 1, { "Power bar outline", 0, 8, 1, 300 }, field = "detachedPowerBarOutline", policy = "playerPowerOutline",
            apply = ApplyDetachedPowerBarOutline, group = "detached" },
    })
    self.dpbTextures = texture
    AddTooltip(texture.outline, "Power Bar Outline",
        "Edge strength of every detached Player power shape, including Bar, Round, Crystal and Orb. 0 disables only that edge.")
    PlaceColumn(textures, 32, -104, 54, controlW, "LEFT", texture.outline)
end

function Page:BuildPlayerHP()
    local layout, controlW, rightX, twoColumns, cardW = self:BarArea("classpower_player_hp", "Layout", self.width < 680 and 840 or 600)
    Card(layout, "Visibility & Position", nil, 14, -38, cardW, twoColumns and 500 or 760)
    local applyRefresh = self:WithRefresh(ApplyPlayerHPBar)
    self.hpUse = Schema.Build(self.ctx, layout, { { "sectionSwitch", "hpUse", nil, { "Extra Health Bar" },
        workspace = "classpower", meta = Meta("player_hp.enabled"),
        get = function() return BoolValue(Bars(), "playerHPBarEnabled", false) end,
        write = { call = SetValue, source = Bars, args = { applyRefresh } } --[[schema setter: AdvancedClassPower.11]] } }, Page.RowOptions).hpUse
    self.hp = self:Controls(layout, Bars, ApplyPlayerHPBar, "player_hp.layout", {
        { "dropdown", "anchor", "CLASS_TOP", { "Anchor", PLAYER_HP_ANCHOR_VALUES, 300 }, field = "playerHPBarAnchor" },
        { "dropdown", "widthMode", "class", { "Width mode", PLAYER_HP_WIDTH_VALUES, 300 }, field = "playerHPBarWidthMode", apply = applyRefresh },
        { "slider", "manualWidth", 0, { "Custom width", 20, 1200, 1, 300 }, field = "playerHPBarWidth" },
        { "dropdown", "shape", "BAR", { "HP shape", PLAYER_HP_SHAPE_VALUES, 300 }, field = "playerHPBarShape", apply = applyRefresh },
        { "slider", "orbSize", 54, { "Orb size", 20, 160, 1, 300 }, field = "playerHPBarOrbSize" },
        { "slider", "height", 6, { "Height", 2, 80, 1, 300 }, field = "playerHPBarHeight" },
        { "flowToggle", "smooth", false, { "Smooth fill" }, field = "playerHPBarSmoothFill" },
        { "slider", "gap", 2, { "Gap", 0, 60, 1, 300 }, field = "playerHPBarGap" },
        { "slider", "x", 0, { "Offset X", -1000, 1000, 1, 300 }, field = "playerHPBarOffsetX" },
        { "slider", "y", 0, { "Offset Y", -1000, 1000, 1, 300 }, field = "playerHPBarOffsetY" },
        { "slider", "layer", 7, { "Frame layer", 0, 30, 1, 300 }, field = "playerHPBarFrameLevelOffset" },
    })
    PlaceColumn(layout, 32, -154, 54, controlW, "LEFT", self.hp.anchor, self.hp.widthMode, self.hp.manualWidth, self.hp.shape, self.hp.orbSize,
        self.hp.height, self.hp.smooth)
    PlaceColumn(layout, rightX, twoColumns and -154 or -540, 54, controlW, "LEFT", self.hp.gap, self.hp.x, self.hp.y, self.hp.layer)
    self:AddNamed("hp", self.hp, "anchor widthMode shape height smooth gap x y layer")
    self:AddNamed("hpManual", self.hp, "manualWidth")
    self:AddNamed("hpOrb", self.hp, "orbSize")
    AddTooltip(self.hpUse, "Second Player HP Bar",
        "Renders a second native Player health bar. The normal Player unitframe HP bar is untouched, so you can show HP twice.")
    AddTooltip(self.hp.anchor, "Anchor",
        "Power anchors use the Player power bar when it is visible; otherwise the HP bar falls back to the Class Resource anchor.")
    AddTooltip(self.hp.widthMode, "Width Mode",
        "Class Resource and Player Power follow existing frames. Custom uses the slider below. Width is resolved only during layout refresh.")
    AddTooltip(self.hp.shape, "HP Shape",
        "Bar keeps the normal statusbar. Follow Player Power mirrors the independent detached Player power shape. Orb uses a single vertical fill.")
    AddTooltip(self.hp.orbSize, "Orb Size",
        "Used only when this HP bar is explicitly set to Orb. Follow Player Power inherits the Player power orb size instead.")
    AddTooltip(self.hp.smooth, "Smooth Fill", "Optional interpolation for this second HP bar. Off keeps direct native SetValue updates.")
end

function Page:BuildPlayerHPTextures()
    local textures, controlW, _, _, cardW = self:BarArea("classpower_player_hp_textures", "Appearance", 440)
    local hpTexturesCard = Card(textures, "HP Textures", nil, 14, -38, cardW, 346)
    if W.AttachContextColorReferences then
        local function PlayerHPColorMode()
            local mode = tostring(Bars().playerHPBarColorMode or "GLOBAL"):upper()
            if mode == "CLASS" or mode == "DARK" or mode == "GRADIENT" then return mode end
            return "GLOBAL"
        end
        W.AttachContextColorReferences(hpTexturesCard, function()
            return PlayerHPColorMode() == "DARK" and {} or { "health.current" }
        end, {
            title = "Extra Health Bar Colors",
            note = "The foreground follows the selected HP color mode. Dark Mode uses the shared dark-tone control.",
            historySource = "menu:class-power-player-hp-colors",
            context = function()
                return { unit = "player", unitKey = "player", healthMode = PlayerHPColorMode() }
            end,
        })
    end
    local function ApplyPlayerHPColorMode()
        ApplyPlayerHPBar()
        if M.Refresh then M.Refresh(self.ctx) end
    end
    local texture = self:Controls(textures, Bars, ApplyPlayerHPBar, "player_hp.textures", {
        { "dropdown", "color", "GLOBAL", { "HP color", PLAYER_HP_COLOR_VALUES, 300 }, field = "playerHPBarColorMode", apply = ApplyPlayerHPColorMode },
        { "dropdown", "fg", "", { "Foreground texture", function() return TextureValues("Use global bar texture") end, 300 },
            field = "playerHPBarTexture", apply = ApplyPlayerHPTextures },
        { "dropdown", "bg", "", { "Background texture", function() return TextureValues("Use foreground texture") end, 300 },
            field = "playerHPBarBgTexture", apply = ApplyPlayerHPTextures },
        { "slider", "bgAlpha", .35, { "BG opacity", 0, 100, 1, 300 }, field = "playerHPBarBgAlpha", policy = "alpha", apply = ApplyPlayerHPBar },
        { "slider", "outline", 1, { "Outline", 0, 8, 1, 300 }, field = "playerHPBarOutline" },
    })
    PlaceColumn(textures, 32, -104, 54, controlW, "LEFT", texture.color, texture.fg, texture.bg, texture.bgAlpha, texture.outline)
    self:AddNamed("hp", texture, "color fg bg bgAlpha outline")
    self:AddNamed("hpTexture", texture, "fg bg")
    AddTooltip(texture.color, "HP Color", "Global follows the normal MSUF health color mode. Class Color forces your class color. Dark Mode forces the "
        .. "configured dark bar color. HP Gradient colors only this second HP bar by current health.")
    AddTooltip(texture.bg, "Background Texture",
        "Visible behind the filled HP amount. At 100% HP the fill covers the background; Outline 0 does not disable this texture.")
    AddTooltip(texture.outline, "HP Outline",
        "Controls only the second HP bar outline. Bar uses four outside border edges; shapes use their fixed edge texture. 0 disables only the outline.")
end

function Page:BuildPlayerHPText()
    local text, controlW, rightX, twoColumns, cardW = self:BarArea("classpower_player_hp_text", "Text", self.width < 680 and 800 or 620)
    local hpTextCard = Card(text, "HP Text", nil, 14, -38, cardW, twoColumns and 520 or 722)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(hpTextCard, {
            title = "Extra Health Text Settings",
            historyLabel = "Extra health text color",
            historySource = "menu:class-power-player-hp-text-color",
            textSettings = {
                scope = "shared",
                modeScope = "player",
                unit = "player",
                kind = "hp",
                colorReferences = function()
                    if Bars().playerHPBarUsePlayerText == true then return nil end
                    return {}
                end,
                capabilities = function()
                    local mirror = Bars().playerHPBarUsePlayerText == true
                    return {
                        shadow = false,
                        opacity = false,
                        baseline = false,
                        shadowAlpha = false,
                        shadowDistance = false,
                        colorMode = mirror,
                        colors = mirror,
                    }
                end,
                subtitle = function()
                    if Bars().playerHPBarUsePlayerText == true then
                        return "Font face follows Shared; text and color mode mirror Player HP."
                    end
                    return "Local HP text uses shared face settings and a fixed white color."
                end,
            },
        })
    end
    local textRefresh = self:WithRefresh(ApplyPlayerHPText)
    self.hpTextEnable = SwitchAt(self.ctx, text, "Show HP text", 32, -104, controlW, Bars, "playerHPBarTextEnabled", true, textRefresh,
        Meta("player_hp.text.enabled"))
    local shared = SwitchAt(self.ctx, text, "Use Player HP text", 32, -136, controlW, Bars, "playerHPBarUsePlayerText", true, textRefresh,
        Meta("player_hp.text.use_player_text"))
    self.hpText = self:Controls(text, Bars, ApplyPlayerHPText, "player_hp.text", {
        { "dropdown", "right", "CURPERCENT", { "Right slot", PLAYER_HP_TEXT_VALUES, 300 }, field = "playerHPBarTextRight", apply = textRefresh },
        { "dropdown", "left", "NONE", { "Left slot", PLAYER_HP_TEXT_VALUES, 300 }, field = "playerHPBarTextLeft", apply = textRefresh },
        { "dropdown", "center", "NONE", { "Center slot", PLAYER_HP_TEXT_VALUES, 300 }, field = "playerHPBarTextCenter", apply = textRefresh },
        { "dropdown", "sep", "", { "Delimiter", DETACHED_POWER_SEPARATORS, 180 }, field = "playerHPBarTextSeparator" },
        { "flowToggle", "reverse", false, { "Reverse order" }, field = "playerHPBarTextReverse" },
        { "slider", "size", 14, { "Text size", 6, 48, 1, 300 }, field = "playerHPBarTextSize" },
        { "slider", "x", 0, { "Text X", -300, 300, 1, 300 }, field = "playerHPBarTextOffsetX" },
        { "slider", "y", 0, { "Text Y", -300, 300, 1, 300 }, field = "playerHPBarTextOffsetY" },
    })
    self.hpHide = {
        self:SourceToggle(text, "Hide right % sign", Bars, "playerHPBarTextRightHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
        self:SourceToggle(text, "Hide left % sign", Bars, "playerHPBarTextLeftHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
        self:SourceToggle(text, "Hide center % sign", Bars, "playerHPBarTextCenterHidePercentSymbol", ApplyPlayerHPText, "player_hp.text"),
    }
    for i, control in ipairs({ self.hpText.right, self.hpHide[1], self.hpText.left, self.hpHide[2], self.hpText.center, self.hpHide[3], self.hpText.sep }) do
        MoveWidget(control, text, 32, ({ -188, -240, -274, -326, -360, -412, -446 })[i], controlW, "LEFT")
    end
    PlaceColumn(text, rightX, twoColumns and -188 or -534, 54, controlW, "LEFT", self.hpText.reverse, self.hpText.size, self.hpText.x, self.hpText.y)
    self:Add("hp", self.hpTextEnable)
    self:Add("hpText", shared)
    self:AddNamed("hpCustomText", self.hpText, "right left center sep reverse size")
    self:Add("hpCustomText", unpack(self.hpHide))
    self:AddNamed("hpTextPosition", self.hpText, "x y")
    AddTooltip(self.hpTextEnable, "HP Text", "Controls only this second HP bar. The normal Player unitframe HP text remains separate.")
    AddTooltip(shared, "Use Player HP Text",
        "Uses Player HP text settings and copies already-rendered Player HP text when it is current. Local Text X/Y still belong to this bar.")
end

function Page:BuildAlternativeMana()
    local section = self:Section("classpower_alt_mana", "Layout", 402, false)
    local cardW = min(620, (section._msuf2Width or self.width) - 28)
    local controlW = min(360, cardW - 64)
    local manaCard = Card(section, "Visibility & Size", "For specializations that use mana alongside another resource.", 14, -38, cardW, 346)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(manaCard, { "class_power.alt_mana" }, {
            title = "Alternative Mana Color",
            historySource = "menu:class-power-alternative-mana-color",
        })
    end
    local applyRefresh = self:WithRefresh(ApplyClassPower)
    self.altToggle = Schema.Build(self.ctx, section, { { "sectionSwitch", "altToggle", nil, { "Show mana bar (dual resource)" },
        workspace = "classpower", meta = Meta("alternative_mana.enabled"),
        get = function() return BoolValue(Bars(), "showAltMana", false) end,
        write = { call = SetValue, source = Bars, args = { applyRefresh } } --[[schema setter: AdvancedClassPower.12]] } }, Page.RowOptions).altToggle
    local fields = self:Controls(section, Bars, ApplyClassPower, "alternative_mana.layout", {
        { "dropdown", "widthMode", "player", { "Width mode", ALT_MANA_WIDTH_VALUES, 300 }, field = "altManaWidthMode", apply = applyRefresh },
        { "slider", "width", 0, { "Custom width", 20, 1200, 1, 300 }, field = "altManaWidth" },
        { "slider", "height", 4, { "Height", 2, 30, 1, 300 }, field = "altManaHeight" },
        { "slider", "x", 0, { "X offset", -1000, 1000, 1, 300 }, field = "altManaOffsetX" },
        { "slider", "y", -2, { "Y offset", -50, 50, 1, 300 }, field = "altManaOffsetY" },
    })
    PlaceColumn(section, 32, -104, 54, controlW, "LEFT", fields.widthMode, fields.width, fields.height, fields.x, fields.y)
    self.altManaWidth = fields.width
    self:AddNamed("altMana", fields, "widthMode width height x y")
end
function Page:BuildAlternativeManaBehavior()
    local section = self:Section("classpower_alt_mana_behavior", "Behavior", 96, false)
    local smooth = SwitchAt(self.ctx, section, "Smooth fill", 32, -40, 280, Bars, "altManaSmoothFill", false,
        ApplyClassPowerSmoothing, Meta("alternative_mana.smooth_fill"))
    self:Add("altMana", smooth)
end

function Page:RefreshControlState()
    local bars, db = Bars(), M.EnsureDB()
    local cpOn = BoolValue(bars, "showClassPower", true)
    SetControlsEnabled(self.groups.cp, cpOn)
    if self.cp.syncPlayerPowerOOC then
        SetControlEnabled(self.cp.syncPlayerPowerOOC, cpOn and BoolValue(bars, "classPowerHideOOC", false))
    end
    if self.ironfurHashes then SetControlEnabled(self.ironfurHashes, cpOn and BoolValue(bars, "showGuardianIronfur", false)) end
    SetControlEnabled(self.cp.width, cpOn and (bars.classPowerWidthMode or "player") == "custom")
    local classBar = NormalizeClassPowerShape(bars.classPowerShape) == "BAR"
    if self.cp.height and self.cp.height._msuf2Title then self.cp.height._msuf2Title:SetText(classBar and "Height" or "Pip size") end
    SetControlEnabled(self.cp.separator, cpOn and classBar)
    SetControlEnabled(self.cp.outline, cpOn and classBar)
    SetControlEnabled(self.cpAlign, cpOn and not classBar)
    -- Ebon Might owns a native duration text even when the optional aggregate
    -- resource text is disabled, so its shared text styling/layer stays usable.
    SetControlsEnabled(self.groups.cpText, cpOn)
    local anyDetached = false
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }) do
        if db[key] and db[key].powerBarDetached then
            anyDetached = true
            break
        end
    end
    local playerDetached = db.player and db.player.powerBarDetached == true
    SetControlsEnabled(self.groups.detached, anyDetached)
    SetControlsEnabled(self.groups.detachedPlayer, playerDetached)
    SetControlEnabled(self.dpbUse, true)
    -- Lazy sections leave their control tables nil until first expand.
    local playerShape = NormalizeDetachedPowerShape(db.player and db.player.detachedPowerBarShape)
    if self.dpb then
        SetControlEnabled(self.dpb.orbSize, playerDetached and playerShape == "ORB")
        SetControlEnabled(self.dpb.height, playerDetached and playerShape ~= "ORB")
        -- Orb derives both axes from its own size, and a Cooldown Viewer width
        -- mode names the source frame instead, so a manual width only decides
        -- anything for a non-Orb bar left on "Manual".
        SetControlEnabled(self.dpb.width, playerDetached and playerShape ~= "ORB"
            and tostring(bars.detachedPowerBarWidthMode or "manual"):lower() == "manual")
    end
    if self.dpbTextures then
        SetControlEnabled(self.dpbTextures.outline, playerDetached)
    end
    local playerTextOn = db.player and PlayerPowerTextShown(db.player)
    if self.dpbText then
        SetControlEnabled(self.dpbText.onBar, playerDetached)
        SetControlEnabled(self.dpbText.size, playerDetached and playerTextOn)
    end
    SetControlsEnabled(self.groups.detachedText, playerDetached and playerTextOn)
    if self.dpbHide then
        for i, mode in ipairs({ (db.player and (db.player.powerTextRight or db.player.powerTextMode)) or "CURPERCENT", db.player and db.player.powerTextLeft
            or "NONE", db.player and db.player.powerTextCenter or "NONE" }) do
            SetControlEnabled(self.dpbHide[i], playerDetached and playerTextOn and HasPercent(mode))
        end
    end
    SetControlsEnabled(self.groups.detachedSlot, playerDetached and playerTextOn)
    local hpOn, hpShape = BoolValue(bars, "playerHPBarEnabled", false), ResolvePlayerHPShape(bars, db)
    local hpOrb = hpShape == "ORB"
    SetControlsEnabled(self.groups.hp, hpOn)
    SetControlsEnabled(self.groups.hpManual, hpOn and not hpOrb and (bars.playerHPBarWidthMode or "class") == "custom")
    SetControlsEnabled(self.groups.hpOrb, hpOn and NormalizePlayerHPShape(bars.playerHPBarShape) == "ORB")
    SetControlsEnabled(self.groups.hpTexture, hpOn and hpShape == "BAR")
    if self.hp then SetControlEnabled(self.hp.height, hpOn and not hpOrb) end
    local hpTextOn = hpOn and BoolValue(bars, "playerHPBarTextEnabled", true)
    local hpCustom = hpTextOn and not BoolValue(bars, "playerHPBarUsePlayerText", true)
    SetControlsEnabled(self.groups.hpText, hpTextOn)
    SetControlsEnabled(self.groups.hpCustomText, hpCustom)
    if self.hpHide then
        for i, mode in ipairs({ bars.playerHPBarTextRight or "CURPERCENT", bars.playerHPBarTextLeft or "NONE", bars.playerHPBarTextCenter or "NONE" }) do
            SetControlEnabled(self.hpHide[i], hpCustom and HasPercent(mode))
        end
    end
    SetControlsEnabled(self.groups.hpTextPosition, hpTextOn)
    SetControlEnabled(self.hpUse, true)
    local altManaOn = BoolValue(bars, "showAltMana", false)
    SetControlsEnabled(self.groups.altMana, altManaOn)
    SetControlEnabled(self.altManaWidth, altManaOn and (bars.altManaWidthMode or "player") == "custom")
    SetControlEnabled(self.altToggle, true)
    SetControlEnabled(self.cpEnable, true)
    -- Hover reasons for the three master switches. Lazy sections add controls
    -- to these groups later, so each refresh re-points them (a field write).
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local reasons = self._msuf2DisabledReasons
        if not reasons then
            local cpReason = W.TurnOnReason("Class Resource", function() return BoolValue(Bars(), "showClassPower", true) end)
            local oocReason = W.TurnOnReason("Hide out of combat", function() return BoolValue(Bars(), "classPowerHideOOC", false) end)
            reasons = {
                cp = cpReason,
                hp = W.TurnOnReason("Extra Health Bar", function() return BoolValue(Bars(), "playerHPBarEnabled", false) end),
                altMana = W.TurnOnReason("Show mana bar (dual resource)", function() return BoolValue(Bars(), "showAltMana", false) end),
                syncPower = function(control) return cpReason(control) or oocReason(control) end,
            }
            self._msuf2DisabledReasons = reasons
        end
        W.SetControlsDisabledReason(self.groups.cp, reasons.cp)
        if self.cp.syncPlayerPowerOOC and W.SetControlDisabledReason then
            W.SetControlDisabledReason(self.cp.syncPlayerPowerOOC, reasons.syncPower)
        end
        W.SetControlsDisabledReason(self.groups.hp, reasons.hp)
        W.SetControlsDisabledReason(self.groups.altMana, reasons.altMana)
    end
end

-- Collapsed sections build only their shell on the visible cold path; content
-- builds on first expand through the shared lazy-section registry. Hidden
-- search-index builds and persisted-open sections still build synchronously
-- inside BuildSectionLazy, so search, Search coverage, and reopened
-- sections keep seeing the full page.
function Page:LazySection(id, title, height, method, prepareShell)
    local UnitPage = M.UnitPage
    if UnitPage and UnitPage.BuildSectionLazy then
        local page = self
        UnitPage.BuildSectionLazy(self.ctx, self.b, "player", {
            id = id,
            title = title,
            height = height,
            defaultOpen = false,
            prepareShell = function(...)
                local refresh = prepareShell and prepareShell(...)
                local section = select(2, ...)
                if section and section._msuf2CollapsibleEntry then Schema.Section(section, "classpower") end
                return refresh
            end,
            build = function(_, proxyBuilder)
                local outerBuilder = page.b
                page.b = proxyBuilder
                method(page)
                page.b = outerBuilder

                -- Newly built controls need their enabled/disabled state; the
                -- proxy is a safe no-op while the page itself is still building.
                page.refresh()
            end,
        })
        return
    end
    method(self)
end

function Page:Build()
    self:BuildHeader()
    local preview = BuildInlineClassPowerPreview(self.ctx, self.b)
    Schema.Custom(preview, { id = "menu2.classpower.preview", kind = "preview",
        scope = "classpower", applyDomain = "preview", owner = preview })
    self:BuildClassLayout()
    self:LazySection("classpower_behavior", "Behavior", 282, Page.BuildClassBehavior)
    self:LazySection("classpower_visuals", "Appearance", 482, Page.BuildClassStyle)
    self:LazySection("classpower_visibility", "Auto-Hide", 280, Page.BuildClassVisibility)
    self:LazySection("classpower_detached_power", "Layout", function() return self.width < 680 and 932 or 600 end, Page.BuildDetachedPower)
    self:LazySection("classpower_detached_power_textures", "Appearance", 240, Page.BuildDetachedPowerTextures)
    self:LazySection("classpower_detached_power_text", "Text", function() return self.width < 680 and 1020 or 700 end, Page.BuildDetachedPowerText)
    self:LazySection("classpower_player_hp", "Layout", function() return self.width < 680 and 840 or 600 end, Page.BuildPlayerHP)
    self:LazySection("classpower_player_hp_textures", "Appearance", 440, Page.BuildPlayerHPTextures)
    self:LazySection("classpower_player_hp_text", "Text", function() return self.width < 680 and 800 or 620 end, Page.BuildPlayerHPText)
    self:LazySection("classpower_alt_mana", "Layout", 402, Page.BuildAlternativeMana)
    self:LazySection("classpower_alt_mana_behavior", "Behavior", 96, Page.BuildAlternativeManaBehavior)
    -- section id, meta path, saved-key prefix, control group, apply, combat-only rules
    for _, spec in ipairs({
        { "classpower_detached_power_visibility", "detached_power.visibility", "playerPower", "detachedPlayer", ApplyDetachedPowerBar },
        { "classpower_player_hp_visibility", "player_hp.visibility", "playerHPBar", "hp", ApplyPlayerHPBar },
        { "classpower_alt_mana_visibility", "alternative_mana.visibility", "altMana", "altMana", ApplyClassPower },
        { "classpower_resource_visibility", "resource_extras.visibility", "resourceExtra", nil, ApplyClassPower, true },
    }) do
        self:LazySection(spec[1], "Auto-Hide", spec[6] and 184 or 248, function(page)
            page:BuildResourceVisibility(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6])
        end)
    end
    if M.ResourceExtrasPage then
        M.ResourceExtrasPage.BuildSections(self, Bars, ApplyClassPower)
        self:LazySection("classpower_resource_marks", "Resource marks and thresholds", function() return M.ResourceExtrasPage.MarksHeight(self) end,
            function(page) M.ResourceExtrasPage.BuildMarks(page, Bars, ApplyClassPower) end)
    end
    -- All callbacks share one late-bound state refresh instead of capturing every control.
    self.refresh = self.refresh(function() self:RefreshControlState() end)
    M.RefreshClassPowerDetachedState = self.refresh
    M.TrackRefresh(self.ctx, self.refresh)
    self.workspace:Select(self.workspace.selected, false, true)
    MaybeOfferQuickSetup()
    self.ctx:SetContentHeight(math.abs(self.b.y) + 42)
end

local function BuildClassPower(ctx) Page.New(ctx):Build() end
M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 23 })
