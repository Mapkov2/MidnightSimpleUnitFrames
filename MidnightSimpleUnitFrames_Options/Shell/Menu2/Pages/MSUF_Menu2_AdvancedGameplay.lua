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
local function TotemFrameAvailable() return TotemFrame ~= nil end
local function MeleeRangeEnabled(g)
    return g.enableCombatCrosshair == true and g.enableCombatCrosshairMeleeRangeColor == true
end
local function MeleeSpecEnabled(g)
    return MeleeRangeEnabled(g) and M.GetGameplayPlayerSpecID() ~= nil
end
local function GameplayDeclarations(anchorValues,frameAnchors)
    return {
        combatTimerAnchor = { "dropdown", "combatTimerAnchor", nil, { "Anchor", anchorValues } },
        combatFontSize = { "slider", "combatFontSize", nil, { "Timer size", 10, 64, 1 } },
        lockCombatTimer = { "flowToggle", "lockCombatTimer", nil, { "Lock position" } },
        combatTimerClickThrough = { "flowToggle", "combatTimerClickThrough", nil, { "Click-through (ALT to drag when unlocked)" } },
        combatOffsetX = { "slider", "combatOffsetX", nil, { "X offset", -800, 800, 1 } },
        combatOffsetY = { "slider", "combatOffsetY", nil, { "Y offset", -800, 800, 1 } },
        lockCombatState = { "flowToggle", "lockCombatState", nil, { "Lock position" } },
        combatStateFontSize = { "slider", "combatStateFontSize", nil, { "Text size", 10, 64, 1 } },
        combatStateDuration = { "slider", "combatStateDuration", nil, { "Duration (s)", 0.5, 5.0, 0.5 } },
        combatStateOffsetX = { "slider", "combatStateOffsetX", nil, { "X offset", -800, 800, 1 } },
        combatStateOffsetY = { "slider", "combatStateOffsetY", nil, { "Y offset", -800, 800, 1 } },
        playerTotemsIconSize = { "slider", "playerTotemsIconSize", nil, { "Icon size", 8, 64, 1 } },
        playerTotemsOffsetX = { "slider", "playerTotemsOffsetX", nil, { "X offset", -200, 200, 1 } },
        playerTotemsOffsetY = { "slider", "playerTotemsOffsetY", nil, { "Y offset", -200, 200, 1 } },
        playerTotemsAnchorFrom = { "dropdown", "playerTotemsAnchorFrom", nil, { "From", frameAnchors } },
        playerTotemsAnchorTo = { "dropdown", "playerTotemsAnchorTo", nil, { "To", frameAnchors } },
        enableCombatCrosshairMeleeRangeColor = { "flowToggle", "enableCombatCrosshairMeleeRangeColor", nil,
            { "Crosshair: color by melee range to target (green=in range, red=out)" } },
        meleeSpellPerClass = { "flowToggle", "meleeSpellPerClass", nil, { "Store per class" } },
        meleeSpellPerSpec = { "flowToggle", "meleeSpellPerSpec", nil, { "Store per spec" } },
        crosshairThickness = { "slider", "crosshairThickness", nil, { "Crosshair thickness", 1, 12, 1 } },
        crosshairSize = { "slider", "crosshairSize", nil, { "Crosshair size", 20, 120, 2 } },
    }
end
local function GameplayRow(declarations,key,layout,apply,defaultApply)
    local row = assert(declarations[key], "unknown Gameplay schema row")
    local fallback = Schema.Default("gameplay", key)
    row[3], row.meta, row.scope, row.domain = fallback, Meta("setting." .. key), "gameplay", "gameplay"
    if row[1] == "slider" then row[4][5] = layout.width or 280
    elseif row[1] == "dropdown" then row[4][3] = layout.width or 280 end
    row[5] = { layout.x, layout.y }
    row.get = function()
        local value = Gameplay()[key]
        if value == nil then return fallback end
        if row[1] == "slider" then return tonumber(value) or fallback end
        if row[1] == "flowToggle" then return value and true or false end
        return value
    end
    row.set = function(value)
        if row[1] == "dropdown" and not value then value = fallback end
        return AP.SetValue(Gameplay(), key, value, apply or defaultApply)
    end
    return row
end
local function SwitchAt(ctx, section, label, x, y, width, key, apply, meta)
    local fallback = Schema.Default("gameplay", key)
    return AP.Row(ctx, section, { "switch", key, fallback, { label, x, y, width },
        meta = meta, scope = "gameplay", domain = "gameplay",
        get = function() return AP.BoolValue(Gameplay(), key, fallback) end,
        set = function(value) return AP.SetValue(Gameplay(), key, value, apply) end,
    })
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
local TOTEM_LAYOUT_KEYS = { "playerTotemsIconSize", "playerTotemsOffsetX", "playerTotemsOffsetY",
    "playerTotemsAnchorFrom", "playerTotemsAnchorTo" }
-- Search metadata plus schema declaration for one totem button; only Preview reads runtime state.
local function RegisterTotemButton(button, label, path, classification, domain, getState)
    local meta = Meta(path, classification)
    RegisterControl(button, meta, label, "button")
    local action = Schema.ButtonAction(button)
    Schema.Custom(button, {
        id = meta.controlId, kind = "button", labelKey = label, meta = meta,
        scope = "gameplay", applyDomain = domain, gate = TotemFrameAvailable,
        get = getState, actionKey = meta.actionKey, set = action,
        action = action, owner = button,
    })
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
    RegisterTotemButton(previewBtn, "Preview", "totem_frame.preview", "ephemeral", "totemPreview",
        MSUF.MSUF_PlayerTotems_IsPreviewActive)
    resetTotemBtn:SetScript("OnClick", function()
        local g = Gameplay()
        for _, key in ipairs(TOTEM_LAYOUT_KEYS) do g[key] = Schema.Default("gameplay", key) end
        ApplyGameplayUI()
        if M.RequestRefresh then M.RequestRefresh(ctx, "advanced-gameplay-totems-reset") elseif M.Refresh then M.Refresh(ctx) end
    end)
    RegisterTotemButton(resetTotemBtn, "Reset TotemFrame layout", "totem_frame.reset_layout", "action", "gameplay")
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

-- Layout geometry of one section. `requested` caps the stacked control width and the column
-- width; `width` is the raw section width the label rows measure against.
local function SectionGeometry(ctx, section, requested)
    local sectionW = tonumber(section._msuf2Width) or GameplayContentWidth(ctx)
    local cardW = max(220, sectionW - 28)
    local gap = 36
    local colW = max(120, floor((max(160, cardW - 32) - gap) * 0.5))
    return {
        width = section._msuf2Width or ctx.width or 900, cardW = cardW,
        controlW = min(requested, max(120, sectionW - 60)),
        left = 32, right = 32 + colW + gap, colW = min(requested, colW),
    }
end
-- Stacked layouts put every control at x = 30 with the control width; wide layouts use two columns.
local function Columns(stacked, g)
    if stacked then return 30, 30, g.controlW end
    return g.left, g.right, g.colW
end
local function OpenSection(env, id, title, stackedHeight, wideHeight, expanded)
    local stacked = GameplayContentWidth(env.ctx) < 620
    local section = env.b:CollapsibleSection(id, title, stacked and stackedHeight or wideHeight, expanded)
    Schema.Section(section, "gameplay")
    return section, stacked
end
local function AddCards(section, cardW, ys)
    for i = 1, #ys, 2 do W.ControlCardBackdrop(section, 14, ys[i], cardW, ys[i + 1]) end
end
local function AddRow(env, list, section, key, x, y, width, apply)
    local spec = GameplayRow(env.declarations, key, { x = x, y = y, width = width }, apply, env.apply)
    if spec[1] == "slider" then spec.roundStep = true end
    list[#list + 1] = AP.Row(env.ctx, section, spec)
end
-- Rows are { key, wide column, stacked y, wide y, stacked width cap, wide width cap, apply }.
local function PlaceRows(env, list, section, stacked, g, rows)
    for i = 1, #rows do
        local r = rows[i]
        if stacked then
            AddRow(env, list, section, r[1], 30, r[3], r[5] and min(r[5], g.controlW) or g.controlW, r[7])
        else
            AddRow(env, list, section, r[1], r[2] == 2 and g.right or g.left, r[4],
                r[6] and min(r[6], g.colW) or g.colW, r[7])
        end
    end
end
local function AttachTextShortcut(section, title, historyLabel, historySource, kind, references, colorTitle, subtitle)
    if not W.AttachContextColorShortcut then return end
    W.AttachContextColorShortcut(section, {
        title = title,
        historyLabel = historyLabel,
        historySource = historySource,
        offsetY = -8,
        textSettings = {
            scope = "shared",
            kind = kind,
            colorReferences = references,
            colorTitle = colorTitle,
            subtitle = subtitle,
            capabilities = { baseline = false },
        },
    })
end
local function AddLockTooltip(toggle, text)
    if type(M.AddTooltip) == "function" and toggle then
        M.AddTooltip(toggle, "Lock position", text, { hook = true, labelHit = true })
    end
end
local function AddGameplayTextInput(env, list, input, key)
    return BindGameplayText(env.ctx, list, input, function() return Gameplay()[key] or Schema.Default("gameplay", key) end,
        function(v) Gameplay()[key] = tostring(v or "") end, Meta("setting." .. key), env.apply,
        key == "combatStateEnterText" and "Enter text" or "Leave text")
end
local function CurrentMeleeSpellID()
    if type(M.GetGameplayMeleeSpellID) == "function" then return M.GetGameplayMeleeSpellID(Gameplay()) end
    return tonumber(Gameplay().nameplateMeleeSpellID) or 0
end
local function SpellName(id)
    if type(M.GetGameplaySpellName) == "function" then return M.GetGameplaySpellName(id) end
    return nil
end
local function SeedMeleeScope(scope)
    if type(M.SeedGameplayMeleeSpellScope) == "function" then M.SeedGameplayMeleeSpellScope(scope) end
end
local function SetMeleeSpellID(value)
    if type(M.SetGameplayMeleeSpellID) == "function" then return M.SetGameplayMeleeSpellID(value) end
    Gameplay().nameplateMeleeSpellID = floor((tonumber(value) or 0) + 0.5)
end

local TIMER_ROWS = {
    { "combatTimerAnchor", 2, -84, -40, 220, 220 },
    { "combatFontSize", 1, -138, -94, nil, 270 },
    { "lockCombatTimer", 2, -192, -100 },
    { "combatTimerClickThrough", 2, -224, -132 },
}
local TIMER_OFFSET_ROWS = {
    { "combatOffsetX", 1, -316, -216 },
    { "combatOffsetY", 2, -386, -216 },
}
local function BuildGameplayTimer(env, controls)
    --- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local timer, stacked = OpenSection(env, "gameplay_timer", "Combat Timer", 570, 430, true)
    AttachTextShortcut(timer, "Combat Timer Text Settings", "Combat timer color", "menu:gameplay-timer-color",
        "gameplay_timer", { "gameplay.timer" }, "Combat Timer Color", "Combat Timer text follows the shared Fonts settings.")
    local geo = SectionGeometry(env.ctx, timer, 300)
    local x1, _, w = Columns(stacked, geo)
    AddCards(timer, geo.cardW, stacked and { -38, 220, -274, 238 } or { -38, 126, -178, 150 })
    local enable = SwitchAt(env.ctx, timer, "Combat Timer", x1, -40, min(230, w), "enableCombatTimer", env.apply, Meta("timer.enabled"))
    PlaceRows(env, controls, timer, stacked, geo, TIMER_ROWS)
    LabelAt(timer, "Timer position (offset)", 30, stacked and -284 or -186, 260, "GameFontHighlightSmall", T.colors.muted)
    PlaceRows(env, controls, timer, stacked, geo, TIMER_OFFSET_ROWS)
    LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, stacked and -492 or -312, min(520, geo.width - 60), "GameFontDisableSmall", T.colors.muted)
    -- controls[3] is the timer's "Lock position" toggle in both layouts above.
    AddLockTooltip(controls[3], "While unlocked, the Combat Timer stays visible out of combat as a movable 0:00 placeholder. Drag it with the mouse or nudge it with the arrow keys - with click-through enabled, hold ALT to drag. Lock it to freeze the position.")
    return enable
end

local STATE_ROWS = {
    { "combatStateFontSize", 1, -258, -152 },
    { "combatStateDuration", 2, -328, -152 },
    { "combatStateOffsetX", 1, -398, -238 },
    { "combatStateOffsetY", 2, -468, -238 },
}
local function BuildGameplayState(env, controls)
    local state, stacked = OpenSection(env, "gameplay_state", "Combat Enter/Leave", 580, 340, false)
    AttachTextShortcut(state, "Combat State Text Settings", "Combat state colors", "menu:gameplay-state-colors",
        "gameplay_state", { "gameplay.enter", "gameplay.leave" }, "Combat State Colors",
        "Combat Enter/Leave text follows the shared Fonts settings.")
    local geo = SectionGeometry(env.ctx, state, 260)
    local x1, x2, w = Columns(stacked, geo)
    AddCards(state, geo.cardW, stacked and { -38, 196, -250, 282 } or { -38, 136, -144, 154 })
    local enable = SwitchAt(env.ctx, state, "Combat Enter/Leave", x1, -40, min(270, w), "enableCombatStateText", env.apply, Meta("combat_state.enabled"))
    AddRow(env, controls, state, "lockCombatState", x2, stacked and -74 or -40)
    local inputW = stacked and w or min(220, w)
    local enterInput = MoveWidget(W.TextInput(state, "Enter text", inputW), state, x1, stacked and -120 or -86)
    local leaveInput = MoveWidget(W.TextInput(state, "Leave text", inputW), state, x2, stacked and -174 or -86)
    PlaceRows(env, controls, state, stacked, geo, STATE_ROWS)
    -- controls[1] is the "Lock position" toggle in both layouts above.
    AddLockTooltip(controls[1], "While unlocked, the Combat Enter/Leave text is shown permanently as a movable handle. Drag it with the mouse or nudge it with the arrow keys. Lock it so the text only appears when entering or leaving combat.")
    AddGameplayTextInput(env, controls, enterInput, "combatStateEnterText")
    AddGameplayTextInput(env, controls, leaveInput, "combatStateLeaveText")
    return enable
end

local TOTEM_ROWS = {
    { "playerTotemsIconSize", 2, -238, -84 },
    { "playerTotemsOffsetX", 2, -308, -168 },
    { "playerTotemsOffsetY", 2, -378, -252 },
}
local function BuildGameplayTotems(env, controls)
    local ctx = env.ctx
    local sec, stacked = OpenSection(env, "gameplay_class_specific", "Class-specific toggles", 620, 390, false)
    local geo = SectionGeometry(ctx, sec, 300)
    local x1, _, w = Columns(stacked, geo)
    local description = TotemFrameAvailable()
        and "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat."
        or "Blizzard TotemFrame is not available on this client."
    AddCards(sec, geo.cardW, stacked and { -38, 520 } or { -38, 276 })
    LabelAt(sec, "Totem / Statue frame", x1, -38, min(360, stacked and geo.width - 60 or w), "GameFontNormalSmall", T.colors.text)
    LabelAt(sec, description, x1, -60, min(520, stacked and geo.width - 60 or geo.cardW - 32), "GameFontDisableSmall", T.colors.muted)
    local enable = SwitchAt(ctx, sec, "Blizzard TotemFrame", x1, -92, min(300, w), "enablePlayerTotems", env.apply, Meta("totem_frame.enabled"))
    local previewBtn = T.Button(sec, "Preview", stacked and min(120, w) or 120, 22)
    previewBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", stacked and 32 or x1, -128)
    local resetTotemBtn = T.Button(sec, "Reset TotemFrame layout", stacked and min(190, w) or 190, 22)
    -- Buttons live in the left column; the sliders own everything from the right column on.
    local btnRowW = max(160, geo.right - geo.left - 12)
    local rowShift = 0
    if stacked then
        resetTotemBtn:SetPoint("TOPLEFT", sec, "TOPLEFT", 32, -160)
        T.FitButtonWidth(previewBtn, 90, max(120, geo.cardW - 64))
        T.FitButtonWidth(resetTotemBtn, 140, max(190, geo.cardW - 64))
    else
        T.FitButtonWidth(previewBtn, 90, btnRowW)
        local previewW = previewBtn:GetWidth() or 120
        local resetW = T.MeasureButtonWidth(resetTotemBtn, 140, btnRowW)
        resetTotemBtn:SetWidth(resetW)
        -- Long translations ("Réinitialiser la disposition TotemFrame") cannot share the row with
        -- Preview, so the pair wraps to a second line instead of truncating.
        local wrapped = (previewW + 12 + resetW) > btnRowW
        rowShift = wrapped and 30 or 0
        if wrapped then
            resetTotemBtn:SetPoint("TOPLEFT", previewBtn, "BOTTOMLEFT", 0, -8)
        else
            resetTotemBtn:SetPoint("TOPLEFT", previewBtn, "TOPRIGHT", 12, 0)
        end
    end
    LabelAt(sec, "Tip: Move the preview via mousedrag or arrow keys.", x1, stacked and -196 or -158 - rowShift,
        min(520, stacked and geo.width - 60 or geo.cardW - 32), "GameFontDisableSmall", T.colors.muted)
    PlaceRows(env, controls, sec, stacked, geo, TOTEM_ROWS)
    -- From/To share one row, so both come out of the same split. Sizing the width and the
    -- second column from unrelated formulas let them overlap each other and bleed into the
    -- slider column at every content width.
    local anchorGap = 12
    local anchorW = stacked and min(220, w) or min(180, max(96, floor((btnRowW - anchorGap) * 0.5)))
    local fromY = stacked and -448 or -202 - rowShift
    AddRow(env, controls, sec, "playerTotemsAnchorFrom", x1, fromY, anchorW)
    AddRow(env, controls, sec, "playerTotemsAnchorTo", stacked and 30 or x1 + anchorW + anchorGap,
        stacked and -502 or fromY, anchorW)
    local SyncTotemPreviewButton = BindTotemActions(ctx, previewBtn, resetTotemBtn, env.apply)
    return enable, SyncTotemPreviewButton, { previewBtn, resetTotemBtn }
end

local CROSS_ROWS = {
    { "crosshairThickness", 2, -560, -334 },
    { "crosshairSize", 2, -630, -418 },
}
local function BuildGameplayCrosshair(env, controls, meleeControls)
    local ctx = env.ctx
    local cross, stacked = OpenSection(env, "gameplay_crosshair", "Combat Crosshair", 800, 588, false)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(cross, { "gameplay.crosshair_in", "gameplay.crosshair_out" }, {
            title = "Combat Crosshair Colors",
            note = "Used when melee-range coloring is enabled.",
            historySource = "menu:gameplay-crosshair-colors",
            offsetY = -8,
        })
    end
    local geo = SectionGeometry(ctx, cross, 300)
    local x1, x2, w = Columns(stacked, geo)
    local spellInputW = min(260, w)
    local function MeleeScopeApply(key, scope)
        return function()
            if Gameplay()[key] then SeedMeleeScope(scope) end
            env.apply()
        end
    end
    AddCards(cross, geo.cardW, stacked and { -38, 332, -390, 346 } or { -38, 242, -312, 214 })
    local enable = SwitchAt(ctx, cross, "Combat Crosshair", x1, -40, min(390, w), "enableCombatCrosshair", env.apply, Meta("crosshair.enabled"))
    AddRow(env, controls, cross, "enableCombatCrosshairMeleeRangeColor", x1, -74)
    local noteX = stacked and 54 or x1 + 24
    LabelAt(cross, "Uses the spell selected below.", noteX, -104, min(420, stacked and geo.width - 82 or w), "GameFontDisableSmall", T.colors.muted)
    local noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", noteX, -126,
        min(520, stacked and geo.width - 82 or geo.cardW - 56), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
    local spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, x1, stacked and -178 or -170)
    local infoX, infoW = stacked and 30 or x2, min(360, stacked and geo.width - 60 or w)
    local selectedSpellText = LabelAt(cross, "", infoX, stacked and -242 or -192, infoW, "GameFontDisableSmall", T.colors.muted)
    LabelAt(cross, "Used by: Crosshair melee-range color.", infoX, stacked and -264 or -214, infoW, "GameFontDisableSmall", T.colors.muted)
    AddRow(env, controls, cross, "meleeSpellPerClass", x2, stacked and -298 or -244, nil, MeleeScopeApply("meleeSpellPerClass", "class"))
    AddRow(env, controls, cross, "meleeSpellPerSpec", stacked and 30 or x2 + min(180, w * 0.52), stacked and -332 or -244, nil,
        MeleeScopeApply("meleeSpellPerSpec", "spec"))
    local classSpellToggle, specSpellToggle = controls[#controls - 1], controls[#controls]
    local preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cross, "TOPLEFT", stacked and 32 or x1, stacked and -412 or -312)
    preview:SetSize(stacked and min(260, max(160, geo.cardW - 28)) or spellInputW, 120)
    PlaceRows(env, controls, cross, stacked, geo, CROSS_ROWS)
    LabelAt(cross, "Colors are configured in Colors > Gameplay.", infoX, stacked and -734 or -514, infoW, "GameFontDisableSmall", T.colors.muted)
    StyleMeleeSpellInput(spellInput, spellInputW)
    BindGameplayText(ctx, controls, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v) SetMeleeSpellID(v) end,
        Meta("crosshair.melee_spell"), env.apply, "Choose spell ID or name")
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
        -- Bars 1/2 are the left/right arms, 3/4 the top/bottom arms; sign is the side of the centre.
        local reach, arm = size * 0.28, size * 0.42
        for i = 1, 4 do
            local bar, sign = bars[i], (i == 1 or i == 4) and -1 or 1
            bar:ClearAllPoints()
            if i <= 2 then
                bar:SetPoint("CENTER", preview, "TOPLEFT", centerX + sign * gap + sign * reach, centerY)
                bar:SetSize(arm, thick)
            else
                bar:SetPoint("CENTER", preview, "TOPLEFT", centerX, centerY + sign * gap + sign * reach)
                bar:SetSize(thick, arm)
            end
            bar:SetVertexColor(r or 1, gr or 0, b or 0, g.enableCombatCrosshair and 1 or 0.35)
        end
    end
    return enable, specSpellToggle, previewRefresh
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
    local env = { ctx = ctx, b = b, apply = ApplyGameplayUI,
        declarations = GameplayDeclarations(anchorValues, frameAnchors) }
    local timerControls, stateControls, totemControls = {}, {}, {}
    local crossControls, meleeControls = {}, {}

    local timerEnable = BuildGameplayTimer(env, timerControls)
    local stateEnable = BuildGameplayState(env, stateControls)
    local totemEnable, SyncTotemPreviewButton, totemActionControls = BuildGameplayTotems(env, totemControls)
    local crossEnable, specSpellToggle
    crossEnable, specSpellToggle, previewRefresh = BuildGameplayCrosshair(env, crossControls, meleeControls)
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
