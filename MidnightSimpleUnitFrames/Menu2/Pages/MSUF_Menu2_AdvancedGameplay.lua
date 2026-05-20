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
local MoveWidget = AP.MoveWidget
local LabelAt = AP.LabelAt
local DividerAt = AP.DividerAt
local BindValueToggle = AP.BindValueToggle
local BindValueSlider = AP.BindValueSlider
local ToggleAt = AP.ToggleAt
local SwitchAt = AP.SwitchAt
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
local function ApplyGameplay()
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
    end
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

local function BuildGameplay(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Gameplay", "Here are several gameplay enhancement options you can toggle on or off.", 74)

    local edit = T.Button(head, "MSUF Edit Mode", 128, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(edit) end
    edit:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -20)
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
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshEditButton)
        else
            RefreshEditButton()
        end
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    local disabledRefresh
    local previewRefresh
    local function ApplyGameplayUI()
        ApplyGameplay()
        if disabledRefresh then disabledRefresh() end
        if previewRefresh then previewRefresh() end
    end

    local anchorValues = {
        { value = "none", text = "None" },
        { value = "player", text = "Player" },
        { value = "target", text = "Target" },
        { value = "focus", text = "Focus" },
    }
    local frameAnchors = {
        { value = "TOPLEFT", text = "TOPLEFT" },
        { value = "TOP", text = "TOP" },
        { value = "TOPRIGHT", text = "TOPRIGHT" },
        { value = "LEFT", text = "LEFT" },
        { value = "CENTER", text = "CENTER" },
        { value = "RIGHT", text = "RIGHT" },
        { value = "BOTTOMLEFT", text = "BOTTOMLEFT" },
        { value = "BOTTOM", text = "BOTTOM" },
        { value = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
    }

    local function PlayerSpecID()
        if ns and type(ns.MSUF_GetPlayerSpecID) == "function" then
            local ok, value = pcall(ns.MSUF_GetPlayerSpecID)
            if ok then return value end
        end
        if GetSpecialization and GetSpecializationInfo then
            local spec = GetSpecialization()
            if spec then
                local id = GetSpecializationInfo(spec)
                return id
            end
        end
        return nil
    end

    local function CurrentMeleeSpellID()
        local g = Gameplay()
        local id = 0
        if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
            local specID = PlayerSpecID()
            if specID then id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0 end
        end
        if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
            local _, class = UnitClass("player")
            if class then id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0 end
        end
        if id <= 0 then id = tonumber(g.nameplateMeleeSpellID) or 0 end
        return id
    end

    local function SpellName(id)
        id = tonumber(id) or 0
        if id <= 0 then return nil end
        if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local info = C_Spell.GetSpellInfo(id)
            if type(info) == "table" and info.name then return info.name end
        end
        if GetSpellInfo then
            local name = GetSpellInfo(id)
            return name
        end
        return nil
    end

    local function SpellIDFromInput(value)
        local text = tostring(value or ""):match("^%s*(.-)%s*$")
        local asNumber = tonumber(text)
        if asNumber then return floor(asNumber + 0.5) end
        if text ~= "" and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
            local ok, info = pcall(C_Spell.GetSpellInfo, text)
            if not ok then info = nil end
            if type(info) == "table" and info.spellID then return tonumber(info.spellID) or 0 end
        end
        if text ~= "" and GetSpellInfo then
            local _, _, _, _, _, _, spellID = GetSpellInfo(text)
            return tonumber(spellID) or 0
        end
        return 0
    end

    local function SeedMeleeClass()
        local g = Gameplay()
        if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
        if UnitClass then
            local _, class = UnitClass("player")
            if class and (tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0) <= 0 then
                g.nameplateMeleeSpellIDByClass[class] = CurrentMeleeSpellID()
            end
        end
    end

    local function SeedMeleeSpec()
        local g = Gameplay()
        if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
        local specID = PlayerSpecID()
        if specID and (tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0) <= 0 then
            g.nameplateMeleeSpellIDBySpec[specID] = CurrentMeleeSpellID()
        end
    end

    local function SetMeleeSpellID(value)
        local spellID = SpellIDFromInput(value)
        local g = Gameplay()
        if g.meleeSpellPerSpec then
            if type(g.nameplateMeleeSpellIDBySpec) ~= "table" then g.nameplateMeleeSpellIDBySpec = {} end
            local specID = PlayerSpecID()
            if specID then g.nameplateMeleeSpellIDBySpec[specID] = spellID end
        elseif g.meleeSpellPerClass and UnitClass then
            if type(g.nameplateMeleeSpellIDByClass) ~= "table" then g.nameplateMeleeSpellIDByClass = {} end
            local _, class = UnitClass("player")
            if class then g.nameplateMeleeSpellIDByClass[class] = spellID end
        end
        g.nameplateMeleeSpellID = spellID
    end

    local timerControls = {}
    local stateControls = {}
    local totemControls = {}
    local firstDanceControls = {}
    local crossControls = {}
    local meleeControls = {}
    local selectedSpellText
    local noSpellWarn

    local function Add(list, widget)
        list[#list + 1] = widget
        return widget
    end

    local function GameplayContentWidth()
        return min(tonumber(M.formContentMaxWidth) or 980, tonumber(ctx.width) or 900)
    end

    local function GameplayStacked()
        return GameplayContentWidth() < 620
    end

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
        local innerX = 30
        local gap = 34
        local innerW = max(160, cardW - 32)
        local colW = max(120, floor((innerW - gap) * 0.5))
        return innerX, innerX + colW + gap, min(requested or colW, colW), colW
    end

    -- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local compactTimer = GameplayStacked()
    local timer = b:CollapsibleSection("gameplay_timer", "Combat Timer", compactTimer and 570 or 430, true)
    local timerW = timer._msuf2Width or ctx.width or 900
    local timerCardW = SectionCardWidth(timer, 680)
    local timerLeftX, timerRightX, timerColW = SectionColumns(timer, 300)
    local timerEnable
    if compactTimer then
        local timerSliderW = SectionControlWidth(timer, 300, 120)
        W.ControlCardBackdrop(timer, 14, -38, timerCardW, 220)
        W.ControlCardBackdrop(timer, 14, -274, timerCardW, 238)
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", 30, -40, min(230, timerSliderW), Gameplay, "enableCombatTimer", false, ApplyGameplayUI)
        local timerAnchor = DropdownAt(ctx, timer, "Anchor", 30, -84, anchorValues, min(220, timerSliderW), Gameplay, "combatTimerAnchor", "none", ApplyGameplayUI)
        Add(timerControls, timerAnchor)
        Add(timerControls, SliderAt(ctx, timer, "Timer size", 30, -138, 10, 64, 1, timerSliderW, Gameplay, "combatFontSize", 24, ApplyGameplayUI))
        Add(timerControls, ToggleAt(ctx, timer, "Lock position", 30, -192, Gameplay, "lockCombatTimer", false, ApplyGameplayUI))
        Add(timerControls, ToggleAt(ctx, timer, "Click-through (ALT to drag when unlocked)", 30, -224, Gameplay, "combatTimerClickThrough", false, ApplyGameplayUI))
        LabelAt(timer, "Timer position (offset)", 30, -284, 260, "GameFontHighlightSmall", T.colors.muted)
        Add(timerControls, SliderAt(ctx, timer, "X offset", 30, -316, -800, 800, 1, timerSliderW, Gameplay, "combatOffsetX", 0, ApplyGameplayUI))
        Add(timerControls, SliderAt(ctx, timer, "Y offset", 30, -386, -800, 800, 1, timerSliderW, Gameplay, "combatOffsetY", -200, ApplyGameplayUI))
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -492, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        W.ControlCardBackdrop(timer, 14, -38, timerCardW, 126)
        W.ControlCardBackdrop(timer, 14, -178, timerCardW, 150)
        timerEnable = SwitchAt(ctx, timer, "Combat Timer", timerLeftX, -40, min(230, timerColW), Gameplay, "enableCombatTimer", false, ApplyGameplayUI)
        local timerAnchor = DropdownAt(ctx, timer, "Anchor", timerRightX, -40, anchorValues, min(220, timerColW), Gameplay, "combatTimerAnchor", "none", ApplyGameplayUI)
        Add(timerControls, timerAnchor)
        Add(timerControls, SliderAt(ctx, timer, "Timer size", timerLeftX, -94, 10, 64, 1, min(270, timerColW), Gameplay, "combatFontSize", 24, ApplyGameplayUI))
        Add(timerControls, ToggleAt(ctx, timer, "Lock position", timerRightX, -100, Gameplay, "lockCombatTimer", false, ApplyGameplayUI))
        Add(timerControls, ToggleAt(ctx, timer, "Click-through (ALT to drag when unlocked)", timerRightX, -132, Gameplay, "combatTimerClickThrough", false, ApplyGameplayUI))
        LabelAt(timer, "Timer position (offset)", 30, -186, 260, "GameFontHighlightSmall", T.colors.muted)
        Add(timerControls, SliderAt(ctx, timer, "X offset", timerLeftX, -216, -800, 800, 1, timerColW, Gameplay, "combatOffsetX", 0, ApplyGameplayUI))
        Add(timerControls, SliderAt(ctx, timer, "Y offset", timerRightX, -216, -800, 800, 1, timerColW, Gameplay, "combatOffsetY", -200, ApplyGameplayUI))
        LabelAt(timer, "Colors are configured in Colors > Gameplay.", 30, -312, min(520, timerW - 60), "GameFontDisableSmall", T.colors.muted)
    end

    local stateStacked = GameplayStacked()
    local state = b:CollapsibleSection("gameplay_state", "Combat Enter/Leave", stateStacked and 580 or 340, false)
    local stateW = state._msuf2Width or ctx.width or 900
    local stateCardW = SectionCardWidth(state, 680)
    local stateControlW = SectionControlWidth(state, 260, 120)
    local stateLeftX, stateRightX, stateColW = SectionColumns(state, 260)
    local stateEnable
    local enterInput
    local leaveInput
    if stateStacked then
        W.ControlCardBackdrop(state, 14, -38, stateCardW, 196)
        W.ControlCardBackdrop(state, 14, -250, stateCardW, 282)
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", 30, -40, min(270, stateControlW), Gameplay, "enableCombatStateText", false, ApplyGameplayUI)
        Add(stateControls, ToggleAt(ctx, state, "Lock position", 30, -74, Gameplay, "lockCombatState", false, ApplyGameplayUI))
        enterInput = MoveWidget(W.TextInput(state, "Enter text", stateControlW), state, 30, -120)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", stateControlW), state, 30, -174)
        Add(stateControls, SliderAt(ctx, state, "Text size", 30, -258, 10, 64, 1, stateControlW, Gameplay, "combatStateFontSize", 24, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "Duration (s)", 30, -328, 0.5, 5.0, 0.5, stateControlW, Gameplay, "combatStateDuration", 1.5, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "X offset", 30, -398, -800, 800, 1, stateControlW, Gameplay, "combatStateOffsetX", 0, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "Y offset", 30, -468, -800, 800, 1, stateControlW, Gameplay, "combatStateOffsetY", 80, ApplyGameplayUI))
    else
        W.ControlCardBackdrop(state, 14, -38, stateCardW, 136)
        W.ControlCardBackdrop(state, 14, -144, stateCardW, 154)
        stateEnable = SwitchAt(ctx, state, "Combat Enter/Leave", stateLeftX, -40, min(270, stateColW), Gameplay, "enableCombatStateText", false, ApplyGameplayUI)
        Add(stateControls, ToggleAt(ctx, state, "Lock position", stateRightX, -40, Gameplay, "lockCombatState", false, ApplyGameplayUI))
        enterInput = MoveWidget(W.TextInput(state, "Enter text", min(220, stateColW)), state, stateLeftX, -86)
        leaveInput = MoveWidget(W.TextInput(state, "Leave text", min(220, stateColW)), state, stateRightX, -86)
        Add(stateControls, SliderAt(ctx, state, "Text size", stateLeftX, -152, 10, 64, 1, stateColW, Gameplay, "combatStateFontSize", 24, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "Duration (s)", stateRightX, -152, 0.5, 5.0, 0.5, stateColW, Gameplay, "combatStateDuration", 1.5, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "X offset", stateLeftX, -238, -800, 800, 1, stateColW, Gameplay, "combatStateOffsetX", 0, ApplyGameplayUI))
        Add(stateControls, SliderAt(ctx, state, "Y offset", stateRightX, -238, -800, 800, 1, stateColW, Gameplay, "combatStateOffsetY", 80, ApplyGameplayUI))
    end
    M.BindTextInput(ctx, enterInput,
        function() return Gameplay().combatStateEnterText or "+Combat" end,
        function(v)
            Gameplay().combatStateEnterText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, enterInput)
    M.BindTextInput(ctx, leaveInput,
        function() return Gameplay().combatStateLeaveText or "-Combat" end,
        function(v)
            Gameplay().combatStateLeaveText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, leaveInput)

    local classStacked = GameplayStacked()
    local classSec = b:CollapsibleSection("gameplay_class_specific", "Class-specific toggles", classStacked and 1120 or 736, false)
    local classW = classSec._msuf2Width or ctx.width or 900
    local classCardW = SectionCardWidth(classSec, 700)
    local classControlW = SectionControlWidth(classSec, 300, 120)
    local classLeftX, classRightX, classColW = SectionColumns(classSec, 300)
    local classToken
    if UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end
    local hasTotemFrame = classToken == "SHAMAN" or classToken == "MONK"
    local isRogue = classToken == "ROGUE"
    local totemEnable
    local previewBtn
    local resetTotemBtn
    local firstDanceEnable
    if classStacked then
        W.ControlCardBackdrop(classSec, 14, -38, classCardW, 520)
        W.ControlCardBackdrop(classSec, 14, -590, classCardW, 430)
        LabelAt(classSec, hasTotemFrame and "Totem / Statue frame" or "(Totem/Statue frame is Shaman/Monk-only)", 30, -38, min(360, classW - 60), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", 30, -60, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", 30, -92, min(300, classControlW), Gameplay, "enablePlayerTotems", false, ApplyGameplayUI)
        previewBtn = T.Button(classSec, "Preview", min(120, classControlW), 22)
        previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 30, -128)
        resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", min(190, classControlW), 22)
        resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 30, -160)
        LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", 30, -196, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        Add(totemControls, SliderAt(ctx, classSec, "Icon size", 30, -238, 8, 64, 1, classControlW, Gameplay, "playerTotemsIconSize", 24, ApplyGameplayUI))
        Add(totemControls, SliderAt(ctx, classSec, "X offset", 30, -308, -200, 200, 1, classControlW, Gameplay, "playerTotemsOffsetX", 0, ApplyGameplayUI))
        Add(totemControls, SliderAt(ctx, classSec, "Y offset", 30, -378, -200, 200, 1, classControlW, Gameplay, "playerTotemsOffsetY", -6, ApplyGameplayUI))
        Add(totemControls, DropdownAt(ctx, classSec, "From", 30, -448, frameAnchors, min(220, classControlW), Gameplay, "playerTotemsAnchorFrom", "TOPLEFT", ApplyGameplayUI))
        Add(totemControls, DropdownAt(ctx, classSec, "To", 30, -502, frameAnchors, min(220, classControlW), Gameplay, "playerTotemsAnchorTo", "BOTTOMLEFT", ApplyGameplayUI))

        DividerAt(classSec, -570)
        LabelAt(classSec, "Rogue: First Dance tracker", 30, -596, min(360, classW - 60), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Optional helper. Shows a 6s timer after leaving combat.", 30, -618, min(520, classW - 60), "GameFontDisableSmall", T.colors.muted)
        firstDanceEnable = SwitchAt(ctx, classSec, "First Dance tracker", 30, -652, min(340, classControlW), Gameplay, "enableFirstDanceTimer", false, ApplyGameplayUI)
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Lock position", 30, -686, Gameplay, "lockFirstDance", false, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Click-through (ALT to drag when unlocked)", 30, -720, Gameplay, "firstDanceClickThrough", false, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Show as icon with cooldown swipe", 30, -754, Gameplay, "firstDanceShowIcon", true, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Keep visible when ready (hide on combat enter)", 30, -788, Gameplay, "firstDanceShowReady", false, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "Icon size", 30, -836, 16, 96, 1, classControlW, Gameplay, "firstDanceIconSize", 40, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "X offset", 30, -906, -800, 800, 1, classControlW, Gameplay, "firstDanceOffsetX", 0, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "Y offset", 30, -976, -800, 800, 1, classControlW, Gameplay, "firstDanceOffsetY", 80, ApplyGameplayUI))
    else
        W.ControlCardBackdrop(classSec, 14, -38, classCardW, 276)
        W.ControlCardBackdrop(classSec, 14, -348, classCardW, 318)
        LabelAt(classSec, hasTotemFrame and "Totem / Statue frame" or "(Totem/Statue frame is Shaman/Monk-only)", classLeftX, -38, min(360, classColW), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", classLeftX, -60, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        totemEnable = SwitchAt(ctx, classSec, "Blizzard TotemFrame", classLeftX, -92, classColW, Gameplay, "enablePlayerTotems", false, ApplyGameplayUI)
        previewBtn = T.Button(classSec, "Preview", 120, 22)
        previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", classLeftX, -128)
        resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", 190, 22)
        resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", classLeftX + 132, -128)
        LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", classLeftX, -158, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        Add(totemControls, SliderAt(ctx, classSec, "Icon size", classRightX, -84, 8, 64, 1, classColW, Gameplay, "playerTotemsIconSize", 24, ApplyGameplayUI))
        Add(totemControls, SliderAt(ctx, classSec, "X offset", classRightX, -168, -200, 200, 1, classColW, Gameplay, "playerTotemsOffsetX", 0, ApplyGameplayUI))
        Add(totemControls, SliderAt(ctx, classSec, "Y offset", classRightX, -252, -200, 200, 1, classColW, Gameplay, "playerTotemsOffsetY", -6, ApplyGameplayUI))
        Add(totemControls, DropdownAt(ctx, classSec, "From", classLeftX, -202, frameAnchors, min(180, classColW), Gameplay, "playerTotemsAnchorFrom", "TOPLEFT", ApplyGameplayUI))
        Add(totemControls, DropdownAt(ctx, classSec, "To", classLeftX + min(196, classColW * 0.55), -202, frameAnchors, min(180, classColW), Gameplay, "playerTotemsAnchorTo", "BOTTOMLEFT", ApplyGameplayUI))

        DividerAt(classSec, -330)
        LabelAt(classSec, "Rogue: First Dance tracker", classLeftX, -354, min(360, classColW), "GameFontNormalSmall", T.colors.text)
        LabelAt(classSec, "Optional helper. Shows a 6s timer after leaving combat.", classLeftX, -376, min(520, classCardW - 32), "GameFontDisableSmall", T.colors.muted)
        firstDanceEnable = SwitchAt(ctx, classSec, "First Dance tracker", classLeftX, -410, classColW, Gameplay, "enableFirstDanceTimer", false, ApplyGameplayUI)
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Lock position", classRightX, -410, Gameplay, "lockFirstDance", false, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Click-through (ALT to drag when unlocked)", classLeftX, -444, Gameplay, "firstDanceClickThrough", false, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Show as icon with cooldown swipe", classLeftX, -478, Gameplay, "firstDanceShowIcon", true, ApplyGameplayUI))
        Add(firstDanceControls, ToggleAt(ctx, classSec, "Keep visible when ready (hide on combat enter)", classRightX, -444, Gameplay, "firstDanceShowReady", false, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "Icon size", classLeftX, -524, 16, 96, 1, classColW, Gameplay, "firstDanceIconSize", 40, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "X offset", classRightX, -524, -800, 800, 1, classColW, Gameplay, "firstDanceOffsetX", 0, ApplyGameplayUI))
        Add(firstDanceControls, SliderAt(ctx, classSec, "Y offset", classLeftX, -608, -800, 800, 1, classColW, Gameplay, "firstDanceOffsetY", 80, ApplyGameplayUI))
    end
    previewBtn:SetScript("OnClick", function()
        if ns and type(ns.MSUF_PlayerTotems_TogglePreview) == "function" then
            pcall(ns.MSUF_PlayerTotems_TogglePreview)
        end
    end)
    resetTotemBtn:SetScript("OnClick", function()
        local g = Gameplay()
        g.playerTotemsIconSize = 24
        g.playerTotemsOffsetX = 0
        g.playerTotemsOffsetY = -6
        g.playerTotemsAnchorFrom = "TOPLEFT"
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
        ApplyGameplayUI()
        if M.Refresh then M.Refresh(ctx) end
    end)
    Add(totemControls, totemEnable)
    Add(totemControls, previewBtn)
    Add(totemControls, resetTotemBtn)

    local crossStacked = GameplayStacked()
    local cross = b:CollapsibleSection("gameplay_crosshair", "Combat Crosshair", crossStacked and 800 or 588, false)
    local crossW = cross._msuf2Width or ctx.width or 900
    local crossCardW = SectionCardWidth(cross, 700)
    local crossControlW = SectionControlWidth(cross, 300, 120)
    local crossLeftX, crossRightX, crossColW = SectionColumns(cross, 300)
    local crossEnable
    local rangeToggle
    local spellInput
    local classSpellToggle
    local specSpellToggle
    local spellInputW
    local preview
    if crossStacked then
        spellInputW = min(260, crossControlW)
        W.ControlCardBackdrop(cross, 14, -38, crossCardW, 332)
        W.ControlCardBackdrop(cross, 14, -390, crossCardW, 346)
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", 30, -40, min(390, crossControlW), Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI)
        rangeToggle = ToggleAt(ctx, cross, "Crosshair: color by melee range to target (green=in range, red=out)", 30, -74, Gameplay, "enableCombatCrosshairMeleeRangeColor", false, ApplyGameplayUI)
        LabelAt(cross, "Uses the spell selected below.", 54, -104, min(420, crossW - 82), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", 54, -126, min(520, crossW - 82), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, 30, -178)
        selectedSpellText = LabelAt(cross, "", 30, -242, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", 30, -264, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
        classSpellToggle = ToggleAt(ctx, cross, "Store per class", 30, -298, Gameplay, "meleeSpellPerClass", false, function()
            if Gameplay().meleeSpellPerClass then SeedMeleeClass() end
            ApplyGameplayUI()
        end)
        specSpellToggle = ToggleAt(ctx, cross, "Store per spec", 30, -332, Gameplay, "meleeSpellPerSpec", false, function()
            if Gameplay().meleeSpellPerSpec then SeedMeleeSpec() end
            ApplyGameplayUI()
        end)
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", 30, -410)
        preview:SetSize(min(260, max(160, crossCardW - 28)), 120)
        Add(crossControls, SliderAt(ctx, cross, "Crosshair thickness", 30, -560, 1, 12, 1, crossControlW, Gameplay, "crosshairThickness", 3, ApplyGameplayUI))
        Add(crossControls, SliderAt(ctx, cross, "Crosshair size", 30, -630, 20, 120, 2, crossControlW, Gameplay, "crosshairSize", 40, ApplyGameplayUI))
        LabelAt(cross, "Colors are configured in Colors > Gameplay.", 30, -734, min(360, crossW - 60), "GameFontDisableSmall", T.colors.muted)
    else
        spellInputW = min(260, crossColW)
        W.ControlCardBackdrop(cross, 14, -38, crossCardW, 242)
        W.ControlCardBackdrop(cross, 14, -312, crossCardW, 214)
        crossEnable = SwitchAt(ctx, cross, "Combat Crosshair", crossLeftX, -40, min(390, crossColW), Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI)
        rangeToggle = ToggleAt(ctx, cross, "Crosshair: color by melee range to target (green=in range, red=out)", crossLeftX, -74, Gameplay, "enableCombatCrosshairMeleeRangeColor", false, ApplyGameplayUI)
        LabelAt(cross, "Uses the spell selected below.", crossLeftX + 24, -104, min(420, crossColW), "GameFontDisableSmall", T.colors.muted)
        noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", crossLeftX + 24, -126, min(520, crossCardW - 56), "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
        spellInput = MoveWidget(W.TextInput(cross, "Choose spell ID or name", spellInputW), cross, crossLeftX, -170)
        selectedSpellText = LabelAt(cross, "", crossRightX, -192, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        LabelAt(cross, "Used by: Crosshair melee-range color.", crossRightX, -214, min(360, crossColW), "GameFontDisableSmall", T.colors.muted)
        classSpellToggle = ToggleAt(ctx, cross, "Store per class", crossRightX, -244, Gameplay, "meleeSpellPerClass", false, function()
            if Gameplay().meleeSpellPerClass then SeedMeleeClass() end
            ApplyGameplayUI()
        end)
        specSpellToggle = ToggleAt(ctx, cross, "Store per spec", crossRightX + min(180, crossColW * 0.52), -244, Gameplay, "meleeSpellPerSpec", false, function()
            if Gameplay().meleeSpellPerSpec then SeedMeleeSpec() end
            ApplyGameplayUI()
        end)
        preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
        preview:SetPoint("TOPLEFT", cross, "TOPLEFT", crossLeftX, -312)
        preview:SetSize(min(260, crossColW), 120)
        Add(crossControls, SliderAt(ctx, cross, "Crosshair thickness", crossRightX, -334, 1, 12, 1, crossColW, Gameplay, "crosshairThickness", 3, ApplyGameplayUI))
        Add(crossControls, SliderAt(ctx, cross, "Crosshair size", crossRightX, -418, 20, 120, 2, crossColW, Gameplay, "crosshairSize", 40, ApplyGameplayUI))
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
            if fill then fill:SetVertexColor(0.025, 0.034, 0.070, 0.98) end
            if edge then edge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
        end
        if spellInput.SetBackdropColor then spellInput:SetBackdropColor(0.025, 0.034, 0.070, 0.98) end
        if spellInput.SetBackdropBorderColor then spellInput:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
        spellInput:HookScript("OnEditFocusGained", function(self)
            if self._msuf2SpellInputEdge then self._msuf2SpellInputEdge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.95) end
        end)
        spellInput:HookScript("OnEditFocusLost", function(self)
            if self._msuf2SpellInputEdge then self._msuf2SpellInputEdge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
        end)
        spellInput:HookScript("OnShow", function(self)
            if self._msuf2SpellInputFill then self._msuf2SpellInputFill:SetVertexColor(0.025, 0.034, 0.070, 0.98) end
            if self._msuf2SpellInputEdge then self._msuf2SpellInputEdge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.58) end
        end)
    end
    M.BindTextInput(ctx, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v)
            SetMeleeSpellID(v)
            ApplyGameplayUI()
        end, true)
    Add(crossControls, rangeToggle)
    Add(crossControls, spellInput)
    Add(crossControls, classSpellToggle)
    Add(crossControls, specSpellToggle)
    Add(meleeControls, spellInput)
    Add(meleeControls, classSpellToggle)
    Add(meleeControls, specSpellToggle)

    local bars = {}
    for i = 1, 4 do
        bars[i] = preview:CreateTexture(nil, "ARTWORK")
        bars[i]:SetColorTexture(1, 0, 0, 1)
    end

    previewRefresh = function()
        local g = Gameplay()
        local id = CurrentMeleeSpellID()
        local name = SpellName(id)
        if selectedSpellText then
            selectedSpellText:SetText((id > 0 and M.Format(M.Tr("Selected: %s (%d)"), name or M.Tr("Spell"), id)) or M.Tr("Selected: none"))
        end
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

    disabledRefresh = function()
        local g = Gameplay()
        local timerOn = g.enableCombatTimer == true
        for i = 1, #timerControls do SetControlEnabled(timerControls[i], timerOn) end
        SetControlEnabled(timerEnable, true)

        local stateOn = g.enableCombatStateText == true
        for i = 1, #stateControls do SetControlEnabled(stateControls[i], stateOn) end
        SetControlEnabled(stateEnable, true)

        local totemsOn = hasTotemFrame and g.enablePlayerTotems == true
        SetControlEnabled(totemEnable, hasTotemFrame)
        for i = 1, #totemControls do
            local control = totemControls[i]
            if control ~= totemEnable then SetControlEnabled(control, hasTotemFrame and (totemsOn or control == previewBtn or control == resetTotemBtn)) end
        end

        local firstOn = isRogue and g.enableFirstDanceTimer == true
        SetControlEnabled(firstDanceEnable, isRogue)
        for i = 1, #firstDanceControls do SetControlEnabled(firstDanceControls[i], firstOn) end

        local crossOn = g.enableCombatCrosshair == true
        SetControlEnabled(crossEnable, true)
        for i = 1, #crossControls do SetControlEnabled(crossControls[i], crossOn) end
        local meleeOn = crossOn and g.enableCombatCrosshairMeleeRangeColor == true
        for i = 1, #meleeControls do SetControlEnabled(meleeControls[i], meleeOn) end
    end

    M.AddRefresher(ctx, function()
        disabledRefresh()
        previewRefresh()
    end)
    disabledRefresh()
    previewRefresh()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gameplay", { title = "MSUF Gameplay", build = BuildGameplay, version = 3 })
