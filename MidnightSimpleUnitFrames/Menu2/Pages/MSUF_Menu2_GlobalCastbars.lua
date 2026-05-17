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
local SetControlsEnabled = GP.SetControlsEnabled
local ApplyFonts = GP.ApplyFonts
local ApplyBars = GP.ApplyBars
local ApplyCastbars = GP.ApplyCastbars
local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Castbar", "Castbar behavior, textures, GCD and interrupt indicators.", 72)

    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then
            pcall(_G.MSUF_EnsureAddonLoaded, "MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
            pcall(C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
        end
    end

    local function ApplyCastbarTextures(reason)
        EnsureCastbars()
        Call("MSUF_UpdateCastbarTextures_Immediate")
        Call("MSUF_UpdateCastbarTextures")
        Call("MSUF_UpdateCastbarVisuals_Immediate")
        Call("MSUF_UpdateCastbarVisuals")
        Call("MSUF_UpdateBossCastbarPreview")
        ApplyCastbars(reason or "MSUF2_CASTBAR_TEXTURES")
    end

    local behavior = b:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 196, true)
    local leftX, rightX = 14, 392
    local shake = W.Toggle(behavior, "Shake on interrupt")
    W.MoveWidget(shake, behavior, leftX, -42)
    M.BindToggle(ctx, shake,
        function() return ReadGBool("castbarInterruptShake", false) end,
        function(v) SetGBool("castbarInterruptShake", v, "MSUF2_CASTBAR_SHAKE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_SHAKE") end)

    local strength = W.Slider(behavior, "Shake strength", 0, 30, 1, 300)
    W.MoveWidget(strength, behavior, leftX, -72, 320)
    M.BindSlider(ctx, strength,
        function() return tonumber(ReadG("castbarShakeStrength", 8)) or 8 end,
        function(v) SetG("castbarShakeStrength", floor((tonumber(v) or 8) + 0.5), "MSUF2_CASTBAR_SHAKE_STRENGTH", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_SHAKE_STRENGTH") end)

    local unified = W.Toggle(behavior, "Always use fill direction for all casts")
    W.MoveWidget(unified, behavior, rightX, -42)
    M.BindToggle(ctx, unified,
        function() return ReadGBool("castbarUnifiedDirection", false) end,
        function(v) SetGBool("castbarUnifiedDirection", v, "MSUF2_CASTBAR_UNIFIED_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_UNIFIED_DIRECTION") end)

    local direction = W.Dropdown(behavior, "Castbar fill direction", {
        { value = "RTL", text = "Right to left (default)" },
        { value = "LTR", text = "Left to right" },
    }, 260)
    W.MoveWidget(direction, behavior, rightX, -72, 300)
    M.BindDropdown(ctx, direction,
        function() return ReadG("castbarFillDirection", "RTL") end,
        function(v) SetG("castbarFillDirection", v or "RTL", "MSUF2_CASTBAR_FILL_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_FILL_DIRECTION") end)

    local opposite = W.Toggle(behavior, "Use opposite fill direction for target")
    W.MoveWidget(opposite, behavior, rightX, -126)
    M.BindToggle(ctx, opposite,
        function() return ReadGBool("castbarOpositeDirectionTarget", true) end,
        function(v) SetGBool("castbarOpositeDirectionTarget", v, "MSUF2_CASTBAR_TARGET_DIRECTION", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TARGET_DIRECTION") end)

    local ticks = W.Toggle(behavior, "Show channel tick lines (5)")
    W.MoveWidget(ticks, behavior, rightX, -150)
    M.BindToggle(ctx, ticks,
        function() return ReadGBool("castbarShowChannelTicks", true) end,
        function(v) SetGBool("castbarShowChannelTicks", v, "MSUF2_CASTBAR_TICKS", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_TICKS") end)

    local gcd = b:CollapsibleSection("castbar_gcd", "GCD Bar", 150, false)
    local syncGCDSubs
    local gcdShow = W.Toggle(gcd, "Show GCD bar for instant casts")
    M.BindToggle(ctx, gcdShow,
        function() return ReadGBool("showGCDBar", true) end,
        function(v)
            SetGBool("showGCDBar", v, "MSUF2_CASTBAR_GCD", { castbar = true, preview = true })
            EnsureCastbars()
            if type(_G.MSUF_SetGCDBarEnabled) == "function" then pcall(_G.MSUF_SetGCDBarEnabled, v) end
            ApplyCastbars("MSUF2_CASTBAR_GCD")
            if syncGCDSubs then syncGCDSubs() end
        end)
    local gcdTime = W.Toggle(gcd, "GCD bar: show time text")
    M.BindToggle(ctx, gcdTime,
        function() return ReadGBool("showGCDBarTime", true) end,
        function(v) SetGBool("showGCDBarTime", v, "MSUF2_CASTBAR_GCD_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_TIME") end)
    local gcdSpell = W.Toggle(gcd, "GCD bar: show spell name + icon")
    M.BindToggle(ctx, gcdSpell,
        function() return ReadGBool("showGCDBarSpell", true) end,
        function(v) SetGBool("showGCDBarSpell", v, "MSUF2_CASTBAR_GCD_SPELL", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_GCD_SPELL") end)
    syncGCDSubs = function()
        SetControlsEnabled({ gcdTime, gcdSpell }, ReadGBool("showGCDBar", true))
    end
    M.AddRefresher(ctx, syncGCDSubs)
    syncGCDSubs()

    local textures = b:CollapsibleSection("castbar_textures", "Textures & Outline", 220, false)
    local texLeftX, texRightX = 14, 392
    local tex = W.Dropdown(textures, "Castbar texture", function() return TextureValues(nil) end, 280)
    W.MoveWidget(tex, textures, texLeftX, -42, 300)
    M.BindDropdown(ctx, tex,
        function() return ReadG("castbarTexture", "Blizzard") end,
        function(v) SetG("castbarTexture", v or "Blizzard", "MSUF2_CASTBAR_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_TEXTURE") end)
    local bgTex = W.Dropdown(textures, "Castbar background texture", function() return TextureValues(nil) end, 280)
    W.MoveWidget(bgTex, textures, texLeftX, -96, 300)
    M.BindDropdown(ctx, bgTex,
        function()
            local v = ReadG("castbarBackgroundTexture", nil)
            if type(v) ~= "string" or v == "" then v = ReadG("castbarTexture", "Blizzard") end
            return v
        end,
        function(v) SetG("castbarBackgroundTexture", v or "Blizzard", "MSUF2_CASTBAR_BG_TEXTURE", { castbar = true, preview = true }); ApplyCastbarTextures("MSUF2_CASTBAR_BG_TEXTURE") end)
    local outline = W.Slider(textures, "Outline thickness", 0, 6, 1, 300)
    W.MoveWidget(outline, textures, texRightX, -42, 320)
    M.BindSlider(ctx, outline,
        function() return tonumber(ReadG("castbarOutlineThickness", 1)) or 1 end,
        function(v)
            SetG("castbarOutlineThickness", floor((tonumber(v) or 1) + 0.5), "MSUF2_CASTBAR_OUTLINE", { castbar = true, preview = true })
            Call("MSUF_ApplyCastbarOutlineToAll", true)
            ApplyCastbarTextures("MSUF2_CASTBAR_OUTLINE")
        end)
    for i, spec in ipairs({
        { "castbarShowGlow", "Show castbar glow effect", true, "MSUF2_CASTBAR_GLOW" },
        { "castbarShowLatency", "Show latency indicator", true, "MSUF2_CASTBAR_LATENCY" },
        { "castbarShowSpark", "Show spark (leading edge highlight)", false, "MSUF2_CASTBAR_SPARK" },
        { "castbarSparkOverflow", "Spark extends beyond bar", true, "MSUF2_CASTBAR_SPARK_OVERFLOW" },
    }) do
        local toggle = W.Toggle(textures, spec[2])
        W.MoveWidget(toggle, textures, texRightX, -96 - ((i - 1) * 24))
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], spec[3]) end,
            function(v) SetGBool(spec[1], v, spec[4], { castbar = true, preview = true }); ApplyCastbarTextures(spec[4]) end)
    end

    local empowered = b:CollapsibleSection("castbar_empowered", "Empowered Casts", 130, false)
    local empoweredLeftX, empoweredRightX = 14, 392
    local syncEmpowered
    local empColor = W.Toggle(empowered, "Add color to stages (Empowered casts)")
    W.MoveWidget(empColor, empowered, empoweredLeftX, -42)
    M.BindToggle(ctx, empColor,
        function() return ReadGBool("empowerColorStages", true) end,
        function(v) SetGBool("empowerColorStages", v, "MSUF2_CASTBAR_EMPOWER_COLOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_COLOR") end)
    local empBlink = W.Toggle(empowered, "Add stage blink (Empowered casts)")
    W.MoveWidget(empBlink, empowered, empoweredLeftX, -68)
    M.BindToggle(ctx, empBlink,
        function() return ReadGBool("empowerStageBlink", true) end,
        function(v)
            SetGBool("empowerStageBlink", v, "MSUF2_CASTBAR_EMPOWER_BLINK", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_CASTBAR_EMPOWER_BLINK")
            if syncEmpowered then syncEmpowered() end
        end)
    local blinkTime = W.Slider(empowered, "Stage blink time (sec)", 0.05, 1.00, 0.01, 300)
    W.MoveWidget(blinkTime, empowered, empoweredRightX, -42, 320)
    M.BindSlider(ctx, blinkTime,
        function() return tonumber(ReadG("empowerStageBlinkTime", 0.25)) or 0.25 end,
        function(v) SetG("empowerStageBlinkTime", tonumber(v) or 0.25, "MSUF2_CASTBAR_EMPOWER_TIME", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_EMPOWER_TIME") end)
    syncEmpowered = function()
        SetControlsEnabled({ blinkTime }, ReadGBool("empowerStageBlink", true))
    end
    M.AddRefresher(ctx, syncEmpowered)
    syncEmpowered()

    local text = b:CollapsibleSection("castbar_name_shortening", "Name Shortening", 154, false)
    local textLeftX, textRightX = 14, 392
    local shorten = W.SwitchAt(text, "Spell name shortening", textLeftX, -42, 260)
    local syncNameShortening
    local function NameShorteningEnabled()
        return (tonumber(ReadG("castbarSpellNameShortening", 0)) or 0) == 1
    end
    M.BindToggle(ctx, shorten,
        NameShorteningEnabled,
        function(v)
            local nextValue = v and 1 or 0
            SetG("castbarSpellNameShortening", nextValue, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_CASTBAR_NAME_SHORTEN")
            if syncNameShortening then syncNameShortening() end
        end)

    local maxLen = W.Slider(text, "Max name length", 6, 30, 1, 300)
    W.MoveWidget(maxLen, text, textRightX, -42, 320)
    M.BindSlider(ctx, maxLen,
        function() return tonumber(ReadG("castbarSpellNameMaxLen", 30)) or 30 end,
        function(v) SetG("castbarSpellNameMaxLen", floor((tonumber(v) or 30) + 0.5), "MSUF2_CASTBAR_NAME_MAX", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_MAX") end)
    local reserved = W.Slider(text, "Reserved space", 0, 30, 1, 300)
    W.MoveWidget(reserved, text, textRightX, -96, 320)
    M.BindSlider(ctx, reserved,
        function() return tonumber(ReadG("castbarSpellNameReservedSpace", 8)) or 8 end,
        function(v) SetG("castbarSpellNameReservedSpace", floor((tonumber(v) or 8) + 0.5), "MSUF2_CASTBAR_NAME_RESERVED", { castbar = true, preview = true }); ApplyCastbars("MSUF2_CASTBAR_NAME_RESERVED") end)
    syncNameShortening = function()
        SetControlsEnabled({ maxLen, reserved }, NameShorteningEnabled())
    end
    M.AddRefresher(ctx, syncNameShortening)
    syncNameShortening()

    local focusKick = b:CollapsibleSection("castbar_focus_kick", "Focus Kick", 326, false)
    local focusHint = W.Text(focusKick, "Track interrupts on your focus without showing the focus castbar.", 14, -38, (focusKick._msuf2Width or ctx.width or 720) - 28, T.colors.muted)
    if focusHint and focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    focusKick._msuf2CursorY = -68
    local focusLeftX, focusRightX = 14, 392
    local syncFocusKick
    local focusEnable = W.SwitchAt(focusKick, "Focus interrupt tracker", focusLeftX, -74, 260)
    M.BindToggle(ctx, focusEnable,
        function() return ReadGBool("enableFocusKickIcon", false) end,
        function(v)
            SetGBool("enableFocusKickIcon", v, "MSUF2_FOCUS_KICK_ENABLE", { castbar = true, preview = true })
            Call("MSUF_UpdateFocusKickIconOptions")
            if not v then Call("MSUF_FocusKick_SetPreviewEnabled", false) end
            if syncFocusKick then syncFocusKick() end
        end)
    local focusPreview = W.Toggle(focusKick, "Show on-screen preview")
    W.MoveWidget(focusPreview, focusKick, focusLeftX, -100)
    M.BindToggle(ctx, focusPreview,
        function()
            local fn = _G.MSUF_FocusKick_IsPreviewEnabled
            return type(fn) == "function" and fn() or false
        end,
        function(v) Call("MSUF_FocusKick_SetPreviewEnabled", v and true or false) end)
    local focusW = W.Slider(focusKick, "Width", 16, 128, 1, 300)
    W.MoveWidget(focusW, focusKick, focusRightX, -74, 320)
    M.BindSlider(ctx, focusW,
        function() return tonumber(ReadG("focusKickIconWidth", 40)) or 40 end,
        function(v) SetG("focusKickIconWidth", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_WIDTH", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusH = W.Slider(focusKick, "Height", 16, 128, 1, 300)
    W.MoveWidget(focusH, focusKick, focusRightX, -128, 320)
    M.BindSlider(ctx, focusH,
        function() return tonumber(ReadG("focusKickIconHeight", 40)) or 40 end,
        function(v) SetG("focusKickIconHeight", floor((tonumber(v) or 40) + 0.5), "MSUF2_FOCUS_KICK_HEIGHT", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusText = W.Slider(focusKick, "Text size", 8, 24, 1, 300)
    W.MoveWidget(focusText, focusKick, focusRightX, -182, 320)
    M.BindSlider(ctx, focusText,
        function()
            local v = tonumber(ReadG("focusKickTextSize", nil))
            if v then return v end
            return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
        end,
        function(v)
            SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
            Call("MSUF_FocusKick_ApplyTimeTextFont")
            Call("MSUF_UpdateFocusKickIconOptions")
        end)
    local focusX = W.Slider(focusKick, "X offset", -500, 500, 1, 300)
    W.MoveWidget(focusX, focusKick, focusLeftX, -150, 320)
    M.BindSlider(ctx, focusX,
        function() return tonumber(ReadG("focusKickIconOffsetX", 300)) or 300 end,
        function(v) SetG("focusKickIconOffsetX", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_X", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local focusY = W.Slider(focusKick, "Y offset", -500, 500, 1, 300)
    W.MoveWidget(focusY, focusKick, focusLeftX, -204, 320)
    M.BindSlider(ctx, focusY,
        function() return tonumber(ReadG("focusKickIconOffsetY", 0)) or 0 end,
        function(v) SetG("focusKickIconOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_FOCUS_KICK_Y", { castbar = true, preview = true }); Call("MSUF_UpdateFocusKickIconOptions") end)
    local resetFocus = W.Button(focusKick, "Reset Position", 150)
    W.MoveWidget(resetFocus, focusKick, focusLeftX, -258)
    resetFocus:SetScript("OnClick", function()
        SetG("focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        SetG("focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        Call("MSUF_UpdateFocusKickIconOptions")
        if ctx.refreshers then
            for i = 1, #ctx.refreshers do
                local fn = ctx.refreshers[i]
                if type(fn) == "function" then pcall(fn) end
            end
        end
    end)
    syncFocusKick = function()
        SetControlsEnabled({ focusPreview, focusW, focusH, focusText, focusX, focusY, resetFocus }, ReadGBool("enableFocusKickIcon", false))
    end
    M.AddRefresher(ctx, syncFocusKick)
    syncFocusKick()

    local kick = b:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 360, false)
    W.Text(kick, "Shows a colored indicator on castbars when your interrupt is ready or on cooldown.", 14, -38, ctx.width - 28, T.colors.muted)
    local kickLeftX, kickRightX = 14, 392
    W.LabelAt(kick, "Castbars", kickLeftX, -70, 160, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(kick, "Appearance", kickRightX, -70, 160, "GameFontNormalSmall", T.colors.accent)
    local syncKickReady
    for i, spec in ipairs({
        { "kickReadyShowTarget", "Show on Target castbar" },
        { "kickReadyShowFocus", "Show on Focus castbar" },
        { "kickReadyShowBoss", "Show on Boss castbars" },
    }) do
        local toggle = W.Toggle(kick, spec[2])
        W.MoveWidget(toggle, kick, kickLeftX, -88 - ((i - 1) * 26))
        M.BindToggle(ctx, toggle,
            function() return ReadGBool(spec[1], false) end,
            function(v)
                SetGBool(spec[1], v, "MSUF2_KICK_READY_ENABLE", { castbar = true, preview = true })
                ApplyCastbars("MSUF2_KICK_READY_ENABLE")
                if syncKickReady then syncKickReady() end
            end)
    end
    local style = W.Dropdown(kick, "Indicator style", {
        { value = "border", text = "Castbar border" },
        { value = "box", text = "Color box next to cast" },
    }, 260)
    W.MoveWidget(style, kick, kickRightX, -88, 300)
    M.BindDropdown(ctx, style,
        function() return ReadG("kickReadyStyle", "border") end,
        function(v) SetG("kickReadyStyle", v or "border", "MSUF2_KICK_READY_STYLE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_STYLE") end)
    local size = W.Slider(kick, "Indicator size", 8, 32, 1, 300)
    W.MoveWidget(size, kick, kickRightX, -142, 320)
    M.BindSlider(ctx, size,
        function() return tonumber(ReadG("kickReadySize", 16)) or 16 end,
        function(v) SetG("kickReadySize", floor((tonumber(v) or 16) + 0.5), "MSUF2_KICK_READY_SIZE", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_SIZE") end)
    local auto = W.Toggle(kick, "Auto-size to castbar height")
    W.MoveWidget(auto, kick, kickRightX, -196)
    M.BindToggle(ctx, auto,
        function() return ReadGBool("kickReadyAutoSize", true) end,
        function(v)
            SetGBool("kickReadyAutoSize", v, "MSUF2_KICK_READY_AUTO", { castbar = true, preview = true })
            ApplyCastbars("MSUF2_KICK_READY_AUTO")
            if syncKickReady then syncKickReady() end
        end)
    local colorHint = W.Text(kick, "Ready / cooldown colors: Colors menu > Interrupt Ready Indicator", kickRightX, -228, 370, T.colors.muted)
    W.LabelAt(kick, "Placement", kickLeftX, -178, 160, "GameFontNormalSmall", T.colors.accent)
    local anchor = W.Dropdown(kick, "Anchor", {
        { value = "RIGHT", text = "Right" },
        { value = "LEFT", text = "Left" },
        { value = "TOP", text = "Top" },
        { value = "BOTTOM", text = "Bottom" },
    }, 180)
    W.MoveWidget(anchor, kick, kickLeftX, -196, 260)
    M.BindDropdown(ctx, anchor,
        function() return ReadG("kickReadyAnchor", "RIGHT") end,
        function(v) SetG("kickReadyAnchor", v or "RIGHT", "MSUF2_KICK_READY_ANCHOR", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_ANCHOR") end)
    local offX = W.Slider(kick, "X offset", -50, 50, 1, 300)
    W.MoveWidget(offX, kick, kickLeftX, -250, 320)
    M.BindSlider(ctx, offX,
        function() return tonumber(ReadG("kickReadyOffsetX", 4)) or 4 end,
        function(v) SetG("kickReadyOffsetX", floor((tonumber(v) or 4) + 0.5), "MSUF2_KICK_READY_X", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_X") end)
    local offY = W.Slider(kick, "Y offset", -50, 50, 1, 300)
    W.MoveWidget(offY, kick, kickLeftX, -304, 320)
    M.BindSlider(ctx, offY,
        function() return tonumber(ReadG("kickReadyOffsetY", 0)) or 0 end,
        function(v) SetG("kickReadyOffsetY", floor((tonumber(v) or 0) + 0.5), "MSUF2_KICK_READY_Y", { castbar = true, preview = true }); ApplyCastbars("MSUF2_KICK_READY_Y") end)
    syncKickReady = function()
        local enabled = ReadGBool("kickReadyShowTarget", false) or ReadGBool("kickReadyShowFocus", false) or ReadGBool("kickReadyShowBoss", false)
        local autoOn = ReadGBool("kickReadyAutoSize", true)
        SetControlsEnabled({ style, auto, anchor, offX, offY }, enabled)
        SetControlEnabled(size, enabled and not autoOn)
        SetControlEnabled(colorHint, enabled)
    end
    M.AddRefresher(ctx, syncKickReady)
    syncKickReady()

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 4 })
