local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local UNIT_SCOPE_KEYS = GP.UNIT_SCOPE_KEYS or {}
local TEXT_SCOPE_KEYS = GP.TEXT_SCOPE_KEYS or {}
local POWER_BAR_SCOPE_UNITS = GP.POWER_BAR_SCOPE_UNITS or {}
local GRADIENT_DIRECTIONS = GP.GRADIENT_DIRECTIONS or {}
local GRADIENT_DIR_KEYS = GP.GRADIENT_DIR_KEYS or {}
local PRIORITY_SINGLE = GP.PRIORITY_SINGLE or {}
local PRIORITY_TYPE = GP.PRIORITY_TYPE or {}
local PRIORITY_LABELS = GP.PRIORITY_LABELS or {}
local PRIORITY_COLORS = GP.PRIORITY_COLORS or {}

local Call = GP.Call
local DB = GP.DB
local G = GP.G
local Bars = GP.Bars
local Unit = GP.Unit
local ReadG = GP.ReadG
local Targeted = GP.Targeted
local SetG = GP.SetG
local ReadGBool = GP.ReadGBool
local SetGBool = GP.SetGBool
local ReadB = GP.ReadB
local SetB = GP.SetB
local SetUBool = GP.SetUBool
local NormalizeScopeKey = GP.NormalizeScopeKey
local ScopeDBKeys = GP.ScopeDBKeys
local ScopeHasOverride = GP.ScopeHasOverride
local ScopeSetOverride = GP.ScopeSetOverride
local ScopeRead = GP.ScopeRead
local ScopeWrite = GP.ScopeWrite
local CurrentFontScope = GP.CurrentFontScope
local CurrentBarsScope = GP.CurrentBarsScope
local IsGFScope = GP.IsGFScope
local IsTextScopeKey = GP.IsTextScopeKey
local BarsFlagForKey = GP.BarsFlagForKey
local FontScopeGet = GP.FontScopeGet
local FontScopeSet = GP.FontScopeSet
local BarScopeGet = GP.BarScopeGet
local BarScopeSet = GP.BarScopeSet
local BarScopeGetBars = GP.BarScopeGetBars
local BarScopeSetBars = GP.BarScopeSetBars
local NormalizeFontKey = GP.NormalizeFontKey
local FontValues = GP.FontValues
local ClearUFFontKeyOverrides = GP.ClearUFFontKeyOverrides
local FontKeyGet = GP.FontKeyGet
local FontKeySet = GP.FontKeySet
local TextureValues = GP.TextureValues
local BarsScopeHasOverride = GP.BarsScopeHasOverride
local BarsScopeSetOverride = GP.BarsScopeSetOverride
local CurrentPowerBarScopeUnit = GP.CurrentPowerBarScopeUnit
local SmoothPowerGet = GP.SmoothPowerGet
local SmoothPowerSet = GP.SmoothPowerSet
local NormalizeHpMode = GP.NormalizeHpMode
local NormalizePowerMode = GP.NormalizePowerMode
local CurrentGradientDirection = GP.CurrentGradientDirection
local SetGradientDirection = GP.SetGradientDirection
local PriorityDefaults = GP.PriorityDefaults
local PriorityAllowed = GP.PriorityAllowed
local PriorityOrder = GP.PriorityOrder
local PriorityColor = GP.PriorityColor
local SetPriorityOrder = GP.SetPriorityOrder
local RefreshBorderTestModes = GP.RefreshBorderTestModes
local SetAbsorbTextureTest = GP.SetAbsorbTextureTest
local ClearAbsorbTextureTest = GP.ClearAbsorbTextureTest
local NormalizeGlowStyle = GP.NormalizeGlowStyle
local SetControlEnabled = GP.SetControlEnabled

local function ReadTooltipProvider()
    local provider = ReadG("unitTooltipProvider", nil)
    if provider == "MSUF" then return "MSUF" end
    if provider == "GAME" then return "GAME" end
    return ReadGBool("disableUnitInfoTooltips", true) and "GAME" or "MSUF"
end

local function ReadTooltipAnchor()
    local anchor = ReadG("unitTooltipAnchor", nil)
    if anchor == "EXTERNAL" or anchor == "FIXED" or anchor == "CURSOR" then
        return anchor
    end
    if ReadTooltipProvider() == "MSUF" then
        return (ReadG("unitInfoTooltipStyle", "classic") == "modern") and "CURSOR" or "FIXED"
    end
    if ReadG("unitInfoTooltipStyle", "classic") == "modern" then
        return "CURSOR"
    end
    return "FIXED"
end

local function WriteTooltipSettings(provider, anchor)
    provider = (provider == "MSUF") and "MSUF" or "GAME"
    if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then
        anchor = "EXTERNAL"
    end
    if provider == "MSUF" and anchor == "EXTERNAL" then
        anchor = "FIXED"
    end
    SetG("unitTooltipProvider", provider, "MSUF2_TOOLTIP_PROVIDER", { preview = false })
    SetG("unitTooltipAnchor", anchor, "MSUF2_TOOLTIP_ANCHOR", { preview = false })
    SetGBool("disableUnitInfoTooltips", provider ~= "MSUF", "MSUF2_TOOLTIPS", { preview = false })
    SetG("unitInfoTooltipStyle", (anchor == "CURSOR") and "modern" or "classic", "MSUF2_TOOLTIP_STYLE", { preview = false })
end
local SetControlsEnabled = GP.SetControlsEnabled
local ApplyFonts = GP.ApplyFonts
local ApplyBars = GP.ApplyBars
local ApplyCastbars = GP.ApplyCastbars
local function BuildMisc(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Miscellaneous", "Update pacing, tooltips, Blizzard frames and range fade.", 72)

    local function RefreshRangeFadeRuntime()
        Call("MSUF_RangeFade_Reset")
        if not Call("MSUF_RangeFade_EvaluateActive", true) then
            Call("MSUF_RangeFade_ApplyCurrent", true)
        end
        Call("MSUF_RangeFadeFB_Reset")
        if not Call("MSUF_RangeFadeFB_EvaluateActive", true) then
            Call("MSUF_RangeFadeFB_ApplyCurrent", true)
        end
    end

    local function RefreshTargetRangeFade()
        Call("MSUF_RangeFade_Reset")
        if not Call("MSUF_RangeFade_EvaluateActive", true) then
            Call("MSUF_RangeFade_RebuildSpells")
        end
    end

    local function RefreshFocusBossRangeFade()
        Call("MSUF_RangeFadeFB_Reset")
        if not Call("MSUF_RangeFadeFB_EvaluateActive", true) then
            Call("MSUF_RangeFadeFB_RebuildSpells")
            Call("MSUF_RangeFadeFB_ApplyCurrent", true)
        end
    end

    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nA UI reload is required.",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local language = b:CollapsibleSection("misc_language", "Language", 146, true)
    local languageW = language._msuf2Width or ctx.width or 720
    local languageDropW = max(260, min(360, languageW - 70))
    local languageDrop = W.Dropdown(language, "Menu language", function()
        return (M.GetLocaleDropdownValues and M.GetLocaleDropdownValues()) or {
            { value = "auto", text = "Follow Blizzard" },
        }
    end, languageDropW)
    M.BindDropdown(ctx, languageDrop,
        function()
            return (M.GetLocaleSelection and M.GetLocaleSelection()) or "auto"
        end,
        function(value)
            value = value or "auto"
            SetG("menuLocale", value, "MSUF2_LOCALE", { preview = false, applyAll = false })
            if M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
            local function RebuildLocalePages()
                if M.InvalidatePage then M.InvalidatePage() end
                if M.SelectPage then M.SelectPage("opt_misc") end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, RebuildLocalePages)
            else
                RebuildLocalePages()
            end
        end)
    W.MoveWidget(languageDrop, language, 30, -44, languageDropW, "LEFT")
    local languageHelp = W.Text(language, "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus.", 30, -96, languageW - 70, T.colors.muted)
    if languageHelp.SetWordWrap then languageHelp:SetWordWrap(true) end

    local menuBehavior = b:CollapsibleSection("misc_menu_behavior", "Menu behavior", 158, true)
    local menuSnap = W.Toggle(menuBehavior, "Enable Windows-style edge snap for this menu")
    M.BindToggle(ctx, menuSnap,
        function() return ReadGBool("slashMenuSnapEnabled", true) end,
        function(v) SetGBool("slashMenuSnapEnabled", v, "MSUF2_MENU_SNAP", { preview = false, applyAll = false, notify = false }) end)
    local menuSnapHelp = W.Text(menuBehavior, "Drag the MSUF menu to a screen side for a half-screen layout, to a corner for a quarter layout, or to the top edge for a maximized layout.", 30, -72, (menuBehavior._msuf2Width or ctx.width or 720) - 70, T.colors.muted)
    if menuSnapHelp.SetWordWrap then menuSnapHelp:SetWordWrap(true) end
    local advancedHidden = W.Toggle(menuBehavior, "Hide Advanced menu section")
    M.BindToggle(ctx, advancedHidden,
        function() return ReadGBool("hideAdvancedMenu", true) end,
        function(v)
            SetGBool("hideAdvancedMenu", v, "MSUF2_ADVANCED_MENU_VISIBILITY", { preview = false, applyAll = false, notify = false })
            if M.RefreshAdvancedNavVisibility then M.RefreshAdvancedNavVisibility() end
        end)
    W.MoveWidget(advancedHidden, menuBehavior, 14, -118, 280, "LEFT")

    local unitInterval, castInterval, budget, urgent
    local updates = b:CollapsibleSection("misc_updates", "Update intervals", 402, true)
    local preset = W.Segment(updates, "Preset", {
        { value = "perf", text = "Performance" },
        { value = "balanced", text = "Balanced" },
        { value = "accurate", text = "Accurate" },
    }, 336)
    M.BindSegment(ctx, preset,
        function() return ReadG("miscUpdatesPreset", "balanced") end,
        function(v)
            v = v or "balanced"
            SetG("miscUpdatesPreset", v, "MSUF2_UPDATE_PRESET", { preview = false })
            local values = {
                perf = { 0.12, 0.06, 1.0, 6 },
                balanced = { 0.05, 0.02, 2.0, 10 },
                accurate = { 0.01, 0.01, 5.0, 50 },
            }
            local p = values[v] or values.balanced
            if unitInterval then unitInterval:SetValue(p[1]) end
            if castInterval then castInterval:SetValue(p[2]) end
            if budget then budget:SetValue(p[3]) end
            if urgent then urgent:SetValue(p[4]) end
        end)

    unitInterval = W.Slider(updates, "Unit update interval", 0.01, 0.30, 0.01, 300)
    M.BindSlider(ctx, unitInterval,
        function() return tonumber(ReadG("frameUpdateInterval", _G.MSUF_FrameUpdateInterval or 0.05)) or 0.05 end,
        function(v)
            v = tonumber(v) or 0.05
            SetG("frameUpdateInterval", v, "MSUF2_UPDATE_INTERVAL", { preview = false })
            _G.MSUF_FrameUpdateInterval = v
        end)
    _G.MSUF2_MiscUnitIntervalSlider = unitInterval

    castInterval = W.Slider(updates, "Castbar update interval", 0.01, 0.30, 0.01, 300)
    M.BindSlider(ctx, castInterval,
        function() return tonumber(ReadG("castbarUpdateInterval", _G.MSUF_CastbarUpdateInterval or 0.02)) or 0.02 end,
        function(v)
            v = tonumber(v) or 0.02
            SetG("castbarUpdateInterval", v, "MSUF2_CASTBAR_UPDATE_INTERVAL", { castbar = true, preview = false })
            _G.MSUF_CastbarUpdateInterval = v
        end)

    budget = W.Slider(updates, "UFCore flush budget", 0.5, 5.0, 0.1, 300)
    M.BindSlider(ctx, budget,
        function() return tonumber(ReadG("ufcoreFlushBudgetMs", 2.0)) or 2.0 end,
        function(v) SetG("ufcoreFlushBudgetMs", tonumber(v) or 2.0, "MSUF2_UFCORE_BUDGET", { preview = false }) end)

    urgent = W.Slider(updates, "UFCore urgent cap", 1, 50, 1, 300)
    M.BindSlider(ctx, urgent,
        function() return tonumber(ReadG("ufcoreUrgentMaxPerFlush", 10)) or 10 end,
        function(v) SetG("ufcoreUrgentMaxPerFlush", floor((tonumber(v) or 10) + 0.5), "MSUF2_UFCORE_URGENT", { preview = false }) end)

    local welcome = W.Toggle(updates, "Show welcome message")
    M.BindToggle(ctx, welcome,
        function() return ReadGBool("showWelcomeMessage", true) end,
        function(v) SetGBool("showWelcomeMessage", v, "MSUF2_WELCOME", { preview = false }) end)

    local version = W.Toggle(updates, "Enable version check (peer-to-peer)")
    M.BindToggle(ctx, version,
        function() return ReadGBool("versionCheckEnabled", true) end,
        function(v) SetGBool("versionCheckEnabled", v, "MSUF2_VERSION_CHECK", { preview = false }) end)

    local tooltips = b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", 216, false)
    local tooltipProvider = W.Dropdown(tooltips, "Tooltip source", {
        { value = "GAME", text = "GameTooltip (addon-compatible)" },
        { value = "MSUF", text = "MSUF custom panel" },
    }, 240)
    M.BindDropdown(ctx, tooltipProvider,
        function() return ReadTooltipProvider() end,
        function(v) WriteTooltipSettings(v, ReadTooltipAnchor()) end)
    local tooltipAnchor = W.Dropdown(tooltips, "Tooltip anchor", {
        { value = "EXTERNAL", text = "Addon / Blizzard controlled" },
        { value = "FIXED", text = "MSUF fixed position" },
        { value = "CURSOR", text = "MSUF cursor" },
    }, 240)
    M.BindDropdown(ctx, tooltipAnchor,
        function() return ReadTooltipAnchor() end,
        function(v) WriteTooltipSettings(ReadTooltipProvider(), v) end)

    local blizzard = b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", 190, false)
    local blizzUF = W.Toggle(blizzard, "Disable Blizzard unitframes")
    M.BindToggle(ctx, blizzUF,
        function() return ReadGBool("disableBlizzardUnitFrames", true) end,
        function(v)
            SetGBool("disableBlizzardUnitFrames", v, "MSUF2_DISABLE_BLIZZARD_UF", { preview = false })
            if print then print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.") end
        end)
    local hardKill = W.Toggle(blizzard, "Fully Hide Blizzard PlayerFrame - resource bar compatibility")
    M.BindToggle(ctx, hardKill,
        function() return ReadGBool("hardKillBlizzardPlayerFrame", false) end,
        function(v)
            SetGBool("hardKillBlizzardPlayerFrame", v, "MSUF2_HARDKILL_PLAYERFRAME", { preview = false })
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end)
    local minimap = W.Toggle(blizzard, "Show MSUF minimap icon")
    M.BindToggle(ctx, minimap,
        function() return ReadGBool("showMinimapIcon", true) end,
        function(v)
            SetGBool("showMinimapIcon", v, "MSUF2_MINIMAP_ICON", { preview = false })
            if type(_G.MSUF_SetMinimapIconEnabled) == "function" then
                pcall(_G.MSUF_SetMinimapIconEnabled, v)
            else
                local g = G()
                g.minimapIconDB = g.minimapIconDB or {}
                g.minimapIconDB.hide = not v
            end
        end)
    local sounds = W.Toggle(blizzard, "Play sound on Target/Target Lost")
    M.BindToggle(ctx, sounds,
        function() return ReadGBool("playTargetSelectLostSounds", false) end,
        function(v)
            SetGBool("playTargetSelectLostSounds", v, "MSUF2_TARGET_SOUNDS", { preview = false })
            Call("MSUF_TargetSoundDriver_ResetState")
            if v then Call("MSUF_TargetSoundDriver_Ensure") end
        end)

    local range = b:CollapsibleSection("misc_range_fade", "Range Fade", 260, false)
    local rangeW = range._msuf2Width or ctx.width or 720
    local rangeLeftX = 30
    local rangeRightX = max(430, floor(rangeW * 0.50))
    local rangeLeftW = max(260, min(340, rangeRightX - rangeLeftX - 70))
    local rangeRightW = max(280, min(360, rangeW - rangeRightX - 42))
    local rangeToggles = {}
    local bossExtras = {}

    W.LabelAt(range, "Unit frames", rangeLeftX, -38, rangeLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(range, "Effect", rangeRightX, -38, rangeRightW, "GameFontNormalSmall", T.colors.accent)

    for index, spec in ipairs({
        { unit = "target", key = "rangeFadeEnabled", label = "Target range fade" },
        { unit = "focus", key = "rangeFadeEnabled", label = "Focus range fade" },
        { unit = "boss", key = "rangeFadeEnabled", label = "Boss range fade" },
        { unit = "boss", key = "rangeFadeCastbar", label = "Boss castbar range fade" },
        { unit = "boss", key = "rangeFadeAuras", label = "Boss auras range fade" },
    }) do
        local toggle = W.Toggle(range, spec.label)
        local y = (index <= 3) and (-66 - (index - 1) * 32) or (-174 - (index - 4) * 32)
        W.MoveWidget(toggle, range, rangeLeftX, y)
        if index <= 3 then
            rangeToggles[#rangeToggles + 1] = toggle
        else
            bossExtras[#bossExtras + 1] = toggle
        end
        M.BindToggle(ctx, toggle,
            function() return Unit(spec.unit)[spec.key] == true end,
            function(v)
                SetUBool(spec.unit, spec.key, v, "MSUF2_RANGE_FADE", { alpha = true, preview = true })
                if spec.unit == "target" then
                    RefreshTargetRangeFade()
                else
                    RefreshFocusBossRangeFade()
                end
            end)
    end

    W.LabelAt(range, "Boss children", rangeLeftX, -148, rangeLeftW, "GameFontNormalSmall", T.colors.accent)

    local affects = W.Dropdown(range, "Range fade affects", {
        { value = "frame", text = "Frame" },
        { value = "health", text = "HP Bar" },
    }, rangeRightW)
    M.BindDropdown(ctx, affects,
        function()
            local value = Unit("target").rangeFadeLayerMode or Unit("focus").rangeFadeLayerMode or Unit("boss").rangeFadeLayerMode or "frame"
            return (value == "health") and "health" or "frame"
        end,
        function(value)
            value = (value == "health") and "health" or "frame"
            Unit("target").rangeFadeLayerMode = value
            Unit("focus").rangeFadeLayerMode = value
            Unit("boss").rangeFadeLayerMode = value
            RefreshRangeFadeRuntime()
            M.RequestGeneralApply("MSUF2_RANGE_FADE_LAYER", { alpha = true, preview = true, applyAll = false })
        end)
    W.MoveWidget(affects, range, rangeRightX, -66, rangeRightW, "LEFT")

    local alpha = W.Slider(range, "Out of range alpha", 0, 60, 5, rangeRightW)
    M.BindSlider(ctx, alpha,
        function()
            local value = tonumber(Unit("target").rangeFadeAlpha or Unit("focus").rangeFadeAlpha or Unit("boss").rangeFadeAlpha or 0.6) or 0.6
            if value < 0 then value = 0 elseif value > 0.6 then value = 0.6 end
            return floor(value * 100 + 0.5)
        end,
        function(v)
            v = (tonumber(v) or 60) / 100
            if v < 0 then v = 0 elseif v > 0.6 then v = 0.6 end
            Unit("target").rangeFadeAlpha = v
            Unit("focus").rangeFadeAlpha = v
            Unit("boss").rangeFadeAlpha = v
            RefreshRangeFadeRuntime()
            M.RequestGeneralApply("MSUF2_RANGE_FADE_ALPHA", { alpha = true, preview = true, applyAll = false })
        end)
    W.MoveWidget(alpha, range, rangeRightX, -120, rangeRightW, "CENTER")

    local portrait = W.Toggle(range, "Fade portrait too")
    M.BindToggle(ctx, portrait,
        function() return ReadGBool("rangeFadePortrait", false) end,
        function(v)
            SetGBool("rangeFadePortrait", v, "MSUF2_RANGE_FADE_PORTRAIT", { alpha = true, preview = true })
            RefreshRangeFadeRuntime()
            Call("MSUF_RefreshAllUnitAlphas")
        end)
    W.MoveWidget(portrait, range, rangeRightX, -176)

    local rangeHint = W.Text(range, "HP Bar only fades the health layer; Frame fades the full unit frame.", rangeRightX, -210, rangeRightW, T.colors.muted)
    if rangeHint.SetWordWrap then rangeHint:SetWordWrap(true) end
    M.AddRefresher(ctx, function()
        local anyEnabled = Unit("target").rangeFadeEnabled == true
            or Unit("focus").rangeFadeEnabled == true
            or Unit("boss").rangeFadeEnabled == true
        SetControlsEnabled({ affects, alpha, portrait }, anyEnabled)
        SetControlsEnabled(rangeToggles, true)
        SetControlsEnabled(bossExtras, Unit("boss").rangeFadeEnabled == true)
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc, version = 5 })
