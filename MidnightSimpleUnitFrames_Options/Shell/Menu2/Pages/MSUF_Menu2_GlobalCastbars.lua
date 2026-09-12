local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Castbars page.
-- Exposes shared castbar backend/visual/text/timing controls and drives a page-local preview.
-- Actual cast/channel state handling is owned by the castbar runtime modules.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local VT = M.ValueTextList
local floor = math.floor
local max = math.max
local min = math.min
local ReadG, SetG, ReadGBool, SetGBool, TextureValues = GP.ReadG, GP.SetG, GP.ReadGBool, GP.SetGBool, GP.TextureValues
local SetControlEnabled, SetControlsEnabled, ApplyCastbars = GP.SetControlEnabled, GP.SetControlsEnabled, GP.ApplyCastbars
local RegisterControl, Meta, ScheduleCastbarPageWork = GP.RegisterControl, GP.CastbarControlMeta, GP.ScheduleCastbarPageWork
local CASTBAR_PAGE_WORK_DELAY, CASTBAR_PREVIEW_REFRESH_INTERVAL = GP.CASTBAR_PAGE_WORK_DELAY, GP.CASTBAR_PREVIEW_REFRESH_INTERVAL
local BuildCastbarPagePreview = GP.BuildCastbarPagePreview
-- Section builders take the page state table built by CreateCastbarPageState
-- (preview handle, refresh requests and the shared cast-control binders) and
-- re-establish the binder names they use before their unchanged bodies.
local function BuildBehaviorSection(S, secBuilder)
    local BuildCastControlSpecs, ApplyAndRefresh, ApplyCastbarsIfNeeded, ShakeCastPreview = S.BuildCastControlSpecs, S.ApplyAndRefresh, S.ApplyCastbarsIfNeeded, S.ShakeCastPreview
    local behavior = secBuilder:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 196, true)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(behavior, { "cast.interrupt_feedback" }, {
            title = "Interrupt Feedback Color",
            historySource = "menu:castbars-interrupt-feedback-color",
        })
    end
    local leftX, rightX = 14, 392
    local behaviorControls = BuildCastControlSpecs(behavior, {
        { "toggle", "Shake on interrupt", leftX, -42, 260, "castbarInterruptShake", false, "MSUF2_CASTBAR_SHAKE", ApplyAndRefresh },
        { "slider", "Shake strength", leftX, -72, 320, 0, 30, 1, "castbarShakeStrength", 8, "MSUF2_CASTBAR_SHAKE_STRENGTH", function(reason, value, applyQueued) ApplyCastbarsIfNeeded(reason, nil, applyQueued); ShakeCastPreview(value) end },
        { "slider", "Interrupt display duration (sec)", leftX, -126, 320, 0, 5, 0.1, "castbarInterruptFeedbackDuration", 0.5, "MSUF2_CASTBAR_INTERRUPT_DURATION", nil, {
            precise = true,
            setValue = function(value)
                local duration = max(0, min(5, tonumber(value) or 0.5))
                SetG("castbarInterruptFeedbackDuration", duration, "MSUF2_CASTBAR_INTERRUPT_DURATION", { preview = true })
                M.PlayCastbarPreviewInterrupt()
            end,
        } },
        { "toggle", "Always use fill direction for all casts", rightX, -42, 360, "castbarUnifiedDirection", false, "MSUF2_CASTBAR_UNIFIED_DIRECTION", ApplyAndRefresh },
        { "dropdown", "Castbar fill direction", rightX, -72, 300, VT("RTL", "Right to left (default)", "LTR", "Left to right"), "castbarFillDirection", "RTL", "MSUF2_CASTBAR_FILL_DIRECTION", ApplyAndRefresh },
        { "toggle", "Use opposite fill direction for target", rightX, -126, 360, "castbarOpositeDirectionTarget", false, "MSUF2_CASTBAR_TARGET_DIRECTION", ApplyAndRefresh },
        { "toggle", "Spell-specific channel tick markers", rightX, -150, 360, "castbarShowChannelTicks", false, "MSUF2_CASTBAR_TICKS", ApplyAndRefresh },
    }, "behavior")
    if M.AddTooltip then
        M.AddTooltip(behaviorControls.castbarShowChannelTicks,
            "Spell-specific channel tick markers",
            "Shows tick separators on the Player castbar while channeling.\n\nSupported spells use their actual tick count, including supported talent and channel-duration changes. Unsupported channels keep five evenly spaced fallback lines. Custom channel tick settings override the automatic layout.\n\nThe markers are event-driven and add no recurring channel polling.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
end
local function BuildFilterSection(S, secBuilder)
    local BuildCastControlSpecs, ApplyAndRefresh = S.BuildCastControlSpecs, S.ApplyAndRefresh
    local filters = secBuilder:CollapsibleSection("castbar_filters", "Filtering & Feedback", 110, false)
    local filterLeftX = 14
    local filterControls = BuildCastControlSpecs(filters, {
        { "toggle", "Hide profession casts", filterLeftX, -46, 320, "castbarHideTradeSkills", false, "MSUF2_CASTBAR_HIDE_TRADESKILLS", ApplyAndRefresh },
        { "toggle", "Show cast pushback", filterLeftX, -72, 320, "castbarShowPushback", false, "MSUF2_CASTBAR_PUSHBACK", ApplyAndRefresh },
    }, "filters")
    if M.AddTooltip then
        M.AddTooltip(filterControls.castbarHideTradeSkills,
            "Hide profession casts",
            "Keeps crafting and gathering casts off every castbar.\n\nThe profession flag is never a protected value, so this filter also holds for units whose spell data is restricted in PvP.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
        M.AddTooltip(filterControls.castbarShowPushback,
            "Show cast pushback",
            "Appends the delay a cast has accumulated to the spell name, for example \"Fireball +0.4\".\n\nThe delay is read once per cast from the same event that starts the bar.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
end
local function BuildGCDSection(S, secBuilder)
    local ctx, BuildCastControlSpecs = S.ctx, S.BuildCastControlSpecs
    local gcd = secBuilder:CollapsibleSection("castbar_gcd", "GCD Bar", 148, false)
    local gcdLeftX = 14
    local syncGCD
    local gcdControls = BuildCastControlSpecs(gcd, {
        { "toggle", "Show GCD bar for instant casts", gcdLeftX, -46, 300, "showGCDBar", false, "MSUF2_CASTBAR_GCD", nil, { switch = true,
            afterSet = function(_, enabled)
                _G.MSUF_SetGCDBarEnabled(enabled and true or false)
                if syncGCD then syncGCD() end
            end } },
        { "toggle", "GCD bar: show time text", gcdLeftX, -78, 300, "showGCDBarTime", true, "MSUF2_CASTBAR_GCD_TIME" },
        { "toggle", "GCD bar: show spell name + icon", gcdLeftX, -104, 300, "showGCDBarSpell", true, "MSUF2_CASTBAR_GCD_SPELL" },
    }, "gcd")
    if M.AddTooltip then
        M.AddTooltip(gcdControls.showGCDBar,
            "Show GCD bar for instant casts",
            "Runs a short castbar for the global cooldown whenever an instant spell triggers it.\n\nThe fill and time text are driven natively by the client from the real (haste-scaled) GCD duration - no per-frame addon work while the bar runs. A real cast, channel or empower always takes priority.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
    end
    syncGCD = function()
        SetControlsEnabled({ gcdControls.showGCDBarTime, gcdControls.showGCDBarSpell }, ReadGBool("showGCDBar", false))
    end
    M.TrackRefresh(ctx, syncGCD)
end
local function BuildTexturesSection(S, secBuilder)
    local ApplyCastbarTextures, RequestCastPreviewRefresh, BuildCastControlSpecs = S.ApplyCastbarTextures, S.RequestCastPreviewRefresh, S.BuildCastControlSpecs
    local textures = secBuilder:CollapsibleSection("castbar_textures", "Textures & Outline", 220, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(textures, {
            "cast.interruptible", "cast.non_interruptible", "cast.background", "cast.border",
        }, {
            title = "Castbar Colors",
            historySource = "menu:castbars-texture-colors",
        })
    end
    local texLeftX, texRightX = 14, 392
    local function ApplyTexturesAndPreview(reason, _, applyQueued)
        if applyQueued ~= true then ApplyCastbarTextures(reason) end
        RequestCastPreviewRefresh()
    end
    BuildCastControlSpecs(textures, {
        { "dropdown", "Castbar texture", texLeftX, -42, 300, function() return TextureValues(nil) end, "castbarTexture", "Blizzard", "MSUF2_CASTBAR_TEXTURE", ApplyTexturesAndPreview },
        { "dropdown", "Castbar background texture", texLeftX, -96, 300, function() return TextureValues(nil) end, "castbarBackgroundTexture", "Blizzard", "MSUF2_CASTBAR_BG_TEXTURE", ApplyTexturesAndPreview, {
            getValue = function()
                local v = ReadG("castbarBackgroundTexture", nil)
                return (type(v) == "string" and v ~= "") and v or ReadG("castbarTexture", "Blizzard")
            end } },
        { "slider", "Outline thickness", texRightX, -42, 320, 0, 6, 1, "castbarOutlineThickness", 1, "MSUF2_CASTBAR_OUTLINE", ApplyTexturesAndPreview },
        { "toggle", "Show castbar glow effect", texRightX, -96, 360, "castbarShowGlow", false, "MSUF2_CASTBAR_GLOW", ApplyTexturesAndPreview },
        { "toggle", "Show latency indicator", texRightX, -120, 360, "castbarShowLatency", true, "MSUF2_CASTBAR_LATENCY", ApplyTexturesAndPreview },
        { "toggle", "Show spark (leading edge highlight)", texRightX, -144, 360, "castbarShowSpark", false, "MSUF2_CASTBAR_SPARK", ApplyTexturesAndPreview },
        { "toggle", "Spark extends beyond bar", texRightX, -168, 360, "castbarSparkOverflow", true, "MSUF2_CASTBAR_SPARK_OVERFLOW", ApplyTexturesAndPreview },
    }, "textures")
end
local function BuildEmpoweredSection(S, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyCastbarsIfNeeded, ShowEmpoweredPreview = S.ctx, S.BuildCastControlSpecs, S.ApplyCastbarsIfNeeded, S.ShowEmpoweredPreview
    local empowered = secBuilder:CollapsibleSection("castbar_empowered", "Empowered Casts", 130, false)
    local empoweredLeftX, empoweredRightX = 14, 392
    local syncEmpowered
    local function ApplyEmpoweredPreview(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        ShowEmpoweredPreview()
    end
    local empoweredControls = BuildCastControlSpecs(empowered, {
        { "toggle", "Add color to stages (Empowered casts)", empoweredLeftX, -42, 300, "empowerColorStages", true, "MSUF2_CASTBAR_EMPOWER_COLOR", ApplyEmpoweredPreview },
        { "toggle", "Add stage blink (Empowered casts)", empoweredLeftX, -68, 300, "empowerStageBlink", true, "MSUF2_CASTBAR_EMPOWER_BLINK", function(reason, value, applyQueued) ApplyEmpoweredPreview(reason, value, applyQueued); if syncEmpowered then syncEmpowered() end end },
        { "slider", "Stage blink time (sec)", empoweredRightX, -42, 320, 0.05, 1.00, 0.01, "empowerStageBlinkTime", 0.25, "MSUF2_CASTBAR_EMPOWER_TIME", ApplyEmpoweredPreview, { precise = true } },
    }, "empowered")
    local blinkControls = { empoweredControls.empowerStageBlinkTime }
    syncEmpowered = function() SetControlsEnabled(blinkControls, ReadGBool("empowerStageBlink", true)) end
    M.TrackRefresh(ctx, syncEmpowered)
end
local function BuildNameShorteningSection(S, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyAndRefresh, RequestCastPreviewRefresh = S.ctx, S.BuildCastControlSpecs, S.ApplyAndRefresh, S.RequestCastPreviewRefresh
    local text = secBuilder:CollapsibleSection("castbar_name_shortening", "Name Shortening", 154, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(text, {
            title = "Cast Text Settings",
            historyLabel = "Cast text color",
            historySource = "menu:castbars-name-text-color",
            textSettings = {
                scope = "shared",
                kind = "cast",
                colorReferences = { "cast.text" },
                colorTitle = "Cast Text Color",
                subtitle = "Castbar font style follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    local textLeftX, textRightX = 14, 392
    local syncNameShortening
    local function NameShorteningEnabled() return (tonumber(ReadG("castbarSpellNameShortening", 0)) or 0) == 1 end
    local textControls = BuildCastControlSpecs(text, {
        { "toggle", "Spell name shortening", textLeftX, -42, 260, nil, nil, nil, nil, { name = "shorten", switch = true, getValue = NameShorteningEnabled,
            settingKey = "general.castbarSpellNameShortening",
            setValue = function(v)
                SetG("castbarSpellNameShortening", v and 1 or 0, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
                RequestCastPreviewRefresh()
                if syncNameShortening then syncNameShortening() end
            end } },
        { "slider", "Max name length", textRightX, -42, 320, 6, 30, 1, "castbarSpellNameMaxLen", 30, "MSUF2_CASTBAR_NAME_MAX", ApplyAndRefresh },
        { "slider", "Reserved space", textRightX, -96, 320, 0, 30, 1, "castbarSpellNameReservedSpace", 8, "MSUF2_CASTBAR_NAME_RESERVED", ApplyAndRefresh },
    }, "name_shortening")
    local nameShorteningControls = { textControls.castbarSpellNameMaxLen, textControls.castbarSpellNameReservedSpace }
    syncNameShortening = function() SetControlsEnabled(nameShorteningControls, NameShorteningEnabled()) end
    M.TrackRefresh(ctx, syncNameShortening)
end
local function BuildFocusKickSection(S, secBuilder)
    local ctx, BuildCastControlSpecs = S.ctx, S.BuildCastControlSpecs
    local focusKick = secBuilder:CollapsibleSection("castbar_focus_kick", "Focus Kick", 352, false)
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(focusKick, {
            title = "Focus Kick Text & Colors",
            historyLabel = "Focus Kick color",
            historySource = "menu:castbars-focus-kick-colors",
            textSettings = {
                scope = "shared",
                kind = "cast",
                colorReferences = { "font.global", "cast.kick_ready", "cast.kick_not_ready" },
                colorTitle = "Focus Kick Colors",
                subtitle = "Focus Kick text follows the shared Fonts settings.",
                capabilities = { shadow = false, opacity = false, baseline = false },
            },
        })
    end
    local focusHint = W.Text(focusKick, "Track interrupts on your focus with a detached kick icon, optionally alongside the Focus castbar.", 14, -38, (focusKick._msuf2Width or ctx.width or 720) - 28, T.colors.muted)
    if focusHint and focusHint.SetWordWrap then focusHint:SetWordWrap(true) end
    focusKick._msuf2CursorY = -68
    local focusLeftX, focusRightX = 14, 392
    local syncFocusKick
    local focusKickOptionsQueued = false
    local focusKickTextFontQueued = false
    local function ApplyFocusKickOptions()
        if focusKickOptionsQueued then return end
        focusKickOptionsQueued = true
        ScheduleCastbarPageWork("MSUF2_FOCUS_KICK_OPTIONS", CASTBAR_PAGE_WORK_DELAY, function()
            focusKickOptionsQueued = false
            _G.MSUF_UpdateFocusKickIconOptions()
        end)
    end
    local function RequestFocusKickTextFont()
        if focusKickTextFontQueued then return end
        focusKickTextFontQueued = true
        ScheduleCastbarPageWork("MSUF2_FOCUS_KICK_TEXT_FONT", CASTBAR_PAGE_WORK_DELAY, function()
            focusKickTextFontQueued = false
            _G.MSUF_FocusKick_ApplyTimeTextFont()
        end)
    end
    local focusControls = BuildCastControlSpecs(focusKick, {
        { "toggle", "Focus interrupt tracker", focusLeftX, -74, 260, "enableFocusKickIcon", false, "MSUF2_FOCUS_KICK_ENABLE", nil, { name = "enable", switch = true,
            afterSet = function(_, enabled)
                _G.MSUF_FocusKickDriver_ForceUpdate()
                _G.MSUF_KickReady_RefreshAll()
                ApplyFocusKickOptions()
                if not enabled then _G.MSUF_FocusKick_SetPreviewEnabled(false) end
                if syncFocusKick then syncFocusKick() end
            end } },
        { "toggle", "Show on-screen preview", focusLeftX, -100, 300, nil, nil, nil, nil, { name = "preview",
            getValue = function()
                local fn = _G.MSUF_FocusKick_IsPreviewEnabled
                return type(fn) == "function" and fn() or false
            end,
            setValue = function(v) _G.MSUF_FocusKick_SetPreviewEnabled(v and true or false) end, classification = "ephemeral" } },
        { "toggle", "Show castbar with Focus Kick icon", focusLeftX, -126, 340, "focusKickShowCastbar", false, "MSUF2_FOCUS_KICK_CASTBAR", nil, { name = "show_castbar",
            setValue = function(v)
                if M.SetGeneralValue("focusKickShowCastbar", v and true or false, "MSUF2_FOCUS_KICK_CASTBAR",
                    { applyAll = false, preview = false, notify = false }) then
                    _G.MSUF_FocusKickDriver_ForceUpdate()
                end
            end } },
        { "slider", "Width", focusRightX, -74, 320, 16, 128, 1, "focusKickIconWidth", 40, "MSUF2_FOCUS_KICK_WIDTH", ApplyFocusKickOptions, { name = "width" } },
        { "slider", "Height", focusRightX, -128, 320, 16, 128, 1, "focusKickIconHeight", 40, "MSUF2_FOCUS_KICK_HEIGHT", ApplyFocusKickOptions, { name = "height" } },
        { "slider", "Text size", focusRightX, -182, 320, 8, 24, 1, nil, nil, nil, nil, { name = "text",
            settingKey = "general.focusKickTextSize",
            getValue = function()
                local v = tonumber(ReadG("focusKickTextSize", nil))
                if v then return v end
                return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
            end,
            setValue = function(v)
                SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
                RequestFocusKickTextFont()
                ApplyFocusKickOptions()
            end } },
        { "slider", "X offset", focusLeftX, -176, 320, -500, 500, 1, "focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_X", ApplyFocusKickOptions, { name = "x", setDefault = 0 } },
        { "slider", "Y offset", focusLeftX, -230, 320, -500, 500, 1, "focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_Y", ApplyFocusKickOptions, { name = "y" } },
    }, "focus_kick")
    local resetFocus = W.Button(focusKick, "Reset Position", 150)
    W.MoveWidget(resetFocus, focusKick, focusLeftX, -284)
    resetFocus:SetScript("OnClick", function()
        SetG("focusKickIconOffsetX", 300, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        SetG("focusKickIconOffsetY", 0, "MSUF2_FOCUS_KICK_RESET", { castbar = true, preview = true })
        ApplyFocusKickOptions()
        if M.RequestRefresh then M.RequestRefresh(ctx, "castbars-focus-kick-reset") elseif M.Refresh then M.Refresh(ctx) end
    end)
    RegisterControl(resetFocus, Meta("focus_kick.reset_position", "action"), "Reset Position", "button")
    local focusKickControls = { focusControls.preview, focusControls.show_castbar, focusControls.width, focusControls.height, focusControls.text, focusControls.x, focusControls.y, resetFocus }
    syncFocusKick = function() SetControlsEnabled(focusKickControls, ReadGBool("enableFocusKickIcon", false)) end
    M.TrackRefresh(ctx, syncFocusKick)
end
local function BuildInterruptReadySection(S, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyCastbarsIfNeeded, ApplyAndRefresh, RequestCastPreviewRefresh = S.ctx, S.BuildCastControlSpecs, S.ApplyCastbarsIfNeeded, S.ApplyAndRefresh, S.RequestCastPreviewRefresh
    local kick = secBuilder:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 382, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(kick, function()
            if tostring(ReadG("kickReadyStyle", "border") or "border"):lower() == "fill" then
                return { "cast.interruptible", "cast.interrupt_unavailable" }
            end
            return { "cast.kick_ready", "cast.kick_not_ready" }
        end, {
            title = "Interrupt Ready Colors",
            note = "The shown colors follow the selected indicator style.",
            historySource = "menu:castbars-interrupt-ready-colors",
        })
    end
    local kickLeftX, kickRightX = 14, 392
    W.LabelAt(kick, "Castbars", kickLeftX, -38, 160, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(kick, "Appearance", kickRightX, -38, 160, "GameFontNormalSmall", T.colors.accent)
    local syncKickReady
    local function ApplyKickReady(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        _G.MSUF_KickReady_RefreshAll()
        RequestCastPreviewRefresh()
        if syncKickReady then syncKickReady() end
    end
    local kickControls = BuildCastControlSpecs(kick, {
        { "toggle", "Show on Target castbar", kickLeftX, -56, 300, "kickReadyShowTarget", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "toggle", "Show on Focus castbar", kickLeftX, -82, 300, "kickReadyShowFocus", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "toggle", "Show on Boss castbars", kickLeftX, -108, 300, "kickReadyShowBoss", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "toggle", "Show on Arena castbars", kickLeftX, -134, 300, "kickReadyShowArena", false, "MSUF2_KICK_READY_ENABLE", ApplyKickReady },
        { "dropdown", "Indicator style", kickRightX, -56, 300, VT("border", "Castbar border", "box", "Color box next to cast", "fill", "Unavailable cast fill"), "kickReadyStyle", "border", "MSUF2_KICK_READY_STYLE", ApplyKickReady },
        { "slider", "Indicator size", kickRightX, -110, 320, 8, 32, 1, "kickReadySize", 16, "MSUF2_KICK_READY_SIZE", ApplyAndRefresh },
        { "toggle", "Auto-size to castbar height", kickRightX, -164, 360, "kickReadyAutoSize", true, "MSUF2_KICK_READY_AUTO", ApplyKickReady },
    }, "interrupt_ready")
    local colorHint = W.Text(kick, "Colors: Colors menu > Castbar Colors", kickRightX, -196, 370, T.colors.muted)
    W.LabelAt(kick, "Placement", kickLeftX, -172, 160, "GameFontNormalSmall", T.colors.accent)
    M.Assign(kickControls, BuildCastControlSpecs(kick, {
        { "dropdown", "Anchor", kickLeftX, -190, 260, VT("RIGHT", "Right", "LEFT", "Left", "TOP", "Top", "BOTTOM", "Bottom"), "kickReadyAnchor", "RIGHT", "MSUF2_KICK_READY_ANCHOR", ApplyCastbarsIfNeeded },
        { "slider", "X offset", kickLeftX, -244, 320, -50, 50, 1, "kickReadyOffsetX", 4, "MSUF2_KICK_READY_X", ApplyCastbarsIfNeeded },
        { "slider", "Y offset", kickLeftX, -298, 320, -50, 50, 1, "kickReadyOffsetY", 0, "MSUF2_KICK_READY_Y", ApplyCastbarsIfNeeded },
    }, "interrupt_ready.placement"))
    local style, size, auto = kickControls.kickReadyStyle, kickControls.kickReadySize, kickControls.kickReadyAutoSize
    local placementControls = { kickControls.kickReadyAnchor, kickControls.kickReadyOffsetX, kickControls.kickReadyOffsetY }
    syncKickReady = function()
        local enabled = ReadGBool("kickReadyShowTarget", false) or ReadGBool("kickReadyShowFocus", false)
            or ReadGBool("kickReadyShowBoss", false) or ReadGBool("kickReadyShowArena", false)
        local autoOn = ReadGBool("kickReadyAutoSize", true)
        local isFill = ReadG("kickReadyStyle", "border") == "fill"
        SetControlEnabled(style, enabled)
        SetControlEnabled(auto, enabled and not isFill)
        SetControlEnabled(size, enabled and not isFill and not autoOn)
        SetControlsEnabled(placementControls, enabled and not isFill)
        SetControlEnabled(colorHint, enabled)
    end
    M.TrackRefresh(ctx, syncKickReady)
end
local function CreateCastbarPageState(ctx, b)
    local function ApplyCastbarTextures(reason)
        _G.MSUF_UpdateCastbarTextures_Immediate()
        _G.MSUF_UpdateBossCastbarPreview()
        ApplyCastbars(reason or "MSUF2_CASTBAR_TEXTURES")
    end
    local castPreview, castPreviewSection, fixedPreview = BuildCastbarPagePreview(ctx, b)
    local function RefreshCastPreview() if castPreview and castPreview.Refresh then castPreview:Refresh() end end
    local castPreviewRefreshQueued = false
    local function RequestCastPreviewRefresh()
        if castPreviewRefreshQueued then return end
        castPreviewRefreshQueued = true
        ScheduleCastbarPageWork("MSUF2_CASTBAR_PAGE_PREVIEW", CASTBAR_PREVIEW_REFRESH_INTERVAL, function()
            castPreviewRefreshQueued = false
            RefreshCastPreview()
        end)
    end
    -- Castbar uses the same bounded Preview slot as every other page-level
    -- preview; only the settings sections below it participate in scrolling.
    if castPreviewSection and fixedPreview then fixedPreview.onActivate = RequestCastPreviewRefresh end
    local function ShakeCastPreview(strength) if castPreview and castPreview.PlayShake then castPreview:PlayShake(strength, false) end end
    local function ShowEmpoweredPreview() M.SetCastbarPreviewType("empowered", 0.62) end
    local function MoveToggle(toggle, parent, x, y, labelWidth)
        W.MoveWidget(toggle, parent, x, y)
        if toggle and toggle._msuf2Label and toggle._msuf2Label.SetWidth then toggle._msuf2Label:SetWidth(max(40, tonumber(labelWidth) or 260)) end
        return toggle
    end
    local function BindCastToggle(parent, label, x, y, labelWidth, key, default, reason, afterSet, opts)
        opts = opts or {}
        local toggle = opts.switch and W.SwitchAt(parent, label, x, y, labelWidth) or W.Toggle(parent, label)
        if not opts.switch then MoveToggle(toggle, parent, x, y, labelWidth) end
        M.BindBoolWidget(ctx, toggle,
            opts.getValue or function() return ReadGBool(key, default) end,
            opts.setValue or function(v)
                SetGBool(key, v, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, v, true) end
            end,
            opts.meta)
        return toggle
    end
    local function BindCastSlider(parent, label, x, y, width, minValue, maxValue, step, key, default, reason, afterSet, opts)
        opts = opts or {}
        local slider = W.Slider(parent, label, minValue, maxValue, step, 300)
        W.MoveWidget(slider, parent, x, y, width or 320)
        local metadata = {}
        if type(opts.meta) == "table" then for metaKey, value in pairs(opts.meta) do metadata[metaKey] = value end end
        metadata.step, metadata.roundStep = step, not opts.precise
        M.BindNumberWidget(ctx, slider,
            opts.getValue or function() return tonumber(ReadG(key, default)) or default end,
            opts.setValue or function(v)
                local fallback = opts.setDefault ~= nil and opts.setDefault or default
                local nextValue = opts.precise and (tonumber(v) or fallback) or floor((tonumber(v) or fallback) + 0.5)
                SetG(key, nextValue, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, nextValue, true) end
            end,
            opts.setDefault ~= nil and opts.setDefault or default, metadata)
        return slider
    end
    local function BindCastDropdown(parent, label, x, y, width, values, key, default, reason, afterSet, opts)
        opts = opts or {}
        local getValue, setValue = opts.getValue, opts.setValue
        if key then
            getValue = getValue or function() return ReadG(key, default) end
            setValue = setValue or function(v)
                local normalize = opts.normalize
                local nextValue = normalize and normalize(v, default) or (v or default)
                SetG(key, nextValue, reason, { castbar = true, preview = true })
                if afterSet then afterSet(reason, nextValue, true) end
            end
        end
        local dropdown = W.Dropdown(parent, label, values, width or 260)
        W.MoveWidget(dropdown, parent, x, y, width or 300)
        M.BindDropdownWidget(ctx, dropdown, getValue, setValue, opts.meta)
        return dropdown
    end
    local CAST_SPEC_OPTION_INDEX = { toggle = 10, slider = 13, dropdown = 11 }
    local function BuildCastControlSpecs(parent, specs, semanticPrefix)
        return M.BuildControlSpecs(specs, {
            toggle = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[6]
                local opts = spec[CAST_SPEC_OPTION_INDEX.toggle] or {}
                local selectedValue3
                if not (opts.classification == "ephemeral") then selectedValue3 = { settingKey = opts.settingKey or (key and ("general." .. key)) } end
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    selectedValue3)
                return BindCastToggle(parent, label, x, y, width, key, spec[7], spec[8], opts.afterSet or spec[9], opts), opts.name or key or i
            end,
            slider = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[9]
                local opts = spec[CAST_SPEC_OPTION_INDEX.slider] or {}
                local selectedValue2
                if not (opts.classification == "ephemeral") then selectedValue2 = { settingKey = opts.settingKey or (key and ("general." .. key)) } end
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    selectedValue2)
                return BindCastSlider(parent, label, x, y, width, spec[6], spec[7], spec[8], key, spec[10], spec[11], opts.afterSet or spec[12], opts), opts.name or key or i
            end,
            dropdown = function(spec, i)
                local label, x, y, width, key = spec[2], spec[3], spec[4], spec[5], spec[7]
                local opts = spec[CAST_SPEC_OPTION_INDEX.dropdown] or {}
                local selectedValue1
                if not (opts.classification == "ephemeral") then selectedValue1 = { settingKey = opts.settingKey or (key and ("general." .. key)) } end
                opts.meta = opts.meta or Meta(semanticPrefix .. "." .. tostring(key or opts.name), opts.classification,
                    selectedValue1)
                return BindCastDropdown(parent, label, x, y, width, spec[6], key, spec[8], spec[9], opts.afterSet or spec[10], opts), opts.name or key or i
            end,
        })
    end
    local function ApplyCastbarsIfNeeded(reason, _, applyQueued)
        if applyQueued ~= true then ApplyCastbars(reason) end
    end
    local function ApplyAndRefresh(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        RequestCastPreviewRefresh()
    end
    -- Sections route through the shared lazy-section registry: the open
    -- Behavior section defers its content one frame behind its shell, closed
    -- sections build on their first expand, and hidden search-index builds
    -- stay synchronous inside BuildSectionLazy.
    local function LazyCastbarSection(spec)
        local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
        if type(buildLazy) == "function" then return buildLazy(ctx, b, nil, spec) end
        return spec.build(ctx, b)
    end
    return {
        ctx = ctx, b = b, castPreview = castPreview, castPreviewSection = castPreviewSection, fixedPreview = fixedPreview,
        ApplyCastbarTextures = ApplyCastbarTextures, RefreshCastPreview = RefreshCastPreview,
        RequestCastPreviewRefresh = RequestCastPreviewRefresh, ShakeCastPreview = ShakeCastPreview,
        ShowEmpoweredPreview = ShowEmpoweredPreview, MoveToggle = MoveToggle, BindCastToggle = BindCastToggle,
        BindCastSlider = BindCastSlider, BindCastDropdown = BindCastDropdown, BuildCastControlSpecs = BuildCastControlSpecs,
        ApplyCastbarsIfNeeded = ApplyCastbarsIfNeeded, ApplyAndRefresh = ApplyAndRefresh, LazyCastbarSection = LazyCastbarSection,
    }
end
local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Castbar", "Castbar behavior, textures and interrupt indicators.", 72)
    local S = CreateCastbarPageState(ctx, b)
    local LazyCastbarSection = S.LazyCastbarSection
    LazyCastbarSection({ sectionId = "castbar_behavior", title = "Shake & Fill Direction", height = 196, defaultOpen = true, build = function(_, secBuilder) return BuildBehaviorSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_filters", title = "Filtering & Feedback", height = 110, build = function(_, secBuilder) return BuildFilterSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_gcd", title = "GCD Bar", height = 148, build = function(_, secBuilder) return BuildGCDSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_textures", title = "Textures & Outline", height = 220, build = function(_, secBuilder) return BuildTexturesSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_empowered", title = "Empowered Casts", height = 130, build = function(_, secBuilder) return BuildEmpoweredSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_name_shortening", title = "Name Shortening", height = 154, build = function(_, secBuilder) return BuildNameShorteningSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_focus_kick", title = "Focus Kick", height = 352, build = function(_, secBuilder) return BuildFocusKickSection(S, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_interrupt_ready", title = "Interrupt Ready Indicator", height = 382, build = function(_, secBuilder) return BuildInterruptReadySection(S, secBuilder) end })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 6 })
