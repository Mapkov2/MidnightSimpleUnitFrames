local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Gameplay page.
-- Builds controls for optional gameplay helpers such as combat timer, crosshair, melee range,
-- and totem/statue frames. Live frame work belongs to GameplayRuntime.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local Gameplay, MoveWidget, LabelAt, SwitchAt, AddTableControlSpecs, ControlMeta, RegisterControl = M.Pick(AP, [[Gameplay MoveWidget LabelAt SwitchAt AddTableControlSpecs ControlMeta RegisterControl]])
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
local VT = M.ValueTextList
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
    local anchorValues = VT("none", "None", "player", "Player", "target", "Target", "focus", "Focus")
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
    local crossControls, meleeControls = {}, {}, {}
    local selectedSpellText
    local noSpellWarn
    local CONTROL_KEY_INDEX = { toggle = 5, switch = 6, slider = 9, dropdown = 7 }
    local function AddControls(list, section, specs)
        for i = 1, #specs do
            local spec = specs[i]
            local key = spec[CONTROL_KEY_INDEX[spec[1]]]
            spec.meta = spec.meta or Meta("setting." .. tostring(key))
        end
        return AddTableControlSpecs(ctx, list, section, Gameplay, specs, ApplyGameplayUI)
    end
    local function AddBackdrops(section, specs) for i = 1, #specs do local s = specs[i]; W.ControlCardBackdrop(section, 14, s[1], s[2], s[3]) end end
    local function AddTextInput(list, input, getValue, setValue, metadata)
        M.BindTextInput(ctx, input, getValue, function(v) setValue(v); ApplyGameplayUI() end, true, metadata)
        M.AppendValues(list, input)
    end
    local function AddGameplayTextInput(list, input, key, fallback)
        return AddTextInput(list, input, function() return Gameplay()[key] or fallback end,
            function(v) Gameplay()[key] = tostring(v or "") end, Meta("setting." .. key))
    end
    local function PaintSpellInput(input, edgeAlpha, withFill, withBorder)
        local accent = T.colors.accent
        if withFill and input._msuf2SpellInputFill then input._msuf2SpellInputFill:SetVertexColor(0.025, 0.034, 0.070, 0.98) end
        if input._msuf2SpellInputEdge then input._msuf2SpellInputEdge:SetVertexColor(accent[1], accent[2], accent[3], edgeAlpha) end
        if withFill and input.SetBackdropColor then input:SetBackdropColor(0.025, 0.034, 0.070, 0.98) end
        if withBorder and input.SetBackdropBorderColor then input:SetBackdropBorderColor(accent[1], accent[2], accent[3], edgeAlpha) end
    end
    local function GameplayContentWidth()
        return min(tonumber(M.formContentMaxWidth) or 980, tonumber(ctx.width) or 900)
    end
    local function GameplayStacked() return GameplayContentWidth() < 620 end
    local function SectionCardWidth(section, maxWidth)
        local sectionW = tonumber(section and section._msuf2Width) or GameplayContentWidth()
        return max(220, sectionW - 28)
    end
    local function SectionControlWidth(section, requested, minWidth)
        local sectionW = tonumber(section and section._msuf2Width) or GameplayContentWidth()
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

    --- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local compactTimer = GameplayStacked()
    local timer = b:CollapsibleSection("gameplay_timer", "Combat Timer", compactTimer and 570 or 430, true)
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
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", 30, -40, min(230, timerSliderW), Gameplay, "enableCombatTimer", false, ApplyGameplayUI, Meta("timer.enabled"))
        AddControls(timerControls, timer, {
            { "dropdown", "Anchor", 30, -84, anchorValues, min(220, timerSliderW), "combatTimerAnchor", "none" },
            { "slider", "Timer size", 30, -138, 10, 64, 1, timerSliderW, "combatFontSize", 24 },
            { "toggle", "Lock position", 30, -192, "lockCombatTimer", false },
            { "toggle", "Click-through (ALT to drag when unlocked)", 30, -224, "combatTimerClickThrough", false },
        })
        LabelAt(timer, "Timer position (offset)", 30, -284, 260, "GameFontHighlightSmall", T.colors.muted)
        AddControls(timerControls, timer, {
            { "slider", "X offset", 30, -316, -800, 800, 1, timerSliderW, "combatOffsetX", 0 },
            { "slider", "Y offset", 30, -386, -800, 800, 1, timerSliderW, "combatOffsetY", -200 },
        })
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -492, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        AddBackdrops(timer, { { -38, timerCardW, 126 }, { -178, timerCardW, 150 } })
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", timerLeftX, -40, min(230, timerColW), Gameplay, "enableCombatTimer", false, ApplyGameplayUI, Meta("timer.enabled"))
        AddControls(timerControls, timer, {
            { "dropdown", "Anchor", timerRightX, -40, anchorValues, min(220, timerColW), "combatTimerAnchor", "none" },
            { "slider", "Timer size", timerLeftX, -94, 10, 64, 1, min(270, timerColW), "combatFontSize", 24 },
            { "toggle", "Lock position", timerRightX, -100, "lockCombatTimer", false },
            { "toggle", "Click-through (ALT to drag when unlocked)", timerRightX, -132, "combatTimerClickThrough", false },
        })
        LabelAt(timer, "Timer position (offset)", 30, -186, 260, "GameFontHighlightSmall", T.colors.muted)
        AddControls(timerControls, timer, {
            { "slider", "X offset", timerLeftX, -216, -800, 800, 1, timerColW, "combatOffsetX", 0 },
            { "slider", "Y offset", timerRightX, -216, -800, 800, 1, timerColW, "combatOffsetY", -200 },
        })
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -312, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    end
    local stateStacked = GameplayStacked()
    local state = b:CollapsibleSection("gameplay_state", "Combat Enter/Leave", stateStacked and 580 or 340, false)
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
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", 30, -40, min(270, stateControlW), Gameplay, "enableCombatStateText", false, ApplyGameplayUI, Meta("combat_state.enabled"))
        AddControls(stateControls, state, { { "toggle", "Lock position", 30, -74, "lockCombatState", false } })
        enterInput = MoveWidget(W.TextInput(state, "Enter text", stateControlW), state, 30, -120)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", stateControlW), state, 30, -174)
        AddControls(stateControls, state, {
            { "slider", "Text size", 30, -258, 10, 64, 1, stateControlW, "combatStateFontSize", 24 },
            { "slider", "Duration (s)", 30, -328, 0.5, 5.0, 0.5, stateControlW, "combatStateDuration", 1.5 },
            { "slider", "X offset", 30, -398, -800, 800, 1, stateControlW, "combatStateOffsetX", 0 },
            { "slider", "Y offset", 30, -468, -800, 800, 1, stateControlW, "combatStateOffsetY", 80 },
        })
    else
        AddBackdrops(state, { { -38, stateCardW, 136 }, { -144, stateCardW, 154 } })
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", stateLeftX, -40, min(270, stateColW), Gameplay, "enableCombatStateText", false, ApplyGameplayUI, Meta("combat_state.enabled"))
        AddControls(stateControls, state, { { "toggle", "Lock position", stateRightX, -40, "lockCombatState", false } })
        enterInput = MoveWidget(W.TextInput(state, "Enter text", min(220, stateColW)), state, stateLeftX, -86)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", min(220, stateColW)), state, stateRightX, -86)
        AddControls(stateControls, state, {
            { "slider", "Text size", stateLeftX, -152, 10, 64, 1, stateColW, "combatStateFontSize", 24 },
            { "slider", "Duration (s)", stateRightX, -152, 0.5, 5.0, 0.5, stateColW, "combatStateDuration", 1.5 },
            { "slider", "X offset", stateLeftX, -238, -800, 800, 1, stateColW, "combatStateOffsetX", 0 },
            { "slider", "Y offset", stateRightX, -238, -800, 800, 1, stateColW, "combatStateOffsetY", 80 },
        })
    end
    AddGameplayTextInput(stateControls, enterInput, "combatStateEnterText", "+Combat")
    AddGameplayTextInput(stateControls, leaveInput, "combatStateLeaveText", "-Combat")
    local classStacked = GameplayStacked()
    local classSec = b:CollapsibleSection("gameplay_class_specific", "Class-specific toggles", classStacked and 620 or 390, false)
    local classW = classSec._msuf2Width or ctx.width or 900
    local classCardW = SectionCardWidth(classSec, 700)
    local classControlW = SectionControlWidth(classSec, 300, 120)
    local classLeftX, classRightX, classColW = SectionColumns(classSec, 300)
    local totemEnable
    local previewBtn
    local resetTotemBtn
    if classStacked then
        AddBackdrops(classSec, { { -38, classCardW, 520 } })
        LabelAt(classSec, "Totem / Statue frame", 30, -38, min(360, classW - 60), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", 30, -60, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", 30, -92, min(300, classControlW), Gameplay, "enablePlayerTotems", false, ApplyGameplayUI, Meta("totem_frame.enabled"))
        previewBtn = T.Button(classSec, "Preview", min(120, classControlW), 22)
        previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 32, -128)
        T.FitButtonWidth(previewBtn, 90, max(120, classCardW - 64))
        resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", min(190, classControlW), 22)
        resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 32, -160)
        T.FitButtonWidth(resetTotemBtn, 140, max(190, classCardW - 64))
        LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", 30, -196, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        AddControls(totemControls, classSec, {
            { "slider", "Icon size", 30, -238, 8, 64, 1, classControlW, "playerTotemsIconSize", 24 },
            { "slider", "X offset", 30, -308, -200, 200, 1, classControlW, "playerTotemsOffsetX", 0 },
            { "slider", "Y offset", 30, -378, -200, 200, 1, classControlW, "playerTotemsOffsetY", -6 },
            { "dropdown", "From", 30, -448, frameAnchors, min(220, classControlW), "playerTotemsAnchorFrom", "TOPLEFT" },
            { "dropdown", "To", 30, -502, frameAnchors, min(220, classControlW), "playerTotemsAnchorTo", "BOTTOMLEFT" },
        })
    else
        AddBackdrops(classSec, { { -38, classCardW, 276 } })
        LabelAt(classSec, "Totem / Statue frame", classLeftX, -38, min(360, classColW), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", classLeftX, -60, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", classLeftX, -92, classColW, Gameplay, "enablePlayerTotems", false, ApplyGameplayUI, Meta("totem_frame.enabled"))
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
            { "slider", "Icon size", classRightX, -84, 8, 64, 1, classColW, "playerTotemsIconSize", 24 },
            { "slider", "X offset", classRightX, -168, -200, 200, 1, classColW, "playerTotemsOffsetX", 0 },
            { "slider", "Y offset", classRightX, -252, -200, 200, 1, classColW, "playerTotemsOffsetY", -6 },
            { "dropdown", "From", classLeftX, -202 - rowShift, frameAnchors, anchorW, "playerTotemsAnchorFrom", "TOPLEFT" },
            { "dropdown", "To", classLeftX + anchorW + anchorGap, -202 - rowShift, frameAnchors, anchorW, "playerTotemsAnchorTo", "BOTTOMLEFT" },
        })
    end
    -- The runtime owns preview state and drops it on its own (class without a TotemFrame, or the
    -- master toggle going off), so the button reads it back rather than tracking a local flag.
    local function SyncTotemPreviewButton()
        local active = type(MSUF.MSUF_PlayerTotems_IsPreviewActive) == "function"
            and MSUF.MSUF_PlayerTotems_IsPreviewActive() == true
        T.ApplyButtonRole(previewBtn, active and "success" or "normal")
    end
    previewBtn:SetScript("OnClick", function()
        if MSUF and type(MSUF.MSUF_PlayerTotems_TogglePreview) == "function" then MSUF.MSUF_PlayerTotems_TogglePreview() end
        SyncTotemPreviewButton()
    end)
    SyncTotemPreviewButton()
    RegisterControl(previewBtn, Meta("totem_frame.preview", "ephemeral"), "Preview", "button")
    resetTotemBtn:SetScript("OnClick", function()
        local g = Gameplay()
        g.playerTotemsIconSize = 24
        g.playerTotemsOffsetX = 0
        g.playerTotemsOffsetY = -6
        g.playerTotemsAnchorFrom = "TOPLEFT"
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
        ApplyGameplayUI()
        if M.RequestRefresh then M.RequestRefresh(ctx, "advanced-gameplay-totems-reset") elseif M.Refresh then M.Refresh(ctx) end
    end)
    RegisterControl(resetTotemBtn, Meta("totem_frame.reset_layout", "action"), "Reset TotemFrame layout", "button")
    local totemActionControls = { previewBtn, resetTotemBtn }
    local crossStacked = GameplayStacked()
    local cross = b:CollapsibleSection("gameplay_crosshair", "Combat Crosshair", crossStacked and 800 or 588, false)
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
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", 30, -40, min(390, crossControlW), Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI, Meta("crosshair.enabled"))
        AddControls(crossControls, cross, { { "toggle", "Crosshair: color by melee range to target (green=in range, red=out)", 30, -74, "enableCombatCrosshairMeleeRangeColor", false } })
        LabelAt(cross, "Uses the spell selected below.", 54, -104, min(420, crossW - 82), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", 54, -126, min(520, crossW - 82), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, 30, -178)
        selectedSpellText = LabelAt(cross, "", 30, -242, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", 30, -264, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        AddControls(crossControls, cross, {
            { "toggle", "Store per class", 30, -298, "meleeSpellPerClass", false, ApplyMeleeClassScope },
            { "toggle", "Store per spec", 30, -332, "meleeSpellPerSpec", false, ApplyMeleeSpecScope },
        })
        classSpellToggle, specSpellToggle = crossControls[#crossControls - 1], crossControls[#crossControls]
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", 32, -412)
        preview:SetSize(min(260, max(160, crossCardW - 28)), 120)
        AddControls(crossControls, cross, {
            { "slider", "Crosshair thickness", 30, -560, 1, 12, 1, crossControlW, "crosshairThickness", 3 },
            { "slider", "Crosshair size", 30, -630, 20, 120, 2, crossControlW, "crosshairSize", 40 },
        })
        LabelAt(cross, "Colors are configured in Colors > Gameplay.", 30, -734, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        spellInputW = min(260, crossColW)
        AddBackdrops(cross, { { -38, crossCardW, 242 }, { -312, crossCardW, 214 } })
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", crossLeftX, -40, min(390, crossColW), Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI, Meta("crosshair.enabled"))
        AddControls(crossControls, cross, { { "toggle", "Crosshair: color by melee range to target (green=in range, red=out)", crossLeftX, -74, "enableCombatCrosshairMeleeRangeColor", false } })
        LabelAt(cross, "Uses the spell selected below.", crossLeftX + 24, -104, min(420, crossColW), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", crossLeftX + 24, -126, min(520, crossCardW - 56), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, crossLeftX, -170)
        selectedSpellText = LabelAt(cross, "", crossRightX, -192, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", crossRightX, -214, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        AddControls(crossControls, cross, {
            { "toggle", "Store per class", crossRightX, -244, "meleeSpellPerClass", false, ApplyMeleeClassScope },
            { "toggle", "Store per spec", crossRightX + min(180, crossColW * 0.52), -244, "meleeSpellPerSpec", false, ApplyMeleeSpecScope },
        })
        classSpellToggle, specSpellToggle = crossControls[#crossControls - 1], crossControls[#crossControls]
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", crossLeftX, -312)
        preview:SetSize(min(260, crossColW), 120)
        AddControls(crossControls, cross, {
            { "slider", "Crosshair thickness", crossRightX, -334, 1, 12, 1, crossColW, "crosshairThickness", 3 },
            { "slider", "Crosshair size", crossRightX, -418, 20, 120, 2, crossColW, "crosshairSize", 40 },
        })
        LabelAt(cross, "Colors are configured in Colors > Gameplay.", crossRightX, -514, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
    end
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
    AddTextInput(crossControls, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v) SetMeleeSpellID(v) end,
        Meta("crosshair.melee_spell"))
    M.AppendValues(meleeControls, spellInput, classSpellToggle, specSpellToggle)
    local bars = {}
    for i = 1, 4 do
        bars[i] = preview:CreateTexture(nil, "ARTWORK")
        bars[i]:SetColorTexture(1, 0, 0, 1)
    end
    previewRefresh = function()
        local g = Gameplay()
        local id = CurrentMeleeSpellID()
        local name = SpellName(id)
        if selectedSpellText then selectedSpellText:SetText((id > 0 and M.Format(M.Tr("Selected: %s (%d)"), name or M.Tr("Spell"), id)) or M.Tr("Selected: none")) end
        if noSpellWarn then noSpellWarn:SetShown((g.enableCombatCrosshairMeleeRangeColor == true) and id <= 0) end
        local size = math.max(20, tonumber(g.crosshairSize) or 40)
        local thick = math.max(1, tonumber(g.crosshairThickness) or 3)
        local previewW = (preview and preview.GetWidth and preview:GetWidth()) or 260
        local previewH = (preview and preview.GetHeight and preview:GetHeight()) or 120
        local centerX, centerY = previewW * 0.5, -(previewH * 0.5)
        local gap = math.max(6, floor(size * 0.20))
        local r, gr, b = 0, 1, 0
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
    -- Each row gates a dependent control group by its master toggle. Blizzard's TotemFrame is
    -- class-agnostic, so the totem rows carry no class gate: Preview and Reset stay live for
    -- everyone, the offset controls follow the master toggle.
    disabledRefresh = M.BindGateGroup(ctx, Gameplay, {
        { enable = timerEnable, controls = timerControls, on = function(g) return g.enableCombatTimer == true end },
        { enable = stateEnable, controls = stateControls, on = function(g) return g.enableCombatStateText == true end },
        { enable = totemEnable, controls = totemActionControls, on = function() return true end },
        { controls = totemControls, on = function(g) return g.enablePlayerTotems == true end },
        { enable = crossEnable, controls = crossControls, on = function(g) return g.enableCombatCrosshair == true end },
        { controls = meleeControls, on = function(g)
            return g.enableCombatCrosshair == true and g.enableCombatCrosshairMeleeRangeColor == true
        end },
    }, { also = function()
        M.CallIf(previewRefresh)
        SyncTotemPreviewButton()
    end })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("gameplay", { title = "MSUF Gameplay", build = BuildGameplay, version = 3 })
