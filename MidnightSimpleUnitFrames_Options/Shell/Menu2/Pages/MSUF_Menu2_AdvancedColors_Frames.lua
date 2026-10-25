-- AdvancedColors: Frames responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AdvancedColorsParts
local ApiCall = Parts.ApiCall
local ApiColorAt = Parts.ApiColorAt
local ApiRGB = Parts.ApiRGB
local ApiSetRGB = Parts.ApiSetRGB
local ApiValue = Parts.ApiValue
local ApplyBossTargetHighlightColor = Parts.ApplyBossTargetHighlightColor
local ApplyCastbarColors = Parts.ApplyCastbarColors
local ApplyColors = Parts.ApplyColors
local ApplyGameplayColors = Parts.ApplyGameplayColors
local ApplyGlobalOutlineColor = Parts.ApplyGlobalOutlineColor
local ApplyUnitframeColorWithReload = Parts.ApplyUnitframeColorWithReload
local Build = Parts.Build
local BuildApiColorSpecs = Parts.BuildApiColorSpecs
local BuildApiOrGeneralColorSpecs = Parts.BuildApiOrGeneralColorSpecs
local BuildTableColorSpecs = Parts.BuildTableColorSpecs
local ButtonAt = Parts.ButtonAt
local COLOR_DATA = Parts.COLOR_DATA
local ClearRGB = Parts.ClearRGB
local ClearRGBAs = Parts.ClearRGBAs
local ClearRGBs = Parts.ClearRGBs
local ColorAPI = Parts.ColorAPI
local ColorValueAt = Parts.ColorValueAt
local ColorsSection = Parts.ColorsSection
local CurrentApplyService = Parts.CurrentApplyService
local CurrentBarsScope = Parts.CurrentBarsScope
local DB = Parts.DB
local FILE = Parts.FILE
local G = Parts.G
local GP = Parts.GP
local Gameplay = Parts.Gameplay
local GeneralColorAt = Parts.GeneralColorAt
local GeneralRGB = Parts.GeneralRGB
local GeneralRGBAlias = Parts.GeneralRGBAlias
local GradientScopeGet = Parts.GradientScopeGet
local GradientScopeSet = Parts.GradientScopeSet
local HighlightRGB = Parts.HighlightRGB
local LabelAt = Parts.LabelAt
local Meta = Parts.Meta
local MoveWidget = Parts.MoveWidget
local NormalizeScopeKey = Parts.NormalizeScopeKey
local Opt = Parts.Opt
local Owned = Parts.Owned
local RegisterControl = Parts.RegisterControl
local RequestGeneral = Parts.RequestGeneral
local ResetNPCColors = Parts.ResetNPCColors
local ResetUnitframeColors = Parts.ResetUnitframeColors
local Schema = Parts.Schema
local SchemaRows = Parts.SchemaRows
local ScopeHasOverride = Parts.ScopeHasOverride
local SetControlEnabled = Parts.SetControlEnabled
local SetControlsEnabled = Parts.SetControlsEnabled
local SetGeneralRGB = Parts.SetGeneralRGB
local SetGeneralRGBAlias = Parts.SetGeneralRGBAlias
local SetHighlightRGB = Parts.SetHighlightRGB
local SetTableRGB = Parts.SetTableRGB
local SliderAt = Parts.SliderAt
local SwitchAt = Parts.SwitchAt
local T = Parts.T
local TableRGB = Parts.TableRGB
local TrText = Parts.TrText
local UnitColorRows = Parts.UnitColorRows
local ValueDropdownAt = Parts.ValueDropdownAt
local ValueSliderAt = Parts.ValueSliderAt
local ValueSwitchAt = Parts.ValueSwitchAt
local ValueTextPairs = Parts.ValueTextPairs
local ValueToggleAt = Parts.ValueToggleAt
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

local function ApplyScopedBarGradientColors(reason)
    local apply = CurrentApplyService()
    local scope = CurrentBarsScope()
    if apply and type(apply.RequestBarGradients) == "function" then
        return apply.RequestBarGradients(reason or "MSUF2_BAR_GRADIENT_COLORS", scope)
    end
    return RequestGeneral(reason or "MSUF2_BAR_GRADIENT_COLORS", {
        preview = true,
        applyAll = false,
        notify = false,
        barGradients = true,
        barsScope = scope,
    })
end


function Build.BarGradients(ctx, b)
    local values, sectionW = GP.SCOPE_VALUES or {}, ctx.width or 720
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, { width = sectionW })
    local scopeBottom = (scopeMetrics and scopeMetrics.bottomY) or -40
    local colorY = math.min(-104, scopeBottom - 54)
    local compact = sectionW < 560
    local resetY = compact and (colorY - 86) or (colorY - 44)
    local section = ColorsSection(b, "colors_bar_gradients", "Bar Gradient Colors", math.abs(resetY) + 54, true)
    local scopeSpec = { id = Meta("bar_gradient.scope.selector", "ephemeral").controlId,
        kind = "segment", scope = "colors", applyDomain = "selection", scopeOwner = true,
        setting = "general.hpPowerTextSelectedKey", get = CurrentBarsScope, values = values,
        write = { source = G, convert = NormalizeScopeKey,
            after = function()
                if M.RequestRefresh then M.RequestRefresh(ctx, "bar-gradient-color-scope")
                elseif M.Refresh then M.Refresh(ctx) end
            end
        } --[[schema setter: J5.Colors.Scope]] }
    scopeSpec.set = Schema.Setter(scopeSpec)
    local scopeBar = W.ScopeOverrideBar(ctx, section, {
        values = values, width = sectionW, getValue = CurrentBarsScope,
        setValue = scopeSpec.set,
        hasOverride = function(value) return value ~= "shared" and ScopeHasOverride(value, "hlOverride") end,
    })
    RegisterControl(scopeBar, Meta("bar_gradient.scope.selector", "ephemeral"), "Editing:", "segment", values)
    Schema.ScopeOwner(scopeBar, "colors", nil, "general.hpPowerTextSelectedKey")
    Schema.Custom(scopeBar, scopeSpec)
    local hint = W.Text(section, "Health and Power use separate gradient colors. Choosing a color creates a custom Bars override for the selected scope.",
        14, colorY + 28, sectionW - 28, T.colors.muted)
    hint:SetJustifyH("LEFT")
    local function GradientRGB(prefix)
        return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "G", 0)) or 0, tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
    end
    local function SetGradientRGB(prefix, r, g, bcol, reason)
        GradientScopeSet(prefix .. "R", r)
        GradientScopeSet(prefix .. "G", g)
        GradientScopeSet(prefix .. "B", bcol)
        ApplyScopedBarGradientColors(reason)
    end
    local function GradientRow(key, label, prefix, reason, path, position)
        return { "color", key, { 0, 0, 0 }, { label }, domain = "barGradients", position = position, path = path,
            get = function() return GradientRGB(prefix) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g,
                bcol) SetGradientRGB(prefix, r, g, bcol, reason) end }
    end
    SchemaRows(ctx, section, {
        GradientRow("health", "Health gradient color", "healthBarGradientColor", "MSUF2_HP_GRADIENT_COLOR",
            "bar_gradient.health.color", { 14, colorY, compact and 180 or 190, 52 }),
        GradientRow("power", "Power gradient color", "powerBarGradientColor", "MSUF2_POWER_GRADIENT_COLOR",
            "bar_gradient.power.color", { compact and 14 or math.max(360, floor(sectionW * 0.50)),
                compact and (colorY - 38) or colorY, compact and 180 or 190, 52 }),
    })
    Owned(ButtonAt(section, "Reset gradient colors", 14, resetY, 180, function()
        for _, prefix in ipairs({ "healthBarGradientColor", "powerBarGradientColor" }) do
            GradientScopeSet(prefix .. "R", 0)
            GradientScopeSet(prefix .. "G", 0)
            GradientScopeSet(prefix .. "B", 0)
        end
        ApplyScopedBarGradientColors("MSUF2_RESET_GRADIENT_COLORS")
    end, "bar_gradient.reset"), "barGradients")
end

function Build.Background(ctx, b)
    local background = ColorsSection(b, "colors_background", "Bar Background Tint", 332, false)
    LabelAt(background, "Fill and color mode affect only the health background; foreground health coloring stays independent.", 12, -8, 660,
        "GameFontHighlightSmall", T.colors.muted)
    LabelAt(background, "Texture comes from Bars; preview uses Player background opacity multiplied by tint opacity.", 12, -24, 660, "GameFontHighlightSmall",
        T.colors.muted)
    local refreshBackgroundPreview
    -- A mode setter of ColorsBackgroundMode (looked up when it runs) that repaints the preview afterwards.
    local function ThenRefresh(name)
        return function(value)
            M.ColorsBackgroundMode[name](value)
            if refreshBackgroundPreview then refreshBackgroundPreview() end
        end
    end
    ValueDropdownAt(ctx, background, "Background Fill", 12, -46,
        ValueTextPairs "full=Full bar|missing=Missing health only", 300,
        M.ColorsBackgroundMode.GetFill, ThenRefresh("SetFill"), Meta("background.fill_mode"))
    ValueDropdownAt(ctx, background, "Background Color", 340, -46,
        ValueTextPairs "custom=Custom tint|match_health=Match health bar|class=Class color|health_gradient=Health gradient", 320,
        M.ColorsBackgroundMode.GetColor, ThenRefresh("SetColor"), Meta("background.color_mode"))
    local previewWidth = max(300, min(648, (background._msuf2Width or ctx.width or 720) - 24))
    local previewPanel = T.Panel(background, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.92 }, T.colors.borderSoft)
    previewPanel:SetPoint("TOPLEFT", background, "TOPLEFT", 12, -104)
    previewPanel:SetSize(previewWidth, 66)
    local previewLabel = T.Font(previewPanel, "GameFontNormalSmall", "Preview", T.colors.muted)
    previewLabel:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -8)
    local previewMode = T.Font(previewPanel, "GameFontHighlightSmall", "", T.colors.muted)
    previewMode:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -8)
    previewMode:SetJustifyH("RIGHT")
    local previewTrack = T.Panel(previewPanel, nil, { 0.006, 0.012, 0.024, 1 }, T.colors.borderSoft)
    previewTrack:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -28)
    previewTrack:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -28)
    previewTrack:SetHeight(22)
    local previewState = { mode = previewMode, healthFraction = .62 }
    previewState.surface = M.PreviewHelpers.NewRuntimeUnitSurface(previewTrack, "player", { hp = .62 })

    refreshBackgroundPreview = function()
        if previewPanel.IsVisible and not previewPanel:IsVisible() then return false end
        return M.RefreshHealthBackgroundInlinePreview(previewState)
    end
    local function ApplyBackgroundColorPreview()
        ApplyColors()
        refreshBackgroundPreview()
    end
    Owned(ColorValueAt(ctx, background, "Bar background tint", 12, -188,
        function() return ApiRGB("GetClassBarBgColor", 0, 0, 0) end,
        function(r, g, c, a)
            local nextAlpha = type(a) == "number" and a or nil
            local ok = nextAlpha ~= nil and ApiCall("SetClassBarBgColor", r, g, c, nextAlpha)
                or ApiCall("SetClassBarBgColor", r, g, c)
            if not ok then
                SetGeneralRGB("classBarBg", r, g, c, nextAlpha)
                ApplyColors()
            end
            refreshBackgroundPreview()
        end,
        nil, nil, Meta("general.classBarBg"), { 0, 0, 0 }), "unitColors")
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -228,
        function() return G().darkBgCustomColor == true end,
        { write = { source = G, boolean = true, after = ApplyBackgroundColorPreview
        } --[[schema setter: J5.Colors.DarkBackground]] },
        Meta("background.dark_mode_custom_color"))
    Owned(ButtonAt(background, "Reset to black", 12, -274, 140, function()
        if not ApiCall("ResetClassBarBgColor") then
            ClearRGB(G(), "classBarBg")
            ApplyUnitframeColorWithReload()
        end
        refreshBackgroundPreview()
    end, "background.reset_to_black"), "unitColors")
    if M.TrackCollapsibleRefresh then M.TrackCollapsibleRefresh(ctx, background, refreshBackgroundPreview)
    elseif M.TrackRefresh then M.TrackRefresh(ctx, refreshBackgroundPreview) end
    if ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = refreshBackgroundPreview end
end
function Build.Appearance(ctx, b)
    local appearance = ColorsSection(b, "colors_appearance", "Unitframe Global Coloring", 290, true)
    local refreshBarModeControls
    local function CurrentBarMode()
        local g = G()
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then mode = (g.useClassColors and "class") or "dark" end
        return mode
    end
    local function SetBarMode(mode)
        local g = G()
        g.barMode = mode
        g.darkMode = (mode == "dark")
        g.useClassColors = (mode == "class")
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
        if M.RequestRefresh then M.RequestRefresh(ctx, "colors-bar-mode") end
    end
    -- The leading mode row retains the canonical Search/input owner.
    local BAR_MODE_CARDS = {
        { mode = "dark", title = "Dark Mode", desc = "Dark, neutral bars for every frame." },
        { mode = "class", title = "Class Colors", desc = "Health bars use Blizzard class colors." },
        { mode = "unified", title = "Unified", desc = "One custom color for all health bars." },
        { mode = "gradient", title = "Gradient", desc = "Bar color follows health percent (low / mid / high)." },
    }
    local appearanceW = appearance._msuf2Width or ctx.width or 720
    local modeRowW = min(appearanceW, 740) - 24
    local modeValues = {}
    for i = 1, #BAR_MODE_CARDS do
        modeValues[i] = { value = BAR_MODE_CARDS[i].mode, text = BAR_MODE_CARDS[i].title }
    end
    local modeRow = W.Segment(appearance, "Bar mode", modeValues, modeRowW)
    MoveWidget(modeRow, appearance, 12, -10, modeRowW)
    local modeMeta = Meta("appearance.bar_mode")
    Schema.Bind(ctx, modeRow, { id = modeMeta.controlId, kind = "segment", labelKey = "Bar mode", scope = "colors",
        applyDomain = "unitColors", settingPath = modeMeta.settingKey, meta = modeMeta,
        get = CurrentBarMode,
            customSetReason = "Writes color channels and coordinates dependent color modes and runtime state.", set = SetBarMode })
    for i = 1, #BAR_MODE_CARDS do
        local btn = modeRow.buttons[i]
        if btn and M.AddTooltip then M.AddTooltip(btn, TrText(BAR_MODE_CARDS[i].title), TrText(BAR_MODE_CARDS[i].desc), { hook = true }) end
    end
    local modeDescLabel = LabelAt(appearance, "", 12, -64, appearanceW - 24, "GameFontHighlightSmall", T.colors.muted)
    local unifiedColor = GeneralColorAt(ctx, appearance, "Unified bar color", 12, -94, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
    local darkColor = ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -136, 0, 100, 1, 300,
        function()
            local v = tonumber(G().darkBarGray)
            if not v then return 7 end
            if v <= 1 then return floor(v * 100 + 0.5) end
            return floor(v + 0.5)
        end,
        function(v)
            G().darkBarGray = (tonumber(v) or 0) / 100
            G().darkBarTone = nil
            ApplyUnitframeColorWithReload()
        end,
        Meta("appearance.dark_mode_tone"))
    local gradientStrength = SliderAt(ctx, appearance, "Health strength", 360, -94, 0, 1, 0.05, 250, G, "gradientStrength", 0.45,
        ApplyUnitframeColorWithReload, Meta("appearance.gradient.strength"))
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -142, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end, Meta("appearance.gradient.enabled"))
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -190, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = GeneralColorAt(ctx, appearance, "Low", 12, -220, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = GeneralColorAt(ctx, appearance, "Mid", 170, -220, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = GeneralColorAt(ctx, appearance, "High", 328, -220, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = ButtonAt(appearance, "Reset gradient", 486, -220, 150, function()
        local g = G()
        g.healthGradientLowR, g.healthGradientLowG, g.healthGradientLowB = 1, 0, 0
        g.healthGradientMidR, g.healthGradientMidG, g.healthGradientMidB = 1, 1, 0
        g.healthGradientHighR, g.healthGradientHighG, g.healthGradientHighB = 0, 1, 0
        ApplyUnitframeColorWithReload()
    end, "appearance.gradient.reset")
    for _, control in ipairs({ modeRow, unifiedColor, gradientLow, gradientMid, gradientHigh, gradientReset }) do
        Owned(control, "unitColors")
    end
    local gradientEditControls = { gradientStrength, gradientStopsLabel, gradientLow, gradientMid, gradientHigh, gradientReset }
    if M.AddTooltip then
        M.AddTooltip(gradientStrength, "Health strength",
            "How dark the health bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color.", { hook = true, labelHit = true })
    end
    refreshBarModeControls = function()
        local mode = CurrentBarMode()
        local gradientMode = mode == "gradient"
        local gradientEnabled = gradientMode and G().enableHealthGradient ~= false
        SetControlEnabled(unifiedColor, mode == "unified")
        SetControlEnabled(darkColor, mode == "dark")
        SetControlEnabled(healthGradient, gradientMode)
        SetControlsEnabled(gradientEditControls, gradientEnabled)
        if modeRow and modeRow.SetValue then modeRow:SetValue(mode) end
        for i = 1, #BAR_MODE_CARDS do
            if BAR_MODE_CARDS[i].mode == mode and modeDescLabel and modeDescLabel.SetText then
                modeDescLabel:SetText(BAR_MODE_CARDS[i].desc)
            end
        end
    end
    M.TrackRefresh(ctx, refreshBarModeControls)
    refreshBarModeControls()
end

function Build.Unit(ctx, b)
    local unit = ColorsSection(b, "colors_unit", "Unitframe Colors", 230, false)
    -- One UnitColorRows row built on its own; the result is the widget.
    local function UnitRow(parent, row) return Schema.Build(ctx, parent, { row }, UnitColorRows)[row[2]] end
    local function NPCColors(section, values, columns, xStep, y, yStep)
        local rows = {}
        for i, value in ipairs(values) do
            rows[i] = { "color", value.key, { value.dr, value.dg, value.db }, { value.label },
                position = { 12 + ((i - 1) % columns) * xStep, y - floor((i - 1) / columns) * yStep },
                apiGet = "GetNPCColor", apiSet = "SetNPCColor", arg = value.key, path = "npc.color." .. tostring(value.key) }
        end
        return Schema.Build(ctx, section, rows, UnitColorRows)
    end
    NPCColors(unit, COLOR_DATA.NPC_ROWS, 1, 0, -10, 36)
    local petColor = UnitRow(unit, { "color", "pet", { 0, 0.8, 0 }, { "Pet Frame Color" }, position = { 360, -10 },
        apiGet = "GetPetFrameColor", apiSet = "SetPetFrameColor", path = "api.SetPetFrameColor" })
    local function RefreshPetColorControl() SetControlEnabled(petColor, G().petFrameUsePlayerClassColor ~= true) end
    local petPlayerClass = UnitRow(unit, { "flowToggle", "petPlayerClass", false, { "Use player's class color for Pet Frame" }, { 360, -54 },
        path = "unit.pet.use_player_class_color", get = function() return G().petFrameUsePlayerClassColor == true end,
        write = { source = G, boolean = true, after = function()
                M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                RefreshPetColorControl()
            end } --[[schema setter: AdvancedColors.7]] })
    M.TrackRefresh(ctx, RefreshPetColorControl)
    RefreshPetColorControl()
    if M.AddTooltip then M.AddTooltip(petPlayerClass, "Use player's class color for Pet Frame",
        "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", { hook = true }) end
    UnitRow(unit, { "flowToggle", "npcClassColorBar", false,
        { "Friendly NPC class colors on HP bars (Class Color mode only)" }, { 360, -82 }, path = "npc.class_color_bar",
        get = function() return ApiValue("GetNPCClassColorBar", function() return G().npcClassColorBar == true end) end,
        apiSet = "SetNPCClassColorBar" })
    -- Tagged colors read their own stored kind: the general getter falls back to enemy red.
    if MSUF.Client.SupportsTapDenied == true then
        local tappedColor = UnitRow(unit, { "color", "tapped", { 0.5, 0.5, 0.5 }, { "Tagged by others" }, position = { 12, -154 },
            path = "npc.color.tapped",
            get = function()
                local colors = DB().npcColors
                local stored = type(colors) == "table" and colors.tapped or nil
                if type(stored) == "table" then return stored.r or 0.5, stored.g or 0.5, stored.b or 0.5 end
                return 0.5, 0.5, 0.5
            end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g, c)
                if not ApiCall("SetNPCColor", "tapped", r, g, c) then
                    local db = DB()
                    db.npcColors = db.npcColors or {}
                    db.npcColors.tapped = { r = r, g = g, b = c }
                    ApplyUnitframeColorWithReload()
                end
            end })
        UnitRow(unit, { "flowToggle", "tappedGray", true, { "Gray out mobs tagged by others" }, { 360, -110 }, path = "npc.tap_denied_gray",
            get = function() return G().tapDeniedGray ~= false end,
            write = { source = G, boolean = true, after = function(value)
                    ApplyUnitframeColorWithReload() SetControlEnabled(tappedColor, value)
                end } --[[schema setter: AdvancedColors.9]], tip = { "Gray out mobs tagged by others",
                "A mob another player hit first gives you no loot or experience. Its health bar and name turn gray, like on the default target frame.",
                { hook = true } } })
        M.TrackRefresh(ctx, function() SetControlEnabled(tappedColor, G().tapDeniedGray ~= false) end)
        SetControlEnabled(tappedColor, G().tapDeniedGray ~= false)
    end
    Owned(ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, ResetUnitframeColors, "unitframe.reset"), "unitColors")
    local npcType = ColorsSection(b, "colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls, npcMaster = {}, nil
    local function RefreshNPCTypeControls(enabled)
        if enabled == nil then enabled = npcMaster and npcMaster:GetChecked() and true or false end
        SetControlsEnabled(npcControls, enabled)
    end
    local function NPCTypeToggle(label, x, y, apiGet, apiSet, key, apiArg)
        npcControls[#npcControls + 1] = UnitRow(npcType, { "flowToggle", key, true, { label }, { x, y },
            apiGet = apiGet, apiSet = apiSet, arg = apiArg, path = "npc_type.option." .. tostring(key) })
    end
    NPCTypeToggle("Color HP bar (Class Color mode only)", 32, -38, "GetNPCTypeColorBar", "SetNPCTypeColorBar", "npcTypeColorBar")
    NPCTypeToggle("Color name text", 32, -62, "GetNPCTypeColorText", "SetNPCTypeColorText", "npcTypeColorText")
    npcMaster = UnitRow(npcType, { "switch", "master", false, { "NPC Type Colors", 12, -10, 260 }, path = "npc_type.enabled",
        get = function() return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type" end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
        write = { source = G, convert = function(v) return v and "type" or "reaction" end,
            call = function(record, key, mode)
                if not ApiCall("SetNPCColorMode", mode) then
                    record[key] = mode
                    ApplyUnitframeColorWithReload()
                end
            end,
            after = function(mode) RefreshNPCTypeControls(mode == "type") end
        } --[[schema setter: H4.AdvancedColors.10]] })
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    local units = ColorAPI().NPC_TYPE_UNITS
    if not (type(units) == "table" and #units > 0) then
        units = M.KeyLabelRows [[npcTypeTarget=Target
npcTypeFocus=Focus
npcTypeBoss=Boss
npcTypeToT=Target of Target]]
    end
    for i, info in ipairs(units) do
        NPCTypeToggle(info.label or info.key, 32 + ((i - 1) % 2) * 180, -114 - floor((i - 1) / 2) * 24,
            "GetNPCTypePerUnit", "SetNPCTypePerUnit", info.key, info.key)
    end
    local typeColors = NPCColors(npcType, COLOR_DATA.NPC_TYPE_ROWS, 2, 330, -174, 38)
    for _, row in ipairs(COLOR_DATA.NPC_TYPE_ROWS) do npcControls[#npcControls + 1] = typeColors[row.key] end
    Owned(ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190,
        function() ResetNPCColors("ResetNPCTypeColors") end, "npc_type.reset"), "unitColors")
    M.TrackRefresh(ctx, RefreshNPCTypeControls)
end

-- Colors that write one shared setting used by unit AND group frames get a
-- small inline tag so the duplication reads as intentional, not as two
-- separate settings.
local function MarkSharedColor(control)
    if not control then return end
    local tag = T.Font(control, "GameFontDisableSmall", "Shared with group frames", T.colors.muted)
    tag:SetPoint("LEFT", control, "RIGHT", 8, 0)
    control._msuf2SharedColorTag = tag
end
function Build.BarColors(ctx, b)
    local barColors = ColorsSection(b, "colors_bar_colors", "Bar & Prediction Colors", 280, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    local barColorControls = BuildApiColorSpecs(ctx, barColors, {
        { "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1 },
        { "Heal-Absorb / Negative Heal", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0 },
        { "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0, nil, nil, nil, "powerBg" },
        { "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0 },
    })
    for _, control in pairs(barColorControls) do Owned(control, "unitColors") end
    local powerBg = barColorControls.powerBg
    MarkSharedColor(barColorControls.SetAbsorbOverlayColor)
    MarkSharedColor(barColorControls.SetHealAbsorbOverlayColor)
    -- Plain general-key swatches: the stored prefix carries R / G / B, the page applies on every edit.
    local function GeneralBarColor(label, x, y, prefix, default, path)
        return Owned(ColorValueAt(ctx, barColors, label, x, y,
            function() return GeneralRGB(prefix, default[1], default[2], default[3]) end,
            function(r, g, c)
                local general = G()
                general[prefix .. "R"], general[prefix .. "G"], general[prefix .. "B"] = r, g, c
                ApplyColors()
            end, nil, nil, Meta(path), default), "unitColors")
    end
    MarkSharedColor(GeneralBarColor("Positive Heal Prediction", barLeftX, -146, "healPredictionColor", { 0, 1, 0 }, "prediction.heal_color"))
    GeneralBarColor("Health loss glow", barLeftX, -182, "healthLossColor", { 1, 0.55, 0.08 }, "bar.health_loss_color")
    Owned(ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end,
        nil, nil, Meta("bar.purge_border_color"), { 1.00, 0.85, 0.00 }), "unitColors")
    Owned(ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end,
        nil, nil, Meta("bar.outline_color"), { 0, 0, 0 }), "unitColors")
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Power background matches HP", barRightX, -148,
        function() return ApiValue("GetPowerBarBackgroundMatchHP", function() return G().powerBarBgMatchBarColor == true end) end,
        { write = { source = G, call = function(record, key, value)
                if not ApiCall("SetPowerBarBackgroundMatchHP", value) then
                    record[key] = value and true or false
                    ApplyColors()
                end
            end,
            after = function(value) SetControlEnabled(powerBg, not (value and true or false)) end
        } --[[schema setter: J5.Colors.PowerBackground]] },
        Meta("bar.power_background_match_health"))
    GeneralBarColor("Power loss glow", barRightX, -182, "powerLossColor", { 0.70, 0.90, 1 }, "bar.power_loss_color")
    Owned(ButtonAt(barColors, "Reset Bar Colors", barLeftX, -234, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        ClearRGB(g, "healPredictionColor")
        ClearRGB(g, "healthLossColor")
        ClearRGB(g, "powerLossColor")
        g.barOutlineColorMode = nil
        ClearRGBs(g, "hlAggroColor", "hlPurgeColor", "aggroBorderColor")
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end, "bar.reset"), "unitColors")
    M.BindGateGroup(ctx, nil, {
        { controls = powerBg, on = function() return not (powerBgMatch:GetChecked() and true or false) end },
    })
end

function Build.Castbar(ctx, b)
    local castbar = ColorsSection(b, "colors_castbar", "Castbar Colors", 580, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    for _, control in pairs(BuildApiColorSpecs(ctx, castbar, {
        { "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8 },
        { "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01 },
        { "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0 },
        { "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1 },
        { "Cast Target Name Color", 360, -118, "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
    for _, control in pairs(BuildApiOrGeneralColorSpecs(ctx, castbar, {
        { "Castbar border color", 360, -46, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, nil, 1 },
        { "Castbar background color", 360, -82, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, nil, 0.85 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
    LabelAt(castbar, "Player castbar override", 12, -170, 260, "GameFontNormal", T.colors.text)
    local overrideModeX, overrideModeW = 300, 190
    local overrideColorX = min(max(overrideModeX + overrideModeW + 36, floor(castW * 0.56)), castW - 236)
    local overrideColorLabelW = max(120, min(168, castW - overrideColorX - 76))
    local overrideColorY = -190
    if overrideColorX < overrideModeX + overrideModeW + 24 then
        overrideColorX = overrideModeX
        overrideColorY = -246
        overrideColorLabelW = max(120, min(230, castW - overrideColorX - 76))
    end
    local overrideColor = Owned(ColorValueAt(ctx, castbar, "Custom color", overrideColorX, overrideColorY,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c)
            if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c) then ApplyCastbarColors() end
        end,
        overrideColorLabelW, nil, Meta("castbar.player_override.custom_color"), { 0, 0.6, 1 }), "castbar")
    local overrideEnable
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", overrideModeX, -190, ValueTextPairs "CLASS=Class color|CUSTOM=Custom color", overrideModeW,
        function() return ApiValue("GetPlayerCastbarOverrideMode", function() return G().playerCastbarOverrideMode or "CLASS" end) end,
        { write = { source = G, call = function(record, key, value)
                if not ApiCall("SetPlayerCastbarOverrideMode", value) then record[key] = value ApplyCastbarColors() end
            end,
            after = function(value)
                SetControlEnabled(overrideColor, (overrideEnable and overrideEnable:GetChecked() and true or false) and value == "CUSTOM")
            end
        } --[[schema setter: J5.Colors.CastbarMode]] },
        Meta("castbar.player_override.mode"))
    local function RefreshCastbarOverrideControls(enabled)
        if enabled == nil then enabled = overrideEnable and overrideEnable:GetChecked() and true or false end
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end
    overrideEnable = ValueSwitchAt(ctx, castbar, "Player override", 12, -190, 260,
        function() return ApiValue("GetPlayerCastbarOverrideEnabled", function() return G().playerCastbarOverrideEnabled == true end) end,
        { write = { source = G, call = function(record, key, value)
                if not ApiCall("SetPlayerCastbarOverrideEnabled", value) then
                    record[key] = value and true or false
                    ApplyCastbarColors()
                end
            end,
            after = function(value) RefreshCastbarOverrideControls(value and true or false) end
        } --[[schema setter: J5.Colors.CastbarEnabled]] },
        Meta("castbar.player_override.enabled"))
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -280, 260, "GameFontNormal", T.colors.text)
    for _, control in pairs(BuildTableColorSpecs(ctx, castbar, G, {
        { "Ready color (kick available)", 12, -310, "kickReadyColor", 0, 1, 0 },
        { "Not ready color (kick on cooldown)", 12, -346, "kickNotReadyColor", 1, 0, 0 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
    Owned(ApiColorAt(ctx, castbar, "Unavailable fill color", 12, -382,
        "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1.0, 0.494117647, 0.137254902, ApplyCastbarColors), "castbar")
    Owned(ButtonAt(castbar, "Reset castbar colors", 12, -506, 170, function()
        local apiOwnsRefresh = ApiCall("ResetCastbarTextColorToGlobal")
        apiOwnsRefresh = ApiCall("ResetCastbarTargetNameColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBorderColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBackgroundColor") or apiOwnsRefresh
        local g = G()
        ClearRGBs(g, "castbarInterruptible", "castbarNonInterruptible", "castbarInterruptFeedback", "castbarInterruptUnavailable")
        ClearRGB(g, "castbarTargetName")
        g.castbarInterruptUnavailableColor = nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        ClearRGB(g, "playerCastbarOverride")
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        if not apiOwnsRefresh then ApplyCastbarColors() end
    end, "castbar.reset"), "castbar")
    M.TrackRefresh(ctx, RefreshCastbarOverrideControls)

    -- Canonical surface for the per-castbar text colors that the Unit > Castbar
    -- cards also expose. One castbar is edited at a time so four units stay
    -- three swatches instead of twelve. An unset detail shows the shared castbar
    -- text color it is currently inheriting; the reset button restores that.
    local detail = ColorsSection(b, "colors_castbar_text", "Castbar Text Colors", 280, false)
    local detailW = detail._msuf2Width or ctx.width or 720
    local function DetailUnit()
        local value = tostring(M._colorsCastbarDetailUnit or "player")
        if value == "target" or value == "focus" or value == "boss" or value == "arena" then return value end
        return "player"
    end
    local function DetailRGB(suffix)
        local read = Opt.MSUF_GetCastbarDetailTextColor
        if type(read) == "function" then
            local r, g, bcol, custom = read(DetailUnit(), suffix)
            if custom == true then return r, g, bcol end
        end
        return ApiRGB("GetCastbarTextColor", 1, 1, 1)
    end
    local function SetDetailRGB(suffix, r, g, bcol)
        local write = Opt.MSUF_SetCastbarDetailTextColor
        if type(write) == "function" then write(DetailUnit(), suffix, r, g, bcol) end
        ApplyCastbarColors()
    end
    LabelAt(detail, "Each castbar text can override the shared castbar text color. Target text exists on Target, Focus, Boss, and Arena.",
        12, -8, detailW - 28, "GameFontHighlightSmall", T.colors.muted)
    local detailMeta = Meta("castbar.text_color.unit", "ephemeral")
    local detailUnitDropdown = Schema.Render(ctx, detail, {
        id = detailMeta.controlId, kind = "dropdown", labelKey = "Editing:", scope = "colors", applyDomain = "menuState", meta = detailMeta,
        values = M.FilterSupportedUnitValues(
            ValueTextPairs "player=Player|target=Target|focus=Focus|boss=Boss|arena=Arena"),
        get = DetailUnit, customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            M._colorsCastbarDetailUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "castbar-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end }, { x = 12, y = -44, width = min(260, detailW - 32) })
    RegisterControl(detailUnitDropdown, Meta("castbar.text_color.unit", "ephemeral"), "Editing:", "dropdown")
    local function DetailColor(label, y, suffix, path)
        return ColorValueAt(ctx, detail, label, 12, y,
            function() return DetailRGB(suffix) end,
            function(r, g, bcol) SetDetailRGB(suffix, r, g, bcol) end,
            nil, nil, Meta(path), nil, { scope = "colors", applyDomain = "castbar" })
    end
    DetailColor("Spell text color", -100, "SpellName", "castbar.text_color.spell_name")
    DetailColor("Cast time color", -136, "Time", "castbar.text_color.time")
    local detailTargetColor = DetailColor("Target text color", -172, "TargetName", "castbar.text_color.target_name")
    Owned(ButtonAt(detail, "Follow shared color", 12, -218, 190, function()
        local reset = MSUF.Require("MSUF_ResetCastbarDetailTextColor", FILE)
        local castUnit = DetailUnit()
        reset(castUnit, "SpellName")
        reset(castUnit, "Time")
        reset(castUnit, "TargetName")
        ApplyCastbarColors()
    end, "castbar.text_color.reset"), "castbar")
    M.TrackRefresh(ctx, function()
        SetControlEnabled(detailTargetColor, DetailUnit() ~= "player")
    end)
end

function Build.Highlight(ctx, b)
    local highlight = ColorsSection(b, "colors_highlight", "Highlight Colors", 154, false)
    SchemaRows(ctx, highlight, {
        { "color", "highlight", { 1, 1, 1 }, { "Mouseover highlight color" }, position = { 12, -10 },
            path = "highlight.mouseover.color", get = HighlightRGB,
                customSetReason = "Writes color channels and coordinates dependent color modes and runtime state.", set = SetHighlightRGB },
        { "color", "bossTargetHighlightColor", { 1, 0.82, 0 }, { "Boss target highlight color" }, position = { 12, -66 },
            path = "table.bossTargetHighlightColor", source = G, apply = ApplyBossTargetHighlightColor },
    })
    local texLayer = ColorsSection(b, "colors_texture_layer", "Texture Layer Colors", 340, false)
    for texIndex, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", suffix = "" },
        { id = "texture_layer2", prefix = "texLayer2", suffix = " 2" },
        { id = "texture_layer3", prefix = "texLayer3", suffix = " 3" },
    }) do
        local rowY, prefix = -10 - (texIndex - 1) * 108, texSlot.prefix
        -- The first slot keeps raw locale keys; later slots add the translated slot number.
        local colorLabel, gradientLabel = "Texture layer color", "Texture layer gradient end"
        if texSlot.suffix ~= "" then
            colorLabel, gradientLabel = M.Tr(colorLabel) .. texSlot.suffix, M.Tr(gradientLabel) .. texSlot.suffix
        end
        SchemaRows(ctx, texLayer, {
            { "color", prefix .. "Color", { 1, 1, 1 }, { colorLabel }, position = { 12, rowY }, path = texSlot.id .. ".color",
                customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g,
                    c) M._SetAllTextureLayerRGB(prefix .. "Color", r, g, c) end },
            { "color", prefix .. "Gradient2", { 0, 0, 0 }, { gradientLabel }, position = { 12, rowY - 36 },
                path = texSlot.id .. ".gradient_color",
                    customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                    set = function(r, g, c) M._SetAllTextureLayerRGB(prefix .. "Gradient2", r, g, c) end },
        })
    end
end
function Build.Gameplay(ctx, b)
    local gameplay = ColorsSection(b, "colors_gameplay", "Combat Feedback", 310, false)
    local colors = SchemaRows(ctx, gameplay, {
        { "color", "combatTimerColor", { 1, 1, 1 }, { "Combat timer text color" }, position = { 12, -10 },
            path = "table.combatTimerColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "combatStateEnterColor", { 1, 1, 1 }, { "Combat Enter text color" }, position = { 12, -46 },
            path = "gameplay.combat_enter_color", source = Gameplay,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            companionWrites = { "gameplay.combatStateLeaveColor" },
            set = function(r, g, c)
                local gp = Gameplay()
                SetTableRGB(gp, "combatStateEnterColor", r, g, c)
                if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
                ApplyGameplayColors()
            end },
        { "color", "combatStateLeaveColor", { 0.7, 0.7, 0.7 }, { "Combat Leave text color" }, position = { 12, -82 },
            path = "table.combatStateLeaveColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "crosshairInRangeColor", { 0, 1, 0 }, { "Crosshair in-range color" }, position = { 12, -142 },
            path = "table.crosshairInRangeColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "crosshairOutRangeColor", { 1, 0, 0 }, { "Crosshair out-of-range color" }, position = { 12, -178 },
            path = "table.crosshairOutRangeColor", source = Gameplay, apply = ApplyGameplayColors },
    })
    SchemaRows(ctx, gameplay, {
        { "flowToggle", "combatStateColorSync", false, { "Sync" }, { 360, -82 },
            path = "gameplay.combat_state_color_sync", source = Gameplay, apply = function()
                local gp = Gameplay()
                if gp.combatStateColorSync then
                    local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
                    SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
                end
                ApplyGameplayColors()
                SetControlEnabled(colors.combatStateLeaveColor, not (gp.combatStateColorSync == true))
            end },
    })
    Owned(ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor, gp.combatStateEnterColor = { 1, 1, 1 }, { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor, gp.crosshairOutRangeColor = { 0, 1, 0 }, { 1, 0, 0 }
        ApplyGameplayColors()
    end, "gameplay.reset"), "unitColors")
    M.BindGateGroup(ctx, nil, {
        { controls = colors.combatStateLeaveColor, on = function() return not (Gameplay().combatStateColorSync == true) end },
    })
end

-- The painter paints through the real bound controls of the sections below
-- (each section's color-context owner list), so every color has exactly one
-- source of truth. This shared spec drives the painter tabs, the description
-- line under them AND the headline above the filtered section list, so users
-- see that one tab controls both.
local COLOR_PAINTER_CATEGORIES = {
    { key = "unit", title = "Player & Target Frames", shortTitle = "Player & Target",
        subtitle = "Bars, text, portraits, NPC colors and combat feedback for unit frames.",
        pickerNote = "HP, name and power text share Font Coloring and remain editable here." },
    { key = "group", title = "Party & Raid Frames", shortTitle = "Party & Raid",
        subtitle = "Shared by Party, Raid and Mythic Raid.",
        pickerNote = "Shared by Party, Raid and Mythic Raid." },
    { key = "cast", title = "Castbars", shortTitle = "Castbar",
        subtitle = "Interrupt states, text, border and kick feedback.",
        pickerNote = "Cast states, feedback, text, border and background." },
    { key = "auras", title = "Auras & Icons", shortTitle = "Auras",
        subtitle = "Cooldown timer urgency, global Dispel types, icon borders and shadows.",
        pickerNote = "Safe, Warning, Urgent, Magic, Curse, Disease, Poison, Bleed, icon border and icon shadow." },
    { key = "resources", title = "Power & Class Resources", shortTitle = "Resources",
        subtitle = "Power bar colors and Class Resource colors (combo points, holy power, ...).",
        pickerNote = "Power and Class Resource colors." },
}

-- Explicit load-time exports for the following responsibility modules.
Parts.ApplyScopedBarGradientColors = ApplyScopedBarGradientColors
Parts.COLOR_PAINTER_CATEGORIES = COLOR_PAINTER_CATEGORIES
