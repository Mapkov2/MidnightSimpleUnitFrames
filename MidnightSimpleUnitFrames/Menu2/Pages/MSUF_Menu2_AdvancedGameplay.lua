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
    local head = b:Header("Midnight Simple Unit Frames - Gameplay", "Here are several gameplay enhancement options you can toggle on or off.", 74)

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

    -- Old order: Combat Timer, Combat Enter/Leave, Class-specific toggles, Combat Crosshair.
    local timer = b:CollapsibleSection("gameplay_timer", "Combat Timer", 430, true)
    local timerEnable = ToggleAt(ctx, timer, "Enable in-combat timer", 14, -40, Gameplay, "enableCombatTimer", false, ApplyGameplayUI)
    local timerAnchor = DropdownAt(ctx, timer, "Anchor", 320, -40, anchorValues, 160, Gameplay, "combatTimerAnchor", "none", ApplyGameplayUI)
    Add(timerControls, timerAnchor)
    Add(timerControls, SliderAt(ctx, timer, "Timer size", 14, -94, 10, 64, 1, 270, Gameplay, "combatFontSize", 24, ApplyGameplayUI))
    Add(timerControls, ToggleAt(ctx, timer, "Lock position", 360, -100, Gameplay, "lockCombatTimer", false, ApplyGameplayUI))
    Add(timerControls, ToggleAt(ctx, timer, "Click-through (ALT to drag when unlocked)", 360, -132, Gameplay, "combatTimerClickThrough", false, ApplyGameplayUI))
    LabelAt(timer, "Timer position (offset)", 14, -186, 260, "GameFontHighlightSmall", T.colors.muted)
    Add(timerControls, SliderAt(ctx, timer, "X offset", 14, -216, -800, 800, 1, 300, Gameplay, "combatOffsetX", 0, ApplyGameplayUI))
    Add(timerControls, SliderAt(ctx, timer, "Y offset", 360, -216, -800, 800, 1, 300, Gameplay, "combatOffsetY", -200, ApplyGameplayUI))
    LabelAt(timer, "Colors are configured in Colors > Gameplay.", 14, -312, 520, "GameFontDisableSmall", T.colors.muted)

    local state = b:CollapsibleSection("gameplay_state", "Combat Enter/Leave", 340, false)
    local stateEnable = ToggleAt(ctx, state, "Show combat enter/leave text", 14, -40, Gameplay, "enableCombatStateText", false, ApplyGameplayUI)
    Add(stateControls, ToggleAt(ctx, state, "Lock position", 360, -40, Gameplay, "lockCombatState", false, ApplyGameplayUI))
    local enterInput = MoveWidget(W.TextInput(state, "Enter text", 220), state, 14, -86)
    M.BindTextInput(ctx, enterInput,
        function() return Gameplay().combatStateEnterText or "+Combat" end,
        function(v)
            Gameplay().combatStateEnterText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, enterInput)
    local leaveInput = MoveWidget(W.TextInput(state, "Leave text", 220), state, 300, -86)
    M.BindTextInput(ctx, leaveInput,
        function() return Gameplay().combatStateLeaveText or "-Combat" end,
        function(v)
            Gameplay().combatStateLeaveText = tostring(v or "")
            ApplyGameplayUI()
        end, true)
    Add(stateControls, leaveInput)
    Add(stateControls, SliderAt(ctx, state, "Text size", 14, -152, 10, 64, 1, 250, Gameplay, "combatStateFontSize", 24, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "Duration (s)", 320, -152, 0.5, 5.0, 0.5, 250, Gameplay, "combatStateDuration", 1.5, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "X offset", 14, -238, -800, 800, 1, 250, Gameplay, "combatStateOffsetX", 0, ApplyGameplayUI))
    Add(stateControls, SliderAt(ctx, state, "Y offset", 320, -238, -800, 800, 1, 250, Gameplay, "combatStateOffsetY", 80, ApplyGameplayUI))

    local classSec = b:CollapsibleSection("gameplay_class_specific", "Class-specific toggles", 704, false)
    local classToken
    if UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end
    local hasTotemFrame = classToken == "SHAMAN" or classToken == "MONK"
    local isRogue = classToken == "ROGUE"
    LabelAt(classSec, hasTotemFrame and "Totem / Statue frame" or "(Totem/Statue frame is Shaman/Monk-only)", 14, -38, 360, "GameFontNormalSmall", T.colors.text)
    LabelAt(classSec, "Uses Blizzard TotemFrame; MSUF only re-anchors it out of combat.", 14, -60, 520, "GameFontDisableSmall", T.colors.muted)
    local totemEnable = ToggleAt(ctx, classSec, "Re-anchor Blizzard TotemFrame", 14, -92, Gameplay, "enablePlayerTotems", false, ApplyGameplayUI)
    local previewBtn = T.Button(classSec, "Preview", 120, 22)
    previewBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 14, -128)
    previewBtn:SetScript("OnClick", function()
        if ns and type(ns.MSUF_PlayerTotems_TogglePreview) == "function" then
            pcall(ns.MSUF_PlayerTotems_TogglePreview)
        end
    end)
    local resetTotemBtn = T.Button(classSec, "Reset TotemFrame layout", 190, 22)
    resetTotemBtn:SetPoint("TOPLEFT", classSec, "TOPLEFT", 146, -128)
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
    LabelAt(classSec, "Tip: Move the preview via mousedrag or arrow keys.", 14, -158, 520, "GameFontDisableSmall", T.colors.muted)
    Add(totemControls, totemEnable)
    Add(totemControls, previewBtn)
    Add(totemControls, resetTotemBtn)
    Add(totemControls, SliderAt(ctx, classSec, "Icon size", 390, -84, 8, 64, 1, 250, Gameplay, "playerTotemsIconSize", 24, ApplyGameplayUI))
    Add(totemControls, SliderAt(ctx, classSec, "X offset", 390, -168, -200, 200, 1, 250, Gameplay, "playerTotemsOffsetX", 0, ApplyGameplayUI))
    Add(totemControls, SliderAt(ctx, classSec, "Y offset", 390, -252, -200, 200, 1, 250, Gameplay, "playerTotemsOffsetY", -6, ApplyGameplayUI))
    Add(totemControls, DropdownAt(ctx, classSec, "From", 14, -202, frameAnchors, 180, Gameplay, "playerTotemsAnchorFrom", "TOPLEFT", ApplyGameplayUI))
    Add(totemControls, DropdownAt(ctx, classSec, "To", 210, -202, frameAnchors, 180, Gameplay, "playerTotemsAnchorTo", "BOTTOMLEFT", ApplyGameplayUI))

    DividerAt(classSec, -330)
    LabelAt(classSec, "Rogue: First Dance tracker", 14, -354, 360, "GameFontNormalSmall", T.colors.text)
    LabelAt(classSec, "Optional helper. Shows a 6s timer after leaving combat.", 14, -376, 520, "GameFontDisableSmall", T.colors.muted)
    local firstDanceEnable = ToggleAt(ctx, classSec, "Track 'The First Dance' (6s after leaving combat)", 14, -410, Gameplay, "enableFirstDanceTimer", false, ApplyGameplayUI)
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Lock position", 390, -410, Gameplay, "lockFirstDance", false, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Click-through (ALT to drag when unlocked)", 14, -444, Gameplay, "firstDanceClickThrough", false, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Show as icon with cooldown swipe", 14, -478, Gameplay, "firstDanceShowIcon", true, ApplyGameplayUI))
    Add(firstDanceControls, ToggleAt(ctx, classSec, "Keep visible when ready (hide on combat enter)", 390, -444, Gameplay, "firstDanceShowReady", false, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "Icon size", 14, -524, 16, 96, 1, 250, Gameplay, "firstDanceIconSize", 40, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "X offset", 300, -524, -800, 800, 1, 250, Gameplay, "firstDanceOffsetX", 0, ApplyGameplayUI))
    Add(firstDanceControls, SliderAt(ctx, classSec, "Y offset", 14, -608, -800, 800, 1, 250, Gameplay, "firstDanceOffsetY", 80, ApplyGameplayUI))

    local cross = b:CollapsibleSection("gameplay_crosshair", "Combat Crosshair", 560, false)
    local crossEnable = ToggleAt(ctx, cross, "Show green combat crosshair under player (in combat)", 14, -40, Gameplay, "enableCombatCrosshair", false, ApplyGameplayUI)
    local rangeToggle = ToggleAt(ctx, cross, "Crosshair: color by melee range to target (green=in range, red=out)", 14, -74, Gameplay, "enableCombatCrosshairMeleeRangeColor", false, ApplyGameplayUI)
    LabelAt(cross, "Uses the spell selected below.", 38, -104, 420, "GameFontDisableSmall", T.colors.muted)
    noSpellWarn = LabelAt(cross, "No melee range spell selected - Crosshair will not work.", 38, -126, 520, "GameFontNormalSmall", { 1, 0.55, 0.1, 1 })
    local spellInput = MoveWidget(W.TextInput(cross, "Choose spell (type spell ID or name)", 220), cross, 14, -170)
    M.BindTextInput(ctx, spellInput,
        function()
            local id = CurrentMeleeSpellID()
            return id > 0 and tostring(id) or ""
        end,
        function(v)
            SetMeleeSpellID(v)
            ApplyGameplayUI()
        end, true)
    selectedSpellText = LabelAt(cross, "", 260, -192, 360, "GameFontDisableSmall", T.colors.muted)
    LabelAt(cross, "Used by: Crosshair melee-range color.", 260, -214, 360, "GameFontDisableSmall", T.colors.muted)
    local classSpellToggle = ToggleAt(ctx, cross, "Store per class", 260, -244, Gameplay, "meleeSpellPerClass", false, function()
        if Gameplay().meleeSpellPerClass then SeedMeleeClass() end
        ApplyGameplayUI()
    end)
    local specSpellToggle = ToggleAt(ctx, cross, "Store per spec", 430, -244, Gameplay, "meleeSpellPerSpec", false, function()
        if Gameplay().meleeSpellPerSpec then SeedMeleeSpec() end
        ApplyGameplayUI()
    end)
    Add(crossControls, rangeToggle)
    Add(crossControls, spellInput)
    Add(crossControls, classSpellToggle)
    Add(crossControls, specSpellToggle)
    Add(meleeControls, spellInput)
    Add(meleeControls, classSpellToggle)
    Add(meleeControls, specSpellToggle)

    local preview = T.Panel(cross, nil, { 0, 0, 0, 0.92 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cross, "TOPLEFT", 14, -292)
    preview:SetSize(260, 120)
    local bars = {}
    for i = 1, 4 do
        bars[i] = preview:CreateTexture(nil, "ARTWORK")
        bars[i]:SetColorTexture(1, 0, 0, 1)
    end
    Add(crossControls, SliderAt(ctx, cross, "Crosshair thickness", 300, -314, 1, 12, 1, 260, Gameplay, "crosshairThickness", 3, ApplyGameplayUI))
    Add(crossControls, SliderAt(ctx, cross, "Crosshair size", 300, -398, 20, 120, 2, 260, Gameplay, "crosshairSize", 40, ApplyGameplayUI))
    LabelAt(cross, "Colors are configured in Colors > Gameplay.", 300, -494, 360, "GameFontDisableSmall", T.colors.muted)

    previewRefresh = function()
        local g = Gameplay()
        local id = CurrentMeleeSpellID()
        local name = SpellName(id)
        if selectedSpellText then
            selectedSpellText:SetText((id > 0 and ("Selected: " .. (name or "Spell") .. " (" .. id .. ")")) or "Selected: none")
        end
        if noSpellWarn then noSpellWarn:SetShown((g.enableCombatCrosshairMeleeRangeColor == true) and id <= 0) end
        local size = math.max(20, tonumber(g.crosshairSize) or 40)
        local thick = math.max(1, tonumber(g.crosshairThickness) or 3)
        local centerX, centerY = 130, -60
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

M.RegisterPage("gameplay", { title = "MSUF Gameplay", build = BuildGameplay, version = 2 })
