local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local CallGlobal = AP.CallGlobal
local DB = AP.DB
local G = AP.G
local Bars = AP.Bars
local Gameplay = AP.Gameplay
local BoolValue = AP.BoolValue
local NumValue = AP.NumValue
local SetValue = AP.SetValue
local DeepCopyTable = AP.DeepCopyTable
local BindTableToggle = AP.BindTableToggle
local BindTableSlider = AP.BindTableSlider
local BindTableDropdown = AP.BindTableDropdown
local BindValueDropdown = AP.BindValueDropdown
local ReadRGB = AP.ReadRGB
local WriteRGB = AP.WriteRGB
local BindTableColor = AP.BindTableColor
local BindSeparateRGB = AP.BindSeparateRGB
local ApplyAuras = AP.ApplyAuras
local MoveWidget = W.MoveWidget or AP.MoveWidget
local LabelAt = AP.LabelAt
local DividerAt = AP.DividerAt
local BindValueToggle = AP.BindValueToggle
local BindValueSlider = AP.BindValueSlider
local ToggleAt = AP.ToggleAt
local ValueToggleAt = AP.ValueToggleAt
local SliderAt = AP.SliderAt
local ValueSliderAt = AP.ValueSliderAt
local DropdownAt = AP.DropdownAt
local ValueDropdownAt = AP.ValueDropdownAt
local ColorAt = AP.ColorAt
local ScopedToggleAt = AP.ScopedToggleAt
local ScopedSliderAt = AP.ScopedSliderAt
local ScopedDropdownAt = AP.ScopedDropdownAt
local TogglePillAt = AP.TogglePillAt
local SetControlEnabled = AP.SetControlEnabled
local function ApplyClassPower()
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    M.RequestGeneralApply("MSUF2_CLASSPOWER", { preview = true, applyAll = false })
end

local function ShowClassPowerReloadPrompt()
    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] then
        _G.StaticPopupDialogs["MSUF_CLASSPOWER_ENABLE_RELOAD"] = {
            text = "Class Resources were enabled or disabled.\n\nA UI reload is required to fully apply this change.\n\nReload now?",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    if StaticPopup_Show then StaticPopup_Show("MSUF_CLASSPOWER_ENABLE_RELOAD") end
end

local function TextureValues(followText)
    local ui = ns and ns.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then
        return ui.StatusBarTextureItems(followText)
    end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name }
    end
    return out
end

local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    M.BindSlider(ctx, slider,
        function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end,
        function(v)
            v = tonumber(v) or ((default or 0) * 100)
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            SetValue(Bars(), key, v / 100, apply)
        end)
    return slider
end

local function ApplyDetachedPowerBar()
    CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    M.RequestGeneralApply("MSUF2_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
end

local function ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar()
end

local function IsMSUFEditModeActive()
    if type(_G.MSUF_IsMSUFEditModeActive) == "function" then return _G.MSUF_IsMSUFEditModeActive() and true or false end
    local st = _G.MSUF_EditState
    if type(st) == "table" and st.active ~= nil then return st.active == true end
    local em2 = _G.MSUF_EM2
    if em2 and em2.State and type(em2.State.IsActive) == "function" then return em2.State.IsActive() and true or false end
    return _G.MSUF_UnitEditModeActive == true
end

local function IsEditModeCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function BuildClassPower(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Class Resources", "Native class-resource layout, visibility and text controls.", 64)

    local colors = T.Button(head, "Class Color", 112, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(colors) end
    colors:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -20)
    colors:SetScript("OnClick", function() M.SelectPage("opt_colors") end)

    local edit = T.Button(head, "MSUF Edit Mode", 128, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(edit) end
    edit:SetPoint("RIGHT", colors, "LEFT", -10, 0)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, head, edit, { width = 88 })
    end
    local function RefreshEditButton()
        local active = IsMSUFEditModeActive()
        if edit.SetText then edit:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode")) end
        if edit.SetActive then edit:SetActive(false) end
        if edit.SetEnabled then edit:SetEnabled(active or not IsEditModeCombatLocked()) end
    end
    edit:SetScript("OnClick", function()
        local active = IsMSUFEditModeActive()
        if (not active) and IsEditModeCombatLocked() then
            if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
            RefreshEditButton()
            return
        end
        local fn = _G.MSUF_SetMSUFEditModeDirect or _G.MSUF_SetEditMode
        if type(fn) == "function" then pcall(fn, not active) end
        RefreshEditButton()
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    local layoutWidth = ctx.width or 900
    local compactLayout = layoutWidth < 620
    local display = b:CollapsibleSection("classpower_display", "Layout", compactLayout and 444 or 268, true)
    local cpControls = {}
    local textControls = {}
    local dpbControls = {}
    local altManaControls = {}

    local cpEnable = BindTableToggle(ctx, display, "Enable", Bars, "showClassPower", true, function()
        ApplyClassPower()
        ShowClassPowerReloadPrompt()
    end)
    local cpHeight = BindTableSlider(ctx, display, "Height", 1, 40, 1, 300, Bars, "classPowerHeight", 4, ApplyClassPower)
    local cpWidthMode = BindTableDropdown(ctx, display, "Width mode", {
        { value = "player", text = "Player frame" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
        { value = "custom", text = "Custom" },
    }, 260, Bars, "classPowerWidthMode", "player", ApplyClassPower)
    local cpWidth = BindTableSlider(ctx, display, "Width", 30, 800, 1, 300, Bars, "classPowerWidth", 0, ApplyClassPower)
    local cpX = BindTableSlider(ctx, display, "Offset X", -800, 800, 1, 300, Bars, "classPowerOffsetX", 0, ApplyClassPower)
    local cpY = BindTableSlider(ctx, display, "Offset Y", -800, 800, 1, 300, Bars, "classPowerOffsetY", 0, ApplyClassPower)
    local cpLevel = BindTableSlider(ctx, display, "Frame level", 0, 30, 1, 300, Bars, "classPowerFrameLevelOffset", 5, ApplyClassPower)
    cpControls[#cpControls + 1] = cpHeight
    cpControls[#cpControls + 1] = cpWidthMode
    cpControls[#cpControls + 1] = cpX
    cpControls[#cpControls + 1] = cpY
    cpControls[#cpControls + 1] = cpLevel
    local layoutLeftX = 32
    local layoutRightX = compactLayout and layoutLeftX or min(max(430, floor(layoutWidth * 0.52)), max(360, layoutWidth - 360))
    local layoutLeftW = compactLayout and max(250, layoutWidth - layoutLeftX - 32) or max(250, layoutRightX - layoutLeftX - 42)
    local layoutRightW = compactLayout and layoutLeftW or max(250, layoutWidth - layoutRightX - 32)
    local layoutControlW = compactLayout and max(250, min(320, layoutWidth - layoutLeftX - 42)) or 300
    local positionTopY = compactLayout and -266 or -64
    LabelAt(display, "Bar", layoutLeftX, -38, layoutLeftW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(display, "Position", layoutRightX, compactLayout and -240 or -38, layoutRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpEnable, display, layoutLeftX, -64)
    MoveWidget(cpHeight, display, layoutLeftX, -98, layoutControlW)
    MoveWidget(cpWidthMode, display, layoutLeftX, -150, layoutControlW)
    MoveWidget(cpWidth, display, layoutLeftX, -202, layoutControlW)
    MoveWidget(cpX, display, layoutRightX, positionTopY, layoutControlW)
    MoveWidget(cpY, display, layoutRightX, positionTopY - 52, layoutControlW)
    MoveWidget(cpLevel, display, layoutRightX, positionTopY - 104, layoutControlW)

    local behavior = b:CollapsibleSection("classpower_behavior", "Behavior", 206, false)
    local cpAnchor = BindTableToggle(ctx, behavior, "Anchor to Essential Cooldown", Bars, "classPowerAnchorToCooldown", false, ApplyClassPower)
    local cpCharged = BindTableToggle(ctx, behavior, "Show empowered combo points", Bars, "showChargedComboPoints", true, ApplyClassPower)
    local cpText = BindTableToggle(ctx, behavior, "Show resource text", Bars, "classPowerShowText", false, ApplyClassPower)
    local cpRune = BindTableToggle(ctx, behavior, "Show rune time (per rune)", Bars, "runeShowTime", true, ApplyClassPower)
    local cpReverse = BindTableToggle(ctx, behavior, "Fill right-to-left", Bars, "classPowerFillReverse", false, ApplyClassPower)
    local cpEle = BindTableToggle(ctx, behavior, "Show Maelstrom bar (Ele)", Bars, "showEleMaelstrom", false, ApplyClassPower)
    local cpEbon = BindTableToggle(ctx, behavior, "Show Ebon Might timer (Aug)", Bars, "showEbonMight", true, ApplyClassPower)
    local cpShadow = BindTableToggle(ctx, behavior, "Show Insanity bar (Shadow)", Bars, "showShadowMana", false, ApplyClassPower)
    local cpPrediction = BindTableToggle(ctx, behavior, "Show resource prediction", Bars, "classPowerShowPrediction", true, ApplyClassPower)
    for _, control in ipairs({ cpAnchor, cpCharged, cpText, cpRune, cpReverse, cpEle, cpEbon, cpShadow, cpPrediction }) do
        cpControls[#cpControls + 1] = control
    end
    local behaviorRightX = min(max(380, floor((ctx.width or 900) * 0.45)), max(320, (ctx.width or 900) - 420))
    MoveWidget(cpAnchor, behavior, 14, -38)
    MoveWidget(cpCharged, behavior, 14, -70)
    MoveWidget(cpText, behavior, 14, -102)
    MoveWidget(cpRune, behavior, 14, -134)
    MoveWidget(cpReverse, behavior, 14, -166)
    MoveWidget(cpEle, behavior, behaviorRightX, -38)
    MoveWidget(cpEbon, behavior, behaviorRightX, -70)
    MoveWidget(cpShadow, behavior, behaviorRightX, -102)
    MoveWidget(cpPrediction, behavior, behaviorRightX, -134)

    local visual = b:CollapsibleSection("classpower_visuals", "Style", 420, false)
    local cpColor = BindTableToggle(ctx, visual, "Color by resource type", Bars, "classPowerColorByType", true, ApplyClassPower)
    local cpComboColor = BindTableDropdown(ctx, visual, "Combo point colors", {
        { value = "default", text = "Resource color" },
        { value = "ramp", text = "Combo ramp" },
        { value = "custom", text = "Custom slots" },
    }, 260, Bars, "classPowerComboPointColorMode", "default", ApplyClassPower)
    local cpFont = BindTableSlider(ctx, visual, "Font size", 6, 32, 1, 300, Bars, "classPowerFontSize", 16, ApplyClassPower)
    local cpTextX = BindTableSlider(ctx, visual, "Text X", -200, 200, 1, 300, Bars, "classPowerTextOffsetX", 0, ApplyClassPower)
    local cpTextY = BindTableSlider(ctx, visual, "Text Y", -200, 200, 1, 300, Bars, "classPowerTextOffsetY", 0, ApplyClassPower)
    local cpBg = BindBarsAlphaPercent(ctx, visual, "BG opacity", "classPowerBgAlpha", 0.3, ApplyClassPower, 1)
    local cpSeparator = BindTableSlider(ctx, visual, "Separator", 0, 4, 1, 300, Bars, "classPowerTickWidth", 1, ApplyClassPower)
    local cpOutline = BindTableSlider(ctx, visual, "Outline", 0, 4, 1, 300, Bars, "classPowerOutline", 1, ApplyClassPower)
    local cpFilled = BindBarsAlphaPercent(ctx, visual, "Filled %", "classPowerFilledAlpha", 1.0, ApplyClassPower, 5)
    local cpEmpty = BindBarsAlphaPercent(ctx, visual, "Empty %", "classPowerEmptyAlpha", 0.3, ApplyClassPower, 5)
    local cpGap = BindTableSlider(ctx, visual, "Pip gap", 0, 8, 1, 300, Bars, "classPowerGap", 0, ApplyClassPower)
    local cpFgTex = BindTableDropdown(ctx, visual, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "classPowerTexture", "", ApplyClassPower)
    local cpBgTex = BindTableDropdown(ctx, visual, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "classPowerBgTexture", "", ApplyClassPower)
    for _, control in ipairs({ cpColor, cpComboColor, cpBg, cpSeparator, cpOutline, cpFilled, cpEmpty, cpGap, cpFgTex, cpBgTex }) do
        cpControls[#cpControls + 1] = control
    end
    textControls[#textControls + 1] = cpFont
    textControls[#textControls + 1] = cpTextX
    textControls[#textControls + 1] = cpTextY
    local styleWidth = ctx.width or 900
    local styleLeftX = 32
    local styleMidX = min(max(360, floor(styleWidth * 0.36)), max(320, styleWidth - 650))
    local styleRightX = min(max(styleMidX + 300, floor(styleWidth * 0.66)), max(styleMidX + 270, styleWidth - 390))
    local styleLeftW = max(240, styleMidX - styleLeftX - 28)
    local styleMidW = max(240, styleRightX - styleMidX - 28)
    local styleRightW = max(240, styleWidth - styleRightX - 32)
    local styleLeftControlW = max(260, min(322, styleMidX - styleLeftX - 20))
    local styleMidControlW = max(240, min(286, styleRightX - styleMidX - 24))
    local styleRightControlW = max(240, min(286, styleWidth - styleRightX - 36))
    LabelAt(visual, "Resource", styleLeftX, -38, styleLeftW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(visual, "Text", styleMidX, -38, styleMidW, "GameFontNormalSmall", T.colors.accent)
    LabelAt(visual, "Opacity", styleRightX, -38, styleRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpColor, visual, styleLeftX, -64)
    MoveWidget(cpComboColor, visual, styleLeftX, -96, styleLeftControlW)
    LabelAt(visual, "Textures", styleLeftX, -158, styleLeftW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpFgTex, visual, styleLeftX, -184, styleLeftControlW)
    MoveWidget(cpBgTex, visual, styleLeftX, -238, styleLeftControlW)
    MoveWidget(cpFont, visual, styleMidX, -64, styleMidControlW)
    MoveWidget(cpTextX, visual, styleMidX, -116, styleMidControlW)
    MoveWidget(cpTextY, visual, styleMidX, -168, styleMidControlW)
    MoveWidget(cpBg, visual, styleRightX, -64, styleRightControlW)
    MoveWidget(cpFilled, visual, styleRightX, -116, styleRightControlW)
    MoveWidget(cpEmpty, visual, styleRightX, -168, styleRightControlW)
    W.DividerAt(visual, -222, styleRightX, 32)
    LabelAt(visual, "Pips & Border", styleRightX, -240, styleRightW, "GameFontNormalSmall", T.colors.accent)
    MoveWidget(cpSeparator, visual, styleRightX, -266, styleRightControlW)
    MoveWidget(cpOutline, visual, styleRightX, -318, styleRightControlW)
    MoveWidget(cpGap, visual, styleRightX, -370, styleRightControlW)

    local visibility = b:CollapsibleSection("classpower_visibility", "Auto-Hide", 170, false)
    local hideOOC = BindTableToggle(ctx, visibility, "Hide out of combat", Bars, "classPowerHideOOC", false, ApplyClassPower)
    local hideFull = BindTableToggle(ctx, visibility, "Hide when full", Bars, "classPowerHideWhenFull", false, ApplyClassPower)
    local hideEmpty = BindTableToggle(ctx, visibility, "Hide when empty", Bars, "classPowerHideWhenEmpty", false, ApplyClassPower)
    for _, control in ipairs({ hideOOC, hideFull, hideEmpty }) do cpControls[#cpControls + 1] = control end

    local dpb = b:CollapsibleSection("classpower_detached_power", "Detached Power Bar", 352, false)
    W.Text(dpb, "Only applies when power bar is detached.", 14, -38, ctx.width - 28, T.colors.muted)
    dpb._msuf2CursorY = -72
    local dpbMode = W.Dropdown(dpb, "Width mode", {
        { value = "manual", text = "Manual" },
        { value = "cooldown", text = "Essential Cooldowns" },
        { value = "utility", text = "Utility Cooldowns" },
        { value = "tracked_buffs", text = "Tracked Buffs" },
    }, 260)
    M.BindDropdown(ctx, dpbMode,
        function() return Bars().detachedPowerBarWidthMode or "manual" end,
        function(v)
            Bars().detachedPowerBarWidthMode = (v ~= "manual") and v or nil
            ApplyDetachedPowerBar()
        end)
    local dpbFg = BindTableDropdown(ctx, dpb, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "detachedPowerBarTexture", "", ApplyDetachedPowerBar)
    local dpbBg = BindTableDropdown(ctx, dpb, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "detachedPowerBarBgTexture", "", ApplyDetachedPowerBar)
    local dpbOutline = BindTableSlider(ctx, dpb, "Power bar outline", 0, 6, 1, 300, Bars, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline)
    for _, control in ipairs({ dpbMode, dpbFg, dpbBg, dpbOutline }) do dpbControls[#dpbControls + 1] = control end

    local altMana = b:CollapsibleSection("classpower_alt_mana", "Alternative Mana Bar", 238, false)
    W.Text(altMana, "Shadow, Ret, Ele, Enh, Balance, Feral, WW", 14, -38, ctx.width - 28, T.colors.muted)
    altMana._msuf2CursorY = -72
    local altManaToggle = BindTableToggle(ctx, altMana, "Show mana bar (dual resource)", Bars, "showAltMana", false, ApplyClassPower)
    local altManaHeight = BindTableSlider(ctx, altMana, "Height", 2, 30, 1, 300, Bars, "altManaHeight", 4, ApplyClassPower)
    local altManaY = BindTableSlider(ctx, altMana, "Y offset", -50, 50, 1, 300, Bars, "altManaOffsetY", -2, ApplyClassPower)
    altManaControls[#altManaControls + 1] = altManaHeight
    altManaControls[#altManaControls + 1] = altManaY

    M.AddRefresher(ctx, function()
        local bars = Bars()
        local cpOn = BoolValue(bars, "showClassPower", true)
        local textOn = cpOn and BoolValue(bars, "classPowerShowText", false)
        local customWidth = cpOn and ((bars.classPowerWidthMode or "player") == "custom")
        local anyDetached = false
        local db = M.EnsureDB()
        for _, key in ipairs({ "player", "target", "focus" }) do
            if db[key] and db[key].powerBarDetached then anyDetached = true; break end
        end
        for i = 1, #cpControls do SetControlEnabled(cpControls[i], cpOn) end
        SetControlEnabled(cpWidth, customWidth)
        for i = 1, #textControls do SetControlEnabled(textControls[i], textOn) end
        for i = 1, #dpbControls do SetControlEnabled(dpbControls[i], anyDetached) end
        local altOn = BoolValue(bars, "showAltMana", false)
        for i = 1, #altManaControls do SetControlEnabled(altManaControls[i], altOn) end
        SetControlEnabled(altManaToggle, true)
        SetControlEnabled(cpEnable, true)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 7 })
