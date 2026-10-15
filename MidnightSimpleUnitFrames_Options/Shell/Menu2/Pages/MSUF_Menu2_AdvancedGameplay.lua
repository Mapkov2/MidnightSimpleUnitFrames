local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Gameplay page.
-- Builds controls for optional gameplay helpers such as combat timer, crosshair, melee range,
-- and totem/statue frames. Live frame work belongs to GameplayRuntime.
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Menu2/Pages/AdvancedGameplay")
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min

local Gameplay, MoveWidget, LabelAt = AP.Gameplay, AP.MoveWidget, AP.LabelAt
local ControlMeta, RegisterControl = AP.ControlMeta, AP.RegisterControl
local GAMEPLAY_SETTING_BY_PATH = {
    ["timer.enabled"] = "gameplay.enableCombatTimer",
    ["combat_state.enabled"] = "gameplay.enableCombatStateText",
    ["totem_frame.enabled"] = "gameplay.enablePlayerTotems",
    ["crosshair.enabled"] = "gameplay.enableCombatCrosshair",
    ["crosshair.melee_spell"] = "gameplay.nameplateMeleeSpellID",
}
local GAMEPLAY_ACTION_BY_PATH = {
    ["totem_frame.reset_layout"] = "reset_player_totems_layout",
}
local function Meta(path, classification, exact)
    local resolved = {}
    if type(exact) == "table" then
        for key, value in pairs(exact) do resolved[key] = value end
    end
    local dbKey = tostring(path or ""):match("^setting%.(.+)$")
    resolved.settingKey = resolved.settingKey or GAMEPLAY_SETTING_BY_PATH[path]
        or (dbKey and ("gameplay." .. dbKey))
    resolved.actionKey = resolved.actionKey or GAMEPLAY_ACTION_BY_PATH[path]
    return ControlMeta("gameplay", "advanced", path, classification, resolved)
end
local ApplyGameplay = M.ApplyGameplay
local Schema = M.ControlSchema
local VT = M.ValueTextList
local function PaintSpellInput(input, edgeAlpha, withFill, withBorder)
    local accent = T.colors.accent
    if withFill and input._msuf2SpellInputFill then input._msuf2SpellInputFill:SetVertexColor(0.025, 0.034, 0.070, 0.98) end
    if input._msuf2SpellInputEdge then input._msuf2SpellInputEdge:SetVertexColor(accent[1], accent[2], accent[3], edgeAlpha) end
    if withFill and input.SetBackdropColor then input:SetBackdropColor(0.025, 0.034, 0.070, 0.98) end
    if withBorder and input.SetBackdropBorderColor then input:SetBackdropBorderColor(accent[1], accent[2], accent[3], edgeAlpha) end
end
local function TotemFrameAvailable() return _G.TotemFrame ~= nil end
local function MeleeRangeEnabled(g)
    return g.enableCombatCrosshair == true and g.enableCombatCrosshairMeleeRangeColor == true
end
local function MeleeSpecEnabled(g)
    return MeleeRangeEnabled(g) and M.GetGameplayPlayerSpecID() ~= nil
end
local function GameplayDeclarations(anchorValues,frameAnchors)
    return {
        combatTimerAnchor = { kind = "dropdown", labelKey = "Anchor", values = anchorValues },
        combatFontSize = { kind = "slider", labelKey = "Timer size", range = { 10, 64, 1 } },
        lockCombatTimer = { kind = "toggle", labelKey = "Lock position" },
        combatTimerClickThrough = { kind = "toggle", labelKey = "Click-through (ALT to drag when unlocked)" },
        combatOffsetX = { kind = "slider", labelKey = "X offset", range = { -800, 800, 1 } },
        combatOffsetY = { kind = "slider", labelKey = "Y offset", range = { -800, 800, 1 } },
        lockCombatState = { kind = "toggle", labelKey = "Lock position" },
        combatStateFontSize = { kind = "slider", labelKey = "Text size", range = { 10, 64, 1 } },
        combatStateDuration = { kind = "slider", labelKey = "Duration (s)", range = { 0.5, 5.0, 0.5 } },
        combatStateOffsetX = { kind = "slider", labelKey = "X offset", range = { -800, 800, 1 } },
        combatStateOffsetY = { kind = "slider", labelKey = "Y offset", range = { -800, 800, 1 } },
        playerTotemsIconSize = { kind = "slider", labelKey = "Icon size", range = { 8, 64, 1 } },
        playerTotemsOffsetX = { kind = "slider", labelKey = "X offset", range = { -200, 200, 1 } },
        playerTotemsOffsetY = { kind = "slider", labelKey = "Y offset", range = { -200, 200, 1 } },
        playerTotemsAnchorFrom = { kind = "dropdown", labelKey = "From", values = frameAnchors },
        playerTotemsAnchorTo = { kind = "dropdown", labelKey = "To", values = frameAnchors },
        enableCombatCrosshairMeleeRangeColor = { kind = "toggle", labelKey = "Crosshair: color by melee range to target (green=in range, red=out)" },
        meleeSpellPerClass = { kind = "toggle", labelKey = "Store per class" },
        meleeSpellPerSpec = { kind = "toggle", labelKey = "Store per spec" },
        crosshairThickness = { kind = "slider", labelKey = "Crosshair thickness", range = { 1, 12, 1 } },
        crosshairSize = { kind = "slider", labelKey = "Crosshair size", range = { 20, 120, 2 } },
    }
end
local function GameplayRow(declarations,key,layout,apply,defaultApply)
    local declaration = assert(declarations[key], "unknown Gameplay schema row")
    local meta = Meta("setting." .. key)
    return {
        id = meta.controlId, kind = declaration.kind, labelKey = declaration.labelKey,
        range = declaration.range, values = declaration.values, layout = layout,
        key = key, settingPath = "gameplay." .. key, scope = "gameplay", applyDomain = "gameplay",
        source = Gameplay, defaultSource = function() return Schema.Default("gameplay", key) end,
        apply = apply or defaultApply, meta = meta,
    }
end
local function SwitchAt(ctx, section, label, x, y, width, key, apply, meta)
    return Schema.Render(ctx, section, {
        id = meta.controlId, kind = "toggle", view = "switch", labelKey = label,
        scope = "gameplay", applyDomain = "gameplay", settingPath = "gameplay." .. key,
        source = Gameplay, key = key, defaultSource = function() return Schema.Default("gameplay", key) end,
        apply = apply, meta = meta,
    }, { x = x, y = y, width = width })
end
local function BindGameplayText(ctx,list,input,getValue,setValue,metadata,apply,label)
    Schema.Bind(ctx, input, {
        id = metadata.controlId, kind = "textinput", labelKey = label, settingPath = metadata.settingKey,
        scope = "gameplay", applyDomain = "gameplay", meta = metadata, commitOnBlur = true,
        get = getValue, set = function(value) setValue(value) apply() end,
    })
    M.AppendValues(list, input)
end
local function GameplayContentWidth(ctx)
    return min(tonumber(M.formContentMaxWidth) or 980, tonumber(ctx.width) or 900)
end
local function BindTotemActions(ctx,previewBtn,resetTotemBtn,ApplyGameplayUI)
    -- The runtime owns preview state and drops it on its own (class without a TotemFrame, or the
    -- master toggle going off), so the button reads it back rather than tracking a local flag.
    local function SyncTotemPreviewButton()
        local active = type(MSUF.MSUF_PlayerTotems_IsPreviewActive) == "function"
            and MSUF.MSUF_PlayerTotems_IsPreviewActive() == true
        T.ApplyButtonRole(previewBtn, active and "success" or "normal")
    end
    local function ToggleTotemPreview()
        if MSUF and type(MSUF.MSUF_PlayerTotems_TogglePreview) == "function" then MSUF.MSUF_PlayerTotems_TogglePreview() end
        SyncTotemPreviewButton()
    end
    previewBtn:SetScript("OnClick", ToggleTotemPreview)
    SyncTotemPreviewButton()
    local previewMeta = Meta("totem_frame.preview", "ephemeral")
    RegisterControl(previewBtn, previewMeta, "Preview", "button")
    local previewAction = Schema.ButtonAction(previewBtn)
    Schema.Custom(previewBtn, {
        id = previewMeta.controlId, kind = "button", labelKey = "Preview", meta = previewMeta,
        scope = "gameplay", applyDomain = "totemPreview", gate = TotemFrameAvailable,
        get = MSUF.MSUF_PlayerTotems_IsPreviewActive, set = previewAction,
        action = previewAction, owner = previewBtn,
    })
    local function ResetTotemLayout()
        local g = Gameplay()
        g.playerTotemsIconSize = Schema.Default("gameplay", "playerTotemsIconSize")
        g.playerTotemsOffsetX = Schema.Default("gameplay", "playerTotemsOffsetX")
        g.playerTotemsOffsetY = Schema.Default("gameplay", "playerTotemsOffsetY")
        g.playerTotemsAnchorFrom = Schema.Default("gameplay", "playerTotemsAnchorFrom")
        g.playerTotemsAnchorTo = Schema.Default("gameplay", "playerTotemsAnchorTo")
        ApplyGameplayUI()
        if M.RequestRefresh then M.RequestRefresh(ctx, "advanced-gameplay-totems-reset") elseif M.Refresh then M.Refresh(ctx) end
    end
    resetTotemBtn:SetScript("OnClick", ResetTotemLayout)
    local resetMeta = Meta("totem_frame.reset_layout", "action")
    RegisterControl(resetTotemBtn, resetMeta, "Reset TotemFrame layout", "button")
    local resetAction = Schema.ButtonAction(resetTotemBtn)
    Schema.Custom(resetTotemBtn, {
        id = resetMeta.controlId, kind = "button", labelKey = "Reset TotemFrame layout", meta = resetMeta,
        scope = "gameplay", applyDomain = "gameplay", gate = TotemFrameAvailable,
        actionKey = resetMeta.actionKey, set = resetAction,
        action = resetAction, owner = resetTotemBtn,
    })
    return SyncTotemPreviewButton
end
local function StyleMeleeSpellInput(spellInput, spellInputW)
    if spellInput then
        spellInput:SetSize(spellInputW, 24)
        if spellInput._msuf2Title then
            spellInput._msuf2Title:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3], 1)
            spellInput._msuf2Title:SetWidth(spellInputW)
        end
        if T.CreateSuperellipseLayers then
            local fill, edge = T.CreateSuperellipseLayers(spellInput, "_msuf2SpellInput", 1, "BACKGROUND", "OVERLAY")
            spellInput._msuf2SpellInputFill = fill
            spellInput._msuf2SpellInputEdge = edge
        end
        PaintSpellInput(spellInput, 0.58, true, true)
        spellInput:HookScript("OnEditFocusGained", function(self) PaintSpellInput(self, 0.95, false, false) end)
        spellInput:HookScript("OnEditFocusLost", function(self) PaintSpellInput(self, 0.58, false, true) end)
        spellInput:HookScript("OnShow", function(self) PaintSpellInput(self, 0.58, true, true) end)
    end
end

local function BuildGameplayTimer(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
    SectionColumns, AddBackdrops, AddControls, Row, timerControls, ApplyGameplayUI)
    --- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local compactTimer = GameplayStacked()
    local timer = b:CollapsibleSection("gameplay_timer", "Combat Timer", compactTimer and 570 or 430, true)
    Schema.Section(timer, "gameplay")
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(timer, {
            title = "Combat Timer Text Settings",
            historyLabel = "Combat timer color",
            historySource = "menu:gameplay-timer-color",
            offsetY = -8,
            textSettings = {
                scope = "shared",
                kind = "gameplay_timer",
                colorReferences = { "gameplay.timer" },
                colorTitle = "Combat Timer Color",
                subtitle = "Combat Timer text follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    local timerW = timer._msuf2Width or ctx.width or 900
    local timerCardW = SectionCardWidth(timer, 680)
    local timerLeftX, timerRightX, timerColW = SectionColumns(timer, 300)
    local timerEnable
    if compactTimer then
        local timerSliderW = SectionControlWidth(timer, 300, 120)
        AddBackdrops(timer, { { -38, timerCardW, 220 }, { -274, timerCardW, 238 } })
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", 30, -40, min(230, timerSliderW), "enableCombatTimer", ApplyGameplayUI, Meta("timer.enabled"))
        AddControls(timerControls, timer, {
            Row("combatTimerAnchor", { x = 30, y = -84, width = min(220, timerSliderW) }),
            Row("combatFontSize", { x = 30, y = -138, width = timerSliderW }),
            Row("lockCombatTimer", { x = 30, y = -192 }),
            Row("combatTimerClickThrough", { x = 30, y = -224 }),
        })
        LabelAt(timer, "Timer position (offset)", 30, -284, 260, "GameFontHighlightSmall", T.colors.muted)
        AddControls(timerControls, timer, {
            Row("combatOffsetX", { x = 30, y = -316, width = timerSliderW }),
            Row("combatOffsetY", { x = 30, y = -386, width = timerSliderW }),
        })
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -492, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        AddBackdrops(timer, { { -38, timerCardW, 126 }, { -178, timerCardW, 150 } })
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", timerLeftX, -40, min(230, timerColW), "enableCombatTimer", ApplyGameplayUI, Meta("timer.enabled"))
        AddControls(timerControls, timer, {
            Row("combatTimerAnchor", { x = timerRightX, y = -40, width = min(220, timerColW) }),
            Row("combatFontSize", { x = timerLeftX, y = -94, width = min(270, timerColW) }),
            Row("lockCombatTimer", { x = timerRightX, y = -100 }),
            Row("combatTimerClickThrough", { x = timerRightX, y = -132 }),
        })
        LabelAt(timer, "Timer position (offset)", 30, -186, 260, "GameFontHighlightSmall", T.colors.muted)
        AddControls(timerControls, timer, {
            Row("combatOffsetX", { x = timerLeftX, y = -216, width = timerColW }),
            Row("combatOffsetY", { x = timerRightX, y = -216, width = timerColW }),
        })
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -312, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    end
    -- timerControls[3] is the timer's "Lock position" toggle in both layout branches above.
    if type(M.AddTooltip) == "function" and timerControls[3] then
        M.AddTooltip(timerControls[3], "Lock position", "While unlocked, the Combat Timer stays visible out of combat as a movable 0:00 placeholder. Drag it with the mouse or nudge it with the arrow keys - with click-through enabled, hold ALT to drag. Lock it to freeze the position.", { hook = true, labelHit = true })
    end
    return timerEnable
end

local function BuildGameplayState(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
    SectionColumns, AddBackdrops, AddControls, Row, stateControls, ApplyGameplayUI, AddGameplayTextInput)
    local stateStacked = GameplayStacked()
    local state = b:CollapsibleSection("gameplay_state", "Combat Enter/Leave", stateStacked and 580 or 340, false)
    Schema.Section(state, "gameplay")
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(state, {
            title = "Combat State Text Settings",
            historyLabel = "Combat state colors",
            historySource = "menu:gameplay-state-colors",
            offsetY = -8,
            textSettings = {
                scope = "shared",
                kind = "gameplay_state",
                colorReferences = { "gameplay.enter", "gameplay.leave" },
                colorTitle = "Combat State Colors",
                subtitle = "Combat Enter/Leave text follows the shared Fonts settings.",
                capabilities = { baseline = false },
            },
        })
    end
    local stateCardW = SectionCardWidth(state, 680)
    local stateControlW = SectionControlWidth(state, 260, 120)
    local stateLeftX, stateRightX, stateColW = SectionColumns(state, 260)
    local stateEnable
    local enterInput
    local leaveInput
    if stateStacked then
        AddBackdrops(state, { { -38, stateCardW, 196 }, { -250, stateCardW, 282 } })
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", 30, -40, min(270, stateControlW), "enableCombatStateText", ApplyGameplayUI, Meta("combat_state.enabled"))
        AddControls(stateControls, state, { Row("lockCombatState", { x = 30, y = -74 }) })
        enterInput = MoveWidget(W.TextInput(state, "Enter text", stateControlW), state, 30, -120)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", stateControlW), state, 30, -174)
        AddControls(stateControls, state, {
            Row("combatStateFontSize", { x = 30, y = -258, width = stateControlW }),
            Row("combatStateDuration", { x = 30, y = -328, width = stateControlW }),
            Row("combatStateOffsetX", { x = 30, y = -398, width = stateControlW }),
            Row("combatStateOffsetY", { x = 30, y = -468, width = stateControlW }),
        })
    else
        AddBackdrops(state, { { -38, stateCardW, 136 }, { -144, stateCardW, 154 } })
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", stateLeftX, -40, min(270, stateColW), "enableCombatStateText", ApplyGameplayUI, Meta("combat_state.enabled"))
        AddControls(stateControls, state, { Row("lockCombatState", { x = stateRightX, y = -40 }) })
        enterInput = MoveWidget(W.TextInput(state, "Enter text", min(220, stateColW)), state, stateLeftX, -86)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", min(220, stateColW)), state, stateRightX, -86)
        AddControls(stateControls, state, {
            Row("combatStateFontSize", { x = stateLeftX, y = -152, width = stateColW }),
            Row("combatStateDuration", { x = stateRightX, y = -152, width = stateColW }),
            Row("combatStateOffsetX", { x = stateLeftX, y = -238, width = stateColW }),
            Row("combatStateOffsetY", { x = stateRightX, y = -238, width = stateColW }),
        })
    end
    -- stateControls[1] is the "Lock position" toggle in both layout branches above.
    if type(M.AddTooltip) == "function" and stateControls[1] then
        M.AddTooltip(stateControls[1], "Lock position", "While unlocked, the Combat Enter/Leave text is shown permanently as a movable handle. Drag it with the mouse or nudge it with the arrow keys. Lock it so the text only appears when entering or leaving combat.", { hook = true, labelHit = true })
    end
    AddGameplayTextInput(stateControls, enterInput, "combatStateEnterText")
    AddGameplayTextInput(stateControls, leaveInput, "combatStateLeaveText")
    return stateEnable
end

local function BuildGameplayTotems(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
    SectionColumns, AddBackdrops, AddControls, Row, totemControls, ApplyGameplayUI)
    local classStacked = GameplayStacked()
    local classSec = b:CollapsibleSection("gameplay_class_specific", "Class-specific toggles", classStacked and 620 or 390, false)
    Schema.Section(classSec, "gameplay")
    local classW = classSec._msuf2Width or ctx.width or 900
    local classCardW = SectionCardWidth(classSec, 700)
    local classControlW = SectionControlWidth(classSec, 300, 120)
    local classLeftX, classRightX, classColW = SectionColumns(classSec, 300)
    local totemDescription = TotemFrameAvailable()
        and "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat."
        or "Blizzard TotemFrame is not available on this client."
    local totemEnable
    local previewBtn
    local resetTotemBtn
    if classStacked then
        AddBackdrops(classSec, { { -38, classCardW, 520 } })
        LabelAt(classSec, "Totem / Statue frame", 30, -38, min(360, classW - 60), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, totemDescription, 30, -60, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", 30, -92, min(300, classControlW), "enablePlayerTotems", ApplyGameplayUI, Meta("totem_frame.enabled"))
        previewBtn = T.Button(classSec, "Preview", min(120, classControlW), 22)
        previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 32, -128)
        T.FitButtonWidth(previewBtn, 90, max(120, classCardW - 64))
        resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", min(190, classControlW), 22)
        resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 32, -160)
        T.FitButtonWidth(resetTotemBtn, 140, max(190, classCardW - 64))
        LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", 30, -196, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        AddControls(totemControls, classSec, {
            Row("playerTotemsIconSize", { x = 30, y = -238, width = classControlW }),
            Row("playerTotemsOffsetX", { x = 30, y = -308, width = classControlW }),
            Row("playerTotemsOffsetY", { x = 30, y = -378, width = classControlW }),
            Row("playerTotemsAnchorFrom", { x = 30, y = -448, width = min(220, classControlW) }),
            Row("playerTotemsAnchorTo", { x = 30, y = -502, width = min(220, classControlW) }),
        })
    else
        AddBackdrops(classSec, { { -38, classCardW, 276 } })
        LabelAt(classSec, "Totem / Statue frame", classLeftX, -38, min(360, classColW), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, totemDescription, classLeftX, -60, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", classLeftX, -92, classColW, "enablePlayerTotems", ApplyGameplayUI, Meta("totem_frame.enabled"))
        previewBtn = T.Button(classSec, "Preview", 120, 22)
        previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", classLeftX, -128)
        resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", 190, 22)
        -- Buttons live in the left column; the sliders own everything from classRightX on.
        local btnRowW = max(160, classRightX - classLeftX - 12)
        T.FitButtonWidth(previewBtn, 90, btnRowW)
        local previewW = previewBtn:GetWidth() or 120
        local resetW = T.MeasureButtonWidth(resetTotemBtn, 140, btnRowW)
        resetTotemBtn:SetWidth(resetW)
        -- Long translations ("Réinitialiser la disposition TotemFrame") cannot share the row with
        -- Preview, so the pair wraps to a second line instead of truncating.
        local wrapped = (previewW + 12 + resetW) > btnRowW
        local rowShift = wrapped and 30 or 0
        if wrapped then
            resetTotemBtn:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, -8)
        else
            resetTotemBtn:SetPoint("TOPLEFT", previewBtn, "TOPRIGHT", 12, 0)
        end
        LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", classLeftX, -158 - rowShift, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        -- From/To share one row, so both come out of the same split. Sizing the width and the
        -- second column from unrelated formulas let them overlap each other and bleed into the
        -- slider column at every content width.
        local anchorGap = 12
        local anchorW = min(180, max(96, floor((btnRowW - anchorGap) * 0.5)))
        AddControls(totemControls, classSec, {
            Row("playerTotemsIconSize", { x = classRightX, y = -84, width = classColW }),
            Row("playerTotemsOffsetX", { x = classRightX, y = -168, width = classColW }),
            Row("playerTotemsOffsetY", { x = classRightX, y = -252, width = classColW }),
            Row("playerTotemsAnchorFrom", { x = classLeftX, y = -202 - rowShift, width = anchorW }),
            Row("playerTotemsAnchorTo", { x = classLeftX + anchorW + anchorGap, y = -202 - rowShift, width = anchorW }),
        })
    end
    local SyncTotemPreviewButton = BindTotemActions(ctx,previewBtn,resetTotemBtn,ApplyGameplayUI)
    local totemActionControls = { previewBtn, resetTotemBtn }
    return totemEnable, SyncTotemPreviewButton, totemActionControls
end

local function BuildGameplayCrosshair(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
    SectionColumns, AddBackdrops, AddControls, Row, crossControls, meleeControls, ApplyGameplayUI,
    SeedMeleeClass, SeedMeleeSpec, AddTextInput, CurrentMeleeSpellID, SetMeleeSpellID, SpellName)
    local selectedSpellText
    local noSpellWarn
    local crossStacked = GameplayStacked()
    local cross = b:CollapsibleSection("gameplay_crosshair", "Combat Crosshair", crossStacked and 800 or 588, false)
    Schema.Section(cross, "gameplay")
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(cross, { "gameplay.crosshair_in", "gameplay.crosshair_out" }, {
            title = "Combat Crosshair Colors",
            note = "Used when melee-range coloring is enabled.",
            historySource = "menu:gameplay-crosshair-colors",
            offsetY = -8,
        })
    end
    local crossW = cross._msuf2Width or ctx.width or 900
    local crossCardW = SectionCardWidth(cross, 700)
    local crossControlW = SectionControlWidth(cross, 300, 120)
    local crossLeftX, crossRightX, crossColW = SectionColumns(cross, 300)
    local crossEnable
    local spellInput
    local classSpellToggle
    local specSpellToggle
    local spellInputW
    local preview
    local function ApplyMeleeClassScope()
        if Gameplay().meleeSpellPerClass then SeedMeleeClass() end
        ApplyGameplayUI()
    end
    local function ApplyMeleeSpecScope()
        if Gameplay().meleeSpellPerSpec then SeedMeleeSpec() end
        ApplyGameplayUI()
    end
    if crossStacked then
        spellInputW = min(260, crossControlW)
        AddBackdrops(cross, { { -38, crossCardW, 332 }, { -390, crossCardW, 346 } })
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", 30, -40, min(390, crossControlW), "enableCombatCrosshair", ApplyGameplayUI, Meta("crosshair.enabled"))
        AddControls(crossControls, cross, { Row("enableCombatCrosshairMeleeRangeColor", { x = 30, y = -74 }) })
        LabelAt(cross, "Uses the spell selected below.", 54, -104, min(420, crossW - 82), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", 54, -126, min(520, crossW - 82), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, 30, -178)
        selectedSpellText = LabelAt(cross, "", 30, -242, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", 30, -264, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        AddControls(crossControls, cross, {
            Row("meleeSpellPerClass", { x = 30, y = -298 }, ApplyMeleeClassScope),
            Row("meleeSpellPerSpec", { x = 30, y = -332 }, ApplyMeleeSpecScope),
        })
        classSpellToggle, specSpellToggle = crossControls[#crossControls - 1], crossControls[#crossControls]
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", 32, -412)
        preview:SetSize(min(260, max(160, crossCardW - 28)), 120)
        AddControls(crossControls, cross, {
            Row("crosshairThickness", { x = 30, y = -560, width = crossControlW }),
            Row("crosshairSize", { x = 30, y = -630, width = crossControlW }),
        })
        LabelAt(cross, "Colors are configured in Colors > Gameplay.", 30, -734, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        spellInputW = min(260, crossColW)
        AddBackdrops(cross, { { -38, crossCardW, 242 }, { -312, crossCardW, 214 } })
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", crossLeftX, -40, min(390, crossColW), "enableCombatCrosshair", ApplyGameplayUI, Meta("crosshair.enabled"))
        AddControls(crossControls, cross, { Row("enableCombatCrosshairMeleeRangeColor", { x = crossLeftX, y = -74 }) })
        LabelAt(cross, "Uses the spell selected below.", crossLeftX + 24, -104, min(420, crossColW), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", crossLeftX + 24, -126, min(520, crossCardW - 56), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, crossLeftX, -170)
        selectedSpellText = LabelAt(cross, "", crossRightX, -192, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", crossRightX, -214, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        AddControls(crossControls, cross, {
            Row("meleeSpellPerClass", { x = crossRightX, y = -244 }, ApplyMeleeClassScope),
            Row("meleeSpellPerSpec", { x = crossRightX + min(180, crossColW * 0.52), y = -244 }, ApplyMeleeSpecScope),
        })
        classSpellToggle, specSpellToggle = crossControls[#crossControls - 1], crossControls[#crossControls]
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", crossLeftX, -312)
        preview:SetSize(min(260, crossColW), 120)
        AddControls(crossControls, cross, {
            Row("crosshairThickness", { x = crossRightX, y = -334, width = crossColW }),
            Row("crosshairSize", { x = crossRightX, y = -418, width = crossColW }),
        })
        LabelAt(cross, "Colors are configured in Colors > Gameplay.", crossRightX, -514, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
    end
    StyleMeleeSpellInput(spellInput, spellInputW)
    AddTextInput(crossControls, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v) SetMeleeSpellID(v) end,
        Meta("crosshair.melee_spell"), "Choose spell ID or name")
    M.AppendValues(meleeControls, spellInput, classSpellToggle, specSpellToggle)
    local bars = {}
    for i = 1, 4 do
        bars[i] = PixelLayoutRegion(preview:CreateTexture(nil, "ARTWORK"))
        bars[i]:SetColorTexture(1, 0, 0, 1)
    end
    local previewRefresh = function()
        local g = Gameplay()
        local id = CurrentMeleeSpellID()
        local name = SpellName(id)
        if selectedSpellText then T.SetTranslatedText(selectedSpellText, (id > 0 and M.Format("Selected: %s (%d)", name or M.Tr("Spell"), id)) or M.Tr("Selected: none")) end
        if noSpellWarn then noSpellWarn:SetShown((g.enableCombatCrosshairMeleeRangeColor == true) and id <= 0) end
        local size = math.max(20, tonumber(g.crosshairSize) or Schema.Default("gameplay","crosshairSize"))
        local thick = math.max(1, tonumber(g.crosshairThickness) or Schema.Default("gameplay","crosshairThickness"))
        local previewW = (preview and preview.GetWidth and preview:GetWidth()) or 260
        local previewH = (preview and preview.GetHeight and preview:GetHeight()) or 120
        local centerX, centerY = previewW * 0.5, -(previewH * 0.5)
        local gap = math.max(6, floor(size * 0.20))
        local color = g.crosshairInRangeColor
        local r, gr, b = (color and color[1]) or 0, (color and color[2]) or 1, (color and color[3]) or 0
        if g.enableCombatCrosshairMeleeRangeColor then
            local c = g.crosshairOutRangeColor
            r, gr, b = (c and c[1]) or 1, (c and c[2]) or 0, (c and c[3]) or 0
        end
        for i = 1, 4 do bars[i]:ClearAllPoints() end
        bars[1]:SetPoint("CENTER", preview, "TOPLEFT", centerX - gap - size * 0.28, centerY)
        bars[1]:SetSize(size * 0.42, thick)
        bars[2]:SetPoint("CENTER", preview, "TOPLEFT", centerX + gap + size * 0.28, centerY)
        bars[2]:SetSize(size * 0.42, thick)
        bars[3]:SetPoint("CENTER", preview, "TOPLEFT", centerX, centerY + gap + size * 0.28)
        bars[3]:SetSize(thick, size * 0.42)
        bars[4]:SetPoint("CENTER", preview, "TOPLEFT", centerX, centerY - gap - size * 0.28)
        bars[4]:SetSize(thick, size * 0.42)
        for i = 1, 4 do bars[i]:SetVertexColor(r or 1, gr or 0, b or 0, g.enableCombatCrosshair and 1 or 0.35) end
    end
    return crossEnable, specSpellToggle, previewRefresh
end

local function BuildGameplay(ctx)
    local b = W.PageBuilder(ctx)
    local disabledRefresh
    local previewRefresh
    local function ApplyGameplayUI()
        -- Gameplay edits often change both enabled state and preview visibility. Apply the
        -- runtime once, then refresh page-local controls. disabledRefresh (BindGateGroup)
        -- also runs previewRefresh via its `also` hook, so one call covers both.
        ApplyGameplay()
        if disabledRefresh then disabledRefresh() end
    end
    -- Only frames this client has (Classic Era has no Focus); a stored one stays listed, read-only.
    local anchorItems = VT("none", "None", "player", "Player", "target", "Target", "focus", "Focus")
    local function anchorValues() return M.AnchorTargetValues(anchorItems, Gameplay().combatTimerAnchor) end
    local frameAnchors = VT("TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT")
    local function CurrentMeleeSpellID()
        if type(M.GetGameplayMeleeSpellID) == "function" then return M.GetGameplayMeleeSpellID(Gameplay()) end
        return tonumber(Gameplay().nameplateMeleeSpellID) or 0
    end
    local function SpellName(id)
        if type(M.GetGameplaySpellName) == "function" then return M.GetGameplaySpellName(id) end
        return nil
    end
    local function SeedMeleeClass()
        if type(M.SeedGameplayMeleeSpellScope) == "function" then M.SeedGameplayMeleeSpellScope("class") end
    end
    local function SeedMeleeSpec()
        if type(M.SeedGameplayMeleeSpellScope) == "function" then M.SeedGameplayMeleeSpellScope("spec") end
    end
    local function SetMeleeSpellID(value)
        if type(M.SetGameplayMeleeSpellID) == "function" then return M.SetGameplayMeleeSpellID(value) end
        Gameplay().nameplateMeleeSpellID = floor((tonumber(value) or 0) + 0.5)
    end
    local timerControls, stateControls, totemControls = {}, {}, {}
    local crossControls, meleeControls = {}, {}
    local declarations = GameplayDeclarations(anchorValues,frameAnchors)
    local function Row(key,layout,apply)
        return GameplayRow(declarations,key,layout,apply,ApplyGameplayUI)
    end
    local function AddControls(list, section, specs)
        for _, spec in ipairs(specs) do
            if spec.kind == "slider" then spec.meta.step, spec.meta.roundStep = spec.range[3], true end
            list[#list + 1] = Schema.Render(ctx, section, spec)
        end
        return list
    end
    local function AddBackdrops(section, specs) for i = 1, #specs do local s = specs[i]; W.ControlCardBackdrop(section, 14, s[1], s[2], s[3]) end end
    local function AddTextInput(list,input,getValue,setValue,metadata,label)
        return BindGameplayText(ctx,list,input,getValue,setValue,metadata,ApplyGameplayUI,label)
    end
    local function AddGameplayTextInput(list, input, key)
        return AddTextInput(list, input, function() return Gameplay()[key] or Schema.Default("gameplay", key) end,
            function(v) Gameplay()[key] = tostring(v or "") end, Meta("setting." .. key),
            key == "combatStateEnterText" and "Enter text" or "Leave text")
    end
    local function GameplayStacked() return GameplayContentWidth(ctx) < 620 end
    local function SectionCardWidth(section, maxWidth)
        local sectionW = tonumber(section and section._msuf2Width) or GameplayContentWidth(ctx)
        return max(220, sectionW - 28)
    end
    local function SectionControlWidth(section, requested, minWidth)
        local sectionW = tonumber(section and section._msuf2Width) or GameplayContentWidth(ctx)
        return min(requested or 300, max(minWidth or 120, sectionW - 60))
    end
    local function SectionColumns(section, requested)
        local cardW = SectionCardWidth(section)
        local innerX = 32
        local gap = 36
        local innerW = max(160, cardW - 32)
        local colW = max(120, floor((innerW - gap) * 0.5))
        return innerX, innerX + colW + gap, min(requested or colW, colW), colW
    end

    local timerEnable = BuildGameplayTimer(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
        SectionColumns, AddBackdrops, AddControls, Row, timerControls, ApplyGameplayUI)
    local stateEnable = BuildGameplayState(ctx, b, GameplayStacked, SectionCardWidth, SectionControlWidth,
        SectionColumns, AddBackdrops, AddControls, Row, stateControls, ApplyGameplayUI, AddGameplayTextInput)
    local totemEnable, SyncTotemPreviewButton, totemActionControls = BuildGameplayTotems(ctx, b, GameplayStacked,
        SectionCardWidth, SectionControlWidth, SectionColumns, AddBackdrops, AddControls, Row, totemControls, ApplyGameplayUI)
    local crossEnable, specSpellToggle
    crossEnable, specSpellToggle, previewRefresh = BuildGameplayCrosshair(ctx, b, GameplayStacked, SectionCardWidth,
        SectionControlWidth, SectionColumns, AddBackdrops, AddControls, Row, crossControls, meleeControls, ApplyGameplayUI,
        SeedMeleeClass, SeedMeleeSpec, AddTextInput, CurrentMeleeSpellID, SetMeleeSpellID, SpellName)
    -- TotemFrame availability follows the same native frame as the runtime owner.
    -- The remaining rows combine client availability and the user's master toggle.
    disabledRefresh = M.BindGateGroup(ctx, Gameplay, {
        { enable = timerEnable, controls = timerControls, on = function(g) return g.enableCombatTimer == true end },
        { enable = stateEnable, controls = stateControls, on = function(g) return g.enableCombatStateText == true end },
        { enable = totemEnable, controls = totemActionControls, enableOn = TotemFrameAvailable, on = TotemFrameAvailable,
            reason = "Blizzard TotemFrame is not available on this client." },
        { controls = totemControls, on = function(g) return TotemFrameAvailable() and g.enablePlayerTotems == true end },
        { enable = crossEnable, controls = crossControls, on = function(g) return g.enableCombatCrosshair == true end },
        { controls = meleeControls, on = MeleeRangeEnabled },
        { controls = specSpellToggle, on = MeleeSpecEnabled,
            reason = "Specialization data is not available for this character yet." },
    }, { also = function()
        if previewRefresh then previewRefresh() end
        SyncTotemPreviewButton()
    end })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("gameplay", { title = "MSUF Gameplay", build = BuildGameplay, version = 10 })
