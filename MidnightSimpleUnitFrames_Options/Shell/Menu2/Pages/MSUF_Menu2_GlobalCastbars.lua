local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Castbars page.
-- Exposes shared castbar backend/visual/text/timing controls and drives a page-local preview.
-- Actual cast/channel state handling is owned by the castbar runtime modules.
local W = M.Widgets
local Schema = M.ControlSchema
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
-- The GCD bar is filled only C-side: MSUF_CastbarGCD.lua has no Lua fallback and
-- stops without C_Spell.GetSpellCooldownDuration or StatusBar:SetTimerDuration.
-- Probe the capability once, never the flavor, and offer the section only when
-- the client can drive the bar. The probe bar is created only when the API exists.
local gcdBarSupported
local function GCDBarSupported()
    if gcdBarSupported ~= nil then return gcdBarSupported end
    local spellAPI = _G.C_Spell
    gcdBarSupported = false
    if type(spellAPI) == "table" and type(spellAPI.GetSpellCooldownDuration) == "function" then
        local castbar = MSUF.Castbars.Frames.Get("player")
        local bar = castbar and castbar.statusBar
        if not bar and type(_G.CreateFrame) == "function" then bar = PixelLayoutRegion(_G.CreateFrame("StatusBar")) end
        gcdBarSupported = bar ~= nil and type(bar.SetTimerDuration) == "function"
        -- The runtime's own answer adds what only it knows: WoW Forever arms
        -- the bar only while its spell data has the GCD spell.
        local runtimeSupported = _G.MSUF_GCDBar_IsSupported
        if gcdBarSupported and type(runtimeSupported) == "function" then
            gcdBarSupported = runtimeSupported() == true
        end
    end
    return gcdBarSupported
end
-- Search drops the GCD Bar rows where this page never builds the section.
M.CastbarGCDBarSupported = GCDBarSupported
-- Section builders take the page state table built by CreateCastbarPageState
-- (preview handle, refresh requests and the shared cast-control binders) and
-- re-establish the binder names they use before their unchanged bodies.
local function BuildBehaviorSection(PageState, secBuilder)
    local BuildCastControlSpecs, ApplyAndRefresh, ApplyCastbarsIfNeeded, ShakeCastPreview = PageState.BuildCastControlSpecs,
        PageState.ApplyAndRefresh, PageState.ApplyCastbarsIfNeeded, PageState.ShakeCastPreview
    local behavior = Schema.Section(secBuilder:CollapsibleSection("castbar_behavior", "Shake & Fill Direction", 224, true), PageState.ctx.key)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(behavior, { "cast.interrupt_feedback" }, {
            title = "Interrupt Feedback Color",
            historySource = "menu:castbars-interrupt-feedback-color",
        })
    end
    local leftX, rightX = 14, 392
    local syncLastTick
    local function ApplyTicksAndSync(...)
        ApplyAndRefresh(...)
        if syncLastTick then syncLastTick() end
    end
    local behaviorControls = BuildCastControlSpecs(behavior, {
        { "flowToggle", "castbarInterruptShake", true, { "Shake on interrupt" }, { leftX, -42 },
            labelWidth = 260, reason = "MSUF2_CASTBAR_SHAKE", afterWrite = ApplyAndRefresh },
        { "slider", "castbarShakeStrength", 8, { "Shake strength", 0, 30, 1, 300 }, { leftX, -72, 320 },
            reason = "MSUF2_CASTBAR_SHAKE_STRENGTH",
            afterWrite = function(reason, value, applyQueued) ApplyCastbarsIfNeeded(reason, nil, applyQueued); ShakeCastPreview(value) end },
        { "slider", "castbarInterruptFeedbackDuration", 0.5, { "Interrupt display duration (sec)", 0, 5, 0.1, 300 }, { leftX, -126, 320 },
            reason = "MSUF2_CASTBAR_INTERRUPT_DURATION", precise = true, set = function(value)
                local duration = max(0, min(5, tonumber(value) or 0.5))
                SetG("castbarInterruptFeedbackDuration", duration, "MSUF2_CASTBAR_INTERRUPT_DURATION", { preview = true })
                MSUF.Castbars.Config.Refresh()
                M.PlayCastbarPreviewInterrupt()
            end },
        { "flowToggle", "castbarUnifiedDirection", false, { "Always use fill direction for all casts" }, { rightX, -42 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_UNIFIED_DIRECTION", afterWrite = ApplyAndRefresh },
        { "dropdown", "castbarFillDirection", "RTL", { "Castbar fill direction", VT("RTL", "Right to left (default)", "LTR",
            "Left to right"), 300 }, { rightX, -72, 300 },
            reason = "MSUF2_CASTBAR_FILL_DIRECTION", afterWrite = ApplyAndRefresh },
        { "flowToggle", "castbarOpositeDirectionTarget", false, { "Use opposite fill direction for target" }, { rightX, -126 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_TARGET_DIRECTION", afterWrite = ApplyAndRefresh },
        { "flowToggle", "castbarShowChannelTicks", false, { "Spell-specific channel tick markers" }, { rightX, -150 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_TICKS", afterWrite = ApplyTicksAndSync },
        { "flowToggle", "castbarAccentLastTick", false, { "Highlight last channel tick" }, { rightX, -178 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_LAST_TICK", afterWrite = ApplyAndRefresh },
    }, "behavior")
    if M.AddTooltip then
        M.AddTooltip(behaviorControls.castbarShowChannelTicks,
            "Spell-specific channel tick markers",
            "Shows tick separators on the Player castbar while channeling.\n\nSupported spells use their actual tick count, including supported talent and channel-duration changes. Unsupported channels keep five evenly spaced fallback lines. Custom channel tick settings override the automatic layout.\n\nThe markers are event-driven and add no recurring channel polling.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
        local tip = { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" }
        M.AddTooltip(behaviorControls.castbarInterruptShake, "Shake on interrupt",
            "Jolts a castbar sideways when the cast it shows is interrupted, so kicks are easy to notice. Applies to every castbar.", tip)
        M.AddTooltip(behaviorControls.castbarShakeStrength, "Shake strength",
            "How far the bar jolts, in pixels. 0 turns the shake off even while Shake on interrupt is enabled.", tip)
        M.AddTooltip(behaviorControls.castbarInterruptFeedbackDuration, "Interrupt display duration (sec)",
            "How long an interrupted cast stays visible with the interrupt message before the bar hides. 0 hides it immediately.", tip)
        M.AddTooltip(behaviorControls.castbarUnifiedDirection, "Always use fill direction for all casts",
            "Makes channeled spells fill up like normal casts. Off keeps the classic look where a channel starts full and drains.", tip)
        M.AddTooltip(behaviorControls.castbarFillDirection, "Castbar fill direction",
            "Which way the bar grows during a cast, on every castbar. Channels drain the other way unless Always use fill direction for all casts is on.", tip)
        M.AddTooltip(behaviorControls.castbarOpositeDirectionTarget, "Use opposite fill direction for target",
            "Flips the fill direction on the Target castbar only, so it can mirror your Player castbar when the two frames face each other.", tip)
    end
    -- The accent marks the last of the channel tick markers, so it needs them on.
    local lastTick = behaviorControls.castbarAccentLastTick
    local function TicksOn() return ReadGBool("castbarShowChannelTicks", false) end
    if W.SetControlDisabledReason and W.TurnOnReason then
        W.SetControlDisabledReason(lastTick, W.TurnOnReason("Spell-specific channel tick markers", TicksOn))
    end
    syncLastTick = function() SetControlEnabled(lastTick, TicksOn()) end
    M.TrackRefresh(PageState.ctx, syncLastTick)
end
local function BuildFilterSection(PageState, secBuilder)
    local BuildCastControlSpecs, ApplyAndRefresh = PageState.BuildCastControlSpecs, PageState.ApplyAndRefresh
    local filters = Schema.Section(secBuilder:CollapsibleSection("castbar_filters", "Filtering & Feedback", 110, false), PageState.ctx.key)
    local filterLeftX = 14
    local filterControls = BuildCastControlSpecs(filters, {
        { "flowToggle", "castbarHideTradeSkills", false, { "Hide profession casts" }, { filterLeftX, -46 },
            labelWidth = 320, reason = "MSUF2_CASTBAR_HIDE_TRADESKILLS", afterWrite = ApplyAndRefresh },
        { "flowToggle", "castbarShowPushback", false, { "Show cast pushback" }, { filterLeftX, -72 },
            labelWidth = 320, reason = "MSUF2_CASTBAR_PUSHBACK", afterWrite = ApplyAndRefresh },
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
local function BuildGCDSection(PageState, secBuilder)
    local ctx, BuildCastControlSpecs = PageState.ctx, PageState.BuildCastControlSpecs
    local gcd = Schema.Section(secBuilder:CollapsibleSection("castbar_gcd", "GCD Bar", 346, false), PageState.ctx.key)
    local gcdLeftX = 14
    local syncGCD
    -- The separate-bar controls depend on the master switch and on "Place GCD
    -- bar separately"; re-sync their enabled state after either changes.
    local function ApplyDetached(...)
        local refreshLayout = _G.MSUF_GCDBar_RefreshLayout
        if type(refreshLayout) == "function" then refreshLayout(...) end
        if syncGCD then syncGCD() end
    end
    local gcdControls = BuildCastControlSpecs(gcd, {
        { "switch", "showGCDBar", false, { "Show GCD bar for instant casts", gcdLeftX, -46, 300 },
            reason = "MSUF2_CASTBAR_GCD", afterWrite = function(_, enabled)
                _G.MSUF_SetGCDBarEnabled(enabled and true or false)
                if syncGCD then syncGCD() end
            end },
        { "flowToggle", "showGCDBarTime", true, { "GCD bar: show time text" }, { gcdLeftX, -78 },
            labelWidth = 300, reason = "MSUF2_CASTBAR_GCD_TIME" },
        { "flowToggle", "showGCDBarSpell", true, { "GCD bar: show spell name + icon" }, { gcdLeftX, -104 },
            labelWidth = 300, reason = "MSUF2_CASTBAR_GCD_SPELL" },
        { "flowToggle", "gcdBarDetached", false, { "Place GCD bar separately" }, { gcdLeftX, -134 },
            labelWidth = 340, reason = "MSUF2_CASTBAR_GCD_DETACHED", afterWrite = ApplyDetached },
        { "flowToggle", "gcdBarIdle", false, { "Keep separate GCD background visible" }, { gcdLeftX, -160 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_GCD_IDLE", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "flowToggle", "gcdBarCombatOnly", false, { "Separate GCD bar only in combat" }, { gcdLeftX, -186 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_GCD_COMBAT", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "slider", "gcdBarWidth", 180, { "Separate GCD bar width", 40, 600, 1, 300 }, { gcdLeftX, -218, 320 },
            reason = "MSUF2_CASTBAR_GCD_WIDTH", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "slider", "gcdBarHeight", 12, { "Separate GCD bar height", 4, 50, 1, 300 }, { gcdLeftX, -272, 320 },
            reason = "MSUF2_CASTBAR_GCD_HEIGHT", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "slider", "gcdBarX", 0, { "Separate GCD horizontal position", -2000, 2000, 1, 300 }, { 392, -46, 320 },
            reason = "MSUF2_CASTBAR_GCD_X", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "slider", "gcdBarY", -180, { "Separate GCD vertical position", -1500, 1500, 1, 300 }, { 392, -104, 320 },
            reason = "MSUF2_CASTBAR_GCD_Y", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
        { "slider", "gcdBarOpacity", 100, { "Separate GCD opacity (percent)", 0, 100, 5, 300 }, { 392, -162, 320 },
            reason = "MSUF2_CASTBAR_GCD_ALPHA", afterWrite = _G.MSUF_GCDBar_RefreshLayout },
    }, "gcd")
    if M.AddTooltip then
        M.AddTooltip(gcdControls.showGCDBar,
            "Show GCD bar for instant casts",
            "Runs a short castbar for the global cooldown whenever an instant spell triggers it.\n\nThe fill and time text are driven natively by the client from the real (haste-scaled) GCD duration - no per-frame addon work while the bar runs. A real cast, channel or empower always takes priority.",
            { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" })
        local tip = { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" }
        M.AddTooltip(gcdControls.showGCDBarTime, "GCD bar: show time text",
            "Shows the remaining global cooldown in the Player castbar time text while the GCD bar runs.", tip)
        M.AddTooltip(gcdControls.showGCDBarSpell, "GCD bar: show spell name + icon",
            "Writes the instant spell's name on the GCD bar and shows its icon. Off leaves the spell text blank.", tip)
    end
    local masterControls = { gcdControls.showGCDBarTime, gcdControls.showGCDBarSpell, gcdControls.gcdBarDetached }
    local detachedControls = {}
    for _, key in ipairs({ "gcdBarIdle", "gcdBarCombatOnly", "gcdBarWidth", "gcdBarHeight", "gcdBarX", "gcdBarY", "gcdBarOpacity" }) do
        detachedControls[#detachedControls + 1] = gcdControls[key]
    end
    if W.SetControlsDisabledReason and W.TurnOnReason then
        local masterReason = W.TurnOnReason("Show GCD bar for instant casts", function() return ReadGBool("showGCDBar", false) end)
        local detachedReason = W.TurnOnReason("Place GCD bar separately", function() return ReadGBool("gcdBarDetached", false) end)
        W.SetControlsDisabledReason(masterControls, masterReason)
        W.SetControlsDisabledReason(detachedControls, function(control) return masterReason(control) or detachedReason(control) end)
    end
    syncGCD = function()
        local master = ReadGBool("showGCDBar", false)
        SetControlsEnabled(masterControls, master)
        SetControlsEnabled(detachedControls, master and ReadGBool("gcdBarDetached", false))
    end
    M.TrackRefresh(ctx, syncGCD)
end
local function BuildTexturesSection(PageState, secBuilder)
    local ApplyCastbarTextures, RequestCastPreviewRefresh, BuildCastControlSpecs = PageState.ApplyCastbarTextures,
        PageState.RequestCastPreviewRefresh, PageState.BuildCastControlSpecs
    local textures = Schema.Section(secBuilder:CollapsibleSection("castbar_textures", "Textures & Outline", 246, false), PageState.ctx.key)
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
    local textureControls = BuildCastControlSpecs(textures, {
        { "dropdown", "castbarTexture", "Blizzard", { "Castbar texture", function() return TextureValues(nil) end, 300 }, { texLeftX, -42, 300 },
            reason = "MSUF2_CASTBAR_TEXTURE", afterWrite = ApplyTexturesAndPreview },
        { "dropdown", "castbarBackgroundTexture", "Blizzard", { "Castbar background texture",
            function() return TextureValues(nil) end, 300 }, { texLeftX, -96, 300 },
            reason = "MSUF2_CASTBAR_BG_TEXTURE", afterWrite = ApplyTexturesAndPreview, get = function()
                local v = ReadG("castbarBackgroundTexture", nil)
                return (type(v) == "string" and v ~= "") and v or ReadG("castbarTexture", "Blizzard")
            end },
        { "slider", "castbarOutlineThickness", 1, { "Outline thickness", 0, 6, 1, 300 }, { texRightX, -42, 320 },
            reason = "MSUF2_CASTBAR_OUTLINE", afterWrite = ApplyTexturesAndPreview },
        { "flowToggle", "castbarShowGlow", false, { "Show castbar glow effect" }, { texRightX, -96 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_GLOW", afterWrite = ApplyTexturesAndPreview },
        { "flowToggle", "castbarShowLatency", true, { "Show latency indicator" }, { texRightX, -120 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_LATENCY", afterWrite = ApplyTexturesAndPreview },
        { "flowToggle", "castbarShowSpark", false, { "Show spark (leading edge highlight)" }, { texRightX, -144 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_SPARK", afterWrite = ApplyTexturesAndPreview },
        { "flowToggle", "castbarSparkOverflow", true, { "Spark extends beyond bar" }, { texRightX, -168 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_SPARK_OVERFLOW", afterWrite = ApplyTexturesAndPreview },
        { "flowToggle", "castbarShowLatencyText", false, { "Show network latency in milliseconds" }, { texRightX, -196 },
            labelWidth = 360, reason = "MSUF2_CASTBAR_LATENCY_TEXT", afterWrite = ApplyTexturesAndPreview },
    }, "textures")
    if M.AddTooltip and textureControls then
        local tip = { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" }
        M.AddTooltip(textureControls.castbarOutlineThickness, "Outline thickness",
            "Width of the border around each castbar, in pixels; 0 removes it. The Interrupt Ready border style colors this border, so keep it above 0 for that style.", tip)
        M.AddTooltip(textureControls.castbarShowGlow, "Show castbar glow effect",
            "Gradually brightens the bar toward white as a cast nears its end, so the last moment of a cast is easy to spot.", tip)
        M.AddTooltip(textureControls.castbarShowLatency, "Show latency indicator",
            "Shades the end of the Player castbar by your latency or spell queue window, whichever is larger, to help time your next spell. Player castbar only.", tip)
        M.AddTooltip(textureControls.castbarSparkOverflow, "Spark extends beyond bar",
            "Lets the spark stick out above and below the bar at about twice its height. Only matters while the spark is shown.", tip)
    end
end
local function BuildEmpoweredSection(PageState, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyCastbarsIfNeeded, ShowEmpoweredPreview = PageState.ctx,
        PageState.BuildCastControlSpecs, PageState.ApplyCastbarsIfNeeded, PageState.ShowEmpoweredPreview
    local empowered = Schema.Section(secBuilder:CollapsibleSection("castbar_empowered", "Empowered Casts", 130, false), PageState.ctx.key)
    local empoweredLeftX, empoweredRightX = 14, 392
    local syncEmpowered
    local function ApplyEmpoweredPreview(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        ShowEmpoweredPreview()
    end
    local empoweredControls = BuildCastControlSpecs(empowered, {
        { "flowToggle", "empowerColorStages", true, { "Add color to stages (Empowered casts)" }, { empoweredLeftX, -42 },
            labelWidth = 300, reason = "MSUF2_CASTBAR_EMPOWER_COLOR", afterWrite = ApplyEmpoweredPreview },
        { "flowToggle", "empowerStageBlink", true, { "Add stage blink (Empowered casts)" }, { empoweredLeftX, -68 },
            labelWidth = 300, reason = "MSUF2_CASTBAR_EMPOWER_BLINK", afterWrite = function(reason, value, applyQueued)
                ApplyEmpoweredPreview(reason, value, applyQueued)
                if syncEmpowered then syncEmpowered() end
            end },
        { "slider", "empowerStageBlinkTime", 0.25, { "Stage blink time (sec)", 0.05, 1.00, 0.01, 300 }, { empoweredRightX, -42, 320 },
            reason = "MSUF2_CASTBAR_EMPOWER_TIME", afterWrite = ApplyEmpoweredPreview, precise = true },
    }, "empowered")
    local blinkControls = { empoweredControls.empowerStageBlinkTime }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        W.SetControlsDisabledReason(blinkControls,
            W.TurnOnReason("Add stage blink (Empowered casts)", function() return ReadGBool("empowerStageBlink", true) end))
    end
    syncEmpowered = function() SetControlsEnabled(blinkControls, ReadGBool("empowerStageBlink", true)) end
    M.TrackRefresh(ctx, syncEmpowered)
end
local function BuildNameShorteningSection(PageState, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyAndRefresh, RequestCastPreviewRefresh = PageState.ctx,
        PageState.BuildCastControlSpecs, PageState.ApplyAndRefresh, PageState.RequestCastPreviewRefresh
    local text = Schema.Section(secBuilder:CollapsibleSection("castbar_name_shortening", "Name Shortening", 154, false), PageState.ctx.key)
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
        { "switch", "shorten", nil, { "Spell name shortening", textLeftX, -42, 260 },
            name = "shorten", get = NameShorteningEnabled, settingKey = "general.castbarSpellNameShortening", set = function(v)
                SetG("castbarSpellNameShortening", v and 1 or 0, "MSUF2_CASTBAR_NAME_SHORTEN", { castbar = true, preview = true })
                RequestCastPreviewRefresh()
                if syncNameShortening then syncNameShortening() end
            end },
        { "slider", "castbarSpellNameMaxLen", 30, { "Max name length", 6, 30, 1, 300 }, { textRightX, -42, 320 },
            reason = "MSUF2_CASTBAR_NAME_MAX", afterWrite = ApplyAndRefresh },
        { "slider", "castbarSpellNameReservedSpace", 8, { "Reserved space", 0, 30, 1, 300 }, { textRightX, -96, 320 },
            reason = "MSUF2_CASTBAR_NAME_RESERVED", afterWrite = ApplyAndRefresh },
    }, "name_shortening")
    local nameShorteningControls = { textControls.castbarSpellNameMaxLen, textControls.castbarSpellNameReservedSpace }
    if M.AddTooltip then
        local tip = { hook = true, titleAsLine = true, labelHit = true, owner = "ANCHOR_RIGHT" }
        M.AddTooltip(textControls.shorten, "Spell name shortening",
            "Cuts long spell names on every castbar to Max name length and marks the cut with '...'. Reserved space applies only while this is on.", tip)
        M.AddTooltip(textControls.castbarSpellNameMaxLen, "Max name length",
            "Spell names longer than this many characters are cut and end in '...'. Names are also trimmed to fit the free bar width, so narrow bars may show fewer.", tip)
        M.AddTooltip(textControls.castbarSpellNameReservedSpace, "Reserved space",
            "Keeps this many extra pixels free next to the spell name, on top of the room kept for the cast time, so long names stay clear of the timer.", tip)
    end
    if W.SetControlsDisabledReason and W.TurnOnReason then
        W.SetControlsDisabledReason(nameShorteningControls, W.TurnOnReason("Spell name shortening", NameShorteningEnabled))
    end
    syncNameShortening = function() SetControlsEnabled(nameShorteningControls, NameShorteningEnabled()) end
    M.TrackRefresh(ctx, syncNameShortening)
end
local function BuildFocusKickSection(PageState, secBuilder)
    local ctx, BuildCastControlSpecs = PageState.ctx, PageState.BuildCastControlSpecs
    local focusKick = Schema.Section(secBuilder:CollapsibleSection("castbar_focus_kick", "Focus Kick", 352, false), PageState.ctx.key)
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
    local focusHint = Schema.Build(ctx, focusKick, {
        { "text", "menu2.opt_castbar.focusKick.focusHint", nil,
            { "Track interrupts on your focus with a detached kick icon, optionally alongside the Focus castbar.", 14, -38,
            (focusKick._msuf2Width or ctx.width or 720) - 28, T.colors.muted } },
    })["menu2.opt_castbar.focusKick.focusHint"]
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
        { "switch", "enableFocusKickIcon", false, { "Focus interrupt tracker", focusLeftX, -74, 260 },
            reason = "MSUF2_FOCUS_KICK_ENABLE", name = "enable", afterWrite = function(_, enabled)
                _G.MSUF_FocusKickDriver_ForceUpdate()
                _G.MSUF_KickReady_RefreshAll()
                ApplyFocusKickOptions()
                if not enabled then _G.MSUF_FocusKick_SetPreviewEnabled(false) end
                if syncFocusKick then syncFocusKick() end
            end },
        { "flowToggle", "preview", nil, { "Show on-screen preview" }, { focusLeftX, -100 },
            labelWidth = 300, name = "preview", get = function()
                local fn = _G.MSUF_FocusKick_IsPreviewEnabled
                return type(fn) == "function" and fn() or false
            end, set = function(v) _G.MSUF_FocusKick_SetPreviewEnabled(v and true or false) end, classification = "ephemeral" },
        { "flowToggle", "focusKickShowCastbar", false, { "Show castbar with Focus Kick icon" }, { focusLeftX, -126 },
            labelWidth = 340, reason = "MSUF2_FOCUS_KICK_CASTBAR", name = "show_castbar", set = function(v)
                if M.SetGeneralValue("focusKickShowCastbar", v and true or false, "MSUF2_FOCUS_KICK_CASTBAR",
                    { applyAll = false, preview = false, notify = false }) then
                    MSUF.Castbars.Config.Refresh()
                    _G.MSUF_FocusKickDriver_ForceUpdate()
                end
            end },
        { "slider", "focusKickIconWidth", 40, { "Width", 16, 128, 1, 300 }, { focusRightX, -74, 320 },
            reason = "MSUF2_FOCUS_KICK_WIDTH", afterWrite = ApplyFocusKickOptions, name = "width" },
        { "slider", "focusKickIconHeight", 40, { "Height", 16, 128, 1, 300 }, { focusRightX, -128, 320 },
            reason = "MSUF2_FOCUS_KICK_HEIGHT", afterWrite = ApplyFocusKickOptions, name = "height" },
        { "slider", "text", nil, { "Text size", 8, 24, 1, 300 }, { focusRightX, -182, 320 },
            name = "text", settingKey = "general.focusKickTextSize", get = function()
                local v = tonumber(ReadG("focusKickTextSize", nil))
                if v then return v end
                return (tonumber(ReadG("focusKickIconHeight", 40)) or 40) >= 48 and 14 or 12
            end, set = function(v)
                SetG("focusKickTextSize", floor((tonumber(v) or 12) + 0.5), "MSUF2_FOCUS_KICK_TEXT", { castbar = true, preview = true })
                RequestFocusKickTextFont()
                ApplyFocusKickOptions()
            end },
        { "slider", "focusKickIconOffsetX", 300, { "X offset", -500, 500, 1, 300 }, { focusLeftX, -176, 320 },
            reason = "MSUF2_FOCUS_KICK_X", afterWrite = ApplyFocusKickOptions, name = "x", writeDefault = 0 },
        { "slider", "focusKickIconOffsetY", 0, { "Y offset", -500, 500, 1, 300 }, { focusLeftX, -230, 320 },
            reason = "MSUF2_FOCUS_KICK_Y", afterWrite = ApplyFocusKickOptions, name = "y" },
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
    Schema.Owned(resetFocus, ctx.key, "castbar")
    local focusKickControls = { focusControls.preview, focusControls.show_castbar, focusControls.width, focusControls.height, focusControls.text,
        focusControls.x, focusControls.y, resetFocus }
    if W.SetControlsDisabledReason and W.TurnOnReason then
        W.SetControlsDisabledReason(focusKickControls,
            W.TurnOnReason("Focus interrupt tracker", function() return ReadGBool("enableFocusKickIcon", false) end))
    end
    syncFocusKick = function() SetControlsEnabled(focusKickControls, ReadGBool("enableFocusKickIcon", false)) end
    M.TrackRefresh(ctx, syncFocusKick)
end
-- The MSUF Suite's enemy nameplates draw this indicator too (MSUF.KickReady,
-- Castbars/MSUF_InterruptReady.lua). Their switch is always built, so the
-- search index carries it, and shown where the Suite's nameplates can draw it
-- (the index hides its row elsewhere through this probe, like the GCD Bar's).
-- It works while that module runs, which registers it as the engine's
-- consumer. The title names the module in the disabled reason.
local function SuiteNameplatesTitle()
    local link = MSUF.SuiteLink
    if not link.HasNameplateKickReady() then return nil end
    return link.ModuleTitle("nameplates") or "Nameplates"
end
M.CastbarSuiteNameplatesSupported = function() return SuiteNameplatesTitle() ~= nil end
local function SuiteNameplatesRunning()
    return MSUF.KickReady.HasConsumers()
end
local function BuildInterruptReadySection(PageState, secBuilder)
    local ctx, BuildCastControlSpecs, ApplyCastbarsIfNeeded, ApplyAndRefresh, RequestCastPreviewRefresh = PageState.ctx,
        PageState.BuildCastControlSpecs, PageState.ApplyCastbarsIfNeeded, PageState.ApplyAndRefresh, PageState.RequestCastPreviewRefresh
    local nameplatesTitle = SuiteNameplatesTitle()
    -- One toggle per castbar unit this client has (MSUF.Client.SupportsUnit):
    -- Classic Era has no focus, boss or arena castbars, TBC no boss castbars and
    -- WoW Forever no arena castbars. Kept toggles stack from the top.
    local unitToggles = {}
    for _, unitToggle in ipairs({
        { "target", "Show on Target castbar", "kickReadyShowTarget" },
        { "focus", "Show on Focus castbar", "kickReadyShowFocus" },
        { "boss", "Show on Boss castbars", "kickReadyShowBoss" },
        { "arena", "Show on Arena castbars", "kickReadyShowArena" },
    }) do
        if unitToggle[1] == "target" or not M.SupportsFrameScope or M.SupportsFrameScope(unitToggle[1]) then
            unitToggles[#unitToggles + 1] = unitToggle
        end
    end
    -- A shown nameplate switch under four castbar toggles moves the placement block down a row.
    local placementShift = (nameplatesTitle and #unitToggles >= 4) and 26 or 0
    local kick = Schema.Section(secBuilder:CollapsibleSection("castbar_interrupt_ready", "Interrupt Ready Indicator", 382, false), PageState.ctx.key)
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
    local function Heading(id, text, x, y)
        local label = W.LabelAt(kick, text, x, y, 160, "GameFontNormalSmall", T.colors.accent)
        return Schema.Custom(label, { id = "menu2.opt_castbar.interrupt_ready.heading." .. id, kind = "text",
            labelKey = text, scope = ctx.key, applyDomain = "presentation", owner = label })
    end
    Heading("castbars", "Castbars", kickLeftX, -38)
    Heading("appearance", "Appearance", kickRightX, -38)
    local syncKickReady
    local function ApplyKickReady(reason, _, applyQueued)
        ApplyCastbarsIfNeeded(reason, nil, applyQueued)
        _G.MSUF_KickReady_RefreshAll()
        RequestCastPreviewRefresh()
        if syncKickReady then syncKickReady() end
    end
    local kickSpecs = {}
    for _, unitToggle in ipairs(unitToggles) do
        kickSpecs[#kickSpecs + 1] = { "flowToggle", unitToggle[3], false, { unitToggle[2] }, { kickLeftX, -56 - #kickSpecs * 26 },
            labelWidth = 300, reason = "MSUF2_KICK_READY_ENABLE", afterWrite = ApplyKickReady }
    end
    kickSpecs[#kickSpecs + 1] = { "flowToggle", "kickReadyShowNameplates", false,
        { "Show on enemy nameplates (MSUF Suite)" }, { kickLeftX, -56 - #kickSpecs * 26 },
            labelWidth = 300, reason = "MSUF2_KICK_READY_ENABLE", afterWrite = ApplyKickReady }
    kickSpecs[#kickSpecs + 1] = { "dropdown", "kickReadyStyle", "border", { "Indicator style", VT("border", "Castbar border",
        "box", "Color box next to cast", "fill", "Unavailable cast fill"), 300 }, { kickRightX, -56, 300 },
            reason = "MSUF2_KICK_READY_STYLE", afterWrite = ApplyKickReady }
    kickSpecs[#kickSpecs + 1] = { "slider", "kickReadySize", 16, { "Indicator size", 8, 32, 1, 300 }, { kickRightX, -110, 320 },
            reason = "MSUF2_KICK_READY_SIZE", afterWrite = ApplyAndRefresh }
    kickSpecs[#kickSpecs + 1] = { "flowToggle", "kickReadyAutoSize", true, { "Auto-size to castbar height" }, { kickRightX, -164 },
            labelWidth = 360, reason = "MSUF2_KICK_READY_AUTO", afterWrite = ApplyKickReady }
    local kickControls = BuildCastControlSpecs(kick, kickSpecs, "interrupt_ready")
    local colorHint = Schema.Build(ctx, kick, {
        { "text", "menu2.opt_castbar.kick.colorHint", nil, { "Colors: Colors menu > Castbar Colors", kickRightX, -196, 370, T.colors.muted } },
    })["menu2.opt_castbar.kick.colorHint"]
    Heading("placement", "Placement", kickLeftX, -172 - placementShift)
    M.Assign(kickControls, BuildCastControlSpecs(kick, {
        { "flowToggle", "kickReadyTimeMarker", false, { "Show interrupt availability markers" }, { kickRightX, -216 },
            labelWidth = 370, reason = "MSUF2_KICK_TIME_MARKER", afterWrite = ApplyKickReady },
        { "flowToggle", "kickReadyTimeSegment", false, { "Shade cast time after interrupts recover" }, { kickRightX, -244 },
            labelWidth = 370, reason = "MSUF2_KICK_TIME_SEGMENT", afterWrite = ApplyKickReady },
        { "dropdown", "kickReadyAnchor", "RIGHT", { "Anchor", VT("RIGHT", "Right", "LEFT", "Left", "TOP", "Top", "BOTTOM",
            "Bottom"), 260 }, { kickLeftX, -190 - placementShift, 260 },
            reason = "MSUF2_KICK_READY_ANCHOR", afterWrite = ApplyCastbarsIfNeeded },
        { "slider", "kickReadyOffsetX", 4, { "X offset", -50, 50, 1, 300 }, { kickLeftX, -244 - placementShift, 320 },
            reason = "MSUF2_KICK_READY_X", afterWrite = ApplyCastbarsIfNeeded },
        { "slider", "kickReadyOffsetY", 0, { "Y offset", -50, 50, 1, 300 }, { kickLeftX, -298 - placementShift, 320 },
            reason = "MSUF2_KICK_READY_Y", afterWrite = ApplyCastbarsIfNeeded },
    }, "interrupt_ready.placement"))
    local nameplateToggle = kickControls.kickReadyShowNameplates
    if not nameplatesTitle then
        nameplateToggle:Hide()
    elseif W.SetControlDisabledReason and W.TurnOnReason then
        W.SetControlDisabledReason(nameplateToggle, W.TurnOnReason(nameplatesTitle, SuiteNameplatesRunning))
    end
    local style, size, auto = kickControls.kickReadyStyle, kickControls.kickReadySize, kickControls.kickReadyAutoSize
    local placementControls = { kickControls.kickReadyAnchor, kickControls.kickReadyOffsetX, kickControls.kickReadyOffsetY }
    -- The time markers draw on an indicator's castbar, so they follow the unit toggles too.
    local markerControls = { kickControls.kickReadyTimeMarker, kickControls.kickReadyTimeSegment }
    syncKickReady = function()
        -- Only a toggle this client builds can turn the indicator on.
        local enabled = ReadGBool("kickReadyShowTarget", false)
            or (kickControls.kickReadyShowFocus ~= nil and ReadGBool("kickReadyShowFocus", false))
            or (kickControls.kickReadyShowBoss ~= nil and ReadGBool("kickReadyShowBoss", false))
            or (kickControls.kickReadyShowArena ~= nil and ReadGBool("kickReadyShowArena", false))
            or (nameplatesTitle ~= nil and ReadGBool("kickReadyShowNameplates", false))
        if nameplatesTitle then SetControlEnabled(nameplateToggle, SuiteNameplatesRunning()) end
        local autoOn = ReadGBool("kickReadyAutoSize", true)
        local isFill = ReadG("kickReadyStyle", "border") == "fill"
        SetControlEnabled(style, enabled)
        SetControlEnabled(auto, enabled and not isFill)
        SetControlEnabled(size, enabled and not isFill and not autoOn)
        SetControlsEnabled(placementControls, enabled and not isFill)
        SetControlsEnabled(markerControls, enabled)
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
    if castPreview then
        Schema.Custom(castPreview, { id = "menu2.opt_castbar.preview", kind = "preview",
            scope = ctx.key, applyDomain = "preview", owner = castPreview })
    end
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
    -- Only the castbar setting/apply policy is page-owned; native controls,
    -- declarations, history and combat refusal come from the shared renderer.
    local function BuildCastControlSpecs(parent, rows, semanticPrefix)
        local options = {}
        options.bind = function(rowCtx, widget, row, kind)
            local key, default, reason = row[2], row[3], row.reason
            local exact
            if row.classification ~= "ephemeral" then exact = { settingKey = row.settingKey or ("general." .. key) } end
            row.meta = row.meta or Meta(semanticPrefix .. "." .. key, row.classification, exact)
            row.domain = "castbar"
            if kind == "slider" then
                row.meta.step, row.meta.roundStep = row[4][4], not row.precise
            end
            row.get = row.get or function()
                if kind == "toggle" then return ReadGBool(key, default) end
                if kind == "slider" then return tonumber(ReadG(key, default)) or default end
                return ReadG(key, default)
            end
            row.set = row.set or function(value)
                local nextValue = value
                if kind == "slider" then
                    local fallback = row.writeDefault ~= nil and row.writeDefault or default
                    nextValue = row.precise and (tonumber(value) or fallback) or floor((tonumber(value) or fallback) + 0.5)
                elseif kind == "dropdown" then
                    nextValue = value or default
                end
                if kind == "toggle" then SetGBool(key, nextValue, reason, { castbar = true, preview = true })
                else SetG(key, nextValue, reason, { castbar = true, preview = true }) end
                if row.afterWrite then row.afterWrite(reason, nextValue, true) end
            end
            if row.writeDefault ~= nil then row[3] = row.writeDefault end
            Schema.UnitBinding(rowCtx, widget, row, kind)
        end
        options.beforeBind = function(widget, row)
            if row.labelWidth then
                -- The old toggle owner sizes the label after placing it.
                W.MoveWidget(widget, parent, row[5][1], row[5][2])
                widget._msuf2Label:SetWidth(max(40, tonumber(row.labelWidth) or 260))
                row[5] = nil
            end
        end
        local controls = Schema.Build(ctx, parent, rows, options)
        for _, row in ipairs(rows) do
            if row.name then controls[row.name] = controls[row[2]] end
        end
        return controls
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
        spec.prepareShell = function(_, section) Schema.Section(section, ctx.key) end
        local buildLazy = M.UnitPage and M.UnitPage.BuildSectionLazy
        if type(buildLazy) == "function" then return buildLazy(ctx, b, nil, spec) end
        return spec.build(ctx, b)
    end
    return {
        ctx = ctx, b = b, castPreview = castPreview, castPreviewSection = castPreviewSection, fixedPreview = fixedPreview,
        ApplyCastbarTextures = ApplyCastbarTextures, RefreshCastPreview = RefreshCastPreview,
        RequestCastPreviewRefresh = RequestCastPreviewRefresh, ShakeCastPreview = ShakeCastPreview,
        ShowEmpoweredPreview = ShowEmpoweredPreview, BuildCastControlSpecs = BuildCastControlSpecs,
        ApplyCastbarsIfNeeded = ApplyCastbarsIfNeeded, ApplyAndRefresh = ApplyAndRefresh, LazyCastbarSection = LazyCastbarSection,
    }
end
local function BuildCastbars(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Castbar", "Castbar behavior, textures and interrupt indicators.", 72)
    local PageState = CreateCastbarPageState(ctx, b)
    local LazyCastbarSection = PageState.LazyCastbarSection
    LazyCastbarSection({ sectionId = "castbar_behavior", title = "Shake & Fill Direction", height = 224, defaultOpen = true,
        build = function(_, secBuilder) return BuildBehaviorSection(PageState, secBuilder) end })
    LazyCastbarSection({ sectionId = "castbar_filters", title = "Filtering & Feedback", height = 110,
        build = function(_, secBuilder) return BuildFilterSection(PageState, secBuilder) end })
    if GCDBarSupported() then
        LazyCastbarSection({ sectionId = "castbar_gcd", title = "GCD Bar", height = 346,
            build = function(_, secBuilder) return BuildGCDSection(PageState, secBuilder) end })
    end
    LazyCastbarSection({ sectionId = "castbar_textures", title = "Textures & Outline", height = 246,
        build = function(_, secBuilder) return BuildTexturesSection(PageState, secBuilder) end })
    -- Empowered casts are an Evoker mechanic: Midnight only. WoW Forever and the
    -- Classic clients have no Evoker (MSUF.Client.HasEmpoweredCasts). A harness
    -- that fakes only IsClassic still hides the section.
    local client = MSUF.Client
    if not client or (client.HasEmpoweredCasts ~= false and client.IsClassic ~= true) then
        LazyCastbarSection({ sectionId = "castbar_empowered", title = "Empowered Casts", height = 130,
            build = function(_, secBuilder) return BuildEmpoweredSection(PageState, secBuilder) end })
    end
    LazyCastbarSection({ sectionId = "castbar_name_shortening", title = "Name Shortening", height = 154,
        build = function(_, secBuilder) return BuildNameShorteningSection(PageState, secBuilder) end })
    -- Focus Kick tracks the focus unit, which Classic Era does not have.
    if not M.SupportsFrameScope or M.SupportsFrameScope("focus") then
        LazyCastbarSection({ sectionId = "castbar_focus_kick", title = "Focus Kick", height = 352,
            build = function(_, secBuilder) return BuildFocusKickSection(PageState, secBuilder) end })
    end
    LazyCastbarSection({ sectionId = "castbar_interrupt_ready", title = "Interrupt Ready Indicator", height = 382,
        build = function(_, secBuilder) return BuildInterruptReadySection(PageState, secBuilder) end })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_castbar", { title = "MSUF Castbar", build = BuildCastbars, version = 6 })
